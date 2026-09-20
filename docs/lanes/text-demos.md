# Text demos lane — report (fable, 2026-09-18)

Branch `lane-textdemos`, worktree `bend-work-demos`. Nothing pushed. `bend2/**`, `gates/**`,
`tests/**`, `tests/caps.sh` and the other `demos/*` untouched: the lane adds `demos/text/` (16
files, +816) and this report.

## Slices

| commit | content |
|---|---|
| `a73eb340` | `bendgrep.bend`, `topwords.bend`, `gen_logs.py`, `gen_corpus.py`, `_lib.sh`, `run_bendgrep.sh`, `run_topwords.sh` |
| `a2bb6ac7` | `slices.bend`, `gen_records.py`, `run_slices.sh` |
| `5626fd26` | `md2html.bend`, `md2html.py` (oracle), `gen_markdown.py`, `run_md2html.sh`, `lanes.sh` |
| `af727a32` | `README.md`; `run_md2html.sh` → `run_md_to_html.sh` (gates/repo.ts allows `[A-Za-z_]+\.sh` in demos, no digits) |
| this commit | this report |

## How to run

From the repo root; each generates its input on first use, builds the C binary if stale, runs it
under `/usr/bin/time -v`, prints wall + peak RSS, and checks the result against an outside tool.

    demos/text/run_md_to_html.sh     # README.md, then big-20.md;   MIB=20
    demos/text/run_topwords.sh       # linux.words, then prose-200; MIB=200
    demos/text/run_bendgrep.sh       # app-500.log;                 MIB=500 NEEDLE=ERROR
    demos/text/run_slices.sh         # records-256.txt;             MIB=256 N=1000000
    demos/text/lanes.sh              # three-lane self-test, ~1 min

`CORPUS=` (default `$HOME/videokit-corpus`) holds the generated inputs, `BIN=` (default
`/tmp/bend-text-demos`) the binaries and the rendered HTML. Neither is in the repo, so nothing
needs a `.gitignore` (and `gates/repo.ts` has no pattern that would allow one under `demos/`).
There is no argv in Bend IO, so the programs take `FILE`, `NEEDLE`, `N` from the environment.
The lane commands are those of `tests/strings/run.sh`: `bun bend2/main.ts x.bend`,
`-o x.js` + `bun x.js`, `-o x` + `./x --gpu off`.

## Measured (C lane, the one timed)

Ryzen 7 7700X, 8 cores / 16 threads, Linux 6.17, `--gpu off`. Other sessions kept the machine at
load average 14 to 21 throughout (8 to 10 at the very end), so every figure is a range over two
runs of the final code: the better one, and the final scripted run (`/tmp/text-demos-final.log`,
reproduced verbatim below). I could not get a quiet machine; quiet numbers should be lower, and
topwords, the only parallel one, should gain the most.

| Demo | Input | Wall | Program's clock (`IO.now`) | Peak RSS |
|---|---|---|---|---|
| md2html | README.md 9,549 B → 273 lines | 0.00 s | read 0–2 ms, render+print 0–1 ms | 2 MB |
| md2html | big-20.md 20 MiB → 504,499 lines | 0.76–1.33 s | read 49–90, render+print 696–1192 ms | 472 MB |
| topwords | linux.words 4.8 MB: 480,374 words, 461,717 unique | 4.85–6.11 s | count+rank 4825–6080 ms | 136 MB |
| topwords | prose-200.txt 200 MiB: 20,211,498 words, 70,852 unique | 16.28–20.85 s | read 683–843, count+rank 15448–19822 ms | 2831 MB |
| bendgrep | app-500.log 500 MiB: 9,010,000 lines, 180,512 hits | 3.36–4.36 s | read 1281–1603, search 1961–2592 ms | 2503 MB |
| slices | records-256.txt 256 MiB, 16,777,216 records | 0.89–1.13 s | load 620–782, tour 0, 1,000,000 slices 212–274 ms | 1282 MB |

Outside tools, same machine, same files: `md2html.py` 1.12 s / 140 MB; `collections.Counter`
9.35 s / 1.66 GB; GNU `grep -c` 0.1 s. Honest reading for the video: md2html beats the Python
oracle; slices is the clean win (about 0.2–0.27 µs per deep slice+parse, flat in the offset);
bendgrep is 30 to 40x slower than grep and topwords about 2x slower than Python. Do not claim
otherwise on camera. RSS is about 4 B per character plus the read buffer (strings are packed U32).

Final scripted run, stdout+stderr as recorded:

    $ FILE=.../README.md (12K) md2html > /tmp/bend-text-demos/README.html
    read 2 ms, render+print 1 ms
      => wall 0:00.00, peak RSS 2 MB
      273 lines of HTML; first heading: <h2>Bend runs FAST</h2>
      check: byte-identical to the Python oracle
    $ FILE=.../big-20.md (21M) md2html > /tmp/bend-text-demos/big-20.html
    read 90 ms, render+print 1192 ms
      => wall 0:01.33, peak RSS 472 MB
      504499 lines of HTML; first heading: <h1>Chapter 1: tree affine string map</h1>
      check: byte-identical to the Python oracle
    $ FILE=/usr/share/dict/linux.words (4.8M) topwords
    total words:  480374
    unique words: 461717          (top-20 table elided here: every word occurs once or twice)
    read 24 ms, count+rank 6080 ms
      => wall 0:06.11, peak RSS 136 MB
    $ FILE=.../prose-200.txt (201M) topwords
    total words:  20211498
    unique words: 70852           (top-20 elided; rank 1 is "pidgeon" 1460286, = Counter)
    read 843 ms, count+rank 19822 ms
      => wall 0:20.85, peak RSS 2831 MB
    $ FILE=.../app-500.log (501M) NEEDLE=ERROR bendgrep
    180512 matching lines of 9010000      (first 5 hits with line numbers elided)
    read 1603 ms, search 2592 ms
      => wall 0:04.36, peak RSS 2503 MB
      check: grep -c says 180512
    $ FILE=.../records-256.txt (256M) N=1000000 slices
    length                    268435456
    records                   16777216
    get 14                    0
    get 134217742             8
    get_end 2                 5
    take 15                   000000000000000
    record 8388608            000000008388608
    record 16777215           000000016777215
    drop to last | take 15    000000016777215
    take_end 16 | trim        000000016777215
    drop_end all but 15       000000000000000
    1000000 scattered records all correct, checksum 463900448
    load 782 ms | tour 0 ms | 1000000 deep slices 274 ms
      => wall 0:01.13, peak RSS 1282 MB

## Lanes

`demos/text/lanes.sh`, run at the tip: 9 / 9 ok. Each `[cli = js = c]` line is a byte compare of
stdout across `bun bend2/main.ts`, the emitted JS under bun, and the emitted C with `--gpu off`.

    ok   md2html [cli = js = c] FILE=README.md
    ok   md2html README.md = md2html.py
    ok   md2html [cli = js = c] FILE=big.md            (1 MiB)
    ok   md2html big.md = md2html.py
    ok   topwords [cli = js = c] FILE=prose.txt        (300 KB)
    ok   topwords = collections.Counter
    ok   bendgrep [cli = js = c] FILE=app.log NEEDLE=ERROR   (1 MiB)
    ok   bendgrep counts = grep -c
    ok   slices [cli = js = c] FILE=records.txt N=200  (1 MiB)

Timing lines go to stderr, so stdout is pure and comparable. An IO `main` under the CLI runs the
JS emitter's path, so "interpret" and "js" are the same engine here, as in `tests/strings/io_*`.
md2html was also diffed against the oracle on `guide/GUIDE.md`, `tests/strings/README.md` and
`docs/omen/lanes/regex.md`: identical. The full-size inputs were run in the C lane only.

## What I could not do, and why

- **Full-size inputs in the JS lane.** JS slices walk code points, so a deep slice is O(offset)
  (10–17 ms each at 1 MiB; `slices` at N=1,000,000 does not finish), and ranking recurses on the
  machine stack (overflows near 30k unique words). Hence `lanes.sh` sizes and `N=200`.
- **`words` over the whole 200 MiB string.** Refcounts are 24-bit (`ERR_RFCS` in `comp.ts`):
  more than 16.7M live views of one payload is `bend: runtime fail-stop`. topwords takes
  `String.lines` and `String.words` per line, so views die as they are counted. bendgrep's 9M
  lines fit; a log past 16.7M lines would not.
- **A fast topwords.** `Map` is a crit-bit trie in Bend, about 2.3 µs per get+set, 94% of the
  time. Sequential: 115 s on 300 MiB. Fork-join at depth 9 (512 leaves, `x y = fork(..) fork(..)`,
  maps merged upward): 36.7 s on 300 MiB, 16–21 s on 200 MiB. The cost shows on the dictionary:
  almost every word unique, so merging dominates and the forked version takes 4.85 s where the
  sequential one took 2.17 s. I kept one program for both inputs. Thread scaling was weak, which
  I attribute to the loaded machine but did not isolate.
- **The 200–500 MB corpus** is at the bottom of the asked range (200 MiB, 2.8 GB RSS): 300 MiB
  works (36.7 s, 4.1 GB) but is slow on camera and heavy beside other sessions. `MIB=300` runs it.
- **Markdown beyond the asked subset.** No ordered lists, nested lists, block quotes, tables, or
  raw HTML: the spec says escape `< > &`, so the README's own `<img>` tags show as text. Inline
  precedence is code, bold, links, italic; an unclosed marker stays literal. `md2html.py` encodes
  exactly the same rules, so "byte-identical" means same spec, not CommonMark conformance.
- **Large Nat literals** (`1000000n`) overflow the checker's stack; `slices` reads `N` from the
  environment and uses `U32.to_nat`.

## Batteries at the tip (`af727a32`, run once, serially)

| battery | result |
|---|---|
| `bun gates/repo.ts` | PASS 45 / 45 (44 before this lane) |
| `bash tests/run.sh --strings` | PASS 85, FAIL 0 (no deep retry was needed this run) |
| `bash tests/run.sh` | PASS 16, FAIL 0 |
| `bash tests/codex/run.sh` | 161 PASS, 0 FAIL, 0 suite errors |
| `bash tests/caps.sh` | all ok; `bend2/base.bend` 42,318 ≤ 43,000; `bend2/comp.ts` 80,198 ≤ 81,000 (both unchanged) |

## Left behind

`$HOME/videokit-corpus` holds this lane's four inputs, 977 MB: `app-500.log`, `prose-200.txt`,
`records-256.txt`, `big-20.md`, kept so the recording does not wait on generation; delete them
after the shoot. The directory totals 1.9 GB because another session put `knob-*.txt`,
`*.oracle*` and `gen_corpus_sh.patch` there; they are not mine and I left them alone.
`/tmp/bend-text-demos` has the binaries and HTML. Scratch files from development are removed.
