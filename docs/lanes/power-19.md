# power-19 — Proof-Carrying Results: an answer nobody has to trust (2026-09-20)

Lane 19. One file shipped, `power/proof.bend`, and it is the only file in the
library that does not compute anything. It reads what another computation
claimed and says yes or no.

The premise is old and the reason it belongs in this library is new. A search
that is fast is a search that is complicated — forked, vectorised, tiled,
short-circuited — and complicated is where wrong answers live. The usual
defence is to audit the search. This lane's defence is that you never audit the
search at all: it hands back a **witness** with its answer, and a small checker
reads the witness. The optimiser may then be rewritten, moved to a GPU or
replaced by a rival, and nothing downstream has to be re-examined, because the
thing downstream reads is the certificate.

That only works if the checker is worth trusting, which puts two demands on it
that the rest of this library does not face:

1. **It must be independently written.** A checker that calls the sorter to
   check the sorter proves nothing. Nothing in `power/proof.bend` imports
   anything but `Base` and `Vec`.
2. **It must be short enough to read in one sitting.** That is the deliverable.
   Four checkers, 584 lines with their comments, and every loop in the file is
   flat.

## What shipped

### `power/proof.bend` — four checkers, each a pair of opposed tests

The design of every one of them is the same, and it is the part worth stating
once: **no single test is ever enough, and the two that suffice pull in
opposite directions.**

| checker | the witness | the tests | what each half alone accepts |
|---|---|---|---|
| `sort(a, o, p, n, limit)` | the output `o` and the permutation `p` | `p` is a bijection over `0..n-1`; `o` non-decreasing; `o[i] == a[p[i]]` | sortedness alone: a sorted array of the wrong elements. the permutation alone: the right elements unsorted. the value test alone: anything monotone. |
| `topk(sc, ix, n, k, thr, limit)` | the `k` chosen indices and the (k+1)-th best score | chosen are distinct, in range, non-increasing, and at or above `thr`; **no unchosen element passes `thr`** | the chosen pass alone: a liar lowers `thr` and picks anything. the unchosen pass alone: a liar raises `thr` and picks nothing. |
| `path(eu, ev, ew, d, n, mm, src, limit)` | the distance labels `d` | `d[src] == 0`; feasibility `d[v] <= d[u] + w(u,v)` on every edge; tightness — every reachable label achieved by some incoming edge | feasibility alone: labels too small. tightness alone: labels too large. |
| `assign(c, u, w, mt, nr, nc, limit)` | the matching `mt` and the dual prices `u`, `w` | `mt` is an injection into the columns; `u[i] <= c[i][j] + w[j]` at every cell; equality at every matched cell; `w[j] == 0` on a column nobody holds | feasibility alone: prices too weak to prove anything. slackness alone: prices that are not feasible, so prove nothing. |

`Bad` names the seven ways a witness can be refused — `Fuel Range Dup Order
Value Over Slack` — and a rejection carries which one, first failure wins.
`Over` and `Slack` are deliberately a pair: they are the two halves of every
duality argument in the file, and naming them apart is what lets a rejection say
*which* half broke rather than "no".

Every entry point returns its input `Vec`s beside the verdict. `Vec` holds an
`Array`, so it is kind `Type` and cannot sit inside a `Result` — the same wall
lanes 5 and 6 hit, with the same resolution: hand the owner back beside the
answer.

## Rule 7 — `power/assign.bend` already ships an `Assign.certify`, and this lane did not use it

The brief warned that lane 10 might not exist. It does, and it already has a
self-check. Two checkers for one problem is exactly the conflict Rule 7 is
about, so: **both stay, and they are not the same thing.**

`Assign.certify(s)` takes the solver's own `Sol` record, returns one bare
`Bool`, carries no budget, and lives in the same file as the solver. It is a
*self-test*: it answers "did my own run go wrong", which is worth having and is
not what this lane is for.

`Proof.assign` takes four flat `Vec`s — the form a certificate travels in —
names the property that failed, refuses a hostile size before reading a cell,
and shares no line of code with any solver. It answers "should I believe this
thing someone sent me".

The overlap is real and it is the point: the fixture makes `Proof.assign` read
`Assign.solve`'s own output. **The lane-10 integration is live, not stubbed.**
Five rows of `tests/power/proof.bend` call `cert(Assign.solve(...))` through a
twelve-line adapter that unpacks `Sol`'s prices with `Assign.price_row`,
`Assign.price_col` and `Assign.at`. Four of those rows are 4×4, 5×5, 2×2 and a
3×5 rectangle and all certify; the fifth is a 3×2, which cannot be matched at
all, and `Proof.assign` rejects the solver's answer with `no range` because a
row that could not be matched carries no column. That row is the one that would
break first if lane 10's `Sol` layout moved, which is why it is pinned.

If a later lane wants one checker instead of two, the move is to delete
`Assign.certify` and have the solver call `Proof.assign` — not the reverse. A
certificate checker that imports the solver stops being a certificate checker.

## Integers, and why that is a soundness decision before it is a compiler one

Every cost, weight, price and distance label in this file is a `U32`. The brief
asked for it and it is also the right call twice over.

A feasibility test in floating point needs an epsilon, and **an epsilon is a
hole in the proof** — it is exactly the slack a wrong answer hides in. "Within
1e-9 of feasible" is not feasible, and a checker that accepts it has traded the
property it was written to guarantee for a tolerance nobody downstream can see.
Complementary slackness and edge feasibility in exact integers have no such
hole: `u[i] <= c[i][j] + w[j]` is true or it is false.

Independently, the compiled C backend miscompiles an `Array<F64>` written from a
recursive loop (recorded in `docs/omen/f64-drop-c-backend.md`), which would
have forced the same choice anyway. Two reasons pointing the same way, and only
one of them is about this compiler.

## The budget, and the guard that must not wrap

A witness is **untrusted input**, and the sizes are part of the witness. A
checker that believes `n` can be made to run for 2^32 steps by a witness that
costs nothing to write. So every entry point takes `limit` last and refuses in
O(1), before a single loop starts, with `Fail{Fuel{}}` and nothing read.

The guard itself is where this could have gone wrong, and the rule is:

> **Sizes are never added, and never multiplied.**

`take(m, n)` subtracts one size at a time; `take_mul(m, a, b)` decides whether
`a * b` fits by asking `b <= left / a`, with a zero guard on `a`, because
`U32.div` answers 0 for a zero divisor. A guard written the obvious way —
`if a * b <= left` — passes a 65,536 × 65,536 witness against a limit of 1,000,
because `65536 * 65536 == 0 (mod 2^32)`. That is a checker that can be made to
scan 4 billion cells by a witness twelve bytes long. The fixture pins the
rejection: `assign(..., 65536, 65536, 1000)` → `no fuel`.

The four budgets are `n` (sort), `k + n` (topk), `mm + n` (path) and
`nr*nc + nr + nc` (assign) — the work each checker actually does, so a valid
witness against an honest limit always has budget left over, and a row prints
how much. Pinning the *remainder* rather than a bare "ok" makes the fixture
sensitive to a checker that quietly skips a pass.

## Verified

`bash tests/power/run.sh proof` — 78 rows, `PASS: 6, FAIL: 0`. Six lanes:
oracle, check, interpret, js, c, c-1thread.

**`tests/power/proof_gen.py` is a set-valued reference**, and that is the one
design decision in the generator worth recording. Each of the four references
returns the **set** of properties a witness violates — one Python comprehension
per property, no traversal order anywhere — and a case is only emitted when that
set is exactly the single fault it was built to have:

```python
def one(got, expect):
    """The fault set a case is allowed to have: empty, or exactly one name."""
    ...
    assert got == (set() if expect is None else {expect}), (got, expect)
```

The reason is that `Proof.*` keeps the **first** failure, so a corruption that
breaks two properties at once pins a reason that depends on which pass runs
first. Such a row would be a fixture of the traversal order rather than of the
checker, and it would silently re-pin itself if a pass were ever reordered. The
generator refuses to print one, at authoring time, rather than let it become a
flaky lane later. Three corruptions were rejected by that assertion and had to
be rebuilt:

- raising a row price `u[i]` breaks feasibility **and** its own matched cell's
  tightness. Replaced by lowering an *unmatched* cost cell, which breaks
  feasibility only.
- a "forbidden cell priced too high" row was two faults for the same reason.
  Replaced by a row whose *matched* cell is the forbidden one, which is a lone
  `slack`.
- a duplicate index in a sort permutation is only a lone `dup` when the array
  has **ties** — otherwise it drags `value` along with it. The generator searches
  for the first `(i, j)` whose repeat yields exactly `{"dup"}`, and a tie-free
  array contributes no `dup` case at all.

The valid witnesses are built by CPython and not by this library: `sorted()` for
the sort, a `heapq` Dijkstra for the labels, and — for the assignment — a
**dual-first construction** checked against an exhaustive-permutation brute
force, because a certificate is easier to build than to find:

```python
c.append(u[i] - w[j] + (0 if mt[i] == j else slack[i][j]))
...
assert brute(c, nr, nc) == sum(c[i * nc + mt[i]] for i in range(nr))
```

78 rows: **51 rejections, 27 acceptances**, which is the ratio the brief asked
for and the ratio the subject deserves. A generator-side tally asserts at least
four cases for each of the seven `Bad` tags and that rejections outnumber
acceptances, so the balance cannot drift as rows are edited.

**Mutants** — five, one per load-bearing pass. Each is a single-string deletion
from `power/proof.bend`; each still type-checks, each passes the oracle and the
checker lanes, and each fails all four executing lanes (`PASS: 2, FAIL: 4`):

| mutant | what it breaks | what the fixture caught |
|---|---|---|
| `sort.clm` discards `claim`'s verdict | the bijection test | 7 rows. Two `no dup` become **`ok`** — a non-permutation accepted outright — and every `no range` falls through to `no value` instead. |
| `sort.cmp` drops the `Value` test | `o[i] == a[p[i]]` | 5 rows `no value` → `ok`: an output element the input never held. |
| `top.on` drops `top.all` | the unchosen pass | 2 rows `no over` → `ok`: a chosen set that left a better element behind. This is the test a buggy heap breaks. |
| `path.on` drops `path.all` | tightness | 5 rows `no slack` → `ok`: labels too large, feasible and worthless. |
| `asg.on` drops `asg.cols` | the free-column test | 1 row `no slack` → `ok`: a discount priced onto a column nobody holds, which is a dual bound the matching does not pay for. |

The first mutant is the instructive one. Deleting the bijection test does not
merely lose the `dup` rows: it *relabels* the range rows, because an
out-of-range permutation index still gets read and the value it reads disagrees.
A checker can fail in a way that still rejects, for the wrong reason, and a
fixture that only pinned pass/fail would have called that a pass. Pinning the
**reason** is what caught it.

## Measured (Ryzen 7 7700X, 8 cores / 16 threads, `--gpu off`, medians of three)

| bench | what it runs | C | bend 1T | bend 16T | 1T/C | 1T→16T |
|---|---|---:|---:|---:|---:|---:|
| `proof` | 128 certificates over 192×192, each checked 16 times: 2,048 checks, left fold | 0.02 | 0.09 | 0.09 | 4.0x | 1.0x |
| `proof_par` | the same 2,048, as a 2^7 tree, one certificate a leaf | 0.02 | 0.08 | **0.02** | 4.0x | **4.3x** |

Taken under `flock /tmp/bend-bench.lock` with four other lanes live, load-avg
5.46 falling to 4.73. A row is only timed after the C twin, `--threads 1` and
`--threads 16` all print the same checksum; `proof` and `proof_par` agree at
1417871453 and 1476526080.

### The headline: check against search

The bench next door, `assign`, **solves** problems of exactly this size and
shape. Both rows were taken back to back, under the same lock, on the same
machine, from the same hash stream:

| | per operation, bend 1T | per operation, C |
|---|---:|---:|
| `assign` — solve one 192×192 (0.35 s / 512) | 684 µs | 410 µs |
| `proof` — check one 192×192 certificate (0.09 s / 2,048) | **44 µs** | **9.8 µs** |
| | **15.6x cheaper** | **42x cheaper** |

The check figure is an **upper bound**, because the `proof` row also builds its
128 certificates and a build is the same O(nr·nc) order as a check: at most 128
check-equivalents on top of 2,048, so the true per-check cost is between 41 and
44 µs. Stated the other way and conservatively: **checking the answer costs
about a sixteenth of finding it**, and that is the entire argument for carrying
a witness.

The asymptotic gap is wider than the measured one — the check is O(nr·nc)
against the solve's O(nr²·nc), so the ratio should grow linearly in `nr` — but
only one size was measured, so that is an argument and not a number. The
constant favours the solver: an augmenting step touches few cells, a check
touches every one of the 36,864 through `Vec.at`.

The certificates in this bench are **built, not solved**. Pick the prices first
and the costs that fit under them second — `u[i]` a row price, `w[j]` a column
price, and a slack that is zero exactly on the matched cell — and the result is
dual-feasible and complementary-slack by algebra, in one O(nr·nc) pass. A bench
that solved for its own input would have been timing `assign.bend` again.

**One instance in four is deliberately broken**, one property each, and the
verdict is folded into the checksum: `Done` contributes the budget it did not
spend, `Fail` contributes `0xF0000000 + tag`. A checker that always answered
`Ok` would match on three instances in four and miss on the fourth. That is the
only way a bench can notice that a proof stopped being a proof.

`proof_par` gets 4.3x on 16 threads, which is the weakest parallel number in
this wave and is honest about why: a leaf is one 192×192 matrix, the build
dominates the leaf, and `Vec` holds an `Array` so no two leaves can share one.
Unlike `assign_par`, where a leaf's cost swings with how long its augmenting
paths turn out to be, **every leaf here costs exactly the same** — a check walks
all `nr·nc` cells whatever the verdict. That is not an accident of the bench: a
checker whose running time told you something about its answer would be a
checker with a timing side channel, and it is the same reason the budget is
taken up front rather than decremented as it goes.

## Written for Bend

- **Both branches of `Bool.pick` are consumed**, because it is a function call
  and not a conditional. A binder read in both needs `+`. `cor.u` in the bench
  wants `(u, +u0) = q` for exactly this.
- **An imported ADT's constructors need qualifying in a pattern.**
  `case Proof.Fuel{}` checks; `case Fuel{}` is "a declared constructor
  (unknown: Fuel)". The bench's `bad()` maps all seven tags and so hits it
  seven times.
- **No checker exits early on its first failure.** The budget already bounds the
  work, so an early exit buys nothing a caller can observe, and a branch per
  cell costs more than the exit saves. `keep` folds the verdict and the first
  failure wins.
- **`claim` is a pigeonhole, not an inverse.** `n` successful claims over a
  range of `n` *is* a bijection, so no checker here builds the inverse
  permutation to look for a hole in it. An out-of-range index is refused before
  the mark, so a hostile index cannot write into the claim vector.
- **`pv` starts at the identity of the comparison it guards** — 0 for the sort's
  non-decreasing test, `2^32-1` for topk's non-increasing one — so the first
  slot compares against a bound it cannot fail and the `i > 0` branch is not
  written at all.

## Deliberate ceilings

- **No negative costs and no negative labels.** `U32` throughout. The column
  prices ride non-negative as a discount, `v[j] = -w[j]`, which is
  `assign.bend`'s own convention, so no cell and no price is ever negated and
  four flat `Vec<U32>` hold the whole witness. A problem with genuinely signed
  costs shifts by a constant before it certifies.
- **`path` certifies distances, not paths.** The witness is the labels. A caller
  that wants the route wants a parent array too, and verifying *that* is a
  different tightness test (parent edges form a tree rooted at `src`). Labels are
  what a distance query returns, so labels are what this checks.
- **`topk` does not check that `thr` is the true (k+1)-th score**, only that it
  separates. It cannot be anything else: if a chosen element is at or above it
  and no unchosen one passes it, the chosen set *is* a valid top-k, which is the
  property, and pinning the exact tie-break would refuse correct answers.
- **No proof that the certificate is small.** A witness for the assignment is
  the matrix plus two price vectors, so the check is O(nr·nc) — same order as
  reading the problem. That is the good case. A certificate scheme for something
  whose witness is larger than its input is not in this file.
- **No `@unsafe` and no `?TODO` under `power/`.** Checked.

## Battery

Four commands, all run, all green:

| command | result |
|---|---|
| `bash tests/power/run.sh proof` | `Power PASS: 6, FAIL: 0` — oracle, check, interpret, js, c, c-1thread |
| `git add -N . && bun gates/repo.ts` | `PASS: 54 / 54` |
| `bash tests/caps.sh` | exit 0, 35 rows, none over cap |
| `flock /tmp/bend-bench.lock bash tests/power/bench/run.sh proof` | `proof` and `proof_par` both timed, so both matched their C twin on 1 and 16 threads |

Scope note: `bash tests/power/run.sh proof` is this lane's fixture only. The
whole `power` suite was not re-run, because four other lanes were editing their
own files throughout and a failure there would have said nothing about this one.

`power/proof.bend` 8,899 ttok against the 64,000 cap; the fixture 5,917 and its
generator 7,654 against 16,000; the two benches 2,312 / 2,221 and the two twins
1,705 / 100. **No cap moved and no `gates/repo.ts` row was needed** — every path
this lane adds already matches an existing allow rule
(`^power/[a-z0-9_]+\.bend$`, `^tests/power/...`, `^docs/omen/...`). No
`bend2/` file was touched: no `comp.ts` row, no `base.bend` change, no new
effect, and none was wanted.

## Next

The obvious consumer is a lane that produces witnesses rather than consuming
them — `power/select.bend` and `power/knn.bend` both return a chosen set and
could hand back the threshold that separates it for two more lines, at which
point `Proof.topk` audits them for free. The interesting one is harder: a
certificate for an *approximate* answer, where the witness proves a ratio rather
than optimality. Duality gives it for the assignment — any feasible `u`, `w` is
a lower bound whether or not it is tight — but it needs a checker that returns a
number instead of a verdict, which is a different signature and a different
lane.
