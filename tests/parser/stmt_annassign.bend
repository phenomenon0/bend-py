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
  String.eq(show(parse("class A(B):\n    x: int\n    y: Optional[List[int]] = None\n    def f(self):\n        self.z: 'T' = 1, *y\n        a[0]: T\n(w): int = 0\n")), "{\"tag\":\"Module\",\"body\":[{\"tag\":\"ClassDef\",\"name\":\"A\",\"bases\":[{\"tag\":\"Name\",\"id\":\"B\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,8,1,9]}],\"keywords\":[],\"body\":[{\"tag\":\"AnnAssign\",\"target\":{\"tag\":\"Name\",\"id\":\"x\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[2,4,2,5]},\"annotation\":{\"tag\":\"Name\",\"id\":\"int\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,7,2,10]},\"value\":null,\"simple\":1,\"_loc\":[2,4,2,10]},{\"tag\":\"AnnAssign\",\"target\":{\"tag\":\"Name\",\"id\":\"y\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[3,4,3,5]},\"annotation\":{\"tag\":\"Subscript\",\"value\":{\"tag\":\"Name\",\"id\":\"Op" ++
      "tional\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[3,7,3,15]},\"slice\":{\"tag\":\"Subscript\",\"value\":{\"tag\":\"Name\",\"id\":\"List\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[3,16,3,20]},\"slice\":{\"tag\":\"Name\",\"id\":\"int\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[3,21,3,24]},\"ctx\":{\"tag\":\"Load\"},\"_loc\":[3,16,3,25]},\"ctx\":{\"tag\":\"Load\"},\"_loc\":[3,7,3,26]},\"value\":{\"tag\":\"Constant\",\"_raw\":\"None\",\"kind\":null,\"_loc\":[3,29,3,33]},\"simple\":1,\"_loc\":[3,4,3,33]},{\"tag\":\"FunctionDef\",\"name\":\"f\",\"args\":{\"tag\":\"arguments\",\"posonlyargs\":[],\"args\":[{\"tag\":\"arg\",\"arg\":\"se" ++
      "lf\",\"annotation\":null,\"type_comment\":null,\"_loc\":[4,10,4,14]}],\"vararg\":null,\"kwonlyargs\":[],\"kw_defaults\":[],\"kwarg\":null,\"defaults\":[]},\"body\":[{\"tag\":\"AnnAssign\",\"target\":{\"tag\":\"Attribute\",\"value\":{\"tag\":\"Name\",\"id\":\"self\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[5,8,5,12]},\"attr\":\"z\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[5,8,5,14]},\"annotation\":{\"tag\":\"Constant\",\"_raw\":\" 'T'\",\"kind\":null,\"_loc\":[5,16,5,19]},\"value\":{\"tag\":\"Tuple\",\"elts\":[{\"tag\":\"Constant\",\"_raw\":\"1\",\"kind\":null,\"_loc\":[5,22,5,23]},{\"tag\":\"Starred\",\"value\"" ++
      ":{\"tag\":\"Name\",\"id\":\"y\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[5,26,5,27]},\"ctx\":{\"tag\":\"Load\"},\"_loc\":[5,25,5,27]}],\"ctx\":{\"tag\":\"Load\"},\"_loc\":[5,22,5,27]},\"simple\":0,\"_loc\":[5,8,5,27]},{\"tag\":\"AnnAssign\",\"target\":{\"tag\":\"Subscript\",\"value\":{\"tag\":\"Name\",\"id\":\"a\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[6,8,6,9]},\"slice\":{\"tag\":\"Constant\",\"_raw\":\"0\",\"kind\":null,\"_loc\":[6,10,6,11]},\"ctx\":{\"tag\":\"Store\"},\"_loc\":[6,8,6,12]},\"annotation\":{\"tag\":\"Name\",\"id\":\"T\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[6,14,6,15]},\"value\":null,\"simple\":0,\"_loc\"" ++
      ":[6,8,6,15]}],\"decorator_list\":[],\"returns\":null,\"type_comment\":null,\"_loc\":[4,4,6,15]}],\"decorator_list\":[],\"_loc\":[1,0,6,15]},{\"tag\":\"AnnAssign\",\"target\":{\"tag\":\"Name\",\"id\":\"w\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[7,1,7,2]},\"annotation\":{\"tag\":\"Name\",\"id\":\"int\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[7,5,7,8]},\"value\":{\"tag\":\"Constant\",\"_raw\":\"0\",\"kind\":null,\"_loc\":[7,11,7,12]},\"simple\":0,\"_loc\":[7,0,7,12]}],\"type_ignores\":[]}") &&
    String.eq(kind(parse("x, y: int")), "Syntax") &&
    String.eq(kind(parse("(x, y): int")), "Syntax") &&
    String.eq(kind(parse("[x]: int")), "Syntax") &&
    String.eq(kind(parse("f(): int")), "Syntax") &&
    String.eq(kind(parse("(a).b: T")), "Syntax") &&
    String.eq(kind(parse("((a))[0]: T")), "Syntax") &&
    String.eq(kind(parse("((a).b): T")), "Done") &&
    String.eq(kind(parse("(f()).c: T")), "Done") &&
    String.eq(kind(parse("x: a, b")), "Syntax") &&
    String.eq(kind(parse("x: *a")), "Syntax") &&
    String.eq(kind(parse("x: int = y = 1")), "Syntax") &&
    String.eq(kind(parse("x = y: int")), "Syntax") &&
    String.eq(kind(parse("x: int += 1")), "Syntax") &&
    String.eq(kind(parse("x: ")), "Syntax") &&
    String.eq(kind(parse("x: int = (y := 1)")), "Done") &&
    String.eq(kind(parse("x: (y := 1)")), "Done") &&
    String.eq(kind(parse("match (x):\n    case _: pass\n")), "Done") &&
    String.eq(kind(parse("match [x]:\n    case _: pass\n")), "Done")

#|True{}
