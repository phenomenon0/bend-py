# Outside M0 is Unknown: open domains, rebound or non-parameter subjects, a
# missing annotation, defaults, class/dotted/float/sequence/mapping patterns.
# n.py: Literal and bool rebound in the module pin nothing; s.py: nor after a
# star import.
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
  "from typing import Literal\nimport math\n\ndef text(s: str) -> int:\n    match s:\n        case \"a\":\n            return 0\n        case _:\n            return 1\n\ndef rebound(b: bool) -> int:\n    b = not b\n    match b:\n        case True:\n            return 1\n        case False:\n            return 0\n\ndef captured(b: bool, c: int) -> int:\n    match c:\n        case b:\n            pass\n    match b:\n        ca" ++
    "se True:\n            return 1\n        case False:\n            return 0\n\ndef local() -> int:\n    b = True\n    match b:\n        case True:\n            return 1\n        case False:\n            return 0\n\ndef untyped(b) -> int:\n    match b:\n        case True:\n            return 1\n        case False:\n            return 0\n\ndef dflt(b: bool = None) -> int:\n    match b:\n        case True:\n            retur" ++
    "n 1\n        case False:\n            return 0\n\ndef klass(b: bool) -> int:\n    match b:\n        case bool():\n            return 1\n\ndef dotted(n: Literal[1, 2]) -> int:\n    match n:\n        case math.pi:\n            return 0\n        case _:\n            return 1\n\ndef real(n: Literal[1, 2]) -> int:\n    match n:\n        case 1.0:\n            return 0\n        case _:\n            return 1\n\ndef seq(b: bool" ++
    ") -> int:\n    match b:\n        case [x]:\n            return 1\n        case _:\n            return 0\n\ndef mapping(b: bool) -> int:\n    match b:\n        case {\"k\": v}:\n            return 1\n        case _:\n            return 0\n"

def shadow() -> String:
  "from typing import Literal\n\nLiteral = dict\n\ndef fake(s: Literal[\"a\"]) -> int:\n    match s:\n        case \"a\":\n            return 0\n\nbool = int\n\ndef shadowed(b: bool) -> int:\n    match b:\n        case True:\n            return 1\n        case False:\n            return 0\n"

def star() -> String:
  "from typing import Literal\nfrom os import *\n\ndef starred(b: bool) -> int:\n    match b:\n        case True:\n            return 1\n        case False:\n            return 0\n\ndef lit(s: Literal[\"a\"]) -> int:\n    match s:\n        case \"a\":\n            return 0\n"

def main() -> String:
  report("m.py", parse(src())) ++
  report("n.py", parse(shadow())) ++
  report("s.py", parse(star()))
#|"m.py:5:4-9:20 exhaustive Unknown the annotation of s pins no finite domain\nm.py:13:4-17:20 exhaustive Unknown b is rebound in the def\nm.py:20:4-22:16 exhaustive Unknown the annotation of c pins no finite domain\nm.py:23:4-27:20 exhaustive Unknown b is rebound in the def\nm.py:31:4-35:20 exhaustive Unknown b is not a parameter of the enclosing def\nm.py:38:4-42:20 exhaustive Unknown the annotation of b pins no finite domain\nm.py:45:4-49:20 exhaustive Unknown the def has parameter defaults\nm.py:52:4-54:20 exhaustive Unknown pattern MatchClass at 53:13 is outside M0\nm.py:57:4-61:20 exhaustive Unknown pattern MatchValue at 58:13 is outside M0\nm.py:64:4-68:20 exhaustive Unknown pattern MatchValue at 65:13 is outside M0\nm.py:71:4-75:20 exhaustive Unknown pattern MatchSequence at 72:13 is outside M0\nm.py:78:4-82:20 exhaustive Unknown pattern MatchMapping at 79:13 is outside M0\nn.py:6:4-8:20 exhaustive Unknown the annotation of s pins no finite domain\nn.py:13:4-17:20 exhaustive Unknown the annotation of b pins no finite domain\ns.py:5:4-9:20 exhaustive Unknown the annotation of b pins no finite domain\ns.py:12:4-14:20 exhaustive Unknown the annotation of s pins no finite domain\n"
