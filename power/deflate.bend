# Deflate: RFC 1951 both ways, over Base's Bytes().
#
# Inflate is a bit machine: one step per bit, the whole state one value
# (St, kind Data), a byte fed as its eight bits low first (step). So a
# read may end anywhere -- inside a code, between a length and its
# distance, in a stored block's LEN -- and the next read carries on from
# the state the last one left; a stream fed in any number of reads
# decodes as the stream whole (the reader kit's feed_split). The output
# grows in St's buffer, whose last 32 KiB are the window a back
# reference reads; take hands out what is past the window.
#
# Budgets. Every output byte is counted against O's cap before it is
# written: a stream that would produce more is refused (TooBig) with
# the cap's worth written and nothing past it, so a decompression bomb
# costs its cap and no more. Refusals are terminal: Bad{why} is kept
# whatever follows (gzip.bend says at which byte).
#   BadBlock    block type 3
#   BadStored   a stored block whose NLEN is not LEN's complement
#   BadCounts   HLIT past 286 or HDIST past 30 codes
#   BadCl       the code length code over-subscribed or incomplete
#   BadRepeat   a repeat code with nothing to repeat, or past the end
#   NoEnd       no code for end-of-block
#   BadLit      the literal/length code over-subscribed or incomplete
#   BadDist     the distance code over-subscribed or incomplete
#   BadCode     a code the tree has no symbol for, or 286, 287, 30, 31
#   FarBack     a distance past what was written
#   TooBig      the output cap
#   Truncated   the input ended inside the stream (finish)
# A code may be incomplete only as zlib allows: a distance or literal
# code of one symbol of length 1, or a distance code of none.
#
# Huffman tables. A code is built from its lengths the way RFC 1951
# 3.2.2 says (codes: bl_count, next_code, then each symbol in order),
# each symbol's code inserted into a tree (ins refuses a code that lands
# on or passes through another: that is over-subscription), and the tree
# laid flat into a String, two cells a node, which the machine walks a
# bit at a time: a cell is 0 (no code), 2j (node j) or 2s + 1 (symbol s).
#
# Deflate is the other way: an LZ77 pass with hash chains (zlib's level
# knobs: good, lazy, nice, chain; greedy for 1-3, one-step lazy for 4-9)
# into blocks of at most 16383 tokens, each written as the smallest of
# stored, fixed and dynamic Huffman; level 0 writes stored blocks only.
# Every match is compared byte by byte in the input before it is taken,
# so what the chains hold decides only how good a match is, never
# whether it is right. deflate_fixed writes the pass's tokens as one
# block with the fixed code, each checked against the input as it is
# written (fixtoks), which deflate_proof.bend proves reads back as x.
import Base
import ../wire/reader.bend as Wr

# Numbers and bits
# ================

def K32() -> Nat:
  32768n

def K64() -> Nat:
  65535n

def pick(b: Bool, x: Nat, y: Nat) -> Nat:
  match b:
    case True{}:
      x
    case False{}:
      y

def u32.pick(b: Bool, x: U32, y: U32) -> U32:
  match b:
    case True{}:
      x
    case False{}:
      y

# bit k of c, low first
def bit(+c: U32, k: Nat) -> Bool:
  U32.is_ne(U32.and(U32.shrn(c, k), 1), 0)

# the eight bits of a byte, low first: the order the stream reads them
def unbyte(+c: U32) -> List<&2, Bool>:
  [bit(c, 0n), bit(c, 1n), bit(c, 2n), bit(c, 3n), bit(c, 4n), bit(c, 5n), bit(c, 6n),
    bit(c, 7n)]

# the byte whose bits, high first, are bs
def byte_of.go(bs: List<&2, Bool>, acc: U32) -> U32:
  match bs:
    case Nil{}:
      acc
    case Con{b, t}:
      byte_of.go(t, U32.or(U32.shl(acc), Bool.to_u32(b)))

def byte_of(bs: List<&2, Bool>) -> U32:
  byte_of.go(bs, 0)

# the number whose bits, low first, are bs
def val(bs: List<&2, Bool>) -> Nat:
  match bs:
    case Nil{}:
      0n
    case Con{b, t}:
      Nat.bit(b, val(t))

# the number whose bits, high first, are bs, after the bits v spells
def hval(bs: List<&2, Bool>, v: Nat) -> Nat:
  match bs:
    case Nil{}:
      v
    case Con{b, t}:
      hval(t, Nat.bit(b, v))

def revapp(xs: List<&2, Bool>, acc: List<&2, Bool>) -> List<&2, Bool>:
  match xs:
    case Nil{}:
      acc
    case Con{x, t}:
      revapp(t, Con{x, acc})

# the low n bits of v, low first
def xbits(n: Nat, +v: Nat) -> List<&2, Bool>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Con{Nat.is_eq(Nat.mod(v, 2n), 1n), xbits(p, Nat.div(v, 2n))}

# v's low n bits read back high first: a code as the tree walks it
def rev(n: Nat, +v: Nat, acc: Nat) -> Nat:
  match n:
    case 0n:
      acc
    case 1n+p:
      rev(p, Nat.div(v, 2n), Nat.add(Nat.double(acc), Nat.mod(v, 2n)))

def nth(xs: List<&2, Nat>, k: Nat) -> Nat:
  match xs k:
    case Nil{} _:
      0n
    case Con{x, t} 0n:
      x
    case Con{x, t} 1n+p:
      nth(t, p)

def bump(xs: List<&2, Nat>, k: Nat) -> List<&2, Nat>:
  match xs k:
    case Nil{} _:
      Nil{}
    case Con{x, t} 0n:
      Con{1n+x, t}
    case Con{x, t} 1n+p:
      Con{x, bump(t, p)}

# every char below 256: what Bytes() promises and deflate assumes
def valid(b: Bytes()) -> Bool:
  match b:
    case SNil{}:
      True{}
    case SCon{Chr{c}, t}:
      U32.is_lt(c, 256) && valid(t)

# CRC-32
# ======
#
# The reflected CRC of ISO 3309 / ITU-T V.42, as gzip and zip use it:
# polynomial 0xEDB88320, register preset to all ones, output inverted.
# crc.bit is the spec, one bit of the register shifted out; table(i) is
# eight of them from i; crc.byte folds a byte in by the table.

def POLY() -> U32:
  3988292384

def crc.bit(+c: U32) -> U32:
  u32.pick(U32.is_eq(U32.and(c, 1), 1), U32.xor(U32.shr(c), POLY()), U32.shr(c))

def crc.bits(n: Nat, c: U32) -> U32:
  match n:
    case 0n:
      c
    case 1n+p:
      crc.bits(p, crc.bit(c))

def crc.entry(i: U32) -> U32:
  crc.bits(8n, i)

# the 256 entries, each four bytes little end first: entry i is
# crc.entry(i), as deflate_proof.bend's crc_tab proves cell by cell
def crc.tab() -> Bytes():
  Bytes.from_list([0, 0, 0, 0, 150, 48, 7, 119, 44, 97, 14, 238, 186, 81, 9, 153,
    25, 196, 109, 7, 143, 244, 106, 112, 53, 165, 99, 233, 163, 149, 100, 158,
    50, 136, 219, 14, 164, 184, 220, 121, 30, 233, 213, 224, 136, 217, 210, 151,
    43, 76, 182, 9, 189, 124, 177, 126, 7, 45, 184, 231, 145, 29, 191, 144,
    100, 16, 183, 29, 242, 32, 176, 106, 72, 113, 185, 243, 222, 65, 190, 132,
    125, 212, 218, 26, 235, 228, 221, 109, 81, 181, 212, 244, 199, 133, 211, 131,
    86, 152, 108, 19, 192, 168, 107, 100, 122, 249, 98, 253, 236, 201, 101, 138,
    79, 92, 1, 20, 217, 108, 6, 99, 99, 61, 15, 250, 245, 13, 8, 141,
    200, 32, 110, 59, 94, 16, 105, 76, 228, 65, 96, 213, 114, 113, 103, 162,
    209, 228, 3, 60, 71, 212, 4, 75, 253, 133, 13, 210, 107, 181, 10, 165,
    250, 168, 181, 53, 108, 152, 178, 66, 214, 201, 187, 219, 64, 249, 188, 172,
    227, 108, 216, 50, 117, 92, 223, 69, 207, 13, 214, 220, 89, 61, 209, 171,
    172, 48, 217, 38, 58, 0, 222, 81, 128, 81, 215, 200, 22, 97, 208, 191,
    181, 244, 180, 33, 35, 196, 179, 86, 153, 149, 186, 207, 15, 165, 189, 184,
    158, 184, 2, 40, 8, 136, 5, 95, 178, 217, 12, 198, 36, 233, 11, 177,
    135, 124, 111, 47, 17, 76, 104, 88, 171, 29, 97, 193, 61, 45, 102, 182,
    144, 65, 220, 118, 6, 113, 219, 1, 188, 32, 210, 152, 42, 16, 213, 239,
    137, 133, 177, 113, 31, 181, 182, 6, 165, 228, 191, 159, 51, 212, 184, 232,
    162, 201, 7, 120, 52, 249, 0, 15, 142, 168, 9, 150, 24, 152, 14, 225,
    187, 13, 106, 127, 45, 61, 109, 8, 151, 108, 100, 145, 1, 92, 99, 230,
    244, 81, 107, 107, 98, 97, 108, 28, 216, 48, 101, 133, 78, 0, 98, 242,
    237, 149, 6, 108, 123, 165, 1, 27, 193, 244, 8, 130, 87, 196, 15, 245,
    198, 217, 176, 101, 80, 233, 183, 18, 234, 184, 190, 139, 124, 136, 185, 252,
    223, 29, 221, 98, 73, 45, 218, 21, 243, 124, 211, 140, 101, 76, 212, 251,
    88, 97, 178, 77, 206, 81, 181, 58, 116, 0, 188, 163, 226, 48, 187, 212,
    65, 165, 223, 74, 215, 149, 216, 61, 109, 196, 209, 164, 251, 244, 214, 211,
    106, 233, 105, 67, 252, 217, 110, 52, 70, 136, 103, 173, 208, 184, 96, 218,
    115, 45, 4, 68, 229, 29, 3, 51, 95, 76, 10, 170, 201, 124, 13, 221,
    60, 113, 5, 80, 170, 65, 2, 39, 16, 16, 11, 190, 134, 32, 12, 201,
    37, 181, 104, 87, 179, 133, 111, 32, 9, 212, 102, 185, 159, 228, 97, 206,
    14, 249, 222, 94, 152, 201, 217, 41, 34, 152, 208, 176, 180, 168, 215, 199,
    23, 61, 179, 89, 129, 13, 180, 46, 59, 92, 189, 183, 173, 108, 186, 192,
    32, 131, 184, 237, 182, 179, 191, 154, 12, 226, 182, 3, 154, 210, 177, 116,
    57, 71, 213, 234, 175, 119, 210, 157, 21, 38, 219, 4, 131, 22, 220, 115,
    18, 11, 99, 227, 132, 59, 100, 148, 62, 106, 109, 13, 168, 90, 106, 122,
    11, 207, 14, 228, 157, 255, 9, 147, 39, 174, 0, 10, 177, 158, 7, 125,
    68, 147, 15, 240, 210, 163, 8, 135, 104, 242, 1, 30, 254, 194, 6, 105,
    93, 87, 98, 247, 203, 103, 101, 128, 113, 54, 108, 25, 231, 6, 107, 110,
    118, 27, 212, 254, 224, 43, 211, 137, 90, 122, 218, 16, 204, 74, 221, 103,
    111, 223, 185, 249, 249, 239, 190, 142, 67, 190, 183, 23, 213, 142, 176, 96,
    232, 163, 214, 214, 126, 147, 209, 161, 196, 194, 216, 56, 82, 242, 223, 79,
    241, 103, 187, 209, 103, 87, 188, 166, 221, 6, 181, 63, 75, 54, 178, 72,
    218, 43, 13, 216, 76, 27, 10, 175, 246, 74, 3, 54, 96, 122, 4, 65,
    195, 239, 96, 223, 85, 223, 103, 168, 239, 142, 110, 49, 121, 190, 105, 70,
    140, 179, 97, 203, 26, 131, 102, 188, 160, 210, 111, 37, 54, 226, 104, 82,
    149, 119, 12, 204, 3, 71, 11, 187, 185, 22, 2, 34, 47, 38, 5, 85,
    190, 59, 186, 197, 40, 11, 189, 178, 146, 90, 180, 43, 4, 106, 179, 92,
    167, 255, 215, 194, 49, 207, 208, 181, 139, 158, 217, 44, 29, 174, 222, 91,
    176, 194, 100, 155, 38, 242, 99, 236, 156, 163, 106, 117, 10, 147, 109, 2,
    169, 6, 9, 156, 63, 54, 14, 235, 133, 103, 7, 114, 19, 87, 0, 5,
    130, 74, 191, 149, 20, 122, 184, 226, 174, 43, 177, 123, 56, 27, 182, 12,
    155, 142, 210, 146, 13, 190, 213, 229, 183, 239, 220, 124, 33, 223, 219, 11,
    212, 210, 211, 134, 66, 226, 212, 241, 248, 179, 221, 104, 110, 131, 218, 31,
    205, 22, 190, 129, 91, 38, 185, 246, 225, 119, 176, 111, 119, 71, 183, 24,
    230, 90, 8, 136, 112, 106, 15, 255, 202, 59, 6, 102, 92, 11, 1, 17,
    255, 158, 101, 143, 105, 174, 98, 248, 211, 255, 107, 97, 69, 207, 108, 22,
    120, 226, 10, 160, 238, 210, 13, 215, 84, 131, 4, 78, 194, 179, 3, 57,
    97, 38, 103, 167, 247, 22, 96, 208, 77, 71, 105, 73, 219, 119, 110, 62,
    74, 106, 209, 174, 220, 90, 214, 217, 102, 11, 223, 64, 240, 59, 216, 55,
    83, 174, 188, 169, 197, 158, 187, 222, 127, 207, 178, 71, 233, 255, 181, 48,
    28, 242, 189, 189, 138, 194, 186, 202, 48, 147, 179, 83, 166, 163, 180, 36,
    5, 54, 208, 186, 147, 6, 215, 205, 41, 87, 222, 84, 191, 103, 217, 35,
    46, 122, 102, 179, 184, 74, 97, 196, 2, 27, 104, 93, 148, 43, 111, 42,
    55, 190, 11, 180, 161, 142, 12, 195, 27, 223, 5, 90, 141, 239, 2, 45])

def crc.cell(+tab: Bytes(), +i: U32) -> U32:
  Bytes.word_le(tab, Nat.mul(U32.to_nat(i), 4n))

# one byte into the register, by the table: z, the register with the
# byte in its low eight bits, is shifted out a byte at once, the table
# giving what its low byte's eight bits fold in
def crc.byte.z(+tab: Bytes(), +z: U32) -> U32:
  U32.xor(crc.cell(tab, U32.and(z, 255)), U32.shrn(z, 8n))

def crc.byte(+tab: Bytes(), c: U32, b: U32) -> U32:
  crc.byte.z(tab, U32.xor(c, U32.and(b, 255)))

# the register after the bytes of x, from c (not inverted either end)
def crc.run(x: Bytes(), +tab: Bytes(), c: U32) -> U32:
  match x:
    case SNil{}:
      c
    case SCon{Chr{b}, t}:
      crc.run(t, tab, crc.byte(tab, c, b))

# crc32(x) continued from a previous crc32 (0 to start), as zlib.crc32
def crc32(x: Bytes(), prev: U32) -> U32:
  U32.not(crc.run(x, crc.tab(), U32.not(prev)))

# Huffman codes
# =============

type Code is Data:
  Code{len: Nat, code: Nat}

# bl_count: how many codes of each length 0..15
def counts(lens: List<&2, Nat>, acc: List<&2, Nat>) -> List<&2, Nat>:
  match lens:
    case Nil{}:
      acc
    case Con{l, t}:
      counts(t, bump(acc, l))

# next_code for each length after the one c counts: code = (code + c) << 1
def firsts.go(cnt: List<&2, Nat>, code: Nat) -> List<&2, Nat>:
  match cnt:
    case Nil{}:
      Nil{}
    case Con{c, t}:
      +nx = Nat.double(Nat.add(code, c))
      Con{nx, firsts.go(t, nx)}

# next_code[0..16]: bl_count[0] is taken as 0, as the RFC sets it
def firsts(cnt: List<&2, Nat>) -> List<&2, Nat>:
  match cnt:
    case Nil{}:
      Nil{}
    case Con{c0, t}:
      Con{0n, firsts.go(Con{0n, t}, 0n)}

# each symbol in order takes the next code of its length
def assign(lens: List<&2, Nat>, +nc: List<&2, Nat>) -> List<&2, Code>:
  match lens:
    case Nil{}:
      Nil{}
    case Con{+l, t}:
      Con{Code{l, pick(Nat.is_eq(l, 0n), 0n, nth(nc, l))}, assign(t, bump(nc, l))}

def zeros(n: Nat) -> List<&2, Nat>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Con{0n, zeros(p)}

# RFC 1951 3.2.2: the code of every symbol from the code lengths
def codes(+lens: List<&2, Nat>) -> List<&2, Code>:
  assign(lens, firsts(counts(lens, zeros(16n))))

# a code's bits as the stream carries them, most significant first
def code_bits(c: Code) -> List<&2, Bool>:
  match c:
    case Code{l, v}:
      revapp(xbits(l, v), Nil{})

# Trees
# -----

type Tr is Data:
  TNil{}
  TLeaf{s: Nat}
  TNode{z: Tr, o: Tr}

def node.l(m: Maybe<&2, Tr>, o: Tr) -> Maybe<&2, Tr>:
  match m:
    case None{}:
      None{}
    case Some{z}:
      Some{TNode{z, o}}

def node.r(z: Tr, m: Maybe<&2, Tr>) -> Maybe<&2, Tr>:
  match m:
    case None{}:
      None{}
    case Some{o}:
      Some{TNode{z, o}}

# s at the end of the path bs; None if the path meets another symbol's
def ins(bs: List<&2, Bool>, t: Tr, +s: Nat) -> Maybe<&2, Tr>:
  match bs t:
    case Nil{} TNil{}:
      Some{TLeaf{s}}
    case Nil{} TLeaf{x}:
      None{}
    case Nil{} TNode{z, o}:
      None{}
    case Con{False{}, r} TNil{}:
      node.l(ins(r, TNil{}, s), TNil{})
    case Con{True{}, r} TNil{}:
      node.r(TNil{}, ins(r, TNil{}, s))
    case Con{b, r} TLeaf{x}:
      None{}
    case Con{False{}, r} TNode{z, o}:
      node.l(ins(r, z, s), o)
    case Con{True{}, r} TNode{z, o}:
      node.r(z, ins(r, o, s))

def build.at(cs: List<&2, Code>, +s: Nat, m: Maybe<&2, Tr>) -> Maybe<&2, Tr>:
  match cs m:
    case Nil{} _:
      m
    case Con{c, t} None{}:
      None{}
    case Con{Code{0n, v}, t} Some{tr}:
      build.at(t, 1n+s, Some{tr})
    case Con{Code{1n+p, v}, t} Some{tr}:
      build.at(t, 1n+s, ins(code_bits(Code{1n+p, v}), tr, s))

# the tree of a code, each symbol in order; None if over-subscribed
def build(cs: List<&2, Code>) -> Maybe<&2, Tr>:
  build.at(cs, 0n, Some{TNil{}})

# the paths no symbol ends on
def holes(t: Tr) -> Nat:
  match t:
    case TNil{}:
      1n
    case TLeaf{s}:
      0n
    case TNode{z, o}:
      Nat.add(holes(z), holes(o))

# no symbols, or one of length 1: the incomplete codes zlib takes
def lone(t: Tr) -> Bool:
  match t:
    case TNil{}:
      True{}
    case TLeaf{s}:
      False{}
    case TNode{z, o}:
      match z o:
        case TLeaf{a} TNil{}:
          True{}
        case TNil{} TLeaf{a}:
          True{}
        case _ _:
          False{}

def nodes(t: Tr) -> Nat:
  match t:
    case TNil{}:
      0n
    case TLeaf{s}:
      0n
    case TNode{z, o}:
      1n+Nat.add(nodes(z), nodes(o))

# the cell pointing at t, t being node j if it is a node
def ent(t: Tr, +j: Nat) -> U32:
  match t:
    case TNil{}:
      0
    case TLeaf{s}:
      U32.from_nat(1n+Nat.double(s))
    case TNode{z, o}:
      U32.from_nat(Nat.double(j))

# t's nodes in preorder, t being node j: node j's cells are 2j and 2j+1
def ser(t: Tr, +j: Nat, out: String) -> String:
  match t:
    case TNil{}:
      out
    case TLeaf{s}:
      out
    case TNode{+z, +o}:
      +jz = Nat.add(1n, j)
      +jo = Nat.add(1n, Nat.add(j, nodes(z)))
      ser(o, jo, ser(z, jz, Bytes.push(Bytes.push(out, ent(z, jz)), ent(o, jo))))

def flat.at(t: Tr, root: Bool) -> String:
  match root:
    case True{}:
      ser(t, 0n, "")
    case False{}:
      Bytes.push(Bytes.push("", 0), 0)

def is_node(t: Tr) -> Bool:
  match t:
    case TNode{z, o}:
      True{}
    case _:
      False{}

# the table the machine walks: node 0 is the root
def flat(+t: Tr) -> String:
  flat.at(t, is_node(t))

# Maybe the table of a code's lengths: None if over-subscribed, or
# incomplete other than as zlib allows (lone), or incomplete at all for
# the code length code (cl)
def table.ok(ok: Bool, +t: Tr) -> Maybe<&2, String>:
  match ok:
    case True{}:
      Some{flat(t)}
    case False{}:
      None{}

def table.at(m: Maybe<&2, Tr>, cl: Bool) -> Maybe<&2, String>:
  match m:
    case None{}:
      None{}
    case Some{+t}:
      table.ok(Nat.is_eq(holes(t), 0n) || (Bool.not(cl) && lone(t)), t)

def table(+lens: List<&2, Nat>, cl: Bool) -> Maybe<&2, String>:
  table.at(build(codes(lens)), cl)

# The fixed code
def reps(n: Nat, +x: Nat, t: List<&2, Nat>) -> List<&2, Nat>:
  match n:
    case 0n:
      t
    case 1n+p:
      Con{x, reps(p, x, t)}

def fixed_ll_lens() -> List<&2, Nat>:
  reps(144n, 8n, reps(112n, 9n, reps(24n, 7n, reps(8n, 8n, Nil{}))))

def fixed_d_lens() -> List<&2, Nat>:
  reps(32n, 5n, Nil{})

def some_or(m: Maybe<&2, String>) -> String:
  match m:
    case None{}:
      ""
    case Some{s}:
      s

# Lengths and distances
# ---------------------

# per length code 257..285: base, extra bits
def LBASE() -> List<&2, Nat>:
  [3n, 4n, 5n, 6n, 7n, 8n, 9n, 10n, 11n, 13n, 15n, 17n, 19n, 23n, 27n, 31n, 35n, 43n, 51n, 59n,
    67n, 83n, 99n, 115n, 131n, 163n, 195n, 227n, U32.to_nat(258)]

def LEXT() -> List<&2, Nat>:
  [0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 1n, 1n, 1n, 1n, 2n, 2n, 2n, 2n, 3n, 3n, 3n, 3n, 4n, 4n, 4n,
    4n, 5n, 5n, 5n, 5n, 0n]

# per distance code 0..29
def DBASE() -> List<&2, Nat>:
  [1n, 2n, 3n, 4n, 5n, 7n, 9n, 13n, 17n, 25n, 33n, 49n, 65n, 97n, 129n, 193n, U32.to_nat(257),
    U32.to_nat(385), U32.to_nat(513), U32.to_nat(769), U32.to_nat(1025), U32.to_nat(1537),
    U32.to_nat(2049), U32.to_nat(3073), U32.to_nat(4097), U32.to_nat(6145), U32.to_nat(8193),
    U32.to_nat(12289), U32.to_nat(16385), U32.to_nat(24577)]

def DEXT() -> List<&2, Nat>:
  [0n, 0n, 0n, 0n, 1n, 1n, 2n, 2n, 3n, 3n, 4n, 4n, 5n, 5n, 6n, 6n, 7n, 7n, 8n, 8n, 9n, 9n, 10n,
    10n, 11n, 11n, 12n, 12n, 13n, 13n]

def str_of(xs: List<&2, Nat>, out: String) -> String:
  match xs:
    case Nil{}:
      out
    case Con{x, t}:
      str_of(t, Bytes.push(out, U32.from_nat(x)))

# The fixed tables, written out: deflate_laws.bend's fixed_built holds
# each to the construction it stands for, and the fixed path reads and
# writes by them.

# the fixed literal/length code's table (table(fixed_ll_lens()))
def FLL() -> String:
  "\u{2}\u{d0}\u{4}R\u{6}$\u{8}\u{16}\u{a}\u{10}\u{c}\u{e}\u{201}\u{203}\u{205}\u{207}\u{12}\u{14}\u{209}\u{20b}\u{20d}\u{20f}\u{18}\u{1e}\u{1a}\u{1c}\u{211}\u{213}\u{215}\u{217} \u{22}\u{219}\u{21b}\u{21d}\u{21f}&4(.*,\u{221}\u{223}\u{225}\u{227}02\u{229}\u{22b}\u{22d}\u{22f}6D8>:<\u{1}\u{3}\u{5}\u{7}@B\u{9}\u{b}\u{d}\u{f}FLHJ\u{11}\u{13}\u{15}\u{17}NP\u{19}\u{1b}\u{1d}\u{1f}T\u{92}VtXfZ`\u{5c}^!#%\u{27}bd)+-/hnjl1357pr9;=?v\u{84}x~z|ACEG\u{80}\u{82}IKMO\u{86}\u{8c}\u{88}\u{8a}QSUW\u{8e}\u{90}Y[]_\u{94}\u{b2}\u{96}\u{a4}\u{98}\u{9e}\u{9a}\u{9c}aceg\u{a0}\u{a2}ikmo\u{a6}\u{ac}\u{a8}\u{aa}qsuw\u{ae}\u{b0}y{}\u{7f}\u{b4}\u{c2}\u{b6}\u{bc}\u{b8}\u{ba}\u{81}\u{83}\u{85}\u{87}\u{be}\u{c0}\u{89}\u{8b}\u{8d}\u{8f}\u{c4}\u{ca}\u{c6}\u{c8}\u{91}\u{93}\u{95}\u{97}\u{cc}\u{ce}\u{99}\u{9b}\u{9d}\u{9f}\u{d2}\u{150}\u{d4}\u{112}\u{d6}\u{f4}\u{d8}\u{e6}\u{da}\u{e0}\u{dc}\u{de}\u{a1}\u{a3}\u{a5}\u{a7}\u{e2}\u{e4}\u{a9}\u{ab}\u{ad}\u{af}\u{e8}\u{ee}\u{ea}\u{ec}\u{b1}\u{b3}\u{b5}\u{b7}\u{f0}\u{f2}\u{b9}\u{bb}\u{bd}\u{bf}\u{f6}\u{104}\u{f8}\u{fe}\u{fa}\u{fc}\u{c1}\u{c3}\u{c5}\u{c7}\u{100}\u{102}\u{c9}\u{cb}\u{cd}\u{cf}\u{106}\u{10c}\u{108}\u{10a}\u{d1}\u{d3}\u{d5}\u{d7}\u{10e}\u{110}\u{d9}\u{db}\u{dd}\u{df}\u{114}\u{132}\u{116}\u{124}\u{118}\u{11e}\u{11a}\u{11c}\u{e1}\u{e3}\u{e5}\u{e7}\u{120}\u{122}\u{e9}\u{eb}\u{ed}\u{ef}\u{126}\u{12c}\u{128}\u{12a}\u{f1}\u{f3}\u{f5}\u{f7}\u{12e}\u{130}\u{f9}\u{fb}\u{fd}\u{ff}\u{134}\u{142}\u{136}\u{13c}\u{138}\u{13a}\u{101}\u{103}\u{105}\u{107}\u{13e}\u{140}\u{109}\u{10b}\u{10d}\u{10f}\u{144}\u{14a}\u{146}\u{148}\u{111}\u{113}\u{115}\u{117}\u{14c}\u{14e}\u{119}\u{11b}\u{11d}\u{11f}\u{152}\u{1c0}\u{154}\u{182}\u{156}\u{164}\u{158}\u{15e}\u{15a}\u{15c}\u{231}\u{233}\u{235}\u{237}\u{160}\u{162}\u{239}\u{23b}\u{23d}\u{23f}\u{166}\u{174}\u{168}\u{16e}\u{16a}\u{16c}\u{121}\u{123}\u{125}\u{127}\u{170}\u{172}\u{129}\u{12b}\u{12d}\u{12f}\u{176}\u{17c}\u{178}\u{17a}\u{131}\u{133}\u{135}\u{137}\u{17e}\u{180}\u{139}\u{13b}\u{13d}\u{13f}\u{184}\u{1a2}\u{186}\u{194}\u{188}\u{18e}\u{18a}\u{18c}\u{141}\u{143}\u{145}\u{147}\u{190}\u{192}\u{149}\u{14b}\u{14d}\u{14f}\u{196}\u{19c}\u{198}\u{19a}\u{151}\u{153}\u{155}\u{157}\u{19e}\u{1a0}\u{159}\u{15b}\u{15d}\u{15f}\u{1a4}\u{1b2}\u{1a6}\u{1ac}\u{1a8}\u{1aa}\u{161}\u{163}\u{165}\u{167}\u{1ae}\u{1b0}\u{169}\u{16b}\u{16d}\u{16f}\u{1b4}\u{1ba}\u{1b6}\u{1b8}\u{171}\u{173}\u{175}\u{177}\u{1bc}\u{1be}\u{179}\u{17b}\u{17d}\u{17f}\u{1c2}\u{200}\u{1c4}\u{1e2}\u{1c6}\u{1d4}\u{1c8}\u{1ce}\u{1ca}\u{1cc}\u{181}\u{183}\u{185}\u{187}\u{1d0}\u{1d2}\u{189}\u{18b}\u{18d}\u{18f}\u{1d6}\u{1dc}\u{1d8}\u{1da}\u{191}\u{193}\u{195}\u{197}\u{1de}\u{1e0}\u{199}\u{19b}\u{19d}\u{19f}\u{1e4}\u{1f2}\u{1e6}\u{1ec}\u{1e8}\u{1ea}\u{1a1}\u{1a3}\u{1a5}\u{1a7}\u{1ee}\u{1f0}\u{1a9}\u{1ab}\u{1ad}\u{1af}\u{1f4}\u{1fa}\u{1f6}\u{1f8}\u{1b1}\u{1b3}\u{1b5}\u{1b7}\u{1fc}\u{1fe}\u{1b9}\u{1bb}\u{1bd}\u{1bf}\u{202}\u{220}\u{204}\u{212}\u{206}\u{20c}\u{208}\u{20a}\u{1c1}\u{1c3}\u{1c5}\u{1c7}\u{20e}\u{210}\u{1c9}\u{1cb}\u{1cd}\u{1cf}\u{214}\u{21a}\u{216}\u{218}\u{1d1}\u{1d3}\u{1d5}\u{1d7}\u{21c}\u{21e}\u{1d9}\u{1db}\u{1dd}\u{1df}\u{222}\u{230}\u{224}\u{22a}\u{226}\u{228}\u{1e1}\u{1e3}\u{1e5}\u{1e7}\u{22c}\u{22e}\u{1e9}\u{1eb}\u{1ed}\u{1ef}\u{232}\u{238}\u{234}\u{236}\u{1f1}\u{1f3}\u{1f5}\u{1f7}\u{23a}\u{23c}\u{1f9}\u{1fb}\u{1fd}\u{1ff}"

# the fixed distance code's table (table(fixed_d_lens()))
def FD() -> String:
  "\u{2} \u{4}\u{12}\u{6}\u{c}\u{8}\u{a}\u{1}\u{3}\u{5}\u{7}\u{e}\u{10}\u{9}\u{b}\u{d}\u{f}\u{14}\u{1a}\u{16}\u{18}\u{11}\u{13}\u{15}\u{17}\u{1c}\u{1e}\u{19}\u{1b}\u{1d}\u{1f}\u{22}0$*&(!#%\u{27},.)+-/28461357:<9;=?"

# the fixed literal/length code as the writer takes it: each symbol's code
def HLLC() -> String:
  "0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\u{5c}]^_`abcdefghijklmnopqrstuvwxyz{|}~\u{7f}\u{80}\u{81}\u{82}\u{83}\u{84}\u{85}\u{86}\u{87}\u{88}\u{89}\u{8a}\u{8b}\u{8c}\u{8d}\u{8e}\u{8f}\u{90}\u{91}\u{92}\u{93}\u{94}\u{95}\u{96}\u{97}\u{98}\u{99}\u{9a}\u{9b}\u{9c}\u{9d}\u{9e}\u{9f}\u{a0}\u{a1}\u{a2}\u{a3}\u{a4}\u{a5}\u{a6}\u{a7}\u{a8}\u{a9}\u{aa}\u{ab}\u{ac}\u{ad}\u{ae}\u{af}\u{b0}\u{b1}\u{b2}\u{b3}\u{b4}\u{b5}\u{b6}\u{b7}\u{b8}\u{b9}\u{ba}\u{bb}\u{bc}\u{bd}\u{be}\u{bf}\u{190}\u{191}\u{192}\u{193}\u{194}\u{195}\u{196}\u{197}\u{198}\u{199}\u{19a}\u{19b}\u{19c}\u{19d}\u{19e}\u{19f}\u{1a0}\u{1a1}\u{1a2}\u{1a3}\u{1a4}\u{1a5}\u{1a6}\u{1a7}\u{1a8}\u{1a9}\u{1aa}\u{1ab}\u{1ac}\u{1ad}\u{1ae}\u{1af}\u{1b0}\u{1b1}\u{1b2}\u{1b3}\u{1b4}\u{1b5}\u{1b6}\u{1b7}\u{1b8}\u{1b9}\u{1ba}\u{1bb}\u{1bc}\u{1bd}\u{1be}\u{1bf}\u{1c0}\u{1c1}\u{1c2}\u{1c3}\u{1c4}\u{1c5}\u{1c6}\u{1c7}\u{1c8}\u{1c9}\u{1ca}\u{1cb}\u{1cc}\u{1cd}\u{1ce}\u{1cf}\u{1d0}\u{1d1}\u{1d2}\u{1d3}\u{1d4}\u{1d5}\u{1d6}\u{1d7}\u{1d8}\u{1d9}\u{1da}\u{1db}\u{1dc}\u{1dd}\u{1de}\u{1df}\u{1e0}\u{1e1}\u{1e2}\u{1e3}\u{1e4}\u{1e5}\u{1e6}\u{1e7}\u{1e8}\u{1e9}\u{1ea}\u{1eb}\u{1ec}\u{1ed}\u{1ee}\u{1ef}\u{1f0}\u{1f1}\u{1f2}\u{1f3}\u{1f4}\u{1f5}\u{1f6}\u{1f7}\u{1f8}\u{1f9}\u{1fa}\u{1fb}\u{1fc}\u{1fd}\u{1fe}\u{1ff}\u{0}\u{1}\u{2}\u{3}\u{4}\u{5}\u{6}\u{7}\u{8}\u{9}\u{a}\u{b}\u{c}\u{d}\u{e}\u{f}\u{10}\u{11}\u{12}\u{13}\u{14}\u{15}\u{16}\u{17}\u{c0}\u{c1}\u{c2}\u{c3}\u{c4}\u{c5}\u{c6}\u{c7}"

# ... and its length (hc(fixed_ll_lens()))
def HLLL() -> String:
  "\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{7}\u{7}\u{7}\u{7}\u{7}\u{7}\u{7}\u{7}\u{7}\u{7}\u{7}\u{7}\u{7}\u{7}\u{7}\u{7}\u{7}\u{7}\u{7}\u{7}\u{7}\u{7}\u{7}\u{7}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}"

# the fixed distance code: each symbol's code
def HDC() -> String:
  "\u{0}\u{1}\u{2}\u{3}\u{4}\u{5}\u{6}\u{7}\u{8}\u{9}\u{a}\u{b}\u{c}\u{d}\u{e}\u{f}\u{10}\u{11}\u{12}\u{13}\u{14}\u{15}\u{16}\u{17}\u{18}\u{19}\u{1a}\u{1b}\u{1c}\u{1d}\u{1e}\u{1f}"

# ... and its length (hc(fixed_d_lens()))
def HDL() -> String:
  "\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}"

# the length code of each length 3..258, at lidx(l): the k whose run of
# 2^LEXT[k] lengths from LBASE[k] holds it
def LCS() -> String:
  "\u{0}\u{1}\u{2}\u{3}\u{4}\u{5}\u{6}\u{7}\u{8}\u{8}\u{9}\u{9}\u{a}\u{a}\u{b}\u{b}\u{c}\u{c}\u{c}\u{c}\u{d}\u{d}\u{d}\u{d}\u{e}\u{e}\u{e}\u{e}\u{f}\u{f}\u{f}\u{f}\u{10}\u{10}\u{10}\u{10}\u{10}\u{10}\u{10}\u{10}\u{11}\u{11}\u{11}\u{11}\u{11}\u{11}\u{11}\u{11}\u{12}\u{12}\u{12}\u{12}\u{12}\u{12}\u{12}\u{12}\u{13}\u{13}\u{13}\u{13}\u{13}\u{13}\u{13}\u{13}\u{14}\u{14}\u{14}\u{14}\u{14}\u{14}\u{14}\u{14}\u{14}\u{14}\u{14}\u{14}\u{14}\u{14}\u{14}\u{14}\u{15}\u{15}\u{15}\u{15}\u{15}\u{15}\u{15}\u{15}\u{15}\u{15}\u{15}\u{15}\u{15}\u{15}\u{15}\u{15}\u{16}\u{16}\u{16}\u{16}\u{16}\u{16}\u{16}\u{16}\u{16}\u{16}\u{16}\u{16}\u{16}\u{16}\u{16}\u{16}\u{17}\u{17}\u{17}\u{17}\u{17}\u{17}\u{17}\u{17}\u{17}\u{17}\u{17}\u{17}\u{17}\u{17}\u{17}\u{17}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1c}"

# the distance code of each distance, at didx(d), the same way
def DCS() -> String:
  "\u{0}\u{1}\u{2}\u{3}\u{4}\u{4}\u{5}\u{5}\u{6}\u{6}\u{6}\u{6}\u{7}\u{7}\u{7}\u{7}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{9}\u{a}\u{a}\u{a}\u{a}\u{a}\u{a}\u{a}\u{a}\u{a}\u{a}\u{a}\u{a}\u{a}\u{a}\u{a}\u{a}\u{b}\u{b}\u{b}\u{b}\u{b}\u{b}\u{b}\u{b}\u{b}\u{b}\u{b}\u{b}\u{b}\u{b}\u{b}\u{b}\u{c}\u{c}\u{c}\u{c}\u{c}\u{c}\u{c}\u{c}\u{c}\u{c}\u{c}\u{c}\u{c}\u{c}\u{c}\u{c}\u{c}\u{c}\u{c}\u{c}\u{c}\u{c}\u{c}\u{c}\u{c}\u{c}\u{c}\u{c}\u{c}\u{c}\u{c}\u{c}\u{d}\u{d}\u{d}\u{d}\u{d}\u{d}\u{d}\u{d}\u{d}\u{d}\u{d}\u{d}\u{d}\u{d}\u{d}\u{d}\u{d}\u{d}\u{d}\u{d}\u{d}\u{d}\u{d}\u{d}\u{d}\u{d}\u{d}\u{d}\u{d}\u{d}\u{d}\u{d}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{e}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{f}\u{0}\u{0}\u{10}\u{11}\u{12}\u{12}\u{13}\u{13}\u{14}\u{14}\u{14}\u{14}\u{15}\u{15}\u{15}\u{15}\u{16}\u{16}\u{16}\u{16}\u{16}\u{16}\u{16}\u{16}\u{17}\u{17}\u{17}\u{17}\u{17}\u{17}\u{17}\u{17}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{18}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{19}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1a}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1b}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1c}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}\u{1d}"

# LBASE, LEXT, DBASE and DEXT as the machine and the writer read them
def LBS() -> String:
  "\u{3}\u{4}\u{5}\u{6}\u{7}\u{8}\u{9}\u{a}\u{b}\u{d}\u{f}\u{11}\u{13}\u{17}\u{1b}\u{1f}#+3;CScs\u{83}\u{a3}\u{c3}\u{e3}\u{102}"

def LXS() -> String:
  "\u{0}\u{0}\u{0}\u{0}\u{0}\u{0}\u{0}\u{0}\u{1}\u{1}\u{1}\u{1}\u{2}\u{2}\u{2}\u{2}\u{3}\u{3}\u{3}\u{3}\u{4}\u{4}\u{4}\u{4}\u{5}\u{5}\u{5}\u{5}\u{0}"

def DBS() -> String:
  "\u{1}\u{2}\u{3}\u{4}\u{5}\u{7}\u{9}\u{d}\u{11}\u{19}!1Aa\u{81}\u{c1}\u{101}\u{181}\u{201}\u{301}\u{401}\u{601}\u{801}\u{c01}\u{1001}\u{1801}\u{2001}\u{3001}\u{4001}\u{6001}"

def DXS() -> String:
  "\u{0}\u{0}\u{0}\u{0}\u{1}\u{1}\u{2}\u{2}\u{3}\u{3}\u{4}\u{4}\u{5}\u{5}\u{6}\u{6}\u{7}\u{7}\u{8}\u{8}\u{9}\u{9}\u{a}\u{a}\u{b}\u{b}\u{c}\u{c}\u{d}\u{d}"

# Inflate
# =======

type Why is Data:
  BadBlock{}
  BadStored{}
  BadCounts{}
  BadCl{}
  BadRepeat{}
  NoEnd{}
  BadLit{}
  BadDist{}
  BadCode{}
  FarBack{}
  TooBig{}
  Truncated{}

def why.show(w: Why) -> String:
  match w:
    case BadBlock{}:
      "BadBlock"
    case BadStored{}:
      "BadStored"
    case BadCounts{}:
      "BadCounts"
    case BadCl{}:
      "BadCl"
    case BadRepeat{}:
      "BadRepeat"
    case NoEnd{}:
      "NoEnd"
    case BadLit{}:
      "BadLit"
    case BadDist{}:
      "BadDist"
    case BadCode{}:
      "BadCode"
    case FarBack{}:
      "FarBack"
    case TooBig{}:
      "TooBig"
    case Truncated{}:
      "Truncated"

# the tables a stream is decoded with, built once: the fixed code's two,
# and the length and distance codes' bases and extra bits
type Tabs is Data:
  Tabs{fll: String, fd: String, lb: String, lx: String, db: String, dx: String}

def tabs() -> Tabs:
  Tabs{FLL(), FD(), LBS(), LXS(), DBS(), DXS()}

# a Huffman block: whether it is the last, its two tables
type Blk is Data:
  Blk{last: Bool, ll: String, d: String}

# a dynamic block's code lengths as they are read: how many of each
# kind, how many lengths are still to come, those read (newest first),
# the code length code's table
type Dyn is Data:
  Dyn{last: Bool, nlit: Nat, ndist: Nat, left: Nat, lens: List<&2, Nat>, cl: String}

# what a run of bits is read for
type K is Data:
  KHead{}
  KLen{last: Bool}
  KNLen{last: Bool, len: List<&2, Bool>}
  KByte{last: Bool, left: Nat}
  KLenX{blk: Blk, base: Nat}
  KDistX{blk: Blk, len: Nat, base: Nat}
  KHlit{last: Bool}
  KHdist{last: Bool, nlit: Nat}
  KHclen{last: Bool, nlit: Nat, ndist: Nat}
  KCl{last: Bool, nlit: Nat, ndist: Nat, left: Nat, got: List<&2, Nat>}
  KRep{h: Dyn, base: Nat, v: Nat}

# what a symbol is decoded for
type SK is Data:
  SLit{blk: Blk}
  SDist{blk: Blk, len: Nat}
  SCl{h: Dyn}

# what the next bit does. Get: left more bits after this one, acc those
# read (newest first). Walk: a code, at node of tab. Skip: the bits to
# the next byte after a stored block's header. End: the stream is over;
# what follows it is not read. Bad: refused, for good.
type Mode is Data:
  Get{left: Nat, acc: List<&2, Bool>, k: K}
  Walk{node: Nat, tab: String, k: SK}
  Skip{last: Bool}
  End{}
  Bad{why: Why}

# the output and what the machine reads by: out, the bytes not yet taken
# with the window before them (keep of them taken already); n, all
# bytes written; cap, the most there may be; the tables
type O is Data:
  O{out: Bytes(), keep: Nat, n: Nat, cap: Nat, t: Tabs}

# the machine: its mode, its output, the offset of the next bit in its
# byte
type St is Data:
  St{m: Mode, o: O, bp: Nat}

# a machine at the start of a stream, at most cap bytes out
def new(cap: Nat) -> St:
  St{Get{2n, Nil{}, KHead{}}, O{"", 0n, 0n, cap, tabs()}, 0n}

def fail(o: O, bp: Nat, why: Why) -> St:
  St{Bad{why}, o, bp}

def done(o: O, bp: Nat) -> St:
  St{End{}, o, bp}

# after a block: the next header, or the end
def next_block(last: Bool, o: O, bp: Nat) -> St:
  match last:
    case True{}:
      done(o, bp)
    case False{}:
      St{Get{2n, Nil{}, KHead{}}, o, bp}

# one byte out, if the cap has room
def emit.if(ok: Bool, out: Bytes(), keep: Nat, n: Nat, cap: Nat, t: Tabs, c: U32, next: Mode,
  bp: Nat) -> St:
  match ok:
    case True{}:
      St{next, O{Bytes.push(out, c), keep, 1n+n, cap, t}, bp}
    case False{}:
      St{Bad{TooBig{}}, O{out, keep, n, cap, t}, bp}

def emit(o: O, c: U32, next: Mode, bp: Nat) -> St:
  match o:
    case O{out, keep, +n, +cap, t}:
      emit.if(Nat.is_lt(n, cap), out, keep, n, cap, t, c, next, bp)

# len bytes, each the one dist back
def copy.go(len: Nat, out: Bytes(), +dist: Nat) -> Bytes():
  match len:
    case 0n:
      out
    case 1n+p:
      +o = out
      +c = Bytes.get(o, Nat.sub(Bytes.len(o), dist))
      copy.go(p, Bytes.push(o, c), dist)

def copy.big(big: Bool, out: Bytes(), keep: Nat, n: Nat, cap: Nat, t: Tabs, +len: Nat,
  dist: Nat, next: Mode, bp: Nat) -> St:
  match big:
    case True{}:
      St{Bad{TooBig{}}, O{out, keep, n, cap, t}, bp}
    case False{}:
      St{next, O{copy.go(len, out, dist), keep, Nat.add(n, len), cap, t}, bp}

def copy.if(far: Bool, big: Bool, out: Bytes(), keep: Nat, n: Nat, cap: Nat, t: Tabs,
  len: Nat, dist: Nat, next: Mode, bp: Nat) -> St:
  match far:
    case True{}:
      St{Bad{FarBack{}}, O{out, keep, n, cap, t}, bp}
    case False{}:
      copy.big(big, out, keep, n, cap, t, len, dist, next, bp)

def copy(o: O, +len: Nat, +dist: Nat, next: Mode, bp: Nat) -> St:
  match o:
    case O{+out, keep, +n, +cap, t}:
      copy.if(Nat.is_lt(Bytes.len(out), dist), Nat.is_lt(cap, Nat.add(n, len)), out, keep, n,
        cap, t, len, dist, next, bp)

def lit_mode(b: Blk) -> Mode:
  match b:
    case Blk{last, +ll, d}:
      Walk{0n, ll, SLit{Blk{last, ll, d}}}

def dist_mode(b: Blk, len: Nat) -> Mode:
  match b:
    case Blk{last, ll, +d}:
      Walk{0n, d, SDist{Blk{last, ll, d}, len}}

def blk_last(b: Blk) -> Bool:
  match b:
    case Blk{last, ll, d}:
      last

# The fixed-width reads
# ---------------------

def stored_head(last: Bool, aligned: Bool, o: O, bp: Nat) -> St:
  match aligned:
    case True{}:
      St{Get{15n, Nil{}, KLen{last}}, o, bp}
    case False{}:
      St{Skip{last}, o, bp}

# a fixed Huffman block: its tables are the machine's
def fixed(last: Bool, o: O, bp: Nat) -> St:
  match o:
    case O{out, keep, n, cap, t}:
      match t:
        case Tabs{+fll, +fd, lb, lx, db, dx}:
          St{lit_mode(Blk{last, fll, fd}), O{out, keep, n, cap, Tabs{fll, fd, lb, lx, db, dx}}, bp}

def block(last: Bool, b1: Bool, b2: Bool, o: O, +bp: Nat) -> St:
  match b1 b2:
    case False{} False{}:
      stored_head(last, Nat.is_eq(bp, 0n), o, bp)
    case True{} False{}:
      fixed(last, o, bp)
    case False{} True{}:
      St{Get{4n, Nil{}, KHlit{last}}, o, bp}
    case True{} True{}:
      fail(o, bp, BadBlock{})

# a block's header, its three bits read (newest first)
def head(acc: List<&2, Bool>, o: O, +bp: Nat) -> St:
  match acc:
    case Con{b2, Con{b1, Con{last, Nil{}}}}:
      block(last, b1, b2, o, bp)
    case _:
      fail(o, bp, BadBlock{})

def stored_body(last: Bool, len: Nat, o: O, bp: Nat) -> St:
  match len:
    case 0n:
      next_block(last, o, bp)
    case 1n+p:
      St{Get{7n, Nil{}, KByte{last, p}}, o, bp}

def stored_nlen(ok: Bool, last: Bool, len: Nat, o: O, bp: Nat) -> St:
  match ok:
    case True{}:
      stored_body(last, len, o, bp)
    case False{}:
      fail(o, bp, BadStored{})

# a stored block's byte
def stored_byte(last: Bool, left: Nat, c: U32, o: O, bp: Nat) -> St:
  match last left:
    case True{} 0n:
      emit(o, c, End{}, bp)
    case False{} 0n:
      emit(o, c, Get{2n, Nil{}, KHead{}}, bp)
    case _ 1n+p:
      emit(o, c, Get{7n, Nil{}, KByte{last, p}}, bp)

# the code lengths are all read: the two tables
def dyn_end.tabs(last: Bool, ml: Maybe<&2, String>, md: Maybe<&2, String>, o: O, bp: Nat) ->
  St:
  match ml:
    case None{}:
      fail(o, bp, BadLit{})
    case Some{ll}:
      match md:
        case None{}:
          fail(o, bp, BadDist{})
        case Some{d}:
          St{lit_mode(Blk{last, ll, d}), o, bp}

def dyn_end.at(noend: Bool, last: Bool, +ll: List<&2, Nat>, +d: List<&2, Nat>, o: O, bp: Nat) ->
  St:
  match noend:
    case True{}:
      fail(o, bp, NoEnd{})
    case False{}:
      dyn_end.tabs(last, table(ll, False{}), table(d, False{}), o, bp)

def dyn_end(last: Bool, +nlit: Nat, lens: List<&2, Nat>, o: O, bp: Nat) -> St:
  +all = List.reverse(&2, Nat, lens)
  +ll = List.take(&2, Nat, all, nlit)
  dyn_end.at(Nat.is_eq(nth(ll, 256n), 0n), last, ll, List.drop(&2, Nat, all, nlit), o, bp)

# the next code length, or the end of them
def dyn_next(h: Dyn, o: O, bp: Nat) -> St:
  match h:
    case Dyn{last, nlit, ndist, left, lens, +cl}:
      match left:
        case 0n:
          dyn_end(last, nlit, lens, o, bp)
        case 1n+p:
          St{Walk{0n, cl, SCl{Dyn{last, nlit, ndist, 1n+p, lens, cl}}}, o, bp}

# the code length code's lengths are sent in this order
def CLORD() -> List<&2, Nat>:
  [16n, 17n, 18n, 0n, 8n, 7n, 9n, 6n, 10n, 5n, 11n, 4n, 12n, 3n, 13n, 2n, 14n, 1n, 15n]

# the length of symbol s among those sent in CLORD's order
def cl_of(ord: List<&2, Nat>, got: List<&2, Nat>, +s: Nat) -> Nat:
  match ord got:
    case Nil{} _:
      0n
    case Con{k, ot} Nil{}:
      0n
    case Con{k, ot} Con{g, gt}:
      pick(Nat.is_eq(k, s), g, cl_of(ot, gt, s))

def cl_lens(n: Nat, +got: List<&2, Nat>, +s: Nat) -> List<&2, Nat>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Con{cl_of(CLORD(), got, s), cl_lens(p, got, 1n+s)}

def cl_done(last: Bool, +nlit: Nat, +ndist: Nat, m: Maybe<&2, String>, o: O, bp: Nat) -> St:
  match m:
    case None{}:
      fail(o, bp, BadCl{})
    case Some{t}:
      dyn_next(Dyn{last, nlit, ndist, Nat.add(nlit, ndist), Nil{}, t}, o, bp)

def rep_n(n: Nat, +v: Nat, lens: List<&2, Nat>) -> List<&2, Nat>:
  match n:
    case 0n:
      lens
    case 1n+p:
      rep_n(p, v, Con{v, lens})

def rep.if(over: Bool, last: Bool, nlit: Nat, ndist: Nat, left: Nat, lens: List<&2, Nat>,
  cl: String, +count: Nat, v: Nat, o: O, bp: Nat) -> St:
  match over:
    case True{}:
      fail(o, bp, BadRepeat{})
    case False{}:
      dyn_next(Dyn{last, nlit, ndist, Nat.sub(left, count), rep_n(count, v, lens), cl}, o, bp)

# a repeat of count, if it fits
def rep(h: Dyn, +count: Nat, v: Nat, o: O, bp: Nat) -> St:
  match h:
    case Dyn{last, nlit, ndist, +left, lens, cl}:
      rep.if(Nat.is_lt(left, count), last, nlit, ndist, left, lens, cl, count, v, o, bp)

def counts_ok(+nlit: Nat, +ndist: Nat) -> Bool:
  Bool.not(Nat.is_lt(U32.to_nat(286), nlit) || Nat.is_lt(30n, ndist))

def hclen.if(ok: Bool, last: Bool, nlit: Nat, ndist: Nat, ncl: Nat, o: O, bp: Nat) -> St:
  match ok:
    case True{}:
      St{Get{2n, Nil{}, KCl{last, nlit, ndist, ncl, Nil{}}}, o, bp}
    case False{}:
      fail(o, bp, BadCounts{})

def cl_got(last: Bool, nlit: Nat, ndist: Nat, left: Nat, got: List<&2, Nat>, o: O, bp: Nat) ->
  St:
  match left:
    case 0n:
      cl_done(last, nlit, ndist, table(cl_lens(19n, List.reverse(&2, Nat, got), 0n), True{}),
        o, bp)
    case 1n+p:
      St{Get{2n, Nil{}, KCl{last, nlit, ndist, p, got}}, o, bp}

# NLEN's bit against LEN's: its complement
def compl.at(x: Bool, y: Bool, r: Bool) -> Bool:
  match x y:
    case True{} False{}:
      r
    case False{} True{}:
      r
    case True{} True{}:
      False{}
    case False{} False{}:
      False{}

# NLEN is LEN's ones' complement: the two, bit for bit, newest first
def compl(a: List<&2, Bool>, b: List<&2, Bool>) -> Bool:
  match a b:
    case Nil{} Nil{}:
      True{}
    case Con{x, s} Con{y, t}:
      compl.at(x, y, compl(s, t))
    case _ _:
      False{}

# a run of bits is read, acc (newest first): what it was for
def fire(k: K, acc: List<&2, Bool>, o: O, +bp: Nat) -> St:
  match k:
    case KHead{}:
      head(acc, o, bp)
    case KLen{last}:
      St{Get{15n, Nil{}, KNLen{last, acc}}, o, bp}
    case KNLen{last, +len}:
      stored_nlen(compl(len, acc), last, hval(len, 0n), o, bp)
    case KByte{last, left}:
      stored_byte(last, left, U32.from_nat(hval(acc, 0n)), o, bp)
    case KLenX{blk, base}:
      St{dist_mode(blk, Nat.add(base, hval(acc, 0n))), o, bp}
    case KDistX{blk, len, base}:
      copy(o, len, Nat.add(base, hval(acc, 0n)), lit_mode(blk), bp)
    case KHlit{last}:
      St{Get{4n, Nil{}, KHdist{last, Nat.add(U32.to_nat(257), hval(acc, 0n))}}, o, bp}
    case KHdist{last, nlit}:
      St{Get{3n, Nil{}, KHclen{last, nlit, 1n+hval(acc, 0n)}}, o, bp}
    case KHclen{last, +nlit, +ndist}:
      hclen.if(counts_ok(nlit, ndist), last, nlit, ndist, Nat.add(3n, hval(acc, 0n)),
        o, bp)
    case KCl{last, nlit, ndist, left, got}:
      cl_got(last, nlit, ndist, left, Con{hval(acc, 0n), got}, o, bp)
    case KRep{h, base, v}:
      rep(h, Nat.add(base, hval(acc, 0n)), v, o, bp)

# The symbols
# -----------

def len_x(blk: Blk, base: Nat, x: Nat, o: O, bp: Nat) -> St:
  match x:
    case 0n:
      St{dist_mode(blk, base), o, bp}
    case 1n+p:
      St{Get{p, Nil{}, KLenX{blk, base}}, o, bp}

# length code i: its base and extra bits from the tables
def len_code(blk: Blk, +i: Nat, o: O, bp: Nat) -> St:
  match o:
    case O{out, keep, n, cap, t}:
      match t:
        case Tabs{fll, fd, +lb, +lx, db, dx}:
          len_x(blk, U32.to_nat(Bytes.get(lb, i)), U32.to_nat(Bytes.get(lx, i)),
            O{out, keep, n, cap, Tabs{fll, fd, lb, lx, db, dx}}, bp)

def lit.c(ok: Bool, blk: Blk, +i: Nat, o: O, bp: Nat) -> St:
  match ok:
    case True{}:
      len_code(blk, i, o, bp)
    case False{}:
      fail(o, bp, BadCode{})

def lit.b(eob: Bool, blk: Blk, +s: Nat, o: O, bp: Nat) -> St:
  match eob:
    case True{}:
      next_block(blk_last(blk), o, bp)
    case False{}:
      lit.c(Nat.is_lt(s, U32.to_nat(286)), blk, Nat.sub(s, U32.to_nat(257)), o, bp)

# a literal/length symbol
def lit(is_lit: Bool, blk: Blk, +s: Nat, o: O, bp: Nat) -> St:
  match is_lit:
    case True{}:
      emit(o, U32.from_nat(s), lit_mode(blk), bp)
    case False{}:
      lit.b(Nat.is_eq(s, 256n), blk, s, o, bp)

def dist_x(blk: Blk, +len: Nat, base: Nat, x: Nat, o: O, bp: Nat) -> St:
  match x:
    case 0n:
      copy(o, len, base, lit_mode(blk), bp)
    case 1n+p:
      St{Get{p, Nil{}, KDistX{blk, len, base}}, o, bp}

# distance code s: its base and extra bits from the tables
def dist_code(blk: Blk, len: Nat, +s: Nat, o: O, bp: Nat) -> St:
  match o:
    case O{out, keep, n, cap, t}:
      match t:
        case Tabs{fll, fd, lb, lx, +db, +dx}:
          dist_x(blk, len, U32.to_nat(Bytes.get(db, s)), U32.to_nat(Bytes.get(dx, s)),
            O{out, keep, n, cap, Tabs{fll, fd, lb, lx, db, dx}}, bp)

# a distance symbol
def dist(ok: Bool, blk: Blk, len: Nat, +s: Nat, o: O, bp: Nat) -> St:
  match ok:
    case True{}:
      dist_code(blk, len, s, o, bp)
    case False{}:
      fail(o, bp, BadCode{})

def cl_len(h: Dyn, s: Nat, o: O, bp: Nat) -> St:
  match h:
    case Dyn{last, nlit, ndist, left, lens, cl}:
      dyn_next(Dyn{last, nlit, ndist, Nat.sub(left, 1n), Con{s, lens}, cl}, o, bp)

def cl_16(h: Dyn, o: O, bp: Nat) -> St:
  match h:
    case Dyn{last, nlit, ndist, left, lens, cl}:
      match lens:
        case Nil{}:
          fail(o, bp, BadRepeat{})
        case Con{+v, t}:
          St{Get{1n, Nil{}, KRep{Dyn{last, nlit, ndist, left, Con{v, t}, cl}, 3n, v}}, o, bp}

# a code length code symbol
def clsym(h: Dyn, s: Nat, o: O, bp: Nat) -> St:
  match s:
    case 16n:
      cl_16(h, o, bp)
    case 17n:
      St{Get{2n, Nil{}, KRep{h, 3n, 0n}}, o, bp}
    case 18n:
      St{Get{6n, Nil{}, KRep{h, 11n, 0n}}, o, bp}
    case _:
      cl_len(h, s, o, bp)

def sym(k: SK, +s: Nat, o: O, bp: Nat) -> St:
  match k:
    case SLit{blk}:
      lit(Nat.is_lt(s, 256n), blk, s, o, bp)
    case SDist{blk, len}:
      dist(Nat.is_lt(s, 30n), blk, len, s, o, bp)
    case SCl{h}:
      clsym(h, s, o, bp)

def walk.lr(tab: String, q: Nat, leaf: Bool, k: SK, o: O, bp: Nat) -> St:
  match leaf:
    case True{}:
      sym(k, q, o, bp)
    case False{}:
      St{Walk{q, tab, k}, o, bp}

def walk.at(tab: String, zero: Bool, qr: Nat & Nat, k: SK, o: O, bp: Nat) -> St:
  match zero:
    case True{}:
      fail(o, bp, BadCode{})
    case False{}:
      (q, r) = qr
      walk.lr(tab, q, Nat.is_eq(r, 1n), k, o, bp)

# a cell of a table: none, a node, a symbol
def walk(tab: String, +x: Nat, k: SK, o: O, bp: Nat) -> St:
  walk.at(tab, Nat.is_eq(x, 0n), Nat.divmod(x, 2n), k, o, bp)

# The machine
# -----------

# one bit, bp being the offset of the bit after it
def mode(m: Mode, b: Bool, o: O, +bp: Nat) -> St:
  match m:
    case Get{left, acc, k}:
      match left:
        case 0n:
          fire(k, Con{b, acc}, o, bp)
        case 1n+p:
          St{Get{p, Con{b, acc}, k}, o, bp}
    case Walk{node, +tab, k}:
      walk(tab, U32.to_nat(Bytes.get(tab, Nat.add(Nat.double(node), Nat.bit(b, 0n)))), k, o, bp)
    case Skip{last}:
      stored_head(last, Nat.is_eq(bp, 0n), o, bp)
    case End{}:
      St{End{}, o, bp}
    case Bad{why}:
      St{Bad{why}, o, bp}

def next_bp(+bp: Nat) -> Nat:
  pick(Nat.is_eq(bp, 7n), 0n, 1n+bp)

def bstep(st: St, b: Bool) -> St:
  match st:
    case St{m, o, bp}:
      mode(m, b, o, next_bp(bp))

# one byte: its eight bits, low first
def step(st: St, +c: U32) -> St:
  bstep(bstep(bstep(bstep(bstep(bstep(bstep(bstep(st, bit(c, 0n)), bit(c, 1n)), bit(c, 2n)),
    bit(c, 3n)), bit(c, 4n)), bit(c, 5n)), bit(c, 6n)), bit(c, 7n))

# the step as the reader kit (wire/reader.bend) takes it: nothing beside
# the state
def wstep(e: Unit, st: St, c: U32) -> St:
  step(st, c)

def wadv(e: Unit, s: Bytes(), st: St) -> St & Bytes():
  Wr.one.step(~Unit, ~St, ~wstep, e, s, st)

# a read, fed to the machine
def feed(+s: Bytes(), st: St) -> St:
  Wr.feed_buf(~Unit, ~St, ~wstep, ~wadv, Unit{}, s, st)

# the same over a list of bytes: what the laws speak of
def feed_list(bs: List<&2, U32>, st: St) -> St:
  Wr.feed(~Unit, ~St, ~wstep, Unit{}, bs, st)

# the bytes past the window, and the machine with the window only
def take(st: St) -> Bytes() & St:
  match st:
    case St{m, o, bp}:
      match o:
        case O{+out, keep, n, cap, t}:
          +w = Nat.sub(Bytes.len(out), K32())
          (Bytes.drop(out, keep), St{m, O{Bytes.drop(out, w), Nat.sub(Bytes.len(out), w), n, cap,
            t}, bp})

# the end of input: the output not yet taken, or why there is none
def finish(st: St) -> Result<&2, &2, Why, Bytes()>:
  match st:
    case St{m, o, bp}:
      match m o:
        case End{} O{out, keep, n, cap, t}:
          Done{Bytes.drop(out, keep)}
        case Bad{why} _:
          Fail{why}
        case _ _:
          Fail{Truncated{}}

# whether the stream has ended
def ended(st: St) -> Bool:
  match st:
    case St{m, o, bp}:
      match m:
        case End{}:
          True{}
        case _:
          False{}

# all bytes written so far
def written(st: St) -> Nat:
  match st:
    case St{m, o, bp}:
      match o:
        case O{out, keep, n, cap, t}:
          n


# Inflate, fast
# =============
#
# The machine steps a bit at a time and builds its state at every bit.
# A whole stream is read faster where the machine is at the start of a
# literal/length code: from there fi.dec reads a symbol whole, its code
# (fi.walk: the machine's walk, cell by cell), its extra bits (fi.get:
# the machine's Get) and its distance, with the same tables, the same
# checks in the same order and the bits the machine would read, at the
# same offsets; a copy reads the byte it copies where it lies (fi.copy,
# copy.go's loop). Anything else -- an end of block, a code, length or
# distance the machine refuses, a cap reached, the input's end -- is
# left to the machine, which steps its bit. inflate_proof.bend proves the
# driver (fi.drv) is the machine over the stream's bits, whatever the
# stream, so D.inflate is finish(feed(s, new(cap))) (law inflate_fast).


# the bit at bit r of byte q, as the machine reads it
def fi.b(+s: Bytes(), +q: Nat, +r: Nat) -> Bool:
  bit(Bytes.get(s, q), r)

# the byte after that bit
def fi.nq(+q: Nat, +r: Nat) -> Nat:
  pick(Nat.is_eq(r, 7n), 1n+q, q)

# whether byte q is there to read
def fi.in(+s: Bytes(), +q: Nat) -> Bool:
  Nat.is_lt(q, Bytes.len(s))

# the cell the machine reads at node for the bit b (mode's Walk row)
def fi.cell(+tab: String, +node: Nat, b: Bool) -> Nat:
  U32.to_nat(Bytes.get(tab, Nat.add(Nat.double(node), Nat.bit(b, 0n))))

# what a cell says, as walk reads it: go on from a node, a symbol, or
# no code
type Wn is Data:
  WGo{n: Nat}
  WSym{s: Nat}
  WBad{}

def fi.step.lr(q: Nat, leaf: Bool) -> Wn:
  match leaf:
    case True{}:
      WSym{q}
    case False{}:
      WGo{q}

def fi.step.at(zero: Bool, qr: Nat & Nat) -> Wn:
  match zero:
    case True{}:
      WBad{}
    case False{}:
      (q, r) = qr
      fi.step.lr(q, Nat.is_eq(r, 1n))

def fi.step(+x: Nat) -> Wn:
  fi.step.at(Nat.is_eq(x, 0n), Nat.divmod(x, 2n))

# a code read from bit r of byte q: the symbol and where it ends, or
# none (no code, the input ends, or k bits did not reach one)
type Wk is Data:
  WLeaf{s: Nat, q: Nat, r: Nat}
  WStop{}

def fi.walk(k: Nat, w: Wn, ok: Bool, +tab: String, +s: Bytes(), +q: Nat, +r: Nat) -> Wk:
  match k w ok:
    case _ WSym{sy} _:
      WLeaf{sy, q, r}
    case 1n+p WGo{n} True{}:
      +q2 = fi.nq(q, r)
      fi.walk(p, fi.step(fi.cell(tab, n, fi.b(s, q, r))), fi.in(s, q2), tab, s, q2, next_bp(r))
    case _ _ _:
      WStop{}

# k bits more, as the machine's Get gathers them (newest first)
type Gt is Data:
  Gt{acc: List<&2, Bool>, q: Nat, r: Nat}
  GStop{}

def fi.get(k: Nat, ok: Bool, +s: Bytes(), +q: Nat, +r: Nat, acc: List<&2, Bool>) -> Gt:
  match k ok:
    case 0n _:
      Gt{acc, q, r}
    case 1n+p True{}:
      +q2 = fi.nq(q, r)
      fi.get(p, fi.in(s, q2), s, q2, next_bp(r), Con{fi.b(s, q, r), acc})
    case 1n+p False{}:
      GStop{}

def fi.at(+s: String, +i: Nat) -> Nat:
  U32.to_nat(Bytes.get(s, i))

# The symbols
# -----------
#
# The next symbol of a Huffman block, read whole the way sym, lit,
# len_x, dist and copy read it: a literal, a copy, or one the fast
# path leaves to the machine (an end of block, a refusal, the input's
# end), with the position after it.

type Dc is Data:
  DLit{c: Nat, q: Nat, r: Nat}
  DCopy{len: Nat, dist: Nat, q: Nat, r: Nat}
  DStop{}

def fi.cp(far: Bool, big: Bool, +len: Nat, +dist: Nat, +q: Nat, +r: Nat) -> Dc:
  match far big:
    case False{} False{}:
      DCopy{len, dist, q, r}
    case _ _:
      DStop{}

def fi.copy.ok(+len: Nat, +dist: Nat, +q: Nat, +r: Nat, +olen: Nat, +n: Nat, +cap: Nat) -> Dc:
  fi.cp(Nat.is_lt(olen, dist), Nat.is_lt(cap, Nat.add(n, len)), len, dist, q, r)

def fi.dist.g(g: Gt, +len: Nat, +base: Nat, +olen: Nat, +n: Nat, +cap: Nat) -> Dc:
  match g:
    case Gt{acc, +q, +r}:
      fi.copy.ok(len, Nat.add(base, hval(acc, 0n)), q, r, olen, n, cap)
    case GStop{}:
      DStop{}

def fi.dist_x(x: Nat, +base: Nat, +s: Bytes(), +len: Nat, +q: Nat, +r: Nat, +olen: Nat, +n: Nat,
  +cap: Nat) -> Dc:
  match x:
    case 0n:
      fi.copy.ok(len, base, q, r, olen, n, cap)
    case 1n+p:
      fi.dist.g(fi.get(1n+p, fi.in(s, q), s, q, r, Nil{}), len, base, olen, n, cap)

def fi.dist(ok: Bool, +ds: Nat, +s: Bytes(), +len: Nat, +q: Nat, +r: Nat, +db: String, +dx: String,
  +olen: Nat, +n: Nat, +cap: Nat) -> Dc:
  match ok:
    case True{}:
      fi.dist_x(fi.at(dx, ds), fi.at(db, ds), s, len, q, r, olen, n, cap)
    case False{}:
      DStop{}

def fi.dsym(wk: Wk, +s: Bytes(), +len: Nat, +db: String, +dx: String, +olen: Nat, +n: Nat, +cap: Nat) ->
  Dc:
  match wk:
    case WLeaf{+ds, +q, +r}:
      fi.dist(Nat.is_lt(ds, 30n), ds, s, len, q, r, db, dx, olen, n, cap)
    case WStop{}:
      DStop{}

def fi.dwalk(+len: Nat, +s: Bytes(), +q: Nat, +r: Nat, +d: String, +db: String, +dx: String, +olen: Nat,
  +n: Nat, +cap: Nat) -> Dc:
  fi.dsym(fi.walk(16n, WGo{0n}, fi.in(s, q), d, s, q, r), s, len, db, dx, olen, n, cap)

def fi.len.g(g: Gt, +base: Nat, +s: Bytes(), +d: String, +db: String, +dx: String, +olen: Nat,
  +n: Nat, +cap: Nat) -> Dc:
  match g:
    case Gt{acc, +q, +r}:
      fi.dwalk(Nat.add(base, hval(acc, 0n)), s, q, r, d, db, dx, olen, n, cap)
    case GStop{}:
      DStop{}

def fi.len_x(x: Nat, +base: Nat, +s: Bytes(), +q: Nat, +r: Nat, +d: String, +db: String,
  +dx: String, +olen: Nat, +n: Nat, +cap: Nat) -> Dc:
  match x:
    case 0n:
      fi.dwalk(base, s, q, r, d, db, dx, olen, n, cap)
    case 1n+p:
      fi.len.g(fi.get(1n+p, fi.in(s, q), s, q, r, Nil{}), base, s, d, db, dx, olen, n, cap)

def fi.lit.c(ok: Bool, +i: Nat, +s: Bytes(), +q: Nat, +r: Nat, +d: String, +lb: String, +lx: String,
  +db: String, +dx: String, +olen: Nat, +n: Nat, +cap: Nat) -> Dc:
  match ok:
    case True{}:
      fi.len_x(fi.at(lx, i), fi.at(lb, i), s, q, r, d, db, dx, olen, n, cap)
    case False{}:
      DStop{}

def fi.lit.b(eob: Bool, +sy: Nat, +s: Bytes(), +q: Nat, +r: Nat, +d: String, +lb: String,
  +lx: String, +db: String, +dx: String, +olen: Nat, +n: Nat, +cap: Nat) -> Dc:
  match eob:
    case True{}:
      DStop{}
    case False{}:
      fi.lit.c(Nat.is_lt(sy, U32.to_nat(286)), Nat.sub(sy, U32.to_nat(257)), s, q, r, d, lb, lx, db, dx,
        olen, n, cap)

def fi.emit(ok: Bool, +sy: Nat, +q: Nat, +r: Nat) -> Dc:
  match ok:
    case True{}:
      DLit{sy, q, r}
    case False{}:
      DStop{}

def fi.lit(is_lit: Bool, +sy: Nat, +s: Bytes(), +q: Nat, +r: Nat, +d: String, +lb: String,
  +lx: String, +db: String, +dx: String, +olen: Nat, +n: Nat, +cap: Nat) -> Dc:
  match is_lit:
    case True{}:
      fi.emit(Nat.is_lt(n, cap), sy, q, r)
    case False{}:
      fi.lit.b(Nat.is_eq(sy, 256n), sy, s, q, r, d, lb, lx, db, dx, olen, n, cap)

def fi.lsym(wk: Wk, +s: Bytes(), +d: String, +lb: String, +lx: String, +db: String, +dx: String,
  +olen: Nat, +n: Nat, +cap: Nat) -> Dc:
  match wk:
    case WLeaf{+sy, +q, +r}:
      fi.lit(Nat.is_lt(sy, 256n), sy, s, q, r, d, lb, lx, db, dx, olen, n, cap)
    case WStop{}:
      DStop{}

# the next symbol at bit r of byte q, its code read with tab
def fi.dec(+s: Bytes(), +q: Nat, +r: Nat, +tab: String, +d: String, +lb: String, +lx: String,
  +db: String, +dx: String, +olen: Nat, +n: Nat, +cap: Nat) -> Dc:
  fi.lsym(fi.walk(16n, WGo{0n}, fi.in(s, q), tab, s, q, r), s, d, lb, lx, db, dx, olen, n, cap)

def fi.back(+o: Bytes(), +dist: Nat) -> U32:
  Bytes.get(o, Nat.sub(Bytes.len(o), dist))

# copy.go, with the byte read where it lies
def fi.copy(len: Nat, +out: Bytes(), +dist: Nat) -> Bytes():
  match len:
    case 0n:
      out
    case 1n+p:
      +c = fi.back(out, dist)
      fi.copy(p, Bytes.push(out, c), dist)

def fi.len(+o: Bytes()) -> Nat:
  Bytes.len(o)

# where the fast path stopped
type Fr is Data:
  Fr{q: Nat, r: Nat, out: Bytes(), n: Nat}

# symbols until one is left to the machine
def fi.run(k: Nat, dc: Dc, +s: Bytes(), +ll: String, +d: String, +lb: String, +lx: String,
  +db: String, +dx: String, +q: Nat, +r: Nat, out: Bytes(), +n: Nat, +cap: Nat) -> Fr:
  match k dc:
    case 1n+p DLit{+c, +q2, +r2}:
      +o2 = Bytes.push(out, U32.from_nat(c))
      fi.run(p, fi.dec(s, q2, r2, ll, d, lb, lx, db, dx, fi.len(o2), 1n+n, cap), s, ll, d, lb, lx, db, dx,
        q2, r2, o2, 1n+n, cap)
    case 1n+p DCopy{+len, +dist, +q2, +r2}:
      +o2 = fi.copy(len, out, dist)
      fi.run(p, fi.dec(s, q2, r2, ll, d, lb, lx, db, dx, fi.len(o2), Nat.add(n, len), cap), s, ll, d, lb,
        lx, db, dx, q2, r2, o2, Nat.add(n, len), cap)
    case _ _:
      Fr{q, r, out, n}

# The driver
# ----------

# the bits of a stream, each byte's low first
def fi.bits(s: Bytes()) -> List<&2, Bool>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{Chr{c}, t}:
      List.append(&2, Bool, unbyte(c), fi.bits(t))

# the machine over bits
def fi.bfeed(bs: List<&2, Bool>, st: St) -> St:
  match bs:
    case Nil{}:
      st
    case Con{b, t}:
      fi.bfeed(t, bstep(st, b))

# the rest of the input from bit r of its first byte, as bits
def fi.rest(t: Bytes(), +r: Nat) -> List<&2, Bool>:
  match t:
    case SNil{}:
      Nil{}
    case SCon{Chr{c}, u}:
      List.append(&2, Bool, List.drop(&2, Bool, unbyte(c), r), fi.bits(u))

type Dv is Data:
  Dv{q: Nat, r: Nat, st: St, go: Bool}

# the machine a bit on
def fi.bit(+s: Bytes(), +q: Nat, +r: Nat, st: St) -> Dv:
  +q2 = fi.nq(q, r)
  Dv{q2, next_bp(r), bstep(st, fi.b(s, q, r)), fi.in(s, q2)}

def fi.fr(f: Fr, +s: Bytes(), last: Bool, +ll: String, +d: String, +keep: Nat, +cap: Nat, t: Tabs) -> Dv:
  match f:
    case Fr{+q, +r, out, n}:
      Dv{q, r, St{lit_mode(Blk{last, ll, d}), O{out, keep, n, cap, t}, r}, fi.in(s, q)}

# a first symbol read whole, and then the rest the fast path reads
def fi.first(dc: Dc, +s: Bytes(), +q: Nat, +r: Nat, +tab: String, last: Bool, +ll: String, +d: String,
  out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, fll: String, fd: String, +lb: String, +lx: String,
  +db: String, +dx: String) -> Dv:
  match dc:
    case DStop{}:
      fi.bit(s, q, r, St{Walk{0n, tab, SLit{Blk{last, ll, d}}}, O{out, keep, n, cap,
        Tabs{fll, fd, lb, lx, db, dx}}, r})
    case DLit{+c, +q2, +r2}:
      +o2 = Bytes.push(out, U32.from_nat(c))
      fi.fr(fi.run(Bytes.len(s), fi.dec(s, q2, r2, ll, d, lb, lx, db, dx, fi.len(o2), 1n+n, cap), s, ll, d,
        lb, lx, db, dx, q2, r2, o2, 1n+n, cap), s, last, ll, d, keep, cap, Tabs{fll, fd, lb, lx, db, dx})
    case DCopy{+len, +dist, +q2, +r2}:
      +o2 = fi.copy(len, out, dist)
      fi.fr(fi.run(Bytes.len(s), fi.dec(s, q2, r2, ll, d, lb, lx, db, dx, fi.len(o2), Nat.add(n, len), cap),
        s, ll, d, lb, lx, db, dx, q2, r2, o2, Nat.add(n, len), cap), s, last, ll, d, keep, cap,
        Tabs{fll, fd, lb, lx, db, dx})

def fi.fast(+s: Bytes(), +q: Nat, +r: Nat, +tab: String, last: Bool, +ll: String, +d: String, o: O) ->
  Dv:
  match o:
    case O{+out, +keep, +n, +cap, t}:
      match t:
        case Tabs{fll, fd, +lb, +lx, +db, +dx}:
          fi.first(fi.dec(s, q, r, tab, d, lb, lx, db, dx, fi.len(out), n, cap), s, q, r, tab, last, ll, d,
            out, keep, n, cap, fll, fd, lb, lx, db, dx)

# at node 0 of a literal code at the machine's own bit, the fast path;
# anywhere else, a bit
def fi.at.bp(same: Bool, +s: Bytes(), +q: Nat, +r: Nat, +tab: String, last: Bool, +ll: String,
  +d: String, o: O, +bp: Nat) -> Dv:
  match same:
    case True{}:
      fi.fast(s, q, r, tab, last, ll, d, o)
    case False{}:
      fi.bit(s, q, r, St{Walk{0n, tab, SLit{Blk{last, ll, d}}}, o, bp})

def fi.node(+s: Bytes(), +q: Nat, +r: Nat, st: St) -> Dv:
  match st:
    case St{m, o, +bp}:
      match m:
        case Walk{node, +tab, sk}:
          match node sk:
            case 0n SLit{blk}:
              match blk:
                case Blk{last, +ll, +d}:
                  fi.at.bp(Nat.is_eq(bp, r), s, q, r, tab, last, ll, d, o, bp)
            case _ _:
              fi.bit(s, q, r, St{Walk{node, tab, sk}, o, bp})
        case _:
          fi.bit(s, q, r, St{m, o, bp})

def fi.drv(k: Nat, +s: Bytes(), dv: Dv) -> St:
  match k dv:
    case 1n+p Dv{+q, +r, st, True{}}:
      fi.drv(p, s, fi.node(s, q, r, st))
    case 0n Dv{+q, +r, st, True{}}:
      fi.bfeed(fi.rest(Bytes.drop(s, q), r), st)
    case _ Dv{q, r, st, False{}}:
      st

# a whole raw deflate stream, at most cap bytes out: the machine over
# it (law inflate_fast), driven by the fast path
def inflate(cap: Nat, +s: Bytes()) -> Result<&2, &2, Why, Bytes()>:
  finish(fi.drv(Nat.add(Nat.mul(8n, Bytes.len(s)), 1n), s, Dv{0n, 0n, new(cap), fi.in(s, 0n)}))

# Deflate
# =======

type Tok is Data:
  Lit{c: U32}
  Ref{len: Nat, dist: Nat}

# The bit writer: out, the whole bytes; pend, the bits of the byte being
# filled, newest first. The eighth bit fills the byte: out it goes.
type W is Data:
  W{out: Bytes(), pend: List<&2, Bool>}

# one bit
def put(w: W, b: Bool) -> W:
  match w:
    case W{out, Con{p6, Con{p5, Con{p4, Con{p3, Con{p2, Con{p1, Con{p0, Nil{}}}}}}}}}:
      W{Bytes.push(out, byte_of([b, p6, p5, p4, p3, p2, p1, p0])), Nil{}}
    case W{out, pend}:
      W{out, Con{b, pend}}

# the low n bits of v, low first: a field, an extra
def putx(n: Nat, w: W, +v: Nat) -> W:
  match n:
    case 0n:
      w
    case 1n+p:
      putx(p, put(w, Nat.is_eq(Nat.mod(v, 2n), 1n)), Nat.div(v, 2n))

# the low n bits of c, high first: a Huffman code
def putm(+n: Nat, w: W, +c: U32) -> W:
  match n:
    case 0n:
      w
    case 1n+p:
      putm(p, put(w, bit(c, Nat.sub(n, 1n))), c)

# zeros to the next byte
def align(w: W) -> W:
  match w:
    case W{out, +pend}:
      putx(Nat.mod(Nat.sub(8n, List.length(&2, Bool, pend)), 8n), W{out, pend}, 0n)

# bytes as they are, the writer being at a byte
def put_raw(w: W, +b: Bytes()) -> W:
  match w:
    case W{out, pend}:
      W{Bytes.append(out, b), pend}

def w_out(w: W) -> Bytes():
  match w:
    case W{out, pend}:
      out

def w_new() -> W:
  W{"", Nil{}}

# The code tables
# ---------------

def pow2(n: Nat) -> Nat:
  match n:
    case 0n:
      1n
    case 1n+p:
      Nat.double(pow2(p))

# a code as the writer takes it: each symbol's code, and its length
type Hc is Data:
  Hc{c: String, l: String}

def hc.go(cs: List<&2, Code>, c: String, l: String) -> Hc:
  match cs:
    case Nil{}:
      Hc{c, l}
    case Con{Code{n, v}, t}:
      hc.go(t, Bytes.push(c, U32.from_nat(v)), Bytes.push(l, U32.from_nat(n)))

def hc(+lens: List<&2, Nat>) -> Hc:
  hc.go(codes(lens), "", "")

# the code of each length 3..258 (at l - 3) and of each distance: d - 1
# up to 256, 256 + (d - 1) >> 7 past it
def lidx(+l: Nat) -> Nat:
  Nat.sub(l, 3n)

def didx(+d: Nat) -> Nat:
  pick(Nat.is_le(d, 256n), Nat.sub(d, 1n), Nat.add(256n, Nat.div(Nat.sub(d, 1n), 128n)))

# what a block is written with: whether every block is to be fixed; its
# two codes; the code of every length and distance, and the codes'
# bases and extra bits
type EC is Data:
  EC{fx: Bool, ll: Hc, d: Hc, lcs: String, dcs: String, lb: String, lx: String, db: String,
    dx: String}

def ec_fixed(fx: Bool) -> EC:
  EC{fx, Hc{HLLC(), HLLL()}, Hc{HDC(), HDL()}, LCS(), DCS(), LBS(), LXS(), DBS(), DXS()}

def nat_at(+s: String, +i: Nat) -> Nat:
  U32.to_nat(Bytes.get(s, i))

# symbol s by the code h
def put_sym(w: W, +h: Hc, +s: Nat) -> W:
  match h:
    case Hc{+c, +l}:
      putm(nat_at(l, s), w, Bytes.get(c, s))

def put_ref(w: W, +ll: Hc, +d: Hc, +lcs: String, +dcs: String, +lb: String, +lx: String,
  +db: String, +dx: String, +len: Nat, +dist: Nat) -> W:
  +k = nat_at(lcs, lidx(len))
  +q = nat_at(dcs, didx(dist))
  putx(nat_at(dx, q), put_sym(putx(nat_at(lx, k), put_sym(w, ll, Nat.add(U32.to_nat(257), k)),
    Nat.sub(len, nat_at(lb, k))), d, q), Nat.sub(dist, nat_at(db, q)))

def put_tok(tok: Tok, w: W, t: EC) -> W & EC:
  match tok t:
    case Lit{c} EC{fx, +ll, d, lcs, dcs, lb, lx, db, dx}:
      (put_sym(w, ll, U32.to_nat(c)), EC{fx, ll, d, lcs, dcs, lb, lx, db, dx})
    case Ref{len, dist} EC{fx, +ll, +d, +lcs, +dcs, +lb, +lx, +db, +dx}:
      (put_ref(w, ll, d, lcs, dcs, lb, lx, db, dx, len, dist),
        EC{fx, ll, d, lcs, dcs, lb, lx, db, dx})

def put_toks(toks: List<&2, Tok>, r: W & EC) -> W & EC:
  match toks:
    case Nil{}:
      r
    case Con{tok, rest}:
      (w, t) = r
      put_toks(rest, put_tok(tok, w, t))

def put_body.at(r: W & EC) -> W & EC:
  (w, t) = r
  match t:
    case EC{fx, +ll, d, lcs, dcs, lb, lx, db, dx}:
      (put_sym(w, ll, 256n), EC{fx, ll, d, lcs, dcs, lb, lx, db, dx})

# the tokens and the end of the block
def put_body(toks: List<&2, Tok>, w: W, t: EC) -> W & EC:
  put_body.at(put_toks(toks, (w, t)))

# Frequencies
# -----------

type FQ is Type:
  FQ{fa: Array<U32>, da: Array<U32>, xt: Nat}

def inc_at(+i: U32, r: Array<U32> & U32) -> Array<U32>:
  (a, v) = r
  Array.set(U32, a, i, U32.inc(v))

def bump_a(a: Array<U32>, +i: Nat) -> Array<U32>:
  inc_at(U32.from_nat(i), Array.get(U32, a, U32.from_nat(i)))

def freq1(tok: Tok, t: EC, r: FQ) -> FQ:
  match tok t r:
    case Lit{c} _ FQ{fa, da, xt}:
      FQ{bump_a(fa, U32.to_nat(c)), da, xt}
    case Ref{+len, +dist} EC{fx, ll, d, +lcs, +dcs, lb, +lx, db, +dx} FQ{fa, da, xt}:
      +k = nat_at(lcs, lidx(len))
      +q = nat_at(dcs, didx(dist))
      FQ{bump_a(fa, Nat.add(U32.to_nat(257), k)), bump_a(da, q),
        Nat.add(xt, Nat.add(nat_at(lx, k), nat_at(dx, q)))}

def freq(toks: List<&2, Tok>, +t: EC, r: FQ) -> FQ:
  match toks:
    case Nil{}:
      r
    case Con{tok, rest}:
      freq(rest, t, freq1(tok, t, r))

def nats(xs: List<U32>) -> List<&2, Nat>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      Con{U32.to_nat(x), nats(t)}

def dot(xs: List<&2, Nat>, ys: List<&2, Nat>) -> Nat:
  match xs ys:
    case Con{x, xt} Con{y, yt}:
      Nat.add(Nat.mul(x, y), dot(xt, yt))
    case _ _:
      0n

# Huffman code lengths
# --------------------
#
# The lengths of an optimal prefix code of at most lim bits for the
# counts fs: a Huffman tree over the used symbols (two at least, so the
# code is complete), its depth counts clamped to lim and brought back to
# a complete code as miniz does (a code at lim is dropped and one above
# it split, until the counts fit), then handed out, the longest to the
# rarest.

type FS is Data:
  FS{f: Nat, s: Nat}

def fs_le(a: FS, b: FS) -> Bool:
  match a b:
    case FS{+fa, +sa} FS{+fb, +sb}:
      Nat.is_lt(fa, fb) || (Nat.is_eq(fa, fb) && Nat.is_le(sa, sb))

def all_fs(fs: List<&2, Nat>, +s: Nat) -> List<&2, FS>:
  match fs:
    case Nil{}:
      Nil{}
    case Con{f, t}:
      Con{FS{f, s}, all_fs(t, 1n+s)}

def fs_used(x: FS) -> Bool:
  match x:
    case FS{f, s}:
      Nat.is_ne(f, 0n)

def used(fs: List<&2, Nat>) -> List<&2, FS>:
  List.filter(~FS, ~fs_used, all_fs(fs, 0n))

def two(xs: List<&2, FS>) -> List<&2, FS>:
  match xs:
    case Nil{}:
      [FS{0n, 0n}, FS{0n, 1n}]
    case Con{FS{f, +s}, Nil{}}:
      [FS{f, s}, FS{0n, pick(Nat.is_eq(s, 0n), 1n, 0n)}]
    case _:
      xs

type HT is Data:
  HL{s: Nat}
  HN{a: HT, b: HT}

type WT is Data:
  WT{w: Nat, t: HT}

def head_lt(+w: Nat, xs: List<&2, WT>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{WT{v, u}, rest}:
      Nat.is_lt(w, v)

def ins_wt(xs: List<&2, WT>, +w: Nat, t: HT, here: Bool) -> List<&2, WT>:
  match xs here:
    case Nil{} _:
      [WT{w, t}]
    case Con{h, rest} True{}:
      Con{WT{w, t}, Con{h, rest}}
    case Con{h, +rest} False{}:
      Con{h, ins_wt(rest, w, t, head_lt(w, rest))}

def merge(n: Nat, xs: List<&2, WT>) -> HT:
  match n xs:
    case 1n+p Con{WT{wa, ta}, Con{WT{wb, tb}, +rest}}:
      +w = Nat.add(wa, wb)
      merge(p, ins_wt(rest, w, HN{ta, tb}, head_lt(w, rest)))
    case _ Con{WT{w, t}, rest}:
      t
    case _ Nil{}:
      HL{0n}

def leaves(xs: List<&2, FS>) -> List<&2, WT>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{FS{f, s}, t}:
      Con{WT{f, HL{s}}, leaves(t)}

def depths(t: HT, +d: Nat, +lim: Nat, cnt: List<&2, Nat>) -> List<&2, Nat>:
  match t:
    case HL{s}:
      bump(cnt, Nat.min(d, lim))
    case HN{a, b}:
      depths(b, 1n+d, lim, depths(a, 1n+d, lim, cnt))

def kraft(cnt: List<&2, Nat>, +i: Nat, +lim: Nat) -> Nat:
  match cnt:
    case Nil{}:
      0n
    case Con{c, t}:
      Nat.add(pick(Nat.is_eq(i, 0n), 0n, Nat.mul(c, pow2(Nat.sub(lim, i)))), kraft(t, 1n+i, lim))

def dec_at(xs: List<&2, Nat>, k: Nat) -> List<&2, Nat>:
  match xs k:
    case Nil{} _:
      Nil{}
    case Con{x, t} 0n:
      Con{Nat.sub(x, 1n), t}
    case Con{x, t} 1n+p:
      Con{x, dec_at(t, p)}

def add2_at(xs: List<&2, Nat>, k: Nat) -> List<&2, Nat>:
  match xs k:
    case Nil{} _:
      Nil{}
    case Con{x, t} 0n:
      Con{2n+x, t}
    case Con{x, t} 1n+p:
      Con{x, add2_at(t, p)}

# the longest length below lim that has a code: to split
def split_at(+cnt: List<&2, Nat>, +i: Nat) -> Nat:
  match i:
    case 0n:
      0n
    case 1n+p:
      pick(Nat.is_eq(nth(cnt, i), 0n), split_at(cnt, p), i)

def kfix.step(+cnt: List<&2, Nat>, +lim: Nat) -> List<&2, Nat>:
  +i = split_at(dec_at(cnt, lim), Nat.sub(lim, 1n))
  add2_at(dec_at(dec_at(cnt, lim), i), 1n+i)

def kfix(n: Nat, cnt: List<&2, Nat>, +lim: Nat, +total: Nat, over: Bool) -> List<&2, Nat>:
  match n:
    case 0n:
      cnt
    case 1n+p:
      match over:
        case False{}:
          cnt
        case True{}:
          kfix(p, kfix.step(cnt, lim), lim, Nat.sub(total, 1n),
            Nat.is_lt(pow2(lim), Nat.sub(total, 1n)))

# lengths longest first, as the counts say
def seq(+cnt: List<&2, Nat>, +l: Nat) -> List<&2, Nat>:
  match l:
    case 0n:
      Nil{}
    case 1n+p:
      reps(nth(cnt, l), l, seq(cnt, p))

def scatter(xs: List<&2, FS>, ls: List<&2, Nat>, out: List<&2, Nat>) -> List<&2, Nat>:
  match xs ls:
    case Con{FS{f, s}, xt} Con{l, lt}:
      scatter(xt, lt, List.set(&2, Nat, out, s, l))
    case _ _:
      out

def lens_of(+syms: List<&2, FS>, +cnt: List<&2, Nat>, +lim: Nat, +nsym: Nat) -> List<&2, Nat>:
  +tot = kraft(cnt, 0n, lim)
  +fixed = kfix(tot, cnt, lim, tot, Nat.is_lt(pow2(lim), tot))
  scatter(syms, seq(fixed, lim), zeros(nsym))

def hlens.at(+syms: List<&2, FS>, +lim: Nat, +nsym: Nat) -> List<&2, Nat>:
  lens_of(syms, depths(merge(List.length(&2, FS, syms), leaves(syms)), 0n, lim, zeros(1n+lim)),
    lim, nsym)

def hlens(fs: List<&2, Nat>, +lim: Nat, +nsym: Nat) -> List<&2, Nat>:
  hlens.at(List.sort(~FS, ~fs_le, two(used(fs))), lim, nsym)

# A dynamic block's header
# ------------------------

# a code length code item: the symbol, and its extra bits
type CLI is Data:
  CLI{s: Nat, x: Nat, v: Nat}

# how many of xs's first are v, at most max
def runlen(max: Nat, xs: List<&2, Nat>, +v: Nat) -> Nat:
  match max xs:
    case 0n _:
      0n
    case 1n+p Nil{}:
      0n
    case 1n+p Con{+h, t}:
      pick(Nat.is_eq(h, v), 1n+runlen(p, t, v), 0n)

# a run of r lengths of v (r at least 1): its items, and how many
# lengths they cover. Zeros: one alone, 17 for 3..10, 18 for 11..138;
# others: the length, then 16 for 3..6 more of it.
def run_items(+v: Nat, +r: Nat) -> List<&2, CLI>:
  Bool.pick(List<&2, CLI>, Nat.is_eq(v, 0n),
    Bool.pick(List<&2, CLI>, Nat.is_lt(r, 3n), [CLI{0n, 0n, 0n}],
      Bool.pick(List<&2, CLI>, Nat.is_le(r, 10n), [CLI{17n, 3n, Nat.sub(r, 3n)}],
        [CLI{18n, 7n, Nat.sub(r, 11n)}])),
    Bool.pick(List<&2, CLI>, Nat.is_lt(r, 4n), [CLI{v, 0n, 0n}],
      [CLI{v, 0n, 0n}, CLI{16n, 2n, Nat.sub(r, 4n)}]))

def run_adv(+v: Nat, +r: Nat) -> Nat:
  pick(Nat.is_eq(v, 0n), pick(Nat.is_lt(r, 3n), 1n, r), pick(Nat.is_lt(r, 4n), 1n, r))

def rle.at(+v: Nat, +r: Nat) -> List<&2, CLI>:
  run_items(v, r)

# the code lengths as code length code items
def rle(n: Nat, xs: List<&2, Nat>) -> List<&2, CLI>:
  match n xs:
    case 0n _:
      Nil{}
    case 1n+p Nil{}:
      Nil{}
    case 1n+p Con{+v, +t}:
      +r = Nat.add(1n, runlen(pick(Nat.is_eq(v, 0n), 137n, 6n), t, v))
      List.append(&2, CLI, run_items(v, r), rle(p, List.drop(&2, Nat, Con{v, t}, run_adv(v, r))))

def cl_freq(xs: List<&2, CLI>, acc: List<&2, Nat>) -> List<&2, Nat>:
  match xs:
    case Nil{}:
      acc
    case Con{CLI{s, x, v}, t}:
      cl_freq(t, bump(acc, s))

def cl_bits(xs: List<&2, CLI>, +lens: List<&2, Nat>) -> Nat:
  match xs:
    case Nil{}:
      0n
    case Con{CLI{+s, x, v}, t}:
      Nat.add(Nat.add(nth(lens, s), x), cl_bits(t, lens))

# the code length code's lengths in the order they are sent
def perm(ord: List<&2, Nat>, +lens: List<&2, Nat>) -> List<&2, Nat>:
  match ord:
    case Nil{}:
      Nil{}
    case Con{k, t}:
      Con{nth(lens, k), perm(t, lens)}

# how many of them are sent: all but the zeros at the end, 4 at least
def ncl.go(xs: List<&2, Nat>, +i: Nat, last: Nat) -> Nat:
  match xs:
    case Nil{}:
      last
    case Con{+x, t}:
      ncl.go(t, 1n+i, pick(Nat.is_eq(x, 0n), last, 1n+i))

def ncl(+pl: List<&2, Nat>) -> Nat:
  Nat.max(4n, ncl.go(pl, 0n, 0n))

def last_used.go(xs: List<&2, Nat>, +i: Nat, last: Nat) -> Nat:
  match xs:
    case Nil{}:
      last
    case Con{+x, t}:
      last_used.go(t, 1n+i, pick(Nat.is_eq(x, 0n), last, 1n+i))

def put3s(n: Nat, xs: List<&2, Nat>, w: W) -> W:
  match n xs:
    case 1n+p Con{x, t}:
      put3s(p, t, putx(3n, w, x))
    case _ _:
      w

def put_items(xs: List<&2, CLI>, +h: Hc, w: W) -> W:
  match xs:
    case Nil{}:
      w
    case Con{CLI{s, x, v}, t}:
      put_items(t, h, putx(x, put_sym(w, h, s), v))

# A dynamic block's plan: its two codes' lengths, how many of each are
# sent, the code length items, the code length code's lengths in sent
# order and how many are sent, and what the header costs in bits
type Dp is Data:
  Dp{ll: List<&2, Nat>, d: List<&2, Nat>, nlit: Nat, ndist: Nat, items: List<&2, CLI>,
    cll: List<&2, Nat>, pl: List<&2, Nat>, ncl: Nat, bits: Nat}

def dplan.at(ll: List<&2, Nat>, d: List<&2, Nat>, +nlit: Nat, +ndist: Nat,
  +items: List<&2, CLI>, +cll: List<&2, Nat>) -> Dp:
  +pl = perm(CLORD(), cll)
  +n = ncl(pl)
  Dp{ll, d, nlit, ndist, items, cll, pl, n, Nat.add(17n, Nat.add(Nat.mul(3n, n), cl_bits(items, cll)))}

def dplan(+ll: List<&2, Nat>, +d: List<&2, Nat>) -> Dp:
  +nlit = Nat.max(U32.to_nat(257), last_used.go(ll, 0n, 0n))
  +ndist = Nat.max(1n, last_used.go(d, 0n, 0n))
  +all = List.append(&2, Nat, List.take(&2, Nat, ll, nlit), List.take(&2, Nat, d, ndist))
  +items = rle(List.length(&2, Nat, all), all)
  dplan.at(ll, d, nlit, ndist, items, hlens(cl_freq(items, zeros(19n)), 7n, 19n))

def put_dyn_head(w: W, last: Bool, p: Dp) -> W:
  match p:
    case Dp{ll, d, nlit, ndist, items, +cll, pl, +n, bits}:
      put_items(items, hc(cll), put3s(n, pl, putx(4n, putx(5n, putx(5n,
        put(put(put(w, last), False{}), True{}), Nat.sub(nlit, U32.to_nat(257))),
        Nat.sub(ndist, 1n)), Nat.sub(n, 4n))))

# Blocks
# ------

# the first n bits of bs (False past its end), each put in turn
def hd(bs: List<&2, Bool>) -> Bool:
  match bs:
    case Nil{}:
      False{}
    case Con{b, t}:
      b

def tl(bs: List<&2, Bool>) -> List<&2, Bool>:
  match bs:
    case Nil{}:
      Nil{}
    case Con{b, t}:
      t

def putn(n: Nat, +bs: List<&2, Bool>, w: W) -> W:
  match n:
    case 0n:
      w
    case 1n+p:
      putn(p, tl(bs), put(w, hd(bs)))

def nots(bs: List<&2, Bool>) -> List<&2, Bool>:
  match bs:
    case Nil{}:
      Nil{}
    case Con{b, t}:
      Con{Bool.not(b), nots(t)}

# A stored block's length is counted in its own 16 bits, low first, the
# bits LEN is written in: one more, and whether all are set (65535)
def inc(bs: List<&2, Bool>) -> List<&2, Bool>:
  match bs:
    case Nil{}:
      Nil{}
    case Con{b, t}:
      match b:
        case True{}:
          Con{False{}, inc(t)}
        case False{}:
          Con{True{}, t}

def all1(bs: List<&2, Bool>) -> Bool:
  match bs:
    case Nil{}:
      True{}
    case Con{b, t}:
      b && all1(t)

def z16() -> List<&2, Bool>:
  [False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{},
    False{}, False{}, False{}, False{}, False{}]

def one16() -> List<&2, Bool>:
  [True{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{},
    False{}, False{}, False{}, False{}, False{}]

# one stored block of the bytes cur, cnt its length's bits
def stored_one(w: W, cur: Bytes(), +cnt: List<&2, Bool>, last: Bool) -> W:
  put_raw(putn(16n, nots(cnt), putn(16n, cnt, align(put(put(put(w, last), False{}), False{})))),
    cur)

# stored blocks as they fill: the bytes of the block so far, their count,
# the writer
type SS is Data:
  SS{cur: Bytes(), cnt: List<&2, Bool>, w: W}

def stored.add.at(full: Bool, cur: Bytes(), +cnt: List<&2, Bool>, w: W, c: U32) -> SS:
  match full:
    case True{}:
      SS{Bytes.push("", c), one16(), stored_one(w, cur, cnt, False{})}
    case False{}:
      SS{Bytes.push(cur, c), inc(cnt), w}

# a byte: into the block, or a full block out and the byte into a new one
def stored.add(s: SS, c: U32) -> SS:
  match s:
    case SS{cur, +cnt, w}:
      stored.add.at(all1(cnt), cur, cnt, w, c)

# the bytes of x as stored blocks of 65535 bytes and one of the rest,
# that one the last if last
def stored.go(x: Bytes(), last: Bool, s: SS) -> W:
  match x:
    case SNil{}:
      match s:
        case SS{cur, cnt, w}:
          stored_one(w, cur, cnt, last)
    case SCon{Chr{c}, t}:
      stored.go(t, last, stored.add(s, c))

def stored_all(+x: Bytes(), +at: Nat, +len: Nat, last: Bool, w: W) -> W:
  stored.go(Bytes.slice(x, at, len), last, SS{"", z16(), w})

def ec_with(ll: Hc, d: Hc, t: EC) -> EC:
  match t:
    case EC{fx, a, b, lcs, dcs, lb, lx, db, dx}:
      EC{fx, ll, d, lcs, dcs, lb, lx, db, dx}

def dyn_block.at(r: W & EC) -> W:
  (w, t) = r
  w

def dyn_block(toks: List<&2, Tok>, w: W, last: Bool, p: Dp, +t: EC) -> W:
  match p:
    case Dp{+ll, +d, nlit, ndist, items, cll, pl, n, bits}:
      dyn_block.at(put_body(toks, put_dyn_head(w, last, Dp{ll, d, nlit, ndist, items, cll, pl, n,
        bits}), ec_with(hc(ll), hc(d), t)))

def fixed_block(toks: List<&2, Tok>, w: W, last: Bool, +t: EC) -> W:
  dyn_block.at(put_body(toks, put(put(put(w, last), True{}), False{}), t))

def sum(xs: List<&2, Nat>) -> Nat:
  match xs:
    case Nil{}:
      0n
    case Con{x, t}:
      Nat.add(x, sum(t))

def dp_ll(p: Dp) -> List<&2, Nat>:
  match p:
    case Dp{ll, d, nlit, ndist, items, cll, pl, n, bits}:
      ll

def dp_d(p: Dp) -> List<&2, Nat>:
  match p:
    case Dp{ll, d, nlit, ndist, items, cll, pl, n, bits}:
      d

def dp_bits(p: Dp) -> Nat:
  match p:
    case Dp{ll, d, nlit, ndist, items, cll, pl, n, bits}:
      bits

# which of the three is written: 0 stored, 1 fixed, 2 dynamic
def choose(+st: Nat, +fx: Nat, +dy: Nat) -> Nat:
  pick(Nat.is_lt(st, Nat.min(fx, dy)), 0n, pick(Nat.is_le(fx, dy), 1n, 2n))

def wblock.at(k: Nat, toks: List<&2, Tok>, +x: Bytes(), +at: Nat, +len: Nat, last: Bool, w: W,
  p: Dp, +t: EC) -> W:
  match k:
    case 0n:
      stored_all(x, at, len, last, w)
    case 1n:
      fixed_block(toks, w, last, t)
    case _:
      dyn_block(toks, w, last, p, t)

def wblock.plan(toks: List<&2, Tok>, +x: Bytes(), +at: Nat, +len: Nat, last: Bool, w: W,
  +t: EC, r: FQ) -> W:
  match r:
    case FQ{fa, da, +xt}:
      +fl = List.take(&2, Nat, nats(Array.to_list(~U32, bump_a(fa, 256n))), U32.to_nat(286))
      +fd = List.take(&2, Nat, nats(Array.to_list(~U32, da)), 30n)
      +p = dplan(hlens(fl, 15n, U32.to_nat(286)), hlens(fd, 15n, 30n))
      wblock.at(choose(Nat.add(Nat.mul(8n, len), Nat.mul(48n, 1n+Nat.div(len, K64()))),
        Nat.add(3n, Nat.add(xt, Nat.add(dot(fl, fixed_ll_lens()), Nat.mul(5n, sum(fd))))),
        Nat.add(dp_bits(p), Nat.add(xt, Nat.add(dot(fl, dp_ll(p)), dot(fd, dp_d(p)))))),
        toks, x, at, len, last, w, p, t)

def ec_fx(t: EC) -> Bool:
  match t:
    case EC{fx, ll, d, lcs, dcs, lb, lx, db, dx}:
      fx

# The fixed path writes only what it has checked: each literal the byte
# it stands for, each copy within the window and over bytes that agree,
# its length and distance carried by their codes, the whole the bytes of
# the block. A block that fails (never, for the matches the pass finds)
# goes out as its bytes, one literal each.

# a copy's bytes: each the one dist before it
def same(len: Nat, +x: Bytes(), +pos: Nat, +dist: Nat) -> Bool:
  match len:
    case 0n:
      True{}
    case 1n+p:
      U32.is_eq(Bytes.get(x, pos), Bytes.get(x, Nat.sub(pos, dist))) && same(p, x, 1n+pos, dist)

# v by code k: its base and its extra bits carry it back
def coded(+b: String, +e: String, +k: Nat, +v: Nat) -> Bool:
  Nat.is_eq(Nat.add(nat_at(b, k), val(xbits(nat_at(e, k), Nat.sub(v, nat_at(b, k))))), v)

def ref_ok(+x: Bytes(), +pos: Nat, +end: Nat, +len: Nat, +dist: Nat) -> Bool:
  +k = nat_at(LCS(), lidx(len))
  +q = nat_at(DCS(), didx(dist))
  Nat.is_lt(k, 29n) && Nat.is_lt(q, 30n) && coded(LBS(), LXS(), k, len) &&
    coded(DBS(), DXS(), q, dist) && Nat.is_lt(0n, dist) && Nat.is_le(dist, pos) &&
    Nat.is_le(Nat.add(pos, len), end) && same(len, x, pos, dist)

# toks read back are the bytes of x from pos to end
def ck(toks: List<&2, Tok>, +x: Bytes(), +pos: Nat, +end: Nat) -> Bool:
  match toks:
    case Nil{}:
      Nat.is_eq(pos, end)
    case Con{tok, r}:
      match tok:
        case Lit{c}:
          Nat.is_lt(pos, end) && U32.is_eq(c, Bytes.get(x, pos)) && ck(r, x, 1n+pos, end)
        case Ref{+len, +dist}:
          ref_ok(x, pos, end, len, dist) && ck(r, x, Nat.add(pos, len), end)

# the n bytes of x from pos, as literals
def lits(n: Nat, +x: Bytes(), +pos: Nat) -> List<&2, Tok>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Con{Lit{Bytes.get(x, pos)}, lits(p, x, 1n+pos)}

def fixtoks.at(ok: Bool, toks: List<&2, Tok>, +x: Bytes(), +at: Nat, +len: Nat) -> List<&2, Tok>:
  match ok:
    case True{}:
      toks
    case False{}:
      lits(len, x, at)

def fixtoks(+toks: List<&2, Tok>, +x: Bytes(), +at: Nat, +len: Nat) -> List<&2, Tok>:
  fixtoks.at(ck(toks, x, at, Nat.add(at, len)), toks, x, at, len)

def wblock.any(fx: Bool, +toks: List<&2, Tok>, +x: Bytes(), +at: Nat, +len: Nat, last: Bool,
  w: W, +t: EC) -> W:
  match fx:
    case True{}:
      fixed_block(fixtoks(toks, x, at, len), w, last, t)
    case False{}:
      wblock.plan(toks, x, at, len, last, w, t,
        freq(toks, t, FQ{Array.new(U32, 9n, 0), Array.new(U32, 5n, 0), 0n}))

# a block: the tokens that cover the len bytes of x from at
def wblock(+toks: List<&2, Tok>, +x: Bytes(), +at: Nat, +len: Nat, last: Bool, w: W, +t: EC) -> W:
  wblock.any(ec_fx(t), toks, x, at, len, last, w, t)

# LZ77
# ----

# zlib's knobs per level: a match this good cuts the chain to a
# quarter; a match this long is not bettered lazily (greedy levels: is
# not inserted past); one this long ends the search; how many links of a
# chain are tried; greedy or lazy
type Lv is Data:
  Lv{good: Nat, lazy: Nat, nice: Nat, chain: Nat, slow: Bool}

def level(n: Nat) -> Lv:
  match n:
    case 0n:
      Lv{0n, 0n, 0n, 0n, False{}}
    case 1n:
      Lv{4n, 4n, 8n, 4n, False{}}
    case 2n:
      Lv{4n, 5n, 16n, 8n, False{}}
    case 3n:
      Lv{4n, 6n, 32n, 32n, False{}}
    case 4n:
      Lv{4n, 4n, 16n, 16n, True{}}
    case 5n:
      Lv{8n, 16n, 32n, 32n, True{}}
    case 6n:
      Lv{8n, 16n, 128n, 128n, True{}}
    case 7n:
      Lv{8n, 32n, 128n, U32.to_nat(256), True{}}
    case 8n:
      Lv{32n, 128n, U32.to_nat(258), U32.to_nat(1024), True{}}
    case _:
      Lv{32n, U32.to_nat(258), U32.to_nat(258), U32.to_nat(4096), True{}}

def lv_chain(+lv: Lv) -> Nat:
  match lv:
    case Lv{g, l, n, c, s}:
      c

def lv_nice(+lv: Lv) -> Nat:
  match lv:
    case Lv{g, l, n, c, s}:
      n

def lv_lazy(+lv: Lv) -> Nat:
  match lv:
    case Lv{g, l, n, c, s}:
      l

def lv_good(+lv: Lv) -> Nat:
  match lv:
    case Lv{g, l, n, c, s}:
      g

def lv_slow(+lv: Lv) -> Bool:
  match lv:
    case Lv{g, l, n, c, s}:
      s

# the three bytes from i, hashed to 15 bits
def hash(+x: Bytes(), +i: Nat) -> U32:
  U32.shrn(U32.mul(U32.and(Bytes.word_le(x, i), 16777215), 2654435761), 17n)

# how many bytes from a and from b agree, at most n; eq says whether
# the ones at a and b do
def mlen(n: Nat, +x: Bytes(), +a: Nat, +b: Nat, +k: Nat, eq: Bool) -> Nat:
  match n:
    case 0n:
      k
    case 1n+p:
      match eq:
        case False{}:
          k
        case True{}:
          mlen(p, x, 1n+a, 1n+b, 1n+k, U32.is_eq(Bytes.get(x, 1n+a), Bytes.get(x, 1n+b)))

def match_len(+x: Bytes(), +a: Nat, +b: Nat, +n: Nat) -> Nat:
  mlen(n, x, a, b, 0n, U32.is_eq(Bytes.get(x, a), Bytes.get(x, b)))

# the hash chains: head, the last position + 1 of each hash; prev, the
# position + 1 before each position (mod 32 KiB) with the same hash
type H is Type:
  H{head: Array<U32>, prev: Array<U32>}

def h_new() -> H:
  H{Array.new(U32, 15n, 0), Array.new(U32, 15n, 0)}

def hins.at(prev: Array<U32>, +i: Nat, r: Array<U32> & U32) -> H & U32:
  (head, +old) = r
  (H{head, Array.set(U32, prev, U32.and(U32.from_nat(i), 32767), old)}, old)

# position i into its chain: the chains, and the chain's head before it
def hins(+x: Bytes(), +i: Nat, h: H) -> H & U32:
  match h:
    case H{head, prev}:
      hins.at(prev, i, Array.swap(U32, head, hash(x, i), U32.from_nat(1n+i)))

def ins_only.at(r: H & U32) -> H:
  (h, old) = r
  h

def ins_run.at(ok: Bool, +x: Bytes(), +i: Nat, h: H) -> H:
  match ok:
    case True{}:
      ins_only.at(hins(x, i, h))
    case False{}:
      h

# the positions from i, k of them, into their chains (those with three
# bytes to hash)
def ins_run(k: Nat, +x: Bytes(), +n: Nat, +i: Nat, h: H) -> H:
  match k:
    case 0n:
      h
    case 1n+p:
      ins_run(p, x, n, 1n+i, ins_run.at(Nat.is_le(Nat.add(i, 3n), n), x, i, h))

# The chain's walk: the best match so far, the link to try next, and
# whether to go on
type CS is Type:
  CS{prev: Array<U32>, cand: U32, blen: Nat, bdist: Nat, go: Bool}

def cstep.next(+cand: U32, +ml: Nat, +nice: Nat, +dist: Nat, +blen: Nat, +bdist: Nat,
  r: Array<U32> & U32) -> CS:
  (prev, +nx) = r
  CS{prev, nx, pick(Nat.is_lt(blen, ml), ml, blen), pick(Nat.is_lt(blen, ml), dist, bdist),
    U32.is_lt(nx, cand) && Nat.is_lt(ml, nice)}

# one link: j, the position it names, if in reach, is compared with i
def cstep.try(+x: Bytes(), +i: Nat, +maxl: Nat, +nice: Nat, prev: Array<U32>, +cand: U32,
  +blen: Nat, +bdist: Nat, ok: Bool) -> CS:
  match ok:
    case False{}:
      CS{prev, cand, blen, bdist, False{}}
    case True{}:
      +j = Nat.sub(U32.to_nat(cand), 1n)
      cstep.next(cand, match_len(x, j, i, maxl), nice, Nat.sub(i, j), blen, bdist,
        Array.get(U32, prev, U32.and(U32.from_nat(j), 32767)))

def cstep(+x: Bytes(), +i: Nat, +maxl: Nat, +nice: Nat, s: CS) -> CS:
  match s:
    case CS{prev, +cand, blen, bdist, go}:
      +j = Nat.sub(U32.to_nat(cand), 1n)
      cstep.try(x, i, maxl, nice, prev, cand, blen, bdist,
        Nat.is_ne(U32.to_nat(cand), 0n) && Nat.is_lt(j, i) && Nat.is_le(Nat.sub(i, j), K32()))

def chain(k: Nat, +x: Bytes(), +i: Nat, +maxl: Nat, +nice: Nat, s: CS) -> CS:
  match k:
    case 0n:
      s
    case 1n+p:
      match s:
        case CS{prev, cand, blen, bdist, go}:
          match go:
            case False{}:
              CS{prev, cand, blen, bdist, False{}}
            case True{}:
              chain(p, x, i, maxl, nice, cstep(x, i, maxl, nice, CS{prev, cand, blen, bdist, True{}}))

# a match found at i: its length (0 if none worth taking) and distance
type Fm is Type:
  Fm{h: H, len: Nat, dist: Nat}

def found(head: Array<U32>, s: CS) -> Fm:
  match s:
    case CS{prev, cand, +blen, +bdist, go}:
      Fm{H{head, prev}, pick(Nat.is_eq(blen, 3n) && Nat.is_lt(U32.to_nat(4096), bdist), 0n, blen),
        bdist}

def find.at(+x: Bytes(), +i: Nat, +maxl: Nat, +nice: Nat, +k: Nat, r: H & U32) -> Fm:
  (h, cand) = r
  match h:
    case H{head, prev}:
      found(head, chain(k, x, i, maxl, nice, CS{prev, cand, 0n, 0n, True{}}))

# position i into its chain, and the longest match there, trying k
# links, taking one of nice at once
def find(+x: Bytes(), +n: Nat, +i: Nat, +nice: Nat, +k: Nat, h: H) -> Fm:
  find.at(x, i, Nat.min(U32.to_nat(258), Nat.sub(n, i)), nice, k, hins(x, i, h))

# find where there are three bytes to hash; else nothing is inserted
def find_if(ok: Bool, +x: Bytes(), +n: Nat, +i: Nat, +nice: Nat, +k: Nat, h: H) -> Fm:
  match ok:
    case True{}:
      find(x, n, i, nice, k, h)
    case False{}:
      Fm{h, 0n, 0n}

# The pass
# --------

# the pass's state: the input, its length, the level, the block tables;
# the position, the chains, the tokens of this block (newest first) and
# how many, the offset their bytes end at and the offset the block
# starts at, the writer; the lazy match held from the position before
# (plen, pdist; avail, whether that position is still to be written);
# whether there is more input
type Z is Type:
  Z{x: Bytes(), n: Nat, lv: Lv, t: EC, i: Nat, h: H, toks: List<&2, Tok>, nt: Nat, tpos: Nat,
    bs: Nat, w: W, plen: Nat, pdist: Nat, avail: Bool, go: Bool}

# greedy: the match at i if there is one, else the byte
def greedy.ok(ok: Bool, +x: Bytes(), +n: Nat, +lv: Lv, t: EC, +i: Nat, h: H,
  toks: List<&2, Tok>, +nt: Nat, +tpos: Nat, bs: Nat, w: W, +len: Nat, +dist: Nat) -> Z:
  match ok:
    case True{}:
      Z{x, n, lv, t, Nat.add(i, len), ins_run(pick(Nat.is_le(len, lv_lazy(lv)), Nat.sub(len, 1n),
        0n), x, n, 1n+i, h), Con{Ref{len, dist}, toks}, 1n+nt, Nat.add(tpos, len), bs, w, 0n, 0n,
        False{}, Nat.is_lt(Nat.add(i, len), n)}
    case False{}:
      Z{x, n, lv, t, 1n+i, h, Con{Lit{Bytes.get(x, i)}, toks}, 1n+nt, 1n+tpos, bs, w, 0n, 0n,
        False{}, Nat.is_lt(1n+i, n)}

def greedy.at(+x: Bytes(), +n: Nat, +lv: Lv, t: EC, +i: Nat, toks: List<&2, Tok>, +nt: Nat,
  +tpos: Nat, bs: Nat, w: W, fm: Fm) -> Z:
  match fm:
    case Fm{h, +len, dist}:
      greedy.ok(Nat.is_le(3n, len), x, n, lv, t, i, h, toks, nt, tpos, bs, w, len, dist)

# lazy: the match held from i - 1 is written if the one at i is no
# longer; else the byte at i - 1 is, and the match at i is held
def lazy.ok(take: Bool, +x: Bytes(), +n: Nat, +lv: Lv, t: EC, +i: Nat, h: H,
  toks: List<&2, Tok>, +nt: Nat, +tpos: Nat, bs: Nat, w: W, +plen: Nat, +pdist: Nat,
  avail: Bool, +len: Nat, +dist: Nat) -> Z:
  match take avail:
    case True{} _:
      Z{x, n, lv, t, Nat.add(Nat.sub(i, 1n), plen), ins_run(Nat.sub(plen, 2n), x, n, 1n+i, h),
        Con{Ref{plen, pdist}, toks}, 1n+nt, Nat.add(tpos, plen), bs, w, 0n, 0n, False{},
        Nat.is_lt(Nat.add(Nat.sub(i, 1n), plen), n)}
    case False{} True{}:
      Z{x, n, lv, t, 1n+i, h, Con{Lit{Bytes.get(x, Nat.sub(i, 1n))}, toks}, 1n+nt, 1n+tpos, bs,
        w, len, dist, True{}, Nat.is_lt(1n+i, n)}
    case False{} False{}:
      Z{x, n, lv, t, 1n+i, h, toks, nt, tpos, bs, w, len, dist, True{}, Nat.is_lt(1n+i, n)}

def lazy.at(+x: Bytes(), +n: Nat, +lv: Lv, t: EC, +i: Nat, toks: List<&2, Tok>, +nt: Nat,
  +tpos: Nat, bs: Nat, w: W, +plen: Nat, pdist: Nat, avail: Bool, fm: Fm) -> Z:
  match fm:
    case Fm{h, +len, dist}:
      lazy.ok(Nat.is_le(3n, plen) && Nat.is_le(len, plen), x, n, lv, t, i, h, toks, nt, tpos, bs,
        w, plen, pdist, avail, len, dist)

# a position: greedy or lazy
def pos.at(slow: Bool, +x: Bytes(), +n: Nat, +lv: Lv, t: EC, +i: Nat, h: H,
  toks: List<&2, Tok>, +nt: Nat, +tpos: Nat, bs: Nat, w: W, +plen: Nat, pdist: Nat,
  avail: Bool) -> Z:
  match slow:
    case False{}:
      greedy.at(x, n, lv, t, i, toks, nt, tpos, bs, w,
        find_if(Nat.is_le(Nat.add(i, 3n), n), x, n, i, lv_nice(lv), lv_chain(lv), h))
    case True{}:
      lazy.at(x, n, lv, t, i, toks, nt, tpos, bs, w, plen, pdist, avail,
        find_if(Nat.is_le(Nat.add(i, 3n), n), x, n, i, lv_nice(lv),
          pick(Nat.is_lt(plen, lv_lazy(lv)),
            pick(Nat.is_le(lv_good(lv), plen), Nat.div(lv_chain(lv), 4n), lv_chain(lv)), 0n), h))

# a full block goes out first
def iter.at(full: Bool, +x: Bytes(), +n: Nat, +lv: Lv, +t: EC, +i: Nat, h: H,
  toks: List<&2, Tok>, +nt: Nat, +tpos: Nat, +bs: Nat, w: W, +plen: Nat, pdist: Nat,
  avail: Bool) -> Z:
  match full:
    case True{}:
      +len = Nat.min(Nat.sub(tpos, bs), Nat.sub(n, bs))
      pos.at(lv_slow(lv), x, n, lv, t, i, h, Nil{}, 0n, tpos, Nat.add(bs, len),
        wblock(List.reverse(&2, Tok, toks), x, bs, len, False{}, w, t), plen, pdist, avail)
    case False{}:
      pos.at(lv_slow(lv), x, n, lv, t, i, h, toks, nt, tpos, bs, w, plen, pdist, avail)

def iter(z: Z) -> Z:
  match z:
    case Z{x, n, lv, +t, i, h, toks, +nt, tpos, bs, w, plen, pdist, avail, go}:
      iter.at(Nat.is_le(16383n, nt) && Bool.not(ec_fx(t)), x, n, lv, t, i, h, toks, nt, tpos, bs, w, plen,
        pdist, avail)

def lz(k: Nat, z: Z) -> Z:
  match k:
    case 0n:
      z
    case 1n+p:
      match z:
        case Z{x, n, lv, t, i, h, toks, nt, tpos, bs, w, plen, pdist, avail, go}:
          match go:
            case False{}:
              Z{x, n, lv, t, i, h, toks, nt, tpos, bs, w, plen, pdist, avail, False{}}
            case True{}:
              lz(p, iter(Z{x, n, lv, t, i, h, toks, nt, tpos, bs, w, plen, pdist, avail, True{}}))

# the pass is over: the byte held, if one, and the last block
def lz_end.at(avail: Bool, +x: Bytes(), +n: Nat, t: EC, toks: List<&2, Tok>, +tpos: Nat,
  +bs: Nat, w: W) -> W:
  match avail:
    case True{}:
      align(wblock(List.reverse(&2, Tok, Con{Lit{Bytes.get(x, Nat.sub(n, 1n))}, toks}), x, bs,
        Nat.sub(n, bs), True{}, w, t))
    case False{}:
      align(wblock(List.reverse(&2, Tok, toks), x, bs, Nat.sub(n, bs), True{}, w, t))

def lz_end(z: Z) -> W:
  match z:
    case Z{x, n, lv, t, i, h, toks, nt, tpos, bs, w, plen, pdist, avail, go}:
      lz_end.at(avail, x, n, t, toks, tpos, bs, w)

# The raw deflate stream of x at a level: 0 stores, 1..9 as zlib's;
# fx, every block with the fixed code
# the pass over x at a level, from its start
def lz_all(+x: Bytes(), +lvl: Nat, fx: Bool) -> Z:
  +n = Bytes.len(x)
  lz(1n+n, Z{x, n, level(lvl), ec_fixed(fx), 0n, h_new(), Nil{}, 0n, 0n, 0n, w_new(), 0n, 0n, False{},
    Nat.is_lt(0n, n)})

# Deflate, fast
# =============
#
# The pass above again, decision for decision -- the hash, the chains,
# the greedy and lazy rules, the block split, the code lengths, the
# header -- and so the same stream, byte for byte (the fixture holds it
# to deflate_gen.py's twin, and to the pass above on 10 MB of text at
# every level), but in flat state: the chains, the block's tokens and
# the frequencies in arrays, the writer's bits in a word that goes out a
# byte at a time, a match's length found four bytes at a time, and a
# link that cannot beat the best match so far passed over at the byte
# that would have to beat it. A token is a U32: a literal, or
# len << 16 | dist. What deflate writes at levels 1 to 9.

# The writer
# ----------

# the bytes out, and the bits of the byte being filled: nb of them, low
# first, in acc (nb < 8)
type FW is Data:
  FW{out: Bytes(), acc: U32, nb: Nat}

# the k low bytes of a, low first
def pushn(k: Nat, out: Bytes(), +a: U32) -> Bytes():
  match k:
    case 0n:
      out
    case 1n+p:
      pushn(p, Bytes.push(out, U32.and(a, 255)), U32.shrn(a, 8n))

# a field of k bits (at most 24), low first
def fput(w: FW, +v: U32, +k: Nat) -> FW:
  match w:
    case FW{out, acc, +nb}:
      +a2 = U32.or(acc, U32.shln(v, nb))
      +n2 = Nat.add(nb, k)
      +nby = Nat.div(n2, 8n)
      FW{pushn(nby, out, a2), U32.shrn(a2, Nat.mul(8n, nby)), Nat.mod(n2, 8n)}

def fput_n(w: FW, +v: Nat, +k: Nat) -> FW:
  fput(w, U32.from_nat(v), k)

# zeros to the next byte
def falign(w: FW) -> FW:
  match w:
    case FW{out, acc, +nb}:
      fput(FW{out, acc, nb}, 0, Nat.mod(Nat.sub(8n, nb), 8n))

def fw_out(w: FW) -> Bytes():
  match w:
    case FW{out, acc, nb}:
      out

# bytes as they are, the writer being at a byte
def fraw(w: FW, +b: Bytes()) -> FW:
  match w:
    case FW{out, acc, nb}:
      FW{Bytes.append(out, b), acc, nb}

# A code as the writer takes it: each symbol's code with its bits in the
# order they go out (the code read back low first), and its length
type RC is Data:
  RC{c: String, l: String}

def rc.go(cs: List<&2, Code>, c: String, l: String) -> RC:
  match cs:
    case Nil{}:
      RC{c, l}
    case Con{Code{+n, v}, t}:
      rc.go(t, Bytes.push(c, U32.from_nat(rev(n, v, 0n))), Bytes.push(l, U32.from_nat(n)))

def rc(+lens: List<&2, Nat>) -> RC:
  rc.go(codes(lens), "", "")

# a cell of a table written out (st_n), or of one built at runtime (at,
# at_n): kept apart so the runtime tables are only ever lent, never owned
def st_n(+s: String, +i: Nat) -> Nat:
  U32.to_nat(Bytes.get(s, i))

def at(+s: String, +i: Nat) -> U32:
  Bytes.get(s, i)

def at_n(+s: String, +i: Nat) -> Nat:
  U32.to_nat(Bytes.get(s, i))

def fsym(w: FW, +c: String, +l: String, +s: Nat) -> FW:
  fput(w, at(c, s), at_n(l, s))

def fsym.rc(w: FW, +h: RC, +s: Nat) -> FW:
  match h:
    case RC{+c, +l}:
      fsym(w, c, l, s)

# The tables a block's tokens are written with: the literal/length
# code's literals and end (lc, ll); each length from 3 to 258 at l - 3,
# its code and extra bits as one field (mv) and that field's width (ml);
# the distance code (dc, dl)
type BT is Data:
  BT{lc: String, ll: String, mv: String, ml: String, dc: String, dl: String}

type S2 is Data:
  S2{a: String, b: String}

def bt.lens(k: Nat, +lc: String, +ll: String, +len: Nat, mv: String, ml: String) -> S2:
  match k:
    case 0n:
      S2{mv, ml}
    case 1n+p:
      +kk = st_n(LCS(), Nat.sub(len, 3n))
      +l = at_n(ll, Nat.add(257n, kk))
      bt.lens(p, lc, ll, 1n+len, Bytes.push(mv, U32.or(at(lc, Nat.add(257n, kk)),
        U32.shln(U32.from_nat(Nat.sub(len, st_n(LBS(), kk))), l))),
        Bytes.push(ml, U32.from_nat(Nat.add(l, st_n(LXS(), kk)))))

def bt.at(+lc: String, +ll: String, r: S2, d: RC) -> BT:
  match r d:
    case S2{mv, ml} RC{dc, dl}:
      BT{lc, ll, mv, ml, dc, dl}

def bt.of(ll: RC, d: RC) -> BT:
  match ll:
    case RC{+lc, +l}:
      bt.at(lc, l, bt.lens(256n, lc, l, 3n, "", ""), d)

# a token: a literal (below 256), or a copy (len << 16 | dist)
def ftok.at(lit: Bool, w: FW, +lc: String, +ll: String, +mv: String, +ml: String, +dc: String,
  +dl: String, +v: U32) -> FW:
  match lit:
    case True{}:
      fsym(w, lc, ll, U32.to_nat(v))
    case False{}:
      +li = Nat.sub(U32.to_nat(U32.shrn(v, 16n)), 3n)
      +dist = U32.to_nat(U32.and(v, 65535))
      +q = st_n(DCS(), didx(dist))
      fput(fput(fput(w, at(mv, li), at_n(ml, li)), at(dc, q), at_n(dl, q)),
        U32.from_nat(Nat.sub(dist, st_n(DBS(), q))), st_n(DXS(), q))

type TW is Type:
  TW{tk: Array<U32>, w: FW}

# the tokens j.. of tk, nt in all
def ftoks(k: Nat, go: Bool, r: Array<U32> & U32, +j: Nat, +nt: Nat, w: FW, +lc: String,
  +ll: String, +mv: String, +ml: String, +dc: String, +dl: String) -> TW:
  match k go:
    case 1n+p True{}:
      (tk, +v) = r
      ftoks(p, Nat.is_lt(1n+j, nt), Array.get(U32, tk, U32.from_nat(1n+j)), 1n+j, nt,
        ftok.at(U32.is_lt(v, 256), w, lc, ll, mv, ml, dc, dl, v), lc, ll, mv, ml, dc, dl)
    case _ _:
      (tk, v) = r
      TW{tk, w}

def fbody.end(r: TW, +lc: String, +ll: String) -> TW:
  match r:
    case TW{tk, w}:
      TW{tk, fsym(w, lc, ll, 256n)}

# the tokens of a block, then its end
def fbody(tk: Array<U32>, +nt: Nat, w: FW, t: BT) -> TW:
  match t:
    case BT{+lc, +ll, +mv, +ml, +dc, +dl}:
      fbody.end(ftoks(1n+nt, Nat.is_lt(0n, nt), Array.get(U32, tk, 0), 0n, nt, w, lc, ll, mv, ml, dc,
        dl), lc, ll)

# Frequencies
# -----------

type FQ2 is Type:
  FQ2{fa: Array<U32>, da: Array<U32>, xt: Nat}

type FF is Type:
  FF{tk: Array<U32>, fa: Array<U32>, da: Array<U32>, xt: Nat}

def ffreq.tok(lit: Bool, +v: U32, fa: Array<U32>, da: Array<U32>, +xt: Nat) -> FQ2:
  match lit:
    case True{}:
      FQ2{bump_a(fa, U32.to_nat(v)), da, xt}
    case False{}:
      +k = st_n(LCS(), lidx(U32.to_nat(U32.shrn(v, 16n))))
      +q = st_n(DCS(), didx(U32.to_nat(U32.and(v, 65535))))
      FQ2{bump_a(fa, Nat.add(257n, k)), bump_a(da, q),
        Nat.add(xt, Nat.add(st_n(LXS(), k), st_n(DXS(), q)))}

def ffreq(k: Nat, go: Bool, r: Array<U32> & U32, +j: Nat, +nt: Nat, f: FQ2) -> FF:
  match k go:
    case 1n+p True{}:
      (tk, +v) = r
      match f:
        case FQ2{fa, da, xt}:
          ffreq(p, Nat.is_lt(1n+j, nt), Array.get(U32, tk, U32.from_nat(1n+j)), 1n+j, nt,
            ffreq.tok(U32.is_lt(v, 256), v, fa, da, xt))
    case _ _:
      (tk, v) = r
      match f:
        case FQ2{fa, da, xt}:
          FF{tk, fa, da, xt}

# Blocks
# ------

def lastb(b: Bool) -> U32:
  u32.pick(b, 1, 0)

# stored blocks of the len bytes of x from at: 65535 a block, the last
# (0 to 65535 bytes) marked last if last is
def fstored(k: Nat, +x: Bytes(), +at: Nat, +left: Nat, +last: Bool, w: FW, go: Bool) -> FW:
  match k go:
    case 1n+p True{}:
      +big = Nat.is_lt(65535n, left)
      +m = pick(big, 65535n, left)
      fstored(p, x, Nat.add(at, m), Nat.sub(left, m), last,
        fraw(fput_n(fput_n(falign(fput(w, lastb(Bool.not(big) && last), 3n)), m, 16n),
          Nat.sub(65535n, m), 16n), Bytes.slice(x, at, m)), big)
    case _ _:
      w

def fput3s(n: Nat, xs: List<&2, Nat>, w: FW) -> FW:
  match n xs:
    case 1n+p Con{+x, t}:
      fput3s(p, t, fput_n(w, x, 3n))
    case _ _:
      w

def fitems(xs: List<&2, CLI>, +h: RC, w: FW) -> FW:
  match xs:
    case Nil{}:
      w
    case Con{CLI{+s, +x, +v}, t}:
      fitems(t, h, fput_n(fsym.rc(w, h, s), v, x))

def fdyn(tk: Array<U32>, +nt: Nat, w: FW, last: Bool, p: Dp) -> TW:
  match p:
    case Dp{+ll, +d, +nlit, +ndist, items, +cll, pl, +n, bits}:
      fbody(tk, nt, fitems(items, rc(cll), fput3s(n, pl, fput_n(fput_n(fput_n(
        fput(w, U32.add(4, lastb(last)), 3n), Nat.sub(nlit, 257n), 5n), Nat.sub(ndist, 1n), 5n),
        Nat.sub(n, 4n), 4n))), bt.of(rc(ll), rc(d)))

def bt_fixed() -> BT:
  bt.of(rc(fixed_ll_lens()), rc(fixed_d_lens()))

def fblock.at(kind: Nat, tk: Array<U32>, +nt: Nat, +x: Bytes(), +at: Nat, +len: Nat, last: Bool,
  w: FW, p: Dp) -> TW:
  match kind:
    case 0n:
      TW{tk, fstored(2n+Nat.div(len, 65535n), x, at, len, last, w, True{})}
    case 1n:
      fbody(tk, nt, fput(w, U32.add(2, lastb(last)), 3n), bt_fixed())
    case _:
      fdyn(tk, nt, w, last, p)

def fblock.plan(r: FF, +nt: Nat, +x: Bytes(), +at: Nat, +len: Nat, last: Bool, w: FW) -> TW:
  match r:
    case FF{tk, fa, da, +xt}:
      +fl = List.take(&2, Nat, nats(Array.to_list(~U32, bump_a(fa, 256n))), 286n)
      +fd = List.take(&2, Nat, nats(Array.to_list(~U32, da)), 30n)
      +p = dplan(hlens(fl, 15n, 286n), hlens(fd, 15n, 30n))
      fblock.at(choose(Nat.add(Nat.mul(8n, len), Nat.mul(48n, 1n+Nat.div(len, K64()))),
        Nat.add(3n, Nat.add(xt, Nat.add(dot(fl, fixed_ll_lens()), Nat.mul(5n, sum(fd))))),
        Nat.add(dp_bits(p), Nat.add(xt, Nat.add(dot(fl, dp_ll(p)), dot(fd, dp_d(p)))))),
        tk, nt, x, at, len, last, w, p)

# a block: the nt tokens of tk, which cover the len bytes of x from at
def fblock(tk: Array<U32>, +nt: Nat, +x: Bytes(), +at: Nat, +len: Nat, last: Bool, w: FW) -> TW:
  fblock.plan(ffreq(1n+nt, Nat.is_lt(0n, nt), Array.get(U32, tk, 0), 0n, nt,
    FQ2{Array.new(U32, 9n, 0), Array.new(U32, 5n, 0), 0n}), nt, x, at, len, last, w)

# LZ77
# ----

# how many of the four bytes of a and b agree, from the low end
def same4(+a: U32, +b: U32) -> Nat:
  +z = U32.xor(a, b)
  pick(U32.is_ne(U32.and(z, 255), 0), 0n, pick(U32.is_ne(U32.and(z, 65535), 0), 1n,
    pick(U32.is_ne(U32.and(z, 16777215), 0), 2n, pick(U32.is_ne(z, 0), 3n, 4n))))

# how many bytes from a and from b agree, from l on, at most n: four at
# a time (a byte past the input reads 0; none past n is counted)
def mlen4(k: Nat, +x: Bytes(), +a: Nat, +b: Nat, +n: Nat, +l: Nat, go: Bool) -> Nat:
  match k go:
    case 1n+p True{}:
      +s = same4(Bytes.word_le(x, Nat.add(a, l)), Bytes.word_le(x, Nat.add(b, l)))
      +l2 = Nat.min(Nat.add(l, s), n)
      mlen4(p, x, a, b, n, l2, Nat.is_eq(s, 4n) && Nat.is_lt(l2, n))
    case _ _:
      l

# The chain's walk from the link cand (lastc the one before it): the
# best match so far, packed as len << 16 | dist
def zchain(k: Nat, +x: Bytes(), +i: Nat, +maxl: Nat, +nice: Nat, go: Bool, r: Array<U32> & U32,
  +blen: Nat, +bdist: Nat, +lastc: U32) -> Array<U32> & U32:
  match k go:
    case 1n+p True{}:
      (prev, +cand) = r
      +j = Nat.sub(U32.to_nat(cand), 1n)
      +ok = U32.is_ne(cand, 0) && U32.is_lt(cand, lastc) && Nat.is_lt(j, i) &&
        Nat.is_le(Nat.sub(i, j), 32768n)
      +ml = mlen4(66n, x, j, i, maxl, 0n, ok && Nat.is_lt(blen, maxl) &&
        U32.is_eq(Bytes.get(x, Nat.add(j, blen)), Bytes.get(x, Nat.add(i, blen))))
      +better = Nat.is_lt(blen, ml)
      zchain(p, x, i, maxl, nice, ok && Nat.is_lt(ml, nice),
        Array.get(U32, prev, U32.and(U32.sub(cand, 1), 32767)), pick(better, ml, blen),
        pick(better, Nat.sub(i, j), bdist), cand)
    case _ _:
      (prev, cand) = r
      (prev, U32.or(U32.shln(U32.from_nat(blen), 16n), U32.from_nat(bdist)))

type ZM is Type:
  ZM{head: Array<U32>, prev: Array<U32>, len: Nat, dist: Nat}

def fm(head: Array<U32>, r: Array<U32> & U32) -> ZM:
  (prev, +pk) = r
  +blen = U32.to_nat(U32.shrn(pk, 16n))
  +bdist = U32.to_nat(U32.and(pk, 65535))
  ZM{head, prev, pick(Nat.is_eq(blen, 3n) && Nat.is_lt(4096n, bdist), 0n, blen), bdist}

def fh(r: Array<U32> & U32, prev: Array<U32>, +x: Bytes(), +n: Nat, +i: Nat, +nice: Nat, +k: Nat) ->
  ZM:
  (head, +cand) = r
  fm(head, zchain(k, x, i, Nat.min(258n, Nat.sub(n, i)), nice, True{},
    (Array.set(U32, prev, U32.and(U32.from_nat(i), 32767), cand), cand), 0n, 0n, 4294967295))

# position i into its chain, and the longest match there, trying k
# links; none where there are not three bytes to hash
def zfind(ok: Bool, +x: Bytes(), +n: Nat, +i: Nat, +nice: Nat, +k: Nat, head: Array<U32>,
  prev: Array<U32>) -> ZM:
  match ok:
    case True{}:
      fh(Array.swap(U32, head, hash(x, i), U32.from_nat(1n+i)), prev, x, n, i, nice, k)
    case False{}:
      ZM{head, prev, 0n, 0n}

type HP is Type:
  HP{head: Array<U32>, prev: Array<U32>}

def fins1.r(r: Array<U32> & U32, prev: Array<U32>, +i: Nat) -> HP:
  (head, +old) = r
  HP{head, Array.set(U32, prev, U32.and(U32.from_nat(i), 32767), old)}

def fins1(ok: Bool, +x: Bytes(), +i: Nat, head: Array<U32>, prev: Array<U32>) -> HP:
  match ok:
    case True{}:
      fins1.r(Array.swap(U32, head, hash(x, i), U32.from_nat(1n+i)), prev, i)
    case False{}:
      HP{head, prev}

# the positions from i, k of them, into their chains
def fins(k: Nat, +x: Bytes(), +n: Nat, +i: Nat, h: HP) -> HP:
  match k:
    case 0n:
      h
    case 1n+p:
      match h:
        case HP{head, prev}:
          fins(p, x, n, 1n+i, fins1(Nat.is_le(Nat.add(i, 3n), n), x, i, head, prev))

# The pass's state: the position, the chains, the block's tokens (nt of
# them, covering the bytes to tpos) and the offset it starts at, the
# writer; the lazy match held from the position before; whether there
# is more input
type FZ is Type:
  FZ{i: Nat, head: Array<U32>, prev: Array<U32>, tk: Array<U32>, nt: Nat, tpos: Nat, bs: Nat,
    w: FW, plen: Nat, pdist: Nat, avail: Bool, go: Bool}

def tok_ref(+len: Nat, +dist: Nat) -> U32:
  U32.or(U32.shln(U32.from_nat(len), 16n), U32.from_nat(dist))

def zgreedy.hp(h: HP, tk: Array<U32>, +x: Bytes(), +n: Nat, +i: Nat, +nt: Nat, +tpos: Nat, +bs: Nat,
  w: FW, +len: Nat) -> FZ:
  match h:
    case HP{head, prev}:
      FZ{Nat.add(i, len), head, prev, tk, 1n+nt, Nat.add(tpos, len), bs, w, 0n, 0n, False{},
        Nat.is_lt(Nat.add(i, len), n)}

def zgreedy.ok(ok: Bool, +x: Bytes(), +n: Nat, +lazy: Nat, +i: Nat, head: Array<U32>,
  prev: Array<U32>, tk: Array<U32>, +nt: Nat, +tpos: Nat, +bs: Nat, w: FW, +len: Nat, +dist: Nat) ->
  FZ:
  match ok:
    case True{}:
      zgreedy.hp(fins(pick(Nat.is_le(len, lazy), Nat.sub(len, 1n), 0n), x, n, 1n+i, HP{head, prev}),
        Array.set(U32, tk, U32.from_nat(nt), tok_ref(len, dist)), x, n, i, nt, tpos, bs, w, len)
    case False{}:
      FZ{1n+i, head, prev, Array.set(U32, tk, U32.from_nat(nt), Bytes.get(x, i)), 1n+nt, 1n+tpos, bs,
        w, 0n, 0n, False{}, Nat.is_lt(1n+i, n)}

def zgreedy.at(fm: ZM, +x: Bytes(), +n: Nat, +lazy: Nat, +i: Nat, tk: Array<U32>, +nt: Nat,
  +tpos: Nat, +bs: Nat, w: FW) -> FZ:
  match fm:
    case ZM{head, prev, +len, +dist}:
      zgreedy.ok(Nat.is_le(3n, len), x, n, lazy, i, head, prev, tk, nt, tpos, bs, w, len, dist)

def zlazy.hp(h: HP, tk: Array<U32>, +x: Bytes(), +n: Nat, +i: Nat, +nt: Nat, +tpos: Nat, +bs: Nat,
  w: FW, +plen: Nat) -> FZ:
  match h:
    case HP{head, prev}:
      FZ{Nat.add(Nat.sub(i, 1n), plen), head, prev, tk, 1n+nt, Nat.add(tpos, plen), bs, w, 0n, 0n,
        False{}, Nat.is_lt(Nat.add(Nat.sub(i, 1n), plen), n)}

def zlazy.ok(take: Bool, avail: Bool, +x: Bytes(), +n: Nat, +i: Nat, head: Array<U32>,
  prev: Array<U32>, tk: Array<U32>, +nt: Nat, +tpos: Nat, +bs: Nat, w: FW, +plen: Nat, +pdist: Nat,
  +len: Nat, +dist: Nat) -> FZ:
  match take avail:
    case True{} _:
      zlazy.hp(fins(Nat.sub(plen, 2n), x, n, 1n+i, HP{head, prev}),
        Array.set(U32, tk, U32.from_nat(nt), tok_ref(plen, pdist)), x, n, i, nt, tpos, bs, w, plen)
    case False{} True{}:
      FZ{1n+i, head, prev, Array.set(U32, tk, U32.from_nat(nt), Bytes.get(x, Nat.sub(i, 1n))), 1n+nt,
        1n+tpos, bs, w, len, dist, True{}, Nat.is_lt(1n+i, n)}
    case False{} False{}:
      FZ{1n+i, head, prev, tk, nt, tpos, bs, w, len, dist, True{}, Nat.is_lt(1n+i, n)}

def zlazy.at(fm: ZM, +x: Bytes(), +n: Nat, +i: Nat, tk: Array<U32>, +nt: Nat, +tpos: Nat, +bs: Nat,
  w: FW, +plen: Nat, +pdist: Nat, avail: Bool) -> FZ:
  match fm:
    case ZM{head, prev, +len, +dist}:
      zlazy.ok(Nat.is_le(3n, plen) && Nat.is_le(len, plen), avail, x, n, i, head, prev, tk, nt, tpos,
        bs, w, plen, pdist, len, dist)

# a position: greedy or lazy
def fpos.at(slow: Bool, +x: Bytes(), +n: Nat, +lv: Lv, +i: Nat, head: Array<U32>,
  prev: Array<U32>, tk: Array<U32>, +nt: Nat, +tpos: Nat, +bs: Nat, w: FW, +plen: Nat, +pdist: Nat,
  avail: Bool) -> FZ:
  match slow:
    case False{}:
      zgreedy.at(zfind(Nat.is_le(Nat.add(i, 3n), n), x, n, i, lv_nice(lv), lv_chain(lv), head,
        prev), x, n, lv_lazy(lv), i, tk, nt, tpos, bs, w)
    case True{}:
      zlazy.at(zfind(Nat.is_le(Nat.add(i, 3n), n), x, n, i, lv_nice(lv),
        pick(Nat.is_lt(plen, lv_lazy(lv)),
          pick(Nat.is_le(lv_good(lv), plen), Nat.div(lv_chain(lv), 4n), lv_chain(lv)), 0n),
        head, prev), x, n, i, tk, nt, tpos, bs, w, plen, pdist, avail)

def fpos(+x: Bytes(), +n: Nat, +lv: Lv, +i: Nat, head: Array<U32>, prev: Array<U32>,
  tk: Array<U32>, +nt: Nat, +tpos: Nat, +bs: Nat, w: FW, +plen: Nat, +pdist: Nat, avail: Bool) -> FZ:
  fpos.at(lv_slow(lv), x, n, lv, i, head, prev, tk, nt, tpos, bs, w, plen, pdist, avail)

def fflush.at(r: TW, +x: Bytes(), +n: Nat, +lv: Lv, +i: Nat, head: Array<U32>, prev: Array<U32>,
  +tpos: Nat, +bs: Nat, +plen: Nat, +pdist: Nat, avail: Bool) -> FZ:
  match r:
    case TW{tk, w}:
      fpos(x, n, lv, i, head, prev, tk, 0n, tpos, bs, w, plen, pdist, avail)

# a full block goes out first
def fstep(full: Bool, +x: Bytes(), +n: Nat, +lv: Lv, +i: Nat, head: Array<U32>,
  prev: Array<U32>, tk: Array<U32>, +nt: Nat, +tpos: Nat, +bs: Nat, w: FW, +plen: Nat, +pdist: Nat,
  avail: Bool) -> FZ:
  match full:
    case True{}:
      +len = Nat.min(Nat.sub(tpos, bs), Nat.sub(n, bs))
      fflush.at(fblock(tk, nt, x, bs, len, False{}, w), x, n, lv, i, head, prev, tpos,
        Nat.add(bs, len), plen, pdist, avail)
    case False{}:
      fpos(x, n, lv, i, head, prev, tk, nt, tpos, bs, w, plen, pdist, avail)

def flz(k: Nat, +x: Bytes(), +n: Nat, +lv: Lv, z: FZ) -> FZ:
  match k:
    case 0n:
      z
    case 1n+p:
      match z:
        case FZ{+i, head, prev, tk, +nt, +tpos, +bs, w, +plen, +pdist, avail, go}:
          match go:
            case False{}:
              FZ{i, head, prev, tk, nt, tpos, bs, w, plen, pdist, avail, False{}}
            case True{}:
              flz(p, x, n, lv, fstep(Nat.is_le(16383n, nt), x, n, lv, i, head, prev, tk, nt, tpos, bs,
                w, plen, pdist, avail))

def fend.tw(r: TW) -> Bytes():
  match r:
    case TW{tk, w}:
      fw_out(falign(w))

# the pass is over: the byte held, if one, and the last block
def fend.at(avail: Bool, +x: Bytes(), +n: Nat, tk: Array<U32>, +nt: Nat, +bs: Nat, w: FW) -> Bytes():
  match avail:
    case True{}:
      fend.tw(fblock(Array.set(U32, tk, U32.from_nat(nt), Bytes.get(x, Nat.sub(n, 1n))), 1n+nt, x, bs,
        Nat.sub(n, bs), True{}, w))
    case False{}:
      fend.tw(fblock(tk, nt, x, bs, Nat.sub(n, bs), True{}, w))

def fend(+x: Bytes(), +n: Nat, z: FZ) -> Bytes():
  match z:
    case FZ{i, head, prev, tk, +nt, tpos, +bs, w, plen, pdist, avail, go}:
      fend.at(avail, x, n, tk, nt, bs, w)

# the raw deflate stream of x at a level from 1 to 9
def fdeflate(+x: Bytes(), +lvl: Nat) -> Bytes():
  +n = Bytes.len(x)
  fend(x, n, flz(1n+n, x, n, level(lvl), FZ{0n, Array.new(U32, 15n, 0), Array.new(U32, 15n, 0),
    Array.new(U32, 15n, 0), 0n, 0n, 0n, FW{"", 0, 0n}, 0n, 0n, False{}, Nat.is_lt(0n, n)}))

def deflate.at(lz_level: Bool, +x: Bytes(), +lvl: Nat) -> Bytes():
  match lz_level:
    case False{}:
      w_out(stored.go(x, True{}, SS{"", z16(), w_new()}))
    case True{}:
      fdeflate(x, lvl)

def deflate(+x: Bytes(), +lvl: Nat) -> Bytes():
  deflate.at(Nat.is_lt(0n, lvl), x, lvl)

# the tokens of a fixed pass (which never cuts a block): the byte held
# at the end, if one, after them
def lz_toks.at(avail: Bool, +x: Bytes(), +n: Nat, toks: List<&2, Tok>) -> List<&2, Tok>:
  match avail:
    case True{}:
      List.reverse(&2, Tok, Con{Lit{Bytes.get(x, Nat.sub(n, 1n))}, toks})
    case False{}:
      List.reverse(&2, Tok, toks)

def lz_toks(z: Z) -> List<&2, Tok>:
  match z:
    case Z{x, n, lv, t, i, h, toks, nt, tpos, bs, w, plen, pdist, avail, go}:
      lz_toks.at(avail, x, n, toks)

# the same matches, as one block with the fixed code: the tokens are
# checked against x as the block is written (fixtoks), so what is
# written is x whatever the pass found
def deflate_fixed(+x: Bytes(), +lvl: Nat) -> Bytes():
  w_out(align(fixed_block(fixtoks(lz_toks(lz_all(x, Nat.max(1n, lvl), True{})), x, 0n, Bytes.len(x)),
    w_new(), True{}, ec_fixed(True{}))))
