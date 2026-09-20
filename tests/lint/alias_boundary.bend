# The declared IR ownership boundary O0 (SOUNDNESS.md): in-boundary sharing
# (`share`, `echo`, `x is None`) is Proven; identity tests, their callers,
# mutation and interning-dependent `is` are Unknown although `total` may be Proven.
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
      Lint.render("m.py", Lint.analyze(m, Lint.contracts())) ++ "--\n" ++ Lint.render("m.py", Lint.alias(m, Lint.contracts()))

def src() -> String:
  "def same(xs: list[str], ys: list[str]) -> bool:\n    return xs is ys\n\ndef caller(xs: list[str]) -> bool:\n    return same(xs, xs)\n\ndef absent(s: str | None) -> bool:\n    return s is None\n\ndef share(xs: list[str]) -> list[list[str]]:\n    return [xs, xs]\n\ndef echo(xs: list[str]) -> list[str]:\n    return xs\n\ndef grows(xs: list[str]) -> list[str]:\n    xs += [\"x\"]\n    return xs\n\ndef interned(s: str) -> b" ++
    "ool:\n    return s is \"a\"\n"

def main() -> String:
  report(parse(src()))
#|"m.py:1:0-2:19 total Proven terminates on exact built-in arguments (T0)\nm.py:4:0-5:23 total Proven terminates on exact built-in arguments (T0)\nm.py:7:0-8:20 total Proven terminates on exact built-in arguments (T0)\nm.py:10:0-11:19 total Proven terminates on exact built-in arguments (T0)\nm.py:13:0-14:13 total Proven terminates on exact built-in arguments (T0)\nm.py:16:0-18:13 total Unknown outside fragment: AugAssign at 17:4\nm.py:20:0-21:19 total Proven terminates on exact built-in arguments (T0)\n--\nm.py:1:0-2:19 ownership Unknown identity comparison observes sharing at 2:11\nm.py:4:0-5:23 ownership Unknown callee same is not proven (cycle or Unknown)\nm.py:7:0-8:20 ownership Proven value semantics is faithful: no mutation, identity test or retained reference (O0)\nm.py:10:0-11:19 ownership Proven value semantics is faithful: no mutation, identity test or retained reference (O0)\nm.py:13:0-14:13 ownership Proven value semantics is faithful: no mutation, identity test or retained reference (O0)\nm.py:16:0-18:13 ownership Unknown outside fragment: AugAssign at 17:4\nm.py:17:4-17:15 param-mutation Advisory augmented assignment mutates parameter xs: the caller observes it\nm.py:20:0-21:19 ownership Unknown identity comparison observes sharing at 21:11\n"
