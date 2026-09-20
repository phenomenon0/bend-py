# asanfix lane — `tests/strings/runtime.py` green again (fable, 2026-09-18)

Branch `lane-asanfix`, worktree `bend-work-asanfix`, off `omen` `5fedee84`.
Touched: `bend2/comp.ts` (2 hunks, −11 ttok), `tests/strings/runtime.py`
(hook retarget + one count). Nothing pushed. Caps untouched. The tracker's
invariant (`track_live == 0 && track_kmp_live == 0` at case end) is unchanged
and holds.

## Root cause — two breaks, the second masked by the first

**1. `018961a2` (reduce1 runtime dedup) — the reported abort.** The runtime
never leaked: `str_scratch_free` frees exactly what the old inline body freed.
What changed is the *shape* the harness instruments by text replacement:

| harness hook (runtime.py) | before `018961a2` | after |
|---|---|---|
| `k->table = 0;` → `track_kmp_live--` | sat behind `if (!k->table) return;` — fires only when a table was owned | **unconditional** in `str_search_close` — fires for table-less cursors too (needle ≤ 1 cell, or longer than the text) |
| `e.mem[k->table] = ALC_AT(e, k->cls);` → sticky-error scratch accounting | matched | text became `e.mem[l] = ALC_AT(e, cls);` inside `str_scratch_free` — `str.replace` **silently matched nothing** |

So the first `search_case` with no KMP table (`m <= 1`) decremented
`track_kmp_live` from 0, the u64 wrapped, and the case-end assert aborted.
The second hook's silent loss meant sticky-error scratch recycling was no
longer accounted at all.

**2. `8f782000` (strfix: "replace sizes its output once") — masked.** Merged
after the harness was already red, so never run under it. `str_replace_take`'s
counting pass did `str_search_close` + a second `str_search_open`: two table
allocations and two prefix-table builds per replace. `search_case` asserts one
build per op (`track_kmp_builds - builds == kmp`), and it is right to: the
second build is pure waste. It only surfaced once break 1 was fixed.

## Fix

- `str_search_close`: the zeroing moves inside the ownership guard —
  `if (k->table) { str_scratch_free(...); k->table = 0; }`. Same semantics
  (zeroing a zero was a no-op), and the release point is again the only place
  `k->table = 0;` executes, which is what the tracker counts.
- `str_replace_take`: the counting pass rewinds the cursor
  (`k.pos = k.matched = 0;`) instead of close + reopen. One table, one build,
  one free; a sticky error mid-count still reaches the single close at the end.
- `runtime.py`: the scratch hook now targets `str_scratch_free`'s recycle line
  (so it also covers the regex `P` scratch, the helper's other caller) and
  **asserts the hook text occurs exactly once** — a future dedup that moves it
  fails loud instead of dropping the accounting. `fault_ops` `replace=7 → 5`:
  replace now performs exactly 5 allocations (verified: offsets 0–4 each inject
  `ERR_HEAP`, offset 5 has no allocation left to fail). Every real allocation
  point is still injected; the tracker is not weakened.

## Proof

`python3 tests/strings/runtime.py` — exit 0, no aborts:

    runtime ownership + UTF-8: ok (84412268 allocations, zero live)
    streaming partition law: ok (177128 partitions, zero live)
    Device-style allocation failures: ok (83 injected cases)
    JS UTF-8 / Python oracle (1799 cases) / length diagnostics / JS partition law (180094): ok

(83 injected = 85 − the 2 replace offsets that no longer exist.)

| gate | result |
|---|---|
| `bun gates/repo.ts` | **PASS 45 / 45** |
| `tests/caps.sh` | ok |
| `tests/run.sh` (f64) | **19 / 0** |
| `tests/strings/run.sh` | **89 / 0** |
| `tests/regex/run.sh` | **49 / 0** |
| `tests/codex/run.sh` | **161 PASS, 0 FAIL, 0 suite errors** |
| `tests/parser/run.sh` | **76 / 0** |

Not run: `gates/test.ts`, `gates/perf.ts` (mini cluster).

## Token readings

| file | before | after | cap |
|---|---|---|---|
| `bend2/comp.ts` | 80,663 | **80,652** (−11) | 81,000 |
| `bend2/base.bend` | 42,971 | 42,971 | 43,000 |

## Left for cleanup (not this lane)

The other `c.replace(...)` hooks in `runtime.py` are still silent on a miss;
only the one that rotted got the occurrence assert. Same treatment is cheap if
another dedup lane touches those sites.
