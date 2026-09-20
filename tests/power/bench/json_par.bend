# json, forked: 2^8 blocks, each building its own 800-record document and
# scanning it four times in its own leaf -- the sequential bench's work in 43 KB
# pieces. The parser state is a plain value with no shared table, so unlike
# radix the fork is free: what a leaf owns is its own document.
import Base
import ../../../power/bytes.bend as Bytes
import ../../../power/json.bend as Json

def key(+i: U32) -> U32:
  U32.xor(U32.mul(U32.inc(i), 2654435761), U32.shrn(i, 3n))

def oct(b: Bytes.Bytes, +x: U32, s: Nat) -> Bytes.Bytes:
  Bytes.push(b, U32.add(48, U32.and(U32.shrn(x, s), 7)))

def d5(b: Bytes.Bytes, +x: U32) -> Bytes.Bytes:
  oct(oct(oct(oct(Bytes.push(b, U32.add(49, U32.and(x, 7))), x, 3n), x, 6n), x, 9n), x, 12n)

def hx(b: Bytes.Bytes, +x: U32, s: Nat) -> Bytes.Bytes:
  Bytes.push(b, U32.add(97, U32.and(U32.shrn(x, s), 15)))

def s8(b: Bytes.Bytes, +x: U32) -> Bytes.Bytes:
  hx(hx(hx(hx(hx(hx(hx(hx(b, x, 0n), x, 4n), x, 8n), x, 12n), x, 16n), x, 20n), x, 24n), x, 28n)

def flag.b(b: Bytes.Bytes, odd: Bool) -> Bytes.Bytes:
  match odd:
    case True{}:
      Bytes.from_list([110, 117, 108, 108], b)
    case False{}:
      Bytes.from_list([116, 114, 117, 101], b)

def flag(b: Bytes.Bytes, +x: U32) -> Bytes.Bytes:
  flag.b(b, U32.is_eq(U32.and(x, 1), 1))

def rec(b: Bytes.Bytes, +h: U32) -> Bytes.Bytes:
  b1 = d5(Bytes.from_list([123, 34, 105, 34, 58], b), h)
  b2 = s8(Bytes.from_list([44, 34, 115, 34, 58, 34], b1), h)
  b3 = flag(Bytes.from_list([34, 44, 34, 98, 34, 58], b2), h)
  b4 = d5(Bytes.from_list([44, 34, 97, 34, 58, 91], b3), h)
  b5 = d5(Bytes.push(b4, 44), U32.shrn(h, 7n))
  Bytes.from_list([93, 125, 44], b5)

def recs(fuel: Nat, +i: U32, b: Bytes.Bytes) -> Bytes.Bytes:
  match fuel:
    case 0n:
      b
    case 1n++p:
      recs(p, U32.inc(i), rec(b, key(i)))

def close(r: Bytes.Bytes & U32) -> Bytes.Bytes:
  (b, +n) = r
  Bytes.push(Bytes.truncate(b, U32.sub(n, 1)), 93)

def doc(fuel: Nat, +lo: U32) -> Bytes.Bytes:
  close(Bytes.len(recs(fuel, lo, Bytes.push(Bytes.new(), 91))))

def rot7(+v: U32) -> U32:
  U32.or(U32.shln(v, 7n), U32.shrn(v, 25n))

# see json.bend: a plain acc*31+x over this many copies of one record loses its
# low bits to the geometric series, and the tree fold of 256 such blocks is 0
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

def fold.fin(+acc: U32, r: Bytes.Bytes & U32) -> Bytes.Bytes & U32:
  (b, l) = r
  (b, acc)

def fold.out(f: Fold) -> Bytes.Bytes & U32:
  match f:
    case Fold{s, acc, on}:
      fold.fin(acc, Json.finish(s))

# thirteen events a record, so 20,000 is more than 800 records can raise
def once(acc: U32, b: Bytes.Bytes) -> Bytes.Bytes & U32:
  fold.out(fold.go(20000n, Fold{Json.start(b, 4000000000), acc, True{}}))

def step(ba: Bytes.Bytes & U32) -> Bytes.Bytes & U32:
  (b, acc) = ba
  once(acc, b)

def rep(k: Nat, ba: Bytes.Bytes & U32) -> Bytes.Bytes & U32:
  match k:
    case 0n:
      ba
    case 1n++p:
      rep(p, step(ba))

def snd(ba: Bytes.Bytes & U32) -> U32:
  (b, acc) = ba
  acc

def block(+lo: U32) -> U32:
  snd(rep(4n, (doc(800n, lo), 0)))

# 801, not 800: with an even stride every block draws the same true/null pattern
# out of key(), every block checksums the same, and 256 equal leaves fold to 0
def par(d: Nat, +lo: U32, +n: U32) -> U32:
  match d:
    case 0n:
      block(lo)
    case 1n++p:
      +h = U32.shr(n)
      a b = par(p, lo, h) par(p, U32.add(lo, h), h)
      mix(a, b)

def main() -> U32:
  par(8n, 0, 205056)
