# Proof: an answer nobody has to trust. A search -- fast, complicated, forked,
# possibly wrong -- returns its answer together with a small witness, and a
# checker in this file reads the witness and says yes or no. You then trust the
# answer because you trust the checker, not because you trust the search. That
# is what makes an aggressive optimiser safe to deploy: the optimiser may be
# rewritten, vectorised, moved to a GPU or replaced by a rival, and nothing
# downstream has to be re-audited, because the thing downstream reads is the
# certificate and not the code that produced it.
#
# Four instances, and each one is a pair of opposed tests. That pairing is the
# whole design and it is why no single check here is ever enough:
#
#   sort         a permutation and the output.  Sortedness alone accepts a
#                sorted array of the wrong elements; the permutation alone
#                accepts the right elements unsorted. Both, plus out[i] ==
#                in[perm[i]], is a proof.
#   topk         the K indices and the (K+1)-th best score as a threshold.
#                Every chosen element is at or above it, every unchosen one at
#                or below it. Either half alone is satisfiable by a liar who
#                picks the threshold to suit.
#   path         the distance labels. d[v] <= d[u] + w feasibility alone accepts
#                labels that are too small; tightness (every label achieved by
#                some incoming edge) alone accepts labels that are too large.
#   assign       the matching and the dual prices. u[i] <= c[i][j] + w[j] alone
#                accepts prices too weak to prove anything; equality on the
#                matched cells alone accepts prices that are not feasible.
#
# Integer arithmetic throughout, and that is a soundness decision before it is
# a compiler one. A feasibility test in floating point needs an epsilon, and an
# epsilon is a hole in the proof -- it is exactly the slack a wrong answer hides
# in. Complementary slackness and edge feasibility in exact integers have no
# such hole. (The compiled C backend also miscompiles an Array<F64> written from
# a recursive loop, which would have forced the same choice anyway.)
#
# The budget. A witness is untrusted input, so it is also a denial of service:
# it names its own sizes, and a checker that believes them can be made to run
# for 2^32 steps. Every entry point takes `limit` last and refuses, in O(1),
# before a single loop starts -- `Fail{Fuel{}}` and nothing read. The sizes are
# never added together, because a sum of sizes is the one place the guard itself
# could wrap and let 2^16 by 2^16 through as a limit of 0.
#
# Written for the compiled lanes: every checker is a fixed number of flat passes
# with one read per cell and no allocation but its own claim vector. None of
# them exits early on the first failure -- the budget already bounds the work,
# and a branch per cell costs more than the exit saves.
import Base
import ./vec.bend as Vec

# -- the verdict -------------------------------------------------------------

# Over and Slack are the two halves of every duality argument here, and naming
# them apart is what makes a rejection say which half broke.
type Bad is Data:
  Fuel{}                      # the witness asked for more work than `limit`
  Range{}                     # an index is outside 0..n-1
  Dup{}                       # an index is claimed twice
  Order{}                     # a claimed ordering does not hold
  Value{}                     # a claimed value is not the one its source holds
  Over{}                      # a bound is exceeded: the witness claims more than it proves
  Slack{}                     # a bound that must be attained is not: it proves less than it claims

def Res() -> Data:
  Result<&2, &2, Bad, U32>

# the verdict inside a pass, with no budget on it: the allowance is settled
# before the first loop, so no loop below has to carry one
type Vd is Data:
  Ok{}
  No{b: Bad}

def show(b: Bad) -> String:
  match b:
    case Fuel{}:
      "fuel"
    case Range{}:
      "range"
    case Dup{}:
      "dup"
    case Order{}:
      "order"
    case Value{}:
      "value"
    case Over{}:
      "over"
    case Slack{}:
      "slack"

def want(b: Bad, ok: Bool) -> Vd:
  match ok:
    case True{}:
      Ok{}
    case False{}:
      No{b}

# the first failure wins, so a rejection names the property that broke and not
# the last cell that happened to notice
def keep(a: Vd, b: Vd) -> Vd:
  match a:
    case Ok{}:
      b
    case No{x}:
      No{x}

def done(left: U32, v: Vd) -> Res():
  match v:
    case Ok{}:
      Done{left}
    case No{b}:
      Fail{b}

# -- the allowance -----------------------------------------------------------

# at or above: unreachable, forbidden, out of contract. assign.bend's ceiling,
# kept here so a certificate crossing between the two files reads the same.
def big() -> U32:
  2147483648

def inf() -> U32:
  4294967295

# take: n units off what is left, or nothing left at all. Every guard below is
# this, chained, so no two sizes are ever added -- a witness naming 2^31 rows
# and 2^31 columns must not slip past a guard on a sum of 0.
def take.if(left: U32, +n: U32, ok: Bool) -> Maybe<&2, U32>:
  match ok:
    case True{}:
      Some{U32.sub(left, n)}
    case False{}:
      None{}

def take(m: Maybe<&2, U32>, +n: U32) -> Maybe<&2, U32>:
  match m:
    case None{}:
      None{}
    case Some{+left}:
      take.if(left, n, U32.is_le(n, left))

# a * b units, decided without computing a * b: a product that wrapped would be
# the same hole the sum is, one multiplication deeper. a == 0 is free because
# then there are no cells at all, and U32.div answers 0 for a zero divisor.
def take_mul.if(left: U32, +a: U32, +b: U32, ok: Bool) -> Maybe<&2, U32>:
  match ok:
    case True{}:
      Some{U32.sub(left, U32.mul(a, b))}
    case False{}:
      None{}

def take_mul(m: Maybe<&2, U32>, +a: U32, +b: U32) -> Maybe<&2, U32>:
  match m:
    case None{}:
      None{}
    case Some{+left}:
      take_mul.if(left, a, b, Bool.or(U32.is_zero(a), U32.is_le(b, U32.div(left, a))))

# -- scratch -----------------------------------------------------------------

def zeros.go(k: Nat, v: Vec.Vec) -> Vec.Vec:
  match k:
    case 0n:
      v
    case 1n++q:
      zeros.go(q, Vec.push(v, 0))

# n cells of 0: the claim vector every "and no index twice" test needs
def zeros(+n: U32) -> Vec.Vec:
  zeros.go(U32.to_nat(n), Vec.new(0))

# claim: x is in 0..n-1 and has not been claimed before. Exactly n successful
# claims over a range of n is a bijection by pigeonhole, which is why no checker
# below ever builds the inverse permutation to look for a hole in it. An index
# out of range is refused before the mark, so a hostile index cannot write.
def claim.mark(seen: Vec.Vec, x: U32, f: U32) -> Vec.Vec & Vd:
  (Vec.put(seen, x, 1), want(Dup{}, U32.is_zero(f)))

def claim.seen(x: U32, r: Vec.Vec & U32) -> Vec.Vec & Vd:
  (seen, f) = r
  claim.mark(seen, x, f)

def claim.if(seen: Vec.Vec, +x: U32, ok: Bool) -> Vec.Vec & Vd:
  match ok:
    case True{}:
      claim.seen(x, Vec.at(seen, x))
    case False{}:
      (seen, No{Range{}})

def claim(seen: Vec.Vec, +x: U32, +n: U32) -> Vec.Vec & Vd:
  claim.if(seen, x, U32.is_lt(x, n))

# -- sort --------------------------------------------------------------------

# a: the input, o: the claimed output, p: the permutation, s: the claim vector,
# pv: the previous output value, v: the verdict so far
type Srt is Type:
  Srt{a: Vec.Vec, o: Vec.Vec, p: Vec.Vec, s: Vec.Vec, pv: U32, v: Vd}

# the three tests, together, on one output slot. There is no i > 0 guard on the
# order test: pv starts at 0 and every U32 is at or above 0, so the first slot
# compares against a bound it cannot fail, and the branch that would have said
# so is not written.
def sort.cmp(a: Vec.Vec, o: Vec.Vec, p: Vec.Vec, s: Vec.Vec, v: Vd, pv: U32, xi: U32, +xo: U32) -> Srt:
  Srt{a, o, p, s, xo, keep(v, keep(want(Value{}, U32.is_eq(xo, xi)), want(Order{}, U32.is_le(pv, xo))))}

def sort.xo(a: Vec.Vec, p: Vec.Vec, s: Vec.Vec, v: Vd, pv: U32, xi: U32, r: Vec.Vec & U32) -> Srt:
  (o, xo) = r
  sort.cmp(a, o, p, s, v, pv, xi, xo)

def sort.xi(o: Vec.Vec, p: Vec.Vec, s: Vec.Vec, v: Vd, pv: U32, t: U32, r: Vec.Vec & U32) -> Srt:
  (a, xi) = r
  sort.xo(a, p, s, v, pv, xi, Vec.at(o, t))

def sort.clm(a: Vec.Vec, o: Vec.Vec, p: Vec.Vec, v: Vd, pv: U32, t: U32, pt: U32, r: Vec.Vec & Vd) -> Srt:
  (s, vc) = r
  sort.xi(o, p, s, keep(v, vc), pv, t, Vec.at(a, pt))

def sort.pt(a: Vec.Vec, o: Vec.Vec, s: Vec.Vec, v: Vd, pv: U32, t: U32, n: U32, r: Vec.Vec & U32) -> Srt:
  (p, +pt) = r
  sort.clm(a, o, p, v, pv, t, pt, claim(s, pt, n))

def sort.one(+t: U32, n: U32, x: Srt) -> Srt:
  match x:
    case Srt{a, o, p, s, pv, v}:
      sort.pt(a, o, s, v, pv, t, n, Vec.at(p, t))

def sort.go(fuel: Nat, +t: U32, +n: U32, x: Srt) -> Srt:
  match fuel:
    case 0n:
      x
    case 1n++q:
      sort.go(q, U32.inc(t), n, sort.one(t, n, x))

def sort.fin(left: U32, x: Srt) -> Vec.Vec & Vec.Vec & Vec.Vec & Res():
  match x:
    case Srt{a, o, p, s, pv, v}:
      (a, o, p, done(left, v))

def sort.on(a: Vec.Vec, o: Vec.Vec, p: Vec.Vec, +n: U32, m: Maybe<&2, U32>) -> Vec.Vec & Vec.Vec & Vec.Vec & Res():
  match m:
    case None{}:
      (a, o, p, Fail{Fuel{}})
    case Some{left}:
      sort.fin(left, sort.go(U32.to_nat(n), 0, n, Srt{a, o, p, zeros(n), 0, Ok{}}))

# sort: `o` is `a` sorted, and `p` says where each output element came from.
# One pass, three tests, n units of budget. Any two of the three tests accept a
# wrong answer; the fixture has a mutant for each.
def sort(a: Vec.Vec, o: Vec.Vec, p: Vec.Vec, +n: U32, limit: U32) -> Vec.Vec & Vec.Vec & Vec.Vec & Res():
  sort.on(a, o, p, n, take(Some{limit}, n))

# -- topk --------------------------------------------------------------------

# sc: the scores, ix: the K chosen indices, s: the claim vector, pv: the
# previous chosen score, v: the verdict so far
type Tk is Type:
  Tk{sc: Vec.Vec, ix: Vec.Vec, s: Vec.Vec, pv: U32, v: Vd}

# a chosen element: in range, not chosen twice, at or above the threshold, and
# no better than the one before it. pv starts at 2^32-1 for the same reason the
# sort checker's starts at 0.
def top.clm(ix: Vec.Vec, pv: U32, v: Vd, thr: U32, r: Vec.Vec & Vd, q: Vec.Vec & U32) -> Tk:
  (s, vc) = r
  (sc, +y) = q
  Tk{sc, ix, s, y, keep(keep(v, vc), keep(want(Slack{}, U32.is_le(thr, y)), want(Order{}, U32.is_le(y, pv))))}

def top.it(sc: Vec.Vec, s: Vec.Vec, pv: U32, v: Vd, n: U32, thr: U32, r: Vec.Vec & U32) -> Tk:
  (ix, +it) = r
  top.clm(ix, pv, v, thr, claim(s, it, n), Vec.at(sc, it))

def top.one(+t: U32, n: U32, thr: U32, x: Tk) -> Tk:
  match x:
    case Tk{sc, ix, s, pv, v}:
      top.it(sc, s, pv, v, n, thr, Vec.at(ix, t))

def top.go(fuel: Nat, +t: U32, +n: U32, +thr: U32, x: Tk) -> Tk:
  match fuel:
    case 0n:
      x
    case 1n++q:
      top.go(q, U32.inc(t), n, thr, top.one(t, n, thr, x))

# an element nobody chose: it must not beat the threshold. This is the test a
# buggy heap breaks, and the only one that reads the whole input.
def top.free(ix: Vec.Vec, s: Vec.Vec, pv: U32, v: Vd, thr: U32, r: Vec.Vec & U32) -> Tk:
  (sc, y) = r
  Tk{sc, ix, s, pv, keep(v, want(Over{}, U32.is_le(y, thr)))}

def top.if(sc: Vec.Vec, ix: Vec.Vec, s: Vec.Vec, pv: U32, v: Vd, j: U32, thr: U32, free: Bool) -> Tk:
  match free:
    case True{}:
      top.free(ix, s, pv, v, thr, Vec.at(sc, j))
    case False{}:
      Tk{sc, ix, s, pv, v}

def top.mark(sc: Vec.Vec, ix: Vec.Vec, pv: U32, v: Vd, j: U32, thr: U32, r: Vec.Vec & U32) -> Tk:
  (s, f) = r
  top.if(sc, ix, s, pv, v, j, thr, U32.is_zero(f))

def top.rest(+j: U32, thr: U32, x: Tk) -> Tk:
  match x:
    case Tk{sc, ix, s, pv, v}:
      top.mark(sc, ix, pv, v, j, thr, Vec.at(s, j))

def top.all(fuel: Nat, +j: U32, +thr: U32, x: Tk) -> Tk:
  match fuel:
    case 0n:
      x
    case 1n++q:
      top.all(q, U32.inc(j), thr, top.rest(j, thr, x))

def top.fin(left: U32, x: Tk) -> Vec.Vec & Vec.Vec & Res():
  match x:
    case Tk{sc, ix, s, pv, v}:
      (sc, ix, done(left, v))

def top.on(sc: Vec.Vec, ix: Vec.Vec, +n: U32, +k: U32, +thr: U32, m: Maybe<&2, U32>) -> Vec.Vec & Vec.Vec & Res():
  match m:
    case None{}:
      (sc, ix, Fail{Fuel{}})
    case Some{left}:
      top.fin(left, top.all(U32.to_nat(n), 0, thr, top.go(U32.to_nat(k), 0, n, thr, Tk{sc, ix, zeros(n), inf(), Ok{}})))

# topk: `ix` names the k greatest of `sc`, and `thr` is the (k+1)-th greatest --
# the score the chosen must reach and the unchosen must not pass. A liar cannot
# pick thr to suit: lowering it fails the unchosen pass, raising it fails the
# chosen one. k + n units of budget.
def topk(sc: Vec.Vec, ix: Vec.Vec, +n: U32, +k: U32, +thr: U32, limit: U32) -> Vec.Vec & Vec.Vec & Res():
  top.on(sc, ix, n, k, thr, take(take(Some{limit}, n), k))

# -- shortest path -----------------------------------------------------------

# eu/ev/ew: the edge list, tail, head and weight; d: the claimed labels; h: one
# flag a vertex, set when some incoming edge achieves its label
type Pth is Type:
  Pth{eu: Vec.Vec, ev: Vec.Vec, ew: Vec.Vec, d: Vec.Vec, h: Vec.Vec, r: Vd}

def path.hit(h: Vec.Vec, vv: U32, on: Bool) -> Vec.Vec:
  match on:
    case True{}:
      Vec.put(h, vv, 1)
    case False{}:
      h

# one edge: d[v] <= d[u] + w, and if the two are equal this edge is what
# achieves d[v] -- which is what the second pass asks after.
def path.tight(eu: Vec.Vec, ev: Vec.Vec, ew: Vec.Vec, d: Vec.Vec, h: Vec.Vec, r: Vd, vv: U32, +dv: U32, +t: U32) -> Pth:
  Pth{eu, ev, ew, d, path.hit(h, vv, U32.is_eq(dv, t)), keep(r, want(Over{}, U32.is_le(dv, t)))}

# an edge out of an unreachable tail, or one whose weight is past the ceiling,
# proves nothing about its head: it cannot make a label too large, so it is
# skipped rather than failed.
def path.live(eu: Vec.Vec, ev: Vec.Vec, ew: Vec.Vec, d: Vec.Vec, h: Vec.Vec, r: Vd, vv: U32, du: U32, dv: U32, w: U32, usable: Bool) -> Pth:
  match usable:
    case True{}:
      path.tight(eu, ev, ew, d, h, r, vv, dv, U32.add(du, w))
    case False{}:
      Pth{eu, ev, ew, d, h, r}

def path.dv(eu: Vec.Vec, ev: Vec.Vec, ew: Vec.Vec, h: Vec.Vec, r: Vd, vv: U32, +du: U32, +w: U32, q: Vec.Vec & U32) -> Pth:
  (d, dv) = q
  path.live(eu, ev, ew, d, h, r, vv, du, dv, w, Bool.and(U32.is_lt(du, big()), U32.is_lt(w, big())))

def path.du(eu: Vec.Vec, ev: Vec.Vec, ew: Vec.Vec, h: Vec.Vec, r: Vd, +vv: U32, w: U32, q: Vec.Vec & U32) -> Pth:
  (d, du) = q
  path.dv(eu, ev, ew, h, r, vv, du, w, Vec.at(d, vv))

def path.wgt(eu: Vec.Vec, ev: Vec.Vec, d: Vec.Vec, h: Vec.Vec, r: Vd, uu: U32, vv: U32, q: Vec.Vec & U32) -> Pth:
  (ew, w) = q
  path.du(eu, ev, ew, h, r, vv, w, Vec.at(d, uu))

def path.head(eu: Vec.Vec, ew: Vec.Vec, d: Vec.Vec, h: Vec.Vec, r: Vd, n: U32, uu: U32, e: U32, q: Vec.Vec & U32) -> Pth:
  (ev, +vv) = q
  path.wgt(eu, ev, d, h, keep(r, want(Range{}, U32.is_lt(vv, n))), uu, vv, Vec.at(ew, e))

def path.tail(ev: Vec.Vec, ew: Vec.Vec, d: Vec.Vec, h: Vec.Vec, r: Vd, +n: U32, +e: U32, q: Vec.Vec & U32) -> Pth:
  (eu, +uu) = q
  path.head(eu, ew, d, h, keep(r, want(Range{}, U32.is_lt(uu, n))), n, uu, e, Vec.at(ev, e))

def path.one(+e: U32, n: U32, x: Pth) -> Pth:
  match x:
    case Pth{eu, ev, ew, d, h, r}:
      path.tail(ev, ew, d, h, r, n, e, Vec.at(eu, e))

def path.go(fuel: Nat, +e: U32, +n: U32, x: Pth) -> Pth:
  match fuel:
    case 0n:
      x
    case 1n++q:
      path.go(q, U32.inc(e), n, path.one(e, n, x))

# a label that no incoming edge achieves is smaller than every path into it, so
# the witness is claiming a route it has not shown. The source is exempt (its
# label is pinned at 0 below) and an unreachable vertex is exempt because the
# feasibility pass above has already proved nothing reaches it.
def path.seen(eu: Vec.Vec, ev: Vec.Vec, ew: Vec.Vec, d: Vec.Vec, r: Vd, q: Vec.Vec & U32) -> Pth:
  (h, f) = q
  Pth{eu, ev, ew, d, h, keep(r, want(Slack{}, U32.is_ne(f, 0)))}

def path.need(eu: Vec.Vec, ev: Vec.Vec, ew: Vec.Vec, d: Vec.Vec, h: Vec.Vec, r: Vd, j: U32, ask: Bool) -> Pth:
  match ask:
    case True{}:
      path.seen(eu, ev, ew, d, r, Vec.at(h, j))
    case False{}:
      Pth{eu, ev, ew, d, h, r}

def path.lab(eu: Vec.Vec, ev: Vec.Vec, ew: Vec.Vec, h: Vec.Vec, r: Vd, +j: U32, src: U32, q: Vec.Vec & U32) -> Pth:
  (d, dj) = q
  path.need(eu, ev, ew, d, h, r, j, Bool.and(U32.is_lt(dj, big()), U32.is_ne(j, src)))

def path.two(+j: U32, src: U32, x: Pth) -> Pth:
  match x:
    case Pth{eu, ev, ew, d, h, r}:
      path.lab(eu, ev, ew, h, r, j, src, Vec.at(d, j))

def path.all(fuel: Nat, +j: U32, +src: U32, x: Pth) -> Pth:
  match fuel:
    case 0n:
      x
    case 1n++q:
      path.all(q, U32.inc(j), src, path.two(j, src, x))

def path.zero(eu: Vec.Vec, ev: Vec.Vec, ew: Vec.Vec, h: Vec.Vec, r: Vd, q: Vec.Vec & U32) -> Pth:
  (d, ds) = q
  Pth{eu, ev, ew, d, h, keep(r, want(Value{}, U32.is_zero(ds)))}

def path.src(+src: U32, +n: U32, x: Pth) -> Pth:
  match x:
    case Pth{eu, ev, ew, d, h, r}:
      path.zero(eu, ev, ew, h, keep(r, want(Range{}, U32.is_lt(src, n))), Vec.at(d, src))

def path.fin(left: U32, x: Pth) -> Vec.Vec & Vec.Vec & Vec.Vec & Vec.Vec & Res():
  match x:
    case Pth{eu, ev, ew, d, h, r}:
      (eu, ev, ew, d, done(left, r))

def path.on(eu: Vec.Vec, ev: Vec.Vec, ew: Vec.Vec, d: Vec.Vec, +n: U32, +mm: U32, +src: U32, m: Maybe<&2, U32>) -> Vec.Vec & Vec.Vec & Vec.Vec & Vec.Vec & Res():
  match m:
    case None{}:
      (eu, ev, ew, d, Fail{Fuel{}})
    case Some{left}:
      path.fin(left, path.all(U32.to_nat(n), 0, src, path.go(U32.to_nat(mm), 0, n, path.src(src, n, Pth{eu, ev, ew, d, zeros(n), Ok{}}))))

# path: `d` are the claimed shortest-path distances from `src` over the mm edges
# (eu -> ev, weight ew) on n vertices. d[src] == 0, every edge feasible, every
# reachable label achieved. mm + n units of budget.
def path(eu: Vec.Vec, ev: Vec.Vec, ew: Vec.Vec, d: Vec.Vec, +n: U32, +mm: U32, +src: U32, limit: U32) -> Vec.Vec & Vec.Vec & Vec.Vec & Vec.Vec & Res():
  path.on(eu, ev, ew, d, n, mm, src, take(take(Some{limit}, n), mm))

# -- assignment --------------------------------------------------------------

# c: the cost matrix, row-major nr by nc; mt: the column matched to each row;
# u: the row prices; w: the column prices, stored non-negative and read as a
# discount, which is assign.bend's own sign convention -- v[j] = -w[j] -- so no
# cell and no price is ever negated and a Vec of U32 holds the whole witness.
type Asg is Type:
  Asg{c: Vec.Vec, u: Vec.Vec, w: Vec.Vec, mt: Vec.Vec, s: Vec.Vec, r: Vd}

# dual feasibility at one cell: u[i] <= c[i][j] + w[j]. A forbidden cell is
# vacuous -- no matching may use it, so no price has to fit under it, which is
# what lets a padded (opt-out) matrix certify at all.
def asg.cell(c: Vec.Vec, u: Vec.Vec, w: Vec.Vec, mt: Vec.Vec, s: Vec.Vec, r: Vd, ui: U32, cij: U32, wj: U32, live: Bool) -> Asg:
  match live:
    case True{}:
      Asg{c, u, w, mt, s, keep(r, want(Over{}, U32.is_le(ui, U32.add(cij, wj))))}
    case False{}:
      Asg{c, u, w, mt, s, r}

def asg.wj(c: Vec.Vec, u: Vec.Vec, mt: Vec.Vec, s: Vec.Vec, r: Vd, ui: U32, +cij: U32, q: Vec.Vec & U32) -> Asg:
  (w, wj) = q
  asg.cell(c, u, w, mt, s, r, ui, cij, wj, U32.is_lt(cij, big()))

def asg.cij(u: Vec.Vec, w: Vec.Vec, mt: Vec.Vec, s: Vec.Vec, r: Vd, ui: U32, j: U32, q: Vec.Vec & U32) -> Asg:
  (c, cij) = q
  asg.wj(c, u, mt, s, r, ui, cij, Vec.at(w, j))

def asg.one(+j: U32, base: U32, ui: U32, x: Asg) -> Asg:
  match x:
    case Asg{c, u, w, mt, s, r}:
      asg.cij(u, w, mt, s, r, ui, j, Vec.at(c, U32.add(base, j)))

def asg.row(fuel: Nat, +j: U32, +base: U32, +ui: U32, x: Asg) -> Asg:
  match fuel:
    case 0n:
      x
    case 1n++q:
      asg.row(q, U32.inc(j), base, ui, asg.one(j, base, ui, x))

def asg.line(c: Vec.Vec, w: Vec.Vec, mt: Vec.Vec, s: Vec.Vec, r: Vd, nc: U32, base: U32, q: Vec.Vec & U32) -> Asg:
  (u, ui) = q
  asg.row(U32.to_nat(nc), 0, base, ui, Asg{c, u, w, mt, s, r})

def asg.feas(+i: U32, +nc: U32, x: Asg) -> Asg:
  match x:
    case Asg{c, u, w, mt, s, r}:
      asg.line(c, w, mt, s, r, nc, U32.mul(i, nc), Vec.at(u, i))

def asg.go(fuel: Nat, +i: U32, +nc: U32, x: Asg) -> Asg:
  match fuel:
    case 0n:
      x
    case 1n++q:
      asg.go(q, U32.inc(i), nc, asg.feas(i, nc, x))

# complementary slackness on a matched cell: u[i] == c[i][j] + w[j] exactly.
# Feasibility above says the prices are legal; this says they are worth as much
# as the matching costs, and the two together are the whole optimality proof.
def asg.eq(c: Vec.Vec, u: Vec.Vec, w: Vec.Vec, mt: Vec.Vec, s: Vec.Vec, r: Vd, ui: U32, cij: U32, wj: U32) -> Asg:
  Asg{c, u, w, mt, s, keep(r, want(Slack{}, U32.is_eq(ui, U32.add(cij, wj))))}

def asg.mw(c: Vec.Vec, u: Vec.Vec, mt: Vec.Vec, s: Vec.Vec, r: Vd, ui: U32, cij: U32, q: Vec.Vec & U32) -> Asg:
  (w, wj) = q
  asg.eq(c, u, w, mt, s, r, ui, cij, wj)

def asg.mc(u: Vec.Vec, w: Vec.Vec, mt: Vec.Vec, s: Vec.Vec, r: Vd, ui: U32, j: U32, q: Vec.Vec & U32) -> Asg:
  (c, cij) = q
  asg.mw(c, u, mt, s, r, ui, cij, Vec.at(w, j))

def asg.mui(c: Vec.Vec, w: Vec.Vec, mt: Vec.Vec, r: Vd, base: U32, +j: U32, qs: Vec.Vec & Vd, qu: Vec.Vec & U32) -> Asg:
  (s, vc) = qs
  (u, ui) = qu
  asg.mc(u, w, mt, s, keep(r, vc), ui, j, Vec.at(c, U32.add(base, j)))

def asg.mi(c: Vec.Vec, u: Vec.Vec, w: Vec.Vec, s: Vec.Vec, r: Vd, base: U32, nc: U32, i: U32, q: Vec.Vec & U32) -> Asg:
  (mt, +j) = q
  asg.mui(c, w, mt, r, base, j, claim(s, j, nc), Vec.at(u, i))

def asg.pair(+i: U32, +nc: U32, x: Asg) -> Asg:
  match x:
    case Asg{c, u, w, mt, s, r}:
      asg.mi(c, u, w, s, r, U32.mul(i, nc), nc, i, Vec.at(mt, i))

def asg.mat(fuel: Nat, +i: U32, +nc: U32, x: Asg) -> Asg:
  match fuel:
    case 0n:
      x
    case 1n++q:
      asg.mat(q, U32.inc(i), nc, asg.pair(i, nc, x))

# a column nothing was matched to must carry no discount, or the dual objective
# is not the matching's cost and the two sides of the duality never meet
def asg.free(c: Vec.Vec, u: Vec.Vec, mt: Vec.Vec, s: Vec.Vec, r: Vd, q: Vec.Vec & U32) -> Asg:
  (w, wj) = q
  Asg{c, u, w, mt, s, keep(r, want(Slack{}, U32.is_zero(wj)))}

def asg.zif(c: Vec.Vec, u: Vec.Vec, w: Vec.Vec, mt: Vec.Vec, s: Vec.Vec, r: Vd, j: U32, free: Bool) -> Asg:
  match free:
    case True{}:
      asg.free(c, u, mt, s, r, Vec.at(w, j))
    case False{}:
      Asg{c, u, w, mt, s, r}

def asg.col(c: Vec.Vec, u: Vec.Vec, w: Vec.Vec, mt: Vec.Vec, r: Vd, j: U32, q: Vec.Vec & U32) -> Asg:
  (s, f) = q
  asg.zif(c, u, w, mt, s, r, j, U32.is_zero(f))

def asg.zero(+j: U32, x: Asg) -> Asg:
  match x:
    case Asg{c, u, w, mt, s, r}:
      asg.col(c, u, w, mt, r, j, Vec.at(s, j))

def asg.cols(fuel: Nat, +j: U32, x: Asg) -> Asg:
  match fuel:
    case 0n:
      x
    case 1n++q:
      asg.cols(q, U32.inc(j), asg.zero(j, x))

def asg.fin(left: U32, x: Asg) -> Vec.Vec & Vec.Vec & Vec.Vec & Vec.Vec & Res():
  match x:
    case Asg{c, u, w, mt, s, r}:
      (c, u, w, mt, done(left, r))

def asg.on(c: Vec.Vec, u: Vec.Vec, w: Vec.Vec, mt: Vec.Vec, +nr: U32, +nc: U32, m: Maybe<&2, U32>) -> Vec.Vec & Vec.Vec & Vec.Vec & Vec.Vec & Res():
  match m:
    case None{}:
      (c, u, w, mt, Fail{Fuel{}})
    case Some{left}:
      asg.fin(left, asg.cols(U32.to_nat(nc), 0, asg.mat(U32.to_nat(nr), 0, nc, asg.go(U32.to_nat(nr), 0, nc, Asg{c, u, w, mt, zeros(nc), Ok{}}))))

# assign: `mt` matches each of nr rows to a column of the nc, and u and w are
# the dual prices that prove it is the cheapest such matching. One pass over
# the matrix and two over its margins -- O(nr * nc) against the O(nr^2 * nc) it
# took to find. The witness arrives as four flat Vecs, which is the form it
# travels in: nothing here needs the solver's own record, or the solver.
def assign(c: Vec.Vec, u: Vec.Vec, w: Vec.Vec, mt: Vec.Vec, +nr: U32, +nc: U32, limit: U32) -> Vec.Vec & Vec.Vec & Vec.Vec & Vec.Vec & Res():
  asg.on(c, u, w, mt, nr, nc, take(take(take_mul(Some{limit}, nr, nc), nr), nc))
