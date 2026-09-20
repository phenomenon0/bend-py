#!/usr/bin/env python3
# The oracle for postings.bend: prints the whole fixture. Every answer comes from
# CPython's own `set`, so the algebra is checked against the language's set type
# and not against a second copy of this implementation.
#
# A row is "<shape>[<members>]" -- S for a sorted id vector, D for one bit per
# id -- so a row pins which container the algebra chose as well as what it holds.
# The shapes below are the rules the file states: `and` keeps a sparse side
# because it bounds the answer, `or` keeps a dense side because it absorbs it,
# `andnot` keeps the left side's, and `not` is dense always because it is
# andnot against the full universe.
import random

rng = random.Random(20260925)

rows, want = [], []


def lit(xs):
    return "[%s]" % ", ".join(map(str, sorted(xs)))


def show(shape, members):
    return "%s[%s]" % (shape, " ".join(map(str, sorted(members))))


def row(call, shape, members):
    rows.append(call)
    want.append(show(shape, members))


def pick(n, k):
    return set(rng.sample(range(n), min(k, n)))


# the four shape combinations of each binary operation, plus the complement,
# over universes that straddle a cell boundary (32) and a multi-cell set.
# ponytail: the row count is capped by the JS lane, not by the algebra -- the
# emitted `do` block is one nested closure a statement and V8's stack gives out
# somewhere past 300, so a fixture stays around json's 143.
for n in [1, 33, 70, 200]:
    for a, b in [
        (pick(n, min(n // 3 + 1, 15)), pick(n, min(n // 2 + 1, 11))),
        (pick(n, 1), set()),
    ]:
        univ = set(range(n))
        sides = {
            "sp": ("S", "sp(%s)" % lit(a), "sp(%s)" % lit(b)),
            "dn": ("D", "dn(%s, %d)" % (lit(a), n), "dn(%s, %d)" % (lit(b), n)),
        }
        for la, (sa, ca, _) in sides.items():
            for lb, (sb, _, cb) in sides.items():
                both_sparse = sa == "S" and sb == "S"
                either_sparse = sa == "S" or sb == "S"
                row(
                    "line(Postings.and(%s, %s))" % (ca, cb),
                    "S" if either_sparse else "D",
                    a & b,
                )
                row(
                    "line(Postings.or(%s, %s))" % (ca, cb),
                    "S" if both_sparse else "D",
                    a | b,
                )
                row("line(Postings.andnot(%s, %s))" % (ca, cb), sa, a - b)
            row("line(Postings.not(%s, %d))" % (ca, n), "D", univ - a)
            rows.append("cnt(Postings.count(%s))" % ca)
            want.append(str(len(a)))

# shape moves: densify / sparsify round trip, and optimize's own rule -- dense
# when the set holds more than n/32 ids, which is when the bitmap is cheaper.
# The k's straddle that threshold rather than sweeping the universe: a full
# 1,000-id set says nothing the boundary pair does not, and prints 1,000 numbers
# eight times to say it.
for n in [32, 200, 1000]:
    for k in [0, 1, n >> 5, (n >> 5) + 1] + ([n] if n == 32 else []):
        a = pick(n, k)
        row("line(Postings.densify(sp(%s), %d))" % (lit(a), n), "D", a)
        row("line(Postings.sparsify(dn(%s, %d)))" % (lit(a), n), "S", a)
        big = len(a) > n >> 5
        row("line(Postings.optimize(sp(%s), %d))" % (lit(a), n), "D" if big else "S", a)
        row(
            "line(Postings.optimize(dn(%s, %d), %d))" % (lit(a), n, n),
            "D" if big else "S",
            a,
        )

# the universe itself, and the empty set in both shapes
for n in [0, 1, 31, 32, 33, 64, 100]:
    row("line(Postings.all(%d))" % n, "D", set(range(n)))
row("line(Postings.sparse())", "S", set())
row("line(Postings.dense(64))", "D", set())

# add: ascending pushes onto a sparse set, one bit on a dense one
for n in [8, 40]:
    a = sorted(pick(n, n // 2))
    row("line(Postings.add(sp(%s), %d))" % (lit(a[:-1]), a[-1]), "S", set(a))
    row("line(Postings.add(dn(%s, %d), %d))" % (lit(a[:-1]), n, a[-1]), "D", set(a))

# membership, including an id past the last one and an id past the universe
a = sorted(pick(60, 20))
for x in [a[0], a[len(a) // 2], a[-1], (set(range(60)) - set(a)).pop(), 59, 0]:
    rows.append("hit(Postings.has(sp(%s), %d))" % (lit(a), x))
    want.append("1" if x in a else "0")
    rows.append("hit(Postings.has(dn(%s, 60), %d))" % (lit(a), x))
    want.append("1" if x in a else "0")

# a three-term boolean query, the shape the index actually asks for:
# (t0 OR t1) AND NOT t2
t0, t1, t2 = pick(120, 30), pick(120, 25), pick(120, 40)
row(
    "line(Postings.andnot(Postings.or(sp(%s), sp(%s)), sp(%s)))"
    % (lit(t0), lit(t1), lit(t2)),
    "S",
    (t0 | t1) - t2,
)
row(
    "line(Postings.andnot(Postings.or(dn(%s, 120), sp(%s)), dn(%s, 120)))"
    % (lit(t0), lit(t1), lit(t2)),
    "D",
    (t0 | t1) - t2,
)
row(
    "line(Postings.and(Postings.not(sp(%s), 120), Postings.or(sp(%s), sp(%s))))"
    % (lit(t2), lit(t0), lit(t1)),
    "S",
    (t0 | t1) - t2,
)

print("""# Postings against CPython's own set (postings_gen.py prints this file). A row is
# "<shape>[<members>]": S for a sorted id vector, D for one bit per id, so every
# row pins which container the algebra chose as well as what it holds.
import Base
import ../../power/vec.bend as Vec
import ../../power/bitset.bend as Bitset
import ../../power/postings.bend as Postings

def shows(xs: List<&2, U32>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{x, t}:
      Con{U32.show(x), shows(t)}

def text(r: Vec.Vec & List<&2, U32>) -> String:
  (v, xs) = r
  String.join(shows(xs), " ")

def mem(s: Postings.Set) -> String:
  text(Vec.to_list(Postings.to_vec(s)))

def tag.s(v: Vec.Vec) -> Postings.Set & String:
  (Postings.Sparse{v}, "S")

def tag.d(b: Bitset.Bitset) -> Postings.Set & String:
  (Postings.Dense{b}, "D")

def tag(s: Postings.Set) -> Postings.Set & String:
  match s:
    case Postings.Sparse{v}:
      tag.s(v)
    case Postings.Dense{b}:
      tag.d(b)

def show(r: Postings.Set & String) -> String:
  (s, t) = r
  t ++ "[" ++ mem(s) ++ "]"

def line(s: Postings.Set) -> String:
  show(tag(s))

def sp(xs: List<&2, U32>) -> Postings.Set:
  Postings.of_list(xs)

def dn(xs: List<&2, U32>, +n: U32) -> Postings.Set:
  Postings.densify(Postings.of_list(xs), n)

def yn(b: Bool) -> String:
  match b:
    case True{}:
      "1"
    case False{}:
      "0"

def hit(r: Postings.Set & Bool) -> String:
  (s, b) = r
  yn(b)

def cnt(r: Postings.Set & U32) -> String:
  (s, n) = r
  U32.show(n)

def main() -> IO(Unit):
  do IO<Unit>:""")
for r in rows:
    print("    IO.print(%s)" % r)
for w in want:
    print("#|" + w)
