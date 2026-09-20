# Bend ⇄ Python — the Python bridge

**An exact CPython 3.11 parser and a verified Python → Bend translator, written in Bend** — with the analysis layers they grew around them: a safety lint, a proof-carrying optimizer, and a power-tools library. Every capability is measured against CPython itself; everything the translator cannot prove, it refuses — with the location of the refusal.

> Status: private working package, not announced. The suites run against a Bend checkout — see `docs/PACKAGE.md` for the lift checklist.

## The pieces

| layer | what | evidence |
|---|---|---|
| `python/parser.bend` | CPython-3.11-exact parser (lexer, unicode tables, f-strings) producing CPython's `ast` — field order and spans | corpus at ceiling: 8,466/8,466 project files, 731/731 stdlib, 0 structural + 0 location diffs vs `ast.parse`; `tests/parser` 108 groups |
| `python/translate.bend` | Python → Bend, tiers T1–T4 (one def → a whole module with calls); untrusted elaboration → **verify kernel** → emit; module calls granted by a kernel-computed rank | `tests/translator` 32 groups; five judge demos across four lanes with CPython as the oracle and byte-identical emission pins; two demos mined from a real project, sha256-pinned |
| `python/lint.bend` | L1–L4 safety kernels: imports, purity, totality, match coverage — claims are forgeable data, one bad entry refutes all | `tests/lint` 76 groups; semantics cross-check against CPython |
| `python/optimize.bend` | proof-carrying rewrites: faithful output stays byte-identical, every refusal is logged with its span | rule #1 `hoist_append`; C-lane 1.57× on the `repo_of` demo |
| `power/` | pure-Bend primitives held to a CPython oracle on four lanes (never in the language core) | `tests/power` |

## The method (why the numbers mean something)

- **Oracle differential** — CPython 3.11.15 is the reference for structure, locations *and* execution.
- **Trust zones** — elaboration is untrusted; the kernel recomputes every claim from the IR alone; emission happens only after verification.
- **Refusals are positioned** (`call g(...) is granted by no def ranked below at 2:11`) and are the design, not the failure.
- **Four lanes per specimen** — strict check, interpreter, emitted JS, emitted C — plus byte-identical emission pins.
- **Honest edges** — the translator is deliberately a subset of Python; `PASS: N, FAIL: 0` means every *named* capability has oracle-differential evidence, not that arbitrary Python works. The parser's scope is the CPython 3.11 grammar exactly; non-ASCII identifiers are deferred.

## Layout

```
python/     the bridge: parser, translator, lint, optimizer, tables
power/      oracle'd pure-Bend primitives
tests/      parser · lint · translator · power suites + the corpus wiring
docs/       lane reports (the versioned history) + BOUNDARY (ownership) + PACKAGE (the one-pager)
```

## Running today

The suites expect to run inside a Bend checkout (they compile with the repo's own `bend`). The standalone runner — `BEND_DIR` or a pinned binary — is the first item on the lift checklist in `docs/PACKAGE.md`.

## Provenance & licensing

- Parser corpus: external trees (project sources + CPython 3.11 stdlib); a public release must bundle a license-safe sample or document provisioning (see `tests/parser/diff.py`).
- Built on [Bend](https://github.com/bendlang/bend). The bridge is ours (`docs/BOUNDARY.md`); core Bend work lives in the fork, not here.
- License: TBD before public.
