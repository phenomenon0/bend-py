# Python syntax service: P0–P4

`main.bend` reads the path in `PY_SOURCE`. `PY_MODE=lex` prints tokens;
`PY_MODE=stats` reports tokens and consumed parser fuel; the default prints
the module AST. Compile from this worktree:

```sh
bun bend2/main.ts demos/python/main.bend -o tests/parser/_out/parser
PY_SOURCE=/path/to/input.py tests/parser/_out/parser --gpu off
bash tests/parser/run.sh
python3 tests/parser/lexdiff.py --files 200
python3 tests/parser/diff.py --corpus 1
```

The implementation is pure, checked Bend. `intake.bend` uses the existing byte
read effect and validates UTF-8 incrementally, including split multibyte
sequences. It accepts a leading BOM, loops over short reads, and bounds input
at 32 MiB. The corpus wrapper excludes non-UTF-8 coding cookies before decode.
`File.read` is separately tested with a 3 MiB regular file because that effect
decodes invalid bytes with replacement and cannot enforce strict intake.

The hand lexer handles indentation and alternate tab columns, comments,
bracket-suppressed newlines, explicit continuations, CRLF, form feed, keywords,
raw number spellings, and prefixed/single/triple strings. Unicode word ranges
are frozen from the pinned CPython 3.11.15 Unicode database. The parser defers
Unicode identifier normalization to later slices.

The parser supports expressions, calls, attributes, subscripts without slices,
tuple/list/set/dict displays and unpacking, `lambda`, assignment and augmented
assignment, expression statements, `if/elif/else`, `while/else`, `for/else`,
`def` with the full parameter grammar, annotations and decorators,
`try/except/else/finally`, `with` (both item-list forms), `global`, `nonlocal`,
`del`, `assert`, `raise`, `return`, `pass`, `break`, `continue`, and `import` /
`from … import` (dotted names, `as`, relative levels, `*`, parenthesized lists), and
`class` (bases, keywords, `**kwds`, decorators, nested), and slices
(`a[i:j:k]`, any bound omitted, slice tuples `a[:, 1]`, in Load/Store/Del), and f-strings
(`JoinedStr`/`FormattedValue`: fields, `!r`/`!s`/`!a`, the debug `=`, format specs with nested
fields, nested/raw/triple-quoted f-strings, implicit concatenation), and comprehensions
(`ListComp`/`SetComp`/`DictComp`/`GeneratorExp`: nested `for` clauses, `if` filters, any
assignment target, the bare generator as a call's sole argument, inside f-string fields), and
annotated assignment (`AnnAssign`: `target: annotation [= value]`, name / attribute / subscript
targets, `simple` 1 only for a bare unparenthesised name, star-expressions as the value, and
CPython's PEG quirk that `(a).b: T` is an illegal target while `((a).b): T` is not), and
`yield` / `yield from` as expressions (`Yield{value?}` / `YieldFrom{value}`: a statement's head,
an assignment's, augmented or annotated value, what parentheses or an f-string field hold; bare
in an argument, a display, a subscript or a lambda body is `Syntax`), and `async def` /
`async for` / `async with` (the plain statement's fields under the `Async` tag, from the `async`
token; after decorators only `async def`), `await` (`Await{value}`: `await` takes a primary, so
`await x ** 2` is `(await x) ** 2` and `await -x` is `Syntax`) and `async for` clauses in
comprehensions (`is_async` 1). Both words are keywords in 3.11: `async = 1` is `Syntax`. Named
expressions (`NamedExpr{target, value}`, the target a `Name` in `Store`) parse where the grammar
names `named_expression`: in parentheses, an `if` / `while` head, a positional argument, a display
or subscript element, a comprehension's element or filter, an f-string field, a decorator; anywhere
else a bare `:=` is `Syntax`, as is a target that is no bare name. `match` statements
(`Match{subject, cases}`, `match_case{pattern, guard, body}` and the eight patterns `MatchValue` /
`MatchSingleton` / `MatchSequence` / `MatchMapping` / `MatchClass` / `MatchStar` / `MatchAs` /
`MatchOr`): `match` and `case` are soft keywords, so only `match subject_expr ':' NEWLINE` at a
statement's head starts one (the header alone backtracks; `match = 1`, `match(x)`, `match [x]: int`
stay simple statements) and its block holds nothing but `case` clauses. It follows
`ast.parse`'s syntax acceptance rather than Python compilation's additional
scope checks (`*a = 1` parses, and so does `yield` or `await` outside a function or in a comprehension).
`except*` is `TryStar` (the `Try` fields; every handler of the `try` has the star and names its
type). Only non-ASCII identifiers report `Unsupported`: a compound statement where a simple one
belongs (`if a: with b: pass`) is `Syntax`, as in the oracle. Syntax failures and limits have distinct
`Syntax` and `Limit` kinds. Failure prints `error KIND LINE COL MESSAGE` and
exits 1. Bracket nesting is bounded at the oracle's 200; 201 is `Limit`.

`syntax.bend` carries scalar positions, token spans, `Load/Store/Del`, expression,
statement, module, error and JSON ADTs. AST nodes carry separate semantic spans
and syntactic covers, plus a grouping bit: this preserves the oracle's spans
for `(a)+b`, `(a,b)`, and `((a,b))`. Context rewriting changes only target
containers; the base of an attribute or subscript remains `Load`.

The wire JSON has node tags, CPython field order, operator/context tags, and
`_loc: [start_line,start_col,end_line,end_col]`. Constants retain `_raw` until
the harness applies `repr(ast.literal_eval(raw))` to both sides, wrapping
adjacent literal text in parentheses and a final newline. This preserves
implicit concatenation across comments without requiring floating-point
conversion in Bend. `normalize.py` separates every location from structural
comparison and maps CPython UTF-8 byte columns to code points per LF-delimited
physical line. Trivia is dropped; there is no span sampling.

One directly recursive `go` dispatches 55 grammar modes with precedence
climbing. Every mode entry decrements a residual global budget. The first
structurally decreasing Nat proves termination independently of the residual
budget. Sequential parses thread the residual state, never replenish it
(except the `with (` header retry below).
The default is `32 * (fuel_weight + 1)`, the weight being one per token plus a
`STRING`'s characters: a conservative bound for the
dispatch graph plus its repeated Rest/collection exits. Every cycle consumes
a token or, in an f-string body, a character of its one token, and no chain of
modes between two consumptions reaches 32
dispatches (measured highwater: 4.5 per token outside many-field f-strings). The one backtracking point,
the `with (` header, restarts its second alternative from the saved budget, so
a header is metered at most twice; bodies are outside the choice. The EOF allowance
covers the final Block entry. The deterministic fuzz harness measures actual
consumption and rejects any `Limit` on an oracle-accepted generated input.

An f-string stays one `STRING` token (the 3.11 tokenizer's shape). `fstring.bend` scans its
body after CPython's `fstring_find_literal`/`fstring_find_expr`; each field's text is lexed as
`(expr)` from the `{` (`lex_at`, so every inner token keeps its source position and a bare
tuple takes CPython's paren span) and parsed by the same `go` on its own
`32 * (fuel_weight + 1)` budget (`within`); the outer budget resumes untouched. Text
Constants travel as `_parts` pieces the harness decodes and joins.
This is an implementation bound with regression evidence, not a mechanized
proof of Python grammar completeness or a bound on hardware memory/time.

No parser continuation/frame machine is used: nesting 200/201 passes the
checker, interpreter, emitted JS and C. JSON output uses an affine tail
continuation and an accumulating output buffer; token counting uses a local
tail loop. Those avoid JS stack and C repeated-copy failures on long inputs.

Run evidence and frozen manifests are written only under `tests/parser/_out/`.
`reference_probe.py` separately measures known large pure-interpreter failures
and exits nonzero when they occur; it is deliberately not relabeled as a
successful parser test. See `docs/omen/lanes/parser.md` for measured results,
the whole-file corpus denominator, and the interpreter limitation.
