import Base
import ../../demos/python/syntax.bend as S
import ../../demos/python/lexer.bend as L
import ../../demos/python/parser.bend as P

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
  String.eq(kind(parse("1 = x")), "Syntax") &&
    String.eq(kind(parse("f(**x,*y)")), "Syntax") &&
    String.eq(kind(parse("import x,")), "Syntax") &&
    String.eq(kind(parse("class A(B: pass")), "Syntax") &&
    String.eq(kind(parse("x: int = (y := 1)")), "Done") &&
    String.eq(kind(parse("match x:\n    case _: pass\n")), "Done") &&
    String.eq(kind(parse("try: pass\nexcept* E as e: pass\nexcept* (F, G): pass\nelse: pass\nfinally: pass\n")), "Done") &&
    String.eq(kind(parse("try: pass\nexcept*: pass\n")), "Syntax") &&
    String.eq(kind(parse("try: pass\nexcept* E: pass\nexcept F: pass\n")), "Syntax") &&
    String.eq(kind(parse("try: pass\nexcept E: pass\nexcept* F: pass\n")), "Syntax")

#|True{}
