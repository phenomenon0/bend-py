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
  String.eq(show(parse("x = (u\"p\" f\"a{{{b!r:>{w}}}}\\n\"\n     rf\"\\d{c = :{d}e}\")\nlog(f\"\"\"{x,\n y=}\"\"\")\n")), "{\"tag\":\"Module\",\"body\":[{\"tag\":\"Assign\",\"targets\":[{\"tag\":\"Name\",\"id\":\"x\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[1,0,1,1]}],\"value\":{\"tag\":\"JoinedStr\",\"values\":[{\"tag\":\"Constant\",\"_parts\":[[\"s\",\"u\\\"p\\\"\"],[\"f\",\"a{\"]],\"kind\":\"u\",\"_loc\":[1,5,2,22]},{\"tag\":\"FormattedValue\",\"value\":{\"tag\":\"Name\",\"id\":\"b\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,16,1,17]},\"conversion\":114,\"format_spec\":{\"tag\":\"JoinedStr\",\"values\":[{\"tag\":\"Constant\",\"_parts\":[[\"f\",\">\"]],\"kind\":\"u\",\"_loc\":[1,5,2,22]},{\"tag\":\"FormattedValue\",\"value\":{\"tag\":\"Name\",\"id\"" ++
      ":\"w\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[1,22,1,23]},\"conversion\":-1,\"format_spec\":null,\"_loc\":[1,5,2,22]}],\"_loc\":[1,10,1,30]},\"_loc\":[1,5,2,22]},{\"tag\":\"Constant\",\"_parts\":[[\"f\",\"}\\\\n\"],[\"v\",\"\\\\d\"],[\"v\",\"c = \"]],\"kind\":\"u\",\"_loc\":[1,5,2,22]},{\"tag\":\"FormattedValue\",\"value\":{\"tag\":\"Name\",\"id\":\"c\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,11,2,12]},\"conversion\":-1,\"format_spec\":{\"tag\":\"JoinedStr\",\"values\":[{\"tag\":\"FormattedValue\",\"value\":{\"tag\":\"Name\",\"id\":\"d\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[2,17,2,18]},\"conversion\":-1,\"format_" ++
      "spec\":null,\"_loc\":[1,5,2,22]},{\"tag\":\"Constant\",\"_parts\":[[\"v\",\"e\"]],\"kind\":null,\"_loc\":[2,5,2,22]}],\"_loc\":[2,5,2,22]},\"_loc\":[1,5,2,22]}],\"_loc\":[1,5,2,22]},\"type_comment\":null,\"_loc\":[1,0,2,23]},{\"tag\":\"Expr\",\"value\":{\"tag\":\"Call\",\"func\":{\"tag\":\"Name\",\"id\":\"log\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[3,0,3,3]},\"args\":[{\"tag\":\"JoinedStr\",\"values\":[{\"tag\":\"Constant\",\"_parts\":[[\"v\",\"x,\\u000a y=\"]],\"kind\":null,\"_loc\":[3,4,4,7]},{\"tag\":\"FormattedValue\",\"value\":{\"tag\":\"Tuple\",\"elts\":[{\"tag\":\"Name\",\"id\":\"x\",\"ctx\":{\"tag\":" ++
      "\"Load\"},\"_loc\":[3,9,3,10]},{\"tag\":\"Name\",\"id\":\"y\",\"ctx\":{\"tag\":\"Load\"},\"_loc\":[4,1,4,2]}],\"ctx\":{\"tag\":\"Load\"},\"_loc\":[3,8,4,3]},\"conversion\":114,\"format_spec\":null,\"_loc\":[3,4,4,7]}],\"_loc\":[3,4,4,7]}],\"keywords\":[],\"_loc\":[3,0,4,8]},\"_loc\":[3,0,4,8]}],\"type_ignores\":[]}") &&
    String.eq(kind(parse("f\"{x!z}\"")), "Syntax") &&
    String.eq(kind(parse("f\"{}\"")), "Syntax") &&
    String.eq(kind(parse("f\"{a}}\"")), "Syntax") &&
    String.eq(kind(parse("f\"{x:{y:{z}}}\"")), "Syntax") &&
    String.eq(kind(parse("f\"{x}\" b\"a\"")), "Syntax") &&
    String.eq(kind(parse("f\"{lambda x: 1}\"")), "Syntax") &&
    String.eq(kind(parse("f\"{(x := 1)}\"")), "Done")

#|True{}
