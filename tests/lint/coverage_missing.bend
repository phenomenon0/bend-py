# M0 negatives: a missing value is Refuted with a recomputed counterexample; a
# value only guarded cases match is Unknown; a guarded duplicate is not dead.
import Base
import ../../demos/python/syntax.bend as S
import ../../demos/python/lexer.bend as L
import ../../demos/python/parser.bend as P
import ../../demos/python/lint.bend as Lint

def parse(s: String) -> Result<&2, &2, S.Error, S.Module>:
  do Result<&2, &2, S.Error, S.Module>:
    ts : List<&2, S.Tok> <- L.lex(s)
    P.parse(ts)

def report(+path: String, r: Result<&2, &2, S.Error, S.Module>) -> String:
  match r:
    case Fail{e}:
      S.error_text(e)
    case Done{m}:
      Lint.render(path, Lint.coverage(m))

def src() -> String:
  "from typing import Literal\n\ndef no_false(b: bool) -> int:\n    match b:\n        case True:\n            return 1\n    return 0\n\ndef no_w(s: Literal[\"r\", \"w\"]) -> int:\n    match s:\n        case \"r\":\n            return 0\n    return 1\n\ndef no_none(b: bool | None) -> int:\n    match b:\n        case True | False:\n            return 1\n    return 0\n\ndef guarded(b: bool, c: bool) -> int:\n    match b:\n        " ++
    "case True if c:\n            return 1\n        case False:\n            return 0\n    return 2\n\ndef guarded_dup(b: bool, c: bool) -> int:\n    match b:\n        case True if c:\n            return 1\n        case True:\n            return 2\n        case False:\n            return 0\n"

def main() -> String:
  report("m.py", parse(src()))
#|"m.py:4:4-6:20 exhaustive Refuted not exhaustive: False matches no case\nm.py:10:4-12:20 exhaustive Refuted not exhaustive: 'w' matches no case\nm.py:16:4-18:20 exhaustive Refuted not exhaustive: None matches no case\nm.py:22:4-26:20 exhaustive Unknown True reaches only guarded cases\nm.py:30:4-36:20 exhaustive Proven every value of {True, False} reaches an unguarded case\n"
