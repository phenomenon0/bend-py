# select, sequential: 32 grounds of 1,024 candidates over 1,024 weighted
# elements each -- 33.5 million similarity cells -- every one of them packed
# under a cost budget of 6,000 by lazy greedy. A ground's first round alone is
# 1.05 million weighted max-ops, and every round after it is one more
# 1,024-term rescan of whichever candidate held the best stale bound, which is
# the whole claim the lazy rule makes: a plain greedy would rescan all 1,024
# every time.
#
# The grounds are clustered on purpose (32 clusters, so ~32 near-duplicates
# each). A clustered ground is the adversarial one for lazy greedy, not the easy
# one: taking a cluster's first member collapses the bound of every other member
# at once, and a collapsed bound is exactly what forces a reinsertion instead of
# a take. A uniform ground would make the bench look faster and mean less.
#
# The checksum folds `left` -- the pops each run actually spent -- so the C twin
# has to reproduce the lazy schedule pop for pop, not merely reach the same set.
# Two implementations can agree on the answer and disagree on the work, and the
# work is what this file measures.
#
# There is no fork in this file, so its 1T and 16T columns are the same run
# twice; select_par.bend is where the threads are.
import Base
import ../../../power/vec.bend as Vec
import ../../../power/select.bend as Select

# the fixture's ground, and the C twin's: a cluster id, a weight in
# [1024, 4097), a cost in [1, 13), and a similarity that is one() on the
# diagonal, a high band inside a cluster and a low band across clusters
def h(+p: U32) -> U32:
  U32.xor(U32.mul(U32.inc(p), 2654435761), U32.shrn(p, 3n))

def mix2(a: U32, b: U32) -> U32:
  h(U32.xor(U32.mul(a, 2654435761), b))

def cl(s: U32, nc: U32, i: U32) -> U32:
  U32.mod(U32.shrn(mix2(U32.add(s, 17), i), 8n), nc)

def wt(s: U32, i: U32) -> U32:
  U32.add(1024, U32.mod(U32.shrn(mix2(U32.add(s, 101), i), 7n), 3073))

def ct(s: U32, i: U32) -> U32:
  U32.add(1, U32.mod(U32.shrn(mix2(U32.add(s, 211), i), 9n), 12))

def sm.g(+g: U32, same: Bool) -> U32:
  match same:
    case True{}:
      U32.add(2600, U32.mod(g, 1200))
    case False{}:
      U32.mod(g, 700)

def sm.ne(+s: U32, +nc: U32, +j: U32, +i: U32) -> U32:
  sm.g(U32.shrn(mix2(U32.add(U32.mul(s, 7), U32.mul(j, 65537)), i), 5n),
    U32.is_eq(cl(s, nc, j), cl(s, nc, i)))

def sm.if(s: U32, nc: U32, j: U32, i: U32, diag: Bool) -> U32:
  match diag:
    case True{}:
      4096
    case False{}:
      sm.ne(s, nc, j, i)

def sm(s: U32, nc: U32, +j: U32, +i: U32) -> U32:
  sm.if(s, nc, j, i, U32.is_eq(j, i))

def gs(fuel: Nat, +p: U32, +s: U32, +nc: U32, +n: U32, v: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      v
    case 1n++q:
      gs(q, U32.inc(p), s, nc, n, Vec.push(v, sm(s, nc, U32.div(p, n), U32.mod(p, n))))

def gv(fuel: Nat, +i: U32, +s: U32, v: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      v
    case 1n++q:
      gv(q, U32.inc(i), s, Vec.push(v, wt(s, i)))

def gc(fuel: Nat, +i: U32, +s: U32, v: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      v
    case 1n++q:
      gc(q, U32.inc(i), s, Vec.push(v, ct(s, i)))

def ground(+s: U32, +n: U32, nc: U32) -> Select.Ground:
  Select.Ground{n, gs(U32.to_nat(U32.mul(n, n)), 0, s, nc, n, Vec.new(0)),
    gv(U32.to_nat(n), 0, s, Vec.new(0)), gc(U32.to_nat(n), 0, s, Vec.new(0))}

def rot7(+v: U32) -> U32:
  U32.or(U32.shln(v, 7n), U32.shrn(v, 25n))

# json_par's mixer, one turn sharper for the reason bm25_par states: 31 is -1
# mod 32, so a plain acc * 31 + x fold runs the low bits out
def mix(+acc: U32, +x: U32) -> U32:
  rot7(U32.add(U32.mul(acc, 31), x))

def fold(xs: List<&2, Select.Pick>, acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case Con{Select.Pick{i, g, c}, t}:
      fold(t, mix(acc, U32.xor(U32.add(U32.mul(i, 31), c), g)))

# the four counters and then every pick in the order it was taken
def sum(r: Select.Run) -> U32:
  match r:
    case Select.Run{l, m, t, c, p, w}:
      fold(p, mix(mix(mix(mix(0, l), m), t), c))

def run(x: Select.Ground & Select.Run) -> Select.Run:
  (g, r) = x
  r

# one shard is one whole selection problem: its own ground, its own budget, its
# own answer. The limit is the pop ceiling power/select.bend proves -- n
# removals and at most n reinserts an epoch -- so it never binds and every run
# here stops on its budget.
def shard.n(+n: U32, budget: U32, nc: U32, s: U32) -> U32:
  sum(run(Select.budgeted(ground(s, n, nc), [], budget,
    U32.add(U32.add(U32.mul(n, n), U32.mul(n, 2)), 4))))

# the shards differ -- 7s never lands on a multiple of 65537 for s under 128, so
# no two shards draw the same similarity row -- and the fold is over 32 distinct
# checksums and not 32 copies of one
def shard(+s: U32) -> U32:
  shard.n(1024, 6000, 32, s)

def go(fuel: Nat, +s: U32, acc: U32) -> U32:
  match fuel:
    case 0n:
      acc
    case 1n++p:
      go(p, U32.inc(s), mix(acc, shard(s)))

def main() -> U32:
  go(32n, 0, 0)
