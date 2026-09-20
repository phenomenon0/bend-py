# power-13 — Drift: the detector that hands back its evidence (2026-09-20)

Lane 13 of the plan. Constant-memory online statistics that fire when a
stream's behaviour changes — and, when they fire, say *what they saw*. A
detector whose answer is a Bool has told its caller nothing it can act on: not
how big the change was, not when it started, not how much data stood behind
either estimate. This lane's `step` returns the detector and, on an alarm, an
`Ev` carrying the index it fired at, the index it believes the change began at,
and the full Welford accumulator on each side of that index.

The cost of that evidence is three extra numbers. It is not a buffer.

## What shipped

`power/drift.bend`, standalone — it imports Base and nothing else in `power/`.

**Welford, and Chan's merge.**

- `type Stat is Data: Stat{n: U32, mu: F64, m2: F64}` — three unboxed scalars.
- `empty()`, `one(x)`, `count(s)`, `mean(s)`, `sqd(s)`, `variance(s)`.
- `push(s, x)` — Welford's update: the mean moves, then `m2` takes the product
  of the residual measured *before* that move and the residual measured after.
- `merge(a, b)` — Chan, Golub and LeVeque 1979. Two accumulators become the one
  the whole stream would have built, correction weighted by `na * nb / n`.
- `tail(w, h)` — the **inverse** of merge: what the suffix saw, given the whole
  and its prefix. This is what makes the evidence window constant memory.

**Page–Hinkley.**

- `type Dir is Data: Up{} | Down{}` — direction is a parameter, not two
  detectors. Down is Up on the negated deviation, and a sign flip is exact in
  floating point, so both share one extremum and one comparison.
- `type Ev is Data: Ev{dir, at, since, before: Stat, after: Stat}` — the report.
- `type PH is Data: PH{dir, delta, lam, warm, w, cum, ext, mark}`.
- `new(dir, delta, lam, warm)`, `seen(d)`, `stat(d)`.
- `step(d, x) -> PH & Maybe<&2, Ev>` — the one actuation door. The running mean
  is updated *before* the deviation is taken against it, which is the order
  River's `drift.PageHinkley` uses. A fired detector comes back reset.

**The Hoeffding cut.**

- `eps(na, nb, r, lnid)` — ADWIN's bound (Bifet and Gavaldà 2007),
  `r * sqrt(ln(1/d) / 2m)` with `1/m = 1/n0 + 1/n1`.
- `hoeffding(a, b, r, lnid)`, `differs(a, b, r, lnid)`, `ev.differs(e, r, lnid)`
  — whether the gap a report found is larger than two windows of those sizes
  could produce by luck.

`ln(1/d)` is taken as a **parameter**, not computed. It is one constant per
caller, and it is the only logarithm this lane would otherwise need: keeping it
out means every number in the file comes from `+ - * /` and `sqrt`, which
IEEE-754 rounds exactly, so the interpreter, the JS lane and the C lane agree
bit for bit instead of within whatever ulp their libm chose. That is not a
style preference — it is why the six-lane fixture can pin exact digits at all.

## The evidence window costs three numbers, not a window

The interesting claim in this lane is that `since` — the estimated changepoint
— is free.

Page–Hinkley accumulates `cum += (x - mean) - delta` and fires when
`cum - min(cum) > lam`. The **argmin of the cumulative sum is the
maximum-likelihood changepoint** of that statistic. So the detector is already
computing the answer: every time the running minimum moves, snapshot the
Welford accumulator as it stands. That snapshot *is* `before`. And `after` is
`tail(w, mark)` — the algebraic difference between the whole accumulator and
its prefix, not a replay of the samples in between.

    before = mark                 the accumulator at the argmin
    after  = tail(w, mark)        the whole, minus the prefix

Total state: eight scalars. No ring buffer, no reservoir, no second pass. The
fixture pins `before` and `after` as counts, means and variances on every one of
the 27 `rsig` rows, so an implementation that got the detection right and the
evidence wrong cannot print a single line.

`tail` is also the one operation here with a real numerical price: it subtracts
two sums of squares, so a suffix that is tiny beside its head loses digits to
cancellation. That is stated in the file, and the "step at index 390 of a
400-sample run" row exists to walk it.

## Rule 7: `merge` is ordered, not exact, and the fixture says so

Two patterns in this package contradict each other and the conflict is real,
so it is named here rather than averaged.

- **Every other `_par` bench in `power/` asserts that a fork's answer does not
  depend on the schedule**, and pins it by requiring the same checksum on 1 and
  16 threads.
- **F64 addition is not associative.** `merge(merge(a,b),c)` and
  `merge(a,merge(b,c))` differ in their last bits. A Welford merge is a sum. So
  "the fork gives the same answer" cannot mean what it means in `budget` or
  `radix`, where the carrier is integers.

The resolution is to be precise about *which* invariance is claimed:

> **The tree's shape is written into the program, not chosen by the scheduler.**
> `par(8n, lo, n)` always splits at the midpoint, left before right, to depth 8.
> Every thread count walks the same tree in the same order and lands on
> identical bits. The schedule chooses *when*, never *what*. Two **different**
> trees over the same data need not agree, and this lane does not claim they do.

That is not a weaker claim dressed up — it is the exact claim, and it is the
one that is testable. The proof is that `drift_par` needs **its own C twin**.
`twin_drift.c` computes the same 33,554,432 samples as a left fold and prints
a *different* number on purpose; `twin_drift_par.c` reproduces the depth-8 tree
and matches. Routing `drift_par` at the sequential twin (the way `rng_par` and
`topk_par` are routed) would have printed a mismatch and the harness would have
refused to time the row. Two twins is the honest shape.

The oracle asserts the consequence rather than assuming it:
`law_merge` checks tree depths 0, 1, 2, 3, 4, 5 and 6 over the same range all
agree **at the printed quantum** (2^-20), and the fixture pins depths 1, 4 and 6
as rows. So the lane's actual guarantee — *reassociation is invisible at the
resolution anyone reads* — is measured, not asserted.

## The finding: the repo's conventional hash cannot test a drift detector

`law_quiet` is the false-positive law: a stationary stream under the configured
threshold must never fire, and — as a control — the *same* stream with `delta`
dropped to 0 must eventually fire, because an unbiased random walk crosses any
fixed threshold. The control failed. With `delta = 0` and 3,000 samples the
statistic never got near `lam`.

The source was the problem. The sample generator used the hash shape that
appears across this package:

    u = (p + 1) * 2654435761
    u ^= p >> 3

That is a **Weyl sequence** — a multiplicative recurrence with no mixing — and a
Weyl sequence is *low-discrepancy by construction*. Measured over the stream it
produced: lag-1 autocorrelation **−0.42**, and a cumulative deviation from the
mean that never left ±4 over 3,000 samples.

Page–Hinkley's statistic **is** a cumulative discrepancy. A source engineered to
have bounded discrepancy cannot exercise it. The false-positive test was not
passing — it was vacuous, and so was every quiet row in the fixture.

Replaced with a multiply–shift–xor finalizer (`u ^= u>>15; u *= 2246822519;
u ^= u>>13`). Measured over 100,000 samples of the shipped source:

    mean       -0.000323
    variance    1.334839      (uniform on [-2, 2) in steps of 1/2048)
    lag-1       0.002266      (was -0.42)
    max |walk| over 3,000       121.89   (was 4)

The control now fires 11 times in 3,000 samples with `delta = 0`, and 0 times
with the shipped `delta = 0.5`. **The detector was only retuned after the source
was fixed** — every operating point in this report is measured against a stream
that can actually drift.

This is worth carrying to other lanes: a bare Knuth multiply is fine as a
*permutation* (a shuffle, a bucket assignment, a probe sequence) and wrong as a
*random stream*. Any lane whose property is about accumulated deviation —
sketches, sampling, anything with a concentration bound — should check which one
it is relying on.

## The finding: dropping an F64 through a polymorphic parameter faults the C backend

The C and c-1thread lanes died with

    bend: memory fault (machine stack overflow?)

after exactly 16 rows of output. Bisected: independent of total row count; row
17 alone is fine; rows 16 and 17 together crash; reproducible with no dependency
on `power/drift.bend` at all.

The path into it here is `Bool.pick`, and **the strictness reading this section
originally gave is not the cause.** `Bool.pick(-A: Type, c, a, b)` is
polymorphic, `A` erases to a *boxed* layout, and `comp.ts` memoizes a def's
signature by name — so the one compiled `Bool.pick` emits a literal
`term_sink(e, a_0)` on whatever word arrives. When that word is an `F64`, the
runtime reads the double's exponent as a heap tag and its low 40 mantissa bits
as a heap address, and sinks a block that was never allocated. Strictness only
decides *which* of the two doubles gets sunk; either one is equally fatal.

The magnitude probe this lane ran — `1000.0` fine, `1000000.0` → silent blank
output, `16777216.0` fine, `2^30` and `2^32` fine, `1e12` → fault, NaN and inf
fine — is non-monotonic because the predicate is a *bit position*, not a size:

    safe  iff  (bits >> 56) & 0x7f <= 1   or   (bits & ((1<<40)-1)) < HEAP_OFF

i.e. safe exactly when no mantissa bit is set below position 40. `16777216.0`
is `2^24` — one exponent, zero mantissa — so it is safe at any magnitude;
`1000000.0` sets bit 37 and is not. That also explains why lane 14's probe
looked unrelated (4097 and 0.1 fail, 8193, 10007 and π pass): π *is* a landmine,
it just happened to address a page that absorbed the free.

The "computed vs literal" line both probes drew is **withdrawn**. It was a
confound: the discriminating pair's literal was `100000.0d` (12 mantissa bits,
safe) and its computed values were multiples of 4097 (14 bits, landmines).
Literals fail on their own — `12291.0d` blanks the output with no arithmetic in
the file. The full root cause, the second surface (`Array<F64>` cells, which are
walked as `Term`s because `lay_arr` routes any `w64` element away from the
packed block), the measured tables and what a real fix costs are at
`docs/omen/f64-drop-c-backend.md`.

The fix here is still `match` instead of `Bool.pick` at `variance`, `merge` and
`tail` (and at the fixture's `lvl`) — `match` is monomorphic and branches, so no
double ever crosses a boxed parameter. It is better code on its own terms; the
note above `variance.at` now gives the real reason. **The backend defect itself
is not fixed by this lane**: `bend2/comp.ts` is editable, but the fix is a third
block mode in the memory manager across four backends, not a local patch. It is
reported here so the next lane that hits it recognises it in one step.

## Verified

`tests/power/drift.bend` — **158 rows**, generated byte-for-byte by
`tests/power/drift_gen.py` from CPython, on six lanes: oracle, check, interpret,
js, c, c-1thread.

    Power PASS: 6, FAIL: 0

Row census:

| helper | rows | what it pins |
|---|---:|---|
| `mg` | 49 | merge and tail: both operands and the result in one string |
| `rsig` | 27 | a full report + its Hoeffding significance |
| `st` | 24 | Welford `push` over hand-written sequences and prefixes |
| `cut` | 16 | chunking invariance: two runs printed in one row |
| `hits` | 11 | the false-positive grid, both directions |
| `yn` | 10 | `differs` on real windows |
| `q` | 8 | `eps` at five count pairs and a second `(r, ln 1/d)` |
| `dly` | 5 | the detection-delay table |
| `rstat` | 4 | what the detector carries between reports |
| other | 4 | `show.dir`, a count-and-variance row for the cancellation case |

**The oracle is independent.** `class W` is Welford written from the 1962 paper;
`law_welford` cross-checks its mean and variance against
`statistics.mean`/`statistics.pvariance` over the batch, so the recurrence is
held to a third implementation that shares no code with either side. `class PH`
is a direct transcription of River's `PageHinkley.update` — mean first, then
deviation, reset on fire — and knows nothing about the Bend file beyond the laws
it is asked to satisfy.

### The laws, asserted before a row is emitted

Each runs in `drift_gen.py` at import, in the style of `law()` in
`budget_gen.py`. A run that breaks one prints nothing at all.

    law_welford   push's mean and variance == statistics.mean / pvariance
    law_merge     merge(prefix, suffix) == the batch, at every split
                  tail(whole, prefix) == the suffix, at every split
                  a depth-d tree == a left fold, depths 0..6
    law_chunk     a detector fires at the same index under any chunking
                  of the prefix (splits at 1, 30, 150, 299)
    law_quiet     3,000 stationary samples under the configured threshold
                  never fire, in either direction
                  ... and the same stream with delta = 0 DOES fire
    law_delay     a step of size k fires within 4 * lam / (k - delta)
                  delays are monotone decreasing in k
                  the evidence window straddles the true step

The last clause of `law_quiet` is the one that caught the Weyl sequence. A
false-positive law with no positive control is a law that cannot fail.

**Two things the fixture design buys.** A row carries **both sides of one claim
in one string** — `mg` prints the merge and the tail of the same pair, `cut`
prints the chunked run and the whole run side by side — so an implementation
that satisfies one side and not the other cannot print the line. And every
number is **quantized at 2^-20** with a `guard()` that refuses any value within
1e-5 of a quantum boundary, so a row is never a coin flip between two lanes'
last bits. `SCALE` is a power of two, so the dyadic samples scale exactly.

### Mutants

Five single-line semantic changes to `power/drift.bend`, each the plausible
wrong implementation, all five caught. `PASS: 2` is oracle + check — the
checked-in fixture and the typechecker are unaffected by a semantic mutation,
which is the point: the four *running* lanes are what refuse it.

| mutant | change | result |
|---|---|---|
| M1 | `push` keeps `d*d` — the naive second moment — instead of Welford's two-residual product | PASS 2 / FAIL 4 |
| M2 | `merge` drops the `na*nb/n` weight for `n/4`: right on equal halves, wrong on every uneven split | PASS 2 / FAIL 4 |
| M3 | Page–Hinkley tracks the running **max** of `cum` instead of the min | PASS 2 / FAIL 4 |
| M4 | the `delta` tolerance is dropped from the cumulative deviation | PASS 2 / FAIL 4 |
| M5 | the evidence's after-window is the whole accumulator instead of `tail(w, mark)` | PASS 2 / FAIL 4 |

M2 is the one worth dwelling on. `n/4` equals `na*nb/n` **exactly** when the two
halves are equal — so a 256-leaf tree of equal leaves would never catch it, and
`drift_par`'s checksum is not what kills this mutant. The 49 `mg` rows are: they
merge at splits 0, 1, 200 and 256 of a 256-sample range, and an uneven split is
where the weight is load-bearing.

## Measured

Both benches run 33,554,432 samples of a square wave — amplitude 3, half-period
65,536, so 512 level changes over the run and the detector spends its life
alarming and re-arming rather than sitting in one long quiet stretch.

    bench             C  bend-1T bend-16T    1T/C  1T/16T
    drift          0.14     0.24     0.24    1.8x    1.0x
    drift_par      0.13     0.14     0.02    1.0x    6.1x

Medians of three under `flock /tmp/bend-bench.lock`, with seven subagent lanes
compiling on the other cores. The `drift_par` 16T column is the one that moves
with contention — an earlier run under heavier load read 0.03 / 4.4× — so read
this as a table and not against the quiet-machine numbers in power-1..6.

**1.8× C sequential, 6.1× on 16 threads.** `drift` is the detector and it does
not fork — a changepoint detector is a scan, each step reading the state the
step before it wrote, so its 16T column is its 1T column and that is correct
rather than disappointing. `drift_par` is the half of this lane that *is*
associative: 2^8 leaves of 131,072, each folding its own range into a Welford
accumulator, joined by `merge` up the tree. At 1.0× C it is the fastest ratio
of any `_par` bench in this package, because Welford's inner loop is one divide
and four adds against no memory traffic at all.

The sequential checksum mixes, for every alarm, the index it fired at, the
changepoint it estimated, and the **quantized means of the before and after
windows** — so `twin_drift.c` only prints this number if its Welford recurrence,
its `tail` and its Page–Hinkley state machine all agree with Bend's to the last
bit of an F64. Both checksums matched C on 1 and 16 threads:

    drift       1112163857   (C, bend-1T, bend-16T)
    drift_par   1329882650   (C, bend-1T, bend-16T)

### Detection delay

A step of size k at index 200; the shipped corner `dir=up, delta=0.5,
lam=16, warm=30`. `since` is the changepoint the detector estimated; the true
one is 200.

| k | fires at | delay | `since` | n before | mean before | n after | mean after |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 0.50 | never in 4,000 | — | — | — | — | — | — |
| 0.75 | 293 | 93 | 220 | 220 | −0.056 | 73 | 0.780 |
| 1.00 | 256 | 56 | 220 | 220 | −0.033 | 36 | 1.020 |
| 2.00 | 217 | 17 | 200 | 200 | −0.072 | 17 | 1.455 |
| 4.00 | 206 | 6 | 200 | 200 | −0.072 | 6 | 3.719 |
| 8.00 | 202 | 2 | 200 | 200 | −0.072 | 2 | 8.563 |

Three things this table says that a boolean detector could not. Delay is
monotone in k and roughly `lam / (k - delta)`, which is the law the oracle
asserts with a 4× slack. For k ≥ 2 the estimated changepoint is **exactly 200** —
the argmin of the cumulative sum lands on the true step, so the evidence
partition is the right one and `before` has all 200 pre-change samples behind
it. And `k = 0.5` never fires: a step the same size as the tolerance is, to this
detector, not a step. That is the tolerance's blind spot and it is a number, not
a surprise.

### False positives

3,000 stationary samples, no change point, both directions, `warm = 30`.

| delta | lam | fires (up) | fires (down) | |
|---:|---:|---:|---:|---|
| 0.25 | 8 | 9 | 7 | |
| 0.5 | 4 | 15 | 19 | |
| 0.5 | 8 | 1 | 1 | |
| **0.5** | **16** | **0** | **0** | **← shipped** |
| 1.0 | 8 | 0 | 0 | |
| 0.0 | 16 | 11 | — | M4's regime: no tolerance |

The shipped corner is the **cheapest** grid cell with zero measured false
positives in both directions — `(1.0, 8)` is also zero but buys its quiet with a
tolerance twice as large, which doubles the blind spot in the delay table above.
All eleven cells are pinned as rows, so a change to the recurrence has to move a
number, not just keep a law true.

The bottom row is the point of `delta`. With the tolerance dropped the statistic
is an unbiased random walk, and a random walk crosses any fixed threshold given
time. `delta` is not decoration — it is what buys the quiet, and M4 is the
mutant that proves the fixture knows it.

## Deliberate ceilings

- **No ADWIN.** The plan offers ADWIN "or a simpler windowed test" and says to
  record the ceiling if the exposition cost is too high. It is. ADWIN's
  substance is the *exponential histogram* — the machinery that keeps every cut
  point of a growing window in O(log n) buckets so all of them can be tested
  each step. That is a variable-length bucket list, which in an affine language
  is an `Array` inside the detector's state, which makes `PH` kind `Type`:
  no longer copyable into both children of a fork, no longer able to ride home
  inside a `Maybe`. The whole reason this lane forks cleanly is that its state
  is scalars. **ADWIN's bound ships; ADWIN's window does not** — `eps` and
  `differs` are the test ADWIN cuts on, applied to the two windows Page–Hinkley
  already found, which is the same question asked once instead of O(log n)
  times. Marked `ponytail:` in the file.
- **No forgetting factor.** River's `PageHinkley` has an `alpha` that decays the
  running mean. This is the classical Page 1954 / Hinkley 1971 statistic, which
  is what the brief spells out. An EWMA mean would make `before` no longer a
  Welford accumulator — it would be a weighted one, with no `tail` inverse — so
  the evidence window would have to become a buffer. The detector's exactness
  and its constant memory are the same property.
- **No automatic threshold.** `delta` and `lam` are the caller's, and the
  false-positive grid above is the whole calibration story. A self-tuning
  threshold needs a model of the stationary distribution, which is the thing the
  detector is supposed to not assume.
- **`merge` is ordered, not exact.** Stated at length above. The claim is
  schedule-independence, not reassociation-independence.
- **No streaming quantiles.** The lane is mean and variance. A drift in shape at
  constant mean and variance is invisible here, and detecting it wants a sketch
  — which is lane 12.

## Battery

power 6/0 for `drift` (+ control) · repo 54/54 · caps ok, no OVER rows · bench
2/2 checksums match C on 1 and 16 threads · 5/5 mutants caught.

    $ bash tests/power/run.sh drift
    ok   wrong #| fixture detected as failing
    ok   drift                [oracle]
    ok   drift                [check]
    ok   drift                [interpret]
    ok   drift                [js]
    ok   drift                [c]
    ok   drift                [c-1thread]

    Power PASS: 6, FAIL: 0

    $ bun gates/repo.ts
    PASS: 54 / 54

    $ flock /tmp/bend-bench.lock bash tests/power/bench/run.sh drift
    bench             C  bend-1T bend-16T    1T/C  1T/16T
    drift          0.14     0.24     0.24    1.8x    1.0x
    drift_par      0.13     0.14     0.02    1.0x    6.1x

    $ bash tests/caps.sh | grep -c OVER
    0

`power/drift.bend` is 4,266 ttok against the 64,000 cap. The fixture, the
generator, the two benches and the two C twins are 13,870 / 10,486 / 998 / 845 /
1,081 / 1,013 against 16,000.

The fixture came in at **17,302 ttok** on the first full draft and was cut to
13,870 without losing a law: the stationary stream's `at0` moved from
4,000,000,000 to 9,999 (same code path, shorter literal), the three post-change
streams are walked only at the two prefix lengths where they differ from the
stationary one, merge splits went from six to four, tree depths from four to
three (depth 0 *is* the left fold, already pinned by `law_merge`), the `eps`
rows from fourteen to six, and the most-repeated argument list got a name
(`up()`). Row count 197 → 158. That also keeps the JS lane clear of its ceiling:
the emitted `do IO<Unit>:` block is one nested closure per statement.

No cap raised, no `gates/repo.ts` rule added, no `bend2/` file touched, no
`base.bend` change, no new effect. `tests/power/bench/run.sh` needed no edit
either — it compiles any `twin_*.c` beside a bench automatically, which is what
let this lane ship two twins without racing the other lanes on a shared file.

## Next

The obvious consumer is the copy-trading and monitoring shape the plan gestures
at, but two lanes inside this package want it sooner. Lane 12 (sketch algebra)
and this one are the same shape from opposite ends — a sketch is a summary that
merges, a `Stat` is a summary that merges, and `differs` is the test either
would use to say two summaries disagree; if lane 12's sketches grow a
`Stat`-shaped mergeable mean, `eps` is already the cut. Lane 18
(consequence preview) wants `ev.differs` directly: "would this action differ?"
is exactly "is the gap between these two windows larger than luck", and the
evidence window is the answer a preview has to show.

And the dropped-computed-F64 fault above has outgrown this report. It is not a
drift bug, and it now has a shared home at `docs/omen/f64-drop-c-backend.md`
(lane 14) where the minimal pair and all three trigger shapes live together.
What stays this lane's to say is the cheapest workaround: any `power/` module
that guards a partial function with `Bool.pick` is computing the undefined arm
today, and swapping it for a `match` removes the cause rather than the symptom.
