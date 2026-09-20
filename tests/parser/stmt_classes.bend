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
  String.eq(show(parse("@d(x)\nclass A(B, *c, metaclass=M, **k):\n    \"doc\"\n    class C: pass\n    def f(self):\n        return 1\nclass D(): y = 1\n")), "{\"tag\":\"Module\",\"body\":[{\"tag\":\"ClassDef\",\"name\":\"A\",\"bases\":[{\"tag\":\"Name\",\"id\":\"B\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,8,2,9]},{\"tag\":\"Starred\",\"value\":{\"tag\":\"Name\",\"id\":\"c\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,12,2,13]},\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,11,2,13]}],\"keywords\":[{\"tag\":\"keyword\",\"arg\":\"metaclass\",\"value\":{\"tag\":\"Name\",\"id\":\"M\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,25,2,26]},\"_loc\":[2,15,2,26]},{\"tag\":\"keyword\",\"arg\":null,\"value\":{\"tag\":\"Name\",\"id\":\"k\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,30,2,31]},\"_loc\":[2,28,2,31]" ++
      "}],\"body\":[{\"tag\":\"Expr\",\"value\":{\"tag\":\"Constant\",\"_raw\":\" \\\"doc\\\"\",\"kind\":null,\"_loc\":[3,4,3,9]},\"_loc\":[3,4,3,9]},{\"tag\":\"ClassDef\",\"name\":\"C\",\"bases\":[],\"keywords\":[],\"body\":[{\"tag\":\"Pass\",\"_loc\":[4,13,4,17]}],\"decorator_list\":[],\"_loc\":[4,4,4,17]},{\"tag\":\"FunctionDef\",\"name\":\"f\",\"args\":{\"tag\":\"arguments\",\"posonlyargs\":[],\"args\":[{\"tag\":\"arg\",\"arg\":\"self\",\"annotation\":null,\"type_comment\":null,\"_loc\":[5,10,5,14]}],\"vararg\":null,\"kwonlyargs\":[],\"kw_defaults\":[],\"kwarg\":null,\"defaults\":[]},\"body\":[{\"tag\":\"" ++
      "Return\",\"value\":{\"tag\":\"Constant\",\"_raw\":\"1\",\"kind\":null,\"_loc\":[6,15,6,16]},\"_loc\":[6,8,6,16]}],\"decorator_list\":[],\"returns\":null,\"type_comment\":null,\"_loc\":[5,4,6,16]}],\"decorator_list\":[{\"tag\":\"Call\",\"func\":{\"tag\":\"Name\",\"id\":\"d\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,1,1,2]},\"args\":[{\"tag\":\"Name\",\"id\":\"x\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,3,1,4]}],\"keywords\":[],\"_loc\":[1,1,1,5]}],\"_loc\":[2,0,6,16]},{\"tag\":\"ClassDef\",\"name\":\"D\",\"bases\":[],\"keywords\":[],\"body\":[{\"tag\":\"Assign\",\"targets\":[{\"tag\":\"Name\",\"id\":\"y\",\"ctx" ++
      "\":{\"tag\":\"Store\"},\"_loc\":[7,11,7,12]}],\"value\":{\"tag\":\"Constant\",\"_raw\":\"1\",\"kind\":null,\"_loc\":[7,15,7,16]},\"type_comment\":null,\"_loc\":[7,11,7,16]}],\"decorator_list\":[],\"_loc\":[7,0,7,16]}],\"type_ignores\":[]}") &&
    String.eq(kind(parse("class A(B: pass")), "Syntax") &&
    String.eq(kind(parse("class A(x=1, y): pass")), "Syntax") &&
    String.eq(kind(parse("@d\nx = 1")), "Syntax") &&
    String.eq(kind(parse("class ﬁ: pass")), "Unsupported")

#|True{}
