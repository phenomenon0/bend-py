#!/usr/bin/env python3
# The oracle for vec.bend: prints the whole fixture. A seeded script of Vec
# operations is replayed against a CPython list; every observation (pop, get,
# set's verdict, len) and the final contents are the expected lines. The script
# crosses four capacity doublings and drains to empty twice.
import random

rng = random.Random(20260919)
xs, ops, want = [], [], []


def val():
    return rng.choice([0, 1, 0xFFFFFFFF, rng.getrandbits(32), rng.getrandbits(8)])


def emit(op):
    kind = op[0]
    if kind == "Push":
        xs.append(op[1])
    elif kind == "Pop":
        want.append(str(xs.pop()) if xs else "none")
    elif kind == "Get":
        want.append(str(xs[op[1]]) if op[1] < len(xs) else "none")
    elif kind == "Set":
        ok = op[1] < len(xs)
        if ok:
            xs[op[1]] = op[2]
        want.append("true" if ok else "false")
    elif kind == "Swap":
        xs[op[1]], xs[op[2]] = xs[op[2]], xs[op[1]]
    elif kind == "Trunc":
        del xs[op[1] :]
    elif kind == "Len":
        want.append(str(len(xs)))
    ops.append("%s{%s}" % (kind, ", ".join(map(str, op[1:]))))


def idx():  # mostly in range, sometimes one past, sometimes far out
    n = len(xs)
    return rng.choice(
        [rng.randrange(n + 1), rng.randrange(n + 1), n, n + 7, 0xFFFFFFFF]
    )


emit(("Pop",))
emit(("Get", 0))
emit(("Len",))
for phase in range(2):
    for _ in range(70):
        r = rng.random()
        if r < 0.55:
            emit(("Push", val()))
        elif r < 0.65:
            emit(("Get", idx()))
        elif r < 0.75:
            emit(("Set", idx(), val()))
        elif r < 0.85 and len(xs) >= 1:
            emit(("Swap", rng.randrange(len(xs)), rng.randrange(len(xs))))
        elif r < 0.90:
            emit(("Trunc", idx()))
        elif r < 0.95:
            emit(("Pop",))
        else:
            emit(("Len",))
    emit(("Len",))
    if phase == 0:
        for _ in range(len(xs) + 2):
            emit(("Pop",))
want.append(", ".join(map(str, xs)))

print("""# Vec against a CPython list (vec_gen.py prints this file): a seeded script of
# operations, every observation one line, the final contents the last.
import Base
import ../../power/vec.bend as Vec

type Op is Data:
  Push{x: U32}
  Pop{}
  Get{i: U32}
  Set{i: U32, x: U32}
  Swap{i: U32, j: U32}
  Trunc{k: U32}
  Len{}

def St() -> Type:
  Vec.Vec & List<&2, String>

def seen(r: Vec.Vec & Maybe<&2, U32>, out: List<&2, String>) -> St():
  (v, m) = r
  match m:
    case None{}:
      (v, Con{"none", out})
    case Some{x}:
      (v, Con{U32.show(x), out})

def told(r: Vec.Vec & Bool, out: List<&2, String>) -> St():
  (v, b) = r
  match b:
    case True{}:
      (v, Con{"true", out})
    case False{}:
      (v, Con{"false", out})

def sized(r: Vec.Vec & U32, out: List<&2, String>) -> St():
  (v, n) = r
  (v, Con{U32.show(n), out})

def step(o: Op, v: Vec.Vec, out: List<&2, String>) -> St():
  match o:
    case Push{x}:
      (Vec.push(v, x), out)
    case Pop{}:
      seen(Vec.pop(v), out)
    case Get{i}:
      seen(Vec.get(v, i), out)
    case Set{i, x}:
      told(Vec.set(v, i, x), out)
    case Swap{i, j}:
      (Vec.swap(v, i, j), out)
    case Trunc{k}:
      (Vec.truncate(v, k), out)
    case Len{}:
      sized(Vec.len(v), out)

def open(o: Op, st: St()) -> St():
  (v, out) = st
  step(o, v, out)

def run(ops: List<&2, Op>, st: St()) -> St():
  match ops:
    case Nil{}:
      st
    case Con{op, t}:
      run(t, open(op, st))

def shows(xs: List<&2, U32>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{x, t}:
      Con{U32.show(x), shows(t)}

def last(r: Vec.Vec & List<&2, U32>, out: List<&2, String>) -> List<&2, String>:
  (v, xs) = r
  Con{String.join(shows(xs), ", "), out}

def report(st: St()) -> String:
  (v, out) = st
  String.join(List.reverse(&2, String, last(Vec.to_list(v), out)), "\\n")

def script() -> List<&2, Op>:
  [""")
for i in range(0, len(ops), 6):
    print("    " + ", ".join(ops[i : i + 6]) + ("," if i + 6 < len(ops) else ""))
print("""  ]

def main() -> IO(Unit):
  IO.print(report(run(script(), (Vec.new(0), []))))
""")
for w in want:
    print("#|" + w)
