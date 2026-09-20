import Base
import ../../demos/python/lexer.bend as L
import ../../demos/python/syntax.bend as S

def words(ts: List<&2, S.Tok>) -> String:
  match ts:
    case Nil{}:
      ""
    case Con{S.Tok{k, text, lo, hi}, rest}:
      k ++ ":" ++ text ++ "|" ++ words(rest)

def show(r: Result<&2, &2, S.Error, List<&2, S.Tok>>) -> String:
  match r:
    case Done{ts}:
      words(ts)
    case Fail{e}:
      S.error_text(e)

def main() -> Bool:
  String.eq(show(L.lex("x = (1 +\n 2) + \\\n 3 # end\r\n")), "NAME:x|OP:=|OP:(|NUMBER:1|OP:+|NUMBER:2|OP:)|OP:+|NUMBER:3|NEWLINE:\r\n|ENDMARKER:|")

#|True{}
