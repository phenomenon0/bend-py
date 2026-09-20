import Base
import ./syntax.bend as S
import ./parse_state.bend as P

def precedence(+raw: String) -> Nat:
  Bool.pick(Nat, String.eq(raw, "if"), 1n,
    Bool.pick(Nat, String.eq(raw, "or"), 2n,
    Bool.pick(Nat, String.eq(raw, "and"), 3n,
    Bool.pick(Nat, String.eq(raw, "<") || String.eq(raw, ">") || String.eq(raw, "<=") || String.eq(raw, ">=") || String.eq(raw, "==") || String.eq(raw, "!=") || String.eq(raw, "in") || String.eq(raw, "is") || String.eq(raw, "not"), 5n,
    Bool.pick(Nat, String.eq(raw, "|"), 6n,
    Bool.pick(Nat, String.eq(raw, "^"), 7n,
    Bool.pick(Nat, String.eq(raw, "&"), 8n,
    Bool.pick(Nat, String.eq(raw, "<<") || String.eq(raw, ">>"), 9n,
    Bool.pick(Nat, String.eq(raw, "+") || String.eq(raw, "-"), 10n,
    Bool.pick(Nat, String.eq(raw, "*") || String.eq(raw, "@") || String.eq(raw, "/") || String.eq(raw, "//") || String.eq(raw, "%"), 11n,
    Bool.pick(Nat, String.eq(raw, "**"), 13n,
    0n)))))))))))

def tag(+raw: String) -> String:
  Bool.pick(String, String.eq(raw, "+"), "Add",
    Bool.pick(String, String.eq(raw, "-"), "Sub",
    Bool.pick(String, String.eq(raw, "*"), "Mult",
    Bool.pick(String, String.eq(raw, "@"), "MatMult",
    Bool.pick(String, String.eq(raw, "/"), "Div",
    Bool.pick(String, String.eq(raw, "//"), "FloorDiv",
    Bool.pick(String, String.eq(raw, "%"), "Mod",
    Bool.pick(String, String.eq(raw, "**"), "Pow",
    Bool.pick(String, String.eq(raw, "<<"), "LShift",
    Bool.pick(String, String.eq(raw, ">>"), "RShift",
    Bool.pick(String, String.eq(raw, "|"), "BitOr",
    Bool.pick(String, String.eq(raw, "^"), "BitXor",
    Bool.pick(String, String.eq(raw, "&"), "BitAnd",
    Bool.pick(String, String.eq(raw, "<"), "Lt",
    Bool.pick(String, String.eq(raw, ">"), "Gt",
    Bool.pick(String, String.eq(raw, "<="), "LtE",
    Bool.pick(String, String.eq(raw, ">="), "GtE",
    Bool.pick(String, String.eq(raw, "=="), "Eq",
    Bool.pick(String, String.eq(raw, "!="), "NotEq",
    Bool.pick(String, String.eq(raw, "in"), "In",
    Bool.pick(String, String.eq(raw, "is"), "Is",
    Bool.pick(String, String.eq(raw, "not"), "NotIn",
    Bool.pick(String, String.eq(raw, "or"), "Or",
    Bool.pick(String, String.eq(raw, "and"), "And",
    ""))))))))))))))))))))))))

def unary(+raw: String) -> String:
  Bool.pick(String, String.eq(raw, "+"), "UAdd", Bool.pick(String, String.eq(raw, "-"), "USub",
    Bool.pick(String, String.eq(raw, "~"), "Invert", "Not")))

def compare_tail(+first: S.Tok, +next: S.Tok) -> P.M(String):
  S.choose(P.M(String), P.is_text(first, "is") && P.is_text(next, "not"), u =>
    do P.M<String>:
      drop : S.Tok <- P.take
      return "IsNot", u =>
    S.choose(P.M(String), P.is_text(first, "not"), u =>
      do P.M<String>:
        drop : S.Tok <- P.expect("in")
        return "NotIn", u => P.M.pure(String, tag(P.tok_text(first)))))

def comparison() -> P.M(String):
  do P.M<String>:
    first : S.Tok <- P.take
    next : S.Tok <- P.peek
    compare_tail(first, next)

def is_end(+t: S.Tok) -> Bool:
  P.is_kind(t, "NEWLINE") || P.is_kind(t, "ENDMARKER") || P.is_kind(t, "DEDENT") ||
    String.contains("|)|]|}|;|:|in|=|+=|-=|*=|/=|//=|%=|**=|@=|&=||=|^=|<<=|>>=|", "|" ++ P.tok_text(t) ++ "|")

def augmented(+raw: String) -> Bool:
  String.contains("|+=|-=|*=|/=|//=|%=|**=|@=|&=||=|^=|<<=|>>=|", "|" ++ raw ++ "|") && Nat.is_ge(String.length(raw), 2n)
