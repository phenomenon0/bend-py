# R-lane #2 — base.bend back under its cap (fable, 2026-09-18)

Branch `lane-reduce2`, worktree `bend-work-reduce2`, off `omen` `8f782000`.
Only `bend2/base.bend` touched. Nothing pushed. Cap untouched (43,000).

## Numbers

| file | before | after | delta | cap |
|---|---|---|---|---|
| `bend2/base.bend` | 43,110 | **42,971** | **−139** | 43,000 — **held** (headroom 29) |

Diff vs `8f782000`: `+31 / −27` lines (the two alias defs and a re-wrapped comment add lines; tokens fall). No def deleted, none renamed, no law or
fixture touched, no comment's *why* dropped.

## What was trimmed — every edit is type-level or text-level

1. **`File.read_text` plumbing types written once** (−59, with 2). The two
   result types of the streaming decoder were spelled out 3× and 5×:
   `File.read_text.Raw()` / `File.read_text.Out()` now name them (the file's own
   `X.Y() -> Data` alias idiom, here `-> Type`). The public `File.read_text`
   signature stays spelled out, as every other effect's is. Three lines that
   only wrapped because of the long types are rejoined (they fit 80 cols now).
2. **strfix comments reflowed** (−5): same content, the two over-long lines
   wrapped back to the file's width, a few filler words gone.
3. **Internal pairs as `A & B`** (−46): `Regex.parse.set.head` returns
   `Bool & String` (was `Sigma<&2, &2, Bool, _ => String>`, 3×) and
   `Regex.parse.Num()` is `Nat & Nat & String`. Both are returned and
   destructured at once, never stored in a Data container — the same idiom as
   `String.cut`, `Regex.exec.adv/feed`, and strfix's own `Maybe<&2, Match> & Nat`.
4. **`Regex.scan.St()` absorbs its `Result`** (−34): every one of its 4 uses
   was `Result<&2, &2, Regex.Error, Regex.scan.St()>`; the alias now says so
   itself — exactly how `Regex.parse.State()` is already written.

## The no-semantic-change argument

- Edits 1 and 4 are alias (un)folding: definitionally equal types. Edit 3 moves
  two internal, immediately-destructured pairs from `&2` (Data) to `&1` (Type);
  the checker accepts every def, and types are erased.
- **Emissions are byte-identical vs `8f782000`**: 63/63 JS artifacts
  (tests/regex, strings, f64, base) and 40/40 emitted C sources (regex, strings,
  f64) — same sha256, same set of non-building fixtures before and after.
  Since no emitted byte moved, no lane's runtime behaviour can have.
- None of the touched aliases is named outside base.bend (grepped tests, demos,
  comp.ts, effs). `Regex.scan.Out()` **is** named by `tests/regex/budget.bend`,
  so it was left alone; the budget pins are untouched.

## Battery (serial, this machine)

| gate | result |
|---|---|
| `bun gates/repo.ts` | **PASS 45 / 45** (was 44 / 45) |
| `tests/caps.sh` | ok, base.bend 42,971 ≤ 43,000 |
| `tests/run.sh` (f64) | **19 / 0** |
| `tests/strings/run.sh` | **89 / 0** |
| `tests/regex/run.sh` | **49 / 0** |
| `tests/codex/run.sh` | **161 PASS, 0 FAIL, 0 suite errors** |
| `tests/parser/run.sh` | **76 / 0** |
| `python3 tests/strings/runtime.py` (ASan) | **FAILS — pre-existing, not this lane** (below) |

Not run: `gates/test.ts`, `gates/perf.ts` (mini cluster).

### ASan harness: red before this lane started

`runtime.py` aborts in the probe: `tests/strings/runtime.c:226`
`search_case: Assertion 'track_live == 0 && track_kmp_live == 0' failed`.
The harness does not read `base.bend`'s defs under test here, and the failure
is identical on untouched trees:

| tree | result |
|---|---|
| `ffaf5fb1` (before the reduce1 merge) | **passes** |
| `018961a2` (integrate lane-reduce1) | **fails**, same assertion |
| `8f782000` (this lane's base) | **fails**, same assertion |
| `lane-reduce2` head | fails, same assertion |

So it entered with R-lane #1's integration. Suspect (unproven): S2's
`str_scratch_free` in `str_search_close` — the probe counts live search scratch
and that is the block S2 rewrote. It is a comp.ts runtime matter, outside a
zero-semantic base.bend diet; left for the orchestrator to route.

## Floor

42,971 is where the provable-safe, idiom-conformant trims end. The task's
~42,900 aim was not reached; what remains was measured and declined:

| candidate | ttok | why not |
|---|---|---|
| fold `Regex.scan.spent` into `scan.got` | −25 | the checker forces a def per computed scrutinee, so the fold must write the span payment in both arms — duplication for 25 ttok |
| `Regex.Ranges()` / `Regex.Span()` inside the `type` decls | ~−70 | the pass is linear: the aliases would have to move up into the Types section, which holds no def today — a layout break |
| `Regex.scan.Out()` absorbs its `Result` | −8 | `tests/regex/budget.bend` names the alias as the payload |
| alias for `Result<…, List<&2, Match>>` | −19 | a new name for 4 internal uses |
| `Nat.add(2n, x)` → `2n+x` (2 sites), `parse.close` arm merge | −6, −11 | value-identical but moves emitted bytes; would forfeit the byte-identical proof |
| comments | ~−5 more | what is left carries the why; ours are 2.1k ttok over 172 lines and already terse |
| unwrapping String signatures | ~−12 | they follow upstream's 80-col wrap |

The strfix lines themselves (hunt target 1) had almost nothing to give: `walk`,
`run`'s extra arm, and `pay`/`spent` are each the shape the one-pass checker
demands. With 29 of headroom the next base.bend fix will trip the cap again;
the honest levers are the Types-section move (−70, a layout decision for the
operator) or the deferred `Regex.parse` rewrite lane — not more dieting.
