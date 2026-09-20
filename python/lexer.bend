# Python 3.11 hand lexer. Trivia is discarded; token spelling is retained.
import Base
import ./syntax.bend as S
import ./scanner.bend as C

type Indent is Data:
  Indent{width: Nat, alternate: Nat}

type State is Data:
  State{rest: String, pos: S.Pos, levels: List<&2, Indent>, brackets: List<&2, Char>,
    bol: Bool, logical: Bool, tokens: List<&2, S.Tok>, finished: Bool}

def keyword(+s: String) -> Bool:
  String.contains("|False|None|True|and|as|assert|async|await|break|class|continue|def|del|elif|else|except|finally|for|from|global|if|import|in|is|lambda|nonlocal|not|or|pass|raise|return|try|while|with|yield|", "|" ++ s ++ "|")

def fail(pos: S.Pos, msg: String) -> Result<&2, &2, S.Error, State>:
  Fail{S.PErr{S.Syntax{}, pos, msg}}

def emit(st: State, kind: String, scan: C.Scan) -> State:
  State{rest, lo, levels, brackets, bol, logical, out, done} = st
  C.Scan{raw, tail, +hi} = scan
  State{tail, hi, levels, brackets, False{}, True{}, S.Tok{kind, raw, lo, hi} <> out, False{}}

def move(st: State, scan: C.Scan, bol: Bool) -> State:
  State{rest, lo, levels, brackets, oldbol, logical, out, done} = st
  C.Scan{raw, tail, hi} = scan
  State{tail, hi, levels, brackets, bol, logical, out, False{}}

def widths(s: String, width: Nat, alt: Nat) -> Indent:
  match s:
    case SNil{}:
      Indent{width, alt}
    case SCon{'\t', tail}:
      widths(tail, (((width / 8n) + 1n) * 8n : Nat), (1n+alt : Nat))
    case SCon{Chr{12}, tail}:
      widths(tail, 0n, 0n)
    case SCon{h, tail}:
      widths(tail, (1n+width : Nat), (1n+alt : Nat))

def layout_go(levels: List<&2, Indent>, +width: Nat, +alt: Nat, +popped: Bool,
  +tail: String, +lo: S.Pos, +hi: S.Pos, +raw: String, +out: List<&2, S.Tok>) -> Result<&2, &2, S.Error, State>:
  match levels:
    case Nil{}:
      fail(hi, "inconsistent dedent")
    case Con{Indent{+w, +a}, +ls}:
      S.choose(Result<&2, &2, S.Error, State>, Nat.is_lt(width, w), u =>
        layout_go(ls, width, alt, True{}, tail, lo, hi, raw, S.Tok{"DEDENT", "", hi, hi} <> out), u =>
        S.choose(Result<&2, &2, S.Error, State>, Nat.is_eq(width, w), u =>
          S.choose(Result<&2, &2, S.Error, State>, Nat.is_eq(alt, a), u =>
            Done{State{tail, hi, Indent{w, a} <> ls, [], False{}, False{}, out, False{}}}, u =>
            fail(hi, "inconsistent tabs and spaces")), u =>
          S.choose(Result<&2, &2, S.Error, State>, popped || Nat.is_le(alt, a), u =>
            fail(hi, "inconsistent indentation"), u =>
            Done{State{tail, hi, Indent{width, alt} <> Indent{w, a} <> ls, [], False{}, False{},
              S.Tok{"INDENT", raw, lo, hi} <> out, False{}}})))

def layout_width(st: State, scan: C.Scan, ind: Indent) -> Result<&2, &2, S.Error, State>:
  State{rest, +lo, levels, brackets, bol, logical, out, done} = st
  C.Scan{raw, tail, hi} = scan
  Indent{w, a} = ind
  layout_go(levels, w, a, False{}, tail, lo, hi, raw, out)

def layout(+st: State, +scan: C.Scan) -> Result<&2, &2, S.Error, State>:
  C.Scan{raw, +tail, hi} = scan
  +h = C.head(tail)
  S.choose(Result<&2, &2, S.Error, State>, String.is_empty(tail) || Char.is_eq(h, '#') || Char.is_eq(h, '\n') || Char.is_eq(h, '\r'), u =>
    Done{move(st, scan, False{})}, u => layout_width(st, scan, widths(raw, 0n, 0n)))

def nl(st: State, scan: C.Scan) -> State:
  State{rest, +lo, levels, +brackets, bol, +logical, +out, done} = st
  C.Scan{+raw, tail, +hi} = scan
  +real = logical && List.is_empty(&2, Char, brackets)
  State{tail, hi, levels, brackets, True{}, Bool.pick(Bool, real, False{}, logical),
    Bool.pick(List<&2, S.Tok>, real, S.Tok{"NEWLINE", raw, lo, S.Pos{C.pos_line(lo), Nat.add(C.pos_col(lo), String.length(raw))}} <> out, out), False{}}

def eof_levels(levels: List<&2, Indent>, +pos: S.Pos, out: List<&2, S.Tok>) -> List<&2, S.Tok>:
  match levels:
    case Con{h, Con{a, rest}}:
      eof_levels(Con{a, rest}, pos, S.Tok{"DEDENT", "", pos, pos} <> out)
    case _:
      S.Tok{"ENDMARKER", "", pos, pos} <> out

def eof(st: State) -> Result<&2, &2, S.Error, State>:
  State{rest, +lo, +levels, +brackets, bol, +logical, +out, done} = st
  +line = C.pos_line(lo)
  +col = C.pos_col(lo)
  +ep = {S.Pos{Bool.pick(Nat, Nat.is_gt(col, 0n), (1n+line : Nat), line), 0n} : S.Pos}
  +last = Bool.pick(List<&2, S.Tok>, logical,
    S.Tok{"NEWLINE", "", lo, S.Pos{line, (1n+col : Nat)}} <> out, out)
  S.choose(Result<&2, &2, S.Error, State>, List.is_empty(&2, Char, brackets), u =>
    Done{State{"", ep, [], [], False{}, False{}, eof_levels(levels, ep, last), True{}}}, u =>
    fail(lo, "unclosed bracket"))

def name(+st: State, +scan: C.Scan) -> Result<&2, &2, S.Error, State>:
  C.Scan{+raw, +tail, +hi} = scan
  S.choose(Result<&2, &2, S.Error, State>, C.is_prefix(raw) && C.is_quote(C.head(tail)), u =>
    do Result<&2, &2, S.Error, State>:
      token : C.Scan <- C.quoted_start(tail, hi, raw)
      return emit(st, "STRING", token), u =>
    Done{emit(st, Bool.pick(String, keyword(raw), "KW", "NAME"), scan)})

def op_text(+s: String) -> String:
  +three = String.take(s, 3n)
  +two = String.take(s, 2n)
  S.choose(String, String.eq(three, "...") || String.eq(three, "**=") || String.eq(three, "//=") || String.eq(three, "<<=") || String.eq(three, ">>="), u => three, u =>
    S.choose(String, String.contains("|==|!=|<=|>=|<<|>>|**|//|+=|-=|*=|/=|%=|@=|&=||=|^=|->|:=|", "|" ++ two ++ "|") && Nat.is_eq(String.length(two), 2n), u => two, u => String.take(s, 1n)))

def close(brackets: List<&2, Char>, +st: State, scan: C.Scan, +c: Char) -> Result<&2, &2, S.Error, State>:
  match brackets:
    case Nil{}:
      fail(S.Pos{1n, 0n}, "unmatched closing bracket")
    case Con{h, tail}:
      State{rest, lo, levels, old, bol, logical, out, done} = st
      +next = emit(State{rest, lo, levels, tail, bol, logical, out, done}, "OP", scan)
      S.choose(Result<&2, &2, S.Error, State>, Char.is_eq(h, c), u => Done{next}, u => fail(lo, "mismatched bracket"))

def op(+st: State, +scan: C.Scan) -> Result<&2, &2, S.Error, State>:
  State{rest, +lo, +levels, +brackets, bol, logical, +out, done} = st
  C.Scan{+raw, tail, hi} = scan
  +c = C.head(raw)
  S.choose(Result<&2, &2, S.Error, State>, String.contains("([{", raw), u =>
    S.choose(Result<&2, &2, S.Error, State>, Nat.is_ge(List.length(&2, Char, brackets), 200n), u =>
      Fail{S.PErr{S.Limit{}, lo, "nesting exceeds 200"}}, u =>
      +end = Bool.pick(Char, Char.is_eq(c, '('), ')', Bool.pick(Char, Char.is_eq(c, '['), ']', '}'))
      Done{emit(State{rest, lo, levels, end <> brackets, bol, logical, out, done}, "OP", scan)}), u =>
    S.choose(Result<&2, &2, S.Error, State>, String.contains(")]}", raw), u => close(brackets, st, scan, c), u =>
      S.choose(Result<&2, &2, S.Error, State>, String.contains("+-*/%@&|^~<>=:;,.!", SCon{c, ""}) && Bool.not(String.eq(raw, "!")), u =>
        Done{emit(st, "OP", scan)}, u => fail(lo, "invalid character"))))

def step_with(+st: State, names: String -> S.Pos -> C.Scan, numbers: String -> S.Pos -> C.Scan) -> Result<&2, &2, S.Error, State>:
  State{+rest, +pos, levels, +brackets, +bol, logical, out, done} = st
  +h = C.head(rest)
  S.choose(Result<&2, &2, S.Error, State>, String.is_empty(rest), u => eof(st), u =>
    S.choose(Result<&2, &2, S.Error, State>, bol && List.is_empty(&2, Char, brackets), u =>
      layout(st, C.span(rest, 1n, pos, "")), u =>
      S.choose(Result<&2, &2, S.Error, State>, C.ws(h), u =>
        Done{move(st, C.span(rest, 1n, pos, ""), False{})}, u =>
        S.choose(Result<&2, &2, S.Error, State>, Char.is_eq(h, '#'), u =>
          Done{move(st, C.span(rest, 2n, pos, ""), False{})}, u =>
          S.choose(Result<&2, &2, S.Error, State>, Char.is_eq(h, '\n') || String.starts_with(rest, "\r\n"), u =>
            Done{nl(st, C.take(rest, Bool.pick(Nat, Char.is_eq(h, '\r'), 2n, 1n), pos, ""))}, u =>
            S.choose(Result<&2, &2, S.Error, State>, Char.is_eq(h, Chr{92}), u =>
              S.choose(Result<&2, &2, S.Error, State>, String.starts_with(rest, "\\\n") || String.starts_with(rest, "\\\r\n"), u =>
                Done{move(st, C.take(rest, Bool.pick(Nat, String.starts_with(rest, "\\\r\n"), 3n, 2n), pos, ""), False{})}, u =>
                fail(pos, "invalid line continuation")), u =>
              S.choose(Result<&2, &2, S.Error, State>, C.is_quote(h), u =>
                do Result<&2, &2, S.Error, State>:
                  token : C.Scan <- C.quoted_start(rest, pos, "")
                  return emit(st, "STRING", token), u =>
                S.choose(Result<&2, &2, S.Error, State>, Char.is_digit(h) || (Char.is_eq(h, '.') && Char.is_digit(C.head(String.drop(rest, 1n)))), u =>
                  Done{emit(st, "NUMBER", numbers(rest, pos))}, u =>
                  S.choose(Result<&2, &2, S.Error, State>, C.word(h), u =>
                    name(st, names(rest, pos)), u =>
                    op(st, C.take(rest, String.length(op_text(rest)), pos, "")))))))))))

# The default remains the independent hand scanner. P3 injects recognizers
# only from the measurement harness; layout/string/operator logic is shared.
def hand_number(+s: String, +p: S.Pos) -> C.Scan:
  C.number(s, 0n, p, "", C.Scan{"", s, p})

def step(st: State) -> Result<&2, &2, S.Error, State>:
  step_with(st, s => p => C.span(s, 0n, p, ""), s => p => hand_number(s, p))

def finished(s: State) -> Bool:
  State{rest, pos, levels, brackets, bol, logical, out, done} = s
  done

def tokens(s: State) -> List<&2, S.Tok>:
  State{rest, pos, levels, brackets, bol, logical, out, done} = s
  List.reverse(&2, S.Tok, out)

def go(fuel: Nat, +st: State) -> Result<&2, &2, S.Error, List<&2, S.Tok>>:
  match fuel:
    case 0n:
      Fail{S.PErr{S.Limit{}, S.Pos{1n, 0n}, "lexer fuel"}}
    case 1n+left:
      S.choose(Result<&2, &2, S.Error, List<&2, S.Tok>>, finished(st), u => Done{tokens(st)}, u =>
        do Result<&2, &2, S.Error, List<&2, S.Tok>>:
          next : State <- step(st)
          go(left, next))

def lex(+s: String) -> Result<&2, &2, S.Error, List<&2, S.Tok>>:
  go((3n * (String.length(s) + 1n) : Nat), State{s, S.Pos{1n, 0n}, [Indent{0n, 0n}], [], True{}, False{}, [], False{}})

# An f-string field: `(expr)` lexed mid-line from the `{`, so every token keeps its source position.
def lex_at(+s: String, pos: S.Pos) -> Result<&2, &2, S.Error, List<&2, S.Tok>>:
  go((3n * (String.length(s) + 1n) : Nat), State{s, pos, [Indent{0n, 0n}], [], False{}, True{}, [], False{}})
