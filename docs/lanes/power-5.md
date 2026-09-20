# power-5 — Json: a streaming event parser (2026-09-20)

Lane 5 of the plan, and the one that closes wave 1. The first lane with no
array in its hot loop: the state is a value, which is the whole point — it is
what makes `skip` cheap, what makes a forked parse (lane 17) free later, and
what forced the two deviations below.

## What shipped

`power/json.bend`, over `power/bytes.bend` and `power/bitset.bend`:

- `start(b, limit) -> St` — a parser over a byte buffer with a byte allowance.
- `next(s) -> St & Event` — one token per call: `ObjOpen ObjEnd ArrOpen ArrEnd
  Field{at,len} Str{at,len} Num{at,len} Flag{v} Null Eof Bad{at,why}`. A span
  points into the caller's own `Bytes`; nothing is copied and no tree is built.
  A 200 MB log costs one `Bytes` and a 256-bit container stack, and a consumer
  that wants three fields never materialises the rest.
- `check(b, limit) -> Bytes & Event` — drive the whole document and hand back
  the event that ended it: `Eof` if it is valid json under the budget, else the
  `Bad` that refused it.
- `skip(s) -> St & Event` — consume the next value whole: a scalar is one
  event, a container is all of it.
- `budget(s)`, `depth(s)` — the unspent allowance and the open-container count.
- `finish(s) -> Bytes & U32` — hand the input and the unspent budget back.
- `raw(b, at, len) -> Bytes & String` — a span exactly as it sits in the input.
- `show(e)`, `reason(e)`, `live(e)` — the event as text, the refusal as text,
  and "is this stream still running".

`Num` keeps the lexeme rather than a number, so `1e400` and `0.10` survive the
parser unchanged and the consumer picks its own numeric tower. `Field` and
`Str` are the span *between* the quotes, escapes unapplied.

## Two deviations from the package convention, and why (Rule 7)

The package-wide rule from lane 1 is `limit: U32` last, `Result<Err, (left,
value)>` back. This lane breaks it twice, and both breaks are the same fact:

**`Bytes` contains an `Array`, so it has kind `Type` — affine, single-owner —
and `Result`/`Maybe`/`List` payloads must have kind `Data`.** The parser state
owns the document. It therefore cannot sit inside a `Result`.

1. **The budget lives inside the state**, not beside the answer. `start` takes
   `limit` and `St` carries `left`; `budget(s)` reads it back out.
2. **A refusal is a terminal event, not a `Result`.** `Bad{at, why}` is
   returned, and `MBad` makes every later `next()` return the same event, so a
   driver loop needs no flag of its own — `live(e)` is the loop condition and
   the stream is its own error channel.

The other lanes keep the convention. If a later lane hits the same wall, this
is the shape to copy: state-owned budget, terminal event, `live` as the
predicate.

## The budget contract

Whitespace is free — it is bounded by the input, so pricing it would only make
the budget harder to reason about. Structural bytes spend 1, saturating. A
value token is scanned with fuel capped at `min(left, n - at) + 1` steps and
then charged what it used, so a hostile 200 MB string met with `limit 1000`
costs 1000 bytes of scanning and comes back `Dry` — never a partial answer and
never a hang.

**Every token that succeeds is charged; a token that fails is not.** That
includes a key string that scanned fine before the colon after it refused: the
scan happened, so it is paid for. The oracle disagreed with the parser here
and the parser was right.

## Verified

`bash tests/power/run.sh json` — 143 rows, six lanes (oracle, check, interpret,
js, c, c-1thread), `PASS: 6, FAIL: 0`. 66 rows are whole event streams, 67 are
`check` verdicts, 4 are `skip`, 6 are `raw`.

`tests/power/json_gen.py` is a **three-way** oracle, not a transcription:

- CPython's own `json.loads` decides accept-or-reject for every document in the
  corpus. `agree()` raises if this generator's scanner and `json.loads` ever
  disagree, so the generator cannot print a fixture that pins a grammar bug.
- CPython's own lexer — `py_scanstring` and the scanner's `NUMBER_RE` —
  independently produces the span of every string and number in the accepted
  documents, and `spans()` raises if a span the generator reports is not the one
  CPython found.
- What is left — *where* a refusal points, and what the budget costs — is this
  parser's own contract, stated in `power/json.bend`'s header and pinned here.

Three classes of row are exempt from the accept/reject check, each for a stated
reason: a budget refusal is not a grammar verdict (CPython has no budget), and
those rows also skip the span check; CPython's decoder recurses, so it answers
`RecursionError` rather than a verdict on the depth-ceiling documents; and
`json.loads` accepts `NaN` / `Infinity`, which are not JSON, so those refusals
are this parser's and not CPython's to confirm.

**Mutants** (the fixture reaches the branches): dropping the leading-zero rule,
forcing the container-kind check in `pop.obj.if` to `True`, and forcing the
affordability test in `charge.if` to `True`. Each fails 4 of 6 lanes.

Two bugs the oracle caught and the fixture now pins: `{"a"` reported `!char@4`
where the input simply ended (`Cut`), and a bad hex digit was reported one byte
past itself (`\u12x` said `esc@4`, not `esc@3`).

## Measured (Ryzen 7 7700X, 8 cores / 16 threads, `--gpu off`, medians of three)

| bench | what it runs | C | bend 1T | bend 16T | 1T/C | 1T→16T |
|---|---|---:|---:|---:|---:|---:|
| `json` | 200,000 records, 10.8 MB, scanned 4x | 0.06 | 0.33 | 0.34 | 5.9x | 1.0x |
| `json_par` | the same work, 2^8 blocks of 800 | 0.05 | 0.32 | **0.05** | 6.2x | **6.7x** |

`{"i":12345,"s":"abcdefgh","b":true,"a":[12345,12345]}`, 54 bytes a record.
Every event is folded into the checksum *with its span*, so a span off by one
changes it, and the row is only timed once Bend's checksum equals the C twin's.

**This is the worst 1T/C in the library** (the rest run 0.9x–2.4x, apart from
`topk_par`'s 4.5x), so the split is worth stating. Taking the slope of 1 / 4 /
7 passes:

| | per pass over 10.8 MB | per byte | per step |
|---|---:|---:|---:|
| C twin | 12.6 ms | 1.2 ns | 3.3 ns |
| this parser | 69.7 ms | 6.5 ns | 18.3 ns |
| a bare `Bytes.at` walk | 4.1 ms | 0.38 ns | — |

A record is 19 steps: 13 events and 6 commas, a comma being the one step that
emits nothing. So the parser is **not** memory-bound — reading every byte costs
6% of its time — and it is not the byte scanners either. It is the ~18 ns of
per-token scaffolding: `next` rebuilds a seven-field `St`, an `Event`, a `Tick`
and the pair it returns, where C mutates one struct through a pointer. That
cost is the affine value-threading itself, which is also exactly what buys
`skip`, a forkable state, and a parser with no global.

Parallel it is the best-behaved lane in the library: 6.7x on 16 threads, and
unlike radix the fork is genuinely free — there is no shared cursor table, so
what a leaf owns is just its own document.

## One optimisation that landed, and its size

`spaces` and the dispatcher's `peek` were fused into `Look{b, i, c, on}`: the
whitespace loop now stops on the first non-space and hands that byte back, so a
step reads its dispatch byte once instead of twice, and a document with no
whitespace between two tokens never allocates a second `Look`. Worth **5%**
(73.5 → 69.7 ms a pass), which is the useful finding: the allocations are not
the cost, the dispatch chain is. Both callers wanted the same pair, so
`spaces`, `spaces.if/on/go/out` are gone and the file is shorter for it.

## Written for Bend

- The checker forbids mutual recursion outside Base, so every scanner is one
  self-recursive loop over a record whose field says whether to keep stepping
  (`Res{Go,Ok,No}`, `Hex`, `Dig`, `Look`) — an early exit has to be a *state*,
  not a second def calling back.
- Reading past the end gives 0, which starts no json token, so every scanner
  indexes without a bounds test of its own.
- `U32.shrn`/`shln`/`to_nat` all have native rows (`comp.ts:192,210`), so a
  runtime shift amount and a runtime `Nat` fuel are both O(1) in the compiled
  lanes. The "a runtime shift is an n-step loop" rule is an interpreter rule.
- An imported constructor must be qualified in `match` — `case Json.ObjOpen{}:`,
  not `case ObjOpen{}:`.
- `U32.div` has a native row too (`comp.ts:181`), and measures it: 10,000,000
  divisions cost 4.7 ms against 1.5 ms for the same loop doing `U32.and`, which
  is one hardware divide, not the 32-step `Word(32n)` loop `base.bend` spells
  out for the checker. The same correction as `shrn` above — `base.bend`'s
  definition is what the interpreter runs, not what the C lane emits.
- The bench checksum needs a rotate. A plain `acc*31 + x` over 200,000 copies of
  one record is a geometric series whose 2-adic valuation climbs: the checksum
  arrived with 18 trailing zeros, and the forked tree fold over 256 such blocks
  came out **exactly 0**. `json_par` blocks also stride by 801, not 800: with an
  even stride every block draws the same `true`/`null` pattern and all 256
  leaves are identical.

## Deliberate ceilings

- **`\u` escapes are validated, not applied**, and UTF-8 is not decoded. `raw`
  hands back the span one `Char` per byte. Unescaping is the consumer's choice
  and belongs with lane 15 (text identity), which owns the normalization tables.
- **No lone-surrogate check** and **no UTF-8 validity check on string bodies** —
  `\uD800` alone and a stray 0x80 both pass. Bytes below 0x20 are refused, which
  is the grammar's own rule.
- **Depth is capped at 256** containers (`Deep`), which is the Bitset the state
  carries. Raising it is one constant and a bigger Bitset.
- **No schema check.** It is a consumer of the event stream, not a change to the
  parser, and lane 17 generalizes the state machine to a grammar — writing it
  twice would be the waste.

## Battery

power 54/0 (+ control) · repo 54/54 · caps ok · bench 14/14 checksums match C.
`power/json.bend` is 11,911 ttok against the 64,000 cap; the fixture, the
generator and the two benches are 6,733 / 5,678 / 1,837 / 1,828 against 16,000.
No `comp.ts` row, no `base.bend` change, no new effect: the lane needed none.

## Next

Wave 1 is closed: Vec/Bytes/Bitset, RNG, Heap/TopK, Scan, Radix, Json. Wave 2
opens with lane 6, BM25 + posting algebra — the first lane with a consumer for
all of them at once, and the one that finally wants Bitset `to_list` /
next-set-bit and an F32 key for the heap.
