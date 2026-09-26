#!/usr/bin/env python3
# The oracle for delta.bend: prints the whole fixture. Every answer comes from
# CPython's own collections.Counter, so the Z-set algebra is checked against the
# language's multiset type and not against a second copy of the implementation.
#
# Counter is used through `update`, never through `+`. Counter.__add__ silently
# drops every count that is not strictly positive, which is exactly the
# distinction this lane exists to make -- a weight of -1 is a retraction and a
# weight of 0 is an absence, and an oracle that could not tell them apart would
# agree with a broken consolidate. `update` adds and keeps the sign.
#
# The shape of the whole file: for every operator, CPython computes
# op(the whole input after the change) FROM SCRATCH, and the fixture pins that
# Bend's *incremental* path prints that. That equivalence -- incremental equals
# recompute -- is the correctness claim of the lane, and the asserts below prove
# each case satisfies it in Python before it is ever emitted.
#
# A row is "{e:+w e:-w ...}", elements ascending, signed weights, and a
# cancelled element is not in it at all.
import random
from collections import Counter

rng = random.Random(20260920)

M = 4294967296

# -- the oracle --------------------------------------------------------------


def sgn(w):
    return "+%d" % w if w >= 0 else "-%d" % -w


def cons(c):
    # the canonical form: no zero-weight row survives it
    return {k: v for k, v in c.items() if v != 0}


def show(c):
    return "{%s}" % " ".join("%d:%s" % (k, sgn(v)) for k, v in sorted(cons(c).items()))


def zadd(*cs):
    out = Counter()
    for c in cs:
        out.update(c)
    return cons(out)


def zneg(c):
    return {k: -v for k, v in c.items()}


def zmap(c, fn):
    out = Counter()
    for k, v in c.items():
        out[fn(k)] += v
    return cons(out)


def zfilter(c, p):
    return cons({k: v for k, v in c.items() if p(k)})


def zagg(c, keyf, valf):
    out = Counter()
    for k, v in c.items():
        out[keyf(k)] += v * valf(k)
    return cons(out)


def zjoin(a, b, keyf, fn):
    out = Counter()
    for x, wx in a.items():
        for y, wy in b.items():
            if keyf(x) == keyf(y):
                out[fn(x, y)] += wx * wy
    return cons(out)


def zdistinct(c):
    return {k: 1 for k, v in cons(c).items() if v > 0}


def pairs(a, b, keyf):
    # what the row allowance counts: emitted pairs, before consolidation
    return sum(1 for x in a for y in b if keyf(x) == keyf(y))


# the element encoding the fixture uses everywhere: k * 256 + v, so the key is
# the high bits and the payload the low byte. jf is deliberately asymmetric --
# jf(x, y) != jf(y, x) -- so a join that mixes up which side is which is caught
# by the value and not only by the weight.
def kf(x):
    return x >> 8


def jf(x, y):
    return (x << 8) + (y & 255)


def mf(x):
    return x >> 8


def pf(x):
    return (x & 255) < 128


def vf(x):
    return x & 255


# -- emitting ----------------------------------------------------------------

rows, want = [], []


def row(call, expect):
    rows.append(call)
    want.append(expect)


def u32(w):
    return w % M


def lit(xs):
    return "[%s]" % ", ".join(str(x) for x in xs)


def zs(c):
    items = sorted(cons(c).items())
    return "zs(%s, %s)" % (lit(k for k, _ in items), lit(u32(v) for _, v in items))


MAX = 4294967295


def gen(nk, nv, n, lo=-2, hi=3):
    c = Counter()
    for _ in range(n):
        w = 0
        while w == 0:
            w = rng.randint(lo, hi)
        c[rng.randrange(nk) * 256 + rng.randrange(nv)] += w
    return cons(c)


# -- 1. the canonical form ---------------------------------------------------
#
# The lane's own definition of correct: a retraction that exactly cancels an
# insert leaves NO ROW, not a row of weight zero. The first three rows are the
# whole of it -- raw() prints the Z-set as built, line() consolidates first.

row("raw(Delta.remove(Delta.insert(Delta.empty(), 5), 5))", "{5:+1 5:-1}")
row("line(Delta.remove(Delta.insert(Delta.empty(), 5), 5))", "{}")
for ws in [[1, 1, 1], [1, 2, -2], [1, -3, 2], [-1, -1, -1]]:
    row(
        "line(zs([5, 5, 5], %s))" % lit(u32(w) for w in ws),
        show(Counter({5: sum(ws)})),
    )
row("raw(zs([9, 3, 9, 3], [1, 2, 1, %d]))" % u32(-2), "{9:+1 3:+2 9:+1 3:-2}")
row("line(zs([9, 3, 9, 3], [1, 2, 1, %d]))" % u32(-2), "{9:+2}")
row("line(Delta.empty())", "{}")
row("line(Delta.negate(zs([1, 2], [3, %d])))" % u32(-1), "{1:-3 2:+1}")

# plus, minus, and the group law a - a == nothing at all
p = {3: 2, 7: -1, 9: 4}
q = {7: 1, 9: -4, 11: 5}
row("line(Delta.plus(%s, %s))" % (zs(p), zs(q)), show(zadd(p, q)))
row("line(Delta.minus(%s, %s))" % (zs(p), zs(q)), show(zadd(p, zneg(q))))
row("line(Delta.minus(%s, %s))" % (zs(p), zs(p)), "{}")
row("line(Delta.plus(%s, Delta.negate(%s)))" % (zs(p), zs(p)), "{}")

# size counts rows, total sums weights -- a row of weight 3 is one row and
# three copies, and that is the whole difference between them
for c in [p, q, {}, {4: -5, 6: 5}]:
    row("num(Delta.size(Delta.consolidate(%s)))" % zs(c), str(len(cons(c))))
    row("sw(Delta.total(%s))" % zs(c), sgn(sum(c.values())))

# weight: 0 for absent and 0 for cancelled, which is the same answer for the
# same reason
wz = {3: 2, 7: -1, 20: 1}
for x in [3, 7, 20, 0, 5, 99]:
    row(
        "num(Delta.weight(Delta.consolidate(%s), %d))" % (zs(wz), x),
        str(u32(wz.get(x, 0))),
    )
row("num(Delta.weight(Delta.consolidate(zs([5, 5], [1, %d])), 5))" % u32(-1), "0")

# -- 2. map and filter are linear --------------------------------------------
#
# op(a + da) == op(a) + op(da). Two rows a case: the recompute and the
# incremental path, both pinned to the same CPython answer. A filter that
# rewrote the weight, or a map that dropped it, breaks the second row only.

cases = [
    (gen(4, 6, 8), gen(4, 6, 3)),
    (gen(6, 4, 12), gen(6, 4, 4, -3, 4)),
    (gen(3, 3, 6), zneg(gen(3, 3, 3))),
    ({}, gen(3, 5, 4)),
]
for a, da in cases:
    full = zadd(a, da)
    assert zmap(full, mf) == zadd(zmap(a, mf), zmap(da, mf))
    assert zfilter(full, pf) == zadd(zfilter(a, pf), zfilter(da, pf))
    row("line(Delta.map(~mf, %s))" % zs(full), show(zmap(full, mf)))
    row(
        "line(Delta.plus(Delta.map(~mf, %s), Delta.map(~mf, %s)))" % (zs(a), zs(da)),
        show(zmap(full, mf)),
    )
    row("line(Delta.filter(~pf, %s))" % zs(full), show(zfilter(full, pf)))
    row(
        "line(Delta.plus(Delta.filter(~pf, %s), Delta.filter(~pf, %s)))"
        % (zs(a), zs(da)),
        show(zfilter(full, pf)),
    )

# -- 3. aggregate_delta and group --------------------------------------------
#
# The output element is the group key and the output WEIGHT is the aggregate,
# so a linear aggregate is itself a Z-set and composes with plus. A key whose
# aggregate did not move produces no row -- the same drop0 rule as an element
# that cancelled, and the third case below is built to hit it.

agg_cases = [
    (gen(4, 8, 10), gen(4, 8, 4)),
    (gen(5, 5, 9), zneg(gen(5, 5, 3))),
    ({256: 1, 257: 2}, {256: -1, 257: -2}),
]
for a, da in agg_cases:
    full = zadd(a, da)
    assert zagg(full, kf, vf) == zadd(zagg(a, kf, vf), zagg(da, kf, vf))
    assert zagg(full, kf, lambda _: 1) == zadd(
        zagg(a, kf, lambda _: 1), zagg(da, kf, lambda _: 1)
    )
    row(
        "line(Delta.aggregate_delta(~kf, ~vf, %s))" % zs(full), show(zagg(full, kf, vf))
    )
    row(
        "line(Delta.plus(Delta.aggregate_delta(~kf, ~vf, %s), "
        "Delta.aggregate_delta(~kf, ~vf, %s)))" % (zs(a), zs(da)),
        show(zagg(full, kf, vf)),
    )
    row("line(Delta.group(~kf, %s))" % zs(full), show(zagg(full, kf, lambda _: 1)))
    row(
        "line(Delta.plus(Delta.group(~kf, %s), Delta.group(~kf, %s)))"
        % (zs(a), zs(da)),
        show(zagg(full, kf, lambda _: 1)),
    )

# -- 4. the index ------------------------------------------------------------
#
# index sorts the rows by key with two stable radix passes sharing one copied
# key column, and unindex is the identity on the Z-set it holds. If the two
# sorts ever disagreed the columns would shear and this round trip would print
# a different multiset.
for c in [gen(6, 6, 12), gen(2, 9, 7), {}, {1: 1}]:
    row("ixline(ix(%s))" % zs(c), show(c))

# -- 5. join is bilinear -----------------------------------------------------
#
#   (a + da) join (b + db)
#     == a join b  +  da join b  +  a join db  +  da join db
#
# Three rows a case: the recompute from scratch, the incremental sum, and the
# delta alone. The last case has a and b sharing no key with da and db, so its
# whole output IS the second-order term -- a join that drops `da join db`
# prints {} there and the right thing everywhere else.

nothing = {}
join_cases = [
    (gen(3, 4, 6), gen(3, 4, 6), gen(3, 4, 2), gen(3, 4, 2)),
    (gen(4, 3, 8), gen(4, 3, 7), gen(4, 3, 3), nothing),
    (gen(4, 3, 8), gen(4, 3, 7), nothing, gen(4, 3, 3)),
    (gen(2, 5, 5), gen(2, 5, 5), zneg(gen(2, 5, 2)), gen(2, 5, 2)),
    ({0 * 256 + 1: 1}, {0 * 256 + 2: 1}, {5 * 256 + 3: 1}, {5 * 256 + 4: 1}),
    (nothing, nothing, gen(3, 4, 3), gen(3, 4, 3)),
]
for a, b, da, db in join_cases:
    full = zjoin(zadd(a, da), zadd(b, db), kf, jf)
    base = zjoin(a, b, kf, jf)
    t1, t2, t3 = (
        zjoin(da, b, kf, jf),
        zjoin(a, db, kf, jf),
        zjoin(da, db, kf, jf),
    )
    delta = zadd(t1, t2, t3)
    assert zadd(base, delta) == full, "bilinearity fails in the oracle"
    row("jout(jn(%s, %s, %d))" % (zs(zadd(a, da)), zs(zadd(b, db)), MAX), show(full))
    row(
        "line(Delta.plus(jz(jn(%s, %s, %d)), jz(jd(%s, %s, %s, %s, %d))))"
        % (zs(a), zs(b), MAX, zs(a), zs(b), zs(da), zs(db), MAX),
        show(full),
    )
    row(
        "jout(jd(%s, %s, %s, %s, %d))" % (zs(a), zs(b), zs(da), zs(db), MAX),
        show(delta),
    )

# the third term on its own, spelled out as a plain join, so the row above that
# isolates it has something to be equal to
a5, b5, da5, db5 = join_cases[4]
row("jout(jn(%s, %s, %d))" % (zs(da5), zs(db5), MAX), show(zjoin(da5, db5, kf, jf)))

# jf's asymmetry: a join keeps the left side left. Swapping the arguments is a
# different answer, and a probe that mixed up which index it was walking would
# print this one instead of the one above.
aa, bb = gen(3, 4, 5), gen(3, 4, 5)
row("jout(jn(%s, %s, %d))" % (zs(aa), zs(bb), MAX), show(zjoin(aa, bb, kf, jf)))
row("jout(jn(%s, %s, %d))" % (zs(bb), zs(aa), MAX), show(zjoin(bb, aa, kf, jf)))

# -- 6. the row allowance ----------------------------------------------------
#
# The allowance counts emitted pairs BEFORE consolidation, because that is the
# number that can blow up: n rows against m rows of one key is n*m pairs and
# one output row. ok is 1 when the whole join fit, and `left` is what is unspent.
# The partial output of a refused join is deliberately NOT pinned -- it depends
# on how far the probe got, which is an implementation detail; what is pinned is
# that the refusal is reported and nothing silently truncates.
ba, bb2 = gen(3, 4, 6), gen(3, 4, 6)
np = pairs(ba, bb2, kf)
for limit in [MAX, np, np + 1, np - 1, 1, 0]:
    row(
        "jok(jn(%s, %s, %d))" % (zs(ba), zs(bb2), limit),
        "1:%d" % (limit - np) if limit >= np else "0:0",
    )
row("jout(jn(%s, %s, %d))" % (zs(ba), zs(bb2), np), show(zjoin(ba, bb2, kf, jf)))

# the same allowance, shared across the three terms of an incremental step
ia, ib, ida, idb = gen(3, 4, 5), gen(3, 4, 5), gen(3, 4, 2), gen(3, 4, 2)
dp = pairs(ida, ib, kf) + pairs(ia, idb, kf) + pairs(ida, idb, kf)
for limit in [MAX, dp, dp - 1, 0]:
    row(
        "jok(jd(%s, %s, %s, %s, %d))" % (zs(ia), zs(ib), zs(ida), zs(idb), limit),
        "1:%d" % (limit - dp) if limit >= dp else "0:0",
    )

# -- 7. distinct is not linear, and distinct_delta is honest about it ---------
#
# distinct(a + da) != distinct(a) + distinct(da): weight 3 is one element and
# weight 1 + (-1) is none, and neither is a function of the delta alone. The
# first row of each case shows the naive sum being WRONG, which is why
# distinct_delta takes the state; the next two show the state-probing form
# agreeing with the recompute.
dist_cases = [
    ({256: 1, 257: 1}, {256: 1, 258: 1}),
    ({256: 1, 257: 2}, {256: -1, 257: -1}),
    ({256: 2}, {256: -2, 512: 3}),
    ({}, {256: 1, 257: -1}),
    ({256: -1}, {256: 2}),
    (gen(4, 4, 8), gen(4, 4, 4, -3, 4)),
]
naive_differs = 0
for st, d in dist_cases:
    full = zadd(st, d)
    recompute = zdistinct(full)
    step = zadd(zdistinct(st), zdistinct(d))
    if step != recompute:
        naive_differs += 1
    delta = zadd(recompute, zneg(zdistinct(st)))
    row("line(Delta.distinct(%s))" % zs(full), show(recompute))
    row("ddout(dd(%s, %s))" % (zs(st), zs(d)), show(delta))
    row(
        "line(Delta.plus(Delta.distinct(%s), ddz(dd(%s, %s))))"
        % (zs(st), zs(st), zs(d)),
        show(recompute),
    )
    # the naive linear step, printed so the fixture SHOWS the non-linearity
    row(
        "line(Delta.plus(Delta.distinct(%s), Delta.distinct(%s)))" % (zs(st), zs(d)),
        show(step),
    )
assert naive_differs >= 4, "the distinct cases must actually exhibit non-linearity"

# distinct's own rule: any strictly positive weight becomes exactly 1, and
# nothing else survives
row("line(Delta.distinct(zs([1, 2, 3], [5, %d, 1])))" % u32(-2), "{1:+1 3:+1}")
row("line(Delta.distinct(zs([1, 1], [2, %d])))" % u32(-2), "{}")

# -- 8. absorb ---------------------------------------------------------------
#
# The kept side taking the change, which costs the side and is therefore its
# own door rather than part of join_delta. After absorbing, a fresh full join
# of the absorbed state is the recompute the incremental step agreed with.
for a, b, da, db in join_cases[:3]:
    row(
        "ixline(Delta.absorb(~kf, ix(%s), ix(%s)))" % (zs(a), zs(da)), show(zadd(a, da))
    )

print(
    """# Delta against CPython's own Counter (delta_gen.py prints this file). A row is
# "{e:+w e:-w}", elements ascending, weights signed, and an element whose
# weights cancelled is not in it at all. raw() prints a Z-set as built; line()
# consolidates first, which is the canonical form every comparison is made in.
#
# The file's spine: for every operator, the recompute from scratch and the
# incremental path are two separate rows pinned to the same expected string.
import Base
import ../../power/vec.bend as Vec
import ../../power/delta.bend as Delta

# the element encoding: k * 256 + v, key in the high bits, payload in the low
# byte. jf is asymmetric on purpose, so a join that swaps its sides is caught.
def kf(x: U32) -> U32:
  U32.shrn(x, 8n)

def jf(x: U32, y: U32) -> U32:
  U32.add(U32.shln(x, 8n), U32.and(y, 255))

def mf(x: U32) -> U32:
  U32.shrn(x, 8n)

def pf(x: U32) -> Bool:
  U32.is_lt(U32.and(x, 255), 128)

def vf(x: U32) -> U32:
  U32.and(x, 255)

def zs(es: List<&2, U32>, ws: List<&2, U32>) -> Delta.ZSet:
  Delta.of_lists(es, ws)

def txt(r: Delta.ZSet & String) -> String:
  (z, s) = r
  s

def raw(z: Delta.ZSet) -> String:
  txt(Delta.show(z))

def line(z: Delta.ZSet) -> String:
  raw(Delta.consolidate(z))

def num(r: Delta.ZSet & U32) -> String:
  (z, n) = r
  U32.show(n)

def sw(r: Delta.ZSet & U32) -> String:
  (z, n) = r
  Delta.wshow(n)

def yn(b: Bool) -> String:
  match b:
    case True{}:
      "1"
    case False{}:
      "0"

def jz(j: Delta.Jn) -> Delta.ZSet:
  match j:
    case Delta.Jn{left, a, b, out, ok}:
      out

def jout(j: Delta.Jn) -> String:
  line(jz(j))

def jok(j: Delta.Jn) -> String:
  match j:
    case Delta.Jn{left, a, b, out, ok}:
      yn(ok) ++ ":" ++ U32.show(left)

def ix(z: Delta.ZSet) -> Delta.Ix:
  Delta.index(~kf, z)

def ixline(x: Delta.Ix) -> String:
  line(Delta.unindex(x))

def jn(a: Delta.ZSet, b: Delta.ZSet, lim: U32) -> Delta.Jn:
  Delta.join(~kf, ~jf, a, b, lim)

def jd(a: Delta.ZSet, b: Delta.ZSet, da: Delta.ZSet, db: Delta.ZSet, lim: U32) ->
  Delta.Jn:
  Delta.join_delta(~jf, ix(a), ix(b), ix(da), ix(db), lim)

def ddz(r: Delta.ZSet & Delta.ZSet) -> Delta.ZSet:
  (st, d) = r
  d

def ddout(r: Delta.ZSet & Delta.ZSet) -> String:
  line(ddz(r))

def dd(st: Delta.ZSet, d: Delta.ZSet) -> Delta.ZSet & Delta.ZSet:
  Delta.distinct_delta(Delta.consolidate(st), d)

def main() -> IO(Unit):
  do IO<Unit>:"""
)
for r in rows:
    print("    IO.print(%s)" % r)
for w in want:
    print("#|" + w)
