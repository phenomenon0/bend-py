# Translator lane — T5 report (opus, 2026-09-20)

Branch `lane-translator-t5`, worktree `bend-work-translator-t5`, off `omen` @ `ac994157` (sync 2.0.17 + T4 + all reports in tree).
T5 = **facts that cross a call boundary.** T4's deviation 4 was the wall: *"No caller-side fact crosses a call, and no callee postcondition comes back."* A caller of `fm_sources` that wanted "each item is under the `sources:` key" had to re-derive it from text it cannot see. T5 puts a **postcondition slot on `Sig`**, recomputed at the callee end from the body alone and granted at the call site by the existing call rule.
Semantic pin: CPython 3.11.15. Acceptance: `bash tests/translator/run.sh` → **`Translator PASS: 40, FAIL: 0`**, ending with seven judge demos, each also with `--optimize`: **`normalize_stem: C1 ok · C2 191/191`**, **`repo_of: C1 ok · C2 186/186`** (+ **C4 1 step Proven**), **`first_dash: C1 ok · C2 168/168 · 2/2 closed doctest laws`**, **`fm_sources: C1 ok · C2 194/194`**, **`source_stems: C1 ok · C2 200/200`**, **`html_file_name: C1 ok · C2 189/189`**, **`page_tail: C1 ok · C2 187/187`** (all C3 tested-fragment; the six no-step demos, both modules among them, **C4 no step · identical**).

Untouched, as instructed: `bend2/**`, `gates/**`, `tests/caps.sh`, `demos/python/syntax.bend`, every other namespace. Faithful mode only, plus the brief's optional tail in tier ③: `optimize.bend` was touched where the widened record forced it, and then given its module door. No pushes.

## Slices

| slice | commit | content |
|---|---|---|
| T5 core | `b46a5b2e` | `demos/python/translate.bend`: the `Post` type, `sure`/`carries`/`carries_each`, the claim check in `verify_in`, the grant at `lets`, the item fact at `IMap`, the widened `gives`; `demos/python/optimize.bend` recomputes rather than carries |
| T5 tests | `dcb7d72d` | `refuse.bend` (+12 rows), `ir_forged.bend` (+12 rows), `emit_post.bend` (new pin) |
| judge | `7e671664` | `judge.py`: `keyed_sources` between the caller and `fm_sources`, and the false-claim control |
| report | `1a057b87` | `docs/omen/lanes/translator-t5.md`, and the brief it was executed from |
| module door (optional tail) | `26a1d920` | `optimize.bend`: `whole`, `optimize_all`, `rewrite_all`, `logs_of`, `framed` on a list; `opt_module.bend` (new pin); `run.sh` runs the `source_stems` module with `--optimize` |
| report, second pass | `66b281df` | the door, in the same report |
| real-program showcase | this commit | `judge.py`: `html_file_name` (mined, sha256-pinned) judged apart, then the `page_tail` module that consumes its carried literal, with two refusal controls; `run.sh` runs both |

## What changed

`demos/python/translate.bend` 1979 → 2141 lines. The three trust zones are unchanged (untrusted `elaborate*`, the `verify` kernel that recomputes from the IR alone, `emit = verify then render`), and so is T4's fourth untrusted stage, the rank. T5 adds no stage. It adds one field, one recompute and one conjunct.

- **The set, and why it is closed.** Two kinds:
  ```
  type Post is Data:
    PHas{text: String}    # the result, a String, contains this literal
    PEach{text: String}   # every item of the result, a list of String, contains it
  ```
  The closure argument is not taste. Enumerate the `pre` guards the contracts actually carry: `""` (no guard), `"literal"`, `"positive"`, `"Regex.compile"` — all static, decided from the argument's own text — plus `"Py.took"`, which is regex-local and born at a `re.search` let, and `"String.contains"`. **`String.contains` is the only guard a fact from another def can discharge.** So the only postcondition worth carrying is one spelled in that predicate, at the two result types the fragment has: a `str`, and a `list[str]` through its items. A third kind (non-empty, sorted, a length bound) would be a claim no guard can consume — a type theory, not a tool — and it would have to be carried, forged, refused and reported with nothing on the other end to use it. The set grows when a guard grows, and not before.

- **`post` on `Fn` is a CLAIM; `post` on `Sig` is a THEOREM.** A TypedIR is data, like a Lint certificate, so a hand-written `Fn` can claim anything. The elaborator proposes the claim (`with_sig` calls `sure(e, ret)` on the body it just built); `verify_in` recomputes `sure(body, ret)` and refuses any claim not in it; `fresh` mints **the checked claim** into the `Sig` the next def is verified against. Nothing that reaches a signature was not recomputed.

- **The recompute.** `sure(body, ret)` reads the result type and dispatches:
  - `carries(e)` — the literals this value *surely* contains, whatever the input. A literal carries itself; `String.append` carries both sides'; a branch carries only what **both** arms carry (`shared`); a `let`, a `return` and a `Maybe` pass through. **Every other node carries nothing.** Silence is safe by construction: the claim is only ever checked *against* this list, so an unmodelled node can only make the kernel refuse more.
  - `carries_each(e)` — the literals every item carries. A comprehension's items are its body's value, so `carries_each(IMap{…}) = carries(body)`. Blocks pass through, branches meet.

- **The grant is the existing call rule, one line.** `lets(name, val, loc, ss)` already turned `m = re.search(p, …)` into the `Py.took` fact. It now also turns `v = g(…)` into `facts_of(posts_in(ss, "g"), "v", loc)`. Those `Sig`s are the ones `fresh` minted, so only checked claims can enter a fact environment — and a call the ICall rule does not grant never reaches an emission, so a fact read off an ungranted call cannot outlive its refusal. Everything downstream is T1–T4 machinery unchanged: the fact is dropped at every binder, consumed through `granted` → `holds` → `gives`.

- **`Py.every` is a fact, not a primitive**, exactly like `Py.took`: `PEach{"k:"}` becomes `Py.every(v, "k:")` in the environment, and a body that *writes* `Py.every` is refused where it stands (`primitive Py.every is not granted by a contract`). Nothing renders it.

- **One fact survives one binder.** `items_of` is the only place a fact crosses a scope: at an `IMap`, a `Py.every(over, Q)` in scope becomes `String.contains(item, Q)` inside the body — every item of a list known to carry `Q` carries `Q`, and a comprehension's item *is* such an item. The match is by `show`, the same text the guard is read by, so the fact must be about the very value being iterated.

- **`gives` widened by one clause: substring transitivity.** A guard asking `String.contains(x, S)` is now discharged by a fact `String.contains(x, Q)` whenever `Q` contains `S`. That is why `keyed_sources`' `PEach{"stem:"}` discharges the caller's `split(':', 1)[1]`: the item is known to contain `stem:`, and `stem:` contains `:`. The widening only **adds** grants, so no program that emitted before emits differently — checked against every `refuse.bend` row that turns on a near-miss (`other guard`: `"-"` is not in `"."`; `guard rebound`: facts are dropped at the binder; `empty sep`: `solid` still gates the empty literal).

- **`optimize.bend` recomputes rather than carries.** `rewrite` rebuilds the `Fn` with `Tr.sure(b, ret)` on the **rewritten** body, not the old claim: a rule that reshapes a literal must not smuggle a claim past the kernel. (It would be caught — `verify` runs on the rewritten IR — but it would be caught as a lie, when it is really a stale fact.)

## The program

The judge's `source_stems` module grew a def between the caller and `fm_sources` (`tests/translator/judge.py`, the caller half of the labeled composite):

```python
def source_stems(text: str) -> list[str]:
    v = keyed_sources(text)
    return [normalize_stem(s.split(':', 1)[1]) for s in v]

def keyed_sources(text: str) -> list[str]:
    return ['stem:' + s for s in fm_sources(text)]
```

`('stem:' + s).split(':', 1)[1] == s` for **every** `s` — the split takes the first colon, which is the key's — so the module computes exactly what T4's did and all 200 fixtures keep their expected answers. What changed is what the kernel must know to emit it. Nothing in `source_stems` says a colon is there: the text it splits came out of a call. The emitted comprehension is

```
def source_stems.comp_3_11(_xs: List<&2, String>) -> List<&2, String>:
  match _xs:
    case Nil{}:
      []
    case Con{s, _rest}:
      normalize_stem(Py.after(s, ":")) <> source_stems.comp_3_11(_rest)
```

and the chain that grants it runs: `keyed_sources`' body is a map whose body is `String.append("stem:", s)` → `carries` = `["stem:"]` → `sure` at `list[str]` = `[PEach{"stem:"}]` → `verify_in` accepts the claim → `fresh` mints it into the `Sig` → at `v = keyed_sources(text)` the caller's environment gains `Py.every(v, "stem:")` → at the comprehension over `v` it becomes `String.contains(s, "stem:")` → `gives` discharges `Py.after`'s `String.contains` guard because `"stem:"` contains `":"`.

Change `'stem:'` to `'stem'` in the Python and nothing else, and the module does not emit at all. That is the judge's fourth control, below.

`tests/translator/emit_post.bend` is the new pin: four defs, both kinds of postcondition, 68 emitted lines and 33 span rows.

```python
def stems(text: str) -> list[str]:
    v = keyed(text)
    return [s.split(':', 1)[1] for s in v]

def head(text: str) -> str:
    k = one(text)
    return k.split(':', 1)[1]

def keyed(text: str) -> list[str]:
    return ['stem:' + s for s in text.split(',')]

def one(text: str) -> str:
    return 'stem:' + text.strip()
```

## The module door (the brief's optional tail)

`optimize.bend` took one def. `PY_DEF=""` — translate.bend's "the whole module" — reached `Tr.elaborate`, which wants a name, so a program could be judged (C1–C3) but not rewritten (C4). The door is `translate.bend`'s own, mirrored:

- **`whole(m, g, on, name)`** branches on `String.is_empty(name)` exactly as `Tr.whole` does: `Tr.elaborate_all` + `optimize_all` for a module, `Tr.elaborate` + `optimize` for a def. `optimize_as` and `main` are unchanged above it, so `PY_DEF` already meant this.
- **`optimize_all(fs, cs)` is `optimize` at module scale.** `Tr.ordered(fs, cs)` — the kernel's rank, each def verified against the signatures of the defs ranked above it — then `rewrite_all`, then **`Tr.ordered` again on the rewritten defs**. The rank is recomputed, not carried, which is the same discipline as the single def's second `verify` and the reason a rewrite that dropped a postcondition is refused *at the caller that reads it* rather than smuggled into the file.
- **`framed` now takes the list.** `Tr.render_all` and `Tr.titles` are what `translate.bend` renders a module with; line 1 is still one line — for one def or for four — so the span map's line numbers stand. `optimize(f, cs) = optimize_all([f], cs)`: `Tr.ordered` on a singleton *is* `Tr.verify`, and `fresh` against no signatures cannot fail, so the single-def file is byte-identical. `opt_repo_of.bend` and `opt_rules.bend` were re-run, not re-pinned.
- **The log is `logs_of`** — the defs' logs concatenated in **rank** order. A line names its site by the Python span, so the def it came from is not in doubt; `opt_module.bend` pins a module whose two sites log callee-first, which is not the source's order.
- **`run.sh` now runs `source_stems` with `--optimize`** like the other four demos. No rule fires on that module, so C4 is the byte-identity claim the three no-step demos already make: **`source_stems --optimize: C4 no step · identical`**. `judge.py` needed no change — its `--optimize` path already sets `PY_DEF=""` for a `module` demo and takes the no-log branch.

## The real-program showcase (a mined producer, and the guard its literal unlocks)

`source_stems` proves the rule, but both halves of its crossing pair are written in `judge.py` — deviation 10 of the first pass said so. This slice pays that down as far as the corpus allows: **the producer is mined and sha256-pinned**, and the fact that crosses the call is recomputed off *its* body.

**The producer.** `html_file_name`, from LLVM's opt-viewer (`…/llvm/tools/opt-viewer/optrecord.py:53`), sha256 `f8270a39f647ca17…`:

```python
def html_file_name(filename):
    return filename.replace("/", "_").replace("#", "_") + ".html"
```

One return, no control flow, every primitive already in the fragment. It is judged **apart first**, as its own demo — `html_file_name: C1 ok · C2 189/189 · C3 tested-fragment`, C4 no step · identical — so the pair's evidence is not one file's. The def is unannotated in the source, so the judge supplies the reviewed signature as a **type stub** (`def html_file_name(filename: str) -> str: pass`), exactly as the other mined demos do. A stub is types, and **there is no Python syntax for a postcondition**: the claim cannot be smuggled in through it. `verify_in` mints it off the body or it does not exist.

**The consumer.** `page_tail` binds the call and splits on the dot:

```python
def page_tail(filename: str) -> str:
    page = html_file_name(filename)
    return page.split(".", 1)[1]
```

`split(sep, 1)[1]` is the guarded contract — `Py.after` is emitted only under a known `String.contains(page, ".")` — and this is the **same split `repo_of` writes**, three lines under a hand-written `'.' not in pid` test that pays for it. Here there is no test to write, and nothing in `page_tail`'s own text says a dot is there. The chain, end to end:

```
carries(body)          String.append(String.replace(String.replace(filename,…),…), ".html")  ->  [".html"]
sure / verify_in       PHas{".html"}, recomputed from the mined body, not read from the stub
fresh                  the checked claim is minted into html_file_name's Sig
lets                   page = html_file_name(filename) is an ICall, so the fact lands on `page`
gives                  contains ".html"  widens to  contains "."   (the split's guard; "." ⊂ ".html")
```

**Two controls, each one character of Python**, and each demanding that **nothing be emitted**:

| substitution | what it kills | result |
|---|---|---|
| `+ ".html"` → `+ "html"` | the producer stops putting the dot there — the claim is gone | `primitive Py.after is not granted by a contract (or its guard is not known here) at 3:11` |
| `split(".", 1)` → `split("!", 1)` | the consumer asks for a separator the claim does not contain — the widening is gone | same diagnostic, same span |

Both mutants still parse, still type-check as Python and still return `str`; CPython runs them happily. Each control asserts its substitution applies before it runs, so neither can pass by matching nothing.

```
$ python3 tests/translator/judge.py --demo page_tail --optimize
source   …/llvm/tools/opt-viewer/optrecord.py:53 html_file_name sha256 f8270a39f647ca17 (ast extraction; module never imported)
source   tests/translator/judge.py page_tail caller written here (labeled composite: 1 pinned def + the caller; the module is never imported)
fixtures 7 literal examples + 20 contract edges + 160 generated (seed 20260919) = 187
C1 checker acceptance : ok (no hole/open goal/@unsafe; strict check; lanes check+interpret+js+c all ran)
C2 source parity      : ok interpret 187/187 js 187/187 c 187/187; lanes identical: True
C3 theorem status     : tested fragment, no theorem. Two defs, one call, and one fact across it. …
controls              : ok (injected hole rejected by C1; the tail that never splits rejected by C2;
                        the page name without its dot refused by the kernel; a separator the claim
                        does not hold refused by the kernel)
page_tail: C1 ok · C2 187/187 · C3 tested-fragment
optimized             : ok no rewrite logged; byte-identical to the faithful file: True
page_tail --optimize: C4 no step · identical
```

**Why the caller is still written here** (and what the mining actually found). The corpus has no in-fragment **call site**. `html_file_name`'s own caller in `optrecord.py` is `make_link`, which does `'"{}#L{}"'.format(html_file_name(File), Line)`: `str.format` is outside the fragment, and the result is never bound to a name — deviation 7 requires the binding, because `lets` is where facts are born and it takes a name. An independent AST join over all **11,003** `.py` files reachable in the tree found **zero** same-file pairs where a literal-carrying producer's result is bound and then split on a separator that literal contains, which reproduces the survey handed to this lane (6,810 files, ~5,100 bound-name guard sites, 116 `"literal" + x` producers, zero perfect pairs). The two candidates offered with the brief were both read and both rejected on the fragment, not on taste:

- **`daemon.py:485 _recent_conversation`** — out of fragment as written (`Compare LtE`, `.find`, `\n` escapes, dynamic slice bounds), and *even repaired* it would claim nothing: its early `return text` path means `shared` intersects two arms to the empty set. Its guard site is `startswith`, which carries **no** `pre` in the contract list, so that consumer never needed a postcondition at all.
- **`lerobot.py:57 block_name`** — five return paths carrying five different literals (`"action/ctrl"`, `"reward"`, `"done"`, `"signal/…"`); `shared` intersects them to empty. Its consumers at 172/228 are `startswith` again.

So the honest shape of the deliverable: **the producer is real, the fact is real and machine-derived, the guard is the corpus's own shape** (`repo_of` writes the identical split), and the two-line caller that binds them is written here and labeled as such on every run.

## Span-map notes

**T5 adds no node, so it adds no row kind.** The postcondition is not in the emitted text and has no span of its own; it is a fact about a `let`-bound name, and the `let` already has its row. In `emit_post.bend`:

```
# 25:2-25:38 <- py 2:4-2:19 Let v : List<&2, String>
# 25:7-25:18 <- py 2:8-2:19 Call keyed : List<&2, String>
# 26:2-26:20 <- py 3:4-3:42 Return : List<&2, String>
# 26:2-26:20 <- py 3:11-3:42 Map s : List<&2, String>
# 22:6-22:22 <- py 3:12-3:30 Prim Py.after : String
```

The `Py.after` row at `py 3:12-3:30` is the whole claim: that primitive is in the file **only** because the `Call keyed` row two lines up brought a fact with it. Delete the postcondition slot and that one row disappears, with a positioned refusal in its place — which is what `refuse.bend`'s `post unclaimed` (in the IR) and `post each false` (in the Python) each pin.

The **refusal** of a claim is the one new diagnostic, and it is positioned at the def:

```
the postcondition that the result contains k: is not established by this body:
  drop the claim, or make every path carry it at 1:0
```

The span is the def's own, which is right: a claim is made by the signature, not by any expression inside it, and the repair named is the two things a writer can actually do.

## Judge

```
$ python3 tests/translator/judge.py --demo source_stems --optimize
source   …/llm-wiki/tools/synapse.py:77 fm_sources sha256 e40787adf3abbb71 (ast extraction; module never imported)
source   …/llm-wiki/tools/wiki.py:92 normalize_stem sha256 4af82c046d8931ed (ast extraction; module never imported)
source   tests/translator/judge.py source_stems caller written here (labeled composite: 2 pinned defs + the caller; the module is never imported)
fixtures 9 literal examples + 31 contract edges + 160 generated (seed 20260919) = 200
C1 checker acceptance : ok (no hole/open goal/@unsafe; strict check; lanes check+interpret+js+c all ran)
C2 source parity      : ok interpret 200/200 js 200/200 c 200/200; lanes identical: True
C3 theorem status     : tested fragment, no theorem. The module is the claim: three calls between four defs, …
                        One fact crosses a call: `keyed_sources` puts every item of its result under the
                        `stem:` key, the kernel recomputes that from its body and mints it into the signature,
                        and the caller's `split(':', 1)[1]` is granted by that postcondition and by nothing
                        else -- its own text never says the colon is there.
controls              : ok (injected hole rejected by C1; the comprehension that normalizes nothing rejected
                        by C2; the key without its colon refused by the kernel)
source_stems: C1 ok · C2 200/200 · C3 tested-fragment
optimized             : ok no rewrite logged; byte-identical to the faithful file: True
source_stems --optimize: C4 no step · identical
```

- **Same 200 fixtures, same 200 answers.** The oracle is the same composite text `exec`'d in CPython; it now has four defs and three calls. C2 is 200/200 on all three lanes and the lanes agree with each other.
- **The C2 control moved with the caller.** `normalize_stem(Py.after(s, ":"))` → `Py.after(s, ":")` in the *emitted Bend*: a comprehension that splits but normalizes nothing. Any fixture with an uppercase or space-bearing source separates it.
- **The fourth control is new, and it is the lane's.** `demo["refuse"]` substitutes in the **Python**, not the emitted Bend: `'stem:' + s` → `'stem' + s`. The module still parses, still type-checks as Python, still returns `list[str]`. The judge re-runs `translate.bend` on it and requires a **non-zero exit** carrying `Py.after is not granted by a contract`. A control that demands a *refusal* is new to `judge.py`; every earlier one demanded a wrong answer. It asserts the substitution applies before it runs, so the control cannot silently pass by matching nothing.

## Tests

| file | rows | what |
|---|---|---|
| `emit_post.bend` | new pin | four defs, both kinds, 68 emitted lines + 33 span rows, four lanes |
| `opt_module.bend` | new pin | the module door: a module with no site left byte for byte, two sites logged callee-first, a caller refused when the callee drops the key's colon, and the optimized file of a module whose rewrite and whose crossing fact are in different defs |
| `refuse.bend` | +12 | T5 source-path rows (`mod(label, body)` = `translate(body, contracts(), "")`) |
| `ir_forged.bend` | +12 | T5 forged TypedIR modules and claims (`mod(label, fs)` = `emit_all(fs, contracts())`) |
| `judge.py` | +1 control | the false claim in the Python, refused by the kernel |
| `judge.py` | +2 demos | `html_file_name` (mined producer, judged apart) and `page_tail` (the module that consumes its claim), with two refusal controls |
| `emit_normalize`, `emit_repo_of`, `emit_fm_sources`, `emit_module`, `opt_repo_of`, `opt_rules` | — | untouched: T1–T4 emission is byte-identical, re-run not re-pinned |

**`refuse.bend`, 12 T5 rows.** Three positive, nine refusals. Every row uses the same two callees — `keyed` (a comprehension under the `stem:` key, `PEach`) and `one` (`'stem:' + text.strip()`, `PHas`) — so the false rows differ from the true ones by **one character of Python**, the key's colon.

| row | result |
|---|---|
| `post each` | **emitted** — `v = keyed(text)`, then `[s.split(':', 1)[1] for s in v]` |
| `post has` | **emitted** — `k = one(text)`, then `k.split(':', 1)[1]` |
| `post under a branch` | **emitted** — the caller's control flow tests `k == 'stem:'` first and splits on the other path |
| `post each false`, `post has false`, `post under a branch false` | `primitive Py.after is not granted by a contract (or its guard is not known here)` at 3:12 / 3:11 / 5:11 — the callee's key is `'stem'` |
| `post other sep` | at 3:11 — the caller splits on `-`; `stem:` does not contain it |
| `post rebound` | at 4:11 — `k = k.strip()` drops the fact at the binder |
| `post unbound` | at 2:11 — `one(text).split(':', 1)[1]`: the postcondition is a fact about a **bound name**, and there is none |
| `post through a call` | at 3:11 — `mid` returns `one(text)`; a claim does not propagate through a call |
| `post item from a split` | at 3:12 — the same comprehension over `text.split(',')`: no call, no fact |
| `post item derived` | at 3:12 — `s.strip().split(':', 1)[1]`: the fact is about `s`, not about `s.strip()` |

**`ir_forged.bend`, 12 T5 rows.** Three honest controls, then nine forgeries a source path cannot state:

| row | result |
|---|---|
| `post granted`, `post each granted` | **emitted** — the honest `PHas` and `PEach` modules |
| `post both arms` | **emitted** — a branch whose two arms prepend the key to different values; `shared` keeps it |
| `post unclaimed` | `Py.after is not granted … at 1:5` — the **same two bodies** with the slot emptied. The claim is the carrier; establishing a fact and not claiming it grants nothing. |
| `post forged` | `the postcondition that the result contains k: is not established by this body: drop the claim, or make every path carry it at 1:0` |
| `post forged substring` | same, for `k` — the body carries `k:`, and a claim is **the literal**, not a substring of it (the widening lives in `gives`, on the consuming side) |
| `post one arm` | same, for `k:` — one arm prepends the key, the other does not |
| `post each forged` | same, `every item of the result contains k:` — the comprehension's body is the bare item |
| `post each as has`, `post has as each` | same — the **kind** is part of the claim: `PHas` on a `list[str]` def and `PEach` on a `str` def are both unbacked |
| `post other sep` | `Py.after is not granted … at 1:5` — the honest claim, a caller splitting on the wrong separator |
| `post fact as call` | `primitive Py.every is not granted by a contract … at 1:1` — writing the fact as if it were a primitive, mirroring T3's `fact as call` row for `Py.took` |

No T5 forgery found a hole: every one was refused by the rule as first written. (T4's `call shadowed` and `two defs` each found one; this lane's kernel surface is smaller.)

## Measurements (cap readings)

| file | bytes | ttok | cap (`gates/repo.ts`) |
|---|---|---|---|
| `demos/python/translate.bend` | 100,241 | **32,471** | 64,000 |
| `demos/python/optimize.bend` | 11,207 | **3,666** | 64,000 |
| `tests/translator/judge.py` | 50,326 | **14,156** | 16,000 |
| `tests/translator/ir_forged.bend` | 27,974 | **9,595** | 16,000 |
| `tests/translator/refuse.bend` | 25,525 | **7,862** | 16,000 |
| `tests/translator/emit_post.bend` | 4,037 | **1,595** | 16,000 |
| `tests/translator/opt_module.bend` | 4,749 | **1,716** | 16,000 |
| `tests/translator/emit_module.bend` | 9,163 | 3,694 | 16,000 |

`translate.bend` grew 6,898 bytes / **2,077 ttok** over T4 (93,343 / 30,394), and holds **51%** of its cap. **No cap was moved**, in `gates/repo.ts` or in `tests/caps.sh`; the brief's "prefer not" held, and nothing in `gates/**` was touched.

**`SOUNDNESS.md` was not extended**, and stands where T4 left it at 3,997 of 4,000 ttok. T5 adds no assumption: the postcondition is a kernel rule with twelve forge rows, recomputed from the IR like every other rule. The three tokens of headroom are still the next lane's problem.

**New paths:** `tests/translator/emit_post.bend` (4,037 bytes), `tests/translator/opt_module.bend` (4,749 bytes) and `docs/omen/lanes/translator-t5.md`. All match existing allow rules (`tests/translator/**`, `docs/omen/**`) — **no gate rejection**. `optimize.bend` grew 1,384 bytes / **416 ttok** for the door, to 6% of its cap.

**`judge.py` is the file to watch.** The two demos cost 5,599 bytes / **1,438 ttok**, taking it to **88%** of its 16,000 cap — 1,844 ttok of headroom, or roughly one more demo of this size. The cap was **not** moved and `gates/**` was not touched; the next lane that wants a demo should expect to split the file instead.

## Deviations (honest list)

1. **Two kinds, and the closure is the guard set.** `PHas` and `PEach`, both spelled in `String.contains`, because that is the only fact-discharged guard the contracts carry that a *cross-def* fact can feed. Non-empty, sorted, length bounds and each-item-stripped are all stateable and all useless today: no guard would consume them. When a guard is added that wants one, the kind is added with it.
2. **The claim is exact literals.** `carries` returns the literals a body *surely* contains, and the claim must be one of them verbatim. `PHas{"k"}` on a body carrying `"k:"` is refused, even though it is true. The widening (substring transitivity) lives on the consuming side, in `gives`, where one rule serves every fact source; putting it in the claim check would mean a second place to get it wrong.
3. **`carries` covers `String.append`, literals and the block shapes.** A literal, a concatenation, a `let`/`return`/branch/`Maybe` passthrough. `String.replace`, `String.trim`, slices and every other primitive carry nothing, even when they provably preserve a literal. Adding one is a one-line case, and each is a separate proof obligation nobody has needed yet.
4. **`carries_each` covers only a comprehension.** A list display (`[a, b]`) and a fold-built list claim nothing, though both are decidable. No caller has asked; `ponytail:` comment in the source says so and names the shape.
5. **A claim does not propagate through a call.** `def mid(t): return one(t)` establishes nothing, because `carries(ICall{…}) = []`. A callee's postcondition is a fact about the *caller's bound name*, not part of the caller's own recompute. Making it transitive is one case in `carries` plus a `ss` parameter through `sure` — and a real design question about whether `sure` may read the signature table at all, which is why it waits. `refuse.bend`'s `post through a call` pins the current answer.
6. **Facts still die at every binder that is not a comprehension.** `items_of` moves exactly one fact across exactly one scope (`Py.every` over the iterated value → `String.contains` on the item). A fold step, a `Maybe` arm and a rebinding `let` drop everything, as in T1–T4.
7. **The fact is about a name, so the call's result must be bound.** `one(text).split(':', 1)[1]` is refused; `k = one(text)` then `k.split(…)` is not. `lets` is where facts are born and it takes a name. A fact about an anonymous subexpression would need a different carrier.
8. **`Sig.post` is `[]` on the elaborator's header-only signatures.** `signature` builds the arity/type row for the ranking pass before any body exists. Only `fresh`, after `verify_in`, ever fills the slot — which is the point, but it means the *ranking* search cannot use postconditions to choose an order.
9. **`Py.every` is a fact with no primitive.** Like `Py.took`, it exists only inside the fact environment; a body that writes it is refused. It renders nowhere and has no runtime.
10. **The producer is mined; the two-line caller is not.** `page_tail`'s `html_file_name` is real source, sha256-pinned, judged apart and never annotated — its claim is recomputed by `verify_in` off the body. The caller that binds it is written in `judge.py` and printed as written-here on every run, because no corpus file *calls* an in-fragment producer and binds the result: `make_link`, `html_file_name`'s own caller, goes through `str.format`. An 11,003-file AST join found zero same-file pairs, reproducing the survey handed to this lane. `source_stems`' `keyed_sources` remains written-here at both ends and is kept as the `PEach` half of the rule.
11. **`optimize.bend` recomputes the claim on every rewrite** rather than proving a rule preserves it. Cheap and always right. With the module door open, a caller *is* in scope: a rewrite that destroys a postcondition another def depends on is refused at that caller's guard, by `optimize_all`'s second `Tr.ordered`, and not at the rule that did it. The diagnostic names the wrong def — the repair is a rule-level obligation, and no rule needs one yet.
12. **Claims are recomputed twice per def** — once by `with_sig` to propose, once by `verify_in` to check. On a module that is `2N` traversals of bodies that have already been walked. The `ponytail:` rule applies: a module is a handful of defs, and the duplication is what keeps the elaborator untrusted.

## What T6 and `optimize.bend` (tier ③) inherit

1. **The module door is closed; the module *rule* is not.** `optimize.bend` now rewrites a program (T4 item 3, taken as this brief's optional tail), but its one rule, `hoist_append`, is a within-expression rewrite: on the `source_stems` module nothing fires, so C4 there is byte identity and nothing more. The first rule that reads across a call — fusion (item 4), or a callee inlined at one site — is what makes the door pay, and it is the first rewrite whose obligation is the *fact* environment, not just the types.
2. **Preconditions are the mirror, and the harder half.** T5 sends facts *out* of a def. A def that wants "my argument contains `:`" needs the caller to discharge it — which means a `pre` slot on `Sig`, checked at every call site and *granted* inside the body. The machinery is symmetric (`gives` already takes a guard and a fact), but the failure mode is not: an unbacked postcondition is refused at one def, an undischarged precondition at every caller.
3. **Transitivity through a call** (deviation 5) is the cheapest real extension, and the first one that forces `sure` to read the signature table — i.e. the first time the *claim* depends on something other than the body.
4. **Map/map fusion across a call** (T4 item 4) now has a fact to preserve as well as a value: `source_stems.comp_3_11 ∘ keyed_sources.comp_6_11` is exactly the pair, and the `Py.after`/`String.append` cancellation in the fused body is a law about the postcondition, not about the types.
5. **The `String.contains` monoculture is load-bearing.** Every cross-def fact in the fragment routes through one predicate, which is why two kinds sufficed. The first guard that is *not* `String.contains` and is *not* static — a numeric bound, a shape, a parsed-pattern property — is the event that makes `Post` a real language instead of two constructors, and it should be resisted until a caller genuinely needs it.
