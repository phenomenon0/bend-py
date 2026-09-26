#!/usr/bin/env python3
# The oracle for drift.bend: prints the whole fixture. The reference below is
# plain CPython floats -- a Welford class, a Chan merge and a transcription of
# the Page-Hinkley recurrence, no Stat, no PH, no Bend -- so a row checks the
# detector and not a second copy of it. The Welford half is checked against
# `statistics.mean` and `statistics.pvariance`, which compute in exact rationals
# and round once: if the recurrence below drifted from the quantity it claims to
# be, that comparison would say so before any row is emitted.
#
# Floating point is the hazard of this lane, and it is answered in two moves.
#
# 1. Nothing prints through F64.show. Every float leaves as
#    floor(x * 2^20 + 0.5), a signed decimal. The scale is a power of TWO on
#    purpose: an exactly-representable sample scales to an exact integer with no
#    rounding, so it lands half a unit from the quantum's edge -- the safest
#    place there is -- instead of somewhere arbitrary.
#
# 2. `guard()` refuses to emit any value that lands near that edge anyway. F64
#    addition is not associative, so a merge over a fork's tree and a merge over
#    a left fold agree to the last few bits and not to the last bit; every law
#    below is therefore asserted AT THE QUANTUM, and guard() is what makes "at
#    the quantum" a promise rather than a hope. The same move bm25_gen.py's
#    guard() and json_gen.py's agree() make.
#
# The laws, all asserted here before any row is emitted:
#
#   Welford equals the batch          mean/variance match statistics.*
#   merge is associative              (a+b)+c == a+(b+c) == the batch
#   a fork's tree equals a left fold  at every depth 0..6
#   tail inverts merge                tail(merge(a, b), a) == b
#   chunking does not move a firing   run(n) == run(k) then run(n-k)
#   a stationary stream never fires   at the configured delta and lambda
#   a step of size k fires            within a delay the table below pins
import math
import statistics

M = 0xFFFFFFFF
SCALE = float(1 << 20)
TOL = 1e-5  # in scaled units: ~660 ulps at the magnitudes this file prints

# -- quantization ------------------------------------------------------------


def quant(x):
    return math.floor(x * SCALE + 0.5)


def guard(x):
    v = x * SCALE + 0.5
    if not math.isfinite(v) or abs(v) >= 2147483648.0:
        raise SystemExit("drift_gen: %r is out of the quantum's range; retune" % x)
    if abs(v - round(v)) < TOL:
        raise SystemExit("drift_gen: %r quantizes on a boundary; retune" % x)
    return x


def q(x):
    return str(quant(guard(x)))


def f64(x):
    return repr(float(x)) + "d"


def lit(x):
    # the language has no unary minus on a term, so a negative literal is
    # written as the negation it is
    return ("F64.neg(%s)" % f64(-x)) if math.copysign(1.0, x) < 0 else f64(x)


# -- the stream, exactly as the fixture builds it ----------------------------


def h(p):
    # a multiply-shift-xor finalizer, not the bare Knuth multiply the rest of
    # this tree uses. The bare multiply is a WEYL SEQUENCE: consecutive p give a
    # low-discrepancy stream whose cumulative deviation from its own mean stays
    # inside +/-4 over three thousand samples, with a lag-1 correlation of -0.42.
    # A false-positive test on that stream proves nothing, because no detector
    # can fire on it -- the statistic this lane computes IS a discrepancy, and a
    # low-discrepancy source is the one input that cannot exercise it. The two
    # xor-shift rounds below cost nothing and give lag-1 0.0000 and a genuine
    # random walk, which is what makes the quiet rows below a real check.
    u = (((p + 1) & M) * 2654435761) & M
    u ^= u >> 15
    u = (u * 2246822519) & M
    u ^= u >> 13
    return u


def nz(p):
    # thirteen bits off the TOP of the hash into [-2, 2) in steps of 1/2048: an
    # integer under 2^13 cast to F64 and divided by a power of two, so every
    # sample is exactly representable and identical on every host
    return (float(h(p) >> 19) - 4096.0) / 2048.0


def lvl(shape, p, at0, jump):
    if p < at0:
        return 0.0
    return jump if shape == 0 else jump * float(p - at0)


def sx(shape, p, at0, jump):
    return lvl(shape, p, at0, jump) + nz(p)


# -- Welford, in plain floats ------------------------------------------------


class W:
    """count, mean and the sum of squared residuals. Welford 1962 for the
    update, Chan/Golub/LeVeque 1979 for the merge."""

    __slots__ = ("n", "mu", "m2")

    def __init__(self, n=0, mu=0.0, m2=0.0):
        self.n, self.mu, self.m2 = n, mu, m2

    def var(self):
        return self.m2 / float(self.n) if self.n else 0.0


def wpush(s, x):
    n1 = s.n + 1
    d = x - s.mu
    mu1 = s.mu + d / float(n1)
    return W(n1, mu1, s.m2 + d * (x - mu1))


def wmerge(a, b):
    if a.n + b.n == 0:
        return W()
    n = a.n + b.n
    fn = float(n)
    d = b.mu - a.mu
    mu = a.mu + d * (float(b.n) / fn)
    w = (float(a.n) * float(b.n)) / fn
    return W(n, mu, (a.m2 + b.m2) + (d * d) * w)


def wtail(w, hd):
    if w.n <= hd.n:
        return W()
    nb = w.n - hd.n
    fn, fa, fb = float(w.n), float(hd.n), float(nb)
    mb = (fn * w.mu - fa * hd.mu) / fb
    d = mb - hd.mu
    ww = (fa * fb) / fn
    return W(nb, mb, (w.m2 - hd.m2) - (d * d) * ww)


def wof(xs):
    s = W()
    for x in xs:
        s = wpush(s, x)
    return s


def samples(lo, n, shape, at0, jump):
    return [sx(shape, lo + i, at0, jump) for i in range(n)]


def wacc(lo, n, shape, at0, jump):
    return wof(samples(lo, n, shape, at0, jump))


def wtree(d, lo, n, shape, at0, jump):
    if d == 0:
        return wacc(lo, n, shape, at0, jump)
    hf = n >> 1
    return wmerge(
        wtree(d - 1, lo, hf, shape, at0, jump),
        wtree(d - 1, lo + hf, hf, shape, at0, jump),
    )


# -- Page-Hinkley, transcribed -----------------------------------------------
#
# m_T = sum (x_t - xbar_T - delta) with xbar the running mean, M_T = min m_t,
# and the alarm is m_T - M_T > lambda. Down is the same recurrence on the
# negated deviation. River's PageHinkley updates the mean before it takes the
# deviation and resets the detector when it fires; both are kept here.
#
# River's forgetting factor alpha is NOT kept -- see docs/omen/lanes/power-13.md
# under "Deliberate ceilings". This is the classical Page 1954 / Hinkley 1971
# statistic, which is what the lane brief spells out.


class PH:
    def __init__(self, dirn, delta, lam, warm):
        self.dirn, self.delta, self.lam, self.warm = dirn, delta, lam, warm
        self.w, self.cum, self.ext, self.mark = W(), 0.0, 0.0, W()

    def step(self, x):
        w1 = wpush(self.w, x)
        dev = (x - w1.mu) if self.dirn == 0 else (w1.mu - x)
        c = self.cum + (dev - self.delta)
        if c < self.ext:
            e, mk = c, w1
        else:
            e, mk = self.ext, self.mark
        if w1.n >= self.warm and (c - e) > self.lam:
            ev = (self.dirn, w1.n, mk.n, mk, wtail(w1, mk))
            self.w, self.cum, self.ext, self.mark = W(), 0.0, 0.0, W()
            return ev
        self.w, self.cum, self.ext, self.mark = w1, c, e, mk
        return None


BLANK = (0, 0, 0, W(), W())


class Run:
    def __init__(self, dirn, delta, lam, warm):
        self.d = PH(dirn, delta, lam, warm)
        self.ev, self.hits = BLANK, 0

    def feed(self, lo, n, shape, at0, jump):
        for i in range(n):
            e = self.d.step(sx(shape, lo + i, at0, jump))
            if e is not None:
                if self.hits == 0:
                    self.ev = e
                self.hits += 1
        return self


def eps(na, nb, r, lnid):
    m = (float(na) * float(nb)) / float(na + nb)
    return r * math.sqrt(lnid / (2.0 * m))


def differs(a, b, r, lnid):
    if a.n == 0 or b.n == 0:
        return False
    return abs(a.mu - b.mu) > eps(a.n, b.n, r, lnid)


# -- the laws ----------------------------------------------------------------

# `at0` past the end of the longest run (3,000) is how a stationary stream is
# written: one code path builds every stream, so the quiet rows and the drifting
# rows cannot disagree about what the noise was.
FLAT = 9999
STREAMS = [
    (0, FLAT, 0.0),  # stationary
    (0, 200, 2.0),  # a step of 2 at 200
    (0, 128, 4.0),  # a step of 4 at 128
    (1, 150, 0.015625),  # a ramp of 1/64 a sample from 150
]


def qw(s):
    return (s.n, quant(s.mu), quant(s.var()))


def law_welford():
    """Welford is the quantity statistics.* computes in exact rationals."""
    for shape, at0, jump in STREAMS:
        for n in (1, 2, 3, 17, 64, 300):
            xs = samples(0, n, shape, at0, jump)
            s = wof(xs)
            assert s.n == n
            assert quant(s.mu) == quant(statistics.mean(xs)), (shape, n, "mean")
            assert quant(s.var()) == quant(statistics.pvariance(xs)), (shape, n, "var")


def law_merge():
    """merge is associative and equals the batch, at the quantum -- and the
    fork's tree agrees with the left fold at every depth it can be cut to."""
    for shape, at0, jump in STREAMS:
        n = 256
        batch = qw(wacc(0, n, shape, at0, jump))
        for k in (0, 1, 3, 64, 128, 200, 255, 256):
            a = wacc(0, k, shape, at0, jump)
            b = wacc(k, n - k, shape, at0, jump)
            assert qw(wmerge(a, b)) == batch, (shape, k, "merge != batch")
            assert qw(wtail(wmerge(a, b), a)) == qw(b), (shape, k, "tail")
        for i, j in ((16, 48), (1, 2), (100, 27)):
            a = wacc(0, i, shape, at0, jump)
            b = wacc(i, j, shape, at0, jump)
            c = wacc(i + j, n - i - j, shape, at0, jump)
            l = qw(wmerge(wmerge(a, b), c))
            r = qw(wmerge(a, wmerge(b, c)))
            assert l == r == batch, (shape, i, j, "assoc")
        for d in range(0, 7):
            assert qw(wtree(d, 0, n, shape, at0, jump)) == batch, (shape, d, "tree")


# dir up, delta 1/2, lambda 16, warm-up 30. Chosen by the sweep in the lane
# report: the cheapest corner of the grid with a measured zero false-positive
# count over 3,000 stationary samples in BOTH directions.
CFG = (0, 0.5, 16.0, 30)


def law_chunk():
    """a detector fires at the same index under any chunking of the prefix: the
    state is a value, so pausing and resuming cannot move an alarm."""
    for shape, at0, jump in STREAMS:
        n = 300
        one = Run(*CFG).feed(0, n, shape, at0, jump)
        for k in (0, 1, 29, 30, 150, 299, 300):
            two = Run(*CFG)
            two.feed(0, k, shape, at0, jump)
            two.feed(k, n - k, shape, at0, jump)
            assert (two.hits, two.ev[1], two.ev[2]) == (one.hits, one.ev[1], one.ev[2])


# the false-positive grid: 3,000 stationary samples per cell, both directions.
# These are measured, not asserted to be zero -- the detector HAS a rate, and
# the lane report prints this table. Only the configured corner is a law.
FPGRID = [(0.25, 8.0), (0.5, 4.0), (0.5, 8.0), (0.5, 16.0), (1.0, 8.0)]


def law_quiet():
    """at the configured tolerance a stationary stream never fires, and delta is
    what buys that. Drop delta and the statistic is an unbiased random walk whose
    excursions cross any fixed threshold; the row below measures both."""
    for dirn in (0, 1):
        r = Run(dirn, CFG[1], CFG[2], CFG[3]).feed(0, 3000, 0, FLAT, 0.0)
        assert r.hits == 0, ("false positive at the configured corner", dirn, r.hits)
    walk = Run(0, 0.0, CFG[2], CFG[3]).feed(0, 3000, 0, FLAT, 0.0)
    assert walk.hits > 0, "delta = 0 should wander past any threshold"
    # and the rate must fall as either knob is raised
    prev = None
    for lam in (4.0, 8.0, 16.0):
        n = Run(0, 0.5, lam, 30).feed(0, 3000, 0, FLAT, 0.0).hits
        assert prev is None or n <= prev, ("a bigger lambda should not fire more", lam)
        prev = n


DELAYS = [0.75, 1.0, 2.0, 4.0, 8.0]


def law_delay():
    """a step of known size fires within a bounded delay, and the delay shrinks
    as the step grows. The bound is lambda / (jump - delta) plus the lag the
    running mean adds; 4x that is the table's ceiling."""
    last = 1 << 30
    for j in DELAYS:
        r = Run(*CFG).feed(0, 600, 0, 200, j)
        assert r.hits >= 1, ("missed a step of", j)
        d = r.ev[1] - 200
        assert 0 < d <= math.ceil(4.0 * CFG[2] / (j - CFG[1])), ("slow", j, d)
        assert d <= last, ("a bigger step should not be slower", j, d, last)
        last = d
        # the evidence has to be evidence: the two means must straddle the step
        assert r.ev[3].n > 0 and r.ev[4].n > 0, ("empty evidence", j)
        assert r.ev[4].mu - r.ev[3].mu > 0.5 * j, ("the gap is not the step", j)


law_welford()
law_merge()
law_chunk()
law_quiet()
law_delay()

# -- the rows ----------------------------------------------------------------

rows, want = [], []


def row(call, text):
    rows.append(call)
    want.append(text)


def st(s):
    return "%d %s %s" % (s.n, q(s.mu), q(s.var()))


def mg(a, b):
    return st(a) + " | " + st(b)


def acc(lo, n, shape, at0, jump):
    return "acc(%d, %dn, %d, %d, %s)" % (lo, n, shape, at0, lit(jump))


def tree(d, lo, n, shape, at0, jump):
    return "tree(%dn, %d, %d, %d, %d, %s)" % (d, lo, n, shape, at0, lit(jump))


def sname(shape, at0, jump):
    return "%d/%d/%s" % (shape, at0, jump)


# -- Welford by hand ---------------------------------------------------------


def pushes(xs):
    call = "D.empty()"
    for x in xs:
        call = "D.push(%s, %s)" % (call, lit(x))
    return call


def sv(s):
    # count and variance only, for the rows whose mean is out of the quantum
    return "%d %s" % (s.n, q(s.var()))


row("st(D.empty())", st(W()))
row("st(D.one(3.5d))", st(wof([3.5])))
for xs in ([1.0], [1.0, 2.0, 6.0], [4.0, 4.0, 4.0, 4.0], [0.5, 0.25, 0.125, 8.0]):
    row("st(%s)" % pushes(xs), st(wof(xs)))
# The reason the recurrence exists. A hundred million beside a spread of a
# quarter: E[x^2] is 1e16, where the gap between neighbouring F64 is 2, so
# sum-of-squares-minus-square-of-sum has no digits left to subtract and returns
# 0 or worse. Welford never forms either quantity. Only the count and the
# variance print -- the mean is outside the quantum's range by design, and it is
# the variance this row is about.
BIG = [100000000.0, 100000000.25, 100000000.5]
row("sv(%s)" % pushes(BIG), sv(wof(BIG)))
row("q(D.variance(D.empty()))", q(0.0))
row("q(D.variance(D.one(9.0d)))", q(0.0))
row("U32.show(D.count(D.one(9.0d)))", "1")

# -- Welford over the streams ------------------------------------------------

# every stream is the same noise until its own change point, so only the
# stationary one is walked at every length; the others are walked at the two
# lengths that straddle theirs
for i, (shape, at0, jump) in enumerate(STREAMS):
    for n in (1, 2, 17, 64, 300) if i == 0 else (64, 300):
        row("st(%s)" % acc(0, n, shape, at0, jump), st(wacc(0, n, shape, at0, jump)))

# -- merge equals the batch, and tail inverts merge --------------------------
# one row, both sides: a merge that lost the count weighting prints two halves

for shape, at0, jump in STREAMS:
    n = 256
    batch = wacc(0, n, shape, at0, jump)
    for k in (0, 1, 200, 256):
        a = wacc(0, k, shape, at0, jump)
        b = wacc(k, n - k, shape, at0, jump)
        row(
            "mg(D.merge(%s, %s), %s)"
            % (
                acc(0, k, shape, at0, jump),
                acc(k, n - k, shape, at0, jump),
                acc(0, n, shape, at0, jump),
            ),
            mg(wmerge(a, b), batch),
        )
        row(
            "mg(D.tail(%s, %s), %s)"
            % (
                acc(0, n, shape, at0, jump),
                acc(0, k, shape, at0, jump),
                acc(k, n - k, shape, at0, jump),
            ),
            mg(wtail(batch, a), b),
        )

# -- associativity, and the fork's tree against the left fold ----------------

for shape, at0, jump in STREAMS:
    n = 256
    i, j = 16, 48
    a = acc(0, i, shape, at0, jump)
    b = acc(i, j, shape, at0, jump)
    c = acc(i + j, n - i - j, shape, at0, jump)
    wa = wacc(0, i, shape, at0, jump)
    wb = wacc(i, j, shape, at0, jump)
    wc = wacc(i + j, n - i - j, shape, at0, jump)
    row(
        "mg(D.merge(D.merge(%s, %s), %s), D.merge(%s, D.merge(%s, %s)))"
        % (a, b, c, a, b, c),
        mg(wmerge(wmerge(wa, wb), wc), wmerge(wa, wmerge(wb, wc))),
    )
    for d in (1, 4, 6):
        row(
            "mg(%s, %s)"
            % (tree(d, 0, n, shape, at0, jump), acc(0, n, shape, at0, jump)),
            mg(wtree(d, 0, n, shape, at0, jump), wacc(0, n, shape, at0, jump)),
        )

# -- the empty ends ----------------------------------------------------------

row("st(D.merge(D.empty(), D.empty()))", st(W()))
row("st(D.merge(D.empty(), D.one(7.0d)))", st(wof([7.0])))
row("st(D.merge(D.one(7.0d), D.empty()))", st(wof([7.0])))
row(
    "mg(D.merge(D.empty(), %s), %s)"
    % (acc(0, 64, 0, 200, 2.0), acc(0, 64, 0, 200, 2.0)),
    mg(wmerge(W(), wacc(0, 64, 0, 200, 2.0)), wacc(0, 64, 0, 200, 2.0)),
)
row("st(D.tail(D.empty(), D.empty()))", st(W()))
row("st(D.tail(D.one(7.0d), D.one(7.0d)))", st(W()))
row(
    "st(D.tail(%s, %s))" % (acc(0, 16, 0, 200, 2.0), acc(0, 64, 0, 200, 2.0)),
    st(W()),
)
row("st(D.tail(D.push(D.one(1.0d), 3.0d), D.empty()))", st(wof([1.0, 3.0])))

# -- the detector: a report, and whether the report is significant -----------


def start(dirn, delta, lam, warm):
    # the configured corner is by far the most repeated argument list in this
    # file, so it gets a name in the fixture too
    if (dirn, delta, lam, warm) == CFG:
        return "up()"
    return "start(D.%s{}, %s, %s, %d)" % (
        "Up" if dirn == 0 else "Down",
        lit(delta),
        lit(lam),
        warm,
    )


def feed(lo, n, shape, at0, jump, inner):
    return "feed(%dn, %d, %d, %d, %s, %s)" % (n, lo, shape, at0, lit(jump), inner)


def ev_text(e):
    dirn, at, since, b, a = e
    return "%s @%d ~%d | %s | %s" % (
        "up" if dirn == 0 else "down",
        at,
        since,
        st(b),
        st(a),
    )


def run_text(r):
    return "%d %s" % (r.hits, ev_text(r.ev))


def sig_text(r, rr, lnid):
    b, a = r.ev[3], r.ev[4]
    return run_text(r) + " sig=" + ("1" if differs(b, a, rr, lnid) else "0")


DE, LA, WA = CFG[1], CFG[2], CFG[3]
CASES = []
for j in (0.75, 1.0, 2.0, 4.0, 8.0):
    CASES.append((0, 200, j, 0, DE, LA, WA, 600))
for j in (-0.75, -1.0, -2.0, -4.0, -8.0):
    CASES.append((0, 200, j, 1, DE, LA, WA, 600))
# the wrong direction must stay silent on the same stream
CASES.append((0, 200, 2.0, 1, DE, LA, WA, 600))
CASES.append((0, 200, -2.0, 0, DE, LA, WA, 600))
# the knobs: lambda buys patience, delta buys quiet, warm buys a mean
for lam in (2.0, 4.0, 8.0, 32.0):
    CASES.append((0, 200, 2.0, 0, DE, lam, WA, 600))
for delta in (0.0, 0.25, 1.0, 1.5):
    CASES.append((0, 200, 2.0, 0, delta, LA, WA, 600))
for warm in (1, 250):
    CASES.append((0, 200, 2.0, 0, DE, LA, warm, 600))
# a ramp is a drift nobody stepped into
for slope in (0.015625, 0.03125, 0.0625):
    CASES.append((1, 150, slope, 0, DE, LA, WA, 400))
# a step at index 0 is not a change, it is a different constant -- nothing to
# detect. A step at 390 of a 400-sample run is a change with almost no evidence
# behind it, and the report has to say so in its counts.
CASES.append((0, 0, 2.0, 0, DE, LA, WA, 400))
CASES.append((0, 390, 2.0, 0, DE, LA, WA, 400))

for shape, at0, jump, dirn, delta, lam, warm, n in CASES:
    r = Run(dirn, delta, lam, warm).feed(0, n, shape, at0, jump)
    row(
        "rsig(%s, 8.0d, 3.0d)"
        % feed(0, n, shape, at0, jump, start(dirn, delta, lam, warm)),
        sig_text(r, 8.0, 3.0),
    )

# -- the delay table ---------------------------------------------------------
# how many samples after a step of size k the detector fires

for j in DELAYS:
    r = Run(*CFG).feed(0, 600, 0, 200, j)
    row(
        "dly(%s, 200)" % feed(0, 600, 0, 200, j, start(*CFG)),
        "%d delay=%d since=%d" % (r.hits, (r.ev[1] - 200) & M, r.ev[2]),
    )

# -- chunking does not move a firing -----------------------------------------
# one row, both runs: a state that is not a value prints two different reports

for shape, at0, jump in STREAMS:
    n = 300
    one = Run(*CFG).feed(0, n, shape, at0, jump)
    for k in (1, 30, 150, 299):
        two = Run(*CFG)
        two.feed(0, k, shape, at0, jump)
        two.feed(k, n - k, shape, at0, jump)
        row(
            "cut(%s, %s)"
            % (
                feed(
                    k,
                    n - k,
                    shape,
                    at0,
                    jump,
                    feed(0, k, shape, at0, jump, start(*CFG)),
                ),
                feed(0, n, shape, at0, jump, start(*CFG)),
            ),
            run_text(two) + " | " + run_text(one),
        )

# -- the false-positive grid -------------------------------------------------
# 3,000 stationary samples a cell, both directions. The configured corner is
# zero and that is the law; the rest is the rate the detector actually has, and
# it is pinned here so a change to the recurrence has to move a number.

for delta, lam in FPGRID:
    for dirn in (0, 1):
        r = Run(dirn, delta, lam, 30).feed(0, 3000, 0, FLAT, 0.0)
        row(
            "hits(%s)" % feed(0, 3000, 0, FLAT, 0.0, start(dirn, delta, lam, 30)),
            str(r.hits),
        )
# the same stream with the tolerance dropped: an unbiased random walk crosses
# any fixed threshold, so delta is not decoration -- it is what buys the quiet
walk = Run(0, 0.0, CFG[2], 30).feed(0, 3000, 0, FLAT, 0.0)
row(
    "hits(%s)" % feed(0, 3000, 0, FLAT, 0.0, start(0, 0.0, CFG[2], 30)),
    str(walk.hits),
)

# -- what the detector carries between reports -------------------------------

for shape, at0, jump in STREAMS:
    r = Run(*CFG).feed(0, 300, shape, at0, jump)
    row(
        "rstat(%s)" % feed(0, 300, shape, at0, jump, start(*CFG)),
        "%d %s" % (r.d.w.n, st(r.d.w)),
    )
row("D.show.dir(D.Up{})", "up")
row("D.show.dir(D.Down{})", "down")

# -- the Hoeffding cut -------------------------------------------------------

# the cut is symmetric in its two counts and driven by the harmonic mean, so
# the pairs that matter are the balanced one, the lopsided one both ways round,
# and the degenerate n=1 end. Only one pair is walked at a second (r, ln 1/d).
for na, nb in ((1, 1), (100, 100), (198, 8), (8, 198), (3000, 1)):
    row(
        "q(D.eps(%d, %d, 8.0d, 3.0d))" % (na, nb),
        q(eps(na, nb, 8.0, 3.0)),
    )
row("q(D.eps(198, 8, 4.0d, 2.0d))", q(eps(198, 8, 4.0, 2.0)))
for shape, at0, jump in STREAMS:
    a = wacc(0, 128, shape, at0, jump)
    b = wacc(128, 128, shape, at0, jump)
    for rr, lnid in ((8.0, 3.0), (0.5, 3.0)):
        row(
            "yn(D.differs(%s, %s, %s, %s))"
            % (
                acc(0, 128, shape, at0, jump),
                acc(128, 128, shape, at0, jump),
                f64(rr),
                f64(lnid),
            ),
            "1" if differs(a, b, rr, lnid) else "0",
        )
# no support on one side is no evidence, whatever the gap
row("yn(D.differs(D.empty(), D.one(1000.0d), 8.0d, 3.0d))", "0")
row("yn(D.differs(D.one(1000.0d), D.empty(), 8.0d, 3.0d))", "0")

assert len(rows) <= 220, "too many rows for the JS lane's closure depth: %d" % len(rows)

print(
    """# Drift against a plain-CPython Welford and a transcription of Page-Hinkley
# (drift_gen.py prints this file). Every float leaves through q() as
# floor(x * 2^20 + 0.5) and never through F64.show: the scale is a power of two,
# so an exactly-representable sample scales without rounding and lands half a
# quantum from the edge, and the generator refuses to emit anything that lands
# nearer than that. The rows that carry a " | " carry both sides of one claim in
# one string -- a merge that lost its count weighting, or a detector whose state
# is not a value, prints two different halves and cannot pass by luck.
import Base
import ../../power/drift.bend as D

def yn(b: Bool) -> String:
  match b:
    case True{}:
      "1"
    case False{}:
      "0"

def qn(+v: F64) -> String:
  U32.show(F64.to_u32(v))

def q.go(+v: F64, neg: Bool) -> String:
  match neg:
    case True{}:
      "-" ++ qn(F64.neg(v))
    case False{}:
      qn(v)

def q.at(+v: F64) -> String:
  q.go(v, F64.is_lt(v, 0.0d))

def q(+x: F64) -> String:
  q.at(F64.round(F64.mul(x, 1048576.0d)))

def st(+s: D.Stat) -> String:
  U32.show(D.count(s)) ++ " " ++ q(D.mean(s)) ++ " " ++ q(D.variance(s))

# count and variance only, for the row whose mean is deliberately far outside
# the quantum's range
def sv(+s: D.Stat) -> String:
  U32.show(D.count(s)) ++ " " ++ q(D.variance(s))

def mg(+a: D.Stat, +b: D.Stat) -> String:
  st(a) ++ " | " ++ st(b)

# -- the stream --------------------------------------------------------------

# a multiply-shift-xor finalizer, not the bare Knuth multiply the rest of this
# tree uses. The bare multiply is a Weyl sequence: its cumulative deviation from
# its own mean stays inside +/-4 over three thousand samples, lag-1 correlation
# -0.42. The statistic this lane computes IS a discrepancy, so a low-discrepancy
# source is the one input that cannot exercise it -- the quiet rows below would
# pass against a detector that had been broken open. Two xor-shift rounds cost
# nothing and buy lag-1 0.0000 and a real random walk.
def h.fin2(+v: U32) -> U32:
  U32.xor(v, U32.shrn(v, 13n))

def h.fin(+u: U32) -> U32:
  h.fin2(U32.mul(U32.xor(u, U32.shrn(u, 15n)), 2246822519))

def h(+p: U32) -> U32:
  h.fin(U32.mul(U32.inc(p), 2654435761))

# noise in [-2, 2) in steps of 1/2048. The thirteen bits come off the TOP of the
# hash and not from a mod: a multiply moves information upward only, so the low
# bits of (p + 1) * C see only the low bits of p. An integer under 2^13 cast to
# F64 and divided by a power of two is exact, so every sample is the same number
# on the interpreter, in V8 and in C.
def nz(+p: U32) -> F64:
  F64.div(F64.sub(U32.to_f64(U32.shrn(h(p), 19n)), 4096.0d), 2048.0d)

# shape 0 is a step of `jump` at `at0`, shape 1 a ramp of `jump` a sample from
# `at0`. A stationary stream is either shape with at0 past the end of the run.
#
# Both guards branch through `match` rather than Bool.pick. Bool.pick is a
# function and so evaluates BOTH arms: before the change point `U32.sub(p, at0)`
# wraps, and the ramp arm computes jump * 4.29e9 -- a number the answer never
# uses. A match never builds it. See docs/omen/lanes/power-13.md.
def lvl.ramp(+p: U32, +at0: U32, +jump: F64, step: Bool) -> F64:
  match step:
    case True{}:
      jump
    case False{}:
      F64.mul(jump, U32.to_f64(U32.sub(p, at0)))

def lvl.at(+shape: U32, +p: U32, +at0: U32, +jump: F64, before: Bool) -> F64:
  match before:
    case True{}:
      0.0d
    case False{}:
      lvl.ramp(p, at0, jump, U32.is_eq(shape, 0))

def lvl(+shape: U32, +p: U32, +at0: U32, +jump: F64) -> F64:
  lvl.at(shape, p, at0, jump, U32.is_lt(p, at0))

def sx(+shape: U32, +p: U32, +at0: U32, +jump: F64) -> F64:
  F64.add(lvl(shape, p, at0, jump), nz(p))

# -- Welford over a range ----------------------------------------------------

def fold(i: Nat, +p: U32, +shape: U32, +at0: U32, +jump: F64, s: D.Stat) -> D.Stat:
  match i:
    case 0n:
      s
    case 1n++k:
      fold(k, U32.inc(p), shape, at0, jump, D.push(s, sx(shape, p, at0, jump)))

# the accumulator over [lo, lo + n), by a straight left fold
def acc(+lo: U32, n: Nat, +shape: U32, +at0: U32, +jump: F64) -> D.Stat:
  fold(n, lo, shape, at0, jump, D.empty())

# the same range merged over a binary tree of depth d: the association a fork
# makes, which is NOT the association the fold above makes. F64 addition is not
# associative, so the two agree to the last few bits and not to the last one --
# the quantum every row prints at is where they are made to agree, and
# drift_gen.py asserts that agreement before it emits a single line.
def tree(d: Nat, +lo: U32, +n: U32, +shape: U32, +at0: U32, +jump: F64) -> D.Stat:
  match d:
    case 0n:
      acc(lo, U32.to_nat(n), shape, at0, jump)
    case 1n++k:
      +hf = U32.shr(n)
      a b = tree(k, lo, hf, shape, at0, jump) tree(k, U32.add(lo, hf), hf, shape, at0, jump)
      D.merge(a, b)

# -- the detector over a range -----------------------------------------------

type Run is Data:
  Run{d: D.PH, ev: D.Ev, hits: U32}

def blank() -> D.Ev:
  D.Ev{D.Up{}, 0, 0, D.empty(), D.empty()}

def start(+dir: D.Dir, +delta: F64, +lam: F64, +warm: U32) -> Run:
  Run{D.new(dir, delta, lam, warm), blank(), 0}

# the configured corner: delta 1/2, lambda 16, warm-up 30. The cheapest cell of
# the sweep in docs/omen/lanes/power-13.md with a measured zero false-positive
# count over 3,000 stationary samples, in BOTH directions.
def up() -> Run:
  start(D.Up{}, 0.5d, 16.0d, 30)

# the FIRST report is the one kept, so a detector that fires twice on one change
# cannot hide the second behind the first -- the count is printed beside it
def land.first(d: D.PH, ev: D.Ev, e: D.Ev, +hits: U32, first: Bool) -> Run:
  match first:
    case True{}:
      Run{d, e, U32.inc(hits)}
    case False{}:
      Run{d, ev, U32.inc(hits)}

def land(r: D.PH & Maybe<&2, D.Ev>, +ev: D.Ev, +hits: U32) -> Run:
  (d, m) = r
  match m:
    case None{}:
      Run{d, ev, hits}
    case Some{e}:
      land.first(d, ev, e, hits, U32.is_eq(hits, 0))

# feed takes a Run and gives one back, so a run can be cut anywhere and resumed
def feed(i: Nat, +p: U32, +shape: U32, +at0: U32, +jump: F64, r: Run) -> Run:
  match i:
    case 0n:
      r
    case 1n++k:
      match r:
        case Run{d, ev, hits}:
          feed(k, U32.inc(p), shape, at0, jump, land(D.step(d, sx(shape, p, at0, jump)), ev, hits))

def eshow(e: D.Ev) -> String:
  match e:
    case D.Ev{dir, at, since, before, after}:
      D.show.dir(dir) ++ " @" ++ U32.show(at) ++ " ~" ++ U32.show(since) ++ " | " ++ st(before) ++ " | " ++ st(after)

def rshow(r: Run) -> String:
  match r:
    case Run{d, ev, hits}:
      U32.show(hits) ++ " " ++ eshow(ev)

def cut(a: Run, b: Run) -> String:
  rshow(a) ++ " | " ++ rshow(b)

def hits(r: Run) -> String:
  match r:
    case Run{d, ev, hits}:
      U32.show(hits)

def rstat.at(+d: D.PH) -> String:
  U32.show(D.seen(d)) ++ " " ++ st(D.stat(d))

def rstat(r: Run) -> String:
  match r:
    case Run{d, ev, hits}:
      rstat.at(d)

def evsig(r: Run, +rng: F64, +lnid: F64) -> Bool:
  match r:
    case Run{d, ev, hits}:
      D.ev.differs(ev, rng, lnid)

# the report and its significance in one row: Page-Hinkley says when, and the
# Hoeffding cut says whether the gap it found is wider than luck allows
def rsig(+r: Run, +rng: F64, +lnid: F64) -> String:
  rshow(r) ++ " sig=" ++ yn(evsig(r, rng, lnid))

def dly.ev(e: D.Ev, +at0: U32, +hits: U32) -> String:
  match e:
    case D.Ev{dir, at, since, before, after}:
      U32.show(hits) ++ " delay=" ++ U32.show(U32.sub(at, at0)) ++ " since=" ++ U32.show(since)

def dly(r: Run, +at0: U32) -> String:
  match r:
    case Run{d, ev, hits}:
      dly.ev(ev, at0, hits)

def main() -> IO(Unit):
  do IO<Unit>:"""
)
for r in rows:
    print("    IO.print(%s)" % r)
for w in want:
    print("#|" + w)
