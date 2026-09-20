# AST builders. Semantic spans and syntactic covers differ for parentheses.
import Base
import ./syntax.bend as S
import ./parse_state.bend as P

def node(tag: String, fields: S.Json, +lo: S.Pos, +hi: S.Pos) -> S.Expr:
  S.Expr{tag, fields, lo, hi, S.Span{lo, hi}, False{}}

def get_tag(e: S.Expr) -> String:
  S.Expr{tag, fs, lo, hi, cover, grouped} = e
  tag

def get_fields(e: S.Expr) -> S.Json:
  S.Expr{tag, fs, lo, hi, cover, grouped} = e
  fs

def get_begin(e: S.Expr) -> S.Pos:
  S.Expr{tag, fs, lo, hi, S.Span{begin, end}, grouped} = e
  begin

def get_finish(e: S.Expr) -> S.Pos:
  S.Expr{tag, fs, lo, hi, S.Span{begin, end}, grouped} = e
  end

def group(+e: S.Expr, +start: S.Pos, +end: S.Pos) -> S.Expr:
  S.Expr{+tag, +fs, lo, hi, cover, grouped} = e
  S.choose(S.Expr, String.eq(tag, "Tuple") && Bool.not(grouped), u =>
    S.Expr{tag, fs, start, end, S.Span{start, end}, True{}}, u =>
    S.Expr{tag, fs, lo, hi, S.Span{start, end}, True{}})

def op(s: String) -> S.Json:
  S.JObj{S.JField{"tag", S.JStr{s}, S.JEnd{}}}

def get(fs: S.Json, +key: String) -> S.Json:
  match fs:
    case S.JField{+k, +v, rest}:
      S.choose(S.Json, String.eq(k, key), u => v, u => get(rest, key))
    case _:
      S.JNull{}

def string(j: S.Json) -> String:
  match j:
    case S.JStr{s}:
      s
    case _:
      ""

def reverse(xs: S.Json, acc: S.Json) -> S.Json:
  match xs:
    case S.JItem{h, t}:
      reverse(t, S.JItem{h, acc})
    case _:
      acc

def arr(xs: S.Json) -> S.Json:
  S.JArr{reverse(xs, S.JEnd{})}

def one(e: S.Expr) -> S.Json:
  S.JItem{S.expr(e), S.JEnd{}}

def name(+t: S.Tok) -> S.Expr:
  node("Name", S.JField{"id", S.JStr{P.tok_text(t)}, S.JField{"ctx", S.context(S.Load{}), S.JEnd{}}}, P.tok_start(t), P.tok_end(t))

def constant(raw: String, kind: S.Json, lo: S.Pos, hi: S.Pos) -> S.Expr:
  node("Constant", S.JField{"_raw", S.JStr{raw}, S.JField{"kind", kind, S.JEnd{}}}, lo, hi)

def atom_constant(+t: S.Tok) -> S.Expr:
  constant(P.tok_text(t), S.JNull{}, P.tok_start(t), P.tok_end(t))

def collection(+kind: String, items: S.Json, lo: S.Pos, hi: S.Pos) -> S.Expr:
  node(kind, S.JField{"elts", arr(items), S.choose(S.Json, String.eq(kind, "Set"), u => S.JEnd{}, u =>
    S.JField{"ctx", S.context(S.Load{}), S.JEnd{}})}, lo, hi)

def unary(operator: String, start: S.Pos, +value: S.Expr) -> S.Expr:
  node("UnaryOp", S.JField{"op", op(operator), S.JField{"operand", S.expr(value), S.JEnd{}}}, start, get_finish(value))

def binary(+left: S.Expr, operator: String, +right: S.Expr) -> S.Expr:
  node("BinOp", S.JField{"left", S.expr(left), S.JField{"op", op(operator), S.JField{"right", S.expr(right), S.JEnd{}}}}, get_begin(left), get_finish(right))

def starred(start: S.Pos, +value: S.Expr) -> S.Expr:
  node("Starred", S.JField{"value", S.expr(value), S.JField{"ctx", S.context(S.Load{}), S.JEnd{}}}, start, get_finish(value))

def boolean(operator: String, values: S.Json, start: S.Pos, end: S.Pos) -> S.Expr:
  node("BoolOp", S.JField{"op", op(operator), S.JField{"values", arr(values), S.JEnd{}}}, start, end)

def compare(left: S.Expr, ops: S.Json, values: S.Json, start: S.Pos, end: S.Pos) -> S.Expr:
  node("Compare", S.JField{"left", S.expr(left), S.JField{"ops", arr(ops), S.JField{"comparators", arr(values), S.JEnd{}}}}, start, end)

def conditional(+body: S.Expr, test: S.Expr, +other: S.Expr) -> S.Expr:
  node("IfExp", S.JField{"test", S.expr(test), S.JField{"body", S.expr(body), S.JField{"orelse", S.expr(other), S.JEnd{}}}}, get_begin(body), get_finish(other))

def attr(+value: S.Expr, +id: S.Tok) -> S.Expr:
  node("Attribute", S.JField{"value", S.expr(value), S.JField{"attr", S.JStr{P.tok_text(id)}, S.JField{"ctx", S.context(S.Load{}), S.JEnd{}}}}, get_begin(value), P.tok_end(id))

def subscript(+value: S.Expr, index: S.Expr, end: S.Pos) -> S.Expr:
  node("Subscript", S.JField{"value", S.expr(value), S.JField{"slice", S.expr(index), S.JField{"ctx", S.context(S.Load{}), S.JEnd{}}}}, get_begin(value), end)

def call(+fn: S.Expr, args: S.Json, keywords: S.Json, end: S.Pos) -> S.Expr:
  node("Call", S.JField{"func", S.expr(fn), S.JField{"args", arr(args), S.JField{"keywords", arr(keywords), S.JEnd{}}}}, get_begin(fn), end)

def kw(arg: S.Json, +value: S.Expr, lo: S.Pos) -> S.Json:
  S.expr(node("keyword", S.JField{"arg", arg, S.JField{"value", S.expr(value), S.JEnd{}}}, lo, get_finish(value)))

def dict(keys: S.Json, values: S.Json, lo: S.Pos, hi: S.Pos) -> S.Expr:
  node("Dict", S.JField{"keys", arr(keys), S.JField{"values", arr(values), S.JEnd{}}}, lo, hi)

# Only target containers and Starred recurse. Attribute.value and Subscript's
# value/slice stay Load; blindly rewriting every descendant ctx is incorrect.
def target_ok(j: S.Json, +mode: String, +star: Bool) -> Bool:
  match j:
    case S.JObj{+fs}:
      +tag = string(get(fs, "tag"))
      (String.eq(tag, "Name") || String.eq(tag, "Attribute") || String.eq(tag, "Subscript") ||
        String.eq(tag, "List") || String.eq(tag, "Tuple") || (star && String.eq(tag, "Starred"))) && target_ok(fs, tag, star)
    case S.JField{+key, value, rest}:
      S.choose(Bool, (String.eq(key, "elts") && (String.eq(mode, "Tuple") || String.eq(mode, "List"))) ||
        (String.eq(key, "value") && String.eq(mode, "Starred")), u => target_ok(value, "", star), u => True{}) && target_ok(rest, mode, star)
    case S.JArr{items}:
      target_ok(items, "", star)
    case S.JItem{h, t}:
      target_ok(h, "", star) && target_ok(t, "", star)
    case _:
      True{}

def target_ctx(j: S.Json, +mode: String, +ctx: S.Json) -> S.Json:
  match j:
    case S.JObj{+fs}:
      S.JObj{target_ctx(fs, string(get(fs, "tag")), ctx)}
    case S.JField{+key, +value, rest}:
      S.JField{key, S.choose(S.Json, String.eq(key, "ctx"), u => ctx, u =>
        S.choose(S.Json, (String.eq(key, "elts") && (String.eq(mode, "Tuple") || String.eq(mode, "List"))) ||
          (String.eq(key, "value") && String.eq(mode, "Starred")), u => target_ctx(value, "", ctx), u => value)), target_ctx(rest, mode, ctx)}
    case S.JArr{items}:
      S.JArr{target_ctx(items, "", ctx)}
    case S.JItem{h, t}:
      S.JItem{target_ctx(h, "", ctx), target_ctx(t, "", ctx)}
    case _:
      j

# `NAME := expression`: the target is a Name in Store.
def named(+t: S.Tok, +value: S.Expr) -> S.Expr:
  node("NamedExpr", S.JField{"target", target_ctx(S.expr(name(t)), "", S.context(S.Store{})), S.JField{"value", S.expr(value), S.JEnd{}}}, P.tok_start(t), get_finish(value))

# `del` targets are assignment targets minus Starred, in Del context. A bare
# top-level `*a = b` is the compiler's error, not ast.parse's: accepted here.
def target_with(+e: S.Expr, +aug: Bool, +del: Bool) -> Result<&2, &2, S.Error, S.Json>:
  +j = S.expr(e)
  +t = get_tag(e)
  S.choose(Result<&2, &2, S.Error, S.Json>, target_ok(j, "", Bool.not(del)) &&
    (Bool.not(aug) || String.eq(t, "Name") || String.eq(t, "Attribute") || String.eq(t, "Subscript")), u =>
    Done{target_ctx(j, "", S.context(Bool.pick(S.Ctx, del, S.Del{}, S.Store{})))}, u =>
    Fail{S.PErr{S.Syntax{}, get_begin(e), Bool.pick(String, del, "invalid del target", "invalid assignment target")}})

def target(e: S.Expr, aug: Bool) -> Result<&2, &2, S.Error, S.Json>:
  target_with(e, aug, False{})

def is_grouped(e: S.Expr) -> Bool:
  S.Expr{tag, fs, lo, hi, cover, grouped} = e
  grouped

# An unparenthesised node of this tag.
def bare(+e: S.Expr, tag: String) -> Bool:
  String.eq(get_tag(e), tag) && Bool.not(is_grouped(e))

# PEG commitment, CPython 3.11: `'(' single_target ')'` wins the annotated target's first alternative and is
# never retried, so a target that *starts* with a parenthesised Name/Attribute/Subscript and goes on
# (`(a).b: T`, `(a)[0]: T`) is "illegal target for annotation", while `((a).b): T` and `(f()).c: T` are fine.
# Down the leftmost chain, the first node that does not begin at the statement is what those parentheses hold.
def starts_at(loc: S.Json, +line: Nat, +col: Nat) -> Bool:
  match loc:
    case S.JArr{S.JItem{S.JNum{l}, S.JItem{S.JNum{c}, rest}}}:
      Nat.is_eq(l, line) && Nat.is_eq(c, col)
    case _:
      True{}

def group_head(j: S.Json, +line: Nat, +col: Nat) -> Bool:
  match j:
    case S.JObj{+fs}:
      +tag = string(get(fs, "tag"))
      S.choose(Bool, starts_at(get(fs, "_loc"), line, col), u =>
        (String.eq(tag, "Attribute") || String.eq(tag, "Subscript") || String.eq(tag, "Call")) && group_head(fs, line, col), u =>
        String.eq(tag, "Name") || String.eq(tag, "Attribute") || String.eq(tag, "Subscript"))
    case S.JField{+key, value, rest}:
      S.choose(Bool, String.eq(key, "value") || String.eq(key, "func"), u => group_head(value, line, col), u => group_head(rest, line, col))
    case _:
      False{}

def ann_target(+e: S.Expr, +start: S.Pos) -> Result<&2, &2, S.Error, S.Json>:
  S.Pos{+line, +col} = start
  S.choose(Result<&2, &2, S.Error, S.Json>, Bool.not(is_grouped(e)) && group_head(S.expr(e), line, col), u =>
    Fail{S.PErr{S.Syntax{}, start, "illegal target for annotation"}}, u => target(e, True{}))

def elts(j: S.Json) -> S.Json:
  match j:
    case S.JObj{fs}:
      get(fs, "elts")
    case _:
      S.JArr{S.JEnd{}}

# `del a, b` deletes two targets; `del (a, b)` deletes one Tuple.
def del_targets(+e: S.Expr) -> Result<&2, &2, S.Error, S.Json>:
  +many = String.eq(get_tag(e), "Tuple") && Bool.not(is_grouped(e))
  do Result<&2, &2, S.Error, S.Json>:
    +j : S.Json <- target_with(e, False{}, True{})
    return S.choose(S.Json, many, u => elts(j), u => S.JArr{S.JItem{j, S.JEnd{}}})

def block(items: S.Json, +end: S.Pos) -> S.Expr:
  node("$block", items, end, end)

def get_body(e: S.Expr) -> S.Json:
  get_fields(e)

def statement(tag: String, value: S.Json, lo: S.Pos, hi: S.Pos) -> S.Expr:
  node(tag, S.JField{"value", value, S.JEnd{}}, lo, hi)

def assignment(targets: S.Json, value: S.Expr, lo: S.Pos, hi: S.Pos) -> S.Expr:
  node("Assign", S.JField{"targets", arr(targets), S.JField{"value", S.expr(value), S.JField{"type_comment", S.JNull{}, S.JEnd{}}}}, lo, hi)

def augmented(target: S.Json, operator: String, value: S.Expr, lo: S.Pos, hi: S.Pos) -> S.Expr:
  node("AugAssign", S.JField{"target", target, S.JField{"op", op(operator), S.JField{"value", S.expr(value), S.JEnd{}}}}, lo, hi)

def compound(kind: String, test: S.Expr, body: S.Expr, +other: S.Expr, lo: S.Pos) -> S.Expr:
  node(kind, S.JField{"test", S.expr(test), S.JField{"body", S.JArr{get_fields(body)}, S.JField{"orelse", S.JArr{get_fields(other)}, S.JEnd{}}}}, lo, get_finish(other))

# CPython 3.11 wraps a lone starred subscript in a Tuple even without a comma.
def index(+e: S.Expr) -> S.Expr:
  S.choose(S.Expr, String.eq(get_tag(e), "Starred"), u =>
    collection("Tuple", one(e), get_begin(e), get_finish(e)), u => e)

def null(j: S.Json) -> Bool:
  match j:
    case S.JNull{}:
      True{}
    case _:
      False{}

def has_unpack(xs: S.Json) -> Bool:
  match xs:
    case S.JItem{S.JObj{fs}, tail}:
      null(get(fs, "arg")) || has_unpack(tail)
    case _:
      False{}

# P4 builders. `$json` and `$none` carry location-free values (arguments,
# withitem lists, an absent optional) through the S.Expr-typed parser result.
def plain(tag: String, fields: S.Json) -> S.Json:
  S.JObj{S.JField{"tag", S.JStr{tag}, fields}}

def carry(j: S.Json) -> S.Expr:
  node("$json", S.JField{"value", j, S.JEnd{}}, S.Pos{1n, 0n}, S.Pos{1n, 0n})

def carried(e: S.Expr) -> S.Json:
  get(get_fields(e), "value")

def none() -> S.Expr:
  node("$none", S.JEnd{}, S.Pos{1n, 0n}, S.Pos{1n, 0n})

def is_none(e: S.Expr) -> Bool:
  String.eq(get_tag(e), "$none")

def opt(+e: S.Expr) -> S.Json:
  S.choose(S.Json, is_none(e), u => S.JNull{}, u => S.expr(e))

def annotated(target: S.Json, note: S.Expr, value: S.Expr, simple: Bool, lo: S.Pos, hi: S.Pos) -> S.Expr:
  node("AnnAssign", S.JField{"target", target, S.JField{"annotation", S.expr(note), S.JField{"value", opt(value), S.JField{"simple", S.JNum{Bool.pick(Nat, simple, 1n, 0n)}, S.JEnd{}}}}}, lo, hi)

def empty(j: S.Json) -> Bool:
  match j:
    case S.JEnd{}:
      True{}
    case _:
      False{}

def arg(+id: S.Tok, note: S.Expr, end: S.Pos) -> S.Json:
  S.expr(node("arg", S.JField{"arg", S.JStr{P.tok_text(id)}, S.JField{"annotation", opt(note), S.JField{"type_comment", S.JNull{}, S.JEnd{}}}}, P.tok_start(id), end))

# Parameter lists accumulate reversed; the parser's phase decides the slot.
type Sig is Data:
  Sig{posonly: S.Json, args: S.Json, vararg: S.Json, kwonly: S.Json, kwdefs: S.Json, kwarg: S.Json, defaults: S.Json}

def sig_new() -> Sig:
  Sig{S.JEnd{}, S.JEnd{}, S.JNull{}, S.JEnd{}, S.JEnd{}, S.JNull{}, S.JEnd{}}

def sig_has_args(sig: Sig) -> Bool:
  Sig{po, args, va, ko, kd, kr, ds} = sig
  Bool.not(empty(args))

def sig_slash(sig: Sig) -> Sig:
  Sig{po, args, va, ko, kd, kr, ds} = sig
  Sig{args, S.JEnd{}, va, ko, kd, kr, ds}

def sig_vararg(sig: Sig, a: S.Json) -> Sig:
  Sig{po, args, va, ko, kd, kr, ds} = sig
  Sig{po, args, a, ko, kd, kr, ds}

def sig_kwarg(sig: Sig, a: S.Json) -> Sig:
  Sig{po, args, va, ko, kd, kr, ds} = sig
  Sig{po, args, va, ko, kd, a, ds}

def sig_add(sig: Sig, +a: S.Json, +dflt: S.Expr, kwonly: Bool, pos: S.Pos) -> Result<&2, &2, S.Error, Sig>:
  Sig{+po, +args, +va, +ko, +kd, +kr, +ds} = sig
  S.choose(Result<&2, &2, S.Error, Sig>, kwonly, u => Done{Sig{po, args, va, S.JItem{a, ko}, S.JItem{opt(dflt), kd}, kr, ds}}, u =>
    S.choose(Result<&2, &2, S.Error, Sig>, Bool.not(is_none(dflt)), u => Done{Sig{po, S.JItem{a, args}, va, ko, kd, kr, S.JItem{S.expr(dflt), ds}}}, u =>
      S.choose(Result<&2, &2, S.Error, Sig>, empty(ds), u => Done{Sig{po, S.JItem{a, args}, va, ko, kd, kr, ds}}, u =>
        Fail{S.PErr{S.Syntax{}, pos, "non-default argument follows default argument"}})))

def arguments(sig: Sig) -> S.Json:
  Sig{po, args, va, ko, kd, kr, ds} = sig
  plain("arguments", S.JField{"posonlyargs", arr(po), S.JField{"args", arr(args), S.JField{"vararg", va, S.JField{"kwonlyargs", arr(ko),
    S.JField{"kw_defaults", arr(kd), S.JField{"kwarg", kr, S.JField{"defaults", arr(ds), S.JEnd{}}}}}}}})

def lambda(start: S.Pos, args: S.Json, +body: S.Expr) -> S.Expr:
  node("Lambda", S.JField{"args", args, S.JField{"body", S.expr(body), S.JEnd{}}}, start, get_finish(body))

def function(id: S.Tok, args: S.Json, +body: S.Expr, decorators: S.Json, returns: S.Expr, start: S.Pos) -> S.Expr:
  node("FunctionDef", S.JField{"name", S.JStr{P.tok_text(id)}, S.JField{"args", args, S.JField{"body", S.JArr{get_fields(body)},
    S.JField{"decorator_list", decorators, S.JField{"returns", opt(returns), S.JField{"type_comment", S.JNull{}, S.JEnd{}}}}}}}, start, get_finish(body))

# `async def` / `async for` / `async with`: the plain statement's fields under the Async tag, from the `async` token.
def async(e: S.Expr, on: Bool) -> S.Expr:
  S.Expr{tag, fs, lo, hi, cover, grouped} = e
  S.Expr{Bool.pick(String, on, "Async", "") ++ tag, fs, lo, hi, cover, grouped}

def loop(target: S.Json, iter: S.Expr, body: S.Expr, +other: S.Expr, start: S.Pos) -> S.Expr:
  node("For", S.JField{"target", target, S.JField{"iter", S.expr(iter), S.JField{"body", S.JArr{get_fields(body)},
    S.JField{"orelse", S.JArr{get_fields(other)}, S.JField{"type_comment", S.JNull{}, S.JEnd{}}}}}}, start, get_finish(other))

def handler(kind: S.Expr, name: S.Json, +body: S.Expr, start: S.Pos) -> S.Expr:
  node("ExceptHandler", S.JField{"type", opt(kind), S.JField{"name", name, S.JField{"body", S.JArr{get_fields(body)}, S.JEnd{}}}}, start, get_finish(body))

def attempt(star: Bool, body: S.Expr, handlers: S.Json, other: S.Expr, +final: S.Expr, start: S.Pos) -> S.Expr:
  node(Bool.pick(String, star, "TryStar", "Try"), S.JField{"body", S.JArr{get_fields(body)}, S.JField{"handlers", arr(handlers), S.JField{"orelse", S.JArr{get_fields(other)},
    S.JField{"finalbody", S.JArr{get_fields(final)}, S.JEnd{}}}}}, start, get_finish(final))

def withitem(ctx: S.Expr, vars: S.Json) -> S.Json:
  plain("withitem", S.JField{"context_expr", S.expr(ctx), S.JField{"optional_vars", vars, S.JEnd{}}})

def context(items: S.Json, +body: S.Expr, start: S.Pos) -> S.Expr:
  node("With", S.JField{"items", items, S.JField{"body", S.JArr{get_fields(body)}, S.JField{"type_comment", S.JNull{}, S.JEnd{}}}}, start, get_finish(body))

# P5 imports. A dotted name travels as `$json` with its real span for the alias location.
def dotted(text: String, lo: S.Pos, hi: S.Pos) -> S.Expr:
  node("$json", S.JField{"value", S.JStr{text}, S.JEnd{}}, lo, hi)

def alias(+name: S.Expr, asname: S.Json, end: S.Pos) -> S.Json:
  S.expr(node("alias", S.JField{"name", carried(name), S.JField{"asname", asname, S.JEnd{}}}, get_begin(name), end))

# P6 classes. `call` is the base list parsed as a Call; only its args and keywords are kept.
def class(id: S.Tok, +call: S.Expr, +body: S.Expr, decorators: S.Json, start: S.Pos) -> S.Expr:
  node("ClassDef", S.JField{"name", S.JStr{P.tok_text(id)}, S.JField{"bases", get(get_fields(call), "args"), S.JField{"keywords", get(get_fields(call), "keywords"),
    S.JField{"body", S.JArr{get_fields(body)}, S.JField{"decorator_list", decorators, S.JEnd{}}}}}}, start, get_finish(body))

# P7 slices. An absent bound is `$none`; the span runs from the first token to the last one taken.
def slice(lower: S.Expr, upper: S.Expr, step: S.Expr, start: S.Pos, end: S.Pos) -> S.Expr:
  node("Slice", S.JField{"lower", opt(lower), S.JField{"upper", opt(upper), S.JField{"step", opt(step), S.JEnd{}}}}, start, end)

# P8 f-strings. A Constant's `_parts` are [kind, text] pieces the harness decodes and joins:
# "s" a whole plain token, "f" f-string literal text (escapes), "v" verbatim (raw, debug text).
# `$f` carries the body scan state between FString steps.
def part(kind: String, text: String) -> S.Json:
  S.JArr{S.JItem{S.JStr{kind}, S.JItem{S.JStr{text}, S.JEnd{}}}}

def fstate(values: S.Json, parts: S.Json, rest: String, pos: S.Pos) -> S.Expr:
  +p = pos
  node("$f", S.JField{"values", values, S.JField{"parts", parts, S.JField{"rest", S.JStr{rest}, S.JEnd{}}}}, p, p)

def flush(values: S.Json, parts: S.Json, kind: S.Json, lo: S.Pos, hi: S.Pos) -> S.Json:
  match parts:
    case S.JItem{h, t}:
      S.JItem{S.expr(node("Constant", S.JField{"_parts", arr(S.JItem{h, t}), S.JField{"kind", kind, S.JEnd{}}}, lo, hi)), values}
    case _:
      values

def joined(values: S.Json, lo: S.Pos, hi: S.Pos) -> S.Expr:
  node("JoinedStr", S.JField{"values", arr(values), S.JEnd{}}, lo, hi)

def formatted(value: S.Expr, conversion: S.Json, spec: S.Json, lo: S.Pos, hi: S.Pos) -> S.Expr:
  node("FormattedValue", S.JField{"value", S.expr(value), S.JField{"conversion", conversion, S.JField{"format_spec", spec, S.JEnd{}}}}, lo, hi)

# P9 comprehensions. `comprehension` carries no location; `is_async` stays 0 (`async` is a later slice).
# `sole`: the one element before `for`, neither starred nor a `**` unpack.
def sole(items: S.Json) -> Bool:
  match items:
    case S.JItem{S.JObj{fs}, S.JEnd{}}:
      Bool.not(String.eq(string(get(fs, "tag")), "Starred"))
    case _:
      False{}

def head(items: S.Json) -> S.Json:
  match items:
    case S.JItem{h, t}:
      h
    case _:
      S.JNull{}

def clause(target: S.Json, iter: S.Expr, ifs: S.Json, is_async: Bool) -> S.Json:
  plain("comprehension", S.JField{"target", target, S.JField{"iter", S.expr(iter), S.JField{"ifs", ifs, S.JField{"is_async", S.JNum{Bool.pick(Nat, is_async, 1n, 0n)}, S.JEnd{}}}}})

def comp(kind: String, head: S.Json, gens: S.Json, lo: S.Pos, hi: S.Pos) -> S.Expr:
  node(kind, S.fields_append(head, S.JField{"generators", arr(gens), S.JEnd{}}), lo, hi)

# P14 `match`. `match_case` carries no location. A capture's name is null for `_` (the wildcard, `*_`).
def match_case(pattern: S.Expr, guard: S.Expr, body: S.Expr) -> S.Json:
  plain("match_case", S.JField{"pattern", S.expr(pattern), S.JField{"guard", opt(guard), S.JField{"body", S.JArr{get_fields(body)}, S.JEnd{}}}})

def capture(+id: S.Tok) -> S.Json:
  S.choose(S.Json, P.is_text(id, "_"), u => S.JNull{}, u => S.JStr{P.tok_text(id)})

def match_as(pattern: S.Json, name: S.Json, lo: S.Pos, hi: S.Pos) -> S.Expr:
  node("MatchAs", S.JField{"pattern", pattern, S.JField{"name", name, S.JEnd{}}}, lo, hi)

def match_mapping(keys: S.Json, patterns: S.Json, rest: S.Json, lo: S.Pos, hi: S.Pos) -> S.Expr:
  node("MatchMapping", S.JField{"keys", arr(keys), S.JField{"patterns", arr(patterns), S.JField{"rest", rest, S.JEnd{}}}}, lo, hi)
