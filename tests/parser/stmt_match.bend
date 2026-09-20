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
  String.eq(show(parse("def f(s):\n    match s.x, *t:\n        case [0 | -1 as a, *_] | {'k': None, **r} if (n := a): return C(a.b, (p, 'q' \"r\"), y=1+2j)\n        case D.E(True, z=[]) | () as w:\n            match = case = w\n")), ("{\"tag\":\"Module\",\"body\":[{\"tag\":\"FunctionDef\",\"name\":\"f\",\"args\":{\"tag\":\"arguments\",\"posonlyargs\":[],\"args\":[{\"tag\":\"arg\",\"arg\":\"s\",\"annotation\":null,\"type_comment\":null,\"_loc\":[1,6,1,7]}],\"vararg\":null,\"kwonlyargs\":[],\"kw_defaults\":[],\"kwarg\":null,\"defaults\":[]},\"body\":[{\"tag\":\"Match\",\"subject\":{\"tag\":\"Tuple\",\"elts\":[{\"tag\":\"Attribute\",\"value\":{\"tag\":\"Name\",\"id\":\"s\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,10,2,11]},\"attr\":\"x\",\"ct" ++ "x\":{\"tag\":\"Load\"},\"_loc\":[2,10,2,13]},{\"tag\":\"Starred\",\"value\":{\"tag\":\"Name\",\"id\":\"t\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,16,2,17]},\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,15,2,17]}],\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,10,2,17]},\"cases\":[{\"tag\":\"match_case\",\"pattern\":{\"tag\":\"MatchOr\",\"patterns\":[{\"tag\":\"MatchSequence\",\"patterns\":[{\"tag\":\"MatchAs\",\"pattern\":{\"tag\":\"MatchOr\",\"patterns\":[{\"tag\":\"MatchValue\",\"value\":{\"tag\":\"Constant\",\"_raw\":" ++ "\"0\",\"kind\":null,\"_loc\":[3,14,3,15]},\"_loc\":[3,14,3,15]},{\"tag\":\"MatchValue\",\"value\":{\"tag\":\"UnaryOp\",\"op\":{\"tag\":\"USub\"},\"operand\":{\"tag\":\"Constant\",\"_raw\":\"1\",\"kind\":null,\"_loc\":[3,19,3,20]},\"_loc\":[3,18,3,20]},\"_loc\":[3,18,3,20]}],\"_loc\":[3,14,3,20]},\"name\":\"a\",\"_loc\":[3,14,3,25]},{\"tag\":\"MatchStar\",\"name\":null,\"_loc\":[3,27,3,29]}],\"_loc\":[3,13,3,30]},{\"tag\":\"MatchMapping\",\"keys\":[{\"tag\":\"Constant\",\"_" ++ "raw\":\" 'k'\",\"kind\":null,\"_loc\":[3,34,3,37]}],\"patterns\":[{\"tag\":\"MatchSingleton\",\"value\":null,\"_loc\":[3,39,3,43]}],\"rest\":\"r\",\"_loc\":[3,33,3,49]}],\"_loc\":[3,13,3,49]},\"guard\":{\"tag\":\"NamedExpr\",\"target\":{\"tag\":\"Name\",\"id\":\"n\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[3,54,3,55]},\"value\":{\"tag\":\"Name\",\"id\":\"a\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[3,59,3,60]},\"_loc\":[3,54,3,60]},\"body\":[{\"tag\":\"Return\",\"value\":{\"tag\":\"Call\",\"func\":{\"tag\":\"Name" ++ "\",\"id\":\"C\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[3,70,3,71]},\"args\":[{\"tag\":\"Attribute\",\"value\":{\"tag\":\"Name\",\"id\":\"a\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[3,72,3,73]},\"attr\":\"b\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[3,72,3,75]},{\"tag\":\"Tuple\",\"elts\":[{\"tag\":\"Name\",\"id\":\"p\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[3,78,3,79]},{\"tag\":\"Constant\",\"_raw\":\" 'q' \\\"r\\\"\",\"kind\":null,\"_loc\":[3,81,3,88]}],\"ctx\":{\"tag\":\"Load\"},\"_loc\":[3,77,3,89]}],\"keywords\":[" ++ "{\"tag\":\"keyword\",\"arg\":\"y\",\"value\":{\"tag\":\"BinOp\",\"left\":{\"tag\":\"Constant\",\"_raw\":\"1\",\"kind\":null,\"_loc\":[3,93,3,94]},\"op\":{\"tag\":\"Add\"},\"right\":{\"tag\":\"Constant\",\"_raw\":\"2j\",\"kind\":null,\"_loc\":[3,95,3,97]},\"_loc\":[3,93,3,97]},\"_loc\":[3,91,3,97]}],\"_loc\":[3,70,3,98]},\"_loc\":[3,63,3,98]}]},{\"tag\":\"match_case\",\"pattern\":{\"tag\":\"MatchAs\",\"pattern\":{\"tag\":\"MatchOr\",\"patterns\":[{\"tag\":\"MatchClass\",\"c" ++ "ls\":{\"tag\":\"Attribute\",\"value\":{\"tag\":\"Name\",\"id\":\"D\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[4,13,4,14]},\"attr\":\"E\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[4,13,4,16]},\"patterns\":[{\"tag\":\"MatchSingleton\",\"value\":true,\"_loc\":[4,17,4,21]}],\"kwd_attrs\":[\"z\"],\"kwd_patterns\":[{\"tag\":\"MatchSequence\",\"patterns\":[],\"_loc\":[4,25,4,27]}],\"_loc\":[4,13,4,28]},{\"tag\":\"MatchSequence\",\"patterns\":[],\"_loc\":[4,31,4,33]}],\"_loc\":[4,13,4,33]},\"name\":\"w\",\"_loc\":[4,13,4,38" ++ "]},\"guard\":null,\"body\":[{\"tag\":\"Assign\",\"targets\":[{\"tag\":\"Name\",\"id\":\"match\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[5,12,5,17]},{\"tag\":\"Name\",\"id\":\"case\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[5,20,5,24]}],\"value\":{\"tag\":\"Name\",\"id\":\"w\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[5,27,5,28]},\"type_comment\":null,\"_loc\":[5,12,5,28]}]}],\"_loc\":[2,4,5,28]}],\"decorator_list\":[],\"returns\":null,\"type_comment\":null,\"_loc\":[1,0,5,28]}],\"type_ignores\":[]}")) &&
    String.eq(kind(parse("match = 1")), "Done") &&
    String.eq(kind(parse("match(x)")), "Done") &&
    String.eq(kind(parse("case = 2")), "Done") &&
    String.eq(kind(parse("match -x")), "Done") &&
    String.eq(kind(parse("match [x]: int")), "Done") &&
    String.eq(kind(parse("match (x):\n    case _: pass\n")), "Done") &&
    String.eq(kind(parse("match x, *y:\n    case _: pass\n")), "Done") &&
    String.eq(kind(parse("match x := 1:\n    case [a, *_] | {1: _, **r} as b if b: pass\n")), "Done") &&
    String.eq(kind(parse("match x:\n    case C(a, b=1, _=2): pass\n")), "Done") &&
    String.eq(kind(parse("match x:\n    case {_.a: -1 + 2j}: pass\n")), "Done") &&
    String.eq(kind(parse("match x:\n    case 1:\n        match y:\n            case 2: pass\n    case _: pass\n")), "Done") &&
    String.eq(kind(parse("match x: pass")), "Syntax") &&
    String.eq(kind(parse("match x:\n    pass\n")), "Syntax") &&
    String.eq(kind(parse("match x:\n    case 1: pass\n    else: pass\n")), "Syntax") &&
    String.eq(kind(parse("match *x:\n    case 1: pass\n")), "Syntax") &&
    String.eq(kind(parse("case 1: pass")), "Syntax") &&
    String.eq(kind(parse("if a: match x:\n    case 1: pass\n")), "Syntax") &&
    String.eq(kind(parse("match x:\n    case *a: pass\n")), "Syntax") &&
    String.eq(kind(parse("match x:\n    case (*a): pass\n")), "Syntax") &&
    String.eq(kind(parse("match x:\n    case a as _: pass\n")), "Syntax") &&
    String.eq(kind(parse("match x:\n    case _.a: pass\n")), "Syntax") &&
    String.eq(kind(parse("match x:\n    case {a: 1}: pass\n")), "Syntax") &&
    String.eq(kind(parse("match x:\n    case {**r, 1: a}: pass\n")), "Syntax") &&
    String.eq(kind(parse("match x:\n    case {**_}: pass\n")), "Syntax") &&
    String.eq(kind(parse("match x:\n    case C(a=1, b): pass\n")), "Syntax") &&
    String.eq(kind(parse("match x:\n    case C(a, _=1): pass\n")), "Syntax") &&
    String.eq(kind(parse("match x:\n    case 1 + 2: pass\n")), "Syntax") &&
    String.eq(kind(parse("match x:\n    case 2j + 1: pass\n")), "Syntax") &&
    String.eq(kind(parse("match x:\n    case -a: pass\n")), "Syntax") &&
    String.eq(kind(parse("match x:\n    case a[0]: pass\n")), "Syntax") &&
    String.eq(kind(parse("match x:\n    case a if b, c: pass\n")), "Syntax") &&
    String.eq(kind(parse("if a: with b: pass")), "Syntax") &&
    String.eq(kind(parse("if a: def f(): pass")), "Syntax") &&
    String.eq(kind(parse("x = 1; try: pass\nfinally: pass")), "Syntax") &&
    String.eq(kind(parse("f(@)")), "Syntax") &&
    String.eq(kind(parse("{with: 1}")), "Syntax") &&
    String.eq(kind(parse("match ﬁ:\n    case 1: pass\n")), "Unsupported") &&
    String.eq(kind(parse("match x:\n    case ﬁ: pass\n")), "Unsupported")

#|True{}
