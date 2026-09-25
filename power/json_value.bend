# JsonValue: JSON as a value, over json.bend's event stream. parse builds the
# tree the tokenizer's events describe; show writes one back in canonical form;
# get and at read into it. The tree holds Base's Bytes() -- a number is its
# lexeme and a string with no escape in it is its span, both views of the
# input, so a parse copies only the strings it has to unescape.
#
#   type Json is Data:
#     Null{} | Flag{b: Bool} | Num{text: Bytes()} | Str{s: Bytes()}
#     Arr{xs: List<&2, Json>} | Obj{kvs: List<&2, Sigma<&2, &2, Bytes(), _ => Json>>}
#
# The number keeps its exact text (1e400, 0.10 and -0 stay what they were
# written as); to_f64 and to_i64 read it when asked. A string is its UTF-8
# bytes with the escapes applied: \u00e9 is the two bytes C3 A9, a surrogate
# pair is one four-byte sequence.
#
# parse(b, lim) answers Done{json} or Fail{why}. The limits, all enforced:
#   depth   no more than this many containers open at once (the tokenizer's own
#           ceiling, 256, holds above it); refused as TooDeep at the bracket
#   budget  the tokenizer's byte allowance (json.bend's header): a value it
#           cannot afford is refused as Budget, never scanned to the end
#   dups    Keep: an object keeps every pair in document order and get answers
#           the last one, which is what CPython's dict holds; Refuse: a key an
#           object already has is refused as DupKey at that key
# RFC 8259 leaves three things to the parser, and this one decides them: the
# text must be UTF-8 (section 8.1), so a string byte sequence that is not is
# refused as BadUtf8; an escaped lone surrogate names no character, so it is
# refused as Lone at its backslash (CPython accepts it into a str it then
# cannot encode); a BOM is not whitespace, so it is refused like any other
# byte that starts no value (as CPython does).
#
# show(j) is the canonical text: no whitespace, members in their order, the
# number's own lexeme, a string's bytes as they are except `"` and `\` and the
# controls below 0x20 -- \b \f \n \r \t by name, the rest \u00XX in lower case.
# That is CPython's json.dumps(ensure_ascii=False, separators=(",", ":")) for
# every string, byte for byte.
#
# The laws (tests/power/json_value.bend pins each on every lane):
#   round trip  parse(show(j)) == Done{j} for every j whose strings are UTF-8
#               and whose numbers are JSON numbers, and show(parse(t)) is t
#               for every canonical t -- held over a seeded corpus built in Bend
#               and CPython's canonical form of every accepted document
#   refusal     every n_ vector of the corpus is refused, every y_ accepted,
#               and the accepted tree is CPython's (as its canonical text)
#   limits      nesting k under a cap d parses iff k <= d; a document parses
#               under a budget of its own length, and a value longer than the
#               budget is refused as Budget
# and closed instances of each are stated here as laws the checker computes.
import Base
import ./json.bend as J

type Json is Data:
  Null{}
  Flag{b: Bool}
  Num{text: Bytes()}
  Str{s: Bytes()}
  Arr{xs: List<&2, Json>}
  Obj{kvs: List<&2, Sigma<&2, &2, Bytes(), _ => Json>>}

type Dups is Data:
  Keep{}
  Refuse{}

type Lim is Data:
  Lim{depth: U32, budget: U32, dups: Dups}

type Why is Data:
  Syntax{at: U32, why: J.Error}   # the tokenizer's refusal: char cut esc digit ctrl
  TooDeep{at: U32}
  Budget{at: U32}
  DupKey{at: U32}
  BadUtf8{at: U32}
  Lone{at: U32}

def Out() -> Data:
  Result<&2, &2, Why, Json>

# 64 deep, the whole input, duplicates kept
def lim(+budget: U32) -> Lim:
  Lim{64, budget, Keep{}}

# -- strings: unescape and validate -------------------------------------------

# the one-byte buffer holding the low eight bits of x
def one(x: U32) -> Bytes():
  SCon{Chr{U32.and(x, 255)}, SNil{}}

# The decoder is one byte machine: the tokenizer has already checked the
# escapes' spelling, so what is left is what the bytes mean -- the escape's
# character, a surrogate pair's code point, and whether raw bytes are UTF-8.
type Dm is Data:
  MN{}                                    # between characters
  ME{}                                    # after a backslash
  MU{k: U32, v: U32, hi: U32, e: U32}     # k hex digits of \u read; hi a pending high half
  MH{hi: U32, e: U32}                     # a high half read: a \ must come
  MHE{hi: U32, e: U32}                    # a high half and a \: a u must come
  MC{need: U32, lo: U32, hi: U32}         # need continuation bytes, the next in [lo, hi]
  MX{f: Why}                             # refused; the rest is read and ignored

type Dx is Data:
  Dx{out: Bytes(), m: Dm}

def emit(+copy: Bool, out: Bytes(), c: U32) -> Bytes():
  match copy:
    case True{}:
      Bytes.append(out, one(c))
    case False{}:
      out

def cont(+cp: U32, s: Nat) -> U32:
  U32.or(128, U32.and(U32.shrn(cp, s), 63))

def utf8.4(+copy: Bool, out: Bytes(), +cp: U32, four: Bool) -> Bytes():
  match four:
    case False{}:
      emit(copy, emit(copy, emit(copy, out, U32.or(224, U32.shrn(cp, 12n))), cont(cp, 6n)), cont(cp, 0n))
    case True{}:
      emit(copy, emit(copy, emit(copy, emit(copy, out, U32.or(240, U32.shrn(cp, 18n))), cont(cp, 12n)), cont(cp, 6n)), cont(cp, 0n))

def utf8.2(+copy: Bool, out: Bytes(), +cp: U32, two: Bool) -> Bytes():
  match two:
    case True{}:
      emit(copy, emit(copy, out, U32.or(192, U32.shrn(cp, 6n))), cont(cp, 0n))
    case False{}:
      utf8.4(copy, out, cp, U32.is_ge(cp, 65536))

# a code point as its UTF-8 bytes
def utf8.1(+copy: Bool, out: Bytes(), +cp: U32, small: Bool) -> Bytes():
  match small:
    case True{}:
      emit(copy, out, cp)
    case False{}:
      utf8.2(copy, out, cp, U32.is_lt(cp, 2048))

def utf8(+copy: Bool, out: Bytes(), +cp: U32) -> Bytes():
  utf8.1(copy, out, cp, U32.is_lt(cp, 128))

def is_high(+v: U32) -> Bool:
  U32.is_ge(v, 55296) && U32.is_lt(v, 56320)

def is_low(+v: U32) -> Bool:
  U32.is_ge(v, 56320) && U32.is_lt(v, 57344)

def hexval(+c: U32) -> U32:
  Bool.pick(U32, U32.is_le(c, 57), U32.sub(c, 48), U32.sub(U32.or(c, 32), 87))

# the byte a one-character escape stands for: " \ / b f n r t
def unesc(+c: U32) -> U32:
  Bool.pick(U32, U32.is_eq(c, 98), 8, Bool.pick(U32, U32.is_eq(c, 102), 12,
    Bool.pick(U32, U32.is_eq(c, 110), 10, Bool.pick(U32, U32.is_eq(c, 114), 13,
      Bool.pick(U32, U32.is_eq(c, 116), 9, c)))))

# a lead byte: how many continuation bytes follow and the range of the first;
# 0 continuation bytes past an ASCII lead means the byte leads nothing
type Ld is Data:
  LBad{}
  LOk{need: U32, lo: U32, hi: U32}

def lead(+c: U32) -> Ld:
  Bool.pick(Ld, U32.is_lt(c, 194), LBad{},
  Bool.pick(Ld, U32.is_lt(c, 224), LOk{1, 128, 191},
  Bool.pick(Ld, U32.is_eq(c, 224), LOk{2, 160, 191},
  Bool.pick(Ld, U32.is_eq(c, 237), LOk{2, 128, 159},
  Bool.pick(Ld, U32.is_lt(c, 240), LOk{2, 128, 191},
  Bool.pick(Ld, U32.is_eq(c, 240), LOk{3, 144, 191},
  Bool.pick(Ld, U32.is_lt(c, 244), LOk{3, 128, 191},
  Bool.pick(Ld, U32.is_eq(c, 244), LOk{3, 128, 143}, LBad{}))))))))

def dx.lead(+copy: Bool, +i: U32, +c: U32, out: Bytes(), l: Ld) -> Dx:
  match l:
    case LBad{}:
      Dx{out, MX{BadUtf8{i}}}
    case LOk{need, lo, hi}:
      Dx{emit(copy, out, c), MC{need, lo, hi}}

def dx.raw(+copy: Bool, +i: U32, +c: U32, out: Bytes(), ascii: Bool) -> Dx:
  match ascii:
    case True{}:
      Dx{emit(copy, out, c), MN{}}
    case False{}:
      dx.lead(copy, i, c, out, lead(c))

def dx.n(+copy: Bool, +i: U32, +c: U32, out: Bytes(), bs: Bool) -> Dx:
  match bs:
    case True{}:
      Dx{out, ME{}}
    case False{}:
      dx.raw(copy, i, c, out, U32.is_lt(c, 128))

def dx.e(+copy: Bool, +i: U32, +c: U32, out: Bytes(), u: Bool) -> Dx:
  match u:
    case True{}:
      Dx{out, MU{0, 0, 0, U32.sub(i, 1)}}
    case False{}:
      Dx{emit(copy, out, unesc(c)), MN{}}

# the pair's code point: 0x10000 + (hi - 0xD800) * 0x400 + (lo - 0xDC00)
def pair(+hi: U32, +lo: U32) -> U32:
  U32.add(65536, U32.add(U32.shln(U32.sub(hi, 55296), 10n), U32.sub(lo, 56320)))

def dx.second(+copy: Bool, out: Bytes(), +v: U32, +hi: U32, +e: U32, low: Bool) -> Dx:
  match low:
    case True{}:
      Dx{utf8(copy, out, pair(hi, v)), MN{}}
    case False{}:
      Dx{out, MX{Lone{e}}}

def dx.bmp(+copy: Bool, out: Bytes(), +v: U32, +e: U32, low: Bool) -> Dx:
  match low:
    case True{}:
      Dx{out, MX{Lone{e}}}
    case False{}:
      Dx{utf8(copy, out, v), MN{}}

def dx.first(+copy: Bool, out: Bytes(), +v: U32, +e: U32, high: Bool) -> Dx:
  match high:
    case True{}:
      Dx{out, MH{v, e}}
    case False{}:
      dx.bmp(copy, out, v, e, is_low(v))

def dx.cp(+copy: Bool, out: Bytes(), +v: U32, +hi: U32, +e: U32, first: Bool) -> Dx:
  match first:
    case True{}:
      dx.first(copy, out, v, e, is_high(v))
    case False{}:
      dx.second(copy, out, v, hi, e, is_low(v))

def dx.u(+copy: Bool, out: Bytes(), +k: U32, +v: U32, +hi: U32, +e: U32, done: Bool) -> Dx:
  match done:
    case True{}:
      dx.cp(copy, out, v, hi, e, U32.is_zero(hi))
    case False{}:
      Dx{out, MU{k, v, hi, e}}

def dx.cont(+i: U32, out: Bytes(), +copy: Bool, +c: U32, +need: U32, ok: Bool) -> Dx:
  match ok:
    case True{}:
      Dx{emit(copy, out, c), Bool.pick(Dm, U32.is_eq(need, 1), MN{}, MC{U32.sub(need, 1), 128, 191})}
    case False{}:
      Dx{out, MX{BadUtf8{i}}}

def dx.step(+copy: Bool, +i: U32, +c: U32, x: Dx) -> Dx:
  match x:
    case Dx{out, m}:
      match m:
        case MN{}:
          dx.n(copy, i, c, out, U32.is_eq(c, 92))
        case ME{}:
          dx.e(copy, i, c, out, U32.is_eq(c, 117))
        case MU{+k, +v, hi, e}:
          dx.u(copy, out, U32.inc(k), U32.add(U32.shln(v, 4n), hexval(c)), hi, e, U32.is_eq(k, 3))
        case MH{hi, +e}:
          Dx{out, Bool.pick(Dm, U32.is_eq(c, 92), MHE{hi, e}, MX{Lone{e}})}
        case MHE{hi, +e}:
          Dx{out, Bool.pick(Dm, U32.is_eq(c, 117), MU{0, 0, hi, e}, MX{Lone{e}})}
        case MC{need, +lo, +hi}:
          dx.cont(i, out, copy, c, need, U32.is_ge(c, lo) && U32.is_le(c, hi))
        case MX{f}:
          Dx{out, MX{f}}

# the string leads, so the loop is structural: no fuel
def dx.go(s: Bytes(), +copy: Bool, +i: U32, x: Dx) -> Dx:
  match s:
    case SNil{}:
      x
    case SCon{Chr{c}, t}:
      dx.go(t, copy, U32.inc(i), dx.step(copy, i, c, x))

def dx.end(+end: U32, x: Dx) -> Result<&2, &2, Why, Bytes()>:
  match x:
    case Dx{out, m}:
      match m:
        case MN{}:
          Done{out}
        case MX{f}:
          Fail{f}
        case MH{hi, e}:
          Fail{Lone{e}}
        case MC{need, lo, hi}:
          Fail{BadUtf8{end}}
        case _:
          Fail{Syntax{end, J.Esc{}}}

# a string with no backslash is its own span once its bytes are known to be
# UTF-8: the check writes nothing, and the answer is the view
def dx.keep(span: Bytes(), r: Result<&2, &2, Why, Bytes()>) -> Result<&2, &2, Why, Bytes()>:
  match r:
    case Done{out}:
      Done{span}
    case Fail{f}:
      Fail{f}

def dx.pick(+span: Bytes(), +o: U32, +end: U32, esc: Bool) -> Result<&2, &2, Why, Bytes()>:
  match esc:
    case True{}:
      dx.end(end, dx.go(span, True{}, o, Dx{"", MN{}}))
    case False{}:
      dx.keep(span, dx.end(end, dx.go(span, False{}, o, Dx{"", MN{}})))

def has_bs(m: Maybe<&2, Nat>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{k}:
      True{}

# the bytes a string span means: at is the offset of its first byte in the
# document, so a refusal points into the document
def decode.span(+span: Bytes(), +o: U32) -> Result<&2, &2, Why, Bytes()>:
  dx.pick(span, o, U32.add(o, U32.from_nat(Bytes.len(span))), has_bs(Bytes.find(span, "\\")))

def decode(+b: Bytes(), +o: U32, +len: U32) -> Result<&2, &2, Why, Bytes()>:
  decode.span(Bytes.slice(b, U32.to_nat(o), U32.to_nat(len)), o)

# -- parse --------------------------------------------------------------------

# an open container: an array's items so far, reversed; an object's pairs so
# far, reversed, and the key its next value belongs to
type Fr is Data:
  FA{xs: List<&2, Json>}
  FO{kvs: List<&2, Sigma<&2, &2, Bytes(), _ => Json>>, k: Bytes()}

type Ps is Data:
  Run{}
  Top{v: Json}
  End{r: Out()}

type P is Type:
  P{s: J.St, stk: List<&2, Fr>, d: U32, ps: Ps}

def rev.a(xs: List<&2, Json>, acc: List<&2, Json>) -> List<&2, Json>:
  match xs:
    case Nil{}:
      acc
    case Con{h, t}:
      rev.a(t, Con{h, acc})

def rev.o(xs: List<&2, Sigma<&2, &2, Bytes(), _ => Json>>, acc: List<&2, Sigma<&2, &2, Bytes(), _ => Json>>) -> List<&2, Sigma<&2, &2, Bytes(), _ => Json>>:
  match xs:
    case Nil{}:
      acc
    case Con{h, t}:
      rev.o(t, Con{h, acc})

# a finished value lands in the container it was inside, or is the document
def land(s: J.St, stk: List<&2, Fr>, +d: U32, v: Json) -> P:
  match stk:
    case Nil{}:
      P{s, Nil{}, d, Top{v}}
    case Con{f, up}:
      match f:
        case FA{xs}:
          P{s, Con{FA{Con{v, xs}}, up}, d, Run{}}
        case FO{kvs, k}:
          P{s, Con{FO{Con{(k, v), kvs}, ""}, up}, d, Run{}}

def fail(s: J.St, stk: List<&2, Fr>, +d: U32, f: Why) -> P:
  P{s, stk, d, End{Fail{f}}}

def refuse(+o: U32, why: J.Error) -> Why:
  match why:
    case J.Deep{}:
      TooDeep{o}
    case J.Dry{}:
      Budget{o}
    case _:
      Syntax{o, why}

def has_key(+k: Bytes(), kvs: List<&2, Sigma<&2, &2, Bytes(), _ => Json>>) -> Bool:
  match kvs:
    case Nil{}:
      False{}
    case Con{h, t}:
      match h:
        case Tuple{x, v}:
          String.eq(x, k) || has_key(k, t)

def is_dup(dups: Dups, +k: Bytes(), stk: List<&2, Fr>) -> Bool:
  match dups:
    case Keep{}:
      False{}
    case Refuse{}:
      match stk:
        case Nil{}:
          False{}
        case Con{f, up}:
          match f:
            case FA{xs}:
              False{}
            case FO{kvs, k0}:
              has_key(k, kvs)

def key.set(stk: List<&2, Fr>, k: Bytes()) -> List<&2, Fr>:
  match stk:
    case Nil{}:
      Nil{}
    case Con{f, up}:
      match f:
        case FA{xs}:
          Con{FA{xs}, up}
        case FO{kvs, k0}:
          Con{FO{kvs, k}, up}

def key.put(s: J.St, stk: List<&2, Fr>, +d: U32, +o: U32, +k: Bytes(), dup: Bool) -> P:
  match dup:
    case True{}:
      fail(s, stk, d, DupKey{o})
    case False{}:
      P{s, key.set(stk, k), d, Run{}}

def field(s: J.St, stk: List<&2, Fr>, +d: U32, dups: Dups, +o: U32, r: Result<&2, &2, Why, Bytes()>) -> P:
  match r:
    case Fail{f}:
      fail(s, stk, d, f)
    case Done{+k}:
      +stk = stk
      key.put(s, stk, d, U32.sub(o, 1), k, is_dup(dups, k, stk))

def str(s: J.St, stk: List<&2, Fr>, +d: U32, r: Result<&2, &2, Why, Bytes()>) -> P:
  match r:
    case Fail{f}:
      fail(s, stk, d, f)
    case Done{v}:
      land(s, stk, d, Str{v})

def shut.a(s: J.St, stk: List<&2, Fr>, +d: U32) -> P:
  match stk:
    case Nil{}:
      fail(s, Nil{}, d, Syntax{0, J.Char{}})
    case Con{f, up}:
      match f:
        case FA{xs}:
          land(s, up, U32.sub(d, 1), Arr{rev.a(xs, Nil{})})
        case FO{kvs, k}:
          fail(s, Con{FO{kvs, k}, up}, d, Syntax{0, J.Char{}})

def shut.o(s: J.St, stk: List<&2, Fr>, +d: U32) -> P:
  match stk:
    case Nil{}:
      fail(s, Nil{}, d, Syntax{0, J.Char{}})
    case Con{f, up}:
      match f:
        case FO{kvs, k}:
          land(s, up, U32.sub(d, 1), Obj{rev.o(kvs, Nil{})})
        case FA{xs}:
          fail(s, Con{FA{xs}, up}, d, Syntax{0, J.Char{}})

def open.if(s: J.St, stk: List<&2, Fr>, +d: U32, +o: U32, fr: Fr, deep: Bool) -> P:
  match deep:
    case True{}:
      fail(s, stk, d, TooDeep{o})
    case False{}:
      P{s, Con{fr, stk}, U32.inc(d), Run{}}

def open.at(stk: List<&2, Fr>, +d: U32, +cap: U32, fr: Fr, r: J.St & U32) -> P:
  (s, +o) = r
  open.if(s, stk, d, U32.sub(o, 1), fr, U32.is_ge(d, cap))

def fin(s: J.St, stk: List<&2, Fr>, +d: U32, ps: Ps) -> P:
  match ps:
    case Top{v}:
      P{s, stk, d, End{Done{v}}}
    case _:
      fail(s, stk, d, Syntax{0, J.Cut{}})

# one event into the tree
def event(+b: Bytes(), +l: Lim, s: J.St, stk: List<&2, Fr>, +d: U32, ps: Ps, e: J.Event) -> P:
  match l:
    case Lim{cap, budget, dups}:
      match e:
        case J.ObjOpen{}:
          open.at(stk, d, cap, FO{Nil{}, ""}, J.cursor(s))
        case J.ArrOpen{}:
          open.at(stk, d, cap, FA{Nil{}}, J.cursor(s))
        case J.ObjEnd{}:
          shut.o(s, stk, d)
        case J.ArrEnd{}:
          shut.a(s, stk, d)
        case J.Field{+o, +len}:
          field(s, stk, d, dups, o, decode(b, o, len))
        case J.Str{+o, +len}:
          str(s, stk, d, decode(b, o, len))
        case J.Num{+o, +len}:
          land(s, stk, d, Num{Bytes.slice(b, U32.to_nat(o), U32.to_nat(len))})
        case J.Flag{v}:
          land(s, stk, d, Flag{v})
        case J.Null{}:
          land(s, stk, d, Null{})
        case J.Eof{}:
          fin(s, stk, d, ps)
        case J.Bad{+o, why}:
          fail(s, stk, d, refuse(o, why))

def step.r(+b: Bytes(), +l: Lim, stk: List<&2, Fr>, +d: U32, ps: Ps, r: J.St & J.Event) -> P:
  (s, e) = r
  event(b, l, s, stk, d, ps, e)

def go(fuel: Nat, +b: Bytes(), +l: Lim, p: P) -> P:
  match fuel:
    case 0n:
      p
    case 1n++f:
      match p:
        case P{s, stk, +d, ps}:
          match ps:
            case End{r}:
              P{s, stk, d, End{r}}
            case Run{}:
              go(f, b, l, step.r(b, l, stk, d, Run{}, J.next(s)))
            case Top{v}:
              go(f, b, l, step.r(b, l, stk, d, Top{v}, J.next(s)))

def result(p: P) -> Out():
  match p:
    case P{s, stk, d, ps}:
      match ps:
        case End{r}:
          r
        case _:
          Fail{Syntax{0, J.Cut{}}}

def parse.l(+b: Bytes(), +l: Lim, budget: U32) -> Out():
  +n = Bytes.len(b)
  result(go(Nat.add(Nat.mul(n, 2n), 4n), b, l, P{J.start(b, budget), Nil{}, 0, Run{}}))

# the document's value, or why it is not one
def parse(+b: Bytes(), +l: Lim) -> Out():
  match l:
    case Lim{c, +budget, u}:
      parse.l(b, Lim{c, budget, u}, budget)

def is_ok(r: Out()) -> Bool:
  match r:
    case Done{v}:
      True{}
    case Fail{f}:
      False{}

# -- show ---------------------------------------------------------------------

def hexd(+d: U32) -> Bytes():
  Bytes.slice("0123456789abcdef", U32.to_nat(d), 1n)

# the escape a byte needs in a string, or None: `"` and `\` and the controls
def esc.text(+c: U32) -> Bytes():
  Bool.pick(Bytes(), U32.is_eq(c, 34), "\\\"",
  Bool.pick(Bytes(), U32.is_eq(c, 92), "\\\\",
  Bool.pick(Bytes(), U32.is_eq(c, 8), "\\b",
  Bool.pick(Bytes(), U32.is_eq(c, 12), "\\f",
  Bool.pick(Bytes(), U32.is_eq(c, 10), "\\n",
  Bool.pick(Bytes(), U32.is_eq(c, 13), "\\r",
  Bool.pick(Bytes(), U32.is_eq(c, 9), "\\t",
    Bytes.concat(["\\u00", hexd(U32.shrn(c, 4n)), hexd(U32.and(c, 15))]))))))))

type Es is Data:
  Es{out: Bytes(), run: U32}

def esc.step(+src: Bytes(), +i: U32, +c: U32, need: Bool, e: Es) -> Es:
  match need:
    case False{}:
      e
    case True{}:
      match e:
        case Es{out, +run}:
          Es{Bytes.concat([out, Bytes.slice(src, U32.to_nat(run), U32.to_nat(U32.sub(i, run))), esc.text(c)]), U32.inc(i)}

# the string leads: a run of bytes that need nothing is copied as one slice
def esc.go(s: Bytes(), +src: Bytes(), +i: U32, e: Es) -> Es:
  match s:
    case SNil{}:
      e
    case SCon{Chr{+c}, t}:
      esc.go(t, src, U32.inc(i), esc.step(src, i, c, U32.is_lt(c, 32) || U32.is_eq(c, 34) || U32.is_eq(c, 92), e))

def esc.fin(+src: Bytes(), e: Es) -> Bytes():
  match e:
    case Es{out, +run}:
      Bytes.concat([out, Bytes.drop(src, U32.to_nat(run)), "\""])

def show.str(out: Bytes(), +s: Bytes()) -> Bytes():
  esc.fin(s, esc.go(s, s, 0, Es{Bytes.append(out, "\""), 0}))

type Sm is Data:
  Whole{}
  Rest{}

def sep(m: Sm, first: Bytes()) -> Bytes():
  match m:
    case Whole{}:
      first
    case Rest{}:
      ","

def shut(m: Sm, empty: Bytes()) -> Bytes():
  match m:
    case Whole{}:
      empty
    case Rest{}:
      ""

# one def for the three shapes a writer walks: a value, and the rest of an
# array or an object after its first member (Rest), so the recursion is on the
# value alone and needs no fuel
def sh(j: Json, m: Sm, out: Bytes()) -> Bytes():
  match j:
    case Null{}:
      Bytes.append(out, "null")
    case Flag{v}:
      Bytes.append(out, Bool.pick(Bytes(), v, "true", "false"))
    case Num{t}:
      Bytes.append(out, t)
    case Str{s}:
      show.str(out, s)
    case Arr{xs}:
      match xs:
        case Nil{}:
          Bytes.append(Bytes.append(out, shut(m, "[")), "]")
        case Con{h, t}:
          sh(Arr{t}, Rest{}, sh(h, Whole{}, Bytes.append(out, sep(m, "["))))
    case Obj{kvs}:
      match kvs:
        case Nil{}:
          Bytes.append(Bytes.append(out, shut(m, "{")), "}")
        case Con{h, t}:
          match h:
            case Tuple{k, v}:
              sh(Obj{t}, Rest{}, sh(v, Whole{}, Bytes.append(show.str(Bytes.append(out, sep(m, "{")), k), ":")))

# the canonical text
def show(j: Json) -> Bytes():
  sh(j, Whole{}, "")

# -- reading it ---------------------------------------------------------------

def get.go(kvs: List<&2, Sigma<&2, &2, Bytes(), _ => Json>>, +key: Bytes(), got: Maybe<&2, Json>) -> Maybe<&2, Json>:
  match kvs:
    case Nil{}:
      got
    case Con{h, t}:
      match h:
        case Tuple{k, v}:
          get.go(t, key, Bool.pick(Maybe<&2, Json>, String.eq(k, key), Some{v}, got))

# an object's value at key -- the last one, if the key repeats; None for a
# missing key or a value that is not an object
def get(j: Json, +key: Bytes()) -> Maybe<&2, Json>:
  match j:
    case Obj{kvs}:
      get.go(kvs, key, None{})
    case _:
      None{}

def at.go(xs: List<&2, Json>, i: Nat) -> Maybe<&2, Json>:
  match xs i:
    case Nil{} _:
      None{}
    case Con{h, t} 0n:
      Some{h}
    case Con{h, t} 1n+p:
      at.go(t, p)

# an array's item at i; None past its end or for a value that is not an array
def at(j: Json, i: Nat) -> Maybe<&2, Json>:
  match j:
    case Arr{xs}:
      at.go(xs, i)
    case _:
      None{}

# structural equality; a number is its lexeme, so 1.0 and 1 differ
def eq(a: Json, b: Json) -> Bool:
  match a:
    case Null{}:
      match b:
        case Null{}:
          True{}
        case _:
          False{}
    case Flag{x}:
      match b:
        case Flag{y}:
          Bool.not(Bool.xor(x, y))
        case _:
          False{}
    case Num{x}:
      match b:
        case Num{y}:
          String.eq(x, y)
        case _:
          False{}
    case Str{x}:
      match b:
        case Str{y}:
          String.eq(x, y)
        case _:
          False{}
    case Arr{xs}:
      match xs:
        case Nil{}:
          match b:
            case Arr{ys}:
              List.is_empty(&2, Json, ys)
            case _:
              False{}
        case Con{h, t}:
          match b:
            case Arr{ys}:
              match ys:
                case Nil{}:
                  False{}
                case Con{g, u}:
                  eq(h, g) && eq(Arr{t}, Arr{u})
            case _:
              False{}
    case Obj{xs}:
      match xs:
        case Nil{}:
          match b:
            case Obj{ys}:
              List.is_empty(&2, Sigma<&2, &2, Bytes(), _ => Json>, ys)
            case _:
              False{}
        case Con{h, t}:
          match h:
            case Tuple{k, v}:
              match b:
                case Obj{ys}:
                  match ys:
                    case Nil{}:
                      False{}
                    case Con{g, u}:
                      match g:
                        case Tuple{k2, v2}:
                          String.eq(k, k2) && eq(v, v2) && eq(Obj{t}, Obj{u})
                case _:
                  False{}

# -- numbers ------------------------------------------------------------------

# the number as the nearest F64 (1e400 is inf); None for a value that is not a
# number
def to_f64(j: Json) -> Maybe<&2, F64>:
  match j:
    case Num{t}:
      F64.read(t)
    case _:
      None{}

def i64.zero() -> I64:
  I64{Word.zero(64n)}

def i64.small(k: Nat) -> I64:
  match k:
    case 0n:
      i64.zero()
    case 1n+p:
      I64.inc(i64.small(p))

def i64.digits(s: Bytes(), acc: I64) -> I64:
  match s:
    case SNil{}:
      acc
    case SCon{Chr{c}, t}:
      i64.digits(t, I64.add(I64.mul(acc, i64.small(10n)), i64.small(U32.to_nat(U32.sub(c, 48)))))

# an integer lexeme: optional minus, then digits only
def is_int(+t: Bytes()) -> Bool:
  Bool.not(has_bs(Bytes.find(t, ".")) || has_bs(Bytes.find(t, "e")) || has_bs(Bytes.find(t, "E")))

# the magnitude fits: fewer than 19 digits, or 19 no greater than the limit's
def fits(+ds: Bytes(), +max: Bytes()) -> Bool:
  +n = Bytes.len(ds)
  Nat.is_lt(n, 19n) || (Nat.is_eq(n, 19n) && Bool.not(String.is_gt(ds, max)))

def i64.fit(+ds: Bytes(), ok: Bool, neg: Bool) -> Maybe<&2, I64>:
  match ok:
    case False{}:
      None{}
    case True{}:
      match neg:
        case True{}:
          Some{I64.neg(i64.digits(ds, i64.zero()))}
        case False{}:
          Some{i64.digits(ds, i64.zero())}

# matched, not Bool.pick: the C runtime sinks the unchosen argument as a Term,
# and an I64 is an unboxed word -- 2^63 - 1, which the path not taken computes
# for -9223372036854775809, faults (POWER.md, dropping an F64 on the C backend)
def i64.sign(+ds: Bytes(), +neg: Bool) -> Maybe<&2, I64>:
  i64.fit(ds, fits(ds, Bool.pick(Bytes(), neg, "9223372036854775808", "9223372036854775807")), neg)

def i64.int(+t: Bytes(), int: Bool) -> Maybe<&2, I64>:
  match int:
    case True{}:
      +neg = Bytes.starts_with(t, "-")
      i64.sign(Bytes.drop(t, Bool.pick(Nat, neg, 1n, 0n)), neg)
    case False{}:
      None{}

# the number as an I64 when its lexeme is an integer in range; None for a
# fraction, an exponent, a magnitude past 2^63 - 1 (2^63 when negative), or a
# value that is not a number. 1.0 and 1e2 are None: the text is the value.
def to_i64(j: Json) -> Maybe<&2, I64>:
  match j:
    case Num{+t}:
      i64.int(t, is_int(t))
    case _:
      None{}

# -- closed laws: instances of the three, computed by the checker -------------

# the canonical text of a parse, or the empty text for a refusal
def text(r: Out()) -> Bytes():
  match r:
    case Done{v}:
      show(v)
    case Fail{w}:
      ""

# round trip: every escape class a string can need, a raw control byte, a
# two- and a four-byte character, a lexeme kept as written, a repeated key
law round_trip:
  {parse(show(Arr{[Str{"q\"b\\c/\n\t\u{1}\u{7f}\u{c3}\u{a9}\u{f0}\u{9f}\u{98}\u{80}"},
    Num{"-1.50e3"}, Obj{[("k", Null{}), ("k", Flag{True{}}), ("", Arr{[]})]}]}), lim(1000)) ==
    Done{Arr{[Str{"q\"b\\c/\n\t\u{1}\u{7f}\u{c3}\u{a9}\u{f0}\u{9f}\u{98}\u{80}"},
    Num{"-1.50e3"}, Obj{[("k", Null{}), ("k", Flag{True{}}), ("", Arr{[]})]}]}} : Out()}

def round_trip():
  {==}

# a canonical text is a fixed point of show . parse, escapes and all
law canonical_fixed:
  {text(parse("{\"a\":[1,-0.5E+2,\"\\u0000\\\"\\\\\"],\"\":{}}", lim(1000))) ==
    "{\"a\":[1,-0.5E+2,\"\\u0000\\\"\\\\\"],\"\":{}}" : Bytes()}

def canonical_fixed():
  {==}

# RFC 8259 negatives: a trailing comma, a leading zero, a raw control byte in
# a string, NaN, two top-level values -- each refused where it stands
law refuses_trailing_comma:
  {parse("[1,]", lim(1000)) == Fail{Syntax{3, J.Char{}}} : Out()}

def refuses_trailing_comma():
  {==}

law refuses_leading_zero:
  {parse("01", lim(1000)) == Fail{Syntax{2, J.Digit{}}} : Out()}

def refuses_leading_zero():
  {==}

law refuses_raw_control:
  {parse("\"a\u{1}\"", lim(1000)) == Fail{Syntax{2, J.Ctrl{}}} : Out()}

def refuses_raw_control():
  {==}

law refuses_nan:
  {parse("NaN", lim(1000)) == Fail{Syntax{0, J.Char{}}} : Out()}

def refuses_nan():
  {==}

law refuses_two_values:
  {parse("1 2", lim(1000)) == Fail{Syntax{2, J.Char{}}} : Out()}

def refuses_two_values():
  {==}

# the choices RFC 8259 leaves: a lone surrogate at its backslash, bytes that
# are not UTF-8 at the first one that cannot continue, a repeated key under
# Refuse at its opening quote
law refuses_lone:
  {parse("[\"\\ud800x\"]", lim(1000)) == Fail{Lone{2}} : Out()}

def refuses_lone():
  {==}

law refuses_overlong:
  {parse("\"\u{c0}\u{80}\"", lim(1000)) == Fail{BadUtf8{1}} : Out()}

def refuses_overlong():
  {==}

law refuses_dup:
  {parse("{\"a\":1,\"a\":2}", Lim{64, 1000, Refuse{}}) == Fail{DupKey{7}} : Out()}

def refuses_dup():
  {==}

# limits: two open under a cap of one is refused at the second bracket; a
# string the budget cannot afford is refused, and the same under its length is not
law depth_cap:
  {parse("[[1]]", Lim{1, 1000, Keep{}}) == Fail{TooDeep{1}} : Out()}

def depth_cap():
  {==}

law budget_short:
  {is_ok(parse("\"abcdef\"", lim(7))) == False{} : Bool}

def budget_short():
  {==}

law budget_own_length:
  {is_ok(parse("\"abcdef\"", lim(8))) == True{} : Bool}

def budget_own_length():
  {==}
