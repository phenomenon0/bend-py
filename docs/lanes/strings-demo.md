# Lane: strings-demo — the strings tour (fable, 2026-09-18)

Branch `lane-strings-demo`, worktree `bend-work-strings-demo`, off `omen` `b37445e0`.
Foreground only; nothing pushed. A tour, not a race: five vignettes plus an off-by-default GPU
appendix, one runner, one generated hostile log. `bend2/bend.ts`, `bend2/main.ts`, `gates/**`,
`tests/caps.sh`, `base.bend`, `comp.ts` and the existing demos are untouched.

## One deviation, named

**The directory is `demos/strings_tour/`, not `demos/strings-tour/`.** `gates/repo.ts` allows
`^demos/[a-z0-9_]+/…`; all 20 existing demo dirs use underscores, and a hyphen would have made
the gate flag every new file. With the underscore the gate is **45 / 45** with no allow rule
added. If the hyphen is wanted: `git mv` + one allow rule (the orchestrator's call), and `T=` in
the two scripts.

## What was built (all new code; 9 files, 24 KB)

| file | role |
|---|---|
| `gen_log.py` | the one input: `BLOCKS` × 65,536 code points of whole lines (knob.bend's fork shape), a self-spelling stamp per block, emoji/é/ß/combining/NBSP/ragged/long lines, the bait as line 2; writes `.oracle` / `.oracle_gpu` (ASCII-whitespace split — Python's bare `split()` would count NBSP as a space and disagree with Bend) |
| `views.bend` | v1: one `File.read`, every line a view (counted, longest measured), `$N` scattered stamp slice+parse+check; reuses `demos/text/slices.bend` (`row`, `parse`, `visits`, `verdict`) by import |
| `codepoints.bend` | v2: six rows, three of them the honest ones (ASCII-only case/trim, combining mark) |
| `fuel.bend` | v3: reads only the first 64 KiB; `^(a+)+$` (cost known up front) and `a.*b\|a` under a 1,000,000 budget (the error) |
| `oops.bend`, `viewcap.bend` | v5: the double-consume that must not compile; `$N` live views of one string |
| `run_tour.sh`, `selftest.sh`, `README.md` | runner (flags `BLOCKS N THREADS RUNS SHARED GPU GPU_MEM ONLY`), self-test, measured table + on-camera lines |

Reused unchanged: `demos/text_stream/main.bend` (v1 stream), `demos/parallel/knob.bend` (v4),
`demos/parallel/gputext.bend` (appendix), `demos/text/_lib.sh` (`timed`). The probe harness at
`/tmp/strings3way` no longer type-checks on this branch (`String.pad_start` takes a `Char` now),
so its probe lines were lifted into `codepoints.bend` and the runner's live footnotes instead.

## What ran

1. `selftest.sh` (4 blocks, 277 KB) **before** any full-size run, and again at the tip:
   **11 / 11 ok** — views, codepoints, fuel, viewcap, text_stream/main, knob, gputext each
   CLI = emitted JS = emitted C; knob and gputext equal to the Python oracle; `oops.bend`
   rejected with `consumed more than once`; the whole tour plays at `BLOCKS=4`. ~27 s.
2. Small tour (`BLOCKS=16`, 1.1 MB), then two full tours (`BLOCKS=4096`: 282,788,890 bytes,
   268,435,456 code points, 3,129,171 lines), the first with `SHARED=1 GPU=1`.
3. `bun gates/repo.ts`: **45 / 45** with the new files tracked.

## Measured (C lane, 7700X 8c/16t, 30 GB, RTX 3090; **under load**, load average 8–16)

| # | what | run 1 (load 8) | run 2 (load 16) |
|---|---|---|---|
| 1 | stream 283 MB, 64 KiB chunks | 2.70 s, 3 MB | 1.91 s, **2,532 KiB** |
| 1 | load (read + decode) | 1438 ms | 1047 ms |
| 1 | 3,129,171 lines as views, each measured | 840 ms | 544 ms |
| 1 | 1,000,000 scattered slice+parse+check | 189 ms, all correct | 118 ms, all correct |
| 1 | views peak RSS | 1,296 MB | 1,295 MB |
| 3 | `^(a+)+$`, 4,097 cp bait | 39 ms | 21 ms |
| 3 | `a.*b\|a` to `budget exhausted at code point 7` | 37 ms | 22 ms |
| 3 | footnote: Python `re`, first 22/24/26 `a` only | 0.13 / 0.57 / 2.30 s | 0.11 / 0.45 / 1.78 s |
| 4 | scan, `--threads` 1 / 4 / 16, median of 3 | 2.97 / 0.94 / 0.58 s (5.15×) | 2.10 / 0.56 / 0.33 s (6.29×) |
| 4 | `SHARED=1` 1 / 4 / 16 | 3.18 / 2.07 / 1.87 s (1.70×) | not run |
| 5 | viewcap 16,000,000 / 17,000,000 | counted, 0.99 s, 1.28 GB / fail-stop, exit 1, 0.56 s | same outputs |
| A | gputext `--gpu off` / `--gpu 8GB` | scan 472 ms / 1855 ms, same bytes | not run |

All v4 / appendix outputs: `36272974:160058848` (`:1470932`), byte-identical across thread
counts and lanes and equal to the Python oracle. Run 2 was *faster* under *higher* load: the
load average is other jobs' demand, not a calibration — hence the ranges, and no quiet-machine
claim anywhere.

Historical numbers are printed only with a date tag: `find_all` 14.2 s → 0.02 s
(`8f782000`, 2026-09-18); 2.7 MiB streaming RSS and the 2.03× (vs 1.5× target) ASCII RSS
**miss** (lane-stream / lane-adaptive, 2026-09-18). The streaming RSS is also re-measured live
(2,532 KiB on this log, consistent with the record).

## Honest limits and things found

- **Vignette 3 is two facts, not one.** The brief's "returns a budget error in linear time" is
  not what `^(a+)+$` does: the Pike VM simply *answers* (no match) in linear time, and its cost
  (weight 96 × (n+1) = 393,408 units) is known before it runs. The budget *error* needs a
  genuinely super-linear call, so the vignette adds the rescan pattern `a.*b|a` on the same
  line: `budget exhausted at code point 7, no partial answer`, in ~20–40 ms. Both are shown;
  neither is dressed as the other.
- **`--gpu 4GB` is out of memory on the 4096-block log** (`bend: out of memory: run again
  with a bigger span`); the appendix defaults to 8GB. My first runner swallowed that failure
  silently under `set -e`; it now prints the runtime's message and exits 1.
- The fail-stop message is `bend: runtime fail-stop` — loud and exit 1, but it does not name
  the view count; the vignette brackets it (16.0M passes, 17.0M stops) to make the cause plain.
- One astral character makes the whole payload 4-byte cells: 1.3 GB RSS for a 283 MB log.
- "A slice does not register on the clock" is true per slice (≈120–190 ns); a million do
  register: 118–189 ms. The README's narration says both.
- Case/trim/words are ASCII-only (NBSP is not a space; `ß`, `ı` unchanged); the footnotes give
  Python the full Unicode case win. A combining mark is its own code point (as in Python).
- The JS lane slices in O(offset) (200 visits on 4 blocks: fine; a million: not attempted).
  Self-test sizes are therefore small; the full tour is C-lane only.
- Not run: a quiet-machine pass, `BLOCKS=1024` timings (the size is documented, 71 MB, not
  timed), Metal, the interpreter on the full log.
- The authoring tool converted `\u` escapes in two files to literal invisible characters once;
  caught by `cat -A`, fixed (`chr(0xa0)`, `String.fromCodePoint`, the generator's escapes restored), and
  `gen_log.py`'s output verified byte-identical before/after.
