# Translator lane — T3 report (fable, 2026-09-19)

Branch `lane-translator-t3`, worktree `bend-work-translator-t3`, off `omen` @ `c25afaec` (T2 integrated).
T3 = the long tail of real code: early return inside a loop, list displays and comprehensions, string slices, `strip(cs)`, `split(sep)`, `splitlines()`, `re.search` / `m.group(k)` as guarded partials, and the last judge demo `fm_sources`.
Semantic pin: CPython 3.11.15. Acceptance: `bash tests/translator/run.sh` → **`Translator PASS: 20, FAIL: 0`**, which ends with the four judge demos:
**`normalize_stem: C1 ok · C2 191/191`**, **`repo_of: C1 ok · C2 186/186`**, **`first_dash: C1 ok · C2 168/168 · 2/2 closed doctest laws`**, **`fm_sources: C1 ok · C2 194/194`** (all C3 tested-fragment).

Untouched, as instructed: `bend2/**`, `gates/**`, `tests/caps.sh`, every other namespace, every other file in `demos/python/`. Faithful mode only: no program-specific rewrite was emitted; the ③ candidates are recorded at the end, not applied. No pushes.

## Slices

| slice | commit | content |
|---|---|---|
| T3 core | `b7810997` | `demos/python/translate.bend`: IList / IMap / early-return fold / slices / regex contracts, kernel + renderer |
| T3 tests | `0fd9ac1d` | `judge.py` (`fm_sources`), `run.sh`, `emit_fm_sources.bend`, `refuse.bend`, `ir_forged.bend` |
| report | this commit | `docs/omen/lanes/translator-t3.md` |

## What changed

`demos/python/translate.bend` 1396 → 1756 lines. Same three trust zones as T1/T2 (untrusted `elaborate`, the `verify` kernel that recomputes from the IR alone, `emit = verify then render`).

- **IR.** `Ty` + `TMatch` (a successful match with its subject, rendered `Py.Match`). `Ir` + `IList{items}` (a list display) and `IMap{item, over, body}` (a comprehension). No new node for the early return: it is an `IFold` whose state is the function's own `Maybe`, stopped by `IStop{ISome{e}}`, then an `IMaybe` on the fold's value.
- **Early return inside a loop.** A loop whose body can `return e` gets its own accumulator `ret_L_C : Maybe<&2, R>` (R = the function's return type), starting at `None{}`. `return e` in the loop becomes `Stop{Some{e}}`; the fold (T2's `Step` helper) stops without evaluating the rest of the list. After the loop, `opt_L_C` matches the fold's value: `Some{r}` returns `r`, `None{}` runs the statements after the loop. The kernel checks positions from the IR: a Stop only in a step, its payload `ISome` of exactly R, and the `None` arm never reading the fold's name. The `if` at the end of a loop body may now be followed by statements when every path of its arm stops (the statements are then its else-continuation, as in a function body). A loop that returns may not also assign a name bound before it: one Step payload, not two.
- **IList, IMap.** `[a, b]` is a list display of one element type. `[]` takes the declared return type, which must be a list, so no element type is ever guessed. `[e for x in xs]` becomes a recursive helper `f.comp_L_C(_xs, captures…)` that matches `_xs`. It visits the head first and conses `e` onto the rest, so `e` is evaluated once per item, in order. The fragment allows one generator, no `if`, and a fresh target. The kernel refuses a comprehension body that returns, stops or lets, and it drops facts at the item binder.
- **Slices.** `x[i:]` = `String.drop(x, i)`, total for any natural `i`. `x[:-k]` = `String.drop_end(x, k)` with guard `positive`: `k` must be a nonzero literal, because Python's `x[:-0]` is `x[:0]` = `""`, not `x`. `x[i:-k]` = `drop_end(drop(x, i), k)`. Other slices (a head `[:k]`, a negative start, a step) stay refused.
- **Regex.** `re.search(p, s, re.S)` = `Py.search(s, p, "s")`, under Base's Regex (CPython 3.11 `re.ASCII`, equal on the value contract).
  - The guard `Regex.compile` makes the `Fail` arm (Python's `re.error`) unreachable. The kernel grants it only when the pattern is a literal that compiles, the flag is the literal `"s"`, and `re` is the module the signature stub imports.
  - `m.group(k)` = `Py.group(m, k)` with guard `Py.took`. The `ILet` of a search makes known the fact `Py.took(m, P)`. The kernel grants group `k` only where `must(P, k)` holds, recomputed from the parsed pattern: every match of `P` sets group `k`. So group 0, an absent group, an optional group, a lazy-`*` group, and a group on one side of `|` are all refused.
  - `if not m` narrows, since a match is always truthy.
- **Literals.** A decimal natural (`1`, rendered `1n`, no sign or `_` or leading zero), and `r'…'` / `r"…"` whose body may hold a backslash but not end in one (`S.quote` escapes it). `TInt` now flows into slice bounds and `group` as well as `>`.
- **Name hygiene.** `re` is reachable only as `re.search` under the stub's `import re`; the judge checks by `ast` that the source module binds `re` only by a top-level `import re`. A def that binds `re` or `len` itself is refused, since Python would read the local.

Contracts added (value contract = printable ASCII + six ASCII whitespace; all pure + total, the guarded ones under their guard):

| Python | Bend | guard |
|---|---|---|
| `s.strip(cs)` | `Py.strip` (prelude: one self-recursive `strip_start`, two `String.reverse`) | — |
| `s.splitlines()` | `String.splitlines` (Base: LF CR CRLF VT FF FS GS RS NEL LS PS, no trailing empty) | — |
| `s.split(sep)` | `String.split_on` | `literal`: `sep` a non-empty literal (Python raises on `''`) |
| `s[i:]` | `String.drop` | — |
| `s[:-k]` | `String.drop_end` | `positive`: `k` a nonzero literal |
| `re.search(p, s, re.S)` | `Py.search(s, p, "s")` : `Maybe<&2, Py.Match>` | `Regex.compile`: `p` a compiling literal, flag `"s"` only |
| `m.group(k)` | `Py.group(m, k)` = `Regex.group` on the kept subject | `Py.took`: group `k` takes part in every match |

## The emitted Bend for `fm_sources` (verbatim)

Source (`~/Documents/Project/llm-wiki/tools/synapse.py:77-87`, sha256 `e40787adf3abbb71…`, extracted by `ast`, module never imported). Reviewed signature stub: `import re\ndef fm_sources(text: str) -> list[str]:\n    pass`.

```python
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
```

`python3 tests/translator/judge.py --demo fm_sources --show` (also pinned in `tests/translator/emit_fm_sources.bend`):

```python
# Faithful translation (tiers 1-2) of Python `fm_sources` 1:0-11:13 by demos/python/translate.bend.
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

def fm_sources.comp_9_23(_xs: List<&2, String>) -> List<&2, String>:
  match _xs:
    case Nil{}:
      []
    case Con{x, _rest}:
      Py.strip(String.trim(x), "\"") <> fm_sources.comp_9_23(_rest)

def fm_sources.if_8_12(_c: Bool, v: String) -> Step<Maybe<&2, List<&2, String>>>:
  match _c:
    case True{}:
      Stop{Some{fm_sources.comp_9_23(String.split_on(String.drop_end(String.drop(v, 1n), 1n), ","))}}
    case False{}:
      Stop{Some{[v]}}

def fm_sources.if_6_8(_c: Bool, ret_5_4: Maybe<&2, List<&2, String>>, line: String) -> Step<Maybe<&2, List<&2, String>>>:
  match _c:
    case True{}:
      +v = {String.trim(Py.after(line, ":")) : String}
      fm_sources.if_8_12(String.starts_with(v, "["), v)
    case False{}:
      Continue{ret_5_4}

def fm_sources.for_5_4(_xs: List<&2, String>, _st: Step<Maybe<&2, List<&2, String>>>) -> Maybe<&2, List<&2, String>>:
  match _xs _st:
    case Nil{} Continue{ret_5_4}:
      ret_5_4
    case Nil{} Stop{ret_5_4}:
      ret_5_4
    case Con{_x, _rest} Stop{ret_5_4}:
      ret_5_4
    case Con{+line, _rest} Continue{ret_5_4}:
      fm_sources.for_5_4(_rest, fm_sources.if_6_8(String.starts_with(line, "sources:"), ret_5_4, line))

def fm_sources.opt_5_4(ret_5_4: Maybe<&2, List<&2, String>>) -> List<&2, String>:
  match ret_5_4:
    case None{}:
      []
    case Some{ret_5_4}:
      ret_5_4

def fm_sources.opt_3_4(m: Maybe<&2, Py.Match>) -> List<&2, String>:
  match m:
    case None{}:
      []
    case Some{m}:
      ret_5_4 = {fm_sources.for_5_4(String.splitlines(Py.group(m, 1n)), Continue{None{}}) : Maybe<&2, List<&2, String>>}
      fm_sources.opt_5_4(ret_5_4)

def fm_sources(text: String) -> List<&2, String>:
  m = {Py.search(text, "^---\\n(.*?)\\n---", "s") : Maybe<&2, Py.Match>}
  fm_sources.opt_3_4(m)
```

Reading it against the Python:
- The `if not m: return []` is `opt_3_4`.
- The loop is `for_5_4`. Its state starts at `Continue{None{}}`, and it stops at the first `sources:` line with `Some` of the answer.
- Both `return`s inside the loop are `Stop{Some{…}}`, in `if_8_12`.
- The final `return []` is the `None` arm of `opt_5_4`.
- The comprehension is `comp_9_23`, head first.
- `+v` is affine because `v` is read twice (the test and one arm).

## Span-map notes

The file carries 53 span rows (`emitted l:c-l:c <- py l:c-l:c Node : type`). Each row was sliced out of both texts and checked to name the emitted text and the Python text it claims. The full map is the `#|` block of `tests/translator/emit_fm_sources.bend`. Excerpt:

```
# 56:53-56:92 <- py 9:54-9:61 Prim String.drop_end : String
# 56:69-56:87 <- py 9:54-9:61 Prim String.drop : String
# 66:15-66:22 <- py 6:8-10:22 Var ret_5_4 : Maybe<&2, List<&2, String>>
# 84:6-84:13 <- py 5:4-10:22 Return : List<&2, String>
# 91:81-91:87 <- py 5:4-10:22 Lit None{} : Maybe<&2, List<&2, String>>
# 95:7-95:49 <- py 2:8-2:50 Prim Py.search : Maybe<&2, Py.Match>
# 95:17-95:21 <- py 2:39-2:43 Var text : String
# 95:23-95:43 <- py 2:18-2:37 Lit "^---\\n(.*?)\\n---" : String
# 95:45-95:48 <- py 2:45-2:49 Lit "s" : String
```

- **One slice, two primitives.** `v[1:-1]` is `drop_end(drop(v, 1), 1)`, and both rows map to the whole subscript `9:54-9:61`. The literals keep their own spans (`9:56`, `9:59`).
- **The flag.** `Lit "s"` maps to the attribute `re.S` (`2:45-2:49`): the kernel grants that literal only because the elaborator read it off `re.S`.
- **Argument order.** `Py.search(subject, pattern, flag)` reverses Python's `(pattern, subject, flag)`. This is sound only because both arguments are pure and total, as with T2's `in`.
- **The synthetic name `ret_5_4`.** Its let, fold, initial `None{}`, final `Opt` and final `Return` all map to the whole loop (`5:4-10:22`). The `Continue{ret_5_4}` read maps to the `if` statement whose false arm it is (`6:8-10:22`).
- **Stop rows.** `Stop` and `Some` rows share the `Some{…}` payload span. The `Stop{…}` wrapper is structure, as in T2.
- **Return rows.** Two `Return … []` rows name `[]`: the one inside `if not m` (`4:8`) and the one after the loop (`11:4`).

## Judge output

```
$ python3 tests/translator/judge.py --demo fm_sources
source   /home/omen/Documents/Project/llm-wiki/tools/synapse.py:77 fm_sources sha256 e40787adf3abbb71 (ast extraction; module never imported)
fixtures 7 literal examples + 27 contract edges + 160 generated (seed 20260919) = 194
C1 checker acceptance : ok (no hole/open goal/@unsafe; strict check; lanes check+interpret+js+c all ran)
C2 source parity      : ok interpret 194/194 js 194/194 c 194/194; lanes identical: True
C3 theorem status     : tested fragment, no theorem. The early return is a Step fold of Maybe (Stop{Some{v}}), then a match on the fold's value; the comprehension is a recursive helper, head first. The translation rests on the primitive contracts (re.search/m.group = Py.search/Py.group on Base's Regex, splitlines, split, strip, the slices), assumed like SOUNDNESS.md A3 and only tested here; group 1 is granted because the kernel reads it off the parsed pattern. The source has no doctests, so no law is stated for it.
controls              : ok (injected hole rejected by C1; translation with a greedy group rejected by C2)
fm_sources: C1 ok · C2 194/194 · C3 tested-fragment
```

The other three demos are unchanged: `normalize_stem: C1 ok · C2 191/191`, `repo_of: C1 ok · C2 186/186`, `first_dash: C1 ok · C2 168/168 · C3 tested-fragment + 2/2 closed doctest laws`. `emit_normalize.bend` and `emit_repo_of.bend` were not re-pinned: T1/T2 emission is byte-identical.

The `fm_sources` oracle runs the extracted def alone with `__builtins__ = {}` and `re` as its only global.

The edges cover:
- the earliest closing delimiter
- `^` without `re.M` (`x---`, a leading `\n`)
- `---\n---`: no match, the group cannot reuse the opening newline
- an empty group
- a `sources:` line after the frontmatter
- the first of two `sources:` lines
- an indented `sources:`
- splitlines on `\r\n`, `\r`, `\v` and `\f`
- `[]` → `[""]`, and `sources:` with no value → `[""]`
- `[a,,b]`, quotes kept by `strip('"')` only at the ends, `'b'` not stripped
- `[a]x`, `a:b` (the split is once)
- `--` and `----` closings
- a 20-line frontmatter

The generator draws frontmatter from labeled lines plus random `sources:` tails over the whole value contract, separated by the splitlines boundaries.

The greedy control (`(.*)` for `(.*?)`) must fail C2, and it does (e.g. `---\nx: 1\n---\nsources: b\n---`: the lazy group ends at the first delimiter and gives `[]`, the greedy one reaches `sources: b`).

## Tests

| file | what |
|---|---|
| `emit_normalize.bend`, `emit_repo_of.bend` | T1/T2 pins, untouched, still byte-identical |
| `emit_fm_sources.bend` | new: the emitted `fm_sources` + span map, four lanes |
| `run.sh` | runs all four judge demos |
| `refuse.bend` | re-pinned, 102 rows (details below) |
| `ir_forged.bend` | re-pinned, 86 rows (details below) |

**Changes to earlier `refuse.bend` rows.**
- T1's "arity" row now uses `s.lower('x')`, because `s.strip('x')` is a contract now.
- T2's "early return" row still refuses, now for the right reason: "a loop that returns must not also assign a name bound before it".

**New T3 rows in `refuse.bend`: 48.** 9 are emitted positive controls, all at an exact position:

| control | what it shows |
|---|---|
| group | `m.group(1)` on a narrowed match |
| comprehension | `[e for x in xs]` |
| list | a list display |
| slices | the three slice forms |
| slice name | `s[len(s):]` |
| split | `s.split(',')` |
| strip chars | `s.strip('"')` |
| early return | `return` inside a loop |
| return then rest | a returning `if` followed by statements |

The other 39 are positioned refusals:
- **`re` access:** `re` not imported or aliased; no flag or another flag (reported as "unresolved name re", see deviations).
- **`group`:** group 0, absent, optional, lazy `*?`, on one side or both sides of `|`, narrowed and then the subject rebound.
- **patterns:** a pattern that does not compile, a pattern name, an escape in the pattern literal, `.group` on the unnarrowed Optional.
- **binding names:** the def binds `re` or `len`.
- **comprehensions:** one with an `if`, with two generators, with a bound target, over `str`, of the wrong type.
- **lists:** a mixed-type list, `[]` in a `str` def.
- **slices:** `[:-0]` (kernel), `[:2]`, `[-1:]`, a step.
- **`split` / `splitlines`:** `split('')` or `split(name)` (kernel), `split()`, `splitlines(True)`.
- **early returns:** return and accumulate, the name `ret_L_C` already taken or read, an `if` that falls through then a return, a loop that returns with a path that falls off, return in `for…else`, return from a nested loop.

**New T3 rows in `ir_forged.bend`: 38** (7 honest controls: list, empty list, comp, group, drop, drop end, early return). The 31 forged IRs are all refused by kernel recompute:
- **lists:** mixed types, a non-list type, a list that returns.
- **comprehensions:** over `str`, the wrong type, the item named like a param, the item unbound, a body that returns, stops or lets, and a fact used inside the body (facts drop at the item).
- **`group`:** no took-fact, group 0, an optional group, a group on one side of `|`, the fact after a let in between, `group` with no search.
- **facts:** a fact spelled as a call.
- **`search`:** a pattern that does not compile, another flag, the flag as a name, the pattern as a name.
- **`drop_end`:** `0`, a leading zero, a name.
- **`split_on`:** the separator as a name, an empty separator.
- **early return:** the `None` arm reads the fold's name, the payload is unwrapped (no `Some`), the `Some` has the wrong type, a Stop outside a step.

## Measurements (cap readings)

| file | bytes | ttok | cap (`gates/repo.ts`) |
|---|---|---|---|
| `demos/python/translate.bend` | 82,750 | 26,952 | 64,000 (over on bytes, so the ttok reading applies: **26,952 / 64,000**) |
| `tests/translator/judge.py` | 26,611 | 7,515 | 16,000 (ttok reading) |
| `tests/translator/ir_forged.bend` | 20,379 | 7,000 | 16,000 (ttok reading) |
| `tests/translator/refuse.bend` | 18,287 | 5,595 | 16,000 (ttok reading) |
| `tests/translator/emit_fm_sources.bend` | 7,600 | 3,082 | 16,000 (passes on bytes) |
| `tests/translator/run.sh` | 4,067 | 1,297 | 16,000 (passes on bytes) |

`translate.bend` grew by 19,461 bytes / 6,391 ttok over T2.

New paths are `tests/translator/emit_fm_sources.bend` and `docs/omen/lanes/translator-t3.md`. Both are matched by existing allow rules (`tests/translator/**`, `docs/omen/**`), so there was **no gate rejection**.

Gates before the final commit, with nothing skipped:

| gate | result |
|---|---|
| `bun gates/repo.ts` | **PASS: 45 / 45** |
| `bash tests/translator/run.sh` | **20 / 0** |
| `bash tests/lint/run.sh totality` | **20 / 0** |
| `bash tests/lint/run.sh alias` | **16 / 0** |
| `bash tests/parser/run.sh` | **108 / 0** |

## Deviations (honest list)

1. **`ICall` is still refused.** The kernel says "IR node Call is not emittable in T3", and the elaborator says "outside the fragment: Call". T2's hand-off put user calls under "needs Lint's call graph + a termination story", and `fm_sources` calls no user def, so no slice of T3 needed it and nothing may claim it.
2. **A loop that returns cannot also accumulate.** The early-return fold's state is the function's `Maybe<R>` alone. A body that both returns and assigns an outer name needs a pair state and is refused.
3. **Regex scope.**
   - Only the 3-argument `re.search(p, s, re.S)` is supported, with `p` a literal, and only under the stub's `import re`.
   - The kernel grants flag `"s"` only (Base's `Regex.compile` would take others; they are not contracted).
   - `re.match`, `re.findall`, `re.M` and 2-argument search all stay refused.
   - The elaborator's messages for the refused forms are imprecise ("unresolved name re" for a missing or other flag), but they are positioned.
4. **`group` is conservative.** `must` grants only groups that take part in every match. Group 0 (always set) is refused too; that is sound, just not complete.
5. **Slices.** Only `[i:]`, `[:-k]` and `[i:-k]` on `str` are supported, with `k` a positive literal. Lists are not sliced.
6. **Comprehensions.** One generator, no `if`, a fresh target, over a list.
7. **Narrowing a match is `if not m:` only.** It must return, then the rest runs under `Some{m}`.
8. **Facts are no longer dropped at every binder.** This reverses T2 item 6. `IMaybe`'s some arm now keeps the outer facts: the took-fact made at `m = re.search(…)` must reach `m.group(1)` inside `Some{m}`. It is sound because the arm rebinds `m` to its own payload, the same value narrowed, and no `str` fact can mention an Optional name. Let, fold and comprehension binders still drop every fact. The "narrowed after rebind" refusal covers a rebind of the subject.
9. **`TInt` flows further than T2 item 4 allowed.** T2 allowed it only into `>`. It now also flows into slice bounds and `group`, and decimal literals make one. Python `int` is still not `Nat` in general: an `int` annotation stays refused.
10. **`[]` is typed from the declared return type.** A `[]` anywhere else is refused.
11. **Binding `re` or `len` is refused**, because the def's scope would shadow the builtin.
12. **`Py.strip_start` uses `Bool.pick`**, which evaluates both sides. It stays total, but costs O(len) per call instead of O(stripped). This is in the prelude only; T2's no-`Bool.pick` rule is about translated operands.
    - The lazy forms are unavailable. A helper def that matches the test and calls back is mutual recursion, which user code cannot declare (an unfilled `law` is refused outside Base). An inline `match` on the test is refused by the checker ("a match cannot scrutinize a computed value"); this was checked on this tree.
13. **`Py.Match` is a Data wrapper** (`PyMatch{s, m}`), because a pair `String & Match` is a Type and `Maybe<&2, T>` needs Data. It keeps the subject that Python keeps as `m.string`.
14. **The seed is still date-based** (20260919), shared with T1/T2.
15. **The judge's `re` assumption.** The stub's `import re` is a labeled assumption that `re` is the stdlib module. The judge's `ast` check proves only that the source module binds `re` by a top-level `import re`, not what `sys.modules` holds at run time.

## What `optimize.bend` (tier ③) inherits

These are candidates only. None is applied; this report records them per the plan's faithful-mode line.

1. **The first rule is intact.** The `repo_of` `s + '-'` hoist targets `String.starts_with(tail, String.append(s, "-"))` in `repo_of.or_7_11` (py `7:24-7:48`), and that text is byte-identical after T3. T3 adds `IList`, `IMap` and the early-return fold shape. A rule's IR pattern must pass these through untouched, and because `IR.verify` recomputes them, a rewrite that damages one is refused by the same kernel as faithful output.
2. **Regex → two literal finds** (`fm_sources`). With `re.S` and no `re.M`, `^---\n(.*?)\n---` matches iff the text starts with `---\n` and the first `\n---` at index ≥ 4 exists. The group is the text in between.
   - Side-condition trap: in `---\n---` the only `\n---` is at 3, overlapping the opener, and the regex does not match. The judge has this edge.
   - Evidence: a Proven grade needs a law relating `Regex.find` to `String.find`, which does not exist yet, so this is Tested (kind 3) until one does.
   - C5 has something real to measure: no compile, no backtracking engine per call.
3. **Early-return loop → `List.find`.** `for_5_4` finds the first line starting with `sources:` and then applies the tail. This is the plan's Q4 (`for`→`List.find`, ② or ③), now with a first real instance. The order is preserved (head first, stop at first), so there is no tie clause to prove.
4. **A parallel map for `comp_9_23`.** The elements are independent, and the body is uniform, pure and total, so the map is legal with no combiner law. It is expected to be legal-unprofitable: the lists are a handful of short strings, and C5 should reject it, like the plan's GPU maps.
5. **Views.** `drop`, `drop_end`, `trim`, `split_on`, `Py.after` and `Regex.group` all return views into `text` (`lanes/strings-adaptive.md`), so the returned list keeps the whole document alive. Whether a `String.copy` compaction at the return pays is a Lint **A** ownership decision, which makes it ③.
6. **`Py.strip`'s eager `Bool.pick`** (deviation 12) is a prelude cost, not a program-specific one. Its fix belongs to ②/Base (a lazy `String.strip_chars` in Base, or checker support for a match on a computed test), not to a rewrite rule.
