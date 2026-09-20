# A coverage certificate is forgeable data: Lint.exhaustive and Lint.dead_case
# recompute M0 membership, the domain and every claimed case from the AST; one
# bad claim refutes the whole witness. Arms count from 0; `here` is "line:col".
import Base
import ../../demos/python/syntax.bend as S
import ../../demos/python/lexer.bend as L
import ../../demos/python/parser.bend as P
import ../../demos/python/lint.bend as Lint

def parse(s: String) -> Result<&2, &2, S.Error, S.Module>:
  do Result<&2, &2, S.Error, S.Module>:
    ts : List<&2, S.Tok> <- L.lex(s)
    P.parse(ts)

def run(+label: String, r: Result<&2, &2, S.Error, S.Module>, +w: List<&2, Lint.Claim>, +here: String) -> String:
  match r:
    case Fail{e}:
      label ++ ": " ++ S.error_text(e) ++ "\n"
    case Done{+m}:
      label ++ ": " ++ Lint.show("m.py", Lint.exhaustive(m, w, here)) ++ "\n"

def dead(+label: String, r: Result<&2, &2, S.Error, S.Module>, +w: List<&2, Lint.Claim>, +here: String, +n: Nat) -> String:
  match r:
    case Fail{e}:
      label ++ ": " ++ S.error_text(e) ++ "\n"
    case Done{+m}:
      label ++ ": " ++ Lint.show("m.py", Lint.dead_case(m, w, here, n)) ++ "\n"

def honest() -> String:
  "def flag(b: bool, c: bool) -> int:\n    match b:\n        case True if c:\n            return 2\n        case True:\n            return 1\n        case False:\n            return 0\n        case False:\n            return 3\n"

def changed() -> String:
  "def flag(b: bool, c: bool) -> int:\n    match b:\n        case True if c:\n            return 2\n        case True:\n            return 1\n        case None:\n            return 0\n        case False:\n            return 3\n"

def rebound() -> String:
  "def flag(b: bool, c: bool) -> int:\n    b = not b\n    match b:\n        case True if c:\n            return 2\n        case True:\n            return 1\n        case False:\n            return 0\n        case False:\n            return 3\n"

def partial() -> String:
  "def flag(b: bool) -> int:\n    match b:\n        case True:\n            return 1\n    return 0\n"

def main() -> String:
  run("honest", parse(honest()), [Lint.Covers{"2:4", "True", 1n}, Lint.Covers{"2:4", "False", 2n}], "2:4") ++
  run("omitted value", parse(honest()), [Lint.Covers{"2:4", "True", 1n}], "2:4") ++
  run("wrong case", parse(honest()), [Lint.Covers{"2:4", "True", 2n}, Lint.Covers{"2:4", "False", 2n}], "2:4") ++
  run("guarded case", parse(honest()), [Lint.Covers{"2:4", "True", 0n}, Lint.Covers{"2:4", "False", 2n}], "2:4") ++
  run("outside the domain", parse(honest()), [Lint.Covers{"2:4", "True", 1n}, Lint.Covers{"2:4", "False", 2n}, Lint.Covers{"2:4", "None", 1n}], "2:4") ++
  run("no such case", parse(honest()), [Lint.Covers{"2:4", "True", 1n}, Lint.Covers{"2:4", "False", 9n}], "2:4") ++
  run("forged miss", parse(honest()), [Lint.Covers{"2:4", "False", 2n}, Lint.Miss{"2:4", "True"}], "2:4") ++
  run("honest miss", parse(partial()), [Lint.Covers{"2:4", "True", 0n}, Lint.Miss{"2:4", "False"}], "2:4") ++
  run("no certificate", parse(honest()), [], "2:4") ++
  run("elsewhere only", parse(honest()), [Lint.Covers{"99:0", "True", 1n}, Lint.Covers{"99:0", "False", 2n}], "2:4") ++
  run("stray claim", parse(honest()), [Lint.Covers{"2:4", "True", 1n}, Lint.Covers{"2:4", "False", 2n}, Lint.Covers{"99:0", "True", 1n}], "2:4") ++
  run("changed case", parse(changed()), [Lint.Covers{"2:4", "True", 1n}, Lint.Covers{"2:4", "False", 2n}], "2:4") ++
  run("rebound subject", parse(rebound()), [Lint.Covers{"3:4", "True", 1n}, Lint.Covers{"3:4", "False", 2n}], "3:4") ++
  dead("honest dead", parse(honest()), [Lint.Dead{"2:4", 3n}], "2:4", 3n) ++
  dead("live case", parse(honest()), [Lint.Dead{"2:4", 2n}], "2:4", 2n) ++
  dead("guarded duplicate", parse(honest()), [Lint.Dead{"2:4", 1n}], "2:4", 1n) ++
  dead("bad companion", parse(honest()), [Lint.Dead{"2:4", 3n}, Lint.Covers{"2:4", "True", 0n}], "2:4", 3n) ++
  dead("changed dead", parse(changed()), [Lint.Dead{"2:4", 3n}], "2:4", 3n) ++
  dead("no certificate", parse(honest()), [], "2:4", 3n)
#|"honest: m.py:2:4-10:20 exhaustive Proven every value of {True, False} reaches an unguarded case\nomitted value: m.py:2:4-10:20 exhaustive Refuted certificate refuted: no case claimed for False\nwrong case: m.py:2:4-10:20 exhaustive Refuted certificate refuted: claim at 2:4: case 2 does not match True\nguarded case: m.py:2:4-10:20 exhaustive Refuted certificate refuted: claim at 2:4: case 0 is guarded\noutside the domain: m.py:2:4-10:20 exhaustive Refuted certificate refuted: claim at 2:4: None is not in the domain\nno such case: m.py:2:4-10:20 exhaustive Refuted certificate refuted: claim at 2:4: no case 9\nforged miss: m.py:2:4-10:20 exhaustive Refuted certificate refuted: claim at 2:4: case 0 matches True\nhonest miss: m.py:2:4-4:20 exhaustive Refuted not exhaustive: False matches no case\nno certificate: m.py:2:4-10:20 exhaustive Unknown no certificate\nelsewhere only: m.py:2:4-10:20 exhaustive Unknown no certificate\nstray claim: m.py:2:4-10:20 exhaustive Refuted certificate refuted: claim at 99:0: no match statement there\nchanged case: m.py:2:4-10:20 exhaustive Refuted certificate refuted: claim at 2:4: case 2 does not match False\nrebound subject: m.py:3:4-11:20 exhaustive Refuted certificate refuted: claim at 3:4: b is rebound in the def\nhonest dead: m.py:9:13-9:18 dead-case Proven no value of {True, False} reaches this case\nlive case: m.py:7:13-7:18 dead-case Refuted certificate refuted: claim at 2:4: False reaches case 2\nguarded duplicate: m.py:5:13-5:17 dead-case Refuted certificate refuted: claim at 2:4: True reaches case 1\nbad companion: m.py:9:13-9:18 dead-case Refuted certificate refuted: claim at 2:4: case 0 is guarded\nchanged dead: m.py:9:13-9:18 dead-case Refuted certificate refuted: claim at 2:4: False reaches case 3\nno certificate: m.py:9:13-9:18 dead-case Unknown no certificate\n"
