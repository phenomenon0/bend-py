# Parser lane — P3 + P4 report (fable, 2026-09-18)

Branch `lane-parser`, worktree `bend-work-parser`. Continues `parser.md` (P0→P2). Oracle pin:
CPython **3.11.15** (`/home/omen/.hermes/hermes-agent/venv/bin/python3`; `normalize.py` re-execs
into it). The previous session (codex) died mid-P3 and left uncommitted work; everything below was
reviewed, reworked where wrong, and re-measured before commit. Nothing pushed. `bend2/**`,
`gates/**`, `tests/caps.sh`, `tests/regex/**`, `tests/strings/**` untouched.

## Slices

| slice | commit | content |
|---|---|---|
| P3 | `e55321d4` | `L.step_with(st, names, numbers)` injection point in `lexer.bend` (default `step` = hand scanner); regex NAME/NUMBER candidate `tests/parser/p3/lexer.bend`; harness `tests/parser/p3.py`; four-lane fixture `regex_candidate.bend`. Candidate measured and **rejected**. |
| P4 | `80fd32d8` | `def` (full parameter grammar, annotations, decorators), `lambda`, `for/else`, `global`/`nonlocal`, `del`, `assert`, `raise`, `try/except/else/finally`, `with` (both forms); AST + JSON in CPython field order; `diff.py --segments`; two bugs found and fixed (below). |
| docs | `6fc74fa5` | `demos/python/README.md` subset + fuel argument; pin note. |

## P3 — regex lexer candidate: measured, rejected

Candidate: NAME = `[A-Za-z_][A-Za-z_0-9]*`, NUMBER = `[1-9][0-9]*|0+`, compiled once with
`Regex.compile`, matched with `Regex.match_at` on a per-line cursor rebased to `at = 0`; Unicode
names and every other number spelling fall back to the hand DFA. The rebase is necessary, not a
tweak: `Regex.exec.run` walks the subject to `SNil` with no early exit once an anchored match is
dead, so matching against the whole file is quadratic.

Whole lex corpus: **736 files, 12,242,916 bytes** (every eligible file in the lexdiff corpus — the
brief's "~1000" does not exist; chunks at skip 800/900 were empty). Two runs, hand/regex order
alternated per run. Timings are end-to-end process wall time: launch + intake + lex + JSON output.

| lane | hand (run 1, run 2) | regex (run 1, run 2) | regex / hand |
|---|---|---|---|
| C (`--gpu off`) | 36.3 s (37.6, 35.0) | 44.1 s (45.0, 43.2) | **1.214×** |
| emitted JS (bun) | 142.1 s (141.7, 142.5) | 179.5 s (180.9, 178.1) | **1.263×** |
| interpret (sample, one 2 KB file) | 0.88–0.90 s | 0.92–0.96 s | ~1.05× |
| check | both check; no runtime | — | — |

- stdout sha256 identical across lanes × modes × runs in every chunk (asserted by `p3.py`), and
  tokens asserted against CPython `tokenize`. The candidate is *correct*; it is just slower.
- Verdict per the brief ("kept only if it measures ≥ the hand lexer"): **rejected**. The hand
  scanner stays the default and stays independent of `Regex`. The candidate lives only under
  `tests/parser/p3/` behind `step_with`, with `regex_candidate.bend` pinning token-stream equality
  in four lanes.
- Default-path audit (the `step_with` refactor must cost nothing): lexer output over 200 corpus
  files byte-identical to the pre-P3 `HEAD` binary, C and JS; C 6.05/6.02 s vs 6.14/6.03 s,
  JS 31.8/30.8 s vs 31.0/31.4 s — inside noise.
- Upstream lever (not mine to touch, `bend2/base.bend`): an early exit in `Regex.exec.run` when the
  thread list is empty would remove the need for the per-line rebase and most of the gap.

## P4 — what landed

Grammar, each only as far as `ast.parse` parity requires:

- `lambda` and `def`: positional-only `/`, defaults, `*args`, bare `*`, keyword-only with
  `kw_defaults` nulls, `**kwargs`, annotations (incl. star annotation on `*args`), `-> returns`,
  decorators. "non-default argument follows default argument", duplicate `/`, `*` without a
  following name, anything after `**` are `Syntax`.
- `for … in …: … else:` with `TestList{6n}` targets (so `in` ends the target), `Store` rewrite.
- `global` / `nonlocal` (added: same production, one line), `del` (its own `Del` rewrite and
  "invalid del target"), `assert a, m`, `raise`, `raise a from b` (`raise from x` is `Syntax`).
- `try`: handlers with `as name`, `else` only after a handler, `finally`; a bare `try` needs
  `finally`. `except*` is `Unsupported`.
- `with`: CPython tries the parenthesized item list first and requires `):`; otherwise the
  expression form. Implemented with one backtracking combinator, `P.either`, scoped to the header.
- Still `Unsupported` (by the brief or by scope): imports, classes, `async`/`await`, `yield`,
  `except*`, comprehensions, annotated assignment, slices, walrus, f-strings, non-ASCII identifiers.

`Mode` grew from 20 to 32 cases; `fuel_k` stays 32 (fuzz highwater 3.25 dispatches/token).

### Bugs found by this slice's own evidence

1. **Exponential `with (`** (mine, caught in review before commit): the first draft put the body
   inside the `either`, so a failure inside nested `with (a, b):` bodies reparsed 2^depth times,
   and the retry restarted from the saved fuel, so the budget did not bound it. Fixed: only the
   header backtracks. Regression: `adversarial.py` `with_paren60` (60 nested, error at the bottom)
   — 3 ms C, 41 ms JS.
2. **Trailing `;` end position** (P2-era, inherited by every P4 compound): CPython ends a compound
   statement at its last non-whitespace token, so `def f():\n    return 1;` ends *after* the `;`.
   Found by `--segments` on tier 2 (1 location diff in 107,210 statements:
   `tiny-cuda-nn/scripts/gen_sh.py`). Fixed in `Simple`; 9 fixtures added; fuzz template now emits one.

## Evidence (final tree, `6fc74fa5`)

| check | result |
|---|---|
| `bash tests/parser/run.sh` | **Parser PASS: 68, FAIL: 0** (17 `.bend` × 4 lanes; was 60 pre-P3: +`regex_candidate`, +`stmt_functions`) |
| fixtures (`diff.py --fixtures all`) | 257 parsed / 257 exact; 0 structural, 0 location, 0 refusals |
| `fuzz.py` | 1,273 generated+directed, 1,268 oracle-accepted, **0 failures**, 0 `Limit` on accepted; 125 negative cases (250 runs); 64 JS samples; highwater 3.25 / 32 |
| `adversarial.py` | 28 / 28 runs, 0 fail-stops |
| `lexdiff.py --files 200` | 215 parsed; 0 kind/text diffs, 0 position diffs, 0 refusals; 25 JS samples, 0 diffs |
| `bash tests/run.sh` | PASS 16 / 16 |
| `bash tests/run.sh --strings` | first run 84 / 85 under load (12 corpus processes running; failing test not captured), **retry 85 / 85** |
| `bash tests/codex/run.sh` | 161 PASS, 0 FAIL |
| `tests/regex/oracle.py --pairs 500` | diffs c=0 js=0 interpret(500)=0 |

The 5 fuzz inputs the oracle rejects are all `a < not (b)` from the pre-existing expression
generator (genuinely invalid), not from the P4 templates.

### Corpus — whole files

`supported` is decided independently from the oracle's AST tags; a supported file the parser
refuses is a failure.

| tier | total | excluded | eligible | oracle-failure | parsed = supported = exact | unsupported | structural / location diffs | refusals | fail-stop | JS parity |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 (llm-wiki tools) | 5 | 0 | 5 | 0 | 0 (0 %) | 5 | 0 / 0 | 0 | 0 | 1 / 1 |
| 2 (Project tree) | 8,048 | 1 | 8,047 | 9 | **414 (5.1 %)** | 7,624 | 0 / 0 | 0 | 0 | 414 / 414 |
| 3 (stdlib) | 732 | 1 | 731 | 0 | 27 (3.7 %) | 704 | 0 / 0 | 0 | 0 | 37 / 37 |

The Project-tier forecast of ≥ 60 % is **missed by an order of magnitude, and P4 could not have
hit it**: the first refusal is `import` in 4,789 files and `from` in 3,478 (8,267 of 8,328
refused files across tiers 2+3), `class` in 34, everything else 27. Imports were out of scope by
the brief. The 9 oracle failures are genuinely invalid under 3.11 (unterminated strings, broken
indents, 3.12-only f-string backslashes).

### Corpus — per statement (`diff.py --corpus N --segments`)

Because imports make the whole-file gate nearly vacuous, `--segments` builds one synthetic file
per source file from every top-level or class-body statement the oracle tags supported — whole
lines verbatim, class members under an `if 1:` header so columns are preserved; statements sharing
a line with a sibling are skipped. Every synthetic file is supported by construction, so any
refusal or diff fails the run.

| tier | files with ≥ 1 segment | statements | bytes | parsed = exact | structural / location diffs | refusals | JS parity |
|---|---|---|---|---|---|---|---|
| 1 | 5 | 53 | 18,220 | 5 / 5 | 0 / 0 | 0 | 1 / 1 |
| 2 | 7,561 | 107,210 | 39,172,376 | 7,561 / 7,561 | 0 / 0 | 0 | 390 / 390 |
| 3 | 717 | 21,769 | 8,448,031 | 717 / 717 | 0 / 0 | 0 | 36 / 36 |

**Gate: 0 structural and 0 location diffs on everything supported — met**, on 129,032 real
statements (47.6 MB) plus fixtures and fuzz.

### Token counts (`ttok`, measured; no cap exists for these files; caps not edited)

parser 10,936 (was 6,953) · unicode 8,824 · nodes 4,586 (was 2,637) · lexer 3,410 · scanner 2,981 ·
syntax 1,551 · parse_state 1,440 (was 1,235) · intake 1,240 · operators 1,159 (was 1,170) · main 336.
All inside `gates/repo.ts` caps (demos `.bend` 64k, README 4k, tests/docs 16k; this report 3.4k).
`bend2/base.bend` 42,318 / 43,000, unchanged by this lane. `tests/caps.sh` still carries a stale
28,000 line for base — not mine to edit, flagged for the orchestrator.

## Deviations

- P3 corpus is 736 files, not ~1000: that is every eligible file. Interpreter lane timed on one
  sample only (whole corpus in the interpreter is hours); check lane has no runtime to time.
- `*a = 1`, `for *a in y`, `with a as *b` are **accepted**: the pinned `ast.parse` accepts them
  (they are compiler errors). Codex's top-level-Starred rejection was removed.
- `:` dropped from `expect_token`'s "probably a later-slice production" heuristic: it turned
  `def f: pass` and `except E as: pass` into `Unsupported` instead of `Syntax`.
- `lambda x: int: x` reports `Unsupported` (annotation), not `Syntax`; dropped from `INVALID`
  rather than special-cased.
- Backtracking (`P.either`) is new to this parser; one use, header-only, documented in the README.
- `nonlocal` added though not in the brief's list (same production as `global`).
- Tier 2 was run in 350-file chunks (`--skip/--files`, added) because the Bash tool caps a call at
  10 minutes; several calls overran the cap and completed in the background — every chunk's exit
  code and JSON was collected before aggregation. The tier-2 manifest is a live listing: 8,033
  files at first count, 8,048 at the final run (other lanes writing); `_out/` is not in it.
- All corpus tiers were re-run after the last parser change; the numbers above are the committed tree.

## Uncertainties

- One unattributed strings-battery failure under heavy load, green on the single allowed retry;
  this lane touches nothing those tests read.
- `--segments` covers top-level and class-body statements only; statements nested solely inside
  unsupported constructs (e.g. a `def` containing a comprehension) are not harvested.
- Corpus p50/p95 latencies were taken under 12-way parallel load and are not reported as timings.
- `with_paren60` was not run against the pre-fix binary; the 2^depth claim is from reading the code.

## Remainder (precise)

1. `import` / `from … import` — unlocks the whole-file tiers (first refusal in 99.3 % of refused files).
2. `class` (bases, keywords, decorators) — then comprehensions, f-strings, slices, `yield`,
   annotated assignment, walrus, `async`/`await`, `except*`, non-ASCII identifier normalization.
3. Upstream: early exit in `Regex.exec.run`; then re-measure the P3 candidate.
