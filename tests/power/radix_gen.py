#!/usr/bin/env python3
# The oracle for radix.bend: prints the whole fixture. Sorting is CPython's
# `sorted`, counting is `collections.Counter`, grouping is a dict fold -- so a
# stable-sort bug, a digit bug and a run-boundary bug each show as a diff.
# Duplicates, keys that differ only in the top byte, and 0 / 2^32-1 are in every
# family; lengths 0, 1 and 2 in each.
import collections
import random

rng = random.Random(20260930)
M = 0xFFFFFFFF


def vec(n):
    # spread across the four digits: whole-range keys, keys that collide in the
    # low byte, keys that differ only in the top byte, and the two extremes
    return [
        rng.choice(
            [
                rng.getrandbits(32),
                rng.randrange(8) << 24,
                rng.randrange(300),
                rng.randrange(4) * 65536,
                0,
                M,
            ]
        )
        for _ in range(n)
    ]


def lit(xs):
    return "[%s]" % ", ".join(map(str, xs))


def show(xs):
    return ", ".join(map(str, xs))


rows, want = [], []
for n in [0, 1, 2, 3, 40]:
    xs = vec(n)
    rows.append("one(Radix.sort(of(%s)))" % lit(xs))
    want.append(show(sorted(xs)))

# every element the same, already sorted, and exactly reversed: the three shapes
# a counting pass can get wrong without a random test noticing
for xs in [[7] * 12, list(range(12)), list(range(12))[::-1], [M, 0] * 6]:
    rows.append("one(Radix.sort(of(%s)))" % lit(xs))
    want.append(show(sorted(xs)))

# tally / unique: the runs of the sorted vector are the groups
for n in [0, 1, 2, 30]:
    xs = [rng.choice([0, 1, 2, 300, 65536, M]) for _ in range(n)]
    c = collections.Counter(xs)
    rows.append("two(Radix.tally(of(%s)))" % lit(xs))
    want.append("%s | %s" % (show(sorted(c)), show([c[k] for k in sorted(c)])))
    rows.append("one(Radix.unique(of(%s)))" % lit(xs))
    want.append(show(sorted(c)))

# histogram by an explicit bucket function: low byte, and a 5-way fold
rows.append("two(Radix.histogram(~Radix.d0, 256, of(%s)))" % lit(vec(0)))
want.append(" | %s" % show([0] * 256))
for n in [1, 25]:
    xs = vec(n)
    lo = collections.Counter(x & 255 for x in xs)
    rows.append("two(Radix.histogram(~Radix.d0, 256, of(%s)))" % lit(xs))
    want.append("%s | %s" % (show(xs), show([lo[b] for b in range(256)])))
    hi = collections.Counter(x >> 24 for x in xs)
    rows.append("two(Radix.histogram(~Radix.d24, 256, of(%s)))" % lit(xs))
    want.append("%s | %s" % (show(xs), show([hi[b] for b in range(256)])))
    five = collections.Counter(x % 5 for x in xs)
    rows.append("two(Radix.histogram(~mod5, 5, of(%s)))" % lit(xs))
    want.append("%s | %s" % (show(xs), show([five[b] for b in range(5)])))

# sort_by_key: the values ride along, and equal keys keep their input order --
# the values are 1000, 1001, ... so a stability break is visible as a swap
for n in [0, 1, 2, 24]:
    ks = [rng.choice([0, 1, 1, 2, 70000, M]) for _ in range(n)]
    vs = [1000 + i for i in range(n)]
    order = sorted(range(n), key=lambda i: ks[i])  # python's sort is stable
    rows.append("two(Radix.sort_by_key(of(%s), of(%s)))" % (lit(ks), lit(vs)))
    want.append(
        "%s | %s" % (show([ks[i] for i in order]), show([vs[i] for i in order]))
    )

# reduce_by_key: sum, max and a non-commutative fold, so the row pins the order
# the values arrive in, not just the set
OPS = {
    "U32.add": lambda a, x: (a + x) & M,
    "most": max,
    "hash": lambda a, x: (a * 31 + x) & M,
}
for n in [0, 1, 2, 30]:
    ks = [rng.choice([0, 1, 1, 2, 70000, M]) for _ in range(n)]
    vs = [rng.randrange(1, 500) for _ in range(n)]
    order = sorted(range(n), key=lambda i: ks[i])
    for name, f in OPS.items():
        acc = {}
        for i in order:
            acc[ks[i]] = f(acc[ks[i]], vs[i]) if ks[i] in acc else vs[i]
        rows.append(
            "two(Radix.reduce_by_key(~%s, of(%s), of(%s)))" % (name, lit(ks), lit(vs))
        )
        want.append(
            "%s | %s" % (show(sorted(acc)), show([acc[k] for k in sorted(acc)]))
        )

print("""# Radix against CPython's sorted / Counter (radix_gen.py prints this file). A
# sort row is the values; a tally, histogram, sort_by_key or reduce_by_key row is
# "first Vec | second Vec". `hash` (a * 31 + x) is not commutative, so its rows
# pin the order a run is folded in, not just the set of keys.
import Base
import ../../power/vec.bend as Vec
import ../../power/radix.bend as Radix

def mod5(x: U32) -> U32:
  U32.mod(x, 5)

def most(a: U32, x: U32) -> U32:
  U32.max(a, x)

def hash(a: U32, x: U32) -> U32:
  U32.add(U32.mul(a, 31), x)

def of(xs: List<&2, U32>) -> Vec.Vec:
  Vec.from_list(xs, Vec.new(0))

def shows(xs: List<&2, U32>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{x, t}:
      Con{U32.show(x), shows(t)}

def text(r: Vec.Vec & List<&2, U32>) -> String:
  (v, xs) = r
  String.join(shows(xs), ", ")

def one(v: Vec.Vec) -> String:
  text(Vec.to_list(v))

def two(r: Vec.Vec & Vec.Vec) -> String:
  (a, b) = r
  one(a) ++ " | " ++ one(b)

def main() -> IO(Unit):
  do IO<Unit>:""")
for r in rows:
    print("    IO.print(%s)" % r)
for w in want:
    print("#|" + w)
