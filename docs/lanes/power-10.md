# power-10 — Assign: the cheapest matching, and the proof that it is cheapest (2026-09-20)

Lane 10. One file, `power/assign.bend`: Jonker-Volgenant by shortest augmenting
path over a U32 cost matrix, O(nr²·nc), the same algorithm SciPy's
`linear_sum_assignment` runs — and SciPy is the oracle.

The lane is not really about the matching. It is about the **second** thing the
algorithm computes and almost every implementation throws away: the dual prices.
They are a certificate that no matching is cheaper, they cost nothing extra to
keep, and checking them is one pass over the matrix against a re-solve. Lane 19
(proof-carrying results) is going to eat this contract, so this lane's job was to
make the prices as trustworthy as the cost.

## What shipped

### `power/assign.bend`

```
solve(c, nr, nc)               -> Vec.Vec & Sol      the matching and its prices
solve_opt(c, nr, nc, gate)     -> Vec.Vec & Sol      same, rows may opt out at `gate`
pad(c, nr, nc, gate)           -> Vec.Vec            the padding solve_opt runs on
certify(c, s)                  -> Ck                 the O(nr·nc) proof check
cost(s)  solved(s)  at(s, i)                         the answer
price_row(s, i)  price_col(s, j)  price(s)           the prices
big()  inf()  none()  le(a, b)                       the number line
type Sol{nr, nc, ok, sum, u, w, c4r}
type Ck{c, s, ok}
```

- **`solve`** grows the matching one row at a time. Each row is a Dijkstra over
  *reduced* costs from the rows already matched, and the shortest alternating
  path it finds is flipped into the matching. `Sol.ok` is false if some row could
  not be matched at all — a cost at or above `big()` is a forbidden pairing, and
  a row all of whose cells are forbidden has nowhere to go.
- **`solve_opt`** is the rectangular and the optional case: `nr` rows, `nc`
  columns, and a per-row opt-out priced at `gate`. It is `pad` plus `solve`, and
  `pad` is exposed because a caller that wants to see the square matrix the
  solver actually ran on should be able to.
- **`certify(c, s)`** re-derives nothing. It checks three things against the
  original matrix, in one pass:

  | pass | what it asserts |
  |---|---|
  | feasibility | `u[i] <= c[i][j] + w[j]` at **every** cell |
  | tightness | equality at every **assigned** cell |
  | zero price | `w[j] = 0` at every column left over |

  Those three are LP duality. Together they say `cost = sum(u) - sum(w)` is a
  lower bound that the matching attains, so the matching is optimal — and that
  argument does not depend on trusting a single line of the solver.

## Rule 7 — the duals are signed and the container is not

The row price is `>= 0` and the column price is `<= 0` at every step of this
algorithm. A `Vec` holds U32. Something had to give, and the three candidates
were: an offset bias, a sign-magnitude pair field, or store the column price
negated.

**Negated wins, and it is not close.** `w[j] = -v[j] >= 0`, every reduced cost is
read as `c[i][j] + w[j] - u[i]`, and the property that makes it safe is the one
being certified anyway: *dual feasibility is exactly the statement that this
subtraction does not go under zero.* The check that proves the answer is also the
check that proves the arithmetic. A bias would have needed its own invariant,
untested, to say the same thing.

Nothing signed is ever stored and no cell of the matrix is ever negated. The
price of that is one contract the caller owes:

> `big() = 2^31`. A cost at or above it is forbidden. Every finite cost, every
> price and every reduced cost must stay below it, which for costs under `C` over
> `nr` rows means **`nr · C < 2^31`**.

At the bench's own numbers — costs in 0..63 over 192 rows — that is 12,096
against 2,147,483,648, five orders of margin. Past the ceiling the arithmetic
wraps, and `certify` is the thing that says so: a wrapped reduced cost is an
infeasible dual, and the cert column goes to 0 rather than a wrong answer going
out silently.

## The contract lane 19 gets

`solve` hands back `u` and `w` beside the matching. A consumer that ships the
answer somewhere else ships the prices with it, and **the far end checks in
O(nr·nc) what cost O(nr²·nc) to produce.** For the bench's 192×192 that is 36,864
cell reads against 7 million — the whole reason proof-carrying is worth doing.
`price_row`, `price_col` and `price` are the accessors; `certify` is the reference
checker, written so lane 19 can port it rather than re-derive it.

## Verified

`bash tests/power/run.sh assign` — 136 rows, **PASS: 6, FAIL: 0** (oracle, check,
interpret, js, c, c-1thread).

`tests/power/assign_gen.py` does not trust one reference. Inside `guard()`, every
instance is solved **three** ways — brute force over `itertools.permutations`,
SciPy's `linear_sum_assignment`, and an independent e-maxx JV — and the generator
refuses to emit a fixture unless all three agree, unless JV's own prices certify,
and unless the duality gap equals the cost. Only brute force and SciPy ever reach
a printed number; the third solver exists to disagree.

**What the fixture pins, and what it deliberately does not.** Costs are dense
enough that several permutations reach the optimum, so which one a solver lands
on is its tie-break and not its answer. So:

- the **cost** on every row — always;
- the **permutation** only where brute force proves the optimum unique;
- the **duality gap**, `sum(u) - sum(w)` — which by strong duality is unique
  however the ties fell, and is therefore the safe way to pin the prices without
  over-specifying them.

`case_opt()` pads in CPython exactly as `pad` pads in Bend, so the oracle covers
`pad` and not only `solve`.

### The mutant grid, and the bug it found

Every mutant is scored **twice**: rows moved, and rows whose cert flipped 1 → 0.
Then each solver mutant is composed with each check-disabling mutant, to find
which of the three passes does the catching.

| mutant | all on | no feasibility | no tightness | no zero price |
|---|---|---|---|---|
| scan takes the last column, not the cheapest | 104 / 19 | 104 / **0** | 104 / 19 | 104 / 19 |
| the dual update pays the column, not the row it holds | 87 / 51 | 87 / 51 | 44 / **0** | 87 / 51 |
| the reduced cost forgets the row potential | 34 / 16 | 34 / 14 | 34 / 16 | 34 / 16 |
| the reduced cost forgets the column price | 19 / 11 | 15 / 7 | 19 / 10 | 19 / 11 |
| every column price starts at one, not at zero | 36 / 24 | 36 / 24 | 36 / 24 | 12 / **0** |
| the opt-out block is built in the other order | 8 / 0 | 8 / 0 | 8 / 0 | 8 / 0 |

Read the bold zeros: **each of the three passes is the unique catcher of exactly
one mutant.** Disable feasibility and the cheapest-column mutant stops being
caught by the certificate; disable tightness and the misapplied dual update stops;
disable the zero-price pass and the biased column price stops. No pass is
decoration.

The last row flips no cert **correctly**. Building the opt-out block in the other
order is a valid solve of a differently-padded matrix — every cost is the same and
every certificate is honest. Only the `perm` rows say anything, and they do.

**This grid found two real bugs.**

1. **`pad.dummy` built the opt-out block in reverse.** Row i's opt-out column came
   out at `nc + (nr-1-i)` instead of `nc + i`. A Bend fuel loop counts *down*, so
   the item being pushed at `1n++q` is `len-1-q` and not `q`; `pad.real` already
   knew that and `pad.dummy` did not. Caught by the `perm` rows — 8 rows, all in
   the `solve_opt` block.

2. **`certify` never ran the dual-feasibility pass.** It built the `Fa` seed and
   handed it straight to `ck.a`, so `fa.go` was dead code. This was found by
   staring at a number that could not be true: the cheapest-column mutant moved
   **104 rows and flipped 0 cert fields**. A certified matching is optimal, so a
   wrong cost with a valid certificate is impossible. Hand-checking
   `[[14,19],[32,26]]` — the mutant returns cost 51 with cert 1 — the LP argument
   gives `51 <= 40`, so no valid duals exist and the certificate had to be lying.
   After the fix the same mutant flips 19, and the fixture still matches
   byte-for-byte.

   The second bug is the lane's argument for itself. The cost oracle could never
   have found it: every printed cost was already right. Only asking *"does the
   certificate do work, or is the cert column along for the ride?"* found it.

### An honest negative result

A seventh mutant — **"certify starts from yes, not from what the solver
claimed"** — **survived.** `certify` seeds its answer with `Sol.ok`, and that seed
turns out to be redundant: the tightness pass already walks `c4r` and rejects any
row whose column is out of range, which is what `none()` is. The seed states
intent and costs nothing, so it stayed, but it is not load-bearing and this report
will not pretend it is. It was replaced in the grid by the zero-price mutant,
which the third pass uniquely catches.

## Measured (Ryzen 7 7700X, 8 cores / 16 threads, `--gpu off`, medians of three)

| bench | what it runs | C | bend 1T | bend 16T | 1T/C | 1T→16T |
|---|---|---:|---:|---:|---:|---:|
| `assign` | 512 independent 192×192 solves, left fold | 0.22 | 0.35 | 0.37 | **1.6x** | 1.0x |
| `assign_par` | the same 512, as a 2^9 tree, one solve a leaf | 0.28 | 0.35 | **0.06** | 1.3x | **5.7x** |

Taken with the machine at load-avg 5.44 (five other lanes building). A standalone
run on a quiet machine gives 0.347 → 0.055, **6.3x**.

**1.6x of `-O3` C is the number this lane is proudest of**, and it was checked
rather than assumed. Two ways: n³ scaling holds empirically, so nothing is
short-circuiting; and at 64 instances of 48×48 the Bend run and the independent C
twin both print **3089211635** — the same matchings, cell for cell, from two
implementations that share no code.

The checksum folds the **cost** and not the matching, for the reason stated above:
ties make the permutation a tie-break. `twin_assign.c` has to reproduce the cost
exactly, and does.

### The parallel finding: leaf granularity beats leaf count

`assign_par`'s first draft bundled eight instances into each of 2^6 leaves — the
obvious shape, fewer bigger leaves, less scheduling overhead. It ran **3.5x** on
sixteen threads. One solve a leaf, 2^9 leaves, runs **6.3x**.

The reason is specific to this algorithm and worth writing down:

> A Jonker-Volgenant solve's cost **swings with its data**. How long the
> augmenting paths turn out to be is a property of the matrix, not of its size. A
> leaf that bundles eight solves bundles their variance too, and the slowest leaf
> sets the clock. One solve a leaf hands that variance to the scheduler instead.

Before believing that I ruled out the alternatives: the thread curve saturates at
4, not 16 (so it is not bandwidth), and a build-only variant showed matrix
construction is 0.036 s of 0.374 s (so it is not allocation). For a
data-dependent algorithm, **make the leaf the smallest honest unit of work** —
the opposite of the advice for a uniform one.

There is nothing to fork *inside* one solve: it is a sequence of shortest-path
searches, each starting from the prices the last one left. The batch is the unit,
which is also the real workload — a tracker re-solves the whole assignment every
frame, and a parameter sweep is a batch of solves.

## Written for Bend

- **No tuple field access.** `r.1` does not exist, so every read of a returned
  pair is a helper-def hop: `(v, x) = r` at the head of a def is the idiom, and
  this file has a dozen of them. It is the single largest source of line count
  here.
- **`+` is rejected on a constructor pattern's last field**, which chose `Sol`'s
  field order. `c4r` — the one Vec that never needs a second use — goes last, so
  `nr`, `nc` and `ok` can all carry their markers.
- **A binder that collides with a top-level `def` is rejected in a `case`
  pattern**, which is why several state-record fields are named for what they
  hold rather than for the def that computes them.
- **No mutual recursion outside Base.** Every loop here is one self-recursive def
  over a fuel `Nat`, with all branch work in non-recursive helpers that answer
  with a state record — `Sc`, `Du`, `St`, `Path`, `Aug`, `Rows`, `Out`, `Pad`,
  `Fe`, `Fa`, `Tg`, `Zp` are all that shape and none of them is an abstraction.
- **`U32.shln` / `U32.shrn` take a `Nat` shift.** `U32.shln(b, 16n)`, not `16`.
- **The fuel loop counts down.** Stated twice because it cost a bug: at `1n++q`
  the item being handled is `len-1-q`. Writing `q` reverses the output, and a
  reversed output can still be a correct answer to a different question, which is
  the worst kind.
- **The residual form of the algorithm was chosen for the compiled lanes.** Each
  column keeps its distance *relative to the frontier*, so the whole dual update
  is one `+delta` on used columns and `-delta` on unused ones — one add a column,
  instead of a subtraction against a stored path length. The inner scan hoists the
  row price out of the loop and reads four flat cells a column.

## Deliberate ceilings

- **U32 costs only.** No float matrix. That is not just the `Array<F64>` question
  — it is that exact integer duality is what makes `certify` a *proof* rather
  than a tolerance check. A float version would need an epsilon, and an epsilon in
  a certificate is a negotiation.
- **Dense matrices only.** `c` is `nr · nc` cells in one Vec. A sparse
  cost matrix (most pairs forbidden) would want an adjacency form and a
  sparse Dijkstra; that is a different file, not a flag on this one.
- **No incremental re-solve.** A tracker that re-solves every frame throws the
  previous prices away. Warm-starting from the last frame's duals is the obvious
  win and is exactly the shape lane 16 (delta-native computation) is for.
- **`big()` is a contract, not a check.** The solver does not verify
  `nr · C < 2^31` on entry; it costs a pass over the matrix to do so, and
  `certify` catches the violation after the fact anyway.

## Battery

`bash tests/power/run.sh assign` PASS 6 / FAIL 0 · `bun gates/repo.ts` 54/54 ·
`bash tests/caps.sh` ok · `flock /tmp/bend-bench.lock bash
tests/power/bench/run.sh assign` — both checksums match C at 1T and 16T ·
mutation grid exits 0 and restores `power/assign.bend` clean.

`power/assign.bend` 10,303 ttok against the 64,000 cap; `tests/power/assign.bend`
11,097 and `assign_gen.py` 4,797 against 16,000; `bench/assign.bend` 773,
`bench/assign_par.bend` 948, `twin_assign.c` 1,480, `twin_assign_par.c` 95.
**No cap moved.** No `comp.ts` row, no `base.bend` change, no new effect, no new
gate rule.

## Next

Lane 19, proof-carrying results, which consumes this lane's dual contract
directly: a result that travels with the evidence for itself, checked in less
time than it took to produce. `certify` is the worked example and the reference
implementation.
