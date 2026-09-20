# A summary is forgeable data: Lint.imports and Lint.pure recompute every entry
# from the modules' ASTs. Only `honest` and `honest pure` may prove; an honest
# path is a counterexample, graded Refuted without the certificate prefix.
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

def row(+label: String, +ms: List<&2, Lint.Mod>, +w: List<&2, Lint.Summary>, +mod: String) -> String:
  label ++ ": " ++ Lint.show(mod ++ ".py", Lint.imports(ms, Lint.contracts(), w, mod)) ++ "\n"

def prow(+label: String, +ms: List<&2, Lint.Mod>, +w: List<&2, Lint.Summary>, +mod: String, +name: String) -> String:
  label ++ ": " ++ Lint.show(mod ++ ".py", Lint.pure(ms, Lint.contracts(), w, mod, name)) ++ "\n"

def honest() -> List<&2, Lint.Summary>:
  [Lint.Ranked{"text", 0n}, Lint.Ranked{"words", 1n}, Lint.Ranked{"app", 2n}]

def table(+ms: List<&2, Lint.Mod>) -> String:
  row("honest", ms, honest(), "app") ++
  row("flipped ranks", ms, [Lint.Ranked{"text", 2n}, Lint.Ranked{"words", 1n}, Lint.Ranked{"app", 0n}], "app") ++
  row("omitted module", ms, [Lint.Ranked{"words", 1n}, Lint.Ranked{"app", 2n}], "app") ++
  row("cycle ranked", ms, [Lint.Ranked{"ping", 0n}, Lint.Ranked{"pong", 1n}], "ping") ++
  row("missing ranked", ms, [Lint.Ranked{"gone", 0n}], "gone") ++
  row("lacking def", ms, [Lint.Ranked{"text", 0n}, Lint.Ranked{"lack", 1n}], "lack") ++
  row("ghost module", ms, [Lint.Ranked{"ghost", 0n}], "ghost") ++
  row("padded", ms, List.append(&2, Lint.Summary, honest(), [Lint.Ranked{"ghost", 0n}]), "app") ++
  row("honest path out", ms, [Lint.Path{["gone", "zz"]}], "gone") ++
  row("honest cycle", ms, [Lint.Path{["ping", "pong", "ping"]}], "ping") ++
  row("forged edge", ms, [Lint.Path{["app", "text", "app"]}], "app") ++
  row("open path", ms, [Lint.Path{["app", "words"]}], "app") ++
  row("no edge", ms, [Lint.Path{["app"]}], "app") ++
  row("empty path", ms, List.append(&2, Lint.Summary, honest(), [Lint.Path{[]}]), "app") ++
  row("no certificate", ms, [], "app") ++
  prow("honest pure", ms, [Lint.Ranked{"text", 0n}, Lint.Ranked{"words", 1n}, Lint.Pure{"text", "twice", 0n}, Lint.Pure{"words", "shout", 1n}], "words", "shout") ++
  prow("pure, no rank", ms, [Lint.Pure{"text", "twice", 0n}], "text", "twice") ++
  prow("flipped pure", ms, [Lint.Ranked{"text", 0n}, Lint.Ranked{"words", 1n}, Lint.Pure{"text", "twice", 1n}, Lint.Pure{"words", "shout", 0n}], "words", "shout") ++
  prow("omitted callee", ms, [Lint.Ranked{"text", 0n}, Lint.Ranked{"words", 1n}, Lint.Pure{"words", "shout", 1n}], "words", "shout") ++
  prow("cyclic pure", ms, [Lint.Ranked{"ping", 0n}, Lint.Ranked{"pong", 1n}, Lint.Pure{"pong", "back", 0n}, Lint.Pure{"ping", "serve", 1n}], "ping", "serve") ++
  prow("ghost def", ms, [Lint.Ranked{"text", 0n}, Lint.Pure{"text", "ghost", 0n}], "text", "ghost") ++
  prow("top-level effect", ms, [Lint.Ranked{"noisy", 0n}, Lint.Pure{"noisy", "tag", 0n}], "noisy", "tag") ++
  prow("shadowed import", ms, [Lint.Ranked{"text", 0n}, Lint.Ranked{"dup", 1n}, Lint.Pure{"dup", "twice", 0n}], "dup", "twice") ++
  prow("no certificate", ms, [], "words", "shout")

def report(r: Result<&2, &2, S.Error, List<&2, Lint.Mod>>) -> String:
  match r:
    case Fail{e}:
      S.error_text(e)
    case Done{ms}:
      table(ms)

def app() -> String:
  "import text\nfrom words import shout as yell\nfrom text import twice\n\ndef greet(xs: list[str]) -> str:\n    acc = \"\"\n    for x in xs:\n        acc = acc + yell(x) + twice(x)\n    return acc\n"

def words() -> String:
  "from text import twice\n\ndef shout(s: str) -> str:\n    return twice(s) + \"!\"\n"

def text() -> String:
  "\"\"\"Pure helpers.\"\"\"\n\ndef twice(s: str) -> str:\n    return s + s\n"

def ping() -> String:
  "from pong import back\n\ndef serve(s: str) -> str:\n    return back(s)\n"

def pong() -> String:
  "from ping import serve\n\ndef back(s: str) -> str:\n    return s\n"

def gone() -> String:
  "import zz\n"

def lack() -> String:
  "from text import nope\n"

def dup() -> String:
  "from text import twice\n\ndef twice(s: str) -> str:\n    return s\n"

def noisy() -> String:
  "print(\"loaded\")\n\ndef tag(s: str) -> str:\n    return s\n"

def units() -> Result<&2, &2, S.Error, List<&2, Lint.Mod>>:
  do Result<&2, &2, S.Error, List<&2, Lint.Mod>>:
    a0 : Lint.Mod <- unit("app", app())
    w1 : Lint.Mod <- unit("words", words())
    t2 : Lint.Mod <- unit("text", text())
    p3 : Lint.Mod <- unit("ping", ping())
    p4 : Lint.Mod <- unit("pong", pong())
    g5 : Lint.Mod <- unit("gone", gone())
    l6 : Lint.Mod <- unit("lack", lack())
    d7 : Lint.Mod <- unit("dup", dup())
    n8 : Lint.Mod <- unit("noisy", noisy())
    Done{[a0, w1, t2, p3, p4, g5, l6, d7, n8]}

def main() -> String:
  report(units())
#|"honest: app.py:1:0-1:11 imports Proven every import resolves in the summary set, acyclically (U0)\nflipped ranks: app.py:1:0-1:11 imports Refuted certificate refuted: words: import of text holds no smaller rank\nomitted module: app.py:1:0-1:11 imports Refuted certificate refuted: words: import of text holds no smaller rank\ncycle ranked: ping.py:1:0-1:21 imports Refuted certificate refuted: ping: import of pong holds no smaller rank\nmissing ranked: gone.py:1:0-1:9 imports Refuted certificate refuted: gone: missing module zz at 1:0\nlacking def: lack.py:1:0-1:21 imports Refuted certificate refuted: lack: text has no def nope at 1:0\nghost module: ghost.py:? imports Refuted certificate refuted: ghost: no unique module ghost\npadded: app.py:1:0-1:11 imports Refuted certificate refuted: ghost: no unique module ghost\nhonest path out: gone.py:1:0-1:9 imports Refuted missing module zz via gone -> zz\nhonest cycle: ping.py:1:0-1:21 imports Refuted import cycle ping -> pong -> ping\nforged edge: app.py:1:0-1:11 imports Refuted certificate refuted: path [app -> text -> app]: text does not import app\nopen path: app.py:1:0-1:11 imports Refuted certificate refuted: path [app -> words]: the path neither closes a cycle nor leaves the summary set\nno edge: app.py:1:0-1:11 imports Refuted certificate refuted: path [app]: no edge\nempty path: app.py:1:0-1:11 imports Refuted certificate refuted: path []: empty path\nno certificate: app.py:1:0-1:11 imports Unknown no certificate\nhonest pure: words.py:3:0-4:25 pure Proven terminates with no effect, through its imports (U0)\npure, no rank: text.py:3:0-4:16 pure Refuted certificate refuted: text.twice: module text holds no import certificate\nflipped pure: words.py:3:0-4:25 pure Refuted certificate refuted: words.shout: callee text.twice holds no smaller rank\nomitted callee: words.py:3:0-4:25 pure Refuted certificate refuted: words.shout: callee text.twice holds no smaller rank\ncyclic pure: ping.py:3:0-4:18 pure Refuted certificate refuted: ping: import of pong holds no smaller rank\nghost def: text.py:? pure Refuted certificate refuted: text.ghost: no unique def ghost\ntop-level effect: noisy.py:3:0-4:12 pure Refuted certificate refuted: noisy: module not closed: Expr at 1:0\nshadowed import: dup.py:3:0-4:12 pure Refuted certificate refuted: dup.twice: no unique def twice\nno certificate: words.py:3:0-4:25 pure Unknown no certificate\n"
