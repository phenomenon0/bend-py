#!/usr/bin/env python3
# The oracle for scan.bend: prints the whole fixture. Every row is one Scan call
# on a seeded vector beside the same thing in plain CPython. `hash` (a * 31 + x,
# wrapping) is neither commutative nor associative, so its rows pin the order of
# the scan, not just its sum. Lengths 0 and 1 are in every family.
import random

rng = random.Random(20260924)
M = 0xFFFFFFFF


def vec(n, small=False):
    return [rng.randrange(6) if small else rng.choice([rng.getrandbits(32), rng.randrange(100), M])
            for _ in range(n)]


OPS = {"U32.add": (lambda a, x: (a + x) & M, 0), "most": (max, 0),
       "U32.xor": (lambda a, x: a ^ x, 0), "hash": (lambda a, x: (a * 31 + x) & M, 7)}


def scan(f, acc, xs, ex=False):
    out = []
    for x in xs:
        if ex:
            out.append(acc)
        acc = f(acc, x)
        if not ex:
            out.append(acc)
    return out, acc


def lit(xs):
    return "[%s]" % ", ".join(map(str, xs))


def show(xs):
    return ", ".join(map(str, xs))


rows, want = [], []
for n in [0, 1, 2, 37]:
    for name, (f, idv) in OPS.items():
        xs = vec(n)
        for ex in (False, True):
            rows.append("tot(Scan.%s(~%s, %d, of(%s)))" % ("scan_ex" if ex else "scan", name, idv, lit(xs)))
            out, acc = scan(f, idv, xs, ex)
            want.append("%s | %d" % (show(out), acc))
xs = vec(24, small=True)  # counts to offsets: a CSR row table
rows.append("tot(Scan.offsets(of(%s)))" % lit(xs))
want.append("%s | %d" % (show(scan(OPS["U32.add"][0], 0, xs, True)[0]), sum(xs)))
xs = vec(20)
rows.append("tot(Scan.sums(of(%s)))" % lit(xs))
want.append("%s | %d" % (show(scan(OPS["U32.add"][0], 0, xs)[0]), sum(xs) & M))

for n in [0, 1, 40]:
    for name in ["U32.add", "hash"]:
        f, idv = OPS[name]
        xs, hs = vec(n), [rng.choice([0, 0, 0, 1, M]) for _ in range(n)]
        out, acc = [], idv
        for x, h in zip(xs, hs):
            acc = f(idv if h else acc, x)
            out.append(acc)
        rows.append("two(Scan.segmented(~%s, %d, of(%s), of(%s)))" % (name, idv, lit(xs), lit(hs)))
        want.append("%s | %s" % (show(out), show(hs)))

for n in [0, 1, 40]:
    xs = vec(n)
    rows.append("one(Scan.filter(~U32.is_even, of(%s)))" % lit(xs))
    want.append(show([x for x in xs if x % 2 == 0]))
    rows.append("one(Scan.filter(~small, of(%s)))" % lit(xs))
    want.append(show([x for x in xs if x < 50]))
    fs = [rng.choice([0, 1, 0, M]) for _ in range(n)]
    rows.append("two(Scan.compact(of(%s), of(%s)))" % (lit(xs), lit(fs)))
    want.append("%s | %s" % (show([x for x, f in zip(xs, fs) if f]), show(fs)))

for n in [0, 1, 2, 60]:
    xs = [rng.choice([0, 1, 2, M]) for _ in range(n)]
    runs = []
    for x in xs:
        if runs and runs[-1][0] == x:
            runs[-1][1] += 1
        else:
            runs.append([x, 1])
    rows.append("two(Scan.rle(of(%s)))" % lit(xs))
    want.append("%s | %s" % (show([r[0] for r in runs]), show([r[1] for r in runs])))

print("""# Scan against plain CPython loops (scan_gen.py prints this file). A scan row is
# "values | total"; a segmented or compact row "values | the second Vec handed
# back"; an rle row "values | counts".
import Base
import ../../power/vec.bend as Vec
import ../../power/scan.bend as Scan

def hash(a: U32, x: U32) -> U32:
  U32.add(U32.mul(a, 31), x)

def most(a: U32, x: U32) -> U32:
  U32.max(a, x)

def small(x: U32) -> Bool:
  U32.is_lt(x, 50)

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

def tot(r: Vec.Vec & U32) -> String:
  (v, n) = r
  one(v) ++ " | " ++ U32.show(n)

def two(r: Vec.Vec & Vec.Vec) -> String:
  (a, b) = r
  one(a) ++ " | " ++ one(b)

def main() -> IO(Unit):
  do IO<Unit>:""")
for r in rows:
    print("    IO.print(%s)" % r)
for w in want:
    print("#|" + w)
