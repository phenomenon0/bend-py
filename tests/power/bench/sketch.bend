# 12,800,000 HyperLogLog updates over 64 registers, then the digest. An update
# is one fmix32 and one descent of the bank, which rebuilds the six nodes on
# the path -- against a C twin that does one array store.
import Base
import ../../../power/sketch.bend as Sk

def go(i: Nat, s: Sk.Sketch) -> Sk.Sketch:
  match i:
    case 0n:
      s
    case 1n++p:
      go(p, Sk.hll.add(s, U32.from_nat(p)))

def main() -> U32:
  Sk.digest(go(12800000n, Sk.hll.new(7, 6n)))
