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
  String.eq(show(L.lex("if x:\n\tpass\nelse:\n\tpass\n")), "KW:if|NAME:x|OP::|NEWLINE:\n|INDENT:\t|KW:pass|NEWLINE:\n|DEDENT:|KW:else|OP::|NEWLINE:\n|INDENT:\t|KW:pass|NEWLINE:\n|DEDENT:|ENDMARKER:|")

#|True{}
