# text, forked: the same 16,776,384-byte corpus and the same answer as
# text.bend, cut 64 ways. The point of this file is the cut.
#
# Grapheme segmentation does not chunk freely. A cluster can straddle any byte
# you pick, and the break decision at offset o reads state carried from the last
# break before o -- the previous class, whether a pictographic run is live,
# whether the regional indicators since the break are odd. Hand a leaf a naked
# [lo, hi) and it starts with no previous class, which is exactly GB1, a break
# at the start of text; every boundary it reports until the first real break is
# wrong, and a flag sequence split down the middle turns one flag into two.
#
# The fix is a run-up, and the run-up needs an anchor: an offset that is a
# cluster start whatever precedes it. GB4 gives one for free -- it breaks after
# LF with no exceptions and no state -- so the byte after any LF is such an
# offset, and so is 0. Each leaf scans BACKWARD from its lo for the nearest of
# those, at most 256 bytes, and if the window holds none it falls back to 0,
# which is always right and only ever slow. It then segments from the anchor and
# reports only the starts that land in its own [lo, hi). The corpus's unit ends
# in CR LF, so in practice the scan walks at most 47 bytes.
#
# The tail straddles too: a code point beginning at hi - 1 runs past hi, and its
# start is this leaf's to report. So a leaf reads four bytes past hi -- one
# maximal UTF-8 width -- and drops the boundaries at or after hi.
#
# The chunk width is chosen so that all of this is actually exercised. 262,131
# is 3 mod 48, so the 64 chunk starts walk sixteen phases through the unit
# instead of sitting on its edge: 32 of them begin in the middle of a UTF-8
# code point -- inside an emoji, inside the ZWJ, inside a combining mark -- and
# 36 begin in the middle of a cluster. A width that divided 48, which a round
# 16 MiB and 64 leaves would have given, puts every cut on a cluster start and
# the anchor could be deleted without changing the answer. The run-up costs
# 1,440 bytes over the 64 leaves and the tails 256 more: 1,696 bytes on
# 16,776,384, 0.0101%.
#
# The leaves combine by adding, not by a rolling mix, because text.bend's
# checksum is a sum of hh(offset) over cluster starts: a sum over disjoint
# ranges is the sum of the sums, so the tree fold of 64 leaves equals the one
# sequential walk without anybody having to fold left to right. text_par gets
# its own twin_text_par.c rather than text's, only because run.sh's alias list
# is for benches that share a twin and this one is a different shape of program
# -- both twins print the same number.
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

def unitb() -> By.Bytes:
  By.from_list(unit(), By.new())

type Cb is Type:
  Cb{j: U32, u: By.Bytes, b: By.Bytes}

def cb.nx(+j: U32, wrap: Bool) -> U32:
  match wrap:
    case True{}:
      0
    case False{}:
      j

def cb.put(+j: U32, b: By.Bytes, r: By.Bytes & U32) -> Cb:
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

def cb.take(t: Cb) -> By.Bytes:
  match t:
    case Cb{j, u, b}:
      b

def corpus(+s: U32, +e: U32) -> By.Bytes:
  cb.take(cb.go(U32.to_nat(U32.sub(e, s)), Cb{U32.mod(s, 48), unitb(), By.new()}))

def hh(+p: U32) -> U32:
  U32.xor(U32.mul(U32.inc(p), 2654435761), U32.shrn(p, 3n))

def rot7(+v: U32) -> U32:
  U32.or(U32.shln(v, 7n), U32.shrn(v, 25n))

def mix(+acc: U32, +x: U32) -> U32:
  rot7(U32.add(U32.mul(acc, 31), x))

# -- the backward scan for an anchor ------------------------------------------

type An is Type:
  An{q: U32, u: By.Bytes, d: U32}

def an.hit(+q: U32, u: By.Bytes, yes: Bool) -> An:
  match yes:
    case True{}:
      An{q, u, 1}
    case False{}:
      An{U32.sub(q, 1), u, 0}

def an.ck(+q: U32, r: By.Bytes & U32) -> An:
  (u, x) = r
  an.hit(q, u, U32.is_eq(x, 10))

# the byte before q, read out of the unit rather than out of a buffer: nothing
# has been built yet when the anchor is wanted
def an.look(+q: U32, u: By.Bytes) -> An:
  an.ck(q, By.at(u, U32.mod(U32.sub(q, 1), 48)))

def an.top(+q: U32, u: By.Bytes, zero: Bool) -> An:
  match zero:
    case True{}:
      An{0, u, 1}
    case False{}:
      an.look(q, u)

def an.on(+q: U32, u: By.Bytes, +d: U32, go: Bool) -> An:
  match go:
    case True{}:
      an.top(q, u, U32.is_zero(q))
    case False{}:
      An{q, u, d}

def an.step(t: An) -> An:
  match t:
    case An{q, u, +d}:
      an.on(q, u, d, U32.is_zero(d))

def an.go(fuel: Nat, t: An) -> An:
  match fuel:
    case 0n:
      t
    case 1n++p:
      an.go(p, an.step(t))

def an.pick(+q: U32, found: Bool) -> U32:
  match found:
    case True{}:
      q
    case False{}:
      0

def an.take(t: An) -> U32:
  match t:
    case An{q, u, d}:
      an.pick(q, U32.is_eq(d, 1))

# anchor: the largest offset at or before lo that starts a cluster no matter
# what precedes it -- 0, or the byte after an LF. Bounded at 256 steps; falling
# out of the window answers 0, which is correct and merely slower.
def anchor(+lo: U32) -> U32:
  an.take(an.go(256n, An{lo, unitb(), 0}))

# -- one leaf -----------------------------------------------------------------

type Ap is Type:
  Ap{j: U32, v: Vec.Vec, s: U32, c: U32}

def ap.add(+a: U32, +b: U32, on: Bool) -> U32:
  match on:
    case True{}:
      U32.add(a, b)
    case False{}:
      a

def ap.hit(+j: U32, v: Vec.Vec, +s: U32, +c: U32, +off: U32, +ok: Bool) -> Ap:
  Ap{U32.inc(j), v, ap.add(s, hh(off), ok), ap.add(c, 1, ok)}

# a boundary the leaf found in its run-up, or past its end, is not its to report
def ap.rng(+j: U32, v: Vec.Vec, +s: U32, +c: U32, +lo: U32, +hi: U32,
  +off: U32) -> Ap:
  ap.hit(j, v, s, c, off, Bool.and(U32.is_ge(off, lo), U32.is_lt(off, hi)))

def ap.put(+j: U32, +s: U32, +c: U32, +q: U32, +lo: U32, +hi: U32,
  r: Vec.Vec & U32) -> Ap:
  (v, x) = r
  ap.rng(j, v, s, c, lo, hi, U32.add(q, x))

def ap.step(+q: U32, +lo: U32, +hi: U32, t: Ap) -> Ap:
  match t:
    case Ap{+j, v, s, c}:
      ap.put(j, s, c, q, lo, hi, Vec.at(v, j))

def ap.go(fuel: Nat, +q: U32, +lo: U32, +hi: U32, t: Ap) -> Ap:
  match fuel:
    case 0n:
      t
    case 1n++p:
      ap.go(p, q, lo, hi, ap.step(q, lo, hi, t))

def ap.out(t: Ap) -> U32 & U32:
  match t:
    case Ap{j, v, s, c}:
      (s, c)

def leaf.n(+q: U32, +lo: U32, +hi: U32, r: Vec.Vec & U32) -> U32 & U32:
  (v, +n) = r
  ap.out(ap.go(U32.to_nat(U32.sub(n, 1)), q, lo, hi, Ap{0, v, 0, 0}))

def leaf.v(+q: U32, +lo: U32, +hi: U32, r: By.Bytes & Vec.Vec) -> U32 & U32:
  (b, v) = r
  leaf.n(q, lo, hi, Vec.len(v))

# the four bytes past hi are the tail over-read: a code point that begins at
# hi - 1 is this leaf's, and decode has to be able to finish it
def leaf.q(+q: U32, +lo: U32, +hi: U32) -> U32 & U32:
  leaf.v(q, lo, hi, Text.graphemes(corpus(q, U32.add(hi, 4))))

def leaf.lo(+lo: U32) -> U32 & U32:
  leaf.q(anchor(lo), lo, U32.add(lo, 262131))

def leaf(k: U32) -> U32 & U32:
  leaf.lo(U32.mul(k, 262131))

# -- the tree -----------------------------------------------------------------

def comb2(a: U32, b: U32, y: U32 & U32) -> U32 & U32:
  (c, d) = y
  (U32.add(a, c), U32.add(b, d))

def comb(x: U32 & U32, y: U32 & U32) -> U32 & U32:
  (a, b) = x
  comb2(a, b, y)

def par(d: Nat, +k: U32) -> U32 & U32:
  match d:
    case 0n:
      leaf(k)
    case 1n++p:
      +w = U32.shln(1, p)
      a b = par(p, k) par(p, U32.add(k, w))
      comb(a, b)

def fin(r: U32 & U32) -> U32:
  (s, c) = r
  mix(s, c)

def main() -> U32:
  fin(par(6n, 0))
