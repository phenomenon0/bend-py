# CsvSpec: the reference csv.bend's reader is held to. It is RFC 4180's
# grammar (section 2, the ABNF) read over a whole input, written for
# whoever checks it rather than for the clock:
#
#   file        = [header CRLF] record *(CRLF record) [CRLF]
#   header      = name *(COMMA name)
#   record      = field *(COMMA field)
#   name        = field
#   field       = (escaped / non-escaped)
#   escaped     = DQUOTE *(TEXTDATA / COMMA / CR / LF / 2DQUOTE) DQUOTE
#   non-escaped = *TEXTDATA
#   COMMA = %x2C   CR = %x0D   DQUOTE = %x22   LF = %x0A   CRLF = CR LF
#   TEXTDATA = %x20-21 / %x23-2B / %x2D-7E
#
# with the dialect's knobs: COMMA and DQUOTE are the dialect's delimiter
# and quote; TEXTDATA is every other byte but CR and LF (so a byte past
# 127, a BOM's too, is data, and so is a control); the line end is CRLF,
# CR or LF as the dialect accepts each; the budgets refuse a field past
# max_field bytes, a record past max_fields fields, and, when ragged is
# off, a record whose width is not the first record's. A trailing line
# end and the empty input add no record (the ABNF would read the empty
# input as one record of one empty field; no reader does).
#
# It shares no code with csv.bend: it has its own classes, its own
# lexer, and it reads by the grammar's productions over the lexemes.
# Its lexer reads CRLF as one symbol, looking a byte ahead, where the
# reader is a machine that holds the CR (CRp) until the next byte says
# what it was. It shares the types the answer is written in: the
# dialect, the byte class names, the refusal reasons and Out.
import Base
import ./csv.bend as Csv

# The dialect
# ===========

def quote(d: Csv.Dialect) -> U32:
  match d:
    case Csv.Dialect{dl, q, a, b, c, h, mf, mn, rg, pd}:
      q

def comma(d: Csv.Dialect) -> U32:
  match d:
    case Csv.Dialect{dl, q, a, b, c, h, mf, mn, rg, pd}:
      dl

def takes_crlf(d: Csv.Dialect) -> Bool:
  match d:
    case Csv.Dialect{dl, q, a, b, c, h, mf, mn, rg, pd}:
      a

def takes_cr(d: Csv.Dialect) -> Bool:
  match d:
    case Csv.Dialect{dl, q, a, b, c, h, mf, mn, rg, pd}:
      c

def takes_lf(d: Csv.Dialect) -> Bool:
  match d:
    case Csv.Dialect{dl, q, a, b, c, h, mf, mn, rg, pd}:
      b

def budget(d: Csv.Dialect) -> Nat:
  match d:
    case Csv.Dialect{dl, q, a, b, c, h, mf, mn, rg, pd}:
      mf

def width(d: Csv.Dialect) -> Nat:
  match d:
    case Csv.Dialect{dl, q, a, b, c, h, mf, mn, rg, pd}:
      mn

def uneven(d: Csv.Dialect) -> Bool:
  match d:
    case Csv.Dialect{dl, q, a, b, c, h, mf, mn, rg, pd}:
      rg

def named(d: Csv.Dialect) -> Bool:
  match d:
    case Csv.Dialect{dl, q, a, b, c, h, mf, mn, rg, pd}:
      h

# Terminals
# =========

def same(+c: U32, x: U32) -> Bool:
  U32.is_eq(c, x)

def kind.if(b: Bool, x: Csv.K, y: Csv.K) -> Csv.K:
  match b:
    case True{}:
      x
    case False{}:
      y

# DQUOTE, then COMMA, then CR, then LF, and TEXTDATA for every other byte
def kind(+d: Csv.Dialect, +c: U32) -> Csv.K:
  kind.if(same(c, quote(d)), Csv.KQ{},
    kind.if(same(c, comma(d)), Csv.KD{},
      kind.if(same(c, 13), Csv.KCR{},
        kind.if(same(c, 10), Csv.KLF{}, Csv.KO{}))))

# a byte and its terminal
type Mark is Data:
  Mark{k: Csv.K, c: U32}

def marks(+d: Csv.Dialect, bs: List<&2, U32>) -> List<&2, Mark>:
  match bs:
    case Nil{}:
      Nil{}
    case Con{+c, t}:
      Con{Mark{kind(d, c), c}, marks(d, t)}

# The lexemes: the terminals, with a line end read as the dialect reads
# it. CRLF is one line end when the dialect takes CRLF; a CR is one when
# it takes CR alone; an LF when it takes LF alone. A CR or an LF it does
# not take is bare. Inside quotes every one of them is data again,
# byte for byte.
type Lx is Data:
  LQuote{c: U32}
  LComma{c: U32}
  LText{c: U32}
  LEnd{c: U32}
  LCrlf{a: U32, b: U32}
  LBareCR{c: U32}
  LBareLF{c: U32}

def lone.cr(ok: Bool, c: U32) -> Lx:
  match ok:
    case True{}:
      LEnd{c}
    case False{}:
      LBareCR{c}

def lone.lf(ok: Bool, c: U32) -> Lx:
  match ok:
    case True{}:
      LEnd{c}
    case False{}:
      LBareLF{c}

# crlf, cr, lf: which line ends the dialect takes
def lex(ms: List<&2, Mark>, +crlf: Bool, +cr: Bool, +lf: Bool) -> List<&2, Lx>:
  match ms:
    case Nil{}:
      Nil{}
    case Con{Mark{Csv.KQ{}, c}, t}:
      Con{LQuote{c}, lex(t, crlf, cr, lf)}
    case Con{Mark{Csv.KD{}, c}, t}:
      Con{LComma{c}, lex(t, crlf, cr, lf)}
    case Con{Mark{Csv.KO{}, c}, t}:
      Con{LText{c}, lex(t, crlf, cr, lf)}
    case Con{Mark{Csv.KLF{}, c}, t}:
      Con{lone.lf(lf, c), lex(t, crlf, cr, lf)}
    case Con{Mark{Csv.KCR{}, a}, +t}:
      match t:
        case Con{Mark{Csv.KLF{}, b}, u}:
          match crlf:
            case True{}:
              Con{LCrlf{a, b}, lex(u, crlf, cr, lf)}
            case False{}:
              Con{lone.cr(cr, a), lex(t, crlf, cr, lf)}
        case _:
          Con{lone.cr(cr, a), lex(t, crlf, cr, lf)}

# The grammar
# ===========

def Fields() -> Data:
  List<&2, Bytes()>

def Recs() -> Data:
  List<&2, List<&2, Bytes()>>

def add(acc: Bytes(), c: U32) -> Bytes():
  Bytes.append(acc, SCon{Chr{c}, SNil{}})

# where the grammar is: a record is due (at its start, or after a line
# end); a field is due (after a COMMA); inside a non-escaped field;
# inside an escaped one; after an escaped one's closing DQUOTE. room
# counts down the bytes the field may still take.
type At is Data:
  Record{}
  Field{}
  Plain{text: Bytes(), room: Nat}
  Quoted{text: Bytes(), room: Nat}
  Closed{text: Bytes(), room: Nat}

# a byte of a field, if the field has room: max_field counts them down
def room(n: Nat, +pos: Nat, k: Nat -> Csv.Out) -> Csv.Out:
  match n:
    case 0n:
      Csv.Refused{pos, Csv.FieldTooLong{}}
    case 1n+m:
      k(m)

# a field ends (at a COMMA, a line end or the end of input), if the
# record has room: max_fields counts them down; the fields so far are
# kept newest first
def field.end(n: Nat, text: Bytes(), fs: Fields(), +pos: Nat, k: Nat -> Fields() -> Csv.Out) ->
  Csv.Out:
  match n:
    case 0n:
      Csv.Refused{pos, Csv.TooManyFields{}}
    case 1n+m:
      k(m, Con{text, fs})

def wide(ok: Bool, rec: Fields(), rs: Recs(), +x: Nat, +pos: Nat,
  k: Recs() -> Maybe<&2, Nat> -> Csv.Out) -> Csv.Out:
  match ok:
    case True{}:
      k(Con{rec, rs}, Some{x})
    case False{}:
      Csv.Refused{pos, Csv.Ragged{}}

# a record ends, having left n of max_fields: it is kept (newest first).
# first is what the first record left; unless ragged, every record must
# leave the same, which is to say be as wide.
def record.end(+d: Csv.Dialect, +n: Nat, rec: Fields(), rs: Recs(), first: Maybe<&2, Nat>,
  +pos: Nat, k: Recs() -> Maybe<&2, Nat> -> Csv.Out) -> Csv.Out:
  match first:
    case None{}:
      k(Con{rec, rs}, Some{n})
    case Some{+x}:
      wide(uneven(d) || Nat.is_eq(n, x), rec, rs, x, pos, k)

# a line end at pos: the field ends, then its record
def line.end(+d: Csv.Dialect, text: Bytes(), n: Nat, fs: Fields(), rs: Recs(),
  first: Maybe<&2, Nat>, +pos: Nat, k: Recs() -> Maybe<&2, Nat> -> Csv.Out) -> Csv.Out:
  field.end(n, text, fs, pos, m => gs =>
    record.end(d, m, List.reverse(&2, Bytes(), gs), rs, first, pos, k))

# the records, oldest first, the first of them the header when the
# dialect has one
def done.named(rs: Recs()) -> Csv.Out:
  match rs:
    case Nil{}:
      Csv.Read{None{}, Nil{}}
    case Con{h, t}:
      Csv.Read{Some{h}, t}

def done.as(h: Bool, rs: Recs()) -> Csv.Out:
  match h:
    case True{}:
      done.named(rs)
    case False{}:
      Csv.Read{None{}, rs}

def done(+d: Csv.Dialect, rs: Recs()) -> Csv.Out:
  done.as(named(d), List.reverse(&2, List<&2, Bytes()>, rs))

# the text of the field a mode holds: none yet, where a field is due
def text(md: At) -> Bytes():
  match md:
    case Plain{t, r}:
      t
    case Quoted{t, r}:
      t
    case Closed{t, r}:
      t
    case _:
      ""

# the end of input. file = ... [CRLF]: a line end at the very end adds
# nothing, and nor does the empty input; otherwise the last record has
# no line end and ends with the input. An escaped field must be closed.
def go.end(+d: Csv.Dialect, +md: At, n: Nat, fs: Fields(), rs: Recs(), first: Maybe<&2, Nat>,
  +pos: Nat) -> Csv.Out:
  match md:
    case Record{}:
      done(d, rs)
    case Quoted{t, r}:
      Csv.Refused{pos, Csv.Unclosed{}}
    case _:
      line.end(d, text(md), n, fs, rs, first, pos, rs2 => f2 => done(d, rs2))

# One def reads the whole grammar, as Bend has no mutual recursion: at
# says which production is being read. n is the fields the record may
# still take; fs its fields so far; rs the records so far; first what
# the first record left of max_fields; pos the offset of the next byte.
def go(ls: List<&2, Lx>, +d: Csv.Dialect, +md: At, +n: Nat, fs: Fields(), rs: Recs(),
  first: Maybe<&2, Nat>, +pos: Nat) -> Csv.Out:
  match ls:
    case Nil{}:
      go.end(d, md, n, fs, rs, first, pos)
    case Con{x, t}:
      match x md:
        # escaped = DQUOTE *(TEXTDATA / COMMA / CR / LF / 2DQUOTE) DQUOTE.
        # A DQUOTE inside is the closing one unless the next symbol is a
        # DQUOTE too, and then the two are one 2DQUOTE: so a DQUOTE
        # closes the field, and a DQUOTE right after it reopens it with
        # one quote of text (counted at the second DQUOTE).
        case LQuote{a} Quoted{txt, r}:
          go(t, d, Closed{txt, r}, n, fs, rs, first, 1n+pos)
        case LQuote{a} Closed{txt, r}:
          room(r, pos, m => go(t, d, Quoted{add(txt, a), m}, n, fs, rs, first, 1n+pos))
        case LCrlf{a, b} Quoted{txt, r}:
          room(r, pos, m => room(m, 1n+pos, j =>
            go(t, d, Quoted{add(add(txt, a), b), j}, n, fs, rs, first, 1n+1n+pos)))
        case LComma{a} Quoted{txt, r}:
          room(r, pos, m => go(t, d, Quoted{add(txt, a), m}, n, fs, rs, first, 1n+pos))
        case LText{a} Quoted{txt, r}:
          room(r, pos, m => go(t, d, Quoted{add(txt, a), m}, n, fs, rs, first, 1n+pos))
        case LEnd{a} Quoted{txt, r}:
          room(r, pos, m => go(t, d, Quoted{add(txt, a), m}, n, fs, rs, first, 1n+pos))
        case LBareCR{a} Quoted{txt, r}:
          room(r, pos, m => go(t, d, Quoted{add(txt, a), m}, n, fs, rs, first, 1n+pos))
        case LBareLF{a} Quoted{txt, r}:
          room(r, pos, m => go(t, d, Quoted{add(txt, a), m}, n, fs, rs, first, 1n+pos))
        # non-escaped = *TEXTDATA: no DQUOTE in it
        case LText{a} Plain{txt, r}:
          room(r, pos, m => go(t, d, Plain{add(txt, a), m}, n, fs, rs, first, 1n+pos))
        case LQuote{a} Plain{txt, r}:
          Csv.Refused{pos, Csv.QuoteInField{}}
        # field = (escaped / non-escaped): a DQUOTE opens an escaped
        # field, TEXTDATA starts a non-escaped one; anything else ends
        # an empty one
        case LQuote{a} Record{}:
          go(t, d, Quoted{"", budget(d)}, n, fs, rs, first, 1n+pos)
        case LQuote{a} Field{}:
          go(t, d, Quoted{"", budget(d)}, n, fs, rs, first, 1n+pos)
        case LText{a} Record{}:
          room(budget(d), pos, m => go(t, d, Plain{add("", a), m}, n, fs, rs, first, 1n+pos))
        case LText{a} Field{}:
          room(budget(d), pos, m => go(t, d, Plain{add("", a), m}, n, fs, rs, first, 1n+pos))
        # after the closing DQUOTE, only a COMMA or a line end
        case LText{a} Closed{txt, r}:
          Csv.Refused{pos, Csv.AfterQuote{}}
        # record = field *(COMMA field)
        case LComma{a} _:
          field.end(n, text(md), fs, pos, m => gs => go(t, d, Field{}, m, gs, rs, first, 1n+pos))
        # *(CRLF record): a line end ends the field, then the record
        case LEnd{a} _:
          line.end(d, text(md), n, fs, rs, first, pos, rs2 => f2 =>
            go(t, d, Record{}, width(d), Nil{}, rs2, f2, 1n+pos))
        case LCrlf{a, b} _:
          line.end(d, text(md), n, fs, rs, first, pos, rs2 => f2 =>
            go(t, d, Record{}, width(d), Nil{}, rs2, f2, 1n+1n+pos))
        # a line end the dialect does not take
        case LBareCR{a} _:
          Csv.Refused{pos, Csv.BareCR{}}
        case LBareLF{a} _:
          Csv.Refused{pos, Csv.BareLF{}}

# the whole input: what it reads as, or where and why it was refused
def parse(bs: List<&2, U32>, +d: Csv.Dialect) -> Csv.Out:
  go(lex(marks(d, bs), takes_crlf(d), takes_cr(d), takes_lf(d)), d, Record{}, width(d), Nil{},
    Nil{}, None{}, 0n)
