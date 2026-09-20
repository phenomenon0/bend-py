# Strings lane — continuation report (fable, 2026-09-18)

Branch `lane-strings`, worktree `bend-work-strings`. Continues the first-class-strings work
(two-word view descriptor `{payload, off<<32|len}` over a counted packed-U32 payload). The
previous session exited while a background suite was still running; this session ran everything
in the foreground. Nothing pushed. Machine shared with two other lanes throughout (load 1.2–2.2).

## Commits

| commit | content |
|---|---|
| `9e2d3076` | JS `io_text`: native fatal `TextDecoder` (`ignoreBOM`) on well-formed chunks, per-byte walk only when it rejects. |
| `f7c3116b` | C `str_uncons`: a count-one descriptor advances in place; `runtime.c` probe for unique / shared / last-cell. |
| this | report. |

## 1. Decode fix (`9e2d3076`) — verified

Measured before commit (previous session): 8 MiB decode **270 ms / +270 MB → 3.4 ms / +0** (ASCII),
**360 ms / +400 MB → 5.9 ms** (Unicode); output-equal on `utf8.bin`, both bench corpora and 2,000
random byte strings. The contract is unchanged: one U+FFFD per ill-formed byte, BOM is an ordinary
U+FEFF, because `fatal: true` rejects exactly the chunks the byte walk must handle.

Full-suite verification this session, on `9e2d3076` with the uncommitted `str_uncons` change set
aside: strings **85/85** (second run; see flake below), `tests/run.sh` **16/16**, codex
**161/161, 0 suite errors**, regex **40/40**.

## 2. Refcount churn (`f7c3116b`) — landed

`match s: case SCon{c, t}` compiles to `str_uncons`. It used to `str_take` the descriptor (free
descriptor + count cell) and `str_view_owned` a new one (alloc descriptor + count cell) per code
point. With a count of one the descriptor is private to the caller (the emitter `val_own`s the
root first; a borrowed root arrives with count ≥ 2), so `off/len` advance in place and the same
`Term` is returned. Shared descriptors and the final cell keep the old path, so an alias never
observes the advance and the last cell still releases descriptor and payload. Rfc'd descriptors
are always heap (`rfc_seal`/`term_keep` skip trivial terms), so static literals never reach the
in-place write.

`tests/strings/bench.sh`, 8 MiB `io` cases + `legacy-4096`, C lane, `--threads 1`. Counters are
the harness's instrumented `heap_alloc` calls over the process phase (deterministic). Wall is 15
interleaved base/new runs of the same binaries, median (needed because of the shared machine —
the harness's own sequential 7-run medians moved ±40 % between runs on unchanged JS).

| workload | allocs before | allocs after | Δ | wall ms before → after |
|---|---:|---:|---:|---|
| legacy-4096 | 454,668 | 241,676 | −47 % | 4.1 → 3.6 (−13 %) |
| ascii-8MiB scan | 19,979,125 | 11,191,059 | −44 % | 129.4 → 110.3 (−15 %) |
| ascii-8MiB materialize | 19,972,889 | 11,184,823 | −44 % | 154.3 → 131.7 (−15 %) |
| unicode-8MiB scan | 13,287,433 | 9,792,177 | −26 % | 90.3 → 83.9 (−7 %) |
| unicode-8MiB materialize | 13,281,977 | 9,786,721 | −26 % | 109.3 → 102.6 (−6 %) |

Every run's output equals the Python oracle; frees track allocs (live returns to the same value).
Peak RSS is unchanged (the saving is churn, not footprint).

Verification with the change: strings **85/85**, `run.sh` **16/16**, codex **161/161**, regex
**40/40**, `python3 tests/strings/runtime.py` all sections ok (ASan/UBSan, ownership with zero
live, 77 injected allocation failures, JS UTF-8/oracle). The GPU lane is covered by the strings
suite's `[gpu]` rows (`--gpu 4GB` on every specimen using `!(`), all ok. New probe in `runtime.c`:
unique uncons performs **zero** allocations and returns the same `Term`; after `term_keep` the
alias still reads `"bcd"` while the tail reads `"cd"`; a one-cell string yields `SNil` with zero
live. The probe aborts on the previous runtime (checked) and passes on this one.

JS is untouched: JS strings are native and have no descriptor churn.

## 3. Streaming decoder — design only (no code)

### Problem

`File.read(f, max)` decodes each chunk independently (`io_str` in C, `io_text` in JS). A scalar
split across two reads becomes 1–3 U+FFFD at the end of one chunk and 1–3 at the start of the
next, so chunked reading is *not* equal to whole-file reading, and a whole-file read needs
`4·bytes` of payload (U32 cells) resident. Inputs larger than RAM need chunked reads whose
concatenation is exactly the whole-file decode.

### Data shapes

```
type Utf8.Dec = Dec{pend: U32, need: U32}      # two words of state, pure data
def Utf8.Dec.new : Utf8.Dec                    # Dec{0, 0}
def File.read_text(file: File, dec: Utf8.Dec, max: U32) ->
  IO(File & Result<&1, &1, U32 & String, Utf8.Dec & String>)
def Utf8.Dec.end(dec: Utf8.Dec) -> String      # "" or the U+FFFDs owed for a cut tail
```

- `pend` packs the ≤ 3 carried bytes of an incomplete sequence (`b0 | b1<<8 | b2<<16`), `need`
  their count (0–3). The lead byte determines the expected length, so no other state exists. It
  is a plain value: no handle, no runtime table, copyable, identical on C, JS and the interpreter.
- The returned `String` is an ordinary two-word view over a fresh counted payload of at most
  `max + 3` cells. Nothing in the view model changes; the consumer's `take/drop/uncons` walk it
  with the in-place advance from §2, and dropping it frees that chunk's payload.
- `File.read` keeps its per-chunk contract (existing specimens pin it); `read_text` is additive.

### Ownership across chunk boundaries

- Carried bytes live **only** in `Dec` (one U32). No chunk's payload is referenced by the state or
  by the next chunk, so memory is bounded by the chunks the *program* retains, never by the
  decoder. This is the reason to carry bytes rather than a view of the previous chunk's tail.
- A consumer token that spans chunks (a word cut by the boundary) is the consumer's business:
  it keeps the unfinished tail view and `String.append`s the next chunk. The tail view pins the
  old payload until then — `String.copy` (already present, class-fitted) un-pins it; the note
  for users is "copy a carried tail shorter than the chunk".
- Read buffer: `malloc`ed per call and freed in `_pack`, as `file_read.c` does today. `Dec` moves
  through the call linearly (consumed, new one returned) — no sharing to reason about.

### Error semantics at boundaries

The law, which is also the oracle: **for every byte string `B` and every partition of `B` into
chunks, `concat(chunks decoded via read_text) ++ Dec.end(final) == io_str(B)`**, with `io_str`
being today's whole-buffer decoder (one U+FFFD per ill-formed byte).

- Carried bytes + new bytes form a valid scalar → emit it at the start of this chunk.
- A truncated sequence at the end of a chunk (a lead plus fewer continuation bytes than it
  announces) is carried, whatever its second byte: no viability table is needed, because a later
  rejection replays exactly what the whole-buffer walk does.
- The completed sequence is ill-formed (bad continuation, overlong, surrogate, > U+10FFFF) → emit
  U+FFFD for the carried lead and re-examine every following byte as a fresh lead. Carried
  continuation bytes are each ill-formed alone, so this is one U+FFFD per carried byte, then the
  offending byte decoded normally — byte for byte `io_str`'s behaviour (`E2 82 41` → `FFFD FFFD A`;
  `E0 80 80`, `ED A0 80` → three U+FFFD wherever the cut falls).
- A chunk that only extends a still-incomplete carry returns `""` with a longer carry, so `""`
  alone does not mean EOF. EOF is a 0-byte `read`: `""` **and** a returned `dec` equal to the one
  passed in (consumed bytes always change `dec` or produce output). The caller then emits
  `Dec.end`: one U+FFFD per carried byte, as `io_str` does for a sequence cut by end of buffer.
  Recommended; the alternative (return the byte count, or a `File.eof` effect) is listed under
  Uncertainties.
- OS errors return `Fail` exactly as `File.read`; the `Dec` passed in is lost with the failed
  call, so a retrying caller must keep its own copy (it is a copyable value).
- BOM: ordinary U+FEFF, first chunk included. No normalization, no newline translation.
- `max = 0` is a no-op read returning `""` and the same `dec`.

### Implementation sketch (for the slice that builds it)

One shared C routine `io_str_dec(e, p, n, &pend, &need)`: today's `io_str` loop with (a) a
3-byte prelude buffer logically prepended, (b) `k <= n - i` failing at end of buffer into
"carry" instead of "replace". `io_str` becomes the call with no carry followed by
`end`, so there is one decoder, not two (ttok: comp.ts has ~585 tokens of headroom at 76,000 —
this must be a refactor of `io_str`, not a second loop; see Uncertainties). JS: `TextDecoder`
with `{fatal: true, ignoreBOM: true}` and `stream: true` does **not** expose its carry, so the
fast path is: compute the truncated-suffix length (≤ 3 bytes, a backwards scan), decode
`carry ++ chunk[0 .. n−suffix]` with the existing fatal decoder, fall back to the byte walk on
reject. Same two-tier shape as `9e2d3076`.

### Acceptance tests

1. **Partition law, exhaustive small:** every byte string of length ≤ 4 over the alphabet
   `{00, 41, 80, BF, C2, E0, ED, F0, F4, A0, 90, FF}` × every partition → equals `io_str(B)`.
   Runs in `runtime.c` (C) and `runtime.py`'s JS section.
2. **Partition law, random:** 2,000 random byte strings (the §1 corpus generator) × random
   partitions including 1-byte chunks; plus `utf8.bin` at every single split point and at chunk
   size 1. CPython cross-check: `codecs.getincrementaldecoder('utf-8')('replace')` is **not**
   the oracle (it emits one U+FFFD per maximal subpart, not per byte); the oracle is whole-buffer
   `io_str`, itself already pinned against the Python per-byte model in `runtime.py`.
3. **Boundary errors:** `E2 82 | AC` → `€`; `E2 82 | 41` → `FFFD FFFD A`; `F0 9F | <EOF>` →
   `Dec.end = FFFD FFFD`; `ED | A0 80` and `ED A0 | 80` → `FFFD FFFD FFFD`.
4. **Bounded memory:** instrumented counters (bench.sh tracker): scanning a 64 MiB file in
   64 KiB chunks has peak live bytes ≤ `c · chunk`, independent of file size (run at 8 and 64 MiB,
   assert equal peaks); zero live at exit; ASan/UBSan clean; injected allocation failure at each
   alloc site leaves zero live.
5. **End-to-end specimen** `tests/strings/io_stream.bend`: word count + rolling hash of the
   unicode bench corpus through `read_text` at chunk sizes 1, 7, 4096 equals the whole-file
   `File.read` answer; C, JS and interpreter lanes identical.
6. **Non-regression:** `File.read` specimens and `io_utf8` unchanged byte for byte.

### Slice plan

| slice | content | gate |
|---|---|---|
| T0 | `Utf8.Dec` type + pure reference decoder in `base.bend` over `List<U32>` bytes (the spec, used by the interpreter lane and as test oracle); partition law stated as a `law`. | check + interpret; base ttok reading |
| T1 | C: refactor `io_str` into the carry-aware routine; `file_read_text.c`; tests 1–3 in `runtime.c`. | runtime.py, strings suite, comp.ts ttok ≤ cap (orchestrator decides cap on the measured number) |
| T2 | JS: suffix-scan + fatal fast path + walk fallback; `file_read_text.js`; tests 1–3 JS side, decode timing vs `9e2d3076` numbers (must stay within 10 %). | runtime.py JS sections |
| T3 | Specimen `io_stream.bend` (test 5), bounded-memory counters (test 4) in bench.sh as a `stream` mode. | strings suite count +4, bench table |
| T4 | Report, EOF-signal decision recorded, README note on carried tails + `String.copy`. | full suite set, clean tree |

Out of scope by design: sockets (`read_text` is written against the fd effect and would port as
is), encodings other than UTF-8, grapheme-aware chunking, mmap-backed payloads (a possible later
answer to "larger than RAM *and* random access"; it would need a payload origin the three-part
`str_writable` test already has a slot for — `>= HEAP_OFF`).

## ttok readings (measured this session)

| file | reading | cap |
|---|---:|---:|
| `bend2/base.bend` | 42,318 | 43,000 |
| `bend2/comp.ts` at `9e2d3076` | 75,220 | 76,000 |
| `bend2/comp.ts` at `f7c3116b` | **75,415** | 76,000 |

Correction to the handed-over numbers: 75,415 is the reading *with* the in-place change (+195),
not before it. `tests/strings/runtime.c` is not under a cap. Headroom in comp.ts is 585 tokens;
slice T1 cannot land as an added loop under the current cap.

## Uncertainties and flakes

- **`deep` flake, pre-existing, frontend-side.** `tests/strings/deep.bend` intermittently dies with
  "the machine stack overflowed" in the bun frontend (seen at `[interpret]` and at `[c build]`,
  i.e. before any emitted runtime code runs). Sampled 60 builds each, interleaved: **11/60 on
  `9e2d3076`'s comp.ts, 16/60 with the change** — not distinguishable (p ≈ 0.28), and the C
  runtime text is not executed by the frontend. With four bun steps per specimen the strings
  suite therefore goes red roughly every second run on this loaded machine: this session saw
  84/1, 85/0 on `9e2d3076` (the first failure's specimen was not captured — my omission — but
  the retry was clean) and 84/1 (`deep [interpret]`), 84/1 (`deep [c build]`), 85/0 with the
  change. The cause is presumably JIT-tier-dependent frame size in `bend.ts`/`main.ts`, which
  this lane may not touch; the regex lane reported the same flake. Needs an owner.
- Wall-time gains (−6 … −15 %) were measured under foreign load; the interleaving controls for
  it but the absolute numbers are soft. The allocation counts are exact.
- The in-place path reads the count with `rfc_view` (same acquire discipline as `ctr_take`) and
  relies on "count one ⇒ exclusive owner", the invariant `str_writable` already relies on. No
  multi-threaded specimen specifically races `str_uncons`; codex/strings thread lanes pass.
- Streaming EOF signalling (`""` + unchanged `dec` vs. an explicit flag or `File.eof`) is the one
  open API decision in §3; it should be settled in T0 before any effect code is written.
- JS `TextDecoder` fast path in T2 assumes the backwards suffix scan is cheap relative to decode
  (≤ 3 bytes inspected); unmeasured.
