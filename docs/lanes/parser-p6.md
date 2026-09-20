# Parser lane — P6 report: `class` (fable, 2026-09-18)

Branch `lane-parser-p6`, worktree `bend-work-parser-p6`, off `lane-parser-p5` at `a5e9007e`.
Continues `parser-p5.md`. Oracle pin unchanged: CPython **3.11.15**
(`/home/omen/.hermes/hermes-agent/venv/bin/python3`). Nothing pushed. `bend2/**`, `gates/**`,
`tests/caps.sh`, and other namespaces' tests untouched. The hand lexer is untouched and still
the default.

## Slices

| slice | commit | content |
|---|---|---|
| P6 | `2cd03d73` | `class` in `parser.bend` (1 new mode), 1 builder in `nodes.bend`, `class` dropped from `O.unsupported`; oracle tag `ClassDef`, fixtures + negatives + fuzz template, four-lane `stmt_classes.bend`, segment harvester takes supported classes whole; README subset. |
| docs | this commit | this report. |

## What landed

- `class NAME [ '(' [arguments] ')' ] ':' suite` → `ClassDef(name, bases, keywords, body,
  decorator_list)` in CPython field order. Location starts at the `class` token (decorators
  excluded, as in 3.8+) and ends with the body.
- The base list **is** the call argument grammar, so it reuses the existing `Arguments` mode on
  a placeholder callee and `N.class` keeps the resulting `Call`'s `args` / `keywords`: positional
  bases, `*bases`, `metaclass=M` and any `name=value`, `**kwds`, trailing comma, multi-line, and
  the same ordering errors (`class A(x=1, y)`, `class A(**k, *y)` are `Syntax`).
- Decorators: `Decorators` now ends in `def` **or** `class`; anything else after `@…` is `Syntax`.
- Bodies are the ordinary `Suite`: methods, docstrings (plain `Expr(Constant)` — `ast.parse`
  has no docstring node), one-line bodies (`class A: x = 1; y = 2`), **nested classes** (in
  classes, in `def`, in `if`) — all in, nothing deferred.
- `class é`, `class A(é)`, `class A(é=1)` stay `Unsupported` (identifier normalization);
  `class match: pass` parses (soft keyword).

Machinery: mode `Class{start, decorators}`; `Mode` 35 → 36 cases; **no new backtracking**;
`fuel_k` stays 32 (fuzz highwater unchanged at 3.25 dispatches/token).

## Evidence (tree `2cd03d73`)

| check | result |
|---|---|
| `bash tests/parser/run.sh` | **Parser PASS: 76, FAIL: 0** (19 `.bend` × 4 lanes; was 72: +`stmt_classes`) |
| fixtures (`diff.py --fixtures all`) | 320 parsed / 320 exact (was 292); 0 structural, 0 location, 0 refusals |
| `fuzz.py` | 1,335 generated+directed, 1,332 oracle-accepted, **0 failures**, 0 `Limit`; 185 negative cases (370 runs, C+JS; was 157); 67 JS samples; highwater 3.25 / 32 |
| negatives vs oracle | all 144 `INVALID` rejected by the pinned `ast.parse`, all 41 `UNSUPPORTED` accepted by it (checked by script, not assumed — it caught one, see Deviations) |
| `adversarial.py` | 28 / 28 runs, 0 fail-stops |
| `lexdiff.py --files 200` | 215 parsed; 0 kind/text diffs, 0 position diffs, 0 refusals; 25 JS samples, 0 diffs |
| `bash tests/run.sh` | PASS 16 / 16 |
| `bash tests/codex/run.sh` | 161 PASS, 0 FAIL |
| `tests/regex/oracle.py --pairs 500` | diffs c=0 js=0 interpret(500)=0 |
| `bash tests/run.sh --strings` | **85 / 85** first run (no `deep` flake this time) |

The 3 fuzz inputs the oracle rejects all fail on line 1 with the generator's pre-existing
`a < not (b)` value shape (was 2; the new template shifts the RNG stream). The share of the
1,000 generated inputs that drew the class template was not counted.

### Corpus — whole files (the P6 success metric)

`supported` is decided independently from the oracle's AST tags (`ClassDef` added); a supported
file the parser refuses is a failure.

| tier | eligible | oracle-failure | **before (P5)** | **after (P6)** parsed = supported = exact | structural / location diffs | refusals | fail-stop | JS parity |
|---|---|---|---|---|---|---|---|---|
| 1 (llm-wiki tools) | 5 | 0 | 0 (0 %) | 0 (0 %) | 0 / 0 | 0 | 0 | — |
| 2 (Project tree) | 8,196 | 9 | 1,215 / 8,110 (**15.0 %**) | **1,801 (22.0 %)** | 0 / 0 | 0 | 0 | 409 / 409 |
| 3 (stdlib) | 731 | 0 | 75 (10.3 %) | **305 (41.7 %)** | 0 / 0 | 0 | 0 | 41 / 41 |

Same-manifest control (oracle tags only, one live listing of 8,174 eligible): 1,214 supported
without `ClassDef`, 1,799 with — so the jump is the classes, not manifest drift; the parser
then measured 1,801 on a listing 22 files larger, and tier 3 hit its forecast exactly (305).

Project **1.48×**, stdlib **4.1×**. The Project jump is smaller than the 3,047 "class is the
first refusal" files suggested, for the same reason as P5: first ≠ only. Application code
behind a class is full of f-strings and annotations; the stdlib is not, hence the split.

Parser refusals now (first refusal per file):

| tier 2 (6,386 refused) | | tier 3 (426 refused) | |
|---|---|---|---|
| f-string | 2,385 | slice | 184 |
| slice | 1,264 | f-string | 91 |
| annotation (annotated assignment) | 957 | comprehension | 62 |
| comprehension | 891 | `yield` | 35 |
| generator argument | 360 | generator argument | 26 |
| dict comprehension | 207 | walrus | 8 |
| `async` | 161 | `async` | 7 |
| `yield` | 102 | dict comprehension | 7 |
| `for` in expression | 34 | annotation | 3 |
| `match` | 16 | `for` in expression | 3 |
| walrus | 9 | | |

Oracle-tag view of what *blocks* files (any position, tier 2 / tier 3 files): `JoinedStr`
4,758 / 183 · `comprehension` 4,258 / 243 · `Slice` 3,742 / 317 · `AnnAssign` 1,619 / 8 ·
`AsyncFunctionDef` 379 / 21 · `Yield` 359 / 85. **Sole** blocker (adding just this tag
completes the file): `Slice` 384 / 83, `AnnAssign` 132 / 0, `AsyncFunctionDef` 31 / 0,
`Yield` — / 5. Slices are the cheapest next jump; f-strings the largest.

### Corpus — per statement (`diff.py --corpus N --segments`)

The harvester now takes a supported class **whole** (one segment) and only descends into the
members of a class it cannot take whole, so segment counts are not comparable with P5 (a class
was N member segments, now 1); statement **nodes** and bytes are.

| tier | files with ≥ 1 segment | segments | statement nodes (all depths) | `ClassDef` nodes | bytes | parsed = exact | structural / location diffs | refusals | JS parity |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 5 | 74 | 231 | 0 | 18,912 | 5 / 5 | 0 / 0 | 0 | — |
| 2 | 7,888 | 143,230 | 572,549 | 7,441 | 44,197,516 | 7,888 / 7,888 | 0 / 0 | 0 | 406 / 406 |
| 3 | 723 | 19,908 | 112,864 | 2,048 | 9,013,880 | 723 / 723 | 0 / 0 | 0 | 41 / 41 |

**Gate: 0 structural and 0 location diffs on everything supported — met**, on 163,212 segments
/ 685,644 statement nodes (53.2 MB; P5: 52.6 MB), which re-runs the whole P4 + imports corpus
and adds **9,489 real `ClassDef`s**: 6,652 with bases, 74 with keywords (`metaclass=` etc.),
192 decorated, 53 classes nested directly in a class.

Not hit by the supported corpus: `**kwds` and `*bases` in a class header (0 occurrences) —
those rest on fixtures and fuzz only.

### Token counts (`ttok`, measured; caps not edited)

parser 12,450 (was 12,141) · nodes 4,861 (was 4,714) · operators 1,153 (was 1,155) ·
README 1,185. **`bend2/base.bend` reads 42,318 in this worktree — untouched.** (The brief
quotes 42,814 / 43,000; that is a newer `omen` than this base. Reading only, nothing edited.)

## Deviations

- `class A(x for x in y): pass` is a `SyntaxError` in CPython (a class header takes
  `arguments`, not a bare genexp) but this parser answers `Unsupported` ("generator or
  argument"), because the header reuses the call `Arguments` mode. The oracle check caught it
  in my `UNSUPPORTED` list; I removed the case rather than special-case the mode. It is a
  conservative refusal, never a wrong accept; it becomes a real `Syntax` decision when
  generator arguments land (the class path must then reject what the call path accepts).
- Whole-file "before" is the P5 report's measurement (1,215 / 8,110), not re-run; the
  same-manifest tag control (1,214 → 1,799) stands in for it.
- The tier-2 manifest is a live listing: 8,174 eligible at the control, 8,196 summed over the
  whole-file chunks, 7,888 segment files. < 0.5 % on the denominator; every chunk exited 0.
- Corpus ran as 200-file (tier 2) / 125-file (tier 3) chunks, 10–14 in parallel. One batch
  (tier-2 whole files 0–2,400) overran the 10-minute tool cap and was finished in the
  background by the harness; I collected its completion notice (12 / 12 chunks exit 0, 14 min)
  before aggregating. Latencies under parallel load are not reported as timings.
- `stmt_errors.bend`: `class A: pass → Unsupported` became `class A(B: pass → Syntax`.
- `stmt_classes.bend`'s expected wire is the C lane's output for a source that is also in
  `STATEMENTS`, where `diff.py` proves it equal to the oracle; the four lanes then agree on it.

## Uncertainties

- **Lexer cost on very large files** (not this lane's code, found while measuring):
  `Maestro/app/launch.py` (986 KB, 23,088 lines) takes **15.8 s idle in `PY_MODE=lex` alone**
  — the parser then refuses at line 36. P5 saw 3.1 s at 498 KB, so roughly quadratic in file
  size. `pydoc_data/topics.py` (parsed, exact) took 17 s under load. No timeouts (30 s cap) yet,
  but a 2 MB file would fail-stop. Worth an owner look before the corpus grows.
- `--segments` does not descend into `def` bodies; classes nested only inside unsupported
  functions are covered by fixtures/fuzz, not corpus.

## Remainder (precise, in measured order)

1. **Slices** — sole blocker of 384 tier-2 + 83 tier-3 files (the cheapest whole-file jump),
   first refusal in 1,264 + 184.
2. **f-strings** — first refusal in 2,385 + 91; blocks 4,758 tier-2 files overall.
3. **Comprehensions / generator arguments / dict comprehensions** — 1,458 + 95 first refusals
   (and settles the `class A(genexp)` deviation above).
4. **Annotated assignment** — 957 first refusals, sole blocker of 132.
5. `yield` / `yield from`, `async`/`await`, walrus, `match`, `except*`, non-ASCII identifiers.
6. Upstream (unchanged): early exit in `Regex.exec.run`, then re-measure the P3 candidate;
   new: the hand lexer's superlinear cost on ~1 MB files.
