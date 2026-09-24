#!/usr/bin/env python3
# The oracle for text.bend: prints the whole fixture. Nothing here is a second
# copy of power/text.bend.
#
#   normalization   unicodedata.normalize, verbatim, on the whole string
#   case folding    str.casefold, verbatim
#   UTF-8           str.encode / bytes.decode -- the decode is also the oracle
#                   for `valid`: a byte string is well-formed exactly when
#                   CPython decodes it
#   graphemes       regex's \X when the module is importable, which is the
#                   independent oracle; ref_gcb below is the fallback and is
#                   asserted equal to \X on every fixture string when both are
#                   present, so a machine without `regex` still prints the same
#                   file and says so by not asserting
#
# The map is the lane, so it is asserted here before it is pinned. For every
# segment the fixture touches:
#
#   normalize(original_bytes[src[j] : src[j+1]]) == normalized_bytes[dst[j] : dst[j+1]]
#
# taken through the byte encoding and back, plus the whole-string check that
# the segments concatenate to CPython's own normalize of the whole input. A
# Bend that mapped an offset to the wrong segment would still print plausible
# code points; it could not print them beside a "1".
#
# Coverage is a deliberate ceiling and the fixture is restricted to it -- see
# the header of power/text.bend. Test strings for the normalizing rows are
# drawn only from U+0000..U+036F, U+0385, U+1E00..U+1EFF, U+1FC1, U+1FED,
# U+2260, U+226E..U+226F, the conjoining jamo and the Hangul syllables, plus
# code points this file proves inert (no decomposition, no fold, class zero,
# and no composition with any mark in the alphabet). CPython normalizes far
# more than that; every code point below is checked to be inside the ceiling
# before it is used, so a row that CPython and Bend would disagree on cannot be
# written by accident.
import unicodedata as U

try:
    import regex
except ImportError:  # pragma: no cover - the fallback is the point
    regex = None

SB, LB, VB, TB = 0xAC00, 0x1100, 0x1161, 0x11A7
VN, TN = 21, 28

# --- the ceiling -------------------------------------------------------------

NORM_COV = [
    (0x0000, 0x036F),
    (0x0385, 0x0385),
    (0x1100, 0x1112),
    (0x1161, 0x1175),
    (0x11A8, 0x11C2),
    (0x1E00, 0x1EFF),
    (0x1FC1, 0x1FC1),
    (0x1FED, 0x1FED),
    (0x2260, 0x2260),
    (0x226E, 0x226F),
    (0xAC00, 0xD7A3),
]
# the full case folds: in coverage but longer than one code point, so simple
# folding leaves them alone and no Fold row may contain one
MULTI = {0x00DF, 0x0130, 0x0149, 0x01F0, 0x1E96, 0x1E97, 0x1E98, 0x1E99, 0x1E9A, 0x1E9E}


def in_cov(cp):
    return any(a <= cp <= b for a, b in NORM_COV)


def inert(cp):
    """Outside the table's coverage but provably indistinguishable from it."""
    c = chr(cp)
    return (
        U.normalize("NFD", c) == c
        and U.normalize("NFC", c) == c
        and c.casefold() == c
        and U.combining(c) == 0
        and not U.decomposition(c)
    )


def fold1(cp):
    f = chr(cp).casefold()
    assert len(f) == 1, "U+%04X has a multi-code-point fold" % cp
    return ord(f)


def lccc(cp):
    return U.combining(U.normalize("NFD", chr(cp))[0])


def is_start(cp):
    """A code point nothing before it can compose with. The two jamo holes are
    the reason this is not `lccc == 0`: a conjoining V or T has class zero and
    still joins leftward."""
    if VB <= cp < VB + VN:
        return False
    if TB < cp < TB + TN:
        return False
    return lccc(cp) == 0


def boffs(cps):
    o, out = 0, [0]
    for c in cps:
        o += len(chr(c).encode())
        out.append(o)
    return out


def normref(s, form):
    """(normalized str, src offsets, dst offsets) -- the map, segment by
    segment, with every segment normalized by CPython."""
    cps = [ord(c) for c in s]
    fcps = [fold1(c) for c in cps] if form == "fold" else list(cps)
    nf = "NFD" if form == "nfd" else "NFC"
    bo = boffs(cps)
    starts = [i for i in range(len(fcps)) if i == 0 or is_start(fcps[i])]
    out, src, dst = "", [], []
    for k, i in enumerate(starts):
        j = starts[k + 1] if k + 1 < len(starts) else len(fcps)
        src.append(bo[i])
        dst.append(len(out.encode()))
        out += U.normalize(nf, "".join(chr(c) for c in fcps[i:j]))
    src.append(bo[-1])
    dst.append(len(out.encode()))
    return out, src, dst


# --- Grapheme_Cluster_Break, the fallback oracle -----------------------------

OTHER, CR, LF, CTL, EXT, ZWJ, RI, PRE, SPM, L, V, T, LV, LVT, PIC = range(15)
GR = []


def add(a, b, k):
    GR.append((a, b, k))


add(0x00, 0x09, CTL), add(0x0A, 0x0A, LF), add(0x0B, 0x0C, CTL)
add(0x0D, 0x0D, CR), add(0x0E, 0x1F, CTL), add(0x7F, 0x9F, CTL)
add(0xA9, 0xA9, PIC), add(0xAD, 0xAD, CTL), add(0xAE, 0xAE, PIC)
add(0x0300, 0x036F, EXT)
add(0x0600, 0x0605, PRE), add(0x06DD, 0x06DD, PRE), add(0x070F, 0x070F, PRE)
add(0x0890, 0x0891, PRE), add(0x08E2, 0x08E2, PRE), add(0x0D4E, 0x0D4E, PRE)
add(0x1100, 0x115F, L), add(0x1160, 0x11A7, V), add(0x11A8, 0x11FF, T)
add(0x200B, 0x200B, CTL), add(0x200C, 0x200C, EXT), add(0x200D, 0x200D, ZWJ)
add(0x2028, 0x2029, CTL), add(0x203C, 0x203C, PIC), add(0x2049, 0x2049, PIC)
add(0x2600, 0x27BF, PIC), add(0x2B00, 0x2BFF, PIC), add(0xAC00, 0xD7A3, LV)
add(0xFE00, 0xFE0F, EXT), add(0xFEFF, 0xFEFF, CTL)
add(0x1F000, 0x1F0FF, PIC), add(0x1F10D, 0x1F1AD, PIC)
add(0x1F1E6, 0x1F1FF, RI), add(0x1F200, 0x1F2FF, PIC)
add(0x1F300, 0x1F3FA, PIC), add(0x1F3FB, 0x1F3FF, EXT), add(0x1F400, 0x1F5FF, PIC)
add(0x1F600, 0x1F64F, PIC), add(0x1F680, 0x1F6FF, PIC), add(0x1F7E0, 0x1F7EB, PIC)
add(0x1F900, 0x1F9FF, PIC), add(0x1FA70, 0x1FAFF, PIC)
# Devanagari comes from the general category, not from a hand list
_dv = []
for _cp in range(0x900, 0x980):
    _c = U.category(chr(_cp))
    _k = EXT if _c in ("Mn", "Me") else SPM if _c == "Mc" else OTHER
    if _dv and _dv[-1][2] == _k and _dv[-1][1] == _cp - 1:
        _dv[-1][1] = _cp
    else:
        _dv.append([_cp, _cp, _k])
for _a, _b, _k in _dv:
    if _k != OTHER:
        add(_a, _b, _k)
GR.sort()
for _i in range(1, len(GR)):
    assert GR[_i - 1][1] < GR[_i][0]
assert len(GR) == 54


def gcls(cp):
    lo, hi = 0, len(GR) - 1
    while lo <= hi:
        m = (lo + hi) // 2
        a, b, k = GR[m]
        if cp < a:
            hi = m - 1
        elif cp > b:
            lo = m + 1
        else:
            return (LV if (cp - SB) % TN == 0 else LVT) if k == LV else k
    return OTHER


def gb(pk, ck, azp, ri):
    raw = ck
    pk = OTHER if pk == PIC else pk
    ck = OTHER if ck == PIC else ck
    if pk == CR and ck == LF:
        return False  # GB3
    if pk in (CR, LF, CTL) or ck in (CR, LF, CTL):
        return True  # GB4, GB5
    if ck in (EXT, ZWJ, SPM):
        return False  # GB9, GB9a
    if pk == PRE:
        return False  # GB9b
    if pk == L and ck in (L, V, LV, LVT):
        return False  # GB6
    if pk in (LV, V) and ck in (V, T):
        return False  # GB7
    if pk in (LVT, T) and ck == T:
        return False  # GB8
    if azp and raw == PIC:
        return False  # GB11
    if pk == RI and ck == RI and ri:
        return False  # GB12, GB13
    return True


def ref_gcb(s):
    cps = [ord(c) for c in s]
    bo = boffs(cps)
    out, prev, pict, azp, ri = [], -1, False, False, False
    for i, cp in enumerate(cps):
        k = gcls(cp)
        if prev < 0 or gb(prev, k, azp, ri):
            out.append(bo[i])
        azp = k == ZWJ and pict
        pict = k == PIC or (pict and k == EXT)
        ri = (not ri) if k == RI else False
        prev = k
    return out + [bo[-1]]


def gstarts(s):
    want = ref_gcb(s)
    if regex is not None:
        got, o = [], 0
        for m in regex.findall(r"\X", s):
            got.append(o)
            o += len(m.encode())
        assert got + [o] == want, (s.encode("unicode_escape"), got, want)
    return want


# --- the fixture -------------------------------------------------------------

rows, want, checked = [], [], {"law": 0, "gcb": 0}


def emit(call, expect):
    rows.append(call)
    want.append(expect)


def cps_of(s):
    return "<" + "".join("%d " % ord(c) for c in s) + ">"


def bytes_of(s):
    return "<" + "".join("%d " % b for b in s.encode()) + ">"


def lit(xs):
    return "[" + ", ".join(str(x) for x in xs) + "]"


def blit(s):
    return lit(list(s.encode()))


def clit(s):
    return lit([ord(c) for c in s])


# -- UTF-8: decode, encode, validity
UTF = ["", "Hi", "ñ", "€5", "\U0001f600!", "각", "̣́"]
for s in UTF:
    emit("cp(By.from_list(%s, By.new()))" % blit(s), cps_of(s))
for s in UTF:
    emit("cp(mk(%s))" % clit(s), cps_of(s))
for s in UTF:
    emit("bv(mk(%s))" % clit(s), bytes_of(s))

BYTES = [
    [],
    [0x41],
    [0xC3, 0xA9],
    [0xE2, 0x82, 0xAC],
    [0xF0, 0x9F, 0x98, 0x80],
    [0xF4, 0x8F, 0xBF, 0xBF],
    [0x80],
    [0xBF, 0xBF],
    [0xC3],
    [0xC2, 0x41],
    [0xC0, 0x80],
    [0xC1, 0xBF],
    [0xE0, 0x80, 0x80],
    [0xE2, 0x82],
    [0xED, 0xA0, 0x80],
    [0xED, 0xBF, 0xBF],
    [0xF0, 0x80, 0x80, 0x80],
    [0xF4, 0x90, 0x80, 0x80],
    [0xF5, 0x80, 0x80, 0x80],
    [0xFF],
    [0x41, 0xC3, 0xA9, 0x80],
]
for xs in BYTES:
    try:
        bytes(xs).decode("utf-8")
        ok = "1"
    except UnicodeDecodeError:
        ok = "0"
    emit("vd(By.from_list(%s, By.new()))" % lit(xs), ok)

# -- graphemes. The alphabet is the covered break classes plus U+4E2D, which
# is Other in the table and Other in the standard. No InCB=Linker: GB9c is out
# of scope, and U+094D is deliberately absent.
G = [
    "",
    "A",
    "abc",
    "\r\n",
    "\n\r",
    "\r\r\n\n",
    "a\r\nb",
    "\ta\x00b",
    "é",
    "ȩ̣́",
    "́",
    "A­ B",
    "​A",
    "\U0001f1e6\U0001f1e7",
    "\U0001f1e6\U0001f1e7\U0001f1e8",
    "\U0001f1e6\U0001f1e7\U0001f1e8\U0001f1e9",
    "A\U0001f1e6\U0001f1e7B",
    "\U0001f1fa\U0001f1f8\U0001f1fa\U0001f1f8",
    "\U0001f468‍\U0001f469‍\U0001f466",
    "\U0001f469\U0001f3fb‍\U0001f9d1",
    "\U0001f600‍A",
    "A‍\U0001f600",
    "\U0001f600️",
    "❤️",
    "♥⭐",
    "‼⁉",
    "\U0001f6f3\U0001f600",
    "가듌",
    "각",
    "가",
    "각",
    "각ᆨ",
    "ᅡᄀ",
    "कां",
    "क़ंक",
    "؀क",
    "ൎA",
    "؀\r",
    "﻿A中",
    "中́中",
    "ä\U0001f1e6\U0001f1e7\r\n각",
]
for s in G:
    checked["gcb"] += 1
    emit(
        "gv(Text.graphemes(By.from_list(%s, By.new())))" % blit(s),
        "<" + "".join("%d " % o for o in gstarts(s)) + ">",
    )

# -- normalization and the map. Every code point below is inside the stated
# ceiling or proved inert; the assertion is the ceiling, not a comment.
N = [
    "",
    "A",
    "Hello, world",
    "é",
    "é",
    "ẹ́",
    "ẹ́",
    "ẹ́",
    "q̣̇",
    "ḍ̇",
    "Ḍ̇",
    "ÁBÇ",
    "Àèẛ",
    "STRASSE",
    "Masse",
    "각",
    "각",
    "각가",
    "ẛ̣",
    "≠≮≯",
    "΅",
    "A̅̀́̂̃",
    "à̖́b",
    "中文á",
    "\U0001f600́A",
    "Café 中文 가",
]
MARKS = [0x0300, 0x0301, 0x0302, 0x0303, 0x0307, 0x0316, 0x0323, 0x0327, 0x0328]
for s in N:
    for c in s:
        cp = ord(c)
        if in_cov(cp):
            continue
        assert inert(cp), "U+%04X is outside the ceiling" % cp
        for m in MARKS:
            assert len(U.normalize("NFC", c + chr(m))) == 2, "U+%04X composes" % cp

FORMS = {"nfd": "Text.Nfd{}", "nfc": "Text.Nfc{}", "fold": "Text.Fold{}"}


def law(s, form):
    """The round-trip, asserted before it is printed."""
    out, src, dst = normref(s, form)
    nf = "NFD" if form == "nfd" else "NFC"
    whole = "".join(chr(fold1(ord(c))) for c in s) if form == "fold" else s
    assert out == U.normalize(nf, whole), (s.encode("unicode_escape"), form)
    ob, nb = s.encode(), out.encode()
    for j in range(len(src) - 1):
        piece = ob[src[j] : src[j + 1]].decode()
        if form == "fold":
            piece = "".join(chr(fold1(ord(c))) for c in piece)
        assert U.normalize(nf, piece).encode() == nb[dst[j] : dst[j + 1]], (
            s.encode("unicode_escape"),
            form,
            j,
        )
        checked["law"] += 1
    return out, src, dst


SRC = []
for i, s in enumerate(N):
    if s:
        SRC.append((i, s))
for i, s in SRC:
    for c in s:
        assert ord(c) not in MULTI

emit("nc(Text.norm(By.new(), Text.Nfc{}))", "<>")
emit("dims(By.new(), Text.Nfd{})", "0 0")
for i, s in SRC:
    for form, ctor in FORMS.items():
        out, src, dst = law(s, form)
        emit("nc(Text.norm(s%d(), %s))" % (i, ctor), cps_of(out))

for i, s in SRC[:6]:
    out, src, dst = law(s, "nfc")
    emit("dims(s%d(), Text.Nfc{})" % i, "%d %d" % (len(out.encode()), len(src) - 1))


def segat(dst, o):
    seg = 0
    while seg + 1 < len(dst) - 1 and dst[seg + 1] <= o:
        seg += 1
    return seg


# the law, once per string and form, with the probe offset rotated so the rows
# together land on first bytes, interior bytes and last bytes of a segment
for n, (i, s) in enumerate(SRC):
    for f, (form, ctor) in enumerate(FORMS.items()):
        out, src, dst = law(s, form)
        nb = len(out.encode())
        o = (n * 7 + f * 3) % nb
        seg = segat(dst, o)
        piece = out.encode()[dst[seg] : dst[seg + 1]].decode()
        emit("rt(s%d(), %s, %d)" % (i, ctor, o), "1 " + cps_of(piece))

# and a sweep of every segment of the two strings that have the most, which is
# what the binary search in back is for
for i, s in sorted(SRC, key=lambda p: -len(normref(p[1], "nfc")[1]))[:1]:
    out, src, dst = law(s, "nfc")
    for seg in range(len(dst) - 1):
        piece = out.encode()[dst[seg] : dst[seg + 1]].decode()
        emit("rt(s%d(), Text.Nfc{}, %d)" % (i, dst[seg]), "1 " + cps_of(piece))

# Span: a citation is the byte range in the original, carried with the document
# and revision it was taken against.
for i, s in SRC[:4]:
    out, src, dst = law(s, "nfc")
    o = len(out.encode()) - 1
    seg = segat(dst, o)
    emit(
        "sp(s%d(), Text.Nfc{}, 7, 3, %d)" % (i, o),
        "7:3:%d-%d" % (src[seg], src[seg + 1]),
    )

assert checked["law"] > 200, checked
assert checked["gcb"] == len(G)
# ponytail: the row count is capped by the JS lane, not by the algebra -- the
# emitted `do` block is one nested closure a statement and V8's stack gives out
# somewhere past 300.
assert len(rows) < 260, "fixture is %d rows" % len(rows)

print(
    """# Text against CPython (text_gen.py prints this file). unicodedata.normalize
# and str.casefold answer every normalizing row; regex's \\X answers every
# grapheme row; bytes.decode answers every validity row. The `rt` rows are the
# law the lane exists for -- "1" then the code points of one normalized
# segment, where the 1 is Bend agreeing that re-normalizing the original bytes
# back(o) pointed at reproduces exactly those code points. Both sides of the
# claim are in one string, so a Bend that mapped the offset to the wrong
# segment cannot print the row at all.
import Base
import ../../power/vec.bend as Vec
import ../../power/bytes.bend as By
import ../../power/text.bend as Text

def yn(b: Bool) -> String:
  match b:
    case True{}:
      "1"
    case False{}:
      "0"

def w(s: String) -> String:
  "<" ++ s ++ ">"

def cp.s(r: By.Bytes & String) -> String:
  (b, s) = r
  w(s)

def cp(b: By.Bytes) -> String:
  cp.s(Text.cps(b))

def vd.s(r: By.Bytes & Bool) -> String:
  (b, x) = r
  yn(x)

def vd(b: By.Bytes) -> String:
  vd.s(Text.valid(b))

def nc.s(r: Text.Norm & String) -> String:
  (m, s) = r
  w(s)

def nc(m: Text.Norm) -> String:
  nc.s(Text.ncps(m))

# the inputs: code points folded through Text.emit, so the encoder is on the
# hook for every row the decoder answers
def mk.go(xs: List<&2, U32>, b: By.Bytes) -> By.Bytes:
  match xs:
    case Nil{}:
      b
    case Con{x, t}:
      mk.go(t, Text.emit(b, x))

def mk(xs: List<&2, U32>) -> By.Bytes:
  mk.go(xs, By.new())

type Bv is Type:
  Bv{i: U32, b: By.Bytes, s: String}

def bv.put(+i: U32, s: String, r: By.Bytes & U32) -> Bv:
  (b, x) = r
  Bv{U32.inc(i), b, s ++ U32.show(x) ++ " "}

def bv.step(t: Bv) -> Bv:
  match t:
    case Bv{+i, b, s}:
      bv.put(i, s, By.at(b, i))

def bv.go(fuel: Nat, t: Bv) -> Bv:
  match fuel:
    case 0n:
      t
    case 1n++p:
      bv.go(p, bv.step(t))

def bv.take(t: Bv) -> String:
  match t:
    case Bv{i, b, s}:
      w(s)

def bv.n(r: By.Bytes & U32) -> String:
  (b, +n) = r
  bv.take(bv.go(U32.to_nat(n), Bv{0, b, ""}))

def bv(b: By.Bytes) -> String:
  bv.n(By.len(b))

type Vs is Type:
  Vs{i: U32, v: Vec.Vec, s: String}

def vs.put(+i: U32, s: String, r: Vec.Vec & U32) -> Vs:
  (v, x) = r
  Vs{U32.inc(i), v, s ++ U32.show(x) ++ " "}

def vs.step(t: Vs) -> Vs:
  match t:
    case Vs{+i, v, s}:
      vs.put(i, s, Vec.at(v, i))

def vs.go(fuel: Nat, t: Vs) -> Vs:
  match fuel:
    case 0n:
      t
    case 1n++p:
      vs.go(p, vs.step(t))

def vs.take(t: Vs) -> String:
  match t:
    case Vs{i, v, s}:
      w(s)

def vs.n(r: Vec.Vec & U32) -> String:
  (v, +n) = r
  vs.take(vs.go(U32.to_nat(n), Vs{0, v, ""}))

def gv(r: By.Bytes & Vec.Vec) -> String:
  (b, v) = r
  vs.n(Vec.len(v))

# the original has to outlive the normalizer for the law to be checkable at
# all, and norm takes its input: a copy through the byte list is the cheapest
# honest way to hold one
def dup.mk(r: By.Bytes & List<&2, U32>) -> By.Bytes & By.Bytes:
  (b, xs) = r
  (b, By.from_list(xs, By.new()))

def dup(b: By.Bytes) -> By.Bytes & By.Bytes:
  dup.mk(By.to_list(b))

def dims.s(n: U32, r: Text.Norm & U32) -> String:
  (m, k) = r
  U32.show(n) ++ " " ++ U32.show(k)

def dims.l(r: Text.Norm & U32) -> String:
  (m, n) = r
  dims.s(n, Text.nsegs(m))

def dims(b: By.Bytes, +f: Text.Form) -> String:
  dims.l(Text.nlen(Text.norm(b, f)))

def rt.cmp(+a: String, b: String) -> String:
  yn(String.eq(a, b)) ++ " " ++ a

def rt.re(seg: String, f: Text.Form, r: By.Bytes & By.Bytes) -> String:
  (o, sl) = r
  rt.cmp(seg, nc(Text.norm(sl, f)))

def rt.sl(seg: String, f: Text.Form, orig: By.Bytes, +s: U32, +e: U32) -> String:
  rt.re(seg, f, Text.slice(orig, s, e))

def rt.ns(orig: By.Bytes, f: Text.Form, +s: U32, +e: U32,
  r: Text.Norm & By.Bytes) -> String:
  (m, x) = r
  rt.sl(cp(x), f, orig, s, e)

def rt.fwd2(orig: By.Bytes, f: Text.Form, +s: U32, +e: U32, m: Text.Norm,
  dd: U32 & U32) -> String:
  (ds, de) = dd
  rt.ns(orig, f, s, e, Text.nslice(m, ds, de))

def rt.fwd(orig: By.Bytes, f: Text.Form, +s: U32, +e: U32,
  r: Text.Norm & (U32 & U32)) -> String:
  (m, dd) = r
  rt.fwd2(orig, f, s, e, m, dd)

def rt.se(orig: By.Bytes, f: Text.Form, m: Text.Norm, +s: U32, +e: U32) -> String:
  rt.fwd(orig, f, s, e, Text.fwd(m, s))

def rt.se2(orig: By.Bytes, f: Text.Form, m: Text.Norm, se: U32 & U32) -> String:
  (s, e) = se
  rt.se(orig, f, m, s, e)

def rt.back(orig: By.Bytes, f: Text.Form, r: Text.Norm & (U32 & U32)) -> String:
  (m, se) = r
  rt.se2(orig, f, m, se)

def rt.m(f: Text.Form, +o: U32, orig: By.Bytes, m: Text.Norm) -> String:
  rt.back(orig, f, Text.back(m, o))

def rt.d(+f: Text.Form, +o: U32, r: By.Bytes & By.Bytes) -> String:
  (a, b) = r
  rt.m(f, o, a, Text.norm(b, f))

# rt: back(o) to a range of the original, slice it out, normalize that slice
# alone, and hold it against the normalized segment fwd says it became
def rt(b: By.Bytes, +f: Text.Form, +o: U32) -> String:
  rt.d(f, o, dup(b))

def sp.f(+d: U32, +v: U32, r: Text.Norm & (U32 & U32)) -> String:
  (m, ab) = r
  Text.span.show(Text.span(d, v, ab))

# a citation: the byte range of the original, carried with the document and the
# revision it was read against, because a range without a revision is a range
# that will one day point at the wrong bytes
def sp(b: By.Bytes, +f: Text.Form, +d: U32, +v: U32, +o: U32) -> String:
  sp.f(d, v, Text.back(Text.norm(b, f), o))
"""
)
for i, s in SRC:
    print("def s%d() -> By.Bytes:" % i)
    print("  By.from_list(%s, By.new())\n" % blit(s))
print("def main() -> IO(Unit):")
print("  do IO<Unit>:")
for r in rows:
    print("    IO.print(%s)" % r)
for x in want:
    print("#|" + x)
