# 200,000 records of one shape, 10,800,001 bytes, parsed four times as an event
# stream: {"i":12345,"s":"abcdefgh","b":true,"a":[12345,12345]}. Every event is
# folded into the checksum with its span, so a span off by one changes it. The
# digits come out of the key's bits rather than five divisions, which is what
# the C twin's jdoc does too: one builder, one arithmetic, one checksum.
import Base
import ../../../power/bytes.bend as Bytes
import ../../../power/json.bend as Json

def key(+i: U32) -> U32:
  U32.xor(U32.mul(U32.inc(i), 2654435761), U32.shrn(i, 3n))

def oct(b: Bytes(), +x: U32, s: Nat) -> Bytes():
  Bytes.push(b, U32.add(48, U32.and(U32.shrn(x, s), 7)))

# five digits, the first never 0, so the lexeme is legal json
def d5(b: Bytes(), +x: U32) -> Bytes():
  oct(oct(oct(oct(Bytes.push(b, U32.add(49, U32.and(x, 7))), x, 3n), x, 6n), x, 9n), x, 12n)

def hx(b: Bytes(), +x: U32, s: Nat) -> Bytes():
  Bytes.push(b, U32.add(97, U32.and(U32.shrn(x, s), 15)))

# eight letters a-p: no quote, no backslash, so the string body is one run
def s8(b: Bytes(), +x: U32) -> Bytes():
  hx(hx(hx(hx(hx(hx(hx(hx(b, x, 0n), x, 4n), x, 8n), x, 12n), x, 16n), x, 20n), x, 24n), x, 28n)

# true and null are both four bytes, so a record is a fixed 54
def flag.b(b: Bytes(), odd: Bool) -> Bytes():
  match odd:
    case True{}:
      Bytes.from_list([110, 117, 108, 108], b)
    case False{}:
      Bytes.from_list([116, 114, 117, 101], b)

def flag(b: Bytes(), +x: U32) -> Bytes():
  flag.b(b, U32.is_eq(U32.and(x, 1), 1))

def rec(b: Bytes(), +h: U32) -> Bytes():
  b1 = d5(Bytes.from_list([123, 34, 105, 34, 58], b), h)
  b2 = s8(Bytes.from_list([44, 34, 115, 34, 58, 34], b1), h)
  b3 = flag(Bytes.from_list([34, 44, 34, 98, 34, 58], b2), h)
  b4 = d5(Bytes.from_list([44, 34, 97, 34, 58, 91], b3), h)
  b5 = d5(Bytes.push(b4, 44), U32.shrn(h, 7n))
  Bytes.from_list([93, 125, 44], b5)

def recs(fuel: Nat, +i: U32, b: Bytes()) -> Bytes():
  match fuel:
    case 0n:
      b
    case 1n++p:
      recs(p, U32.inc(i), rec(b, key(i)))

# the last record left a trailing comma behind; drop it and shut the array
def close(r: Bytes() & U32) -> Bytes():
  (b, +n) = r
  Bytes.push(Bytes.truncate(b, U32.sub(n, 1)), 93)

def doc(fuel: Nat) -> Bytes():
  close(Bytes.len(recs(fuel, 0, Bytes.push(Bytes.new(), 91))))

def rot7(+v: U32) -> U32:
  U32.or(U32.shln(v, 7n), U32.shrn(v, 25n))

# the rotate is not decoration: this event stream is 200,000 copies of one
# record, and a plain acc*31+x over it is a geometric series whose 2-adic
# valuation climbs -- the checksum arrived with 18 trailing zeros, and the
# forked bench's tree fold over 256 such blocks came out exactly 0. Feeding the
# high bits back kills it.
def mix(+acc: U32, +x: U32) -> U32:
  rot7(U32.add(U32.mul(acc, 31), x))

def mix3(+acc: U32, +c: U32, +at: U32, +len: U32) -> U32:
  mix(mix(mix(acc, c), at), len)

def flag.code(+acc: U32, v: Bool) -> U32:
  match v:
    case True{}:
      mix(acc, 8)
    case False{}:
      mix(acc, 9)

def ev(+acc: U32, e: Json.Event) -> U32:
  match e:
    case Json.ObjOpen{}:
      mix(acc, 1)
    case Json.ObjEnd{}:
      mix(acc, 2)
    case Json.ArrOpen{}:
      mix(acc, 3)
    case Json.ArrEnd{}:
      mix(acc, 4)
    case Json.Field{at, len}:
      mix3(acc, 5, at, len)
    case Json.Str{at, len}:
      mix3(acc, 6, at, len)
    case Json.Num{at, len}:
      mix3(acc, 7, at, len)
    case Json.Flag{v}:
      flag.code(acc, v)
    case Json.Null{}:
      mix(acc, 10)
    case Json.Eof{}:
      mix(acc, 11)
    case Json.Bad{at, why}:
      mix(mix(acc, 12), at)

type Fold is Type:
  Fold{s: Json.St, acc: U32, on: Bool}

def fold.mk(+e: Json.Event, +acc: U32, s: Json.St) -> Fold:
  Fold{s, ev(acc, e), Json.live(e)}

def fold.step(acc: U32, r: Json.St & Json.Event) -> Fold:
  (s, +e) = r
  fold.mk(e, acc, s)

def fold.go(fuel: Nat, f: Fold) -> Fold:
  match fuel:
    case 0n:
      f
    case 1n++p:
      match f:
        case Fold{s, acc, on}:
          match on:
            case True{}:
              fold.go(p, fold.step(acc, Json.next(s)))
            case False{}:
              Fold{s, acc, False{}}

def fold.fin(+acc: U32, r: Bytes() & U32) -> Bytes() & U32:
  (b, l) = r
  (b, acc)

def fold.out(f: Fold) -> Bytes() & U32:
  match f:
    case Fold{s, acc, on}:
      fold.fin(acc, Json.finish(s))

# thirteen events a record, so three million is a million more than the document
# can raise; the walk stops itself at Eof
def once(acc: U32, b: Bytes()) -> Bytes() & U32:
  fold.out(fold.go(3000000n, Fold{Json.start(b, 4000000000), acc, True{}}))

def step(ba: Bytes() & U32) -> Bytes() & U32:
  (b, acc) = ba
  once(acc, b)

def rep(k: Nat, ba: Bytes() & U32) -> Bytes() & U32:
  match k:
    case 0n:
      ba
    case 1n++p:
      rep(p, step(ba))

def snd(ba: Bytes() & U32) -> U32:
  (b, acc) = ba
  acc

def main() -> U32:
  snd(rep(4n, (doc(200000n), 0)))
