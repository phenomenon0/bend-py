# Json: JSON as an event stream. next() hands back one token per call and a
# span into the caller's own Bytes -- never a tree, never a copy of the
# document. A 200 MB log costs the parser one Bytes and a 256-bit stack, and a
# consumer that wants three fields never materialises the rest.
#
# The state is one value: cursor, depth, a Bitset holding the kind of every open
# container (1 object, 0 array), a Mode, and the budget left. Nothing is global
# and nothing mutates behind the caller's back, which is what makes skip() cheap
# and a forked parse (lane 17) possible at all.
#
# The budget: `limit` is a byte allowance. A value token's scanner is capped at
# what is left, so a hostile 200 MB string met with limit 1000 costs 1000 bytes
# of scanning and comes back Dry -- never a partial answer and never a hang.
# Whitespace and structural bytes spend saturating, so an exhausted budget is
# reported at the next value token rather than mid-brace.
#
# The document is Base's Bytes(), the buffer TCP.recv_buf and File.read_buf
# hand back, so a span is a view of it (raw) and json_value.bend builds a tree
# over the same bytes without copying a number or an unescaped string.
#
# Errors are an event, not a Result: the state owns an affine Bitset, which
# cannot sit inside Result's Data payload. Bad{at, why} is terminal -- every
# later next() returns the same event, so a driver loop needs no flag.
import Base
import ./vec.bend as Vec
import ./bytes.bend as Bytes
import ./bitset.bend as Bitset

type Error is Data:
  Char{}                    # a byte that cannot start or continue what is expected
  Cut{}                     # the input ended inside a value or an open container
  Esc{}                     # a bad \escape, or a \u without four hex digits
  Digit{}                   # a number the grammar rejects: 01, .5, 1., 1e, -
  Ctrl{}                    # a raw byte below 0x20 inside a string
  Deep{}                    # more than 256 containers open at once
  Dry{}                     # the budget ran out

type Event is Data:
  ObjOpen{}
  ObjEnd{}
  ArrOpen{}
  ArrEnd{}
  Field{at: U32, len: U32}  # an object key: the raw span between the quotes
  Str{at: U32, len: U32}    # a string value, escapes not applied
  Num{at: U32, len: U32}    # the lexeme, so 1e400 and 0.10 stay exactly as written
  Flag{v: Bool}
  Null{}
  Eof{}
  Bad{at: U32, why: Error}

type Mode is Data:
  MVal{}                    # a value must come
  MVal0{}                   # a value, or the ] closing an empty array
  MKey{}                    # a key must come
  MKey0{}                   # a key, or the } closing an empty object
  MPost{}                   # after a value inside a container: , ] }
  MDone{}                   # the one top-level value is complete
  MBad{e: Event}            # terminal, holding the event to repeat

type St is Type:
  St{b: Bytes(), at: U32, n: U32, dep: U32, ks: Bitset.Bitset, md: Mode, left: U32}

# every scanner is one self-recursive loop over this: Go keeps stepping, Ok and
# No stop it. The checker forbids mutual recursion outside Base, so an early
# exit has to be a state, not a second def calling back.
type Res is Data:
  Go{}
  Ok{}
  No{why: Error}

type Walk is Type:
  Walk{b: Bytes(), i: U32, r: Res}

type Tok is Data:
  TObj{}
  TObjE{}
  TArr{}
  TArrE{}
  TQuo{}
  TCom{}
  TNum{}
  TTru{}
  TFal{}
  TNul{}
  TEnd{}
  TJunk{}

# -- bytes -------------------------------------------------------------------

# reading past the end gives 0, which starts no json token, so every scanner can
# index without a bounds test of its own
def peek.if(b: Bytes(), +i: U32, ok: Bool) -> Bytes() & U32:
  match ok:
    case True{}:
      Bytes.at(b, i)
    case False{}:
      (b, 0)

def peek(b: Bytes(), +i: U32, +n: U32) -> Bytes() & U32:
  peek.if(b, i, U32.is_lt(i, n))

def ws(+c: U32) -> Bool:
  Bool.or(Bool.or(U32.is_eq(c, 32), U32.is_eq(c, 9)), Bool.or(U32.is_eq(c, 10), U32.is_eq(c, 13)))

def digit(+c: U32) -> Bool:
  Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57))

def is_hex(+c: U32) -> Bool:
  Bool.or(digit(c), Bool.or(Bool.and(U32.is_ge(c, 97), U32.is_le(c, 102)), Bool.and(U32.is_ge(c, 65), U32.is_le(c, 70))))

# the eight escapes that stand for one character: " \ / b f n r t
def simple(+c: U32) -> Bool:
  Bool.or(Bool.or(Bool.or(U32.is_eq(c, 34), U32.is_eq(c, 92)), Bool.or(U32.is_eq(c, 47), U32.is_eq(c, 98))), Bool.or(Bool.or(U32.is_eq(c, 102), U32.is_eq(c, 110)), Bool.or(U32.is_eq(c, 114), U32.is_eq(c, 116))))

# -- whitespace --------------------------------------------------------------

# Look fuses the whitespace skip with the peek its caller would do next: the
# loop stops on the first byte that is not a space and hands that byte back, so
# a step reads its dispatch byte once instead of twice. Past the end the byte
# reads 0, which is not a space and starts no token, so the end needs no test of
# its own here. Both callers -- the step, and the colon after a key -- want
# exactly this pair, and a document with no whitespace in it never allocates a
# second Look.
type Look is Type:
  Look{b: Bytes(), i: U32, c: U32, on: Bool}

def look.if(b: Bytes(), +i: U32, +c: U32, hit: Bool) -> Look:
  match hit:
    case True{}:
      Look{b, U32.inc(i), c, True{}}
    case False{}:
      Look{b, i, c, False{}}

def look.set(+i: U32, r: Bytes() & U32) -> Look:
  (b, +c) = r
  look.if(b, i, c, ws(c))

def look.go(fuel: Nat, +n: U32, l: Look) -> Look:
  match fuel:
    case 0n:
      l
    case 1n++p:
      match l:
        case Look{b, +i, c, on}:
          match on:
            case True{}:
              look.go(p, n, look.set(i, peek(b, i, n)))
            case False{}:
              Look{b, i, c, False{}}

# whitespace is free: it is bounded by the input, so pricing it would only make
# the budget harder to reason about
def look(b: Bytes(), +i: U32, +n: U32) -> Look:
  look.go(U32.to_nat(U32.inc(n)), n, look.set(i, peek(b, i, n)))

# -- strings -----------------------------------------------------------------

type Hex is Type:
  Hex{b: Bytes(), j: U32, ok: Bool}

def hex.if(b: Bytes(), +j: U32, ok: Bool) -> Hex:
  match ok:
    case True{}:
      Hex{b, U32.inc(j), True{}}
    case False{}:
      Hex{b, j, False{}}

# a bad digit does not advance, so \u12x is refused at the x like every other
# scanner refuses the byte it could not use
def hex.set(+j: U32, r: Bytes() & U32) -> Hex:
  (b, c) = r
  hex.if(b, j, is_hex(c))

def hex.go(k: Nat, +n: U32, h: Hex) -> Hex:
  match k:
    case 0n:
      h
    case 1n++p:
      match h:
        case Hex{b, +j, ok}:
          match ok:
            case True{}:
              hex.go(p, n, hex.set(j, peek(b, j, n)))
            case False{}:
              Hex{b, j, False{}}

def hex4.fin(h: Hex) -> Walk:
  match h:
    case Hex{b, +j, ok}:
      match ok:
        case True{}:
          Walk{b, j, Go{}}
        case False{}:
          Walk{b, j, No{Esc{}}}

def hex4(b: Bytes(), +j: U32, +n: U32) -> Walk:
  hex4.fin(hex.go(4n, n, Hex{b, j, True{}}))

def esc.u(b: Bytes(), +j: U32, +n: U32, hit: Bool) -> Walk:
  match hit:
    case True{}:
      hex4(b, U32.inc(j), n)
    case False{}:
      Walk{b, j, No{Esc{}}}

def esc.one(b: Bytes(), +j: U32, +n: U32, +c: U32, plain: Bool) -> Walk:
  match plain:
    case True{}:
      Walk{b, U32.inc(j), Go{}}
    case False{}:
      esc.u(b, j, n, U32.is_eq(c, 117))

def esc.on(+j: U32, +n: U32, r: Bytes() & U32) -> Walk:
  (b, +c) = r
  esc.one(b, j, n, c, simple(c))

def esc.end(b: Bytes(), +j: U32, +n: U32, past: Bool) -> Walk:
  match past:
    case True{}:
      Walk{b, j, No{Cut{}}}
    case False{}:
      esc.on(j, n, Bytes.at(b, j))

def esc(b: Bytes(), +j: U32, +n: U32) -> Walk:
  esc.end(b, j, n, U32.is_ge(j, n))

def str.ctl(b: Bytes(), +i: U32, low: Bool) -> Walk:
  match low:
    case True{}:
      Walk{b, i, No{Ctrl{}}}
    case False{}:
      Walk{b, U32.inc(i), Go{}}

def str.esc(b: Bytes(), +i: U32, +n: U32, +c: U32, hit: Bool) -> Walk:
  match hit:
    case True{}:
      esc(b, U32.inc(i), n)
    case False{}:
      str.ctl(b, i, U32.is_lt(c, 32))

def str.quo(b: Bytes(), +i: U32, +n: U32, +c: U32, hit: Bool) -> Walk:
  match hit:
    case True{}:
      Walk{b, U32.inc(i), Ok{}}
    case False{}:
      str.esc(b, i, n, c, U32.is_eq(c, 92))

def str.on(+i: U32, +n: U32, r: Bytes() & U32) -> Walk:
  (b, +c) = r
  str.quo(b, i, n, c, U32.is_eq(c, 34))

def str.end(b: Bytes(), +i: U32, +n: U32, past: Bool) -> Walk:
  match past:
    case True{}:
      Walk{b, i, No{Cut{}}}
    case False{}:
      str.on(i, n, Bytes.at(b, i))

def str.go(fuel: Nat, +n: U32, w: Walk) -> Walk:
  match fuel:
    case 0n:
      w
    case 1n++p:
      match w:
        case Walk{b, +i, r}:
          match r:
            case Go{}:
              str.go(p, n, str.end(b, i, n, U32.is_ge(i, n)))
            case Ok{}:
              Walk{b, i, Ok{}}
            case No{why}:
              Walk{b, i, No{why}}

# entered on the opening quote; the fuel cap is the budget, so a string longer
# than the caller can afford stops early instead of being read and then refused
def str(b: Bytes(), +at: U32, +n: U32, +left: U32) -> Walk:
  str.go(U32.to_nat(U32.inc(U32.min(left, U32.sub(n, at)))), n, Walk{b, U32.inc(at), Go{}})

# -- numbers -----------------------------------------------------------------

type Dig is Type:
  Dig{b: Bytes(), i: U32, k: U32, on: Bool}

def dig.if(b: Bytes(), +i: U32, +k: U32, hit: Bool) -> Dig:
  match hit:
    case True{}:
      Dig{b, U32.inc(i), U32.inc(k), True{}}
    case False{}:
      Dig{b, i, k, False{}}

def dig.set(+i: U32, +k: U32, r: Bytes() & U32) -> Dig:
  (b, c) = r
  dig.if(b, i, k, digit(c))

def dig.go(fuel: Nat, +n: U32, d: Dig) -> Dig:
  match fuel:
    case 0n:
      d
    case 1n++p:
      match d:
        case Dig{b, +i, k, on}:
          match on:
            case True{}:
              dig.go(p, n, dig.set(i, k, peek(b, i, n)))
            case False{}:
              Dig{b, i, k, False{}}

def digits(b: Bytes(), +i: U32, +n: U32, fuel: Nat) -> Dig:
  dig.go(fuel, n, Dig{b, i, 0, True{}})

# -? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)? -- four straight-line
# steps over one digits loop, which is a third of the code an explicit DFA takes
def num.ok(b: Bytes(), +i: U32, some: Bool) -> Walk:
  match some:
    case True{}:
      Walk{b, i, Ok{}}
    case False{}:
      Walk{b, i, No{Digit{}}}

def num.e3(d: Dig) -> Walk:
  match d:
    case Dig{b, +i, k, on}:
      num.ok(b, i, U32.is_gt(k, 0))

def num.e2(b: Bytes(), +i: U32, +n: U32, +fuel: Nat, sign: Bool) -> Walk:
  match sign:
    case True{}:
      num.e3(digits(b, U32.inc(i), n, fuel))
    case False{}:
      num.e3(digits(b, i, n, fuel))

def num.e1(+i: U32, +n: U32, +fuel: Nat, r: Bytes() & U32) -> Walk:
  (b, +c) = r
  num.e2(b, i, n, fuel, Bool.or(U32.is_eq(c, 43), U32.is_eq(c, 45)))

def num.exp(b: Bytes(), +i: U32, +n: U32, +fuel: Nat, hit: Bool) -> Walk:
  match hit:
    case True{}:
      num.e1(U32.inc(i), n, fuel, peek(b, U32.inc(i), n))
    case False{}:
      Walk{b, i, Ok{}}

def num.eq(+i: U32, +n: U32, +fuel: Nat, r: Bytes() & U32) -> Walk:
  (b, +c) = r
  num.exp(b, i, n, fuel, Bool.or(U32.is_eq(c, 101), U32.is_eq(c, 69)))

def num.f3(b: Bytes(), +i: U32, +n: U32, +fuel: Nat, some: Bool) -> Walk:
  match some:
    case True{}:
      num.eq(i, n, fuel, peek(b, i, n))
    case False{}:
      Walk{b, i, No{Digit{}}}

def num.f2(+n: U32, +fuel: Nat, d: Dig) -> Walk:
  match d:
    case Dig{b, +i, k, on}:
      num.f3(b, i, n, fuel, U32.is_gt(k, 0))

def num.frac(b: Bytes(), +i: U32, +n: U32, +fuel: Nat, hit: Bool) -> Walk:
  match hit:
    case True{}:
      num.f2(n, fuel, digits(b, U32.inc(i), n, fuel))
    case False{}:
      num.eq(i, n, fuel, peek(b, i, n))

def num.dot(+i: U32, +n: U32, +fuel: Nat, r: Bytes() & U32) -> Walk:
  (b, c) = r
  num.frac(b, i, n, fuel, U32.is_eq(c, 46))

def num.i2(b: Bytes(), +i: U32, +n: U32, +fuel: Nat, bad: Bool) -> Walk:
  match bad:
    case True{}:
      Walk{b, i, No{Digit{}}}
    case False{}:
      num.dot(i, n, fuel, peek(b, i, n))

# no digits at all, or a leading 0 that is not the whole integer part
def num.i1(+n: U32, +fuel: Nat, +c1: U32, d: Dig) -> Walk:
  match d:
    case Dig{b, +i, +k, on}:
      num.i2(b, i, n, fuel, Bool.or(U32.is_eq(k, 0), Bool.and(U32.is_eq(c1, 48), U32.is_ne(k, 1))))

def num.s2(+i: U32, +n: U32, +fuel: Nat, r: Bytes() & U32) -> Walk:
  (b, +c) = r
  num.i1(n, fuel, c, digits(b, i, n, fuel))

def num.s1(b: Bytes(), +i: U32, +n: U32, +fuel: Nat, neg: Bool) -> Walk:
  match neg:
    case True{}:
      num.s2(U32.inc(i), n, fuel, peek(b, U32.inc(i), n))
    case False{}:
      num.s2(i, n, fuel, peek(b, i, n))

def num.s0(+i: U32, +n: U32, +fuel: Nat, r: Bytes() & U32) -> Walk:
  (b, c) = r
  num.s1(b, i, n, fuel, U32.is_eq(c, 45))

def num(b: Bytes(), +at: U32, +n: U32, +left: U32) -> Walk:
  num.s0(at, n, U32.to_nat(U32.inc(U32.min(left, U32.sub(n, at)))), peek(b, at, n))

# -- true / false / null -----------------------------------------------------

type Mat is Type:
  Mat{b: Bytes(), i: U32, ok: Bool}

def lit.hit(b: Bytes(), +i: U32, ok: Bool) -> Mat:
  match ok:
    case True{}:
      Mat{b, U32.inc(i), True{}}
    case False{}:
      Mat{b, i, False{}}

# a mismatch does not advance, so `tru` is refused at the byte that is missing
# rather than one past the end of the input
def lit.eq(+i: U32, +x: U32, r: Bytes() & U32) -> Mat:
  (b, c) = r
  lit.hit(b, i, U32.is_eq(c, x))

def lit.one(+n: U32, m: Mat, +x: U32) -> Mat:
  match m:
    case Mat{b, +i, ok}:
      match ok:
        case True{}:
          lit.eq(i, x, peek(b, i, n))
        case False{}:
          Mat{b, i, False{}}

# the shrinking argument has to come before the rebuilt one: every argument left
# of it must be passed unchanged, so the list goes second and the Mat last
def lit.go(+n: U32, want: List<&2, U32>, m: Mat) -> Mat:
  match want:
    case Nil{}:
      m
    case Con{x, t}:
      lit.go(n, t, lit.one(n, m, x))

def lit.res(m: Mat) -> Walk:
  match m:
    case Mat{b, +i, ok}:
      match ok:
        case True{}:
          Walk{b, i, Ok{}}
        case False{}:
          Walk{b, i, No{Char{}}}

def lit(b: Bytes(), +i: U32, +n: U32, want: List<&2, U32>) -> Walk:
  lit.res(lit.go(n, want, Mat{b, i, True{}}))

# -- budget ------------------------------------------------------------------

def spend(+left: U32, +k: U32) -> U32:
  U32.sub(U32.max(left, k), k)

def charge.dry(r: Res) -> Res:
  match r:
    case Ok{}:
      No{Dry{}}
    case Go{}:
      Go{}
    case No{why}:
      No{why}

def charge.if(r: Res, ok: Bool) -> Res:
  match ok:
    case True{}:
      r
    case False{}:
      charge.dry(r)

def charge(r: Res, +left: U32, +used: U32) -> Res:
  charge.if(r, U32.is_ge(left, used))

# a scanner still Go when its fuel ran out either hit the end of the input or
# hit the end of the budget, and the cursor says which
def res.why(past: Bool) -> Res:
  match past:
    case True{}:
      No{Cut{}}
    case False{}:
      No{Dry{}}

def res.fin(r: Res, +i: U32, +n: U32) -> Res:
  match r:
    case Go{}:
      res.why(U32.is_ge(i, n))
    case Ok{}:
      Ok{}
    case No{why}:
      No{why}

# -- the token classifier ----------------------------------------------------

def tok.num(+c: U32, hit: Bool) -> Tok:
  match hit:
    case True{}:
      TNum{}
    case False{}:
      TJunk{}

def tok.nul(+c: U32, hit: Bool) -> Tok:
  match hit:
    case True{}:
      TNul{}
    case False{}:
      tok.num(c, Bool.or(digit(c), U32.is_eq(c, 45)))

def tok.fal(+c: U32, hit: Bool) -> Tok:
  match hit:
    case True{}:
      TFal{}
    case False{}:
      tok.nul(c, U32.is_eq(c, 110))

def tok.tru(+c: U32, hit: Bool) -> Tok:
  match hit:
    case True{}:
      TTru{}
    case False{}:
      tok.fal(c, U32.is_eq(c, 102))

def tok.com(+c: U32, hit: Bool) -> Tok:
  match hit:
    case True{}:
      TCom{}
    case False{}:
      tok.tru(c, U32.is_eq(c, 116))

def tok.quo(+c: U32, hit: Bool) -> Tok:
  match hit:
    case True{}:
      TQuo{}
    case False{}:
      tok.com(c, U32.is_eq(c, 44))

def tok.arre(+c: U32, hit: Bool) -> Tok:
  match hit:
    case True{}:
      TArrE{}
    case False{}:
      tok.quo(c, U32.is_eq(c, 34))

def tok.arr(+c: U32, hit: Bool) -> Tok:
  match hit:
    case True{}:
      TArr{}
    case False{}:
      tok.arre(c, U32.is_eq(c, 93))

def tok.obje(+c: U32, hit: Bool) -> Tok:
  match hit:
    case True{}:
      TObjE{}
    case False{}:
      tok.arr(c, U32.is_eq(c, 91))

def tok(+c: U32) -> Tok:
  tok.obje(c, U32.is_eq(c, 125))

def tok.at(+c: U32, hit: Bool) -> Tok:
  match hit:
    case True{}:
      TObj{}
    case False{}:
      tok(c)

def tok.end(+c: U32, past: Bool) -> Tok:
  match past:
    case True{}:
      TEnd{}
    case False{}:
      tok.at(c, U32.is_eq(c, 123))

# -- the machine -------------------------------------------------------------

type Tick is Type:
  More{s: St}
  Emit{s: St, e: Event}

def err.e(b: Bytes(), +at: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32, +e: Event) -> Tick:
  Emit{St{b, at, n, dep, ks, MBad{e}, left}, e}

def err(b: Bytes(), +at: U32, +n: U32, dep: U32, ks: Bitset.Bitset, left: U32, why: Error) -> Tick:
  err.e(b, at, n, dep, ks, left, Bad{at, why})

def after.if(top: Bool) -> Mode:
  match top:
    case True{}:
      MDone{}
    case False{}:
      MPost{}

def after(+dep: U32) -> Mode:
  after.if(U32.is_zero(dep))

# a value landed: at depth 0 the document is over, inside a container the next
# thing must be a comma or a closer
def land(b: Bytes(), +at: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32, e: Event) -> Tick:
  Emit{St{b, at, n, dep, ks, after(dep), left}, e}

def val.str.r(b: Bytes(), +at: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32, +i: U32, r: Res) -> Tick:
  match r:
    case Ok{}:
      land(b, i, n, dep, ks, spend(left, U32.sub(i, at)), Str{U32.inc(at), U32.sub(U32.sub(i, at), 2)})
    case No{why}:
      err(b, i, n, dep, ks, left, why)
    case Go{}:
      err(b, i, n, dep, ks, left, Cut{})

def val.str.w(+at: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32, w: Walk) -> Tick:
  match w:
    case Walk{b, +i, r}:
      val.str.r(b, at, n, dep, ks, left, i, charge(res.fin(r, i, n), left, U32.sub(i, at)))

def val.str(b: Bytes(), +at: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32) -> Tick:
  val.str.w(at, n, dep, ks, left, str(b, at, n, left))

def val.num.r(b: Bytes(), +at: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32, +i: U32, r: Res) -> Tick:
  match r:
    case Ok{}:
      land(b, i, n, dep, ks, spend(left, U32.sub(i, at)), Num{at, U32.sub(i, at)})
    case No{why}:
      err(b, i, n, dep, ks, left, why)
    case Go{}:
      err(b, i, n, dep, ks, left, Cut{})

def val.num.w(+at: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32, w: Walk) -> Tick:
  match w:
    case Walk{b, +i, r}:
      val.num.r(b, at, n, dep, ks, left, i, charge(res.fin(r, i, n), left, U32.sub(i, at)))

def val.num(b: Bytes(), +at: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32) -> Tick:
  val.num.w(at, n, dep, ks, left, num(b, at, n, left))

def val.lit.r(b: Bytes(), +at: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32, +i: U32, e: Event, r: Res) -> Tick:
  match r:
    case Ok{}:
      land(b, i, n, dep, ks, spend(left, U32.sub(i, at)), e)
    case No{why}:
      err(b, i, n, dep, ks, left, why)
    case Go{}:
      err(b, i, n, dep, ks, left, Cut{})

def val.lit.w(+at: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32, e: Event, w: Walk) -> Tick:
  match w:
    case Walk{b, +i, r}:
      val.lit.r(b, at, n, dep, ks, left, i, e, charge(res.fin(r, i, n), left, U32.sub(i, at)))

def val.lit(b: Bytes(), +at: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32, e: Event, want: List<&2, U32>) -> Tick:
  val.lit.w(at, n, dep, ks, left, e, lit(b, U32.inc(at), n, want))

def push.ok(b: Bytes(), +at: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32, md: Mode, e: Event) -> Tick:
  Emit{St{b, U32.inc(at), n, U32.inc(dep), ks, md, spend(left, 1)}, e}

def val.obj(b: Bytes(), +at: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32, deep: Bool) -> Tick:
  match deep:
    case True{}:
      err(b, at, n, dep, ks, left, Deep{})
    case False{}:
      push.ok(b, at, n, dep, Bitset.set(ks, dep), left, MKey0{}, ObjOpen{})

def val.arr(b: Bytes(), +at: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32, deep: Bool) -> Tick:
  match deep:
    case True{}:
      err(b, at, n, dep, ks, left, Deep{})
    case False{}:
      push.ok(b, at, n, dep, Bitset.clear(ks, dep), left, MVal0{}, ArrOpen{})

# a closer pops before it is checked, so `dep` here is already the new depth
def pop.arr.if(b: Bytes(), +at: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32, isobj: Bool) -> Tick:
  match isobj:
    case True{}:
      err(b, at, n, dep, ks, left, Char{})
    case False{}:
      land(b, U32.inc(at), n, dep, ks, spend(left, 1), ArrEnd{})

def pop.arr(b: Bytes(), +at: U32, +n: U32, +dep: U32, +left: U32, r: Bitset.Bitset & Bool) -> Tick:
  (ks, isobj) = r
  pop.arr.if(b, at, n, dep, ks, left, isobj)

def pop.obj.if(b: Bytes(), +at: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32, isobj: Bool) -> Tick:
  match isobj:
    case True{}:
      land(b, U32.inc(at), n, dep, ks, spend(left, 1), ObjEnd{})
    case False{}:
      err(b, at, n, dep, ks, left, Char{})

def pop.obj(b: Bytes(), +at: U32, +n: U32, +dep: U32, +left: U32, r: Bitset.Bitset & Bool) -> Tick:
  (ks, isobj) = r
  pop.obj.if(b, at, n, dep, ks, left, isobj)

def shut.arr(b: Bytes(), +at: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32, ok: Bool) -> Tick:
  match ok:
    case True{}:
      pop.arr(b, at, n, U32.sub(dep, 1), left, Bitset.test(ks, U32.sub(dep, 1)))
    case False{}:
      err(b, at, n, dep, ks, left, Char{})

def shut.obj(b: Bytes(), +at: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32, ok: Bool) -> Tick:
  match ok:
    case True{}:
      pop.obj(b, at, n, U32.sub(dep, 1), left, Bitset.test(ks, U32.sub(dep, 1)))
    case False{}:
      err(b, at, n, dep, ks, left, Char{})

def value(b: Bytes(), +at: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32, shut: Bool, t: Tok) -> Tick:
  match t:
    case TObj{}:
      val.obj(b, at, n, dep, ks, left, U32.is_ge(dep, 256))
    case TArr{}:
      val.arr(b, at, n, dep, ks, left, U32.is_ge(dep, 256))
    case TQuo{}:
      val.str(b, at, n, dep, ks, left)
    case TNum{}:
      val.num(b, at, n, dep, ks, left)
    case TTru{}:
      val.lit(b, at, n, dep, ks, left, Flag{True{}}, [114, 117, 101])
    case TFal{}:
      val.lit(b, at, n, dep, ks, left, Flag{False{}}, [97, 108, 115, 101])
    case TNul{}:
      val.lit(b, at, n, dep, ks, left, Null{}, [117, 108, 108])
    case TArrE{}:
      shut.arr(b, at, n, dep, ks, left, shut)
    case TEnd{}:
      err(b, at, n, dep, ks, left, Cut{})
    case _:
      err(b, at, n, dep, ks, left, Char{})

# a key is one call: the string, the whitespace after it and the colon, so the
# stream has no colon event to ignore
# the colon is the one byte not reached through the token classifier, so this is
# the one place that has to tell "ended here" from "wrong byte here" itself
def key.col.no(b: Bytes(), +j: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32, past: Bool) -> Tick:
  match past:
    case True{}:
      err(b, j, n, dep, ks, left, Cut{})
    case False{}:
      err(b, j, n, dep, ks, left, Char{})

def key.col.if(b: Bytes(), +j: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32, e: Event, hit: Bool) -> Tick:
  match hit:
    case True{}:
      Emit{St{b, U32.inc(j), n, dep, ks, MVal{}, spend(left, 1)}, e}
    case False{}:
      key.col.no(b, j, n, dep, ks, left, U32.is_ge(j, n))

def key.col(+n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32, e: Event, l: Look) -> Tick:
  match l:
    case Look{b, j, c, on}:
      key.col.if(b, j, n, dep, ks, left, e, U32.is_eq(c, 58))

def key.str.r(b: Bytes(), +at: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32, +i: U32, r: Res) -> Tick:
  match r:
    case Ok{}:
      key.col(n, dep, ks, spend(left, U32.sub(i, at)), Field{U32.inc(at), U32.sub(U32.sub(i, at), 2)}, look(b, i, n))
    case No{why}:
      err(b, i, n, dep, ks, left, why)
    case Go{}:
      err(b, i, n, dep, ks, left, Cut{})

def key.str.w(+at: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32, w: Walk) -> Tick:
  match w:
    case Walk{b, +i, r}:
      key.str.r(b, at, n, dep, ks, left, i, charge(res.fin(r, i, n), left, U32.sub(i, at)))

def key.str(b: Bytes(), +at: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32) -> Tick:
  key.str.w(at, n, dep, ks, left, str(b, at, n, left))

def keym(b: Bytes(), +at: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32, shut: Bool, t: Tok) -> Tick:
  match t:
    case TQuo{}:
      key.str(b, at, n, dep, ks, left)
    case TObjE{}:
      shut.obj(b, at, n, dep, ks, left, shut)
    case TEnd{}:
      err(b, at, n, dep, ks, left, Cut{})
    case _:
      err(b, at, n, dep, ks, left, Char{})

def post.com.if(b: Bytes(), +at: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32, isobj: Bool) -> Tick:
  match isobj:
    case True{}:
      More{St{b, U32.inc(at), n, dep, ks, MKey{}, spend(left, 1)}}
    case False{}:
      More{St{b, U32.inc(at), n, dep, ks, MVal{}, spend(left, 1)}}

def post.com(b: Bytes(), +at: U32, +n: U32, +dep: U32, +left: U32, r: Bitset.Bitset & Bool) -> Tick:
  (ks, isobj) = r
  post.com.if(b, at, n, dep, ks, left, isobj)

# a comma emits nothing, so this is the one step that returns More
def post(b: Bytes(), +at: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32, t: Tok) -> Tick:
  match t:
    case TCom{}:
      post.com(b, at, n, dep, left, Bitset.test(ks, U32.sub(dep, 1)))
    case TArrE{}:
      shut.arr(b, at, n, dep, ks, left, True{})
    case TObjE{}:
      shut.obj(b, at, n, dep, ks, left, True{})
    case TEnd{}:
      err(b, at, n, dep, ks, left, Cut{})
    case _:
      err(b, at, n, dep, ks, left, Char{})

def endm(b: Bytes(), +at: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32, t: Tok) -> Tick:
  match t:
    case TEnd{}:
      Emit{St{b, at, n, dep, ks, MDone{}, left}, Eof{}}
    case _:
      err(b, at, n, dep, ks, left, Char{})

def disp(b: Bytes(), +at: U32, +n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32, md: Mode, t: Tok) -> Tick:
  match md:
    case MVal{}:
      value(b, at, n, dep, ks, left, False{}, t)
    case MVal0{}:
      value(b, at, n, dep, ks, left, True{}, t)
    case MKey{}:
      keym(b, at, n, dep, ks, left, False{}, t)
    case MKey0{}:
      keym(b, at, n, dep, ks, left, True{}, t)
    case MPost{}:
      post(b, at, n, dep, ks, left, t)
    case MDone{}:
      endm(b, at, n, dep, ks, left, t)
    case MBad{e}:
      err.e(b, at, n, dep, ks, left, e)

def step.tok(+n: U32, +dep: U32, ks: Bitset.Bitset, +left: U32, md: Mode, l: Look) -> Tick:
  match l:
    case Look{b, +at, c, on}:
      disp(b, at, n, dep, ks, left, md, tok.end(c, U32.is_ge(at, n)))

def step(s: St) -> Tick:
  match s:
    case St{b, at, +n, dep, ks, md, left}:
      step.tok(n, dep, ks, left, md, look(b, at, n))

def next.bad(s: St) -> St & Event:
  match s:
    case St{b, +at, n, dep, ks, md, left}:
      (St{b, at, n, dep, ks, MBad{Bad{at, Char{}}}, left}, Bad{at, Char{}})

def next.out(t: Tick) -> St & Event:
  match t:
    case Emit{s, e}:
      (s, e)
    case More{s}:
      next.bad(s)

def next.go(fuel: Nat, t: Tick) -> Tick:
  match fuel:
    case 0n:
      t
    case 1n++p:
      match t:
        case Emit{s, e}:
          Emit{s, e}
        case More{s}:
          next.go(p, step(s))

# one call is one event; the only step that emits nothing is the comma, so four
# is already two more than the machine can use
def next(s: St) -> St & Event:
  next.out(next.go(4n, More{s}))

# -- the door ----------------------------------------------------------------

def start.n(+limit: U32, r: Bytes() & U32) -> St:
  (b, n) = r
  St{b, 0, n, 0, Bitset.new(8n), MVal{}, limit}

def start(b: Bytes(), +limit: U32) -> St:
  start.n(limit, Bytes.len(b))

def budget.mk(b: Bytes(), at: U32, n: U32, dep: U32, ks: Bitset.Bitset, md: Mode, +left: U32) -> St & U32:
  (St{b, at, n, dep, ks, md, left}, left)

def budget(s: St) -> St & U32:
  match s:
    case St{b, at, n, dep, ks, md, left}:
      budget.mk(b, at, n, dep, ks, md, left)

# the offset the next step starts from: just past the last event's bytes
def cursor(s: St) -> St & U32:
  match s:
    case St{b, +at, n, dep, ks, md, left}:
      (St{b, at, n, dep, ks, md, left}, at)

def depth(s: St) -> St & U32:
  match s:
    case St{b, at, n, +dep, ks, md, left}:
      (St{b, at, n, dep, ks, md, left}, dep)

# hand the input and the unspent budget back; the container stack is dropped
def finish(s: St) -> Bytes() & U32:
  match s:
    case St{b, at, n, dep, ks, md, left}:
      (b, left)

# -- driving it --------------------------------------------------------------

def live(e: Event) -> Bool:
  match e:
    case Eof{}:
      False{}
    case Bad{at, why}:
      False{}
    case _:
      True{}

type Chk is Type:
  Chk{s: St, e: Event, on: Bool}

def check.step(r: St & Event) -> Chk:
  (s, +e) = r
  Chk{s, e, live(e)}

def check.go(fuel: Nat, c: Chk) -> Chk:
  match fuel:
    case 0n:
      c
    case 1n++p:
      match c:
        case Chk{s, e, on}:
          match on:
            case True{}:
              check.go(p, check.step(next(s)))
            case False{}:
              Chk{s, e, False{}}

def check.b(e: Event, r: Bytes() & U32) -> Bytes() & Event:
  (b, l) = r
  (b, e)

def check.out(c: Chk) -> Bytes() & Event:
  match c:
    case Chk{s, e, on}:
      check.b(e, finish(s))

def check.len(+limit: U32, r: Bytes() & U32) -> Bytes() & Event:
  (b, +n) = r
  check.out(check.go(U32.to_nat(U32.add(U32.mul(n, 2), 4)), Chk{start.n(limit, (b, n)), Eof{}, True{}}))

# drive the whole document and hand back the event that ended it: Eof if it is
# valid json under the budget, otherwise the Bad that refused it
def check(b: Bytes(), +limit: U32) -> Bytes() & Event:
  check.len(limit, Bytes.len(b))

type Skp is Type:
  Skp{s: St, e: Event, d: U32, on: Bool}

def skip.d(+d: U32, e: Event) -> U32:
  match e:
    case ObjOpen{}:
      U32.inc(d)
    case ArrOpen{}:
      U32.inc(d)
    case ObjEnd{}:
      U32.sub(d, 1)
    case ArrEnd{}:
      U32.sub(d, 1)
    case _:
      d

def skip.mk(+d: U32, +e: Event, s: St) -> Skp:
  Skp{s, e, d, Bool.and(U32.is_gt(d, 0), live(e))}

def skip.step(d: U32, r: St & Event) -> Skp:
  (s, +e) = r
  skip.mk(skip.d(d, e), e, s)

def skip.go(fuel: Nat, k: Skp) -> Skp:
  match fuel:
    case 0n:
      k
    case 1n++p:
      match k:
        case Skp{s, e, d, on}:
          match on:
            case True{}:
              skip.go(p, skip.step(d, next(s)))
            case False{}:
              Skp{s, e, d, False{}}

def skip.out(k: Skp) -> St & Event:
  match k:
    case Skp{s, e, d, on}:
      (s, e)

def skip.run(fuel: Nat, s: St) -> St & Event:
  skip.out(skip.go(fuel, skip.step(0, next(s))))

# consume the next value whole -- a scalar is one event, a container is all of
# it -- and hand back the event that closed it
def skip(s: St) -> St & Event:
  match s:
    case St{b, at, +n, dep, ks, md, left}:
      skip.run(U32.to_nat(U32.add(U32.mul(n, 2), 4)), St{b, at, n, dep, ks, md, left})

# -- reading a span ----------------------------------------------------------

# the span exactly as it sits in the input: escapes are not applied and
# non-ascii is not decoded, because a span is what the parser promises and
# unescaping is the consumer's choice (json_value.bend makes it). A view of
# the caller's buffer: nothing is copied.
def raw(+b: Bytes(), +at: U32, +len: U32) -> Bytes() & String:
  (b, Bytes.slice(b, at, len))

# -- showing it --------------------------------------------------------------

def reason(e: Error) -> String:
  match e:
    case Char{}:
      "char"
    case Cut{}:
      "cut"
    case Esc{}:
      "esc"
    case Digit{}:
      "digit"
    case Ctrl{}:
      "ctrl"
    case Deep{}:
      "deep"
    case Dry{}:
      "dry"

def span(name: String, at: U32, len: U32) -> String:
  name ++ "@" ++ U32.show(at) ++ "+" ++ U32.show(len)

# json's own spelling, not Bool.show's -- an event stream reads back as the
# document it came from
def show.flag(v: Bool) -> String:
  match v:
    case True{}:
      "true"
    case False{}:
      "false"

def show(e: Event) -> String:
  match e:
    case ObjOpen{}:
      "{"
    case ObjEnd{}:
      "}"
    case ArrOpen{}:
      "["
    case ArrEnd{}:
      "]"
    case Field{at, len}:
      span("key", at, len)
    case Str{at, len}:
      span("str", at, len)
    case Num{at, len}:
      span("num", at, len)
    case Flag{v}:
      show.flag(v)
    case Null{}:
      "null"
    case Eof{}:
      "eof"
    case Bad{at, w}:
      "!" ++ reason(w) ++ "@" ++ U32.show(at)
