"""The translator's differential fuzzer: random typed modules in (and around)
the fragment, CPython 3.11.15 as the oracle, every emitted lane as the suspect.

  python3 tests/translator/fuzz.py [--n 200] [--seed 1] [--jobs 4] [--inputs 12] [--interp 0]

For each generated module, demos/python/translate.bend (built once to JS) either
refuses it, which is allowed and counted by its diagnostic (the coverage map), or
emits Bend. An emitted module owes two things (translator-modes.md, C1 and C2):
  C1  it checks: no hole, no open goal, `All terms check.`
  C2  on every generated input inside the value contract (printable ASCII plus
      the six ASCII whitespace), every lane prints exactly what CPython returns.
      Where CPython RAISES on such an input, an emitted def that returns anything
      is a soundness hole: the kernel granted a partial operation.
A finding is shrunk line by line while it fails the same way and is written to
tests/translator/_out/fuzz/. Every module is a pure function of (seed, index).
The run ends with the refusal table and `TFUZZ PASS: n, FAIL: k`."""

import argparse
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "tests", "translator", "_out")
WS = " \t\n\r\x0b\x0c"
ALPHABET = "".join(map(chr, range(32, 127))) + WS
ENV = dict(os.environ, BEND_NO_TELEMETRY="1")

# Modules
# =======

TYPES = ["str", "bool", "list[str]", "str | None"]
LITS = ["", "a", "x", " ", "-", ".", "ab", "a b", "--", "x.y", "Ab", " a ", ":", "#"]


class Gen:
    def __init__(self, rng):
        self.r = rng
        self.defs = []  # (name, [param types], return type)
        self.ndef = {}  # name -> how many trailing parameters have literal defaults

    def p(self, pct):
        return self.r.random() * 100 < pct

    def pick(self, xs):
        return self.r.choice(xs)

    def lit(self):
        return repr(self.pick(LITS))

    def names(self, env, t):
        return [n for n, k in env.items() if k == t]

    def expr(self, env, t, d=0):
        own = self.names(env, t)
        if d > 2 or self.p(25):
            if own and self.p(70):
                return self.pick(own)
            return {"str": self.lit, "bool": lambda: self.pick(["True", "False"]),
                    "list[str]": lambda: f"[{self.lit()}]",
                    "str | None": lambda: "None"}[t]()
        calls = [dn for dn, ps, rt in self.defs if rt == t]
        if calls and self.p(12):
            dn = self.pick(calls)
            ps = [ps for n, ps, _ in self.defs if n == dn][0]
            k = len(ps) - (self.r.randint(0, self.ndef.get(dn, 0)) if self.p(60) else 0)  # omit defaulted tails
            return f"{dn}({', '.join(self.expr(env, pt, d + 1) for pt in ps[:k])})"
        if t == "str":
            s = lambda: self.expr(env, "str", d + 1)
            return self.pick([
                lambda: f"{s()}.strip()", lambda: f"{s()}.lower()",
                lambda: f"{s()}.replace({self.lit()}, {self.lit()})",
                lambda: f"({s()} + {s()})", lambda: f"{s()}.strip({self.lit()})",
                lambda: f"{s()}[{self.r.randint(0, 3)}:]",
                lambda: f"{s()}[:-{self.r.randint(1, 3)}]",
                lambda: f"({s()} if {self.expr(env, 'bool', d + 1)} else {s()})",
                lambda: f"{s()}.upper()", lambda: f"{s()}.lstrip()", lambda: f"{s()}.rstrip()",
                lambda: f"{self.lit()}.join({self.expr(env, 'list[str]', d + 1)})",
            ])()
        if t == "bool":
            s = lambda: self.expr(env, "str", d + 1)
            b = lambda: self.expr(env, "bool", d + 1)
            return self.pick([
                lambda: f"({s()} == {s()})", lambda: f"({self.lit()} in {s()})",
                lambda: f"{s()}.startswith({s()})", lambda: f"(not {b()})",
                lambda: f"({b()} and {b()})", lambda: f"({b()} or {b()})",
                lambda: f"(len({s()}) > {self.r.randint(0, 4)})",
                lambda: f"({s()} {self.pick(['<', '<=', '>', '>='])} {s()})",
                lambda: f"{s()}.endswith({s()})",
                lambda: f"((len({s()}) + len({s()})) {self.pick(['<', '<=', '>=', '=='])} {self.r.randint(0, 6)})",
            ])()
        if t == "list[str]":
            s = lambda: self.expr(env, "str", d + 1)
            return self.pick([
                lambda: f"{s()}.split({repr(self.pick(['.', ' ', '-', ',', ':']))})",
                lambda: f"{s()}.splitlines()",
                lambda: f"[{s()}, {s()}]",
                lambda: f"[x.strip() for x in {self.expr(env, 'list[str]', d + 1)}]",
            ])()
        return self.expr(env, "str", d + 1) if self.p(60) else "None"  # str | None

    def test(self, env):
        """An `if` test: a bool, or a str / list read for its truth value."""
        k = self.r.randint(0, 5)
        if k <= 2:
            return self.expr(env, "bool")
        leaf = lambda: self.expr(env, self.pick(["str", "list[str]", "bool"]))
        if k == 3:
            return leaf()
        if k == 4:
            return f"not {leaf()}"
        return f"{leaf()} {self.pick(['and', 'or'])} {leaf()}"

    def block(self, env, ret, ind, depth, in_loop=False):
        pad = "    " * ind
        out = []
        for _ in range(self.r.randint(0, 2)):
            k = self.r.randint(0, 9)
            if k <= 3:
                t = self.pick(["str", "str", "bool", "list[str]"])
                n = self.pick(["t", "u", "v", "w"])
                if env.get(n) not in (None, t):
                    continue
                out.append(f"{pad}{n} = {self.expr(env, t)}")
                env[n] = t
            elif k <= 5 and depth < 2:
                # a branch returns, or both sides bind the same name (the join)
                if self.p(50):
                    out.append(f"{pad}if {self.test(env)}:")
                    out.append(f"{pad}    return {self.expr(env, ret)}")
                else:
                    t = self.pick(["str", "bool"])
                    n = self.pick([m for m in ("t", "u", "v", "w") if env.get(m) in (None, t)] or ["t9"])
                    out.append(f"{pad}if {self.expr(env, 'bool')}:")
                    out.append(f"{pad}    {n} = {self.expr(env, t)}")
                    out.append(f"{pad}else:")
                    out.append(f"{pad}    {n} = {self.expr(env, t)}")
                    env[n] = t
            elif k <= 7 and depth < 2 and (self.names(env, "list[str]") or self.names(env, "str")):
                # the fold shape: one accumulator bound before the loop, assigned in
                # the body, and/or an early return or break on a guard
                acc = self.pick(["acc", "best"])
                if env.get(acc) not in (None, "str"):
                    continue
                out.append(f"{pad}{acc} = {self.expr(env, 'str')}")
                env[acc] = "str"
                inner = dict(env)
                inner["x"] = "str"
                seqs = self.names(env, "list[str]") + (self.names(env, "str") if self.p(40) else [])
                out.append(f"{pad}for x in {self.pick(seqs or self.names(env, 'str'))}:")
                exit_ = self.p(50)
                if exit_:
                    out.append(f"{pad}    if {self.expr(inner, 'bool')}:")
                    out.append(f"{pad}        " + (f"return {self.expr(inner, ret)}" if self.p(60) else "break"))
                if not exit_ or self.p(60):
                    out.append(f"{pad}    {acc} = {self.expr(inner, 'str')}")
            elif k == 8 and self.names(env, "str") and self.p(40):
                n = self.pick(self.names(env, "str"))
                out.append(f"{pad}{n} += {self.expr(env, 'str')}")
            elif k == 8 and self.names(env, "str"):
                # the guarded partial: split(sep, 1)[1] only where sep is known in the string
                s = self.pick(self.names(env, "str"))
                sep = self.pick(["'.'", "'-'", "':'"])
                out.append(f"{pad}if {sep} in {s}:")
                out.append(f"{pad}    return {s}.split({sep}, 1)[1]" if ret in ("str", "str | None")
                           else f"{pad}    return {self.expr(env, ret)}")
            elif k == 9 and self.names(env, "str | None"):
                o = self.pick(self.names(env, "str | None"))
                if self.p(50):
                    # the guard narrows: after it, o is a str
                    out.append(f"{pad}if {o} is None:")
                    out.append(f"{pad}    return {self.expr(env, ret)}")
                    if depth == 0:
                        env[o] = "str"
                else:
                    inner = dict(env)
                    inner[o] = "str"
                    out.append(f"{pad}if {o} is not None:")
                    out.append(f"{pad}    return {self.expr(inner, ret)}")
        return out

    def module(self):
        lines = []
        # module constants, read (never bound) inside the defs
        self.konsts = {}
        for i in range(self.r.randint(0, 2) if self.p(40) else 0):
            k, t = f"K{i}", self.pick(["str", "str", "bool", "list[str]"])
            v = {"str": self.lit, "bool": lambda: self.pick(["True", "False"]),
                 "list[str]": lambda: "[" + ", ".join(self.lit() for _ in range(self.r.randint(1, 3))) + "]"}[t]()
            lines.append(f"{k} = {v}")
            self.konsts[k] = t
        if self.konsts:
            lines.append("")
        for i in range(self.r.randint(1, 3)):
            name = f"f{i}"
            ps = [self.pick(TYPES) for _ in range(self.r.randint(1, 3))]
            ret = self.pick(["str", "str", "bool", "str | None", "list[str]"])
            params = [f"p{j}" for j in range(len(ps))]
            env = {**self.konsts, **dict(zip(params, ps))}
            nd = 0
            if self.p(35):
                nd = sum(1 for _ in range(self.r.randint(1, len(ps))))
                while nd and ps[len(ps) - nd] == "list[str]":
                    nd -= 1  # a list default is not a literal
                nd = min(nd, len([t for t in ps[len(ps) - nd:] if t != "list[str]"])) if nd else 0
                if any(t == "list[str]" for t in ps[len(ps) - nd:]):
                    nd = 0
            self.ndef[name] = nd
            lit = {"str": lambda: repr(self.pick(LITS)), "bool": lambda: self.pick(["True", "False"]), "str | None": lambda: "None"}
            heads = [f"{p}: {t}" + (f" = {lit[t]()}" if j >= len(ps) - nd else "") for j, (p, t) in enumerate(zip(params, ps))]
            lines.append(f"def {name}({', '.join(heads)}) -> {ret}:")
            lines += self.block(env, ret, 1, 0)
            lines.append(f"    return {self.expr(env, ret)}")
            lines.append("")
            self.defs.append((name, ps, ret))
        return "\n".join(lines), list(self.defs)


def value(rng, t):
    if t == "bool":
        return rng.random() < 0.5
    if t == "list[str]":
        return [value(rng, "str") for _ in range(rng.randint(0, 3))]
    if t == "str | None" and rng.random() < 0.3:
        return None
    pool = [ALPHABET, "ab.-: xX", WS + "a."]
    src = rng.choice(pool)
    return "".join(rng.choice(src) for _ in range(rng.randint(0, 8)))


def module(seed, i):
    rng = random.Random(f"{seed}:{i}")
    text, defs = Gen(rng).module()
    calls = [(name, tuple(value(rng, t) for t in ps), ret) for name, ps, ret in defs for _ in range(ARGS.inputs)]
    return text, defs, calls

# Bend side
# =========


def bend_str(s):
    named = {"\\": "\\\\", '"': '\\"', "\n": "\\n", "\t": "\\t", "\r": "\\r"}
    return '"' + "".join(named.get(c) or (c if " " <= c <= "~" else "\\u{%x}" % ord(c)) for c in s) + '"'


def bend_val(v, t):
    if t == "bool":
        return "True{}" if v else "False{}"
    if t == "list[str]":
        return "[" + ", ".join(bend_str(x) for x in v) + "]"
    if t == "str | None":
        return "None{}" if v is None else "Some{" + bend_str(v) + "}"
    return bend_str(v)


def enc(v, t):
    """What the harness prints for one result: code points, never an escaping convention."""
    if t == "bool":
        return "1|" if v else "0|"
    if t == "list[str]":
        return "".join("".join(f"{ord(c)} " for c in x) + ";" for x in v) + "|"
    if t == "str | None":
        return "N|" if v is None else "S " + "".join(f"{ord(c)} " for c in v) + "|"
    return "".join(f"{ord(c)} " for c in v) + "|"


HARNESS = """import Base
import ./m.bend as T

def codes(s: String) -> String:
  match s:
    case SNil{}:
      "|"
    case SCon{h, t}:
      U32.show(Char.to_u32(h)) ++ " " ++ codes(t)

def item(s: String) -> String:
  match s:
    case SNil{}:
      ";"
    case SCon{h, t}:
      U32.show(Char.to_u32(h)) ++ " " ++ item(t)

def e_str(s: String) -> String:
  codes(s)

def e_bool(b: Bool) -> String:
  match b:
    case True{}:
      "1|"
    case False{}:
      "0|"

def e_maybe(m: Maybe<&2, String>) -> String:
  match m:
    case None{}:
      "N|"
    case Some{s}:
      "S " ++ codes(s)

def e_list(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      "|"
    case Con{h, t}:
      item(h) ++ e_list(t)

"""
ENC = {"str": "e_str", "bool": "e_bool", "str | None": "e_maybe", "list[str]": "e_list"}
PTYPE = {"str": "str", "bool": "bool", "list[str]": "list[str]", "str | None": "str | None"}


def harness(calls, defs):
    sig = {n: ps for n, ps, _ in defs}
    parts = [calls[k:k + 12] for k in range(0, len(calls), 12)]
    out = [HARNESS]
    for k, part in enumerate(parts):
        body = " ++\n  ".join(
            f"{ENC[ret]}(T.{n}({', '.join(bend_val(a, t) for a, t in zip(args, sig[n]))}))"
            for n, args, ret in part)
        out.append(f"def part{k}() -> String:\n  {body}\n")
    out.append("def main() -> String:\n  " + " ++ ".join(f"part{k}()" for k in range(len(parts))) + "\n")
    return "\n".join(out)

# The property
# ============


def sh(cmd, timeout=300, **kw):
    try:
        p = subprocess.run(cmd, cwd=ROOT, env={**ENV, **kw.pop("env", {})}, capture_output=True,
                           text=True, timeout=timeout, **kw)
        return p.returncode, (p.stdout + p.stderr).strip()
    except subprocess.TimeoutExpired:
        return 124, "timeout"


CHECK = ("import * as B from './bend2/bend.ts'; const book = B.book_nil();"
         "await B.book_load(book, process.argv[1], '', new Map()); B.book_valid(book);"
         "if (book.hols + book.open) process.exit(1); console.log('All terms check.');")


def oracle(text, calls):
    """Per call: ('ok', encoded) or ('raise', exception name)."""
    scope = {}
    exec(compile(text, "m", "exec"), scope)
    out = []
    for n, args, ret in calls:
        try:
            out.append(("ok", enc(scope[n](*[list(a) if isinstance(a, list) else a for a in args]), ret)))
        except Exception as e:  # noqa: BLE001 - the oracle's own behaviour is the data
            out.append(("raise", type(e).__name__))
    return out


def verdict(text, defs, calls, lanes, work):
    """(None, refusal message or None) when the contract holds; else ((kind, detail), None)."""
    os.makedirs(work, exist_ok=True)
    try:
        want = oracle(text, calls)
    except SyntaxError:
        return None, None
    src = os.path.join(work, "m.py")
    open(src, "w").write(text)
    rc, emitted = sh(["bun", os.path.join(OUT, "translate.js")], env={"PY_SOURCE": src, "PY_DEF": ""})
    if rc != 0 or not emitted.startswith("# Faithful translation"):
        first = next((l for l in emitted.splitlines() if l.strip()), f"exit {rc}")
        first = re.sub(r"^error Unsupported \d+ \d+ ", "", first)
        return None, re.sub(r"\b\d+:\d+(-\d+:\d+)?\b", "L:C", re.sub(r"\b[fp]\d\b", "_", first))[:110]
    raised = [(c, w[1]) for c, w in zip(calls, want) if w[0] == "raise"]
    if raised:
        (n, args, _), exc = raised[0]
        return ("EMITTED-A-PARTIAL-DEF", f"CPython raises {exc} on {n}{args!r}, the translation is total"), None
    open(os.path.join(work, "m.bend"), "w").write(emitted)
    test = os.path.join(work, "t.bend")
    open(test, "w").write(harness(calls, defs))
    expect = '"' + "".join(w[1] for w in want) + '"'  # main's String prints quoted
    rc, got = sh(["bun", "-e", CHECK, os.path.join(work, "m.bend")])
    if rc != 0 or got != "All terms check.":
        return ("C1-EMITTED-DOES-NOT-CHECK", got.splitlines()[:3]), None
    for lane in lanes:
        if lane == "interp":
            rc, got = sh(["bun", "bend2/main.ts", test])
        else:
            target = os.path.join(work, "t.js" if lane == "js" else "t")
            brc, log = sh(["bun", "bend2/main.ts", test, "-o", target], timeout=900)
            if brc != 0:
                return (f"BUILD-FAILS-{lane}", log[:300]), None
            rc, got = sh(["bun", target] if lane == "js" else [target, "--gpu", "off"])
        if got != expect:
            k = next((j for j in range(min(len(got), len(expect))) if got[j] != expect[j]), 0)
            return (f"C2-{lane}", f"exit {rc}; cpython …{expect[max(0, k - 40):k + 60]!r} bend …{got[max(0, k - 40):k + 60]!r}"), None
    return None, None


def shrink(text, defs, calls, lanes, kind, work):
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        if lines[i].startswith("def ") or re.match(r"\s+return ", lines[i]) and i + 1 < len(lines) and lines[i + 1] == "":
            i += 1  # a def's header and its final return keep the module well-formed
            continue
        trial = "\n".join(lines[:i] + lines[i + 1:]) + "\n"
        got, _ = verdict(trial, defs, calls, lanes, work)
        if got is not None and got[0] == kind:
            lines = lines[:i] + lines[i + 1:]
        else:
            i += 1
    return "\n".join(lines) + "\n"


def main():
    global ARGS
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=200)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--inputs", type=int, default=12, help="generated calls per def")
    ap.add_argument("--interp", type=int, default=0, help="also run the interpreter on every k-th module")
    ap.add_argument("--show", type=int, default=-1, help="print module i and exit")
    ARGS = ap.parse_args()
    if ARGS.show >= 0:
        print(module(ARGS.seed, ARGS.show)[0], end="")
        return 0
    os.makedirs(os.path.join(OUT, "fuzz"), exist_ok=True)
    tr = os.path.join(OUT, "translate.js")
    if not os.path.exists(tr):
        rc, log = sh(["bun", "bend2/main.ts", "demos/python/translate.bend", "-o", tr], timeout=1800)
        if rc != 0:
            print(log)
            return 2

    def one(i):
        text, defs, calls = module(ARGS.seed, i)
        lanes = ["js", "c"] + (["interp"] if ARGS.interp and i % ARGS.interp == 0 else [])
        work = tempfile.mkdtemp(dir=os.path.join(OUT, "fuzz"), prefix=f"m{i}_")
        try:
            got, refused = verdict(text, defs, calls, lanes, work)
            if got is None:
                return i, None, refused
            small = shrink(text, defs, calls, lanes, got[0], work)
            with open(os.path.join(OUT, "fuzz", f"finding_{ARGS.seed}_{i}.py"), "w") as f:
                f.write(small)
            return i, (got, small), None
        finally:
            shutil.rmtree(work, ignore_errors=True)

    fails, refusals, emitted = [], {}, 0
    with ThreadPoolExecutor(ARGS.jobs) as pool:
        for fut in as_completed([pool.submit(one, i) for i in range(ARGS.n)]):
            i, bad, refused = fut.result()
            if bad:
                (kind, detail), small = bad
                fails.append(i)
                print(f"FAIL {kind} seed={ARGS.seed} i={i}: {detail}\n{small}", flush=True)
            elif refused:
                refusals[refused] = refusals.get(refused, 0) + 1
            else:
                emitted += 1
    print(f"\nEmitted and held C1+C2: {emitted}. Refused (the fragment's edge, by first diagnostic):")
    for msg, n in sorted(refusals.items(), key=lambda kv: -kv[1])[:25]:
        print(f"  {n:5d}  {msg}")
    print(f"\nTFUZZ PASS: {ARGS.n - len(fails)}, FAIL: {len(fails)}")
    return 1 if fails else 0


ARGS = None
if __name__ == "__main__":
    sys.exit(main())
