# Drift: constant-memory online statistics that say when a stream's behaviour
# changed, and hand back what they saw rather than a bit.
#
# Three pieces, in the order they depend on each other:
#
#   Stat   Welford's online mean and variance, plus Chan's parallel merge, so
#          the two halves of a fork combine into the accumulator the whole would
#          have built. Three numbers, no window.
#   PH     Page-Hinkley: the cumulative deviation from the running mean, with a
#          magnitude tolerance `delta` a deviation must exceed before it counts,
#          against a threshold `lam`. It fires when cum - min(cum) > lam.
#   eps    the Hoeffding bound ADWIN cuts on: how far two means of a bounded
#          variable may sit apart by luck alone.
#
# The evidence is the point. A detector that answers True has told its caller
# nothing it can act on. This one answers with the index it fired at, the index
# it believes the change happened at, and the Welford accumulator on each side
# of that index -- count, mean and variance, before and after. The change index
# is not guessed and costs no window: the running minimum of the cumulative sum
# IS the maximum-likelihood change point of the Page-Hinkley statistic, so the
# snapshot taken the last time that minimum moved is already the answer, and it
# costs three more numbers.
#
# Direction is a parameter, not two detectors. Down is Up on the negated
# deviation, and a sign flip is exact in floating point, so both directions
# share one extremum, one comparison and one code path.
#
# Floating point, stated. F64 addition is not associative, so `merge` is
# ORDERED, not exact: merge(merge(a, b), c) and merge(a, merge(b, c)) may differ
# in the last bits. A fork's association is written into the program and not
# chosen by the scheduler, so every lane and every thread count walks the same
# tree and gets the same bits; two *different* trees over the same data need
# not. Everything printed against this file is quantized, and every law is
# asserted at that quantum in tests/power/drift_gen.py rather than assumed.
#
# Written for the compiled lanes: a Stat is three unboxed scalars, so its kind
# is Data -- it copies into both children of a fork, it drops, and it rides home
# inside a Maybe. The update is one divide and four adds and allocates nothing.
import Base

# -- Welford -----------------------------------------------------------------

type Stat is Data:
  Stat{n: U32, mu: F64, m2: F64}

def empty() -> Stat:
  Stat{0, 0.0d, 0.0d}

def one(+x: F64) -> Stat:
  Stat{1, x, 0.0d}

def count(s: Stat) -> U32:
  match s:
    case Stat{n, mu, m2}:
      n

def mean(s: Stat) -> F64:
  match s:
    case Stat{n, mu, m2}:
      mu

# the raw second moment about the mean: sum of squared residuals, not yet divided
def sqd(s: Stat) -> F64:
  match s:
    case Stat{n, mu, m2}:
      m2

# population variance, m2 / n. An empty accumulator is 0 and not 0/0 -- a NaN
# here would poison every comparison downstream of it, silently.
#
# The guard is a `match` and not `Bool.pick` on purpose, here and at merge and
# tail below, for two independent reasons. Bool.pick is a function, so it is
# STRICT: both arms are evaluated and the loser is dropped. Every guard in this
# file exists precisely because the losing arm is undefined -- 0/0 at an empty
# count, a division by a zero suffix length in tail -- so a strict pick computes
# the garbage it was written to avoid and merely hides it. Separately, Bool.pick
# is POLYMORPHIC, and a polymorphic parameter erases to a boxed word, so the one
# compiled Bool.pick sinks whatever arrives as if it were a heap pointer. An F64
# is unboxed: the C backend then frees a block addressed by the double's own
# mantissa bits. A match is monomorphic and branches, which answers both. See
# docs/omen/f64-drop-c-backend.md.
def variance.at(+m2: F64, +n: U32, empty: Bool) -> F64:
  match empty:
    case True{}:
      0.0d
    case False{}:
      F64.div(m2, U32.to_f64(n))

def variance.go(+m2: F64, +n: U32) -> F64:
  variance.at(m2, n, U32.is_eq(n, 0))

def variance(s: Stat) -> F64:
  match s:
    case Stat{n, mu, m2}:
      variance.go(m2, n)

# Welford's update: the mean moves first, then m2 takes the product of the
# residual measured before that move and the residual measured after it. The
# naive route -- keep sum and sum of squares, subtract at the end -- is the same
# quantity in exact arithmetic and catastrophically wrong in floating point once
# the mean is large beside the spread. That cancellation is the whole reason
# this recurrence exists, and it is the first mutant this lane pins.
def push.go(+n1: U32, +mu: F64, +m2: F64, +d: F64, +x: F64) -> Stat:
  +mu1 = F64.add(mu, F64.div(d, U32.to_f64(n1)))
  +q1 = F64.add(m2, F64.mul(d, F64.sub(x, mu1)))
  Stat{n1, mu1, q1}

def push.at(+n: U32, +mu: F64, +m2: F64, +x: F64) -> Stat:
  push.go(U32.inc(n), mu, m2, F64.sub(x, mu), x)

def push(s: Stat, +x: F64) -> Stat:
  match s:
    case Stat{n, mu, m2}:
      push.at(n, mu, m2, x)

def merge.mk(+na: U32, +ma: F64, +qa: F64, +nb: U32, +mb: F64, +qb: F64) -> Stat:
  +n = U32.add(na, nb)
  +fn = U32.to_f64(n)
  +d = F64.sub(mb, ma)
  +mu = F64.add(ma, F64.mul(d, F64.div(U32.to_f64(nb), fn)))
  +w = F64.div(F64.mul(U32.to_f64(na), U32.to_f64(nb)), fn)
  +q = F64.add(F64.add(qa, qb), F64.mul(F64.mul(d, d), w))
  Stat{n, mu, q}

def merge.b(+na: U32, +ma: F64, +qa: F64, b: Stat) -> Stat:
  match b:
    case Stat{nb, mb, qb}:
      merge.mk(na, ma, qa, nb, mb, qb)

def merge.raw(a: Stat, b: Stat) -> Stat:
  match a:
    case Stat{na, ma, qa}:
      merge.b(na, ma, qa, b)

# Chan's parallel update: two accumulators become the one the whole stream would
# have built. The correction term is weighted by na * nb / n, and dropping that
# weight is the merge bug that looks right on equal halves and is wrong on every
# uneven one. Either side may be empty and the formula is already exact there --
# a zero count zeroes the correction and collapses the weighted mean onto the
# non-empty side. Only two empties divide zero by zero, which is the pick below.
def merge.go(a: Stat, b: Stat, void: Bool) -> Stat:
  match void:
    case True{}:
      empty()
    case False{}:
      merge.raw(a, b)

def merge(+a: Stat, +b: Stat) -> Stat:
  merge.go(a, b, U32.is_eq(U32.add(count(a), count(b)), 0))

def tail.mk(+n: U32, +mu: F64, +q: F64, +na: U32, +ma: F64, +qa: F64) -> Stat:
  +nb = U32.sub(n, na)
  +fn = U32.to_f64(n)
  +fa = U32.to_f64(na)
  +fb = U32.to_f64(nb)
  +mb = F64.div(F64.sub(F64.mul(fn, mu), F64.mul(fa, ma)), fb)
  +d = F64.sub(mb, ma)
  +w = F64.div(F64.mul(fa, fb), fn)
  +qb = F64.sub(F64.sub(q, qa), F64.mul(F64.mul(d, d), w))
  Stat{nb, mb, qb}

def tail.h(+n: U32, +mu: F64, +q: F64, h: Stat) -> Stat:
  match h:
    case Stat{na, ma, qa}:
      tail.mk(n, mu, q, na, ma, qa)

def tail.raw(w: Stat, h: Stat) -> Stat:
  match w:
    case Stat{n, mu, q}:
      tail.h(n, mu, q, h)

# the inverse of merge: what the suffix saw, given the whole and its prefix.
# This is what keeps the evidence window constant memory -- the "after" half of
# a drift report is an algebraic difference, not a buffer of samples. It is also
# the one operation here with a real numerical price: it subtracts two sums of
# squares, so a tail that is tiny beside its head loses digits to cancellation.
# A prefix at least as long as the whole has no suffix, and answers empty.
def tail.go(w: Stat, h: Stat, void: Bool) -> Stat:
  match void:
    case True{}:
      empty()
    case False{}:
      tail.raw(w, h)

def tail(+w: Stat, +h: Stat) -> Stat:
  tail.go(w, h, U32.is_le(count(w), count(h)))

# -- Page-Hinkley ------------------------------------------------------------

type Dir is Data:
  Up{}
  Down{}

def show.dir(d: Dir) -> String:
  match d:
    case Up{}:
      "up"
    case Down{}:
      "down"

# what a firing detector hands back. `at` is the sample it fired on, `since` the
# sample it believes the change began at, and the two accumulators are the
# stream either side of `since` -- so a caller has the size of the change, the
# support under each mean, and the delay it paid, without asking twice.
type Ev is Data:
  Ev{dir: Dir, at: U32, since: U32, before: Stat, after: Stat}

type PH is Data:
  PH{dir: Dir, delta: F64, lam: F64, warm: U32, w: Stat, cum: F64, ext: F64, mark: Stat}

# delta is the magnitude a deviation must exceed before it counts at all -- with
# delta at 0 the statistic is a random walk and any long stationary stream
# eventually drifts past any threshold, which is the false-positive mutant
# below. lam is the height the excursion must reach. warm is the count the
# detector refuses to fire under, because a running mean over three samples is
# not a mean and every early sample looks like a change against it.
def new(+dir: Dir, +delta: F64, +lam: F64, +warm: U32) -> PH:
  PH{dir, delta, lam, warm, empty(), 0.0d, 0.0d, empty()}

def seen(d: PH) -> U32:
  match d:
    case PH{dir, delta, lam, warm, w, cum, ext, mark}:
      count(w)

def stat(d: PH) -> Stat:
  match d:
    case PH{dir, delta, lam, warm, w, cum, ext, mark}:
      w

# Down is Up on the negated deviation. Negation is exact, so the two directions
# share one extremum and one comparison rather than needing a min and a max.
def dev(dir: Dir, +x: F64, +mu: F64) -> F64:
  match dir:
    case Up{}:
      F64.sub(x, mu)
    case Down{}:
      F64.sub(mu, x)

def step.ev(+dir: Dir, +w: Stat, +mark: Stat) -> Ev:
  Ev{dir, count(w), count(mark), mark, tail(w, mark)}

def step.out(+dir: Dir, +delta: F64, +lam: F64, +warm: U32, +w: Stat, +c: F64, +e: F64, +mark: Stat, fire: Bool) -> PH & Maybe<&2, Ev>:
  match fire:
    case True{}:
      (new(dir, delta, lam, warm), Some{step.ev(dir, w, mark)})
    case False{}:
      (PH{dir, delta, lam, warm, w, c, e, mark}, None{})

def step.ext(+dir: Dir, +delta: F64, +lam: F64, +warm: U32, +w: Stat, +c: F64, +e: F64, +mark: Stat) -> PH & Maybe<&2, Ev>:
  step.out(dir, delta, lam, warm, w, c, e, mark,
    Bool.and(U32.is_ge(count(w), warm), F64.is_gt(F64.sub(c, e), lam)))

def step.min(+dir: Dir, +delta: F64, +lam: F64, +warm: U32, +w: Stat, +c: F64, +e: F64, +mark: Stat, low: Bool) -> PH & Maybe<&2, Ev>:
  match low:
    case True{}:
      step.ext(dir, delta, lam, warm, w, c, c, w)
    case False{}:
      step.ext(dir, delta, lam, warm, w, c, e, mark)

def step.cum(+dir: Dir, +delta: F64, +lam: F64, +warm: U32, +w: Stat, +c: F64, +e: F64, +mark: Stat) -> PH & Maybe<&2, Ev>:
  step.min(dir, delta, lam, warm, w, c, e, mark, F64.is_lt(c, e))

def step.w(+dir: Dir, +delta: F64, +lam: F64, +warm: U32, +cum: F64, +e: F64, +mark: Stat, +x: F64, +w1: Stat) -> PH & Maybe<&2, Ev>:
  step.cum(dir, delta, lam, warm, w1,
    F64.add(cum, F64.sub(dev(dir, x, mean(w1)), delta)), e, mark)

def step.at(+dir: Dir, +delta: F64, +lam: F64, +warm: U32, +w: Stat, +cum: F64, +e: F64, +mark: Stat, +x: F64) -> PH & Maybe<&2, Ev>:
  step.w(dir, delta, lam, warm, cum, e, mark, x, push(w, x))

# the one actuation door: a sample in, the detector and -- when it fires -- the
# evidence out. The mean is updated before the deviation is taken against it,
# which is the order River's PageHinkley uses. A fired detector comes back
# reset: the Page-Hinkley statistic is defined against one regime, and the
# regime just changed, so the next report is measured from here.
def step(d: PH, +x: F64) -> PH & Maybe<&2, Ev>:
  match d:
    case PH{dir, delta, lam, warm, w, cum, ext, mark}:
      step.at(dir, delta, lam, warm, w, cum, ext, mark, x)

# -- the Hoeffding cut -------------------------------------------------------

# ADWIN's cut (Bifet and Gavalda 2007): two means of a variable with range r are
# further apart than luck allows, at confidence 1 - d, when their gap exceeds
#
#   r * sqrt(ln(1/d) / (2 m)),   1/m = 1/n0 + 1/n1
#
# `lnid` is ln(1/d) and is taken as a parameter rather than computed. It is one
# constant per caller, and it is the only logarithm this lane would otherwise
# need: keeping it out means every number in this file comes from +, -, *, / and
# sqrt, which IEEE-754 rounds exactly, so the interpreter, the JS lane and the C
# lane agree bit for bit instead of within whatever ulp their libm chose.
#
# ponytail: the bound, not the window. ADWIN's exponential histogram -- the
# machinery that keeps every cut point of a growing window in log memory -- is
# the ceiling this lane declines; see docs/omen/lanes/power-13.md.
def eps(+na: U32, +nb: U32, +r: F64, +lnid: F64) -> F64:
  +m = F64.div(F64.mul(U32.to_f64(na), U32.to_f64(nb)), U32.to_f64(U32.add(na, nb)))
  F64.mul(r, F64.sqrt(F64.div(lnid, F64.mul(2.0d, m))))

def hoeffding(+a: Stat, +b: Stat, +r: F64, +lnid: F64) -> F64:
  eps(count(a), count(b), r, lnid)

def differs.go(+a: Stat, +b: Stat, +r: F64, +lnid: F64, ok: Bool) -> Bool:
  match ok:
    case True{}:
      F64.is_gt(F64.abs(F64.sub(mean(a), mean(b))), hoeffding(a, b, r, lnid))
    case False{}:
      False{}

def differs(+a: Stat, +b: Stat, +r: F64, +lnid: F64) -> Bool:
  differs.go(a, b, r, lnid,
    Bool.and(U32.is_lt(0, count(a)), U32.is_lt(0, count(b))))

# the significance of a report: Page-Hinkley says *when*, this says whether the
# gap it found is larger than two windows of those sizes could produce by luck.
# The two questions are separate on purpose -- a detector tuned to fire early
# will fire on noise, and this is the test that says so, from the evidence the
# detector already handed back and without a second pass over the stream.
def ev.differs(e: Ev, +r: F64, +lnid: F64) -> Bool:
  match e:
    case Ev{dir, at, since, before, after}:
      differs(before, after, r, lnid)
