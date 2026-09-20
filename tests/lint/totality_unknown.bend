# Outside T0 is Unknown, never Proven: each def names its first offender.
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
  "def spin(s: str) -> str:\n    while s:\n        pass\n    return s\n\ndef ask(s: str) -> str:\n    return mystery(s)\n\ndef grow(xs: list[str]) -> list[str]:\n    for x in xs:\n        xs.append(x)\n    return xs\n\ndef alias(xs: list[str]) -> list[str]:\n    ys = xs\n    for x in xs:\n        ys += [x]\n    return ys\n\ndef again(s: str) -> str:\n    return again(s)\n\ndef ping(s: str) -> str:\n    return pong(s)\n\ndef " ++
    "pong(s: str) -> str:\n    return ping(s)\n\ndef above(s: str) -> str:\n    return ping(s)\n\n@cache\ndef memo(s: str) -> str:\n    return s\n\ndef bare(s):\n    return s\n\ndef thing(s: Thing) -> str:\n    return s\n\ndef lam(s: str) -> str:\n    return (lambda t: t)(s)\n\ndef glob(s: str) -> str:\n    return s + SUFFIX\n\ndef kw(xs: list[str]) -> list[str]:\n    return sorted(xs, reverse=True)\n\ndef arity(xs: list[str])" ++
    " -> int:\n    return len(xs, xs)\n\ndef ok(s: str) -> str:\n    return s\n"

def open() -> String:
  "import os\n\ndef ok(s: str) -> str:\n    return s\n"

def main() -> String:
  report(parse(src())) ++ "open module:\n" ++ report(parse(open()))
#|"m.py:1:0-4:12 total Unknown unbounded loop While at 2:4\nm.py:6:0-7:21 total Unknown unresolved call mystery at 7:11\nm.py:9:0-12:13 total Unknown dynamic call at 11:8\nm.py:14:0-18:13 total Unknown outside fragment: AugAssign at 17:8\nm.py:20:0-21:19 total Unknown callee again is not proven (cycle or Unknown)\nm.py:23:0-24:18 total Unknown callee pong is not proven (cycle or Unknown)\nm.py:26:0-27:18 total Unknown callee ping is not proven (cycle or Unknown)\nm.py:29:0-30:18 total Unknown callee ping is not proven (cycle or Unknown)\nm.py:33:0-34:12 total Unknown decorated or non-simple parameters\nm.py:36:0-37:12 total Unknown missing or non-builtin annotation\nm.py:39:0-40:12 total Unknown missing or non-builtin annotation\nm.py:42:0-43:27 total Unknown dynamic call at 43:12\nm.py:45:0-46:21 total Unknown unresolved name SUFFIX at 46:15\nm.py:48:0-49:35 total Unknown outside fragment: keyword at 49:22\nm.py:51:0-52:22 total Unknown contract of len does not grant this call at 52:11\nm.py:54:0-55:12 total Proven terminates on exact built-in arguments (T0)\nopen module:\nm.py:3:0-4:12 total Unknown module not closed: Import at 1:0\n"
