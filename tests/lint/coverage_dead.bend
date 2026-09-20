# M0 dead-case: duplicate constant, True after 1 (== overlap), wildcard after a
# full enumeration, a value outside the domain, a guarded shadow. w.py: CPython
# itself refuses a wildcard before other cases (SyntaxError); M0 agrees.
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
  "from typing import Literal\n\ndef dup(s: Literal[\"r\", \"w\"]) -> int:\n    match s:\n        case \"r\":\n            return 0\n        case \"w\":\n            return 1\n        case \"r\":\n            return 2\n\ndef overlap(b: bool) -> int:\n    match b:\n        case 1:\n            return 1\n        case True:\n            return 2\n        case False:\n            return 0\n\ndef late(b: bool) -> int:\n    match b:\n   " ++
    "     case True:\n            return 1\n        case False:\n            return 0\n        case _:\n            return 2\n\ndef outside(s: Literal[\"r\", \"w\"]) -> int:\n    match s:\n        case \"a\":\n            return 9\n        case \"r\" | \"w\":\n            return 0\n\ndef shadowed_guard(s: Literal[\"r\", \"w\"], c: bool) -> int:\n    match s:\n        case \"r\":\n            return 0\n        case \"r\" if c:\n           " ++
    " return 1\n        case \"w\":\n            return 2\n"

def wild() -> String:
  "def first(b: bool) -> int:\n    match b:\n        case _:\n            return 0\n        case True:\n            return 1\n"

def main() -> String:
  report("m.py", parse(src())) ++
  report("w.py", parse(wild()))
#|"m.py:4:4-10:20 exhaustive Proven every value of {'r', 'w'} reaches an unguarded case\nm.py:9:13-9:16 dead-case Proven no value of {'r', 'w'} reaches this case\nm.py:13:4-19:20 exhaustive Proven every value of {True, False} reaches an unguarded case\nm.py:16:13-16:17 dead-case Proven no value of {True, False} reaches this case\nm.py:22:4-28:20 exhaustive Proven every value of {True, False} reaches an unguarded case\nm.py:27:13-27:14 dead-case Proven no value of {True, False} reaches this case\nm.py:31:4-35:20 exhaustive Proven every value of {'r', 'w'} reaches an unguarded case\nm.py:32:13-32:16 dead-case Proven no value of {'r', 'w'} reaches this case\nm.py:38:4-44:20 exhaustive Proven every value of {'r', 'w'} reaches an unguarded case\nm.py:41:13-41:16 dead-case Proven no value of {'r', 'w'} reaches this case\nw.py:2:4-6:20 exhaustive Proven every value of {True, False} reaches an unguarded case\nw.py:5:13-5:17 dead-case Proven no value of {True, False} reaches this case\n"
