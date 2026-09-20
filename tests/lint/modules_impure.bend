# pure through imports: log.say prints (an impure contract of print), so greet,
# which imports it, is not pure: Unknown from the search, Refuted when declared.
# `log.say` through `import log` is a dynamic call; quiet stays Proven. noisy
# prints when imported: it is not closed, so page, which imports it, is Unknown.
import Base
import ../../demos/python/syntax.bend as S
import ../../demos/python/lexer.bend as L
import ../../demos/python/parser.bend as P
import ../../demos/python/lint.bend as Lint

def unit(+name: String, +s: String) -> Result<&2, &2, S.Error, Lint.Mod>:
  do Result<&2, &2, S.Error, Lint.Mod>:
    ts : List<&2, S.Tok> <- L.lex(s)
    m : S.Module <- P.parse(ts)
    Done{Lint.Mod{name, m}}

def cs() -> List<&2, Lint.Contract>:
  List.append(&2, Lint.Contract, Lint.contracts(), [Lint.Contract{"print", 1n, False{}, True{}}])

# A pure summary the search did not find, declared: the kernel refutes it.
def declared() -> List<&2, Lint.Summary>:
  [Lint.Ranked{"log", 0n}, Lint.Ranked{"app", 1n}, Lint.Pure{"log", "say", 0n}, Lint.Pure{"app", "greet", 1n}]

def report(r: Result<&2, &2, S.Error, List<&2, Lint.Mod>>) -> String:
  match r:
    case Fail{e}:
      S.error_text(e)
    case Done{+ms}:
      "search: " ++ Lint.modules(ms, cs()) ++ "declared: " ++ Lint.show("app.py", Lint.pure(ms, cs(), declared(), "app", "greet")) ++
        "\nno contract: " ++ Lint.show("app.py", Lint.pure(ms, Lint.contracts(), declared(), "app", "greet")) ++ "\n"

def log() -> String:
  "def say(s: str) -> str:\n    print(s)\n    return s\n"

def app() -> String:
  "import log\nfrom log import say\n\ndef greet(s: str) -> str:\n    return say(s) + s\n\ndef shout(s: str) -> str:\n    return log.say(s)\n\ndef quiet(s: str) -> str:\n    return s + s\n"

def noisy() -> String:
  "print(\"loaded\")\n\ndef tag(s: str) -> str:\n    return s\n"

def page() -> String:
  "from noisy import tag\n\ndef mark(s: str) -> str:\n    return tag(s)\n"

def units() -> Result<&2, &2, S.Error, List<&2, Lint.Mod>>:
  do Result<&2, &2, S.Error, List<&2, Lint.Mod>>:
    l0 : Lint.Mod <- unit("log", log())
    a1 : Lint.Mod <- unit("app", app())
    n2 : Lint.Mod <- unit("noisy", noisy())
    p3 : Lint.Mod <- unit("page", page())
    Done{[l0, a1, n2, p3]}

def main() -> String:
  report(units())
#|"search: log.py:1:0-3:12 pure Unknown contract of print does not grant this call at 2:4\napp.py:1:0-1:10 imports Proven every import resolves in the summary set, acyclically (U0)\napp.py:4:0-5:21 pure Unknown callee log.say is not proven (cycle or Unknown)\napp.py:7:0-8:21 pure Unknown dynamic call at 8:11\napp.py:10:0-11:16 pure Proven terminates with no effect, through its imports (U0)\nnoisy.py:3:0-4:12 pure Unknown noisy: module not closed: Expr at 1:0\npage.py:1:0-1:21 imports Unknown import of noisy is not certified (cycle or Unknown)\npage.py:3:0-4:17 pure Unknown page: import of noisy is not certified (cycle or Unknown)\ndeclared: app.py:4:0-5:21 pure Refuted certificate refuted: log.say: contract of print does not grant this call at 2:4\nno contract: app.py:4:0-5:21 pure Refuted certificate refuted: log.say: unresolved call print at 2:4\n"
