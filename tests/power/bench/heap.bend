# push 8,000,000 keyed entries, drain them all, fold the order
import Base
import ../../../power/heap.bend as Heap

def key(+i: U32) -> U32:
  U32.xor(U32.mul(U32.inc(i), 2654435761), U32.shrn(i, 3n))

def fill(fuel: Nat, +i: U32, h: Heap.Heap) -> Heap.Heap:
  match fuel:
    case 0n:
      h
    case 1n++p:
      fill(p, U32.inc(i), Heap.push(h, U32.and(key(i), 1048575), i))

def fold(xs: List<&2, Heap.Entry>, acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case Con{e, t}:
      match e:
        case Heap.Entry{k, x}:
          fold(t, U32.add(U32.mul(acc, 31), U32.xor(k, x)))

def out(r: Heap.Heap & List<&2, Heap.Entry>) -> U32:
  (h, xs) = r
  fold(xs, 0)

def main() -> U32:
  out(Heap.drain(fill(8000000n, 0, Heap.new())))
