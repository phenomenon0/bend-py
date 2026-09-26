# Gzip: RFC 1952 around power/deflate.bend's raw streams, both ways.
#
# gunzip is a byte machine (G, kind Data) over the member's parts: the
# ten fixed bytes, FEXTRA's length and bytes, FNAME and FCOMMENT to
# their zero, FHCRC, the deflate stream (the inflate machine, fed the
# byte), and the eight trailer bytes. A read may end anywhere and the
# next carries on (the reader kit's feed_split, as for inflate).
#
# What is checked, and refused if wrong (Bad{at, why}, terminal, at the
# offset of the byte that broke the rule):
#   NotGzip     the magic bytes 1f 8b
#   BadMethod   CM other than 8 (deflate)
#   BadFlags    a reserved FLG bit (RFC 1952 2.3.1.2: must refuse)
#   BadHcrc     FHCRC's 16 bits against the header's CRC-32
#   Inflate     the deflate stream, as power/deflate.bend refuses it,
#               TooBig among them: the cap counts every member's bytes
#   BadCrc      the trailer's CRC-32 against the member's bytes
#   BadSize     ISIZE against the member's length mod 2^32
#   Truncated   the input ended inside a member (finish)
# Members follow one another, as gzip -c a b makes them; zero bytes
# between or after members are skipped (as CPython's gzip.decompress
# does); the empty input is no members and no bytes.
#
# gzip writes one member: MTIME 0, XFL 2 at level 9 and 4 at level 1,
# OS 255, no optional fields: CPython's gzip.compress(mtime=0) header.
import Base
import ../wire/reader.bend as Wr
import ./deflate.bend as D

type Why is Data:
  NotGzip{}
  BadMethod{}
  BadFlags{}
  BadHcrc{}
  Inflate{why: D.Why}
  BadCrc{}
  BadSize{}
  Truncated{}

def why.show(w: Why) -> String:
  match w:
    case NotGzip{}:
      "NotGzip"
    case BadMethod{}:
      "BadMethod"
    case BadFlags{}:
      "BadFlags"
    case BadHcrc{}:
      "BadHcrc"
    case Inflate{w2}:
      "Inflate:" ++ D.why.show(w2)
    case BadCrc{}:
      "BadCrc"
    case BadSize{}:
      "BadSize"
    case Truncated{}:
      "Truncated"

# Writing
# =======

def push4(b: Bytes(), +v: U32) -> Bytes():
  Bytes.push(Bytes.push(Bytes.push(Bytes.push(b, U32.and(v, 255)), U32.and(U32.shrn(v, 8n), 255)),
    U32.and(U32.shrn(v, 16n), 255)), U32.shrn(v, 24n))

def xfl(+lvl: Nat) -> U32:
  D.u32.pick(Nat.is_eq(lvl, 9n), 2, D.u32.pick(Nat.is_eq(lvl, 1n), 4, 0))

def header(+lvl: Nat) -> Bytes():
  Bytes.push(Bytes.push(push4(Bytes.from_list([31, 139, 8, 0]), 0), xfl(lvl)), 255)

# one gzip member holding x, deflated at lvl
def gzip(+x: Bytes(), +lvl: Nat) -> Bytes():
  push4(push4(Bytes.append(header(lvl), D.deflate(x, lvl)), D.crc32(x, 0)),
    U32.from_nat(Bytes.len(x)))

# Reading
# =======

# where the reader is in a member. Head: k of the ten fixed bytes read;
# the header's bytes so far are kept (hb) for FHCRC. XLen, XSkip: the
# extra field. Name, Comm: to their zero. HCrc: the two check bytes.
# Body: the deflate stream. Trail: k of
# the eight read, the CRC-32 and ISIZE as they fill, little end first.
# Gap: between members. Start: before the first.
type Ph is Data:
  Start{}
  Head{k: Nat, flg: U32, hb: Bytes()}
  XLen{k: Nat, lo: Nat, flg: U32, hb: Bytes()}
  XSkip{left: Nat, flg: U32, hb: Bytes()}
  Name{flg: U32, hb: Bytes()}
  Comm{flg: U32, hb: Bytes()}
  HCrc{k: Nat, lo: Nat, hb: Bytes()}
  Body{st: D.St}
  Trail{k: Nat, cv: U32, sv: U32, st: D.St}
  Gap{}
  Bad{at: Nat, why: Why}

# the reader: its part, the output of the members done and not yet
# taken, the CRC-32 of the current member's bytes already taken, the
# cap left for the members to come, the offset of the next byte
type G is Data:
  G{ph: Ph, done: Bytes(), crc: U32, cap: Nat, pos: Nat}

def new(cap: Nat) -> G:
  G{Start{}, "", 0, cap, 0n}

def has(+flg: U32, bit: U32) -> Bool:
  U32.is_ne(U32.and(flg, bit), 0)

def next.hcrc(ok: Bool, hb: Bytes(), +cap: Nat, +pos: Nat) -> Ph:
  match ok:
    case True{}:
      HCrc{0n, 0n, hb}
    case False{}:
      Body{D.new(cap)}

def next.comm(ok: Bool, +flg: U32, hb: Bytes(), +cap: Nat, +pos: Nat) -> Ph:
  match ok:
    case True{}:
      Comm{flg, hb}
    case False{}:
      next.hcrc(has(flg, 2), hb, cap, pos)

def next.name(ok: Bool, +stage: Nat, +flg: U32, hb: Bytes(), +cap: Nat, +pos: Nat) -> Ph:
  match ok:
    case True{}:
      Name{flg, hb}
    case False{}:
      next.comm(Nat.is_le(stage, 2n) && has(flg, 16), flg, hb, cap, pos)

# after the fixed bytes (stage 0), FEXTRA (1), FNAME (2), FCOMMENT (3):
# the next field the flags ask for, or the body
def next.at(ok: Bool, +stage: Nat, +flg: U32, hb: Bytes(), +cap: Nat, +pos: Nat) -> Ph:
  match ok:
    case True{}:
      XLen{0n, 0n, flg, hb}
    case False{}:
      next.name(Nat.is_le(stage, 1n) && has(flg, 8), stage, flg, hb, cap, pos)

def next(+stage: Nat, +flg: U32, hb: Bytes(), +cap: Nat, +pos: Nat) -> Ph:
  next.at(Nat.is_eq(stage, 0n) && has(flg, 4), stage, flg, hb, cap, pos)

def bad(+pos: Nat, why: Why) -> Ph:
  Bad{pos, why}

# a byte of the fixed ten, k of them read before it
def head.at(last: Bool, +k: Nat, +flg: U32, hb: Bytes(), +cap: Nat, +pos: Nat) -> Ph:
  match last:
    case True{}:
      next(0n, flg, hb, cap, pos)
    case False{}:
      Head{1n+k, flg, hb}

def head(+k: Nat, +flg: U32, hb: Bytes(), +c: U32, +cap: Nat, +pos: Nat) -> Ph:
  Bool.pick(Ph, Nat.is_eq(k, 1n) && U32.is_ne(c, 139), Bad{pos, NotGzip{}},
    Bool.pick(Ph, Nat.is_eq(k, 2n) && U32.is_ne(c, 8), Bad{pos, BadMethod{}},
      Bool.pick(Ph, Nat.is_eq(k, 3n) && has(c, 224), Bad{pos, BadFlags{}},
        head.at(Nat.is_eq(k, 9n), k, D.u32.pick(Nat.is_eq(k, 3n), c, flg), Bytes.push(hb, c),
          cap, pos))))

def xlen.none(none: Bool, +len: Nat, +flg: U32, hb: Bytes(), +cap: Nat, +pos: Nat) -> Ph:
  match none:
    case True{}:
      next(1n, flg, hb, cap, pos)
    case False{}:
      XSkip{len, flg, hb}

def xlen.len(+len: Nat, +flg: U32, hb: Bytes(), +cap: Nat, +pos: Nat) -> Ph:
  xlen.none(Nat.is_eq(len, 0n), len, flg, hb, cap, pos)

def xlen.at(first: Bool, +lo: Nat, +flg: U32, hb: Bytes(), +c: U32, +cap: Nat, +pos: Nat) ->
  Ph:
  match first:
    case True{}:
      XLen{1n, U32.to_nat(c), flg, hb}
    case False{}:
      xlen.len(Nat.add(lo, Nat.mul(U32.to_nat(c), 256n)), flg, hb, cap, pos)

def xskip(last: Bool, +left: Nat, +flg: U32, hb: Bytes(), +cap: Nat, +pos: Nat) -> Ph:
  match last:
    case True{}:
      next(1n, flg, hb, cap, pos)
    case False{}:
      XSkip{Nat.sub(left, 1n), flg, hb}

# a byte of FNAME (stage 2) or FCOMMENT (3)
def zstr(zero: Bool, +stage: Nat, +flg: U32, +hb: Bytes(), +cap: Nat, +pos: Nat) -> Ph:
  match zero:
    case True{}:
      next(stage, flg, hb, cap, pos)
    case False{}:
      Bool.pick(Ph, Nat.is_eq(stage, 2n), Name{flg, hb}, Comm{flg, hb})

def hcrc.at(ok: Bool, +cap: Nat, +pos: Nat) -> Ph:
  match ok:
    case True{}:
      Body{D.new(cap)}
    case False{}:
      Bad{pos, BadHcrc{}}

def hcrc(first: Bool, +lo: Nat, +hb: Bytes(), +c: U32, +cap: Nat, +pos: Nat) -> Ph:
  match first:
    case True{}:
      HCrc{1n, U32.to_nat(c), hb}
    case False{}:
      hcrc.at(Nat.is_eq(Nat.add(lo, Nat.mul(U32.to_nat(c), 256n)),
        U32.to_nat(U32.and(D.crc32(hb, 0), 65535))), cap, pos)

# a byte of the deflate stream: at its end, the trailer
def body(+pos: Nat, st: D.St) -> Ph:
  match st:
    case D.St{m, o, bp}:
      match m:
        case D.End{}:
          Trail{0n, 0, 0, D.St{D.End{}, o, bp}}
        case D.Bad{why}:
          Bad{pos, Inflate{why}}
        case D.Get{l, a, k}:
          Body{D.St{D.Get{l, a, k}, o, bp}}
        case D.Walk{n, t, k}:
          Body{D.St{D.Walk{n, t, k}, o, bp}}
        case D.Skip{l}:
          Body{D.St{D.Skip{l}, o, bp}}

# the member's bytes not yet taken, and how many it has in all
def rest(st: D.St) -> Bytes() & Nat:
  match st:
    case D.St{m, o, bp}:
      match o:
        case D.O{out, keep, n, cap, t}:
          (Bytes.drop(out, keep), n)

def trail.size(ok: Bool, +sv: U32, +pos: Nat, +b: Bytes(), +n: Nat, +done: Bytes(), +crc: U32,
  +cap: Nat) -> G:
  match ok:
    case False{}:
      G{Bad{pos, BadCrc{}}, done, crc, cap, 1n+pos}
    case True{}:
      Bool.pick(G, U32.is_ne(U32.from_nat(n), sv), G{Bad{pos, BadSize{}}, done, crc, cap, 1n+pos},
        G{Gap{}, Bytes.append(done, b), 0, Nat.sub(cap, n), 1n+pos})

# the eighth byte: the member is checked
def trail.end(+cv: U32, +sv: U32, +pos: Nat, r: Bytes() & Nat, done: Bytes(), +crc: U32,
  +cap: Nat) -> G:
  (+b, +n) = r
  trail.size(U32.is_eq(D.crc32(b, crc), cv), sv, pos, b, n, done, crc, cap)

def trail.cv(+k: Nat, +cv: U32, +c: U32) -> U32:
  D.u32.pick(Nat.is_lt(k, 4n), U32.or(cv, U32.shln(c, Nat.mul(8n, Nat.mod(k, 4n)))), cv)

def trail.sv(+k: Nat, +sv: U32, +c: U32) -> U32:
  D.u32.pick(Nat.is_lt(k, 4n), sv, U32.or(sv, U32.shln(c, Nat.mul(8n, Nat.mod(k, 4n)))))

def trail(last: Bool, +k: Nat, +cv: U32, +sv: U32, st: D.St, +c: U32, done: Bytes(),
  +crc: U32, +cap: Nat, +pos: Nat) -> G:
  match last:
    case True{}:
      trail.end(trail.cv(k, cv, c), trail.sv(k, sv, c), pos, rest(st), done, crc, cap)
    case False{}:
      G{Trail{1n+k, trail.cv(k, cv, c), trail.sv(k, sv, c), st}, done, crc, cap, 1n+pos}

def gap(+c: U32, +pos: Nat) -> Ph:
  Bool.pick(Ph, U32.is_eq(c, 0), Gap{},
    Bool.pick(Ph, U32.is_eq(c, 31), Head{1n, 0, Bytes.push("", c)}, Bad{pos, NotGzip{}}))

def start(+c: U32, +pos: Nat) -> Ph:
  Bool.pick(Ph, U32.is_eq(c, 31), Head{1n, 0, Bytes.push("", c)}, Bad{pos, NotGzip{}})

# one byte
def step(g: G, +c: U32) -> G:
  match g:
    case G{ph, done, +crc, +cap, +pos}:
      match ph:
        case Start{}:
          G{start(c, pos), done, crc, cap, 1n+pos}
        case Head{+k, +flg, hb}:
          G{head(k, flg, hb, c, cap, pos), done, crc, cap, 1n+pos}
        case XLen{+k, lo, flg, hb}:
          G{xlen.at(Nat.is_eq(k, 0n), lo, flg, Bytes.push(hb, c), c, cap, pos), done, crc, cap,
            1n+pos}
        case XSkip{+left, flg, hb}:
          G{xskip(Nat.is_le(left, 1n), left, flg, Bytes.push(hb, c), cap, pos), done, crc, cap,
            1n+pos}
        case Name{flg, hb}:
          G{zstr(U32.is_eq(c, 0), 2n, flg, Bytes.push(hb, c), cap, pos), done, crc, cap, 1n+pos}
        case Comm{flg, hb}:
          G{zstr(U32.is_eq(c, 0), 3n, flg, Bytes.push(hb, c), cap, pos), done, crc, cap, 1n+pos}
        case HCrc{+k, lo, hb}:
          G{hcrc(Nat.is_eq(k, 0n), lo, hb, c, cap, pos), done, crc, cap, 1n+pos}
        case Body{st}:
          G{body(pos, D.step(st, c)), done, crc, cap, 1n+pos}
        case Trail{+k, cv, sv, st}:
          trail(Nat.is_eq(k, 7n), k, cv, sv, st, c, done, crc, cap, pos)
        case Gap{}:
          G{gap(c, pos), done, crc, cap, 1n+pos}
        case Bad{at, why}:
          G{Bad{at, why}, done, crc, cap, pos}

def wstep(e: Unit, g: G, c: U32) -> G:
  step(g, c)

def wadv(e: Unit, s: Bytes(), g: G) -> G & Bytes():
  Wr.one.step(~Unit, ~G, ~wstep, e, s, g)

# a read, fed to the reader
def feed(+s: Bytes(), g: G) -> G:
  Wr.feed_buf(~Unit, ~G, ~wstep, ~wadv, Unit{}, s, g)

def feed_list(bs: List<&2, U32>, g: G) -> G:
  Wr.feed(~Unit, ~G, ~wstep, Unit{}, bs, g)

def take.at(r: Bytes() & D.St, done: Bytes(), +crc: U32, +cap: Nat, +pos: Nat) -> Bytes() & G:
  (+b, st) = r
  (Bytes.append(done, b), G{Body{st}, "", D.crc32(b, crc), cap, pos})

def take.ph(ph: Ph, done: Bytes(), +crc: U32, +cap: Nat, +pos: Nat) -> Bytes() & G:
  match ph:
    case Body{st}:
      take.at(D.take(st), done, crc, cap, pos)
    case Start{}:
      (done, G{Start{}, "", crc, cap, pos})
    case Head{k, flg, hb}:
      (done, G{Head{k, flg, hb}, "", crc, cap, pos})
    case XLen{k, lo, flg, hb}:
      (done, G{XLen{k, lo, flg, hb}, "", crc, cap, pos})
    case XSkip{left, flg, hb}:
      (done, G{XSkip{left, flg, hb}, "", crc, cap, pos})
    case Name{flg, hb}:
      (done, G{Name{flg, hb}, "", crc, cap, pos})
    case Comm{flg, hb}:
      (done, G{Comm{flg, hb}, "", crc, cap, pos})
    case HCrc{k, lo, hb}:
      (done, G{HCrc{k, lo, hb}, "", crc, cap, pos})
    case Trail{k, cv, sv, st}:
      (done, G{Trail{k, cv, sv, st}, "", crc, cap, pos})
    case Gap{}:
      (done, G{Gap{}, "", crc, cap, pos})
    case Bad{at, why}:
      (done, G{Bad{at, why}, "", crc, cap, pos})

# the bytes decoded and not yet taken, and the reader without them
def take(g: G) -> Bytes() & G:
  match g:
    case G{ph, done, crc, cap, pos}:
      take.ph(ph, done, crc, cap, pos)

type Err is Data:
  Err{at: Nat, why: Why}

# the end of input: the bytes not yet taken, or why there are none
def finish(g: G) -> Result<&2, &2, Err, Bytes()>:
  match g:
    case G{ph, done, crc, cap, pos}:
      match ph:
        case Start{}:
          Done{done}
        case Gap{}:
          Done{done}
        case Bad{at, why}:
          Fail{Err{at, why}}
        case _:
          Fail{Err{pos, Truncated{}}}

# a whole gzip file, at most cap bytes out
def gunzip(cap: Nat, +s: Bytes()) -> Result<&2, &2, Err, Bytes()>:
  finish(feed(s, new(cap)))
