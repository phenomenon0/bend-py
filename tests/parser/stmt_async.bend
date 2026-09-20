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
  String.eq(show(parse("@d\nasync def f(a):\n    async with a as b, c:\n        async for x in await b: y = [await z async for z in x if z]\n        else: return await y ** 2\n")), "{\"tag\":\"Module\",\"body\":[{\"tag\":\"AsyncFunctionDef\",\"name\":\"f\",\"args\":{\"tag\":\"arguments\",\"posonlyargs\":[],\"args\":[{\"tag\":\"arg\",\"arg\":\"a\",\"annotation\":null,\"type_comment\":null,\"_loc\":[2,12,2,13]}],\"vararg\":null,\"kwonlyargs\":[],\"kw_defaults\":[],\"kwarg\":null,\"defaults\":[]},\"body\":[{\"tag\":\"AsyncWith\",\"items\":[{\"tag\":\"withitem\",\"context_expr\":{\"tag\":\"Name\",\"id\":\"a\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[3,15,3,16]},\"optional_vars\":{\"tag\":\"Name\",\"id\":\"b\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[3,20,3,21]}},{\"tag\":\"withitem\",\"context_e" ++
      "xpr\":{\"tag\":\"Name\",\"id\":\"c\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[3,23,3,24]},\"optional_vars\":null}],\"body\":[{\"tag\":\"AsyncFor\",\"target\":{\"tag\":\"Name\",\"id\":\"x\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[4,18,4,19]},\"iter\":{\"tag\":\"Await\",\"value\":{\"tag\":\"Name\",\"id\":\"b\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[4,29,4,30]},\"_loc\":[4,23,4,30]},\"body\":[{\"tag\":\"Assign\",\"targets\":[{\"tag\":\"Name\",\"id\":\"y\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[4,32,4,33]}],\"value\":{\"tag\":\"ListComp\",\"elt\":{\"tag\":\"Await\",\"value\":{\"tag\":\"Name\",\"id\":\"z\",\"ctx\":{\"tag\":\"Load\"},\"_loc\"" ++
      ":[4,43,4,44]},\"_loc\":[4,37,4,44]},\"generators\":[{\"tag\":\"comprehension\",\"target\":{\"tag\":\"Name\",\"id\":\"z\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[4,55,4,56]},\"iter\":{\"tag\":\"Name\",\"id\":\"x\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[4,60,4,61]},\"ifs\":[{\"tag\":\"Name\",\"id\":\"z\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[4,65,4,66]}],\"is_async\":1}],\"_loc\":[4,36,4,67]},\"type_comment\":null,\"_loc\":[4,32,4,67]}],\"orelse\":[{\"tag\":\"Return\",\"value\":{\"tag\":\"BinOp\",\"left\":{\"tag\":\"Await\",\"value\":{\"tag\":\"Name\",\"id\":\"y\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[5,27,5,28]},\"_loc" ++
      "\":[5,21,5,28]},\"op\":{\"tag\":\"Pow\"},\"right\":{\"tag\":\"Constant\",\"_raw\":\"2\",\"kind\":null,\"_loc\":[5,32,5,33]},\"_loc\":[5,21,5,33]},\"_loc\":[5,14,5,33]}],\"type_comment\":null,\"_loc\":[4,8,5,33]}],\"type_comment\":null,\"_loc\":[3,4,5,33]}],\"decorator_list\":[{\"tag\":\"Name\",\"id\":\"d\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,1,1,2]}],\"returns\":null,\"type_comment\":null,\"_loc\":[2,0,5,33]}],\"type_ignores\":[]}") &&
    String.eq(kind(parse("async def f(): pass")), "Done") &&
    String.eq(kind(parse("async for x in y: pass")), "Done") &&
    String.eq(kind(parse("async with (a as b, c): pass")), "Done") &&
    String.eq(kind(parse("@d\nasync def f(): pass")), "Done") &&
    String.eq(kind(parse("[x async for x in y]")), "Done") &&
    String.eq(kind(parse("f(x async for x in y)")), "Done") &&
    String.eq(kind(parse("{a: b async for a in c}")), "Done") &&
    String.eq(kind(parse("await x")), "Done") &&
    String.eq(kind(parse("await x ** 2")), "Done") &&
    String.eq(kind(parse("-await x")), "Done") &&
    String.eq(kind(parse("await (await x)")), "Done") &&
    String.eq(kind(parse("(await x).y = 1")), "Done") &&
    String.eq(kind(parse("f'{await x}'")), "Done") &&
    String.eq(kind(parse("yield await x")), "Done") &&
    String.eq(kind(parse("lambda: await x")), "Done") &&
    String.eq(kind(parse("await(x)")), "Done") &&
    String.eq(kind(parse("async = 1")), "Syntax") &&
    String.eq(kind(parse("async()")), "Syntax") &&
    String.eq(kind(parse("x.async")), "Syntax") &&
    String.eq(kind(parse("def await(): pass")), "Syntax") &&
    String.eq(kind(parse("f(await=1)")), "Syntax") &&
    String.eq(kind(parse("await")), "Syntax") &&
    String.eq(kind(parse("await -x")), "Syntax") &&
    String.eq(kind(parse("await await x")), "Syntax") &&
    String.eq(kind(parse("await not x")), "Syntax") &&
    String.eq(kind(parse("await lambda: 1")), "Syntax") &&
    String.eq(kind(parse("await x = 1")), "Syntax") &&
    String.eq(kind(parse("(await x) = 1")), "Syntax") &&
    String.eq(kind(parse("del await x")), "Syntax") &&
    String.eq(kind(parse("(await x): int")), "Syntax") &&
    String.eq(kind(parse("async class A: pass")), "Syntax") &&
    String.eq(kind(parse("async\ndef f(): pass")), "Syntax") &&
    String.eq(kind(parse("@d\nasync for x in y: pass")), "Syntax") &&
    String.eq(kind(parse("[x async in y]")), "Syntax") &&
    String.eq(kind(parse("[async for x in y]")), "Syntax") &&
    String.eq(kind(parse("async with: pass")), "Syntax") &&
    String.eq(kind(parse("await (x := 1)")), "Done") &&
    String.eq(kind(parse("[x async for x in (y := z)]")), "Done") &&
    String.eq(kind(parse("async def f(): await ﬁ")), "Unsupported")

#|True{}
