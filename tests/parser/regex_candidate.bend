# Both recognizers must emit identical complete token streams in every lane.
import Base
import ../../demos/python/syntax.bend as S
import ../../demos/python/lexer.bend as L
import ./p3/lexer.bend as R

def show(r: Result<&2, &2, S.Error, List<&2, S.Tok>>) -> String:
  match r:
    case Done{ts}:
      S.json(S.JArr{S.toks(ts)})
    case Fail{e}:
      S.error_text(e)

def main() -> Bool:
  +s = {"if name_2:\n\tx = 00 + 123 + 012 + 1_000 + .5 + 1e-3 + 0x1_F\n\ty = r'hi' + '''two\nlines'''\n\téx = aK + 2j\n" : String}
  String.eq(show(L.lex(s)), show(R.lex(s)))
#|True{}
