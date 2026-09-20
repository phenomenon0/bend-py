# The IR kernel: `emit` renders only what `verify` recomputes from the IR and
# the contracts. `honest` is the elaborator's own IR for normalize_stem; every
# other case forges one thing (a TypedIR is data, like a Lint certificate) and
# must be refused. `assumed` is the trust boundary on purpose: a contract that
# lies about purity is refused, but one that lies about meaning cannot be seen.
# T2: each new node (Let, Branch, Fold, Some, Maybe, Stop) has honest controls
# and forgeries of its position, types, binders and guard; Call is still refused.
# T3: List, Map (a comprehension) and the early-return fold likewise, and the
# regex and slice guards: re.S only, a compiling pattern, a group the parsed
# pattern must take, a positive `[:-k]`.
# T4: Call is emittable at last, and a module is a list of defs. What the
# kernel grants is a call to a def it has ALREADY accepted, at that def's own
# arity, argument types and result type -- so the forgeries are a call no
# prefix of the ranking can reach (unknown, cyclic, self), one that misstates
# the callee's shape, and a name a binder of the caller has taken.
import Base
import ../../demos/python/syntax.bend as S
import ../../demos/python/translate.bend as Tr

def at(a: Nat, b: Nat) -> S.Json:
  S.JArr{S.JItem{S.JNum{1n}, S.JItem{S.JNum{a}, S.JItem{S.JNum{1n}, S.JItem{S.JNum{b}, S.JEnd{}}}}}}

def s() -> Tr.Ir:
  Tr.IVar{"s", Tr.TStr{}, at(0n, 1n)}

def call(bend: String, args: Tr.Ir) -> Tr.Ir:
  Tr.IPrim{bend, args, Tr.TStr{}, at(0n, 9n)}

def one(x: Tr.Ir) -> Tr.Ir:
  Tr.IArg{x, Tr.IEnd{}}

def fn(name: String, ret: Tr.Ty, eff: Tr.Eff, body: Tr.Ir) -> Tr.Fn:
  Tr.Fn{name, [Tr.Param{"s", Tr.TStr{}, at(0n, 1n)}], ret, [], eff, body, at(0n, 9n)}

def ret(x: Tr.Ir) -> Tr.Fn:
  fn("f", Tr.TStr{}, Tr.Pure{}, Tr.IReturn{x, at(0n, 9n)})

def line(r: Result<&2, &2, S.Error, String>) -> String:
  match r:
    case Done{text}:
      "emitted"
    case Fail{e}:
      S.error_text(e)

def try(label: String, f: Tr.Fn) -> String:
  label ++ ": " ++ line(Tr.emit(f, Tr.contracts())) ++ "\n"

def lying() -> List<&2, Tr.Contract>:
  [Tr.Contract{Tr.TStr{}, "strip", [], Tr.TStr{}, "String.trim", False{}, True{}, "", ""}]

def ms() -> Tr.Ty:
  Tr.TMaybe{Tr.TStr{}}

def yes() -> Tr.Ir:
  Tr.ILit{"True", Tr.TBool{}, at(2n, 3n)}

def none() -> Tr.Ir:
  Tr.ILit{"None", ms(), at(2n, 3n)}

def m() -> Tr.Ir:
  Tr.IVar{"m", ms(), at(4n, 5n)}

def has(sep: String) -> Tr.Ir:
  Tr.IPrim{"String.contains", Tr.IArg{s(), one(Tr.ILit{sep, Tr.TStr{}, at(2n, 3n)})}, Tr.TBool{}, at(1n, 3n)}

def after(sep: String) -> Tr.Ir:
  Tr.IPrim{"Py.after", Tr.IArg{s(), one(Tr.ILit{sep, Tr.TStr{}, at(6n, 7n)})}, Tr.TStr{}, at(5n, 8n)}

def rs(x: Tr.Ir) -> Tr.Ir:
  Tr.IReturn{x, at(0n, 9n)}

# f(s: str, xs: list[str]) -> str
def tail(body: Tr.Ir) -> Tr.Fn:
  Tr.Fn{"f", [Tr.Param{"s", Tr.TStr{}, at(0n, 1n)}, Tr.Param{"xs", Tr.TList{Tr.TStr{}}, at(2n, 3n)}], Tr.TStr{}, [], Tr.Pure{}, body, at(0n, 9n)}

def fold(item: String, over: Tr.Ir, acc: String, step: Tr.Ir) -> Tr.Ir:
  rs(Tr.IFold{item, over, acc, s(), step, Tr.TStr{}, at(3n, 4n)})

def xs() -> Tr.Ir:
  Tr.IVar{"xs", Tr.TList{Tr.TStr{}}, at(2n, 3n)}

def x() -> Tr.Ir:
  Tr.IVar{"x", Tr.TStr{}, at(7n, 8n)}

def opt(on: String, none: Tr.Ir, some: Tr.Ir) -> Tr.Ir:
  Tr.ILet{"m", Tr.ISome{s(), ms(), at(1n, 2n)}, rs(Tr.IMaybe{on, none, some, Tr.TStr{}, at(3n, 4n)}), at(0n, 4n)}

# g(s: str) -> str, the callee every T4 case calls.
def g() -> Tr.Fn:
  Tr.Fn{"g", [Tr.Param{"s", Tr.TStr{}, at(0n, 1n)}], Tr.TStr{}, [], Tr.Pure{}, rs(s()), at(0n, 9n)}

def calls(name: String, args: Tr.Ir, t: Tr.Ty) -> Tr.Fn:
  ret(Tr.ICall{name, args, t, at(0n, 4n)})

def mod(label: String, fs: List<&2, Tr.Fn>) -> String:
  label ++ ": " ++ line(Tr.emit_all(fs, Tr.contracts())) ++ "\n"

def t4() -> String:
  mod("module", [g(), calls("g", one(s()), Tr.TStr{})]) ++
  mod("caller first", [calls("g", one(s()), Tr.TStr{}), g()]) ++
  mod("call arity", [g(), calls("g", Tr.IArg{s(), one(s())}, Tr.TStr{})]) ++
  mod("call unknown", [g(), calls("h", one(s()), Tr.TStr{})]) ++
  mod("call arg type", [g(), tail(rs(Tr.ICall{"g", one(xs()), Tr.TStr{}, at(0n, 4n)}))]) ++
  mod("call result type", [g(), calls("g", one(s()), Tr.TBool{})]) ++
  mod("call self", [calls("f", one(s()), Tr.TStr{})]) ++
  mod("call cycle", [calls("g", one(s()), Tr.TStr{}),
    Tr.Fn{"g", [Tr.Param{"s", Tr.TStr{}, at(0n, 1n)}], Tr.TStr{}, [], Tr.Pure{}, rs(Tr.ICall{"f", one(s()), Tr.TStr{}, at(0n, 4n)}), at(0n, 9n)}]) ++
  mod("call shadowed", [g(), Tr.Fn{"f", [Tr.Param{"g", Tr.TStr{}, at(0n, 1n)}], Tr.TStr{}, [], Tr.Pure{},
    rs(Tr.ICall{"g", one(Tr.IVar{"g", Tr.TStr{}, at(0n, 1n)}), Tr.TStr{}, at(0n, 4n)}), at(0n, 9n)}]) ++
  mod("two defs", [g(), g()]) ++
  mod("call impure", [g(), fn("f", Tr.TStr{}, Tr.Impure{}, Tr.IReturn{Tr.ICall{"g", one(s()), Tr.TStr{}, at(0n, 4n)}, at(0n, 9n)})])

def t2() -> String:
  try("let", tail(Tr.ILet{"x", s(), rs(x()), at(0n, 4n)})) ++
  try("let in argument", ret(call("String.trim", one(Tr.ILet{"x", s(), s(), at(0n, 4n)})))) ++
  try("let retyped", tail(Tr.ILet{"s", yes(), rs(s()), at(0n, 4n)})) ++
  try("let name", tail(Tr.ILet{"_c", s(), rs(s()), at(0n, 4n)})) ++
  try("let scope", tail(Tr.ILet{"x", x(), rs(s()), at(0n, 4n)})) ++
  try("return in argument", ret(call("String.trim", one(rs(s()))))) ++
  try("branch", tail(Tr.IBranch{has("."), rs(s()), rs(s()), Tr.TStr{}, at(0n, 4n)})) ++
  try("branch test", tail(Tr.IBranch{s(), rs(s()), rs(s()), Tr.TStr{}, at(0n, 4n)})) ++
  try("branch arm type", tail(Tr.IBranch{has("."), rs(s()), rs(yes()), Tr.TStr{}, at(0n, 4n)})) ++
  try("branch falls", tail(Tr.IBranch{has("."), rs(s()), s(), Tr.TStr{}, at(0n, 4n)})) ++
  try("helper names", ret(Tr.IBranch{has("."), Tr.IBranch{has("."), s(), s(), Tr.TStr{}, at(0n, 4n)}, s(), Tr.TStr{}, at(0n, 4n)})) ++
  try("guarded", tail(Tr.IBranch{has("."), rs(after(".")), rs(s()), Tr.TStr{}, at(0n, 4n)})) ++
  try("guard wrong arm", tail(Tr.IBranch{has("."), rs(s()), rs(after(".")), Tr.TStr{}, at(0n, 4n)})) ++
  try("guard absent", ret(after("."))) ++
  try("guard other sep", tail(Tr.IBranch{has("."), rs(after("-")), rs(s()), Tr.TStr{}, at(0n, 4n)})) ++
  try("guard empty sep", tail(Tr.IBranch{has(""), rs(after("")), rs(s()), Tr.TStr{}, at(0n, 4n)})) ++
  try("guard rebound", tail(Tr.IBranch{has("."), Tr.ILet{"s", call("String.trim", one(s())), rs(after(".")), at(0n, 4n)}, rs(s()), Tr.TStr{}, at(0n, 4n)})) ++
  try("fold", tail(fold("x", xs(), "acc", x()))) ++
  try("fold stop", tail(fold("x", xs(), "acc", Tr.IStop{x(), at(5n, 6n)}))) ++
  try("fold over", tail(fold("x", s(), "acc", x()))) ++
  try("fold item is acc", tail(fold("x", xs(), "x", x()))) ++
  try("fold step type", tail(fold("x", xs(), "acc", yes()))) ++
  try("fold step returns", tail(fold("x", xs(), "acc", rs(x())))) ++
  try("fold step rebinds capture", tail(fold("x", xs(), "acc", Tr.ILet{"s", x(), x(), at(5n, 6n)}))) ++
  try("stop outside", tail(Tr.IStop{s(), at(0n, 4n)})) ++
  try("stop type", tail(fold("x", xs(), "acc", Tr.IStop{yes(), at(5n, 6n)}))) ++
  try("maybe", tail(opt("m", s(), Tr.IVar{"m", Tr.TStr{}, at(4n, 5n)}))) ++
  try("maybe on str", tail(opt("s", s(), s()))) ++
  try("maybe none reads", tail(opt("m", Tr.IPrim{"String.trim", one(m()), Tr.TStr{}, at(5n, 6n)}, s()))) ++
  try("maybe unnarrowed", tail(opt("m", s(), m()))) ++
  try("maybe arm type", tail(opt("m", s(), yes()))) ++
  try("some type", tail(Tr.ILet{"m", Tr.ISome{yes(), ms(), at(1n, 2n)}, rs(s()), at(0n, 4n)})) ++
  try("none at bool", tail(Tr.IBranch{Tr.ILit{"None", Tr.TBool{}, at(0n, 1n)}, rs(s()), rs(s()), Tr.TStr{}, at(0n, 4n)})) ++
  try("bool literal", tail(Tr.IBranch{Tr.ILit{"Maybe", Tr.TBool{}, at(0n, 1n)}, rs(s()), rs(s()), Tr.TStr{}, at(0n, 4n)}))

def ls() -> Tr.Ty:
  Tr.TList{Tr.TStr{}}

def lit(text: String, t: Tr.Ty) -> Tr.Ir:
  Tr.ILit{text, t, at(2n, 3n)}

# f(s: str, xs: list[str]) -> list[str]
def lf(body: Tr.Ir) -> Tr.Fn:
  Tr.Fn{"f", [Tr.Param{"s", Tr.TStr{}, at(0n, 1n)}, Tr.Param{"xs", ls(), at(2n, 3n)}], ls(), [], Tr.Pure{}, body, at(0n, 9n)}

def list(items: Tr.Ir) -> Tr.Ir:
  Tr.IList{items, ls(), at(1n, 2n)}

def comp(item: String, over: Tr.Ir, body: Tr.Ir) -> Tr.Ir:
  Tr.IMap{item, over, body, ls(), at(3n, 4n)}

def search(p: String, flags: Tr.Ir) -> Tr.Ir:
  Tr.IPrim{"Py.search", Tr.IArg{s(), Tr.IArg{lit(p, Tr.TStr{}), one(flags)}}, Tr.TMaybe{Tr.TMatch{}}, at(1n, 2n)}

def group(k: String) -> Tr.Ir:
  Tr.IPrim{"Py.group", Tr.IArg{Tr.IVar{"m", Tr.TMatch{}, at(4n, 5n)}, one(lit(k, Tr.TInt{}))}, Tr.TStr{}, at(5n, 6n)}

# m = re.search(p, s, re.S); if not m: return []; <some>
def matched(m: Tr.Ir, some: Tr.Ir) -> Tr.Fn:
  lf(Tr.ILet{"m", m, Tr.IMaybe{"m", rs(list(Tr.IEnd{})), some, ls(), at(3n, 4n)}, at(0n, 4n)})

def rl(x: Tr.Ir) -> Tr.Ir:
  rs(list(one(x)))

def slice(bend: String, k: Tr.Ir) -> Tr.Fn:
  ret(Tr.IPrim{bend, Tr.IArg{s(), one(k)}, Tr.TStr{}, at(1n, 2n)})

# The early return: a fold of Maybe that stops at Some{v}, then a match on it.
def early(step: Tr.Ir, some: Tr.Ir) -> Tr.Fn:
  +r = {Tr.TMaybe{ls()} : Tr.Ty}
  lf(Tr.ILet{"ret", Tr.IFold{"x", xs(), "ret", Tr.ILit{"None", r, at(2n, 3n)}, step, r, at(3n, 4n)},
    Tr.IMaybe{"ret", rs(list(Tr.IEnd{})), some, ls(), at(3n, 5n)}, at(0n, 4n)})

def stop() -> Tr.Ir:
  Tr.IStop{Tr.ISome{list(one(x())), Tr.TMaybe{ls()}, at(6n, 7n)}, at(5n, 6n)}

def t3() -> String:
  try("list", lf(rs(list(Tr.IArg{s(), one(call("String.trim", one(s())))})))) ++
  try("list empty", lf(rs(list(Tr.IEnd{})))) ++
  try("list mixed", lf(rs(list(Tr.IArg{s(), one(yes())})))) ++
  try("list of a non-list type", lf(rs(Tr.IList{one(s()), Tr.TStr{}, at(1n, 2n)}))) ++
  try("list returns", lf(rs(list(one(rs(s())))))) ++
  try("comp", lf(rs(comp("x", xs(), call("String.trim", one(x())))))) ++
  try("comp over str", lf(rs(comp("x", s(), x())))) ++
  try("comp type", lf(rs(Tr.IMap{"x", xs(), yes(), ls(), at(3n, 4n)}))) ++
  try("comp item name", lf(rs(comp("_c", xs(), s())))) ++
  try("comp item unbound", lf(rs(comp("x", xs(), Tr.IVar{"y", Tr.TStr{}, at(7n, 8n)})))) ++
  try("comp body returns", lf(rs(comp("x", xs(), rs(x()))))) ++
  try("comp body stops", lf(rs(comp("x", xs(), Tr.IStop{x(), at(5n, 6n)})))) ++
  try("comp body lets", lf(rs(comp("x", xs(), Tr.ILet{"y", x(), x(), at(5n, 6n)})))) ++
  try("comp drops facts", lf(Tr.IBranch{has("."), rs(comp("x", xs(), after("."))), rs(xs()), ls(), at(0n, 4n)})) ++
  try("group", matched(search("^a(b)", lit("s", Tr.TStr{})), rl(group("1")))) ++
  try("group absent", matched(search("^a(b)", lit("s", Tr.TStr{})), rl(group("2")))) ++
  try("group zero", matched(search("^a(b)", lit("s", Tr.TStr{})), rl(group("0")))) ++
  try("group optional", matched(search("^a(b)?", lit("s", Tr.TStr{})), rl(group("1")))) ++
  try("group one side", matched(search("(a)|b", lit("s", Tr.TStr{})), rl(group("1")))) ++
  try("group after let", matched(search("^a(b)", lit("s", Tr.TStr{})), Tr.ILet{"y", s(), rl(group("1")), at(4n, 6n)})) ++
  try("group without search", lf(Tr.ILet{"m", Tr.ISome{Tr.ILit{"s", Tr.TStr{}, at(1n, 2n)}, Tr.TMaybe{Tr.TStr{}}, at(1n, 2n)},
    rs(Tr.IMaybe{"m", list(Tr.IEnd{}), list(one(group("1"))), ls(), at(3n, 4n)}), at(0n, 4n)})) ++
  try("fact as call", ret(Tr.IPrim{"Py.took", Tr.IArg{s(), one(lit("(a)", Tr.TStr{}))}, Tr.TBool{}, at(1n, 2n)})) ++
  try("search bad pattern", matched(search("^a(b", lit("s", Tr.TStr{})), rl(group("1")))) ++
  try("search other flag", matched(search("^a(b)", lit("m", Tr.TStr{})), rl(group("1")))) ++
  try("search flag name", matched(search("^a(b)", s()), rl(group("1")))) ++
  try("search pattern name", matched(Tr.IPrim{"Py.search", Tr.IArg{s(), Tr.IArg{s(), one(lit("s", Tr.TStr{}))}}, Tr.TMaybe{Tr.TMatch{}}, at(1n, 2n)},
    rl(group("1")))) ++
  try("drop", slice("String.drop", lit("1", Tr.TInt{}))) ++
  try("drop end", slice("String.drop_end", lit("1", Tr.TInt{}))) ++
  try("drop end zero", slice("String.drop_end", lit("0", Tr.TInt{}))) ++
  try("drop end leading zero", slice("String.drop_end", lit("01", Tr.TInt{}))) ++
  try("drop end name", slice("String.drop_end", call("String.length", one(s())))) ++
  try("split sep name", lf(rs(Tr.IPrim{"String.split_on", Tr.IArg{s(), one(s())}, ls(), at(1n, 2n)}))) ++
  try("split sep empty", lf(rs(Tr.IPrim{"String.split_on", Tr.IArg{s(), one(lit("", Tr.TStr{}))}, ls(), at(1n, 2n)}))) ++
  try("early return", early(stop(), rs(Tr.IVar{"ret", ls(), at(4n, 5n)}))) ++
  try("early return none reads", lf(Tr.ILet{"ret", Tr.IFold{"x", xs(), "ret", Tr.ILit{"None", Tr.TMaybe{ls()}, at(2n, 3n)}, stop(), Tr.TMaybe{ls()}, at(3n, 4n)},
    Tr.IMaybe{"ret", rs(Tr.IVar{"ret", ls(), at(4n, 5n)}), rs(list(Tr.IEnd{})), ls(), at(3n, 5n)}, at(0n, 4n)})) ++
  try("early return unwrapped", early(Tr.IStop{list(one(x())), at(5n, 6n)}, rs(Tr.IVar{"ret", ls(), at(4n, 5n)}))) ++
  try("early return some type", early(Tr.IStop{Tr.ISome{x(), Tr.TMaybe{ls()}, at(6n, 7n)}, at(5n, 6n)}, rs(Tr.IVar{"ret", ls(), at(4n, 5n)}))) ++
  try("early return outside", lf(stop()))

# T5: the postcondition slot. `post` on a Fn is a CLAIM -- a TypedIR is data,
# so it can over-claim -- and the kernel recomputes from the body what the
# claim is checked against: PHas when every path of a str body prepends the
# literal, PEach when a comprehension prepends it to every item. The reader is
# granted its guarded split by the callee's claim and by nothing else, so the
# unclaimed row is the same two bodies with the slot emptied, and refused.
def app(k: String, v: Tr.Ir) -> Tr.Ir:
  Tr.IPrim{"String.append", Tr.IArg{lit(k, Tr.TStr{}), one(v)}, Tr.TStr{}, at(1n, 3n)}

# g(s: str) -> str
def keyed(post: List<&2, Tr.Post>, body: Tr.Ir) -> Tr.Fn:
  Tr.Fn{"g", [Tr.Param{"s", Tr.TStr{}, at(0n, 1n)}], Tr.TStr{}, post, Tr.Pure{}, body, at(0n, 9n)}

# g(s: str) -> list[str]
def each_keyed(post: List<&2, Tr.Post>, body: Tr.Ir) -> Tr.Fn:
  Tr.Fn{"g", [Tr.Param{"s", Tr.TStr{}, at(0n, 1n)}], ls(), post, Tr.Pure{}, body, at(0n, 9n)}

# f(s: str) -> str = { v = g(s); return Py.after(v, sep) }
def reader(sep: String) -> Tr.Fn:
  Tr.Fn{"f", [Tr.Param{"s", Tr.TStr{}, at(0n, 1n)}], Tr.TStr{}, [], Tr.Pure{},
    Tr.ILet{"v", Tr.ICall{"g", one(s()), Tr.TStr{}, at(0n, 4n)},
      rs(Tr.IPrim{"Py.after", Tr.IArg{Tr.IVar{"v", Tr.TStr{}, at(5n, 6n)}, one(lit(sep, Tr.TStr{}))}, Tr.TStr{}, at(5n, 8n)}),
      at(0n, 4n)}, at(0n, 9n)}

# f(s: str) -> list[str] = { v = g(s); return [Py.after(x, ":") for x in v] }
def each_reader() -> Tr.Fn:
  Tr.Fn{"f", [Tr.Param{"s", Tr.TStr{}, at(0n, 1n)}], ls(), [], Tr.Pure{},
    Tr.ILet{"v", Tr.ICall{"g", one(s()), ls(), at(0n, 4n)},
      rs(comp("x", Tr.IVar{"v", ls(), at(5n, 6n)},
        Tr.IPrim{"Py.after", Tr.IArg{x(), one(lit(":", Tr.TStr{}))}, Tr.TStr{}, at(5n, 8n)})),
      at(0n, 4n)}, at(0n, 9n)}

def kv() -> Tr.Ir:
  Tr.IPrim{"String.split_on", Tr.IArg{s(), one(lit(",", Tr.TStr{}))}, ls(), at(1n, 2n)}

def z() -> Tr.Ir:
  Tr.ILit{"z", Tr.TStr{}, at(2n, 3n)}

def t5() -> String:
  mod("post granted", [keyed([Tr.PHas{"k:"}], rs(app("k:", s()))), reader(":")]) ++
  mod("post unclaimed", [keyed([], rs(app("k:", s()))), reader(":")]) ++
  mod("post forged", [keyed([Tr.PHas{"k:"}], rs(s())), reader(":")]) ++
  mod("post forged substring", [keyed([Tr.PHas{"k"}], rs(app("k:", s()))), reader(":")]) ++
  mod("post both arms", [keyed([Tr.PHas{"k:"}],
    Tr.IBranch{has("."), rs(app("k:", s())), rs(app("k:", z())), Tr.TStr{}, at(0n, 4n)}), reader(":")]) ++
  mod("post one arm", [keyed([Tr.PHas{"k:"}],
    Tr.IBranch{has("."), rs(app("k:", s())), rs(s()), Tr.TStr{}, at(0n, 4n)}), reader(":")]) ++
  mod("post other sep", [keyed([Tr.PHas{"k:"}], rs(app("k:", s()))), reader("-")]) ++
  mod("post each granted", [each_keyed([Tr.PEach{"k:"}], rs(comp("x", kv(), app("k:", x())))), each_reader()]) ++
  mod("post each forged", [each_keyed([Tr.PEach{"k:"}], rs(comp("x", kv(), x()))), each_reader()]) ++
  mod("post each as has", [each_keyed([Tr.PHas{"k:"}], rs(comp("x", kv(), app("k:", x())))), each_reader()]) ++
  mod("post has as each", [keyed([Tr.PEach{"k:"}], rs(app("k:", s()))), reader(":")]) ++
  try("post fact as call", ret(Tr.IPrim{"Py.every", Tr.IArg{s(), one(lit("k:", Tr.TStr{}))}, Tr.TBool{}, at(1n, 2n)}))

def main() -> String:
  try("honest", ret(call("String.replace", Tr.IArg{call("String.to_lower", one(call("String.trim", one(s())))),
    Tr.IArg{Tr.ILit{" ", Tr.TStr{}, at(2n, 5n)}, one(Tr.ILit{"-", Tr.TStr{}, at(6n, 9n)})}}))) ++
  try("unknown prim", ret(call("String.reverse", one(s())))) ++
  try("arity", ret(call("String.replace", one(s())))) ++
  try("arg type", ret(call("String.trim", one(Tr.IVar{"s", Tr.TBool{}, at(0n, 1n)})))) ++
  try("result type", ret(Tr.IPrim{"String.trim", one(s()), Tr.TBool{}, at(0n, 9n)})) ++
  try("unbound", ret(Tr.IVar{"t", Tr.TStr{}, at(0n, 1n)})) ++
  try("literal", ret(Tr.ILit{"a\nb", Tr.TStr{}, at(0n, 1n)})) ++
  try("no span", ret(Tr.IVar{"s", Tr.TStr{}, S.JNull{}})) ++
  try("call", ret(Tr.ICall{"g", one(s()), Tr.TStr{}, at(0n, 4n)})) ++
  try("no return", fn("f", Tr.TStr{}, Tr.Pure{}, s())) ++
  try("return type", fn("f", Tr.TBool{}, Tr.Pure{}, Tr.IReturn{s(), at(0n, 9n)})) ++
  try("effect", fn("f", Tr.TStr{}, Tr.Impure{}, Tr.IReturn{s(), at(0n, 9n)})) ++
  try("identifier", fn("F-x", Tr.TStr{}, Tr.Pure{}, Tr.IReturn{s(), at(0n, 9n)})) ++
  "assumed: " ++ line(Tr.emit(ret(call("String.trim", one(s()))), lying())) ++ "\n" ++
  t2() ++
  t3() ++
  t4() ++
  t5()
#|"honest: emitted\nunknown prim: error Unsupported 1 0 primitive String.reverse is not granted by a contract (or its guard is not known here) at 1:0\narity: error Unsupported 1 0 primitive String.replace is not granted by a contract (or its guard is not known here) at 1:0\narg type: error Unsupported 1 0 primitive String.trim is not granted by a contract (or its guard is not known here) at 1:0\nresult type: error Unsupported 1 0 primitive String.trim is not granted by a contract (or its guard is not known here) at 1:0\nunbound: error Unsupported 1 0 unbound or mistyped name t at 1:0\nliteral: error Unsupported 1 0 literal outside the contract at 1:0\nno span: error Unsupported 1 0 unbound or mistyped name s at 0:0\ncall: error Unsupported 1 0 call g(String;) -> String is granted by no def ranked below this one at 1:0\nno return: error Unsupported 1 0 body does not return String at 1:0\nreturn type: error Unsupported 1 0 body does not return Bool at 1:0\neffect: error Unsupported 1 0 effect is not Pure at 1:0\nidentifier: error Unsupported 1 0 name or span not emittable at 1:0\nassumed: error Unsupported 1 0 primitive String.trim is not granted by a contract (or its guard is not known here) at 1:0\nlet: emitted\nlet in argument: error Unsupported 1 0 let of x: in argument position, retyped, or rebinding a captured name inside a fold step at 1:0\nlet retyped: error Unsupported 1 0 let of s: in argument position, retyped, or rebinding a captured name inside a fold step at 1:0\nlet name: error Unsupported 1 0 let of _c: in argument position, retyped, or rebinding a captured name inside a fold step at 1:0\nlet scope: error Unsupported 1 0 unbound or mistyped name x at 1:7\nreturn in argument: error Unsupported 1 0 return outside tail position at 1:0\nbranch: emitted\nbranch test: error Unsupported 1 0 branch on a non-Bool test, or arms of another type at 1:0\nbranch arm type: error Unsupported 1 0 branch on a non-Bool test, or arms of another type at 1:0\nbranch falls: error Unsupported 1 0 body does not return String at 1:0\nhelper names: error Unsupported 1 0 two helper defs share a name at 1:0\nguarded: emitted\nguard wrong arm: error Unsupported 1 0 primitive Py.after is not granted by a contract (or its guard is not known here) at 1:5\nguard absent: error Unsupported 1 0 primitive Py.after is not granted by a contract (or its guard is not known here) at 1:5\nguard other sep: error Unsupported 1 0 primitive Py.after is not granted by a contract (or its guard is not known here) at 1:5\nguard empty sep: error Unsupported 1 0 primitive Py.after is not granted by a contract (or its guard is not known here) at 1:5\nguard rebound: error Unsupported 1 0 primitive Py.after is not granted by a contract (or its guard is not known here) at 1:5\nfold: emitted\nfold stop: emitted\nfold over: error Unsupported 1 0 fold over a non-list, item = accumulator, or a step of another type at 1:3\nfold item is acc: error Unsupported 1 0 fold over a non-list, item = accumulator, or a step of another type at 1:3\nfold step type: error Unsupported 1 0 fold over a non-list, item = accumulator, or a step of another type at 1:3\nfold step returns: error Unsupported 1 0 return outside tail position at 1:0\nfold step rebinds capture: error Unsupported 1 0 let of s: in argument position, retyped, or rebinding a captured name inside a fold step at 1:5\nstop outside: error Unsupported 1 0 break outside a fold step, or not of the accumulator's type at 1:0\nstop type: error Unsupported 1 0 fold over a non-list, item = accumulator, or a step of another type at 1:3\nmaybe: emitted\nmaybe on str: error Unsupported 1 0 Optional match on a name that is not Optional, a None arm that reads it, or arms of another type at 1:3\nmaybe none reads: error Unsupported 1 0 Optional match on a name that is not Optional, a None arm that reads it, or arms of another type at 1:3\nmaybe unnarrowed: error Unsupported 1 0 Optional match on a name that is not Optional, a None arm that reads it, or arms of another type at 1:3\nmaybe arm type: error Unsupported 1 0 Optional match on a name that is not Optional, a None arm that reads it, or arms of another type at 1:3\nsome type: error Unsupported 1 0 Some of a mistyped value at 1:1\nnone at bool: error Unsupported 1 0 literal outside the contract at 1:0\nbool literal: error Unsupported 1 0 literal outside the contract at 1:0\nlist: emitted\nlist empty: emitted\nlist mixed: error Unsupported 1 0 list of items not all of its element type at 1:1\nlist of a non-list type: error Unsupported 1 0 list of items not all of its element type at 1:1\nlist returns: error Unsupported 1 0 return outside tail position at 1:0\ncomp: emitted\ncomp over str: error Unsupported 1 0 comprehension over a non-list, or of another type at 1:3\ncomp type: error Unsupported 1 0 comprehension over a non-list, or of another type at 1:3\ncomp item name: error Unsupported 1 0 comprehension over a non-list, or of another type at 1:3\ncomp item unbound: error Unsupported 1 0 unbound or mistyped name y at 1:7\ncomp body returns: error Unsupported 1 0 return outside tail position at 1:0\ncomp body stops: error Unsupported 1 0 break outside a fold step, or not of the accumulator's type at 1:5\ncomp body lets: error Unsupported 1 0 let of y: in argument position, retyped, or rebinding a captured name inside a fold step at 1:5\ncomp drops facts: error Unsupported 1 0 primitive Py.after is not granted by a contract (or its guard is not known here) at 1:5\ngroup: emitted\ngroup absent: error Unsupported 1 0 primitive Py.group is not granted by a contract (or its guard is not known here) at 1:5\ngroup zero: error Unsupported 1 0 primitive Py.group is not granted by a contract (or its guard is not known here) at 1:5\ngroup optional: error Unsupported 1 0 primitive Py.group is not granted by a contract (or its guard is not known here) at 1:5\ngroup one side: error Unsupported 1 0 primitive Py.group is not granted by a contract (or its guard is not known here) at 1:5\ngroup after let: error Unsupported 1 0 primitive Py.group is not granted by a contract (or its guard is not known here) at 1:5\ngroup without search: error Unsupported 1 0 primitive Py.group is not granted by a contract (or its guard is not known here) at 1:5\nfact as call: error Unsupported 1 0 primitive Py.took is not granted by a contract (or its guard is not known here) at 1:1\nsearch bad pattern: error Unsupported 1 0 primitive Py.search is not granted by a contract (or its guard is not known here) at 1:1\nsearch other flag: error Unsupported 1 0 primitive Py.search is not granted by a contract (or its guard is not known here) at 1:1\nsearch flag name: error Unsupported 1 0 primitive Py.search is not granted by a contract (or its guard is not known here) at 1:1\nsearch pattern name: error Unsupported 1 0 primitive Py.search is not granted by a contract (or its guard is not known here) at 1:1\ndrop: emitted\ndrop end: emitted\ndrop end zero: error Unsupported 1 0 primitive String.drop_end is not granted by a contract (or its guard is not known here) at 1:1\ndrop end leading zero: error Unsupported 1 0 literal outside the contract at 1:2\ndrop end name: error Unsupported 1 0 primitive String.drop_end is not granted by a contract (or its guard is not known here) at 1:1\nsplit sep name: error Unsupported 1 0 primitive String.split_on is not granted by a contract (or its guard is not known here) at 1:1\nsplit sep empty: error Unsupported 1 0 primitive String.split_on is not granted by a contract (or its guard is not known here) at 1:1\nearly return: emitted\nearly return none reads: error Unsupported 1 0 Optional match on a name that is not Optional, a None arm that reads it, or arms of another type at 1:3\nearly return unwrapped: error Unsupported 1 0 fold over a non-list, item = accumulator, or a step of another type at 1:3\nearly return some type: error Unsupported 1 0 Some of a mistyped value at 1:6\nearly return outside: error Unsupported 1 0 break outside a fold step, or not of the accumulator's type at 1:5\nmodule: emitted\ncaller first: emitted\ncall arity: error Unsupported 1 0 call g(String;String;) -> String is granted by no def ranked below this one at 1:0\ncall unknown: error Unsupported 1 0 call h(String;) -> String is granted by no def ranked below this one at 1:0\ncall arg type: error Unsupported 1 0 call g(List<&2, String>;) -> String is granted by no def ranked below this one at 1:0\ncall result type: error Unsupported 1 0 call g(String;) -> Bool is granted by no def ranked below this one at 1:0\ncall self: error Unsupported 1 0 call f(String;) -> String is granted by no def ranked below this one at 1:0\ncall cycle: error Unsupported 1 0 call g(String;) -> String is granted by no def ranked below this one at 1:0\ncall shadowed: error Unsupported 1 0 call g(String;) -> String is granted by no def ranked below this one at 1:0\ntwo defs: error Unsupported 1 0 two defs of the module are named g at 1:0\ncall impure: error Unsupported 1 0 effect is not Pure at 1:0\npost granted: emitted\npost unclaimed: error Unsupported 1 0 primitive Py.after is not granted by a contract (or its guard is not known here) at 1:5\npost forged: error Unsupported 1 0 the postcondition that the result contains k: is not established by this body: drop the claim, or make every path carry it at 1:0\npost forged substring: error Unsupported 1 0 the postcondition that the result contains k is not established by this body: drop the claim, or make every path carry it at 1:0\npost both arms: emitted\npost one arm: error Unsupported 1 0 the postcondition that the result contains k: is not established by this body: drop the claim, or make every path carry it at 1:0\npost other sep: error Unsupported 1 0 primitive Py.after is not granted by a contract (or its guard is not known here) at 1:5\npost each granted: emitted\npost each forged: error Unsupported 1 0 the postcondition that every item of the result contains k: is not established by this body: drop the claim, or make every path carry it at 1:0\npost each as has: error Unsupported 1 0 the postcondition that the result contains k: is not established by this body: drop the claim, or make every path carry it at 1:0\npost has as each: error Unsupported 1 0 the postcondition that every item of the result contains k: is not established by this body: drop the claim, or make every path carry it at 1:0\npost fact as call: error Unsupported 1 0 primitive Py.every is not granted by a contract (or its guard is not known here) at 1:1\n"
