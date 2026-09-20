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
  String.eq(show(parse("x = {k: [v for *v, in k if v] for k in d}\nf({g(a, b)} for a, (b, c[0]) in z if a if b for c.d in a)\n")), "{\"tag\":\"Module\",\"body\":[{\"tag\":\"Assign\",\"targets\":[{\"tag\":\"Name\",\"id\":\"x\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[1,0,1,1]}],\"value\":{\"tag\":\"DictComp\",\"key\":{\"tag\":\"Name\",\"id\":\"k\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,5,1,6]},\"value\":{\"tag\":\"ListComp\",\"elt\":{\"tag\":\"Name\",\"id\":\"v\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,9,1,10]},\"generators\":[{\"tag\":\"comprehension\",\"target\":{\"tag\":\"Tuple\",\"elts\":[{\"tag\":\"Starred\",\"value\":{\"tag\":\"Name\",\"id\":\"v\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[1,16,1,17]},\"ctx\":{\"tag\":\"Store\"},\"_loc\":[1,15,1,17]}],\"ctx\":" ++
      "{\"tag\":\"Store\"},\"_loc\":[1,15,1,18]},\"iter\":{\"tag\":\"Name\",\"id\":\"k\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,22,1,23]},\"ifs\":[{\"tag\":\"Name\",\"id\":\"v\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,27,1,28]}],\"is_async\":0}],\"_loc\":[1,8,1,29]},\"generators\":[{\"tag\":\"comprehension\",\"target\":{\"tag\":\"Name\",\"id\":\"k\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[1,34,1,35]},\"iter\":{\"tag\":\"Name\",\"id\":\"d\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,39,1,40]},\"ifs\":[],\"is_async\":0}],\"_loc\":[1,4,1,41]},\"type_comment\":null,\"_loc\":[1,0,1,41]},{\"tag\":\"Expr\",\"value\":{\"tag\":\"Call\"" ++
      ",\"func\":{\"tag\":\"Name\",\"id\":\"f\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,0,2,1]},\"args\":[{\"tag\":\"GeneratorExp\",\"elt\":{\"tag\":\"Set\",\"elts\":[{\"tag\":\"Call\",\"func\":{\"tag\":\"Name\",\"id\":\"g\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,3,2,4]},\"args\":[{\"tag\":\"Name\",\"id\":\"a\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,5,2,6]},{\"tag\":\"Name\",\"id\":\"b\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,8,2,9]}],\"keywords\":[],\"_loc\":[2,3,2,10]}],\"_loc\":[2,2,2,11]},\"generators\":[{\"tag\":\"comprehension\",\"target\":{\"tag\":\"Tuple\",\"elts\":[{\"tag\":\"Name\",\"id\":\"a\",\"ctx\":{\"tag\":\"Store\"},\"_" ++
      "loc\":[2,16,2,17]},{\"tag\":\"Tuple\",\"elts\":[{\"tag\":\"Name\",\"id\":\"b\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[2,20,2,21]},{\"tag\":\"Subscript\",\"value\":{\"tag\":\"Name\",\"id\":\"c\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,23,2,24]},\"slice\":{\"tag\":\"Constant\",\"_raw\":\"0\",\"kind\":null,\"_loc\":[2,25,2,26]},\"ctx\":{\"tag\":\"Store\"},\"_loc\":[2,23,2,27]}],\"ctx\":{\"tag\":\"Store\"},\"_loc\":[2,19,2,28]}],\"ctx\":{\"tag\":\"Store\"},\"_loc\":[2,16,2,28]},\"iter\":{\"tag\":\"Name\",\"id\":\"z\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,32,2,33]},\"ifs\":[{\"tag\":\"Name\",\"id\":\"a\",\"ctx\":{\"tag\":\"Loa" ++
      "d\"},\"_loc\":[2,37,2,38]},{\"tag\":\"Name\",\"id\":\"b\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,42,2,43]}],\"is_async\":0},{\"tag\":\"comprehension\",\"target\":{\"tag\":\"Attribute\",\"value\":{\"tag\":\"Name\",\"id\":\"c\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,48,2,49]},\"attr\":\"d\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[2,48,2,51]},\"iter\":{\"tag\":\"Name\",\"id\":\"a\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,55,2,56]},\"ifs\":[],\"is_async\":0}],\"_loc\":[2,1,2,57]}],\"keywords\":[],\"_loc\":[2,0,2,57]},\"_loc\":[2,0,2,57]}],\"type_ignores\":[]}") &&
    String.eq(kind(parse("[*a for a in b]")), "Syntax") &&
    String.eq(kind(parse("f(x for x in y, 1)")), "Syntax") &&
    String.eq(kind(parse("class A(x for x in y): pass")), "Syntax") &&
    String.eq(kind(parse("{**a for a in b}")), "Syntax") &&
    String.eq(kind(parse("(a, b for a in c)")), "Syntax") &&
    String.eq(kind(parse("[x for x in a if b else c]")), "Syntax") &&
    String.eq(kind(parse("[x for x in lambda: y]")), "Syntax") &&
    String.eq(kind(parse("a[x for x in y]")), "Syntax") &&
    String.eq(kind(parse("[x for x in y] = 1")), "Syntax") &&
    String.eq(kind(parse("[x for x in (y := z)]")), "Done") &&
    String.eq(kind(parse("[x := 1 for x in y]")), "Done")

#|True{}
