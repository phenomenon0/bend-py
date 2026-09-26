"""The translator's coverage census on real code: every top-level def of a Python
tree, translated alone, and the first refusal of each counted.

  python3 tests/translator/census.py [TREE] [--jobs 4] [--limit N] [--json OUT]

TREE defaults to CPython's own standard library (sysconfig's `stdlib`), which
every machine with the oracle has, so the number is reproducible anywhere.

A def is probed with demos/python/translate.bend (built once to JS). An
annotated def is probed as written. An unannotated one is probed with stubs
from the fragment's types, the parameters all `str`, all `list[str]` or all
`bool`, crossed with the four return types, in that order. The search stops
at the first stub that emits, and tries another only when the refusal is about
types. A def that emits under a stub emits under an *unreviewed* claim: an
upper bound on coverage, never a certification (stubs1.md's review is what
certifies). The census prints:
  - emits (annotated), emits (stub), refused;
  - refusals by class (positions and names stripped);
  - refusals by detail: the statement or expression outside the fragment, the
    method with no contract, the name left unresolved.
Every run is a pure function of the tree and the translator, so two runs are
compared by their tables (--json keeps the per-def rows)."""

import argparse
import ast
import json
import os
import re
import subprocess
import sys
import sysconfig
import tempfile
from collections import Counter
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "tests", "translator", "_out")
TR = os.path.join(OUT, "translate.js")
ENV = dict(os.environ, BEND_NO_TELEMETRY="1")
PARAMS = ["str", "list[str]", "bool"]
RETS = ["str", "bool", "str | None", "list[str]"]
TYPEY = ("type mismatch", "annotation", "does not return", "Optional", "over a non-list",
         "truthiness", "no verified contract", "mixed element", "two types")


def defs(tree):
    """(file, name, source text, annotated?, nparams) for each top-level def."""
    for dp, dn, fs in os.walk(tree):
        dn[:] = sorted(d for d in dn if d not in ("test", "tests", "idlelib", "__pycache__", "site-packages"))
        for f in sorted(fs):
            if not f.endswith(".py"):
                continue
            path = os.path.join(dp, f)
            try:
                src = open(path, encoding="utf-8").read()
                mod = ast.parse(src)
            except (SyntaxError, UnicodeDecodeError, ValueError):
                continue
            for n in mod.body:
                if isinstance(n, ast.FunctionDef):
                    a = n.args
                    annotated = n.returns is not None or any(x.annotation is not None for x in a.args)
                    # a header with defaults alone is stubbed like any other: the
                    # translator fills literal defaults at calls and strips them
                    yield (os.path.relpath(path, tree), n.name, ast.get_source_segment(src, n),
                           annotated, len(a.args), bool(a.vararg or a.kwarg
                                                        or a.kwonlyargs or a.posonlyargs or n.decorator_list))


def translate(text, name, sig, work):
    src = os.path.join(work, "m.py")
    open(src, "w").write(text + "\n")
    env = {**ENV, "PY_SOURCE": src, "PY_DEF": name}
    if sig is not None:
        open(os.path.join(work, "sig.py"), "w").write(sig)
        env["PY_SIG"] = os.path.join(work, "sig.py")
    try:
        p = subprocess.run(["bun", TR], env=env, capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired:
        return False, "timeout"
    out = (p.stdout + p.stderr).strip()
    if p.returncode == 0 and out.startswith("# Faithful translation"):
        return True, ""
    return False, next((l for l in out.splitlines() if l.strip()), f"exit {p.returncode}")


def callee(text, msg):
    """The call a refusal points at, read off the def's own AST by position."""
    x = re.search(r" at (\d+):(\d+)", msg)
    if not x:
        return ""
    line, col = int(x.group(1)), int(x.group(2))
    for n in ast.walk(ast.parse(text)):
        if isinstance(n, (ast.Call, ast.Attribute, ast.Subscript)) and n.lineno == line and n.col_offset == col:
            f = n.func if isinstance(n, ast.Call) else n
            if isinstance(f, ast.Name):
                return f.id + "()"
            if isinstance(f, ast.Attribute):
                base = f.value.id + "." if isinstance(f.value, ast.Name) and f.value.id in ("os", "sys", "re", "str", "math") else "."
                return base + f.attr + ("()" if isinstance(n, ast.Call) else "")
            return type(f).__name__
    return ""


def classify(msg, text):
    """(class, detail) of a first refusal."""
    m = re.sub(r"^error \w+ \d+ \d+ ", "", msg)
    d = ""
    bare = re.sub(r" at \d+:\d+(-\d+:\d+)?$", "", m)
    for pat in (r"outside the fragment: statement (\w+)", r"outside the fragment: (\w+(?: \w+)?)",
                r"no verified contract for (\.\w+ on \([^)]*\))", r"unresolved (?:name|call) ([\w.]+)",
                r"module not closed: (\w+)"):
        x = re.search(pat + "$", bare) or re.search(pat, bare)
        if x:
            d = x.group(1)
            break
    if d in ("Call", "Attribute", "Subscript"):
        d = f"{d}: {callee(text, m) or '?'}"
    c = re.sub(r" at \d+:\d+(-\d+:\d+)?$", "", m)
    c = re.sub(r"\b(unresolved (?:name|call)) [\w.]+", r"\1 X", c)
    c = re.sub(r"no verified contract for \.\w+ on \([^)]*\) with \([^)]*\)", "no verified contract for a method", c)
    c = re.sub(r"(is not Optional|let of|the name|two types, )[: ]*[\w&<>,; ]+", r"\1 X", c)
    c = re.sub(r"\b[a-z_]\w*\(([^()]*)\)", r"f(\1)", c)
    return c[:100], d


def header(text):
    """What makes a header non-simple, most specific first."""
    f = ast.parse(text).body[0]
    a = f.args
    if f.decorator_list:
        return "decorated"
    if a.vararg or a.kwarg:
        return "*args / **kwargs"
    if a.kwonlyargs or a.posonlyargs:
        return "keyword-only / positional-only"
    if a.defaults:
        return "default values only"
    return "other"


def probe(row, work):
    path, name, text, annotated, n, odd = row
    if annotated or odd:
        ok, msg = translate(text, name, None, work)
        return ("emits (annotated)" if ok else "refused"), msg
    tried = None
    for pt in PARAMS:
        for rt in RETS:
            sig = f"def {name}({', '.join(f'p{i}: {pt}' for i in range(n))}) -> {rt}:\n    pass\n"
            # the stub names the def's own parameters
            names = [a.arg for a in ast.parse(text).body[0].args.args]
            sig = f"def {name}({', '.join(f'{a}: {pt}' for a in names)}) -> {rt}:\n    pass\n"
            ok, msg = translate(text, name, sig, work)
            if ok:
                return "emits (stub)", f"({pt}) -> {rt}"
            tried = tried or msg
            if not any(t in msg for t in TYPEY):
                return "refused", tried
    return "refused", tried


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tree", nargs="?", default=sysconfig.get_path("stdlib"))
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--json", default="")
    a = ap.parse_args()
    if not os.path.exists(TR):
        os.makedirs(OUT, exist_ok=True)
        r = subprocess.run(["bun", "bend2/main.ts", "demos/python/translate.bend", "-o", TR], cwd=ROOT, env=ENV,
                           capture_output=True, text=True)
        if r.returncode:
            print(r.stdout + r.stderr)
            return 2
    # One row per distinct def body (as stubs1 counted unique candidates): the
    # stdlib's encodings/ alone repeats one getregentry() a hundred times.
    seen, rows = set(), []
    for r in defs(a.tree):
        key = ast.dump(ast.parse(r[2]).body[0], annotate_fields=False)
        if key not in seen:
            seen.add(key)
            rows.append(r)
    if a.limit:
        rows = rows[: a.limit]
    base = tempfile.mkdtemp(prefix="census_", dir=OUT)

    def one(ir):
        i, row = ir
        work = os.path.join(base, str(i))
        os.makedirs(work, exist_ok=True)
        verdict, msg = probe(row, work)
        return row, verdict, msg

    with ThreadPoolExecutor(a.jobs) as pool:
        results = list(pool.map(one, enumerate(rows)))
    verdicts = Counter(v for _, v, _ in results)
    classes, details = Counter(), Counter()
    for row, v, msg in results:
        if v == "refused":
            c, d = classify(msg, row[2])
            if c.startswith("decorated or non-simple"):
                d = "header: " + header(row[2])
            classes[c] += 1
            if d:
                details[d] += 1
    total = len(results)
    print(f"census of {a.tree}: {total} distinct top-level defs")
    for k in ("emits (annotated)", "emits (stub)", "refused"):
        print(f"  {k:18s} {verdicts[k]:6d}  {100 * verdicts[k] / max(total, 1):5.1f}%")
    print("\nrefusals by class:")
    for c, k in classes.most_common(25):
        print(f"  {k:6d}  {c}")
    print("\nrefusals by detail (statement / expression / method / name):")
    for d, k in details.most_common(40):
        print(f"  {k:6d}  {d}")
    emitted = [(r[0], r[1], m) for r, v, m in results if v.startswith("emits")]
    print(f"\nemitting defs ({len(emitted)}):")
    for p, n, m in emitted[:60]:
        print(f"  {p}:{n}  {m}")
    if a.json:
        json.dump([{"file": r[0], "def": r[1], "verdict": v, "msg": m} for r, v, m in results], open(a.json, "w"), indent=0)
    return 0


if __name__ == "__main__":
    sys.exit(main())
