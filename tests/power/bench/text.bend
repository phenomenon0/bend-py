# text, sequential: extended grapheme cluster segmentation, UAX #29, over a
# 16,776,384-byte corpus -- 8,038,684 code points, 5,592,128 clusters. That is
# the number this bench is about: one gtab() binary search and one break
# decision per code point, plus the UTF-8 decode that finds the code point.
#
# The corpus is not a data file. It is one 48-byte unit repeated 349,508 times,
# rebuilt the same way on both sides, exactly as tests/strings/bench.sh rebuilds
# its two 8 MiB corpora from a unit string and a repeat-to-N rule. The unit is
# chosen so every rule that can fire does: an ASCII run (GB999), a precomposed
# e-acute (a 2-byte decode), a Hangul LV syllable followed by a T jamo (GB9a via
# the LV/LVT arithmetic), a regional-indicator pair (GB12/GB13), a base with two
# combining marks (GB9), a ZWJ emoji sequence (GB11), two CJK ideographs, and a
# CR LF pair (GB3) -- which is also the anchor text_par.bend scans back to.
#
# The checksum is a SUM of hh(offset) over cluster starts, not a rolling fold,
# and the count rides beside it. That is the whole reason text_par.bend can
# answer the same number: a sum over disjoint ranges is the sum of the sums, so
# 64 leaves in a tree and one sequential walk agree without the leaves having to
# be combined left to right. A missed, extra or shifted boundary changes it.
#
# There is no fork in this file, so its 1T and 16T columns are the same run
# twice; text_par.bend is where the threads are.
import Base
import ../../../power/vec.bend as Vec
import ../../../power/bytes.bend as By
import ../../../power/text.bend as Text

# The unit, 48 bytes and 23 code points, written out as the bytes themselves
# so no editor and no encoding sits between this file and the corpus. In
# order: C a f, U+00E9, space, U+AC00 U+11A8, space, U+1F1FA U+1F1F8, space,
# e U+0301 U+0323, space, U+1F468 U+200D U+1F469, space, U+4E2D U+6587, then
# U+000D U+000A. Sixteen clusters.
def unit() -> List<&2, U32>:
  [67, 97, 102, 195, 169, 32, 234, 176, 128, 225, 134, 168, 32, 240, 159, 135,
    186, 240, 159, 135, 184, 32, 101, 204, 129, 204, 163, 32, 240, 159, 145,
    168, 226, 128, 141, 240, 159, 145, 169, 32, 228, 184, 173, 230, 150, 135,
    13, 10]

def unitb() -> Bytes():
  By.from_list(unit(), By.new())

type Cb is Type:
  Cb{j: U32, u: Bytes(), b: Bytes()}

# the unit index wraps by a compare, not by a mod: the mod is paid once, at the
# start of a range, and never inside the byte loop
def cb.nx(+j: U32, wrap: Bool) -> U32:
  match wrap:
    case True{}:
      0
    case False{}:
      j

def cb.put(+j: U32, b: Bytes(), r: Bytes() & U32) -> Cb:
  (u, x) = r
  Cb{cb.nx(U32.inc(j), U32.is_eq(j, 47)), u, By.push(b, x)}

def cb.step(t: Cb) -> Cb:
  match t:
    case Cb{+j, u, b}:
      cb.put(j, b, By.at(u, j))

def cb.go(fuel: Nat, t: Cb) -> Cb:
  match fuel:
    case 0n:
      t
    case 1n++p:
      cb.go(p, cb.step(t))

def cb.take(t: Cb) -> Bytes():
  match t:
    case Cb{j, u, b}:
      b

# corpus: bytes [s, e) of the endless repetition of unit(). Asking for a range
# that starts mid-unit is the whole point -- text_par.bend's leaves do.
def corpus(+s: U32, +e: U32) -> Bytes():
  cb.take(cb.go(U32.to_nat(U32.sub(e, s)), Cb{U32.mod(s, 48), unitb(), By.new()}))

# knn.bend's hash and knn_par.bend's mixer
def hh(+p: U32) -> U32:
  U32.xor(U32.mul(U32.inc(p), 2654435761), U32.shrn(p, 3n))

def rot7(+v: U32) -> U32:
  U32.or(U32.shln(v, 7n), U32.shrn(v, 25n))

def mix(+acc: U32, +x: U32) -> U32:
  rot7(U32.add(U32.mul(acc, 31), x))

type Ac is Type:
  Ac{j: U32, v: Vec.Vec, s: U32, c: U32}

def ac.put(+j: U32, +s: U32, +c: U32, r: Vec.Vec & U32) -> Ac:
  (v, x) = r
  Ac{U32.inc(j), v, U32.add(s, hh(x)), U32.inc(c)}

def ac.step(t: Ac) -> Ac:
  match t:
    case Ac{+j, v, s, c}:
      ac.put(j, s, c, Vec.at(v, j))

def ac.go(fuel: Nat, t: Ac) -> Ac:
  match fuel:
    case 0n:
      t
    case 1n++p:
      ac.go(p, ac.step(t))

def ac.out(t: Ac) -> U32:
  match t:
    case Ac{j, v, s, c}:
      mix(s, c)

# graphemes() closes its answer with the buffer length as a sentinel, so the
# fold runs to len - 1 and the count is the cluster count, not one more
def seq.n(r: Vec.Vec & U32) -> U32:
  (v, +n) = r
  ac.out(ac.go(U32.to_nat(U32.sub(n, 1)), Ac{0, v, 0, 0}))

def seq.v(r: Bytes() & Vec.Vec) -> U32:
  (b, v) = r
  seq.n(Vec.len(v))

def main() -> U32:
  seq.v(Text.graphemes(corpus(0, 16776384)))
