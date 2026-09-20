# Parser lane — P12 report: `async` / `await` (fable, 2026-09-19)

Branch `lane-parser-p12`, worktree `bend-work-parser-p12`, off `lane-parser-p11` at `53418fd1`.
Continues `parser-p11.md`. Oracle pin unchanged: CPython **3.11.15**
(`/home/omen/.hermes/hermes-agent/venv/bin/python3`). Nothing pushed. `bend2/**`, `gates/**`,
`tests/caps.sh`, and other namespaces' tests untouched. The hand lexer is untouched and still
the default; its superlinear cost was not chased.

## Slices

| slice | commit | content |
|---|---|---|
| P12 | `29e54d7a` | `async def` / `async for` / `async with`, `await`, async comprehensions: `parser.bend` (two helpers `comp_start` / `async_word`, an `await` branch in `Prefix`, `async` in `Line` / `Decorators` / `Comp`; **no new mode**), `nodes.bend` (`N.async` retag, `N.clause` takes `is_async`), `async` / `await` out of `O.unsupported` and `P.expect_token`; oracle tags `AsyncFunctionDef AsyncFor AsyncWith Await` in `normalize.py` and the `comprehension.is_async` exclusion removed; fixtures (new `fixtures_async.py`) + negatives + a fourth fuzz stream; four-lane `stmt_async.bend`; stale expectations (the `Unsupported` examples that used `await` / `async for` now use a walrus; `yield await x` is `Done`); README subset. |
| P12 docs | this commit | this report. |

Every number below is a fresh run on the `29e54d7a` tree (the docs commit changes no parser or
harness source).

## What landed

`AsyncFunctionDef`, `AsyncFor`, `AsyncWith` in CPython 3.11 field order with exact spans, and
`Await{value}`; `comprehension.is_async = 1` for `async for` clauses.

- **Async statements are the plain statement, retagged.** `Line` peeks `async`, `async_word`
  takes it and requires `def` / `for` / `with` next (else `Syntax`), the existing `Def` / `For` /
  `With` modes run unchanged, and `N.async` prefixes the tag with `Async`. The span starts at the
  `async` token, also under decorators (the oracle's `lineno` for a decorated def is the
  `async` line, not the decorator's). After decorators only
  `async def` is legal (`@d\nasync for …` is `Syntax`), as in the oracle.
- **`await` takes a primary.** `await_primary: AWAIT primary` sits between `power` and `primary`:
  the operand is `Expression{14}` (atom + trailers only), so `await x ** 2` is `(await x) ** 2`,
  `await f(x).y[0]` is one await, `-await x` and `not await x` parse; `await -x`, `await not x`,
  `await lambda: 1`, `await await x`, `await *x` and bare `await` are `Syntax`. The unary
  operators got the matching gate (minimum ≤ 13), which is what makes `await -x` a `Syntax`
  rather than a parse.
- **Async comprehensions** at all four comprehension entries (group / generator, list, set and
  dict displays, the sole-generator call argument): `comp_start` replaces the `for` peek, `Comp`
  takes an optional `async` before each `for`, mixed clauses (`for … async for … if …`) included.
- **No new mode, no backtracking.** Mode count stays 44. parser.bend +449 tokens.

### The refusal set, as the oracle has it

**`async` and `await` are hard keywords in 3.11 — the brief's "legal as identifiers" is 3.6
behaviour.** Probed before any code was written: `async = 1`, `await = 1`, `async()`, `x.async`,
`x.await`, `def async()`, `def await()`, `f(await=1)`, `import async`, `class await: pass`,
`lambda async: 1` are all `SyntaxError` in the pinned oracle (they became reserved in 3.7). The
hand lexer already tags both `KW`, so they fail as any keyword in a name slot does → `Syntax`.
There are no soft-keyword corners to handle; the fixtures hold these as negatives.

**`ast.parse` has no scope pass** (as for yield in P11): `await x` at module level, in a plain
`def`, in a lambda, in a class body; `async for` / `async with` outside an async function;
`[x async for x in y]` in a sync function — all **parse, exact**, as the oracle does. "`'await'
outside function`" is the compiler's symtable, not the parser.

Still `Unsupported` (oracle-accepted, a later slice inside the async form): `await (x := 1)`,
`[x async for x in (y := z)]`, `async with (x := 1): pass`, `async def f(): await é`,
`async def é(): pass`, `async for é in y: pass`, async under `match` — all in `UNSUPPORTED`.

## Evidence (final tree)

| check | result |
|---|---|
| `bash tests/parser/run.sh` | **Parser PASS: 100, FAIL: 0** (25 `.bend` × 4 lanes; was 96: +`stmt_async`). Three full runs: **98 / 2, then 100 / 0, then 100 / 0** (battery, logged) — see Uncertainties |
| fixtures (`diff.py --fixtures all`) | **1,196 parsed / 1,196 exact** (P11: 965); 0 structural, 0 location, 0 refusals, 0 `Limit` |
| `fuzz.py` | 2,962 generated+directed (**250 async sources** on a fourth seeded stream `0xA57A2012`; the first three streams' sources are untouched), 2,574 oracle-accepted, 388 oracle-rejected generated negatives (33 / 119 / 119 / **117** per stream), **0 failures**, 0 `Limit`; **704 negative cases** (1,408 runs, C+JS; was 615); 125 JS samples; fuel high-water unchanged (79.25, P8's f-string; async max 4.5 dispatches / token) |
| negatives vs oracle | every `STATEMENTS` source accepted, every `INVALID` rejected, every `UNSUPPORTED` accepted by the pinned `ast.parse` (script, 0 bad of 1,023 / 634 / 70) |
| oracle probe | 357 hand-written async / await forms, run before the fixtures were written: accept/reject and AST equal on all but the one policy case below |
| `adversarial.py` | 28 / 28 runs, 0 fail-stops |
| `lexdiff.py --files 200` | 215 parsed; 0 kind/text diffs, 0 position diffs, 0 refusals; 25 JS samples, 0 diffs |
| `diff.py --self-test` | 20 / 20 round trips; ctx / constant / end-span corruption detected |
| final battery | see the last section |

### Corpus — whole files (the P12 success metric)

`supported` is decided independently from the oracle's AST tags (the four async tags added, the
`is_async` exclusion dropped); a supported file the parser refuses is a failure.

| tier | eligible | oracle-failure | **before (P11)** | **after (P12)** parsed = supported = exact | structural / location diffs | refusals | `Limit` | fail-stop | JS parity |
|---|---|---|---|---|---|---|---|---|---|
| 1 (llm-wiki tools) | 5 | 0 | 5 (100 %) | **5 (100 %)** | 0 / 0 | 0 | 0 | 0 | 1 / 1 |
| 2 (Project tree) | 8,388 | 9 | 7,906 / 8,372 (**94.4 %**) | **8,298 (98.93 %)** | 0 / 0 | 0 | 0 | 0 | 415 parsed of 420 samples, 0 mismatches |
| 3 (stdlib) | 731 | 0 | 684 (**93.6 %**) | **705 (96.44 %)** | 0 / 0 | 0 | 0 | 0 | 34 parsed of 37 samples, 0 mismatches |

Same-manifest control (oracle tags only, over the very manifest of the run): tier 2 **7,922**
supported without the async tags, **8,298** with (**+376**); stdlib **684 → 705 (+21)**. **The
P11 sole-blocker forecast was +376 / +21 → ≈ 98.9 % / 96.4 %: both are exact.** The raw tier-2
delta is +392; the other +16 is the live listing's growth (8,372 → 8,388 eligible). Of the
8,379 files the oracle itself parses, 99.03 % now parse whole.

`async` / `await` no longer appear as a refusal anywhere. Same runner as P11 (one manifest per
tier, 100-file chunks 14-way through `diff.evaluate`); all chunks returned ok; slowest file
**25.09 s** (tier 2) / 15.8 s (tier 3) under 14-way load, cap 30 s, no timeouts.

Parser refusals now (first refusal per file):

| tier 2 (81 refused) | | tier 3 (26 refused) | |
|---|---|---|---|
| walrus | 52 | walrus | 23 |
| `match` | 25 | `match` | 2 |
| argument (a walrus in a call) | 4 | argument | 1 |

Oracle-tag view of what is left (tier 2 / tier 3 files). **Blocks** (any position): walrus 56 /
25 · `match` 26 / 2. **Sole** blocker: **walrus 55 / 24** · `match` 25 / 1. Pair `match`+walrus
1 / 1. No other unsupported tag occurs.

Async shape census, whole files, pinned `ast` (tier 2 / tier 3): files with async 379 / 21, of
which supported **376 / 21** · `AsyncFunctionDef` 2,585 / 172 (decorated 1,226 / 7) ·
`AsyncWith` 313 / 4 · `AsyncFor` 38 / 0 · `Await` 3,290 / 151 (spanning lines 788 in tier 2;
parents in tier 2: `Assign` 1,632, `Expr` 1,187, `Return` 195, `Call` 152, `Subscript` 33,
`keyword` 21, `If` 12, rest scattered) · async comprehension clauses **3 / 0**.

### Corpus — per statement (segments)

| tier | files | segments | bytes | parsed = exact | structural / location | statement nodes | JS |
|---|---|---|---|---|---|---|---|
| 1 | 5 | 105 | 76,289 | all | 0 / 0 | 1,242 | 1 / 1 |
| 2 | 8,083 | 154,481 | 106,922,198 | all | 0 / 0 | 1,310,454 | 418 / 418 |
| 3 | 724 | 14,250 | 11,803,271 | all | 0 / 0 | 148,960 | 37 / 37 |

**168,836 segments, 1,460,656 statement nodes, ~118.8 MB, 0 structural + 0 location diffs.**
(P11: 168,768 segments / 1,422,314 nodes; +38,342 nodes.) Slowest segment file 24.3 s.

Async nodes inside the segment corpus (tier 2 / tier 3): `AsyncFunctionDef` 2,582 / 172 ·
`AsyncWith` 313 / 4 · `AsyncFor` 38 / 0 · `Await` 3,273 / 151 · async comprehension clauses 3 /
0 — **6,536 async nodes, all exact**. Async comprehensions are 3 corpus nodes; `await` with a
`**` right of it, the unary/await negatives, mixed sync/async clauses, async dict / set / call
generators and decorated `async def` corner spans are covered by fixtures and fuzz only.

### Token counts (`ttok`, measured; caps not edited)

parser 16,679 (was 16,230) · nodes 6,354 (was 6,243) · operators 1,145 (was 1,149) ·
parse_state 1,728 · README 1,771 (was 1,654) · fstring, lexer, syntax unchanged ·
`stmt_async.bend` 1,695 (new) · `stmt_annassign.bend` 1,609 · `stmt_errors.bend` 261 ·
`stmt_comprehensions.bend` 1,592 · `stmt_yield.bend` 1,494 · `fixtures.py` 15,689 (was 15,801) ·
`fixtures_async.py` 3,149 (new) · `fuzz.py` 4,543 (was 3,549) · `normalize.py` 1,972 (was
1,982). `bun gates/repo.ts` PASS 44 / 44 with these.

## Deviations

- **The brief's soft-keyword premise is wrong for the pinned oracle** (above): `async` / `await`
  as identifiers are `Syntax`, following 3.11, not parsed as names.
- **`await := 1` is `Unsupported`, the oracle says `SyntaxError`** — the one mismatch of the
  357-form probe. Same standing conservative-refusal policy as P9–P11 (`production :=` is
  refused before the grammar around it is judged); it is in neither `INVALID` nor
  `UNSUPPORTED`. It resolves with the walrus slice.
- **P12 fixtures live in a new file `tests/parser/fixtures_async.py`** (231 statements, 111
  invalid), appended to `STATEMENTS` / `INVALID` at the end of `fixtures.py`: with them inline
  `fixtures.py` read 18,767 ttok against the 16,000 cap, and `bun gates/repo.ts` failed. Caps
  were not edited; the split is the fix. `fixtures.py` is at 15,689 — **the next slice's
  fixtures need their own file too.**
- **The fuzz got a fourth RNG stream** rather than new choices in the first three (P10 / P11
  precedent): their sources stay what they were.
- **Error messages**: `async x` answers "expected def, for or with after async"; kinds and
  positions are what the harness compares.
- **The corpus runner** and the control / census scripts lived in `/tmp` again and are not
  committed; they call the committed harness functions unchanged.
- Trusted expected output in `stmt_async.bend`: as in P5–P11, the wire text is the C lane's
  output for a source that is also in the fixtures, where `diff.py` proves it equal to the oracle.

## Uncertainties

- **`tests/parser/run.sh`: 98 / 2 on the first full run of the final tree, 100 / 0 on the next
  two.** I had filtered that first run's output and **did not capture which two tests failed**;
  the brief's named `stmt_functions [check]` stack flake is the likely one, not verified. The
  battery run is logged in full and has no FAIL line.
- Strings suite 85 / 0 on the first try this session (no `deep` flake).
- **Lexer cost on very large files** (unchanged, not chased): slowest whole-file parse **25.1 s**
  under 14-way load against the 30 s cap — P10 18.6 s, P11 21.9 s. Load-dependent, but the
  margin is now under 5 s; the next slice that makes more big files parseable may need the
  runner at lower parallelism (a measurement setting, not a parser change) or the lexer work.
- `--segments` still does not descend into `def` bodies.

## Remainder (precise, in measured order)

1. **Walrus** — the jump on both tiers now: sole **55 + 24** → Project 98.93 % → ~99.6 %,
   stdlib 96.44 % → ~99.7 %; resolves the `await := 1` / `yield x := 1` / unparenthesised-walrus
   policy deviations and the 3 async `UNSUPPORTED` entries that are a walrus inside.
2. `match` (sole 25 + 1, pair with walrus 1 + 1), then `except*`, non-ASCII identifiers. All
   together: Project 8,379 / 8,388 (the 9 oracle failures remain), stdlib 731 / 731.
3. Upstream (unchanged): early exit in `Regex.exec.run`, then re-measure the P3 candidate; the
   hand lexer's superlinear cost on ~1 MB files; the checker's stack depth.

## Final battery (serial, final tree)

| check | measured |
|---|---|
| `bun gates/repo.ts` | **PASS 44 / 44** |
| `bash tests/run.sh --strings` | **85 / 0** |
| `bash tests/run.sh` (f64) | **16 / 0** |
| `bash tests/codex/run.sh` | **161 PASS, 0 FAIL**, 0 suite errors |
| `bash tests/regex/run.sh` | **49 / 0** |
| `bash tests/parser/run.sh` | **100 / 0** (no retry needed in the battery) |

Nothing was skipped. As in P8–P11, the gate / strings / f64 totals (44 / 85 / 16) are this
base's full suites; the counts after a rebase were not verified here.
