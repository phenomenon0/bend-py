# Utf8: validate a byte buffer as UTF-8 with a fork tree, and find its first
# bad byte, without knowing where any leaf starts in the character stream.
#
# A validator is a DFA (Unicode 15, table 3-7): 0 ACC, 1-3 tails still owed,
# 4 E0 / 5 ED / 6 F0 / 7 F4 (a lead whose next byte has a narrowed range), 8
# DEAD. A leaf does not know which state it starts in, so it computes where it
# would end from each of the eight live states (Mytkowicz et al., "Data-parallel
# finite-state machines", ASPLOS 2014). DEAD is absorbing, so that map is eight
# nibbles -- one U32 -- and maps compose associatively: `then` is both the
# per-byte step and the join. UTF-8 self-synchronizes, so four bytes into a
# leaf every live start has converged on one state; from there a leaf runs one
# DFA, one lookup a byte, carrying which starts are still alive. A byte's class
# is a telescoping sum over the thirteen edges of the table, with no branch.
#
#   check(b, d)      the map and the scalar count of all of b, over 2^d leaves;
#                    valid iff the map sends ACC to ACC (valid(map))
#   first_bad(b, d)  the first byte at which a validator dies (len(b) if it
#                    runs out mid-scalar; none() if b is valid), by descending
#                    the same tree: a left half's map says whether a DFA
#                    entering it dies inside, so only one child is entered
#
# The buffer is Base's Bytes() -- a String of bytes, packed a byte a cell, kind
# Data -- so the fork shares it (one count per fork, not per read) and every
# read is Bytes.get's native borrowed load. demos/monoids/utf8.bend is the
# showcase this was lifted from; tests/power/utf8.bend holds it to CPython's
# own decoder.
import Base

type Sum is Data:
  Sum{map: U32, count: U32}

# -- the monoid ---------------------------------------------------------------

def ident() -> U32:
  1985229328 # 0x76543210: every state to itself

def nib(+m: U32, s: Nat) -> U32:
  U32.and(U32.shrn(m, s), 15)

# where g sends state t; DEAD (8) shifts g by 32, which is 0, and t & 8 restores it
def look(+g: U32, +t: U32) -> U32:
  U32.or(U32.and(U32.shrn(g, U32.to_nat(U32.shln(t, 2n))), 15), U32.and(t, 8))

# f, then g
def then(+f: U32, +g: U32) -> U32:
  +a = U32.or(look(g, nib(f, 0n)), U32.shln(look(g, nib(f, 4n)), 4n))
  +b = U32.or(U32.shln(look(g, nib(f, 8n)), 8n), U32.shln(look(g, nib(f, 12n)), 12n))
  +c = U32.or(U32.shln(look(g, nib(f, 16n)), 16n), U32.shln(look(g, nib(f, 20n)), 20n))
  +d = U32.or(U32.shln(look(g, nib(f, 24n)), 24n), U32.shln(look(g, nib(f, 28n)), 28n))
  U32.or(U32.or(a, b), U32.or(c, d))

def join(x: Sum, y: Sum) -> Sum:
  match x y:
    case Sum{f, c} Sum{g, e}:
      Sum{then(f, g), U32.add(c, e)}

def valid(+m: U32) -> Bool:
  U32.is_zero(nib(m, 0n))

def none() -> U32:
  4294967295

# -- one byte as a map ------------------------------------------------------------

def edge(+b: U32, x: U32, d: U32) -> U32:
  U32.mul(Bool.to_u32(U32.is_ge(b, x)), d)

#   80 tails (ED, F4 take them)  90 tails (ED, F0)  A0 tails (E0, F0)
#   C0 C1 dead  C2 lead 1  E0 lead E0  E1 lead 2  ED lead ED  EE lead 2
#   F0 lead F0  F1 lead 3  F4 lead F4  F5.. dead
def cls(+b: U32) -> U32:
  +t = U32.add(U32.add(edge(b, 128, 2676988040), edge(b, 144, 1509949440)),
    U32.add(edge(b, 160, 6881280), edge(b, 192, 101148544)))
  +l = U32.add(U32.add(edge(b, 194, 4294967289), edge(b, 224, 3)),
    U32.add(edge(b, 225, 4294967294), edge(b, 237, 3)))
  +h = U32.add(U32.add(edge(b, 238, 4294967293), edge(b, 240, 4)),
    U32.add(U32.add(edge(b, 241, 4294967293), edge(b, 244, 4)), edge(b, 245, 1)))
  U32.add(2290649216, U32.add(U32.add(t, l), h))

# 1 unless b is a tail byte: the scalar count of a valid range
def starts(+b: U32) -> U32:
  Bool.to_u32(U32.is_ne(U32.and(b, 192), 128))

def byte(+b: Bytes(), +p: U32) -> U32:
  U32.and(Bytes.get(b, U32.to_nat(p)), 255)

# -- a leaf ---------------------------------------------------------------------------

# k bytes from p as full maps
def leaf.gen(k: Nat, +b: Bytes(), +p: U32, +m: U32, +c: U32) -> Sum:
  match k:
    case 0n:
      Sum{m, c}
    case 1n++q:
      +x = byte(b, p)
      leaf.gen(q, b, U32.inc(p), then(m, cls(x)), U32.add(c, starts(x)))

# k bytes from p through one converged DFA in state x
def leaf.one(k: Nat, +b: Bytes(), +p: U32, +x: U32, +c: U32) -> Sum:
  match k:
    case 0n:
      Sum{x, c}
    case 1n++q:
      +y = byte(b, p)
      leaf.one(q, b, U32.inc(p), look(cls(y), x), U32.add(c, starts(y)))

# k whole words from byte p: four bytes of one borrowed read a turn
def leaf.words(k: Nat, +b: Bytes(), +p: U32, +x: U32, +c: U32) -> Sum:
  match k:
    case 0n:
      Sum{x, c}
    case 1n++q:
      +w = Bytes.word_le(b, U32.to_nat(p))
      +b0 = U32.and(w, 255)
      +b1 = U32.and(U32.shrn(w, 8n), 255)
      +b2 = U32.and(U32.shrn(w, 16n), 255)
      +b3 = U32.shrn(w, 24n)
      +n = U32.add(U32.add(starts(b0), starts(b1)), U32.add(starts(b2), starts(b3)))
      leaf.words(q, b, U32.add(p, 4), look(cls(b3), look(cls(b2), look(cls(b1), look(cls(b0), x)))),
        U32.add(c, n))

def leaf.tail(s: Sum, +b: Bytes(), +p: U32, +k: U32) -> Sum:
  match s:
    case Sum{x, c}:
      leaf.one(U32.to_nat(k), b, p, x, c)

# 0xF on each live nibble of a converged map, the one state they hold, and back
def alive(+m: U32) -> U32:
  U32.mul(U32.and(U32.not(U32.shrn(m, 3n)), 286331153), 15)

def common(+v: U32) -> U32:
  +a = U32.or(v, U32.shrn(v, 16n))
  +b = U32.or(a, U32.shrn(a, 8n))
  U32.and(U32.or(b, U32.shrn(b, 4n)), 15)

def spread(+l: U32, +x: U32) -> U32:
  U32.or(U32.and(l, U32.mul(x, 286331153)), U32.and(U32.not(l), 2290649224))

def leaf.end(+l: U32, s: Sum) -> Sum:
  match s:
    case Sum{x, c}:
      Sum{spread(l, x), c}

# after the first four bytes: every live start has converged; one DFA on
def leaf.rest(s: Sum, +b: Bytes(), +p: U32, +k: U32) -> Sum:
  match s:
    case Sum{+m, c}:
      +l = alive(m)
      +w = U32.shrn(k, 2n)
      leaf.end(l, leaf.tail(leaf.words(U32.to_nat(w), b, p, common(U32.and(m, l)), c), b,
        U32.add(p, U32.shln(w, 2n)), U32.and(k, 3)))

def leaf.short(c: Bool, s: Sum, +b: Bytes(), +p: U32, +n: U32) -> Sum:
  match c:
    case True{}:
      s # under four bytes: no convergence promised, keep the full map
    case False{}:
      leaf.rest(s, b, U32.add(p, 4), U32.sub(n, 4))

def leaf(+b: Bytes(), +p: U32, +n: U32) -> Sum:
  leaf.short(U32.is_lt(n, 4), leaf.gen(U32.to_nat(U32.min(n, 4)), b, p, ident(), 0), b, p, n)

# -- the tree -------------------------------------------------------------------------

# bytes lo .. lo+n-1 of b, 2^d leaves
def tree(d: Nat, +b: Bytes(), +lo: U32, +n: U32) -> Sum:
  match d:
    case 0n:
      leaf(b, lo, n)
    case 1n++p:
      +h = U32.shr(n)
      l r = tree(p, b, lo, h) tree(p, b, U32.add(lo, h), U32.sub(n, h))
      join(l, r)

# the map and scalar count of all of b, over 2^d leaves
def check(+b: Bytes(), d: Nat) -> Sum:
  tree(d, b, 0, U32.from_nat(Bytes.len(b)))

# -- the first bad byte -------------------------------------------------------------

# the first byte at or after p that kills a DFA standing in state s; if none
# does and the bytes end mid-scalar, the end; else none()
def walk(k: Nat, +b: Bytes(), +p: U32, +s: U32, +at: U32) -> U32:
  match k:
    case 0n:
      Bool.pick(U32, Bool.and(U32.is_eq(at, none()), U32.is_ne(s, 0)), p, at)
    case 1n++q:
      +s2 = look(cls(byte(b, p)), s)
      +first = Bool.and(U32.is_eq(s2, 8), U32.is_eq(at, none()))
      walk(q, b, U32.inc(p), s2, Bool.pick(U32, first, p, at))

def map_of(s: Sum) -> U32:
  match s:
    case Sum{f, _}:
      f

# a node of n bytes from lo, entered in state s; left is its left half's
# summary (made at depth d - 1). Only one child is entered: the left if the
# DFA dies there, else the right, in the state the left half leaves it in.
# If nothing dies the path is the rightmost one, so the last walk sees the end.
def dead(d: Nat, left: Sum, +b: Bytes(), +lo: U32, +n: U32, +s: U32) -> U32:
  match d:
    case 0n:
      walk(U32.to_nat(n), b, lo, s, none())
    case 1n++p:
      +h = U32.shr(n)
      +mid = look(map_of(left), s)
      +go_left = U32.is_eq(mid, 8)
      +lo2 = Bool.pick(U32, go_left, lo, U32.add(lo, h))
      +n2 = Bool.pick(U32, go_left, h, U32.sub(n, h))
      dead(p, tree(Nat.sub(p, 1n), b, lo2, U32.shr(n2)), b, lo2, n2,
        Bool.pick(U32, go_left, s, mid))

# where a validator reading b from the start dies: the first byte it cannot
# take; len(b) if b ends mid-scalar; none() if b is valid. 2^d leaves, d >= 1.
def first_bad(+b: Bytes(), +d: Nat) -> U32:
  +n = U32.from_nat(Bytes.len(b))
  dead(d, tree(Nat.sub(d, 1n), b, 0, U32.shr(n)), b, 0, n, 0)
