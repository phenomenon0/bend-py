# Proofs-as-lint over the parser's wire AST (S.Json). L1: the totality fragment
# T0 and local reachability. `certificate` is the trusted kernel: it recomputes
# every condition from the actual AST and contracts; a witness only supplies
# call ranks. `analyze` is untrusted search in front of it. See SOUNDNESS.md.
# L2: the ownership fragment O0 (`own`, the same kernel) and the alias/effect
# advisories (`alias`). L3: finite-domain match coverage M0 (`exhaustive`,
# `dead_case`, the same recompute-don't-trust discipline; `coverage` searches).
# L4: closed-module summaries U0 (`imports`, `pure`: the same kernel over a
# summary set of modules; `modules` searches).
import Base
import ./syntax.bend as S
import ./nodes.bend as N

type Grade is Data:
  Proven{}
  Refuted{}
  Unknown{}
  Advisory{}

type Diag is Data:
  Diag{loc: S.Json, rule: String, grade: Grade, msg: String}

# A primitive's contract is an assumption about CPython (SOUNDNESS.md, A3);
# a call is granted it only at this arity and only if pure and total.
type Contract is Data:
  Contract{name: String, arity: Nat, pure: Bool, total: Bool}

# One witness entry: every resolved callee must hold a strictly smaller rank.
type Rank is Data:
  Rank{name: String, rank: Nat}

type Fact is Data:
  Bad{loc: S.Json, why: String}
  Calls{name: String}

type Env is Data:
  Env{locals: List<&2, String>, defs: List<&2, String>, contracts: List<&2, Contract>}

def contracts() -> List<&2, Contract>:
  [Contract{"len", 1n, True{}, True{}}, Contract{"str", 1n, True{}, True{}},
   Contract{"bool", 1n, True{}, True{}}, Contract{"sorted", 1n, True{}, True{}}]

# ---- helpers ----

def count(xs: List<&2, String>, +k: String) -> Nat:
  match xs:
    case Nil{}:
      0n
    case h <> t:
      Nat.add(Bool.pick(Nat, String.eq(h, k), 1n, 0n), count(t, k))

def has(xs: List<&2, String>, +k: String) -> Bool:
  Nat.is_gt(count(xs, k), 0n)

def field(j: S.Json, key: String) -> S.Json:
  match j:
    case S.JObj{fs}:
      N.get(fs, key)
    case _:
      S.JNull{}

def tag_of(j: S.Json) -> String:
  N.string(field(j, "tag"))

def is_null(j: S.Json) -> Bool:
  match j:
    case S.JNull{}:
      True{}
    case _:
      False{}

def is_empty(j: S.Json) -> Bool:
  match j:
    case S.JArr{S.JEnd{}}:
      True{}
    case _:
      False{}

def items(j: S.Json) -> S.Json:
  match j:
    case S.JArr{xs}:
      xs
    case _:
      S.JEnd{}

def size(xs: S.Json) -> Nat:
  match xs:
    case S.JItem{h, t}:
      1n+size(t)
    case _:
      0n

def line(loc: S.Json) -> Nat:
  match loc:
    case S.JArr{S.JItem{S.JNum{l}, rest}}:
      l
    case _:
      0n

def col(loc: S.Json) -> Nat:
  match loc:
    case S.JArr{S.JItem{l, S.JItem{S.JNum{c}, rest}}}:
      c
    case _:
      0n

def at(+loc: S.Json) -> String:
  " at " ++ Nat.show(line(loc)) ++ ":" ++ Nat.show(col(loc))

def contract(cs: List<&2, Contract>, +k: String) -> Maybe<&2, Contract>:
  match cs:
    case Nil{}:
      None{}
    case Contract{+name, arity, pure, total} <> t:
      S.choose(Maybe<&2, Contract>, String.eq(name, k), u => Some{Contract{name, arity, pure, total}}, u => contract(t, k))

def rank(w: List<&2, Rank>, +k: String) -> Maybe<&2, Nat>:
  match w:
    case Nil{}:
      None{}
    case Rank{name, r} <> t:
      S.choose(Maybe<&2, Nat>, String.eq(name, k), u => Some{r}, u => rank(t, k))

# ---- resolve: bindings and call targets ----

# Every name a function binds: parameters and Store targets.
def binds(j: S.Json) -> List<&2, String>:
  match j:
    case S.JObj{+fs}:
      +tag = N.string(N.get(fs, "tag"))
      own = S.choose(List<&2, String>, String.eq(tag, "arg"), u => [N.string(N.get(fs, "arg"))], u =>
        S.choose(List<&2, String>, String.eq(tag, "Name") && String.eq(tag_of(N.get(fs, "ctx")), "Store"), u =>
          [N.string(N.get(fs, "id"))], u => []))
      List.append(&2, String, own, binds(fs))
    case S.JField{key, value, rest}:
      List.append(&2, String, binds(value), binds(rest))
    case S.JArr{xs}:
      binds(xs)
    case S.JItem{h, t}:
      List.append(&2, String, binds(h), binds(t))
    case _:
      []

def granted(c: Maybe<&2, Contract>, +id: String, +n: Nat, +loc: S.Json) -> List<&2, Fact>:
  match c:
    case None{}:
      [Bad{loc, "unresolved call " ++ id ++ at(loc)}]
    case Some{Contract{name, arity, pure, total}}:
      S.choose(List<&2, Fact>, pure && total && Nat.is_eq(arity, n), u => [], u =>
        [Bad{loc, "contract of " ++ id ++ " does not grant this call" ++ at(loc)}])

# The callee of Call{func, args, ..}: spelling is not authority. A local or a
# module def of a contracted name revokes the contract; only a unique module
# def or an unshadowed contracted primitive resolves.
def callee(+func: S.Json, +args: S.Json, +env: Env) -> List<&2, Fact>:
  Env{locals, defs, +cs} = env
  +loc = field(func, "_loc")
  +id = N.string(field(func, "id"))
  +n = count(defs, id)
  S.choose(List<&2, Fact>, Bool.not(String.eq(tag_of(func), "Name")), u =>
    [Bad{loc, "dynamic call" ++ at(loc)}], u =>
    S.choose(List<&2, Fact>, (has(locals, id) || Nat.is_gt(n, 0n)) && Maybe.is_some(&2, Contract, contract(cs, id)), u =>
      [Bad{loc, "shadowed builtin " ++ id ++ at(loc)}], u =>
      S.choose(List<&2, Fact>, has(locals, id), u =>
        [Bad{loc, "call through local " ++ id ++ at(loc)}], u =>
        S.choose(List<&2, Fact>, Nat.is_eq(n, 1n), u => [Calls{id}], u =>
          S.choose(List<&2, Fact>, Nat.is_gt(n, 1n), u =>
            [Bad{loc, "ambiguous def " ++ id ++ at(loc)}], u =>
            granted(contract(cs, id), id, size(items(args)), loc))))))

# ---- effects and termination: fragment membership ----

# Pure, non-mutating forms plus For (a structural fold: nothing in the fragment
# mutates, so the iterated str/list is finite and fixed; Break/Continue only
# shorten it).
def admitted(+t: String) -> Bool:
  has(["Return", "Assign", "If", "For", "Break", "Continue", "Pass", "Expr", "Name", "Constant", "BoolOp", "UnaryOp",
    "BinOp", "Compare", "IfExp", "List", "Call", "Load", "Store", "And", "Or", "Not", "Add",
    "Eq", "NotEq", "Lt", "LtE", "Gt", "GtE", "Is", "IsNot", "In", "NotIn"], t)

def judge(+tag: String, +fs: S.Json, +loc: S.Json, +env: Env) -> List<&2, Fact>:
  Env{locals, defs, cs} = env
  +id = N.string(N.get(fs, "id"))
  S.choose(List<&2, Fact>, String.eq(tag, "While"), u =>
    [Bad{loc, "unbounded loop While" ++ at(loc)}], u =>
    S.choose(List<&2, Fact>, Bool.not(admitted(tag)), u =>
      [Bad{loc, "outside fragment: " ++ tag ++ at(loc)}], u =>
      S.choose(List<&2, Fact>, String.eq(tag, "Name") && String.eq(tag_of(N.get(fs, "ctx")), "Load") && Bool.not(has(locals, id)), u =>
        [Bad{loc, "unresolved name " ++ id ++ at(loc)}], u => [])))

# `near` is the closest enclosing span: operator nodes carry none.
def scan(j: S.Json, +parent: String, +near: S.Json, +env: Env) -> List<&2, Fact>:
  match j:
    case S.JObj{+fs}:
      +tag = N.string(N.get(fs, "tag"))
      +own = N.get(fs, "_loc")
      +loc = S.choose(S.Json, is_null(own), u => near, u => own)
      List.append(&2, Fact, judge(tag, fs, loc, env), scan(fs, tag, loc, env))
    case S.JField{+key, +value, +rest}:
      S.choose(List<&2, Fact>, String.eq(parent, "Call") && String.eq(key, "func"), u =>
        List.append(&2, Fact, callee(value, N.get(rest, "args"), env), scan(rest, parent, near, env)), u =>
        List.append(&2, Fact, scan(value, "", near, env), scan(rest, parent, near, env)))
    case S.JArr{xs}:
      scan(xs, "", near, env)
    case S.JItem{h, t}:
      List.append(&2, Fact, scan(h, "", near, env), scan(t, "", near, env))
    case _:
      []

# Annotations state assumption A1: str, bool, int, list[T], T | None.
def ann_ok(j: S.Json, +names: List<&2, String>, +tags: List<&2, String>) -> Bool:
  match j:
    case S.JObj{+fs}:
      +tag = N.string(N.get(fs, "tag"))
      S.choose(Bool, String.eq(tag, "Name"), u => has(names, N.string(N.get(fs, "id"))), u =>
        S.choose(Bool, String.eq(tag, "Constant"), u => String.eq(N.string(N.get(fs, "_raw")), "None"), u =>
          has(tags, tag) && ann_ok(fs, names, tags)))
    case S.JField{key, value, rest}:
      ann_ok(value, names, tags) && ann_ok(rest, names, tags)
    case _:
      True{}

def typed(+j: S.Json) -> Bool:
  Bool.not(is_null(j)) && ann_ok(j, ["str", "bool", "int", "list"], ["Subscript", "BinOp", "BitOr", "Load"])

def all_typed(xs: S.Json) -> Bool:
  match xs:
    case S.JItem{h, t}:
      typed(field(h, "annotation")) && all_typed(t)
    case _:
      True{}

def header(+f: S.Json) -> List<&2, Fact>:
  +a = field(f, "args")
  +loc = field(f, "_loc")
  plain = is_empty(field(f, "decorator_list")) && is_empty(field(a, "posonlyargs")) && is_empty(field(a, "kwonlyargs")) &&
    is_empty(field(a, "defaults")) && is_null(field(a, "vararg")) && is_null(field(a, "kwarg"))
  S.choose(List<&2, Fact>, Bool.not(plain), u => [Bad{loc, "decorated or non-simple parameters"}], u =>
    S.choose(List<&2, Fact>, all_typed(items(field(a, "args"))) && typed(field(f, "returns")), u => [], u =>
      [Bad{loc, "missing or non-builtin annotation"}]))

# A closed module: defs and a docstring only, so module globals after import
# are exactly the def names (A2).
def closed(xs: S.Json) -> List<&2, Fact>:
  match xs:
    case S.JItem{+h, t}:
      +tag = tag_of(h)
      ok = String.eq(tag, "FunctionDef") || (String.eq(tag, "Expr") && String.eq(tag_of(field(h, "value")), "Constant"))
      List.append(&2, Fact, S.choose(List<&2, Fact>, ok, u => [], u =>
        [Bad{field(h, "_loc"), "module not closed: " ++ tag ++ at(field(h, "_loc"))}]), closed(t))
    case _:
      []

def def_names(xs: S.Json) -> List<&2, String>:
  match xs:
    case S.JItem{+h, t}:
      List.append(&2, String, S.choose(List<&2, String>, String.eq(tag_of(h), "FunctionDef"), u =>
        [N.string(field(h, "name"))], u => []), def_names(t))
    case _:
      []

def find_def(xs: S.Json, +name: String) -> S.Json:
  match xs:
    case S.JItem{+h, t}:
      S.choose(S.Json, String.eq(tag_of(h), "FunctionDef") && String.eq(N.string(field(h, "name")), name), u => h, u =>
        find_def(t, name))
    case _:
      S.JNull{}

def consts(xs: S.Json) -> Bool:
  match xs:
    case S.JItem{+h, t}:
      String.eq(tag_of(h), "Constant") && has(["None", "True", "False"], N.string(field(h, "_raw"))) && consts(t)
    case _:
      True{}

def any_tag(xs: S.Json, +tags: List<&2, String>) -> Bool:
  match xs:
    case S.JItem{h, t}:
      has(tags, tag_of(h)) || any_tag(t, tags)
    case _:
      False{}

# O0's extra condition: `is` observes sharing, except against None/True/False.
def ident(j: S.Json) -> List<&2, Fact>:
  match j:
    case S.JObj{+fs}:
      +loc = N.get(fs, "_loc")
      bad = String.eq(N.string(N.get(fs, "tag")), "Compare") && any_tag(items(N.get(fs, "ops")), ["Is", "IsNot"]) &&
        Bool.not(consts(items(N.get(fs, "comparators"))))
      List.append(&2, Fact, S.choose(List<&2, Fact>, bad, u => [Bad{loc, "identity comparison observes sharing" ++ at(loc)}], u => []), ident(fs))
    case S.JField{key, value, rest}:
      List.append(&2, Fact, ident(value), ident(rest))
    case S.JArr{xs}:
      ident(xs)
    case S.JItem{h, t}:
      List.append(&2, Fact, ident(h), ident(t))
    case _:
      []

# The def's own conditions; `defs` are the module-level names (L4 adds imports).
def member(+body: S.Json, +cs: List<&2, Contract>, +name: String, o: Bool, +defs: List<&2, String>) -> List<&2, Fact>:
  +f = find_def(body, name)
  unique = S.choose(List<&2, Fact>, Nat.is_eq(count(defs, name), 1n), u => [], u =>
    [Bad{field(f, "_loc"), "no unique def " ++ name}])
  List.append(&2, Fact, unique, List.append(&2, Fact, header(f),
    List.append(&2, Fact, scan(field(f, "body"), "", field(f, "_loc"), Env{binds(f), defs, cs}),
      S.choose(List<&2, Fact>, o, u => ident(f), u => []))))

# Every condition of "name is in T0" (`o`: in O0), recomputed from the AST.
def check_fn(+body: S.Json, +cs: List<&2, Contract>, +name: String, o: Bool) -> List<&2, Fact>:
  List.append(&2, Fact, closed(body), member(body, cs, name, o, def_names(body)))

# ---- verify: the kernel ----

# "" when every fact is discharged: no Bad, every callee ranked below `r`.
def discharge(fs: List<&2, Fact>, +w: List<&2, Rank>, +r: Nat) -> String:
  match fs:
    case Nil{}:
      ""
    case Bad{loc, why} <> t:
      why
    case Calls{+g} <> t:
      S.choose(String, Nat.is_lt(Maybe.default(&2, Nat, rank(w, g), r), r), u => discharge(t, w, r), u =>
        "callee " ++ g ++ " holds no smaller rank")

def entries(es: List<&2, Rank>, +w: List<&2, Rank>, +body: S.Json, +cs: List<&2, Contract>, +o: Bool) -> String:
  match es:
    case Nil{}:
      ""
    case Rank{+name, +r} <> t:
      +why = discharge(check_fn(body, cs, name, o), w, r)
      S.choose(String, String.is_empty(why), u => entries(t, w, body, cs, o), u => name ++ ": " ++ why)

# "" iff every entry of the witness checks against the actual AST/contracts.
# By induction on rank every entry is then total (SOUNDNESS.md, T0).
def certificate(m: S.Module, +cs: List<&2, Contract>, +w: List<&2, Rank>, +o: Bool) -> String:
  S.Module{body} = m
  entries(w, w, body, cs, o)

def def_loc(m: S.Module, name: String) -> S.Json:
  S.Module{body} = m
  field(find_def(body, name), "_loc")

def rule_of(o: Bool) -> String:
  Bool.pick(String, o, "ownership", "total")

def holds(o: Bool) -> String:
  Bool.pick(String, o, "value semantics is faithful: no mutation, identity test or retained reference (O0)",
    "terminates on exact built-in arguments (T0)")

# The witness entry is consulted first, so no entry means no proof by
# computation alone (the law below).
def verdict(entry: Maybe<&2, Nat>, +m: S.Module, +cs: List<&2, Contract>, +w: List<&2, Rank>, +name: String, +o: Bool) -> Diag:
  match entry:
    case None{}:
      Diag{def_loc(m, name), rule_of(o), Unknown{}, "no certificate"}
    case Some{r}:
      +why = certificate(m, cs, w, o)
      S.choose(Diag, String.is_empty(why), u =>
        Diag{def_loc(m, name), rule_of(o), Proven{}, holds(o)}, u =>
        Diag{def_loc(m, name), rule_of(o), Refuted{}, "certificate refuted: " ++ why})

def verify(+m: S.Module, +cs: List<&2, Contract>, +w: List<&2, Rank>, +name: String) -> Diag:
  verdict(rank(w, name), m, cs, w, name, False{})

# The same kernel over O0 = T0 without identity tests (SOUNDNESS.md, O0).
def own(+m: S.Module, +cs: List<&2, Contract>, +w: List<&2, Rank>, +name: String) -> Diag:
  verdict(rank(w, name), m, cs, w, name, True{})

def is_proven(d: Diag) -> Bool:
  match d:
    case Diag{loc, rule, Proven{}, msg}:
      True{}
    case _:
      False{}

# A certificate is required: with none, nothing is ever Proven.
law no_certificate_no_proof:
  for +m: S.Module
  for +cs: List<&2, Contract>
  for +name: String
  {is_proven(verify(m, cs, Nil{}, name)) == False{} : Bool}

def no_certificate_no_proof(m, cs, name):
  {==}

law no_certificate_no_ownership:
  for +m: S.Module
  for +cs: List<&2, Contract>
  for +name: String
  {is_proven(own(m, cs, Nil{}, name)) == False{} : Bool}

def no_certificate_no_ownership(m, cs, name):
  {==}

# ---- analyze: untrusted witness search, then the kernel ----

def why_not(fs: List<&2, Fact>, +w: List<&2, Rank>) -> String:
  match fs:
    case Nil{}:
      ""
    case Bad{loc, why} <> t:
      why
    case Calls{+g} <> t:
      S.choose(String, Maybe.is_some(&2, Nat, rank(w, g)), u => why_not(t, w), u =>
        "callee " ++ g ++ " is not proven (cycle or Unknown)")

# One round: rank `r` for each unranked def whose callees were ranked earlier.
def round(names: List<&2, String>, +w: List<&2, Rank>, +body: S.Json, +cs: List<&2, Contract>, +o: Bool, +r: Nat) -> List<&2, Rank>:
  match names:
    case Nil{}:
      []
    case +h <> t:
      ok = Maybe.is_none(&2, Nat, rank(w, h)) && String.is_empty(why_not(check_fn(body, cs, h, o), w))
      List.append(&2, Rank, S.choose(List<&2, Rank>, ok, u => [Rank{h, r}], u => []), round(t, w, body, cs, o, r))

def infer(fuel: Nat, +names: List<&2, String>, +w: List<&2, Rank>, +body: S.Json, +cs: List<&2, Contract>, +o: Bool, +r: Nat) -> List<&2, Rank>:
  match fuel:
    case 0n:
      w
    case 1n+p:
      infer(p, names, List.append(&2, Rank, w, round(names, w, body, cs, o, r)), body, cs, o, 1n+r)

def totals(names: List<&2, String>, +w: List<&2, Rank>, +valid: Bool, +body: S.Json, +cs: List<&2, Contract>, +o: Bool) -> List<&2, Diag>:
  match names:
    case Nil{}:
      []
    case +h <> t:
      +loc = field(find_def(body, h), "_loc")
      d = S.choose(Diag, valid && Maybe.is_some(&2, Nat, rank(w, h)), u =>
        Diag{loc, rule_of(o), Proven{}, holds(o)}, u =>
        Diag{loc, rule_of(o), Unknown{}, why_not(check_fn(body, cs, h, o), w)})
      d <> totals(t, w, valid, body, cs, o)

# Advisory: a binding spelled like a contracted primitive.
def shadows(j: S.Json, +cs: List<&2, Contract>) -> List<&2, Diag>:
  match j:
    case S.JObj{+fs}:
      +tag = N.string(N.get(fs, "tag"))
      +id = S.choose(String, String.eq(tag, "arg"), u => N.string(N.get(fs, "arg")), u =>
        S.choose(String, String.eq(tag, "FunctionDef"), u => N.string(N.get(fs, "name")), u =>
          S.choose(String, String.eq(tag, "Name") && String.eq(tag_of(N.get(fs, "ctx")), "Store"), u =>
            N.string(N.get(fs, "id")), u => "")))
      List.append(&2, Diag, S.choose(List<&2, Diag>, Maybe.is_some(&2, Contract, contract(cs, id)), u =>
        [Diag{N.get(fs, "_loc"), "shadowed-builtin", Advisory{}, id ++ " is rebound; calls to it are not granted the builtin's contract"}], u => []),
        shadows(fs, cs))
    case S.JField{key, value, rest}:
      List.append(&2, Diag, shadows(value, cs), shadows(rest, cs))
    case S.JArr{xs}:
      shadows(xs, cs)
    case S.JItem{h, t}:
      List.append(&2, Diag, shadows(h, cs), shadows(t, cs))
    case _:
      []

# Local reachability R0: the statement after an unconditional transfer in the
# same block never runs (finally bodies run, but control does not come back).
def after(+h: S.Json, t: S.Json) -> List<&2, Diag>:
  match t:
    case S.JItem{next, rest}:
      +tag = tag_of(h)
      +loc = field(next, "_loc")
      S.choose(List<&2, Diag>, has(["Return", "Raise", "Break", "Continue"], tag), u =>
        [Diag{loc, "unreachable", Proven{}, "follows " ++ tag ++ " in the same block"}], u =>
        S.choose(List<&2, Diag>, String.eq(tag, "While") && String.eq(N.string(field(field(h, "test"), "_raw")), "True"), u =>
          [Diag{loc, "unreachable", Unknown{}, "follows while True; break analysis is outside R0"}], u => []))
    case _:
      []

def dead(j: S.Json) -> List<&2, Diag>:
  match j:
    case S.JObj{fs}:
      dead(fs)
    case S.JField{key, value, rest}:
      List.append(&2, Diag, dead(value), dead(rest))
    case S.JArr{xs}:
      dead(xs)
    case S.JItem{+h, +t}:
      List.append(&2, Diag, after(h, t), List.append(&2, Diag, dead(h), dead(t)))
    case _:
      []

# ---- deterministic order and rendering ----

def le(a: Diag, b: Diag) -> Bool:
  Diag{+la, ra, ga, ma} = a
  Diag{+lb, rb, gb, mb} = b
  +l1 = line(la)
  +l2 = line(lb)
  +c1 = col(la)
  +c2 = col(lb)
  Nat.is_lt(l1, l2) || (Nat.is_eq(l1, l2) && (Nat.is_lt(c1, c2) || (Nat.is_eq(c1, c2) && String.is_le(ra, rb))))

def grade(g: Grade) -> String:
  match g:
    case Proven{}:
      "Proven"
    case Refuted{}:
      "Refuted"
    case Unknown{}:
      "Unknown"
    case Advisory{}:
      "Advisory"

def span(loc: S.Json) -> String:
  match loc:
    case S.JArr{S.JItem{S.JNum{a}, S.JItem{S.JNum{b}, S.JItem{S.JNum{c}, S.JItem{S.JNum{d}, rest}}}}}:
      Nat.show(a) ++ ":" ++ Nat.show(b) ++ "-" ++ Nat.show(c) ++ ":" ++ Nat.show(d)
    case _:
      "?"

def show(+path: String, d: Diag) -> String:
  Diag{loc, rule, g, msg} = d
  path ++ ":" ++ span(loc) ++ " " ++ rule ++ " " ++ grade(g) ++ " " ++ msg

def render(+path: String, ds: List<&2, Diag>) -> String:
  match ds:
    case Nil{}:
      ""
    case h <> t:
      show(path, h) ++ "\n" ++ render(path, t)

def analyze(+m: S.Module, +cs: List<&2, Contract>) -> List<&2, Diag>:
  S.Module{+body} = m
  +names = def_names(body)
  +w = infer(List.length(&2, String, names), names, [], body, cs, False{}, 0n)
  +valid = String.is_empty(certificate(m, cs, w, False{}))
  List.sort(~Diag, ~le, List.append(&2, Diag, totals(names, w, valid, body, cs, False{}),
    List.append(&2, Diag, shadows(body, cs), dead(body))))

# ---- L2: alias/effect advisories (no certificate, no guarantee) ----

# What one function body says about names. May-alias is flow-insensitive
# (branch joins and rebinding both merge), so repeated use is never an event.
type Ev is Data:
  Edge{x: String, y: String, loc: S.Json}
  Bind{name: String, val: S.Json, imm: Bool}
  Mut{name: String, loc: S.Json, how: String}
  Esc{name: String, loc: S.Json, how: String}
  Use{name: String, loc: S.Json}

def mutators() -> List<&2, String>:
  ["append", "extend", "insert", "pop", "remove", "clear", "sort", "reverse", "update", "add", "discard", "setdefault", "popitem"]

# Names an expression may evaluate to: `a`, `a if c else d`, `a or d`.
def sources(j: S.Json, +parent: String) -> List<&2, String>:
  match j:
    case S.JObj{+fs}:
      +tag = N.string(N.get(fs, "tag"))
      S.choose(List<&2, String>, String.eq(tag, "Name"), u => [N.string(N.get(fs, "id"))], u =>
        S.choose(List<&2, String>, has(["IfExp", "BoolOp"], tag), u => sources(fs, tag), u => []))
    case S.JField{key, value, +rest}:
      S.choose(List<&2, String>, has(["body", "orelse", "values"], key), u =>
        List.append(&2, String, sources(value, ""), sources(rest, parent)), u => sources(rest, parent))
    case S.JArr{xs}:
      sources(xs, "")
    case S.JItem{h, t}:
      List.append(&2, String, sources(h, ""), sources(t, ""))
    case _:
      []

def edges(ys: List<&2, String>, +x: String, +loc: S.Json) -> List<&2, Ev>:
  match ys:
    case Nil{}:
      []
    case y <> t:
      Edge{x, y, loc} <> edges(t, x, loc)

def first(xs: S.Json) -> S.Json:
  match xs:
    case S.JItem{h, t}:
      h
    case _:
      S.JNull{}

# The name bound by `b = v`, `b: T = v` or `b += v`; "" for any other target.
def bound(+tag: String, +fs: S.Json) -> String:
  +ts = items(N.get(fs, "targets"))
  +t = S.choose(S.Json, String.eq(tag, "Assign"), u =>
    S.choose(S.Json, Nat.is_eq(size(ts), 1n), u => first(ts), u => S.JNull{}), u =>
    S.choose(S.Json, has(["AnnAssign", "AugAssign"], tag), u => N.get(fs, "target"), u => S.JNull{}))
  S.choose(String, String.eq(tag_of(t), "Name"), u => N.string(field(t, "id")), u => "")

def quiet(fs: List<&2, Fact>, +safe: List<&2, String>) -> Bool:
  match fs:
    case Nil{}:
      True{}
    case Bad{loc, why} <> t:
      False{}
    case Calls{g} <> t:
      has(safe, g) && quiet(t, safe)

def escapes(xs: S.Json, +how: String) -> List<&2, Ev>:
  match xs:
    case S.JItem{+h, t}:
      List.append(&2, Ev, S.choose(List<&2, Ev>, String.eq(tag_of(h), "Name"), u =>
        [Esc{N.string(field(h, "id")), field(h, "_loc"), how}], u => []), escapes(t, how))
    case _:
      []

# A call mutates its receiver by method spelling (advisory: spelling is not
# authority) and lets its Name arguments escape unless the callee is a granted
# pure primitive or an O0-certified def (`safe`).
def call(+fs: S.Json, +loc: S.Json, +env: Env, +safe: List<&2, String>) -> List<&2, Ev>:
  +func = N.get(fs, "func")
  +recv = field(func, "value")
  +attr = N.string(field(func, "attr"))
  +method = String.eq(tag_of(func), "Attribute")
  how = "passed to " ++ S.choose(String, method, u => "." ++ attr, u =>
    S.choose(String, String.eq(tag_of(func), "Name"), u => N.string(field(func, "id")), u => "a dynamic call"))
  List.append(&2, Ev, S.choose(List<&2, Ev>, method && String.eq(tag_of(recv), "Name") && has(mutators(), attr), u =>
    [Mut{N.string(field(recv, "id")), loc, "." ++ attr}], u => []),
    S.choose(List<&2, Ev>, quiet(callee(func, N.get(fs, "args"), env), safe), u => [], u => escapes(items(N.get(fs, "args")), how)))

def notes(+tag: String, +fs: S.Json, +env: Env, +safe: List<&2, String>) -> List<&2, Ev>:
  +loc = N.get(fs, "_loc")
  +id = N.string(N.get(fs, "id"))
  +ctx = tag_of(N.get(fs, "ctx"))
  +b = bound(tag, fs)
  +held = N.get(fs, "value")
  +note = N.get(fs, "annotation")
  S.choose(List<&2, Ev>, String.eq(tag, "arg"), u =>
    [Bind{N.string(N.get(fs, "arg")), S.JNull{}, Bool.not(is_null(note)) && ann_ok(note, ["str", "bool", "int"], ["BinOp", "BitOr", "Load"])}], u =>
    S.choose(List<&2, Ev>, Bool.not(String.is_empty(b)), u =>
      Bind{b, held, False{}} <> List.append(&2, Ev, edges(sources(held, ""), b, loc),
        S.choose(List<&2, Ev>, String.eq(tag, "AugAssign"), u => [Mut{b, loc, "augmented assignment"}], u => [])), u =>
      S.choose(List<&2, Ev>, String.eq(tag, "Name"), u =>
        S.choose(List<&2, Ev>, String.eq(ctx, "Load"), u => [Use{id, loc}], u => [Bind{id, S.JNull{}, False{}}]), u =>
        S.choose(List<&2, Ev>, has(["Subscript", "Attribute"], tag) && has(["Store", "Del"], ctx) && String.eq(tag_of(held), "Name"), u =>
          [Mut{N.string(field(held, "id")), loc, "item or attribute store"}], u =>
          S.choose(List<&2, Ev>, String.eq(tag, "Call"), u => call(fs, loc, env, safe), u => [])))))

# `skip`: the plain Name target of a binding is already a Bind with its value.
def walk(j: S.Json, +skip: Bool, +env: Env, +safe: List<&2, String>) -> List<&2, Ev>:
  match j:
    case S.JObj{+fs}:
      +tag = N.string(N.get(fs, "tag"))
      List.append(&2, Ev, notes(tag, fs, env, safe), walk(fs, Bool.not(String.is_empty(bound(tag, fs))), env, safe))
    case S.JField{key, value, +rest}:
      S.choose(List<&2, Ev>, skip && has(["targets", "target"], key), u => walk(rest, skip, env, safe), u =>
        List.append(&2, Ev, walk(value, False{}, env, safe), walk(rest, skip, env, safe)))
    case S.JArr{xs}:
      walk(xs, False{}, env, safe)
    case S.JItem{h, t}:
      List.append(&2, Ev, walk(h, False{}, env, safe), walk(t, False{}, env, safe))
    case _:
      []

# Immutable reuse: an expression over constants, operators and immutable names
# is immutable on exact str/bool/int/None (A1).
def imm_expr(j: S.Json, +imm: List<&2, String>) -> Bool:
  match j:
    case S.JObj{+fs}:
      +tag = N.string(N.get(fs, "tag"))
      S.choose(Bool, String.eq(tag, "Name"), u => has(imm, N.string(N.get(fs, "id"))), u =>
        has(["Constant", "BinOp", "BoolOp", "UnaryOp", "Compare", "IfExp", "Load", "And", "Or", "Not", "USub", "UAdd", "Add", "Sub",
          "Mult", "Div", "FloorDiv", "Mod", "Pow", "Eq", "NotEq", "Lt", "LtE", "Gt", "GtE", "Is", "IsNot", "In", "NotIn"], tag) &&
          imm_expr(fs, imm))
    case S.JField{key, value, rest}:
      imm_expr(value, imm) && imm_expr(rest, imm)
    case S.JArr{xs}:
      imm_expr(xs, imm)
    case S.JItem{h, t}:
      imm_expr(h, imm) && imm_expr(t, imm)
    case _:
      True{}

def bound_imm(es: List<&2, Ev>, +n: String, +imm: List<&2, String>) -> Bool:
  match es:
    case Nil{}:
      True{}
    case Bind{name, +val, ok} <> t:
      (Bool.not(String.eq(name, n)) || ok || (Bool.not(is_null(val)) && imm_expr(val, imm))) && bound_imm(t, n, imm)
    case Edge{x, y, loc} <> t:
      bound_imm(t, n, imm)
    case Mut{name, loc, how} <> t:
      bound_imm(t, n, imm)
    case Esc{name, loc, how} <> t:
      bound_imm(t, n, imm)
    case Use{name, loc} <> t:
      bound_imm(t, n, imm)

def keep(ns: List<&2, String>, +es: List<&2, Ev>, +imm: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}:
      []
    case +h <> t:
      List.append(&2, String, S.choose(List<&2, String>, bound_imm(es, h, imm), u => [h], u => []), keep(t, es, imm))

# Greatest fixpoint: start from every bound name, drop what has a mutable binding.
def settle(fuel: Nat, +es: List<&2, Ev>, +imm: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n:
      imm
    case 1n+p:
      settle(p, es, keep(imm, es, imm))

def grow(es: List<&2, Ev>, +seen: List<&2, String>) -> List<&2, String>:
  match es:
    case Nil{}:
      seen
    case Edge{+x, +y, loc} <> t:
      grow(t, S.choose(List<&2, String>, has(seen, x) && Bool.not(has(seen, y)), u => y <> seen, u =>
        S.choose(List<&2, String>, has(seen, y) && Bool.not(has(seen, x)), u => x <> seen, u => seen)))
    case Bind{name, val, ok} <> t:
      grow(t, seen)
    case Mut{name, loc, how} <> t:
      grow(t, seen)
    case Esc{name, loc, how} <> t:
      grow(t, seen)
    case Use{name, loc} <> t:
      grow(t, seen)

def reach(fuel: Nat, +es: List<&2, Ev>, +seen: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n:
      seen
    case 1n+p:
      reach(p, es, grow(es, seen))

def num_at(n: Nat, xs: S.Json) -> Nat:
  match n:
    case 0n:
      line(S.JArr{xs})
    case 1n+p:
      match xs:
        case S.JItem{h, t}:
          num_at(p, t)
        case _:
          0n

# `l` starts at or after the end of `e`.
def past(+l: S.Json, +e: S.Json) -> Bool:
  +el = num_at(2n, items(e))
  Nat.is_gt(line(l), el) || (Nat.is_eq(line(l), el) && Bool.not(Nat.is_lt(col(l), num_at(3n, items(e)))))

# ponytail: textual order only; a read earlier in the same loop body is missed.
# Upgrade path: treat every Use inside an enclosing For/While as later.
def later(es: List<&2, Ev>, +a: String, +loc: S.Json) -> S.Json:
  match es:
    case Nil{}:
      S.JNull{}
    case Use{name, +l} <> t:
      S.choose(S.Json, String.eq(name, a) && past(l, loc), u => l, u => later(t, a, loc))
    case Edge{x, y, l} <> t:
      later(t, a, loc)
    case Bind{name, val, ok} <> t:
      later(t, a, loc)
    case Mut{name, l, how} <> t:
      later(t, a, loc)
    case Esc{name, l, how} <> t:
      later(t, a, loc)

def edge_at(es: List<&2, Ev>, +a: String) -> S.Json:
  match es:
    case Nil{}:
      S.JNull{}
    case Edge{x, y, +l} <> t:
      S.choose(S.Json, String.eq(x, a) || String.eq(y, a), u => l, u => edge_at(t, a))
    case Bind{name, val, ok} <> t:
      edge_at(t, a)
    case Mut{name, l, how} <> t:
      edge_at(t, a)
    case Esc{name, l, how} <> t:
      edge_at(t, a)
    case Use{name, l} <> t:
      edge_at(t, a)

# The first mutable alias of `b` still observable after `loc`: read later, or a
# parameter (the caller holds it).
def hazard(cs: List<&2, String>, +b: String, +loc: S.Json, +rule: String, +what: String, +es: List<&2, Ev>, +params: List<&2, String>, +imm: List<&2, String>) -> List<&2, Diag>:
  match cs:
    case Nil{}:
      []
    case +a <> t:
      +l = later(es, a, loc)
      S.choose(List<&2, Diag>, String.eq(a, b) || has(imm, a) || (is_null(l) && Bool.not(has(params, a))), u =>
        hazard(t, b, loc, rule, what, es, params, imm), u =>
        [Diag{loc, rule, Advisory{}, what ++ "; " ++ a ++ " may alias it (binding" ++ at(edge_at(es, a)) ++ ") and is " ++
          S.choose(String, is_null(l), u => "a parameter", u => "read" ++ at(l))}])

def flags(todo: List<&2, Ev>, +es: List<&2, Ev>, +params: List<&2, String>, +imm: List<&2, String>, +n: Nat) -> List<&2, Diag>:
  match todo:
    case Nil{}:
      []
    case Mut{+name, +loc, +how} <> t:
      List.append(&2, Diag, S.choose(List<&2, Diag>, has(imm, name), u => [], u =>
        List.append(&2, Diag, S.choose(List<&2, Diag>, has(params, name), u =>
          [Diag{loc, "param-mutation", Advisory{}, how ++ " mutates parameter " ++ name ++ ": the caller observes it"}], u => []),
          hazard(reach(n, es, [name]), name, loc, "alias-mutation", how ++ " mutates " ++ name, es, params, imm))),
        flags(t, es, params, imm, n))
    case Esc{+name, +loc, +how} <> t:
      List.append(&2, Diag, S.choose(List<&2, Diag>, has(imm, name), u => [], u =>
        hazard(reach(n, es, [name]), name, loc, "alias-escape", name ++ " is " ++ how ++ ", which may mutate or keep it", es, params, imm)),
        flags(t, es, params, imm, n))
    case Edge{x, y, loc} <> t:
      flags(t, es, params, imm, n)
    case Bind{name, val, ok} <> t:
      flags(t, es, params, imm, n)
    case Use{name, loc} <> t:
      flags(t, es, params, imm, n)

# ponytail: top-level defs only, nested scopes share the def's names, and
# reach is recomputed per event. Upgrade path: scope-aware walk, memoized classes.
def fn_flags(xs: S.Json, +defs: List<&2, String>, +cs: List<&2, Contract>, +safe: List<&2, String>) -> List<&2, Diag>:
  match xs:
    case S.JItem{+h, t}:
      +names = binds(h)
      +es = walk(h, False{}, Env{names, defs, cs}, safe)
      +n = List.length(&2, String, names)
      List.append(&2, Diag, S.choose(List<&2, Diag>, String.eq(tag_of(h), "FunctionDef"), u =>
        flags(es, es, binds(field(h, "args")), settle(n, es, names), n), u => []), fn_flags(t, defs, cs, safe))
    case _:
      []

def ranked(w: List<&2, Rank>) -> List<&2, String>:
  match w:
    case Nil{}:
      []
    case Rank{name, r} <> t:
      name <> ranked(t)

# `ownership` per def through the kernel (O0), then the advisories. Passing a
# name to an O0-certified def is not an escape.
def alias(+m: S.Module, +cs: List<&2, Contract>) -> List<&2, Diag>:
  S.Module{+body} = m
  +names = def_names(body)
  +w = infer(List.length(&2, String, names), names, [], body, cs, True{}, 0n)
  +valid = String.is_empty(certificate(m, cs, w, True{}))
  List.sort(~Diag, ~le, List.append(&2, Diag, totals(names, w, valid, body, cs, True{}),
    fn_flags(body, names, cs, S.choose(List<&2, String>, valid, u => ranked(w), u => []))))

def grade_of(d: Diag) -> String:
  Diag{loc, rule, g, msg} = d
  grade(g)

# ---- L3: finite-domain match coverage (M0) ----

# A coverage witness entry, keyed by the match's "line:col"; cases count from
# 0. It never carries the domain: the kernel recomputes that from the AST.
type Claim is Data:
  Covers{here: String, value: String, arm: Nat}
  Miss{here: String, value: String}
  Dead{here: String, arm: Nat}

# A match with its recomputed domain; `why` is "" iff it is in M0.
type Site is Data:
  Site{loc: S.Json, dom: List<&2, String>, cases: S.Json, why: String}

# How often `x` is bound under `j`: a string under any key that can name a
# binder (arg, name, asname, names, rest, ...), a Name stored or deleted, or a
# star import (it may bind anything).
def binders(j: S.Json, +key: String, +x: String) -> Nat:
  match j:
    case S.JObj{+fs}:
      name = String.eq(N.string(N.get(fs, "tag")), "Name") && String.eq(N.string(N.get(fs, "id")), x) &&
        Bool.not(String.eq(tag_of(N.get(fs, "ctx")), "Load"))
      Nat.add(Bool.pick(Nat, name, 1n, 0n), binders(fs, "", x))
    case S.JField{k, value, rest}:
      Nat.add(binders(value, k, x), binders(rest, key, x))
    case S.JArr{xs}:
      binders(xs, key, x)
    case S.JItem{h, t}:
      Nat.add(binders(h, key, x), binders(t, key, x))
    case S.JStr{+s}:
      Bool.pick(Nat, (String.eq(s, x) && Bool.not(has(["tag", "id", "attr", "_raw", "kind", "type_comment"], key))) ||
        (String.eq(s, "*") && String.eq(key, "name")), 1n, 0n)
    case _:
      0n

# A string body that is its own repr: printable ASCII, no backslash or quote.
def bare(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{h, t}:
      +n = Char.to_u32(h)
      U32.is_ge(n, 32) && U32.is_le(n, 126) && Bool.not(U32.is_eq(n, 92) || U32.is_eq(n, 34) || U32.is_eq(n, 39)) && bare(t)

def digits(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{h, t}:
      +n = Char.to_u32(h)
      U32.is_ge(n, 48) && U32.is_le(n, 57) && digits(t)

# A decimal int literal already in repr form: no sign, underscore or leading 0.
def decimal(+s: String) -> Bool:
  Bool.not(String.is_empty(s)) && digits(s) && (String.eq(s, "0") || Bool.not(String.starts_with(s, "0")))

# Python's repr of a literal M0 admits, else "": True, False, None, a decimal
# int, or a '...'/"..." string with a bare body (its repr is '<body>').
def canon(+s: String) -> String:
  +body = String.drop(String.drop_end(s, 1n), 1n)
  quoted = Nat.is_lt(1n, String.length(s)) && bare(body) &&
    ((String.starts_with(s, "'") && String.ends_with(s, "'")) || (String.starts_with(s, "\"") && String.ends_with(s, "\"")))
  S.choose(String, has(["True", "False", "None"], s) || decimal(s), u => s, u =>
    S.choose(String, quoted, u => "'" ++ body ++ "'", u => ""))

# The value of a literal node: a Constant, or -n on a decimal n (-0 is 0).
def elt(+j: S.Json) -> String:
  +op = field(j, "operand")
  +n = String.trim(N.string(field(op, "_raw")))
  S.choose(String, String.eq(tag_of(j), "Constant"), u => canon(String.trim(N.string(field(j, "_raw")))), u =>
    S.choose(String, String.eq(tag_of(j), "UnaryOp") && String.eq(tag_of(field(j, "op")), "USub") && String.eq(tag_of(op), "Constant") && decimal(n), u =>
      S.choose(String, String.eq(n, "0"), u => "0", u => "-" ++ n), u => ""))

def each(xs: S.Json) -> List<&2, String>:
  match xs:
    case S.JItem{h, t}:
      elt(h) <> each(t)
    case _:
      []

# The finite domain an annotation pins under A1, in annotation order; "" marks
# a part it cannot pin. `bl`/`lit`: bool and Literal are the builtin and
# typing.Literal in this module.
def domain(j: S.Json, +bl: Bool, +lit: Bool) -> List<&2, String>:
  match j:
    case S.JObj{+fs}:
      +tag = N.string(N.get(fs, "tag"))
      +v = N.get(fs, "value")
      +s = N.get(fs, "slice")
      S.choose(List<&2, String>, String.eq(tag, "Name"), u =>
        S.choose(List<&2, String>, bl && String.eq(N.string(N.get(fs, "id")), "bool"), u => ["True", "False"], u => [""]), u =>
        S.choose(List<&2, String>, String.eq(tag, "Constant"), u =>
          [S.choose(String, String.eq(String.trim(N.string(N.get(fs, "_raw"))), "None"), u => "None", u => "")], u =>
          S.choose(List<&2, String>, String.eq(tag, "BinOp") && String.eq(tag_of(N.get(fs, "op")), "BitOr"), u => domain(fs, bl, lit), u =>
            S.choose(List<&2, String>, String.eq(tag, "Subscript") && lit && String.eq(tag_of(v), "Name") && String.eq(N.string(field(v, "id")), "Literal"), u =>
              S.choose(List<&2, String>, String.eq(tag_of(s), "Tuple"), u => each(items(field(s, "elts"))), u => [elt(s)]), u => [""]))))
    case S.JField{key, value, +rest}:
      S.choose(List<&2, String>, has(["left", "right"], key), u => List.append(&2, String, domain(value, bl, lit), domain(rest, bl, lit)), u =>
        domain(rest, bl, lit))
    case _:
      []

def single(j: S.Json) -> String:
  match j:
    case S.JBool{b}:
      Bool.pick(String, b, "True", "False")
    case _:
      "None"

# Python's == on domain values: True == 1 and False == 0; otherwise equal iff
# the reprs are (a str never equals an int).
def eqv(+v: String) -> String:
  S.choose(String, String.eq(v, "True"), u => "1", u => S.choose(String, String.eq(v, "False"), u => "0", u => v))

# Does the M0 pattern `j` match `v`? Singletons by identity, values by ==.
def hits(j: S.Json, +v: String) -> Bool:
  match j:
    case S.JObj{+fs}:
      +tag = N.string(N.get(fs, "tag"))
      S.choose(Bool, String.eq(tag, "MatchSingleton"), u => String.eq(single(N.get(fs, "value")), v), u =>
        S.choose(Bool, String.eq(tag, "MatchValue"), u => String.eq(eqv(elt(N.get(fs, "value"))), eqv(v)), u =>
          (String.eq(tag, "MatchAs") && is_null(N.get(fs, "pattern"))) || hits(fs, v)))
    case S.JField{key, value, +rest}:
      S.choose(Bool, has(["pattern", "patterns"], key), u => hits(value, v), u => hits(rest, v))
    case S.JArr{xs}:
      hits(xs, v)
    case S.JItem{h, t}:
      hits(h, v) || hits(t, v)
    case _:
      False{}

# "" iff pattern `j` is in M0: a singleton, a literal value, a capture or
# wildcard, as- and or-patterns over those; else the first offender.
def pat_why(j: S.Json) -> String:
  match j:
    case S.JObj{+fs}:
      +tag = N.string(N.get(fs, "tag"))
      S.choose(String, String.eq(tag, "MatchSingleton") || (String.eq(tag, "MatchValue") && Bool.not(String.is_empty(elt(N.get(fs, "value"))))), u => "", u =>
        S.choose(String, has(["MatchAs", "MatchOr"], tag), u => pat_why(fs), u => "pattern " ++ tag ++ at(N.get(fs, "_loc")) ++ " is outside M0"))
    case S.JField{key, value, rest}:
      +a = pat_why(value)
      S.choose(String, String.is_empty(a), u => pat_why(rest), u => a)
    case S.JArr{xs}:
      pat_why(xs)
    case S.JItem{h, t}:
      +a = pat_why(h)
      S.choose(String, String.is_empty(a), u => pat_why(t), u => a)
    case _:
      ""

def arms_why(xs: S.Json) -> String:
  match xs:
    case S.JItem{h, t}:
      +a = pat_why(field(h, "pattern"))
      S.choose(String, String.is_empty(a), u => arms_why(t), u => a)
    case _:
      ""

def param(xs: S.Json, +x: String) -> S.Json:
  match xs:
    case S.JItem{+h, t}:
      S.choose(S.Json, String.eq(N.string(field(h, "arg")), x), u => h, u => param(t, x))
    case _:
      S.JNull{}

def spot(+loc: S.Json) -> String:
  Nat.show(line(loc)) ++ ":" ++ Nat.show(col(loc))

# M0 membership of one match, recomputed: the subject is a parameter of the
# innermost def `f`, which has no defaults and binds it nowhere else; its
# annotation pins a finite domain; every case pattern is in M0.
def site(+fs: S.Json, +f: S.Json, +bl: Bool, +lit: Bool) -> Site:
  +s = N.get(fs, "subject")
  +x = N.string(field(s, "id"))
  +a = field(f, "args")
  +p = param(items(field(a, "args")), x)
  +d = domain(field(p, "annotation"), bl, lit)
  +cases = N.get(fs, "cases")
  why = S.choose(String, Bool.not(String.eq(tag_of(s), "Name")), u => "the subject is not a name", u =>
    S.choose(String, is_null(p), u => x ++ " is not a parameter of the enclosing def", u =>
      S.choose(String, Bool.not(is_empty(field(a, "defaults"))), u => "the def has parameter defaults", u =>
        S.choose(String, Bool.not(Nat.is_eq(binders(f, "", x), 1n)), u => x ++ " is rebound in the def", u =>
          S.choose(String, has(d, "") || Nat.is_eq(List.length(&2, String, d), 0n), u => "the annotation of " ++ x ++ " pins no finite domain", u =>
            arms_why(items(cases)))))))
  Site{N.get(fs, "_loc"), d, cases, why}

# Every match under `j`; `f` is the innermost enclosing def (JNull at module
# level or in a class).
def sites(j: S.Json, +f: S.Json, +bl: Bool, +lit: Bool) -> List<&2, Site>:
  match j:
    case S.JObj{+fs}:
      +tag = N.string(N.get(fs, "tag"))
      +g = S.choose(S.Json, String.eq(tag, "FunctionDef"), u => S.JObj{fs}, u =>
        S.choose(S.Json, has(["ClassDef", "AsyncFunctionDef"], tag), u => S.JNull{}, u => f))
      List.append(&2, Site, S.choose(List<&2, Site>, String.eq(tag, "Match"), u => [site(fs, f, bl, lit)], u => []), sites(fs, g, bl, lit))
    case S.JField{key, value, rest}:
      List.append(&2, Site, sites(value, f, bl, lit), sites(rest, f, bl, lit))
    case S.JArr{xs}:
      sites(xs, f, bl, lit)
    case S.JItem{h, t}:
      List.append(&2, Site, sites(h, f, bl, lit), sites(t, f, bl, lit))
    case _:
      []

def literal_alias(xs: S.Json) -> Bool:
  match xs:
    case S.JItem{+h, t}:
      (String.eq(N.string(field(h, "name")), "Literal") && is_null(field(h, "asname"))) || literal_alias(t)
    case _:
      False{}

def level0(j: S.Json) -> Bool:
  match j:
    case S.JNum{n}:
      Nat.is_eq(n, 0n)
    case _:
      False{}

def typing_literal(xs: S.Json) -> Bool:
  match xs:
    case S.JItem{+h, t}:
      (String.eq(tag_of(h), "ImportFrom") && String.eq(N.string(field(h, "module")), "typing") && level0(field(h, "level")) &&
        literal_alias(items(field(h, "names")))) || typing_literal(t)
    case _:
      False{}

# bool is the builtin iff nothing in the module binds it; Literal is
# typing.Literal iff a top-level `from typing import Literal` is its only binder.
def module_sites(m: S.Module) -> List<&2, Site>:
  S.Module{+body} = m
  sites(body, S.JNull{}, Nat.is_eq(binders(body, "", "bool"), 0n), Nat.is_eq(binders(body, "", "Literal"), 1n) && typing_literal(body))

def find_site(ss: List<&2, Site>, +here: String) -> Maybe<&2, Site>:
  match ss:
    case Nil{}:
      None{}
    case Site{+loc, dom, cases, why} <> t:
      S.choose(Maybe<&2, Site>, String.eq(spot(loc), here), u => Some{Site{loc, dom, cases, why}}, u => find_site(t, here))

def site_of(+m: S.Module, +here: String) -> Site:
  Maybe.default(&2, Site, find_site(module_sites(m), here), Site{S.JNull{}, [], S.JEnd{}, "no match statement there"})

def loc_of(s: Site) -> S.Json:
  Site{loc, d, cases, why} = s
  loc

def dom_of(s: Site) -> List<&2, String>:
  Site{loc, d, cases, why} = s
  d

def cases_of(s: Site) -> S.Json:
  Site{loc, d, cases, why} = s
  cases

def nth(n: Nat, xs: S.Json) -> S.Json:
  match n:
    case 0n:
      first(xs)
    case 1n+p:
      match xs:
        case S.JItem{h, t}:
          nth(p, t)
        case _:
          S.JNull{}

# The first case from number `i` whose pattern matches `v` (only unguarded
# cases when `strict`).
def first_arm(xs: S.Json, +v: String, +i: Nat, +strict: Bool) -> Maybe<&2, Nat>:
  match xs:
    case S.JItem{+h, t}:
      S.choose(Maybe<&2, Nat>, hits(field(h, "pattern"), v) && (Bool.not(strict) || is_null(field(h, "guard"))), u => Some{i}, u =>
        first_arm(t, v, 1n+i, strict))
    case _:
      None{}

# "" iff case `k` (number `n`) matches no value of `d` that an earlier
# unguarded case does not catch first.
def dead_why(d: List<&2, String>, +cases: S.Json, +n: Nat, +k: S.Json) -> String:
  match d:
    case Nil{}:
      ""
    case +v <> t:
      +j = Maybe.default(&2, Nat, first_arm(items(cases), v, 0n, True{}), n)
      S.choose(String, Bool.not(hits(field(k, "pattern"), v)) || Nat.is_lt(j, n), u => dead_why(t, cases, n, k), u =>
        v ++ " reaches case " ++ Nat.show(n))

# "" iff the claim holds of its match's recomputed domain and cases.
def claim_why(c: Claim, +d: List<&2, String>, +cases: S.Json) -> String:
  match c:
    case Covers{here, +v, +n}:
      +k = nth(n, items(cases))
      S.choose(String, Bool.not(has(d, v)), u => v ++ " is not in the domain", u =>
        S.choose(String, is_null(k), u => "no case " ++ Nat.show(n), u =>
          S.choose(String, Bool.not(is_null(field(k, "guard"))), u => "case " ++ Nat.show(n) ++ " is guarded", u =>
            S.choose(String, hits(field(k, "pattern"), v), u => "", u => "case " ++ Nat.show(n) ++ " does not match " ++ v))))
    case Miss{here, +v}:
      +j = first_arm(items(cases), v, 0n, False{})
      S.choose(String, Bool.not(has(d, v)), u => v ++ " is not in the domain", u =>
        S.choose(String, Maybe.is_none(&2, Nat, j), u => "", u => "case " ++ Nat.show(Maybe.default(&2, Nat, j, 0n)) ++ " matches " ++ v))
    case Dead{here, +n}:
      +k = nth(n, items(cases))
      S.choose(String, is_null(k), u => "no case " ++ Nat.show(n), u => dead_why(d, cases, n, k))

def at_of(c: Claim) -> String:
  match c:
    case Covers{here, v, n}:
      here
    case Miss{here, v}:
      here
    case Dead{here, n}:
      here

def check(+c: Claim, s: Maybe<&2, Site>) -> String:
  match s:
    case None{}:
      "no match statement there"
    case Some{Site{loc, d, cases, +why}}:
      S.choose(String, String.is_empty(why), u => claim_why(c, d, cases), u => why)

# "" iff every claim holds of the match it names, M0 membership included,
# all recomputed from the AST: one bad claim refutes the whole witness.
def certify(w: List<&2, Claim>, +ss: List<&2, Site>) -> String:
  match w:
    case Nil{}:
      ""
    case +c <> t:
      +why = check(c, find_site(ss, at_of(c)))
      S.choose(String, String.is_empty(why), u => certify(t, ss), u => "claim at " ++ at_of(c) ++ ": " ++ why)

def mine(w: List<&2, Claim>, +here: String) -> List<&2, Claim>:
  match w:
    case Nil{}:
      []
    case +c <> t:
      List.append(&2, Claim, S.choose(List<&2, Claim>, String.eq(at_of(c), here), u => [c], u => []), mine(t, here))

def missed(cs: List<&2, Claim>) -> String:
  match cs:
    case Nil{}:
      ""
    case Miss{here, v} <> t:
      v
    case Covers{here, v, n} <> t:
      missed(t)
    case Dead{here, n} <> t:
      missed(t)

def covered(cs: List<&2, Claim>, +v: String) -> Bool:
  match cs:
    case Nil{}:
      False{}
    case Covers{here, x, n} <> t:
      String.eq(x, v) || covered(t, v)
    case Miss{here, x} <> t:
      covered(t, v)
    case Dead{here, n} <> t:
      covered(t, v)

def uncovered(d: List<&2, String>, +cs: List<&2, Claim>) -> String:
  match d:
    case Nil{}:
      ""
    case +v <> t:
      S.choose(String, covered(cs, v), u => uncovered(t, cs), u => v)

def braces(d: List<&2, String>) -> String:
  "{" ++ String.join(d, ", ") ++ "}"

def cover(claims: List<&2, Claim>, +m: S.Module, +w: List<&2, Claim>, +here: String) -> Diag:
  match claims:
    case Nil{}:
      Diag{loc_of(site_of(m, here)), "exhaustive", Unknown{}, "no certificate"}
    case +h <> +t:
      +s = site_of(m, here)
      +loc = loc_of(s)
      +d = dom_of(s)
      +why = certify(w, module_sites(m))
      +miss = missed(h <> t)
      +gap = uncovered(d, h <> t)
      S.choose(Diag, Bool.not(String.is_empty(why)), u => Diag{loc, "exhaustive", Refuted{}, "certificate refuted: " ++ why}, u =>
        S.choose(Diag, Bool.not(String.is_empty(miss)), u => Diag{loc, "exhaustive", Refuted{}, "not exhaustive: " ++ miss ++ " matches no case"}, u =>
          S.choose(Diag, String.is_empty(gap), u => Diag{loc, "exhaustive", Proven{}, "every value of " ++ braces(d) ++ " reaches an unguarded case"}, u =>
            Diag{loc, "exhaustive", Refuted{}, "certificate refuted: no case claimed for " ++ gap})))

# Kernel entry: is match `here` ("line:col") exhaustive under witness `w`? Its
# claims are consulted first, so none means no proof (the law below).
def exhaustive(+m: S.Module, +w: List<&2, Claim>, +here: String) -> Diag:
  cover(mine(w, here), m, w, here)

def claims_dead(w: List<&2, Claim>, +here: String, +n: Nat) -> Bool:
  match w:
    case Nil{}:
      False{}
    case Dead{a, k} <> t:
      (String.eq(a, here) && Nat.is_eq(k, n)) || claims_dead(t, here, n)
    case Covers{a, v, k} <> t:
      claims_dead(t, here, n)
    case Miss{a, v} <> t:
      claims_dead(t, here, n)

def arm_loc(+m: S.Module, +here: String, +n: Nat) -> S.Json:
  field(field(nth(n, items(cases_of(site_of(m, here)))), "pattern"), "_loc")

def unreached(c: Bool, +m: S.Module, +w: List<&2, Claim>, +here: String, +n: Nat) -> Diag:
  match c:
    case False{}:
      Diag{arm_loc(m, here, n), "dead-case", Unknown{}, "no certificate"}
    case True{}:
      d = dom_of(site_of(m, here))
      +why = certify(w, module_sites(m))
      S.choose(Diag, String.is_empty(why), u => Diag{arm_loc(m, here, n), "dead-case", Proven{}, "no value of " ++ braces(d) ++ " reaches this case"}, u =>
        Diag{arm_loc(m, here, n), "dead-case", Refuted{}, "certificate refuted: " ++ why})

# Kernel entry: is case `n` of match `here` dead under witness `w`?
def dead_case(+m: S.Module, +w: List<&2, Claim>, +here: String, +n: Nat) -> Diag:
  unreached(claims_dead(w, here, n), m, w, here, n)

law no_certificate_no_coverage:
  for +m: S.Module
  for +here: String
  {is_proven(exhaustive(m, Nil{}, here)) == False{} : Bool}

def no_certificate_no_coverage(m, here):
  {==}

law no_certificate_no_dead_case:
  for +m: S.Module
  for +here: String
  for +n: Nat
  {is_proven(dead_case(m, Nil{}, here, n)) == False{} : Bool}

def no_certificate_no_dead_case(m, here, n):
  {==}

# ---- L3 analyze: untrusted claim search, then the kernel ----

# Per value: the first unguarded case that matches it, else Miss if no case
# matches it at all; a value only guarded cases match gets no claim.
def search(d: List<&2, String>, +here: String, +cases: S.Json) -> List<&2, Claim>:
  match d:
    case Nil{}:
      []
    case +v <> t:
      +j = first_arm(items(cases), v, 0n, True{})
      c = S.choose(List<&2, Claim>, Maybe.is_some(&2, Nat, j), u => [Covers{here, v, Maybe.default(&2, Nat, j, 0n)}], u =>
        S.choose(List<&2, Claim>, Maybe.is_none(&2, Nat, first_arm(items(cases), v, 0n, False{})), u => [Miss{here, v}], u => []))
      List.append(&2, Claim, c, search(t, here, cases))

def deads(xs: S.Json, +d: List<&2, String>, +here: String, +cases: S.Json, +n: Nat) -> List<&2, Claim>:
  match xs:
    case S.JItem{h, t}:
      List.append(&2, Claim, S.choose(List<&2, Claim>, String.is_empty(dead_why(d, cases, n, h)), u => [Dead{here, n}], u => []),
        deads(t, d, here, cases, 1n+n))
    case _:
      []

def witness(ss: List<&2, Site>) -> List<&2, Claim>:
  match ss:
    case Nil{}:
      []
    case Site{+loc, +d, +cases, +why} <> t:
      +here = spot(loc)
      List.append(&2, Claim, S.choose(List<&2, Claim>, String.is_empty(why), u =>
        List.append(&2, Claim, search(d, here, cases), deads(items(cases), d, here, cases, 0n)), u => []), witness(t))

def only_guarded(d: List<&2, String>, +cases: S.Json) -> String:
  match d:
    case Nil{}:
      ""
    case +v <> t:
      S.choose(String, Maybe.is_none(&2, Nat, first_arm(items(cases), v, 0n, True{})) &&
        Maybe.is_some(&2, Nat, first_arm(items(cases), v, 0n, False{})), u => v, u => only_guarded(t, cases))

def dead_diags(cs: List<&2, Claim>, +m: S.Module, +w: List<&2, Claim>) -> List<&2, Diag>:
  match cs:
    case Nil{}:
      []
    case Dead{here, n} <> t:
      dead_case(m, w, here, n) <> dead_diags(t, m, w)
    case Covers{here, v, n} <> t:
      dead_diags(t, m, w)
    case Miss{here, v} <> t:
      dead_diags(t, m, w)

def verdicts(ss: List<&2, Site>, +m: S.Module, +w: List<&2, Claim>) -> List<&2, Diag>:
  match ss:
    case Nil{}:
      []
    case Site{+loc, +d, +cases, +why} <> t:
      +here = spot(loc)
      +g = only_guarded(d, cases)
      e = S.choose(Diag, Bool.not(String.is_empty(why)), u => Diag{loc, "exhaustive", Unknown{}, why}, u =>
        S.choose(Diag, Bool.not(String.is_empty(g)) && String.is_empty(missed(mine(w, here))), u =>
          Diag{loc, "exhaustive", Unknown{}, g ++ " reaches only guarded cases"}, u => exhaustive(m, w, here)))
      e <> List.append(&2, Diag, dead_diags(mine(w, here), m, w), verdicts(t, m, w))

# `exhaustive` per match and `dead-case` per dead case, through the kernel.
def coverage(+m: S.Module) -> List<&2, Diag>:
  +ss = module_sites(m)
  List.sort(~Diag, ~le, verdicts(ss, m, witness(ss)))

# ---- L4: closed-module summaries (U0) ----

# One module of the summary set, imported as `name` and rendered as name.py.
# The set is closed when every import resolves inside it (SOUNDNESS.md, A5).
type Mod is Data:
  Mod{name: String, m: S.Module}

# A summary entry, forgeable like a rank: a module's import rank, a def's pure
# rank, or a counterexample path of imports (back to its start, or out of the set).
type Summary is Data:
  Ranked{module: String, rank: Nat}
  Pure{module: String, name: String, rank: Nat}
  Path{mods: List<&2, String>}

# A top-level binder and what it denotes: mod.def, n.x or the module n.
type Link is Data:
  Link{name: String, qual: String}

def mod_names(ms: List<&2, Mod>) -> List<&2, String>:
  match ms:
    case Nil{}:
      []
    case Mod{name, m} <> t:
      name <> mod_names(t)

def mod_body(ms: List<&2, Mod>, +k: String) -> S.Json:
  match ms:
    case Nil{}:
      S.JEnd{}
    case Mod{+name, m} <> t:
      S.Module{body} = m
      S.choose(S.Json, String.eq(name, k), u => body, u => mod_body(t, k))

def plain(xs: S.Json, +bad: String) -> Bool:
  match xs:
    case S.JItem{h, t}:
      Bool.not(String.contains(N.string(field(h, "name")), bad)) && plain(t, bad)
    case _:
      True{}

# U0's imports: `import n [as a], ...` and `from n import x [as a], ...` at
# level 0, every n a single name, no star.
def u0_import(+h: S.Json) -> Bool:
  +tag = tag_of(h)
  +n = N.string(field(h, "module"))
  S.choose(Bool, String.eq(tag, "Import"), u => plain(items(field(h, "names")), "."), u =>
    String.eq(tag, "ImportFrom") && level0(field(h, "level")) && Bool.not(String.contains(n, ".")) &&
      plain(items(field(h, "names")), "*"))

def alias_names(xs: S.Json) -> List<&2, String>:
  match xs:
    case S.JItem{h, t}:
      N.string(field(h, "name")) <> alias_names(t)
    case _:
      []

# The modules a U0 import statement names, in order.
def targets(+h: S.Json) -> List<&2, String>:
  S.choose(List<&2, String>, Bool.not(u0_import(h)), u => [], u =>
    S.choose(List<&2, String>, String.eq(tag_of(h), "Import"), u => alias_names(items(field(h, "names"))), u =>
      [N.string(field(h, "module"))]))

# A module's import edges, in statement order.
def deps(xs: S.Json) -> List<&2, String>:
  match xs:
    case S.JItem{+h, t}:
      List.append(&2, String, targets(h), deps(t))
    case _:
      []

# The top level without its U0 imports: what `closed` must still admit.
def rest_of(xs: S.Json) -> S.Json:
  match xs:
    case S.JItem{+h, +t}:
      S.choose(S.Json, u0_import(h), u => rest_of(t), u => S.JItem{h, rest_of(t)})
    case _:
      S.JEnd{}

def aliases(xs: S.Json, +pre: String) -> List<&2, Link>:
  match xs:
    case S.JItem{+h, t}:
      +x = N.string(field(h, "name"))
      +a = field(h, "asname")
      Link{S.choose(String, is_null(a), u => x, u => N.string(a)), pre ++ x} <> aliases(t, pre)
    case _:
      []

# Every top-level binder of module `mod`: def d is mod.d, `from n import x as a`
# binds a to n.x, `import n as a` binds a to the module n.
def links(xs: S.Json, +mod: String) -> List<&2, Link>:
  match xs:
    case S.JItem{+h, t}:
      +tag = tag_of(h)
      +d = N.string(field(h, "name"))
      +pre = S.choose(String, String.eq(tag, "ImportFrom"), u => N.string(field(h, "module")) ++ ".", u => "")
      List.append(&2, Link, S.choose(List<&2, Link>, String.eq(tag, "FunctionDef"), u => [Link{d, mod ++ "." ++ d}], u =>
        S.choose(List<&2, Link>, u0_import(h), u => aliases(items(field(h, "names")), pre), u => [])), links(t, mod))
    case _:
      []

def link_names(ls: List<&2, Link>) -> List<&2, String>:
  match ls:
    case Nil{}:
      []
    case Link{name, q} <> t:
      name <> link_names(t)

def qual(ls: List<&2, Link>, +k: String) -> String:
  match ls:
    case Nil{}:
      k
    case Link{name, q} <> t:
      S.choose(String, String.eq(name, k), u => q, u => qual(t, k))

def qualify(fs: List<&2, Fact>, +ls: List<&2, Link>) -> List<&2, Fact>:
  match fs:
    case Nil{}:
      []
    case Bad{loc, why} <> t:
      Bad{loc, why} <> qualify(t, ls)
    case Calls{g} <> t:
      Calls{qual(ls, g)} <> qualify(t, ls)

# T0's conditions for mod.name with its imports as module binders; callees
# come out qualified (mod.def, n.x).
def check_x(+ms: List<&2, Mod>, +cs: List<&2, Contract>, +mod: String, +name: String) -> List<&2, Fact>:
  +body = mod_body(ms, mod)
  +ls = links(body, mod)
  qualify(member(body, cs, name, False{}, link_names(ls)), ls)

# The module ranks (`p` False) or the pure ranks, keyed mod.def (`p` True).
def ranks(w: List<&2, Summary>, +p: Bool) -> List<&2, Rank>:
  match w:
    case Nil{}:
      []
    case Ranked{mod, r} <> t:
      List.append(&2, Rank, S.choose(List<&2, Rank>, p, u => [], u => [Rank{mod, r}]), ranks(t, p))
    case Pure{mod, name, r} <> t:
      List.append(&2, Rank, S.choose(List<&2, Rank>, p, u => [Rank{mod ++ "." ++ name, r}], u => []), ranks(t, p))
    case Path{ps} <> t:
      ranks(t, p)

def undefined(xs: S.Json, +defs: List<&2, String>) -> String:
  match xs:
    case S.JItem{+h, t}:
      +x = N.string(field(h, "name"))
      S.choose(String, has(defs, x), u => undefined(t, defs), u => x)
    case _:
      ""

# Per module an import statement names: Bad if it is outside the summary set
# or lacks a def the statement imports from it, else the edge Calls{module}.
def stmt_facts(+h: S.Json, ts: List<&2, String>, +ms: List<&2, Mod>) -> List<&2, Fact>:
  match ts:
    case Nil{}:
      []
    case +t <> rest:
      +loc = field(h, "_loc")
      +x = S.choose(String, String.eq(tag_of(h), "ImportFrom"), u => undefined(items(field(h, "names")), def_names(mod_body(ms, t))), u => "")
      f = S.choose(Fact, Bool.not(has(mod_names(ms), t)), u => Bad{loc, "missing module " ++ t ++ at(loc)}, u =>
        S.choose(Fact, String.is_empty(x), u => Calls{t}, u => Bad{loc, t ++ " has no def " ++ x ++ at(loc)}))
      f <> stmt_facts(h, rest, ms)

def imp_facts(xs: S.Json, +ms: List<&2, Mod>) -> List<&2, Fact>:
  match xs:
    case S.JItem{+h, t}:
      List.append(&2, Fact, stmt_facts(h, targets(h), ms), imp_facts(t, ms))
    case _:
      []

def ranked_below(k: Maybe<&2, Nat>, r: Maybe<&2, Nat>) -> Bool:
  match r:
    case None{}:
      Maybe.is_some(&2, Nat, k)
    case Some{+n}:
      Nat.is_lt(Maybe.default(&2, Nat, k, n), n)

# "" iff no fact is Bad and every import edge holds a module rank below `r`
# (the kernel), or any rank (`r` None: the search's view).
def below(fs: List<&2, Fact>, +mr: List<&2, Rank>, +r: Maybe<&2, Nat>) -> String:
  match fs:
    case Nil{}:
      ""
    case Bad{loc, why} <> t:
      why
    case Calls{+g} <> t:
      S.choose(String, ranked_below(rank(mr, g), r), u => below(t, mr, r), u =>
        S.choose(String, Maybe.is_none(&2, Nat, r), u => "import of " ++ g ++ " is not certified (cycle or Unknown)", u =>
          "import of " ++ g ++ " holds no smaller rank"))

# "" iff `mod` is one module of the set, closed but for U0 imports, and each
# import names a module of the set (and, `from n import x`, a def x of n)
# ranked below `r`.
def mod_why(+ms: List<&2, Mod>, +mod: String, +mr: List<&2, Rank>, +r: Maybe<&2, Nat>) -> String:
  +body = mod_body(ms, mod)
  S.choose(String, Bool.not(Nat.is_eq(count(mod_names(ms), mod), 1n)), u => "no unique module " ++ mod, u =>
    below(List.append(&2, Fact, closed(rest_of(body)), imp_facts(body, ms)), mr, r))

def final(xs: List<&2, String>, +d: String) -> String:
  match xs:
    case Nil{}:
      d
    case h <> t:
      final(t, h)

def hops(ys: List<&2, String>, +x: String, +ms: List<&2, Mod>) -> String:
  match ys:
    case Nil{}:
      ""
    case +y <> t:
      S.choose(String, has(deps(mod_body(ms, x)), y), u => hops(t, y, ms), u => x ++ " does not import " ++ y)

# "" iff `p` walks at least one recomputed import edge and ends on a module
# it passed already (a cycle below its start) or outside the summary set.
def path_why(p: List<&2, String>, +ms: List<&2, Mod>) -> String:
  match p:
    case Nil{}:
      "empty path"
    case +a <> +t:
      +z = final(t, a)
      S.choose(String, List.is_empty(&2, String, t), u => "no edge", u =>
        S.choose(String, Nat.is_lt(1n, count(a <> t, z)) || Bool.not(has(mod_names(ms), z)), u => hops(t, a, ms), u =>
          "the path neither closes a cycle nor leaves the summary set"))

def tagged(+who: String, +why: String) -> String:
  S.choose(String, String.is_empty(why), u => "", u => who ++ ": " ++ why)

# "" iff the entry checks against the actual modules, every condition recomputed.
def entry_why(e: Summary, +ms: List<&2, Mod>, +cs: List<&2, Contract>, +w: List<&2, Summary>) -> String:
  match e:
    case Ranked{+mod, r}:
      tagged(mod, mod_why(ms, mod, ranks(w, False{}), Some{r}))
    case Pure{+mod, +name, r}:
      tagged(mod ++ "." ++ name, S.choose(String, Maybe.is_none(&2, Nat, rank(ranks(w, False{}), mod)), u =>
        "module " ++ mod ++ " holds no import certificate", u => discharge(check_x(ms, cs, mod, name), ranks(w, True{}), r)))
    case Path{+p}:
      tagged("path [" ++ String.join(p, " -> ") ++ "]", path_why(p, ms))

# "" iff every entry checks: one bad entry refutes the whole summary.
def vouch(es: List<&2, Summary>, +ms: List<&2, Mod>, +cs: List<&2, Contract>, +w: List<&2, Summary>) -> String:
  match es:
    case Nil{}:
      ""
    case e <> t:
      +why = entry_why(e, ms, cs, w)
      S.choose(String, String.is_empty(why), u => vouch(t, ms, cs, w), u => why)

def is_about(e: Summary, +mod: String) -> Bool:
  match e:
    case Ranked{m, r}:
      String.eq(m, mod)
    case Pure{m, n, r}:
      False{}
    case Path{p}:
      String.eq(Maybe.default(&2, String, List.head(&2, String, p), ""), mod)

# The import claims about `mod`: its rank, or a path from it.
def about(w: List<&2, Summary>, +mod: String) -> List<&2, Summary>:
  match w:
    case Nil{}:
      []
    case +e <> t:
      List.append(&2, Summary, S.choose(List<&2, Summary>, is_about(e, mod), u => [e], u => []), about(t, mod))

def path_of(w: List<&2, Summary>) -> List<&2, String>:
  match w:
    case Nil{}:
      []
    case Path{p} <> t:
      p
    case Ranked{mod, r} <> t:
      path_of(t)
    case Pure{mod, name, r} <> t:
      path_of(t)

def second(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case h <> t:
      Maybe.default(&2, String, List.head(&2, String, t), "")

# The first top-level import naming module `t` ("": any import at all).
def import_loc(xs: S.Json, +t: String) -> S.Json:
  match xs:
    case S.JItem{+h, tl}:
      S.choose(S.Json, has(["Import", "ImportFrom"], tag_of(h)) && (String.is_empty(t) || has(targets(h), t)), u => field(h, "_loc"), u =>
        import_loc(tl, t))
    case _:
      S.JNull{}

def counter(+p: List<&2, String>, +ms: List<&2, Mod>) -> String:
  +z = final(p, "")
  S.choose(String, has(mod_names(ms), z), u => "import cycle " ++ String.join(p, " -> "), u =>
    "missing module " ++ z ++ " via " ++ String.join(p, " -> "))

def settled(cl: List<&2, Summary>, +ms: List<&2, Mod>, +cs: List<&2, Contract>, +w: List<&2, Summary>, +mod: String) -> Diag:
  match cl:
    case Nil{}:
      Diag{import_loc(mod_body(ms, mod), ""), "imports", Unknown{}, "no certificate"}
    case +h <> +t:
      +body = mod_body(ms, mod)
      +why = vouch(w, ms, cs, w)
      +p = path_of(h <> t)
      S.choose(Diag, Bool.not(String.is_empty(why)), u => Diag{import_loc(body, ""), "imports", Refuted{}, "certificate refuted: " ++ why}, u =>
        S.choose(Diag, List.is_empty(&2, String, p), u =>
          Diag{import_loc(body, ""), "imports", Proven{}, "every import resolves in the summary set, acyclically (U0)"}, u =>
          Diag{import_loc(body, second(p)), "imports", Refuted{}, counter(p, ms)}))

# Kernel entry: do the imports of module `mod` resolve in the summary set,
# acyclically? Its claims are consulted first, so none means no proof.
def imports(+ms: List<&2, Mod>, +cs: List<&2, Contract>, +w: List<&2, Summary>, +mod: String) -> Diag:
  settled(about(w, mod), ms, cs, w, mod)

def held(entry: Maybe<&2, Nat>, +ms: List<&2, Mod>, +cs: List<&2, Contract>, +w: List<&2, Summary>, +mod: String, +name: String) -> Diag:
  match entry:
    case None{}:
      Diag{field(find_def(mod_body(ms, mod), name), "_loc"), "pure", Unknown{}, "no certificate"}
    case Some{r}:
      +loc = field(find_def(mod_body(ms, mod), name), "_loc")
      +why = vouch(w, ms, cs, w)
      S.choose(Diag, String.is_empty(why), u => Diag{loc, "pure", Proven{}, "terminates with no effect, through its imports (U0)"}, u =>
        Diag{loc, "pure", Refuted{}, "certificate refuted: " ++ why})

# Kernel entry: is mod.name in U0, T0 across the summary set?
def pure(+ms: List<&2, Mod>, +cs: List<&2, Contract>, +w: List<&2, Summary>, +mod: String, +name: String) -> Diag:
  held(rank(ranks(w, True{}), mod ++ "." ++ name), ms, cs, w, mod, name)

law no_certificate_no_imports:
  for +ms: List<&2, Mod>
  for +cs: List<&2, Contract>
  for +mod: String
  {is_proven(imports(ms, cs, Nil{}, mod)) == False{} : Bool}

def no_certificate_no_imports(ms, cs, mod):
  {==}

law no_certificate_no_purity:
  for +ms: List<&2, Mod>
  for +cs: List<&2, Contract>
  for +mod: String
  for +name: String
  {is_proven(pure(ms, cs, Nil{}, mod, name)) == False{} : Bool}

def no_certificate_no_purity(ms, cs, mod, name):
  {==}

# ---- L4 analyze: untrusted summary search, then the kernel ----

def mround(names: List<&2, String>, +ms: List<&2, Mod>, +w: List<&2, Summary>, +r: Nat) -> List<&2, Summary>:
  match names:
    case Nil{}:
      []
    case +h <> t:
      ok = Maybe.is_none(&2, Nat, rank(ranks(w, False{}), h)) && String.is_empty(mod_why(ms, h, ranks(w, False{}), None{}))
      List.append(&2, Summary, S.choose(List<&2, Summary>, ok, u => [Ranked{h, r}], u => []), mround(t, ms, w, r))

def pdefs(ds: List<&2, String>, +mod: String, +ms: List<&2, Mod>, +cs: List<&2, Contract>, +w: List<&2, Summary>, +r: Nat) -> List<&2, Summary>:
  match ds:
    case Nil{}:
      []
    case +d <> t:
      ok = Maybe.is_none(&2, Nat, rank(ranks(w, True{}), mod ++ "." ++ d)) && String.is_empty(why_not(check_x(ms, cs, mod, d), ranks(w, True{})))
      List.append(&2, Summary, S.choose(List<&2, Summary>, ok, u => [Pure{mod, d, r}], u => []), pdefs(t, mod, ms, cs, w, r))

def pround(mods: List<&2, String>, +ms: List<&2, Mod>, +cs: List<&2, Contract>, +w: List<&2, Summary>, +r: Nat) -> List<&2, Summary>:
  match mods:
    case Nil{}:
      []
    case +mod <> t:
      List.append(&2, Summary, pdefs(def_names(mod_body(ms, mod)), mod, ms, cs, w, r), pround(t, ms, cs, w, r))

# One round per unit of fuel: module ranks (`p` False) or pure ranks over the
# defs of `names`, each above what earlier rounds ranked.
def summarize(fuel: Nat, +p: Bool, +names: List<&2, String>, +ms: List<&2, Mod>, +cs: List<&2, Contract>, +w: List<&2, Summary>, +r: Nat) -> List<&2, Summary>:
  match fuel:
    case 0n:
      w
    case 1n+q:
      more = S.choose(List<&2, Summary>, p, u => pround(names, ms, cs, w, r), u => mround(names, ms, w, r))
      summarize(q, p, names, ms, cs, List.append(&2, Summary, w, more), 1n+r)

# An import walk from the targets `ts` back into `seen` (the walk so far) or out
# of the summary set, depth-first in import order, at most `fuel` edges deep.
# ponytail: no visited set, exponential on dense import graphs; memoize if it matters.
def trail(fuel: Nat, ts: List<&2, String>, +seen: List<&2, String>, +ms: List<&2, Mod>) -> List<&2, String>:
  match fuel:
    case 0n:
      []
    case 1n++q:
      match ts:
        case Nil{}:
          []
        case +t <> rest:
          +goal = has(seen, t) || Bool.not(has(mod_names(ms), t))
          +p = S.choose(List<&2, String>, goal, u => [], u => trail(q, deps(mod_body(ms, t)), t <> seen, ms))
          S.choose(List<&2, String>, goal, u => [t], u =>
            S.choose(List<&2, String>, List.is_empty(&2, String, p), u => trail(1n+q, rest, seen, ms), u => t <> p))

def paths(names: List<&2, String>, +ms: List<&2, Mod>, +mr: List<&2, Rank>, +n: Nat) -> List<&2, Summary>:
  match names:
    case Nil{}:
      []
    case +h <> t:
      +p = trail(n, deps(mod_body(ms, h)), [h], ms)
      List.append(&2, Summary, S.choose(List<&2, Summary>, Maybe.is_none(&2, Nat, rank(mr, h)) && Bool.not(List.is_empty(&2, String, p)), u =>
        [Path{h <> p}], u => []), paths(t, ms, mr, n))

def ndefs(names: List<&2, String>, +ms: List<&2, Mod>) -> Nat:
  match names:
    case Nil{}:
      0n
    case +h <> t:
      Nat.add(List.length(&2, String, def_names(mod_body(ms, h))), ndefs(t, ms))

def pures(ds: List<&2, String>, +mod: String, +ms: List<&2, Mod>, +cs: List<&2, Contract>, +w: List<&2, Summary>) -> List<&2, Diag>:
  match ds:
    case Nil{}:
      []
    case +d <> t:
      +loc = field(find_def(mod_body(ms, mod), d), "_loc")
      v = S.choose(Diag, Maybe.is_some(&2, Nat, rank(ranks(w, True{}), mod ++ "." ++ d)), u => pure(ms, cs, w, mod, d), u =>
        Diag{loc, "pure", Unknown{}, S.choose(String, Maybe.is_none(&2, Nat, rank(ranks(w, False{}), mod)), u =>
          tagged(mod, mod_why(ms, mod, ranks(w, False{}), None{})), u => why_not(check_x(ms, cs, mod, d), ranks(w, True{})))})
      v <> pures(t, mod, ms, cs, w)

def summaries(us: List<&2, Mod>, +ms: List<&2, Mod>, +cs: List<&2, Contract>, +w: List<&2, Summary>) -> String:
  match us:
    case Nil{}:
      ""
    case Mod{+mod, m} <> t:
      S.Module{+body} = m
      +im = S.choose(List<&2, Diag>, Bool.not(any_tag(body, ["Import", "ImportFrom"])), u => [], u =>
        [S.choose(Diag, List.is_empty(&2, Summary, about(w, mod)), u =>
          Diag{import_loc(body, ""), "imports", Unknown{}, mod_why(ms, mod, ranks(w, False{}), None{})}, u => imports(ms, cs, w, mod))])
      render(mod ++ ".py", List.sort(~Diag, ~le, List.append(&2, Diag, im, pures(def_names(body), mod, ms, cs, w)))) ++ summaries(t, ms, cs, w)

# `imports` per module that imports and `pure` per def, through the kernel;
# each module's diagnostics sorted, modules in manifest order.
def modules(+ms: List<&2, Mod>, +cs: List<&2, Contract>) -> String:
  +names = mod_names(ms)
  +n = List.length(&2, String, names)
  +w0 = summarize(n, False{}, names, ms, cs, [], 0n)
  +mr = ranks(w0, False{})
  +w = summarize(ndefs(names, ms), True{}, ranked(mr), ms, cs, List.append(&2, Summary, w0, paths(names, ms, mr, n)), 0n)
  summaries(ms, ms, cs, w)
