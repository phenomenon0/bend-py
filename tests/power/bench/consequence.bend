# 2,000,000 readings previewed, collapsed to their distinct consequences. The
# readings draw from a pool of 977 patterns, so the answer is ~977 groups of
# ~2,048 readings each -- the shape a clarifier actually sees, not an all-distinct
# input the sort would find easy. Trace lengths run 1..8, so the gather walks a
# real cursor rather than a stride, and the flat block is ~9,000,000 actions.
# The checksum folds all three answer columns (digest, representative, count)
# with a * 31 + x, so a wrong digest, a wrong representative and a wrong tally
# each move it.
import Base
import ../../../power/vec.bend as Vec
import ../../../power/consequence.bend as Conseq

def pat(+j: U32) -> U32:
  U32.mod(j, 977)

def tlen(j: U32) -> U32:
  U32.add(U32.and(pat(j), 7), 1)

def act(+p: U32, i: U32) -> U32:
  U32.xor(U32.mul(U32.inc(p), 2654435761), U32.mul(i, 40503))

# one trace: tlen(j) actions of pattern pat(j), pushed onto the flat block
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

def main() -> U32:
  sum3(Conseq.collapse_traces(2166136261, outer(2000000n, 0, Vec.new(0)), lfill(2000000n, 0, Vec.new(0))))
