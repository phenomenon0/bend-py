# R0 local reachability: positive, negative, Unknown; finally is preserved.
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
  "def after_return(s: str) -> str:\n    return s\n    s = s + s\n\ndef branch(s: str) -> str:\n    if s:\n        return s\n    return s + s\n\ndef loops(xs: list[str]) -> str:\n    for x in xs:\n        if x:\n            continue\n            x = x + x\n        break\n        x = \"\"\n    return \"\"\n\ndef fin(s: str) -> str:\n    try:\n        raise ValueError(s)\n        s = \"\"\n    finally:\n        s = s + s\n    retur" ++
    "n s\n\ndef forever(s: str) -> str:\n    while True:\n        s = s + s\n    return s\n"

def main() -> String:
  report(parse(src()))
#|"m.py:1:0-3:13 total Proven terminates on exact built-in arguments (T0)\nm.py:3:4-3:13 unreachable Proven follows Return in the same block\nm.py:5:0-8:16 total Proven terminates on exact built-in arguments (T0)\nm.py:10:0-17:13 total Proven terminates on exact built-in arguments (T0)\nm.py:14:12-14:21 unreachable Proven follows Continue in the same block\nm.py:16:8-16:14 unreachable Proven follows Break in the same block\nm.py:19:0-25:12 total Unknown outside fragment: Try at 20:4\nm.py:22:8-22:14 unreachable Proven follows Raise in the same block\nm.py:27:0-30:12 total Unknown unbounded loop While at 28:4\nm.py:30:4-30:12 unreachable Unknown follows while True; break analysis is outside R0\n"
