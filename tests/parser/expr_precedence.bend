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
  String.eq(show(parse("result = -2**2 + (a if not b in c else d)\n")), "{\"tag\":\"Module\",\"body\":[{\"tag\":\"Assign\",\"targets\":[{\"tag\":\"Name\",\"id\":\"result\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[1,0,1,6]}],\"value\":{\"tag\":\"BinOp\",\"left\":{\"tag\":\"UnaryOp\",\"op\":{\"tag\":\"USub\"},\"operand\":{\"tag\":\"BinOp\",\"left\":{\"tag\":\"Constant\",\"_raw\":\"2\",\"kind\":null,\"_loc\":[1,10,1,11]},\"op\":{\"tag\":\"Pow\"},\"right\":{\"tag\":\"Constant\",\"_raw\":\"2\",\"kind\":null,\"_loc\":[1,13,1,14]},\"_loc\":[1,10,1,14]},\"_loc\":[1,9,1,14]},\"op\":{\"tag\"" ++ ":\"Add\"},\"right\":{\"tag\":\"IfExp\",\"test\":{\"tag\":\"UnaryOp\",\"op\":{\"tag\":\"Not\"},\"operand\":{\"tag\":\"Compare\",\"left\":{\"tag\":\"Name\",\"id\":\"b\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,27,1,28]},\"ops\":[{\"tag\":\"In\"}],\"comparators\":[{\"tag\":\"Name\",\"id\":\"c\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,32,1,33]}],\"_loc\":[1,27,1,33]},\"_loc\":[1,23,1,33]},\"body\":{\"tag\":\"Name\",\"id\":\"a\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,18,1,19]},\"orelse\":{\"tag\":\"Name\",\"id\":\"" ++ "d\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,39,1,40]},\"_loc\":[1,18,1,40]},\"_loc\":[1,9,1,41]},\"type_comment\":null,\"_loc\":[1,0,1,41]}],\"type_ignores\":[]}")

#|True{}
