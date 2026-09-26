# delta_full, the recompute: the same 128 updates as delta.bend, answered the way
# a system with no delta operators has to answer them -- rebuild both relations,
# join them whole, join the changed ones whole, subtract. Every step pays the
# collection; delta.bend's step pays the change.
#
# The two files print the SAME checksum. That is not a convenience: it is
# bilinearity, which says
#
#   (a + da) join (b + db) - a join b == da join b + a join db + da join db
#
# and the row this file computes on the left is the row delta.bend computes on
# the right. So the pair is a bench and an equivalence test at once -- if they
# ever disagreed at 128 steps, the three-term expansion would be wrong.
#
# Everything above the main loop is byte-for-byte delta.bend's, because the two
# have to start from identical data or the ratio measures the data instead.
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

def emk(+x: U32) -> U32:
  U32.add(U32.shln(U32.and(x, 127), 8n), U32.and(U32.shrn(x, 8n), 255))

def el(+p: U32) -> U32:
  emk(h(p))

def wt(+p: U32) -> U32:
  U32.add(1, U32.and(h(U32.add(p, 7777)), 1))

def dwt(+p: U32) -> U32:
  U32.sub(1, U32.mul(2, U32.and(h(U32.add(p, 31337)), 1)))

def kf(x: U32) -> U32:
  U32.shrn(x, 8n)

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

# minus consolidates, so what arrives here is already canonical -- the same
# contract delta.bend's sum states
def sum(+acc: U32, z: Delta.ZSet) -> U32:
  match z:
    case Delta.ZSet{e, w}:
      ck.len(w, acc, Vec.len(e))

def jz(j: Delta.Jn) -> Delta.ZSet:
  match j:
    case Delta.Jn{left, a, b, out, ok}:
      out

def fl.sub(+acc: U32, base: Delta.ZSet, now: Delta.ZSet) -> U32:
  sum(acc, Delta.minus(now, base))

# both relations rebuilt, both joins run whole, one subtraction. The two joins
# differ by 8 rows a side out of 9,216 and the recompute has no way to know it.
def fl.step(+acc: U32, +p: U32) -> U32:
  fl.sub(acc, jz(Delta.join(~kf, ~jf, mk(0, na()), mk(bb(), nb()), lim())),
    jz(Delta.join(~kf, ~jf, Delta.plus(mk(0, na()), dk(p, nd())),
      Delta.plus(mk(bb(), nb()), dk(U32.add(p, nd()), nd())), lim())))

def fl.go(fuel: Nat, +p: U32, +acc: U32) -> U32:
  match fuel:
    case 0n:
      acc
    case 1n++q:
      fl.go(q, U32.add(p, 16), fl.step(acc, p))

def main() -> U32:
  fl.go(128n, bd(), 0)
