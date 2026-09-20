# Lint lane — L2 report (fable, 2026-09-19)

Branch `lane-lint2`, worktree `bend-work-lint2`, off `omen` @ `8d040fb9` (L1 included). Plan: `plan-astra-v2.md` §3, L2 row.
Semantic pin: CPython 3.11.15. Acceptance: `bash tests/lint/run.sh alias` → **`Lint PASS: 16, FAIL: 0`** (2:22 wall);
regression: `bash tests/lint/run.sh totality` → **`Lint PASS: 20, FAIL: 0`** (3:01 wall, run after the last code edit).

## Slices

| slice | commit | content |
|---|---|---|
| L2 | `db57ff93` | `demos/python/lint.bend` (+359 lines), `demos/python/SOUNDNESS.md`, `tests/lint/alias_{flag,safe,boundary,forged}.bend`, `tests/lint/{run.sh,semantics.py}` |
| report | this commit | `docs/omen/lanes/lint2.md` |

Untouched, as instructed: `bend2/**`, `gates/**`, `tests/caps.sh`, other namespaces, the parser demo files. No pushes.
`run.sh` needed no new code for the subcommand: its argument is a specimen-name prefix, so `alias` selects `alias_*.bend` (header comment updated).

## Rules added

| rule | grade | what |
|---|---|---|
| `ownership` (O0) | Proven / Refuted / Unknown | O0 = T0 **and** no `is`/`is not` except against `None`/`True`/`False`. `Lint.own(m, cs, w, name)` is L1's kernel with one flag: the witness is still ranks only, and T0 membership **plus** the identity scan (`ident`) are recomputed for every witness entry, so all transitive callees are in O0. Law `no_certificate_no_ownership` checked by Bend (`{==}`) |
| `alias-mutation` | Advisory | a mutation through `b` (mutator-method spelling, item/attribute store or `del`, `+=`) while a distinct mutable alias `a` is read textually later or is a parameter. Message cites the alias binding and the later read |
| `alias-escape` | Advisory | `b` passed as a Name argument to a call that is neither a granted pure primitive nor an O0-certified def, under the same alias condition |
| `param-mutation` | Advisory | a mutation through a mutable parameter itself (the caller holds the alias) |

Mechanics (`Lint.alias(m, cs)`, untrusted, sorted by line/col/rule like `analyze`): one walk per top-level def yields `Ev = Edge | Bind | Mut | Esc | Use`;
may-alias classes are flow-insensitive over `b = a`, `b: T = a`, `b = a if c else d`, `b = a or d` (so **branch joins** merge for free);
**immutable reuse** is a greatest fixpoint: a name is skipped when every binding is an immutably annotated parameter (`str|bool|int|None`, A1) or an
expression of constants/operators over such names (`t = s; t += "x"` is silent); **repeated use** is never an event; a **move** (`c = b; c.append(..); return c`, `b` dead) is silent.
`analyze` is unchanged (no alias lines added to it), so every L1 `#|` block is byte-identical.

## The declared IR ownership boundary (full text: `SOUNDNESS.md` § O0)

For a function graded `ownership Proven`, under A1–A4, TypedIR may assume: **B1** no argument (or anything reachable from one) is mutated;
**B2** no reference to an argument survives the call except inside the result, which *may share* with arguments; **B3** sharing is unobservable inside O0
(no mutation, no identity test), so copy/share/move are indistinguishable and an affine IR may duplicate or move any binding.
Outside: everything not `ownership Proven` — including `total Proven` functions that test identity — and whatever a non-O0 caller does with a shared result. Never universal Python alias safety.

**What T1/T2 may now assume.** Gate on `Lint.own` (or the `ownership Proven` lines of `Lint.alias`), not on `total`: for those defs translate lists/strings with plain value semantics,
duplicate or move freely, and treat calls between them as pure. For every other def assume nothing about ownership: either refuse (Unknown → unsupported) or keep a faithful
reference model. Advisories are for humans; the translator must not read them as evidence in either direction.

## Fixtures and results

Four specimens × four lanes (check / interpret / js / c) + the shared wrong-`#|` control, literal guard (longest 431 chars), unsafe/TODO grep, `semantics.py`.

- `alias_flag` (must flag): plan's `b=a; mutate(b); use(a)` → `alias-escape`; `.append` / `b[0]=` / `+=` through an alias, `if` join, IfExp join, transitive chain → `alias-mutation`; container escape (`box.append(b)`) → `alias-escape` + `param-mutation`; `mutate` itself → `param-mutation`. The O0 helper `use` is `ownership Proven` and unflagged, and `use(a)` is not an escape.
- `alias_safe` (must NOT flag): repeated use, immutable reuse (`str`, `str | None`), `sorted()` copy then mutate, move, join of fresh lists, alias passed to an O0-certified def then the original read. Zero Advisory lines.
- `alias_boundary` (prints `analyze` then `alias`): `absent` (`s is None`), `share` (`[xs, xs]`), `echo` (`return xs`) `ownership Proven`; `same` (`xs is ys`), its `caller`, `interned` (`s is "a"`) are **`total Proven` but `ownership Unknown`**; `grows` (`xs += ..`) Unknown + `param-mutation`.
- `alias_forged` (8 witnesses, outcomes predicted before the first run and matched; after the slash the `total` grade of the same witness):

| case | ownership | total | kernel reason |
|---|---|---|---|
| honest | Proven | Proven | — |
| flipped ranks | Refuted | Refuted | top: callee echo holds no smaller rank |
| omitted callee | Refuted | Refuted | top: callee echo holds no smaller rank |
| changed callee (AST swapped) | Refuted | Refuted | echo: outside fragment: AugAssign at 2:4 |
| no certificate | Unknown | Unknown | no certificate |
| identity | **Refuted** | **Proven** | same: identity comparison observes sharing at 2:11 |
| identity callee | **Refuted** | **Proven** | same: identity comparison … (callee checked as a witness entry) |
| identity omitted | Refuted | Refuted | caller: callee same holds no smaller rank |

- `semantics.py` (pinned CPython): 104 spans equal oracle node spans (53 before); 94 `total Proven` calls terminated; **28 `ownership Proven` calls left every argument equal to its deep copy** (B1 evidence);
  18 alias controls: in `alias_flag`/`alias_safe` a def carries an Advisory **iff** it really mutates an argument on some generated input, and nothing in `alias_safe` does;
  control `same(xs, xs) != same(copy, copy)` shows the identity exclusion is necessary. The iff check can fail: its first version did (it expected the helper `use` to flag).

## Measurements

| file | ttok | cap |
|---|---|---|
| `demos/python/lint.bend` (830 lines) | 10,759 (was 5,741) | 64,000 |
| `demos/python/SOUNDNESS.md` | 2,749 (was 1,811) | 4,000 |
| `tests/lint/alias_flag.bend` / `alias_forged` / `alias_boundary` / `alias_safe` | 1,209 / 968 / 803 / 720 | 16,000 |
| `tests/lint/run.sh` / `semantics.py` | 1,265 / 1,829 | 16,000 |

`bun gates/repo.ts` after the commit → `PASS: 45 / 45` (8.9 s; no new path rejected). `bash tests/caps.sh` → no `OVER` line.
**Not run:** the parser/strings/regex batteries and `gates/test.ts`/`perf.ts` (this lane changes no file they read; they need the mini cluster).

## Deviations (fail loud)

1. **`ownership Proven` is a paper-argued candidate, not a mechanized theorem** — same status as T0; only the two K0 laws are checked by Bend. L1's "Next" listed a fragment evaluator for L2; the L2 plan row does not, and it was **not built**.
2. The plan says "ownership IR certificates are a later fragment". O0 is deliberately the no-mutation corner only: nothing that mutates can be `ownership Proven`. The "law concerns verified IR moves" is therefore not stated yet; B3 says moves are *unobservable* in O0, which is weaker.
3. L1 kernel signatures changed (additive flag `o` on `check_fn/entries/certificate/verdict/round/infer/totals`; `ann_ok` takes its name/tag lists). Public `verify/analyze/contracts/render/show` are unchanged; L1 fixtures byte-identical and green.
4. Whole-witness rejection carries over: one identity-testing entry refutes every name in an ownership witness (`identity callee`). `alias` search avoids it by never ranking such a def.
5. Advisory misses, by design and listed in SOUNDNESS.md: reads earlier in the same loop (`ponytail:` comment in `later`), element/attribute-path aliases, tuple targets, keyword/starred arguments, nested scopes (conflated), methods and module-level code. Noise: rebinding does not kill an alias; mutator-method *spelling* is trusted for advisories only.
6. `hazard` reports the first observable alias per event, not all of them (keeps one line per location and the order total).
7. `alias` is a separate entry point, not merged into `analyze`; merge when a CLI consumer exists. `reach` is recomputed per event (quadratic; fine for fixtures).
8. Specimens generated once by an inline script; `#|` lines recorded from interpreter output and reviewed line by line.
9. `semantics.py` silences Python warnings (`s is "a"` is a deliberate specimen).

## Next

- Fragment evaluator in Bend → turn T0/O0 from candidates into theorems.
- Ownership certificates for mutating code (unique-owner locals: `b = sorted(a); b.append(..)`), the first place a *move* law is non-trivial.
- Measure `alias` on the corpus (advisory counts by rule, O0 share of defs) before widening either side.
