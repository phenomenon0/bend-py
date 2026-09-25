# Constrained decoding, sequential: 2,097,152 documents of 3 to 79 bytes, and at
# every one of those 85,983,692 positions the mask is *derived* before the byte
# is stepped. That is the decoder's real loop -- a sampler needs the set of legal
# next tokens at every position, not just a verdict at the end -- so a bench
# that only called step would measure half the primitive and the cheaper half.
#
# The document is a function of its index, not a buffer: 8 opening brackets, 32
# single digits separated by commas, 8 closing brackets. No Bytes anywhere, so
# the shard in grammar_par.bend needs no buffer of its own and the two benches
# do identical work per document. It exercises the stack (push, top, pop, and
# the depth-dependent masks of Sep and Int) which is the part a flat token
# grammar would not have.
#
# The checksum folds the mask itself -- three of its eight words, and the depth
# -- so a state that stepped correctly while masking wrongly still fails here.
# There is no fork in this file; grammar_par.bend is where the threads are.
import Base
import ../../../power/grammar.bend as Gr

def hash(+acc: U32, +x: U32) -> U32:
  U32.mul(U32.xor(acc, x), 16777619)

# all eight words, not the three that carry ASCII: a word neither side reads is
# a word either compiler may stop computing, and then the two are not doing the
# same work. Folding the whole mask keeps every lane live in both.
def fold1(+acc: U32, +d: U32, m: Gr.Mask) -> U32:
  match m:
    case Gr.Mask{w0, w1, w2, w3, w4, w5, w6, w7}:
      hash(acc, U32.xor(U32.xor(U32.xor(w0, w1), U32.xor(w2, w3)),
        U32.xor(U32.xor(w4, w5), U32.xor(w6, U32.add(w7, d)))))

def b(t: Bool) -> U32:
  match t:
    case True{}:
      1
    case False{}:
      0

def fin(+acc: U32, +s: Gr.St) -> U32:
  hash(acc, U32.add(U32.mul(b(Gr.done(s)), 2), b(Gr.live(s))))

# byte i of the document: d opening brackets, w body bytes, d closing brackets.
# The digit cycles on 8 and not 10 because U32.mod is a 32-step bit loop and
# this is an inner loop; eight digits are as valid as ten.
def byte.el(+j: U32, +o: U32, comma: Bool) -> U32:
  match comma:
    case True{}:
      44
    case False{}:
      U32.add(48, U32.and(U32.add(U32.shrn(j, 1n), o), 7))

def byte.mid(+j: U32, +o: U32) -> U32:
  byte.el(j, o, U32.is_eq(U32.and(j, 1), 1))

def byte.tail(+i: U32, +d: U32, +o: U32, shut: Bool) -> U32:
  match shut:
    case True{}:
      93
    case False{}:
      byte.mid(U32.sub(i, d), o)

def byte.go(+i: U32, +d: U32, +w: U32, +o: U32, open: Bool) -> U32:
  match open:
    case True{}:
      91
    case False{}:
      byte.tail(i, d, o, U32.is_ge(i, U32.add(d, w)))

def byte(+i: U32, +d: U32, +w: U32, +o: U32) -> U32:
  byte.go(i, d, w, o, U32.is_lt(i, d))

type Dc is Data:
  Dc{acc: U32, s: Gr.St}

# the state is read twice here -- its mask and its depth -- which a Type kind
# would refuse; St is Data, so +s is all it takes
def doc.mk(+acc: U32, +s: Gr.St, +c: U32) -> Dc:
  Dc{fold1(acc, Gr.depth(s), Gr.mask(s)), Gr.step(s, c)}

def doc.go(k: Nat, +i: U32, +d: U32, +w: U32, +o: U32, x: Dc) -> Dc:
  match k:
    case 0n:
      x
    case 1n++p:
      match x:
        case Dc{acc, s}:
          doc.go(p, U32.inc(i), d, w, o, doc.mk(acc, s, byte(i, d, w, o)))

def doc.out(x: Dc) -> U32:
  match x:
    case Dc{acc, s}:
      fin(acc, s)

def one.go(+acc: U32, +o: U32, +d: U32, +w: U32) -> U32:
  doc.out(doc.go(U32.to_nat(U32.add(U32.add(d, d), w)), 0, d, w, o,
    Dc{acc, Gr.start()}))

# the *shape* of document o -- 1 to 8 levels of nesting, 1 to 63 body bytes --
# and not only its digits, because a digit is a byte the state machine cannot
# tell from any other digit. Two documents that differ nowhere the mask can see
# are one document run twice, and a shard of those has a leaf checksum that says
# nothing about the shard (the trap lane 8 found in two shipped benches).
#
# The high bits of the product, not the low ones: multiplication carries
# upwards only, so o & 7 is blind to every bit above the third and every shard
# would draw the same shapes in the same order.
def one.dw(+acc: U32, +o: U32, +x: U32) -> U32:
  one.go(acc, o, U32.add(1, U32.and(U32.shrn(x, 29n), 7)),
    U32.sub(U32.mul(2, U32.add(1, U32.and(U32.shrn(x, 24n), 31))), 1))

def one(+acc: U32, +o: U32) -> U32:
  one.dw(acc, o, U32.mul(U32.xor(o, U32.shrn(o, 15n)), 2654435761))

def many(k: Nat, +o: U32, acc: U32) -> U32:
  match k:
    case 0n:
      acc
    case 1n++p:
      many(p, U32.inc(o), one(acc, o))

def main() -> U32:
  many(2097152n, 0, 0)
