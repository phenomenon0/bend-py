# Regex lane — R5 + R6 report (fable, 2026-09-18)

Branch `lane-regex`, worktree `bend-work-regex`. Continues `regex-r34.md`. Nothing pushed.
`bend2/bend.ts`, `bend2/main.ts`, `bend2/base.bend`, `gates/**`, `demos/**`, `tests/caps.sh`,
`tests/parser/**`, `tests/strings/**` untouched.

**Continuity.** The first R5 session committed the natives (`928a040f`) and was then SIGTERM'd:
the kernel OOM-killed a 4 GB `bun` child while three lanes ran suites concurrently. This report is
the resumed tail, run strictly serially. The 4 GB `bun` was **this lane's own**: the draft
`runtime.py` had a forged row `ISave{4294967296n}`, and a `Nat` literal expands in unary — the
`-o` compile sits past 4 GB RSS for 10+ min before anything else happens (reproduced, killed at
4.0 GB; `16777215n` instead fails fast with `a literal too large to expand`). Both operands are
now computed (`Nat.mul(U32.to_nat(65536), U32.to_nat(65536))`, `U32.to_nat(16777215)`): the two
programs build in ~1.5 s each.

## Slices

| slice | commit | content |
|---|---|---|
| R5 natives | `928a040f` | `comp.ts` +282/−3: rows `regex_exec` / `regex_match_at`; C `re_exec_take` (program packed `op:8\|a:24\|b:24`, sets in a side block `lo\|hi<<32`, raw + closed thread banks, slot rows, generation-stamped visited, `err_spun` polling, a bounds pass that turns any out-of-range pc/slot into a dead thread; one scratch block per call, host and device from one source); JS `re_exec` mirror over `Int32Array` by `codePointAt` (`at` costs one prefix scan). |
| R5 runtime | `5970a0b1` | `tests/regex/runtime.py` |
| R5 bench | `35893bcd` | `tests/regex/bench.bend` + `tests/regex/bench.py` |
| R5 gpu | `d783858f` | `tests/regex/gpu.bend` + the gpu lane in `tests/regex/run.sh` |
| R6 | this commit | this report |

`base.bend` is unchanged since R4: the reference VM stays the oracle, the natives add 0 to base.

## ttok

| file | before R5 (`3ea7d078`) | final | delta | cap |
|---|---|---|---|---|
| `bend2/base.bend` | 42,318 | **42,318** | 0 | 43,000 ok |
| `bend2/comp.ts` | 75,152 | **79,935** | +4,783 | 76,000 — **over** |

(`ttok` CLI; `bun gates/repo.ts` reads the same 79,935 and is 43 / 44, the comp cap its only FAIL.
Mid-native reading was 78,204.) Caps not edited; next round thousand is **80,000**, which leaves
65 tokens — the plan's 80–83k expectation suggests **81,000**. Orchestrator's call.

## Test counts (at `d783858f`, every suite run alone, serially)

| suite | result |
|---|---|
| `bash tests/run.sh` | **16 / 16** |
| `bash tests/regex/run.sh` | **49 / 49** — 12 fixtures × check/interpret/js/c + `gpu` [gpu]; `--selftest` ok. (40 / 40 re-verified at `928a040f` before the new fixtures.) |
| `python3 tests/regex/oracle.py --jobs 4` | **0 diffs** — C 5,000, JS 5,000, interpret 500 (3 min 04 s). Natives live in C and JS; the interpret lane is the reference VM. |
| `python3 tests/regex/runtime.py` | **ok** — see below (34 s) |
| `bash tests/run.sh --strings` | **85 / 85** |
| `bash tests/codex/run.sh` | **161 / 161**, 0 suite errors |
| `bun gates/repo.ts` | 43 / 44 — the comp cap only; the new files pass the allow list |

No lane flaked in this session; nothing was retried.

### runtime.py

Two generated Bend programs over the same 328 rows (240 seeded oracle-generator pairs with flags at
assorted `at` incl. past the end, + 11 forged programs × 2 `ngroups` × 4 subjects = 88), each row
`[exec, match_at]`: one through `Regex.exec` / `Regex.match_at` (natives), one through
`Regex.exec.go` (reference, no native row). C built with clang 21 `-O1 -fsanitize=address,undefined
-fno-sanitize-recover=undefined`, every `heap_alloc` / `heap_free` tracked (double alloc, double
free, class mismatch assert), the VM scratch block counted.

| program | lane | tracked allocs | kept at exit | VM scratch blocks | scratch live |
|---|---|---|---|---|---|
| native | C `--threads 1` and `8` | 347,471 | 3,031 | 656 (= 2 × 328) | **0** |
| reference | C `--threads 1` and `8` | 445,613 | 3,031 | 0 | 0 |
| both | JS | — | — | — | byte-identical to C |

ASan/UBSan clean; stdout byte-identical across native/reference × C(1)/C(8)/JS. Forged programs
(empty, no `IMatch`, self loops, pcs at 99 and 2²⁴−1, slots at 7 and 2³², a save after the
match, a set with no ranges) die quietly as `None{}` or match exactly as the reference does.

## Benchmarks

Ryzen 7 7700X, clang 21.1.7, bun 1.3.4, Linux 6.17; `bun bend2/main.ts -o`, C with `--gpu off
--threads 1`; per row one untimed warm process then the **median wall time of 7 fresh processes**
(process start and text construction included; the `base` row is that floor). Another lane was
running on the machine. Text = k lines of 64 code points + one 42-cp tail line, the only place a
pattern matches, so one `exec` reads everything. n is code points (1 MiB = 1,048,576; ≈ 1.06 MiB
of UTF-8). Raw rows: `tests/regex/_out/bench-*.json` (gitignored).

Patterns: p0 `Fable@Bend` · p1 `[0-9]{4}-[0-9]{2}-[0-9]{2}` · p2 `<(\w+)@(\w+)\.(com|net|org)>`
flag `i` · p3 `q.*X.z$` flag `m` (a `.*` thread alive on every line).

### scan, 1 MiB

| row | C native | JS native | C reference @ 64 KiB | C reference @ 1 MiB |
|---|---|---|---|---|
| base (build + `String.length`) | 3.5 ms | 48.3 ms | — | — |
| p0 | 13.2 ms | 58.6 ms | 146 ms | — |
| p1 | 15.8 ms | 88.8 ms | 150 ms | — |
| p2 | 15.7 ms | 62.4 ms | 160 ms | **40.0 s** (1 run) |
| p3 | 23.3 ms | 197.5 ms | 176 ms | — |

Net of the floor the C native runs at **9–19 ns per code point** (≈ 55–110 MiB/s on these
patterns), JS native at 10–142 ns. Natives vs reference on p2 at 1 MiB, C: 40.0 s → 15.7 ms,
**≈ 2,500×** raw (≈ 3,300× net). At 64 KiB the ratio is ≈ 10× raw only because 64 KiB of native
work is under the process floor; the reference is what grows.

### doubling, p2 (m fixed)

| n | C base | C native | × vs half |
|---|---|---|---|
| 1 MiB | 3.5 ms | 15.4 ms | — |
| 2 MiB | 6.8 ms | 29.8 ms | 1.93 |
| 4 MiB | 13.1 ms | 59.6 ms | 2.00 |

| n | C reference | × vs half |
|---|---|---|
| 64 KiB | 0.157 s | — |
| 128 KiB | 0.603 s | 3.84 |
| 256 KiB | 2.560 s | 4.24 |

**Native: linear** (14.2–14.7 ns/cp flat). **Reference VM on C: quadratic in n** (see
Uncertainties) — 64 KiB → 1 MiB is 16× the text and 255× the time.

### `--case rescan` — `a.*b|a` on n `a`s, n(n+1)/2 steps

| driver | lane | n | median | ns / step | × vs half |
|---|---|---|---|---|---|
| native walk (`Regex.exec` from each `end`) | C | 8,192 | 0.485 s | 14.45 | — |
| | C | 16,384 | 1.951 s | 14.54 | 4.02 |
| | C | 32,768 | 7.856 s | 14.63 | 4.03 |
| native walk | JS | 8,192 | 5.070 s | 151.1 | — |
| | JS | 16,384 | 20.02 s | 149.2 | 3.95 |
| `Regex.find_all` (reference VM, budgeted) | C | 512 | 0.093 s | 705 | — |
| | C | 1,024 | 0.371 s | 707 | 4.00 |
| | C | 2,048 | 1.505 s | 717 | 4.06 |

The quadratic is exact and its constant flat: **14.5 ns/step native C, ≈ 150 ns/step native JS
(which also pays the `at` prefix scan), ≈ 710 ns/step through `find_all`**. Every run returned
exactly n matches. `find_all`'s budget caps this case at n ≤ 15,893 (weight 34 · (n+1)(n+2)/2 ≤
2³²−1).

## Deviations

1. **Only `regex_exec` and `regex_match_at` are native.** No `regex_compile` row (compile is
   one-off and not on the hot path; its errors are pinned texts best kept in one place).
2. **The globals do not reach the natives.** `Regex.scan` (under `find_all` / `split` /
   `replace`) calls `Regex.exec.go(..., ne)` for the same-position retry, and `fullmatch` needs
   `full`; neither flag has a native row, so those run the reference VM — the 710 vs 14.5 ns/step
   above. Cheapest next step: in `Regex.scan`, call `Regex.exec` whenever `ne` is false (one
   line of base; rerun the oracle). Not done here: it is a base edit outside this tail's brief.
3. `bench.bend` takes no `--case`: a compiled Bend binary has no program arguments. The flag
   lives on `tests/regex/bench.py --case scan|doubling|rescan|all`, which keeps every def of
   `bench.bend` and swaps `main` for one case at size. `bench.bend`'s own `main` is the same code
   at k = 2 / n = 8, pinned on all four lanes (native spans == reference spans).
4. The reference VM is measured at 64 KiB with medians of 7 and **once** at 1 MiB (40 s a run).
5. `tests/regex/run.sh` said "GPU out of scope"; it now has the strings suite's gpu lane (a test
   with a call bang also runs `--gpu 4GB`). `gpu.bend` is one `all!(…)` transfer whose body forks
   one task per record (`h t = one(re, s) each(re, tail)`), each running `exec` + `match_at`.
6. `runtime.py` vs the strings shape: no hand-written C harness — the emitted C is instrumented in
   place. So "zero live at exit" is asserted for the **VM scratch blocks** (656 allocated, 0
   live); of the general heap, 3,031 cells outlive the run — `main`'s printed result, which the
   runtime never frees — and the script asserts that count is **equal** for native and reference.
   Extra clang flag `-fsanitize-address-use-after-return=never`: with ASan's fake stack clang 21
   fails this translation unit with `Interference usage of base pointer/frame pointer`.
   The call-site asserts are "natives present iff the native program" (C inlines `row`: 144
   sites), not an exact count.
7. Big `Nat`s in harnesses must be computed, never written (see Continuity); `bench.py` does the
   same for its sizes.
8. The C-build arity workaround from R4 (rows nested in `part<k>()` defs of 10) is kept in
   `runtime.py`.

## Uncertainties

- **Why the reference VM is quadratic on C** is not root-caused. Suspect: `Regex.exec.run`
  rebuilds `SCon{Chr{x}, t}` every position to hand `alive` the look-ahead, which on the native
  string representation is likely a copy of the remaining text. It is invisible at oracle sizes
  (≤ 64 cp) and does not affect correctness, but it is what every global pays today (Deviation 2).
- **GPU scope.** `gpu.bend` proves the VM compiles through NVRTC for the device (the embedded
  device source carries `re_exec_take`), runs under `--gpu 4GB` on the RTX 3090 (which fails
  loud without a device) and returns the four-lane bytes in order. It is 7 short records: no GPU
  throughput claim, no Metal run, no large-scratch or many-thousand-task run, and the scheduler's
  placement of each task was not inspected.
- **Interpret lane** has no natives: it is the reference VM (and unary `Nat`), fine at fixture
  sizes, untimed here.
- JS natives are 4–10× the C natives on scans and 10× on rescan; part is the `at` prefix scan
  (`codePointAt` from 0 on every call), which makes any `exec`-per-match loop quadratic in JS even
  when C is not. Not optimized.
- Timings are wall-clock medians on a shared desktop with another lane running; the ratios and
  the doubling fits are robust, single-digit-ms rows are not precise to better than ~10 %.
- The oracle still covers only its generated distribution (see `regex-r34.md`); `runtime.py`
  adds forged programs and `at` past the end, nothing longer than 64 cp. Long-text agreement
  between native and reference is pinned only by the four bench spans at 64 KiB / 1 MiB.
