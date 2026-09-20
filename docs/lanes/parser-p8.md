# Parser lane — P8 report: f-strings (fable, 2026-09-19)

Branch `lane-parser-p8`, worktree `bend-work-parser-p8`, off `lane-parser-p7` at `21c1be35`.
Continues `parser-p7.md`. Oracle pin unchanged: CPython **3.11.15**
(`/home/omen/.hermes/hermes-agent/venv/bin/python3`). Nothing pushed. `bend2/**`, `gates/**`,
`tests/caps.sh`, and other namespaces' tests untouched. The hand lexer gained 4 lines (`lex_at`,
a position-true entry) and is otherwise untouched; its superlinear cost was not chased.

## Slices

| slice | commit | content |
|---|---|---|
| P8 | `16c952e9` | f-strings: new `fstring.bend` (scanner after `fstring_find_literal` / `fstring_find_expr`), 2 modes in `parser.bend`, builders in `nodes.bend`, `within` in `parse_state.bend`, `lex_at` in `lexer.bend`; oracle tags `JoinedStr` `FormattedValue`, `_parts` decoding in `normalize.py`, fixtures + negatives + fuzz shape, four-lane `stmt_fstrings.bend`; README subset. |
| P8 fix + docs | this commit | the f-string fuel weight (a wrong `Limit`, found while writing this report), the oracle's quadratic source-segment fix, 3 regression fixtures, README fuel wording, this report. |

The first P8 session died after `16c952e9`, mid-corpus. Its `_out/` artifacts were incomplete
(tier 2: 11 of 84 chunks, with gaps at 400 / 600 / 1000; no segment runs), so **every corpus
number below is a fresh run on the final tree**, not a salvage.

## What landed

3.11 f-strings are one `STRING` token (the tokenizer's shape, kept). `fstring.bend` scans the
body; each replacement field's text is re-lexed as `(expr)` from the `{` by `lex_at`, so every
inner token keeps its true source position and a bare tuple takes CPython's paren span; the
same `go` parses it on its own budget (`within`), then the outer state resumes untouched.

- `JoinedStr{values}` / `FormattedValue{value, conversion, format_spec}` in CPython field
  order; `!r` / `!s` / `!a`; the debug `=` (`f"{x = }"`, `f"{x=!s}"`, `f"{x=:>10}"`) expanded to
  its verbatim text Constant + default `!r` exactly as CPython does.
- Format specs as nested `JoinedStr`s with nested fields (`f"{x:>{w}.{p}f}"`), nesting bounded
  at CPython's 2 levels (`f-string: expressions nested too deeply`).
- Nested f-strings in fields, raw (`rf` / `fR` …: backslashes verbatim), triple-quoted and
  multi-line bodies, `\N{…}` (a brace that is not a field), escaped `{{` `}}`, `!=` / `==` /
  `>=` / `<=` inside a field not mistaken for a conversion or debug `=`.
- Implicit concatenation with plain strings on either side, with CPython's kind (`u`) and
  adjacent-text merge rules; `bytes` + f-string is `Syntax` ("cannot mix bytes and nonbytes").
- Text Constants travel on the wire as `_parts` pieces (`s` plain token, `f` f-string literal
  text, `v` verbatim) that the harness decodes and joins, so Bend still does no escape
  decoding or float conversion.
- Errors: `f"{}"`, `f"{x!z}"`, `f"{x"`, `f"x}"`, `f"{a b}"`, `f"{x#}"`, a backslash in a field,
  `f"{(a}"` / `f"{[a)}"`, `f"{lambda x: 1}"`, `f"{a = b}"`, `f"{x:{y:{z}}}"`, `f"{x}" = 1`,
  `del f"{x}"`, … are `Syntax` (42 f-string negatives); comprehension / walrus / `yield` /
  `await` / non-ASCII names inside a field stay `Unsupported`.

Machinery: `Mode` 39 → 41 (`FString`, `Joined`); no new backtracking; `fuel_k` stays 32.

## Evidence (final tree, this commit)

| check | result |
|---|---|
| `bash tests/parser/run.sh` | **Parser PASS: 84, FAIL: 0** (21 `.bend` × 4 lanes; was 80: +`stmt_fstrings`) — see Uncertainties for one flaky first run |
| fixtures (`diff.py --fixtures all`) | **471 parsed / 471 exact** (P7: 388; `16c952e9`: 468; +3 fuel regressions); 0 structural, 0 location, 0 refusals, 0 `Limit` |
| `fuzz.py` | 1,487 generated+directed (423 f-string sources), 1,466 oracle-accepted, 21 oracle-rejected generated negatives, **0 failures**, 0 `Limit`; **266 negative cases** (532 runs, C+JS; was 217); 73 JS samples |
| negatives vs oracle | all 211 `INVALID` rejected by the pinned `ast.parse`, all 55 `UNSUPPORTED` accepted by it (checked by script this session) |
| `adversarial.py` | 28 / 28 runs, 0 fail-stops |
| `lexdiff.py --files 200` | 215 parsed; 0 kind/text diffs, 0 position diffs, 0 refusals; 25 JS samples, 0 diffs |
| `diff.py --self-test` | 20 / 20 round trips; ctx / constant / end-span corruption detected |
| final battery | see the last section |

### Corpus — whole files (the P8 success metric)

`supported` is decided independently from the oracle's AST tags (`JoinedStr`,
`FormattedValue` added); a supported file the parser refuses is a failure.

| tier | eligible | oracle-failure | **before (P7)** | **after (P8)** parsed = supported = exact | structural / location diffs | refusals | `Limit` | fail-stop | JS parity |
|---|---|---|---|---|---|---|---|---|---|
| 1 (llm-wiki tools) | 5 | 0 | 0 (0 %) | 0 (0 %) — all 5 still refuse (supported 0) | 0 / 0 | 0 | 0 | 0 | — |
| 2 (Project tree) | 8,327 | 9 | 2,186 / 8,246 (**26.5 %**) | **3,258 (39.1 %)** | 0 / 0 | 0 | 0 | 0 | 163 / 163 parsed samples, 0 mismatches on all 417 samples |
| 3 (stdlib) | 731 | 0 | 388 (**53.1 %**) | **443 (60.6 %)** | 0 / 0 | 0 | 0 | 0 | 27 / 27 parsed samples, 0 mismatches on all 41 |

Same-manifest control (oracle tags only, over the very records of the run): tier 2 **2,190**
supported without the two f-string tags, **3,258** with (**+1,068**); stdlib **388 → 443
(+55)**. The P7 forecast was +1,066 / +55: stdlib is exact, and tier 2 is the forecast plus the
live listing's growth (an earlier full pass of this session, on a listing of 8,302, measured
2,189 → 3,255 = **+1,066 exactly**). So the jump is the f-strings, not manifest drift.

Project **1.49×**, stdlib **1.14×**. `f-string` no longer appears as a refusal anywhere.

Parser refusals now (first refusal per file):

| tier 2 (5,060 refused) | | tier 3 (288 refused) | |
|---|---|---|---|
| comprehension | 2,020 | comprehension | 121 |
| annotation (annotated assignment) | 1,233 | generator argument | 53 |
| generator argument | 893 | `yield` | 48 |
| dict comprehension | 459 | dict comprehension | 20 |
| `async` (statement 97 + production 124) | 221 | walrus | 15 |
| `yield` | 142 | `async` | 15 |
| `for` in expression | 60 | `for` in expression | 11 |
| `match` | 17 | annotation | 5 |
| walrus | 15 | | |

Oracle-tag view of what is left (tier 2 / tier 3 files). **Blocks** (any position):
comprehension family 4,391 / 243 · `AnnAssign` 1,619 / 8 · async 379 / 21 · yield 374 / 89 ·
walrus 56 / 25 · `match` 26 / 2. **Sole** blocker (adding just this group completes the file):
**comprehension family 2,953 / 163** · `AnnAssign` 373 / 2 · async 139 / 12 · yield 62 / 18 ·
walrus 8 / 9. No file is unsupported by non-ASCII identifiers alone.

### Corpus — per statement (`diff.py --corpus N --segments`)

| tier | files with ≥ 1 segment | segments | statement nodes (all depths) | `JoinedStr` / `FormattedValue` nodes | bytes | parsed = exact | structural / location diffs | refusals | JS parity |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 5 | 91 | 765 | 73 / 104 | 47,958 | 5 / 5 | 0 / 0 | 0 | 1 / 1 |
| 2 | 8,020 | 155,848 | 889,041 | 37,753 / 51,571 | 69,575,431 | 8,020 / 8,020 | 0 / 0 | 0 | 415 / 415 |
| 3 | 723 | 18,151 | 137,102 | 763 / 1,091 | 10,674,491 | 723 / 723 | 0 / 0 | 0 | 41 / 41 |

**Gate: 0 structural and 0 location diffs on everything supported — met**, on 174,090
segments / 1,026,908 statement nodes (80.3 MB; P7: 165,331 / 802,335 / 62.0 MB), which re-runs
the whole P4–P7 corpus and adds **38,589 real `JoinedStr` and 52,766 `FormattedValue` nodes**.
(The stdlib segment *count* fell from 19,097 because functions and classes that were harvested
member-by-member are now supported whole and count once; the node count is the honest size.)

f-string shape coverage in the supported corpus (tier 2 / tier 3, counted from the harvested
segment files with the pinned `ast`): spanning lines (triple-quoted or concatenated runs)
3,541 / 123 · format specs 6,816 / 28, with a nested field in the spec 25 / 2 · `!r` 1,462 /
324 · `!s` 8 / 3 · an f-string nested in a field 18 / 0. Not hit by the supported corpus: `!a`
— fixtures and fuzz only.

### Token counts (`ttok`, measured; caps not edited)

parser 14,758 (was 13,096) · fstring 2,982 (new) · nodes 5,369 (was 4,960) · lexer 3,509 (was
3,410) · parse_state 1,744 (was 1,440) · syntax 1,704 (was 1,551) · README 1,436 (was 1,213).
`bend2/base.bend` reads 42,318 in this worktree — untouched.

## Deviations

- **The spec closing-Constant token-span quirk** (CPython 3.11, reproduced, not invented): every
  text Constant of an f-string run takes the span of the *whole run* of adjacent string tokens
  and the run's kind — except a format spec's text that *follows a nested field*, which takes
  its *own STRING token's* span and no kind. In `x = "a" f"{b:>{w}.2f}" "c"` the oracle gives
  `'a'`, `'c'` and `'>'` columns 4–26 and `'.2f'` columns 8–22. The spec's nested `JoinedStr`
  likewise takes the token's span. Invisible when the f-string stands alone; fixtures
  `'u"" f"{x:a{y}b}" "b"'` and the two after it pin it. It is why `FString` carries both
  the run's and the token's bounds (`F.Ctx`).
- **A wrong `Limit` in `16c952e9`, fixed here.** The budget was `32 × (tokens + 1)`, but an
  f-string is one token whose body dispatches once per text run / field: a small file holding
  one f-string of many fields (`f"{a}x{a}x…"`, 3 tokens, budget 128: 60 fields parsed, 200
  answered `Limit`) refused valid input. The fuzz never generated that many fields and no corpus file is that lopsided (a real
  file's budget is shared across all its tokens; the corpus had 0 `Limit` before and after), so
  it was found by reading the fuzz highwater (4.5 dispatches/token, up from 3.25), not by a
  failure. Fix: `S.fuel_weight` — one per token plus a `STRING`'s characters — feeds both the
  outer budget and each field's `within` budget (every f-string dispatch consumes at least one
  character of its token, so this is still a terminating, linear bound). 300-field fixtures
  (body, spec, nested-in-field) pin it; 5,000 fields parse. The fuzz `highwater.ratio` is now
  79 per *token* because those fixtures are in it; outside them it is 4.5. The whole corpus
  was re-run after the fix.
- **Oracle harness: a quadratic `ast.get_source_segment`.** It re-splits the whole source per
  Constant; on `Maestro/app/launch.py` (986 KB) the oracle alone took **> 580 s** (this is the
  chunk that was missing from the dead session's artifacts, and very likely why P7's tier-2
  batches overran 10 minutes). `normalize.py` now splits once with the same
  `ast._splitlines_no_ff` and slices with the stdlib's own arithmetic: 0.64 s, and equal to
  `ast.get_source_segment` on 15,623 Constants of 60+ stdlib files (checked by script). It uses
  a private stdlib function, acceptable only because the oracle is pinned to 3.11.15.
- Whole-file "before" is the P7 report's measurement (2,186 / 8,246), not re-run; the
  same-manifest tag control (2,190 → 3,258) stands in for it.
- The tier-2 manifest is a live listing shared with other sessions' worktrees: 8,302 eligible
  at the first pass, 8,327 at the final one (8,020 segment files). < 0.5 % on the denominator;
  all 180 final chunks exited 0 (84 + 84 tier-2, 6 + 6 tier-3) plus tier 1.
- Corpus ran as 100-file (tier 2) / 125-file (tier 3) chunks, 14 in parallel, **in the
  foreground** under a wall-clock cap; with the oracle fix the whole of tier 2 fits in one
  8-minute window. Latencies under parallel load are not reported as timings.
- JS parity is reported as parsed-sample counts (5 % deterministic sample); 0 mismatches on
  every sample, parsed or refused.
- `stmt_fstrings.bend`'s expected wire is the C lane's output for sources that are also in the
  fixtures, where `diff.py` proves them equal to the oracle; the four lanes then agree on it.
- Conservative refusals, unchanged policy: an unsupported production inside a field
  (`f"{[x for x in y]}"`) is `Unsupported` even where CPython would go on to a `SyntaxError`.

## Uncertainties

- **One flaky `[check]`**: the first full `tests/parser/run.sh` after the fuel fix printed
  83 / 1 — `stmt_functions [check]` died with `RangeError: Maximum call stack size exceeded`
  inside `bend2/bend.ts` `term_check`. The same check passed twice standalone and the suite
  passed 84 / 84 on the next two full runs. The checker's JS stack depth on the parser is near
  bun's limit and JIT-tier dependent; `bend.ts` is out of lane. Expect it to recur as the
  parser grows.
- **Lexer cost on very large files** (unchanged, not chased): whole-file under 14-way load,
  `Maestro/app/launch.py` **23.4 s**, `wgp.py` 12.3 s, `pydoc_data/topics.py` 15.7 s — the
  closest yet to the 30 s fail-stop cap. No timeouts occurred.
- `--segments` still does not descend into `def` bodies; f-strings inside unsupported functions
  are covered by fixtures/fuzz and by the 3,701 whole files, not by segments.

## Remainder (precise, in measured order)

1. **Comprehensions / generator arguments / dict comprehensions** — now the first refusal in
   3,432 + 205 files and the **sole blocker of 2,953 + 163**: Project 39.1 % → ~74.6 %, and the
   **bigger stdlib jump**, 60.6 % → ~82.9 %. Settles the `class A(genexp)`, `a[genexp]` and
   f-string-field deviations.
2. **Annotated assignment** — the sleeper: first refusal in 1,233 tier-2 files, blocks 1,619,
   sole blocker of 373 + 2 (2.5× its P7 figure, since f-strings no longer co-block), and the
   scout found it in nearly every refusal list across requests / click / pandas / urllib3. The
   cheapest slice left (`target: annotation [= value]`, the `simple` flag).
3. `async` / `await` (sole 139 + 12), `yield` / `yield from` (62 + 18; stdlib-heavy, blocks
   89), walrus (8 + 9; blocks 25 stdlib), `match` (blocks 26 + 2, sole 0), `except*`,
   non-ASCII identifiers.
4. Upstream (unchanged): early exit in `Regex.exec.run`, then re-measure the P3 candidate; the
   hand lexer's superlinear cost on ~1 MB files; the checker's stack depth (above).

## Final battery (serial, final tree)

| check | expected by the brief | measured |
|---|---|---|
| `bun gates/repo.ts` | 45 / 45 | **PASS 44 / 44** (with this report in the tree) |
| `bash tests/run.sh --strings` | 89 / 0 | **85 / 0**, first run (no `deep` flake) |
| `bash tests/run.sh` (f64) | 19 / 0 | **16 / 0** |
| `bash tests/codex/run.sh` | 161 | **161 PASS, 0 FAIL**, 0 suite errors |
| `bash tests/regex/run.sh` | 49 / 0 | **49 / 0** |
| `bash tests/parser/run.sh` | 84 / 84 | **84 / 0** |

Everything that ran passed, nothing was skipped. Three totals are *smaller* than the brief's
(gate 44 vs 45, strings 85 vs 89, f64 16 vs 19): this branch's base predates the reduce /
strfix merges, and the counts are this base's full suites (P7 measured the same 85 and 16) —
not failures, but not the brief's numbers either; they should reach 45 / 89 / 19 once the lane
is rebased onto a base with those merges, and that was not verified here.
