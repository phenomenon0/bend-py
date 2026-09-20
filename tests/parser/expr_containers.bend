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

def main() -> Bool:
  String.eq(show(parse("([a,*b], {c:d, **e}, {f,g})\n")), "{\"tag\":\"Module\",\"body\":[{\"tag\":\"Expr\",\"value\":{\"tag\":\"Tuple\",\"elts\":[{\"tag\":\"List\",\"elts\":[{\"tag\":\"Name\",\"id\":\"a\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,2,1,3]},{\"tag\":\"Starred\",\"value\":{\"tag\":\"Name\",\"id\":\"b\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,5,1,6]},\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,4,1,6]}],\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,1,1,7]},{\"tag\":\"Dict\",\"keys\":[{\"tag\":\"Name\",\"id\":\"c\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,10,1,11]},null]," ++ "\"values\":[{\"tag\":\"Name\",\"id\":\"d\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,12,1,13]},{\"tag\":\"Name\",\"id\":\"e\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,17,1,18]}],\"_loc\":[1,9,1,19]},{\"tag\":\"Set\",\"elts\":[{\"tag\":\"Name\",\"id\":\"f\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,22,1,23]},{\"tag\":\"Name\",\"id\":\"g\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,24,1,25]}],\"_loc\":[1,21,1,26]}],\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,0,1,27]},\"_loc\":[1,0,1,27]}],\"type_ignores\":[]}")

#|True{}
