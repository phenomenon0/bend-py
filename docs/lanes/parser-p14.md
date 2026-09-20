# Parser lane — P14 report: `match` (PEP 634), the end of refuse-first, `except*` (fable, 2026-09-19)

Branch `lane-parser-p14` off `lane-parser-p13` (`4e097d28`). Oracle: pinned CPython 3.11.15
`ast.parse`. **The corpus is at its ceiling: every file the oracle parses, this parser parses
exactly — Project 8,466 / 8,466, stdlib 731 / 731, tier 1 5 / 5; 0 structural + 0 location
diffs.** What is left outside is not grammar: 9 files the oracle itself rejects (all answered
`Syntax` here too) and 2 files excluded for their encoding. `Unsupported` now has exactly one
producer: a non-ASCII identifier.

## Slices

| commit | slice |
|---|---|
| `a73177db` | `match` statements: `Match` / `match_case` and the eight patterns, soft keywords by header-only backtracking (`P.attempt`), and the last refuse-first policy deleted (`O.unsupported`, `expected()`); `fixtures_match.py`, sixth fuzz stream, `stmt_match` lane file; two lane literals split for the checker's JS stack |
| `23c15a27` | `except*` → `TryStar`; 35 fixtures, +4 lane checks; `except*` out of `UNSUPPORTED` |
| `3d67f304` | `stmt_walrus` expected literal split with `++` (the battery's only parser-lane failure) |
| (this) | report |

Task 3's other half, **non-ASCII identifiers, is deferred** — see Remainder.

## What landed

**Match.** `Match{subject, cases}`, `match_case{pattern, guard, body}`, `MatchValue`,
`MatchSingleton`, `MatchSequence`, `MatchMapping{keys, patterns, rest}`, `MatchClass{cls,
patterns, kwd_attrs, kwd_patterns}`, `MatchStar`, `MatchAs`, `MatchOr` — CPython 3.11 field
order and spans. Eleven new modes in the one `go` (`Subject`, `Cases`, `Patterns`, `Pattern`,
`Alternatives`, `Closed`, `PatName`, `Literal`, `PatSeq`, `PatMap`, `PatArgs`; 55 modes in all).

**Soft keywords.** A line whose first token is the NAME `match` first tries
`match subject_expr ':' NEWLINE` under `P.attempt`; on `Syntax` — and only `Syntax`; `Unsupported`
and `Limit` stand — the saved state (fuel included) is restored and the line is the simple
statement it always was. The subject is `TestList{0}` (a named expression or a star tuple; a
bare starred subject is `Syntax`). This is the second backtracking point in the parser (after
`with (`), header-only as there: the subject expression is parsed at most twice, the block
never. `case` is a keyword only as the first token of a line inside a match block; the block is
`case` clauses only. `AfterSmall` lost its `soft` field and both `match statement` refusals.
No backtracking inside patterns.

**Patterns.** Open sequences (`case a, b:`), `|`, `as` (target not `_`, not dotted), `_` the
wildcard decided before any trailer, captures, dotted values, literals (strings incl. f-strings
and implicit concatenation through `Prefix{14}`, signed numbers, `real ± imaginary` only),
`None` / `True` / `False`, groups, `[]` / `()` sequences with `*name` / `*_`, mappings (literal
or dotted keys, `**rest` last, no `**_`), class patterns (no positional after keyword). A
`MatchAs` span starts at its pattern's cover, so `(a) as b` starts at the parenthesis.

**The end of refuse-first.** `O.unsupported` (`def|try|with|@`) and its four pre-checks
(Sequence, Dictionary, Arguments, Small) and `expected()` (five call sites) are deleted: a
compound statement in simple position (`if a: with b: pass`, `x = 1; def f(): pass`) and a stray
`@` / keyword in an expression (`f(@)`, `{with: 1}`) are `Syntax`, as in the oracle. The sweep
for siblings found no other refuse-first site: after `23c15a27`, `P.unsupported` is reached only
from the non-ASCII identifier check.

**`except*`.** `TryStar{body, handlers, orelse, finalbody}` — `Try`'s fields under another tag
(`N.attempt` takes the star). `Handlers` carries the star of the first handler.

### What the oracle accepts (recorded, 3.11.15)

Headers — a `Match`: `match x:` · `match(x):` · `match[x]:` · `match{x}:` · `match -x:` ·
`match ...:` · `match x,:` · `match *a, b:` · `match (x := 1):` · `match x := 1:` · `match await x:` ·
`match \⏎ x:` · a multi-line parenthesised subject · tabs · a missing final newline · comments
after the header, between and after cases · nested `match` inside a case · `case(y):` /
`case [y]:` / `case {}:` · `case 1: a; b` · `case 1: pass;`.
Not a `Match`, but the simple statement: `match = 1` · `match(x)` · `match.x` · `match[x]` ·
`match, x = 1, 2` · `match: int = 1` · `match += 1` · `match [x]: int = 1` (an `AnnAssign`) ·
`match -x` · `match *x` · `match in x` · `match not in x` · `match is x` · `match if x else y` ·
`match or x` · `match == x` · `match @ x` · `match; x` · `match = lambda: 1` · `print(match)` ·
`case = 2`, `case(x)`, `case.x` outside a block.
`SyntaxError`: `match x` / `match 1` / `match 'a'` / `match lambda: 1` (expected `:`) ·
`match.x:` + block · `match (x): int` (illegal annotation target) · `match (x) = 1` ·
`match x, y = 1` · `match *x:` · `match s: case x: pass` (one line) · a block that is `pass`,
holds a statement before / after the cases, or an `else:` at either indent · `case = 1` inside
the block · `case:` · `case x` without `:` · an unindented `case` · `case x: pass` at top level ·
`if a: match x:` + block.

Guards — `named_expression`: `if y := 1`, `if (yield)`, `if lambda: 1`, `if b if c else d`
accepted; `if y, z`, `if *y`, `if` alone rejected. `case 1, if a:` is accepted (open sequence,
then the guard).

Patterns accepted: `-1`, `- 1`, `-0`, `1j`, `-1j`, `1+2j`, `1-2j`, `-1+2j`, `1.5+2j`,
`0x1+2j`, `1e3+2j`, `1 + 2J`, `1_0`, `"a" "b"`, `b"a"`, `f"{x}"`, `"a" f"{x}"`, `x._`, `__`,
`_x`, `x.y()`, `x(a,)`, `x(a=1,)`, `x(a=1, a=2)` (no duplicate check in `ast.parse`),
`{"a": 1, "a": 2}` (likewise), `{a.b: 1}`, `{1: x, -2: y, 1+2j: z, None: w, True: v}`,
`{f"a": 1}`, `{1: x as y}`, `{**x,}`, `()`, `(x,)`, `(*x,)`, `[*x, *y]` (no multiple-star check),
`[* x]`, `*x,`, `x, *_`, `(x)` and `((x))` (a `MatchAs`, the group leaves no node),
`(x as y) as z`, `_ as y`, `x | y as z` (`as` binds the whole `|`), `x | (y as z)`, the soft
keywords as captures (`case`, `match`, `case(match)`), and every name position with a non-ASCII
identifier (this parser: `Unsupported`).
Patterns rejected: `+1`, `--1`, `1j+2j` ("real number required"), `1+2` ("imaginary number
required"), `1 + -2j`, `1 - - 2j`, `"a" b"b"`, `...`, `_.y`, `_()`, `_._`, `C(_.a)`, `{_: 1}`,
`x(a=1, 2)`, `x(*a)`, `x(**a)`, `x(a)(b)`, `x()()`, `x[0]`, `(*x)`, `*x` alone, `[*x.y]`,
`[*(x)]`, `{**_}`, `{**r, "a": 1}`, `{**a, **b}`, `{**a.b}`, `{a: 1}`, `{(1): x}`,
`{x.y(): 1}`, `{"a": *x}`, `x as _`, `x as y.z`, `x as y as z`, `x as y | z`, `*x as y`,
`x |`, `| x`, `x | | y`, `x | *y`, and every expression that is not a pattern (`-x`, `not x`,
`x + 1`, `x := 1`, `x: int`, `1 if x else 2`, `lambda: 1`, `[x for x in y]`, `x[1:2]`, `1 < 2`,
`"a" + "b"`).

Two PEG quirks, reproduced and pinned by fixtures:

- `{_.a: 1}` **is accepted** (a mapping key is `name_or_attr`, no wildcard rule) although `_.a`
  as a pattern is not.
- `C(a, _=1)` **is `Syntax`** while `C(_=1)`, `C(_=1, _=2)` and `C(a, b=1, _=2)` parse: after a
  positional, the positional gather consumes `_` as a wildcard pattern and the PEG does not
  backtrack over it. One guarded branch in `PatArgs` (`_` with no keyword yet and a positional
  already taken). Found by the fuzz negatives, not by reading the grammar.

`except*`: `except` and `except*` never mix on one `try`; `except*:` with no type is `Syntax`;
`except * E`, `except*E`, a parenthesised walrus / yield type and `as _` parse; `except* E, F`,
`except* *E`, `except** E` are `Syntax`.

## Deviations resolved

- **Compound statement in simple position** (P13's last standing policy): `Unsupported
  statement with|try|def|@` → `Syntax`. 68 retired-policy negatives in `MATCH_INVALID`; the
  walrus fuzz stream's workaround (compound lines left unwrapped) is removed.
- **`match`**: 11 forms moved from `UNSUPPORTED` (`fixtures.py`) and 2 from `WALRUS_UNSUPPORTED`
  to parsed; 3 stale `Unsupported` lane expectations flipped to `Done` (`stmt_annassign` 2,
  `stmt_errors` 1).
- **`except*`**: out of `UNSUPPORTED`; 17 accepted + 16 negatives + 2 non-ASCII fixtures.

## Evidence (parser tree `23c15a27`; `3d67f304` changes one lane test only)

| check | result |
|---|---|
| `bash tests/parser/run.sh` | **Parser PASS: 108, FAIL: 0** on `3d67f304` (27 `.bend` × 4 lanes; was 104: +`stmt_match`). The battery run on `23c15a27` was 106 / 2, both `stmt_walrus` builds, the checker-stack literal — fixed in `3d67f304`, see Uncertainties |
| fixtures (`diff.py --fixtures all`) | **1,773 parsed / 1,773 exact** (P13: 1,434); 0 structural, 0 location, 0 refusals, 0 `Limit` |
| `fuzz.py` | 4,539 generated+directed (**500 match sources** on a sixth seeded stream `0xA57A2014`: 244 oracle-accepted, 256 oracle-rejected negatives; the first five streams' sources are untouched but for the removed walrus workaround), 3,590 oracle-accepted, 949 oracle-rejected (each must answer `Syntax`), **0 failures**, 0 normalization failures, no `Limit`; + **1,276 negatives** (1,208 `INVALID` + 68 `UNSUPPORTED`) × 2 lanes = 2,552 runs; 179 JS samples |
| negatives vs oracle | every `MATCH_STATEMENTS` source accepted, every `MATCH_INVALID` rejected, every `MATCH_UNSUPPORTED` accepted by the pinned `ast.parse` (the generator classifies by the oracle; 339 / 406 / 24) |
| `probe.py` | 14 / 14 |
| `adversarial.py` | 28 / 28 runs, 0 fail-stops |
| `lexdiff.py --files 200` | 215 parsed; 0 kind/text diffs, 0 position diffs, 0 refusals; 25 JS samples, 0 diffs (lexer untouched) |
| `diff.py --self-test` | 20 / 20 round trips; ctx / constant / end-span corruption detected |
| final battery | see the last section |

Failures on the way, none left:

- The first full lane run of the match slice was 97 / 7: six stale `Unsupported` expectations
  (flipped) and one `stmt_functions [interpret]` stack overflow — see Uncertainties.
- The first fuzz run of the match stream had 1 negative failure: a fixture with `C(_, _=_)`,
  which the oracle rejects (the quirk above). The parser was changed, not the expectation.
- `match @ x` answered `Unsupported` until the refuse-first policy went (it propagated through
  `P.attempt` by design); that ordered task 2 into the first slice.

### Corpus — whole files (the P14 success metric)

| tier | eligible | oracle-failure | **before (P13)** | **after (P14)** parsed = supported = exact | structural / location diffs | refusals | `Limit` | fail-stop | JS parity |
|---|---|---|---|---|---|---|---|---|---|
| 1 (llm-wiki tools) | 5 | 0 | 5 (100 %) | **5 (100 %)** | 0 / 0 | 0 | 0 | 0 | 1 / 1 |
| 2 (Project tree) | 8,475 | 9 | 8,396 / 8,422 (**99.69 %**) | **8,466 / 8,466 (100 %)**; 99.89 % of eligible | 0 / 0 | **0** | 0 | 0 | 423 / 423 samples parsed, 0 mismatches |
| 3 (stdlib) | 731 | 0 | 729 (**99.73 %**) | **731 (100 %)** | 0 / 0 | **0** | 0 | 0 | 37 / 37, 0 mismatches |

Same-manifest control (oracle tags, over the manifest of this run): tier 2 has **26** files
with a `Match`, stdlib **2** — supported 8,440 → 8,466 and 729 → 731. **The P13 sole-blocker
forecast was +26 / +2: both exact.** The raw tier-2 figure moved by +70 because the Project
tree grew between runs (8,422 → 8,466 oracle-parsed files). For the first time the JS samples
all parse (P13: 418 of 422; the four were `match` files).

Runner as P13 but **8-way** (P13's advice; 14-way hit the cap once): one manifest per tier,
100-file chunks through `diff.evaluate`; all chunks ok; slowest whole file **20.4 s** (tier 2) /
16.3 s (tier 3), cap 30 s, **no timeouts**, nothing re-run. Box load average was 14–20 from the
parallel lanes. Wall: tier 2 1 min 49 s, tier 3 26 s.

Match shape census, whole files, pinned `ast` (tier 2 / tier 3): files 26 / 2; `Match` 81 / 3;
`match_case` 303 / 7; `MatchValue` 202 / 0; `MatchAs` 182 / 4; `MatchClass` 50 / 4;
`MatchSequence` 40 / 0; `MatchOr` 4 / 0; `MatchSingleton` 0 / 1; `MatchMapping` 0 / 0;
`MatchStar` 0 / 0; guards 2 / 1; subjects `Attribute` 45, `Name` 30 / 2, `Call` 4 / 1,
`Subscript` 2. `TryStar` 0 / 0 and non-ASCII names 0 / 0. **Mappings, stars and every
soft-keyword corner are exercised by the fixtures and the fuzz stream only — the corpus holds
none.**

### The residual tail, by category (all of it)

| category | tier 2 | tier 3 | what |
|---|---|---|---|
| grammar not covered | **0** | **0** | — |
| non-ASCII identifier (`Unsupported`) | 0 | 0 | no corpus file holds one |
| `Limit` / timeout / fail-stop | 0 | 0 | slowest 20.4 s of 30 s |
| oracle failure (not Python 3.11) | 9 | 0 | below |
| excluded before parsing (encoding) | 1 | 1 | below |

The 9 oracle failures — the parser was run on each; **all 9 answer `Syntax`**, 8 on the oracle's
line:

| file | oracle | this parser |
|---|---|---|
| `Agent-GO/mathshard-ai/fbref_enhanced_scraper.py` | unterminated string literal, line 415 | `Syntax 415 19` invalid character in string |
| `Agent-GO/mathshard-ai/test_first_10_games.py` | unterminated string literal, line 54 | `Syntax 54 15` |
| `…/terminalbench_2/terminalbench2_env.py` | unterminated string literal, line 248 | `Syntax 248 42` |
| `Agent-GO/quantum_puf_experiment.py` | expected an indented block after `try`, line 27 | `Syntax 28 0` expected INDENT (the oracle names the `try` line) |
| `…/block_sparse_attention/flash_attn_bsa_varlen_mask.py` | unexpected indent, line 111 | `Syntax 111 0` |
| `…/faiss-src/demos/index_pq_flat_separate_codes_from_codebook.py` | invalid syntax, line 102 | `Syntax 102 0` invalid character |
| `…/notebooks/notebook_fireworks.py` | f-string expression part cannot include a backslash, line 167 | `Syntax 167 35`, same message |
| `kami-remix/works/tsc-archive/fill_portfolio.py` | same, line 77 | `Syntax 77 70` |
| `smaug/smaug/app_ui.py` | same, line 389 | `Syntax 388 97` (the f-string opens on 388; the oracle reports the expression's line) |

The three f-string files are valid Python 3.12 (PEP 701), not 3.11. Exclusions: tier 2
`…/llvm/utils/lit/tests/shtest-encoding.py` (72 bytes, deliberately invalid UTF-8), tier 3
`turtledemo/clock.py` (`coding: cp1252` cookie; the harness takes UTF-8 only).

### Corpus — per statement (`--segments`)

| tier | files | segments | bytes | parsed = exact | structural / location | statement nodes | JS |
|---|---|---|---|---|---|---|---|
| 1 | 5 | 105 | 76,289 | 5 / 5 | 0 / 0 | 1,242 | 1 / 1 |
| 2 | 8,170 | 155,560 | 107,919,253 | 8,170 / 8,170 | **0 / 0** | 1,319,924 | 422 / 422, 0 mismatches |
| 3 | 724 | 14,009 | 11,853,389 | 724 / 724 | **0 / 0** | 149,474 | 37 / 37, 0 mismatches |

**169,674 segments, 1,470,640 statement nodes, 0 structural + 0 location diffs**, incl. 84
`Match` / 310 `match_case` / 487 pattern nodes (the whole census above: every corpus match
statement is a segment) and 148 `NamedExpr`. Slowest segment file 20.1 s; **no timeouts** (P13
had one at 14-way).

### Token counts (`ttok`)

`parser.bend` 21,173 (P13 16,885; cap 64k) · `nodes.bend` 6,777 · `operators.bend` 1,095 ·
`parse_state.bend` 1,925 · `fixtures.py` 15,399 (cap 16k; 12 entries moved out) ·
`fixtures_match.py` 11,226 · `fixtures_walrus.py` 4,744 · `fuzz.py` 7,033 · `normalize.py`
1,996 · `stmt_match.bend` 2,586 · `stmt_functions.bend` 1,736 · `stmt_errors.bend` 372 ·
`README.md` 2,038. `bun gates/repo.ts`: PASS 44 / 44. Readings only; no cap edits.

## Deviations standing

- **Non-ASCII identifiers answer `Unsupported`** (the oracle accepts them everywhere, patterns
  included). The only `Unsupported` left; the 68 `UNSUPPORTED` fixtures (24 of them match forms, all non-ASCII) hold the line.
- Error **kind** only: CPython's messages and offsets are not reproduced. Where the oracle has a
  dedicated message for a match form ("positional patterns follow keyword patterns", "cannot use
  '_' as a target", "real / imaginary number required in complex literal") this parser says
  `Syntax` with its own text.
- `ast.parse` runs no compile-time pattern checks (duplicate keys / attributes, multiple stars,
  irrefutable case not last, name bound twice); neither does this parser — parity, not a gap.

## Uncertainties

- **The checker's JS stack vs long literals.** `term_check` recurses once per character of a
  string literal, so a lane file whose `main` holds a ≳4k-character expected string overflows
  the JS stack *nondeterministically*. Growing the book pushed `stmt_functions` from 8 / 8 to
  ~3 / 6 and the new `stmt_match` to 5 / 6; an instrumented scratch copy of the checker showed
  the depth in the test's `main` (3,475 frames), not in the parser's `go`. Both literals are now
  `++`-joined 1.5k chunks (6 / 6 each). `bend2/bend.ts` is off-limits and was not touched.
  `stmt_walrus.bend` held a 4,072-character literal, ran 6 / 6 during the slice and was left
  alone — **then failed in the battery** (`[js build]` + `[c build]`, Parser 106 / 2). Split the
  same way in `3d67f304` (24 / 24 over six runs). No lane literal is now over 3.1k
  (`stmt_comprehensions` 3,077, `stmt_slices` 3,014, `stmt_annassign` 2,974): **keep lane
  literals under ~3k or chunk them.** The strings suite's `deep [js build]` flake reports the
  same error and is presumably the same mechanism (not investigated; not my namespace).
- Strings suite: **84 / 1 (`deep [js build]`) on the battery run and again on the one retry**;
  the build alone then passed 5 of 6. Files untouched by this lane; the known flake, worse than
  in P13 (one retry sufficed there).
- `demos/python/README.md` line 83 still says "43 grammar modes" (55 now; stale since P11). Left
  alone again; a one-word fix for whoever owns the README's numbers.
- The match fuzz stream is 51 % negatives after reweighting (the first cut was 91 %).
- A full `tests/parser/run.sh` is ~15–17 min under load, past a 10-minute foreground limit; it
  was run detached and awaited.
- `--segments` still does not descend into `def` bodies. The corpus runner, census, generator
  (`gen.py`, which wrote `fixtures_match.py` from oracle-classified candidates) and probe
  scripts lived in `/tmp/p14` and are not committed, as before.

## Remainder — the state of the queue

The grammar queue is **empty for the corpus**: 0 files in any tier are blocked by this parser.

1. **Non-ASCII identifiers** — deferred, recorded: 0 corpus files; needs the XID_Start /
   XID_Continue tables and NFKC normalisation of the name (`ast` reports the normalised id), and
   the identifier scan lives in the lexer, which the parallel lexer-quadratic lane owns. Not
   cheap, not mine to touch this round. It is the last `Unsupported`.
2. **Lexer cost** (the parallel lane): the slowest whole file is 20.4 s of the 30 s cap at 8-way
   on a loaded box. Coverage cannot go up; only this number can go down.
3. Harness, not parser: non-UTF-8 source encodings (2 exclusions); `--segments` inside `def`.
4. Out of scope by construction: the 9 oracle failures (3 are 3.12 f-strings — a 3.12 oracle
   would be a new program, not a residual).

## Final battery (serial, `23c15a27` tree; the parser lanes re-run on `3d67f304`)

| command | result |
|---|---|
| `bun gates/repo.ts` | PASS: 44 / 44 |
| `bash tests/run.sh --strings` | Strings PASS: 84, FAIL: 1 (`deep [js build]`, known flake) → retry 84 / 1, the same test; alone 5 / 6 |
| `bash tests/run.sh` | PASS: 16, FAIL: 0 |
| `bash tests/codex/run.sh` | 161 PASS, 0 FAIL; 0 suite errors |
| `bash tests/regex/run.sh` | Regex PASS: 49, FAIL: 0 |
| `bash tests/parser/run.sh` | **Parser PASS: 108, FAIL: 0** on `3d67f304` (27 `.bend` × 4 lanes; was 104: +`stmt_match`). The battery run on `23c15a27` was 106 / 2, both `stmt_walrus` builds, the checker-stack literal — fixed in `3d67f304`, see Uncertainties |
