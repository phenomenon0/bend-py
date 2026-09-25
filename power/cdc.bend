# FastCDC: content-defined chunking. Where a fixed 4 KiB split moves every
# boundary after an inserted byte, a content-defined one puts the boundary at a
# place the bytes themselves pick, so an insert disturbs one chunk and the rest
# of the file keeps the addresses it already had. Paired with blake3.bend that
# is deduplication: cut, hash each piece, store the pieces you have not seen.
#
# The rolling hash is Gear -- h = (h << 1) + gear[byte] -- and the cut test is
# a mask over h's high bits. Normalized chunking is the paper's contribution:
# below the minimum no cut is even tested, from there to the average the mask
# is two bits stricter so early cuts are rarer, past the average it is two bits
# looser so late ones are commoner, and at the maximum the cut is forced. The
# chunk sizes come out far tighter around the average than one mask gives.
#
# Written for the compiled lanes: the scan is one self-recursive loop over a
# two-variant record, so a cut returns at the byte it found rather than idling
# out the rest of its fuel, and the gear table is read once per byte with
# nothing else touching memory.
import Base
import ./vec.bend as Vec
import ./bytes.bend as Bytes
import ./rng.bend as Rng

# The chunker owns the buffer while it is cutting, because the table is an
# array and an array has a single owner: handing back a (Bytes, Vec, U32)
# triple every call would make the table the caller's problem.
type Cdc is Type:
  Cdc{g: Vec.Vec, b: Bytes()}

# The gear table is 256 words that need to spread a byte across 32 bits and
# nothing more -- no collision resistance, no structure. Threefry draws them,
# which is one line here and one line in any other language, rather than 256
# constants transcribed by hand from a reference and checked by eye.
def tbl.go(fuel: Nat, +i: U32, v: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      v
    case 1n++p:
      tbl.go(p, U32.inc(i), Vec.push(v, Rng.u32(2654435761, 0, i)))

def gear() -> Vec.Vec:
  tbl.go(256n, 0, Vec.new(0))

# new: a chunker over b
def new(b: Bytes()) -> Cdc:
  Cdc{gear(), b}

# into: the buffer back, the table dropped
def into(c: Cdc) -> Bytes():
  match c:
    case Cdc{g, b}:
      b

# the masks are the top bits of the hash, not the bottom ones: under
# h = (h << 1) + gear[byte], bit k has seen only the last k + 1 bytes, so a
# low-bit mask would cut on a two-byte window and throw away the shift
# resistance the whole scheme exists for
def topmask(+k: U32) -> U32:
  U32.shln(U32.sub(U32.shln(1, U32.to_nat(k)), 1), U32.to_nat(U32.sub(32, k)))

# the paper's four sizes from one knob: bits is log2 of the target average, the
# minimum is a quarter of it, the maximum eight times, and the two masks sit
# two bits either side
def avg(+bits: U32) -> U32:
  U32.shln(1, U32.to_nat(bits))

# -- the scan ----------------------------------------------------------------

type Cs is Type:
  CGo{i: U32, h: U32, g: Vec.Vec, b: Bytes()}
  CHit{i: U32, g: Vec.Vec, b: Bytes()}

def cs.tst(i: U32, h: U32, g: Vec.Vec, b: Bytes(), hit: Bool) -> Cs:
  match hit:
    case True{}:
      CHit{i, g, b}
    case False{}:
      CGo{i, h, g, b}

def cs.new(i: U32, +h: U32, msk: U32, g: Vec.Vec, b: Bytes()) -> Cs:
  cs.tst(i, h, g, b, U32.is_zero(U32.and(h, msk)))

def cs.fin(+i: U32, +h: U32, msk: U32, b: Bytes(), r: Vec.Vec & U32) -> Cs:
  (g, x) = r
  cs.new(U32.inc(i), U32.add(U32.shln(h, 1n), x), msk, g, b)

def cs.gear(i: U32, h: U32, msk: U32, g: Vec.Vec, r: Bytes() & U32) -> Cs:
  (b, x) = r
  cs.fin(i, h, msk, b, Vec.at(g, x))

# one byte: roll it in, then test. A hit records the index one past the byte
# that caused it, which is the length of the chunk from the scan's start.
def cs.one(+i: U32, h: U32, msk: U32, g: Vec.Vec, b: Bytes()) -> Cs:
  cs.gear(i, h, msk, g, Bytes.at(b, i))

# CHit returns without recursing, so the loop stops at the cut and the fuel is
# only a bound
def cs.go(fuel: Nat, +msk: U32, s: Cs) -> Cs:
  match fuel:
    case 0n:
      s
    case 1n++p:
      match s:
        case CHit{i, g, b}:
          CHit{i, g, b}
        case CGo{i, h, g, b}:
          cs.go(p, msk, cs.one(i, h, msk, g, b))

# the length the scan settled on. The scan carries absolute indices, because
# that is what Bytes.at wants, so both answers are a distance from off: a hit
# is where it hit, and no hit at all is the whole span it was given -- which is
# the maximum chunk, or what was left before the end of the range.
def cs.out(+off: U32, +hi: U32, s: Cs) -> Cdc & U32:
  match s:
    case CHit{i, g, b}:
      (Cdc{g, b}, U32.sub(i, off))
    case CGo{i, h, g, b}:
      (Cdc{g, b}, U32.sub(hi, off))

# -- one cut -----------------------------------------------------------------

def cut.run(+off: U32, +lo: U32, +md: U32, +hi: U32, +bits: U32, s: Cs) -> Cdc & U32:
  cs.out(off, hi,
    cs.go(U32.to_nat(U32.sub(hi, md)), topmask(U32.sub(bits, 2)),
      cs.go(U32.to_nat(U32.sub(md, lo)), topmask(U32.add(bits, 2)), s)))

# the two loops run back to back rather than choosing a mask per byte: the
# second sees a CHit from the first and returns it untouched, so the normal
# point costs one comparison per chunk instead of one per byte
def cut.run2(c: Cdc, +off: U32, +lo: U32, +md: U32, +hi: U32, +bits: U32) -> Cdc & U32:
  match c:
    case Cdc{g, b}:
      cut.run(off, lo, md, hi, bits, CGo{lo, 0, g, b})

def cut.sz(c: Cdc, +off: U32, +end: U32, +bits: U32, +a: U32) -> Cdc & U32:
  cut.run2(c, off,
    U32.min(U32.add(off, U32.shrn(a, 2n)), end),
    U32.min(U32.add(off, a), end),
    U32.min(U32.add(off, U32.shln(a, 3n)), end),
    bits)

# cut: the length of the chunk that starts at off, never more than what is left
# before end. bits is log2 of the target average size; 10 asks for 1 KiB
# chunks, 13 for the paper's 8 KiB.
def cut(c: Cdc, +off: U32, +end: U32, +bits: U32) -> Cdc & U32:
  cut.sz(c, off, end, bits, avg(bits))

# -- the whole buffer --------------------------------------------------------

type Sp is Type:
  SGo{off: U32, xs: List<&2, U32>, c: Cdc}
  SEnd{xs: List<&2, U32>, c: Cdc}

def sp.mk(+e: U32, xs: List<&2, U32>, c: Cdc) -> Sp:
  SGo{e, Con{e, xs}, c}

def sp.hit(+off: U32, xs: List<&2, U32>, r: Cdc & U32) -> Sp:
  (c, n) = r
  sp.mk(U32.add(off, n), xs, c)

def sp.if(+off: U32, +end: U32, bits: U32, xs: List<&2, U32>, c: Cdc, more: Bool) -> Sp:
  match more:
    case True{}:
      sp.hit(off, xs, cut(c, off, end, bits))
    case False{}:
      SEnd{xs, c}

def sp.go(fuel: Nat, +end: U32, +bits: U32, s: Sp) -> Sp:
  match fuel:
    case 0n:
      s
    case 1n++p:
      match s:
        case SEnd{xs, c}:
          SEnd{xs, c}
        case SGo{+off, xs, c}:
          sp.go(p, end, bits, sp.if(off, end, bits, xs, c, U32.is_lt(off, end)))

def sp.out(s: Sp) -> Cdc & List<&2, U32>:
  match s:
    case SEnd{xs, c}:
      (c, List.reverse(&2, U32, xs))
    case SGo{off, xs, c}:
      (c, List.reverse(&2, U32, xs))

# split: every cut point of the range, ascending, the last of them end itself.
# The fuel is the most chunks the range can hold -- one per minimum size -- so
# it never runs out before the range does.
def split(c: Cdc, +off: U32, +end: U32, +bits: U32) -> Cdc & List<&2, U32>:
  sp.out(sp.go(U32.to_nat(U32.add(U32.shrn(U32.sub(end, off), U32.to_nat(U32.sub(bits, 2))), 2)),
    end, bits, SGo{off, [], c}))
