# M0 exhaustive Proven: bool, bool | None, Literal strs and ints, wildcard, capture,
# or- and as-patterns, case 1/0 on bool (== overlap), nested matches.
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
  "from typing import Literal\n\ndef flag(b: bool) -> int:\n    match b:\n        case True:\n            return 1\n        case False:\n            return 0\n\ndef maybe(b: bool | None) -> int:\n    match b:\n        case None:\n            return 0\n        case True | False:\n            return 1\n\ndef mode(s: Literal[\"r\", 'w']) -> int:\n    match s:\n        case \"r\":\n            return 0\n        case 'w':\n      " ++
    "      return 1\n\ndef rest(s: Literal[\"r\", \"w\", \"a\"]) -> int:\n    match s:\n        case \"r\":\n            return 0\n        case _:\n            return 1\n\ndef nums(b: bool) -> int:\n    match b:\n        case 1:\n            return 1\n        case 0:\n            return 0\n\ndef signs(n: Literal[-1, 0, 1]) -> int:\n    match n:\n        case -1 | 0 as small:\n            return small\n        case other:\n        " ++
    "    return other\n\ndef opt(s: Literal[\"a\"] | None) -> int:\n    match s:\n        case (None as n):\n            return 0\n        case \"a\":\n            return 1\n\ndef nested(a: bool, b: bool) -> int:\n    match a:\n        case True:\n            match b:\n                case True:\n                    return 3\n                case False:\n                    return 2\n        case False:\n            return " ++
    "0\n"

def main() -> String:
  report("m.py", parse(src()))
#|"m.py:4:4-8:20 exhaustive Proven every value of {True, False} reaches an unguarded case\nm.py:11:4-15:20 exhaustive Proven every value of {True, False, None} reaches an unguarded case\nm.py:18:4-22:20 exhaustive Proven every value of {'r', 'w'} reaches an unguarded case\nm.py:25:4-29:20 exhaustive Proven every value of {'r', 'w', 'a'} reaches an unguarded case\nm.py:32:4-36:20 exhaustive Proven every value of {True, False} reaches an unguarded case\nm.py:39:4-43:24 exhaustive Proven every value of {-1, 0, 1} reaches an unguarded case\nm.py:46:4-50:20 exhaustive Proven every value of {'a', None} reaches an unguarded case\nm.py:53:4-61:20 exhaustive Proven every value of {True, False} reaches an unguarded case\nm.py:55:12-59:28 exhaustive Proven every value of {True, False} reaches an unguarded case\n"
