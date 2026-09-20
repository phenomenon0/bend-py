# Stub pass #1 — report (opus, 2026-09-20)

Branch `lane-stubs1`, worktree `bend-work-stubs1`, off `omen` @ `0efa5e7a` (post-T5).
The brief is `docs/omen/plans/stubs1-brief.md`: certify as many real `llm-wiki` tools defs as the
fragment honestly allows, with **reviewed type stubs** where the header is the only thing missing.

**The brief's premise did not survive contact.** The census read "80% of `llm-wiki`'s 45 defs refuse
on *missing or non-builtin annotation*" as *types are the gate*. That is a **first-error** view: the
header is checked before the body, so an unannotated def reports its header and stops. Probed
properly — annotation stripped in a throwaway copy, `import re` offered, all four fragment types
tried — `llm-wiki` yields **three** certifiable defs, and all three are already demos
(`normalize_stem`, `overview.repo_of`, `synapse.fm_sources`). **Zero new.** Not one of the other 40
is gated by its types: every one dies in its body. The refusal table below is that result, and it is
the lane's first deliverable.

So the stub work was done, at the same standard, on a wider corpus (deviation 1): **11,042 Python
files** across the Project tree, 480 unique in-fragment candidates, **33 certify**, **ten** are
certified here as judge demos.

Semantic pin: CPython 3.11.15. Acceptance: `bash tests/translator/run.sh` → **Translator PASS: 40, FAIL: 0**, and all seventeen judge demos green (the existing seven, byte-identical and re-run rather than re-pinned, plus the ten below).
Repo gate: `bun gates/repo.ts` → **PASS: 53 / 53**.

Untouched, as instructed: `bend2/**`, `gates/**`, `tests/caps.sh`, `demos/python/**`. No cap moved,
no gate edited, no push.

## Slices

| slice | commit | content |
|---|---|---|
| triage + the ten | `9e0f7b53` | `tests/translator/demos_stubs1.py` (new), `judge.py` wiring + the refusal control on the stub + the `Bool` renderer, `run.sh` runs the ten, `.gitignore` gains `__pycache__/` |
| report | this commit | `docs/omen/lanes/stubs1.md`, and the brief it was executed from |

## The refusal table (`llm-wiki` tools, all 43 top-level defs)

The probe: compile `demos/python/translate.bend` once to `/tmp/tr`, then one run per def with
`PY_SOURCE`/`PY_DEF` (≈0.15 s each). For a def whose header is annotated or defaulted, the probe
strips the header **in a copy** and retries with each of the four fragment types and with
`import re` — a copy, never a claim, because a stub cannot override an existing annotation
(`translate.bend:1283`, "a signature is given: the source header must be plain and unannotated").
What is recorded below is therefore the **body's** first refusal, not the header's.

| class | defs | what it is |
|---|---:|---|
| outside the fragment | 28 | `Dict` / `Tuple` / `Call` / `Raise` / `Attribute` / statement `Assign`\|`Expr`\|`Try` — sqlite3, subprocess, `Path`, `json`, `argparse`, f-strings with calls |
| unresolved module global | 7 | `SLUGS`, `H1_RE`, `FRONTMATTER_RE`, `sqlite3` ×4 — the fragment resolves `re` (by a checked `import re`) and nothing else |
| decorated / non-simple header | 2 | `git` ×2: `*args` — no stub can name the parameters |
| loop shape | 2 | `harvest`, `build_frontmatter`: "the body must assign exactly one name bound before the loop" |
| truthiness of a non-bool | 1 | `wiki._repo_of` at 2:11 — `if not page_id`, and that is its **only** blocker |
| no contract for the call | 1 | `find_stub_pages`: `.execute` on a String |
| **certified** | **3** | `normalize_stem`, `overview.repo_of`, `synapse.fm_sources` — all already demos |

**Not one refusal is an annotation refusal.** The 9 partially annotated defs in `wiki.py` were
re-probed with their headers stripped and every one still failed in its body, so the
"plain and unannotated" rule cost this lane exactly **zero** certifiable defs (inherit item 2).

Per def, first refusal (file, line, def):

| def | class | first refusal |
|---|---|---|
| `freshcheck.git` 28, `ingest.git` 29 | header | `*args` — no stub can name them |
| `freshcheck.chat` 35, `ingest.chat` 55, `synapse.chat` 42 | fragment | `Dict` at 2:11 |
| `freshcheck.check_repo` 45 | fragment | `Call` at 2:11 |
| `freshcheck.main` 149, `synapse.main` 90 | fragment | `Attribute` at 2:18 / 2:21 |
| `ingest.harvest` 33, `wiki.build_frontmatter` 151 | loop | the for-body assigns more than the accumulator |
| `ingest.parse_plan_json` 81 | fragment | statement `Raise` at 5:8 |
| `ingest.main` 105 | fragment | statement `Assign` at 2:4 |
| **`overview.repo_of` 15** | — | **certified** (stub `(pid: str, slugs: list[str]) -> str \| None`) |
| `overview.main` 26, `wiki.cmd_bridges` 1199, `wiki.main` 1221 | fragment | `Call` |
| `synapse.repo_of` 66 | global | `SLUGS` at 6:13 |
| **`synapse.fm_sources` 77** | — | **certified** (stub `(text: str) -> list[str]` + `import re`) |
| **`wiki.normalize_stem` 92** | — | **certified** (annotated in source) |
| `wiki.git_hash_object` 97 | fragment | statement `Try` at 3:4 |
| `wiki.parse_frontmatter` 109 | global | `FRONTMATTER_RE` at 6:8 |
| `wiki.extract_h1` 171 | global | `H1_RE` at 3:8 |
| `wiki.extract_sections` 177 | fragment | `Call` at 7:12 |
| `wiki.find_stub_pages` 200 | contract | `.execute` on a String at 6:10 |
| `wiki.init_db` 215, `clear_index` 271, `index_vault` 285 | fragment | statement `Expr` at 3:4 |
| `wiki.cmd_migrate` 474, `cmd_search` 589, `cmd_read` 677, `cmd_context` 746, `cmd_patch` 804, `cmd_lint` 934 | fragment | `Call` at 3:12 / 3:14 |
| `wiki._fm_parse` 1005, `_src_map` 1119 | fragment | `Dict` |
| `wiki._fm_parse2` 1025, `_repo_slugs` 1034 | fragment | `Call` |
| `wiki._repo_of` 1044 | truthiness | `if not page_id` at 2:11 — nothing else |
| `wiki._resolve_id` 1055 | fragment | `Tuple` at 2:58 |
| `wiki.cmd_graph` 1065, `cmd_paths` 1085, `cmd_code` 1149, `cmd_hubs` 1188 | global | `sqlite3` |

## The ten

Every one is **mined** from a real program, extracted by `ast` (its module is never imported or
executed) and pinned by sha256; six were unannotated and carry a reviewed stub as `sig`, four are
annotated in their own source. All ten pass C1 + C2 on the four lanes with their controls.

| def | source | claim | fixtures | C2 | what it exercises |
|---|---|---|---:|---|---|
| `escape_path` | `instant-ngp/dependencies/tinyexr/kuroga.py:83` · `771bba52cd7791f2` | stub `(word: str) -> str` | 7 + 20 + 160 = **187** | 187/187 ×3 | three chained `.replace`, and the order is the contract: the `'$ '` pass runs first so the `$` it writes is not escaped again |
| `upgrade_tumblr_url` | `archi-lab/src/enrich/match_and_download_hq.py:61` · `97b387d3c65373e3` | as written `(url: str) -> str` | 8 + 14 + 160 = **182** | 182/182 ×3 | an early `return` inside a `for` over a literal list — a Step fold (Continue/Stop), then a match on the Maybe for the fall-through |
| `sc_feas_class` | `footydata/docs/site/build_ideas.py:271` · `84d9214c6e05e9ab` | stub `(f: str) -> str` | 8 + 14 + 160 = **182** | 182/182 ×3 | assign-to-a-parameter as a rebinding let, then two `if`s on `String.eq` with a fall-through |
| `is_unet_key` | `kohya_ss/sd-scripts/tools/merge_models.py:13` · `32bb6b256534a139` | stub `(key: str) -> bool` | 7 + 14 + 160 = **181** | 181/181 ×3 | `not (a or b or c)` — `Bool.not` over two nested matches; the or-chain's short circuit *is* the match |
| `make_word_regex` | `ipad-lab/.../llvm/utils/lit/lit/util.py:38` · `db00f5c2f2c20c08` | stub `(word: str) -> str` | 6 + 14 + 160 = **180** | 180/180 ×3 | two `String.append`s of one raw literal; no call site in `lit/`, so the claim is defended from the body alone |
| `string_begins_with` | `Maestro/app/models/TTS/index_tts2/utils/xtransformers.py:97` · `3eae7a30aaaa82e8` | stub `(prefix: str, str: str) -> bool` | 7 + 14 + 160 = **181** | 181/181 ×3 | a parameter *named* `str`, shadowing the builtin — the stub has to name it the same way |
| `is_remote_or_virtual_path` | `img2threejs/forge/stage4_review/append_review.py:66` · `0ffcafa7f5e77a32` | as written `(value: str) -> bool` | 8 + 14 + 160 = **182** | 182/182 ×3 | `a or b or c` as two nested matches, mixing `.__contains__` and `.startswith` |
| `safe_name` | `Richiebot-m7/scripts/batch_gemini_ocr.py:26` · `dbe911413c3f23ae` | stub `(pdf_name: str) -> str` | 7 + 14 + 160 = **181** | 181/181 ×3 | five chained `.replace`; the same body is copied into three files in that repo and this is the one with call sites |
| `esc` | `voice-clone-lab/.../richie-compare-2026-09-08/build_page.py:97` · `7d28c6549e007328` | as written `(s: str) -> str` | 6 + 14 + 160 = **180** | 180/180 ×3 | HTML escaping, order-critical: `&` first, or the `&lt;` it writes is escaped again |
| `canon_bool` | `glyph/py/glyph/loose.py:97` · `24a41ad9b22c5c86` | as written `(v: bool) -> str` | 2 + 2 + 160 = **164** | 164/164 ×3 | a `bool` **parameter** and a conditional expression; the domain is `{True, False}`, so the fixtures exhaust it |

All ten are also run with `--optimize` and all ten report **C4 no step · identical**: not one
optimizer rule fires on any of them. `repo_of` (`C4 1 step Proven (law starts_append)`) remains the
only demo in the battery that rewrites. That is a measurement of the rule set against real code,
not a defect — see inherit item 6.

## A stub is a reviewed claim, and the kernel checks it

The judge already refused a mutated **body**. It could not refuse a mutated **claim**, because
`refuse` only ever substituted in the Python. Four lines in `judge.py` fix that: a refusal control
whose `old` is in the demo's `sig` edits the stub instead, and `emit` takes the mutated text. The
reviewed claim is now the thing under test wherever it lives — the stub for six of the ten, the
source's own header for the other four — and each control is a **single type**, changed once:

| def | claim | edit | the kernel's answer |
|---|---|---|---|
| `escape_path` | stub | `word: str` → `word: bool` | `no verified contract for .replace on (Bool) with (String;String;) at 2:11` |
| `upgrade_tumblr_url` | source header | `url: str` → `url: bool` | `no verified contract for .__contains__ on (Bool) with (String;) at 3:7` |
| `sc_feas_class` | stub | `f: str` → `f: bool` | `no verified contract for .lower on (Bool) with () at 2:8` |
| `is_unet_key` | stub | `-> bool` → `-> str` | `type mismatch: (Bool) where (String) is expected at 3:4` |
| `make_word_regex` | stub | `-> str` → `-> bool` | `type mismatch: (String) where (Bool) is expected at 2:4` |
| `string_begins_with` | stub | `-> bool` → `-> str` | `type mismatch: (Bool) where (String) is expected at 2:4` |
| `is_remote_or_virtual_path` | source header | `-> bool` → `-> str` | `type mismatch: (Bool) where (String) is expected at 2:4` |
| `safe_name` | stub | `pdf_name: str` → `pdf_name: bool` | `no verified contract for .replace on (Bool) with (String;String;) at 2:11` |
| `esc` | source header | `-> str` → `-> bool` | `type mismatch: (String) where (Bool) is expected at 2:4` |
| `canon_bool` | source header | `v: bool` → `v: str` | `truthiness of a non-bool is outside the fragment at 3:18` |

None of these is caught by a type-checker downstream: the emission simply does not happen, and the
diagnostic carries the position in the **Python** where the claim broke.

## The stubs that were refused

The brief's rule — *"if the types cannot be defended from the body and its call sites, refuse the
def. Silence over guessing."* — cost five defs that the translator would have accepted:

| def | the stub that certifies | why it is a lie |
|---|---|---|
| `Maestro/app/wgp.py:11234 all_letters` | `(source_str: str, letters: list[str]) -> bool` | **every call site passes a `str`**: `all_letters(audio_prompt_type, "AB")`, `all_letters(video_prompt_type, "IK")`, `all_letters(src, pos)`. CPython iterates the str as characters; the fragment has no `for c in str`, so the only stub that certifies is the one the callers contradict |
| `Maestro/app/wgp.py:11240 any_letters` | same | same, same file |
| `Maestro/app/wgp.py:11262 del_in_sequence` | `(source_str: str, letters: list[str]) -> str` | same: `del_in_sequence(audio_prompt_type, "N")`, `del_in_sequence(video_prompt_type, "IK")`. A shame — its guard reads `source_str` while its accumulator is `ret`, and the two differ when a removal *creates* a later needle |
| `ComfyUI/comfy/diffusers_convert.py:188 convert_text_enc_state_dict` | `(text_enc_dict: str) -> str` | the body is `return text_enc_dict` and certifies under any type; the parameter is a state dict |
| `LAM_Audio2Expression/.../lovasz.py:183 isnan` | `(x: str) -> bool` | `x != x` certifies as String equality; `x` is a float/tensor, and the def exists *because* NaN breaks reflexivity — which `String.eq` does not |

Two more certify and were left out as padding, not as lies: `no_recompile` (returns the constant
`True`) and `expand_numbers` (an identity with a `TODO`). Certifying either would prove nothing.

## Certifiable, not demoed

Ten was the target and ten are certified; these twelve also pass the probe and are the next pass's
free pickings (no new mechanism needed, only fixtures and review):

`is_visible`, `is_trash_name`, `keep_line`, `is_path`, `lowercase`, `get_short_name`,
`parse_page_id`, `safe_dirname`, `mask_context`, `done`, plus `no_recompile` and `expand_numbers`
above. `generate_manifest.py:345 safe_name` is a byte-for-byte copy of the demoed one in a second
file (three copies of that body exist in that repo; only one has call sites).

## The module that isn't (the brief's item 4)

The brief: *"2–3 defs that call each other, with a T5 fact crossing if it arises naturally — if not,
say so and skip it."* **It does not arise. Skipping it.** That is a measured result, not a guess:

- 146 same-file caller/callee groups where **every** def in the group passes the in-fragment
  pre-filter, probed through the module door (`PY_DEF=""`) with a stub search per def: **0 emit.**
- 461 same-file callers of the **33 defs that certify**, probed the same way: **0 emit.**

607 groups, no module. The callers fail where their callees do not: `statement Assign` (a caller
almost always binds the result before using it, and multi-statement bodies leave the fragment),
`Call` on something else in the same expression, `BinOp` on ints, `Tuple` returns. The shape T5
needs — callee returns a carried literal, caller binds it with `v = g(x)` and then guards on it — is
what `page_tail` had to be **written** for. The door is open (`opt_module.bend` proves the
optimizer's half); the corpus has not walked through it.

## Tests

| file | rows | what |
|---|---|---|
| `tests/translator/demos_stubs1.py` | new | the ten demos: path, sha256 pin, reviewed stub, literal examples, contract edges, a seeded generator, a C2 control and a refusal control each |
| `tests/translator/judge.py` | +33 −6 | the refusal control may edit the `sig`; `harness` can print a `Bool`; `sh()` sets `BEND_NO_TELEMETRY=1` |
| `tests/translator/run.sh` | +7 −1 | the ten, each with `--optimize`, after the existing seven |
| the seven existing demos | — | untouched and re-run, not re-pinned |

## Measurements

| file | bytes | ttok | cap | note |
|---|---:|---:|---:|---|
| `tests/translator/demos_stubs1.py` | 17,793 | 4,913 | 16,000 | new; `tests/(regex\|parser\|lint\|translate\|translator)/**` allow row, no gate edit |
| `tests/translator/judge.py` | 51,479 | 14,450 | 16,000 | **the file to watch** — 90% of its cap. The ten demos are in their own file for exactly this reason |
| `tests/translator/run.sh` | 4,993 | 1,519 | 16,000 | |
| `docs/omen/lanes/stubs1.md` | 21,143 | 6,270 | 16,000 | |
| `docs/omen/plans/stubs1-brief.md` | 2,852 | 764 | 16,000 | the brief, committed with the report |

## Deviations

1. **The corpus is the Project tree, not `llm-wiki`.** The brief scopes the mission to `llm-wiki`
   tools. `llm-wiki` is exhausted: 3 certifiable defs, all already demos, 0 new — see the refusal
   table, which is delivered in full as the brief asks. To deliver the brief's *point* (ten honest
   certificates) the mine was widened to 11,042 files under `~/Documents/Project`, same discipline:
   mined, sha256-pinned, reviewed stub, four lanes, controls.
2. **The premise is corrected, not worked around.** "80% refuse on missing annotation" is a
   first-error artifact of checking the header before the body. Reviewed types are *not* the gate;
   the body's statement and expression coverage is. Recorded here because the next brief should not
   be written from the census's first-error view.
3. **`judge.py` grew by 33 lines against 6** (+294 ttok, to 90% of cap). The demos themselves are in a
   new file; the wiring (`DEMOS.update`), the `sig`-refusal control and the `Bool` renderer
   (deviation 10) could not be.
4. **`BEND_NO_TELEMETRY=1` in the harness.** The repo is `bend 2.0.17`; upstream published `2.0.21`,
   so `bend2/main.ts:158`'s daily check prints `bend 2.0.21 is available: run bend update` on
   **stderr** — and the judge's `sh()` folds stderr into the emitted file, which then fails to parse
   in every lane. This is machine state, not a lane change: the translator battery is red today for
   anyone on this machine, with or without this lane. `gates/ping.ts:216` already sanctions the flag
   ("BEND_NO_TELEMETRY=1 asks nothing and writes no cache"), so `sh()` and `run.sh` set it. A test
   harness must not have a network notice in its artifacts.
5. **`int` is still refused**, so arithmetic defs never reached the stub stage. `translate.bend:1199`
   states why ("a Python int is unbounded and signed, and no contract here reads one from a
   parameter"), and the mine honoured it: every numeric candidate was dropped before review.
6. **`string_begins_with` names a parameter `str`.** The stub must shadow the builtin exactly as the
   source does. `elaborate_def` refuses a def that binds `re` or `len`; `str` is not on that list,
   and the demo is the evidence that it does not need to be.
7. **`make_word_regex` has no call site.** Its claim is defended from the body alone — `+` against a
   `str` literal forces both the parameter and the return — and the report says so rather than
   implying a call site was read.
8. **Item 4 is skipped**, with 607 probed groups as the reason (above), not a shrug.
9. **The fixture counts differ per demo** (164 to 187): `canon_bool`'s domain is two values, so its
   "160 generated" are drawn from a two-element set and its C2 is exhaustive. Said in its C3 rather
   than dressed up as a bigger number.
10. **The judge harness could not print a `Bool`.** Three of the ten return `bool` and no demo
    before them did: `harness` rendered a `String`, a `List<&2, String>` or a `Maybe`, so a bool
    result crashed the judge (`TypeError: 'bool' object is not iterable`) before any Bend ran.
    Fourteen lines add a `flag` renderer (`True{}` → `"1|"`, `False{}` → `"0|"`), selected off the expected
    values exactly as `listed` already is. The translator emitted all three correctly on the first
    attempt; the gap was entirely in the oracle-comparison harness.

## What the next stub pass inherits

1. **Module-global constants are the single highest-value gap.** Seven `llm-wiki` defs — and the
   most interesting ones, `synapse.repo_of`, `parse_frontmatter`, `extract_h1` — refuse only on
   `unresolved name SLUGS` / `H1_RE` / `FRONTMATTER_RE`. The fragment resolves exactly one global,
   `re`, through a checked `import re`. A reviewed **constant** door (a pinned literal or a pinned
   compiled pattern, checked like `imports_re` checks the import) would convert them in a batch.
   Note `find_stub_pages` and the `cmd_*` family would not follow: they need sqlite3.
2. **The "plain and unannotated" stub rule costs nothing today** — every partially annotated
   `wiki.py` def fails in its body with the header stripped — so it is an inherit item, not a
   blocker. Revisit only if a def appears whose *only* problem is a wrong annotation.
3. **`wiki._repo_of` is one rule away.** Its only refusal is `truthiness of a non-bool` at 2:11
   (`if not page_id`). A guarded `if not <str>` → `String.is_empty` rule would certify it, and it is
   a real function with real call sites.
4. **Twelve certifiable defs are sitting there** (above) — fixtures and review, no new mechanism.
5. **The module needs a produced fact, and the corpus does not produce one.** 607 groups, zero
   modules. Either a rule that widens what a caller may do between the call and the guard
   (`statement Assign` is the wall), or accept that `page_tail`-shaped demos are written, not mined.
6. **The optimizer's rules do not fire on real code.** Ten mined defs, all under `--optimize`, all
   `C4 no step · identical`; the one rewriting demo in the battery (`repo_of`, `law starts_append`)
   is one this repo wrote. The proven surface this lane was asked to enlarge is now ten defs wider,
   and the optimization run that follows it has ten more programs to be measured against — but it
   should expect to need **new rules**, not more inputs for the existing three.
