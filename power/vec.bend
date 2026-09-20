# Vec: a growable packed sequence of U32 over Base's Array, which every compiled
# lane lays as one flat block of raw u32 cells. (The element is closed: the
# compiler lays an Array by its element type and refuses an open one.) One owner,
# so every write is in place and every read hands the Vec back.
#
# Written for the compiled lanes: the capacity is one shift of the stored depth
# (Array.size walks the tree on the interpreter); growth is ANode{old, fresh},
# one block copy that keeps indices 0..len-1 where they were; the pushed element
# fills the fresh half, so no default element is ever asked for.
import Base

type Vec is Type:
  Vec{len: U32, depth: Nat, arr: Array<U32>}

def new(+fill: U32) -> Vec:
  Vec{0, 2n, [fill : U32^2n]}

def len(v: Vec) -> Vec & U32:
  match v:
    case Vec{+n, d, arr}:
      (Vec{n, d, arr}, n)

# push: amortized O(1)
def push.if(+n: U32, +d: Nat, arr: Array<U32>, +x: U32, fits: Bool) -> Vec:
  match fits:
    case True{}:
      Vec{U32.inc(n), d, Array.set(U32, arr, n, x)}
    case False{}:
      Vec{U32.inc(n), 1n+d, Array.set(U32, ANode{arr, [x : U32^d]}, n, x)}

def push(v: Vec, +x: U32) -> Vec:
  match v:
    case Vec{+n, +d, arr}:
      push.if(n, d, arr, x, U32.is_lt(n, U32.shln(1, d)))

# at: unchecked, the index wraps at the capacity; for loops that own their bounds
def at.fin(n: U32, d: Nat, r: Array<U32> & U32) -> Vec & U32:
  (arr, x) = r
  (Vec{n, d, arr}, x)

def at(v: Vec, +i: U32) -> Vec & U32:
  match v:
    case Vec{n, d, arr}:
      at.fin(n, d, Array.get(U32, arr, i))

# get: checked
def get.some(r: Vec & U32) -> Vec & Maybe<&2, U32>:
  (v, x) = r
  (v, Some{x})

def get.if(v: Vec, +i: U32, ok: Bool) -> Vec & Maybe<&2, U32>:
  match ok:
    case True{}:
      get.some(at(v, i))
    case False{}:
      (v, None{})

def get(v: Vec, +i: U32) -> Vec & Maybe<&2, U32>:
  match v:
    case Vec{+n, d, arr}:
      get.if(Vec{n, d, arr}, i, U32.is_lt(i, n))

# put: unchecked write; set: checked, the Bool says whether it landed
def put(v: Vec, i: U32, x: U32) -> Vec:
  match v:
    case Vec{n, d, arr}:
      Vec{n, d, Array.set(U32, arr, i, x)}

def set.if(v: Vec, i: U32, x: U32, ok: Bool) -> Vec & Bool:
  match ok:
    case True{}:
      (put(v, i, x), True{})
    case False{}:
      (v, False{})

def set(v: Vec, +i: U32, x: U32) -> Vec & Bool:
  match v:
    case Vec{+n, d, arr}:
      set.if(Vec{n, d, arr}, i, x, U32.is_lt(i, n))

# pop: the last element; the slot keeps its old word, len forgets it
def pop.if(+n: U32, d: Nat, arr: Array<U32>, empty: Bool) -> Vec & Maybe<&2, U32>:
  match empty:
    case True{}:
      (Vec{n, d, arr}, None{})
    case False{}:
      get.some(at.fin(U32.sub(n, 1), d, Array.get(U32, arr, U32.sub(n, 1))))

def pop(v: Vec) -> Vec & Maybe<&2, U32>:
  match v:
    case Vec{+n, d, arr}:
      pop.if(n, d, arr, U32.is_zero(n))

# swap: exchange two slots, unchecked; one read and two writes through Array.swap
def swap.put(j: U32, r: Array<U32> & U32) -> Array<U32>:
  (arr, xi) = r
  Array.set(U32, arr, j, xi)

def swap.got(+i: U32, +j: U32, r: Array<U32> & U32) -> Array<U32>:
  (arr, xj) = r
  swap.put(j, Array.swap(U32, arr, i, xj))

def swap(v: Vec, i: U32, +j: U32) -> Vec:
  match v:
    case Vec{n, d, arr}:
      Vec{n, d, swap.got(i, j, Array.get(U32, arr, j))}

def truncate.if(n: U32, d: Nat, arr: Array<U32>, k: U32, shorter: Bool) -> Vec:
  match shorter:
    case True{}:
      Vec{k, d, arr}
    case False{}:
      Vec{n, d, arr}

def truncate(v: Vec, +k: U32) -> Vec:
  match v:
    case Vec{+n, d, arr}:
      truncate.if(n, d, arr, k, U32.is_lt(k, n))

# the list leads: a self-call must shrink before any argument changes
def from_list(xs: List<&2, U32>, v: Vec) -> Vec:
  match xs:
    case Nil{}:
      v
    case Con{+x, t}:
      from_list(t, push(v, x))

def to_list.cons(r: Vec & U32, acc: List<&2, U32>) -> Vec & List<&2, U32>:
  (v, x) = r
  (v, Con{x, acc})

def to_list.step(i: U32, va: Vec & List<&2, U32>) -> Vec & List<&2, U32>:
  (v, acc) = va
  to_list.cons(at(v, i), acc)

# i counts down beside the index it names: the measure is a Nat, the read a U32
def to_list.go(i: Nat, va: Vec & List<&2, U32>) -> Vec & List<&2, U32>:
  match i:
    case 0n:
      va
    case 1n++p:
      to_list.go(p, to_list.step(U32.from_nat(p), va))

def to_list.len(r: Vec & U32) -> Vec & List<&2, U32>:
  (v, n) = r
  to_list.go(U32.to_nat(n), (v, []))

def to_list(v: Vec) -> Vec & List<&2, U32>:
  to_list.len(len(v))
