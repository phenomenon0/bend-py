# Constrained decoding, forked: 256 shards of 8,192 documents, the same
# 2,097,152 documents and the same 85,983,692 derived masks the sequential
# bench does, split 256 ways.
#
# This is the one _par bench in the library that needs no shard-private buffer,
# and the reason is the lane's whole claim. bm25_par, knn_par and cdc_par all
# shard because a Bytes or an Array has one owner and no two lanes can read one.
# A grammar state is five U32s and a Data tag, so it is copied, not moved: the
# same parent state goes down both sides of a fork, which is what a beam is. The
# document being a function of its index rather than a buffer is the same fact
# applied twice.
#
# 256 and not 64, for the reason cdc_par gives: the scheduler wants many more
# tasks than threads.
import Base
import ../../../power/grammar.bend as Gr

def hash(+acc: U32, +x: U32) -> U32:
  U32.mul(U32.xor(acc, x), 16777619)

# the join is not hash: xor-then-multiply is a bijection at every level, so no
# depth of tree folds the leaves away (cdc_par's finding, and its 31 * a + b
# tree really did fold to zero before it was changed)
def tmix(+a: U32, +b: U32) -> U32:
  U32.mul(U32.xor(U32.add(a, 2654435761), b), 16777619)

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

# shard s owns offsets s * 8192 .. s * 8192 + 8191. one.dw draws each document's
# shape from the high bits of a hash of its offset, so the 256 leaf checksums are
# 256 different numbers and not 256 copies of one.
def shard(+s: U32) -> U32:
  many(8192n, U32.shln(s, 13n), 0)

def par(k: Nat, +s: U32) -> U32:
  match k:
    case 0n:
      shard(s)
    case 1n++p:
      +q = U32.shln(1, p)
      a b = par(p, s) par(p, U32.add(s, q))
      tmix(a, b)

def main() -> U32:
  par(8n, 0)
