# assign, sequential: 512 independent 192 x 192 cost matrices, each solved to a
# minimum-cost perfect matching by Jonker-Volgenant shortest augmenting path.
# That is the number this bench is about -- 18.9 million cells read and repriced
# per instance in the worst case, and far fewer in fact, because on random costs
# the augmenting path is short and the row loop ends after a handful of scans.
#
# The checksum folds the COST of each matching and not the matching itself:
# costs in 0..63 over 192 rows make ties dense, several permutations reach the
# optimum, and which one a solver lands on is its tie-break rather than its
# answer. The cost is the answer, and twin_assign.c has to reproduce it exactly.
#
# There is no fork in this file, so its 1T and 16T columns are the same run
# twice; assign_par.bend is where the threads are.
import Base
import ../../../power/vec.bend as Vec
import ../../../power/assign.bend as Assign

# the same hash the C twin uses, and the same shift: a cost in 0..63, so 192
# rows times 63 is 12,096 -- three orders under assign's 2^31 ceiling, which is
# where the reduced-cost arithmetic would start to wrap
def h(+p: U32) -> U32:
  U32.xor(U32.mul(U32.inc(p), 2654435761), U32.shrn(p, 3n))

def cell(+p: U32) -> U32:
  U32.shrn(h(p), 26n)

def mk.go(fuel: Nat, +p: U32, c: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      c
    case 1n++q:
      mk.go(q, U32.inc(p), Vec.push(c, cell(p)))

# instance b draws its n*n cells from the hash run at b << 16, so no two
# instances share a cell while n <= 256
def mk(+base: U32, +n: U32) -> Vec.Vec:
  mk.go(U32.to_nat(U32.mul(n, n)), base, Vec.new(0))

def rot7(+v: U32) -> U32:
  U32.or(U32.shln(v, 7n), U32.shrn(v, 25n))

def mix(+acc: U32, +x: U32) -> U32:
  rot7(U32.add(U32.mul(acc, 31), x))

def take(acc: U32, r: Assign.Sol & U32) -> U32:
  (s, k) = r
  mix(acc, k)

# the matrix and the Sol are both dropped here: nothing downstream reads the
# prices, so the only thing that survives a solve is its cost
def one(acc: U32, r: Vec.Vec & Assign.Sol) -> U32:
  (c, s) = r
  take(acc, Assign.cost(s))

def go(fuel: Nat, +b: U32, +n: U32, acc: U32) -> U32:
  match fuel:
    case 0n:
      acc
    case 1n++q:
      go(q, U32.inc(b), n, one(acc, Assign.solve(mk(U32.shln(b, 16n), n), n, n)))

def main() -> U32:
  go(512n, 0, 192, 0)
