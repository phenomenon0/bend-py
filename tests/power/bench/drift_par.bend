# drift, forked: the same 33,554,432 samples as drift.bend, but summarised
# rather than detected -- 2^8 leaves of 131,072, each folding its own range into
# a Welford accumulator, joined back up the tree by Chan's merge.
#
# This bench exists because the merge is the associative half of the lane. The
# detector cannot fork; the accumulator can, and a fork is only worth having if
# the answer does not depend on the schedule. It does not, and the reason is
# narrow enough to be worth stating: F64 addition is NOT associative, so a tree
# merge and a left fold give different last bits. What makes the checksum stable
# is that the tree's SHAPE is written into this program -- par(8n, ...) always
# splits at the same indices -- so 1 thread and 16 threads walk the same tree in
# the same order and land on identical bits. The schedule chooses when, never
# what. twin_drift_par.c reproduces that tree; twin_drift.c's left fold gives a
# different number on purpose, which is why this bench has its own twin.
import Base
import ../../../power/drift.bend as D

def h.fin2(+v: U32) -> U32:
  U32.xor(v, U32.shrn(v, 13n))

def h.fin(+u: U32) -> U32:
  h.fin2(U32.mul(U32.xor(u, U32.shrn(u, 15n)), 2246822519))

def h(+p: U32) -> U32:
  h.fin(U32.mul(U32.inc(p), 2654435761))

def nz(+p: U32) -> F64:
  F64.div(F64.sub(U32.to_f64(U32.shrn(h(p), 19n)), 4096.0d), 2048.0d)

def sq(+p: U32) -> F64:
  F64.add(F64.mul(3.0d, U32.to_f64(U32.and(U32.shrn(p, 16n), 1))), nz(p))

def rot7(+v: U32) -> U32:
  U32.or(U32.shln(v, 7n), U32.shrn(v, 25n))

def mix(+acc: U32, +x: U32) -> U32:
  rot7(U32.add(U32.mul(acc, 31), x))

def qu(+x: F64) -> U32:
  F64.to_u32(F64.floor(F64.add(F64.mul(F64.add(x, 8.0d), 1048576.0d), 0.5d)))

def leaf(i: Nat, +p: U32, s: D.Stat) -> D.Stat:
  match i:
    case 0n:
      s
    case 1n++k:
      leaf(k, U32.inc(p), D.push(s, sq(p)))

def par(d: Nat, +lo: U32, +n: U32) -> D.Stat:
  match d:
    case 0n:
      leaf(U32.to_nat(n), lo, D.empty())
    case 1n++k:
      +hf = U32.shr(n)
      a b = par(k, lo, hf) par(k, U32.add(lo, hf), hf)
      D.merge(a, b)

# the count, the mean and the variance all enter the checksum: a merge that
# forgot to weight by count moves the mean, and one that dropped the correction
# term moves only the variance, so both have to be in the number
def out(+s: D.Stat) -> U32:
  mix(mix(D.count(s), qu(D.mean(s))), qu(D.variance(s)))

def main() -> U32:
  out(par(8n, 0, 33554432))
