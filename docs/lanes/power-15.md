# power-15 — Text identity: normalize hard, cite exactly (2026-09-20)

Lane 15 of the plan, wave 3, and the largest file in `power/`. The lane is not
"a normalizer" and not "a grapheme segmenter"; both of those already exist in
every language's standard library. The lane is the thing those libraries
throw away.

Normalization is not injective. `e` + U+0301 and U+00E9 are the same three
normalized bytes, and `ﬁ` folds to two. Once the pass has run, the offsets of
the original are gone — not hidden, *gone*, because two different inputs became
one output and no function can undo that. So a system that normalizes for
search and then wants to cite, highlight or edit the original has two
unpleasant options: normalize and lose the citation, or don't normalize and
lose the match. This lane takes the third: the offsets come out of the pass
that destroys them, or they do not exist.

    for every normalized offset o, with (s, e) = back(o),
    norm(original[s..e]) is exactly the normalized bytes of that segment

That law is the lane. A normalizer that loses the map is not this primitive,
and the fixture pins the law as a row on every fixture string, both forms, both
directions.

## What shipped

`power/text.bend`, over `power/bytes.bend` and `power/vec.bend`.

**UTF-8, with offsets.**

- `size(cp)`, `emit(b, cp)` — encode, all of U+0000..U+10FFFF.
- `decode(b, i) -> b & (cp, width)` — the code point at a byte offset and how
  far to step. Offsets are the interface; there is no "iterator" object.
- `valid(b) -> b & Bool` — well-formedness, including overlongs, surrogates
  and truncated tails.
- `cps(b) -> b & String` — the decoded code points, for fixtures.

**Grapheme clusters, UAX #29 extended.**

- `gcb(cp)` — the break class: `0 Other  1 CR  2 LF  3 Control  4 Extend
  5 ZWJ  6 Regional_Indicator  7 Prepend  8 SpacingMark  9 L  10 V  11 T
  12 LV  13 LVT  14 Extended_Pictographic`.
- `brk(p, k, raw, fl)` — GB3 through GB13 in order, over the previous class,
  the current class and three carried bits.
- `flag(raw, fl)` — the three bits: a ZWJ closing a pictographic run, a live
  pictographic run, an odd count of regional indicators since the last break.
- `graphemes(b) -> b & Vec` — every cluster start, with the buffer length as a
  closing sentinel so the caller gets ranges and not just points.

**Normalization, and the map.**

- `type Form is Data: Nfd{} | Nfc{} | Fold{}`.
- `type Norm is Type: Norm{out: Bytes, src: Vec, dst: Vec}` — the normalized
  bytes and the *same list of segments in two coordinate systems*.
- `norm(b, f) -> Norm` — one pass.
- `back(m, o) -> m & (s, e)` — a normalized offset to the original byte range
  it came from: a binary search of `dst`, one read of `src`.
- `fwd(m, o) -> m & (s, e)` — the same two steps the other way.
- `type Span is Data: Span{doc, rev, start, end}` and `span(doc, rev, (s, e))`
  — a citation carries the revision it was taken against, because a byte range
  without one is a range that will eventually point at the wrong bytes.
- `nlen`, `nsegs`, `nslice`, `ncps`, `slice` — readers.
- `ccc`, `lccc`, `is_start`, `fold`, `comp`, `order`, `compose` — the pieces,
  exported because the fixture pins them individually.

Every reader of a `Norm` hands the `Norm` back (`back(m, o) -> Norm & ...`).
`Norm` contains two `Vec`s and a `Bytes`, so its kind is `Type`: affine,
single-owner. This is the same fact power-20 named from the other side — a
`Budget` is kind `Data` and rides inside a `Result`; a `Norm` cannot, and every
signature in the back half of this file is shaped by that.

## The coverage ceiling, stated exactly

The brief asked for a correct, honestly-scoped normalizer over a broad one that
could not be verified. This is the scope, quoted from the module header, and it
is the claim the fixture is restricted to:

    decode / encode / valid / size    all of U+0000..U+10FFFF

    graphemes                         exact for U+0000..U+02FF, U+0300..U+036F,
                                      the Prepend code points of Arabic and
                                      Malayalam, Devanagari U+0900..U+097F,
                                      Hangul U+1100..U+11FF and U+AC00..U+D7A3,
                                      U+1E00..U+1EFF, U+200B..U+200D,
                                      U+2028..U+2029, U+203C, U+2049,
                                      U+2600..U+27BF, U+2B00..U+2BFF,
                                      U+FE00..U+FE0F, U+FEFF and the emoji and
                                      regional-indicator blocks of plane 1.
                                      Every other code point is classed Other,
                                      which is right for letters and wrong for
                                      a combining mark outside U+0300..U+036F:
                                      Hebrew, Thai and the other Indic scripts
                                      would split a cluster that should hold.
                                      GB9c, the Indic conjunct rule, is out of
                                      scope in every script.

    norm (Nfd, Nfc, Fold)             U+0000..U+036F, U+0385, U+1E00..U+1EFF,
                                      U+1FC1, U+1FED, U+2260, U+226E..U+226F,
                                      Hangul U+1100..U+1112, U+1161..U+1175,
                                      U+11A8..U+11C2 and U+AC00..U+D7A3.

54 derived ranges for the break classes; 11,172 Hangul syllables folded into
one LV row because LV and LVT differ by arithmetic, not by range.

**The normalization set is closed under canonical decomposition and canonical
composition, and that is what makes it a coverage claim rather than a range.**
No input drawn from it can decompose or compose to something outside it, so for
any string over that alphabet the answer either matches Unicode exactly or the
table is wrong — there is no third outcome where the answer is "right up to the
edge of what I implemented". Anything outside passes through unchanged, which
is the correct behaviour for the 99% of code points that are already normal
and wrong only for the ones that are not. `tests/power/text_gen.py` refuses to
write a normalizing row containing a code point it has not first proven inside
the ceiling or provably inert (`inert(cp)`: NFD and NFC fix it, `casefold` fixes
it, combining class 0, no decomposition mapping).

`Fold` is **simple** case folding. The ten code points inside coverage whose
full fold is longer than one code point — U+00DF ß, U+0130 İ, U+0149, U+01F0,
U+1E96..U+1E9A, U+1E9E — are left alone, and `MULTI` in the generator asserts
none of them reaches a Fold row. Half-implementing them would have made `fold`
a one-to-many map and the offset map a different object; see the ceilings.

## The map is per segment, not per code point

The design decision that makes the law hold by construction rather than by
luck. A **segment** is a starter-led run: the boundary sits in front of every
code point that nothing before it can compose with. Inside a segment the
normalizer reorders by combining class and composes freely; across a boundary
it cannot do either. So the map has one entry per segment, and a per-code-point
map would be a lie — after `order` runs there is no code point in the output
that corresponds to a specific code point of the input.

This is also why `is_start` is not `lccc(cp) == 0`:

    def is_start(cp):
        if VB <= cp < VB + VN:  return False   # conjoining V jamo
        if TB <  cp < TB + TN:  return False   # conjoining T jamo
        return lccc(cp) == 0

A conjoining V or T jamo has combining class zero and still joins leftward
under Hangul's algorithmic composition. Taking the textbook rule would put a
segment boundary in the middle of every decomposed Hangul syllable and the law
would fail on exactly the strings the lane exists for. The generator has the
same two holes, derived from `unicodedata` independently, and the fixture has
Hangul rows in three forms.

## Rule 7: three places where two plausible rules disagreed

**GB9c is out of scope in every script, not in some.** UAX #29's Indic conjunct
rule needs `InCB` property data that the derived ranges here do not carry.
Implementing it for Devanagari (whose SpacingMark and Extend ranges *are*
carried) and not for the rest would make the coverage claim conditional on
script, which is the one thing the ceiling is for. It is off everywhere, and
the header says so in those words.

**Outside coverage is `Other`, not a guess.** The alternative was to class all
of U+0483..U+0489, U+0591..U+05BD, U+0610..U+061A and friends as Extend by
block, which would be right most of the time. "Right most of the time" is not
a coverage claim you can pin, and a fixture cannot distinguish it from correct
without the real property data. Classing them Other is *wrong in a stated way*
— Hebrew and Thai combining marks split a cluster that should hold — which a
caller can route around. The header names the failure; the tables do not
pretend.

**Simple folding, not full.** `str.casefold` is full folding, so the oracle had
to be constrained rather than the implementation extended. The choice was
between a `fold` that returns one code point and an honest exclusion list, or a
`fold` that returns a list and drags one-to-many through the offset map, the
segment buffer and every signature downstream. The first is a ten-code-point
hole; the second is a different primitive. Taken the first, listed the ten.

## Reuse

`demos/python/unicode.bend` — read first, as the brief asked. It holds
`Ranges`/`member`: a balanced BST of disjoint scalar ranges answering `Bool`,
generated from a pinned CPython oracle with no host dependency. **The shape was
reused and the data could not be** — that file carries Python's `\w` and XID
sets, which share no code point classification with GCB, ccc, or canonical
decomposition. `Tab`/`look` here is the same tree with the same `choose`
branch, returning a class `U32` instead of a `Bool`, and all five tables
(`gtab`, `ctab`, `dtab`, `ftab`, `ptab`) are that one shape. `demos/python/unicode.bend`
was not edited.

`power/bytes.bend` had no UTF-8 — checked first, as the brief asked. It is byte
storage: `new`, `push`, `at`, `len`, `from_list`. `decode`/`emit` are new here
and belong here, not there: `Bytes` should not know about code points.

## Verified

`tests/power/text.bend` — **257 rows**, generated by
`python3 tests/power/text_gen.py > tests/power/text.bend`, on six lanes:
oracle, check, interpret, js, c, c-1thread.

    Power PASS: 6, FAIL: 0

Rows by section: `cp` 14 (decode), `bv` 7 (encode), `vd` 21 (validity, well-
formed and every class of malformed), `gv` 41 (grapheme boundaries), `nc` 76
(normalized output, 25 strings x 3 forms + empty), `dims` 7 (output length and
segment count), `rt` 87 (the law), `sp` 4 (`Span`).

**Oracle independence.** Nothing in `text_gen.py` is a second copy of the Bend
code:

    normalization   unicodedata.normalize, verbatim, on the whole string
    case folding    str.casefold, verbatim
    UTF-8           str.encode / bytes.decode -- the decode is also the oracle
                    for `valid`: a byte string is well-formed exactly when
                    CPython decodes it
    graphemes       regex's \X when importable, which is the independent
                    oracle; the in-file ref_gcb is the fallback and is
                    asserted equal to \X on every fixture string when both
                    are present

`law()` runs before any row is emitted and asserts, per segment and through the
byte encoding, that `normalize(original[src[j]:src[j+1]])` equals
`normalized[dst[j]:dst[j+1]]`, plus the whole-string check that the segments
concatenate to CPython's own normalize of the input. `law()` runs on every
(string, form) the fixture touches and asserts once per segment: **434
assertions** in a generation run (`assert checked["law"] > 200`), and
`checked["gcb"] == len(G)` — all 41 grapheme strings through `\X`. A fixture row
that breaks the law cannot reach the file, so the file cannot pin a bug the two
implementations share.

### The fixture pins the map one-way, not only as a round trip

A test that asserts only `back(fwd(span)) == span` is satisfied by *any* pair of
mutually inverse functions, including a consistently wrong pair — an off-by-one
in both directions, or a map that collapses a non-injective run to the wrong end
of it. A round trip cannot tell you *which* original byte was picked, only that
it was picked consistently. So the fixture pins the one-way answer twice:

- the **4 `sp` rows** print the original byte range literally — `7:3:0-1`,
  `7:3:11-12` — against `src[seg]`/`src[seg+1]` that CPython computed in
  `normref()` from `unicodedata` alone;
- the **87 `rt` rows** print `1 <code points>`, where Bend maps the offset back,
  re-slices the **original** by that range, re-normalizes *that slice*, and
  prints its code points — expected against the normalized segment CPython
  computed independently. A wrong range re-normalizes to different code points.

Measured, not argued. Mutant M7 shifts only the original-side map by one byte:

    M7 differing rows by section:
      cp 0  bv 0  vd 0  gv 0  nc 0  dims 0  rt 85  sp 4     (89 of 257)
      sp expected  7:3:0-1  7:3:11-12  7:3:0-3  7:3:0-2
      sp actual    7:3:1-1  7:3:12-12  7:3:1-3  7:3:1-2

Every "does it normalize correctly" row — all 76 `nc` and all 7 `dims` — passes
under M7. A fixture built the obvious way would have shipped it.

### Mutants

Seven single-line changes to `power/text.bend`, all seven caught. `PASS: 2` is
oracle + check: the fixture file and the typechecker are unmoved by a semantic
mutation, which is the point — the four *running* lanes are what refuse it.

| mutant | the one line | result |
|---|---|---|
| M1 Regional_Indicator pairing dropped, so flags split | `bit.ri`: `bit.of(4,` → `bit.of(0,` | PASS 2 / FAIL 4 |
| M2 CR LF broken into two clusters | `brk`: `U32.is_eq(k, 2)` → `U32.is_eq(k, 3)` | PASS 2 / FAIL 4 |
| M3 ZWJ never joins | `bit.azp`: `U32.is_eq(raw, 5)` → `U32.is_eq(raw, 55)` | PASS 2 / FAIL 4 |
| M4 offset map off by one after a multi-byte decomposition (dst side) | `fl.map`: `Vec.push(dst, n)` → `Vec.push(dst, U32.inc(n))` | PASS 2 / FAIL 4 |
| M5 canonical ordering made unstable | `snk.cmp`: `U32.is_gt(ccc(a), ccc(b))` → `is_ge` | PASS 2 / FAIL 4 |
| M6 D115 blocked rule too loose | `cm.at`: `U32.is_lt(last, cc)` → `U32.is_le(last, cc)` | PASS 2 / FAIL 4 |
| M7 offset map off by one on the original side (src) | `fl.map`: `Vec.push(src, seg)` → `Vec.push(src, U32.inc(seg))` | PASS 2 / FAIL 4 |

M1's diff is the predicted one, and it lands on 6 `gv` rows and nothing else:

    exp <0 8 >            act <0 4 8 >
    exp <0 8 12 >         act <0 4 8 12 >
    exp <0 8 16 >         act <0 4 8 12 16 >
    exp <0 1 9 10 >       act <0 1 5 9 10 >
    exp <0 3 11 13 19 >   act <0 3 7 11 13 19 >

Every flag split into its two halves, at exactly the 4-byte offsets where a
regional indicator begins.

**M6 escaped the first sweep, and fixing that changed the fixture.** No string
had a starter followed by a *non-composing* same-class mark and then a
*composing* same-class mark, so the blocked-rule guard was always short-
circuited by `co == 0` and `is_lt` vs `is_le` could not be told apart. The
string `A` U+0300 U+0301 U+0302 U+0303 became `A` U+0305 U+0300 U+0301 U+0302
U+0303: U+0305 has class 230 and does not compose with A, so `last` becomes 230
and the following U+0300 is correctly blocked — while the mutant composes it to
À. Zero net row change, which mattered: the row budget is 257 against a JS-lane
ceiling of 260.

## Measured

`tests/power/bench/text.bend` segments a **16,776,384-byte** corpus —
8,038,684 code points, 5,592,128 clusters — into extended grapheme clusters.
One `gtab()` binary search and one break decision per code point, plus the
UTF-8 decode that finds it.

The corpus is not a data file. It is one 48-byte unit repeated 349,508 times,
rebuilt the same way on both sides, the way `tests/strings/bench.sh` rebuilds
its 8 MiB corpora from a unit string and a repeat-to-N rule. The unit is chosen
so every rule that can fire does: an ASCII run (GB999), a precomposed é (a
2-byte decode), a Hangul LV syllable followed by a T jamo (GB9a through the
LV/LVT arithmetic), a regional-indicator pair (GB12/GB13), a base with two
combining marks (GB9), a ZWJ emoji sequence (GB11), two CJK ideographs, and a
CR LF pair (GB3).

    bench             C  bend-1T bend-16T    1T/C  1T/16T
    text           0.07     1.06     1.12   15.6x    0.9x
    text_par       0.06     1.01     0.30   16.2x    3.4x

    C        229 MiB/s      bend 1T   15.1 MiB/s      bend_par 16T   53.3 MiB/s

All four programs print **1662718575**, and `run.sh` refuses to time a row
until they do, so these are correctness rows as well as timing rows.

**This bench had no C twin before this lane.** `text` was the only bench in the
suite absent from both `twins.c`'s dispatch and `run.sh`'s shared-twin alias
list, so it would have failed the checksum step rather than been timed.
`twin_text.c` (the sequential twin, holding the 54-range table flattened out of
`gtab()`'s BST and line-for-line ports of `gcb`/`gg`/`gnl`/`join`/`brk`/`flag`)
and `twin_text_par.c` (which `#include`s it under `TWIN_TEXT_NO_MAIN`, the
`twin_grammar_par.c` convention) ship with the lane. Neither `twins.c` nor
`run.sh` was touched.

The checksum was also confirmed against a **third** implementation: because the
unit ends in CR LF and GB4 breaks after LF unconditionally and statelessly, the
corpus's cluster starts are exactly the unit's repeated, so CPython's `regex`
`\X` on the 48-byte unit plus arithmetic gives 5,592,128 clusters and
1662718575 without scanning 16 MB.

**15.6× C is the honest number and it is the worst ratio in the package**
(scalar lanes run 2×). The inner loop is a table lookup and a branch per code
point with no arithmetic to hide anything: C does a direct byte load and a
binary search over a flat array, Bend does a `choose` tree over a `Data`
constructor and `By.at` through a `Vec` with bounds masking. There is no
floating point, no multiply chain, nothing that closes the gap. It is what
segmentation costs here.

### The chunk boundary

**Grapheme segmentation does not chunk freely.** The break decision at offset
`o` reads state carried from the last break before `o` — the previous class,
whether a pictographic run is live, whether the regional indicators since the
break are odd. Hand a leaf a naked `[lo, hi)` and it starts with no previous
class, which is exactly GB1, a break at the start of text: every boundary it
reports until the first real break is wrong, and a flag sequence split down the
middle becomes two flags.

`text_par.bend` handles it explicitly, two ways:

- **A backward anchor scan.** GB4 breaks after LF with no exceptions and no
  state, so the byte after any LF is a cluster start *whatever precedes it*, and
  so is 0. Each leaf scans backward from its `lo` for the nearest, at most 256
  bytes, segments from there, and reports only the starts that land in its own
  `[lo, hi)`. Falling out of the 256-byte window answers 0, which is always
  correct and merely slower.
- **A four-byte tail over-read.** A code point beginning at `hi - 1` runs past
  `hi` and its start is this leaf's to report, so each leaf reads one maximal
  UTF-8 width past `hi` and drops boundaries at or after `hi`.

Cost: **1,440 run-up bytes + 256 tail bytes = 1,696 on 16,776,384, 0.0101%**.
`text_par` at 1T is 1.01 s against `text`'s 1.06 s — the over-read is below the
difference between two compiled programs of different shape, let alone
measurable.

The leaves combine by **adding**, not by a rolling mix: the checksum is a sum of
`hh(offset)` over cluster starts with the count beside it, and a sum over
disjoint ranges is the sum of the sums. The tree of 64 leaves therefore equals
the one sequential walk without anything being folded left to right, and the
schedule cannot change the answer.

**3.4× on 16 threads** is below the 5–6× the scalar lanes reach. Each leaf
builds and fills its own ~262 KB `Bytes` before it scans, so the fork is
allocator- and bandwidth-bound rather than compute-bound; that is a hypothesis
consistent with the numbers, not a measurement.

## A hole found in this lane's own bench, and closed

The first version of this bench used a 16,776,192-byte corpus and 64 chunks of
262,128 bytes. Both are multiples of 48. **Every chunk boundary therefore
landed exactly on a unit boundary, which is exactly a cluster start** — so the
anchor scan and the tail over-read, the entire subject of `text_par.bend` and
the hazard the brief singles out, were never exercised. Deleting the anchor
would not have changed the checksum. A bench that cannot fail when you delete
the thing it measures is not measuring it.

The fix is one constant: 16,776,384 = 48 × 349,508 with chunks of 262,131,
which is **3 mod 48**. The 64 chunk starts now walk sixteen phases through the
unit: **32 of 64 begin in the middle of a UTF-8 code point** — inside an emoji,
inside the ZWJ, inside a combining mark — and **36 of 64 begin in the middle of
a cluster**.

Two negative controls, run on the fixed bench, each a one-line deletion:

| control | checksum |
|---|---|
| as shipped | 1662718575 |
| `anchor(lo)` := `lo` — no run-up | 879894037 |
| `corpus(q, hi + 4)` := `corpus(q, hi)` — no tail over-read | 2783662206 |

Both diverge. The cut is load-bearing, and now the bench says so.

## Deliberate ceilings

- **GB9c, the Indic conjunct rule, is off in every script.** It needs `InCB`
  data the derived tables do not carry. Upgrade path: derive `InCB` alongside
  GCB and add one rule to `brk` — the carried-bit machinery is already there.
- **Combining marks outside U+0300..U+036F are classed `Other`**, so Hebrew,
  Thai and the non-Devanagari Indic scripts split clusters that should hold.
  Upgrade path: more ranges in `gtab()`, no code change — `look` is a tree over
  whatever ranges it is given, and `tests/power/text_gen.py` would pin them
  against `regex`'s `\X` the same day.
- **Normalization covers Latin-1, Latin Extended Additional, the combining
  diacriticals, Hangul, and seven stragglers.** Not Greek polytonic beyond
  U+0385/U+1FC1/U+1FED, not Cyrillic, not the CJK compatibility ideographs, not
  NFKC/NFKD at all. Upgrade path: extend `dtab`/`ctab` and re-run the
  closure check in the generator — the ceiling is a table, not an algorithm.
- **Simple case folding.** Ten code points in coverage have multi-code-point
  full folds and are left alone. Full folding would make `fold` one-to-many and
  change the shape of the map, the buffer and every signature downstream. It is
  a different primitive, not a bigger table.
- **`back` is a fixed 32-round binary search**, not a loop that stops when the
  range closes. Bend's fuel-and-state shape wants a `Nat` known up front and 32
  rounds covers every `U32` index; a document with fewer segments pays the same
  five or six wasted compares. Marked `ponytail:` in the file.
- **No incremental / streaming normalization.** `norm` takes a whole `Bytes`
  and answers a whole `Norm`. A streaming form would need the segment boundary
  to be re-derivable at a chunk edge, which is the same anchor problem
  `text_par.bend` solves for graphemes and is not solved here.

## The size of the file

`power/text.bend` is 31,274 ttok against a 64,000 cap, and the largest file in
`power/` by a distance — `delta` is next at 12,345. Roughly a third is the UAX
#29 class table plus the GB1–GB13 ladder, a third the canonical
decomposition/composition tables and the ccc-ordering sink, and a third the
offset map with `back`/`fwd`. None of it is scaffolding: the tables are the
size the coverage claim commits to, and the map is the part with no shortcut,
since one normalized offset answers to a run of original bytes and a span has
to survive both directions.

    power/text.bend                   31274 / 64000
    tests/power/text.bend              9708 / 16000
    tests/power/text_gen.py            7475 / 16000
    tests/power/bench/text.bend        1616 / 16000
    tests/power/bench/text_par.bend    3069 / 16000
    tests/power/bench/twin_text.c      2557 / 16000
    tests/power/bench/twin_text_par.c   377 / 16000

## Battery

power 6/0 for `text` (+ the wrong-`#|` control) · repo 54/54 · caps ok ·
bench 2/2 rows, all four programs on 1662718575 · 7/7 mutants caught ·
2/2 negative controls diverge.

## Next

The two upgrades that would pay immediately, in order: `InCB` for GB9c, since
the rule machinery is already there and only the data is missing; and the
remaining combining-mark ranges in `gtab()`, since that is pure table and would
turn "exact for these scripts" into "exact for text". Neither needs a line of
new algorithm. NFKC is the one that does — compatibility decomposition is not
closed the way canonical decomposition is, and it would want its own ceiling
argument before its own table.
