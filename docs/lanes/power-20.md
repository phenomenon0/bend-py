# power-20 — Budget: the allowance as a value (2026-09-20)

Lane 20 of the plan. It was scheduled after lane 15, and it is written here
because it is the one lane in wave 4 that depends on nothing: three U32s and
their algebra. It is also the lane that settles a debt. The plan wrote the
budget convention into wave 1 — `limit: U32` last, `Result<Err, (left, value)>`
back — and after six lanes that convention appears in exactly one primitive:

    $ grep -c limit power/*.bend
    power/json.bend:10

Not because the convention is wrong, but because every other lane's work is
bounded by its input. `Radix.sort` over a Vec of n does n log n and stops;
there is no allowance to hand it that the Vec does not already imply. Json is
the odd one because its input is a *stream* whose cost is not a function of its
length — a hostile 200 MB string costs what you let it cost. This lane makes
the allowance a first-class value rather than a parameter convention, so the
primitives that do need one share an algebra instead of each inventing a `left`
field.

## What shipped

`power/budget.bend`, standalone — it imports Base and nothing else in `power/`.

- `type Meter is Data: Work{} | Out{} | Calls{}` — the three meters.
- `type Budget is Data: Budget{work, out, calls}` — three U32s and nothing else.
- `type Error is Data: Dry{m: Meter}` — a refusal names the wall it hit.
- `Res(T) = Result<Error, T>` — the lane's return type.
- `new(w, o, c)`, `none()`, `all()` — construction.
- `left(b, m)`, `set(b, m, n)`, `afford(b, m, n)`, `is_empty(b)` — reading.
- `spend(b, m, n) -> Res(Budget)` — pay before building, or `Fail{Dry{m}}`. A
  refused charge spends nothing; there is no partial pay.
- `take(b, m, n) -> Budget & U32` — the same charge capped instead of refused,
  handing back what was actually granted, for a loop that wants to do as much
  as it can afford rather than refuse the batch.
- `used(started, now, m)` — how far a meter moved, clamped at 0.
- `join(a, b)` — two remainders become one, saturating.
- `lo(b)`, `hi(b)`, `split(b)` — the two halves a binary fork hands its
  children.
- `cap(outer, inner)` — meterwise min: the only door into a nested call.
- `fold(r, m, n)` — charge the next step onto a `Res` that may already have
  refused, keeping the first refusal.
- `show.m(m)` — the meter as text.

## Three meters, and why memory is not one of them

A meter is defined by *when* it is charged, not by what it measures:

    Work   as effort is spent            one step, one byte scanned, one compare
    Out    as the answer is built        a cap on the result, not on the effort
    Calls  as something expensive or irreversible is done     an IO round trip

Those are three different charge points, so they cannot share a counter: a
search that is cheap per step but returns a million rows is not the same
failure as one that grinds for an hour and returns nothing, and a caller that
wants to bound model calls does not want to bound compares.

**Memory is deliberately excluded.** Memory is a high-water mark: it is charged
with `max` and released on the way out, not subtracted and kept. Putting it in
this record would make two of the four laws below false — `join` would have to
take a max on one field and a sum on the others, and `used + left == left` has
no meaning for a gauge that goes back down. A high-water meter is a different
record with a different algebra, and merging them would buy one type at the
price of every law on it.

## The four laws

Each is asserted in `tests/power/budget_gen.py`'s `law()` before any row is
emitted, *and* pinned as a row in `tests/power/budget.bend`:

    afford(b, m, n) == is_done(spend(b, m, n))   a caller cannot be told yes
                                                 and then refused, or the reverse
    join(lo(b), hi(b)) == b                      a fork neither loses nor invents
    cap(outer, inner) <= outer, meterwise        nested code cannot raise a limit
    used(b0, b, m) + left(b, m) == left(b0, m)   nothing leaks

The fixture's shape follows from them. A row carries **both sides of one claim
in one string**, so an implementation that satisfies one side and not the other
cannot print the line at all:

    pair(B.afford(b, Work{}, 10), B.spend(b, Work{}, 10))   ->  "1 0 5 2"
    acct(b0, b, Work{})                                     ->  "17 17"
    halves(b)                                               ->  "4 3 2 | 3 2 1 -> 7 5 3"

`acct` prints `used + left` beside `left(b0)`; two different numbers is the
leak. `halves` prints lo, hi and their join beside each other; the parent is
the third field. That is why the mutants below all die on four lanes at once
rather than on one lucky row.

## The finding: kind `Data` is what makes a Budget forkable

power-5 recorded a deviation — Json carries its allowance inside its own state
instead of returning it in a `Result` — and blamed the `Result` convention.
That was the wrong culprit, and this lane names the right one (Rule 7).

`Bytes`/`Vec`/`Bitset` contain an `Array`, so their kind is `Type`: affine,
single-owner. `Result` payloads must be kind `Data`. **It was never the
allowance that forced Json's deviation; it was the payload beside it.** A
Budget is three U32s, kind `Data`, and rides inside a `Result` without trouble.

The same fact shows up again in the fork, and it is why `lo` and `hi` exist
separately from `split`. The first draft had `split(b) -> (Budget, Budget)` and
a recursive tree that destructured the pair and recursed:

    def ft.go(...): ... ftree(...)     # "expected: a defined name, observed: ftree"

A computed pair cannot be destructured mid-body in Bend, so it has to go to a
helper as a parameter — and that helper has to call the recursive function,
which is defined after it. Mutual recursion is rejected outside Base. The fix
is not a workaround, it is the better shape: because a Budget is kind `Data`,
**both children can derive their own half from the same parent value**, and
nothing has to thread a pair down the recursion at all.

    a x = par(p, lo, h, B.lo(b)) par(p, U32.add(lo, h), h, B.hi(b))

An affine primitive has no such luxury — a `Vec` must be split into two halves
and each handed to exactly one side. That is the whole difference between
forking a Budget and forking a Vec, and it is the reason this lane could be
written at all.

`lo` takes the **ceiling** and `hi` the floor, so the two sum to the parent
exactly. An odd allowance is never rounded away, and `join(lo(b), hi(b)) == b`
holds at every depth of a tree rather than only at even numbers. At depth 8
over `all()` a floor/floor split would lose up to 255 units per meter; the
fixture catches it at depth 1 over `Budget{7,5,3}`.

## Verified

`tests/power/budget.bend` — 174 rows, generated by `tests/power/budget_gen.py`
from three CPython ints, on six lanes: oracle, check, interpret, js, c,
c-1thread.

    Power PASS: 6, FAIL: 0

The oracle is independent: `Ref` is a 3-tuple of Python ints with `min`, `>>`
and saturating add, and it knows nothing about Bend's file beyond the four laws
it is asked to satisfy. Every budget the fixture mentions goes through `law()`
first, so a row that breaks a law cannot reach the file — the fixture cannot
pin a bug that both implementations share.

Eleven budgets carry the file: empty, one unit, the working shape `{10,5,2}`,
the odd `{7,5,3}` that only an exact `lo`/`hi` survives, the saturated
`all()`, and six drawn from a seeded RNG so the laws are not checked only on
numbers a human would pick.

### Mutants

Six single-line changes to `power/budget.bend`, each the plausible wrong
implementation, all six caught. `PASS: 2` is oracle + check — the fixture file
and the typechecker are unaffected by a semantic mutation, which is the point:
the four *running* lanes are what refuse it.

| mutant | result |
|---|---|
| `lo` takes the floor too, so an odd allowance is rounded away | PASS 2 / FAIL 4 |
| `join` adds without saturating, so a fork invents budget at the ceiling | PASS 2 / FAIL 4 |
| `afford` is strict, so spending exactly what is left is refused | PASS 2 / FAIL 4 |
| `cap` takes the inner budget, so nested code raises its own limit | PASS 2 / FAIL 4 |
| `take` is uncapped, so a charge past the meter wraps | PASS 2 / FAIL 4 |
| `used` is unclamped, so a `now` past its start reports a near-2^32 spend | PASS 2 / FAIL 4 |

## Measured

`tests/power/bench/budget.bend` runs 204,800,000 charges through `B.fold` —
the library's own chaining primitive, not an inlined copy of it. The meters
start at `all()` and the run spends about 307,000,000 of each, so nothing ever
runs dry: the branch `fold` takes every step is the branch C takes, and the row
is the threading cost and nothing else. The twin is `twin_budget.c`: three u32
meters in an array and a bounds test a charge.

    bench             C  bend-1T bend-16T    1T/C  1T/16T
    budget         0.16     0.34     0.36    2.2x    1.0x
    budget_par     0.16     0.33     0.06    2.1x    5.4x

**2.2× C, 5.4× on 16 threads.** Carrying an allowance down a loop costs what
carrying three integers costs — the 2.2× is the same constant every scalar lane
in this package pays (bitset 2.1×, radix 2.0×, vec 2.2×), so the Budget adds
nothing measurable over the loop it rides in.

`budget_par` prints **the same checksum as the sequential run and as C**, and
that identity is the row. It forks into 2^8 ranges of 800,000, each handed its
own half of the allowance by `lo`/`hi` on the way down and joined back on the
way up. Because `lo + hi == parent` exactly and `join` sums the remainders
back, the final accounting does not depend on the schedule at all. A split that
rounded, or a join that saturated early, would print a different number and the
harness would refuse to time it — the bench is a law check that happens to also
be a stopwatch.

The whole suite, run under contention with four other lanes building:

    bench             C  bend-1T bend-16T    1T/C  1T/16T
    bitset         0.29     0.60     0.60    2.1x    1.0x
    bm25           0.67     2.65     2.32    3.9x    1.1x
    bm25_par       0.33     0.69     0.12    2.1x    6.0x
    budget         0.16     0.34     0.36    2.2x    1.0x
    budget_par     0.16     0.33     0.06    2.1x    5.4x
    bytes          0.20     0.33     0.33    1.6x    1.0x
    heap           2.75     2.10     2.27    0.8x    0.9x
    json           0.08     0.37     0.35    4.9x    1.1x
    json_par       0.06     0.34     0.06    6.1x    5.5x
    knn            0.12     0.14     0.14    1.2x    1.0x
    knn_par        0.44     0.62     0.15    1.4x    4.1x
    radix          0.18     0.37     0.38    2.0x    1.0x
    radix_par      0.12     0.29     0.05    2.4x    5.6x
    rng            0.39     0.39     0.39    1.0x    1.0x
    rng_par        0.39     0.39     0.06    1.0x    6.0x
    scan           0.41     0.90     0.83    2.2x    1.1x
    scan_par       0.27     0.46     0.10    1.7x    4.7x
    topk           0.30     0.46     0.46    1.6x    1.0x
    topk_par       0.29     1.53     0.27    5.3x    5.7x
    vec            0.28     0.60     0.59    2.2x    1.0x

Every figure is a median of three under `flock /tmp/bend-bench.lock`, with four
subagent lanes compiling on the other cores — so these are a few percent slower
than the quiet-machine numbers in power-1..6 and should be read as a table, not
against them.

## A bug in the harness, found and fixed

The twin-per-lane change made earlier in this session (`twin_<bench>.c` beside
a bench, so concurrent lanes cannot corrupt a shared `twins.c`) used `set --`
to build the twin's command line. `set --` rebinds `$1`. The prefix filter on
the next line reads `$1`. From the second iteration onward every bench was
compared against the *twin's path* instead of the prefix and skipped.

    bench             C  bend-1T bend-16T    1T/C  1T/16T
    budget         0.15     0.33     0.34    2.2x    1.0x     <- budget_par missing

`tests/power/bench/run.sh` now holds the prefix in a name (`only`) and the twin
command in an array, and the full run is 20 rows again. This is worth stating
plainly: **for the span of this session, any `bench/run.sh` invocation silently
timed only its first matching bench.** The lane-1..6 tables in those reports
were measured before that edit and are unaffected; the table above is the first
full run since.

## Deliberate ceilings

- **No `Inf` meter.** `all()` is max on every meter, not a fourth constructor.
  A real infinity would need an `Inf` arm in each meter and a case in every
  operation, to buy a distinction nothing in this library can reach: 2^32-1
  steps at one nanosecond is four seconds, and 2^32-1 calls is not a program.
  Marked `ponytail:` in the file.
- **No memory meter**, for the reason above. When a high-water gauge is
  actually wanted it is a second record with `max` for its join.
- **No risk meter.** The plan lists risk beside work/memory/output/model-call.
  Risk is not a scalar anyone can spend — it is a policy over the `Calls`
  charge point, and it belongs with the consequence-preview lane (18), which is
  where a "would this action differ?" test already lives.
- **`fold` chains `spend`, not `take`.** A capped charge has a second half to
  hand back, so it cannot chain through a `Res(Budget)` without a pair. A loop
  that wants `take` writes its own accumulator; the benches do exactly that.
- **No fairness in `lo`/`hi`.** The left child gets the ceiling every time, so
  a shallow tree over a tight budget favours the left spine. Exact is what the
  law needs; even is what a scheduler would want, and no consumer wants it yet.

## Battery

power 6/0 for `budget` (+ control) · repo 54/54 · caps ok · bench 20/20
checksums match C · 6/6 mutants caught.

`power/budget.bend` is 2,487 ttok against the 64,000 cap. The fixture, the
generator, the two benches and the C twin are 7,936 / 3,293 / 437 / 713 / 256
against 16,000. No cap raised, no `gates/repo.ts` rule added — the lane-0 rules
already cover `power/*.bend` and `tests/power/**`. No `comp.ts` row, no
`base.bend` change, no new effect: the lane needed none.

The one file outside the lane that changed is `tests/power/bench/run.sh`, for
the `set --` fix above and to route `budget_par` at the `budget` twin, the way
`rng_par` and `topk_par` are already routed.

## Next

The remaining wave-4 lanes all have a consumer for this one. Lane 19
(proof-carrying results) wants `Calls` to bound how much verification an
untrusted answer may buy; lane 17 (forkable grammar state) wants `lo`/`hi` to
divide a beam's allowance across its branches; lane 16 (delta-native) wants
`Out` to bound how large a delta may grow before it is cheaper to rebuild. And
Json is the first primitive to retrofit: its state-owned `left` is a `Work`
meter by another name, and `start(b, limit)` becomes `start(b, budget)` once
there is a second caller that cares.
