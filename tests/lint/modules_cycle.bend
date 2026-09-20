# imports Refuted by a cycle: self (loop), mutual by `from` (ping, pong: CPython
# raises ImportError) and by `import` (left, right: CPython binds half-built
# modules), and a module that only reaches one (fan).
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

def loop() -> String:
  "import loop\n\ndef f(s: str) -> str:\n    return s\n"

def ping() -> String:
  "from pong import back\n\ndef serve(s: str) -> str:\n    return back(s)\n"

def pong() -> String:
  "from ping import serve\n\ndef back(s: str) -> str:\n    return s\n"

def left() -> String:
  "import right\n"

def right() -> String:
  "import left\n"

def fan() -> String:
  "import ping\n\ndef g(s: str) -> str:\n    return s\n"

def units() -> Result<&2, &2, S.Error, List<&2, Lint.Mod>>:
  do Result<&2, &2, S.Error, List<&2, Lint.Mod>>:
    l0 : Lint.Mod <- unit("loop", loop())
    p1 : Lint.Mod <- unit("ping", ping())
    p2 : Lint.Mod <- unit("pong", pong())
    l3 : Lint.Mod <- unit("left", left())
    r4 : Lint.Mod <- unit("right", right())
    f5 : Lint.Mod <- unit("fan", fan())
    Done{[l0, p1, p2, l3, r4, f5]}

def main() -> String:
  report(units())
#|"loop.py:1:0-1:11 imports Refuted import cycle loop -> loop\nloop.py:3:0-4:12 pure Unknown loop: import of loop is not certified (cycle or Unknown)\nping.py:1:0-1:21 imports Refuted import cycle ping -> pong -> ping\nping.py:3:0-4:18 pure Unknown ping: import of pong is not certified (cycle or Unknown)\npong.py:1:0-1:22 imports Refuted import cycle pong -> ping -> pong\npong.py:3:0-4:12 pure Unknown pong: import of ping is not certified (cycle or Unknown)\nleft.py:1:0-1:12 imports Refuted import cycle left -> right -> left\nright.py:1:0-1:11 imports Refuted import cycle right -> left -> right\nfan.py:1:0-1:11 imports Refuted import cycle fan -> ping -> pong -> ping\nfan.py:3:0-4:12 pure Unknown fan: import of ping is not certified (cycle or Unknown)\n"
