# The optimizer, rule #1: tier 3 of docs/omen/plans/translator-modes.md, an
# IR -> IR rewrite over translate.bend's TypedIR. The faithful IR must pass the
# kernel (Tr.verify) before a rule looks at it, and the rewritten IR must pass
# it again; a refused rewrite is an error, never a silent fallback. A rule is a
# pattern, a side-condition, an evidence kind and a SOUNDNESS row
# (docs/omen/lanes/optimize-v1.md). Where the pattern matches and the
# side-condition fails, the step is not applied and the log says Unknown with
# its span. The log ends the file as comments, one line per site; an empty log
# leaves the faithful file byte for byte.
import Base
import ./syntax.bend as S
import ./intake.bend as I
import ./lexer.bend as L
import ./parser.bend as P
import ./lint.bend as Lint
import ./translate.bend as Tr

# ---- evidence: the law hoist_append rests on (kind 1, checked by the checker) ----

# `c`, then `t` after its first |s| chars starts with `p`; the helper the
# rewrite renders, as a def the law can name.
def hoisted(c: Bool, t: String, s: String, p: String) -> Bool:
  match c:
    case True{}:
      String.starts_with(String.drop(t, String.length(s)), p)
    case False{}:
      False{}

law length_go:
  for s: String
  for n: Nat
  {1n+String.length.go(s, n) == String.length.go(s, 1n+n) : Nat}

def length_go(s, n):
  match s:
    case SNil{}:
      {==}
    case SCon{h, t}:
      length_go(t, 1n+n)

law hoisted_cons:
  for c: Bool
  for x: Char
  for xt: String
  for y: Char
  for ys: String
  for p: String
  {hoisted(c, xt, ys, p) == hoisted(c, SCon{x, xt}, SCon{y, ys}, p) : Bool}

def hoisted_cons(c, x, xt, y, ys, p):
  match c:
    case True{}:
      %length_go(ys, 0n) : {String.starts_with(String.drop(xt, String.length(ys)), p) == String.starts_with(String.drop(SCon{x, xt}, _), p) : Bool}
      {==}
    case False{}:
      {==}

# The rule's law, over all strings: t starts with s ++ p iff it starts with s
# and, after it, with p.
law starts_append:
  for t: String
  for s: String
  for +p: String
  {String.starts_with(t, String.append(s, p)) == hoisted(String.starts_with(t, s), t, s, p) : Bool}

# One step of the induction, the hypothesis passed in (no mutual recursion).
law starts_step:
  for b: Bool
  for x: Char
  for +xt: String
  for y: Char
  for +ys: String
  for +p: String
  for ih: {String.starts_with(xt, String.append(ys, p)) == hoisted(String.starts_with(xt, ys), xt, ys, p) : Bool}
  {String.starts_with.if(xt, String.append(ys, p), b) == hoisted(String.starts_with.if(xt, ys, b), SCon{x, xt}, SCon{y, ys}, p) : Bool}

def starts_step(b, x, xt, y, ys, p, ih):
  match b:
    case True{}:
      %hoisted_cons(String.starts_with(xt, ys), x, xt, y, ys, p) : {String.starts_with(xt, String.append(ys, p)) == _ : Bool}
      ih
    case False{}:
      {==}

def starts_append(t, s, p):
  match t s:
    case SNil{} SNil{}:
      {==}
    case SCon{x, xt} SNil{}:
      {==}
    case SNil{} SCon{y, ys}:
      {==}
    case SCon{+x, +xt} SCon{+y, +ys}:
      starts_step(Char.is_eq(x, y), x, xt, y, ys, p, starts_append(xt, ys, p))

# ---- rule hoist_append: starts_with(x, y ++ z) -> starts_with(x, y) and z after it ----

def bend_of(e: Tr.Ir) -> String:
  match e:
    case Tr.IPrim{bend, args, t, loc}:
      bend
    case _:
      ""

def args_of(e: Tr.Ir) -> Tr.Ir:
  match e:
    case Tr.IPrim{bend, args, t, loc}:
      args
    case _:
      Tr.IEnd{}

def is_var(e: Tr.Ir) -> Bool:
  match e:
    case Tr.IVar{name, t, loc}:
      True{}
    case _:
      False{}

# The pattern: a starts_with whose prefix is an append.
def matches(+bend: String, +args: Tr.Ir) -> Bool:
  String.eq(bend, "String.starts_with") && String.eq(bend_of(Tr.hd(Tr.tl(args))), "String.append")

# The side-condition: x and y are names. The rewrite reads each twice, which is
# a `+` share of a name but would evaluate any other expression twice.
def fires(+bend: String, +args: Tr.Ir) -> Bool:
  matches(bend, args) && is_var(Tr.hd(args)) && is_var(Tr.hd(args_of(Tr.hd(Tr.tl(args)))))

# An `and` branch, so z is tested only when y matched. `args` come rewritten
# (x and y are names, so only z can change). The calls keep the call's span;
# the new nodes take the append's, and so does the branch, which names its
# helper: at the call's own position a BoolOp or IfExp may already have one.
def hoist(+args: Tr.Ir, +loc: S.Json) -> Tr.Ir:
  +x = Tr.hd(args)
  +a = Tr.hd(Tr.tl(args))
  +y = Tr.hd(args_of(a))
  +at = Tr.own_loc(a)
  +rest = {Tr.IPrim{"String.drop", Tr.IArg{x, Tr.IArg{Tr.IPrim{"String.length", Tr.IArg{y, Tr.IEnd{}}, Tr.TInt{}, at}, Tr.IEnd{}}}, Tr.TStr{}, at} : Tr.Ir}
  Tr.IBranch{Tr.IPrim{"String.starts_with", Tr.IArg{x, Tr.IArg{y, Tr.IEnd{}}}, Tr.TBool{}, loc},
    Tr.IPrim{"String.starts_with", Tr.IArg{rest, Tr.IArg{Tr.hd(Tr.tl(args_of(a))), Tr.IEnd{}}}, Tr.TBool{}, loc},
    Tr.ILit{"False", Tr.TBool{}, at}, Tr.TBool{}, at}

# The rewrite: every node as it was, but where the rule fires.
def opt(e: Tr.Ir) -> Tr.Ir:
  match e:
    case Tr.IVar{name, t, loc}:
      Tr.IVar{name, t, loc}
    case Tr.ILit{text, t, loc}:
      Tr.ILit{text, t, loc}
    case Tr.IPrim{+bend, +args, t, +loc}:
      S.choose(Tr.Ir, fires(bend, args), u => hoist(opt(args), loc), u => Tr.IPrim{bend, opt(args), t, loc})
    case Tr.ICall{name, args, t, loc}:
      Tr.ICall{name, opt(args), t, loc}
    case Tr.ILet{name, val, body, loc}:
      Tr.ILet{name, opt(val), opt(body), loc}
    case Tr.IBranch{test, yes, no, t, loc}:
      Tr.IBranch{opt(test), opt(yes), opt(no), t, loc}
    case Tr.IFold{item, over, acc, init, step, t, loc}:
      Tr.IFold{item, opt(over), acc, opt(init), opt(step), t, loc}
    case Tr.IReturn{val, loc}:
      Tr.IReturn{opt(val), loc}
    case Tr.IArg{h, t}:
      Tr.IArg{opt(h), opt(t)}
    case Tr.IEnd{}:
      Tr.IEnd{}
    case Tr.ISome{val, t, loc}:
      Tr.ISome{opt(val), t, loc}
    case Tr.IMaybe{on, none, some, t, loc}:
      Tr.IMaybe{on, opt(none), opt(some), t, loc}
    case Tr.IStop{val, loc}:
      Tr.IStop{opt(val), loc}
    case Tr.IList{items, t, loc}:
      Tr.IList{opt(items), t, loc}
    case Tr.IMap{item, over, body, t, loc}:
      Tr.IMap{item, opt(over), opt(body), t, loc}

# The log: a line per site the pattern matches, in the order `opt` visits them.
def steps(e: Tr.Ir) -> String:
  match e:
    case Tr.IPrim{+bend, +args, t, +loc}:
      S.choose(String, fires(bend, args), u =>
        "# hoist_append " ++ Lint.span(loc) ++ " Proven: law starts_append, demos/python/optimize.bend\n", u =>
        S.choose(String, matches(bend, args), u =>
          "# hoist_append " ++ Lint.span(loc) ++ " Unknown: not applied, the string or its prefix is not a name (it would be evaluated twice)\n", u => "")) ++ steps(args)
    case Tr.ICall{name, args, t, loc}:
      steps(args)
    case Tr.ILet{name, val, body, loc}:
      steps(val) ++ steps(body)
    case Tr.IBranch{test, yes, no, t, loc}:
      steps(test) ++ steps(yes) ++ steps(no)
    case Tr.IFold{item, over, acc, init, step, t, loc}:
      steps(over) ++ steps(init) ++ steps(step)
    case Tr.IReturn{val, loc}:
      steps(val)
    case Tr.IArg{h, t}:
      steps(h) ++ steps(t)
    case Tr.ISome{val, t, loc}:
      steps(val)
    case Tr.IMaybe{on, none, some, t, loc}:
      steps(none) ++ steps(some)
    case Tr.IStop{val, loc}:
      steps(val)
    case Tr.IList{items, t, loc}:
      steps(items)
    case Tr.IMap{item, over, body, t, loc}:
      steps(over) ++ steps(body)
    case _:
      ""

# ---- emit ----

# The rewritten body is a different body, so its postconditions are recomputed
# rather than carried: a rule that reshapes a literal must not smuggle a claim.
def rewrite(f: Tr.Fn) -> Tr.Fn:
  Tr.Fn{name, ps, +ret, post, eff, body, loc} = f
  +b = opt(body)
  Tr.Fn{name, ps, ret, Tr.sure(b, ret), eff, b, loc}

def rewrite_all(fs: List<&2, Tr.Fn>) -> List<&2, Tr.Fn>:
  match fs:
    case Nil{}:
      []
    case f <> t:
      rewrite(f) <> rewrite_all(t)

def log_of(f: Tr.Fn) -> String:
  Tr.Fn{name, ps, ret, post, eff, body, loc} = f
  steps(body)

# One log for the module, the defs in the kernel's rank order. A line names its
# site by the Python span, so the def it came from is not in doubt.
def logs_of(fs: List<&2, Tr.Fn>) -> String:
  match fs:
    case Nil{}:
      ""
    case f <> t:
      log_of(f) ++ logs_of(t)

# Line 1 names this file -- one line for one def or for the whole module, as
# translate.bend's own line 1 is -- so the span map's lines stand.
def framed(+fs: List<&2, Tr.Fn>, cs: List<&2, Tr.Contract>, +log: String) -> String:
  +text = Tr.render_all(fs, cs)
  S.choose(String, String.is_empty(log), u => text, u =>
    "# Optimized translation (tier 3) of Python " ++ Tr.titles(fs, "") ++ " by demos/python/optimize.bend; the rewrite log ends the file.\n" ++
      Pair.snd(String, String, Pair.snd(String, String & String, String.partition(text, "\n"))) ++ "# rewrites: rule, Python span, grade: evidence\n" ++ log)

# The module door. The rank is the kernel's and is recomputed on the rewritten
# defs rather than carried, exactly as the body's own verify is: a rewrite that
# dropped a postcondition a caller reads would be refused here, at that caller.
def optimize_all(fs: List<&2, Tr.Fn>, +cs: List<&2, Tr.Contract>) -> Result<&2, &2, S.Error, String>:
  do Result<&2, &2, S.Error, String>:
    +ok : List<&2, Tr.Fn> <- Tr.ordered(fs, cs)
    better : List<&2, Tr.Fn> <- Tr.ordered(rewrite_all(ok), cs)
    Done{framed(better, cs, logs_of(ok))}

# One def is the module of one: `Tr.ordered` on a singleton is `Tr.verify`, and
# `fresh` against no signatures cannot fail.
def optimize(f: Tr.Fn, +cs: List<&2, Tr.Contract>) -> Result<&2, &2, S.Error, String>:
  optimize_all([f], cs)

# An empty `name` is the whole module, as translate.bend's `whole` is.
def whole(+m: S.Module, +g: S.Module, +on: List<&2, Tr.Contract>, +name: String) -> Result<&2, &2, S.Error, String>:
  S.choose(Result<&2, &2, S.Error, String>, String.is_empty(name), u =>
    do Result<&2, &2, S.Error, String>:
      fs : List<&2, Tr.Fn> <- Tr.elaborate_all(m, g, on)
      optimize_all(fs, on), u =>
    do Result<&2, &2, S.Error, String>:
      f : Tr.Fn <- Tr.elaborate(m, g, on, name)
      optimize(f, on))

# translate.bend's pipeline, `optimize` in place of `emit`.
def optimize_as(source: String, sig: String, cs: List<&2, Tr.Contract>, +name: String) -> Result<&2, &2, S.Error, String>:
  do Result<&2, &2, S.Error, String>:
    ts : List<&2, S.Tok> <- L.lex(source)
    m : S.Module <- P.parse(ts)
    ss : List<&2, S.Tok> <- L.lex(sig)
    +g : S.Module <- P.parse(ss)
    +on : List<&2, Tr.Contract> <- Done{Tr.scoped(cs, Tr.imports_re(Lint.items(Lint.field(S.module(g), "body"))))}
    whole(m, g, on, name)

# PY_SOURCE, PY_DEF and PY_SIG as translate.bend's main.
def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, IO.get_env("PY_SOURCE"))
    name : String <- IO.try(String, IO.get_env("PY_DEF"))
    source : String <- I.load(path)
    got : Result<&1, &1, U32 & String, String> <- IO.get_env("PY_SIG")
    types : String <- Tr.stub(got)
    bend : String <- I.unwrap(&2, String, optimize_as(source, types, Tr.contracts(), name))
    IO.print(bend)
