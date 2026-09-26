# Postings' set algebra over a 65,536-document universe: 4,096 rounds, 8 sets built
# and 4 operations a round, every member id of every answer folded in.
#
# The four operations are the four distinct paths through `and` and `or`, and
# they are chosen to be those rather than to be four calls:
#
#   and(sparse, sparse)  one left-to-right merge, mode 2
#   or (dense,  dense)   Bitset's own cell loop, 32 ids an iteration
#   and(sparse, dense)   sieve -- the sparse side bounds the answer
#   or (sparse, dense)   paint -- the dense side absorbs it
#
# `andnot` is not a fifth path: it is the same merge at mode 4, the same sieve
# at want=False and the same paint through `off`.
#
# A set has one owner, so an operation consumes both operands and every round
# builds its own. That is not overhead the bench adds -- it is what using this
# module costs, and the C twin builds the same sets the same way.
#
# 512 ids is under the 65,536/32 = 2,048 the optimizer densifies above, and
# 4,096 is over it, so `optimize` takes its sparse arm four times a round and
# its dense arm four times. The container decision is the point of the module,
# and it executes here rather than being assumed.
import Base
import ../../../power/postings.bend as P
import ../../../power/vec.bend as V

# the multiply alone is not enough. `2654435761 mod 64` is 49 and `512 * 49` is
# a multiple of 64, so the low six bits of `(s+1) * 2654435761` repeat every 512
# seeds -- and the low six bits are the only ones the three parameters below
# read. Folding the high half down breaks that: s and s+512 now differ. The
# first version of this file did not, and every 512th seed rebuilt an identical
# set, which the parallel twin caught by returning a checksum of exactly zero.
def mix(+h: U32) -> U32:
  U32.xor(h, U32.shrn(h, 16n))

def hsh(+s: U32) -> U32:
  mix(U32.mul(U32.inc(s), 2654435761))

# a start in 0..63 and a stride in 1..64 (sparse) or 1..8 (dense). The widest
# run a sparse set can reach is 63 + 511*64 = 32,767 and a dense one
# 63 + 4,095*8 = 32,823, both inside the universe -- an id at or past capacity
# would wrap into the wrong cell rather than read as absent.
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

# the answer's ids, in order, whatever shape held them: `to_vec` enumerates a
# dense set low to high. Folding contents and not words is what lets the twin
# pick its own layout and still have to agree id for id.
def fold(acc: U32, s: P.Set) -> U32:
  fin(acc, V.len(P.to_vec(s)))

def rnd(+b: U32, acc: U32) -> U32:
  fold(fold(fold(fold(acc,
    P.and(sp(b), sp(U32.add(b, 1)))),
    P.or(dn(U32.add(b, 2)), dn(U32.add(b, 3)))),
    P.and(sp(U32.add(b, 4)), dn(U32.add(b, 5)))),
    P.or(sp(U32.add(b, 6)), dn(U32.add(b, 7))))

def rep(fuel: Nat, +i: U32, acc: U32) -> U32:
  match fuel:
    case 0n:
      acc
    case 1n++p:
      rep(p, U32.inc(i), rnd(U32.mul(i, 8), acc))

def main() -> U32:
  rep(4096n, 0, 0)
