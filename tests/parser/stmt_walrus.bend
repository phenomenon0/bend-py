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
  String.eq(show(parse("@(d := e)\ndef f(a):\n    if (n := len(a)) > 1: return [y := f(n), y ** 2]\n    while c := a.pop(): print(f\"{(z := c)!r}\", k=(w := z), *[v for v in a if (u := v)])\n")), ("{\"tag\":\"Module\",\"body\":[{\"tag\":\"FunctionDef\",\"name\":\"f\",\"args\":{\"tag\":\"arguments\",\"posonlyargs\":[],\"args\":[{\"tag\":\"arg\",\"arg\":\"a\",\"annotation\":null,\"type_comment\":null,\"_loc\":[2,6,2,7]}],\"vararg\":null,\"kwonlyargs\":[],\"kw_defaults\":[],\"kwarg\":null,\"defaults\":[]},\"body\":[{\"tag\":\"If\",\"test\":{\"tag\":\"Compare\",\"left\":{\"tag\":\"NamedExpr\",\"target\":{\"tag\":\"Name\",\"id\":\"n\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[3,8,3,9]},\"value\":{\"tag\":\"Cal" ++ "l\",\"func\":{\"tag\":\"Name\",\"id\":\"len\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[3,13,3,16]},\"args\":[{\"tag\":\"Name\",\"id\":\"a\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[3,17,3,18]}],\"keywords\":[],\"_loc\":[3,13,3,19]},\"_loc\":[3,8,3,19]},\"ops\":[{\"tag\":\"Gt\"}],\"comparators\":[{\"tag\":\"Constant\",\"_raw\":\"1\",\"kind\":null,\"_loc\":[3,23,3,24]}],\"_loc\":[3,7,3,24]},\"body\":[{\"tag\":\"Return\",\"value\":{\"tag\":\"List\",\"elts\":[{\"tag\":\"NamedExpr\",\"target\":{\"tag\":\"Name\",\"id\":" ++ "\"y\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[3,34,3,35]},\"value\":{\"tag\":\"Call\",\"func\":{\"tag\":\"Name\",\"id\":\"f\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[3,39,3,40]},\"args\":[{\"tag\":\"Name\",\"id\":\"n\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[3,41,3,42]}],\"keywords\":[],\"_loc\":[3,39,3,43]},\"_loc\":[3,34,3,43]},{\"tag\":\"BinOp\",\"left\":{\"tag\":\"Name\",\"id\":\"y\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[3,45,3,46]},\"op\":{\"tag\":\"Pow\"},\"right\":{\"tag\":\"" ++ "Constant\",\"_raw\":\"2\",\"kind\":null,\"_loc\":[3,50,3,51]},\"_loc\":[3,45,3,51]}],\"ctx\":{\"tag\":\"Load\"},\"_loc\":[3,33,3,52]},\"_loc\":[3,26,3,52]}],\"orelse\":[],\"_loc\":[3,4,3,52]},{\"tag\":\"While\",\"test\":{\"tag\":\"NamedExpr\",\"target\":{\"tag\":\"Name\",\"id\":\"c\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[4,10,4,11]},\"value\":{\"tag\":\"Call\",\"func\":{\"tag\":\"Attribute\",\"value\":{\"tag\":\"Name\",\"id\":\"a\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[4,15,4,16]},\"attr\":\"pop\",\"ctx\":{" ++ "\"tag\":\"Load\"},\"_loc\":[4,15,4,20]},\"args\":[],\"keywords\":[],\"_loc\":[4,15,4,22]},\"_loc\":[4,10,4,22]},\"body\":[{\"tag\":\"Expr\",\"value\":{\"tag\":\"Call\",\"func\":{\"tag\":\"Name\",\"id\":\"print\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[4,24,4,29]},\"args\":[{\"tag\":\"JoinedStr\",\"values\":[{\"tag\":\"FormattedValue\",\"value\":{\"tag\":\"NamedExpr\",\"target\":{\"tag\":\"Name\",\"id\":\"z\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[4,34,4,35]},\"value\":{\"tag\":\"Name\",\"id\":\"c\",\"ctx\":{\"t" ++ "ag\":\"Load\"},\"_loc\":[4,39,4,40]},\"_loc\":[4,34,4,40]},\"conversion\":114,\"format_spec\":null,\"_loc\":[4,30,4,45]}],\"_loc\":[4,30,4,45]},{\"tag\":\"Starred\",\"value\":{\"tag\":\"ListComp\",\"elt\":{\"tag\":\"Name\",\"id\":\"v\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[4,61,4,62]},\"generators\":[{\"tag\":\"comprehension\",\"target\":{\"tag\":\"Name\",\"id\":\"v\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[4,67,4,68]},\"iter\":{\"tag\":\"Name\",\"id\":\"a\",\"ctx\":{\"tag\":" ++ "\"Load\"},\"_loc\":[4,72,4,73]},\"ifs\":[{\"tag\":\"NamedExpr\",\"target\":{\"tag\":\"Name\",\"id\":\"u\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[4,78,4,79]},\"value\":{\"tag\":\"Name\",\"id\":\"v\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[4,83,4,84]},\"_loc\":[4,78,4,84]}],\"is_async\":0}],\"_loc\":[4,60,4,86]},\"ctx\":{\"tag\":\"Load\"},\"_loc\":[4,59,4,86]}],\"keywords\":[{\"tag\":\"keyword\",\"arg\":\"k\",\"value\":{\"tag\":\"NamedExpr\",\"target\":{\"tag\":\"Name\",\"id\":\"w\",\"ctx\":{\"tag\":\"Store\"},\"" ++ "_loc\":[4,50,4,51]},\"value\":{\"tag\":\"Name\",\"id\":\"z\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[4,55,4,56]},\"_loc\":[4,50,4,56]},\"_loc\":[4,47,4,57]}],\"_loc\":[4,24,4,87]},\"_loc\":[4,24,4,87]}],\"orelse\":[],\"_loc\":[4,4,4,87]}],\"decorator_list\":[{\"tag\":\"NamedExpr\",\"target\":{\"tag\":\"Name\",\"id\":\"d\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[1,2,1,3]},\"value\":{\"tag\":\"Name\",\"id\":\"e\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,7,1,8]},\"_loc\":[1,2,1,8]}],\"returns\":null,\"type_comment\":" ++ "null,\"_loc\":[2,0,4,87]}],\"type_ignores\":[]}")) &&
    String.eq(kind(parse("(x := 1)")), "Done") &&
    String.eq(kind(parse("if x := 1: pass")), "Done") &&
    String.eq(kind(parse("f(x := 1, y := 2)")), "Done") &&
    String.eq(kind(parse("a[x := 1]")), "Done") &&
    String.eq(kind(parse("a[(x := 1):2]")), "Done") &&
    String.eq(kind(parse("[y := f(x) for x in z]")), "Done") &&
    String.eq(kind(parse("[x for x in y if (z := x)]")), "Done") &&
    String.eq(kind(parse("{(k := a): (v := b)}")), "Done") &&
    String.eq(kind(parse("f\"{(x := 1)}\"")), "Done") &&
    String.eq(kind(parse("(x := (y := 1))")), "Done") &&
    String.eq(kind(parse("lambda: (x := 1)")), "Done") &&
    String.eq(kind(parse("yield (x := 1)")), "Done") &&
    String.eq(kind(parse("await (x := 1)")), "Done") &&
    String.eq(kind(parse("with (x := 1): pass")), "Done") &&
    String.eq(kind(parse("@(x := d)\ndef f(): pass")), "Done") &&
    String.eq(kind(parse("f\"{x:=1}\"")), "Done") &&
    String.eq(kind(parse("x := 1")), "Syntax") &&
    String.eq(kind(parse("x = y := 1")), "Syntax") &&
    String.eq(kind(parse("(a.b := 1)")), "Syntax") &&
    String.eq(kind(parse("(a[0] := 1)")), "Syntax") &&
    String.eq(kind(parse("((x) := 1)")), "Syntax") &&
    String.eq(kind(parse("(x := y := 1)")), "Syntax") &&
    String.eq(kind(parse("f(k=x := 1)")), "Syntax") &&
    String.eq(kind(parse("{x := 1: 2}")), "Syntax") &&
    String.eq(kind(parse("a[1:x := 2]")), "Syntax") &&
    String.eq(kind(parse("a[::=1]")), "Syntax") &&
    String.eq(kind(parse("lambda: x := 1")), "Syntax") &&
    String.eq(kind(parse("[x for x in y := z]")), "Syntax") &&
    String.eq(kind(parse("[x for x in y if z := x]")), "Syntax") &&
    String.eq(kind(parse("x: y := 1")), "Syntax") &&
    String.eq(kind(parse("x: int = y := 1")), "Syntax") &&
    String.eq(kind(parse("yield x := 1")), "Syntax") &&
    String.eq(kind(parse("await := 1")), "Syntax") &&
    String.eq(kind(parse("for a in x := 1: pass")), "Syntax") &&
    String.eq(kind(parse("with x := 1: pass")), "Syntax") &&
    String.eq(kind(parse("(x := 1) = 2")), "Syntax") &&
    String.eq(kind(parse("(x := *a)")), "Syntax") &&
    String.eq(kind(parse("(ﬁ := 1)")), "Unsupported") &&
    String.eq(kind(parse("(x := ﬁ)")), "Unsupported")

#|True{}
