#!/usr/bin/env python3
# The oracle for exact.bend: prints the whole fixture. The values are rebuilt
# here from the same integer rule, the true sum is a Fraction, and the printed
# F32 is picked among a handful of candidates by exact distance, ties to the
# even significand -- no accumulator and no rounding code of its own. The same
# answer must come back at every fork depth, which is the point of the file.
import struct
from fractions import Fraction

M = 0xFFFFFFFF


def f32(b):
    return struct.unpack("<f", struct.pack("<I", b))[0]


def b32(x):
    return struct.unpack("<I", struct.pack("<f", x))[0]


def key(i):
    x = (((i + 1) * 2654435761) & M) ^ (i >> 3)
    x = ((x ^ (x >> 15)) * 2246822519) & M
    return x ^ (x >> 13)


def val(i):
    """giants of 2^60..2^75 planted in +/- pairs 32 apart, over small values
    of 2^-40..2^-9 with random signs; every 61st one subnormal"""
    if i % 64 == 32:
        return val(i - 32) ^ 0x80000000
    r = key(i)
    if i % 64 == 0:
        return ((187 + (r & 15)) << 23) | (r >> 9)
    e = 0 if i % 61 == 0 else 87 + (r & 31)
    return ((r >> 31) << 31) | (e << 23) | ((r >> 8) & 0x7FFFFF)


def nearest(r):
    if abs(r) >= 2**128 - 2**103:
        return 0x7F800000 | (0x80000000 if r < 0 else 0)
    g = b32(float(r))
    cands = [b for b in {g - 1, g, g + 1, g ^ 0x80000000}
             if 0 <= b <= M and (b & 0x7F800000) != 0x7F800000]
    best = min(cands, key=lambda b: (abs(Fraction(f32(b)) - r), b & 1))
    return best & 0x7FFFFFFF if r == 0 else best


def exact(xs):
    return nearest(sum(Fraction(f32(b)) for b in xs))


def naive(xs):
    acc = 0.0
    for b in xs:
        acc = f32(b32(acc + f32(b)))
    return b32(acc)


SIZES = [1, 7, 64, 1000, 4096, 20480]
EDGES = [
    [1065353216, 864026624], [1065353217, 864026624], [1065353216, 864026624, 1],
    [1065353215, 855638016], [2139095039, 2139095039],
    [4286578687, 4286578687, 2139095039], [1, 1, 3], [1065353216, 3212836864],
    [1904214016, 2373976064], [],
]
FORKS = [0, 3, 8]


def rows():
    out = []
    for n in SIZES:
        xs = [val(i) for i in range(n)]
        e, nv = exact(xs), naive(xs)
        for _ in FORKS:
            out.append("%d %d" % (e, nv))
    for xs in EDGES:
        out.append(str(exact(xs)))
    return out


BEND = r'''# Exact against Python's Fraction: the same bits at fork depths 0, 3 and 8 over
# one Vec (the naive left fold printed beside each, for contrast), then the
# rounding edges streamed through `add`: ties to even both ways, a tie plus
# one subnormal ulp, a carry out of the significand, overflow to inf, a
# subnormal total, 1 - 1, a borrow through every limb, and the empty sum.
# exact_gen.py prints this file.
import Base
import ../../power/vec.bend as Vec
import ../../power/exact.bend as Ex

def key(+i: U32) -> U32:
  +a = U32.xor(U32.mul(U32.inc(i), 2654435761), U32.shrn(i, 3n))
  +b = U32.mul(U32.xor(a, U32.shrn(a, 15n)), 2246822519)
  U32.xor(b, U32.shrn(b, 13n))

def small(+i: U32) -> U32:
  +r = key(i)
  +e = Bool.pick(U32, U32.is_eq(U32.mod(i, 61), 0), 0, U32.add(87, U32.and(r, 31)))
  U32.or(U32.or(U32.shln(U32.shrn(r, 31n), 31n), U32.shln(e, 23n)),
    U32.and(U32.shrn(r, 8n), 8388607))

def giant(+i: U32) -> U32:
  +r = key(i)
  U32.or(U32.shln(U32.add(187, U32.and(r, 15)), 23n), U32.shrn(r, 9n))

def val.k(k: U32, +i: U32) -> U32:
  match k:
    case 0:
      giant(i)
    case 32:
      U32.xor(giant(U32.sub(i, 32)), 2147483648)
    case _:
      small(i)

def val(+i: U32) -> U32:
  val.k(U32.and(i, 63), i)

def fill(k: Nat, +i: U32, v: Vec.Vec) -> Vec.Vec:
  match k:
    case 0n:
      v
    case 1n++q:
      fill(q, U32.inc(i), Vec.push(v, val(i)))

# the F32 whose bits are x, by exact products (Base has no bitcast back)
def fac(j: Nat, +x: F32) -> F32:
  match j:
    case 0n:
      x
    case 1n++q:
      fac(q, F32.mul(x, x))

def pow2(j: Nat, +k: U32, +neg: Bool, +acc: F32) -> F32:
  match j:
    case 0n:
      acc
    case 1n++q:
      +f = fac(q, Bool.pick(F32, neg, 0.5, 2.0))
      pow2(q, k, neg, Bool.pick(F32, U32.is_eq(U32.and(U32.shrn(k, q), 1), 1), F32.mul(acc, f), acc))

def value(+x: U32) -> F32:
  +o = U32.sub(U32.max(U32.and(U32.shrn(x, 23n), 255), 1), 1)
  +neg = U32.is_lt(o, 149)
  +k = Bool.pick(U32, neg, U32.sub(149, o), U32.sub(o, 149))
  +v = F32.mul(U32.to_f32(Ex.mant(x)), pow2(8n, k, neg, 1.0))
  Bool.pick(F32, U32.is_eq(U32.shrn(x, 31n), 1), F32.neg(v), v)

def naive(k: Nat, +i: U32, +acc: F32) -> F32:
  match k:
    case 0n:
      acc
    case 1n++q:
      naive(q, U32.inc(i), F32.add(acc, value(val(i))))

def row(r: Vec.Vec & U32, +n: U32) -> String:
  (v, e) = r
  U32.show(e) ++ " " ++ U32.show(F32.bits(naive(U32.to_nat(n), 0, 0.0)))

def at(+n: U32, d: Nat) -> String:
  row(Ex.sum(fill(U32.to_nat(n), 0, Vec.new(0)), d), n)

def edge(xs: List<&2, U32>) -> String:
  U32.show(Ex.round(Ex.of_list(xs, Ex.zero())))

def main() -> IO(Unit):
  do IO<Unit>:'''

if __name__ == "__main__":
    print(BEND)
    for n in SIZES:
        for d in FORKS:
            print("    IO.print(at(%d, %dn))" % (n, d))
    for xs in EDGES:
        print("    IO.print(edge([%s]))" % ", ".join(map(str, xs)) if xs else
              "    IO.print(edge(Nil{}))")
    for r in rows():
        print("#|" + r)
