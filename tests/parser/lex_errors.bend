import Base
import ../../demos/python/lexer.bend as L
import ../../demos/python/syntax.bend as S

def bad(s: String) -> Bool:
  Result.is_fail(&2, &2, S.Error, List<&2, S.Tok>, L.lex(s))

def main() -> Bool:
  bad("if x:\n    pass\n  pass\n") &&
    bad("x = '''unclosed") &&
    bad("if x:\n\tpass\n        pass\n") &&
    bad("x = \\ \n") &&
    bad("\0") && bad("\"\0\"") && bad("#\0")

#|True{}
