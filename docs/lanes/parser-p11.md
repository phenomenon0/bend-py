# Parser lane — P11 report: `yield` / `yield from` (fable, 2026-09-19)

Branch `lane-parser-p11`, worktree `bend-work-parser-p11`, off `lane-parser-p10` at `85c21433`.
Continues `parser-p10.md`. Oracle pin unchanged: CPython **3.11.15**
(`/home/omen/.hermes/hermes-agent/venv/bin/python3`). Nothing pushed. `bend2/**`, `gates/**`,
`tests/caps.sh`, and other namespaces' tests untouched. The hand lexer is untouched and still
the default; its superlinear cost was not chased.

## Slices

| slice | commit | content |
|---|---|---|
| P11 | `51b9962f` | `yield` / `yield from`: one new mode `Star` in `parser.bend` (`yield_expr \| star_expressions`), `yield` out of `O.unsupported`; no `nodes.bend` change (`Yield` / `YieldFrom` are `N.statement`'s one-`value` node); oracle tags `Yield YieldFrom` in `normalize.py`; fixtures + negatives + a third fuzz stream; four-lane `stmt_yield.bend`; stale expectations (`x: int = yield` was the `Unsupported` example in `stmt_errors` / `stmt_annassign`, now `x: int = await y`; the yield sources moved from `UNSUPPORTED` to `STATEMENTS`); README subset. |
| P11 docs | this commit | this report. |

Every number below is a fresh run on the `51b9962f` tree (the docs commit changes no parser or
harness source; `51b9962f` is `b7933e5d` with its message's counts corrected, same tree).

## What landed

`Yield{value}` (value optional) and `YieldFrom{value}` in CPython 3.11 field order with exact
spans: from the `yield` token to the end of the value (its closing `)` or trailing `,`
included); a bare `yield` is the token. Parentheses around a yield belong to the parent, as for
every other expression.

- **One mode, no backtracking.** CPython has `yield_expr` at exactly five places, always as
  `yield_expr | star_expressions`: a statement's head (`Expr(Yield)`), an assignment's value
  (each `=` of a chain: `x = y = yield`), an augmented value, an annotated value, and a group
  `'(' (yield_expr | named_expression) ')'`. `Star{}` peeks `yield`, else is `TestList{0}`; those
  five call sites switched from `TestList{0}` to `Star{}`. Mode count 43 → 44.
- **f-string fields come free**: a field is lexed as `( … )` and parsed as a group (P8), so
  `f'{yield}'`, `f'{yield x:>{(yield)}}'`, `f'{yield=}'` parse as the oracle does.
- **`yield` takes star-expressions** (`yield a, b`, `yield *a, b`, `yield a,`, even `yield *a` —
  the oracle accepts it), **`yield from` one `expression`** (ternary / lambda allowed; `yield
  from a, b` and `yield from *a` are `Syntax`). Bare `yield` is decided by the existing
  `O.is_end` token set; `yield()`, `yield[0]`, `yield -x`, `yield not x` are values, not
  calls / subscripts / operators on a yield.
- **Everywhere else yield is not an `expression`** → `Syntax`, by removing it from the
  unsupported set and letting `Prefix` fail: `foo(yield)`, `f(x=yield)`, `[yield]`, `{1: yield}`,
  `a[yield]`, `lambda: yield`, `return yield`, `raise yield`, `if yield:`, `for x in yield:`,
  `with yield:`, `def f(x=yield)`, `x = a, yield`, `(yield, 1)`, `yield yield`, `not yield`,
  `a + yield`. **The brief's `foo(yield)` is a `SyntaxError` in 3.11** — `foo((yield))` is the
  valid form; both are fixtures.
- **Targets**: `yield = 1`, `x = yield = 1`, `(yield) = 1`, `(yield) += 1`, `(yield): int`,
  `del (yield)`, `for (yield) in x`, `with a as (yield)` fall to the existing `N.target` /
  `ann_target` / `del_targets` checks (unknown tag → `Syntax`) with no new code, while
  `(yield).x = 1`, `(yield)[0] += 1`, `(yield).x: int`, `del (yield).x` parse (the yield is the
  base, in `Load`).
- **Generator elements**: `((yield) for x in y)` parses; `(yield x for x in y)` must not (the
  element is `assignment_expression | expression`). The group's `for` check takes an element
  that is a yield only if it is itself grouped. **Found by the first fixtures run** (my first
  guard refused the grouped form too; fixed before the commit).

### The refusal set, as the oracle has it

**`ast.parse` has no scope pass.** "`'yield' outside function`", "`'yield' inside list
comprehension`" and yield in a class body or lambda are errors of the *compiler's* symtable, not
the parser's: the pinned `ast.parse` **accepts** `yield` at module level, `[(yield) for x in y]`,
`[x for x in (yield)]`, `lambda: (yield)`, `class A:\n    yield`. This parser follows
`ast.parse` (the standing README policy, as with `*a = 1`), so all of these **parse, exact** —
none is refused and none stays `Unsupported`. What the parser distinguishes is exactly what the
grammar does: grouped yield anywhere = fine, bare yield outside the five slots = `Syntax`.
A compile-level scope check would be a separate pass over the finished AST, not a parser slice.

Still `Unsupported` (oracle-accepted, a later slice inside the yield): `yield (x := 1)`,
`yield await x`, `yield from await x`, `yield é`, `async def f(): yield`, yield under `match`,
`[(yield) async for x in y]` — all in `UNSUPPORTED`.

## Evidence (final tree)

| check | result |
|---|---|
| `bash tests/parser/run.sh` | **Parser PASS: 96, FAIL: 0** (24 `.bend` × 4 lanes; was 92: +`stmt_yield`), two full runs, no flake this session |
| fixtures (`diff.py --fixtures all`) | **965 parsed / 965 exact** (P10: 771); 0 structural, 0 location, 0 refusals, 0 `Limit` |
| `fuzz.py` | 2,481 generated+directed (**250 yield sources** on a third seeded stream `0xA57A2011`; the first two streams' sources are untouched), 2,210 oracle-accepted, 271 oracle-rejected generated negatives (33 / 119 / **119** per stream — the yield 119 equalling P10's annotated 119 is a coincidence, counted per stream by script), **0 failures**, 0 `Limit`; **615 negative cases** (1,230 runs, C+JS; was 491); 112 JS samples; fuel high-water unchanged (79.25, P8's f-string; yield max 4.5 dispatches / token) |
| negatives vs oracle | every `STATEMENTS` source accepted, every `INVALID` rejected, every `UNSUPPORTED` accepted by the pinned `ast.parse` (script, 0 bad of 792 / 523 / 92) |
| oracle probe | 110 hand-written yield forms, run before any fixture was written: accept/reject and AST equal on all but the one policy case below |
| `adversarial.py` | 28 / 28 runs, 0 fail-stops |
| `lexdiff.py --files 200` | 215 parsed; 0 kind/text diffs, 0 position diffs, 0 refusals; 25 JS samples, 0 diffs |
| `diff.py --self-test` | 20 / 20 round trips; ctx / constant / end-span corruption detected |
| final battery | see the last section |

### Corpus — whole files (the P11 success metric)

`supported` is decided independently from the oracle's AST tags (`Yield`, `YieldFrom` added); a
supported file the parser refuses is a failure.

| tier | eligible | oracle-failure | **before (P10)** | **after (P11)** parsed = supported = exact | structural / location diffs | refusals | `Limit` | fail-stop | JS parity |
|---|---|---|---|---|---|---|---|---|---|
| 1 (llm-wiki tools) | 5 | 0 | 5 (100 %) | **5 (100 %)** | 0 / 0 | 0 | 0 | 0 | 1 / 1 |
| 2 (Project tree) | 8,372 | 9 | 7,573 / 8,357 (**90.6 %**) | **7,906 (94.4 %)** | 0 / 0 | 0 | 0 | 0 | 396 parsed of 419 samples, 0 mismatches |
| 3 (stdlib) | 731 | 0 | 610 (**83.4 %**) | **684 (93.6 %)** | 0 / 0 | 0 | 0 | 0 | 33 parsed of 37 samples, 0 mismatches |

Same-manifest control (oracle tags only, over the very manifest of the run): tier 2 **7,588**
supported without the `Yield`/`YieldFrom` tags, **7,906** with (**+318**); stdlib **610 → 684
(+74)**. **The P10 sole-blocker forecast was +318 / +74 → ≈ 94.4 % / 93.6 %: both are exact.**
The raw tier-2 delta is +333; the other +15 is the live listing's growth (8,357 → 8,372
eligible). The jump is yield, not manifest drift.

`yield` no longer appears as a refusal anywhere. This session's runner takes **one manifest per
tier** and fans 100-file chunks out 14-way through `diff.evaluate` (P10 re-listed the tree per
chunk; one listing cannot drift between chunks). All 84 + 8 + 1 whole-file chunks returned ok;
slowest file 21.9 s (tier 2) / 15.4 s (tier 3) under 14-way load, cap 30 s, no timeouts. JS
samples are every 20th file of a chunk, so their count follows the chunking (37 vs P10's 41).

Parser refusals now (first refusal per file):

| tier 2 (457 refused) | | tier 3 (47 refused) | |
|---|---|---|---|
| `async` (production 192 + statement 185) | 377 | walrus | 23 |
| walrus | 52 | `async` (statement 20 + production 1) | 21 |
| `match` | 25 | `match` | 2 |
| argument (a walrus / await in a call) | 3 | argument | 1 |

Oracle-tag view of what is left (tier 2 / tier 3 files). **Blocks** (any position): async 379 /
21 · walrus 56 / 25 · `match` 26 / 2. **Sole** blocker: **async 376 / 21 · walrus 52 / 24** ·
`match` 25 / 1. Pairs: async+walrus 3 / 0, `match`+walrus 1 / 1. No other unsupported tag occurs.

### Corpus — per statement (segments)

| tier | files | segments | bytes | parsed = exact | structural / location | statement nodes | JS |
|---|---|---|---|---|---|---|---|
| 1 | 5 | 105 | 76,289 | all | 0 / 0 | 1,242 | 1 / 1 |
| 2 | 8,067 | 154,079 | 103,696,286 | all | 0 / 0 | 1,273,557 | 416 / 416 |
| 3 | 724 | 14,584 | 11,666,795 | all | 0 / 0 | 147,515 | 37 / 37 |

**168,768 segments, 1,422,314 statement nodes, ~115.4 MB, 0 structural + 0 location diffs.**
(P10: 170,636 segments / 1,410,808 nodes. Segments fall again because classes with generator
methods are now supported whole and count once; the node count is the honest size: +11,506.)

Yield shape coverage in the segment corpus (tier 2 / tier 3, counted with the pinned `ast`;
tier 1 has none): **808 / 489** nodes · `Yield` 745 / 411, `YieldFrom` 63 / 78 · bare 127 / 11 ·
tuple value 137 / 105 · spanning lines 41 / 44 · parent `Expr` 801 / 487, **`Assign` 7 / 0,
`Lambda` 0 / 1, `Return` 0 / 1**. **Yield as a subexpression is 9 of 1,297 corpus nodes** (and
0 of the 1,152 in the supported *whole* files — the `x = yield` files are all `async`-blocked):
receiving generators are rare in this corpus; `x = y = yield`, `x += yield`, grouped yields in
calls / displays / conditions / f-strings and the whole negative set are covered by fixtures
and fuzz only.

### Token counts (`ttok`, measured; caps not edited)

parser 16,230 (was 15,929) · operators 1,149 · nodes 6,243 (unchanged) · README 1,654 (was
1,573) · parse_state, fstring, lexer, syntax unchanged · `stmt_yield.bend` 1,494 (new) ·
`stmt_annassign.bend` 1,605 · `stmt_errors.bend` 257 · `fixtures.py` 15,801 (was 12,979) ·
`fuzz.py` 3,549 (was 2,900) · `normalize.py` 1,982. `bun gates/repo.ts` PASS 44 / 44 with these.

## Deviations

- **`yield x := 1` is `Unsupported`, the oracle says `SyntaxError`** — the one mismatch of the
  110-form probe. Same standing conservative-refusal policy as P9 / P10 (`production :=` is
  refused before the grammar around it is judged); it is in neither `INVALID` nor
  `UNSUPPORTED`. It resolves with the walrus slice.
- **Error messages**: `yield = 1` answers `Syntax` "invalid assignment target" (CPython:
  "assignment to yield expression not possible"), `del (yield)` likewise. Kinds and positions
  are what the harness compares.
- **The fuzz got a third RNG stream** rather than new choices in the first two (P10's
  precedent): their sources stay what they were.
- **The corpus runner** (one manifest, 14-way `Pool` over `diff.evaluate` / `diff.segments`)
  and the control / census scripts lived in `/tmp` this session and are not committed; they
  call the committed harness functions unchanged. P10's were not committed either.
- Trusted expected output in `stmt_yield.bend`: as in P5–P10, the wire text is the C lane's
  output for a source that is also in `fixtures.py`, where `diff.py` proves it equal to the
  oracle (and the generator asserted that equality before writing the file).

## Uncertainties

- **Strings suite: 84 / 1 on the first battery run, 85 / 0 on the one retry.** The brief names
  the `deep` flake as base-staleness; I tailed the first run's output and **did not capture
  which test failed**, so "it was `deep`" is likely, not verified.
- The checker's JS stack flake (`stmt_functions [check]`) did not occur in 2 full `run.sh`
  runs; the parser is 301 tokens larger than P10's.
- **Lexer cost on very large files** (unchanged, not chased): slowest whole-file parse 21.9 s
  under 14-way load against the 30 s cap — 3.3 s closer than P10's 18.6 s; load-dependent, but
  the margin is thinning as more big files become parseable.
- `--segments` still does not descend into `def` bodies.

## Remainder (precise, in measured order)

1. **`async` / `await`** — the Project jump: sole **376 + 21** → Project 94.4 % → **~98.9 %**,
   stdlib 93.6 % → ~96.4 %; blocks 379 / 21. Includes `async for` in comprehensions (one peek
   in `Comp`, P9); `await` is a unary-level prefix, `async def/for/with` reuse `Def` / `For` /
   `With` with a tag.
2. **Walrus** — now the stdlib jump: sole **52 + 24** (stdlib +3.3 pts → ~96.9 % alone; with
   async ~99.7 %); resolves the `yield x := 1` / unparenthesised-walrus policy deviations.
3. `match` (sole 25 + 1), then `except*`, non-ASCII identifiers. All four together: Project
   8,363 / 8,372 (the 9 oracle failures remain), stdlib 731 / 731.
4. Upstream (unchanged): early exit in `Regex.exec.run`, then re-measure the P3 candidate; the
   hand lexer's superlinear cost on ~1 MB files; the checker's stack depth.

## Final battery (serial, final tree)

| check | measured |
|---|---|
| `bun gates/repo.ts` | **PASS 44 / 44** |
| `bash tests/run.sh --strings` | 84 / 1, then **85 / 0** on the one retry (see Uncertainties) |
| `bash tests/run.sh` (f64) | **16 / 0** |
| `bash tests/codex/run.sh` | **161 PASS, 0 FAIL**, 0 suite errors |
| `bash tests/regex/run.sh` | **49 / 0** |
| `bash tests/parser/run.sh` | **96 / 0** |

Nothing was skipped. As in P8–P10, the gate / strings / f64 totals (44 / 85 / 16) are this
base's full suites; the base predates the reduce / strfix / tour merges, and the counts after a
rebase were not verified here.
