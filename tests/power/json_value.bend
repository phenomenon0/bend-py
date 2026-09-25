# JsonValue against CPython (json_value_gen.py prints this file). A corpus
# row is a document and what parse makes of it: `ok` and the canonical text of
# the tree, or `err`; a row tagged with a kind is where RFC 8259 leaves the
# choice to the parser and this one's is pinned. Then the limits (depth, budget,
# duplicate keys), the readers (get, at, to_f64, to_i64), and the round-trip
# law over 300 seeded values. Every byte past printable ascii prints as \xHH.
import Base
import ../../power/json_value.bend as JV

def hx(+d: U32) -> String:
  Bytes.slice("0123456789abcdef", U32.to_nat(d), 1n)

def vis.c(+c: U32) -> String:
  Bool.pick(String, U32.is_ge(c, 32) && U32.is_lt(c, 127), SCon{Chr{c}, SNil{}},
    "\\x" ++ hx(U32.shrn(c, 4n)) ++ hx(U32.and(c, 15)))

def vis.go(s: Bytes(), acc: String) -> String:
  match s:
    case SNil{}:
      acc
    case SCon{Chr{+c}, t}:
      vis.go(t, acc ++ vis.c(c))

def vis(s: Bytes()) -> String:
  vis.go(s, "")

def reason(w: JV.Why) -> String:
  match w:
    case JV.Syntax{at, why}:
      "syntax"
    case JV.TooDeep{at}:
      "deep"
    case JV.Budget{at}:
      "budget"
    case JV.DupKey{at}:
      "dup"
    case JV.BadUtf8{at}:
      "utf8"
    case JV.Lone{at}:
      "lone"

def res(r: JV.Out(), tag: Bool) -> String:
  match r:
    case Done{v}:
      "ok " ++ vis(JV.show(v))
    case Fail{w}:
      match tag:
        case True{}:
          "err:" ++ reason(w)
        case False{}:
          "err"

def big() -> JV.Lim:
  JV.lim(1000000)

def row(name: String, +doc: Bytes()) -> String:
  name ++ " " ++ res(JV.parse(doc, big()), False{})

def kind(name: String, +doc: Bytes()) -> String:
  name ++ " " ++ res(JV.parse(doc, big()), True{})

def ownlen.go(ds: List<&2, Bytes()>, +n: Nat, +k: Nat) -> String:
  match ds:
    case Nil{}:
      "budget own length ok " ++ Nat.show(k) ++ "/" ++ Nat.show(n)
    case Con{+d, t}:
      ownlen.go(t, 1n+n, Bool.pick(Nat, JV.is_ok(JV.parse(d, JV.lim(U32.from_nat(Bytes.len(d))))), 1n+k, k))

def ownlen(ds: List<&2, Bytes()>) -> String:
  ownlen.go(ds, 0n, 0n)

def nest(k: Nat, s: Bytes()) -> Bytes():
  match k:
    case 0n:
      s
    case 1n+p:
      nest(p, Bytes.concat(["[", s, "]"]))

def deep(+k: U32, +d: U32) -> String:
  "deep k=" ++ U32.show(k) ++ " d=" ++ U32.show(d) ++ " " ++
    res(JV.parse(nest(U32.to_nat(k), ""), JV.Lim{d, 1000000, JV.Keep{}}), True{})

def dry(+doc: Bytes(), +lim: U32) -> String:
  "budget " ++ vis(doc) ++ " " ++ U32.show(lim) ++ " " ++ res(JV.parse(doc, JV.lim(lim)), True{})

def dup(+doc: Bytes()) -> String:
  "dup " ++ vis(doc) ++ " keep " ++ res(JV.parse(doc, big()), True{}) ++
    " refuse " ++ res(JV.parse(doc, JV.Lim{64, 1000000, JV.Refuse{}}), True{})

def opt(m: Maybe<&2, JV.Json>) -> String:
  match m:
    case None{}:
      "none"
    case Some{v}:
      vis(JV.show(v))

def tree(r: JV.Out()) -> JV.Json:
  match r:
    case Done{v}:
      v
    case Fail{w}:
      JV.Null{}

def get(+doc: Bytes(), +key: Bytes()) -> String:
  "get " ++ vis(key) ++ " " ++ opt(JV.get(tree(JV.parse(doc, big())), key))

def at(+doc: Bytes(), +i: Nat) -> String:
  "at " ++ Nat.show(i) ++ " " ++ opt(JV.at(tree(JV.parse(doc, big())), i))

def f64.show(m: Maybe<&2, F64>) -> String:
  match m:
    case None{}:
      "none"
    case Some{x}:
      F64.show(x)

def f64(+t: Bytes()) -> String:
  "f64 " ++ t ++ " " ++ f64.show(JV.to_f64(tree(JV.parse(t, big()))))

def i64.nat(a: I64) -> Nat:
  match a:
    case I64{x}:
      Word.to_nat(64n, x)

def i64.low() -> I64:
  I64.shrn(I64.not(I64{Word.zero(64n)}), 32n)

def i64.show(m: Maybe<&2, I64>) -> String:
  match m:
    case None{}:
      "none"
    case Some{+x}:
      Nat.show(i64.nat(I64.shrn(x, 32n))) ++ ":" ++ Nat.show(i64.nat(I64.and(x, i64.low())))

def i64(+t: Bytes()) -> String:
  "i64 " ++ t ++ " " ++ i64.show(JV.to_i64(tree(JV.parse(t, big()))))

def notnum() -> String:
  "non-numbers " ++ f64.show(JV.to_f64(JV.Str{"1"})) ++ " " ++ i64.show(JV.to_i64(JV.Null{}))

# -- the round trip: the generator json_value_gen.py runs too -----------------

def lcg(+s: U32) -> U32:
  U32.add(U32.mul(s, 1664525), 1013904223)

def draw(+s: U32) -> U32:
  U32.shrn(s, 8n)

def pieces() -> List<&2, Bytes()>:
  ["a", "Z", " ", "\"", "\\", "/", "\n", "\u{1}", "\u{1f}", "\u{7f}", "\u{c3}\u{a9}",
   "\u{e2}\u{82}\u{ac}", "\u{f0}\u{9f}\u{98}\u{80}"]

def keys() -> List<&2, Bytes()>:
  ["a", "b", "\u{c3}\u{a9}"]

def lexemes() -> List<&2, Bytes()>:
  ["0", "-0", "7", "-12", "3.25", "1e5", "-2.5E-3", "123456789012345678901234567890",
   "0.10", "1E+40"]

def nth(xs: List<&2, Bytes()>, i: Nat) -> Bytes():
  match xs i:
    case Nil{} _:
      ""
    case Con{h, t} 0n:
      h
    case Con{h, t} 1n+p:
      nth(t, p)

type Gs is Data:
  Gs{b: Bytes(), s: U32}

def gstr.step(+ps: List<&2, Bytes()>, g: Gs) -> Gs:
  match g:
    case Gs{b, s}:
      +s1 = lcg(s)
      Gs{Bytes.append(b, nth(ps, U32.to_nat(U32.mod(draw(s1), U32.from_nat(List.length(&2, Bytes(), ps)))))), s1}

def gstr(n: Nat, +ps: List<&2, Bytes()>, g: Gs) -> Gs:
  match n:
    case 0n:
      g
    case 1n+p:
      gstr(p, ps, gstr.step(ps, g))

# what a value will be, drawn before it is built: a leaf is whole, a container
# says how many members it will have
type Plan is Data:
  Leaf{v: JV.Json}
  PArr{dep: U32, k: Nat}
  PObj{dep: U32, k: Nat}

type Pl is Data:
  Pl{p: Plan, s: U32}

def plan.str(g: Gs) -> Pl:
  match g:
    case Gs{b, s}:
      Pl{Leaf{JV.Str{b}}, s}

def plan.c(+dep: U32, +c: U32, +q: U32, +s: U32) -> Pl:
  Bool.pick(Pl, U32.is_eq(c, 0), Pl{Leaf{JV.Null{}}, s},
  Bool.pick(Pl, U32.is_eq(c, 1), Pl{Leaf{JV.Flag{U32.is_eq(U32.and(q, 1), 1)}}, s},
  Bool.pick(Pl, U32.is_eq(c, 2), Pl{Leaf{JV.Num{nth(lexemes(), U32.to_nat(U32.mod(q, 10)))}}, s},
  Bool.pick(Pl, U32.is_eq(c, 3), plan.str(gstr(U32.to_nat(U32.mod(q, 6)), pieces(), Gs{"", s})),
  Bool.pick(Pl, U32.is_eq(c, 4), Pl{PArr{dep, U32.to_nat(U32.mod(q, 4))}, s},
    Pl{PObj{dep, U32.to_nat(U32.mod(q, 4))}, s})))))

def plan.r(+dep: U32, +s: U32, +r: U32) -> Pl:
  plan.c(dep, U32.mod(r, Bool.pick(U32, U32.is_ge(dep, 3), 4, 6)), U32.shrn(r, 4n), s)

def plan(+dep: U32, +s0: U32) -> Pl:
  +s = lcg(s0)
  plan.r(dep, s, draw(s))

type Gv is Data:
  Gv{v: JV.Json, s: U32}

def cons.a(+h: JV.Json, r: Gv) -> Gv:
  match r:
    case Gv{v, s}:
      match v:
        case JV.Arr{xs}:
          Gv{JV.Arr{Con{h, xs}}, s}
        case _:
          Gv{v, s}

def cons.o(+k: Bytes(), +h: JV.Json, r: Gv) -> Gv:
  match r:
    case Gv{v, s}:
      match v:
        case JV.Obj{kvs}:
          Gv{JV.Obj{Con{(k, h), kvs}}, s}
        case _:
          Gv{v, s}

def gv.v(g: Gv) -> JV.Json:
  match g:
    case Gv{v, s}:
      v

def gv.s(g: Gv) -> U32:
  match g:
    case Gv{v, s}:
      s

def pl.p(q: Pl) -> Plan:
  match q:
    case Pl{p, s}:
      p

def pl.s(q: Pl) -> U32:
  match q:
    case Pl{p, s}:
      s

def gs.b(g: Gs) -> Bytes():
  match g:
    case Gs{b, s}:
      b

def gs.s(g: Gs) -> U32:
  match g:
    case Gs{b, s}:
      s

def key(+s0: U32) -> Gs:
  +s = lcg(s0)
  gstr(U32.to_nat(U32.mod(draw(s), 3)), keys(), Gs{"", s})

# one def builds a value and the members of a container, so the recursion is
# on fuel alone: every call hands its callee the fuel less one
def build(fuel: Nat, pl: Plan, +s: U32) -> Gv:
  match fuel:
    case 0n:
      Gv{JV.Null{}, s}
    case 1n++f:
      match pl:
        case Leaf{v}:
          Gv{v, s}
        case PArr{+dep, k}:
          match k:
            case 0n:
              Gv{JV.Arr{[]}, s}
            case 1n+q:
              +e = plan(U32.inc(dep), s)
              +x = build(f, pl.p(e), pl.s(e))
              cons.a(gv.v(x), build(f, PArr{dep, q}, gv.s(x)))
        case PObj{+dep, k}:
          match k:
            case 0n:
              Gv{JV.Obj{[]}, s}
            case 1n+q:
              +kb = key(s)
              +e = plan(U32.inc(dep), gs.s(kb))
              +x = build(f, pl.p(e), pl.s(e))
              cons.o(gs.b(kb), gv.v(x), build(f, PObj{dep, q}, gv.s(x)))

def value(+seed: U32) -> JV.Json:
  +e = plan(0, seed)
  gv.v(build(64n, pl.p(e), pl.s(e)))

type Rt is Data:
  Rt{ok: Nat, h: U32, shown: List<&2, String>}

def rt.check(+j: JV.Json, +t: Bytes(), r: JV.Out()) -> Bool:
  match r:
    case Done{+v}:
      JV.eq(v, j) && String.eq(JV.show(v), t)
    case Fail{w}:
      False{}

def rt.one(+i: Nat, +j: JV.Json, +t: Bytes(), r: Rt) -> Rt:
  match r:
    case Rt{+ok, h, +shown}:
      Rt{Bool.pick(Nat, rt.check(j, t, JV.parse(t, big())), 1n+ok, ok),
        U32.add(U32.mul(h, 31), String.hash(t)),
        Bool.pick(List<&2, String>, Nat.is_lt(i, 5n),
          Con{"rt " ++ Nat.show(i) ++ " " ++ vis(t), shown}, shown)}

def rt.go(n: Nat, +i: Nat, r: Rt) -> Rt:
  match n:
    case 0n:
      r
    case 1n+p:
      +j = value(U32.add(U32.mul(U32.from_nat(i), 7919), 1))
      rt.go(p, 1n+i, rt.one(i, j, JV.show(j), r))

def rt.out(+n: Nat, r: Rt) -> String:
  match r:
    case Rt{ok, h, shown}:
      String.join(List.reverse(&2, String, shown), "\n") ++ "\nrt law " ++ Nat.show(ok) ++
        "/" ++ Nat.show(n) ++ " hash " ++ U32.show(h)

def roundtrip(+n: Nat) -> String:
  rt.out(n, rt.go(n, 0n, Rt{0n, 0, []}))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(row("y_arr_empty", "[]"))
    IO.print(row("y_arr_ws", " [ 1 , 2 ] "))
    IO.print(row("y_arr_nested", "[[[]],[[],[[]]]]"))
    IO.print(row("y_arr_mixed", "[null,true,false,0,\"\",[],{}]"))
    IO.print(row("y_obj_empty", "{}"))
    IO.print(row("y_obj_basic", "{\"a\":1,\"b\":[2,3],\"c\":{\"d\":null}}"))
    IO.print(row("y_obj_ws", "\u{9}{ \"a\" :\u{a}1 }\u{d}\u{a}"))
    IO.print(row("y_obj_empty_key", "{\"\":0}"))
    IO.print(row("y_obj_dup_key", "{\"a\":1,\"a\":2}"))
    IO.print(row("y_obj_order", "{\"z\":1,\"a\":2,\"m\":3}"))
    IO.print(row("y_num_zero", "0"))
    IO.print(row("y_num_neg_zero", "-0"))
    IO.print(row("y_num_int", "123456789"))
    IO.print(row("y_num_neg", "-42"))
    IO.print(row("y_num_frac", "3.25"))
    IO.print(row("y_num_exp", "1e5"))
    IO.print(row("y_num_exp_up", "1E+40"))
    IO.print(row("y_num_exp_neg", "-2.5E-3"))
    IO.print(row("y_num_zero_exp", "0e1"))
    IO.print(row("y_num_trailing_zero", "0.10"))
    IO.print(row("y_num_huge", "1e400"))
    IO.print(row("y_num_long", "123456789012345678901234567890"))
    IO.print(row("y_str_empty", "\"\""))
    IO.print(row("y_str_ascii", "\"hello world\""))
    IO.print(row("y_str_escapes", "\"\\\"\\\\\\/\\b\\f\\n\\r\\t\""))
    IO.print(row("y_str_u_ascii", "\"\\u0041\\u007a\""))
    IO.print(row("y_str_u_nul", "\"a\\u0000b\""))
    IO.print(row("y_str_u_ctrl", "\"\\u001f\\u0001\""))
    IO.print(row("y_str_u_2byte", "\"\\u00e9\""))
    IO.print(row("y_str_u_3byte", "\"\\u20ac\""))
    IO.print(row("y_str_u_upper_hex", "\"\\u00E9\\u20AC\""))
    IO.print(row("y_str_u_pair", "\"\\ud83d\\ude00\""))
    IO.print(row("y_str_u_pair_max", "\"\\udbff\\udfff\""))
    IO.print(row("y_str_u_fffe", "\"\\ufffe\\uffff\""))
    IO.print(row("y_str_raw_2byte", "\"caf\u{c3}\u{a9}\""))
    IO.print(row("y_str_raw_3byte", "\"\u{e2}\u{82}\u{ac}\""))
    IO.print(row("y_str_raw_4byte", "\"\u{f0}\u{9f}\u{98}\u{80}\""))
    IO.print(row("y_str_raw_del", "\"\u{7f}\""))
    IO.print(row("y_str_raw_max", "\"\u{f4}\u{8f}\u{bf}\u{bf}\""))
    IO.print(row("y_str_slash", "\"a/b\""))
    IO.print(row("y_lit_true", "true"))
    IO.print(row("y_lit_false", "false"))
    IO.print(row("y_lit_null", "null"))
    IO.print(row("y_key_escaped", "{\"\\u0061\":\"\\u0062\"}"))
    IO.print(row("y_deep_64", "[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]"))
    IO.print(row("n_empty", ""))
    IO.print(row("n_ws_only", "  "))
    IO.print(row("n_arr_trailing_comma", "[1,]"))
    IO.print(row("n_arr_leading_comma", "[,1]"))
    IO.print(row("n_arr_double_comma", "[1,,2]"))
    IO.print(row("n_arr_unclosed", "[1"))
    IO.print(row("n_arr_extra_close", "[1]]"))
    IO.print(row("n_arr_colon", "[1:2]"))
    IO.print(row("n_obj_trailing_comma", "{\"a\":1,}"))
    IO.print(row("n_obj_missing_colon", "{\"a\" 1}"))
    IO.print(row("n_obj_missing_value", "{\"a\":}"))
    IO.print(row("n_obj_unquoted_key", "{a:1}"))
    IO.print(row("n_obj_single_quote", "{'a':1}"))
    IO.print(row("n_obj_num_key", "{1:1}"))
    IO.print(row("n_obj_unclosed", "{\"a\":1"))
    IO.print(row("n_obj_close_arr", "{\"a\":1]"))
    IO.print(row("n_num_leading_zero", "01"))
    IO.print(row("n_num_dot_start", ".5"))
    IO.print(row("n_num_dot_end", "1."))
    IO.print(row("n_num_exp_empty", "1e"))
    IO.print(row("n_num_exp_sign", "1e+"))
    IO.print(row("n_num_minus", "-"))
    IO.print(row("n_num_plus", "+1"))
    IO.print(row("n_num_hex", "0x1"))
    IO.print(row("n_num_nan", "NaN"))
    IO.print(row("n_num_inf", "Infinity"))
    IO.print(row("n_num_neg_inf", "-Infinity"))
    IO.print(row("n_lit_tru", "tru"))
    IO.print(row("n_lit_nul", "nul"))
    IO.print(row("n_lit_True", "True"))
    IO.print(row("n_str_unclosed", "\"abc"))
    IO.print(row("n_str_single", "'a'"))
    IO.print(row("n_str_raw_ctrl", "\"a\u{1}b\""))
    IO.print(row("n_str_raw_newline", "\"a\u{a}b\""))
    IO.print(row("n_str_raw_tab", "\"a\u{9}b\""))
    IO.print(row("n_str_bad_escape", "\"\\x41\""))
    IO.print(row("n_str_upper_U", "\"\\U0041\""))
    IO.print(row("n_str_short_u", "\"\\u12\""))
    IO.print(row("n_str_bad_hex", "\"\\u12g4\""))
    IO.print(row("n_str_escape_end", "\"\\"))
    IO.print(row("n_two_values", "1 2"))
    IO.print(row("n_trailing_garbage", "[]x"))
    IO.print(row("n_comment", "[1/*c*/]"))
    IO.print(row("n_bom", "\u{ef}\u{bb}\u{bf}[]"))
    IO.print(row("n_utf8_outside", "[\u{c3}\u{a9}]"))
    IO.print(kind("i_str_lone_high", "\"\\ud800\""))
    IO.print(kind("i_str_lone_low", "\"\\udc00\""))
    IO.print(kind("i_str_high_then_ascii", "\"\\ud800\\u0041\""))
    IO.print(kind("i_str_high_then_char", "\"\\ud800x\""))
    IO.print(kind("i_str_high_then_escape", "\"\\ud800\\n\""))
    IO.print(kind("i_str_two_highs", "\"\\ud800\\ud800\""))
    IO.print(kind("i_str_high_at_end", "[\"\\udbff\"]"))
    IO.print(kind("i_key_lone", "{\"\\udfff\":1}"))
    IO.print(kind("i_utf8_lone_cont", "\"\u{80}\""))
    IO.print(kind("i_utf8_overlong_2", "\"\u{c0}\u{80}\""))
    IO.print(kind("i_utf8_overlong_c1", "\"\u{c1}\u{bf}\""))
    IO.print(kind("i_utf8_overlong_3", "\"\u{e0}\u{80}\u{80}\""))
    IO.print(kind("i_utf8_overlong_4", "\"\u{f0}\u{80}\u{80}\u{80}\""))
    IO.print(kind("i_utf8_surrogate", "\"\u{ed}\u{a0}\u{80}\""))
    IO.print(kind("i_utf8_past_max", "\"\u{f4}\u{90}\u{80}\u{80}\""))
    IO.print(kind("i_utf8_f5", "\"\u{f5}\u{80}\u{80}\u{80}\""))
    IO.print(kind("i_utf8_ff", "\"\u{ff}\""))
    IO.print(kind("i_utf8_truncated", "\"\u{e2}\u{82}\""))
    IO.print(kind("i_utf8_truncated_mid", "\"\u{e2}\u{82}a\""))
    IO.print(kind("i_utf8_in_key", "{\"\u{c3}\":1}"))
    IO.print(kind("i_utf8_escaped_string", "\"\\n\u{c3}\""))
    IO.print(ownlen(["[]", " [ 1 , 2 ] ", "[[[]],[[],[[]]]]", "[null,true,false,0,\"\",[],{}]", "{}", "{\"a\":1,\"b\":[2,3],\"c\":{\"d\":null}}", "\u{9}{ \"a\" :\u{a}1 }\u{d}\u{a}", "{\"\":0}", "{\"a\":1,\"a\":2}", "{\"z\":1,\"a\":2,\"m\":3}", "0", "-0", "123456789", "-42", "3.25", "1e5", "1E+40", "-2.5E-3", "0e1", "0.10", "1e400", "123456789012345678901234567890", "\"\"", "\"hello world\"", "\"\\\"\\\\\\/\\b\\f\\n\\r\\t\"", "\"\\u0041\\u007a\"", "\"a\\u0000b\"", "\"\\u001f\\u0001\"", "\"\\u00e9\"", "\"\\u20ac\"", "\"\\u00E9\\u20AC\"", "\"\\ud83d\\ude00\"", "\"\\udbff\\udfff\"", "\"\\ufffe\\uffff\"", "\"caf\u{c3}\u{a9}\"", "\"\u{e2}\u{82}\u{ac}\"", "\"\u{f0}\u{9f}\u{98}\u{80}\"", "\"\u{7f}\"", "\"\u{f4}\u{8f}\u{bf}\u{bf}\"", "\"a/b\"", "true", "false", "null", "{\"\\u0061\":\"\\u0062\"}", "[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]"]))
    IO.print(deep(1, 1))
    IO.print(deep(2, 1))
    IO.print(deep(8, 8))
    IO.print(deep(9, 8))
    IO.print(deep(64, 64))
    IO.print(deep(65, 64))
    IO.print(deep(256, 300))
    IO.print(deep(257, 300))
    IO.print(dry("\"0123456789\"", 12))
    IO.print(dry("\"0123456789\"", 11))
    IO.print(dry("\"0123456789\"", 3))
    IO.print(dry("12345678", 8))
    IO.print(dry("12345678", 7))
    IO.print(dry("12345678", 3))
    IO.print(dry("\"\\u00e9\\u00e9\"", 14))
    IO.print(dry("\"\\u00e9\\u00e9\"", 13))
    IO.print(dry("\"\\u00e9\\u00e9\"", 3))
    IO.print(dry("[\"abcd\",\"abcd\",\"abcd\",\"abcd\",\"abcd\",\"abcd\",\"abcd\",\"abcd\"]", 57))
    IO.print(dry("[\"abcd\",\"abcd\",\"abcd\",\"abcd\",\"abcd\",\"abcd\",\"abcd\",\"abcd\"]", 30))
    IO.print(dup("{\"a\":1,\"a\":2}"))
    IO.print(dup("{\"a\":1,\"b\":{\"a\":2}}"))
    IO.print(dup("{\"a\":1,\"\\u0061\":2}"))
    IO.print(dup("[{\"a\":1},{\"a\":1}]"))
    IO.print(dup("{\"k\":{\"x\":1,\"y\":2,\"x\":3}}"))
    IO.print(dup("{\"\":1,\"\":2}"))
    IO.print(get("{\"a\":1,\"b\":[true,\"x\"],\"a\":{\"c\":null}}", "a"))
    IO.print(get("{\"a\":1,\"b\":[true,\"x\"],\"a\":{\"c\":null}}", "b"))
    IO.print(get("{\"a\":1,\"b\":[true,\"x\"],\"a\":{\"c\":null}}", "c"))
    IO.print(get("{\"a\":1,\"b\":[true,\"x\"],\"a\":{\"c\":null}}", ""))
    IO.print(get("{\"\\u00e9\":2,\"\":3}", "\u{c3}\u{a9}"))
    IO.print(get("{\"\\u00e9\":2,\"\":3}", ""))
    IO.print(get("[1,2]", "a"))
    IO.print(at("[10,\"s\",[1],{\"k\":0}]", 0n))
    IO.print(at("[10,\"s\",[1],{\"k\":0}]", 1n))
    IO.print(at("[10,\"s\",[1],{\"k\":0}]", 2n))
    IO.print(at("[10,\"s\",[1],{\"k\":0}]", 3n))
    IO.print(at("[10,\"s\",[1],{\"k\":0}]", 4n))
    IO.print(at("{\"a\":1}", 0n))
    IO.print(at("[]", 0n))
    IO.print(f64("0"))
    IO.print(f64("-0"))
    IO.print(f64("1"))
    IO.print(f64("-7"))
    IO.print(f64("3.25"))
    IO.print(f64("1e5"))
    IO.print(f64("1E+40"))
    IO.print(f64("-2.5E-3"))
    IO.print(f64("0.10"))
    IO.print(f64("1e400"))
    IO.print(f64("-1e400"))
    IO.print(f64("123456789"))
    IO.print(f64("9007199254740993"))
    IO.print(f64("0.1"))
    IO.print(f64("1e-7"))
    IO.print(f64("123e-20"))
    IO.print(f64("1e21"))
    IO.print(f64("5e-324"))
    IO.print(i64("0"))
    IO.print(i64("-0"))
    IO.print(i64("1"))
    IO.print(i64("-1"))
    IO.print(i64("4294967296"))
    IO.print(i64("-4294967297"))
    IO.print(i64("9223372036854775807"))
    IO.print(i64("-9223372036854775808"))
    IO.print(i64("9223372036854775808"))
    IO.print(i64("-9223372036854775809"))
    IO.print(i64("12345678901234567890"))
    IO.print(i64("1.0"))
    IO.print(i64("1e2"))
    IO.print(i64("-5"))
    IO.print(notnum())
    IO.print(roundtrip(300n))
#|y_arr_empty ok []
#|y_arr_ws ok [1,2]
#|y_arr_nested ok [[[]],[[],[[]]]]
#|y_arr_mixed ok [null,true,false,0,"",[],{}]
#|y_obj_empty ok {}
#|y_obj_basic ok {"a":1,"b":[2,3],"c":{"d":null}}
#|y_obj_ws ok {"a":1}
#|y_obj_empty_key ok {"":0}
#|y_obj_dup_key ok {"a":1,"a":2}
#|y_obj_order ok {"z":1,"a":2,"m":3}
#|y_num_zero ok 0
#|y_num_neg_zero ok -0
#|y_num_int ok 123456789
#|y_num_neg ok -42
#|y_num_frac ok 3.25
#|y_num_exp ok 1e5
#|y_num_exp_up ok 1E+40
#|y_num_exp_neg ok -2.5E-3
#|y_num_zero_exp ok 0e1
#|y_num_trailing_zero ok 0.10
#|y_num_huge ok 1e400
#|y_num_long ok 123456789012345678901234567890
#|y_str_empty ok ""
#|y_str_ascii ok "hello world"
#|y_str_escapes ok "\"\\/\b\f\n\r\t"
#|y_str_u_ascii ok "Az"
#|y_str_u_nul ok "a\u0000b"
#|y_str_u_ctrl ok "\u001f\u0001"
#|y_str_u_2byte ok "\xc3\xa9"
#|y_str_u_3byte ok "\xe2\x82\xac"
#|y_str_u_upper_hex ok "\xc3\xa9\xe2\x82\xac"
#|y_str_u_pair ok "\xf0\x9f\x98\x80"
#|y_str_u_pair_max ok "\xf4\x8f\xbf\xbf"
#|y_str_u_fffe ok "\xef\xbf\xbe\xef\xbf\xbf"
#|y_str_raw_2byte ok "caf\xc3\xa9"
#|y_str_raw_3byte ok "\xe2\x82\xac"
#|y_str_raw_4byte ok "\xf0\x9f\x98\x80"
#|y_str_raw_del ok "\x7f"
#|y_str_raw_max ok "\xf4\x8f\xbf\xbf"
#|y_str_slash ok "a/b"
#|y_lit_true ok true
#|y_lit_false ok false
#|y_lit_null ok null
#|y_key_escaped ok {"a":"b"}
#|y_deep_64 ok [[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]
#|n_empty err
#|n_ws_only err
#|n_arr_trailing_comma err
#|n_arr_leading_comma err
#|n_arr_double_comma err
#|n_arr_unclosed err
#|n_arr_extra_close err
#|n_arr_colon err
#|n_obj_trailing_comma err
#|n_obj_missing_colon err
#|n_obj_missing_value err
#|n_obj_unquoted_key err
#|n_obj_single_quote err
#|n_obj_num_key err
#|n_obj_unclosed err
#|n_obj_close_arr err
#|n_num_leading_zero err
#|n_num_dot_start err
#|n_num_dot_end err
#|n_num_exp_empty err
#|n_num_exp_sign err
#|n_num_minus err
#|n_num_plus err
#|n_num_hex err
#|n_num_nan err
#|n_num_inf err
#|n_num_neg_inf err
#|n_lit_tru err
#|n_lit_nul err
#|n_lit_True err
#|n_str_unclosed err
#|n_str_single err
#|n_str_raw_ctrl err
#|n_str_raw_newline err
#|n_str_raw_tab err
#|n_str_bad_escape err
#|n_str_upper_U err
#|n_str_short_u err
#|n_str_bad_hex err
#|n_str_escape_end err
#|n_two_values err
#|n_trailing_garbage err
#|n_comment err
#|n_bom err
#|n_utf8_outside err
#|i_str_lone_high err:lone
#|i_str_lone_low err:lone
#|i_str_high_then_ascii err:lone
#|i_str_high_then_char err:lone
#|i_str_high_then_escape err:lone
#|i_str_two_highs err:lone
#|i_str_high_at_end err:lone
#|i_key_lone err:lone
#|i_utf8_lone_cont err:utf8
#|i_utf8_overlong_2 err:utf8
#|i_utf8_overlong_c1 err:utf8
#|i_utf8_overlong_3 err:utf8
#|i_utf8_overlong_4 err:utf8
#|i_utf8_surrogate err:utf8
#|i_utf8_past_max err:utf8
#|i_utf8_f5 err:utf8
#|i_utf8_ff err:utf8
#|i_utf8_truncated err:utf8
#|i_utf8_truncated_mid err:utf8
#|i_utf8_in_key err:utf8
#|i_utf8_escaped_string err:utf8
#|budget own length ok 45/45
#|deep k=1 d=1 ok []
#|deep k=2 d=1 err:deep
#|deep k=8 d=8 ok [[[[[[[[]]]]]]]]
#|deep k=9 d=8 err:deep
#|deep k=64 d=64 ok [[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]
#|deep k=65 d=64 err:deep
#|deep k=256 d=300 ok [[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]
#|deep k=257 d=300 err:deep
#|budget "0123456789" 12 ok "0123456789"
#|budget "0123456789" 11 err:budget
#|budget "0123456789" 3 err:budget
#|budget 12345678 8 ok 12345678
#|budget 12345678 7 err:budget
#|budget 12345678 3 err:budget
#|budget "\u00e9\u00e9" 14 ok "\xc3\xa9\xc3\xa9"
#|budget "\u00e9\u00e9" 13 err:budget
#|budget "\u00e9\u00e9" 3 err:budget
#|budget ["abcd","abcd","abcd","abcd","abcd","abcd","abcd","abcd"] 57 ok ["abcd","abcd","abcd","abcd","abcd","abcd","abcd","abcd"]
#|budget ["abcd","abcd","abcd","abcd","abcd","abcd","abcd","abcd"] 30 err:budget
#|dup {"a":1,"a":2} keep ok {"a":1,"a":2} refuse err:dup
#|dup {"a":1,"b":{"a":2}} keep ok {"a":1,"b":{"a":2}} refuse ok {"a":1,"b":{"a":2}}
#|dup {"a":1,"\u0061":2} keep ok {"a":1,"a":2} refuse err:dup
#|dup [{"a":1},{"a":1}] keep ok [{"a":1},{"a":1}] refuse ok [{"a":1},{"a":1}]
#|dup {"k":{"x":1,"y":2,"x":3}} keep ok {"k":{"x":1,"y":2,"x":3}} refuse err:dup
#|dup {"":1,"":2} keep ok {"":1,"":2} refuse err:dup
#|get a {"c":null}
#|get b [true,"x"]
#|get c none
#|get  none
#|get \xc3\xa9 2
#|get  3
#|get a none
#|at 0 10
#|at 1 "s"
#|at 2 [1]
#|at 3 {"k":0}
#|at 4 none
#|at 0 none
#|at 0 none
#|f64 0 0
#|f64 -0 -0
#|f64 1 1
#|f64 -7 -7
#|f64 3.25 3.25
#|f64 1e5 100000
#|f64 1E+40 1e+40
#|f64 -2.5E-3 -0.0025
#|f64 0.10 0.1
#|f64 1e400 inf
#|f64 -1e400 -inf
#|f64 123456789 123456789
#|f64 9007199254740993 9007199254740992
#|f64 0.1 0.1
#|f64 1e-7 1e-7
#|f64 123e-20 1.23e-18
#|f64 1e21 1e+21
#|f64 5e-324 5e-324
#|i64 0 0:0
#|i64 -0 0:0
#|i64 1 0:1
#|i64 -1 4294967295:4294967295
#|i64 4294967296 1:0
#|i64 -4294967297 4294967294:4294967295
#|i64 9223372036854775807 2147483647:4294967295
#|i64 -9223372036854775808 2147483648:0
#|i64 9223372036854775808 none
#|i64 -9223372036854775809 none
#|i64 12345678901234567890 none
#|i64 1.0 none
#|i64 1e2 none
#|i64 -5 4294967295:4294967291
#|non-numbers none none
#|rt 0 "ZZ\u001f"
#|rt 1 {"\xc3\xa9":"","":"\xf0\x9f\x98\x80Z"}
#|rt 2 true
#|rt 3 "\x7f\u0001\x7f\u0001a"
#|rt 4 {}
#|rt law 300/300 hash 3177533287
