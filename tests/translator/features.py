"""What-if census: which features would make how much of a Python tree translatable.

  python3 tests/translator/features.py [TREE] [--methods] [--top 25] [--json OUT]

census.py runs the translator and counts each def by its FIRST refusal, so it
can say what blocks a def but not what would unblock it: a def refused for a
`try` may also hold a dict, a while and an isinstance. This tool reads each
distinct def's AST once, statically, and records EVERY feature it uses that the
fragment lacks. A def is unlocked by a feature set F when all its missing
features are in F. That turns "what next" into a measurement:

  - alone:  defs whose only missing feature is X (X unlocks them by itself);
  - greedy: the order of features that unlocks the most defs at each step,
            with the cumulative count, i.e. the payoff curve of the roadmap;
  - plan:   cumulative unlocks for the named tiers of the plan
            (translator-census.md): generic types, records and sums.

It is an estimate, not a certification: a syntactic feature is a proxy for a
kernel rule, types of unannotated code are read off syntax (an int literal in
arithmetic means int), and a def unlocked here must still translate and pass
C1+C2. The number it ranks is the same one census.py measures, so the two are
compared on the same tree. `--methods` also counts defs inside classes (census
counts top-level defs only); a method's `self.x` is the `record` feature.
"""

import argparse
import ast
import json
import os
import sys
import sysconfig
from collections import Counter

# What the fragment translates today (translate.bend at HEAD, tier 0 included:
# plain f-strings, keyword calls to module defs, capital locals). Anything a
# def uses outside this is a missing feature, named by `miss`.
STR_METHODS = {"startswith", "endswith", "strip", "lstrip", "rstrip", "lower", "upper",
               "split", "splitlines", "replace", "find", "join", "__bool__", "partition"}
BUILTINS = {"len", "str", "bool"}
BUILTINS_ALL = set(dir(__builtins__)) if isinstance(__builtins__, dict) is False else set(__builtins__)

# The plan's tiers (translator-census.md, "how to get close"), as feature sets.
PLAN = [
    ("0 cheap syntax", {"uppercase-name", "fstring", "kwargs-call"}),
    ("1 int + tuples", {"int", "int-builtins", "tuple", "multi-accumulator", "return-in-loop"}),
    ("2 library surface", {"str-methods-more", "list-methods", "iter-builtins", "subscript", "slice"}),
    ("3 records", {"record", "class-body"}),
    ("4 dict/set/while", {"dict", "set", "while"}),
    ("5 sums + exceptions", {"isinstance", "raise", "try", "assert"}),
    ("6 other-module contracts", {"module-call"}),
]


def miss(fn):
    """The set of features `fn` uses that the fragment lacks."""
    m = set()
    a = fn.args
    if a.vararg or a.kwarg:
        m.add("varargs")
    if a.kwonlyargs or a.posonlyargs:
        m.add("kwonly")
    if fn.decorator_list:
        m.add("decorator")
    for d in a.defaults + [d for d in a.kw_defaults if d is not None]:
        if not isinstance(d, ast.Constant):
            m.add("default-nonliteral")
    params = {x.arg for x in a.args}
    # locals: a method call on any name the def binds is a call on a value,
    # not on another module (`line.split`, `m.group`)
    params |= {x.arg for x in a.kwonlyargs + a.posonlyargs + [a.vararg, a.kwarg] if x}
    bound = params | {n.id for n in ast.walk(fn) if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Store)}
    bound |= {x.arg for n in ast.walk(fn) if isinstance(n, ast.Lambda) for x in n.args.args}
    for ann in [x.annotation for x in a.args] + [fn.returns]:
        if ann is not None:
            m |= ann_miss(ann)
    for n in ast.walk(fn):
        if n is fn:
            continue
        m |= node_miss(n, bound)
    return m


def ann_miss(t):
    s = ast.unparse(t)
    out = set()
    if "int" in s:
        out.add("int")
    if "float" in s or "complex" in s:
        out.add("float")
    if "tuple" in s.lower():
        out.add("tuple")
    if "dict" in s.lower() or "Mapping" in s:
        out.add("dict")
    if "set" in s.lower():
        out.add("set")
    if "bytes" in s:
        out.add("bytes")
    if any(k in s for k in ("Callable", "Iterator", "Iterable", "Any", "object", "Type")):
        out.add("dynamic-type")
    return out


def node_miss(n, params):
    m = set()
    t = type(n)
    if t in (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda):
        m.add("closure")
    elif t is ast.ClassDef:
        m.add("class-body")
    elif t is ast.While:
        m.add("while")
    elif t in (ast.Try, getattr(ast, "TryStar", ast.Try)):
        m.add("try")
    elif t is ast.Raise:
        m.add("raise")
    elif t is ast.Assert:
        m.add("assert")
    elif t in (ast.With, ast.AsyncWith):
        m.add("with")
    elif t in (ast.Global, ast.Nonlocal):
        m.add("global")
    elif t in (ast.Import, ast.ImportFrom):
        m.add("import")
    elif t is ast.Delete:
        m.add("del")
    elif t in (ast.Yield, ast.YieldFrom, ast.Await):
        m.add("generator")
    elif t in (ast.Dict, ast.DictComp):
        m.add("dict")
    elif t in (ast.Set, ast.SetComp):
        m.add("set")
    elif t is ast.GeneratorExp:
        m.add("generator")
    elif t is ast.Tuple:
        m.add("tuple")
    elif t is ast.Starred:
        m.add("varargs")
    elif t is ast.FormattedValue:
        if n.conversion != -1 or n.format_spec is not None:
            m.add("fstring")
    elif t is ast.Constant:
        if isinstance(n.value, float) or isinstance(n.value, complex):
            m.add("float")
        elif isinstance(n.value, bytes):
            m.add("bytes")
        elif isinstance(n.value, int) and not isinstance(n.value, bool) and n.value < 0:
            m.add("int")
    elif t is ast.UnaryOp and isinstance(n.op, ast.USub):
        m.add("int")
    elif t is ast.BinOp:
        if not isinstance(n.op, ast.Add):
            m.add("int")
        if isinstance(n.op, ast.Mod) and isinstance(n.left, (ast.Constant, ast.JoinedStr)) and isinstance(getattr(n.left, "value", None), str):
            m.add("fstring")
    elif t is ast.AugAssign:
        if not isinstance(n.op, ast.Add):
            m.add("int")
        if not isinstance(n.target, ast.Name):
            m.add("mutation")
    elif t is ast.Subscript:
        m.add("slice" if isinstance(n.slice, ast.Slice) else "subscript")
    elif t is ast.Assign:
        for tg in n.targets:
            if isinstance(tg, (ast.Tuple, ast.List)):
                m.add("tuple")
            elif isinstance(tg, ast.Attribute):
                m.add("record" if isinstance(tg.value, ast.Name) and tg.value.id == "self" else "mutation")
            elif isinstance(tg, ast.Subscript):
                m.add("mutation")
        if len(n.targets) > 1:
            m.add("chained-assign")
    elif t is ast.Attribute:
        if isinstance(n.value, ast.Name) and n.value.id == "self":
            m.add("record")
    elif t is ast.Call:
        m |= call_miss(n, params)
    elif t is ast.For:
        if isinstance(n.target, (ast.Tuple, ast.List)):
            m.add("tuple")
        if n.orelse:
            m.add("for-else")
        if any(isinstance(x, ast.Return) for x in ast.walk(n)):
            m.add("return-in-loop")
        assigned = {x.id for s in n.body for x in ast.walk(s)
                    if isinstance(x, ast.Name) and isinstance(x.ctx, ast.Store)} - {getattr(n.target, "id", None)}
        if len(assigned) > 1:
            m.add("multi-accumulator")
    elif t is ast.Compare:
        for op in n.ops:
            if isinstance(op, (ast.Is, ast.IsNot)):
                continue
            if isinstance(op, (ast.In, ast.NotIn)):
                continue
    return m


def call_miss(n, params):
    f = n.func
    m = set()
    if n.keywords and not (isinstance(f, ast.Name) and f.id[:1].islower() and f.id not in BUILTINS_ALL):
        m.add("kwargs-call")
    if isinstance(f, ast.Name):
        name = f.id
        if name in BUILTINS:
            return m
        if name == "isinstance":
            m.add("isinstance")
        elif name in ("getattr", "setattr", "hasattr", "type", "vars", "eval", "exec", "globals", "locals", "id", "callable", "super"):
            m.add("reflection")
        elif name in ("int", "abs", "min", "max", "sum", "divmod", "ord", "chr", "hex", "oct", "bin", "round", "pow"):
            m.add("int-builtins")
        elif name in ("range", "enumerate", "zip", "sorted", "reversed", "map", "filter", "any", "all", "list", "iter", "next"):
            m.add("iter-builtins")
        elif name in ("dict", "set", "frozenset"):
            m.add("dict" if name == "dict" else "set")
        elif name in ("tuple",):
            m.add("tuple")
        elif name in ("float",):
            m.add("float")
        elif name in ("print", "open", "input"):
            m.add("io")
        elif name[:1].isupper():
            m.add("record")          # constructing a class instance
        # any other plain name: a module-local def (the census resolves those)
    elif isinstance(f, ast.Attribute):
        if isinstance(f.value, ast.Name) and f.value.id == "self":
            m.add("record")
        elif f.attr in STR_METHODS:
            pass
        elif f.attr in ("append", "extend", "pop", "insert", "remove", "sort", "reverse", "index", "count", "copy", "clear"):
            m.add("list-methods")
        elif f.attr in ("get", "items", "keys", "values", "setdefault", "update"):
            m.add("dict")
        elif f.attr in ("format",):
            m.add("fstring")
        elif isinstance(f.value, ast.Name) and f.value.id not in params:
            m.add("module-call")     # os.path.x, sys.x, re.x: another module's API
        else:
            m.add("str-methods-more")
    else:
        m.add("reflection")          # calling the result of an expression
    return m


def defs(tree, methods):
    for dp, dn, fs in os.walk(tree):
        dn[:] = sorted(d for d in dn if d not in ("test", "tests", "idlelib", "__pycache__", "site-packages"))
        for f in sorted(fs):
            if not f.endswith(".py"):
                continue
            path = os.path.join(dp, f)
            try:
                mod = ast.parse(open(path, encoding="utf-8").read())
            except (SyntaxError, UnicodeDecodeError, ValueError):
                continue
            for n in mod.body:
                if isinstance(n, ast.FunctionDef):
                    yield os.path.relpath(path, tree), n.name, n, False
                elif methods and isinstance(n, ast.ClassDef):
                    for c in n.body:
                        if isinstance(c, ast.FunctionDef):
                            yield os.path.relpath(path, tree), n.name + "." + c.name, c, True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tree", nargs="?", default=sysconfig.get_path("stdlib"))
    ap.add_argument("--methods", action="store_true")
    ap.add_argument("--top", type=int, default=25)
    ap.add_argument("--json", default="")
    a = ap.parse_args()
    seen, rows = set(), []
    for path, name, fn, is_method in defs(a.tree, a.methods):
        key = ast.dump(fn, annotate_fields=False)
        if key in seen:
            continue
        seen.add(key)
        m = miss(fn)
        if is_method:
            m.add("record")          # a method needs its receiver as a record
        rows.append((path, name, frozenset(m)))
    total = len(rows)
    freq = Counter(f for _, _, m in rows for f in m)
    clean = sum(1 for _, _, m in rows if not m)
    alone = Counter(next(iter(m)) for _, _, m in rows if len(m) == 1)
    print(f"what-if census of {a.tree}: {total} distinct defs{' (with methods)' if a.methods else ''}")
    print(f"  no missing feature (syntactic upper bound today): {clean}  ({100 * clean / total:.1f}%)")
    print(f"  missing-feature count per def: " + ", ".join(
        f"{k}:{v}" for k, v in sorted(Counter(min(len(m), 6) for _, _, m in rows).items())) + "  (6 = 6+)")
    print("\nfeatures by how many defs use them (a def counts once per feature):")
    for f, k in freq.most_common(a.top):
        print(f"  {k:6d}  {100 * k / total:5.1f}%  {f:20s}  alone unlocks {alone[f]}")

    # Greedy: add the feature that unlocks the most defs, given those added.
    have, got, curve = set(), clean, []
    feats = set(freq)
    while feats:
        best = max(sorted(feats), key=lambda f: sum(1 for _, _, m in rows if m and m <= have | {f}))
        now = sum(1 for _, _, m in rows if m <= have | {best})
        if now == got:
            break
        have.add(best)
        feats.discard(best)
        curve.append((best, now))
        got = now
        if len(curve) >= a.top:
            break
    print("\ngreedy roadmap (feature added -> defs unlocked, cumulative):")
    for f, k in curve:
        print(f"  + {f:20s} {k:6d}  {100 * k / total:5.1f}%")

    print("\nthe plan's tiers, cumulative:")
    have = set()
    for label, fs in PLAN:
        have |= fs
        k = sum(1 for _, _, m in rows if m <= have)
        print(f"  {label:24s} {k:6d}  {100 * k / total:5.1f}%")
    rest = Counter(f for _, _, m in rows if not m <= have for f in m - have)
    print("\nafter the whole plan, what still blocks (top):")
    for f, k in rest.most_common(12):
        print(f"  {k:6d}  {f}")
    if a.json:
        json.dump([{"file": p, "def": n, "missing": sorted(m)} for p, n, m in rows], open(a.json, "w"), indent=0)
    return 0


if __name__ == "__main__":
    sys.exit(main())
