# Assign against brute force over the injective maps, cross-checked against
# SciPy (assign_gen.py prints this file). A row is "<cost> <ok> <cert>": what
# the matching costs, whether a full one was found, and whether the prices that
# came back prove it optimal. `perm` rows appear only where exactly one map
# reaches the optimum; `gap` rows print (sum of row prices - sum of column
# prices), which strong duality makes equal to the cost and which is unique
# however the ties fell.
import Base
import ../../power/vec.bend as Vec
import ../../power/assign.bend as Assign

def mat(xs: List<&2, U32>) -> Vec.Vec:
  Vec.from_list(xs, Vec.new(0))

def yn(b: Bool) -> String:
  match b:
    case True{}:
      "1"
    case False{}:
      "0"

def line.ck(k: U32, ok: Bool, x: Assign.Ck) -> String:
  match x:
    case Assign.Ck{c, s, cert}:
      U32.show(k) ++ " " ++ yn(ok) ++ " " ++ yn(cert)

def line.ok(c: Vec.Vec, k: U32, r: Assign.Sol & Bool) -> String:
  (s, ok) = r
  line.ck(k, ok, Assign.certify(c, s))

def line.cost(c: Vec.Vec, r: Assign.Sol & U32) -> String:
  (s, k) = r
  line.ok(c, k, Assign.solved(s))

def line(r: Vec.Vec & Assign.Sol) -> String:
  (c, s) = r
  line.cost(c, Assign.cost(s))

def perm.at(acc: List<&2, String>, r: Assign.Sol & U32) -> Assign.Sol & List<&2, String>:
  (s, x) = r
  (s, Con{U32.show(x), acc})

def perm.one(i: U32, sa: Assign.Sol & List<&2, String>) -> Assign.Sol & List<&2, String>:
  (s, acc) = sa
  perm.at(acc, Assign.at(s, i))

def perm.go(fuel: Nat, sa: Assign.Sol & List<&2, String>) -> Assign.Sol & List<&2, String>:
  match fuel:
    case 0n:
      sa
    case 1n++q:
      perm.go(q, perm.one(U32.from_nat(q), sa))

def perm.txt(r: Assign.Sol & List<&2, String>) -> String:
  (s, xs) = r
  String.join(xs, " ")

def perm(+n: U32, r: Vec.Vec & Assign.Sol) -> String:
  (c, s) = r
  perm.txt(perm.go(U32.to_nat(n), (s, [])))

def gap.add(acc: U32, r: Assign.Sol & U32) -> Assign.Sol & U32:
  (s, x) = r
  (s, U32.add(acc, x))

def gap.row(i: U32, sa: Assign.Sol & U32) -> Assign.Sol & U32:
  (s, acc) = sa
  gap.add(acc, Assign.price_row(s, i))

def gap.rows(fuel: Nat, sa: Assign.Sol & U32) -> Assign.Sol & U32:
  match fuel:
    case 0n:
      sa
    case 1n++q:
      gap.rows(q, gap.row(U32.from_nat(q), sa))

def gap.col(j: U32, sa: Assign.Sol & U32) -> Assign.Sol & U32:
  (s, acc) = sa
  gap.add(acc, Assign.price_col(s, j))

def gap.cols(fuel: Nat, sa: Assign.Sol & U32) -> Assign.Sol & U32:
  match fuel:
    case 0n:
      sa
    case 1n++q:
      gap.cols(q, gap.col(U32.from_nat(q), sa))

def gap.sub(su: U32, r: Assign.Sol & U32) -> String:
  (s, sw) = r
  U32.show(U32.sub(su, sw))

def gap.go(+nc: U32, r: Assign.Sol & U32) -> String:
  (s, su) = r
  gap.sub(su, gap.cols(U32.to_nat(nc), (s, 0)))

def gap(+nr: U32, +nc: U32, r: Vec.Vec & Assign.Sol) -> String:
  (c, s) = r
  gap.go(nc, gap.rows(U32.to_nat(nr), (s, 0)))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(line(Assign.solve(mat([29]), 1, 1)))
    IO.print(perm(1, Assign.solve(mat([29]), 1, 1)))
    IO.print(gap(1, 1, Assign.solve(mat([29]), 1, 1)))
    IO.print(line(Assign.solve(mat([25]), 1, 1)))
    IO.print(perm(1, Assign.solve(mat([25]), 1, 1)))
    IO.print(gap(1, 1, Assign.solve(mat([25]), 1, 1)))
    IO.print(line(Assign.solve(mat([14, 19, 32, 26]), 2, 2)))
    IO.print(perm(2, Assign.solve(mat([14, 19, 32, 26]), 2, 2)))
    IO.print(line(Assign.solve(mat([1, 3, 36, 17]), 2, 2)))
    IO.print(perm(2, Assign.solve(mat([1, 3, 36, 17]), 2, 2)))
    IO.print(line(Assign.solve(mat([29, 37, 27, 1, 2, 31, 5, 11, 39]), 3, 3)))
    IO.print(perm(3, Assign.solve(mat([29, 37, 27, 1, 2, 31, 5, 11, 39]), 3, 3)))
    IO.print(gap(3, 3, Assign.solve(mat([29, 37, 27, 1, 2, 31, 5, 11, 39]), 3, 3)))
    IO.print(line(Assign.solve(mat([34, 22, 4, 24, 20, 4, 25, 2, 15]), 3, 3)))
    IO.print(perm(3, Assign.solve(mat([34, 22, 4, 24, 20, 4, 25, 2, 15]), 3, 3)))
    IO.print(gap(3, 3, Assign.solve(mat([34, 22, 4, 24, 20, 4, 25, 2, 15]), 3, 3)))
    IO.print(line(Assign.solve(mat([0, 32, 17, 28, 32, 34, 6, 12, 39, 34, 10, 17, 22, 35, 26, 33]), 4, 4)))
    IO.print(perm(4, Assign.solve(mat([0, 32, 17, 28, 32, 34, 6, 12, 39, 34, 10, 17, 22, 35, 26, 33]), 4, 4)))
    IO.print(line(Assign.solve(mat([17, 9, 11, 2, 25, 2, 31, 36, 34, 16, 16, 0, 33, 20, 12, 21]), 4, 4)))
    IO.print(perm(4, Assign.solve(mat([17, 9, 11, 2, 25, 2, 31, 36, 34, 16, 16, 0, 33, 20, 12, 21]), 4, 4)))
    IO.print(line(Assign.solve(mat([16, 21, 11, 4, 8, 23, 39, 16, 27, 29, 17, 20, 30, 2, 35, 19, 16, 5, 2, 18, 10, 17, 25, 26, 2]), 5, 5)))
    IO.print(gap(5, 5, Assign.solve(mat([16, 21, 11, 4, 8, 23, 39, 16, 27, 29, 17, 20, 30, 2, 35, 19, 16, 5, 2, 18, 10, 17, 25, 26, 2]), 5, 5)))
    IO.print(line(Assign.solve(mat([2, 17, 4, 38, 21, 23, 0, 2, 13, 32, 2, 5, 24, 24, 24, 36, 26, 8, 18, 21, 37, 3, 37, 23, 23]), 5, 5)))
    IO.print(perm(5, Assign.solve(mat([2, 17, 4, 38, 21, 23, 0, 2, 13, 32, 2, 5, 24, 24, 24, 36, 26, 8, 18, 21, 37, 3, 37, 23, 23]), 5, 5)))
    IO.print(gap(5, 5, Assign.solve(mat([2, 17, 4, 38, 21, 23, 0, 2, 13, 32, 2, 5, 24, 24, 24, 36, 26, 8, 18, 21, 37, 3, 37, 23, 23]), 5, 5)))
    IO.print(line(Assign.solve(mat([22, 1, 7, 16, 4, 30, 38, 34, 10, 23, 34, 39, 33, 12, 25, 7, 4, 7, 16, 33, 37, 6, 26, 31, 11, 23, 36, 3, 25, 5, 31, 2, 10, 21, 3, 5]), 6, 6)))
    IO.print(perm(6, Assign.solve(mat([22, 1, 7, 16, 4, 30, 38, 34, 10, 23, 34, 39, 33, 12, 25, 7, 4, 7, 16, 33, 37, 6, 26, 31, 11, 23, 36, 3, 25, 5, 31, 2, 10, 21, 3, 5]), 6, 6)))
    IO.print(line(Assign.solve(mat([22, 36, 4, 32, 14, 0, 13, 35, 2, 33, 21, 10, 27, 26, 35, 21, 15, 26, 27, 39, 37, 39, 36, 37, 15, 11, 7, 28, 37, 39, 39, 33, 33, 1, 29, 27]), 6, 6)))
    IO.print(perm(6, Assign.solve(mat([22, 36, 4, 32, 14, 0, 13, 35, 2, 33, 21, 10, 27, 26, 35, 21, 15, 26, 27, 39, 37, 39, 36, 37, 15, 11, 7, 28, 37, 39, 39, 33, 33, 1, 29, 27]), 6, 6)))
    IO.print(line(Assign.solve(mat([34, 11, 36, 9, 7, 4, 30, 0, 30, 23, 22, 10, 25, 33, 28, 12, 33, 4, 37, 26, 26, 32, 27, 3, 32, 22, 24, 10, 14, 37, 9, 3, 30, 3, 38, 26, 29, 36, 33, 10, 23, 39, 7, 8, 36, 8, 32, 23, 32]), 7, 7)))
    IO.print(perm(7, Assign.solve(mat([34, 11, 36, 9, 7, 4, 30, 0, 30, 23, 22, 10, 25, 33, 28, 12, 33, 4, 37, 26, 26, 32, 27, 3, 32, 22, 24, 10, 14, 37, 9, 3, 30, 3, 38, 26, 29, 36, 33, 10, 23, 39, 7, 8, 36, 8, 32, 23, 32]), 7, 7)))
    IO.print(gap(7, 7, Assign.solve(mat([34, 11, 36, 9, 7, 4, 30, 0, 30, 23, 22, 10, 25, 33, 28, 12, 33, 4, 37, 26, 26, 32, 27, 3, 32, 22, 24, 10, 14, 37, 9, 3, 30, 3, 38, 26, 29, 36, 33, 10, 23, 39, 7, 8, 36, 8, 32, 23, 32]), 7, 7)))
    IO.print(line(Assign.solve(mat([25, 39, 17, 9, 14, 7, 32, 14, 21, 26, 20, 15, 21, 0, 24, 27, 6, 19, 11, 26, 12, 16, 8, 31, 37, 30, 13, 33, 38, 6, 20, 7, 6, 39, 26, 34, 27, 1, 22, 20, 33, 38, 29, 32, 22, 33, 7, 38, 36]), 7, 7)))
    IO.print(perm(7, Assign.solve(mat([25, 39, 17, 9, 14, 7, 32, 14, 21, 26, 20, 15, 21, 0, 24, 27, 6, 19, 11, 26, 12, 16, 8, 31, 37, 30, 13, 33, 38, 6, 20, 7, 6, 39, 26, 34, 27, 1, 22, 20, 33, 38, 29, 32, 22, 33, 7, 38, 36]), 7, 7)))
    IO.print(gap(7, 7, Assign.solve(mat([25, 39, 17, 9, 14, 7, 32, 14, 21, 26, 20, 15, 21, 0, 24, 27, 6, 19, 11, 26, 12, 16, 8, 31, 37, 30, 13, 33, 38, 6, 20, 7, 6, 39, 26, 34, 27, 1, 22, 20, 33, 38, 29, 32, 22, 33, 7, 38, 36]), 7, 7)))
    IO.print(line(Assign.solve(mat([6, 17, 5, 20]), 1, 4)))
    IO.print(perm(1, Assign.solve(mat([6, 17, 5, 20]), 1, 4)))
    IO.print(gap(1, 4, Assign.solve(mat([6, 17, 5, 20]), 1, 4)))
    IO.print(line(Assign.solve(mat([25, 6, 4, 2, 3, 13, 3, 17, 7, 12]), 2, 5)))
    IO.print(perm(2, Assign.solve(mat([25, 6, 4, 2, 3, 13, 3, 17, 7, 12]), 2, 5)))
    IO.print(gap(2, 5, Assign.solve(mat([25, 6, 4, 2, 3, 13, 3, 17, 7, 12]), 2, 5)))
    IO.print(line(Assign.solve(mat([13, 6, 19, 20, 1, 5, 23, 3, 3, 11, 24, 27]), 3, 4)))
    IO.print(perm(3, Assign.solve(mat([13, 6, 19, 20, 1, 5, 23, 3, 3, 11, 24, 27]), 3, 4)))
    IO.print(gap(3, 4, Assign.solve(mat([13, 6, 19, 20, 1, 5, 23, 3, 3, 11, 24, 27]), 3, 4)))
    IO.print(line(Assign.solve(mat([23, 21, 9, 12, 9, 28, 18, 12, 7, 26, 8, 21, 25, 15, 16, 26, 6, 17, 18, 29, 0]), 3, 7)))
    IO.print(gap(3, 7, Assign.solve(mat([23, 21, 9, 12, 9, 28, 18, 12, 7, 26, 8, 21, 25, 15, 16, 26, 6, 17, 18, 29, 0]), 3, 7)))
    IO.print(line(Assign.solve(mat([10, 5, 13, 27, 7, 7, 6, 15, 15, 24, 28, 15, 11, 3, 28, 29, 19, 19, 25, 14, 25, 29, 6, 0]), 4, 6)))
    IO.print(perm(4, Assign.solve(mat([10, 5, 13, 27, 7, 7, 6, 15, 15, 24, 28, 15, 11, 3, 28, 29, 19, 19, 25, 14, 25, 29, 6, 0]), 4, 6)))
    IO.print(gap(4, 6, Assign.solve(mat([10, 5, 13, 27, 7, 7, 6, 15, 15, 24, 28, 15, 11, 3, 28, 29, 19, 19, 25, 14, 25, 29, 6, 0]), 4, 6)))
    IO.print(line(Assign.solve(mat([19, 23, 27, 26, 19, 1, 4, 19, 6, 8, 23, 24, 5, 27, 27, 29, 18, 20, 20, 20, 3, 17, 19, 11, 18, 26, 9, 24, 16, 2]), 5, 6)))
    IO.print(perm(5, Assign.solve(mat([19, 23, 27, 26, 19, 1, 4, 19, 6, 8, 23, 24, 5, 27, 27, 29, 18, 20, 20, 20, 3, 17, 19, 11, 18, 26, 9, 24, 16, 2]), 5, 6)))
    IO.print(gap(5, 6, Assign.solve(mat([19, 23, 27, 26, 19, 1, 4, 19, 6, 8, 23, 24, 5, 27, 27, 29, 18, 20, 20, 20, 3, 17, 19, 11, 18, 26, 9, 24, 16, 2]), 5, 6)))
    IO.print(line(Assign.solve(mat([6, 25]), 2, 1)))
    IO.print(line(Assign.solve(mat([10, 16, 9, 4, 9, 27]), 3, 2)))
    IO.print(line(Assign.solve(mat([0, 22, 5, 21, 19, 29, 13, 15, 9, 17, 18, 17, 2, 22, 15, 23, 3, 5, 18, 14]), 5, 4)))
    IO.print(line(Assign.solve(mat([]), 4, 0)))
    IO.print(line(Assign.solve(mat([0, 0, 0, 0]), 2, 2)))
    IO.print(gap(2, 2, Assign.solve(mat([0, 0, 0, 0]), 2, 2)))
    IO.print(line(Assign.solve(mat([0, 0, 0, 0, 0, 0, 0, 0, 0]), 3, 3)))
    IO.print(gap(3, 3, Assign.solve(mat([0, 0, 0, 0, 0, 0, 0, 0, 0]), 3, 3)))
    IO.print(line(Assign.solve(mat([7, 7, 7, 7, 7, 7, 7, 7, 7]), 3, 3)))
    IO.print(gap(3, 3, Assign.solve(mat([7, 7, 7, 7, 7, 7, 7, 7, 7]), 3, 3)))
    IO.print(line(Assign.solve(mat([1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]), 4, 4)))
    IO.print(gap(4, 4, Assign.solve(mat([1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]), 4, 4)))
    IO.print(line(Assign.solve(mat([3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3]), 5, 5)))
    IO.print(gap(5, 5, Assign.solve(mat([3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3]), 5, 5)))
    IO.print(line(Assign.solve(mat([2, 2, 2, 9, 2, 2, 9, 9, 9, 2, 2, 2, 2, 9, 2, 2]), 4, 4)))
    IO.print(gap(4, 4, Assign.solve(mat([2, 2, 2, 9, 2, 2, 9, 9, 9, 2, 2, 2, 2, 9, 2, 2]), 4, 4)))
    IO.print(line(Assign.solve(mat([9, 2, 2, 2, 2, 2, 9, 9, 2, 2, 9, 2, 2, 9, 2, 9, 9, 2, 2, 2, 2, 9, 9, 9, 9]), 5, 5)))
    IO.print(gap(5, 5, Assign.solve(mat([9, 2, 2, 2, 2, 2, 9, 9, 2, 2, 9, 2, 2, 9, 2, 9, 9, 2, 2, 2, 2, 9, 9, 9, 9]), 5, 5)))
    IO.print(line(Assign.solve(mat([4294967295, 3, 8, 2, 4294967295, 21, 4294967295, 5, 0]), 3, 3)))
    IO.print(perm(3, Assign.solve(mat([4294967295, 3, 8, 2, 4294967295, 21, 4294967295, 5, 0]), 3, 3)))
    IO.print(line(Assign.solve(mat([4294967295, 8, 4294967295, 22, 4294967295, 4294967295, 10, 4294967295, 4294967295, 2, 4294967295, 4294967295, 4294967295, 23, 15, 18, 16, 4294967295, 4294967295, 4294967295]), 4, 5)))
    IO.print(perm(4, Assign.solve(mat([4294967295, 8, 4294967295, 22, 4294967295, 4294967295, 10, 4294967295, 4294967295, 2, 4294967295, 4294967295, 4294967295, 23, 15, 18, 16, 4294967295, 4294967295, 4294967295]), 4, 5)))
    IO.print(line(Assign.solve(mat([2, 4294967295, 4294967295, 21, 23, 4294967295, 4, 4, 4294967295, 22, 8, 4294967295, 23, 18, 4294967295, 4294967295, 4294967295, 18, 17, 14, 4294967295, 4, 4294967295, 5, 23]), 5, 5)))
    IO.print(perm(5, Assign.solve(mat([2, 4294967295, 4294967295, 21, 23, 4294967295, 4, 4, 4294967295, 22, 8, 4294967295, 23, 18, 4294967295, 4294967295, 4294967295, 18, 17, 14, 4294967295, 4, 4294967295, 5, 23]), 5, 5)))
    IO.print(line(Assign.solve(mat([24, 4294967295, 4294967295, 23, 20, 4294967295, 13, 4294967295, 22, 4294967295, 10, 4294967295, 4294967295, 4294967295, 4294967295, 12, 20, 8, 4294967295, 4294967295, 4294967295, 21, 7, 24, 4294967295, 4294967295, 4294967295, 22, 23, 2, 5, 8, 6, 4294967295, 4294967295, 4294967295]), 6, 6)))
    IO.print(perm(6, Assign.solve(mat([24, 4294967295, 4294967295, 23, 20, 4294967295, 13, 4294967295, 22, 4294967295, 10, 4294967295, 4294967295, 4294967295, 4294967295, 12, 20, 8, 4294967295, 4294967295, 4294967295, 21, 7, 24, 4294967295, 4294967295, 4294967295, 22, 23, 2, 5, 8, 6, 4294967295, 4294967295, 4294967295]), 6, 6)))
    IO.print(line(Assign.solve(mat([4294967295, 4294967295, 21, 13, 4294967295, 4294967295, 4294967295, 4294967295, 4294967295, 4294967295, 5, 4294967295, 9, 4294967295, 4294967295, 4294967295, 4294967295, 20, 4294967295, 4294967295, 4294967295, 13, 4294967295, 4294967295, 4294967295, 4294967295, 19, 4294967295, 4294967295, 4294967295, 18, 4294967295, 4294967295, 4294967295, 12, 4294967295, 8, 4294967295, 4294967295, 4294967295]), 5, 8)))
    IO.print(perm(5, Assign.solve(mat([4294967295, 4294967295, 21, 13, 4294967295, 4294967295, 4294967295, 4294967295, 4294967295, 4294967295, 5, 4294967295, 9, 4294967295, 4294967295, 4294967295, 4294967295, 20, 4294967295, 4294967295, 4294967295, 13, 4294967295, 4294967295, 4294967295, 4294967295, 19, 4294967295, 4294967295, 4294967295, 18, 4294967295, 4294967295, 4294967295, 12, 4294967295, 8, 4294967295, 4294967295, 4294967295]), 5, 8)))
    IO.print(line(Assign.solve(mat([1, 4294967295, 4294967295, 2, 4294967295, 4294967295, 4294967295, 4294967295, 3]), 3, 3)))
    IO.print(line(Assign.solve(mat([4294967295, 4294967295, 4294967295, 1, 2, 3, 4, 5, 6]), 3, 3)))
    IO.print(line(Assign.solve(mat([5, 4294967295, 4294967295, 6]), 2, 2)))
    IO.print(perm(2, Assign.solve(mat([5, 4294967295, 4294967295, 6]), 2, 2)))
    IO.print(line(Assign.solve(mat([4294967295, 1, 7, 4294967295]), 2, 2)))
    IO.print(perm(2, Assign.solve(mat([4294967295, 1, 7, 4294967295]), 2, 2)))
    IO.print(line(Assign.solve_opt(mat([9, 9, 9, 9]), 2, 2, 0)))
    IO.print(perm(2, Assign.solve_opt(mat([9, 9, 9, 9]), 2, 2, 0)))
    IO.print(line(Assign.solve_opt(mat([9, 9, 9, 9]), 2, 2, 3)))
    IO.print(perm(2, Assign.solve_opt(mat([9, 9, 9, 9]), 2, 2, 3)))
    IO.print(gap(2, 4, Assign.solve_opt(mat([9, 9, 9, 9]), 2, 2, 3)))
    IO.print(line(Assign.solve_opt(mat([9, 9, 9, 9]), 2, 2, 8)))
    IO.print(perm(2, Assign.solve_opt(mat([9, 9, 9, 9]), 2, 2, 8)))
    IO.print(line(Assign.solve_opt(mat([9, 9, 9, 9]), 2, 2, 9)))
    IO.print(line(Assign.solve_opt(mat([9, 9, 9, 9]), 2, 2, 20)))
    IO.print(line(Assign.solve_opt(mat([1, 9, 9, 9]), 2, 2, 3)))
    IO.print(perm(2, Assign.solve_opt(mat([1, 9, 9, 9]), 2, 2, 3)))
    IO.print(gap(2, 4, Assign.solve_opt(mat([1, 9, 9, 9]), 2, 2, 3)))
    IO.print(line(Assign.solve_opt(mat([1, 9, 9, 9]), 2, 2, 20)))
    IO.print(perm(2, Assign.solve_opt(mat([1, 9, 9, 9]), 2, 2, 20)))
    IO.print(line(Assign.solve_opt(mat([4, 7, 2, 6, 3, 8]), 2, 3, 1)))
    IO.print(perm(2, Assign.solve_opt(mat([4, 7, 2, 6, 3, 8]), 2, 3, 1)))
    IO.print(line(Assign.solve_opt(mat([4, 7, 2, 6, 3, 8]), 2, 3, 5)))
    IO.print(perm(2, Assign.solve_opt(mat([4, 7, 2, 6, 3, 8]), 2, 3, 5)))
    IO.print(gap(2, 5, Assign.solve_opt(mat([4, 7, 2, 6, 3, 8]), 2, 3, 5)))
    IO.print(line(Assign.solve_opt(mat([4, 7, 2, 6, 3, 8]), 2, 3, 50)))
    IO.print(perm(2, Assign.solve_opt(mat([4, 7, 2, 6, 3, 8]), 2, 3, 50)))
    IO.print(line(Assign.solve_opt(mat([3, 1, 4, 1, 5, 9, 2, 6, 5]), 3, 3, 2)))
    IO.print(perm(3, Assign.solve_opt(mat([3, 1, 4, 1, 5, 9, 2, 6, 5]), 3, 3, 2)))
    IO.print(line(Assign.solve_opt(mat([3, 1, 4, 1, 5, 9, 2, 6, 5]), 3, 3, 4)))
    IO.print(perm(3, Assign.solve_opt(mat([3, 1, 4, 1, 5, 9, 2, 6, 5]), 3, 3, 4)))
    IO.print(gap(3, 6, Assign.solve_opt(mat([3, 1, 4, 1, 5, 9, 2, 6, 5]), 3, 3, 4)))
    IO.print(line(Assign.solve_opt(mat([3, 1, 4, 1, 5, 9, 2, 6, 5]), 3, 3, 100)))
    IO.print(perm(3, Assign.solve_opt(mat([3, 1, 4, 1, 5, 9, 2, 6, 5]), 3, 3, 100)))
    IO.print(line(Assign.solve_opt(mat([4294967295, 2, 4294967295, 4294967295, 4294967295, 4294967295]), 2, 3, 7)))
    IO.print(perm(2, Assign.solve_opt(mat([4294967295, 2, 4294967295, 4294967295, 4294967295, 4294967295]), 2, 3, 7)))
    IO.print(gap(2, 5, Assign.solve_opt(mat([4294967295, 2, 4294967295, 4294967295, 4294967295, 4294967295]), 2, 3, 7)))
    IO.print(line(Assign.solve(mat([]), 0, 0)))
    IO.print(line(Assign.solve(mat([]), 0, 3)))
    IO.print(line(Assign.solve(mat([6]), 1, 1)))
    IO.print(perm(1, Assign.solve(mat([6]), 1, 1)))
    IO.print(gap(1, 1, Assign.solve(mat([6]), 1, 1)))
    IO.print(line(Assign.solve(mat([8, 2, 5, 1]), 1, 4)))
    IO.print(perm(1, Assign.solve(mat([8, 2, 5, 1]), 1, 4)))
    IO.print(gap(1, 4, Assign.solve(mat([8, 2, 5, 1]), 1, 4)))
    IO.print(line(Assign.solve(mat([3, 1, 4, 1]), 4, 1)))
    IO.print(line(Assign.solve(mat([255, 760, 416, 73, 894, 883, 62, 672, 673, 731, 141, 778, 656, 239, 51, 103, 362, 772, 617, 274, 931, 597, 312, 629, 933, 745, 855, 966, 154, 959, 960, 842, 460, 477, 676, 292, 82, 650, 429, 204, 879, 899, 331, 198, 76, 215, 466, 730, 413, 971, 391, 368, 8, 576, 949, 428, 219, 513, 314, 52, 901, 97, 957, 232]), 8, 8)))
    IO.print(gap(8, 8, Assign.solve(mat([255, 760, 416, 73, 894, 883, 62, 672, 673, 731, 141, 778, 656, 239, 51, 103, 362, 772, 617, 274, 931, 597, 312, 629, 933, 745, 855, 966, 154, 959, 960, 842, 460, 477, 676, 292, 82, 650, 429, 204, 879, 899, 331, 198, 76, 215, 466, 730, 413, 971, 391, 368, 8, 576, 949, 428, 219, 513, 314, 52, 901, 97, 957, 232]), 8, 8)))
    IO.print(line(Assign.solve(mat([182, 424, 773, 303, 275, 306, 247, 513, 150, 869, 912, 480, 250, 974, 848, 395, 295, 601, 63, 706, 675, 164, 845, 379, 552, 677, 516, 944, 209, 366, 777, 432, 118, 574, 671, 612, 533, 945, 290, 212, 754, 495, 305, 425, 223, 70, 394, 674, 514, 842, 39, 684, 791, 45, 343, 98, 119, 521, 396, 199, 767, 471, 304, 246, 229, 79, 571, 699, 577, 505, 924, 217, 770, 882, 120, 216, 936, 664, 456, 239, 414]), 9, 9)))
    IO.print(gap(9, 9, Assign.solve(mat([182, 424, 773, 303, 275, 306, 247, 513, 150, 869, 912, 480, 250, 974, 848, 395, 295, 601, 63, 706, 675, 164, 845, 379, 552, 677, 516, 944, 209, 366, 777, 432, 118, 574, 671, 612, 533, 945, 290, 212, 754, 495, 305, 425, 223, 70, 394, 674, 514, 842, 39, 684, 791, 45, 343, 98, 119, 521, 396, 199, 767, 471, 304, 246, 229, 79, 571, 699, 577, 505, 924, 217, 770, 882, 120, 216, 936, 664, 456, 239, 414]), 9, 9)))
    IO.print(line(Assign.solve(mat([536870911, 536870908, 536870904, 536870910]), 2, 2)))
    IO.print(perm(2, Assign.solve(mat([536870911, 536870908, 536870904, 536870910]), 2, 2)))
    IO.print(gap(2, 2, Assign.solve(mat([536870911, 536870908, 536870904, 536870910]), 2, 2)))
    IO.print(line(Assign.solve(mat([536870906, 2, 9, 536870909]), 2, 2)))
    IO.print(perm(2, Assign.solve(mat([536870906, 2, 9, 536870909]), 2, 2)))
    IO.print(gap(2, 2, Assign.solve(mat([536870906, 2, 9, 536870909]), 2, 2)))
#|29 1 1
#|0
#|29
#|25 1 1
#|0
#|25
#|40 1 1
#|0 1
#|18 1 1
#|0 1
#|34 1 1
#|2 1 0
#|34
#|30 1 1
#|2 0 1
#|30
#|57 1 1
#|0 3 2 1
#|31 1 1
#|0 1 3 2
#|52 1 1
#|52
#|43 1 1
#|2 3 0 4 1
#|43
#|37 1 1
#|1 2 4 3 0 5
#|56 1 1
#|5 2 4 0 1 3
#|45 1 1
#|5 0 3 6 2 4 1
#|45
#|54 1 1
#|5 6 0 1 3 2 4
#|54
#|5 1 1
#|2
#|5
#|5 1 1
#|3 1
#|5
#|12 1 1
#|1 3 0
#|12
#|16 1 1
#|16
#|16 1 1
#|4 0 1 5
#|16
#|33 1 1
#|5 3 0 2 4
#|33
#|0 0 0
#|0 0 0
#|0 0 0
#|0 0 0
#|0 1 1
#|0
#|0 1 1
#|0
#|21 1 1
#|21
#|4 1 1
#|4
#|15 1 1
#|15
#|8 1 1
#|8
#|10 1 1
#|10
#|5 1 1
#|1 0 2
#|51 1 1
#|1 4 3 0
#|42 1 1
#|0 2 3 4 1
#|75 1 1
#|0 2 3 4 5 1
#|57 1 1
#|3 2 5 6 4
#|0 0 0
#|0 0 0
#|11 1 1
#|0 1
#|8 1 1
#|1 0
#|0 1 1
#|2 3
#|6 1 1
#|2 3
#|6
#|16 1 1
#|2 3
#|18 1 1
#|18 1 1
#|4 1 1
#|0 3
#|4
#|10 1 1
#|0 1
#|2 1 1
#|3 4
#|5 1 1
#|2 1
#|5
#|5 1 1
#|2 1
#|4 1 1
#|1 0 5
#|6 1 1
#|1 0 5
#|6
#|7 1 1
#|1 0 2
#|9 1 1
#|1 4
#|9
#|0 1 1
#|0 1 1
#|6 1 1
#|0
#|6
#|1 1 1
#|3
#|1
#|0 0 0
#|1789 1 1
#|1789
#|1472 1 1
#|1472
#|1073741812 1 1
#|1 0
#|1073741812
#|11 1 1
#|1 0
#|11
