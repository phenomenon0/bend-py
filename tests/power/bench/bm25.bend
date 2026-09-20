# 4,000,000 occurrences over 16,384 terms and 2,048 documents indexed once, then
# 250,000 queries of 8 terms each ranked to their best 8 -- the whole search
# loop, build and query, in one number. The vocabulary is skewed the way a real
# one is: a term is the product of two hashes divided by nt, so the low term ids
# carry long rows and most terms carry one posting, and the queries draw their
# terms from the same distribution, so a query hits the fat rows as often as a
# real one does.
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
# hashes start at 2^30, past every corpus seed, so the two streams are disjoint
def shard(occ: Nat, qn: Nat, +lo: U32, +nt: U32, +nd: U32) -> U32:
  qs.out(qs.go(qn, U32.add(lo, 1073741824), nt, Qs{index(occ, lo, nt, nd), 0}))

def main() -> U32:
  shard(4000000n, 250000n, 0, 16384, 2048)
