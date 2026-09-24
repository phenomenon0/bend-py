# Delta: DBSP's Z-sets, and the operators that update a derived view from a
# change instead of rebuilding it. A Z-set is a collection whose every element
# carries a signed integer weight: +1 is one copy, +2 is two, -1 is a retraction
# of one. Insert and delete stop being two different operations and become one
# addition, which is why every relational operator below can be fed a *delta*
# and answer with the delta of its own output.
#
# The algebra, and the one line of it that is not obvious:
#
#   map, filter, negate, aggregate   linear.   op(a + da) == op(a) + op(da),
#                                    so the delta alone is enough.
#   join                             BIlinear. (a+da) join (b+db) is
#                                    a join b + da join b + a join db + da join db,
#                                    so an incremental join must keep BOTH
#                                    inputs and produce THREE terms. Dropping
#                                    the third -- the one that is second order
#                                    in the change -- is the classic bug, and it
#                                    is not zero.
#   distinct                         neither. Weight 3 becomes 1 and weight 0
#                                    becomes no row at all, so no function of
#                                    the delta alone can answer. distinct_delta
#                                    takes the accumulated state and probes it.
#
# Consolidation is where power/radix.bend earns its place: a Z-set is
# consolidated by sorting on the element and summing the weights of each run,
# which is exactly reduce_by_key, and then dropping every row whose total
# reached zero. A retraction that exactly cancels an insert leaves NO ROW, not a
# row of weight zero -- the canonical form is what makes two Z-sets comparable.
#
# Weights are two's complement in a U32: +1 is 1, -1 is 4294967295. U32.add and
# U32.mul are the wrapping machine operations, so signed add and signed multiply
# are the unsigned ones unchanged and only compare and show have to know the
# sign. That keeps every column a Vec of U32, which is the only element type an
# Array can hold here, and it keeps the C lane out of the Array<F64> corruption
# that a float weight would have walked into.
#
# Written for the compiled lanes: every column is a Vec, every operator is one
# index loop or one call into Radix, and a join probes rather than scans -- the
# kept side is indexed once and a delta row costs one binary search plus its own
# matches. That is the whole claim of the lane, and tests/power/bench/delta.bend
# against tests/power/bench/delta_full.bend is where it is priced.
#
# Contract: consolidate before comparing, before show, before weight, and before
# distinct_delta's state argument -- those four want the canonical form. An
# operator that can grow its input takes a row allowance last and hands the
# remainder back first, the package convention from power/budget.bend.
import Base
import ./vec.bend as Vec
import ./scan.bend as Scan
import ./radix.bend as Radix
import ./postings.bend as Postings

# -- signed weights ----------------------------------------------------------

def sign() -> U32:
  2147483648

def wneg(w: U32) -> U32:
  U32.sub(0, w)

def wadd(a: U32, b: U32) -> U32:
  U32.add(a, b)

def wmul(a: U32, b: U32) -> U32:
  U32.mul(a, b)

def is_neg(w: U32) -> Bool:
  U32.is_ge(w, sign())

# strictly above zero: not zero and not negative
def is_pos(+w: U32) -> Bool:
  Bool.and(U32.is_ne(w, 0), U32.is_lt(w, sign()))

def wshow.if(+w: U32, neg: Bool) -> String:
  match neg:
    case True{}:
      "-" ++ U32.show(wneg(w))
    case False{}:
      "+" ++ U32.show(w)

def wshow(+w: U32) -> String:
  wshow.if(w, is_neg(w))

# -- the Z-set ---------------------------------------------------------------

# Two parallel columns, so a row is (e[i], w[i]). Both hold an Array, so ZSet's
# kind is Type: it has one owner, it cannot sit inside a Result or a Maybe, and
# a List of Z-sets is not expressible. Every operator below therefore hands its
# inputs back beside its answer rather than returning a Result, and a refusal
# rides as a field of the answer record instead of as a Fail arm.
type ZSet is Type:
  ZSet{e: Vec.Vec, w: Vec.Vec}

def empty() -> ZSet:
  ZSet{Vec.new(0), Vec.new(0)}

# push: one row appended, no consolidation. The un-canonical form is legal and
# is what every builder produces; consolidate is what makes it canonical.
def push(z: ZSet, +e: U32, +w: U32) -> ZSet:
  match z:
    case ZSet{es, ws}:
      ZSet{Vec.push(es, e), Vec.push(ws, w)}

def insert(z: ZSet, +e: U32) -> ZSet:
  push(z, e, 1)

def remove(z: ZSet, +e: U32) -> ZSet:
  push(z, e, wneg(1))

def of_lists(es: List<&2, U32>, ws: List<&2, U32>) -> ZSet:
  ZSet{Vec.from_list(es, Vec.new(0)), Vec.from_list(ws, Vec.new(0))}

def size.len(ws: Vec.Vec, r: Vec.Vec & U32) -> ZSet & U32:
  (es, n) = r
  (ZSet{es, ws}, n)

# size: how many rows, not how many copies -- a row of weight 3 counts once
def size(z: ZSet) -> ZSet & U32:
  match z:
    case ZSet{es, ws}:
      size.len(ws, Vec.len(es))

def total.put(+acc: U32, r: Vec.Vec & U32) -> Vec.Vec & U32:
  (w, x) = r
  (w, wadd(acc, x))

def total.add(+i: U32, r: Vec.Vec & U32) -> Vec.Vec & U32:
  (w, acc) = r
  total.put(acc, Vec.at(w, i))

def total.go(fuel: Nat, +i: U32, r: Vec.Vec & U32) -> Vec.Vec & U32:
  match fuel:
    case 0n:
      r
    case 1n++p:
      total.go(p, U32.inc(i), total.add(i, r))

def total.out(es: Vec.Vec, r: Vec.Vec & U32) -> ZSet & U32:
  (w, acc) = r
  (ZSet{es, w}, acc)

def total.len(es: Vec.Vec, r: Vec.Vec & U32) -> ZSet & U32:
  (w, n) = r
  total.out(es, total.go(U32.to_nat(n), 0, (w, 0)))

# total: the sum of every weight, signed. The cardinality of the multiset.
def total(z: ZSet) -> ZSet & U32:
  match z:
    case ZSet{es, ws}:
      total.len(es, Vec.len(ws))

# -- flags, and the two columns kept together --------------------------------

# One flag column drives both of a Z-set's columns through Scan.compact, which
# hands the flags back untouched -- that is what keeps the two rows aligned.
type Flg is Type:
  Flg{v: Vec.Vec, f: Vec.Vec}

def flg.nz(fs: Vec.Vec, r: Vec.Vec & U32) -> Flg:
  (v, x) = r
  Flg{v, Vec.push(fs, Bool.to_u32(U32.is_ne(x, 0)))}

def flg.nz.go(fuel: Nat, +i: U32, s: Flg) -> Flg:
  match fuel:
    case 0n:
      s
    case 1n++p:
      match s:
        case Flg{v, fs}:
          flg.nz.go(p, U32.inc(i), flg.nz(fs, Vec.at(v, i)))

def flg.nz.len(r: Vec.Vec & U32) -> Flg:
  (v, n) = r
  flg.nz.go(U32.to_nat(n), 0, Flg{v, Vec.new(0)})

def flags_nz(v: Vec.Vec) -> Flg:
  flg.nz.len(Vec.len(v))

def flg.p(~p: U32 -> Bool, fs: Vec.Vec, r: Vec.Vec & U32) -> Flg:
  (v, x) = r
  Flg{v, Vec.push(fs, Bool.to_u32(p(x)))}

def flg.p.go(~p: U32 -> Bool, fuel: Nat, +i: U32, s: Flg) -> Flg:
  match fuel:
    case 0n:
      s
    case 1n++q:
      match s:
        case Flg{v, fs}:
          flg.p.go(~p, q, U32.inc(i), flg.p(~p, fs, Vec.at(v, i)))

def flg.p.len(~p: U32 -> Bool, r: Vec.Vec & U32) -> Flg:
  (v, n) = r
  flg.p.go(~p, U32.to_nat(n), 0, Flg{v, Vec.new(0)})

def flags_p(~p: U32 -> Bool, v: Vec.Vec) -> Flg:
  flg.p.len(~p, Vec.len(v))

def pick.w(e2: Vec.Vec, r: Vec.Vec & Vec.Vec) -> ZSet:
  (w2, fs) = r
  ZSet{e2, w2}

def pick.e(w: Vec.Vec, r: Vec.Vec & Vec.Vec) -> ZSet:
  (e2, fs) = r
  pick.w(e2, Scan.compact(w, fs))

# pick: both columns kept where the flag is set, dense, in order, in place
def pick(e: Vec.Vec, w: Vec.Vec, fs: Vec.Vec) -> ZSet:
  pick.e(w, Scan.compact(e, fs))

def drop0.f(e: Vec.Vec, s: Flg) -> ZSet:
  match s:
    case Flg{w, fs}:
      pick(e, w, fs)

# drop0: a weight of zero leaves no row at all. This is the line that makes a
# retraction cancelling an insert vanish rather than sit there as a zero.
def drop0(e: Vec.Vec, w: Vec.Vec) -> ZSet:
  drop0.f(e, flags_nz(w))

# -- consolidation -----------------------------------------------------------

def cons.of(r: Vec.Vec & Vec.Vec) -> ZSet:
  (es, ws) = r
  drop0(es, ws)

# consolidate: the canonical form -- one row an element, elements ascending, no
# zero weight anywhere. Radix.reduce_by_key is the whole of it: the stable sort
# on the element column puts equal elements adjacent, and the run walk sums
# their weights. There is no second sort in this file.
def consolidate(z: ZSet) -> ZSet:
  match z:
    case ZSet{e, w}:
      cons.of(Radix.reduce_by_key(~wadd, e, w))

# -- the additive group ------------------------------------------------------

type Ap is Type:
  Ap{a: ZSet, b: ZSet}

def app.w(ae: Vec.Vec, aw: Vec.Vec, be: Vec.Vec, +e: U32, r: Vec.Vec & U32) -> Ap:
  (bw, w) = r
  Ap{ZSet{Vec.push(ae, e), Vec.push(aw, w)}, ZSet{be, bw}}

def app.e(ae: Vec.Vec, aw: Vec.Vec, bw: Vec.Vec, +i: U32, r: Vec.Vec & U32) -> Ap:
  (be, e) = r
  app.w(ae, aw, be, e, Vec.at(bw, i))

def app.step(a: ZSet, b: ZSet, +i: U32) -> Ap:
  match a b:
    case ZSet{ae, aw} ZSet{be, bw}:
      app.e(ae, aw, bw, i, Vec.at(be, i))

def app.go(fuel: Nat, +i: U32, s: Ap) -> Ap:
  match fuel:
    case 0n:
      s
    case 1n++p:
      match s:
        case Ap{a, b}:
          app.go(p, U32.inc(i), app.step(a, b, i))

def app.fin(s: Ap) -> ZSet:
  match s:
    case Ap{a, b}:
      a

def app.len(a: ZSet, b: ZSet, +n: U32) -> ZSet:
  app.fin(app.go(U32.to_nat(n), 0, Ap{a, b}))

def app.size(a: ZSet, r: ZSet & U32) -> ZSet:
  (b, n) = r
  app.len(a, b, n)

# append: b's rows onto a's, no consolidation. The Z-set sum before its
# canonical form, and what every operator that grows a collection actually does.
def append(a: ZSet, b: ZSet) -> ZSet:
  app.size(a, size(b))

# plus: the group operation. Weights of equal elements add, and an element whose
# weights cancel is gone.
def plus(a: ZSet, b: ZSet) -> ZSet:
  consolidate(append(a, b))

def neg.put(+i: U32, r: Vec.Vec & U32) -> Vec.Vec:
  (w, x) = r
  Vec.put(w, i, wneg(x))

def neg.go(fuel: Nat, +i: U32, w: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      w
    case 1n++p:
      neg.go(p, U32.inc(i), neg.put(i, Vec.at(w, i)))

def neg.len(r: Vec.Vec & U32) -> Vec.Vec:
  (w, n) = r
  neg.go(U32.to_nat(n), 0, w)

# negate: every weight flipped. A whole collection retracted in one operator.
def negate(z: ZSet) -> ZSet:
  match z:
    case ZSet{e, w}:
      ZSet{e, neg.len(Vec.len(w))}

def minus(a: ZSet, b: ZSet) -> ZSet:
  plus(a, negate(b))

# -- the linear operators ----------------------------------------------------

def map.put(~f: U32 -> U32, +i: U32, r: Vec.Vec & U32) -> Vec.Vec:
  (e, x) = r
  Vec.put(e, i, f(x))

def map.go(~f: U32 -> U32, fuel: Nat, +i: U32, e: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      e
    case 1n++p:
      map.go(~f, p, U32.inc(i), map.put(~f, i, Vec.at(e, i)))

def map.len(~f: U32 -> U32, r: Vec.Vec & U32) -> Vec.Vec:
  (e, n) = r
  map.go(~f, U32.to_nat(n), 0, e)

def map.z(~f: U32 -> U32, w: Vec.Vec, e: Vec.Vec) -> ZSet:
  ZSet{map.len(~f, Vec.len(e)), w}

# map: each element through f, its weight kept. Consolidated on the way out
# because f may send two elements to one, and then their weights must meet.
def map(~f: U32 -> U32, z: ZSet) -> ZSet:
  match z:
    case ZSet{e, w}:
      consolidate(map.z(~f, w, e))

def filter.f(w: Vec.Vec, s: Flg) -> ZSet:
  match s:
    case Flg{e, fs}:
      pick(e, w, fs)

# filter: the rows whose element p holds for, WEIGHTS UNCHANGED. A filter that
# rewrote the weight would not be linear and every incremental claim would fail.
def filter(~p: U32 -> Bool, z: ZSet) -> ZSet:
  match z:
    case ZSet{e, w}:
      filter.f(w, flags_p(~p, e))

type Agg is Type:
  Agg{e: Vec.Vec, w: Vec.Vec, k: Vec.Vec, v: Vec.Vec}

def agg.w(~key: U32 -> U32, ~val: U32 -> U32, e: Vec.Vec, ks: Vec.Vec, vs: Vec.Vec, +x: U32, r: Vec.Vec & U32) -> Agg:
  (w, wt) = r
  Agg{e, w, Vec.push(ks, key(x)), Vec.push(vs, wmul(wt, val(x)))}

def agg.step(~key: U32 -> U32, ~val: U32 -> U32, w: Vec.Vec, ks: Vec.Vec, vs: Vec.Vec, +i: U32, r: Vec.Vec & U32) -> Agg:
  (e, x) = r
  agg.w(~key, ~val, e, ks, vs, x, Vec.at(w, i))

def agg.go(~key: U32 -> U32, ~val: U32 -> U32, fuel: Nat, +i: U32, s: Agg) -> Agg:
  match fuel:
    case 0n:
      s
    case 1n++p:
      match s:
        case Agg{e, w, ks, vs}:
          agg.go(~key, ~val, p, U32.inc(i), agg.step(~key, ~val, w, ks, vs, i, Vec.at(e, i)))

def agg.fin(s: Agg) -> ZSet:
  match s:
    case Agg{e, w, ks, vs}:
      cons.of(Radix.reduce_by_key(~wadd, ks, vs))

def agg.len(~key: U32 -> U32, ~val: U32 -> U32, e: Vec.Vec, w: Vec.Vec, +n: U32) -> ZSet:
  agg.fin(agg.go(~key, ~val, U32.to_nat(n), 0, Agg{e, w, Vec.new(0), Vec.new(0)}))

def agg.size(~key: U32 -> U32, ~val: U32 -> U32, w: Vec.Vec, r: Vec.Vec & U32) -> ZSet:
  (e, n) = r
  agg.len(~key, ~val, e, w, n)

# aggregate_delta: the output element is the group key and the output WEIGHT is
# the aggregate, sum over the group of weight times val. A linear aggregate is
# a weight, which is the trick: fed a delta it answers with the delta of the
# aggregate per key, and a key whose aggregate did not move produces no row --
# drop0 again, the same rule as an element that cancelled.
def aggregate_delta(~key: U32 -> U32, ~val: U32 -> U32, z: ZSet) -> ZSet:
  match z:
    case ZSet{e, w}:
      agg.size(~key, ~val, w, Vec.len(e))

def one(x: U32) -> U32:
  1

# group: the count per key, which is aggregate_delta of the constant one
def group(~key: U32 -> U32, z: ZSet) -> ZSet:
  aggregate_delta(~key, ~one, z)

# -- the key-sorted index ----------------------------------------------------

# Ix: a Z-set's rows in key order, with the key column materialized. The column
# is what lets a probe be Postings.lower over a plain Vec and lets the run scan
# read a key without calling key() again. This is DBSP's trace, minus the
# multi-level merge: it is built once and probed many times, and that asymmetry
# is the entire reason an incremental join is cheap.
type Ix is Type:
  Ix{k: Vec.Vec, e: Vec.Vec, w: Vec.Vec}

def cp.put(d: Vec.Vec, r: Vec.Vec & U32) -> Vec.Vec & Vec.Vec:
  (s, x) = r
  (s, Vec.push(d, x))

def cp.step(+i: U32, sd: Vec.Vec & Vec.Vec) -> Vec.Vec & Vec.Vec:
  (s, d) = sd
  cp.put(d, Vec.at(s, i))

def cp.go(fuel: Nat, +i: U32, sd: Vec.Vec & Vec.Vec) -> Vec.Vec & Vec.Vec:
  match fuel:
    case 0n:
      sd
    case 1n++p:
      cp.go(p, U32.inc(i), cp.step(i, sd))

def cp.len(r: Vec.Vec & U32) -> Vec.Vec & Vec.Vec:
  (v, n) = r
  cp.go(U32.to_nat(n), 0, (v, Vec.new(0)))

# copy: the Vec, and a fresh duplicate of it. One owner means the second stable
# sort below needs its own key column, and this is the only place that copies.
def copy(v: Vec.Vec) -> Vec.Vec & Vec.Vec:
  cp.len(Vec.len(v))

def kc.put(~key: U32 -> U32, ks: Vec.Vec, r: Vec.Vec & U32) -> Vec.Vec & Vec.Vec:
  (e, x) = r
  (e, Vec.push(ks, key(x)))

def kc.step(~key: U32 -> U32, +i: U32, ek: Vec.Vec & Vec.Vec) -> Vec.Vec & Vec.Vec:
  (e, ks) = ek
  kc.put(~key, ks, Vec.at(e, i))

def kc.go(~key: U32 -> U32, fuel: Nat, +i: U32, ek: Vec.Vec & Vec.Vec) -> Vec.Vec & Vec.Vec:
  match fuel:
    case 0n:
      ek
    case 1n++p:
      kc.go(~key, p, U32.inc(i), kc.step(~key, i, ek))

def kc.len(~key: U32 -> U32, r: Vec.Vec & U32) -> Vec.Vec & Vec.Vec:
  (e, n) = r
  kc.go(~key, U32.to_nat(n), 0, (e, Vec.new(0)))

def keys(~key: U32 -> U32, e: Vec.Vec) -> Vec.Vec & Vec.Vec:
  kc.len(~key, Vec.len(e))

def ix.snd(k1: Vec.Vec, e2: Vec.Vec, r: Vec.Vec & Vec.Vec) -> Ix:
  (k2, w2) = r
  Ix{k1, e2, w2}

def ix.fst(k2: Vec.Vec, w: Vec.Vec, r: Vec.Vec & Vec.Vec) -> Ix:
  (k1, e2) = r
  ix.snd(k1, e2, Radix.sort_by_key(k2, w))

def ix.two(e: Vec.Vec, w: Vec.Vec, r: Vec.Vec & Vec.Vec) -> Ix:
  (k1, k2) = r
  ix.fst(k2, w, Radix.sort_by_key(k1, e))

def ix.k(w: Vec.Vec, r: Vec.Vec & Vec.Vec) -> Ix:
  (e, ks) = r
  ix.two(e, w, copy(ks))

# index: two stable radix sorts sharing one key column, copied once. Equal keys
# and a deterministic LSD pass mean both sorts move their payload by exactly the
# same permutation, so the three columns stay aligned without a third sort.
def index(~key: U32 -> U32, z: ZSet) -> Ix:
  match z:
    case ZSet{e, w}:
      ix.k(w, keys(~key, e))

def unindex(x: Ix) -> ZSet:
  match x:
    case Ix{k, e, w}:
      ZSet{e, w}

def ix_size.len(e: Vec.Vec, w: Vec.Vec, r: Vec.Vec & U32) -> Ix & U32:
  (k, n) = r
  (Ix{k, e, w}, n)

def ix_size(x: Ix) -> Ix & U32:
  match x:
    case Ix{k, e, w}:
      ix_size.len(e, w, Vec.len(k))

# -- the probe join ----------------------------------------------------------

# More keeps the run going, Ends says the key changed or the side ran out, and
# Dry says the row allowance refused a match that was there. Dry is the only one
# that survives into the next row: a refused join is refused whole.
type Run is Data:
  More{}
  Ends{}
  Dry{}

type Pr is Type:
  Pr{xs: Ix, ys: Ix, out: ZSet, left: U32, st: Run}

def elem(~f: U32 -> U32 -> U32, flip: Bool, ex: U32, ey: U32) -> U32:
  match flip:
    case True{}:
      f(ey, ex)
    case False{}:
      f(ex, ey)

# one matched pair: the elements through f, the weights multiplied. The product
# is what makes a join bilinear rather than linear.
def emit(~f: U32 -> U32 -> U32, flip: Bool, out: ZSet, ex: U32, wx: U32, ey: U32, wy: U32) -> ZSet:
  push(out, elem(~f, flip, ex, ey), wmul(wx, wy))

def run.hit(~f: U32 -> U32 -> U32, flip: Bool, xs: Ix, yk: Vec.Vec, ye: Vec.Vec, out: ZSet, +left: U32, ex: U32, wx: U32, ey: U32, r: Vec.Vec & U32) -> Pr:
  (yw, wy) = r
  Pr{xs, Ix{yk, ye, yw}, emit(~f, flip, out, ex, wx, ey, wy), U32.sub(left, 1), More{}}

def run.e(~f: U32 -> U32 -> U32, flip: Bool, xs: Ix, yk: Vec.Vec, yw: Vec.Vec, out: ZSet, left: U32, ex: U32, wx: U32, +j: U32, r: Vec.Vec & U32) -> Pr:
  (ye, ey) = r
  run.hit(~f, flip, xs, yk, ye, out, left, ex, wx, ey, Vec.at(yw, j))

def run.pay(~f: U32 -> U32 -> U32, flip: Bool, xs: Ix, yk: Vec.Vec, ye: Vec.Vec, yw: Vec.Vec, out: ZSet, left: U32, ex: U32, wx: U32, +j: U32, dry: Bool) -> Pr:
  match dry:
    case True{}:
      Pr{xs, Ix{yk, ye, yw}, out, left, Dry{}}
    case False{}:
      run.e(~f, flip, xs, yk, yw, out, left, ex, wx, j, Vec.at(ye, j))

def run.same(~f: U32 -> U32 -> U32, flip: Bool, xs: Ix, yk: Vec.Vec, ye: Vec.Vec, yw: Vec.Vec, out: ZSet, +left: U32, ex: U32, wx: U32, +j: U32, same: Bool) -> Pr:
  match same:
    case True{}:
      run.pay(~f, flip, xs, yk, ye, yw, out, left, ex, wx, j, U32.is_zero(left))
    case False{}:
      Pr{xs, Ix{yk, ye, yw}, out, left, Ends{}}

def run.cmp(~f: U32 -> U32 -> U32, flip: Bool, xs: Ix, ye: Vec.Vec, yw: Vec.Vec, out: ZSet, left: U32, +kx: U32, ex: U32, wx: U32, +j: U32, r: Vec.Vec & U32) -> Pr:
  (yk, ky) = r
  run.same(~f, flip, xs, yk, ye, yw, out, left, ex, wx, j, U32.is_eq(ky, kx))

def run.step(~f: U32 -> U32 -> U32, flip: Bool, xs: Ix, ys: Ix, out: ZSet, left: U32, +kx: U32, ex: U32, wx: U32, +j: U32) -> Pr:
  match ys:
    case Ix{yk, ye, yw}:
      run.cmp(~f, flip, xs, ye, yw, out, left, kx, ex, wx, j, Vec.at(yk, j))

# the run of ys sharing one key. The state's own field carries the stop, which
# is what lets one self-recursive def leave early: Bend has no mutual recursion,
# so "is the run still going" cannot live in a second def (postings' bs.go draws
# the same shape for the same reason).
def run.go(~f: U32 -> U32 -> U32, +flip: Bool, fuel: Nat, +j: U32, +kx: U32, +ex: U32, +wx: U32, s: Pr) -> Pr:
  match fuel:
    case 0n:
      s
    case 1n++p:
      match s:
        case Pr{xs, ys, out, left, st}:
          match st:
            case More{}:
              run.go(~f, flip, p, U32.inc(j), kx, ex, wx, run.step(~f, flip, xs, ys, out, left, kx, ex, wx, j))
            case Ends{}:
              Pr{xs, ys, out, left, Ends{}}
            case Dry{}:
              Pr{xs, ys, out, left, Dry{}}

def pr.at(~f: U32 -> U32 -> U32, flip: Bool, +n: U32, xs: Ix, ye: Vec.Vec, yw: Vec.Vec, out: ZSet, left: U32, +kx: U32, ex: U32, wx: U32, r: Vec.Vec & U32) -> Pr:
  (yk, +lo) = r
  run.go(~f, flip, U32.to_nat(U32.sub(n, lo)), lo, kx, ex, wx, Pr{xs, Ix{yk, ye, yw}, out, left, More{}})

def pr.find(~f: U32 -> U32 -> U32, flip: Bool, +n: U32, xs: Ix, ys: Ix, out: ZSet, left: U32, +kx: U32, ex: U32, wx: U32) -> Pr:
  match ys:
    case Ix{yk, ye, yw}:
      pr.at(~f, flip, n, xs, ye, yw, out, left, kx, ex, wx, Postings.lower(yk, kx, 0, n))

def pr.wx(~f: U32 -> U32 -> U32, flip: Bool, +n: U32, xk: Vec.Vec, xe: Vec.Vec, ys: Ix, out: ZSet, left: U32, +kx: U32, ex: U32, r: Vec.Vec & U32) -> Pr:
  (xw, wx) = r
  pr.find(~f, flip, n, Ix{xk, xe, xw}, ys, out, left, kx, ex, wx)

def pr.ex(~f: U32 -> U32 -> U32, flip: Bool, +i: U32, +n: U32, xk: Vec.Vec, xw: Vec.Vec, ys: Ix, out: ZSet, left: U32, +kx: U32, r: Vec.Vec & U32) -> Pr:
  (xe, ex) = r
  pr.wx(~f, flip, n, xk, xe, ys, out, left, kx, ex, Vec.at(xw, i))

def pr.kx(~f: U32 -> U32 -> U32, flip: Bool, +i: U32, +n: U32, xe: Vec.Vec, xw: Vec.Vec, ys: Ix, out: ZSet, left: U32, r: Vec.Vec & U32) -> Pr:
  (xk, kx) = r
  pr.ex(~f, flip, i, n, xk, xw, ys, out, left, kx, Vec.at(xe, i))

def pr.row(~f: U32 -> U32 -> U32, flip: Bool, +i: U32, +n: U32, xs: Ix, ys: Ix, out: ZSet, left: U32) -> Pr:
  match xs:
    case Ix{xk, xe, xw}:
      pr.kx(~f, flip, i, n, xe, xw, ys, out, left, Vec.at(xk, i))

def pr.go(~f: U32 -> U32 -> U32, +flip: Bool, fuel: Nat, +i: U32, +n: U32, s: Pr) -> Pr:
  match fuel:
    case 0n:
      s
    case 1n++p:
      match s:
        case Pr{xs, ys, out, left, st}:
          match st:
            case Dry{}:
              Pr{xs, ys, out, left, Dry{}}
            case More{}:
              pr.go(~f, flip, p, U32.inc(i), n, pr.row(~f, flip, i, n, xs, ys, out, left))
            case Ends{}:
              pr.go(~f, flip, p, U32.inc(i), n, pr.row(~f, flip, i, n, xs, ys, out, left))

def pr.ny(~f: U32 -> U32 -> U32, flip: Bool, xs: Ix, +nx: U32, out: ZSet, +limit: U32, r: Ix & U32) -> Pr:
  (ys, ny) = r
  pr.go(~f, flip, U32.to_nat(nx), 0, ny, Pr{xs, ys, out, limit, More{}})

def pr.nx(~f: U32 -> U32 -> U32, flip: Bool, ys: Ix, out: ZSet, +limit: U32, r: Ix & U32) -> Pr:
  (xs, nx) = r
  pr.ny(~f, flip, xs, nx, out, limit, ix_size(ys))

# probe: for every row of xs, the run of ys with the same key. One binary search
# a row plus its own matches -- NOT a scan of ys, which is what makes a small
# delta against a large kept side cost the delta and not the side. The output is
# appended to `out`, so the three terms of an incremental join accumulate into
# one Z-set and are consolidated once.
def probe(~f: U32 -> U32 -> U32, flip: Bool, xs: Ix, ys: Ix, out: ZSet, +limit: U32) -> Pr:
  pr.nx(~f, flip, ys, out, limit, ix_size(xs))

# -- join --------------------------------------------------------------------

# The answer record, and the budget convention bent exactly as far as the kinds
# force. power/budget.bend's rule is Result<Err, (left, value)>, remainder
# first; an Ix and a ZSet hold arrays, so their kind is Type and neither can sit
# inside a Result. So the remainder is still first and the refusal is still
# explicit -- `ok` False means the row allowance ran out and `out` is short --
# but they ride as fields rather than as arms. power/json.bend deviated the same
# way for the same reason (power-5 recorded it): it is the payload that forces
# it, never the allowance.
type Jn is Type:
  Jn{left: U32, a: Ix, b: Ix, out: ZSet, ok: Bool}

def jn.ok(st: Run) -> Bool:
  match st:
    case More{}:
      True{}
    case Ends{}:
      True{}
    case Dry{}:
      False{}

def jn.of(s: Pr) -> Jn:
  match s:
    case Pr{xs, ys, out, left, st}:
      Jn{left, xs, ys, consolidate(out), jn.ok(st)}

# join_ix: two indexed Z-sets, every pair of rows whose keys agree. The
# allowance counts emitted pairs BEFORE consolidation, which is the number that
# can blow up: n rows against m rows of one key is n*m pairs and one output row.
def join_ix(~f: U32 -> U32 -> U32, a: Ix, b: Ix, +limit: U32) -> Jn:
  jn.of(probe(~f, False{}, a, b, empty(), limit))

def join.ix(~key: U32 -> U32, ~f: U32 -> U32 -> U32, a: ZSet, b: ZSet, +limit: U32) -> Jn:
  join_ix(~f, index(~key, a), index(~key, b), limit)

# join: the whole thing from scratch -- index both sides, then probe. This is
# the recompute path, and the one an incremental step must agree with.
def join(~key: U32 -> U32, ~f: U32 -> U32 -> U32, a: ZSet, b: ZSet, +limit: U32) -> Jn:
  join.ix(~key, ~f, a, b, limit)

def jd.fin(a: Ix, b: Ix, out: ZSet, +left: U32, ok: Bool) -> Jn:
  Jn{left, a, b, consolidate(out), ok}

# the last probe hands da and db back and they are dropped here: an incremental
# step consumes its change, and what survives is the kept state plus the output.
def jd.t3(a: Ix, b: Ix, s1: Run, s2: Run, r: Pr) -> Jn:
  match r:
    case Pr{da, db, out, left, st}:
      jd.fin(a, b, out, left, Bool.and(jn.ok(s1), Bool.and(jn.ok(s2), jn.ok(st))))

def jd.t2(~f: U32 -> U32 -> U32, b: Ix, da: Ix, s1: Run, r: Pr) -> Jn:
  match r:
    case Pr{db, a, out, left, st}:
      jd.t3(a, b, s1, st, probe(~f, False{}, da, db, out, left))

def jd.t1(~f: U32 -> U32 -> U32, a: Ix, db: Ix, r: Pr) -> Jn:
  match r:
    case Pr{da, b, out, left, st}:
      jd.t2(~f, b, da, st, probe(~f, True{}, db, a, out, left))

# join_delta: DBSP's bilinear rule, spelled out. (a + da) join (b + db) differs
# from a join b by exactly three terms:
#
#     da join b   +   a join db   +   da join db
#
# The first two are each proportional to one delta and the kept side's matches.
# The third is second order in the change -- small, and NOT zero: two rows that
# arrive in the same step and join each other appear in no other term, because
# neither of them is in a or b yet. A join that drops it is the classic DBSP
# bug, and the fixture has a case whose whole content is that one row.
#
# All three probes accumulate into ONE output Z-set and share ONE allowance, so
# the result is consolidated once and a refusal refuses the step, not a term.
#
# a and b come back untouched: the caller owns when the state absorbs the
# change. That is deliberate, and it is the asymmetry the lane is built on --
# absorbing costs the side, and DBSP amortizes it across many steps.
def join_delta(~f: U32 -> U32 -> U32, a: Ix, b: Ix, da: Ix, db: Ix, +limit: U32) -> Jn:
  jd.t1(~f, a, db, probe(~f, False{}, da, b, empty(), limit))

def absorb.z(~key: U32 -> U32, a: ZSet, d: ZSet) -> Ix:
  index(~key, append(a, d))

# absorb: the kept side takes the change. O(the side), which is why it is its
# own door and not part of join_delta.
def absorb(~key: U32 -> U32, a: Ix, d: Ix) -> Ix:
  absorb.z(~key, unindex(a), unindex(d))

# -- distinct ----------------------------------------------------------------

def ones.go(fuel: Nat, +i: U32, w: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      w
    case 1n++p:
      ones.go(p, U32.inc(i), Vec.put(w, i, 1))

def ones.len(r: Vec.Vec & U32) -> Vec.Vec:
  (w, n) = r
  ones.go(U32.to_nat(n), 0, w)

def dist.set(z: ZSet) -> ZSet:
  match z:
    case ZSet{e, w}:
      ZSet{e, ones.len(Vec.len(w))}

# a template predicate may not carry a use mark, and is_pos reads its argument
# twice, so the one passed to flags_p is this wrapper
def dist.p(w: U32) -> Bool:
  is_pos(w)

def dist.f(e: Vec.Vec, s: Flg) -> ZSet:
  match s:
    case Flg{w, fs}:
      dist.set(pick(e, w, fs))

# the flags are read off the WEIGHT column, not the element column: presence is
# a property of the weight. drop0 is the same shape with a different predicate.
def dist.pos(z: ZSet) -> ZSet:
  match z:
    case ZSet{e, w}:
      dist.f(e, flags_p(~dist.p, w))

# distinct: the set behind the multiset. Every element whose accumulated weight
# is strictly positive gets weight exactly 1; everything else is gone. NOT
# linear -- 1 + 1 + 1 is 3 copies but one element, and 1 + (-1) is no element --
# which is why this one takes the whole collection and distinct_delta below
# takes the state.
def distinct(z: ZSet) -> ZSet:
  dist.pos(consolidate(z))

type Dd is Type:
  Dd{st: ZSet, d: ZSet, out: ZSet}

def dd.if(out: ZSet, +e: U32, was: Bool, now: Bool) -> ZSet:
  match was now:
    case False{} True{}:
      push(out, e, 1)
    case True{} False{}:
      push(out, e, wneg(1))
    case True{} True{}:
      out
    case False{} False{}:
      out

# the row the state contributes: +1 if this element just became present, -1 if
# it just left, and nothing at all if its presence did not change. That is the
# honest incremental distinct: it is a function of (old weight, delta weight),
# and the old weight is not in the delta.
def dd.emit(out: ZSet, +e: U32, +old: U32, +dw: U32) -> ZSet:
  dd.if(out, e, is_pos(old), is_pos(wadd(old, dw)))

def dd.got(se: Vec.Vec, d: ZSet, out: ZSet, +e: U32, +dw: U32, r: Vec.Vec & U32) -> Dd:
  (sw, old) = r
  Dd{ZSet{se, sw}, d, dd.emit(out, e, old, dw)}

def dd.hit(se: Vec.Vec, sw: Vec.Vec, d: ZSet, out: ZSet, +e: U32, +dw: U32, +i: U32, there: Bool) -> Dd:
  match there:
    case True{}:
      dd.got(se, d, out, e, dw, Vec.at(sw, i))
    case False{}:
      Dd{ZSet{se, sw}, d, dd.emit(out, e, 0, dw)}

def dd.eq(sw: Vec.Vec, d: ZSet, out: ZSet, +e: U32, +dw: U32, +i: U32, r: Vec.Vec & U32) -> Dd:
  (se, y) = r
  dd.hit(se, sw, d, out, e, dw, i, U32.is_eq(y, e))

def dd.in(sw: Vec.Vec, d: ZSet, out: ZSet, +e: U32, +dw: U32, +i: U32, +n: U32, se: Vec.Vec) -> Dd:
  dd.eq(sw, d, out, e, dw, i, Vec.at(se, U32.min(i, U32.sub(n, 1))))

def dd.bound(sw: Vec.Vec, d: ZSet, out: ZSet, +e: U32, +dw: U32, +n: U32, inside: Bool, +i: U32, se: Vec.Vec) -> Dd:
  match inside:
    case True{}:
      dd.in(sw, d, out, e, dw, i, n, se)
    case False{}:
      Dd{ZSet{se, sw}, d, dd.emit(out, e, 0, dw)}

def dd.lo(sw: Vec.Vec, d: ZSet, out: ZSet, +e: U32, +dw: U32, +n: U32, r: Vec.Vec & U32) -> Dd:
  (se, +i) = r
  dd.bound(sw, d, out, e, dw, n, U32.is_lt(i, n), i, se)

def dd.seek(st: ZSet, d: ZSet, out: ZSet, +e: U32, +dw: U32, +n: U32) -> Dd:
  match st:
    case ZSet{se, sw}:
      dd.lo(sw, d, out, e, dw, n, Postings.lower(se, e, 0, n))

def dd.w(st: ZSet, de: Vec.Vec, out: ZSet, +e: U32, +n: U32, r: Vec.Vec & U32) -> Dd:
  (dw, x) = r
  dd.seek(st, ZSet{de, dw}, out, e, x, n)

def dd.e(st: ZSet, dw: Vec.Vec, out: ZSet, +i: U32, +n: U32, r: Vec.Vec & U32) -> Dd:
  (de, e) = r
  dd.w(st, de, out, e, n, Vec.at(dw, i))

def dd.step(st: ZSet, d: ZSet, out: ZSet, +i: U32, +n: U32) -> Dd:
  match d:
    case ZSet{de, dw}:
      dd.e(st, dw, out, i, n, Vec.at(de, i))

def dd.go(fuel: Nat, +i: U32, +n: U32, s: Dd) -> Dd:
  match fuel:
    case 0n:
      s
    case 1n++p:
      match s:
        case Dd{st, d, out}:
          dd.go(p, U32.inc(i), n, dd.step(st, d, out, i, n))

def dd.fin(s: Dd) -> ZSet & ZSet:
  match s:
    case Dd{st, d, out}:
      (st, consolidate(out))

def dd.len(st: ZSet, +n: U32, r: ZSet & U32) -> ZSet & ZSet:
  (d, m) = r
  dd.fin(dd.go(U32.to_nat(m), 0, n, Dd{st, d, empty()}))

def dd.n(d: ZSet, r: ZSet & U32) -> ZSet & ZSet:
  (st, n) = r
  dd.len(st, n, size(consolidate(d)))

# distinct_delta: the change to distinct(state) caused by adding d to state.
# The state must be consolidated -- its elements ascending is what makes the
# lookup a binary search. Every element the delta touches costs one search of
# the state and nothing else, so this is proportional to the change even though
# the operator it differentiates is not linear at all.
#
# The state comes back unchanged: the caller adds d to it when it wants to, the
# same split join_delta draws.
def distinct_delta(st: ZSet, d: ZSet) -> ZSet & ZSet:
  dd.n(d, size(st))

# -- lookup and text ---------------------------------------------------------

def wt.out(e: Vec.Vec, r: Vec.Vec & U32) -> ZSet & U32:
  (w, x) = r
  (ZSet{e, w}, x)

def wt.hit(e: Vec.Vec, w: Vec.Vec, +i: U32, there: Bool) -> ZSet & U32:
  match there:
    case True{}:
      wt.out(e, Vec.at(w, i))
    case False{}:
      (ZSet{e, w}, 0)

def wt.eq(w: Vec.Vec, +x: U32, +i: U32, r: Vec.Vec & U32) -> ZSet & U32:
  (e, y) = r
  wt.hit(e, w, i, U32.is_eq(y, x))

def wt.bound(e: Vec.Vec, w: Vec.Vec, +x: U32, +i: U32, +n: U32, inside: Bool) -> ZSet & U32:
  match inside:
    case True{}:
      wt.eq(w, x, i, Vec.at(e, U32.min(i, U32.sub(n, 1))))
    case False{}:
      (ZSet{e, w}, 0)

def wt.lo(w: Vec.Vec, +x: U32, +n: U32, r: Vec.Vec & U32) -> ZSet & U32:
  (e, +i) = r
  wt.bound(e, w, x, i, n, U32.is_lt(i, n))

def wt.n(e: Vec.Vec, w: Vec.Vec, +x: U32, +n: U32) -> ZSet & U32:
  wt.lo(w, x, n, Postings.lower(e, x, 0, n))

def wt.len(w: Vec.Vec, +x: U32, r: Vec.Vec & U32) -> ZSet & U32:
  (e, n) = r
  wt.n(e, w, x, n)

# weight: what an element weighs, 0 if it is not there -- and 0 is exactly what
# a cancelled element weighs, which is the same answer for the same reason.
# One binary search; the Z-set must be consolidated.
def weight(z: ZSet, +x: U32) -> ZSet & U32:
  match z:
    case ZSet{e, w}:
      wt.len(w, x, Vec.len(e))

type Sh is Type:
  Sh{e: Vec.Vec, w: Vec.Vec, xs: List<&2, String>}

def sh.put(e: Vec.Vec, acc: List<&2, String>, +x: U32, r: Vec.Vec & U32) -> Sh:
  (w, y) = r
  Sh{e, w, Con{U32.show(x) ++ ":" ++ wshow(y), acc}}

def sh.step(w: Vec.Vec, acc: List<&2, String>, +k: U32, r: Vec.Vec & U32) -> Sh:
  (e, x) = r
  sh.put(e, acc, x, Vec.at(w, k))

def sh.go(i: Nat, s: Sh) -> Sh:
  match i:
    case 0n:
      s
    case 1n++p:
      match s:
        case Sh{e, w, acc}:
          +k = U32.from_nat(p)
          sh.go(p, sh.step(w, acc, k, Vec.at(e, k)))

def sh.fin(s: Sh) -> ZSet & String:
  match s:
    case Sh{e, w, xs}:
      (ZSet{e, w}, "{" ++ String.join(xs, " ") ++ "}")

def sh.len(w: Vec.Vec, r: Vec.Vec & U32) -> ZSet & String:
  (e, n) = r
  sh.fin(sh.go(U32.to_nat(n), Sh{e, w, []}))

# show: "{e:+w e:-w}", ascending by element. A zero weight never appears in it
# because a consolidated Z-set has no zero row to print.
def show(z: ZSet) -> ZSet & String:
  match z:
    case ZSet{e, w}:
      sh.len(w, Vec.len(e))
