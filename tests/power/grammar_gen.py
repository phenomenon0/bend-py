#!/usr/bin/env python3
# The oracle for grammar.bend: prints the whole fixture.
#
# Two independent authorities, and the generator refuses to emit a row either
# one disagrees with:
#
#   1. CPython's json.loads decides accept/reject for every document here. It
#      shares no code and no design with the PDA below, so a grammar that is
#      wrong about 01, or 1., or a trailing comma, cannot reach the fixture.
#   2. The mask is computed here by *brute force* -- all 256 bytes stepped and
#      the survivors collected -- which is the opposite derivation from the
#      module's, where the mask is read off the node. A `pin` row prints both
#      of Bend's answers side by side against this one, so three derivations
#      have to agree for the row to pass.
#
# The corpus is ASCII: the grammar is a byte grammar, and UTF-8 well-formedness
# inside a string is deliberately not its job (see the lane report).
import json

WS = {9, 10, 13, 32}
DIG = set(range(48, 58))
HEX = DIG | set(range(65, 71)) | set(range(97, 103))
ESCCH = set(b'"\\/bfnrtu')
DOTE = {46, 101, 69}
EONLY = {101, 69}
SIGN = {43, 45}
ACCEPT = {"fin", "zero", "int", "frac", "expd"}
DEAD = ("dead", 0, (), 0)
LIT = {
    "t.r": (114, "t.u"),
    "t.u": (117, "t.e"),
    "t.e": (101, None),
    "f.a": (97, "f.l"),
    "f.l": (108, "f.s"),
    "f.s": (115, "f.e"),
    "f.e": (101, None),
    "n.u": (117, "n.l"),
    "n.l": (108, "n.l2"),
    "n.l2": (108, None),
}
UESC = {"u1": "u2", "u2": "u3", "u3": "u4", "u4": "str"}


def go(s, n, f=None):
    return (n, s[1], s[2], s[3] if f is None else f)


def after(s):
    return ("fin" if s[1] == 0 else "sep", s[1], s[2], 0)


def push(s, n, obj):
    return DEAD if s[1] >= 64 else (n, s[1] + 1, s[2] + (obj,), s[3])


def pop(s):
    d = s[1] - 1
    return ("fin" if d == 0 else "sep", d, s[2][:d], 0)


def top(s):
    return s[1] > 0 and s[2][s[1] - 1]


def sh_val(s, c):
    if c in WS:
        return s
    if c == 34:
        return go(s, "str", 0)
    if c == 45:
        return go(s, "min")
    if c in DIG:
        return go(s, "zero" if c == 48 else "int")
    if c == 116:
        return go(s, "t.r")
    if c == 102:
        return go(s, "f.a")
    if c == 110:
        return go(s, "n.u")
    if c == 91:
        return push(s, "vale", False)
    if c == 123:
        return push(s, "keye", True)
    return DEAD


def sh_key(s, c):
    if c in WS:
        return s
    return go(s, "str", 1) if c == 34 else DEAD


def shift(s, c):
    n = s[0]
    if n == "dead":
        return DEAD
    if n == "val":
        return sh_val(s, c)
    if n == "vale":
        return pop(s) if c == 93 else sh_val(s, c)
    if n == "keye":
        return pop(s) if c == 125 else sh_key(s, c)
    if n == "key":
        return sh_key(s, c)
    if n == "colon":
        if c in WS:
            return s
        return go(s, "val") if c == 58 else DEAD
    if n == "sep":
        if c in WS:
            return s
        if c == 44:
            return go(s, "key" if top(s) else "val")
        return pop(s) if c == (125 if top(s) else 93) else DEAD
    if n == "fin":
        return s if c in WS else DEAD
    if n == "str":
        if c == 34:
            return go(s, "colon", 0) if s[3] else after(s)
        if c == 92:
            return go(s, "esc")
        return DEAD if c < 32 else s
    if n == "esc":
        if c not in ESCCH:
            return DEAD
        return go(s, "u1" if c == 117 else "str")
    if n in UESC:
        return go(s, UESC[n]) if c in HEX else DEAD
    if n == "min":
        if c == 48:
            return go(s, "zero")
        return go(s, "int") if c in DIG else DEAD
    if n == "zero":
        if c == 46:
            return go(s, "dot")
        return go(s, "exp") if c in EONLY else DEAD
    if n == "int":
        if c in DIG:
            return s
        if c == 46:
            return go(s, "dot")
        return go(s, "exp") if c in EONLY else DEAD
    if n == "dot":
        return go(s, "frac") if c in DIG else DEAD
    if n == "frac":
        if c in DIG:
            return s
        return go(s, "exp") if c in EONLY else DEAD
    if n == "exp":
        if c in SIGN:
            return go(s, "esgn")
        return go(s, "expd") if c in DIG else DEAD
    if n == "esgn":
        return go(s, "expd") if c in DIG else DEAD
    if n == "expd":
        return s if c in DIG else DEAD
    want, nxt = LIT[n]
    if c != want:
        return DEAD
    return after(s) if nxt is None else go(s, nxt)


def cont(n, c):
    # a number is the one token with no closing byte, so it ends at the first
    # byte that cannot continue it and that byte is then the separator
    if n == "zero":
        return c in DOTE
    if n == "int":
        return c in DIG or c in DOTE
    if n == "frac":
        return c in DIG or c in EONLY
    if n == "expd":
        return c in DIG
    return True


def step(s, c):
    return shift(s if cont(s[0], c) else after(s), c)


def live(s):
    return s[0] != "dead"


def done(s):
    return s[1] == 0 and s[0] in ACCEPT


def run(doc, s=("val", 0, (), 0)):
    for ch in doc.encode():
        s = step(s, ch)
    return s


def brute(s):
    """The mask the hard way: every byte stepped, the survivors kept. The
    module derives the same set from the node alone -- that is the law."""
    return [c for c in range(256) if live(step(s, c))]


def ranges(cs):
    out, i = "", 0
    while i < len(cs):
        j = i
        while j + 1 < len(cs) and cs[j + 1] == cs[j] + 1:
            j += 1
        out += " %d" % cs[i] if i == j else " %d-%d" % (cs[i], cs[j])
        i = j + 1
    return out


def show(s):
    return "%s/%d%s" % (s[0], s[1], "k" if s[3] else "")


def lit(doc):
    out = ""
    for ch in doc:
        out += {'"': '\\"', "\\": "\\\\", "\t": "\\t", "\n": "\\n", "\r": "\\r"}.get(
            ch, ch
        )
    return '"' + out + '"'


def loads_ok(doc):
    try:
        json.loads(doc, parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
        return True
    except (ValueError, RecursionError):
        return False


rows, want = [], []


def row(call, text):
    rows.append(call)
    want.append(text)


# -- the corpus --------------------------------------------------------------
# valid documents first, then the ways each shape is wrong. Every one of them is
# put to json.loads below, so this list is a claim about JSON and not about the
# PDA above.

GOOD = [
    "1",
    "0",
    "-0",
    "-1",
    "12",
    "1.5",
    "0.5",
    "-0.5",
    "1e2",
    "1E2",
    "1e+2",
    "1e-2",
    "0e0",
    "1.5e10",
    "-12.25E-3",
    '""',
    '"a"',
    '"a b"',
    '"\\""',
    '"\\\\"',
    '"\\/"',
    '"\\b\\f\\n\\r\\t"',
    '"\\u00e9"',
    '"\\uD83D\\uDE00"',
    "true",
    "false",
    "null",
    "[]",
    "{}",
    "[1]",
    "[1,2]",
    '["a",1,true]',
    '{"a":1}',
    '{"a":1,"b":2}',
    '{"a":{"b":[1,{"c":null}]}}',
    "[[[]]]",
    "  1  ",
    " [ 1 , 2 ] ",
    '{ "a" : 1 }',
    "[{}]",
    "[[],[]]",
    '{"":0}',
    '{"a":[],"b":{}}',
    "[0,-0,1e0]",
    "\t[\n1\r]\t",
]

BAD = [
    "",
    " ",
    "01",
    "-",
    "1.",
    ".5",
    "1e",
    "1e+",
    "+1",
    "00",
    "0x1",
    "1 2",
    "[",
    "]",
    "{",
    "}",
    "[,]",
    "[1,]",
    "[1 2]",
    '{"a"}',
    '{"a":}',
    "{:1}",
    '{"a":1,}',
    "{a:1}",
    "{'a':1}",
    "[1}",
    '{"a":1]',
    "tru",
    "truu",
    "fals",
    "nul",
    "nulll",
    "TRUE",
    '"',
    '"a',
    '"\\x"',
    '"\\u12"',
    '"\\u12g4"',
    '"a\tb"',
    '"a\nb"',
    "[]]",
    "{}}",
    "nan",
    "Infinity",
    "-Infinity",
    "NaN",
    "[1,,2]",
    '{"a" 1}',
    "--1",
    "1..2",
    "1e2e3",
]


def end(s):
    return "%s done=%s live=%s" % (
        show(s),
        "Y" if done(s) else "n",
        "Y" if live(s) else "n",
    )


for d in GOOD + BAD:
    s = run(d)
    assert done(s) == loads_ok(d), (d, show(s), loads_ok(d))
    row("doc(%s)" % lit(d), end(s))

# -- the law: the derived mask against the brute-forced one ------------------
# one prefix a distinct reachable state, so every node the corpus can reach has
# its mask pinned against the 256 steps it is supposed to summarise

seen, picks = {}, []
for d in GOOD + BAD:
    s = ("val", 0, (), 0)
    for i, ch in enumerate(d.encode()):
        s = step(s, ch)
        pre = d[: i + 1]
        if s not in seen and live(s) and all(32 <= ord(c) < 127 for c in pre):
            seen[s] = pre
            picks.append((s, pre))
# extra prefixes for the states a short corpus does not reach: every literal
# chain, a key string, a deep stack, and an object separator
for pre in [
    "tr",
    "tru",
    "fa",
    "fal",
    "fals",
    "n",
    "nu",
    "nul",
    '{"a',
    '{"a"',
    '{"a":',
    '{"a":1',
    '{"a":1,',
    "[[[[1",
    '"\\',
    '"\\u',
    '"\\u0',
    '"\\u00',
    '"\\u00e',
    "[1,2",
    '{"a":{',
    "-",
    "1.",
    "1e",
    "1e+",
    "0",
    "0.",
    "0.5",
    "[0",
    # the ceiling, in both nodes that start a value: push kills `[` and `{`
    # here, so the mask must not offer them
    "[" * 64,
    "[" * 63 + '{"a":',
]:
    s = run(pre)
    if live(s) and s not in seen:
        seen[s] = pre
        picks.append((s, pre))

for s, pre in picks:
    m = ranges(brute(s))
    row("pin(at(%s))" % lit(pre), "%s |%s |%s |" % (show(s), m, m))

# a dead state allows nothing, and the two derivations have to agree on that too
m = ranges(brute(DEAD))
row("pin(at(%s))" % lit("[,"), "%s |%s |%s |" % (show(DEAD), m, m))

# -- forking: the state is a value, so a rollback is not an operation --------
# the parent is printed, then three continuations taken *from the same value*,
# then the parent again. A state that had to be rebuilt to be reused, or that a
# continuation mutated, cannot print the first and last fields equal.

FORKS = [
    ('{"a":', ["1", '"x"', "["]),
    ("[1,", ["2]", "tru", "{"]),
    ('{"a":1', [",", "}", "e"]),
    ("", ["{", "[", "1"]),
    ("[[", ["]", "1", "]]"]),
    ('"ab', ['c"', "\\\\", '"']),
]
for pre, conts in FORKS:
    s = run(pre)
    ends = " ".join(show(run(c, s)) for c in conts)
    row(
        "fork3(at(%s), %s, %s, %s)"
        % (lit(pre), lit(conts[0]), lit(conts[1]), lit(conts[2])),
        "%s -> %s -> %s" % (show(s), ends, show(s)),
    )

# -- the 64-container ceiling ------------------------------------------------
# refused, not truncated: the 65th open bracket is dead, and json.loads agrees
# the document is otherwise fine

for n in [1, 32, 63, 64, 65]:
    d = "[" * n + "1" + "]" * n
    s = run(d)
    if n <= 64:
        assert done(s) and loads_ok(d), n
    else:
        # the ceiling is a refusal, not a truncation: json.loads takes this one
        assert not live(s) and loads_ok(d), n
    row("deep(%dn)" % n, end(s))

print(
    """# Grammar against CPython (grammar_gen.py prints this file). A `doc` row is one
# document fed whole -- json.loads decided accept or reject for every one of
# them and the generator refuses to print a row it disagrees with. A `pin` row
# is the claim the lane exists for: the mask the module *derives* from its node,
# then the mask *brute-forced* by stepping all 256 bytes, printed side by side.
# They are different code paths, so a row where they differ is the constrained
# decoding bug caught in the act. A `fork` row takes three continuations from
# one state value and then prints that state again unchanged.
import Base
import ../../power/bytes.bend as Bytes
import ../../power/grammar.bend as Gr

# ascii only: this is a byte grammar and utf-8 inside a string is not its job
def of.push(c: Char, b: Bytes.Bytes) -> Bytes.Bytes:
  match c:
    case Chr{code}:
      Bytes.push(b, code)

def of.go(s: String, b: Bytes.Bytes) -> Bytes.Bytes:
  match s:
    case SNil{}:
      b
    case SCon{h, t}:
      of.go(t, of.push(h, b))

def of(s: String) -> Bytes.Bytes:
  of.go(s, Bytes.new())

def yn(t: Bool) -> String:
  match t:
    case True{}:
      "Y"
    case False{}:
      "n"

# the Bytes is dropped here and the St kept: affine lets the document go, Data
# lets the state stay
def stt(w: Gr.Walk) -> Gr.St:
  match w:
    case Gr.Walk{b, s}:
      s

def at(d: String) -> Gr.St:
  stt(Gr.run(of(d), Gr.start()))

def on(+s: Gr.St, d: String) -> Gr.St:
  stt(Gr.run(of(d), s))

def end(+s: Gr.St) -> String:
  Gr.show(s) ++ " done=" ++ yn(Gr.done(s)) ++ " live=" ++ yn(Gr.live(s))

def doc(d: String) -> String:
  end(at(d))

# the mask the hard way: 256 steps, one bit a survivor. The module never does
# this -- it reads the node -- which is exactly why the two are worth printing
# in the same row.
def probe.b(+acc: U32, +j: U32, hit: Bool) -> U32:
  match hit:
    case True{}:
      U32.or(acc, U32.shln(1, U32.to_nat(j)))
    case False{}:
      acc

def probe.w(k: Nat, +c: U32, +j: U32, +s: Gr.St, acc: U32) -> U32:
  match k:
    case 0n:
      acc
    case 1n++p:
      probe.w(p, U32.inc(c), U32.inc(j), s, probe.b(acc, j, Gr.live(Gr.step(s, c))))

def probe(+s: Gr.St) -> Gr.Mask:
  Gr.Mask{probe.w(32n, 0, 0, s, 0), probe.w(32n, 32, 0, s, 0),
    probe.w(32n, 64, 0, s, 0), probe.w(32n, 96, 0, s, 0),
    probe.w(32n, 128, 0, s, 0), probe.w(32n, 160, 0, s, 0),
    probe.w(32n, 192, 0, s, 0), probe.w(32n, 224, 0, s, 0)}

def pin(+s: Gr.St) -> String:
  Gr.show(s) ++ " |" ++ Gr.Mask.show(Gr.mask(s)) ++ " |" ++ Gr.Mask.show(probe(s)) ++ " |"

# one parent value, three continuations, and the parent again
def fork3(+s: Gr.St, a: String, b: String, c: String) -> String:
  Gr.show(s) ++ " -> " ++ Gr.show(on(s, a)) ++ " " ++ Gr.show(on(s, b)) ++ " " ++ Gr.show(on(s, c)) ++ " -> " ++ Gr.show(s)

def nest(k: Nat, acc: String) -> String:
  match k:
    case 0n:
      acc
    case 1n++p:
      nest(p, "[" ++ acc ++ "]")

def deep(k: Nat) -> String:
  end(at(nest(k, "1")))

def main() -> IO(Unit):
  do IO<Unit>:"""
)
for r in rows:
    print("    IO.print(%s)" % r)
for w in want:
    print("#|" + w)
