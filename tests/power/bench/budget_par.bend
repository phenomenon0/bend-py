# budget, forked: the same 204,800,000 charges as 2^8 ranges of 800,000, each
# range handed its own half of the allowance by lo/hi on the way down and joined
# back on the way up. The checksum is the sequential one because no meter runs
# dry: lo and hi sum to the parent exactly and join sums the remainders back, so
# the accounting does not depend on the schedule. That identity is the row --
# a split that rounded, or a join that saturated early, would print a different
# number and the harness would refuse to time it.
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

def merge.d(p: B.Budget, x: B.Res(B.Budget)) -> B.Res(B.Budget):
  match x:
    case Fail{e}:
      Fail{e}
    case Done{q}:
      Done{B.join(p, q)}

def merge(a: B.Res(B.Budget), x: B.Res(B.Budget)) -> B.Res(B.Budget):
  match a:
    case Fail{e}:
      Fail{e}
    case Done{p}:
      merge.d(p, x)

def par(d: Nat, +lo: U32, +n: U32, +b: B.Budget) -> B.Res(B.Budget):
  match d:
    case 0n:
      go(U32.to_nat(n), lo, Done{b})
    case 1n++p:
      +h = U32.shr(n)
      a x = par(p, lo, h, B.lo(b)) par(p, U32.add(lo, h), h, B.hi(b))
      merge(a, x)

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
  sum(par(8n, 0, 204800000, B.all()))
