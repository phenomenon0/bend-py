# assign, forked: the same 512 instances of 192 x 192 assign.bend solves, cut
# into 2^6 leaves of 8 instances each. Same total work as the sequential file,
# so the two rows of the table read against each other directly.
#
# The batch is the unit and not the instance, because one Jonker-Volgenant
# solve is a sequence of shortest-path searches, each starting from the prices
# the last one left: there is nothing inside it to fork. A batch of independent
# instances is the honest unit of parallelism here, and it is also the real
# workload -- a tracker re-solves the whole assignment every frame, and a
# sweep over parameters or over time windows is a batch of such solves.
#
# Each leaf owns its own matrix. That is not a choice: a Vec holds an Array and
# an Array has one owner, so no two lanes could read one matrix even if the
# algebra let them.
import Base
import ../../../power/vec.bend as Vec
import ../../../power/assign.bend as Assign

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

def mk(+base: U32, +n: U32) -> Vec.Vec:
  mk.go(U32.to_nat(U32.mul(n, n)), base, Vec.new(0))

def rot7(+v: U32) -> U32:
  U32.or(U32.shln(v, 7n), U32.shrn(v, 25n))

# json_par's mixer, one turn sharper for the reason bm25_par states: a leaf
# checksum is itself an acc * 31 + x fold and 31 is -1 mod 32, so a plain
# a * 31 + b tree runs the low bits out and folds every leaf to 0
def mix(+acc: U32, +x: U32) -> U32:
  rot7(U32.add(U32.mul(acc, 31), x))

def take(acc: U32, r: Assign.Sol & U32) -> U32:
  (s, k) = r
  mix(acc, k)

def one(acc: U32, r: Vec.Vec & Assign.Sol) -> U32:
  (c, s) = r
  take(acc, Assign.cost(s))

def go(fuel: Nat, +b: U32, +n: U32, acc: U32) -> U32:
  match fuel:
    case 0n:
      acc
    case 1n++q:
      go(q, U32.inc(b), n, one(acc, Assign.solve(mk(U32.shln(b, 16n), n), n, n)))

# one leaf is one instance, so the tree is 2^9 wide and every leaf holds a
# different matrix. The first draft bundled eight instances a leaf into 2^6
# leaves and ran 3.5x on sixteen threads against this file's 6.3x: a
# Jonker-Volgenant solve's cost swings with its data -- how long the augmenting
# paths turn out to be is a property of the matrix -- so a leaf that bundles
# eight solves bundles their variance too, and the slowest leaf sets the clock.
# One solve a leaf hands that variance to the scheduler instead.
def shard(+s: U32) -> U32:
  go(1n, s, 192, 0)

def par(d: Nat, +s: U32) -> U32:
  match d:
    case 0n:
      shard(s)
    case 1n++p:
      +w = U32.shln(1, p)
      a b = par(p, s) par(p, U32.add(s, w))
      mix(a, b)

def main() -> U32:
  par(9n, 0)
