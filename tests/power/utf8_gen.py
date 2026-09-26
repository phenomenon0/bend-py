#!/usr/bin/env python3
# The oracle for utf8.bend: prints the whole fixture. The bytes are rebuilt
# from the same slot rule as demos/monoids/utf8_gen.py (Threefry2x32-20 from the
# Random123 paper, held to its known-answer vectors), and every verdict is
# CPython's: validity and the scalar count from bytes.decode("utf-8"), the
# first bad byte read off its UnicodeDecodeError. The state map comes from a
# reference DFA, cross-checked against the decoder's verdict.
import sys

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


for k, c, want in [
    ((0, 0), (0, 0), (0x6B200159, 0x99BA4EFE)),
    ((M, M), (M, M), (0x1CB996FC, 0xBB002BE7)),
    ((0x13198A2E, 0x03707344), (0x243F6A88, 0x85A308D3), (0xC4923A9C, 0x483DF7A0)),
]:
    assert block(*k, *c) == want


def enc(cp):
    b = chr(cp).encode("utf-8", "surrogatepass")
    return b


def asc(r, sh):
    return bytes([0x30 + ((r >> sh) & 63)])


def cp3(r):
    c = (r >> 3) & 0xFFFF
    c = c + 0x800 if c < 0x800 else c
    return c - 0x800 if 0xD800 <= c < 0xE000 else c


POISON = [
    b"\x80AAA",  # a lone continuation: invalid start byte
    b"\xc0\xafAA",  # an overlong '/': C0 is never a lead
    b"\xed\xa0\x80A",  # U+D800 encoded: ED forbids A0..BF
    b"\xe2\x82AA",  # a euro sign cut short
    b"\xf5AAA",  # past the last plane's lead
    b"\xf4\x90\x80\x80",  # U+110000: F4 forbids 90..BF
    b"\xe0\x80\x80A",  # an overlong NUL: E0 forbids 80..9F
    b"A\xc3AA",  # a two-byte lead with no tail
]


def slot(seed, i, poison):
    if i in poison:
        return POISON[poison[i]]
    r = block(seed, 0, i, 0)[0]
    k = r & 7
    if k < 2:
        return b"".join(asc(r, 3 + 6 * j) for j in range(4))
    if k == 2:
        return enc(0x80 + ((r >> 3) & 0x3FF)) + enc(0x80 + ((r >> 13) & 0x3FF))
    if k == 3:
        return enc(cp3(r)) + asc(r, 19)
    if k == 4:
        return asc(r, 19) + enc(cp3(r))
    if k < 7:
        return enc(0x10000 + ((r >> 3) % 0x100000))
    return enc(0x80 + ((r >> 3) & 0x3FF)) + asc(r, 13) + asc(r, 19)


def corpus(seed, lo, n, poison):
    out = b"".join(slot(seed, i, poison) for i in range((lo + n + 3) // 4))
    assert len(out) == 4 * ((lo + n + 3) // 4)
    return out[lo:lo + n]


# The reference DFA (Unicode 15, table 3-7): 0 ACC, 1-3 need that many tails,
# 4 E0, 5 ED, 6 F0, 7 F4, 8 dead. Only used to cross-check CPython.
def nxt(s, b):
    if s == 0:
        if b < 0x80: return 0
        if 0xC2 <= b < 0xE0: return 1
        if b == 0xE0: return 4
        if b == 0xED: return 5
        if 0xE0 < b < 0xF0: return 2
        if b == 0xF0: return 6
        if 0xF0 < b < 0xF4: return 3
        if b == 0xF4: return 7
        return 8
    lo, hi = {4: (0xA0, 0xC0), 5: (0x80, 0xA0), 6: (0x90, 0xC0), 7: (0x80, 0x90)}.get(s, (0x80, 0xC0))
    if not lo <= b < hi: return 8
    return {1: 0, 2: 1, 3: 2, 4: 1, 5: 1, 6: 2, 7: 2}[s]


def smap(data):
    out = ""
    for s0 in range(8):
        s = s0
        for b in data:
            s = nxt(s, b)
            if s == 8: break
        out += str(s)
    return out


def verdict(data):
    try:
        cps = len(data.decode("utf-8"))
        return "yes", cps, "-"
    except UnicodeDecodeError as e:
        dead = {"invalid start byte": e.start, "invalid continuation byte": e.end,
                "unexpected end of data": len(data)}[e.reason]
        cps = sum(1 for b in data if b & 0xC0 != 0x80)
        return "no", cps, str(dead)


def dfa_dead(data):
    s = 0
    for i, b in enumerate(data):
        s = nxt(s, b)
        if s == 8: return i
    return len(data) if s else None



CASES = [  # name, seed, first byte, n bytes, {slot: poison}
    ("clean", 1, 0, 4096, {}),
    ("cut", 3, 0, 4097, {}),
    ("mid", 3, 1, 4000, {}),
    ("empty", 1, 0, 0, {}),
    ("three", 5, 0, 3, {}),
] + [("poison" + str(k), 9 + k, 0, 5001, {200 + 97 * k: k, 900: (k + 3) % 8})
     for k in range(8)]
FORKS = [0, 3, 8]
DESC = [1, 4, 9]


CORPUS_SRC = r'''# -- the corpus: slot i is four bytes, little end first -------------------------

def asc(+r: U32, s: Nat) -> U32:
  U32.add(48, U32.and(U32.shrn(r, s), 63))

def tail(+c: U32, s: Nat) -> U32:
  U32.or(128, U32.and(U32.shrn(c, s), 63))

def enc2(+c: U32) -> U32:
  U32.or(U32.or(192, U32.shrn(c, 6n)), U32.shln(tail(c, 0n), 8n))

def enc3(+c: U32) -> U32:
  U32.or(U32.or(224, U32.shrn(c, 12n)),
    U32.or(U32.shln(tail(c, 6n), 8n), U32.shln(tail(c, 0n), 16n)))

def enc4(+c: U32) -> U32:
  U32.or(U32.or(240, U32.shrn(c, 18n)), U32.or(U32.shln(tail(c, 12n), 8n),
    U32.or(U32.shln(tail(c, 6n), 16n), U32.shln(tail(c, 0n), 24n))))

# a 3-byte scalar off 16 random bits: lifted past the overlong range, and a
# surrogate folded down into D000..D7FF, so ED still gets exercised
def cp3.lo(c: Bool, +x: U32) -> U32:
  match c:
    case True{}:
      U32.add(x, 2048)
    case False{}:
      x

def cp3.sur(c: Bool, +x: U32) -> U32:
  match c:
    case True{}:
      U32.sub(x, 2048)
    case False{}:
      x

def cp3(+r: U32) -> U32:
  +x = U32.and(U32.shrn(r, 3n), 65535)
  +y = cp3.lo(U32.is_lt(x, 2048), x)
  cp3.sur(Bool.and(U32.is_ge(y, 55296), U32.is_lt(y, 57344)), y)

def two(+r: U32) -> U32:
  enc2(U32.add(128, U32.and(U32.shrn(r, 3n), 1023)))

def gen.k(k: U32, +r: U32) -> U32:
  match k:
    case 2:
      U32.or(two(r), U32.shln(enc2(U32.add(128, U32.and(U32.shrn(r, 13n), 1023))), 16n))
    case 3:
      U32.or(enc3(cp3(r)), U32.shln(asc(r, 19n), 24n))
    case 4:
      U32.or(asc(r, 19n), U32.shln(enc3(cp3(r)), 8n))
    case 5:
      enc4(U32.add(65536, U32.mod(U32.shrn(r, 3n), 1048576)))
    case 6:
      enc4(U32.add(65536, U32.mod(U32.shrn(r, 3n), 1048576)))
    case 7:
      U32.or(two(r), U32.or(U32.shln(asc(r, 13n), 16n), U32.shln(asc(r, 19n), 24n)))
    case _:
      U32.or(U32.or(asc(r, 3n), U32.shln(asc(r, 9n), 8n)),
        U32.or(U32.shln(asc(r, 15n), 16n), U32.shln(asc(r, 21n), 24n)))

def gen(+seed: U32, +i: U32) -> U32:
  +r = Rng.u32(seed, 0, i)
  gen.k(U32.and(r, 7), r)

# the eight injuries, one per rule of table 3-7 that a real decoder must enforce
def poison(t: U32) -> U32:
  match t:
    case 0:
      1094795648 # 80 'A' 'A' 'A'   a lone tail
    case 1:
      1094823872 # C0 AF 'A' 'A'    an overlong '/'
    case 2:
      1098948845 # ED A0 80 'A'     U+D800
    case 3:
      1094812386 # E2 82 'A' 'A'    a euro sign cut short
    case 4:
      1094795765 # F5 'A' 'A' 'A'   past the last plane's lead
    case 5:
      2155909364 # F4 90 80 80      U+110000
    case 6:
      1098940640 # E0 80 80 'A'     an overlong NUL
    case _:
      1094828865 # 'A' C3 'A' 'A'   a lead with no tail

# Where: slot k1 carries injury t1, slot k2 injury t2 (4294967295: none).
type Where is Data:
  Where{seed: U32, k1: U32, t1: U32, k2: U32, t2: U32}

def slot.2(c: Bool, t2: U32, +seed: U32, +i: U32) -> U32:
  match c:
    case True{}:
      poison(t2)
    case False{}:
      gen(seed, i)

def slot.1(c: Bool, t1: U32, +k2: U32, t2: U32, +seed: U32, +i: U32) -> U32:
  match c:
    case True{}:
      poison(t1)
    case False{}:
      slot.2(U32.is_eq(i, k2), t2, seed, i)

def slot(+seed: U32, +k1: U32, +t1: U32, +k2: U32, +t2: U32, +i: U32) -> U32:
  slot.1(U32.is_eq(i, k1), t1, k2, t2, seed, i)

def byte(+seed: U32, +k1: U32, +t1: U32, +k2: U32, +t2: U32, +p: U32) -> U32:
  U32.and(U32.shrn(slot(seed, k1, t1, k2, t2, U32.shrn(p, 2n)),
    U32.to_nat(U32.shln(U32.and(p, 3), 3n))), 255)

'''


def packed(m):
    return sum(int(c) << (4 * s) for s, c in enumerate(m))


def rows():
    out = []
    for name, seed, lo, n, poison in CASES:
        data = corpus(seed, lo, n, poison) if n else b""
        ok, cps, dead = verdict(data)
        m = smap(data) if n else "01234567"
        assert (m[0] == "0") == (ok == "yes")
        bad = 4294967295 if dead == "-" else int(dead)
        for _ in FORKS:
            out.append("%s %d %d" % (name, packed(m), cps))
        for _ in DESC:
            out.append("%s bad %d" % (name, bad))
    return out


def where(poison):
    ks = sorted(poison.items())
    k1, t1 = ks[0] if ks else (4294967295, 0)
    k2, t2 = ks[1] if len(ks) > 1 else (4294967295, 0)
    return k1, t1, k2, t2


BEND = r'''# Utf8 against CPython's decoder, over a real Bytes buffer: the corpus of
# demos/monoids/utf8.bend (Threefry slots, eight kinds of injury) is pushed into
# Base's Bytes() byte by byte, then `check` runs at fork depths 0, 3 and 8 and
# `first_bad` descends at 1, 4 and 9 -- every depth the same line. Cases: clean,
# cut three tails short, starting one byte into a scalar, empty, three bytes,
# and one per injury. utf8_gen.py prints this file.
import Base
import ../../power/rng.bend as Rng
import ../../power/utf8.bend as U

''' + CORPUS_SRC + r'''def fill(k: Nat, +seed: U32, +k1: U32, +t1: U32, +k2: U32, +t2: U32, +p: U32,
  b: Bytes()) -> Bytes():
  match k:
    case 0n:
      b
    case 1n++q:
      fill(q, seed, k1, t1, k2, t2, U32.inc(p), Bytes.push(b, byte(seed, k1, t1, k2, t2, p)))

def buf(+seed: U32, +k1: U32, +t1: U32, +k2: U32, +t2: U32, +lo: U32, +n: U32) -> Bytes():
  fill(U32.to_nat(n), seed, k1, t1, k2, t2, lo, "")

def row(name: String, s: U.Sum) -> String:
  match s:
    case U.Sum{m, c}:
      name ++ " " ++ U32.show(m) ++ " " ++ U32.show(c)

def bad(name: String, +p: U32) -> String:
  name ++ " bad " ++ U32.show(p)

def main() -> IO(Unit):
  do IO<Unit>:'''

if __name__ == "__main__":
    print(BEND)
    for name, seed, lo, n, poison in CASES:
        k1, t1, k2, t2 = where(poison)
        mk = "buf(%d, %d, %d, %d, %d, %d, %d)" % (seed, k1, t1, k2, t2, lo, n)
        for d in FORKS:
            print('    IO.print(row("%s", U.check(%s, %dn)))' % (name, mk, d))
        for d in DESC:
            print('    IO.print(bad("%s", U.first_bad(%s, %dn)))' % (name, mk, d))
    for r in rows():
        print("#|" + r)
