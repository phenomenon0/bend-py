# BLAKE3, forked: 2^16 leaves, each its own 1 KiB chunk with its own chunk
# number, joined by BLAKE3's own parent compression up a perfect binary tree.
# 64 MiB, 1,048,576 compressions, and the tree of joins is not a checksum bolted
# on top of the leaves -- it is the hash.
#
# This is the one place in the power benches where the parallel answer is not
# merely equal to the sequential one by arithmetic luck: BLAKE3's tree mode is
# defined so that a message cut at chunk boundaries, hashed in any order, and
# joined left to right gives the identical 32 bytes a single pass gives. The C
# twin therefore does not reproduce the fork. It hashes the 64 MiB serially,
# through a chunk stack, and the row passes only if 65,536 independent leaves
# and one sequential walk land on the same root.
#
# The leaf is a whole chunk because a chunk is BLAKE3's smallest independent
# unit: its counter is baked into every compression, so a half chunk has no
# chaining value of its own and cannot be a leaf at all.
import Base
import ../../../power/bytes.bend as Bytes
import ../../../power/blake3.bend as B3

def key(+i: U32) -> U32:
  U32.xor(U32.mul(U32.inc(i), 2654435761), U32.shrn(i, 3n))

def fill(fuel: Nat, +i: U32, b: Bytes.Bytes) -> Bytes.Bytes:
  match fuel:
    case 0n:
      b
    case 1n++p:
      fill(p, U32.inc(i), Bytes.push(b, key(i)))

def rot7(+v: U32) -> U32:
  U32.or(U32.shln(v, 7n), U32.shrn(v, 25n))

def mix(+acc: U32, +x: U32) -> U32:
  rot7(U32.add(U32.mul(acc, 31), x))

def cvmix(+acc: U32, c: B3.Cv) -> U32:
  match c:
    case B3.Cv{a0, a1, a2, a3, a4, a5, a6, a7}:
      mix(mix(mix(mix(mix(mix(mix(mix(acc, a0), a1), a2), a3), a4), a5), a6), a7)

def drop(r: Bytes.Bytes & B3.Cv) -> B3.Cv:
  (b, c) = r
  c

# leaf s owns 1,024 bytes and nothing else does: the buffer is built inside the
# leaf, from key indices s * 1024 up, so byte i of leaf s is byte s * 1024 + i
# of the message the twin hashes, and no two lanes ever touch one Array.
def leaf(+s: U32, +fl: U32) -> B3.Cv:
  drop(B3.chunk(fill(1024n, U32.shln(s, 10n), Bytes.new()), 0, 1024, s, fl))

def par(d: Nat, +s: U32) -> B3.Cv:
  match d:
    case 0n:
      leaf(s, 0)
    case 1n++p:
      +w = U32.shln(1, p)
      a b = par(p, s) par(p, U32.add(s, w))
      B3.parent(a, b, 0)

# the same tree, with ROOT on the final join alone. A one-leaf tree is a single
# chunk that is the whole message, so ROOT rides the chunk instead.
def root(d: Nat, +s: U32) -> B3.Cv:
  match d:
    case 0n:
      leaf(s, 8)
    case 1n++p:
      +w = U32.shln(1, p)
      a b = par(p, s) par(p, U32.add(s, w))
      B3.parent(a, b, 8)

def main() -> U32:
  cvmix(0, root(16n, 0))
