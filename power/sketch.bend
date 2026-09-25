# Sketch algebra: four constant-memory summaries of a stream -- HyperLogLog
# (distinct count), CountMin (frequency), MinHash (similarity) and DDSketch
# (quantiles) -- each with a merge that is exact-associative, so a fork tree
# gives the number a sequential pass gives, bit for bit, at every depth and
# under every schedule.
#
# The one design decision everything else follows from: a sketch is kind Data.
# Vec, Bitset and every index built on Base's Array have kind Type -- affine,
# single-owner, and barred from a Result payload -- so a sketch that owned an
# Array could not hand itself back inside a Result and could not let both
# children of a fork derive from the same parent. Both are exactly what a
# sketch is for. So the registers are a Bank: a perfect binary tree of U32
# cells, a plain recursive ADT of numbers like Nat, kind Data. It copies, it
# drops, it rides inside a Result, and `merge` can therefore *refuse*.
#
# The second decision is that an update and a merge are the same operation.
# Every algorithm here is a commutative monoid over one cell:
#
#   Hll    max         idempotent, so merging a sketch with itself is a no-op
#   Cm     saturating add
#   Mh     min         idempotent
#   Dd     saturating add
#
# `bank.fuse` combines one cell with one value using the algo's own op, and
# `bank.zip` combines two banks cellwise with that same op. An update is a
# merge with a one-hot sketch, which is why associativity is not a property
# this file has to be careful about -- it is the only thing it can express.
# Saturating add is associative (min(a+b+c, max) either way), so the ceiling
# does not cost the law.
#
# The third is that nothing in the streaming path is a float. DDSketch's
# mapping is `index = ceil(log(x)/log(gamma))` with gamma = 2^(1/4), computed
# in integers: the exponent from a leading-zero count and the mantissa against
# four exact thresholds floor(2^31 * 2^(j/4)). That is the exact logarithmic
# mapping on the quarter-octave grid, not an approximation of it, and it is the
# same integer on the interpreter, on JS and on C -- where libm's log and V8's
# Math.log agree to the last ulp only by luck. Neither is HyperLogLog's
# estimator: its harmonic sum is fixed point and its logarithm is a squaring
# ladder, so there is no float in this file at all.
#
# Written for the compiled lanes: an update is one hash (Murmur3's fmix32, five
# native rows) and one descent of the bank, which rebuilds the path and nothing
# else; a merge is one structural zip; a read is a descent with no allocation.
import Base
import ./bitset.bend as Bit

# -- the fingerprint ---------------------------------------------------------

type Algo is Data:
  Hll{}
  Cm{}
  Mh{}
  Dd{}

# algo tag, seed and cell count: everything two sketches must agree on before
# their cells mean the same thing. Two HLLs on different seeds hash the same
# element into different registers, so a cellwise max of them is not the sketch
# of the union -- it is a number with no meaning at all. That is the error this
# record exists to make expressible.
type Fp is Data:
  Fp{algo: Algo, seed: U32, cells: U32}

type Error is Data:
  Mismatch{want: Fp, got: Fp}
  Undefined{}

def max() -> U32:
  4294967295

# -- hashing -----------------------------------------------------------------

# Murmur3's finalizer (fmix32): five rows, full avalanche on 32 bits. The seed
# is mixed in before the avalanche rather than after, so a seed change moves
# every element to an unrelated cell.
def mix(+x: U32) -> U32:
  +a = U32.xor(x, U32.shrn(x, 16n))
  +b = U32.mul(a, 2246822507)
  +c = U32.xor(b, U32.shrn(b, 13n))
  +d = U32.mul(c, 3266489909)
  U32.xor(d, U32.shrn(d, 16n))

def hash(+seed: U32, +x: U32) -> U32:
  mix(U32.xor(U32.mul(x, 2654435761), U32.add(U32.mul(seed, 2246822519), 3266489917)))

# leading zeros, 32 for 0: smear the highest set bit down, then count the ones.
# Bit.ones is bitset.bend's SWAR popcount ladder -- five native rows, no loop,
# and the one thing this lane borrows from another.
def nlz(+x: U32) -> U32:
  +a = U32.or(x, U32.shrn(x, 1n))
  +b = U32.or(a, U32.shrn(a, 2n))
  +c = U32.or(b, U32.shrn(b, 4n))
  +d = U32.or(c, U32.shrn(c, 8n))
  +e = U32.or(d, U32.shrn(d, 16n))
  U32.sub(32, Bit.ones(e))

# saturating add: a merge may lose count at the ceiling, never invent it, and
# min(a + b, max) is associative either way round, so the ceiling is free
def sat(+a: U32, +x: U32) -> U32:
  Bool.pick(U32, U32.is_lt(U32.sub(max(), a), x), max(), U32.add(a, x))

# -- the bank ----------------------------------------------------------------

# a perfect binary tree of 2^d U32 cells, kind Data. Leaves are in index order
# left to right, which is what lets DDSketch's quantile walk them in value
# order with a plain left-then-right fold.
type Bank is Data:
  BLeaf{w: U32}
  BNode{l: Bank, r: Bank}

def bank.new(d: Nat, w: U32) -> Bank:
  match d:
    case 0n:
      BLeaf{w}
    case 1n++p:
      +t = bank.new(p, w)
      BNode{t, t}

# the descent carries a one-bit mask rather than a depth: a Nat parameter would
# have to shrink in step with the tree, and the mask is one shift a level
def bit(+i: U32, +m: U32) -> Bool:
  U32.is_ne(U32.and(i, m), 0)

# the cell monoid: the whole difference between the four algorithms
def cell(k: Algo, +x: U32, +y: U32) -> U32:
  match k:
    case Hll{}:
      U32.max(x, y)
    case Cm{}:
      sat(x, y)
    case Mh{}:
      U32.min(x, y)
    case Dd{}:
      sat(x, y)

# fuse: combine one cell with one value, under the algo's own op. This is the
# update path of all four sketches -- an arrival is a merge with a one-hot
# sketch, so a sketch cannot be updated in a way its merge does not agree with.
def bank.fuse(k: Algo, b: Bank, +m: U32, +i: U32, +v: U32, c: Bool) -> Bank:
  match b c:
    case BLeaf{w} True{}:
      BLeaf{cell(k, w, v)}
    case BLeaf{w} False{}:
      BLeaf{cell(k, w, v)}
    case BNode{l, r} True{}:
      BNode{l, bank.fuse(k, r, U32.shr(m), i, v, bit(i, U32.shr(m)))}
    case BNode{l, r} False{}:
      BNode{bank.fuse(k, l, U32.shr(m), i, v, bit(i, U32.shr(m))), r}

def bank.at(k: Algo, b: Bank, +cells: U32, +i: U32, +v: U32) -> Bank:
  bank.fuse(k, b, U32.shr(cells), i, v, bit(i, U32.shr(cells)))

def bank.got(b: Bank, +m: U32, +i: U32, c: Bool) -> U32:
  match b c:
    case BLeaf{w} True{}:
      w
    case BLeaf{w} False{}:
      w
    case BNode{l, r} True{}:
      bank.got(r, U32.shr(m), i, bit(i, U32.shr(m)))
    case BNode{l, r} False{}:
      bank.got(l, U32.shr(m), i, bit(i, U32.shr(m)))

# a read allocates nothing: it walks one path and drops the rest
def bank.cell(b: Bank, +cells: U32, +i: U32) -> U32:
  bank.got(b, U32.shr(cells), i, bit(i, U32.shr(cells)))

def bank.zip(+k: Algo, a: Bank, b: Bank) -> Bank:
  match a b:
    case BLeaf{x} BLeaf{y}:
      BLeaf{cell(k, x, y)}
    case BLeaf{x} BNode{p, q}:
      BLeaf{x}
    case BNode{p, q} BLeaf{y}:
      BLeaf{y}
    case BNode{p, q} BNode{s, t}:
      BNode{bank.zip(k, p, s), bank.zip(k, q, t)}

def bank.sum(b: Bank, +acc: U32) -> U32:
  match b:
    case BLeaf{w}:
      sat(acc, w)
    case BNode{l, r}:
      bank.sum(r, bank.sum(l, acc))

def bank.digest(b: Bank, +acc: U32) -> U32:
  match b:
    case BLeaf{w}:
      U32.add(U32.mul(acc, 31), w)
    case BNode{l, r}:
      bank.digest(r, bank.digest(l, acc))

type Sketch is Data:
  Sketch{fp: Fp, bank: Bank}

def Res(T: Data) -> Data:
  Result<&2, &2, Error, T>

# -- fingerprints ------------------------------------------------------------

def algo.tag(a: Algo) -> U32:
  match a:
    case Hll{}:
      0
    case Cm{}:
      1
    case Mh{}:
      2
    case Dd{}:
      3

def show.algo(a: Algo) -> String:
  match a:
    case Hll{}:
      "hll"
    case Cm{}:
      "cm"
    case Mh{}:
      "mh"
    case Dd{}:
      "dd"

def fp.eq3(+p: U32, +q: U32, a: U32, b: U32, c: U32, d: U32) -> Bool:
  Bool.and(U32.is_eq(p, q), Bool.and(U32.is_eq(a, b), U32.is_eq(c, d)))

def fp.eq(a: Fp, b: Fp) -> Bool:
  match a b:
    case Fp{k, s, n} Fp{j, t, m}:
      fp.eq3(algo.tag(k), algo.tag(j), s, t, n, m)

def fp.tag(f: Fp) -> U32:
  match f:
    case Fp{k, s, n}:
      U32.add(U32.mul(algo.tag(k), 1000003), U32.add(U32.mul(s, 31), n))

def fp.of(s: Sketch) -> Fp:
  match s:
    case Sketch{f, b}:
      f

def fp.cells(f: Fp) -> U32:
  match f:
    case Fp{k, s, n}:
      n

def cells(s: Sketch) -> U32:
  match s:
    case Sketch{f, b}:
      fp.cells(f)

# the whole sketch in one number: the fingerprint and every cell in index
# order. Two sketches with the same digest agree cell for cell.
def digest(s: Sketch) -> U32:
  match s:
    case Sketch{f, b}:
      bank.digest(b, fp.tag(f))

# -- merge -------------------------------------------------------------------

def merge.do(f: Fp, a: Bank, b: Bank) -> Res(Sketch):
  match f:
    case Fp{+k, s, n}:
      Done{Sketch{Fp{k, s, n}, bank.zip(k, a, b)}}

def merge.if(f: Fp, g: Fp, a: Bank, b: Bank, ok: Bool) -> Res(Sketch):
  match ok:
    case True{}:
      merge.do(f, a, b)
    case False{}:
      Fail{Mismatch{f, g}}

# merge: cellwise under the algo's op, and only when the two sketches were
# built to the same fingerprint. An incompatible merge is an error, not a
# number -- it is the one thing a caller cannot check afterwards, because a
# cellwise max of two differently seeded HLLs is a perfectly plausible sketch
# of nothing.
def merge(a: Sketch, b: Sketch) -> Res(Sketch):
  match a b:
    case Sketch{+f, x} Sketch{+g, y}:
      merge.if(f, g, x, y, fp.eq(f, g))

def merge2.b(a: Sketch, r: Res(Sketch)) -> Res(Sketch):
  match r:
    case Fail{e}:
      Fail{e}
    case Done{b}:
      merge(a, b)

# the fork tree's combiner: two results become one, keeping the first refusal
def merge2(x: Res(Sketch), y: Res(Sketch)) -> Res(Sketch):
  match x:
    case Fail{e}:
      Fail{e}
    case Done{a}:
      merge2.b(a, y)

# -- HyperLogLog -------------------------------------------------------------

# m = 2^d registers, one per cell. Flajolet's estimator with the small-range
# (linear counting) correction.
#
# The low d bits of the hash pick the register and the leading-zero count of
# the *remaining* bits gives rho. Those two bit ranges are disjoint, so rho is
# read off the hash with the register bits masked to zero rather than shifted
# away: no variable shift, and the cell count is free to come from the
# fingerprint instead of being frozen into the code. An all-zero high half
# (probability 2^-(32-d)) reports rho = 33 instead of 33-d; the mass involved
# is 2^-26 at d = 6 and the estimator never sees the difference.
def hll.new(+seed: U32, +d: Nat) -> Sketch:
  Sketch{Fp{Hll{}, seed, U32.shln(1, d)}, bank.new(d, 0)}

def hll.mk(+k: Algo, +s: U32, +n: U32, b: Bank, +h: U32) -> Sketch:
  +lo = U32.sub(n, 1)
  Sketch{Fp{k, s, n},
    bank.at(k, b, n, U32.and(h, lo), U32.inc(nlz(U32.and(h, U32.not(lo)))))}

def hll.mk2(+k: Algo, +s: U32, +n: U32, b: Bank, +x: U32) -> Sketch:
  hll.mk(k, s, n, b, hash(s, x))

def hll.go(f: Fp, b: Bank, +x: U32) -> Sketch:
  match f:
    case Fp{k, s, n}:
      hll.mk2(k, s, n, b, x)

def hll.add(s: Sketch, +x: U32) -> Sketch:
  match s:
    case Sketch{f, b}:
      hll.go(f, b, x)

# the harmonic sum and the zero-register count in one pass
type Zs is Data:
  Zs{s: U32, v: U32}

# -- the estimator, in integers ----------------------------------------------
#
# Flajolet's estimator is alpha_m * m^2 / sum(2^-r), and the textbook way to
# write it is in doubles. This does not, and the reason is not taste. A float
# here would be the only float in the library, and it would be a float whose
# truncation decides a printed number -- libm's log and V8's Math.log need not
# agree in the last ulp, and one ulp either side of an integer boundary is a
# different answer on the C lane and the JS lane. It was also measured: an F64
# carried in a record through this module's C build faults the runtime outright
# (see docs/omen/lanes/power-12.md). So the harmonic sum is fixed point and the
# small-range logarithm is a squaring ladder, and every lane prints the same
# integer because there is nothing left that could differ.

# alpha_m * 2^32, from Flajolet's table.
# ponytail: 0.7213 flat past 64 registers, instead of 0.7213/(1 + 1.079/m).
# That correction is 0.84% at m = 128 and 0.1% at m = 1024, against a standard
# error of 9.2% and 3.3%; computing it needs m * 2^32 / (m + 1.079), and the
# numerator does not fit a U32.
def hll.alpha(+m: U32) -> U32:
  Bool.pick(U32, U32.is_eq(m, 16), 2890137797,
    Bool.pick(U32, U32.is_eq(m, 32), 2993204531,
      Bool.pick(U32, U32.is_eq(m, 64), 3044758155, 3098137299)))

# d: the register count's log, m being a power of two by construction
def hll.d(+m: U32) -> U32:
  U32.sub(31, nlz(m))

# K: the harmonic sum's fixed-point scale. 32 - 2d is the largest scale that
# keeps the numerator alpha * m^2 * 2^K at alpha * 2^32, the biggest a U32
# holds; the min caps it at 24 for the narrow widths where 32 - 2d would push
# the shift past a word.
def hll.k(+m: U32) -> U32:
  U32.min(24, U32.sub(32, U32.min(32, U32.mul(2, hll.d(m)))))

# and the matching right shift on the numerator, zero once 2d >= 8
def hll.sh(+m: U32) -> U32:
  U32.sub(8, U32.min(8, U32.mul(2, hll.d(m))))

# a register's contribution, 2^(K-r), floored at 1. The floor is a ceiling in
# disguise: a register past r = K stops halving, so the estimate saturates at
# alpha * m * 2^K -- 47 million for 64 registers, which is a hundred times past
# where a 64-register sketch says anything useful. Without it a sketch whose
# every register passed K would divide by zero.
def hll.w(+r: U32, +k: U32) -> U32:
  U32.shln(1, U32.to_nat(U32.sub(k, U32.min(r, k))))

def hll.scan.leaf(+k: U32, +w: U32, a: Zs) -> Zs:
  match a:
    case Zs{s, v}:
      Zs{U32.add(s, hll.w(w, k)), U32.add(v, Bool.to_u32(U32.is_eq(w, 0)))}

def hll.scan(+k: U32, b: Bank, a: Zs) -> Zs:
  match b:
    case BLeaf{w}:
      hll.scan.leaf(k, w, a)
    case BNode{l, r}:
      hll.scan(k, r, hll.scan(k, l, a))

# floor(2^15 * log2(x)) for x >= 1, x's mantissa held at scale 2^15 in
# [2^15, 2^16) -- where a square is at most (2^16-1)^2 = 4,294,836,225, under
# 2^32 by 131,071. That headroom is the whole reason the scale is 15 and not
# 16: one more bit and the ladder would need a word this language does not
# have. Each step squares, reads the carry bit out of the top, and normalises
# by that same bit, so there is no branch in it.
def hll.lg.go(i: Nat, +y: U32, +acc: U32) -> U32:
  match i:
    case 0n:
      acc
    case 1n++p:
      +z = U32.shrn(U32.mul(y, y), 15n)
      hll.lg.go(p, U32.shrn(z, U32.to_nat(U32.shrn(z, 16n))),
        U32.add(U32.mul(acc, 2), U32.shrn(z, 16n)))

def hll.nrm(+x: U32, +e: U32, up: Bool) -> U32:
  match up:
    case True{}:
      U32.shln(x, U32.to_nat(U32.sub(15, e)))
    case False{}:
      U32.shrn(x, U32.to_nat(U32.sub(e, 15)))

def hll.lg2(+x: U32, +e: U32) -> U32:
  U32.add(U32.shln(e, 15n), hll.lg.go(15n, hll.nrm(x, e, U32.is_lt(e, 15)), 0))

def hll.lg(+x: U32) -> U32:
  hll.lg2(x, U32.sub(31, nlz(x)))

# linear counting: m * ln(m/v) over the v registers still empty. ln from log2
# by 22713/2^15 = ln 2; the value is narrowed by five bits first so the product
# stays in a word, which costs three parts in a hundred thousand.
# ponytail: valid while m * ln(m/v) * 2^15 fits a U32, which is every register
# count up to 8192.
def hll.small.n(+m: U32, +t: U32) -> U32:
  U32.shrn(U32.mul(m, U32.shrn(U32.mul(U32.shrn(t, 5n), 22713), 10n)), 15n)

def hll.small(+m: U32, +v: U32) -> U32:
  hll.small.n(m, U32.sub(hll.lg(m), hll.lg(v)))

def hll.big(+m: U32, +s: U32) -> U32:
  U32.div(U32.shrn(hll.alpha(m), U32.to_nat(hll.sh(m))), s)

def hll.pick(+m: U32, +e: U32, +v: U32, small: Bool) -> U32:
  match small:
    case True{}:
      hll.small(m, v)
    case False{}:
      e

# the small-range switch is E <= 2.5m, written as 2E <= 5m so it is a compare
# between two integers and not between two roundings
def hll.e3(+m: U32, +e: U32, +v: U32) -> U32:
  hll.pick(m, e, v,
    Bool.and(U32.is_le(U32.mul(e, 2), U32.mul(m, 5)), U32.is_gt(v, 0)))

def hll.e2(+m: U32, a: Zs) -> U32:
  match a:
    case Zs{s, v}:
      hll.e3(m, hll.big(m, s), v)

def hll.e1(+n: U32, b: Bank) -> U32:
  hll.e2(n, hll.scan(hll.k(n), b, Zs{0, 0}))

def hll.e0(f: Fp, b: Bank) -> U32:
  match f:
    case Fp{k, s, n}:
      hll.e1(n, b)

# ponytail: no large-range correction. It is -2^32 * ln(1 - E/2^32), and it
# only moves the answer past E = 2^32/30 = 143,000,000 distinct elements, which
# a 64-register sketch cannot resolve to better than a factor anyway.
def hll.estimate(s: Sketch) -> U32:
  match s:
    case Sketch{f, b}:
      hll.e0(f, b)

# -- CountMin ----------------------------------------------------------------

# d rows of w counters; a row's counter for x is hash(seed + row, x) mod w, and
# the estimate is the least of the d rows. Every row overcounts (a collision
# adds someone else's weight and nothing ever subtracts), so the minimum is an
# upper bound that is tight whenever one row is collision-free.
#
# ponytail: the row count is fixed at 4 and the width is cells/4. A row count
# in the fingerprint would need a second config word to stay checkable, to buy
# a knob whose useful values are 3..5.
def cm.rows() -> U32:
  4

def cm.width(+n: U32) -> U32:
  U32.shrn(n, 2n)

def cm.new(+seed: U32, +d: Nat) -> Sketch:
  Sketch{Fp{Cm{}, seed, U32.shln(1, d)}, bank.new(d, 0)}

def cm.slot(+s: U32, +x: U32, +w: U32, +r: U32) -> U32:
  U32.add(U32.mul(r, w), U32.and(hash(U32.add(s, U32.mul(r, 2246822519)), x), U32.sub(w, 1)))

def cm.rowloop(i: Nat, b: Bank, +n: U32, +s: U32, +x: U32, +c: U32) -> Bank:
  match i:
    case 0n:
      b
    case 1n++p:
      cm.rowloop(p,
        bank.at(Cm{}, b, n, cm.slot(s, x, cm.width(n), U32.from_nat(p)), c),
        n, s, x, c)

def cm.mk(+k: Algo, +s: U32, +n: U32, b: Bank, +x: U32, +c: U32) -> Sketch:
  Sketch{Fp{k, s, n}, cm.rowloop(U32.to_nat(cm.rows()), b, n, s, x, c)}

def cm.go(f: Fp, b: Bank, +x: U32, +c: U32) -> Sketch:
  match f:
    case Fp{k, s, n}:
      cm.mk(k, s, n, b, x, c)

def cm.add(s: Sketch, +x: U32, +c: U32) -> Sketch:
  match s:
    case Sketch{f, b}:
      cm.go(f, b, x, c)

def cm.minloop(i: Nat, +b: Bank, +n: U32, +s: U32, +x: U32, +acc: U32) -> U32:
  match i:
    case 0n:
      acc
    case 1n++p:
      cm.minloop(p, b, n, s, x,
        U32.min(acc, bank.cell(b, n, cm.slot(s, x, cm.width(n), U32.from_nat(p)))))

def cm.e0(f: Fp, b: Bank, +x: U32) -> U32:
  match f:
    case Fp{k, s, n}:
      cm.minloop(U32.to_nat(cm.rows()), b, n, s, x, max())

def cm.estimate(s: Sketch, +x: U32) -> U32:
  match s:
    case Sketch{f, b}:
      cm.e0(f, b, x)

# the total weight the sketch was fed: one row's sum, saturating
def cm.t0(f: Fp, b: Bank) -> U32:
  match f:
    case Fp{k, s, n}:
      U32.div(bank.sum(b, 0), cm.rows())

def cm.total(s: Sketch) -> U32:
  match s:
    case Sketch{f, b}:
      cm.t0(f, b)

# -- MinHash -----------------------------------------------------------------

# k independent hashes, cell i keeping the least hash i has ever seen. Two
# streams agree in a slot exactly when the element that minimises hash i is in
# both, which happens with probability |A n B| / |A u B| -- so the matching
# slots out of k estimate the Jaccard index directly, and the merge is a
# cellwise min because the least of a union is the least of the leasts.
def mh.new(+seed: U32, +d: Nat) -> Sketch:
  Sketch{Fp{Mh{}, seed, U32.shln(1, d)}, bank.new(d, max())}

def mh.one(b: Bank, +n: U32, +j: U32, +s: U32, +x: U32) -> Bank:
  bank.at(Mh{}, b, n, j, hash(U32.add(s, U32.mul(j, 2654435761)), x))

def mh.slotloop(i: Nat, b: Bank, +n: U32, +s: U32, +x: U32) -> Bank:
  match i:
    case 0n:
      b
    case 1n++p:
      mh.slotloop(p,
        mh.one(b, n, U32.from_nat(p), s, x),
        n, s, x)

def mh.mk(+k: Algo, +s: U32, +n: U32, b: Bank, +x: U32) -> Sketch:
  Sketch{Fp{k, s, n}, mh.slotloop(U32.to_nat(n), b, n, s, x)}

def mh.go(f: Fp, b: Bank, +x: U32) -> Sketch:
  match f:
    case Fp{k, s, n}:
      mh.mk(k, s, n, b, x)

def mh.add(s: Sketch, +x: U32) -> Sketch:
  match s:
    case Sketch{f, b}:
      mh.go(f, b, x)

def mh.same(a: Bank, b: Bank, +acc: U32) -> U32:
  match a b:
    case BLeaf{x} BLeaf{y}:
      U32.add(acc, Bool.to_u32(U32.is_eq(x, y)))
    case BLeaf{x} BNode{p, q}:
      acc
    case BNode{p, q} BLeaf{y}:
      acc
    case BNode{p, q} BNode{s, t}:
      mh.same(q, t, mh.same(p, s, acc))

def mh.jac.if(f: Fp, g: Fp, x: Bank, y: Bank, ok: Bool) -> Res(U32):
  match ok:
    case True{}:
      Done{mh.same(x, y, 0)}
    case False{}:
      Fail{Mismatch{f, g}}

# the matching slots out of k; a similarity is that over cells(a). It refuses
# for the same reason merge does -- two different seeds are two different
# permutations, and their slots have nothing to say to each other.
def mh.jaccard(a: Sketch, b: Sketch) -> Res(U32):
  match a b:
    case Sketch{+f, x} Sketch{+g, y}:
      mh.jac.if(f, g, x, y, fp.eq(f, g))

# -- DDSketch ----------------------------------------------------------------

# relative-error buckets: bucket i holds (gamma^(i-1), gamma^i], so any value
# in it is within (gamma-1)/(gamma+1) of the bucket's midpoint no matter how
# large it is. gamma = 2^(1/4) gives a guaranteed 8.64% relative error and 4
# buckets an octave, so 128 cells span 1 .. 2^31.
#
# index = ceil(4 * log2(x)), computed exactly in integers. Write x = 2^e * f
# with f in [1, 2) and let mm = x << nlz(x), the mantissa as a fixed-point
# number in [2^31, 2^32). Then the answer is 4e + j for the least j with
# 2^(j/4) >= f, i.e. mm <= floor(2^31 * 2^(j/4)) -- and those four thresholds
# are irrational multiples of 2^31, so no integer mantissa ever ties.
def dd.t1() -> U32:
  2553802833

def dd.t2() -> U32:
  3037000499

def dd.t3() -> U32:
  3611622602

def dd.j(+m: U32) -> U32:
  Bool.pick(U32, U32.is_le(m, 2147483648), 0,
    Bool.pick(U32, U32.is_le(m, dd.t1()), 1,
      Bool.pick(U32, U32.is_le(m, dd.t2()), 2,
        Bool.pick(U32, U32.is_le(m, dd.t3()), 3, 4))))

def dd.idx.go(+x: U32, +z: U32) -> U32:
  U32.add(U32.mul(U32.sub(31, z), 4), dd.j(U32.shln(x, U32.to_nat(z))))

# ponytail: x = 0 is recorded in bucket 0, the bucket of the values just at or
# below 1, rather than in a zero counter of its own. A quantile sketch that
# cannot represent 0 is DDSketch's own shape -- it keeps a separate zero count
# -- and that count is a second field with its own merge and its own place in
# every walk, for a value this package's streams (latencies, sizes, weights)
# do not produce. The ceiling is named here and asserted in the fixture.
def dd.idx(+x: U32) -> U32:
  dd.idx.go(U32.max(x, 1), nlz(U32.max(x, 1)))

def dd.new(+seed: U32, +d: Nat) -> Sketch:
  Sketch{Fp{Dd{}, seed, U32.shln(1, d)}, bank.new(d, 0)}

def dd.mk(+k: Algo, +s: U32, +n: U32, b: Bank, +x: U32) -> Sketch:
  Sketch{Fp{k, s, n}, bank.at(k, b, n, U32.min(dd.idx(x), U32.sub(n, 1)), 1)}

def dd.go(f: Fp, b: Bank, +x: U32) -> Sketch:
  match f:
    case Fp{k, s, n}:
      dd.mk(k, s, n, b, x)

def dd.add(s: Sketch, +x: U32) -> Sketch:
  match s:
    case Sketch{f, b}:
      dd.go(f, b, x)

def dd.count(s: Sketch) -> U32:
  match s:
    case Sketch{f, b}:
      bank.sum(b, 0)

# the walk: rank counts down through the buckets in index order; hit is the
# first bucket whose count carries it past, and max() means "not yet"
type Walk is Data:
  Walk{hit: U32, rank: U32, at: U32}

def walk.take(+c: U32, +r: U32, +at: U32, +hit: U32, found: Bool) -> Walk:
  match found:
    case True{}:
      Walk{at, 0, U32.inc(at)}
    case False{}:
      Walk{hit, U32.sub(r, c), U32.inc(at)}

def walk.go(+c: U32, +r: U32, +at: U32, +hit: U32, done: Bool) -> Walk:
  match done:
    case True{}:
      Walk{hit, r, U32.inc(at)}
    case False{}:
      walk.take(c, r, at, hit, U32.is_lt(r, c))

def walk.leaf(+c: U32, w: Walk) -> Walk:
  match w:
    case Walk{+hit, r, at}:
      walk.go(c, r, at, hit, U32.is_ne(hit, max()))

def bank.walk(b: Bank, w: Walk) -> Walk:
  match b:
    case BLeaf{c}:
      walk.leaf(c, w)
    case BNode{l, r}:
      bank.walk(r, bank.walk(l, w))

def walk.hit(w: Walk) -> U32:
  match w:
    case Walk{hit, r, at}:
      hit

def dd.q.if(b: Bank, +qp: U32, +n: U32, empty: Bool) -> Res(U32):
  match empty:
    case True{}:
      Fail{Undefined{}}
    case False{}:
      Done{walk.hit(bank.walk(b,
        Walk{max(), U32.div(U32.mul(qp, U32.sub(n, 1)), 1000), 0}))}

def dd.q.n(b: Bank, +qp: U32, +n: U32) -> Res(U32):
  dd.q.if(b, qp, n, U32.is_eq(n, 0))

def dd.q.go(+b: Bank, +qp: U32) -> Res(U32):
  dd.q.n(b, qp, bank.sum(b, 0))

# quantile(q): q in per mille, the answer the *bucket index* of the value at
# rank floor(q * (n-1)) -- the same element sorted(xs)[floor(q*(n-1))] names.
# An index, not a value, because a value would be a float and this file prints
# no floats; the bucket is (gamma^(i-1), gamma^i] and the caller reconstructs
# whatever representative it wants.
#
# ponytail: q * (n-1) is a U32 product, so a sketch holding more than about
# 4,290,000 values would wrap. The count is there to check against.
def dd.quantile(s: Sketch, +qp: U32) -> Res(U32):
  match s:
    case Sketch{f, b}:
      dd.q.go(b, qp)
