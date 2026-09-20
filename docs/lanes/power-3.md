# power-3 — Scan, and the bench harness that grades every lane (2026-09-20)

Lane 1 of the plan, plus `tests/power/bench/`: each primitive against a C twin
of the same algorithm, and against itself at 16 threads.

## What shipped

- `power/scan.bend` — `scan` / `scan_ex` (inclusive / exclusive, any operator
  and identity), `sums`, `offsets` (the CSR row table, a partition's write
  positions, a frontier's slots), `segmented` (the total restarts at every
  head), `filter` (a predicate, in place), `compact` (keep-to-dense by a flag
  vector), `rle` (runs to values and counts). Oracle: plain CPython loops;
  operators `U32.add`, `U32.max`, `U32.xor` and a non-commutative `hash`
  (a·31+x, identity 7) so a fixed order is what is pinned, not just a sum.
- **`Scan.exact` / `Scan.ordered` / `Scan.fast` collapsed into one def.** The
  plan had three: a schedule-independent U32 scan, a fixed-tree float scan, and
  a fast one. One left-to-right index loop is all three at once — it is the one
  fixed order, so a non-associative operator has one answer on every lane and
  every schedule, and it is also the fastest of the three (below). Three names
  for one loop is three names.
- `partition` is not here: `filter` plus `compact` with the complement flags is
  it, in the caller, with no new type.

## The bench harness

`bash tests/power/bench/run.sh [prefix]` — one `.bend` per primitive in
`tests/power/bench/`, one `twins.c` holding the same algorithm in plain C
(clang -O3, the flags `bend` itself builds with; single-threaded). **A row is
only timed once Bend's checksum equals C's**, at one thread and at sixteen, so
a timing can never be of a different computation. Medians of three.

## Measured (Ryzen 7 7700X, 8 cores / 16 threads, `--gpu off`)

| bench | what it runs | C | bend 1T | bend 16T | 1T/C | 1T→16T |
|---|---|---:|---:|---:|---:|---:|
| `heap` | push 8,000,000, drain all | 1.96 | 1.80 | 1.82 | **0.9x** | 1.0x |
| `rng` | 204,800,000 Threefry draws | 0.39 | 0.39 | 0.40 | **1.0x** | 1.0x |
| `topk` | best 100 of 400,000,000 | 0.31 | 0.45 | 0.45 | 1.4x | 1.0x |
| `bytes` | 64,000,000 pushes + 4 reads each | 0.19 | 0.31 | 0.31 | 1.6x | 1.0x |
| `scan` | 64,000,000 cells, summed 20x | 0.39 | 0.70 | 0.70 | 1.8x | 1.0x |
| `vec` | 64,000,000 pushes + 4 reads each | 0.25 | 0.51 | 0.50 | 2.0x | 1.0x |
| `bitset` | 2^27 bits, 80 x (xor, popcount) | 0.23 | 0.53 | 0.54 | 2.3x | 1.0x |
| `rng_par` | the same draws, 2^8 ranges | 0.39 | 0.39 | **0.05** | 1.0x | **7.7x** |
| `topk_par` | the same stream, 2^8 ranges merged | 0.31 | 1.41 | **0.21** | 4.5x | **6.8x** |
| `scan_par` | 2^8 leaf-private blocks of 250,000 | 0.26 | 0.43 | **0.07** | 1.7x | **5.8x** |

Heap beats C; the counter RNG ties it. Nothing is more than 2.3x off, and the
three forked benches beat single-threaded C outright (rng 7.8x, scan 3.7x,
topk 1.5x).

## Four things the harness found

1. **The scheduler wants many more tasks than threads.** Static dealing, no work
   stealing (GUIDE.md:152), so one task per core leaves cores idle at the tail.
   Same rng work, 16 threads: fork depth 4 → 2.1x, depth 6 → 3.2x, **depth 8 →
   8.0x**, depth 10 → 9.0x. Fork to 2^8 leaves, not 2^4. Every parallel lane
   from here takes depth 8 as the floor.
2. **A parallel call anywhere in the program taxes the whole program.** One
   `a b = f g` widens the emitted worker's register bank from 2 to 11 and its
   signature from 6 args to 15 (`WL_SIG`, `WL_BANK`) — every def pays it, and a
   def that never forks pays it too. Measured on `topk` with the fork at depth
   **0**, so the fork never runs: 0.45 s → 1.41 s, **3.2x**, and lowering the
   fork def's own arity does not shrink the bank. The tax is ~0 on an
   arithmetic leaf (`rng_par` 1T ties `rng` 1T) and ~3x on one that allocates.
   So a fork must clear ~3x before it pays: `topk_par` scales 6.8x and nets
   only 2.1x over the sequential bench.
3. **`Array` is at C parity; the wrapper is not.** A raw `Array<U32>` loop over
   64,000,000 cells with the `vec` bench's access pattern runs in 0.25 s — the
   same 0.25 s as C. `Vec` on the identical traffic takes 0.51 s: the cost is
   opening and rebuilding the `Vec{len, depth, arr}` record per access. It is
   *not* worth hoisting in `scan`: rewriting `Scan.sums`'s inner loop to hold
   the Array directly changed nothing (0.70 s either way), because at
   64,000,000 cells that loop is DRAM-bound — 10 GB moved in 0.70 s, 14 GB/s
   against C's 20 GB/s. Hoist only where the loop fits in cache.
4. **A native popcount row was tried and reverted.** `POPC` (Metal `popcount`,
   CUDA `__popc`, clang `__builtin_popcount`) in `comp.ts` plus `U32.ones` in
   Base: verified correct on check / interpret / JS / C against CPython, landed
   in the hot loop as `POPC((u32)(r_1))` — and bought **4%** on a 335,000,000
   word count (0.55 → 0.53). C's 3.2x on count-only is an auto-vectorized loop,
   not the instruction. Reverted rather than raise Base's cap for noise; the
   note and the numbers are in `power/bitset.bend`. Worth revisiting only for
   the GPU lanes, where the SWAR ladder is twelve ops.

## Written for Bend

- every def is one left-to-right index loop carrying `fuel: Nat, +i: U32`
- in place wherever the output is no longer than the input (scan, scan_ex,
  segmented, filter, compact all are); `rle` alone builds two fresh Vecs
- the operator and the predicate are `~f` / `~p` template parameters, so each
  instance compiles with them inline — `sums` and `offsets` are `~U32.add`
- a def whose parameters carry `+` (e.g. `U32.max`) does not match a plain
  `U32 -> U32 -> U32`; the fixture wraps it (`most`)
- a def must precede its first use: `seg.set` before `seg.put`, `compact.fin`
  before `compact.got`

## Mutants (the fixture reaches the branches)

`seg.from` returning `acc` where it should return `id` (heads ignored), and
`filter.if` not advancing the write index: each fails 4 of 6 lanes.

## Deliberate ceilings

- U32 only, like the rest of the lib. A float scan needs `Scan` over F32, which
  lands with the first float consumer (KNN / FFT).
- `scan_par` forks over leaf-private blocks. One shared Array still does not
  fork (power-1): that is a runtime property, and the blocked shape is the
  answer, not a parallel scan of one array.

## Battery

power 42/0 (+ control) · repo 54/54 · caps ok · bench 10/10 checksums match C.
The scan fixture was regenerated at smaller n (300 → 37, 200 → 40, 150 → 60) to
fit the 16,000 ttok test cap; no loop has a size-dependent branch past 37.

## Next

Lane 3 — Radix Sort / Histogram / Reduce-by-Key on Vec and Scan. It is the
first lane where the fork is the algorithm (`bench/runtime/tree-radix`), so it
takes finding 1 (depth 8) and finding 2 (clear 3x first) as its starting rules.
