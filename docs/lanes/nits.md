# Lane: nits — the six deferred items

Branch `lane-nits` (off `omen` at f134bfa7). One commit per landed item, the
full battery per item. `bend2/bend.ts`, `bend2/main.ts`, `gates/**`,
`tests/caps.sh` and `bend2/comp.ts` are untouched (so `runtime.py` was never
due); no cap was edited. Nothing was pushed.

| # | item | state | where |
|---|---|---|---|
| 1 | `File.fold_text` | **designed + verified, cap-blocked** (base needs 43,291) | branch `lane-nits-base` |
| 2 | parser `Block` append quadratic | **done** | 9c28cd21 |
| 3 | sockets decode-carry | **done** (effect + specimen); base wrapper **cap-blocked** (+320) | e742cc0b, `lane-nits-base` |
| 4 | non-ASCII identifiers | **identity tier done** (XID validity exact; NFKC-stable identifiers parse); full NFKC + marks **designed** | this commit series |
| 5 | 3.12 f-strings | **evaluated: deferred**, design + decision below | this file |
| 6 | mixed-width packing | **evaluated: designed**, measurements below | this file |

## Cap readings (ttok, measured here)

| file | now | cap | left | note |
|---|---:|---:|---:|---|
| `bend2/base.bend` | 42,913 | 43,000 | 87 | the brief said 42,971; this tree reads 42,913 |
| `bend2/comp.ts` | 80,652 | 81,000 | 348 | item 6 cannot fit in any form |
| `demos/python/parser.bend` | 21,513 | 64,000 | 42,487 | |
| `demos/python/unicode.bend` | 13,013 | 64,000 | 50,987 | item 4's tables: +4,189 |

**Measured base needs** (each verified on four lanes before measuring):
item 1 alone **43,291** (+378); item 3's wrapper alone **43,233** (+320);
both **43,611**. A cap of 44,000 lands both with 389 to spare. They are
stacked, ready to cherry-pick, on `lane-nits-base` (gate reads 44/45 there:
`base.bend` over its cap and nothing else).

## 1. `File.fold_text` — designed, verified, cap-blocked

```
File.fold_text(~S: Type, ~step: S -> String -> S, fuel: Nat, file: File,
  dec: Utf8.Dec, +max: U32, st: S) -> IO(S)
```

Folds `step` over the file's `File.read_text` chunks (`max` bytes each,
`fuel` chunks at most), closes the file at the end and answers the state; a
read error dies as `IO.try` does. Three defs, because of three checker
rules met on the way (recorded so the next helper does not rediscover them):

- a `match` cannot scrutinize a computed value → `Utf8.Dec.eof(dec)` goes
  through `File.fold_text.end(eof: Bool, ..)`;
- no mutual recursion and definition order matters → the helpers take the
  recursion as an `again` continuation, and the group sits after
  `Utf8.Dec.eof` (String section), not beside `File.read_text`;
- a function argument cannot be `+` (not `Data`) → `S` and `step` are `~`
  template parameters, as `List.foldl`'s `~f`.

Evidence: a scratch specimen folding a scalar count over
`tests/strings/utf8.bin` at max 1 / 3 / 4096 answers 15 / 15 / 15 (the
`io_stream` specimen's "15 chars") on interpret, JS and C. It is committed as
`tests/strings/io_fold.bend` on `lane-nits-base` only, with the def.
Residual risk: none beyond `File.read_text`'s own; `IO.die` halts the
process, so the fuel-out and error paths do not close the file first.

## 2. Parser `Block` append — done (9c28cd21)

`Block{top, statements, end}` appended every line's body with
`S.fields_append(statements, ..)`: O(n) per line, O(n²) per block. `Simple`
did the same per `;`. Both now push reversed (`N.reverse(body, statements)`,
`S.JItem{.., statements}`) and reverse once where the block is built. Output
is unchanged: 1773/1773 fixtures, fuzz, adversarial and corpus tier 1 inside
Parser 108/0.

| input (C lane, `--gpu off`) | before | after |
|---|---:|---:|
| `x = 1\n` × 10,000, parse | 0.98 s | 0.30 s |
| × 20,000 | 3.28 s | 0.58 s |
| × 40,000 | 12.29 s | 1.18 s |
| 10k → 40k ratio | 12.5 | 3.9 |
| `x = 1; ` × 5,000 on one line | 0.31 s | 0.16 s |
| × 20,000 | 3.20 s | 0.58 s |
| lex only, 40,000 lines (unchanged) | 0.87 s | 0.87 s |

Guard: `tests/parser/lexscale.py` now measures `PY_MODE=parse` on the same
file (its N lines are one block of N statements), limit 6.0. The old parser
reads 8.73 there and fails the guard (checked by swapping the old
`parser.bend` in); the new one reads 3.8–4.0. The limit is 6 rather than the
lexer's 8 because the row carries the linear lex, which dilutes the old ratio.
Residual risk: other accumulators were not audited (`Arguments`, parameter
lists and `Cases` already accumulate reversed); a quadratic elsewhere would
need its own shape of input to show.

Battery: gate 45/45, strings 89/0, f64 19/0, codex 161/0, regex 49/0,
parser 108/0.

## 3. Sockets decode-carry — done (e742cc0b); base wrapper cap-blocked

`TCP.recv_text.go` (`bend2/effs/tcp_recv_text_go.c` / `.js`) is `File.read_text`'s
carry on a socket: the carried bytes go first, a scalar cut by the end of a
recv is carried out (`pend` low byte first, `need` <= 3), a recv that only
feeds the carry parks again instead of answering `""`, and a recv of 0 bytes
replaces a live carry with U+FFFD and answers `need` 4 (end of stream).

Evidence: `tests/strings/io_sock_utf8.bend` sends `"añ€😀 wörd\n"` × 3 over
loopback and drains it at max 1 / 2 / 3 / 7 / 4096; every max answers the
sent text's hash and length (263802747, 30) on interpret, JS, C and C
threads. Off-suite, a Python peer splitting U+1F600 1+1+2 across waits and
closing on a lone C3 lead decodes to `97 128512 98 65533` on interpret / JS /
C, which is Python's whole-stream `errors="replace"` decode.

Cap: the specimen binds the wrapper locally (`Sock.Raw`, `def
TCP.recv_text.go` importing `../../bend2/effs/tcp_recv_text_go`), because the
base def `TCP.recv_text(sock, dec, max)` needs +320 tok (43,233 > 43,000). It
is ready on `lane-nits-base` (93e37e69), where the specimen uses the base def.

Residual risk: (a) the end-of-stream carry path is covered only by the
off-suite Python peer (a Bend peer cannot close mid-scalar deterministically
inside one specimen); (b) `gates/test.ts` matches test effect imports as
`"./name.(c|js)"`, so the specimen's `../../bend2/effs/` import is unproven on
the cluster gate — it goes away when the base def lands; (c) the parser suite
was not run on `lane-nits-base` (it changes `base.bend` only by adding defs).

Battery: gate 45/45, strings 93/0, f64 19/0, codex 161/0, regex 49/0,
parser 108/0.

## 4. Non-ASCII identifiers — identity tier done; full NFKC + marks designed

**Done (this commit):** a non-ASCII identifier that NFKC leaves alone parses
as written; one with a scalar outside XID_Continue (or outside XID_Start in
first place) answers `Syntax` "invalid character" as the oracle does; one
NFKC would change stays `Unsupported` (so `Unsupported` is now: NFKC-changed
identifiers only). `café`, `变量`, `переменная`, `λ` parse; `ﬁ`, `ｉｆ`, `ǆ`,
`K` (Kelvin) are refused; `a²`, `٣a` are syntax errors.

How it stays exact without normalizing: a NAME token is a run of the lexer's
`\w` scalars, so three tables generated from the pinned oracle decide it
(`tests/parser/gen_ident.py` prints them into `demos/python/unicode.bend`):

| table | ranges | verdict |
|---|---:|---|
| `not_continue` = `\w` − XID_Continue | 82 | `Syntax` anywhere |
| `not_start` = (`\w` ∩ XID_Continue) − XID_Start | 65 | `Syntax` in first place |
| `unstable` = `\w` ∩ (NFKC changes it ∪ ccc ≠ 0 ∪ second of a composition pair, jamo V/T included) | 198 | `Unsupported` |

A string with no `unstable` scalar is its own NFKC form: every scalar is
stable, nothing reorders (all ccc 0) and nothing composes (no seconds); the
generator asserts the last step's premise over all of XID_Continue (0
violators). Validity is decided on the raw token and before stability, as
the oracle does (`verify_identifier` runs before `new_identifier`'s NFKC).
Keywords need nothing: they are decided on the raw text and a stable
non-ASCII identifier cannot be one.

The guard sits at the parser's four identifier sites (`ident_guard`), not in
a token pre-pass, so strings and comments are untouched and lexdiff (NAME =
`tokenize`'s `\w`) is byte-identical.

Evidence: the 65 former `Unsupported` fixtures with `é` now parse exactly
(fixtures 1773 → 1838, 0 structural / 0 location diffs) and their `ﬁ` twins
keep answering `Unsupported` on C and JS; `fuzz.py` gained 1,000 seeded
identifier sources over 15 identifier slots — 442 exact, 372 oracle
`SyntaxError`, 186 `Unsupported` — 0 failures; the harness policy
(`normalize.supported`) applies the same scalar test from `gen_ident`, so a
refusal of a stable identifier would count as a supported refusal. Cost:
`unicode.bend` 8,824 → 13,013 tok, `parser.bend` 21,513 (caps 64,000).

**Designed, not built — two parts that were bigger than they looked:**

1. *Identifiers with marks* (`नाम`, any Mn/Mc: XID_Continue − `\w` = 311
   ranges). The lexer follows `tokenize`, whose NAME is `\w`; marks are not
   alphanumeric, so `tokenize` reads `न`, ERRORTOKEN, `म` while the C
   tokenizer reads one identifier and `ast.parse` accepts. Here that is
   `Syntax` "invalid character" — before and after this commit, a true
   mismatch with `ast.parse` that the corpus (0 files) never showed. The two
   pinned oracles disagree, so widening NAME breaks lexdiff's contract; the
   clean change is to pin NAME to the C tokenizer (scalar ≥ 128 continues an
   identifier; validate after) and teach lexdiff to merge `tokenize`'s
   NAME/ERRORTOKEN runs for comparison. That is a lexer-contract decision,
   not a nit. The harness counts such sources as outside the slice.
2. *Full NFKC.* Measured on the pinned Unicode 14.0.0: 3,568 scalars change
   under NFKC (606 to more than one scalar); 4,453 decomposition entries
   (1,769 single-target, 1,493 multi); 912 scalars / 382 ranges with ccc ≠ 0;
   941 composition pairs, plus algorithmic Hangul. As Bend range trees at
   this file's ~12 tok per entry that is **≈ 80k tokens of tables** against
   a 64,000 cap per file and a demo of ~52k in all — larger than the parser
   itself, for 0 corpus files. Shape if wanted: tables split over two or
   three generated files (`nfkc_decomp`, `nfkc_ccc`, `nfkc_comp`), the three
   passes (decompose, canonical order, compose) in one `nfkc.bend`, called
   from `ident_guard`'s `Unsupported` arm only, so the identity tier stays
   the fast path; the fuzz above already is its acceptance test (the 186
   `Unsupported` rows become exact rows, names compared after NFKC).

Residual risk: a source holding both an NFKC-changed identifier and, later,
an invalid one answers `Unsupported` where the oracle says `SyntaxError` (the
first refusal wins; both are refusals, and it was so before). The harness
treats any unstable scalar inside an f-string token, literal text included,
as outside the slice (it can only lower the supported count).

## 5. Python 3.12 f-strings — evaluated, deferred

**Decision: do not implement now.** The 3.11 contract stays whole; a 3.12
mode is specified below for when there is a reason beyond three files.

What PEP 701 changes, against this parser's shape:

- In 3.11 an f-string is one `STRING` token that ends at the first matching
  quote; `fstring.bend` then scans the body (`fstring_find_literal/_expr`).
  In 3.12 the token's end depends on brace nesting (same-quote reuse inside
  `{}`), so the change starts in the **lexer**, not in `fstring.bend`.
- Backslashes and `#` comments become legal in the expression part; nested
  strings inside it then carry escapes, so the expression scanner must skip
  `\"` inside nested literals (it never had to: 3.11 refuses the backslash
  first, `fstring.bend:119`).
- 3.12 locates the pieces of a `JoinedStr` exactly; 3.11 gives every
  `Constant` / `FormattedValue` the whole run's span (`Ctx.lo/hi`). A file
  only 3.12 can parse has **no 3.11 locations to agree with**.

Measured need: of 8,475 corpus files, **3** are 3.12-only f-strings
(0.035 %), and all three use one feature — a backslash in the expression
part (`—`-style escapes inside a nested literal). `python3.12` on this
machine parses all three; nested same-quotes and comments occur in 0 files.

Why not the one-line version (drop the backslash refusal): it needs the
nested-literal escape skip, a mode flag threaded from `PY_MODE`/env through
`P.State` to the scanner, a second pinned oracle (3.12) with a
locations-stripped comparison, and it yields a hybrid that is neither
CPython: 3.11's grammar with one 3.12 relaxation. Every row of today's
evidence (0 policy mismatches against one pinned oracle) would gain an
asterisk for 3 files.

If it is wanted later, the clean shape is:

1. `PY_GRAMMAR=3.12` (default `3.11`), carried in `P.State`; never inferred.
2. Classified superset: in 3.11 mode the three constructs keep answering
   `Syntax` with the oracle's message; in 3.12 mode they parse. A file's
   result records the mode, so reports never mix the two contracts.
3. Phase A (backslash + comments in the expression part; token boundary
   unchanged) covers 3/3 corpus files; phase B (brace-aware token end in the
   lexer for same-quote nesting) covers the rest of PEP 701.
4. Oracle: pin 3.12.x beside 3.11.15; compare structure + locations against
   3.12 in 3.12 mode (so `Ctx`'s whole-run spans become exact spans there),
   and keep 3.11 mode byte-identical to today (the existing 1773 fixtures
   are the tripwire).

Residual risk of deferring: none to the contract; the three files keep
answering `Syntax` on the oracle's own message.

## 6. Mixed-width strings packing — evaluated, designed

**Decision: design note only.** `comp.ts` has 348 tokens under its cap and
any variant touches `str_cell`, `str_cell_put`, `str_reserve`,
`str_copy_cells`, `io_str`, the literal packer and both GPU sources.

The problem, from the adaptive lane's own table: one astral scalar makes the
payload 4 B per cell (unicode-8MiB peak RSS 30,768 KiB — no gain — while the
same text without its astral scalars reads 18,680, and Latin-1 14,136).

Payload bytes under each technique (model: `fit` as `str_fit`; region tables
and patch entries counted; `/tmp/mixed_model.py`, reproduced below):

| corpus | cells | UTF-8 | today | regions 256 | regions 4096 | patch |
|---|---:|---:|---:|---:|---:|---:|
| bench unicode unit ×10k (astral every 17 cells) | 150,000 | 240,000 | 600,000 | 602,344 | 600,148 | 380,000 |
| this repo's `docs/omen/lanes/*.md` (99.72 % 1 B, 0.28 % 2 B, 0.0014 % 4 B) | 286,196 | 288,368 | 1,144,784 | 420,972 | 597,248 | 292,636 |
| ASCII 1 MiB + one U+1F600 at the end | 1,048,573 | 1,048,576 | 4,194,292 | 1,065,716 | 1,061,876 | 1,048,581 |
| Latin-1 prose, one emoji per 2,000 cells | 1,000,500 | 1,189,500 | 4,002,000 | 1,399,524 | 4,002,980 | 1,004,500 |

- **Per-region widths** (fixed R cells per region, a u32 byte-offset per
  region): O(1) access with one extra load; helps only when wide scalars
  cluster. Sparse-but-regular wide scalars defeat large regions (last row,
  R = 4096: no gain) and the dense bench corpus defeats all of them.
- **Patch table (recommended)**: keep the payload at the width `w` that
  minimises `n·w + 8·k`, store the k scalars that do not fit as a sentinel
  cell (the top value of the width: 0xFF / 0xFFFF — so 1 B then holds ≤ 0xFE)
  plus a sorted `(cell index, scalar)` side block; fall back to today's
  whole-payload widening when the patch table would be larger. Reads stay one
  compare on the fast path and a binary search only on a sentinel; views stay
  zero-copy (a view searches the same table by absolute index). It wins every
  row above, including the dense one (380,000 vs 600,000), and it removes the
  late-widening peak (n + 4n) because a late wide scalar becomes one patch.

Costs to settle before building it: a third branch in `str_cell` (the
adaptive lane measured +6–13 % process time for its two); in-place append of
a wide scalar grows the side block (it needs its own capacity/ownership —
the simplest is a second `TAG_BUF` hung off the payload's first word);
`String.copy` must rebase patch indices; the GPU sources need the search
loop; equality/hash/order already go cell by cell and are unaffected.
Estimated `comp.ts` need: 1,200–1,800 tokens (the adaptive lane spent 796 on
a smaller change) → **cap ≥ 83,000**.

Probe plan (no new harness): `runtime.py`'s `cells()` width cycle gains a
patched width, the `widths` section asserts payload size ≤ `n·w + 8k + class
slack`, and `bench.sh` gains the two sparse corpora above beside
`unicode-*`; acceptance is RSS ≤ 1.3× the 1 B row on the sparse corpora with
the ASCII rows' time within noise of today.

BATTERYFINAL
