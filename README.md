# Bend ⇄ Python — the Python bridge

**An exact CPython 3.11 parser and a verified Python → Bend translator, written in Bend** — with the analysis layers they grew around them: a safety lint, a proof-carrying optimizer, and a power-tools library. Every capability is measured against CPython itself; everything the translator cannot prove, it refuses — with the location of the refusal.

> The suites run against the Bend fork commit named in `BEND_PIN`; `./setup.sh` fetches it. The package and its Bend travel as a pair.

## Two tiers

- **The translator is the product.** It compiles a verified subset of real Python into checked Bend: untrusted elaboration, then a kernel that recomputes every claim, then emission, then native C and GPU lanes. Code outside what it can verify is refused, with the position of the refusal.
- **The VM is the fallback, and a torture test for the compiler.** It runs any program in its subset as bytecode on a Bend stack machine. It is slower than CPython and does not try to compete with it. It holds the same oracle discipline, it is the widest workload Bend's emitter sees, and it has already found emitter problems that a small program never reaches: a 14 GB C emission, clang's bracket-nesting limit, and a silent merge hazard.

## The pieces

| layer | what | evidence |
|---|---|---|
| `python/parser.bend` | CPython-3.11-exact parser (lexer, unicode tables, f-strings) producing CPython's `ast` — field order and spans | corpus at ceiling: 8,466/8,466 project files, 731/731 stdlib, 0 structural + 0 location diffs vs `ast.parse`; `tests/parser` 108 groups |
| `python/translate.bend` | Python → Bend, tiers T1–T4 (one def → a whole module with calls); untrusted elaboration → **verify kernel** → emit; module calls granted by a kernel-computed rank | `tests/translator` 32 groups; five judge demos across four lanes with CPython as the oracle and byte-identical emission pins; two demos mined from a real project, sha256-pinned |
| `python/lint.bend` | L1–L4 safety kernels: imports, purity, totality, match coverage — claims are forgeable data, one bad entry refutes all | `tests/lint` 76 groups; semantics cross-check against CPython |
| `python/optimize.bend` | proof-carrying rewrites: faithful output stays byte-identical, every refusal is logged with its span | rule #1 `hoist_append`; C-lane 1.57× on the `repo_of` demo |
| `python/vm.bend` | the fallback tier: the house parser, then bytecode, then a stack VM; ints, bools, None, strings (escapes, `+`, `*`, ordering, `len`, indexing, slicing), `def`/recursion, `if`/`while`, `print` | `tests/vm`: 53 checks on four lanes plus refusal controls; `python/fuzz_vm.py`: 1,200 generated programs against CPython with zero findings |
| `power/` | pure-Bend primitives held to a CPython oracle on four lanes (never in the language core) | `tests/power` |

## The method (why the numbers mean something)

- **Oracle differential** — CPython 3.11.15 is the reference for structure, locations *and* execution.
- **Generated, not just curated** — the VM's fuzzer checks its contract on random programs: exit 0 means CPython's exact bytes, a refusal is the VM's own, and every lane agrees. It found a miscompile and three wrong refusals that no fixture reached.
- **Trust zones** — elaboration is untrusted; the kernel recomputes every claim from the IR alone; emission happens only after verification.
- **Refusals are positioned** (`call g(...) is granted by no def ranked below at 2:11`) and are the design, not the failure.
- **Four lanes per specimen** — strict check, interpreter, emitted JS, emitted C — plus byte-identical emission pins.
- **Honest edges** — the translator is deliberately a subset of Python; `PASS: N, FAIL: 0` means every *named* capability has oracle-differential evidence, not that arbitrary Python works. The parser's scope is the CPython 3.11 grammar exactly; non-ASCII identifiers are deferred.

## Layout

```
python/     the bridge: parser, translator, lint, optimizer, tables — and the VM tier
power/      oracle'd pure-Bend primitives
tests/      parser · lint · translator · power · vm suites + the corpus wiring
tools/      lift.sh — refresh from the fork, or --check for drift
docs/       lane reports (the versioned history) + BOUNDARY (ownership) + PACKAGE (the one-pager)
BEND_PIN    the fork commit this package is certified against
```

## Running (from a clone)

Needs: `bun`, `clang`, `git`, and CPython **3.11.15** as the oracle (the suites
refuse any other version). `tests/power`'s `assign` oracle also needs `numpy` and
`scipy`. The translator's mined demos read their pinned sources from the trees
they were mined from, so on another machine those 16 report missing files, and
the 40 in-repo items are the portable result.

```sh
./setup.sh                          # ../bend if it sits at BEND_PIN, else fetches the pin into .bend/
bash tests/translator/run.sh        # or tests/vm, tests/lint, tests/power, tests/parser
python3 python/fuzz_vm.py --n 300   # the VM's differential fuzzer (after tests/vm has built it)
```

`BEND_DIR=/path/to/bend ./setup.sh` uses your own checkout; off the pin it warns,
and with `BEND_STRICT=1` it refuses. `setup.sh` links `bend2/` from the checkout
and bridges the suites' historical `demos/python` path to this repo's `python/`.
The bridge is developed in the fork; `tools/lift.sh FORK_DIR` refreshes this
repo from it and rewrites `BEND_PIN`, and `tools/lift.sh --check` fails on drift.

The parser suite additionally needs a corpus and the CPython 3.11.15 oracle — see `tests/parser/CORPUS.md`.

## The tour

`tour/index.html` — one module checked end to end (a real fact crossing a call
is *recomputed* by the kernel and minted into the signature), the emitted Bend,
the refusals, and how to run everything. Single static file, no build step.

## Provenance & licensing

- Parser corpus: external trees (project sources + CPython 3.11 stdlib); a public release must bundle a license-safe sample or document provisioning (see `tests/parser/diff.py`).
- Built on [Bend](https://github.com/bendlang/bend). The bridge is ours (`docs/BOUNDARY.md`); core Bend work lives in the fork, not here.
- License: MIT — see `LICENSE`.
