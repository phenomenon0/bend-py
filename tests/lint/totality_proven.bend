# T0 positive: for->fold, acyclic resolved calls, contracted primitives.
# Diagnostics arrive in span order, not in rule order.
import Base
import ../../demos/python/syntax.bend as S
import ../../demos/python/lexer.bend as L
import ../../demos/python/parser.bend as P
import ../../demos/python/lint.bend as Lint

def parse(s: String) -> Result<&2, &2, S.Error, S.Module>:
  do Result<&2, &2, S.Error, S.Module>:
    ts : List<&2, S.Tok> <- L.lex(s)
    P.parse(ts)

def report(r: Result<&2, &2, S.Error, S.Module>) -> String:
  match r:
    case Fail{e}:
      S.error_text(e)
    case Done{m}:
      Lint.render("m.py", Lint.analyze(m, Lint.contracts()))

def src() -> String:
  "\"\"\"Closed module: defs and a docstring only.\"\"\"\n\ndef shout(s: str, loud: bool) -> str:\n    return s + \"!\" if loud else s\n\ndef join(xs: list[str], sep: str) -> str:\n    acc = \"\"\n    for x in xs:\n        if acc == \"\":\n            acc = shout(x, False)\n        else:\n            acc = acc + sep + shout(x, len(x) > 3)\n    return acc\n\ndef longest(xs: list[str]) -> str | None:\n    best = None\n    for x i" ++
    "n sorted(xs):\n        if best is None or len(x) > len(best):\n            best = x\n    return best\n\ndef pairs(xs: list[str], ys: list[str]) -> list[str]:\n    out = []\n    for x in xs:\n        for y in ys:\n            if not x in out and x != y:\n                out = out + [join([x, y], \"-\")]\n    return out\n"

def main() -> String:
  report(parse(src()))
#|"m.py:3:0-4:33 total Proven terminates on exact built-in arguments (T0)\nm.py:6:0-13:14 total Proven terminates on exact built-in arguments (T0)\nm.py:15:0-20:15 total Proven terminates on exact built-in arguments (T0)\nm.py:22:0-28:14 total Proven terminates on exact built-in arguments (T0)\n"
