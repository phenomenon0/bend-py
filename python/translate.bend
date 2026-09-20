# The translator, slices T1-T3: wire AST -> TypedIR -> Bend, faithful mode only
# (docs/omen/plans/translator-modes.md, tiers 1-2; no rewrite layer).
# `elaborate` is untrusted search; `verify` is the kernel: it recomputes every
# binding, type, position and primitive contract from the IR itself, and `emit`
# renders only what `verify` accepted. Anything unknown is a positioned
# diagnostic, never a guess. T2 adds the control idioms `repo_of` needs: ILet,
# IBranch (`if`/`and`/`or`/IfExp), IFold (`for` over a list, `break` as
# Continue/Stop), and None -> Maybe (ISome, IMaybe). A branch or a loop is
# rendered as a helper def that matches on its parameter, so the untaken side
# is never evaluated (no Bool.pick, no strict `||`). T3 adds the long tail
# `fm_sources` needs: an early return from a loop (a Stop of Some{value}, then a
# match on the fold's result), IList, IMap (a comprehension as a recursive
# helper), string slices, `re.search` and `m.group(k)` as guarded partials, and
# `if not m`. ICall is still refused.
# Ownership: every value is an immutable exact str/bool/list/Optional
# (SOUNDNESS.md A1); a name read twice is marked `+` by the renderer and the
# Bend checker (C1) checks it. See docs/omen/lanes/translator-t2.md.
import Base
import ./syntax.bend as S
import ./nodes.bend as N
import ./intake.bend as I
import ./lexer.bend as L
import ./parser.bend as P
import ./lint.bend as Lint

# TInt is a natural number (Bend `Nat`): in this fragment only `len` and a
# decimal literal make one; a comparison, a slice bound and `group` read one.
# TMatch is a successful re match with its subject (Python keeps `m.string`).
# TBad is no type: its spelling equals nothing.
type Ty is Data:
  TBool{}
  TStr{}
  TInt{}
  TList{of: Ty}
  TMaybe{of: Ty}
  TMatch{}
  TBad{}

type Eff is Data:
  Pure{}
  Impure{}

# IArg/IEnd chain argument lists inside the one recursive ADT (as S.Json does):
# mutual recursion between a node walker and a list walker is not allowed.
# Every node carries `loc`, the Python span [line, col, line, col] it came from.
# ILet/IReturn/IStop are block nodes (a let line, the function's tail, a `break`
# in a fold step); IBranch, IMaybe and IFold are expressions rendered as calls
# of helper defs. IMaybe matches the Optional name `on` and rebinds it, narrowed
# to its payload, inside `some`. IFold's value is the final accumulator. IList
# is a list display; IMap is `[body for item in over]`, a helper call too.
type Ir is Data:
  IVar{name: String, ty: Ty, loc: S.Json}
  ILit{text: String, ty: Ty, loc: S.Json}
  IPrim{bend: String, args: Ir, ty: Ty, loc: S.Json}
  ICall{name: String, args: Ir, ty: Ty, loc: S.Json}
  ILet{name: String, val: Ir, body: Ir, loc: S.Json}
  IBranch{test: Ir, yes: Ir, no: Ir, ty: Ty, loc: S.Json}
  IFold{item: String, over: Ir, acc: String, init: Ir, step: Ir, ty: Ty, loc: S.Json}
  IReturn{val: Ir, loc: S.Json}
  IArg{head: Ir, rest: Ir}
  IEnd{}
  ISome{val: Ir, ty: Ty, loc: S.Json}
  IMaybe{on: String, none: Ir, some: Ir, ty: Ty, loc: S.Json}
  IStop{val: Ir, loc: S.Json}
  IList{items: Ir, ty: Ty, loc: S.Json}
  IMap{item: String, over: Ir, body: Ir, ty: Ty, loc: S.Json}

type Param is Data:
  Param{name: String, ty: Ty, loc: S.Json}

# What a call to a def makes known about its result, in the one predicate a
# guard on the other side can consume: `String.contains`. PHas is the result,
# a String; PEach is every item of the result, a list of String. That is the
# whole set, and the closure argument is exactly that -- a postcondition no
# guard can discharge would be a type theory, not a tool. `post` on Fn is a
# CLAIM (a TypedIR is data): the kernel recomputes what the body establishes
# with `sure` and refuses a claim that is not backed. `post` on Sig is the
# claim the kernel already checked, which is what a caller may rely on.
type Post is Data:
  PHas{text: String}
  PEach{text: String}

type Fn is Data:
  Fn{name: String, params: List<&2, Param>, ret: Ty, post: List<&2, Post>, eff: Eff, body: Ir, loc: S.Json}

# What a call to a module def must agree with, read off that def's own header.
# The kernel holds only the signatures of the defs it has already accepted, in
# the order it accepted them, so a call is granted against a strict prefix:
# list position IS the rank, and neither a cycle nor a self-call can be stated.
type Sig is Data:
  Sig{name: String, params: List<&2, Param>, ret: Ty, post: List<&2, Post>}

# A primitive's contract is an assumption about CPython and Base on the value
# contract (printable ASCII plus the six ASCII whitespace), like SOUNDNESS.md
# A3: `recv.method(args)` on an exact `recv` means `bend(recv, args)`. The
# receiver's static type resolves the method (A1: exact `str`, no subclass),
# so spelling alone is never authority. A call is granted only if pure and total.
# `pre` guards a Python-partial operation: the kernel grants it only where every
# argument after the receiver is a literal (a non-empty string or a natural) and
# the guard holds: `literal` by that alone, `positive` for a nonzero natural,
# `Regex.compile` when the pattern compiles, else where the fact `pre(args)` is
# known on the path. `src` is the Bend text of a helper Base lacks. A method
# spelled `re.` is `re`'s function, reachable only if the signature imports it.
type Contract is Data:
  Contract{recv: Ty, method: String, args: List<&2, Ty>, ret: Ty, bend: String, pure: Bool, total: Bool, pre: String, src: String}

# x.split(sep, 1)[1] where `sep in x`: the text after the first sep. Python
# raises IndexError without the guard and ValueError on an empty sep.
def after() -> String:
  "def Py.after(+s: String, +sep: String) -> String:\n  Pair.snd(String, String, Pair.snd(String, String & String, String.partition(s, sep)))\n\n"

# x.strip(cs): the ends of x cleared of every char in cs. One self-recursive def
# (a helper calling back is a law user code cannot use); both sides are total.
def strip() -> String:
  "def Py.strip_start(s: String, +cs: String) -> String:\n  match s:\n    case SNil{}:\n      SNil{}\n    case SCon{+h, +t}:\n      Bool.pick(String, String.contains(cs, SCon{h, SNil{}}), Py.strip_start(t, cs), SCon{h, t})\n\n" ++
  "def Py.strip(s: String, +cs: String) -> String:\n  String.reverse(Py.strip_start(String.reverse(Py.strip_start(s, cs)), cs))\n\n"

# re.search(p, s, f): the first match of p in s with its subject (Python's
# m.string, so a Data pair), under Base's Regex (CPython 3.11 re.ASCII, equal on the value
# contract). The guard makes the Fail arm, Python's re.error, unreachable.
def search() -> String:
  "type Py.Match is Data:\n  PyMatch{s: String, m: Match}\n\n" ++
  "def Py.search.found(+s: String, m: Maybe<&2, Match>) -> Maybe<&2, Py.Match>:\n  match m:\n    case None{}:\n      None{}\n    case Some{mm}:\n      Some{PyMatch{s, mm}}\n\n" ++
  "def Py.search.run(+s: String, r: Regex.Res(Regex)) -> Maybe<&2, Py.Match>:\n  match r:\n    case Fail{e}:\n      None{}\n    case Done{re}:\n      Py.search.found(s, Regex.find(re, s))\n\n" ++
  "def Py.search(s: String, p: String, +f: String) -> Maybe<&2, Py.Match>:\n  Py.search.run(s, Regex.compile(p, f))\n\n"

# m.group(k) where group k took part in the match; Python gives None otherwise.
def group() -> String:
  "def Py.group(m: Py.Match, k: Nat) -> String:\n  match m:\n    case PyMatch{s, mm}:\n      Maybe.default(&2, String, Regex.group(s, mm, k), \"\")\n\n"

def contracts() -> List<&2, Contract>:
  [Contract{TStr{}, "strip", [], TStr{}, "String.trim", True{}, True{}, "", ""},
   Contract{TStr{}, "lower", [], TStr{}, "String.to_lower", True{}, True{}, "", ""},
   Contract{TStr{}, "replace", [TStr{}, TStr{}], TStr{}, "String.replace", True{}, True{}, "", ""},
   Contract{TStr{}, "startswith", [TStr{}], TBool{}, "String.starts_with", True{}, True{}, "", ""},
   Contract{TStr{}, "__contains__", [TStr{}], TBool{}, "String.contains", True{}, True{}, "", ""},
   Contract{TStr{}, "__eq__", [TStr{}], TBool{}, "String.eq", True{}, True{}, "", ""},
   Contract{TStr{}, "__add__", [TStr{}], TStr{}, "String.append", True{}, True{}, "", ""},
   Contract{TStr{}, "__len__", [], TInt{}, "String.length", True{}, True{}, "", ""},
   Contract{TInt{}, "__gt__", [TInt{}], TBool{}, "Nat.is_gt", True{}, True{}, "", ""},
   Contract{TBool{}, "not", [], TBool{}, "Bool.not", True{}, True{}, "", ""},
   Contract{TStr{}, "split(,1)[1]", [TStr{}], TStr{}, "Py.after", True{}, True{}, "String.contains", after()},
   Contract{TStr{}, "strip", [TStr{}], TStr{}, "Py.strip", True{}, True{}, "", strip()},
   Contract{TStr{}, "splitlines", [], TList{TStr{}}, "String.splitlines", True{}, True{}, "", ""},
   Contract{TStr{}, "split", [TStr{}], TList{TStr{}}, "String.split_on", True{}, True{}, "literal", ""},
   Contract{TStr{}, "[i:]", [TInt{}], TStr{}, "String.drop", True{}, True{}, "", ""},
   Contract{TStr{}, "[:-k]", [TInt{}], TStr{}, "String.drop_end", True{}, True{}, "positive", ""},
   Contract{TStr{}, "re.search", [TStr{}, TStr{}], TMaybe{TMatch{}}, "Py.search", True{}, True{}, "Regex.compile", search()},
   Contract{TMatch{}, "group", [TInt{}], TStr{}, "Py.group", True{}, True{}, "Py.took", group()}]

# ---- types ----

# The Bend spelling of a type; injective, so it also decides type equality.
def ty(t: Ty) -> String:
  match t:
    case TBool{}:
      "Bool"
    case TStr{}:
      "String"
    case TInt{}:
      "Nat"
    case TList{of}:
      "List<&2, " ++ ty(of) ++ ">"
    case TMaybe{of}:
      "Maybe<&2, " ++ ty(of) ++ ">"
    case TMatch{}:
      "Py.Match"
    case TBad{}:
      ""

def tys(ts: List<&2, Ty>) -> String:
  match ts:
    case Nil{}:
      ""
    case h <> t:
      ty(h) ++ ";" ++ tys(t)

# TBad for a chain or a refused node.
def typ(e: Ir) -> Ty:
  match e:
    case IVar{name, t, loc}:
      t
    case ILit{text, t, loc}:
      t
    case IPrim{bend, args, t, loc}:
      t
    case ICall{name, args, t, loc}:
      t
    case IBranch{test, yes, no, t, loc}:
      t
    case IFold{item, over, acc, init, step, t, loc}:
      t
    case ISome{val, t, loc}:
      t
    case IMaybe{on, none, some, t, loc}:
      t
    case IList{items, t, loc}:
      t
    case IMap{item, over, body, t, loc}:
      t
    case ILet{name, val, body, loc}:
      typ(body)
    case IReturn{val, loc}:
      typ(val)
    case IStop{val, loc}:
      typ(val)
    case _:
      TBad{}

def ty_of(e: Ir) -> String:
  ty(typ(e))

def arg_tys(e: Ir) -> String:
  match e:
    case IArg{h, t}:
      ty_of(h) ++ ";" ++ arg_tys(t)
    case _:
      ""

def param_tys(ps: List<&2, Param>) -> String:
  match ps:
    case Nil{}:
      ""
    case Param{name, t, loc} <> rest:
      ty(t) ++ ";" ++ param_tys(rest)

# A call resolves when one of the signatures the kernel already holds bears
# this name, exactly these argument types and this result type. Nothing here
# reads the IR's own claim about the callee: `ss` is the authority.
def resolves(ss: List<&2, Sig>, +name: String, +args: Ir, +ret: String) -> Bool:
  match ss:
    case Nil{}:
      False{}
    case Sig{n, ps, r, q} <> rest:
      (String.eq(n, name) && String.eq(param_tys(ps), arg_tys(args)) && String.eq(ty(r), ret)) || resolves(rest, name, args, ret)

def named(ss: List<&2, Sig>, +id: String) -> Bool:
  match ss:
    case Nil{}:
      False{}
    case Sig{n, ps, r, q} <> rest:
      String.eq(n, id) || named(rest, id)

def inner(t: Ty) -> Ty:
  match t:
    case TMaybe{of}:
      of
    case _:
      TBad{}

def elem(t: Ty) -> Ty:
  match t:
    case TList{of}:
      of
    case _:
      TBad{}

# The innermost binding wins; TBad when unbound.
def type_in(env: List<&2, Param>, +id: String) -> Ty:
  match env:
    case Nil{}:
      TBad{}
    case Param{name, t, loc} <> rest:
      S.choose(Ty, String.eq(name, id), u => t, u => type_in(rest, id))

def has_name(env: List<&2, Param>, +id: String) -> Bool:
  match env:
    case Nil{}:
      False{}
    case Param{name, t, loc} <> rest:
      String.eq(name, id) || has_name(rest, id)

def own_loc(e: Ir) -> S.Json:
  match e:
    case IVar{name, t, loc}:
      loc
    case ILit{text, t, loc}:
      loc
    case IPrim{bend, args, t, loc}:
      loc
    case ICall{name, args, t, loc}:
      loc
    case ILet{name, val, body, loc}:
      loc
    case IBranch{test, yes, no, t, loc}:
      loc
    case IFold{item, over, acc, init, step, t, loc}:
      loc
    case IReturn{val, loc}:
      loc
    case ISome{val, t, loc}:
      loc
    case IMaybe{on, none, some, t, loc}:
      loc
    case IStop{val, loc}:
      loc
    case IList{items, t, loc}:
      loc
    case IMap{item, over, body, t, loc}:
      loc
    case _:
      S.JNull{}

def hd(e: Ir) -> Ir:
  match e:
    case IArg{h, t}:
      h
    case _:
      IEnd{}

def tl(e: Ir) -> Ir:
  match e:
    case IArg{h, t}:
      t
    case _:
      IEnd{}

# ---- reads: the affine discipline ----

def one(b: Bool) -> Nat:
  match b:
    case True{}:
      1n
    case False{}:
      0n

def some1(n: Nat) -> Nat:
  match n:
    case 0n:
      0n
    case 1n+p:
      1n

# How many times the def that renders `e` reads the binding `x`. A branch, an
# Optional match and a fold are calls of helper defs: their lifted parts read a
# captured name once, as one argument, however often the helper itself does.
def reads(e: Ir, +x: String) -> Nat:
  match e:
    case IVar{name, t, loc}:
      one(String.eq(name, x))
    case IPrim{bend, args, t, loc}:
      reads(args, x)
    case ICall{name, args, t, loc}:
      reads(args, x)
    case IArg{h, t}:
      Nat.add(reads(h, x), reads(t, x))
    case ILet{name, val, body, loc}:
      Nat.add(reads(val, x), S.choose(Nat, String.eq(name, x), u => 0n, u => reads(body, x)))
    case IBranch{test, yes, no, t, loc}:
      Nat.add(reads(test, x), some1(Nat.add(reads(yes, x), reads(no, x))))
    case IMaybe{on, none, some, t, loc}:
      +hit = String.eq(on, x)
      Nat.add(one(hit), some1(Nat.add(reads(none, x), S.choose(Nat, hit, u => 0n, u => reads(some, x)))))
    case IFold{item, over, acc, init, step, t, loc}:
      Nat.add(Nat.add(reads(over, x), reads(init, x)),
        S.choose(Nat, String.eq(item, x) || String.eq(acc, x), u => 0n, u => some1(reads(step, x))))
    case IReturn{val, loc}:
      reads(val, x)
    case ISome{val, t, loc}:
      reads(val, x)
    case IStop{val, loc}:
      reads(val, x)
    case IList{items, t, loc}:
      reads(items, x)
    case IMap{item, over, body, t, loc}:
      Nat.add(reads(over, x), S.choose(Nat, String.eq(item, x), u => 0n, u => some1(reads(body, x))))
    case _:
      0n

# A helper matches once, so a captured name is read as often as its busiest arm.
def busiest(arms: Ir, +x: String) -> Nat:
  match arms:
    case IArg{h, t}:
      Nat.max(reads(h, x), busiest(t, x))
    case _:
      0n

def keep_if(b: Bool, p: Param, more: List<&2, Param>) -> List<&2, Param>:
  match b:
    case True{}:
      p <> more
    case False{}:
      more

# The names a helper captures: bound, innermost binding only, read by `arms`.
def caps(env: List<&2, Param>, +arms: Ir, +skip: List<&2, String>) -> List<&2, Param>:
  match env:
    case Nil{}:
      []
    case Param{+name, +t, +loc} <> rest:
      keep = Bool.not(Lint.has(skip, name)) && Nat.is_gt(reads(arms, name), 0n)
      more = caps(rest, arms, name <> skip)
      keep_if(keep, Param{name, t, loc}, more)

# Does a fold step `break`? Then its helper threads Continue/Stop.
def stops(e: Ir) -> Bool:
  match e:
    case IStop{val, loc}:
      True{}
    case ILet{name, val, body, loc}:
      stops(body)
    case IBranch{test, yes, no, t, loc}:
      stops(yes) || stops(no)
    case IMaybe{on, none, some, t, loc}:
      stops(none) || stops(some)
    case _:
      False{}

# Does every path of a fold step's `if` arm end in a Stop? Then the statements
# after the `if` are its else-continuation, as in a function body.
def stops_all(e: Ir) -> Bool:
  match e:
    case IStop{val, loc}:
      True{}
    case ILet{name, val, body, loc}:
      stops_all(body)
    case IBranch{test, yes, no, t, loc}:
      stops_all(yes) && stops_all(no)
    case IMaybe{on, none, some, t, loc}:
      stops_all(none) && stops_all(some)
    case _:
      False{}

def is_lit(e: Ir, want: String) -> Bool:
  match e:
    case ILit{text, t, loc}:
      String.eq(text, want) && String.eq(ty(t), "Bool")
    case _:
      False{}

# A helper is named by its Python position; the kernel refuses a collision.
def hname(f: String, kind: String, +loc: S.Json) -> String:
  f ++ "." ++ kind ++ "_" ++ Nat.show(Lint.line(loc)) ++ "_" ++ Nat.show(Lint.col(loc))

def bkind(yes: Ir, no: Ir) -> String:
  S.choose(String, is_lit(yes, "True"), u => "or", u => S.choose(String, is_lit(no, "False"), u => "and", u => "if"))

# ---- show: one expression on one line ----

def sep(e: Ir) -> String:
  match e:
    case IArg{h, t}:
      ", "
    case _:
      ""

def lit_text(text: String, t: Ty) -> String:
  match t:
    case TStr{}:
      S.quote(text)
    case TBool{}:
      text ++ "{}"
    case TInt{}:
      text ++ "n"
    case TMaybe{of}:
      "None{}"
    case _:
      "?literal"

def argl(cs: List<&2, Param>) -> String:
  match cs:
    case Nil{}:
      ""
    case Param{name, t, loc} <> rest:
      ", " ++ name ++ argl(rest)

def seed(+s: String, stop: Bool) -> String:
  S.choose(String, stop, u => "Continue{" ++ s ++ "}", u => s)

# A refused node renders as a hole, which C1 rejects; `emit` never reaches it.
def show(e: Ir, +f: String, +env: List<&2, Param>) -> String:
  match e:
    case IVar{name, t, loc}:
      name
    case ILit{text, t, loc}:
      lit_text(text, t)
    case IPrim{bend, args, t, loc}:
      bend ++ "(" ++ show(args, f, env) ++ ")"
    case ICall{name, args, t, loc}:
      name ++ "(" ++ show(args, f, env) ++ ")"
    case IArg{h, +t}:
      show(h, f, env) ++ sep(t) ++ show(t, f, env)
    case IEnd{}:
      ""
    case IReturn{val, loc}:
      show(val, f, env)
    case IStop{val, loc}:
      show(val, f, env)
    case ISome{val, t, loc}:
      "Some{" ++ show(val, f, env) ++ "}"
    case IBranch{test, +yes, +no, t, loc}:
      hname(f, bkind(yes, no), loc) ++ "(" ++ show(test, f, env) ++ argl(caps(env, IArg{yes, IArg{no, IEnd{}}}, [])) ++ ")"
    case IMaybe{+on, none, some, t, loc}:
      hname(f, "opt", loc) ++ "(" ++ on ++ argl(caps(env, IArg{none, IArg{some, IEnd{}}}, [on])) ++ ")"
    case IFold{item, over, acc, init, +step, t, loc}:
      hname(f, "for", loc) ++ "(" ++ show(over, f, env) ++ ", " ++ seed(show(init, f, env), stops(step)) ++
        argl(caps(env, IArg{step, IEnd{}}, [item, acc])) ++ ")"
    case IList{items, t, loc}:
      "[" ++ show(items, f, env) ++ "]"
    case IMap{item, over, body, t, +loc}:
      hname(f, "comp", loc) ++ "(" ++ show(over, f, env) ++ argl(caps(env, IArg{body, IEnd{}}, [item])) ++ ")"
    case _:
      "?refused"

def fail(b, -A: Kind(b), k: S.ErrorKind, +loc: S.Json, msg: String) -> Result<&2, b, S.Error, A>:
  Fail{S.error(k, S.Pos{Lint.line(loc), Lint.col(loc)}, msg)}

def refuse(b, -A: Kind(b), +loc: S.Json, msg: String) -> Result<&2, b, S.Error, A>:
  fail(b, A, S.Unsupported{}, loc, msg ++ Lint.at(loc))

# ---- literals ----

# Printable ASCII other than `q` and `b`.
def plain(s: String, +q: U32, +b: U32) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{h, t}:
      +n = Char.to_u32(h)
      U32.is_ge(n, 32) && U32.is_le(n, 126) && Bool.not(U32.is_eq(n, b)) && Bool.not(U32.is_eq(n, q)) && plain(t, q, b)

def digits(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{h, t}:
      +n = Char.to_u32(h)
      U32.is_ge(n, 48) && U32.is_le(n, 57) && digits(t)

# A decimal natural as Python spells it: no sign, no `_`, no leading zero.
def natural(+s: String) -> Bool:
  Bool.not(String.is_empty(s)) && digits(s) && (String.eq(s, "0") || Bool.not(String.starts_with(s, "0")))

def quoted(s: String) -> Bool:
  match s:
    case SCon{h, t}:
      +n = Char.to_u32(h)
      U32.is_eq(n, 34) || U32.is_eq(n, 39)
    case SNil{}:
      False{}

def closes(last: Maybe<&2, Char>, +q: U32) -> Bool:
  match last:
    case Some{c}:
      U32.is_eq(Char.to_u32(c), q)
    case None{}:
      False{}

# The literal contract: one '...' or "..." token of printable ASCII with no
# backslash and no inner closing quote (so no other prefix, escape, triple quote
# or adjacent literal); or r'...' / r"..." whose body may hold a backslash but
# not end in one. Its value is then its body, by inspection of the grammar.
def quote(+raw: String, +r: Bool) -> Maybe<&2, String>:
  match raw:
    case SNil{}:
      None{}
    case SCon{h, +t}:
      +q = Char.to_u32(h)
      +body = String.drop_end(t, 1n)
      ok = (U32.is_eq(q, 34) || U32.is_eq(q, 39)) && closes(String.get_end(t, 1n), q) &&
        plain(body, q, S.choose(U32, r, u => q, u => 92)) && Bool.not(r && String.ends_with(body, "\\"))
      S.choose(Maybe<&2, String>, ok, u => Some{body}, u => None{})

def literal(+raw: String) -> Maybe<&2, String>:
  +r = String.starts_with(raw, "r")
  quote(S.choose(String, r, u => String.drop(raw, 1n), u => raw), r)

def lit(m: Maybe<&2, String>, +loc: S.Json) -> Result<&2, &2, S.Error, Ir>:
  match m:
    case Some{s}:
      Done{ILit{s, TStr{}, loc}}
    case None{}:
      refuse(&2, Ir, loc, "literal outside the contract (one plain ASCII string or r-string, no escapes; a decimal natural; True, False, None)")

def is_maybe(t: Ty) -> Bool:
  match t:
    case TMaybe{of}:
      True{}
    case _:
      False{}

# `None` has no type of its own in this fragment: it takes the declared return
# type, which must be Optional (repo_of's accumulator is the value it returns).
def constant(+raw: String, +ret: Ty, +loc: S.Json) -> Result<&2, &2, S.Error, Ir>:
  S.choose(Result<&2, &2, S.Error, Ir>, String.eq(raw, "True") || String.eq(raw, "False"), u => Done{ILit{raw, TBool{}, loc}}, u =>
    S.choose(Result<&2, &2, S.Error, Ir>, String.eq(raw, "None"), u =>
      S.choose(Result<&2, &2, S.Error, Ir>, is_maybe(ret), u => Done{ILit{"None", ret, loc}}, u =>
        refuse(&2, Ir, loc, "None outside an Optional return type")), u =>
      S.choose(Result<&2, &2, S.Error, Ir>, natural(raw), u => Done{ILit{raw, TInt{}, loc}}, u =>
        lit(literal(raw), loc))))

# ---- postconditions: what a call makes known ----

# The literals kept by both sides.
def shared(xs: List<&2, String>, +ys: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case +h <> +t:
      S.choose(List<&2, String>, Lint.has(ys, h), u => h <> shared(t, ys), u => shared(t, ys))

# The literals this value surely contains, whatever the input: a literal
# contains itself, a concatenation carries both sides', a branch only what
# both arms carry, a block what its returns carry. Every other node carries
# nothing -- the claim is only ever checked against this, so silence is safe.
def carries(e: Ir) -> List<&2, String>:
  match e:
    case ILit{+text, +t, loc}:
      S.choose(List<&2, String>, String.eq(ty(t), "String") && Bool.not(String.is_empty(text)), u => [text], u => [])
    case IPrim{+bend, +args, t, loc}:
      S.choose(List<&2, String>, String.eq(bend, "String.append"), u => carries(args), u => [])
    case IArg{h, t}:
      List.append(&2, String, carries(h), carries(t))
    case ILet{name, val, body, loc}:
      carries(body)
    case IReturn{val, loc}:
      carries(val)
    case IBranch{test, yes, no, t, loc}:
      shared(carries(yes), carries(no))
    case IMaybe{on, none, some, t, loc}:
      shared(carries(none), carries(some))
    case _:
      []

# The literals every item of this list value surely contains: a comprehension's
# items are its body's value.
# ponytail: a list display and a fold carry nothing; the shapes that would need
# it (`[a, b]`, an accumulated list) have no caller asking yet.
def carries_each(e: Ir) -> List<&2, String>:
  match e:
    case IMap{item, over, body, t, loc}:
      carries(body)
    case ILet{name, val, body, loc}:
      carries_each(body)
    case IReturn{val, loc}:
      carries_each(val)
    case IBranch{test, yes, no, t, loc}:
      shared(carries_each(yes), carries_each(no))
    case IMaybe{on, none, some, t, loc}:
      shared(carries_each(none), carries_each(some))
    case _:
      []

def hases(xs: List<&2, String>) -> List<&2, Post>:
  match xs:
    case Nil{}:
      []
    case h <> t:
      PHas{h} <> hases(t)

def eaches(xs: List<&2, String>) -> List<&2, Post>:
  match xs:
    case Nil{}:
      []
    case h <> t:
      PEach{h} <> eaches(t)

# Every postcondition this body establishes at this result type: the truth a
# claim is checked against (the kernel), and the claim to make (the
# elaborator). Only the two result types a guard can consume are read.
def sure(+body: Ir, +ret: Ty) -> List<&2, Post>:
  S.choose(List<&2, Post>, String.eq(ty(ret), "String"), u => hases(carries(body)), u =>
    S.choose(List<&2, Post>, String.eq(ty(ret), "List<&2, String>"), u => eaches(carries_each(body)), u => []))

def pshow(p: Post) -> String:
  match p:
    case PHas{text}:
      "the result contains " ++ text
    case PEach{text}:
      "every item of the result contains " ++ text

def post_in(ps: List<&2, Post>, +p: Post) -> Bool:
  match ps:
    case Nil{}:
      False{}
    case h <> t:
      String.eq(pshow(h), pshow(p)) || post_in(t, p)

# The first claim the body does not establish, "" when every one is backed.
def unbacked(cl: List<&2, Post>, +truth: List<&2, Post>) -> String:
  match cl:
    case Nil{}:
      ""
    case +h <> t:
      S.choose(String, post_in(truth, h), u => unbacked(t, truth), u => pshow(h))

# A module holds at most one def of a name (`fresh`), so the name decides.
def posts_in(ss: List<&2, Sig>, +name: String) -> List<&2, Post>:
  match ss:
    case Nil{}:
      []
    case Sig{n, ps, r, q} <> rest:
      S.choose(List<&2, Post>, String.eq(n, name), u => q, u => posts_in(rest, name))

# A postcondition as a fact about the name the call's result was bound to.
# Py.every is a fact, not a primitive, like Py.took: no contract bears it, so
# writing it in a body is refused where it stands.
def fact_of(p: Post, +name: String, +loc: S.Json) -> Ir:
  match p:
    case PHas{text}:
      IPrim{"String.contains", IArg{IVar{name, TBad{}, loc}, IArg{ILit{text, TStr{}, loc}, IEnd{}}}, TBool{}, loc}
    case PEach{text}:
      IPrim{"Py.every", IArg{IVar{name, TBad{}, loc}, IArg{ILit{text, TStr{}, loc}, IEnd{}}}, TBool{}, loc}

def facts_of(ps: List<&2, Post>, +name: String, +loc: S.Json) -> List<&2, Ir>:
  match ps:
    case Nil{}:
      []
    case h <> rest:
      fact_of(h, name, loc) <> facts_of(rest, name, loc)

# The one fact that survives a binder: every item of a list known to carry a
# literal carries it, and a comprehension's item IS such an item. `over` must
# be the very value the fact is about, by the same text the guard is read by.
def item_of(f: Ir, +over: Ir, +item: String, +loc: S.Json) -> List<&2, Ir>:
  match f:
    case IPrim{+b, +fa, t, l}:
      S.choose(List<&2, Ir>, String.eq(b, "Py.every") && String.eq(show(hd(fa), "", []), show(over, "", [])), u =>
        [IPrim{"String.contains", IArg{IVar{item, TBad{}, loc}, IArg{hd(tl(fa)), IEnd{}}}, TBool{}, loc}], u => [])
    case _:
      []

def items_of(fs: List<&2, Ir>, +over: Ir, +item: String, +loc: S.Json) -> List<&2, Ir>:
  match fs:
    case Nil{}:
      []
    case f <> rest:
      List.append(&2, Ir, item_of(f, over, item, loc), items_of(rest, over, item, loc))

# ---- elaborate: untrusted search ----

def lookup(env: List<&2, Param>, +id: String, +loc: S.Json) -> Result<&2, &2, S.Error, Ir>:
  match env:
    case Nil{}:
      refuse(&2, Ir, loc, "unresolved name " ++ id)
    case Param{name, t, at} <> rest:
      S.choose(Result<&2, &2, S.Error, Ir>, String.eq(name, id), u => Done{IVar{id, t, loc}}, u => lookup(rest, id, loc))

def grant(cs: List<&2, Contract>, +recv: Ir, +args: Ir, +attr: String, +loc: S.Json) -> Result<&2, &2, S.Error, Ir>:
  match cs:
    case Nil{}:
      refuse(&2, Ir, loc, "no verified contract for ." ++ attr ++ " on (" ++ ty_of(recv) ++ ") with (" ++ arg_tys(args) ++ ")")
    case Contract{r, method, as, ret, bend, pure, total, pre, src} <> rest:
      ok = String.eq(method, attr) && String.eq(ty(r), ty_of(recv)) && String.eq(tys(as), arg_tys(args)) && pure && total
      S.choose(Result<&2, &2, S.Error, Ir>, ok, u => Done{IPrim{bend, IArg{recv, args}, ret, loc}}, u =>
        grant(rest, recv, args, attr, loc))

def negate(r: Result<&2, &2, S.Error, Ir>, +cs: List<&2, Contract>, +loc: S.Json) -> Result<&2, &2, S.Error, Ir>:
  match r:
    case Done{e}:
      grant(cs, e, IEnd{}, "not", loc)
    case Fail{x}:
      Fail{x}

def tail_of(xs: S.Json) -> S.Json:
  match xs:
    case S.JItem{h, t}:
      t
    case _:
      S.JEnd{}

def chain(a: S.Json, b: S.Json) -> S.Json:
  match a:
    case S.JItem{h, t}:
      S.JItem{h, chain(t, b)}
    case _:
      b

def raw_of(j: S.Json) -> String:
  String.trim(N.string(Lint.field(j, "_raw")))

def is_const(+j: S.Json, want: String) -> Bool:
  String.eq(Lint.tag_of(j), "Constant") && String.eq(raw_of(j), want)

def op_of(+j: S.Json) -> String:
  S.choose(String, Nat.is_eq(Lint.size(Lint.items(Lint.field(j, "ops"))), 1n), u =>
    Lint.tag_of(Lint.first(Lint.items(Lint.field(j, "ops")))), u => "chain")

# `X is None` / `X is not None` on a name: the name, else "".
def none_test(+j: S.Json, +op: String) -> String:
  +l = Lint.field(j, "left")
  ok = String.eq(Lint.tag_of(j), "Compare") && String.eq(op_of(j), op) && String.eq(Lint.tag_of(l), "Name") &&
    is_const(Lint.first(Lint.items(Lint.field(j, "comparators"))), "None")
  S.choose(String, ok, u => N.string(Lint.field(l, "id")), u => "")

# `X is None or E` / `X is not None and E`: the name X that E may read narrowed
# to its payload (E runs only where X is not None), else "".
def narrow(+j: S.Json) -> String:
  +vs = Lint.items(Lint.field(j, "values"))
  +or = String.eq(Lint.tag_of(Lint.field(j, "op")), "Or")
  S.choose(String, String.eq(Lint.tag_of(j), "BoolOp") && Nat.is_eq(Lint.size(vs), 2n), u =>
    none_test(Lint.first(vs), S.choose(String, or, u => "Is", u => "IsNot")), u => "")

# x.split(sep, 1)[1], the one subscript form.
def split_form(+j: S.Json) -> Bool:
  +c = Lint.field(j, "value")
  +f = Lint.field(c, "func")
  +as = Lint.items(Lint.field(c, "args"))
  String.eq(Lint.tag_of(j), "Subscript") && is_const(Lint.field(j, "slice"), "1") && String.eq(Lint.tag_of(c), "Call") &&
    String.eq(Lint.tag_of(f), "Attribute") && String.eq(N.string(Lint.field(f, "attr")), "split") &&
    Lint.is_empty(Lint.field(c, "keywords")) && Nat.is_eq(Lint.size(as), 2n) && is_const(Lint.first(tail_of(as)), "1")

# x[i:], x[:-k], x[i:-k]: no step; a present upper bound is a negated literal.
def slice_form(+j: S.Json) -> Bool:
  +sl = Lint.field(j, "slice")
  +hi = Lint.field(sl, "upper")
  String.eq(Lint.tag_of(j), "Subscript") && String.eq(Lint.tag_of(sl), "Slice") && Lint.is_null(Lint.field(sl, "step")) &&
    Bool.not(Lint.is_null(Lint.field(sl, "lower")) && Lint.is_null(hi)) &&
    (Lint.is_null(hi) || (String.eq(Lint.tag_of(hi), "UnaryOp") && String.eq(Lint.tag_of(Lint.field(hi, "op")), "USub") &&
      String.eq(Lint.tag_of(Lint.field(hi, "operand")), "Constant")))

# The present bounds of a slice, lower first; the upper as its literal k.
def bounds(+sl: S.Json) -> S.Json:
  +lo = Lint.field(sl, "lower")
  +hi = S.choose(S.Json, Lint.is_null(Lint.field(sl, "upper")), u => S.JEnd{}, u => S.JItem{Lint.field(Lint.field(sl, "upper"), "operand"), S.JEnd{}})
  S.choose(S.Json, Lint.is_null(lo), u => hi, u => S.JItem{lo, hi})

def offers(cs: List<&2, Contract>, +m: String) -> Bool:
  match cs:
    case Nil{}:
      False{}
    case Contract{r, method, as, ret, bend, pure, total, pre, src} <> rest:
      String.eq(method, m) || offers(rest, m)

def is_attr(+j: S.Json, +of: String, +attr: String) -> Bool:
  +v = Lint.field(j, "value")
  String.eq(Lint.tag_of(j), "Attribute") && String.eq(Lint.tag_of(v), "Name") && String.eq(N.string(Lint.field(v, "id")), of) &&
    String.eq(N.string(Lint.field(j, "attr")), attr)

# re.search(p, s, re.S), where `re` is the module the signature imports (a
# granted contract) and no local name.
def re_form(+j: S.Json, +env: List<&2, Param>, +cs: List<&2, Contract>) -> Bool:
  +as = Lint.items(Lint.field(j, "args"))
  String.eq(Lint.tag_of(j), "Call") && is_attr(Lint.field(j, "func"), "re", "search") && offers(cs, "re.search") &&
    Bool.not(has_name(env, "re")) && Lint.is_empty(Lint.field(j, "keywords")) && Nat.is_eq(Lint.size(as), 3n) &&
    is_attr(Lint.first(tail_of(tail_of(as))), "re", "S")

def zero(j: S.Json) -> Bool:
  match j:
    case S.JNum{n}:
      Nat.is_eq(n, 0n)
    case _:
      False{}

# [elt for x in xs]: one generator, a fresh name, no condition.
def comp_form(+j: S.Json, +env: List<&2, Param>) -> Bool:
  +gs = Lint.items(Lint.field(j, "generators"))
  +g = Lint.first(gs)
  +t = Lint.field(g, "target")
  String.eq(Lint.tag_of(j), "ListComp") && Nat.is_eq(Lint.size(gs), 1n) && String.eq(Lint.tag_of(t), "Name") &&
    Bool.not(has_name(env, N.string(Lint.field(t, "id")))) && Lint.is_empty(Lint.field(g, "ifs")) && zero(Lint.field(g, "is_async"))

def is_len(+j: S.Json, +env: List<&2, Param>) -> Bool:
  +f = Lint.field(j, "func")
  String.eq(Lint.tag_of(j), "Call") && String.eq(Lint.tag_of(f), "Name") && String.eq(N.string(Lint.field(f, "id")), "len") &&
    Bool.not(has_name(env, "len")) && Lint.is_empty(Lint.field(j, "keywords")) && Nat.is_eq(Lint.size(Lint.items(Lint.field(j, "args"))), 1n)

# f(a, b) where f names a def of this module whose signature the kernel holds
# and no local shadows it: the one call form T4 admits.
def is_user(+j: S.Json, +env: List<&2, Param>, +ss: List<&2, Sig>) -> Bool:
  +f = Lint.field(j, "func")
  +id = N.string(Lint.field(f, "id"))
  String.eq(Lint.tag_of(j), "Call") && String.eq(Lint.tag_of(f), "Name") && named(ss, id) &&
    Bool.not(has_name(env, id)) && Lint.is_empty(Lint.field(j, "keywords"))

def is_method(+j: S.Json) -> Bool:
  String.eq(Lint.tag_of(j), "Call") && String.eq(Lint.tag_of(Lint.field(j, "func")), "Attribute") && Lint.is_empty(Lint.field(j, "keywords"))

def two(a: S.Json, b: S.Json) -> S.Json:
  S.JItem{a, S.JItem{b, S.JEnd{}}}

# The subexpressions of a node, in Python's evaluation order. A node with none
# here is a leaf or is refused by `build`.
def subs(+j: S.Json, +env: List<&2, Param>, +cs: List<&2, Contract>, +ss: List<&2, Sig>) -> S.Json:
  +tag = Lint.tag_of(j)
  +c = Lint.field(j, "value")
  +as = Lint.items(Lint.field(j, "args"))
  S.choose(S.Json, re_form(j, env, cs), u => two(Lint.first(as), Lint.first(tail_of(as))), u =>
  S.choose(S.Json, slice_form(j), u => S.JItem{c, bounds(Lint.field(j, "slice"))}, u =>
  S.choose(S.Json, String.eq(tag, "List"), u => Lint.items(Lint.field(j, "elts")), u =>
  S.choose(S.Json, is_method(j), u => S.JItem{Lint.field(Lint.field(j, "func"), "value"), as}, u =>
    S.choose(S.Json, is_user(j, env, ss), u => as, u =>
    S.choose(S.Json, is_len(j, env), u => Lint.items(Lint.field(j, "args")), u =>
      S.choose(S.Json, String.eq(tag, "UnaryOp"), u => S.JItem{Lint.field(j, "operand"), S.JEnd{}}, u =>
        S.choose(S.Json, String.eq(tag, "BinOp"), u => two(Lint.field(j, "left"), Lint.field(j, "right")), u =>
          S.choose(S.Json, String.eq(tag, "Compare") && String.eq(none_test(j, op_of(j)), "") && Bool.not(String.eq(op_of(j), "chain")), u =>
            two(Lint.field(j, "left"), Lint.first(Lint.items(Lint.field(j, "comparators")))), u =>
            S.choose(S.Json, String.eq(tag, "BoolOp"), u =>
              S.choose(S.Json, String.eq(narrow(j), ""), u => Lint.items(Lint.field(j, "values")), u => tail_of(Lint.items(Lint.field(j, "values")))), u =>
              S.choose(S.Json, String.eq(tag, "IfExp"), u => S.JItem{Lint.field(j, "test"), two(Lint.field(j, "body"), Lint.field(j, "orelse"))}, u =>
                S.choose(S.Json, split_form(j), u =>
                  two(Lint.field(Lint.field(c, "func"), "value"), Lint.first(Lint.items(Lint.field(c, "args")))), u => S.JEnd{}))))))))))))

# The environment the subexpressions see: X narrowed under `X is None or E`.
def scope(+j: S.Json, +env: List<&2, Param>) -> List<&2, Param>:
  +x = narrow(j)
  S.choose(List<&2, Param>, String.eq(x, ""), u => env, u => Param{x, inner(type_in(env, x)), Lint.field(j, "_loc")} <> env)

def all_ty(e: Ir, +want: String) -> Bool:
  match e:
    case IArg{h, t}:
      String.eq(ty_of(h), want) && all_ty(t, want)
    case IEnd{}:
      True{}
    case _:
      False{}

def reads_end(e: Ir) -> Nat:
  match e:
    case IArg{h, t}:
      1n
    case _:
      0n

# a or b or c = a or (b or c): right-nested helper matches, so an operand runs
# only if every operand before it failed to decide. A nested branch is placed
# at its first operand, which keeps helper names distinct.
def bools(e: Ir, +or: Bool, +loc: S.Json) -> Ir:
  match e:
    case IArg{+h, +t}:
      +rest = bools(t, or, own_loc(hd(t)))
      S.choose(Ir, Nat.is_eq(reads_end(t), 0n), u => h, u =>
        S.choose(Ir, or, u => IBranch{h, ILit{"True", TBool{}, loc}, rest, TBool{}, loc}, u =>
          IBranch{h, rest, ILit{"False", TBool{}, loc}, TBool{}, loc}))
    case _:
      IEnd{}

# `e` at type `want`: itself, or Some{e} when `want` is Optional of its type.
def lift(+e: Ir, +want: Ty, +loc: S.Json) -> Result<&2, &2, S.Error, Ir>:
  S.choose(Result<&2, &2, S.Error, Ir>, String.eq(ty_of(e), ty(want)), u => Done{e}, u =>
    S.choose(Result<&2, &2, S.Error, Ir>, String.eq(ty(inner(want)), ty_of(e)), u => Done{ISome{e, want, own_loc(e)}}, u =>
      refuse(&2, Ir, loc, "type mismatch: (" ++ ty_of(e) ++ ") where (" ++ ty(want) ++ ") is expected")))

# The common type of two arms: equal, or one the Optional of the other.
def join(+a: Ty, +b: Ty) -> Ty:
  S.choose(Ty, String.eq(ty(inner(b)), ty(a)), u => b, u => a)

def lit_bool(b: Bool, loc: S.Json) -> Ir:
  ILit{S.choose(String, b, u => "True", u => "False"), TBool{}, loc}

def need_bool(+e: Ir, r: Result<&2, &2, S.Error, Ir>) -> Result<&2, &2, S.Error, Ir>:
  S.choose(Result<&2, &2, S.Error, Ir>, all_ty(e, "Bool"), u => r, u =>
    refuse(&2, Ir, own_loc(hd(e)), "truthiness of a non-bool is outside the fragment"))

# A list display: `[]` takes the declared return type, which must be a list.
def list_of(+kids: Ir, +ret: Ty, +loc: S.Json) -> Result<&2, &2, S.Error, Ir>:
  +t = S.choose(Ty, Nat.is_eq(reads_end(kids), 0n), u => ret, u => TList{typ(hd(kids))})
  S.choose(Result<&2, &2, S.Error, Ir>, Bool.not(String.is_empty(ty(elem(t)))) && all_ty(kids, ty(elem(t))), u => Done{IList{kids, t, loc}}, u =>
    refuse(&2, Ir, loc, "list of mixed element types, or [] outside a list return type"))

# x[i:-k] = drop_end(drop(x, i), k).
def cut(+j: S.Json, +kids: Ir, +cs: List<&2, Contract>, +loc: S.Json) -> Result<&2, &2, S.Error, Ir>:
  +sl = Lint.field(j, "slice")
  +lo = Bool.not(Lint.is_null(Lint.field(sl, "lower")))
  +hi = Bool.not(Lint.is_null(Lint.field(sl, "upper")))
  S.choose(Result<&2, &2, S.Error, Ir>, lo && hi, u =>
    do Result<&2, &2, S.Error, Ir>:
      d : Ir <- grant(cs, hd(kids), IArg{hd(tl(kids)), IEnd{}}, "[i:]", loc)
      grant(cs, d, tl(tl(kids)), "[:-k]", loc), u =>
    grant(cs, hd(kids), tl(kids), S.choose(String, lo, u => "[i:]", u => "[:-k]"), loc))

# The call node, typed at the callee's declared result: the elaborator picks
# the signature whose parameter types the arguments match, and the kernel
# recomputes that choice. A name no held signature bears never gets here.
def called(ss: List<&2, Sig>, +name: String, +args: Ir, +loc: S.Json) -> Result<&2, &2, S.Error, Ir>:
  match ss:
    case Nil{}:
      refuse(&2, Ir, loc, "no def ranked below this one takes " ++ name ++ "(" ++ arg_tys(args) ++ ")")
    case Sig{n, ps, r, q} <> rest:
      S.choose(Result<&2, &2, S.Error, Ir>, String.eq(n, name) && String.eq(param_tys(ps), arg_tys(args)), u =>
        Done{ICall{name, args, r, loc}}, u => called(rest, name, args, loc))

# One node from its elaborated subexpressions `kids`. Not recursive.
def build(+j: S.Json, +kids: Ir, +env: List<&2, Param>, +cs: List<&2, Contract>, +ret: Ty, +ss: List<&2, Sig>) -> Result<&2, &2, S.Error, Ir>:
  +tag = Lint.tag_of(j)
  +loc = Lint.field(j, "_loc")
  +op = S.choose(String, String.eq(tag, "Compare"), u => op_of(j), u => Lint.tag_of(Lint.field(j, "op")))
  +a = hd(kids)
  +b = hd(tl(kids))
  +c = hd(tl(tl(kids)))
  +x = S.choose(String, String.eq(tag, "BoolOp"), u => narrow(j), u => none_test(j, op))
  +yes = String.eq(op, "Is") || String.eq(op, "Or")
  S.choose(Result<&2, &2, S.Error, Ir>, re_form(j, env, cs), u => grant(cs, b, IArg{a, IArg{ILit{"s", TStr{}, Lint.field(Lint.first(tail_of(tail_of(Lint.items(Lint.field(j, "args"))))), "_loc")}, IEnd{}}}, "re.search", loc), u =>
  S.choose(Result<&2, &2, S.Error, Ir>, slice_form(j), u => cut(j, kids, cs, loc), u =>
  S.choose(Result<&2, &2, S.Error, Ir>, String.eq(tag, "List"), u => list_of(kids, ret, loc), u =>
  S.choose(Result<&2, &2, S.Error, Ir>, is_method(j), u => grant(cs, a, tl(kids), N.string(Lint.field(Lint.field(j, "func"), "attr")), loc), u =>
    S.choose(Result<&2, &2, S.Error, Ir>, is_user(j, env, ss), u => called(ss, N.string(Lint.field(Lint.field(j, "func"), "id")), kids, loc), u =>
    S.choose(Result<&2, &2, S.Error, Ir>, is_len(j, env), u => grant(cs, a, IEnd{}, "__len__", loc), u =>
      S.choose(Result<&2, &2, S.Error, Ir>, split_form(j), u => grant(cs, a, tl(kids), "split(,1)[1]", loc), u =>
        S.choose(Result<&2, &2, S.Error, Ir>, String.eq(tag, "UnaryOp") && String.eq(op, "Not"), u => need_bool(kids, grant(cs, a, IEnd{}, "not", loc)), u =>
          S.choose(Result<&2, &2, S.Error, Ir>, String.eq(tag, "BinOp") && String.eq(op, "Add"), u => grant(cs, a, tl(kids), "__add__", loc), u =>
            S.choose(Result<&2, &2, S.Error, Ir>, Bool.not(String.eq(x, "")), u =>
              S.choose(Result<&2, &2, S.Error, Ir>, Bool.not(is_maybe(type_in(env, x))), u => refuse(&2, Ir, loc, "`is None` on a name that is not Optional: " ++ x), u =>
                S.choose(Result<&2, &2, S.Error, Ir>, String.eq(tag, "Compare"), u => Done{IMaybe{x, lit_bool(yes, loc), lit_bool(Bool.not(yes), loc), TBool{}, loc}}, u =>
                  need_bool(kids, Done{IMaybe{x, lit_bool(yes, loc), a, TBool{}, loc}}))), u =>
              S.choose(Result<&2, &2, S.Error, Ir>, String.eq(tag, "BoolOp"), u => need_bool(kids, Done{bools(kids, yes, loc)}), u =>
                S.choose(Result<&2, &2, S.Error, Ir>, String.eq(tag, "IfExp"), u =>
                  need_bool(IArg{a, IEnd{}}, do Result<&2, &2, S.Error, Ir>:
                    y : Ir <- lift(b, join(typ(b), typ(c)), loc)
                    n : Ir <- lift(c, join(typ(b), typ(c)), loc)
                    Done{IBranch{a, y, n, join(typ(b), typ(c)), loc}}), u =>
                  S.choose(Result<&2, &2, S.Error, Ir>, String.eq(op, "Eq"), u => grant(cs, a, tl(kids), "__eq__", loc), u =>
                    S.choose(Result<&2, &2, S.Error, Ir>, String.eq(op, "NotEq"), u => negate(grant(cs, a, tl(kids), "__eq__", loc), cs, loc), u =>
                      S.choose(Result<&2, &2, S.Error, Ir>, String.eq(op, "Gt"), u => grant(cs, a, tl(kids), "__gt__", loc), u =>
                        S.choose(Result<&2, &2, S.Error, Ir>, String.eq(op, "In"), u => grant(cs, b, IArg{a, IEnd{}}, "__contains__", loc), u =>
                          S.choose(Result<&2, &2, S.Error, Ir>, String.eq(op, "NotIn"), u => negate(grant(cs, b, IArg{a, IEnd{}}, "__contains__", loc), cs, loc), u =>
                            refuse(&2, Ir, loc, "outside the fragment: " ++ tag ++ S.choose(String, String.eq(op, ""), u => "", u => " " ++ op)))))))))))))))))))

def listy(+e: Ir, what: String) -> Result<&2, &2, S.Error, Unit>:
  S.choose(Result<&2, &2, S.Error, Unit>, String.is_empty(ty(elem(typ(e)))), u =>
    refuse(&2, Unit, own_loc(e), what ++ " over a non-list (" ++ ty_of(e) ++ ")"), u => Done{Unit{}})

# One def walks nodes and argument chains (JItem). Fuel is the JSON size, a
# bound on depth: exhaustion is a Limit diagnostic, not a partial tree.
# Subexpressions are elaborated left to right, as Python evaluates them; `in`
# alone swaps its operands, unobservable since every granted primitive is pure
# and total.
def expr(fuel: Nat, +j: S.Json, +env: List<&2, Param>, +cs: List<&2, Contract>, +ret: Ty, +ss: List<&2, Sig>) -> Result<&2, &2, S.Error, Ir>:
  match fuel:
    case 0n:
      fail(&2, Ir, S.Limit{}, S.JNull{}, "elaboration fuel exhausted")
    case 1n+p:
      +left = p
      +tag = Lint.tag_of(j)
      +loc = Lint.field(j, "_loc")
      +g = Lint.first(Lint.items(Lint.field(j, "generators")))
      +x = N.string(Lint.field(Lint.field(g, "target"), "id"))
      S.choose(Result<&2, &2, S.Error, Ir>, Lint.is_empty(S.JArr{j}), u => Done{IEnd{}}, u =>
        S.choose(Result<&2, &2, S.Error, Ir>, Nat.is_gt(Lint.size(j), 0n), u =>
          do Result<&2, &2, S.Error, Ir>:
            h : Ir <- expr(left, Lint.first(j), env, cs, ret, ss)
            t : Ir <- expr(left, tail_of(j), env, cs, ret, ss)
            Done{IArg{h, t}}, u =>
          S.choose(Result<&2, &2, S.Error, Ir>, String.eq(tag, "Name") && String.eq(Lint.tag_of(Lint.field(j, "ctx")), "Load"), u =>
            lookup(env, N.string(Lint.field(j, "id")), loc), u =>
            S.choose(Result<&2, &2, S.Error, Ir>, String.eq(tag, "Constant"), u => constant(raw_of(j), ret, loc), u =>
            S.choose(Result<&2, &2, S.Error, Ir>, comp_form(j, env), u =>
              do Result<&2, &2, S.Error, Ir>:
                +over : Ir <- expr(left, Lint.field(g, "iter"), env, cs, ret, ss)
                ok : Unit <- listy(over, "comprehension")
                +body : Ir <- expr(left, Lint.field(j, "elt"), Param{x, elem(typ(over)), loc} <> env, cs, ret, ss)
                Done{IMap{x, over, body, TList{typ(body)}, loc}}, u =>
              do Result<&2, &2, S.Error, Ir>:
                kids : Ir <- expr(left, subs(j, env, cs, ss), scope(j, env), cs, ret, ss)
                build(j, kids, env, cs, ret, ss))))))

def weight(j: S.Json) -> Nat:
  match j:
    case S.JObj{fs}:
      1n+weight(fs)
    case S.JArr{xs}:
      1n+weight(xs)
    case S.JField{key, value, rest}:
      1n+Nat.add(weight(value), weight(rest))
    case S.JItem{h, t}:
      1n+Nat.add(weight(h), weight(t))
    case _:
      1n

def docstring(+s: S.Json) -> Bool:
  +v = Lint.field(s, "value")
  String.eq(Lint.tag_of(s), "Expr") && String.eq(Lint.tag_of(v), "Constant") && quoted(raw_of(v))

# The one name a loop body assigns that is bound outside it: the accumulator.
# "" when there is none, "?" when there are several.
def accs(ns: List<&2, String>, +env: List<&2, Param>, +got: String) -> String:
  match ns:
    case Nil{}:
      got
    case +n <> +t:
      S.choose(String, Bool.not(has_name(env, n)) || String.eq(n, got), u => accs(t, env, got), u =>
        S.choose(String, String.eq(got, ""), u => accs(t, env, n), u => "?"))

def target(+h: S.Json) -> String:
  +ts = Lint.items(Lint.field(h, "targets"))
  +t = S.choose(S.Json, String.eq(Lint.tag_of(h), "For"), u => Lint.field(h, "target"), u => Lint.first(ts))
  ok = String.eq(Lint.tag_of(t), "Name") && (String.eq(Lint.tag_of(h), "For") || Nat.is_eq(Lint.size(ts), 1n))
  S.choose(String, ok, u => N.string(Lint.field(t, "id")), u => "")

# A rebound name keeps its type (an Optional accumulator stays Optional).
def slot(+env: List<&2, Param>, +x: String, e: Ir) -> Ty:
  S.choose(Ty, has_name(env, x), u => type_in(env, x), u => typ(e))

# Is there a node with this tag (and this id, unless "") in `j`?
def under(j: S.Json, +tag: String, +id: String) -> Bool:
  match j:
    case S.JObj{+fs}:
      +o = {S.JObj{fs} : S.Json}
      (String.eq(Lint.tag_of(o), tag) && (String.is_empty(id) || String.eq(N.string(Lint.field(o, "id")), id))) || under(fs, tag, id)
    case S.JArr{xs}:
      under(xs, tag, id)
    case S.JField{key, value, rest}:
      under(value, tag, id) || under(rest, tag, id)
    case S.JItem{h, t}:
      under(h, tag, id) || under(t, tag, id)
    case _:
      False{}

# `not X` on an Optional match: X is None, since a match is always truthy.
def no_match(+j: S.Json, +env: List<&2, Param>) -> String:
  +x = Lint.field(j, "operand")
  +id = N.string(Lint.field(x, "id"))
  ok = String.eq(Lint.tag_of(j), "UnaryOp") && String.eq(Lint.tag_of(Lint.field(j, "op")), "Not") && String.eq(Lint.tag_of(x), "Name") &&
    String.eq(ty(type_in(env, id)), ty(TMaybe{TMatch{}}))
  S.choose(String, ok, u => id, u => "")

def falls(bad: Bool, +t: S.Json) -> Result<&2, &2, S.Error, Unit>:
  S.choose(Result<&2, &2, S.Error, Unit>, bad, u =>
    refuse(&2, Unit, Lint.field(Lint.first(t), "_loc"), "statement after an if that falls through inside a loop is outside the fragment"), u => Done{Unit{}})

def must_bool(+e: Ir) -> Result<&2, &2, S.Error, Unit>:
  S.choose(Result<&2, &2, S.Error, Unit>, String.eq(ty_of(e), "Bool"), u => Done{Unit{}}, u =>
    refuse(&2, Unit, own_loc(e), "truthiness of a non-bool is outside the fragment"))

# Statements. `acc` is "" in a function body, where every path must end in one
# `return e` (falling off the end, an implicit None, is refused) and the
# statements after an `if` are its else-continuation. Inside a `for` body `acc`
# names the accumulator: a path ends by falling off (the step's value is the
# accumulator) or by `break`; an `if` must then be the last statement, unless
# its arm always stops. A loop that returns has no accumulator of the user's:
# its own, ret_L_C, is None until a `return e` stops the fold with Some{e};
# then a match on it returns e or runs the statements after the loop. A
# leading docstring is a constant expression statement: skipped.
def block(fuel: Nat, xs: S.Json, first: Bool, +near: S.Json, +env: List<&2, Param>, +cs: List<&2, Contract>, +ret: Ty, +acc: String, +ss: List<&2, Sig>) -> Result<&2, &2, S.Error, Ir>:
  match fuel xs:
    case 0n _:
      fail(&2, Ir, S.Limit{}, S.JNull{}, "elaboration fuel exhausted")
    case 1n+p S.JItem{+h, +t}:
      +left = p
      +loc = Lint.field(h, "_loc")
      +val = Lint.field(h, "value")
      +tag = Lint.tag_of(h)
      +x = target(h)
      +loop = Bool.not(String.eq(acc, ""))
      +last = Lint.is_empty(S.JArr{t})
      +body = Lint.items(Lint.field(h, "body"))
      +a = accs(Lint.binds(Lint.field(h, "body")), env, "")
      +nx = no_match(Lint.field(h, "test"), env)
      +r = "ret_" ++ Nat.show(Lint.line(loc)) ++ "_" ++ Nat.show(Lint.col(loc))
      +rt = {TMaybe{ret} : Ty}
      S.choose(Result<&2, &2, S.Error, Ir>, first && docstring(h), u => block(left, t, False{}, near, env, cs, ret, acc, ss), u =>
        S.choose(Result<&2, &2, S.Error, Ir>, String.eq(tag, "Return") && Bool.not(Lint.is_null(val)), u =>
            S.choose(Result<&2, &2, S.Error, Ir>, Bool.not(last), u => refuse(&2, Ir, Lint.field(Lint.first(t), "_loc"), "statement after return"), u =>
              do Result<&2, &2, S.Error, Ir>:
                +e : Ir <- expr(weight(val), val, env, cs, ret, ss)
                +v : Ir <- lift(e, ret, loc)
                Done{S.choose(Ir, loop, u => IStop{ISome{v, rt, loc}, loc}, u => IReturn{v, loc})}), u =>
          S.choose(Result<&2, &2, S.Error, Ir>, String.eq(tag, "Assign") && Bool.not(String.eq(x, "")), u =>
            do Result<&2, &2, S.Error, Ir>:
              +e : Ir <- expr(weight(val), val, env, cs, ret, ss)
              v : Ir <- lift(e, slot(env, x, e), loc)
              k : Ir <- block(left, t, False{}, loc, Param{x, slot(env, x, e), loc} <> env, cs, ret, acc, ss)
              Done{ILet{x, v, k, loc}}, u =>
            S.choose(Result<&2, &2, S.Error, Ir>, String.eq(tag, "If") && Bool.not(String.is_empty(nx)), u =>
              do Result<&2, &2, S.Error, Ir>:
                +none : Ir <- block(left, body, False{}, loc, env, cs, ret, acc, ss)
                ok : Unit <- falls(loop && Bool.not(last) && Bool.not(stops_all(none)), t)
                some : Ir <- block(left, chain(Lint.items(Lint.field(h, "orelse")), t), False{}, loc, Param{nx, TMatch{}, loc} <> env, cs, ret, acc, ss)
                Done{IMaybe{nx, none, some, typ(none), loc}}, u =>
            S.choose(Result<&2, &2, S.Error, Ir>, String.eq(tag, "If"), u =>
                do Result<&2, &2, S.Error, Ir>:
                  +c : Ir <- expr(weight(Lint.field(h, "test")), Lint.field(h, "test"), env, cs, ret, ss)
                  ok : Unit <- must_bool(c)
                  +yes : Ir <- block(left, body, False{}, loc, env, cs, ret, acc, ss)
                  ok : Unit <- falls(loop && Bool.not(last) && Bool.not(stops_all(yes)), t)
                  no : Ir <- block(left, chain(Lint.items(Lint.field(h, "orelse")), t), False{}, loc, env, cs, ret, acc, ss)
                  Done{IBranch{c, yes, no, typ(yes), loc}}, u =>
              S.choose(Result<&2, &2, S.Error, Ir>, String.eq(tag, "For") && Bool.not(loop), u =>
                S.choose(Result<&2, &2, S.Error, Ir>, String.eq(x, "") || has_name(env, x) || Bool.not(Lint.is_empty(Lint.field(h, "orelse"))), u =>
                  refuse(&2, Ir, loc, "for: the target must be one fresh name and there is no else"), u =>
                  S.choose(Result<&2, &2, S.Error, Ir>, under(body, "Return", ""), u =>
                    S.choose(Result<&2, &2, S.Error, Ir>, Bool.not(String.eq(a, "")), u =>
                      refuse(&2, Ir, loc, "for: a loop that returns must not also assign a name bound before it"), u =>
                      S.choose(Result<&2, &2, S.Error, Ir>, has_name(env, r) || under(S.JItem{h, t}, "Name", r), u =>
                        refuse(&2, Ir, loc, "for: the name " ++ r ++ " is taken"), u =>
                        do Result<&2, &2, S.Error, Ir>:
                          +over : Ir <- expr(weight(Lint.field(h, "iter")), Lint.field(h, "iter"), env, cs, ret, ss)
                          ok : Unit <- listy(over, "for")
                          step : Ir <- block(left, body, False{}, loc, Param{x, elem(typ(over)), loc} <> Param{r, rt, loc} <> env, cs, ret, r, ss)
                          k : Ir <- block(left, t, False{}, loc, env, cs, ret, acc, ss)
                          Done{ILet{r, IFold{x, over, r, ILit{"None", rt, loc}, step, rt, loc}, IMaybe{r, k, IReturn{IVar{r, ret, loc}, loc}, ret, loc}, loc}})), u =>
                  S.choose(Result<&2, &2, S.Error, Ir>, String.eq(a, "") || String.eq(a, "?"), u =>
                    refuse(&2, Ir, loc, "for: the body must assign exactly one name bound before the loop (the accumulator)"), u =>
                    do Result<&2, &2, S.Error, Ir>:
                      +over : Ir <- expr(weight(Lint.field(h, "iter")), Lint.field(h, "iter"), env, cs, ret, ss)
                      ok : Unit <- listy(over, "for")
                      step : Ir <- block(left, body, False{}, loc, Param{x, elem(typ(over)), loc} <> env, cs, ret, a, ss)
                      k : Ir <- block(left, t, False{}, loc, env, cs, ret, acc, ss)
                      Done{ILet{a, IFold{x, over, a, IVar{a, type_in(env, a), loc}, step, type_in(env, a), loc}, k, loc}}))), u =>
                S.choose(Result<&2, &2, S.Error, Ir>, String.eq(tag, "Break") && loop && last, u => Done{IStop{IVar{acc, type_in(env, acc), loc}, loc}}, u =>
                  refuse(&2, Ir, loc, "outside the fragment: statement " ++ tag))))))))
    case 1n+p _:
      S.choose(Result<&2, &2, S.Error, Ir>, String.eq(acc, ""), u =>
        refuse(&2, Ir, near, "no return: falling off the end is outside the fragment"), u =>
        Done{IVar{acc, type_in(env, acc), near}})

# str, bool, list[T], T | None. `int` is refused: a Python int is unbounded and
# signed, and no contract here reads one from a parameter.
def ann(fuel: Nat, +j: S.Json, +near: S.Json) -> Result<&2, &2, S.Error, Ty>:
  match fuel:
    case 0n:
      fail(&2, Ty, S.Limit{}, S.JNull{}, "elaboration fuel exhausted")
    case 1n+p:
      +left = p
      +tag = Lint.tag_of(j)
      +id = N.string(Lint.field(j, "id"))
      +v = Lint.field(j, "value")
      +loc = S.choose(S.Json, Lint.is_null(j), u => near, u => Lint.field(j, "_loc"))
      S.choose(Result<&2, &2, S.Error, Ty>, String.eq(tag, "Name") && String.eq(id, "str"), u => Done{TStr{}}, u =>
        S.choose(Result<&2, &2, S.Error, Ty>, String.eq(tag, "Name") && String.eq(id, "bool"), u => Done{TBool{}}, u =>
          S.choose(Result<&2, &2, S.Error, Ty>, String.eq(tag, "Subscript") && String.eq(Lint.tag_of(v), "Name") && String.eq(N.string(Lint.field(v, "id")), "list"), u =>
            do Result<&2, &2, S.Error, Ty>:
              of : Ty <- ann(left, Lint.field(j, "slice"), loc)
              Done{TList{of}}, u =>
            S.choose(Result<&2, &2, S.Error, Ty>, String.eq(tag, "BinOp") && String.eq(Lint.tag_of(Lint.field(j, "op")), "BitOr") && is_const(Lint.field(j, "right"), "None"), u =>
              do Result<&2, &2, S.Error, Ty>:
                of : Ty <- ann(left, Lint.field(j, "left"), loc)
                Done{TMaybe{of}}, u =>
              refuse(&2, Ty, loc, "annotation outside the fragment (str, bool, list[T], T | None)")))))

# Types from the signature's parameters `gs`, names and spans from the source's
# `fs`: the two must name the same parameters in the same order.
def params(gs: S.Json, fs: S.Json) -> Result<&2, &2, S.Error, List<&2, Param>>:
  match gs fs:
    case S.JItem{+g, gt} S.JItem{+f, ft}:
      +name = N.string(Lint.field(f, "arg"))
      do Result<&2, &2, S.Error, List<&2, Param>>:
        a : Ty <- ann(weight(g), Lint.field(g, "annotation"), Lint.field(f, "_loc"))
        ok : Unit <- S.choose(Result<&2, &2, S.Error, Unit>, String.eq(name, N.string(Lint.field(g, "arg"))), u => Done{Unit{}}, u =>
          refuse(&2, Unit, Lint.field(f, "_loc"), "signature names a different parameter than " ++ name))
        ps : List<&2, Param> <- params(gt, ft)
        Done{Param{name, a, Lint.field(f, "_loc")} <> ps}
    case S.JEnd{} S.JEnd{}:
      Done{[]}
    case _ _:
      refuse(&2, List<&2, Param>, S.JNull{}, "signature and source disagree on the parameter count")

def header(fs: List<&2, Lint.Fact>, +loc: S.Json) -> Result<&2, &2, S.Error, Unit>:
  match fs:
    case Nil{}:
      Done{Unit{}}
    case Lint.Bad{at, msg} <> t:
      fail(&2, Unit, S.Unsupported{}, loc, msg)
    case Lint.Calls{g} <> t:
      header(t, loc)

def untyped(xs: S.Json) -> Bool:
  match xs:
    case S.JItem{h, t}:
      Lint.is_null(Lint.field(h, "annotation")) && untyped(t)
    case _:
      True{}

# The source def with the signature's annotations: a typed twin for Lint.header.
def plain_args(+f: S.Json) -> Bool:
  +a = Lint.field(f, "args")
  Lint.is_empty(Lint.field(f, "decorator_list")) && Lint.is_empty(Lint.field(a, "posonlyargs")) && Lint.is_empty(Lint.field(a, "kwonlyargs")) &&
    Lint.is_empty(Lint.field(a, "defaults")) && Lint.is_null(Lint.field(a, "vararg")) && Lint.is_null(Lint.field(a, "kwarg")) &&
    untyped(Lint.items(Lint.field(a, "args"))) && Lint.is_null(Lint.field(f, "returns"))

# The module must be closed and the def unique with a plain typed header: the
# same conditions, by the same code, as Lint's T0 kernel (SOUNDNESS.md A2).
# An unannotated def (repo_of) takes its types from `sig`, a closed module
# holding one annotated stub of the same name: a labeled assumption of the
# judge (A1: exact builtin types), never inferred. Then the source header must
# be plain and wholly unannotated, so no annotation is ever overridden.
# A def's header alone: parameter types from the signature stub (or the def's
# own annotations), names and spans from the source. Read before any body, so
# a call can be checked against a callee whose body has not been read yet.
def signature(+f: S.Json, +g: S.Json, +name: String) -> Result<&2, &2, S.Error, Sig>:
  do Result<&2, &2, S.Error, Sig>:
    ps : List<&2, Param> <- params(Lint.items(Lint.field(Lint.field(g, "args"), "args")), Lint.items(Lint.field(Lint.field(f, "args"), "args")))
    ret : Ty <- ann(weight(g), Lint.field(g, "returns"), Lint.field(f, "_loc"))
    Done{Sig{name, ps, ret, []}}

def with_sig(s: Sig, +f: S.Json, +cs: List<&2, Contract>, +ss: List<&2, Sig>, +loc: S.Json) -> Result<&2, &2, S.Error, Fn>:
  Sig{+name, +ps, +ret, post} = s
  do Result<&2, &2, S.Error, Fn>:
    +e : Ir <- block(weight(Lint.field(f, "body")), Lint.items(Lint.field(f, "body")), True{}, loc, ps, cs, ret, "", ss)
    Done{Fn{name, ps, ret, sure(e, ret), Pure{}, e, loc}}

def elaborate_def(+body: S.Json, +stubs: S.Json, +cs: List<&2, Contract>, +name: String, +ss: List<&2, Sig>) -> Result<&2, &2, S.Error, Fn>:
  +f = Lint.find_def(body, name)
  +stub = Lint.find_def(stubs, name)
  +g = S.choose(S.Json, Lint.is_null(stub), u => f, u => stub)
  +loc = Lint.field(f, "_loc")
  +ns = Lint.def_names(body)
  unique = S.choose(List<&2, Lint.Fact>, Nat.is_eq(Lint.count(ns, name), 1n), u => [], u =>
    [Lint.Bad{loc, "no unique def " ++ name}])
  source = S.choose(List<&2, Lint.Fact>, Lint.is_null(stub) || plain_args(f), u => [], u =>
    [Lint.Bad{loc, "a signature is given: the source header must be plain and unannotated"}])
  +bs = Lint.binds(f)
  global = S.choose(List<&2, Lint.Fact>, Lint.has(bs, "re") || Lint.has(bs, "len"), u =>
    [Lint.Bad{loc, "the def binds re or len, which Python then reads as a local"}], u => [])
  shadow = S.choose(List<&2, Lint.Fact>, Lint.has(ns, "re") || Lint.has(ns, "len"), u =>
    [Lint.Bad{loc, "a def of the module is named re or len, which revokes the builtin the contracts assume"}], u => [])
  do Result<&2, &2, S.Error, Fn>:
    ok : Unit <- header(List.append(&2, Lint.Fact, unique, List.append(&2, Lint.Fact, Lint.closed(body), List.append(&2, Lint.Fact, source,
      List.append(&2, Lint.Fact, global, List.append(&2, Lint.Fact, shadow, Lint.header(g)))))), loc)
    s : Sig <- signature(f, g, name)
    with_sig(s, f, cs, ss, loc)

def elaborate(m: S.Module, sig: S.Module, +cs: List<&2, Contract>, +name: String) -> Result<&2, &2, S.Error, Fn>:
  S.Module{body} = m
  S.Module{stubs} = sig
  elaborate_def(body, stubs, cs, name, [])

def some_def(ns: List<&2, String>, +loc: S.Json) -> Result<&2, &2, S.Error, Unit>:
  match ns:
    case Nil{}:
      refuse(&2, Unit, loc, "module: no top-level def to translate")
    case h <> t:
      Done{Unit{}}

def sigs_of(ns: List<&2, String>, +body: S.Json, +stubs: S.Json) -> Result<&2, &2, S.Error, List<&2, Sig>>:
  match ns:
    case Nil{}:
      Done{[]}
    case +n <> t:
      +f = Lint.find_def(body, n)
      +stub = Lint.find_def(stubs, n)
      do Result<&2, &2, S.Error, List<&2, Sig>>:
        s : Sig <- signature(f, S.choose(S.Json, Lint.is_null(stub), u => f, u => stub), n)
        rest : List<&2, Sig> <- sigs_of(t, body, stubs)
        Done{s <> rest}

def elaborate_each(ns: List<&2, String>, +body: S.Json, +stubs: S.Json, +cs: List<&2, Contract>, +ss: List<&2, Sig>) -> Result<&2, &2, S.Error, List<&2, Fn>>:
  match ns:
    case Nil{}:
      Done{[]}
    case +n <> t:
      do Result<&2, &2, S.Error, List<&2, Fn>>:
        f : Fn <- elaborate_def(body, stubs, cs, n, ss)
        rest : List<&2, Fn> <- elaborate_each(t, body, stubs, cs, ss)
        Done{f <> rest}

# The whole module: every top-level def, each elaborated against every def's
# signature, so the source may put a caller before its callee. Nothing is
# ranked here -- the kernel does that, and refuses what it cannot rank.
def elaborate_all(m: S.Module, sig: S.Module, +cs: List<&2, Contract>) -> Result<&2, &2, S.Error, List<&2, Fn>>:
  S.Module{+body} = m
  S.Module{+stubs} = sig
  +ns = Lint.def_names(body)
  do Result<&2, &2, S.Error, List<&2, Fn>>:
    ok : Unit <- some_def(ns, Lint.field(Lint.first(body), "_loc"))
    ss : List<&2, Sig> <- sigs_of(ns, body, stubs)
    elaborate_each(ns, body, stubs, cs, ss)

# ---- verify: the kernel ----

def spanned(loc: S.Json) -> Bool:
  Bool.not(String.eq(Lint.span(loc), "?"))

def bound(env: List<&2, Param>, +id: String, +want: String) -> Bool:
  match env:
    case Nil{}:
      False{}
    case Param{name, t, loc} <> rest:
      S.choose(Bool, String.eq(name, id), u => String.eq(ty(t), want), u => bound(rest, id, want))

# Names and literals only: what a fact may mention and a guard may be asked of.
def simple(e: Ir) -> Bool:
  match e:
    case IVar{name, t, loc}:
      True{}
    case ILit{text, t, loc}:
      True{}
    case IArg{h, t}:
      simple(h) && simple(t)
    case IEnd{}:
      True{}
    case _:
      False{}

def solid(e: Ir) -> Bool:
  match e:
    case ILit{text, +t, loc}:
      Bool.not(String.is_empty(text)) && (String.eq(ty(t), "String") || String.eq(ty(t), "Nat"))
    case IArg{h, t}:
      solid(h) && solid(t)
    case IEnd{}:
      True{}
    case _:
      False{}

# What a test's outcome makes known on the path: the primitive call itself, of
# names and literals, seen through not/or/and. The kernel drops every fact at
# every binder, so a fact never outlives the names it mentions; except where
# IMaybe's some arm rebinds `on` to its own payload, the same value narrowed.
def known(e: Ir, +want: Bool) -> List<&2, Ir>:
  match e:
    case IArg{h, t}:
      known(h, want)
    case IPrim{+bend, +args, +t, +loc}:
      S.choose(List<&2, Ir>, String.eq(bend, "Bool.not"), u => known(args, Bool.not(want)), u =>
        S.choose(List<&2, Ir>, want && simple(args), u => [IPrim{bend, args, t, loc}], u => []))
    case IBranch{+test, +yes, +no, t, loc}:
      +or = is_lit(yes, "True") && Bool.not(want)
      +and = is_lit(no, "False") && want
      S.choose(List<&2, Ir>, or, u => List.append(&2, Ir, known(test, False{}), known(no, False{})), u =>
        S.choose(List<&2, Ir>, and, u => List.append(&2, Ir, known(test, True{}), known(yes, True{})), u => []))
    case _:
      []

# What a let makes known: `m = re.search(p, ...)` binds a match that, if any,
# took every group p must take (Py.took is a fact, not a primitive); and
# `v = g(...)` binds a value carrying every postcondition the kernel minted
# into g's signature. A call the ICall rule does not grant never reaches an
# emission, so a fact read off an ungranted call cannot outlive its refusal.
def lets(+name: String, val: Ir, +loc: S.Json, +ss: List<&2, Sig>) -> List<&2, Ir>:
  match val:
    case IPrim{+bend, args, t, l}:
      S.choose(List<&2, Ir>, String.eq(bend, "Py.search"), u =>
        [IPrim{"Py.took", IArg{IVar{name, TBad{}, loc}, IArg{hd(tl(args)), IEnd{}}}, TBool{}, loc}], u => [])
    case ICall{+n, args, t, l}:
      facts_of(posts_in(ss, n), name, loc)
    case _:
      []

def text_of(e: Ir) -> String:
  match e:
    case ILit{text, t, loc}:
      text
    case _:
      ""

# Group k takes part in every match of r, so m.group(k) is a string, not None.
def must(r: Re, +k: String) -> Bool:
  match r:
    case RCap{n, x}:
      String.eq(Nat.show(n), k) || must(x, k)
    case RCat{a, b}:
      must(a, k) || must(b, k)
    case RAlt{a, b}:
      must(a, k) && must(b, k)
    case RRep{x, lo, hi, g}:
      Nat.is_gt(lo, 0n) && must(x, k)
    case _:
      False{}

def took(r: Regex.Res(Re), +k: String) -> Bool:
  match r:
    case Done{x}:
      must(x, k)
    case Fail{e}:
      False{}

def compiles(r: Regex.Res(Regex)) -> Bool:
  match r:
    case Done{x}:
      True{}
    case Fail{e}:
      False{}

# Does the fact give the guard `pre` of these arguments? Itself; or
# `startswith(x, q)` -- and `q in x`, which is how a callee's postcondition
# arrives -- gives `sep in x` when q holds sep, sound by transitivity of
# substring; or `Py.took(m, p)` gives the group `m.group(k)` asks for.
def gives(f: Ir, +pre: String, +args: Ir) -> Bool:
  match f:
    case IPrim{+b, +fa, t, loc}:
      +x = String.eq(show(hd(fa), "", []), show(hd(args), "", []))
      +q = hd(tl(fa))
      (String.eq(b, pre) && String.eq(show(fa, "", []), show(args, "", []))) ||
        (x && String.eq(pre, "String.contains") && (String.eq(b, "String.starts_with") || String.eq(b, pre)) && solid(tl(fa)) &&
          String.contains(text_of(q), text_of(hd(tl(args))))) ||
        (x && String.eq(pre, "Py.took") && String.eq(b, pre) && took(Regex.parse(text_of(q)), text_of(hd(tl(args)))))
    case _:
      False{}

def holds(fs: List<&2, Ir>, +pre: String, +args: Ir) -> Bool:
  match fs:
    case Nil{}:
      False{}
    case f <> rest:
      gives(f, pre, args) || holds(rest, pre, args)

# A guard that the literal arguments decide alone. The one flag contracted is re.S.
def static(+pre: String, +args: Ir) -> Bool:
  String.eq(pre, "literal") || (String.eq(pre, "positive") && Bool.not(String.eq(text_of(hd(tl(args))), "0"))) ||
    (String.eq(pre, "Regex.compile") && String.eq(text_of(hd(tl(tl(args)))), "s") && compiles(Regex.compile(text_of(hd(tl(args))), "s")))

# A contract grants `bend` at these types; a guarded one (`pre`) only where the
# arguments after the receiver are literals and the guard is decided by them or
# given by a fact known on the path (then the receiver is a name).
def granted(cs: List<&2, Contract>, +bend: String, +args: Ir, +ret: String, +facts: List<&2, Ir>) -> Bool:
  match cs:
    case Nil{}:
      False{}
    case Contract{r, method, as, out, b, pure, total, +pre, src} <> rest:
      guard = String.is_empty(pre) || (solid(tl(args)) && (static(pre, args) || (simple(args) && holds(facts, pre, args))))
      (String.eq(b, bend) && String.eq(ty(r) ++ ";" ++ tys(as), arg_tys(args)) && String.eq(ty(out), ret) && pure && total && guard) ||
        granted(rest, bend, args, ret, facts)

def ident_tail(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{h, t}:
      +n = Char.to_u32(h)
      ((U32.is_ge(n, 97) && U32.is_le(n, 122)) || (U32.is_ge(n, 48) && U32.is_le(n, 57)) || U32.is_eq(n, 95)) && ident_tail(t)

# ponytail: lower-case ASCII names only, and no reserved-word list: a Python
# name that is a Bend keyword fails the strict check (C1) loudly. Upgrade: mangle.
# A helper's own names (_c, _xs, _st, _rest, f.kind_l_c) are not idents.
def ident(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{h, t}:
      +n = Char.to_u32(h)
      U32.is_ge(n, 97) && U32.is_le(n, 122) && ident_tail(t)

def idents(ps: List<&2, Param>) -> Bool:
  match ps:
    case Nil{}:
      True{}
    case Param{name, t, loc} <> rest:
      ident(name) && spanned(loc) && idents(rest)

# Where a node stands: the function's tail (every path ends in IReturn), a fold
# step (a path ends in the accumulator's next value or IStop), or an argument.
type Pos is Data:
  PTail{}
  PStep{acc: String}
  PArg{}

def is_arg(p: Pos) -> Bool:
  match p:
    case PArg{}:
      True{}
    case _:
      False{}

def is_tail(p: Pos) -> Bool:
  match p:
    case PTail{}:
      True{}
    case _:
      False{}

def acc_of(p: Pos) -> String:
  match p:
    case PStep{acc}:
      acc
    case _:
      ""

def lit_ok(+text: String, t: Ty) -> Bool:
  match t:
    case TStr{}:
      plain(text, 0, 0)
    case TInt{}:
      natural(text)
    case TBool{}:
      String.eq(text, "True") || String.eq(text, "False")
    case TMaybe{of}:
      String.eq(text, "None")
    case _:
      False{}

def both(a: String, +b: String) -> String:
  match a:
    case SNil{}:
      b
    case SCon{h, t}:
      SCon{h, t}

# "" iff the node is inside the emittable fragment: bound, typed, spanned, in a
# position that can hold it, every primitive granted by a contract (and its
# guard known). Recomputed from the IR alone; the elaborator is not trusted.
def why(e: Ir, +pos: Pos, +env: List<&2, Param>, +facts: List<&2, Ir>, +cs: List<&2, Contract>, +ss: List<&2, Sig>) -> String:
  match e:
    case IVar{+name, t, +loc}:
      S.choose(String, spanned(loc) && bound(env, name, ty(t)), u => "", u => "unbound or mistyped name " ++ name ++ Lint.at(loc))
    case ILit{text, t, +loc}:
      S.choose(String, spanned(loc) && lit_ok(text, t), u => "", u => "literal outside the contract" ++ Lint.at(loc))
    case IPrim{+bend, +args, t, +loc}:
      S.choose(String, spanned(loc) && granted(cs, bend, args, ty(t), facts), u => why(args, PArg{}, env, facts, cs, ss), u =>
        "primitive " ++ bend ++ " is not granted by a contract (or its guard is not known here)" ++ Lint.at(loc))
    case IArg{h, t}:
      both(why(h, PArg{}, env, facts, cs, ss), why(t, PArg{}, env, facts, cs, ss))
    case IEnd{}:
      ""
    case IReturn{val, +loc}:
      S.choose(String, spanned(loc) && is_tail(pos), u => why(val, PArg{}, env, facts, cs, ss), u => "return outside tail position" ++ Lint.at(loc))
    case IStop{+val, +loc}:
      S.choose(String, spanned(loc) && bound(env, acc_of(pos), ty_of(val)), u => why(val, PArg{}, env, facts, cs, ss), u =>
        "break outside a fold step, or not of the accumulator's type" ++ Lint.at(loc))
    case ICall{+name, +args, +t, +loc}:
      S.choose(String, spanned(loc) && ident(name) && Bool.not(has_name(env, name)) && resolves(ss, name, args, ty(t)), u =>
        why(args, PArg{}, env, facts, cs, ss), u =>
        "call " ++ name ++ "(" ++ arg_tys(args) ++ ") -> " ++ ty(t) ++ " is granted by no def ranked below this one" ++ Lint.at(loc))
    case ISome{+val, t, +loc}:
      S.choose(String, spanned(loc) && String.eq(ty(inner(t)), ty_of(val)) && Bool.not(String.is_empty(ty_of(val))), u =>
        why(val, PArg{}, env, facts, cs, ss), u => "Some of a mistyped value" ++ Lint.at(loc))
    case ILet{+name, +val, body, +loc}:
      +stepped = String.is_empty(acc_of(pos)) || String.eq(acc_of(pos), name) || Bool.not(has_name(env, name))
      +kept = Bool.not(has_name(env, name)) || bound(env, name, ty_of(val))
      ok = spanned(loc) && ident(name) && Bool.not(is_arg(pos)) && Bool.not(String.is_empty(ty_of(val))) && stepped && kept
      S.choose(String, ok, u => both(why(val, PArg{}, env, facts, cs, ss), why(body, pos, Param{name, typ(val), loc} <> env, lets(name, val, loc, ss), cs, ss)), u =>
        "let of " ++ name ++ ": in argument position, retyped, or rebinding a captured name inside a fold step" ++ Lint.at(loc))
    case IBranch{+test, +yes, +no, +t, +loc}:
      ok = spanned(loc) && String.eq(ty_of(test), "Bool") && String.eq(ty_of(yes), ty(t)) && String.eq(ty_of(no), ty(t)) && Bool.not(String.is_empty(ty(t)))
      S.choose(String, ok, u => both(why(test, PArg{}, env, facts, cs, ss), both(why(yes, pos, env, List.append(&2, Ir, known(test, True{}), facts), cs, ss),
        why(no, pos, env, List.append(&2, Ir, known(test, False{}), facts), cs, ss))), u => "branch on a non-Bool test, or arms of another type" ++ Lint.at(loc))
    case IMaybe{+on, +none, +some, +t, +loc}:
      ok = spanned(loc) && ident(on) && is_maybe(type_in(env, on)) && Nat.is_eq(reads(none, on), 0n) &&
        String.eq(ty_of(none), ty(t)) && String.eq(ty_of(some), ty(t)) && Bool.not(String.is_empty(ty(t)))
      S.choose(String, ok, u => both(why(none, pos, env, facts, cs, ss), why(some, pos, Param{on, inner(type_in(env, on)), loc} <> env, facts, cs, ss)), u =>
        "Optional match on a name that is not Optional, a None arm that reads it, or arms of another type" ++ Lint.at(loc))
    case IFold{+item, +over, +acc, +init, +step, +t, +loc}:
      ok = spanned(loc) && ident(item) && ident(acc) && Bool.not(String.eq(item, acc)) && Bool.not(String.is_empty(ty(elem(typ(over))))) &&
        String.eq(ty_of(init), ty(t)) && String.eq(ty_of(step), ty(t)) && Bool.not(String.is_empty(ty(t)))
      S.choose(String, ok, u => both(why(over, PArg{}, env, facts, cs, ss), both(why(init, PArg{}, env, facts, cs, ss),
        why(step, PStep{acc}, Param{acc, t, loc} <> Param{item, elem(typ(over)), loc} <> env, [], cs, ss))), u =>
        "fold over a non-list, item = accumulator, or a step of another type" ++ Lint.at(loc))
    case IList{+items, +t, +loc}:
      ok = spanned(loc) && Bool.not(String.is_empty(ty(elem(t)))) && all_ty(items, ty(elem(t)))
      S.choose(String, ok, u => why(items, PArg{}, env, facts, cs, ss), u => "list of items not all of its element type" ++ Lint.at(loc))
    case IMap{+item, +over, +body, +t, +loc}:
      ok = spanned(loc) && ident(item) && Bool.not(String.is_empty(ty(elem(typ(over))))) && Bool.not(String.is_empty(ty_of(body))) &&
        String.eq(ty(t), ty(TList{typ(body)}))
      S.choose(String, ok, u => both(why(over, PArg{}, env, facts, cs, ss),
        why(body, PArg{}, Param{item, elem(typ(over)), loc} <> env, items_of(facts, over, item, loc), cs, ss)), u =>
        "comprehension over a non-list, or of another type" ++ Lint.at(loc))

# The type every tail path returns; "" if any path does not end in IReturn.
def returned(e: Ir) -> String:
  match e:
    case IReturn{val, loc}:
      ty_of(val)
    case ILet{name, val, body, loc}:
      returned(body)
    case IBranch{test, yes, no, t, loc}:
      +a = returned(yes)
      S.choose(String, String.eq(a, returned(no)), u => a, u => "")
    case IMaybe{on, none, some, t, loc}:
      +a = returned(none)
      S.choose(String, String.eq(a, returned(some)), u => a, u => "")
    case _:
      ""

# Every helper def name the renderer will use.
def helpers(e: Ir, +f: String) -> List<&2, String>:
  match e:
    case IPrim{bend, args, t, loc}:
      helpers(args, f)
    case ICall{name, args, t, loc}:
      helpers(args, f)
    case IArg{h, t}:
      List.append(&2, String, helpers(h, f), helpers(t, f))
    case IReturn{val, loc}:
      helpers(val, f)
    case IStop{val, loc}:
      helpers(val, f)
    case ISome{val, t, loc}:
      helpers(val, f)
    case ILet{name, val, body, loc}:
      List.append(&2, String, helpers(val, f), helpers(body, f))
    case IBranch{test, +yes, +no, t, loc}:
      hname(f, bkind(yes, no), loc) <> List.append(&2, String, helpers(test, f), List.append(&2, String, helpers(yes, f), helpers(no, f)))
    case IMaybe{on, none, some, t, loc}:
      hname(f, "opt", loc) <> List.append(&2, String, helpers(none, f), helpers(some, f))
    case IFold{item, over, acc, init, step, t, loc}:
      hname(f, "for", loc) <> List.append(&2, String, helpers(over, f), List.append(&2, String, helpers(init, f), helpers(step, f)))
    case IList{items, t, loc}:
      helpers(items, f)
    case IMap{item, over, body, t, loc}:
      hname(f, "comp", loc) <> List.append(&2, String, helpers(over, f), helpers(body, f))
    case _:
      []

def distinct(xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case +h <> +t:
      Bool.not(Lint.has(t, h)) && distinct(t)

def is_pure(e: Eff) -> Bool:
  match e:
    case Pure{}:
      True{}
    case Impure{}:
      False{}

# A def against the signatures of the defs the kernel already accepted: every
# call in its body must name one of them. T1-T3 pass [], so a call is refused
# there exactly as before.
def verify_in(f: Fn, +ss: List<&2, Sig>, +cs: List<&2, Contract>) -> Result<&2, &2, S.Error, Fn>:
  Fn{+name, +ps, +ret, +post, +eff, +body, +loc} = f
  +bad = why(body, PTail{}, ps, [], cs, ss)
  +loose = unbacked(post, sure(body, ret))
  S.choose(Result<&2, &2, S.Error, Fn>, Bool.not(ident(name) && idents(ps) && spanned(loc)), u =>
    refuse(&2, Fn, loc, "name or span not emittable"), u =>
    S.choose(Result<&2, &2, S.Error, Fn>, Bool.not(String.is_empty(bad)), u => fail(&2, Fn, S.Unsupported{}, loc, bad), u =>
      S.choose(Result<&2, &2, S.Error, Fn>, Bool.not(String.eq(returned(body), ty(ret))), u =>
        refuse(&2, Fn, loc, "body does not return " ++ ty(ret)), u =>
        S.choose(Result<&2, &2, S.Error, Fn>, Bool.not(distinct(helpers(body, name))), u => refuse(&2, Fn, loc, "two helper defs share a name"), u =>
          S.choose(Result<&2, &2, S.Error, Fn>, Bool.not(String.is_empty(loose)), u =>
            refuse(&2, Fn, loc, "the postcondition that " ++ loose ++ " is not established by this body: drop the claim, or make every path carry it"), u =>
            S.choose(Result<&2, &2, S.Error, Fn>, Bool.not(is_pure(eff)), u => refuse(&2, Fn, loc, "effect is not Pure"), u =>
              Done{Fn{name, ps, ret, post, eff, body, loc}}))))))

def verify(f: Fn, +cs: List<&2, Contract>) -> Result<&2, &2, S.Error, Fn>:
  verify_in(f, [], cs)

# The signatures with this def's own added, so the defs ranked above may call
# it. Two defs of one name are refused here: the module would emit two defs of
# that name, and no call could say which. The source path cannot state it
# (`unique`), but a TypedIR is data.
def fresh(f: Fn, +ss: List<&2, Sig>) -> Result<&2, &2, S.Error, List<&2, Sig>>:
  Fn{+name, +ps, +ret, +post, eff, body, +loc} = f
  S.choose(Result<&2, &2, S.Error, List<&2, Sig>>, named(ss, name), u =>
    refuse(&2, List<&2, Sig>, loc, "two defs of the module are named " ++ name), u =>
    Done{List.append(&2, Sig, ss, [Sig{name, ps, ret, post}])})

def placed(r: Result<&2, &2, S.Error, Fn>) -> Bool:
  match r:
    case Done{g}:
      True{}
    case Fail{e}:
      False{}

# `fs` with a def the kernel accepts against `ss` in front and the others in
# order; `fs` in its own order when none is, so `order` then reports that
# def's own diagnostic rather than inventing an ordering one.
def first_ready(fs: List<&2, Fn>, +seen: List<&2, Fn>, +ss: List<&2, Sig>, +cs: List<&2, Contract>) -> List<&2, Fn>:
  match fs:
    case Nil{}:
      seen
    case +f <> +t:
      S.choose(List<&2, Fn>, placed(verify_in(f, ss, cs)), u => f <> List.append(&2, Fn, seen, t), u =>
        first_ready(t, List.append(&2, Fn, seen, [f]), ss, cs))

# The rank: peel the def the kernel accepts against the signatures held so
# far, add its signature, look again. List position IS the rank, so a callee
# always precedes its caller and neither a cycle nor a self-call can ever be
# peeled -- each is a call no prefix grants, reported at the call.
# ponytail: n passes over n defs, each re-verified; a module is a handful of
# defs. A real ranking pass if that stops being true.
def order(fuel: Nat, fs: List<&2, Fn>, +ss: List<&2, Sig>, +cs: List<&2, Contract>) -> Result<&2, &2, S.Error, List<&2, Fn>>:
  match fuel fs:
    case 0n _:
      fail(&2, List<&2, Fn>, S.Limit{}, S.JNull{}, "module ranking fuel exhausted")
    case 1n+p Nil{}:
      Done{[]}
    case 1n+p Con{+f, +t}:
      +left = p
      do Result<&2, &2, S.Error, List<&2, Fn>>:
        +g : Fn <- verify_in(f, ss, cs)
        +more : List<&2, Sig> <- fresh(g, ss)
        rest : List<&2, Fn> <- order(left, first_ready(t, [], more, cs), more, cs)
        Done{g <> rest}

def ordered(+fs: List<&2, Fn>, +cs: List<&2, Contract>) -> Result<&2, &2, S.Error, List<&2, Fn>>:
  order(Nat.add(1n, List.length(&2, Fn, fs)), first_ready(fs, [], [], cs), [], cs)

# ---- emit: render what the kernel accepted ----

def kind(e: Ir) -> String:
  match e:
    case IVar{name, t, loc}:
      "Var " ++ name
    case ILit{text, t, loc}:
      "Lit " ++ lit_text(text, t)
    case IPrim{bend, args, t, loc}:
      "Prim " ++ bend
    case ICall{name, args, t, loc}:
      "Call " ++ name
    case IReturn{val, loc}:
      "Return"
    case IStop{val, loc}:
      "Stop"
    case ISome{val, t, loc}:
      "Some"
    case ILet{name, val, body, loc}:
      "Let " ++ name
    case IBranch{test, yes, no, t, loc}:
      "Branch " ++ bkind(yes, no)
    case IMaybe{on, none, some, t, loc}:
      "Opt " ++ on
    case IFold{item, over, acc, init, step, t, loc}:
      "Fold " ++ item ++ " -> " ++ acc
    case IList{items, t, loc}:
      "List"
    case IMap{item, over, body, t, loc}:
      "Map " ++ item
    case _:
      "?"

# One span-map row, placed relative to its def: line `dl` of the def, columns
# col..col+w. `tail` is the Python side.
type Row is Data:
  Row{dl: Nat, col: Nat, w: Nat, tail: String}

# One rendered def: its text (ending in a newline) and its rows.
type Def is Data:
  Def{text: String, rows: List<&2, Row>}

# A let's row carries the type of the value it binds.
def row_ty(e: Ir) -> String:
  match e:
    case ILet{name, val, body, loc}:
      ty_of(val)
    case other:
      ty_of(other)

def row(+e: Ir, w: Nat, dl: Nat, col: Nat) -> Row:
  Row{dl, col, w, " <- py " ++ Lint.span(own_loc(e)) ++ " " ++ kind(e) ++ " : " ++ row_ty(e) ++ "\n"}

# The rows of an expression shown on one line from `col`: one per IR node.
def xrows(e: Ir, +f: String, +env: List<&2, Param>, +dl: Nat, +col: Nat) -> List<&2, Row>:
  match e:
    case IPrim{+bend, +args, +t, +loc}:
      row(IPrim{bend, args, t, loc}, String.length(show(IPrim{bend, args, t, loc}, f, env)), dl, col) <>
        xrows(args, f, env, dl, Nat.add(col, 1n+String.length(bend)))
    case ICall{+name, +args, +t, +loc}:
      row(ICall{name, args, t, loc}, String.length(show(ICall{name, args, t, loc}, f, env)), dl, col) <>
        xrows(args, f, env, dl, Nat.add(col, 1n+String.length(name)))
    case IArg{+h, +t}:
      List.append(&2, Row, xrows(h, f, env, dl, col), xrows(t, f, env, dl, Nat.add(col, Nat.add(String.length(show(h, f, env)), String.length(sep(t))))))
    case IReturn{+val, +loc}:
      row(IReturn{val, loc}, String.length(show(val, f, env)), dl, col) <> xrows(val, f, env, dl, col)
    case IStop{+val, +loc}:
      row(IStop{val, loc}, String.length(show(val, f, env)), dl, col) <> xrows(val, f, env, dl, col)
    case ISome{+val, +t, +loc}:
      row(ISome{val, t, loc}, Nat.add(6n, String.length(show(val, f, env))), dl, col) <> xrows(val, f, env, dl, Nat.add(col, 5n))
    case IBranch{+test, +yes, +no, +t, +loc}:
      row(IBranch{test, yes, no, t, loc}, String.length(show(IBranch{test, yes, no, t, loc}, f, env)), dl, col) <>
        xrows(test, f, env, dl, Nat.add(col, 1n+String.length(hname(f, bkind(yes, no), loc))))
    case IFold{+item, +over, +acc, +init, +step, +t, +loc}:
      +at = Nat.add(col, 1n+String.length(hname(f, "for", loc)))
      +to = Nat.add(at, Nat.add(String.length(show(over, f, env)), Nat.add(2n, String.length(seed("", stops(step))))))
      row(IFold{item, over, acc, init, step, t, loc}, String.length(show(IFold{item, over, acc, init, step, t, loc}, f, env)), dl, col) <>
        List.append(&2, Row, xrows(over, f, env, dl, at), xrows(init, f, env, dl, S.choose(Nat, stops(step), u => Nat.sub(to, 1n), u => to)))
    case IList{+items, +t, +loc}:
      row(IList{items, t, loc}, String.length(show(IList{items, t, loc}, f, env)), dl, col) <> xrows(items, f, env, dl, 1n+col)
    case IMap{+item, +over, +body, +t, +loc}:
      row(IMap{item, over, body, t, loc}, String.length(show(IMap{item, over, body, t, loc}, f, env)), dl, col) <>
        xrows(over, f, env, dl, Nat.add(col, 1n+String.length(hname(f, "comp", loc))))
    case IEnd{}:
      []
    case +other:
      [row(other, String.length(show(other, f, env)), dl, col)]

def atop(text: String, rs: List<&2, Row>, d: Def) -> Def:
  Def{rest, rows} = d
  Def{text ++ rest, List.append(&2, Row, rs, rows)}

def mark(n: Nat) -> String:
  S.choose(String, Nat.is_gt(n, 1n), u => "+", u => "")

def pad(n: Nat) -> String:
  match n:
    case 0n:
      ""
    case 1n+p:
      " " ++ pad(p)

# A fold step that can `break` yields a Step: Stop{v} at a break, Continue{v}
# otherwise. A tail branch is a call of a helper that already yields a Step.
def wrap_of(e: Ir, +wrap: Bool) -> String:
  match e:
    case IStop{val, loc}:
      "Stop{"
    case IBranch{test, yes, no, t, loc}:
      ""
    case IMaybe{on, none, some, t, loc}:
      ""
    case _:
      S.choose(String, wrap, u => "Continue{", u => "")

def close(open: String) -> String:
  S.choose(String, String.is_empty(open), u => "", u => "}")

# A block from line `dl` at indent `ind`: one line per let, then the tail as
# `pre` tail `post`. A let is always annotated: `x = {v : T}`.
def blk(e: Ir, +f: String, +env: List<&2, Param>, +dl: Nat, +ind: Nat, +pre: String, +post: String, +wrap: Bool) -> Def:
  match e:
    case ILet{+name, +val, +body, +loc}:
      +m = mark(reads(body, name))
      +line = pad(ind) ++ m ++ name ++ " = {" ++ show(val, f, env) ++ " : " ++ ty_of(val) ++ "}"
      atop(line ++ "\n", row(ILet{name, val, body, loc}, Nat.sub(String.length(line), ind), dl, ind) <>
        xrows(val, f, env, dl, Nat.add(ind, Nat.add(String.length(m ++ name), 4n))),
        blk(body, f, Param{name, typ(val), loc} <> env, 1n+dl, ind, pre, post, wrap))
    case +other:
      +w = wrap_of(other, wrap)
      Def{pad(ind) ++ pre ++ w ++ show(other, f, env) ++ close(w) ++ post ++ "\n",
        xrows(other, f, env, dl, Nat.add(ind, String.length(pre ++ w)))}

def height(e: Ir) -> Nat:
  match e:
    case ILet{name, val, body, loc}:
      1n+height(body)
    case _:
      1n

# Helper parameters: `+` on a name its busiest arm reads twice; always in a
# fold, whose every iteration reads its captures again.
def sigs(cs: List<&2, Param>, +arms: Ir, +always: Bool) -> String:
  match cs:
    case Nil{}:
      ""
    case Param{+name, t, loc} <> rest:
      ", " ++ S.choose(String, always, u => "+", u => mark(busiest(arms, name))) ++ name ++ ": " ++ ty(t) ++ sigs(rest, arms, always)

def out(+t: Ty, wrap: Bool) -> String:
  S.choose(String, wrap, u => "Step<" ++ ty(t) ++ ">", u => ty(t))

def two_arms(+head: String, +a: String, +b: String, x: Def, y: Def) -> Def:
  Def{xt, xr} = x
  Def{yt, yr} = y
  Def{head ++ "    case " ++ a ++ ":\n" ++ xt ++ "    case " ++ b ++ ":\n" ++ yt, List.append(&2, Row, xr, yr)}

# The helper defs of `e`, innermost first (a def precedes its uses), for a node
# in block position under `wrap`. A branch is a match on the helper's Bool
# parameter, an Optional test a match on the name, a fold a structural
# recursion on the list: only the taken arm is ever evaluated.
def defs(e: Ir, +f: String, +env: List<&2, Param>, +wrap: Bool) -> List<&2, Def>:
  match e:
    case IPrim{bend, args, t, loc}:
      defs(args, f, env, False{})
    case ICall{name, args, t, loc}:
      defs(args, f, env, False{})
    case IArg{h, t}:
      List.append(&2, Def, defs(h, f, env, False{}), defs(t, f, env, False{}))
    case IReturn{val, loc}:
      defs(val, f, env, False{})
    case IStop{val, loc}:
      defs(val, f, env, False{})
    case ISome{val, t, loc}:
      defs(val, f, env, False{})
    case ILet{+name, +val, body, +loc}:
      List.append(&2, Def, defs(val, f, env, False{}), defs(body, f, Param{name, typ(val), loc} <> env, wrap))
    case IBranch{test, +yes, +no, +t, +loc}:
      +arms = {IArg{yes, IArg{no, IEnd{}}} : Ir}
      head = "def " ++ hname(f, bkind(yes, no), loc) ++ "(_c: Bool" ++ sigs(caps(env, arms, []), arms, False{}) ++ ") -> " ++ out(t, wrap) ++ ":\n  match _c:\n"
      List.append(&2, Def, defs(test, f, env, False{}), List.append(&2, Def, defs(yes, f, env, wrap), List.append(&2, Def, defs(no, f, env, wrap),
        [two_arms(head, "True{}", "False{}", blk(yes, f, env, 3n, 6n, "", "", wrap), blk(no, f, env, Nat.add(4n, height(yes)), 6n, "", "", wrap))])))
    case IMaybe{+on, +none, +some, +t, +loc}:
      +arms = {IArg{none, IArg{some, IEnd{}}} : Ir}
      +inside = {Param{on, inner(type_in(env, on)), loc} <> env : List<&2, Param>}
      head = "def " ++ hname(f, "opt", loc) ++ "(" ++ on ++ ": " ++ ty(type_in(env, on)) ++ sigs(caps(env, arms, [on]), arms, False{}) ++ ") -> " ++ out(t, wrap) ++
        ":\n  match " ++ on ++ ":\n"
      List.append(&2, Def, defs(none, f, env, wrap), List.append(&2, Def, defs(some, f, inside, wrap),
        [two_arms(head, "None{}", "Some{" ++ mark(reads(some, on)) ++ on ++ "}", blk(none, f, env, 3n, 6n, "", "", wrap),
          blk(some, f, inside, Nat.add(4n, height(none)), 6n, "", "", wrap))]))
    case IFold{+item, +over, +acc, init, +step, +t, +loc}:
      +stop = stops(step)
      +inside = {Param{acc, t, loc} <> Param{item, elem(typ(over)), loc} <> env : List<&2, Param>}
      +cs = caps(env, IArg{step, IEnd{}}, [item, acc])
      +name = hname(f, "for", loc)
      +pat = "Con{" ++ mark(reads(step, item)) ++ item ++ ", _rest}"
      +am = mark(reads(step, acc)) ++ acc
      +xs = "_xs: " ++ ty(typ(over))
      head = S.choose(String, stop, u =>
        "def " ++ name ++ "(" ++ xs ++ ", _st: Step<" ++ ty(t) ++ ">" ++ sigs(cs, IEnd{}, True{}) ++ ") -> " ++ ty(t) ++ ":\n  match _xs _st:\n" ++
          "    case Nil{} Continue{" ++ acc ++ "}:\n      " ++ acc ++ "\n    case Nil{} Stop{" ++ acc ++ "}:\n      " ++ acc ++ "\n" ++
          "    case Con{_x, _rest} Stop{" ++ acc ++ "}:\n      " ++ acc ++ "\n    case " ++ pat ++ " Continue{" ++ am ++ "}:\n", u =>
        "def " ++ name ++ "(" ++ xs ++ ", " ++ am ++ ": " ++ ty(t) ++ sigs(cs, IEnd{}, True{}) ++ ") -> " ++ ty(t) ++ ":\n  match _xs:\n" ++
          "    case Nil{}:\n      " ++ acc ++ "\n    case " ++ pat ++ ":\n")
      List.append(&2, Def, defs(over, f, env, False{}), List.append(&2, Def, defs(init, f, env, False{}), List.append(&2, Def, defs(step, f, inside, stop),
        [atop(head, [], blk(step, f, inside, S.choose(Nat, stop, u => 9n, u => 5n), 6n, name ++ "(_rest, ", argl(cs) ++ ")", stop))])))
    case IList{items, t, loc}:
      defs(items, f, env, False{})
    case IMap{+item, +over, +body, +t, +loc}:
      +inside = {Param{item, elem(typ(over)), loc} <> env : List<&2, Param>}
      +cs = caps(env, IArg{body, IEnd{}}, [item])
      +name = hname(f, "comp", loc)
      head = "def " ++ name ++ "(_xs: " ++ ty(typ(over)) ++ sigs(cs, IEnd{}, True{}) ++ ") -> " ++ ty(t) ++ ":\n  match _xs:\n" ++
        "    case Nil{}:\n      []\n    case Con{" ++ mark(reads(body, item)) ++ item ++ ", _rest}:\n"
      List.append(&2, Def, defs(over, f, env, False{}), List.append(&2, Def, defs(body, f, inside, False{}),
        [atop(head, [], blk(body, f, inside, 5n, 6n, "", " <> " ++ name ++ "(_rest" ++ argl(cs) ++ ")", False{}))]))
    case _:
      []

def sig(ps: List<&2, Param>, +body: Ir, lead: String) -> String:
  match ps:
    case Nil{}:
      ""
    case Param{+name, t, loc} <> rest:
      lead ++ mark(reads(body, name)) ++ name ++ ": " ++ ty(t) ++ sig(rest, body, ", ")

def param_rows(ps: List<&2, Param>, +body: Ir, +col: Nat) -> List<&2, Row>:
  match ps:
    case Nil{}:
      []
    case Param{+name, +t, loc} <> rest:
      +w = String.length(mark(reads(body, name)) ++ name ++ ": " ++ ty(t))
      Row{0n, col, w, " <- py " ++ Lint.span(loc) ++ " Param " ++ name ++ " : " ++ ty(t) ++ "\n"} <> param_rows(rest, body, Nat.add(col, Nat.add(w, 2n)))

def nl(s: String) -> Nat:
  match s:
    case SNil{}:
      0n
    case SCon{h, t}:
      Nat.add(one(U32.is_eq(Char.to_u32(h), 10)), nl(t))

def row_text(rs: List<&2, Row>, +at: Nat) -> String:
  match rs:
    case Nil{}:
      ""
    case Row{dl, +col, w, tail} <> rest:
      +line = Nat.show(Nat.add(at, dl))
      "# " ++ line ++ ":" ++ Nat.show(col) ++ "-" ++ line ++ ":" ++ Nat.show(Nat.add(col, w)) ++ tail ++ row_text(rest, at)

# Defs a blank line apart.
def code(ds: List<&2, Def>) -> String:
  match ds:
    case Nil{}:
      ""
    case Def{text, rows} <> rest:
      text ++ "\n" ++ code(rest)

# Their span rows, the first def starting at line `at`.
def maps(ds: List<&2, Def>, +at: Nat) -> String:
  match ds:
    case Nil{}:
      ""
    case Def{text, rows} <> rest:
      row_text(rows, at) ++ maps(rest, Nat.add(at, 1n+nl(text)))

# What the defs need that Base lacks: the Step type and each used contract's `src`.
def prelude(cs: List<&2, Contract>, +text: String) -> String:
  match cs:
    case Nil{}:
      S.choose(String, String.contains(text, "Stop{"), u => "type Step<-A: Data> is Data:\n  Continue{acc: A}\n  Stop{acc: A}\n\n", u => "")
    case Contract{r, method, as, ret, bend, pure, total, pre, src} <> rest:
      S.choose(String, String.contains(text, bend ++ "("), u => src, u => "") ++ prelude(rest, text)

# One def: its helpers, then the def itself, body at col 2.
def one_def(f: Fn) -> List<&2, Def>:
  Fn{+name, +ps, ret, post, eff, +body, loc} = f
  List.append(&2, Def, defs(body, name, ps, False{}),
    [atop("def " ++ name ++ "(" ++ sig(ps, body, "") ++ ") -> " ++ ty(ret) ++ ":\n", param_rows(ps, body, Nat.add(5n, String.length(name))),
      blk(body, name, ps, 1n, 2n, "", "", False{}))])

def all_defs(fs: List<&2, Fn>) -> List<&2, Def>:
  match fs:
    case Nil{}:
      []
    case f <> t:
      List.append(&2, Def, one_def(f), all_defs(t))

def titles(fs: List<&2, Fn>, lead: String) -> String:
  match fs:
    case Nil{}:
      ""
    case Fn{name, ps, ret, post, eff, body, loc} <> t:
      lead ++ "`" ++ name ++ "` " ++ Lint.span(loc) ++ titles(t, ", ")

# Line 1 a comment, line 2 the import, line 4 the first def: prelude, then the
# defs in the kernel's rank order, then the span map. Callees first is not a
# preference: a Bend def may not name a def written below it, so the rank is
# what makes the emitted file resolve at all, whatever order the Python had.
def render_all(+fs: List<&2, Fn>, cs: List<&2, Contract>) -> String:
  +ds = all_defs(fs)
  +pre = prelude(cs, code(ds))
  "# Faithful translation (tiers 1-2) of Python " ++ titles(fs, "") ++ " by demos/python/translate.bend.\n" ++
    "import Base\n\n" ++ pre ++ code(ds) ++ "# spans: emitted Bend <- Python source, node : type\n" ++ maps(ds, Nat.add(4n, nl(pre)))

def render(f: Fn, cs: List<&2, Contract>) -> String:
  render_all([f], cs)

def emit(f: Fn, +cs: List<&2, Contract>) -> Result<&2, &2, S.Error, String>:
  do Result<&2, &2, S.Error, String>:
    ok : Fn <- verify(f, cs)
    Done{render(ok, cs)}

def emit_all(fs: List<&2, Fn>, +cs: List<&2, Contract>) -> Result<&2, &2, S.Error, String>:
  do Result<&2, &2, S.Error, String>:
    ok : List<&2, Fn> <- ordered(fs, cs)
    Done{render_all(ok, cs)}

# The signature says `import re`: one name, no alias.
def imports_re(xs: S.Json) -> Bool:
  match xs:
    case S.JItem{+h, t}:
      +ns = Lint.items(Lint.field(h, "names"))
      +a = Lint.first(ns)
      (String.eq(Lint.tag_of(h), "Import") && Nat.is_eq(Lint.size(ns), 1n) && String.eq(N.string(Lint.field(a, "name")), "re") &&
        Lint.is_null(Lint.field(a, "asname"))) || imports_re(t)
    case _:
      False{}

# `re.` contracts are `re`'s functions: offered only where `re` is that module.
def scoped(cs: List<&2, Contract>, +re: Bool) -> List<&2, Contract>:
  match cs:
    case Nil{}:
      []
    case Contract{r, +method, as, ret, bend, pure, total, pre, src} <> rest:
      +more = scoped(rest, re)
      S.choose(List<&2, Contract>, re || Bool.not(String.starts_with(method, "re.")), u =>
        Contract{r, method, as, ret, bend, pure, total, pre, src} <> more, u => more)

# An empty `name` is the whole module, every top-level def with the calls
# between them (T4); otherwise the one def named, as T1-T3.
def whole(+m: S.Module, +g: S.Module, +on: List<&2, Contract>, +name: String) -> Result<&2, &2, S.Error, String>:
  S.choose(Result<&2, &2, S.Error, String>, String.is_empty(name), u =>
    do Result<&2, &2, S.Error, String>:
      fs : List<&2, Fn> <- elaborate_all(m, g, on)
      emit_all(fs, on), u =>
    do Result<&2, &2, S.Error, String>:
      f : Fn <- elaborate(m, g, on, name)
      emit(f, on))

# `sig` is Python source holding an annotated stub of `name` (and `import re`
# if `re` is the module), or "" when the def carries its own annotations.
def translate_as(source: String, sig: String, cs: List<&2, Contract>, +name: String) -> Result<&2, &2, S.Error, String>:
  do Result<&2, &2, S.Error, String>:
    ts : List<&2, S.Tok> <- L.lex(source)
    m : S.Module <- P.parse(ts)
    ss : List<&2, S.Tok> <- L.lex(sig)
    +g : S.Module <- P.parse(ss)
    +on : List<&2, Contract> <- Done{scoped(cs, imports_re(Lint.items(Lint.field(S.module(g), "body"))))}
    whole(m, g, on, name)

def translate(source: String, +cs: List<&2, Contract>, name: String) -> Result<&2, &2, S.Error, String>:
  translate_as(source, "", cs, name)

# The signature file's text; "" when PY_SIG is unset.
def stub(r: Result<&1, &1, U32 & String, String>) -> IO(String):
  match r:
    case Done{path}:
      I.load(path)
    case Fail{e}:
      IO.pure(String, "")

# PY_SOURCE names a UTF-8 file, PY_DEF the def to translate, PY_SIG (optional)
# a file holding its annotated stub.
def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, IO.get_env("PY_SOURCE"))
    name : String <- IO.try(String, IO.get_env("PY_DEF"))
    source : String <- I.load(path)
    got : Result<&1, &1, U32 & String, String> <- IO.get_env("PY_SIG")
    types : String <- stub(got)
    bend : String <- I.unwrap(&2, String, translate_as(source, types, contracts(), name))
    IO.print(bend)
