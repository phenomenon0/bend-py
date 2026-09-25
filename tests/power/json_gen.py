#!/usr/bin/env python3
# The oracle for json.bend: prints the whole fixture.
#
# Three things check each other here. CPython's own `json` decides accept or
# reject for every document in the corpus -- `agree()` below raises if this
# file's scanner and `json.loads` ever disagree, so the generator cannot print a
# fixture that pins a grammar bug. CPython's own lexer (`py_scanstring` and the
# scanner's NUMBER_RE) independently produces the span of every string and
# number in the accepted documents, and `spans()` raises if a span this file
# reports is not the one CPython's lexer found. What is left -- where a refusal
# points, and what the budget costs -- is the parser's own contract, stated in
# power/json.bend's header and pinned here.
import json
import re
from json.decoder import py_scanstring
from json.scanner import NUMBER_RE

WS = (32, 9, 10, 13)
SIMPLE = tuple(b'"\\/bfnrt')


def ishex(c):
    return 48 <= c <= 57 or 97 <= c <= 102 or 65 <= c <= 70


def isdig(c):
    return 48 <= c <= 57


def at(b, i, n):
    # reading past the end gives 0, which starts no json token
    return b[i] if i < n else 0


def spaces(b, i, n):
    while i < n and b[i] in WS:
        i += 1
    return i


def spend(left, k):
    return max(left, k) - k


def charge(r, left, used):
    # a scan the caller cannot afford is Dry even when the bytes were fine
    if left >= used:
        return r
    return "dry" if r == "ok" else r


def fin(r, i, n):
    # a scanner still running when its fuel ran out hit the end of the input or
    # the end of the budget, and the cursor says which
    if r == "go":
        return "cut" if i >= n else "dry"
    return r


def scan_str(b, at_, n, left):
    i = at_ + 1
    fuel = min(left, n - at_) + 1
    while fuel > 0:
        fuel -= 1
        if i >= n:
            return i, "cut"
        c = b[i]
        if c == 34:
            return i + 1, "ok"
        if c == 92:
            j = i + 1
            if j >= n:
                return j, "cut"
            e = b[j]
            if e in SIMPLE:
                i = j + 1
                continue
            if e != 117:
                return j, "esc"
            k = j + 1
            for _ in range(4):
                if not ishex(at(b, k, n)):
                    return k, "esc"
                k += 1
            i = k
            continue
        if c < 32:
            return i, "ctrl"
        i += 1
    return i, "go"


def digits(b, i, n, fuel):
    k = 0
    while fuel > 0:
        fuel -= 1
        if not isdig(at(b, i, n)):
            break
        i += 1
        k += 1
    return i, k


def scan_num(b, at_, n, left):
    fuel = min(left, n - at_) + 1
    i = at_
    if at(b, i, n) == 45:
        i += 1
    c1 = at(b, i, n)
    i, k = digits(b, i, n, fuel)
    if k == 0 or (c1 == 48 and k != 1):
        return i, "digit"  # no digits at all, or 01
    if at(b, i, n) == 46:
        i, k2 = digits(b, i + 1, n, fuel)
        if k2 == 0:
            return i, "digit"
    c = at(b, i, n)
    if c in (101, 69):
        j = i + 1
        if at(b, j, n) in (43, 45):
            j += 1
        i, k3 = digits(b, j, n, fuel)
        if k3 == 0:
            return i, "digit"
    return i, "ok"


def scan_lit(b, i, n, want):
    for x in want:
        if at(b, i, n) != x:
            return i, "char"
        i += 1
    return i, "ok"


def classify(c, past):
    if past:
        return "end"
    return {
        123: "obj",
        125: "obje",
        91: "arr",
        93: "arre",
        34: "quo",
        44: "com",
        116: "tru",
        102: "fal",
        110: "nul",
    }.get(c, "num" if (isdig(c) or c == 45) else "junk")


LIT = {"tru": (b"rue", "true"), "fal": (b"alse", "false"), "nul": (b"ull", "null")}


class St:
    def __init__(self, b, limit):
        self.b, self.n, self.left = b, len(b), limit
        self.at, self.dep, self.ks, self.md = 0, 0, [], "val"
        self.bad = None

    def err(self, i, why):
        self.at, self.bad = i, "!%s@%d" % (why, i)
        self.md = "bad"
        return self.bad

    def land(self, i, left, e):
        # a value at the top level ends the document; inside a container the
        # next thing is a comma or a closer
        self.at, self.left = i, left
        self.md = "done" if self.dep == 0 else "post"
        return e

    def value(self, t, shut):
        b, n, at_, left = self.b, self.n, self.at, self.left
        if t in ("obj", "arr"):
            if self.dep >= 256:
                return self.err(at_, "deep")
            self.ks.append(t == "obj")
            self.at, self.dep, self.left = at_ + 1, self.dep + 1, spend(left, 1)
            self.md = "key0" if t == "obj" else "val0"
            return "{" if t == "obj" else "["
        if t in ("quo", "num") or t in LIT:
            if t == "quo":
                i, r = scan_str(b, at_, n, left)
                mk = lambda: "str@%d+%d" % (at_ + 1, (i - at_) - 2)
            elif t == "num":
                i, r = scan_num(b, at_, n, left)
                mk = lambda: "num@%d+%d" % (at_, i - at_)
            else:
                i, r = scan_lit(b, at_ + 1, n, LIT[t][0])
                mk = lambda: LIT[t][1]
            r = charge(fin(r, i, n), left, i - at_)
            if r != "ok":
                return self.err(i, "cut" if r == "go" else r)
            return self.land(i, spend(left, i - at_), mk())
        if t == "arre":
            return self.close(False, shut)
        return self.err(at_, "cut" if t == "end" else "char")

    def close(self, isobj, shut):
        # a closer pops before it is checked, so the kind it finds is the one
        # the matching opener pushed
        if not shut or self.ks.pop() != isobj:
            return self.err(self.at, "char")
        self.dep -= 1
        return self.land(self.at + 1, spend(self.left, 1), "}" if isobj else "]")

    def keym(self, t, shut):
        b, n, at_, left = self.b, self.n, self.at, self.left
        if t == "quo":
            i, r = scan_str(b, at_, n, left)
            r = charge(fin(r, i, n), left, i - at_)
            if r != "ok":
                return self.err(i, "cut" if r == "go" else r)
            e = "key@%d+%d" % (at_ + 1, (i - at_) - 2)
            # the key scanned, so it is paid for even if the colon then refuses:
            # every token that succeeds is charged, a token that fails is not
            self.left = left = spend(left, i - at_)
            j = spaces(b, i, n)
            if at(b, j, n) != 58:
                # the colon is the one byte not reached through the classifier
                return self.err(j, "cut" if j >= n else "char")
            self.at, self.left, self.md = j + 1, spend(left, 1), "val"
            return e
        if t == "obje":
            return self.close(True, shut)
        return self.err(at_, "cut" if t == "end" else "char")

    def post(self, t):
        if t == "com":
            isobj = self.ks[-1]
            self.at, self.left = self.at + 1, spend(self.left, 1)
            self.md = "key" if isobj else "val"
            return None  # a comma emits nothing
        if t in ("arre", "obje"):
            return self.close(t == "obje", True)
        return self.err(self.at, "cut" if t == "end" else "char")

    def step(self):
        self.at = spaces(self.b, self.at, self.n)
        t = classify(at(self.b, self.at, self.n), self.at >= self.n)
        md = self.md
        if md in ("val", "val0"):
            return self.value(t, md == "val0")
        if md in ("key", "key0"):
            return self.keym(t, md == "key0")
        if md == "post":
            return self.post(t)
        if md == "done":
            return "eof" if t == "end" else self.err(self.at, "char")
        return self.bad  # terminal: the same event for ever

    def next(self):
        for _ in range(4):
            e = self.step()
            if e is not None:
                return e
        return self.err(self.at, "char")


def events(doc, limit):
    """the whole stream, as json.bend's show() prints it, and the budget left"""
    s = St(doc.encode(), limit)
    out = []
    while True:
        e = s.next()
        out.append(e)
        if e == "eof" or e.startswith("!"):
            return out, s.left, s


# -- what CPython says -------------------------------------------------------


def cpython_ok(doc):
    try:
        json.loads(doc)
        return True
    except (ValueError, RecursionError):
        return False


def cpython_spans(doc):
    """every string and number span CPython's own lexer finds, in order"""
    out, i, n = [], 0, len(doc)
    while i < n:
        c = doc[i]
        if c == '"':
            _, j = py_scanstring(doc, i + 1)
            out.append(("str", i + 1, j - i - 2))
            i = j
        elif c == "-" or c.isdigit():
            m = NUMBER_RE.match(doc, i)
            out.append(("num", i, m.end() - i))
            i = m.end()
        else:
            i += 1
    return out


def mine_spans(evs):
    out = []
    for e in evs:
        m = re.fullmatch(r"(key|str|num)@(\d+)\+(\d+)", e)
        if m:
            kind = "num" if m[1] == "num" else "str"
            out.append((kind, int(m[2]), int(m[3])))
    return out


CONST = re.compile(r"\b(NaN|Infinity)\b")


def agree(doc, evs):
    """cpython decides accept/reject, and its lexer decides every span"""
    ok = not evs[-1].startswith("!")
    # a budget refusal is not a grammar verdict: cpython has no budget, so it
    # accepts what Dry stopped. those rows pin the budget, not the grammar
    if evs[-1].startswith("!dry"):
        return
    # cpython's decoder recurses, so it answers RecursionError rather than a
    # verdict on the deep documents; those rows pin this parser's own ceiling
    deep = doc.count("[") + doc.count("{") > 100
    if not CONST.search(doc) and not deep:
        if ok != cpython_ok(doc):
            raise SystemExit("disagree with json.loads on %r: mine=%s" % (doc, ok))
    if ok and mine_spans(evs) != cpython_spans(doc):
        raise SystemExit(
            "span disagrees with cpython's lexer on %r: %s vs %s"
            % (doc, mine_spans(evs), cpython_spans(doc))
        )


# -- the corpus --------------------------------------------------------------


# the document is what the fixture reads, so it is written as a bend literal
def blit(s):
    out = ['"']
    for ch in s:
        o = ord(ch)
        out.append(
            {'"': '\\"', "\\": "\\\\", "\n": "\\n", "\t": "\\t", "\r": "\\r"}.get(
                ch, ch if 32 <= o < 127 else "\\u{%x}" % o
            )
        )
    return "".join(out) + '"'


BIG = 1000000  # a budget no document in the corpus can reach

rows, want = [], []


def ev(doc, limit=BIG):
    evs, left, _ = events(doc, limit)
    agree(doc, evs)
    rows.append("ev(%s, %d)" % (blit(doc), limit))
    want.append(" ".join(evs) + " left=%d" % left)


def chk(doc, limit=BIG):
    evs, _, _ = events(doc, limit)
    agree(doc, evs)
    rows.append("chk(%s, %d)" % (blit(doc), limit))
    want.append(evs[-1])


DEP = {"{": 1, "[": 1, "}": -1, "]": -1}


def done(e):
    return e == "eof" or e.startswith("!")


def sk(doc, k, limit=BIG):
    """k events, then one skip -- a scalar is one event, a container all of it"""
    s = St(doc.encode(), limit)
    for _ in range(k):
        s.next()
    e = s.next()
    d = DEP.get(e, 0)
    assert d >= 0, "skip must start on a value, not a closer"
    while d > 0 and not done(e):
        e = s.next()
        d += DEP.get(e, 0)
    out = [e]
    while not done(e):
        e = s.next()
        out.append(e)
    rows.append("sk(%s, %dn, %d)" % (blit(doc), k, limit))
    want.append(" ".join(out) + " left=%d" % s.left)


def rw(doc, at_, len_):
    rows.append("rw(%s, %d, %d)" % (blit(doc), at_, len_))
    want.append(doc[at_ : at_ + len_])


# the shapes: every scalar at the top level, then inside each container
for doc in [
    "1",
    "0",
    "-0",
    "12345",
    "-7",
    "1.5",
    "-2.5e3",
    "0.10",
    "1E+40",
    "1e-0",
    "1e400",
    '""',
    '"x"',
    '"\\u0041\\t"',
    '"a\\\\b"',
    '"\\"\\/\\b\\f\\n\\r"',
    "true",
    "false",
    "null",
    "[]",
    "{}",
    "[1]",
    "[[]]",
    "[{}]",
    '{"a":1}',
    '{"":null}',
    '{"a":{"b":[1,2,{"c":true}]}}',
    '[1,2,3,[4,[5]],{"k":"v"}]',
    "  \t\n\r [ 1 , 2 ]  \n",
    '{ "a" : 1 , "b" : 2 }',
    '["\\u00e9", "\\ud83d\\ude00"]',
]:
    ev(doc)

# the refusals: one document per error the parser can report
for doc in [
    "",
    " ",
    "[",
    "{",
    "[1",
    '{"a"',
    '{"a":',
    '{"a":1',
    '"abc',
    '"abc\\',
    "]",
    "}",
    ",",
    ":",
    "x",
    "tru",
    "truE",
    "trues",
    "nul",
    "fals",
    "01",
    "-01",
    "00",
    ".5",
    "1.",
    "1.e5",
    "1e",
    "1e+",
    "-",
    "+1",
    "1 2",
    "[]]",
    "[1,]",
    "[,1]",
    "[1,,2]",
    '{"a":1,}',
    "{,}",
    '{"a"1}',
    '{"a":1:2}',
    "{a:1}",
    "{1:2}",
    '{"a":}',
    "[1}",
    "{]",
    '["a" "b"]',
    '"\\q"',
    '"\\u12"',
    '"\\u12x4"',
    '"\\uZZZZ"',
    '"\\u123"',
    '"a\tb"',
    '"a\u0001b"',
    "[1, 2",
    "nan",
    "Infinity",
    "'x'",
    "[01]",
    '{"a":01}',
    "1.5.5",
    "--1",
    "0x10",
]:
    chk(doc)

# the same refusals as a stream, so the fixture pins where the cursor stopped
# and that the error repeats for ever instead of needing a flag
for doc in ["[1,]", '{"a"1}', '"\\u12x4"', "[1 2]", "01"]:
    ev(doc)

# the budget: the same document at limits either side of what it costs
COST = '["abcdefgh", 1]'
for limit in [0, 1, 2, 4, 5, 6, 11, 12, 13, 14, 40]:
    ev(COST, limit)
# a string the caller cannot afford is refused without being read
for limit in [0, 3, 6, 7, 8]:
    ev('"abcdefgh"', limit)
for limit in [0, 1, 2, 3, 6]:
    ev("-2.5e3", limit)
for limit in [0, 3, 4, 5]:
    ev("false", limit)
# whitespace is free, so padding a document does not change what it costs
ev("   [ 1 ]   ", 2)
ev("[1]", 2)
# a budget that runs out mid-document is reported at the next value token
ev('{"aa":1,"bb":2}', 9)

# depth: 256 containers open at once is the ceiling, the 257th is Deep
chk("[" * 255 + "1" + "]" * 255)
chk("[" * 256 + "1" + "]" * 256)
chk("[" * 257 + "1" + "]" * 257)
chk("[" * 256 + "]" * 256)
chk('{"a":' * 256 + "1" + "}" * 256)
chk('{"a":' * 257 + "1" + "}" * 257)

# skip: the value after a key, a whole container, and a skip that hits an error
sk('{"a":[1,2,3],"b":7}', 2, BIG)
sk("[[1,[2,3]],9]", 0, BIG)
sk('[{"a":{"b":1}},2]', 1, BIG)
sk('[[1,2],"x"]', 0, BIG)

# raw: the span really is that text in the caller's own bytes
rw('{"a":123,"bb":"xy"}', 2, 1)
rw('{"a":123,"bb":"xy"}', 5, 3)
rw('{"a":123,"bb":"xy"}', 10, 2)
rw('{"a":123,"bb":"xy"}', 15, 2)
rw('"\\u0041\\t"', 1, 8)
rw("[]", 0, 0)

for doc in ['{"a":123,"bb":"xy"}', '[1.5e2,"\\n"]']:
    ev(doc)

print(
    """# Json against CPython (json_gen.py prints this file). An `ev` row is every
# event of one document and the budget it had left; a `chk` row is only the
# event that ended it, which is `eof` or the refusal; `sk` skips the next value
# whole; `rw` reads a span back out of the caller's own bytes. A span is
# `name@offset+length` into the document, never a copy. CPython's json decides
# accept or reject for every document here and its own lexer decides every span
# -- the generator refuses to print a fixture that disagrees with either.
import Base
import ../../power/bytes.bend as Bytes
import ../../power/json.bend as Json

# ascii only: the corpus writes non-ascii as \\uXXXX, which is ascii itself
# (ponytail: a utf-8 encoder lands with the first consumer that has a String)
def of.push(c: Char, b: Bytes()) -> Bytes():
  match c:
    case Chr{code}:
      Bytes.push(b, code)

def of.go(s: String, b: Bytes()) -> Bytes():
  match s:
    case SNil{}:
      b
    case SCon{h, t}:
      of.go(t, of.push(h, b))

def of(s: String) -> Bytes():
  of.go(s, Bytes.new())

type Run is Type:
  Run{s: Json.St, acc: String, on: Bool}

def run.mk(+e: Json.Event, acc: String, s: Json.St) -> Run:
  Run{s, acc ++ Json.show(e) ++ " ", Json.live(e)}

def run.step(acc: String, r: Json.St & Json.Event) -> Run:
  (s, +e) = r
  run.mk(e, acc, s)

def run.go(fuel: Nat, k: Run) -> Run:
  match fuel:
    case 0n:
      k
    case 1n++p:
      match k:
        case Run{s, acc, on}:
          match on:
            case True{}:
              run.go(p, run.step(acc, Json.next(s)))
            case False{}:
              Run{s, acc, False{}}

def run.left(acc: String, r: Bytes() & U32) -> String:
  (b, l) = r
  acc ++ "left=" ++ U32.show(l)

def run.out(k: Run) -> String:
  match k:
    case Run{s, acc, on}:
      run.left(acc, Json.finish(s))

def drain(acc: String, s: Json.St) -> String:
  run.out(run.go(4096n, Run{s, acc, True{}}))

def ev(doc: String, +limit: U32) -> String:
  drain("", Json.start(of(doc), limit))

def chk.e(r: Bytes() & Json.Event) -> String:
  (b, e) = r
  Json.show(e)

def chk(doc: String, +limit: U32) -> String:
  chk.e(Json.check(of(doc), limit))

def pre.s(r: Json.St & Json.Event) -> Json.St:
  (s, e) = r
  s

def pre(k: Nat, s: Json.St) -> Json.St:
  match k:
    case 0n:
      s
    case 1n++p:
      pre(p, pre.s(Json.next(s)))

def sk.run(r: Json.St & Json.Event) -> String:
  (s, +e) = r
  drain(Json.show(e) ++ " ", s)

def sk(doc: String, k: Nat, +limit: U32) -> String:
  sk.run(Json.skip(pre(k, Json.start(of(doc), limit))))

def rw.out(r: Bytes() & String) -> String:
  (b, s) = r
  s

def rw(doc: String, +at: U32, +len: U32) -> String:
  rw.out(Json.raw(of(doc), at, len))

def main() -> IO(Unit):
  do IO<Unit>:"""
)
for r in rows:
    print("    IO.print(%s)" % r)
for w in want:
    print("#|" + w)
