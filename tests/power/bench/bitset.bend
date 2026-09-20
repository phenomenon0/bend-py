# 2^27 bits: set 16,000,000 keyed bits, then 80 x (xor with a fresh one-bit set,
# count)
import Base
import ../../../power/bitset.bend as Bitset

def key(+i: U32) -> U32:
  U32.and(U32.xor(U32.mul(U32.inc(i), 2654435761), U32.shrn(i, 3n)), 134217727)

def fill(fuel: Nat, +i: U32, b: Bitset.Bitset) -> Bitset.Bitset:
  match fuel:
    case 0n:
      b
    case 1n++p:
      fill(p, U32.inc(i), Bitset.set(b, key(i)))

def add(acc: U32, r: Bitset.Bitset & U32) -> Bitset.Bitset & U32:
  (b, n) = r
  (b, U32.add(U32.mul(acc, 31), n))

def step(+k: U32, ba: Bitset.Bitset & U32) -> Bitset.Bitset & U32:
  (b, acc) = ba
  add(acc, Bitset.count(Bitset.xor(b, Bitset.set(Bitset.new(22n), key(k)))))

def rep(k: Nat, ba: Bitset.Bitset & U32) -> Bitset.Bitset & U32:
  match k:
    case 0n:
      ba
    case 1n++p:
      rep(p, step(U32.from_nat(p), ba))

def snd(ba: Bitset.Bitset & U32) -> U32:
  (b, acc) = ba
  acc

def main() -> U32:
  snd(rep(80n, (fill(16000000n, 0, Bitset.new(22n)), 0)))
