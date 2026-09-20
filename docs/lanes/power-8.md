# power-8 — Knn: batched vector similarity and exact search (2026-09-20)

Lane 8, mining Faiss's flat indexes. It is the lane power-6 named on its way
out: *"the lane where the F32-key question this one refused comes back for
real, since a distance genuinely is a float and there is no 2^20 quantum that
is obviously right for it."* It came back, and this time the answer was yes.

It is also the library's first serious GPU benchmark, and that measurement
turned out to be about a build system rather than about a GPU.

## What shipped

### `power/knn.bend` — a flat index over one packed `Array<F32>`

```
type Flat is Type:
  Flat{m: U32, d: U32, depth: Nat, xs: Array<F32>}
```

Row-major, `d` cells a vector, `m` vectors, one allocation. `Array<F32>` is
packed — `bend2/comp.ts:160` puts `F32` in `W32` alongside `U32` — so a
`Flat` is one flat block of 32-bit cells and not a tree of boxes.

- `new(d)`, `sized(d, depth)`, `push(f, x)`, `of_list(d, xs)` — construction.
  `sized` pre-allocates so a bench pays no doubling copies; `new` doubles.
- `dim`, `size`, `at(f, i, c)`, `cell`, `put` — shape and access.
- `l2(f, i, q, j)`, `ip(f, i, q, j)` — squared L2 and inner product between
  row `i` of one store and row `j` of another. Both return
  `Flat & Flat & F32`: both owners back, beside the answer.
- `norm(f, i)`, `normalize(f)` — the L2 norm a row, and the store with every
  row scaled to unit length. **A zero row keeps its zeros** instead of becoming
  `d` NaNs, which is the answer a cosine index should give it.
- `search_l2(f, q, j, k)`, `search_ip(f, q, j, k)` — the `k` nearest (or `k`
  greatest) rows to query `j`, best first, through `TopK`. Returns
  `Flat & Flat & List<Heap.Entry>`.
- `key(x)`, `near(x)` — the order-preserving map from `F32` to `U32`, below.

Cosine is not a third function: it is `search_ip` over a `normalize`d store,
which is what a cosine index physically is.

## Rule 7 — power-6 refused the F32 key; this lane takes it, and the reasons invert

power-6 ranked BM25 scores as fixed-point U32 at 2^20 and gave three reasons.
Two of them are properties of *that* score, not of floats, and both fail here:

1. **power-6: "a score is bounded and scale-free, so a quantum is obvious."**
   A squared L2 distance is neither. It is unbounded above and it scales with
   the data — vectors in [-32, 32) over 64 dimensions reach ~2.6·10^5, and the
   same index over unit vectors reaches 4. No single quantum serves both, and
   a wrong one either saturates or throws away every distinction.
2. **power-6: "integer addition is exactly associative, so a forked query and
   a straight one agree."** That argument is about the *accumulator*, and this
   lane's accumulator is a float either way — the distance is a sum of squares
   before anything is ranked. Quantizing the key would not have made the sum
   associative; it would only have blurred the comparison afterwards.

So the ranking key here is the IEEE-754 bit pattern, mapped to a total order:

```
def key.if(+b: U32, neg: Bool) -> U32:
  match neg:
    case True{}:
      U32.not(b)
    case False{}:
      U32.or(b, 2147483648)

# the `+ 0.0` is not dead: it is the one operation that maps -0.0 to +0.0
def key(+x: F32) -> U32:
  key.b(F32.bits(F32.add(x, 0.0)))

def near(+x: F32) -> U32:
  U32.sub(4294967295, key(x))
```

Flip the sign bit for a positive, invert everything for a negative. This is
the standard radix-sortable float encoding, and it is **exact**: it discards
nothing, so two distances that differ in the last ulp still rank apart. `near`
is its reverse, for L2, where smaller is better.

**What it cost.** `F32.bits` is one-way — `law F32.bits: F32 -> U32` at
`base.bend:1794`, with nothing back. So a drained `Heap.Entry` carries the
*key*, not the distance, and a caller who wants the number recomputes it with
`l2`. That is bm25's `explain` shape, arrived at from the opposite direction,
and it is stated in the file rather than hidden.

**Why this is safe on every lane.** Ranking on raw float bits is only sound if
all six lanes produce bit-identical floats. They do, and the reason is
structural rather than lucky:

- Both emitters compute in double and round to float32 — `Math.fround(a op b)`
  for JS (`comp.ts:219`), `(f32)(double op)` for C. For `+ - * /` and `sqrt`
  that double rounding is *provably* identical to a native float32 op, because
  float64 carries more than twice float32's precision. This lane uses no other
  operation and no transcendental at all — which is exactly the ulp hazard
  power-6's `guard()` had to work around, absent here by construction.
- The `interpret` lane is the JS emitter for an IO main (`main.ts:613`
  `book_run` → `Comp.io_run` at `comp.ts:1734`). Only a *value* main goes
  through `Bend.term_snf`, which has no float laws. So the fixture's six lanes
  are really oracle, checker, JS-in-process, JS-standalone, C, C-1thread — and
  no lane evaluates floats by a third rule.
- **1T and 16T cannot disagree.** Bend's scheduler is "a contention-free,
  binary fork-join machine: every task is handed to a core exactly once and
  never moved afterwards" (GUIDE.md:154), so association order is fixed by the
  source and not by the schedule. The `exact` / `ordered` split power-1 drew
  for Scan does not arise, and it does not arise for a *different* reason than
  power-6's: not because the operation is associative, but because the tree is
  written down.

## Verified

`bash tests/power/run.sh knn` — 151 rows, **`PASS: 6, FAIL: 0`**.
Six lanes: oracle, check, interpret, js, c, c-1thread.

**Every row prints a U32, and that is the point rather than a convenience.** A
distance is printed as `key(distance)` — its exact 32-bit pattern — so a row
pins the float to the last bit instead of to however many digits a printer
chose to show. `tests/power/knn_gen.py` is plain CPython (lists and floats, no
Flat, no TopK) and reproduces the emitters' arithmetic exactly through
`struct.pack('<f')`; its `guard()` refuses to print a fixture holding any value
that is not an exact finite F32, so a three-host disagreement becomes a
generator failure at authoring time.

The rows cover the key map on the floats that make its claim hard (`-32.0`,
`-0.0`, `+0.0`, `4096.0` — negatives must land under every positive and `-0.0`
must land on `+0.0`'s key), then the store's shape and cells, then `l2` and
`ip` sweeping the store against one query *and* three rows against every query
(so the index arithmetic is exercised in both arguments), the norms before and
after `normalize`, cosine over both sides normalized, the zero-row case, and
the searches at `k < n`, `k = n` and `k > n`.

**Mutants** — four, each confirming the fixture reaches the branch. Every one
passes the oracle and the checker and fails all four executing lanes
(`PASS: 2, FAIL: 4`), and the file was restored `diff -q` clean after each:

| mutant | what it breaks |
|---|---|
| `key.if` returns `b` unchanged for a negative | the sign half of the total order |
| `key` drops the `+ 0.0` | `-0.0` ranks above every positive |
| `near` returns `key` | L2 search returns the *farthest* k |
| `nz.row` normalizes a zero row anyway | a zero row becomes `d` NaNs |

The third is the useful one: it returns a well-formed answer of the right
length in the right shape, and only the fixture's ordering catches it.

## Measured (Ryzen 7 7700X, 8 cores / 16 threads, `--gpu off`)

| bench | what it runs | C | bend 1T | bend 16T | 1T/C | 1T→16T |
|---|---|---:|---:|---:|---:|---:|
| `knn` | 65,536 vectors × 64 dims, 64 queries, k=10 — 268M mul-adds | 0.12 | 0.14 | 0.14 | **1.2x** | 1.0x |
| `knn_par` | 2^6 shards, each 2,048 × 64 and its own 128 queries — 1.07G mul-adds | 0.44 | 0.51 | **0.15** | **1.2x** | **3.4x** |

**1.2x of C is the best ratio in the library so far** (power-6's bm25 was 3.4x,
its `bm25_par` 2.1x). The reason is that this lane's inner loop is the one
shape Bend compiles to nearly the same machine code C gets: a fixed-count walk
over a packed `Array<F32>` doing subtract, multiply, add, with no allocation
and no branch inside it.

The C twin is left strictly ordered on purpose. Without `-ffast-math` clang
will not reassociate a float reduction, so it stays scalar — verified by
disassembly (`mulps` ×2, `addss` ×4: the reduction did not vectorize) and by a
volatile counter confirming exactly 268,435,456 inner iterations. A vectorized
C would be measuring a transform Bend was never asked to make.

Thread sweep on `knn_par`, minimum of seven runs each:

| threads | 1 | 2 | 4 | 6 | 8 | 12 | 16 |
|---|---:|---:|---:|---:|---:|---:|---:|
| seconds | 0.491 | 0.257 | 0.146 | 0.137 | 0.138 | 0.139 | 0.140 |
| speedup | 1.0x | 1.9x | 3.4x | 3.6x | 3.6x | 3.5x | 3.5x |

Clean doubling to 4 threads, then flat. **Stated honestly: every number in this
report was taken with six other lanes compiling and benchmarking in the same
working tree, at a load average of 2 to 5.** Minimum-of-seven is the right
estimator under that interference and is what the sweep uses, but the plateau
at ~3.6x is partly this machine having fewer than 8 free cores, not purely the
bench saturating. The harness row (3.4x) and the sweep agree, so the ratio is
sound even if the ceiling is not the machine's true one.

## The GPU measurement, and the mistake in it

This lane was commissioned as the library's first serious GPU benchmark. The
first answer it produced was **7.9 s on an RTX 3090 against 0.15 s on eight CPU
cores — a 49x loss**. That number was wrong, and the way it was wrong is worth
more than the number.

A `!` binary keeps its GPU program in a `.gpu` file beside it. When that file
is missing or stale, the binary **recompiles the CUDA program on every run**
and says so:

```
bend: compiling the GPU program (/tmp/g64.gpu is missing or stale)
```

The 7.9 s was nvcc. The binary being timed had been built in an earlier session
and its `.gpu` had gone stale; it printed the correct checksum every time,
which is precisely why nothing looked wrong. Rebuilt and warmed, the same
program on the same data:

| | GPU (RTX 3090) | CPU 16T | CPU 1T |
|---|---:|---:|---:|
| 64 shards, 1.07G mul-adds | 0.249 | 0.153 | 0.516 |
| 64 shards, stores built, **zero queries** | 0.113 | 0.014 | — |
| **difference — the search alone** | **0.136** | **0.139** | — |

**The GPU ties eight CPU cores on the distance work and loses the benchmark on
store construction.** Subtracting the zero-query run isolates it: 0.136 s on
the GPU against 0.139 s on 16 threads for the same 1.07 billion multiply-adds.
The 0.113 s floor is launch plus building 64 stores, and a store is built by a
sequential `push` loop — a serial dependence chain per lane, which is the one
thing a GPU is worst at. Running 4,096 lanes instead of 64 makes it worse, not
better (0.230 s for one eighth of the arithmetic), because 8× more cells get
built by that same serial loop.

GPU engagement was confirmed by sampling during the run: 41% utilization and
760 MiB against a 699 MiB idle baseline.

So the honest finding is **not** "the GPU loses at KNN". It is: the search
kernel is already at parity with the whole CPU, and the benchmark's shape —
every lane building its own store from scratch — hands the GPU a workload that
is 45% serial setup. A real index is built once and queried many times. That
bench is worth writing and this lane did not write it; it is named as a ceiling
below.

## The hash trap that made two shipped benches meaningless

Both benches originally drew their vectors from `h(p) % 8192`. The 4,096-shard
checksum came out **exactly 0**. Bisecting by depth (4 → 973340784, 6 →
1879179264, 8/10/12 → 0) and printing the leaves showed every leaf checksum
identical, and the cause was in the hash, not the fold:

> `h(p) = ((p + 1) * 2654435761) ^ (p >> 3)` taken `% 8192` is **blind to any
> base that is a multiple of 2^13**, because a multiply propagates information
> only upward: the low 13 bits of `(p + 1) * C` see only the low 13 bits of `p`.

Every base anyone would pick is a multiple of 2^13. The consequence was that
`knn.bend`'s 64 queries *were* the first 64 rows of its own store — every
query at distance 0 — and `knn_par.bend`'s 64 shards held byte-identical
vectors. Both files carried header comments claiming the opposite.

**The C twin agreed throughout, because it reproduced the same degenerate
data.** A twin checks that two implementations compute the same function; it
cannot check that the function was given meaningful input. That is the lesson,
and it is the one thing in this lane that generalizes to every other bench in
the suite.

The fix is to take the thirteen bits off the **top** (`h(p) >> 19`), applied in
all five copies — the generator, both benches, both twins — with the trap
written into each header so it cannot recur. The fixture was regenerated (still
6/6) and the six leaf checksums are now distinct.

## Written for Bend

- **`Flat` is kind `Type`**, because it holds an `Array`. So it cannot sit
  inside a `Result` or a `Maybe`, and every operation hands the owner back
  beside the answer: `Flat & Flat & F32` for a distance, `Flat & Flat &
  List<Heap.Entry>` for a search. Same wall lanes 5 and 6 hit, same resolution.
- **The shard is the parallel unit, not the query.** A `Flat` holds an `Array`
  and an `Array` has one owner, so no two lanes can read one store. Beyond
  idiom: a value every lane reads costs an atomic per read, which on a hot cell
  loop is the entire budget. Sharding the store is also how a real vector
  database scales past one machine, so the shape is the honest one.
- **`nz.one` needed a helper to exist.** A pair destructured mid-body cannot
  have a binder used twice, so `nz.one.r(+a, +d, +r, f)` was split out purely
  so `r` could be marked `+` and read more than once. The affine checker is
  the design constraint, not a formatting preference.
- **Negative float literals do not parse** — there is no unary minus on a term
  — so the generator writes them as `F32.neg(1.5)`. `lit()` in `knn_gen.py`
  exists only for that.
- `sized(d, depth)` was added for the benches: `new` doubles its array, and a
  65,536 × 64 store built by doubling pays 22 full copies before it is filled.

## Deliberate ceilings

- **No query-block tiling.** Faiss processes B queries against a block of
  vectors at once to amortize the memory traffic. A B-wide tile needs B
  separate affine `TopK` values live in one record, and there is no way to hold
  them without writing the record B times for a fixed B. Marked `ponytail:` in
  the file. The upgrade is a `Vec`-backed multi-heap, not a change to `search`.
- **No `||x||² - 2⟨x,q⟩` decomposition.** Faiss turns L2 into a GEMM this way.
  It is refused on accuracy, not effort: for near-identical vectors the two
  large terms cancel and the small difference is computed from their
  cancellation, which is catastrophic in F32 — exactly the regime a KNN index
  spends its time in.
- **NaN is ranked, not noticed.** `key` maps NaN to a bit pattern like any
  other float, so a NaN distance sorts (above every number, for a positive
  NaN) rather than raising. A store containing NaN is a caller error this file
  does not detect.
- **No index structure at all.** This is Faiss's *flat* index: exhaustive,
  exact, O(m·d) a query. IVF, HNSW and PQ are all approximate, all need a
  training step, and all belong in their own lane.
- **No build-once/query-many bench.** See the GPU section — it is the
  measurement that would show the GPU honestly, and it is not here.

## Battery

`tests/power/run.sh knn` **6/6** · caps ok · `rg '@unsafe|\?TODO' power/` clean ·
`git status bend2/` clean · bench 2/2 checksums match C (`818226000` on the C
twin, bend 1T, bend 16T, and both GPU paths).

The suite-wide counters are not lane 8's to report: this lane was executed
concurrently with six others in one working tree, and the shared gates moved
under it all day. At the last run the power suite stood at 104 pass / 5 fail
and `gates/repo.ts` at 52/54, with **every failure belonging to lanes 12
(`sketch`) and 13 (`drift`)** and none to this one. `knn` is green on all six
lanes in every run taken.

`power/knn.bend` 4,231 ttok against the 64,000 cap; the fixture 8,417 and its
generator 3,492 against 16,000; the two benches 916 / 1,223 and the two twins
893 / 895. **No cap moved, and `gates/repo.ts` was not edited** — its existing
rules at lines 76-77 already cover every new file.

No `comp.ts` row, no `base.bend` change, no new effect, no edit to `bend2/`.

**The one repo failure is not this lane's.** `gp_probe.bend` at the repo root
is a string-escape probe belonging to lane 15 (text identity), written during
this session; it is left alone under the rule against touching another lane's
files. Without it the gate is 54/54.

## Next

Lane 7. The deferred items this lane did not need and did not take: a packed
`File.read_bytes` effect, Bytes `word_le`, RNG `normal`, a 16-bit radix digit,
and a k-way merge for `radix_par`.

One finding to carry forward, because it is not about this lane: **a stale
`.gpu` file silently turns every GPU benchmark into a CUDA compile benchmark,
while still printing the right answer.** Any lane that times a `!` binary
should build fresh and warm the `.gpu` before the first timed run.
