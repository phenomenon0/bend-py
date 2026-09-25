# FastCDC, sequential: a 16 MiB buffer cut four times, at target averages of
# 256 B, 1 KiB, 4 KiB and 16 KiB. 64 MiB of rolling hash -- one gear lookup, a
# shift, an add and a mask test per byte -- which is the number this bench is
# about; the buffer is filled once and scanned four times so the fill is a
# twentieth of the run rather than half of it.
#
# The four averages are not decoration. The normalizing masks are derived from
# bits, and the minimum, maximum and the two mask widths all move with it, so a
# single average would leave three quarters of the size logic unmeasured and,
# worse, unchecked against the twin.
#
# There is no fork here, so its 1T and 16T columns are the same run twice;
# cdc_par.bend is where the threads are.
import Base
import ../../../power/bytes.bend as Bytes
import ../../../power/cdc.bend as Cdc

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

# every boundary, not the count: two chunkings can agree on how many cuts they
# made and disagree on all but the first
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

def main() -> U32:
  cs.out(cs.go(4n, 16777216, 8, Cs{0, Cdc.new(fill(16777216n, 0, Bytes.new()))}))
