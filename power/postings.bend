# Postings: an integer set over a document universe, in the two shapes that pay
# -- a sorted unique Vec of ids, and one bit per id -- with and / or / andnot /
# not across the pair. This is Roaring's array-or-bitmap decision without
# Roaring's chunking: the chunking exists so that ids scattered through a 32-bit
# space still meet inside one container, and an index that numbers its documents
# 0..n-1 has nothing to scatter, while the container choice -- the part that
# actually pays -- is the whole of the idea.
#
# Written for the compiled lanes: a dense-dense operation is Bitset's own
# in-place cell loop, 32 documents an iteration and no allocation; a sparse
# operation is one left-to-right merge whose output is never longer than its
# inputs; a mixed pair goes the way that keeps the answer's own shape, so an
# AND with a sparse side costs that side and not the universe.
#
# Every set in one expression must be over one universe: a dense set's capacity
# is rounded up to 32 * 2^d, and a sparse id at or past that capacity would
# wrap into the wrong cell rather than read as absent.
import Base
import ./vec.bend as Vec
import ./bitset.bend as Bitset

type Set is Type:
  Sparse{v: Vec.Vec}         # ascending, no duplicates
  Dense{b: Bitset.Bitset}    # one bit per id, capacity 32 * 2^depth

# ponytail: 2^32-1 is the merge's end-of-side sentinel, so it is not a member.
# A universe that needs it needs a flag per side instead, two more record fields.
def top() -> U32:
  4294967295

# -- shapes ------------------------------------------------------------------

# the highest set bit's index plus one, branch-free: smear the value down and
# count the ones, which is the ladder Bitset already carries.
def bits(+x: U32) -> U32:
  +a = U32.or(x, U32.shrn(x, 1n))
  +b = U32.or(a, U32.shrn(a, 2n))
  +c = U32.or(b, U32.shrn(b, 4n))
  +d = U32.or(c, U32.shrn(c, 8n))
  Bitset.ones(U32.or(d, U32.shrn(d, 16n)))

# the Bitset depth whose 32 * 2^d bits hold n of them
def depth(+n: U32) -> Nat:
  U32.to_nat(U32.sub(U32.max(bits(U32.sub(U32.max(n, 1), 1)), 5), 5))

def sparse() -> Set:
  Sparse{Vec.new(0)}

def dense(+n: U32) -> Set:
  Dense{Bitset.new(depth(n))}

# 1s in the low k bits and 0 above; k of 32 or more is every bit, because a
# shift of 32 answers 0 and 0 - 1 is the full word
def lowmask(+k: U32) -> U32:
  U32.sub(U32.shln(1, U32.to_nat(U32.min(k, 32))), 1)

def all.lim.if(+n: U32, +base: U32, past: Bool) -> U32:
  match past:
    case True{}:
      0
    case False{}:
      U32.sub(n, base)

def all.lim(+n: U32, +base: U32) -> U32:
  all.lim.if(n, base, U32.is_ge(base, n))

def all.go(fuel: Nat, +j: U32, +n: U32, b: Bitset.Bitset) -> Bitset.Bitset:
  match fuel:
    case 0n:
      b
    case 1n++p:
      all.go(p, U32.inc(j), n, Bitset.set_word(b, j, lowmask(all.lim(n, U32.shln(j, 5n)))))

def all.mk(+d: Nat, +n: U32) -> Set:
  Dense{all.go(Nat.pow(2n, d), 0, n, Bitset.new(d))}

# every id below n and nothing above: written a cell at a time, so a complement
# costs the universe once and not a bit at a time
def all(+n: U32) -> Set:
  all.mk(depth(n), n)

# add: the id must be greater than every id already in a sparse set; a dense set
# takes them in any order
def add(s: Set, +x: U32) -> Set:
  match s:
    case Sparse{v}:
      Sparse{Vec.push(v, x)}
    case Dense{b}:
      Dense{Bitset.set(b, x)}

# of_list: the caller promises ascending and unique, which is what a posting
# list already is
def of_list(xs: List<&2, U32>) -> Set:
  Sparse{Vec.from_list(xs, Vec.new(0))}

# -- enumeration -------------------------------------------------------------

# the set bits of one word, low to high. The loop is bounded by the popcount, so
# a word with two bits costs two steps and an empty one costs none.
def enum.w(fuel: Nat, +base: U32, +w: U32, v: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      v
    case 1n++p:
      +lo = Bitset.low(w)
      enum.w(p, base, U32.xor(w, lo), Vec.push(v, U32.add(base, Bitset.ctz(lo))))

type Enum is Type:
  Enum{b: Bitset.Bitset, out: Vec.Vec}

def enum.word(+j: U32, out: Vec.Vec, r: Bitset.Bitset & U32) -> Enum:
  (b, +w) = r
  Enum{b, enum.w(U32.to_nat(Bitset.ones(w)), U32.shln(j, 5n), w, out)}

def enum.go(fuel: Nat, +j: U32, e: Enum) -> Enum:
  match fuel:
    case 0n:
      e
    case 1n++q:
      match e:
        case Enum{b, out}:
          enum.go(q, U32.inc(j), enum.word(j, out, Bitset.word(b, j)))

def enum.fin(e: Enum) -> Vec.Vec:
  match e:
    case Enum{b, out}:
      out

def enum.cells(r: Bitset.Bitset & U32) -> Vec.Vec:
  (b, cap) = r
  enum.fin(enum.go(U32.to_nat(U32.shrn(cap, 5n)), 0, Enum{b, Vec.new(0)}))

def enum(b: Bitset.Bitset) -> Vec.Vec:
  enum.cells(Bitset.size(b))

# to_vec: the members, ascending. The set is spent, so a sparse one is the
# answer already and nothing is copied.
def to_vec(s: Set) -> Vec.Vec:
  match s:
    case Sparse{v}:
      v
    case Dense{b}:
      enum(b)

# -- membership --------------------------------------------------------------

type Bs is Type:
  Bs{v: Vec.Vec, lo: U32, hi: U32, on: Bool}

def bs.mk(v: Vec.Vec, +lo: U32, +hi: U32) -> Bs:
  Bs{v, lo, hi, U32.is_lt(lo, hi)}

def bs.if(v: Vec.Vec, +mid: U32, lo: U32, hi: U32, less: Bool) -> Bs:
  match less:
    case True{}:
      bs.mk(v, U32.inc(mid), hi)
    case False{}:
      bs.mk(v, lo, mid)

def bs.got(+mid: U32, lo: U32, hi: U32, +x: U32, r: Vec.Vec & U32) -> Bs:
  (v, y) = r
  bs.if(v, mid, lo, hi, U32.is_lt(y, x))

# the window shrinks in the record's own flag: the checker forbids a loop whose
# test lives in a second def, so "is there still a window" is a field
def bs.go(fuel: Nat, +x: U32, s: Bs) -> Bs:
  match fuel:
    case 0n:
      s
    case 1n++p:
      match s:
        case Bs{v, +lo, +hi, on}:
          match on:
            case True{}:
              +mid = U32.add(lo, U32.shr(U32.sub(hi, lo)))
              bs.go(p, x, bs.got(mid, lo, hi, x, Vec.at(v, mid)))
            case False{}:
              Bs{v, lo, hi, False{}}

def bs.out(s: Bs) -> Vec.Vec & U32:
  match s:
    case Bs{v, lo, hi, on}:
      (v, lo)

# lower: the first index in [lo, hi) whose value is not less than x, which is
# where x is if it is there and where it would go if it is not
def lower(v: Vec.Vec, +x: U32, +lo: U32, +hi: U32) -> Vec.Vec & U32:
  bs.out(bs.go(33n, x, bs.mk(v, lo, hi)))

def found.eq(+x: U32, r: Vec.Vec & U32) -> Vec.Vec & Bool:
  (v, y) = r
  (v, U32.is_eq(y, x))

def found.if(v: Vec.Vec, +x: U32, +i: U32, ok: Bool) -> Vec.Vec & Bool:
  match ok:
    case True{}:
      found.eq(x, Vec.at(v, i))
    case False{}:
      (v, False{})

def found.at(+x: U32, +n: U32, r: Vec.Vec & U32) -> Vec.Vec & Bool:
  (v, +i) = r
  found.if(v, x, i, U32.is_lt(i, n))

# found: is x in v[0..n)
def found(v: Vec.Vec, +x: U32, +n: U32) -> Vec.Vec & Bool:
  found.at(x, n, lower(v, x, 0, n))

def has.sp.out(r: Vec.Vec & Bool) -> Set & Bool:
  (v, t) = r
  (Sparse{v}, t)

def has.sp(+x: U32, r: Vec.Vec & U32) -> Set & Bool:
  (v, n) = r
  has.sp.out(found(v, x, n))

def has.dn.out(r: Bitset.Bitset & Bool) -> Set & Bool:
  (b, t) = r
  (Dense{b}, t)

def has.dn.if(b: Bitset.Bitset, +x: U32, ok: Bool) -> Set & Bool:
  match ok:
    case True{}:
      has.dn.out(Bitset.test(b, x))
    case False{}:
      (Dense{b}, False{})

def has.dn(+x: U32, r: Bitset.Bitset & U32) -> Set & Bool:
  (b, cap) = r
  has.dn.if(b, x, U32.is_lt(x, cap))

# has: one test on a dense set, one binary search on a sparse one
def has(s: Set, +x: U32) -> Set & Bool:
  match s:
    case Sparse{v}:
      has.sp(x, Vec.len(v))
    case Dense{b}:
      has.dn(x, Bitset.size(b))

def count.sp(r: Vec.Vec & U32) -> Set & U32:
  (v, n) = r
  (Sparse{v}, n)

def count.dn(r: Bitset.Bitset & U32) -> Set & U32:
  (b, n) = r
  (Dense{b}, n)

def count(s: Set) -> Set & U32:
  match s:
    case Sparse{v}:
      count.sp(Vec.len(v))
    case Dense{b}:
      count.dn(Bitset.count(b))

# -- the merge ---------------------------------------------------------------

# One left-to-right walk serves all three sparse operations. The mode says which
# relation emits: 4 the ids only a has, 2 the ids both have, 1 the ids only b
# has -- so 2 is intersection, 4 is difference and 7 is union. The advance is
# the same either way, which is why one loop is enough.
type Cur is Data:
  Cur{i: U32, j: U32, na: U32, nb: U32}

def cur.i(c: Cur) -> U32:
  match c:
    case Cur{i, j, na, nb}:
      i

def cur.j(c: Cur) -> U32:
  match c:
    case Cur{i, j, na, nb}:
      j

def cur.na(c: Cur) -> U32:
  match c:
    case Cur{i, j, na, nb}:
      na

def cur.nb(c: Cur) -> U32:
  match c:
    case Cur{i, j, na, nb}:
      nb

def cur.on(c: Cur) -> Bool:
  match c:
    case Cur{i, j, na, nb}:
      Bool.or(U32.is_lt(i, na), U32.is_lt(j, nb))

def bump(+i: U32, stay: Bool) -> U32:
  match stay:
    case True{}:
      i
    case False{}:
      U32.inc(i)

def cur.next(c: Cur, lt: Bool, gt: Bool) -> Cur:
  match c:
    case Cur{i, j, na, nb}:
      Cur{bump(i, gt), bump(j, lt), na, nb}

# a side that has run out reads as the sentinel, so it loses every comparison
# and the other side drains on its own
def key.if(v: Vec.Vec, +i: U32, live: Bool) -> Vec.Vec & U32:
  match live:
    case True{}:
      Vec.at(v, i)
    case False{}:
      (v, top())

def key(v: Vec.Vec, +i: U32, +n: U32) -> Vec.Vec & U32:
  key.if(v, i, U32.is_lt(i, n))

def mrg.pick(+mode: U32, lt: Bool, gt: Bool) -> Bool:
  match lt:
    case True{}:
      U32.is_ne(U32.and(mode, 4), 0)
    case False{}:
      match gt:
        case True{}:
          U32.is_ne(U32.and(mode, 1), 0)
        case False{}:
          U32.is_ne(U32.and(mode, 2), 0)

def mrg.emit(o: Vec.Vec, +x: U32, yes: Bool) -> Vec.Vec:
  match yes:
    case True{}:
      Vec.push(o, x)
    case False{}:
      o

type Mrg is Type:
  Mrg{a: Vec.Vec, b: Vec.Vec, o: Vec.Vec, cur: Cur, on: Bool}

def mrg.mk(a: Vec.Vec, b: Vec.Vec, o: Vec.Vec, +c: Cur) -> Mrg:
  Mrg{a, b, o, c, cur.on(c)}

def mrg.dec(+mode: U32, a: Vec.Vec, b: Vec.Vec, o: Vec.Vec, c: Cur, +x: U32, +lt: Bool, +gt: Bool) -> Mrg:
  mrg.mk(a, b, mrg.emit(o, x, mrg.pick(mode, lt, gt)), cur.next(c, lt, gt))

def mrg.rel(+mode: U32, a: Vec.Vec, b: Vec.Vec, o: Vec.Vec, c: Cur, +ka: U32, +kb: U32) -> Mrg:
  mrg.dec(mode, a, b, o, c, U32.min(ka, kb), U32.is_lt(ka, kb), U32.is_gt(ka, kb))

def mrg.kb(+mode: U32, a: Vec.Vec, o: Vec.Vec, c: Cur, +ka: U32, r: Vec.Vec & U32) -> Mrg:
  (b, kb) = r
  mrg.rel(mode, a, b, o, c, ka, kb)

def mrg.ka(+mode: U32, b: Vec.Vec, o: Vec.Vec, +c: Cur, r: Vec.Vec & U32) -> Mrg:
  (a, ka) = r
  mrg.kb(mode, a, o, c, ka, key(b, cur.j(c), cur.nb(c)))

def mrg.go(+mode: U32, fuel: Nat, m: Mrg) -> Mrg:
  match fuel:
    case 0n:
      m
    case 1n++p:
      match m:
        case Mrg{a, b, o, +c, on}:
          match on:
            case True{}:
              mrg.go(mode, p, mrg.ka(mode, b, o, c, key(a, cur.i(c), cur.na(c))))
            case False{}:
              Mrg{a, b, o, c, False{}}

def mrg.out(m: Mrg) -> Vec.Vec:
  match m:
    case Mrg{a, b, o, c, on}:
      o

def merge.nb(+mode: U32, a: Vec.Vec, +na: U32, r: Vec.Vec & U32) -> Vec.Vec:
  (b, +nb) = r
  mrg.out(mrg.go(mode, U32.to_nat(U32.inc(U32.add(na, nb))), mrg.mk(a, b, Vec.new(0), Cur{0, 0, na, nb})))

def merge.na(+mode: U32, b: Vec.Vec, r: Vec.Vec & U32) -> Vec.Vec:
  (a, na) = r
  merge.nb(mode, a, na, Vec.len(b))

# merge: one step per id of either side, so the walk is bounded by na + nb
def merge(+mode: U32, a: Vec.Vec, b: Vec.Vec) -> Vec.Vec:
  merge.na(mode, b, Vec.len(a))

# -- sparse against dense ----------------------------------------------------

type Sv is Type:
  Sv{v: Vec.Vec, b: Bitset.Bitset, o: Vec.Vec}

def sv.take(t: Bool, want: Bool) -> Bool:
  match want:
    case True{}:
      t
    case False{}:
      Bool.not(t)

def sv.bit(v: Vec.Vec, o: Vec.Vec, +x: U32, want: Bool, r: Bitset.Bitset & Bool) -> Sv:
  (b, t) = r
  Sv{v, b, mrg.emit(o, x, sv.take(t, want))}

def sv.at(b: Bitset.Bitset, o: Vec.Vec, want: Bool, r: Vec.Vec & U32) -> Sv:
  (v, +x) = r
  sv.bit(v, o, x, want, Bitset.test(b, x))

def sv.go(fuel: Nat, +i: U32, +want: Bool, s: Sv) -> Sv:
  match fuel:
    case 0n:
      s
    case 1n++p:
      match s:
        case Sv{v, b, o}:
          sv.go(p, U32.inc(i), want, sv.at(b, o, want, Vec.at(v, i)))

def sv.out(s: Sv) -> Vec.Vec:
  match s:
    case Sv{v, b, o}:
      o

def sieve.n(b: Bitset.Bitset, want: Bool, r: Vec.Vec & U32) -> Vec.Vec:
  (v, n) = r
  sv.out(sv.go(U32.to_nat(n), 0, want, Sv{v, b, Vec.new(0)}))

# sieve: the ids of v whose bit in b is want. The answer is no longer than v,
# which is why a mixed AND keeps the sparse shape.
def sieve(v: Vec.Vec, b: Bitset.Bitset, want: Bool) -> Vec.Vec:
  sieve.n(b, want, Vec.len(v))

# the two writes, without their affinity marks: a template parameter's type has
# to match the binder annotations too
def on(b: Bitset.Bitset, i: U32) -> Bitset.Bitset:
  Bitset.set(b, i)

def off(b: Bitset.Bitset, i: U32) -> Bitset.Bitset:
  Bitset.clear(b, i)

type Pt is Type:
  Pt{v: Vec.Vec, b: Bitset.Bitset}

def pt.set(~f: Bitset.Bitset -> U32 -> Bitset.Bitset, b: Bitset.Bitset, r: Vec.Vec & U32) -> Pt:
  (v, x) = r
  Pt{v, f(b, x)}

def pt.go(~f: Bitset.Bitset -> U32 -> Bitset.Bitset, fuel: Nat, +i: U32, p: Pt) -> Pt:
  match fuel:
    case 0n:
      p
    case 1n++q:
      match p:
        case Pt{v, b}:
          pt.go(~f, q, U32.inc(i), pt.set(~f, b, Vec.at(v, i)))

def pt.out(p: Pt) -> Bitset.Bitset:
  match p:
    case Pt{v, b}:
      b

def paint.n(~f: Bitset.Bitset -> U32 -> Bitset.Bitset, b: Bitset.Bitset, r: Vec.Vec & U32) -> Bitset.Bitset:
  (v, n) = r
  pt.out(pt.go(~f, U32.to_nat(n), 0, Pt{v, b}))

# paint: every id of v written into b by f -- set for a union, clear for a
# difference. One template parameter, so each instance compiles its own write.
def paint(~f: Bitset.Bitset -> U32 -> Bitset.Bitset, v: Vec.Vec, b: Bitset.Bitset) -> Bitset.Bitset:
  paint.n(~f, b, Vec.len(v))

# -- the algebra -------------------------------------------------------------

# and: a sparse side bounds the answer, so a mixed pair sieves that side through
# the other's bits and stays sparse; two dense sets are Bitset's cell loop.
def and(a: Set, b: Set) -> Set:
  match a b:
    case Sparse{x} Sparse{y}:
      Sparse{merge(2, x, y)}
    case Sparse{x} Dense{d}:
      Sparse{sieve(x, d, True{})}
    case Dense{d} Sparse{y}:
      Sparse{sieve(y, d, True{})}
    case Dense{c} Dense{d}:
      Dense{Bitset.and(c, d)}

# or: a dense side absorbs the answer, so a mixed pair paints the sparse ids in
# and stays dense
def or(a: Set, b: Set) -> Set:
  match a b:
    case Sparse{x} Sparse{y}:
      Sparse{merge(7, x, y)}
    case Sparse{x} Dense{d}:
      Dense{paint(~on, x, d)}
    case Dense{d} Sparse{y}:
      Dense{paint(~on, y, d)}
    case Dense{c} Dense{d}:
      Dense{Bitset.or(c, d)}

# andnot: the left side's shape is the answer's, because removing ids never
# grows it
def andnot(a: Set, b: Set) -> Set:
  match a b:
    case Sparse{x} Sparse{y}:
      Sparse{merge(4, x, y)}
    case Sparse{x} Dense{d}:
      Sparse{sieve(x, d, False{})}
    case Dense{c} Sparse{y}:
      Dense{paint(~off, y, c)}
    case Dense{c} Dense{d}:
      Dense{Bitset.andnot(c, d)}

# not: the complement inside 0..n-1. It is andnot against the full universe,
# and the answer is n - |s| ids -- dense by definition whenever s was sparse,
# which is why there is no sparse path here.
def not(s: Set, +n: U32) -> Set:
  andnot(all(n), s)

# -- shape ------------------------------------------------------------------

def densify(s: Set, n: U32) -> Set:
  match s:
    case Sparse{v}:
      Dense{paint(~on, v, Bitset.new(depth(n)))}
    case Dense{b}:
      Dense{b}

def sparsify(s: Set) -> Set:
  match s:
    case Sparse{v}:
      Sparse{v}
    case Dense{b}:
      Sparse{enum(b)}

def opt.if(s: Set, n: U32, big: Bool) -> Set:
  match big:
    case True{}:
      densify(s, n)
    case False{}:
      sparsify(s)

def opt.pick(+n: U32, r: Set & U32) -> Set:
  (s, c) = r
  opt.if(s, n, U32.is_gt(c, U32.shrn(n, 5n)))

# optimize: the cheaper shape for what the set now holds. A sparse set costs one
# word an id; a dense one costs n/32 words whatever it holds. That is Roaring's
# rule with its fixed 4096 replaced by the universe the set is actually over.
def optimize(s: Set, +n: U32) -> Set:
  opt.pick(n, count(s))
