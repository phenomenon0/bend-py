# power-2 — Heap / TopK (Beam) (2026-09-20)

Lane 4 of the plan, on `power/vec.bend`.

## What shipped

- `power/heap.bend` — binary min-heap of `Entry{key, val}`, ordered by key then
  val. `new len push pop peek replace drain` (`replace` = heapq.heapreplace, one
  sift; `drain` = every entry, greatest first). Oracle: CPython `heapq` over
  tuples, a 190-op seeded script, keys from a range of 12 so ties dominate.
- `power/topk.bend` — `TopK{k, heap}`: `new offer offer_all drain merge`.
  Oracle: `sorted(stream, reverse=True)[:K]`, K ∈ {0, 1, 5, 16, 50 > N, 3 of an
  empty stream}; two merge rows hold "the K of two halves, merged, are the K of
  the whole".
- **Beam is not a type.** A beam frontier is `offer` every expansion, `drain`.
  A `Beam` wrapper lands if a caller needs more than that.

## Why (key, val) and not key alone

Ties are where a heap is non-deterministic. Ordering by the pair makes the
result a function of the *set* offered, not of arrival order — which is what
makes `merge` exact and what lets a forked search give one answer on any
schedule. Give `val` an insertion index or an id. The mutant whose `less`
ignores `val` fails all four run lanes of both fixtures.

## Written for Bend

- one Vec, entry i in cells 2i / 2i+1: a sift stays in one flat block
- both sifts carry the moving entry and write each level once (hole, not swap)
- pop and replace do not shrink the Vec; push truncates to 2n first, so the
  length stays the truth and no pop pays for a truncate
- a losing `TopK.offer` is one peek and one compare, no write

## Three checker rules met here (they bind every later lane)

1. **Outside Base there is no mutual recursion.** A forward `law` is "an
   unfilled law" unless Base declared it (bend.ts infer-ref, `tld.b`). A loop
   with an early exit is therefore *one* self-recursive def over a small state
   type: non-recursive `look` defs answer `Done{v}` / `More{v, j}`, and the loop
   matches that. `Sift` in heap.bend is the pattern.
2. `(a, b, +c) = r` — a `+` on the **last** field of a nested pair pattern fails
   ("cannot infer `_ => U32`"); `+` on a middle field is fine. Twice-used last
   fields go through a `+` parameter of one more def (`up.lt`, `down.lt`).
   Looks like a bend.ts quirk, not a rule; not ours to edit — flagged.
3. `U32 & U32` is kind `Type`; `Maybe<&2, …>` / `List<&2, …>` want `Data`. Hence
   `Entry`. An imported constructor is written `Heap.Entry{…}`, in patterns too.

## Measured (Ryzen 7 7700X, `--gpu off --threads 1`, 3 runs, identical)

| | wall |
|---|---:|
| push 1,000,000 Threefry keys, drain all | 0.14 s |
| `TopK(100)` over 100,000,000 Threefry keys | 0.58 s (5.8 ns / offer, draw included) |

## Deliberate ceilings

- keys are U32. An F32 score enters through an order-preserving bit map; that
  lands with the first float consumer (KNN / BM25), with its oracle.
- `ArgTopK` is this TopK: `val` is the provenance.

## Battery

power 36/0 (+ control) · repo 54/54 · caps ok (nothing in `bend2/` touched).

## Next

Scan / Segmented Scan / Compaction — written over an index loop first (power-1's
finding), the fork measured before it is kept.
