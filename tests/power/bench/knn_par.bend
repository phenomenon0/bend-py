# knn, forked: 2^6 shards, each one leaf's own store of 2,048 vectors in 64
# dimensions and its own 128 queries: 1.07 billion multiply-adds, four times
# what knn.bend does sequentially, cut 64 ways.
#
# The shard is the unit and not the query, for the same reason bm25_par.bend
# gives: a Flat holds an Array and an Array has a single owner, so no two lanes
# can read one store. A shared store is not merely unidiomatic here -- a value
# every lane reads costs an atomic per read, which on a hot cell loop is the
# whole budget. Sharding the store is also how a real vector database scales
# past one machine, so the shape is the honest one.
#
# The shards differ -- their hash ranges are disjoint -- so the tree fold of the
# 64 leaf checksums is not the fold of 64 equal numbers.
import Base
import ../../../power/knn.bend as Knn
import ../../../power/heap.bend as Heap

# the same hash and the same scaling the C twin uses: a value in [-32, 32) in
# steps of 1/128, exact in F32, so the two sides start from identical floats.
# The thirteen bits come off the TOP of the hash, not from a mod: a multiply
# moves information upward only, so `% 8192` would make v blind to any base that
# is a multiple of 2^13 -- which is every base here -- and this bench was
# written that way first, with its queries byte-identical to its store and every
# shard identical to every other, the C twin agreeing throughout because it
# reproduced the same degenerate data.
def h(+p: U32) -> U32:
  U32.xor(U32.mul(U32.inc(p), 2654435761), U32.shrn(p, 3n))

def v(+p: U32) -> F32:
  F32.div(F32.sub(U32.to_f32(U32.shrn(h(p), 19n)), 4096.0), 128.0)

def mk.go(fuel: Nat, +p: U32, f: Knn.Flat) -> Knn.Flat:
  match fuel:
    case 0n:
      f
    case 1n++q:
      mk.go(q, U32.inc(p), Knn.push(f, v(p)))

def mk(+base: U32, +n: U32, +d: U32, depth: Nat) -> Knn.Flat:
  mk.go(U32.to_nat(U32.mul(n, d)), base, Knn.sized(d, depth))

def rot7(+v: U32) -> U32:
  U32.or(U32.shln(v, 7n), U32.shrn(v, 25n))

# json_par's mixer, one turn sharper for the reason bm25_par states: a leaf
# checksum is itself an acc * 31 + x fold and 31 is -1 mod 32, so a plain
# a * 31 + b tree runs the low bits out and folds every leaf to 0
def mix(+acc: U32, +x: U32) -> U32:
  rot7(U32.add(U32.mul(acc, 31), x))

def fold(xs: List<&2, Heap.Entry>, acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case Con{Heap.Entry{k, x}, t}:
      fold(t, mix(acc, U32.xor(k, x)))

type Qs is Type:
  Qs{f: Knn.Flat, q: Knn.Flat, acc: U32}

def qs.one(acc: U32, r: Knn.Flat & Knn.Flat & List<&2, Heap.Entry>) -> Qs:
  (f, q, xs) = r
  Qs{f, q, fold(xs, acc)}

def qs.go(fuel: Nat, +j: U32, +k: U32, x: Qs) -> Qs:
  match fuel:
    case 0n:
      x
    case 1n++p:
      match x:
        case Qs{f, q, acc}:
          qs.go(p, U32.inc(j), k, qs.one(acc, Knn.search_l2(f, q, j, k)))

def qs.out(x: Qs) -> U32:
  match x:
    case Qs{f, q, acc}:
      acc

# one shard: 2,048 vectors hashed from base, 128 queries hashed from 2^30 past
# it, so the two streams are disjoint and no two shards draw the same vectors
def shard.b(+b: U32) -> U32:
  qs.out(qs.go(128n, 0, 10, Qs{mk(b, 2048, 64, 17n), mk(U32.add(1073741824, b), 128, 64, 13n), 0}))

def shard(+s: U32) -> U32:
  shard.b(U32.shln(s, 20n))

def par(d: Nat, +s: U32) -> U32:
  match d:
    case 0n:
      shard(s)
    case 1n++p:
      +w = U32.shln(1, p)
      a b = par(p, s) par(p, U32.add(s, w))
      mix(a, b)

def main() -> U32:
  par(6n, 0)
