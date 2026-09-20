# Lint lane — L1 report (fable, 2026-09-19)

Branch `lane-lint1`, worktree `bend-work-lint1`, off `omen` @ `f134bfa7`. Plan: `plan-astra-v2.md` §3.
Semantic pin: CPython 3.11.15. Acceptance: `bash tests/lint/run.sh totality` → **`Lint PASS: 20, FAIL: 0`** (3:07 wall).

## Slices

| slice | commit | content |
|---|---|---|
| L1 | `ce917a98` | `demos/python/lint.bend`, `demos/python/SOUNDNESS.md`, `tests/lint/{run.sh,semantics.py,totality_*.bend}` |
| report | this commit | `docs/omen/lanes/lint1.md` |

Untouched, as instructed: `bend2/**`, `gates/**`, `tests/caps.sh`, other namespaces' tests, the parser demo files. No pushes.

## Fragment T0 (full text: `demos/python/SOUNDNESS.md`)

Closed pure typed functions over exact built-ins:

- module = `def`s + docstring only; header undecorated, plain positional params, every param and return annotated in `str | bool | int | list[T] | T | None`;
- body tags allowlisted: `Return Assign If For Break Continue Pass Expr` / `Name Constant BoolOp UnaryOp(Not) BinOp(Add) Compare IfExp List Call`; nothing mutates (no `AugAssign`, attribute, subscript, method call, `while`, `try`, …);
- every loaded name is a param or local `Store`;
- a call is either a unique module `def` ranked strictly below the caller by the witness (acyclic; self/mutual recursion refused) or a contracted primitive (`len str bool sorted`, arity 1) whose contract is `pure && total`, at arity, **and whose name is bound nowhere in the function or module** — a shadowed builtin revokes the contract (spelling ≠ authority);
- `for` over an exact unmutated `str`/`list` is a fold: structural termination.

Guarantee: the call **terminates** (returns or raises) under A1–A4 (exact args, pristine module/builtins, contracts true of CPython, host). Anything dynamic, unresolved or outside the allowlist → `Unknown`.

## Verifier design

- **Kernel** `Lint.certificate(m, cs, w) -> String` (`""` = valid). The witness is only `List<Rank{name, rank}>`. For every witness entry the kernel recomputes from the actual AST/contracts: unique def exists, module closed, header typed, body scan (`scan` → `Fact = Bad{loc, why} | Calls{name}`), contract grants, and `rank(callee) < rank(caller)` for each resolved call. Any bad entry rejects the whole witness.
- `Lint.verify(m, cs, w, name) -> Diag`: no entry for `name` → `Unknown "no certificate"`; certificate valid → `Proven`; else `Refuted` with the kernel's reason (the *certificate* is refuted; the property stays Unknown).
- **Law** `no_certificate_no_proof`: `is_proven(verify(m, cs, [], name)) == False` for all `m, cs, name` — checked by Bend (`{==}`); `verify` consults the witness entry first so it holds by computation.
- **Untrusted search** `Lint.analyze(m, cs)`: round-based rank inference (`infer`), then each candidate goes through the same kernel; failures print `why_not` as `Unknown`. Also emits `unreachable` (R0: after `Return/Raise/Break/Continue` `Proven`; after `while True` `Unknown`) and `shadowed-builtin` (`Advisory`). Output sorted by (line, col, rule) via `List.sort`; rendering `path:l:c-el:ec rule Grade msg`.

## Fixtures and results

Five specimens × four lanes (check / interpret / js / c) + wrong-`#|` control + literal guard + unsafe/TODO grep + `semantics.py`.

Forged witness (`totality_forged.bend`, 14 cases; outcomes were predicted before the first run and matched):

| case | grade | kernel reason |
|---|---|---|
| honest | Proven | — |
| flipped ranks | Refuted | f: callee helper holds no smaller rank |
| omitted callee | Refuted | f: callee helper holds no smaller rank |
| changed callee (AST swapped under an honest witness) | Refuted | helper: unbounded loop While at 2:4 |
| cycle | Refuted | g: callee f holds no smaller rank |
| self call | Refuted | f: callee f holds no smaller rank |
| ghost def | Refuted | ghost: no unique def ghost |
| padded (honest + ghost entry) | Refuted | ghost: no unique def ghost |
| no certificate | Unknown | no certificate |
| granted (`len` under `contracts()`) | Proven | — |
| no contract (`cs = []`) | Refuted | f: unresolved call len at 2:11 |
| partial contract (`total=False`) | Refuted | contract of wait does not grant this call at 2:11 |
| impure contract (`pure=False`) | Refuted | contract of wait does not grant this call at 2:11 |
| assumed (false contract, both flags True) | **Proven** | on purpose: shows trust boundary A3 |

- `totality_shadow`: module `def len`, parameter `sorted`, local `str` → callers `Unknown "shadowed builtin len at 5:11"` (etc.) + one `Advisory` per binding; an honest-looking witness for `count` → `Refuted "count: shadowed builtin len at 5:11"`; the user's own `len` def and `fine` (unshadowed `bool`) stay Proven.
- `totality_unknown`: while, unresolved call, dynamic call, AugAssign, self/mutual recursion, decorator, missing annotation, method call, global name, keyword arg, wrong arity, open module (Import) → all `Unknown`; one in-fragment function stays `Proven`.
- `totality_reach`: after return/continue/break/raise-before-finally `Proven`; after `while True` `Unknown`; return inside `if` emits nothing.
- `semantics.py` (pinned CPython): 53 diagnostic spans equal the oracle's node spans; all 59 `Proven` calls on generated exact-builtin arguments terminated within 1 s; controls `spin` and `alias` (`ys = xs; for x in xs: ys += [x]`, graded Unknown) diverge.

## Measurements

| file | ttok | cap |
|---|---|---|
| `demos/python/lint.bend` (471 lines) | 5,741 | 64,000 |
| `demos/python/SOUNDNESS.md` | 1,811 | 4,000 |
| `tests/lint/totality_forged.bend` | 1,451 | 16,000 |
| `tests/lint/totality_unknown.bend` | 946 | 16,000 |
| `tests/lint/totality_shadow.bend` | 665 | 16,000 |
| `tests/lint/totality_reach.bend` | 599 | 16,000 |
| `tests/lint/totality_proven.bend` | 559 | 16,000 |
| `tests/lint/run.sh` / `semantics.py` | 1,251 / 1,175 | 16,000 |

Readings only: `bun gates/repo.ts` → `PASS: 45 / 45` (9.9 s; no path rejected — `tests/lint/**`, `docs/omen/**`, `demos/*/*.md` rules already exist); `bash tests/caps.sh` → no `OVER` line. Gate wall time 2:58 and 3:07 (two full runs), longest source literal 430 chars. **Not run:** the parser/strings/regex batteries — this lane changes no file they read.

## Deviations (fail loud)

1. **`Proven` is a paper-argued candidate, not a mechanized theorem.** Per plan §3 it becomes a theorem only once a fragment evaluator exists in Bend and termination is stated against it. Only K0 (`no_certificate_no_proof`) is checked by Bend. SOUNDNESS.md says so in the status column.
2. Closed-universe induction argument instead of type inference: annotations are checked syntactically; values are argued to stay in U = {str, bool, int, None, list of U}. No expression typing in the kernel.
3. Coverage (`match` finite-domain) deferred to L3; "resolve / effects / termination" exist as `scan`/`granted`/`certificate`, not as separately named passes; "finite summaries" = the rank witness + `Fact` list only.
4. Whole-witness rejection: one bad entry refutes every name in the witness (`padded`). Conservative, simple.
5. `shadowed-builtin` is keyed on contracted names, not CPython's full `builtins` list.
6. Guard in `tests/lint/run.sh` skips `#|` lines (the first gate run failed 20/1 on the 1,301-char *expected-output comment* of `totality_forged`; it is not a Bend literal). Parser fixtures never hit this because their `#|` lines are ≤ 9 chars. Alternative if unwanted: compare inside Bend and print a short verdict.
7. Specimens were generated once by an inline script; `#|` lines were recorded from interpreter output and reviewed line by line (forged outcomes predicted first).
8. `analyze` re-runs the kernel per function and per inference round: O(n²) module scans. Fine for fixtures; memoize facts when run on the corpus.
9. The first gate run exceeded the tool's 120 s foreground limit and was auto-backgrounded; it was waited on, then rerun in the foreground.

## Next

- L2: fragment evaluator in Bend + the termination proposition against it (turns T0 from candidate into theorem); alias/ownership advisories.
- Widen T0 measured against the corpus (count functions Proven / Unknown by reason before widening): `-`/`*`/`%`, `range`, tuple, subscript reads, `AugAssign` on non-aliased locals.
- L3 coverage, L4 cross-module summaries; wire `lint` into `demos/python/main.bend` CLI once a consumer exists.
