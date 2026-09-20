# Parser lane — P13 report: walrus (`:=`, `NamedExpr`) (fable, 2026-09-19)

Branch `lane-parser-p13`, worktree `bend-work-parser-p13`, off `lane-parser-p12` at `e5cd75ad`.
Continues `parser-p12.md`. Oracle pin unchanged: CPython **3.11.15**
(`/home/omen/.hermes/hermes-agent/venv/bin/python3`). Nothing pushed. `bend2/**`, `gates/**`,
`tests/caps.sh`, and other namespaces' tests untouched. The hand lexer is untouched and still
the default; its superlinear cost was not chased (a parallel lane owns it).

## Slices

| slice | commit | content |
|---|---|---|
| P13 | `942c6ba5` | named expressions: `parser.bend` (`Expression{0}` = `named_expression`, `Expression{1}` = `expression`; every `Expression` / `TestList` / `Item` site audited against the 3.11 grammar; two `Syntax` checks for a bare walrus as dict key / slice lower bound; **no new mode**), `nodes.bend` (`N.named`, `N.bare`), `:=` out of `O.unsupported` and `P.expect_token` (the refuse-walrus-first policy, deleted); oracle tag `NamedExpr` in `normalize.py`; fixtures (new `fixtures_walrus.py`) + negatives + a fifth fuzz stream; four-lane `stmt_walrus.bend`; 10 stale `Unsupported` lane expectations flipped to `Done`; 19 entries moved out of `UNSUPPORTED`; README subset. |
| P13 docs | this commit | this report. |

Every number below is a fresh run on the `942c6ba5` tree (the docs commit changes no parser or
harness source).

## What landed

`NamedExpr{target, value}` in CPython 3.11 field order with exact spans (from the NAME token to
the value's end; the parentheses are not part of the node, as in the oracle). The target is a
`Name` in `Store`.

- **One number carries the whole rule.** `Expression{minimum}` already existed with 0 and 1
  equivalent. Now **0 is `named_expression`, 1 is `expression`**: at minimum 0, a `NAME` token
  followed by `:=` takes both, parses `Expression{1}` as the value and builds the node; anything
  else falls to the old path. Two tokens of lookahead, no backtracking, no new mode (still 44).
  parser.bend 16,679 → 16,885 tokens (+206).
- **Where the grammar names `named_expression`, the site stays 0**: what a group holds, `if` /
  `elif` / `while` heads, positional call arguments (and class bases), list / set / tuple display
  elements, subscript elements, comprehension elements and `if` filters, f-string fields (they
  parse as a group), decorators, and the value of another walrus only when parenthesised.
- **Everywhere else the site was bumped to 1**, so a bare `:=` there meets no production and is
  `Syntax`, as in the oracle: dict keys and values (display and comprehension), slice bounds,
  keyword / `*` / `**` argument values, `return`, `del`, `assert` (both), `raise` (both),
  annotations and annotated / plain / augmented assignment values, `yield` / `yield from`
  values, lambda bodies and defaults, parameter defaults / annotations / return annotation,
  `for` targets and iterables (statement and comprehension), `except` kinds, `with` items, the
  ternary's three operands, every operator operand.
- Two sites share an `Item{0}` parse with a legal site and get a check instead: a bare walrus
  as a **dict key** (`{x := 1: 2}`; the first element of a brace display is parsed before `:`
  tells set from dict) and as a **slice lower bound** (`a[x := 1:2]`; parsed before `:` tells
  index from slice) are `Syntax` via `N.bare(e, "NamedExpr")` (tag and not grouped).
  `{(k := a): b}` and `a[(x := 1):2]` parse.
- **The refusal policy is deleted, not adjusted.** `:=` is out of `O.unsupported` and
  `P.expect_token` lost its `:=` special case, so a stray `:=` anywhere is a plain unexpected
  token → `Syntax`.

### The oracle's non-Name target errors (recorded)

The target is one `NAME` token; everything else is a `SyntaxError` in the pinned oracle, and
`Syntax` here (kind only — this parser does not reproduce CPython's messages):

| form | oracle message |
|---|---|
| `(a.b := 1)`, `(x.y.z := 1)` | cannot use assignment expressions with attribute |
| `(a[0] := 1)` | cannot use assignment expressions with subscript |
| `((x) := 1)` | cannot use assignment expressions with name |
| `((x, y) := 1)` / `([x] := 1)` | … with tuple / … with list |
| `(1 := 2)`, `('s' := 1)` / `(None := 1)`, `(True := 1)` | … with literal / … with None, True |
| `(f() := 1)` | … with function call |
| `(-x := 1)`, `not x := 1` | … with expression |
| `lambda: x := 1` | … with lambda |
| `await x := 1` | … with await expression |
| `(*x := 1)`, `(await := 1)`, `(lambda := 1)`, `(yield := 1)` | invalid syntax |
| `(x := 1) = 2` | cannot assign to named expression here. Maybe you meant '==' instead of '='? |
| `(x := 1): int` | illegal target for annotation |
| `del (x := 1)` | cannot delete named expression |
| `for (x := 1) in y: pass` | cannot assign to named expression |

`(x, y := 1)` is **accepted** by the oracle — `Tuple[x, NamedExpr(y, 1)]`, not a tuple target —
and parses exact here. A `NamedExpr` is no assignment / `del` / `for` / `with … as` / annotation
target: `N.target_ok` whitelists tags, so those were `Syntax` with no change.

**`ast.parse` has no scope pass** (as for yield and await): `[x := 1 for x in y]` (rebinding the
iteration variable), `[x for x in (y := z)]` (walrus in a comprehension iterable), a walrus in a
class-body comprehension — all **parse, exact**, as the oracle does. Those are symtable errors.

`f"{x:=1}"` is not a walrus: `x` with format spec `=1`, as in the oracle. `f"{(x := 1)}"` is.

Still `Unsupported` (oracle-accepted, a later slice inside the walrus): `(é := 1)`, `(x := é)`,
`if é := 1: pass`, `f(é := 1)`, `[é := 1]` (non-ASCII identifiers), and a walrus beside `match`
— the 7 entries of `WALRUS_UNSUPPORTED`.

## Deviations resolved (each one)

The standing policy since P7: *a `:=` anywhere answers `Unsupported` first*, including where the
oracle answers `SyntaxError`. All of it is gone; **0 policy mismatches remain on the probe**.

**A. The named policy mismatches of earlier reports — now `Syntax`, as the oracle** (all seven are
the head of `WALRUS_INVALID`, and lane checks in `stmt_walrus.bend`):

| # | form | recorded in | oracle | before | now |
|---|---|---|---|---|---|
| 1 | `a[::=1]` | P7 (slices) | invalid syntax | Unsupported | **Syntax** |
| 2 | `[x for x in y if z := x]` | P9 (comprehensions) | invalid syntax | Unsupported | **Syntax** |
| 3 | `[x for x in y := z]` | P9 | invalid syntax | Unsupported | **Syntax** |
| 4 | `x: y := 1` | P10 (annotated assignment) | invalid syntax | Unsupported | **Syntax** |
| 5 | `x: int = y := 1` | P10 | invalid syntax | Unsupported | **Syntax** |
| 6 | `yield x := 1` | P11 (yield) | invalid syntax | Unsupported | **Syntax** |
| 7 | `await := 1` | P12 (async; its one probe mismatch) | invalid syntax | Unsupported | **Syntax** |

**B. Oracle-accepted forms held in `UNSUPPORTED` as "a walrus inside" — now parsed, exact** (19,
moved from `fixtures.py` `UNSUPPORTED` to `WALRUS_STATEMENTS`):
`(x := 1)` · `with (x := 1): pass` · `a[x:=1]` · `a[1:(x:=2)]` · `f"{(x := 1)}"` ·
`[x := 1 for x in y]` · `[x for x in (y := z)]` · `[x for x in y if (z := x)]` ·
`f(x := 1 for x in y)` · `{(k := a): b for a in c}` · `x: (y := 1)` · `x: int = (y := 1)` ·
`yield (x := 1)` · `x = yield (y := 1)` · `(yield (x := 1))` · `await (x := 1)` ·
`[x async for x in (y := z)]` · `async with (x := 1): pass` · `f'{yield (x := 1)}'`.

**C. Lane expectations that asserted the refusal — flipped `Unsupported` → `Done`** (10 lines, 7
files): `stmt_annassign.bend` (`x: int = (y := 1)`, `x: (y := 1)`), `stmt_async.bend`
(`await (x := 1)`, `[x async for x in (y := z)]`), `stmt_comprehensions.bend`
(`[x for x in (y := z)]`, `[x := 1 for x in y]`), `stmt_errors.bend` (`x: int = (y := 1)`),
`stmt_fstrings.bend` (`f"{(x := 1)}"`), `stmt_slices.bend` (`a[1:(x:=2)]`), `stmt_yield.bend`
(`yield (x := 1)`). `stmt_annassign`, `stmt_async` and `stmt_errors` keep another `Unsupported` example (non-ASCII); `stmt_comprehensions`, `stmt_fstrings`, `stmt_slices` and `stmt_yield` now hold none — the refusal kind stays covered by `stmt_errors`, `stmt_walrus` and the 58 `UNSUPPORTED` fixtures on both lanes.

**D. The probe.** 330 hand-written walrus forms, run against the P12 parser before any code:
201 oracle-accepted (197 outside the subset, i.e. the walrus itself), 129 rejected, **124
mismatches — every one an oracle `SyntaxError` answered `Unsupported`**. After: 201 accepted (5
outside the subset: non-ASCII / `match`), 129 rejected, **0 mismatches**, accept/reject and the
full AST + spans. The 124, all now `Syntax`:

`(x := y := 1)` · `(x := *a)` · `(x := yield)` · `x := 1` · `x = y := 1` · `x = (y := 1) = 2` · `(x := 1) = 2` · `(x := 1) += 2` · `(x := 1): int` · `x, y := 1, 2` · `((x, y) := 1)` · `(a.b := 1)` · `(a[0] := 1)` · `((a) := 1)` · `([a] := 1)` · `(f() := 1)` · `(1 := 1)` · `(None := 1)` · `(True := 1)` · `("a" := 1)` · `(lambda := 1)` · `(x :=)` · `(:= 1)` · `(x := := 1)` · `(x for x in y := z)` · `(x for x in y if z := x)` · `(x for (x := 1) in y)` · `(x for x := 1 in y)` · `[x := *a]` · `[x for x in y if z := x]` · `[x for x in y := z]` · `[x := 1, for x in y]` · `{x := 1: 2}` · `{1: x := 2}` · `{**x := 1}` · `{k := a: b for a in c}` · `{a: v := b for a in c}` · `{*x := 1}` · `f(k=x := 1)` · `f(k := 1 = 2)` · `f(*x := 1)` · `f(**x := 1)` · `f(x := 1 for x in y, 2)` · `class A(k=x := 1): pass` · `a[x := 1:2]` · `a[1:x := 2]` · `if x := 1, 2: pass` · `if x := y := 1: pass` · `if not x := 1: pass` · `if a and x := 1: pass` · `if x := 1: y := 2` · `if a.b := 1: pass` · `if (x) := 1: pass` · `if x := yield: pass` · `if x := *a: pass` · `while x := 1, 2: pass` · `for x in y := z: pass` · `for x := 1 in y: pass` · `for (x := 1) in y: pass` · `with x := 1: pass` · `with a as (x := 1): pass` · `async with x := 1: pass` · `return x := 1` · `del x := 1` · `del (x := 1)` · `assert x := 1` · `assert a, x := 1` · `raise x := 1` · `raise E from x := 1` · `yield x := 1` · `(yield x := 1)` · `yield from x := 1` · `(yield := 1)` · `await := 1` · `await x := 1` · `(await x := 1)` · `(await := 1)` · `lambda: x := 1` · `(lambda: x := 1)` · `lambda x := 1: 2` · `lambda x=y := 1: x` · `def f(x=y := 1): pass` · `def f(x: y := 1): pass` · `def f() -> y := 1: pass` · `@x := 1, 2\ndef f(): pass` · `@a.b := 1\ndef f(): pass` · `x = a if b := c else d` · `x = a if b else c := 2` · `x = y := 1 or 2` · `x = *y := a,` · `(x := 1); y := 2` · `import x := 1` · `global x := 1` · `try: pass\nexcept x := E: pass` · `x[y := 1, z := 2:3]` · `x[:y := 1]` · `x[::y := 1]` · `not x := 1` · `-x := 1` · `(not x := 1)` · `(-x := 1)` · `(x := 1 := 2)` · `(x := y) := 1` · `((x := y) := 1)` · `[x := 1] = 2` · `[(x := 1)] = 2` · `(a, (x := 1)) = 2` · `for (x := 1), y in z: pass` · `for [x := 1] in z: pass` · `del [x := 1]` · `del (a, (x := 1))` · `with a as [x := 1]: pass` · `(x := 1) : int = 2` · `((x := 1)): int` · `f(a := b := 1)` · `f(a := *b)` · `f(a := **b)` · `f(a.b := 1)` · `f(a[0] := 1)` · `f((a) := 1)` · `f(1 := 1)` · `f(a := 1 = 2)` · `f(a = 1 := 2)` · `f(a := 1,, b)`

## Evidence (final tree)

| check | result |
|---|---|
| `bash tests/parser/run.sh` | **Parser PASS: 104, FAIL: 0** (26 `.bend` × 4 lanes; was 100: +`stmt_walrus`). Two full green runs (slice, battery). The first run of the slice was 103 / 1: `stmt_walrus [c build]`, **not a flake** — "an arity over 255" with 59 `&&` checks; trimmed to 40 (the dropped forms stay in the fixtures) |
| fixtures (`diff.py --fixtures all`) | **1,434 parsed / 1,434 exact** (P12: 1,196); 0 structural, 0 location, 0 refusals, 0 `Limit` |
| `fuzz.py` | 3,700 generated+directed (**500 walrus sources** on a fifth seeded stream `0xA57A2013`: 219 oracle-accepted, 281 oracle-rejected negatives; the first four streams' sources are untouched), 3,031 oracle-accepted, 669 oracle-rejected (each must answer `Syntax`), **0 failures**, 0 normalization failures, no `Limit`; + **860 negatives** (802 `INVALID` + 58 `UNSUPPORTED`) × 2 lanes = 1,720 runs; 150 JS samples |
| negatives vs oracle | every `STATEMENTS` source accepted, every `INVALID` rejected, every `UNSUPPORTED` accepted by the pinned `ast.parse` (script, 0 bad of 1,261 / 802 / 58) |
| oracle probe | 330 forms, 0 mismatches (section D) |
| `adversarial.py` | 28 / 28 runs, 0 fail-stops |
| `lexdiff.py --files 200` | 215 parsed; 0 kind/text diffs, 0 position diffs, 0 refusals; 25 JS samples, 0 diffs |
| `diff.py --self-test` | 20 / 20 round trips; ctx / constant / end-span corruption detected |
| final battery | see the last section |

The first fuzz run of the slice had **12 failures, all in the new generator, none in the
parser**: the stream's wrappers put a generated `with` / `try` line after `if a:` or `;`, which
the oracle rejects and this parser has always answered `Unsupported statement with` (compound
statement in simple position — a pre-existing policy, not a walrus one, left alone). Lines that
start with `with` / `try` / `@` now stay unwrapped. See Uncertainties.

### Corpus — whole files (the P13 success metric)

`supported` is decided independently from the oracle's AST tags (`NamedExpr` added); a supported
file the parser refuses is a failure.

| tier | eligible | oracle-failure | **before (P12)** | **after (P13)** parsed = supported = exact | structural / location diffs | refusals | `Limit` | fail-stop | JS parity |
|---|---|---|---|---|---|---|---|---|---|
| 1 (llm-wiki tools) | 5 | 0 | 5 (100 %) | **5 (100 %)** | 0 / 0 | 0 | 0 | 0 | 1 / 1 |
| 2 (Project tree) | 8,431 | 9 | 8,298 / 8,388 (**98.93 %**) | **8,396 / 8,422 (99.69 %)** | 0 / 0 | 0 | 0 | 0 | 418 parsed of 422 samples, 0 mismatches |
| 3 (stdlib) | 731 | 0 | 705 (**96.44 %**) | **729 (99.73 %)** | 0 / 0 | 0 | 0 | 0 | 36 parsed of 37 samples, 0 mismatches |

Same-manifest control (oracle tags only, over the very manifest of the run): tier 2 **8,341**
supported without `NamedExpr`, **8,396** with (**+55**); stdlib **705 → 729 (+24)**. **The P12
sole-blocker forecast was +55 / +24: both are exact.** The raw tier-2 numbers moved more than
+55 because the Project tree grew between runs (8,388 → 8,422 oracle-parsed files); the control
is the like-for-like figure.

Refusals left: tier 2 **26**, tier 3 **2** — every one `Unsupported … match statement`. `:=` no
longer appears as a refusal anywhere. Oracle-tag view: blocks `match` 26 / 2, sole `match`
26 / 2, nothing else — **no file in either tier is blocked by `except*` or a non-ASCII
identifier**. (The one tier-2 and one tier-3 file with walrus + `match` are now sole-`match`.)
Same runner as P12 (one manifest per tier, 100-file chunks 14-way through `diff.evaluate`); all
chunks returned ok; slowest whole file **26.3 s** (tier 2) / 23.0 s (tier 3) under 14-way load,
cap 30 s, no timeouts.

Walrus shape census, whole files, pinned `ast` (tier 2 / tier 3): files with a walrus 56 / 25,
supported 55 / 24; `NamedExpr` nodes 110 / 38 (109 / 35 in supported files). Parents, tier 2:
`If.test` 52, `While.test` 18, `Compare.left` 13, `BoolOp.values` 6, `comprehension.ifs` 6,
`Call.args` 5, `Attribute.value` 4, `IfExp.test` 2, `UnaryOp.operand` 1, `Compare.comparators`
1, `Slice.lower` 1 (parenthesised), `For.iter` 1 (parenthesised); tier 3: `If.test` 13,
`Compare.left` 9, `While.test` 6, `BinOp.left` 4, `Attribute.value` 3, `BoolOp.values` 1,
`Call.args` 1, `UnaryOp.operand` 1. One multi-line walrus per tier. No nested walrus values in
the corpus (the fixtures and the fuzz stream hold them).

### Corpus — per statement (`--segments`)

| tier | files | segments | bytes | parsed = exact | structural / location | statement nodes | JS |
|---|---|---|---|---|---|---|---|
| 1 | 5 | 105 | 76,289 | 5 / 5 | 0 / 0 | 1,242 | 1 / 1 |
| 2 | 8,126 | 155,107 | 107,465,346 | 8,126 / 8,126 | **0 / 0** | 1,316,112 | 420 / 420, 0 mismatches |
| 3 | 724 | 14,007 | 11,850,720 | 724 / 724 | **0 / 0** | 149,435 | 37 / 37, 0 mismatches |

**169,219 segments, 1,466,789 statement nodes, 0 structural + 0 location diffs**, incl. **145
`NamedExpr` nodes** (110 / 35). One tier-2 segment file (`seg-…-010-0082`, 488 segments,
960 kB) hit the 30 s cap under 14-way load (`fail-stop: timeout`); alone it parses in 15.6 s,
and its chunk re-run serially is 100 / 100 exact — the table is after that re-run. That is the
lexer cost P12 warned about, not the walrus; see Uncertainties.

### Token counts (`ttok`)

`parser.bend` 16,885 (P12 16,679; cap 64k) · `nodes.bend` 6,482 · `operators.bend` 1,143 ·
`parse_state.bend` 1,695 · `fixtures.py` 15,549 (cap 16k; 19 entries moved out) · `fixtures_walrus.py` 4,778 · `fixtures_async.py` 3,149 · `fuzz.py` 5,942 ·
`normalize.py` 1,974 · `stmt_walrus.bend` 2,462. `bun gates/repo.ts`: PASS 44 / 44. Readings
only; no cap edits.

## Deviations standing

- Compound statement after `:` on the same line or after `;` (`if a: with b: pass`) answers
  `Unsupported statement with|try|def|@`; the oracle answers `SyntaxError`. Pre-existing (the
  `O.unsupported` list is now `def try with @`), surfaced again by the new fuzz wrappers, not a
  walrus matter and not touched. It is the last refuse-first policy left; a one-line follow-up.
- Error **kind** only: CPython's specific messages (table above) are not reproduced; positions
  of `Syntax` are this parser's, not the oracle's offsets.
- Non-ASCII identifiers and `match` stay `Unsupported` (also inside a walrus).

## Uncertainties

- `demos/python/README.md` still says "43 grammar modes" (44 since P11). Not mine, left alone.
- **The 30 s cap is now being hit** by the measurement, once: a 960 kB segment file under 14-way
  load. Whole files peaked at 26.3 s (P10 18.6, P11 21.9, P12 25.1). The next corpus run should
  drop the runner to ~8-way or wait for the lexer lane; no parser change is implied.
- The "arity over 255" C-lane limit caps a lane test at roughly 40–50 `String.eq` checks in one
  `&&` chain. `stmt_async` has 40. Future lane files should stay near that or split.
- The walrus fuzz stream is 56 % negatives by design (most slots take no bare walrus); the
  accepted half is 219 sources. The probe and fixtures carry the systematic coverage.
- Strings suite: **84 / 1 (`deep [js build]`) on the first battery run, 85 / 0 on the retry** —
  the known load flake. Nothing else flaked.
- The corpus runner, control / census and probe scripts lived in `/tmp/p13` and are not
  committed, as before.
- `--segments` still does not descend into `def` bodies.

## Remainder (precise, in measured order)

1. **`match`** — the only blocker left in either corpus: sole **26 + 2** → Project 8,422 / 8,422
   of the oracle-parsed files (99.69 % → 100 %; the 9 oracle failures stay excluded), stdlib
   731 / 731. Soft keyword: the first slice that needs real lookahead / a second attempt.
2. `except*` and non-ASCII identifiers — **0 corpus files** blocked by either; fixtures-only
   value. Then the compound-in-simple-position policy above (Unsupported → Syntax).

## Final battery (serial, `942c6ba5` tree)

| command | result |
|---|---|
| `bun gates/repo.ts` | PASS: 44 / 44 |
| `bash tests/run.sh --strings` | Strings PASS: 84, FAIL: 1 (`deep [js build]`, known flake) → retry **85 / 0** |
| `bash tests/run.sh` | PASS: 16, FAIL: 0 |
| `bash tests/codex/run.sh` | 161 PASS, 0 FAIL; 0 suite errors |
| `bash tests/regex/run.sh` | Regex PASS: 49, FAIL: 0 |
| `bash tests/parser/run.sh` | Parser PASS: 104, FAIL: 0 |
