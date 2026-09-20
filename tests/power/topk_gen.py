#!/usr/bin/env python3
# The oracle for topk.bend: prints the whole fixture. Each row is a stream
# offered to a TopK and drained; the expected line is CPython's
# sorted(stream, reverse=True)[:K]. Keys come from a range of 9, so most of a
# row is ties. The merge rows hold the claim that makes TopK mergeable: the K of
# two halves, merged, are the K of the whole.
import random

rng = random.Random(20260923)
M = 0xFFFFFFFF


def stream(n):
    return [(rng.choice([rng.randrange(9), rng.randrange(9), 0, M]),
             rng.choice([rng.randrange(500), rng.randrange(3), M])) for _ in range(n)]


def lit(xs):
    return "[%s]" % ", ".join("Heap.Entry{%d, %d}" % e for e in xs)


def top(xs, k):
    return " ".join("%d:%d" % e for e in sorted(xs, reverse=True)[:k])


rows, want = [], []
for k, n in [(0, 10), (1, 40), (5, 200), (16, 120), (50, 20), (3, 0)]:
    xs = stream(n)
    rows.append("one(%d, %s)" % (k, lit(xs)))
    want.append(top(xs, k))
for k, n in [(8, 150), (4, 3)]:
    xs, ys = stream(n), stream(n)
    rows.append("two(%d, %s, %s)" % (k, lit(xs), lit(ys)))
    want.append(top(xs + ys, k))

print("""# TopK against CPython's sorted (topk_gen.py prints this file): one row per
# stream, the kept entries best first; an empty row is an empty TopK.
import Base
import ../../power/heap.bend as Heap
import ../../power/topk.bend as TopK

def shows(xs: List<&2, Heap.Entry>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{Heap.Entry{k, x}, t}:
      Con{U32.show(k) ++ ":" ++ U32.show(x), shows(t)}

def line(r: TopK.TopK & List<&2, Heap.Entry>) -> String:
  (t, xs) = r
  String.join(shows(xs), " ")

def one(k: U32, xs: List<&2, Heap.Entry>) -> String:
  line(TopK.drain(TopK.offer_all(xs, TopK.new(k))))

def two(+k: U32, xs: List<&2, Heap.Entry>, ys: List<&2, Heap.Entry>) -> String:
  line(TopK.drain(TopK.merge(TopK.offer_all(xs, TopK.new(k)), TopK.offer_all(ys, TopK.new(k)))))

def main() -> IO(Unit):
  do IO<Unit>:""")
for r in rows:
    print("    IO.print(%s)" % r)
for w in want:
    print("#|" + w)
