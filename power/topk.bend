# TopK: the K greatest (key, val) entries of a stream in K entries of memory: a
# min-heap of the K kept so far, whose root is the one an arrival must beat.
# Entries order by key and then by val (Heap's order), so which of two equal keys
# is kept never depends on arrival order, and the K of a merged stream are the K
# of the merge: TopK.merge is exact. A beam search frontier is this: offer every
# expansion, drain.
#
# Written for the compiled lanes: an arrival that loses costs one peek and one
# compare, no write; one that wins is Heap.replace, a single sift.
import Base
import ./heap.bend as Heap

type TopK is Type:
  TopK{k: U32, heap: Heap.Heap}

def new(k: U32) -> TopK:
  TopK{k, Heap.new()}

def offer.beat(k: U32, h: Heap.Heap, key: U32, val: U32, wins: Bool) -> TopK:
  match wins:
    case True{}:
      TopK{k, Heap.replace(h, key, val)}
    case False{}:
      TopK{k, h}

def offer.min(k: U32, +key: U32, +val: U32, r: Heap.Heap & Maybe<&2, Heap.Entry>) -> TopK:
  (h, m) = r
  match m:
    case None{}:
      TopK{k, h}
    case Some{Heap.Entry{mk, mx}}:
      offer.beat(k, h, key, val, Heap.less(mk, mx, key, val))

def offer.if(k: U32, h: Heap.Heap, +key: U32, +val: U32, room: Bool) -> TopK:
  match room:
    case True{}:
      TopK{k, Heap.push(h, key, val)}
    case False{}:
      offer.min(k, key, val, Heap.peek(h))

def offer.len(+k: U32, +key: U32, +val: U32, r: Heap.Heap & U32) -> TopK:
  (h, n) = r
  offer.if(k, h, key, val, U32.is_lt(n, k))

def offer(t: TopK, +key: U32, +val: U32) -> TopK:
  match t:
    case TopK{k, h}:
      offer.len(k, key, val, Heap.len(h))

# the list leads: a self-call must shrink before any argument changes
def offer_all(xs: List<&2, Heap.Entry>, t: TopK) -> TopK:
  match xs:
    case Nil{}:
      t
    case Con{Heap.Entry{+key, +val}, rest}:
      offer_all(rest, offer(t, key, val))

# drain: the kept entries, best first; the TopK comes back empty
def drain.fin(k: U32, r: Heap.Heap & List<&2, Heap.Entry>) -> TopK & List<&2, Heap.Entry>:
  (h, xs) = r
  (TopK{k, h}, xs)

def drain(t: TopK) -> TopK & List<&2, Heap.Entry>:
  match t:
    case TopK{k, h}:
      drain.fin(k, Heap.drain(h))

def merge.fin(a: TopK, r: TopK & List<&2, Heap.Entry>) -> TopK:
  (b, xs) = r
  offer_all(xs, a)

# merge: a keeps the best of both under its own K; b is spent
def merge(a: TopK, b: TopK) -> TopK:
  merge.fin(a, drain(b))
