import Base
import ../../../demos/python/syntax.bend as S
import ../../../demos/python/intake.bend as I
import ../../../demos/python/lexer.bend as L
import ./lexer.bend as R

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, IO.get_env("PY_SOURCE"))
    mode : String <- IO.try(String, IO.get_env("PY_LEXER"))
    +source : String <- I.load(path)
    ts : List<&2, S.Tok> <- I.unwrap(&2, List<&2, S.Tok>, S.choose(Result<&2, &2, S.Error, List<&2, S.Tok>>, String.eq(mode, "regex"), u => R.lex(source), u => L.lex(source)))
    IO.print(S.json(S.JArr{S.toks(ts)}))
