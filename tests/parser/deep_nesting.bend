import Base
import ../../demos/python/syntax.bend as S
import ../../demos/python/lexer.bend as L
import ../../demos/python/parser.bend as P

def parse(r: Result<&2, &2, S.Error, List<&2, S.Tok>>) -> Result<&2, &2, S.Error, S.Module>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{ts}:
      P.parse(ts)

def limited(r: Result<&2, &2, S.Error, S.Module>) -> Bool:
  match r:
    case Fail{S.PErr{S.Limit{}, pos, msg}}:
      True{}
    case _:
      False{}

def source(+n: Nat) -> String:
  String.repeat("(", n) ++ "0" ++ String.repeat(")", n)

def main() -> Bool:
  Result.is_done(&2, &2, S.Error, S.Module, parse(L.lex(source(200n)))) && limited(parse(L.lex(source(201n))))

#|True{}
