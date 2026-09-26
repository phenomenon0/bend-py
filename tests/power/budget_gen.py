#!/usr/bin/env python3
# The oracle for budget.bend: prints the whole fixture. Every answer comes from
# the Ref class below, written in plain CPython integers -- three ints and a
# tuple, not a second copy of the Bend file.
#
# The four laws are asserted *here* as well as pinned in the file, because a row
# that Bend and this oracle both get wrong would still pass the four lanes:
#
#   afford(b, m, n) == is_done(spend(b, m, n))
#   join(lo(b), hi(b)) == b
#   cap(outer, inner) <= outer, meterwise
#   used(b0, b, m) + left(b, m) == left(b0, m)
#
# A row that carries both sides of a law in one string is the point: "1 7 5 2"
# is afford saying yes *and* the budget the charge produced, so a Bend that
# answered yes and then refused cannot print that line at all.
import random

rng = random.Random(20260930)
MAX = 0xFFFFFFFF
METERS = ["work", "out", "calls"]


class Ref:
    """A Budget as three CPython ints."""

    def __init__(self, w, o, c):
        self.t = (w, o, c)

    def __eq__(self, x):
        return self.t == x.t

    def left(self, m):
        return self.t[m]

    def set(self, m, n):
        v = list(self.t)
        v[m] = n
        return Ref(*v)

    def afford(self, m, n):
        return n <= self.t[m]

    def spend(self, m, n):
        return self.set(m, self.t[m] - n) if self.afford(m, n) else ("dry", m)

    def take(self, m, n):
        g = min(n, self.t[m])
        return self.set(m, self.t[m] - g), g

    def is_empty(self):
        return self.t == (0, 0, 0)

    def join(self, b):
        return Ref(*[min(x + y, MAX) for x, y in zip(self.t, b.t)])

    def hi(self):
        return Ref(*[x >> 1 for x in self.t])

    def lo(self):
        return Ref(*[x - (x >> 1) for x in self.t])

    def cap(self, i):
        return Ref(*[min(x, y) for x, y in zip(self.t, i.t)])


def used(started, now, m):
    return max(0, started.left(m) - now.left(m))


def fold(r, m, n):
    return r if isinstance(r, tuple) else r.spend(m, n)


def law(b, m, n, o):
    """The four laws, on every budget this file mentions. Raises rather than
    emits, so a row that breaks one can never reach the fixture."""
    assert b.afford(m, n) == (not isinstance(b.spend(m, n), tuple))
    assert b.lo().join(b.hi()) == b
    assert all(x <= y for x, y in zip(b.cap(o).t, b.t))
    later, _ = b.take(m, n)
    assert used(b, later, m) + later.left(m) == b.left(m)


def sb(b):
    return "%d %d %d" % b.t


def sr(r):
    return "dry:" + METERS[r[1]] if isinstance(r, tuple) else sb(r)


def mk(b):
    return "B.new(%d, %d, %d)" % b.t


def cap_of(m):
    return "B." + METERS[m].capitalize() + "{}"


rows, want = [], []


def row(call, text):
    rows.append(call)
    want.append(text)


# the five that say something -- empty, one unit, the working shape, an odd one
# that only an exact lo/hi survives, and the saturated ceiling -- plus six drawn
# ones so the laws are not only checked on the numbers a human would pick.
ALL = [Ref(0, 0, 0), Ref(1, 0, 0), Ref(10, 5, 2), Ref(7, 5, 3), Ref(MAX, MAX, MAX)]
ALL += [
    Ref(rng.randrange(0, 200), rng.randrange(0, 200), rng.randrange(0, 40))
    for _ in range(6)
]
for b in ALL:
    for m in range(3):
        law(b, m, rng.randrange(0, 300), ALL[rng.randrange(0, len(ALL))])

# -- construction and reading ------------------------------------------------

row("sb(B.none())", sb(Ref(0, 0, 0)))
row("sb(B.all())", sb(Ref(MAX, MAX, MAX)))
for b in ALL[:5]:
    row("sb(%s)" % mk(b), sb(b))
for m in range(3):
    row("num(B.left(%s, %s))" % (mk(ALL[2]), cap_of(m)), str(ALL[2].left(m)))
for b in [Ref(0, 0, 0), Ref(0, 0, 1), Ref(1, 0, 0), Ref(10, 5, 2)]:
    row("yn(B.is_empty(%s))" % mk(b), "1" if b.is_empty() else "0")

# -- law 1: afford and spend are the same predicate --------------------------
# one row is both halves, so a yes followed by a refusal cannot print it

for b in ALL[:6]:
    for m in range(3):
        for n in [b.left(m), (b.left(m) + 1) & MAX, 300]:
            row(
                "pair(B.afford(%s, %s, %d), B.spend(%s, %s, %d))"
                % (mk(b), cap_of(m), n, mk(b), cap_of(m), n),
                ("1 " if b.afford(m, n) else "0 ") + sr(b.spend(m, n)),
            )

# -- take: capped instead of refused -----------------------------------------

for b in ALL[:4]:
    for m in range(3):
        for n in [b.left(m) // 2, b.left(m) + 7]:
            nb, g = b.take(m, n)
            row(
                "got(B.take(%s, %s, %d))" % (mk(b), cap_of(m), n),
                "%s got %d" % (sb(nb), g),
            )

# -- law 4: used + left == left before ---------------------------------------
# the second number is the answer the first must equal; a leak prints two

for b in ALL[:4]:
    for m in range(3):
        later, _ = b.take(m, rng.randrange(0, 250))
        row(
            "acct(%s, %s, %s)" % (mk(b), mk(later), cap_of(m)),
            "%d %d" % (used(b, later, m) + later.left(m), b.left(m)),
        )
        # a `now` holding more than `started` is off the timeline: clamped to 0
        row(
            "num(B.used(%s, %s, %s))" % (mk(later), mk(b), cap_of(m)),
            str(used(later, b, m)),
        )

# -- law 2: a fork neither loses nor invents ---------------------------------
# lo takes the ceiling, so an odd allowance is never rounded away

for b in ALL[:6] + [Ref(1, 1, 1), Ref(3, 5, 7), Ref(MAX, 1, 0)]:
    row(
        "halves(%s)" % mk(b),
        "%s | %s -> %s" % (sb(b.lo()), sb(b.hi()), sb(b.lo().join(b.hi()))),
    )
    row("sj(B.split(%s))" % mk(b), sb(b))

# -- join saturates: it may lose budget, never invent it ---------------------

for a, x in [
    (Ref(MAX, MAX, MAX), Ref(1, 1, 1)),
    (Ref(MAX, 0, 3), Ref(MAX, MAX, 4)),
    (Ref(0, 0, 0), Ref(9, 8, 7)),
]:
    row("sb(B.join(%s, %s))" % (mk(a), mk(x)), sb(a.join(x)))

# -- law 3: cap is meterwise min, so nested code cannot raise a limit --------

for o in ALL[:4]:
    for i in [Ref(MAX, MAX, MAX), Ref(0, 0, 0), Ref(99, 1, 7)]:
        row("sb(B.cap(%s, %s))" % (mk(o), mk(i)), sb(o.cap(i)))

# -- fold: a chain keeps the first refusal -----------------------------------

CHAIN = [(0, 3), (1, 2), (2, 1), (0, 4)]
for b in [Ref(10, 5, 2), Ref(7, 5, 3), Ref(6, 5, 2), Ref(10, 1, 2), Ref(10, 5, 0)]:
    call = "B.spend(%s, B.Work{}, %d)" % (mk(b), CHAIN[0][1])
    r = b.spend(*CHAIN[0])
    for m, n in CHAIN[1:]:
        call = "B.fold(%s, %s, %d)" % (call, cap_of(m), n)
        r = fold(r, m, n)
    row("sr(%s)" % call, sr(r))

# -- the fork tree: the law under the thing it exists for --------------------
# depth d hands lo/hi down and joins the remainders back; leaf i charges
# (i mod 3) + 1 against Work. The row is "<spent>+<left>", and spent + left ==
# started is the whole claim -- including w = 7 under 16 leaves, where a leaf
# that cannot afford its charge takes what is there and the tree still balances.


def ftree(d, i, b):
    if d == 0:
        return b.take(0, i % 3 + 1)
    a = ftree(d - 1, i * 2, b.lo())
    x = ftree(d - 1, i * 2 + 1, b.hi())
    return a[0].join(x[0]), a[1] + x[1]


for d in [0, 1, 2, 3, 4]:
    for w in [0, 7, 9, 1000]:
        nb, spent = ftree(d, 0, Ref(w, 0, 0))
        assert spent + nb.left(0) == w
        row("tree(%dn, %d)" % (d, w), "%d+%d" % (spent, nb.left(0)))

print(
    """# Budget against three CPython ints (budget_gen.py prints this file). The rows
# that carry two numbers, or a "1 "/"0 " prefix, are the laws: both sides of one
# claim in one string, so a Bend that satisfies only one side cannot print them.
import Base
import ../../power/budget.bend as B

def sb(b: B.Budget) -> String:
  match b:
    case B.Budget{w, o, c}:
      U32.show(w) ++ " " ++ U32.show(o) ++ " " ++ U32.show(c)

def err(e: B.Error) -> String:
  match e:
    case B.Dry{m}:
      "dry:" ++ B.show.m(m)

def sr(r: B.Res(B.Budget)) -> String:
  match r:
    case Done{b}:
      sb(b)
    case Fail{e}:
      err(e)

def yn(b: Bool) -> String:
  match b:
    case True{}:
      "1"
    case False{}:
      "0"

def num(n: U32) -> String:
  U32.show(n)

def pair(a: Bool, r: B.Res(B.Budget)) -> String:
  yn(a) ++ " " ++ sr(r)

def got(r: B.Budget & U32) -> String:
  (b, n) = r
  sb(b) ++ " got " ++ U32.show(n)

def sj(r: B.Budget & B.Budget) -> String:
  (a, b) = r
  sb(B.join(a, b))

# law 4 in one row: the accounted total beside the total it has to equal
def acct(+b0: B.Budget, +b: B.Budget, +m: B.Meter) -> String:
  U32.show(U32.add(B.used(b0, b, m), B.left(b, m))) ++ " " ++ U32.show(B.left(b0, m))

def halves(+b: B.Budget) -> String:
  sb(B.lo(b)) ++ " | " ++ sb(B.hi(b)) ++ " -> " ++ sb(B.join(B.lo(b), B.hi(b)))

# the tree the law exists for: lo/hi down, join back, spent counted at the leaf
def tree.mix2(p: B.Budget, +s: U32, x: B.Budget & U32) -> B.Budget & U32:
  (q, t) = x
  (B.join(p, q), U32.add(s, t))

def tree.mix(a: B.Budget & U32, x: B.Budget & U32) -> B.Budget & U32:
  (p, s) = a
  tree.mix2(p, s, x)

def ftree(d: Nat, +i: U32, +b: B.Budget) -> B.Budget & U32:
  match d:
    case 0n:
      B.take(b, B.Work{}, U32.add(U32.mod(i, 3), 1))
    case 1n++p:
      a x = ftree(p, U32.mul(i, 2), B.lo(b)) ftree(p, U32.add(U32.mul(i, 2), 1), B.hi(b))
      tree.mix(a, x)

def tree.show(r: B.Budget & U32) -> String:
  (b, s) = r
  U32.show(s) ++ "+" ++ U32.show(B.left(b, B.Work{}))

def tree(d: Nat, +w: U32) -> String:
  tree.show(ftree(d, 0, B.new(w, 0, 0)))

def main() -> IO(Unit):
  do IO<Unit>:"""
)
for r in rows:
    print("    IO.print(%s)" % r)
for w in want:
    print("#|" + w)
