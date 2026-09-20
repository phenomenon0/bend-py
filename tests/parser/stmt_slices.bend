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
  String.eq(show(parse("a[b[1:]][:-1].c()[x:y, ::2] = d[:]\ndel a[1:2:3], e[*f, :g]\n")), "{\"tag\":\"Module\",\"body\":[{\"tag\":\"Assign\",\"targets\":[{\"tag\":\"Subscript\",\"value\":{\"tag\":\"Call\",\"func\":{\"tag\":\"Attribute\",\"value\":{\"tag\":\"Subscript\",\"value\":{\"tag\":\"Subscript\",\"value\":{\"tag\":\"Name\",\"id\":\"a\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,0,1,1]},\"slice\":{\"tag\":\"Subscript\",\"value\":{\"tag\":\"Name\",\"id\":\"b\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,2,1,3]},\"slice\":{\"tag\":\"Slice\",\"lower\":{\"tag\":\"Constant\",\"_raw\":\"1\",\"kind\":null,\"_loc\":[1,4,1,5]},\"upper\":null,\"step\":null,\"_loc\":[1,4,1,6]},\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,2,1,7]},\"" ++
      "ctx\":{\"tag\":\"Load\"},\"_loc\":[1,0,1,8]},\"slice\":{\"tag\":\"Slice\",\"lower\":null,\"upper\":{\"tag\":\"UnaryOp\",\"op\":{\"tag\":\"USub\"},\"operand\":{\"tag\":\"Constant\",\"_raw\":\"1\",\"kind\":null,\"_loc\":[1,11,1,12]},\"_loc\":[1,10,1,12]},\"step\":null,\"_loc\":[1,9,1,12]},\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,0,1,13]},\"attr\":\"c\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,0,1,15]},\"args\":[],\"keywords\":[],\"_loc\":[1,0,1,17]},\"slice\":{\"tag\":\"Tuple\",\"elts\":[{\"tag\":\"Slice\",\"lower\":{\"tag\":\"Name\",\"id\":\"x\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,18,1,19]},\"upper\":{\"tag\":\"Nam" ++
      "e\",\"id\":\"y\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,20,1,21]},\"step\":null,\"_loc\":[1,18,1,21]},{\"tag\":\"Slice\",\"lower\":null,\"upper\":null,\"step\":{\"tag\":\"Constant\",\"_raw\":\"2\",\"kind\":null,\"_loc\":[1,25,1,26]},\"_loc\":[1,23,1,26]}],\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,18,1,26]},\"ctx\":{\"tag\":\"Store\"},\"_loc\":[1,0,1,27]}],\"value\":{\"tag\":\"Subscript\",\"value\":{\"tag\":\"Name\",\"id\":\"d\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,30,1,31]},\"slice\":{\"tag\":\"Slice\",\"lower\":null,\"upper\":null,\"step\":null,\"_loc\":[1,32,1,33]},\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,30," ++
      "1,34]},\"type_comment\":null,\"_loc\":[1,0,1,34]},{\"tag\":\"Delete\",\"targets\":[{\"tag\":\"Subscript\",\"value\":{\"tag\":\"Name\",\"id\":\"a\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,4,2,5]},\"slice\":{\"tag\":\"Slice\",\"lower\":{\"tag\":\"Constant\",\"_raw\":\"1\",\"kind\":null,\"_loc\":[2,6,2,7]},\"upper\":{\"tag\":\"Constant\",\"_raw\":\"2\",\"kind\":null,\"_loc\":[2,8,2,9]},\"step\":{\"tag\":\"Constant\",\"_raw\":\"3\",\"kind\":null,\"_loc\":[2,10,2,11]},\"_loc\":[2,6,2,11]},\"ctx\":{\"tag\":\"Del\"},\"_loc\":[2,4,2,12]},{\"tag\":\"Subscript\",\"value\":{\"tag\":\"Name\",\"id\":\"e\",\"ctx\":{\"tag\":\"Loa" ++
      "d\"},\"_loc\":[2,14,2,15]},\"slice\":{\"tag\":\"Tuple\",\"elts\":[{\"tag\":\"Starred\",\"value\":{\"tag\":\"Name\",\"id\":\"f\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,17,2,18]},\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,16,2,18]},{\"tag\":\"Slice\",\"lower\":null,\"upper\":{\"tag\":\"Name\",\"id\":\"g\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,21,2,22]},\"step\":null,\"_loc\":[2,20,2,22]}],\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,16,2,22]},\"ctx\":{\"tag\":\"Del\"},\"_loc\":[2,14,2,23]}],\"_loc\":[2,0,2,23]}],\"type_ignores\":[]}") &&
    String.eq(kind(parse("a[1:2:3:4]")), "Syntax") &&
    String.eq(kind(parse("a[*b:1]")), "Syntax") &&
    String.eq(kind(parse("a[]")), "Syntax") &&
    String.eq(kind(parse("x = 1:2")), "Syntax") &&
    String.eq(kind(parse("a[1:(x:=2)]")), "Done")

#|True{}
