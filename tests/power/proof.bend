# proof.bend against a set-valued CPython reference (proof_gen.py prints this
# file). A row is one verdict: "ok <budget left>" or "no <property>". Every
# instance appears once valid and then once per single-fault corruption -- a
# checker is worth what it rejects, so most of these rows are rejections.
import Base
import ../../power/vec.bend as Vec
import ../../power/assign.bend as Assign
import ../../power/proof.bend as Proof

def vec(xs: List<&2, U32>) -> Vec.Vec:
  Vec.from_list(xs, Vec.new(0))

def res(r: Result<&2, &2, Proof.Bad, U32>) -> String:
  match r:
    case Done{left}:
      "ok " ++ U32.show(left)
    case Fail{b}:
      "no " ++ Proof.show(b)

def s2(q: Vec.Vec & Vec.Vec & Result<&2, &2, Proof.Bad, U32>) -> String:
  (a, b, r) = q
  res(r)

def s3(q: Vec.Vec & Vec.Vec & Vec.Vec & Result<&2, &2, Proof.Bad, U32>) -> String:
  (a, b, c, r) = q
  res(r)

def s4(q: Vec.Vec & Vec.Vec & Vec.Vec & Vec.Vec & Result<&2, &2, Proof.Bad, U32>) -> String:
  (a, b, c, d, r) = q
  res(r)

# Assign.Sol holds the prices in the solver's own layout -- one scratch cell in
# front of each -- so the certificate has to be unpacked before it can travel.
# Three pushes a row and a column is the whole adapter, and it is the only thing
# in this file that knows the solver exists.
type Wit is Type:
  Wit{s: Assign.Sol, u: Vec.Vec, w: Vec.Vec, mt: Vec.Vec}

def wit.u(w: Vec.Vec, mt: Vec.Vec, q: Assign.Sol & U32) -> Wit:
  (s, x) = q
  Wit{s, vec([]), w, mt}

def wit.pu(u: Vec.Vec, w: Vec.Vec, mt: Vec.Vec, q: Assign.Sol & U32) -> Wit:
  (s, x) = q
  Wit{s, Vec.push(u, x), w, mt}

def wit.pw(u: Vec.Vec, w: Vec.Vec, mt: Vec.Vec, q: Assign.Sol & U32) -> Wit:
  (s, x) = q
  Wit{s, u, Vec.push(w, x), mt}

def wit.pm(u: Vec.Vec, w: Vec.Vec, mt: Vec.Vec, q: Assign.Sol & U32) -> Wit:
  (s, x) = q
  Wit{s, u, w, Vec.push(mt, x)}

def wit.rows(fuel: Nat, +i: U32, x: Wit) -> Wit:
  match fuel:
    case 0n:
      x
    case 1n++q:
      match x:
        case Wit{s, u, w, mt}:
          wit.rows(q, U32.inc(i), wit.pu(u, w, mt, Assign.price_row(s, i)))

def wit.cols(fuel: Nat, +j: U32, x: Wit) -> Wit:
  match fuel:
    case 0n:
      x
    case 1n++q:
      match x:
        case Wit{s, u, w, mt}:
          wit.cols(q, U32.inc(j), wit.pw(u, w, mt, Assign.price_col(s, j)))

def wit.mts(fuel: Nat, +i: U32, x: Wit) -> Wit:
  match fuel:
    case 0n:
      x
    case 1n++q:
      match x:
        case Wit{s, u, w, mt}:
          wit.mts(q, U32.inc(i), wit.pm(u, w, mt, Assign.at(s, i)))

def wit.chk(c: Vec.Vec, nr: U32, nc: U32, lim: U32, x: Wit) -> String:
  match x:
    case Wit{s, u, w, mt}:
      s4(Proof.assign(c, u, w, mt, nr, nc, lim))

def cert.go(c: Vec.Vec, +nr: U32, +nc: U32, lim: U32, x: Wit) -> String:
  wit.chk(c, nr, nc, lim, wit.mts(U32.to_nat(nr), 0, wit.cols(U32.to_nat(nc), 0, wit.rows(U32.to_nat(nr), 0, x))))

def cert(q: Vec.Vec & Assign.Sol, +nr: U32, +nc: U32, lim: U32) -> String:
  (c, s) = q
  cert.go(c, nr, nc, lim, Wit{s, vec([]), vec([]), vec([])})

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(s3(Proof.sort(vec([5, 1, 9, 3, 7, 2]), vec([1, 2, 3, 5, 7, 9]), vec([1, 5, 3, 0, 4, 2]), 6, 1000)))
    IO.print(s3(Proof.sort(vec([5, 1, 9, 3, 7, 2]), vec([1, 2, 3, 5, 7, 9]), vec([1, 5, 3, 0, 4, 9]), 6, 1000)))
    IO.print(s3(Proof.sort(vec([5, 1, 9, 3, 7, 2]), vec([2, 1, 3, 5, 7, 9]), vec([5, 1, 3, 0, 4, 2]), 6, 1000)))
    IO.print(s3(Proof.sort(vec([5, 1, 9, 3, 7, 2]), vec([1, 2, 3, 5, 7, 8]), vec([1, 5, 3, 0, 4, 2]), 6, 1000)))
    IO.print(s3(Proof.sort(vec([4, 4, 4, 1]), vec([1, 4, 4, 4]), vec([3, 0, 1, 2]), 4, 1000)))
    IO.print(s3(Proof.sort(vec([4, 4, 4, 1]), vec([1, 4, 4, 4]), vec([3, 0, 0, 2]), 4, 1000)))
    IO.print(s3(Proof.sort(vec([4, 4, 4, 1]), vec([1, 4, 4, 4]), vec([3, 0, 1, 7]), 4, 1000)))
    IO.print(s3(Proof.sort(vec([4, 4, 4, 1]), vec([4, 1, 4, 4]), vec([0, 3, 1, 2]), 4, 1000)))
    IO.print(s3(Proof.sort(vec([4, 4, 4, 1]), vec([1, 4, 4, 5]), vec([3, 0, 1, 2]), 4, 1000)))
    IO.print(s3(Proof.sort(vec([0, 4294967295, 8]), vec([0, 8, 4294967295]), vec([0, 2, 1]), 3, 1000)))
    IO.print(s3(Proof.sort(vec([0, 4294967295, 8]), vec([0, 8, 4294967295]), vec([0, 2, 6]), 3, 1000)))
    IO.print(s3(Proof.sort(vec([0, 4294967295, 8]), vec([8, 0, 4294967295]), vec([2, 0, 1]), 3, 1000)))
    IO.print(s3(Proof.sort(vec([0, 4294967295, 8]), vec([0, 8, 4294967294]), vec([0, 2, 1]), 3, 1000)))
    IO.print(s3(Proof.sort(vec([11]), vec([11]), vec([0]), 1, 1000)))
    IO.print(s3(Proof.sort(vec([11]), vec([11]), vec([4]), 1, 1000)))
    IO.print(s3(Proof.sort(vec([11]), vec([10]), vec([0]), 1, 1000)))
    IO.print(s3(Proof.sort(vec([3, 1, 3, 1, 2]), vec([1, 1, 2, 3, 3]), vec([1, 3, 4, 0, 2]), 5, 1000)))
    IO.print(s3(Proof.sort(vec([3, 1, 3, 1, 2]), vec([1, 1, 2, 3, 3]), vec([1, 1, 4, 0, 2]), 5, 1000)))
    IO.print(s3(Proof.sort(vec([3, 1, 3, 1, 2]), vec([1, 1, 2, 3, 3]), vec([1, 3, 4, 0, 8]), 5, 1000)))
    IO.print(s3(Proof.sort(vec([3, 1, 3, 1, 2]), vec([1, 2, 1, 3, 3]), vec([1, 4, 3, 0, 2]), 5, 1000)))
    IO.print(s3(Proof.sort(vec([3, 1, 3, 1, 2]), vec([1, 1, 2, 3, 4]), vec([1, 3, 4, 0, 2]), 5, 1000)))
    IO.print(s3(Proof.sort(vec([5, 1, 9, 3]), vec([1, 3, 5, 9]), vec([1, 3, 0, 2]), 4, 4)))
    IO.print(s3(Proof.sort(vec([5, 1, 9, 3]), vec([1, 3, 5, 9]), vec([1, 3, 0, 2]), 4, 3)))
    IO.print(s3(Proof.sort(vec([5, 1, 9, 3]), vec([1, 3, 5, 9]), vec([1, 3, 0, 2]), 4000000000, 10)))
    IO.print(s2(Proof.topk(vec([3, 9, 4, 1, 7, 6]), vec([1, 4, 5]), 6, 3, 4, 1000)))
    IO.print(s2(Proof.topk(vec([3, 9, 4, 1, 7, 6]), vec([1, 4, 2]), 6, 3, 4, 1000)))
    IO.print(s2(Proof.topk(vec([3, 9, 4, 1, 7, 6]), vec([1, 4, 5]), 6, 3, 7, 1000)))
    IO.print(s2(Proof.topk(vec([3, 9, 4, 1, 7, 6]), vec([5, 4, 1]), 6, 3, 4, 1000)))
    IO.print(s2(Proof.topk(vec([5, 5, 5, 5]), vec([0, 1]), 4, 2, 5, 1000)))
    IO.print(s2(Proof.topk(vec([5, 5, 5, 5]), vec([0, 1]), 4, 2, 6, 1000)))
    IO.print(s2(Proof.topk(vec([5, 5, 5, 5]), vec([0, 0]), 4, 2, 5, 1000)))
    IO.print(s2(Proof.topk(vec([5, 5, 5, 5]), vec([0, 6]), 4, 2, 5, 1000)))
    IO.print(s2(Proof.topk(vec([0, 1, 2]), vec([2, 1, 0]), 3, 3, 0, 1000)))
    IO.print(s2(Proof.topk(vec([0, 1, 2]), vec([2, 1, 0]), 3, 3, 1, 1000)))
    IO.print(s2(Proof.topk(vec([0, 1, 2]), vec([0, 1, 2]), 3, 3, 0, 1000)))
    IO.print(s2(Proof.topk(vec([0, 1, 2]), vec([2, 2, 1]), 3, 3, 0, 1000)))
    IO.print(s2(Proof.topk(vec([0, 1, 2]), vec([2, 1, 5]), 3, 3, 0, 1000)))
    IO.print(s2(Proof.topk(vec([8, 2]), vec([0]), 2, 1, 2, 1000)))
    IO.print(s2(Proof.topk(vec([8, 2]), vec([1]), 2, 1, 2, 1000)))
    IO.print(s2(Proof.topk(vec([8, 2]), vec([0]), 2, 1, 9, 1000)))
    IO.print(s2(Proof.topk(vec([4, 2, 9]), vec([2, 0, 1]), 3, 3, 0, 1000)))
    IO.print(s2(Proof.topk(vec([4, 2, 9]), vec([2, 0]), 3000000000, 2, 0, 20)))
    IO.print(s4(Proof.path(vec([0, 0, 1, 2, 1]), vec([1, 2, 3, 3, 2]), vec([4, 9, 3, 1, 2]), vec([0, 4, 6, 7]), 4, 5, 0, 1000)))
    IO.print(s4(Proof.path(vec([0, 0, 1, 2, 1]), vec([1, 2, 3, 3, 2]), vec([4, 9, 3, 1, 2]), vec([0, 4, 6, 6]), 4, 5, 0, 1000)))
    IO.print(s4(Proof.path(vec([0, 1, 2, 3]), vec([1, 2, 3, 4]), vec([7, 7, 7, 7]), vec([0, 7, 14, 21, 28]), 5, 4, 0, 1000)))
    IO.print(s4(Proof.path(vec([0, 1, 2, 3]), vec([1, 2, 3, 4]), vec([7, 7, 7, 7]), vec([0, 7, 14, 21, 27]), 5, 4, 0, 1000)))
    IO.print(s4(Proof.path(vec([0, 1]), vec([1, 2]), vec([5, 6]), vec([0, 5, 11, 4294967295]), 4, 2, 0, 1000)))
    IO.print(s4(Proof.path(vec([0, 1]), vec([1, 2]), vec([5, 6]), vec([0, 5, 10, 4294967295]), 4, 2, 0, 1000)))
    IO.print(s4(Proof.path(vec([0, 1]), vec([1, 2]), vec([5, 6]), vec([0, 5, 11, 1]), 4, 2, 0, 1000)))
    IO.print(s4(Proof.path(vec([0, 1, 2, 0]), vec([1, 2, 0, 2]), vec([2, 3, 4, 100]), vec([7, 0, 3]), 3, 4, 1, 1000)))
    IO.print(s4(Proof.path(vec([0, 1, 2, 0]), vec([1, 2, 0, 2]), vec([2, 3, 4, 100]), vec([6, 0, 3]), 3, 4, 1, 1000)))
    IO.print(s4(Proof.path(vec([0, 1, 2, 0]), vec([1, 2, 0, 8]), vec([2, 3, 4, 100]), vec([7, 0, 3]), 3, 4, 1, 1000)))
    IO.print(s4(Proof.path(vec([0, 0]), vec([1, 1]), vec([6, 2147483648]), vec([0, 6]), 2, 2, 0, 1000)))
    IO.print(s4(Proof.path(vec([0, 0]), vec([1, 1]), vec([6, 2147483648]), vec([0, 6]), 4000000000, 2, 0, 50)))
    IO.print(s4(Proof.assign(vec([8, 8, 11, 11, 7, 4, 6, 8, 6]), vec([9, 7, 8]), vec([2, 1, 3]), vec([1, 2, 0]), 3, 3, 1000)))
    IO.print(s4(Proof.assign(vec([6, 8, 11, 11, 7, 4, 6, 8, 6]), vec([9, 7, 8]), vec([2, 1, 3]), vec([1, 2, 0]), 3, 3, 1000)))
    IO.print(s4(Proof.assign(vec([8, 8, 11, 11, 7, 4, 6, 8, 6]), vec([8, 7, 8]), vec([2, 1, 3]), vec([1, 2, 0]), 3, 3, 1000)))
    IO.print(s4(Proof.assign(vec([9, 8, 13, 4, 4, 8, 6, 8]), vec([6, 5]), vec([1, 0, 0, 2]), vec([3, 0]), 2, 4, 1000)))
    IO.print(s4(Proof.assign(vec([4, 8, 13, 4, 4, 8, 6, 8]), vec([6, 5]), vec([1, 0, 0, 2]), vec([3, 0]), 2, 4, 1000)))
    IO.print(s4(Proof.assign(vec([9, 8, 13, 4, 4, 8, 6, 8]), vec([5, 5]), vec([1, 0, 0, 2]), vec([3, 0]), 2, 4, 1000)))
    IO.print(s4(Proof.assign(vec([9, 8, 13, 4, 4, 8, 6, 8]), vec([6, 5]), vec([1, 1, 0, 2]), vec([3, 0]), 2, 4, 1000)))
    IO.print(s4(Proof.assign(vec([0, 2, 3, 1, 0, 4, 5, 6, 0]), vec([0, 0, 0]), vec([0, 0, 0]), vec([0, 1, 2]), 3, 3, 1000)))
    IO.print(s4(Proof.assign(vec([0, 2, 3, 1, 0, 4, 5, 6, 0]), vec([0, 0, 0]), vec([0, 0, 0]), vec([4, 1, 2]), 3, 3, 1000)))
    IO.print(s4(Proof.assign(vec([4]), vec([4]), vec([0]), vec([0]), 1, 1, 1000)))
    IO.print(s4(Proof.assign(vec([4]), vec([3]), vec([0]), vec([0]), 1, 1, 1000)))
    IO.print(s4(Proof.assign(vec([4]), vec([4]), vec([0]), vec([2]), 1, 1, 1000)))
    IO.print(s4(Proof.assign(vec([0, 0, 0, 0]), vec([0, 0]), vec([0, 0]), vec([0, 1]), 2, 2, 1000)))
    IO.print(s4(Proof.assign(vec([0, 0, 0, 0]), vec([0, 0]), vec([0, 0]), vec([0, 0]), 2, 2, 1000)))
    IO.print(s4(Proof.assign(vec([0, 4294967295, 4294967295, 0]), vec([0, 0]), vec([0, 0]), vec([0, 1]), 2, 2, 1000)))
    IO.print(s4(Proof.assign(vec([0, 4294967295, 4294967295, 0]), vec([0, 0]), vec([0, 0]), vec([1, 0]), 2, 2, 1000)))
    IO.print(s4(Proof.assign(vec([0, 4294967295, 4294967295, 0]), vec([0, 0]), vec([0, 0]), vec([0, 1]), 2, 2, 8)))
    IO.print(s4(Proof.assign(vec([0, 4294967295, 4294967295, 0]), vec([0, 0]), vec([0, 0]), vec([0, 1]), 2, 2, 7)))
    IO.print(s4(Proof.assign(vec([0, 4294967295, 4294967295, 0]), vec([0, 0]), vec([0, 0]), vec([0, 1]), 65536, 65536, 1000)))
    IO.print(cert(Assign.solve(vec([7, 2, 9, 4, 3, 8, 1, 6, 5, 5, 2, 7, 6, 1, 4, 9]), 4, 4), 4, 4, 1000))
    IO.print(cert(Assign.solve(vec([4, 1, 7, 2, 9, 8, 3, 2, 6, 1, 5, 9, 4, 3, 7]), 3, 5), 3, 5, 1000))
    IO.print(cert(Assign.solve(vec([2, 2, 2, 2, 2, 9, 1, 8, 3, 7, 4, 6, 5, 5, 4, 1, 9, 2, 8, 3, 7, 3, 6, 4, 5]), 5, 5), 5, 5, 1000))
    IO.print(cert(Assign.solve(vec([0, 0, 0, 0]), 2, 2), 2, 2, 1000))
    IO.print(cert(Assign.solve(vec([1, 2, 3, 4, 5, 6]), 3, 2), 3, 2, 1000))
#|ok 994
#|no range
#|no order
#|no value
#|ok 996
#|no dup
#|no range
#|no order
#|no value
#|ok 997
#|no range
#|no order
#|no value
#|ok 999
#|no range
#|no value
#|ok 995
#|no dup
#|no range
#|no order
#|no value
#|ok 0
#|no fuel
#|no fuel
#|ok 991
#|no over
#|no slack
#|no order
#|ok 994
#|no slack
#|no dup
#|no range
#|ok 994
#|no slack
#|no order
#|no dup
#|no range
#|ok 997
#|no over
#|no slack
#|ok 994
#|no fuel
#|ok 991
#|no slack
#|ok 991
#|no slack
#|ok 994
#|no slack
#|no slack
#|ok 993
#|no slack
#|no range
#|ok 996
#|no fuel
#|ok 985
#|no over
#|no slack
#|ok 986
#|no over
#|no slack
#|no slack
#|ok 985
#|no range
#|ok 997
#|no slack
#|no range
#|ok 992
#|no dup
#|ok 992
#|no slack
#|ok 0
#|no fuel
#|no fuel
#|ok 976
#|ok 977
#|ok 965
#|ok 992
#|no range
