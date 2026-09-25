# The Python VM spike: source -> house lexer -> house parser -> typed AST ->
# bytecode -> a stack VM. The subset (v2): v1 (non-negative ints, bools,
# + - * // %, comparisons, and/or/not, if/elif/else, while, def/call/recursion,
# return, print) plus strings -- literals with escapes, + and ==/!= dispatched
# by type, len(), print of strings. Floats, lists, dicts, f-strings and the
# rest are refused by name. The dispatch is the one dense U32 match over the
# contiguous opcode rows -- the new compiler's table shape; what it lowers to
# is measured in the lane report.
#   PY_SOURCE=prog.py bun bend2/main.ts demos/python/vm.bend
import Base
import ./syntax.bend as S
import ./intake.bend as I
import ./lexer.bend as L
import ./parser.bend as P
import ./nodes.bend as N

# Types
# =====

type Val is Data:
  VInt{n: Nat}
  VBool{b: Bool}
  VNone{}
  VStr{s: String}
  VFunc{i: Nat}
  VUnset{}

# op is U32 and DENSE 0..29 (contiguous rows only); a and b are operands.
type Instr is Data:
  Instr{op: U32, a: Nat, b: Nat}

type Def is Data:
  Def{name: String, params: List<&2, String>, nparams: Nat, body: S.Json}

type Func is Data:
  Func{nparams: Nat, nlocals: Nat, code: List<&2, Instr>}

type VFrame is Data:
  VFrame{here: List<&2, Instr>, rest: List<&2, Instr>, locals: List<&2, Val>, depth: Nat}

type Prog is Data:
  Prog{funcs: List<&2, Func>, consts: List<&2, Val>, nglobals: Nat, code: List<&2, Instr>}

# One compilation threads the tables through every fragment: the const pool
# and the global name table grow, the local table is fixed per unit.
type Env is Data:
  Env{consts: List<&2, Val>, nconsts: Nat, globals: List<&2, String>, nglobals: Nat,
      funcs: List<&2, Def>, names: List<&2, String>, nnames: Nat}

# A compiled fragment, REVERSED (the latest instr at the head), with its
# length: jump targets are absolute positions computed from the sub-lengths.
# A fault is an unsupported construct; it compiles to nothing and rides out.
type Cx is Data:
  Cx{code: List<&2, Instr>, len: Nat, env: Env, fault: String}

type Frg is Data:
  Frg{code: List<&2, Instr>, len: Nat, op: U32}

type Pop is Data:
  Pop{args: List<&2, Val>, more: List<&2, Val>}

type Run is Data:
  Run{funcs: List<&2, Func>, consts: List<&2, Val>, stack: List<&2, Val>,
      here: List<&2, Instr>, rest: List<&2, Instr>, locals: List<&2, Val>,
      globals: List<&2, Val>, frames: List<&2, VFrame>, out: List<&2, String>,
      fault: String}

# Opcodes, dense and contiguous:
#   0 CONST a      6 ADD      11 LT     17 NOT      23 CALL a b
#   1 LOAD_L a     7 SUB      12 LTE    18 JUMP a   24 RET
#   2 STORE_L a    8 MUL      13 GT     19 JIF a    25 PRINT b
#   3 LOAD_G a     9 DIV      14 GTE    20 JIT a    26 HALT
#   4 STORE_G a   10 MOD      15 EQ     21 JIFK a   27 LEN
#   5 POP                     16 NEQ    22 JITK a   28 GETITEM  29 SLICE a b

# S.Json access
# ===========

def jfields(+j: S.Json) -> S.Json:
  match j:
    case S.JObj{fs}:
      fs
    case _:
      S.JEnd{}

def jtag(+j: S.Json) -> String:
  N.string(N.get(jfields(j), "tag"))

def jfield(+j: S.Json, +key: String) -> S.Json:
  N.get(jfields(j), key)

def jstr(+j: S.Json) -> String:
  match j:
    case S.JStr{s}:
      s
    case _:
      ""

def jnull(+j: S.Json) -> Bool:
  match j:
    case S.JNull{}:
      True{}
    case _:
      False{}

def jitems(+j: S.Json) -> S.Json:
  match j:
    case S.JArr{xs}:
      xs
    case _:
      S.JEnd{}

def jend(+j: S.Json) -> Bool:
  match j:
    case S.JEnd{}:
      True{}
    case _:
      False{}

def first_of(+js: S.Json) -> S.Json:
  match js:
    case S.JItem{h, t}:
      h
    case _:
      S.JNull{}

# The number of entries in a JSON item chain (an argument list, a statement list).
def jcount(+j: S.Json) -> Nat:
  match j:
    case S.JItem{h, t}:
      (1n + jcount(t) : Nat)
    case _:
      0n

# Fragments
# =========

# join(later, earlier): both reversed; the result is the program
# earlier ++ later, still reversed -- which in the reversed shape is the
# plain append later ++ earlier. O(|later|), one cons per instruction.
def join(+later: List<&2, Instr>, earlier: List<&2, Instr>) -> List<&2, Instr>:
  match later:
    case Nil{}:
      earlier
    case Con{h, t}:
      Con{h, join(t, earlier)}

def one(+op: U32, +a: Nat, +b: Nat) -> List<&2, Instr>:
  Con{Instr{op, a, b}, Nil{}}

def pick_fault(+a: String, +b: String) -> String:
  S.choose(String, String.is_empty(a), u => b, u => a)

def count(+js: S.Json, +n: Nat) -> Nat:
  match js:
    case S.JEnd{}:
      n
    case S.JItem{one, rest}:
      count(rest, 1n+n)
    case _:
      n

def headc(+s: String) -> Char:
  match s:
    case SNil{}:
      Chr{0}
    case SCon{h, t}:
      h

# A computed Cx is read through its accessors: a pattern-let of a computed
# value is not a legal scrutinee, a parameter is.
def cx_code(+c: Cx) -> List<&2, Instr>:
  match c:
    case Cx{code, len, env, fault}:
      code

def cx_len(+c: Cx) -> Nat:
  match c:
    case Cx{code, len, env, fault}:
      len

def cx_env(+c: Cx) -> Env:
  match c:
    case Cx{code, len, env, fault}:
      env

def cx_fault(+c: Cx) -> String:
  match c:
    case Cx{code, len, env, fault}:
      fault

# The subset's int ceiling, 2**48 - 1: every lane holds it exactly (the JS
# lane's immediates stop there, the C lane's words would wrap at 2**64), so a
# result past it is refused rather than rounded or wrapped. Composed, never
# written long, and never through 2**48 itself -- the JS lane refuses that
# intermediate: (2**16 - 1) * 2**32 + (2**16 - 1) * 2**16 + (2**16 - 1).
def int_cap() -> Nat:
  +w = Nat.mul(256n, 256n)
  +m = Nat.sub(w, 1n)
  Nat.add(Nat.mul(m, Nat.mul(w, w)), Nat.add(Nat.mul(m, w), m))

def add_fits(+x: Nat, +y: Nat) -> Bool:
  Nat.is_le(y, int_cap()) && Nat.is_le(x, Nat.sub(int_cap(), y))

def mul_fits(+x: Nat, +y: Nat) -> Bool:
  Nat.is_eq(y, 0n) || Nat.is_le(x, Nat.div(int_cap(), y))

# Number literals
# ===============

def digit_ok(+c: Char, +base: Nat) -> Bool:
  +n = Char.to_u32(c)
  S.choose(Bool, U32.is_ge(n, 48) && U32.is_le(n, 57), u => Nat.is_lt((U32.to_nat(n) - 48n : Nat), base), u =>
    S.choose(Bool, U32.is_ge(n, 65) && U32.is_le(n, 70), u => Nat.is_lt((U32.to_nat(n) - 55n : Nat), base), u =>
      S.choose(Bool, U32.is_ge(n, 97) && U32.is_le(n, 102), u => Nat.is_lt((U32.to_nat(n) - 87n : Nat), base), u => False{})))

def digit_val(+c: Char) -> Nat:
  +n = Char.to_u32(c)
  S.choose(Nat, U32.is_ge(n, 48) && U32.is_le(n, 57), u => (U32.to_nat(n) - 48n : Nat), u =>
    S.choose(Nat, U32.is_ge(n, 65) && U32.is_le(n, 70), u => (U32.to_nat(n) - 55n : Nat), u =>
      (U32.to_nat(n) - 87n : Nat)))

type NV is Data:
  NV{n: Nat, fault: String}

def nv_n(+p: NV) -> Nat:
  match p:
    case NV{n, fault}:
      n

def nv_f(+p: NV) -> String:
  match p:
    case NV{n, fault}:
      fault

def digits(+s: String, +base: Nat, +acc: Nat) -> NV:
  match s:
    case SNil{}:
      NV{acc, ""}
    case SCon{+h, +t}:
      S.choose(NV, Char.is_eq(h, '_'), u => digits(t, base, acc), u =>
        S.choose(NV, digit_ok(h, base), u =>
          S.choose(NV, Nat.is_le(acc, Nat.div(Nat.sub(int_cap(), digit_val(h)), base)), u => digits(t, base, (base * acc + digit_val(h) : Nat)), u =>
            NV{0n, "an int past 2**48 - 1 is outside the subset"}), u =>
          S.choose(NV, Char.is_eq(h, '.') || Char.is_eq(h, 'e') || Char.is_eq(h, 'E') || Char.is_eq(h, 'j') || Char.is_eq(h, 'J'),
            u => NV{0n, "floats and complex literals are outside the subset"}, u => NV{0n, "invalid digit in literal"})))

def number_value(+raw: String) -> NV:
  S.choose(NV, String.starts_with(raw, "0x") || String.starts_with(raw, "0X"), u => digits(String.drop(raw, 2n), 16n, 0n), u =>
    S.choose(NV, String.starts_with(raw, "0o") || String.starts_with(raw, "0O"), u => digits(String.drop(raw, 2n), 8n, 0n), u =>
      S.choose(NV, String.starts_with(raw, "0b") || String.starts_with(raw, "0B"), u => digits(String.drop(raw, 2n), 2n, 0n), u =>
        digits(raw, 10n, 0n))))

# String literals
# ===============

# The decoded value of a literal: the string and a fault (bytes, unicode
# escapes, an octal value out of range).
type SV is Data:
  SV{s: String, fault: String}

def sv_s(+p: SV) -> String:
  match p:
    case SV{s, fault}:
      s

def sv_f(+p: SV) -> String:
  match p:
    case SV{s, fault}:
      fault

def esc_char(+n: Nat) -> Char:
  Char.from_u32(U32.from_nat(n))

def quote_of(+c: Char) -> Bool:
  Char.is_eq(c, '\'') || Char.is_eq(c, '"')

# The parser joins adjacent STRING tokens with a space (parser.bend's Strings),
# so a run of chunks: skip the spaces, scan one body, keep going.

# A scanned body: the chars so far (reversed), the rest after the closing
# quote, and a fault (unterminated, bytes are refused above, unicode escapes,
# an octal value out of range).
type ESV is Data:
  ESV{acc: String, rest: String, fault: String}

def gv_s(+p: ESV) -> String:
  match p:
    case ESV{acc, rest, fault}:
      acc

def gv_rest(+p: ESV) -> String:
  match p:
    case ESV{acc, rest, fault}:
      rest

def gv_f(+p: ESV) -> String:
  match p:
    case ESV{acc, rest, fault}:
      fault

# The walk's mode, a constructor per state: the dispatch stays a constructor
# match. The walk carries ONE CHARACTER OF LOOKAHEAD (cur): each call processes
# cur in its mode and consumes the string's head as the next cur, so every
# self-call's first argument is the matched tail.
type M is Data:
  MBody{}
  MEsc{}
  MHex1{}
  MHex2{}
  MOct{}
  MCr{}
  MQx{}
  MGap{}
  MPre{}
  MQrun{}

# esc decodes a STRING token run: the parser joins adjacent tokens with a
# space (MGap skips it), each chunk opens with its prefix (r/b/u/f in MPre)
# and quote run (MQrun), the body copies through (MBody), the closing quote
# (one, or three for a triple -- MQx counts the run) ends the chunk, a
# backslash escapes (MEsc, unless the prefix was r): \n and friends decode,
# \\xHH takes one or two hex digits, \\NNN up to three octal digits, unknown
# letters keep the backslash, \\u \\U \\N are refused. acc gathers the decoded
# text chunk by chunk; buf holds the current chunk reversed. A mode that
# stops mid-escape emits what it owes and re-dispatches the unconsumed char.
# MOct ends two ways -- a third digit, or a char that is not one -- and both
# leave cur, the char after the escape, still to handle exactly as MBody
# would (close, escape, triple-quote run, or copy). The third-digit exit once
# dropped it: "\101hi" read as "Ai" (found by fuzz_vm.py).
def esc(+s: String, +q: Char, +tri: Bool, +raw: Bool, +acc: String, +buf: String, +m: M, +v: Nat, +k: Nat, +cur: Nat) -> ESV:
  match s m:
    case SNil{} _:
      match m:
        case MGap{}:
          ESV{acc, "", ""}
        case MBody{}:
          S.choose(ESV, Char.is_eq(esc_char(cur), q) && Bool.not(tri), u => ESV{String.append(acc, String.reverse(buf)), "", ""}, u => ESV{acc, "", "an unterminated string literal"})
        case MQx{}:
          S.choose(ESV, Char.is_eq(esc_char(cur), q) && Nat.is_eq(v, 2n), u => ESV{String.append(acc, String.reverse(buf)), "", ""}, u => ESV{acc, "", "an unterminated string literal"})
        case MQrun{}:
          S.choose(ESV, Char.is_eq(esc_char(cur), q) && Nat.is_eq(v, 1n), u => ESV{acc, "", ""}, u => ESV{acc, "", "an unterminated string literal"})
        case MCr{}:
          S.choose(ESV, Char.is_eq(esc_char(cur), q) && Bool.not(tri), u => ESV{String.append(acc, String.reverse(buf)), "", ""}, u => ESV{acc, "", "an unterminated string literal"})
        case MHex2{}:
          ESV{"", "", "an invalid \\x escape"}
        case MOct{}:
          S.choose(ESV, Nat.is_le(v, 255n), u => S.choose(ESV, Char.is_eq(esc_char(cur), q) && Bool.not(tri), u => ESV{String.append(acc, String.reverse(SCon{esc_char(v), buf})), "", ""}, u => ESV{acc, "", "an unterminated string literal"}), u => ESV{"", "", "an octal escape outside the range 0-0o377"})
        case _:
          ESV{acc, "", "an unterminated string literal"}
    case SCon{+h, +t} MBody{}:
      S.choose(ESV, Char.is_eq(esc_char(cur), q), u => S.choose(ESV, tri, u => esc(t, q, tri, raw, acc, buf, MQx{}, 1n, k, U32.to_nat(Char.to_u32(h))), u => esc(t, q, tri, raw, String.append(acc, String.reverse(buf)), "", MGap{}, 0n, 0n, U32.to_nat(Char.to_u32(h)))), u => S.choose(ESV, Char.is_eq(esc_char(cur), Chr{92}) && Bool.not(raw), u => esc(t, q, tri, raw, acc, buf, MEsc{}, 0n, k, U32.to_nat(Char.to_u32(h))), u => esc(t, q, tri, raw, acc, SCon{esc_char(cur), buf}, MBody{}, 0n, k, U32.to_nat(Char.to_u32(h)))))
    case SCon{+h, +t} MEsc{}:
      S.choose(ESV, Char.is_eq(esc_char(cur), '\n'), u => esc(t, q, tri, raw, acc, buf, MBody{}, 0n, k, U32.to_nat(Char.to_u32(h))), u => S.choose(ESV, Char.is_eq(esc_char(cur), '\r'), u => esc(t, q, tri, raw, acc, buf, MCr{}, 0n, k, U32.to_nat(Char.to_u32(h))), u => S.choose(ESV, Char.is_eq(esc_char(cur), 'n'), u => esc(t, q, tri, raw, acc, SCon{esc_char(10n), buf}, MBody{}, 0n, k, U32.to_nat(Char.to_u32(h))), u => S.choose(ESV, Char.is_eq(esc_char(cur), 't'), u => esc(t, q, tri, raw, acc, SCon{esc_char(9n), buf}, MBody{}, 0n, k, U32.to_nat(Char.to_u32(h))), u => S.choose(ESV, Char.is_eq(esc_char(cur), 'r'), u => esc(t, q, tri, raw, acc, SCon{esc_char(13n), buf}, MBody{}, 0n, k, U32.to_nat(Char.to_u32(h))), u => S.choose(ESV, Char.is_eq(esc_char(cur), 'a'), u => esc(t, q, tri, raw, acc, SCon{esc_char(7n), buf}, MBody{}, 0n, k, U32.to_nat(Char.to_u32(h))), u => S.choose(ESV, Char.is_eq(esc_char(cur), 'b'), u => esc(t, q, tri, raw, acc, SCon{esc_char(8n), buf}, MBody{}, 0n, k, U32.to_nat(Char.to_u32(h))), u => S.choose(ESV, Char.is_eq(esc_char(cur), 'f'), u => esc(t, q, tri, raw, acc, SCon{esc_char(12n), buf}, MBody{}, 0n, k, U32.to_nat(Char.to_u32(h))), u => S.choose(ESV, Char.is_eq(esc_char(cur), 'v'), u => esc(t, q, tri, raw, acc, SCon{esc_char(11n), buf}, MBody{}, 0n, k, U32.to_nat(Char.to_u32(h))), u => S.choose(ESV, Char.is_eq(esc_char(cur), Chr{92}), u => esc(t, q, tri, raw, acc, SCon{Chr{92}, buf}, MBody{}, 0n, k, U32.to_nat(Char.to_u32(h))), u => S.choose(ESV, Char.is_eq(esc_char(cur), esc_char(39n)), u => esc(t, q, tri, raw, acc, SCon{esc_char(39n), buf}, MBody{}, 0n, k, U32.to_nat(Char.to_u32(h))), u => S.choose(ESV, Char.is_eq(esc_char(cur), esc_char(34n)), u => esc(t, q, tri, raw, acc, SCon{esc_char(34n), buf}, MBody{}, 0n, k, U32.to_nat(Char.to_u32(h))), u => S.choose(ESV, Char.is_eq(esc_char(cur), 'x'), u => esc(t, q, tri, raw, acc, buf, MHex1{}, 0n, k, U32.to_nat(Char.to_u32(h))), u => S.choose(ESV, digit_ok(esc_char(cur), 8n), u => esc(t, q, tri, raw, acc, buf, MOct{}, digit_val(esc_char(cur)), 1n, U32.to_nat(Char.to_u32(h))), u => S.choose(ESV, Char.is_eq(esc_char(cur), 'u') || Char.is_eq(esc_char(cur), 'U') || Char.is_eq(esc_char(cur), 'N'), u => ESV{"", "", "unicode escapes are outside the subset"}, u => esc(t, q, tri, raw, acc, SCon{esc_char(cur), SCon{Chr{92}, buf}}, MBody{}, 0n, k, U32.to_nat(Char.to_u32(h))))))))))))))))))
    case SCon{+h, +t} MHex1{}:
      S.choose(ESV, digit_ok(esc_char(cur), 16n), u => esc(t, q, tri, raw, acc, buf, MHex2{}, digit_val(esc_char(cur)), 0n, U32.to_nat(Char.to_u32(h))), u => ESV{"", "", "an invalid \\x escape"})
    case SCon{+h, +t} MHex2{}:
      S.choose(ESV, digit_ok(esc_char(cur), 16n), u => esc(t, q, tri, raw, acc, SCon{esc_char((16n*v + digit_val(esc_char(cur)) : Nat)), buf}, MBody{}, 0n, k, U32.to_nat(Char.to_u32(h))), u => ESV{"", "", "an invalid \\x escape"})
    case SCon{+h, +t} MOct{}:
      S.choose(ESV, Nat.is_lt(k, 3n) && digit_ok(esc_char(cur), 8n), u => esc(t, q, tri, raw, acc, buf, MOct{}, (8n*v + digit_val(esc_char(cur)) : Nat), 1n+k, U32.to_nat(Char.to_u32(h))), u =>
        S.choose(ESV, Nat.is_le(v, 255n), u => S.choose(ESV, Char.is_eq(esc_char(cur), q), u => S.choose(ESV, tri, u => esc(t, q, tri, raw, acc, SCon{esc_char(v), buf}, MQx{}, 1n, k, U32.to_nat(Char.to_u32(h))), u => esc(t, q, tri, raw, String.append(acc, String.reverse(SCon{esc_char(v), buf})), "", MGap{}, 0n, 0n, U32.to_nat(Char.to_u32(h)))), u => S.choose(ESV, Char.is_eq(esc_char(cur), Chr{92}) && Bool.not(raw), u => esc(t, q, tri, raw, acc, SCon{esc_char(v), buf}, MEsc{}, 0n, k, U32.to_nat(Char.to_u32(h))), u => esc(t, q, tri, raw, acc, SCon{esc_char(cur), SCon{esc_char(v), buf}}, MBody{}, 0n, k, U32.to_nat(Char.to_u32(h))))), u => ESV{"", "", "an octal escape outside the range 0-0o377"}))
    case SCon{+h, +t} MCr{}:
      S.choose(ESV, Char.is_eq(esc_char(cur), '\n'), u => esc(t, q, tri, raw, acc, buf, MBody{}, 0n, k, U32.to_nat(Char.to_u32(h))), u => S.choose(ESV, Char.is_eq(esc_char(cur), q) && Bool.not(tri), u => esc(t, q, tri, raw, String.append(acc, String.reverse(buf)), "", MGap{}, 0n, 0n, U32.to_nat(Char.to_u32(h))), u => S.choose(ESV, Char.is_eq(esc_char(cur), Chr{92}) && Bool.not(raw), u => esc(t, q, tri, raw, acc, buf, MEsc{}, 0n, k, U32.to_nat(Char.to_u32(h))), u => esc(t, q, tri, raw, acc, SCon{esc_char(cur), buf}, MBody{}, 0n, k, U32.to_nat(Char.to_u32(h))))))
    case SCon{+h, +t} MQx{}:
      S.choose(ESV, Char.is_eq(esc_char(cur), q), u => S.choose(ESV, Nat.is_eq(v, 2n), u => esc(t, q, tri, raw, String.append(acc, String.reverse(buf)), "", MGap{}, 0n, 0n, U32.to_nat(Char.to_u32(h))), u => esc(t, q, tri, raw, acc, buf, MQx{}, 2n, k, U32.to_nat(Char.to_u32(h)))), u => S.choose(ESV, Nat.is_eq(v, 2n), u => S.choose(ESV, Char.is_eq(esc_char(cur), q) && Bool.not(tri), u => esc(t, q, tri, raw, String.append(acc, String.reverse(SCon{q, SCon{q, buf}})), "", MGap{}, 0n, 0n, U32.to_nat(Char.to_u32(h))), u => S.choose(ESV, Char.is_eq(esc_char(cur), Chr{92}) && Bool.not(raw), u => esc(t, q, tri, raw, acc, SCon{q, SCon{q, buf}}, MEsc{}, 0n, k, U32.to_nat(Char.to_u32(h))), u => esc(t, q, tri, raw, acc, SCon{esc_char(cur), SCon{q, SCon{q, buf}}}, MBody{}, 0n, k, U32.to_nat(Char.to_u32(h))))), u => S.choose(ESV, Char.is_eq(esc_char(cur), q) && Bool.not(tri), u => esc(t, q, tri, raw, String.append(acc, String.reverse(SCon{q, buf})), "", MGap{}, 0n, 0n, U32.to_nat(Char.to_u32(h))), u => S.choose(ESV, Char.is_eq(esc_char(cur), Chr{92}) && Bool.not(raw), u => esc(t, q, tri, raw, acc, SCon{q, buf}, MEsc{}, 0n, k, U32.to_nat(Char.to_u32(h))), u => esc(t, q, tri, raw, acc, SCon{esc_char(cur), SCon{q, buf}}, MBody{}, 0n, k, U32.to_nat(Char.to_u32(h)))))))
    case SCon{+h, +t} MGap{}:
      S.choose(ESV, Char.is_eq(esc_char(cur), ' '), u => esc(t, q, tri, raw, acc, buf, MGap{}, 0n, 0n, U32.to_nat(Char.to_u32(h))), u => S.choose(ESV, quote_of(esc_char(cur)), u => S.choose(ESV, Nat.is_eq(k, 1n), u => ESV{"", "", "bytes literals are outside the subset"}, u => esc(t, esc_char(cur), False{}, raw, acc, "", MQrun{}, 1n, 0n, U32.to_nat(Char.to_u32(h)))), u => S.choose(ESV, Char.is_eq(esc_char(cur), 'r') || Char.is_eq(esc_char(cur), 'R'), u => esc(t, q, tri, True{}, acc, buf, MPre{}, v, k, U32.to_nat(Char.to_u32(h))), u => esc(t, q, tri, raw, acc, buf, MPre{}, v, k, U32.to_nat(Char.to_u32(h))))))
    case SCon{+h, +t} MPre{}:
      S.choose(ESV, quote_of(esc_char(cur)), u => S.choose(ESV, Nat.is_eq(k, 1n), u => ESV{"", "", "bytes literals are outside the subset"}, u => esc(t, esc_char(cur), False{}, raw, acc, "", MQrun{}, 1n, 0n, U32.to_nat(Char.to_u32(h)))), u => S.choose(ESV, Char.is_eq(esc_char(cur), 'r') || Char.is_eq(esc_char(cur), 'R'), u => esc(t, q, tri, True{}, acc, buf, MPre{}, v, k, U32.to_nat(Char.to_u32(h))), u => S.choose(ESV, Char.is_eq(esc_char(cur), 'b') || Char.is_eq(esc_char(cur), 'B'), u => esc(t, q, tri, raw, acc, buf, MPre{}, v, 1n, U32.to_nat(Char.to_u32(h))), u => S.choose(ESV, Char.is_eq(esc_char(cur), 'u') || Char.is_eq(esc_char(cur), 'U') || Char.is_eq(esc_char(cur), 'f') || Char.is_eq(esc_char(cur), 'F'), u => esc(t, q, tri, raw, acc, buf, MPre{}, v, k, U32.to_nat(Char.to_u32(h))), u => ESV{acc, "", "an unterminated string literal"}))))
    case SCon{+h, +t} MQrun{}:
      S.choose(ESV, Char.is_eq(esc_char(cur), q), u => S.choose(ESV, Nat.is_eq(v, 3n), u => esc(t, q, True{}, raw, acc, "", MQx{}, 1n, k, U32.to_nat(Char.to_u32(h))), u => esc(t, q, tri, raw, acc, "", MQrun{}, 1n+v, k, U32.to_nat(Char.to_u32(h)))), u => S.choose(ESV, Nat.is_eq(v, 3n), u => S.choose(ESV, Char.is_eq(esc_char(cur), Chr{92}) && Bool.not(raw), u => esc(t, q, True{}, raw, acc, "", MEsc{}, 0n, k, U32.to_nat(Char.to_u32(h))), u => esc(t, q, True{}, raw, acc, SCon{esc_char(cur), ""}, MBody{}, 0n, k, U32.to_nat(Char.to_u32(h)))), u => S.choose(ESV, Nat.is_eq(v, 2n), u => esc(t, q, tri, raw, acc, "", MGap{}, 0n, 0n, U32.to_nat(Char.to_u32(h))), u => S.choose(ESV, Char.is_eq(esc_char(cur), Chr{92}) && Bool.not(raw), u => esc(t, q, False{}, raw, acc, "", MEsc{}, 0n, k, U32.to_nat(Char.to_u32(h))), u => esc(t, q, False{}, raw, acc, SCon{esc_char(cur), ""}, MBody{}, 0n, k, U32.to_nat(Char.to_u32(h)))))))
    case _ _:
      ESV{acc, "", "an unterminated string literal"}

def str_lit(+raw: String) -> SV:
  +got : ESV = esc(String.drop(raw, 1n), Chr{0}, False{}, False{}, "", "", MGap{}, 0n, 0n, U32.to_nat(Char.to_u32(headc(raw))))
  S.choose(SV, String.is_empty(gv_f(got)), u => SV{gv_s(got), ""}, u => SV{"", gv_f(got)})

# Tables

# ======

type AC is Data:
  AC{env: Env, idx: Nat}

def ac_env(+p: AC) -> Env:
  match p:
    case AC{env, idx}:
      env

def ac_idx(+p: AC) -> Nat:
  match p:
    case AC{env, idx}:
      idx

def add_const(+env: Env, +v: Val) -> AC:
  Env{+cs, nc, +gs, ng, +fs, +ns, nn} = env
  AC{Env{Con{v, cs}, 1n+nc, gs, ng, fs, ns, nn}, nc}

def local_find(+ns: List<&2, String>, +name: String, +i: Nat) -> Maybe<&2, Nat>:
  match ns:
    case Nil{}:
      None{}
    case Con{h, t}:
      S.choose(Maybe<&2, Nat>, String.eq(h, name), u => Some{i}, u => local_find(t, name, 1n+i))

def global_find(+gs: List<&2, String>, +name: String, +i: Nat) -> Maybe<&2, Nat>:
  match gs:
    case Nil{}:
      None{}
    case Con{h, t}:
      S.choose(Maybe<&2, Nat>, String.eq(h, name), u => Some{i}, u => global_find(t, name, 1n+i))

type GS is Data:
  GS{env: Env, slot: Nat}

def gs_env(+p: GS) -> Env:
  match p:
    case GS{env, slot}:
      env

def gs_slot(+p: GS) -> Nat:
  match p:
    case GS{env, slot}:
      slot

# The global slot: found by name, else a fresh row at the end.
def gslot_put(+found: Maybe<&2, Nat>, +env: Env, +name: String, +gs: List<&2, String>, +ng: Nat) -> GS:
  match found:
    case Some{i}:
      GS{env, Nat.sub(ng, 1n+i)}
    case None{}:
      Env{+cs, nc, gs2, ng2, +fs, +ns, nn} = env
      GS{Env{cs, nc, Con{name, gs}, 1n+ng, fs, ns, nn}, ng}

def gslot(+env: Env, +name: String) -> GS:
  Env{+cs, nc, +gs, +ng, +fs, +ns, nn} = env
  gslot_put(global_find(gs, name, 0n), Env{cs, nc, gs, ng, fs, ns, nn}, name, gs, ng)

def func_hit(+fs: List<&2, Def>, +name: String) -> Bool:
  match fs:
    case Nil{}:
      False{}
    case Con{Def{nm, params, np, body}, t}:
      S.choose(Bool, String.eq(nm, name), u => True{}, u => func_hit(t, name))

def func_ix(+fs: List<&2, Def>, +name: String, +i: Nat) -> Nat:
  match fs:
    case Nil{}:
      0n
    case Con{Def{nm, params, np, body}, t}:
      S.choose(Nat, String.eq(nm, name), u => i, u => func_ix(t, name, 1n+i))

def func_find(+fs: List<&2, Def>, +name: String, +i: Nat) -> Maybe<&2, Nat>:
  match fs:
    case Nil{}:
      None{}
    case Con{Def{nm, params, np, body}, t}:
      S.choose(Maybe<&2, Nat>, String.eq(nm, name), u => Some{i}, u => func_find(t, name, 1n+i))

def f_np(+f: Func) -> Nat:
  match f:
    case Func{np, nl, code}:
      np

def f_nl(+f: Func) -> Nat:
  match f:
    case Func{np, nl, code}:
      nl

def f_code(+f: Func) -> List<&2, Instr>:
  match f:
    case Func{np, nl, code}:
      code

def nparams_at(+fs: List<&2, Def>, i: Nat) -> Nat:
  match fs i:
    case Con{Def{nm, params, np, body}, t} 0n:
      np
    case Con{d, t} 1n+p:
      nparams_at(t, p)
    case _ _:
      0n

# Operator tags -> dense opcode rows; 99 is not an opcode.
def binop_code(+tag: String) -> U32:
  S.choose(U32, String.eq(tag, "Add"), u => 6, u =>
    S.choose(U32, String.eq(tag, "Sub"), u => 7, u =>
      S.choose(U32, String.eq(tag, "Mult"), u => 8, u =>
        S.choose(U32, String.eq(tag, "FloorDiv"), u => 9, u =>
          S.choose(U32, String.eq(tag, "Mod"), u => 10, u => 99)))))

def cmp_code(+tag: String) -> U32:
  S.choose(U32, String.eq(tag, "Lt"), u => 11, u =>
    S.choose(U32, String.eq(tag, "LtE"), u => 12, u =>
      S.choose(U32, String.eq(tag, "Gt"), u => 13, u =>
        S.choose(U32, String.eq(tag, "GtE"), u => 14, u =>
          S.choose(U32, String.eq(tag, "Eq"), u => 15, u =>
            S.choose(U32, String.eq(tag, "NotEq"), u => 16, u => 99))))))

# The local table of a function: params first, then every assigned name
# (Python's own rule: a name assigned anywhere in the body is local).
def has_name(+ns: List<&2, String>, +name: String) -> Bool:
  match ns:
    case Nil{}:
      False{}
    case Con{h, t}:
      S.choose(Bool, String.eq(h, name), u => True{}, u => has_name(t, name))

def add_name(+ns: List<&2, String>, +name: String) -> List<&2, String>:
  Bool.pick(List<&2, String>, has_name(ns, name), ns, Con{name, ns})

def prewalk_target(+j: S.Json, +ns: List<&2, String>) -> List<&2, String>:
  S.choose(List<&2, String>, String.eq(jtag(j), "Name"), u => add_name(ns, jstr(jfield(j, "id"))), u => ns)

def prewalk_targets(+js: S.Json, +ns: List<&2, String>) -> List<&2, String>:
  match js:
    case S.JEnd{}:
      ns
    case S.JItem{one, rest}:
      prewalk_targets(rest, prewalk_target(one, ns))
    case _:
      ns

# The statement kinds the prewalk looks into, read off the tag once: a match
# over string literals emits a per-character bit tree, which nested past
# clang's 256-bracket limit in the C lane.
type PK is Data:
  PAssign{}
  PAugAssign{}
  PAnnAssign{}
  PIf{}
  PWhile{}
  POther{}

def pw_kind(+tag: String) -> PK:
  S.choose(PK, String.eq(tag, "Assign"), u => PAssign{}, u =>
    S.choose(PK, String.eq(tag, "AugAssign"), u => PAugAssign{}, u =>
      S.choose(PK, String.eq(tag, "AnnAssign"), u => PAnnAssign{}, u =>
        S.choose(PK, String.eq(tag, "If"), u => PIf{}, u =>
          S.choose(PK, String.eq(tag, "While"), u => PWhile{}, u => POther{})))))

type PW is Data:
  PWOne{kind: PK, j: S.Json}
  PWChain{js: S.Json}

# The local-name prewalk: one self-recursive def (a chain and a statement
# would be mutually recursive otherwise), the leaf helpers beside it.
def prewalk(fuel: Nat, job: PW, +ns: List<&2, String>) -> List<&2, String>:
  match fuel job:
    case 0n _:
      ns
    case 1n++left PWChain{js}:
      match js:
        case S.JItem{+one, rest}:
          +kind : PK = pw_kind(jtag(one))
          prewalk(left, PWChain{rest}, prewalk(left, PWOne{kind, one}, ns))
        case _:
          ns
    case 1n++left PWOne{+kind, +j}:
      match kind:
        case PAssign{}:
          prewalk_targets(jitems(jfield(j, "targets")), ns)
        case PAugAssign{}:
          prewalk_target(jfield(j, "target"), ns)
        case PAnnAssign{}:
          S.choose(List<&2, String>, jnull(jfield(j, "value")), u => ns, u => prewalk_target(jfield(j, "target"), ns))
        case PIf{}:
          prewalk(left, PWChain{jitems(jfield(j, "orelse"))}, prewalk(left, PWChain{jitems(jfield(j, "body"))}, ns))
        case PWhile{}:
          prewalk(left, PWChain{jitems(jfield(j, "orelse"))}, prewalk(left, PWChain{jitems(jfield(j, "body"))}, ns))
        case POther{}:
          ns

# Fuels are derived from the module (runtime data), never written as one
# long constant: a folded constant fuel expands unary in the emitter.
def stmt_fuel(+body: S.Json) -> Nat:
  Nat.mul(Nat.mul(100n, 100n), Nat.add(count(body, 1n), 1n))

# Pass 1: the module's defs, collected reversed.
type GD is Data:
  GD{defs: List<&2, Def>, fault: String}

def gd_defs(+p: GD) -> List<&2, Def>:
  match p:
    case GD{defs, fault}:
      defs

def gd_flt(+p: GD) -> String:
  match p:
    case GD{defs, fault}:
      fault

type PN is Data:
  PN{names: List<&2, String>, fault: String}

def pn_names(+p: PN) -> List<&2, String>:
  match p:
    case PN{names, fault}:
      names

def pn_flt(+p: PN) -> String:
  match p:
    case PN{names, fault}:
      fault

def param_names(+js: S.Json, +acc: List<&2, String>, +flt: String) -> PN:
  match js:
    case S.JEnd{}:
      PN{acc, flt}
    case S.JItem{one, rest}:
      S.choose(PN, String.eq(jtag(one), "arg"), u =>
        param_names(rest, Con{jstr(jfield(one, "arg")), acc}, flt), u => PN{acc, "expected parameter"})
    case _:
      PN{acc, "expected parameter"}

def take_def(+j: S.Json, +defs: List<&2, Def>) -> GD:
  +decorated = jitems(jfield(j, "decorator_list"))
  +arguments = jfield(j, "args")
  S.choose(GD, Bool.not(jnull(jfield(arguments, "vararg"))) || Bool.not(jnull(jfield(arguments, "kwarg"))) || Bool.not(jend(jitems(jfield(arguments, "kwonlyargs")))),
    u => GD{defs, "*args, keyword-only and **kwargs parameters are outside the subset"}, u =>
    S.choose(GD, Bool.not(jend(decorated)), u => GD{defs, "decorators are outside the subset"}, u =>
      +po : PN = param_names(jitems(jfield(arguments, "posonlyargs")), Nil{}, "")
      +pa : PN = param_names(jitems(jfield(arguments, "args")), pn_names(po), "")
      S.choose(GD, String.is_empty(pn_flt(po)) && String.is_empty(pn_flt(pa)), u =>
        +params = List.reverse(&2, String, pn_names(pa))
        GD{Con{Def{jstr(jfield(j, "name")), params, List.length(&2, String, params), jitems(jfield(j, "body"))}, defs}, ""}, u =>
        GD{defs, pick_fault(pn_flt(po), pn_flt(pa))})))


def collect(+js: S.Json, +defs: List<&2, Def>) -> GD:
  match js:
    case S.JEnd{}:
      GD{defs, ""}
    case S.JItem{+one, +rest}:
      +got : GD = collect(rest, defs)
      +tag : String = jtag(one)
      S.choose(GD, String.eq(tag, "FunctionDef"), u =>
        +td : GD = take_def(one, gd_defs(got))
        GD{gd_defs(td), pick_fault(gd_flt(got), gd_flt(td))}, u =>
        got)
    case _:
      GD{defs, ""}

# Pass 2 prep: each module-level def becomes a _DefBind statement where it
# stands -- the k-th def (source order, its function index) is bound to its
# name when control reaches it, as CPython binds it, so a call that runs
# first is a NameError rather than a call.
def def_bind(+name: String, +k: Nat) -> S.Json:
  S.JObj{S.JField{"tag", S.JStr{"_DefBind"}, S.JField{"name", S.JStr{name}, S.JField{"index", S.JNum{k}, S.JEnd{}}}}}

def jnum(+j: S.Json) -> Nat:
  match j:
    case S.JNum{n}:
      n
    case _:
      0n

def bind_defs(+js: S.Json, +k: Nat) -> S.Json:
  match js:
    case S.JEnd{}:
      S.JEnd{}
    case S.JItem{+one, rest}:
      S.choose(S.Json, String.eq(jtag(one), "FunctionDef"), u => S.JItem{def_bind(jstr(jfield(one, "name")), k), bind_defs(rest, 1n+k)}, u => S.JItem{one, bind_defs(rest, k)})
    case _:
      S.JEnd{}

# Expressions
# ===========

def bop_put(+frags: List<&2, Frg>, +end: Nat, +is_and: Bool, +first: Nat, +acc: List<&2, Instr>) -> List<&2, Instr>:
  match frags first:
    case Nil{} _:
      acc
    case Con{Frg{c, l, op}, t} 0n:
      bop_put(t, end, is_and, 1n, join(c, acc))
    case Con{Frg{c, l, op}, t} 1n+p:
      bop_put(t, end, is_and, 1n+p, join(acc, Con{Instr{Bool.pick(U32, is_and, 21, 22), end, 0n}, c}))

# Assembles a Compare: the leftmost operand (op 98), then each comparator and
# its opcode. Chains are refused in cexp's Compare arm, so only the 0n arm
# runs today; the 1n+p arm is the (a<b) and (b<c) shape, which would evaluate
# a middle twice, kept for when chains land with a DUP.
def cmp_put(+frags: List<&2, Frg>, +end: Nat, +first: Nat, +acc: List<&2, Instr>) -> List<&2, Instr>:
  match frags first:
    case Nil{} _:
      acc
    case Con{Frg{c, l, 98}, t} _:
      cmp_put(t, end, 1n, join(acc, c))
    case Con{Frg{c, l, op}, t} 0n:
      cmp_put(t, end, 1n, join(one(op, 0n, 0n), c))
    case Con{Frg{c, l, op}, t} 1n+p:
      cmp_put(t, end, 1n+p, join(acc, Con{Instr{5, 0n, 0n}, Con{Instr{19, end, 0n}, join(one(op, 0n, 0n), c)}}))

# A constant: one CONST row into the growing pool.
def const_cx(+env: Env, +v: Val) -> Cx:
  +made : AC = add_const(env, v)
  Cx{one(0, ac_idx(made), 0n), 1n, ac_env(made), ""}

type EK is Data:
  EConstant{}
  EName{}
  EBinOp{}
  EUnaryOp{}
  EBoolOp{}
  ECompare{}
  ECall{}
  EIfExp{}
  ESubscript{}
  EList{}
  EDict{}
  EOther{}

# The expression's kind, read off its tag once. The dispatch below is a
# constructor match: a match over string literals is emitted as a
# per-character tree with the arm bodies under it, and at eleven arms of this
# size that drove the C emitter past 14 GB.
def expr_kind(+tag: String) -> EK:
  S.choose(EK, String.eq(tag, "Constant"), u => EConstant{}, u =>
    S.choose(EK, String.eq(tag, "Name"), u => EName{}, u =>
    S.choose(EK, String.eq(tag, "BinOp"), u => EBinOp{}, u =>
    S.choose(EK, String.eq(tag, "UnaryOp"), u => EUnaryOp{}, u =>
    S.choose(EK, String.eq(tag, "BoolOp"), u => EBoolOp{}, u =>
    S.choose(EK, String.eq(tag, "Compare"), u => ECompare{}, u =>
    S.choose(EK, String.eq(tag, "Call"), u => ECall{}, u =>
    S.choose(EK, String.eq(tag, "IfExp"), u => EIfExp{}, u =>
    S.choose(EK, String.eq(tag, "Subscript"), u => ESubscript{}, u =>
    S.choose(EK, String.eq(tag, "List"), u => EList{}, u =>
    S.choose(EK, String.eq(tag, "Dict"), u => EDict{}, u =>
      EOther{})))))))))))

# One self-recursive def compiles every expression shape. Many is a JItem
# chain (call and print arguments, in order). BOp and CmpJ are the two-pass
# chains: the values are compiled first (the walk), then assembled with the
# end target every keep-jump needs. Tag1 re-enters with the expression's
# kind as a field, the one legal scrutinee for the dispatch.
type Job is Data:
  One{j: S.Json}
  Many{js: S.Json}
  BOp{js: S.Json, base0: Nat, acc: List<&2, Frg>, sum: Nat, n: Nat, flt: String, is_and: Bool}
  CmpJ{ops: S.Json, vals: S.Json, base0: Nat, acc: List<&2, Frg>, sum: Nat, n: Nat, flt: String}
  Tag1{kind: EK, j: S.Json}

def slot_put(+found: Maybe<&2, Nat>, +env: Env, +name: String, is_store: Bool) -> Cx:
  match found:
    case Some{i}:
      Cx{one(Bool.pick(U32, is_store, 2, 1), i, 0n), 1n, env, ""}
    case None{}:
      +slot : GS = gslot(env, name)
      Cx{one(Bool.pick(U32, is_store, 4, 3), gs_slot(slot), 0n), 1n, gs_env(slot), ""}

def name_cx(+env: Env, +name: String, +is_store: Bool) -> Cx:
  Env{+cs, nc, +gs, ng, +fs, +ns, nn} = env
  slot_put(local_find(ns, name, 0n), Env{cs, nc, gs, ng, fs, ns, nn}, name, is_store)

# CPython's builtins, which a program may read without binding them. The
# subset calls print and len by name and has none as a value: reading one
# unbound is refused, not reported as a NameError that CPython never raises.
def is_builtin(+name: String) -> Bool:
  String.contains(" abs aiter all anext any ascii bin bool breakpoint bytearray bytes callable chr classmethod compile complex copyright credits delattr dict dir divmod enumerate eval exec exit filter float format frozenset getattr globals hasattr hash help hex id input int isinstance issubclass iter len license list locals map max memoryview min next object oct open ord pow print property quit range repr reversed round set setattr slice sorted staticmethod str sum super tuple type vars zip BaseException BaseExceptionGroup Exception ExceptionGroup ArithmeticError AssertionError AttributeError BlockingIOError BrokenPipeError BufferError BytesWarning ChildProcessError ConnectionAbortedError ConnectionError ConnectionRefusedError ConnectionResetError DeprecationWarning EOFError EncodingWarning EnvironmentError FileExistsError FileNotFoundError FloatingPointError FutureWarning GeneratorExit IOError ImportError ImportWarning IndentationError IndexError InterruptedError IsADirectoryError KeyError KeyboardInterrupt LookupError MemoryError ModuleNotFoundError NameError NotADirectoryError NotImplemented NotImplementedError OSError OverflowError PendingDeprecationWarning PermissionError ProcessLookupError RecursionError ReferenceError ResourceWarning RuntimeError RuntimeWarning StopAsyncIteration StopIteration SyntaxError SyntaxWarning SystemError SystemExit TabError TimeoutError TypeError UnboundLocalError UnicodeDecodeError UnicodeEncodeError UnicodeError UnicodeTranslateError UnicodeWarning UserWarning ValueError Warning ZeroDivisionError Ellipsis ", String.append(String.append(" ", name), " "))

def is_usub(+j: S.Json) -> Bool:
  String.eq(jtag(j), "UnaryOp") && String.eq(jstr(jfield(jfield(j, "op"), "tag")), "USub")

def store_target(+j: S.Json, +base: Nat, +env: Env) -> Cx:
  S.choose(Cx, String.eq(jtag(j), "Name"), u => name_cx(env, jstr(jfield(j, "id")), True{}), u =>
    Cx{Nil{}, 0n, env, "the assignment target is outside the subset"})

def load_target(+j: S.Json, +base: Nat, +env: Env) -> Cx:
  S.choose(Cx, String.eq(jtag(j), "Name"), u => name_cx(env, jstr(jfield(j, "id")), False{}), u =>
    Cx{Nil{}, 0n, env, "the assignment target is outside the subset"})

def cexp(+fuel: Nat, +job: Job, +base: Nat, +env: Env) -> Cx:
  match fuel job:
    case 0n _:
      Cx{Nil{}, 0n, env, "the compiler ran out of fuel"}
    case 1n++left Many{js}:
      match js:
        case S.JEnd{}:
          Cx{Nil{}, 0n, env, ""}
        case S.JItem{+one, +rest}:
          +head : Cx = cexp(left, One{one}, base, env)
          +tail : Cx = cexp(left, Many{rest}, (cx_len(head) + base : Nat), cx_env(head))
          Cx{join(cx_code(tail), cx_code(head)), (cx_len(head) + cx_len(tail) : Nat), cx_env(tail), pick_fault(cx_fault(head), cx_fault(tail))}
        case _:
          Cx{Nil{}, 0n, env, ""}
    case 1n++left BOp{js, base0, acc, sum, n, flt, is_and}:
      match js:
        case S.JEnd{}:
          +extra : Nat = Nat.sub(n, 1n)
          +total = (sum + extra : Nat)
          Cx{bop_put(acc, (total + base0 : Nat), is_and, 0n, Nil{}), total, env, flt}
        case S.JItem{+one, +rest}:
          +head : Cx = cexp(left, One{one}, base, env)
          cexp(left, BOp{rest, base0, Con{Frg{cx_code(head), cx_len(head), 0}, acc}, (sum + cx_len(head) : Nat), 1n+n, pick_fault(flt, cx_fault(head)), is_and},
            (cx_len(head) + base + 1n : Nat), cx_env(head))
        case _:
          Cx{Nil{}, 0n, env, flt}
    case 1n++left CmpJ{ops, vals, base0, acc, sum, n, flt}:
      match ops vals:
        case S.JEnd{} _:
          +extra : Nat = Nat.sub((3n * n : Nat), 2n)
          +total = (sum + extra : Nat)
          Cx{cmp_put(acc, (total + base0 : Nat), 0n, Nil{}), total, env, flt}
        case S.JItem{+op, +opr} S.JItem{+one, +rest}:
          +code = cmp_code(jstr(jfield(op, "tag")))
          S.choose(Cx, U32.is_eq(code, 99), u => Cx{Nil{}, 0n, env, "the comparison is outside the subset"}, u =>
            +head : Cx = cexp(left, One{one}, base, env)
            cexp(left, CmpJ{opr, rest, base0, Con{Frg{cx_code(head), cx_len(head), code}, acc}, (sum + cx_len(head) : Nat), 1n+n, pick_fault(flt, cx_fault(head))},
              (cx_len(head) + base + 3n : Nat), cx_env(head)))
        case _ _:
          Cx{Nil{}, 0n, env, flt}
    case 1n++left One{j}:
      cexp(left, Tag1{expr_kind(jtag(j)), j}, base, env)
    case 1n++left Tag1{kind, j}:
      match kind:
        case EConstant{}:
          +raw = jstr(jfield(j, "_raw"))
          S.choose(Cx, String.eq(raw, "True"), u => const_cx(env, VBool{True{}}), u =>
            S.choose(Cx, String.eq(raw, "False"), u => const_cx(env, VBool{False{}}), u =>
              S.choose(Cx, String.eq(raw, "None"), u => const_cx(env, VNone{}), u =>
                S.choose(Cx, Char.is_digit(headc(raw)) || Char.is_eq(headc(raw), '.'), u =>
                  +nv : NV = number_value(raw)
                  S.choose(Cx, String.is_empty(nv_f(nv)), u => const_cx(env, VInt{nv_n(nv)}), u => Cx{Nil{}, 0n, env, nv_f(nv)}), u =>
                  +sv : SV = str_lit(raw)
                  S.choose(Cx, String.is_empty(sv_f(sv)), u => const_cx(env, VStr{sv_s(sv)}), u => Cx{Nil{}, 0n, env, sv_f(sv)})))))
        case EName{}:
          Env{+cs, +nc, +gs, +ng, +fs, +ns, +nn} = env
          +name = jstr(jfield(j, "id"))
          S.choose(Cx, func_hit(fs, name) && Bool.not(has_name(ns, name)), u => Cx{Nil{}, 0n, Env{cs, nc, gs, ng, fs, ns, nn}, "functions as values are outside the subset"}, u =>
            S.choose(Cx, is_builtin(name) && Bool.not(has_name(ns, name)) && Bool.not(has_name(gs, name)), u =>
              Cx{Nil{}, 0n, Env{cs, nc, gs, ng, fs, ns, nn}, String.append(String.append("the builtin ", name), " is outside the subset")}, u =>
              name_cx(Env{cs, nc, gs, ng, fs, ns, nn}, name, False{})))
        case EBinOp{}:
          +lft : Cx = cexp(left, One{jfield(j, "left")}, base, env)
          +rgt : Cx = cexp(left, One{jfield(j, "right")}, (cx_len(lft) + base : Nat), cx_env(lft))
          +code = binop_code(jstr(jfield(jfield(j, "op"), "tag")))
          S.choose(Cx, U32.is_eq(code, 99), u => Cx{Nil{}, 0n, cx_env(rgt), "the operator is outside the subset"}, u =>
            Cx{join(one(code, 0n, 0n), join(cx_code(rgt), cx_code(lft))), 1n+(cx_len(lft) + cx_len(rgt) : Nat), cx_env(rgt),
              pick_fault(cx_fault(lft), cx_fault(rgt))})
        case EUnaryOp{}:
          +op = jstr(jfield(jfield(j, "op"), "tag"))
          S.choose(Cx, String.eq(op, "UAdd"), u => cexp(left, One{jfield(j, "operand")}, base, env), u =>
            S.choose(Cx, String.eq(op, "Not"), u =>
              +inner : Cx = cexp(left, One{jfield(j, "operand")}, base, env)
              Cx{join(one(17, 0n, 0n), cx_code(inner)), 1n+cx_len(inner), cx_env(inner), cx_fault(inner)}, u =>
              Cx{Nil{}, 0n, env, "negatives and ~ are outside the subset"}))
        case EBoolOp{}:
          cexp(left, BOp{jitems(jfield(j, "values")), base, Nil{}, 0n, 0n, "", String.eq(jstr(jfield(jfield(j, "op"), "tag")), "And")}, base, env)
        case ECompare{}:
          +ops = jitems(jfield(j, "ops"))
          S.choose(Cx, Nat.is_eq(jcount(ops), 1n), u =>
            +lft : Cx = cexp(left, One{jfield(j, "left")}, base, env)
            cexp(left, CmpJ{ops, jitems(jfield(j, "comparators")), base, Con{Frg{cx_code(lft), cx_len(lft), 98}, Nil{}}, cx_len(lft), 0n, cx_fault(lft)},
              (cx_len(lft) + base : Nat), cx_env(lft)), u =>
            Cx{Nil{}, 0n, env, "chained comparisons are outside the subset"})
        case ECall{}:
          Env{+cs, +nc, +gs, +ng, +fs, +ns, +nn} = env
          +fn = jfield(j, "func")
          +kw = jitems(jfield(j, "keywords"))
          +args = jitems(jfield(j, "args"))
          S.choose(Cx, Bool.not(String.eq(jtag(fn), "Name")), u => Cx{Nil{}, 0n, Env{cs, nc, gs, ng, fs, ns, nn}, "calling a non-name is outside the subset"}, u =>
            S.choose(Cx, Bool.not(jend(kw)), u => Cx{Nil{}, 0n, Env{cs, nc, gs, ng, fs, ns, nn}, "keyword arguments are outside the subset"}, u =>
              +name = jstr(jfield(fn, "id"))
              S.choose(Cx, String.eq(name, "print"), u =>
                +argv : Cx = cexp(left, Many{args}, base, Env{cs, nc, gs, ng, fs, ns, nn})
                Cx{join(one(25, 0n, jcount(args)), cx_code(argv)), 1n+cx_len(argv), cx_env(argv), cx_fault(argv)}, u =>
                S.choose(Cx, func_hit(fs, name), u =>
                  +i : Nat = func_ix(fs, name, 0n)
                  +callee : Cx = name_cx(Env{cs, nc, gs, ng, fs, ns, nn}, name, False{})
                  +argv : Cx = cexp(left, Many{args}, (cx_len(callee) + base : Nat), cx_env(callee))
                  S.choose(Cx, Nat.is_eq(jcount(args), nparams_at(fs, i)), u =>
                    Cx{join(one(23, i, jcount(args)), join(cx_code(argv), cx_code(callee))), (1n + (cx_len(callee) + cx_len(argv) : Nat) : Nat), cx_env(argv), cx_fault(argv)}, u =>
                    Cx{Nil{}, 0n, cx_env(argv), String.append(name, " is called with the wrong number of arguments")}), u =>
                  S.choose(Cx, String.eq(name, "len"), u =>
                    S.choose(Cx, Nat.is_eq(jcount(args), 1n), u =>
                      +argv : Cx = cexp(left, Many{args}, base, Env{cs, nc, gs, ng, fs, ns, nn})
                      Cx{join(one(27, 0n, 0n), cx_code(argv)), 1n+cx_len(argv), cx_env(argv), cx_fault(argv)}, u =>
                      Cx{Nil{}, 0n, Env{cs, nc, gs, ng, fs, ns, nn}, String.append(name, " is called with the wrong number of arguments")}), u =>
                    Cx{Nil{}, 0n, Env{cs, nc, gs, ng, fs, ns, nn}, String.append(name, " is not a defined function")})))))
        case EIfExp{}:
          +test : Cx = cexp(left, One{jfield(j, "test")}, base, env)
          +body : Cx = cexp(left, One{jfield(j, "body")}, (cx_len(test) + base + 1n : Nat), cx_env(test))
          +other : Cx = cexp(left, One{jfield(j, "orelse")}, (cx_len(test) + base + cx_len(body) + 2n : Nat), cx_env(body))
          Cx{join(cx_code(other), join(one(18, (cx_len(test) + base + cx_len(body) + cx_len(other) + 2n : Nat), 0n),
              join(cx_code(body), join(one(19, (cx_len(test) + base + cx_len(body) + 2n : Nat), 0n), cx_code(test))))),
            (cx_len(test) + cx_len(body) + cx_len(other) + 2n : Nat), cx_env(other),
            pick_fault(cx_fault(test), pick_fault(cx_fault(body), cx_fault(other)))}
        case ESubscript{}:
          +val_j = jfield(j, "value")
          +slc_j = jfield(j, "slice")
          S.choose(Cx, String.eq(jtag(slc_j), "Slice"), u =>
            +lo_j = jfield(slc_j, "lower")
            +hi_j = jfield(slc_j, "upper")
            +st_j = jfield(slc_j, "step")
            S.choose(Cx, Bool.not(jnull(st_j)), u => Cx{Nil{}, 0n, env, "slice steps are outside the subset"}, u =>
              S.choose(Cx, is_usub(lo_j) || is_usub(hi_j), u => Cx{Nil{}, 0n, env, "negative indices are outside the subset"}, u =>
                +has_lo = Bool.not(jnull(lo_j))
                +has_hi = Bool.not(jnull(hi_j))
                +vs : Cx = cexp(left, One{val_j}, base, env)
                +lo_cx : Cx = S.choose(Cx, has_lo, u => cexp(left, One{lo_j}, (cx_len(vs) + base : Nat), cx_env(vs)), u => Cx{Nil{}, 0n, cx_env(vs), ""})
                +hi_cx : Cx = S.choose(Cx, has_hi, u => cexp(left, One{hi_j}, (cx_len(vs) + cx_len(lo_cx) + base : Nat), cx_env(lo_cx)), u => Cx{Nil{}, 0n, cx_env(lo_cx), ""})
                Cx{join(one(29, Bool.pick(Nat, has_lo, 1n, 0n), Bool.pick(Nat, has_hi, 1n, 0n)), join(cx_code(hi_cx), join(cx_code(lo_cx), cx_code(vs)))),
                  (1n + (cx_len(vs) + (cx_len(lo_cx) + cx_len(hi_cx) : Nat) : Nat) : Nat), cx_env(hi_cx),
                  pick_fault(cx_fault(vs), pick_fault(cx_fault(lo_cx), cx_fault(hi_cx)))})), u =>
            S.choose(Cx, is_usub(slc_j), u => Cx{Nil{}, 0n, env, "negative indices are outside the subset"}, u =>
              S.choose(Cx, String.eq(jtag(slc_j), "Tuple"), u => Cx{Nil{}, 0n, env, "the subscript is outside the subset"}, u =>
                +vs : Cx = cexp(left, One{val_j}, base, env)
                +idx : Cx = cexp(left, One{slc_j}, (cx_len(vs) + base : Nat), cx_env(vs))
                Cx{join(one(28, 0n, 0n), join(cx_code(idx), cx_code(vs))),
                  (1n + (cx_len(vs) + cx_len(idx) : Nat) : Nat), cx_env(idx),
                  pick_fault(cx_fault(vs), cx_fault(idx))})))
        case EList{}:
          Cx{Nil{}, 0n, env, "lists are outside the subset"}
        case EDict{}:
          Cx{Nil{}, 0n, env, "dicts are outside the subset"}
        case EOther{}:
          Cx{Nil{}, 0n, env, "the expression is outside the subset"}

# `a and b and c`: each value but the last keeps itself on the stack when it
# decides the answer (JIFK for and, JITK for or), else pops and asks the
# next -- CPython's operand-values semantics, not a bare short-circuit.
# Statements
# ==========

# Walk compiles a JItem chain; TagS re-enters with the statement's tag as a
# field and compiles exactly one statement, then joins the chain's rest.
type SJ is Data:
  Walk{js: S.Json}
  TagS{tag: String, one: S.Json, rest: S.Json}

def store_join(+fuel: Nat, +target: S.Json, +value: Cx, +base: Nat) -> Cx:
  Cx{vcode, vlen, venv, vfault} = value
  +stored : Cx = store_target(target, (vlen + base : Nat), venv)
  Cx{join(cx_code(stored), vcode), (vlen + cx_len(stored) : Nat), cx_env(stored), pick_fault(vfault, cx_fault(stored))}

def aug_assign(+fuel: Nat, +sj: S.Json, +base: Nat, +env: Env) -> Cx:
  +code = binop_code(jstr(jfield(jfield(sj, "op"), "tag")))
  S.choose(Cx, U32.is_eq(code, 99), u => Cx{Nil{}, 0n, env, "the augmented operator is outside the subset"}, u =>
    +loaded : Cx = load_target(jfield(sj, "target"), base, env)
    +value : Cx = cexp(fuel, One{jfield(sj, "value")}, (cx_len(loaded) + base : Nat), cx_env(loaded))
    +stored : Cx = store_target(jfield(sj, "target"), (cx_len(loaded) + base + cx_len(value) + 1n : Nat), cx_env(value))
    Cx{join(cx_code(stored), join(one(code, 0n, 0n), join(cx_code(value), cx_code(loaded)))),
      (cx_len(loaded) + cx_len(value) + cx_len(stored) + 1n : Nat), cx_env(stored),
      pick_fault(cx_fault(loaded), pick_fault(cx_fault(value), cx_fault(stored)))})

def cstmt(+fuel: Nat, +job: SJ, +base: Nat, +env: Env) -> Cx:
  match fuel job:
    case 0n _:
      Cx{Nil{}, 0n, env, "the compiler ran out of fuel"}
    case 1n++left Walk{js}:
      match js:
        case S.JEnd{}:
          Cx{Nil{}, 0n, env, ""}
        case S.JItem{+h, +t}:
          cstmt(left, TagS{jtag(h), h, t}, base, env)
        case _:
          Cx{Nil{}, 0n, env, ""}
    case 1n++left TagS{+tag, +sj, +rest}:
      +self : Cx = S.choose(Cx, String.eq(tag, "Pass"), u => Cx{Nil{}, 0n, env, ""}, u =>
        S.choose(Cx, String.eq(tag, "_DefBind"), u =>
          store_join(left, S.JObj{S.JField{"tag", S.JStr{"Name"}, S.JField{"id", jfield(sj, "name"), S.JEnd{}}}}, const_cx(env, VFunc{jnum(jfield(sj, "index"))}), base), u =>
        S.choose(Cx, String.eq(tag, "Expr"), u =>
          +inner : Cx = cexp(left, One{jfield(sj, "value")}, base, env)
          Cx{join(one(5, 0n, 0n), cx_code(inner)), 1n+cx_len(inner), cx_env(inner), cx_fault(inner)}, u =>
        S.choose(Cx, String.eq(tag, "Assign"), u =>
          +targets = jitems(jfield(sj, "targets"))
          S.choose(Cx, Nat.is_eq(count(targets, 0n), 1n), u =>
            +value : Cx = cexp(left, One{jfield(sj, "value")}, base, env)
            store_join(left, first_of(targets), value, base), u =>
            Cx{Nil{}, 0n, env, "multiple assignment targets are outside the subset"}), u =>
        S.choose(Cx, String.eq(tag, "AugAssign"), u => aug_assign(left, sj, base, env), u =>
        S.choose(Cx, String.eq(tag, "AnnAssign"), u =>
          S.choose(Cx, jnull(jfield(sj, "value")), u => Cx{Nil{}, 0n, env, ""}, u =>
            +value : Cx = cexp(left, One{jfield(sj, "value")}, base, env)
            store_join(left, jfield(sj, "target"), value, base)), u =>
        S.choose(Cx, String.eq(tag, "Return"), u =>
          S.choose(Cx, jnull(jfield(sj, "value")), u =>
            +made : AC = add_const(env, VNone{})
            Cx{join(one(24, 0n, 0n), one(0, ac_idx(made), 0n)), 2n, ac_env(made), ""}, u =>
            +value : Cx = cexp(left, One{jfield(sj, "value")}, base, env)
            Cx{join(one(24, 0n, 0n), cx_code(value)), 1n+cx_len(value), cx_env(value), cx_fault(value)}), u =>
        S.choose(Cx, String.eq(tag, "If"), u =>
          +test : Cx = cexp(left, One{jfield(sj, "test")}, base, env)
          +body : Cx = cstmt(left, Walk{jitems(jfield(sj, "body"))}, (cx_len(test) + base + 1n : Nat), cx_env(test))
          +other : Cx = cstmt(left, Walk{jitems(jfield(sj, "orelse"))}, (cx_len(test) + base + cx_len(body) + 2n : Nat), cx_env(body))
          Cx{join(cx_code(other), join(one(18, (cx_len(test) + base + cx_len(body) + cx_len(other) + 2n : Nat), 0n),
              join(cx_code(body), join(one(19, (cx_len(test) + base + cx_len(body) + 2n : Nat), 0n), cx_code(test))))),
            (cx_len(test) + cx_len(body) + cx_len(other) + 2n : Nat), cx_env(other),
            pick_fault(cx_fault(test), pick_fault(cx_fault(body), cx_fault(other)))}, u =>
        S.choose(Cx, String.eq(tag, "While"), u =>
          +test : Cx = cexp(left, One{jfield(sj, "test")}, base, env)
          +body : Cx = cstmt(left, Walk{jitems(jfield(sj, "body"))}, (cx_len(test) + base + 1n : Nat), cx_env(test))
          +other : Cx = cstmt(left, Walk{jitems(jfield(sj, "orelse"))}, (cx_len(test) + base + cx_len(body) + 2n : Nat), cx_env(body))
          Cx{join(cx_code(other), join(one(18, base, 0n),
              join(cx_code(body), join(one(19, (cx_len(test) + base + cx_len(body) + 2n : Nat), 0n), cx_code(test))))),
            (cx_len(test) + cx_len(body) + cx_len(other) + 2n : Nat), cx_env(other),
            pick_fault(cx_fault(test), pick_fault(cx_fault(body), cx_fault(other)))}, u =>
          Cx{Nil{}, 0n, env, "the statement is outside the subset"})))))))))
      +after : Cx = cstmt(left, Walk{rest}, (cx_len(self) + base : Nat), cx_env(self))
      Cx{join(cx_code(after), cx_code(self)), (cx_len(self) + cx_len(after) : Nat), cx_env(after), pick_fault(cx_fault(self), cx_fault(after))}

# Assign/AnnAssign: the value, then the store.
type BD is Data:
  BD{func: Func, env: Env, fault: String}

def bd_func(+p: BD) -> Func:
  match p:
    case BD{func, env, fault}:
      func

def bd_env(+p: BD) -> Env:
  match p:
    case BD{func, env, fault}:
      env

def bd_flt(+p: BD) -> String:
  match p:
    case BD{func, env, fault}:
      fault

def compile_def(+d: Def, +env: Env) -> BD:
  Def{name, +params, np, body} = d
  Env{+cs, +nc, +gs, +ng, +fs, +ns, +nn} = env
  +assigned = prewalk(stmt_fuel(body), PWChain{body}, Nil{})
  +names = List.append(&2, String, params, List.reverse(&2, String, assigned))
  +nnames = List.length(&2, String, names)
  +inner : Cx = cstmt(stmt_fuel(body), Walk{body}, 0n, Env{cs, nc, gs, ng, fs, names, nnames})
  +made : AC = add_const(cx_env(inner), VNone{})
  +full = join(one(24, 0n, 0n), join(one(0, ac_idx(made), 0n), cx_code(inner)))
  BD{Func{np, nnames, List.reverse(&2, Instr, full)}, ac_env(made), cx_fault(inner)}

type Built is Data:
  Built{funcs: List<&2, Func>, env: Env, fault: String}

def bu_funcs(+p: Built) -> List<&2, Func>:
  match p:
    case Built{funcs, env, fault}:
      funcs

def bu_env(+p: Built) -> Env:
  match p:
    case Built{funcs, env, fault}:
      env

def bu_flt(+p: Built) -> String:
  match p:
    case Built{funcs, env, fault}:
      fault

def compile_defs(+defs: List<&2, Def>, env: Env, acc: List<&2, Func>) -> Built:
  match defs:
    case Nil{}:
      Built{List.reverse(&2, Func, acc), env, ""}
    case Con{d, t}:
      +made : BD = compile_def(d, env)
      +rest : Built = compile_defs(t, bd_env(made), Con{bd_func(made), acc})
      Built{bu_funcs(rest), bu_env(rest), pick_fault(bd_flt(made), bu_flt(rest))}

def env_consts(+e: Env) -> List<&2, Val>:
  match e:
    case Env{cs, nc, gs, ng, fs, ns, nn}:
      cs

def env_nglobals(+e: Env) -> Nat:
  match e:
    case Env{cs, nc, gs, ng, fs, ns, nn}:
      ng

def build(+m: S.Module) -> Result<&2, &2, S.Error, Prog>:
  S.Module{body} = m
  +got : GD = collect(body, Nil{})
  +defs = gd_defs(got)
  +clean : S.Json = bind_defs(body, 0n)
  +main : Cx = cstmt(stmt_fuel(clean), Walk{clean}, 0n, Env{Nil{}, 0n, Nil{}, 0n, defs, Nil{}, 0n})
  +done : Built = compile_defs(defs, cx_env(main), Nil{})
  +halted : List<&2, Instr> = Con{Instr{26, 0n, 0n}, cx_code(main)}
  +fault = pick_fault(gd_flt(got), pick_fault(cx_fault(main), bu_flt(done)))
  +fin : Env = bu_env(done)
  S.choose(Result<&2, &2, S.Error, Prog>, String.is_empty(fault), u =>
    Done{Prog{bu_funcs(done), List.reverse(&2, Val, env_consts(fin)), env_nglobals(fin), List.reverse(&2, Instr, halted)}}, u =>
    Fail{S.PErr{S.Unsupported{}, S.Pos{1n, 0n}, fault}})

# Runtime
# =======

def val_at(+xs: List<&2, Val>, n: Nat) -> Val:
  match xs n:
    case Nil{} _:
      VNone{}
    case Con{h, t} 0n:
      h
    case Con{h, t} 1n+p:
      val_at(t, p)

def val_set(+xs: List<&2, Val>, n: Nat, +v: Val) -> List<&2, Val>:
  match xs n:
    case Nil{} _:
      Nil{}
    case Con{h, t} 0n:
      Con{v, t}
    case Con{h, t} 1n+p:
      Con{h, val_set(t, p, v)}

def func_at(+fs: List<&2, Func>, n: Nat) -> Func:
  match fs n:
    case Nil{} _:
      Func{0n, 0n, Nil{}}
    case Con{h, t} 0n:
      h
    case Con{h, t} 1n+p:
      func_at(t, p)

# Popping n values leaves them in stack order: the head of the result is the
# TOP of the stack -- the last value pushed, the right operand of a binop.
# Argument lists want the other order and reverse it at the two call sites.
def pop_vals(+p: Pop) -> List<&2, Val>:
  match p:
    case Pop{args, more}:
      args

def pop_more(+p: Pop) -> List<&2, Val>:
  match p:
    case Pop{args, more}:
      more

def pop_any(+p: Pop) -> Bool:
  match p:
    case Pop{args, more}:
      match args:
        case Nil{}:
          False{}
        case Con{h, t}:
          True{}

def pop_head(+p: Pop) -> Val:
  match p:
    case Pop{args, more}:
      val_at(args, 0n)

def pop_second(+p: Pop) -> Val:
  match p:
    case Pop{args, more}:
      val_at(args, 1n)

def pop_third(+p: Pop) -> Val:
  match p:
    case Pop{args, more}:
      val_at(args, 2n)

def frames_ok(+fs: List<&2, VFrame>) -> Bool:
  match fs:
    case Nil{}:
      False{}
    case Con{h, t}:
      True{}

def frame_of(+fs: List<&2, VFrame>) -> VFrame:
  match fs:
    case Nil{}:
      VFrame{Nil{}, Nil{}, Nil{}, 0n}
    case Con{h, t}:
      h

def frames_tail(+fs: List<&2, VFrame>) -> List<&2, VFrame>:
  match fs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      t

def vh_here(+f: VFrame) -> List<&2, Instr>:
  match f:
    case VFrame{here, rest, locals, depth}:
      here

def vh_rest(+f: VFrame) -> List<&2, Instr>:
  match f:
    case VFrame{here, rest, locals, depth}:
      rest

def vh_locals(+f: VFrame) -> List<&2, Val>:
  match f:
    case VFrame{here, rest, locals, depth}:
      locals

# The number of calls in flight: the depth the top frame recorded.
def frames_depth(+fs: List<&2, VFrame>) -> Nat:
  match fs:
    case Nil{}:
      0n
    case Con{VFrame{here, rest, locals, depth}, t}:
      depth

# CPython 3.11 holds 1000 frames, the module's among them: the 1000th call
# in flight is its RecursionError, and here the same call faults. Composed,
# never written long.
def call_cap() -> Nat:
  Nat.sub(Nat.mul(10n, 100n), 1n)

def cmp_pick(+which: Nat, +x: Nat, +y: Nat) -> Bool:
  match which:
    case 0n:
      Nat.is_ne(x, y)
    case 11n:
      Nat.is_lt(x, y)
    case 12n:
      Nat.is_le(x, y)
    case 13n:
      Nat.is_gt(x, y)
    case 14n:
      Nat.is_ge(x, y)
    case 15n:
      Nat.is_eq(x, y)
    case 1n+p:
      Nat.is_ne(x, y)


# Strings order as CPython orders them: code point by code point, a prefix
# first.
def str_pick(+which: Nat, +x: String, +y: String) -> Bool:
  match which:
    case 11n:
      String.is_lt(x, y)
    case 12n:
      String.is_le(x, y)
    case 13n:
      String.is_gt(x, y)
    case _:
      String.is_ge(x, y)

def pop_args(+n: Nat, +stack: List<&2, Val>) -> Pop:
  match n stack:
    case 0n _:
      Pop{Nil{}, stack}
    case 1n+p Con{v, t}:
      +below : Pop = pop_args(p, t)
      Pop{Con{v, pop_vals(below)}, pop_more(below)}
    case 1n+p Nil{}:
      Pop{Nil{}, Nil{}}

# A local past the parameters starts unset: reading it before its first
# store is CPython's UnboundLocalError, not a None.
def unsets(+n: Nat, +xs: List<&2, Val>) -> List<&2, Val>:
  match n:
    case 0n:
      xs
    case 1n+p:
      Con{VUnset{}, unsets(p, xs)}

def truthy(+v: Val) -> Bool:
  match v:
    case VInt{n}:
      Nat.is_ne(n, 0n)
    case VBool{b}:
      b
    case VNone{}:
      False{}
    case VStr{s}:
      Bool.not(String.is_empty(s))
    case VFunc{i}:
      True{}
    case VUnset{}:
      False{}

# CPython's bools are ints: True is 1 in arithmetic and comparison.
def nums_ok(+a: Val, +b: Val) -> Bool:
  match a b:
    case VInt{x} VInt{y}:
      True{}
    case VInt{x} VBool{q}:
      True{}
    case VBool{p} VInt{y}:
      True{}
    case VBool{p} VBool{q}:
      True{}
    case _ _:
      False{}

type NN is Data:
  NN{x: Nat, y: Nat}

def num2(+a: Val, +b: Val) -> NN:
  match a b:
    case VInt{x} VInt{y}:
      NN{x, y}
    case VInt{x} VBool{q}:
      NN{x, Bool.pick(Nat, q, 1n, 0n)}
    case VBool{p} VInt{y}:
      NN{Bool.pick(Nat, p, 1n, 0n), y}
    case VBool{p} VBool{q}:
      NN{Bool.pick(Nat, p, 1n, 0n), Bool.pick(Nat, q, 1n, 0n)}
    case _ _:
      NN{0n, 0n}

def nn_x(+p: NN) -> Nat:
  match p:
    case NN{x, y}:
      x

def nn_y(+p: NN) -> Nat:
  match p:
    case NN{x, y}:
      y

def vtext(+v: Val) -> String:
  match v:
    case VInt{n}:
      Nat.show(n)
    case VBool{b}:
      Bool.pick(String, b, "True", "False")
    case VNone{}:
      "None"
    case VStr{s}:
      s
    case VFunc{i}:
      "<function>"
    case VUnset{}:
      ""

# A string is its own text; anything else is not a string.
def is_str(+v: Val) -> Bool:
  match v:
    case VStr{s}:
      True{}
    case _:
      False{}

def str_of(+v: Val) -> String:
  match v:
    case VStr{s}:
      s
    case _:
      ""

def both_str(+a: Val, +b: Val) -> Bool:
  match a b:
    case VStr{x} VStr{y}:
      True{}
    case _ _:
      False{}

# Two strings off the stack: x is the right operand (the head), y the left.
type SS is Data:
  SS{x: String, y: String}

def str2(+a: Val, +b: Val) -> SS:
  match a b:
    case VStr{x} VStr{y}:
      SS{x, y}
    case _ _:
      SS{"", ""}

def ss_x(+p: SS) -> String:
  match p:
    case SS{x, y}:
      x

def ss_y(+p: SS) -> String:
  match p:
    case SS{x, y}:
      y

def is_num(+v: Val) -> Bool:
  match v:
    case VInt{n}:
      True{}
    case VBool{b}:
      True{}
    case _:
      False{}

def num_of(+v: Val) -> Nat:
  match v:
    case VInt{n}:
      n
    case VBool{b}:
      Bool.pick(Nat, b, 1n, 0n)
    case _:
      0n

def is_unset(+v: Val) -> Bool:
  match v:
    case VUnset{}:
      True{}
    case _:
      False{}

def is_func(+v: Val) -> Bool:
  match v:
    case VFunc{i}:
      True{}
    case _:
      False{}

def func_of(+v: Val) -> Nat:
  match v:
    case VFunc{i}:
      i
    case _:
      0n

# Python's == over the subset's values: strings by text, numbers (bools are
# ints) by value, None only with None; any other pair is unequal.
def val_eq(+a: Val, +b: Val) -> Bool:
  match a b:
    case VStr{x} VStr{y}:
      String.eq(x, y)
    case VNone{} VNone{}:
      True{}
    case _ _:
      S.choose(Bool, nums_ok(a, b), u => Nat.is_eq(num_of(a), num_of(b)), u => False{})

# str * int and int * str repeat the string; a bool counts as its int.
def str_rep(+a: Val, +b: Val) -> Bool:
  (is_str(a) && is_num(b)) || (is_num(a) && is_str(b))

def rep_s(+a: Val, +b: Val) -> String:
  S.choose(String, is_str(a), u => str_of(a), u => str_of(b))

def rep_n(+a: Val, +b: Val) -> Nat:
  S.choose(Nat, is_str(a), u => num_of(b), u => num_of(a))

# A string stops at 2**24 characters: a repeat can grow one exponentially,
# and past the ceiling it is refused rather than run out of memory.
def str_cap() -> Nat:
  Nat.mul(Nat.mul(256n, 256n), 256n)

def char_at(+s: String, +idx: Nat) -> String:
  String.take(String.drop(s, idx), 1n)

type SliceArgs is Data:
  SliceArgs{s: Val, lo: Val, hi: Val}

def slice_args(+picked: Pop, +a: Nat, +b: Nat) -> SliceArgs:
  match a b:
    case 0n 0n:
      SliceArgs{pop_head(picked), VNone{}, VNone{}}
    case 1n+p 0n:
      SliceArgs{pop_second(picked), pop_head(picked), VNone{}}
    case 0n 1n+q:
      SliceArgs{pop_second(picked), VNone{}, pop_head(picked)}
    case 1n+p 1n+q:
      SliceArgs{pop_third(picked), pop_second(picked), pop_head(picked)}

def sa_s(+sa: SliceArgs) -> Val:
  match sa:
    case SliceArgs{s, lo, hi}:
      s

def sa_lo(+sa: SliceArgs) -> Val:
  match sa:
    case SliceArgs{s, lo, hi}:
      lo

def sa_hi(+sa: SliceArgs) -> Val:
  match sa:
    case SliceArgs{s, lo, hi}:
      hi

def slice_str(+s: String, +has_lo: Nat, +has_hi: Nat, +lo_val: Val, +hi_val: Val) -> String:
  match has_lo has_hi:
    case 0n 0n:
      s
    case 1n+p 0n:
      String.drop(s, num_of(lo_val))
    case 0n 1n+q:
      String.take(s, num_of(hi_val))
    case 1n+p 1n+q:
      String.slice(s, num_of(lo_val), num_of(hi_val))

def line(+vs: List<&2, Val>, acc: String, first: Bool) -> String:
  match vs:
    case Nil{}:
      String.append(acc, "\n")
    case Con{h, t}:
      S.choose(String, first, u => line(t, vtext(h), False{}), u => line(t, String.append(String.append(acc, " "), vtext(h)), False{}))

def fault_run(funcs: List<&2, Func>, consts: List<&2, Val>, stack: List<&2, Val>, here: List<&2, Instr>,
  locals: List<&2, Val>, globals: List<&2, Val>, frames: List<&2, VFrame>, out: List<&2, String>, msg: String) -> Run:
  Run{funcs, consts, stack, here, Nil{}, locals, globals, frames, out, msg}

# The VM. One step per instruction: the fetch is the head of `rest` (a zipper,
# O(1)), a jump re-drops from `here`, a call saves the caller's zipper in a
# frame. The dispatch is the dense U32 match over op -- contiguous 0..29.
# The opcode kind: one constructor per dense opcode row. The dispatch over
# the run is a total constructor match (every body emitted once, no bit
# tree); op -> kind is the dense U32 match, contiguous 0..29 -- the new
# compiler's table shape, and what it lowers to is measured in the report.
type OpKind is Data:
  KConst{}
  KLoadL{}
  KStoreL{}
  KLoadG{}
  KStoreG{}
  KPop{}
  KAdd{}
  KSub{}
  KMul{}
  KDiv{}
  KMod{}
  KLt{}
  KLtE{}
  KGt{}
  KGtE{}
  KEq{}
  KNeq{}
  KNot{}
  KJump{}
  KJif{}
  KJit{}
  KJifk{}
  KJitk{}
  KCall{}
  KRet{}
  KPrint{}
  KHalt{}
  KLen{}
  KGetItem{}
  KSlice{}
  KBad{}

def op_kind(op: U32) -> OpKind:
  match op:
    case 0:
      KConst{}
    case 1:
      KLoadL{}
    case 2:
      KStoreL{}
    case 3:
      KLoadG{}
    case 4:
      KStoreG{}
    case 5:
      KPop{}
    case 6:
      KAdd{}
    case 7:
      KSub{}
    case 8:
      KMul{}
    case 9:
      KDiv{}
    case 10:
      KMod{}
    case 11:
      KLt{}
    case 12:
      KLtE{}
    case 13:
      KGt{}
    case 14:
      KGtE{}
    case 15:
      KEq{}
    case 16:
      KNeq{}
    case 17:
      KNot{}
    case 18:
      KJump{}
    case 19:
      KJif{}
    case 20:
      KJit{}
    case 21:
      KJifk{}
    case 22:
      KJitk{}
    case 23:
      KCall{}
    case 24:
      KRet{}
    case 25:
      KPrint{}
    case 26:
      KHalt{}
    case 27:
      KLen{}
    case 28:
      KGetItem{}
    case 29:
      KSlice{}
    case _:
      KBad{}

# The VM. One step per instruction: the fetch is the head of `rest` (a zipper,
# O(1)), a jump re-drops from `here`, a call saves the caller's zipper in a
# frame. Go fetches the next instruction and re-enters with its kind; the
# kind arms are the dispatch. Every stack match rides in a helper body: an
# arm of a literal match that matches an outer binder directly trips the
# checker's flatten.
# The VM's step mode. Go fetches the next instruction and re-enters flat: the
# kind match must be the arm's first statement (an intervening binder
# consumes the field's quantity in the checker's flatten), so Op carries the
# run's ten fields directly. One step per instruction: the fetch is the head
# of `rest` (a zipper, O(1)), a jump re-drops from `here`, a call saves the
# caller's zipper in a frame.
type Step is Data:
  Go{run: Run}
  Op{kind: OpKind, a: Nat, b: Nat, more: List<&2, Instr>, funcs: List<&2, Func>, consts: List<&2, Val>,
     stack: List<&2, Val>, here: List<&2, Instr>, rest: List<&2, Instr>, locals: List<&2, Val>,
     globals: List<&2, Val>, frames: List<&2, VFrame>, out: List<&2, String>, fault: String}

def step(+fuel: Nat, +job: Step) -> Run:
  match fuel job:
    case 0n _:
      Run{Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, "the VM ran out of fuel"}
    case 1n++left Go{Run{+funcs, +consts, +stack, +here, +rest, +locals, +globals, +frames, +out, +fault}}:
      match rest:
        case Nil{}:
          fault_run(funcs, consts, stack, here, locals, globals, frames, out, "stepped past the end of the code")
        case Con{Instr{op, a, b}, more}:
          step(left, Op{op_kind(op), a, b, more, funcs, consts, stack, here, rest, locals, globals, frames, out, fault})
    case 1n++left Op{+kind, +a, +b, +more, +funcs, +consts, +stack, +here, +rest, +locals, +globals, +frames, +out, +fault}:
      match kind:
        case KConst{}:
          step(left, Go{Run{funcs, consts, Con{val_at(consts, a), stack}, here, more, locals, globals, frames, out, fault}})
        case KLoadL{}:
          S.choose(Run, is_unset(val_at(locals, a)), u =>
            fault_run(funcs, consts, stack, here, locals, globals, frames, out, "a local read before assignment (UnboundLocalError)"), u =>
            step(left, Go{Run{funcs, consts, Con{val_at(locals, a), stack}, here, more, locals, globals, frames, out, fault}}))
        case KStoreL{}:
          +picked : Pop = pop_args(1n, stack)
          S.choose(Run, pop_any(picked), u =>
            step(left, Go{Run{funcs, consts, pop_more(picked), here, more, val_set(locals, a, pop_head(picked)), globals, frames, out, fault}}), u =>
            fault_run(funcs, consts, stack, here, locals, globals, frames, out, "stack underflow"))
        case KLoadG{}:
          S.choose(Run, is_unset(val_at(globals, a)), u =>
            fault_run(funcs, consts, stack, here, locals, globals, frames, out, "a name read before assignment (NameError)"), u =>
            step(left, Go{Run{funcs, consts, Con{val_at(globals, a), stack}, here, more, locals, globals, frames, out, fault}}))
        case KStoreG{}:
          +picked : Pop = pop_args(1n, stack)
          S.choose(Run, pop_any(picked), u =>
            step(left, Go{Run{funcs, consts, pop_more(picked), here, more, locals, val_set(globals, a, pop_head(picked)), frames, out, fault}}), u =>
            fault_run(funcs, consts, stack, here, locals, globals, frames, out, "stack underflow"))
        case KPop{}:
          +picked : Pop = pop_args(1n, stack)
          S.choose(Run, pop_any(picked), u =>
            step(left, Go{Run{funcs, consts, pop_more(picked), here, more, locals, globals, frames, out, fault}}), u =>
            fault_run(funcs, consts, stack, here, locals, globals, frames, out, "stack underflow"))
        case KAdd{}:
          +picked : Pop = pop_args(2n, stack)
          S.choose(Run, both_str(pop_head(picked), pop_second(picked)), u =>
            +ss : SS = str2(pop_head(picked), pop_second(picked))
            S.choose(Run, Nat.is_le((String.length(ss_y(ss)) + String.length(ss_x(ss)) : Nat), str_cap()), u =>
              step(left, Go{Run{funcs, consts, Con{VStr{String.append(ss_y(ss), ss_x(ss))}, pop_more(picked)}, here, more, locals, globals, frames, out, fault}}), u =>
              fault_run(funcs, consts, stack, here, locals, globals, frames, out, "a string past 2**24 characters is outside the subset")), u =>
            S.choose(Run, nums_ok(pop_head(picked), pop_second(picked)), u =>
              +xy : NN = num2(pop_second(picked), pop_head(picked))
              S.choose(Run, add_fits(nn_x(xy), nn_y(xy)), u =>
                step(left, Go{Run{funcs, consts, Con{VInt{(nn_x(xy) + nn_y(xy) : Nat)}, pop_more(picked)}, here, more, locals, globals, frames, out, fault}}), u =>
                fault_run(funcs, consts, stack, here, locals, globals, frames, out, "an int past 2**48 - 1 is outside the subset")), u =>
              fault_run(funcs, consts, stack, here, locals, globals, frames, out, "a non-number in +")))
        case KSub{}:
          +picked : Pop = pop_args(2n, stack)
          S.choose(Run, nums_ok(pop_head(picked), pop_second(picked)), u =>
            +xy : NN = num2(pop_second(picked), pop_head(picked))
            S.choose(Run, Nat.is_ge(nn_x(xy), nn_y(xy)), u =>
              step(left, Go{Run{funcs, consts, Con{VInt{Nat.sub(nn_x(xy), nn_y(xy))}, pop_more(picked)}, here, more, locals, globals, frames, out, fault}}), u =>
              fault_run(funcs, consts, stack, here, locals, globals, frames, out, "a negative result is outside the subset")), u =>
            fault_run(funcs, consts, stack, here, locals, globals, frames, out, "a non-number in -"))
        case KMul{}:
          +picked : Pop = pop_args(2n, stack)
          S.choose(Run, str_rep(pop_second(picked), pop_head(picked)), u =>
            +rs : String = rep_s(pop_second(picked), pop_head(picked))
            +rn : Nat = rep_n(pop_second(picked), pop_head(picked))
            S.choose(Run, Nat.is_eq(rn, 0n) || Nat.is_le(String.length(rs), Nat.div(str_cap(), rn)), u =>
              step(left, Go{Run{funcs, consts, Con{VStr{String.repeat(rs, rn)}, pop_more(picked)}, here, more, locals, globals, frames, out, fault}}), u =>
              fault_run(funcs, consts, stack, here, locals, globals, frames, out, "a string past 2**24 characters is outside the subset")), u =>
          S.choose(Run, nums_ok(pop_head(picked), pop_second(picked)), u =>
            +xy : NN = num2(pop_second(picked), pop_head(picked))
            S.choose(Run, mul_fits(nn_x(xy), nn_y(xy)), u =>
              step(left, Go{Run{funcs, consts, Con{VInt{(nn_x(xy) * nn_y(xy) : Nat)}, pop_more(picked)}, here, more, locals, globals, frames, out, fault}}), u =>
              fault_run(funcs, consts, stack, here, locals, globals, frames, out, "an int past 2**48 - 1 is outside the subset")), u =>
            fault_run(funcs, consts, stack, here, locals, globals, frames, out, "a non-number in *")))
        case KDiv{}:
          +picked : Pop = pop_args(2n, stack)
          S.choose(Run, nums_ok(pop_head(picked), pop_second(picked)), u =>
            +xy : NN = num2(pop_second(picked), pop_head(picked))
            S.choose(Run, Nat.is_ne(nn_y(xy), 0n), u =>
              step(left, Go{Run{funcs, consts, Con{VInt{Nat.div(nn_x(xy), nn_y(xy))}, pop_more(picked)}, here, more, locals, globals, frames, out, fault}}), u =>
              fault_run(funcs, consts, stack, here, locals, globals, frames, out, "division by zero")), u =>
            fault_run(funcs, consts, stack, here, locals, globals, frames, out, "a non-number in //"))
        case KMod{}:
          +picked : Pop = pop_args(2n, stack)
          S.choose(Run, nums_ok(pop_head(picked), pop_second(picked)), u =>
            +xy : NN = num2(pop_second(picked), pop_head(picked))
            S.choose(Run, Nat.is_ne(nn_y(xy), 0n), u =>
              step(left, Go{Run{funcs, consts, Con{VInt{Nat.mod(nn_x(xy), nn_y(xy))}, pop_more(picked)}, here, more, locals, globals, frames, out, fault}}), u =>
              fault_run(funcs, consts, stack, here, locals, globals, frames, out, "division by zero")), u =>
            fault_run(funcs, consts, stack, here, locals, globals, frames, out, "a non-number in %"))
        case KLt{}:
          +picked : Pop = pop_args(2n, stack)
          S.choose(Run, both_str(pop_head(picked), pop_second(picked)), u =>
            step(left, Go{Run{funcs, consts, Con{VBool{str_pick(11n, str_of(pop_second(picked)), str_of(pop_head(picked)))}, pop_more(picked)}, here, more, locals, globals, frames, out, fault}}), u =>
          S.choose(Run, nums_ok(pop_head(picked), pop_second(picked)), u =>
            +xy : NN = num2(pop_second(picked), pop_head(picked))
            step(left, Go{Run{funcs, consts, Con{VBool{cmp_pick(11n, nn_x(xy), nn_y(xy))}, pop_more(picked)}, here, more, locals, globals, frames, out, fault}}), u =>
            fault_run(funcs, consts, stack, here, locals, globals, frames, out, "an ordering between a number and a string, or with None (TypeError)")))
        case KLtE{}:
          +picked : Pop = pop_args(2n, stack)
          S.choose(Run, both_str(pop_head(picked), pop_second(picked)), u =>
            step(left, Go{Run{funcs, consts, Con{VBool{str_pick(12n, str_of(pop_second(picked)), str_of(pop_head(picked)))}, pop_more(picked)}, here, more, locals, globals, frames, out, fault}}), u =>
          S.choose(Run, nums_ok(pop_head(picked), pop_second(picked)), u =>
            +xy : NN = num2(pop_second(picked), pop_head(picked))
            step(left, Go{Run{funcs, consts, Con{VBool{cmp_pick(12n, nn_x(xy), nn_y(xy))}, pop_more(picked)}, here, more, locals, globals, frames, out, fault}}), u =>
            fault_run(funcs, consts, stack, here, locals, globals, frames, out, "an ordering between a number and a string, or with None (TypeError)")))
        case KGt{}:
          +picked : Pop = pop_args(2n, stack)
          S.choose(Run, both_str(pop_head(picked), pop_second(picked)), u =>
            step(left, Go{Run{funcs, consts, Con{VBool{str_pick(13n, str_of(pop_second(picked)), str_of(pop_head(picked)))}, pop_more(picked)}, here, more, locals, globals, frames, out, fault}}), u =>
          S.choose(Run, nums_ok(pop_head(picked), pop_second(picked)), u =>
            +xy : NN = num2(pop_second(picked), pop_head(picked))
            step(left, Go{Run{funcs, consts, Con{VBool{cmp_pick(13n, nn_x(xy), nn_y(xy))}, pop_more(picked)}, here, more, locals, globals, frames, out, fault}}), u =>
            fault_run(funcs, consts, stack, here, locals, globals, frames, out, "an ordering between a number and a string, or with None (TypeError)")))
        case KGtE{}:
          +picked : Pop = pop_args(2n, stack)
          S.choose(Run, both_str(pop_head(picked), pop_second(picked)), u =>
            step(left, Go{Run{funcs, consts, Con{VBool{str_pick(14n, str_of(pop_second(picked)), str_of(pop_head(picked)))}, pop_more(picked)}, here, more, locals, globals, frames, out, fault}}), u =>
          S.choose(Run, nums_ok(pop_head(picked), pop_second(picked)), u =>
            +xy : NN = num2(pop_second(picked), pop_head(picked))
            step(left, Go{Run{funcs, consts, Con{VBool{cmp_pick(14n, nn_x(xy), nn_y(xy))}, pop_more(picked)}, here, more, locals, globals, frames, out, fault}}), u =>
            fault_run(funcs, consts, stack, here, locals, globals, frames, out, "an ordering between a number and a string, or with None (TypeError)")))
        case KEq{}:
          +picked : Pop = pop_args(2n, stack)
          step(left, Go{Run{funcs, consts, Con{VBool{val_eq(pop_second(picked), pop_head(picked))}, pop_more(picked)}, here, more, locals, globals, frames, out, fault}})
        case KNeq{}:
          +picked : Pop = pop_args(2n, stack)
          step(left, Go{Run{funcs, consts, Con{VBool{Bool.not(val_eq(pop_second(picked), pop_head(picked)))}, pop_more(picked)}, here, more, locals, globals, frames, out, fault}})
        case KNot{}:
          +picked : Pop = pop_args(1n, stack)
          S.choose(Run, pop_any(picked), u =>
            step(left, Go{Run{funcs, consts, Con{VBool{Bool.not(truthy(pop_head(picked)))}, pop_more(picked)}, here, more, locals, globals, frames, out, fault}}), u =>
            fault_run(funcs, consts, stack, here, locals, globals, frames, out, "stack underflow"))
        case KJump{}:
          step(left, Go{Run{funcs, consts, stack, here, List.drop(&2, Instr, here, a), locals, globals, frames, out, fault}})
        case KJif{}:
          +picked : Pop = pop_args(1n, stack)
          S.choose(Run, pop_any(picked), u =>
            S.choose(Run, truthy(pop_head(picked)), u =>
              step(left, Go{Run{funcs, consts, pop_more(picked), here, more, locals, globals, frames, out, fault}}), u =>
              step(left, Go{Run{funcs, consts, pop_more(picked), here, List.drop(&2, Instr, here, a), locals, globals, frames, out, fault}})), u =>
            fault_run(funcs, consts, stack, here, locals, globals, frames, out, "stack underflow"))
        case KJit{}:
          +picked : Pop = pop_args(1n, stack)
          S.choose(Run, pop_any(picked), u =>
            S.choose(Run, truthy(pop_head(picked)), u =>
              step(left, Go{Run{funcs, consts, pop_more(picked), here, List.drop(&2, Instr, here, a), locals, globals, frames, out, fault}}), u =>
              step(left, Go{Run{funcs, consts, pop_more(picked), here, more, locals, globals, frames, out, fault}})), u =>
            fault_run(funcs, consts, stack, here, locals, globals, frames, out, "stack underflow"))
        case KJifk{}:
          +picked : Pop = pop_args(1n, stack)
          S.choose(Run, pop_any(picked), u =>
            S.choose(Run, truthy(pop_head(picked)), u =>
              step(left, Go{Run{funcs, consts, pop_more(picked), here, more, locals, globals, frames, out, fault}}), u =>
              step(left, Go{Run{funcs, consts, stack, here, List.drop(&2, Instr, here, a), locals, globals, frames, out, fault}})), u =>
            fault_run(funcs, consts, stack, here, locals, globals, frames, out, "stack underflow"))
        case KJitk{}:
          +picked : Pop = pop_args(1n, stack)
          S.choose(Run, pop_any(picked), u =>
            S.choose(Run, truthy(pop_head(picked)), u =>
              step(left, Go{Run{funcs, consts, stack, here, List.drop(&2, Instr, here, a), locals, globals, frames, out, fault}}), u =>
              step(left, Go{Run{funcs, consts, pop_more(picked), here, more, locals, globals, frames, out, fault}})), u =>
            fault_run(funcs, consts, stack, here, locals, globals, frames, out, "stack underflow"))
        case KCall{}:
          # The callee value sits under its b arguments, as CPython loads it:
          # a name not yet bound by its def faulted at the load, a name
          # rebound to a non-function faults here.
          +picked : Pop = pop_args((b + 1n : Nat), stack)
          S.choose(Run, is_func(val_at(pop_vals(picked), b)), u =>
            +callee : Func = func_at(funcs, func_of(val_at(pop_vals(picked), b)))
            +depth : Nat = (1n + frames_depth(frames) : Nat)
            S.choose(Run, Nat.is_le(depth, call_cap()), u =>
            S.choose(Run, Nat.is_eq(b, f_np(callee)), u =>
              step(left, Go{Run{funcs, consts, pop_more(picked), f_code(callee), f_code(callee),
                List.append(&2, Val, List.reverse(&2, Val, List.take(&2, Val, pop_vals(picked), b)), unsets(Nat.sub(f_nl(callee), b), Nil{})), globals, Con{VFrame{here, more, locals, depth}, frames}, out, fault}}), u =>
              fault_run(funcs, consts, stack, here, locals, globals, frames, out, "a call with the wrong number of arguments")), u =>
              fault_run(funcs, consts, stack, here, locals, globals, frames, out, "maximum recursion depth exceeded (RecursionError)")), u =>
            fault_run(funcs, consts, stack, here, locals, globals, frames, out, "calling a non-function is outside the subset"))
        case KRet{}:
          +picked : Pop = pop_args(1n, stack)
          S.choose(Run, pop_any(picked) && frames_ok(frames), u =>
            step(left, Go{Run{funcs, consts, Con{pop_head(picked), pop_more(picked)}, vh_here(frame_of(frames)), vh_rest(frame_of(frames)), vh_locals(frame_of(frames)), globals, frames_tail(frames), out, fault}}), u =>
            fault_run(funcs, consts, stack, here, locals, globals, frames, out, "return outside a call"))
        case KPrint{}:
          +picked : Pop = pop_args(b, stack)
          step(left, Go{Run{funcs, consts, Con{VNone{}, pop_more(picked)}, here, more, locals, globals, frames, Con{line(List.reverse(&2, Val, pop_vals(picked)), "", True{}), out}, fault}})
        case KLen{}:
          +picked : Pop = pop_args(1n, stack)
          S.choose(Run, pop_any(picked) && is_str(pop_head(picked)), u =>
            step(left, Go{Run{funcs, consts, Con{VInt{String.length(str_of(pop_head(picked)))}, pop_more(picked)}, here, more, locals, globals, frames, out, fault}}), u =>
            fault_run(funcs, consts, stack, here, locals, globals, frames, out, "a non-string in len()"))
        case KGetItem{}:
          +picked : Pop = pop_args(2n, stack)
          S.choose(Run, pop_any(picked) && is_str(pop_second(picked)), u =>
            S.choose(Run, is_num(pop_head(picked)), u =>
              +str : String = str_of(pop_second(picked))
              +idx : Nat = num_of(pop_head(picked))
              S.choose(Run, Nat.is_lt(idx, String.length(str)), u =>
                step(left, Go{Run{funcs, consts, Con{VStr{char_at(str, idx)}, pop_more(picked)}, here, more, locals, globals, frames, out, fault}}), u =>
                fault_run(funcs, consts, stack, here, locals, globals, frames, out, "an out-of-range index is outside the subset")), u =>
              fault_run(funcs, consts, stack, here, locals, globals, frames, out, "a non-integer index is outside the subset")), u =>
            fault_run(funcs, consts, stack, here, locals, globals, frames, out, "a non-string in indexing"))
        case KSlice{}:
          +picked : Pop = pop_args((a + b + 1n : Nat), stack)
          +sa : SliceArgs = slice_args(picked, a, b)
          S.choose(Run, is_str(sa_s(sa)), u =>
            S.choose(Run, (Nat.is_eq(a, 0n) || is_num(sa_lo(sa))) && (Nat.is_eq(b, 0n) || is_num(sa_hi(sa))), u =>
              +res : String = slice_str(str_of(sa_s(sa)), a, b, sa_lo(sa), sa_hi(sa))
              step(left, Go{Run{funcs, consts, Con{VStr{res}, pop_more(picked)}, here, more, locals, globals, frames, out, fault}}), u =>
              fault_run(funcs, consts, stack, here, locals, globals, frames, out, "a non-integer slice bound is outside the subset")), u =>
            fault_run(funcs, consts, stack, here, locals, globals, frames, out, "a non-string in slicing"))
        case KHalt{}:
          Run{funcs, consts, stack, here, more, locals, globals, frames, out, fault}
        case KBad{}:
          Run{Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, "a bad opcode"}

# Boot
# ====

# Composed, never written long: big Nat literals expand unary in the checker.
def fuel() -> Nat:
  Nat.mul(Nat.mul(100n, 100n), Nat.mul(100n, 100n))

def vm_run(+prog: Prog) -> Run:
  Prog{funcs, consts, nglobals, code} = prog
  step(fuel(), Go{Run{funcs, consts, Nil{}, code, code, Nil{}, List.replicate(Val, nglobals, VUnset{}), Nil{}, Nil{}, ""}})

# Composed, never written long: big Nat literals expand unary in the checker.
def finish(+r: Run) -> IO(Unit):
  match r:
    case Run{+funcs, +consts, +stack, +here, +rest, +locals, +globals, +frames, +out, +fault}:
      S.choose(IO(Unit), String.is_empty(fault), u => IO.write(String.concat(List.reverse(&2, String, out))), u =>
        IO.die(Unit, 1, String.append("vm: ", fault)))

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, IO.get_env("PY_SOURCE"))
    source : String <- I.load(path)
    ts : List<&2, S.Tok> <- I.unwrap(&2, List<&2, S.Tok>, L.lex(source))
    m : S.Module <- I.unwrap(&2, S.Module, P.parse(ts))
    prog : Prog <- I.unwrap(&2, Prog, build(m))
    r : Run <- IO.pure(Run, vm_run(prog))
    finish(r)