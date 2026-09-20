# Lane deep-fix — the `strings deep` flake, fixed at source

Branch `lane-deepfix` off `omen` @ `de84b938`. One fixture line changed
(`a9a90e1f`); no compiler, runner, gate or cap touched. bun 1.3.4.

## Root cause

`tests/strings/deep.bend` still carried one large `Nat` literal: the expected
line count of the split, `4097n`. `5ecf5227` had already rewritten the other
counts as products, but missed this one.

A `Nat` literal is unary: `4097n` parses to 4,097 nested `Succ` constructors.
The checker walks that spine recursively, two JS frames per `Succ`. Trace from
the original fixture (`Error.stackTraceLimit` raised, frames histogrammed):

```
FAIL frames=8076
4035 at tele_check (bend2/bend.ts:1112)
4035 at term_check (bend2/bend.ts:3522)      <- check-ctr: checks the ctr's fields
   1 at term_check (bend2/bend.ts:3505)      <- innermost: term_wnf(book, ty) under check-ctr
   1 at term_infer (bend2/bend.ts:3385)
   1 at term_check (bend2/bend.ts:3645)
   1 at book_valid (bend2/bend.ts:3755)
```

So: `term_check` (case `Ctr`, check-ctr) → `tele_check` → `term_check` …,
~8k frames deep, and the frame that finally tips over is the `term_wnf` call at
`bend.ts:3505`. At that depth the run sits right on bun's JS stack limit; whether
it fits depends on frame size — presumably (not measured) on which JIT tier the two functions happen
to be in when the spine is walked — hence non-deterministic, and worse under
load. It is the checker's recursion, in `bend.ts`, which this lane may not
touch. Every frontend phase (`[check]`, `[interpret]`, `[js build]`,
`[c build]`) type-checks the book first, which is why the failure rotated
across all four.

Same class as upstream #779/#791 (literal too large to expand).

## Fix

```diff
-   (Nat.is_eq(count.go(String.split(sample(), '\n'), 0n), 4097n),
+   (Nat.is_eq(count.go(String.split(sample(), '\n'), 0n), 1n+Nat.mul(64n, 64n)),
```

The checker now sees a term a few nodes deep; the value is computed at
evaluation time, where the runtime handles it without JS recursion over the
spine. **Payload unchanged:** `sample()` is untouched (44 × 4096 bytes), the
assertion is the same equality against the same number, and the fixture's
measured `#|` block is unchanged. The fixture still tests exactly what it
tested: split / words / to_upper over a 180 KiB string.

Levers not taken: bun `--stack-size` and a bounded retry in
`tests/strings/run.sh`. With the cause removed in the fixture neither is
needed, so neither was built; no rate is claimed for them.

## Rates

| what | before | after |
|---|---|---|
| frontend runs of `deep.bend`, overflow signature | **28/240** | **0/240** |
| check-phase trace probe on the original fixture, this session | 2/8 | — |
| full strings suite, serial, this session | — | **11/11 runs 85/0**, 0 overflow lines |
| `deep` rows across those 11 runs (`check`/`interpret`/`js`/`c`) | — | 44/44 ok |

The 240-run pair is the measurement recorded in `a9a90e1f`. Its per-phase
breakdown was lost when that session was cut off (network error); only the
totals survive, so only the totals are reported. Earlier history for context
(`strings-cont.md`): 11/60 and 16/60 build failures, suite red about every
second run.

The 11 suite runs were serial, on a machine under foreign load throughout
(1-min load average 5.6–15.2 at the end of each run) — the condition under
which the flake used to fire most.

Other suites on the tip: `bun gates/repo.ts` **44/44**, `tests/run.sh` (f64)
**16/0**, `tests/codex/run.sh` **161/0**, `tests/regex/run.sh` **49/0**.

Caps readings (unchanged by this lane): base 42,318 / 43,000; bend.ts 40,399 /
41,000; comp 80,198 / 81,000. Note: `tests/caps.sh` still lists base.bend
against a stale 28,000 and prints `OVER`; pre-existing, off-limits here, the
repo gate (43,000) is the one that decides. Flagged for the orchestrator.

## Residual risk

- 0/240 and 0/44 bound the rate, they do not prove zero; but the mechanism is
  gone, not shrunk: the deepest literal left in the fixture is `64n` (two
  frames per `Succ` → ~130 frames, derived, against ~8,000 measured at the cliff).
- The checker's recursion over literal spines is still there. Any fixture, in
  any namespace, that writes a literal in the low thousands will flake the same
  way. Probe this session (`def main() -> Nat: <N>n`, `bun bend2/main.ts`, 8
  runs each, under load): 3000n 0/8, 4097n (in the fixture) 28/240 ≈ 12 %,
  6000n 7/8.
- No upstream issue needed from us: the class is already tracked (#779/#791).
  If one is filed anyway, the trace above plus 28/240 at 4,097 is the datum.

## Sibling: the regex lane's OOM

Same root family. `regex-r56.md`: a forged row `ISave{4294967296n}` in
`runtime.py` — a unary 2^32 literal — had bun expanding it until the kernel
OOM-killed a 4 GB child. There the literal was big enough to exhaust memory;
here it was just big enough to graze the stack. One cause, two symptoms.

**Recommended test-authoring rule:** *big operands are computed, not literal.*
Any `Nat` above a few hundred is written as an expression (`Nat.mul(64n, 64n)`,
`1n+Nat.mul(…)`), never as an `Nn` literal — in fixtures and in generated rows.
