# gemv, sequential: one 512 x 512 weight matrix as a flat Array<F32>, and 512
# successive decode steps against it -- each step a fresh length-512 activation
# vector, a full matrix-vector product, and a length-512 result written out and
# read back. 134 million multiply-adds through one flat block, which is the
# number this bench is about; it is the skeleton of a decode step with the
# nonlinearity taken out, and the question it exists to answer is what a dense
# F32 loop costs in Bend against the same loop in C.
#
# The row dot product is power/knn.bend's `ip`, not a copy of it written here.
# Knn.Flat already IS this layout -- n rows of d floats row major in one flat
# Array<F32>, one owner, an index loop and no allocation in the inner loop --
# and a second hand-typed copy would measure the same loop while being free to
# drift from it. The matrix is a Flat of 512 rows; the activation is a Flat of
# one row, so `ip(w, i, x, 0)` is row i of the weights against the vector.
#
# The result vector is materialized rather than folded on the fly, because that
# is the shape being asked about: a decode step writes activations that the next
# op reads. Dropping it is safe -- an F32 cell is w32, which takes the packed
# block and is never walked as a Term (see docs/omen/f64-drop-c-backend.md).
#
# There is no fork in this file, so its 1T and 16T columns are the same run
# twice; gemv_par.bend is where the threads are.
import Base
import ../../../power/knn.bend as Knn

# knn.bend's hash and scaling: a value in [-32, 32) in steps of 1/128, exact in
# F32, so Bend and the C twin start from identical floats. The thirteen bits
# come off the TOP of the hash, so a base that is a multiple of 2^13 -- which
# every base here is -- still moves the value.
def h(+p: U32) -> U32:
  U32.xor(U32.mul(U32.inc(p), 2654435761), U32.shrn(p, 3n))

def v(+p: U32) -> F32:
  F32.div(F32.sub(U32.to_f32(U32.shrn(h(p), 19n)), 4096.0), 128.0)

def mk.go(fuel: Nat, +p: U32, f: Knn.Flat) -> Knn.Flat:
  match fuel:
    case 0n:
      f
    case 1n++q:
      mk.go(q, U32.inc(p), Knn.push(f, v(p)))

def mk(+base: U32, +n: U32, +d: U32, depth: Nat) -> Knn.Flat:
  mk.go(U32.to_nat(U32.mul(n, d)), base, Knn.sized(d, depth))

def rot7(+v: U32) -> U32:
  U32.or(U32.shln(v, 7n), U32.shrn(v, 25n))

# gemv_par folds shard checksums as a tree, and a plain acc * 31 + b tree runs
# the low bits out (31 is -1 mod 32, json_par's finding); one rotate a step
# keeps it alive. The two files use the same mixer so their rows are comparable.
def mix(+acc: U32, +x: U32) -> U32:
  rot7(U32.add(U32.mul(acc, 31), x))

# -- one decode step ---------------------------------------------------------

# the weights, the activation and the result: three Arrays, three owners, so
# the row loop carries all three and hands them back
type Step is Type:
  Step{w: Knn.Flat, x: Knn.Flat, y: Knn.Flat}

def step.put(y: Knn.Flat, r: Knn.Flat & Knn.Flat & F32) -> Step:
  (w, x, s) = r
  Step{w, x, Knn.push(y, s)}

def step.go(fuel: Nat, +i: U32, s: Step) -> Step:
  match fuel:
    case 0n:
      s
    case 1n++p:
      match s:
        case Step{w, x, y}:
          step.go(p, U32.inc(i), step.put(y, Knn.ip(w, i, x, 0)))

# -- the checksum over one result vector -------------------------------------

# the bits, not the number: no float reaches a printed line, and F32.bits is
# exact where any decimal rendering is libm's
type Sum is Type:
  Sum{y: Knn.Flat, acc: U32}

def sum.one(+acc: U32, r: Knn.Flat & F32) -> Sum:
  (y, s) = r
  Sum{y, mix(acc, F32.bits(s))}

def sum.go(fuel: Nat, +i: U32, x: Sum) -> Sum:
  match fuel:
    case 0n:
      x
    case 1n++p:
      match x:
        case Sum{y, acc}:
          sum.go(p, U32.inc(i), sum.one(acc, Knn.cell(y, i)))

# `y` has no further use: the result vector is dropped here
def sum.out(x: Sum) -> U32:
  match x:
    case Sum{y, acc}:
      acc

# -- the run: one matrix, many steps -----------------------------------------

type Run is Type:
  Run{w: Knn.Flat, acc: U32}

# `x` has no further use either: the activation is dropped with the step
def run.done(+m: U32, +acc: U32, s: Step) -> Run:
  match s:
    case Step{w, x, y}:
      Run{w, sum.out(sum.go(U32.to_nat(m), 0, Sum{y, acc}))}

def run.step(w: Knn.Flat, +base: U32, +m: U32, +k: U32, +dm: Nat, +dk: Nat, +acc: U32) -> Run:
  run.done(m, acc, step.go(U32.to_nat(m), 0, Step{w, mk(base, 1, k, dk), Knn.sized(1, dm)}))

def run.go(fuel: Nat, +base: U32, +m: U32, +k: U32, +dm: Nat, +dk: Nat, x: Run) -> Run:
  match fuel:
    case 0n:
      x
    case 1n++p:
      match x:
        case Run{w, acc}:
          run.go(p, U32.add(base, k), m, k, dm, dk, run.step(w, base, m, k, dm, dk, acc))

def run.out(x: Run) -> U32:
  match x:
    case Run{w, acc}:
      acc

# `steps` decode steps of an m x k matrix-vector product, the weights hashed
# from wbase. The activation hashes start 2^30 past the weights' and advance by
# k a step, so no two steps share a vector and no vector is a matrix row; they
# do not depend on wbase, because an activation is broadcast to every shard
# while the weight rows are what a shard owns (gemv_par.bend).
def gemv(steps: Nat, +wbase: U32, +m: U32, +k: U32, +dmat: Nat, +dm: Nat, +dk: Nat) -> U32:
  run.out(run.go(steps, 1073741824, m, k, dm, dk, Run{mk(wbase, m, k, dmat), 0}))

def main() -> U32:
  gemv(512n, 0, 512, 512, 18n, 9n, 9n)
