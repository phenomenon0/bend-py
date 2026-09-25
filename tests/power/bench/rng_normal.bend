# 25,600,000 normal draws, quantised to millionths and summed
import Base
import ../../../power/rng.bend as Rng

# the draw as an integer: the twin has to agree bit for bit, and it can only do
# that on a number, not on sixteen digits of a double
def q(z: F64) -> U32:
  F64.to_u32(F64.add(F64.mul(F64.add(z, 8.0d), 1000000.0d), 0.5d))

def go(i: Nat, +acc: U32) -> U32:
  match i:
    case 0n:
      acc
    case 1n++p:
      go(p, U32.add(acc, q(Rng.normal(1, 0, U32.from_nat(p)))))

def main() -> U32:
  go(25600000n, 0)
