# Bytes: a growable byte buffer, four bytes to a U32 cell of a Vec, little end
# first, so a buffer is a quarter the words of a U32 per byte and a whole cell
# is one native read. One owner: a write is in place, a read hands it back.
#
# Written for the compiled lanes: a byte is one shift and one mask of its cell;
# len is the truth, so pop and truncate move no data and push masks the slot it
# lands in rather than trusting it to be clean.
import Base
import ./vec.bend as Vec

type Bytes is Type:
  Bytes{len: U32, cells: Vec.Vec}

def new() -> Bytes:
  Bytes{0, Vec.new(0)}

def len(b: Bytes) -> Bytes & U32:
  match b:
    case Bytes{+n, v}:
      (Bytes{n, v}, n)

# the shift of byte i inside its cell: 0, 8, 16 or 24
def shift(i: U32) -> Nat:
  U32.to_nat(U32.shln(U32.and(i, 3), 3n))

# at: unchecked, the index wraps at the capacity
def at.fin(n: U32, +i: U32, r: Vec.Vec & U32) -> Bytes & U32:
  (v, w) = r
  (Bytes{n, v}, U32.and(U32.shrn(w, shift(i)), 255))

def at(b: Bytes, +i: U32) -> Bytes & U32:
  match b:
    case Bytes{n, v}:
      at.fin(n, i, Vec.at(v, U32.shrn(i, 2n)))

def get.some(r: Bytes & U32) -> Bytes & Maybe<&2, U32>:
  (b, x) = r
  (b, Some{x})

def get.if(b: Bytes, +i: U32, ok: Bool) -> Bytes & Maybe<&2, U32>:
  match ok:
    case True{}:
      get.some(at(b, i))
    case False{}:
      (b, None{})

def get(b: Bytes, +i: U32) -> Bytes & Maybe<&2, U32>:
  match b:
    case Bytes{+n, v}:
      get.if(Bytes{n, v}, i, U32.is_lt(i, n))

# word_le: the four bytes at byte index i, little end first, as one U32.
# Unchecked like at. An i that is a multiple of four is exactly one cell, so it
# is one native read and no shifting at all -- which is the only case a hash
# over 64-byte blocks ever asks for; any other i costs a second read, two
# shifts and an or.
def word_le.one(n: U32, r: Vec.Vec & U32) -> Bytes & U32:
  (v, w) = r
  (Bytes{n, v}, w)

def word_le.hi(n: U32, s: Nat, t: Nat, lo: U32, r: Vec.Vec & U32) -> Bytes & U32:
  (v, hi) = r
  (Bytes{n, v}, U32.or(U32.shrn(lo, s), U32.shln(hi, t)))

def word_le.lo(n: U32, +c: U32, s: Nat, t: Nat, r: Vec.Vec & U32) -> Bytes & U32:
  (v, lo) = r
  word_le.hi(n, s, t, lo, Vec.at(v, U32.inc(c)))

# the split shifts are 8, 16, 24 and their complements 24, 16, 8 -- never 0 or
# 32, which is why the aligned case has to be its own branch and not a shift by
# nothing
def word_le.if(n: U32, v: Vec.Vec, +i: U32, +c: U32, aligned: Bool) -> Bytes & U32:
  match aligned:
    case True{}:
      word_le.one(n, Vec.at(v, c))
    case False{}:
      word_le.lo(n, c, shift(i),
        U32.to_nat(U32.shln(U32.sub(4, U32.and(i, 3)), 3n)), Vec.at(v, c))

def word_le(b: Bytes, +i: U32) -> Bytes & U32:
  match b:
    case Bytes{n, v}:
      word_le.if(n, v, i, U32.shrn(i, 2n), U32.is_zero(U32.and(i, 3)))

# put: unchecked write of the low eight bits of x into slot i
def put.cell(+w: U32, +s: Nat, x: U32) -> U32:
  U32.or(U32.and(w, U32.not(U32.shln(255, s))), U32.shln(U32.and(x, 255), s))

def put.fin(+i: U32, x: U32, r: Vec.Vec & U32) -> Vec.Vec:
  (v, w) = r
  Vec.put(v, U32.shrn(i, 2n), put.cell(w, shift(i), x))

def put(b: Bytes, +i: U32, x: U32) -> Bytes:
  match b:
    case Bytes{n, v}:
      Bytes{n, put.fin(i, x, Vec.at(v, U32.shrn(i, 2n)))}

def set.if(b: Bytes, i: U32, x: U32, ok: Bool) -> Bytes & Bool:
  match ok:
    case True{}:
      (put(b, i, x), True{})
    case False{}:
      (b, False{})

def set(b: Bytes, +i: U32, x: U32) -> Bytes & Bool:
  match b:
    case Bytes{+n, v}:
      set.if(Bytes{n, v}, i, x, U32.is_lt(i, n))

# push: a byte that opens a cell pushes the cell (dropping any the length had
# already forgotten); any other lands in the last one
def push.if(+n: U32, v: Vec.Vec, x: U32, opens: Bool) -> Bytes:
  match opens:
    case True{}:
      Bytes{U32.inc(n), Vec.push(Vec.truncate(v, U32.shrn(n, 2n)), U32.and(x, 255))}
    case False{}:
      Bytes{U32.inc(n), put.fin(n, x, Vec.at(v, U32.shrn(n, 2n)))}

def push(b: Bytes, x: U32) -> Bytes:
  match b:
    case Bytes{+n, v}:
      push.if(n, v, x, U32.is_zero(U32.and(n, 3)))

def pop.if(+n: U32, v: Vec.Vec, empty: Bool) -> Bytes & Maybe<&2, U32>:
  match empty:
    case True{}:
      (Bytes{n, v}, None{})
    case False{}:
      get.some(at(Bytes{U32.sub(n, 1), v}, U32.sub(n, 1)))

def pop(b: Bytes) -> Bytes & Maybe<&2, U32>:
  match b:
    case Bytes{+n, v}:
      pop.if(n, v, U32.is_zero(n))

def truncate.if(n: U32, v: Vec.Vec, k: U32, shorter: Bool) -> Bytes:
  match shorter:
    case True{}:
      Bytes{k, v}
    case False{}:
      Bytes{n, v}

def truncate(b: Bytes, +k: U32) -> Bytes:
  match b:
    case Bytes{+n, v}:
      truncate.if(n, v, k, U32.is_lt(k, n))

# the list leads: a self-call must shrink before any argument changes
def from_list(xs: List<&2, U32>, b: Bytes) -> Bytes:
  match xs:
    case Nil{}:
      b
    case Con{x, t}:
      from_list(t, push(b, x))

def to_list.cons(r: Bytes & U32, acc: List<&2, U32>) -> Bytes & List<&2, U32>:
  (b, x) = r
  (b, Con{x, acc})

def to_list.step(i: U32, ba: Bytes & List<&2, U32>) -> Bytes & List<&2, U32>:
  (b, acc) = ba
  to_list.cons(at(b, i), acc)

def to_list.go(i: Nat, ba: Bytes & List<&2, U32>) -> Bytes & List<&2, U32>:
  match i:
    case 0n:
      ba
    case 1n++p:
      to_list.go(p, to_list.step(U32.from_nat(p), ba))

def to_list.len(r: Bytes & U32) -> Bytes & List<&2, U32>:
  (b, n) = r
  to_list.go(U32.to_nat(n), (b, []))

def to_list(b: Bytes) -> Bytes & List<&2, U32>:
  to_list.len(len(b))
