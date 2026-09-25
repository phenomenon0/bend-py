# The laws of power/deflate.bend and power/gzip.bend. They are stated
# here and proved in deflate_proof.bend; `bun bend2/main.ts
# power/deflate_proof.bend` is the gate, and prints "All terms check."
# only when every one of them holds.
import Base
import ../wire/reader.bend as Wr
import ./deflate.bend as D
import ./gzip.bend as Z

# The reads
# =========

# LAW: chunking does not change the decode. Feeding a read and then the
# next lands exactly where feeding the two joined would have: a code, a
# length and its distance, a stored block's LEN, a dynamic header cut
# anywhere, to the bit, read as the stream whole.
law inflate_split:
  for +a: List<&2, U32>
  for +b: List<&2, U32>
  for +st: D.St
  {D.feed_list(List.append(&2, U32, a, b), st) == D.feed_list(b, D.feed_list(a, st)) : D.St}

# LAW: the walk over a read's Bytes is the machine over its bytes ...
law inflate_buf:
  for +s: Bytes()
  for +st: D.St
  {D.feed(s, st) == D.feed_list(Bytes.to_list(s), st) : D.St}

# LAW: a whole stream is the machine over it. D.inflate reads what it
# can a symbol at a time (deflate.bend's fast path) and steps the machine
# a bit where it cannot; whatever the stream, that is the machine fed the
# stream, so every law of the machine is a law of D.inflate.
law inflate_fast:
  for +cap: Nat
  for +s: Bytes()
  {D.inflate(cap, s) == D.finish(D.feed(s, D.new(cap))) : Result<&2, &2, D.Why, Bytes()>}

# ... so reads cut anywhere decode as the stream whole.
law inflate_buf_split:
  for +a: Bytes()
  for +b: Bytes()
  for +st: D.St
  {D.feed(Bytes.append(a, b), st) == D.feed(b, D.feed(a, st)) : D.St}

# LAW: a refusal is terminal, and so is the end: no byte moves the
# machine out of Bad or End (at any bit of a byte), so nothing after a
# refused byte revives the stream and nothing after its end is read.
law inflate_bad:
  for +s: List<&2, U32>
  for +why: D.Why
  for +o: D.O
  for +bp: Nat
  for lt: {Nat.is_lt(bp, 8n) == True{} : Bool}
  {D.feed_list(s, D.St{D.Bad{why}, o, bp}) == D.St{D.Bad{why}, o, bp} : D.St}

law inflate_end:
  for +s: List<&2, U32>
  for +o: D.O
  for +bp: Nat
  for lt: {Nat.is_lt(bp, 8n) == True{} : Bool}
  {D.feed_list(s, D.St{D.End{}, o, bp}) == D.St{D.End{}, o, bp} : D.St}

# LAW: the same for gunzip: chunking never changes a read ...
law gunzip_split:
  for +a: List<&2, U32>
  for +b: List<&2, U32>
  for +g: Z.G
  {Z.feed_list(List.append(&2, U32, a, b), g) == Z.feed_list(b, Z.feed_list(a, g)) : Z.G}

law gunzip_buf:
  for +s: Bytes()
  for +g: Z.G
  {Z.feed(s, g) == Z.feed_list(Bytes.to_list(s), g) : Z.G}

# ... and a refused file stays refused, at the byte that broke it.
law gunzip_bad:
  for +s: List<&2, U32>
  for +at: Nat
  for +why: Z.Why
  for +done: Bytes()
  for +crc: U32
  for +cap: Nat
  for +pos: Nat
  {Z.feed_list(s, Z.G{Z.Bad{at, why}, done, crc, cap, pos}) ==
    Z.G{Z.Bad{at, why}, done, crc, cap, pos} : Z.G}

# CRC-32
# ======

# The generator, reflected: 0xEDB88320, x^32 + x^26 + x^23 + x^22 +
# x^16 + x^12 + x^11 + x^10 + x^8 + x^7 + x^5 + x^4 + x^2 + x + 1 with
# its bits read from x^0 at the top down.
def ref.poly() -> U32:
  3988292384

# one bit of the register: shift right, and fold in the generator when
# the bit shifted out is 1
def ref.bit(+c: U32) -> U32:
  D.u32.pick(U32.is_eq(U32.and(c, 1), 1), U32.xor(U32.shr(c), ref.poly()), U32.shr(c))

def ref.bits(n: Nat, c: U32) -> U32:
  match n:
    case 0n:
      c
    case 1n+p:
      ref.bits(p, ref.bit(c))

# The reference: the register a bit at a time, eight bits to a byte,
# the byte first xored into the register's low eight bits. As RFC 1952 8
# and ISO 3309 give it; nothing here is deflate.bend's own CRC.
def crc_ref(x: Bytes(), c: U32) -> U32:
  match x:
    case SNil{}:
      c
    case SCon{Chr{b}, t}:
      crc_ref(t, ref.bits(8n, U32.xor(c, U32.and(b, 255))))

# LAW: the table-driven CRC-32 is the bit-at-a-time one, for every input
# and every CRC it is continued from: the table's 256 cells are right,
# and a byte folded in by its cell is the byte's eight bits folded in.
law crc32_ref:
  for +x: Bytes()
  for +prev: U32
  {D.crc32(x, prev) == U32.not(crc_ref(x, U32.not(prev))) : U32}

# Round trips
# ===========

# LAW: stored blocks read back. Any bytes (each below 256, as Bytes()
# promises), stored at level 0 as blocks of 65535 and the rest, inflate
# to themselves under any cap they fit: every header, LEN, NLEN, byte
# and block boundary as the writer put it, to the bit.
law stored_round_trip:
  for +x: Bytes()
  for +cap: Nat
  for +vx: {D.valid(x) == True{} : Bool}
  for fits: {Nat.is_le(Bytes.len(x), cap) == True{} : Bool}
  {D.inflate(cap, D.deflate(x, 0n)) == Done{x} : Result<&2, &2, D.Why, Bytes()>}

# The code tables
# ===============
#
# RFC 1951 3.2.5, from its rules and not its tables: length code i
# (257 + i) has (i - 4) / 4 extra bits from i = 8 on, none below and
# none for 285, which is 258 alone; distance code i has (i - 2) / 2 from
# i = 4 on. Each base is the one before it plus the 2^extra values that
# code spans, from 3 and from 1.

def ref.lext(+i: Nat) -> Nat:
  D.pick(Nat.is_lt(i, 8n) || Nat.is_eq(i, 28n), 0n, Nat.div(Nat.sub(i, 4n), 4n))

def ref.dext(+i: Nat) -> Nat:
  D.pick(Nat.is_lt(i, 4n), 0n, Nat.div(Nat.sub(i, 2n), 2n))

# a code's extra bits: a distance code's, or a length code's
def ref.ext(+dist: Bool, +i: Nat) -> Nat:
  match dist:
    case True{}:
      ref.dext(i)
    case False{}:
      ref.lext(i)

def ref.exts(n: Nat, +dist: Bool, +i: Nat) -> List<&2, Nat>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Con{ref.ext(dist, i), ref.exts(p, dist, 1n+i)}

# the bases as bytes pairs would not hold them: as U32s
def ref.bases(n: Nat, +dist: Bool, +i: Nat, +b: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Con{b, ref.bases(p, dist, 1n+i, U32.add(b, U32.shln(1, ref.ext(dist, i))))}

def u32s(xs: List<&2, Nat>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      Con{U32.from_nat(x), u32s(t)}

# LAW: the length codes are RFC 1951's: 285 is 258, the rest by the rule.
law length_codes:
  {D.LEXT() == ref.exts(29n, False{}, 0n) : List<&2, Nat>} &
  {u32s(D.LBASE()) == List.append(&2, U32, ref.bases(28n, False{}, 0n, 3), [258]) : List<&2, U32>}

# LAW: the distance codes are RFC 1951's.
law dist_codes:
  {D.DEXT() == ref.exts(30n, True{}, 0n) : List<&2, Nat>} &
  {u32s(D.DBASE()) == ref.bases(30n, True{}, 0n, 1) : List<&2, U32>}

# LAW: the tables deflate.bend writes out are what they stand for: the
# fixed codes' tables and codes built from their lengths, and the length
# and distance tables above.
law tables_written:
  {D.some_or(D.table(D.fixed_ll_lens(), False{})) == D.FLL() : String} &
  {D.some_or(D.table(D.fixed_d_lens(), False{})) == D.FD() : String} &
  {D.hc(D.fixed_ll_lens()) == D.Hc{D.HLLC(), D.HLLL()} : D.Hc} &
  {D.hc(D.fixed_d_lens()) == D.Hc{D.HDC(), D.HDL()} : D.Hc} &
  {D.str_of(D.LBASE(), "") == D.LBS() : String} &
  {D.str_of(D.LEXT(), "") == D.LXS() : String} &
  {D.str_of(D.DBASE(), "") == D.DBS() : String} &
  {D.str_of(D.DEXT(), "") == D.DXS() : String}

# Huffman codes
# =============
#
# RFC 1951 3.2.6: the fixed literal/length code, symbol by symbol, as the
# RFC lists it; the fixed distance code is 5 bits, the code the symbol.
def ref.fcode.at(a: Bool, b: Bool, c: Bool, +s: Nat) -> D.Code:
  match a b c:
    case True{} _ _:
      D.Code{8n, Nat.add(48n, s)}
    case False{} True{} _:
      D.Code{9n, Nat.add(400n, Nat.sub(s, 144n))}
    case False{} False{} True{}:
      D.Code{7n, Nat.sub(s, 256n)}
    case False{} False{} False{}:
      D.Code{8n, Nat.add(192n, Nat.sub(s, 280n))}

def ref.fcode(+s: Nat) -> D.Code:
  ref.fcode.at(Nat.is_lt(s, 144n), Nat.is_lt(s, 256n), Nat.is_lt(s, 280n), s)

def ref.fixed(n: Nat, +s: Nat) -> List<&2, D.Code>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Con{ref.fcode(s), ref.fixed(p, 1n+s)}

def ref.fdist(n: Nat, +s: Nat) -> List<&2, D.Code>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Con{D.Code{5n, s}, ref.fdist(p, 1n+s)}

# LAW: the canonical code of RFC 1951 3.2.2, built from the lengths: the
# RFC's own example (ABCDEFGH of lengths 3 3 3 3 3 2 4 4 are 010 011 100
# 101 110 00 1110 1111), and the fixed codes of 3.2.6 whole.
law canonical:
  {D.codes([3n, 3n, 3n, 3n, 3n, 2n, 4n, 4n]) == [D.Code{3n, 2n}, D.Code{3n, 3n}, D.Code{3n, 4n},
    D.Code{3n, 5n}, D.Code{3n, 6n}, D.Code{2n, 0n}, D.Code{4n, 14n}, D.Code{4n, 15n}] : List<&2, D.Code>} &
  {D.codes(D.fixed_ll_lens()) == ref.fixed(288n, 0n) : List<&2, D.Code>} &
  {D.codes(D.fixed_d_lens()) == ref.fdist(32n, 0n) : List<&2, D.Code>}

# The machine's table: node j's two cells, 2j for a 0 bit and 2j+1 for a
# 1; a cell is 0 (no code), 2s+1 (symbol s) or 2k (node k).
# at the cell v (z: it is 0, odd: it is a symbol's) with the bits bs
# still to read; the root is node 0
def ref.walk(bs: List<&2, Bool>, +tab: String, +v: Nat, z: Bool, odd: Bool) -> Maybe<&2, Nat>:
  match bs z odd:
    case _ True{} _:
      None{}
    case Nil{} False{} True{}:
      Some{Nat.div(v, 2n)}
    case Nil{} False{} False{}:
      None{}
    case Con{b, t} False{} True{}:
      None{}
    case Con{b, t} False{} False{}:
      +w = U32.to_nat(Bytes.get(tab, Nat.add(Nat.double(Nat.div(v, 2n)), D.pick(b, 1n, 0n))))
      ref.walk(t, tab, w, Nat.is_eq(w, 0n), Nat.is_eq(Nat.mod(w, 2n), 1n))

# a code's bits, most significant first
def ref.hbits(l: Nat, +v: Nat, acc: List<&2, Bool>) -> List<&2, Bool>:
  match l:
    case 0n:
      acc
    case 1n+p:
      ref.hbits(p, Nat.div(v, 2n), Con{Nat.is_eq(Nat.mod(v, 2n), 1n), acc})

def ref.is(m: Maybe<&2, Nat>, +s: Nat) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{x}:
      Nat.is_eq(x, s)

# every symbol from s on walks the table to itself by its code
def ref.decodes(+tab: String, cs: List<&2, D.Code>, +s: Nat) -> Bool:
  match cs:
    case Nil{}:
      True{}
    case Con{D.Code{l, v}, t}:
      ref.is(ref.walk(ref.hbits(l, v, Nil{}), tab, 0n, False{}, False{}), s) && ref.decodes(tab, t, 1n+s)

def ref.fll(t: D.Tabs) -> String:
  match t:
    case D.Tabs{fll, fd, lb, lx, db, dx}:
      fll

def ref.fd(t: D.Tabs) -> String:
  match t:
    case D.Tabs{fll, fd, lb, lx, db, dx}:
      fd

# LAW: the fixed tables the machine decodes by take every fixed code to
# its symbol.
law fixed_tables:
  {ref.decodes(ref.fll(D.tabs()), ref.fixed(288n, 0n), 0n) == True{} : Bool} &
  {ref.decodes(ref.fd(D.tabs()), ref.fdist(32n, 0n), 0n) == True{} : Bool}

# LAW: the fixed path reads back. Any bytes, at any level, written by
# deflate_fixed -- whatever matches the pass finds, each checked against
# the input before it is written -- inflate to themselves under any cap
# they fit: every literal, length, distance and extra bit through the
# fixed code's tables, every copy within the window.
law fixed_round_trip:
  for +x: Bytes()
  for +lvl: Nat
  for +cap: Nat
  for +vx: {D.valid(x) == True{} : Bool}
  for fits: {Nat.is_le(Bytes.len(x), cap) == True{} : Bool}
  {D.inflate(cap, D.deflate_fixed(x, lvl)) == Done{x} : Result<&2, &2, D.Why, Bytes()>}

# The cap
# =======

# LAW: the cap is a bomb guard. However many bytes come in, the machine
# has written at most cap bytes...
law output_cap:
  for +s: List<&2, U32>
  for +cap: Nat
  {Nat.is_le(D.written(D.feed_list(s, D.new(cap))), cap) == True{} : Bool}

# ... and what a stream inflates to is at most cap bytes.
law inflate_cap:
  for +s: Bytes()
  for +cap: Nat
  for +y: Bytes()
  for e: {D.inflate(cap, s) == Done{y} : Result<&2, &2, D.Why, Bytes()>}
  {Nat.is_le(Bytes.len(y), cap) == True{} : Bool}

# The window
# ==========

# LAW: a distance past the output is refused, with nothing written ...
law copy_far:
  for +out: Bytes()
  for +keep: Nat
  for +n: Nat
  for +cap: Nat
  for +t: D.Tabs
  for +len: Nat
  for +dist: Nat
  for +next: D.Mode
  for +bp: Nat
  for far: {Nat.is_lt(Bytes.len(out), dist) == True{} : Bool}
  {D.copy(D.O{out, keep, n, cap, t}, len, dist, next, bp) ==
    D.St{D.Bad{D.FarBack{}}, D.O{out, keep, n, cap, t}, bp} : D.St}

# ... and one within it, under the cap, is copied: len more bytes,
# counted, and the machine goes on.
law copy_near:
  for +out: Bytes()
  for +keep: Nat
  for +n: Nat
  for +cap: Nat
  for +t: D.Tabs
  for +len: Nat
  for +dist: Nat
  for +next: D.Mode
  for +bp: Nat
  for near: {Nat.is_le(dist, Bytes.len(out)) == True{} : Bool}
  for room: {Nat.is_le(Nat.add(n, len), cap) == True{} : Bool}
  {D.copy(D.O{out, keep, n, cap, t}, len, dist, next, bp) ==
    D.St{next, D.O{D.copy.go(len, out, dist), keep, Nat.add(n, len), cap, t}, bp} : D.St}

# LAW: LZ77. Each byte a copy writes is the byte dist before it, the
# copy running over its own bytes when len > dist.
law copy_back:
  for +len: Nat
  for +out: Bytes()
  for +dist: Nat
  for +j: Nat
  for d1: {Nat.is_lt(0n, dist) == True{} : Bool}
  for dle: {Nat.is_le(dist, Bytes.len(out)) == True{} : Bool}
  for jl: {Nat.is_lt(j, len) == True{} : Bool}
  {Bytes.get(D.copy.go(len, out, dist), Nat.add(j, Bytes.len(out))) ==
    Bytes.get(D.copy.go(len, out, dist), Nat.sub(Nat.add(j, Bytes.len(out)), dist)) : U32}

# what a take leaves the machine: its window
def win(r: Bytes() & D.St) -> Bytes():
  (x, st) = r
  match st:
    case D.St{m, o, bp}:
      match o:
        case D.O{out, keep, n, cap, t}:
          out

# LAW: a take keeps the last 32768 bytes (all of them, fewer written):
# the whole window any distance reaches back into, and what it drops is
# what comes before it.
law take_window:
  for +m: D.Mode
  for +out: Bytes()
  for +keep: Nat
  for +n: Nat
  for +cap: Nat
  for +t: D.Tabs
  for +bp: Nat
  {Bytes.len(win(D.take(D.St{m, D.O{out, keep, n, cap, t}, bp}))) == Nat.min(Bytes.len(out), 32768n) : Nat} &
  {String.append(String.take(out, Nat.sub(Bytes.len(out), 32768n)), win(D.take(D.St{m, D.O{out, keep, n, cap, t},
    bp}))) == out : Bytes()}
