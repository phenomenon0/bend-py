# Threefry2x32-20 against Random123's known-answer vectors and a CPython
# oracle (rng_gen.py prints this file). darts forks 2^12 draws addressed by
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

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(pair(Rng.block(0, 0, 0, 0)))
    IO.print(pair(Rng.block(4294967295, 4294967295, 4294967295, 4294967295)))
    IO.print(pair(Rng.block(320440878, 57701188, 608135816, 2242054355)))
    IO.print(U32.show(Rng.u32(2720817508, 422443259, 3463391847)))
    IO.print(U32.show(Rng.u32(1507332086, 598775174, 3385754322)))
    IO.print(U32.show(Rng.u32(2812640468, 3214643307, 4246283621)))
    IO.print(U32.show(Rng.u32(3501566526, 3291293899, 1454131517)))
    IO.print(U32.show(Rng.u32(1727549882, 3093311510, 2406846198)))
    IO.print(U32.show(Rng.u32(1203505495, 238119131, 3760058264)))
    IO.print(U32.show(Rng.u32(268753648, 1838328610, 399258933)))
    IO.print(U32.show(Rng.u32(2310413939, 96524362, 4037425305)))
    IO.print(U32.show(Rng.u32(1365913607, 2529530074, 4096465562)))
    IO.print(U32.show(Rng.u32(2948112831, 100852846, 1646498990)))
    IO.print(U32.show(Rng.u32(16297475, 155920079, 2895420981)))
    IO.print(U32.show(Rng.u32(2828334351, 2147176926, 3670668556)))
    IO.print(U32.show(Rng.u32(0, 0, 0)))
    IO.print(U32.show(Rng.u32(4294967295, 4294967295, 4294967295)))
    IO.print(U32.show(Rng.u32(1, 0, 0)))
    IO.print(U32.show(Rng.u32(0, 1, 0)))
    IO.print(U32.show(Rng.u32(0, 0, 1)))
    IO.print(U32.show(F32.to_u32(F32.mul(Rng.f32(2720817508, 422443259, 3463391847), 16777216.0))))
    IO.print(U32.show(F32.to_u32(F32.mul(Rng.f32(1507332086, 598775174, 3385754322), 16777216.0))))
    IO.print(U32.show(F32.to_u32(F32.mul(Rng.f32(2812640468, 3214643307, 4246283621), 16777216.0))))
    IO.print(U32.show(F32.to_u32(F32.mul(Rng.f32(3501566526, 3291293899, 1454131517), 16777216.0))))
    IO.print(U32.show(F32.to_u32(F32.mul(Rng.f32(1727549882, 3093311510, 2406846198), 16777216.0))))
    IO.print(U32.show(F32.to_u32(F32.mul(Rng.f32(1203505495, 238119131, 3760058264), 16777216.0))))
    IO.print(U32.show(Rng.below(2720817508, 422443259, 3463391847, 1000)))
    IO.print(U32.show(Rng.below(1507332086, 598775174, 3385754322, 1000)))
    IO.print(U32.show(Rng.below(2812640468, 3214643307, 4246283621, 1000)))
    IO.print(U32.show(Rng.below(3501566526, 3291293899, 1454131517, 1000)))
    IO.print(U32.show(Rng.below(1727549882, 3093311510, 2406846198, 1000)))
    IO.print(U32.show(Rng.below(1203505495, 238119131, 3760058264, 1000)))
    IO.print(U32.show(darts(12n, 7, 0)))
#|1797259609 2579123966
#|481924860 3137350631
#|3297917596 1212020640
#|3903524943
#|2255031856
#|2725932544
#|3116552998
#|509643080
#|1889996376
#|1087189658
#|472803142
#|3180894815
#|2655374930
#|548983238
#|1112354789
#|1797259609
#|179615050
#|3023415290
#|507451445
#|1351547692
#|15248144
#|8808718
#|10648174
#|12174035
#|1990793
#|7382798
#|943
#|856
#|544
#|998
#|80
#|376
#|3221
