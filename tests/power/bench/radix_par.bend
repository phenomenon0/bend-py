# radix, forked: 2^8 blocks of 31,250 keys, each sorted four times in its own
# leaf -- the sequential bench's work exactly, but as 256 sorted runs -- the
# scatter's cursor table is shared state, so a fork can only own a whole block
# (docs/omen/lanes/power-1.md). Merging the runs is a k-way merge, not this lane.
import Base
import ../../../power/vec.bend as Vec
import ../../../power/radix.bend as Radix

def key(+i: U32) -> U32:
  U32.xor(U32.mul(U32.inc(i), 2654435761), U32.shrn(i, 3n))

def fill(fuel: Nat, +i: U32, v: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      v
    case 1n++p:
      fill(p, U32.inc(i), Vec.push(v, key(i)))

def hash(acc: U32, r: Vec.Vec & U32) -> Vec.Vec & U32:
  (v, x) = r
  (v, U32.add(U32.mul(acc, 31), x))

def fold.at(+i: U32, va: Vec.Vec & U32) -> Vec.Vec & U32:
  (v, acc) = va
  hash(acc, Vec.at(v, i))

def fold.go(fuel: Nat, +i: U32, va: Vec.Vec & U32) -> Vec.Vec & U32:
  match fuel:
    case 0n:
      va
    case 1n++p:
      fold.go(p, U32.inc(i), fold.at(i, va))

def snd(va: Vec.Vec & U32) -> U32:
  (v, acc) = va
  acc

def sorted(acc: U32, v: Vec.Vec) -> Vec.Vec & U32:
  fold.go(31250n, 0, (Radix.sort(v), acc))

def step(va: Vec.Vec & U32) -> Vec.Vec & U32:
  (v, acc) = va
  sorted(acc, v)

def rep(k: Nat, va: Vec.Vec & U32) -> Vec.Vec & U32:
  match k:
    case 0n:
      va
    case 1n++p:
      rep(p, step(va))

def block(+lo: U32) -> U32:
  snd(rep(4n, (fill(31250n, lo, Vec.new(0)), 0)))

def par(d: Nat, +lo: U32, +n: U32) -> U32:
  match d:
    case 0n:
      block(lo)
    case 1n++p:
      +h = U32.shr(n)
      a b = par(p, lo, h) par(p, U32.add(lo, h), h)
      U32.add(U32.mul(a, 31), b)

def main() -> U32:
  par(8n, 0, 8000000)
