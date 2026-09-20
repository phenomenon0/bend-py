# Lane: strings-adaptive — adaptive-width packed payloads

Branch `lane-adaptive` (off `omen` at ee48b782). Commits 6f882a3c, 54955c69,
and this report. Representation change only: no op surface, descriptor,
ownership or semantics change. `bend2/bend.ts`, `bend2/main.ts`, `gates/**`,
`tests/caps.sh`, `base.bend` and other namespaces' tests are untouched.

## Design

A String is still the two-word view `{payload Term, off<<32|len}`; the payload
is still a `TAG_BUF` term behind `rfc_wrap`. The only new state is a 2-bit
**narrowing** `nar` in the payload Term's aux, bits 5–6, above the 5-bit block
class (`blk_cls` masks `& 31`, so free/drop/size-class paths are unchanged):

| nar | cell | holds | 
|---:|---:|---|
| 0 | 4 B | any scalar (the old layout, bit-identical: old terms read as nar 0) |
| 1 | 2 B | ≤ U+FFFF |
| 2 | 1 B | ≤ U+00FF |

- Cell capacity `str_cap(d) = 1 << (cls + nar)`; the block's words are unchanged.
- `str_fit(c)` gives the narrowest nar for a scalar; the empty string reads as nar 2.
- All cell access goes through `str_cell` / `str_cell_put`; 2 B cells are read
  and written bytewise through `u8*`, so host, CUDA and Metal share one source
  with no new typedef. KMP prefix tables stay u32 blocks.
- **Views never change width** (take/drop/slice/trim/split/uncons stay zero-copy,
  `off`/`len` are in cells). The in-place protocol is preserved: a unique
  payload is reused iff it is writable, has room, *and* already has the target
  width; otherwise `str_reserve(.., nar)` reallocates, converting in
  `str_copy_cells`.
- Construction picks the widest cell needed: prepend/pad `str_fit(c)` capped by
  the input, append/push_range/repeat the input's width, join the wider of
  separator and parts, from_list per cell, case transform writes at the input's
  width, static literals are packed at content width at compile time.
- `String.copy` scans the visible cells and compacts to their width (the one
  op that narrows).
- `io_str` (file/stdin/argv decode) is one pass: start at 1 B sized for the
  byte count, and on the first scalar that does not fit, move what is decoded
  into a payload of that width sized for `len + 1 + bytes left` (at most two
  moves).
- JS lane: native strings, no change. Reference (`base.bend` SCon/SNil): no change.

## Slices

1. **6f882a3c** — nar discriminator, accessors, every native op, `str_reserve`
   width parameter, packed literals, two-pass exact-width `io_str`; runtime
   probe: `cells()` cycles widths so every oracle compares mixed-width
   payloads, plus a `widths` section (io_str width per text; order/hash/
   Map.bit/copy equality across widths; prepend/append/pad widening; view stays
   wide, copy compacts; wide-separator join; uncons at each width; zero live).
2. **54955c69** — `io_str` single pass with widening (two-pass cost unicode
   acquire +30–50 %, measured; see below); decode fault op in the probe.

## Gates (final code, 54955c69)

| gate | result |
|---|---|
| strings suite (`tests/strings/run.sh`, four lanes, one `[gpu]` row on CUDA RTX 3090) | 85 pass / 0 fail |
| `tests/run.sh` (f64) | 16 / 0 |
| codex | 161 / 0, 0 suite errors |
| regex | 49 / 0 |
| `bun gates/repo.ts` | 44 / 44 |
| `tests/strings/runtime.py` (ASan/UBSan, ownership, retention, oracles) | all ok; 80,493,758 allocations, zero live; 85 injected faults (was 77: +8 `decode`); JS UTF-8 517 vectors; Python oracle 1799 cases |

ttok: `bend2/comp.ts` 80,198 → **80,994** (cap 81,000; 6 left — the UTF-8
decoder was kept inline in `io_str` and one comment shortened to fit);
`bend2/base.bend` 42,318, unchanged (not edited). No cap edited.

## Measurements

`tests/strings/bench.sh`, C lane, `--gpu off --threads 1`, 7 runs, medians.
"before" = this checkout at ee48b782 (`/tmp/adaptive-before`), "after" =
54955c69 (`/tmp/adaptive-after2`). Input bytes: 8 MiB = 8,192 KiB, 64 MiB =
65,536 KiB. The machine was loaded throughout (load average 7–14 on 16
cores), so the bench's wall medians from separate sessions are **not
comparable** to each other; time is judged from the interleaved A/B below.

### Peak RSS (KiB) — stable to ±0.1 % in every run

| case | before | after | ratio | after / input |
|---|---:|---:|---:|---:|
| ascii-8MiB-io-scan | 43,060 | 18,552 | 0.43× | 2.26× |
| ascii-64MiB-io-scan | 329,592 | 133,220 | 0.40× | 2.03× |
| retain-8MiB-view | 43,120 | 18,568 | 0.43× | 2.27× |
| retain-8MiB-copy | 43,108 | 18,352 | 0.43× | 2.24× |
| unicode-8MiB-io-scan (has U+1F600 → 4 B) | 30,832 | 30,768 | 1.00× | — |
| unicode-64MiB-io-scan (same) | 231,476 | 231,272 | 1.00× | — |
| BMP-only 6.67 MiB (unicode corpus minus astral; 2 B) | 28,208 | 18,680 | 0.66× | — |
| Latin-1 6.67 MiB (unicode corpus, non-Latin-1 → é; 1 B) | 29,236 | 14,136 | 0.48× | — |

The last two rows are hand-made corpora run through the unicode-8MiB bench
binaries (single run each; checksums identical before/after).

### Bench wall medians, as printed (ms; wall / acquire / process)

| case | before | after (different session, heavier load) |
|---|---|---|
| ascii-8MiB-io-scan | 117.5 / 22.2 / 85.8 | 204.8 / 33.3 / 167.4 |
| ascii-64MiB-io-scan | 874.8 / 173.6 / 677.4 | 1472.2 / 235.8 / 1224.5 |
| unicode-8MiB-io-scan | 102.3 / 27.6 / 70.7 | 93.4 / 21.4 / 68.7 |
| unicode-64MiB-io-scan | 722.9 / 165.2 / 543.4 | 739.8 / 174.2 / 552.7 |
| retain-8MiB-view | 25.0 / 21.2 / 0.011 | 20.0 / 17.5 / 0.009 |
| retain-8MiB-copy | 27.3 / 23.2 / 0.012 | 19.8 / 17.4 / 0.009 |

The ASCII rows ran while the load was highest (the same session's `base/c`
rows were also ~2× their usual); the unicode and retain rows ran later and
are *faster* than "before". Neither direction is evidence — hence:

### Interleaved A/B, before vs after binaries alternating (load 12–14)

Wall phases from the BENCH marks, ms, min / median:

| case (runs) | acquire before | acquire after | process before | process after |
|---|---|---|---|---|
| ascii-8MiB (25) | 22.4 / 33.6 | 23.2 / 31.8 | 97.4 / 142.3 | 109.8 / 168.7 |
| ascii-64MiB (9) | 252.5 / 281.2 | 207.5 / 258.8 | 948.6 / 1162.7 | 1181.1 / 1309.1 |
| unicode-8MiB (25) | 24.2 / 30.5 | 26.5 / 36.8 | 85.7 / 119.8 | 88.2 / 128.9 |
| unicode-64MiB (9) | 180.7 / 237.6 | 216.1 / 283.3 | 632.6 / 939.6 | 680.3 / 1022.5 |

Whole-process CPU (rusage user+sys), ms, min / q1 / median:

| case (runs) | before | after |
|---|---|---|
| ascii-8MiB (25) | 114.4 / 122.1 / 153.6 | 116.7 / 123.6 / 136.7 |
| ascii-64MiB (7) | 898.4 / 902.2 / 915.6 | 921.3 / 923.8 / 936.0 |
| unicode-8MiB (25) | 88.7 / 95.1 / 130.4 | 96.5 / 100.9 / 114.4 |

Earlier interleaved runs at slice 1 (quieter, load ~10): ASCII process min
86.1 → 91.5 (+6 %); CPU min 113.3 → 112.2 (equal); unicode CPU +11 %.

**Honest reading: there is a time regression, and it is not only noise.**
The process phase (per-cell reads through `str_cell`'s width dispatch:
uncons, lines, trim, words) is slower by roughly **+6 % to +13 % on ASCII
(one loaded 64 MiB run showed +24 % min)** and **+3 % to +8 % on unicode**.
Whole-process CPU is **+2–2.5 % on ASCII** (acquire is cheaper with the narrower payload — 64 MiB acquire min 252 →
208 ms; fewer page faults is the likely cause, not measured)
and **+5–9 % on unicode**, which gets no memory benefit on this corpus. A
gprof build is flat: ~14 M `str_cell` calls for 5.2 M cells, no hot spot;
reordering the dispatch branches made no measurable difference.

Two-pass vs single-pass `io_str`: with the two-pass decode (slice 1) the
bench's unicode-64MiB acquire median was 165.2 → 230.3 ms; with the single
pass, interleaved unicode-8MiB acquire min is 19.9 (before) → 24.3, and the
final bench's unicode-64MiB acquire median is 174.2.

## Deviations

- **Target "~1.5× input RSS" is missed: ASCII lands at 2.03× (64 MiB) /
  2.26× (8 MiB).** The floor is structural: `bend2/effs/file_read.c` reads the
  file into a malloc buffer on a worker thread and then calls `io_str`, so
  file bytes + 1 B payload = 2× input, plus the fixed runtime. The payload
  itself is now 1.0× input (was 4×).
- `io_str` no longer sizes the payload exactly: it allocates for the byte
  count (an upper bound on cells). For pure ASCII that is exact; for
  multi-byte text the class can be up to one step larger than the two-pass
  version. The probe's exact-size assert became an upper bound accordingly.
- Op results take the *inputs'* width, not the content's: a slice/view of a
  wide string stays wide; case transform and repeat keep the input width;
  only `String.copy`, `io_str`, literals and from_list look at content.

## Honest limits

- Per-cell width dispatch costs the few percent above on every read path.
- One astral scalar makes the whole payload 4 B (the bench's unicode corpus:
  no RSS change, only the dispatch cost).
- Late widening: a wide scalar near the end of a large narrow text holds both
  payloads during the move (peak ≈ n + 4n bytes on top of the file buffer),
  worse than the old fixed 4n for that input. Not benchmarked; the probe
  covers its correctness and its fault paths (`decode` fault op).
- Widening a unique payload by append/prepend/pad of a wider scalar
  reallocates and copies once (amortised as before afterwards).
- Metal is unverifiable on this machine; CUDA ran only the suite's one
  `[gpu]` row. The cell accessors are plain `u8*` reads shared by all devices.
- All timings were taken on a loaded machine without `perf`/`valgrind`.

## Deferred

- Decode straight from the fd into the payload (or in chunks), removing the
  file buffer: the only route to ~1.0–1.5× RSS. Touches `bend2/effs/` and the
  worker handoff.
- Width-specialised inner loops (hoist the dispatch out of lines/trim/words/
  search/hash) to win back the process-phase cost; not attempted — `comp.ts`
  has 6 ttok left under its cap.
- Narrowing on ops other than copy (e.g. a slice of a wide text that is
  itself ASCII).
