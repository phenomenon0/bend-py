#!/usr/bin/env python3
# The oracle for consequence.bend: prints the whole fixture. Every answer comes
# from CPython's own dict keyed by the trace tuple, so the partition is checked
# against the language's own notion of equal sequences and not against a second
# copy of this implementation's hash.
#
# That is deliberate, and it is what the file can honestly pin. Bend groups by
# a 32-bit digest; CPython groups by tuple equality. A row matches only if the
# two agree on WHICH readings are the same reading -- which is the whole
# contract. The digest's constants are not part of it: swap Murmur3's
# multiplier for another good one and every row here still passes, because a
# different good hash induces the same partition. So no row prints a digest,
# and the mutants in the lane report break the partition, never the mixer.
#
# A row is "<k>: <reps> | <cnts>" -- how many distinct consequences, the
# lowest-numbered reading standing for each (ascending, so the row does not
# depend on digest order), and how many readings each one speaks for. A "y"/"n"
# row is `settled`: whether there is anything left to ask at all.
import random

rng = random.Random(20260920)

rows, want = [], []
SEED = 2166136261


def lit(xs):
    return "[%s]" % ", ".join(map(str, xs))


def flat(traces):
    acts = [a for t in traces for a in t]
    lens = [len(t) for t in traces]
    return acts, lens


def oracle(traces):
    # first index wins: dict preserves insertion order, so the representative
    # is the lowest-numbered reading with that trace -- the same tie-break the
    # stable sort gives Bend
    groups = {}
    for i, t in enumerate(traces):
        groups.setdefault(tuple(t), []).append(i)
    reps = sorted(g[0] for g in groups.values())
    by_rep = {g[0]: len(g) for g in groups.values()}
    return reps, [by_rep[r] for r in reps]


def call(traces):
    acts, lens = flat(traces)
    return "Conseq.collapse_traces(%d, vec(%s), vec(%s))" % (SEED, lit(acts), lit(lens))


def case(traces):
    reps, cnts = oracle(traces)
    rows.append("grp(%s)" % call(traces))
    want.append(
        "%d: %s | %s" % (len(reps), " ".join(map(str, reps)), " ".join(map(str, cnts)))
    )
    rows.append("yn(Conseq.settled(%s))" % call(traces))
    want.append("y" if len(reps) == 1 else "n")


# the shape the primitive exists for: N readings of one request, most of which
# turn out to do the same thing
case([[1, 2, 3], [1, 2, 3], [1, 2, 3]])  # nothing to ask
case([[1, 2, 3], [1, 2, 4], [1, 2, 3]])  # a real two-way question
case([[1], [2], [3], [4]])  # every reading differs
case([[7]] * 8)  # eight readings, one consequence

# order counts: a preview that does the same things in a different order is a
# different consequence, and the fold has to say so
case([[1, 2], [2, 1]])
case([[1, 2, 3], [3, 2, 1], [1, 2, 3]])
case([[1, 1, 2], [1, 2, 1], [2, 1, 1]])

# prefixes and suffixes: neither containment nor a shared edge may merge
case([[1, 2], [1, 2, 3]])
case([[1, 2, 3], [2, 3]])
case([[1, 2, 3], [1, 2, 3, 1, 2, 3]])
case([[5, 5], [5], [5, 5, 5]])

# the empty trace: a reading that would do nothing is a consequence like any
# other, and two of them are the same one
case([[]])
case([[], []])
case([[], [1]])
case([[1], [], [1], []])
case([[], [], [1, 2], [1, 2], []])
case([[1, 2], []])
case([[], [1], [], [2], []])

# the degenerate ends
case([])  # no readings at all
case([[1]])  # one reading
case([[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]])  # one long one

# a boundary that only a correct cursor gets right: the last trace is empty, so
# its start index is one past the end of the flat block
case([[1, 2, 3], []])
case([[1], [2], []])
case([[], [1, 2, 3]])

# repeated codes inside one trace, which a fold that xors or adds would collapse
case([[1, 1], [1]])
case([[1, 1, 1, 1], [1, 1], [1, 1, 1, 1]])
case([[0], [0, 0], [0, 0, 0]])
case([[0], []])  # a zero action is not an absent action

# values that straddle the digit boundaries the radix sort passes on
case([[255], [256], [65535], [65536], [16777215], [16777216]])
case([[4294967295], [0], [4294967295]])
case([[2147483648], [2147483647]])

# random fleets, the sizes a real clarifier sees, with duplicates planted so
# the partition is never trivially all-distinct
for n, pool, tlen in [(6, 3, 2), (10, 4, 3), (16, 5, 4), (24, 6, 3), (32, 8, 5)]:
    base = [
        [rng.randrange(1, 50) for _ in range(rng.randrange(0, tlen + 1))]
        for _ in range(pool)
    ]
    case([list(base[rng.randrange(pool)]) for _ in range(n)])

# every reading distinct, then every reading identical, at a size where the
# sort actually runs all four passes
case([[i, i * 7919] for i in range(20)])
case([[3, 1, 4, 1, 5]] * 20)

print("""# Consequence against CPython's own dict (consequence_gen.py prints this file).
# A row is "<k>: <reps> | <cnts>": how many distinct consequences N readings
# have, the lowest-numbered reading standing for each, and how many readings
# each one speaks for. Bend groups by a 32-bit digest of each preview trace and
# CPython groups by tuple equality, so a row matches only when the two agree on
# which readings are the same reading. A "y" row is `settled`: every reading
# does the same thing, so there is no question to ask.
import Base
import ../../power/vec.bend as Vec
import ../../power/radix.bend as Radix
import ../../power/consequence.bend as Conseq

def shows(xs: List<&2, U32>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{x, t}:
      Con{U32.show(x), shows(t)}

def text(r: Vec.Vec & List<&2, U32>) -> String:
  (v, xs) = r
  String.join(shows(xs), " ")

def line(v: Vec.Vec) -> String:
  text(Vec.to_list(v))

def vec(xs: List<&2, U32>) -> Vec.Vec:
  Vec.from_list(xs, Vec.new(0))

# the groups come back ascending by digest, which is this implementation's
# business; sorting them by representative is what makes the row an oracle's
def grp.fin(k: U32, r: Vec.Vec & Vec.Vec) -> String:
  (reps, cnts) = r
  U32.show(k) ++ ": " ++ line(reps) ++ " | " ++ line(cnts)

def grp.n(rc: Vec.Vec & Vec.Vec, k: U32) -> String:
  (reps, cnts) = rc
  grp.fin(k, Radix.sort_by_key(reps, cnts))

def grp.cnt(r: Conseq.Groups & U32) -> String:
  (g, k) = r
  grp.n(Conseq.representatives(g), k)

def grp(g: Conseq.Groups) -> String:
  grp.cnt(Conseq.count(g))

def yn.say(b: Bool) -> String:
  match b:
    case True{}:
      "y"
    case False{}:
      "n"

def yn(r: Conseq.Groups & Bool) -> String:
  (g, b) = r
  yn.say(b)

def main() -> IO(Unit):
  do IO<Unit>:""")
for r in rows:
    print("    IO.print(%s)" % r)
for w in want:
    print("#|" + w)
