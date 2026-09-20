# base-fit lane — fit, don't move (fable, 2026-09-19)

Branch `lane-base-fit`, worktree `bend-work-base-fit`, off `omen` `1bc3d961`.
Touched: `bend2/base.bend`, `tests/strings/io_sock_utf8.bend`, this report.
`bend.ts`, `main.ts`, `gates/**`, `tests/caps.sh` untouched. Cap untouched
(43,000). Nothing pushed.

## Verdict

| def | verdict | base.bend |
|---|---|---|
| `TCP.recv_text` | **LANDED under the held cap** (its cost cut +320 -> +182) | **42,953** <= 43,000, headroom 47 |
| `File.fold_text` | **still cap-blocked**, restacked and parked on `lane-base-fit-fold` (`06cf6ee8`) | 43,334 > 43,000 (+381) |

Target (>= 291 freed) **not reached**: 142 tokens were freed net on the old
text, and 138 more were taken off the TCP wrapper itself. The floor rule
applies: the honest savings are landed, the floor and the remaining levers
are itemized below. Both defs under 43,000 needs a further **334**; no lever
I can defend reaches it (the largest, declined, is 217), so **both defs =
a cap move, or fold_text waits**. That decision is the orchestrator's.

## Savings itemization

| # | commit | file:region | what | ttok |
|---|---|---|---|---|
| 1 | `8f0c882b` | base.bend: Regex section, 15 signatures (`Regex.parse.Scan`, `parse.re`, `parse`, `flags`, `compile.*`, `scan.paid*`, `find_all`, `split*`, `replace*`) | `Regex.Res(T)` names `Result<&2, &2, Regex.Error, T>` once | 42,913 -> 42,801 (**-112**) |
| 2 | `de1e9d2b` | base.bend: Types section, `Re` / `Inst` / `Match` / `Regex.Cls` | `Regex.Range/Ranges/Span` moved above the Regex types, which now name them (the Sigma was spelled 5x) | 42,801 -> 42,748 (**-53**) |
| 3 | `3c0212ce`* | base.bend: `File.read_text` plumbing | `Utf8.Dec.Raw(H)` / `Out(H)` replace `File.read_text.Raw()` / `Out()`; `File.read_text.pack` takes an erased `-H` | 42,748 -> 42,771 (**+23**) |
| 4 | `2f7c0024` | base.bend: `TCP.recv_text` (+ its specimen) | the wrapper reuses 3's aliases and pack instead of carrying its own two aliases and a copy of `pack` | +320 -> **+182** (**-138** on the parked def) |

\* hash after the message amend; see `git log`.

Net on the old text: **-142**. Net against the both-defs reading of
`lane-nits-base` (43,611): **43,334, -277**.

Every edit is type-level: alias folding, an alias parameter, an erased type
argument. No def deleted or renamed, no law, check or comment's *why* touched.

Notes on the edits:

- **1.** A payload with an inline `Sigma<.., _ => ..>` cannot go through
  `Regex.Res`: once `T` is substituted the checker re-infers the payload type
  and cannot infer the bare binder (`expected: an annotated term`). This holds
  through an alias too (`Regex.Res(Regex.scan.Out())` is refused where the
  result is destructured). So `parse.State/Item/Tree/Code/Bounds`, `scan.St`
  and the three `scan.Out()` results stay spelled out.
- **2. is a layout decision** and sits in its own commit so it can be dropped:
  the Types section now holds its first three defs (reduce2 declined this for
  that reason, est. -70; measured -53 with the one-line comment that explains
  them). The pass is linear, so an alias has to precede the types using it.
- **3/4.** `File.read_text.pack` is now handle-blind but keeps its `File.*`
  name, because the name is an emitted identifier (`$File$read_text$pack$`)
  and renaming it would move bytes. `Utf8.Dec.pack` is the right name;
  **flagged follow-up**, a pure rename whose emission diff is the identifier.
  Nothing outside base.bend named the old `Raw()`/`Out()` aliases except
  `io_sock_utf8` (the parked specimen), updated to `Utf8.Dec.Out(Socket)`.

## Emission evidence

Harness of this lane's construction (`/tmp/basefit/emit.sh`, `cmp.sh`): every
`.bend` of `tests/base`, `tests/regex`, `tests/strings`, `tests/f64`,
`tests/translator`, `demos/strings_tour`, `demos/text` is emitted as JS
(`-o x.js`) and as C source (`-o x.c`), sha256 per artifact, manifest diffed
against the `1bc3d961` baseline. 80 specimens, **160 artifacts**; 10 of them
(5 specimens x 2) do not build before or after — `tests/base/{json,parser,
bytes_ops,heap_queue_deque}` and `demos/strings_tour/oops` are expected-error
specimens — and the non-building set is the same.

| after commit | result |
|---|---|
| 1 `Regex.Res` | **160 / 160 identical** |
| 2 aliases above the types | **160 / 160 identical** |
| 3 handle-blind plumbing | **160 / 160 identical** |
| 4 `TCP.recv_text` | **158 / 160 identical**; the 2 that moved are `io_sock_utf8.{js,c}`, whose *source* changed (the wrapper left the specimen for base) |
| selftest: `Regex.spaces` `(32, 32)` -> `(32, 33)` | **DIFF detected** (regex and strings_tour artifacts move), then reverted |

Why only type-level edits: the emitters keep def names, parameter names and
term structure (`$Regex$parse$push$(t_0, n_0, stack_0, r_0)`), so any
term-level refactor — merging the ten `case Fail{e}: Fail{e}` relays, folding
one-use helpers — moves bytes and is out by the lane's rule. What is erased is
types, aliases, erased (`-`) arguments, comments and layout; that is the whole
search space, and reduce2 had already mined it once.

## Battery (serial, this machine, lane head `2f7c0024` + this report)

BATTERY_TABLE

## Floor and remaining levers

Floor under the byte-identical rule: **42,771** for the old text (42,953 with
`TCP.recv_text`). Measured and declined, or blocked:

| lever | ttok | status |
|---|---|---|
| `IO.Res(A)` for `Result<&1, &1, U32 & String, A>` (23 sites) | **-217** upper bound (measured in memory; sites with an `&` payload may hit note 1's checker limit) | **declined**: 19 of the sites are upstream's effect signatures, spelled out by upstream's convention (reduce2 kept that line too); a fork of upstream text, not a diet. Even taken, both defs read ~43,117 |
| `Regex.Res` over the Sigma payloads (9 sites) | ~-55 | **blocked** by the checker (note 1); would need annotated binders, which cost more than they save |
| `File.fold_text` in two defs (an `eof: Bool` parameter instead of the `again` continuation) | ~-60 | **blocked**: a `match` inside the bind's lambda on a let-bound variable is refused (`match scrutinees in binder order`), there is no U32 literal pattern for `need == 4`, and no mutual recursion — the three-def shape nits.md records is forced |
| aliases for `Maybe<&2, Caps> & Threads` (3x), `Maybe<&2, Match> & Nat` (3x), the esc table type (2x) | ~0 each | the def costs what the uses save |
| comments (ours: 115 lines, 1,947 ttok) | ~0 | each states a contract or a why; reduce2 reflowed them already |
| `Utf8.Dec.pack` rename | 0 | quality follow-up, moves one emitted identifier |

So: `File.fold_text` (+381) needs the cap at **>= 43,334** as things stand,
or ~43,117 if the orchestrator also takes the `IO.Res` fork of upstream's
signatures. The measured move for both defs with the next fix's headroom in
mind would be 43,500. With 47 of headroom on the lane head, the next base.bend
fix trips the cap again either way — the structural lever is still the
deferred `Regex.parse` rewrite (5,996 ttok), not more dieting.

## Battery (orchestrator-verified on this exact tree)

All ten checks green: gate 45/45; strings 93/0; f64 19/0; codex 161/0; regex 49/0;
parser 108/0; lint totality 20/0; alias 16/0; translator 12/0; runtime.py ASan
(84,412,268 allocations, zero live; 177,128 stream partitions; 180,094 JS partitions;
83 injected failures). This report + these results committed by the orchestrator after
the session exited mid-battery; the commits above were not touched.
