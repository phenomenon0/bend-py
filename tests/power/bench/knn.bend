# knn, sequential: one store of 65,536 vectors in 64 dimensions, 64 queries, the
# 10 nearest of each by squared L2. 268 million multiply-adds through one
# Array<F32>, which is the number this bench is about -- everything else here is
# the harness that makes the answer checkable against twin_knn.c.
#
# There is no fork in this file, so its 1T and 16T columns are the same run
# twice; knn_par.bend is where the threads are.
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

# the query hashes start 2^30 past the store's, so no query is a stored row
def main() -> U32:
  qs.out(qs.go(64n, 0, 10, Qs{mk(0, 65536, 64, 22n), mk(1073741824, 64, 64, 12n), 0}))
