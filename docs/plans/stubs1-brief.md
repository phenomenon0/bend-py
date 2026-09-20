# Stub pass #1 — certify ten real functions (brief, 2026-09-20)

Branch `lane-stubs1`, worktree `bend-work-stubs1`, off `omen` @ `0efa5e7a` (post-T5).

## Why this lane exists

The coverage census (2026-09-20, the orchestrator): of `llm-wiki`'s 45 top-level
defs, **80% refuse on "missing or non-builtin annotation"**; the Project-tree
sample shows the same shape (71.7% annotation, 21% decorated/non-simple, 6%
outside the fragment). Reach is gated by **reviewed types**, not by exotic
syntax. The orchestrator's call, operator's instruction: agents do the stub
work. The optimization run comes AFTER this — it wants a bigger proven surface.

## Mission

Certify as many real `llm-wiki` tools defs as the fragment honestly allows.

1. **Triage fast.** Compile the translator once:
   `bun bend2/main.ts demos/python/translate.bend -o /tmp/tr` — then loop
   `/tmp/tr` with `PY_SOURCE`/`PY_DEF` per def (≈0.15 s each). Record every
   def's first refusal, by class.
2. **Stubs where defensible.** For the annotation class, write **reviewed type
   stubs** (the judge's `sig` mechanism; `fm_sources` is the precedent) and
   retry. A stub is a reviewed claim — if the types cannot be defended from the
   body and its call sites, refuse the def. Silence over guessing.
3. **Certify each success as a single-def judge demo**: source mined and
   sha256-pinned, fixtures (literal + edge + generated like the existing demos),
   four lanes, C1/C2/C3, and a one-character control that must refuse where a
   claim would break. **Target: 10 new certified defs** — fewer is fine, never
   padded. A certified def must pass C1 + C2 on all four lanes with its
   controls: no exceptions.
4. **One module**: 2–3 defs that call each other, with a T5 fact crossing if it
   arises naturally — if not, say so and skip it.
5. **The refusal table** is a deliverable too: every non-certified def with its
   class (annotation / decorated / outside-the-fragment / other), refined from
   the census's first-error view.

## Hard rules

- No `bend2/**` or `gates/**` edits; caps measured + itemized only if truly
  required (prefer not — new files should fit existing allow rows).
- Same discipline as T4/T5: sha256 pins for mined sources, byte-identical pins
  kept, positioned refusals, house commit voice, one slice per commit.
- Battery: `bash tests/translator/run.sh` + repo gate `bun gates/repo.ts` green.
- Report `docs/omen/lanes/stubs1.md`: the per-def outcome table, fixture
  counts, cap readings, deviations (numbered), and what the next stub pass
  inherits.
- **No push.**

## The point

Every certified real function is a durable artifact: checked types, totality,
four-lane execution, CPython-oracle fixtures, and a proof of what did not have
to be trusted. The refusal map is the audit. Ten honest certificates beat a
hundred "almost".
