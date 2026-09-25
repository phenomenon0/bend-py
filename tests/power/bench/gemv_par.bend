# gemv, forked: one 8,192 x 512 weight matrix cut into 2^6 row blocks of 128
# rows, and 128 decode steps against it -- 537 million multiply-adds, four
# times what gemv.bend does sequentially, cut 64 ways.
#
# The row block is the unit for the reason knn_par.bend and bm25_par.bend give:
# a Flat holds an Array and an Array has one owner, so no two lanes can read one
# matrix. Row-blocking is also how a real GEMV shards -- every row is
# independent, the activation is broadcast, and nothing is reduced across
# shards -- so the shape is the honest one rather than a concession.
#
# The activation vectors do NOT depend on the shard: every lane hashes the same
# 128 vectors, which is what a broadcast is. The weight rows do -- each shard's
# hash range is its own -- so the 64 leaf checksums differ and the tree fold is
# not the fold of 64 equal numbers.
#
# This file imports gemv.bend rather than restating its loop, which is a
# deliberate break with the other _par twins here (they duplicate their
# sequential file's helpers). A bench whose whole point is the ratio between
# two rows should not be able to drift between them: `ip` over one flat block
# is the thing being measured, and there is exactly one copy of the code that
# calls it.
import Base
import ./gemv.bend as Gemv

def rot7(+v: U32) -> U32:
  U32.or(U32.shln(v, 7n), U32.shrn(v, 25n))

# gemv.bend's mixer, and it has to be: a leaf checksum is itself an acc * 31 + x
# fold, and 31 is -1 mod 32, so a plain a * 31 + b tree runs the low bits out
# and folds every leaf to 0 (json_par's finding)
def mix(+acc: U32, +x: U32) -> U32:
  rot7(U32.add(U32.mul(acc, 31), x))

# shard s owns rows [s * 128, (s + 1) * 128) of the 8,192: 128 * 512 = 2^16
# floats, so its hash base is s << 16 and no two shards draw the same weights
def shard(+s: U32) -> U32:
  Gemv.gemv(128n, U32.shln(s, 16n), 128, 512, 16n, 7n, 9n)

def par(d: Nat, +s: U32) -> U32:
  match d:
    case 0n:
      shard(s)
    case 1n++p:
      +w = U32.shln(1, p)
      a b = par(p, s) par(p, U32.add(s, w))
      mix(a, b)

def main() -> U32:
  par(6n, 0)
