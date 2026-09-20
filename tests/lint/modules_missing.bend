# imports Refuted by a path out of the summary set: app imports util, helpers
# imports strings, top reaches strings through helpers. A def missing from a
# module of the set has no counterexample in U0: lack stays Unknown; so do the
# imports outside U0 (relative, star, dotted).
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

def report(r: Result<&2, &2, S.Error, List<&2, Lint.Mod>>) -> String:
  match r:
    case Fail{e}:
      S.error_text(e)
    case Done{ms}:
      Lint.modules(ms, Lint.contracts())

def app() -> String:
  "from util import pad\n\ndef run(s: str) -> str:\n    return pad(s)\n"

def helpers() -> String:
  "from strings import strip\n\ndef clean(s: str) -> str:\n    return s\n"

def top() -> String:
  "import helpers\n\ndef go(s: str) -> str:\n    return s\n"

def lack() -> String:
  "from text import nope\n"

def text() -> String:
  "\"\"\"Pure helpers.\"\"\"\n\ndef twice(s: str) -> str:\n    return s + s\n"

def rel() -> String:
  "from .text import twice\n"

def star() -> String:
  "from text import *\n"

def dots() -> String:
  "import text.twice\nfrom text.sub import x\n"

def units() -> Result<&2, &2, S.Error, List<&2, Lint.Mod>>:
  do Result<&2, &2, S.Error, List<&2, Lint.Mod>>:
    a0 : Lint.Mod <- unit("app", app())
    h1 : Lint.Mod <- unit("helpers", helpers())
    t2 : Lint.Mod <- unit("top", top())
    l3 : Lint.Mod <- unit("lack", lack())
    t4 : Lint.Mod <- unit("text", text())
    r5 : Lint.Mod <- unit("rel", rel())
    s6 : Lint.Mod <- unit("star", star())
    d7 : Lint.Mod <- unit("dots", dots())
    Done{[a0, h1, t2, l3, t4, r5, s6, d7]}

def main() -> String:
  report(units())
#|"app.py:1:0-1:20 imports Refuted missing module util via app -> util\napp.py:3:0-4:17 pure Unknown app: missing module util at 1:0\nhelpers.py:1:0-1:25 imports Refuted missing module strings via helpers -> strings\nhelpers.py:3:0-4:12 pure Unknown helpers: missing module strings at 1:0\ntop.py:1:0-1:14 imports Refuted missing module strings via top -> helpers -> strings\ntop.py:3:0-4:12 pure Unknown top: import of helpers is not certified (cycle or Unknown)\nlack.py:1:0-1:21 imports Unknown text has no def nope at 1:0\ntext.py:3:0-4:16 pure Proven terminates with no effect, through its imports (U0)\nrel.py:1:0-1:23 imports Unknown module not closed: ImportFrom at 1:0\nstar.py:1:0-1:18 imports Unknown module not closed: ImportFrom at 1:0\ndots.py:1:0-1:17 imports Unknown module not closed: Import at 1:0\n"
