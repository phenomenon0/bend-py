#!/usr/bin/env python3
# The oracle for json_value.bend: prints the whole fixture.
#
# CPython's json decides every row. A document is first decoded as strict UTF-8
# (RFC 8259 section 8.1: the text is UTF-8), then handed to json.loads with
# hooks that keep what the Bend tree keeps -- every object pair in order
# (object_pairs_hook), every number's own lexeme (parse_int, parse_float), and
# NaN / Infinity refused (parse_constant; they are not JSON). The canonical
# text of what it built is then written here with json.dumps' own string
# escaper, so the expected output of every accepted document is CPython's
# tree in CPython's spelling, and a refused one is `err`.
#
# Where RFC 8259 leaves the parser a choice, power/json_value.bend's header
# states the one it makes, and the rows tagged with a kind pin it: a lone
# surrogate escape (CPython builds a str it cannot encode) is `lone`, invalid
# UTF-8 is `utf8`, a duplicate key under Refuse is `dup`, nesting past the
# cap is `deep`, and a value the budget cannot afford is `budget`. The
# generator checks each tag against CPython before printing it: a `lone` row
# must be one CPython accepts with a surrogate inside, a `utf8` row one whose
# bytes do not decode, a `dup` row one whose pairs repeat a key.
#
# The round trip is a law over values, not documents: the Bend file builds
# 300 values from a seeded generator (every byte class a string can hold:
# quotes, backslashes, controls, DEL, two-, three- and four-byte UTF-8; ten
# number lexemes; nesting to 4), and for each checks parse(show(j)) == Done{j}
# and show(parse(show(j))) == show(j). This file runs the same generator, so
# the texts it expects -- five printed whole, all 300 folded into a hash -- are
# CPython's canonical text of the same values, and json.loads is asked to read
# each back as the value it came from.
import json
import sys

sys.setrecursionlimit(10000)


class Raw:
    def __init__(self, text):
        self.text = text


class Obj:
    def __init__(self, kvs):
        self.kvs = kvs


def bad_constant(name):
    raise ValueError("not json: " + name)


def load(s):
    return json.loads(
        s,
        object_pairs_hook=Obj,
        parse_int=Raw,
        parse_float=Raw,
        parse_constant=bad_constant,
    )


def canon(v):
    if v is None:
        return "null"
    if v is True:
        return "true"
    if v is False:
        return "false"
    if isinstance(v, Raw):
        return v.text
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, list):
        return "[" + ",".join(canon(x) for x in v) + "]"
    if isinstance(v, Obj):
        return "{" + ",".join(canon(k) + ":" + canon(x) for k, x in v.kvs) + "}"
    raise TypeError(v)


def strings(v):
    if isinstance(v, str):
        yield v
    elif isinstance(v, list):
        for x in v:
            yield from strings(x)
    elif isinstance(v, Obj):
        for k, x in v.kvs:
            yield k
            yield from strings(x)


def lone(v):
    return any(0xD800 <= ord(c) <= 0xDFFF for s in strings(v) for c in s)


def dups(v):
    if isinstance(v, list):
        return any(dups(x) for x in v)
    if isinstance(v, Obj):
        ks = [k for k, _ in v.kvs]
        return len(set(ks)) < len(ks) or any(dups(x) for _, x in v.kvs)
    return False


def depth(v):
    if isinstance(v, list):
        return 1 + max((depth(x) for x in v), default=0)
    if isinstance(v, Obj):
        return 1 + max((depth(x) for _, x in v.kvs), default=0)
    return 0


def vis(b):
    # the fixture stays ascii: printable bytes as they are, the rest \xHH
    return "".join(chr(c) if 32 <= c < 127 else "\\x%02x" % c for c in b)


def verdict(b):
    # (accepted?, the python value or None, why it was refused)
    try:
        s = b.decode("utf-8")
    except UnicodeDecodeError:
        return False, None, "utf8"
    try:
        v = load(s)
    except (ValueError, RecursionError):
        return False, None, "syntax"
    if lone(v):
        return False, v, "lone"
    return True, v, None


def lit(b):
    # a Bend string literal holding exactly these bytes, one Char per byte
    out = []
    for c in b:
        if c == 34:
            out.append('\\"')
        elif c == 92:
            out.append("\\\\")
        elif 32 <= c < 127:
            out.append(chr(c))
        else:
            out.append("\\u{%x}" % c)
    return '"' + "".join(out) + '"'


rows, want = [], []

# -- the corpus: y_ must parse, n_ must be refused, i_ is where RFC 8259 lets a
# parser choose and this one's choice is pinned. Written for this file in the
# JSONTestSuite naming; nothing is fetched. ---------------------------------
Y = [
    ("y_arr_empty", b"[]"),
    ("y_arr_ws", b" [ 1 , 2 ] "),
    ("y_arr_nested", b"[[[]],[[],[[]]]]"),
    ("y_arr_mixed", b'[null,true,false,0,"",[],{}]'),
    ("y_obj_empty", b"{}"),
    ("y_obj_basic", b'{"a":1,"b":[2,3],"c":{"d":null}}'),
    ("y_obj_ws", b'\t{ "a" :\n1 }\r\n'),
    ("y_obj_empty_key", b'{"":0}'),
    ("y_obj_dup_key", b'{"a":1,"a":2}'),
    ("y_obj_order", b'{"z":1,"a":2,"m":3}'),
    ("y_num_zero", b"0"),
    ("y_num_neg_zero", b"-0"),
    ("y_num_int", b"123456789"),
    ("y_num_neg", b"-42"),
    ("y_num_frac", b"3.25"),
    ("y_num_exp", b"1e5"),
    ("y_num_exp_up", b"1E+40"),
    ("y_num_exp_neg", b"-2.5E-3"),
    ("y_num_zero_exp", b"0e1"),
    ("y_num_trailing_zero", b"0.10"),
    ("y_num_huge", b"1e400"),
    ("y_num_long", b"123456789012345678901234567890"),
    ("y_str_empty", b'""'),
    ("y_str_ascii", b'"hello world"'),
    ("y_str_escapes", b'"\\"\\\\\\/\\b\\f\\n\\r\\t"'),
    ("y_str_u_ascii", b'"\\u0041\\u007a"'),
    ("y_str_u_nul", b'"a\\u0000b"'),
    ("y_str_u_ctrl", b'"\\u001f\\u0001"'),
    ("y_str_u_2byte", b'"\\u00e9"'),
    ("y_str_u_3byte", b'"\\u20ac"'),
    ("y_str_u_upper_hex", b'"\\u00E9\\u20AC"'),
    ("y_str_u_pair", b'"\\ud83d\\ude00"'),
    ("y_str_u_pair_max", b'"\\udbff\\udfff"'),
    ("y_str_u_fffe", b'"\\ufffe\\uffff"'),
    ("y_str_raw_2byte", '"caf\u00e9"'.encode()),
    ("y_str_raw_3byte", '"\u20ac"'.encode()),
    ("y_str_raw_4byte", '"\U0001f600"'.encode()),
    ("y_str_raw_del", b'"\x7f"'),
    ("y_str_raw_max", '"\U0010ffff"'.encode()),
    ("y_str_slash", b'"a/b"'),
    ("y_lit_true", b"true"),
    ("y_lit_false", b"false"),
    ("y_lit_null", b"null"),
    ("y_key_escaped", b'{"\\u0061":"\\u0062"}'),
    ("y_deep_64", b"[" * 64 + b"]" * 64),
]
N = [
    ("n_empty", b""),
    ("n_ws_only", b"  "),
    ("n_arr_trailing_comma", b"[1,]"),
    ("n_arr_leading_comma", b"[,1]"),
    ("n_arr_double_comma", b"[1,,2]"),
    ("n_arr_unclosed", b"[1"),
    ("n_arr_extra_close", b"[1]]"),
    ("n_arr_colon", b"[1:2]"),
    ("n_obj_trailing_comma", b'{"a":1,}'),
    ("n_obj_missing_colon", b'{"a" 1}'),
    ("n_obj_missing_value", b'{"a":}'),
    ("n_obj_unquoted_key", b"{a:1}"),
    ("n_obj_single_quote", b"{'a':1}"),
    ("n_obj_num_key", b"{1:1}"),
    ("n_obj_unclosed", b'{"a":1'),
    ("n_obj_close_arr", b'{"a":1]'),
    ("n_num_leading_zero", b"01"),
    ("n_num_dot_start", b".5"),
    ("n_num_dot_end", b"1."),
    ("n_num_exp_empty", b"1e"),
    ("n_num_exp_sign", b"1e+"),
    ("n_num_minus", b"-"),
    ("n_num_plus", b"+1"),
    ("n_num_hex", b"0x1"),
    ("n_num_nan", b"NaN"),
    ("n_num_inf", b"Infinity"),
    ("n_num_neg_inf", b"-Infinity"),
    ("n_lit_tru", b"tru"),
    ("n_lit_nul", b"nul"),
    ("n_lit_True", b"True"),
    ("n_str_unclosed", b'"abc'),
    ("n_str_single", b"'a'"),
    ("n_str_raw_ctrl", b'"a\x01b"'),
    ("n_str_raw_newline", b'"a\nb"'),
    ("n_str_raw_tab", b'"a\tb"'),
    ("n_str_bad_escape", b'"\\x41"'),
    ("n_str_upper_U", b'"\\U0041"'),
    ("n_str_short_u", b'"\\u12"'),
    ("n_str_bad_hex", b'"\\u12g4"'),
    ("n_str_escape_end", b'"\\'),
    ("n_two_values", b"1 2"),
    ("n_trailing_garbage", b"[]x"),
    ("n_comment", b"[1/*c*/]"),
    ("n_bom", b"\xef\xbb\xbf[]"),
    ("n_utf8_outside", b"[\xc3\xa9]"),
]
I = [
    # RFC 8259 8.2: a lone surrogate names no character; CPython keeps it in a
    # str it cannot encode, this parser refuses it at its backslash
    ("i_str_lone_high", b'"\\ud800"', "lone"),
    ("i_str_lone_low", b'"\\udc00"', "lone"),
    ("i_str_high_then_ascii", b'"\\ud800\\u0041"', "lone"),
    ("i_str_high_then_char", b'"\\ud800x"', "lone"),
    ("i_str_high_then_escape", b'"\\ud800\\n"', "lone"),
    ("i_str_two_highs", b'"\\ud800\\ud800"', "lone"),
    ("i_str_high_at_end", b'["\\udbff"]', "lone"),
    ("i_key_lone", b'{"\\udfff":1}', "lone"),
    # RFC 8259 8.1: the text is UTF-8, so a string byte sequence that is not
    ("i_utf8_lone_cont", b'"\x80"', "utf8"),
    ("i_utf8_overlong_2", b'"\xc0\x80"', "utf8"),
    ("i_utf8_overlong_c1", b'"\xc1\xbf"', "utf8"),
    ("i_utf8_overlong_3", b'"\xe0\x80\x80"', "utf8"),
    ("i_utf8_overlong_4", b'"\xf0\x80\x80\x80"', "utf8"),
    ("i_utf8_surrogate", b'"\xed\xa0\x80"', "utf8"),
    ("i_utf8_past_max", b'"\xf4\x90\x80\x80"', "utf8"),
    ("i_utf8_f5", b'"\xf5\x80\x80\x80"', "utf8"),
    ("i_utf8_ff", b'"\xff"', "utf8"),
    ("i_utf8_truncated", b'"\xe2\x82"', "utf8"),
    ("i_utf8_truncated_mid", b'"\xe2\x82a"', "utf8"),
    ("i_utf8_in_key", b'{"\xc3":1}', "utf8"),
    ("i_utf8_escaped_string", b'"\\n\xc3"', "utf8"),
]

for name, b in Y:
    ok, v, why = verdict(b)
    assert ok, name
    rows.append('row("%s", %s)' % (name, lit(b)))
    want.append("%s ok %s" % (name, vis(canon(v).encode())))
for name, b in N:
    ok, v, why = verdict(b)
    assert not ok and why in ("syntax", "utf8"), name
    rows.append('row("%s", %s)' % (name, lit(b)))
    want.append("%s err" % name)
for name, b, tag in I:
    ok, v, why = verdict(b)
    assert not ok and why == tag, (name, why)
    rows.append('kind("%s", %s)' % (name, lit(b)))
    want.append("%s err:%s" % (name, tag))

# every accepted document also parses under a budget of exactly its own length
n = sum(1 for _, b in Y)
rows.append('ownlen([%s])' % ", ".join(lit(b) for _, b in Y))
want.append("budget own length ok %d/%d" % (n, n))

# -- limits -------------------------------------------------------------------

# nesting k under a cap d parses iff k <= d, and never past the tokenizer's 256
for k, d in [(1, 1), (2, 1), (8, 8), (9, 8), (64, 64), (65, 64), (256, 300), (257, 300)]:
    b = b"[" * k + b"]" * k
    assert verdict(b)[0] and depth(load(b.decode())) == k
    rows.append('deep(%d, %d)' % (k, d))
    want.append("deep k=%d d=%d %s" % (k, d, "ok " + vis(b) if k <= min(d, 256) else "err:deep"))

# a value longer than the budget is refused as Budget: a document that is one
# string or one number costs its whole length, so the budget one short of it is
# the first one refused
for b in [b'"0123456789"', b"12345678", b'"\\u00e9\\u00e9"']:
    assert verdict(b)[0]
    for lim in (len(b), len(b) - 1, 3):
        rows.append('dry(%s, %d)' % (lit(b), lim))
        want.append("budget %s %d %s" % (vis(b), lim, "ok " + vis(canon(load(b.decode())).encode())
                                         if lim >= len(b) else "err:budget"))

# a budget covers the whole document: one value too many costs it
b = b"[" + b",".join([b'"abcd"'] * 8) + b"]"
for lim in (len(b), 30):
    rows.append('dry(%s, %d)' % (lit(b), lim))
want.append("budget %s %d ok %s" % (vis(b), len(b), vis(b)))
want.append("budget %s 30 err:budget" % vis(b))

# duplicate keys: Keep holds every pair (CPython's pairs), Refuse refuses the
# second at its key -- in the same object only, and by the unescaped bytes
for b in [b'{"a":1,"a":2}', b'{"a":1,"b":{"a":2}}', b'{"a":1,"\\u0061":2}', b'[{"a":1},{"a":1}]',
          b'{"k":{"x":1,"y":2,"x":3}}', b'{"":1,"":2}']:
    ok, v, _ = verdict(b)
    assert ok
    rows.append('dup(%s)' % lit(b))
    want.append("dup %s keep ok %s refuse %s" % (vis(b), vis(canon(v).encode()),
                                                 "err:dup" if dups(v) else "ok " + vis(canon(v).encode())))

# -- reading into it ----------------------------------------------------------


def pyget(v, key):
    got = None
    if isinstance(v, Obj):
        for k, x in v.kvs:
            if k == key:
                got = x
    return got


def pyat(v, i):
    return v[i] if isinstance(v, list) and i < len(v) else None


def show_opt(x):
    return "none" if x is None else vis(canon(x).encode())


GETS = [
    (b'{"a":1,"b":[true,"x"],"a":{"c":null}}', ["a", "b", "c", ""]),
    (b'{"\\u00e9":2,"":3}', ["\u00e9", ""]),
    (b"[1,2]", ["a"]),
]
for b, keys in GETS:
    v = load(b.decode())
    for key in keys:
        rows.append('get(%s, %s)' % (lit(b), lit(key.encode())))
        want.append("get %s %s" % (vis(key.encode()), show_opt(pyget(v, key))))
ATS = [(b'[10,"s",[1],{"k":0}]', [0, 1, 2, 3, 4]), (b'{"a":1}', [0]), (b"[]", [0])]
for b, idxs in ATS:
    v = load(b.decode())
    for i in idxs:
        rows.append('at(%s, %dn)' % (lit(b), i))
        want.append("at %d %s" % (i, show_opt(pyat(v, i))))


# -- numbers: to_f64 is CPython's float of the lexeme, printed as Bend prints an
# F64 (JavaScript's Number#toString, which the C runtime's f64_text copies);
# to_i64 is the integer when the lexeme is one and it fits, as the two halves
# of its 64-bit pattern ------------------------------------------------------


def js_num(x):
    if x != x:
        return "nan"
    if x in (float("inf"), float("-inf")):
        return "inf" if x > 0 else "-inf"
    if x == 0:
        return "-0" if str(x).startswith("-") else "0"
    sign = "-" if x < 0 else ""
    r = repr(abs(x))
    if "e" in r:
        mant, ex = r.split("e")
        e = int(ex)
    else:
        mant, e = r, 0
    if "." in mant:
        ip, fp = mant.split(".")
    else:
        ip, fp = mant, ""
    digits = (ip + fp).lstrip("0")
    point = len(ip) + e  # the decimal point sits after this many digits of ip+fp
    lead = len(ip + fp) - len((ip + fp).lstrip("0"))
    point -= lead
    digits = digits.rstrip("0") or "0"
    k, n = len(digits), point
    if k <= n <= 21:
        return sign + digits + "0" * (n - k)
    if 0 < n <= 21:
        return sign + digits[:n] + "." + digits[n:]
    if -6 < n <= 0:
        return sign + "0." + "0" * (-n) + digits
    m = digits[0] + ("." + digits[1:] if k > 1 else "")
    return sign + m + "e" + ("+" if n - 1 >= 0 else "-") + str(abs(n - 1))


NUMS = ["0", "-0", "1", "-7", "3.25", "1e5", "1E+40", "-2.5E-3", "0.10", "1e400", "-1e400",
        "123456789", "9007199254740993", "0.1", "1e-7", "123e-20", "1e21", "5e-324"]
for t in NUMS:
    rows.append('f64("%s")' % t)
    want.append("f64 %s %s" % (t, js_num(float(t))))
INTS = ["0", "-0", "1", "-1", "4294967296", "-4294967297", "9223372036854775807",
        "-9223372036854775808", "9223372036854775808", "-9223372036854775809",
        "12345678901234567890", "1.0", "1e2", "-5"]
for t in INTS:
    rows.append('i64("%s")' % t)
    fits = "." not in t and "e" not in t.lower() and -(2**63) <= int(t) < 2**63
    if fits:
        u = int(t) % 2**64
        want.append("i64 %s %d:%d" % (t, u >> 32, u & 0xFFFFFFFF))
    else:
        want.append("i64 %s none" % t)
rows.append('notnum()')
want.append("non-numbers none none")

# -- the round trip, over the same seeded values the Bend file builds ---------

M32 = 0xFFFFFFFF


def lcg(s):
    return (s * 1664525 + 1013904223) & M32


def draw(s):
    return s >> 8


PIECES = [b"a", b"Z", b" ", b'"', b"\\", b"/", b"\n", b"\x01", b"\x1f", b"\x7f",
          "\u00e9".encode(), "\u20ac".encode(), "\U0001f600".encode()]
KEYS = [b"a", b"b", "\u00e9".encode()]
LEXEMES = ["0", "-0", "7", "-12", "3.25", "1e5", "-2.5E-3",
           "123456789012345678901234567890", "0.10", "1E+40"]


def gstr(ps, n, s):
    out = b""
    for _ in range(n):
        s = lcg(s)
        out += ps[draw(s) % len(ps)]
    return out, s


def value(dep, s):
    # (python value, seed after)
    s = lcg(s)
    r = draw(s)
    c = r % (4 if dep >= 3 else 6)
    q = r >> 4
    if c == 0:
        return None, s
    if c == 1:
        return (q & 1) == 1, s
    if c == 2:
        return Raw(LEXEMES[q % 10]), s
    if c == 3:
        b, s = gstr(PIECES, q % 6, s)
        return b.decode(), s
    if c == 4:
        xs = []
        for _ in range(q % 4):
            x, s = value(dep + 1, s)
            xs.append(x)
        return xs, s
    kvs = []
    for _ in range(q % 4):
        s = lcg(s)
        kb, s = gstr(KEYS, draw(s) % 3, s)
        x, s = value(dep + 1, s)
        kvs.append((kb.decode(), x))
    return Obj(kvs), s


def fnv(b):
    # String.hash: FNV-1a over four little-endian bytes per Char, here one byte
    h = 2166136261
    for c in b:
        for byte in (c, 0, 0, 0):
            h = ((h ^ byte) * 16777619) & M32
    return h


RT = 300
acc = 0
for i in range(RT):
    v, _ = value(0, (i * 7919 + 1) & M32)
    t = canon(v).encode()
    back = load(t.decode())
    assert canon(back).encode() == t
    if i < 5:
        want.append("rt %d %s" % (i, vis(t)))
    acc = (acc * 31 + fnv(t)) & M32
rows.append("roundtrip(%dn)" % RT)
want.append("rt law %d/%d hash %d" % (RT, RT, acc))

print(
    """# JsonValue against CPython (json_value_gen.py prints this file). A corpus
# row is a document and what parse makes of it: `ok` and the canonical text of
# the tree, or `err`; a row tagged with a kind is where RFC 8259 leaves the
# choice to the parser and this one's is pinned. Then the limits (depth, budget,
# duplicate keys), the readers (get, at, to_f64, to_i64), and the round-trip
# law over 300 seeded values. Every byte past printable ascii prints as \\xHH.
import Base
import ../../power/json_value.bend as JV

def hx(+d: U32) -> String:
  Bytes.slice("0123456789abcdef", U32.to_nat(d), 1n)

def vis.c(+c: U32) -> String:
  Bool.pick(String, U32.is_ge(c, 32) && U32.is_lt(c, 127), SCon{Chr{c}, SNil{}},
    "\\\\x" ++ hx(U32.shrn(c, 4n)) ++ hx(U32.and(c, 15)))

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
  ["a", "Z", " ", "\\"", "\\\\", "/", "\\n", "\\u{1}", "\\u{1f}", "\\u{7f}", "\\u{c3}\\u{a9}",
   "\\u{e2}\\u{82}\\u{ac}", "\\u{f0}\\u{9f}\\u{98}\\u{80}"]

def keys() -> List<&2, Bytes()>:
  ["a", "b", "\\u{c3}\\u{a9}"]

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
      String.join(List.reverse(&2, String, shown), "\\n") ++ "\\nrt law " ++ Nat.show(ok) ++
        "/" ++ Nat.show(n) ++ " hash " ++ U32.show(h)

def roundtrip(+n: Nat) -> String:
  rt.out(n, rt.go(n, 0n, Rt{0n, 0, []}))

def main() -> IO(Unit):
  do IO<Unit>:"""
)
for r in rows:
    print("    IO.print(%s)" % r)
for w in want:
    print("#|" + w)
