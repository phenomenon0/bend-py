# R-lane #1 — reduce, S1 report (2026-09-18)

Branch `lane-reduce1`, worktree `bend-work-reduce1`, off `omen` `f9a4b7d2`.
Plan + sizing: `docs/omen/plans/reduce1.md`. Nothing pushed.

## S1 — table clusters behind `tpl_ops`

- `tpl_ops` gained a 5th arg (`call`) for the f32/f64 `show`/`read` pairs.
- 11 clusters collapsed: length/hash/from_list/splitlines · get/get_end ·
  slice/replace · take_end/drop_end · order/join/repeat/partition ·
  starts_with/ends_with · find/find_last · pad_start/pad_end · regex
  exec/match_at · f32 show/read · f64 show/read.
- Reordering-safe: `OPERATIONS` is pure lookups (no iteration order deps).

## Numbers

| file | before | after | delta | cap |
|---|---|---|---|---|
| `bend2/comp.ts` | 80,198 | **79,812** | **−386** | 81,000 — **held** (headroom 1,188) |

Diff: `+23 / −43` lines (del/ins **1.87**). No cap raise, nothing lowered.

## Evidence

- **Byte-identical emissions**: 9 fixtures × C + JS artifacts diffed against the
  `omen` tree — 18/18 identical (padding, search, split, replace, compare,
  regex exec, regex captures, f64 read_roundtrip, f64 show_specials).
- `bash tests/run.sh` **16 / 16** · `--strings` **85 / 85** ·
  `tests/regex/run.sh` **49 / 49** · `tests/codex/run.sh` **161 / 161, 0 errors** ·
  oracle **5,000 pairs: c=0 js=0 interpret=0** · `tests/caps.sh` ok ·
  `bun gates/repo.ts` **PASS 44 / 44**.

## Next

**S2 — one scratch/pack ABI for the `*_take` family** (est −1.5…−2k; the
`re_exec_take` envelope included; VM logic untouched).

---

# S1 review + S2 (fable, 2026-09-18)

## S1 review (builder of record)

- The `slice replace` cluster left the original `string_replace` row behind as a
  duplicate key (same value, so harmless, but dead ttok). Removed.
- `tpl_ops` passes `call` straight through (`{ C, JS, call }`): every `Intr.call`
  consumer tests `=== true`, so `call: false` ≡ absent. No spread/branch.
- comp.ts 79,812 → **79,757** (−55). 18/18 artifacts byte-identical vs `/tmp/emit/old-*`.

## S2 — measured first; the estimate was wrong

The plan sized S2 at −1.5…−2k by counting the *whole* `*_take` defs (6,755 ttok)
as if they were envelope. They are not: the envelope is `str_peek` on entry and
`term_sink` on exit — ~2 lines per def. A macro-pair ABI saves ~6 ttok per def
(~−120 total) and hides control flow (`break`/`return`) inside macros. **Not
built.** The defs are algorithm, and the algorithm is already tight.

What was genuinely duplicated, and is now written once:

- `re_node` → `str_node`, moved above `str_get_take`; the hand-rolled Some-boxing
  in `str_get_take` and `str_find_take` now calls it (`cls_fit(1) == 0`, same
  alloc class, same NONE-on-error).
- `str_scratch_free(e, cls, l)`: the "sticky error → recycle locally, else
  heap_free" block lived in both `str_search_close` and the `re_exec_take` tail.
- `re_exec_take`: two identical early exits merged
  (`Loc P = err_seen(e.mem) ? 0 : heap_alloc(e, cls)`). VM untouched.

## Numbers

| file | lane start | after S1 | after S1 review | after S2 | lane delta | cap |
|---|---|---|---|---|---|---|
| `bend2/comp.ts` | 80,198 | 79,812 | 79,757 | **79,625** | **−573** | 81,000 — **held** (headroom 1,375) |

S2 diff: `+27 / −38` lines (del/ins 1.41).

## Evidence (S1 review + S2 together, suites serial)

- JS artifacts 9/9 byte-identical vs the `omen` tree. C artifacts embed the
  runtime, so they differ textually by exactly the S2 edits — the byte-identical
  bar cannot apply to a runtime slice; behaviour is judged by the suites + oracle.
- `tests/run.sh` **16/16** · `--strings` **85/85** · `tests/regex/run.sh` **49/49** ·
  `tests/codex/run.sh` **161/161, 0 errors** · oracle **5,000 pairs c=0 js=0
  interpret(500)=0** · `tests/caps.sh` ok · `bun gates/repo.ts` **PASS 44/44**.
- Not run: `gates/test.ts` / `gates/perf.ts` (mini cluster).

## Next

S3 (`base.bend` sweep, 42,318 ttok) is where the real bulk is — comp.ts's
string/regex runtime has no further cheap fat. Size with a usage graph first.
The comp cap could be lowered 81,000 → 80,000 now; left for the operator.

---

# S3 — base.bend sizing (fable, 2026-09-18): no sweep to run

Usage graph: `python3 docs/omen/plans/reduce1-s3-graph.py` (def/law/type blocks;
roots = every name mentioned in any tracked file outside base.bend + every def
ending in a type-directed operator suffix of bend.ts; conservative prefixes).

| probe | result |
|---|---|
| blocks / roots / live | 689 / 415 / 681 |
| **orphans** | **8 blocks / 331 ttok** |
| — `String.split.fin` (82) | ~~dead upstream too~~ **wrong**: upstream's `String.split` uses it; our strings-lane accumulator rewrite orphaned it. Retired at the strfix integration |
| — `F64.{min,max,clamp,lerp,square,hypot,round}` (249) | ours, no test, no user — but the exact mirror of upstream's tested F32 kit (`tests/base/num_kit.bend`). Parity surface, not debt. **Kept**; the defect is the missing test, not the defs |

So "retire orphaned helpers (String.* first)" has nothing to retire: String.* has
zero orphans — every helper is reached from a reference def that an intrinsic or a
test uses.

Where the 18.4k over upstream (23,924 → 42,318) actually is:

| family (ours, not in upstream) | blocks | ttok | used outside tests |
|---|---|---|---|
| Regex | 152 | 14,154 | comp.ts (Inst/Match ctors), demos |
| String | 48 | 3,153 | reference defs of the comp.ts intrinsics |
| F64 | 48 | 1,041 | — |
| other | 7 | 456 | |

Regex split: parse 5,996 · exec 2,978 · scan 983 · emit 873 · rest ~3.3k.

**Conclusion.** The base growth is one itemized public surface — the regex
library plus the string reference defs — i.e. exactly what Discipline (1) allows
a raise for. It is not orphan debt and a sweep cannot recover it. The only real
lever is a *rewrite* of `Regex.parse.*` (6k; the oracle + 49 suite tests make it
safely judgeable) — that is a build-quality lane of its own, not an R-lane slice.
No base.bend edits made; base cap untouched.

## R-lane #1 close

comp.ts 80,198 → **79,625** (−573), caps held, all gates green (above).
base.bend unchanged (42,318). Plan estimates vs measured: S1 −332 est / −441
real; S2 −1.5…−2k est / −132 real; S3 open est / −0 (−331 available, declined).
Lesson for R-lane #2 sizing: count *duplicated* ttok, not the ttok of the defs
that contain the duplication.

## Operator follow-up (2026-09-18)

- comp cap **held at 81,000**: the merged tree with lane-adaptive measures 80,994;
  re-measure at integration.
- `tests/f64/kit.bend` added: the seven F64 kit defs on interpret/JS/C
  (min/max in both argument orders, clamp above/below/inside, lerp, square,
  hypot, round half-up incl. negative). `tests/run.sh` is now **19/19** (was 16).
  Orphans: 8 → 1 (`String.split.fin`; retired at the strfix integration → 0).
- `Regex.parse` rewrite lane: deferred.
