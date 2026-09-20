# f-string body scanners after CPython 3.11's fstring_find_literal / fstring_find_expr.
# Pure and one character per call; the parser drives them and parses the fields.
import Base
import ./syntax.bend as S
import ./scanner.bend as C

# raw, the first token's kind, the whole run's span (Constant, FormattedValue)
# and this token's span (a format spec's JoinedStr).
type Ctx is Data:
  Ctx{raw: Bool, kind: S.Json, lo: S.Pos, hi: S.Pos, tlo: S.Pos, thi: S.Pos}

type Cut is Data:
  Cut{text: String, rest: String, pos: S.Pos}

type Open is Data:
  Open{raw: Bool, body: String, offset: Nat}

type Tail is Data:
  Tail{debug: String, conversion: Nat, spec: Bool, rest: String, pos: S.Pos}

def fail(-A: Data, pos: S.Pos, msg: String) -> Result<&2, &2, S.Error, A>:
  Fail{S.PErr{S.Syntax{}, pos, msg}}

def text_of(c: Cut) -> String:
  Cut{t, rest, pos} = c
  t

def rest_of(c: Cut) -> String:
  Cut{t, r, pos} = c
  r

def pos_of(c: Cut) -> S.Pos:
  Cut{t, rest, p} = c
  p

def prefix_len(s: String, +n: Nat) -> Nat:
  match s:
    case SNil{}:
      n
    case SCon{+h, t}:
      S.choose(Nat, C.is_quote(h), u => n, u => prefix_len(t, (1n+n : Nat)))

def open(+raw: String) -> Open:
  +n = prefix_len(raw, 0n)
  +s = String.drop(raw, n)
  +q = {SCon{C.head(s), ""} : String}
  +d = Bool.pick(Nat, String.starts_with(s, q ++ q ++ q), 3n, 1n)
  Open{String.contains(String.to_lower(String.take(raw, n)), "r"), String.drop_end(String.drop(s, d), d), (n + d : Nat)}

def is_raw(o: Open) -> Bool:
  Open{r, b, n} = o
  r

def body(o: Open) -> String:
  Open{r, b, n} = o
  b

def offset(o: Open) -> Nat:
  Open{r, b, n} = o
  n

def shift(p: S.Pos, n: Nat) -> S.Pos:
  S.Pos{ln, col} = p
  S.Pos{ln, (col + n : Nat)}

# A literal whose value is the empty string: nothing, or only backslash-newlines.
def vanishes(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{Chr{92}, SCon{'\n', t}}:
      vanishes(t)
    case SCon{Chr{92}, SCon{'\r', SCon{'\n', t}}}:
      vanishes(t)
    case _:
      False{}

def brace(+c: Char) -> Bool:
  Char.is_eq(c, '{') || Char.is_eq(c, '}')

# Literal text up to a field's `{`, the spec's closing `}` (level > 0) or the end.
# `{{` and `}}` fold at level 0 only. mode: 0 scan, 1 keep one (an escape pair),
# 2 drop one (the second brace), 3 keep through `}` (a \N{name}).
def literal(s: String, +raw: Bool, +level: Nat, +mode: Nat, +at: S.Pos, acc: String) -> Result<&2, &2, S.Error, Cut>:
  match s:
    case SNil{}:
      Done{Cut{String.reverse(acc), "", at}}
    case SCon{+h, +t}:
      +a = acc
      +n = C.head(t)
      +next = C.advance(at, h)
      S.choose(Result<&2, &2, S.Error, Cut>, Nat.is_eq(mode, 2n), u => literal(t, raw, level, 0n, next, a), u =>
        S.choose(Result<&2, &2, S.Error, Cut>, Nat.is_eq(mode, 1n) || (Nat.is_eq(mode, 3n) && Bool.not(Char.is_eq(h, '}'))), u =>
          literal(t, raw, level, Bool.pick(Nat, Nat.is_eq(mode, 1n), 0n, 3n), next, SCon{h, a}), u =>
          S.choose(Result<&2, &2, S.Error, Cut>, Nat.is_eq(mode, 3n), u => literal(t, raw, level, 0n, next, SCon{h, a}), u =>
            S.choose(Result<&2, &2, S.Error, Cut>, Char.is_eq(h, Chr{92}) && Bool.not(raw) && Bool.not(String.is_empty(t)), u =>
              literal(t, raw, level, Bool.pick(Nat, brace(n), 0n, Bool.pick(Nat, String.starts_with(t, "N{"), 3n, 1n)), next, SCon{h, a}), u =>
              S.choose(Result<&2, &2, S.Error, Cut>, Bool.not(brace(h)), u => literal(t, raw, level, 0n, next, SCon{h, a}), u =>
                S.choose(Result<&2, &2, S.Error, Cut>, Nat.is_eq(level, 0n) && Char.is_eq(n, h), u => literal(t, raw, level, 2n, next, SCon{h, a}), u =>
                  S.choose(Result<&2, &2, S.Error, Cut>, Nat.is_eq(level, 0n) && Char.is_eq(h, '}'), u =>
                    fail(Cut, at, "f-string: single '}' is not allowed"), u =>
                    Done{Cut{String.reverse(a), SCon{h, t}, at}})))))))

def closer(+c: Char) -> Char:
  Bool.pick(Char, Char.is_eq(c, '('), ')', Bool.pick(Char, Char.is_eq(c, '['), ']', '}'))

# The expression after `{`, up to a top-level `=` `!` `:` `}` (left in rest).
# quote: the open string delimiter; stack: the expected closers; skip: characters already decided.
def extent(s: String, +quote: String, +stack: String, +skip: Nat, +at: S.Pos, acc: String) -> Result<&2, &2, S.Error, Cut>:
  match s:
    case SNil{}:
      fail(Cut, at, Bool.pick(String, String.is_empty(quote), "f-string: expecting '}'", "f-string: unterminated string"))
    case SCon{+h, +t}:
      +a = {SCon{h, acc} : String}
      +here = {SCon{h, t} : String}
      +n = C.head(t)
      +next = C.advance(at, h)
      +q = {SCon{h, ""} : String}
      S.choose(Result<&2, &2, S.Error, Cut>, Char.is_eq(h, Chr{92}), u => fail(Cut, at, "f-string expression part cannot include a backslash"), u =>
        S.choose(Result<&2, &2, S.Error, Cut>, Bool.not(Nat.is_eq(skip, 0n)), u => extent(t, quote, stack, (skip - 1n : Nat), next, a), u =>
          S.choose(Result<&2, &2, S.Error, Cut>, Bool.not(String.is_empty(quote)), u =>
            S.choose(Result<&2, &2, S.Error, Cut>, String.starts_with(here, quote), u =>
              extent(t, "", stack, (String.length(quote) - 1n : Nat), next, a), u => extent(t, quote, stack, 0n, next, a)), u =>
            S.choose(Result<&2, &2, S.Error, Cut>, C.is_quote(h), u =>
              S.choose(Result<&2, &2, S.Error, Cut>, String.starts_with(here, q ++ q ++ q), u =>
                extent(t, q ++ q ++ q, stack, 2n, next, a), u => extent(t, q, stack, 0n, next, a)), u =>
              S.choose(Result<&2, &2, S.Error, Cut>, String.contains("([{", q), u => extent(t, quote, SCon{closer(h), stack}, 0n, next, a), u =>
                S.choose(Result<&2, &2, S.Error, Cut>, Char.is_eq(h, '#'), u => fail(Cut, at, "f-string expression part cannot include '#'"), u =>
                  S.choose(Result<&2, &2, S.Error, Cut>, String.is_empty(stack) && String.contains("!:}=<>", q), u =>
                    S.choose(Result<&2, &2, S.Error, Cut>, String.contains("!=<>", q) && Char.is_eq(n, '='), u => extent(t, quote, stack, 1n, next, a), u =>
                      S.choose(Result<&2, &2, S.Error, Cut>, String.contains("<>", q), u => extent(t, quote, stack, 0n, next, a), u =>
                        Done{Cut{String.reverse(String.drop(a, 1n)), here, at}})), u =>
                    S.choose(Result<&2, &2, S.Error, Cut>, String.contains(")]}", q), u =>
                      S.choose(Result<&2, &2, S.Error, Cut>, Char.is_eq(C.head(stack), h), u => extent(t, quote, String.drop(stack, 1n), 0n, next, a), u =>
                        fail(Cut, at, "f-string: closing parenthesis does not match")), u =>
                      extent(t, quote, stack, 0n, next, a)))))))))

def space(+c: Char) -> Bool:
  C.ws(c) || Char.is_eq(c, '\n') || Char.is_eq(c, '\r') || Char.is_eq(c, Chr{11})

def blank(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{+h, t}:
      space(h) && blank(t)

def field(s: String, at: S.Pos) -> Result<&2, &2, S.Error, Cut>:
  do Result<&2, &2, S.Error, Cut>:
    +c : Cut <- extent(s, "", "", 0n, at, "")
    S.choose(Result<&2, &2, S.Error, Cut>, blank(text_of(c)), u => fail(Cut, pos_of(c), "f-string: empty expression not allowed"), u => Done{c})

def spaces(s: String, +at: S.Pos, acc: String) -> Cut:
  match s:
    case SNil{}:
      Cut{String.reverse(acc), "", at}
    case SCon{+h, +t}:
      +a = acc
      S.choose(Cut, space(h), u => spaces(t, C.advance(at, h), SCon{h, a}), u => Cut{String.reverse(a), SCon{h, t}, at})

# After the expression: `=` and its whitespace (the debug text), `!c`, then `:` opening a spec.
def tail(+s: String, +at: S.Pos) -> Result<&2, &2, S.Error, Tail>:
  +dbg = S.choose(Cut, Char.is_eq(C.head(s), '='), u => spaces(String.drop(s, 1n), C.advance(at, '='), "="), u => Cut{"", s, at})
  +r = rest_of(dbg)
  +p = pos_of(dbg)
  +bang = Char.is_eq(C.head(r), '!')
  +c = C.head(String.drop(r, 1n))
  +r2 = Bool.pick(String, bang, String.drop(r, 2n), r)
  +p2 = Bool.pick(S.Pos, bang, shift(p, 2n), p)
  +colon = Char.is_eq(C.head(r2), ':')
  S.choose(Result<&2, &2, S.Error, Tail>, bang && Bool.not(Char.is_eq(c, 's') || Char.is_eq(c, 'r') || Char.is_eq(c, 'a')), u =>
    fail(Tail, p, "f-string: invalid conversion character: expected 's', 'r', or 'a'"), u =>
    Done{Tail{text_of(dbg), Bool.pick(Nat, bang, U32.to_nat(Char.to_u32(c)), 0n), colon,
      Bool.pick(String, colon, String.drop(r2, 1n), r2), Bool.pick(S.Pos, colon, shift(p2, 1n), p2)}})

def debug(t: Tail) -> String:
  Tail{d, c, spec, r, p} = t
  d

def conversion(t: Tail) -> Nat:
  Tail{d, c, spec, r, p} = t
  c

def has_spec(t: Tail) -> Bool:
  Tail{d, c, spec, r, p} = t
  spec

def tail_cut(t: Tail) -> Cut:
  Tail{d, c, spec, r, p} = t
  Cut{"", r, p}
