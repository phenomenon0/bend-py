# Budget: the allowance as a value, not as a counter someone holds. A Budget is
# three U32 meters and nothing else, so its kind is Data -- it copies, it drops,
# and it rides inside a Result. That last one is the whole lane. Vec, Bytes and
# every index built on them have kind Type, so a primitive that owns an array
# cannot hand its remaining allowance back inside a Result and has to carry it in
# its own state instead -- power/json.bend does exactly that, and power-5
# recorded it as a deviation from the package convention. It was never the
# allowance that forced the deviation; it was the payload beside it.
#
# Three meters, because a meter is defined by *when* it is charged and not by
# what it measures:
#
#   Work   as effort is spent           one step, one byte scanned, one compare
#   Out    as the answer is built       a cap on the result, not on the effort
#   Calls  as something expensive or irreversible is done   an IO round trip
#
# Memory is deliberately not a meter. Memory is a high-water mark, so it is
# charged with max and released on the way out, not subtracted and kept; putting
# it in this record would make join and `spent + left == started` false. A
# high-water meter is a different record with a different algebra.
#
# The four laws, each pinned by a row in tests/power/budget.bend:
#
#   afford(b, m, n) == is_done(spend(b, m, n))   a caller cannot be told yes and
#                                                then refused, or the reverse
#   join(split(b)) == b                          a fork neither loses nor invents
#   cap(outer, inner) <= outer, meterwise        nested code cannot raise a limit
#   used(b0, b, m) + left(b, m) == left(b0, m)   nothing leaks
#
# Written for the compiled lanes: every operation here is three U32 compares or
# three U32 subtractions on an unboxed record. Threading a budget down a loop
# costs what threading three integers costs, which is the number the bench
# reports against a C `while (left--)`.
import Base

type Meter is Data:
  Work{}
  Out{}
  Calls{}

type Budget is Data:
  Budget{work: U32, out: U32, calls: U32}

# the refusal says which meter ran out: a caller that hits a wall wants to know
# which wall, and "Dry" alone makes a retry policy guess
type Error is Data:
  Dry{m: Meter}

def Res(T: Data) -> Data:
  Result<&2, &2, Error, T>

def max() -> U32:
  4294967295

# -- construction ------------------------------------------------------------

def new(+work: U32, +out: U32, +calls: U32) -> Budget:
  Budget{work, out, calls}

# nothing is affordable
def none() -> Budget:
  Budget{0, 0, 0}

# ponytail: "unlimited" is max on every meter, not a fourth constructor. A real
# infinity would need an Inf arm in each meter and a case in every operation
# below, to buy a distinction nothing in this library can reach: 2^32-1 steps at
# one nanosecond is four seconds, and 2^32-1 calls is not a program.
def all() -> Budget:
  Budget{max(), max(), max()}

def show.m(m: Meter) -> String:
  match m:
    case Work{}:
      "work"
    case Out{}:
      "out"
    case Calls{}:
      "calls"

# -- reading -----------------------------------------------------------------

def left(b: Budget, m: Meter) -> U32:
  match b m:
    case Budget{w, o, c} Work{}:
      w
    case Budget{w, o, c} Out{}:
      o
    case Budget{w, o, c} Calls{}:
      c

def set(b: Budget, m: Meter, +n: U32) -> Budget:
  match b m:
    case Budget{w, o, c} Work{}:
      Budget{n, o, c}
    case Budget{w, o, c} Out{}:
      Budget{w, n, c}
    case Budget{w, o, c} Calls{}:
      Budget{w, o, n}

def afford(+b: Budget, +m: Meter, +n: U32) -> Bool:
  U32.is_le(n, left(b, m))

# is_empty: no meter has anything left. Not the same as "some meter is dry" --
# a loop that stops on the first dry meter tests afford, not this
def is_empty(+b: Budget) -> Bool:
  Bool.and(U32.is_eq(left(b, Work{}), 0),
    Bool.and(U32.is_eq(left(b, Out{}), 0), U32.is_eq(left(b, Calls{}), 0)))

# -- spending ----------------------------------------------------------------

def spend.if(+b: Budget, +m: Meter, +n: U32, ok: Bool) -> Res(Budget):
  match ok:
    case True{}:
      Done{set(b, m, U32.sub(left(b, m), n))}
    case False{}:
      Fail{Dry{m}}

# pay before building: the answer is the budget after the charge, or the meter
# that refused it. A refused charge spends nothing -- there is no partial pay.
def spend(+b: Budget, +m: Meter, +n: U32) -> Res(Budget):
  spend.if(b, m, n, afford(b, m, n))

# take: the same charge, but capped instead of refused -- the budget goes to zero
# and the second half of the answer is what was actually granted. For a loop that
# wants to do as much as it can afford rather than refuse the whole batch.
def take.n(+b: Budget, +m: Meter, +g: U32) -> Budget & U32:
  (set(b, m, U32.sub(left(b, m), g)), g)

def take(+b: Budget, +m: Meter, +n: U32) -> Budget & U32:
  take.n(b, m, U32.min(n, left(b, m)))

# used: how far a meter moved between a budget and a later one. Clamped at 0,
# because a `now` holding more than `started` is not on the same timeline and
# reporting that as a near-2^32 spend would be the worse lie.
def used.if(+a: U32, +b: U32, back: Bool) -> U32:
  match back:
    case True{}:
      0
    case False{}:
      U32.sub(a, b)

def used(+started: Budget, +now: Budget, +m: Meter) -> U32:
  used.if(left(started, m), left(now, m), U32.is_lt(left(started, m), left(now, m)))

# -- composition -------------------------------------------------------------

# saturating add: join may lose budget, never invent it. min(a + b, max) is at
# most a + b for every a and b, so no sequence of joins can raise a total.
def sat.if(+a: U32, +x: U32, over: Bool) -> U32:
  match over:
    case True{}:
      max()
    case False{}:
      U32.add(a, x)

def sat(+a: U32, +x: U32) -> U32:
  sat.if(a, x, U32.is_lt(U32.sub(max(), a), x))

def join.mk(+w: U32, +o: U32, +c: U32, b: Budget) -> Budget:
  match b:
    case Budget{x, y, z}:
      Budget{sat(w, x), sat(o, y), sat(c, z)}

# join: two remainders become one. After a fork, this is what the parent gets
# back, and what it gets back is at most what it handed out.
def join(a: Budget, b: Budget) -> Budget:
  match a:
    case Budget{w, o, c}:
      join.mk(w, o, c, b)

# hi: the right half a binary fork hands its second child, floor on every meter.
def hi(b: Budget) -> Budget:
  match b:
    case Budget{w, o, c}:
      Budget{U32.shrn(w, 1n), U32.shrn(o, 1n), U32.shrn(c, 1n)}

def lo.mk(+w: U32, +o: U32, +c: U32) -> Budget:
  Budget{U32.sub(w, U32.shrn(w, 1n)), U32.sub(o, U32.shrn(o, 1n)), U32.sub(c, U32.shrn(c, 1n))}

# lo: the left half, and it takes the ceiling, so lo and hi sum to the parent
# *exactly* and an odd allowance is never rounded away -- which is what makes
# join(lo(b), hi(b)) == b hold at every depth of a tree and not only at even
# numbers. lo and hi exist separately from `split` because a fork wants them
# separately: a Budget has kind Data, so both children can derive their own half
# from the same parent value and nothing has to thread a pair down the recursion.
# An affine primitive has no such luxury, and that is the whole difference
# between forking a Budget and forking a Vec.
def lo(b: Budget) -> Budget:
  match b:
    case Budget{w, o, c}:
      lo.mk(w, o, c)

def split(+b: Budget) -> Budget & Budget:
  (lo(b), hi(b))

def cap.mk(+w: U32, +o: U32, +c: U32, inner: Budget) -> Budget:
  match inner:
    case Budget{x, y, z}:
      Budget{U32.min(w, x), U32.min(o, y), U32.min(c, z)}

# cap: the budget a nested call actually gets, meterwise min of what the caller
# has and what the callee asked for. This is the law the lane exists for --
# nested code cannot raise a limit, because the only door in is this one and min
# is never above its left argument.
def cap(outer: Budget, inner: Budget) -> Budget:
  match outer:
    case Budget{w, o, c}:
      cap.mk(w, o, c, inner)

# -- the Result convention ---------------------------------------------------

# The package convention from lane 1 is that an unbounded operation takes a
# Budget and returns the unspent remainder beside its answer -- `Done{(b, x)}`,
# which needs no helper. What does need one is the chain: `fold` charges the next
# step onto a Result that may already have refused, so a caller spends a sequence
# without writing a match a step, and the first refusal is the one that is kept.
def fold(r: Res(Budget), +m: Meter, +n: U32) -> Res(Budget):
  match r:
    case Fail{e}:
      Fail{e}
    case Done{b}:
      spend(b, m, n)
