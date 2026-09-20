# Lane: runtime-refactor — `tests/strings/runtime.c` consolidation

Branch `lane-refactor` (off `omen` at 8008c163). Commits bf7df257, 2a2d17dc,
44564614, and this report. One file changed:
`tests/strings/runtime.c`. `bend2/bend.ts`, `bend2/main.ts`, `gates/**`,
`tests/caps.sh`, `runtime.py` and other namespaces' tests are untouched.

## Outcome

| | ttok | lines |
|---|---:|---:|
| before (union merge) | 8,939 | 593 |
| slice 1: scaffolding | 8,812 | |
| slice 2: byte tables, dispatch, comments | 8,500 | |
| slice 3: `str()`, `zero_live()` | **8,394** | 600 |

**The 8,000 target is missed by 394. 8,394 is the floor with quality held**, so
the file still needs the standing cap move in `gates/repo.ts` (any cap ≥ 8,400
holds it; the present 9,500 has 1,106 of slack). `bun gates/repo.ts` passes at
the standing cap (PASS 45/45); it would fail at 8,000. `python3
tests/strings/runtime.py` passes (ASan/UBSan, zero live), stdout byte-identical
to the baseline.

## What was consolidated

- `expect_bytes(e, s, text, len)` under `expect_text`; `roundtrip()` (the NUL
  case) is now one `expect_bytes` call in `main` — same three conjuncts
  (`n`, `memcmp`, trailing NUL), same `zero_live` after.
- `cells_at(e, xs, n, nar)`: the alloc/put/view triple shared by `cells()` and
  the `widths` wider-payload loop. `cells()`' static `turn` rotation is
  untouched and called in the same order, so every case gets the same width.
- `a_then_b(e, n)`: the two hand-filled `a…ab` payloads of `adversarial`.
- `pop(e, &xs)`: the two `ctr_take`/`spare_free` list pops in `acceptance`.
- `lcg(&x)`: the 64-bit LCG step written out three times in `stream_law`;
  same seed, same draw order, so the same 2,000 strings and cuts.
- `stream_check` compares through `expect_cells` (it was a hand copy of it:
  `len` assert + one `str_at_peek` assert per cell).
- `stream_run`: `was_need` was a second name for `had`; one variable.
- Boundary errors: six hand-written asserts → a six-row `edge` table, one
  assert per row (`len` + `memcmp` of all `len` scalars — the same conjuncts).
- `search_case`: the non-overlapping scan ran twice (count, then replaced
  text); now once, computing both. Pure C, before any runtime call, so the
  runtime call order is unchanged. `kmp = m > 1 && m <= n` named once.
- `abc`/`pin` byte tables as string literals (the form runtime.py's `cases`
  already uses for the same specimen): −90 ttok, same bytes (sized arrays,
  the 20-byte `pin` and 12-byte `abc` verified by the partition counts).
- `fault`: `ON(name)` for the 17-way `strcmp` chain; the guard snapshot is a
  `memcpy`. `main` reuses `ON` for the three must-die modes.
- `SNIL`, `ull`, `zero_live()` (a macro, so a failure still reports the call
  site's line), `str(e, "lit")` for the 20 literals whose length was counted
  by hand (a script checked each old length against the literal's `strlen`).
- Comments: the new families' headers kept (the partition law, the width
  law); restatements of the next line dropped; one wrong comment fixed
  (`copy allocates just a class-2 payload` — the assert says class 0).

## Coverage equivalence

Measured, not argued from reading. A harness (`/tmp`, not committed) builds
the probe exactly as runtime.py does, with `assert` redefined to count its
evaluations and an `atexit` dump of the tracked counters. Baseline vs. final:

    allocs=84416896 reads=3888788 kmp=28123 copy=579105 words=11085405 asserts=21611433

identical in every field, and identical for **each of the 85 fault runs**
(per-op, per-offset: allocs, reads, words, asserts). So the refactor performs
the same runtime operations with the same allocation/read/copy/KMP totals and
evaluates exactly the same number of asserts, on the main run and on every
injected fault. stdout is byte-identical: 4,437 oracle cases, the adversarial
read counts 548,856 / 1,097,720, the three Structural lines, 177,128
partitions, 84,416,896 allocations, 85 faults, and the JS lines.

Static assert sites went 93 → 72, fully accounted: 14 became `zero_live()`,
1 (`roundtrip`) and 2 (`stream_check`) moved into `expect_bytes` /
`expect_cells`, 5 boundary sites became 1 looped site. No conjunct was dropped.

Mutation spot-checks on the consolidated paths, each killed: an `edge` row's
expected scalar; an `edge` row's FFFD; `stream_check` length; the NUL
round-trip bytes; the fault bank guard; the merged scan's count. (One mutant
survived — `a_then_b` ending in `bb` — and is equivalent: the needle mutates
identically and is still found at `n - m`; the original had the same blind spot.)

No scenario was merged with another: I looked for genuinely redundant checks
between the stream family, the width family and the older probes and found
none. The closest — the six boundary errors vs. the exhaustive sweep — are not
subsumed (0xac and 0x82 are outside the 12-byte alphabet, and they pin absolute
scalars where the sweep only compares against `io_str`), so they stay.

## Behaviour notes (not coverage)

- `main`'s mode dispatch: any unknown 2-arg mode now returns 1 instead of
  running the suite, and `fault-*` is matched before the 2-arg modes.
  runtime.py's invocations (`fault-<op> <n>`, `raw-output`, `limit-pad`,
  `limit-repeat`, no args) behave identically — the full script passes with
  the same stderr checks.
- `adversarial` allocates text-payload, text-descriptor, needle-payload,
  needle-descriptor (was payload, payload, descriptor, descriptor). Same
  blocks, same counts; the search and its read bound are unaffected.

## Why 8,394 is the floor

What remains is scenario code, and it is C: `for (u32 i = 0; i < n; i++)`
alone is ~220 repeated tokens, `assert(str_peek(e, …)…`, `_take(e,
term_keep(e, …` and the 17 fault ops make up most of the rest. An n-gram scan
of the final file finds no repeated sequence whose extraction pays for its
helper: I costed `linear()` (the three payload-bound blocks), a shared
split-field walker, `nar_of`, `data_of` — each nets ≤ 0 once the definition
and its comment are counted. The remaining ways down are the ones ruled out:

- a `term_keep(e, text), term_keep(e, needle)` macro and joined statements
  (−60..−100): golf;
- cutting the ~800 comment tokens in half: they are the partition law, the
  width law, and the why of each ownership scenario — the load-bearing part;
- dropping the six boundary errors or a sweep: coverage.

Recommendation: set the `tests/*/*.(c|js)` cap to 8,500 rather than 9,500 if a
tight ceiling is wanted; 8,000 does not fit this file honestly.
