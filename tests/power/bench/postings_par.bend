# The same set algebra as postings.bend, forked: 256 independent shards of 32
# rounds each, combined up a balanced tree of depth 8.
#
# postings.bend measures what the four operations cost. This file measures
# whether they fork, and the answer is not obvious from that one: a set holds
# an Array, an Array has one owner, and every operation here consumes both its
# operands -- so nothing is shared between shards and nothing can be, which is
# the condition a fork needs. What is being tested is that the runtime actually
# spreads them, not that the algorithm allows it.
#
# The shards take disjoint seed ranges -- shard `lo` gets lo*256 .. lo*256+255,
# 8,192 rounds over the whole 0..65,535 span -- and with the generator below
# that means disjoint work. It did not before: see the note on `mix`.
#
# The combine is `mix` at every node, so the answer pins the tree's shape as
# well as its leaves -- a shard landing in the wrong slot changes it.
import Base
import ../../../power/postings.bend as P
import ../../../power/vec.bend as V

# the multiply alone is not enough. `2654435761 mod 64` is 49 and `512 * 49` is
# a multiple of 64, so the low six bits of `(s+1) * 2654435761` repeat every 512
# seeds -- and the low six bits are the only ones the three parameters below
# read. Folding the high half down breaks that: s and s+512 now differ. The
# first version of this file did not, and every 512th seed rebuilt an identical
# set, which the parallel twin caught by returning a checksum of exactly zero.
def fold_hi(+h: U32) -> U32:
  U32.xor(h, U32.shrn(h, 16n))

def hsh(+s: U32) -> U32:
  fold_hi(U32.mul(U32.inc(s), 2654435761))

def bg(+s: U32) -> U32:
  U32.and(hsh(s), 63)

def st(+s: U32) -> U32:
  U32.inc(U32.and(U32.shrn(hsh(s), 8n), 63))

def st8(+s: U32) -> U32:
  U32.inc(U32.and(U32.shrn(hsh(s), 20n), 7))

def mk.go(fuel: Nat, +x: U32, +d: U32, s: P.Set) -> P.Set:
  match fuel:
    case 0n:
      s
    case 1n++p:
      mk.go(p, U32.add(x, d), d, P.add(s, x))

def mk(k: Nat, x: U32, d: U32) -> P.Set:
  P.optimize(mk.go(k, x, d, P.Sparse{V.new(0)}), 65536)

def sp(+s: U32) -> P.Set:
  mk(512n, bg(s), st(s))

def dn(+s: U32) -> P.Set:
  mk(4096n, bg(s), st8(s))

def one(acc: U32, r: V.Vec & U32) -> V.Vec & U32:
  (v, x) = r
  (v, U32.add(U32.mul(acc, 31), x))

def step(i: U32, va: V.Vec & U32) -> V.Vec & U32:
  (v, acc) = va
  one(acc, V.at(v, i))

def go(fuel: Nat, +i: U32, va: V.Vec & U32) -> V.Vec & U32:
  match fuel:
    case 0n:
      va
    case 1n++p:
      go(p, U32.inc(i), step(i, va))

def out(va: V.Vec & U32) -> U32:
  (v, acc) = va
  acc

def fin(acc: U32, r: V.Vec & U32) -> U32:
  (v, n) = r
  out(go(U32.to_nat(n), 0, (v, acc)))

def fold(acc: U32, s: P.Set) -> U32:
  fin(acc, V.len(P.to_vec(s)))

def rnd(+b: U32, acc: U32) -> U32:
  fold(fold(fold(fold(acc,
    P.and(sp(b), sp(U32.add(b, 1)))),
    P.or(dn(U32.add(b, 2)), dn(U32.add(b, 3)))),
    P.and(sp(U32.add(b, 4)), dn(U32.add(b, 5)))),
    P.or(sp(U32.add(b, 6)), dn(U32.add(b, 7))))

def rot7(+v: U32) -> U32:
  U32.or(U32.shln(v, 7n), U32.shrn(v, 25n))

# the suite's mixer. power-6 states the trap as "a leaf checksum is itself an
# acc * 31 + x fold and 31 is -1 mod 32, so every leaf shares a residue and a
# plain a * 31 + b tree runs the low bits out". That premise does not hold
# here -- measured, these 256 leaves cover all 32 residues mod 32, because the
# four answers differ in length shard to shard and the fold length is what sets
# the residue. The plain combine gave a sound 94643560. The mixer is used
# anyway: every other _par twin in this suite mixes, the residue spread is a
# property of the seeds rather than of the bench, and a rule that holds only
# while an incidental measurement holds is not one to lean a checksum on.
# Checked by perturbing leaf 137 by +1, +32, +1024 and +2^31: each changes it.
def mix(+acc: U32, +x: U32) -> U32:
  rot7(U32.add(U32.mul(acc, 31), x))

def batch(fuel: Nat, +b: U32, acc: U32) -> U32:
  match fuel:
    case 0n:
      acc
    case 1n++p:
      batch(p, U32.add(b, 8), rnd(b, acc))

def leaf(lo: U32) -> U32:
  batch(32n, U32.mul(lo, 256), 0)

def tree(k: Nat, +lo: U32) -> U32:
  match k:
    case 0n:
      leaf(lo)
    case 1n++p:
      a b = tree(p, U32.mul(lo, 2)) tree(p, U32.inc(U32.mul(lo, 2)))
      mix(a, b)

def main() -> U32:
  tree(8n, 0)
