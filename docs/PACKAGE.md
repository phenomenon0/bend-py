# The Python bridge — package one-pager (2026-09-19)

## What this is

Everything Python-facing we have built on Bend: an exact CPython-3.11 parser, a
verified Python → Bend translator (T1–T4), a safety lint (L1–L4), a
proof-carrying optimizer, and the power-tools library. One story:

**Python in → exact AST → verified Bend out → checked → optimized.**

One bundle, four extractable seams.

## Why a bundle (and not four products)

- The pieces compose into one narrative and share one discipline (oracle
  differential, verify kernel, positioned refusals, byte-identical pins).
  Announcing four things dilutes four times.
- The seams stay real: the **parser** is standalone-valuable (exact CPython ASTs
  *without* CPython); the **translator** is the legible-to-outsiders piece;
  **lint/optimize** are the depth.
- If an audience ever wants one piece alone, it extracts cleanly.

## Ownership & destination

- Ours (Zone B of `docs/BOUNDARY.md`); **not upstream-bound**; offered to Bend
  only if they ask. Governance stays in the fork; this repo is the package.
- Depends on a Bend checkout: the fork's core (2.0.17 lineage + our
  strings/streaming/regex). The bridge never duplicates `bend2/**`.

## Launch checklist (before public)

1. ✅ **Standalone runner** — `setup.sh` (`BEND_DIR`, default sibling `../bend`)
   links `bend2/` and bridges `demos/python -> python/`; every suite runs from a
   plain clone.
2. ✅ **Corpus provisioning** — documented in `tests/parser/CORPUS.md`;
   `manifest.py` honors `PKG_TOOLS_DIR` / `PKG_CORPUS_TREE` / `PKG_FORBIDDEN_DIR`.
3. ✅ **License** — MIT (`LICENSE`); corpus stays unbundled, so no provenance
   headers are carried here (see CORPUS.md).
4. ✅ **Translator tour page** — `tour/index.html` (single static file, captured
   live from the lane: the checked module, the emitted Bend, the refusals).
5. ✅ **Name/visibility** — **Bend-Py**; repo `phenomenon0/bend-py`, public
   (2026-09-21, operator's word).
6. ✅ Two upstream `bend.ts` bugs filed: bendlang/bend#914, #915.

## Versioning

By lane reports (`docs/lanes/**` — the complete T/P/L/optimize history) plus the
fork commit the lift was cut from.
