# FastCDC, forked: 2^8 shards, each its own 64 KiB buffer cut four times, at
# 256 B, 1 KiB, 4 KiB and 16 KiB. 64 MiB of rolling hash, the same total the
# sequential bench does, split 256 ways.
#
# The shard is the unit for the reason bm25_par.bend and knn_par.bend give: a
# Bytes holds an Array and an Array has a single owner, so no two lanes can
# scan one buffer. Here that is not a concession -- it is how deduplication is
# actually run. A chunker is applied to a file, and a store has many files, so
# the honest parallel shape is a lane per file, which is exactly a lane per
# shard.
#
# The shards differ: shard s fills from key index s * 65,536, so the 256 leaf
# checksums are 256 different numbers and the tree fold is not 256 copies of one.
#
# 256 and not the 64 the other _par benches use: at 64 this row scaled 3.4x on
# sixteen threads and at 256 it scales 6.8x, on identical total work. The
# scheduler wants more tasks than it has threads by a wider margin than four.
import Base
import ../../../power/bytes.bend as Bytes
import ../../../power/cdc.bend as Cdc

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

# the leaf checksum is itself an acc * 31 + x fold, and 31 is -1 mod 32, so a
# plain a * 31 + b tree runs the low bits out and folds every leaf to 0; the
# extra turn is json_par's fix
def mix(+acc: U32, +x: U32) -> U32:
  rot7(U32.add(U32.mul(acc, 31), x))

# the join, and it is not mix. Multiplying by 31 destroys the low five bits of
# the left operand every level, and rot7 only moves the damage seven places on;
# over six levels the thirty wrecked positions still leave two clean ones, which
# is why the depth-6 benches get away with mix, and over eight levels forty
# positions cover the word and every tree folds to 0 -- which this bench and its
# twin were both measured doing before the constant changed. 2654435761 is odd,
# so a * K is a bijection mod 2^32 and no level destroys anything at any depth.
def tmix(+a: U32, +b: U32) -> U32:
  rot7(U32.add(U32.mul(a, 2654435761), b))

def fold(xs: List<&2, U32>, acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case Con{x, t}:
      fold(t, mix(acc, x))

type Cs is Type:
  Cs{acc: U32, c: Cdc.Cdc}

def cs.put(acc: U32, r: Cdc.Cdc & List<&2, U32>) -> Cs:
  (c, xs) = r
  Cs{fold(xs, acc), c}

def cs.one(+n: U32, +bits: U32, acc: U32, c: Cdc.Cdc) -> Cs:
  cs.put(acc, Cdc.split(c, 0, n, bits))

def cs.go(fuel: Nat, +n: U32, +bits: U32, s: Cs) -> Cs:
  match fuel:
    case 0n:
      s
    case 1n++p:
      match s:
        case Cs{acc, c}:
          cs.go(p, n, U32.add(bits, 2), cs.one(n, bits, acc, c))

def cs.out(s: Cs) -> U32:
  match s:
    case Cs{acc, c}:
      acc

# one shard: 64 KiB of its own, its own gear table, its own four scans
def shard.b(+base: U32) -> U32:
  cs.out(cs.go(4n, 65536, 8, Cs{0, Cdc.new(fill(65536n, base, Bytes.new()))}))

def shard(+s: U32) -> U32:
  shard.b(U32.shln(s, 16n))

def par(d: Nat, +s: U32) -> U32:
  match d:
    case 0n:
      shard(s)
    case 1n++p:
      +w = U32.shln(1, p)
      a b = par(p, s) par(p, U32.add(s, w))
      tmix(a, b)

def main() -> U32:
  par(8n, 0)
