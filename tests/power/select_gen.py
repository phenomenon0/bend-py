#!/usr/bin/env python3
# The oracle for select.bend: prints the whole fixture. Every answer comes from
# the plain O(n^2) greedy below -- CPython lists, a full rescan of every
# candidate every round, no heap and no bound. power/select.bend is the lazy
# (accelerated) greedy of the same objective, and the two must agree item for
# item and gain for gain, because the lazy rule is an exactness argument and not
# an approximation: a stale gain is an upper bound, so a fresh gain that still
# beats the best stale one is the value the full rescan would have found.
#
# A row is "<why> <room> <total> <count> [item:gain:cost ...]", so it pins why
# the run stopped, what is left of the cost budget, the objective reached, and
# every pick *with the marginal gain it was taken for*. The gains are the point:
# a set is easy to get right by accident, a sequence of marginal gains is not.
#
# The ground is generated, not written out: an n = 24 instance is 576
# similarity cells, and eighty of those spelled as list literals is a fixture
# nobody can read and a ttok cap nobody can meet. Both sides compute the same
# cells from the same hash, so the fixture pins the algebra and not a table.
#
# ponytail: the row count is capped by the JS lane, not by the algorithm -- the
# emitted `do` block is one nested closure a statement and V8's stack gives out
# somewhere past 300, so a fixture stays near postings' 208.
MASK = 0xFFFFFFFF
ONE = 4096
TOP = 16777215

rows, want = [], []


# -- the ground, the same integers power/select.bend's fixture computes --------


def h(p):
    p &= MASK
    return ((((p + 1) & MASK) * 2654435761) & MASK) ^ (p >> 3)


def mix(a, b):
    return h((((a & MASK) * 2654435761) & MASK) ^ (b & MASK))


def cl(s, nc, i):
    return (mix((s + 17) & MASK, i) >> 8) % nc


def wt(s, i):
    return 1024 + ((mix((s + 101) & MASK, i) >> 7) % 3073)


# k scales every cost. A row with k = 1 keeps costs in 1..12, where a gain
# always outweighs its price; a row with k large is the other regime, where a
# real gain over a real cost quantizes to nothing and only `ratio`'s floor at 1
# keeps `ratio == 0` meaning `gain == 0`. Both regimes are real: a cost is
# tokens, or milliseconds, or dollars, and nothing says it shares a scale with
# the coverage.
def ct(s, i, k):
    return k * (1 + ((mix((s + 211) & MASK, i) >> 9) % 12))


def sm(s, nc, j, i):
    if j == i:
        return ONE
    g = mix((((s * 7) & MASK) + ((j * 65537) & MASK)) & MASK, i) >> 5
    if cl(s, nc, j) == cl(s, nc, i):
        return 2600 + (g % 1200)
    return g % 700


def ground(s, n, nc, k):
    sim = [[sm(s, nc, j, i) for i in range(n)] for j in range(n)]
    return sim, [wt(s, i) for i in range(n)], [ct(s, i, k) for i in range(n)]


# -- the objective ------------------------------------------------------------


def gain(n, sim, val, cov, j):
    # the shift is per term, exactly as power/select.bend's `term` does it: a
    # sum of floors is not the floor of a sum, and the fixture is exact
    return sum((val[i] * max(0, sim[j][i] - cov[i])) >> 12 for i in range(n))


def ratio(g, c):
    if g == 0:
        return 0
    return max(1, (min(g, TOP) << 8) // max(c, 1))


# -- the oracle: greedy by full rescan ----------------------------------------


def solve(s, n, nc, required, budget, limit, k=1):
    sim, val, cost = ground(s, n, nc, k)
    cov = [0] * n
    taken = [False] * n
    room, total, picks, why = budget, 0, [], "full"

    def take(j, g, c):
        nonlocal room, total
        picks.append((j, g, c))
        total += g
        room -= c
        taken[j] = True
        for i in range(n):
            cov[i] = max(cov[i], sim[j][i])

    # the required items first and in order, charged before anything is scored
    for j in required:
        if why in ("over", "bad"):
            break
        if j >= n or taken[j]:
            why = "bad"
            break
        c = max(cost[j], 1)
        if c > room:
            why = "over"
            break
        take(j, gain(n, sim, val, cov, j), c)

    if why == "full":
        pops = limit
        while True:
            if pops == 0:
                why = "dry"
                break
            if room == 0:
                break
            best = None
            for j in range(n):
                if taken[j]:
                    continue
                c = max(cost[j], 1)
                if c > room:
                    continue
                g = gain(n, sim, val, cov, j)
                r = ratio(g, c)
                if best is None or r > best[0]:
                    best = (r, j, g, c)
            if best is None or best[2] == 0:
                break
            take(best[1], best[2], best[3])
            # the lazy side charges pops, not rounds; the fixture only ever asks
            # for a limit of 0 or for one past the proven bound, so a round is
            # all the oracle has to count and it can never be the binding one
            pops -= 1
    return "%s %d %d %d [%s]" % (
        why,
        room,
        total,
        len(picks),
        " ".join("%d:%d:%d" % p for p in picks),
    )


# the pop ceiling power/select.bend proves: every pop drops, takes or reinserts;
# drops and takes are each once an item, and between two takes the coverage does
# not move, so an item reinserted once has its true value stored and wins the
# next test. n * (n + 1) reinserts + n removals, and four to spare.
def bound(n):
    return n * n + 2 * n + 4


def emit(s, n, nc, required, budget, limit=None, k=1):
    limit = bound(n) if limit is None else limit
    rows.append(
        "line(Select.budgeted(ground(%d, %d, %d, %d), [%s], %d, %d))"
        % (s, n, nc, k, ", ".join(map(str, required)), budget, limit)
    )
    want.append(solve(s, n, nc, required, budget, limit, k))
    return want[-1]


# -- the rows -----------------------------------------------------------------

# a budget sweep over one ground: the pack grows item by item, and every earlier
# pick and every earlier gain has to reappear unchanged in the longer row
for b in [0, 1, 2, 4, 7, 11, 16, 23, 32, 48, 70, 100, 150]:
    emit(1, 12, 3, [], b)

# required: forced in first, charged first, and their gains measured against
# only the required items ahead of them. [0, 5] and [5, 0] are the same set and
# must give the same picks in the given order with *different* gains, because
# the second one is measured after the first.
for req in [[0], [5], [11], [0, 5], [5, 0], [3, 7, 9]]:
    for b in [12, 40, 100]:
        emit(1, 12, 3, req, b)

# the three refusals, and the two ways to spend nothing
emit(1, 12, 3, [12], 100)  # an index past the ground
emit(1, 12, 3, [3, 3], 100)  # the same item twice
emit(1, 12, 3, [1, 4, 6, 8], 6)  # required costs more than the budget
emit(1, 12, 3, [5], 0)  # a budget of zero cannot buy a required item
emit(1, 12, 3, [], 0)  # a budget of zero buys nothing and refuses nothing
emit(1, 12, 3, [], 1)

# limit 0: the greedy never runs, the required items still do
emit(1, 12, 3, [], 40, 0)
emit(1, 12, 3, [5], 40, 0)
emit(1, 12, 3, [7, 2], 40, 0)
emit(1, 12, 3, [12], 40, 0)  # a malformed request is refused before the limit

# one cluster: every item is a near-duplicate of every other, which is the case
# top-K gets wrong. The second pick's gain must collapse against the first's.
for b in [10, 25, 50, 90]:
    emit(2, 16, 1, [], b)

# no clusters: every off-diagonal similarity is low, so coverage barely
# overlaps and the marginal gains stay near the standalone values
for b in [10, 25, 50, 90]:
    emit(3, 16, 16, [], b)

for b in [8, 20, 40, 70, 120]:
    emit(4, 20, 4, [], b)
for req in [[1, 13], [19]]:
    for b in [20, 60, 120]:
        emit(4, 20, 4, req, b)

for b in [10, 30, 60, 100, 160]:
    emit(5, 24, 6, [], b)
emit(5, 24, 6, [0, 23], 60)
emit(5, 24, 6, [11], 160)

for b in [6, 18, 44, 90]:
    emit(6, 14, 2, [], b)
for b in [6, 18, 44, 90]:
    emit(7, 14, 7, [], b)

# the degenerate grounds: one candidate, two, three
for n in [1, 2, 3]:
    for b in [0, 1, 3, 12, 60]:
        emit(8, n, 1, [], b)
emit(8, 1, 1, [0], 60)
emit(8, 2, 1, [1], 60)
emit(8, 3, 2, [2, 0], 60)

# costs on a scale of their own: 4,096 and 8,192 times the coverage unit, where
# a tail gain over a tail cost floors to zero. These rows are the only thing in
# the file that can tell `ratio`'s floor from its absence, and without them
# "a ratio of 0 means a gain of 0" is an invariant nothing checks.
SCALED = [(5, 24, 6, [], 900000, 4096), (5, 24, 6, [], 300000, 4096), (5, 24, 6, [], 60000, 4096), (2, 16, 1, [], 700000, 8192), (2, 16, 1, [], 200000, 8192), (5, 24, 6, [3, 17], 900000, 4096), (2, 16, 1, [0], 700000, 8192), (3, 16, 16, [], 500000, 4096), (1, 12, 3, [], 40000, 4096), (1, 12, 3, [], 4096, 4096), (1, 12, 3, [], 4095, 4096)]
for a in SCALED:
    emit(a[0], a[1], a[2], a[3], a[4], k=a[5])


# -- what the fixture has to be worth -----------------------------------------


# Fail loud at authoring time rather than ship a fixture that cannot catch
# anything: every stop arm has to appear, the packs have to be long enough for a
# marginal gain to differ from a standalone one, and the whole point of the
# primitive -- that it does not pick the top-K by standalone score -- has to be
# true of at least one row, or the file is testing a ranker.
def audit():
    for arm in ["full", "dry", "over", "bad"]:
        assert any(w.startswith(arm + " ") for w in want), arm
    assert max(int(w.split()[3]) for w in want) >= 6, "no row selects a real pack"

    # top-K by standalone gain per cost against an empty coverage -- which is
    # what ranking does -- on the one-cluster ground, against the greedy's pick
    s, n, nc, b = 2, 16, 1, 50
    sim, val, cost = ground(s, n, nc, 1)
    zero = [0] * n
    order = sorted(
        range(n), key=lambda j: (-ratio(gain(n, sim, val, zero, j), cost[j]), j)
    )
    room, naive = b, []
    for j in order:
        if cost[j] <= room:
            naive.append(j)
            room -= cost[j]
    lazy = [
        int(p.split(":")[0])
        for p in solve(s, n, nc, [], b, bound(n))[:-1].split("[")[1].split()
    ]
    assert naive != lazy, "greedy and top-K agree: the fixture proves nothing"

    # and the floor itself: strip it, re-solve the scaled rows, and at least one
    # has to move -- otherwise the family above is decoration and the mutant
    # that drops `U32.max(1, ...)` walks through this file untouched
    global ratio
    keep = ratio
    ratio = lambda g, c: 0 if g == 0 else (min(g, TOP) << 8) // max(c, 1)
    try:
        moved = sum(
            1
            for a in SCALED
            if solve(a[0], a[1], a[2], a[3], a[4], bound(a[1]), a[5])
            != want[rows.index(
                "line(Select.budgeted(ground(%d, %d, %d, %d), [%s], %d, %d))"
                % (a[0], a[1], a[2], a[5], ", ".join(map(str, a[3])), a[4], bound(a[1])))]
        )
    finally:
        ratio = keep
    assert moved > 0, "no row can see ratio's floor"
    return naive, lazy


naive, lazy = audit()

print(
    """# Select against a plain O(n^2) CPython greedy (select_gen.py prints this file).
# A row is "<why> <room> <total> <count> [item:gain:cost ...]": why the run
# stopped, the cost budget left, the objective reached, how many were picked,
# and every pick with the marginal gain it was taken for. The lazy greedy here
# and the full rescan there must agree item for item and gain for gain.
#
# The ground is computed, not tabulated: `sm`, `wt` and `ct` are the same
# integers select_gen.py computes, so a row pins the algebra and not a table.
# Row %d of this file is the one that says why the primitive exists -- on a
# ground of one cluster, where every item is a near-duplicate, ranking by
# standalone score per cost takes %s and this takes %s.
import Base
import ../../power/vec.bend as Vec
import ../../power/select.bend as Select

def h(+p: U32) -> U32:
  U32.xor(U32.mul(U32.inc(p), 2654435761), U32.shrn(p, 3n))

def mix(a: U32, b: U32) -> U32:
  h(U32.xor(U32.mul(a, 2654435761), b))

def cl(s: U32, nc: U32, i: U32) -> U32:
  U32.mod(U32.shrn(mix(U32.add(s, 17), i), 8n), nc)

def wt(s: U32, i: U32) -> U32:
  U32.add(1024, U32.mod(U32.shrn(mix(U32.add(s, 101), i), 7n), 3073))

# k scales every cost, and a row with k large is the regime where a real gain
# over a real cost floors to zero -- which is the only thing that can tell
# `ratio`'s floor at 1 from its absence
def ct(s: U32, i: U32, k: U32) -> U32:
  U32.mul(k, U32.add(1, U32.mod(U32.shrn(mix(U32.add(s, 211), i), 9n), 12)))

def sm.g(+g: U32, same: Bool) -> U32:
  match same:
    case True{}:
      U32.add(2600, U32.mod(g, 1200))
    case False{}:
      U32.mod(g, 700)

def sm.ne(+s: U32, +nc: U32, +j: U32, +i: U32) -> U32:
  sm.g(U32.shrn(mix(U32.add(U32.mul(s, 7), U32.mul(j, 65537)), i), 5n),
    U32.is_eq(cl(s, nc, j), cl(s, nc, i)))

def sm.if(s: U32, nc: U32, j: U32, i: U32, diag: Bool) -> U32:
  match diag:
    case True{}:
      4096
    case False{}:
      sm.ne(s, nc, j, i)

def sm(s: U32, nc: U32, +j: U32, +i: U32) -> U32:
  sm.if(s, nc, j, i, U32.is_eq(j, i))

# the n * n coverage rows, flat: cell p is row p / n, column p %% n
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

def gc(fuel: Nat, +i: U32, +s: U32, +k: U32, v: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      v
    case 1n++q:
      gc(q, U32.inc(i), s, k, Vec.push(v, ct(s, i, k)))

def ground(+s: U32, +n: U32, nc: U32, k: U32) -> Select.Ground:
  Select.Ground{n, gs(U32.to_nat(U32.mul(n, n)), 0, s, nc, n, Vec.new(0)),
    gv(U32.to_nat(n), 0, s, Vec.new(0)), gc(U32.to_nat(n), 0, s, k, Vec.new(0))}

def pk(x: Select.Pick) -> String:
  match x:
    case Select.Pick{i, g, c}:
      U32.show(i) ++ ":" ++ U32.show(g) ++ ":" ++ U32.show(c)

def pks(xs: List<&2, Select.Pick>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{x, t}:
      Con{pk(x), pks(t)}

def out(+r: Select.Run) -> String:
  Select.show(Select.why(r)) ++ " " ++ U32.show(Select.room(r)) ++ " "
    ++ U32.show(Select.total(r)) ++ " " ++ U32.show(Select.count(r)) ++ " ["
    ++ String.join(pks(Select.chosen(r)), " ") ++ "]"

# the Ground comes back because the caller still owns it; this file is done
# with it and drops it
def line(x: Select.Ground & Select.Run) -> String:
  (g, r) = x
  out(r)

def main() -> IO(Unit):
  do IO<Unit>:"""
    % (
        1 + rows.index("line(Select.budgeted(ground(2, 16, 1, 1), [], 50, 292))"),
        " ".join(map(str, naive)),
        " ".join(map(str, lazy)),
    )
)
for r in rows:
    print("    IO.print(%s)" % r)
for w in want:
    print("#|" + w)
