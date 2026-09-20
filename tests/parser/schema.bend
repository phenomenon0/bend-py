import Base
import ../../demos/python/syntax.bend as S

def main() -> Bool:
  +p = {S.Pos{1n, 0n} : S.Pos}
  node = {S.Expr{"Name", S.JField{"id", S.JStr{"x"}, S.JField{"ctx", S.context(S.Store{}), S.JEnd{}}}, p, S.Pos{1n, 1n}, S.Span{p, S.Pos{1n, 1n}}, False{}} : S.Expr}
  String.eq(S.json(S.expr(node)), "{\"tag\":\"Name\",\"id\":\"x\",\"ctx\":{\"tag\":\"Store\"},\"_loc\":[1,0,1,1]}")

#|True{}
