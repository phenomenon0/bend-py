# Translator lane — T1 report (fable, 2026-09-19)

Branch `lane-translator-t1`, worktree `bend-work-translator-t1`, off `omen` @ `86a88234` (L1 + L2 included).
Plans: `docs/omen/plans/translator-modes.md` (tiers ① ② only — faithful mode; no tier ③), `plan-astra-v2.md` §4/§6.
Semantic pin: CPython 3.11.15. Acceptance: `bash tests/translator/run.sh` → **`Translator PASS: 12, FAIL: 0`** (2:56 wall, re-run on the committed runner), which ends with
`python3 tests/translator/judge.py --demo normalize_stem` → **`normalize_stem: C1 ok · C2 191/191 · C3 tested-fragment`**.

## Slices

| slice | commit | content |
|---|---|---|
| T1 core | `83dd6307` | `demos/python/translate.bend` (495 lines): TypedIR, `elaborate`, `verify`, `emit`, `translate`, `main` |
| T1 tests | `68d01ac2` | `tests/translator/{judge.py,run.sh,emit_normalize.bend,refuse.bend,ir_forged.bend}`; kernel tightened (`IReturn` only at the root) |
| report | this commit | `docs/omen/lanes/translator-t1.md` |

Untouched, as instructed: `bend2/**`, `gates/**`, `tests/caps.sh`, every other namespace, every other file in `demos/python/` (imported, not edited). No pushes.

## Design

`translate = intake → lex → parse (the parser lane's S.Json wire AST) → elaborate → verify → render`. Three parts with different trust:

- **`elaborate(m, cs, name) → Result<Fn>`** — untrusted. Reuses Lint's facts for the closed-module and header conditions (`Lint.closed`, `Lint.header`), then
  accepts exactly: one top-level `def` with `str`-annotated simple parameters and a `-> str` return, an optional leading docstring, and exactly one `return e`,
  where `e` is a bound parameter `Name`, one plain string literal token (printable ASCII, no backslash, no inner quote, no adjacent-literal concatenation — read from the
  token spelling `_raw`, not from a decoded value), or a method call `recv.m(args…)` whose **receiver type, method, argument types** match a contract.
  Receiver is elaborated before arguments, arguments left to right (Python's order). Structural recursion is by fuel = AST weight, so the walk is total in Bend.
- **`verify(f, cs) → Result<Unit>`** — the kernel; trusts nothing the elaborator wrote. From the IR alone it recomputes: every `IVar` is a bound parameter at its declared type;
  every `ILit` is inside the literal contract; every `IPrim` is granted by a contract that is `pure` **and** `total` with exactly these argument types and this result type;
  every node and parameter has a span; identifiers are emittable; the body is one root `IReturn` whose value has the declared return type; the effect is `Pure`.
  `ICall`/`ILet`/`IBranch`/`IFold` are declared in the IR (the brief's node set) and **refused** by the kernel in T1 — nothing emits them yet, so nothing may claim them.
- **`emit(f, cs) = verify then render`** — there is no way to render an unverified `Fn` through the public path. The rendered file carries its own span map as comments.

TypedIR: `Ty = TBool | TStr | TInt | TList{of} | TMaybe{of}` · `Eff = Pure | Impure` ·
`Ir = IVar | ILit | IPrim | ICall | ILet | IBranch | IFold | IReturn | IArg/IEnd` (one ADT with chain constructors, the house answer to no mutual recursion), every node with `loc`
(`[line, col, line, col]`, the parser's `_loc`) and a type · `Fn{name, params, ret, eff, body, loc}` ·
`Contract{recv, method, args, ret, bend, pure, total}`.

Contracts shipped (the whole primitive table of T1; value contract = printable ASCII + the six ASCII whitespace):

| Python | Bend | note checked against `base.bend` |
|---|---|---|
| `str.strip()` | `String.trim` | `Char.is_space` = 32, 9–13: exactly CPython's ASCII whitespace |
| `str.lower()` | `String.to_lower` | ASCII-only in Bend; equal to CPython on the value contract only |
| `str.replace(str, str)` | `String.replace` | non-overlapping, left to right, all occurrences; the literal `old` is never empty in the demo |

Evaluation order, short-circuiting and first-on-tie: the fragment has no `and`/`or`/`if`/`min`/`max`, so there is nothing to short-circuit and no tie; order is preserved
structurally (receiver, then arguments, nested calls inside-out = Bend's strict call order) and is unobservable anyway, every primitive being pure and total. No `Bool.pick` is emitted; no helper match is needed yet.

## The emitted Bend for `normalize_stem` (verbatim)

Source (`~/Documents/Project/llm-wiki/tools/wiki.py:92`, extracted by `ast`, sha256 of the text `4af82c046d8931ed…`):

```python
def normalize_stem(s: str) -> str:
    """Normalize a page name to its file stem form."""
    return s.strip().lower().replace(" ", "-")
```

Emitted (`judge.py --demo normalize_stem --show`; pinned byte-for-byte in `tests/translator/emit_normalize.bend`):

```
# Faithful translation (tiers 1-2) of Python `normalize_stem` 1:0-3:46 by demos/python/translate.bend.
import Base

def normalize_stem(s: String) -> String:
  String.replace(String.to_lower(String.trim(s)), " ", "-")

# spans: emitted Bend <- Python source, node : type
# 4:19-4:28 <- py 1:19-1:25 Param s : String
# 5:2-5:59 <- py 3:4-3:46 Return : String
# 5:2-5:59 <- py 3:11-3:46 Prim String.replace : String
# 5:17-5:48 <- py 3:11-3:28 Prim String.to_lower : String
# 5:33-5:47 <- py 3:11-3:20 Prim String.trim : String
# 5:45-5:46 <- py 3:11-3:12 Var s : String
# 5:50-5:53 <- py 3:37-3:40 Lit " " : String
# 5:55-5:58 <- py 3:42-3:45 Lit "-" : String
```

## Spans mapping

Lines are 1-based, columns 0-based, end exclusive, both sides. Python positions are relative to the extracted def (add 91 lines for `wiki.py`).

| emitted Bend | Python | IR node | type | Python text |
|---|---|---|---|---|
| 4:19–4:28 | 1:19–1:25 | Param `s` | String | `s: str` |
| 5:2–5:59 | 3:4–3:46 | Return | String | `return s.strip().lower().replace(" ", "-")` |
| 5:2–5:59 | 3:11–3:46 | Prim `String.replace` | String | `s.strip().lower().replace(" ", "-")` |
| 5:17–5:48 | 3:11–3:28 | Prim `String.to_lower` | String | `s.strip().lower()` |
| 5:33–5:47 | 3:11–3:20 | Prim `String.trim` | String | `s.strip()` |
| 5:45–5:46 | 3:11–3:12 | Var `s` | String | `s` |
| 5:50–5:53 | 3:37–3:40 | Lit `" "` | String | `" "` |
| 5:55–5:58 | 3:42–3:45 | Lit `"-"` | String | `"-"` |

The Bend-side columns are computed by the renderer from the text it renders (`show` and `spans` walk the same IR), and the whole file is pinned in `emit_normalize.bend`, so a drift between text and map fails the suite.

## Judge output

```
source   /home/omen/Documents/Project/llm-wiki/tools/wiki.py:92 normalize_stem sha256 4af82c046d8931ed (ast extraction; module never imported)
fixtures 7 literal examples + 24 contract edges + 160 generated (seed 20260919) = 191
C1 checker acceptance : ok (no hole/open goal/@unsafe; strict check; lanes check+interpret+js+c all ran)
C2 source parity      : ok interpret 191/191 js 191/191 c 191/191; lanes identical: True
C3 theorem status     : tested fragment, no theorem. The for/if/None idioms are unused; the translation rests on three primitive contracts (str.strip/lower/replace = String.trim/to_lower/replace on the ASCII value contract), assumed like SOUNDNESS.md A3 and only tested here. Lint grades this def `ownership Unknown` (method call = dynamic call in T0/O0): B1-B3 are argued from `str` immutability (A1), a paper-argued candidate.
controls              : ok (injected hole rejected by C1; translation without strip rejected by C2)
normalize_stem: C1 ok · C2 191/191 · C3 tested-fragment
```

Safety posture: the judge `ast.parse`s `wiki.py` and takes one `FunctionDef` by `ast.get_source_segment`; **the module is never imported or executed**. The extracted text is sha256-pinned
(a changed source is re-reviewed, not re-judged) and is `exec`'d alone with `__builtins__ = {"str": str}`. The oracle must first agree with the 7 hand-written literal examples
(the source has a docstring and no doctest, so these are labeled contract fixtures) before its outputs are used as expectations for the edges and the seeded inputs.
Results cross the language boundary as code points, so no escaping convention is trusted. The two controls run on every invocation: a hole injected into the emitted text must trip C1's text check, and
the translation with `String.trim(s)` replaced by `s` must produce a different answer through the same comparison path.

Refusal evidence (both pinned `#|`, four lanes each):

- `refuse.bend` — 1 near-miss that emits (literal receiver) + 21 refusals, all positioned `error Unsupported L C …`: unknown method (`.title`), wrong arity, keyword argument,
  `str.lower(s)` spelling, builtin `len`, unresolved name, escaped literal, adjacent literals, unbound method, `IfExp`, `Assign`, statement after `return`, bare `return`,
  fall-through, untyped parameter, `int` parameter, non-`str` return, default value, open module (`import`), duplicate def, absent def.
- `ir_forged.bend` — 1 honest IR that emits + 16 forged IRs the kernel refuses: unknown primitive, wrong arity, wrong argument type, wrong result type, unbound name, out-of-contract literal,
  missing span, `Call`, `Let`, `Branch`, `Fold`, no return, wrong return type, `Impure` effect, unemittable identifier, and a contract table that itself lies (`pure = False`).

## Measurements

| file | ttok | bytes | gate cap |
|---|---|---|---|
| `demos/python/translate.bend` | 6373 | 19676 | 64000 — ok |
| `tests/translator/emit_normalize.bend` | 485 | 1379 | 16000 — ok |
| `tests/translator/ir_forged.bend` | 1442 | 4084 | 16000 — ok |
| `tests/translator/refuse.bend` | 1092 | 3620 | 16000 — ok |
| `tests/translator/judge.py` | 3009 | 10695 | **not in the allow list** |
| `tests/translator/run.sh` | 1253 | 3896 | **not in the allow list** |

**Repo gate: `bun gates/repo.ts` → `PASS: 43 / 45`**, the two failures being exactly:

```
FAIL tests/translator/judge.py: not in the allow list
FAIL tests/translator/run.sh: not in the allow list
```

`gates/repo.ts:71` allows `tests/(regex|parser|lint|translate)/…` (and `.gitignore` has `tests/translate/_out/`), while the brief names `tests/translator/`. I followed the brief and did not touch `gates/**`;
the orchestrator either adds `translator` to that alternation (both files are under its 16000 cap) or renames the directory. The three `.bend` files pass under the generic `tests/<ns>/*.bend` rule.
The runner writes nothing in-tree (its control fixture lives in the `mktemp` dir), so no `_out` ignore entry is needed.

Neighbor suites, run after the last code edit: `bash tests/lint/run.sh totality` → **`Lint PASS: 20, FAIL: 0`** (3:04); `bash tests/lint/run.sh alias` → **`Lint PASS: 16, FAIL: 0`** (2:16);
`bash tests/parser/run.sh` → **`Parser PASS: 108, FAIL: 0`** (10:11). `bash tests/caps.sh`: 32 ok, no OVER (it does not list the translator files; their readings are the table above, by the same `ttok`).

## Deviations (honest list)

1. **C3 is "tested fragment", not a theorem.** Nothing here is mechanized. The kernel's guarantee — *emitted ⇒ every primitive is contract-granted, every name bound, every node typed and spanned* —
   is a paper-argued candidate in the L1/L2 sense: recomputed by code, exercised by 16 forged IRs, not proved.
2. **The three primitive contracts are assumed** (SOUNDNESS.md A3-style) and only *tested* (191 inputs × 3 run lanes) on the value contract: printable ASCII + six ASCII whitespace.
   Outside it they are false and known to be: `str.lower()`/`str.strip()` are Unicode-aware, `String.to_lower`/`String.trim` are ASCII. The type `String` does not carry the value contract; nothing enforces it at a call site yet.
3. **Lint does not certify this def.** `Lint.analyze`/`Lint.alias` grade `normalize_stem` `total Unknown` / `ownership Unknown: dynamic call at 2:11` — T0/O0 treat every method call as dynamic.
   L2's instruction is "gate on `Lint.own`"; T1 cannot, for its only demo. Instead the translator's contracts are **receiver-typed** (the receiver's IR type is `TStr` under A1 exact `str`, so `.strip` is `str.strip`),
   and B1–B3 are argued from `str` immutability. That argument is on paper only. The honest fix is in Lint (see T2 needs), not a wider claim here.
4. **`Call`/`Let`/`Branch`/`Fold`/`TBool`/`TInt`/`TList`/`TMaybe` are declared, not implemented.** The brief lists them as IR nodes and says the fragment is exactly what `normalize_stem` needs; I resolved that as
   "in the type, refused by the kernel and never produced by the elaborator". So short-circuit helper matches and first-on-tie are *obligations recorded*, not code exercised.
5. **Elaborator recursion is fuel-bounded** (fuel = AST weight), not structurally justified; running out of fuel is an `error Limit` diagnostic that blocks emission, never a guess.
6. **Identifiers**: only lowercase-ASCII/digit/underscore names are emittable and there is no Bend reserved-word list (`ponytail:` comment in the source) — a parameter named `case` would emit a file Bend rejects. C1 would catch it (the check lane fails); it would not be silent.
7. **Literals**: one plain token only; escapes, prefixes, triple quotes and adjacent concatenation are refused rather than decoded.
8. **Docstring is dropped** from the emitted code (it is not semantics); the header comment cites the source span instead.
9. **`tests/translator/` vs the gate's `tests/translate/`** — see Measurements.
10. **Judge path is absolute to this machine** (`~/Documents/Project/llm-wiki/tools/wiki.py`, oracle at `~/.hermes/hermes-agent/venv/bin/python3`), like the lint lane's pin; elsewhere the judge fails loud, it does not skip.
11. No tier-③ rewrite is applied. Candidate recorded only: fusing `to_lower`∘`replace` into one pass (needs an equivalence proof; out of T1).

## What T2 / T3 need next

- **Lint admission for receiver-typed method calls.** Extend T0/O0 so a method call on an A1-exact-typed receiver with a granted contract is a primitive, not a "dynamic call"; then the translator can gate on `Lint.own` as L2 intended and deviation 3 closes. One contract table should serve both (today `Lint`'s and `translate.bend`'s are separate).
- **T2 = the control idioms**: `ILet` (affine: a Python name read twice needs `+x`), `IBranch` with **helper matches** for `and`/`or`/`if` so the untaken side is never evaluated (never `Bool.pick`), `IFold` for `for` over a list with Done/Continue for `break`/early `return`,
  `TMaybe` for `None`-returning searches, first-on-tie for `min`/`max`/`sorted(key=…)`. Each needs: elaborator case, kernel rule, renderer, one emit test, refusals, forged IRs, and judge fixtures that *observe* the property (a raising/looping right operand for short-circuit; equal keys for ties).
- **`ICall` between translated defs**, ordered by definition (Bend needs define-before-use) and gated on the callee being emitted too; totality of recursion comes from L1's rank witness.
- **Value contracts in types**: make "ASCII string" a checked precondition (refinement or a validating boundary function) so deviation 2 stops being prose.
- **A restricted doctest adapter** for the judge (literal `>>>` examples only, parsed, never executed as a module) so examples come from the source when it has them.
- **T3 (tier ③)** can then start: rewrites as separately-justified IR→IR steps, each with its own C2 run and a recorded equivalence argument; the span map already survives IR rewriting because spans live on nodes.
- **Mechanization**: state the kernel theorem in `bend2/bend.lean` terms (or as Bend `{==}` laws like L1's `no_certificate_no_proof`) — first candidate: *no contract ⇒ no emission*.
