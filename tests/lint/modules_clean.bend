# U0 imports Proven and pure Proven: an acyclic summary set with a diamond (app
# imports words and text, words imports text), an alias, a plain `import`, a
# docstring; app comes first in the manifest: the rounds rank, not the order.
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
  "import text\nfrom words import shout as yell\nfrom text import twice\n\ndef greet(xs: list[str]) -> str:\n    acc = \"\"\n    for x in xs:\n        acc = acc + yell(x) + twice(x)\n    return acc\n"

def words() -> String:
  "from text import twice\n\ndef shout(s: str) -> str:\n    return twice(s) + \"!\"\n\ndef size(xs: list[str]) -> int:\n    return len(xs)\n"

def text() -> String:
  "\"\"\"Pure helpers.\"\"\"\n\ndef twice(s: str) -> str:\n    return s + s\n"

def units() -> Result<&2, &2, S.Error, List<&2, Lint.Mod>>:
  do Result<&2, &2, S.Error, List<&2, Lint.Mod>>:
    a0 : Lint.Mod <- unit("app", app())
    w1 : Lint.Mod <- unit("words", words())
    t2 : Lint.Mod <- unit("text", text())
    Done{[a0, w1, t2]}

def main() -> String:
  report(units())
#|"app.py:1:0-1:11 imports Proven every import resolves in the summary set, acyclically (U0)\napp.py:5:0-9:14 pure Proven terminates with no effect, through its imports (U0)\nwords.py:1:0-1:22 imports Proven every import resolves in the summary set, acyclically (U0)\nwords.py:3:0-4:25 pure Proven terminates with no effect, through its imports (U0)\nwords.py:6:0-7:18 pure Proven terminates with no effect, through its imports (U0)\ntext.py:3:0-4:16 pure Proven terminates with no effect, through its imports (U0)\n"
