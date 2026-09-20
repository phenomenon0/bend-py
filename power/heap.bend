# Heap: a binary min-heap of (key, val) entries, ordered by key and then by val,
# so equal keys leave in one fixed order whatever order they came in: give val an
# insertion index or an id and ties are settled. CPython's heapq over tuples is
# the same order and is the oracle.
#
# Written for the compiled lanes: one Vec, entry i in cells 2i and 2i+1, so a
# sift touches one flat block; both sifts carry the moving entry and write each
# level once (the hole, not a swap); the loop leaves at the first level that is
# already in order; 32 levels of fuel is every heap a U32 indexes.
import Base
import ./vec.bend as Vec

type Heap is Type:
  Heap{n: U32, cells: Vec.Vec}

type Entry is Data:
  Entry{key: U32, val: U32}

def new() -> Heap:
  Heap{0, Vec.new(0)}

def len(h: Heap) -> Heap & U32:
  match h:
    case Heap{+n, v}:
      (Heap{n, v}, n)

# (k1, x1) < (k2, x2)
def less(+k1: U32, x1: U32, +k2: U32, x2: U32) -> Bool:
  Bool.or(U32.is_lt(k1, k2), Bool.and(U32.is_eq(k1, k2), U32.is_lt(x1, x2)))

def entry.v(k: U32, r: Vec.Vec & U32) -> Vec.Vec & (U32 & U32):
  (v, x) = r
  (v, (k, x))

def entry.k(+i: U32, r: Vec.Vec & U32) -> Vec.Vec & (U32 & U32):
  (v, k) = r
  entry.v(k, Vec.at(v, U32.inc(U32.shl(i))))

def entry(v: Vec.Vec, +i: U32) -> Vec.Vec & (U32 & U32):
  entry.k(i, Vec.at(v, U32.shl(i)))

def write(v: Vec.Vec, +i: U32, k: U32, x: U32) -> Vec.Vec:
  Vec.put(Vec.put(v, U32.shl(i), k), U32.inc(U32.shl(i)), x)

# A sift is one self-recursive def (outside Base a def may only call itself
# back), so a level is looked at by defs that do not recurse and answer with
# where the sift stands: settled, or the hole moved to j.
type Sift is Type:
  Done{v: Vec.Vec}
  More{v: Vec.Vec, j: U32}

# up: the entry (k, x) rises from the hole at i
def up.if(v: Vec.Vec, +i: U32, k: U32, x: U32, j: U32, pk: U32, px: U32, rises: Bool) -> Sift:
  match rises:
    case True{}:
      More{write(v, i, pk, px), j}
    case False{}:
      Done{write(v, i, k, x)}

def up.lt(v: Vec.Vec, +i: U32, +k: U32, +x: U32, j: U32, +pk: U32, +px: U32) -> Sift:
  up.if(v, i, k, x, j, pk, px, less(k, x, pk, px))

def up.cmp(+i: U32, +k: U32, +x: U32, j: U32, r: Vec.Vec & (U32 & U32)) -> Sift:
  (v, pk, px) = r
  up.lt(v, i, k, x, j, pk, px)

def up.at(v: Vec.Vec, +i: U32, k: U32, x: U32, root: Bool) -> Sift:
  match root:
    case True{}:
      Done{write(v, i, k, x)}
    case False{}:
      up.cmp(i, k, x, U32.shr(U32.sub(i, 1)), entry(v, U32.shr(U32.sub(i, 1))))

def up.look(v: Vec.Vec, +i: U32, k: U32, x: U32) -> Sift:
  up.at(v, i, k, x, U32.is_zero(i))

def up(fuel: Nat, s: Sift, +k: U32, +x: U32) -> Vec.Vec:
  match fuel:
    case 0n:
      match s:
        case Done{v}:
          v
        case More{v, j}:
          write(v, j, k, x)
    case 1n++p:
      match s:
        case Done{v}:
          v
        case More{v, j}:
          up(p, up.look(v, j, k, x), k, x)

# down: the entry (k, x) sinks from the hole at i in a heap of n
def down.if(v: Vec.Vec, +n: U32, +i: U32, +k: U32, +x: U32, +c: U32, ck: U32, cx: U32, sinks: Bool) -> Sift:
  match sinks:
    case True{}:
      More{write(v, i, ck, cx), c}
    case False{}:
      Done{write(v, i, k, x)}

def down.two(v: Vec.Vec, +n: U32, +i: U32, +k: U32, +x: U32, +l: U32, +lk: U32, +lx: U32, +rk: U32, +rx: U32, right: Bool) -> Sift:
  match right:
    case True{}:
      down.if(v, n, i, k, x, U32.inc(l), rk, rx, less(rk, rx, k, x))
    case False{}:
      down.if(v, n, i, k, x, l, lk, lx, less(lk, lx, k, x))

def down.lt(v: Vec.Vec, +n: U32, +i: U32, +k: U32, +x: U32, +l: U32, +lk: U32, +lx: U32, +rk: U32, +rx: U32) -> Sift:
  down.two(v, n, i, k, x, l, lk, lx, rk, rx, less(rk, rx, lk, lx))

def down.pick(+n: U32, +i: U32, +k: U32, +x: U32, +l: U32, +lk: U32, +lx: U32, r: Vec.Vec & (U32 & U32)) -> Sift:
  (v, rk, rx) = r
  down.lt(v, n, i, k, x, l, lk, lx, rk, rx)

def down.has(v: Vec.Vec, +n: U32, +i: U32, +k: U32, +x: U32, +l: U32, +lk: U32, +lx: U32, two: Bool) -> Sift:
  match two:
    case True{}:
      down.pick(n, i, k, x, l, lk, lx, entry(v, U32.inc(l)))
    case False{}:
      down.if(v, n, i, k, x, l, lk, lx, less(lk, lx, k, x))

def down.left(+n: U32, +i: U32, +k: U32, +x: U32, +l: U32, r: Vec.Vec & (U32 & U32)) -> Sift:
  (v, lk, lx) = r
  down.has(v, n, i, k, x, l, lk, lx, U32.is_lt(U32.inc(l), n))

def down.at(v: Vec.Vec, +n: U32, +i: U32, +k: U32, +x: U32, leaf: Bool) -> Sift:
  match leaf:
    case True{}:
      Done{write(v, i, k, x)}
    case False{}:
      down.left(n, i, k, x, U32.inc(U32.shl(i)), entry(v, U32.inc(U32.shl(i))))

def down.look(v: Vec.Vec, +n: U32, +i: U32, k: U32, x: U32) -> Sift:
  down.at(v, n, i, k, x, U32.is_ge(U32.inc(U32.shl(i)), n))

def down(fuel: Nat, s: Sift, +n: U32, +k: U32, +x: U32) -> Vec.Vec:
  match fuel:
    case 0n:
      match s:
        case Done{v}:
          v
        case More{v, j}:
          write(v, j, k, x)
    case 1n++p:
      match s:
        case Done{v}:
          v
        case More{v, j}:
          down(p, down.look(v, n, j, k, x), n, k, x)

def push(h: Heap, +k: U32, +x: U32) -> Heap:
  match h:
    case Heap{+n, v}:
      Heap{U32.inc(n), up(32n, More{Vec.push(Vec.push(Vec.truncate(v, U32.shl(n)), k), x), n}, k, x)}

# peek: the least entry, left in place
def peek.fin(n: U32, r: Vec.Vec & (U32 & U32)) -> Heap & Maybe<&2, Entry>:
  (v, k, x) = r
  (Heap{n, v}, Some{Entry{k, x}})

def peek.if(+n: U32, v: Vec.Vec, empty: Bool) -> Heap & Maybe<&2, Entry>:
  match empty:
    case True{}:
      (Heap{n, v}, None{})
    case False{}:
      peek.fin(n, entry(v, 0))

def peek(h: Heap) -> Heap & Maybe<&2, Entry>:
  match h:
    case Heap{+n, v}:
      peek.if(n, v, U32.is_zero(n))

# pop: the least entry out; the last entry sinks from the root
def pop.fix(+m: U32, v: Vec.Vec, +lk: U32, +lx: U32, none: Bool) -> Vec.Vec:
  match none:
    case True{}:
      v
    case False{}:
      down(32n, More{v, 0}, m, lk, lx)

def pop.last(+m: U32, top: Entry, r: Vec.Vec & (U32 & U32)) -> Heap & Maybe<&2, Entry>:
  (v, lk, lx) = r
  (Heap{m, pop.fix(m, v, lk, lx, U32.is_zero(m))}, Some{top})

def pop.root(+m: U32, r: Vec.Vec & (U32 & U32)) -> Heap & Maybe<&2, Entry>:
  (v, k, x) = r
  pop.last(m, Entry{k, x}, entry(v, m))

def pop.if(+n: U32, v: Vec.Vec, empty: Bool) -> Heap & Maybe<&2, Entry>:
  match empty:
    case True{}:
      (Heap{n, v}, None{})
    case False{}:
      pop.root(U32.sub(n, 1), entry(v, 0))

def pop(h: Heap) -> Heap & Maybe<&2, Entry>:
  match h:
    case Heap{+n, v}:
      pop.if(n, v, U32.is_zero(n))

# replace: the least entry gives its place to (k, x), one sift instead of a pop
# and a push (heapq.heapreplace). On an empty heap it is a push.
def replace.if(+n: U32, v: Vec.Vec, +k: U32, +x: U32, empty: Bool) -> Heap:
  match empty:
    case True{}:
      push(Heap{n, v}, k, x)
    case False{}:
      Heap{n, down(32n, More{v, 0}, n, k, x)}

def replace(h: Heap, +k: U32, +x: U32) -> Heap:
  match h:
    case Heap{+n, v}:
      replace.if(n, v, k, x, U32.is_zero(n))

# drain: every entry, greatest first (each pop conses onto the last)
def drain.cons(r: Heap & Maybe<&2, Entry>, acc: List<&2, Entry>) -> Heap & List<&2, Entry>:
  (h, m) = r
  match m:
    case None{}:
      (h, acc)
    case Some{e}:
      (h, Con{e, acc})

def drain.step(ha: Heap & List<&2, Entry>) -> Heap & List<&2, Entry>:
  (h, acc) = ha
  drain.cons(pop(h), acc)

def drain.go(i: Nat, ha: Heap & List<&2, Entry>) -> Heap & List<&2, Entry>:
  match i:
    case 0n:
      ha
    case 1n++p:
      drain.go(p, drain.step(ha))

def drain.len(r: Heap & U32) -> Heap & List<&2, Entry>:
  (h, n) = r
  drain.go(U32.to_nat(n), (h, []))

def drain(h: Heap) -> Heap & List<&2, Entry>:
  drain.len(len(h))
