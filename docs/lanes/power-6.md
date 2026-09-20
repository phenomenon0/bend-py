# power-6 — Postings and Bm25: search, and the sets that filter it (2026-09-20)

Lane 6, and the first of wave 2. It is also the first lane that is a *consumer*:
`power/bm25.bend` imports Vec, Scan, Radix, Heap, TopK and Postings and writes
almost no loop of its own that one of them did not already own. That was the
point of wave 1, and it is the first evidence the wave was built right.

Two files shipped, because BM25 without a filter is half a search engine.

## What shipped

### `power/postings.bend` — an integer set in the two shapes that pay

A document set, `Sparse` (ascending unique ids in a Vec) or `Dense` (one bit an
id), with the algebra crossing the pair:

- `sparse()`, `dense(n)`, `all(n)`, `of_list(xs)`, `add(s, x)` — construction.
- `and / or / andnot / not` — all four shape combinations of each.
- `has(s, x)`, `count(s)`, `to_vec(s)` — membership (binary search when sparse,
  one bit test when dense), cardinality, the members ascending.
- `densify(s, n)`, `sparsify(s)`, `optimize(s, n)` — shape moves, and the rule:
  dense above n/32 members, which is the point the bitmap gets cheaper.

Each operation answers in the shape that costs least: `and` keeps a sparse side
because a sparse side *bounds* the answer, `or` keeps a dense side because a
dense side *absorbs* it, `andnot` keeps the left side's, and `not` is dense
always because it is `andnot` against the universe. So `and` with one sparse
side costs that side and never the universe — which is the whole reason a
filtered query over 10^6 documents is cheap.

### `power/bm25.bend` — an inverted index whose postings carry their score

BM25S's move: BM25's tf and length terms depend only on the document and its
idf only on the term, so the entire per-posting weight is known at **index**
time. A query stops being arithmetic and becomes a gather.

- `build(terms, docs, nt, nd, k1, b) -> Index` — two stable radix passes, one
  run walk turning `(term, document)` runs into postings, one prefix sum for the
  CSR row table, one nested loop that prices them: **one logarithm a term, not a
  posting**.
- `query(ix, qv) -> Index & Vec` — one saturating add a posting into a dense
  accumulator; returns a score a document.
- `rank(scores, k) -> Vec & List<Heap.Entry>` — the best k, best first, through
  TopK.
- `keep(scores, set, nd) -> Vec` — a Postings filter applied to a score vector;
  this is the join between the two files.
- `df(ix, t)`, `postings(ix, t) -> Index & Postings.Set`, `explain(ix, t, doc)` —
  the explainability surface: a term's document frequency, its row *as a
  Postings set* (so a row is directly an operand of the boolean algebra), and
  the single weight one term contributed to one document. `explain` summed over
  a query's terms reproduces `query`'s score exactly, and the fixture pins that
  identity on every corpus.
- `quant`, `idf`, `weight`, `sat`, `score` — the arithmetic, exposed, because a
  score nobody can re-derive is not explainable.

## Rule 7 — power-5 closed asking for two things; here is what happened to both

power-5's last line said this lane "finally wants Bitset `to_list` /
next-set-bit and an F32 key for the heap". One arrived, one was refused:

1. **Next-set-bit landed, as `Bitset.ctz`** (`power/bitset.bend:169`), over
   `low(x) = x & -x`. `Postings.enum` uses it to walk a dense set one *set* bit
   at a time instead of testing 32 bits a word, so `to_vec` on a sparse-ish
   dense set costs its members and not its capacity.
2. **The F32 heap key was refused. Scores are fixed point U32 at 2^20.** Three
   reasons, and the third is the one that matters:
   - `Vec` holds U32, and `base.bend` hands out `F32.bits` with no law back, so
     a float score would have to ride as a bit pattern nobody can re-read.
   - `TopK` already ranks U32 keys, so no float-keyed heap is needed at all.
   - **Integer addition is exactly associative.** A document's score does not
     depend on the order its query terms arrived in, so a forked query sums to
     the same bits as a straight one, and the `exact` / `ordered` split power-1
     had to draw for Scan does not arise. Choosing F32 here would have imported
     that split into every query.

   The quantum is one part in 2^20 of a score of 1, and the largest idf for any
   corpus that fits a U32 document count is under 23, so a few hundred query
   terms still fit with room. `sat` clamps rather than wraps: a score that wraps
   ranks a document *last* instead of first, which is the worst failure the
   ranker has.

## The Roaring deviation, stated

`power/postings.bend` is CRoaring's array-or-bitmap decision **without
Roaring's chunking**. Roaring cuts the 32-bit id space into 2^16 chunks so that
ids scattered across a huge space still meet inside one container. An index that
numbers its documents 0..n-1 has nothing to scatter. The container *choice* —
the part that actually pays — is the whole of the idea, and it is here. If a
later lane needs sets over sparse 32-bit keys (hashes, not document ids), the
chunk layer is a `Vec` of `(hi16, Set)` on top of this file, not a change to it.

One consequence is stated in the file and worth repeating: **every set in one
expression must be over one universe.** A dense set rounds capacity up to
32·2^d, and a sparse id at or past that capacity would wrap into the wrong cell
rather than read as absent.

## Verified

`bash tests/power/run.sh bm25` — 88 rows, `PASS: 6, FAIL: 0`.
`bash tests/power/run.sh postings` — 208 rows, `PASS: 6, FAIL: 0`.
Six lanes each: oracle, check, interpret, js, c, c-1thread.

**`tests/power/postings_gen.py` uses CPython's own `set`** for every answer, so
the algebra is checked against the language's set type and not a second copy of
this implementation. A row prints `"<shape>[<members>]"` — `S` or `D` — so it
pins *which container the algebra chose* as well as what it holds. That is what
makes the shape rules above testable rather than decorative.

**`tests/power/bm25_gen.py` is a plain-CPython reference** — dicts and floats,
no Vec, no radix, no CSR — spelling BM25 in the same order `power/bm25.bend`
spells it. Four corpora: the lane's own hand-checked three-document probe, then
Lucene's defaults over a zipf vocabulary, then `b = 0` (no length
normalization at all), then a wider index with `k1 = 0.4` so tf saturates fast.

The one hazard is the logarithm. A weight is quantized `floor(w·2^20 + 0.5)`,
and V8's `Math.log`, glibc's `log` and CPython's `math.log` need not agree in
the last ulp — which only matters for a weight whose scaled value sits on an
integer boundary. **`guard()` refuses to print a fixture containing one**, the
same move `json_gen.py`'s `agree()` makes: a three-host disagreement becomes a
generator failure at authoring time instead of a flaky lane later.

**Mutants** — four, each confirming the fixture reaches the branch. Every one
passes the oracle and the checker and fails all four executing lanes (`PASS: 2,
FAIL: 4`):

| mutant | what it breaks |
|---|---|
| `weight` drops `(1 - b)` from `norm` | the length-normalization constant term |
| `run.same` breaks a run on the term only, not `(term, document)` | tf collapses to the row length |
| `span`'s vocabulary guard forced to `True{}` | a query term at or past `nt` reads past the row table |
| `or(Sparse, Dense)` answers sparse | the shape rule, not the members |

The last one is the useful one: it returns the **right members in the wrong
container**, and the fixture still catches it, because a row prints its shape.

## The fixture that did not get a cap raise

`tests/power/postings.bend` arrived at **47,266 ttok** against the 16,000 cap
that every test in `gates/repo.ts:76` carries. The lazy move is to raise the
cap. Measuring first said not to: every other power fixture is ≤ 8,115 ttok, so
this one was a 6× outlier — a fat fixture, not a cap problem.

Two edits to the generator fixed it, both deleting rows that said nothing:
binary-operation operands capped at 15 and 11 members (the merge does not care
whether a side has 15 ids or 60), and `optimize`'s `k` sweep replaced by four
values *straddling* its n/32 threshold instead of running to the full universe —
a 1,000-id set printed eight times says exactly what the boundary pair says.

**47,266 → 15,595, and the coverage is the same:** 204 rows became 208. No cap
moved in this lane.

## Measured (Ryzen 7 7700X, 8 cores / 16 threads, `--gpu off`, medians of three)

| bench | what it runs | C | bend 1T | bend 16T | 1T/C | 1T→16T |
|---|---|---:|---:|---:|---:|---:|
| `bm25` | index 4,000,000 occurrences, then 250,000 queries | 0.59 | 2.01 | 2.03 | 3.4x | 1.0x |
| `bm25_par` | 2^8 shards, each its own index and its own 1,000 queries | 0.32 | 0.67 | **0.10** | 2.1x | **6.7x** |

16,384 terms, 2,048 documents, queries of 8 terms ranked to their best 8. The
vocabulary is skewed the way a real one is — a term is the product of two hashes
divided by `nt`, so low ids carry long rows and most terms carry one posting —
and **the queries draw from the same distribution**, so a query hits the fat
rows as often as a real one does. Every ranked entry is folded into the
checksum, and a row is only timed once Bend's checksum equals the C twin's.

`bm25` is flat across threads by construction: it is one index and one query
loop, with nothing to fork. The split of its 3.4x, from a two-point measurement
at 50,000 and 250,000 queries:

| | C | bend 1T | ratio |
|---|---:|---:|---:|
| build (4,000,000 occurrences → 16,384 rows) | 0.071 s | 0.162 s | **2.3x** |
| query (8 terms, ~134 postings, 2,048-doc sweep) | 1.79 µs | 7.56 µs | **4.2x** |

Build is the better half, and it is the half that is almost entirely wave-1
code — two `Radix` passes and one `Scan` prefix sum. The query loop is the
worse half and it is this file's own.

Dropping the query to one term costs C 0.71 µs instead of 1.79 µs, which splits
the query again: **0.56 µs is the 2,048-document accumulator sweep** (the
`memset`, then the walk that collects non-zero scores) and 1.20 µs is the 134
postings. The sweep is O(nd) no matter how small the query — it is the floor a
WAND / MaxScore top-k would remove, and the reason `nd`, not the query, sets the
cost of a *small* query. Stated as a ceiling below rather than fixed here.

Parallel, the shape is the one wave 1 predicted: **an `Index` holds arrays, and
an array has one owner, so no fork can share an index.** The shard, not the
query, is the unit of parallel search — which is also how a real cluster does
it. 6.7x on 16 threads with each leaf owning its own corpus, its own index and
its own queries.

## The tree-fold trap, one turn sharper than power-5 recorded it

power-5 found that folding `acc*31 + x` over a tree of **equal** leaves lands on
exactly 0, and fixed its bench by making the leaves differ (stride 801, not
800). `bm25_par`'s leaves *do* differ — disjoint key ranges, different corpora,
different queries — and it still came out **0** on both C and Bend.

The rule is sharper than "equal leaves":

> A leaf checksum is itself an `acc*31 + x` fold, and **31 ≡ -1 (mod 32)**, so
> `31a + b ≡ b - a`, and every leaf of this bench comes out congruent mod 32 to
> every other. A plain `a*31 + b` tree combine then shifts five zero bits in a
> level, and 2^40 ≡ 0 (mod 2^32) kills 256 leaves in 8 levels.

Distinct leaves are not enough; leaves must not share a residue mod 32, and
they will share one whenever the leaf value is itself a `·31 + x` fold — which
is to say, always, for the way every bench in this suite computes a checksum.

The fix is json_par's existing mixer, `mix(acc, x) = rot7(acc*31 + x)`, mirrored
in the C twin as `jmix`. The rotate is what stops the low bits from running out.
Checked by perturbing a leaf by +1, +32, +1024 and +2^31: each changes the
result. New checksum 1611071552, identical on C, 1T and 16T.

## Written for Bend

- **`Set` is kind `Type`**, because both arms hold an array. So it cannot sit
  inside a `Result` or a `Maybe`, and `postings(ix, t)` returns
  `Index & Postings.Set` rather than a `Maybe` — the same wall lane 5 hit, with
  the same resolution: hand the owner back beside the answer.
- **A dense-dense operation is Bitset's own in-place cell loop** — 32 documents
  an iteration, no allocation. A sparse operation is one left-to-right merge
  whose output is never longer than its inputs. One `merge` with a `mode`
  argument serves and/or/andnot, so there is one cursor machine, not three.
- `2^32-1` is the merge's end-of-side sentinel, so it is not a member. Marked
  `ponytail:` in the file with its upgrade path (a live flag a side, two record
  fields).
- **`build` is two stable radix passes, by document then by term**, which leaves
  the postings grouped by term *with their documents ascending* — the ordering a
  `Postings.Sparse` needs, obtained for free from the sort that had to happen
  anyway. The run walk breaks on either column changing, which is why it is a
  walk of its own and not `Scan.rle` over one column.
- The JS lane's statement ceiling is still the binding constraint on fixture
  size: the emitted `do IO<Unit>:` block is one nested closure a statement and
  V8 gives out past roughly 300. 208 rows is near the practical ceiling, and the
  cap trim above kept it there for the right reason as well as the stated one.

## Deliberate ceilings

- **No WAND / MaxScore.** The query sweeps every document. Measured above at
  0.56 µs a query for nd = 2,048; it becomes the whole cost for a small query
  over a large corpus. The upgrade is a per-term max weight in the row table and
  a threshold from the heap — an `Index` field and a branch, not a redesign.
- **No chunked containers and no run container.** See the Roaring deviation.
- **No phrase or positional postings.** A posting is `(document, weight)`; there
  is no room for offsets, and phrase search is a different index, not a flag.
- **No stemming, no stopwords, no tokenizer.** The index takes term *ids*.
  Text → ids is lane 15's (text identity), and writing a tokenizer twice would
  be the waste.
- **`nt` and `nd` are fixed at build.** There is no incremental add. Delta
  indexing is lane 16 (delta-native computation), which is where it belongs.

## Battery

power 66/0 (+ control) · repo 54/54 · caps ok · bench 16/16 checksums match C.

`power/bm25.bend` 7,207 ttok and `power/postings.bend` 5,824 against the 64,000
cap; the two fixtures 7,077 / 15,595 and their generators 2,597 / 2,145 against
16,000; the two benches 1,269 / 1,537. **No cap moved.** No `comp.ts` row, no
`base.bend` change, no new effect — the lane needed none. `tests/power/bench/
run.sh` gained one word, `-lm`, because `idf` calls `log`.

## Next

Lane 8, batched vector similarity and exact KNN — `Array<F32>` tiles against
TopK, and the library's first serious GPU (`!`) benchmark. It is also the lane
where the F32-key question this one refused comes back for real, since a
distance genuinely is a float and there is no 2^20 quantum that is obviously
right for it.
