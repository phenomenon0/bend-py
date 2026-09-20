# A certificate is forgeable data: Lint.verify recomputes every condition from
# the actual AST and contracts. Only `honest`, `granted` and `assumed` may prove;
# `assumed` shows the trust boundary: a contract is an assumption (SOUNDNESS A3).
import Base
import ../../demos/python/syntax.bend as S
import ../../demos/python/lexer.bend as L
import ../../demos/python/parser.bend as P
import ../../demos/python/lint.bend as Lint

def parse(s: String) -> Result<&2, &2, S.Error, S.Module>:
  do Result<&2, &2, S.Error, S.Module>:
    ts : List<&2, S.Tok> <- L.lex(s)
    P.parse(ts)

def run(+label: String, r: Result<&2, &2, S.Error, S.Module>, +cs: List<&2, Lint.Contract>, +w: List<&2, Lint.Rank>, +name: String) -> String:
  match r:
    case Fail{e}:
      label ++ ": " ++ S.error_text(e) ++ "\n"
    case Done{m}:
      label ++ ": " ++ Lint.show("m.py", Lint.verify(m, cs, w, name)) ++ "\n"

def honest() -> String:
  "def helper(s: str) -> str:\n    return s + s\n\ndef f(xs: list[str]) -> str:\n    acc = \"\"\n    for x in xs:\n        acc = acc + helper(x)\n    return acc\n"

def changed() -> String:
  "def helper(s: str) -> str:\n    while s:\n        pass\n    return s\n\ndef f(xs: list[str]) -> str:\n    acc = \"\"\n    for x in xs:\n        acc = acc + helper(x)\n    return acc\n"

def cycle() -> String:
  "def f(s: str) -> str:\n    return g(s)\n\ndef g(s: str) -> str:\n    return f(s)\n"

def self() -> String:
  "def f(s: str) -> str:\n    return f(s)\n"

def waits() -> String:
  "def f(s: str) -> str:\n    return wait(s)\n"

def prim() -> String:
  "def f(xs: list[str]) -> int:\n    return len(xs)\n"

def main() -> String:
  run("honest", parse(honest()), Lint.contracts(), [Lint.Rank{"helper", 0n}, Lint.Rank{"f", 1n}], "f") ++
  run("flipped ranks", parse(honest()), Lint.contracts(), [Lint.Rank{"helper", 1n}, Lint.Rank{"f", 0n}], "f") ++
  run("omitted callee", parse(honest()), Lint.contracts(), [Lint.Rank{"f", 1n}], "f") ++
  run("changed callee", parse(changed()), Lint.contracts(), [Lint.Rank{"helper", 0n}, Lint.Rank{"f", 1n}], "f") ++
  run("cycle", parse(cycle()), Lint.contracts(), [Lint.Rank{"g", 0n}, Lint.Rank{"f", 1n}], "f") ++
  run("self call", parse(self()), Lint.contracts(), [Lint.Rank{"f", 0n}], "f") ++
  run("ghost def", parse(honest()), Lint.contracts(), [Lint.Rank{"ghost", 0n}], "ghost") ++
  run("padded", parse(honest()), Lint.contracts(), [Lint.Rank{"helper", 0n}, Lint.Rank{"f", 1n}, Lint.Rank{"ghost", 0n}], "f") ++
  run("no certificate", parse(honest()), Lint.contracts(), [], "f") ++
  run("granted", parse(prim()), Lint.contracts(), [Lint.Rank{"f", 0n}], "f") ++
  run("no contract", parse(prim()), [], [Lint.Rank{"f", 0n}], "f") ++
  run("partial contract", parse(waits()), [Lint.Contract{"wait", 1n, True{}, False{}}], [Lint.Rank{"f", 0n}], "f") ++
  run("impure contract", parse(waits()), [Lint.Contract{"wait", 1n, False{}, True{}}], [Lint.Rank{"f", 0n}], "f") ++
  run("assumed", parse(waits()), [Lint.Contract{"wait", 1n, True{}, True{}}], [Lint.Rank{"f", 0n}], "f")
#|"honest: m.py:4:0-8:14 total Proven terminates on exact built-in arguments (T0)\nflipped ranks: m.py:4:0-8:14 total Refuted certificate refuted: f: callee helper holds no smaller rank\nomitted callee: m.py:4:0-8:14 total Refuted certificate refuted: f: callee helper holds no smaller rank\nchanged callee: m.py:6:0-10:14 total Refuted certificate refuted: helper: unbounded loop While at 2:4\ncycle: m.py:1:0-2:15 total Refuted certificate refuted: g: callee f holds no smaller rank\nself call: m.py:1:0-2:15 total Refuted certificate refuted: f: callee f holds no smaller rank\nghost def: m.py:? total Refuted certificate refuted: ghost: no unique def ghost\npadded: m.py:4:0-8:14 total Refuted certificate refuted: ghost: no unique def ghost\nno certificate: m.py:4:0-8:14 total Unknown no certificate\ngranted: m.py:1:0-2:18 total Proven terminates on exact built-in arguments (T0)\nno contract: m.py:1:0-2:18 total Refuted certificate refuted: f: unresolved call len at 2:11\npartial contract: m.py:1:0-2:18 total Refuted certificate refuted: f: contract of wait does not grant this call at 2:11\nimpure contract: m.py:1:0-2:18 total Refuted certificate refuted: f: contract of wait does not grant this call at 2:11\nassumed: m.py:1:0-2:18 total Proven terminates on exact built-in arguments (T0)\n"
