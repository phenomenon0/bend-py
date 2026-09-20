# Translator modes — faithful-verbatim, or the best Bend that keeps the structure?

Design note, lane `tdesign` (off `omen` @ `f134bfa7`), 2026-09-19. No production code. Reads
`plan-astra-v2.md` §4/§6 and the locked `parser-regex.md` §4; seeds the T1–T3 briefs.
Tags as in the plan: [M] measured/read here · [E] engineering call · [Q] for arbitration.

## 0. The answer in one paragraph

Neither pole. "Verbatim" is not a real option — Python statements have no Bend spelling, so every
translation is already a rewrite (`for`→fold). "Best Bend" is not a translation mode either — it
is a *second claim* stacked on a translation. So: **the translator is faithful, always, and it
emits one artifact whose meaning is the Python function's meaning on the declared contract.
"Best Bend" is an evidence-gated rewrite layer over that faithful IR**, where each step names
what it changed, what it preserves, and what proves it. Default off. Never silent. The faithful
output is never discarded: it is the specification every optimized output is judged against.

## 1. The spectrum

**① Semantics-faithful by construction — the floor.** Non-negotiable, already in plan §4:
evaluation order, short-circuiting (helper matches, never eager `Bool.pick`), first-on-tie,
early-return suppressing later body evaluation (Done/Continue state), declared value contracts
(ASCII, finite lists, ranged ints). Faithful means *observationally equal on the contract
domain*, including which inputs fail. It does not mean token-for-token resemblance.

**② Structure-preserving idiom — in plan.** `for` accumulator → fold; early-return loop → fold
over Done/Continue; `if` → `match`; `None` → `Maybe`; restricted doctest → closed equality law.
Rule for this tier: the mapping is **fixed per syntactic form and justified once**, in the
translator's SOUNDNESS row, not per program. A reader can put the Python and the Bend side by
side and match them node for node via source spans. No program-specific cleverness lives here.

**③ Verified-optimization — future; where "best Bend" lives.** Program-specific rewrites that
change cost shape, not meaning:
- *parallel folds* — a left fold becomes a balanced tree of parallel calls (`a b = f(x) g(y)`)
  when a law proves the combiner associative with an identity (and total on the contract);
- *views* — native Strings are two-word views, `take/drop/slice/trim/split` zero-copy [M,
  `lanes/strings-adaptive.md`]; ownership analysis (Lint **A**, Proven only inside the IR)
  decides where a `clone` can go and where a `String.copy` compaction should be added;
- *arena-friendly shapes* — accumulators over rebuilds, fused passes, no intermediate lists;
- *GPU-able maps* — `f!` over independent elements when `f` is uniform, pure and bounded
  (GUIDE: GPU wins on uniform numeric work, loses on divergent work).

The line between ② and ③: ② is a fixed homomorphism on syntax, provable once; ③ depends on a
*property of this program* (associativity, read-only use, independence) and so needs
per-program evidence. Anything needing per-program evidence is ③ by definition, however small.

## 2. Mode architecture

```
elaborate(AST, contracts) → TypedIR₀ ─ IR.verify ─ emit → faithful.bend      (default; T1–T3)
                               │
                 rewrite(IR₀, evidence[]) → IRₙ ─ IR.verify ─ emit → optimized.bend   (③, opt-in)
```

- [E] **One translator.** ③ is `IR → IR`, never a second `elaborate`. A different translator
  would fork the semantics floor; a rewrite layer inherits it and can only lose it visibly.
- [E] **Rewrites are named, closed, and individually gated.** Each rule = (pattern on IR,
  side-condition, evidence kind, SOUNDNESS row). No rule without all four. The emitted file
  carries a rewrite log (rule, source span, evidence id) as comments; `--mode faithful` output
  carries none. An optimized artifact with an empty log is byte-identical to the faithful one.
- [E] **Evidence kinds, in descending strength** — and the grade a step may claim:
  1. *Law checked by the Bend checker* against the defined fragment evaluator → **Proven**.
  2. *Verifier-recomputed analysis* (ownership/read-only, independence; the Lint.verify
     discipline: certificates are forgeable data, recompute against the actual IR) → **Proven
     on fragment**.
  3. *Judge-gated parity only* (faithful vs optimized agree on fixtures + generated inputs)
     → **Tested**, never Proven. Allowed, but labeled; a signature `law` is not a theorem.
- [E] **Failed evidence = step not applied**, reported as Unknown with the span. Never a
  fallback that silently half-applies, never a repair loop that weakens the side-condition.

### How `judge.py` grades, per mode

The plan's three claims stay separate (§6: checker acceptance ≠ empirical source parity ≠
semantic theorem status). An optimization adds a **fourth, separate** claim; it does not
strengthen or borrow from the first three.

| Claim | Faithful mode | Optimized mode |
|---|---|---|
| C1 checker acceptance (no holes/goals/unsafe, four lanes) | required | required, again, on the optimized file |
| C2 source parity (Python oracle vs Bend, fixtures + contract edges) | required | required, again — not inherited |
| C3 semantic theorem status (per SOUNDNESS row) | reported as-is | unchanged; ③ never upgrades C3 |
| C4 rewrite equivalence (optimized ≡ faithful on contract) | n/a | per step: Proven / Proven-on-fragment / Tested, with evidence id |
| C5 benefit (the point of optimizing) | n/a | measured, medians of seven warmed runs, per lane; no gain → step rejected |

[E] C4 is judged **Bend-vs-Bend** (faithful artifact as reference), so it needs no Python and
can use generated inputs far beyond the fixture set. C5 exists because an unprofitable rewrite
is pure risk: if it does not measurably help, it does not ship. The report line is a tuple, never
one PASS: `repo_of: C1 ok · C2 14/14 · C3 tested-fragment · C4 1 step Proven · C5 1.0× (rejected)`.
Harness self-test per plan doctrine: a deliberately unsound rewrite (non-associative combiner
parallelized) must be caught by C4.

## 3. The three demo targets

### T1 `normalize_stem` — `s.strip().lower().replace(" ", "-")` [M, `wiki.py:92–94`]
Faithful: `String.replace(String.to_lower(String.trim(s)), " ", "-")`, contract printable ASCII
+ six ASCII whitespace. Bend already reads like the Python; ② is the whole story.
Best-Bend could go further in two ways:
- *Fuse `lower` and `replace` into one per-char map* (one traversal, no intermediate string).
  Needs: both are char-wise maps on the contract (`" "`→`"-"` is 1:1 only because the needle is
  one char — side-condition on the literal) and `lower(' ') = ' '`, `lower(c) ≠ ' '` for c ≠ ' '
  so the order commutes. Closed finite domain (ASCII) → a checker law by exhaustion. **Proven.**
- *Parallel/GPU char map.* Needs independence (free once it is a map) — but strings here are
  tens of bytes; C5 will reject it. Record as "legal, unprofitable".
`trim` must stay outside the fusion: it is positional, not char-wise.

### T2 `repo_of` — longest matching slug, first on tie [M, `overview.py:15–23`]
Faithful: guard → `split('.',1)[1]` → left fold with `Maybe String` accumulator, strict `>` so
the first of equal-length matches wins.
- *Parallel reduce over `slugs`.* The combiner "longer wins, left wins ties" **is** associative
  with identity `None` — but it is **not commutative**, so only an order-preserving balanced
  split is legal; any reordering reduce breaks first-on-tie. Needs: law `assoc(pick)` + identity
  (provable: lexicographic max on (length, −index) restricted to order-preserving trees), and the
  fold body refactored to `map(match?) ∘ reduce(pick)` — that refactor is itself a rewrite step
  needing "the predicate does not read `best`" (syntactic, verifier-recomputed). This is the
  canonical ③ example: the floor's first-on-tie clause is exactly what the law must carry.
- *Hoist `s + '-'`*: Python rebuilds it per iteration; Bend can test `starts_with(tail, s)` then
  the next char, no allocation. Needs: `startswith(s+'-') ⇔ startswith(s) ∧ tail[len s]='-'`,
  a closed string law. **Proven**, small, arena-friendly.
- *Views/ownership*: `tail` is read by every iteration — in affine Bend the faithful fold must
  thread or clone it. Read-only analysis licenses threading one view. Note: this is forced by
  the target language, so part of it is ②, not ③ — see open question Q2.
- Honest C5 note: slug lists are ~tens of entries; parallelism will not pay. The proof is the
  showcase, not the speedup.

### T3 `fm_sources` — frontmatter `sources:` extraction [M, `synapse.py:77–87`]
Faithful: one lazy DOTALL search, `splitlines`, early-return loop (Done/Continue), `split(':',1)`,
slice `v[1:-1]`, comprehension with `strip().strip('"')`.
- *Replace the regex with two literal finds* (`"---\n"` at 0, then first `"\n---"`). Needs:
  equivalence of lazy `(.*?)` + literal tail to leftmost `find` — true for this pattern shape,
  provable against the R2 reference VM as a fragment law. High value (drops the regex dependency
  from the hot path), high proof cost. **Judge-gated first, Proven later** — and the R4 oracle's
  "earliest closing delimiter" fixtures are the exact regression set.
- *Early-return loop → `List.find` + continuation.* Needs nothing beyond ②'s Done/Continue
  soundness; arguably it *is* ② once `find` is an admitted fold form. Laziness matters: later
  lines must not be evaluated (they cannot fail here, so it is cost, not meaning).
- *Parallel map over the comma-split items.* Independent by construction; GPU-unprofitable
  (divergent string work, tiny N). Legal, rejected by C5.
- *View retention — the one optimization that points the other way.* Every returned item is a
  zero-copy view into the whole document [M: views pin their payload; `retain-8MiB-view` case in
  `lanes/strings-adaptive.md`]. Best Bend here may **add** `String.copy` on the results so a
  caller holding sources does not pin every file body. Meaning-preserving trivially; C5 measures
  retained bytes, not time. Python has no analogue — evidence that "best Bend" is not always
  "fewer operations".

## 4. Risks, open questions, arbitration

- **R1 Fidelity of failure.** `v[1:-1]` on `"["`, `split(...)[1]` guarded by an earlier test:
  the floor includes *which inputs raise*. Rewrites must preserve the failure set on the
  contract, or the contract must exclude it explicitly. Easy to lose in fusion.
- **R2 Contract narrowing as a cheat.** Any rewrite is "provable" on a small enough contract.
  Rule: ③ never edits the contract; it consumes the one T1–T3 fixed.
- **R3 Tested mislabeled as Proven.** Same forgery risk as Lint certificates; same cure
  (recompute; forged-evidence negative fixtures; C4 self-test above).
- **R4 Proof cost swamps the demo.** Plan §8.10 already flags underestimated proof cost.
  ③ must not block or delay T1–T3, which ship faithful-only.
- **R5 Readability.** Operator's "keeping the structure": an optimized artifact that no longer
  maps span-for-span to the Python loses the demo's legibility. Rewrite log mitigates; [Q] cap
  ③ at rewrites whose log fits beside the source?
- **Q1 [Q]** Is Tested-only (kind 3) evidence admissible in a shipped optimized artifact, or
  Proven-only? Recommend: admissible, labeled, excluded from any "verified" headline.
- **Q2 [Q]** Where do affinity-forced choices (thread vs clone `tail`) sit? Recommend: ② picks
  the single canonical safe form (clone-free threading when syntactically read-only, else
  clone); anything analysis-dependent is ③.
- **Q3 [Q]** Does the rewrite layer live in `translate.bend` (cap pressure, 4–7k forecast) or a
  sibling `optimize.bend`? Recommend sibling: keeps the floor's file auditable on its own.
- **Q4 [Q]** Is `for`→`List.find` ② or ③? Recommend ②, once, with its SOUNDNESS row.

## 5. Smallest first step (T3+1)

[E] **One rule, one target: `repo_of` `s + '-'` hoist** (`starts_with(s+'-')` → `starts_with(s)`
∧ next char). Why this one: closed string law the checker can discharge (exercises evidence
kind 1 end to end), touches no ordering (cannot break first-on-tie), measurable allocation delta
(C5 has something to say), and the rewrite log is one line. It forces the whole skeleton into
existence — rule 4-tuple, log, C4 Bend-vs-Bend judge, C5 measurement, unsound-rewrite self-test
— at the lowest proof cost.

**Second**, not first: the `repo_of` order-preserving parallel reduce — the headline example,
but it needs the map∘reduce refactor step and an associativity law over `Maybe String` with a
tie clause. Do it when the skeleton exists. **Not worth doing**: GPU maps on any of the three
targets (C5 rejects them; record as legal-unprofitable). **Until T3 lands: nothing.** T1–T3
briefs carry one added line each: *"faithful mode only; emit no program-specific rewrite; record
candidate ③ rewrites in the lane report, do not apply them."*
