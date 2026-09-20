# Strings lane — streaming UTF-8 decoder T0–T4 (fable, 2026-09-18)

Branch `lane-stream`, worktree `bend-work-stream`, off `130bc136` (omen's tip was one docs
commit ahead, `f9a4b7d2`; `lane-adaptive` had not merged, so nothing collided). Implements the
design in `strings-cont.md` §3. Everything ran in the foreground; nothing pushed. bun 1.3.4,
clang, Linux x86-64, 30 GiB box shared with other lanes.

## Commits

| commit | content |
|---|---|
| `e3550cdd` | T0–T1: `Utf8.Dec`, `File.read_text` (C + JS effect), partition-law probes in `runtime.c` / `runtime.py`. |
| `7347faa7` | `tests/strings/io_stream.bend`, `demos/text_stream/` (chunked scan, whole-file twin, `bench.sh`). |
| this | README note, report. |

## What landed

```
type Utf8.Dec is Data: Dec{pend: U32, need: U32}
def Utf8.Dec.new() -> Utf8.Dec                       # Dec{0, 0}
def Utf8.Dec.eof(dec: Utf8.Dec) -> Bool              # need == 4
def File.read_text(file: File, dec: Utf8.Dec, max: U32) ->
  IO(File & Result<&1, &1, U32 & String, Utf8.Dec & String>)
```

`pend` packs the carried bytes low byte first, `need` counts them (0–3), as designed. The effect
is `File.read_text.go(file, pend, need, max)` over flat U32s (`bend2/effs/file_read_text_go.{c,js}`)
with a small Bend wrapper re-boxing `Dec`, so no host code reads or builds a constructor.
`File.read`, `io_str` and `io_text` are **untouched** — `comp.ts` has a zero-byte diff.

### Three departures from the design note, each measured

1. **No second decoder loop, no `io_str` refactor.** A lead byte is never a continuation byte,
   so the whole-buffer walk always arrives at every lead as a sequence start. The effect
   therefore scans back ≤ 3 bytes for a lead whose sequence is cut by the end of the buffer,
   cuts it off, and hands `carry ++ chunk` minus that suffix to the existing `io_str`/`io_text`.
   The JS fatal-`TextDecoder` fast path is inherited as is. Cost: 0 tokens in `comp.ts`
   (the design expected a refactor under a cap with 585 tokens of headroom).
2. **Carry rule: a cut lead plus *continuation bytes only*.** The note's rule ("carried whatever
   its second byte", then `Dec.end` = one U+FFFD per carried byte) is wrong at end of file:
   `E2 41 <EOF>` must decode `FFFD 'A'` (that is what `io_str` does), not `FFFD FFFD`. With only
   continuations carried, "one U+FFFD per carried byte" is exactly `io_str` of the carry. The
   probe pins `E2 41` explicitly.
3. **EOF protocol (the open question) — decided: the 0-byte read flushes and says so.** On a
   0-byte read with `max > 0` the effect itself decodes the leftover carry (the owed U+FFFDs
   arrive as that call's text) and returns `Dec{0, 4}`; `Utf8.Dec.eof` tests `need == 4`.
   Rejected: `""` + unchanged `dec` (caller must compare states and must remember to call a
   separate `Dec.end` — forgetting it silently drops replacements), and a `File.eof` effect
   (extra syscall and surface). Consequently there is **no `Utf8.Dec.end`** in base. `max = 0`
   is a no-op (`""`, same `dec`, not EOF). A `dec` with `need ≥ 4` passed back in reads as no
   carry. OS errors return `Fail` as `File.read` does.

Not built (said so rather than skipped silently):
- **T0's pure reference decoder in `base.bend`.** IO mains interpret through the JS effects, so
  the interpreter lane does not need it, and base had 682 tokens of headroom. The law is
  enforced against the real decoders instead (below). A pure `Utf8.Dec.step` over
  `List<U32>` (for `File.read_bytes`/socket users) is new public surface for a later cap line.
- **Design test 4 as instrumented live-byte counters in `tests/strings/bench.sh`.** Replaced by
  the RSS curve below plus the ASan zero-live probe; `bench.sh` is unchanged.
- **Sockets.** `TCP.recv` still decodes per chunk; the `_dec` step ports as is.

## The law and its fixtures

*For every byte string `B` and every partition of `B`: the chunks decoded through the carry, then
the end-of-file call, append to `io_str(B)`* (one U+FFFD per ill-formed byte, BOM an ordinary
U+FEFF). Both probes drive the shipped decode step (`file_read_text_go_dec`), not a copy.

| probe | cases | result |
|---|---|---|
| C, ASan/UBSan, alloc tracker (`runtime.c: stream_law`) | every string ≤ 4 bytes over `{00 41 80 BF C2 E0 ED F0 F4 A0 90 FF}` × every partition (incl. interleaved 0-byte reads); 2,000 random strings ≤ 64 bytes × random cuts and 1-byte chunks; `utf8.bin` at every split and at chunk 1; spelled-out boundaries (`E2 82│AC`→€, `E2 82│41`→`FFFD FFFD A`, `F0 9F<EOF>`→`FFFD FFFD`, `E2 41<EOF>`→`FFFD A`, `ED│A0 80`, `ED A0│80`→3×FFFD) | **177,128 partitions ok, zero live** |
| JS (`runtime.py`) | same exhaustive set; all 517 oracle byte vectors at every split and chunk 1; 2,000 random | **180,094 partitions ok** |
| invariants asserted per call | `need ≤ 3` before EOF; EOF → `Dec{0,4}`; idle read changes nothing; consumed bytes always yield text or a longer carry | ok |
| mutation check | carry limited to 2 bytes → C aborts in `stream_check`, JS throws | both caught |
| `tests/strings/io_stream.bend` | hash + chars + words of `utf8.bin` and a written 3,400-byte 1/2/3/4-byte-scalar corpus at chunks 1, 2, 3, 7, 4096 = whole-file `File.read` line; hashes equal an independent Python FNV | check / interpret / JS / C identical |

## T4 — constant memory (measured)

`demos/text_stream/main.bend`: `File.read_text` in 64 KiB chunks; between chunks only a
`Scan{hash, chars, words, gap}` and the `Dec` live. `whole.bend`: the same scan over one
`File.read`. `bash demos/text_stream/bench.sh` — C lane, `--threads 1 --gpu off`, peak RSS from
`/usr/bin/time`, median of three; corpus `yes 'añ€😀 wörd the quick brown fox' | head -c N`
(the cut tail makes the last scalar ill-formed on purpose). At 8 MiB the line is also checked
against the JS lane and an independent Python oracle.

Runtime floor (empty file): **2,152 KiB**.

| input | stream RSS | over floor | stream s | whole-file RSS | whole s | same line |
|---|---:|---:|---:|---:|---:|---|
| 8 MiB | 2,804 KiB | 652 KiB | 0.05 | 36,852 KiB | 0.06 | yes |
| 64 MiB | 2,616 KiB | 464 KiB | 0.37 | 280,240 KiB | 0.52 | yes |
| 256 MiB | 2,680 KiB | 528 KiB | 1.68 | 1,114,344 KiB | 1.99 | yes |

The curve is flat: 32× the input, RSS within ±100 KiB run-to-run noise (the floor itself moved
2,148–2,288 KiB across runs), against 4.2× input materialized (1.06 GiB at 256 MiB). The ~0.5 MiB
over the floor is the chunk: 64 KiB read buffer + 256 KiB of U32 cells + frames. With 4 KiB
chunks the 256 MiB scan peaks at **2,276 KiB** (2,276–2,344; indistinguishable from the floor)
at 2.3 s instead of 1.7 s. Streaming is also 15–30 % faster than whole-file here.

A file larger than RAM was not run: the box has 30 GiB and the point would cost a >30 GiB
corpus; the flat curve is the evidence offered, and nothing in the path scales with file size
(no chunk is referenced by the decoder state or the next chunk).

JS lane, for honesty: the same stream at 8 MiB peaks at 100 MiB / 1.5 s (whole-file: 2.5 GiB /
3.2 s), at 64 MiB 156 MiB / 11.3 s, empty file 46 MiB. Bounded far below whole-file, but **not
flat** — bun's GC heap grows with allocation volume; the C lane is the constant-memory claim.
The T2 criterion "decode within 10 % of `9e2d3076`" holds by construction (`io_text` is
unchanged; the additions are a ≤ 3-byte scan and a `len + 4` buffer) and was not separately timed.

## Verification (tip of this branch)

| suite | result |
|---|---|
| `tests/strings/run.sh` | **89 / 0** (85 + 4 `io_stream` rows), first run, no `deep` retry needed; check/interpret/JS/C byte-identical per specimen |
| `python3 tests/strings/runtime.py` | all sections ok, ASan/UBSan, zero live, 77 injected failures |
| `tests/run.sh` (f64) | 16 / 0 |
| `tests/codex/run.sh` | 161 / 0, 0 suite errors |
| `tests/regex/run.sh` | 49 / 0 |
| `bun gates/repo.ts` | 44 / 44 |

## ttok and bookkeeping

| file | before | after | cap | cap line |
|---|---:|---:|---:|---|
| `bend2/base.bend` | 42,318 | **42,814** (+496) | 43,000 | held — 186 left |
| `bend2/comp.ts` | 80,198 | **80,198** (0) | 81,000 | held |
| `bend2/effs/file_read_text_go.c` / `.js` | — | 831 / 434 | 4,000 | new files |
| `tests/strings/io_stream.bend` | — | under 16,000 | 16,000 | new |

Base's +496 is new public surface: `Utf8.Dec` (type, `new`, `eof`) and `File.read_text` (+ its
`.go` effect and `.pack` wrapper). Diff vs `130bc136`: 10 files, **+580 / −1** (ratio 0.002 — a
build lane; nothing existing was superseded, since `io_str`/`io_text` are reused, not forked).
Not touched: `bend2/bend.ts`, `bend2/main.ts`, `gates/**`, `tests/caps.sh`, other namespaces.

## Uncertainties

- **Consumer ergonomics.** A read loop needs continuation-passing helpers (`chunk`, `choose`)
  because matches only head def bodies, and an until-EOF loop is `@unsafe` or fuelled (the
  specimen uses fuel, the demo `@unsafe`). A `File.fold_text(file, max, state, step)` in base
  would hide all of it (~250 tokens — over the current base cap, so not built; candidate
  surface for the orchestrator to price).
- `demos/text_stream/` was used because `demos/text/` belongs to `lane-textdemos`; merge is
  path-disjoint. If `lane-adaptive` lands narrower payloads, the whole-file column shrinks
  (up to 4×) and should be re-measured; the stream column should not move.
- Short reads (pipes, ttys) are handled the same as file chunks; only regular files were run.
- The `Dec` handed to a failed call is gone with it (as designed); a retrying caller copies it
  first (`+dec`).
