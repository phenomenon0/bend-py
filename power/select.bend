# Select: the pack, not the top K. Ranking hands back the K items that each
# score highest, which over any real candidate pool is K near-duplicates: the
# second copy of the best chunk scores almost exactly what the first one did.
# apricot's answer, and this file's, is to score a *set* by how much of the
# ground it covers and to take the item with the most new coverage per unit of
# cost -- facility location under a lazy greedy, which is the standard budgeted
# submodular selection and the one a context packer actually wants.
#
#   f(S) = sum over ground elements i of  val[i] * max over j in S of sim[j][i]
#
# `sim` is a row a *candidate*: row j says how well candidate j covers each
# ground element i, so it need not be symmetric and a candidate need not cover
# itself best (the fixture's does, at `one()`). `val[i]` weights the element
# being covered -- what it costs to leave i uncovered -- and is the only place a
# per-item prior enters. The marginal gain of j against a coverage vector cov is
#
#   d(j) = sum_i val[i] * max(0, sim[j][i] - cov[i])   >> 12, one term at a time
#
# which is non-increasing in cov, term by term, which is what makes the lazy
# bound below sound.
#
# The lazy (accelerated) greedy is Minoux's, and it is the reason this is
# affordable: a gain only ever falls, so a *stale* gain is an upper bound. Keep
# the candidates in a heap keyed by their last computed gain, pop the top,
# recompute it, and if the fresh value still beats the next item's stale bound,
# take it -- every other candidate's true gain is under its own bound, which is
# under this one. Otherwise put it back at its fresh value and pop again. A
# round costs one O(n) recomputation instead of n of them, and the answer is the
# plain greedy's, exactly, not approximately: tests/power/select.bend pins that
# against an O(n^2) CPython greedy that has never heard of a heap.
#
# Everything is fixed point U32 at 2^12 (`one()`), not F32 -- so the oracle
# comparison is exact rather than tolerance-based, and because an Array<F64>
# written from a recursive loop is corrupted by the C backend today. Selection
# only ever *compares* gains; it never needs them accurate.
#
# The two budgets in this file are different things and do not compose into one:
#
#   budget  the cost ceiling on the answer     charged per item taken
#   limit   the ceiling on work                charged per heap pop
#
# `budget` bounds what is selected, `limit` bounds how long the search for it
# may run, and either may bind first -- `why` says which did. `limit` is the
# package's own convention from lane 1 (an unbounded loop takes a limit last and
# hands the remainder back first); it cannot ride in a Result here because the
# answer comes back beside a Ground, whose kind is Type, so `Run` carries `left`
# in its first field and `why` plays the part of the error arm. power/json.bend
# made the same move for the same reason.
import Base
import ./vec.bend as Vec
import ./heap.bend as Heap

# -- the fixed point ---------------------------------------------------------

# 1.0. A similarity, a coverage and a weight are all in [0, one()]; a gain is
# not -- it is a sum over the ground set.
def one() -> U32:
  4096

# the largest gain the ratio key can tell apart. 2^24 - 1 << 8 is under 2^32, so
# the shift below cannot wrap; with weights at one() that is a ground set of
# 4,096 fully uncovered elements, and past it the key stops discriminating.
# ponytail: a saturating key, not a wider one -- the upgrade is a 64-bit heap
# key, which is a change to power/heap.bend and not to this file.
def top() -> U32:
  16777215

# ratio: gain per unit cost, the quantity budgeted greedy maximizes. Scaled by
# 2^8 so that a cheap small gain still outranks an expensive one, and floored at
# 1 for any positive gain, so that `ratio == 0` means `gain == 0` and nothing
# else -- the loop below stops on a zero gain and must not be told a real one is
# zero because its cost was large. Both halves are monotone in the gain, which
# is what keeps a stale ratio an upper bound on a fresh one.
def ratio.pos(g: U32, c: U32) -> U32:
  U32.max(1, U32.div(U32.shln(U32.min(g, top()), 8n), U32.max(c, 1)))

def ratio.if(g: U32, c: U32, zero: Bool) -> U32:
  match zero:
    case True{}:
      0
    case False{}:
      ratio.pos(g, c)

def ratio(+g: U32, c: U32) -> U32:
  ratio.if(g, c, U32.is_zero(g))

# Heap is a min-heap over (key, val), so a max-heap on the ratio is the
# complement of the ratio, and the val is the candidate index -- which settles
# every tie at the smallest index, on both sides of the fixture.
def key(r: U32) -> U32:
  U32.sub(4294967295, r)

# -- the ground --------------------------------------------------------------

# n candidates over n ground elements. `sim` is n * n cells, row major by
# candidate: cell j * n + i is how much candidate j covers element i. `val` and
# `cost` are n cells each. The caller owns the shape: a short `sim` reads
# wrapped cells rather than failing, the same rule Vec.at states.
type Ground is Type:
  Ground{n: U32, sim: Vec.Vec, val: Vec.Vec, cost: Vec.Vec}

def of_lists(n: U32, sim: List<&2, U32>, val: List<&2, U32>, cost: List<&2, U32>) -> Ground:
  Ground{n, Vec.from_list(sim, Vec.new(0)), Vec.from_list(val, Vec.new(0)),
    Vec.from_list(cost, Vec.new(0))}

def size(g: Ground) -> Ground & U32:
  match g:
    case Ground{+n, sim, val, cost}:
      (Ground{n, sim, val, cost}, n)

# -- the answer --------------------------------------------------------------

# why an item is in the answer, not only that it is: `gain` is the marginal
# coverage it added at the moment it was taken, which is the witness a caller
# needs to explain or to re-rank a pack. It is not the item's standalone value
# and the two differ by exactly what the earlier picks already covered.
type Pick is Data:
  Pick{item: U32, gain: U32, cost: U32}

type Stop is Data:
  Full{}
  Dry{}
  Over{}
  Bad{}

def show(s: Stop) -> String:
  match s:
    case Full{}:
      "full"
    case Dry{}:
      "dry"
    case Over{}:
      "over"
    case Bad{}:
      "bad"

# `halted` is the two arms that refuse a request outright, as opposed to the two
# that end a run: a malformed `required` list, or one that does not fit.
def halted(s: Stop) -> Bool:
  match s:
    case Full{}:
      False{}
    case Dry{}:
      False{}
    case Over{}:
      True{}
    case Bad{}:
      True{}

# left: pops still allowed. room: budget still unspent. total: the sum of every
# pick's own gain, which is f(S) because the gains telescope. count: how many.
type Run is Data:
  Run{left: U32, room: U32, total: U32, count: U32, picks: List<&2, Pick>, why: Stop}

def left(r: Run) -> U32:
  match r:
    case Run{l, m, t, c, p, w}:
      l

def room(r: Run) -> U32:
  match r:
    case Run{l, m, t, c, p, w}:
      m

def total(r: Run) -> U32:
  match r:
    case Run{l, m, t, c, p, w}:
      t

def count(r: Run) -> U32:
  match r:
    case Run{l, m, t, c, p, w}:
      c

def chosen(r: Run) -> List<&2, Pick>:
  match r:
    case Run{l, m, t, c, p, w}:
      p

def why(r: Run) -> Stop:
  match r:
    case Run{l, m, t, c, p, w}:
      w

def mark(r: Run, s: Stop) -> Run:
  match r:
    case Run{l, m, t, c, p, w}:
      Run{l, m, t, c, p, s}

# one pop charged. A required item costs no pop: it was never searched for.
def tick(r: Run) -> Run:
  match r:
    case Run{l, m, t, c, p, w}:
      Run{U32.sub(l, 1), m, t, c, p, w}

def add(r: Run, j: U32, +g: U32, +x: U32) -> Run:
  match r:
    case Run{l, m, t, c, p, w}:
      Run{l, U32.sub(m, x), U32.add(t, g), U32.inc(c), Con{Pick{j, g, x}, p}, w}

def rev.go(xs: List<&2, Pick>, acc: List<&2, Pick>) -> List<&2, Pick>:
  match xs:
    case Nil{}:
      acc
    case Con{x, t}:
      rev.go(t, Con{x, acc})

def rev(r: Run) -> Run:
  match r:
    case Run{l, m, t, c, p, w}:
      Run{l, m, t, c, rev.go(p, []), w}

# -- the marginal gain -------------------------------------------------------

# the three vectors the gain loop owns, and its accumulator first, so the
# accumulator may be marked used-twice (a + is refused on a pattern's last
# field, and the caller both keeps the gain and prices it)
type Gs is Type:
  Gs{acc: U32, sim: Vec.Vec, val: Vec.Vec, cov: Vec.Vec}

# one ground element's share: what this candidate covers past what is already
# covered, priced by the element's own weight. The shift is per term and not on
# the sum, so the term never exceeds one() and a ground set of 2^20 elements
# still cannot wrap the accumulator -- and the CPython oracle sums the same
# integers in the same order.
def term(vi: U32, si: U32, +ci: U32, acc: U32) -> U32:
  U32.add(acc, U32.shrn(U32.mul(vi, U32.sub(U32.max(si, ci), ci)), 12n))

def gain.cov(sim: Vec.Vec, val: Vec.Vec, vi: U32, si: U32, acc: U32, r: Vec.Vec & U32) -> Gs:
  (cov, ci) = r
  Gs{term(vi, si, ci, acc), sim, val, cov}

def gain.val(sim: Vec.Vec, cov: Vec.Vec, i: U32, si: U32, acc: U32, r: Vec.Vec & U32) -> Gs:
  (val, vi) = r
  gain.cov(sim, val, vi, si, acc, Vec.at(cov, i))

def gain.sim(val: Vec.Vec, cov: Vec.Vec, +i: U32, acc: U32, r: Vec.Vec & U32) -> Gs:
  (sim, si) = r
  gain.val(sim, cov, i, si, acc, Vec.at(val, i))

def gain.one(+i: U32, base: U32, x: Gs) -> Gs:
  match x:
    case Gs{acc, sim, val, cov}:
      gain.sim(val, cov, i, acc, Vec.at(sim, U32.add(base, i)))

def gain.go(fuel: Nat, +i: U32, +base: U32, x: Gs) -> Gs:
  match fuel:
    case 0n:
      x
    case 1n++p:
      gain.go(p, U32.inc(i), base, gain.one(i, base, x))

def gain(sim: Vec.Vec, val: Vec.Vec, cov: Vec.Vec, +n: U32, j: U32) -> Gs:
  gain.go(U32.to_nat(n), 0, U32.mul(j, n), Gs{0, sim, val, cov})

# -- taking an item ----------------------------------------------------------

type Cv is Type:
  Cv{sim: Vec.Vec, cov: Vec.Vec}

def cover.put(sim: Vec.Vec, i: U32, si: U32, r: Vec.Vec & U32) -> Cv:
  (cov, ci) = r
  Cv{sim, Vec.put(cov, i, U32.max(si, ci))}

def cover.sim(cov: Vec.Vec, +i: U32, r: Vec.Vec & U32) -> Cv:
  (sim, si) = r
  cover.put(sim, i, si, Vec.at(cov, i))

def cover.one(+i: U32, base: U32, x: Cv) -> Cv:
  match x:
    case Cv{sim, cov}:
      cover.sim(cov, i, Vec.at(sim, U32.add(base, i)))

def cover.go(fuel: Nat, +i: U32, +base: U32, x: Cv) -> Cv:
  match fuel:
    case 0n:
      x
    case 1n++p:
      cover.go(p, U32.inc(i), base, cover.one(i, base, x))

# cov[i] <- max(cov[i], sim[j][i]) for every i. Taking an item never lowers a
# coverage, which is the other half of why a stale gain is an upper bound.
def cover(sim: Vec.Vec, cov: Vec.Vec, +n: U32, j: U32) -> Cv:
  cover.go(U32.to_nat(n), 0, U32.mul(j, n), Cv{sim, cov})

# -- the whole state ---------------------------------------------------------

# `taken` is one flag a candidate, and it exists for exactly two jobs: to keep a
# repeated `required` index from being charged twice, and to keep the required
# items out of the heap. (They would also exclude themselves -- a just-taken
# item's gain against its own coverage is 0 by construction -- but a flag says
# so where an invariant only implies it.) `run` is second, not last, because the
# state is read and rebuilt in the same breath everywhere below.
type St is Type:
  St{n: U32, run: Run, sim: Vec.Vec, val: Vec.Vec, cost: Vec.Vec, cov: Vec.Vec,
    taken: Vec.Vec, h: Heap.Heap}

type Step is Type:
  Fin{s: St}
  Go{s: St}

def zeros.go(fuel: Nat, v: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      v
    case 1n++p:
      zeros.go(p, Vec.push(v, 0))

def zeros(n: U32) -> Vec.Vec:
  zeros.go(U32.to_nat(n), Vec.new(0))

# -- the required items ------------------------------------------------------

# charged first and in the order given, before the greedy ever runs, so a
# required item's gain is measured against only the required items ahead of it
# and the budget it eats is gone before a single candidate is scored.
def force.take(n: U32, val: Vec.Vec, cost: Vec.Vec, taken: Vec.Vec, h: Heap.Heap,
  r: Run, +j: U32, cj: U32, gj: U32, x: Cv) -> St:
  match x:
    case Cv{sim, cov}:
      St{n, add(r, j, gj, cj), sim, val, cost, cov, Vec.put(taken, j, 1), h}

def force.gn(+n: U32, cost: Vec.Vec, taken: Vec.Vec, h: Heap.Heap, r: Run, +j: U32,
  cj: U32, x: Gs) -> St:
  match x:
    case Gs{gj, sim, val, cov}:
      force.take(n, val, cost, taken, h, r, j, cj, gj, cover(sim, cov, n, j))

def force.fit(+n: U32, r: Run, sim: Vec.Vec, val: Vec.Vec, cost: Vec.Vec, cov: Vec.Vec,
  taken: Vec.Vec, h: Heap.Heap, +j: U32, cj: U32, ok: Bool) -> St:
  match ok:
    case True{}:
      force.gn(n, cost, taken, h, r, j, cj, gain(sim, val, cov, n, j))
    case False{}:
      St{n, mark(r, Over{}), sim, val, cost, cov, taken, h}

def force.cst(n: U32, +r: Run, sim: Vec.Vec, val: Vec.Vec, cov: Vec.Vec,
  taken: Vec.Vec, h: Heap.Heap, j: U32, x: Vec.Vec & U32) -> St:
  (cost, c0) = x
  +cj = U32.max(c0, 1)
  force.fit(n, r, sim, val, cost, cov, taken, h, j, cj, U32.is_le(cj, room(r)))

def force.dup(n: U32, r: Run, sim: Vec.Vec, val: Vec.Vec, cost: Vec.Vec, cov: Vec.Vec,
  taken: Vec.Vec, h: Heap.Heap, +j: U32, free: Bool) -> St:
  match free:
    case True{}:
      force.cst(n, r, sim, val, cov, taken, h, j, Vec.at(cost, j))
    case False{}:
      St{n, mark(r, Bad{}), sim, val, cost, cov, taken, h}

def force.tk(n: U32, r: Run, sim: Vec.Vec, val: Vec.Vec, cost: Vec.Vec, cov: Vec.Vec,
  h: Heap.Heap, j: U32, x: Vec.Vec & U32) -> St:
  (taken, t) = x
  force.dup(n, r, sim, val, cost, cov, taken, h, j, U32.is_zero(t))

# an index at or past n, or one already taken, is a malformed request and says
# so; it is not silently dropped, because a caller that asked for an item it
# cannot have wants to hear about it
def force.range(n: U32, r: Run, sim: Vec.Vec, val: Vec.Vec, cost: Vec.Vec, cov: Vec.Vec,
  taken: Vec.Vec, h: Heap.Heap, +j: U32, bad: Bool) -> St:
  match bad:
    case True{}:
      St{n, mark(r, Bad{}), sim, val, cost, cov, taken, h}
    case False{}:
      force.tk(n, r, sim, val, cost, cov, h, j, Vec.at(taken, j))

def force.gate(+n: U32, r: Run, sim: Vec.Vec, val: Vec.Vec, cost: Vec.Vec, cov: Vec.Vec,
  taken: Vec.Vec, h: Heap.Heap, +j: U32, stopped: Bool) -> St:
  match stopped:
    case True{}:
      St{n, r, sim, val, cost, cov, taken, h}
    case False{}:
      force.range(n, r, sim, val, cost, cov, taken, h, j, U32.is_ge(j, n))

def force.one(j: U32, s: St) -> St:
  match s:
    case St{n, +r, sim, val, cost, cov, taken, h}:
      force.gate(n, r, sim, val, cost, cov, taken, h, j, halted(why(r)))

# the list leads: a self-call must shrink before any argument changes
def force(js: List<&2, U32>, s: St) -> St:
  match js:
    case Nil{}:
      s
    case Con{j, t}:
      force(t, force.one(j, s))

# -- the first round ---------------------------------------------------------

# every free candidate's exact gain against the coverage the required items
# left, keyed into the heap. This is the one round a lazy greedy cannot make
# cheap -- every later round reuses these as bounds.
def build.ct(n: U32, r: Run, sim: Vec.Vec, val: Vec.Vec, cov: Vec.Vec, taken: Vec.Vec,
  h: Heap.Heap, j: U32, gj: U32, x: Vec.Vec & U32) -> St:
  (cost, c0) = x
  St{n, r, sim, val, cost, cov, taken, Heap.push(h, key(ratio(gj, U32.max(c0, 1))), j)}

def build.gn(n: U32, r: Run, cost: Vec.Vec, taken: Vec.Vec, h: Heap.Heap, +j: U32,
  x: Gs) -> St:
  match x:
    case Gs{gj, sim, val, cov}:
      build.ct(n, r, sim, val, cov, taken, h, j, gj, Vec.at(cost, j))

def build.free(+n: U32, r: Run, sim: Vec.Vec, val: Vec.Vec, cost: Vec.Vec, cov: Vec.Vec,
  taken: Vec.Vec, h: Heap.Heap, +j: U32, free: Bool) -> St:
  match free:
    case True{}:
      build.gn(n, r, cost, taken, h, j, gain(sim, val, cov, n, j))
    case False{}:
      St{n, r, sim, val, cost, cov, taken, h}

def build.tk(n: U32, r: Run, sim: Vec.Vec, val: Vec.Vec, cost: Vec.Vec, cov: Vec.Vec,
  h: Heap.Heap, j: U32, x: Vec.Vec & U32) -> St:
  (taken, t) = x
  build.free(n, r, sim, val, cost, cov, taken, h, j, U32.is_zero(t))

def build.one(+j: U32, s: St) -> St:
  match s:
    case St{n, r, sim, val, cost, cov, taken, h}:
      build.tk(n, r, sim, val, cost, cov, h, j, Vec.at(taken, j))

def build.go(fuel: Nat, +j: U32, s: St) -> St:
  match fuel:
    case 0n:
      s
    case 1n++p:
      build.go(p, U32.inc(j), build.one(j, s))

# this round is the one O(n^2) pass in the whole primitive, so a request that
# was already refused does not pay for it
def build.hot(+n: U32, r: Run, sim: Vec.Vec, val: Vec.Vec, cost: Vec.Vec, cov: Vec.Vec,
  taken: Vec.Vec, h: Heap.Heap, stop: Bool) -> St:
  match stop:
    case True{}:
      St{n, r, sim, val, cost, cov, taken, h}
    case False{}:
      build.go(U32.to_nat(n), 0, St{n, r, sim, val, cost, cov, taken, h})

def build.all(s: St) -> St:
  match s:
    case St{n, +r, sim, val, cost, cov, taken, h}:
      build.hot(n, r, sim, val, cost, cov, taken, h, halted(why(r)))

# -- the lazy round ----------------------------------------------------------

def step.take(n: U32, val: Vec.Vec, cost: Vec.Vec, taken: Vec.Vec, h: Heap.Heap,
  r: Run, j: U32, cj: U32, gj: U32, x: Cv) -> Step:
  match x:
    case Cv{sim, cov}:
      Go{St{n, add(tick(r), j, gj, cj), sim, val, cost, cov, taken, h}}

# a zero gain ends the run and is not taken: the item that reached here held the
# best bound of every candidate left, and a bound of zero bounds them all
def step.zero(+n: U32, r: Run, sim: Vec.Vec, val: Vec.Vec, cost: Vec.Vec, cov: Vec.Vec,
  taken: Vec.Vec, h: Heap.Heap, +j: U32, cj: U32, gj: U32, z: Bool) -> Step:
  match z:
    case True{}:
      Fin{St{n, mark(tick(r), Full{}), sim, val, cost, cov, taken, h}}
    case False{}:
      step.take(n, val, cost, taken, h, r, j, cj, gj, cover(sim, cov, n, j))

# the lazy test. `kt` is this candidate's fresh key and (k2, j2) the best stale
# key left; every remaining candidate's true gain is under its own bound, which
# is under that one, so a fresh value that beats it is the greedy's own choice.
# Losing costs a reinsertion at the fresh value and nothing else -- and the
# fresh key is never lower than the stale one it replaced, which is why the loop
# cannot cycle: an item reinserted at an unchanged key would have won the test.
def step.cmp(n: U32, r: Run, sim: Vec.Vec, val: Vec.Vec, cost: Vec.Vec, cov: Vec.Vec,
  taken: Vec.Vec, h: Heap.Heap, j: U32, cj: U32, +gj: U32, kt: U32, wins: Bool) -> Step:
  match wins:
    case True{}:
      step.zero(n, r, sim, val, cost, cov, taken, h, j, cj, gj, U32.is_zero(gj))
    case False{}:
      Go{St{n, tick(r), sim, val, cost, cov, taken, Heap.push(h, kt, j)}}

def step.peek(n: U32, r: Run, sim: Vec.Vec, val: Vec.Vec, cost: Vec.Vec, cov: Vec.Vec,
  taken: Vec.Vec, +j: U32, cj: U32, +gj: U32, +kt: U32,
  x: Heap.Heap & Maybe<&2, Heap.Entry>) -> Step:
  (h, m) = x
  match m:
    case None{}:
      step.zero(n, r, sim, val, cost, cov, taken, h, j, cj, gj, U32.is_zero(gj))
    case Some{Heap.Entry{k2, j2}}:
      step.cmp(n, r, sim, val, cost, cov, taken, h, j, cj, gj, kt,
        Heap.less(kt, j, k2, j2))

def step.gn(n: U32, r: Run, cost: Vec.Vec, taken: Vec.Vec, h: Heap.Heap, j: U32,
  +cj: U32, x: Gs) -> Step:
  match x:
    case Gs{+gj, sim, val, cov}:
      step.peek(n, r, sim, val, cost, cov, taken, j, cj, gj, key(ratio(gj, cj)),
        Heap.peek(h))

# an item priced past what is left is dropped for good, not put back: the room
# only ever falls, so nothing that cannot be afforded now can be afforded later
def step.afford(+n: U32, r: Run, sim: Vec.Vec, val: Vec.Vec, cost: Vec.Vec, cov: Vec.Vec,
  taken: Vec.Vec, h: Heap.Heap, +j: U32, cj: U32, no: Bool) -> Step:
  match no:
    case True{}:
      Go{St{n, tick(r), sim, val, cost, cov, taken, h}}
    case False{}:
      step.gn(n, r, cost, taken, h, j, cj, gain(sim, val, cov, n, j))

def step.cst(n: U32, +r: Run, sim: Vec.Vec, val: Vec.Vec, cov: Vec.Vec, taken: Vec.Vec,
  h: Heap.Heap, j: U32, x: Vec.Vec & U32) -> Step:
  (cost, c0) = x
  +cj = U32.max(c0, 1)
  step.afford(n, r, sim, val, cost, cov, taken, h, j, cj, U32.is_gt(cj, room(r)))

# the index arrives as an Entry's last field, which a + may not mark, so the
# read that needs it twice happens one def in
def step.on(n: U32, r: Run, sim: Vec.Vec, val: Vec.Vec, cost: Vec.Vec, cov: Vec.Vec,
  taken: Vec.Vec, h: Heap.Heap, +j: U32) -> Step:
  step.cst(n, r, sim, val, cov, taken, h, j, Vec.at(cost, j))

# the popped candidate's own stale key is not read: only its identity matters,
# because the gain is recomputed from the coverage either way
def step.pop(n: U32, r: Run, sim: Vec.Vec, val: Vec.Vec, cost: Vec.Vec, cov: Vec.Vec,
  taken: Vec.Vec, x: Heap.Heap & Maybe<&2, Heap.Entry>) -> Step:
  (h, m) = x
  match m:
    case None{}:
      Fin{St{n, mark(r, Full{}), sim, val, cost, cov, taken, h}}
    case Some{Heap.Entry{k, j}}:
      step.on(n, r, sim, val, cost, cov, taken, h, j)

def step.room(n: U32, r: Run, sim: Vec.Vec, val: Vec.Vec, cost: Vec.Vec, cov: Vec.Vec,
  taken: Vec.Vec, h: Heap.Heap, broke: Bool) -> Step:
  match broke:
    case True{}:
      Fin{St{n, mark(r, Full{}), sim, val, cost, cov, taken, h}}
    case False{}:
      step.pop(n, r, sim, val, cost, cov, taken, Heap.pop(h))

def step.dry(n: U32, +r: Run, sim: Vec.Vec, val: Vec.Vec, cost: Vec.Vec, cov: Vec.Vec,
  taken: Vec.Vec, h: Heap.Heap, dry: Bool) -> Step:
  match dry:
    case True{}:
      Fin{St{n, mark(r, Dry{}), sim, val, cost, cov, taken, h}}
    case False{}:
      step.room(n, r, sim, val, cost, cov, taken, h, U32.is_zero(room(r)))

# a refused run is over: `bad` and `over` are answers, and a later round must
# not take another item on top of one nor overwrite what it said with `full`
def step.hot(n: U32, +r: Run, sim: Vec.Vec, val: Vec.Vec, cost: Vec.Vec, cov: Vec.Vec,
  taken: Vec.Vec, h: Heap.Heap, stop: Bool) -> Step:
  match stop:
    case True{}:
      Fin{St{n, r, sim, val, cost, cov, taken, h}}
    case False{}:
      step.dry(n, r, sim, val, cost, cov, taken, h, U32.is_zero(left(r)))

def step(s: St) -> Step:
  match s:
    case St{n, +r, sim, val, cost, cov, taken, h}:
      step.hot(n, r, sim, val, cost, cov, taken, h, halted(why(r)))

def loop.dry(s: St) -> St:
  match s:
    case St{n, r, sim, val, cost, cov, taken, h}:
      St{n, mark(r, Dry{}), sim, val, cost, cov, taken, h}

# the fuel is one more than the limit, so the limit is what actually stops the
# run and the fuel is only the checker's proof that it stops at all
def loop(fuel: Nat, x: Step) -> St:
  match fuel:
    case 0n:
      match x:
        case Fin{s}:
          s
        case Go{s}:
          loop.dry(s)
    case 1n++p:
      match x:
        case Fin{s}:
          s
        case Go{s}:
          loop(p, step(s))

# -- the door ----------------------------------------------------------------

# the coverage vector, the flags and the heap are the run's own and do not
# outlive it; the Ground comes back because the caller still owns it
def out(s: St) -> Ground & Run:
  match s:
    case St{n, r, sim, val, cost, cov, taken, h}:
      (Ground{n, sim, val, cost}, rev(r))

def budgeted.go(js: List<&2, U32>, limit: U32, s: St) -> Ground & Run:
  out(loop((1n + U32.to_nat(limit) : Nat), Go{build.all(force(js, s))}))

def budgeted.mk(js: List<&2, U32>, +n: U32, budget: U32, +limit: U32, sim: Vec.Vec,
  val: Vec.Vec, cost: Vec.Vec) -> Ground & Run:
  budgeted.go(js, limit,
    St{n, Run{limit, budget, 0, 0, [], Full{}}, sim, val, cost, zeros(n), zeros(n),
      Heap.new()})

# budgeted: the required items first and at their price, then lazy greedy by
# gain per cost until the budget cannot buy another item, nothing is left that
# adds anything, or the pop limit runs out -- `why` says which, and every pick
# carries the gain it was taken for.
def budgeted(g: Ground, required: List<&2, U32>, budget: U32, limit: U32) -> Ground & Run:
  match g:
    case Ground{n, sim, val, cost}:
      budgeted.mk(required, n, budget, limit, sim, val, cost)
