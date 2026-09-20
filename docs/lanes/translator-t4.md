# Translator lane — T4 report (fable, 2026-09-19)

Branch `lane-translator-t4`, worktree `bend-work-translator-t4`, off `omen` @ `2babbefa` (T3 and the lint stream integrated).
T4 = `ICall` and the module. T1–T3 translate **one** def and refuse every user call ("IR node Call is not emittable in T3"); T4 takes a **program**: N top-level defs of one source, elaborated together, with the calls between them granted by a rank the kernel computes itself. The caller may be written first.
Semantic pin: CPython 3.11.15. Acceptance: `bash tests/translator/run.sh` → **`Translator PASS: 32, FAIL: 0`**, ending with five judge demos:
**`normalize_stem: C1 ok · C2 191/191`**, **`repo_of: C1 ok · C2 186/186`** (+ C4 1 step Proven), **`first_dash: C1 ok · C2 168/168 · 2/2 closed doctest laws`**, **`fm_sources: C1 ok · C2 194/194`**, **`source_stems: C1 ok · C2 200/200`** (all C3 tested-fragment).

Untouched, as instructed: `bend2/**`, `gates/**`, `tests/caps.sh`, every other namespace, `demos/python/optimize.bend` and `demos/python/syntax.bend`. Faithful mode only. No pushes.

## Slices

| slice | commit | content |
|---|---|---|
| T4 core | `1cf340ce` | `demos/python/translate.bend`: `ICall`, module elaboration, the ranking search, the kernel's call rule, `emit_all` |
| T4 tests | `9114478c` | `ir_forged.bend` (+12 rows), `refuse.bend` (+17 rows), `emit_module.bend` (new pin), and the two kernel rules those forgeries found |
| judge | `4432b403` | `judge.py` (the `source_stems` module demo), `run.sh` |
| report | this commit | `docs/omen/lanes/translator-t4.md` |

## What changed

`demos/python/translate.bend` 1756 → 1979 lines. Same three trust zones (untrusted `elaborate*`, the `verify` kernel that recomputes from the IR alone, `emit = verify then render`); T4 adds a fourth stage **between** them, and it is untrusted too: the **rank**.

- **The door.** `translate_as(source, sig, contracts, name)` with an **empty** `name` means the whole module: every top-level def, with the calls between them. A non-empty name is T1–T3, one def. The judge sets `PY_DEF=""`; `IO.get_env` uses `Object.hasOwn`, so "set to empty" is distinguishable from unset.
- **`ICall{name, args, t, loc}`.** The callee is a module-local def name, `args` is the same `IArg` spine every primitive uses, `t` is the result type, and the span is mandatory like every other node. There is no new call form for builtins: contracted methods stay `IPrim`.
- **The rank (untrusted).** `ordered` peels the defs the kernel already accepts:
  - `first_ready(fs, [], ss, cs)` rotates the list until its head is a def `verify_in` accepts against the signatures `ss` collected so far, and keeps the original order when **none** is ready, so the failure reported is that def's own diagnostic at its own call, not an invented one about ordering;
  - `order` verifies that head for real, appends its signature with `fresh`, and recurses on the rest;
  - the certificate is **the list position**: a def is emitted only after every def it calls. There is no call-graph extractor to trust, because the placement predicate *is* the kernel.
  - `fresh` also refuses two defs of one name: a module would emit both and no call could say which. The source path cannot state it (`unique` refuses it earlier), but a forged TypedIR can.
  - Fuel is `length + 1` (the last step must reach the empty list). Exhaustion is a positioned `Limit` error, not a silent stop.
- **The kernel's call rule.** `verify_in` carries the signatures of the defs ranked below. A call is granted only when all four hold, recomputed from the IR:
  1. the span is real and the callee is an identifier;
  2. the callee is **not** a name bound in the caller's own scope (`Bool.not(has_name(env, name))`) — otherwise Python would call the binding and the emitted Bend would call the def;
  3. `resolves(ss, name, args, ty(t))`: some signature in the prefix has that name, that arity, those argument types and that result type;
  4. the arguments themselves verify in argument position.
  A cycle, a self-call, an unknown callee, a wrong arity or a wrong type is a call **no prefix grants**, so it is refused where it is written:
  `call g(String;) -> String is granted by no def ranked below this one at 2:11`.
  Effects are unchanged: a def is `Pure` or it is refused, so every call site is pure by construction.
- **Emission.** `emit_all` = rank, then render: the prelude (the contracts any def uses) once, then the defs in rank order, then one span map for the whole file. The title names every def with its source span. `render(f, cs) = render_all([f], cs)`, so **T1–T3 emission is byte-identical** — `emit_normalize.bend`, `emit_repo_of.bend`, `emit_fm_sources.bend`, `opt_repo_of.bend` and `opt_rules.bend` were re-run, not re-pinned.

## The program

The source is a **labeled composite** (`tests/translator/judge.py`, demo `source_stems`): two reviewed defs mined from `~/Documents/Project/llm-wiki` by `ast`, plus a caller written in the judge and labeled as such. No real ≤4-def in-fragment call chain exists in that tree (surveyed by `ast`), which is the fallback the brief allows. The parts carry their pins; the caller carries none and claims none.

```python
def source_stems(text: str) -> list[str]:
    return [normalize_stem(s) for s in fm_sources(text)]

def fm_sources(text):
    m = re.search(r"^---\n(.*?)\n---", text, re.S)
    if not m:
        return []
    for line in m.group(1).splitlines():
        if line.startswith('sources:'):
            v = line.split(':', 1)[1].strip()
            if v.startswith('['):
                return [x.strip().strip('"') for x in v[1:-1].split(',')]
            return [v]
    return []

def normalize_stem(s: str) -> str:
    """Lowercase and replace spaces with hyphens."""
    return s.strip().lower().replace(" ", "-")
```

`fm_sources` (`tools/synapse.py:77`, sha256 `e40787adf3abbb71…`) is unannotated, so its types come from the reviewed stub `import re\ndef fm_sources(text: str) -> list[str]:\n    pass`. `normalize_stem` (`tools/wiki.py:92`, sha256 `4af82c046d8931ed…`) annotates itself. The caller is written **first** and calls both; the kernel ranks them below it.

`python3 tests/translator/judge.py --demo source_stems --show`, pinned byte for byte in `tests/translator/emit_module.bend`:

```
# Faithful translation (tiers 1-2) of Python `fm_sources` 4:0-14:13, `normalize_stem` 16:0-18:46, `source_stems` 1:0-2:56 by demos/python/translate.bend.
import Base

def Py.after(+s: String, +sep: String) -> String:
  Pair.snd(String, String, Pair.snd(String, String & String, String.partition(s, sep)))

def Py.strip_start(s: String, +cs: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+h, +t}:
      Bool.pick(String, String.contains(cs, SCon{h, SNil{}}), Py.strip_start(t, cs), SCon{h, t})

def Py.strip(s: String, +cs: String) -> String:
  String.reverse(Py.strip_start(String.reverse(Py.strip_start(s, cs)), cs))

type Py.Match is Data:
  PyMatch{s: String, m: Match}

def Py.search.found(+s: String, m: Maybe<&2, Match>) -> Maybe<&2, Py.Match>:
  match m:
    case None{}:
      None{}
    case Some{mm}:
      Some{PyMatch{s, mm}}

def Py.search.run(+s: String, r: Regex.Res(Regex)) -> Maybe<&2, Py.Match>:
  match r:
    case Fail{e}:
      None{}
    case Done{re}:
      Py.search.found(s, Regex.find(re, s))

def Py.search(s: String, p: String, +f: String) -> Maybe<&2, Py.Match>:
  Py.search.run(s, Regex.compile(p, f))

def Py.group(m: Py.Match, k: Nat) -> String:
  match m:
    case PyMatch{s, mm}:
      Maybe.default(&2, String, Regex.group(s, mm, k), "")

type Step<-A: Data> is Data:
  Continue{acc: A}
  Stop{acc: A}

def fm_sources.comp_12_23(_xs: List<&2, String>) -> List<&2, String>:
  match _xs:
    case Nil{}:
      []
    case Con{x, _rest}:
      Py.strip(String.trim(x), "\"") <> fm_sources.comp_12_23(_rest)

def fm_sources.if_11_12(_c: Bool, v: String) -> Step<Maybe<&2, List<&2, String>>>:
  match _c:
    case True{}:
      Stop{Some{fm_sources.comp_12_23(String.split_on(String.drop_end(String.drop(v, 1n), 1n), ","))}}
    case False{}:
      Stop{Some{[v]}}

def fm_sources.if_9_8(_c: Bool, ret_8_4: Maybe<&2, List<&2, String>>, line: String) -> Step<Maybe<&2, List<&2, String>>>:
  match _c:
    case True{}:
      +v = {String.trim(Py.after(line, ":")) : String}
      fm_sources.if_11_12(String.starts_with(v, "["), v)
    case False{}:
      Continue{ret_8_4}

def fm_sources.for_8_4(_xs: List<&2, String>, _st: Step<Maybe<&2, List<&2, String>>>) -> Maybe<&2, List<&2, String>>:
  match _xs _st:
    case Nil{} Continue{ret_8_4}:
      ret_8_4
    case Nil{} Stop{ret_8_4}:
      ret_8_4
    case Con{_x, _rest} Stop{ret_8_4}:
      ret_8_4
    case Con{+line, _rest} Continue{ret_8_4}:
      fm_sources.for_8_4(_rest, fm_sources.if_9_8(String.starts_with(line, "sources:"), ret_8_4, line))

def fm_sources.opt_8_4(ret_8_4: Maybe<&2, List<&2, String>>) -> List<&2, String>:
  match ret_8_4:
    case None{}:
      []
    case Some{ret_8_4}:
      ret_8_4

def fm_sources.opt_6_4(m: Maybe<&2, Py.Match>) -> List<&2, String>:
  match m:
    case None{}:
      []
    case Some{m}:
      ret_8_4 = {fm_sources.for_8_4(String.splitlines(Py.group(m, 1n)), Continue{None{}}) : Maybe<&2, List<&2, String>>}
      fm_sources.opt_8_4(ret_8_4)

def fm_sources(text: String) -> List<&2, String>:
  m = {Py.search(text, "^---\\n(.*?)\\n---", "s") : Maybe<&2, Py.Match>}
  fm_sources.opt_6_4(m)

def normalize_stem(s: String) -> String:
  String.replace(String.to_lower(String.trim(s)), " ", "-")

def source_stems.comp_2_11(_xs: List<&2, String>) -> List<&2, String>:
  match _xs:
    case Nil{}:
      []
    case Con{s, _rest}:
      normalize_stem(s) <> source_stems.comp_2_11(_rest)

def source_stems(text: String) -> List<&2, String>:
  source_stems.comp_2_11(fm_sources(text))
```

Reading it against the Python:
- **Rank order, not source order.** The file is `fm_sources`, then `normalize_stem`, then `source_stems`. The Python wrote the caller first. Callees-first is not cosmetic: a Bend def may not name a def written below it (checked on this tree: a `main` that calls a `later` defined after it fails with "expected: a defined name"), so **the rank is what makes the emitted file resolve at all**.
- **The two calls are plain Bend calls.** `fm_sources(text)` is the comprehension's iterable (`109:25`), `normalize_stem(s)` is its body, inside the generated helper `source_stems.comp_2_11` (`106:6`). No wrapper, no thunk, no dictionary.
- **The prelude is emitted once** for the whole module: `Py.after`, `Py.strip`, `Py.Match`, `Py.search`, `Py.group`, `Step`. `normalize_stem` and `source_stems` contribute none of it, and `fm_sources`' share is unchanged from T3.
- **The parts are untouched.** `fm_sources`' body is T3's, up to the synthetic helper names, which carry their Python line and so move with the caller's three lines (`comp_9_23` → `comp_12_23`, `if_8_12` → `if_11_12`, `for_5_4` → `for_8_4`, `opt_3_4` → `opt_6_4`). `normalize_stem`'s body is T1's, character for character.
- **The comprehension helper is self-recursive** (`comp_2_11` calls itself), as in T1–T3: generated helpers recurse structurally. The rank governs calls between **user** defs only.

## Span-map notes

68 rows (`emitted l:c-l:c <- py l:c-l:c Node : type`), the whole map in the `#|` block of `tests/translator/emit_module.bend`. Three are new to T4:

```
# 106:6-106:23 <- py 2:12-2:29 Call normalize_stem : String
# 106:21-106:22 <- py 2:27-2:28 Var s : String
# 109:25-109:41 <- py 2:39-2:55 Call fm_sources : List<&2, String>
```

- **A `Call` row names the whole call expression**, both halves: the emitted `normalize_stem(s)` and the Python `normalize_stem(s)`. The callee name has no row of its own — it is not an operand — while each argument keeps its own row (`106:21-106:22 <- py 2:27-2:28 Var s`).
- **The map is a module map, not a concatenation.** Emitted lines run 1…109 across all three defs, and the Python side crosses def boundaries freely: `py 2:*` (the caller), `py 5–14:*` (`fm_sources`), `py 16–18:*` (`normalize_stem`), in one sorted table.
- **The parts' maps survive the move, and the move is measurable.** All 53 `fm_sources` rows from `emit_fm_sources.bend` reappear with their Python halves shifted by exactly **+3** lines (the caller's two lines and the blank), and their emitted columns identical except on lines 56 and 64, which shift by **+1** because `comp_12_23` and `if_11_12` are one digit longer than T3's names. All 8 `normalize_stem` rows from `emit_normalize.bend` reappear with the Python half shifted by **+15** and **identical columns**. This was checked by re-reading both pins, not by eye.
- **A span is a module span.** `py 1:17-1:26` is the caller's `text` parameter and `py 4:15-4:19` is `fm_sources`' — two `Param` rows that would both be `1:*` if the defs were translated apart.

## Judge

```
$ python3 tests/translator/judge.py --demo source_stems
source   …/llm-wiki/tools/synapse.py:77 fm_sources sha256 e40787adf3abbb71 (ast extraction; module never imported)
source   …/llm-wiki/tools/wiki.py:92 normalize_stem sha256 4af82c046d8931ed (ast extraction; module never imported)
source   tests/translator/judge.py source_stems caller written here (labeled composite: 2 pinned defs + the caller; the module is never imported)
fixtures 9 literal examples + 31 contract edges + 160 generated (seed 20260919) = 200
C1 checker acceptance : ok (no hole/open goal/@unsafe; strict check; lanes check+interpret+js+c all ran)
C2 source parity      : ok interpret 200/200 js 200/200 c 200/200; lanes identical: True
C3 theorem status     : tested fragment, no theorem. The module is the claim: two calls between three defs, ranked by the kernel (a callee is granted only against the defs it has already accepted, so the rank is the list position and a cycle cannot be stated). Each call is the plain Bend call; the parts' own contracts are unchanged and were judged apart above. The caller is written in this file and labeled, not mined: it carries no reviewed source, so nothing is assumed of it beyond what the fragment already grants.
controls              : ok (injected hole rejected by C1; the comprehension that calls nothing rejected by C2)
source_stems: C1 ok · C2 200/200 · C3 tested-fragment
```

- **End-to-end, through the top of the chain.** Every fixture calls `source_stems(text)`; nothing calls `fm_sources` or `normalize_stem` directly. The oracle is the same composite text `exec`'d in CPython with `__builtins__ = {"str": str, "list": list}` and `re` as its only global, so the Python module has the same three defs and the same call chain.
- **Four lanes.** C1 is `book_valid` plus the strict `check`; C2 runs the emitted module in `interpret`, `js` and `c` and demands all three agree with CPython **and** with each other.
- **Fixtures.** The 31 contract edges are `fm_sources`' 27 (frontmatter delimiters, `^` without `re.M`, splitlines boundaries, quote stripping, `[a,,b]`, …) plus four the caller earns: `sources: A B` (both calls on one item), `[ A B , C D ]` (a list where every item goes through `normalize_stem`), `sources:  ` (whitespace only → `[""]` → `[""]`), and `sources: -` (a value `normalize_stem` leaves alone).
- **The controls are the brief's two.** A hole injected into the emitted module must be rejected by C1, and it is. A **wrong call** — in the emitted Bend, `normalize_stem(s)` inside `source_stems.comp_2_11` replaced by `s`, so the comprehension calls nothing — must be rejected by C2, and it is (any fixture with an uppercase or space-bearing source separates them).

## Tests

| file | rows | what |
|---|---|---|
| `emit_module.bend` | new pin | the whole module + its 68 span rows, four lanes |
| `refuse.bend` | +17 | T4 source refusals (`mod(label, body)` = `translate(body, contracts(), "")`) |
| `ir_forged.bend` | +12 | T4 forged TypedIR modules (`mod(label, fs)` = `emit_all(fs, contracts())`) |
| `emit_normalize`, `emit_repo_of`, `emit_fm_sources`, `opt_repo_of`, `opt_rules` | — | untouched: T1–T3 emission is byte-identical |

**`refuse.bend`, 17 T4 rows.** One positive control, `chain`: three defs, `f` calls `g` calls `h`, the caller written first, **emitted**. The other 16 are refusals, each at its own position:

| row | diagnostic |
|---|---|
| `self call`, `cycle`, `cycle of three` | `call <callee>(String;) -> String is granted by no def ranked below this one at 2:11` (`f` for the self-call, `g` for both cycles) |
| `call arity`, `call arg type` | `no def ranked below this one takes g(String;) at 5:11` |
| `call result type` | `type mismatch: (String) where (List<&2, String>) is expected at 5:4` |
| `unknown callee`, `param shadows`, `let shadows`, `keyword call` | `outside the fragment: Call` |
| `import`, `from import` | `module not closed: Import at 1:0` / `… ImportFrom at 1:0` |
| `no def` | `module: no top-level def to translate at 1:0` |
| `def named len`, `def named re` | `a def of the module is named re or len, which revokes the builtin the contracts assume` |
| `two defs of a name` | `no unique def g` |

**`ir_forged.bend`, 12 T4 rows.** Two honest controls (`module`, and `caller first` — the same two defs in the other order, both **emitted**), then ten forged TypedIRs that the kernel refuses by recompute, with no source to blame:

- `call arity` (two arguments to a one-parameter def), `call unknown` (`h`), `call arg type` (a `List` where the signature says `String`), `call result type` (`TBool`), `call self`, `call cycle` (two defs calling each other), `call shadowed` (a caller whose **parameter** is named `g`, so Python would call the parameter) — all `granted by no def ranked below this one at 1:0`;
  The message echoes the **attempted** signature, which is all the IR states: `call g(String;String;) -> String`, `call g(List<&2, String>;) -> String`, `call g(String;) -> Bool`.
- `two defs` (the same def twice) — `two defs of the module are named g at 1:0`;
- `call impure` (a caller marked `Impure`) — `effect is not Pure at 1:0`.

Two of these were written as expected-to-pass and **found real holes**, which is why the kernel gained two rules in `9114478c`: `call shadowed` (fixed by `Bool.not(has_name(env, name))`) and `two defs` (fixed by `fresh`, which also let `sig_of` be deleted).

## Measurements (cap readings)

| file | bytes | ttok | cap (`gates/repo.ts`) |
|---|---|---|---|
| `demos/python/translate.bend` | 93,343 | **30,394** | 64,000 |
| `demos/python/SOUNDNESS.md` | 15,087 | **3,997** | 4,000 |
| `tests/translator/judge.py` | 42,889 | **12,230** | 16,000 |
| `tests/translator/ir_forged.bend` | 23,243 | **7,990** | 16,000 |
| `tests/translator/refuse.bend` | 21,990 | **6,782** | 16,000 |
| `tests/translator/emit_module.bend` | 9,163 | **3,694** | 16,000 |
| `tests/translator/emit_fm_sources.bend` | 7,600 | 3,082 | 16,000 |
| `tests/translator/run.sh` | 4,522 | 1,420 | 16,000 |

`translate.bend` grew 10,593 bytes / 3,442 ttok over T3 (82,750 / 26,952), and holds **47%** of its cap.

**`SOUNDNESS.md` was not extended.** It stands at 3,997 of 4,000 ttok — three tokens — and T4's claims (the rank, the call rule) are kernel rules with their own forge rows, not new *assumptions*. Adding a row would have meant trimming an existing assumption's text to pay for it; that trade belongs to whoever next needs the space, and is recorded here instead.

**New paths:** `tests/translator/emit_module.bend` (9,163 bytes) and `docs/omen/lanes/translator-t4.md`. Both match existing allow rules (`tests/translator/**`, `docs/omen/**`) — **no gate rejection**.

GATESTABLE

## Deviations (honest list)

1. **Acyclic only.** Self-recursion and cycles are refused with a positioned diagnostic, never faked. This is not only conservatism: a cycle *cannot* be emitted, because a Bend def may not name a def written below it and mutual recursion is unavailable to user code. Self-recursion is expressible in Bend but has no termination story here, so it waits for a measure (see inherits).
2. **The diagnostic names the rank, not the reason.** A cycle, a self-call, an unknown callee and a bad type all report "granted by no def ranked below this one". That is exactly what the kernel knows — it has a prefix and a call, not a graph — but it is a poorer message than L4's explicit cycle counterexample. The elaborator's earlier, more specific refusals (`no def ranked below this one takes g(String;)`) cover the arity and argument-type cases.
3. **A module must be closed.** Any `import` or `from … import` in the translated source is refused (`module not closed`). `re.` is reachable only through the **reviewed stub**'s `import re`, exactly as in T3 — so `fm_sources` keeps its regex inside a module that itself imports nothing.
4. **Calls are checked against the signature alone.** No caller-side fact crosses a call, and no callee postcondition comes back. `Py.took`-style facts stop at the call boundary.
5. **Two defs of one name are refused**, in both the source path (`no unique def g`) and the IR path (`two defs of the module are named g`). Python's last-wins is not modeled.
6. **Keyword arguments, defaults and `*args` stay outside the fragment** (`outside the fragment: Call`), as do calls to names bound in scope.
7. **Ranking is O(n²) verification** — `first_ready` re-verifies each candidate against the current prefix on every pass. A module is a handful of defs; the code says so in a `ponytail:` comment, and a real ranking pass is the upgrade if that stops being true.
8. **The module switch is an empty `PY_DEF`.** `""` is a real value, not unset; `IO.get_env` distinguishes them. A caller that forgets `PY_DEF` still gets T1–T3 behaviour (an error naming the missing def), not a silent whole-module translation.
9. **The judge demo is a labeled composite.** The two parts are real, pinned and sha256'd; the caller is written in `judge.py`, printed as such on every run, and claims nothing. The brief's first choice — a real ≤4-def chain in `llm-wiki` — does not exist in the fragment.
10. **No `--optimize` for the module.** `demos/python/optimize.bend` still takes one def through `PY_DEF`; the module demo runs C1/C2/C3 only, and `run.sh` says so where it calls it.
11. **Emission order is the rank**, so the emitted file need not follow the Python source's order — and the title line lists the defs in **rank** order with their source spans, which is the order a reader of the Python will not recognize.
12. **The prelude is the union.** One prelude for the module, selected by what the rendered code mentions. A def that uses no contract adds nothing, but it also cannot get a smaller file than the module's.

## What T5 and `optimize.bend` (tier ③) inherit

1. **`ICall` is now in the IR that rewrite rules match.** A rule must pass calls through untouched, and because `IR.verify` recomputes the resolution and the rank, a rewrite that reorders defs, renames a callee or changes an arity is refused by the **same** kernel as faithful output. The first rule (`hoist_append` on `repo_of`) is unaffected: its target text is byte-identical after T4, and `opt_repo_of.bend` / `opt_rules.bend` were re-run green.
2. **Inlining becomes stateable.** The callee's body is in the same IR, ranked strictly below the caller, so a tier-③ inline rule has its termination argument for free — the rank is a well-founded measure on a module with no cycles. Nobody has written it; this is the first lane where it could be written.
3. **The optimizer needs a module mode.** It takes `PY_DEF` and one def. Until it grows `emit_all`'s door, a program can be judged (C1–C3) but not rewritten (C4), which is why `source_stems` runs without `--optimize`.
4. **A fusion target exists.** `source_stems.comp_2_11` maps `normalize_stem` over `fm_sources(text)`'s output, which `fm_sources` built by another map (`comp_12_23`) or a singleton. Map/map fusion across a call is the first cross-def rewrite the tree can state, and it needs (2) or a law relating the two helpers.
5. **Recursion wants Lint's measure, not the translator's rank.** The rank refuses self-calls; the lint stream (L1–L4) already recomputes structural descent for totality. A translator that accepts `def f(xs): … f(xs[1:])` should carry a Lint-style descent certificate in the IR rather than invent a second one.
6. **Cross-def facts are the next kernel extension.** Deviation 4 is the wall: `fm_sources`' result is `list[str]` and nothing more, so a caller that wants "non-empty" or "each item stripped" must re-derive it. A postcondition slot on `Sig`, recomputed at both ends, is the shape that fits the existing kernel.
