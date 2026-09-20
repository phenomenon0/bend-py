# Shared Python syntax and JSON wire format. Locations are scalar columns.
import Base

type Pos is Data:
  Pos{line: Nat, col: Nat}

type ErrorKind is Data:
  Syntax{}
  Unsupported{}
  Limit{}

type Error is Data:
  PErr{kind: ErrorKind, pos: Pos, msg: String}

type Ctx is Data:
  Load{}
  Store{}
  Del{}

type Tok is Data:
  Tok{kind: String, text: String, start: Pos, end: Pos}

# One recursive JSON ADT avoids mutually recursive field/list definitions.
# JEnd terminates the internal field/item chains, never an emitted value.
type Json is Data:
  JNull{}
  JStr{text: String}
  JNum{value: Nat}
  JNeg{value: Nat}
  JBool{value: Bool}
  JObj{fields: Json}
  JArr{items: Json}
  JField{key: String, value: Json, rest: Json}
  JItem{value: Json, rest: Json}
  JEnd{}

type Span is Data:
  Span{start: Pos, end: Pos}

type Expr is Data:
  Expr{tag: String, fields: Json, start: Pos, end: Pos, cover: Span, grouped: Bool}

type Stmt is Data:
  Stmt{node: Expr}

type Module is Data:
  Module{body: Json}

def choose(-A: Type, b: Bool, yes: Unit -> A, no: Unit -> A) -> A:
  match b:
    case True{}:
      yes(Unit{})
    case False{}:
      no(Unit{})

def error(kind: ErrorKind, pos: Pos, msg: String) -> Error:
  PErr{kind, pos, msg}

def kind(k: ErrorKind) -> String:
  match k:
    case Syntax{}:
      "Syntax"
    case Unsupported{}:
      "Unsupported"
    case Limit{}:
      "Limit"

def error_text(e: Error) -> String:
  PErr{k, Pos{ln, col}, msg} = e
  "error " ++ kind(k) ++ " " ++ Nat.show(ln) ++ " " ++ Nat.show(col) ++ " " ++ msg

def hex(n: U32) -> String:
  String.take(String.drop("0123456789abcdef", U32.to_nat(n)), 1n)

def escape_char(+c: Char) -> String:
  +n = Char.to_u32(c)
  choose(String, U32.is_lt(n, 32), u =>
    "\\u00" ++ hex((n / 16 : U32)) ++ hex((n % 16 : U32)), u =>
    choose(String, U32.is_eq(n, 34) || U32.is_eq(n, 92), u =>
      "\\" ++ SCon{c, ""}, u => SCon{c, ""}))

# Append into a uniquely owned buffer. Constructing child strings first makes
# a long left-associated AST quadratic in the C runtime's flat strings.
def escape_into(s: String, acc: String) -> String:
  match s:
    case SNil{}:
      acc
    case SCon{h, t}:
      escape_into(t, acc ++ escape_char(h))

def quote(s: String) -> String:
  escape_into(s, "\"") ++ "\""

def comma(j: Json) -> String:
  match j:
    case JEnd{}:
      ""
    case _:
      ","

# The encoder continuation is always called in tail position. This is solely
# an output traversal, not a parser continuation/frame machine.
def json_k(j: Json, acc: String, k: String -> String) -> String:
  match j:
    case JNull{}:
      k(acc ++ "null")
    case JStr{s}:
      k(escape_into(s, acc ++ "\"") ++ "\"")
    case JNum{n}:
      k(acc ++ Nat.show(n))
    case JNeg{n}:
      k(acc ++ "-" ++ Nat.show(n))
    case JBool{b}:
      k(acc ++ Bool.pick(String, b, "true", "false"))
    case JObj{fs}:
      json_k(fs, acc ++ "{", out => k(out ++ "}"))
    case JArr{xs}:
      json_k(xs, acc ++ "[", out => k(out ++ "]"))
    case JField{name, v, +rest}:
      json_k(v, acc ++ quote(name) ++ ":", out => json_k(rest, out ++ comma(rest), k))
    case JItem{v, +rest}:
      json_k(v, acc, out => json_k(rest, out ++ comma(rest), k))
    case JEnd{}:
      k(acc)

def json(j: Json) -> String:
  json_k(j, "", out => out)

def fields_append(a: Json, b: Json) -> Json:
  match a:
    case JField{k, v, rest}:
      JField{k, v, fields_append(rest, b)}
    case JItem{v, rest}:
      JItem{v, fields_append(rest, b)}
    case _:
      b

def pos(p: Pos) -> Json:
  Pos{ln, col} = p
  JItem{JNum{ln}, JItem{JNum{col}, JEnd{}}}

def expr(e: Expr) -> Json:
  Expr{tag, fs, lo, hi, cover, grouped} = e
  JObj{JField{"tag", JStr{tag}, fields_append(fs,
    JField{"_loc", JArr{fields_append(pos(lo), pos(hi))}, JEnd{}})}}

def stmt(s: Stmt) -> Json:
  Stmt{e} = s
  expr(e)

def module(m: Module) -> Json:
  Module{body} = m
  JObj{JField{"tag", JStr{"Module"}, JField{"body", JArr{body},
    JField{"type_ignores", JArr{JEnd{}}, JEnd{}}}}}

def tok(t: Tok) -> Json:
  Tok{k, text, lo, hi} = t
  JObj{JField{"kind", JStr{k}, JField{"text", JStr{text},
    JField{"start", JArr{pos(lo)}, JField{"end", JArr{pos(hi)}, JEnd{}}}}}}

def toks(ts: List<&2, Tok>) -> Json:
  match ts:
    case Nil{}:
      JEnd{}
    case Con{h, t}:
      JItem{tok(h), toks(t)}

def context(c: Ctx) -> Json:
  match c:
    case Load{}:
      JObj{JField{"tag", JStr{"Load"}, JEnd{}}}
    case Store{}:
      JObj{JField{"tag", JStr{"Store"}, JEnd{}}}
    case Del{}:
      JObj{JField{"tag", JStr{"Del"}, JEnd{}}}

# Base.List.length is non-tail-recursive on emitted JS. Corpus token lists
# use this structurally decreasing accumulator instead.
def token_count(ts: List<&2, Tok>, count: Nat) -> Nat:
  match ts:
    case Nil{}:
      count
    case Con{h, tail}:
      token_count(tail, 1n+count)

# The fuel weight of a token list: one per token plus a STRING's characters. An f-string is one
# token whose body dispatches once per text run or field, each consuming a character of it.
def fuel_weight(ts: List<&2, Tok>, count: Nat) -> Nat:
  match ts:
    case Nil{}:
      count
    case Con{h, tail}:
      Tok{k, text, lo, hi} = h
      fuel_weight(tail, (1n + count
        + Bool.pick(Nat, String.eq(k, "STRING"), String.length(text), 0n) : Nat))
