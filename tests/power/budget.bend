# Budget against three CPython ints (budget_gen.py prints this file). The rows
# that carry two numbers, or a "1 "/"0 " prefix, are the laws: both sides of one
# claim in one string, so a Bend that satisfies only one side cannot print them.
import Base
import ../../power/budget.bend as B

def sb(b: B.Budget) -> String:
  match b:
    case B.Budget{w, o, c}:
      U32.show(w) ++ " " ++ U32.show(o) ++ " " ++ U32.show(c)

def err(e: B.Error) -> String:
  match e:
    case B.Dry{m}:
      "dry:" ++ B.show.m(m)

def sr(r: B.Res(B.Budget)) -> String:
  match r:
    case Done{b}:
      sb(b)
    case Fail{e}:
      err(e)

def yn(b: Bool) -> String:
  match b:
    case True{}:
      "1"
    case False{}:
      "0"

def num(n: U32) -> String:
  U32.show(n)

def pair(a: Bool, r: B.Res(B.Budget)) -> String:
  yn(a) ++ " " ++ sr(r)

def got(r: B.Budget & U32) -> String:
  (b, n) = r
  sb(b) ++ " got " ++ U32.show(n)

def sj(r: B.Budget & B.Budget) -> String:
  (a, b) = r
  sb(B.join(a, b))

# law 4 in one row: the accounted total beside the total it has to equal
def acct(+b0: B.Budget, +b: B.Budget, +m: B.Meter) -> String:
  U32.show(U32.add(B.used(b0, b, m), B.left(b, m))) ++ " " ++ U32.show(B.left(b0, m))

def halves(+b: B.Budget) -> String:
  sb(B.lo(b)) ++ " | " ++ sb(B.hi(b)) ++ " -> " ++ sb(B.join(B.lo(b), B.hi(b)))

# the tree the law exists for: lo/hi down, join back, spent counted at the leaf
def tree.mix2(p: B.Budget, +s: U32, x: B.Budget & U32) -> B.Budget & U32:
  (q, t) = x
  (B.join(p, q), U32.add(s, t))

def tree.mix(a: B.Budget & U32, x: B.Budget & U32) -> B.Budget & U32:
  (p, s) = a
  tree.mix2(p, s, x)

def ftree(d: Nat, +i: U32, +b: B.Budget) -> B.Budget & U32:
  match d:
    case 0n:
      B.take(b, B.Work{}, U32.add(U32.mod(i, 3), 1))
    case 1n++p:
      a x = ftree(p, U32.mul(i, 2), B.lo(b)) ftree(p, U32.add(U32.mul(i, 2), 1), B.hi(b))
      tree.mix(a, x)

def tree.show(r: B.Budget & U32) -> String:
  (b, s) = r
  U32.show(s) ++ "+" ++ U32.show(B.left(b, B.Work{}))

def tree(d: Nat, +w: U32) -> String:
  tree.show(ftree(d, 0, B.new(w, 0, 0)))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(sb(B.none()))
    IO.print(sb(B.all()))
    IO.print(sb(B.new(0, 0, 0)))
    IO.print(sb(B.new(1, 0, 0)))
    IO.print(sb(B.new(10, 5, 2)))
    IO.print(sb(B.new(7, 5, 3)))
    IO.print(sb(B.new(4294967295, 4294967295, 4294967295)))
    IO.print(num(B.left(B.new(10, 5, 2), B.Work{})))
    IO.print(num(B.left(B.new(10, 5, 2), B.Out{})))
    IO.print(num(B.left(B.new(10, 5, 2), B.Calls{})))
    IO.print(yn(B.is_empty(B.new(0, 0, 0))))
    IO.print(yn(B.is_empty(B.new(0, 0, 1))))
    IO.print(yn(B.is_empty(B.new(1, 0, 0))))
    IO.print(yn(B.is_empty(B.new(10, 5, 2))))
    IO.print(pair(B.afford(B.new(0, 0, 0), B.Work{}, 0), B.spend(B.new(0, 0, 0), B.Work{}, 0)))
    IO.print(pair(B.afford(B.new(0, 0, 0), B.Work{}, 1), B.spend(B.new(0, 0, 0), B.Work{}, 1)))
    IO.print(pair(B.afford(B.new(0, 0, 0), B.Work{}, 300), B.spend(B.new(0, 0, 0), B.Work{}, 300)))
    IO.print(pair(B.afford(B.new(0, 0, 0), B.Out{}, 0), B.spend(B.new(0, 0, 0), B.Out{}, 0)))
    IO.print(pair(B.afford(B.new(0, 0, 0), B.Out{}, 1), B.spend(B.new(0, 0, 0), B.Out{}, 1)))
    IO.print(pair(B.afford(B.new(0, 0, 0), B.Out{}, 300), B.spend(B.new(0, 0, 0), B.Out{}, 300)))
    IO.print(pair(B.afford(B.new(0, 0, 0), B.Calls{}, 0), B.spend(B.new(0, 0, 0), B.Calls{}, 0)))
    IO.print(pair(B.afford(B.new(0, 0, 0), B.Calls{}, 1), B.spend(B.new(0, 0, 0), B.Calls{}, 1)))
    IO.print(pair(B.afford(B.new(0, 0, 0), B.Calls{}, 300), B.spend(B.new(0, 0, 0), B.Calls{}, 300)))
    IO.print(pair(B.afford(B.new(1, 0, 0), B.Work{}, 1), B.spend(B.new(1, 0, 0), B.Work{}, 1)))
    IO.print(pair(B.afford(B.new(1, 0, 0), B.Work{}, 2), B.spend(B.new(1, 0, 0), B.Work{}, 2)))
    IO.print(pair(B.afford(B.new(1, 0, 0), B.Work{}, 300), B.spend(B.new(1, 0, 0), B.Work{}, 300)))
    IO.print(pair(B.afford(B.new(1, 0, 0), B.Out{}, 0), B.spend(B.new(1, 0, 0), B.Out{}, 0)))
    IO.print(pair(B.afford(B.new(1, 0, 0), B.Out{}, 1), B.spend(B.new(1, 0, 0), B.Out{}, 1)))
    IO.print(pair(B.afford(B.new(1, 0, 0), B.Out{}, 300), B.spend(B.new(1, 0, 0), B.Out{}, 300)))
    IO.print(pair(B.afford(B.new(1, 0, 0), B.Calls{}, 0), B.spend(B.new(1, 0, 0), B.Calls{}, 0)))
    IO.print(pair(B.afford(B.new(1, 0, 0), B.Calls{}, 1), B.spend(B.new(1, 0, 0), B.Calls{}, 1)))
    IO.print(pair(B.afford(B.new(1, 0, 0), B.Calls{}, 300), B.spend(B.new(1, 0, 0), B.Calls{}, 300)))
    IO.print(pair(B.afford(B.new(10, 5, 2), B.Work{}, 10), B.spend(B.new(10, 5, 2), B.Work{}, 10)))
    IO.print(pair(B.afford(B.new(10, 5, 2), B.Work{}, 11), B.spend(B.new(10, 5, 2), B.Work{}, 11)))
    IO.print(pair(B.afford(B.new(10, 5, 2), B.Work{}, 300), B.spend(B.new(10, 5, 2), B.Work{}, 300)))
    IO.print(pair(B.afford(B.new(10, 5, 2), B.Out{}, 5), B.spend(B.new(10, 5, 2), B.Out{}, 5)))
    IO.print(pair(B.afford(B.new(10, 5, 2), B.Out{}, 6), B.spend(B.new(10, 5, 2), B.Out{}, 6)))
    IO.print(pair(B.afford(B.new(10, 5, 2), B.Out{}, 300), B.spend(B.new(10, 5, 2), B.Out{}, 300)))
    IO.print(pair(B.afford(B.new(10, 5, 2), B.Calls{}, 2), B.spend(B.new(10, 5, 2), B.Calls{}, 2)))
    IO.print(pair(B.afford(B.new(10, 5, 2), B.Calls{}, 3), B.spend(B.new(10, 5, 2), B.Calls{}, 3)))
    IO.print(pair(B.afford(B.new(10, 5, 2), B.Calls{}, 300), B.spend(B.new(10, 5, 2), B.Calls{}, 300)))
    IO.print(pair(B.afford(B.new(7, 5, 3), B.Work{}, 7), B.spend(B.new(7, 5, 3), B.Work{}, 7)))
    IO.print(pair(B.afford(B.new(7, 5, 3), B.Work{}, 8), B.spend(B.new(7, 5, 3), B.Work{}, 8)))
    IO.print(pair(B.afford(B.new(7, 5, 3), B.Work{}, 300), B.spend(B.new(7, 5, 3), B.Work{}, 300)))
    IO.print(pair(B.afford(B.new(7, 5, 3), B.Out{}, 5), B.spend(B.new(7, 5, 3), B.Out{}, 5)))
    IO.print(pair(B.afford(B.new(7, 5, 3), B.Out{}, 6), B.spend(B.new(7, 5, 3), B.Out{}, 6)))
    IO.print(pair(B.afford(B.new(7, 5, 3), B.Out{}, 300), B.spend(B.new(7, 5, 3), B.Out{}, 300)))
    IO.print(pair(B.afford(B.new(7, 5, 3), B.Calls{}, 3), B.spend(B.new(7, 5, 3), B.Calls{}, 3)))
    IO.print(pair(B.afford(B.new(7, 5, 3), B.Calls{}, 4), B.spend(B.new(7, 5, 3), B.Calls{}, 4)))
    IO.print(pair(B.afford(B.new(7, 5, 3), B.Calls{}, 300), B.spend(B.new(7, 5, 3), B.Calls{}, 300)))
    IO.print(pair(B.afford(B.new(4294967295, 4294967295, 4294967295), B.Work{}, 4294967295), B.spend(B.new(4294967295, 4294967295, 4294967295), B.Work{}, 4294967295)))
    IO.print(pair(B.afford(B.new(4294967295, 4294967295, 4294967295), B.Work{}, 0), B.spend(B.new(4294967295, 4294967295, 4294967295), B.Work{}, 0)))
    IO.print(pair(B.afford(B.new(4294967295, 4294967295, 4294967295), B.Work{}, 300), B.spend(B.new(4294967295, 4294967295, 4294967295), B.Work{}, 300)))
    IO.print(pair(B.afford(B.new(4294967295, 4294967295, 4294967295), B.Out{}, 4294967295), B.spend(B.new(4294967295, 4294967295, 4294967295), B.Out{}, 4294967295)))
    IO.print(pair(B.afford(B.new(4294967295, 4294967295, 4294967295), B.Out{}, 0), B.spend(B.new(4294967295, 4294967295, 4294967295), B.Out{}, 0)))
    IO.print(pair(B.afford(B.new(4294967295, 4294967295, 4294967295), B.Out{}, 300), B.spend(B.new(4294967295, 4294967295, 4294967295), B.Out{}, 300)))
    IO.print(pair(B.afford(B.new(4294967295, 4294967295, 4294967295), B.Calls{}, 4294967295), B.spend(B.new(4294967295, 4294967295, 4294967295), B.Calls{}, 4294967295)))
    IO.print(pair(B.afford(B.new(4294967295, 4294967295, 4294967295), B.Calls{}, 0), B.spend(B.new(4294967295, 4294967295, 4294967295), B.Calls{}, 0)))
    IO.print(pair(B.afford(B.new(4294967295, 4294967295, 4294967295), B.Calls{}, 300), B.spend(B.new(4294967295, 4294967295, 4294967295), B.Calls{}, 300)))
    IO.print(pair(B.afford(B.new(118, 103, 14), B.Work{}, 118), B.spend(B.new(118, 103, 14), B.Work{}, 118)))
    IO.print(pair(B.afford(B.new(118, 103, 14), B.Work{}, 119), B.spend(B.new(118, 103, 14), B.Work{}, 119)))
    IO.print(pair(B.afford(B.new(118, 103, 14), B.Work{}, 300), B.spend(B.new(118, 103, 14), B.Work{}, 300)))
    IO.print(pair(B.afford(B.new(118, 103, 14), B.Out{}, 103), B.spend(B.new(118, 103, 14), B.Out{}, 103)))
    IO.print(pair(B.afford(B.new(118, 103, 14), B.Out{}, 104), B.spend(B.new(118, 103, 14), B.Out{}, 104)))
    IO.print(pair(B.afford(B.new(118, 103, 14), B.Out{}, 300), B.spend(B.new(118, 103, 14), B.Out{}, 300)))
    IO.print(pair(B.afford(B.new(118, 103, 14), B.Calls{}, 14), B.spend(B.new(118, 103, 14), B.Calls{}, 14)))
    IO.print(pair(B.afford(B.new(118, 103, 14), B.Calls{}, 15), B.spend(B.new(118, 103, 14), B.Calls{}, 15)))
    IO.print(pair(B.afford(B.new(118, 103, 14), B.Calls{}, 300), B.spend(B.new(118, 103, 14), B.Calls{}, 300)))
    IO.print(got(B.take(B.new(0, 0, 0), B.Work{}, 0)))
    IO.print(got(B.take(B.new(0, 0, 0), B.Work{}, 7)))
    IO.print(got(B.take(B.new(0, 0, 0), B.Out{}, 0)))
    IO.print(got(B.take(B.new(0, 0, 0), B.Out{}, 7)))
    IO.print(got(B.take(B.new(0, 0, 0), B.Calls{}, 0)))
    IO.print(got(B.take(B.new(0, 0, 0), B.Calls{}, 7)))
    IO.print(got(B.take(B.new(1, 0, 0), B.Work{}, 0)))
    IO.print(got(B.take(B.new(1, 0, 0), B.Work{}, 8)))
    IO.print(got(B.take(B.new(1, 0, 0), B.Out{}, 0)))
    IO.print(got(B.take(B.new(1, 0, 0), B.Out{}, 7)))
    IO.print(got(B.take(B.new(1, 0, 0), B.Calls{}, 0)))
    IO.print(got(B.take(B.new(1, 0, 0), B.Calls{}, 7)))
    IO.print(got(B.take(B.new(10, 5, 2), B.Work{}, 5)))
    IO.print(got(B.take(B.new(10, 5, 2), B.Work{}, 17)))
    IO.print(got(B.take(B.new(10, 5, 2), B.Out{}, 2)))
    IO.print(got(B.take(B.new(10, 5, 2), B.Out{}, 12)))
    IO.print(got(B.take(B.new(10, 5, 2), B.Calls{}, 1)))
    IO.print(got(B.take(B.new(10, 5, 2), B.Calls{}, 9)))
    IO.print(got(B.take(B.new(7, 5, 3), B.Work{}, 3)))
    IO.print(got(B.take(B.new(7, 5, 3), B.Work{}, 14)))
    IO.print(got(B.take(B.new(7, 5, 3), B.Out{}, 2)))
    IO.print(got(B.take(B.new(7, 5, 3), B.Out{}, 12)))
    IO.print(got(B.take(B.new(7, 5, 3), B.Calls{}, 1)))
    IO.print(got(B.take(B.new(7, 5, 3), B.Calls{}, 10)))
    IO.print(acct(B.new(0, 0, 0), B.new(0, 0, 0), B.Work{}))
    IO.print(num(B.used(B.new(0, 0, 0), B.new(0, 0, 0), B.Work{})))
    IO.print(acct(B.new(0, 0, 0), B.new(0, 0, 0), B.Out{}))
    IO.print(num(B.used(B.new(0, 0, 0), B.new(0, 0, 0), B.Out{})))
    IO.print(acct(B.new(0, 0, 0), B.new(0, 0, 0), B.Calls{}))
    IO.print(num(B.used(B.new(0, 0, 0), B.new(0, 0, 0), B.Calls{})))
    IO.print(acct(B.new(1, 0, 0), B.new(0, 0, 0), B.Work{}))
    IO.print(num(B.used(B.new(0, 0, 0), B.new(1, 0, 0), B.Work{})))
    IO.print(acct(B.new(1, 0, 0), B.new(1, 0, 0), B.Out{}))
    IO.print(num(B.used(B.new(1, 0, 0), B.new(1, 0, 0), B.Out{})))
    IO.print(acct(B.new(1, 0, 0), B.new(1, 0, 0), B.Calls{}))
    IO.print(num(B.used(B.new(1, 0, 0), B.new(1, 0, 0), B.Calls{})))
    IO.print(acct(B.new(10, 5, 2), B.new(0, 5, 2), B.Work{}))
    IO.print(num(B.used(B.new(0, 5, 2), B.new(10, 5, 2), B.Work{})))
    IO.print(acct(B.new(10, 5, 2), B.new(10, 0, 2), B.Out{}))
    IO.print(num(B.used(B.new(10, 0, 2), B.new(10, 5, 2), B.Out{})))
    IO.print(acct(B.new(10, 5, 2), B.new(10, 5, 0), B.Calls{}))
    IO.print(num(B.used(B.new(10, 5, 0), B.new(10, 5, 2), B.Calls{})))
    IO.print(acct(B.new(7, 5, 3), B.new(0, 5, 3), B.Work{}))
    IO.print(num(B.used(B.new(0, 5, 3), B.new(7, 5, 3), B.Work{})))
    IO.print(acct(B.new(7, 5, 3), B.new(7, 0, 3), B.Out{}))
    IO.print(num(B.used(B.new(7, 0, 3), B.new(7, 5, 3), B.Out{})))
    IO.print(acct(B.new(7, 5, 3), B.new(7, 5, 0), B.Calls{}))
    IO.print(num(B.used(B.new(7, 5, 0), B.new(7, 5, 3), B.Calls{})))
    IO.print(halves(B.new(0, 0, 0)))
    IO.print(sj(B.split(B.new(0, 0, 0))))
    IO.print(halves(B.new(1, 0, 0)))
    IO.print(sj(B.split(B.new(1, 0, 0))))
    IO.print(halves(B.new(10, 5, 2)))
    IO.print(sj(B.split(B.new(10, 5, 2))))
    IO.print(halves(B.new(7, 5, 3)))
    IO.print(sj(B.split(B.new(7, 5, 3))))
    IO.print(halves(B.new(4294967295, 4294967295, 4294967295)))
    IO.print(sj(B.split(B.new(4294967295, 4294967295, 4294967295))))
    IO.print(halves(B.new(118, 103, 14)))
    IO.print(sj(B.split(B.new(118, 103, 14))))
    IO.print(halves(B.new(1, 1, 1)))
    IO.print(sj(B.split(B.new(1, 1, 1))))
    IO.print(halves(B.new(3, 5, 7)))
    IO.print(sj(B.split(B.new(3, 5, 7))))
    IO.print(halves(B.new(4294967295, 1, 0)))
    IO.print(sj(B.split(B.new(4294967295, 1, 0))))
    IO.print(sb(B.join(B.new(4294967295, 4294967295, 4294967295), B.new(1, 1, 1))))
    IO.print(sb(B.join(B.new(4294967295, 0, 3), B.new(4294967295, 4294967295, 4))))
    IO.print(sb(B.join(B.new(0, 0, 0), B.new(9, 8, 7))))
    IO.print(sb(B.cap(B.new(0, 0, 0), B.new(4294967295, 4294967295, 4294967295))))
    IO.print(sb(B.cap(B.new(0, 0, 0), B.new(0, 0, 0))))
    IO.print(sb(B.cap(B.new(0, 0, 0), B.new(99, 1, 7))))
    IO.print(sb(B.cap(B.new(1, 0, 0), B.new(4294967295, 4294967295, 4294967295))))
    IO.print(sb(B.cap(B.new(1, 0, 0), B.new(0, 0, 0))))
    IO.print(sb(B.cap(B.new(1, 0, 0), B.new(99, 1, 7))))
    IO.print(sb(B.cap(B.new(10, 5, 2), B.new(4294967295, 4294967295, 4294967295))))
    IO.print(sb(B.cap(B.new(10, 5, 2), B.new(0, 0, 0))))
    IO.print(sb(B.cap(B.new(10, 5, 2), B.new(99, 1, 7))))
    IO.print(sb(B.cap(B.new(7, 5, 3), B.new(4294967295, 4294967295, 4294967295))))
    IO.print(sb(B.cap(B.new(7, 5, 3), B.new(0, 0, 0))))
    IO.print(sb(B.cap(B.new(7, 5, 3), B.new(99, 1, 7))))
    IO.print(sr(B.fold(B.fold(B.fold(B.spend(B.new(10, 5, 2), B.Work{}, 3), B.Out{}, 2), B.Calls{}, 1), B.Work{}, 4)))
    IO.print(sr(B.fold(B.fold(B.fold(B.spend(B.new(7, 5, 3), B.Work{}, 3), B.Out{}, 2), B.Calls{}, 1), B.Work{}, 4)))
    IO.print(sr(B.fold(B.fold(B.fold(B.spend(B.new(6, 5, 2), B.Work{}, 3), B.Out{}, 2), B.Calls{}, 1), B.Work{}, 4)))
    IO.print(sr(B.fold(B.fold(B.fold(B.spend(B.new(10, 1, 2), B.Work{}, 3), B.Out{}, 2), B.Calls{}, 1), B.Work{}, 4)))
    IO.print(sr(B.fold(B.fold(B.fold(B.spend(B.new(10, 5, 0), B.Work{}, 3), B.Out{}, 2), B.Calls{}, 1), B.Work{}, 4)))
    IO.print(tree(0n, 0))
    IO.print(tree(0n, 7))
    IO.print(tree(0n, 9))
    IO.print(tree(0n, 1000))
    IO.print(tree(1n, 0))
    IO.print(tree(1n, 7))
    IO.print(tree(1n, 9))
    IO.print(tree(1n, 1000))
    IO.print(tree(2n, 0))
    IO.print(tree(2n, 7))
    IO.print(tree(2n, 9))
    IO.print(tree(2n, 1000))
    IO.print(tree(3n, 0))
    IO.print(tree(3n, 7))
    IO.print(tree(3n, 9))
    IO.print(tree(3n, 1000))
    IO.print(tree(4n, 0))
    IO.print(tree(4n, 7))
    IO.print(tree(4n, 9))
    IO.print(tree(4n, 1000))
#|0 0 0
#|4294967295 4294967295 4294967295
#|0 0 0
#|1 0 0
#|10 5 2
#|7 5 3
#|4294967295 4294967295 4294967295
#|10
#|5
#|2
#|1
#|0
#|0
#|0
#|1 0 0 0
#|0 dry:work
#|0 dry:work
#|1 0 0 0
#|0 dry:out
#|0 dry:out
#|1 0 0 0
#|0 dry:calls
#|0 dry:calls
#|1 0 0 0
#|0 dry:work
#|0 dry:work
#|1 1 0 0
#|0 dry:out
#|0 dry:out
#|1 1 0 0
#|0 dry:calls
#|0 dry:calls
#|1 0 5 2
#|0 dry:work
#|0 dry:work
#|1 10 0 2
#|0 dry:out
#|0 dry:out
#|1 10 5 0
#|0 dry:calls
#|0 dry:calls
#|1 0 5 3
#|0 dry:work
#|0 dry:work
#|1 7 0 3
#|0 dry:out
#|0 dry:out
#|1 7 5 0
#|0 dry:calls
#|0 dry:calls
#|1 0 4294967295 4294967295
#|1 4294967295 4294967295 4294967295
#|1 4294966995 4294967295 4294967295
#|1 4294967295 0 4294967295
#|1 4294967295 4294967295 4294967295
#|1 4294967295 4294966995 4294967295
#|1 4294967295 4294967295 0
#|1 4294967295 4294967295 4294967295
#|1 4294967295 4294967295 4294966995
#|1 0 103 14
#|0 dry:work
#|0 dry:work
#|1 118 0 14
#|0 dry:out
#|0 dry:out
#|1 118 103 0
#|0 dry:calls
#|0 dry:calls
#|0 0 0 got 0
#|0 0 0 got 0
#|0 0 0 got 0
#|0 0 0 got 0
#|0 0 0 got 0
#|0 0 0 got 0
#|1 0 0 got 0
#|0 0 0 got 1
#|1 0 0 got 0
#|1 0 0 got 0
#|1 0 0 got 0
#|1 0 0 got 0
#|5 5 2 got 5
#|0 5 2 got 10
#|10 3 2 got 2
#|10 0 2 got 5
#|10 5 1 got 1
#|10 5 0 got 2
#|4 5 3 got 3
#|0 5 3 got 7
#|7 3 3 got 2
#|7 0 3 got 5
#|7 5 2 got 1
#|7 5 0 got 3
#|0 0
#|0
#|0 0
#|0
#|0 0
#|0
#|1 1
#|0
#|0 0
#|0
#|0 0
#|0
#|10 10
#|0
#|5 5
#|0
#|2 2
#|0
#|7 7
#|0
#|5 5
#|0
#|3 3
#|0
#|0 0 0 | 0 0 0 -> 0 0 0
#|0 0 0
#|1 0 0 | 0 0 0 -> 1 0 0
#|1 0 0
#|5 3 1 | 5 2 1 -> 10 5 2
#|10 5 2
#|4 3 2 | 3 2 1 -> 7 5 3
#|7 5 3
#|2147483648 2147483648 2147483648 | 2147483647 2147483647 2147483647 -> 4294967295 4294967295 4294967295
#|4294967295 4294967295 4294967295
#|59 52 7 | 59 51 7 -> 118 103 14
#|118 103 14
#|1 1 1 | 0 0 0 -> 1 1 1
#|1 1 1
#|2 3 4 | 1 2 3 -> 3 5 7
#|3 5 7
#|2147483648 1 0 | 2147483647 0 0 -> 4294967295 1 0
#|4294967295 1 0
#|4294967295 4294967295 4294967295
#|4294967295 4294967295 7
#|9 8 7
#|0 0 0
#|0 0 0
#|0 0 0
#|1 0 0
#|0 0 0
#|1 0 0
#|10 5 2
#|0 0 0
#|10 1 2
#|7 5 3
#|0 0 0
#|7 1 3
#|3 3 1
#|0 3 2
#|dry:work
#|dry:out
#|dry:calls
#|0+0
#|1+6
#|1+8
#|1+999
#|0+0
#|3+4
#|3+6
#|3+997
#|0+0
#|6+1
#|6+3
#|7+993
#|0+0
#|7+0
#|8+1
#|15+985
#|0+0
#|7+0
#|9+0
#|31+969
