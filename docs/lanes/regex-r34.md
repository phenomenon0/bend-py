# Regex lane — R3 + R4 report (fable, 2026-09-18)

Branch `lane-regex`, worktree `bend-work-regex`. Continues `regex.md` (R0→R2). Semantic pin:
CPython **3.11.15** `re` under `re.ASCII`. The R4 session was SIGTERM'd once mid-slice (oracle
written, never run); this report covers the resumed run. Nothing pushed.

## Slices

| slice | commit | content |
|---|---|---|
| R3 | `cddba67a` | Derived API `Regex.find` / `is_match` / `group`; budgeted globals `find_all` / `split` / `replace(re, s, by, limit)` on one `U32` budget; finditer same-position retry via a VM `ne` (non-empty) flag; fixtures `laws.bend`, `budget.bend`, `globals.bend`. |
| R4 | `64c9e9b7` | `tests/regex/oracle.py` — 5,000-pair differential oracle vs CPython; two oracle-found semantic fixes in `base.bend`; `wordb.bend` pins both. |

### R3 — derived API + budgeted globals

- `find = exec(re, s, 0)`, `is_match = is_some(find)`, `group(s, m, k)` slices the explicit source
  (absent capture `None` ≠ empty capture).
- One budget per global call, never reset per result, no partial success: a search from `at` pays
  `(1 + length − at) · weight(re)` **before** it runs (`weight` = every inst once, each with a capture
  copy `3 + 2·ngroups`, plus class-range probes; `Regex.cost` multiplies saturating at `U32` max);
  the output is paid from what is left (`1 + ngroups` per `Match`; 1 per code point for
  `split`/`replace`). Exhaustion ⇒ `Fail{RErr{at, "budget exhausted"}}`.
- Driver = Python `finditer` order, including the same-position retry (`|a` on `a` ⇒
  (0,0),(0,1),(1,1)). `split` = unmatched gaps only (empties kept, separators and groups omitted);
  `find_all` returns `Match` records (unlike Python `findall`); `replace` text is literal.
- `budget.bend` pins the rescan case: `a.*b|a` on n `a`s costs `weight·(n+1)(n+2)/2` — quadratic,
  exact, one unit short at any stage is an error. `laws.bend` pins the seven §1.3 laws.

### R4 — oracle

`tests/regex/oracle.py [--pairs 5000] [--interpret 500] [--seed 34] [--jobs N] [--selftest]`

- **Pin:** refuses anything but CPython `(3, 11, 15)`; started under another python it re-execs
  once into `/home/omen/.hermes/hermes-agent/venv/bin/python3` (the same pin as
  `tests/parser/normalize.py`). Resolved executable:
  `/home/omen/.hermes/hermes-agent/.hermes-runtime/python/generation-1785203907-1740771-edaf0b90/cpython-3.11.15-linux-x86_64-gnu/bin/python3.11`.
- **Generator** (seeded `random.Random(34)`, no hash-order dependence — corpus sha identical under
  `PYTHONHASHSEED=1/2`): v1 syntax only — literals incl. `é`/`😀`, `\xHH \uXXXX \UHHHHHHHH`,
  escaped metachars/punctuation, classes (ranges, `\d\w\s\D\W\S`, `\b`=backspace, negation,
  trailing `-`), `.`, anchors `^ $ \b \B`, capturing / `(?:` groups to depth 3, alternation incl.
  empty branches, all quantifier forms + lazy, flags `i m s` (20 % each). It tracks nullability and
  **never emits an unbounded repeat of a nullable body** (the v1 `NullableRepeat` exclusion); every
  pattern must compile under CPython or the run aborts as a generator bug. Text: 0…64 code
  points (max observed 64) from a fixed pool + the pattern's own printable chars.
- **Compared, byte for byte**, per pair: `search` and `fullmatch` (span + every group, absent ≠
  empty), every `finditer` match (span + groups) vs `find_all`, the gaps vs `split`, literal
  replacement vs `replace` (`re.sub(p, lambda m: by, s)`, with `by` ∈ {``, `-`, `<é>`, `\1`,
  `\g<0>&`, `😀\n`} to prove literalness). The gap reconstruction is asserted equal to CPython's
  own `rx.split(s)[::groups+1]` and `sub == by.join(gaps)`.
- **Lanes:** C (`--gpu off`) and JS on all 5,000; interpreter on the first 500. 125 pairs per
  generated Bend program, rows in defs of 10.
- **Self-test:** `--selftest` corrupts one expectation and passes only if exactly that row is
  reported on both C and JS.
- **Result:** `Oracle: 5000 pairs, diffs c=0 js=0 interpret(500)=0` (exit 0, ~5 min wall on 16
  cores).

Recorded in `tests/regex/_out/` (gitignored): `corpus.json`, `oracle.json`.

| sha256 | |
|---|---|
| executable | `8deffe5dd9ebcf98a062917a4e73bb8fbb7d5846f83dec01fb7506fd5d41c54e` |
| `re/__init__.py` | `029ead61f362489e9bb034f4c2503abee95462056541e9ad07715de3c353b0da` |
| `re/_parser.py` | `4748e39c77d6dc14f81af80e68a62ad99031a8182d5e0b219a6666d0cfb1626f` |
| `re/_compiler.py` | `c05067f8bfa4c13cbbf1eedc4d5cafc9b621bcb6ebc5771ba0518a18095af15a` |
| `corpus.json` (seed 34, 5,000) | `bf50b39afdc433325049549dad135c7dafbbd617da498373a026de55a9b522b6` |

(`oracle.py` and `base.bend` hashes are in `oracle.json`; bun 1.3.4.)

**Diffs found and fixed in the semantics (oracle untouched):**

1. **`\b` / `\B` on the empty string.** CPython 3.11 (`SRE_AT_BOUNDARY`/`NON_BOUNDARY`: `beginning
   == end ⇒ 0`) makes *neither* hold; Bend had `\B` matching `""`. Fixed in `Regex.exec.wordb`
   (1 diff per lane in the first 250 pairs). Note: CPython 3.14 changed this; v1 stays on 3.11.
2. **A group around an anchor takes a quantifier.** `(?:^){3}`, `(\b)?`, `(?:$)??` compile in
   CPython; Bend's `fin` returned the bare anchor and `push` re-derived "nothing to repeat" from
   it. Fixed with `Regex.parse.push.q` (a closed group is always an atom). Bare `^*` is still
   `"nothing to repeat"`; `(?:^)*` is still `NullableRepeat`. 13 of 5,000 pairs per lane.

## Size (`ttok < bend2/base.bend`)

| point | ttok | delta |
|---|---|---|
| baseline | 27,844 | — |
| after R2 (`3cc1e045`) | 40,017 | +12,173 |
| after R3 (`cddba67a`) | **42,217** | +2,200 |
| after R4 (`64c9e9b7`) | **42,253** | +36 |

**Over the 41,000 cap since R3.** `bun gates/repo.ts` reports `FAIL bend2/base.bend: 42318 > 41000
ttok` (43/44 PASS; the gate's own tokenizer reads 42,318 where the `ttok` CLI reads 42,253). Gates
and caps were not edited (prohibited): the orchestrator sets the cap at merge — next round
thousand, **43,000**.

## Test counts (at `64c9e9b7`)

| suite | result |
|---|---|
| `python3.11 tests/regex/oracle.py` | **0 diffs** — C 5,000, JS 5,000, interpret 500; `--selftest` ok |
| `bash tests/regex/run.sh` | **40 / 40** (10 fixtures × check/interpret/js/c); `--selftest` ok |
| `bash tests/run.sh` | **16 / 16** |
| `bash tests/run.sh --strings` | **85 / 85** on the idle-machine run; **84 / 85** on the first run (see Uncertainty) |
| `bash tests/codex/run.sh` | **161 / 161**, 0 suite errors |
| `bun gates/repo.ts` | 43 / 44 — the base cap only |

## Deviations

1. Oracle pairs carry flags and a replacement string as well as (pattern, text).
2. "findall" is compared as `finditer` Match records (the plan's §1.3 `find_all` contract), not
   Python's `findall` strings; "split" is compared against the gaps (asserted equal to CPython's
   split with group columns dropped).
3. The harness program nests rows in `part<k>()` defs of 10: a single list literal of ≥ 25 rows
   dies in the C build with `an arity over 255` (`comp.ts` `FID_ARITY_T`; JS and interpreter take
   125). Harness-side workaround; `comp.ts` untouched. Worth knowing for R5.
4. The CPython path is hard-coded in `oracle.py` (as in `tests/parser/normalize.py`); if that
   hermes runtime generation is rotated the oracle fails loud rather than running on another patch.
5. R4b (bun priority cross-check) not done — optional in the plan.

## Uncertainty

- **`tests/strings/deep` [interpret]** failed once inside the battery (`the machine stack
  overflowed`) while `gates/repo.ts` was running concurrently; standalone 3/3 pass, and the full
  battery rerun alone is 85/85. Same load/book-size-sensitive JS stack-depth class as the R2
  report (#779/#791); a bigger base makes it likelier. Not masked, not root-caused
  (`bend2/*.ts` and `tests/strings/**` are off-limits to this lane).
- The oracle proves agreement on the *generated* distribution only: depth ≤ 3, counts ≤ 5,
  text ≤ 64 cp, no `\0`/`\r\f\v` escapes in patterns, no `max_rep`/`max_prog` edge, no budget
  exhaustion (limit = `U32` max). Those stay covered by the hand fixtures only.
- 0 diffs is on the reference VM compiled per lane; R5 natives must rerun this oracle unchanged.
