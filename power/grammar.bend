# Grammar: a parser state that is a *value*, and the set of next bytes it will
# accept. This is lane 5's state machine with the document taken out of it.
#
# power/json.bend owns its input: its St holds a Bytes, so its kind is Type --
# affine, one owner, and a fork has to hand the buffer to exactly one side. That
# is right for a parser and wrong for constrained decoding, where the whole job
# is to hold a position in a grammar and try many continuations from it.
#
# So the state here is five U32s and a Node tag: kind Data. It copies, it drops,
# it rides inside a Result, and both children of a fork derive their own copy
# from the same parent -- a beam of 64 branches is 64 values off one state, not
# 64 copies of a buffer. Rollback is not an operation: the state you came from
# is still a value you are holding.
#
#   step(s, c)    advance on one byte
#   mask(s)       the 256-bit set of bytes that keep it alive -- also Data
#   allows(s, c)  read that set
#
# and the law the lane exists to pin:
#
#   allows(s, c) == live(step(s, c))    for every byte of every reachable state
#
# A mask that disagrees with the step it is supposed to predict is the whole
# failure mode of constrained decoding: the sampler is told a token is legal,
# emits it, and the parser dies three tokens later with no way back. Here the
# two are separate code paths -- mask reads the node, step runs the transition
# -- and the fixture asserts they agree on all 256 bytes at every state it
# reaches, which is the only reason keeping them separate is safe.
#
# The grammar is JSON, and it is *code*, not a table. In an affine language a
# shared read-only transition table is the expensive thing (one owner, so a fork
# cannot read it twice) and a match on a constructor is the cheap one, which is
# the reverse of the usual table-driven-is-faster intuition. A second grammar is
# more defs, not loaded data.
#
# Nesting is capped at 64 containers, one kind bit each in two U32s, because
# that is what fits in a Data record without an Array. Deeper input is refused,
# not truncated.
import Base
import ./bytes.bend as Bytes

# -- the byte mask -----------------------------------------------------------

# 256 bits as eight U32s: one bit a byte, word c >> 5, bit c & 31. An Array
# would be one field instead of eight and would cost the state its kind.
type Mask is Data:
  Mask{w0: U32, w1: U32, w2: U32, w3: U32, w4: U32, w5: U32, w6: U32, w7: U32}

def bit.get(+w: U32, +i: U32) -> Bool:
  U32.is_eq(U32.and(U32.shrn(w, U32.to_nat(i)), 1), 1)

def bit.set(+w: U32, +i: U32) -> U32:
  U32.or(w, U32.shln(1, U32.to_nat(i)))

def bit.clr(+w: U32, +i: U32) -> U32:
  U32.and(w, U32.not(U32.shln(1, U32.to_nat(i))))

# both arms are already-evaluated U32s, so strictness costs nothing here and
# buys a flat word select instead of eight defs
def sel(a: U32, b: U32, hit: Bool) -> U32:
  match hit:
    case True{}:
      a
    case False{}:
      b

def word.8(a: U32, b: U32, c: U32, d: U32, e: U32, f: U32, g: U32, h: U32, +i: U32) -> U32:
  sel(sel(sel(a, b, U32.is_eq(i, 0)), sel(c, d, U32.is_eq(i, 2)), U32.is_lt(i, 2)),
    sel(sel(e, f, U32.is_eq(i, 4)), sel(g, h, U32.is_eq(i, 6)), U32.is_lt(i, 6)),
    U32.is_lt(i, 4))

def Mask.word(m: Mask, +i: U32) -> U32:
  match m:
    case Mask{a, b, c, d, e, f, g, h}:
      word.8(a, b, c, d, e, f, g, h, i)

def Mask.has(+m: Mask, +c: U32) -> Bool:
  bit.get(Mask.word(m, U32.shrn(c, 5n)), U32.and(c, 31))

def Mask.or.b(a0: U32, a1: U32, a2: U32, a3: U32, a4: U32, a5: U32, a6: U32, a7: U32, b: Mask) -> Mask:
  match b:
    case Mask{b0, b1, b2, b3, b4, b5, b6, b7}:
      Mask{U32.or(a0, b0), U32.or(a1, b1), U32.or(a2, b2), U32.or(a3, b3),
        U32.or(a4, b4), U32.or(a5, b5), U32.or(a6, b6), U32.or(a7, b7)}

def Mask.or(a: Mask, b: Mask) -> Mask:
  match a:
    case Mask{a0, a1, a2, a3, a4, a5, a6, a7}:
      Mask.or.b(a0, a1, a2, a3, a4, a5, a6, a7, b)

# the byte classes as constants, not as a range loop: a mask is read once a step
# and built never
def M.none() -> Mask:
  Mask{0, 0, 0, 0, 0, 0, 0, 0}

def M.ws() -> Mask:
  Mask{9728, 1, 0, 0, 0, 0, 0, 0}

def M.digit() -> Mask:
  Mask{0, 67043328, 0, 0, 0, 0, 0, 0}

def M.hex() -> Mask:
  Mask{0, 67043328, 126, 126, 0, 0, 0, 0}

def M.vstart() -> Mask:
  Mask{0, 67051524, 134217728, 135282752, 0, 0, 0, 0}

def M.escch() -> Mask:
  Mask{0, 32772, 268435456, 3424324, 0, 0, 0, 0}

def M.body() -> Mask:
  Mask{0, 4294967295, 4294967295, 4294967295, 4294967295, 4294967295, 4294967295, 4294967295}

def M.dote() -> Mask:
  Mask{0, 16384, 32, 32, 0, 0, 0, 0}

def M.eonly() -> Mask:
  Mask{0, 0, 32, 32, 0, 0, 0, 0}

def M.sign() -> Mask:
  Mask{0, 10240, 0, 0, 0, 0, 0, 0}

def M.colon() -> Mask:
  Mask{0, 67108864, 0, 0, 0, 0, 0, 0}

def M.comma() -> Mask:
  Mask{0, 4096, 0, 0, 0, 0, 0, 0}

def M.rbrace() -> Mask:
  Mask{0, 0, 0, 536870912, 0, 0, 0, 0}

def M.rbrack() -> Mask:
  Mask{0, 0, 536870912, 0, 0, 0, 0, 0}

def M.quote() -> Mask:
  Mask{0, 4, 0, 0, 0, 0, 0, 0}

def M.c_a() -> Mask:
  Mask{0, 0, 0, 2, 0, 0, 0, 0}

def M.c_e() -> Mask:
  Mask{0, 0, 0, 32, 0, 0, 0, 0}

def M.c_l() -> Mask:
  Mask{0, 0, 0, 4096, 0, 0, 0, 0}

def M.c_r() -> Mask:
  Mask{0, 0, 0, 262144, 0, 0, 0, 0}

def M.c_s() -> Mask:
  Mask{0, 0, 0, 524288, 0, 0, 0, 0}

def M.c_u() -> Mask:
  Mask{0, 0, 0, 2097152, 0, 0, 0, 0}

# -- the state ---------------------------------------------------------------

# one constructor a grammar position. Fin is "a complete top-level value"; the
# four accepting number nodes are complete too, because a number has no closing
# byte and is finished by whatever follows it -- see reduce.
type Node is Data:
  Dead{}
  Val{}
  Vale{}
  Keye{}
  Key{}
  Colon{}
  Sep{}
  Fin{}
  Str{}
  Esc{}
  U1{}
  U2{}
  U3{}
  U4{}
  Min{}
  Zero{}
  Int{}
  Dot{}
  Frac{}
  Exp{}
  Esgn{}
  Expd{}
  Tr{}
  Tu{}
  Te{}
  Fa{}
  Fl{}
  Fs{}
  Fe{}
  Nu{}
  Nl{}
  Nl2{}

# depth counts open containers; k0/k1 hold their kinds, one bit each, 1 object
# and 0 array; kf is 1 while the string being scanned is a key rather than a
# value, which is the only thing the string scanner needs to know about where it
# came from.
type St is Data:
  St{n: Node, depth: U32, k0: U32, k1: U32, kf: U32}

def dead() -> St:
  St{Dead{}, 0, 0, 0, 0}

def start() -> St:
  St{Val{}, 0, 0, 0, 0}

def node(s: St) -> Node:
  match s:
    case St{n, d, k0, k1, kf}:
      n

def depth(s: St) -> U32:
  match s:
    case St{n, d, k0, k1, kf}:
      d

def kflag(s: St) -> U32:
  match s:
    case St{n, d, k0, k1, kf}:
      kf

def go(s: St, m: Node) -> St:
  match s:
    case St{n, d, k0, k1, kf}:
      St{m, d, k0, k1, kf}

def go.k(s: St, m: Node, +f: U32) -> St:
  match s:
    case St{n, d, k0, k1, kf}:
      St{m, d, k0, k1, f}

# -- the container stack -----------------------------------------------------

def kind.set(+w: U32, +i: U32, obj: Bool) -> U32:
  match obj:
    case True{}:
      bit.set(w, i)
    case False{}:
      bit.clr(w, i)

def push.mk(m: Node, +d: U32, k0: U32, k1: U32, +kf: U32, low: Bool, +obj: Bool) -> St:
  match low:
    case True{}:
      St{m, U32.inc(d), kind.set(k0, d, obj), k1, kf}
    case False{}:
      St{m, U32.inc(d), k0, kind.set(k1, U32.sub(d, 32), obj), kf}

def push.go(s: St, m: Node, +obj: Bool) -> St:
  match s:
    case St{n, +d, k0, k1, kf}:
      push.mk(m, d, k0, k1, kf, U32.is_lt(d, 32), obj)

# 64 containers is the ceiling: two U32s of kind bits is what a Data record can
# carry without an Array, and an Array would cost the state its kind. Deeper
# input is refused outright rather than silently flattened.
def push.at(s: St, m: Node, +obj: Bool, deep: Bool) -> St:
  match deep:
    case True{}:
      dead()
    case False{}:
      push.go(s, m, obj)

def push(+s: St, m: Node, +obj: Bool) -> St:
  push.at(s, m, obj, U32.is_ge(depth(s), 64))

def top.at(+k0: U32, +k1: U32, +i: U32, low: Bool) -> Bool:
  match low:
    case True{}:
      bit.get(k0, i)
    case False{}:
      bit.get(k1, U32.sub(i, 32))

def top.raw(s: St) -> Bool:
  match s:
    case St{n, +d, k0, k1, kf}:
      top.at(k0, k1, U32.sub(d, 1), U32.is_lt(U32.sub(d, 1), 32))

def top.go(+s: St, zero: Bool) -> Bool:
  match zero:
    case True{}:
      False{}
    case False{}:
      top.raw(s)

# the kind of the innermost open container. The depth-0 guard is not decoration:
# U32.sub(0, 1) wraps, and U32.to_nat of that builds a four-billion-long unary
# number -- a hang, not an error.
def top(+s: St) -> Bool:
  top.go(s, U32.is_zero(depth(s)))

# after a value completes: back to the enclosing container's separator, or to
# the end of the document if there is no enclosing container
def after.n(zero: Bool) -> Node:
  match zero:
    case True{}:
      Fin{}
    case False{}:
      Sep{}

def after(+s: St) -> St:
  go.k(s, after.n(U32.is_zero(depth(s))), 0)

def pop.mk(m: Node, +d: U32, k0: U32, k1: U32, low: Bool) -> St:
  match low:
    case True{}:
      St{m, d, bit.clr(k0, d), k1, 0}
    case False{}:
      St{m, d, k0, bit.clr(k1, U32.sub(d, 32)), 0}

# the closed container's kind bit is cleared on the way out, so two states that
# mean the same thing are the same value -- which is what lets the fixture
# compare a rolled-back state against the one it forked from
def pop.go(s: St, +d: U32) -> St:
  match s:
    case St{n, old, k0, k1, kf}:
      pop.mk(after.n(U32.is_zero(d)), d, k0, k1, U32.is_lt(d, 32))

def pop(+s: St) -> St:
  pop.go(s, U32.sub(depth(s), 1))

# -- the transition ----------------------------------------------------------

def is.ws(+c: U32) -> Bool:
  Mask.has(M.ws(), c)

def is.digit(+c: U32) -> Bool:
  Mask.has(M.digit(), c)

# The checker refuses a match on anything but a parameter or a field, so every
# byte test is a Bool the caller computes and the callee matches. A chain of
# tests is therefore one def a link, each link's False arm calling the next with
# the next test already applied. Strictness is why the chain is not one `sel`
# per link instead: an untaken pop(s) at depth 0 would wrap and hang.
def to.if(+s: St, m: Node, hit: Bool) -> St:
  match hit:
    case True{}:
      go(s, m)
    case False{}:
      dead()

def stay.if(+s: St, hit: Bool) -> St:
  match hit:
    case True{}:
      s
    case False{}:
      dead()

def end.if(+s: St, hit: Bool) -> St:
  match hit:
    case True{}:
      after(s)
    case False{}:
      dead()

# a value start: the seven first bytes a JSON value can have
def val.obj(+s: St, hit: Bool) -> St:
  match hit:
    case True{}:
      push(s, Keye{}, True{})
    case False{}:
      dead()

def val.arr(+s: St, +c: U32, hit: Bool) -> St:
  match hit:
    case True{}:
      push(s, Vale{}, False{})
    case False{}:
      val.obj(s, U32.is_eq(c, 123))

def val.null(+s: St, +c: U32, hit: Bool) -> St:
  match hit:
    case True{}:
      go(s, Nu{})
    case False{}:
      val.arr(s, c, U32.is_eq(c, 91))

def val.false(+s: St, +c: U32, hit: Bool) -> St:
  match hit:
    case True{}:
      go(s, Fa{})
    case False{}:
      val.null(s, c, U32.is_eq(c, 110))

def val.true(+s: St, +c: U32, hit: Bool) -> St:
  match hit:
    case True{}:
      go(s, Tr{})
    case False{}:
      val.false(s, c, U32.is_eq(c, 102))

# a leading zero may not be followed by another digit, which is why Zero and Int
# are separate nodes and not one node with a counter
def val.num(+s: St, hit: Bool) -> St:
  match hit:
    case True{}:
      go(s, Zero{})
    case False{}:
      go(s, Int{})

def val.dig(+s: St, +c: U32, hit: Bool) -> St:
  match hit:
    case True{}:
      val.num(s, U32.is_eq(c, 48))
    case False{}:
      val.true(s, c, U32.is_eq(c, 116))

def val.minus(+s: St, +c: U32, hit: Bool) -> St:
  match hit:
    case True{}:
      go(s, Min{})
    case False{}:
      val.dig(s, c, is.digit(c))

def val.str(+s: St, +c: U32, hit: Bool) -> St:
  match hit:
    case True{}:
      go.k(s, Str{}, 0)
    case False{}:
      val.minus(s, c, U32.is_eq(c, 45))

def val.ws(+s: St, +c: U32, hit: Bool) -> St:
  match hit:
    case True{}:
      s
    case False{}:
      val.str(s, c, U32.is_eq(c, 34))

def st.val(+s: St, +c: U32) -> St:
  val.ws(s, c, is.ws(c))

# the same, plus the closing bracket of an array that is still empty
def vale.close(+s: St, +c: U32, hit: Bool) -> St:
  match hit:
    case True{}:
      pop(s)
    case False{}:
      st.val(s, c)

def st.vale(+s: St, +c: U32) -> St:
  vale.close(s, c, U32.is_eq(c, 93))

def key.str(+s: St, hit: Bool) -> St:
  match hit:
    case True{}:
      go.k(s, Str{}, 1)
    case False{}:
      dead()

def key.ws(+s: St, +c: U32, hit: Bool) -> St:
  match hit:
    case True{}:
      s
    case False{}:
      key.str(s, U32.is_eq(c, 34))

def st.key(+s: St, +c: U32) -> St:
  key.ws(s, c, is.ws(c))

def keye.close(+s: St, +c: U32, hit: Bool) -> St:
  match hit:
    case True{}:
      pop(s)
    case False{}:
      st.key(s, c)

def st.keye(+s: St, +c: U32) -> St:
  keye.close(s, c, U32.is_eq(c, 125))

def colon.ws(+s: St, +c: U32, hit: Bool) -> St:
  match hit:
    case True{}:
      s
    case False{}:
      to.if(s, Val{}, U32.is_eq(c, 58))

def st.colon(+s: St, +c: U32) -> St:
  colon.ws(s, c, is.ws(c))

# a separator closes the container it is in, so the byte that is legal here
# depends on the stack and not only on the node
def sep.pop(+s: St, hit: Bool) -> St:
  match hit:
    case True{}:
      pop(s)
    case False{}:
      dead()

def sep.next(+s: St, obj: Bool) -> St:
  match obj:
    case True{}:
      go(s, Key{})
    case False{}:
      go(s, Val{})

def sep.shut(+s: St, +c: U32, obj: Bool) -> St:
  match obj:
    case True{}:
      sep.pop(s, U32.is_eq(c, 125))
    case False{}:
      sep.pop(s, U32.is_eq(c, 93))

def sep.comma(+s: St, +c: U32, hit: Bool) -> St:
  match hit:
    case True{}:
      sep.next(s, top(s))
    case False{}:
      sep.shut(s, c, top(s))

def sep.ws(+s: St, +c: U32, hit: Bool) -> St:
  match hit:
    case True{}:
      s
    case False{}:
      sep.comma(s, c, U32.is_eq(c, 44))

def st.sep(+s: St, +c: U32) -> St:
  sep.ws(s, c, is.ws(c))

def st.fin(+s: St, +c: U32) -> St:
  stay.if(s, is.ws(c))

# -- strings -----------------------------------------------------------------

# a closing quote lands in a different node depending on whether the string was
# a key or a value; kf is what carries that across the scan
def str.shut(+s: St, key: Bool) -> St:
  match key:
    case True{}:
      go.k(s, Colon{}, 0)
    case False{}:
      after(s)

def str.ctl(+s: St, low: Bool) -> St:
  match low:
    case True{}:
      dead()
    case False{}:
      s

def str.esc(+s: St, +c: U32, hit: Bool) -> St:
  match hit:
    case True{}:
      go(s, Esc{})
    case False{}:
      str.ctl(s, U32.is_lt(c, 32))

def str.quo(+s: St, +c: U32, hit: Bool) -> St:
  match hit:
    case True{}:
      str.shut(s, U32.is_eq(kflag(s), 1))
    case False{}:
      str.esc(s, c, U32.is_eq(c, 92))

def st.str(+s: St, +c: U32) -> St:
  str.quo(s, c, U32.is_eq(c, 34))

def esc.u(+s: St, hit: Bool) -> St:
  match hit:
    case True{}:
      go(s, U1{})
    case False{}:
      go(s, Str{})

def esc.ok(+s: St, +c: U32, hit: Bool) -> St:
  match hit:
    case True{}:
      esc.u(s, U32.is_eq(c, 117))
    case False{}:
      dead()

def st.esc(+s: St, +c: U32) -> St:
  esc.ok(s, c, Mask.has(M.escch(), c))

def st.hex(+s: St, +c: U32, m: Node) -> St:
  to.if(s, m, Mask.has(M.hex(), c))

# -- numbers -----------------------------------------------------------------

def st.min.z(+s: St, +c: U32, hit: Bool) -> St:
  match hit:
    case True{}:
      go(s, Zero{})
    case False{}:
      to.if(s, Int{}, is.digit(c))

def st.min(+s: St, +c: U32) -> St:
  st.min.z(s, c, U32.is_eq(c, 48))

def st.zero.d(+s: St, +c: U32, hit: Bool) -> St:
  match hit:
    case True{}:
      go(s, Dot{})
    case False{}:
      to.if(s, Exp{}, Mask.has(M.eonly(), c))

def st.zero(+s: St, +c: U32) -> St:
  st.zero.d(s, c, U32.is_eq(c, 46))

def st.int.d(+s: St, +c: U32, hit: Bool) -> St:
  match hit:
    case True{}:
      s
    case False{}:
      st.zero(s, c)

def st.int(+s: St, +c: U32) -> St:
  st.int.d(s, c, is.digit(c))

def st.dot(+s: St, +c: U32) -> St:
  to.if(s, Frac{}, is.digit(c))

def st.frac.d(+s: St, +c: U32, hit: Bool) -> St:
  match hit:
    case True{}:
      s
    case False{}:
      to.if(s, Exp{}, Mask.has(M.eonly(), c))

def st.frac(+s: St, +c: U32) -> St:
  st.frac.d(s, c, is.digit(c))

def st.esgn(+s: St, +c: U32) -> St:
  to.if(s, Expd{}, is.digit(c))

def st.exp.s(+s: St, +c: U32, hit: Bool) -> St:
  match hit:
    case True{}:
      go(s, Esgn{})
    case False{}:
      st.esgn(s, c)

def st.exp(+s: St, +c: U32) -> St:
  st.exp.s(s, c, Mask.has(M.sign(), c))

def st.expd(+s: St, +c: U32) -> St:
  stay.if(s, is.digit(c))

# -- literals ----------------------------------------------------------------

def st.lit(+s: St, +c: U32, +want: U32, m: Node) -> St:
  to.if(s, m, U32.is_eq(c, want))

def st.lit.end(+s: St, +c: U32, +want: U32) -> St:
  end.if(s, U32.is_eq(c, want))

# -- shift, reduce, step -----------------------------------------------------

def shift.at(m: Node, +s: St, +c: U32) -> St:
  match m:
    case Dead{}:
      dead()
    case Val{}:
      st.val(s, c)
    case Vale{}:
      st.vale(s, c)
    case Keye{}:
      st.keye(s, c)
    case Key{}:
      st.key(s, c)
    case Colon{}:
      st.colon(s, c)
    case Sep{}:
      st.sep(s, c)
    case Fin{}:
      st.fin(s, c)
    case Str{}:
      st.str(s, c)
    case Esc{}:
      st.esc(s, c)
    case U1{}:
      st.hex(s, c, U2{})
    case U2{}:
      st.hex(s, c, U3{})
    case U3{}:
      st.hex(s, c, U4{})
    case U4{}:
      st.hex(s, c, Str{})
    case Min{}:
      st.min(s, c)
    case Zero{}:
      st.zero(s, c)
    case Int{}:
      st.int(s, c)
    case Dot{}:
      st.dot(s, c)
    case Frac{}:
      st.frac(s, c)
    case Exp{}:
      st.exp(s, c)
    case Esgn{}:
      st.esgn(s, c)
    case Expd{}:
      st.expd(s, c)
    case Tr{}:
      st.lit(s, c, 114, Tu{})
    case Tu{}:
      st.lit(s, c, 117, Te{})
    case Te{}:
      st.lit.end(s, c, 101)
    case Fa{}:
      st.lit(s, c, 97, Fl{})
    case Fl{}:
      st.lit(s, c, 108, Fs{})
    case Fs{}:
      st.lit(s, c, 115, Fe{})
    case Fe{}:
      st.lit.end(s, c, 101)
    case Nu{}:
      st.lit(s, c, 117, Nl{})
    case Nl{}:
      st.lit(s, c, 108, Nl2{})
    case Nl2{}:
      st.lit.end(s, c, 108)

def shift(+s: St, +c: U32) -> St:
  shift.at(node(s), s, c)

# A number is the one token with no closing byte: it ends at the first byte that
# cannot continue it, and that byte is then the separator. reduce is that
# completion, applied before the shift, so step is two flat passes and never the
# self-call the checker would refuse.
def cont.at(m: Node, +c: U32) -> Bool:
  match m:
    case Zero{}:
      Mask.has(M.dote(), c)
    case Int{}:
      Bool.or(is.digit(c), Mask.has(M.dote(), c))
    case Frac{}:
      Bool.or(is.digit(c), Mask.has(M.eonly(), c))
    case Expd{}:
      is.digit(c)
    case Dead{}:
      True{}
    case Val{}:
      True{}
    case Vale{}:
      True{}
    case Keye{}:
      True{}
    case Key{}:
      True{}
    case Colon{}:
      True{}
    case Sep{}:
      True{}
    case Fin{}:
      True{}
    case Str{}:
      True{}
    case Esc{}:
      True{}
    case U1{}:
      True{}
    case U2{}:
      True{}
    case U3{}:
      True{}
    case U4{}:
      True{}
    case Min{}:
      True{}
    case Dot{}:
      True{}
    case Exp{}:
      True{}
    case Esgn{}:
      True{}
    case Tr{}:
      True{}
    case Tu{}:
      True{}
    case Te{}:
      True{}
    case Fa{}:
      True{}
    case Fl{}:
      True{}
    case Fs{}:
      True{}
    case Fe{}:
      True{}
    case Nu{}:
      True{}
    case Nl{}:
      True{}
    case Nl2{}:
      True{}

def reduce.if(+s: St, keep: Bool) -> St:
  match keep:
    case True{}:
      s
    case False{}:
      after(s)

def reduce(+s: St, +c: U32) -> St:
  reduce.if(s, cont.at(node(s), c))

def step(+s: St, +c: U32) -> St:
  shift(reduce(s, c), c)

def live.at(m: Node) -> Bool:
  match m:
    case Dead{}:
      False{}
    case Val{}:
      True{}
    case Vale{}:
      True{}
    case Keye{}:
      True{}
    case Key{}:
      True{}
    case Colon{}:
      True{}
    case Sep{}:
      True{}
    case Fin{}:
      True{}
    case Str{}:
      True{}
    case Esc{}:
      True{}
    case U1{}:
      True{}
    case U2{}:
      True{}
    case U3{}:
      True{}
    case U4{}:
      True{}
    case Min{}:
      True{}
    case Zero{}:
      True{}
    case Int{}:
      True{}
    case Dot{}:
      True{}
    case Frac{}:
      True{}
    case Exp{}:
      True{}
    case Esgn{}:
      True{}
    case Expd{}:
      True{}
    case Tr{}:
      True{}
    case Tu{}:
      True{}
    case Te{}:
      True{}
    case Fa{}:
      True{}
    case Fl{}:
      True{}
    case Fs{}:
      True{}
    case Fe{}:
      True{}
    case Nu{}:
      True{}
    case Nl{}:
      True{}
    case Nl2{}:
      True{}

def live(s: St) -> Bool:
  live.at(node(s))

# accepting: the document could stop here. A top-level number has no closing
# byte, so the four number nodes accept at depth 0 exactly as Fin does.
def acc.at(m: Node) -> Bool:
  match m:
    case Fin{}:
      True{}
    case Zero{}:
      True{}
    case Int{}:
      True{}
    case Frac{}:
      True{}
    case Expd{}:
      True{}
    case Dead{}:
      False{}
    case Val{}:
      False{}
    case Vale{}:
      False{}
    case Keye{}:
      False{}
    case Key{}:
      False{}
    case Colon{}:
      False{}
    case Sep{}:
      False{}
    case Str{}:
      False{}
    case Esc{}:
      False{}
    case U1{}:
      False{}
    case U2{}:
      False{}
    case U3{}:
      False{}
    case U4{}:
      False{}
    case Min{}:
      False{}
    case Dot{}:
      False{}
    case Exp{}:
      False{}
    case Esgn{}:
      False{}
    case Tr{}:
      False{}
    case Tu{}:
      False{}
    case Te{}:
      False{}
    case Fa{}:
      False{}
    case Fl{}:
      False{}
    case Fs{}:
      False{}
    case Fe{}:
      False{}
    case Nu{}:
      False{}
    case Nl{}:
      False{}
    case Nl2{}:
      False{}

def done(+s: St) -> Bool:
  Bool.and(U32.is_zero(depth(s)), acc.at(node(s)))

# -- the mask ----------------------------------------------------------------

def mask.sep(obj: Bool) -> Mask:
  match obj:
    case True{}:
      Mask.or(M.comma(), M.rbrace())
    case False{}:
      Mask.or(M.comma(), M.rbrack())

def mask.tail(+s: St, zero: Bool) -> Mask:
  match zero:
    case True{}:
      M.ws()
    case False{}:
      Mask.or(M.ws(), mask.sep(top(s)))

# the bytes that end a number: whitespace at the top level, or the comma and
# closer of whatever container it sits in. This is reduce, read forwards.
def mask.after(+s: St) -> Mask:
  mask.tail(s, U32.is_zero(depth(s)))

def mask.close(+s: St, zero: Bool) -> Mask:
  match zero:
    case True{}:
      M.none()
    case False{}:
      mask.sep(top(s))

# a value start at the ceiling is vstart less `[` and `{`: push refuses a 65th
# container, and a mask that still offered them would pass a byte the step kills
def mask.val(deep: Bool) -> Mask:
  match deep:
    case True{}:
      Mask{0, 67051524, 0, 1065024, 0, 0, 0, 0}
    case False{}:
      M.vstart()

def mask.at(m: Node, +s: St) -> Mask:
  match m:
    case Dead{}:
      M.none()
    case Val{}:
      Mask.or(M.ws(), mask.val(U32.is_ge(depth(s), 64)))
    case Vale{}:
      Mask.or(M.ws(), Mask.or(mask.val(U32.is_ge(depth(s), 64)), M.rbrack()))
    case Keye{}:
      Mask.or(M.ws(), Mask.or(M.quote(), M.rbrace()))
    case Key{}:
      Mask.or(M.ws(), M.quote())
    case Colon{}:
      Mask.or(M.ws(), M.colon())
    case Sep{}:
      Mask.or(M.ws(), mask.close(s, U32.is_zero(depth(s))))
    case Fin{}:
      M.ws()
    case Str{}:
      M.body()
    case Esc{}:
      M.escch()
    case U1{}:
      M.hex()
    case U2{}:
      M.hex()
    case U3{}:
      M.hex()
    case U4{}:
      M.hex()
    case Min{}:
      M.digit()
    case Zero{}:
      Mask.or(M.dote(), mask.after(s))
    case Int{}:
      Mask.or(M.digit(), Mask.or(M.dote(), mask.after(s)))
    case Dot{}:
      M.digit()
    case Frac{}:
      Mask.or(M.digit(), Mask.or(M.eonly(), mask.after(s)))
    case Exp{}:
      Mask.or(M.digit(), M.sign())
    case Esgn{}:
      M.digit()
    case Expd{}:
      Mask.or(M.digit(), mask.after(s))
    case Tr{}:
      M.c_r()
    case Tu{}:
      M.c_u()
    case Te{}:
      M.c_e()
    case Fa{}:
      M.c_a()
    case Fl{}:
      M.c_l()
    case Fs{}:
      M.c_s()
    case Fe{}:
      M.c_e()
    case Nu{}:
      M.c_u()
    case Nl{}:
      M.c_l()
    case Nl2{}:
      M.c_l()

# the set of bytes that keep this state alive, built from the node and the stack
# and never by trying all 256 bytes -- which is the point, and the hazard the
# fixture's law exists to close
def mask(+s: St) -> Mask:
  mask.at(node(s), s)

def allows(+s: St, +c: U32) -> Bool:
  Mask.has(mask(s), c)

# -- showing ------------------------------------------------------------------

# a mask as decimal byte ranges: "9-10 13 32 34 45 48-57 91 102 110 116 123".
# Ranges rather than eight words because the point of printing a mask is that a
# human reading a failed row can see *which byte* moved.
type Sh is Data:
  Sh{out: String, st: U32, open: Bool}

def rng.if(+a: U32, +b: U32, one: Bool) -> String:
  match one:
    case True{}:
      " " ++ U32.show(a)
    case False{}:
      " " ++ U32.show(a) ++ "-" ++ U32.show(b)

def rng(+a: U32, +b: U32) -> String:
  rng.if(a, b, U32.is_eq(a, b))

def sh.mk(out: String, +st: U32, +i: U32, open: Bool, here: Bool) -> Sh:
  match open here:
    case False{} False{}:
      Sh{out, st, False{}}
    case False{} True{}:
      Sh{out, i, True{}}
    case True{} False{}:
      Sh{out ++ rng(st, U32.sub(i, 1)), 0, False{}}
    case True{} True{}:
      Sh{out, st, True{}}

def sh.one(h: Sh, +i: U32, here: Bool) -> Sh:
  match h:
    case Sh{out, st, open}:
      sh.mk(out, st, i, open, here)

def sh.go(k: Nat, +i: U32, +m: Mask, h: Sh) -> Sh:
  match k:
    case 0n:
      h
    case 1n++p:
      sh.go(p, U32.inc(i), m, sh.one(h, i, Mask.has(m, i)))

def sh.fin(out: String, +st: U32, open: Bool) -> String:
  match open:
    case True{}:
      out ++ rng(st, 255)
    case False{}:
      out

def sh.end(h: Sh) -> String:
  match h:
    case Sh{out, st, open}:
      sh.fin(out, st, open)

def Mask.show(+m: Mask) -> String:
  sh.end(sh.go(256n, 0, m, Sh{"", 0, False{}}))

def show.n(m: Node) -> String:
  match m:
    case Dead{}:
      "dead"
    case Val{}:
      "val"
    case Vale{}:
      "vale"
    case Keye{}:
      "keye"
    case Key{}:
      "key"
    case Colon{}:
      "colon"
    case Sep{}:
      "sep"
    case Fin{}:
      "fin"
    case Str{}:
      "str"
    case Esc{}:
      "esc"
    case U1{}:
      "u1"
    case U2{}:
      "u2"
    case U3{}:
      "u3"
    case U4{}:
      "u4"
    case Min{}:
      "min"
    case Zero{}:
      "zero"
    case Int{}:
      "int"
    case Dot{}:
      "dot"
    case Frac{}:
      "frac"
    case Exp{}:
      "exp"
    case Esgn{}:
      "esgn"
    case Expd{}:
      "expd"
    case Tr{}:
      "t.r"
    case Tu{}:
      "t.u"
    case Te{}:
      "t.e"
    case Fa{}:
      "f.a"
    case Fl{}:
      "f.l"
    case Fs{}:
      "f.s"
    case Fe{}:
      "f.e"
    case Nu{}:
      "n.u"
    case Nl{}:
      "n.l"
    case Nl2{}:
      "n.l2"

def show.k(+kf: U32, key: Bool) -> String:
  match key:
    case True{}:
      "k"
    case False{}:
      ""

# node, depth, and a k when the string being scanned is a key. The stack's kind
# bits are not printed: top() is the only thing that reads them, and a state
# that differs only in a bit above depth is a state pop forgot to clear.
def show(+s: St) -> String:
  show.n(node(s)) ++ "/" ++ U32.show(depth(s)) ++ show.k(kflag(s), U32.is_eq(kflag(s), 1))

# -- driving a document ------------------------------------------------------

# the Bytes is the caller's and comes back with the state: a document is fed,
# never owned. Walk is kind Type only because it holds that Bytes -- the St
# inside it is still Data, which is the whole point of the lane.
type Walk is Type:
  Walk{b: Bytes.Bytes, s: St}

def run.at(s: St, r: Bytes.Bytes & U32) -> Walk:
  (b, c) = r
  Walk{b, step(s, c)}

def run.go(k: Nat, +i: U32, w: Walk) -> Walk:
  match k:
    case 0n:
      w
    case 1n++p:
      match w:
        case Walk{b, s}:
          run.go(p, U32.inc(i), run.at(s, Bytes.at(b, i)))

def run.len(s: St, r: Bytes.Bytes & U32) -> Walk:
  (b, n) = r
  run.go(U32.to_nat(n), 0, Walk{b, s})

# a dead state keeps stepping and stays dead, so run never needs an early exit
def run(b: Bytes.Bytes, s: St) -> Walk:
  run.len(s, Bytes.len(b))
