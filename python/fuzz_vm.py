"""The VM's differential fuzzer: random programs in (and just past) the subset,
CPython 3.11.15 as the oracle, every compiled lane as the suspect.

  python3 demos/python/fuzz_vm.py [--n 300] [--seed 1] [--jobs 4] [--interp 0]

The property is the lane's contract, not a fixture: a program the VM runs to
exit 0 must print exactly what CPython prints and CPython must exit 0 too, and
every lane must agree byte for byte. A non-zero exit is a refusal, which is
allowed and counted, but it must be the VM's own ("vm: ..." or a compile
refusal), never the runtime dying under it ("bend: ..."). Anything else is a
finding. It is shrunk line by line while it keeps failing the same way, then
written to tests/vm/_out/fuzz/. The run prints a coverage table (what CPython
ran and the VM refused, by message) and ends `FUZZ PASS: n, FAIL: k`.
Each program is a pure function of (seed, index), so a finding replays."""

import argparse
import os
import resource
import random
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "tests", "vm", "_out")
LANES = {
    "c": lambda: [os.path.join(OUT, "vm.bin"), "--gpu", "off"],
    "js": lambda: ["bun", os.path.join(OUT, "vm.js")],
    "interp": lambda: ["bun", "bend2/main.ts", "demos/python/vm.bend"],
}

# Programs
# ========


class Gen:
    """One program. Names are typed loosely so most expressions are
    well-typed; a few percent are not, on purpose (TypeError on CPython must
    be a fault on the VM, never a value)."""

    def __init__(self, rng):
        self.r = rng
        self.lines = []
        self.vars = {}  # definitely assigned: name -> "int" | "bool" | "str" | "none"
        self.maybe = {}  # assigned on some path only
        self.funcs = []  # (name, nparams, the type it returns)
        self.loops = 0

    def p(self, pct):
        return self.r.random() * 100 < pct

    def pick(self, xs):
        return self.r.choice(xs)

    # Literals
    def int_lit(self):
        if self.p(0.1):
            return "07"  # a SyntaxError in Python 3: the VM must not take it
        if self.p(6):
            return self.pick(["0x1f", "0XbeEf", "0o17", "0b101", "1_000", "00",
                              "281474976710655", "281474976710656"])
        return str(self.pick([0, 1, 2, 3, 5, 7, 10, 12, 100, self.r.randint(0, 50)]))

    def str_lit(self):
        # quotes appear only escaped, so either delimiter is safe; a raw
        # literal takes no backslash at all
        raw = self.p(5)
        plain = ["a", "b", "z", " ", "0", "hi", "é", ""]
        esc = ["\\n", "\\t", "\\\\", "\\'", '\\"', "\\x41", "\\101"]
        body = "".join(self.pick(plain if raw else plain + esc)
                       for _ in range(self.r.randint(0, 4)))
        q = self.pick(["'", '"'])
        return ("r" if raw else "") + q + body + q

    # Expressions, by the type they should have
    def names(self, t):
        return [n for n, k in self.vars.items() if k == t]

    def expr(self, t, d=0):
        if d > 2 or self.p(30):
            return self.leaf(t)
        if self.p(1.5):  # deliberately off-type
            t = self.pick(["int", "bool", "str", "none"])
        if t == "int":
            k = self.r.randint(0, 9)
            if k <= 4:
                op = self.pick(["+", "*", "-", "//", "%", "+", "*"])
                rhs = self.expr("int", d + 1)
                if op in ("//", "%") and self.p(75):
                    rhs = str(self.r.randint(1, 9))  # mostly a divisor that cannot be 0
                return f"({self.expr('int', d + 1)} {op} {rhs})"
            if k == 5:
                return f"len({self.expr('str', d + 1)})"
            if k == 6 and self.funcs:
                return self.call(d)
            if k == 7:
                return f"({self.pick(['True', 'False'])} + {self.expr('int', d + 1)})"
            if k == 8:
                return f"({self.expr('int', d + 1)} {self.pick(['and', 'or'])} {self.expr('int', d + 1)})"
            return self.ifexp("int", d)
        if t == "bool":
            k = self.r.randint(0, 5)
            if k <= 2:
                a = self.pick(["int", "int", "str", "bool", "none"])
                b = a if self.p(92) else self.pick(["int", "str", "none"])
                op = self.pick(["<", "<=", ">", ">=", "==", "!="])
                if "none" in (a, b) and self.p(90):
                    op = self.pick(["==", "!="])
                chain = f" {self.pick(['<', '=='])} {self.expr(b, d + 1)}" if self.p(3) else ""
                return f"({self.expr(a, d + 1)} {op} {self.expr(b, d + 1)}{chain})"
            if k == 3:
                return f"(not {self.expr(self.pick(['bool', 'int', 'str', 'none']), d + 1)})"
            # and/or yield an operand, not a bool: mixed types now and then,
            # where only truth is asked of the result
            op = self.pick(["and", "or"])
            if self.p(15):
                return f"({self.expr(self.pick(['int', 'str']), d + 1)} {op} {self.expr(self.pick(['bool', 'int', 'str', 'none']), d + 1)})"
            return f"({self.expr('bool', d + 1)} {op} {self.expr('bool', d + 1)})"
        if t == "str":
            k = self.r.randint(0, 6)
            if k <= 1:
                return f"({self.expr('str', d + 1)} + {self.expr('str', d + 1)})"
            if k == 2:
                i = self.expr("int", d + 1) if self.p(20) else str(self.r.randint(0, 2))
                pad = "" if self.p(25) else ' + "xyz"'  # mostly in range
                return f"({self.expr('str', d + 1)}{pad})[{i}]"
            if k == 3:
                lo = self.expr("int", d + 1) if self.p(70) else ""
                hi = self.expr("int", d + 1) if self.p(70) else ""
                return f"{self.expr('str', d + 1)}[{lo}:{hi}]"
            if k == 4:
                n = str(self.r.randint(0, 4)) if self.p(85) else self.expr("int", d + 1)
                return f"({self.expr('str', d + 1)} * {n})" if self.p(50) else f"({n} * {self.expr('str', d + 1)})"
            return self.ifexp("str", d)
        return self.leaf("none")

    def ifexp(self, t, d):
        return f"({self.expr(t, d + 1)} if {self.expr('bool', d + 1)} else {self.expr(t, d + 1)})"

    def leaf(self, t):
        own = self.names(t)
        if own and self.p(55):
            return self.pick(own)
        maybe = [n for n in self.maybe if self.maybe[n] == t]
        if maybe and self.p(4):  # assigned on some path only: may be unbound
            return self.pick(maybe)
        if self.p(0.4):
            return self.pick(["undefined_name", "print"])  # NameError / a function value
        return {"int": self.int_lit, "str": self.str_lit,
                "bool": lambda: self.pick(["True", "False"]),
                "none": lambda: "None"}[t]()

    def call(self, d):
        ints = [f for f in self.funcs if f[2] == "int"]
        name, n, _ = self.pick(ints if ints and self.p(97) else self.funcs)
        n = n if self.p(97) else n + 1
        return f"{name}({', '.join(self.expr('int', d + 1) for _ in range(n))})"

    # Statements
    def stmt(self, ind, depth):
        k = self.r.randint(0, 9)
        pad = "    " * ind
        if k <= 2 or depth > 2:
            t = self.pick(["int", "int", "str", "bool", "none"])
            name = self.pick(["a", "b", "c", "s", "t", "u", "x", "y"])
            if self.vars.get(name) not in (None, t) and depth > 0:
                name = name + "2"  # keep branch-local retypes from confusing the generator
            self.lines.append(f"{pad}{name} = {self.expr(t)}")
            self.vars[name] = t
        elif k == 3 and self.names("int"):
            op = self.pick(["+=", "-=", "*=", "//=", "%="])
            self.lines.append(f"{pad}{self.pick(self.names('int'))} {op} {self.expr('int')}")
        elif k == 3 and self.names("str"):
            self.lines.append(f"{pad}{self.pick(self.names('str'))} += {self.expr('str')}")
        elif k <= 5:
            args = ", ".join(self.expr(self.pick(["int", "str", "bool", "none"]))
                             for _ in range(self.r.randint(0, 3)))
            self.lines.append(f"{pad}print({args})")
        elif k == 6:
            self.lines.append(f"{pad}if {self.expr('bool')}:")
            self.block(ind + 1, depth + 1)
            if self.p(40):
                self.lines.append(f"{pad}elif {self.expr('bool')}:")
                self.block(ind + 1, depth + 1)
            if self.p(50):
                self.lines.append(f"{pad}else:")
                self.block(ind + 1, depth + 1)
        elif k == 7:
            # a loop that always ends: its counter is its own and only falls
            c = f"k{self.loops}"
            self.loops += 1
            self.lines.append(f"{pad}{c} = {self.r.randint(0, 4)}")
            self.lines.append(f"{pad}while {c} > 0:")
            self.lines.append(f"{pad}    {c} = {c} - 1")
            self.block(ind + 1, depth + 1)
        elif self.funcs:
            self.lines.append(f"{pad}{self.call(0)}")
        else:
            self.lines.append(f"{pad}pass")

    def block(self, ind, depth):
        # a branch's new names are only maybe-assigned after it
        before = dict(self.vars)
        for _ in range(self.r.randint(1, 3)):
            self.stmt(ind, depth)
        for n, t in self.vars.items():
            if n not in before:
                self.maybe[n] = t
        self.vars = before

    def func(self, i):
        name = f"f{i}"
        params = ["n", "m", "q"][: self.r.randint(0, 3)]
        saved, saved_maybe = self.vars, self.maybe
        self.vars, self.maybe = dict(saved), {}
        self.vars.update({p: "int" for p in params})
        head = f"def {name}({', '.join(params)}):"
        body_start = len(self.lines)
        self.lines.append(head)
        if params and self.p(40):
            # bounded self-recursion on its first parameter
            p0 = params[0]
            rest = ", ".join(["(" + p0 + " - 1)"] + params[1:])
            self.lines.append(f"    if {p0} <= 0:")
            self.lines.append(f"        return {self.expr('int')}")
            self.funcs.append((name, len(params), "int"))
            self.lines.append(f"    return {name}({rest}) {self.pick(['+', '*'])} {self.expr('int')}")
        else:
            self.block(1, 1)
            ret = self.pick(["int", "int", "str", "none"])
            if ret != "none" or self.p(50):
                self.lines.append(f"    return {self.expr(ret)}")
            self.funcs.append((name, len(params), ret))
        self.vars, self.maybe = saved, saved_maybe
        if self.p(3):  # a call above its def: NameError
            self.lines.insert(body_start, f"print({name}({', '.join('1' for _ in params)}))")

    def program(self):
        for i in range(self.r.randint(0, 3)):
            self.func(i)
        for _ in range(self.r.randint(2, 8)):
            self.stmt(0, 0)
        return "\n".join(self.lines) + "\n"


def program(seed, i):
    return Gen(random.Random(f"{seed}:{i}")).program()

# The property
# ============


def run(cmd, src, path, timeout=60):
    with open(path, "w") as f:
        f.write(src)
    env = dict(os.environ, PY_SOURCE=path, BEND_NO_TELEMETRY="1")
    # the oracle gets 1 GiB: a generated program may grow a string without
    # bound, and CPython's MemoryError is then its answer
    cap = (lambda: resource.setrlimit(resource.RLIMIT_AS, (1 << 30, 1 << 30))) \
        if cmd[0] == sys.executable else None
    try:
        p = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, timeout=timeout,
                           preexec_fn=cap)
        return p.returncode, p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace")
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"


def verdict(src, lanes, tag):
    """None when the contract holds; else (kind, lane, detail). Also returns
    the refusal message when the VM refused a program CPython ran."""
    path = os.path.join(OUT, "fuzz", f"{tag}.py")
    code, out, err = run([sys.executable, path], src, path, 10)
    if code == 124:
        return None, None  # CPython itself did not finish: no oracle
    seen = {}
    refused = None
    for lane in lanes:
        lc, lo, le = run(LANES[lane](), src, path.replace(".py", f".{lane}.py"))
        text = (lo + le).strip()
        seen[lane] = (lc == 0, lo if lc == 0 else "")
        if lc == 0:
            if code != 0:
                return ("RAN-WHAT-CPYTHON-REJECTS", lane, err.strip().splitlines()[-1:]), None
            if lo != out:
                return ("MISCOMPILE", lane, f"cpython {out!r} vm {lo!r}"), None
        else:
            last = text.splitlines()[-1] if text else f"exit {lc}"
            if last.startswith("bend:") or lc == 124:
                return ("RUNTIME-NOT-VM", lane, last), None
            if code == 0:
                refused = last.replace("vm: ", "").replace("error Unsupported 1 0 ", "")
    if len(set(seen.values())) > 1:
        return ("LANE-SPLIT", ",".join(lanes), repr(seen)), None
    return None, refused


def shrink(src, lanes, kind, tag):
    lines = src.splitlines()
    i = 0
    while i < len(lines):
        if re.fullmatch(r"\s*(k\d+) = \1 - 1", lines[i]):
            i += 1  # a loop's own step: without it the loop never ends
            continue
        trial = "\n".join(lines[:i] + lines[i + 1:]) + "\n"
        got, _ = verdict(trial, lanes, tag + "_s")
        if got is not None and got[0] == kind:
            lines = lines[:i] + lines[i + 1:]
        else:
            i += 1
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=300)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--interp", type=int, default=0, help="also run the interpreter on every k-th program")
    ap.add_argument("--show", type=int, default=-1, help="print program i and exit")
    a = ap.parse_args()
    if a.show >= 0:
        print(program(a.seed, a.show), end="")
        return 0
    os.makedirs(os.path.join(OUT, "fuzz"), exist_ok=True)

    def one(i):
        lanes = ["c", "js"] + (["interp"] if a.interp and i % a.interp == 0 else [])
        src = program(a.seed, i)
        got, refused = verdict(src, lanes, f"p{i}")
        if got is None:
            return i, None, refused
        small = shrink(src, lanes, got[0], f"p{i}")
        with open(os.path.join(OUT, "fuzz", f"finding_{a.seed}_{i}.py"), "w") as f:
            f.write(small)
        return i, (got, small), refused

    fails, refusals, ok = [], {}, 0
    with ThreadPoolExecutor(a.jobs) as pool:
        for done in as_completed([pool.submit(one, i) for i in range(a.n)]):
            i, bad, refused = done.result()
            if bad:
                fails.append((i, bad))
                (kind, lane, detail), small = bad
                print(f"FAIL {kind} [{lane}] seed={a.seed} i={i}: {detail}\n{small}", flush=True)
            else:
                ok += 1
                if refused:
                    refusals[refused] = refusals.get(refused, 0) + 1
    print("\nCPython ran it, the VM refused it (the subset's edge, by message):")
    for msg, n in sorted(refusals.items(), key=lambda kv: -kv[1]):
        print(f"  {n:5d}  {msg}")
    print(f"\nFUZZ PASS: {ok}, FAIL: {len(fails)}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
