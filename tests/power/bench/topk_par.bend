# topk, forked: 2^8 ranges each keep their own best 100, and the pairs merge on
# the way up. Entries order by (key, val), so the merged answer is the whole
# stream's, whatever the split.
import Base
import ../../../power/heap.bend as Heap
import ../../../power/topk.bend as TopK

def key(+i: U32) -> U32:
  U32.xor(U32.mul(U32.inc(i), 2654435761), U32.shrn(i, 3n))

def feed(fuel: Nat, +i: U32, t: TopK.TopK) -> TopK.TopK:
  match fuel:
    case 0n:
      t
    case 1n++p:
      feed(p, U32.inc(i), TopK.offer(t, key(i), i))

def par(d: Nat, +lo: U32, +n: U32) -> TopK.TopK:
  match d:
    case 0n:
      feed(U32.to_nat(n), lo, TopK.new(100))
    case 1n++p:
      +h = U32.shr(n)
      a b = par(p, lo, h) par(p, U32.add(lo, h), h)
      TopK.merge(a, b)

def fold(xs: List<&2, Heap.Entry>, acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case Con{e, t}:
      match e:
        case Heap.Entry{k, x}:
          fold(t, U32.add(U32.mul(acc, 31), U32.xor(k, x)))

def out(r: TopK.TopK & List<&2, Heap.Entry>) -> U32:
  (t, xs) = r
  fold(xs, 0)

def main() -> U32:
  out(TopK.drain(par(8n, 0, 400000000)))
