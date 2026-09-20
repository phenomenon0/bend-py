# Lint lane — L3 report (fable, 2026-09-19)

Branch `lane-lint3`, worktree `bend-work-lint3`, off `omen` @ `c25afaec` (L1, L2, translator T2 included). Plan: `plan-astra-v2.md` §3 ("M after match
parsing") and the L3 row. The plan is not in this worktree; it was read from `../bend-parser/plan-astra-v2.md`. Semantic pin: CPython 3.11.15.
Acceptance: `bash tests/lint/run.sh coverage` → **`Lint PASS: 20, FAIL: 0`** (3:01 wall).
Regression, run after the last code edit: `bash tests/lint/run.sh totality` → **`Lint PASS: 20, FAIL: 0`**, and `bash tests/lint/run.sh alias` → **`Lint PASS: 16, FAIL: 0`**.

## Slices

| slice | commit | content |
|---|---|---|
| kernel | `dc1d77a1` | `demos/python/lint.bend` (+505/−2 lines: the L3 section appended; header comment updated), `demos/python/SOUNDNESS.md` (M0) |
| fixtures | `abfd1110` | `tests/lint/coverage_{proven,missing,dead,unknown,forged}.bend`, `tests/lint/semantics.py` (L3 cross-check), `tests/lint/run.sh` (header comment) |
| report | this commit | `docs/omen/lanes/lint3.md` |

Untouched, as instructed: `bend2/**`, `gates/**`, `tests/caps.sh`, other namespaces, `translate.bend`. `lint.bend` imports nothing new, so
`translate.bend → lint.bend` stays acyclic. No pushes. `run.sh` needed no new code: its argument is a name prefix, so `coverage` selects
`coverage_*.bend`.

## Rules added

| rule | grades | what |
|---|---|---|
| `exhaustive` | Proven / Refuted / Unknown | the match statement at `here` ("line:col"): every value of its domain D reaches an unguarded case (**Proven**); some v ∈ D matches no case, guarded or not (**Refuted** `not exhaustive: v`); a forged claim (**Refuted** `certificate refuted: …`); outside M0, a value that reaches only guarded cases, or no certificate (**Unknown**) |
| `dead-case` | Proven / Refuted / Unknown | case n of that match: no value of D reaches its body (**Proven**); the claim fails the recompute (**Refuted**); no claim (**Unknown**). `coverage` prints only the Proven ones |

**Witness = claims, recomputed.** `Claim = Covers{here, value, arm} | Miss{here, value} | Dead{here, arm}`, with arms counted from 0.
A claim never carries the domain. `Lint.exhaustive(m, w, here)` and `Lint.dead_case(m, w, here, n)` recompute the following from the AST
(`module_sites`): M0 membership, D, and for every claim of the witness whether that claim holds. The checks are: a Covers value lies in D
and its arm is unguarded and matches it; a Miss value lies in D and no case matches it at all; a Dead arm is reached by no value that an
earlier unguarded case does not catch first. **One bad claim refutes the whole witness**, as in L1/L2. `Lint.coverage(m)` is untrusted
search. It proposes a Covers for the first unguarded match, a Miss when nothing matches, and a Dead per unreached arm. Then it grades only
through the two kernel entries, sorted by line/col/rule with L1's `le`.
Bend checks two new laws (`{==}`): `no_certificate_no_coverage` and `no_certificate_no_dead_case`. Both were mutation-tested: flipping the
no-certificate grade to Proven fails `book_valid` for each.

## The finite-domain boundary (M0; full text in `SOUNDNESS.md` § M0)

A domain counts as finite when **the kernel can list every exact value an A1 argument may hold, and name each by a literal whose Python
repr it computes without evaluating anything.** That gives three sources:

- `bool` → `True, False`. This holds only if nothing in the module binds `bool` (def, parameter, store, import, capture, star import).
- `None` → `None`.
- `Literal[…]` → its elements. This holds only if a top-level `from typing import Literal` (no `as`, level 0) is `Literal`'s only binder.
  An element is admitted if it is `True`/`False`/`None`, a decimal int, `-n` (with `-0` read as `0`), or a str literal whose body is
  printable ASCII without quote or backslash (repr `'body'`).

`X | Y` concatenates the domains. Everything else stays open and is graded Unknown: `str`, `int`, aliases, `Optional[…]`, a nested or empty
`Literal`, bytes/float/complex elements, prefixed or escaped strings.

The subject must be a parameter in `args.args` of the innermost `def`. That def has no defaults (a default may lie outside D: `dflt()`
falls through). Nothing else in the def binds the subject.

The patterns admitted are singletons (identity), literal values (`==`, so `case 1` matches `True` and `case 0` matches `False`), capture and
`_`, and `as` and `|` over those. Guarded cases never cover and never shadow, but they do defeat a Miss. Class, sequence, mapping, dotted
and float patterns are Unknown ("Unknown first", per plan).

A1 gains one sentence: a `Literal[…]` parameter holds a listed value with its exact type. A2 gains one sentence: `bool` and `Literal` are
bound only by the module's syntactic binders.

## Fixtures and results

Five specimens run in each of four lanes (check / interpret / js / c). The run also covers the shared wrong-`#|` control, the literal guard
(the generator splits sources into ≤400-char pieces), the unsafe/TODO grep and `semantics.py`. Outcomes were predicted before each first
run and matched; the only slip was a hand-counted line number that was one off. The `#|` blocks were recorded from interpreter output and
reviewed line by line.

- **`coverage_proven`** (full coverage; 9 × `exhaustive Proven`):
  - `bool`, `bool | None` (with `True | False`), and `Literal` with mixed quotes;
  - `_` after an explicit case (wildcard covers), and `case 1`/`case 0` on `bool` (equality overlap covers);
  - `Literal[-1, 0, 1]` with `-1 | 0 as small` and a capture;
  - `(None as n)` over `Literal["a"] | None`;
  - an outer and an inner nested match.
- **`coverage_missing`** (missing cases):
  - `Refuted not exhaustive:` `False` (the plan's negative), `'w'` and `None`;
  - `guarded`: Unknown, "True reaches only guarded cases";
  - `guarded_dup` (`True if c`, `True`, `False`): **Proven with no dead line**. This is the guarded-duplicate negative.
- **`coverage_dead`** (dead arms; each line is `exhaustive Proven` plus `dead-case Proven`):
  - a duplicate unguarded constant;
  - `True` after `1` (explicit equality overlap);
  - `_` after a full enumeration (wildcard after explicit);
  - a value outside D;
  - a guarded case shadowed by an earlier unguarded one;
  - `w.py`: `_` first, so `True` is dead. CPython refuses to compile this ("wildcard makes remaining patterns unreachable").
- **`coverage_unknown`** (open domains → Unknown, each with its own reason):
  - `str`, `int` (even with `_`);
  - a rebound subject, and a subject captured by an earlier `case b`;
  - a local, an unannotated parameter, defaults;
  - class, sequence, mapping, dotted (`math.pi`) and float (`1.0`) patterns;
  - `n.py`: `Literal = dict`, `bool = int`;
  - `s.py`: `from os import *`, which rebinds nothing here, but a star import may.
- **`coverage_forged`** (forged-coverage controls; honest source: `True if c`, `True`, `False`, `False`):

| case | grade | kernel reason |
|---|---|---|
| honest | Proven | every value of {True, False} reaches an unguarded case |
| omitted value | Refuted | no case claimed for False |
| wrong case | Refuted | claim at 2:4: case 2 does not match True |
| guarded case | Refuted | case 0 is guarded |
| outside the domain | Refuted | None is not in the domain |
| no such case | Refuted | no case 9 |
| forged miss | Refuted | case 0 matches True (a guarded case may be taken) |
| honest miss (`partial`) | Refuted | not exhaustive: False matches no case |
| no certificate | Unknown | no certificate |
| elsewhere only | Unknown | no certificate (all claims name 99:0) |
| stray claim | Refuted | claim at 99:0: no match statement there |
| changed case (arm 2 now `None`) | Refuted | case 2 does not match False |
| rebound subject | Refuted | claim at 3:4: b is rebound in the def |
| honest dead (arm 3) | Proven | no value of {True, False} reaches this case |
| live case (arm 2) | Refuted | False reaches case 2 |
| guarded duplicate (arm 1) | Refuted | True reaches case 1 |
| bad companion | Refuted | an honest Dead plus a guarded Covers: case 0 is guarded |
| changed dead | Refuted | False reaches case 3 |
| dead, no certificate | Unknown | no certificate |

**`semantics.py`** is independent of M0: it reads the domain off the *evaluated* annotation via `typing` and traces each call with
`sys.settrace`.
- Every `exhaustive` span must be an oracle `Match` in the file its report names, and every `dead-case` span an oracle case pattern.
- `exhaustive Proven` requires that a case body runs whenever the match runs, and that the printed domain equals the oracle's.
- `not exhaustive: v` requires that v is in the domain and that no body runs for it.
- `dead-case Proven` requires that the body never runs, or, for `w.py`, that CPython's own SyntaxError is observed.
- Controls: `shadowed(2)`, `fake('b')`, `dflt()`, `captured(True, 5)` and `untyped(2)` fall through every case, so each Unknown exclusion is
  necessary. `guarded(True, ·)` runs or skips its case depending on the guard, so neither Proven nor Refuted would be sound there.
- Mutation-tested: a false Proven, a live arm claimed dead, a wrong counterexample and a wrong domain each fail loudly (4 failures, then
  restored).
- Totals: 165 spans equal oracle spans (104 before L3), 60 coverage calls traced, 0 failures.

## Measurements

The gate reads bytes when a file is under its cap in bytes, otherwise ttok.

| file | ttok | bytes | cap |
|---|---|---|---|
| `demos/python/lint.bend` (1,332 lines) | 17,425 (was 10,759) | 53,798 (the gate's reading) | 64,000 |
| `demos/python/SOUNDNESS.md` | 3,732 (was 2,749) | — | 4,000 |
| `tests/lint/coverage_forged` / `unknown` / `dead` / `proven` / `missing` | 2,044 / 1,268 / 917 / 876 / 561 | — | 16,000 |
| `tests/lint/semantics.py` / `run.sh` | 3,574 / 1,274 | — | 16,000 |
| `docs/omen/lanes/lint3.md` | 3,870 | — | 16,000 |

`bun gates/repo.ts` with the report staged → `PASS: 45 / 45` (no new path rejected). `bash tests/caps.sh` → no `OVER` line (it does not list the lint files).
Walls: coverage 3:01, totality 3:01, alias 2:26. `translate.bend` imports `lint.bend`, so the translator battery was rerun after the last code edit:
`bash tests/translator/run.sh` → **`Translator PASS: 16, FAIL: 0`** (4:25 wall; repo_of 186/186, first_dash 168/168 + 2/2 doctest laws, normalize_stem 191/191).
**Not run:** the parser/strings/regex batteries and `gates/test.ts`/`perf.ts` (this lane changes no file they read; they need the mini cluster).

## Deviations (fail loud)

1. **Grade overload (a Rule 7 conflict, surfaced rather than averaged).** In L1/L2, `Refuted` means "the certificate is refuted; the
   property stays Unknown". For `exhaustive`, `Refuted not exhaustive: v` refutes the *property*, with a counterexample recomputed under
   A1. I kept the fixed four-grade set, disambiguated by message prefix, and wrote the exception into SOUNDNESS's Refuted row. Flagged for
   cleanup: add a distinct grade (for example `Falsified`) if a consumer ever needs to branch on the grade alone.
2. **M0 correctness is argued on paper, not mechanized**, the same status as T0/O0. The plan's phrase "law verifies coverage for every
   admitted value" is realized as the kernel's recompute per match: every v ∈ D needs a verified Covers claim (`uncovered`). It is not a
   universally quantified Bend law. The only Bend-checked laws are the two no-certificate laws.
3. **Binder counting is conservative.** Any string under a key other than `tag/id/attr/_raw/kind/type_comment` counts, so a keyword name
   `f(b=1)` or a later rebinding after the match makes the subject Unknown. A star import binds everything (added mid-lane after review;
   `s.py`).
4. **Open or unpinned domains are Unknown even with a wildcard.** `text(s: str)` with `case _` really is exhaustive. Only `args.args` is
   supported; positional-only/keyword-only/`*args` subjects, free variables of nested defs, class-body and `async def` matches are Unknown.
5. **D is not deduplicated.** `Literal["r", "r"]` prints `{'r', 'r'}` (typing dedups). Verdicts are unaffected.
6. **Claims are consulted per match.** A witness whose claims all name other matches is "no certificate" (Unknown), not Refuted
   (`elsewhere only`). A stray claim next to real ones refutes the whole witness (`stray claim`).
7. **Location key.** `here` is `"line:col"` of the `Match` (col 0-based, as in `_loc`), and arms count from 0. Two matches cannot share a
   start, so the key is unique.
8. **A review catch.** The mechanical rename `at` → `here` (a def name cannot be a pattern variable) damaged one message ("claim here
   2:4"). Review caught and fixed it before any `#|` was recorded.
9. **Evidence split.** `semantics.py` skips behaviour checks for `coverage_forged`, whose sources share spans; this is the L1/L2 forged
   convention. The evidence for `w.py` is CPython's SyntaxError, not a run.

## What L4 inherits

- `module_sites(m)`: every match of a module, with its recomputed D and M0 verdict, keyed by `"line:col"`. It is the natural per-def
  summary row ("`f` is exhaustive over D").
- `binders` and the module-level facts "`bool` unbound" and "`Literal` is `typing.Literal`". Cross-module summaries should replace "a star
  import binds everything" with the imported module's export list, and allow a `Literal` alias defined in another module (`Mode =
  Literal[…]`), which is Unknown today.
- For the translator: lower an `IMatch` without a fallback arm only on `exhaustive Proven`; on `Refuted not exhaustive: v`, emit the
  explicit fall-through. `dead-case Proven` arms may be dropped.
- The pattern: every kernel entry ships with its no-certificate law, and the fixtures ship with a forged table and a CPython trace
  cross-check.
