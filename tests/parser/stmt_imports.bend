# Expected wire AST independently derived from the pinned CPython oracle.
import Base
import ../../demos/python/syntax.bend as S
import ../../demos/python/lexer.bend as L
import ../../demos/python/parser.bend as P

def show(r: Result<&2, &2, S.Error, S.Module>) -> String:
  match r:
    case Fail{e}:
      S.error_text(e)
    case Done{m}:
      S.json(S.module(m))

def parse(s: String) -> Result<&2, &2, S.Error, S.Module>:
  do Result<&2, &2, S.Error, S.Module>:
    ts : List<&2, S.Tok> <- L.lex(s)
    P.parse(ts)

def kind(r: Result<&2, &2, S.Error, S.Module>) -> String:
  match r:
    case Done{m}:
      "Done"
    case Fail{S.PErr{k, pos, msg}}:
      S.kind(k)

def main() -> Bool:
  String.eq(show(parse("import a.b as c, d\nfrom ...e.f import (g as h, i,)\nif x:\n    from . import j; from k import *\n")), "{\"tag\":\"Module\",\"body\":[{\"tag\":\"Import\",\"names\":[{\"tag\":\"alias\",\"name\":\"a.b\",\"asname\":\"c\",\"_loc\":[1,7,1,15]},{\"tag\":\"alias\",\"name\":\"d\",\"asname\":null,\"_loc\":[1,17,1,18]}],\"_loc\":[1,0,1,18]},{\"tag\":\"ImportFrom\",\"module\":\"e.f\",\"names\":[{\"tag\":\"alias\",\"name\":\"g\",\"asname\":\"h\",\"_loc\":[2,20,2,26]},{\"tag\":\"alias\",\"name\":\"i\",\"asname\":null,\"_loc\":[2,28,2,29]}],\"level\":3,\"_loc\":[2,0,2,31]},{\"tag\":\"If\",\"test\":{\"tag\":\"Name\",\"id\":" ++ "\"x\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[3,3,3,4]},\"body\":[{\"tag\":\"ImportFrom\",\"module\":null,\"names\":[{\"tag\":\"alias\",\"name\":\"j\",\"asname\":null,\"_loc\":[4,18,4,19]}],\"level\":1,\"_loc\":[4,4,4,19]},{\"tag\":\"ImportFrom\",\"module\":\"k\",\"names\":[{\"tag\":\"alias\",\"name\":\"*\",\"asname\":null,\"_loc\":[4,35,4,36]}],\"level\":0,\"_loc\":[4,21,4,36]}],\"orelse\":[],\"_loc\":[3,0,4,36]}],\"type_ignores\":[]}") &&
    String.eq(kind(parse("from a import b,")), "Syntax") &&
    String.eq(kind(parse("from import a")), "Syntax") &&
    String.eq(kind(parse("from a import (*)")), "Syntax") &&
    String.eq(kind(parse("import ﬁ")), "Unsupported")

#|True{}
