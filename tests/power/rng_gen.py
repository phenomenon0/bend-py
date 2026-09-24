#!/usr/bin/env python3
# The oracle for rng.bend: prints the whole fixture. Threefry2x32-20 is written
# here from the Random123 paper, independently of power/rng.bend, and held to
# Random123's three known-answer vectors before any row is emitted. run.sh
# diffs this against the checked-in file.
import math
import random

M = 0xFFFFFFFF
ROT = [13, 15, 26, 6, 17, 29, 16, 24]


def rotl(x, r):
    return ((x << r) | (x >> (32 - r))) & M


def block(k0, k1, c0, c1):
    ks = [k0, k1, k0 ^ k1 ^ 0x1BD11BDA]
    a, b = (c0 + ks[0]) & M, (c1 + ks[1]) & M
    for r in range(20):
        a = (a + b) & M
        b = rotl(b, ROT[r % 8]) ^ a
        if r % 4 == 3:
            n = r // 4 + 1
            a = (a + ks[n % 3]) & M
            b = (b + ks[(n + 1) % 3] + n) & M
    return a, b


KAT = [  # Random123 kat_vectors: key, counter, output
    ((0, 0), (0, 0), (0x6B200159, 0x99BA4EFE)),
    ((M, M), (M, M), (0x1CB996FC, 0xBB002BE7)),
    ((0x13198A2E, 0x03707344), (0x243F6A88, 0x85A308D3), (0xC4923A9C, 0x483DF7A0)),
]
for k, c, want in KAT:
    assert block(*k, *c) == want, (k, c)


def u32(seed, stream, step):
    return block(seed, stream, step, 0)[0]


def hit(seed, i):  # a quarter-circle dart from two streams of one seed
    x, y = u32(seed, 0, i) >> 17, u32(seed, 1, i) >> 17
    return 1 if x * x + y * y < (1 << 30) else 0


def normal(seed, stream, step):
    """Box-Muller on both words of one block, written from the definition and
    not from power/rng.bend: the cosine half only, so the draw does not depend
    on the parity of step."""
    a, b = block(seed, stream, step, 0)
    return math.sqrt(-2 * math.log((a + 0.5) / 2**32)) * math.cos(
        2 * math.pi * (b / 2**32)
    )


def quant(z):  # z + 8 in millionths; see q() in the fixture for why
    return int((z + 8.0) * 1000000 + 0.5)


def insig(seed, i):  # one draw of stream 2, inside one standard deviation
    return 1 if abs(normal(seed, 2, i)) < 1.0 else 0


rng = random.Random(20260919)
draws = [
    (rng.getrandbits(32), rng.getrandbits(32), rng.getrandbits(32)) for _ in range(12)
]
draws += [(0, 0, 0), (M, M, M), (1, 0, 0), (0, 1, 0), (0, 0, 1)]
DEPTH = 12
SIG = 12

rows, want = [], []
for k, c, _ in KAT:
    rows.append("pair(Rng.block(%d, %d, %d, %d))" % (*k, *c))
    want.append("%d %d" % block(*k, *c))
for s, t, i in draws:
    rows.append("U32.show(Rng.u32(%d, %d, %d))" % (s, t, i))
    want.append(str(u32(s, t, i)))
for s, t, i in draws[:6]:  # the f32 draw scaled back is exactly the top 24 bits
    rows.append(
        "U32.show(F32.to_u32(F32.mul(Rng.f32(%d, %d, %d), 16777216.0)))" % (s, t, i)
    )
    want.append(str(u32(s, t, i) >> 8))
for s, t, i in draws[:6]:
    rows.append("U32.show(Rng.below(%d, %d, %d, 1000))" % (s, t, i))
    want.append(str(u32(s, t, i) % 1000))
rows.append("U32.show(darts(%dn, 7, 0))" % DEPTH)
want.append(str(sum(hit(7, i) for i in range(1 << DEPTH))))
for s, t, i in draws[:6]:
    rows.append("U32.show(q(Rng.normal(%d, %d, %d)))" % (s, t, i))
    want.append(str(quant(normal(s, t, i))))
# the six rows above pin the formula; this one pins that the formula is a
# normal. 2^12 draws inside one standard deviation should be 0.6827 * 4096 =
# 2796 and the binomial standard error is 30, so a count that is not near it is
# a bug and not a seed.
rows.append("U32.show(sigma(%dn, 5, 0))" % SIG)
want.append(str(sum(insig(5, i) for i in range(1 << SIG))))

print(
    """# Threefry2x32-20 against Random123's known-answer vectors and a CPython
# oracle (rng_gen.py prints this file). darts forks 2^%d draws addressed by
# counter alone: the count is the same under any --threads, which is the point
# of a counter RNG.
import Base
import ../../power/rng.bend as Rng

def pair(xy: U32 & U32) -> String:
  (x, y) = xy
  U32.show(x) ++ " " ++ U32.show(y)

def bit(inside: Bool) -> U32:
  match inside:
    case True{}:
      1
    case False{}:
      0

def dart(+seed: U32, +i: U32) -> U32:
  +x = U32.shrn(Rng.u32(seed, 0, i), 17n)
  +y = U32.shrn(Rng.u32(seed, 1, i), 17n)
  bit(U32.is_lt(U32.add(U32.mul(x, x), U32.mul(y, y)), 1073741824))

def darts(d: Nat, +seed: U32, +i: U32) -> U32:
  match d:
    case 0n:
      dart(seed, i)
    case 1n++p:
      a b = darts(p, seed, i) darts(p, seed, U32.add(i, U32.shln(1, p)))
      U32.add(a, b)

# z + 8 in millionths. The four lanes hold the same double, but printing it raw
# would pin sixteen digits of whichever libm the lane links, and only six of
# them are the answer. The + 8 is free: |z| < 6.8 by construction, see norm.of.
def q(z: F64) -> U32:
  F64.to_u32(F64.add(F64.mul(F64.add(z, 8.0d), 1000000.0d), 0.5d))

def insig(+seed: U32, +i: U32) -> U32:
  bit(F64.is_lt(F64.abs(Rng.normal(seed, 2, i)), 1.0d))

def sigma(d: Nat, +seed: U32, +i: U32) -> U32:
  match d:
    case 0n:
      insig(seed, i)
    case 1n++p:
      a b = sigma(p, seed, i) sigma(p, seed, U32.add(i, U32.shln(1, p)))
      U32.add(a, b)

def main() -> IO(Unit):
  do IO<Unit>:"""
    % DEPTH
)
for r in rows:
    print("    IO.print(%s)" % r)
for w in want:
    print("#|" + w)
