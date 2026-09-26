# BLAKE3: the 32-byte root hash of a byte range, and the pieces a caller needs
# to build that hash in parallel -- chunk for a leaf, parent for a join. A
# content address is the hash; two ranges with the same address hold the same
# bytes, and the tree means a caller may hash the halves on different cores and
# still land on the number a single pass would have printed.
#
# Written for the compiled lanes: the sixteen words of a block, the sixteen of
# the compression state and the eight of a chaining value are records of U32,
# not arrays, so a round is straight-line register arithmetic with no memory
# between the G's and no bounds check anywhere in the 448 operations of a
# compression. Only the block read touches the buffer.
#
# The tree is the reference implementation's chunk stack, not a recursion: a
# def may not call one defined after it, so a left-then-right tree walk is not
# expressible. Chunks go by left to right, each chaining value is merged into a
# stack of perfect subtrees whenever the chunk count says a subtree just closed,
# and the leftovers fold right to left at the end. Same tree, one loop.
import Base
import ./vec.bend as Vec
import ./bytes.bend as Bytes

# the chaining value: eight words, the hash of one subtree
type Cv is Data:
  Cv{a0: U32, a1: U32, a2: U32, a3: U32, a4: U32, a5: U32, a6: U32, a7: U32}

# the compression state: sixteen words
type St is Data:
  St{v0: U32, v1: U32, v2: U32, v3: U32, v4: U32, v5: U32, v6: U32, v7: U32,
     v8: U32, v9: U32, v10: U32, v11: U32, v12: U32, v13: U32, v14: U32, v15: U32}

# a 64-byte message block, sixteen little-endian words
type Bk is Data:
  Bk{m0: U32, m1: U32, m2: U32, m3: U32, m4: U32, m5: U32, m6: U32, m7: U32,
     m8: U32, m9: U32, m10: U32, m11: U32, m12: U32, m13: U32, m14: U32, m15: U32}

# what one G returns: the four words it touched
type Q is Data:
  Q{qa: U32, qb: U32, qc: U32, qd: U32}

# the flags. A chunk's first block opens it and its last closes it; a parent
# node says so; the one node at the top of the tree is the root.
def CHUNK_START() -> U32:
  1

def CHUNK_END() -> U32:
  2

def PARENT() -> U32:
  4

def ROOT() -> U32:
  8

# the IV: the first eight fractional words of the square roots of the first
# eight primes, the same constants SHA-256 uses
def iv() -> Cv:
  Cv{1779033703, 3144134277, 1013904242, 2773480762,
     1359893119, 2600822924, 528734635, 1541459225}

# BLAKE3 rotates right; l is 32 - r, passed in so no Nat subtraction runs here
def rotr(+x: U32, r: Nat, l: Nat) -> U32:
  U32.or(U32.shrn(x, r), U32.shln(x, l))

# the G function, BLAKE2s's quarter round with BLAKE3's rotation counts
def g(a: U32, +b: U32, c: U32, d: U32, mx: U32, my: U32) -> Q:
  +a1 = U32.add(U32.add(a, b), mx)
  +d1 = rotr(U32.xor(d, a1), 16n, 16n)
  +c1 = U32.add(c, d1)
  +b1 = rotr(U32.xor(b, c1), 12n, 20n)
  +a2 = U32.add(U32.add(a1, b1), my)
  +d2 = rotr(U32.xor(d1, a2), 8n, 24n)
  +c2 = U32.add(c1, d2)
  b2 = rotr(U32.xor(b1, c2), 7n, 25n)
  Q{a2, b2, c2, d2}

def cg0.put(q: Q, v1: U32, v2: U32, v3: U32, v5: U32, v6: U32, v7: U32, v9: U32, v10: U32, v11: U32, v13: U32, v14: U32, v15: U32) -> St:
  match q:
    case Q{qa, qb, qc, qd}:
      St{qa, v1, v2, v3, qb, v5, v6, v7, qc, v9, v10, v11, qd, v13, v14, v15}

def cg0(mx: U32, my: U32, s: St) -> St:
  match s:
    case St{v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15}:
      cg0.put(g(v0, v4, v8, v12, mx, my), v1, v2, v3, v5, v6, v7, v9, v10, v11, v13, v14, v15)

def cg1.put(q: Q, v0: U32, v2: U32, v3: U32, v4: U32, v6: U32, v7: U32, v8: U32, v10: U32, v11: U32, v12: U32, v14: U32, v15: U32) -> St:
  match q:
    case Q{qa, qb, qc, qd}:
      St{v0, qa, v2, v3, v4, qb, v6, v7, v8, qc, v10, v11, v12, qd, v14, v15}

def cg1(mx: U32, my: U32, s: St) -> St:
  match s:
    case St{v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15}:
      cg1.put(g(v1, v5, v9, v13, mx, my), v0, v2, v3, v4, v6, v7, v8, v10, v11, v12, v14, v15)

def cg2.put(q: Q, v0: U32, v1: U32, v3: U32, v4: U32, v5: U32, v7: U32, v8: U32, v9: U32, v11: U32, v12: U32, v13: U32, v15: U32) -> St:
  match q:
    case Q{qa, qb, qc, qd}:
      St{v0, v1, qa, v3, v4, v5, qb, v7, v8, v9, qc, v11, v12, v13, qd, v15}

def cg2(mx: U32, my: U32, s: St) -> St:
  match s:
    case St{v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15}:
      cg2.put(g(v2, v6, v10, v14, mx, my), v0, v1, v3, v4, v5, v7, v8, v9, v11, v12, v13, v15)

def cg3.put(q: Q, v0: U32, v1: U32, v2: U32, v4: U32, v5: U32, v6: U32, v8: U32, v9: U32, v10: U32, v12: U32, v13: U32, v14: U32) -> St:
  match q:
    case Q{qa, qb, qc, qd}:
      St{v0, v1, v2, qa, v4, v5, v6, qb, v8, v9, v10, qc, v12, v13, v14, qd}

def cg3(mx: U32, my: U32, s: St) -> St:
  match s:
    case St{v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15}:
      cg3.put(g(v3, v7, v11, v15, mx, my), v0, v1, v2, v4, v5, v6, v8, v9, v10, v12, v13, v14)

def dg0.put(q: Q, v1: U32, v2: U32, v3: U32, v4: U32, v6: U32, v7: U32, v8: U32, v9: U32, v11: U32, v12: U32, v13: U32, v14: U32) -> St:
  match q:
    case Q{qa, qb, qc, qd}:
      St{qa, v1, v2, v3, v4, qb, v6, v7, v8, v9, qc, v11, v12, v13, v14, qd}

def dg0(mx: U32, my: U32, s: St) -> St:
  match s:
    case St{v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15}:
      dg0.put(g(v0, v5, v10, v15, mx, my), v1, v2, v3, v4, v6, v7, v8, v9, v11, v12, v13, v14)

def dg1.put(q: Q, v0: U32, v2: U32, v3: U32, v4: U32, v5: U32, v7: U32, v8: U32, v9: U32, v10: U32, v13: U32, v14: U32, v15: U32) -> St:
  match q:
    case Q{qa, qb, qc, qd}:
      St{v0, qa, v2, v3, v4, v5, qb, v7, v8, v9, v10, qc, qd, v13, v14, v15}

def dg1(mx: U32, my: U32, s: St) -> St:
  match s:
    case St{v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15}:
      dg1.put(g(v1, v6, v11, v12, mx, my), v0, v2, v3, v4, v5, v7, v8, v9, v10, v13, v14, v15)

def dg2.put(q: Q, v0: U32, v1: U32, v3: U32, v4: U32, v5: U32, v6: U32, v9: U32, v10: U32, v11: U32, v12: U32, v14: U32, v15: U32) -> St:
  match q:
    case Q{qa, qb, qc, qd}:
      St{v0, v1, qa, v3, v4, v5, v6, qb, qc, v9, v10, v11, v12, qd, v14, v15}

def dg2(mx: U32, my: U32, s: St) -> St:
  match s:
    case St{v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15}:
      dg2.put(g(v2, v7, v8, v13, mx, my), v0, v1, v3, v4, v5, v6, v9, v10, v11, v12, v14, v15)

def dg3.put(q: Q, v0: U32, v1: U32, v2: U32, v5: U32, v6: U32, v7: U32, v8: U32, v10: U32, v11: U32, v12: U32, v13: U32, v15: U32) -> St:
  match q:
    case Q{qa, qb, qc, qd}:
      St{v0, v1, v2, qa, qb, v5, v6, v7, v8, qc, v10, v11, v12, v13, qd, v15}

def dg3(mx: U32, my: U32, s: St) -> St:
  match s:
    case St{v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15}:
      dg3.put(g(v3, v4, v9, v14, mx, my), v0, v1, v2, v5, v6, v7, v8, v10, v11, v12, v13, v15)

# one round: the four column G's, then the four diagonal ones
def round8(m0: U32, m1: U32, m2: U32, m3: U32, m4: U32, m5: U32, m6: U32, m7: U32, m8: U32, m9: U32, m10: U32, m11: U32, m12: U32, m13: U32, m14: U32, m15: U32, s: St) -> St:
  dg3(m14, m15, dg2(m12, m13, dg1(m10, m11, dg0(m8, m9, cg3(m6, m7, cg2(m4, m5, cg1(m2, m3, cg0(m0, m1, s))))))))

# the seven rounds, each on the last one's permuted message
def rnd(fuel: Nat, +m0: U32, +m1: U32, +m2: U32, +m3: U32, +m4: U32, +m5: U32, +m6: U32, +m7: U32, +m8: U32, +m9: U32, +m10: U32, +m11: U32, +m12: U32, +m13: U32, +m14: U32, +m15: U32, s: St) -> St:
  match fuel:
    case 0n:
      s
    case 1n++p:
      rnd(p, m2, m6, m3, m10, m7, m0, m4, m13, m1, m11, m12, m5, m9, m14, m15, m8,
        round8(m0, m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14, m15, s))

# the compression: seven rounds over a state seeded with the chaining value,
# the IV's first four words, the chunk counter, the block length and the flags.
# The new chaining value is the two halves of the finished state xored, which
# is also the first 32 bytes of the extended output -- so the root needs no
# separate path.
def compress.out(s: St) -> Cv:
  match s:
    case St{v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15}:
      Cv{U32.xor(v0, v8), U32.xor(v1, v9), U32.xor(v2, v10), U32.xor(v3, v11),
         U32.xor(v4, v12), U32.xor(v5, v13), U32.xor(v6, v14), U32.xor(v7, v15)}

def compress.m(c0: U32, c1: U32, c2: U32, c3: U32, c4: U32, c5: U32, c6: U32, c7: U32,
               ct: U32, ch: U32, bl: U32, fl: U32, m: Bk) -> Cv:
  match m:
    case Bk{m0, m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14, m15}:
      compress.out(rnd(7n, m0, m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14, m15,
        St{c0, c1, c2, c3, c4, c5, c6, c7,
           1779033703, 3144134277, 1013904242, 2773480762, ct, ch, bl, fl}))

# compress: the chaining value c fed one block, at chunk counter ct/ch, with bl
# of the block's 64 bytes real and the flags fl
def compress(c: Cv, m: Bk, ct: U32, ch: U32, bl: U32, fl: U32) -> Cv:
  match c:
    case Cv{c0, c1, c2, c3, c4, c5, c6, c7}:
      compress.m(c0, c1, c2, c3, c4, c5, c6, c7, ct, ch, bl, fl, m)

# parent: the chaining value of the node whose children are l and r. fl carries
# ROOT for the one node at the top and nothing for the rest.
def parent.r(a0: U32, a1: U32, a2: U32, a3: U32, a4: U32, a5: U32, a6: U32, a7: U32,
             +fl: U32, r: Cv) -> Cv:
  match r:
    case Cv{b0, b1, b2, b3, b4, b5, b6, b7}:
      compress(iv(), Bk{a0, a1, a2, a3, a4, a5, a6, a7, b0, b1, b2, b3, b4, b5, b6, b7},
        0, 0, 64, U32.or(4, fl))

def parent(l: Cv, r: Cv, +fl: U32) -> Cv:
  match l:
    case Cv{a0, a1, a2, a3, a4, a5, a6, a7}:
      parent.r(a0, a1, a2, a3, a4, a5, a6, a7, fl, r)

# -- reading a block out of the buffer ---------------------------------------

# a word of the block: whole if all four bytes are below the content end, the
# valid low bytes masked if it straddles it, and zero past it. BLAKE3 pads the
# last block of a chunk with zeros; at wraps at the capacity rather than
# faulting, so the mask is the whole of the padding.
def w.mask(k: Nat, r: Bytes() & U32) -> Bytes() & U32:
  (b, x) = r
  (b, U32.and(x, U32.sub(U32.shln(1, k), 1)))

def w.part(b: Bytes(), +o: U32, e: U32) -> Bytes() & U32:
  w.mask(U32.to_nat(U32.shln(U32.sub(e, o), 3n)), Bytes.word_le(b, o))

def w.if(b: Bytes(), +o: U32, +e: U32, some: Bool) -> Bytes() & U32:
  match some:
    case True{}:
      w.part(b, o, e)
    case False{}:
      (b, 0)

def w.go(b: Bytes(), +o: U32, +e: U32, full: Bool) -> Bytes() & U32:
  match full:
    case True{}:
      Bytes.word_le(b, o)
    case False{}:
      w.if(b, o, e, U32.is_lt(o, e))

def w(b: Bytes(), +o: U32, +e: U32) -> Bytes() & U32:
  w.go(b, o, e, U32.is_lt(U32.add(o, 3), e))

# the block is filled by a shift register rather than a sixteen-deep ladder: a
# read hands back a pair, a pair cannot be opened mid-body, and sixteen nested
# readers each carrying the words before it is 136 parameters of plumbing. One
# push that drops the oldest word and appends the newest, run sixteen times
# from zero, leaves the words in order.
def bk.push(m: Bk, x: U32) -> Bk:
  match m:
    case Bk{m0, m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14, m15}:
      Bk{m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14, m15, x}

type Rd is Type:
  Rd{o: U32, e: U32, m: Bk, b: Bytes()}

def rd.step(o: U32, e: U32, m: Bk, r: Bytes() & U32) -> Rd:
  (b, x) = r
  Rd{o, e, bk.push(m, x), b}

def rd.one(s: Rd) -> Rd:
  match s:
    case Rd{+o, +e, m, b}:
      rd.step(U32.add(o, 4), e, m, w(b, o, e))

def rd.go(fuel: Nat, s: Rd) -> Rd:
  match fuel:
    case 0n:
      s
    case 1n++p:
      rd.go(p, rd.one(s))

def blk.out(s: Rd) -> Bytes() & Bk:
  match s:
    case Rd{o, e, m, b}:
      (b, m)

# blk: the 64-byte block at o, zero-padded past the content end e, its words
# read where they lie in the buffer (a borrowed read on C, an index on JS)
def blk(b: Bytes(), o: U32, e: U32) -> Bytes() & Bk:
  blk.out(rd.go(16n, Rd{o, e, Bk{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}, b}))

# -- one chunk ---------------------------------------------------------------

def bit(b: Bool, +x: U32) -> U32:
  match b:
    case True{}:
      x
    case False{}:
      0

type Ck is Type:
  Ck{cv: Cv, o: U32, e: U32, t: U32, fl: U32, i: U32, b: Bytes()}

def ck.put(+o: U32, +e: U32, +t: U32, +fl: U32, +i: U32, cv: Cv, bl: U32, f: U32,
           r: Bytes() & Bk) -> Ck:
  (b, m) = r
  Ck{compress(cv, m, t, 0, bl, f), U32.add(o, 64), e, t, fl, U32.inc(i), b}

# a chunk's first block opens it and its last closes it. fl is what the caller
# adds on top -- ROOT when this chunk is the whole message -- and it rides the
# closing block alone: a root is the last compression of the tree, not every
# compression of its one chunk, and setting it on all sixteen blocks of a full
# chunk is a hash that agrees with BLAKE3 only while the chunk is one block.
def ck.one(+o: U32, +e: U32, +t: U32, +fl: U32, +i: U32, cv: Cv, b: Bytes()) -> Ck:
  ck.put(o, e, t, fl, i, cv,
    U32.min(U32.sub(e, o), 64),
    U32.or(bit(U32.is_zero(i), 1), bit(U32.is_lt(e, U32.add(o, 65)), U32.or(2, fl))),
    blk(b, o, e))

def ck.go(fuel: Nat, s: Ck) -> Ck:
  match fuel:
    case 0n:
      s
    case 1n++p:
      match s:
        case Ck{cv, o, e, t, fl, i, b}:
          ck.go(p, ck.one(o, e, t, fl, i, cv, b))

def ck.out(s: Ck) -> Bytes() & Cv:
  match s:
    case Ck{cv, o, e, t, fl, i, b}:
      (b, cv)

# the blocks of a chunk of n bytes: the empty chunk is still one block
def blocks(+n: U32) -> Nat:
  U32.to_nat(U32.max(U32.shrn(U32.add(n, 63), 6n), 1))

# chunk: the chaining value of the n bytes at off as chunk number t. fl is 0
# for a leaf of a tree and ROOT when the chunk is the whole message.
def chunk(b: Bytes(), +off: U32, +n: U32, t: U32, fl: U32) -> Bytes() & Cv:
  ck.out(ck.go(blocks(n), Ck{iv(), off, U32.add(off, n), t, fl, 0, b}))

# -- the chunk stack ---------------------------------------------------------

# after chunk number t - 1 is hashed, t perfect subtrees have closed for every
# low zero bit of t: merge that many times, then push. The stack therefore
# holds perfect subtrees of strictly decreasing size, left to right, which is
# exactly BLAKE3's tree.
type Mg is Data:
  MDone{st: List<&2, Cv>}
  MMore{t: U32, c: Cv, st: List<&2, Cv>}

def mg.on(+t: U32, c: Cv, h: Cv, tl: List<&2, Cv>, closed: Bool) -> Mg:
  match closed:
    case True{}:
      MMore{U32.shrn(t, 1n), parent(h, c, 0), tl}
    case False{}:
      MDone{Con{c, Con{h, tl}}}

def mg.step(+t: U32, c: Cv, st: List<&2, Cv>) -> Mg:
  match st:
    case Nil{}:
      MDone{Con{c, []}}
    case Con{h, tl}:
      mg.on(t, c, h, tl, U32.is_zero(U32.and(t, 1)))

def mg.end(m: Mg) -> List<&2, Cv>:
  match m:
    case MDone{st}:
      st
    case MMore{t, c, st}:
      Con{c, st}

def mg.go(fuel: Nat, m: Mg) -> List<&2, Cv>:
  match fuel:
    case 0n:
      mg.end(m)
    case 1n++p:
      match m:
        case MDone{st}:
          st
        case MMore{t, c, st}:
          mg.go(p, mg.step(t, c, st))

type Hs is Type:
  Hs{o: U32, t: U32, st: List<&2, Cv>, b: Bytes()}

def hs.put(+o: U32, +t: U32, st: List<&2, Cv>, r: Bytes() & Cv) -> Hs:
  (b, cv) = r
  Hs{U32.add(o, 1024), U32.inc(t), mg.go(32n, mg.step(U32.inc(t), cv, st)), b}

def hs.one(s: Hs) -> Hs:
  match s:
    case Hs{+o, +t, st, b}:
      hs.put(o, t, st, chunk(b, o, 1024, t, 0))

def hs.go(fuel: Nat, s: Hs) -> Hs:
  match fuel:
    case 0n:
      s
    case 1n++p:
      hs.go(p, hs.one(s))

# the leftovers fold right to left, and the last join is the root
def fin.go(st: List<&2, Cv>, c: Cv) -> Cv:
  match st:
    case Nil{}:
      c
    case Con{h, tl}:
      match tl:
        case Nil{}:
          parent(h, c, 8)
        case Con{h2, t2}:
          fin.go(Con{h2, t2}, parent(h, c, 0))

def hash.fin(st: List<&2, Cv>, r: Bytes() & Cv) -> Bytes() & Cv:
  (b, c) = r
  (b, fin.go(st, c))

def hash.last(+e: U32, s: Hs) -> Bytes() & Cv:
  match s:
    case Hs{+o, t, st, b}:
      hash.fin(st, chunk(b, o, U32.sub(e, o), t, 0))

# every chunk but the last goes through the stack; the last one stays out of it
# so that the final join is the one that carries ROOT
def hash.big(b: Bytes(), +off: U32, +n: U32, nc: U32) -> Bytes() & Cv:
  hash.last(U32.add(off, n), hs.go(U32.to_nat(U32.sub(nc, 1)), Hs{off, 0, [], b}))

def hash.if(b: Bytes(), +off: U32, +n: U32, one: Bool) -> Bytes() & Cv:
  match one:
    case True{}:
      chunk(b, off, n, 0, 8)
    case False{}:
      hash.big(b, off, n, U32.shrn(U32.add(n, 1023), 10n))

# hash: the BLAKE3 root of the n bytes at off. A message of one chunk or less
# is that chunk hashed as the root; anything longer is the tree.
def hash(b: Bytes(), +off: U32, +n: U32) -> Bytes() & Cv:
  hash.if(b, off, n, U32.is_lt(n, 1025))

def all.len(r: Bytes() & U32) -> Bytes() & Cv:
  (b, n) = r
  hash(b, 0, n)

# hash_all: the root of the whole buffer
def hash_all(b: Bytes()) -> Bytes() & Cv:
  all.len(Bytes.len(b))

# -- the address as text -----------------------------------------------------

def hexc.if(+d: U32, lo: Bool) -> Char:
  match lo:
    case True{}:
      Char.from_u32(U32.add(d, 48))
    case False{}:
      Char.from_u32(U32.add(d, 87))

def hexc(+d: U32) -> Char:
  hexc.if(d, U32.is_lt(d, 10))

def nib(+x: U32, s: Nat) -> Char:
  hexc(U32.and(U32.shrn(x, s), 15))

# a word's four bytes, little end first, two hex digits each
def hexw(+x: U32, t: List<&2, Char>) -> List<&2, Char>:
  Con{nib(x, 4n), Con{nib(x, 0n), Con{nib(x, 12n), Con{nib(x, 8n),
    Con{nib(x, 20n), Con{nib(x, 16n), Con{nib(x, 28n), Con{nib(x, 24n), t}}}}}}}}

# hex: the 64 hex digits the BLAKE3 command line prints
def hex(c: Cv) -> String:
  match c:
    case Cv{a0, a1, a2, a3, a4, a5, a6, a7}:
      String.from_list(hexw(a0, hexw(a1, hexw(a2, hexw(a3,
        hexw(a4, hexw(a5, hexw(a6, hexw(a7, [])))))))))
