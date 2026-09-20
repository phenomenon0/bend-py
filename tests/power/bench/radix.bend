# 8,000,000 keys sorted four times, each sort folded into the checksum -- the
# fold is a * 31 + x, so any permutation error changes it
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

def sorted(acc: U32, v: Vec.Vec) -> Vec.Vec & U32:
  fold.go(8000000n, 0, (Radix.sort(v), acc))

def step(va: Vec.Vec & U32) -> Vec.Vec & U32:
  (v, acc) = va
  sorted(acc, v)

def rep(k: Nat, va: Vec.Vec & U32) -> Vec.Vec & U32:
  match k:
    case 0n:
      va
    case 1n++p:
      rep(p, step(va))

def snd(va: Vec.Vec & U32) -> U32:
  (v, acc) = va
  acc

def main() -> U32:
  snd(rep(4n, (fill(8000000n, 0, Vec.new(0)), 0)))
