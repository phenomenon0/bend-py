# Lint lane — L4 report (fable, 2026-09-19)

Branch `lane-lint4`, worktree `bend-work-lint4`, off `omen` @ `707d0d9b` (L1–L3, translator T3 included). Plan: `plan-astra-v2.md` §3 and
the L4 row ("Closed-module summaries after P5 | `bash tests/lint/run.sh modules`: missing/cyclic/impure dependency"), read from
`../bend-parser/plan-astra-v2.md`. Semantic pin: CPython 3.11.15.
Acceptance: `bash tests/lint/run.sh modules` → **`Lint PASS: 20, FAIL: 0`** (2:41 wall, sharing the machine with another session's battery).
Regression, run after the last code edit: `totality` → **`Lint PASS: 20, FAIL: 0`**, `alias` → **`Lint PASS: 16, FAIL: 0`**, `coverage` → **`Lint PASS: 20, FAIL: 0`**.

## Slices

| slice | commit | content |
|---|---|---|
| kernel | `d909a66b` | `demos/python/lint.bend` (+457/−6 lines: the L4 section appended; `check_fn` split into `closed` + `member`; header comment), `demos/python/SOUNDNESS.md` (U0, A5) |
| fixtures | `efac0dda` | `tests/lint/modules_{clean,missing,cycle,impure,forged}.bend`, `tests/lint/semantics.py` (L4 cross-check), `tests/lint/run.sh` (header comment) |
| report | this commit | `docs/omen/lanes/lint4.md` |

Untouched, as instructed: `bend2/**`, `gates/**`, `tests/caps.sh`, other namespaces, `translate.bend`. `lint.bend` imports nothing new, so
`translate.bend → lint.bend` stays acyclic. No pushes. `run.sh` needed no new code: `modules` is a name prefix.

## Rules added

| rule | grades | what |
|---|---|---|
| `imports` | Proven / Refuted / Unknown | per module: every import resolves in the summary set, acyclically (**Proven**); a recomputed import path from it closes a cycle (**Refuted** `import cycle a -> … -> x`) or leaves the set (**Refuted** `missing module z via a -> … -> z`); a forged summary (**Refuted** `certificate refuted: …`); outside U0 or no certificate (**Unknown**) |
| `pure` | Proven / Refuted / Unknown | per def: T0 across the set, callees in other modules included: under A1–A5 a call terminates and runs no effect (**Proven**); a forged summary (**Refuted**); anything else (**Unknown**, with the first failing reason, qualified `mod.def`) |

**The unit and the summary.** A unit is `Mod{name, m}`: a parsed `name.py`, imported as `name`, rendered `name.py`. The summary set is the
list of units handed to the kernel. A summary is a list of forgeable entries, the L1 witness lifted one level:

- `Ranked{module, rank}`: the module is closed but for U0 imports, and each import names a unit of the set (and, for `from n import x`,
  a def x of n) whose own `Ranked` rank is **smaller**. Ranks order the import graph, so a vouched rank excludes cycles below it.
- `Pure{module, name, rank}`: `module.name` passes T0's conditions (`member`, the L1 kernel) with the module's imports as binders: `from n
  import x as a` makes `a(…)` a call of `n.x`, which needs its own `Pure` rank below this one. `Pure` also needs its module's `Ranked` entry.
  Module and pure ranks are separate keys (`mod` vs `mod.def`).
- `Path{mods}`: a counterexample. The kernel recomputes every edge (`x does not import y`) and requires the walk to end on a module it
  already passed (a cycle, possibly a lasso) or on a name outside the set.

`Lint.imports(ms, cs, w, mod)` and `Lint.pure(ms, cs, w, mod, name)` are the kernel entries. **Every entry of `w` is vouched, one bad entry
refutes all** (`vouch`, as L1–L3). Claims about the module are consulted first: none means `Unknown no certificate`. A vouched `Path`
refutes the property at the first import naming its second module; else the vouched `Ranked` proves it. A `Ranked` and a `Path` for the same
module cannot both vouch: the rank forces everything reachable to be ranked, in the set and strictly decreasing, which leaves a path
nowhere to repeat or exit. `Lint.modules(ms, cs)` is untrusted search: module-rank rounds (fuel = number of units), `trail` walks for the
unranked, then pure-rank rounds (fuel = number of defs), every verdict through the two kernel entries or with the recomputed reason as
Unknown. Output per unit in manifest order, sorted with L1's `le`.
Bend checks two new laws (`{==}`): `no_certificate_no_imports` and `no_certificate_no_purity`.

**Missing, cyclic, impure, in U0's terms.** Missing: an import names no unit (`missing module`), or no def of the unit (`text has no def
nope`, Unknown; deviation 4). Cyclic: a path back to a module it passed. Impure: a callee, through `from n import x`, that is not `pure`
Proven: an effectful contract (`print`, `pure: False`), an unresolved name, a module not closed (top-level effect), or a cycle.

## The module boundary (full text in `SOUNDNESS.md` § U0 membership, A5)

- **U0 imports:** `import n [as a], …` and `from n import x [as a], …`, level 0, n a single name, no `*`. Relative, dotted and star
  imports make the module not closed (Unknown), like any other non-def statement.
- **Closed but for imports:** after removing U0 imports the top level must pass L1's `closed` (defs and a docstring).
- **A5:** units are `name.py` files first on `sys.path`, not packages; `missing module z` means not in the set (z may well be installed,
  stdlib included).
- **Claims narrowed during review.** `closed` admits any FunctionDef, decorated or not, and a def statement evaluates its decorators and
  annotations at import. So `imports Proven` claims no missing or half-built module is hit, not that importing is silent or raises
  nothing, and `pure` covers the call, not the import. Both exclusions are in SOUNDNESS.

## Fixtures and results

Five specimens × four lanes (check / interpret / js / c), plus the shared wrong-`#|` control, the literal guard and `semantics.py`. Every
`#|` block was recorded from interpreter output and reviewed line by line against the predicted verdicts.

- **`modules_clean`** (app → words → text, app → text: a diamond): 2 × `imports Proven`, 4 × `pure Proven`, including a call through
  `from words import shout as yell`. `text` imports nothing, so it gets no `imports` row.
- **`modules_missing`**:
  - `app` imports `util` (not a unit): `Refuted missing module util via app -> util`, and `pure` Unknown with the reason;
  - `helpers → strings`, and `top → helpers → strings`: the transitive miss is reported on `top` with the whole path;
  - `lack` (`from text import nope`): Unknown `text has no def nope`;
  - `rel` (`from .text import twice`), `star` (`from text import *`), `dots` (`import text.twice`): Unknown `module not closed`.
- **`modules_cycle`**: `loop` (self), `ping ⇄ pong` (`from` cycle), `left ⇄ right` (plain `import` cycle), `fan → ping` (a lasso): every
  `imports` Refuted with its cycle, every `pure` Unknown `import of … is not certified (cycle or Unknown)`.
- **`modules_impure`** (contracts plus `print`, `pure: False`): `log.say` prints; `app.greet` calls it through `from log import say`, Unknown
  `callee log.say is not proven`; `app.shout` via `import log` is a dynamic call; `app.quiet` stays Proven next to them; `noisy` prints at
  top level, so its def and `page` (which imports it) are Unknown. `declared:` a summary claiming both pure → `Refuted certificate refuted:
  log.say: contract of print does not grant this call`; `no contract:` the same without the print contract → `unresolved call print`.
- **`modules_forged`** (manifest app, words, text, ping, pong, gone, lack, dup, noisy):

| row | grade | kernel reason |
|---|---|---|
| honest | Proven | every import resolves, acyclically |
| flipped ranks / omitted module | Refuted | words: import of text holds no smaller rank |
| cycle ranked | Refuted | ping: import of pong holds no smaller rank |
| missing ranked | Refuted | gone: missing module zz at 1:0 |
| lacking def | Refuted | lack: text has no def nope at 1:0 |
| ghost module / padded | Refuted | ghost: no unique module ghost (padded: an honest summary plus the ghost) |
| honest path out | Refuted | missing module zz via gone -> zz |
| honest cycle | Refuted | import cycle ping -> pong -> ping |
| forged edge | Refuted | path [app -> text -> app]: text does not import app |
| open path | Refuted | path [app -> words]: the path neither closes a cycle nor leaves the summary set |
| no edge / empty path | Refuted | path [app]: no edge / path []: empty path |
| no certificate (imports) | Unknown | no certificate |
| honest pure | Proven | terminates with no effect, through its imports |
| pure, no rank | Refuted | text.twice: module text holds no import certificate |
| flipped pure / omitted callee | Refuted | words.shout: callee text.twice holds no smaller rank |
| cyclic pure | Refuted | ping: import of pong holds no smaller rank |
| ghost def | Refuted | text.ghost: no unique def ghost |
| top-level effect | Refuted | noisy: module not closed: Expr at 1:0 |
| shadowed import | Refuted | dup.twice: no unique def twice (`from text import twice` and `def twice`) |
| no certificate (pure) | Unknown | no certificate |

**`semantics.py`** writes each specimen's units as `name.py` files to a temp dir on `sys.path` and never trusts U0. The graph comes from
`ast`, cycles from `graphlib`.
- Every `imports` span must be an oracle `Import`/`ImportFrom`, every `pure` span an oracle `FunctionDef`, of the unit the row names.
- `imports Proven`: everything below is a unit, the graph below is acyclic, the import raises nothing.
- `import cycle p`: p starts at the module, walks oracle edges, and the graph below has a cycle.
- `missing module z`: z is no unit, and importing raises `ModuleNotFoundError` for z.
- `pure Proven`: every sampled call terminates, prints nothing and keeps its arguments.
- Controls: ping's `from` cycle raises ImportError while left's plain `import` cycle imports fine, so cycles are checked on the graph, not by
  importing; `lack` raises ImportError, so the Unknown is a real miss; `app.greet` prints, and importing `page` prints `loaded`.
- Totals: 165 spans, 94 Proven calls, 28 ownership calls, 18 alias controls, 60 coverage calls, **59 module verdicts** (every row with a
  span; the two `?` rows have none), 0 failures.

**Mutations** (each run, then restored; all caught):
- Kernel, 17 (the first `no star` edit broke the parse and was redone, not counted): rank order, path edges, path cycle, pure needs a module rank, vouch all, closedness, in the set, def exists, qualify, import
  binders, unique module, path grade, pure vouch, no star, no dots, no dotted `from`, level 0. The level-0 mutation was first *missed*,
  because a separate non-empty-module check also rejected `from . import text`. That check was dead; I removed it and retargeted `rel.py` to
  `from .text import twice`, then re-pinned and reran.
- `semantics.py`, 9 forged expectations: a moved span on each rule, a shortened cycle, a Proven lasso, a Proven `lack`, the wrong missing
  module, a missing module relabelled a cycle, a Proven `log.say`, a Refuted clean import. Each failed loudly.

## Measurements

The gate reads bytes when a file is under its cap in bytes, otherwise ttok.

| file | ttok | bytes | cap |
|---|---|---|---|
| `demos/python/lint.bend` (1,783 lines) | 23,468 (was 17,425) | 72,515 | 64,000 |
| `demos/python/SOUNDNESS.md` | 3,997 (was 3,732) | 15,087 | 4,000 |
| `tests/lint/modules_forged` / `impure` / `missing` / `cycle` / `clean` | 2,511 / 1,035 / 905 / 781 / 680 | — | 16,000 |
| `tests/lint/semantics.py` / `run.sh` | 5,246 / 1,283 (was 3,574 / 1,274) | — | 16,000 |
| `docs/omen/lanes/lint4.md` | 4,670 | — | 16,000 |

`bun gates/repo.ts` with the report staged → `PASS: 45 / 45` (no new path rejected). `bash tests/caps.sh` → no `OVER` line (it does not list the lint files).
Walls: modules 2:41, totality 3:11, alias 2:36, coverage 3:16 (another session's battery shared the machine). `translate.bend` imports `lint.bend`, so the translator battery was rerun after the last code edit:
`bash tests/translator/run.sh` → **`Translator PASS: 20, FAIL: 0`** (7:01 wall; normalize_stem 191/191, repo_of 186/186, first_dash 168/168 + 2/2 doctest laws, fm_sources 194/194).
**Not run:** the parser/strings/regex batteries and `gates/test.ts`/`perf.ts` (this lane changes no file they read; they need the cluster).

## Deviations (fail loud)

1. **The fragment id was renamed mid-lane, X0 → U0 (Rule 7, surfaced).** `omen` gained optimize-v1 after this branch point, and its
   report proposes an `X1` SOUNDNESS row for `hoist_append`. Two X rows in one table would read as one family, so the uncommitted module
   fragment took `U0` (units; unused elsewhere in the repo). The X family stays free for rewrites.
2. **Grade overload, extended.** L3's `not exhaustive: v` refutes the property; `import cycle …` and `missing module …` now do too
   (SOUNDNESS's Refuted row lists the three). L3's flagged cleanup (a distinct `Falsified` grade) is still open, now with three messages.
3. **`n.f(…)` through `import n` is a dynamic call** (T0 admits `Name(…)` calls only), so `app.shout` is Unknown. Only `from n import x
   [as a]` resolves across modules. `import n` still counts as an edge, for missing and cycles.
4. **A missing def is Unknown, not Refuted.** `from text import nope` fails in CPython (ImportError, the `lack` control), but there is no
   `Lacks` counterexample entry, so the search reports Unknown and a `Ranked` claim over it is refuted as a forged certificate.
5. **"Missing" is relative to the set** (A5): `import os` in a unit is `missing module os`. A unit named like a stdlib module is the unit.
6. **Lassos count.** `fan → ping → pong → ping` is reported on `fan` as `import cycle fan -> ping -> pong -> ping` though `fan` is not on
   the cycle: importing `fan` still reaches a half-built module. `semantics.py` checks "a cycle below", not "a cycle through".
7. **Only the first claim per module is shown.** `imports` reports the first vouched `Path`, at the first import naming the path's second
   module; a module with several cycles gets one.
8. **`trail` is exponential** on dense import graphs (no visited set; `ponytail:` comment, memoize if it matters). Depth is bounded by the
   number of units.
9. **Claims narrowed after review** (above): decorators and annotations run at import, so neither rule claims silent or exception-free
   imports. `semantics.py` still checks that each Proven import raises nothing. That is stronger than the claim, and holds on these units.
10. **SOUNDNESS fit.** L4 needs about 270 ttok and SOUNDNESS had 268 left, so I trimmed, following L3's precedent. My own text was
    compressed. The K0 row became one brace form, with `no_certificate_no_ownership` folded in, and O0's separate sentence about that law
    went. Two sentences that the Exclusions already state were removed: A1's "Python does not enforce annotations; T0 says nothing about
    other arguments" and O0's "ownership certificates for mutating code … are a later fragment". Result: 3,997 / 4,000.
11. **Not done from L3's "What L4 inherits":** star imports still bind everything for M0, and a `Literal` alias from another module is still
    Unknown. U0 summaries carry ranks, not export lists or type aliases.
12. **Modules without imports get no `imports` row** in the search (nothing to claim); the kernel, if asked, answers at `name.py:?`.

## Closing note for the lint stream

L1–L4 give one discipline: forgeable certificates, a kernel that recomputes every condition from the AST, untrusted search in front, four
grades, sorted output, a no-certificate law per entry, a forged table and a CPython cross-check per rule. The four fragments are T0/O0
(total, ownership), M0 (coverage), U0 (closed-module summaries), plus the R0/S0/L0 reachability, shadowing and alias notes. What a future
slice would add, roughly in order of value:

- **A mechanized fragment evaluator** (plan §3). T0, O0, M0 and U0 are all argued on paper. A small-step evaluator for the fragment in Bend
  would turn each `Proven` into a checked theorem rather than a candidate.
- **Recursion certificates** (rank/countdown), deferred since L1; U0's module ranks are the same shape one level up.
- **Stdlib summaries**: contract modules (`os.path`, `re`) as trusted units, so "missing" can mean missing on the host and `pure` can reach
  through them. Today they are assumptions only via `Contract`.
- **Richer imports**: packages and `__init__`, relative and dotted imports, attribute calls through `import n` (an unshadowed module binder
  plus a def of n), and a `Lacks` counterexample for a missing def.
- **Import-time effects**: prove def statements inert (no decorators, annotations in U) so that `imports Proven` can claim a silent import.
- **Exports for M0**: a unit's export list replaces "a star import binds everything", and module-level `Literal` aliases become domains.
- **A distinct property-refuting grade** (`Falsified`) for the three counterexample messages; a memoized `trail`.
