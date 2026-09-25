# Exact against Python's Fraction: the same bits at fork depths 0, 3 and 8 over
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
  do IO<Unit>:
    IO.print(at(1, 0n))
    IO.print(at(1, 3n))
    IO.print(at(1, 8n))
    IO.print(at(7, 0n))
    IO.print(at(7, 3n))
    IO.print(at(7, 8n))
    IO.print(at(64, 0n))
    IO.print(at(64, 3n))
    IO.print(at(64, 8n))
    IO.print(at(1000, 0n))
    IO.print(at(1000, 3n))
    IO.print(at(1000, 8n))
    IO.print(at(4096, 0n))
    IO.print(at(4096, 3n))
    IO.print(at(4096, 8n))
    IO.print(at(20480, 0n))
    IO.print(at(20480, 3n))
    IO.print(at(20480, 8n))
    IO.print(edge([1065353216, 864026624]))
    IO.print(edge([1065353217, 864026624]))
    IO.print(edge([1065353216, 864026624, 1]))
    IO.print(edge([1065353215, 855638016]))
    IO.print(edge([2139095039, 2139095039]))
    IO.print(edge([4286578687, 4286578687, 2139095039]))
    IO.print(edge([1, 1, 3]))
    IO.print(edge([1065353216, 3212836864]))
    IO.print(edge([1904214016, 2373976064]))
    IO.print(edge(Nil{}))
#|1588496844 1588496844
#|1588496844 1588496844
#|1588496844 1588496844
#|1588496844 1588496844
#|1588496844 1588496844
#|1588496844 1588496844
#|998453669 970710919
#|998453669 970710919
#|998453669 970710919
#|1016309526 3116597246
#|1016309526 3116597246
#|1016309526 3116597246
#|1024146758 3151963857
#|1024146758 3151963857
#|1024146758 3151963857
#|1004161534 992667879
#|1004161534 992667879
#|1004161534 992667879
#|1065353216
#|1065353218
#|1065353217
#|1065353216
#|2139095040
#|4286578687
#|5
#|0
#|1904214016
#|0
