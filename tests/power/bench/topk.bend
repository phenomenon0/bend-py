# the best 100 of 400,000,000 keyed offers
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
  out(TopK.drain(feed(400000000n, 0, TopK.new(100))))
