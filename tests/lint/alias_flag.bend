# L2 positives: every function but the O0 helper `use` MUST flag. The plan's `b=a; mutate(b); use(a)`,
# method/store/augmented mutation through an alias, branch and IfExp joins, a
# transitive alias, an escape into a container. All Advisory: no proof is claimed.
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
  "def mutate(xs: list[str]) -> None:\n    xs.append(\"m\")\n\ndef use(xs: list[str]) -> int:\n    return len(xs)\n\ndef plan(a: list[str]) -> int:\n    b = a\n    mutate(b)\n    return use(a)\n\ndef method(a: list[str]) -> list[str]:\n    b = a\n    b.append(\"x\")\n    return a\n\ndef store(a: list[str]) -> list[str]:\n    b = a\n    b[0] = \"x\"\n    return a\n\ndef augmented(a: list[str]) -> list[str]:\n    b = a\n    b += [" ++
    "\"x\"]\n    return a\n\ndef join(a: list[str], c: bool) -> list[str]:\n    if c:\n        b = a\n    else:\n        b = []\n    b.append(\"x\")\n    return a\n\ndef ternary(a: list[str], c: bool) -> list[str]:\n    b = a if c else []\n    b.append(\"x\")\n    return a\n\ndef chain(a: list[str]) -> list[str]:\n    b = a\n    c = b\n    c.append(\"x\")\n    return a\n\ndef keeps(a: list[str], box: list[list[str]]) -> list[str]:\n" ++
    "    b = a\n    box.append(b)\n    return a\n"

def main() -> String:
  report(parse(src()))
#|"m.py:1:0-2:18 ownership Unknown dynamic call at 2:4\nm.py:2:4-2:18 param-mutation Advisory .append mutates parameter xs: the caller observes it\nm.py:4:0-5:18 ownership Proven value semantics is faithful: no mutation, identity test or retained reference (O0)\nm.py:7:0-10:17 ownership Unknown callee mutate is not proven (cycle or Unknown)\nm.py:9:11-9:12 alias-escape Advisory b is passed to mutate, which may mutate or keep it; a may alias it (binding at 8:4) and is read at 10:15\nm.py:12:0-15:12 ownership Unknown dynamic call at 14:4\nm.py:14:4-14:17 alias-mutation Advisory .append mutates b; a may alias it (binding at 13:4) and is read at 15:11\nm.py:17:0-20:12 ownership Unknown outside fragment: Subscript at 19:4\nm.py:19:4-19:8 alias-mutation Advisory item or attribute store mutates b; a may alias it (binding at 18:4) and is read at 20:11\nm.py:22:0-25:12 ownership Unknown outside fragment: AugAssign at 24:4\nm.py:24:4-24:14 alias-mutation Advisory augmented assignment mutates b; a may alias it (binding at 23:4) and is read at 25:11\nm.py:27:0-33:12 ownership Unknown dynamic call at 32:4\nm.py:32:4-32:17 alias-mutation Advisory .append mutates b; a may alias it (binding at 29:8) and is read at 33:11\nm.py:35:0-38:12 ownership Unknown dynamic call at 37:4\nm.py:37:4-37:17 alias-mutation Advisory .append mutates b; a may alias it (binding at 36:4) and is read at 38:11\nm.py:40:0-44:12 ownership Unknown dynamic call at 43:4\nm.py:43:4-43:17 alias-mutation Advisory .append mutates c; a may alias it (binding at 41:4) and is read at 44:11\nm.py:46:0-49:12 ownership Unknown dynamic call at 48:4\nm.py:48:4-48:17 param-mutation Advisory .append mutates parameter box: the caller observes it\nm.py:48:15-48:16 alias-escape Advisory b is passed to .append, which may mutate or keep it; a may alias it (binding at 47:4) and is read at 49:11\n"
