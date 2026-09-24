# 204,800,000 charges through B.fold: what carrying an allowance down a loop
# costs, against C's three integers. Nothing runs dry -- the meters start at max
# and the run spends about 307,000,000 of each -- so the branch fold takes every
# step is the branch C takes, and the row is the threading cost and nothing else.
import Base
import ../../../power/budget.bend as B

def meter.2(is1: Bool) -> B.Meter:
  match is1:
    case True{}:
      B.Out{}
    case False{}:
      B.Calls{}

def meter.1(is0: Bool, +m: U32) -> B.Meter:
  match is0:
    case True{}:
      B.Work{}
    case False{}:
      meter.2(U32.is_eq(m, 1))

def meter.0(+m: U32) -> B.Meter:
  meter.1(U32.is_eq(m, 0), m)

def meter(+at: U32) -> B.Meter:
  meter.0(U32.mod(at, 3))

def go(i: Nat, +at: U32, r: B.Res(B.Budget)) -> B.Res(B.Budget):
  match i:
    case 0n:
      r
    case 1n++p:
      go(p, U32.inc(at), B.fold(r, meter(at), U32.add(U32.and(at, 7), 1)))

def sum.b(b: B.Budget) -> U32:
  match b:
    case B.Budget{w, o, c}:
      U32.add(U32.mul(w, 31), U32.add(U32.mul(o, 7), c))

def sum(r: B.Res(B.Budget)) -> U32:
  match r:
    case Fail{e}:
      0
    case Done{b}:
      sum.b(b)

def main() -> U32:
  sum(go(204800000n, 0, Done{B.all()}))
