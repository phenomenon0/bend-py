#!/usr/bin/env python3
"""Prints tests/power/fft.bend, this file's fixture, byte for byte.

The oracle is the *definition*, not the algorithm. Bend computes a radix-2
Cooley-Tukey decimation-in-time recursion whose twiddles come off a half-angle
sqrt recurrence; CPython here computes

    X[k] = sum_j x[j] exp(-2 pi i j k / n)

straight, O(n^2), with cmath.exp doing the twiddles. The two share no code and
no factorisation, so a row that matches is a real agreement about what a DFT is
and not two copies of one loop agreeing with themselves.

They meet on a scaled integer. Bend rounds each component with
floor(|v| * 100 + 0.5) and a sign; this file does the identical arithmetic on
its float64 answer. That works only while the two answers sit on the same side
of every rounding boundary, so `q` refuses to emit a value that lands within
MARGIN of one -- the fixture fails loudly at generation rather than quietly on
some other machine.
"""

import cmath
import math

SCALE = 100.0
# Measured, not guessed. Re-emitting this fixture at SCALE=100000 recovers Bend's
# F32 answer to ~1e-5 and puts the worst |F32 - float64| gap over all 320 values
# at 0.00276 scaled units (ramp5 bin 1: 26.5983300 against 26.5983024). MARGIN is
# set ~7x above that. The closest any case here comes to a boundary is 0.0322, so
# the tripwire has 11.7x of room before it fires on this data -- it is there to
# catch a *new* case, not to grade the present one.
MARGIN = 0.02


def dft(xs, sign):
    n = len(xs)
    return [
        sum(xs[j] * cmath.exp(sign * 2j * math.pi * j * k / n) for j in range(n))
        for k in range(n)
    ]


def fwd(xs):
    return dft(xs, -1)


def inv(xs):
    n = len(xs)
    return [v / n for v in dft(xs, +1)]


def conv(a, b):
    return inv([x * y for x, y in zip(fwd(a), fwd(b))])


def q(v):
    """The Bend renderer, in float64: floor(|v| * 100 + 0.5), signed."""
    s = abs(v) * SCALE
    n = math.floor(s + 0.5)
    off = abs(s - math.floor(s) - 0.5)
    if off < MARGIN:
        raise SystemExit(
            f"fft_gen: {v!r} scales to {s!r}, within {MARGIN} of a rounding "
            f"boundary -- F32 and float64 may round it apart. Change the case."
        )
    return f"-{n}" if (v < 0 and n > 0) else f"{n}"


def row(xs):
    return " ".join(f"{q(c.real)} {q(c.imag)}" for c in xs)


def pad(xs, d):
    return xs + [0.0] * ((1 << d) - len(xs))


def lit(xs):
    # Bend has no negative float literal; -1.0 is written F32.neg(1.0)
    return ", ".join(f"F32.neg({-x:.1f})" if x < 0 else f"{x:.1f}" for x in xs)


RAMP = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
IMP = [1.0]
DC = [1.0] * 8
SHIFT = [0.0, 1.0]
BOX = [1.0, 1.0, 1.0, 1.0]
TONE = [1.0, 0.0, -1.0, 0.0, 1.0, 0.0, -1.0, 0.0]

ROWS = [
    # an impulse transforms to a flat one: every twiddle meets a zero
    ("imp3", fwd(pad(IMP, 3))),
    # a constant transforms to n at bin 0 and exact zeros elsewhere
    ("dc3", fwd(pad(DC, 3))),
    # +/-1 at every other sample is the Nyquist-adjacent tone: bins 2 and 6
    ("tone3", fwd(pad(TONE, 3))),
    # the same eight points at three lengths: zero padding interpolates
    ("ramp3", fwd(pad(RAMP, 3))),
    ("ramp4", fwd(pad(RAMP, 4))),
    ("ramp5", fwd(pad(RAMP, 5))),
    # ifft . fft is the identity, and says so at three depths
    ("rt3", inv(fwd(pad(RAMP, 3)))),
    ("rt4", inv(fwd(pad(RAMP, 4)))),
    ("rt5", inv(fwd(pad(RAMP, 5)))),
    # convolving with a shifted impulse rotates; with a box, it runs a sum
    ("sh3", conv(pad(RAMP, 3), pad(SHIFT, 3))),
    ("box4", conv(pad(RAMP, 4), pad(BOX, 4))),
]

BODY = """# The radix-2 transform against the DFT's own definition, computed in CPython at
# O(n^2) with cmath.exp for the twiddles (fft_gen.py prints this file). Bend
# factorises and takes its twiddles off a half-angle sqrt recurrence; the oracle
# does neither, so the two agree only about what a DFT is.
#
# Every component is printed as round(v * 100) with a sign, which is what lets a
# float32 answer and a float64 one be compared exactly. The generator refuses to
# emit a value near a rounding boundary, so the comparison cannot go soft.
#
# The rows carry claims that hold for reasons, not just for values: an impulse
# must transform flat, a constant must give exact zeros away from bin 0, the
# same eight points at three lengths must interpolate rather than change, the
# inverse must undo the forward at every depth, and a convolution with a shifted
# impulse must rotate the signal it convolves.
import Base
import ../../power/fft.bend as F

def qs2(neg: Bool, n: U32) -> String:
  match neg:
    case True{{}}:
      String.append("-", U32.show(n))
    case False{{}}:
      U32.show(n)

def qn(v: F32, +n: U32) -> String:
  qs2(Bool.and(F32.is_lt(v, 0.0), U32.is_lt(0, n)), n)

# floor(|v| * 100 + 0.5) with a sign; -0 prints as 0
def qi(+v: F32) -> String:
  qn(v, F32.to_u32(F32.floor(F32.add(F32.mul(F32.abs(v), 100.0), 0.5))))

def shc(+x: F.C) -> String:
  String.append(qi(F.c.re(x)), String.append(" ", qi(F.c.im(x))))

def shl(xs: List<&2, F.C>, acc: String) -> String:
  match xs:
    case Nil{{}}:
      acc
    case Con{{x, t}}:
      shl(t, String.append(acc, String.append(" ", shc(x))))

def fin(r: F.Sig & List<&2, F.C>) -> String:
  (s, xs) = r
  shl(xs, "")

def show(s: F.Sig) -> String:
  fin(F.to_list(s))

def imp(+d: Nat) -> F.Sig:
  F.of_real([{imp}], d)

def dc(+d: Nat) -> F.Sig:
  F.of_real([{dc}], d)

def tone(+d: Nat) -> F.Sig:
  F.of_real([{tone}], d)

def ramp(+d: Nat) -> F.Sig:
  F.of_real([{ramp}], d)

def shift(+d: Nat) -> F.Sig:
  F.of_real([{shift}], d)

def box(+d: Nat) -> F.Sig:
  F.of_real([{box}], d)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.append("imp3:", show(F.fft(imp(3n)))))
    IO.print(String.append("dc3:", show(F.fft(dc(3n)))))
    IO.print(String.append("tone3:", show(F.fft(tone(3n)))))
    IO.print(String.append("ramp3:", show(F.fft(ramp(3n)))))
    IO.print(String.append("ramp4:", show(F.fft(ramp(4n)))))
    IO.print(String.append("ramp5:", show(F.fft(ramp(5n)))))
    IO.print(String.append("rt3:", show(F.ifft(F.fft(ramp(3n))))))
    IO.print(String.append("rt4:", show(F.ifft(F.fft(ramp(4n))))))
    IO.print(String.append("rt5:", show(F.ifft(F.fft(ramp(5n))))))
    IO.print(String.append("sh3:", show(F.convolve(ramp(3n), shift(3n)))))
    IO.print(String.append("box4:", show(F.convolve(ramp(4n), box(4n)))))
"""


def main():
    src = BODY.format(
        imp=lit(IMP),
        dc=lit(DC),
        tone=lit(TONE),
        ramp=lit(RAMP),
        shift=lit(SHIFT),
        box=lit(BOX),
    )
    out = [src]
    for label, vals in ROWS:
        out.append(f"#|{label}: {row(vals)}\n")
    print("".join(out), end="")


if __name__ == "__main__":
    main()
