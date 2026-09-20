# rng, forked: the 204,800,000 draws as 2^8 ranges of 800,000. A draw is a pure
# function of its counter, so a range is a leaf that owns nothing.
import Base
import ../../../power/rng.bend as Rng

def go(i: Nat, +at: U32, +acc: U32) -> U32:
  match i:
    case 0n:
      acc
    case 1n++p:
      go(p, U32.inc(at), U32.add(acc, Rng.u32(1, 0, at)))

def par(d: Nat, +lo: U32, +n: U32) -> U32:
  match d:
    case 0n:
      go(U32.to_nat(n), lo, 0)
    case 1n++p:
      +h = U32.shr(n)
      a b = par(p, lo, h) par(p, U32.add(lo, h), h)
      U32.add(a, b)

def main() -> U32:
  par(8n, 0, 204800000)
