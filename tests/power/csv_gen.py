#!/usr/bin/env python3
# The oracle for csv.bend: prints the whole fixture.
#
# Two authorities, and they check each other. CPython's own csv module
# (strict=True, dialects 'excel' and 'excel-tab', field_size_limit for the
# budget rows) decides the records and accept-or-refuse of every document it
# can read, and writes the bytes every writer row must equal; `agree()` raises
# if the reference below ever disagrees with it, so the generator cannot print
# a fixture that pins a grammar bug. What CPython has no word on -- where a
# refusal points, a quote inside an unquoted field (CPython keeps it as data,
# RFC 4180 does not), CR or LF refused by a dialect, max_fields, ragged rows,
# the header flag, the pad knob -- is `Ref`, written here from RFC 4180's
# grammar, not from the Bend file.
#
# Known, deliberate differences from CPython, each pinned by a row:
#   - a blank line is [""] here (the ABNF's one empty field); CPython says [].
#     agree() maps CPython's [] to [""].
#   - a quote inside an unquoted field is refused here; CPython keeps it.
#   - a UTF-8 BOM is data here, as in CPython read as latin-1: Csv.drop_bom
#     strips it on request.
#
# Every read row prints the result of one read, and the reader agrees with
# the same bytes fed one byte a read and with csv_spec.bend's parse, or the
# row says DISAGREE.
import csv
import io

Q, CM, CR, LF = 34, 44, 13, 10


class D:
    def __init__(self, name, delim=CM, quote=Q, crlf=True, lf=True, cr=True, header=False,
                 max_field=131072, max_fields=65536, ragged=True, pad=False, cpy=None):
        self.name, self.delim, self.quote = name, delim, quote
        self.crlf, self.lf, self.cr, self.header = crlf, lf, cr, header
        self.max_field, self.max_fields, self.ragged, self.pad = max_field, max_fields, ragged, pad
        self.cpy = cpy

    def bend(self):
        b = lambda x: "True{}" if x else "False{}"
        return "Csv.Dialect{%d, %d, %s, %s, %s, %s, %dn, %dn, %s, %s}" % (
            self.delim, self.quote, b(self.crlf), b(self.lf), b(self.cr), b(self.header),
            self.max_field, self.max_fields, b(self.ragged), b(self.pad))


EXCEL = D("excel", cpy="excel")
TSV = D("tsv", delim=9, cpy="excel-tab")
RFC = D("rfc", lf=False, cr=False, ragged=False)
SMALL = D("small", max_field=3, max_fields=2, cpy="excel")
HEAD = D("head", header=True, ragged=False)
LFONLY = D("lf", crlf=False, cr=False)
CRONLY = D("cr", crlf=False, lf=False)
CRLFCR = D("crlf+cr", lf=False)
SEMI = D("semi", delim=59, quote=39)
PAD = D("pad", pad=True)


class Ref:
    """RFC 4180's grammar over a whole input, with the dialect's knobs."""

    def __init__(self, d):
        self.d = d

    def kind(self, c):
        d = self.d
        if c == d.quote:
            return "Q"
        if c == d.delim:
            return "D"
        if c == CR:
            return "CR"
        if c == LF:
            return "LF"
        return "T"

    def lex(self, bs):
        # (lexeme, bytes, offset): a line end the dialect takes, or a bare one
        out, i, n = [], 0, len(bs)
        while i < n:
            k = self.kind(bs[i])
            if k == "CR":
                if self.d.crlf and i + 1 < n and self.kind(bs[i + 1]) == "LF":
                    out.append(("CRLF", bs[i:i + 2], i))
                    i += 2
                    continue
                out.append(("END" if self.d.cr else "BCR", bs[i:i + 1], i))
            elif k == "LF":
                out.append(("END" if self.d.lf else "BLF", bs[i:i + 1], i))
            else:
                out.append((k, bs[i:i + 1], i))
            i += 1
        return out

    def parse(self, bs):
        d = self.d
        toks = self.lex(bs)
        recs, fields, first = [], [], None
        n = d.max_fields

        class Bad(Exception):
            pass

        def refuse(at, why):
            raise Bad((at, why))

        def field_end(text, at):
            nonlocal n
            if n == 0:
                refuse(at, "too-many-fields")
            n -= 1
            fields.append(bytes(text))

        def record_end(text, at):
            nonlocal n, fields, first
            field_end(text, at)
            if first is None:
                first = n
            elif not d.ragged and n != first:
                refuse(at, "ragged")
            recs.append(fields)
            fields, n = [], d.max_fields

        try:
            mode, text, room, i = "record", bytearray(), 0, 0
            while i < len(toks):
                k, b, at = toks[i]
                i += 1
                if mode == "quoted":
                    if k == "Q":
                        mode = "closed"
                        continue
                    for j, c in enumerate(b):  # CRLF is two bytes of text
                        if room == 0:
                            refuse(at + j, "field-too-long")
                        room -= 1
                        text.append(c)
                    continue
                if mode == "closed" and k == "Q":  # the second of a 2DQUOTE
                    if room == 0:
                        refuse(at, "field-too-long")
                    room -= 1
                    text.append(b[0])
                    mode = "quoted"
                    continue
                if k == "T":
                    if mode == "closed":
                        refuse(at, "after-quote")
                    if mode in ("record", "field"):
                        mode, text, room = "plain", bytearray(), d.max_field
                    if room == 0:
                        refuse(at, "field-too-long")
                    room -= 1
                    text.append(b[0])
                    continue
                if k == "Q":
                    if mode == "plain":
                        refuse(at, "quote-in-field")
                    mode, text, room = "quoted", bytearray(), d.max_field
                    continue
                t = text if mode in ("plain", "closed") else b""
                if k == "D":
                    field_end(t, at)
                    mode, text = "field", bytearray()
                elif k in ("END", "CRLF"):
                    record_end(t, at)
                    mode, text = "record", bytearray()
                elif k == "BCR":
                    refuse(at, "bare-cr")
                else:
                    refuse(at, "bare-lf")
            end = len(bs)
            if mode == "quoted":
                refuse(end, "unclosed")
            if mode != "record":
                t = text if mode in ("plain", "closed") else b""
                record_end(t, end)
        except Bad as e:
            return ("bad",) + e.args[0]
        if d.header and recs:
            return ("ok", recs[0], recs[1:])
        return ("ok", None, recs)

    def needs(self, f):
        d = self.d
        if any(self.kind(c) != "T" for c in f):
            return True
        return d.pad and len(f) > 0 and (f[0] == 32 or f[-1] == 32)

    def field(self, f, force=False):
        d = self.d
        if not (self.needs(f) or force):
            return bytes(f)
        out = bytearray([d.quote])
        for c in f:
            out.append(c)
            if c == d.quote:
                out.append(c)
        out.append(d.quote)
        return bytes(out)

    def show(self, rs):
        out = bytearray()
        for r in rs:
            if len(r) == 1:
                out += self.field(r[0], force=(len(r[0]) == 0))
            else:
                out += bytes([self.d.delim]).join(self.field(f) for f in r)
            out += b"\r\n"
        return bytes(out)


def cpython_read(d, bs):
    csv.field_size_limit(d.max_field)
    try:
        rows = list(csv.reader(io.StringIO(bs.decode("latin-1"), newline=""), dialect=d.cpy,
                               strict=True))
    except csv.Error:
        return None
    return [[f.encode("latin-1") for f in r] or [b""] for r in rows]


def agree(d, bs, got):
    """CPython's csv decides where it can speak."""
    if d.cpy is None:
        return
    mine = Ref(d)
    cp = cpython_read(d, bs)
    if got[0] == "ok":
        assert cp == got[2], (bs, cp, got)
    elif got[2] == "quote-in-field":
        # RFC 4180 refuses it; CPython keeps the quote as data
        assert cp is not None and any(bytes([d.quote]) in f for r in cp for f in r), (bs, cp)
    elif got[2] in ("unclosed", "after-quote", "field-too-long"):
        assert cp is None, (bs, cp, got)
    elif got[2] == "too-many-fields":
        assert cp is not None and max(len(r) for r in cp) > d.max_fields, (bs, cp)
    else:
        raise AssertionError((bs, got))
    del mine


def cpython_write(d, rs):
    s = io.StringIO()
    csv.writer(s, dialect=d.cpy).writerows([[f.decode("latin-1") for f in r] for r in rs])
    return s.getvalue().encode("latin-1")


def esc(b):
    out = []
    for c in b:
        if 32 <= c < 127 and chr(c) not in "\\|[]":
            out.append(chr(c))
        else:
            out.append("\\x%02x" % c)
    return "".join(out)


def show_rec(r):
    return "[" + "|".join(esc(f) for f in r) + "]"


def show_out(o):
    if o[0] == "bad":
        return "bad@%d:%s" % (o[1], o[2])
    h = "H" + show_rec(o[1]) + " " if o[1] is not None else ""
    return "ok %s%d:%s" % (h, len(o[2]), "".join(show_rec(r) for r in o[2]))


def blist(bs):
    return "[" + ", ".join(str(c) for c in bs) + "]"


def bytes_lit(f):
    return "Bytes.from_list(%s)" % blist(f)


def recs_lit(rs):
    return "[" + ", ".join("[" + ", ".join(bytes_lit(f) for f in r) + "]" for r in rs) + "]"


rows, want = [], []


def read_row(d, bs):
    got = Ref(d).parse(bs)
    agree(d, bs, got)
    rows.append("rd(%s, %s)" % (d.bend(), blist(bs)))
    want.append(show_out(got))


def write_row(d, rs, fits=True):
    ref = Ref(d)
    b = ref.show(rs)
    if d.cpy is not None:
        assert cpython_write(d, rs) == b, (rs, cpython_write(d, rs), b)
    back = ref.parse(b)
    if fits:
        assert back == ("ok", None, rs), (rs, back)
    rows.append("wr(%s, %s)" % (d.bend(), recs_lit(rs)))
    want.append(esc(b) + " => " + show_out(back))


U = lambda s: s.encode("utf-8")

# -- RFC 4180, as CPython's excel reads it ------------------------------------
for bs in [b"", b"a", b"a,b", b"a,b\r\n", b"a,b\r\nc,d\r\n", b"a,b\r\nc,d", b",", b",,\r\n",
           b"a,,b\r\n", b"\r\n", b"\r\n\r\n", b"a\r\n\r\nb", b"a,\r\n", b" a , b ",
           b'"a"', b'""', b'""""', b'"a""b"', b'"a,b"', b'"a\r\nb",c\r\n', b'"\r\n"',
           b'"a"\r\n"b"', b'x,"y""z"\r\n', b'"a""",b', b'"""a"""',
           b'a"b', b'"a"b', b'"abc', b'"a""', b'"', b'a,"b', b'"a" ,b', b'ab"',
           b"a\rb", b"a\nb", b"a\r\rb", b"a\n\n", b"a\r", b'"a"\r', b'"a"\rb', b"a\r\n\nb",
           b"a\n\r\nb", U("é,ü\r\n"), U('"日本",語'), b"\xef\xbb\xbfa,b\r\n",
           b"a\x00b,\x7f\r\n", b'"a\rb"', b'"a\nb"']:
    read_row(EXCEL, bs)

# -- excel-tab ------------------------------------------------------------------
for bs in [b"a\tb\r\n", b'a\tb\r\n"c\td"\te\r\n', b"a,b\tc", b'"x"\t\t""\n']:
    read_row(TSV, bs)

# -- the budgets: a field of 3 bytes at most, a record of 2 fields ---------------
for bs in [b"abc", b"abcd", b'"abc"', b'"abcd"', b'"ab""c"', b'"a""b"', b'"a\r\nb"', b'"ab\r\n"',
           b"a,b", b"a,b,c", b"a,b\r\nc,d,e\r\n", b",,", b"a,b\r\n"]:
    read_row(SMALL, bs)

# -- RFC 4180 to the letter: CRLF only, every record as wide as the first --------
for bs in [b"a,b\r\nc,d\r\n", b"a\nb", b"a\rb", b"a,b\r\nc\r\n", b"a\r", b'"a\nb"\r\n',
           b"a,b\r\nc,d,e", b"\r\n", b"a\r\r\n", b'"a"\n']:
    read_row(RFC, bs)

# -- the header row -------------------------------------------------------------
for bs in [b"h1,h2\r\n1,2\r\n", b"h1,h2\r\n", b"", b"h1,h2\r\n1\r\n"]:
    read_row(HEAD, bs)

# -- one line end alone ---------------------------------------------------------
for bs in [b"a\nb\n", b"a\r\nb", b'"a\r\nb"\n']:
    read_row(LFONLY, bs)
for bs in [b"a\rb\r", b"a\r\nb", b"a\n"]:
    read_row(CRONLY, bs)
for bs in [b"a\r\nb", b"a\rb", b"a\r\r\n", b"a\nb"]:
    read_row(CRLFCR, bs)

# -- another delimiter and quote --------------------------------------------------
for bs in [b"'a;b';c", b"a;'b''c'\r\n", b'"a";b']:
    read_row(SEMI, bs)

# -- the writer ---------------------------------------------------------------------
for d, rs in [
    (EXCEL, [[b"a", b"b,c", b'd"e', b"f\r\ng", b""]]),
    (EXCEL, [[b""]]),
    (EXCEL, [[b" x "]]),
    (EXCEL, [[b"a"], [b"b"]]),
    (EXCEL, [[b'"']]),
    (EXCEL, [[b"", b""]]),
    (EXCEL, [[b"\r"], [b"\n"]]),
    (EXCEL, [[U("é"), U("日,本")]]),
    (EXCEL, [[b"h1", b"h2"], [b"1", b"2"], [b"", b'""']]),
    (EXCEL, []),
    (TSV, [[b"a", b"b\tc", b"d,e"]]),
    (RFC, [[b"a", b"b"], [b"c\r\n", b"d"]]),
    (PAD, [[b" x", b"y ", b"z", b" "]]),
    (SEMI, [[b"a;b", b"c'd", b"e"]]),
]:
    write_row(d, rs)
# a record of no fields is written as a blank line, as CPython writes it, and
# reads back as one empty field: the one list show cannot give back (fits
# refuses it)
write_row(EXCEL, [[b"a"], [], [b"b"]], fits=False)

# -- files: the same document through read_file and fold_file, in chunks of
# 1, 2, 3 and 64 KiB, so every boundary falls inside a field, a quote pair
# and a CRLF somewhere
FPATH = '"/tmp/bend-power-csv.csv"'
FDATA = b'a,b\r\n"x\r\ny","z"""\r\n,\r\nlast'
FDATA_LIT = '"a,b\\r\\n\\"x\\r\\ny\\",\\"z\\"\\"\\"\\r\\n,\\r\\nlast"'
FCHUNKS = [1, 2, 3]
got = Ref(EXCEL).parse(FDATA)
agree(EXCEL, FDATA, got)
FILE_WANT = [show_out(got)]
for k in FCHUNKS:
    FILE_WANT.append("%d records, then %s" % (len(got[2]), show_out(("ok", None, []))))
FILE_WANT.append("no file")

BEND = r'''# Csv against CPython (csv_gen.py prints this file). A read row is one
# document through Csv.read; it must also agree with the same bytes fed a
# byte a read and with csv_spec.bend's parse, or it says DISAGREE. A write
# row is the bytes Csv.show writes, which must be CPython's csv.writer's,
# then what reading them back gives. Bytes are printed as they are when
# they are printable ASCII, else \xHH (and \ | [ ] always).
import Base
import ../../power/csv.bend as Csv
import ../../power/csv_spec.bend as Spec

def u32.pick(b: Bool, x: U32, y: U32) -> U32:
  match b:
    case True{}:
      x
    case False{}:
      y

def hex1(+n: U32) -> String:
  SCon{Chr{U32.add(n, u32.pick(U32.is_lt(n, 10), 48, 87))}, SNil{}}

def esc.c(+c: U32, ok: Bool) -> String:
  match ok:
    case True{}:
      SCon{Chr{c}, SNil{}}
    case False{}:
      "\\x" ++ hex1(U32.shrn(c, 4n)) ++ hex1(U32.and(c, 15))

def plain(+c: U32) -> Bool:
  U32.is_ge(c, 32) && U32.is_lt(c, 127) && U32.is_ne(c, 92) && U32.is_ne(c, 124) &&
    U32.is_ne(c, 91) && U32.is_ne(c, 93)

def esc(b: Bytes()) -> String:
  match b:
    case SNil{}:
      ""
    case SCon{Chr{+c}, t}:
      esc.c(c, plain(c)) ++ esc(t)

def fields(r: List<&2, Bytes()>) -> String:
  match r:
    case Nil{}:
      ""
    case Con{f, t}:
      match t:
        case Nil{}:
          esc(f)
        case Con{g, u}:
          esc(f) ++ "|" ++ fields(Con{g, u})

def rec(r: List<&2, Bytes()>) -> String:
  "[" ++ fields(r) ++ "]"

def recs(rs: List<&2, List<&2, Bytes()>>) -> String:
  match rs:
    case Nil{}:
      ""
    case Con{r, t}:
      rec(r) ++ recs(t)

def head(h: Maybe<&2, List<&2, Bytes()>>) -> String:
  match h:
    case None{}:
      ""
    case Some{r}:
      "H" ++ rec(r) ++ " "

def out(o: Csv.Out) -> String:
  match o:
    case Csv.Refused{at, why}:
      "bad@" ++ Nat.show(at) ++ ":" ++ Csv.why.show(why)
    case Csv.Read{h, +rs}:
      "ok " ++ head(h) ++ Nat.show(List.length(&2, List<&2, Bytes()>, rs)) ++ ":" ++ recs(rs)

# the same bytes, one byte a read
def bytewise(+d: Csv.Dialect, s: Bytes(), p: Csv.P) -> Csv.P:
  match s:
    case SNil{}:
      p
    case SCon{h, t}:
      bytewise(d, t, Csv.feed_buf(d, SCon{h, SNil{}}, p))

def mark(ok: Bool) -> String:
  match ok:
    case True{}:
      ""
    case False{}:
      " DISAGREE"

def rd.all(+a: String, +b: String, +c: String) -> String:
  a ++ mark(String.eq(a, b) && String.eq(a, c))

def rd(+d: Csv.Dialect, +xs: List<&2, U32>) -> String:
  rd.all(out(Csv.read(d, Bytes.from_list(xs))),
    out(Csv.result(d, Csv.finish(d, bytewise(d, Bytes.from_list(xs), Csv.new(d))))),
    out(Spec.parse(xs, d)))

def wr.at(+d: Csv.Dialect, +b: Bytes()) -> String:
  esc(b) ++ " => " ++ out(Csv.read(d, b))

def wr(+d: Csv.Dialect, rs: List<&2, List<&2, Bytes()>>) -> String:
  wr.at(d, Csv.show(d, rs))

# Files: a document written, then read back through File.read_buf in
# chunks, whole and folded a record at a time
def put.close(r: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, x) = r
  File.close(f)

def put(path: String, data: String) -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open(path, "w"))
    r : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, data)
    put.close(r)

def count(n: Nat, r: List<&2, Bytes()>) -> Nat:
  1n+n

def rf(r: Result<&1, &1, U32 & String, Csv.Out>) -> String:
  match r:
    case Fail{e}:
      "no file"
    case Done{o}:
      out(o)

def ff(r: Result<&1, &1, U32 & String, Nat & Csv.Out>) -> String:
  match r:
    case Fail{e}:
      "no file"
    case Done{(n, o)}:
      Nat.show(n) ++ " records, then " ++ out(o)
'''

print(BEND.rstrip("\n"))
print()
print("def main() -> IO(Unit):")
print("  do IO<Unit>:")
for r in rows:
    print("    IO.print(%s)" % r)
print("    put(%s, %s)" % (FPATH, FDATA_LIT))
print("    r1 : Result<&1, &1, U32 & String, Csv.Out> <- Csv.read_file(%s, Csv.excel())" % FPATH)
print("    IO.print(rf(r1))")
for i, k in enumerate(FCHUNKS):
    print("    f%d : Result<&1, &1, U32 & String, Nat & Csv.Out> <- Csv.fold_file(~Nat, ~count, %s, Csv.excel(), %d, 0n)" % (i, FPATH, k))
    print("    IO.print(ff(f%d))" % i)
print("    r2 : Result<&1, &1, U32 & String, Csv.Out> <- Csv.read_file(%s, Csv.excel())" % (FPATH[:-5] + '-none.csv"'))
print("    IO.print(rf(r2))")
for w in want + FILE_WANT:
    print("#|" + w)
