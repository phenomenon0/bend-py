# delta, incremental: one kept join of 1,024 rows against 8,192 rows over 128
# keys, indexed ONCE, then 128 updates of 8 rows a side. Each update asks for the
# delta of the output and gets it out of DBSP's three bilinear terms --
# da join b, a join db, da join db -- so a step costs the change and a binary
# search into the kept side, never a walk of it.
#
# delta_full.bend is the same 128 updates answered by recomputing both joins from
# scratch and subtracting, which is what a non-incremental system does. The two
# print the SAME checksum, because bilinearity says they must, and the ratio of
# their times is the only number this lane is really about.
#
# There is no fork in this file. Consolidation is Radix.reduce_by_key, and
# power/radix.bend does not fork on purpose: an Array pays a full copy per fork
# level (power-1) and a parallel call anywhere taxes the whole program about 3x
# (power-3), which counting an add cannot repay. So the 1T and 16T columns here
# are the same run twice, and delta has no _par twin.
import Base
import ../../../power/vec.bend as Vec
import ../../../power/delta.bend as Delta

def na() -> U32:
  1024

def nb() -> U32:
  8192

def nd() -> U32:
  8

def bb() -> U32:
  1000000000

def bd() -> U32:
  2000000000

def lim() -> U32:
  4294967295

def h(+p: U32) -> U32:
  U32.xor(U32.mul(U32.inc(p), 2654435761), U32.shrn(p, 3n))

# the element: 7 bits of key in the high half, one byte of payload in the low,
# so 8,192 rows land 64 to a key and one delta row meets 64 matches
def emk(+x: U32) -> U32:
  U32.add(U32.shln(U32.and(x, 127), 8n), U32.and(U32.shrn(x, 8n), 255))

def el(+p: U32) -> U32:
  emk(h(p))

def wt(+p: U32) -> U32:
  U32.add(1, U32.and(h(U32.add(p, 7777)), 1))

# a delta weight is +1 or -1: half of every change is a retraction, which is
# what makes the cancelling path hot rather than decorative
def dwt(+p: U32) -> U32:
  U32.sub(1, U32.mul(2, U32.and(h(U32.add(p, 31337)), 1)))

def kf(x: U32) -> U32:
  U32.shrn(x, 8n)

# asymmetric on purpose: jf(x, y) is not jf(y, x), so a term that walks its two
# sides the wrong way round changes the checksum and not only the timing
def jf(x: U32, y: U32) -> U32:
  U32.add(U32.shln(x, 8n), U32.and(y, 255))

def mk.go(fuel: Nat, +p: U32, z: Delta.ZSet) -> Delta.ZSet:
  match fuel:
    case 0n:
      z
    case 1n++q:
      mk.go(q, U32.inc(p), Delta.push(z, el(p), wt(p)))

def mk(+base: U32, +n: U32) -> Delta.ZSet:
  mk.go(U32.to_nat(n), base, Delta.empty())

def dk.go(fuel: Nat, +p: U32, z: Delta.ZSet) -> Delta.ZSet:
  match fuel:
    case 0n:
      z
    case 1n++q:
      dk.go(q, U32.inc(p), Delta.push(z, el(p), dwt(p)))

def dk(+base: U32, +n: U32) -> Delta.ZSet:
  dk.go(U32.to_nat(n), base, Delta.empty())

def rot7(+v: U32) -> U32:
  U32.or(U32.shln(v, 7n), U32.shrn(v, 25n))

def mix(+acc: U32, +x: U32) -> U32:
  rot7(U32.add(U32.mul(acc, 31), x))

# the checksum folds the row COUNT and then every (element, weight) of the
# consolidated delta, in ascending element order. The count is in there to catch
# a consolidation that kept a zero-weight row -- but measured, it does not: at
# these sizes the three terms never cancel to exactly zero, so mutating drop0
# away leaves this number unchanged. tests/power/delta.bend is what pins that
# rule; this file prices the algorithm.
type Ck is Type:
  Ck{e: Vec.Vec, w: Vec.Vec, acc: U32}

def ck.w(e: Vec.Vec, +acc: U32, +x: U32, r: Vec.Vec & U32) -> Ck:
  (w, y) = r
  Ck{e, w, mix(mix(acc, x), y)}

def ck.step(w: Vec.Vec, +acc: U32, +i: U32, r: Vec.Vec & U32) -> Ck:
  (e, x) = r
  ck.w(e, acc, x, Vec.at(w, i))

def ck.go(fuel: Nat, +i: U32, s: Ck) -> Ck:
  match fuel:
    case 0n:
      s
    case 1n++p:
      match s:
        case Ck{e, w, acc}:
          ck.go(p, U32.inc(i), ck.step(w, acc, i, Vec.at(e, i)))

def ck.fin(s: Ck) -> U32:
  match s:
    case Ck{e, w, acc}:
      acc

def ck.len(w: Vec.Vec, +acc: U32, r: Vec.Vec & U32) -> U32:
  (e, +n) = r
  ck.fin(ck.go(U32.to_nat(n), 0, Ck{e, w, mix(acc, n)}))

# the Z-set must already be canonical: join_delta consolidates its own output,
# and a second pass here would cost a sort to learn nothing
def sum(+acc: U32, z: Delta.ZSet) -> U32:
  match z:
    case Delta.ZSet{e, w}:
      ck.len(w, acc, Vec.len(e))

# the kept state, threaded: join_delta hands both indexes back, so a and b are
# built once outside the loop and never rebuilt inside it. That is the whole
# asymmetry -- the side is indexed once and probed 64 times.
type St is Type:
  St{a: Delta.Ix, b: Delta.Ix, acc: U32}

def st.one(+acc: U32, j: Delta.Jn) -> St:
  match j:
    case Delta.Jn{left, a, b, out, ok}:
      St{a, b, sum(acc, out)}

def st.step(a: Delta.Ix, b: Delta.Ix, +acc: U32, +p: U32) -> St:
  st.one(acc, Delta.join_delta(~jf, a, b, Delta.index(~kf, dk(p, nd())),
    Delta.index(~kf, dk(U32.add(p, nd()), nd())), lim()))

def st.go(fuel: Nat, +p: U32, s: St) -> St:
  match fuel:
    case 0n:
      s
    case 1n++q:
      match s:
        case St{a, b, acc}:
          st.go(q, U32.add(p, 16), st.step(a, b, acc, p))

def st.out(s: St) -> U32:
  match s:
    case St{a, b, acc}:
      acc

def main() -> U32:
  st.out(st.go(128n, bd(), St{Delta.index(~kf, mk(0, na())),
    Delta.index(~kf, mk(bb(), nb())), 0}))
