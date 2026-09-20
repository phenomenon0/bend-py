# push 64,000,000 keys, then read every one back four times
import Base
import ../../../power/vec.bend as Vec

def key(+i: U32) -> U32:
  U32.xor(U32.mul(U32.inc(i), 2654435761), U32.shrn(i, 3n))

def fill(fuel: Nat, +i: U32, v: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      v
    case 1n++p:
      fill(p, U32.inc(i), Vec.push(v, key(i)))

def add(+i: U32, acc: U32, r: Vec.Vec & U32) -> Vec.Vec & U32:
  (v, x) = r
  (v, U32.add(U32.mul(acc, 31), x))

def step(+i: U32, va: Vec.Vec & U32) -> Vec.Vec & U32:
  (v, acc) = va
  add(i, acc, Vec.at(v, i))

def sum(fuel: Nat, +i: U32, va: Vec.Vec & U32) -> Vec.Vec & U32:
  match fuel:
    case 0n:
      va
    case 1n++p:
      sum(p, U32.inc(i), step(i, va))

def rep(k: Nat, va: Vec.Vec & U32) -> Vec.Vec & U32:
  match k:
    case 0n:
      va
    case 1n++p:
      rep(p, sum(64000000n, 0, va))

def snd(va: Vec.Vec & U32) -> U32:
  (v, acc) = va
  acc

def main() -> U32:
  snd(rep(4n, (fill(64000000n, 0, Vec.new(0)), 0)))
