# 256 independent 16,384-point transforms, forked up a balanced tree and combined
# a*31 + b. The single-transform bench already forks -- `go` recurses into both
# halves at once -- so this one asks the other question: what happens when the
# work is embarrassingly parallel to begin with and the runtime is not being
# asked to split one buffer.
import Base
import ../../../power/fft.bend as F

def key(+s: U32, +i: U32) -> U32:
  U32.xor(U32.mul(U32.inc(U32.add(i, s)), 2654435761), U32.shrn(i, 3n))

def val(+s: U32, +i: U32) -> F32:
  F32.div(U32.to_f32(U32.and(key(s, i), 65535)), 65536.0)

def fill(fuel: Nat, +s: U32, +i: U32, g: F.Sig) -> F.Sig:
  match fuel:
    case 0n:
      g
    case 1n++p:
      fill(p, s, U32.inc(i), F.put(g, i, F.C{val(s, i), 0.0}))

def fold1(acc: U32, +x: F.C) -> U32:
  U32.add(U32.mul(U32.add(U32.mul(acc, 31), F32.bits(F.c.re(x))), 31), F32.bits(F.c.im(x)))

def acc1(acc: U32, r: F.Sig & F.C) -> F.Sig & U32:
  (s, x) = r
  (s, fold1(acc, x))

def step(+i: U32, sa: F.Sig & U32) -> F.Sig & U32:
  (s, acc) = sa
  acc1(acc, F.at(s, i))

def walk(fuel: Nat, +i: U32, sa: F.Sig & U32) -> F.Sig & U32:
  match fuel:
    case 0n:
      sa
    case 1n++p:
      walk(p, U32.inc(i), step(i, sa))

def snd(sa: F.Sig & U32) -> U32:
  (s, acc) = sa
  acc

# one leaf: seed it, transform it, fold its bits. Nothing is shared with a
# sibling, so the only thing the fork has to get right is the combine.
def leaf(+s: U32) -> U32:
  snd(walk(16384n, 0, (F.fft(fill(16384n, s, 0, F.new(14n))), 0)))

def tree(k: Nat, +lo: U32) -> U32:
  match k:
    case 0n:
      leaf(lo)
    case 1n++p:
      a b = tree(p, U32.mul(lo, 2)) tree(p, U32.inc(U32.mul(lo, 2)))
      U32.add(U32.mul(a, 31), b)

def main() -> U32:
  tree(8n, 0)
