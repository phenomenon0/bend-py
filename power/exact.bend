# Exact: the sum of F32s with no rounding until the end, so its bits do not
# depend on the order, the split, the thread count or the lane.
#
# Every finite F32 is an integer multiple of 2^-149 below 2^128. A 320-bit
# two's-complement integer (ten U32 limbs, limb j worth 2^(32j - 149)) holds
# any one of them exactly and the exact sum of up to 2^32 of them. Integer
# addition is associative, so a fork tree joins leaves with one 320-bit add,
# and `round` gives the unique nearest F32 to the true sum (ties to even,
# overflow to inf), whatever the tree looked like. This is Kulisch's
# accumulator (the "exact dot product" of the 1970s-80s), in the shape the
# power library wants: `Acc` is kind Data, a leaf carries its limbs as ten
# words (no record per element). `sum` forks one Vec of F32 bit patterns with
# Array.fork (two handles to one block in O(1), reads only, no copy); `sum_bytes`
# forks Base's Bytes() -- a float32 file as File.read_buf hands it back.
#
# Inputs are finite: an inf or NaN is read as a large finite value (E = 255 is
# not special-cased). demos/monoids/kulisch.bend is the showcase this was lifted
# from; tests/power/exact.bend holds it to Python's Fraction.
import Base
import ./vec.bend as Vec

def mant(+x: U32) -> U32:
  U32.or(U32.and(x, 8388607), U32.shln(Bool.to_u32(U32.is_ne(U32.and(x, 2139095040), 0)), 23n))

type Acc is Data:
  Acc{l0: U32, l1: U32, l2: U32, l3: U32, l4: U32, l5: U32, l6: U32, l7: U32, l8: U32, l9: U32}

def zero() -> Acc:
  Acc{0, 0, 0, 0, 0, 0, 0, 0, 0, 0}

# the carry out of a + b + c (c is 0 or 1)
def carry(+a: U32, +b: U32, +c: U32) -> U32:
  +s = U32.add(a, b)
  U32.or(Bool.to_u32(U32.is_lt(s, a)), Bool.to_u32(U32.is_lt(U32.add(s, c), s)))

# what limb j receives of a value whose low word goes to limb k
def put(+k: U32, j: U32, +lo: U32, +hi: U32) -> U32:
  +j2 = j
  U32.or(U32.mul(Bool.to_u32(U32.is_eq(k, j2)), lo),
    U32.mul(Bool.to_u32(U32.is_eq(U32.inc(k), j2)), hi))

# the join: a 320-bit add, exact, so the tree's shape cannot show
def join(a: Acc, b: Acc) -> Acc:
  match a b:
    case Acc{+a0, +a1, +a2, +a3, +a4, +a5, +a6, +a7, +a8, a9} Acc{+b0, +b1, +b2, +b3, +b4, +b5, +b6, +b7, +b8, b9}:
      +c0 = carry(a0, b0, 0)
      +c1 = carry(a1, b1, c0)
      +c2 = carry(a2, b2, c1)
      +c3 = carry(a3, b3, c2)
      +c4 = carry(a4, b4, c3)
      +c5 = carry(a5, b5, c4)
      +c6 = carry(a6, b6, c5)
      +c7 = carry(a7, b7, c6)
      +c8 = carry(a8, b8, c7)
      Acc{U32.add(a0, b0), U32.add(U32.add(a1, b1), c0), U32.add(U32.add(a2, b2), c1),
        U32.add(U32.add(a3, b3), c2), U32.add(U32.add(a4, b4), c3),
        U32.add(U32.add(a5, b5), c4), U32.add(U32.add(a6, b6), c5),
        U32.add(U32.add(a7, b7), c6), U32.add(U32.add(a8, b8), c7),
        U32.add(U32.add(a9, b9), c8)}

def limb(j: U32, l0: U32, l1: U32, l2: U32, l3: U32, l4: U32, l5: U32, l6: U32,
  l7: U32, l8: U32, l9: U32) -> U32:
  match j:
    case 0:
      l0
    case 1:
      l1
    case 2:
      l2
    case 3:
      l3
    case 4:
      l4
    case 5:
      l5
    case 6:
      l6
    case 7:
      l7
    case 8:
      l8
    case 9:
      l9
    case _:
      0

def at(+a: Acc, j: U32) -> U32:
  match a:
    case Acc{l0, l1, l2, l3, l4, l5, l6, l7, l8, l9}:
      limb(j, l0, l1, l2, l3, l4, l5, l6, l7, l8, l9)

# -a, for the one negative total: once, here, never per element
def negate(a: Acc) -> Acc:
  match a:
    case Acc{l0, l1, l2, l3, l4, l5, l6, l7, l8, l9}:
      join(Acc{1, 0, 0, 0, 0, 0, 0, 0, 0, 0}, Acc{U32.not(l0), U32.not(l1),
        U32.not(l2), U32.not(l3), U32.not(l4), U32.not(l5), U32.not(l6),
        U32.not(l7), U32.not(l8), U32.not(l9)})

def ge(+x: U32, +y: U32) -> U32:
  Bool.to_u32(U32.is_ge(x, y))

def nz(+x: U32) -> U32:
  Bool.to_u32(U32.is_ne(x, 0))

# the index of the top set bit (0 for 0 and 1): sum over k of [x >= 2^k]
def fls(k: Nat, +x: U32, +b: U32) -> U32:
  match k:
    case 0n:
      b
    case 1n++q:
      fls(q, x, U32.add(b, ge(x, U32.shln(2, q))))

# the top set bit of the whole 320 bits
def top(a: Acc) -> U32:
  match a:
    case Acc{+l0, +l1, +l2, +l3, +l4, +l5, +l6, +l7, +l8, +l9}:
      +s9 = l9
      +s8 = U32.or(l8, s9)
      +s7 = U32.or(l7, s8)
      +s6 = U32.or(l6, s7)
      +s5 = U32.or(l5, s6)
      +s4 = U32.or(l4, s5)
      +s3 = U32.or(l3, s4)
      +s2 = U32.or(l2, s3)
      +s1 = U32.or(l1, s2)
      +t = U32.add(U32.add(U32.add(nz(s1), nz(s2)), U32.add(nz(s3), nz(s4))),
        U32.add(U32.add(U32.add(nz(s5), nz(s6)), U32.add(nz(s7), nz(s8))), nz(s9)))
      U32.add(U32.shln(t, 5n), fls(31n, limb(t, l0, l1, l2, l3, l4, l5, l6, l7, l8, l9), 0))

# the 32 bits from bit p up
def window(+a: Acc, +p: U32) -> U32:
  +k = U32.shrn(p, 5n)
  +r = U32.and(p, 31)
  U32.or(U32.shrn(at(a, k), U32.to_nat(r)), U32.shln(at(a, U32.inc(k)), U32.to_nat(U32.sub(32, r))))

# 1 if any bit below bit p is set
def sticky(j: Nat, +a: Acc, +p: U32, +acc: U32) -> U32:
  match j:
    case 0n:
      nz(acc)
    case 1n++q:
      +w = at(a, U32.from_nat(q))
      +k = U32.shrn(p, 5n)
      +part = U32.and(w, U32.sub(U32.shln(1, U32.to_nat(U32.and(p, 31))), 1))
      +mine = Bool.pick(U32, U32.is_lt(U32.from_nat(q), k), w,
        Bool.pick(U32, U32.is_eq(U32.from_nat(q), k), part, 0))
      sticky(q, a, p, U32.or(acc, mine))

# round-to-nearest-even of a magnitude whose top bit is h >= 24
def wide(+m: Acc, +h: U32) -> U32:
  +s = U32.sub(h, 23)
  +sig = U32.and(window(m, s), 16777215)
  +g = U32.and(window(m, U32.sub(s, 1)), 1)
  +up = U32.and(g, U32.or(sticky(10n, m, U32.sub(s, 1), 0), U32.and(sig, 1)))
  # (E-1) << 23 plus the 24-bit significand: its hidden bit makes E, and a
  # round-up that carries out of the significand bumps E for free
  U32.min(U32.add(U32.add(U32.shln(s, 23n), sig), up), 2139095040)

def mag(+m: Acc) -> U32:
  +h = top(m)
  # under 2^24 the integer IS the bit pattern: subnormal below 2^23, E = 1 above
  Bool.pick(U32, U32.is_lt(h, 24), at(m, 0), wide(m, h))

# the correctly rounded F32 of the exact sum, as bits
def round(+a: Acc) -> U32:
  +neg = U32.shrn(at(a, 9), 31n)
  U32.or(U32.shln(neg, 31n), mag(Bool.pick(Acc, U32.is_eq(neg, 1), negate(a), a)))


# -- one value at a time ----------------------------------------------------------

# the limbs of acc, plus the F32 whose bits are x: the whole per-element step
def add.limbs(+x: U32, +l0: U32, +l1: U32, +l2: U32, +l3: U32, +l4: U32, +l5: U32,
  +l6: U32, +l7: U32, +l8: U32, +l9: U32) -> Acc:
  +sm = U32.sub(0, U32.shrn(x, 31n))
  +o = U32.sub(U32.max(U32.and(U32.shrn(x, 23n), 255), 1), 1)
  +k = U32.shrn(o, 5n)
  +m = mant(x)
  +lo = U32.shln(m, U32.to_nat(U32.and(o, 31)))
  +hi = U32.shrn(m, U32.to_nat(U32.sub(32, U32.and(o, 31))))
  +c = U32.and(sm, 1)
  +o0 = U32.xor(put(k, 0, lo, hi), sm)
  +c0 = carry(l0, o0, c)
  +o1 = U32.xor(put(k, 1, lo, hi), sm)
  +c1 = carry(l1, o1, c0)
  +o2 = U32.xor(put(k, 2, lo, hi), sm)
  +c2 = carry(l2, o2, c1)
  +o3 = U32.xor(put(k, 3, lo, hi), sm)
  +c3 = carry(l3, o3, c2)
  +o4 = U32.xor(put(k, 4, lo, hi), sm)
  +c4 = carry(l4, o4, c3)
  +o5 = U32.xor(put(k, 5, lo, hi), sm)
  +c5 = carry(l5, o5, c4)
  +o6 = U32.xor(put(k, 6, lo, hi), sm)
  +c6 = carry(l6, o6, c5)
  +o7 = U32.xor(put(k, 7, lo, hi), sm)
  +c7 = carry(l7, o7, c6)
  +o8 = U32.xor(put(k, 8, lo, hi), sm)
  +c8 = carry(l8, o8, c7)
  +o9 = U32.xor(put(k, 9, lo, hi), sm)
  Acc{U32.add(U32.add(l0, o0), c),
    U32.add(U32.add(l1, o1), c0),
    U32.add(U32.add(l2, o2), c1),
    U32.add(U32.add(l3, o3), c2),
    U32.add(U32.add(l4, o4), c3),
    U32.add(U32.add(l5, o5), c4),
    U32.add(U32.add(l6, o6), c5),
    U32.add(U32.add(l7, o7), c6),
    U32.add(U32.add(l8, o8), c7),
    U32.add(U32.add(l9, o9), c8)}

# acc plus the F32 whose bits are x: for a caller that streams its values
def add(a: Acc, +x: U32) -> Acc:
  match a:
    case Acc{l0, l1, l2, l3, l4, l5, l6, l7, l8, l9}:
      add.limbs(x, l0, l1, l2, l3, l4, l5, l6, l7, l8, l9)

def of_list(xs: List<&2, U32>, a: Acc) -> Acc:
  match xs:
    case Nil{}:
      a
    case Con{x, t}:
      of_list(t, add(a, x))

# -- the fork over a Vec -------------------------------------------------------------

# k cells from i; r is the read of cell i (the array and its word), so the loop
# threads the array without a record per step and keeps the limbs as words
def leaf(k: Nat, +i: U32, r: Array<U32> & U32, +l0: U32, +l1: U32, +l2: U32,
  +l3: U32, +l4: U32, +l5: U32, +l6: U32, +l7: U32, +l8: U32, +l9: U32) -> Array<U32> & Acc:
  match k:
    case 0n:
      (arr, _) = r
      (arr, Acc{l0, l1, l2, l3, l4, l5, l6, l7, l8, l9})
    case 1n++q:
      (arr, +x) = r
      +sm = U32.sub(0, U32.shrn(x, 31n))
      +o = U32.sub(U32.max(U32.and(U32.shrn(x, 23n), 255), 1), 1)
      +k = U32.shrn(o, 5n)
      +m = mant(x)
      +lo = U32.shln(m, U32.to_nat(U32.and(o, 31)))
      +hi = U32.shrn(m, U32.to_nat(U32.sub(32, U32.and(o, 31))))
      +c = U32.and(sm, 1)
      +o0 = U32.xor(put(k, 0, lo, hi), sm)
      +c0 = carry(l0, o0, c)
      +o1 = U32.xor(put(k, 1, lo, hi), sm)
      +c1 = carry(l1, o1, c0)
      +o2 = U32.xor(put(k, 2, lo, hi), sm)
      +c2 = carry(l2, o2, c1)
      +o3 = U32.xor(put(k, 3, lo, hi), sm)
      +c3 = carry(l3, o3, c2)
      +o4 = U32.xor(put(k, 4, lo, hi), sm)
      +c4 = carry(l4, o4, c3)
      +o5 = U32.xor(put(k, 5, lo, hi), sm)
      +c5 = carry(l5, o5, c4)
      +o6 = U32.xor(put(k, 6, lo, hi), sm)
      +c6 = carry(l6, o6, c5)
      +o7 = U32.xor(put(k, 7, lo, hi), sm)
      +c7 = carry(l7, o7, c6)
      +o8 = U32.xor(put(k, 8, lo, hi), sm)
      +c8 = carry(l8, o8, c7)
      +o9 = U32.xor(put(k, 9, lo, hi), sm)
      leaf(q, U32.inc(i), Array.get(U32, arr, U32.inc(i)),
        U32.add(U32.add(l0, o0), c),
        U32.add(U32.add(l1, o1), c0),
        U32.add(U32.add(l2, o2), c1),
        U32.add(U32.add(l3, o3), c2),
        U32.add(U32.add(l4, o4), c3),
        U32.add(U32.add(l5, o5), c4),
        U32.add(U32.add(l6, o6), c5),
        U32.add(U32.add(l7, o7), c6),
        U32.add(U32.add(l8, o8), c7),
        U32.add(U32.add(l9, o9), c8))

def tree.join(l: Array<U32> & Acc, r: Array<U32> & Acc) -> Array<U32> & Acc:
  (a, x) = l
  (b, y) = r
  (Array.join(U32, a, b), join(x, y))

# cells lo .. lo+n-1 of one array, 2^d leaves; hs is two handles to it
def tree(d: Nat, hs: Array<U32> & Array<U32>, +lo: U32, +n: U32) -> Array<U32> & Acc:
  match d:
    case 0n:
      (a, b) = hs
      leaf(U32.to_nat(n), lo, Array.get(U32, Array.join(U32, a, b), lo), 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0)
    case 1n++p:
      (a, b) = hs
      +h = U32.shr(n)
      l r = tree(p, Array.fork(U32, a), lo, h) tree(p, Array.fork(U32, b), U32.add(lo, h), U32.sub(n, h))
      tree.join(l, r)

def sum.fin(n: U32, d: Nat, r: Array<U32> & Acc) -> Vec.Vec & U32:
  (arr, a) = r
  (Vec.Vec{n, d, arr}, round(a))

# the exact sum of the F32s whose bits fill v, correctly rounded, as bits;
# 2^fork leaves, and the Vec comes back
def sum(v: Vec.Vec, fork: Nat) -> Vec.Vec & U32:
  match v:
    case Vec.Vec{+n, d, arr}:
      sum.fin(n, d, tree(fork, Array.fork(U32, arr), 0, n))

# -- the fork over Base's Bytes() ---------------------------------------------------

# k words from word i of b (little-endian F32 bits, four bytes apiece)
def words(k: Nat, +b: Bytes(), +i: U32, +l0: U32, +l1: U32, +l2: U32, +l3: U32,
  +l4: U32, +l5: U32, +l6: U32, +l7: U32, +l8: U32, +l9: U32) -> Acc:
  match k:
    case 0n:
      Acc{l0, l1, l2, l3, l4, l5, l6, l7, l8, l9}
    case 1n++q:
      +x = Bytes.word_le(b, U32.to_nat(U32.shln(i, 2n)))
      +sm = U32.sub(0, U32.shrn(x, 31n))
      +o = U32.sub(U32.max(U32.and(U32.shrn(x, 23n), 255), 1), 1)
      +k = U32.shrn(o, 5n)
      +m = mant(x)
      +lo = U32.shln(m, U32.to_nat(U32.and(o, 31)))
      +hi = U32.shrn(m, U32.to_nat(U32.sub(32, U32.and(o, 31))))
      +c = U32.and(sm, 1)
      +o0 = U32.xor(put(k, 0, lo, hi), sm)
      +c0 = carry(l0, o0, c)
      +o1 = U32.xor(put(k, 1, lo, hi), sm)
      +c1 = carry(l1, o1, c0)
      +o2 = U32.xor(put(k, 2, lo, hi), sm)
      +c2 = carry(l2, o2, c1)
      +o3 = U32.xor(put(k, 3, lo, hi), sm)
      +c3 = carry(l3, o3, c2)
      +o4 = U32.xor(put(k, 4, lo, hi), sm)
      +c4 = carry(l4, o4, c3)
      +o5 = U32.xor(put(k, 5, lo, hi), sm)
      +c5 = carry(l5, o5, c4)
      +o6 = U32.xor(put(k, 6, lo, hi), sm)
      +c6 = carry(l6, o6, c5)
      +o7 = U32.xor(put(k, 7, lo, hi), sm)
      +c7 = carry(l7, o7, c6)
      +o8 = U32.xor(put(k, 8, lo, hi), sm)
      +c8 = carry(l8, o8, c7)
      +o9 = U32.xor(put(k, 9, lo, hi), sm)
      words(q, b, U32.inc(i),
        U32.add(U32.add(l0, o0), c),
        U32.add(U32.add(l1, o1), c0),
        U32.add(U32.add(l2, o2), c1),
        U32.add(U32.add(l3, o3), c2),
        U32.add(U32.add(l4, o4), c3),
        U32.add(U32.add(l5, o5), c4),
        U32.add(U32.add(l6, o6), c5),
        U32.add(U32.add(l7, o7), c6),
        U32.add(U32.add(l8, o8), c7),
        U32.add(U32.add(l9, o9), c8))

def words.tree(d: Nat, +b: Bytes(), +lo: U32, +n: U32) -> Acc:
  match d:
    case 0n:
      words(U32.to_nat(n), b, lo, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    case 1n++p:
      +h = U32.shr(n)
      l r = words.tree(p, b, lo, h) words.tree(p, b, U32.add(lo, h), U32.sub(n, h))
      join(l, r)

# the exact sum of a buffer of little-endian F32s (a float32 file as read),
# correctly rounded, as bits; 2^d leaves share the buffer. A trailing partial
# word is not a float and is left out.
def sum_bytes(+b: Bytes(), d: Nat) -> U32:
  round(words.tree(d, b, 0, U32.shrn(U32.from_nat(Bytes.len(b)), 2n)))
