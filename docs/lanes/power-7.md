# power-7 — Select: the pack, not the top K (2026-09-20)

Ranking hands back the K items that each score highest, which over any real
candidate pool is K near-duplicates — the second copy of the best chunk scores
almost exactly what the first one did. `power/select.bend` scores a *set* by how
much of the ground it covers and takes the item with the most **new** coverage
per unit cost: facility location under a lazy greedy, which is what a context
packer under a token budget actually wants.

The fixture makes that difference a measured fact and not a claim. On the
one-cluster ground at budget 50, ranking by standalone gain per cost takes

    8 1 12 10 15 14 7 5 0 3

and this file takes

    8 1 12 10 7 5 11 15 14

— and `select_gen.py`'s `audit()` **refuses to print the fixture** if those two
lists ever agree, because a fixture on which a ranker and a submodular packer
give the same answer is a fixture testing a ranker.

## What shipped

### `power/select.bend` — budgeted submodular selection with witnesses

    f(S)  = sum_i  val[i] * max_{j in S} sim[j][i]
    d(j)  = sum_i  val[i] * max(0, sim[j][i] - cov[i])   >> 12, one term at a time

- `Ground{n, sim, val, cost}`, `of_lists(n, sim, val, cost)`, `size(g)` — `sim`
  is n·n cells row-major **by candidate**, so it need not be symmetric and a
  candidate need not cover itself best. `val[i]` is what it costs to leave
  element i uncovered, and is the only place a per-element prior enters.
- `budgeted(g, required, budget, limit) -> Ground & Run` — the door.
- `Run{left, room, total, count, picks, why}` with `left/room/total/count/
  chosen/why` — pops still allowed, budget still unspent, f(S), how many, the
  picks in the order taken, and which of four things stopped it.
- `Pick{item, gain, cost}` — **the witness, and the reason this lane exists in
  the shape it does.** `gain` is the marginal coverage the item added *at the
  moment it was taken*, not its standalone value; the two differ by exactly what
  the earlier picks already covered. Lane 19 wants a proof-carrying answer, and
  a set with no gains attached cannot carry one. The gains telescope, so
  `total == sum of every pick's gain == f(S)` — an identity the fixture prints
  on every row and therefore pins.
- `Stop` = `Full` (budget cannot buy another item) · `Dry` (nothing left adds
  anything) · `Over` (the `required` list does not fit) · `Bad` (the `required`
  list is malformed), with `show` and `halted`.
- `ratio`, `key`, `term`, `gain`, `cover`, `one()`, `top()` — the arithmetic,
  exposed, for the same reason bm25 exposes `idf`: a choice nobody can re-derive
  is not explainable.

`required` items are forced in first, in the order given, **charged against the
budget before a single candidate is scored**, and each one's gain is measured
against only the required items ahead of it. So `[0, 5]` and `[5, 0]` pick the
same set in the given order with *different* gains, and the fixture carries both.

### The lazy rule, and why the answer is the plain greedy's exactly

A marginal gain is non-increasing in `cov` term by term, so a **stale** gain is
an upper bound on a fresh one. Keep the candidates in a max-heap keyed by their
last computed gain-per-cost, pop the top, recompute it, and if the fresh value
still beats the next item's stale bound, take it — every other candidate's true
gain is under its own bound, which is under this one. Otherwise reinsert at the
fresh value and pop again.

A round costs one O(n) recomputation instead of n of them. The answer is not an
approximation of the greedy's; it **is** the greedy's, which is exactly what
`tests/power/select.bend` pins against an O(n²) CPython rescan that has never
heard of a heap.

Two things follow and are stated in the file:

- **The loop cannot cycle.** A reinserted item's fresh key is never *lower* than
  the stale one it replaced, and equality would have won the test — so a
  reinsert strictly increases the key.
- **The pop ceiling is `n² + 2n + 4`, and it is proved, not guessed.** Every pop
  drops, takes or reinserts; drops and takes are each at most once an item, and
  between two takes the coverage does not move, so an item reinserted once holds
  its true value and wins the next test — n(n+1) reinserts at most. Both benches
  pass that number as `limit`, so it never binds and every run stops on its
  budget. `select_gen.py` computes it as `bound(n)` from the same formula.
- **An unaffordable item is dropped for good, not reinserted.** `room` only
  falls, so nothing priced past what is left now can be afforded later.

## Rule 7 — fixed point at 2^12, not F32, and the reason is not the one power-6 gave

power-6 refused an F32 heap key because integer addition is exactly
associative. That argument does not apply here — this lane has no fork inside a
selection to reassociate. Three different reasons carried it:

1. **The oracle.** A CPython reference in floats and a C twin in floats agree to
   a tolerance; the whole value of `select_gen.py` is that it agrees **byte for
   byte**, so a one-ulp `gain` that flips one comparison is caught rather than
   tolerated. Selection only ever *compares* gains — it never needs them
   accurate — so precision buys nothing and costs the exactness.
2. **The C backend defect.** An `Array<F64>` written from a recursive loop comes
   back corrupted today (`docs/omen/f64-drop-c-backend.md`). A float gain
   vector would have walked straight into it.
3. `Vec` holds U32 and `Heap` keys on U32, so a float would ride as a bit
   pattern with no law back — the same wall power-6 named.

**The shift is per term and not on the sum.** `sum of floors != floor of sum`,
and the CPython oracle shifts in the same place over the same integers in the
same order, which is the only reason the two sides can be compared for equality
at all.

## The apricot deviation, stated

apricot is `SelectionMethod='lazy'` over a **uniform-cost, cardinality**
constraint — pick k items. This file is the **knapsack** version: an item is
worth its price, `cost` is per item, and the greedy maximizes gain *per unit
cost*, not gain. That is the constraint a context packer has (tokens,
milliseconds, dollars), and it is a different algorithm at the key: `ratio`, not
`gain`, orders the heap.

Two consequences, both deliberate:

- **No cost-benefit greedy pair.** The knapsack greedy's standard 1−1/e
  guarantee needs `max(ratio greedy, best single item)`. This file returns the
  ratio greedy alone. The single-item comparison is one extra pass and a `max`,
  and it changes the *answer*, so it belongs to a caller that wants the bound —
  not hidden inside a primitive whose fixture pins exact picks. Listed as a
  ceiling below.
- **No k cap.** The budget is the only limit. A caller wanting "at most k" sets
  costs to 1 and the budget to k, which is exactly apricot's constraint
  recovered as a special case.

`ratio` is scaled by 2^8 so a cheap small gain still outranks an expensive one,
and **floored at 1 for any positive gain**, so `ratio == 0` means `gain == 0`
and nothing else. The loop stops on a zero gain and must never be told a real
one is zero because its cost was large.

## Verified

`bash tests/power/run.sh select` — **104 rows, `PASS: 6, FAIL: 0`**: oracle,
check, interpret, js, c, c-1thread.

**`tests/power/select_gen.py` is a plain O(n²) CPython greedy** — lists, a full
rescan of every candidate every round, no heap and no bound anywhere in it. It
is not a second copy of this implementation; it is the algorithm the lazy rule
claims to reproduce, written the slow way. A row prints

    <why> <room> <total> <count> [item:gain:cost ...]

so it pins why the run stopped, what is left of the budget, the objective
reached, and **every pick with the marginal gain it was taken for**. A set is
easy to get right by accident; a sequence of marginal gains is not.

Nine families: a budget sweep over one ground (every earlier pick and gain has
to reappear unchanged in the longer row), `required` in both orders, the three
refusals and the two ways to spend nothing, `limit = 0` (the greedy never runs,
the required items still do), one cluster (every item a near-duplicate — the
case top-K gets wrong), no clusters, three mid-size grounds, the degenerate
n = 1/2/3, and eleven **scaled-cost** rows at k = 4096 and 8192.

`audit()` fails the *generator* rather than ship a fixture that cannot catch
anything: all four `Stop` arms must appear, some row must select a pack of ≥ 6,
the top-K contrast at the head of this report must hold, and — stripping
`ratio`'s floor and re-solving — at least one scaled row must move. That last
assertion exists because M4 below walked through an earlier fixture untouched.

### What the fixture deliberately does **not** print

**`left`** — the pops a run actually spent. It is lazy-greedy-specific, and a
plain O(n²) CPython greedy cannot predict it without becoming a lazy greedy,
which would destroy the oracle's independence. The cost is a real blind spot,
named here rather than hidden: M5 below is invisible to the fixture. **The bench
closes it** — `twin_select.c` folds `left` into the checksum, so the C twin has
to reproduce the lazy schedule pop for pop, not merely reach the same set. Two
implementations can agree on the answer and disagree on the work, and the work
is what the bench measures.

### Mutants — seven, run from `/tmp/sel_mutate.py`, none left in the tree

| # | mutant | caught by |
|---|---|---|
| M1 | lazy test dropped: the stale bound wins outright, no reinsert | fixture, **61 rows** |
| M2 | `required` items not charged against the budget | fixture, **35 rows** |
| M3 | total coverage, not marginal: `term` forgets `cov` | fixture, **74 rows** |
| M4 | `ratio` loses its floor at 1 | fixture, **4 rows** |
| M5 | a reinsert costs no pop (`left` is not ticked) | **bench only** — C 3024064962, mutant 643053521 |
| M6 | `cover` takes the min instead of the max | fixture, **74 rows** |
| M7 | heap key not complemented: worst ratio first | fixture, **72 rows** |

M4 is the one that earned its keep. **It originally survived both the fixture
and the bench**, because every cost in the file was in 1..12, so `g << 8 < c`
never held and the floor never fired. The fix was not a bigger fixture but a
*different regime*: a cost scale `k` threaded through generator and fixture, and
eleven rows at k = 4096/8192 where a real tail gain over a real cost quantizes
to zero. A cost is tokens, or milliseconds, or dollars, and nothing says it
shares a scale with the coverage — the fixture had been testing only the half
of the input space where it does.

M5 is the one that stayed alive against the fixture by design, and it is the
reason the bench checksum folds `left` at all.

## Measured (Ryzen 7 7700X, 8 cores / 16 threads, `--gpu off`)

| bench | what it runs | C | bend 1T | bend 16T | 1T/C | 1T→16T |
|---|---|---:|---:|---:|---:|---:|
| `select` | 32 grounds of 1,024 × 1,024, each packed to a budget of 6,000 | 0.12 | 0.37 | 0.37 | 3.2x | 1.0x |
| `select_par` | 2^7 shards, each its own ground and its own budget | 0.46 | 1.50 | **0.33** | 3.2x | **4.5x** |

33.5 million similarity cells sequential, 134 million forked. **The grounds are
clustered on purpose** — 32 clusters, so ~32 near-duplicates each — and that is
the *adversarial* ground for lazy greedy, not the easy one: taking a cluster's
first member collapses the bound of every other member at once, and a collapsed
bound is exactly what forces a reinsertion instead of a take. A uniform ground
would make this bench look faster and mean less.

Checksums: `select` 3024064962, `select_par` 2310228381, each identical on C,
1T and 16T. Both fold the four counters and then **every pick** as
`(item*31 + cost) ^ gain`, through json_par's `rot7(acc*31 + x)` mixer for the
reason power-6 records — a leaf checksum is itself a `·31 + x` fold, and 31 ≡ −1
(mod 32), so a plain tree combine runs the low bits out.

`select.bend` has no fork, so its 1T and 16T columns are the same run twice.
**The 3.2x single-thread ratio to C is identical in both rows**, which is the
useful reading: it is the cost of the primitive itself — the gain loop, the heap
and the Vec reads — and it does not change with the shape of the work above it.

**Measured with other lanes live on the machine** (load average ~5.6, several
sibling benches queued on the same `flock`), so 4.5x on 16 threads is a floor
and not this bench's ceiling. The ratio to C and the checksums are unaffected by
load; the absolute seconds are. Stated rather than re-run in quiet, because the
gate takes medians on the cluster and this table is the lane's own reading.

**The shard is the unit of parallelism, not the gain recomputation.** Two
reasons, and the second is the one that matters:

1. A `Ground` holds Arrays and an Array has one owner, so no two lanes can read
   one similarity matrix — the same wall lanes 5, 6 and 8 hit.
2. **Inside one selection the rounds are strictly sequential by construction**:
   round k+1's gains are defined against the coverage round k left. The only
   width a single run offers is the first round's n independent gains, which is
   one O(n) pass out of an O(n · rounds) algorithm. Packing *many* contexts at
   once is the workload that has width, and it is the one a context packer runs.

## Written for Bend

- **`Ground` and `St` are kind `Type`** (they hold Arrays), so the answer cannot
  ride in a `Result`: a kind-`Type` value beside an answer forbids it. `Run`
  therefore carries `left` in its **first** field and `why` plays the part of the
  error arm — `power/json.bend`'s move, for the same reason, and the lane-1
  convention (an unbounded loop takes a `limit` last and hands the remainder back
  first) preserved through it.
- **`budget` and `limit` are different things and do not compose.** `budget`
  bounds what is selected and is charged per item taken; `limit` bounds how long
  the search may run and is charged per heap pop. Either may bind first, and
  `why` says which.
- **Field order is affinity.** `Gs{acc, sim, val, cov}` puts the accumulator
  *first* so it can be marked `+` — a `+` is refused on a constructor pattern's
  last field, and the caller both keeps the gain and prices it. `St{n, run, ...}`
  puts `run` second for the same reason.
- **The `+` marker is needed even across `match` branches.** `step.hot` uses `r`
  exactly once per arm of a two-arm match and still needed `+r`. `step.room` has
  the same shape and does not. The branch exemption is not something to rely on.
- **No mutual recursion outside Base**, so the round loop is one self-recursive
  `loop(fuel, Step)` over a `Fin`/`Go` state with every phase as a non-recursive
  helper. `Fin`, not `Halt` — Base already declares `Halt`.
- The fuel is `1n + U32.to_nat(limit)`, one more than the limit, so **the limit
  is what actually stops the run and the fuel is only the checker's proof that it
  stops at all**. Bare operators need the annotation since 2.0.16:
  `(1n + U32.to_nat(limit) : Nat)`.
- **A refused run is an answer and is not overwritten.** `step.hot` and
  `build.hot` gate on `halted(why(r))` so an `Over` or `Bad` run neither takes a
  further item nor has its `why` replaced by `full` on a later round. `build.hot`
  also skips the one O(n²) pass in the whole primitive, so a request that was
  already refused does not pay for it. This was a real bug — 9 of 93 rows failed
  on it before the gates went in.
- **Ties are settled by the heap's own val.** The key is `(MAX − ratio, index)`,
  so highest ratio then lowest index, and the order is *total*. That is why
  `twin_select.c` is free to use a plain sift heap instead of `heap.bend`'s
  hole-carrying pair: every correct min-heap pops a total order in the same
  sequence.
- The JS lane's statement ceiling is still binding on fixture size — the emitted
  `do IO<Unit>:` block is one nested closure a statement and V8 gives out past
  roughly 300. 104 rows sits well inside it.

## Deliberate ceilings

- **No cost-benefit pair, so no 1−1/e bound.** See the apricot deviation. One
  extra pass and a `max`, in a caller.
- **`top()` is 2^24−1.** `top() << 8` is under 2^32, so the ratio key cannot
  wrap; with weights at `one()` that is a ground set of 4,096 fully uncovered
  elements, past which the key stops discriminating. Marked `ponytail:` in the
  file — the upgrade is a 64-bit heap key, which is a change to
  `power/heap.bend` and not to this file.
- **No stochastic or sieve greedy.** apricot's `'sample'` and `'sieve'` modes
  trade exactness for speed on n in the millions. This file's fixture is an
  *exactness* argument; a sampled greedy would have no oracle.
- **No sparse `sim`.** The ground is n² dense cells. A real candidate pool with
  a sparse similarity graph wants a CSR `sim`, which is `power/bm25.bend`'s row
  table applied here — a `Ground` field and a changed inner loop, not a redesign.
- **`sim` is given, not computed.** Embeddings → similarity is lane 8's (KNN).
- **No incremental add or remove.** A `Ground` is fixed at construction.

## Battery

power 6/0 on 104 rows · bench 2/2 checksums match C · caps ok.

`power/select.bend` 8,017 ttok against the 64,000 cap; `tests/power/select.bend`
10,285 and `tests/power/select_gen.py` 5,059 against 16,000; the two benches
1,801 / 1,717 and the two twins 1,830 / 1,981. **No cap moved, and
`gates/repo.ts` needed no new row** — the existing `tests/power/…` and
`power/*.bend` rules already cover every file this lane added.

No `bend2/` change of any kind: no `comp.ts` native row, no `base.bend` edit, no
new effect. The lane needed none. No `@unsafe`, no `?TODO`. `twin_select.c` and
`twin_select_par.c` are this lane's own files; the shared `twins.c`,
`tests/power/run.sh`, `tests/power/bench/run.sh` and `tests/caps.sh` were not
touched.

## Next

Lane 19, proof-carrying results, is the consumer this lane was shaped for:
`Pick{item, gain, cost}` is already a witness, `total` is already the sum of
them, and `why` already says which constraint bound. What it will want and this
file does not have is a *certificate* — the losing candidate and the bound that
lost, so a caller can verify a pack was optimal-for-the-greedy without re-running
the greedy. That is one extra `Pick` field written at the lazy test, where both
numbers are already in hand.
