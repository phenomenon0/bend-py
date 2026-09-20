# Consuming string and number scanners. No source-prefix indexing loops.
import Base
import ./syntax.bend as S
import ./unicode.bend as U

type Scan is Data:
  Scan{raw: String, rest: String, end: S.Pos}

def head(s: String) -> Char:
  match s:
    case SNil{}:
      Chr{0}
    case SCon{h, t}:
      h

def advance(+p: S.Pos, c: Char) -> S.Pos:
  S.Pos{ln, col} = p
  S.choose(S.Pos, Char.is_eq(c, '\n'), u => S.Pos{1n+ln, 0n}, u => S.Pos{ln, 1n+col})

def ascii_word(+c: Char) -> Bool:
  Char.is_alpha(c) || Char.is_digit(c) || Char.is_eq(c, '_')

def word(+c: Char) -> Bool:
  S.choose(Bool, U32.is_lt(Char.to_u32(c), 128), u => ascii_word(c), u => U.word(Char.to_u32(c)))

def ws(+c: Char) -> Bool:
  Char.is_eq(c, ' ') || Char.is_eq(c, '\t') || Char.is_eq(c, Chr{12})

def accepts(mode: Nat, +c: Char) -> Bool:
  match mode:
    case 0n:
      word(c)
    case 1n:
      ws(c)
    case _:
      Bool.not(Char.is_eq(c, '\n') || Char.is_eq(c, '\r') || Char.is_eq(c, Chr{0}))

def span(s: String, +mode: Nat, +pos: S.Pos, acc: String) -> Scan:
  match s:
    case SNil{}:
      Scan{String.reverse(acc), "", pos}
    case SCon{+h, +t}:
      +a = acc
      S.choose(Scan, accepts(mode, h), u =>
        span(t, mode, advance(pos, h), SCon{h, a}), u =>
        Scan{String.reverse(a), SCon{h, t}, pos})

def take(s: String, n: Nat, pos: S.Pos, acc: String) -> Scan:
  match s n:
    case _ 0n:
      Scan{String.reverse(acc), s, pos}
    case SNil{} _:
      Scan{String.reverse(acc), "", pos}
    case SCon{+h, t} 1n+p:
      take(t, p, advance(pos, h), SCon{h, acc})

def is_prefix(+s: String) -> Bool:
  +lower = String.to_lower(s)
  String.eq(lower, "r") || String.eq(lower, "u") || String.eq(lower, "b") ||
    String.eq(lower, "f") || String.eq(lower, "br") || String.eq(lower, "rb") ||
    String.eq(lower, "fr") || String.eq(lower, "rf")

def is_quote(+c: Char) -> Bool:
  Char.is_eq(c, Chr{39}) || Char.is_eq(c, Chr{34})

def quoted(s: String, +delim: String, +triple: Bool, +escaped: Bool,
  +pos: S.Pos, acc: String) -> Result<&2, &2, S.Error, Scan>:
  match s:
    case SNil{}:
      Fail{S.PErr{S.Syntax{}, pos, "unterminated string"}}
    case SCon{+h, +t}:
      +a = acc
      S.choose(Result<&2, &2, S.Error, Scan>, Bool.not(escaped) && String.starts_with(SCon{h, t}, delim), u =>
        Done{take(SCon{h, t}, String.length(delim), pos, a)}, u =>
        S.choose(Result<&2, &2, S.Error, Scan>, Char.is_eq(h, Chr{0}) || (Bool.not(triple) && Bool.not(escaped) && Char.is_eq(h, '\n')), u =>
          Fail{S.PErr{S.Syntax{}, pos, "invalid character in string"}}, u =>
          quoted(t, delim, triple, (Bool.not(escaped) && Char.is_eq(h, Chr{92})) || (escaped && Char.is_eq(h, '\r') && Char.is_eq(head(t), '\n')),
            advance(pos, h), SCon{h, a})))

def pos_line(p: S.Pos) -> Nat:
  S.Pos{ln, col} = p
  ln

def pos_col(p: S.Pos) -> Nat:
  S.Pos{ln, col} = p
  col

def quoted_start(+s: String, +pos: S.Pos, prefix: String) -> Result<&2, &2, S.Error, Scan>:
  +q = {SCon{head(s), ""} : String}
  +triple = String.starts_with(s, q ++ q ++ q)
  +delim = Bool.pick(String, triple, q ++ q ++ q, q)
  +n = String.length(delim)
  quoted(String.drop(s, n), delim, triple, False{},
    S.Pos{pos_line(pos), Nat.add(pos_col(pos), n)}, String.reverse(prefix ++ delim))


def digit(+c: Char) -> Bool:
  Char.is_digit(c)

def digit_base(+c: Char, +base: Nat) -> Bool:
  +n = Char.to_u32(c)
  (U32.is_ge(n, 48) && U32.is_lt(n, (48 + U32.from_nat(Nat.min(base, 10n)) : U32))) ||
    (Nat.is_eq(base, 16n) && ((U32.is_ge(n, 65) && U32.is_le(n, 70)) || (U32.is_ge(n, 97) && U32.is_le(n, 102))))

# Number DFA: zero/decimal/leading-zero, radix runs, fraction, exponent,
# imaginary suffix, and underscore-pending states. Last acceptance enables
# tokenize-compatible rollback of incomplete exponent/radix suffixes.
def number_next(state: Nat, +c: Char) -> Nat:
  match state:
    case 0n:
      Bool.pick(Nat, Char.is_eq(c, '0'), 1n, Bool.pick(Nat, digit(c), 2n, Bool.pick(Nat, Char.is_eq(c, '.'), 10n, 0n)))
    case 1n:
      Bool.pick(Nat, Char.is_eq(c, '0'), 24n, Bool.pick(Nat, digit(c), 3n, Bool.pick(Nat, Char.is_eq(c, '_'), 16n, Bool.pick(Nat, Char.is_eq(c, '.'), 10n, Bool.pick(Nat, Char.is_eq(c, 'e') || Char.is_eq(c, 'E'), 12n, Bool.pick(Nat, Char.is_eq(c, 'j') || Char.is_eq(c, 'J'), 15n, Bool.pick(Nat, Char.is_eq(c, 'x') || Char.is_eq(c, 'X'), 4n, Bool.pick(Nat, Char.is_eq(c, 'o') || Char.is_eq(c, 'O'), 6n, Bool.pick(Nat, Char.is_eq(c, 'b') || Char.is_eq(c, 'B'), 8n, 0n)))))))))
    case 2n:
      Bool.pick(Nat, digit(c), 2n, Bool.pick(Nat, Char.is_eq(c, '_'), 17n, Bool.pick(Nat, Char.is_eq(c, '.'), 10n, Bool.pick(Nat, Char.is_eq(c, 'e') || Char.is_eq(c, 'E'), 12n, Bool.pick(Nat, Char.is_eq(c, 'j') || Char.is_eq(c, 'J'), 15n, 0n)))))
    case 3n:
      Bool.pick(Nat, digit(c), 3n, Bool.pick(Nat, Char.is_eq(c, '_'), 18n, Bool.pick(Nat, Char.is_eq(c, '.'), 10n, Bool.pick(Nat, Char.is_eq(c, 'e') || Char.is_eq(c, 'E'), 12n, Bool.pick(Nat, Char.is_eq(c, 'j') || Char.is_eq(c, 'J'), 15n, 0n)))))
    case 4n:
      Bool.pick(Nat, digit_base(c, 16n), 5n, Bool.pick(Nat, Char.is_eq(c, '_'), 19n, 0n))
    case 5n:
      Bool.pick(Nat, digit_base(c, 16n), 5n, Bool.pick(Nat, Char.is_eq(c, '_'), 19n, 0n))
    case 6n:
      Bool.pick(Nat, digit_base(c, 8n), 7n, Bool.pick(Nat, Char.is_eq(c, '_'), 20n, 0n))
    case 7n:
      Bool.pick(Nat, digit_base(c, 8n), 7n, Bool.pick(Nat, Char.is_eq(c, '_'), 20n, 0n))
    case 8n:
      Bool.pick(Nat, digit_base(c, 2n), 9n, Bool.pick(Nat, Char.is_eq(c, '_'), 21n, 0n))
    case 9n:
      Bool.pick(Nat, digit_base(c, 2n), 9n, Bool.pick(Nat, Char.is_eq(c, '_'), 21n, 0n))
    case 10n:
      Bool.pick(Nat, digit(c), 11n, Bool.pick(Nat, Char.is_eq(c, 'e') || Char.is_eq(c, 'E'), 12n, Bool.pick(Nat, Char.is_eq(c, 'j') || Char.is_eq(c, 'J'), 15n, 0n)))
    case 11n:
      Bool.pick(Nat, digit(c), 11n, Bool.pick(Nat, Char.is_eq(c, '_'), 22n, Bool.pick(Nat, Char.is_eq(c, 'e') || Char.is_eq(c, 'E'), 12n, Bool.pick(Nat, Char.is_eq(c, 'j') || Char.is_eq(c, 'J'), 15n, 0n))))
    case 12n:
      Bool.pick(Nat, digit(c), 14n, Bool.pick(Nat, Char.is_eq(c, '+') || Char.is_eq(c, '-'), 13n, 0n))
    case 13n:
      Bool.pick(Nat, digit(c), 14n, 0n)
    case 14n:
      Bool.pick(Nat, digit(c), 14n, Bool.pick(Nat, Char.is_eq(c, '_'), 23n, Bool.pick(Nat, Char.is_eq(c, 'j') || Char.is_eq(c, 'J'), 15n, 0n)))
    case 15n:
      0n
    case 16n:
      Bool.pick(Nat, Char.is_eq(c, '0'), 24n, Bool.pick(Nat, digit(c), 3n, 0n))
    case 17n:
      Bool.pick(Nat, digit(c), 2n, 0n)
    case 18n:
      Bool.pick(Nat, digit(c), 3n, 0n)
    case 19n:
      Bool.pick(Nat, digit_base(c, 16n), 5n, 0n)
    case 20n:
      Bool.pick(Nat, digit_base(c, 8n), 7n, 0n)
    case 21n:
      Bool.pick(Nat, digit_base(c, 2n), 9n, 0n)
    case 22n:
      Bool.pick(Nat, digit(c), 11n, 0n)
    case 23n:
      Bool.pick(Nat, digit(c), 14n, 0n)
    case 24n:
      Bool.pick(Nat, Char.is_eq(c, '0'), 24n, Bool.pick(Nat, digit(c), 3n,
        Bool.pick(Nat, Char.is_eq(c, '_'), 16n, Bool.pick(Nat, Char.is_eq(c, '.'), 10n,
          Bool.pick(Nat, Char.is_eq(c, 'e') || Char.is_eq(c, 'E'), 12n,
            Bool.pick(Nat, Char.is_eq(c, 'j') || Char.is_eq(c, 'J'), 15n, 0n))))))
    case _:
      0n

def number_accept(+state: Nat) -> Bool:
  Nat.is_eq(state, 24n) || Nat.is_eq(state, 1n) || Nat.is_eq(state, 2n) || Nat.is_eq(state, 5n) || Nat.is_eq(state, 7n) || Nat.is_eq(state, 9n) || Nat.is_eq(state, 10n) || Nat.is_eq(state, 11n) || Nat.is_eq(state, 14n) || Nat.is_eq(state, 15n)

def number(s: String, +state: Nat, +pos: S.Pos, acc: String, +best: Scan) -> Scan:
  match s:
    case SNil{}:
      best
    case SCon{+h, +t}:
      +next = number_next(state, h)
      +a = {SCon{h, acc} : String}
      +end = advance(pos, h)
      S.choose(Scan, Nat.is_eq(next, 0n), u => best, u =>
        number(t, next, end, a, S.choose(Scan, number_accept(next), u =>
          Scan{String.reverse(a), t, end}, u => best)))
