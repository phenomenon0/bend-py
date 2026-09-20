# scan, forked: 2^8 blocks of 250,000, each built and prefix-summed twenty times
# in its own leaf. One shared Array cannot fork (a fork copies both halves,
# docs/omen/lanes/power-1.md), so the block is leaf-private: the shape every
# array primitive here parallelizes under.
import Base
import ../../../power/vec.bend as Vec
import ../../../power/scan.bend as Scan

def key(+i: U32) -> U32:
  U32.xor(U32.mul(U32.inc(i), 2654435761), U32.shrn(i, 3n))

def fill(fuel: Nat, +i: U32, v: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      v
    case 1n++p:
      fill(p, U32.inc(i), Vec.push(v, key(i)))

def again(acc: U32, r: Vec.Vec & U32) -> Vec.Vec & U32:
  (v, t) = r
  (v, U32.add(U32.mul(acc, 31), t))

def step(va: Vec.Vec & U32) -> Vec.Vec & U32:
  (v, acc) = va
  again(acc, Scan.sums(v))

def rep(k: Nat, va: Vec.Vec & U32) -> Vec.Vec & U32:
  match k:
    case 0n:
      va
    case 1n++p:
      rep(p, step(va))

def snd(va: Vec.Vec & U32) -> U32:
  (v, acc) = va
  acc

def block(+lo: U32) -> U32:
  snd(rep(20n, (fill(250000n, lo, Vec.new(0)), 0)))

def par(d: Nat, +lo: U32, +n: U32) -> U32:
  match d:
    case 0n:
      block(lo)
    case 1n++p:
      +h = U32.shr(n)
      a b = par(p, lo, h) par(p, U32.add(lo, h), h)
      U32.add(U32.mul(a, 31), b)

def main() -> U32:
  par(8n, 0, 64000000)
