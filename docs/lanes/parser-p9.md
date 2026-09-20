# Parser lane — P9 report: comprehensions (fable, 2026-09-19)

Branch `lane-parser-p9`, worktree `bend-work-parser-p9`, off `lane-parser-p8` at `f7b42f5a`.
Continues `parser-p8.md`. Oracle pin unchanged: CPython **3.11.15**
(`/home/omen/.hermes/hermes-agent/venv/bin/python3`). Nothing pushed. `bend2/**`, `gates/**`,
`tests/caps.sh`, and other namespaces' tests untouched. The hand lexer is untouched and still
the default; its superlinear cost was not chased.

## Slices

| slice | commit | content |
|---|---|---|
| P9 | `f7d277ff` | comprehensions: 2 modes in `parser.bend` (`Comp`, `Ifs`), the `open` position on `Arguments`, 4 builders in `nodes.bend`, `for` out of the unsupported lists (`operators.bend`, `parse_state.bend`); oracle tags `ListComp` `SetComp` `DictComp` `GeneratorExp` `comprehension` (async ones excluded) in `normalize.py`, fixtures + negatives + fuzz generator, four-lane `stmt_comprehensions.bend`; README subset. |
| P9 docs | this commit | this report; one stale P8 expectation in `stmt_fstrings.bend` (a comprehension in an f-string field was the example of an `Unsupported` field — it parses now; the example is `f"{(x := 1)}"`). |

Every corpus number below is a fresh run on the `f7d277ff` tree (the docs commit changes no
parser or harness source).

## What landed

All four forms, in CPython 3.11 field order with exact spans:
`ListComp` / `SetComp` / `GeneratorExp` `{elt, generators}`, `DictComp` `{key, value,
generators}`, each generator a `comprehension{target, iter, ifs, is_async}` (`is_async` always
`0`; no `lineno` fields, as in the oracle).

- **No backtracking, no new entry point.** The bracket modes already parse their first element;
  at the separator they now peek `for`. Exactly one plain (non-starred) element and no
  separator yet → `Comp{kind, head, start, close, gens}`; anything else before a `for`
  (`[a, b for ..]`, `[*a for ..]`, `{**a for ..}`, `{a: b, c: d for ..}`) is `Syntax`, as in
  CPython. Mode count 41 → 43.
- **Clauses** loop in `Comp`: `for` → target through the existing star-targets path
  (`TestList` + `N.target`, so tuple / starred / attribute / subscript / list / parenthesised
  targets and the trailing-comma `for *v, in k` come for free, with the same Store ctx and the
  same rejections as assignment) → `in` → iter as a *disjunction* (`Expression{2n}`: a bare
  ternary or lambda is `Syntax`, parenthesised is fine) → `Ifs`, which collects `if
  <disjunction>` filters until the next token is not `if`. Nested `for` clauses are the same
  loop; the closing bracket ends it and gives the span.
- **The bare generator argument**: `f(x for x in y)` — `Arguments` sees `for` after a sole
  positional, no keywords, no separator, and builds the `GeneratorExp` spanning the *call's
  parentheses* (the new `open` position carried on `Arguments`), CPython's span.
  `f(x for x in y, 1)`, `f(1, x for x in y)`, `f(x for x in y,)`, `class A(x for x in y)` and
  `a[x for x in y]` are `Syntax`, as in CPython.
- **Everywhere an expression goes**: nested comprehensions in elt / iter / filter, multi-line,
  inside slices, call arguments, `def` defaults, and f-string fields
  (`f"{x for x in y}"` is a `GeneratorExp` spanning the field's virtual parens — it fell out of
  P8's `(expr)` relex with no code).
- `for` outside a comprehension position is now `Syntax` (was `Unsupported`): there is no
  expression `for` left to be unsupported.

## Evidence (final tree)

| check | result |
|---|---|
| `bash tests/parser/run.sh` | **Parser PASS: 88, FAIL: 0** (22 `.bend` × 4 lanes; was 84: +`stmt_comprehensions`) |
| fixtures (`diff.py --fixtures all`) | **596 parsed / 596 exact** (P8: 471); 0 structural, 0 location, 0 refusals, 0 `Limit` |
| `fuzz.py` | 1,612 generated+directed (**544 comprehension sources**, 457 f-string sources), 1,579 oracle-accepted, 33 oracle-rejected generated negatives, **0 failures**, 0 `Limit`; **362 negative cases** (724 runs, C+JS; was 266); 78 JS samples |
| negatives vs oracle | every `STATEMENTS` source accepted, every `INVALID` rejected, every `UNSUPPORTED` accepted by the pinned `ast.parse` (checked by script this session, 0 bad) |
| `adversarial.py` | 28 / 28 runs, 0 fail-stops |
| `lexdiff.py --files 200` | 215 parsed; 0 kind/text diffs, 0 position diffs, 0 refusals; 25 JS samples, 0 diffs |
| `diff.py --self-test` | 20 / 20 round trips; ctx / constant / end-span corruption detected |
| final battery | see the last section |

### Corpus — whole files (the P9 success metric)

`supported` is decided independently from the oracle's AST tags (the four comprehension tags
and `comprehension` added, a `comprehension` with `is_async` excluded); a supported file the
parser refuses is a failure.

| tier | eligible | oracle-failure | **before (P8)** | **after (P9)** parsed = supported = exact | structural / location diffs | refusals | `Limit` | fail-stop | JS parity |
|---|---|---|---|---|---|---|---|---|---|
| 1 (llm-wiki tools) | 5 | 0 | 0 (0 %) | **5 (100 %)** | 0 / 0 | 0 | 0 | 0 | — |
| 2 (Project tree) | 8,342 | 9 | 3,258 / 8,327 (**39.1 %**) | **6,226 (74.6 %)** | 0 / 0 | 0 | 0 | 0 | 317 parsed of 416 samples, 0 mismatches |
| 3 (stdlib) | 731 | 0 | 443 (**60.6 %**) | **606 (82.9 %)** | 0 / 0 | 0 | 0 | 0 | 36 parsed of 41 samples, 0 mismatches |

Same-manifest control (oracle tags only, over the very records of the run): tier 2 **3,260**
supported without the comprehension tags, **6,226** with (**+2,966**); stdlib **443 → 606
(+163)**. The P8 forecast was +2,953 / +163 → ≈74.6 % / 82.9 %: stdlib is exact; tier 2 is the
forecast plus the live listing's growth (8,327 → 8,342 eligible, +13 newly completed files).
The jump is the comprehensions, not manifest drift.

Project **1.91×**, stdlib **1.37×**, tier 1 from none to all. `comprehension`, `generator
argument`, `dict comprehension` and `for in expression` no longer appear as refusals anywhere.
All 84 + 6 chunks exited 0; slowest file 24.1 s (tier 2) / 15.7 s (tier 3) under 14-way load,
cap 30 s, no timeouts.

Parser refusals now (first refusal per file):

| tier 2 (2,107 refused) | | tier 3 (125 refused) | |
|---|---|---|---|
| annotation (annotated assignment) | 1,556 | `yield` (statement 79 + production 1) | 80 |
| `async` (production 156 + statement 113) | 269 | walrus | 20 |
| `yield` (statement 236 + production 1) | 237 | `async` statement | 17 |
| walrus | 28 | annotation | 6 |
| `match` | 17 | `match` | 1 |
| | | argument | 1 |

Oracle-tag view of what is left (tier 2 / tier 3 files). **Blocks** (any position):
`AnnAssign` 1,619 / 8 · async 379 / 21 · yield 374 / 89 · walrus 56 / 25 · `match` 26 / 2.
**Sole** blocker: **`AnnAssign` 1,332 / 4** · async 225 / 16 · yield 205 / 72 · walrus 23 / 15
· `match` 15 / 0. Top pairs (tier 2): `AnnAssign`+async 114, `AnnAssign`+yield 113. No other
unsupported tag occurs.

### Corpus — per statement (`diff.py --corpus N --segments`)

| tier | files | segments | bytes | parsed = exact | structural / location | statement nodes | JS |
|---|---|---|---|---|---|---|---|
| 1 | 5 | 105 | 76,289 | all | 0 / 0 | 1,242 | — |
| 2 | 8,037 | 159,251 | 94,639,459 | all | 0 / 0 | 1,173,211 | 415 / 415 |
| 3 | 723 | 15,523 | 11,443,016 | all | 0 / 0 | 145,026 | 41 / 41 |

**174,879 segments, 1,319,479 statement nodes, ~106.2 MB, 0 structural + 0 location diffs.**
(P8: 174,090 segments / 1,026,908 nodes. The segment count barely moves because members
harvested one by one are now supported whole and count once; the node count is the honest size.)

Comprehension shape coverage in the supported segment corpus (tier 1 / 2 / 3, counted with the
pinned `ast`): `ListComp` 11 / 13,036 / 457 · `SetComp` 6 / 895 / 21 · `DictComp` 4 / 4,179 /
56 · `GeneratorExp` 14 / 8,217 / 316 (**27,212** in all) · `comprehension` clauses 36 / 26,955
/ 881 · more than one `for` 1 / 598 / 31 · at least one `if` 8 / 5,354 / 203 · more than one
`if` 0 / 4 / 0 · spanning lines 1 / 5,507 / 235 · bare generator as a call's sole argument 12
/ 7,786 / 261 · a comprehension nested in a comprehension 0 / 656 / 4 · inside an f-string
field 0 / 60 / 0. Targets in the corpus are only `Name` (22,366 / 741) and `Tuple` (4,589 /
140): **attribute, subscript, starred and list targets are covered by fixtures and fuzz only.**

### Token counts (`ttok`, measured; caps not edited)

parser 15,663 (was 14,758) · nodes 5,647 (was 5,369) · operators 1,151 · parse_state 1,736 (was
1,744) · README 1,493 (was 1,436) · fstring 2,982, lexer 3,509, syntax 1,704 (all unchanged) ·
`stmt_comprehensions.bend` 1,590 (new) · `fixtures.py` 9,852 · `fuzz.py` 2,534 ·
`normalize.py` 1,977.

## Deviations

- **Async comprehensions stay `Unsupported`** (`[x async for x in y]`, and `await` in any
  clause). The brief: support the field if the corpus needs it. Measured: a `comprehension`
  with `is_async` occurs in **2** tier-2 files and **0** stdlib files, and is the sole blocker
  of **0** — both files also need `async def`. So `is_async` is emitted as the constant `0`,
  `async` in a clause refuses with `production async`, and the oracle side excludes those
  comprehensions from `supported`. It belongs to the `async` slice, where `async for` costs
  one peek in `Comp`.
- **Walrus inside comprehensions, as the oracle records it** (walrus itself is a later slice):
  `ast.parse` accepts `[y := f(x) for x in z]`, `[x for x in y if (z := x)]`, `[(a := x) for x
  in y]`, and even `[x := 1 for x in y]` and `[x for x in (y := z)]`; the "cannot rebind the iteration variable" / "in iterable expression" rules are
  compiler (symtable) errors, *not* `ast.parse` errors, so a syntax-level parser must accept
  them when walrus lands. The unparenthesised `[x for x in y if z := x]` and `[x for x in y :=
  z]` are oracle `SyntaxError`s; this parser answers `Unsupported` (`production :=`) for them —
  the standing conservative-refusal policy, a token it does not support is refused before the
  grammar around it is judged. They are therefore in neither `INVALID` nor `UNSUPPORTED`.
- **`for` outside a comprehension is now `Syntax`**, not `Unsupported` (`x = for`, `a + for`).
  Statement-level `for` loops are untouched.
- **`Arguments` carries the `(` position** (`open`), used only for the bare generator's span.
  The alternative — re-deriving it from the callee's end — is wrong under `f (x for x in y)`
  and line continuations.
- **Settled from P8's list**: `class A(x for x in y)` and `a[x for x in y]` are `Syntax` like
  CPython (were `Unsupported`); a comprehension in an f-string field parses.
- Trusted expected output in `stmt_comprehensions.bend`: as in P5–P8, the wire text is the C
  lane's output for a source that is also in `fixtures.py`, where `diff.py` proves it equal to
  the oracle; the four lanes then agree on it.

## Uncertainties

- **One stale expectation slipped past the slice commit**: `f7d277ff` was committed with the
  new fixture green but before a full `run.sh`; the full run was 84 / 4 (`stmt_fstrings` × 4
  lanes, its "unsupported field" example being a comprehension). Fixed in this commit; 88 / 0.
  The tree at `f7d277ff` alone is red on that one fixture.
- **Lexer cost on very large files** (unchanged, not chased): slowest whole-file parse 24.1 s
  under 14-way load, against the 30 s cap. No timeouts, but the margin is P8's.
- `--segments` still does not descend into `def` bodies; comprehensions inside unsupported
  functions are covered by fixtures/fuzz and the 6,837 whole files, not by segments.
- The checker's JS stack depth (P8's flaky `[check]`) did not recur in three full suite runs
  this session, with the parser 900 tokens larger. Not evidence it is gone.

## Remainder (precise, in measured order)

1. **Annotated assignment** — no longer the sleeper: first refusal in 1,556 + 6 files, blocks
   1,619 / 8, **sole blocker of 1,332 + 4**. Project 74.6 % → ~90.6 %; stdlib barely moves
   (82.9 % → ~83.4 %). Still the cheapest slice left (`target: annotation [= value]`, the
   `simple` flag).
2. **`yield` / `yield from`** — the stdlib jump: sole 205 + 72 (stdlib → ~92.7 %), blocks 374 /
   89.
3. **`async` / `await`** (sole 225 + 16; includes `async for` in comprehensions, above), then
   walrus (23 + 15), `match` (15 + 0), `except*`, non-ASCII identifiers.
4. Upstream (unchanged): early exit in `Regex.exec.run`, then re-measure the P3 candidate; the
   hand lexer's superlinear cost on ~1 MB files; the checker's stack depth.

## Final battery (serial, final tree)

| check | measured |
|---|---|
| `bun gates/repo.ts` | **PASS 44 / 44** |
| `bash tests/run.sh --strings` | 84 / 1 first run — `deep [interpret]`, "the machine stack overflowed", the base-staleness flake the brief names; **85 / 0** on the one retry |
| `bash tests/run.sh` (f64) | **16 / 0** |
| `bash tests/codex/run.sh` | **161 PASS, 0 FAIL**, 0 suite errors |
| `bash tests/regex/run.sh` | **49 / 0** |
| `bash tests/parser/run.sh` | **88 / 0** |

Nothing was skipped. As in P8, the gate / strings / f64 totals (44 / 85 / 16) are this base's
full suites; the base predates the reduce / strfix / tour merges, and the counts after a rebase
were not verified here.
