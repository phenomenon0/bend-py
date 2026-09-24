#!/usr/bin/env python3
# The oracle for sketch.bend: prints the whole fixture.
#
# Two things are computed here, and they are computed twice over, differently.
#
#   the truth       set(), collections.Counter, sorted() -- what the stream
#                   actually contains. CPython's own containers, no sketch.
#   the sketch      a flat list of registers with max / min / saturating add
#                   over it. A list, not a tree: Bend's Bank is a perfect
#                   binary tree of cells and this is a Python list of the same
#                   cells, so a bug in the descent, the mask, the leaf order or
#                   the zip has nothing to hide behind here.
#
# Every accuracy claim is asserted between the two before a row is emitted, so
# a fixture row can never pin a sketch that is merely self-consistent:
#
#   |hll - |set(xs)|| <= 3.5 * 1.04/sqrt(m) * |set(xs)|    HLL's own bound
#   cm(x) >= Counter(xs)[x], and <= it + e/w * total       CountMin never under
#   |mh/k - jaccard(set(a), set(b))| <= 4/sqrt(k)          MinHash's own bound
#   dd(q) is the bucket of sorted(xs)[floor(q*(n-1))]      exactly, and that
#                                                          bucket is within
#                                                          8.64% of the value
#
# and the four laws of the algebra itself:
#
#   merge(merge(a,b),c) == merge(a,merge(b,c))   associativity, cell for cell
#   merge(a,b) == merge(b,a)                     commutativity
#   merge(a,a) == a                              idempotence, for max and min
#   merge refuses when the fingerprints differ   and the refusal names both
#
# Floats appear in exactly one printed number, HyperLogLog's estimate, and
# every one of them is asserted to be at least 0.01 away from an integer
# boundary -- so no difference between libm's log and V8's Math.log in the last
# ulp can change a truncation and split the C lane from the JS lane.
import math
from collections import Counter

M32 = 0xFFFFFFFF
SEED = 7
HLG, HM = 6, 64  # HyperLogLog: 2^6 = 64 registers
CLG, CM_ = 6, 64  # CountMin: 4 rows of 16
MLG, MK = 6, 64  # MinHash: 64 slots
DLG, DN = 7, 128  # DDSketch: 128 buckets


# -- the hash, the only part of the reference that must mirror the Bend file --


def mix(x):
    x &= M32
    x ^= x >> 16
    x = (x * 0x85EBCA6B) & M32
    x ^= x >> 13
    x = (x * 0xC2B2AE35) & M32
    return x ^ (x >> 16)


def hsh(seed, x):
    return mix(((x * 0x9E3779B1) & M32) ^ (((seed * 0x85EBCA77) + 0xC2B2AE3D) & M32))


def nlz(x):
    """Leading zeros -- from int.bit_length(), not from a popcount ladder."""
    return 32 - x.bit_length()


def sat(a, b):
    return min(a + b, M32)


def ilg(x):
    """floor(2^15 * log2(x)) by the same squaring ladder sketch.bend runs, and
    asserted against math.log2 every time it is called."""
    e = x.bit_length() - 1
    y = x >> (e - 15) if e >= 15 else x << (15 - e)
    acc = 0
    for _ in range(15):
        z = (y * y) >> 15
        assert z <= M32
        b = z >> 16
        y, acc = z >> b, acc * 2 + b
    r = (e << 15) + acc
    assert abs(r / 32768 - math.log2(x)) < 0.002, x
    return r


# -- DDSketch's mapping: ceil(4 * log2(x)) in exact integers -----------------

THR = [1 << 31] + [math.floor((1 << 31) * 2 ** (j / 4)) for j in (1, 2, 3)]
GAMMA = 2 ** (1 / 4)
ALPHA = (GAMMA - 1) / (GAMMA + 1)


def ddidx(x):
    x = max(x, 1)
    z = nlz(x)
    mm = (x << z) & M32
    j = 4
    for k in range(4):
        if mm <= THR[k]:
            j = k
            break
    return 4 * (31 - z) + j


for _t in [1, 2, 3, 4, 5, 7, 8, 9, 16, 100, 1000, 65535, 1 << 20, (1 << 31) - 1]:
    # the mapping is the ceiling of the real log, exactly
    assert ddidx(_t) == math.ceil(4 * math.log2(_t)), _t
    # and the bucket it names holds the value: (gamma^(i-1), gamma^i]
    assert GAMMA ** (ddidx(_t) - 1) <= _t <= GAMMA ** ddidx(_t) * (1 + 1e-9), _t


# -- the sketch, as a flat list ----------------------------------------------

ALGOS = {"hll": 0, "cm": 1, "mh": 2, "dd": 3}


class Ref:
    def __init__(self, algo, seed, cells):
        self.a, self.s, self.n = algo, seed, cells
        self.c = [M32 if algo == "mh" else 0] * cells

    def copy(self):
        r = Ref(self.a, self.s, self.n)
        r.c = list(self.c)
        return r

    def fp(self):
        return (self.a, self.s, self.n)

    def op(self, x, y):
        return {"hll": max, "mh": min, "cm": sat, "dd": sat}[self.a](x, y)

    def fuse(self, i, v):
        self.c[i] = self.op(self.c[i], v)

    def merge(self, o):
        if self.fp() != o.fp():
            return ("mismatch", self.fp(), o.fp())
        r = self.copy()
        r.c = [r.op(x, y) for x, y in zip(self.c, o.c)]
        return r

    def tag(self):
        return (ALGOS[self.a] * 1000003 + self.s * 31 + self.n) & M32

    def digest(self):
        d = self.tag()
        for w in self.c:
            d = (d * 31 + w) & M32
        return d

    # -- per algorithm --
    def hll_add(self, x):
        h = hsh(self.s, x)
        lo = self.n - 1
        self.fuse(h & lo, nlz(h & (~lo & M32)) + 1)

    def hll_est(self):
        """Flajolet's estimator in integers -- see the note in sketch.bend. The
        float version is computed beside it and the two are asserted to agree
        to within HLL's own standard error, so the fixed point is checked
        against the textbook formula and not merely against itself."""
        m, v = self.n, self.c.count(0)
        d = m.bit_length() - 1
        k = min(24, 32 - min(32, 2 * d))
        sh = 8 - min(8, 2 * d)
        al = {16: 2890137797, 32: 2993204531, 64: 3044758155}.get(m, 3098137299)
        s = sum(1 << (k - min(r, k)) for r in self.c)
        assert s <= M32 and (al >> sh) <= M32
        e = (al >> sh) // s
        if 2 * e <= 5 * m and v > 0:
            t = ilg(m) - ilg(v)
            e = (m * (((t >> 5) * 22713) >> 10)) >> 15
            exact = m * math.log(m / v)
        else:
            exact = {16: 0.673, 32: 0.697, 64: 0.709}.get(
                m, 0.7213 / (1 + 1.079 / m)
            ) * m * m / sum(2.0 ** -min(r, k) for r in self.c)
        # the fixed point tracks the double it replaces to well inside HLL's
        # own error: a rounding here can never be what a row is pinning
        assert abs(e - exact) <= 0.02 * exact + 1, (e, exact)
        return e

    def cm_slots(self, x):
        w = self.n >> 2
        return [
            r * w + (hsh((self.s + r * 0x85EBCA77) & M32, x) & (w - 1))
            for r in range(4)
        ]

    def cm_add(self, x, c):
        for i in self.cm_slots(x):
            self.fuse(i, c)

    def cm_est(self, x):
        return min(self.c[i] for i in self.cm_slots(x))

    def cm_total(self):
        t = 0
        for w in self.c:
            t = sat(t, w)
        return t // 4

    def mh_add(self, x):
        for j in range(self.n):
            self.fuse(j, hsh((self.s + j * 0x9E3779B1) & M32, x))

    def mh_same(self, o):
        return sum(1 for x, y in zip(self.c, o.c) if x == y)

    def dd_add(self, x):
        self.fuse(min(ddidx(x), self.n - 1), 1)

    def dd_count(self):
        t = 0
        for w in self.c:
            t = sat(t, w)
        return t

    def dd_q(self, qp):
        n = self.dd_count()
        if n == 0:
            return ("undefined",)
        rank = ((qp * (n - 1)) & M32) // 1000
        for i, w in enumerate(self.c):
            if rank < w:
                return i
            rank -= w
        return M32


# -- the streams -------------------------------------------------------------
# value at step t, the same arithmetic the fixture's `val` does. a*t stays
# under 2^32 for every t the fixture reaches, so no wrap is ever hidden here.


def val(t, a, b, k):
    assert t * a + b <= M32
    return (t * a + b) % k


def dsq(t, a, b, k):
    v = val(t, a, b, k) + 1
    return v * v


def dlin(t, a, b, k):
    """The DDSketch streams start at 1: a relative error is a statement about
    a positive value, and zero is a deliberate ceiling tested on its own."""
    return val(t, a, b, k) + 1


def stream(kind, n, off, a, b, k):
    f = {"lin": val, "sq": dsq, "dlin": dlin}[kind]
    return [f(off + t, a, b, k) for t in range(n)]


def build(algo, kind, n, off, a, b, k, seed=SEED):
    lg = {"hll": HLG, "cm": CLG, "mh": MLG, "dd": DLG}[algo]
    r = Ref(algo, seed, 1 << lg)
    for t, v in enumerate(stream(kind, n, off, a, b, k)):
        if algo == "hll":
            r.hll_add(v)
        elif algo == "cm":
            r.cm_add(v, (off + t) % 3 + 1)
        elif algo == "mh":
            r.mh_add(v)
        else:
            r.dd_add(v)
    return r


def bpart(algo, kind, n, off, a, b, k, seed=SEED):
    """The Bend expression that builds the same sketch."""
    lg = {"hll": HLG, "cm": CLG, "mh": MLG, "dd": DLG}[algo]
    p = {"lin": "", "dlin": "", "sq": "q"}[kind]
    return "%s%spart(%dn, Sk.%s.new(%d, %dn), %d, %d, %d, %d)" % (
        algo[0] if algo != "cm" else "c",
        p,
        n,
        algo,
        seed,
        lg,
        off,
        a,
        b,
        k,
    )


# -- laws --------------------------------------------------------------------


def law(a, b, c):
    """Associativity, commutativity, and (where the op is idempotent) that a
    sketch merged with itself is itself. Asserted on every trio the fixture
    mentions, so a row that breaks one cannot reach the file."""
    ab_c = a.merge(b).merge(c)
    a_bc = a.merge(b.merge(c))
    assert ab_c.c == a_bc.c, a.a
    assert a.merge(b).c == b.merge(a).c, a.a
    if a.a in ("hll", "mh"):
        assert a.merge(a).c == a.c, a.a
    # and a merge across fingerprints is an error, not a number
    o = Ref(a.a, a.s + 1, a.n)
    assert a.merge(o)[0] == "mismatch"


rows, want = [], []


def row(call, text):
    rows.append(call)
    want.append(text)


def sb(r):
    return str(r.digest())


def mism(x, y):
    return "mismatch %s:%d:%d vs %s:%d:%d" % (x + y)


# ---------------------------------------------------------------- primitives

for x in [0, 1, 2, 1000, 4294967295]:
    row("num(Sk.hash(7, %d))" % x, str(hsh(7, x)))
for x in [0, 1, 255, 2147483648, 4294967295]:
    row("num(Sk.nlz(%d))" % x, str(nlz(x)))
for x in [0, 1, 2, 3, 4, 5, 8, 17, 1000, 65535, 2147483647]:
    row("num(Sk.dd.idx(%d))" % x, str(ddidx(x)))

# ------------------------------------------------------------- fingerprints

for a, lg in [("hll", HLG), ("cm", CLG), ("mh", MLG), ("dd", DLG)]:
    row("sfp(Sk.fp.of(Sk.%s.new(7, %dn)))" % (a, lg), "%s:7:%d" % (a, 1 << lg))
    row("num(Sk.digest(Sk.%s.new(7, %dn)))" % (a, lg), sb(Ref(a, 7, 1 << lg)))

# ------------------------------------------------------------- HyperLogLog
# a row is "estimate truth": the sketch's answer beside what set() counted.

HS = [
    (400, 1, 0, 100000),  # 400 distinct
    (2000, 1, 0, 100000),  # 2000 distinct
    (4096, 1, 0, 100000),  # 4096 distinct
    (4096, 1, 0, 64),  # 64 distinct out of 4096 arrivals
    (4096, 1, 0, 700),  # 700 distinct
    (20000, 7, 3, 100000),  # 20000 distinct, a stride
    (64, 1, 0, 100000),  # 64 distinct -- linear counting territory
    (8, 1, 0, 100000),  # 8 distinct
]
for n, a, b, k in HS:
    r = build("hll", "lin", n, 0, a, b, k)
    truth = len(set(stream("lin", n, 0, a, b, k)))
    err = abs(r.hll_est() - truth) / truth
    assert err <= 3.5 * 1.04 / math.sqrt(HM), (n, k, r.hll_est(), truth, err)
    row(
        "erow(%s, %d)" % (bpart("hll", "lin", n, 0, a, b, k), truth),
        "%d %d" % (r.hll_est(), truth),
    )
    row("drow(%s)" % bpart("hll", "lin", n, 0, a, b, k), sb(r))

# merge: two halves against the whole, both digests in one row
for n, a, b, k in HS[:5]:
    h = n // 2
    x = build("hll", "lin", h, 0, a, b, k)
    y = build("hll", "lin", h, h, a, b, k)
    w = build("hll", "lin", n, 0, a, b, k)
    law(x, y, w)
    assert x.merge(y).c == w.c  # HLL merge is exact: no approximation in it
    row(
        "rr(Sk.merge(%s, %s), Done{%s})"
        % (
            bpart("hll", "lin", h, 0, a, b, k),
            bpart("hll", "lin", h, h, a, b, k),
            bpart("hll", "lin", n, 0, a, b, k),
        ),
        "%s %s" % (sb(x.merge(y)), sb(w)),
    )

# three-way associativity, both bracketings in one row
for n, a, b, k in HS[:4]:
    t = n // 3
    ps = [build("hll", "lin", t, i * t, a, b, k) for i in range(3)]
    law(*ps)
    e = [bpart("hll", "lin", t, i * t, a, b, k) for i in range(3)]
    row(
        "rr(Sk.merge2(Sk.merge(%s, %s), Done{%s}), Sk.merge2(Done{%s}, Sk.merge(%s, %s)))"
        % (e[0], e[1], e[2], e[0], e[1], e[2]),
        "%s %s"
        % (sb(ps[0].merge(ps[1]).merge(ps[2])), sb(ps[0].merge(ps[1].merge(ps[2])))),
    )

# idempotence: max is idempotent, so a sketch merged with itself is itself
for n, a, b, k in HS[:3]:
    x = build("hll", "lin", n, 0, a, b, k)
    assert x.merge(x).c == x.c
    row(
        "rr(Sk.merge(%s, %s), Done{%s})"
        % tuple([bpart("hll", "lin", n, 0, a, b, k)] * 3),
        "%s %s" % (sb(x.merge(x)), sb(x)),
    )

# the estimate of a merge is the estimate of the union
for n, a, b, k in HS[:4]:
    h = n // 2
    x = build("hll", "lin", h, 0, a, b, k)
    y = build("hll", "lin", h, h, a, b, k)
    truth = len(set(stream("lin", n, 0, a, b, k)))
    mg = x.merge(y)
    assert abs(mg.hll_est() - truth) / truth <= 3.5 * 1.04 / math.sqrt(HM)
    row(
        "mrow(Sk.merge(%s, %s), %d)"
        % (
            bpart("hll", "lin", h, 0, a, b, k),
            bpart("hll", "lin", h, h, a, b, k),
            truth,
        ),
        "%d %d" % (mg.hll_est(), truth),
    )

# and the refusals: a different seed, a different width, a different algorithm
row(
    "sres(Sk.merge(Sk.hll.new(7, 6n), Sk.hll.new(9, 6n)))",
    mism(("hll", 7, 64), ("hll", 9, 64)),
)
row(
    "sres(Sk.merge(Sk.hll.new(7, 6n), Sk.hll.new(7, 5n)))",
    mism(("hll", 7, 64), ("hll", 7, 32)),
)
row(
    "sres(Sk.merge(Sk.hll.new(7, 6n), Sk.cm.new(7, 6n)))",
    mism(("hll", 7, 64), ("cm", 7, 64)),
)
row(
    "sres(Sk.merge2(Sk.merge(Sk.hll.new(7, 6n), Sk.hll.new(9, 6n)), Done{Sk.hll.new(7, 6n)}))",
    mism(("hll", 7, 64), ("hll", 9, 64)),
)

# the fork tree: 2^d leaves merged back must be the sequential sketch, at every
# depth. One number, six times, and the seventh row is the sequential pass.
TN, TA, TB, TK = 4096, 1, 0, 100000
tw = build("hll", "lin", TN, 0, TA, TB, TK)
for d in range(6):
    leaf = TN >> d
    ps = [build("hll", "lin", leaf, i * leaf, TA, TB, TK) for i in range(1 << d)]
    acc = ps[0]
    for q in ps[1:]:
        acc = acc.merge(q)
    assert acc.c == tw.c, d
    row("sres(htree(%dn, 0, %d, %d, %d, %d))" % (d, TN, TA, TB, TK), sb(tw))
row("drow(%s)" % bpart("hll", "lin", TN, 0, TA, TB, TK), sb(tw))

# ------------------------------------------------------------------ CountMin
# a row is "estimate truth": CountMin never underestimates, and the gap is the
# collision mass -- both numbers in one string, so a row that underestimates
# cannot be printed.

CS = [(2048, 1, 0, 256), (4096, 3, 1, 1024)]
for n, a, b, k in CS:
    r = build("cm", "lin", n, 0, a, b, k)
    truth = Counter()
    for t, v in enumerate(stream("lin", n, 0, a, b, k)):
        truth[v] += t % 3 + 1
    total = sum(truth.values())
    for key in sorted(truth)[:: max(1, len(truth) // 8)][:8]:
        est = r.cm_est(key)
        assert est >= truth[key], (key, est, truth[key])
        assert est <= truth[key] + math.e / (CM_ >> 2) * total, (key, est, total)
        row(
            "crow(%s, %d, %d)" % (bpart("cm", "lin", n, 0, a, b, k), key, truth[key]),
            "%d %d" % (est, truth[key]),
        )
    row("num(Sk.cm.total(%s))" % bpart("cm", "lin", n, 0, a, b, k), str(r.cm_total()))
    assert r.cm_total() == total
    row("drow(%s)" % bpart("cm", "lin", n, 0, a, b, k), sb(r))

for n, a, b, k in CS:
    h = n // 2
    x = build("cm", "lin", h, 0, a, b, k)
    y = build("cm", "lin", h, h, a, b, k)
    w = build("cm", "lin", n, 0, a, b, k)
    law(x, y, w)
    assert x.merge(y).c == w.c  # counts add: a merge is exact
    row(
        "rr(Sk.merge(%s, %s), Done{%s})"
        % (
            bpart("cm", "lin", h, 0, a, b, k),
            bpart("cm", "lin", h, h, a, b, k),
            bpart("cm", "lin", n, 0, a, b, k),
        ),
        "%s %s" % (sb(x.merge(y)), sb(w)),
    )
    t = n // 3
    ps = [build("cm", "lin", t, i * t, a, b, k) for i in range(3)]
    law(*ps)
    e = [bpart("cm", "lin", t, i * t, a, b, k) for i in range(3)]
    row(
        "rr(Sk.merge2(Sk.merge(%s, %s), Done{%s}), Sk.merge2(Done{%s}, Sk.merge(%s, %s)))"
        % (e[0], e[1], e[2], e[0], e[1], e[2]),
        "%s %s"
        % (sb(ps[0].merge(ps[1]).merge(ps[2])), sb(ps[0].merge(ps[1].merge(ps[2])))),
    )

# the ceiling is saturating, and saturation is where a counter would wrap: a
# counter at 2^32-1 charged ten more stays there. A plain add here is still
# associative and still commutative, so no law row can see it -- only a row
# that actually reaches the ceiling can.
zc = Ref("cm", 7, 16)
zc.cm_add(5, M32)
zc.cm_add(5, 10)
assert zc.cm_est(5) == M32
assert zc.merge(zc).cm_est(5) == M32
row("crow(cmsat(), 5, %d)" % M32, "%d %d" % (zc.cm_est(5), M32))
row("drow(cmsat())", sb(zc))
row(
    "rr(Sk.merge(cmsat(), cmsat()), Done{cmsat()})",
    "%s %s" % (sb(zc.merge(zc)), sb(zc)),
)

row(
    "sres(Sk.merge(Sk.cm.new(7, 6n), Sk.cm.new(7, 4n)))",
    mism(("cm", 7, 64), ("cm", 7, 16)),
)
row(
    "sres(Sk.merge(Sk.cm.new(3, 6n), Sk.cm.new(7, 6n)))",
    mism(("cm", 3, 64), ("cm", 7, 64)),
)

# the CountMin fork tree
CN, CA, CB, CK = 1024, 1, 0, 256
cw = build("cm", "lin", CN, 0, CA, CB, CK)
for d in range(3):
    row("sres(ctree(%dn, 0, %d, %d, %d, %d))" % (d, CN, CA, CB, CK), sb(cw))

# ------------------------------------------------------------------- MinHash
# a row is "matching slots, true Jaccard in per mille": the estimate is
# matches/k, and the truth is |A n B| / |A u B| from two CPython sets.

MS = [
    ((512, 1, 0, 1024, 0), (512, 1, 0, 1024, 256)),  # half overlap
    ((512, 1, 0, 1024, 0), (512, 1, 0, 1024, 0)),  # identical
    ((512, 1, 0, 1024, 0), (512, 1, 0, 1024, 512)),  # disjoint
    ((600, 1, 0, 1024, 0), (600, 1, 0, 1024, 300)),  # half overlap, odd size
    ((256, 1, 0, 4096, 0), (256, 1, 0, 4096, 64)),  # three quarters
    ((1000, 3, 1, 2048, 0), (1000, 3, 1, 2048, 500)),  # a stride
]
for (n1, a1, b1, k1, o1), (n2, a2, b2, k2, o2) in MS:
    x = build("mh", "lin", n1, o1, a1, b1, k1)
    y = build("mh", "lin", n2, o2, a2, b2, k2)
    sa = set(stream("lin", n1, o1, a1, b1, k1))
    sbb = set(stream("lin", n2, o2, a2, b2, k2))
    j = len(sa & sbb) / len(sa | sbb)
    m = x.mh_same(y)
    assert abs(m / MK - j) <= 4 / math.sqrt(MK), (m, j)
    row(
        "jrow(Sk.mh.jaccard(%s, %s), %d)"
        % (
            bpart("mh", "lin", n1, o1, a1, b1, k1),
            bpart("mh", "lin", n2, o2, a2, b2, k2),
            round(j * 1000),
        ),
        "%d %d" % (m, round(j * 1000)),
    )

MB = (512, 1, 0, 1024)
for off in [0, 256, 512]:
    r = build("mh", "lin", MB[0], off, *MB[1:])
    row("drow(%s)" % bpart("mh", "lin", MB[0], off, *MB[1:]), sb(r))

for n, a, b, k in [(512, 1, 0, 1024), (600, 1, 0, 4096)]:
    h = n // 2
    x = build("mh", "lin", h, 0, a, b, k)
    y = build("mh", "lin", h, h, a, b, k)
    w = build("mh", "lin", n, 0, a, b, k)
    law(x, y, w)
    assert x.merge(y).c == w.c  # the least of a union is the least of the leasts
    row(
        "rr(Sk.merge(%s, %s), Done{%s})"
        % (
            bpart("mh", "lin", h, 0, a, b, k),
            bpart("mh", "lin", h, h, a, b, k),
            bpart("mh", "lin", n, 0, a, b, k),
        ),
        "%s %s" % (sb(x.merge(y)), sb(w)),
    )
    assert x.merge(x).c == x.c
    row(
        "rr(Sk.merge(%s, %s), Done{%s})"
        % tuple([bpart("mh", "lin", h, 0, a, b, k)] * 3),
        "%s %s" % (sb(x.merge(x)), sb(x)),
    )
    # a sketch is perfectly similar to itself: every slot matches
    row(
        "jrow(Sk.mh.jaccard(%s, %s), %d)"
        % tuple([bpart("mh", "lin", h, 0, a, b, k)] * 2 + [1000]),
        "%d 1000" % MK,
    )
    t = n // 3
    ps = [build("mh", "lin", t, i * t, a, b, k) for i in range(3)]
    law(*ps)
    e = [bpart("mh", "lin", t, i * t, a, b, k) for i in range(3)]
    row(
        "rr(Sk.merge2(Sk.merge(%s, %s), Done{%s}), Sk.merge2(Done{%s}, Sk.merge(%s, %s)))"
        % (e[0], e[1], e[2], e[0], e[1], e[2]),
        "%s %s"
        % (sb(ps[0].merge(ps[1]).merge(ps[2])), sb(ps[0].merge(ps[1].merge(ps[2])))),
    )

row(
    "sres(Sk.merge(Sk.mh.new(7, 6n), Sk.mh.new(8, 6n)))",
    mism(("mh", 7, 64), ("mh", 8, 64)),
)
row(
    "jres(Sk.mh.jaccard(Sk.mh.new(7, 6n), Sk.mh.new(7, 5n)))",
    mism(("mh", 7, 64), ("mh", 7, 32)),
)
row(
    "jres(Sk.mh.jaccard(Sk.mh.new(7, 6n), Sk.dd.new(7, 6n)))",
    mism(("mh", 7, 64), ("dd", 7, 64)),
)

# ----------------------------------------------------------------- DDSketch
# a row is "the sketch's bucket, the bucket of the true quantile". They are
# equal exactly: the buckets partition the values monotonically, so walking
# them by rank finds the bucket sorted(xs)[rank] is in, and a row with two
# different numbers is a broken walk or a broken mapping.

DS = [("dlin", 3000, 1, 0, 5000), ("sq", 3000, 1, 0, 181), ("dlin", 1024, 7, 3, 64)]
QS = [0, 100, 250, 500, 750, 900, 990, 1000]
for kind, n, a, b, k in DS:
    xs = stream(kind, n, 0, a, b, k)
    r = build("dd", kind, n, 0, a, b, k)
    srt = sorted(xs)
    for q in QS:
        rank = q * (len(srt) - 1) // 1000
        tru = srt[rank]
        want_i = min(ddidx(tru), DN - 1)
        got = r.dd_q(q)
        assert got == want_i, (kind, q, got, want_i, tru)
        # the bucket's own representative is within alpha of the true value
        rep = 2 * GAMMA**got / (GAMMA + 1)
        assert abs(rep - tru) <= ALPHA * tru + 1e-9, (tru, rep)
        row(
            "qrow(Sk.dd.quantile(%s, %d), %d)"
            % (bpart("dd", kind, n, 0, a, b, k), q, want_i),
            "%d %d" % (got, want_i),
        )
    row("num(Sk.dd.count(%s))" % bpart("dd", kind, n, 0, a, b, k), str(r.dd_count()))
    assert r.dd_count() == n
    row("drow(%s)" % bpart("dd", kind, n, 0, a, b, k), sb(r))

for kind, n, a, b, k in DS[:2]:
    h = n // 2
    x = build("dd", kind, h, 0, a, b, k)
    y = build("dd", kind, h, h, a, b, k)
    w = build("dd", kind, n, 0, a, b, k)
    law(x, y, w)
    assert x.merge(y).c == w.c
    row(
        "rr(Sk.merge(%s, %s), Done{%s})"
        % (
            bpart("dd", kind, h, 0, a, b, k),
            bpart("dd", kind, h, h, a, b, k),
            bpart("dd", kind, n, 0, a, b, k),
        ),
        "%s %s" % (sb(x.merge(y)), sb(w)),
    )
    t = n // 3
    ps = [build("dd", kind, t, i * t, a, b, k) for i in range(3)]
    law(*ps)
    e = [bpart("dd", kind, t, i * t, a, b, k) for i in range(3)]
    row(
        "rr(Sk.merge2(Sk.merge(%s, %s), Done{%s}), Sk.merge2(Done{%s}, Sk.merge(%s, %s)))"
        % (e[0], e[1], e[2], e[0], e[1], e[2]),
        "%s %s"
        % (sb(ps[0].merge(ps[1]).merge(ps[2])), sb(ps[0].merge(ps[1].merge(ps[2])))),
    )
    # a merged sketch answers the quantile of the union
    srt = sorted(stream(kind, n, 0, a, b, k))
    for q in [250, 500, 900]:
        tru = srt[q * (len(srt) - 1) // 1000]
        mg = x.merge(y)
        assert mg.dd_q(q) == min(ddidx(tru), DN - 1)
        row(
            "mq(Sk.merge(%s, %s), %d, %d)"
            % (
                bpart("dd", kind, h, 0, a, b, k),
                bpart("dd", kind, h, h, a, b, k),
                q,
                min(ddidx(tru), DN - 1),
            ),
            "%d %d" % (mg.dd_q(q), min(ddidx(tru), DN - 1)),
        )

# the empty sketch has no quantile, and says so
row("jres(Sk.dd.quantile(Sk.dd.new(7, 7n), 500))", "undefined")
# the zero ceiling: 0 lands in bucket 0, beside the values at or below 1
z = Ref("dd", 7, DN)
for v in [0, 0, 1, 5]:
    z.dd_add(v)
assert z.c[0] == 3 and ddidx(1) == 0
row("qrow(Sk.dd.quantile(dz(), 0), 0)", "0 0")
row(
    "qrow(Sk.dd.quantile(dz(), 1000), %d)" % ddidx(5),
    "%d %d" % (z.dd_q(1000), ddidx(5)),
)
row("num(Sk.dd.count(dz()))", "4")
row("drow(dz())", sb(z))
# and the top ceiling: anything past the last bucket clamps into it
row("num(Sk.dd.idx(4294967295))", str(ddidx(4294967295)))
big = Ref("dd", 7, DN)
big.dd_add(4294967295)
row(
    "qrow(Sk.dd.quantile(dbig(), 500), %d)" % (DN - 1),
    "%d %d" % (big.dd_q(500), DN - 1),
)

DN_, DA, DB, DK = 1024, 1, 0, 5000
dw = build("dd", "dlin", DN_, 0, DA, DB, DK)
for d in range(3):
    row("sres(dtree(%dn, 0, %d, %d, %d, %d))" % (d, DN_, DA, DB, DK), sb(dw))

assert len(rows) < 260, len(rows)

print(
    """# Sketch algebra against a flat CPython list of registers and the truth from
# set(), Counter() and sorted() (sketch_gen.py prints this file). A row that
# carries two numbers carries both sides of one claim: the sketch's answer and
# what it is answering about, or two bracketings of the same merge, so an
# implementation that satisfies one side cannot print the line.
import Base
import ../../power/sketch.bend as Sk

def num(n: U32) -> String:
  U32.show(n)

def sfp(f: Sk.Fp) -> String:
  match f:
    case Sk.Fp{k, s, n}:
      Sk.show.algo(k) ++ ":" ++ U32.show(s) ++ ":" ++ U32.show(n)

def serr(e: Sk.Error) -> String:
  match e:
    case Sk.Mismatch{w, g}:
      "mismatch " ++ sfp(w) ++ " vs " ++ sfp(g)
    case Sk.Undefined{}:
      "undefined"

def sres(r: Sk.Res(Sk.Sketch)) -> String:
  match r:
    case Done{s}:
      U32.show(Sk.digest(s))
    case Fail{e}:
      serr(e)

def jres(r: Sk.Res(U32)) -> String:
  match r:
    case Done{x}:
      U32.show(x)
    case Fail{e}:
      serr(e)

def rr(x: Sk.Res(Sk.Sketch), y: Sk.Res(Sk.Sketch)) -> String:
  sres(x) ++ " " ++ sres(y)

def drow(s: Sk.Sketch) -> String:
  U32.show(Sk.digest(s))

# the estimate beside the truth set() counted
def erow(s: Sk.Sketch, +t: U32) -> String:
  U32.show(Sk.hll.estimate(s)) ++ " " ++ U32.show(t)

def mrow(r: Sk.Res(Sk.Sketch), +t: U32) -> String:
  match r:
    case Done{s}:
      erow(s, t)
    case Fail{e}:
      serr(e)

def crow(s: Sk.Sketch, +x: U32, +t: U32) -> String:
  U32.show(Sk.cm.estimate(s, x)) ++ " " ++ U32.show(t)

def jrow(r: Sk.Res(U32), +t: U32) -> String:
  jres(r) ++ " " ++ U32.show(t)

def qrow(r: Sk.Res(U32), +t: U32) -> String:
  jres(r) ++ " " ++ U32.show(t)

def mq(r: Sk.Res(Sk.Sketch), +q: U32, +t: U32) -> String:
  match r:
    case Done{s}:
      qrow(Sk.dd.quantile(s, q), t)
    case Fail{e}:
      serr(e)

# the streams: value at step t, and the squared variant that spreads a
# DDSketch over four octaves instead of one
def val(+t: U32, +a: U32, +b: U32, +k: U32) -> U32:
  U32.mod(U32.add(U32.mul(t, a), b), k)

def sq(+t: U32, +a: U32, +b: U32, +k: U32) -> U32:
  +v = U32.add(val(t, a, b, k), 1)
  U32.mul(v, v)

def hpart(i: Nat, s: Sk.Sketch, +off: U32, +a: U32, +b: U32, +k: U32) -> Sk.Sketch:
  match i:
    case 0n:
      s
    case 1n++p:
      hpart(p, Sk.hll.add(s, val(U32.add(off, U32.from_nat(p)), a, b, k)), off, a, b, k)

def cpart(i: Nat, s: Sk.Sketch, +off: U32, +a: U32, +b: U32, +k: U32) -> Sk.Sketch:
  match i:
    case 0n:
      s
    case 1n++p:
      +t = U32.add(off, U32.from_nat(p))
      cpart(p, Sk.cm.add(s, val(t, a, b, k), U32.add(U32.mod(t, 3), 1)), off, a, b, k)

def mpart(i: Nat, s: Sk.Sketch, +off: U32, +a: U32, +b: U32, +k: U32) -> Sk.Sketch:
  match i:
    case 0n:
      s
    case 1n++p:
      mpart(p, Sk.mh.add(s, val(U32.add(off, U32.from_nat(p)), a, b, k)), off, a, b, k)

def dpart(i: Nat, s: Sk.Sketch, +off: U32, +a: U32, +b: U32, +k: U32) -> Sk.Sketch:
  match i:
    case 0n:
      s
    case 1n++p:
      dpart(p, Sk.dd.add(s, U32.inc(val(U32.add(off, U32.from_nat(p)), a, b, k))), off, a, b, k)

def dqpart(i: Nat, s: Sk.Sketch, +off: U32, +a: U32, +b: U32, +k: U32) -> Sk.Sketch:
  match i:
    case 0n:
      s
    case 1n++p:
      dqpart(p, Sk.dd.add(s, sq(U32.add(off, U32.from_nat(p)), a, b, k)), off, a, b, k)

# a counter driven to the ceiling and charged again
def cmsat() -> Sk.Sketch:
  Sk.cm.add(Sk.cm.add(Sk.cm.new(7, 4n), 5, 4294967295), 5, 10)

def dz() -> Sk.Sketch:
  Sk.dd.add(Sk.dd.add(Sk.dd.add(Sk.dd.add(Sk.dd.new(7, 7n), 0), 0), 1), 5)

def dbig() -> Sk.Sketch:
  Sk.dd.add(Sk.dd.new(7, 7n), 4294967295)

# the fork tree: 2^d leaves, each its own sketch over its own range of the
# stream, merged back on the way up. The digest is the sequential digest at
# every depth, or the merge is not associative.
def htree(d: Nat, +off: U32, +n: U32, +a: U32, +b: U32, +k: U32) -> Sk.Res(Sk.Sketch):
  match d:
    case 0n:
      Done{hpart(U32.to_nat(n), Sk.hll.new(7, 6n), off, a, b, k)}
    case 1n++p:
      +h = U32.shr(n)
      x y = htree(p, off, h, a, b, k) htree(p, U32.add(off, h), h, a, b, k)
      Sk.merge2(x, y)

def ctree(d: Nat, +off: U32, +n: U32, +a: U32, +b: U32, +k: U32) -> Sk.Res(Sk.Sketch):
  match d:
    case 0n:
      Done{cpart(U32.to_nat(n), Sk.cm.new(7, 6n), off, a, b, k)}
    case 1n++p:
      +h = U32.shr(n)
      x y = ctree(p, off, h, a, b, k) ctree(p, U32.add(off, h), h, a, b, k)
      Sk.merge2(x, y)

def dtree(d: Nat, +off: U32, +n: U32, +a: U32, +b: U32, +k: U32) -> Sk.Res(Sk.Sketch):
  match d:
    case 0n:
      Done{dpart(U32.to_nat(n), Sk.dd.new(7, 7n), off, a, b, k)}
    case 1n++p:
      +h = U32.shr(n)
      x y = dtree(p, off, h, a, b, k) dtree(p, U32.add(off, h), h, a, b, k)
      Sk.merge2(x, y)

def main() -> IO(Unit):
  do IO<Unit>:"""
)
for r in rows:
    print("    IO.print(%s)" % r)
for w in want:
    print("#|" + w)
