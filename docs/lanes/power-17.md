# power-17 — Grammar: a constrained-decoding state that forks (2026-09-20)

Lane 17. One file, one claim: **a grammar state small enough to copy is a
grammar state you can fork.** Constrained decoding needs the set of legal next
tokens at every position, and a sampler that wants to score several candidates
needs that set from *the same state*, several times over. Every table-driven
parser in the world can tell you whether a byte is legal. Almost none of them
let you ask the question twice from one position without rebuilding something.

`power/grammar.bend` is a JSON byte grammar whose whole state is five U32s and
a tag — kind `Data`, so it copies, drops, and rides inside a `Result`. A fork
is not an operation on it. Both children just *get* it.

## What shipped

### `power/grammar.bend` — the automaton, and the mask it derives

- `start() -> St`, `step(s, c) -> St` — the transition. A dead state keeps
  stepping and stays dead, so no caller needs an early exit.
- `mask(s) -> Mask` — the 256 bits of legal next bytes, **derived from the node
  in one read**, not by trying all 256.
- `allows(s, c) -> Bool`, `live(s) -> Bool`, `done(s) -> Bool` — the three
  verdicts. `done` is acceptance: depth 0 and a node that can end a document.
- `depth(s) -> U32`, `node(s) -> Node`, `show(s) -> String` — the state, readable.
- `run(b, s) -> Walk` — a whole `Bytes` through the machine.
- `Mask.has/or/word`, `Mask.show` — the mask as a value, and as byte ranges.

`type St is Data: St{n: Node, depth: U32, k0: U32, k1: U32, kf: U32}`. The
container stack is two U32s of kind bits — one bit per open container, 1 for
an object and 0 for an array — and `kf` is the single bit that says the string
being scanned is a key, so its closing quote goes to a colon and not to a
separator. There is no `Array` anywhere in the state, and that is the point:
an `Array` would make `St` kind `Type`, one owner, and the lane would be over.

### The law the lane exists for

    allows(s, c)  ==  live(step(s, c))

The mask is computed one way (read the node, or the top kind bit at a
separator) and the truth is computed the other way (step the byte, see if it
died). A constrained decoder that masks with the first and steps with the
second is only correct if they agree, and they are written to agree by
construction, not by sharing code. `tests/power/grammar.bend` prints them side
by side for every reachable node.

## Rule 7 — the scope call: nothing was cut

The handoff said to cut anything speculative, unreachable, or untestable, and
that a smaller pinned module beats 1,212 unverified lines. I measured before
I cut, and the measurement said don't.

- **139 defs, 0 unreferenced.** Every def is reached from `step`, `mask`,
  `run`, `show` or the fixture's own surface. The cross-reference is over
  `power/grammar.bend` itself plus the three files that import it as `Gr`.
- **32 `Node` constructors, 32 pinned.** Every one has a `pin` row in the
  fixture where its derived mask is printed beside a brute-forced one. There
  is no state in the type that the test cannot reach and does not check.
- **476 reachable states**, enumerated by breadth-first search over all 256
  bytes to depth 3. The fixture's 70 `pin` rows cover one state per distinct
  reachable node-and-kind shape.

The honest version of "I cut nothing" is that the file was already the size of
its job: 32 nodes because JSON has 32 lexical positions, 21 mask constants
because that is how many distinct byte classes those positions ask for, and a
`cont`/`shift` split because a number is the one JSON token with no closing
byte and has to end at the first byte that cannot continue it.

## The four header counts that were wrong

All four bench files stated a document count the code does not run.

| file | header said | code runs |
|---|---|---|
| `bench/grammar.bend` | 262,144 documents, 20,709,376 positions | 2,097,152 / 85,983,692 |
| `bench/twin_grammar.c` | 1,048,576 documents, 82,837,504 positions | 2,097,152 / 85,983,692 |
| `bench/grammar_par.bend` | 256 shards of 4,096 | 256 shards of 8,192 |
| `bench/twin_grammar_par.c` | 256 shards of 4,096 | 256 shards of 8,192 |

The counts are not a typo, they are a number nobody could reproduce from the
file. `many(2097152n, 0, 0)` is the sequential loop and `many(8192n, ...)` is
the shard; a later lane sizing its own bench against "82,837,504 masks" would
have been comparing against a figure that was never run.

The corrected numbers are **counted, not estimated**: the document shape is
`d = 1 + ((x >> 29) & 7)` levels and `w = 2 * (1 + ((x >> 24) & 31)) - 1` body
bytes over `x = (o ^ (o >> 15)) * 2654435761`, so the position count is the sum
of `2d + w` over all 2,097,152 offsets, run through the same expression in
Python. It comes to 85,983,692 — an average of exactly 41.0 bytes a document,
between the 3-byte and 79-byte extremes the shape function can draw. The
headers now say 3 to 79 bytes rather than a single width, because no document
in the bench is 79 bytes except the ones that are.

These were comment-only edits. No code in any bench changed, and the checksums
are the ones the gate already matched against C.

## Verified

`bash tests/power/run.sh grammar` — **6 lanes, 0 fail**, plus the control (the
runner first holds the comparison path to a deliberately wrong `#|` fixture and
requires it to be reported failing):

    ok   wrong #| fixture detected as failing
    ok   grammar              [oracle]
    ok   grammar              [check]
    ok   grammar              [interpret]
    ok   grammar              [js]
    ok   grammar              [c]
    ok   grammar              [c-1thread]

### The oracle is two authorities, not one

`tests/power/grammar_gen.py` prints all 177 rows. It would be worth very little
if it were the Bend transition function transliterated, so it is checked twice
from outside itself:

1. **Accept/reject comes from CPython `json.loads`.** The generator asserts
   `done(s) == loads_ok(d)` for all 96 documents and refuses to print a row it
   disagrees with. 44 valid documents, 52 invalid ones — `01`, `1.`, `.5`,
   `1e+`, `[1,]`, `{a:1}`, `'a'`, `nulll`, `"a<TAB>b"`, `NaN`, `Infinity`,
   `1e2e3` and the rest of the traps a hand-written JSON parser falls into.
2. **The mask comes from brute force.** `brute(s)` is
   `[c for c in range(256) if live(step(s, c))]` — the opposite derivation from
   the module's single node read. A `pin` row prints the module's derived mask
   and the brute-forced one in the same line, so a row where they differ is the
   constrained-decoding bug caught in the act.

The 177 rows: 96 `doc`, 70 `pin`, 6 `fork3`, 5 `deep`.

### The fork rows

A `fork3` row takes one state value, runs **three different continuations from
it**, and then prints the parent again:

    fork3(at("{\"a\":"), "1", "\"x\"", "[")
      -> val/1 -> int/1 sep/1 vale/2 -> val/1

First field and last field are the same state. That equality is the lane's
claim in one line — no rollback, no checkpoint, no rebuild, and no continuation
able to reach back and disturb the parent. In a language where the state held
an `Array`, the row would not typecheck.

### Mutants — 7 run, 5 caught, 2 proved equivalent

Each mutant was applied by script in `/tmp`, run through all six lanes, and the
file restored with the restore asserted by SHA.

| # | mutation | verdict |
|---|---|---|
| M1 | `mask(Int)` drops `M.dote()` — `.` and `e` still step, just aren't advertised | **caught**, 4 lanes |
| M2 | `cont(Zero)` also accepts a digit | **survived — equivalent** |
| M3 | `mask.sep` swaps `}` and `]` — the kind bit, mask side | **caught**, 4 lanes |
| M4 | `push` ceiling 64 → 65 | **caught**, 4 lanes |
| M5 | `after()` keeps the key flag instead of clearing it | **survived — equivalent** |
| M6 | `str.ctl` admits bytes < 32 — a raw tab inside a string | **caught**, 4 lanes |
| M7 | `top.raw` reads kind bit `d`, not `d - 1` | **caught**, 4 lanes |

M1 is the mutant worth having. It changes *only* the mask and leaves every
accept/reject verdict identical, so the 96 `doc` rows pass it untouched — it
dies on the `pin` rows alone. That is the evidence that the mask/step law is
actually pinned and not just implied by the parser being right.

**The two survivors are equivalent mutants, and I checked rather than assumed.**
Replaying both against the oracle's own PDA over all 476 reachable states × 256
bytes gives **0 differing (state, byte) pairs** for each:

- **M2.** `cont` only matters when it returns *false*, because false is what
  fires `after()`. Letting `Zero` continue on a digit removes that `after`, and
  then `shift(Zero, digit)` is dead — while with the `after`, `shift(Fin, digit)`
  and `shift(Sep, digit)` are dead too. Same answer by both routes, and the mask
  never reads `cont` at all. `01` stays rejected either way.
- **M5.** `after()` is only reachable from value-ending nodes, and the key flag
  is already cleared at the key's closing quote on the way to `Colon`. No
  reachable state has `kf` set where `after()` can fire — the search counts
  zero. The clear is defensive, not load-bearing.

Both are dead code in the sense that matters: removing the redundancy would not
change a single answer. Neither is a hole in the fixture, and I am not adding
rows to "catch" a mutation that does nothing.

## Measured (Ryzen 7 7700X, 8 cores / 16 threads, `--gpu off`, medians of three)

`flock /tmp/bend-bench.lock bash tests/power/bench/run.sh grammar`. Both rows
checksum-matched the C twin at `--threads 1` **and** `--threads 16` before any
timing was taken.

    bench             C  bend-1T bend-16T    1T/C  1T/16T
    grammar        0.33     0.83     0.82    2.5x    1.0x
    grammar_par     0.32     0.87     0.14    2.7x    6.4x

2,097,152 documents, 85,983,692 masks derived, in both rows. **The mask is
derived at every position, before the byte is stepped** — a bench that only
called `step` would measure half the primitive and the cheaper half.

The checksum folds all eight mask words plus the depth, not the three words
that carry ASCII: a word neither side reads is a word either compiler may stop
computing, and then the two are not doing the same work.

### 2.5x against `-O3` C, and where it goes

C keeps the whole state in four scalars — `uint8_t n, d, f` and a `uint64_t k`
— and its `switch` is a jump table. Bend's `St` is a heap record with a `Node`
tag, and `mask` returns an eight-word `Mask` record per position. 2.5x for a
32-state pushdown automaton carrying a real 256-bit mask out of every step is
the record-versus-register gap and nothing more exotic.

### 6.4x on 16 threads, and why the sequential row is 1.0x

The sequential bench has **no fork in it at all** — `many` is one loop over
2,097,152 documents, so 1.0x at 16 threads is the correct answer, not a
scaling failure. All the threading lives in `grammar_par.bend`.

**The shard boundary is the document offset, and nothing else.** `shard(s)`
owns offsets `s * 8192 .. s * 8192 + 8191`; `par(8n, 0)` is a perfect binary
fork tree of depth 8 over 256 of them, joined with `tmix`. This is the only
`_par` bench in the library that needs **no shard-private buffer**: `bm25_par`,
`knn_par` and `cdc_par` all shard because a `Bytes` or an `Array` has one owner
and no two lanes can read one. A grammar state is five U32s and a tag, and the
document is a function of its index rather than a buffer, so there is nothing
to split — the fork is free because the data is `Data`.

### Is 6.4x the tree working, or the shard size being lucky?

Neither — it is the **task count**. Holding total work fixed at 2,097,152
documents and varying only how they are cut (built in `/tmp` against a copy of
the module, so nothing landed in the shared bench directory; medians of three,
under the same lock):

| shards | docs/leaf | 1T | 16T | 16T speedup |
|---:|---:|---:|---:|---:|
| 16 | 131,072 | 0.94 | 0.49 | 1.9x |
| 64 | 32,768 | 0.93 | 0.29 | 3.2x |
| **256** | **8,192** | **0.92** | **0.18** | **5.2x** |
| 1,024 | 2,048 | 1.03 | 0.26 | 4.0x |
| 4,096 | 512 | 0.97 | 0.18 | 5.3x |

The single-thread column is flat across a 256-fold change in leaf size, so the
fork tree itself costs nothing measurable down to 512 documents a leaf. What
moves is the 16-thread column, and it moves with the *number* of tasks: 16
shards on 16 threads is 1.9x because one slow shard is 1/16th of the run with
nowhere to migrate, and the shape function draws documents of 3 to 79 bytes, so
shards are not equal work. By 256 tasks the scheduler has enough to balance
and the curve flattens.

**This is the same finding as lane 10** (`docs/omen/lanes/power-10.md`, "leaf
granularity beats leaf count"), reached from the other side. `assign_par`'s
first draft bundled eight solves into each of 2^6 leaves — fewer, bigger
leaves, less scheduling overhead — and ran **3.5x**. One solve a leaf, 2^9
leaves, runs **6.3x**. Its reason is the reason here: a leaf that bundles eight
solves bundles their variance too, and the slowest leaf sets the clock.

Lane 17 draws documents of 3 to 79 bytes from a hash, so its leaves have the
same variance problem and answer to the same fix.

**But variance is not the whole reason, and lane 9 is the file that proves it.**
`cdc_par`'s shards are *uniform* — 64 KiB each, the same four scans — and it
went 3.4x at 64 shards to 6.8x at 256 on identical total work, the same curve
this table draws. Even leaves, same 2x. So the rule the three lanes share is
stronger than the variance argument alone: **oversubscribe by a wide margin
whether or not the leaves are even.** Variance raises the price of getting it
wrong; it is not what sets the price. `docs/omen/lanes/power-9.md` states it
that way and cites this table; the pointer goes both ways.

(I was handed a summary of lane 10 that said it went 3.5x → 6.3x by making
leaves *bigger*. It says the opposite. The table above was measured before I
read power-10.md and agrees with power-10.md, not with the summary.)

The 5.2x in this table and the 6.4x in the gate row are the same configuration
measured twice on a machine running six other lanes; the sweep is a relative
comparison within one pass, the gate row is the number of record.

## Written for Bend

**The depth-0 guard is not decoration.** `U32.sub(0, 1)` wraps to 4,294,967,295
and `U32.to_nat` of that builds a four-billion-long unary number. A missing
guard before a `pop` is a hang, not an error, so `top` checks `depth == 0`
before it ever computes `d - 1`.

**No mutual recursion, so the transition is a dispatch chain.** `shift.at`
matches the node and hands each case to its own non-recursive helper
(`st.val`, `st.str`, `st.zero`, …), each of which answers with a state record.
The only self-recursive def in the file is `run.go` over a fuel `Nat`.

**The kind stack is two U32s because 64 is what a `Data` record can hold.** One
U32 would cap nesting at 32; an `Array` would lift the cap and cost the state
its kind, which is the whole lane. `push.mk` picks the word by `d < 32` and the
bit by `d` or `d - 32`.

**`U32.shln`/`shrn` take a `Nat`**, so every shift by a runtime value goes
through `U32.to_nat` — which is why the bit helpers take the index as a `U32`
and convert once at the bottom.

## Deliberate ceilings

- **64 open containers.** The 65th `[` or `{` is refused — the state goes dead
  — rather than silently flattened. `deep(64n)` accepts and `deep(65n)` is
  dead, and the generator asserts `json.loads` takes both, so the row records a
  deliberate divergence from CPython rather than a parse bug.
- **Bytes, not code points.** `M.body()` admits 32–255 inside a string. There
  is no UTF-8 well-formedness check, because a constrained decoder masks
  *bytes* and a token that ends mid-sequence is still a legal token. A caller
  that needs well-formedness composes it; the grammar does not guess.
- **`\uXXXX` is four hex digits, not a surrogate pair check.** `U1`–`U4` accept
  any hex; an unpaired surrogate passes. Same reason.
- **No numbers are evaluated.** The machine says whether a byte may follow, not
  what the number is. `1e999` is legal here and infinite in CPython.

## Battery

power 6/0 (+ control) · repo 53/54 · caps ok · bench 2/2 checksums match C.

The one `repo.ts` failure is **`d_probe.bend` at the repo root, which is not
mine** — I did not create, edit, stage or delete it, and it is reported rather
than fixed. Every file this lane owns passes. (`git add -N .` from any lane
stages every untracked file in the tree, which is how a foreign probe ends up
in the gate's view.)

`power/grammar.bend` 9,862 ttok against the 64,000 cap; the fixture 6,165 and
its generator 4,640 against 16,000; the benches 1,578 and 1,653; the twins
3,572 and 292. **No cap moved and `gates/repo.ts` was not edited** — lines
76–77 already allow `power/*.bend` and `tests/power/**`, so the lane needed no
new row. No `bend2/` change of any kind: no `comp.ts` row, no `base.bend`
addition, no new effect. No `@unsafe`, no `?TODO`. Nothing committed.

## Next

- **`allows` has no bench.** The library ships `mask` (one node read, all 256
  bits) and `allows` (one bit). A decoder with a 128k-token vocabulary calls
  the second a great many more times than the first, and the two have different
  costs; the bench only measures `mask`.
- **The beam is described but not measured.** `fork3` proves one state feeds
  three continuations; no bench runs *n* candidates from one position and shows
  the shared-parent saving against re-running the prefix. That is the row that
  would make the lane's claim a number instead of a type-check.
- **The kind stack could be one U64.** It is two U32s because `push.mk` was
  written against U32 helpers. A U64 pair would still be `Data`, still cap at
  64, and would delete the `d < 32` branch from four defs.
- **Nothing here is JSON-specific except the 32 nodes.** `St`, the mask
  algebra, the container stack and the `cont`/`shift` split are a grammar
  shape, not a JSON shape. A second grammar in the same skeleton would say
  whether that is true or whether JSON is quietly baked into the frame.
