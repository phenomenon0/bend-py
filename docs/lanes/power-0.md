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
