# power-16 — Delta: Z-sets, and the three terms of an incremental join (2026-09-20)

Lane 16. power-6 closed by saying that incremental indexing "is lane 16
(delta-native computation), which is where it belongs." This is that lane, and
it is the second consumer lane: `power/delta.bend` imports Vec, Scan, Radix and
Postings, and the only sort it performs is `Radix.reduce_by_key`.

The idea is DBSP's. A collection is a **Z-set**: every element carries a signed
integer weight, so `+1` is one copy, `+2` is two, and `-1` is a retraction of
one. Insert and delete stop being two operations and become one addition. Once
they do, every relational operator can be handed a *change* and answer with the
change to its own output — and a derived view costs the edit instead of the
collection.

Measured at the bottom: **131x at one thread**, and the two paths print the same
checksum, so the pair is a benchmark and an equivalence proof at once.

## What shipped

### `power/delta.bend` — the operator algebra

**Signed weights.** Two's complement in a U32: `+1` is `1`, `-1` is
`4294967295`. `U32.add` and `U32.mul` are the wrapping machine operations, so
signed add and signed multiply are the unsigned ones *unchanged* — only compare
(`is_neg`, `is_pos`) and print (`wshow`) have to know the sign. That keeps every
column a `Vec` of U32, which is the only element type an `Array` holds here, and
it keeps the C lane clear of the `Array<F64>` corruption a float weight would
have walked into.

- `ZSet{e, w}` — two parallel columns, a row is `(e[i], w[i])`.
- `empty`, `push`, `insert`, `remove`, `of_lists`, `size`, `total` — building,
  and the two counts that differ: `size` is rows, `total` is the signed sum of
  weights (the cardinality of the multiset).
- `consolidate(z)` — **the canonical form**: one row an element, elements
  ascending, and *no zero weight anywhere*. It is literally
  `Radix.reduce_by_key(~wadd, e, w)` followed by `drop0`. The stable sort puts
  equal elements adjacent, the run walk sums them, and `drop0` deletes every row
  whose total reached zero. There is no second sort in the file.
- `append`, `plus`, `negate`, `minus` — the additive group. `plus` consolidates;
  `append` is the un-canonical sum, which is what every operator that grows a
  collection actually produces.
- `map(~f, z)`, `filter(~p, z)`, `aggregate_delta(~key, ~val, z)`, `group(~key, z)`
  — the linear ones. `filter` keeps the weight *untouched*; `map` consolidates,
  because `f` may collide two elements onto one.
- `Ix{k, e, w}`, `index(~key, z)`, `unindex`, `ix_size` — a Z-set sorted by a
  key it does not store as part of its element.
- `join_ix`, `join`, `join_delta`, `absorb` — below.
- `distinct(z)`, `distinct_delta(st, d)` — below.
- `weight(z, x)`, `show(z)` — a single element's accumulated weight by binary
  search (0 for absent *and* for cancelled, which is the same thing), and
  `{e:+w e:-w}`.

### The bilinear join, spelled out

`join` is the only operator here that is not linear, and getting it wrong is
the classic DBSP bug. It is **bi**linear:

```
(a + da) join (b + db)  ==  a join b  +  da join b  +  a join db  +  da join db
```

so an incremental join must keep **both** inputs and produce **three** terms.
The third is second order in the change — small, and *not zero*: two rows that
arrive in the same step and join each other appear in no other term, because
neither of them is in `a` or `b` yet. `join_delta` is three `probe` calls
chained, all three accumulating into one output Z-set and sharing one row
allowance, with `a` and `b` handed back untouched and `da`/`db` consumed.

The join is a **probe**, not a merge: the kept side is indexed once and a delta
row costs one binary search (`Postings.lower` over the key column) plus its own
matches. That is the whole reason the number at the bottom is 131x and not 2x —
a merge join would still walk the kept side once per step.

### `distinct`, implemented honestly

`distinct` is **not linear** and the brief said not to fake it. Weight 3 means
three copies but one element, and weight 0 means no element, so no function of
the delta alone can answer. Both forms shipped:

- `distinct(z)` — the whole collection. Consolidate, then keep every element
  whose accumulated weight is strictly positive, at weight exactly 1.
- `distinct_delta(st, d) -> ZSet & ZSet` — the incremental form, and it takes
  the **accumulated state**, which is the honest signature. For each element of
  the change it binary-searches the state, compares presence before against
  presence after, and emits `+1` on became-present, `-1` on left, and *nothing*
  when the element was already there or still is not. It returns the updated
  state beside the output delta, so the caller threads it.

The fixture prints, beside every `distinct_delta` row, **the naive linear step**
— `distinct(d)` on its own — so the divergence is visible in the fixture rather
than asserted in prose. The generator refuses to emit unless at least four cases
actually diverge (`assert naive_differs >= 4`).

## The equivalence the lane is really about

`tests/power/delta_gen.py` computes every answer twice. For each case CPython
builds the changed collection and runs the operator on it **from scratch**, and
separately runs the incremental path, and the generator asserts they agree
before printing:

```python
assert zadd(base, delta) == full, "bilinearity fails in the oracle"
```

Then it prints *three* rows a join case — the recompute, the incremental sum,
and the delta alone — so Bend is pinned on all three and not merely on their
agreement. Six join cases, including one where `a` and `b` share no key with
`da` and `db`, so that case's **whole output is the second-order term**.

The oracle is `collections.Counter`, driven through `update` and never through
`+`. That is deliberate and documented in the file: `Counter.__add__` silently
drops non-positive counts, which is exactly the distinction this lane exists to
make. An oracle written the obvious way would have agreed with a broken library.

## Rule 7 — the recompute twin is the disagreeing pattern, kept on purpose

`tests/power/bench/delta.bend` and `tests/power/bench/delta_full.bend` are two
implementations of the same answer, which every other lane in this suite would
call a duplication to be deleted. It is the opposite here: the pair *is* the
claim. They print the same checksum because bilinearity says they must, and the
ratio of their times is the only number the lane is about. Deleting either one
leaves the other unfalsifiable.

Both C twins are their own files (`twin_delta.c`, `twin_delta_full.c`) and
neither touches the shared `tests/power/bench/twins.c`. The harness auto-compiles
every `twin_*.c` sibling at `-O3` and refuses to time a row until the twin,
`--threads 1` and `--threads 16` all print the same number — so all four
implementations agreeing on **3207137296** is four-way, two-language
verification of the three-term expansion.

## The budget deviation, stated (it is power-5's)

`join_ix`, `join` and `join_delta` take a row allowance `limit: U32` last and
hand the remainder back first, which is `power/budget.bend`'s convention. But
the refusal rides as a **field** of the answer record (`Jn.ok`) rather than as a
`Fail` arm, because `ZSet` and `Ix` are kind `Type` and cannot sit inside a
`Result`. This is the same wall and the same resolution `power/json.bend` hit
and power-5 recorded; it is not a new decision, and it is not a better one.

The allowance counts **emitted pairs, before consolidation**, because that is
the number that can blow up: `n` rows against `m` rows of one key is `n*m` pairs
and possibly one output row. The fixture pins `1:left` / `0:0` through a `jok`
helper and deliberately does **not** pin the partial output — a refused join's
partial answer is not a promise.

## Verified

`bash tests/power/run.sh delta` — **122 rows, `PASS: 6, FAIL: 0`**. Six lanes:
oracle, check, interpret, js, c, c-1thread. Eight sections: the canonical form;
map/filter linearity; `aggregate_delta` and `group`; the index round-trip; join
bilinearity; the row allowance; distinct's non-linearity; `absorb`.

**Mutants** — three, each confirming the fixture reaches the branch. Every one
passes the oracle and the checker and fails all four executing lanes
(`PASS: 2, FAIL: 4`):

| mutant | what it breaks | what the fixture printed instead |
|---|---|---|
| `jd.t2` returns its carried `Pr` instead of running the third probe | `da join db`, the second-order term | the isolating case `{328452:+1}` became `{}`; every mixed case lost its own second-order rows (`{... 131842:-3 131843:+1}` → `{... 131842:-3}`) |
| `cons.of` returns `ZSet{es, ws}` instead of `drop0(es, ws)` | consolidation dropping a total-zero row | `{}` became `{5:+0}`; `{9:+2}` became `{3:+0 9:+2}` — a retraction that cancelled an insert left a row behind |
| `filter.f` rewrites every kept weight to 1 | filter's linearity | `{1:-2 259:+1 260:+1 261:-2 ...}` became `{1:+1 259:+1 260:+1 261:+1 ...}`, and the incremental-equals-recompute row paired with it broke too |

**One of those three does not move the bench, and the bench used to claim it
did.** Mutant 2 leaves the benchmark checksum at 3207137296 unchanged: at these
sizes the three terms never cancel to exactly zero, so no zero-weight row is
ever produced and folding the row count into the checksum does not catch it. Two
comments asserting otherwise — in `tests/power/bench/delta.bend` and in
`twin_delta.c` — were corrected to say what was measured. The fixture is what
pins the zero-drop rule; the bench prices the algorithm.

## Measured (Ryzen 7 7700X, 8 cores / 16 threads, `--gpu off`, medians of three)

| bench | what it runs | C | bend 1T | bend 16T | 1T/C | 1T→16T |
|---|---|---:|---:|---:|---:|---:|
| `delta` | 128 updates of 8 rows a side against a kept 1,024 x 8,192 join | 0.00 | 0.01 | 0.01 | 1.7x | 0.9x |
| `delta_full` | the same 128 updates, both joins recomputed whole and subtracted | 0.71 | 0.84 | 0.83 | 1.2x | 1.0x |

The harness prints two decimals and the incremental row is under one of them.
The medians it is rounding:

| | incremental | full recompute | **speedup** |
|---|---:|---:|---:|
| C (`clang -O3`) | 0.003734 s | 0.719960 s | **192.8x** |
| bend 1T | 0.006756 s | 0.888076 s | **131.4x** |
| bend 16T | 0.006665 s | 0.877037 s | **131.6x** |

**That is the headline, and it is the honest one.** 1,024 rows joined against
8,192 rows over 128 keys — 64 matches a key, 65,536 pairs a full join — then 128
steps that each change 8 rows a side out of 9,216. The incremental path pays the
8 rows and a binary search; the recompute pays 9,216 rows and two whole joins,
twice, plus a subtraction, and has no way to know that 0.17% of its input moved.

Two honest qualifications:

1. **C is faster at this than Bend is, and by more on the incremental side
   (1.8x) than on the recompute side (1.2x).** A recompute is bandwidth work and
   Bend is close to C on it; an incremental step is pointer-chasing and
   allocation, where Bend's interaction net pays more. The lane's ratio is
   therefore *better in C than in Bend* — 193x against 131x — which is the
   opposite of a result that flatters the runtime it is written in.
2. **The ratio is set by the size of the change against the size of the
   collection**, and both are mine. 8 rows against 9,216 is a realistic
   materialized-view edit, not a rigged one, but a lane that changed 40% of its
   input every step would measure near 1x and the operators would be the same
   operators. The claim is asymptotic — O(change) against O(collection) — and
   the number above is one point on it.

**There is no `delta_par.bend`, and no fork anywhere in the lane.**
Consolidation is `Radix.reduce_by_key`, and `power/radix.bend` deliberately does
not fork: an Array pays a full copy a fork level (power-1) and a parallel call
anywhere taxes the whole program about 3x (power-3), which counting an add
cannot repay. **This is an inherited measurement, not one re-taken here** — I
did not re-measure radix's fork cost in this lane. The 1T and 16T columns above
are the same run twice, and they agree to within noise, which is consistent with
that inheritance but does not independently establish it.

## Written for Bend

- **`ZSet` and `Ix` are kind `Type`**, because every field holds an `Array`. So
  neither sits inside a `Result` or a `Maybe`, a `List` of Z-sets is not
  expressible, and every operator hands its inputs back beside its answer. The
  same wall power-5 and power-6 each hit; the same resolution.
- **A template parameter may not carry a `+` use mark.** `wadd`, `wneg`,
  `is_neg` and `wmul` therefore read their arguments once, and `dist.p` exists
  as a one-line wrapper solely so `is_pos` — which reads its argument twice —
  can be passed to `flags_p`.
- **`index` gets two aligned columns out of one sort order without a third
  sort.** It copies the key column and calls `Radix.sort_by_key` twice with
  *identical* key columns; the LSD radix is stable and deterministic, so the two
  calls apply the same permutation, and the second key column is dropped.
- **`join_delta` is a three-link chain because `db` cannot be used twice.** The
  obvious spelling passes `db` to the second probe and to the third, which is an
  affine violation. Each probe hands both of its indexes back inside the `Pr` it
  returns, so `jd.t1 -> jd.t2 -> jd.t3` threads them rather than copying them.
- **One flag column drives both of a Z-set's columns through `Scan.compact`,**
  which hands the flags back untouched. That is what keeps the two columns
  aligned through `filter`, `drop0` and `distinct` without a second pass.
- `distinct`'s flags are read off the **weight** column, not the element column.
  Presence is a property of the weight. Writing it the other way round
  typechecks perfectly and was the one logic bug that survived to a test run.

## Deliberate ceilings

The brief drew the line and this is where it fell:

- **No `z^-1` delay operator, no circuits, no fixpoint iteration, no nested time
  domains.** This is the operator algebra, not a DBSP runtime. Recursive views —
  transitive closure, graph reachability — need exactly those, and they are the
  next thing anyone building on this will want.
- **No streaming `distinct`.** `distinct_delta` takes one state and one delta.
  Threading state across a stream of deltas is the caller's, through `absorb`
  and `plus`.
- **No aggregate but sum-by-key.** `min`, `max` and distinct-count are not
  linear over Z-sets and each needs its own state treatment, the way `distinct`
  got one. Adding them as if they were linear would be the same bug the second
  mutant models.
- **An element is one U32.** There is no `(key, value)` indexed Z-set; a key is
  a *function* of the element (`~key`), which is why the fixture's elements are
  `k*256 + v`. Wider rows want a Vec-of-columns Z-set, which is a different
  type, not a flag on this one.
- **No trace, no compaction, no frontier, no bitemporality.** A weight has no
  time attached.
- **No join ordering or multi-way planning.** `join_delta` joins two indexed
  inputs; a three-way incremental join is two of them and the caller chooses.
- **BM25 index delta is not implemented.** power-6 pointed here for it, and what
  arrived is the *join* half. `bm25.build` still fixes `nt` and `nd` at build
  time, and making an inverted index incremental is its own lane's worth of
  work — the postings row table is a CSR, and CSR does not take insertions.

## Battery

power `delta` 6/0 (122 rows) · repo 54/54 · caps ok (35 rows) · bench `delta`
and `delta_full` both matching their C twins at 1T and 16T.

`power/delta.bend` 12,345 ttok against the 64,000 cap; the fixture 10,344 and
its generator 5,587 against 16,000; the two benches 1,870 / 1,523 and the two
twins 1,571 / 1,570. **No cap moved**, and `gates/repo.ts` needed no new row —
its existing `power/*.bend`, `tests/power/**` and `docs/omen/**` patterns
already cover every file here.

No `bend2/` change of any kind. **No `comp.ts` native row, no `base.bend`
change, no new effect — the lane needed none.** No `@unsafe` and no `?TODO`
under `power/`. `tests/power/bench/run.sh`, `tests/power/run.sh`,
`tests/power/bench/twins.c` and `tests/caps.sh` are untouched.

## Next

The honest next step is the one this lane stopped short of: `z^-1` and a
fixpoint operator, which turn the algebra above into a circuit and make
recursive views — reachability, shortest paths, any `WITH RECURSIVE` — cost
their change. Everything here is a component of that and nothing here presumes
it.

The nearer one is a `(key, value)` Z-set with a Vec-of-columns element, which is
what a delta-native `bm25.build` would need before power-6's pointer to this
lane is actually discharged.
