# power-18 — Consequence: the question you do not have to ask (2026-09-20)

Lane 18. One file, and the smallest idea in the library: **an ambiguous request
with N readings does not need an N-way question.** Run each reading through a
deterministic preview and you get N action traces. Two readings whose traces
agree are the same reading as far as the world is concerned — asking which one
was meant is a question with one answer. `collapse` keeps one representative a
distinct trace, so the question a caller ends up asking has exactly as many
branches as there are *outcomes*, which is often one, which is no question.

The plan's row called it `collapse_by_consequence(interps, preview)`. What
shipped splits that in two, because the halves have different owners.

## What shipped

### `power/consequence.bend` — the digest, and the grouping

The preview is **the caller's**, and this file never runs it. That is the whole
boundary decision of the lane: a preview is domain code (what would this
reading actually do to a filesystem, a cart, an index?) and nothing generic can
be written about it. What *is* generic is the step after — given the traces it
produced, how many different things could happen, and which reading stands for
each. That is what this file answers, and it is the part that is the same in
every domain.

So the signature is not `(interps, preview)` but the traces themselves:

    digest(seed, acts, lens)            -> Vec      one digest a reading
    collapse(digs)                      -> Groups   the distinct consequences
    collapse_traces(seed, acts, lens)   -> Groups   the two, which is the move

    count(g)            -> Groups & U32    how many different things could happen
    settled(g)          -> Groups & Bool   True when there is nothing to ask
    representatives(g)  -> Vec & Vec       readings to offer, and their weights

`Groups{keys, reps, cnts}` is the answer: ascending by digest, one row a
distinct consequence, holding what it hashed to, the lowest-numbered reading
that produces it, and how many readings do. `cnts` is not decoration — when a
clarifier does have to ask, `6 readings mean this / 1 means that` is a
different question from `3 and 4`, and the second column is what ranks the
options.

A Vec holds an Array, so it is kind `Type` and cannot sit inside another Vec.
The N traces therefore arrive **concatenated with their lengths beside them** —
the CSR shape `postings`, `bm25` and `knn` already use, so a caller that has
one of those has the layout already.

### The three loops, and why there is no fourth

    heads    one flag a cell over the flat block, set where a trace starts
    (scan)   Scan.segmented folds the digest, restarting at every flag
    gather   trace j's digest is the cell its last action landed in

Then the grouping is one `Radix.sort_by_key(digs, iota(n))` and one walk of the
runs the sort makes adjacent. Nothing here allocates per trace and nothing
nests a loop inside a loop: the digest is one pass over the one flat block,
whatever the shape of the traces inside it.

That the middle step is a **segmented scan** is not a flourish. Grouping by
key is the textbook parallel primitive precisely because a segmented scan is,
and writing the fold that way means the parallel version of this file is the
same code with a different driver rather than a rewrite.

## The empty trace, which is the case that matters

A reading that would do *nothing* is a consequence like any other, and two of
them are the same consequence. That sounds like an edge case and is not: "the
request is ambiguous, but three of the five readings turn out to be no-ops" is
the single most common shape a clarifier meets, and a primitive that crashes or
merges on it is useless.

Two places handle it, both by construction rather than by a special case:

**In `heads`.** An empty trace sets the flag at its own start index, which is
the same cell its successor starts at — so it writes the flag its successor
would have written, the marks stay correct, and the cursor still lands right.
The one genuinely out-of-range case (an empty trace *last*, whose start index
is one past the end of the flat block) goes through `Vec.set`, which is the
checked write and returns a `Bool` the code drops. That is the whole handling.

**In `gather`.** An empty trace never reached a cell, so there is no cell to
read; it keeps the seed. Which is right in the strong sense as well as the
convenient one — the seed is the digest of the empty sequence, so "does
nothing" gets an identity rather than a sentinel, and two no-op readings land
in the same group without anything being told to make them.

`tests/power/consequence.bend` spends seven rows on this: one empty, two
empties, empty-then-full, alternating, all-empty, empty-last (the out-of-range
start), empty-first. Mutant 5 below is the one that catches a cursor that does
not respect them.

## Rule 9 — what the fixture can honestly pin, and what it cannot

This is the interesting part of the lane and it is worth being exact about.

Bend groups by a 32-bit digest. The oracle, `consequence_gen.py`, groups with
**CPython's own `dict` keyed by the trace tuple** — it never computes a hash,
and there is no second copy of the implementation anywhere in the test. A row
matches only when the two agree on *which readings are the same reading*. That
is the contract, stated against the language's own notion of equal sequences.

Which means the fixture is **deliberately blind to the mixer**, and it should
be. Swap Murmur3's finalizer for another good hash and every row still passes,
because a different good hash induces the same partition — that is not a
regression, it is a refactor. Measured rather than assumed:

| change | `run.sh consequence` | `bench/run.sh consequence` |
|---|---|---|
| `Sketch.hash` → `Sketch.mix(acc*16777619 ^ x)` | `PASS: 6, FAIL: 0` | **FAIL both rows** |

So the two halves of the battery pin different things, and the lane needs both:
**the fixture pins the contract, the C twin pins the implementation.** The
twin reproduces the digests on purpose and folds them into its checksum, so the
constants are held by the one artifact that has a right to hold them.

A consequence of this, stated plainly: the mutants below all break the
*partition*. None of them touches the mixer, because a mixer mutant is not a
mutant.

## The mutants

Five, each reverted after. `PASS: 2` is the oracle and strict-check lanes,
which do not depend on the answer; `FAIL: 4` is interpret, js, c and c-1thread.

| | mutation | result |
|---|---|---|
| 1 | `Vec.set(hs, at, 1)` → `0`: no trace ever restarts the fold | `PASS: 2, FAIL: 4` |
| 2 | `U32.is_eq(x, key)` → `is_ne` in the run walk | `PASS: 2, FAIL: 4` |
| 3 | gather reads `at + l` instead of `at + l - 1` | `PASS: 2, FAIL: 4` |
| 4 | `Vec.push(cnts, run)` → `Vec.push(cnts, 1)` | `PASS: 2, FAIL: 4` |
| 5 | head cursor `U32.add(at, l)` → `U32.inc(at)` | `PASS: 2, FAIL: 4` |

Mutant 1 is the one the empty-trace rows earn their keep on: with no restart,
every digest becomes a running fold of everything before it, so no two readings
ever agree and every row collapses to all-distinct. Mutant 3 is the off-by-one
that a fixture of equal-length traces would not catch, which is why the bench
uses lengths 1..8 and the fixture uses lengths 0..12.

One mutation was tried and **rejected as not a mutant**: the empty-trace branch
pushing `0` instead of `seed`. Both are constants distinct from any reached
digest, the partition is unchanged, and the fixture passes — correctly. It is a
different spelling of the same behaviour, not a bug, so it is not counted.

## One thing the language decided

`~f: U32 -> U32 -> U32` will **not** accept a def whose binders are marked:

    - expected : @_:U32 -> @_:U32 -> U32
    - observed : @+seed:U32 -> @+x:U32 -> U32

`Sketch.hash(+seed: U32, +x: U32)` is marked because it uses both twice, and
that marking is part of its type. So a marked def cannot be passed as a `~f`
directly and needs a one-line unmarked face:

    def fold(acc: U32, x: U32) -> U32:
      Sketch.hash(acc, x)

Cheap, and obvious once seen, but it is a rule about `~` that is not written
down anywhere else in the library — `scan.bend`'s own callers all pass
`~U32.add`, which happens to be unmarked. Any lane that wants to hand an
existing power def to a `~f` parameter will hit this.

## Measured (Ryzen 7 7700X, 8 cores / 16 threads, `--gpu off`, medians of three)

| bench | C | 1T | 16T | 1T/C | scaling |
|---|---:|---:|---:|---:|---:|
| `consequence` | 0.13 | 0.26 | 0.26 | 2.0x | — |
| `consequence_par` | 0.12 | 0.17 | 0.03 | 1.4x | **5.6x** |

`consequence` is 2,000,000 readings drawn from a pool of 977 patterns, trace
lengths 1..8, so ~9,000,000 actions in the flat block and ~977 groups of ~2,048
readings each. That is the shape a clarifier sees; an all-distinct input would
be an easier sort and a dishonest number. `consequence_par` is 2^8 leaf-private
blocks of 8,000 readings each.

**The scaling column is a floor, not a result.** Nine lane agents were
compiling on this box while it ran. Lane 9 measured the same depression on its
own rows and saw them recover when the box was quiet. The `1T/C` column is
stable across runs; `1T/16T` is not.

The parallel shape needed no argument to justify, which is unusual for this
library: readings of one request never have to be grouped against readings of
another, so leaf-private blocks are what the problem actually is, not a
concession to the fact that an Array cannot fork (power-1).

## Deliberate ceilings

- **32-bit digest.** Two unrelated traces collide at ~2^-32 a pair and are
  merged into one group silently — which in this domain means a question that
  should have been asked is not. Marked `ponytail:` in the file. The upgrade is
  a 64-bit digest, which is two lanes of the same fold, not a new algorithm.
- **The preview is the caller's.** No `preview` combinator shipped, because
  there is nothing domain-independent to say about one. If several callers
  arrive wanting the same preview shape, that is when to look again.
- **The bench pattern pool is uniform** (977 patterns, ~2,048 readings each).
  A skewed pool — one huge group and a long tail — is the harder case for the
  run walk and is not measured.

## Battery

`bash tests/power/run.sh consequence` — **`Power PASS: 6, FAIL: 0`**, plus the
harness's own `wrong #| fixture detected as failing` control. All six lanes:
oracle, check, interpret, js, c, c-1thread.

`bash tests/power/run.sh` — **`Power PASS: 120, FAIL: 0`**, the whole library as
it stood when this was written (96 when lane 9 ran; the other lanes in flight
have landed 24 rows since). Lane 18's own share is the 6 above.

`bun gates/repo.ts` — **`PASS: 53 / 54`**. The one failure is `d_probe.bend`, a
scratch probe another lane left at the repo root; it was reported to its owner
and is not this lane's file. The gate named no lane-18 file.

`bash tests/caps.sh` — no `OVER` rows.

Both bench rows' checksums match their C twins at 1T and 16T; `run.sh` only
times a row once they do.

`power/consequence.bend` 3,168 ttok against the 64,000 cap; the fixture 7,591
and its generator 2,131 against 16,000; the two benches 840 / 928 and the two
twins 914 / 940. **No cap moved**, and **no `gates/repo.ts` edit** — lines
76-77 already cover `power/*.bend` and `tests/power/**`. No `comp.ts` row, no
`base.bend` change, no new effect, and no existing power file touched: the lane
adds seven files and modifies none.

## Next

Nothing in this lane; it was the last one the plan lists that had no owner. The
open items are the eleven lanes still in flight and the integration pass behind
them.
