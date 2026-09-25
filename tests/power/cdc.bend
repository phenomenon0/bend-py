# FastCDC against a second implementation of the paper (cdc_gen.py prints this
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

def fill(fuel: Nat, +i: U32, b: Bytes()) -> Bytes():
  match fuel:
    case 0n:
      b
    case 1n++p:
      fill(p, U32.inc(i), Bytes.push(b, U32.and(mix(i), 255)))

def buf(n: Nat, seed: U32) -> Bytes():
  fill(n, seed, Bytes.new())

# the same stream with one byte pushed in at p, so every later index shifts
def sbuf(n1: Nat, n2: Nat, +seed: U32, +p: U32) -> Bytes():
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
  do IO<Unit>:
    IO.print(cuts(4096n, 0, 4096, 8))
    IO.print(cuts(8192n, 0, 8192, 8))
    IO.print(cuts(8192n, 7, 8192, 10))
    IO.print(cuts(16384n, 3, 16384, 10))
    IO.print(cuts(2048n, 11, 2048, 9))
    IO.print(cuts(12000n, 5, 12000, 9))
    IO.print(cuts(100n, 0, 100, 10))
    IO.print(cuts(1n, 4, 1, 8))
    IO.print(cuts(256n, 2, 256, 8))
    IO.print(cuts(300n, 9, 300, 8))
    IO.print(cuts(0n, 0, 0, 10))
    IO.print(one(8192n, 0, 0, 8192, 8))
    IO.print(one(8192n, 0, 300, 8192, 8))
    IO.print(one(8192n, 0, 1000, 8192, 8))
    IO.print(one(8192n, 0, 8100, 8192, 8))
    IO.print(one(8192n, 0, 8191, 8192, 8))
    IO.print(one(16384n, 3, 4096, 16384, 10))
    IO.print(one(16384n, 3, 15000, 16384, 10))
    IO.print(resync(8192n, 3n, 8189n, 8192, 0, 0, 3, 8))
    IO.print(resync(8192n, 100n, 8092n, 8192, 0, 0, 100, 8))
    IO.print(resync(8192n, 4000n, 4192n, 8192, 0, 0, 4000, 8))
    IO.print(resync(16384n, 7n, 16377n, 16384, 3, 3, 7, 10))
    IO.print(resync(16384n, 9000n, 7384n, 16384, 3, 3, 9000, 10))
    IO.print(resync(12000n, 1n, 11999n, 12000, 5, 5, 1, 9))
    IO.print(resync(8192n, 3n, 8189n, 8192, 0, 41, 3, 8))
    IO.print(resync(16384n, 7n, 16377n, 16384, 3, 77, 7, 10))
#|262 548 892 972 1244 1567 1638 1917 2186 2502 2936 3227 3526 3844 4096
#|262 548 892 972 1244 1567 1638 1917 2186 2502 2936 3227 3526 3844 4153 4759 4833 5146 5468 5906 6333 6648 6805 7166 7392 7749 8031 8192
#|1048 2518 4038 5498 6641 7742 8192
#|1052 2522 4042 5502 6645 7746 8796 9997 11084 12669 13767 14936 16384
#|612 1233 2025 2048
#|618 1239 2031 2186 2699 3312 3839 4399 5061 5651 6328 6870 7387 8360 8794 9307 9884 10397 10919 11159 11831 12000
#|100
#|1
#|256
#|300
#|
#|262
#|323
#|436
#|92
#|1
#|1406
#|1384
#|28 of 28
#|28 of 28
#|14 of 28
#|13 of 13
#|6 of 13
#|22 of 22
#|1 of 28
#|1 of 13
