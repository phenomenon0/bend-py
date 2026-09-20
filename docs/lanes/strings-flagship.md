# Lane: strings-flagship — one hostile log, five traps, and nothing happens (fable, 2026-09-19)

Branch `lane-strings-flagship`, worktree `bend-work-strings-flagship`, off `omen` `f134bfa7`.
Foreground only; nothing pushed. A frame, not a rewrite: `demos/strings_tour/` keeps its five
programs and its one generated log, and every act now springs a real trap on Python or JS live
before Bend runs the same input. The opener is Stack Overflow's July 20, 2016 outage: their trim
regex, and their line rebuilt from the postmortem (their comment, 20,000 spaces, one `x`) as
line 3 of the log. `bend2/**`, `gates/**`, `tests/**`, `views.bend`, `codepoints.bend`,
`oops.bend`, `viewcap.bend` and the reused demos are untouched.

## Deviations from the approved plan, named

1. **Base.** The plan said `omen` `23f92d70`; `omen` had moved to `f134bfa7` (parser lanes).
   `23f92d70` is an ancestor and `base.bend`, `comp.ts` and `demos/strings_tour/` are
   unchanged between the two, so the lane branches off the tip.
2. **One sentence of the copy was cut, not softened.** Plan mode measured "interpreted, the
   20,000-space line takes 23 s and grows faster than its bill". It does not reproduce: see
   Step 0. The README states the three measured lanes instead.
3. **"Interpreted" became "through the CLI"** everywhere in the copy: see things found, 2.
4. **`run_tour.sh` times the 16,000,000-view run** (`timed`, one word). The runner on `omen`
   never timed it; the old README's 0.99 s was taken by hand, and the copy quotes a time.

## What changed (5 files; no new file under `demos/`)

| file | ttok before → final | ins / del | cap | |
|---|---:|---:|---:|---|
| `README.md` | 1,535 → 3,838 | 232 / 76 | 4,000 | held |
| `run_tour.sh` | 2,201 → 3,531 | 71 / 27 | 4,000 | held |
| `fuel.bend` | 861 → 1,641 | 65 / 34 | 64,000 | held |
| `gen_log.py` | 1,072 → 1,141 | 5 / 2 | 8,000 | held |
| `selftest.sh` | 727 → 833 | 8 / 3 | 4,000 | held |

- `gen_log.py`: line 3 of block 0 is the Stack Overflow line (39 + 20,000 + 1 code points).
  Pool bodies are drawn before it, so they are unchanged; the block order draws shift, so the
  log and both oracles change, self-consistently. The log is now `hostile2-<blocks>.log`: the
  corpus dir is shared between worktrees and a pre-line-3 log must never be picked up.
- `fuel.bend`: three doses of the line (5,000 / 10,000 / 20,000 spaces) under a 2,000,000
  tank, a 20-cell gauge, the same dose refused under 1,000,000 with the price it needed, then
  the bait rows as before. Fail-loud: a log without the line exits 1 and says regenerate.
- `run_tour.sh`: acts reordered (fuel, torn, views, knob, compiler); act 2 builds
  `demos/text_stream/whole.bend` and asserts stream == whole; seven new live `^` lines, each
  printing measured ratios; the `8f782000` record line cut (a commit, not a lane report).
- `selftest.sh`: 11 → 13 checks (`whole.bend` through three lanes; the units pin).

## Step 0 — measured before building (4-block log, load average 1.0–2.1)

| lane | 5,000 / 10,000 / 20,000 spaces | refused | `^(a+)+$` | `a.*b\|a` to the error | whole process |
|---|---:|---:|---:|---:|---:|
| emitted C | 11 / 22 / 40 ms (again: 10 / 20 / 41, 11 / 20 / 41) | 0 ms | 18–19 ms | 44–45 ms | build 2.9 s |
| emitted JS (bun) | 70 / 107 / 186 ms | 1 ms | 79 ms | 220 ms | 0.70 s, build 0.5 s |
| CLI (`bun bend2/main.ts`) | 77 / 138 / 252 ms | 2 ms | 94 ms | 260 ms | 1.35 s |

Rows byte-identical on all three. Every lane is about ×2 per doubling; no stack overflow on
JS. Decision-table branch 1: the copy stands. Regex oracle at this tip
(`tests/regex/oracle.py --jobs 4`, pinned CPython 3.11.15): **5,000 pairs, 0 diffs on C, 0 on
JS, 0 on the 500-pair CLI sample**, 2 min 49 s; so that receipt is tagged with this lane.

## What ran

1. `selftest.sh`: **13 / 13 ok**, twice (29.9 s, 29.7 s; load 2.5 and 5.6), the second at the
   final state of all five files. The tour replays at `BLOCKS=4` with all seven new `^` lines.
2. Two full tours, `BLOCKS=4096`: 282,789,518 bytes, 268,435,456 code points, 3,110,547
   lines; run 1 with `SHARED=1 GPU=1` (1 min 17 s), run 2 plain (32 s). Every value predicted
   in plan mode from the in-memory patch matched the generated log: bytes, lines, oracle
   `36332633:4172640078` (`:1474863`), 192 cut boundaries, first Python raise at chunk 30,
   380 chunks that would, 420 invented U+FFFD, longest line 20,040 code points.
3. README numbers: 258 numeric tokens, 224 found verbatim in the two runs' output by script;
   the other 34 classified by hand (postmortem facts, roundings, `96 × 4,098`, `1,000,000 −
   999,756 = 244`, the Step 0 record, figures quoted from dated lane reports, tool versions).
4. Mutation: a generator with 15,000 spaces in line 3 makes the "20000 spaces" row print
   `872436 of 2000000 units` with no error (`String.take` clamps); the selftest's pin fails on it.
5. Invisible characters (python `unicodedata`, categories Cf / Cc) in the nine tour files: 0.
6. `bun gates/repo.ts`: **45 / 45**. `tests/strings/run.sh`: **89 pass, 0 fail** (2 min 33 s).
   `tests/regex/run.sh`: **49 / 0** (39 s). Both untouched; both equal the asanfix record.

## Measured (C lane, 7700X 8c/16t, 30 GB, RTX 3090, clang 21.1.7; **under load**)

| act | what | run 1 (load 3.2) | run 2 (load 5.2) |
|---|---|---|---|
| 1 | doses 5,000 / 10,000 / 20,000 spaces | 13 / 21 / 53 ms | 12 / 21 / 40 ms |
| 1 | `^(a+)+$` on the bait; `a.*b\|a` to the error | 21 ms; 47 ms | 19 ms; 45 ms |
| 1 | `^` Python `re`, same regex, same line | 0.07 / 0.27 / 1.03 s (×3.7, ×3.9) | 0.07 / 0.26 / 0.84 s (×4.0, ×3.2) |
| 1 | `^` bun, same regex, same line | 0.02 / 0.08 / 0.32 s (×3.6, ×4.0) | 0.02 / 0.07 / 0.27 s (×3.9, ×4.0) |
| 1 | `^` Python `^(a+)+$`, first 22 / 24 / 26 `a` | 0.12 / 0.48 / 1.89 s | 0.10 / 0.39 / 1.52 s |
| 2 | stream, 64 KiB chunks | 2.35 s, 2,532 KiB | 1.74 s, 2,532 KiB |
| 2 | whole-file read, same output line | 2.51 s, 1,295 MB | 2.14 s, 1,295 MB |
| 2 | `^` Python per-chunk decode; `^` JS per-chunk `toString` | raises at chunk 30 (380 would); 420 U+FFFD | same |
| 3 | load; 3,110,547 lines as views; 1,000,000 visits | 1163 / 533 / 115 ms, 1,296 MB | 834 / 513 / 100 ms, 1,295 MB |
| 3 | `^` JS, the same offsets as string indices | 999,756 stamps wrong | same |
| 4 | scan, `--threads` 1 / 4 / 16, median of 3 | 2.15 / 0.59 / 0.31 s (6.97×) | 2.08 / 0.54 / 0.28 s (7.29×) |
| 4 | `SHARED=1` 1 / 4 / 16 | 2.11 / 1.63 / 1.55 s (1.36×) | not run |
| 4 | `^` Python threads, first 64 MiB | 0.35 / 0.34 / 0.31 s (1.12×) | 0.34 / 0.34 / 0.31 s (1.11×) |
| 5 | `^` Python, one stream counted twice | `3110547 0` | same |
| 5 | viewcap 16,000,000 / 17,000,000 | 0.93 s, 1,253 MB / fail-stop, exit 1 | 0.94 s / same |
| A | gputext scan, `--gpu off` / `--gpu 8GB` | 378 / 1825 ms, same bytes | not run |

All act 4 / appendix outputs byte-identical across thread counts and lanes and equal to the
Python oracle. CPython 3.14.2 (a GIL build), bun 1.3.4.

## Honest limits and things found

1. **The plan's "23 s interpreted" is not real.** The same program runs the 20,000-space dose
   in 252 ms through the CLI. Probes: `String.repeat` to 20,000 alone 0.2 s; a rebuilt probe,
   283 ms in the scan, 0.67 s in all. Not root-caused: the likely culprit is the plan-mode
   stdin probe building its own string quadratically, under load 14. It was cut before it
   shipped; the selftest estimate built on it (70–90 s) was wrong too (measured ~30 s).
2. **There is no interpreter lane.** `main.ts:461-462` calls `Comp.io_run`, and
   `comp.ts:1727-1731` builds `js_lib(...) + RUNTIME_MAIN` and runs it with `new Function`:
   the CLI is the JS emitter, run in-process. So `cli = js = c` compares two hosts of one
   emitter, plus C, and the oracle's `interpret` lane (`oracle.py:301-302`) is the same thing.
   This lane's copy says "through the CLI". **Flagged for cleanup, not touched:** earlier lane
   reports and `tests/regex/oracle.py` still say "interpreter" / "interpreted".
3. A literal `20000n` dies at once (`the machine stack overflowed (a deep recursion, or a
   literal too large to expand)`); `fuel.bend` computes it (`U32.to_nat(k)`), as FLOW.md says.
4. `SHARED=1` is 1.36× at 16 threads here against 1.70× in lane-strings-demo: another log
   order, another load, one run each. Both say the same thing: the tree stops scaling.
5. Python's second doubling in run 2 is ×3.2 (0.26 → 0.84 s): load noise on a quadratic. The
   copy quotes the measured span (×3.2 to ×4.0) and the on-camera line went from "about four
   times" to "three to four times".
6. `--gpu 4GB` is still out of memory on the new log (`bend: out of memory: run again with a
   bigger span, as in --gpu 8GB`); the appendix defaults to 8GB.
7. The three budgeted-lane facts the copy leans on are read from source, not measured:
   `Regex.scan.pay` (`base.bend:3590`) refuses before `Regex.exec.walk` runs; `Regex.scan.go`
   re-prices every search from its own `at`; only `Regex.exec` / `match_at` have natives.
8. Plan typo: the head of block 0 is 24,167 bytes (23 + 4,103 + 20,041), not 44,167. It fits
   the 64 KiB `fuel.bend` reads either way.
9. The authoring tool turns a backslash-u escape into the invisible character itself (it bit
   the plan, and lane-strings-demo before it). Procedure used here: text with that escape is
   extracted from verified sources or patched by python, never typed through the editor, and
   the `unicodedata` scan is the check. A byte-level `grep -P` missed them; do not trust it.

Not run: a quiet-machine pass; `BLOCKS=1024` timings (size measured: 70,691,027 bytes); the
JS and CLI lanes on the full log (the JS lane slices in O(offset)); Metal; the codex suite
(its 161 / 0 is quoted from lane-asanfix, dated); a recording (the "On camera" lines are the
script). `tests/regex/_out/` is git-ignored scratch from the oracle run, not committed.
