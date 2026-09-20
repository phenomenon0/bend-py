# Bend on Apple silicon — lane report (fable, 2026-09-20)

Branch `lane-apple`, worktree `bend-work-apple`, off `omen` @ `ac994157`. Bend built and measured
on an Apple M3 Ultra driven over ssh from the Linux box. Nothing pushed. Files touched: this
report and `docs/omen/apple/{parse_scale.sh,decode_len.bend,decode_bench.sh,measure_watts.sh,bench_pins.sh}`.
`bend2/**`, `gates/**`, `tests/**`, `demos/**` untouched — every Mac-side runner is a new file
under `docs/omen/apple/`, and the repo's own scripts ran on the Mac unmodified.

**Watts: no CPU-package figure, on either host.** Both boxes refuse those counters without a
one-time sudo grant, so **there is not one Apple-silicon watt in this report**, and every place
one would go says so. The one rail that needs no root — the discrete NVIDIA board on the Linux
box — *was* sampled, and that measurement is real and is in §5-6; it is the proof that
`docs/omen/apple/measure_watts.sh` works end to end, not a substitute for the missing rail.
The script exits 77 and says why rather than print a number it did not take. The two grant
one-liners are in §6.

## The boxes

| | Mac (this lane) | Linux (the comparison) |
|---|---|---|
| chip | Apple M3 Ultra, **20 P + 8 E = 28**, 60-core GPU | Ryzen 7 7700X, 8 C / 16 T, RTX 3090 |
| memory | 96 GiB unified | 30 GiB + 24 GB VRAM |
| os | macOS 27.0 (26A428), Darwin 27.0.0 arm64 | Fedora 43, Linux 6.17 x86_64 |
| toolchain | Apple clang 21.0.0, bun 1.4.2, Metal 4 | clang 21.1.7, bun, CUDA |
| load | **2.9 – 6.6 throughout — the Mac carries a normal user's session** | 2.1 – 5.2 |

Every Mac number below is therefore pessimistic; none was taken on an idle machine, and the load
average at the time is printed in the box line of each run's own log.

## 0-1 — toolchain and sync

`bun` installed user-level from `bun.sh/install` (no root, no Homebrew): `~/.bun/bin/bun`, 1.4.2
arm64. `clang` is Xcode's, already present. Repo rsynced to `~/bend-apple/` (`--exclude .git
--exclude node_modules`). **No `bun install` was needed and none was run** — `~/bend-apple/` has no
`node_modules` at all and `bun bend2/main.ts` checks, interprets, emits JS and emits C from a bare
tree. A fresh Mac is two commands from a working Bend: install bun, copy the repo.

**What the Mac tree actually is, exactly.** `~/bend-apple/` is this branch — the four files that
are the language and the compiler are byte-identical to the worktree this report is committed in
(`md5` on both: `comp.ts 77d0cbe7…`, `bend.ts 25519c59…`, `base.bend 635a1b2e…`,
`main.ts f86bfebb…`), and `demos/`, `tests/`, `bench/` and `gates/` list the same. **Two things
are not from this branch and both matter:**

- **`demos/parallel/parse_corpus.bend`, `_lib.sh` and `gen_manifest.py` do not exist on
  `lane-apple`.** They are overlaid from `lane-parcorpora` @ `2f03db02`, byte-identical to that
  branch's copies. §3's scaling table is therefore *that* demo, compiled by *this* branch's
  compiler. Said plainly because a reader who checks out `lane-apple` will not find the program
  the biggest table in this report measures.
- **`~/bend-apple/power/` is not mine.** Seven `.bend` files another session wrote there during
  this one. Nothing in this lane read, ran, built or edited them; they are named because they are
  in the directory, and because they are part of the load these tables were measured under.

Three shims live in `~/bend-apple-bin/` so the repo's own scripts run unedited — **they are not
in the repo and not a proposed change**, they are a Mac that lacks three tools the runners assume:

| shim | why | body |
|---|---|---|
| `timeout` | `tests/run.sh` calls `timeout 300`; macOS has no such binary | perl fork + `alarm`, exits 124 on the timeout, like GNU |
| `nproc` | several runners call it | `sysctl -n hw.ncpu` |
| `rg` | `tests/strings/run.sh:62` gates the GPU lane on ripgrep, and without it that lane is skipped **silently** (F5) | `exec grep -qE`, refusing any flag but `-q` |

The three corpora the parse runner needs were rsynced whole, with their Linux manifests:

| corpus | root on the Mac | files | bytes |
|---|---|---:|---:|
| numpy | `~/bend-corpora/libscout/x/numpy-2.4.6/numpy` | 619 | 9,936,605 |
| pandas | `~/bend-corpora/libscout/x/pandas-3.0.6/pandas` | 300 | 8,185,396 |
| stdlib | `~/bend-corpora/stdlib` — the pinned CPython 3.11.15 stdlib, shipped as files | 290 | 6,349,245 |

The manifests are the Linux ones with the path prefix rewritten: `gen_manifest.py` walks a
*pinned* CPython to decide eligibility and the Mac has no such interpreter, so re-deriving the
list there would have produced a different corpus and made the two machines incomparable. Taking
the manifest as given is what makes the cross-machine hash comparison below mean anything.

## 2 — build, smoke, and what macOS costs the tree

All four lanes work on arm64/macOS. Check, interpret, JS (`-o x.js`, run by bun) and C
(`-o x`, built by Xcode clang) all ran; the emitted C builds with the same `-O3` line the Linux
side uses, no flag changes, no `#ifdef` added.

**The suite battery, both hosts, at this commit.** Read the two `FAIL` columns carefully: in every
one of these runners `pass` is incremented *only* inside the per-test lane loop, while the
auxiliary Python checks that follow it can only ever increment `fail`. An identical `PASS` on both
hosts therefore means **the same Bend tests passed on both machines**; a Mac-only `FAIL` is an
auxiliary check, not a Bend test.

| suite | command | Linux x86_64 | Mac arm64 | the difference |
|---|---|---|---|---|
| f64 | `bash tests/run.sh` | 19 / 0 | **17 / 1** | `mc_pi` only: its `[c]` lane fails and its `[gpu]` lane never runs (F3) |
| strings | `bash tests/run.sh --strings` | 102 / 0 | **102 / 0** | none — but 101 / 0 before the `rg` shim (F5) |
| regex | `bash tests/regex/run.sh` | 49 / 0 | **49 / 0** | none |
| codex | `bash tests/codex/run.sh` | 161 / 0 | **cannot run** | `mapfile`, which bash 3.2.57 does not have (F5) |
| parser | `bash tests/parser/run.sh` | 108 / 0 | **108 / 7** | 7 auxiliary checks, all of them the CPython oracle (F2) |
| lint | `bash tests/lint/run.sh` | 76 / 0 | **76 / 1** | 1 auxiliary check, `tests/lint/semantics.py` |
| translator | `bash tests/translator/run.sh` | 32 / 0 | **32 / 5** | 5 auxiliary checks, `judge.py --demo` x4 plus `source_stems` |

**367 Bend tests pass identically on both machines** (102 + 49 + 108 + 76 + 32); `f64` is 19 on
Linux and 17 on the Mac for the one reason F3 gives; `codex`'s 161 are untested on arm64 for a
shell-version reason with nothing to do with Bend. Every Mac-only `FAIL` in the table is a Python
helper that needs an interpreter or a tool the Mac does not have — counted here rather than
quietly dropped, because the runner counts them and so does this report.

### Findings (honest, in the order they cost time)

**F1 — three GNU-isms in the runners.** `demos/parallel/_lib.sh` times with `date +%s%N`, sizes the
box with `nproc`, and `tests/run.sh` wraps each lane in `timeout 300`. BSD `date` has no `%N` (it
prints the literal `N`, so every duration comes out as a garbage integer — it fails *quietly*,
which is the dangerous part), and neither `nproc` nor `timeout` exists. Fixed **in my worktree
only**: `docs/omen/apple/parse_scale.sh` is that table with `perl -MTime::HiRes=time` for the
clock and `sysctl -n hw.ncpu` for the core count. `tests/run.sh` is not mine to edit, so the two
shims above stand in.

**F2 — `gen_manifest.py` wants a pinned CPython.** It decides eligibility with
`tokenize.detect_encoding` and the parser oracle's intake, from a specific interpreter. The Mac
has none, so `parse_scale.sh` takes `$OUT/corpora.txt` as given instead of generating it. This is
a deliberate deviation and it is what makes the two machines comparable at all (§3).

**F3 — `tests/f64/mc_pi.bend`: MSL has no fp64, and the failure takes the working CPU binary
with it.** This is the one FAIL in the whole Mac battery (§11), and it is worth being exact about,
because the lane label is misleading. `tests/run.sh` reports it as `FAIL mc_pi [c] (build)` — a C
failure. It is not. What happens, verified step by step:

```
$ bun bend2/main.ts tests/f64/mc_pi.bend -o /tmp/mc_pi
program_source:2225:17: error: use of undeclared identifier 'f64_rewrap';
                               did you mean 'f32_rewrap'?
program_source:2228:31: error: use of undeclared identifier 'f64_unbox';
                               did you mean 'f32_unbox'?
Error: mc_pi failed to build /tmp/mc_pi

$ /tmp/mc_pi --gpu off              # …but the binary exists, and is correct
3.141498565673828
823525

$ /tmp/mc_pi --gpu 4GB              # the same errors, no result, no fallback
program_source:2225:17: error: use of undeclared identifier 'f64_rewrap' …
```

`program_source` is the Metal compiler, not clang: **Metal Shading Language has no fp64**, which
`bend2/comp.ts` already accounts for at its `#ifdef __METAL_VERSION__` block by emitting only the
`f32_*` family for the device. `mc_pi.bend` is the one program in the tree that combines `F64`
with a `!` call, so it is the one program whose device half cannot exist on Apple silicon. The
same file builds and runs its GPU lane on the Linux box, because CUDA has fp64.

Two things follow, and only the first is about Apple silicon:

1. **The fp64 gap is real and unfixable by a flag.** Nothing to do but know it.
2. **The build command fails whole when only the device half failed** — and prints raw MSL
   diagnostics to do it, so the CPU binary sitting on disk and printing the right answer looks
   like a C build failure to every runner in the tree. A one-line diagnostic ("this program uses
   F64 in a `!` call; Metal has no fp64") plus a decision about whether `-o` should succeed with
   a CPU-only binary is a `comp.ts` change, in a file this lane does not touch. **Recorded, not
   made.**

**F4 — a Bend binary costs 14-17 ms to start on macOS and ~0 on Linux, and half of it is one
`mmap`.** A Bend hello-world C binary, 11 timed runs after 2 warm, median, at the thread count
shown:

| | hello, 1 thread | hello, all threads | `/usr/bin/true` | **Bend's own startup** | load |
|---|---:|---:|---:|---:|---|
| Mac, M3 Ultra | 22.98 ms | 22.73 ms (28) | 8.72 ms | **≈ 14.3 ms** | 4.88 |
| Ryzen 7700X | 2.98 ms | 3.07 ms (16) | 2.96 ms | **≈ 0.02 ms** | 3.67 |

The same three medians were taken twice more during the session, at load 3.81 and 4.20:
25.98 / 25.72 (28) / 8.91 ms — **≈ 17.1 ms** — and 24.63 / 25.51 (28) / 8.79 ms — **≈ 15.8 ms**.
Three independent measurements, **14-17 ms**; the table below explains most of that span's floor
and not its spread.

Subtracting `/usr/bin/true` removes the fork/exec the measurement harness pays on each host, which
is what makes the last column comparable across two very differently loaded machines. It does not
move with the thread count, so it is not thread setup. A 20-line probe finds where most of it
goes:

| reservation | Darwin `mmap` | Linux `mmap` |
|---|---:|---:|
| `1<<33` — 8 GiB | 0.006 – 0.011 ms | 0.003 ms |
| `1<<36` — 64 GiB | 0.046 – 0.070 ms | 0.001 ms |
| `1<<40` — 1 TiB | 0.641 – 1.304 ms | 0.001 ms |
| **`1<<43` — 8 TiB, what `corpus_setup` reserves** | **6.270 – 7.916 ms** | 0.001 ms |
| `1<<46` — 64 TiB | 53.659 – 58.287 ms | 0.001 ms |

(min–max of 3 runs on the Mac, 5 on the Ryzen; `PROT_READ|PROT_WRITE`,
`MAP_PRIVATE|MAP_ANON|MAP_NORESERVE`. First touch is 0.002 – 0.024 ms in every cell of both hosts,
so the whole cost is the reservation itself.)

`corpus_setup` reserves the whole `Loc` space — `1ull << 43`, 8 TiB, `MAP_NORESERVE` — for the CPU
path. **Linux charges O(1) for that reservation regardless of size; Darwin charges O(size)**, so a
line that is free on Linux costs 6.3-7.9 ms on the Mac. Stated exactly: that is **40-55 %**
of the 14-17 ms, and this lane does not claim the rest — dyld, the rest of `main`, and the
`/usr/bin/true` subtraction's own error bar are all in there, unattributed. What the probe does
settle is the *shape*: the cost is a function of the reservation's size and of nothing else, so it
is a **fixed toll, not a rate**. It does not scale with threads, it does not scale with the work,
and it vanishes into the noise on anything that runs longer than a second. It dominates every
short benchmark, which is why every table below either runs long enough not to care or reports
the floor beside the number.

**F5 — two suites need tools macOS does not ship, and one of them fails *silently*.**

`tests/strings/run.sh:62` decides whether a test gets a GPU lane with ripgrep:

```bash
if rg -q '[A-Za-z0-9_]!\(' "$t"; then
```

macOS has no `rg`. The `if` simply takes the false branch, so the GPU lane is **skipped without a
word** and the suite reports `Strings PASS: 101, FAIL: 0` — a green run that silently tested one
thing less. A four-line `sh` shim on `$PATH` that forwards `rg -q` to `grep -qE` (and refuses any
other flag loudly) restores the 102nd: `gpu`, the one test in that suite with a `!` call.

`tests/codex/run.sh:59-60` uses `mapfile`, a bash-4 builtin. The Mac's `/bin/bash` is **3.2.57**
(Apple has shipped that 2007 release for licence reasons ever since; `/bin/zsh` is the default
shell). There is no shim for a missing builtin, so the whole 161-test codex suite is untested on
arm64. That is a shell-version gap, not a Bend one, and it is reported as an untested suite rather
than folded into a pass count.

Both are **shims outside the tree**, in `~/bend-apple-bin/`, on the Mac's `$PATH` for the run.
Neither `tests/strings/run.sh` nor `tests/codex/run.sh` was edited; `tests/**` is not this lane's.

**F6 — the tree's two pin generators disagree on the thread count, by 2x.** Not a macOS finding,
but this lane is what surfaced it. `gates/perf.ts`'s `THREADS` rounds the core count **up** to a
power of two:

```js
const THREADS = "nt=1; while [ $nt -lt $(getconf _NPROCESSORS_ONLN) ] &&"
  + " [ $nt -lt 256 ]; do nt=$((nt*2)); done;";          // 10 cores -> 16, 28 -> 32
```

`bend2/docs/gen_pins.ts`'s `runtime_cell` rounds the same number **down**:

```ts
let nt = 1;
while (nt * 2 <= os.cpus().length && nt < 256) { nt *= 2; }   // 10 cores -> 8, 28 -> 16
```

So `bench/runtime/_pin_/apple_m4.txt` (written by `gates/perf.ts`) and `apple_m4_max.txt` (written
by `gen_pins.ts`) hold `PAR-CPU` columns measured at thread counts that differ by a factor of two
on the same core count, and neither file records which. On this 28-core machine the two rules give
exactly **32 and 16** — the two PAR columns in §7 — and the measured gap between them is a median
of **1.34x**. Nothing was edited: `gates/**` is off limits and `gen_pins.ts` is not this lane's,
so this is filed as an observation with both measurements attached.

## 3 — the benchmarks

### parse_corpus: the 28-core scaling table

`demos/parallel/parse_corpus.bend` — **from `lane-parcorpora` @ `2f03db02`, not from this branch**
(§0-1) — one binary that reads a manifest, lexes and parses every file
with `demos/python`'s own lexer and parser, and prints `status hash path` per file plus a corpus
hash. `PAR_MODE=seq` runs the leaves one after another; `--threads N` is the only knob. Driven by
`docs/omen/apple/parse_scale.sh`: one warm run then **5 timed runs, median**, and **every run —
warm and timed — is `cmp`'d against the sequential run's stdout inside the loop**, so a single
differing byte aborts the script.

```bash
ROOT=~/bend-apple THREADS="1 2 4 8 16 20 24 28" bash docs/omen/apple/parse_scale.sh
```

Load 3.11 → 3.32. 54 runs per corpus, every one byte-identical to that corpus's sequential run.

| corpus | mode | threads | wall s | parse s | speedup | files/s | MB/s |
|---|---|---:|---:|---:|---:|---:|---:|
| **numpy** 619 files, 9.5 MB | seq | 1 | 6.40 | 6.33 | 1.00× | 96.7 | 1.5 |
| | par | 1 | 6.38 | 6.30 | 1.00× | 97.1 | 1.5 |
| | par | 2 | 3.57 | 3.50 | 1.79× | 173.2 | 2.7 |
| | par | 4 | 2.21 | 2.14 | 2.90× | 280.2 | 4.3 |
| | par | 8 | 1.39 | 1.31 | 4.62× | 446.9 | 6.8 |
| | par | 16 | 0.82 | 0.75 | 7.84× | 757.6 | 11.6 |
| | par | 20 | 0.70 | 0.63 | 9.20× | 889.4 | 13.6 |
| | par | 24 | 0.65 | 0.58 | 9.81× | 947.9 | 14.5 |
| | par | **28** | **0.61** | 0.53 | **10.57×** | **1021.5** | 15.6 |
| **pandas** 300 files, 7.8 MB | seq | 1 | 4.30 | 4.24 | 1.00× | 69.8 | 1.8 |
| | par | 1 | 4.25 | 4.19 | 1.01× | 70.6 | 1.8 |
| | par | 2 | 2.23 | 2.18 | 1.92× | 134.3 | 3.5 |
| | par | 4 | 1.31 | 1.25 | 3.27× | 228.5 | 5.9 |
| | par | 8 | 0.82 | 0.76 | 5.25× | 366.7 | 9.5 |
| | par | 16 | 0.77 | 0.71 | 5.59× | 390.6 | 10.2 |
| | par | **20** | **0.45** | 0.40 | **9.48×** | **662.3** | 17.2 |
| | par | 24 | 0.46 | 0.41 | 9.28× | 647.9 | 16.9 |
| | par | 28 | 0.46 | 0.41 | 9.28× | 647.9 | 16.9 |
| **stdlib** 290 files, 6.1 MB | seq | 1 | 3.94 | 3.89 | 1.00× | 73.5 | 1.5 |
| | par | 1 | 3.96 | 3.90 | 1.00× | 73.3 | 1.5 |
| | par | 2 | 2.07 | 2.01 | 1.91× | 140.3 | 2.9 |
| | par | 4 | 1.19 | 1.14 | 3.32× | 244.1 | 5.1 |
| | par | 8 | 0.67 | 0.62 | 5.89× | 432.8 | 9.0 |
| | par | 16 | 0.49 | 0.44 | 8.08× | 594.3 | 12.4 |
| | par | **20** | **0.36** | 0.31 | **10.95×** | **805.6** | 16.8 |
| | par | 24 | 0.36 | 0.31 | 10.80× | 794.5 | 16.6 |
| | par | 28 | 0.37 | 0.32 | 10.63× | 781.7 | 16.3 |

`par --threads 1` lands on the sequential time in all three (1.00×, 1.01×, 1.00×): the fork/join
tree itself costs nothing measurable, the speedup is the threads.

**Where each corpus stops.** numpy is the only one still gaining at 28 (its 619 files are the most
leaves and the widest file-size spread, so the tail is the longest to hide). pandas and stdlib
peak at 20 — the P-core count — and go flat or slightly worse after, which is the 8 E-cores
joining a tree whose leaves are already smaller than the E-core's share of the work. pandas'
`--threads 16` row (0.77 s, out of line with 8 → 0.82 and 20 → 0.45) is the worst case of that:
16 is neither a clean half of 20 P-cores nor the whole 28.

### The same bytes on two architectures

The per-file `status hash` digest of the 290-file stdlib corpus, x86_64/Linux vs arm64/macOS:

```
b48c40b7cddee51b73db76f3e4075c866183b9f0a5b4fa79c067b47ce922fc18   (both)
```

Identical. The trailing `corpus <hash>` line differs (`279149589` Linux, `2771585941` Mac) for one
reason only: it hashes the absolute paths, which differ per machine. Every parse result — 290
files, every token, every AST, every FNV hash of every JSON serialization — is the same on both.
Verdicts `619 ok`, `300 ok`, `290 ok`: every file in all three corpora parses on both machines.

### Against the Ryzen

Same three corpora, same binary source, `docs/omen/lanes/parcorpora.md`'s numbers (load 2.9 → 5.2):

| corpus | Ryzen 7700X seq | M3 Ultra seq | per-core | Ryzen best (16 T) | M3 Ultra best (28 T) | machine |
|---|---:|---:|---:|---:|---:|---:|
| numpy | 8.31 s | 6.40 s | **1.30×** | 1.56 s | **0.61 s** | **2.56×** |
| pandas | 5.56 s | 4.30 s | **1.29×** | 1.04 s | **0.45 s** | **2.31×** |
| stdlib | 5.04 s | 3.94 s | **1.28×** | 0.81 s | **0.36 s** | **2.25×** |

An M3 Ultra P-core is ~1.3× a Zen 4 core on this work, and the machine is ~2.3-2.6× the machine —
the rest is 28 threads against 16. Both figures include the Mac's 14-17 ms floor (F4), which is under
5 % of even the fastest row here.

### Decode + length, 8 MiB and 64 MiB, both lanes

`docs/omen/apple/decode_len.bend` opens a file, reads it whole, closes it and prints
`String.length`, with `IO.now()` either side of the read and either side of the length.
`decode_bench.sh` rebuilds the corpora from **`tests/strings/bench.sh`'s own two unit strings**
(`"  alpha beta\n gamma\t\n"` and `"  café λ😀\n 漢字\t\n"`), repeated to exactly N bytes by that
script's own rule — tail cut on a code-point boundary and space-padded — and **asserts that
script's own code-point count on every single run**. A wrong count aborts before any timing.

| corpus | bytes | code points | lane | wall s | read s | length s | MB/s (wall) | Mcp/s (wall) |
|---|---:|---:|---|---:|---:|---:|---:|---:|
| ascii | 8,388,608 | 8,388,608 | C | 0.040 | 0.013 | **0.000** | 200.0 | 209.7 |
| | | | JS | 0.071 | 0.004 | 0.049 | 112.7 | 118.2 |
| unicode | 8,388,608 | 5,242,882 | C | 0.043 | 0.014 | **0.000** | 186.0 | 121.9 |
| | | | JS | 0.078 | 0.008 | 0.052 | 102.6 | 67.2 |
| ascii | 67,108,864 | 67,108,864 | C | 0.129 | 0.099 | **0.000** | 496.1 | 520.2 |
| | | | JS | 0.412 | 0.016 | 0.376 | 155.3 | 162.9 |
| unicode | 67,108,864 | 41,943,041 | C | 0.139 | 0.107 | **0.000** | 460.4 | 301.8 |
| | | | JS | 0.472 | 0.052 | 0.398 | 135.6 | 88.9 |

Medians of 7 (8 MiB) and 5 (64 MiB), one warm run each, every run printing the oracle count.

- **`String.length` is free on the C lane and is the whole cost on JS.** 0 ms against 376-398 ms
  at 64 MiB: the C string already carries its code-point count from the decode, and the JS lane
  walks it. That is the single largest lane difference this lane measured, and it is a property of
  the two runtimes, not of the Mac.
- The C lane's real decode rate, taken from the binary's own `read` phase so the 23-26 ms process
  floor (F4) is excluded: **646 MiB/s and 678 Mcp/s on ASCII, 598 MiB/s and 392 Mcp/s on UTF-8**
  at 64 MiB. The 8 MiB rows are mostly floor — wall 40 ms of which 13 ms is the read — which is
  why the 64 MiB pass was added.

### Regex scan, 1 MiB, against the Ryzen at the same commit

`tests/regex/bench.py --case scan --runs 7` ported to the Mac **unmodified** — it shells out to
`bun` and `cc` and needs nothing GNU. Patterns are that file's own: p0 `Fable@Bend`,
p1 `[0-9]{4}-[0-9]{2}-[0-9]{2}`, p2 `<(\w+)@(\w+)\.(com|net|org)>` flag `i`, p3 `q.*X.z$` flag `m`.
Both hosts re-run today at this commit; every row on both printed the same span.

| row | C Ryzen | C M3 Ultra | C net of base | | JS Ryzen | JS M3 Ultra |
|---|---:|---:|---:|---:|---:|---:|
| base (build + `String.length`) | 3.5 ms | 19.6 ms | — | | 49.4 ms | **20.5 ms** |
| p0 | 14.0 ms | 31.1 ms | 10.5 → 11.5 ms | **1.10×** | 59.5 ms | **50.2 ms** |
| p1 | 16.9 ms | 32.8 ms | 13.4 → 13.2 ms | **0.99×** | 96.7 ms | **70.6 ms** |
| p2 | 15.8 ms | 29.7 ms | 12.3 → 10.1 ms | **0.82×** | 62.9 ms | **53.9 ms** |
| p3 | 24.3 ms | 42.5 ms | 20.8 → 22.9 ms | **1.10×** | 200.1 ms | **142.8 ms** |
| reference VM, p2 @ 1 MiB (1 run) | 0.435 s | 0.507 s | | | — | — |

**Raw, the Mac looks about 2× worse on C. Net of its own base row it is a dead heat** — 0.82× to
1.10×, and on p2 the M3 Ultra is the faster of the two. The entire raw gap is F4's startup toll,
which every one of these 30-40 ms processes pays once. **On JS the Mac wins outright on every
row**, base included (20.5 ms against 49.4 ms): bun starts faster on arm64.

**One stale pin noticed in passing.** `docs/omen/lanes/regex-r56.md` records the reference VM at
p2 / 1 MiB as **40.0 s** on this Ryzen and calls the VM quadratic in n. Today it is **0.435 s on
the Ryzen, 0.507 s on the Mac** — ~92× on the same machine — and the per-code-point cost now
*falls* from 64 KiB to 1 MiB on both hosts (426 → 415 ns/cp Ryzen, 706 → 484 Mac) instead of
exploding. **A tree change, not an Apple finding** (it reproduces on Linux), but r56's headline
"≈ 2,500× native vs reference" is now ≈ 27× and should be re-pinned.

## 4 — P-cores and E-cores, without touching a line of the core

Process-level only: the same binary, the same corpus (stdlib, 290 files), the same
`parse_scale.sh` table, run three times under three scheduler classes via the `WRAP` hook.

```bash
WRAP="" ... ; WRAP="/usr/sbin/taskpolicy -c utility" ... ; WRAP="/usr/sbin/taskpolicy -c background" ...
```

### What `taskpolicy -c` actually does — and does not

- It sets a **QoS clamp** on the task. A clamp is a ceiling, and **it only clamps downward**: this
  `taskpolicy` accepts `utility`, `background` and `maintenance` and **rejects `user-interactive`**
  outright — `taskpolicy: Could not parse 'user-interactive' as a QoS clamp`. There is therefore
  no "more P than default" setting to ask for, and the P-leaning row below **is** the default row.
- It is a **hint to the scheduler, not an affinity mask.** It does not pin anything to a cluster.
  Darwin is free to run background-QoS threads on a P-core that is otherwise idle, and
  utility-QoS threads on E-cores. It also carries clock and I/O-priority effects that are not
  placement at all.
- **Placement here is inferred, not observed.** `ps -o %cpu` reports total CPU and cannot
  attribute a cluster; the only tool that reports per-cluster residency is
  `powermetrics --samplers cpu_power`, which needs root this lane does not have (§6). Read the
  table as *what each QoS class delivers*, which is measured, and the cluster attribution as an
  inference from the shape of the curve, which is argued below.

### The table (medians of 5, 20 runs per block, every run byte-identical)

| class | threads | wall s | parse s | speedup vs its own seq | files/s | load at run |
|---|---:|---:|---:|---:|---:|---|
| **default** | 1 (seq) | 3.92 | 3.87 | 1.00× | 74.0 | 3.06 |
| | 8 | 0.67 | 0.62 | 5.85× | 432.8 | |
| | 20 | **0.36** | 0.31 | **10.89×** | **805.6** | |
| | 28 | 0.37 | 0.32 | 10.62× | 785.9 | |
| **`-c utility`** | 1 (seq) | 3.95 | 3.90 | 1.00× | 73.4 | 3.20 |
| | 8 | 0.67 | 0.62 | 5.91× | 433.5 | |
| | 20 | **0.36** | 0.31 | **10.98×** | **805.6** | |
| | 28 | 0.37 | 0.32 | 10.57× | 775.4 | |
| **`-c background`** | 1 (seq) | 20.25 | 20.08 | 1.00× | 14.3 | 5.27 |
| | 8 | **3.32** | 3.15 | 6.09× | 87.2 | |
| | 20 | **3.12** | 2.94 | 6.49× | 92.9 | |
| | 28 | 3.24 | 3.08 | 6.24× | 89.4 | |

### What the three rows say

**`utility` is indistinguishable from default** — 0.67 / 0.36 / 0.37 against 0.67 / 0.36 / 0.37,
inside the noise at every point. On this machine a utility clamp buys the scheduler nothing it
was not already doing, so there is no "E-leaning" measurement to be had from it.

**`background` is a different machine.** Two things fall out of it, and the second is the
interesting one:

1. **Per-core ratio: 5.2×.** Single-threaded, default 3.92 s vs background 20.25 s. That is one
   P-core at the default QoS against one core at background QoS — **not** a clean
   microarchitectural P:E ratio, because the background clamp lowers the clock and the scheduling
   priority as well as leaning on the E-cluster. Take 5.2× as the *end-to-end cost of asking for
   the cheapest class*, which is what a user actually controls.
2. **The curve saturates at exactly 8.** Background goes 3.32 s at 8 threads → 3.12 s at 20 →
   3.24 s at 28. Twelve more threads buy 6 %, and the next eight buy nothing at all. The default
   curve is still improving from 8 to 20 (0.67 → 0.36). **8 is the E-core count**, and a plateau
   at precisely the width of the small cluster is what confinement to that cluster looks like
   from outside. This is the placement evidence, and it is a throughput argument rather than a
   residency measurement — see the caveat above.

**E-cores alone still parse.** At its plateau the background class dispatches **92.9 files/s**
(290 files in 3.12 s) against the full machine's 805.6 — the 8 E-cores are worth about 11.5 % of
20 P + 8 E on this work, and they are doing it at the QoS class the OS reserves for work nobody
is waiting on.

## 5-6 — watts

**The directive was: measured, never imagined. Here is exactly what was and was not obtained.**

| rail | host | status |
|---|---|---|
| CPU package / cluster (`powermetrics --samplers cpu_power`) | Mac | **unavailable pending one-time sudo grant** |
| CPU package (`turbostat --show PkgWatt`) | Linux | **unavailable pending one-time sudo grant** |
| RAPL `energy_uj` | Linux | **unavailable** — `Permission denied` (root-only since the platypus/RAPL side-channel fix) |
| GPU board (`nvidia-smi`) | Linux | **MEASURED** — needs no root; table below |
| GPU (`powermetrics --samplers gpu_power`) | Mac | **unavailable pending the same grant** |

### What was tried, and the exact refusal

```
$ sudo -n /usr/bin/powermetrics -i 200 --samplers cpu_power -n 5     # Mac
sudo: a password is required
$ sudo -n /usr/sbin/turbostat --show PkgWatt --interval 1            # Linux
sudo: a password is required
$ cat /sys/class/powercap/intel-rapl:0/energy_uj                     # Linux
cat: '/sys/class/powercap/intel-rapl:0/energy_uj': Permission denied
```

Tried once each, as instructed; **no password was attempted**. The rootless paths were checked and
are genuinely empty on the Mac: `ioreg -c AppleSMC` exposes **0** keys whose name contains `watt`,
there is no `IOPMPowerSource` (it is a desktop on AC), and `/etc/sudoers.d/` is empty. There is no
number to read on that machine without the grant, and this report does not print one.

### The one-time grants (one line each, sampler only)

```bash
# Mac
echo "dog ALL=(ALL) NOPASSWD: /usr/bin/powermetrics" | sudo tee /etc/sudoers.d/powermetrics && sudo chmod 440 /etc/sudoers.d/powermetrics
# Linux
echo "omen ALL=(ALL) NOPASSWD: /usr/sbin/turbostat" | sudo tee /etc/sudoers.d/turbostat && sudo chmod 440 /etc/sudoers.d/turbostat
```

After either, `docs/omen/apple/measure_watts.sh <label> -- <cmd>` prints samples / mean W / peak W
/ joules per rail with no further changes. It is committed and it is wired for all three samplers.

### `measure_watts.sh`, verified end to end on the rail that needs no root

The script was not left as an untested artifact. On Linux it detects the missing grant, says so,
and falls back to the NVIDIA board sensor, which any user may read — so the whole path (sample,
run, stop, parse, joules) is proven on real hardware. Sampled at 200 ms around
`bench/runtime/mandelbrot` built by Bend, RTX 3090:

| window | wall s | samples | mean W | peak W | board joules |
|---|---:|---:|---:|---:|---:|
| idle, before | 15.004 | 69 | **14.46** | 18.21 | 216.9 |
| **CPU lane** — 20 × `--gpu off --threads 16` | 9.148 | 40 | **13.95** | 18.22 | 127.6 |
| **GPU lane** — 20 × `--gpu 512MB` | 2.474 | 16 | **81.27** | 150.63 | **201.1** |
| idle, after | 15.005 | 70 | 33.35 | 150.99 | 500.5 |

Read honestly:

- The CPU lane leaves the board at idle (13.95 W vs 14.46 W): when Bend runs on 16 CPU threads the
  discrete GPU is genuinely doing nothing, which is the control this table needed.
- The GPU lane costs **81.27 W mean, 150.63 W peak, 201.1 J for 20 runs = 10.1 J per run**, or
  **8.3 J per run net of the 14.46 W idle floor**. It is also 3.7× faster in wall time
  (0.124 s/run against 0.457 s/run).
- **This does not say the GPU lane uses less total energy.** The CPU package is the rail that is
  not readable, and it is exactly where the CPU lane's cost lives. Board watts are one side of
  the ledger and the report will not pretend otherwise.
- **The trailing idle window is dirty** — 33.35 W mean and a 150.99 W peak after the GPU run,
  against 14.46 W before it. The board had not settled and the desktop was live. It is printed
  because it was measured, not because it is a clean baseline; the leading window is the baseline.

**No watt figure anywhere in this report is modelled, scaled from a TDP, or inferred.** Every
Apple-silicon watt is absent, and labelled absent.

## 7 — Metal: first light, and the whole runtime bench table

The stretch goal was "GPU first light; if it resists, design-note it". It did not resist. **Every
`!` program this lane ran compiled to Metal and executed on the M3 Ultra's 60-core GPU — all 16
`bench/runtime` benches plus `tests/regex/gpu.bend` and `tests/strings/gpu.bend` in their suites'
own GPU lanes — with exactly one exception, `tests/f64/mc_pi.bend` (F3), and all 16 benches
reproduced their pinned output.** The tree's other `!` files (`tests/compile/*`, `tests/printer/*`,
`tests/comptime/*`, three demos) belong to runners this lane did not drive; not claimed either way.

### That the device really executes — by construction, not by a utilization graph

`bend2/comp.ts`'s CLI leaves no room for a silent CPU fallback:

```c
bool dev = gpu != 0 && BANGS != 0 && gpu_probe();
if (gpu == 1 && BANGS != 0 && !dev) {
  cli_fail("--gpu on, but this binary found no GPU device", NULL);
}
```

`gpu_probe()` on the Metal path *is* `MTLCreateSystemDefaultDevice() != nil`. A `--gpu 4GB` run
that exits 0 therefore had a real Metal device; a machine without one gets a hard failure, not a
slower answer. Downstream of that, `corpus_setup(dev=true, …)` takes the `gpu_map(size)` branch
(the heap is device memory, not a host `mmap`), and every `!` call goes through `gpu_pass`, which
commits a command buffer, `waitUntilCompleted`s it, and `err_fail`s on `[cb error]`. The archive
it dispatches is genuinely GPU code:

```
$ file /tmp/sort.gpu
/tmp/sort.gpu (for architecture applegpu): Mach-O 64-bit GPU executable applegpu
$ strings /tmp/sort.gpu | grep -m1 'metal version'
Apple metal version 32023.921 (metalfe-32023.921.5)
```

with `bend_dev`, `monk_step`, `task_deal`, `ring_push`, `work_loop` and `heap_alloc` as kernel
symbols. **What is *not* offered as evidence:** GPU utilization. `ioreg -c IOAccelerator`'s
`Device Utilization %` reads 54-71 % on this machine *at idle* — the desktop compositor dominates
it — and a `sort --gpu 4GB` loop does not move it. The tool that would attribute GPU residency is
`powermetrics --samplers gpu_power`, which needs the root this lane does not have (§5-6). The
construction above is the evidence; the utilization sampling was tried, was useless, and is
reported as useless.

### The 16-bench runtime table on the M3 Ultra

`docs/omen/apple/bench_pins.sh` replicates `gates/perf.ts`'s runtime table on one machine — the
gate shards its 48 cells over 48 minis and a Mac that is not in the cluster cannot be a shard.
Same emit (`bend main.bend -o main.c`), same two build lines, same flags, same warm-run-first,
medians of **3** instead of the gate's single timed run:

```
cc -std=c11 -O3 main.c -lpthread                                        # SEQ, PAR
cc -std=c11 -O3 -DBEND_METAL=1 -x objective-c -fobjc-arc main.c \
   -lpthread -framework Metal -framework Foundation                     # GPU
```

Every one of the 16 benches built, ran all three modes, and printed the **pinned output**
(`OUTPUT` below is `apple_m4.txt`'s column, matched byte for byte, 16 / 16). The machine carried
real user load throughout — `load average` was 4.20 → 5.52 across the `nt=32` sweep and 4.85 →
6.56 across the `nt=16` one — so every figure here is a *loaded-machine* figure and reads
pessimistic against a pin taken on an idle box.

| bench        | SEQ-CPU  | PAR nt=32 | PAR nt=16 | PAR-GPU  |   GPU vs PAR32 | OUTPUT     |
|--------------|----------|-----------|-----------|----------|----------------|------------|
| bfs          |   3.977s |    0.221s |    0.300s |   0.211s |          1.0x  | 651176970  |
| editdist     |   2.186s |    0.159s |    0.179s |   0.192s |   1.2x slower  | 2229810577 |
| gameoflife   |   8.318s |    0.431s |    0.596s |   0.072s |          6.0x  | 2016151040 |
| hashmap      |   3.469s |    0.197s |    0.279s |   0.831s |   4.2x slower  | 1307803744 |
| kmeans       |   2.304s |    0.309s |    0.307s |   0.313s |   1.0x slower  | 1616398086 |
| lexer        |   9.466s |    0.511s |    0.666s |  14.677s |  28.7x slower  | 2401049475 |
| mandelbrot   |   5.166s |    0.290s |    0.384s |   0.067s |          4.3x  | 3101455856 |
| merkle       |   5.637s |    0.335s |    0.417s |   0.080s |          4.2x  | 3104235417 |
| nbody        |   6.797s |    0.346s |    0.496s |   0.073s |          4.7x  | 3516450380 |
| queens       |   6.049s |    0.336s |    0.455s |   1.165s |   3.5x slower  | 2063750025 |
| raytrace     |   5.371s |    0.293s |    0.397s |   0.215s |          1.4x  | 1924309504 |
| symreg       |   4.673s |    0.258s |    0.350s |   0.724s |   2.8x slower  | 2383953211 |
| terrain      |   2.536s |    0.158s |    0.202s |   0.125s |          1.3x  | 2572468224 |
| tree-bitonic |   7.222s |    0.803s |    0.891s |   1.453s |   1.8x slower  | 3787129428 |
| tree-matmul  |   3.807s |    0.255s |    0.354s |   0.348s |   1.4x slower  | 3797651056 |
| tree-radix   |   4.761s |    0.393s |    0.408s |   1.158s |   2.9x slower  | 1998173798 |

What the table says:

- **The parallel runtime scales to 28 cores.** Median SEQ→PAR speedup is **17.7x at `nt=32`**,
  on a machine that was also running someone's desktop the whole time. `nbody` peaks at **19.6x**,
  `bfs` at **18.0x**, `mandelbrot` at **17.8x**; the floor is `tree-bitonic` at 9.0x and `kmeans`
  at 7.5x, both allocation-heavy. Note this is *below* 20x — the E-cores' contribution is not
  visible in this column, and §4 is where it is measured.
- **`nt=32` beats `nt=16` on 15 of 16 benches**, median **1.34x**, which is the honest answer to
  "does the gate's thread rule fit a 28-core box": it does, by oversubscribing 32 workers onto 28
  cores rather than leaving 12 idle. The one that does not is `kmeans` (0.99x), and `tree-radix`
  barely moves (1.04x).
- **The GPU wins on 7 of 16** (`bfs`, `gameoflife`, `mandelbrot`, `merkle`, `nbody`, `raytrace`,
  `terrain`), up to **6.0x over an already-19x-parallel CPU run** on `gameoflife` and **4.7x** on
  `nbody`. It loses on the nine whose kernels are allocation- or pointer-chase-bound. The M4
  pin's GPU also wins on 7 of 16, 6 of them the same benches: the split is a property of the
  workloads, not of this machine.
- **GPU RSS is flat at 13.2-14.2M on all 16**, against a CPU `PAR` RSS spanning 3.7M (`queens`)
  to 662.6M (`tree-radix`) — `/usr/bin/time -l`'s maximum resident set, as the gate records it.
  On the GPU path the heap is device memory, so the host process holds only the shell.

### Against the two pins in the tree

`bench/runtime/_pin_/apple_m4_max.txt` (2026-09-17, `d0db7b3e`) and `apple_m4.txt` (2026-09-11,
`b20509fd`) are the tree's own Apple numbers. **Neither commit is reachable from this checkout**
(`git cat-file -e` fails on both), so a difference between the pins and this run can be hardware,
load, *or* a runtime change in between, and this lane cannot separate them. Ratios below are
`M3 Ultra / pin`; **under 1.00 means the M3 Ultra was faster**. The PAR column uses the M3
Ultra's `nt=16`, which is the thread count `gen_pins.ts`'s own rule picks on 28 cores (F6) —
but neither pin file records its machine's core count or its `nt`, so that column is the
loosest comparison in the table and is offered as indicative only.

| bench        | SEQ M3U/M4Max | PAR M3U nt=16 / M4Max | GPU M3U/M4Max | GPU M3U/M4 |
|--------------|---------------|-----------------------|---------------|------------|
| bfs          |          1.02 |                       0.87 |          1.02 |       0.22 |
| editdist     |          0.85 |                       0.76 |          1.33 |       0.40 |
| gameoflife   |          1.07 |                       0.92 |          1.14 |       0.72 |
| hashmap      |          1.27 |                       1.17 |          1.60 |       0.54 |
| kmeans       |          1.11 |                       1.15 |          1.64 |       0.45 |
| lexer        |          4.42 |                       3.36 |         13.65 |       3.77 |
| mandelbrot   |          1.15 |                       0.97 |          1.18 |       0.99 |
| merkle       |          1.34 |                       0.99 |          1.13 |       0.99 |
| nbody        |          1.18 |                       0.96 |          1.24 |       1.12 |
| queens       |          1.12 |                       1.00 |          1.25 |       0.43 |
| raytrace     |          1.16 |                       1.00 |          1.42 |       0.54 |
| symreg       |          1.55 |                       1.32 |          1.37 |       0.89 |
| terrain      |          1.14 |                       1.03 |          1.18 |       0.43 |
| tree-bitonic |          1.20 |                       1.12 |          3.23 |       0.73 |
| tree-matmul  |          1.84 |                       1.57 |          1.51 |       0.35 |
| tree-radix   |          1.17 |                       0.92 |          3.69 |       1.13 |
| **median**   |      **1.16** |                   **1.00** |      **1.35** |   **0.63** |

- **Single-thread, the M3 Ultra is ~16 % behind the M4 Max** (median 1.16), which is what one
  generation of Apple core and a loaded machine buy. At equal thread count the two are a **dead
  heat** (median 1.00) — the Ultra's extra cores are exactly cancelled by the per-core deficit at
  `nt=16`; the Ultra's win comes from being *allowed* 32 threads (the 1.34x above).
- **The GPU column disagrees with itself across the two pins** — median **1.35** against the M4
  Max's, median **0.63** against the M4's. The M3 Ultra's 60-core GPU is slower than the M4
  Max's on all 16 benches and faster than the M4 mini's on 13 of 16 — two readings that cannot
  both be about this machine's hardware. The two pins are six days and one
  unreachable commit apart, and the M4 Max pin came from a different tool (`gen_pins.ts`, which
  also emits C/TS/Lean columns) than the M4 one (`gates/perf.ts`). **Flagged, not explained.**

### The `lexer` anomaly

`lexer` is the one row that is off by a factor, not a percent: **4.4x** the M4 Max's SEQ time,
**3.4x** its PAR time, **13.7x** its GPU time. Every other bench's SEQ and PAR ratios sit between
0.76x and 1.84x, and the worst other GPU ratio is 3.69x. It is not a correctness divergence — `lexer` prints `2401049475`, the pinned
output, in all three modes.

The bench's own header says why the shape is fragile:

> Bend's String is a cons list, one node per character, so the lexer walks a linked list where C
> walks bytes.

That is a dependent-load chain: every step's address comes from the previous load, so the
workload is bound by memory *latency* and nothing else — no prefetcher helps, no extra core
helps, and a GPU (14.677s, the only bench where the GPU is catastrophically worse) is the worst
possible machine for it. An Ultra is two dies joined by an interposer, and a pointer chase that
lands on the far die pays the fabric each hop. **That is the hypothesis and it is not proven
here** — proving it needs a latency-under-die-crossing measurement this lane did not take, and
the unreachable pin commits mean a change in the bench or the runtime between `d0db7b3e` and
`ac994157` cannot be ruled out either. It is recorded as an open anomaly with a testable cause.

## 8 — methodology

- **Everything ran over `ssh -o ConnectTimeout=10 -o BatchMode=yes dog@depths-mac-studio`**, every
  session non-interactive, no GUI tool touched.
- **Medians, always, with a warm run first.** 5 timed runs for the parse table, 7 for decode at
  8 MiB and for the regex scan, 5 for decode at 64 MiB, 3 for the runtime pins (the gate takes 1).
- **Wall time from outside** the process (`perl -MTime::HiRes=time`, because BSD `date` has no
  `%N`), and where a phase is quoted it is the binary's own `IO.now()` delta, printed on stderr.
- **Correctness is asserted inside the loop, not checked afterwards.** The parse table `cmp`s every
  run against the sequential run's stdout; the decode bench compares every run's code-point count
  against the generator's oracle; the pins table compares all three modes' stdout against each
  other and prints the value, which is then read against the committed pin.
- **`BEND_NO_TELEMETRY=1` everywhere.** Without it `bend2/main.ts`'s daily version check writes
  `bend 2.0.20 is available: run bend update` to stderr, and `tests/run.sh` captures stderr into
  the compared output — six spurious FAILs on the first Mac run, all of them that one line.
- **The Mac was never idle.** Load average 3.1 - 6.6 for the whole session, printed in each run's
  own box line and quoted beside each table. Nothing here was measured on a quiet machine.
- **Linux comparison numbers were re-run today at this commit**, except the parse table (§3),
  which is `parcorpora.md`'s, and the `_pin_` files, which are the repo's own.

## 9 — honest limits

1. **No watts on Apple silicon.** §5-6. The single biggest hole in this lane, and it is a
   permissions hole, not a measurement one: one `sudoers.d` line closes it.
2. **P/E placement is inferred from a throughput plateau, not observed.** §4. The plateau at
   exactly 8 threads is a strong shape, but it is not residency data, and `taskpolicy` is a hint
   rather than an affinity mask. Anyone who grants the `powermetrics` line gets the real
   attribution in the same run as the watts.
3. **`taskpolicy` cannot ask for P.** It clamps downward only, so there is no "pin to P-cores"
   row anywhere in this report — the P-leaning row *is* the default row, and it is labelled that
   way rather than dressed as a third class.
4. **The pins table is medians of 3 against pins that are single timed runs.** Both
   `gates/perf.ts` and `gen_pins.ts` do one warm then *one* timed run per cell; `bench_pins.sh`
   takes three and reports the median — the more stable statistic, but not the same one. It is
   also a hand-rolled runner on a loaded machine, not `gates/perf.ts`, which cannot run here (it
   shards 48 cells over 48 minis). Its build lines, flags, `MEMORY` spans and warm-run discipline
   are copied verbatim; the harness is not.
5. **`apple_m4` and `apple_m4_max` were measured on their own machines, days and commits**
   (`b20509fd`, 2026-09-11; `d0db7b3e`, 2026-09-17). **Neither commit is reachable from this
   branch** — `git cat-file -e` fails on both, here and in the main checkout — so the bench
   sources cannot be diffed against what the pins measured. Cross-machine rows are indicative;
   only OUTPUT is an exact comparison, and it matches on all 16. Load-bearing for §7's `lexer`.
6. **One suite could not run on the Mac at all** (`codex`, 161 tests, F5) and three more lost
   auxiliary checks to a missing CPython oracle. The battery table in §2 names each and why; none
   of them is a Bend test failing. The `rg` gap in F5 is the uncomfortable one: without the shim
   the strings suite reported `Strings PASS: 101, FAIL: 0` — green, and one test short — so a
   macOS green on that suite is only trustworthy with the shim on `$PATH`.
7. **The 8 MiB decode rows are mostly process floor.** That is why the 64 MiB pass exists and why
   the throughput sentence quotes the binary's own read phase rather than the wall.

## 10 — lines for the video kit

Every one of these is a measured number from a table above.

- **"The M3 Ultra parsed 619 NumPy files — 9.5 MB of Python, lexed and parsed with a parser
  written in Bend — in 0.61 seconds. 1,021 files a second, on 20 performance cores and 8
  efficiency cores, from a program with no thread code in it."**
- **"All three corpora: 1,209 Python files, 23.4 MB, 1.42 seconds. One binary. `--threads` is the
  only knob."**
- **"The efficiency cores alone still dispatched 93 files a second — at the quality-of-service
  class macOS reserves for work nobody is waiting on."**
- **"Same source, two architectures, byte-identical results: the 290-file digest is
  `b48c40b7…fc18` on x86_64 Linux and on arm64 macOS. Not 'the same answer' — the same bytes."**
- **"Written once, run on the GPU: `mandelbrot` goes 5.17 s on one core, 0.29 s on the 28-core
  CPU pool, and 0.067 s on the 60-core GPU. 77×, and nobody wrote a line of Metal."**
- **"`gameoflife`: 8.32 seconds to 0.072. That is 115× for adding one character — the `!`."**
- **"Across sixteen benchmarks the median speedup from one core to the thread pool is 17.7× —
  and that was measured while somebody else was using the machine."**
- **"64 megabytes of UTF-8, decoded and counted in 107 milliseconds — 392 million code points a
  second."**
- **"Sixteen benchmarks, three modes each — one core, twenty-eight cores, sixty GPU cores.
  Forty-eight runs, and all forty-eight printed the number the cluster pinned."**

## 11 — what this lane added, and the gate

Six files, all under `docs/omen/`, nothing else in the tree touched. `bend2/bend.ts`,
`bend2/main.ts`, `gates/**` and `tests/caps.sh` were never opened for writing; every other
namespace was read-only.

| file | what it is | ttok | cap |
|---|---|---:|---:|
| `docs/omen/lanes/bend-apple.md` | this report | ~15.9k | 16000 |
| `docs/omen/apple/parse_scale.sh` | `demos/parallel/_lib.sh`'s table, de-GNU-ised, plus a `WRAP` hook | 1183 | 16000 |
| `docs/omen/apple/decode_len.bend` | read a file, print `String.length`, phase timings on stderr | 371 | 16000 |
| `docs/omen/apple/decode_bench.sh` | rebuilds `tests/strings/bench.sh`'s corpora and asserts its oracle count | 1077 | 16000 |
| `docs/omen/apple/measure_watts.sh` | real watts around one command, or exit 77 saying why not | 1340 | 16000 |
| `docs/omen/apple/bench_pins.sh` | `gates/perf.ts`'s runtime table on one machine | 1449 | 16000 |

`bun gates/repo.ts` → **PASS: 53 / 53** with all six staged. No new path was rejected, so there
is nothing to record under the rejection rule. Every script in the table was re-run clean at the
tip before the commit; the runs are the tables above.
