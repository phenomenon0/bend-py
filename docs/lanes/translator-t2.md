# Translator lane — T2 report (fable, 2026-09-19)

Branch `lane-translator-t2`, worktree `bend-work-translator-t2`, off `omen` @ `1bc3d961` (T1 integrated).
T2 = the control idioms: `ILet`, `IBranch`, `IFold`, `None`→`Maybe`, the restricted doctest→law adapter, and the second judge demo `repo_of`.
Semantic pin: CPython 3.11.15. Acceptance: `bash tests/translator/run.sh` → **`Translator PASS: 16, FAIL: 0`**, which ends with the three judge demos:
**`normalize_stem: C1 ok · C2 191/191`**, **`repo_of: C1 ok · C2 186/186`**, **`first_dash: C1 ok · C2 168/168 · 2/2 closed doctest laws`** (all C3 tested-fragment).

Untouched, as instructed: `bend2/**`, `gates/**`, `tests/caps.sh`, every other namespace, every other file in `demos/python/`. No pushes.

## Slices

| slice | commit | content |
|---|---|---|
| T2 core | `42bd8c8b` | `demos/python/translate.bend`: Let / Branch / Fold / Maybe / guarded primitive / signature stub, kernel + renderer |
| T2 tests | `1b5078d5` | `judge.py` (`repo_of`, `first_dash`, doctest adapter), `run.sh`, `emit_repo_of.bend`, `fixtures.py`, `refuse.bend`, `ir_forged.bend` |
| report | this commit | `docs/omen/lanes/translator-t2.md` |

## What changed

`demos/python/translate.bend` 495 → 1396 lines. Same three trust zones as T1 (untrusted `elaborate`, the `verify` kernel that recomputes from the IR alone, `emit = verify then render`).

- **IR.** `Ty` + `TBad`; `Ir` + `ISome{val}`, `IMaybe{on, none, some}` (Optional test/narrowing), `IStop{val}` (`break`). `Contract` grows to 9 fields: `pre` (a guard primitive that must be a *known fact* where the primitive is used) and `src` (the text of a helper def the emitted file must carry).
- **`ILet` — affine discipline.** `x = e` emits `x = {e : T}`. The renderer counts reads of every binder in its scope (`reads`; a helper call that captures the name counts once) and writes `+x` **iff reads ≥ 2**; a single-use name stays linear. Same rule for parameters, helper parameters, the fold item and the `Some{x}` pattern binder. In `repo_of`: `+pid` (guard + split), `+tail` (captured by every fold step), `+s`, `+best` inside the step; `slugs`, `best` at the tail stay linear. The Bend checker is the judge of this: a missing `+` is a check error, and C1 runs strict.
- **`IBranch` — never eager.** `and` / `or` / `if` / `x if c else y` all become a helper def `f.<kind>_<line>_<col>(_c: Bool, captures…)` that matches `_c`; only the test is evaluated at the call site, the untaken side lives in an arm that does not run. `a or b` = `True{}` / `b`; `a and b` = `b` / `False{}`. No `Bool.pick`, no `||`/`&&` on translated operands. Captures are computed (`caps`), sorted by first use, typed from the environment.
- **`IFold` — `for` over a list.** `acc = fold(item, xs, acc0, step)` → a recursive helper `f.for_l_c(_xs, acc, captures…)` matching `_xs`; items are visited head first, the step is evaluated once per item, in order. With `break` the helper takes a `Step` state and matches `_xs _st`: `Stop{acc}` returns without touching the rest (items after the stop are **not** evaluated); the `Step` type is emitted in the file's prelude only when used.
- **`None` → `Maybe`.** `T | None` = `Maybe<&2, T>`; the literal `None` takes the declared Optional type (from the return annotation or the let it rebinds); a `T` value flowing into an Optional slot is lifted to `ISome`. The two narrowing forms `X is None or E` and `X is not None and E` become `match X` with `Some{X}` rebinding the name at `T` inside `E` (so `len(best)` is `String.length(best)` on a `String`).
- **Guarded partial primitive.** `s.split(sep, 1)[1]` is total only when `sep in s`. The contract `Py.after` has `pre = String.contains`; the elaborator and — independently — the kernel keep a fact list (`known`: learned from `if t:` arms through `not`, `or` (false side), `and` (true side)); the primitive is granted only if `String.contains(s, sep)` on the *same variable and same non-empty literal* is known. Facts are dropped at every binder (a rebound `s` forgets everything). `repo_of` gets the fact from the false arm of `pid.startswith('SRC-') or '.' not in pid`.
- **Signature stub.** `repo_of` is unannotated in the source. `translate_as(source, sig, cs, name)` takes the reviewed signature as a separate stub (`def repo_of(pid: str, slugs: list[str]) -> str | None: pass`; CLI: `PY_SIG=<path>`); parameter names/spans come from the source, types from the stub, and the two must agree on names and arity. `translate = translate_as` with no stub (T1 path, byte-identical).

Contracts shipped (value contract = printable ASCII + six ASCII whitespace; all pure + total, the last one under its guard):

| Python | Bend | | Python | Bend |
|---|---|---|---|---|
| `s.strip()` | `String.trim` | | `a == b` (str) | `String.eq` |
| `s.lower()` | `String.to_lower` | | `a + b` (str) | `String.append` |
| `s.replace(a, b)` | `String.replace` | | `len(s)` | `String.length` : Nat |
| `s.startswith(p)` | `String.starts_with` | | `m > n` (len results) | `Nat.is_gt` |
| `x in s` / `x not in s` | `String.contains` (+ `Bool.not`) | | `not b` | `Bool.not` |
| `s.split(sep, 1)[1]` **if `sep in s` known** | `Py.after` = `snd(snd(String.partition))` | | | |

## The emitted Bend for `repo_of` (verbatim)

Source (`~/Documents/Project/llm-wiki/tools/overview.py:15-23`, sha256 `295c526c1ee5ec2b…`, extracted by `ast`, module never imported):

```python
def repo_of(pid, slugs):
    if pid.startswith('SRC-') or '.' not in pid:
        return None
    tail = pid.split('.', 1)[1]
    best = None
    for s in slugs:
        if tail == s or tail.startswith(s + '-'):
            best = s if best is None or len(s) > len(best) else best
    return best
```

`python3 tests/translator/judge.py --demo repo_of --show` (also pinned in `tests/translator/emit_repo_of.bend`):

```python
# Faithful translation (tiers 1-2) of Python `repo_of` 1:0-9:15 by demos/python/translate.bend.
import Base

def Py.after(+s: String, +sep: String) -> String:
  Pair.snd(String, String, Pair.snd(String, String & String, String.partition(s, sep)))

def repo_of.or_2_7(_c: Bool, pid: String) -> Bool:
  match _c:
    case True{}:
      True{}
    case False{}:
      Bool.not(String.contains(pid, "."))

def repo_of.or_7_11(_c: Bool, s: String, tail: String) -> Bool:
  match _c:
    case True{}:
      True{}
    case False{}:
      String.starts_with(tail, String.append(s, "-"))

def repo_of.opt_8_24(best: Maybe<&2, String>, s: String) -> Bool:
  match best:
    case None{}:
      True{}
    case Some{best}:
      Nat.is_gt(String.length(s), String.length(best))

def repo_of.if_8_19(_c: Bool, best: Maybe<&2, String>, s: String) -> Maybe<&2, String>:
  match _c:
    case True{}:
      Some{s}
    case False{}:
      best

def repo_of.if_7_8(_c: Bool, +best: Maybe<&2, String>, +s: String) -> Maybe<&2, String>:
  match _c:
    case True{}:
      best = {repo_of.if_8_19(repo_of.opt_8_24(best, s), best, s) : Maybe<&2, String>}
      best
    case False{}:
      best

def repo_of.for_6_4(_xs: List<&2, String>, best: Maybe<&2, String>, +tail: String) -> Maybe<&2, String>:
  match _xs:
    case Nil{}:
      best
    case Con{+s, _rest}:
      repo_of.for_6_4(_rest, repo_of.if_7_8(repo_of.or_7_11(String.eq(tail, s), s, tail), best, s), tail)

def repo_of.if_2_4(_c: Bool, pid: String, slugs: List<&2, String>) -> Maybe<&2, String>:
  match _c:
    case True{}:
      None{}
    case False{}:
      tail = {Py.after(pid, ".") : String}
      best = {None{} : Maybe<&2, String>}
      best = {repo_of.for_6_4(slugs, best, tail) : Maybe<&2, String>}
      best

def repo_of(+pid: String, slugs: List<&2, String>) -> Maybe<&2, String>:
  repo_of.if_2_4(repo_of.or_2_7(String.starts_with(pid, "SRC-"), pid), pid, slugs)
```

## Span-map notes

The file carries 52 span rows (`emitted l:c-l:c <- py l:c-l:c Node : type`); every row was checked to slice exactly the emitted text it names. The full map is the `#|` block of `tests/translator/emit_repo_of.bend`. Excerpt:

```
# spans: emitted Bend <- Python source, node : type
# 31:6-31:13 <- py 8:19-8:20 Some : Maybe<&2, String>
# 38:6-38:86 <- py 8:12-8:68 Let best : Maybe<&2, String>
# 38:14-38:65 <- py 8:19-8:68 Branch if : Maybe<&2, String>
# 38:30-38:55 <- py 8:24-8:58 Opt best : Bool
# 48:29-48:98 <- py 7:8-8:68 Branch if : Maybe<&2, String>
# 48:44-48:88 <- py 7:11-7:48 Branch or : Bool
# 55:6-55:42 <- py 4:4-4:31 Let tail : String
# 55:14-55:32 <- py 4:11-4:31 Prim Py.after : String
# 56:6-56:41 <- py 5:4-5:15 Let best : Maybe<&2, String>
# 57:6-57:69 <- py 6:4-8:68 Let best : Maybe<&2, String>
# 57:14-57:48 <- py 6:4-8:68 Fold s -> best : Maybe<&2, String>
# 60:12-60:24 <- py 1:12-1:15 Param pid : String
# 60:26-60:49 <- py 1:17-1:22 Param slugs : List<&2, String>
# 61:2-61:82 <- py 2:4-3:19 Branch if : Maybe<&2, String>
# 61:17-61:69 <- py 2:7-2:47 Branch or : Bool
```

- Rows are in emitted order, so helper bodies come first and the entry def last; a node that became a helper has **one** row at its call site (`Branch`/`Opt`/`Fold`), and its arms have rows inside the helper def. Python spans are untouched parser `_loc`s, so `or` at py 2:7-2:47 maps to the call at 61:17-61:69 *and* its right operand 2:33-2:47 maps into the helper at 12:6-12:41.
- Helper names encode the Python position (`repo_of.or_2_7` = the `or` at line 2 col 7), so a Bend checker error inside a helper is already a Python position; the kernel refuses two helpers with one name.
- Synthetic nodes reuse the span of what caused them: `True{}` of an `or` carries the whole `or`; `Some{s}` carries `s`; the fold's accumulator read carries the `for`.
- `x not in s` maps to **two** rows (`Bool.not` and `String.contains`, same Python span); `in` swaps operand order in the emitted call (`String.contains(pid, ".")`), both operands are pure and total, so the order is unobservable — the rows keep each operand's own span.
- A `Let` row's type is the bound value's type, a `Return` row the function's.

## Judge output

```
$ python3 tests/translator/judge.py --demo repo_of
source   ~/Documents/Project/llm-wiki/tools/overview.py:15 repo_of sha256 295c526c1ee5ec2b (ast extraction; module never imported)
fixtures 10 literal examples + 16 contract edges + 160 generated (seed 20260919) = 186
C1 checker acceptance : ok (no hole/open goal/@unsafe; strict check; lanes check+interpret+js+c all ran)
C2 source parity      : ok interpret 186/186 js 186/186 c 186/186; lanes identical: True
C3 theorem status     : tested fragment, no theorem. if/or/not-in, Optional narrowing and the for-fold are emitted as helper matches; the translation rests on the primitive contracts (…) assumed like SOUNDNESS.md A3 and only tested here. The source has no doctests, so no law is stated for it.
controls              : ok (injected hole rejected by C1; translation without the '-' boundary rejected by C2)
repo_of: C1 ok · C2 186/186 · C3 tested-fragment

$ python3 tests/translator/judge.py --demo first_dash
source   tests/translator/fixtures.py:9 first_dash sha256 9ee30afe73e14c99 (ast extraction; module never imported)
fixtures 4 literal examples + 4 contract edges + 160 generated (seed 20260919) = 168
C1 checker acceptance : ok (…)
C2 source parity      : ok interpret 168/168 js 168/168 c 168/168; lanes identical: True
C3 theorem status     : tested fragment, no theorem. `break` is a Step fold (Continue/Stop): items after the stop are not evaluated. Its closed doctests are checked laws (closed instances, not a universal theorem).
doctest laws          : ok 2 closed literal-call examples checked as laws ({==}, by the checker); 2 outside the restriction, skipped and not approximated
controls              : ok (injected hole rejected by C1; translation without break rejected by C2; falsified doctest laws rejected by the checker)
first_dash: C1 ok · C2 168/168 · C3 tested-fragment + 2/2 closed doctest laws
```

`normalize_stem` is unchanged: `C1 ok · C2 191/191 · C3 tested-fragment`, emitted text byte-identical to T1 (`emit_normalize.bend` was not re-pinned).
The `repo_of` oracle runs the extracted def alone with `__builtins__ = {"len": len}`. Labeled fixtures cover: longest prefix in both list orders, first-on-tie (strict `>`), `SRC-` guard and its case-sensitivity, no dot, `tail == s`, prefix without the `-` boundary, split-once (tail keeps later dots), empty slug, empty list.

## The doctest → closed-equality-law adapter (restricted, on purpose)

In `judge.py` (`doctest_laws`, `law_file`). A doctest becomes a law **only** when it is a closed literal call: `>>> f(<literals>)` of the demo's own def, positional args that `ast.literal_eval` reads as `str` / `list[str]` matching the signature, and a want that reads as a literal of the return type (no output = `None`). Each becomes

```python
law doctest_0:
  {T.first_dash(["a", "-b", "-c"]) == Some{"-b"} : Maybe<&2, String>}

def doctest_0():
  {==}
```

and the strict checker decides it by computation. Doctest text is parsed (`doctest.DocTestParser` + `ast`), **never executed**. Everything else — `… is None`, a nested call like `sorted([...])`, names, keywords, expected exceptions — is counted as *skipped* and reported, not approximated. The oracle must also agree with each law's want before anything else is judged. Control: every want falsified → the checker must refuse. A closed instance is not a universal theorem and the judge's C3 line says so; a law failure fails the judge but is reported apart from C1/C2.
`repo_of` has no doctests, so the adapter is exercised on the labeled fixture `tests/translator/fixtures.py::first_dash` (2 closed, 2 deliberately outside).

## Tests

| file | what |
|---|---|
| `emit_normalize.bend` | T1 pin, untouched, still byte-identical |
| `emit_repo_of.bend` | new: the emitted `repo_of` + span map, four lanes |
| `refuse.bend` | re-pinned: T1's positioned refusals + T2 — 4 positive controls (loop, break, guarded split, guard via `and`) and 28 new positioned refusals: unguarded split, guard on another sep / rebound / via `or` / empty sep, `split` without maxsplit, bare index, truthiness `if`/`or`, early return in a loop, no / two accumulators, `for…else`, bound loop target, nested `for`, statement after the `if` in a loop, `for` over `str`, `break` outside, `while`, path that falls off, `is None` on a non-Optional, `None` at a non-Optional, retyped name, user call, comparison chain, augassign, tuple target, `len` escaping as a value |
| `ir_forged.bend` | re-pinned, 48 rows: T1's 14 (its three "Let/Branch/Fold not emittable" rows became real cases; `call` now says T2) + 34 T2 rows — 6 honest controls (let, branch, guarded, fold, fold stop, maybe) and 28 forged IRs refused by kernel recompute (41 refused in all): let in argument position / retyped / reserved name / out of scope; return in argument or inside a step; branch on non-Bool / arm type / arm that falls; duplicate helper names; `Py.after` with guard in the wrong arm / absent / other sep / empty sep / rebound variable; fold over non-list / item = acc / step type / step rebinding a capture; stop outside a step / of the wrong type; Optional match on a `str` / none-arm reading the name / unnarrowed some-arm / arm type; `Some` of the wrong type; `None` at Bool; non-literal Bool |

## Measurements (cap readings)

| file | bytes | ttok | cap (`gates/repo.ts`) |
|---|---|---|---|
| `demos/python/translate.bend` | 63,289 | 20,561 | 64,000 (passes on bytes; **711 bytes** of byte-headroom, then the ttok reading applies: 20,561 / 64,000) |
| `tests/translator/judge.py` | 20,513 | 5,756 | 16,000 |
| `tests/translator/ir_forged.bend` | 11,251 | 3,913 | 16,000 |
| `tests/translator/refuse.bend` | 9,765 | 2,955 | 16,000 |
| `tests/translator/emit_repo_of.bend` | 5,858 | 2,381 | 16,000 |
| `tests/translator/run.sh` | 4,044 | 1,292 | 16,000 |
| `tests/translator/fixtures.py` | 708 | 184 | 16,000 |

New paths: `tests/translator/emit_repo_of.bend`, `tests/translator/fixtures.py`, `docs/omen/lanes/translator-t2.md` — all matched by existing allow rules (`tests/translator/**`, `docs/omen/**`); **no gate rejection**. Gates before the final commit: `bun gates/repo.ts` **PASS: 45 / 45** (new files tracked) · `bash tests/translator/run.sh` **16 / 0** · `bash tests/lint/run.sh totality` **20 / 0** · `bash tests/lint/run.sh alias` **16 / 0** · `bash tests/parser/run.sh` **108 / 0**. Nothing skipped.

## Deviations (honest list)

1. **`Continue`/`Stop`, not `Done`/`Continue`.** Bend constructors are global and Base's `Result` owns `Done`; the emitted `Step` type uses `Stop`.
2. **Early `return` inside a loop is refused** ("outside the fragment (T3)"), positioned. `break` is implemented (Step fold); early return needs a second Step payload (result vs accumulator) and `repo_of` does not use it. The brief listed it; it is not done.
3. **`ICall` is still refused** by the kernel ("not emittable in T2"): no user-function call in either demo, nothing may claim it.
4. **`int` annotations are refused.** `TInt` exists only as the type of `len(…)`, rendered `Nat`, and may only flow into `>`; a `len` result escaping as a value is refused (Python `int` ≠ `Nat` in general).
5. **Narrowing is two forms only**: `X is None or E`, `X is not None and E`. `if x is None:` as a statement, walrus, `==  None` are refused.
6. **Facts are dropped at every binder** (let, fold, Some-pattern), not just binders of the guarded variable — coarser than needed, never unsound.
7. **One accumulator per loop**, the `if` must be the last statement of a loop body, no nested `for`, no `for…else`, loop target must be fresh.
8. **Signature stub** for unannotated defs is a reviewed input, like the contracts; with a stub the source must be fully unannotated (no mixing).
9. **`in` operand order** is swapped in the emitted call (see span notes); sound only because both operands are pure and total — the kernel checks that.
10. `repo_of` has no doctests; the adapter's evidence is the labeled fixture, not real-world code.
11. `first_dash` and the refuse/forge cases are the only coverage of `break`; no llm-wiki def with `break` was judged.

## What T3 gets

- Early `return` in a loop: `Step` with a distinct result payload (`Stop{r}` of the function's type vs `Continue{acc}`), then the tail continuation matches the fold's outcome. The kernel position rule (`PStep`) already isolates where it may appear.
- `ICall` for user defs in the same closed module (needs Lint's call graph + a termination story); multiple accumulators (tuple/record state); nested folds; `if x is None:` statement narrowing; `int` as a real type with a contract.
- Finer fact invalidation (only binders of the guarded variable), and more guarded partials on the `pre` mechanism (`s[0]` under `s != ""`, `xs[0]`, `dict[k]` under `k in d`).
- The adapter: universal laws from non-closed doctests are tier ③ and stay out of faithful mode; T3 could add `bool` / `list[str]` wants and keyword-free multi-def doctests.
