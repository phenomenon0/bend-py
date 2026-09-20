# power-4 — Radix: sort, histogram, reduce-by-key (2026-09-20)

Lane 3 of the plan. The first lane whose parallel shape was a real question, so
it was written under power-3's two rules: fork to 2^8 leaves, and clear ~3x
before a fork pays.

## What shipped

`power/radix.bend`, over `power/vec.bend` and `power/scan.bend`:

- `histogram(~key, buckets, v)` — how many of `v` fall in each of `buckets`
  buckets under any key function; the Vec comes back untouched beside the table.
  `Scan.offsets` of that table is where each bucket starts: the CSR row
  pointers, a partition's write positions, the scatter's cursors.
- `sort(v)` — stable LSD radix, four passes of eight bits, full 32-bit keys,
  duplicates kept.
- `sort_by_key(keys, vals)` — the same four passes moving a second Vec alongside,
  so a value rides with its key; equal keys keep their input order.
- `tally(v)` — every distinct value, ascending, and how many times it occurs.
- `unique(v)` — the values of `tally`.
- `reduce_by_key(~f, keys, vals)` — the distinct keys and their values folded
  by `f`, in key order and, within a key, in input order.

`tally` is `Scan.rle(sort(v))` and `unique` is its first component: sorting puts
equal values adjacent, and `rle`'s runs are exactly the groups. The plan had
`reduce_by_key` as sort plus a segmented scan plus a compaction; after the sort
the runs are already adjacent, so it is one walk instead of three passes and two
extra Vecs. `group_by` is not here — it is `sort_by_key` plus `Scan.offsets` of
`tally`'s counts, in the caller, with no new type.

## The one design decision

**The bucket function is a template parameter, not a shift argument.** The
obvious `digit(x, shift)` threading `shift: Nat` through the loop is a trap:
`U32.shrn` (`base.bend:1513`) recurses on its Nat, so a runtime shift is a
24-step loop per element on the top digit. As `~key` each pass specialises at
compile time and the shift is a literal — verified in the emitted C:

    INLINE Term spin_14(Env e, THR Term* o, u32 r0) {
      Term a_0 = 16ull;
      v_2 = U32_BIN((a_0 >= 32 ? 0 : U32_BIN(x_0, >>, a_0)), &, 255ull);

`a_0` is a constant, so clang folds it to one `x >> 16`. The same parameter is
what makes `histogram` general rather than radix-only.

(power-5 corrects the premise, not the decision: `U32.shrn` has a native row
(`comp.ts:192`), so a *runtime* shift is one machine shift in the compiled
lanes, not a 24-step loop — that loop is what the checker and the interpreter
run. `~key` is still the right parameter, for the generality.)

## Measured (Ryzen 7 7700X, 8 cores / 16 threads, `--gpu off`, medians of three)

`bash tests/power/bench/run.sh` — every row timed only after Bend's checksum
equals the C twin's, at one thread and at sixteen.

| bench | what it runs | C | bend 1T | bend 16T | 1T/C | 1T→16T |
|---|---|---:|---:|---:|---:|---:|
| `radix` | 8,000,000 keys sorted 4x | 0.16 | 0.35 | 0.34 | 2.1x | 1.0x |
| `radix_par` | the same work, 2^8 blocks | 0.12 | 0.25 | **0.04** | 2.1x | **6.3x** |

2.1x off C, in the same band as `vec` (2.0x) and `bitset` (2.4x). Forked, it
beats single-threaded C by 3.0x.

## Three things this lane found

1. **The gap to C is the scatter's cache misses, not the Vec record.** power-3
   found `Vec`'s open-and-rebuild costs 2x on cache-resident traffic and said to
   hoist the raw `Array` only where the hot loop fits in cache. Radix's 1 KB
   count table is exactly that case, so it was tried: a probe with the count and
   cursor tables as raw `Array<U32>` (no record per bump, no record per cursor
   read — four of the eight table touches per element per pass) ran **0.33 s
   against 0.35 s, 6%**, same checksum. The library kept the Vec table, which is
   what lets `histogram` hand its counts straight to `Scan.offsets`. What is
   left is the scatter writing to 256 cursors scattered across a 32 MB buffer;
   C pays those misses too, and its 2.1x is that it pays them one instruction at
   a time.
2. **Blocking is worth more than threading, before any threading.** `radix_par`
   at **one** thread is 0.25 s against `radix`'s 0.35 s on byte-identical work —
   256 blocks of 125 KB stay in L2 while one 32 MB sort does not. C shows the
   same split (0.12 vs 0.16). Block first, then fork; the fork is the second
   1.4x, not the first.
3. **The scatter is the part that cannot fork.** One counting pass is a shared
   256-cursor table read and written by every element — shared mutable state, so
   under an affine single-owner Array (power-1) a fork can only own a whole
   block. The honest parallel shape is 256 leaf-private sorts, which is 256
   sorted runs, not one sorted Vec. That is what `radix_par` measures and what
   the file says it measures. Merging them is a k-way merge and is not in this
   lane.

## Mutants (the fixture reaches the branches)

`red.if` keeping the last value instead of folding it (the equal-keys branch),
and the pair scatter's cursor never advancing (`U32.inc(at)` → `at`): each fails
4 of 6 lanes.

## Written for Bend

- `~key` must be a *leading* binder — "a plain binder (only leading binders take
  `~`)" — so every def carrying it puts it first
- the four-pass chain threads one `Pair` record whose fields swap roles per pass,
  so four passes allocate two buffers and no more; four is even, so the answer
  lands in the caller's own buffer
- `U32.rem` does not exist; the modulo is `U32.mod` (`base.bend:1611`)
- affinity: `scat.dig` takes `+d` (the digit indexes the cursor table and then
  writes it back), `red.got` takes `+key` and `+x` (compared, then stored)

## Deliberate ceilings

- U32 keys, eight-bit digits, four passes — fixed, not a parameter. A 16-bit
  digit is 65,536 buckets and two passes; it wins only above ~10^8 elements and
  costs a 256 KB table, so it lands if a consumer ever asks.
- No k-way merge, so `radix_par` returns sorted runs rather than a sorted Vec
  (finding 3).
- `reduce_by_key` folds U32 values. Float aggregation lands with the first float
  consumer, like `Scan` over F32 (KNN / FFT).

## Battery

power 48/0 (+ control) · repo 54/54 · caps ok · bench 12/12 checksums match C.

## Next

Lane 5 — streaming JSON + schema. Independent of the Vec chain: the parser state
is a plain value, which is what makes lane 17 (forkable grammar state) free
later.
