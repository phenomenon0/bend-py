# lane-strgaps — the Python-gap String ops

Base `23f92d70` (omen). Operator-sanctioned new public surface: the must-have `str` methods
the audit against Python 3.12 found missing. 28 public ops, all pure `base.bend` defs;
`comp.ts`, `bend.ts`, `main.ts` untouched; **no natives** (nothing here is measured-hot).

## Ops added

| group | ops |
|---|---|
| predicates (ASCII) | `String.is_alpha` `is_digit` `is_alnum` `is_space` `is_upper` `is_lower` `is_ascii` `is_printable` `is_identifier` `is_title`; aliases `is_decimal` = `is_numeric` = `is_digit` |
| Char helpers they need | `Char.is_letter` `Char.is_alnum` `Char.is_ascii` `Char.is_printable` `Char.is_word` |
| edits | `String.remove_prefix` `remove_suffix` `center(s, w, c)` `swapcase` `title` `casefold` (= `to_lower`) `expandtabs(s, n)` `rsplit(s, sep)` `rpartition(s, sep)` |
| format | `String.format(s, args: List<String>) -> Maybe<String>` |

Naming: underscore where the siblings already have one (`is_*` like `Char.is_alpha` /
`String.is_empty`; `remove_prefix` beside `starts_with`), Python's single word where the tree
already keeps Python's (`splitlines`, `zfill`, `partition` → `swapcase`, `casefold`,
`expandtabs`, `rsplit`, `rpartition`). The brief's `isnumeric` / `istitle` are spelled
`is_numeric` / `is_title`. Bend has no default arguments: `center`'s fill and `expandtabs`'
tab size are explicit.

`String.format` v1: `{}` takes the next arg, `{n}` the nth, `{{` `}}` are the braces. `None` —
the house idiom for fallible String ops (`String.find`, `String.get`, `Nat.read`, `U32.read`) —
on a lone brace, an unclosed field, an index past `args`, `{}` mixed with `{n}` (Python's own
rule), or anything else inside a field. **No names, no `!r`, no `:spec` mini-language
(width/fill/type): future work**, said so in the def's comment.

## ttok per def (`ttok`, each chunk with its comments)

| def | ttok | def | ttok |
|---|---:|---|---:|
| String.nonempty_all (shared walker) | 111 | String.remove_prefix | 40 |
| Char.is_letter | 46 | String.remove_suffix | 40 |
| String.is_alpha | 23 | String.center | 103 |
| String.is_digit | 23 | String.swapcase | 65 |
| String.is_decimal | 32 | String.title (+ .go) | 109 |
| String.is_numeric | 17 | String.casefold | 27 |
| Char.is_alnum | 41 | String.expandtabs (+ .go) | 227 |
| String.is_alnum | 25 | String.rsplit (+ .push) | 112 |
| String.is_space | 54 | String.rpartition (+ .at) | 152 |
| String.is_lower | 57 | String.format (law, put, sub, field, step, go) | 744 |
| String.is_upper | 32 | | |
| Char.is_ascii + String.is_ascii | 69 | | |
| Char.is_printable + String.is_printable | 76 | | |
| Char.is_word + String.is_identifier | 107 | | |
| String.is_title (+ .go) | 138 | **total** | **2,470** |

Predicates 851, edits 875, format 744.

## Cap line

| file | before | final | cap | note |
|---|---:|---:|---|---|
| bend2/base.bend | 42,913 | 45,383 | 43,000 → **45,470** | raised by exactly the itemized 2,470 above; the 87 of prior headroom is unchanged, no margin added |
| bend2/comp.ts, bend.ts, main.ts, every test cap | — | — | held | untouched |

`gates/repo.ts` and `tests/caps.sh`: the one `base.bend` number each, nothing else (operator
exception). Ratio ins/del: 228/0 in base.bend — a pure build lane (tracked target ≥0.15 is
**missed**, by construction: nothing was superseded). **Debt row:** +2,470 base.bend, to be
retired by the next base.bend R-lane. Candidates met while here: `Char.is_letter` exists only
because `Char.is_alpha` takes `+c` and `~f: Char -> Bool` wants a linear argument — making
`Char.is_alpha` linear (a `match` on `Chr{+x}`) deletes the wrapper (−46); `String.to_upper`,
`to_lower`, `swapcase`, `copy` are four copies of one char-map walk.

## Oracle

`tests/strings/gaps_gen.py` **is** the fixture's source: it prints `tests/strings/gaps.bend`
whole, and every ASCII row's expectation is computed by CPython's own `str` method
(`isalpha` … `istitle`, `removeprefix`, `removesuffix`, `center`, `swapcase`, `title`,
`casefold`, `expandtabs`, `rsplit`, `rpartition`, `format`; a raised
`ValueError`/`IndexError`/`KeyError` is `None`). `run.sh` gained one check, `gaps [oracle]`,
which fails if the checked-in fixture and the generator disagree — so the fixture cannot drift
from Python. 126 oracle rows + 9 hand-written deviation rows; the 29 predicate rows each
carry all 12 predicates. The first full run agreed with Python on every row (my first `center` put the pad on the
wrong side; a smoke test caught it before the fixture existed), identically on interpret / JS / C.

## Deviations and disagreements with the brief

1. **`center`: the brief's "extra goes RIGHT, matching Python" is not what Python does.**
   CPython's rule is `left = pad/2 + (pad & width & 1)`: `'ab'.center(5,'*')` is `**ab*`
   (extra LEFT, width odd), `'a'.center(4,'-')` is `-a--` (extra right, width even). The two
   instructions conflict; the oracle wins — implemented CPython's rule, rows for both parities.
2. **`expandtabs`: the brief says lines split on `\n` only; Python also restarts the column at
   `\r`.** Implemented Python's (one extra `Bool.or`), since mechanical agreement is the
   evidence standard. Row `"a\r\tb"` pins it. Columns are code points, as in Python.
3. **`rsplit` takes a String separator, not a Char.** With no maxsplit, a Char `rsplit` is
   `String.split` exactly — a dead alias. It only differs from `split_on` on overlapping
   separators (`"aaa"` on `"aa"`: `["", "a"]` vs `["a", ""]`), so that is what it is:
   `split_on` scanning from the right. Empty separator: total, `[s]`, like `split_on`
   (Python raises).
4. **`rpartition`**: absent → `("", "", s)` as Python; the empty separator (Python raises)
   gives the same, mirroring `partition`'s totality.
5. **ASCII stance** (documented on the defs, pinned by deviation rows): `"é"` is not alpha /
   lower / printable / identifier; `"٣"` is not a digit; `title("éa")` is `"éA"` (Python
   `"Éa"`); `swapcase("ß")` is `"ß"` (Python `"SS"`). `is_printable` is U+0020..U+007E.
6. **`is_space`** is trim's set (U+0020, U+0009..U+000D). Python's `isspace` also accepts
   U+001C..U+001F; ours does not, to keep `is_space`, `trim` and `words` one definition.
7. **`is_identifier`** accepts keywords (`"if"`) — so does Python's `isidentifier`.
8. **`format`**: a `{n}` index is read by `U32.read`, so an index ≥ 2^32 is `None` (Python:
   `ValueError`, also an error). `{01}` is arg 1 and `{+1}` / `{ 0}` / `{-1}` are `None`, as
   Python.

## Found on the way

- **`Nat.read` does not finish in the interpreter lane.** `Nat.read("1")` was killed at a 20 s timeout under
  `bun bend2/main.ts` (its per-digit overflow guard divides 2^48 by 10 in unary); my first
  `format` used it and hung the fixture. `format` now uses `U32.read`. `Nat.read` itself is
  untouched (out of scope) — `tests/base/read_bounds.bend` presumably only meets it compiled.
  Worth an R-lane look.
- No forward references in `base.bend`: `String.format` lives after `U32.read`, not in the
  String section.
- `String.nonempty_all` is public-by-visibility but named for what it does (False on empty),
  so nobody mistakes it for a vacuous-truth `all`.

## Not in scope (per the brief)

`index`/`rindex` (`find`/`find_last` cover them under our failure model),
`translate`/`maketrans`, `encode`/`decode` (the IO layer owns UTF-8), `ljust`/`rjust`
(`pad_end`/`pad_start` exist), `maxsplit`, format specs.

## Verification (serial, this machine)

| suite | result |
|---|---|
| `bash tests/strings/run.sh` | **94 / 0** (was 89: + gaps check/interpret/js/c + oracle) |
| `bash tests/run.sh` (f64) | 19 / 0 |
| `bash tests/codex/run.sh` | 161 / 0, 0 suite errors |
| `bash tests/regex/run.sh` | 49 / 0 |
| `bash tests/caps.sh` | exit 0 |
| `python3 tests/strings/runtime.py` | ok |
| `bun gates/repo.ts` | PASS 45 / 45 |

Not run: `gates/test.ts` / `gates/perf.ts` (mini cluster), GPU lanes for `gaps` (it has no
`!(` parallel call, so `run.sh` does not schedule one), `bench.sh` (no existing op changed).
