#!/usr/bin/env python3
# The oracle for assign.bend: prints the whole fixture. Every cost printed here
# is found by brute force over the injective maps -- itertools.permutations and
# a sum, sharing not one line with a shortest-augmenting-path search -- and
# cross-checked against SciPy's linear_sum_assignment where SciPy can take the
# matrix. Nothing in this file is allowed to print until guard() has agreed.
#
# A row is "<cost> <ok> <cert>": what the matching costs, whether a full one was
# found, and whether the prices that came back with it prove it optimal. The
# permutation itself is pinned only where brute force finds exactly one optimal
# map -- ties make it implementation-defined, and a test that pins one of
# several right answers is a test that breaks on a tie-break change. What is
# pinned instead, for every feasible instance, is the duality gap: sum of the
# row prices minus sum of the column prices equals the cost, at the optimum and
# nowhere else, and that number IS unique however the ties fell.
import itertools
import random

import numpy as np
from scipy.optimize import linear_sum_assignment

BIG = 0x80000000
INF = 0xFFFFFFFF

rng = random.Random(20260930)

rows, want = [], []


# -- the oracles -------------------------------------------------------------


def brute(a, n, m):
    """(best cost, how many maps reach it, one of them) over injective maps.
    A cell at or above BIG is forbidden and no map may use it."""
    best, cnt, arg = None, 0, None
    for pm in itertools.permutations(range(m), n):
        if any(a[i * m + pm[i]] >= BIG for i in range(n)):
            continue
        c = sum(a[i * m + pm[i]] for i in range(n))
        if best is None or c < best:
            best, cnt, arg = c, 1, pm
        elif c == best:
            cnt += 1
    return best, cnt, arg


def scipy_cost(a, n, m):
    """None when SciPy cannot take the matrix (a forbidden cell, or no rows)."""
    if n == 0 or m == 0 or any(x >= BIG for x in a):
        return None
    mat = np.array(a, dtype=float).reshape(n, m)
    ri, ci = linear_sum_assignment(mat)
    return int(mat[ri, ci].sum())


def jv(a, n, m):
    """Jonker-Volgenant by shortest augmenting path, the e-maxx residual form:
    the reference the Bend file is a port of. Used ONLY inside guard() -- never
    to produce a printed number -- to confirm that a valid certificate exists
    for the cost brute force found, since the Bend file has to print one.
    Returns (col4row, u, w, cost) or None."""
    u = [0] * (n + 1)
    w = [0] * (m + 1)
    p = [0] * (m + 1)
    way = [0] * (m + 1)
    for i in range(1, n + 1):
        p[0] = i
        j0 = 0
        minv = [INF] * (m + 1)
        used = [False] * (m + 1)
        while True:
            used[j0] = True
            i0 = p[j0]
            delta, j1 = INF, 0
            for j in range(1, m + 1):
                if used[j]:
                    continue
                cij = a[(i0 - 1) * m + (j - 1)]
                cur = INF if cij >= BIG else cij + w[j] - u[i0]
                if cur < minv[j]:
                    minv[j], way[j] = cur, j0
                if minv[j] < delta:
                    delta, j1 = minv[j], j
            if delta >= BIG:
                return None
            for j in range(0, m + 1):
                if used[j]:
                    u[p[j]] += delta
                    w[j] += delta
                else:
                    minv[j] -= delta
            j0 = j1
            if p[j0] == 0:
                break
        while True:
            j1 = way[j0]
            p[j0] = p[j1]
            j0 = j1
            if j0 == 0:
                break
    c4r = [None] * n
    for j in range(1, m + 1):
        if p[j] != 0:
            c4r[p[j] - 1] = j - 1
    return c4r, u, w, sum(a[i * m + c4r[i]] for i in range(n))


def certify(a, n, m, c4r, u, w):
    """The same three checks the Bend file's certify makes."""
    seen = set()
    for i in range(n):
        j = c4r[i]
        if j is None or not 0 <= j < m or j in seen:
            return False
        seen.add(j)
        if u[i + 1] != a[i * m + j] + w[j + 1]:
            return False
    for i in range(n):
        for j in range(m):
            if a[i * m + j] < BIG and u[i + 1] > a[i * m + j] + w[j + 1]:
                return False
    return all(w[j + 1] == 0 for j in range(m) if j not in seen)


def guard(a, n, m):
    """Everything known about this instance, or an exception. Returns
    (cost, ok, cert, gap, unique_perm_or_None)."""
    assert len(a) == n * m, "matrix is not n*m"
    assert all(x < BIG or x == INF for x in a), "a cost between big and inf"
    assert all(x < BIG for x in a if x != INF), "an out-of-contract cost"
    if n * max(a + [0], default=0) >= BIG and any(x != INF for x in a):
        finite = [x for x in a if x != INF]
        assert n * max(finite, default=0) < BIG, "nr * max cost is out of contract"

    if m < n:  # no full matching can exist
        return 0, 0, 0, None, None

    best, cnt, arg = brute(a, n, m)
    if best is None:  # feasible shape, but the allowed cells cannot cover it
        assert jv(a, n, m) is None, "brute force says infeasible and JV does not"
        return 0, 0, 0, None, None

    sp = scipy_cost(a, n, m)
    assert sp is None or sp == best, "SciPy and brute force disagree: %r %r" % (
        sp,
        best,
    )

    r = jv(a, n, m)
    assert r is not None, "brute force found a matching and JV did not"
    c4r, u, w, cost = r
    assert cost == best, "JV cost %d, brute force %d" % (cost, best)
    assert certify(a, n, m, c4r, u, w), "JV's own prices do not certify"
    gap = sum(u[1:]) - sum(w[1:])
    assert gap == best, "duality gap %d is not the cost %d" % (gap, best)
    return best, 1, 1, gap, (arg if cnt == 1 else None)


# -- emitting ----------------------------------------------------------------


def lit(a):
    return "[%s]" % ", ".join(map(str, a))


def case(a, n, m, perm=True, gap=True):
    cost, ok, cert, g, arg = guard(a, n, m)
    call = "Assign.solve(mat(%s), %d, %d)" % (lit(a), n, m)
    rows.append("line(%s)" % call)
    want.append("%d %d %d" % (cost, ok, cert))
    if perm and arg is not None and n > 0:  # a map of no rows prints a blank line
        rows.append("perm(%d, %s)" % (n, call))
        want.append(" ".join(map(str, arg)))
    if gap and g is not None:
        rows.append("gap(%d, %d, %s)" % (n, m, call))
        want.append(str(g))


def case_opt(a, n, m, gate, gap=True):
    """solve_opt is solve over the padded matrix, so the oracle pads too: the
    optimum over partial matchings priced at `gate` IS the optimum over the
    matrix with one opt-out column per row."""
    wide = n + m
    padded = []
    for i in range(n):
        padded += a[i * m : (i + 1) * m]
        padded += [gate if k == i else INF for k in range(n)]
    cost, ok, cert, g, arg = guard(padded, n, wide)
    call = "Assign.solve_opt(mat(%s), %d, %d, %d)" % (lit(a), n, m, gate)
    rows.append("line(%s)" % call)
    want.append("%d %d %d" % (cost, ok, cert))
    if arg is not None:
        rows.append("perm(%d, %s)" % (n, call))
        want.append(" ".join(map(str, arg)))
    if gap and g is not None:
        rows.append("gap(%d, %d, %s)" % (n, wide, call))
        want.append(str(g))


# -- the instances -----------------------------------------------------------

# dense squares, the shape everything else is a deviation from. Costs drawn
# from a range wide enough that ties are the exception, so most of these pin
# the permutation as well as the cost.
for n in [1, 2, 3, 4, 5, 6, 7]:
    for _ in range(2):
        case([rng.randrange(0, 40) for _ in range(n * n)], n, n, gap=(n % 2 == 1))

# rectangles: more columns than rows, so some columns are left over and their
# price has to come back zero -- which is a thing certify checks
for n, m in [(1, 4), (2, 5), (3, 4), (3, 7), (4, 6), (5, 6)]:
    case([rng.randrange(0, 30) for _ in range(n * m)], n, m)

# taller than wide: no full matching exists at any price
for n, m in [(2, 1), (3, 2), (5, 4), (4, 0)]:
    case([rng.randrange(0, 30) for _ in range(n * m)], n, m)

# ties: every optimum is one of many, so nothing but the cost and the
# certificate is pinned, and the solver's tie-break is free to move
for n, v in [(2, 0), (3, 0), (3, 7), (4, 1), (5, 3)]:
    case([v] * (n * n), n, n)
# a matrix of two values only, which makes long ties inside one row
for n in [4, 5]:
    case([rng.choice([2, 9]) for _ in range(n * n)], n, n)


# forbidden cells. A sparse row is the real shape of a gated tracker: most
# pairings are ruled out before the solver ever sees them.
def sparse(n, m, keep, hi=25):
    a = [INF] * (n * m)
    for i in range(n):
        for j in rng.sample(range(m), keep):
            a[i * m + j] = rng.randrange(0, hi)
    return a


for n, m, keep in [(3, 3, 2), (4, 4, 2), (4, 5, 2), (5, 5, 3), (6, 6, 3), (5, 8, 2)]:
    a = sparse(n, m, keep)
    best, _, _ = brute(a, n, m)
    if best is None:
        continue  # the draw happened to be infeasible; the block below pins that
    case(a, n, m, gap=False)

# infeasible by gating: two rows that can only reach the same one column, and a
# row that can reach nothing at all
case([1, INF, INF, 2, INF, INF, INF, INF, 3], 3, 3)
case([INF, INF, INF, 1, 2, 3, 4, 5, 6], 3, 3)
case([5, INF, INF, 6], 2, 2, gap=False)
case([INF, 1, 7, INF], 2, 2, gap=False)

# opting out. The gate is the price of leaving a row unmatched: below every
# real option nothing is matched, above every real option everything is.
for a, n, m, gates in [
    ([9, 9, 9, 9], 2, 2, [0, 3, 8, 9, 20]),
    ([1, 9, 9, 9], 2, 2, [3, 20]),
    ([4, 7, 2, 6, 3, 8], 2, 3, [1, 5, 50]),
    ([3, 1, 4, 1, 5, 9, 2, 6, 5], 3, 3, [2, 4, 100]),
]:
    for g in gates:
        case_opt(a, n, m, g, gap=(g in (3, 5, 4)))
# a wide gate over a sparse matrix: the rows that cannot reach anything take it
case_opt([INF, 2, INF, INF, INF, INF], 2, 3, 7)

# edges: no rows, no columns, one of each
case([], 0, 0, gap=False)
case([], 0, 3, gap=False)
case([6], 1, 1)
case([8, 2, 5, 1], 1, 4)
case([3, 1, 4, 1], 4, 1)

# big enough that brute force is the wrong oracle and SciPy is the right one,
# and wide enough costs that the answer is one permutation
for n in [8, 9]:
    a = rng.sample(range(1000), n * n)
    sp = scipy_cost(a, n, n)
    r = jv(a, n, n)
    assert r is not None and r[3] == sp, "JV and SciPy disagree at n=%d" % n
    assert certify(a, n, n, r[0], r[1], r[2]), "JV's prices do not certify at n=%d" % n
    assert sum(r[1][1:]) - sum(r[2][1:]) == sp, (
        "duality gap is not the cost at n=%d" % n
    )
    call = "Assign.solve(mat(%s), %d, %d)" % (lit(a), n, n)
    rows.append("line(%s)" % call)
    want.append("%d 1 1" % sp)
    rows.append("gap(%d, %d, %s)" % (n, n, call))
    want.append(str(sp))

# the top of the contract: costs near 2^31 / nr, where the prices are the
# largest they can be and still fit
hi = (BIG // 4) - 1
case([hi, hi - 3, hi - 7, hi - 1], 2, 2)
case([hi - 5, 2, 9, hi - 2], 2, 2)

# ponytail: the row count is capped by the JS lane, not by the algebra -- the
# emitted `do` block is one nested closure a statement and V8's stack gives out
# somewhere past 300, so a fixture stays near postings' 200.
assert len(rows) < 260, "fixture is %d rows, past what the JS lane will take" % len(
    rows
)

print("""# Assign against brute force over the injective maps, cross-checked against
# SciPy (assign_gen.py prints this file). A row is "<cost> <ok> <cert>": what
# the matching costs, whether a full one was found, and whether the prices that
# came back prove it optimal. `perm` rows appear only where exactly one map
# reaches the optimum; `gap` rows print (sum of row prices - sum of column
# prices), which strong duality makes equal to the cost and which is unique
# however the ties fell.
import Base
import ../../power/vec.bend as Vec
import ../../power/assign.bend as Assign

def mat(xs: List<&2, U32>) -> Vec.Vec:
  Vec.from_list(xs, Vec.new(0))

def yn(b: Bool) -> String:
  match b:
    case True{}:
      "1"
    case False{}:
      "0"

def line.ck(k: U32, ok: Bool, x: Assign.Ck) -> String:
  match x:
    case Assign.Ck{c, s, cert}:
      U32.show(k) ++ " " ++ yn(ok) ++ " " ++ yn(cert)

def line.ok(c: Vec.Vec, k: U32, r: Assign.Sol & Bool) -> String:
  (s, ok) = r
  line.ck(k, ok, Assign.certify(c, s))

def line.cost(c: Vec.Vec, r: Assign.Sol & U32) -> String:
  (s, k) = r
  line.ok(c, k, Assign.solved(s))

def line(r: Vec.Vec & Assign.Sol) -> String:
  (c, s) = r
  line.cost(c, Assign.cost(s))

def perm.at(acc: List<&2, String>, r: Assign.Sol & U32) -> Assign.Sol & List<&2, String>:
  (s, x) = r
  (s, Con{U32.show(x), acc})

def perm.one(i: U32, sa: Assign.Sol & List<&2, String>) -> Assign.Sol & List<&2, String>:
  (s, acc) = sa
  perm.at(acc, Assign.at(s, i))

def perm.go(fuel: Nat, sa: Assign.Sol & List<&2, String>) -> Assign.Sol & List<&2, String>:
  match fuel:
    case 0n:
      sa
    case 1n++q:
      perm.go(q, perm.one(U32.from_nat(q), sa))

def perm.txt(r: Assign.Sol & List<&2, String>) -> String:
  (s, xs) = r
  String.join(xs, " ")

def perm(+n: U32, r: Vec.Vec & Assign.Sol) -> String:
  (c, s) = r
  perm.txt(perm.go(U32.to_nat(n), (s, [])))

def gap.add(acc: U32, r: Assign.Sol & U32) -> Assign.Sol & U32:
  (s, x) = r
  (s, U32.add(acc, x))

def gap.row(i: U32, sa: Assign.Sol & U32) -> Assign.Sol & U32:
  (s, acc) = sa
  gap.add(acc, Assign.price_row(s, i))

def gap.rows(fuel: Nat, sa: Assign.Sol & U32) -> Assign.Sol & U32:
  match fuel:
    case 0n:
      sa
    case 1n++q:
      gap.rows(q, gap.row(U32.from_nat(q), sa))

def gap.col(j: U32, sa: Assign.Sol & U32) -> Assign.Sol & U32:
  (s, acc) = sa
  gap.add(acc, Assign.price_col(s, j))

def gap.cols(fuel: Nat, sa: Assign.Sol & U32) -> Assign.Sol & U32:
  match fuel:
    case 0n:
      sa
    case 1n++q:
      gap.cols(q, gap.col(U32.from_nat(q), sa))

def gap.sub(su: U32, r: Assign.Sol & U32) -> String:
  (s, sw) = r
  U32.show(U32.sub(su, sw))

def gap.go(+nc: U32, r: Assign.Sol & U32) -> String:
  (s, su) = r
  gap.sub(su, gap.cols(U32.to_nat(nc), (s, 0)))

def gap(+nr: U32, +nc: U32, r: Vec.Vec & Assign.Sol) -> String:
  (c, s) = r
  gap.go(nc, gap.rows(U32.to_nat(nr), (s, 0)))

def main() -> IO(Unit):
  do IO<Unit>:""")
for r in rows:
    print("    IO.print(%s)" % r)
for w in want:
    print("#|" + w)
