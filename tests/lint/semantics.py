#!/usr/bin/env python3
"""Independent CPython evidence for the lint specimens (empirical, not a proof).

For every tests/lint/*.bend: each embedded Python source must parse; every
`total` span in the #| block must be a FunctionDef span of the pinned oracle's
`ast`; every `unreachable` span must be a statement that follows another in a
block; every function graded `total Proven` by analyze is called on exact
built-in arguments and must terminate (return or raise) within the alarm.
Controls: `spin` and `alias` (graded Unknown) must NOT terminate, so the alarm
detects divergence and the AugAssign exclusion is shown necessary.

L2 (tests/lint/alias_*.bend): every advisory span is an oracle node span; a
function graded `ownership Proven` leaves every argument equal to its deep copy;
in alias_flag a function carries an Advisory iff it really mutates an argument
on some input (`use` is the unflagged one); alias_safe carries no Advisory and
mutates no argument. Control: `same` (total
Proven, ownership Unknown) tells shared arguments from copies, so O0's
identity exclusion is necessary.

L3 (tests/lint/coverage_*.bend): every `exhaustive` span is an oracle Match, every
`dead-case` span an oracle case pattern, in the file its report names. The domain
of the subject is read off the evaluated annotation (`typing`, not M0) and each
function is called on every value of it (other parameters sampled) under
sys.settrace: `exhaustive Proven` = a case body runs whenever the match does and
the domain printed is the oracle's; `not exhaustive: v` = v is in the domain and
no case body runs for it; `dead-case Proven` = that case's body never runs; in w.py
CPython itself refuses to compile an irrefutable case ahead of others, both. Controls: shadowed, fake,
dflt, captured and untyped (graded Unknown) fall through every case on some
input, and `guarded` both runs and skips its guarded case, so each exclusion is
necessary.

L4 (tests/lint/modules_*.bend): each unit is written as name.py to a temp dir on
sys.path (SOUNDNESS A5). Every `imports` span is an oracle Import/ImportFrom, every
`pure` span an oracle FunctionDef, of the unit its report names. The import graph
is read off `ast` and sorted by `graphlib`: `imports Proven` = every module below
is a unit, no cycle, and the import raises nothing; `import cycle p` = p walks
graph edges and the graph below has a cycle; `missing module z` = z is no unit and
the import raises ModuleNotFoundError for z; `pure Proven` = every call on sampled
arguments terminates, prints nothing and keeps its arguments. Controls: ping's
`from` cycle raises ImportError while left's plain `import` cycle imports fine
(so cycles are checked on the graph, not by importing); lack raises ImportError
(graded Unknown); app.greet (Unknown through log) prints, and so does importing
page (Unknown through noisy).
"""
import ast, contextlib, copy, glob, graphlib, importlib, io, itertools, json, os, re, shutil, signal, sys, tempfile, types, typing, warnings

warnings.simplefilter("ignore")  # `s is "a"` is a specimen

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "parser"))
import normalize  # re-executes under the pinned CPython 3.11.15 oracle, or exits

LIT = re.compile(r'"(?:\\.|[^"\\])*"')

def sources(text):
    out = []
    for m in re.finditer(r'^def (\w+)\(\) -> String:\n((?:  +".*\n)+)', text, re.M):
        out.append((m.group(1), "".join(json.loads(s) for s in LIT.findall(m.group(2)))))
    return out

def values(ann):
    if isinstance(ann, ast.Name):
        return {"str": ["", "a", "héllo wörld"], "bool": [True, False], "int": [0, 3]}[ann.id]
    if isinstance(ann, ast.Subscript):
        inner = values(ann.slice)
        return [[], inner[:1], list(inner), list(inner) * 3]
    if isinstance(ann, ast.BinOp):
        return [None] + values(ann.left)
    raise ValueError(ast.dump(ann))

class Timeout(Exception):
    pass

def alarm(*_):
    raise Timeout()

def terminates(fn, args, limit=1.0):
    signal.signal(signal.SIGALRM, alarm)
    signal.setitimer(signal.ITIMER_REAL, limit)
    try:
        fn(*args)
    except Timeout:
        return False
    except Exception:
        pass  # T0 claims termination, not successful return
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
    return True

def mutated(fn, args):
    """True/False: fn changed an argument; per-input evidence, exceptions included."""
    before = copy.deepcopy(args)
    try:
        fn(*args)
    except Exception:
        pass
    return list(args) != list(before)

def domain(t):
    """The finite value set an evaluated annotation admits, or None."""
    if t is bool:
        return [True, False]
    if t is None or t is type(None):
        return [None]
    if typing.get_origin(t) is typing.Literal:
        return list(typing.get_args(t))
    if typing.get_origin(t) in (typing.Union, types.UnionType):
        parts = [domain(a) for a in typing.get_args(t)]
        return None if any(d is None for d in parts) else sum(parts, [])
    return None

def traced(fn, args):
    """The lines of fn's own frame that run on fn(*args)."""
    lines = set()
    def tr(frame, event, arg):
        if frame.f_code is fn.__code__:
            if event == "line":
                lines.add(frame.f_lineno)
            return tr
    sys.settrace(tr)
    try:
        fn(*args)
    except Exception:
        pass
    finally:
        sys.settrace(None)
    return lines

def trials(fn, node, x):
    """(v, lines run) for every domain value v of parameter x, the others sampled."""
    d = domain(fn.__annotations__[x])
    pools = [d if a.arg == x else values(a.annotation) for a in node.args.args]
    i = [a.arg for a in node.args.args].index(x)
    return d, [(args[i], traced(fn, args)) for args in itertools.product(*pools)]

def inputs(node):
    return [copy.deepcopy(a) for a in itertools.product(*(values(a.annotation) for a in node.args.args))]

def edges(tree):
    """The modules a unit's top-level imports name (U0 and not)."""
    out = []
    for n in tree.body:
        if isinstance(n, ast.Import):
            out += [a.name for a in n.names]
        elif isinstance(n, ast.ImportFrom):
            out.append("." * n.level + (n.module or ""))
    return out

def fresh(names, mod):
    """Import mod from scratch: (exception or None, stdout)."""
    for n in names:
        sys.modules.pop(n, None)
    out = io.StringIO()
    try:
        with contextlib.redirect_stdout(out):
            importlib.import_module(mod)
    except Exception as e:
        return e, out.getvalue()
    return None, out.getvalue()

def modules(path, text, expected):
    """L4 evidence for one modules_* specimen: (failures, checks)."""
    srcs = dict(sources(text))
    units = {m: srcs[fn] for m, fn in re.findall(r'unit\("(\w+)", (\w+)\(\)\)', text)}
    trees = {m: ast.parse(s) for m, s in units.items()}
    graph = {m: edges(t) for m, t in trees.items()}
    def below(m, seen):
        for d in graph.get(m, []):
            if d not in seen:
                seen.add(d)
                below(d, seen)
        return seen
    tmp = tempfile.mkdtemp()
    for m, s in units.items():
        open(os.path.join(tmp, m + ".py"), "w").write(s)
    sys.path.insert(0, tmp)
    fails = checks = 0
    try:
        for m in re.finditer(r"(\w+)\.py:(\d+):(\d+)-(\d+):(\d+) (imports|pure) (\w+) ([^\n]*)", expected):
            mod, span, rule, grade, msg = m.group(1), tuple(map(int, m.groups()[1:5])), m.group(6), m.group(7), m.group(8)
            kinds = (ast.Import, ast.ImportFrom) if rule == "imports" else ast.FunctionDef
            nodes = {(n.lineno, n.col_offset, n.end_lineno, n.end_col_offset): n for n in trees[mod].body if isinstance(n, kinds)}
            checks += 1
            if span not in nodes:
                print(f"FAIL {path}: {rule} span {mod}.py:{span} is no oracle {rule} node"); fails += 1
                continue
            if "forged" in path or "certificate refuted" in msg or grade not in ("Proven", "Refuted"):
                continue
            reach = below(mod, {mod})
            try:
                graphlib.TopologicalSorter({n: graph.get(n, []) for n in reach}).prepare()
                cyclic = False
            except graphlib.CycleError:
                cyclic = True
            if rule == "imports" and grade == "Proven":
                err, out = fresh(units, mod)
                if cyclic or not reach <= units.keys() or err:
                    print(f"FAIL {path}: imports Proven {mod}: cyclic={cyclic}, outside={reach - units.keys()}, {err!r}, {out!r}"); fails += 1
            elif msg.startswith("import cycle "):
                p = msg[len("import cycle "):].split(" -> ")
                if p[0] != mod or not cyclic or any(b not in graph[a] for a, b in zip(p, p[1:])):
                    print(f"FAIL {path}: {mod}: no oracle cycle along {p}"); fails += 1
            elif msg.startswith("missing module "):
                z = msg.split()[2]
                err, _ = fresh(units, mod)
                if z in units or not isinstance(err, ModuleNotFoundError) or err.name != z:
                    print(f"FAIL {path}: {mod}: {z} is a unit or the import raised {err!r}"); fails += 1
            elif rule == "pure" and grade == "Proven":
                fresh(units, mod)
                node, fn = nodes[span], getattr(sys.modules[mod], nodes[span].name)
                for args in inputs(node):
                    out, before = io.StringIO(), copy.deepcopy(args)
                    with contextlib.redirect_stdout(out):
                        ok = terminates(fn, args)
                    if not ok or out.getvalue() or list(args) != list(before):
                        print(f"FAIL {path}: pure Proven {mod}.{node.name}{before}: terminated={ok}, printed {out.getvalue()!r}, args {args}"); fails += 1
            else:
                print(f"FAIL {path}: no evidence for {rule} {grade} {msg}"); fails += 1
        if path.endswith("modules_cycle.bend"):
            err, _ = fresh(units, "ping")
            if isinstance(err, ImportError) and "partially initialized" in str(err) and fresh(units, "left") == (None, ""):
                print("ok   control: ping's `from` cycle raises ImportError, left's `import` cycle imports (graph, not import, finds it)")
            else:
                print(f"FAIL control: ping raised {err!r} or left did not import"); fails += 1
        if path.endswith("modules_missing.bend"):
            err, _ = fresh(units, "lack")
            if type(err) is ImportError:
                print("ok   control: lack raises ImportError (graded Unknown: no U0 counterexample for a missing def)")
            else:
                print(f"FAIL control: lack raised {err!r}"); fails += 1
        if path.endswith("modules_impure.bend"):
            fresh(units, "app")
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                sys.modules["app"].greet("a")
            if out.getvalue() and fresh(units, "page") == (None, "loaded\n"):
                print("ok   control: app.greet prints through log.say (graded Unknown, Refuted when declared), importing page prints")
            else:
                print("FAIL control: app.greet or importing page printed nothing"); fails += 1
    finally:
        sys.path.remove(tmp)
        for n in units:
            sys.modules.pop(n, None)
        shutil.rmtree(tmp)
    return fails, checks

def main():
    fails = calls = spans = kept = hits = cov = mods = 0
    for path in sorted(glob.glob("tests/lint/*.bend")):
        text = open(path, encoding="utf-8").read()
        expected = "".join(json.loads(l[2:]) for l in text.splitlines() if l.startswith("#|"))
        defs, follows, nodes, flagged = {}, set(), set(), set()
        where = {name: py for py, name in re.findall(r'report\("(\w+\.py)", parse\((\w+)\(\)\)\)', text)}
        sites, cases, envs, refused = {}, {}, {}, {}
        for name, src in sources(text):
            tree = ast.parse(src)
            py = where.get(name, "m.py")
            env = envs[py] = {}
            try:
                compile(src, py, "exec")
            except SyntaxError as e:
                refused[py] = str(e)
            for stmt in tree.body:  # one statement at a time: `@cache` raises NameError, the rest still bind
                try:
                    with contextlib.redirect_stdout(io.StringIO()):  # noisy prints when run
                        exec(compile(ast.Module([stmt], []), path, "exec"), env)
                except Exception:
                    pass
            for node in ast.walk(tree):
                for block in ("body", "orelse", "finalbody"):
                    for s in getattr(node, block, [])[1:] if isinstance(getattr(node, block, None), list) else []:
                        follows.add((s.lineno, s.col_offset, s.end_lineno, s.end_col_offset))
                if hasattr(node, "end_col_offset"):
                    nodes.add((node.lineno, node.col_offset, node.end_lineno, node.end_col_offset))
                if isinstance(node, ast.FunctionDef):
                    defs[(node.lineno, node.col_offset, node.end_lineno, node.end_col_offset)] = (node, env)
                    for mt in (n for n in ast.walk(node) if isinstance(n, ast.Match)):
                        sites[(py, mt.lineno, mt.col_offset, mt.end_lineno, mt.end_col_offset)] = (mt, node, env)
                        for k, c in enumerate(mt.cases):
                            p = c.pattern
                            cases[(py, p.lineno, p.col_offset, p.end_lineno, p.end_col_offset)] = (mt, k, node, env)
        for m in re.finditer(r"m\.py:(\d+):(\d+)-(\d+):(\d+) (\S+) (\w+)", expected):
            span, rule, grade = tuple(map(int, m.groups()[:4])), m.group(5), m.group(6)
            spans += 1
            if rule == "total" and span not in defs:
                print(f"FAIL {path}: total span {span} is no oracle FunctionDef"); fails += 1
            if rule == "unreachable" and span not in follows:
                print(f"FAIL {path}: unreachable span {span} follows nothing"); fails += 1
            if rule in ("ownership", "alias-mutation", "alias-escape", "param-mutation"):
                if span not in (defs if rule == "ownership" else nodes):
                    print(f"FAIL {path}: {rule} span {span} is no oracle node"); fails += 1
                flagged |= {d for d in defs if grade == "Advisory" and d[0] <= span[0] <= d[2]}
            if rule == "ownership" and grade == "Proven" and "forged" not in path and span in defs:
                node, env = defs[span]
                for args in inputs(node):
                    kept += 1
                    if mutated(env[node.name], args):
                        print(f"FAIL {path}: ownership Proven {node.name}{args} mutated an argument"); fails += 1
            if rule == "total" and grade == "Proven" and "forged" not in path and span in defs:
                node, env = defs[span]
                for args in itertools.product(*(values(a.annotation) for a in node.args.args)):
                    calls += 1
                    if not terminates(env[node.name], args):
                        print(f"FAIL {path}: Proven {node.name}{args} did not terminate"); fails += 1
        for m in re.finditer(r"(\w+\.py):(\d+):(\d+)-(\d+):(\d+) (exhaustive|dead-case) (\w+) (.*)", expected):
            span, rule, grade, msg = (m.group(1), *map(int, m.groups()[1:5])), m.group(6), m.group(7), m.group(8)
            spans += span[0] != "m.py"  # m.py spans are counted by the loop above
            if span not in (sites if rule == "exhaustive" else cases):
                print(f"FAIL {path}: {rule} span {span} is no oracle {'Match' if rule == 'exhaustive' else 'case pattern'}"); fails += 1
                continue
            if "forged" in path or grade not in ("Proven", "Refuted") or "certificate refuted" in msg:
                continue
            mt, k, node, env = (*sites[span][:1], None, *sites[span][1:]) if rule == "exhaustive" else cases[span]
            if node.name not in env:
                # only an irrefutable unguarded case ahead of others: it catches every value, the rest are dead
                if "makes remaining patterns unreachable" not in refused.get(span[0], ""):
                    print(f"FAIL {path}: {node.name} did not compile: {refused.get(span[0])}"); fails += 1
                continue
            d, runs = trials(env[node.name], node, mt.subject.id)
            shown = "{" + ", ".join(map(repr, d)) + "}"
            bodies = [c.body[0].lineno for c in mt.cases]
            if grade == "Proven" and shown not in msg:
                print(f"FAIL {path}: {node.name}: the oracle domain is {shown}: {msg}"); fails += 1
            for v, lines in runs:
                cov += 1
                ran = mt.lineno in lines and any(b in lines for b in bodies)
                if rule == "exhaustive" and grade == "Proven" and mt.lineno in lines and not ran:
                    print(f"FAIL {path}: exhaustive Proven {node.name}: {v!r} ran no case"); fails += 1
                if rule == "exhaustive" and grade == "Refuted" and msg == f"not exhaustive: {v!r} matches no case" and ran:
                    print(f"FAIL {path}: {node.name}: {v!r} is claimed to match no case but ran one"); fails += 1
                if rule == "dead-case" and grade == "Proven" and bodies[k] in lines:
                    print(f"FAIL {path}: dead-case Proven {node.name} case {k} ran on {v!r}"); fails += 1
            if rule == "exhaustive" and grade == "Refuted" and not any(msg == f"not exhaustive: {v!r} matches no case" for v in d):
                print(f"FAIL {path}: {node.name}: the counterexample is outside the oracle domain {shown}: {msg}"); fails += 1
        if "modules_" in path:
            f, n = modules(path, text, expected)
            fails, mods = fails + f, mods + n
        if path.endswith("coverage_dead.bend"):
            if "makes remaining patterns unreachable" in refused.get("w.py", ""):
                print(f"ok   control: CPython refuses w.py: {refused['w.py']}")
            else:
                print("FAIL control: CPython compiles w.py"); fails += 1
        if path.endswith("coverage_missing.bend"):
            if envs["m.py"]["guarded"](True, True) == 1 and envs["m.py"]["guarded"](True, False) == 2:
                print("ok   control: guarded True runs its case or none, by the guard (graded Unknown)")
            else:
                print("FAIL control: guarded does not depend on its guard"); fails += 1
        if path.endswith("coverage_unknown.bend"):
            for py, name, args in (("n.py", "shadowed", (2,)), ("n.py", "fake", ("b",)), ("m.py", "dflt", ()),
                                   ("m.py", "captured", (True, 5)), ("m.py", "untyped", (2,))):
                if envs[py][name](*args) is None:
                    print(f"ok   control: {name}{args} falls through every case (graded Unknown)")
                else:
                    print(f"FAIL control: {name}{args} reached a case"); fails += 1
        if path.endswith("alias_flag.bend") or path.endswith("alias_safe.bend"):
            for span, (node, env) in defs.items():
                real = any(mutated(env[node.name], a) for a in inputs(node))
                if real != (span in flagged) or (real and path.endswith("alias_safe.bend")):
                    print(f"FAIL {path}: {node.name} flagged={span in flagged}, mutates an argument={real}"); fails += 1
                hits += 1
        if path.endswith("alias_boundary.bend"):
            same, xs = defs[(1, 0, 2, 19)][1]["same"], ["a"]
            if same(xs, xs) and not same(list(xs), list(xs)):
                print("ok   control: same tells shared from copied arguments (ownership Unknown)")
            else:
                print("FAIL control: same does not observe sharing"); fails += 1
        if path.endswith("totality_unknown.bend"):
            env = defs[(1, 0, 4, 12)][1]
            for name, args in (("spin", ("a",)), ("alias", (["a"],))):
                if terminates(env[name], args, 0.2):
                    print(f"FAIL control: {name} terminated; the alarm detects nothing"); fails += 1
                else:
                    print(f"ok   control: {name} diverges under CPython (graded Unknown)")
    print(f"semantics: {spans} spans against the oracle, {calls} Proven calls terminated, {kept} ownership-Proven calls kept "
          f"their arguments, {hits} alias controls, {cov} coverage calls, {mods} module verdicts, {fails} failures")
    return 1 if fails or not calls else 0

if __name__ == "__main__":
    sys.exit(main())
