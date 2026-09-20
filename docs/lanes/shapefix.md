# Lane shapefix — the parser fixtures' load-flake, fixed by shape

Branch `lane-shapefix` off `omen` @ `32dfd098`. Nine fixture files reshaped
(`1545e548`, `b902fbbc`); no compiler, runner, gate, cap, `fixtures*.py` or
`run.sh` touched. bun 1.3.4, 16 cores. Nothing pushed.

## Root cause

Same class as `deep-fix.md`, a different literal. A `String` literal is a
`Cons` spine, one node per character. Each parser fixture compares the wire
AST against one expected-JSON literal, and in the two flaking fixtures that
literal is the deepest in the namespace:

| fixture | deepest literal (chars = nested `Cons`) |
|---|---|
| `stmt_functions` | **3,439** |
| `stmt_walrus` | **3,362** |
| `stmt_comprehensions` | 2,513 |
| `stmt_slices` | 2,486 |
| `stmt_annassign` | 2,462 |
| `stmt_async` / `stmt_yield` | 1,914 / 1,900 |
| `stmt_fstrings` / `stmt_classes` | 1,808 / 1,743 |
| `stmt_assign` and everything else | <= 1,130 |

Trace from the original `stmt_functions.bend` (frames histogrammed,
unloaded machine, 1 of 3 probe runs):

```
OVERFLOW frames=6827
3410 at tele_check (bend2/bend.ts:1112)
3410 at term_check (bend2/bend.ts:3522)      <- check-ctr, one pair per Cons
   1 at term_wnf   (bend2/bend.ts:2901)
   1 at term_check (bend2/bend.ts:3505)
   1 at term_infer (bend2/bend.ts:3385)
   1 at term_check (bend2/bend.ts:3645)
```

Two checker frames per character, ~6.8k frames: on bun's JS stack limit. Whether
it fits depends on frame size (JIT tier at the time the spine is walked —
presumed, not measured), hence non-deterministic and worse under load. Every
lane type-checks the book first, so the failure rotates across `[check]`,
`[interpret]`, `[js build]`, `[c build]`. The `&&` chains (39 in `stmt_walrus`)
are not the driver: `stmt_functions` has none and flakes the most.

A synthetic `String.eq("a"*N, "b")` sweep (24 interpret runs per N, loaded):
0/24 for N <= 3,200, 1/24 at N = 3,400. The cliff is ~3,400 and soft.

## Fix

Every string literal over 1,200 chars in `tests/parser/*.bend` is now a `++`
chain of <= 512-char pieces, split on character/escape boundaries:

```
  String.eq(show(parse("...")), "{\"tag\":\"Module\", ... 512 chars" ++
      "... 512 chars" ++
      "...rest")
```

The checker now sees spines <= 512 deep under a `++` nest <= 7 deep; the
concatenation happens at evaluation time. Deepest literal left in the
namespace: 1,130 (`stmt_assign`, untouched; a third of the cliff, never flaked).

**Equivalence-preserving because:**
- mechanical split (a 20-line script, not kept in the repo — the allow list is
  a gate); per file, deleting every `" ++ "` seam from the new text reproduces
  the `HEAD` file byte for byte (asserted twice, by the splitter and by an
  independent regex over `git show HEAD:<file>`), so every source string,
  every expected string, every check and its order are identical;
- `main`'s type, the checks and the `#|` blocks are unchanged; outputs are
  byte-identical (all four lanes green for all nine files);
- the comparison still bites: altering one char in the last piece
  (`type_ignores` -> `type_ignoreX`) prints `False{}` for both fixtures.

`stmt_functions` and `stmt_walrus` are the fix proper. The other seven never
overflowed in measurement (below) but sat at 51–74% of a soft cliff, so the
same shaping was extended to them: the four the brief named (`async`,
`comprehensions`, `annassign`, `yield`) plus `slices`, `fstrings`, `classes`,
which are the same hazard by the same measure. No file split was needed.

## Rates

Overflow signature per frontend run; 32 runs per cell, 4 at a time, with 8 CPU
burners alongside (1-min load average 13–32 on 16 cores; other lanes were also
running). `check` = the `run.sh` check body, `interpret` = `bun bend2/main.ts f`,
`jsbuild` = `... -o out.js`.

| fixture | lane | before | after |
|---|---|---|---|
| `stmt_functions` | check | 1/32 | **0/32** |
| | interpret | 6/32 | **0/32** |
| | jsbuild | 0/32 | **0/32** |
| `stmt_walrus` | check | 0/32 | **0/32** |
| | interpret | 3/32 | **0/32** |
| | jsbuild | 4/32 | **0/32** |
| **both** | all | **14/192** | **0/192** |
| `stmt_comprehensions` | all three | 0/96 | 0/96 |
| `stmt_annassign` | all three | 0/96 | 0/96 |
| `stmt_async` | all three | 0/96 | 0/96 |
| `stmt_yield` | all three | 0/96 | 0/96 |
| `stmt_slices` | all three | 0/96 | 0/96 |

Not rated before or after: `stmt_fstrings`, `stmt_classes` (lane-checked only,
4/4 each). The c-build lane was not rated separately: it runs the same
frontend as jsbuild before emitting.

## Battery (on the tip)

| command | result |
|---|---|
| `bun gates/repo.ts` | **PASS: 45 / 45** |
| `bash tests/run.sh --strings` | **Strings PASS: 89, FAIL: 0** |
| `bash tests/run.sh` (f64) | **PASS: 19, FAIL: 0** |
| `bash tests/codex/run.sh` | **161 PASS, 0 FAIL; 0 suite errors** |
| `bash tests/regex/run.sh` | **Regex PASS: 49, FAIL: 0** |
| `bash tests/parser/run.sh` (full: lanes, probe, fixtures, fuzz, adversarial, corpus tier 1) | **Parser PASS: 104, FAIL: 0** (26 `.bend` x 4 lanes; exit 0, 0 overflow lines; corpus tier 1 5/5 exact) |

One run each, serial, first attempt, no retries.

## Residual risk

- The cause is the checker's recursion in `bend.ts` (off-limits; upstream
  #779/#791). Shaping moves the fixtures away from the cliff, it does not
  remove the cliff. Rule for new parser fixtures (P14's `match` included):
  **no string literal over ~1,000 chars; split with `++`.** Nothing enforces
  it; a one-line check in `run.sh` would, not added here to keep that file
  free for P14.
- The demo sources (`demos/python/*.bend`) are checked in the same book; their
  term depth was not audited beyond the fact that the 0/192 after-rate
  includes them.
- 0/32 per cell only bounds the per-run rate below ~9% (95%); the pooled
  0/192 bounds it below ~1.6%, against 7.3% measured before. The structural
  argument (depth 512 vs a ~3,400 cliff) is the stronger guarantee.
- The cliff moves with bun's version and stack size; a bun upgrade that
  shrinks it 3x would bring `stmt_assign` (1,130) into range.
