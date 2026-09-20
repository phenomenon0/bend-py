# Lexer-perf lane report (fable, 2026-09-19)

Branch `lane-lexperf`, worktree `bend-work-lexperf`, off `omen` at `270df1e8`. Nothing pushed.
`bend2/**`, `gates/**`, `tests/caps.sh`, `demos/python/**` and other namespaces' tests untouched.

## Verdict

**The quadratic was real, it was not in the lexer's source, and it is already fixed on `omen`.**
`demos/python/lexer.bend` + `scanner.bend` are unchanged by this lane. The 15.8 s / 25.1 s readings
came from binaries built in the parser lanes' worktrees, whose `bend2/` predates the runtime fix
`8f782000` (lane-strfix: *cons-after-uncons is a view*). The same lexer source built on `omen`'s
runtime lexes the 986 KB file in **0.95 s** and parses it whole in **1.05 s**, linear to 7.9 MB.

This lane adds one regression guard (`tests/parser/lexscale.py`), re-runs the whole P12 corpus
procedure on `omen`'s runtime (it had only ever been measured on the old one), and reports one
**new, separate** superlinear term found on the way: the **parser's** `Block` accumulator.

**Action for the parser program:** `lane-parser-p13` is based on `lane-parser-p12`, which does not
contain `8f782000`. Its corpus runs will still show ~25 s files until it merges `omen`.

## Profile

Input: prefixes of `Maestro/app/launch.py` cut at a top-level `def`/`class` (each tokenizes clean
under CPython), idle machine, `PY_MODE=lex`, C lane, `--gpu off`, wall seconds.

| build (same `demos/python` source in every row) | 248 KB | 496 KB | 986 KB | exponents |
|---|---|---|---|---|
| P12 lane's binary (`bend-work-parser-p12/_out/parser`, pre-strfix base) | 1.22 | 4.67 | 16.66 | 1.94, 1.83 |
| `8f782000^` (adaptive-width strings, no strfix) | 8.80 | 36.67 | 137.50 | 2.06, 1.91 |
| `8f782000` (strfix integrated) | 0.24 | 0.51 | 0.97 | 1.09, 0.93 |
| `omen` `270df1e8` (this lane) | 0.24 | 0.49 | 0.95 | 1.03, 0.96 |

The token JSON is **byte-identical** across the `8f782000^`, `8f782000` and `omen` builds at all
three sizes (`cmp`), so the speedup changes no output.

**The quadratic term.** The scanner peeks a character by matching `SCon{h, t}` and, when the run
ends, hands back the remainder as `SCon{h, t}` (`scanner.bend` `span`, and `quoted`'s
`String.starts_with(SCon{h, t}, delim)` once per string character). Before `8f782000` the runtime
rebuilt a packed string on that re-cons — a copy of the whole remaining source, once per token
(once per character inside strings): Θ(n) × tokens = Θ(n²). `8f782000` makes cons-after-uncons
return the original view in O(1). None of the brief's suspects applied: there is no
`String.drop` loop (one `drop(rest, 1n)` on a `.`-led number), line/col are threaded incrementally
through `advance`, and `take`/`span` walk only the token they return.

`omen`, beyond the file (launch.py concatenated with itself; still valid Python):

| size | 0.99 MB | 1.97 MB | 3.95 MB | 7.89 MB | exponents |
|---|---|---|---|---|---|
| lex s | 0.99 | 1.88 | 3.81 | 7.95 | 0.93, 1.02, 1.06 |
| whole parse s | 1.10 | 2.23 | 4.19 | 8.50 | 1.02, 0.91, 1.02 |
| lex peak RSS | 157 MB | 311 MB | 620 MB | 1.24 GB | linear |

## Fix

None to the lexer: rung one of the ladder — the change already exists where every caller routes
through (the runtime), and rewriting `span`/`quoted` to dodge a copy that no longer happens would
be churn against a byte-identical-output requirement. What was missing is a tripwire, since the
lexer's linearity now rests on a runtime property no parser test observed:

- `tests/parser/lexscale.py` (hooked into `run.sh`'s full run): `PY_MODE=lex`, C lane, a
  many-token source at 10,000 and 40,000 lines, best of three, fails if the 4×-size ratio
  exceeds 8 (linear 4, quadratic 16). Reads **3.8–4.1** on `omen`; the P12-era binary reads
  **13.7** (2.37 s → 32.39 s) on the same two files, so it would have failed there. A ratio, so
  machine-independent. `subprocess`'s `timeout=` polls on a 50 ms grid; readings are that coarse
  (so are `diff.py`'s `ms`).

## Before / after

Before = the P12 lane's binary / P12 report. After = `omen` `270df1e8`. Same sources.

| measurement | before | after |
|---|---|---|
| launch.py (986 KB) lex-only, idle | 16.66 s (P6 report: 15.8 s) | **0.95 s** |
| launch.py whole parse, idle | 16.55 s | **1.05 s** |
| launch.py whole parse, 14 copies at once (16 cores) | — | 1.82–1.97 s |
| launch.py in the corpus run (14-way) — the corpus slowest | 25.09 s | **2.18 s** |
| slowest segment file (959,619 B, launch.py's) | 24.29 s | 3.40 s |
| `pydoc_data/topics.py` (775 KB, giant strings) lex / parse, idle | 16.17 / 16.12 s | 0.37 / 0.30 s |
| `wgp.py` (752 KB) lex / parse, idle | 8.73 / 8.75 s | 0.82 / 0.87 s |
| tier 3 slowest whole / segment | 15.79 / 15.82 s | 0.66 / 0.55 s |
| tier 2 corpus wall, 14-way: whole files (8,432) / segments (8,126 files) | not recorded | 76 s / 134 s |
| timeouts against the 30 s cap | 0 (5 s of headroom) | 0 (slowest 3.4 s) |

## Verification (all on `omen`'s runtime, this worktree)

| check | result |
|---|---|
| `bash tests/parser/run.sh` | three full runs: **99 / 1, 99 / 1, 100 / 0**. The two misses are `stmt_functions [interpret]` (run 1) and `stmt_functions [check]` (run 2): the known JS-stack-limit flake inside `bend2/bend.ts` (P8/P11/P12 reports), out of lane. Standalone here 4/6 then 6/6; in the P12 worktree 5/6 on `[check]`. Its `[js]` and `[c]` lanes passed every time. Machine shared with the P13 lane throughout (load 4–7). |
| fixtures | **1196 / 1196** exact |
| fuzz | 2,962 sources / 2,574 accepted / 388 rejected / **0 failures**, 704 negatives (1,408 runs) — P12's counts exactly |
| adversarial | 28 / 28, 0 fail-stops |
| corpus, P12 procedure (one manifest per tier, 100-file chunks 14-way through `diff.evaluate`) | **0 structural + 0 location diffs** on **169,567 segments / 1,463,791 statement nodes** (tier 1: 105 / 1,242; tier 2: 155,212 / 1,313,589; tier 3: 14,250 / 148,960), incl. 6,536 async nodes |
| whole files | tier 1 5/5; tier 2 **8,341 / 8,431 = 98.93 %** (81 refused, 9 oracle failures); tier 3 **705 / 731 = 96.44 %**. Every supported file exact. P12's 8,298 / 8,388 plus the live listing's growth (+43 eligible, +43 parsed); refusal histogram unchanged (walrus 52/23, match, …). JS parity samples 422 + 420 + 37 + 37, 0 mismatches |
| `bun gates/repo.ts` | **PASS 45 / 45** |
| `bash tests/run.sh --strings` | **89 / 0** |
| `bash tests/run.sh` (f64) | **19 / 0** |
| `bash tests/codex/run.sh` | **161 PASS, 0 FAIL**, 0 suite errors |
| `bash tests/regex/run.sh` | **49 / 0** |

The corpus runner and aggregators are P12's `/tmp/p12corpus.py`, `p12agg.py`, `p12segcount.py`
with the worktree path and label prefix substituted; not committed, as in P12.

## Residual limits

1. **Parser: a block of k statements costs Θ(k²)** — new, not the lexer, not fixed here.
   `parser.bend:551` grows a block with `S.fields_append(statements, …)`, which walks the whole
   accumulated list per statement. Measured on `x = f(a, 'b') + 12` × k top-level lines (C lane,
   idle), `PY_MODE=stats` minus `PY_MODE=lex`:

   | k | lex s | stats s | parser share s | exponent |
   |---|---|---|---|---|
   | 12,500 | 0.83 | 1.85 | 1.0 | |
   | 25,000 | 1.71 | 6.41 | 4.7 | 2.2 |
   | 50,000 | 3.04 | 29.94 | 26.9 | 2.5 |

   A 950 KB file of 50,000 top-level statements parses in 22.6 s, 1.9 MB in 133 s: over the 30 s
   cap. The corpus does not hit it (launch.py's 23,088 lines sit in nested blocks; the largest
   blocks are small), which is why it never showed. Fix sketch: accumulate the block reversed
   (`JItem{stmt, acc}`) and reverse once at the two `N.block(statements, end)` exits — a line
   may carry several statements (`a; b`), so reverse-prepend `N.get_body(line)`. Left alone
   because `parser.bend` is being edited by the concurrent P13 lane and the brief scoped this
   lane to the lexer. The exponent above 2 is cache pressure on top of the quadratic walk.
2. **JS lane, same input:** `bun parser.js` on the 50,000-statement file dies after 58 s with
   `bend: memory fault (machine stack overflow?)`. Launch.py-shaped inputs are fine (JS parity
   0 mismatches on the corpus samples). Same cause family as (1); re-measure after it.
3. **The lexer's linearity is a runtime property.** `span`/`quoted` stay O(token) only while
   cons-after-uncons is a view. `lexscale.py` is the tripwire. Making the scanner independent
   of it (return the unmatched `+s` instead of re-consing) is possible but was not needed.
4. **Constants, all linear:** ~150 k tokens/s on token-dense source, ~1 MB/s on real code; peak
   RSS ≈ 160 bytes per source byte in lex mode (the token list plus its JSON), ≈ 100 in parse
   mode — a 32 MiB input (the intake bound) would want ~5 GB. `keyword` scans a 200-character
   table per name and `op_text` takes three prefixes per operator: constant factors, not chased.
   Nothing in the lexer is O(n log n); the fuel is `3(n+1)` and is a machine word.
5. **`8f782000^` is 8× slower than the P12 lane's base** on the same source (137 s vs 16.7 s):
   presumably adaptive-width payloads made the pre-strfix re-cons copy costlier. Moot after
   strfix; not investigated.

## Commits

| slice | what |
|---|---|
| guard | `tests/parser/lexscale.py` + one line in `tests/parser/run.sh` |
| report | this file + the 50 ms-grid comment in `lexscale.py` |
