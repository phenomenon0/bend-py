# Optimizer lane — optimize-v1 report (fable, 2026-09-19)

Branch `lane-optimize-v1`, worktree `bend-work-optimize-v1`, off `omen` @ `707d0d9b` (T3 integrated).
Plan: `docs/omen/plans/translator-modes.md` tier ③, §2 (rule 4-tuple, evidence kinds, C4/C5) and §5 (the first step: the `repo_of` `s + '-'` hoist).
Acceptance: `bash tests/translator/run.sh` → **`Translator PASS: 28, FAIL: 0`**; its `repo_of` judge line is now
**`repo_of --optimize: C1 ok · C2 186/186 · C3 tested-fragment · C4 1 step Proven (law starts_append) · C5 not measured (--bench)`**, and with `--bench`
**`… · C5 c 1.57x · js 0.77x (rejected) · interpret 1.02x (rejected)`**.

## Slices

| slice | commit | content |
|---|---|---|
| optimizer + pins | `364b20e3` | `demos/python/optimize.bend` (rule #1, the law, the pipeline); `tests/translator/{opt_repo_of,opt_rules}.bend` |
| judge | `121ccef2` | `judge.py --optimize [--bench]` (C1/C2 again, C3 unchanged, C4, C5, controls); `run.sh` runs every demo with `--optimize` |
| report | this commit | `docs/omen/lanes/optimize-v1.md` |

Untouched, as instructed: `bend2/**` (so `bend.ts`, `main.ts`, `base.bend`), `gates/**`, `tests/caps.sh`, every other namespace, and `demos/python/translate.bend`: faithful output is byte-identical by construction, and the judge checks it again. No pushes.

## The pipeline

`optimize_as(source, sig, cs, name)` is `translate_as` with `optimize` in place of `emit`: lex → parse → scoped contracts → `Tr.elaborate`, and then

```
optimize(f, cs) = Tr.verify(f, cs) -> ok; Tr.verify(rewrite(ok), cs) -> better; framed(better, cs, log_of(ok))
```

- The kernel (`Tr.verify`, unchanged, reused) sees the faithful IR before any rule does and the rewritten IR after. A rewrite it refuses is an error, never a silent fallback to the faithful file. The probes below show this happening: before the span fix, the kernel refused two rewrites that were sound but badly named.
- `opt` rebuilds every one of the 15 IR constructors as it was, except where a rule fires. `steps` walks the same tree in the same order and writes one log line per site the pattern matches: Proven where the side-condition holds and the step was applied, Unknown where it did not hold and the step was not applied.
- `framed`: an empty log returns `Tr.render`'s text, byte for byte. Otherwise, line 1 names the optimizer instead of the translator, so the span map's line numbers stay right. The rest is the rendered file, followed by `# rewrites: rule, Python span, grade: evidence` and the log.
- `main` uses translate.bend's env protocol (`PY_SOURCE`, `PY_DEF`, `PY_SIG` through `Tr.stub`), so the judge drives both files the same way.

## Rule #1 — `hoist_append`

| part | text |
|---|---|
| pattern | `IPrim String.starts_with [x, IPrim String.append [y, z]]` (`matches`) |
| side-condition | `x` and `y` are `IVar`s (`fires`). Each is read twice after the rewrite. For a name that is a `+` share; for any other expression it would be a second evaluation (cost, and for an effectful future fragment, meaning). Recomputed from the IR at every site, with no certificate to forge |
| rewrite | `IBranch{starts_with(x, y), starts_with(drop(x, length(y)), z), False}`, an `and` that tests `z` only when `y` matched. The calls keep the original call's span. The new `drop`/`length`, the `False` and the branch take the append's span (deviation 1) |
| evidence | kind 1, **Proven**: `law starts_append` in `optimize.bend`, over all strings `t, s, p`: `starts_with(t, append(s, p)) == hoisted(starts_with(t, s), t, s, p)`, where `hoisted` is the helper the rewrite renders, as a def the law can name. By induction on `t, s` (`match t s`). The step case goes through `starts_step`, which takes the hypothesis as an argument because Bend has no mutual recursion, and `hoisted_cons`, which rests on `length_go`: `String.length`'s accumulator shifts by one. Checked by the checker whenever `optimize.bend` is loaded: laws in imported files are checked, which I confirmed with a falsified-law probe |
| log | `# hoist_append <py span of the call> Proven: law starts_append, demos/python/optimize.bend`, or `… Unknown: not applied, the string or its prefix is not a name (it would be evaluated twice)` |

**SOUNDNESS row** (the text for the table; not added to `demos/python/SOUNDNESS.md`, which is the lint lanes' file):

| id | rule | guarantee | theorem status |
|---|---|---|---|
| X1 | `hoist_append` (`Proven`) | at the logged site, the rewritten Bend term returns the same Bool as the faithful term for every pair of strings bound to `x`, `y` and every `z`. The optimized file therefore computes what the faithful one computes, and C2's claim for the faithful file carries over to the optimized one unchanged, under A4 | mechanized: `law starts_append` is checked by the Bend checker against Base's definitions of `starts_with`, `append`, `drop` and `length`. The judge also checks a per-artifact instance, `step`, which ties the law to the helper actually emitted. Under A4 (the runtimes are trusted), the native C/JS string primitives compute Base's definitions. That is an assumption, differentially tested by C2 and C4 in every lane, and not proven. The rule never touches C3: the faithful file's theorem status is the optimized file's |
| X1 | `hoist_append` (`Unknown`) | none. The site is left as the faithful file has it | — |

## The emitted Bend for `repo_of`

Pinned byte for byte in `tests/translator/opt_repo_of.bend`; the judge compiles the same text. Against the faithful file (`emit_repo_of.bend`), the diff is:

```diff
-# Faithful translation (tiers 1-2) of Python `repo_of` 1:0-9:15 by demos/python/translate.bend.
+# Optimized translation (tier 3) of Python `repo_of` 1:0-9:15 by demos/python/optimize.bend; the rewrite log ends the file.
@@
-def repo_of.or_7_11(_c: Bool, s: String, tail: String) -> Bool:
+def repo_of.and_7_40(_c: Bool, s: String, tail: String) -> Bool:
+  match _c:
+    case True{}:
+      String.starts_with(String.drop(tail, String.length(s)), "-")
+    case False{}:
+      False{}
+
+def repo_of.or_7_11(_c: Bool, +s: String, +tail: String) -> Bool:
   match _c:
     case True{}:
       True{}
     case False{}:
-      String.starts_with(tail, String.append(s, "-"))
+      repo_of.and_7_40(String.starts_with(tail, s), s, tail)
```

The span rows for the rewritten nodes follow. Every other row is the faithful row, 7 lines down.

```
# 17:6-17:66 <- py 7:24-7:48 Prim String.starts_with : Bool
# 17:25-17:60 <- py 7:40-7:47 Prim String.drop : String
# 17:37-17:41 <- py 7:24-7:28 Var tail : String
# 17:43-17:59 <- py 7:40-7:47 Prim String.length : Nat
# 17:57-17:58 <- py 7:40-7:41 Var s : String
# 17:62-17:65 <- py 7:44-7:47 Lit "-" : String
# 19:6-19:13 <- py 7:40-7:47 Lit False{} : Bool
# 26:6-26:60 <- py 7:40-7:47 Branch and : Bool
# 26:23-26:50 <- py 7:24-7:48 Prim String.starts_with : Bool
# 26:42-26:46 <- py 7:24-7:28 Var tail : String
# 26:48-26:49 <- py 7:40-7:41 Var s : String
...
# rewrites: rule, Python span, grade: evidence
# hoist_append 7:24-7:48 Proven: law starts_append, demos/python/optimize.bend
```

Each of these rows was checked by hand against both texts. The `+s, +tail` on `or_7_11` is the renderer's own share marking, because both names are now read twice; nothing in `optimize.bend` writes it.

## Judge output

`judge.py --demo repo_of --optimize --bench` (the faithful block first, unchanged from T3, then):

```
optimized             : demos/python/optimize.bend, 1 step(s) logged
  # hoist_append 7:24-7:48 Proven: law starts_append, demos/python/optimize.bend
C1 checker acceptance : ok (again, on the optimized file)
C2 source parity      : ok interpret 186/186 js 186/186 c 186/186 (again, vs the oracle; not inherited)
C3 theorem status     : unchanged, tested-fragment (tier 3 never upgrades C3)
C4 rewrite equivalence: ok log spans read back by ast: True; optimized == faithful in interpret, js, c on the 186 fixtures and 1000 more generated (seed 20260920): True; step law (starts_append at repo_of.and_7_40, stated against the emitted file): checked
controls              : ok (injected hole rejected by C1; helper without the '-' boundary rejected by C2, C4 parity and the step law; `s.strip() + '-'` not applied, logged Unknown at its span, code as faithful)
C5 measured benefit   : medians of 7 warmed runs, alternated, wall clock per process (startup included); the 186 fixtures per iteration; faithful -> optimized:
  c          20000 iterations  0.777 s -> 0.496 s  1.57x  gain
  js          5000 iterations  2.405 s -> 3.108 s  0.77x  rejected
  interpret     20 iterations  5.050 s -> 4.949 s  1.02x  rejected
repo_of --optimize: C1 ok · C2 186/186 · C3 tested-fragment · C4 1 step Proven (law starts_append) · C5 c 1.57x · js 0.77x (rejected) · interpret 1.02x (rejected)
```

`bash tests/translator/run.sh` runs `--optimize` on every demo. Its optimizer lines:

```
optimized             : ok no rewrite logged; byte-identical to the faithful file: True
normalize_stem --optimize: C4 no step · identical
optimized             : demos/python/optimize.bend, 1 step(s) logged
repo_of --optimize: C1 ok · C2 186/186 · C3 tested-fragment · C4 1 step Proven (law starts_append) · C5 not measured (--bench)
optimized             : ok no rewrite logged; byte-identical to the faithful file: True
first_dash --optimize: C4 no step · identical
optimized             : ok no rewrite logged; byte-identical to the faithful file: True
fm_sources --optimize: C4 no step · identical
Translator PASS: 28, FAIL: 0
```

What each claim checks (`optimized()` in `judge.py`):

- **No rewrite logged**: the optimizer's file must equal the faithful file byte for byte. This covers normalize_stem, first_dash and fm_sources. It is also the proof that the default path is unchanged: the same judge run emits both files.
- **C1** again, on the optimized file: no hole, open goal or `@unsafe`; strict check; interpret, js and c all run.
- **C2** again, against the CPython oracle on the same 186 fixtures (10 literal, 16 contract edges, 160 seeded), identical in all three lanes. Not inherited from the faithful run.
- **C3** is reported unchanged. Tier ③ never upgrades it.
- **C4**, Bend-vs-Bend, three parts:
  1. The log equals the expected line, with the span read back off the Python source by `ast`, independently of the parser.
  2. The optimized file equals the faithful file in interpret, js and c on the 186 fixtures and on 1,000 more generated inputs (seed 20260920, no oracle).
  3. The **step law**: a law file that imports the emitted artifact as `T` and `optimize.bend` as `O` must check.
     - `law bridge`: `O.hoisted(b, tail, s, "-") == T.repo_of.and_7_40(b, s, tail)`, by `{==}` in each branch of `b`.
     - `law step`: `starts_with(tail, append(s, "-")) == T.repo_of.and_7_40(starts_with(tail, s), s, tail)`, by `Equal.trans` of `O.starts_append(tail, s, "-")` and `bridge`.

     The judge finds the helper's name and parameter order in the emitted file: it is the one `def` the faithful file lacks.
- **Controls**, which must fail:
  - an injected hole, rejected by C1;
  - the unsound rewrite (the helper's `True` arm replaced by `True{}`: the `'-'` boundary dropped), rejected by C2 against the oracle, by C4 parity against the faithful file, and by the step law. For the law, the judge also requires the failure to be at `Location: bridge`, so a failed import cannot count as a rejection;
  - the negative control for the side-condition: the source with `s + '-'` replaced by `s.strip() + '-'`. The optimizer must log exactly `# hoist_append 7:24-7:56 Unknown: …` (span by `ast`), and its code and span map must equal the faithful translation of the same variant.

### C5 — the method and the numbers

Method (`bench()` in `judge.py`):
- One bench file per lane and artifact. Each iteration calls `repo_of` on all 186 fixtures and sums `length(result)`. The first argument is `String.take(pid, k)` with `k ≥ 1000 >` every pid's length, so the value is unchanged but no call can be shared across iterations.
- Iterations per lane: c 20,000, js 5,000, interpret 20. Each run takes seconds in its lane.
- Per lane: build both, run each once as a warm-up, then seven runs alternating faithful and optimized. Wall clock is taken around the whole process with `time.perf_counter`, so it includes startup (not measured separately). The figure is the median.
- The results must be equal (they are).
- A lane under 1.05× rejects the step there. 5% is the noise band I chose; the plan says only "no gain".
- 16 cores, load average about 5 from other work when the run started.

| lane | faithful | optimized | ratio | verdict |
|---|---|---|---|---|
| c | 0.777 s | 0.496 s | 1.57× | gain |
| js | 2.405 s | 3.108 s | 0.77× | **rejected** |
| interpret | 5.050 s | 4.949 s | 1.02× | **rejected** (flat) |

Why the lanes disagree (read from `bend2/comp.ts`, not measured separately):
- **C**: strings are views. `length` and `drop` are O(1), and `append` allocates a new string every iteration of the slug loop. The hoist removes that allocation.
- **JS**: `str_length` and `str_offset` are code-point loops, so `drop(tail, length(s))` costs two O(n) walks and a `slice`, where the faithful `+` and `startsWith` are native and cheap.
- **interpret**: dominated by the evaluator itself; the string ops are a small share.

A `String.get`-based variant (next char instead of drop) was tried during development and was worse on JS, so it was not pursued.

**Flagged for the operator: the C5 policy.** The plan's rule is "no gain → step rejected", per lane. The optimizer emits one file for all lanes, and this step gains on C and loses on JS. The judge reports the per-lane verdicts and does not fail on them, since C5 is a measurement, not a gate. Whether the step ships is left to the operator:
- (a) ship it, because C is the performance lane;
- (b) key the rule on the target backend, which needs a backend argument to `optimize`;
- (c) reject it everywhere unless every lane gains.

The judge supports any of the three without a change to the rule.

## Tests

- **`opt_repo_of.bend`** pins `O.optimize_as` on the `repo_of` source and stub: the whole emitted file, span map and log. It runs in all four lanes.
- **`opt_rules.bend`** checks the rule's edges row by row:
  - no match leaves the file byte-identical: normalize_stem, and a literal prefix `t.startswith('SRC-')`;
  - the side-condition fails and the code and span map stay the faithful ones, with one Unknown line and its span: the prefix is not a name (`s.strip() + '-'`), the string is not a name (`t.strip().startswith(…)`), and a literal head (`'a' + '-'`: the condition is names, not "cheap to duplicate");
  - two sites log in visit order: one Proven, one Unknown;
  - `t.startswith(t + '-')`, where x and y are the same name, is applied;
  - the two collision probes (below), shown whole.
- **`run.sh`** scans `optimize.bend` for `@unsafe`/`?TODO` too, and runs each demo's judge with `--optimize`.

The collision probes: `t.startswith(s + '-') and u` and `t.startswith(s + '-') if u else False`. My first version named the new branch by the call's span, so its helper was `f.and_2_11`. The Python `and` (a BoolOp, or an IfExp whose false arm is `False`) starting at the same column has the same helper name. Both were refused by the kernel: `two helper defs share a name at 1:0`. That is the kernel doing its job, but a sound rewrite should not be refused. Deviation 1 is the fix.

## Measurements (cap readings)

| file | bytes | ttok | cap (`gates/repo.ts`) |
|---|---|---|---|
| `demos/python/optimize.bend` (new) | 9,613 | 3,192 | 64,000 (passes on bytes) |
| `demos/python/translate.bend` | 82,750 | 26,952 | 64,000, ttok reading (unchanged) |
| `tests/translator/judge.py` | 39,421 | 11,277 | 16,000, ttok reading (was 26,611 / 7,515) |
| `tests/translator/opt_repo_of.bend` (new) | 6,580 | 2,667 | 16,000 (passes on bytes) |
| `tests/translator/opt_rules.bend` (new) | 7,147 | 2,561 | 16,000 (passes on bytes) |
| `tests/translator/run.sh` | 4,307 | 1,362 | 16,000 (passes on bytes) |
| `docs/omen/lanes/optimize-v1.md` (new) | 20,495 | 5,847 | 16,000 |

Every new path is matched by an existing allow rule: `demos/<ns>/*.bend`, `tests/translator/**` and `docs/omen/**`. There was **no gate rejection**.

Gates before the last commit:
- `bun gates/repo.ts`: `PASS: 45 / 45`
- `tests/translator/run.sh`: `Translator PASS: 28, FAIL: 0`
- `tests/lint/run.sh totality`: `Lint PASS: 20, FAIL: 0`
- `tests/lint/run.sh alias`: `Lint PASS: 16, FAIL: 0`

## Deviations (honest list)

1. **The new branch and its helper take the append's span, not the call's.** With the call's span, the helper `f.and_<call>` collides with a Python `and` or `x if c else False` starting at the same position. The kernel refused both probes. The append's position cannot start another `and` node, because it is the first operand of the call's own argument. Cost: the `Branch and` span row points at `s + '-'` (`7:40-7:47`), not at the whole call. The two `starts_with` rows keep the call's span. The kernel's distinct-name check stays as the backstop.
2. **The shape generalizes the plan's.** The plan has `startswith(s) ∧ tail[len s] = '-'`; the rule has `starts_with(x, y) ∧ starts_with(drop(x, |y|), z)` for any `z`. That is the same step when `z` is one character, with no indexing primitive to add and a law over all `z`. It is not a different rule, so the "smallest adjacent rule" clause was not needed.
3. **C5 runs only with `--bench`**, not in `run.sh`. Timing on a shared machine is a measurement, not a pass/fail gate. The report's numbers are from `--bench`.
4. **C5's 1.05× threshold is mine.** The plan says "no gain → rejected" without a band.
5. **The step law is stated by the judge for this rule** (`hoist` in the demo entry: `tail`, `s`, `"-"`), not derived for any site in general. A second site or a second rule needs its own instance. The generic part is finding the helper and its parameter order in the emitted file.
6. **The SOUNDNESS row is text in this report**, not a row in `demos/python/SOUNDNESS.md`, which is the lint lanes' file.
7. **An Unknown-only log still changes the header.** A file whose only log lines are Unknown gets the optimizer's line 1 and the log, although its code is the faithful code. This follows the plan: failed evidence is reported, with its span. Only an empty log is byte-identical.
8. **`hoisted` duplicates the emitted helper as a def** so the law can name it. The per-artifact `bridge` law, checked by computation, is what ties the two together.

## What rule #2 inherits

- **The skeleton, one function per part of the rule 4-tuple:**
  - `matches` is the pattern and `fires` the side-condition;
  - `hoist` is the rewrite and `steps` the log line;
  - one `opt` walker, and verify → rewrite → verify, with the log as comments.

  A second rule adds a case to `opt` and `steps`, and one law.
- **Judge**: `--optimize` already does C1/C2 again, C3 unchanged, C4 (ast-read log spans, Bend-vs-Bend parity on 1,000 more inputs, a per-artifact law), the unsound-rewrite self-test, the Unknown control, and C5 per lane under `--bench`.
- **Evidence kind 1 costs two laws.** One is general, in `optimize.bend`, over a def that mirrors the helper. The other is a per-artifact bridge, by `{==}` per branch, stated against the emitted file.
- **Name new helpers by a position no other node of that kind can own.** The kernel's distinct-name check will catch you otherwise.
- **The plan's rule #2, the order-preserving parallel reduce over `slugs`:**
  - It needs the map∘reduce refactor as its own step. Its side-condition, "the predicate does not read `best`", is a kind-2, verifier-recomputed analysis.
  - It needs an associativity law for "longer wins, left wins ties" over `Maybe String`, with identity `None`: kind 1.
  - The IR has `IFold` and `IMap` but no reduce, and the kernel refuses `ICall`. The reduce needs either a new IR node, which means editing translate.bend with its faithful output kept byte-identical and re-judged, or a granted `IPrim` contract for a Base reduce.
  - C5 will likely reject it: slug lists are tens of entries, as the plan says.
- **The JS cost model decides string rules.** Any rewrite that trades an allocation for `length`/`drop` gains on C (O(1) views) and loses on JS (O(n) code-point walks). Settle the C5 per-lane policy above before rule #2 is measured.
