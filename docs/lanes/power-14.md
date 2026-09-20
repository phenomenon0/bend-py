# power-14 — FFT: the radix-2 transform, bit-for-bit on three backends (2026-09-20)

Lane 14 of the plan. A radix-2 Cooley-Tukey transform over complex points,
out of place, decimation in time, with numpy's sign convention and numpy's
`1/n` on the inverse.

The lane's claim is narrower and harder than "it computes a DFT". It is that
**the same transform prints the same bits** under the checker, the interpreter,
the emitted JS and the emitted C, on one thread and on sixteen — so the bench
can checksum raw IEEE-754 words instead of comparing within a tolerance, and a
C twin either reproduces the answer exactly or the harness refuses to time it.

## What shipped

| file | size | what it is |
|---|---:|---|
| `power/fft.bend` | 453 lines, 5,103 ttok / 64,000 | the module |
| `tests/power/fft_gen.py` | 207 lines, 2,220 ttok | the oracle — an O(n²) DFT in CPython |
| `tests/power/fft.bend` | 90 lines, 1,759 ttok / 16,000 | 11 rows, 320 printed values |
| `tests/power/bench/fft.bend` | 565 ttok | one 2²⁰-point transform |
| `tests/power/bench/fft_par.bend` | 691 ttok | 256 independent 2¹⁴-point transforms |
| `tests/power/bench/twin_fft.c` | 140 lines, 1,482 ttok | the C twin |
| `tests/power/bench/twin_fft_par.c` | 142 lines, 1,387 ttok | the C twin |

The surface, all of it public:

- `type C is Data: C{re, im}` — a complex point. `c.zero`, `c.one`, `c.re`,
  `c.im`, `cadd`, `csub`, `cmul`, `csq`, `cconj`, `cscale`.
- `type Sig is Type: Sig{n, d, arr}` — a signal: `2^d` points, `n` of them, in
  an `Array<C>`. `new(d)`, `len`, `at(s, i)`, `put(s, i, x)`, `of_list`,
  `of_real`, `to_list`.
- `half(j)`, `kernel(p)`, `table(m, p, b)` — the twiddles.
- `split(s, m, p)`, `comb(a, b, m, p)`, `go(d, x)` — the recursion.
- `fft(s)`, `conj(s)`, `ifft(s)`, `hadamard(a, b)`, `convolve(x, y)`.

`Sig` is kind `Type`, not `Data`, because it contains an `Array`. That is
power-20's finding and it is load-bearing here: a `Sig` has a single owner, so
it cannot sit in a `Result` and it cannot be read by two forked branches. The
whole shape of the file follows from it — see "Written for the fork".

## F32, not F64 — and the reason is mechanical

`C{re: F32, im: F32}`, not `F64`. This is not a numerical preference and it is
not a workaround chosen by trial. The root cause, derived by the coordinator
and written up in `docs/omen/f64-drop-c-backend.md`:

An `F64` is stored **unboxed**, so a double's raw bits ride in a `Term`-shaped
slot. The C runtime reads bits 56-62 of such a slot as a tag and the low 40 as
a heap address, and `term_sink` frees anything the tag does not call trivial.
Which slots get walked is decided by `lay_arr` in `comp.ts`: an element wider
than `w32` cannot use the packed 32-bit block (`blk_ptr` is `u32a*`, `blk_node`
packs two cells per word) and falls into the block whose cells `term_drop`,
`blk_copy` and `blk_keep` each walk **as `Term`s**. `C{re: F64, im: F64}` is
`ks = ["w64","w64"]` and lands there. `C{re: F32, im: F32}` is
`ks = ["w32","w32"]`, takes the packed block, and is never walked.

So the F32 change fixes this **mechanically, not by luck** — and no
rearrangement of the transform could have saved F64, because an FFT must drop
buffers. This one discards three at every level of the recursion: the source a
`split` consumes, and the two halves plus the twiddle table a `comb` consumes.

What it looked like before the diagnosis, for the record: in F64 the forward
transform was correct at 2, 4 and 8 points and died at 16 with
`bend: memory fault (machine stack overflow?)`, on one thread and on sixteen,
while the checker, the interpreter and JS agreed bit for bit. It is a
C-backend-only fault and the same file is correct everywhere else.

I earlier framed this as "the drop of a *computed* F64" and published a
magnitude sweep around it. **Both are retracted.** Literals fail too, and
magnitude correlates with nothing usable; the real predicate is on a double's
bits (safe iff no mantissa bit is set below position 40, or the value is
zero/inf/NaN), which is why the old sweeps looked random. The doc carries the
derivation, the emitted C, the second surface (polymorphic params, where
`sig_def`'s memoization emits a literal `term_sink` on a raw double), and what
a real fix needs.

The determinism argument below is unaffected: IEEE-754 requires the same five
operations to be correctly rounded in binary32 as in binary64.

## Determinism: why there is no `sin` and no `cos` in the file

Every arithmetic operation in the module is one of the five IEEE-754 requires
to be correctly rounded — add, sub, mul, div, sqrt. Nothing else. That is the
entire reason three backends agree on the last bit: the interpreter, V8 and
clang have no freedom left.

So the twiddles cannot come off a library `sin`/`cos`. Those are libm's, one
implementation per host, and nothing in the standard makes two hosts agree on
their last bit — a single ulp there and the C lane and the JS lane print
different fixtures on different machines. Instead `half` runs the half-angle
recurrence

    cos(t/2) = sqrt((1 + cos t) / 2)    sin(t/2) = sqrt((1 - cos t) / 2)

seeded at `exp(i·pi) = (-1, 0)`, one `sqrt` per level. The angle stays in
`[0, pi]`, where `sin` is never negative, so the positive root is the right one
at every step and no quadrant bookkeeping is needed.

`table` then builds `b^k` by squaring — `t[2k] = t[k]²`, `t[2k+1] = t[2k]·b` —
so every entry reads an index below its own, one ascending pass fills it, and
the rounding depth is `log m` instead of the `m` a running product would carry.

This is what lets the bench checksum `F32.bits` directly. Both twins compile
with `#pragma STDC FP_CONTRACT OFF`, because an FMA would round once where Bend
rounds twice — a real difference in the answer, not a detail.

## Written for the fork

An `Array` has one owner, and one owner cannot be two halves at once. The
textbook in-place butterfly loop over a single buffer is therefore not
available, and the recursion is the real thing instead: `split` **gathers** the
even and the odd points into two new buffers that own themselves, `go` recurses
into both sides in parallel, and `comb` merges them.

The price is the gather — `n log n` cells copied on top of the `n log n`
butterflies — and it is paid deliberately, to make the halving tree a fork tree.

The twiddle table is recomputed at **every** combine for the same reason: a
single-owner `Array` cannot be shared across a parallel fork, so it cannot be
hoisted out of the recursion. `twin_fft.c` recomputes it too, with a comment
saying why. Hoisting it on the C side would have timed a different algorithm
and flattered Bend's column by comparison.

## Verified

### The oracle is not the same algorithm

`fft_gen.py` computes the DFT's **definition** — `X[k] = Σ x[j]·exp(-2πijk/n)`,
O(n²), twiddles straight from `cmath.exp`. Bend factorises and takes its
twiddles off a `sqrt` recurrence. The two share no code and no factorisation,
so a row that matches is an agreement about what a DFT *is*, not two copies of
one loop agreeing with themselves.

They meet on a scaled integer: each component is printed as
`floor(|v|·100 + 0.5)` with a sign, computed identically on Bend's F32 answer
and on CPython's float64 one. That comparison is only valid while both answers
sit on the same side of every rounding boundary, so `q` **refuses to emit** a
value within `MARGIN = 0.02` of one — the fixture fails loudly at generation
rather than quietly on somebody else's machine.

`MARGIN` is measured, not guessed. Re-emitting the fixture at `SCALE=100000`
recovers Bend's F32 answer to ~1e-5 and puts the worst `|F32 - float64|` gap
over all 320 values at **0.00276** scaled units (ramp5 bin 1: 26.5983300
against 26.5983024). `MARGIN` sits ~7x above that. The closest any case here
comes to a boundary is 0.0322, so the tripwire has 11.7x of room on this data —
it is there to catch a *new* case, not to grade the present one.

### The rows carry claims, not just values

An impulse must transform flat (every twiddle meets a zero). A constant must
give `n` at bin 0 and **exact** zeros elsewhere. `±1` at every other sample is
the Nyquist-adjacent tone and must land in bins 2 and 6. The same eight points
at three lengths must *interpolate* rather than change. The inverse must undo
the forward at every depth. A convolution with a shifted impulse must rotate
the signal, and with a box must run a sum. 11 rows, 320 values.

### Mutants — seven, all caught

Run from `/tmp/fft_mutate.sh`, which restores the original on every exit path;
nothing was left in the tree.

| # | mutant | rows failed |
|---|---|---:|
| M1 | `kernel`: `exp(+iπ/2^p)` — the transform runs backwards | 3 / 11 |
| M2 | `csub` becomes `cadd` — the butterfly loses its minus | 10 / 11 |
| M3 | `half.step`: the two roots swapped, every twiddle reflected | 8 / 11 |
| M4 | `half(0n) = (1, 0)` instead of `(-1, 0)` | 5 / 11 |
| M5 | `ifft` drops the `1/n` | 5 / 11 |
| M6 | `cmul`: the cross term added instead of subtracted | 8 / 11 |
| M7 | `cconj` returns `x` unchanged | 8 / 11 |

**M1 is the one worth reading.** Only 3 of 11 rows catch a flipped Fourier sign
convention, and that is structural rather than bad luck: the round-trip rows
are direction-blind (conjugating twice is the identity), the convolution rows
are too (both transforms flip together and the product comes back right), and
`imp3`, `dc3` and `tone3` have zero or symmetric imaginary parts. Only the raw
forward `ramp3/4/5` rows pin the sign. A fixture built from round-trip and
convolution tests alone — the obvious way to test an FFT — would have let this
module ship with the wrong convention.

## Measured (Ryzen 7 7700X, 8 cores / 16 threads, `--gpu off`)

| bench | C | bend-1T | bend-16T | 1T/C | 1T→16T |
|---|---:|---:|---:|---:|---:|
| `fft` — one 2²⁰-point transform | 0.09 | 0.12 | 0.06 | 1.4x | 2.0x |
| `fft_par` — 256 independent 2¹⁴-point transforms | 0.16 | 0.33 | 0.06 | 2.1x | 5.9x |

Checksums `1308687614` and `2381610451`, identical on C, on 1 thread and on 16.
The harness only times a row after that three-way match, so the seconds above
are seconds spent computing the same bits.

**1.4x and 2.1x off C on one core** is the cost of the primitive, and it is
paid mostly in the gather that a single-owner `Array` forces. At 16 threads
Bend is *faster than the C twin* on both rows (0.06 against 0.09 and 0.16),
which is the whole point of writing it for the fork.

The two scaling numbers differ for a reason that can be computed rather than
guessed. In one transform the combines are a dependent chain: the top `comb` is
O(n), its two children are O(n/2) each and run in parallel, and so on, so the
critical path is `n + n/2 + n/4 + … = 2n` against `n log n` of work — an
**Amdahl ceiling of log n / 2 = 10x** at n = 2²⁰. Measured 2.0x, well under it;
the gap is memory traffic, and I did not profile further, so I state the number
and not a cause. `fft_par`'s leaves are independent, so its ceiling is the 16
threads themselves, and 5.9x of 16 on a machine with 8 physical cores is the
honest shape of that.

Both rows were timed under `flock /tmp/bend-bench.lock` with sibling lanes live
on the box. Ratios and checksums are unaffected by load; absolute seconds are.
5.9x is a floor, not this bench's ceiling.

### A note on sizing

The first cut of these benches ran at 2¹⁶ points and 64×2¹², and timed at 0.01s
— one significant digit, entirely noise at the harness's two decimal places.
They were resized to land in the same 0.1–1.5s band the sibling rows occupy.
The original numbers (1T 0.020, 16T 0.007, C 0.010) are not in the table
because a median of three 10ms runs is not a measurement.

## Deliberate ceilings

- **`ponytail:` F32 carries 24 mantissa bits**, so a transform this deep loses
  roughly `log2(n)/2` of them to accumulation. Fine for the spectra and
  convolutions here; not for anything that then inverts a near-singular system.
  The upgrade is one `sed` back to F64 the day `comp.ts` grows a packed block
  mode for 64-bit cells — the structure is float-width agnostic.
- **Radix-2 only, powers of two only.** No mixed radix, no Bluestein. A length
  that is not a power of two must be zero-padded by the caller, which changes
  the spectrum it gets (interpolation, not truncation) — `ramp3/4/5` in the
  fixture exist to make that behaviour explicit rather than surprising.
- **No real-input specialisation.** A real signal is transformed as a full
  complex one, so `of_real` pays 2x the necessary work and throws away the
  conjugate symmetry of the answer. An `rfft` that packs `n` reals into `n/2`
  complex points is the obvious next primitive, not a rewrite of this one.
- **The twiddle table is rebuilt at every combine.** Stated above; it is forced
  by single ownership, not chosen. If Bend ever grows a shareable read-only
  `Array`, hoisting it is a large constant-factor win and a small diff.
- **Out of place.** `n log n` cells copied on top of `n log n` butterflies.
  This is the price of the fork and it is the reason the 16-thread column beats
  C at all.

## Battery

    POWER_TIMEOUT=600 bash tests/power/run.sh fft
      ok fft [oracle] [check] [interpret] [js] [c] [c-1thread]
      Power PASS: 6, FAIL: 0

    bun gates/repo.ts                                   PASS: 54 / 54
    bash tests/caps.sh                                  rc=0
    flock /tmp/bend-bench.lock bash tests/power/bench/run.sh fft
                                                        exit 0, both rows matched C before timing

No cap moved. **No `gates/repo.ts` row was needed** — the existing
`^power/[a-z0-9_]+\.bend$` and `^tests/(…|power)/…$` rules already cover every
file. Nothing under `bend2/` was touched, no `base.bend` change, no `comp.ts`
native row and no new effect requested. No `@unsafe` and no `?TODO` anywhere in
the lane. Nothing committed.

## Next

- **`rfft`/`irfft`** — halve the work and the memory for real input, which is
  what `of_real` callers actually have.
- **Bluestein or mixed radix** for non-power-of-two lengths.
- **Hoist the twiddle table** the day a shareable read-only `Array` exists.
- **F64** the day `lay_arr` has a packed block mode for 64-bit cells; one `sed`
  and the fixture regenerates.
- The FFT is the missing half of several siblings: `convolve` is already here,
  so polynomial multiplication and long-integer multiplication are short files
  on top of it rather than new lanes.
