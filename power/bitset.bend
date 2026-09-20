# Bitset: 32 flags per U32 cell over Base's Array, a fixed 32 * 2^depth bits.
# One owner: a write is in place, a read hands the set back.
#
# Written for the compiled lanes: a bit is one shift and one mask on a native
# cell; the whole-set operations (and / or / xor / andnot, count) are one index
# loop in place, the cell operation a template parameter so each instance is
# compiled with its operator inline; popcount is the SWAR ladder, five native
# rows, no loop.
import Base

type Bitset is Type:
  Bitset{depth: Nat, arr: Array<U32>}

def new(+d: Nat) -> Bitset:
  Bitset{d, [0 : U32^d]}

# the capacity in bits
def size(b: Bitset) -> Bitset & U32:
  match b:
    case Bitset{+d, arr}:
      (Bitset{d, arr}, U32.shln(32, d))

def mask(+i: U32) -> U32:
  U32.shln(1, U32.to_nat(U32.and(i, 31)))

# edit: one cell rewritten by f(cell, mask). The index wraps at the capacity.
def edit.put(~f: U32 -> U32 -> U32, +c: U32, +m: U32, r: Array<U32> & U32) -> Array<U32>:
  (arr, w) = r
  Array.set(U32, arr, c, f(w, m))

def edit(~f: U32 -> U32 -> U32, b: Bitset, +i: U32) -> Bitset:
  match b:
    case Bitset{d, arr}:
      Bitset{d, edit.put(~f, U32.shrn(i, 5n), mask(i), Array.get(U32, arr, U32.shrn(i, 5n)))}

def andnot.w(w: U32, m: U32) -> U32:
  U32.and(w, U32.not(m))

def set(b: Bitset, +i: U32) -> Bitset:
  edit(~U32.or, b, i)

def clear(b: Bitset, +i: U32) -> Bitset:
  edit(~andnot.w, b, i)

def flip(b: Bitset, +i: U32) -> Bitset:
  edit(~U32.xor, b, i)

def test.fin(d: Nat, +m: U32, r: Array<U32> & U32) -> Bitset & Bool:
  (arr, w) = r
  (Bitset{d, arr}, U32.is_ne(U32.and(w, m), 0))

def test(b: Bitset, +i: U32) -> Bitset & Bool:
  match b:
    case Bitset{d, arr}:
      test.fin(d, mask(i), Array.get(U32, arr, U32.shrn(i, 5n)))

# zip: one in-place index loop over the cells. Not a fork tree, and measured: a
# match on ANode copies both halves and ANode{l, r} copies them back, so every
# fork level is two passes over the set; at 2^22 cells twelve levels ran 50x
# slower than this loop on one thread and did not scale on sixteen. The two sets
# must be one size:
# ponytail: where the sizes disagree the left side's stands and the right wraps;
# a checked door (depths compared once, a Maybe out) when a caller can hold
# mixed sizes.
def zip.put(~f: U32 -> U32 -> U32, +j: U32, ra: Array<U32> & U32, y: U32) -> Array<U32>:
  (a, x) = ra
  Array.set(U32, a, j, f(x, y))

def zip.got(~f: U32 -> U32 -> U32, +j: U32, a: Array<U32>, rb: Array<U32> & U32) -> Array<U32> & Array<U32>:
  (b, y) = rb
  (zip.put(~f, j, Array.get(U32, a, j), y), b)

def zip.step(~f: U32 -> U32 -> U32, +j: U32, ab: Array<U32> & Array<U32>) -> Array<U32> & Array<U32>:
  (a, b) = ab
  zip.got(~f, j, a, Array.get(U32, b, j))

def zip.loop(~f: U32 -> U32 -> U32, i: Nat, ab: Array<U32> & Array<U32>) -> Array<U32> & Array<U32>:
  match i:
    case 0n:
      ab
    case 1n++p:
      zip.loop(~f, p, zip.step(~f, U32.from_nat(p), ab))

def zip.left(ab: Array<U32> & Array<U32>) -> Array<U32>:
  (a, b) = ab
  a

def zip(~f: U32 -> U32 -> U32, +d: Nat, a: Array<U32>, b: Array<U32>) -> Array<U32>:
  zip.left(zip.loop(~f, Nat.pow(2n, d), (a, b)))

def and(a: Bitset, b: Bitset) -> Bitset:
  match a b:
    case Bitset{+d, xs} Bitset{e, ys}:
      Bitset{d, zip(~U32.and, d, xs, ys)}

def or(a: Bitset, b: Bitset) -> Bitset:
  match a b:
    case Bitset{+d, xs} Bitset{e, ys}:
      Bitset{d, zip(~U32.or, d, xs, ys)}

def xor(a: Bitset, b: Bitset) -> Bitset:
  match a b:
    case Bitset{+d, xs} Bitset{e, ys}:
      Bitset{d, zip(~U32.xor, d, xs, ys)}

def andnot(a: Bitset, b: Bitset) -> Bitset:
  match a b:
    case Bitset{+d, xs} Bitset{e, ys}:
      Bitset{d, zip(~andnot.w, d, xs, ys)}

# popcount of one cell: the SWAR ladder. Measured against a native POPC row in
# comp.ts (one __builtin_popcount): 4% on a 335,000,000-word count, inside the
# noise -- C's win there is an auto-vectorized loop, not the instruction. The
# row was reverted; it is worth revisiting only with the GPU lanes, where the
# ladder is twelve ops.
def ones(+x: U32) -> U32:
  +a = U32.sub(x, U32.and(U32.shrn(x, 1n), 1431655765))
  +b = U32.add(U32.and(a, 858993459), U32.and(U32.shrn(a, 2n), 858993459))
  U32.shrn(U32.mul(U32.and(U32.add(b, U32.shrn(b, 4n)), 252645135), 16843009), 24n)

def count.add(+s: U32, r: Array<U32> & U32) -> Array<U32> & U32:
  (a, x) = r
  (a, U32.add(s, ones(x)))

def count.step(+j: U32, as: Array<U32> & U32) -> Array<U32> & U32:
  (a, s) = as
  count.add(s, Array.get(U32, a, j))

def count.loop(i: Nat, as: Array<U32> & U32) -> Array<U32> & U32:
  match i:
    case 0n:
      as
    case 1n++p:
      count.loop(p, count.step(U32.from_nat(p), as))

def count.fin(d: Nat, r: Array<U32> & U32) -> Bitset & U32:
  (arr, n) = r
  (Bitset{d, arr}, n)

def count(b: Bitset) -> Bitset & U32:
  match b:
    case Bitset{+d, arr}:
      count.fin(d, count.loop(Nat.pow(2n, d), (arr, 0)))

# one cell at a time, for the callers that want to skip 32 flags at once rather
# than test them: an empty word is one compare, and a walk that enumerates the
# set bits is bounded by how many there are, not by the capacity. The index
# wraps at the cell count, like edit's does at the bit count.
def word.fin(d: Nat, r: Array<U32> & U32) -> Bitset & U32:
  (arr, w) = r
  (Bitset{d, arr}, w)

def word(b: Bitset, +j: U32) -> Bitset & U32:
  match b:
    case Bitset{d, arr}:
      word.fin(d, Array.get(U32, arr, j))

def set_word(b: Bitset, j: U32, w: U32) -> Bitset:
  match b:
    case Bitset{d, arr}:
      Bitset{d, Array.set(U32, arr, j, w)}

# the index of the lowest set bit. x & -x isolates it, and its index is the
# popcount of the mask below it -- the ladder above, so no ctz row is needed.
# Zero answers 32, which is off the end of a cell and stops a walk.
def low(+x: U32) -> U32:
  U32.and(x, U32.sub(0, x))

def ctz(+x: U32) -> U32:
  ones(U32.sub(low(x), 1))

# the list leads: a self-call must shrink before any argument changes
def from_list(xs: List<&2, U32>, b: Bitset) -> Bitset:
  match xs:
    case Nil{}:
      b
    case Con{+i, t}:
      from_list(t, set(b, i))
