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
  String.eq(show(parse("if a:\n    x = b\nelif c:\n    return d\nelse:\n    while e:\n        continue\n    else:\n        break\n")), "{\"tag\":\"Module\",\"body\":[{\"tag\":\"If\",\"test\":{\"tag\":\"Name\",\"id\":\"a\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,3,1,4]},\"body\":[{\"tag\":\"Assign\",\"targets\":[{\"tag\":\"Name\",\"id\":\"x\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[2,4,2,5]}],\"value\":{\"tag\":\"Name\",\"id\":\"b\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,8,2,9]},\"type_comment\":null,\"_loc\":[2,4,2,9]}],\"orelse\":[{\"tag\":\"If\",\"test\":{\"tag\":\"Name\",\"id\":\"c\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[3,5,3,6]},\"body\":[" ++ "{\"tag\":\"Return\",\"value\":{\"tag\":\"Name\",\"id\":\"d\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[4,11,4,12]},\"_loc\":[4,4,4,12]}],\"orelse\":[{\"tag\":\"While\",\"test\":{\"tag\":\"Name\",\"id\":\"e\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[6,10,6,11]},\"body\":[{\"tag\":\"Continue\",\"_loc\":[7,8,7,16]}],\"orelse\":[{\"tag\":\"Break\",\"_loc\":[9,8,9,13]}],\"_loc\":[6,4,9,13]}],\"_loc\":[3,0,9,13]}],\"_loc\":[1,0,9,13]}],\"type_ignores\":[]}")

#|True{}
