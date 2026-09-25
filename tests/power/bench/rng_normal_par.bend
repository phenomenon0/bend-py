# the same 25,600,000 draws in a 2^9 fork tree of 50,000 each. It prints what
# rng_normal prints: a counter RNG's draw does not depend on who computed it,
# and a wrapping sum does not depend on the order it was added in, so the tree
# is free to be any shape.
import Base
import ../../../power/rng.bend as Rng

def q(z: F64) -> U32:
  F64.to_u32(F64.add(F64.mul(F64.add(z, 8.0d), 1000000.0d), 0.5d))

def leaf(i: Nat, +base: U32, +acc: U32) -> U32:
  match i:
    case 0n:
      acc
    case 1n++p:
      leaf(p, base, U32.add(acc, q(Rng.normal(1, 0, U32.add(base, U32.from_nat(p))))))

def tree(d: Nat, +base: U32) -> U32:
  match d:
    case 0n:
      leaf(50000n, base, 0)
    case 1n++p:
      a b = tree(p, base) tree(p, U32.add(base, U32.mul(50000, U32.shln(1, p))))
      U32.add(a, b)

def main() -> U32:
  tree(9n, 0)
