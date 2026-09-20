# power-12 — Sketch algebra: four summaries, one merge (2026-09-20)

Lane 12 of the plan. Four tiny mergeable summaries over a stream —
HyperLogLog, CountMin, MinHash, DDSketch — each constant-memory, each with a
`merge` that is exact-associative, so a fork tree gives the same answer as a
sequential pass. Not approximately the same answer. The same number.

That is the lane's whole claim, and the bench is where it is cashed:
`sketch_par.bend` forks 12,800,000 updates into 2^8 ranges, merges the 256
leaf sketches back up the tree, and prints the digest the sequential run and
the C twin print. If the merge were only *nearly* associative the harness
would refuse to time it.

## What shipped

`power/sketch.bend`, 722 lines — it imports Base and `power/bitset.bend`, for
`Bit.ones`, the SWAR popcount that `nlz` is built on. Nothing else in `power/`.

- `type Algo is Data: Hll{} | Cm{} | Mh{} | Dd{}` — which summary this is.
- `type Fp is Data: Fp{algo, seed, cells}` — the fingerprint every sketch
  carries.
- `type Error is Data: Mismatch{want, got} | Undefined{}` — a refusal names
  both fingerprints; `Undefined` is the quantile of an empty sketch.
- `type Bank is Data: BLeaf{w} | BNode{l, r}` — the registers.
- `type Sketch is Data: Sketch{fp, bank}` — fingerprint and registers.
- `Res(T) = Result<Error, T>`.
- `hash(seed, x)`, `nlz(x)`, `sat(a, x)` — the shared arithmetic.
- `cell(k, x, y)` — the one cell monoid the whole lane runs on.
- `merge(a, b) -> Res(Sketch)`, `merge2(x, y)` — the algebra, and its chaining
  form for a fork tree.
- `digest(s)` — a fold of the fingerprint and every cell, for a checksum.
- `hll.new / hll.add / hll.estimate`
- `cm.new / cm.add / cm.estimate / cm.total`
- `mh.new / mh.add / mh.jaccard -> Res(U32)`
- `dd.new / dd.add / dd.count / dd.idx / dd.quantile -> Res(U32)`
- `fp.of`, `fp.eq`, `show.algo`, `cells` — reading the fingerprint.

## The decision everything else follows from: a sketch is kind `Data`

The lane requires that `merge` **refuse** when two fingerprints disagree, and a
refusal in this package is `Fail{e}` in a `Result`. A `Result` payload must be
kind `Data`. Anything containing an `Array` — `Vec`, `Bytes`, `Bitset` — is kind
`Type`: affine, single-owner, barred from a `Result` payload. That is power-20's
finding, and it decides this lane's representation before a line is written.

So the registers are a **`Bank`**: a perfect binary tree of `U32` cells, a plain
recursive ADT of numbers like `Nat`. It copies, it drops, it rides inside a
`Result` — and, exactly as in power-20's fork, **both children of a fork can
derive from one parent sketch** with nothing threaded down the recursion.

The price is real and is what the `1T/C` column below reports: an update
rebuilds the six nodes on its descent path where C does one array store. A
register file wants to be an array and this one cannot be, because an array
would cost the refusal — which is the law the lane exists for. Named, paid,
measured.

The second decision is that **an update and a merge are the same operation**.
Every algorithm here folds its cell under one binary op:

    Hll   registerwise max         idempotent, so forking is free
    Cm    saturating add           counts accumulate
    Mh    elementwise min          the least of a union is the least of the leasts
    Dd    saturating add           bucket counts accumulate

`cell(k, x, y)` is that op, and `bank.at` (an update) and `bank.zip` (a merge)
both call it. Associativity is therefore **structural** rather than a property
anyone has to be careful about: an update is a merge with a one-hot sketch, and
there is no second code path that could disagree with the first.

Saturating add is associative at the ceiling as well as below it, which is why
the ceiling costs no law.

## The third decision: there is no float in the file

The plan flagged DDSketch as "the one needing care with F64 logs". It needs
none, because it has none.

DDSketch's mapping is `index = ceil(log(x)/log(gamma))` with `gamma = 2^(1/4)`.
That is computed here in exact integers: the exponent from a leading-zero
count, the mantissa against four thresholds `floor(2^31 * 2^(j/4))`. It is the
exact quarter-octave mapping, not an approximation of it, and `sketch_gen.py`
asserts `ddidx(x) == math.ceil(4 * math.log2(x))` on a ladder of values before
emitting anything.

HyperLogLog's estimator was the remaining float, and it is now integer too:

- the harmonic sum is fixed point, `sum 2^(K-r)` with `K = min(24, 32-2d)`
  chosen so the numerator lands at `alpha * 2^32`, the largest a U32 holds;
- the small-range correction's `ln(m/v)` comes from a **squaring ladder** —
  `floor(2^15 * log2(x))` by fifteen squarings of a mantissa held at scale
  `2^15`, where a square is at most `(2^16-1)^2 = 4,294,836,225`, under `2^32`
  by 131,071. That headroom is the reason the scale is 15 and not 16.

`sketch_gen.py` computes the textbook double beside every integer estimate and
asserts they agree to inside 2% — so the fixed point is checked against the
formula it replaces, not merely against itself.

### Why it is integer: a measured C-backend defect, not taste

The first version used F64 and typechecked. It passed **oracle, check,
interpret and js**, and failed **c and c-1thread**:

    Power PASS: 4, FAIL: 2

The fault was not in the estimator's arithmetic. Bisecting the fixture row by
row (`stdbuf -o0`, because the crash point moves under a buffered pipe) reduced
it to: calling `hll.estimate` repeatedly in one C build faults the runtime.

    IO.print(e(400n))  x1   ->  415
    IO.print(e(400n))  x6   ->  415, 415, "bend: runtime fail-stop"

with the full fixture instead reporting `bend: memory fault (machine stack
overflow?)` at a row that runs fine on its own, and at a different row
depending on how many rows precede it. `ulimit -s unlimited` does not change
it, so it is not the machine stack. Symptom instability at a moving address is
memory corruption.

Lane 14 reported the same class independently and in the same session, first as
an `Array<F64>` defect. This lane's `Zs{z: F64, v: U32}` holds no `Array`, so
the two reports could not both be the same bug, and that disagreement is what
forced the question open.

**The rule this section originally drew — "dropping a *computed* F64 is broken,
a literal drops fine" — is withdrawn.** It came from a discriminating pair that
confounded two variables: the literal in it was `100000.0d` and the computed
values were multiples of `4097`. Literals fail on their own. The real mechanism,
root-caused after this lane shipped, is that an `F64` is stored **unboxed**, so
the runtime reads a raw double's exponent as a heap tag and its low 40 mantissa
bits as a heap address. A double is a landmine iff any mantissa bit is set below
position 40 — a bit position, not a magnitude, which is why every sweep looked
random. Exactly two surfaces sink such a slot: `Array<F64>` cells (walked as
`Term`s) and **polymorphic parameters** (a def's signature is memoized by name,
so the single compiled `Bool.pick` emits `term_sink` on whatever word arrives).
Strictness was never the cause; it only decides which of the two doubles is
sunk. The full writeup, with all three lanes' evidence, the bit predicate and
what a real fix costs, is `docs/omen/f64-drop-c-backend.md`.

Against that mechanism, **`Zs` itself is now measured clean**: a monomorphic
record with a mixed `w64 + w32` layout, built from a computed `F64.mul`, dropped
2,000 times in a C binary, returns the exact sum. Constructor fields get real
`w64` slots; containers are not a surface. So the drop that killed the F64
estimator was elsewhere in it — one of the two named surfaces, and a guarding
`Bool.pick` is the only candidate the file's shape admits — but that file no
longer exists, so this lane cannot name the line. Recorded as unisolated rather
than guessed.

**Rule 7 — two ways out, one kept.** Lane 14's first advice was to store `F32`
instead. The rejection reasoning was wrong (`F32` does not merely "narrow" the
surface: `w32` cells take the packed block and are never walked, so it is a real
fix for the array surface) but **the decision still holds** — an integer
estimator removes the question instead of routing around it, and it makes every
printed number identical on interpreter, JS and C by construction. The cheaper
fix for a lane that genuinely needs the float is lane 13's
`match`-instead-of-`Bool.pick`; this lane does not need a float at all.

The gain is not only robustness. Every printed number in this lane is now the
same integer on the interpreter, on JS and on C by construction, with no ulp
argument anywhere.

## The laws

Asserted in `sketch_gen.py`'s `law()` before any row is emitted, *and* pinned
as rows in `tests/power/sketch.bend`:

    merge(merge(a,b),c) == merge(a,merge(b,c))   associativity, cell for cell
    merge(a,b) == merge(b,a)                     commutativity
    merge(a,a) == a                              idempotence — max and min only
    merge refuses on a fingerprint mismatch      and names both fingerprints

The fixture's shape follows from them. **A row carries both sides of one claim
in one string**, so an implementation that satisfies one side and not the other
cannot print the line:

    erow(hll_sketch, 400)          ->  "415 400"     estimate beside set()'s count
    crow(cm_sketch, key, 132)      ->  "137 132"     estimate beside Counter's sum
    jrow(jaccard(a,b), 333)        ->  "19 333"      matching slots beside true J
    qrow(quantile(s, 500), 45)     ->  "45 45"       two numbers that must be equal
    rr(merge(a,b), Done{whole})    ->  "1465624862 1465624862"

`qrow` is the strongest of them. DDSketch's buckets partition the values
monotonically, so walking them by rank finds the bucket that
`sorted(xs)[floor(q*(n-1))]` falls in — **exactly**, not within a tolerance. A
row with two different numbers is a broken walk or a broken mapping, and there
is no slack in it to hide either.

## Verified

`tests/power/sketch.bend` — 174 rows, generated by `tests/power/sketch_gen.py`,
on six lanes: oracle, check, interpret, js, c, c-1thread.

    ok   wrong #| fixture detected as failing
    ok   sketch               [oracle]
    ok   sketch               [check]
    ok   sketch               [interpret]
    ok   sketch               [js]
    ok   sketch               [c]
    ok   sketch               [c-1thread]
    Power PASS: 6, FAIL: 0

**The oracle is independent twice over.** The *truth* comes from CPython's own
containers — `set()` for the distinct count, `collections.Counter` for the
frequencies, `sorted()` for the quantiles — with no sketch involved. The
*sketch* is modelled as a flat Python **list** of cells with `max` / `min` /
saturating add, not as a tree: a bug in Bend's descent, its index mask, its
leaf order or its zip has nothing to hide behind, because the reference does
not have a descent, a mask, a leaf order or a zip. `nlz` comes from
`int.bit_length()`, not from a second copy of the popcount ladder.

Every accuracy claim is asserted between the two before a row is emitted, so a
row can never pin a sketch that is merely self-consistent:

    |hll - |set(xs)||  <= 3.5 * 1.04/sqrt(m) * |set(xs)|
    cm(x) >= Counter(xs)[x],  and <= it + e/w * total
    |mh/k - jaccard(set(a), set(b))| <= 4/sqrt(k)
    dd(q) == ddidx(sorted(xs)[rank])         exactly
    ilg(x)/2^15 within 0.002 of math.log2(x)

The fork tree is pinned as rows too: `htree(dn, ...)` for `d = 0..5` — 1, 2, 4,
8, 16 and 32 leaves — all print the sequential digest, as do `ctree` and
`dtree` for CountMin and DDSketch.

### Mutants

Eight single-line semantic changes to `power/sketch.bend`, each the plausible
wrong implementation. `PASS: 2` is oracle + check — the fixture file and the
typechecker are unaffected by a semantic mutation, which is the point: the four
*running* lanes are what refuse it.

| mutant | result |
|---|---|
| HLL merge takes `min`, not `max` | PASS 2 / FAIL 4 |
| MinHash merge takes `max`, not `min` | PASS 2 / FAIL 4 |
| CountMin estimate keeps the last row instead of the least | PASS 2 / FAIL 4 |
| `merge` ignores a fingerprint mismatch (`fp.eq(f, g)` → `True{}`) | PASS 2 / FAIL 4 |
| DDSketch quantile ranks by `q*n`, not `q*(n-1)` | PASS 2 / FAIL 4 |
| DDSketch bucket floors the log instead of ceiling it (`is_le` → `is_lt`) | PASS 2 / FAIL 4 |
| CountMin counters add without saturating | PASS 2 / FAIL 4 |
| HyperLogLog records the leading-zero run without the `+1` | PASS 2 / FAIL 4 |

**The saturation mutant is worth its own paragraph, because it survived the
first fixture.** A plain `U32.add` in place of `sat` is still associative and
still commutative, so no law row can see it — only a row that actually reaches
the ceiling can. Three rows were added: a counter driven to `2^32-1` and
charged ten more, its digest, and a merge of two such sketches. Reported here
rather than quietly fixed, because "8/8 caught" would otherwise be a claim
about a fixture that had been rewritten to make it true.

## Measured

`tests/power/bench/sketch.bend` runs 12,800,000 HyperLogLog updates over 64
registers through `Sk.hll.add` — the library's own entry point, not an inlined
copy — and prints `Sk.digest`. The twin is `twin_sketch.c`: a flat `u32[64]`
and one compare-and-store an update, under `clang -O3`.

    bench             C  bend-1T bend-16T    1T/C  1T/16T
    sketch         0.05     0.80     0.65   17.3x    1.2x
    sketch_par     0.04     0.65     0.11   18.5x    6.0x

A second run of the same two rows, taken later under the same lock with a
different set of lanes compiling beside it, read `17.5x / 1.0x` and
`15.4x / 5.2x` — same shape, and the spread is the noise floor of a shared
machine, not a change in the program.

**17× C, 6.0× on 16 threads.** The 17× is the Bank, and it is the honest
number: C does one store into a register file, Bend rebuilds the six `BNode`s
on the descent path and the `Sketch` and `Fp` around them. Against the other
scalar lanes in this package (bitset 2.1×, radix 2.0×, vec 2.2×) it is an order
of magnitude worse per element, and that gap *is* the cost of kind `Data`. It
buys the refusal, the free fork, and the 6.0×.

`sketch_par` prints **the same checksum as the sequential run and as C**
(`267983600`), and that identity is the row. It forks into 2^8 ranges of
50,000, each range building its own sketch from `hll.new`, merged back up the
tree by `merge2`. Registerwise max is associative, commutative and idempotent,
so the schedule cannot be observed in the answer. A merge that took `min`, or
one that ignored the fingerprint, would print a different number and the
harness would refuse to time it — the bench is a law check that happens to also
be a stopwatch.

Both figures are medians of three under `flock /tmp/bend-bench.lock`, with
several subagent lanes compiling on the other cores.

### Accuracy against space

Every figure below is computed by `sketch_gen.py` against CPython's own truth,
on the same streams the fixture pins.

**HyperLogLog** — 64 registers, 256 bytes of cells. Standard error
`1.04/sqrt(64)` = **13.0%**.

    arrivals   distinct   estimate    error   branch
         400        400        415    +3.8%   harmonic
        2000       2000       1656   -17.2%   harmonic
        4096       4096       3995    -2.5%   harmonic
        4096         64         65    +1.6%   linear counting
        4096        700        725    +3.6%   harmonic
       20000      20000      15054   -24.7%   harmonic
          64         64         65    +1.6%   linear counting
           8          8          8    +0.0%   linear counting

Worst 24.7% = **1.90 sigma**, inside the 3.5-sigma band the generator asserts.
The linear-counting rows are the ones that matter: without the small-range
correction, 8 distinct elements in 64 registers estimate at ~48, and the
harmonic formula is simply the wrong estimator down there.

**CountMin** — 4 rows of 16, 64 cells. The estimate is **never below** the
truth (asserted for every key the fixture names) and above it by at most
`e/w = 0.170` of the total mass:

    keys   total mass   overcount min   max   bound
     256         4095             123   299     695
    1024         8191             407   584    1391

Worst 0.073 of total mass against a 0.170 bound. 1024 keys into 16 columns is
far past where CountMin is useful — it is in the fixture to show the bound
holding where the sketch is badly undersized, not to flatter it.

**MinHash** — 64 slots. Standard error `1/sqrt(64)` = **12.5%**.

    true J   matches    estimate     error
    0.3333     19/64      0.2969   -0.0365
    1.0000     64/64      1.0000   +0.0000
    0.0000      0/64      0.0000   +0.0000
    0.3333     22/64      0.3438   +0.0104
    0.6000     35/64      0.5469   -0.0531
    0.3333     18/64      0.2812   -0.0521

Worst 0.053 absolute. Identical sets give 64/64 and disjoint sets give 0/64 —
both exact, both pinned, neither a coincidence: min-hashing is exact at the two
ends and only approximate in between.

**DDSketch** — 128 buckets, `gamma = 2^(1/4)`, guaranteed relative error
`alpha = (gamma-1)/(gamma+1)` = **8.6427%**. 128 buckets is 32 octaves: values
1 .. 2^31.75 = 3,611,622,602, everything above clamping into bucket 127. The
quantile rows do not assert a tolerance at all — the returned bucket is
*exactly* `ddidx(sorted(xs)[rank])` — and the 8.64% is asserted separately,
between each bucket's own representative `2*gamma^i/(gamma+1)` and the true
value at that rank.

## Deliberate ceilings

- **No large-range HLL correction.** It is `-2^32 * ln(1 - E/2^32)` and only
  moves the answer past E = 2^32/30 ≈ 143,000,000, which a 64-register sketch
  cannot resolve to better than a factor anyway. Marked `ponytail:` in the file.
- **`alpha_m` is 0.7213 flat past 64 registers**, instead of
  `0.7213/(1 + 1.079/m)`. That correction is 0.84% at m = 128 and 0.1% at
  m = 1024, against a standard error of 9.2% and 3.3%. Computing it needs
  `m * 2^32 / (m + 1.079)`, whose numerator does not fit a U32.
- **A register past `r = K` stops halving.** The contribution is floored at 1,
  so the estimate saturates at `alpha * m * 2^K` — 47 million for 64 registers,
  a hundred times past where 64 registers say anything. Without the floor a
  sketch whose every register passed K would divide by zero. A ceiling that
  replaces a crash.
- **Linear counting is valid to 8192 registers**, where `m * ln(m/v) * 2^15`
  stops fitting a U32.
- **CountMin's row count is fixed at 4**, width `cells/4`. A row count in the
  fingerprint would need a second config word to stay checkable, to buy a knob
  whose useful values are 3..5.
- **DDSketch records 0 in bucket 0**, beside the values at or below 1, rather
  than refusing it or carrying a separate zero count. A relative error is a
  statement about a positive value; zero has none, and the fixture pins the
  behaviour explicitly (`dz()`) rather than leaving it to be discovered.
- **`dd.quantile`'s rank is `qp * (n-1) / 1000`, a U32 product** — it wraps past
  about 4,290,000 recorded values. Marked `ponytail:` in the file.
- **Murmur3's fmix32 rather than reusing `power/rng.bend`'s Threefry-20.**
  Rule 7, and this one went against reuse: Threefry-20 is twenty rounds where
  fmix32 is five native rows, and it is paid *per element on the streaming
  path*, which is the one place in this library where a constant factor is the
  whole cost. Reuse was taken where it was free — `Bit.ones`, bitset's SWAR
  popcount, is what `nlz` is built on.
- **No `Array` anywhere**, for the kind reason above, and — as it turned out —
  avoiding the computed-F64-drop defect by construction rather than by luck.

## Battery

power 6/0 for `sketch` (+ control) · repo 54/54 · caps ok · bench 2/2
checksums match C · 8/8 mutants caught.

An earlier run of the repo gate read 53/54, and the one failure was **not this
lane's**: `d_probe.bend`, a stray probe file at the repo root left by a
concurrent lane, which that lane has since removed. Every file this lane added
is covered by the lane-0 rules and passes.

    power/sketch.bend                     8,836 ttok  /  64,000
    tests/power/sketch.bend              12,299 ttok  /  16,000
    tests/power/sketch_gen.py            11,254 ttok  /  16,000
    tests/power/bench/sketch.bend           156 ttok  /  16,000
    tests/power/bench/sketch_par.bend       327 ttok  /  16,000
    tests/power/bench/twin_sketch.c         448 ttok  /  16,000
    tests/power/bench/twin_sketch_par.c     483 ttok  /  16,000

No cap raised, no `gates/repo.ts` rule added, no `comp.ts` row, no `base.bend`
change, no new effect. **No shared file was edited** — in particular not
`tests/power/bench/twins.c` and not `tests/power/bench/run.sh`. `sketch_par`
needs to be compared against the sequential answer, and rather than add a
`case` line to the shared `run.sh` (where concurrent lanes would conflict) it
ships its own `twin_sketch_par.c`, which is `twin_sketch.c` with a different
header comment. One duplicated C file against one contended edit.

## Next

- **`power/cdc.bend` (lane 9) and `power/bm25.bend`** both hash a stream and
  both would take a `Fp`-carrying summary for free; a `Sketch` beside a chunker
  gives "how many distinct chunks" at 256 bytes.
- **`power/budget.bend` (lane 20)** is the natural bound on a sketch over a
  hostile stream: `Work` per update, and `merge` is the one operation that
  costs nothing to allow.
- **A t-digest** would give accurate tail quantiles where DDSketch gives
  uniform relative error, but its merge is not exact-associative — a fork tree
  and a sequential pass give *different* centroids. It does not belong in this
  lane, and saying why is more useful than shipping it: this lane's entire
  contract is that the fork is unobservable.
- **The Bank's 17× against C** is the one number here worth attacking. A
  four-ary or eight-ary bank would cut the descent from six rebuilt nodes to
  two or three at the same cell count. That is a change to `bank.fuse` and
  `bank.new` only — `cell`, `merge`, every law and the whole fixture are
  untouched by it, which is itself an argument for the shape.
