# The same 12,800,000 updates as 2^8 ranges of 50,000, each range its own
# sketch, merged back on the way up. The digest is the sequential digest and
# the C twin's, because registerwise max is associative, commutative and
# idempotent -- the fork is free, not approximated.
import Base
import ../../../power/sketch.bend as Sk

def go(i: Nat, +at: U32, s: Sk.Sketch) -> Sk.Sketch:
  match i:
    case 0n:
      s
    case 1n++p:
      go(p, U32.inc(at), Sk.hll.add(s, at))

def par(d: Nat, +lo: U32, +n: U32) -> Sk.Res(Sk.Sketch):
  match d:
    case 0n:
      Done{go(U32.to_nat(n), lo, Sk.hll.new(7, 6n))}
    case 1n++p:
      +h = U32.shr(n)
      a b = par(p, lo, h) par(p, U32.add(lo, h), h)
      Sk.merge2(a, b)

def fin(r: Sk.Res(Sk.Sketch)) -> U32:
  match r:
    case Done{s}:
      Sk.digest(s)
    case Fail{e}:
      0

def main() -> U32:
  fin(par(8n, 0, 12800000))
