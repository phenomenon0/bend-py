# One forward transform of 65,536 real points, checksummed on the raw IEEE-754
# bits of every output component. The twin is the same recursion in C: same
# half-angle twiddle recurrence, same per-combine table, same order of
# operations -- so a matching checksum is a claim about bit-for-bit agreement,
# not about being close enough.
import Base
import ../../../power/fft.bend as F

def key(+i: U32) -> U32:
  U32.xor(U32.mul(U32.inc(i), 2654435761), U32.shrn(i, 3n))

# (h & 0xFFFF) / 65536 is exact in binary32: the numerator is under 2^16 and the
# denominator is a power of two, so Bend and C start from identical inputs
def val(+i: U32) -> F32:
  F32.div(U32.to_f32(U32.and(key(i), 65535)), 65536.0)

def fill(fuel: Nat, +i: U32, s: F.Sig) -> F.Sig:
  match fuel:
    case 0n:
      s
    case 1n++p:
      fill(p, U32.inc(i), F.put(s, i, F.C{val(i), 0.0}))

def fold1(acc: U32, +x: F.C) -> U32:
  U32.add(U32.mul(U32.add(U32.mul(acc, 31), F32.bits(F.c.re(x))), 31), F32.bits(F.c.im(x)))

def acc1(acc: U32, r: F.Sig & F.C) -> F.Sig & U32:
  (s, x) = r
  (s, fold1(acc, x))

def step(+i: U32, sa: F.Sig & U32) -> F.Sig & U32:
  (s, acc) = sa
  acc1(acc, F.at(s, i))

def walk(fuel: Nat, +i: U32, sa: F.Sig & U32) -> F.Sig & U32:
  match fuel:
    case 0n:
      sa
    case 1n++p:
      walk(p, U32.inc(i), step(i, sa))

def snd(sa: F.Sig & U32) -> U32:
  (s, acc) = sa
  acc

def main() -> U32:
  snd(walk(1048576n, 0, (F.fft(fill(1048576n, 0, F.new(20n))), 0)))
