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
  String.eq(show(parse("a, [b, *c], d.e[f] = source\nx.y += (z)\n")), "{\"tag\":\"Module\",\"body\":[{\"tag\":\"Assign\",\"targets\":[{\"tag\":\"Tuple\",\"elts\":[{\"tag\":\"Name\",\"id\":\"a\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[1,0,1,1]},{\"tag\":\"List\",\"elts\":[{\"tag\":\"Name\",\"id\":\"b\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[1,4,1,5]},{\"tag\":\"Starred\",\"value\":{\"tag\":\"Name\",\"id\":\"c\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[1,8,1,9]},\"ctx\":{\"tag\":\"Store\"},\"_loc\":[1,7,1,9]}],\"ctx\":{\"tag\":\"Store\"},\"_loc\":[1,3,1,10]},{\"tag\":\"Subscript\",\"v" ++ "alue\":{\"tag\":\"Attribute\",\"value\":{\"tag\":\"Name\",\"id\":\"d\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,12,1,13]},\"attr\":\"e\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,12,1,15]},\"slice\":{\"tag\":\"Name\",\"id\":\"f\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,16,1,17]},\"ctx\":{\"tag\":\"Store\"},\"_loc\":[1,12,1,18]}],\"ctx\":{\"tag\":\"Store\"},\"_loc\":[1,0,1,18]}],\"value\":{\"tag\":\"Name\",\"id\":\"source\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,21,1,27]},\"type_comment\":null,\"_loc\":[1,0,1,27]}" ++ ",{\"tag\":\"AugAssign\",\"target\":{\"tag\":\"Attribute\",\"value\":{\"tag\":\"Name\",\"id\":\"x\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,0,2,1]},\"attr\":\"y\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[2,0,2,3]},\"op\":{\"tag\":\"Add\"},\"value\":{\"tag\":\"Name\",\"id\":\"z\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,8,2,9]},\"_loc\":[2,0,2,10]}],\"type_ignores\":[]}")

#|True{}
