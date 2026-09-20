#!/usr/bin/env python3
# The oracle for bitset.bend: prints the whole fixture. A seeded script of
# Bitset operations is replayed against a CPython int used as a bit string;
# every test and count is an expected line. Indexes past the capacity wrap, as
# the Array under it does. The last row zips two 2^17-bit sets built from one
# index list each and counts the four results.
import random

rng = random.Random(20260920)
D = 3
BITS = 32 << D
bits, ops, want = 0, [], []


def idx():
    return rng.choice([rng.randrange(BITS), rng.randrange(BITS), 0, BITS - 1,
                       BITS + rng.randrange(BITS), 0xFFFFFFFF])


def of(xs, n):
    r = 0
    for i in xs:
        r |= 1 << (i % n)
    return r


ZIP = {"And": lambda a, b: a & b, "Or": lambda a, b: a | b,
       "Xor": lambda a, b: a ^ b, "Andnot": lambda a, b: a & ~b}


def emit(kind, arg=None):
    global bits
    if kind == "Set":
        bits |= 1 << (arg % BITS)
    elif kind == "Clear":
        bits &= ~(1 << (arg % BITS))
    elif kind == "Flip":
        bits ^= 1 << (arg % BITS)
    elif kind == "Test":
        want.append("true" if bits >> (arg % BITS) & 1 else "false")
    elif kind == "Count":
        want.append(str(bin(bits).count("1")))
    else:
        bits = ZIP[kind](bits, of(arg, BITS))
    if kind == "Count":
        ops.append("Count{}")
    elif kind in ZIP:
        ops.append("%s{[%s]}" % (kind, ", ".join(map(str, arg))))
    else:
        ops.append("%s{%d}" % (kind, arg))


emit("Count")
emit("Test", 0)
for _ in range(120):
    r = rng.random()
    if r < 0.35:
        emit("Set", idx())
    elif r < 0.45:
        emit("Clear", idx())
    elif r < 0.55:
        emit("Flip", idx())
    elif r < 0.75:
        emit("Test", idx())
    elif r < 0.85:
        emit("Count")
    else:
        emit(rng.choice(list(ZIP)), [idx() for _ in range(rng.randrange(40))])
for i in range(0, BITS, 7):
    emit("Test", i)
emit("Count")

BIG = 12
xs = [rng.getrandbits(32) for _ in range(400)]
ys = xs[:150] + [rng.getrandbits(32) for _ in range(250)]
n = 32 << BIG
want.append(" ".join(str(bin(f(of(xs, n), of(ys, n))).count("1")) for f in ZIP.values()))

print("""# Bitset against a CPython int (bitset_gen.py prints this file): a seeded script
# of operations, every test and count one line; then four zips of two 2^%d-bit
# sets, counted.
import Base
import ../../power/bitset.bend as Bitset

type Op is Data:
  Set{i: U32}
  Clear{i: U32}
  Flip{i: U32}
  Test{i: U32}
  Count{}
  And{xs: List<&2, U32>}
  Or{xs: List<&2, U32>}
  Xor{xs: List<&2, U32>}
  Andnot{xs: List<&2, U32>}

def St() -> Type:
  Bitset.Bitset & List<&2, String>

def told(r: Bitset.Bitset & Bool, out: List<&2, String>) -> St():
  (b, t) = r
  match t:
    case True{}:
      (b, Con{"true", out})
    case False{}:
      (b, Con{"false", out})

def sized(r: Bitset.Bitset & U32, out: List<&2, String>) -> St():
  (b, n) = r
  (b, Con{U32.show(n), out})

def step(o: Op, b: Bitset.Bitset, out: List<&2, String>) -> St():
  match o:
    case Set{i}:
      (Bitset.set(b, i), out)
    case Clear{i}:
      (Bitset.clear(b, i), out)
    case Flip{i}:
      (Bitset.flip(b, i), out)
    case Test{i}:
      told(Bitset.test(b, i), out)
    case Count{}:
      sized(Bitset.count(b), out)
    case And{xs}:
      (Bitset.and(b, Bitset.from_list(xs, Bitset.new(%dn))), out)
    case Or{xs}:
      (Bitset.or(b, Bitset.from_list(xs, Bitset.new(%dn))), out)
    case Xor{xs}:
      (Bitset.xor(b, Bitset.from_list(xs, Bitset.new(%dn))), out)
    case Andnot{xs}:
      (Bitset.andnot(b, Bitset.from_list(xs, Bitset.new(%dn))), out)

def open(o: Op, st: St()) -> St():
  (b, out) = st
  step(o, b, out)

def run(ops: List<&2, Op>, st: St()) -> St():
  match ops:
    case Nil{}:
      st
    case Con{o, t}:
      run(t, open(o, st))

def report(st: St()) -> String:
  (b, out) = st
  String.join(List.reverse(&2, String, out), "\\n")

def ones(r: Bitset.Bitset & U32) -> String:
  (b, n) = r
  U32.show(n)

def big(xs: List<&2, U32>) -> Bitset.Bitset:
  Bitset.from_list(xs, Bitset.new(%dn))

def xs() -> List<&2, U32>:
  [%s]

def ys() -> List<&2, U32>:
  [%s]

def script() -> List<&2, Op>:
  [""" % (BIG + 5, D, D, D, D, BIG, ", ".join(map(str, xs)), ", ".join(map(str, ys))))
for i in range(0, len(ops), 5):
    print("    " + ", ".join(ops[i:i + 5]) + ("," if i + 5 < len(ops) else ""))
print("""  ]

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(report(run(script(), (Bitset.new(%dn), []))))
    IO.print(String.join([
      ones(Bitset.count(Bitset.and(big(xs()), big(ys())))),
      ones(Bitset.count(Bitset.or(big(xs()), big(ys())))),
      ones(Bitset.count(Bitset.xor(big(xs()), big(ys())))),
      ones(Bitset.count(Bitset.andnot(big(xs()), big(ys()))))], " "))
""" % D)
for w in want:
    print("#|" + w)
