# L2 negatives: nothing here may flag. Repeated use is legal; immutable reuse
# (str under A1), a sorted() copy, a move (the old name is dead), a join of fresh
# lists, and an alias passed to an O0-certified def (the boundary at work).
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
    case Done{+m}:
      Lint.render("m.py", Lint.alias(m, Lint.contracts()))

def src() -> String:
  "def helper(xs: list[str]) -> int:\n    return len(xs)\n\ndef repeated(a: list[str]) -> int:\n    return helper(a) + helper(a)\n\ndef immutable(s: str) -> str:\n    t = s\n    t += \"x\"\n    return s + t\n\ndef copied(a: list[str]) -> list[str]:\n    b = sorted(a)\n    b.append(\"x\")\n    return a\n\ndef moved(a: list[str]) -> list[str]:\n    b = sorted(a)\n    c = b\n    c.append(\"x\")\n    return c\n\ndef fresh(a: list[s" ++
    "tr], c: bool) -> list[str]:\n    if c:\n        b = []\n    else:\n        b = [\"y\"]\n    b.append(\"x\")\n    return a + b\n\ndef certified(a: list[str]) -> int:\n    b = a\n    n = helper(b)\n    return n + len(a)\n\ndef optional(s: str | None) -> str:\n    t = s or \"\"\n    t += \"!\"\n    return t\n"

def main() -> String:
  report(parse(src()))
#|"m.py:1:0-2:18 ownership Proven value semantics is faithful: no mutation, identity test or retained reference (O0)\nm.py:4:0-5:32 ownership Proven value semantics is faithful: no mutation, identity test or retained reference (O0)\nm.py:7:0-10:16 ownership Unknown outside fragment: AugAssign at 9:4\nm.py:12:0-15:12 ownership Unknown dynamic call at 14:4\nm.py:17:0-21:12 ownership Unknown dynamic call at 20:4\nm.py:23:0-29:16 ownership Unknown dynamic call at 28:4\nm.py:31:0-34:21 ownership Proven value semantics is faithful: no mutation, identity test or retained reference (O0)\nm.py:36:0-39:12 ownership Unknown outside fragment: AugAssign at 38:4\n"
