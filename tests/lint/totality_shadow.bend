# Spelling is not authority: a rebound `len`/`str`/`sorted` revokes the builtin's
# contract for every call so spelled; the binding itself gets an Advisory.
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
  "def len(xs: list[str]) -> int:\n    return 0\n\ndef count(xs: list[str]) -> int:\n    return len(xs)\n\ndef order(sorted: list[str]) -> list[str]:\n    return sorted(sorted)\n\ndef text(xs: list[str]) -> str:\n    str = \"a\"\n    return str(xs)\n\ndef fine(xs: list[str]) -> bool:\n    return bool(xs)\n"

def forged(r: Result<&2, &2, S.Error, S.Module>) -> String:
  match r:
    case Fail{e}:
      S.error_text(e)
    case Done{m}:
      Lint.show("m.py", Lint.verify(m, Lint.contracts(), [Lint.Rank{"len", 0n}, Lint.Rank{"count", 1n}], "count"))

def main() -> String:
  report(parse(src())) ++ "forged: " ++ forged(parse(src()))
#|"m.py:1:0-2:12 shadowed-builtin Advisory len is rebound; calls to it are not granted the builtin's contract\nm.py:1:0-2:12 total Proven terminates on exact built-in arguments (T0)\nm.py:4:0-5:18 total Unknown shadowed builtin len at 5:11\nm.py:7:0-8:25 total Unknown shadowed builtin sorted at 8:11\nm.py:7:10-7:27 shadowed-builtin Advisory sorted is rebound; calls to it are not granted the builtin's contract\nm.py:10:0-12:18 total Unknown shadowed builtin str at 12:11\nm.py:11:4-11:7 shadowed-builtin Advisory str is rebound; calls to it are not granted the builtin's contract\nm.py:14:0-15:19 total Proven terminates on exact built-in arguments (T0)\nforged: m.py:4:0-5:18 total Refuted certificate refuted: count: shadowed builtin len at 5:11"
