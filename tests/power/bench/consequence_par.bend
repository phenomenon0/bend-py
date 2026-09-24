# consequence, forked: 2^8 blocks of 8,000 readings, each previewed and
# collapsed in its own leaf. One shared Array cannot fork (a fork copies both
# halves, docs/omen/lanes/power-1.md), so the block is leaf-private -- and a
# clarifier is leaf-private by nature: readings of one request never need to be
# grouped against readings of another, so this is the real shape, not a
# benchmark's convenience.
import Base
import ../../../power/vec.bend as Vec
import ../../../power/consequence.bend as Conseq

def pat(+j: U32) -> U32:
  U32.mod(j, 977)

def tlen(j: U32) -> U32:
  U32.add(U32.and(pat(j), 7), 1)

def act(+p: U32, i: U32) -> U32:
  U32.xor(U32.mul(U32.inc(p), 2654435761), U32.mul(i, 40503))

def inner(fuel: Nat, +p: U32, +i: U32, v: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      v
    case 1n++q:
      inner(q, p, U32.inc(i), Vec.push(v, act(p, i)))

def outer(fuel: Nat, +j: U32, v: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      v
    case 1n++q:
      outer(q, U32.inc(j), inner(U32.to_nat(tlen(j)), pat(j), 0, v))

def lfill(fuel: Nat, +j: U32, v: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      v
    case 1n++q:
      lfill(q, U32.inc(j), Vec.push(v, tlen(j)))

def hash(acc: U32, r: Vec.Vec & U32) -> Vec.Vec & U32:
  (v, x) = r
  (v, U32.add(U32.mul(acc, 31), x))

def fold.at(+i: U32, va: Vec.Vec & U32) -> Vec.Vec & U32:
  (v, acc) = va
  hash(acc, Vec.at(v, i))

def fold.go(fuel: Nat, +i: U32, va: Vec.Vec & U32) -> Vec.Vec & U32:
  match fuel:
    case 0n:
      va
    case 1n++p:
      fold.go(p, U32.inc(i), fold.at(i, va))

def snd(va: Vec.Vec & U32) -> U32:
  (v, acc) = va
  acc

def fold.n(acc: U32, r: Vec.Vec & U32) -> U32:
  (v, n) = r
  snd(fold.go(U32.to_nat(n), 0, (v, acc)))

def sum3(g: Conseq.Groups) -> U32:
  match g:
    case Conseq.Groups{keys, reps, cnts}:
      fold.n(fold.n(fold.n(0, Vec.len(keys)), Vec.len(reps)), Vec.len(cnts))

# the readings of one request: numbered lo.. globally, but collapsed against
# each other alone, so the representatives a block reports are its own 0..7999
def block(+lo: U32) -> U32:
  sum3(Conseq.collapse_traces(2166136261, outer(8000n, lo, Vec.new(0)), lfill(8000n, lo, Vec.new(0))))

def par(d: Nat, +lo: U32, +n: U32) -> U32:
  match d:
    case 0n:
      block(lo)
    case 1n++p:
      +h = U32.shr(n)
      a b = par(p, lo, h) par(p, U32.add(lo, h), h)
      U32.add(U32.mul(a, 31), b)

def main() -> U32:
  par(8n, 0, 2048000)
