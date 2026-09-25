# Utf8 against CPython's decoder, over a real Bytes buffer: the corpus of
# demos/monoids/utf8.bend (Threefry slots, eight kinds of injury) is pushed into
# Base's Bytes() byte by byte, then `check` runs at fork depths 0, 3 and 8 and
# `first_bad` descends at 1, 4 and 9 -- every depth the same line. Cases: clean,
# cut three tails short, starting one byte into a scalar, empty, three bytes,
# and one per injury. utf8_gen.py prints this file.
import Base
import ../../power/rng.bend as Rng
import ../../power/utf8.bend as U

# -- the corpus: slot i is four bytes, little end first -------------------------

def asc(+r: U32, s: Nat) -> U32:
  U32.add(48, U32.and(U32.shrn(r, s), 63))

def tail(+c: U32, s: Nat) -> U32:
  U32.or(128, U32.and(U32.shrn(c, s), 63))

def enc2(+c: U32) -> U32:
  U32.or(U32.or(192, U32.shrn(c, 6n)), U32.shln(tail(c, 0n), 8n))

def enc3(+c: U32) -> U32:
  U32.or(U32.or(224, U32.shrn(c, 12n)),
    U32.or(U32.shln(tail(c, 6n), 8n), U32.shln(tail(c, 0n), 16n)))

def enc4(+c: U32) -> U32:
  U32.or(U32.or(240, U32.shrn(c, 18n)), U32.or(U32.shln(tail(c, 12n), 8n),
    U32.or(U32.shln(tail(c, 6n), 16n), U32.shln(tail(c, 0n), 24n))))

# a 3-byte scalar off 16 random bits: lifted past the overlong range, and a
# surrogate folded down into D000..D7FF, so ED still gets exercised
def cp3.lo(c: Bool, +x: U32) -> U32:
  match c:
    case True{}:
      U32.add(x, 2048)
    case False{}:
      x

def cp3.sur(c: Bool, +x: U32) -> U32:
  match c:
    case True{}:
      U32.sub(x, 2048)
    case False{}:
      x

def cp3(+r: U32) -> U32:
  +x = U32.and(U32.shrn(r, 3n), 65535)
  +y = cp3.lo(U32.is_lt(x, 2048), x)
  cp3.sur(Bool.and(U32.is_ge(y, 55296), U32.is_lt(y, 57344)), y)

def two(+r: U32) -> U32:
  enc2(U32.add(128, U32.and(U32.shrn(r, 3n), 1023)))

def gen.k(k: U32, +r: U32) -> U32:
  match k:
    case 2:
      U32.or(two(r), U32.shln(enc2(U32.add(128, U32.and(U32.shrn(r, 13n), 1023))), 16n))
    case 3:
      U32.or(enc3(cp3(r)), U32.shln(asc(r, 19n), 24n))
    case 4:
      U32.or(asc(r, 19n), U32.shln(enc3(cp3(r)), 8n))
    case 5:
      enc4(U32.add(65536, U32.mod(U32.shrn(r, 3n), 1048576)))
    case 6:
      enc4(U32.add(65536, U32.mod(U32.shrn(r, 3n), 1048576)))
    case 7:
      U32.or(two(r), U32.or(U32.shln(asc(r, 13n), 16n), U32.shln(asc(r, 19n), 24n)))
    case _:
      U32.or(U32.or(asc(r, 3n), U32.shln(asc(r, 9n), 8n)),
        U32.or(U32.shln(asc(r, 15n), 16n), U32.shln(asc(r, 21n), 24n)))

def gen(+seed: U32, +i: U32) -> U32:
  +r = Rng.u32(seed, 0, i)
  gen.k(U32.and(r, 7), r)

# the eight injuries, one per rule of table 3-7 that a real decoder must enforce
def poison(t: U32) -> U32:
  match t:
    case 0:
      1094795648 # 80 'A' 'A' 'A'   a lone tail
    case 1:
      1094823872 # C0 AF 'A' 'A'    an overlong '/'
    case 2:
      1098948845 # ED A0 80 'A'     U+D800
    case 3:
      1094812386 # E2 82 'A' 'A'    a euro sign cut short
    case 4:
      1094795765 # F5 'A' 'A' 'A'   past the last plane's lead
    case 5:
      2155909364 # F4 90 80 80      U+110000
    case 6:
      1098940640 # E0 80 80 'A'     an overlong NUL
    case _:
      1094828865 # 'A' C3 'A' 'A'   a lead with no tail

# Where: slot k1 carries injury t1, slot k2 injury t2 (4294967295: none).
type Where is Data:
  Where{seed: U32, k1: U32, t1: U32, k2: U32, t2: U32}

def slot.2(c: Bool, t2: U32, +seed: U32, +i: U32) -> U32:
  match c:
    case True{}:
      poison(t2)
    case False{}:
      gen(seed, i)

def slot.1(c: Bool, t1: U32, +k2: U32, t2: U32, +seed: U32, +i: U32) -> U32:
  match c:
    case True{}:
      poison(t1)
    case False{}:
      slot.2(U32.is_eq(i, k2), t2, seed, i)

def slot(+seed: U32, +k1: U32, +t1: U32, +k2: U32, +t2: U32, +i: U32) -> U32:
  slot.1(U32.is_eq(i, k1), t1, k2, t2, seed, i)

def byte(+seed: U32, +k1: U32, +t1: U32, +k2: U32, +t2: U32, +p: U32) -> U32:
  U32.and(U32.shrn(slot(seed, k1, t1, k2, t2, U32.shrn(p, 2n)),
    U32.to_nat(U32.shln(U32.and(p, 3), 3n))), 255)

def fill(k: Nat, +seed: U32, +k1: U32, +t1: U32, +k2: U32, +t2: U32, +p: U32,
  b: Bytes()) -> Bytes():
  match k:
    case 0n:
      b
    case 1n++q:
      fill(q, seed, k1, t1, k2, t2, U32.inc(p), Bytes.push(b, byte(seed, k1, t1, k2, t2, p)))

def buf(+seed: U32, +k1: U32, +t1: U32, +k2: U32, +t2: U32, +lo: U32, +n: U32) -> Bytes():
  fill(U32.to_nat(n), seed, k1, t1, k2, t2, lo, "")

def row(name: String, s: U.Sum) -> String:
  match s:
    case U.Sum{m, c}:
      name ++ " " ++ U32.show(m) ++ " " ++ U32.show(c)

def bad(name: String, +p: U32) -> String:
  name ++ " bad " ++ U32.show(p)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(row("clean", U.check(buf(1, 4294967295, 0, 4294967295, 0, 0, 4096), 0n)))
    IO.print(row("clean", U.check(buf(1, 4294967295, 0, 4294967295, 0, 0, 4096), 3n)))
    IO.print(row("clean", U.check(buf(1, 4294967295, 0, 4294967295, 0, 0, 4096), 8n)))
    IO.print(bad("clean", U.first_bad(buf(1, 4294967295, 0, 4294967295, 0, 0, 4096), 1n)))
    IO.print(bad("clean", U.first_bad(buf(1, 4294967295, 0, 4294967295, 0, 0, 4096), 4n)))
    IO.print(bad("clean", U.first_bad(buf(1, 4294967295, 0, 4294967295, 0, 0, 4096), 9n)))
    IO.print(row("cut", U.check(buf(3, 4294967295, 0, 4294967295, 0, 0, 4097), 0n)))
    IO.print(row("cut", U.check(buf(3, 4294967295, 0, 4294967295, 0, 0, 4097), 3n)))
    IO.print(row("cut", U.check(buf(3, 4294967295, 0, 4294967295, 0, 0, 4097), 8n)))
    IO.print(bad("cut", U.first_bad(buf(3, 4294967295, 0, 4294967295, 0, 0, 4097), 1n)))
    IO.print(bad("cut", U.first_bad(buf(3, 4294967295, 0, 4294967295, 0, 0, 4097), 4n)))
    IO.print(bad("cut", U.first_bad(buf(3, 4294967295, 0, 4294967295, 0, 0, 4097), 9n)))
    IO.print(row("mid", U.check(buf(3, 4294967295, 0, 4294967295, 0, 1, 4000), 0n)))
    IO.print(row("mid", U.check(buf(3, 4294967295, 0, 4294967295, 0, 1, 4000), 3n)))
    IO.print(row("mid", U.check(buf(3, 4294967295, 0, 4294967295, 0, 1, 4000), 8n)))
    IO.print(bad("mid", U.first_bad(buf(3, 4294967295, 0, 4294967295, 0, 1, 4000), 1n)))
    IO.print(bad("mid", U.first_bad(buf(3, 4294967295, 0, 4294967295, 0, 1, 4000), 4n)))
    IO.print(bad("mid", U.first_bad(buf(3, 4294967295, 0, 4294967295, 0, 1, 4000), 9n)))
    IO.print(row("empty", U.check(buf(1, 4294967295, 0, 4294967295, 0, 0, 0), 0n)))
    IO.print(row("empty", U.check(buf(1, 4294967295, 0, 4294967295, 0, 0, 0), 3n)))
    IO.print(row("empty", U.check(buf(1, 4294967295, 0, 4294967295, 0, 0, 0), 8n)))
    IO.print(bad("empty", U.first_bad(buf(1, 4294967295, 0, 4294967295, 0, 0, 0), 1n)))
    IO.print(bad("empty", U.first_bad(buf(1, 4294967295, 0, 4294967295, 0, 0, 0), 4n)))
    IO.print(bad("empty", U.first_bad(buf(1, 4294967295, 0, 4294967295, 0, 0, 0), 9n)))
    IO.print(row("three", U.check(buf(5, 4294967295, 0, 4294967295, 0, 0, 3), 0n)))
    IO.print(row("three", U.check(buf(5, 4294967295, 0, 4294967295, 0, 0, 3), 3n)))
    IO.print(row("three", U.check(buf(5, 4294967295, 0, 4294967295, 0, 0, 3), 8n)))
    IO.print(bad("three", U.first_bad(buf(5, 4294967295, 0, 4294967295, 0, 0, 3), 1n)))
    IO.print(bad("three", U.first_bad(buf(5, 4294967295, 0, 4294967295, 0, 0, 3), 4n)))
    IO.print(bad("three", U.first_bad(buf(5, 4294967295, 0, 4294967295, 0, 0, 3), 9n)))
    IO.print(row("poison0", U.check(buf(9, 200, 0, 900, 3, 0, 5001), 0n)))
    IO.print(row("poison0", U.check(buf(9, 200, 0, 900, 3, 0, 5001), 3n)))
    IO.print(row("poison0", U.check(buf(9, 200, 0, 900, 3, 0, 5001), 8n)))
    IO.print(bad("poison0", U.first_bad(buf(9, 200, 0, 900, 3, 0, 5001), 1n)))
    IO.print(bad("poison0", U.first_bad(buf(9, 200, 0, 900, 3, 0, 5001), 4n)))
    IO.print(bad("poison0", U.first_bad(buf(9, 200, 0, 900, 3, 0, 5001), 9n)))
    IO.print(row("poison1", U.check(buf(10, 297, 1, 900, 4, 0, 5001), 0n)))
    IO.print(row("poison1", U.check(buf(10, 297, 1, 900, 4, 0, 5001), 3n)))
    IO.print(row("poison1", U.check(buf(10, 297, 1, 900, 4, 0, 5001), 8n)))
    IO.print(bad("poison1", U.first_bad(buf(10, 297, 1, 900, 4, 0, 5001), 1n)))
    IO.print(bad("poison1", U.first_bad(buf(10, 297, 1, 900, 4, 0, 5001), 4n)))
    IO.print(bad("poison1", U.first_bad(buf(10, 297, 1, 900, 4, 0, 5001), 9n)))
    IO.print(row("poison2", U.check(buf(11, 394, 2, 900, 5, 0, 5001), 0n)))
    IO.print(row("poison2", U.check(buf(11, 394, 2, 900, 5, 0, 5001), 3n)))
    IO.print(row("poison2", U.check(buf(11, 394, 2, 900, 5, 0, 5001), 8n)))
    IO.print(bad("poison2", U.first_bad(buf(11, 394, 2, 900, 5, 0, 5001), 1n)))
    IO.print(bad("poison2", U.first_bad(buf(11, 394, 2, 900, 5, 0, 5001), 4n)))
    IO.print(bad("poison2", U.first_bad(buf(11, 394, 2, 900, 5, 0, 5001), 9n)))
    IO.print(row("poison3", U.check(buf(12, 491, 3, 900, 6, 0, 5001), 0n)))
    IO.print(row("poison3", U.check(buf(12, 491, 3, 900, 6, 0, 5001), 3n)))
    IO.print(row("poison3", U.check(buf(12, 491, 3, 900, 6, 0, 5001), 8n)))
    IO.print(bad("poison3", U.first_bad(buf(12, 491, 3, 900, 6, 0, 5001), 1n)))
    IO.print(bad("poison3", U.first_bad(buf(12, 491, 3, 900, 6, 0, 5001), 4n)))
    IO.print(bad("poison3", U.first_bad(buf(12, 491, 3, 900, 6, 0, 5001), 9n)))
    IO.print(row("poison4", U.check(buf(13, 588, 4, 900, 7, 0, 5001), 0n)))
    IO.print(row("poison4", U.check(buf(13, 588, 4, 900, 7, 0, 5001), 3n)))
    IO.print(row("poison4", U.check(buf(13, 588, 4, 900, 7, 0, 5001), 8n)))
    IO.print(bad("poison4", U.first_bad(buf(13, 588, 4, 900, 7, 0, 5001), 1n)))
    IO.print(bad("poison4", U.first_bad(buf(13, 588, 4, 900, 7, 0, 5001), 4n)))
    IO.print(bad("poison4", U.first_bad(buf(13, 588, 4, 900, 7, 0, 5001), 9n)))
    IO.print(row("poison5", U.check(buf(14, 685, 5, 900, 0, 0, 5001), 0n)))
    IO.print(row("poison5", U.check(buf(14, 685, 5, 900, 0, 0, 5001), 3n)))
    IO.print(row("poison5", U.check(buf(14, 685, 5, 900, 0, 0, 5001), 8n)))
    IO.print(bad("poison5", U.first_bad(buf(14, 685, 5, 900, 0, 0, 5001), 1n)))
    IO.print(bad("poison5", U.first_bad(buf(14, 685, 5, 900, 0, 0, 5001), 4n)))
    IO.print(bad("poison5", U.first_bad(buf(14, 685, 5, 900, 0, 0, 5001), 9n)))
    IO.print(row("poison6", U.check(buf(15, 782, 6, 900, 1, 0, 5001), 0n)))
    IO.print(row("poison6", U.check(buf(15, 782, 6, 900, 1, 0, 5001), 3n)))
    IO.print(row("poison6", U.check(buf(15, 782, 6, 900, 1, 0, 5001), 8n)))
    IO.print(bad("poison6", U.first_bad(buf(15, 782, 6, 900, 1, 0, 5001), 1n)))
    IO.print(bad("poison6", U.first_bad(buf(15, 782, 6, 900, 1, 0, 5001), 4n)))
    IO.print(bad("poison6", U.first_bad(buf(15, 782, 6, 900, 1, 0, 5001), 9n)))
    IO.print(row("poison7", U.check(buf(16, 879, 7, 900, 2, 0, 5001), 0n)))
    IO.print(row("poison7", U.check(buf(16, 879, 7, 900, 2, 0, 5001), 3n)))
    IO.print(row("poison7", U.check(buf(16, 879, 7, 900, 2, 0, 5001), 8n)))
    IO.print(bad("poison7", U.first_bad(buf(16, 879, 7, 900, 2, 0, 5001), 1n)))
    IO.print(bad("poison7", U.first_bad(buf(16, 879, 7, 900, 2, 0, 5001), 4n)))
    IO.print(bad("poison7", U.first_bad(buf(16, 879, 7, 900, 2, 0, 5001), 9n)))
#|clean 2290649216 2416
#|clean 2290649216 2416
#|clean 2290649216 2416
#|clean bad 4294967295
#|clean bad 4294967295
#|clean bad 4294967295
#|cut 2290649217 2487
#|cut 2290649217 2487
#|cut 2290649217 2487
#|cut bad 4097
#|cut bad 4097
#|cut bad 4097
#|mid 2156398728 2413
#|mid 2156398728 2413
#|mid 2156398728 2413
#|mid bad 0
#|mid bad 0
#|mid bad 0
#|empty 1985229328 0
#|empty 1985229328 0
#|empty 1985229328 0
#|empty bad 4294967295
#|empty bad 4294967295
#|empty bad 4294967295
#|three 2290649216 1
#|three 2290649216 1
#|three 2290649216 1
#|three bad 4294967295
#|three bad 4294967295
#|three bad 4294967295
#|poison0 2290649224 2994
#|poison0 2290649224 2994
#|poison0 2290649224 2994
#|poison0 bad 800
#|poison0 bad 800
#|poison0 bad 800
#|poison1 2290649224 3058
#|poison1 2290649224 3058
#|poison1 2290649224 3058
#|poison1 bad 1188
#|poison1 bad 1188
#|poison1 bad 1188
#|poison2 2290649224 3007
#|poison2 2290649224 3007
#|poison2 2290649224 3007
#|poison2 bad 1577
#|poison2 bad 1577
#|poison2 bad 1577
#|poison3 2290649224 2979
#|poison3 2290649224 2979
#|poison3 2290649224 2979
#|poison3 bad 1966
#|poison3 bad 1966
#|poison3 bad 1966
#|poison4 2290649224 2987
#|poison4 2290649224 2987
#|poison4 2290649224 2987
#|poison4 bad 2352
#|poison4 bad 2352
#|poison4 bad 2352
#|poison5 2290649224 2922
#|poison5 2290649224 2922
#|poison5 2290649224 2922
#|poison5 bad 2741
#|poison5 bad 2741
#|poison5 bad 2741
#|poison6 2290649224 2983
#|poison6 2290649224 2983
#|poison6 2290649224 2983
#|poison6 bad 3129
#|poison6 bad 3129
#|poison6 bad 3129
#|poison7 2290649224 2992
#|poison7 2290649224 2992
#|poison7 2290649224 2992
#|poison7 bad 3518
#|poison7 bad 3518
#|poison7 bad 3518
