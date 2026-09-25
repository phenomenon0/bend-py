# BLAKE3, sequential: a 16 MiB buffer hashed four times, from offsets 0, 1, 2
# and 3, so four genuinely different 16 MiB messages go through the tree for one
# buffer's worth of filling. 64 MiB is 1,048,576 compressions, each 7 rounds
# of 8 G functions -- 58.7 million G calls, which is the number this bench is
# about.
#
# The four offsets are what keeps the fill honest: hashing one range four times
# would measure the same tree four times, and hashing four disjoint quarters
# would put a quarter of the buffer through the chunk stack per pass, leaving
# the fill a third of the run instead of a twentieth.
#
# There is no fork here, so its 1T and 16T columns are the same run twice;
# blake3_par.bend is where the threads are.
import Base
import ../../../power/bytes.bend as Bytes
import ../../../power/blake3.bend as B3

def key(+i: U32) -> U32:
  U32.xor(U32.mul(U32.inc(i), 2654435761), U32.shrn(i, 3n))

def fill(fuel: Nat, +i: U32, b: Bytes()) -> Bytes():
  match fuel:
    case 0n:
      b
    case 1n++p:
      fill(p, U32.inc(i), Bytes.push(b, key(i)))

def rot7(+v: U32) -> U32:
  U32.or(U32.shln(v, 7n), U32.shrn(v, 25n))

def mix(+acc: U32, +x: U32) -> U32:
  rot7(U32.add(U32.mul(acc, 31), x))

# the whole root, not one word of it: a bench whose checksum reads eight of the
# eight words cannot pass while the tree is wrong in the other seven
def cvmix(+acc: U32, c: B3.Cv) -> U32:
  match c:
    case B3.Cv{a0, a1, a2, a3, a4, a5, a6, a7}:
      mix(mix(mix(mix(mix(mix(mix(mix(acc, a0), a1), a2), a3), a4), a5), a6), a7)

type Hs is Type:
  Hs{acc: U32, b: Bytes()}

def hs.put(acc: U32, r: Bytes() & B3.Cv) -> Hs:
  (b, c) = r
  Hs{cvmix(acc, c), b}

def hs.one(+n: U32, +i: U32, acc: U32, b: Bytes()) -> Hs:
  hs.put(acc, B3.hash(b, i, U32.sub(n, i)))

def hs.go(fuel: Nat, +n: U32, +i: U32, s: Hs) -> Hs:
  match fuel:
    case 0n:
      s
    case 1n++p:
      match s:
        case Hs{acc, b}:
          hs.go(p, n, U32.inc(i), hs.one(n, i, acc, b))

def hs.out(s: Hs) -> U32:
  match s:
    case Hs{acc, b}:
      acc

def main() -> U32:
  hs.out(hs.go(4n, 16777216, 0, Hs{0, fill(16777216n, 0, Bytes.new())}))
