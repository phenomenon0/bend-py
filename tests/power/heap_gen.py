#!/usr/bin/env python3
# The oracle for heap.bend: prints the whole fixture. A seeded script of Heap
# operations is replayed against CPython's heapq over (key, val) tuples; every
# pop, peek and len is an expected line and the final drain (greatest first)
# the last. Keys come from a range of 12 so ties are the common case, and val
# settles them.
import heapq
import random

rng = random.Random(20260922)
M = 0xFFFFFFFF
hp, ops, want = [], [], []


def pair():
    return (rng.choice([rng.randrange(12), rng.randrange(12), 0, M]),
            rng.choice([rng.randrange(1000), rng.randrange(4), 0, M]))


def show(e):
    return "%d:%d" % e


def emit(kind, e=None):
    if kind == "Push":
        heapq.heappush(hp, e)
    elif kind == "Pop":
        want.append(show(heapq.heappop(hp)) if hp else "none")
    elif kind == "Peek":
        want.append(show(hp[0]) if hp else "none")
    elif kind == "Replace":
        heapq.heapreplace(hp, e) if hp else heapq.heappush(hp, e)
    elif kind == "Len":
        want.append(str(len(hp)))
    ops.append("%s{%s}" % (kind, "%d, %d" % e if e else ""))


emit("Pop")
emit("Peek")
emit("Replace", pair())
for phase in range(2):
    for _ in range(90):
        r = rng.random()
        if r < 0.50:
            emit("Push", pair())
        elif r < 0.70:
            emit("Pop")
        elif r < 0.80:
            emit("Peek")
        elif r < 0.93:
            emit("Replace", pair())
        else:
            emit("Len")
    emit("Len")
    if phase == 0:
        for _ in range(len(hp) + 2):
            emit("Pop")
want.append(" ".join(show(e) for e in sorted(hp, reverse=True)))

print("""# Heap against CPython's heapq (heap_gen.py prints this file): a seeded script
# of operations, every observation one line, the final drain the last.
import Base
import ../../power/heap.bend as Heap

type Op is Data:
  Push{k: U32, x: U32}
  Pop{}
  Peek{}
  Replace{k: U32, x: U32}
  Len{}

def St() -> Type:
  Heap.Heap & List<&2, String>

def show(e: Heap.Entry) -> String:
  match e:
    case Heap.Entry{k, x}:
      U32.show(k) ++ ":" ++ U32.show(x)

def seen(r: Heap.Heap & Maybe<&2, Heap.Entry>, out: List<&2, String>) -> St():
  (h, m) = r
  match m:
    case None{}:
      (h, Con{"none", out})
    case Some{e}:
      (h, Con{show(e), out})

def sized(r: Heap.Heap & U32, out: List<&2, String>) -> St():
  (h, n) = r
  (h, Con{U32.show(n), out})

def step(o: Op, h: Heap.Heap, out: List<&2, String>) -> St():
  match o:
    case Push{k, x}:
      (Heap.push(h, k, x), out)
    case Pop{}:
      seen(Heap.pop(h), out)
    case Peek{}:
      seen(Heap.peek(h), out)
    case Replace{k, x}:
      (Heap.replace(h, k, x), out)
    case Len{}:
      sized(Heap.len(h), out)

def open(o: Op, st: St()) -> St():
  (h, out) = st
  step(o, h, out)

def run(ops: List<&2, Op>, st: St()) -> St():
  match ops:
    case Nil{}:
      st
    case Con{o, t}:
      run(t, open(o, st))

def shows(xs: List<&2, Heap.Entry>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{e, t}:
      Con{show(e), shows(t)}

def last(r: Heap.Heap & List<&2, Heap.Entry>, out: List<&2, String>) -> List<&2, String>:
  (h, xs) = r
  Con{String.join(shows(xs), " "), out}

def report(st: St()) -> String:
  (h, out) = st
  String.join(List.reverse(&2, String, last(Heap.drain(h), out)), "\\n")

def script() -> List<&2, Op>:
  [""")
for i in range(0, len(ops), 6):
    print("    " + ", ".join(ops[i:i + 6]) + ("," if i + 6 < len(ops) else ""))
print("""  ]

def main() -> IO(Unit):
  IO.print(report(run(script(), (Heap.new(), []))))
""")
for w in want:
    print("#|" + w)
