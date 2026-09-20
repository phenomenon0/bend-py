# Translator lane T5 — cross-def facts (brief, 2026-09-20)

Branch `lane-translator-t5`, worktree `bend-work-translator-t5`, off `omen` @ `ac994157` (sync 2.0.17 + T4 + all reports in tree).

## The mission

T5 = **facts that cross a call boundary.** T4 made a module translatable; the wall it named (its report, deviation 4) is:

> *"`fm_sources`' result is `list[str]` and nothing more, so a caller that wants 'non-empty' or 'each item stripped' must re-derive it. A postcondition slot on `Sig`, recomputed at both ends, is the shape that fits the existing kernel."*

Build that slot.

## The shape (design freedom on details — the discipline is fixed)

- A **small, closed set of checkable postconditions** on def signatures — only kinds the kernel can recompute from the IR alone (non-empty, each-item matches a simple predicate, sorted, length bounds, ...). Pick a defensible first set and defend its closure; resist building a type theory.
- Carried in `Sig`; **recomputed at the callee end** (emission may rely only on what the kernel verifies) and **granted at the call site** by the existing call rule — the callee's postconditions enter the caller's fact environment as a new conjunct of the four T4 rules.
- Forged postconditions must be refusable — the witness/forgery pattern of L1–L4 and of T4's own tests applies.
- Every refusal keeps its span and names the repair, like every existing diagnostic.

## Acceptance

- `bash tests/translator/run.sh` green with **new rows**: a postcondition granted across a call; a forged postcondition refused; a caller whose control flow depends on a callee's postcondition (positive), plus its false-claim negative control.
- Extend the judge demo so **one real fact crosses a call** in the `source_stems` pipeline (e.g. each-item-stripped from `normalize_stem`'s map, or non-empty from `fm_sources`), with a labeled control where the claim is false and the kernel says so.
- T1–T4 emissions stay **byte-identical** where untouched (re-run the pins, do not re-pin).
- `docs/omen/lanes/translator-t5.md` in the house voice: rules, slices, fixture results, cap readings, deviations (numbered, like T4's).
- Battery: `bash tests/translator/run.sh` + repo gate `bun gates/repo.ts` clean. **Do not push.**

## Scope

`demos/python/**`, `tests/translator/**`, `docs/omen/lanes/**` only. `bend2/**`, `gates/**`, `tests/caps.sh` untouched unless a **measured, itemized** cap move is truly required (prefer not; report first).

## Optional tail (only if the core lands clean and early)

1. The optimizer's module door (C4 for whole modules) — T4 report item 1. Small.
2. Nothing else. Keep the tier honest.

## House notes

- Read `docs/omen/FLOW.md`, the T4 report and the sync report before deciding anything.
- Existing kernel rule lives in `translate.bend`'s `verify_in`; the postcondition grant is an extension there, not a new checker.
- Commit style: `integrate`-voice summaries with battery counts, like every lane.
