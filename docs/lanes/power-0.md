# power-0 — the power-tools library: skeleton + the counter RNG (2026-09-19)

Plan of record: twenty primitives (data, raw power, elite algorithms, the new
five), re-implemented from their reference sources, in `power/*.bend` — a library
over Base, never in `base.bend`, no cap pressure on `bend2/`.

## What shipped

- `tests/power/run.sh` — the translator runner's shape: the wrong-`#|` control,
  then per specimen **oracle** (`NAME_gen.py` prints the whole fixture from
  CPython; the checked-in file must equal it), **check**, **interpret**, **js**,
  **c**, and **c-1thread** (the same binary under `--threads 1`: a schedule must
  not change an answer).
- `gates/repo.ts` — `power` joins the tests namespace rule; `power/*.bend` at
  64,000. 53 → 54 rules. Nothing in `bend2/` touched; caps read identical.
- `docs/omen/BOUNDARY.md` — `power/**` placed in Zone B.
- `power/rng.bend` — **Threefry2x32-20** (Random123). `block(k0, k1, c0, c1)`,
  `u32(seed, stream, step)`, `f32` (top 24 bits over 2^24: exact on every lane),
  `below` (modulo; bias marked `ponytail:`).

## Method (the rule for every lane after this)

The translator cannot port these sources (no int arithmetic, `while`, indexing).
So: read the source, hand-write Bend, and hold it to a CPython oracle written
independently from the paper. `rng_gen.py` asserts Random123's three
known-answer vectors on itself before it emits a row.

## Written for Bend

- every op is one native `u32_*` row; rotation = two literal shifts + or
- twenty rounds unrolled into straight-line lets: no rotation table, no loop,
  no `match` on a U32 (SHADERS "do not" 8)
- a let cannot open a computed pair, so a group of four rounds takes the last
  group's pair as a parameter (`go_a` / `go_b`); the key injection is folded into
  the group so there is one pair per group, five per block
- an import alias is the prefix: the library file defines `u32`, the caller
  writes `Rng.u32`

## Measured (Ryzen 7 7700X, `--gpu off`, 3 runs each, identical)

`darts(24n)` = 2^24 darts = 33.5M blocks, forked by counter alone:

| `--threads` | wall |
|---:|---:|
| 1 | 0.20 s (~6 ns / 20-round block) |
| 16 | 0.02–0.03 s (~8×) |

Count 13,174,536 on every run and every thread count (π ≈ 3.1410).

## Battery

power 6/0 (+ control) · repo 54/54 · caps ok (unchanged).

## Not done / next

- `normal`, `MonteCarlo.map/reduce`, bootstrap: `normal` needs `log`/`cos`, which
  are not bit-pinned across lanes — lands with an explicit lane note, after Scan.
- GPU (`!`) timing not taken in this lane.
- Next: `power/vec.bend` (Vec / Bytes / Bitset over `Array<U32>`), then Heap/TopK.

---

# Closing the lane: `normal`, and what happened to the other two (2026-09-20)

The three deferrals above are now settled, and two of them turned out not to be
work at all.

## `bootstrap` was already written under another name

A bootstrap resample is "element *i* of replicate *r*, drawn with replacement
from *n*". That is `below(seed, r, i, n)`, letter for letter. The only thing
missing was the sentence saying so, which is now the comment above `below` —
because the property worth writing down is not the arithmetic, it is that a
replicate is *addressable by its number and never stored*. A thousand bootstrap
replicates of a million rows is a billion indices nobody has to hold.

Adding a `bootstrap` alias would have been a second name for one expression.
Skipped.

## `MonteCarlo.map/reduce` was already written as a test

`darts` in `tests/power/rng.bend` is a Monte Carlo map/reduce: 2^12 draws
addressed by counter alone, mapped through a predicate, reduced on the halving
tree, same answer under every `--threads`. Every parallel bench in this library
since has been the same five lines. A higher-order wrapper over a shape that is
already written twenty times, with one implementation and no caller asking for
it, is the abstraction the ladder exists to refuse.

What the wrapper would have bought — proof that the pattern is schedule-free —
the fixture already buys, and buys with a pinned number instead of a type.
Skipped, and this paragraph is the reason, so the next reader does not re-open it.

## `normal` is real, and the lane note it needs is short

`normal(seed, stream, step) -> F64`, Box–Muller on **both words of one block**.
Threefry2x32 returns a pair and `u32` was throwing the second word away; Box–Muller
wants exactly two uniforms. So the second draw is free — no second call, and the
*k*-th normal stays addressable exactly like the *k*-th uniform.

Three decisions, each one a hazard the original deferral was right to flag:

**F64, not F32.** The deferral said `log`/`cos` are not bit-pinned across lanes.
That is true of `F32.log`: it is `logf` in the emitted C and a rounded `Math.log`
in the emitted JS, and those are different rows of different libms. In F64 the
four lanes hold the same double — this is the same finding `power/bm25.bend`
already acts on when it does its idf in F64, and the two files should stay
agreed. `norm.of` is therefore F64 throughout and the caller converts if it wants
less.

**The uniform is nudged off zero.** `(a + 0.5) / 2^32` rather than `a / 2^32`.
`log(0)` is `-inf` on every lane, and a fixture that prints `-inf` on three lanes
and `nan` on the fourth is a day lost to nothing. One counter in 2^32 hits it, so
it would have been found by a stranger and not by this lane.

That nudge also *bounds the answer*, which is what makes the fixture printable:
the largest `|z|` reachable is `sqrt(2 · ln(2^33)) < 6.8`. So `z + 8` is positive
for every input there is, and the fixture prints it as an unsigned fixed-point
number with no sign column and no branch.

**The sine half is discarded.** Box–Muller yields two normals per pair and
keeping both is the textbook thing to do. It is refused here: it would make the
draw at `(seed, stream, step)` depend on whether `step` is even, and a draw that
depends on the parity of its own address is precisely the property this whole
file exists not to have. Marked `ponytail:` at the site.

## Verified

`bash tests/power/run.sh rng` → **PASS 6 / FAIL 0** (oracle, check, interpret,
js, c, c-1thread), plus the deliberately wrong `#|` control detected as failing.

Seven rows added to `tests/power/rng_gen.py`, whose Box–Muller is written from
the definition and not transliterated from `power/rng.bend`:

- six draws printed as `q(z)` = `(z + 8) · 10^6`, which pins the formula to six
  decimals — enough that a wrong rotation, a wrong nudge or a swapped word moves
  the number, and coarse enough that a 1-ulp difference between two libms cannot;
- one row that pins that the formula is a *normal* and not merely deterministic:
  2^12 draws of stream 2 inside one standard deviation, counted on the same fork
  tree `darts` uses. Expected `0.6827 · 4096 = 2796`, binomial standard error 30,
  **measured 2777** — 0.6σ out. A count far from that is a bug, not a seed.

The six pinned values would pass any deterministic function. The sigma count is
what encodes *why* the function matters.

The Bend run and an independent CPython run agree to the last printed digit on
the raw doubles as well, not just the quantised ones: `-0.0404641950859371` and
`-0.32056684727248513` for the first two draws of `(7, 0, ·)`.

## Measured

Two benches added, each checksum-matched against its C twin at `--threads 1`
**and** `--threads 16` before any clock started. `twin_rng_normal.c` writes
Threefry's round structure from the Random123 paper rather than from the Bend
file; `twin_rng_normal_par.c` `#include`s it, because the forked bench must print
the same number and therefore had better be the same program. (`run.sh` shares a
twin by name for `rng`, `topk` and `budget` through a closed `case` list in the
runner; growing that list would be editing a shared gate file, so the one-line
file exists instead.)

25,600,000 draws, Ryzen 7 7700X, `--gpu off`, medians of three, under
`flock /tmp/bend-bench.lock`:

| bench | C | bend-1T | bend-16T | 1T/C | 1T/16T |
|---|---:|---:|---:|---:|---:|
| `rng` | 0.39 | 0.39 | 0.40 | 1.0x | 1.0x |
| `rng_normal` | 0.89 | 0.73 | 0.74 | **0.8x** | 1.0x |
| `rng_normal_par` | 0.91 | 0.79 | **0.11** | 0.9x | **6.9x** |
| `rng_par` | 0.40 | 0.39 | 0.06 | 1.0x | 6.1x |

Two things to read off it honestly.

`rng_normal` at **0.8x** means the Bend program is *faster than the C twin* — the
first row in this library where that happens. It is not a Bend win to brag about:
both sides call the same `log`, `cos` and `sqrt`, so the libm work is identical
and the difference is in what surrounds it. It is reported as measured rather
than explained away, and anyone quoting it should quote the sequential Threefry
row next to it, where the two are dead level at 1.0x.

`rng_normal_par` at **6.9x** is the best scaling figure in the library so far,
and it is the *easy* case: 512 leaves of exactly 50,000 draws each, every leaf
the same work to the instruction. That is worth saying out loud next to lane 10
and lane 17, which both land around 5–6x with *unequal* leaves. Those two lanes
agree that what costs the last 10x of scaling is variance between leaves, not the
fork tree — lane 17 measured 1T flat across a 256-fold change in leaf size, and
lane 10 found one solve per leaf (2^9 leaves) beats eight solves per leaf (2^6
leaves), 6.3x against 3.5x, because bundling work bundles its variance and the
slowest leaf sets the clock. This lane is the control for both: make the leaves
genuinely equal and the number goes up, with the same tree.

## Battery

`bash tests/power/run.sh rng` 6/0 + control · `bun gates/repo.ts` **54/54** ·
`bash tests/caps.sh` exit 0 · bench 4/4 checksum-matched at 1T and 16T. No cap
moved, `gates/repo.ts` not edited (the `power/` and `tests/power/` allow lines
already cover every new path), no `bend2/` change, no `@unsafe`, no `?TODO`.
