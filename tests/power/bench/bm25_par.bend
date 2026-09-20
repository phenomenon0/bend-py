# bm25, forked: 2^8 shards, each one leaf's own index over its own 16,384
# occurrences and its own 1,000 queries. An Index holds arrays and an array has
# a single owner, so no fork can share one index -- the shard, not the query, is
# the unit of parallel search, which is also how a real cluster does it. The
# shards differ (their corpora come from disjoint key ranges), so the tree fold
# of the 256 leaf checksums is not the fold of 256 equal numbers.
import Base
import ../../../power/vec.bend as Vec
import ../../../power/heap.bend as Heap
import ../../../power/bm25.bend as Bm25

def key(+i: U32) -> U32:
  U32.xor(U32.mul(U32.inc(i), 2654435761), U32.shrn(i, 3n))

# the product of two uniforms over nt, which lands under nt and piles up near 0
def skew(+nt: U32, +a: U32, +b: U32) -> U32:
  U32.div(U32.mul(U32.mod(a, nt), U32.mod(b, nt)), nt)

# -- the corpus --------------------------------------------------------------

type Cp is Type:
  Cp{t: Vec.Vec, d: Vec.Vec}

def cp.b(+nt: U32, +nd: U32, t: Vec.Vec, d: Vec.Vec, +a: U32, +b: U32) -> Cp:
  Cp{Vec.push(t, skew(nt, a, b)), Vec.push(d, U32.mod(key(b), nd))}

def cp.one(+nt: U32, +nd: U32, t: Vec.Vec, d: Vec.Vec, +a: U32) -> Cp:
  cp.b(nt, nd, t, d, a, key(a))

def cp.go(fuel: Nat, +i: U32, +nt: U32, +nd: U32, x: Cp) -> Cp:
  match fuel:
    case 0n:
      x
    case 1n++p:
      match x:
        case Cp{t, d}:
          cp.go(p, U32.inc(i), nt, nd, cp.one(nt, nd, t, d, key(i)))

def cp.mk(+nt: U32, +nd: U32, x: Cp) -> Bm25.Index:
  match x:
    case Cp{t, d}:
      Bm25.build(t, d, nt, nd, 1.2d, 0.75d)

def index(fuel: Nat, +lo: U32, +nt: U32, +nd: U32) -> Bm25.Index:
  cp.mk(nt, nd, cp.go(fuel, lo, nt, nd, Cp{Vec.new(0), Vec.new(0)}))

# -- the queries -------------------------------------------------------------

def qterm(+nt: U32, +a: U32) -> U32:
  skew(nt, a, key(a))

def qv.go(fuel: Nat, +s: U32, +nt: U32, v: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      v
    case 1n++p:
      qv.go(p, U32.inc(s), nt, Vec.push(v, qterm(nt, key(s))))

def qvec(+s: U32, +nt: U32) -> Vec.Vec:
  qv.go(8n, s, nt, Vec.new(0))

def fold(xs: List<&2, Heap.Entry>, acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case Con{Heap.Entry{k, x}, t}:
      fold(t, U32.add(U32.mul(acc, 31), U32.xor(k, x)))

def rout(acc: U32, r: Vec.Vec & List<&2, Heap.Entry>) -> U32:
  (v, xs) = r
  fold(xs, acc)

type Qs is Type:
  Qs{ix: Bm25.Index, acc: U32}

def qs.rank(acc: U32, r: Bm25.Index & Vec.Vec) -> Qs:
  (ix, v) = r
  Qs{ix, rout(acc, Bm25.rank(v, 8))}

def qs.one(+s: U32, +nt: U32, x: Qs) -> Qs:
  match x:
    case Qs{ix, acc}:
      qs.rank(acc, Bm25.query(ix, qvec(s, nt)))

def qs.go(fuel: Nat, +s: U32, +nt: U32, x: Qs) -> Qs:
  match fuel:
    case 0n:
      x
    case 1n++p:
      qs.go(p, U32.add(s, 8), nt, qs.one(s, nt, x))

def qs.out(x: Qs) -> U32:
  match x:
    case Qs{ix, acc}:
      acc

# one shard: index occ occurrences from key(lo + i), then qn queries whose term
# hashes start 2^30 past this shard's corpus seeds, so the two streams are
# disjoint and no two shards draw the same queries
def shard(occ: Nat, qn: Nat, +lo: U32, +nt: U32, +nd: U32) -> U32:
  qs.out(qs.go(qn, U32.add(lo, 1073741824), nt, Qs{index(occ, lo, nt, nd), 0}))

def rot7(+v: U32) -> U32:
  U32.or(U32.shln(v, 7n), U32.shrn(v, 25n))

# json_par's mixer, and for the same reason one turn sharper: a leaf checksum is
# itself an acc * 31 + x fold, and 31 is -1 mod 32, so every leaf here comes out
# congruent mod 32 even though the shards differ. A plain a * 31 + b tree then
# shifts five zero bits in a level and the 256 leaves fold to exactly 0 -- the
# rotate is what stops the low bits from running out
def mix(+acc: U32, +x: U32) -> U32:
  rot7(U32.add(U32.mul(acc, 31), x))

def par(d: Nat, +lo: U32, +n: U32) -> U32:
  match d:
    case 0n:
      shard(16384n, 1000n, lo, 256, 256)
    case 1n++p:
      +h = U32.shr(n)
      a b = par(p, lo, h) par(p, U32.add(lo, h), h)
      mix(a, b)

def main() -> U32:
  par(8n, 0, 4194304)
