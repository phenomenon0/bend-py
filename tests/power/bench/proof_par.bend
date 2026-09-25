# proof, forked: the same 2,048 checks proof.bend runs, cut into 2^7 leaves of
# one certificate each. Same total work as the sequential file, so the two rows
# of the table read against each other directly.
#
# A leaf is one certificate and its sixteen checks. Unlike assign_par, where a
# leaf's cost swings with its matrix -- how long the augmenting paths turn out
# to be is a property of the data -- every leaf here costs exactly the same,
# because a check walks all nr*nc cells whatever the verdict. That is not an
# accident of this bench: a checker whose running time told you something about
# its answer would be a checker with a timing side channel, and the budget is
# taken up front for the same reason.
#
# Each leaf owns its own certificate. That is not a choice: a Vec holds an
# Array and an Array has one owner, so no two lanes could read one matrix even
# if the algebra let them.
import Base
import ../../../power/vec.bend as Vec
import ../../../power/proof.bend as Proof

# the same hash and the same shift the assign bench uses, so the two rows draw
# their numbers from one stream: a value in 0..63
def h(+p: U32) -> U32:
  U32.xor(U32.mul(U32.inc(p), 2654435761), U32.shrn(p, 3n))

def d6(+p: U32) -> U32:
  U32.shrn(h(p), 26n)

def rot7(+v: U32) -> U32:
  U32.or(U32.shln(v, 7n), U32.shrn(v, 25n))

def mix(+acc: U32, +x: U32) -> U32:
  rot7(U32.add(U32.mul(acc, 31), x))

# three disjoint runs of the hash an instance: rows at base, columns at
# base+4096, cells at base+8192. 192*192 is 36,864, so the cells end at
# base+45,055 and the next instance starts at base+65,536 -- no two instances
# and no two roles ever share a draw.
def up(+base: U32, +i: U32) -> U32:
  U32.add(64, d6(U32.add(base, i)))

def wp(+base: U32, +j: U32) -> U32:
  d6(U32.add(base, U32.add(4096, j)))

# the matched column of row i. 97 and 192 are coprime, so i -> 97i+13 mod 192
# is a bijection, which is what makes the matching a matching and what makes
# the free-column pass vacuous -- every column is held.
def g(+i: U32) -> U32:
  U32.mod(U32.add(U32.mul(97, i), 13), 192)

# zero on the matched cell, at least one everywhere else: c[i][j] = u[i] - w[j]
# + slack then satisfies u[i] <= c[i][j] + w[j] for every cell and with
# equality exactly on the matched one. u is at least 64 and w at most 63, so
# the subtraction never wraps and every cost lands in 1..191.
def sk(+base: U32, +i: U32, +j: U32, +gi: U32) -> U32:
  Bool.pick(U32, U32.is_eq(j, gi), 0,
    U32.inc(d6(U32.add(base, U32.add(8192, U32.add(U32.mul(i, 192), j))))))

def row.go(fuel: Nat, +base: U32, +ui: U32, +i: U32, +j: U32, +gi: U32, c: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      c
    case 1n++q:
      row.go(q, base, ui, i, U32.inc(j), gi,
        Vec.push(c, U32.add(U32.sub(ui, wp(base, j)), sk(base, i, j, gi))))

def mk.go(fuel: Nat, +base: U32, +i: U32, c: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      c
    case 1n++q:
      mk.go(q, base, U32.inc(i), row.go(192n, base, up(base, i), i, 0, g(i), c))

def uv.go(fuel: Nat, +base: U32, +i: U32, v: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      v
    case 1n++q:
      uv.go(q, base, U32.inc(i), Vec.push(v, up(base, i)))

def wv.go(fuel: Nat, +base: U32, +j: U32, v: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      v
    case 1n++q:
      wv.go(q, base, U32.inc(j), Vec.push(v, wp(base, j)))

def mv.go(fuel: Nat, +i: U32, v: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      v
    case 1n++q:
      mv.go(q, U32.inc(i), Vec.push(v, g(i)))

# the damage, one property an instance and never two: a cost the prices do not
# dominate (Over), a row price its matched cell no longer meets (Slack), a row
# holding a column that does not exist (Range). Instances 0..4 modulo 8 are
# left alone, so three quarters of the batch is a true certificate.
def cor.c(+k: U32, +v: U32, q: Vec.Vec & U32) -> Vec.Vec:
  (c, c0) = q
  Vec.put(c, 0, Bool.pick(U32, U32.is_eq(k, 5), v, c0))

def cor.u(+k: U32, q: Vec.Vec & U32) -> Vec.Vec:
  (u, +u0) = q
  Vec.put(u, 0, Bool.pick(U32, U32.is_eq(k, 6), U32.sub(u0, 1), u0))

def cor.m(+k: U32, q: Vec.Vec & U32) -> Vec.Vec:
  (mt, m0) = q
  Vec.put(mt, 0, Bool.pick(U32, U32.is_eq(k, 7), 193, m0))

type St is Type:
  St{c: Vec.Vec, u: Vec.Vec, w: Vec.Vec, mt: Vec.Vec, acc: U32}

def inst(+base: U32, +k: U32, acc: U32) -> St:
  St{cor.c(k, U32.sub(U32.sub(up(base, 0), wp(base, 0)), 1), Vec.at(mk.go(192n, base, 0, Vec.new(0)), 0)),
    cor.u(k, Vec.at(uv.go(192n, base, 0, Vec.new(0)), 0)),
    wv.go(192n, base, 0, Vec.new(0)),
    cor.m(k, Vec.at(mv.go(192n, 0, Vec.new(0)), 0)), acc}

# Done carries the budget the check did not need, which pins the accounting;
# Fail carries the reason, lifted clear of any budget so the two never collide.
def bad(b: Proof.Bad) -> U32:
  match b:
    case Proof.Fuel{}:
      1
    case Proof.Range{}:
      2
    case Proof.Dup{}:
      3
    case Proof.Order{}:
      4
    case Proof.Value{}:
      5
    case Proof.Over{}:
      6
    case Proof.Slack{}:
      7

def tag(r: Result<&2, &2, Proof.Bad, U32>) -> U32:
  match r:
    case Done{left}:
      left
    case Fail{b}:
      U32.add(4026531840, bad(b))

def step(acc: U32, q: Vec.Vec & Vec.Vec & Vec.Vec & Vec.Vec & Result<&2, &2, Proof.Bad, U32>) -> St:
  (c, u, w, mt, r) = q
  St{c, u, w, mt, mix(acc, tag(r))}

# the witness survives its own check -- Proof.assign hands all four Vecs back --
# so re-checking is free of any rebuild, which is what lets the build amortize
def reps(fuel: Nat, x: St) -> St:
  match fuel:
    case 0n:
      x
    case 1n++p:
      match x:
        case St{c, u, w, mt, acc}:
          reps(p, step(acc, Proof.assign(c, u, w, mt, 192, 192, 40000)))

def out(x: St) -> U32:
  match x:
    case St{c, u, w, mt, acc}:
      acc

def shard(+b: U32) -> U32:
  out(reps(16n, inst(U32.shln(b, 16n), U32.and(b, 7), 0)))

def par(d: Nat, +s: U32) -> U32:
  match d:
    case 0n:
      shard(s)
    case 1n++p:
      +w = U32.shln(1, p)
      a b = par(p, s) par(p, U32.add(s, w))
      mix(a, b)

def main() -> U32:
  par(7n, 0)
