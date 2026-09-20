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
  String.eq(show(parse("def f(a):\n    x = y = yield a, *b\n    x += yield from (yield)\n    z: int = yield\n    print((yield), f'{yield x}')\n    yield\n")), "{\"tag\":\"Module\",\"body\":[{\"tag\":\"FunctionDef\",\"name\":\"f\",\"args\":{\"tag\":\"arguments\",\"posonlyargs\":[],\"args\":[{\"tag\":\"arg\",\"arg\":\"a\",\"annotation\":null,\"type_comment\":null,\"_loc\":[1,6,1,7]}],\"vararg\":null,\"kwonlyargs\":[],\"kw_defaults\":[],\"kwarg\":null,\"defaults\":[]},\"body\":[{\"tag\":\"Assign\",\"targets\":[{\"tag\":\"Name\",\"id\":\"x\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[2,4,2,5]},{\"tag\":\"Name\",\"id\":\"y\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[2,8,2,9]}],\"value\":{\"tag\":\"Yield\",\"value\":{\"tag\":\"Tuple\",\"elts\":[{\"tag\":\"Name\",\"id\":\"a\",\"ctx\":{\"tag" ++
      "\":\"Load\"},\"_loc\":[2,18,2,19]},{\"tag\":\"Starred\",\"value\":{\"tag\":\"Name\",\"id\":\"b\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,22,2,23]},\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,21,2,23]}],\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,18,2,23]},\"_loc\":[2,12,2,23]},\"type_comment\":null,\"_loc\":[2,4,2,23]},{\"tag\":\"AugAssign\",\"target\":{\"tag\":\"Name\",\"id\":\"x\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[3,4,3,5]},\"op\":{\"tag\":\"Add\"},\"value\":{\"tag\":\"YieldFrom\",\"value\":{\"tag\":\"Yield\",\"value\":null,\"_loc\":[3,21,3,26]},\"_loc\":[3,9,3,27]},\"_loc\":[3,4,3,27]},{\"tag\":\"AnnAssign\",\"" ++
      "target\":{\"tag\":\"Name\",\"id\":\"z\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[4,4,4,5]},\"annotation\":{\"tag\":\"Name\",\"id\":\"int\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[4,7,4,10]},\"value\":{\"tag\":\"Yield\",\"value\":null,\"_loc\":[4,13,4,18]},\"simple\":1,\"_loc\":[4,4,4,18]},{\"tag\":\"Expr\",\"value\":{\"tag\":\"Call\",\"func\":{\"tag\":\"Name\",\"id\":\"print\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[5,4,5,9]},\"args\":[{\"tag\":\"Yield\",\"value\":null,\"_loc\":[5,11,5,16]},{\"tag\":\"JoinedStr\",\"values\":[{\"tag\":\"FormattedValue\",\"value\":{\"tag\":\"Yield\",\"value\":{\"tag\":\"Name\",\"id\":\"x\",\"ctx\"" ++
      ":{\"tag\":\"Load\"},\"_loc\":[5,28,5,29]},\"_loc\":[5,22,5,29]},\"conversion\":-1,\"format_spec\":null,\"_loc\":[5,19,5,31]}],\"_loc\":[5,19,5,31]}],\"keywords\":[],\"_loc\":[5,4,5,32]},\"_loc\":[5,4,5,32]},{\"tag\":\"Expr\",\"value\":{\"tag\":\"Yield\",\"value\":null,\"_loc\":[6,4,6,9]},\"_loc\":[6,4,6,9]}],\"decorator_list\":[],\"returns\":null,\"type_comment\":null,\"_loc\":[1,0,6,9]}],\"type_ignores\":[]}") &&
    String.eq(kind(parse("yield")), "Done") &&
    String.eq(kind(parse("x = y = yield")), "Done") &&
    String.eq(kind(parse("f'{yield from x}'")), "Done") &&
    String.eq(kind(parse("[(yield) for x in y]")), "Done") &&
    String.eq(kind(parse("((yield) for x in y)")), "Done") &&
    String.eq(kind(parse("lambda: (yield)")), "Done") &&
    String.eq(kind(parse("yield()")), "Done") &&
    String.eq(kind(parse("(yield).x: int")), "Done") &&
    String.eq(kind(parse("foo(yield)")), "Syntax") &&
    String.eq(kind(parse("(yield, 1)")), "Syntax") &&
    String.eq(kind(parse("x = a, yield")), "Syntax") &&
    String.eq(kind(parse("[yield]")), "Syntax") &&
    String.eq(kind(parse("a[yield]")), "Syntax") &&
    String.eq(kind(parse("lambda: yield")), "Syntax") &&
    String.eq(kind(parse("return yield")), "Syntax") &&
    String.eq(kind(parse("yield yield")), "Syntax") &&
    String.eq(kind(parse("yield from a, b")), "Syntax") &&
    String.eq(kind(parse("yield from *a")), "Syntax") &&
    String.eq(kind(parse("yield = 1")), "Syntax") &&
    String.eq(kind(parse("x = yield = 1")), "Syntax") &&
    String.eq(kind(parse("(yield): int")), "Syntax") &&
    String.eq(kind(parse("del (yield)")), "Syntax") &&
    String.eq(kind(parse("(yield x for x in y)")), "Syntax") &&
    String.eq(kind(parse("yield.x")), "Syntax") &&
    String.eq(kind(parse("yield (x := 1)")), "Done") &&
    String.eq(kind(parse("yield await x")), "Done")

#|True{}
