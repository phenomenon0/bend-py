# Parser lane — P10 report: annotated assignment (fable, 2026-09-19)

Branch `lane-parser-p10`, worktree `bend-work-parser-p10`, off `lane-parser-p9` at `72fa24f2`.
Continues `parser-p9.md`. Oracle pin unchanged: CPython **3.11.15**
(`/home/omen/.hermes/hermes-agent/venv/bin/python3`). Nothing pushed. `bend2/**`, `gates/**`,
`tests/caps.sh`, and other namespaces' tests untouched. The hand lexer is untouched and still
the default; its superlinear cost was not chased.

## Slices

| slice | commit | content |
|---|---|---|
| P10 | `547d47e7` | annotated assignment: the `:` branch of `AfterSmall` in `parser.bend` (no new mode; `AfterSmall` gains `soft`, the statement's first token being `match`), `annotated` / `ann_target` / `group_head` / `starts_at` in `nodes.bend`; oracle tag `AnnAssign` in `normalize.py`; fixtures + negatives + a second fuzz stream; four-lane `stmt_annassign.bend`; one stale P9 expectation in `stmt_errors.bend` (`x: int = 1` was the example of `Unsupported` — it parses now; the example is `x: int = yield`); README subset. |
| P10 docs | this commit | this report. |

Every corpus number below is a fresh run on the `547d47e7` tree (the docs commit changes no
parser or harness source).

## What landed

`AnnAssign{target, annotation, value, simple}` in CPython 3.11 field order with exact spans
(statement = first token of the target, its `(` included, to the end of the value or, without
one, of the annotation).

- **No new mode, no backtracking.** A simple statement already parses its leading
  star-expressions and looks at the next token (`=`, an augmented operator, end). `:` there is
  the annotation: target check → `Expression{0}` (CPython's `expression`: ternary and lambda
  allowed, a bare tuple or a star is `Syntax`) → optional `=` + `TestList{0}` (`annotated_rhs` =
  star-expressions: `x: T = 1, 2`, `x: T = *a, b`, even `x: T = *a`). Mode count stays 43.
- **Targets**: exactly augmented assignment's set — `Name`, `Attribute`, `Subscript` (slices and
  slice tuples included), in `Store`; the base stays `Load`. Tuple / list / starred / call /
  literal / operator targets are `Syntax`, as in CPython ("only single target … can be
  annotated", "illegal target for annotation").
- **`simple`** is `1` only for a bare unparenthesised `Name`: `(x): int` and `((x)): int = 1`
  are `simple=0` with the Name's own span (the P2 grouping bit, no new state); attribute and
  subscript targets are always `0`.
- **`value` is optional for every target kind** — the brief's question, settled by the oracle:
  `a[0]: T`, `a.b: T`, `a[1:2]: T`, `(a.b): T` all parse with `value: null`. The corpus uses it:
  39 value-less non-Name targets in tier 2 (`self.x: T` declarations).
- **Inside and outside class bodies** the node is the same (the class-body distinction is the
  compiler's `__annotations__`, not `ast.parse`'s); `def`, `if`/`for`/`while`/`try`/`with`
  suites, one-line suites (`if a: x: int`, `class A: x: int = 1; y: str`) and `;` lists all
  pass through the one `Small` path.
- **Annotations are arbitrary expressions**: names, attributes, subscripts
  (`Dict[str, Tuple[int, ...]]`, `Callable[[int], bool]`), strings (incl. implicit
  concatenation and f-strings), `int | None`, calls, ternaries, lambdas, displays,
  comprehensions, parenthesised and multi-line forms, backslash continuations.

### What the oracle revealed (and the fuzz found)

- **PEG commitment: `(a).b: T` is illegal, `((a).b): T` is not.** The 3.11 rule is
  `('(' single_target ')' | single_subscript_attribute_target) ':' expression …`. A PEG group
  commits to its first successful alternative: once `'(' single_target ')'` matches the leading
  `(a)`, the group is done, the next token is not `:`, and the second alternative is never
  tried — "illegal target for annotation". So a target that *starts* with a parenthesised
  Name / Attribute / Subscript and goes on is rejected: `(a)[0]: T`, `(a).b: T`, `(a)(b).c: T`,
  `((a))[0]: T`, `(a.b).c: T`, `(f().c)(d).e: T`; while `((a)[0]): T`, `(f()).c: T`,
  `(a, b)[0]: T`, `(a + b).c: T`, `[a][0]: T`, `().b: T` are fine (what the parentheses hold is
  not a single target, or the group is the whole target). Plain and augmented assignment have
  no such rule (`(a)[0] = 1`, `(a).b += 1` parse). **No directed fixture of mine had it; the
  second fuzz stream found it on its first run** (oracle-rejected sources this parser
  accepted). Implemented without parser state: down the target's leftmost
  `Attribute`/`Subscript`/`Call` chain, the first node that does not begin at the statement's
  start is what the leading parentheses hold; if it is a Name / Attribute / Subscript and the
  target as a whole is not grouped → `Syntax` (`N.group_head`, from the `_loc`s already on the
  wire JSON). Negatives and positives of each shape above pin it in `fixtures.py`, plus the four-lane fixture.
- **`match` as a target vs a `match` header.** `match: int = 1`, `match[0]: int`,
  `match.x: int = 1`, `(match): int` are annotated assignments; `match (x):`, `match [x]:`,
  `match (x).y[0]:`, `match -x:` read as an expression up to the `:` and must stay
  `Unsupported` (they are valid 3.10+ `match` statements). A `match` header is the only one of
  the two that ends the line at the `:`, so: first token `match` and NEWLINE after the `:` →
  `Unsupported` (`match statement`). Exact, not a heuristic: `x:` + NEWLINE is never a valid
  annotated assignment.
- `x: int = y = 1`, `x = y: int`, `x: int: str`, `x: int += 1` are `Syntax` (no chaining in
  either direction). `x: int = yield`, `x: (yield)`, `x: await z`, `x: (y := 1)` are
  oracle-accepted and answer `Unsupported` (their own later slices).

## Evidence (final tree)

| check | result |
|---|---|
| `bash tests/parser/run.sh` | **Parser PASS: 92, FAIL: 0** (23 `.bend` × 4 lanes; was 88: +`stmt_annassign`) — see Uncertainties for one flaky run |
| fixtures (`diff.py --fixtures all`) | **771 parsed / 771 exact** (P9: 596); 0 structural, 0 location, 0 refusals, 0 `Limit` |
| `fuzz.py` | 2,037 generated+directed (**250 annotated sources** on a second seeded stream, so the P2–P9 generated sources are byte-identical to P9's), 1,885 oracle-accepted, 152 oracle-rejected generated negatives (119 of them annotated: illegal targets, the PEG quirk), **0 failures**, 0 `Limit`; **491 negative cases** (982 runs, C+JS; was 362); 94 JS samples; fuel high-water unchanged (P8's many-field f-string; annotated max 3.65 dispatches / token) |
| negatives vs oracle | every `STATEMENTS` source accepted, every `INVALID` rejected, every `UNSUPPORTED` accepted by the pinned `ast.parse` (checked by script this session, 0 bad of 598 / 402 / 89) |
| `adversarial.py` | 28 / 28 runs, 0 fail-stops |
| `lexdiff.py --files 200` | 215 parsed; 0 kind/text diffs, 0 position diffs, 0 refusals; 25 JS samples, 0 diffs |
| `diff.py --self-test` | 20 / 20 round trips; ctx / constant / end-span corruption detected |
| final battery | see the last section |

### Corpus — whole files (the P10 success metric)

`supported` is decided independently from the oracle's AST tags (`AnnAssign` added); a
supported file the parser refuses is a failure.

| tier | eligible | oracle-failure | **before (P9)** | **after (P10)** parsed = supported = exact | structural / location diffs | refusals | `Limit` | fail-stop | JS parity |
|---|---|---|---|---|---|---|---|---|---|
| 1 (llm-wiki tools) | 5 | 0 | 5 (100 %) | **5 (100 %)** | 0 / 0 | 0 | 0 | 0 | — |
| 2 (Project tree) | 8,357 | 9 | 6,226 / 8,342 (**74.6 %**) | **7,573 (90.6 %)** | 0 / 0 | 0 | 0 | 0 | 385 parsed of 418 samples, 0 mismatches |
| 3 (stdlib) | 731 | 0 | 606 (**82.9 %**) | **610 (83.4 %)** | 0 / 0 | 0 | 0 | 0 | 36 parsed of 41 samples, 0 mismatches |

Same-manifest control (oracle tags only, over the very manifest of the run): tier 2 **6,241**
supported without the `AnnAssign` tag, **7,573** with (**+1,332**); stdlib **606 → 610 (+4)**.
**The P9 sole-blocker forecast was +1,332 / +4 → ≈ 90.6 % / 83.4 %: both are exact.** The raw
tier-2 delta is +1,347; the other +15 is the live listing's growth (8,342 → 8,357 eligible —
this worktree's own `tests/parser/*.py` among them). The jump is annotated assignment, not
manifest drift.

`annotation` no longer appears as a refusal anywhere. All 84 + 6 whole-file chunks exited 0;
slowest file 18.6 s (tier 2) / 15.9 s (tier 3) under 14-way load, cap 30 s, no timeouts.

Parser refusals now (first refusal per file):

| tier 2 (775 refused) | | tier 3 (121 refused) | |
|---|---|---|---|
| `async` (production 191 + statement 180) | 371 | `yield` (statement 80 + production 1) | 81 |
| `yield` (statement 332 + production 1) | 333 | walrus | 20 |
| walrus | 46 | `async` statement | 18 |
| `match` | 22 | `match` | 1 |
| argument | 3 | argument | 1 |

Oracle-tag view of what is left (tier 2 / tier 3 files). **Blocks** (any position): async 379 /
21 · yield 374 / 89 · walrus 56 / 25 · `match` 26 / 2. **Sole** blocker: **async 339 / 17 ·
yield 318 / 74** · walrus 39 / 15 · `match` 20 / 0. Top pairs (tier 2): async+yield 37,
walrus+yield 13, `match`+yield 5. No other unsupported tag occurs (no `except*`, no non-ASCII
identifier file is blocked by that alone).

### Corpus — per statement (`diff.py --corpus N --segments`)

| tier | files | segments | bytes | parsed = exact | structural / location | statement nodes | JS |
|---|---|---|---|---|---|---|---|
| 1 | 5 | 105 | 76,289 | all | 0 / 0 | 1,242 | 1 / 1 |
| 2 | 8,052 | 155,015 | 102,766,484 | all | 0 / 0 | 1,264,361 | 416 / 416 |
| 3 | 723 | 15,516 | 11,452,966 | all | 0 / 0 | 145,205 | 41 / 41 |

**170,636 segments, 1,410,808 statement nodes, ~114.3 MB, 0 structural + 0 location diffs.**
(P9: 174,879 segments / 1,319,479 nodes. Segments fall again because classes harvested member
by member — dataclasses above all — are now supported whole and count once; the node count is
the honest size: +91,329.) All 84 + 6 + 1 segment chunks exited 0.

`AnnAssign` shape coverage in the segment corpus (tier 2 / tier 3, counted with the pinned
`ast`; tier 1 has none): **20,189 / 36** nodes · target `Name` 18,832 / 31, `Attribute` 1,355 /
5, **`Subscript` 2 / 0** · `simple=0` 1,357 / 5 · no value 6,036 / 14 · no value on a non-Name
target 39 / 0 · spanning lines 1,607 / 2. In the supported whole files (16,765 / 29 nodes):
annotation `Name` 8,425, `Subscript` 6,667, `BinOp` (`X | None`) 1,109, `Attribute` 518,
`Constant` (string) 29, `Call` 17; value a bare `Tuple`/`Starred` 102 / 2. **A parenthesised
Name target (`(x): T`) occurs 0 times in the corpus, a subscript target twice: both, and the PEG
quirk, are covered by fixtures and fuzz only.**

### Token counts (`ttok`, measured; caps not edited)

parser 15,929 (was 15,663) · nodes 6,243 (was 5,647) · README 1,573 (was 1,493) · operators,
parse_state, fstring, lexer, syntax unchanged · `stmt_annassign.bend` 1,604 (new) ·
`stmt_errors.bend` 256 · `fixtures.py` 12,979 (was 9,852) · `fuzz.py` 2,900 (was 2,534) ·
`normalize.py` 1,979. `bun gates/repo.ts` PASS 44 / 44 with these.

## Deviations

- **`match x: int` is `Unsupported`, the oracle says `SyntaxError`.** Same standing
  conservative-refusal policy as P9's unparenthesised walrus: the statement is refused as a
  `match` statement before the grammar around it is judged. Likewise `x: @d` / `x: int = @`
  (`production @`) and `x: y := 1` / `x: int = y := 1` (`production :=`). They are in neither
  `INVALID` nor `UNSUPPORTED`.
- **Error message**: tuple/list/call targets answer `Syntax` "invalid assignment target" (the
  shared `N.target` check), the PEG-quirk ones "illegal target for annotation". Kinds and
  positions are what the harness compares; messages are not matched to CPython's.
- **`AfterSmall` carries `soft`** (first token is `match`) rather than re-deriving it from the
  target tree: `(match)[0]:` + NEWLINE and `match[0]:` + NEWLINE differ only in that token.
- **The fuzz got a second RNG stream** (`0xA57A2010`) instead of new templates in the first:
  adding a choice to the first stream would have reshuffled all 1,000 P2–P9 generated sources.
- Trusted expected output in `stmt_annassign.bend`: as in P5–P9, the wire text is the C lane's
  output for a source that is also in `fixtures.py`, where `diff.py` proves it equal to the
  oracle; the four lanes then agree on it.

## Uncertainties

- **The checker's JS stack depth flaked once** (P8's known flake, `bend2/bend.ts`, not
  touchable here): full `run.sh` runs on the final tree were 92 / 0, **91 / 1**
  (`stmt_functions [check]`, "Maximum call stack size exceeded" in `term_check` on that
  fixture's one large string literal), then 5 / 5 isolated reruns of that fixture ok, then
  92 / 0. 1 failure in 9 checks of that fixture this session (the pre-fix 89 / 4 run included). The parser is 266 tokens larger
  and `stmt_functions` itself is unchanged, so this is more likely load than growth — not
  proven either way.
- **Lexer cost on very large files** (unchanged, not chased): slowest whole-file parse 18.6 s
  under 14-way load against the 30 s cap.
- `--segments` still does not descend into `def` bodies; annotated assignments inside
  unsupported functions are covered by fixtures/fuzz and the 8,188 whole files.
- A first draft of the fixture edit mis-targeted two string replacements (it rewrote my new
  `STATEMENTS` entries instead of P9's `UNSUPPORTED` ones); the first full run caught it
  (15 fuzz failures on that run, the PEG quirk and the policy cases among them; 0 after). The committed tree never
  had it.

## Remainder (precise, in measured order)

1. **`yield` / `yield from`** — the stdlib jump: sole **318 + 74** → Project 90.6 % → ~94.4 %,
   stdlib 83.4 % → **~93.6 %**; blocks 374 / 89. (`x: T = yield` is already wired: the value
   goes through `TestList`, so it lands with the expression.)
2. **`async` / `await`** — now the larger Project jump: sole **339 + 17** (Project +4.1 pts,
   stdlib +2.3); includes `async for` in comprehensions (one peek in `Comp`, P9). yield and
   async together with their 37 + 4 shared files: Project → ~98.9 %, stdlib → ~96.4 %.
3. Walrus (sole 39 + 15), then `match` (20 + 0), `except*`, non-ASCII identifiers.
4. Upstream (unchanged): early exit in `Regex.exec.run`, then re-measure the P3 candidate; the
   hand lexer's superlinear cost on ~1 MB files; the checker's stack depth.

## Final battery (serial, final tree)

| check | measured |
|---|---|
| `bun gates/repo.ts` | **PASS 44 / 44** |
| `bash tests/run.sh --strings` | **85 / 0** (first run; the `deep` flake did not occur) |
| `bash tests/run.sh` (f64) | **16 / 0** |
| `bash tests/codex/run.sh` | **161 PASS, 0 FAIL**, 0 suite errors |
| `bash tests/regex/run.sh` | **49 / 0** |
| `bash tests/parser/run.sh` | **92 / 0** (after the one flaky 91 / 1 above) |

Nothing was skipped. As in P8–P9, the gate / strings / f64 totals (44 / 85 / 16) are this
base's full suites; the base predates the reduce / strfix / tour merges, and the counts after a
rebase were not verified here.
