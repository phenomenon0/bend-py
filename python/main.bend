# PY_SOURCE names a UTF-8 file. PY_MODE=lex selects the token JSON interface.
import Base
import ./syntax.bend as S
import ./intake.bend as I
import ./lexer.bend as L
import ./parser.bend as P

def emit(+mode: String, +ts: List<&2, S.Tok>) -> IO(Unit):
  S.choose(IO(Unit), String.eq(mode, "lex"), u =>
    IO.print(S.json(S.JArr{S.toks(ts)})), u =>
    S.choose(IO(Unit), String.eq(mode, "stats"), u =>
      do IO<Unit>:
        stats : S.Json <- I.unwrap(&2, S.Json, P.stats(ts))
        IO.print(S.json(stats)), u =>
    do IO<Unit>:
      m : S.Module <- I.unwrap(&2, S.Module, P.parse(ts))
      IO.print(S.json(S.module(m)))))

def mode(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Done{s}:
      s
    case Fail{e}:
      "parse"

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, IO.get_env("PY_SOURCE"))
    opt : Result<&1, &1, U32 & String, String> <- IO.get_env("PY_MODE")
    source : String <- I.load(path)
    ts : List<&2, S.Tok> <- I.unwrap(&2, List<&2, S.Tok>, L.lex(source))
    emit(mode(opt), ts)
