# Parser lane — Astra — P0–P2

Built in `/home/omen/Documents/Project/bend-work-parser` on `lane-parser`.
No pushes. The canonical checkout and all prohibited source/test/gate paths
were left unchanged. This report records local execution, not cluster or GPU
validation.

## Slice status and commits

| Slice | Commit | Result |
|---|---|---|
| P0 | `df0be973` | Skeleton, shared ADTs/JSON, strict intake, pinned oracle, manifests and harness control; 12/12 lane checks. |
| P1 | `69af1c43` | Hand lexer; 32/32 lane checks and 200-file token parity. |
| P2 | `03069518` | Expressions/statements, contexts, spans, fuel, specimens and C/JS stress handling; 60/60 lane checks. The two largest pure-interpreter stress probes remain unpassed at the harness bound, as detailed below. |

The final `bash tests/parser/run.sh` passes 60 lane checks across 15 specimens:
15 checks, 14 pure interpretations plus one IO CLI/JS execution, 15 emitted-JS
runs and 15 C runs with `--gpu off`. The deliberately wrong `#|` fixture is
executed successfully as `1n`, compared against `2n`, and required to fail the
same output comparator. It is a negative control, not an extra passing lane.
P2 also reran the NUL rejection fixture in all four lanes after its final guard.

## Files and implementation

All parser implementation is total Bend under `demos/python/`, with sibling
imports and no `@unsafe`:

- `syntax.bend`: positions, spans, tokens, contexts, Expr/Stmt/Module/error and
  JSON ADTs; JSON encoder; tail token counter.
- `intake.bend`: incremental strict UTF-8/BOM decoding and bounded byte reads.
- `lexer.bend`: indentation/alternate columns, logical lines, brackets,
  continuations, comments and token dispatch.
- `scanner.bend`: consuming name/string/number scanners, raw spellings,
  escaped CRLF handling and the number DFA.
- `unicode.bend`: 730 non-ASCII word ranges from the pinned Unicode database.
- `parse_state.bend`: state/result combinators, classified errors, residual
  budget and token operations.
- `operators.bend`: precedence/operator tags and compound comparisons.
- `nodes.bend`: AST builders, syntactic covers, grouping and target context
  validation/rewriting.
- `parser.bend`: one directly recursive mode-dispatched precedence parser.
- `main.bend`: strict input, token/AST/stats output and classified exit 1.
- `README.md`: invocation, interfaces, subset and fuel reasoning.

`tests/parser/` contains `run.sh`, `normalize.py`, `diff.py`, `manifest.py`,
`lexdiff.py`, `fixtures.py`, `fuzz.py`, `adversarial.py`, `reference_probe.py`,
and the small checked-in `.bend` fixtures (`schema`, `intake`, `io_read`, five
`lex_*`, three `expr_*`, three `stmt_*`, `deep_nesting`). Manifests, executable
builds, oracle hashes, generated inputs and all detailed results are ignored
under `tests/parser/_out/`.

No parser frames were introduced. The 200/201 nesting fixture passes all four
lanes, so the arbitration's escalation trigger did not fire. Parser modes are
grammar selectors; ordinary recursive calls return their results. Every mode
entry consumes one unit of residual global fuel, threaded through subsequent
parses. `K = 32`, with `budget = K * (token_count + 1)`, conservatively bounds
the 20-mode transition graph and its closing dispatches. The observed maximum
was **13 entries / (3 tokens + 1) = 3.25**. This reasoning is not a mechanized
complexity proof; the executable fuzz criterion is recorded below.

The JSON encoder uses an affine tail continuation and one accumulating buffer.
That is an output traversal, not a parser frame machine. It fixes deep-output
JS stack use and repeated child-string copying on C. A local tail counter
avoids Base.List.length's non-tail JS recursion on long token lists. No Base
or compiler change was needed.

## Oracle, canonicalization and intake

The harness requires **CPython 3.11.15** at
`/home/omen/.hermes/hermes-agent/venv/bin/python3`. Its resolved executable is
`/home/omen/.hermes/hermes-agent/.hermes-runtime/python/generation-1785203907-1740771-edaf0b90/cpython-3.11.15-linux-x86_64-gnu/bin/python3.11`.
`normalize.py` pins the path/version and fails if that version changes;
`_out/oracle.json` records executable, ast and tokenize SHA-256 hashes and
behavior notes. Parsing uses `feature_version=(3,11), type_comments=False`.
The 200/201 bracket bound and ast.parse's acceptance of top-level
return/break/continue are asserted by the harness.

The wire carries raw literals; both sides of comparison use
`repr(literal_eval(raw))`. Parenthesized wrapping and a final newline preserve
implicit concatenation across comments. Every AST location is compared in a
separate pass, using per-physical-line UTF-8 boundary maps to convert byte
columns to code points. Form feed is not a line separator. `ctx`, operator tags
and CPython field/list order are retained. The 20-case harness round trip
includes independent ctx/constant/end-span corruption controls.

`File.read` was verified on a **3,145,728-byte** regular file on C. Production
strict intake uses `File.read_bytes`, since File.read replaces invalid UTF-8.
The read loop handles short reads, split multibyte sequences and BOM; input is
bounded at 32 MiB. There are **14/14 C/JS intake/exit-1 checks**, including a
scalar split across the 64 KiB read boundary. The corpus wrapper excludes
non-UTF-8 coding cookies before decode. NUL is rejected outside tokens, inside
strings and in comments.

## Measured parity and coverage

| Measurement | Result |
|---|---|
| Lexer corpus | 200/200 files tokenized: five llm-wiki tools plus 195 pinned-stdlib files. |
| Directed lexer inputs | 15/15, including CRLF, form feed, continued strings, tabs, raw prefixes, triples and numeric rollback. |
| Lexer differences | 0 kind/text differences; 0 token-position differences; 0 refusals or fail-stops. |
| Lexer JS cross-check | 25/25: all 15 directed inputs and 10 corpus samples. |
| Parser directed inputs | 143/143 supported, parsed and exact; 0 structural or location differences. |
| Fuel/grammar generation | 1,159 generated/directed inputs; 1,157 oracle-accepted, 2 oracle rejections. No Limit on an oracle-accepted input; 0 structural/location failures. |
| Fuzz JS cross-check | 58 samples, 0 differences. |
| Negative grammar cases | 51 cases on both C and JS: 102/102 classified as expected. |
| Production adversarial CLI | 26/26 C/JS runs, 0 fail-stops. |

The production adversarial set includes nesting 200/201, 5,000 unary operators,
100,000 binary operators, a 10 MiB comment line, mixed tabs, NUL in three
positions, invalid UTF-8, unterminated triple quotes, inconsistent dedent and
token soup. CPython rejects the two extreme expression chains with
RecursionError; those are recorded as oracle failures, not parser verdicts.
The production Bend parser returns Done for those chains on both C and JS.

Tier 1 whole-file results:

| File | Result |
|---|---|
| `freshcheck.py` | Unsupported: import at line 16. |
| `ingest.py` | Unsupported: import at line 14. |
| `overview.py` | Unsupported: import at line 6. |
| `synapse.py` | Unsupported: import at line 12. |
| `wiki.py` | Unsupported: import at line 15. |

**Total 5; eligible 5; independently supported 0; parsed 0; exact 0;
unsupported 5; Limit 0; Syntax/error 0; oracle-failure 0; fail-stops 0;
structural diffs 0; location diffs 0. Parse rate: 0/5 = 0%.**
The C corpus is checked file by file and the deterministic JS sample covers
one of the five. C p50/p95: 10.16 / 69.41 ms (single local corpus run). Zero supported tier-1 files is not
positive acceptance evidence: imports/functions belong to later slices. The
143 directed cases and grammar fuzz supply the non-vacuous P2 evidence.

## Deviations, open acceptance and limits

The original demand for the largest adversarial inputs to settle in every lane
is **not fully met**. `reference_probe.py` uses computed sizes rather than
large Nat literals, and the actual pure-interpreter measurements are:

| Probe | Pure interpreter |
|---|---|
| 5,000-character length baseline | Pass, 0.58 s. |
| 5,000 unary operators | Done, 46.50 s. |
| 100,000 binary operators | Timeout at 60 s. |
| 10 MiB comment line | Timeout at 60 s. |

These two timeouts remain failed reference probes; they are not counted as
passing tests or converted to parser `Limit`. The main runner gates the regular
four-lane specimens and production C/JS adversarial path. Run
`python3 tests/parser/reference_probe.py` separately to reproduce the open
reference gate. Longer-run completion is unmeasured. There is no claim of zero
fail-stops for this separate pure-interpreter stress set, and no claim that
changing parser frames would fix its cost; the mandated below-200 trigger
passed. Early probes using large Nat literals also overflowed during checking;
the reported results above explicitly avoid that confounder.

The lexer freezes Unicode word classification, while parser identifier NFKC
normalization remains Unsupported. Slice/function/import/comprehension/f-string
and other P4–P6 grammar remains out of scope. Literal payloads remain raw in
Bend; value decoding/validation occurs in the differential normalizer. The
oracle's out-of-scope JoinedStr text constants use repr(node.value), because
CPython spans those constants over the whole f-string. This does not mask a
supported Constant difference.

The final checks also include `bash tests/caps.sh` (pass), `git diff --check`
(pass), and `PATH="$HOME/.local/bin:$PATH" bun gates/repo.ts` after each slice
commit (44/44). Final source measurement: 30,219 ttok across the ten Bend modules; largest file `demos/python/unicode.bend` at 8,824/64,000 ttok. No caps or allow rules
were edited. Unrelated cluster, regex, lint, translator and GPU gates were not
claimed as parser-lane evidence.

Detailed generated evidence: `_out/RESULTS.md`, `oracle.json`,
`corpus-1.jsonl`, `corpus-lex.jsonl`, `lex-results.json`, `fixtures.json`,
`fuzz-results.json`, `adversarial-results.json`, `reference-results.json`,
`intake.json`, `sizes.json`, and the per-slice runner logs.
