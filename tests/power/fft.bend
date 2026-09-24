# The radix-2 transform against the DFT's own definition, computed in CPython at
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
    case True{}:
      String.append("-", U32.show(n))
    case False{}:
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
    case Nil{}:
      acc
    case Con{x, t}:
      shl(t, String.append(acc, String.append(" ", shc(x))))

def fin(r: F.Sig & List<&2, F.C>) -> String:
  (s, xs) = r
  shl(xs, "")

def show(s: F.Sig) -> String:
  fin(F.to_list(s))

def imp(+d: Nat) -> F.Sig:
  F.of_real([1.0], d)

def dc(+d: Nat) -> F.Sig:
  F.of_real([1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0], d)

def tone(+d: Nat) -> F.Sig:
  F.of_real([1.0, 0.0, F32.neg(1.0), 0.0, 1.0, 0.0, F32.neg(1.0), 0.0], d)

def ramp(+d: Nat) -> F.Sig:
  F.of_real([1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0], d)

def shift(+d: Nat) -> F.Sig:
  F.of_real([0.0, 1.0], d)

def box(+d: Nat) -> F.Sig:
  F.of_real([1.0, 1.0, 1.0, 1.0], d)

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
#|imp3: 100 0 100 0 100 0 100 0 100 0 100 0 100 0 100 0
#|dc3: 800 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
#|tone3: 0 0 0 0 400 0 0 0 0 0 0 0 400 0 0 0
#|ramp3: 3600 0 -400 966 -400 400 -400 166 -400 0 -400 -166 -400 -400 -400 -966
#|ramp4: 3600 0 -814 -2514 -400 966 338 -748 -400 400 428 -334 -400 166 448 -99 -400 0 448 99 -400 -166 428 334 -400 -400 338 748 -400 -966 -814 2514
#|ramp5: 3600 0 2017 -2660 -814 -2514 -1730 -318 -400 966 779 244 338 -748 -560 -449 -400 400 377 367 428 -334 -223 -445 -400 166 159 408 448 -99 -20 -430 -400 0 -20 430 448 99 159 -408 -400 -166 -223 445 428 334 377 -367 -400 -400 -560 449 338 748 779 -244 -400 -966 -1730 318 -814 2514 2017 2660
#|rt3: 100 0 200 0 300 0 400 0 500 0 600 0 700 0 800 0
#|rt4: 100 0 200 0 300 0 400 0 500 0 600 0 700 0 800 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
#|rt5: 100 0 200 0 300 0 400 0 500 0 600 0 700 0 800 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
#|sh3: 800 0 100 0 200 0 300 0 400 0 500 0 600 0 700 0
#|box4: 100 0 300 0 600 0 1000 0 1400 0 1800 0 2200 0 2600 0 2100 0 1500 0 800 0 0 0 0 0 0 0 0 0 0 0
