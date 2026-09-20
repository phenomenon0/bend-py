# power-9 — Blake3 and Cdc: content addresses, and where to cut (2026-09-20)

Lane 9. Two files, and they are one idea: **a content address, and the boundary
that makes the address reusable.** Hash a file and you can say whether you have
seen it. Hash a *chunk* and you can say which parts of it you have seen — but
only if the chunk boundaries survive an edit, which is the whole of what
FastCDC is for. Neither file is much use without the other, so they shipped
together.

## What shipped

### `power/blake3.bend` — the root hash, and the two pieces a fork needs

- `hash(b, off, n) -> Bytes & Cv` — the BLAKE3 root of a byte range.
  `hash_all(b)` for the whole buffer.
- `chunk(b, off, n, t, fl) -> Bytes & Cv` — one leaf: the chaining value of up
  to 1,024 bytes as chunk number `t`.
- `parent(l, r, fl) -> Cv` — one join.
- `compress(c, m, ct, ch, bl, fl) -> Cv` — the 7-round core, exposed.
- `hex(c) -> String` — the 64 digits `b3sum` prints.
- `iv()`, `CHUNK_START/CHUNK_END/PARENT/ROOT`, `blocks(n)` — the constants and
  the block count, because a caller building its own tree needs them.

`chunk` and `parent` are the public surface for a reason. They are what lets a
caller hash the halves of a message on different cores and land on the number a
single pass prints — BLAKE3's tree mode is a *law*, not an approximation, and
`bench/blake3_par.bend` is built to hold the implementation to it.

**Written for the compiled lanes.** The sixteen words of a block, the sixteen
of the compression state and the eight of a chaining value are records of U32,
not arrays. A round is straight-line register arithmetic: no memory between the
G's, no bounds check anywhere in the 448 operations of a compression. Only the
block read touches the buffer.

### `power/cdc.bend` — where to cut

- `new(b) -> Cdc`, `into(c) -> Bytes` — the chunker takes the buffer and gives
  it back. It owns it while cutting because the gear table is an array and an
  array has one owner; handing back a `(Bytes, Vec, U32)` triple every call
  would make the table the caller's problem.
- `cut(c, off, end, bits) -> Cdc & U32` — the length of the chunk starting at
  `off`. `bits` is log2 of the target average: 10 asks for 1 KiB, 13 for the
  paper's 8 KiB.
- `split(c, off, end, bits) -> Cdc & List<U32>` — every cut point of a range,
  ascending, the last of them `end`.
- `topmask(k)`, `avg(bits)` — the arithmetic, exposed.

The gear table is 256 Threefry draws (`Rng.u32(2654435761, 0, i)`) rather than
256 constants transcribed from a reference. A gear entry needs to spread a byte
across 32 bits and nothing more — no collision resistance, no structure — so
generating it is one line here and one line in the C twin and the Python
oracle, and nothing gets mistyped.

## Three things the language decided

### 1. No forward references, so the tree is a stack

BLAKE3's specification describes a recursive tree: split at the largest power
of two chunks, hash both halves, join. **Bend cannot express it.** A def may
not call one defined after it, so the left half and the right half cannot both
be the same function.

`power/blake3.bend` is therefore the *reference implementation's* construction
instead: a chunk stack. Chunks go by left to right; after chunk `t - 1` is
hashed, one perfect subtree has closed for every low zero bit of `t`, so merge
that many times and push. The stack holds perfect subtrees of strictly
decreasing size, left to right, which is exactly BLAKE3's tree. The leftovers
fold right to left at the end.

This is not a workaround that costs something — it is what the official
implementation does, and it is one loop rather than a recursion. But it has a
real consequence for the test: **`tests/power/blake3_gen.py` writes the
recursive tree, deliberately.** The oracle and the implementation are not two
copies of one algorithm. A row agreeing says the two constructions *are the
same tree*.

### 2. A pair cannot be opened mid-body, so the block read is a shift register

Reading a 64-byte block is sixteen word reads, and each hands back a
`Bytes & U32` pair that can only be destructured by a helper. Sixteen nested
readers, each carrying the words already read, is 136 parameters of plumbing.

Instead: one `bk.push` that drops the oldest word of a `Bk` and appends the
newest, run sixteen times from a zero block. The words land in order. Sixteen
identical steps instead of sixteen different ones.

### 3. `Bytes.word_le`, added for this lane

A block read is four bytes at a time, and `Bytes.at` is one. The new
`Bytes.word_le(b, o)` is one native read when `o` is a multiple of four and two
reads glued by a pair of shifts otherwise. `tests/power/bytes_gen.py` gained a
`Word` op whose offsets walk all four alignments — at the front of the buffer,
across a cell boundary, and at the very end, where the second cell it touches
holds bytes past the length. A word must not carry them. `bytes` stayed
`PASS: 6, FAIL: 0` with the rows added.

Padding rides on top of it: BLAKE3 zero-pads the last block of a chunk, `at`
wraps at capacity rather than faulting, so `w.part` masks the valid low bytes
of a straddling word and `w.if` returns 0 past the end. The mask is the whole
of the padding.

## The bug that was worth the lane

`fl` — the caller's extra flags, which is `ROOT` when a chunk is the whole
message — was first applied to **every block of the chunk**. Every published
vector up to 64 bytes passed. Every vector above it failed.

The reason is the shape of the flag: a root is *the last compression of the
tree*, not every compression of its one chunk. A one-block chunk has only one
compression, so the two readings agree exactly while the message is 64 bytes or
less, and diverge the moment it is 65. A test suite that stopped at "hashes the
empty string correctly" would have shipped it.

It is now stated in the file at `ck.one`, and the mutant that restores it
(below) is the first row of the table.

## Rule 9 — the row that is the point of the file

Fifty-nine of the 60 `blake3` rows and eighteen of the 26 `cdc` rows check
*what* the code computes. Eight `cdc` rows check **why anyone wants it**:

```
resync(8192, seed, splice at p, bits) -> "<k> of <n>"
```

Take a buffer, cut it. Splice one byte in at position `p`, cut again. Print how
many *trailing* boundaries the two runs agree on. A fixed-size chunker scores 0
on every one of these — every boundary after `p` moves by one. Content-defined
chunking scores almost all of them:

| splice at | of | agreed |
|---|---:|---:|
| byte 3 of 8,192 | 28 | **28** |
| byte 100 | 28 | **28** |
| byte 4,000 | 28 | 14 |
| byte 7 of 16,384 | 13 | **13** |
| byte 9,000 | 13 | 6 |
| byte 1 of 12,000 | 22 | **22** |
| byte 3, *different seed* | 28 | 1 |
| byte 7, *different seed* | 13 | 1 |

The two control rows are what make it a test rather than a demonstration: same
shape, same code path, unrelated content, and the score collapses to 1 — the
final boundary, which is `end` and matches trivially. A splice mid-buffer
agreeing on only the boundaries *after* it (14 of 28, 6 of 13) is the right
answer, not a weak one: nothing before the splice was ever going to move.

The fixture's byte generator is what makes this writable. The buffer's bytes
are a function of the index — `mix(i)`, a three-round avalanche — not of a
chained state, so splicing one byte in at `p` is exactly a shift of every later
index. No generator state has to be threaded through two builders.

## Verified

`bash tests/power/run.sh blake3` — 60 rows, `PASS: 6, FAIL: 0`.
`bash tests/power/run.sh cdc` — 26 rows, `PASS: 6, FAIL: 0`.
`bash tests/power/run.sh bytes` — `PASS: 6, FAIL: 0` with the `word_le` rows.
Six lanes each: oracle, check, interpret, js, c, c-1thread.

**`tests/power/blake3_gen.py` refuses to print anything until it reproduces all
35 entries of BLAKE3-team/BLAKE3's own `test_vectors.json`** — the official
input (the bytes `i % 251`) at lengths 0 through 102,400. Those 35 vectors are
then the first 35 rows of the fixture, so the Bend implementation is held to
the project's published numbers and not to a second opinion. The remaining 25
rows pin the pieces the published vectors cannot reach: a range that is not the
whole buffer (`at`), a leaf at a chunk counter other than 0 (`leaf` — the
counter is in the hash, which is what stops a tree from being reordered), and a
root built **by hand** from two and four leaves joined with `parent`, whose
answer is the published whole-message vector. That last group is the law
`blake3_par` stands on.

**`tests/power/cdc_gen.py` is an independent Python FastCDC**, whose gear table
comes from a Threefry copied out of the already-verified `rng_gen.py` with its
three Random123 known-answer assertions retained — so the table is proven
before a single row is emitted.

**Mutants** — six, each passing the oracle and the checker and failing all four
executing lanes (`PASS: 2, FAIL: 4`):

| mutant | what it breaks |
|---|---|
| `ROOT` on every block, not the last | the real bug above; passes every vector ≤ 64 bytes |
| `parent` without the `PARENT` flag | domain separation between a leaf and a join |
| `g`'s rotations mirrored (`rotr` args swapped) | the diffusion, not the structure |
| `topmask` returns the low bits | the cut tests a 2-byte window; shift resistance gone |
| minimum is `avg/2`, not `avg/4` | one of the four sizes normalized chunking derives |
| both halves get the same mask | normalization off; the cut works, the distribution does not |

The last two are the useful ones. Both still produce a *valid* chunking —
boundaries ascending, none past the end, resync still working — and both are
caught, because the fixture pins every boundary and not the chunk count.

## Measured (Ryzen 7 7700X, 8 cores / 16 threads, `--gpu off`, medians of three)

| bench | what it runs | C | bend 1T | bend 16T | 1T/C | 1T→16T |
|---|---|---:|---:|---:|---:|---:|
| `blake3` | 16 MiB hashed four times = 1,048,576 compressions | 0.09 | 0.22 | 0.22 | **2.5x** | 1.0x |
| `blake3_par` | 65,536 independent 1 KiB leaves up a 16-level tree | 0.13 | 0.26 | **0.06** | **2.1x** | 4.7x |
| `cdc` | 16 MiB cut four times, at 256 B / 1 / 4 / 16 KiB | 0.03 | 0.17 | 0.17 | 4.8x | 1.0x |
| `cdc_par` | 256 shards × 64 KiB, each cut four times | 0.03 | 0.12 | **0.03** | 3.7x | 4.3x |

Checksums, identical on C, 1T and 16T: 1084526474, 2742522233, 710121685,
751219470.

**These were taken with six other lane agents compiling on the same box
(load average 7-8).** The 1T/C column is stable across runs — it was 2.6 / 2.2 /
4.7 / 3.5 on an earlier pass — but the scaling column is not: `blake3_par`
measured **8.0x** and `cdc_par` **6.8x** when the machine was quiet. The
numbers above are a floor, and they are the honest ones to publish because they
are the ones reproducible right now.

`blake3` is the best 1T/C ratio in the power library so far, and the reason is
the design note at the top of the file: a compression is 448 register
operations on records with no array in sight, which is the shape Bend's C
emitter is best at. `cdc` is the worst of the four at 4.8x, and its inner loop
is the opposite shape — one `Vec.at` and one `Bytes.at` per byte, which is two
bounds-checked array reads against C's two pointer dereferences, with almost no
arithmetic to hide them behind.

**`blake3_par`'s twin does not reproduce the fork.** It fills the whole 64 MiB
and hashes it serially through one chunk stack. The row passes only if 65,536
independent leaves joined up a binary tree and one left-to-right walk agree on
the root. That is a live check on BLAKE3's tree-mode law every time the bench
runs, not an agreement between two copies of one loop.

`cdc_par`'s shard is not a concession either. A `Bytes` holds an array and an
array has one owner, so no two lanes can scan one buffer — but a chunker is
applied to a *file*, and a store has many files, so a lane per shard is a lane
per file, which is how deduplication is actually run.

## Rule 7 — the `acc*31` mixer, and where it stops working

Every `_par` bench in this library folds its leaves with `mix(a, b) =
rot7(a*31 + b)`, the fix power-5 and power-6 arrived at. `cdc_par` at depth 8
folded to **0** — and so did its C twin, which is how it was ruled a real
algebraic collapse rather than a Bend bug.

> `31 ≡ -1 (mod 32)`, so `a*31` destroys the low **five** bits of the left
> operand at every level, and `rot7` only moves the damage seven places on.
> Six levels wreck 30 of 32 positions — two clean bits survive, which is why
> every existing depth-6 bench gets away with it. **Eight levels wreck 40**,
> which covers the word.

power-6 recorded this as "leaves must not share a residue mod 32". The sharper
statement is that `mix` has a **depth ceiling of about six**, independent of
the leaves.

`cdc_par` therefore joins with `tmix(a, b) = rot7(a*2654435761 + b)`. An odd
multiplier is a bijection mod 2^32, so no level destroys anything at any depth.
The leaf chain keeps `mix` — it is a linear fold, not a tree, and the ceiling
does not apply.

**Flagged for cleanup:** this is a second mixer in a suite that had one. Two
would be better as one, and `tmix` is the one that is correct everywhere. The
conversion is mechanical (`mix` → `tmix` in every `_par` bench and twin, then
re-pin twelve checksums) and is not worth doing inside a lane that is not about
benches. `cdc_par`'s comment names the trap so the next depth-8 fork does not
have to rediscover it.

## The other measured deviation: 256 shards, not 64

Every other `_par` bench forks 64 ways. `cdc_par` forks 256. At 64 it scaled
**3.4x**; at 256, on identical total work, **6.8x**.

Two probes ruled out the obvious explanations. 64 shards of 64 KiB scanned 16
times each — a quarter of the buffer construction, the same scan volume —
scaled *worse*, at 2.5x, which rules out fill cost and memory bandwidth. What
is left is task granularity: **the scheduler wants more tasks than it has
threads by a wider margin than four**, and 4× oversubscription is what every
other `_par` bench currently assumes.

Two other lanes found the same shape independently. power-10 went 3.5x → 6.3x
by unbundling eight solves a leaf into one, and power-17's granularity sweep at
fixed total work reads 1.9x / 3.2x / 5.2x at 16 / 64 / 256 shards. Both explain
it by **variance**: their leaves are unequal work (a Jonker-Volgenant solve's
cost swings with its matrix; a JSON document is 3 to 79 bytes), so a fat leaf
bundles the variance and the slowest one sets the clock.

`cdc_par` is the case that isolates the other half of the explanation. **Its
shards are uniform** — 64 KiB each, the same four scans, differing only in
content — and moving from 64 to 256 still bought 2x. So oversubscription pays
here for scheduling slack alone, with no variance to smooth. The rule the three
lanes agree on is therefore stronger than the variance argument on its own:
more tasks than threads by a wide margin, whether or not the leaves are even.

## Written for Bend

- **`Cv`, `St`, `Bk` and `Q` are kind `Data`** — records of U32 with no array —
  so a chaining value can be returned from a fork, sit in a `List`, and be
  copied. That is what makes `blake3_par`'s tree expressible at all. `Cdc`,
  `Rd`, `Ck` and `Hs` hold a `Bytes` and are kind `Type`.
- **`rotr(x, r, l)` takes both shift counts.** `l` is `32 - r`, passed in by
  the caller, so no Nat subtraction runs inside the round.
- The eight G's of a round are eight defs (`cg0..cg3`, `dg0..dg3`) each with a
  `.put` partner, because a `Q` cannot be destructured mid-body and a 16-field
  record cannot be updated in place. It is 16 defs of plumbing for a round that
  is 4 lines in C — the single largest concession in the file, and the reason
  `power/blake3.bend` is 460 lines against the C twin's 130.
- **`cs.go`'s `CHit` variant returns without recursing**, so a cut stops at the
  byte that caused it instead of idling out the rest of its fuel. The two
  normalized halves run back to back rather than choosing a mask per byte: the
  second loop sees a `CHit` from the first and hands it straight back, so the
  normal point costs one comparison per *chunk* instead of one per byte.
- `split`'s fuel is the most chunks a range can hold — one per minimum size —
  so it never runs out before the range does.
- `mg.go` is given 32 fuel: a 32-bit chunk counter cannot close more than 32
  subtrees at once.

## Deliberate ceilings

- **No keyed mode, no key derivation, no extended output.** BLAKE3 has three
  more flag bits and an XOF. Each is a flag and a loop on top of what is here;
  none has a consumer. `compress` is exposed so a caller can build them without
  a change to this file.
- **The hash is a `Cv`, not 32 bytes.** `hex` prints it. Writing it back into a
  `Bytes` is one loop nobody has asked for yet.
- **No incremental hasher.** `hash` takes a whole range. A streaming `update` /
  `finalize` pair is the chunk stack with its state made public — a real
  feature, and the right one to add the day a consumer streams from a file
  rather than a buffer.
- **`cut` reads one byte at a time.** FastCDC's paper also describes skipping
  ahead by the minimum size *without* hashing, which this does (`lo` starts the
  scan), but not the SIMD-friendly two-bytes-at-a-time variant. That one
  changes the boundaries, so it is a different chunker, not an optimization.
- **No chunk store, no dedup index.** Cut, hash, and then compare against what
  you have — the comparison is `Postings` or a hash set, and joining the three
  is an application, not a primitive.

## Battery

`bash tests/power/run.sh` — **`Power PASS: 96, FAIL: 0`** (+ control), the whole
library as it stood when this was written; lane 9's own share is the 12 that are
`blake3` and `cdc`, plus `bytes` re-run for `word_le`. `bash tests/caps.sh` — no
`OVER` rows. The four bench rows' checksums match their C twins at 1T and 16T.

`bun gates/repo.ts` — **`PASS: 54 / 54`**. It read 51/54 mid-lane on three
files none of which were this lane's (two scratch probes other lanes had left at
the repo root, and one over-cap fixture); each was reported to its owner and
each has since been cleared.

`power/blake3.bend` 7,830 ttok and `power/cdc.bend` 2,504 against the 64,000
cap; the two fixtures 3,924 / 2,501 and their generators 4,312 / 3,428 against
16,000; the four benches 801 / 934 / 744 / 1,181. **No cap moved**, no
`gates/repo.ts` edit — lines 76-77 already cover `power/*.bend` and
`tests/power/**`. No `comp.ts` row, no `base.bend` change, no new effect.

`Bytes.word_le` is the lane's only change to an existing power file, and
`tests/power/bytes.bend` grew the rows that cover it.

## Next

Lane 7, budgeted subset selection — apricot's submodular greedy, which is the
first lane whose answer is *chosen* rather than computed, and the first that
will want `Heap` for something other than top-k. Its natural consumer is this
lane: deduplication picks a subset of chunks, and "which chunks are worth
keeping" is a budgeted selection over content addresses.
