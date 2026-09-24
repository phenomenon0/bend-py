#!/usr/bin/env python3
# The oracle for cdc.bend: prints the whole fixture. FastCDC is written here
# from the paper, independently of power/cdc.bend, over the same gear table --
# 256 Threefry draws, which this file recomputes from the Random123 paper and
# holds to Random123's own known answers before any row is emitted, exactly as
# rng_gen.py does.
#
# The rows that matter are the last group. A chunker is only worth its cost if
# a byte inserted near the front of a file leaves the boundaries after it
# alone; every other property it has, a fixed-size split has too, and more
# cheaply. So the fixture measures that directly: split a buffer, splice one
# byte into it, split again, and count how many of the two runs' trailing
# boundaries line up once the splice's one-byte shift is undone. A fixed split
# scores zero on that row by construction, and so does a chunker that has quietly
# stopped being content-defined.
M = 0xFFFFFFFF
ROT = [13, 15, 26, 6, 17, 29, 16, 24]


def rotl(x, r):
    return ((x << r) | (x >> (32 - r))) & M


def block(k0, k1, c0, c1):
    ks = [k0, k1, k0 ^ k1 ^ 0x1BD11BDA]
    a, b = (c0 + ks[0]) & M, (c1 + ks[1]) & M
    for r in range(20):
        a = (a + b) & M
        b = rotl(b, ROT[r % 8]) ^ a
        if r % 4 == 3:
            n = r // 4 + 1
            a = (a + ks[n % 3]) & M
            b = (b + ks[(n + 1) % 3] + n) & M
    return a, b


KAT = [  # Random123 kat_vectors: key, counter, output
    ((0, 0), (0, 0), (0x6B200159, 0x99BA4EFE)),
    ((M, M), (M, M), (0x1CB996FC, 0xBB002BE7)),
    ((0x13198A2E, 0x03707344), (0x243F6A88, 0x85A308D3), (0xC4923A9C, 0x483DF7A0)),
]
for k, c, want in KAT:
    assert block(*k, *c) == want, (k, c)

GEAR = [block(2654435761, 0, i, 0)[0] for i in range(256)]


def topmask(k):
    return (((1 << k) - 1) << (32 - k)) & M


def mix(i):  # the buffer's bytes are a function of the index, not of a chained
    h = ((i ^ (i >> 16)) * 2246822507) & M  # state, so splicing one in is just
    h = ((h ^ (h >> 13)) * 3266489909) & M  # a shift of every later index
    return h ^ (h >> 16)


def byte(i):
    return mix(i) & 255


def cut(data, off, end, bits):
    a = 1 << bits
    lo, md, hi = (min(off + a // 4, end), min(off + a, end), min(off + a * 8, end))
    h, i = 0, lo
    for stop, msk in ((md, topmask(bits + 2)), (hi, topmask(bits - 2))):
        while i < stop:
            h = ((h << 1) + GEAR[data[i]]) & M
            i += 1
            if not h & msk:
                return i - off
    return hi - off


def split(data, off, end, bits):
    xs = []
    while off < end:
        off += cut(data, off, end, bits)
        xs.append(off)
    return xs


def tail(xs, ys):  # how many trailing boundaries the two runs agree on
    n = 0
    for x, y in zip(reversed(xs), reversed(ys)):
        if x != y:
            break
        n += 1
    return n


def buf(n, seed):
    return [byte(seed + i) for i in range(n)]


def sbuf(n, seed, p):
    return buf(p, seed) + [255] + buf(n - p, seed + p)


rows, want = [], []


def cuts(n, seed, bits):
    rows.append("cuts(%dn, %d, %d, %d)" % (n, seed, n, bits))
    want.append(" ".join(map(str, split(buf(n, seed), 0, n, bits))))


def one(n, seed, off, bits):
    rows.append("one(%dn, %d, %d, %d, %d)" % (n, seed, off, n, bits))
    want.append(str(cut(buf(n, seed), off, n, bits)))


def resync(n, sa, sb, p, bits):
    rows.append(
        "resync(%dn, %dn, %dn, %d, %d, %d, %d, %d)" % (n, p, n - p, n, sa, sb, p, bits)
    )
    a, b = split(buf(n, sa), 0, n, bits), split(sbuf(n, sb, p), 0, n + 1, bits)
    want.append("%d of %d" % (tail([x + 1 for x in a], b), len(a)))


# 1. where the cuts fall, over four sizes and three target averages. The last
# offset of every run is the end itself: a split covers the range exactly.
for n, seed, bits in [
    (4096, 0, 8),
    (8192, 0, 8),
    (8192, 7, 10),
    (16384, 3, 10),
    (2048, 11, 9),
    (12000, 5, 9),
]:
    cuts(n, seed, bits)

# 2. the sizes the normalizing masks are there to enforce: nothing below the
# minimum, nothing above the maximum, and a range shorter than the minimum is
# one chunk whatever its content says
for n, seed, bits in [(100, 0, 10), (1, 4, 8), (256, 2, 8), (300, 9, 8), (0, 0, 10)]:
    cuts(n, seed, bits)

# 3. a single cut, from offsets that are not the start: the chunker has no
# memory between chunks, so a cut at off must not depend on what came before it
for n, seed, off, bits in [
    (8192, 0, 0, 8),
    (8192, 0, 300, 8),
    (8192, 0, 1000, 8),
    (8192, 0, 8100, 8),
    (8192, 0, 8191, 8),
    (16384, 3, 4096, 10),
    (16384, 3, 15000, 10),
]:
    one(n, seed, off, bits)

# 4. the property the whole primitive exists for: one byte spliced in at p and
# the boundaries after it come back. The rows with two different seeds are the
# control -- unrelated bytes, so nothing lines up and the count is near zero.
for n, sa, sb, p, bits in [
    (8192, 0, 0, 3, 8),
    (8192, 0, 0, 100, 8),
    (8192, 0, 0, 4000, 8),
    (16384, 3, 3, 7, 10),
    (16384, 3, 3, 9000, 10),
    (12000, 5, 5, 1, 9),
    (8192, 0, 41, 3, 8),
    (16384, 3, 77, 7, 10),
]:
    resync(n, sa, sb, p, bits)

print("""# FastCDC against a second implementation of the paper (cdc_gen.py prints this
# file). The first rows are where the cuts land and how big they may be; the
# last group is the only property that distinguishes a content-defined split
# from a fixed one -- splice a byte in near the front, split again, and count
# how many trailing boundaries survive. The rows whose two buffers come from
# different seeds are the control: nothing survives, because nothing matched.
import Base
import ../../power/vec.bend as Vec
import ../../power/bytes.bend as Bytes
import ../../power/rng.bend as Rng
import ../../power/cdc.bend as Cdc

# the buffer's bytes are a function of the index, not of a chained state, so a
# byte spliced in at p is exactly a shift of every index after it
def mix(+i: U32) -> U32:
  +h1 = U32.mul(U32.xor(i, U32.shrn(i, 16n)), 2246822507)
  +h2 = U32.mul(U32.xor(h1, U32.shrn(h1, 13n)), 3266489909)
  U32.xor(h2, U32.shrn(h2, 16n))

def fill(fuel: Nat, +i: U32, b: Bytes.Bytes) -> Bytes.Bytes:
  match fuel:
    case 0n:
      b
    case 1n++p:
      fill(p, U32.inc(i), Bytes.push(b, U32.and(mix(i), 255)))

def buf(n: Nat, seed: U32) -> Bytes.Bytes:
  fill(n, seed, Bytes.new())

# the same stream with one byte pushed in at p, so every later index shifts
def sbuf(n1: Nat, n2: Nat, +seed: U32, +p: U32) -> Bytes.Bytes:
  fill(n2, U32.add(seed, p), Bytes.push(fill(n1, seed, Bytes.new()), 255))

def shows(xs: List<&2, U32>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{x, t}:
      Con{U32.show(x), shows(t)}

def text(r: Cdc.Cdc & List<&2, U32>) -> String:
  (c, xs) = r
  String.join(shows(xs), " ")

def num(r: Cdc.Cdc & U32) -> String:
  (c, n) = r
  U32.show(n)

def cuts(n: Nat, seed: U32, +end: U32, +bits: U32) -> String:
  text(Cdc.split(Cdc.new(buf(n, seed)), 0, end, bits))

def one(n: Nat, seed: U32, +off: U32, +end: U32, +bits: U32) -> String:
  num(Cdc.cut(Cdc.new(buf(n, seed)), off, end, bits))

# -- the surviving boundaries ------------------------------------------------

def bump(xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      []
    case Con{x, t}:
      Con{U32.inc(x), bump(t)}

# walking two lists to a first difference needs a helper that decides and a
# loop that steps, because the decider may not call the loop defined after it:
# the decision becomes the state instead
type Pr is Data:
  PEnd{n: U32}
  PGo{n: U32, xs: List<&2, U32>, ys: List<&2, U32>}

def pr.on(+n: U32, xt: List<&2, U32>, yt: List<&2, U32>, same: Bool) -> Pr:
  match same:
    case True{}:
      PGo{U32.inc(n), xt, yt}
    case False{}:
      PEnd{n}

def pr.mk(n: U32, xs: List<&2, U32>, ys: List<&2, U32>) -> Pr:
  match xs:
    case Nil{}:
      PEnd{n}
    case Con{x, xt}:
      match ys:
        case Nil{}:
          PEnd{n}
        case Con{y, yt}:
          pr.on(n, xt, yt, U32.is_eq(x, y))

def pr.end(s: Pr) -> U32:
  match s:
    case PEnd{n}:
      n
    case PGo{n, xs, ys}:
      n

def pr.go(fuel: Nat, s: Pr) -> U32:
  match fuel:
    case 0n:
      pr.end(s)
    case 1n++p:
      match s:
        case PEnd{n}:
          n
        case PGo{n, xs, ys}:
          pr.go(p, pr.mk(n, xs, ys))

# how many of the two runs' last boundaries line up
def tail(xs: List<&2, U32>, ys: List<&2, U32>) -> U32:
  pr.go(4096n, PGo{0, List.reverse(&2, U32, xs), List.reverse(&2, U32, ys)})

def len.go(xs: List<&2, U32>, +n: U32) -> U32:
  match xs:
    case Nil{}:
      n
    case Con{x, t}:
      len.go(t, U32.inc(n))

def say(+k: U32, xs: List<&2, U32>) -> String:
  U32.show(k) ++ " of " ++ U32.show(len.go(xs, 0))

def rs.b(+xs: List<&2, U32>, r: Cdc.Cdc & List<&2, U32>) -> String:
  (c, ys) = r
  say(tail(bump(xs), ys), xs)

def rs.a(n1: Nat, n2: Nat, +sb: U32, +p: U32, +end: U32, +bits: U32,
         r: Cdc.Cdc & List<&2, U32>) -> String:
  (c, xs) = r
  rs.b(xs, Cdc.split(Cdc.new(sbuf(n1, n2, sb, p)), 0, U32.inc(end), bits))

def resync(n: Nat, n1: Nat, n2: Nat, +end: U32, sa: U32, +sb: U32, +p: U32,
           +bits: U32) -> String:
  rs.a(n1, n2, sb, p, end, bits, Cdc.split(Cdc.new(buf(n, sa)), 0, end, bits))

def main() -> IO(Unit):
  do IO<Unit>:""")
for r in rows:
    print("    IO.print(%s)" % r)
for w in want:
    print("#|" + w)
