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
  String.eq(show(parse("f(a, k=b, **c).d[e, f]\n")), "{\"tag\":\"Module\",\"body\":[{\"tag\":\"Expr\",\"value\":{\"tag\":\"Subscript\",\"value\":{\"tag\":\"Attribute\",\"value\":{\"tag\":\"Call\",\"func\":{\"tag\":\"Name\",\"id\":\"f\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,0,1,1]},\"args\":[{\"tag\":\"Name\",\"id\":\"a\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,2,1,3]}],\"keywords\":[{\"tag\":\"keyword\",\"arg\":\"k\",\"value\":{\"tag\":\"Name\",\"id\":\"b\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,7,1,8]},\"_loc\":[1,5,1,8]},{\"tag\":\"keyword\",\"arg\":null,\"v" ++ "alue\":{\"tag\":\"Name\",\"id\":\"c\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,12,1,13]},\"_loc\":[1,10,1,13]}],\"_loc\":[1,0,1,14]},\"attr\":\"d\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,0,1,16]},\"slice\":{\"tag\":\"Tuple\",\"elts\":[{\"tag\":\"Name\",\"id\":\"e\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,17,1,18]},{\"tag\":\"Name\",\"id\":\"f\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,20,1,21]}],\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,17,1,21]},\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,0,1,22]},\"_loc\":[1,0,1,22]}]" ++ ",\"type_ignores\":[]}")

#|True{}
