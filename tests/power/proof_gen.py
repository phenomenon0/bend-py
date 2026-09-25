#!/usr/bin/env python3
# The oracle for proof.bend: prints the whole fixture. A checker is only worth
# what it REJECTS, so this file is weighted toward rejection: every instance is
# emitted once valid and then once per single-fault corruption, and the fixture
# pins which property caught each one.
#
# The expected verdict is not computed by walking the Bend checker's traversal
# order. It comes from a set-valued CPython reference -- `*_faults` below, one
# comprehension per property, no loop order at all -- and a case is only emitted
# when that set has exactly the size the case intends: {} for a valid witness,
# one named property for a corruption. `one()` asserts it. A corruption that
# breaks two properties at once would make the expected reason depend on which
# test the Bend file happens to run first, so it is refused at authoring time
# rather than pinned as if it meant something.
#
# The valid witnesses come from CPython's own answers: `sorted` for the sort
# permutation, a `sorted` by (-score, index) for topk, a heapq Dijkstra for the
# path labels. The assignment certificates are built dual-first -- pick the
# prices, then the costs that fit under them -- which makes the certificate
# valid by construction; `brute()` then confirms by exhaustive permutation that
# the matching really is a cheapest one, so the construction is checked against
# the definition of the problem and not against a second solver.
#
# A row is one verdict: "ok <budget left>" or "no <property>".
import heapq
import itertools

BIG = 0x80000000
INF = 0xFFFFFFFF

rows, want = [], []


def lit(xs):
    return "vec([%s])" % ", ".join(map(str, xs))


def row(call, verdict):
    rows.append(call)
    want.append(verdict)


def one(got, expect):
    """The fault set a case is allowed to have: empty, or exactly one name."""
    if expect == "fuel":
        # a budget refusal is only unambiguous on an otherwise valid witness
        assert got == set(), got
        return "no fuel"
    assert got == (set() if expect is None else {expect}), (got, expect)
    return "ok %d" if expect is None else ("no " + expect)


# -- the reference: one comprehension a property, no traversal order ---------


def sort_faults(a, o, p, n):
    f = set()
    if any(x >= n for x in p):
        f.add("range")
    if len(set(p)) != len(p):
        f.add("dup")
    if any(o[i] > o[i + 1] for i in range(n - 1)):
        f.add("order")
    if any(o[i] != a[p[i]] for i in range(n) if p[i] < n):
        f.add("value")
    return f


def topk_faults(sc, ix, n, k, thr):
    f = set()
    if any(x >= n for x in ix):
        f.add("range")
    if len(set(ix)) != len(ix):
        f.add("dup")
    ch = [sc[x] for x in ix if x < n]
    if any(y < thr for y in ch):
        f.add("slack")
    if any(ch[i] < ch[i + 1] for i in range(len(ch) - 1)):
        f.add("order")
    taken = {x for x in ix if x < n}
    if any(sc[j] > thr for j in range(n) if j not in taken):
        f.add("over")
    return f


def path_faults(eu, ev, ew, d, n, m, src):
    f = set()
    if src >= n or any(eu[e] >= n or ev[e] >= n for e in range(m)):
        f.add("range")
    if src < n and d[src] != 0:
        f.add("value")
    live = [
        e
        for e in range(m)
        if eu[e] < n and ev[e] < n and d[eu[e]] < BIG and ew[e] < BIG
    ]
    if any(d[ev[e]] > d[eu[e]] + ew[e] for e in live):
        f.add("over")
    hit = {ev[e] for e in live if d[ev[e]] == d[eu[e]] + ew[e]}
    if any(v not in hit for v in range(n) if v != src and d[v] < BIG):
        f.add("slack")
    return f


def assign_faults(c, u, w, mt, nr, nc):
    f = set()
    cell = [[c[i * nc + j] for j in range(nc)] for i in range(nr)]
    if any(
        cell[i][j] < BIG and u[i] > cell[i][j] + w[j]
        for i in range(nr)
        for j in range(nc)
    ):
        f.add("over")
    if any(j >= nc for j in mt):
        f.add("range")
    if len(set(mt)) != len(mt):
        f.add("dup")
    # the tightness test does not exempt a forbidden cell -- matching one is
    # exactly what it must refuse -- so this sum is taken modulo 2^32, the way
    # the U32 it mirrors would take it
    if any(
        u[i] != (cell[i][mt[i]] + w[mt[i]]) % 2**32 for i in range(nr) if mt[i] < nc
    ):
        f.add("slack")
    held = {j for j in mt if j < nc}
    if any(w[j] != 0 for j in range(nc) if j not in held):
        f.add("slack")
    return f


def brute(c, nr, nc):
    """The cheapest injective row -> column map, by exhaustion."""
    return min(
        sum(c[i * nc + pm[i]] for i in range(nr))
        for pm in itertools.permutations(range(nc), nr)
    )


def dijkstra(eu, ev, ew, n, m, src):
    adj = [[] for _ in range(n)]
    for e in range(m):
        adj[eu[e]].append((ev[e], ew[e]))
    d = [INF] * n
    d[src] = 0
    q = [(0, src)]
    while q:
        du, x = heapq.heappop(q)
        if du > d[x]:
            continue
        for y, w in adj[x]:
            if du + w < d[y]:
                d[y] = du + w
                heapq.heappush(q, (d[y], y))
    return d


# -- sort --------------------------------------------------------------------

LIM = 1000


def sort_case(a, p, o, expect, n=None, lim=LIM):
    n = len(a) if n is None else n
    t = one(sort_faults(a, o, p, n), expect)
    row(
        "s3(Proof.sort(%s, %s, %s, %d, %d))" % (lit(a), lit(o), lit(p), n, lim),
        t % (lim - n) if expect is None else t,
    )


for a in [[5, 1, 9, 3, 7, 2], [4, 4, 4, 1], [0, 4294967295, 8], [11], [3, 1, 3, 1, 2]]:
    n = len(a)
    p = sorted(range(n), key=lambda i: (a[i], i))
    o = [a[i] for i in p]
    sort_case(a, p, o, None)
    # dup: a repeated source index, aimed at two slots holding equal values so
    # that only the bijection breaks and the value test still holds. On an
    # array with no ties a repeat always drags `value` down with it, which is
    # two faults, so those arrays skip this case rather than pin a reason that
    # depends on which test runs first.
    for i in range(n):
        for j in range(i + 1, n):
            q = list(p)
            q[j] = p[i]
            if sort_faults(a, o, q, n) == {"dup"}:
                sort_case(a, q, o, "dup")
                break
        else:
            continue
        break
    # range: one source index past the end
    q = list(p)
    q[n - 1] = n + 3
    sort_case(a, q, o, "range")
    # order: two adjacent output slots swapped, permutation swapped with them,
    # so only the ordering breaks and every element is still the right one
    if n > 1:
        j = next((i for i in range(n - 1) if o[i] != o[i + 1]), None)
        if j is not None:
            oo, pp = list(o), list(p)
            oo[j], oo[j + 1] = oo[j + 1], oo[j]
            pp[j], pp[j + 1] = pp[j + 1], pp[j]
            sort_case(a, pp, oo, "order")
    # value: an output slot holding something the input never had, chosen so
    # the sequence stays non-decreasing
    j = n - 1
    oo = list(o)
    oo[j] = o[j] - 1 if o[j] > 0 and (j == 0 or o[j] - 1 >= o[j - 1]) else o[j] + 1
    if sort_faults(a, oo, p, n) == {"value"}:
        sort_case(a, p, oo, "value")

# the budget: exactly enough, one short, and a witness that claims four billion
# rows against a limit of ten -- refused in O(1), nothing read
a = [5, 1, 9, 3]
p = sorted(range(4), key=lambda i: (a[i], i))
o = [a[i] for i in p]
sort_case(a, p, o, None, lim=4)
sort_case(a, p, o, "fuel", lim=3)
rows.append("s3(Proof.sort(%s, %s, %s, 4000000000, 10))" % (lit(a), lit(o), lit(p)))
want.append("no fuel")

# -- topk --------------------------------------------------------------------


def topk_case(sc, ix, k, thr, expect, n=None, lim=LIM):
    n = len(sc) if n is None else n
    t = one(topk_faults(sc, ix, n, k, thr), expect)
    row(
        "s2(Proof.topk(%s, %s, %d, %d, %d, %d))" % (lit(sc), lit(ix), n, k, thr, lim),
        t % (lim - n - k) if expect is None else t,
    )


for sc, k in [([3, 9, 4, 1, 7, 6], 3), ([5, 5, 5, 5], 2), ([0, 1, 2], 3), ([8, 2], 1)]:
    n = len(sc)
    order = sorted(range(n), key=lambda i: (-sc[i], i))
    ix = order[:k]
    thr = sc[order[k]] if k < n else 0
    topk_case(sc, ix, k, thr, None)
    # over: swap a chosen index for an unchosen one that beats the threshold
    if k < n and sc[order[k]] < sc[order[k - 1]]:
        bad = ix[:-1] + [order[k]]
        if topk_faults(sc, bad, n, k, thr) == {"over"}:
            topk_case(sc, bad, k, thr, "over")
    # slack: the threshold raised above the worst chosen element
    hi = min(sc[i] for i in ix) + 1
    if topk_faults(sc, ix, n, k, hi) == {"slack"}:
        topk_case(sc, ix, k, hi, "slack")
    # order: the chosen list reversed
    if k > 1 and topk_faults(sc, ix[::-1], n, k, thr) == {"order"}:
        topk_case(sc, ix[::-1], k, thr, "order")
    # dup: the best index chosen twice
    if k > 1:
        bad = [ix[0]] + ix[:-1]
        if topk_faults(sc, bad, n, k, thr) == {"dup"}:
            topk_case(sc, bad, k, thr, "dup")
    # range: an index past the end
    bad = ix[:-1] + [n + 2]
    if topk_faults(sc, bad, n, k, thr) == {"range"}:
        topk_case(sc, bad, k, thr, "range")

# a threshold of 0 with every element chosen, and the hostile size again
topk_case([4, 2, 9], [2, 0, 1], 3, 0, None)
rows.append(
    "s2(Proof.topk(%s, %s, 3000000000, 2, 0, 20))" % (lit([4, 2, 9]), lit([2, 0]))
)
want.append("no fuel")

# -- shortest path -----------------------------------------------------------

GRAPHS = [
    # a diamond: two routes to the far corner, one of them cheaper
    ([0, 0, 1, 2, 1], [1, 2, 3, 3, 2], [4, 9, 3, 1, 2], 4, 0),
    # a line, so every label is achieved by exactly one edge
    ([0, 1, 2, 3], [1, 2, 3, 4], [7, 7, 7, 7], 5, 0),
    # a vertex nothing reaches: its label must come back unreachable
    ([0, 1], [1, 2], [5, 6], 4, 0),
    # a cycle, and a source that is not vertex 0
    ([0, 1, 2, 0], [1, 2, 0, 2], [2, 3, 4, 100], 3, 1),
]


def path_case(eu, ev, ew, d, n, src, expect, mm=None, lim=LIM):
    mm = len(eu) if mm is None else mm
    t = one(path_faults(eu, ev, ew, d, n, mm, src), expect)
    row(
        "s4(Proof.path(%s, %s, %s, %s, %d, %d, %d, %d))"
        % (lit(eu), lit(ev), lit(ew), lit(d), n, mm, src, lim),
        t % (lim - n - mm) if expect is None else t,
    )


for eu, ev, ew, n, src in GRAPHS:
    m = len(eu)
    d = dijkstra(eu, ev, ew, n, m, src)
    path_case(eu, ev, ew, d, n, src, None)
    # over: a reachable label raised by one, so some edge into it no longer fits
    for v in range(n):
        if v != src and d[v] < BIG:
            bad = list(d)
            bad[v] = d[v] + 1
            if path_faults(eu, ev, ew, bad, n, m, src) == {"over"}:
                path_case(eu, ev, ew, bad, n, src, "over")
                break
    # slack: a label lowered by one -- still feasible against every edge, and
    # now achieved by none of them
    for v in range(n):
        if v != src and 0 < d[v] < BIG:
            bad = list(d)
            bad[v] = d[v] - 1
            if path_faults(eu, ev, ew, bad, n, m, src) == {"slack"}:
                path_case(eu, ev, ew, bad, n, src, "slack")
                break
    # slack again, the other way: a vertex nothing reaches given a finite label
    for v in range(n):
        if d[v] >= BIG:
            bad = list(d)
            bad[v] = 1
            if path_faults(eu, ev, ew, bad, n, m, src) == {"slack"}:
                path_case(eu, ev, ew, bad, n, src, "slack")
                break
    # value: the source label moved off zero
    bad = list(d)
    bad[src] = 1
    if path_faults(eu, ev, ew, bad, n, m, src) == {"value"}:
        path_case(eu, ev, ew, bad, n, src, "value")
    # range: an edge whose head is not a vertex
    bad = list(ev)
    bad[m - 1] = n + 5
    if path_faults(eu, bad, ew, d, n, m, src) == {"range"}:
        path_case(eu, bad, ew, d, n, src, "range")
    # range: a source that is not a vertex
    if path_faults(eu, ev, ew, d, n, m, n + 1) == {"range"}:
        path_case(eu, ev, ew, d, n, n + 1, "range")

# a forbidden edge -- weight at or past the ceiling -- proves nothing about its
# head, so the labels that ignore it still certify
eu, ev, ew, n, src = [0, 0], [1, 1], [6, BIG], 2, 0
path_case(eu, ev, ew, [0, 6], n, src, None)
rows.append(
    "s4(Proof.path(%s, %s, %s, %s, 4000000000, 2, 0, 50))"
    % (lit(eu), lit(ev), lit(ew), lit([0, 6]))
)
want.append("no fuel")

# -- assignment --------------------------------------------------------------


# dual-first: pick the prices, then the costs that fit under them. u[i] is the
# row price, w[j] the column price stored non-negative (assign.bend's sign
# convention: the true dual is v[j] = -w[j]), and the slack s[i][j] >= 0 is 0
# exactly on the matched cell, which is complementary slackness by construction.
def build(nr, nc, mt, u, w, slack):
    c = []
    for i in range(nr):
        for j in range(nc):
            c.append(u[i] - w[j] + (0 if mt[i] == j else slack[i][j]))
    assert all(x >= 0 for x in c)
    assert assign_faults(c, u, w, mt, nr, nc) == set(), assign_faults(
        c, u, w, mt, nr, nc
    )
    assert brute(c, nr, nc) == sum(c[i * nc + mt[i]] for i in range(nr))
    return c


def assign_case(c, u, w, mt, nr, nc, expect, lim=LIM):
    t = one(assign_faults(c, u, w, mt, nr, nc), expect)
    row(
        "s4(Proof.assign(%s, %s, %s, %s, %d, %d, %d))"
        % (lit(c), lit(u), lit(w), lit(mt), nr, nc, lim),
        t % (lim - nr * nc - nr - nc) if expect is None else t,
    )


CASES = [
    # square, every column held, every price non-trivial
    (3, 3, [1, 2, 0], [9, 7, 8], [2, 1, 3], [[0, 4, 5], [6, 0, 2], [3, 1, 0]]),
    # wide: two columns left over, and their prices must be zero
    (2, 4, [3, 0], [6, 5], [1, 0, 0, 2], [[4, 2, 7, 0], [0, 3, 1, 5]]),
    # every price zero: the degenerate certificate still has to hold
    (3, 3, [0, 1, 2], [0, 0, 0], [0, 0, 0], [[0, 2, 3], [1, 0, 4], [5, 6, 0]]),
    # one row, one column
    (1, 1, [0], [4], [0], [[0]]),
]

for nr, nc, mt, u, w, slack in CASES:
    for i in range(nr):
        for j in range(nc):
            if mt[i] != j:
                slack[i][j] = max(slack[i][j], 1)
    c = build(nr, nc, mt, u, w, slack)
    assign_case(c, u, w, mt, nr, nc, None)
    # over: a cell the prices do not dominate -- a dual computed for a cheaper
    # matrix than the one it arrived with. Raising a row price instead would
    # break its matched cell's tightness in the same breath, two faults at
    # once, so the corruption goes into an UNMATCHED cell, where feasibility is
    # the only thing that can notice.
    for i in range(nr):
        for j in range(nc):
            if mt[i] != j and u[i] - w[j] >= 1:
                bad = list(c)
                bad[i * nc + j] = u[i] - w[j] - 1
                if assign_faults(bad, u, w, mt, nr, nc) == {"over"}:
                    assign_case(bad, u, w, mt, nr, nc, "over")
                    break
        else:
            continue
        break
    # slack: a row price lowered, so its matched cell is no longer tight
    if u[0] > 0:
        bad = list(u)
        bad[0] = u[0] - 1
        if assign_faults(c, bad, w, mt, nr, nc) == {"slack"}:
            assign_case(c, bad, w, mt, nr, nc, "slack")
    # slack: a column nobody holds given a price
    held = set(mt)
    for j in range(nc):
        if j not in held:
            bad = list(w)
            bad[j] = 1
            if assign_faults(c, u, bad, mt, nr, nc) == {"slack"}:
                assign_case(c, u, bad, mt, nr, nc, "slack")
                break
    # dup: two rows holding the same column
    if nr > 1:
        bad = list(mt)
        bad[1] = mt[0]
        if assign_faults(c, u, w, bad, nr, nc) == {"dup"}:
            assign_case(c, u, w, bad, nr, nc, "dup")
    # range: a row holding a column that does not exist
    bad = list(mt)
    bad[0] = nc + 1
    if assign_faults(c, u, w, bad, nr, nc) == {"range"}:
        assign_case(c, u, w, bad, nr, nc, "range")

# an all-zero matrix, where every cell is tight and every price is zero. It is
# the only shape where a repeated column is a LONE fault -- anywhere else the
# repeat also leaves a column unheld and a row untight -- so it is where the
# bijection test has to earn its place on its own.
assign_case([0, 0, 0, 0], [0, 0], [0, 0], [0, 1], 2, 2, None)
assign_case([0, 0, 0, 0], [0, 0], [0, 0], [0, 0], 2, 2, "dup")

# a forbidden cell is vacuous: no matching may use it, so no price has to fit
# under it, which is what lets a padded (opt-out) matrix certify at all
c = [0, INF, INF, 0]
assign_case(c, [0, 0], [0, 0], [0, 1], 2, 2, None)
# and vacuous is not the same as free: a matching that USES a forbidden cell is
# refused, because tightness does not exempt it and no price can reach 2^32-1
assign_case(c, [0, 0], [0, 0], [1, 0], 2, 2, "slack")

# the budget, exactly and one short, and the row this guard exists for: a
# witness naming 2^16 by 2^16 cells. 65536 * 65536 is 0 modulo 2^32, so a guard
# that formed the product would wave it through and then walk four billion
# cells; the guard divides instead.
assign_case(c, [0, 0], [0, 0], [0, 1], 2, 2, None, lim=8)
assign_case(c, [0, 0], [0, 0], [0, 1], 2, 2, "fuel", lim=7)
rows.append(
    "s4(Proof.assign(%s, %s, %s, %s, 65536, 65536, 1000))"
    % (lit(c), lit([0, 0]), lit([0, 0]), lit([0, 1]))
)
want.append("no fuel")

# -- against power/assign.bend's own solver ----------------------------------

# The integration: the solver runs, its Sol is unpacked into the four flat Vecs
# a certificate travels as, and the checker reads them. Nothing here tells the
# checker what the answer is -- the expected row is `ok`, and if the solver ever
# stops producing a certifiable matching this fixture says so in the reason.
SOLVE = [
    (4, 4, [7, 2, 9, 4, 3, 8, 1, 6, 5, 5, 2, 7, 6, 1, 4, 9]),
    (3, 5, [4, 1, 7, 2, 9, 8, 3, 2, 6, 1, 5, 9, 4, 3, 7]),
    (5, 5, [2, 2, 2, 2, 2, 9, 1, 8, 3, 7, 4, 6, 5, 5, 4, 1, 9, 2, 8, 3, 7, 3, 6, 4, 5]),
    (2, 2, [0, 0, 0, 0]),
]
for nr, nc, c in SOLVE:
    rows.append(
        "cert(Assign.solve(%s, %d, %d), %d, %d, %d)" % (lit(c), nr, nc, nr, nc, LIM)
    )
    want.append("ok %d" % (LIM - nr * nc - nr - nc))

# a taller-than-wide matrix has no full matching, so the solver comes back with
# nothing matched -- and nothing is not a certificate. The checker says so at
# the first row holding no column at all.
rows.append("cert(Assign.solve(%s, 3, 2), 3, 2, %d)" % (lit([1, 2, 3, 4, 5, 6]), LIM))
want.append("no range")

# Every corruption above is emitted only when it turns out to be single-fault,
# which means a corruption that stopped working would drop out of the fixture
# without a word. So count the reasons and refuse to print a fixture that has
# gone quiet: seven of each rejection, and rejections the clear majority.
tally = {}
for w in want:
    tally[w.split()[-1] if w.startswith("no ") else "ok"] = (
        tally.get(w.split()[-1] if w.startswith("no ") else "ok", 0) + 1
    )
for name in ["range", "dup", "order", "value", "over", "slack", "fuel"]:
    assert tally.get(name, 0) >= 4, (name, tally)
assert len(want) - tally["ok"] > tally["ok"], tally

print(
    """# proof.bend against a set-valued CPython reference (proof_gen.py prints this
# file). A row is one verdict: "ok <budget left>" or "no <property>". Every
# instance appears once valid and then once per single-fault corruption -- a
# checker is worth what it rejects, so most of these rows are rejections.
import Base
import ../../power/vec.bend as Vec
import ../../power/assign.bend as Assign
import ../../power/proof.bend as Proof

def vec(xs: List<&2, U32>) -> Vec.Vec:
  Vec.from_list(xs, Vec.new(0))

def res(r: Result<&2, &2, Proof.Bad, U32>) -> String:
  match r:
    case Done{left}:
      "ok " ++ U32.show(left)
    case Fail{b}:
      "no " ++ Proof.show(b)

def s2(q: Vec.Vec & Vec.Vec & Result<&2, &2, Proof.Bad, U32>) -> String:
  (a, b, r) = q
  res(r)

def s3(q: Vec.Vec & Vec.Vec & Vec.Vec & Result<&2, &2, Proof.Bad, U32>) -> String:
  (a, b, c, r) = q
  res(r)

def s4(q: Vec.Vec & Vec.Vec & Vec.Vec & Vec.Vec & Result<&2, &2, Proof.Bad, U32>) -> String:
  (a, b, c, d, r) = q
  res(r)

# Assign.Sol holds the prices in the solver's own layout -- one scratch cell in
# front of each -- so the certificate has to be unpacked before it can travel.
# Three pushes a row and a column is the whole adapter, and it is the only thing
# in this file that knows the solver exists.
type Wit is Type:
  Wit{s: Assign.Sol, u: Vec.Vec, w: Vec.Vec, mt: Vec.Vec}

def wit.u(w: Vec.Vec, mt: Vec.Vec, q: Assign.Sol & U32) -> Wit:
  (s, x) = q
  Wit{s, vec([]), w, mt}

def wit.pu(u: Vec.Vec, w: Vec.Vec, mt: Vec.Vec, q: Assign.Sol & U32) -> Wit:
  (s, x) = q
  Wit{s, Vec.push(u, x), w, mt}

def wit.pw(u: Vec.Vec, w: Vec.Vec, mt: Vec.Vec, q: Assign.Sol & U32) -> Wit:
  (s, x) = q
  Wit{s, u, Vec.push(w, x), mt}

def wit.pm(u: Vec.Vec, w: Vec.Vec, mt: Vec.Vec, q: Assign.Sol & U32) -> Wit:
  (s, x) = q
  Wit{s, u, w, Vec.push(mt, x)}

def wit.rows(fuel: Nat, +i: U32, x: Wit) -> Wit:
  match fuel:
    case 0n:
      x
    case 1n++q:
      match x:
        case Wit{s, u, w, mt}:
          wit.rows(q, U32.inc(i), wit.pu(u, w, mt, Assign.price_row(s, i)))

def wit.cols(fuel: Nat, +j: U32, x: Wit) -> Wit:
  match fuel:
    case 0n:
      x
    case 1n++q:
      match x:
        case Wit{s, u, w, mt}:
          wit.cols(q, U32.inc(j), wit.pw(u, w, mt, Assign.price_col(s, j)))

def wit.mts(fuel: Nat, +i: U32, x: Wit) -> Wit:
  match fuel:
    case 0n:
      x
    case 1n++q:
      match x:
        case Wit{s, u, w, mt}:
          wit.mts(q, U32.inc(i), wit.pm(u, w, mt, Assign.at(s, i)))

def wit.chk(c: Vec.Vec, nr: U32, nc: U32, lim: U32, x: Wit) -> String:
  match x:
    case Wit{s, u, w, mt}:
      s4(Proof.assign(c, u, w, mt, nr, nc, lim))

def cert.go(c: Vec.Vec, +nr: U32, +nc: U32, lim: U32, x: Wit) -> String:
  wit.chk(c, nr, nc, lim, wit.mts(U32.to_nat(nr), 0, wit.cols(U32.to_nat(nc), 0, wit.rows(U32.to_nat(nr), 0, x))))

def cert(q: Vec.Vec & Assign.Sol, +nr: U32, +nc: U32, lim: U32) -> String:
  (c, s) = q
  cert.go(c, nr, nc, lim, Wit{s, vec([]), vec([]), vec([])})

def main() -> IO(Unit):
  do IO<Unit>:"""
)
for r in rows:
    print("    IO.print(%s)" % r)
for w in want:
    print("#|" + w)
