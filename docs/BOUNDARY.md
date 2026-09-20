# Ownership boundary — Core · Toolchain (ours) · Materials (2026-09-19)

The distinction (operator's call, this date): **not everything we build belongs to
Bend's core.** Language-level features land in `bend2/**` (core-style, cap- and
battery-gated, upstream offer open). Everything Python-facing is **ours** — a
library we own; Bend users are not burdened with it; if Bend wants it later, we
can offer it then. Materials sit outside the repo entirely.

## Zone A — CORE (`bend2/**`): the language, runtime, stdlib
Ours-worth-having, already landed in the fork:
- **Strings** — views, adaptive width, code points (`comp.ts` + `base.bend`).
- **Streaming** — `File.read_text` + `Utf8.Dec` carries (flat ~2.3 MiB).
- **Sockets text** — `TCP.recv` decode-carry (`bend2/effs/`).
- **Regex** — native Pike VM (`comp.ts`) + stdlib API (`base.bend`).

Policy: language-level only; no Python-specific anything; every addition capped
(`tests/caps.sh` + `gates/repo.ts`) and battery-gated; upstream = Taelin's call
(PR #795 precedent — offered, closed, fine). Parked follow-ups live here too:
mixed-width packing, `File.fold_text` (floor 43,334 > held cap; waits).

## Zone B — TOOLCHAIN ("ours", package-in-waiting): Python ⇄ Bend
Everything Python-facing — read, check, port:
- `demos/python/**` — lexer, parser, unicode tables, fstring, `lint.bend`,
  `translate.bend`, SOUNDNESS.md (the whole Python bridge).
- `tests/{parser,lint,translator}/**` — its suites; the judge/differential
  methodology; the four-lane discipline applied to it.
- `docs/omen/**` — governance/reports for both zones.

Policy: **we own it**; no upstream obligation; deliberately *not* native-Bend
concerns (nobody needs Python's grammar or Unicode NAME tables in a language
core). It lifts out to a separate repo cleanly — its dependencies are enumerated
(the parser wire format, base.bend APIs it consumes, the runner shapes). If Bend
wants it, we offer; until then it stays our package, versioned by lane reports.

## Zone C — MATERIALS: outside the repo
Video kit, reports, corpora (`~/videokit-corpus`, `~/libscout/`), scouts,
benches. Rule of record: artifacts under `$HOME`, dated, no `/tmp`.

## Placement audit (today)
| path | zone |
|---|---|
| `bend2/**` (base, comp, effs, pack) | A — capped, battery-gated |
| `demos/python/**`, `tests/{parser,lint,translator}/**` | B — ours |
| `demos/{text,text_stream,parallel,regex,strings_tour}/**` | B — showcase, lifts with the package |
| `power/**`, `tests/power/**` | B — the power-tools library: pure Bend over Base, never in `base.bend`; each primitive held to a CPython oracle on four lanes (`tests/power/run.sh`) |
| `tests/{f64,strings,regex,codex}/**` | A-adjacent — core feature suites |
| `docs/omen/**`, `gates/**` | governance — stays in the fork |
| video-kit, libscout, corpora | C — outside |

## Open items under this boundary
- Optimization layer (`optimize.bend`) = Zone B. L4 = Zone B.
- If a Zone B piece ever hardens into a general primitive (e.g., a text-cursor
  API), the CORE pull-request is a separate, deliberate act — never a merge
  side-effect.
