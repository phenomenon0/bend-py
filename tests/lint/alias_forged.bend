# An ownership certificate is forgeable data: Lint.own recomputes O0 (T0 and no
# identity test) for every witness entry. After the slash: the `total` grade of
# the same witness, so `identity` shows total Proven is not ownership Proven.
import Base
import ../../demos/python/syntax.bend as S
import ../../demos/python/lexer.bend as L
import ../../demos/python/parser.bend as P
import ../../demos/python/lint.bend as Lint

def parse(s: String) -> Result<&2, &2, S.Error, S.Module>:
  do Result<&2, &2, S.Error, S.Module>:
    ts : List<&2, S.Tok> <- L.lex(s)
    P.parse(ts)

def run(+label: String, r: Result<&2, &2, S.Error, S.Module>, +w: List<&2, Lint.Rank>, +name: String) -> String:
  match r:
    case Fail{e}:
      label ++ ": " ++ S.error_text(e) ++ "\n"
    case Done{+m}:
      label ++ ": " ++ Lint.show("m.py", Lint.own(m, Lint.contracts(), w, name)) ++ " / " ++
        Lint.grade_of(Lint.verify(m, Lint.contracts(), w, name)) ++ "\n"

def honest() -> String:
  "def echo(xs: list[str]) -> list[str]:\n    return xs\n\ndef top(xs: list[str]) -> list[list[str]]:\n    return [echo(xs), xs]\n"

def changed() -> String:
  "def echo(xs: list[str]) -> list[str]:\n    xs += [\"x\"]\n    return xs\n\ndef top(xs: list[str]) -> list[list[str]]:\n    return [echo(xs), xs]\n"

def sames() -> String:
  "def same(xs: list[str], ys: list[str]) -> bool:\n    return xs is ys\n\ndef caller(xs: list[str]) -> bool:\n    return same(xs, xs)\n"

def main() -> String:
  run("honest", parse(honest()), [Lint.Rank{"echo", 0n}, Lint.Rank{"top", 1n}], "top") ++
  run("flipped ranks", parse(honest()), [Lint.Rank{"echo", 1n}, Lint.Rank{"top", 0n}], "top") ++
  run("omitted callee", parse(honest()), [Lint.Rank{"top", 1n}], "top") ++
  run("changed callee", parse(changed()), [Lint.Rank{"echo", 0n}, Lint.Rank{"top", 1n}], "top") ++
  run("no certificate", parse(honest()), [], "top") ++
  run("identity", parse(sames()), [Lint.Rank{"same", 0n}], "same") ++
  run("identity callee", parse(sames()), [Lint.Rank{"same", 0n}, Lint.Rank{"caller", 1n}], "caller") ++
  run("identity omitted", parse(sames()), [Lint.Rank{"caller", 1n}], "caller")
#|"honest: m.py:4:0-5:25 ownership Proven value semantics is faithful: no mutation, identity test or retained reference (O0) / Proven\nflipped ranks: m.py:4:0-5:25 ownership Refuted certificate refuted: top: callee echo holds no smaller rank / Refuted\nomitted callee: m.py:4:0-5:25 ownership Refuted certificate refuted: top: callee echo holds no smaller rank / Refuted\nchanged callee: m.py:5:0-6:25 ownership Refuted certificate refuted: echo: outside fragment: AugAssign at 2:4 / Refuted\nno certificate: m.py:4:0-5:25 ownership Unknown no certificate / Unknown\nidentity: m.py:1:0-2:19 ownership Refuted certificate refuted: same: identity comparison observes sharing at 2:11 / Proven\nidentity callee: m.py:4:0-5:23 ownership Refuted certificate refuted: same: identity comparison observes sharing at 2:11 / Proven\nidentity omitted: m.py:4:0-5:23 ownership Refuted certificate refuted: caller: callee same holds no smaller rank / Refuted\n"
