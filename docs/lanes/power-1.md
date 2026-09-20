# power-1 — Vec / Bytes / Bitset (2026-09-20)

Lane 2 of the plan: the data floor the later primitives stand on. Three files
over Base's `Array<U32>`, each held to a CPython oracle on four lanes.

## What shipped

- `power/vec.bend` — `Vec`: growable packed U32 sequence. `new len push pop at
  get put set swap truncate from_list to_list`. Oracle: CPython `list`.
- `power/bytes.bend` — `Bytes`: growable byte buffer, four bytes per U32 cell of
  a Vec, little end first. `new len push pop at get put set truncate from_list
  to_list`. Oracle: CPython `bytearray`.
- `power/bitset.bend` — `Bitset`: fixed 32·2^depth bits. `new size set clear
  flip test and or xor andnot count from_list`. Oracle: a CPython int.
- `tests/power/{vec,bytes,bitset}_gen.py` + their fixtures: a seeded op script
  (~150 ops) replayed against the oracle; every observation is one `#|` line.
  Out-of-range and 0xFFFFFFFF indexes are in every script.

## Two facts this lane found (they bind every later lane)

1. **The compiler refuses an open Array element type** (`arr_open`,
   comp.ts:2341): an Array is laid by its element. So there is no generic
   `Vec<T>` without a compiler change; `Vec` is U32. An F32 vector is a second
   type or `F32.bits` over this one — decided in the KNN lane, where it is needed.
2. **An Array does not fork for free.** A match on `ANode` is `blk_half` twice —
   each half allocated and *copied* — and `ANode{l, r}` copies both back
   (comp.ts:4583). Bitset's whole-set ops were first written as the fork tree
   (`Array.map`'s shape). Measured, 2^22 cells, Ryzen 7 7700X, `--gpu off`:

   | 20 × xor, then count | 1 thread | 16 threads |
   |---|---:|---:|
   | fork to single cells | 2.54 s | 0.93 s |
   | fork to 2^10-cell blocks, index loop inside | 0.55 s | 0.68 s |
   | fork 4 levels | 0.32 s | 0.43 s |
   | **no fork: one in-place index loop** | **0.05 s** | 0.05 s |

   100 × popcount of the same set: 1.74 s (blocks) → 0.43 s (loop), ~1 ns/cell.
   The loop shipped. Consequence for Scan / Radix / KNN / FFT: parallelism over
   an *array* pays a full copy per fork level, so it must be bought with heavy
   per-cell work or taken over leaf-private data (tree-radix's shape), never
   assumed. Each of those lanes measures it.

## Written for Bend

- capacity is one shift of a stored depth, never `Array.size`
- Vec growth is `ANode{old, [x : U32^d]}`: one copy, indexes stay put, and the
  pushed element is the fill, so no default element is asked for
- Bytes: `len` is the truth — pop and truncate move nothing; push masks its slot
  instead of trusting it clean (the mutant without the mask fails all four run
  lanes, so the script does reach that case)
- Bitset: the cell operator is a `~f` template parameter, so and / or / xor /
  andnot are four compiled instances of one loop with the operator inline;
  popcount is the SWAR ladder
- checker rules met on the way: a def that matches a parameter must do so before
  it opens a pair (so `step` takes the state already opened and `open` opens
  it); a self-call's measure leads the argument list

## Deliberate ceilings (`ponytail:` in the source)

- Bitset zip of two different sizes: the left size stands, the right wraps. A
  checked door when a caller can hold mixed sizes.
- Indexes of `at` / `put` / Bitset bit ops wrap at the capacity (the Array's own
  rule); `get` / `set` are the checked doors on Vec and Bytes.

## Battery

power 24/0 (+ control) · repo 54/54 · caps ok (nothing in `bend2/` touched).
Not re-run this lane: strings / regex / parser / lint / translator / codex —
no file they read was changed.

## Not done / next

- packed `File.read_bytes` effect (today a cons list): needs a row in `effs/`;
  lands with the first lane that reads a real file (FastCDC / BLAKE3).
- Bitset `to_list` / next-set-bit iteration: lands with posting lists (BM25).
- Bytes `word_le` (a u32 at a byte offset): lands with BLAKE3.
- Next: Heap / TopK / Beam on Vec.
