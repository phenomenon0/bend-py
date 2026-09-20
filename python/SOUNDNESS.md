# SOUNDNESS — what each lint grade guarantees, and where the guarantee stops

`demos/python/lint.bend` grades every diagnostic:

| grade | meaning |
|---|---|
| `Proven` | the kernel recomputed every condition of the rule's fragment from the actual AST and contracts, and they hold; the guarantee below then follows **under the listed assumptions**, with the theorem status in the last column |
| `Refuted` | a certificate was offered and recomputation contradicts it. The *certificate* is refuted; the property itself stays Unknown, unless a recomputed counterexample refutes it: `not exhaustive: v` (M0), `import cycle`, `missing module` (U0) |
| `Unknown` | outside the fragment, unresolved, or no certificate. No claim either way |
| `Advisory` | a note that needs no proof and carries none |

A certificate (witness) is forgeable data. `Lint.verify(ast, contracts, witness, name)` trusts none
of it: the witness supplies only a rank per function; fragment membership, binding and call
resolution, contract grants and the rank inequalities are all recomputed (`certificate`).
`Lint.analyze` is untrusted search: whatever it infers goes through the same kernel before a
`Proven` is printed. Coverage is the same: `Lint.coverage` searches, and `Lint.exhaustive` and
`Lint.dead_case` recompute M0 membership, the domain and every claim before grading; U0 too (`Lint.modules`).

## Fragments

| id | rule | guarantee | theorem status |
|---|---|---|---|
| T0 | `total` | every call of the function on arguments satisfying A1, in a module state satisfying A2, **terminates**: it returns or raises. Successful return is *not* claimed (`TypeError`, `RecursionError` on a cyclic argument, `MemoryError` are terminations) | **argued on paper (below), not mechanized.** Per plan §3 this is a *candidate* theorem until a fragment evaluator exists in Bend and the proposition is checked against it. Empirical evidence only: `tests/lint/semantics.py` (pinned CPython 3.11.15). |
| R0 | `unreachable` (`Proven`) | a statement that directly follows `return` / `raise` / `break` / `continue` in the same block is never executed | argued on paper, not mechanized. Holds for all Python, no assumptions: each of the four transfers control out of the block; a `finally` body runs, but control never resumes at the next statement of the block |
| R0 | `unreachable` (`Unknown`) | none: the statement follows `while True:`; deciding it needs break analysis | — |
| S0 | `shadowed-builtin` (`Advisory`) | none. A `def`, parameter or `Store` name is spelled like a contracted primitive | — |
| O0 | `ownership` | under A1–A4 the function satisfies B1–B3 of the **IR ownership boundary** below | argued on paper, not mechanized: a *candidate*, like T0. Evidence: `semantics.py` (arguments equal their deep copies after every generated call) |
| L0 | `alias-mutation`, `alias-escape`, `param-mutation` (`Advisory`) | none. A reasoned note citing the binding and the later read; neither sound nor complete for Python | — |
| M0 | `exhaustive` (`Proven`) | under A1–A2, whenever the match runs, some unguarded case matches the subject: no value of the domain D falls through | argued on paper (below), not mechanized. Evidence: `semantics.py` calls every value of D, traced |
| M0 | `exhaustive` (`Refuted`, `not exhaustive: v`) | v ∈ D, and no case matches v, guarded or not, so a call with v runs no case | the same |
| M0 | `dead-case` (`Proven`) | the case's body never runs: every value of D fails its pattern or is caught by an earlier unguarded case | the same |
| U0 | `imports` | `Proven`: under A5 importing the module hits no missing or half-built module (each import names a unit, `from n import x` a def of n, acyclically). `Refuted`: an import path closes a cycle or leaves the set | on paper (ranks order the graph), not mechanized. Evidence: `semantics.py` |
| U0 | `pure` | T0 across the set (A1–A5): terminates, no effect | on paper, as T0 (callees ranked lower), not mechanized |
| K0 | laws `no_certificate_no_{proof,ownership,coverage,dead_case,imports,purity}` | each rule's `is_proven` on an empty certificate is `False` for every input | **checked by Bend** (`{==}`, in `lint.bend`). Laws about the verifier, not about Python |

## T0 membership (all recomputed by the kernel)

- **Module closed (A2's syntactic half):** top level is `def`s and a docstring only. Anything else
  (import, assignment, class, decorator call, `async def`) makes every function `Unknown`.
- **Header:** no decorators; plain positional parameters only (no defaults, `/`, `*`, `**`,
  keyword-only); every parameter and the return annotated in `str | bool | int | list[T] | T | None`.
- **Body:** only `Return Assign If For Break Continue Pass Expr`, expressions `Name Constant BoolOp
  UnaryOp(Not) BinOp(Add) Compare IfExp List Call`. Nothing in the fragment mutates: no `AugAssign`
  (`ys = xs; for x in xs: ys += [x]` diverges — a control in `semantics.py`), no attribute, subscript,
  `del`, method call, comprehension, lambda, nested def/class, `global`, `while`, `try`, `with`, f-string.
- **Names:** every loaded name is a parameter or a local `Store` target of this function.
- **Calls:** `Name(...)` with positional arguments only, resolved as exactly one of
  - a module `def` with a unique definition and no local rebinding → the witness must rank it
    strictly below the caller (acyclic by the rank inequality; self and mutual recursion are refused);
  - a contracted primitive: not rebound locally, not defined in the module, contract `pure` and
    `total`, called at the contract's arity.
  A local or module binding of a contracted name **revokes** the contract (`shadowed builtin`):
  spelling is not authority. Anything else — methods, call results, lambdas — is a dynamic call.
- **For → fold:** the iterated value is an exact `str`/`list` (A1) that nothing can mutate, so the
  loop body runs at most `len` times; any other iterated value raises `TypeError`.

**Argument (paper).** By induction on the witness rank, then on the statement structure. All values
reachable in a T0 body are exact built-ins from the closed universe U = {`str`, `bool`, `int`, `None`,
`list` of U}: parameters by A1, constants, results of `+`/comparisons/`not`/`and`/`or` on U, list
displays, results of contracted primitives (A3) and of lower-ranked T0 functions (IH). Every admitted
operation on U terminates in CPython (A4), no user hook (`__add__`, `__iter__`, `__eq__`, `__bool__`)
can run because no value is a user type, `for` iterates a finite unmutated sequence, and calls go
strictly down in rank.

## The IR ownership boundary (O0) — what the translator's TypedIR may assume

O0 = T0 **and** no `is` / `is not` except against `None`/`True`/`False` (`ident`; `s is "a"` depends
on interning and is refused). Same kernel, same rank witness: `Lint.own(ast, contracts, witness,
name)` recomputes T0 membership plus `ident` for **every** witness entry, so every transitive callee
is in O0 too. For a function graded `ownership Proven`, under A1–A4, TypedIR may assume:

- **B1 no mutation.** No argument, and nothing reachable from one, is mutated during the call:
  nothing in T0 mutates, callees are O0 or contracted `pure` (A3).
- **B2 no retention.** After the call no reference to an argument survives except inside the
  result (no globals, attributes, closures, containers passed in). The result **may share** with
  arguments (`return xs`, `[xs, xs]`).
- **B3 sharing unobservable.** Inside O0 nothing mutates or tests identity, so copy, share and move
  are indistinguishable: value semantics is faithful, and an affine IR may duplicate or move
  any binding. Repeated use is legal.

**Outside the boundary — assume nothing:** any function not graded `ownership Proven`
(`Unknown`/`Refuted`), even when `total Proven` (`same(xs, ys): return xs is ys`); what a non-O0
caller does with a shared result; arguments violating A1; other threads. B1–B3 are statements
about verified O0 functions, **never universal Python alias safety**.

## L0 advisories (no certificate)

Per top-level `def`, flow-insensitive may-alias classes from `b = a`, `b: T = a`, `b = a if c else d`,
`b = a or d` (so branch joins and rebinding both merge). Events: a mutation through a name
(mutator-method spelling, item/attribute store or `del`, `+=`), or a Name argument escaping to a
call that is neither a granted pure primitive nor an O0-certified def. An event on `b` is reported
when a distinct alias `a` is read textually later or is a parameter; `param-mutation` when `b` is
itself a parameter. Names whose every binding is immutable on exact `str|bool|int|None` (A1; greatest
fixpoint over constants and operators) are skipped: immutable reuse is safe. **Known misses:** reads
earlier in the same loop, element/attribute-path aliases (`for x in xs`, `b = a.f`, `b = a[0]`),
tuple targets, keyword/starred arguments, nested scopes (conflated), methods and module-level code.
**Known noise:** rebinding does not kill an alias; method spelling is not authority.

## M0 membership: the finite-domain boundary (all recomputed by the kernel)

The module need not be closed. A `match` is in M0 when:
- **Subject:** a name that is a plain positional parameter of the innermost enclosing `def`, the
  def has no defaults, and nothing else in the def binds the name (store, `del`, capture, walrus,
  `global`, keyword name: counted conservatively).
- **Domain D:** the parameter's annotation, in order: `bool` → `True, False`, only if nothing in the
  module binds `bool`; `None`; `Literal[…]`, only if a top-level `from typing import Literal` is
  its only binder, with elements `True`/`False`/`None`, decimal ints, `-n`, and str literals of
  printable ASCII without quote or backslash; `X | Y` concatenates. A star import binds everything.
  Anything else (`str`, `int`, aliases, `Optional`, empty or nested `Literal`) is Unknown.
  Why finite: under A1 each admitted annotation has finitely many exact values, and each is named
  by a literal whose repr the kernel computes without evaluating anything.
- **Patterns:** `None`/`True`/`False` (identity); a literal in D's syntax (`==`, so `case 1` matches
  `True`); capture and `_` (irrefutable); `as` and `|` over those. Anything else (class, sequence,
  mapping, dotted, float) is Unknown. A guarded case never covers and never shadows (its guard
  may fail), but it may be taken, so it defeats a `Miss` claim.

**Argument (paper).** Python tries cases in order and runs the body of the first case whose pattern
matches and whose guard is true. By A1 the subject holds some v ∈ D, and nothing rebinds it. The
kernel decides "pattern p matches v" exactly for M0 patterns and immutable v. So a first unguarded
case for every v means no fall-through. No case for v means a fall-through. If every v fails p or
reaches an earlier unguarded case, p's body is dead. A guard that raises ends the match, which
contradicts none of the three.

## U0 membership (all recomputed by the kernel)

Entries `Ranked`, `Pure`, `Path` are forgeable; one bad one refutes all. `Ranked`: a unique unit,
T0-closed but for U0 imports (`import n`, `from n import x`, `as` allowed, level 0, n one name, no
`*`) of lower-ranked units. `Pure`: T0 in a ranked module, imports bind lower-ranked defs (`n.f(…)`
is dynamic). `Path`: recomputed edges ending on a repeat or a non-unit.

## Assumptions (the trust boundary)

- **A1 exact arguments.** Arguments are exact instances (not subclasses) of the annotated built-in
  types, recursively for list elements, finite, and not mutated by another thread during the call.
  A `Literal[…]` parameter holds one of the listed values with its exact type (`1`, not `True` or `1.0`).
- **A2 module state.** The call happens with module globals as they are right after import of the
  closed module (exactly the `def` names) and with CPython's pristine `builtins`. Nobody ran
  `module.helper = evil` or `builtins.len = evil` in between. For M0: `bool` and `Literal` are
  bound only by the module's syntactic binders (no `exec`, `globals()` or `builtins` writes).
- **A3 contracts.** Each `Contract{name, arity, pure, total}` is an *assumption about CPython*, not
  something the kernel can check: `len`, `str`, `bool`, `sorted` at arity 1 on U are taken as pure
  and total. The kernel checks only that a call is *granted* by a contract (name unshadowed, arity,
  both flags). A false contract yields a false `Proven`: the `assumed` case in
  `tests/lint/totality_forged.bend` shows this boundary on purpose.
- **A4 host.** CPython 3.11 semantics of the admitted operations on U; the parser's AST is the AST
  of the source (differentially tested against `ast.parse`, not proven); the Bend checker and
  runtimes are trusted.
- **A5 units.** `name.py` files first on `sys.path`, not packages; `missing module z`
  means not in the set.

## Exclusions

Successful return; resource bounds (a T0 function may build a 2^n-sized string); anything
concurrent; any argument outside A1; generators/async; classes; recursion (rank/countdown
certificates are deferred per plan §3); `match` coverage outside M0 (decided guards, class/sequence/
mapping patterns, open domains); imports outside U0; a def statement's own exceptions; ownership certificates for mutating code.

## Fixtures per rule (`bash tests/lint/run.sh totality`, `alias`, `coverage`, `modules`)

| rule | positive | negative | Unknown |
|---|---|---|---|
| `total` | `totality_proven`, `honest`/`granted` in `totality_forged` | every other case of `totality_forged` (`Refuted`), `totality_shadow` | `totality_unknown`, `no certificate` |
| `unreachable` | `totality_reach`: after return / continue / break / raise-before-finally | `branch` (return inside `if`) emits nothing | `forever` (after `while True`) |
| `shadowed-builtin` | `totality_shadow`: def, parameter, local | `fine` (uses `bool` unshadowed) | — (advisory) |
| `ownership` | `alias_boundary`: `absent`, `share`, `echo`; `honest` in `alias_forged` | every other witness of `alias_forged` (`Refuted`; `identity` is `total Proven`) | `alias_boundary`: `same`, `caller`, `grows`, `interned`; `no certificate` |
| L0 advisories | `alias_flag`: plan example, method/store/`+=`, if and IfExp joins, chain, container escape | `alias_safe`: repeated use, immutable reuse, copy, move, fresh join, alias passed to an O0 def | — (advisory) |
| `exhaustive` | `coverage_proven`, `guarded_dup` in `coverage_missing`, `honest` in `coverage_forged` | `coverage_missing` (`not exhaustive: v`); every other witness of `coverage_forged` (`Refuted`) | `coverage_unknown`, `guarded`, `no certificate`, `elsewhere only` |
| `dead-case` | `coverage_dead`: duplicate, `True` after `1`, `_` last, outside D, guarded shadow, `w.py` (`_` first); `honest dead` | `live case`, `guarded duplicate`, `bad companion`, `changed dead` (`Refuted`) | `no certificate` |
| `imports`, `pure` | `modules_clean`, `honest` | `modules_missing`, `modules_cycle`, `declared`, forged | `search`, `lack`, `rel`, `star`, `dots` |
