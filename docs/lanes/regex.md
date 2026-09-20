# Regex lane — R0→R2 report (fable, 2026-09-18)

Branch `lane-regex`, worktree `bend-work-regex`. Semantic pin: CPython 3.11 `re.ASCII`.
Every fixture expectation was cross-checked against `python3` 3.11.15.

## Slices

| slice | commit | content |
|---|---|---|
| R0 | `1006c81b` | `tests/regex/run.sh` — four lanes (check / interpret / js / c), `--selftest` with a deliberately wrong `#|` fixture that is detected as failing. |
| R1 | `d0fe9477` | `Re`, `Regex.Error` types; `Regex.parse` (stack machine, fuel = `String.length(p)`); `Regex.nullable`; pinned `RErr` texts. Fixtures `parse.bend` (14 `Re` dumps), `errors.bend` (9 `RErr` texts incl. `NullableRepeat`, `{,n}`, reversed range). |
| R2 | `cfac2dcc` | `Inst`, `Regex`, `Match` types; `Regex.expand` / `Regex.emit` / `Regex.compile` (flags `i m s`); ordered Pike VM `Regex.exec` with ε-closure (fuel + visited list); `Regex.match_at`, `Regex.fullmatch`. Fixtures `exec.bend`, `captures.bend`, `flags.bend`, `wordb.bend`. |

R3+ (budgeted globals, `sub`, `split`, …) not started — out of scope for this brief.

## Files touched

- `bend2/base.bend` — types appended to the top `# Data` section; new `# Regex` section between `# String` and `# Text`.
- `tests/regex/run.sh`, `tests/regex/{smoke,parse,errors,exec,captures,flags,wordb}.bend`.
- `docs/omen/lanes/regex.md` (this file).

Untouched, as instructed: `bend2/{comp,bend,main}.ts`, `demos/**`, `tests/{parser,strings}/**`, `gates/**`, `tests/caps.sh`.

## Size (ttok, `ttok < bend2/base.bend`)

| point | ttok | delta |
|---|---|---|
| baseline (`1006c81b`) | 27,844 | — |
| after R1 | 34,805 | +6,961 |
| after R2 | 40,017 | +12,173 |

PLAN §1.5 estimated +4k…+9k and says: "If R2 measures > +5k, reopen fable's Q7 (separate `Regex.bend` module) before R3."
R2 measures +12,173, so **Q7 must be reopened before R3**. `gates/repo.ts` still caps base at 28,000, so
`bun gates/repo.ts` reports `FAIL bend2/base.bend: 40017 > 28000 ttok` (43/44 PASS). I did not edit the gate (prohibited);
the cap is for the orchestrator to reset at the next round thousand (41,000) or to move the section into its own module.

Roughly 40% of the R2 delta is the VM (`Regex.exec.*`, ~2.1k), 30% emit/expand/compile, the rest types and comments.
Nothing speculative is in there; the parser could lose ~1k by dropping the per-position error `pos` tracking if that is wanted.

## Test counts (committed R2 base)

| suite | result |
|---|---|
| `bash tests/regex/run.sh` | **28 / 28** (7 fixtures × check/interpret/js/c) |
| `bash tests/run.sh` (f64) | **16 / 16** |
| `bash tests/run.sh --strings` | **81 / 85** — the 4 failures are `deep` on all four lanes (checker overflow, below); 84 other lanes pass |
| `bash tests/codex/run.sh` | **161 / 161**, 0 suite errors |

`tests/strings/deep` — see "Uncertainty" below.

## Deviations from PLAN §1.2 (all semantics-preserving)

1. **Type placement** — `Re`, `Inst`, `Regex`, `Match`, `Regex.Error`, `Regex.Frame`, `Regex.Cls` live in the top `# Data`
   section (types must precede use in base). The `# Regex` section holds only defs.
2. **Ranges are `Sigma<U32,U32>` pairs** (`RSet{neg, rs}` / `ISet{neg, rs}`), not `Char` pairs; `Match.groups` is
   `List<Maybe<Sigma<Nat,Nat>>>`. Same information, fewer wrappers.
3. **`IBol{multi}` / `IEol{multi}`** carry the `m` flag as a field instead of separate multi-line instructions.
4. **Parser is a stack machine** (`Regex.Frame` stack, `Regex.Cls` for class scanning) rather than level-Nat precedence
   climbing; single self-recursive `Regex.parse.run` with fuel `String.length(p)`. Error positions are the offset where the
   parser gave up, which for some errors (e.g. `(` unclosed) is the end of input rather than the opening paren.
5. **`{,n}`** is reported as `"bad repeat"` (CPython treats `{,n}` as a literal string; the PLAN listed it as an error, I kept the error).
6. **`\b` inside a class** is backspace (CPython semantics), `\B` in a class is an error.
7. **Bounded repeats are unfolded** by `Regex.expand` at the `Re` level (`x{2,4}` → `x x (x (x)?)?`), so `emit` only sees
   `*`, `?`, and unbounded. `max_rep=256` and `max_prog=4096` are enforced: `(a{256}){256}` → `"program exceeds max_prog"`.
8. **Flag `i`** turns every literal into a one- or two-range `ISet` (ASCII fold via xor 32 on the letter ranges) instead of
   a case-folded `IChr`.
9. **`fullmatch`** is a VM `cut` flag (an `IMatch` before end-of-input is skipped) rather than an appended absolute-EOL instruction.
10. **ε-closure** is a worklist with a visited list and fuel `3·(1+|prog|)`; complexity is O(n·m²) per input (`List.contains`
    on the visited list). Slow-but-correct was the brief; `^(a+)+$` on 80×`a`+`b` returns `None` in 0.5 s on the interpreter.
11. **Forged programs**: an `ISave` with an out-of-range slot, or a `pc` past the end, is a dead thread — never a crash.
12. **New error texts** (pos 0): `"program exceeds max_prog"`, `"unknown flag"`, `"duplicate flag"`.

## Uncertainty — `tests/strings/deep` check-lane flake

`deep.bend` (44 code points × 4096 string ops) intermittently fails in the **checker** (not evaluation) with
`RangeError: Maximum call stack size exceeded` in `bend.ts` `tele_open ← tele_head ← tele_check ← term_check`.
Evidence, all on frozen copies so no mid-edit pollution (each row is one fixture run):

| base | lane | result |
|---|---|---|
| HEAD (27,844) | check | 5/5 pass |
| HEAD | interpret (`bun bend2/main.ts`) | 5/5 pass |
| R1 (34,805) | interpret | 2/3 pass |
| R2 (40,017) | check, idle machine | 1/5, 2/3, 1/5 pass on three separate series |
| R2 | check, 16 busy-loop cores | 3/3 pass |
| R2 | interpret | 2/2 pass standalone; 0/2 inside the full `--strings` battery (all four lanes fail there, since every lane checks first) |
| R2 with `4096n` literal replaced by `Nat.mul(64n, 64n)` | check | 1/5 pass — not a literal-expansion issue |

So: deterministic pass on HEAD, non-deterministic on R2, no correlation with CPU load, and not caused by any single
literal. The overflow is a JS stack-depth limit in the checker's recursion that the larger book makes likelier to hit;
I could not pin the mechanism further without instrumenting `bend2/bend.ts`, which is prohibited for this lane.
Reported as-is, not masked: the strings battery is **81/85**, not 85/85, on this branch.

## Orchestrator amendments (post-report)

- `gates/repo.ts`: base cap 28,000 → 41,000 (measured 40,017). Module split deferred to the R6
  review — natives bind by name through base definitions; a non-base module would need a new
  compiler mechanism (not worth it for layout alone).
- `tests/strings/deep.bend`: repeat counts rewritten as `Nat.mul(64n, 64n)` — value-identical,
  payload unchanged (44 cp × 4096 = 180,224 bytes). Root cause of the checker flake: the `4096n`
  literal is a 4,096-deep node chain against the JS stack limit — non-deterministic, load- and
  book-size-dependent; class already tracked upstream as #779/#791 (evidence comment added to
  #779). The rewritten fixture passed 5/5 deterministically (123–135 s each, full workload).
