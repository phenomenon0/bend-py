# 204,800,000 Threefry draws, summed
import Base
import ../../../power/rng.bend as Rng

def go(i: Nat, +acc: U32) -> U32:
  match i:
    case 0n:
      acc
    case 1n++p:
      go(p, U32.add(acc, Rng.u32(1, 0, U32.from_nat(p))))

def main() -> U32:
  go(204800000n, 0)
