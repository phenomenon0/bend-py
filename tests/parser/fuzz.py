"""Seeded supported-grammar generation, differential checks, and residual fuel measurements."""
from normalize import OUT, oracle, pin, supported
from diff import build, run, compare
from fixtures import EXPRESSIONS, STATEMENTS, INVALID, UNSUPPORTED
import argparse
import ast
import json
import random


def fstring(rng, sub):
    """An implicit-concatenation run with f-strings: fields, conversions, debug `=`, nested specs."""
    def field():
        value = sub()
        if any(c in value for c in '"\\#'):  # 3.11: the expression cannot reuse the quote, nor hold a backslash or comment
            value = "a"
        spec = rng.choice(["", "", ":", ":>10", ":{" + rng.choice(["w", "w!r", "w:>5"]) + "}", ":.{p}f", ": {a}{b} ", ":{{w}}"])
        return "{ " + value + rng.choice(["", " ", "=", " = "]) + rng.choice(["", "", "!r", "!s", "!a"]) + spec + "}"
    def token():
        if rng.randrange(4) == 0:
            return rng.choice(["'s'", "u'é'", "''", "r'\\d'", "'\\n'"])
        body = "".join(rng.choice(["", "a", "{{", "}}", "é😀", "\\n", " x ", "'", "\\N{DIGIT ONE}"]) if rng.randrange(2) else field()
                       for _ in range(rng.randrange(4)))
        return rng.choice(["f", "F", "rf", "fR"]) + '"' + body + '"'
    tokens = [token() for _ in range(rng.randrange(1, 4))]
    tokens[rng.randrange(len(tokens))] = 'f"' + field() + '"'
    return "(" + rng.choice([" ", "\n  "]).join(tokens) + ")"


def identifier_sources(rng, count):
    """One non-ASCII identifier of `\\w` scalars per source, in every identifier slot: the oracle accepts it as written,
    accepts it under another (NFKC) name, or rejects a scalar outside XID_Start / XID_Continue."""
    from gen_ident import W, XC, XS, UNSTABLE
    pools = [sorted(W & XS - UNSTABLE)] * 4 + [sorted(W & XC - XS - UNSTABLE), sorted(W - XC), sorted(W & UNSTABLE), [ord(c) for c in "ab_1"]]
    slots = ["{0} = 1", "x.{0}", "f({0}=1)", "def {0}({0}): pass", "class {0}: pass", "import {0}.{0} as {0}", "from a import {0}", "global {0}", "lambda {0}: {0}",
             "f'{{{0}}}'", "[{0} for {0} in y]", "({0} := 1)", "match x:\n    case {0}.{0}: pass\n", "try: pass\nexcept E as {0}: pass", "{0}: {0} = {0}"]
    return [rng.choice(slots).format("".join(chr(rng.choice(rng.choice(pools))) for _ in range(rng.randrange(1, 5)))) for _ in range(count)]


def comprehension(rng, sub):
    """All four forms: nested `for` clauses, `if` filters, non-name targets, multi-line, the bare call argument."""
    gap = rng.choice([" ", " ", "\n  "])
    target = lambda: rng.choice(["a", "a", "a, b", "a, *b", "*a,", "(a, b)", "[a, (b, *c)]", "a.b", "a[0]", "a[1:2], b.c"])
    clause = lambda: gap + "for " + target() + " in " + sub() + "".join(gap + "if " + sub() for _ in range(rng.randrange(3)))
    clauses = "".join(clause() for _ in range(rng.randrange(1, 4)))
    return rng.choice(["[{0}{2}]", "{{{0}{2}}}", "{{{0}: {1}{2}}}", "({0}{2})", "f({0}{2})", "f( {0}{2} )(a)"]).format(sub(), sub(), clauses)


def annotated(rng, sub):
    """`target: annotation [= value]`: every target kind (parenthesised or not), any expression as annotation, star-expressions as value; some targets the oracle rejects."""
    target = rng.choice(["x", "x", "(x)", "((x))", "a.b", "(a.b)", "a[" + sub() + "]", "(" + sub() + ").c", "(" + sub() + ")[1:2]", "f(" + sub() + ").d",
                         "x, y", "(x, y)", "[x]", "*x", "f()", "(" + sub() + ")"])
    value = rng.choice(["", "", " = " + sub(), " = " + sub() + ", " + sub(), " = *a, " + sub(), " = " + sub() + ","])
    return target + rng.choice([": ", ":", " : "]) + sub() + value


def yielding(rng, sub):
    """`yield_expr | star_expressions` in every slot that takes it, and in some that do not (the oracle rejects those)."""
    y = rng.choice(["yield", "yield", "yield " + sub(), "yield " + sub(), "yield from " + sub(), "yield " + sub() + ", " + sub(), "yield *a, " + sub(), "yield " + sub() + ",",
                    "yield from " + sub() + ", b", "yield yield", "yield from *a"])
    g = "(" + y + ")"
    return rng.choice([y, y, "x = " + y, "x = y = " + y, "x " + rng.choice(["+=", "//=", "@="]) + " " + y, "x: " + sub() + " = " + y, "x: " + g, g, "(" + g + ")", "(\n " + y + "\n)",
                       "f(" + g + ", " + sub() + ", k=" + g + ")", g + ".a[" + g + "] = " + y, "[" + g + ", " + sub() + "]", "{" + g + ": " + g + "}", g + " if " + g + " else " + g, sub() + " + " + g, "not " + g,
                       "[" + g + " for x in " + g + " if " + g + "]", "f'{" + y + "}'", "f'{" + y + "!r:>{" + g + "}}'", "lambda: " + g, "return " + g, "yield " + g, "yield from " + g,
                       "f(" + y + ")", "[" + y + "]", "(" + y + ", 1)", "x = " + sub() + ", " + y, "return " + y, "lambda: " + y, y + " = 1", g + " = 1", y + ": int", "(" + y + " for x in y)", "a[" + y + "]", sub() + " + " + y])


def awaiting(rng, sub):
    """`await primary` in every expression slot, async comprehensions, and the three async statements; some shapes the oracle rejects."""
    p = rng.choice(["x", "x.y", "f(" + sub() + ")", "x[" + sub() + "]", "(" + sub() + ")", "[" + sub() + "]", "f'{x}'", "(yield)", "1"] * 4 + ["-x", "not x", "lambda: x", "await x", "*x", ""])
    a = "await " + p
    c = rng.choice(["async for", "async for", "async for", "for", "for", "async"]) + " i in " + rng.choice([a, sub(), "a if b else c"]) + rng.choice(["", " if " + a, " async for j in " + a + " if j", " for j in k"])
    return rng.choice([a, a, "x = " + a, "x = y = " + a + ", " + a, "x " + rng.choice(["+=", "**=", ">>="]) + " " + a, "x: " + a + " = " + a, a + " ** " + a, "-" + a + " ** -" + a, sub() + " + " + a + " * " + sub(),
                       a + " if " + a + " else " + a, "not " + a + " or " + a + " < " + a, "f(" + a + ", *" + a + ", k=" + a + ", **" + a + ")", "x[" + a + ":" + a + ", " + a + "]", "{" + a + ": " + a + ", **" + a + "}", "(" + a + ").y = " + a,
                       "f'{" + a + "!r:>{" + a + "}}'", "lambda x=" + a + ": " + a, "return " + a, "yield " + a, "yield from " + a, "del (" + a + ").y, (" + a + ")[0]", "assert " + a + ", " + a, "raise " + a + " from " + a,
                       "[" + a + " " + c + "]", "{" + a + " " + c + "}", "{" + a + ": " + sub() + " " + c + "}", "(" + a + " " + c + ")", "f(" + sub() + " " + c + ")", "x = [[j " + c + "] " + c + "]",
                       a + " = 1", "(" + a + ") += 1", a + ": int", "for " + a + " in y: pass", "del " + a, "f(await=" + sub() + ")", "x.await", "async = " + sub(), "[" + sub() + " async]", "f(" + sub() + " " + c + ", 1)"])


def naming(rng, sub):
    """`NAME := expression` in every slot that takes a named expression, and in some that do not (the oracle rejects those)."""
    t = rng.choice(["x"] * 60 + ["a.b", "a[0]", "(x)", "x, y", "1", "None", "await", "*x", ""])
    v = rng.choice([sub(), sub(), sub(), "lambda: " + sub(), sub() + " if " + sub() + " else " + sub(), "(y := " + sub() + ")", "(yield)", "await z"] * 5 + ["y := " + sub(), "*a", "yield", sub() + ", " + sub(), ""])
    w = t + rng.choice([" := ", ":=", " :=\n  "]) + v
    g = "(" + w + ")"
    c = rng.choice(["for", "for", "async for"]) + " i in " + rng.choice([sub(), g, w]) + rng.choice(["", " if " + g, " if " + w, " if " + g + " if " + g])
    return rng.choice([g, g, w, "x = " + g, "x = " + w, "x = y = " + g + ", " + g, "x " + rng.choice(["+=", "|=", "<<="]) + " " + rng.choice([g, w]), "x: " + g + " = " + g, "x: int = " + w, g + " = 1", g + ": int", g + ".y[" + w + "] = " + g,
                       "if " + w + ": pass\nelif " + w + ": pass", "if " + g + " and " + g + ":\n    while " + w + ": pass\n", "while " + w + ", 1: pass", "if not " + w + ": pass", "if " + sub() + " or " + w + ": pass",
                       "[" + w + ", " + w + "]", "[*a, " + w + ",]", "(" + w + ", " + w + ")", "(" + w + ",)", "{" + w + ", " + w + "}", "{" + w + ": " + sub() + "}", "{" + g + ": " + g + ", **" + g + "}", "{" + sub() + ": " + w + "}",
                       "f(" + w + ", " + w + ", k=" + g + ", *" + g + ", **" + g + ")", "f(k=" + w + ")", "f(*" + w + ")", "f(" + sub() + ", " + w + ")(" + w + ")", "class A(" + w + ", k=" + g + "): pass",
                       "a[" + w + "]", "a[" + w + ", " + w + "]", "a[" + g + ":" + g + ":" + g + ", " + w + "]", "a[" + w + ":" + sub() + "]", "a[" + sub() + ":" + w + "]",
                       "[" + w + " " + c + "]", "{" + w + " " + c + "}", "(" + w + " " + c + ")", "f(" + w + " " + c + ")", "{" + g + ": " + g + " " + c + "}", "{" + w + ": " + sub() + " " + c + "}", "{" + sub() + ": " + w + " " + c + "}",
                       "f'{" + g + "!r:>{" + g + "}}'", "f'{" + w + "}'", "f'{" + g + " = }'", "lambda: " + rng.choice([g, w]), "lambda a=" + rng.choice([g, w]) + ": a", "@" + w + "\ndef f(a=" + g + ", *b: " + g + ") -> " + g + ": pass",
                       "return " + rng.choice([g, w]), "yield " + rng.choice([g, w]), "yield from " + rng.choice([g, w]), "await " + rng.choice([g, w]), "del " + rng.choice([g, w, "a[" + w + "]"]), "assert " + rng.choice([g + ", " + g, w]),
                       "raise " + g + " from " + rng.choice([g, w]), "for a in " + rng.choice([g, w]) + ": pass", "for " + g + " in a: pass", "with " + g + " as a, " + g + ": pass", "with (" + w + "): pass", "with (" + w + ", " + w + "): pass", "with " + w + ": pass",
                       "with (" + g + " as a, " + g + "): pass", "try: pass\nexcept " + rng.choice([g, w]) + " as e: pass", g + " if " + g + " else " + g, sub() + " if " + w + " else " + sub(), "not " + g + " < -" + g + " ** " + g, sub() + " + " + w])


def pattern(rng, depth):
    # P14: every pattern production, and the near misses the oracle rejects (a star outside a sequence, `as _`, a non-literal arithmetic, a trailer on `_`).
    sub = lambda: pattern(rng, depth - 1)
    if depth <= 0 or rng.randrange(4) == 0:
        good = ["a", "b", "_", "0", "-1", "1.5", "2j", "1+2j", "-1 - 2J", "'s'", "'s' 't'", "b'x'", "None", "True", "False", "a.b", "a.b.c", "match", "case", "C()", "{}", "[]", "()", "f's{a}'"]
        return rng.choice(good if rng.randrange(30) else ["-a", "1+2", "2j+1", "...", "_.a", "_()", "a[0]", "+1", "*a", "-'s'", "1 + -2j"])
    choice = rng.randrange(12)
    many = lambda: ", ".join(rng.choice([sub(), sub(), sub(), "*" + rng.choice(["a", "_", "a", "_", "a", "_", "a.b", "(a)"])]) for _ in range(rng.randrange(1, 4))) + rng.choice(["", ","])
    if choice == 0:
        return "(" + sub() + ")"
    if choice < 3:
        close = rng.choice(["[]", "()"] * 12 + ["[)"])
        return close[0] + many() + close[1]
    if choice == 3:
        return " | ".join(sub() for _ in range(rng.randrange(2, 4)))
    if choice == 4:
        return sub() + " as " + rng.choice(["a", "b", "c", "d"] * 5 + ["_", "a.b", "(a)"])
    if choice < 7:
        key = lambda: rng.choice(["'k'", "1", "-1", "1+2j", "None", "True", "a.b", "_.a", "'k' 'l'"] * 3 + ["a", "_", "(1)"])
        items = [key() + ": " + sub() for _ in range(rng.randrange(0, 3))] + rng.choice([[], [], ["**" + rng.choice(["r"] * 8 + ["_", "a.b"])]])
        if rng.randrange(20) == 0:
            rng.shuffle(items)
        return "{" + ", ".join(items) + rng.choice(["", ","] if items else [""]) + "}"
    if choice < 10:
        args = [rng.choice([sub(), sub(), rng.choice(["k", "k", "k", "_", "a.b"]) + "=" + sub()] * 5 + ["*a"]) for _ in range(rng.randrange(0, 4))]
        if rng.randrange(10):
            args.sort(key=lambda a: "=" in a.split("(")[0].split("[")[0].split("{")[0])
        return rng.choice(["C", "a.C", "match"] * 5 + ["_", "C()"]) + "(" + ", ".join(args) + ")"
    return sub() + ", " + sub()


def matching(rng, sub):
    case = lambda pad: pad + "case " + pattern(rng, rng.randrange(0, 4)) + rng.choice(["", "", " if " + sub(), " if " + sub(), " if a := " + sub()] * 4 + [" if " + sub() + ", b"]) + rng.choice([": pass\n", ":\n" + pad + "    x = " + sub() + "\n" + pad + "    match = case\n"])
    head = rng.choice(["x", "x, y", "x,", "*x, y", "(x)", "[x]", "-x", "x := a", sub(), sub()] * 3 + ["*x", "x: int", ""])
    body = "".join(case("    ") for _ in range(rng.randrange(1, 4)))
    if rng.randrange(6) == 0:
        body += "    case _:\n        match y:\n" + case("            ") + "    case _: pass\n"
    return "match " + head + ":\n" + body + rng.choice(["", "match(x)\ncase = match\n"] * 8 + ["else: pass\n", "    pass\n"])


def expression(rng, depth):
    if depth <= 0 or rng.randrange(5) == 0:
        return rng.choice(["a", "b", "c", "0", "17", "0x10", "1.5", "True", "None", "'é😀'", "..."])
    sub = lambda: expression(rng, depth - 1)
    choice = rng.randrange(18)
    if choice >= 15:
        return comprehension(rng, sub)
    if choice >= 13:
        return fstring(rng, sub)
    if choice == 0:
        return rng.choice(["-", "+", "~", "not "]) + "(" + sub() + ")"
    if choice < 4:
        return "(" + sub() + ") " + rng.choice(["+", "-", "*", "**", "@", "/", "//", "%", "<<", ">>", "|", "^", "&", "and", "or", "<", "is not", "not in"]) + " (" + sub() + ")"
    if choice == 4:
        return "(" + sub() + " if " + sub() + " else " + sub() + ")"
    if choice == 5:
        return "f(" + sub() + ", k=" + sub() + ")"
    if choice == 6:
        return "(" + sub() + ").attr[" + sub() + "]"
    if choice == 7:
        return "[" + sub() + ", " + sub() + "]"
    if choice == 8:
        return "{" + sub() + ": " + sub() + "}"
    if choice == 9:
        return "(" + sub() + ", " + sub() + ")"
    if choice == 10:
        return "{" + sub() + ", " + sub() + "}"
    if choice == 11:
        part = lambda: rng.choice(["", sub()])
        return "(" + sub() + ")[" + part() + ":" + part() + rng.choice(["", ":" + part()]) + rng.choice(["", ", " + sub(), ", ::" + part() + ","]) + "]"
    return "(" + sub() + " < " + sub() + " <= " + sub() + ")"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, default=1000)
    args = parser.parse_args()
    pin()
    build()
    rng = random.Random(0xA57A2026)
    sources = EXPRESSIONS + STATEMENTS
    for i in range(args.count):
        value = expression(rng, rng.randrange(1, 5))
        sources.append(rng.choice([value, "x = " + value, "x += " + value,
                                  "if " + value + ":\n    pass\nelse:\n    return x\n",
                                  "while " + value + ":\n    break\n",
                                  "def f(a, b=" + value + ", *c, d: " + value + " = 1, **e) -> " + value + ":\n    return lambda x, y=" + value + ": x;\n",
                                  "@" + value + "\ndef f():\n    for a, *b in " + value + ", c:\n        del a, b[" + value + "]\n    else:\n        assert " + value + ", a\n",
                                  "try:\n    raise " + value + " from " + value + "\nexcept " + value + " as e:\n    global g\nelse:\n    pass\nfinally:\n    x = 1\n",
                                  "import a.b as c, d\nif " + value + ":\n    from ..e.f import (g as h, i,)\n    from . import j; from k import *\n",
                                  "@" + value + "\nclass A(B, " + value + ", *c, metaclass=" + value + ", **k):\n    'doc'\n    x = " + value + "\n    class C: pass\n    @d\n    def f(self):\n        return " + value + "\nclass D(): y = 1; z = 2\n",
                                  "with (" + value + ") as a, " + value + ":\n    pass\nwith (" + value + " as b, c):\n    nonlocal n\n"]))
    # A second stream, so the P2-P9 sources above stay what they were.
    rng = random.Random(0xA57A2010)
    for i in range(args.count // 4):
        line = annotated(rng, lambda: expression(rng, rng.randrange(0, 3)))
        sources.append(rng.choice([line, line, "class A(B):\n    'doc'\n    " + line + "\n    y: int\n    def f(self):\n        self." + line + "\n",
                                  "if a: " + line + "; " + line + "\nelse:\n    " + line + "\n", "def f():\n    " + line + "\n    return x\n"]))
    # A third stream, for the same reason.
    rng = random.Random(0xA57A2011)
    for i in range(args.count // 4):
        line = yielding(rng, lambda: expression(rng, rng.randrange(0, 3)))
        sources.append(rng.choice([line, line, "def f():\n    " + line + "\n    return x\n", "def f(self):\n    while a:\n        " + line + "\n    else:\n        " + line + "; " + line + "\n",
                                  "if a: " + line + "; " + line + "\nelse:\n    " + line + "\n", "class A:\n    def f(self):\n        try:\n            " + line + "\n        finally:\n            pass\n"]))
    # A fourth stream, for the same reason.
    rng = random.Random(0xA57A2012)
    for i in range(args.count // 4):
        sub = lambda: expression(rng, rng.randrange(0, 3))
        line = awaiting(rng, sub)
        sources.append(rng.choice([line, line, "async def f():\n    " + line + "\n    return x\n", "@d\nasync def f(a, /, b=1, *c, d, **e) -> " + sub() + ":\n    async with " + sub() + " as a, (b):\n        " + line + "\n",
                                  "async def f(self):\n    async for a, *b in " + sub() + ", c:\n        " + line + "\n    else:\n        " + line + "; " + line + "\n",
                                  "class A:\n    @d\n    async def f(self):\n        async with (" + sub() + " as a, b):\n            " + line + "\n        async with (a, b) as c: pass\n",
                                  "if a: " + line + "; " + line + "\nelse:\n    async for x in y: " + line + "\n", "async " + rng.choice(["def f(): ", "class A: ", "if a: ", "with a: ", "for x in y: ", "while a: ", "\ndef f(): "]) + line + "\n"]))
    # A fifth stream, for the same reason.
    rng = random.Random(0xA57A2013)
    for i in range(args.count // 2):  # twice the others: most slots take no bare walrus, so over half are negatives
        line = naming(rng, lambda: expression(rng, rng.randrange(0, 3)))
        sources.append(rng.choice([line, line, "def f():\n    " + line + "\n    return x\n", "async def f(self):\n    while a:\n        " + line + "\n    else:\n        " + line + "; " + line + "\n",
                                  "if a: " + line + "; " + line + "\nelse:\n    " + line + "\n", "class A:\n    def f(self):\n        try:\n            " + line + "\n        finally:\n            pass\n"]))
    # A sixth stream, for the same reason.
    rng = random.Random(0xA57A2014)
    for i in range(args.count // 2):  # as the fifth: the near misses make about half negatives
        block = matching(rng, lambda: expression(rng, rng.randrange(0, 3)))
        sources.append(rng.choice([block, block, "def f(x):\n" + "".join("    " + l + "\n" for l in block.splitlines()), "class A:\n    async def f(self):\n        while a:\n" + "".join("            " + l + "\n" for l in block.splitlines())]))
    # Long lists/chains and nesting deliberately exercise non-consuming transitions.
    for n in [1, 2, 10, 50, 100, 200]:
        sources += ["(" * n + "a" + ")" * n, "[" * n + "a" + "]" * n,
                    "+".join(["a"] * n), " or ".join(["a"] * n),
                    "[" + ",".join(["a"] * n) + "]", "not " * n + "a"]
    records, failures, highwater = [], [], {"ratio": 0}
    path = OUT / "fuzz-input.py"
    for i, source in enumerate(sources):
        path.write_text(source)
        try:
            # Fuel acceptance is tested even if oracle AST conversion exceeds a host stack.
            ast.parse(source, feature_version=(3, 11), type_comments=False)
        except (SyntaxError, RecursionError, MemoryError) as exc:
            records.append({"i": i, "oracle-failure": str(exc)})
            # A generated source the oracle rejects (an f-string shape) is a negative: never parsed.
            if isinstance(exc, SyntaxError) and run(path)["status"] != "syntax":
                failures.append({"i": i, "source": source, "oracle": str(exc), "result": run(path)})
            continue
        result = run(path, mode="stats")
        if result["status"] != "parsed":
            failure = {"i": i, "source": source, "result": result}
            failures.append(failure)
            records.append(failure)
            continue
        stats = result["value"]
        ratio = stats["used"] / (stats["tokens"] + 1)
        if ratio > highwater["ratio"]:
            highwater = {"ratio": ratio, "i": i, **stats}
        rec = {"i": i, **stats}
        try:
            want, _ = oracle(source)
            got = run(path)
            if got["status"] != "parsed":
                failures.append({"i": i, "source": source, "result": got})
            else:
                struct, loc = compare(want, got["value"])
                if struct or loc:
                    failures.append({"i": i, "source": source, "structural": struct, "locations": loc})
            if i % 20 == 0:
                js = run(path, "js")
                if js.get("value") != got.get("value") or js["status"] != got["status"]:
                    failures.append({"i": i, "source": source, "js": js})
        except (RecursionError, MemoryError) as exc:
            rec["normalization-failure"] = str(exc)
        records.append(rec)
    identifiers = identifier_sources(random.Random(0xA57A2015), args.count)
    for source in identifiers:
        path.write_text(source)
        got = run(path)
        try:
            want, tree = oracle(source)
        except SyntaxError as exc:
            if got["status"] != "syntax":
                failures.append({"source": source, "oracle": str(exc), "result": got})
            continue
        if not supported(tree, source):
            if got["status"] != "unsupported":
                failures.append({"source": source, "expected": "unsupported", "result": got})
        elif got["status"] != "parsed" or compare(want, got["value"]) != ([], []):
            failures.append({"source": source, "expected": "exact", "result": got})
    for expected, cases in [("syntax", INVALID), ("unsupported", UNSUPPORTED)]:
        for source in cases:
            path.write_text(source)
            for lane in ("c", "js"):
                got = run(path, lane)
                if got["status"] != expected:
                    failures.append({"source": source, "lane": lane, "expected": expected, "got": got})
    counts = {"generated_and_directed": len(sources), "oracle_accepted": sum("used" in r or "result" in r for r in records),
              "oracle_rejected": sum("oracle-failure" in r for r in records), "fstring_sources": sum("f\"" in s.lower() for s in sources),
              "comprehension_sources": sum(" for " in s or "\n  for " in s for s in sources),
              "annotated_sources": args.count // 4, "yield_sources": args.count // 4, "async_sources": args.count // 4, "walrus_sources": args.count // 2, "match_sources": args.count // 2,
              "no_limit_on_oracle_accepted": not any(f.get("result", {}).get("status") == "limit" for f in failures),
              "normalization_failures": sum("normalization-failure" in r for r in records),
              "identifier_sources": len(identifiers),
              "negative_cases": len(INVALID) + len(UNSUPPORTED),
              "negative_runs": 2 * (len(INVALID) + len(UNSUPPORTED)),
              "js_samples": sum(r["i"] % 20 == 0 and "used" in r and "normalization-failure" not in r for r in records), "failures": len(failures), "fuel_k": 32,
              "highwater": highwater}
    (OUT / "fuzz-results.json").write_text(json.dumps({"counts": counts, "failures": failures, "records": records}, indent=2) + "\n")
    print(json.dumps(counts, indent=2))
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
