# Flat: n vectors of d floats in one row-major array, and exact K nearest
# neighbours over them by brute force -- Faiss's IndexFlat, which is the index
# every approximate one is measured against and the one that is right.
#
# The decision worth arguing is the rank key. TopK ranks U32, a distance is F32,
# and this file bridges them with the bits and not with a fixed point. IEEE-754
# was laid out so that the bit pattern of a float, read as an integer, is
# already in float order for one sign; `key` makes that total across both signs
# by setting the sign bit of a positive and inverting a negative, and then a U32
# compare IS the float compare, for every finite float, with no quantum to pick
# and nothing rounded away. power-6 refused the same trick for bm25 and took a
# fixed point instead, because a bm25 weight has a known range and integer sums
# are associative; a squared distance has neither -- it is unbounded and scale
# dependent, so there is no one quantum, and nothing is being summed across
# shards. Two different arguments, two different answers.
#
# The price, stated: F32.bits is one-way (Base has no U32 -> F32), so a drained
# entry carries the key, not the distance. A caller that wants the number calls
# `l2` again on the id it got back -- bm25's `explain`, one O(d) pass.
#
# Written for the compiled lanes: one flat Array<F32> (F32 lays as a 32-bit
# word, so the store is one block, not a tree of boxes), an index loop and no
# allocation in the distance, and search_l2 / search_ip as separate defs so the
# hot loop never branches on a mode.
import Base
import ./topk.bend as TopK
import ./heap.bend as Heap

# n * d floats, row major: row i column c is cell i * d + c. `m` counts floats,
# so the vector count is m / d and a partial row cannot be represented.
type Flat is Type:
  Flat{m: U32, d: U32, depth: Nat, xs: Array<F32>}

def new(+d: U32) -> Flat:
  Flat{0, d, 2n, [0.0 : F32^2n]}

# an empty store with room for 2^depth floats, so `push` never has to grow it.
# Filling by doubling copies about as many cells again as it stores; a caller
# that knows n and d up front pays neither those copies nor the peak.
def sized(+d: U32, +depth: Nat) -> Flat:
  Flat{0, d, depth, [0.0 : F32^depth]}

def dim(f: Flat) -> Flat & U32:
  match f:
    case Flat{m, +d, depth, xs}:
      (Flat{m, d, depth, xs}, d)

def size(f: Flat) -> Flat & U32:
  match f:
    case Flat{+m, +d, depth, xs}:
      (Flat{m, d, depth, xs}, U32.div(m, d))

# -- the cells ---------------------------------------------------------------

# an unchecked read: p must be under m. Vec's `at`, for floats.
def cell.fin(m: U32, d: U32, depth: Nat, r: Array<F32> & F32) -> Flat & F32:
  (xs, x) = r
  (Flat{m, d, depth, xs}, x)

def cell(f: Flat, +p: U32) -> Flat & F32:
  match f:
    case Flat{m, d, depth, xs}:
      cell.fin(m, d, depth, Array.get(F32, xs, p))

def put(f: Flat, +p: U32, x: F32) -> Flat:
  match f:
    case Flat{m, d, depth, xs}:
      Flat{m, d, depth, Array.set(F32, xs, p, x)}

def at(f: Flat, +i: U32, +c: U32) -> Flat & F32:
  match f:
    case Flat{m, +d, depth, xs}:
      cell.fin(m, d, depth, Array.get(F32, xs, U32.add(U32.mul(i, d), c)))

# push one float, doubling the block when it is full: Vec's growth, since the
# store is built once and read many times and a copy per doubling is amortized
def push.if(+m: U32, +d: U32, +depth: Nat, xs: Array<F32>, +x: F32, fits: Bool) -> Flat:
  match fits:
    case True{}:
      Flat{U32.inc(m), d, depth, Array.set(F32, xs, m, x)}
    case False{}:
      Flat{U32.inc(m), d, 1n+depth, Array.set(F32, ANode{xs, [x : F32^depth]}, m, x)}

def push(f: Flat, +x: F32) -> Flat:
  match f:
    case Flat{+m, +d, +depth, xs}:
      push.if(m, d, depth, xs, x, U32.is_lt(m, U32.shln(1, depth)))

# the floats in row-major order; the caller states d, and a length that is not a
# multiple of d leaves a partial row this type cannot hold, so it is the
# caller's to get right
def of_list.go(xs: List<&2, F32>, f: Flat) -> Flat:
  match xs:
    case Nil{}:
      f
    case Con{x, t}:
      of_list.go(t, push(f, x))

def of_list(xs: List<&2, F32>, +d: U32) -> Flat:
  of_list.go(xs, new(d))

# -- the rank key ------------------------------------------------------------

# the total order of IEEE-754 as a U32: for two floats a and b, key(a) < key(b)
# exactly when a < b. Positives already sort by their raw bits, so they only
# need lifting above every negative (set the sign bit); negatives sort backwards
# by their raw bits, so they are inverted, which also lands them below.
# NaN is not ordered and gets whatever its payload gives -- a NaN distance is a
# caller's bug, and this file will rank it rather than notice it.
def key.if(+b: U32, neg: Bool) -> U32:
  match neg:
    case True{}:
      U32.not(b)
    case False{}:
      U32.or(b, 2147483648)

def key.b(+b: U32) -> U32:
  key.if(b, U32.is_ge(b, 2147483648))

# the `+ 0.0` is not dead: it is the one operation that maps -0.0 to +0.0, and
# without it two floats that compare equal would get different keys
def key(+x: F32) -> U32:
  key.b(F32.bits(F32.add(x, 0.0)))

# the same order reversed, for a distance: nearer is a bigger key, so a min
# search runs on the same max-heap a similarity search does
def near(+x: F32) -> U32:
  U32.sub(4294967295, key(x))

# -- the distances -----------------------------------------------------------

# two Flats and one accumulator: an Array has one owner, so a loop over two
# stores has to carry both of them, and a record is how a Bend loop carries
# more than it returns
type Acc is Type:
  Acc{f: Flat, q: Flat, s: F32}

def l2.y(f: Flat, +x: F32, +s: F32, r: Flat & F32) -> Acc:
  (q, y) = r
  Acc{f, q, F32.add(s, F32.square(F32.sub(x, y)))}

def l2.x(q: Flat, +b: U32, +s: F32, r: Flat & F32) -> Acc:
  (f, x) = r
  l2.y(f, x, s, cell(q, b))

def l2.go(fuel: Nat, +a: U32, +b: U32, x: Acc) -> Acc:
  match fuel:
    case 0n:
      x
    case 1n++p:
      match x:
        case Acc{f, q, s}:
          l2.go(p, U32.inc(a), U32.inc(b), l2.x(q, b, s, cell(f, a)))

def acc.out(x: Acc) -> Flat & Flat & F32:
  match x:
    case Acc{f, q, s}:
      (f, q, s)

def l2.d(q: Flat, +i: U32, +j: U32, +d: U32, f: Flat) -> Flat & Flat & F32:
  acc.out(l2.go(U32.to_nat(d), U32.mul(i, d), U32.mul(j, d), Acc{f, q, 0.0}))

# the squared L2 between row i of f and row j of q. Squared, like Faiss: the
# square root is monotone, so it changes no ranking and costs one call a row.
def l2(f: Flat, +i: U32, q: Flat, +j: U32) -> Flat & Flat & F32:
  match f:
    case Flat{m, +d, depth, xs}:
      l2.d(q, i, j, d, Flat{m, d, depth, xs})

def ip.y(f: Flat, +x: F32, +s: F32, r: Flat & F32) -> Acc:
  (q, y) = r
  Acc{f, q, F32.add(s, F32.mul(x, y))}

def ip.x(q: Flat, +b: U32, +s: F32, r: Flat & F32) -> Acc:
  (f, x) = r
  ip.y(f, x, s, cell(q, b))

def ip.go(fuel: Nat, +a: U32, +b: U32, x: Acc) -> Acc:
  match fuel:
    case 0n:
      x
    case 1n++p:
      match x:
        case Acc{f, q, s}:
          ip.go(p, U32.inc(a), U32.inc(b), ip.x(q, b, s, cell(f, a)))

def ip.d(q: Flat, +i: U32, +j: U32, +d: U32, f: Flat) -> Flat & Flat & F32:
  acc.out(ip.go(U32.to_nat(d), U32.mul(i, d), U32.mul(j, d), Acc{f, q, 0.0}))

# the inner product of row i of f and row j of q. Bigger is better, which is the
# opposite of l2, which is why they get their own searches.
def ip(f: Flat, +i: U32, q: Flat, +j: U32) -> Flat & Flat & F32:
  match f:
    case Flat{m, +d, depth, xs}:
      ip.d(q, i, j, d, Flat{m, d, depth, xs})

# -- the norm, and normalize -------------------------------------------------

type Sq is Type:
  Sq{f: Flat, s: F32}

def sq.add(+s: F32, r: Flat & F32) -> Sq:
  (f, x) = r
  Sq{f, F32.add(s, F32.square(x))}

def sq.go(fuel: Nat, +a: U32, x: Sq) -> Sq:
  match fuel:
    case 0n:
      x
    case 1n++p:
      match x:
        case Sq{f, s}:
          sq.go(p, U32.inc(a), sq.add(s, cell(f, a)))

def sq.out(x: Sq) -> Flat & F32:
  match x:
    case Sq{f, s}:
      (f, F32.sqrt(s))

def norm.d(+i: U32, +d: U32, f: Flat) -> Flat & F32:
  sq.out(sq.go(U32.to_nat(d), U32.mul(i, d), Sq{f, 0.0}))

# the L2 length of row i
def norm(f: Flat, +i: U32) -> Flat & F32:
  match f:
    case Flat{m, +d, depth, xs}:
      norm.d(i, d, Flat{m, d, depth, xs})

def nz.put(+a: U32, +r: F32, x: Flat & F32) -> Flat:
  (f, v) = x
  put(f, a, F32.div(v, r))

def nz.go(fuel: Nat, +a: U32, +r: F32, f: Flat) -> Flat:
  match fuel:
    case 0n:
      f
    case 1n++p:
      nz.go(p, U32.inc(a), r, nz.put(a, r, cell(f, a)))

# a zero row has no direction to keep, so it stays zero rather than becoming a
# row of NaN -- and its inner product with everything is 0, which is the answer
# a cosine search should give it
def nz.row(+a: U32, +d: U32, +r: F32, f: Flat, zero: Bool) -> Flat:
  match zero:
    case True{}:
      f
    case False{}:
      nz.go(U32.to_nat(d), a, r, f)

def nz.one.r(+a: U32, +d: U32, +r: F32, f: Flat) -> Flat:
  nz.row(a, d, r, f, F32.is_eq(r, 0.0))

def nz.one(+i: U32, +d: U32, x: Flat & F32) -> Flat:
  (f, r) = x
  nz.one.r(U32.mul(i, d), d, r, f)

def nz.rows(fuel: Nat, +i: U32, +d: U32, f: Flat) -> Flat:
  match fuel:
    case 0n:
      f
    case 1n++p:
      nz.rows(p, U32.inc(i), d, nz.one(i, d, norm(f, i)))

def nz.n(+d: U32, x: Flat & U32) -> Flat:
  (f, n) = x
  nz.rows(U32.to_nat(n), 0, d, f)

# every row to unit length, in place. This is how a cosine search is done:
# normalize the store once, normalize the query, then search_ip -- which is what
# Faiss tells you to do instead of giving cosine its own index.
def normalize(f: Flat) -> Flat:
  match f:
    case Flat{m, +d, depth, xs}:
      nz.n(d, size(Flat{m, d, depth, xs}))

# -- the search --------------------------------------------------------------

type Rk is Type:
  Rk{f: Flat, q: Flat, t: TopK.TopK}

def rk.acc(+i: U32, t: TopK.TopK, r: Flat & Flat & U32) -> Rk:
  (f, q, k) = r
  Rk{f, q, TopK.offer(t, k, i)}

def l2.key(+i: U32, t: TopK.TopK, r: Flat & Flat & F32) -> Rk:
  (f, q, s) = r
  rk.acc(i, t, (f, q, near(s)))

def l2.scan(fuel: Nat, +i: U32, +j: U32, x: Rk) -> Rk:
  match fuel:
    case 0n:
      x
    case 1n++p:
      match x:
        case Rk{f, q, t}:
          l2.scan(p, U32.inc(i), j, l2.key(i, t, l2(f, i, q, j)))

def ip.key(+i: U32, t: TopK.TopK, r: Flat & Flat & F32) -> Rk:
  (f, q, s) = r
  rk.acc(i, t, (f, q, key(s)))

def ip.scan(fuel: Nat, +i: U32, +j: U32, x: Rk) -> Rk:
  match fuel:
    case 0n:
      x
    case 1n++p:
      match x:
        case Rk{f, q, t}:
          ip.scan(p, U32.inc(i), j, ip.key(i, t, ip(f, i, q, j)))

def rk.out(f: Flat, q: Flat, r: TopK.TopK & List<&2, Heap.Entry>) -> Flat & Flat & List<&2, Heap.Entry>:
  (t, xs) = r
  (f, q, xs)

def rk.fin(x: Rk) -> Flat & Flat & List<&2, Heap.Entry>:
  match x:
    case Rk{f, q, t}:
      rk.out(f, q, TopK.drain(t))

# the K nearest rows of f to row j of q, nearest first, each as an entry whose
# `val` is the row and whose `key` is `near(distance)` -- the order, not the
# number. Two rows at the same distance are settled by TopK's own rule, the
# greater row number, so the answer never depends on the scan order.
def search_l2.n(q: Flat, +j: U32, +k: U32, x: Flat & U32) -> Flat & Flat & List<&2, Heap.Entry>:
  (f, n) = x
  rk.fin(l2.scan(U32.to_nat(n), 0, j, Rk{f, q, TopK.new(k)}))

def search_l2(f: Flat, q: Flat, +j: U32, +k: U32) -> Flat & Flat & List<&2, Heap.Entry>:
  search_l2.n(q, j, k, size(f))

# the K rows of f with the greatest inner product with row j of q, best first
def search_ip.n(q: Flat, +j: U32, +k: U32, x: Flat & U32) -> Flat & Flat & List<&2, Heap.Entry>:
  (f, n) = x
  rk.fin(ip.scan(U32.to_nat(n), 0, j, Rk{f, q, TopK.new(k)}))

def search_ip(f: Flat, q: Flat, +j: U32, +k: U32) -> Flat & Flat & List<&2, Heap.Entry>:
  search_ip.n(q, j, k, size(f))
