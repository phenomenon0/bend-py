# Parser lane — P5 report: `import` / `from` (fable, 2026-09-18)

Branch `lane-parser-p5`, worktree `bend-work-parser-p5`, off `omen` at `ee48b782`. Continues
`parser-p34.md`. Oracle pin unchanged: CPython **3.11.15**
(`/home/omen/.hermes/hermes-agent/venv/bin/python3`). Nothing pushed. `bend2/**`, `gates/**`,
`tests/caps.sh`, and other namespaces' tests untouched. All work ran in the foreground (one
corpus call overran the Bash tool's 10-minute cap and was finished by the harness in the
background; its exit codes and JSON were collected before aggregation — see Deviations).

## Slices

| slice | commit | content |
|---|---|---|
| P5 | `4a1d6e45` | `import` / `from … import` in `parser.bend` (3 new modes), 2 builders in `nodes.bend`, `import|from` dropped from `O.unsupported`; oracle tag set + fixtures + negatives + fuzz template + four-lane `stmt_imports.bend`; README subset. |
| docs | this commit | this report. |

## What landed

Grammar, exactly as far as `ast.parse` parity requires:

- `import a.b.c as d, e` → `Import(names=[alias(name, asname)])`. Dotted names are joined from
  tokens (`import a . b` → `"a.b"`).
- `from … import …` → `ImportFrom(module, names, level)` in CPython field order. Leading dots
  count the level; the lexer's single `...` token counts 3 (`from .... import a` → level 4,
  `from . . import a` → 2). A bare relative import has `module: null`; `from import a` is `Syntax`.
- `from m import *` (alias `"*"` with the star token's span), parenthesized lists with optional
  trailing comma. Without parentheses a trailing comma is `Syntax` (the next name is required);
  `()`, `(*)`, `*, b`, `b.c` as an imported name are `Syntax`.
- Locations: `alias` runs from the first name token to the end of the asname (or last name
  token); `Import`/`ImportFrom` end at the last consumed token, so the parenthesized form ends
  at `)` — all for free from the existing `P.end`.
- Keywords are lexed as `KW`, so `import if`, `import a as in` are `Syntax` through the existing
  `ident()`; non-ASCII names stay `Unsupported` ("Unicode identifier normalization").
- `x = import a` is now `Syntax` rather than `Unsupported` (correct: it is not a later-slice
  production any more).

Machinery: modes `From{start, level}`, `Dotted{dotted, text, start}`,
`Aliases{dotted, paren, names, separator}` (same shape as P4's `Items`); `N.dotted` carries a
name string with its real span through the `S.Expr`-typed result, `N.alias` builds the node.
`Mode` 32 → 35 cases; **no new backtracking**; `fuel_k` stays 32 (fuzz highwater unchanged at
3.25 dispatches/token). Hand lexer untouched and still the default.

## Evidence (tree `4a1d6e45`)

| check | result |
|---|---|
| `bash tests/parser/run.sh` | **Parser PASS: 72, FAIL: 0** (18 `.bend` × 4 lanes; was 68: +`stmt_imports`) |
| fixtures (`diff.py --fixtures all`) | 292 parsed / 292 exact (was 257); 0 structural, 0 location, 0 refusals |
| `fuzz.py` | 1,308 generated+directed, 1,306 oracle-accepted, **0 failures**, 0 `Limit`; 157 negative cases (314 runs, C+JS; was 125); 66 JS samples; highwater 3.25 / 32 |
| negatives vs oracle | all 121 `INVALID` rejected by the pinned `ast.parse`, all 36 `UNSUPPORTED` accepted by it (checked, not assumed) |
| `adversarial.py` | 28 / 28 runs, 0 fail-stops |
| `lexdiff.py --files 200` | 215 parsed; 0 kind/text diffs, 0 position diffs, 0 refusals; 25 JS samples, 0 diffs |
| `bash tests/run.sh` | PASS 16 / 16 |
| `bash tests/codex/run.sh` | 161 PASS, 0 FAIL |
| `tests/regex/oracle.py --pairs 500` | diffs c=0 js=0 interpret(500)=0 |
| `bash tests/run.sh --strings` | first run **83 / 85** (failing names not captured), **retry 85 / 85** — see Uncertainties |

The 2 fuzz inputs the oracle rejects are the pre-existing generator's `a < not (b)` shape, not
the P5 template.

### Corpus — whole files (the P5 success metric)

`supported` is decided independently from the oracle's AST tags (`Import ImportFrom alias`
added to the tag set); a supported file the parser refuses is a failure.

| tier | eligible | oracle-failure | **before (P4)** | **after (P5)** parsed = supported = exact | structural / location diffs | refusals | fail-stop | JS parity |
|---|---|---|---|---|---|---|---|---|
| 1 (llm-wiki tools) | 5 | 0 | 0 (0 %) | 0 (0 %) | 0 / 0 | 0 | 0 | 1 / 1 |
| 2 (Project tree) | 8,110 | 9 | 414 / 8,047 (**5.1 %**) | **1,215 (15.0 %)** | 0 / 0 | 0 | 0 | 418 / 418 |
| 3 (stdlib) | 731 | 0 | 27 (3.7 %) | **75 (10.3 %)** | 0 / 0 | 0 | 0 | 38 / 38 |

Project whole-file coverage **2.9×** (5.1 % → 15.0 %); stdlib 2.8×. Same-manifest control
(oracle tags only, live listing at 8,077 eligible): 416 supported without the P5 tags, 1,208
with them — so the jump is the imports, not manifest drift (1,208 forecast from tags alone;
1,215 measured on a listing 33 files larger).

**The jump is large but not the "most files" the 99.3 % first-refusal figure suggested**, and
it could not have been: imports were the *first* refusal, not the *only* one. First refusals
now (tier 2, 6,886 refused): `class` 3,047 (2,661 statement + 386 decorated), f-string 1,738,
slice 741, comprehension 530 + generator 245 + dict-comp 170, annotated assignment 253,
`yield` 71, `async` 39. Tier 3 (656 refused): `class` 485, slice 61, f-string 37,
comprehensions 45, `yield` 18. Tier 1's five files now fall to generator arguments (3),
f-string (1), slice (1).

### Corpus — per statement (`diff.py --corpus N --segments`)

| tier | files with ≥ 1 segment | statements | bytes | parsed = exact | structural / location diffs | refusals | JS parity |
|---|---|---|---|---|---|---|---|
| 1 | 5 | 74 (was 53) | 18,912 | 5 / 5 | 0 / 0 | 0 | 1 / 1 |
| 2 | 7,835 | 161,365 (was 107,210) | 43,724,935 | 7,835 / 7,835 | 0 / 0 | 0 | 405 / 405 |
| 3 | 723 | 25,321 (was 21,769) | 8,861,351 | 723 / 723 | 0 / 0 | 0 | 38 / 38 |

**Gate: 0 structural and 0 location diffs on everything supported — met**, on **186,760**
real statements (52.6 MB; was 129,032), of which 58,060 are `Import`/`ImportFrom` nodes
(top-level and nested), plus fixtures and fuzz.

### Token counts (`ttok`, measured; caps not edited)

parser 12,141 (was 10,936) · nodes 4,714 (was 4,586) · operators 1,155 (was 1,159) ·
README 1,168. All inside the `gates/repo.ts` caps quoted in the P3–P4 report (demos `.bend`
64k, README 4k). **`bend2/base.bend` 42,318 / 43,000 — unchanged, not touched.**

## Deviations

- Whole-file baseline (414 / 8,047) is the P3–P4 report's measurement, not re-run here; the
  same-manifest oracle-tag control above (416 → 1,208) stands in for it.
- The tier-2 manifest is a live listing (other lanes write into `~/Documents/Project`): 8,077
  eligible at the forecast, 8,110 summed over the whole-file chunks, which were run in three
  batches minutes apart; chunk boundaries can shift by a few files between batches. Every
  chunk exited 0 with 0 diffs / 0 refusals, so this affects the denominator by < 0.5 %, not
  the gate.
- Corpus tiers ran as 350-file (tier 2) / 250-file (tier 3) chunks, 8–12 in parallel. The
  first batch (chunks 0–2,450) exceeded the 10-minute tool cap and was moved to the background
  by the harness; I waited for its completion notice (all 8 chunks exit 0) before aggregating.
  Slowest chunks are dominated by the JS sample and oracle conversion on 100–500 KB generated
  files, not the C parser (max 3.1 s on a 498 KB file). Latencies under parallel load are not
  reported as timings.
- `stmt_errors.bend`: its `import x → Unsupported` assertion became `import x, → Syntax` plus
  `class A: pass → Unsupported`.
- `tests/caps.sh` stale-line flag from P3–P4 was fixed upstream (`77fa296b`); nothing to add.

## Uncertainties

- Strings battery 83 / 85 on first run, 85 / 85 on the single retry; the failing names were not
  captured on the first run (only the tail was read). This lane touches nothing under
  `tests/strings` or `bend2`; P3–P4 saw the same flake. Worth an owner look if it recurs idle.
- `--segments` still harvests top-level and class-body statements only; imports nested solely
  inside unsupported constructs are covered by fixtures/fuzz, not corpus.
- `from __future__ import braces` etc. parse (as in `ast.parse`; the rejection is the compiler's).

## Remainder (precise, in measured order of first refusals)

1. `class` (bases, keywords, decorators) — first refusal in 3,047 tier-2 and 485 tier-3 files.
2. f-strings (1,738), slices (741 + 61), comprehensions / generator arguments (945 + 45).
3. Annotated assignment (253), `yield` (71 + 18), `async`/`await`, walrus, `except*`,
   non-ASCII identifier normalization.
4. Upstream (unchanged): early exit in `Regex.exec.run`; then re-measure the P3 candidate.
