# Corpus provisioning — the parser suite

The parser's evidence is differential: every file in a corpus is parsed by this
parser and by the pinned oracle (CPython 3.11.15, `ast.parse`), and structural
and location diffs must both be zero. The corpora themselves are **not bundled**
— they are machine-local trees owned by their authors — so a clone supplies
its own and the suites hash every file before use (corpus code is never
imported or executed).

## Tiers (`diff.py --corpus N`)

| tier | what | default root |
|---|---|---|
| `1` | the llm-wiki tools tree | `~/Documents/Project/llm-wiki/tools` |
| `2` | a project tree, walked, Python files only | `~/Documents/Project` |
| `3` | the oracle's own stdlib | `sysconfig` of the running CPython |
| `lex` | tier 1 first, then everything else | same roots |

Exclusions, applied identically everywhere: symlinks, files over 1 MiB,
the Bend checkout itself (never parse the thing you live in), and
`.git`, `.venv`, `venv`, `node_modules`, `site-packages`, `_out`,
`__pycache__` directories.

## Pointing it at your trees

`tests/parser/manifest.py` reads three environment overrides (defaults above):

```
PKG_TOOLS_DIR      # tier-1 tools directory
PKG_CORPUS_TREE    # tier-2 walk root
PKG_FORBIDDEN_DIR  # a tree the walk must never enter (default: the bend checkout)
```

## The oracle pin

The suite's oracle is **CPython 3.11.15** — the version the parser is exact
against. `PY_MODE`-driven runs invoke the interpreter; the differential
comparison uses `ast.parse` from the same pin. A different CPython can be used
for exploration, but the recorded results (8,466 / 8,466 project files,
731 / 731 stdlib, 0 structural + 0 location diffs) are stated at the pin.

## The recorded result

`diff.py --corpus 1` and the full runs write `tests/parser/_out/corpus-*.jsonl`
manifests: one hashed row per file with its exclusion (if any). Those rows are
the evidence trail — keep `_out/` out of version control.
