# The proofs of power/deflate_laws.bend.
import Base
import ../wire/reader.bend as Wr
import ./deflate.bend as D
import ./gzip.bend as Z
import ./deflate_laws.bend as Laws
import ./inflate_proof.bend as IP

# The reads
# =========
#
# The inflate machine and the gunzip machine are byte-step readers; the
# reader kit (wire/reader.bend) proves chunking once for every such
# reader, and a one-byte move needs no obligation but the kit's own.

def Laws.inflate_split(a, b, st):
  Wr.feed_split(~Unit, ~D.St, ~D.wstep, Unit{}, a, b, st)

def adv_ok(+e: Unit, +s: Bytes(), p: D.St) ->
  {Wr.feed_buf.last(~Unit, ~D.St, ~D.wstep, e, D.wadv(e, s, p)) ==
    Wr.feed_buf.slow(~Unit, ~D.St, ~D.wstep, e, s, p) : D.St}:
  Wr.one.step_ok(~Unit, ~D.St, ~D.wstep, e, s, p)

def Laws.inflate_buf(s, st):
  Wr.feed_buf_is_feed(~Unit, ~D.St, ~D.wstep, ~D.wadv, ~adv_ok, Unit{}, s, st)

def Laws.inflate_fast(cap, s):
  IP.inflate_fast(cap, s)

def Laws.inflate_buf_split(a, b, st):
  Wr.feed_buf_split(~Unit, ~D.St, ~D.wstep, ~D.wadv, ~adv_ok, Unit{}, a, b, st)

def Laws.gunzip_split(a, b, g):
  Wr.feed_split(~Unit, ~Z.G, ~Z.wstep, Unit{}, a, b, g)

def gz_adv_ok(+e: Unit, +s: Bytes(), p: Z.G) ->
  {Wr.feed_buf.last(~Unit, ~Z.G, ~Z.wstep, e, Z.wadv(e, s, p)) ==
    Wr.feed_buf.slow(~Unit, ~Z.G, ~Z.wstep, e, s, p) : Z.G}:
  Wr.one.step_ok(~Unit, ~Z.G, ~Z.wstep, e, s, p)

def Laws.gunzip_buf(s, g):
  Wr.feed_buf_is_feed(~Unit, ~Z.G, ~Z.wstep, ~Z.wadv, ~gz_adv_ok, Unit{}, s, g)

# The fixed points
# ----------------
#
# A byte is eight steps and the bit offset goes round once: from any of
# the eight offsets a refused (or ended) machine is where it was.

type B8 is Data:
  O0{}
  O1{}
  O2{}
  O3{}
  O4{}
  O5{}
  O6{}
  O7{}

def b8n(k: B8) -> Nat:
  match k:
    case O0{}:
      0n
    case O1{}:
      1n
    case O2{}:
      2n
    case O3{}:
      3n
    case O4{}:
      4n
    case O5{}:
      5n
    case O6{}:
      6n
    case O7{}:
      7n

type Held is Data:
  HBad{why: D.Why, o: D.O, k: B8}
  HEnd{o: D.O, k: B8}

def held(x: Held) -> D.St:
  match x:
    case HBad{why, o, k}:
      D.St{D.Bad{why}, o, b8n(k)}
    case HEnd{o, k}:
      D.St{D.End{}, o, b8n(k)}

def held_fix(+e: Unit, +x: Held, +c: U32) -> {D.wstep(e, held(x), c) == held(x) : D.St}:
  match x:
    case HBad{why, o, k}:
      match k:
        case O0{}:
          {==}
        case O1{}:
          {==}
        case O2{}:
          {==}
        case O3{}:
          {==}
        case O4{}:
          {==}
        case O5{}:
          {==}
        case O6{}:
          {==}
        case O7{}:
          {==}
    case HEnd{o, k}:
      match k:
        case O0{}:
          {==}
        case O1{}:
          {==}
        case O2{}:
          {==}
        case O3{}:
          {==}
        case O4{}:
          {==}
        case O5{}:
          {==}
        case O6{}:
          {==}
        case O7{}:
          {==}

def held_feeds(+s: List<&2, U32>, +x: Held) ->
  {D.feed_list(s, held(x)) == held(x) : D.St}:
  Wr.bad_feeds(~Unit, ~D.St, ~D.wstep, ~Held, ~held, ~held_fix, Unit{}, s, x)

def bad_at(+s: List<&2, U32>, +why: D.Why, +o: D.O, +bp: Nat) ->
  {Nat.is_lt(bp, 8n) == True{} : Bool} -> {D.feed_list(s, D.St{D.Bad{why}, o, bp}) == D.St{D.Bad{why}, o, bp} : D.St}:
  match bp:
    case 0n:
      lt => held_feeds(s, HBad{why, o, O0{}})
    case 1n+p0:
      match p0:
        case 0n:
          lt => held_feeds(s, HBad{why, o, O1{}})
        case 1n+p1:
          match p1:
            case 0n:
              lt => held_feeds(s, HBad{why, o, O2{}})
            case 1n+p2:
              match p2:
                case 0n:
                  lt => held_feeds(s, HBad{why, o, O3{}})
                case 1n+p3:
                  match p3:
                    case 0n:
                      lt => held_feeds(s, HBad{why, o, O4{}})
                    case 1n+p4:
                      match p4:
                        case 0n:
                          lt => held_feeds(s, HBad{why, o, O5{}})
                        case 1n+p5:
                          match p5:
                            case 0n:
                              lt => held_feeds(s, HBad{why, o, O6{}})
                            case 1n+p6:
                              match p6:
                                case 0n:
                                  lt => held_feeds(s, HBad{why, o, O7{}})
                                case 1n+p7:
                                  lt => Nat.lt_zero({D.feed_list(s, D.St{D.Bad{why}, o, 8n+p7}) == D.St{D.Bad{why}, o, 8n+p7} : D.St}, p7, lt)

def end_at(+s: List<&2, U32>, +o: D.O, +bp: Nat) ->
  {Nat.is_lt(bp, 8n) == True{} : Bool} -> {D.feed_list(s, D.St{D.End{}, o, bp}) == D.St{D.End{}, o, bp} : D.St}:
  match bp:
    case 0n:
      lt => held_feeds(s, HEnd{o, O0{}})
    case 1n+p0:
      match p0:
        case 0n:
          lt => held_feeds(s, HEnd{o, O1{}})
        case 1n+p1:
          match p1:
            case 0n:
              lt => held_feeds(s, HEnd{o, O2{}})
            case 1n+p2:
              match p2:
                case 0n:
                  lt => held_feeds(s, HEnd{o, O3{}})
                case 1n+p3:
                  match p3:
                    case 0n:
                      lt => held_feeds(s, HEnd{o, O4{}})
                    case 1n+p4:
                      match p4:
                        case 0n:
                          lt => held_feeds(s, HEnd{o, O5{}})
                        case 1n+p5:
                          match p5:
                            case 0n:
                              lt => held_feeds(s, HEnd{o, O6{}})
                            case 1n+p6:
                              match p6:
                                case 0n:
                                  lt => held_feeds(s, HEnd{o, O7{}})
                                case 1n+p7:
                                  lt => Nat.lt_zero({D.feed_list(s, D.St{D.End{}, o, 8n+p7}) == D.St{D.End{}, o, 8n+p7} : D.St}, p7, lt)

def Laws.inflate_bad(s, why, o, bp, lt):
  bad_at(s, why, o, bp)(lt)

def Laws.inflate_end(s, o, bp, lt):
  end_at(s, o, bp)(lt)

type GB is Data:
  GB{at: Nat, why: Z.Why, done: Bytes(), crc: U32, cap: Nat, pos: Nat}

def gb(x: GB) -> Z.G:
  match x:
    case GB{at, why, done, crc, cap, pos}:
      Z.G{Z.Bad{at, why}, done, crc, cap, pos}

def gb_fix(+e: Unit, +x: GB, +c: U32) -> {Z.wstep(e, gb(x), c) == gb(x) : Z.G}:
  match x:
    case GB{at, why, done, crc, cap, pos}:
      {==}

def Laws.gunzip_bad(s, at, why, done, crc, cap, pos):
  Wr.bad_feeds(~Unit, ~Z.G, ~Z.wstep, ~GB, ~gb, ~gb_fix, Unit{}, s, GB{at, why, done, crc, cap, pos})


# CRC-32
# ======
#
# The table method is right because the CRC's bit step is linear over
# xor (lin): eight steps of the register z are eight steps of its low
# byte, which the table holds (tab, cell by cell), xor eight steps of
# the rest, which has no bit to fold in and so is only shifted (hi8).
# U32 is Word(32n), 32 Bools low bit first; the lemmas are on words.

# Words
# -----

def bx_comm(+a: Bool, +b: Bool) -> {Bool.xor(a, b) == Bool.xor(b, a) : Bool}:
  match a b:
    case False{} False{}:
      {==}
    case False{} True{}:
      {==}
    case True{} False{}:
      {==}
    case True{} True{}:
      {==}

def wcon_eq(-p: Nat, -a: Bool, -b: Bool, -s: Word(p), -t: Word(p), e1: {a == b : Bool},
  e2: {s == t : Word(p)}) -> {WCon{a, s} == WCon{b, t} : Word(1n+p)}:
  %Equal.sym(Bool, a, b, e1) : {WCon{_, s} == WCon{b, t} : Word(1n+p)}
  %Equal.sym(Word(p), s, t, e2) : {WCon{b, _} == WCon{b, t} : Word(1n+p)}
  {==}

def x_comm(+n: Nat, +a: Word(n), +b: Word(n)) -> {Word.xor(n, a, b) == Word.xor(n, b, a) : Word(n)}:
  match n:
    case 0n:
      match a b:
        case WNil{} WNil{}:
          {==}
    case 1n+p:
      match a b:
        case WCon{+ah, +at} WCon{+bh, +bt}:
          wcon_eq(p, Bool.xor(ah, bh), Bool.xor(bh, ah), Word.xor(p, at, bt), Word.xor(p, bt, at),
            bx_comm(ah, bh), x_comm(p, at, bt))

def bx_assoc(+a: Bool, +b: Bool, +c: Bool) ->
  {Bool.xor(Bool.xor(a, b), c) == Bool.xor(a, Bool.xor(b, c)) : Bool}:
  match a b c:
    case False{} False{} False{}:
      {==}
    case False{} False{} True{}:
      {==}
    case False{} True{} False{}:
      {==}
    case False{} True{} True{}:
      {==}
    case True{} False{} False{}:
      {==}
    case True{} False{} True{}:
      {==}
    case True{} True{} False{}:
      {==}
    case True{} True{} True{}:
      {==}

def x_assoc(+n: Nat, +a: Word(n), +b: Word(n), +c: Word(n)) ->
  {Word.xor(n, Word.xor(n, a, b), c) == Word.xor(n, a, Word.xor(n, b, c)) : Word(n)}:
  match n:
    case 0n:
      match a b c:
        case WNil{} WNil{} WNil{}:
          {==}
    case 1n+p:
      match a b c:
        case WCon{+ah, +at} WCon{+bh, +bt} WCon{+ch, +ct}:
          wcon_eq(p, Bool.xor(Bool.xor(ah, bh), ch), Bool.xor(ah, Bool.xor(bh, ch)),
            Word.xor(p, Word.xor(p, at, bt), ct), Word.xor(p, at, Word.xor(p, bt, ct)),
            bx_assoc(ah, bh, ch), x_assoc(p, at, bt, ct))

def bx_self(+a: Bool) -> {Bool.xor(a, a) == False{} : Bool}:
  match a:
    case False{}:
      {==}
    case True{}:
      {==}

def x_self(+n: Nat, +a: Word(n)) -> {Word.xor(n, a, a) == Word.zero(n) : Word(n)}:
  match n:
    case 0n:
      match a:
        case WNil{}:
          {==}
    case 1n+p:
      match a:
        case WCon{+ah, +at}:
          wcon_eq(p, Bool.xor(ah, ah), False{}, Word.xor(p, at, at), Word.zero(p), bx_self(ah),
            x_self(p, at))

def x_zero(+n: Nat, +a: Word(n)) -> {Word.xor(n, Word.zero(n), a) == a : Word(n)}:
  match n:
    case 0n:
      match a:
        case WNil{}:
          {==}
    case 1n+p:
      match a:
        case WCon{+ah, +at}:
          wcon_eq(p, ah, ah, Word.xor(p, Word.zero(p), at), at, {==}, x_zero(p, at))

def pad_xor(+n: Nat, +a: Word(n), +b: Word(n)) ->
  {Word.shr.pad(n, Word.xor(n, a, b)) == Word.xor(1n+n, Word.shr.pad(n, a), Word.shr.pad(n, b)) :
    Word(1n+n)}:
  match n:
    case 0n:
      match a b:
        case WNil{} WNil{}:
          {==}
    case 1n+p:
      match a b:
        case WCon{+ah, +at} WCon{+bh, +bt}:
          wcon_eq(1n+p, Bool.xor(ah, bh), Bool.xor(ah, bh), Word.shr.pad(p, Word.xor(p, at, bt)),
            Word.xor(1n+p, Word.shr.pad(p, at), Word.shr.pad(p, bt)), {==}, pad_xor(p, at, bt))

def band_f(+a: Bool) -> {Bool.and(a, False{}) == False{} : Bool}:
  match a:
    case False{}:
      {==}
    case True{}:
      {==}

def and_zero(+n: Nat, +a: Word(n)) -> {Word.and(n, a, Word.zero(n)) == Word.zero(n) : Word(n)}:
  match n:
    case 0n:
      match a:
        case WNil{}:
          {==}
    case 1n+p:
      match a:
        case WCon{+ah, +at}:
          wcon_eq(p, Bool.and(ah, False{}), False{}, Word.and(p, at, Word.zero(p)), Word.zero(p),
            band_f(ah), and_zero(p, at))

# U32
# ---

def ux_comm(+a: U32, +b: U32) -> {U32.xor(a, b) == U32.xor(b, a) : U32}:
  match a b:
    case U32{+x} U32{+y}:
      Equal.cong(Word(32n), U32, w => U32{w}, Word.xor(32n, x, y), Word.xor(32n, y, x),
        x_comm(32n, x, y))

def ux_assoc(+a: U32, +b: U32, +c: U32) ->
  {U32.xor(U32.xor(a, b), c) == U32.xor(a, U32.xor(b, c)) : U32}:
  match a b c:
    case U32{+x} U32{+y} U32{+z}:
      Equal.cong(Word(32n), U32, w => U32{w}, Word.xor(32n, Word.xor(32n, x, y), z),
        Word.xor(32n, x, Word.xor(32n, y, z)), x_assoc(32n, x, y, z))

def ux_self(+a: U32) -> {U32.xor(a, a) == U32{Word.zero(32n)} : U32}:
  match a:
    case U32{+x}:
      Equal.cong(Word(32n), U32, w => U32{w}, Word.xor(32n, x, x), Word.zero(32n), x_self(32n, x))

def ux_zero(+a: U32) -> {U32.xor(U32{Word.zero(32n)}, a) == a : U32}:
  match a:
    case U32{+x}:
      Equal.cong(Word(32n), U32, w => U32{w}, Word.xor(32n, Word.zero(32n), x), x, x_zero(32n, x))

# (a ^ p) ^ b is (a ^ b) ^ p
def ux_swap(+a: U32, +p: U32, +b: U32) ->
  {U32.xor(U32.xor(a, p), b) == U32.xor(U32.xor(a, b), p) : U32}:
  %Equal.sym(U32, U32.xor(U32.xor(a, p), b), U32.xor(a, U32.xor(p, b)), ux_assoc(a, p, b)) :
    {_ == U32.xor(U32.xor(a, b), p) : U32}
  %ux_comm(b, p) : {U32.xor(a, _) == U32.xor(U32.xor(a, b), p) : U32}
  Equal.sym(U32, U32.xor(U32.xor(a, b), p), U32.xor(a, U32.xor(b, p)), ux_assoc(a, b, p))

# The CRC's one bit, read off the word
# -----------------------------------

def shr1(t: Word(31n)) -> U32:
  U32{Word.shr.pad(31n, t)}

def cbit(b: Bool, +t: Word(31n)) -> U32:
  D.u32.pick(b, U32.xor(shr1(t), D.POLY()), shr1(t))

def bitc(+b: Bool, +t: Word(31n)) -> {D.crc.bit(U32{WCon{b, t}}) == cbit(b, t) : U32}:
  match b:
    case False{}:
      %Equal.sym(Word(31n), Word.and(31n, t, Word.zero(31n)), Word.zero(31n), and_zero(31n, t)) :
        {D.u32.pick(U32.is_eq(U32{WCon{False{}, _}}, 1), U32.xor(shr1(t), D.POLY()), shr1(t)) ==
          cbit(False{}, t) : U32}
      {==}
    case True{}:
      %Equal.sym(Word(31n), Word.and(31n, t, Word.zero(31n)), Word.zero(31n), and_zero(31n, t)) :
        {D.u32.pick(U32.is_eq(U32{WCon{True{}, _}}, 1), U32.xor(shr1(t), D.POLY()), shr1(t)) ==
          cbit(True{}, t) : U32}
      {==}

def sh_x(+s: Word(31n), +t: Word(31n)) ->
  {shr1(Word.xor(31n, s, t)) == U32.xor(shr1(s), shr1(t)) : U32}:
  Equal.cong(Word(32n), U32, w => U32{w}, Word.shr.pad(31n, Word.xor(31n, s, t)),
    Word.xor(32n, Word.shr.pad(31n, s), Word.shr.pad(31n, t)), pad_xor(31n, s, t))

# (a ^ p) ^ (b ^ p) is a ^ b
def ux_cancel(+a: U32, +p: U32, +b: U32) ->
  {U32.xor(U32.xor(a, p), U32.xor(b, p)) == U32.xor(a, b) : U32}:
  %ux_assoc(U32.xor(a, p), b, p) : {_ == U32.xor(a, b) : U32}
  %Equal.sym(U32, U32.xor(U32.xor(a, p), b), U32.xor(U32.xor(a, b), p), ux_swap(a, p, b)) :
    {U32.xor(_, p) == U32.xor(a, b) : U32}
  %Equal.sym(U32, U32.xor(U32.xor(U32.xor(a, b), p), p), U32.xor(U32.xor(a, b), U32.xor(p, p)),
    ux_assoc(U32.xor(a, b), p, p)) : {_ == U32.xor(a, b) : U32}
  %Equal.sym(U32, U32.xor(p, p), U32{Word.zero(32n)}, ux_self(p)) :
    {U32.xor(U32.xor(a, b), _) == U32.xor(a, b) : U32}
  %ux_comm(U32{Word.zero(32n)}, U32.xor(a, b)) : {_ == U32.xor(a, b) : U32}
  ux_zero(U32.xor(a, b))

# one CRC bit of a ^ b is the bit of a ^ the bit of b: the step is linear
def lin(+a: Bool, +b: Bool, +s: Word(31n), +t: Word(31n)) ->
  {cbit(Bool.xor(a, b), Word.xor(31n, s, t)) == U32.xor(cbit(a, s), cbit(b, t)) : U32}:
  match a b:
    case False{} False{}:
      sh_x(s, t)
    case True{} False{}:
      %Equal.sym(U32, shr1(Word.xor(31n, s, t)), U32.xor(shr1(s), shr1(t)), sh_x(s, t)) :
        {U32.xor(_, D.POLY()) == U32.xor(U32.xor(shr1(s), D.POLY()), shr1(t)) : U32}
      Equal.sym(U32, U32.xor(U32.xor(shr1(s), D.POLY()), shr1(t)),
        U32.xor(U32.xor(shr1(s), shr1(t)), D.POLY()), ux_swap(shr1(s), D.POLY(), shr1(t)))
    case False{} True{}:
      %Equal.sym(U32, shr1(Word.xor(31n, s, t)), U32.xor(shr1(s), shr1(t)), sh_x(s, t)) :
        {U32.xor(_, D.POLY()) == U32.xor(shr1(s), U32.xor(shr1(t), D.POLY())) : U32}
      ux_assoc(shr1(s), shr1(t), D.POLY())
    case True{} True{}:
      %Equal.sym(U32, shr1(Word.xor(31n, s, t)), U32.xor(shr1(s), shr1(t)), sh_x(s, t)) :
        {_ == U32.xor(U32.xor(shr1(s), D.POLY()), U32.xor(shr1(t), D.POLY())) : U32}
      Equal.sym(U32, U32.xor(U32.xor(shr1(s), D.POLY()), U32.xor(shr1(t), D.POLY())),
        U32.xor(shr1(s), shr1(t)), ux_cancel(shr1(s), D.POLY(), shr1(t)))

def bit_lin(+x: U32, +y: U32) ->
  {D.crc.bit(U32.xor(x, y)) == U32.xor(D.crc.bit(x), D.crc.bit(y)) : U32}:
  match x y:
    case U32{WCon{+a, +s}} U32{WCon{+b, +t}}:
      %Equal.sym(U32, D.crc.bit(U32{WCon{Bool.xor(a, b), Word.xor(31n, s, t)}}),
        cbit(Bool.xor(a, b), Word.xor(31n, s, t)), bitc(Bool.xor(a, b), Word.xor(31n, s, t))) :
        {_ == U32.xor(D.crc.bit(U32{WCon{a, s}}), D.crc.bit(U32{WCon{b, t}})) : U32}
      %Equal.sym(U32, D.crc.bit(U32{WCon{a, s}}), cbit(a, s), bitc(a, s)) :
        {cbit(Bool.xor(a, b), Word.xor(31n, s, t)) == U32.xor(_, D.crc.bit(U32{WCon{b, t}})) : U32}
      %Equal.sym(U32, D.crc.bit(U32{WCon{b, t}}), cbit(b, t), bitc(b, t)) :
        {cbit(Bool.xor(a, b), Word.xor(31n, s, t)) == U32.xor(cbit(a, s), _) : U32}
      lin(a, b, s, t)

def bits_lin(+n: Nat, +x: U32, +y: U32) ->
  {D.crc.bits(n, U32.xor(x, y)) == U32.xor(D.crc.bits(n, x), D.crc.bits(n, y)) : U32}:
  match n:
    case 0n:
      {==}
    case 1n+p:
      %Equal.sym(U32, D.crc.bit(U32.xor(x, y)), U32.xor(D.crc.bit(x), D.crc.bit(y)), bit_lin(x, y)) :
        {D.crc.bits(p, _) == U32.xor(D.crc.bits(p, D.crc.bit(x)), D.crc.bits(p, D.crc.bit(y))) : U32}
      bits_lin(p, D.crc.bit(x), D.crc.bit(y))

def bx_f(+a: Bool) -> {Bool.xor(a, False{}) == a : Bool}:
  match a:
    case False{}:
      {==}
    case True{}:
      {==}

def band_t(+a: Bool) -> {Bool.and(a, True{}) == a : Bool}:
  match a:
    case False{}:
      {==}
    case True{}:
      {==}

# the low byte of a word, and the rest
def lo(z0: Bool, z1: Bool, z2: Bool, z3: Bool, z4: Bool, z5: Bool, z6: Bool, z7: Bool) -> U32:
  U32{WCon{z0, WCon{z1, WCon{z2, WCon{z3, WCon{z4, WCon{z5, WCon{z6, WCon{z7, Word.zero(24n)}}}}}}}}}

def hi(+r: Word(24n)) -> U32:
  U32{WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, r}}}}}}}}}

def split(+z0: Bool, +z1: Bool, +z2: Bool, +z3: Bool, +z4: Bool, +z5: Bool, +z6: Bool, +z7: Bool, +r: Word(24n)) ->
  {U32.xor(lo(z0, z1, z2, z3, z4, z5, z6, z7), hi(r)) == U32{WCon{z0, WCon{z1, WCon{z2, WCon{z3, WCon{z4, WCon{z5, WCon{z6, WCon{z7, r}}}}}}}}} : U32}:
  Equal.cong(Word(32n), U32, w => U32{w}, WCon{Bool.xor(z0, False{}), WCon{Bool.xor(z1, False{}), WCon{Bool.xor(z2, False{}), WCon{Bool.xor(z3, False{}), WCon{Bool.xor(z4, False{}), WCon{Bool.xor(z5, False{}), WCon{Bool.xor(z6, False{}), WCon{Bool.xor(z7, False{}), Word.xor(24n, Word.zero(24n), r)}}}}}}}}, WCon{z0, WCon{z1, WCon{z2, WCon{z3, WCon{z4, WCon{z5, WCon{z6, WCon{z7, r}}}}}}}},
    wcon_eq(31n, Bool.xor(z0, False{}), z0, WCon{Bool.xor(z1, False{}), WCon{Bool.xor(z2, False{}), WCon{Bool.xor(z3, False{}), WCon{Bool.xor(z4, False{}), WCon{Bool.xor(z5, False{}), WCon{Bool.xor(z6, False{}), WCon{Bool.xor(z7, False{}), Word.xor(24n, Word.zero(24n), r)}}}}}}}, WCon{z1, WCon{z2, WCon{z3, WCon{z4, WCon{z5, WCon{z6, WCon{z7, r}}}}}}}, bx_f(z0), wcon_eq(30n, Bool.xor(z1, False{}), z1, WCon{Bool.xor(z2, False{}), WCon{Bool.xor(z3, False{}), WCon{Bool.xor(z4, False{}), WCon{Bool.xor(z5, False{}), WCon{Bool.xor(z6, False{}), WCon{Bool.xor(z7, False{}), Word.xor(24n, Word.zero(24n), r)}}}}}}, WCon{z2, WCon{z3, WCon{z4, WCon{z5, WCon{z6, WCon{z7, r}}}}}}, bx_f(z1), wcon_eq(29n, Bool.xor(z2, False{}), z2, WCon{Bool.xor(z3, False{}), WCon{Bool.xor(z4, False{}), WCon{Bool.xor(z5, False{}), WCon{Bool.xor(z6, False{}), WCon{Bool.xor(z7, False{}), Word.xor(24n, Word.zero(24n), r)}}}}}, WCon{z3, WCon{z4, WCon{z5, WCon{z6, WCon{z7, r}}}}}, bx_f(z2), wcon_eq(28n, Bool.xor(z3, False{}), z3, WCon{Bool.xor(z4, False{}), WCon{Bool.xor(z5, False{}), WCon{Bool.xor(z6, False{}), WCon{Bool.xor(z7, False{}), Word.xor(24n, Word.zero(24n), r)}}}}, WCon{z4, WCon{z5, WCon{z6, WCon{z7, r}}}}, bx_f(z3), wcon_eq(27n, Bool.xor(z4, False{}), z4, WCon{Bool.xor(z5, False{}), WCon{Bool.xor(z6, False{}), WCon{Bool.xor(z7, False{}), Word.xor(24n, Word.zero(24n), r)}}}, WCon{z5, WCon{z6, WCon{z7, r}}}, bx_f(z4), wcon_eq(26n, Bool.xor(z5, False{}), z5, WCon{Bool.xor(z6, False{}), WCon{Bool.xor(z7, False{}), Word.xor(24n, Word.zero(24n), r)}}, WCon{z6, WCon{z7, r}}, bx_f(z5), wcon_eq(25n, Bool.xor(z6, False{}), z6, WCon{Bool.xor(z7, False{}), Word.xor(24n, Word.zero(24n), r)}, WCon{z7, r}, bx_f(z6), wcon_eq(24n, Bool.xor(z7, False{}), z7, Word.xor(24n, Word.zero(24n), r), r, bx_f(z7), x_zero(24n, r))))))))))

def low(+z0: Bool, +z1: Bool, +z2: Bool, +z3: Bool, +z4: Bool, +z5: Bool, +z6: Bool, +z7: Bool, +r: Word(24n)) ->
  {U32.and(U32{WCon{z0, WCon{z1, WCon{z2, WCon{z3, WCon{z4, WCon{z5, WCon{z6, WCon{z7, r}}}}}}}}}, 255) == lo(z0, z1, z2, z3, z4, z5, z6, z7) : U32}:
  Equal.cong(Word(32n), U32, w => U32{w}, WCon{Bool.and(z0, True{}), WCon{Bool.and(z1, True{}), WCon{Bool.and(z2, True{}), WCon{Bool.and(z3, True{}), WCon{Bool.and(z4, True{}), WCon{Bool.and(z5, True{}), WCon{Bool.and(z6, True{}), WCon{Bool.and(z7, True{}), Word.and(24n, r, Word.zero(24n))}}}}}}}}, WCon{z0, WCon{z1, WCon{z2, WCon{z3, WCon{z4, WCon{z5, WCon{z6, WCon{z7, Word.zero(24n)}}}}}}}},
    wcon_eq(31n, Bool.and(z0, True{}), z0, WCon{Bool.and(z1, True{}), WCon{Bool.and(z2, True{}), WCon{Bool.and(z3, True{}), WCon{Bool.and(z4, True{}), WCon{Bool.and(z5, True{}), WCon{Bool.and(z6, True{}), WCon{Bool.and(z7, True{}), Word.and(24n, r, Word.zero(24n))}}}}}}}, WCon{z1, WCon{z2, WCon{z3, WCon{z4, WCon{z5, WCon{z6, WCon{z7, Word.zero(24n)}}}}}}}, band_t(z0), wcon_eq(30n, Bool.and(z1, True{}), z1, WCon{Bool.and(z2, True{}), WCon{Bool.and(z3, True{}), WCon{Bool.and(z4, True{}), WCon{Bool.and(z5, True{}), WCon{Bool.and(z6, True{}), WCon{Bool.and(z7, True{}), Word.and(24n, r, Word.zero(24n))}}}}}}, WCon{z2, WCon{z3, WCon{z4, WCon{z5, WCon{z6, WCon{z7, Word.zero(24n)}}}}}}, band_t(z1), wcon_eq(29n, Bool.and(z2, True{}), z2, WCon{Bool.and(z3, True{}), WCon{Bool.and(z4, True{}), WCon{Bool.and(z5, True{}), WCon{Bool.and(z6, True{}), WCon{Bool.and(z7, True{}), Word.and(24n, r, Word.zero(24n))}}}}}, WCon{z3, WCon{z4, WCon{z5, WCon{z6, WCon{z7, Word.zero(24n)}}}}}, band_t(z2), wcon_eq(28n, Bool.and(z3, True{}), z3, WCon{Bool.and(z4, True{}), WCon{Bool.and(z5, True{}), WCon{Bool.and(z6, True{}), WCon{Bool.and(z7, True{}), Word.and(24n, r, Word.zero(24n))}}}}, WCon{z4, WCon{z5, WCon{z6, WCon{z7, Word.zero(24n)}}}}, band_t(z3), wcon_eq(27n, Bool.and(z4, True{}), z4, WCon{Bool.and(z5, True{}), WCon{Bool.and(z6, True{}), WCon{Bool.and(z7, True{}), Word.and(24n, r, Word.zero(24n))}}}, WCon{z5, WCon{z6, WCon{z7, Word.zero(24n)}}}, band_t(z4), wcon_eq(26n, Bool.and(z5, True{}), z5, WCon{Bool.and(z6, True{}), WCon{Bool.and(z7, True{}), Word.and(24n, r, Word.zero(24n))}}, WCon{z6, WCon{z7, Word.zero(24n)}}, band_t(z5), wcon_eq(25n, Bool.and(z6, True{}), z6, WCon{Bool.and(z7, True{}), Word.and(24n, r, Word.zero(24n))}, WCon{z7, Word.zero(24n)}, band_t(z6), wcon_eq(24n, Bool.and(z7, True{}), z7, Word.and(24n, r, Word.zero(24n)), Word.zero(24n), band_t(z7), and_zero(24n, r))))))))))

def hi8(+r: Word(24n), +z0: Bool, +z1: Bool, +z2: Bool, +z3: Bool, +z4: Bool, +z5: Bool, +z6: Bool, +z7: Bool) ->
  {D.crc.bits(8n, hi(r)) == U32.shrn(U32{WCon{z0, WCon{z1, WCon{z2, WCon{z3, WCon{z4, WCon{z5, WCon{z6, WCon{z7, r}}}}}}}}}, 8n) : U32}:
  %Equal.sym(U32, D.crc.bit(U32{WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, r}}}}}}}}}), U32{Word.shr.pad(31n, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, r}}}}}}})}, bitc(False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, r}}}}}}})) :
    {D.crc.bits(7n, _) == U32.shrn(U32{WCon{z0, WCon{z1, WCon{z2, WCon{z3, WCon{z4, WCon{z5, WCon{z6, WCon{z7, r}}}}}}}}}, 8n) : U32}
  %Equal.sym(U32, D.crc.bit(U32{WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, Word.shr.pad(24n, r)}}}}}}}}), U32{Word.shr.pad(31n, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, Word.shr.pad(24n, r)}}}}}})}, bitc(False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, Word.shr.pad(24n, r)}}}}}})) :
    {D.crc.bits(6n, _) == U32.shrn(U32{WCon{z0, WCon{z1, WCon{z2, WCon{z3, WCon{z4, WCon{z5, WCon{z6, WCon{z7, r}}}}}}}}}, 8n) : U32}
  %Equal.sym(U32, D.crc.bit(U32{WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, Word.shr.pad(25n, Word.shr.pad(24n, r))}}}}}}}), U32{Word.shr.pad(31n, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, Word.shr.pad(25n, Word.shr.pad(24n, r))}}}}})}, bitc(False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, Word.shr.pad(25n, Word.shr.pad(24n, r))}}}}})) :
    {D.crc.bits(5n, _) == U32.shrn(U32{WCon{z0, WCon{z1, WCon{z2, WCon{z3, WCon{z4, WCon{z5, WCon{z6, WCon{z7, r}}}}}}}}}, 8n) : U32}
  %Equal.sym(U32, D.crc.bit(U32{WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, Word.shr.pad(26n, Word.shr.pad(25n, Word.shr.pad(24n, r)))}}}}}}), U32{Word.shr.pad(31n, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, Word.shr.pad(26n, Word.shr.pad(25n, Word.shr.pad(24n, r)))}}}})}, bitc(False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, Word.shr.pad(26n, Word.shr.pad(25n, Word.shr.pad(24n, r)))}}}})) :
    {D.crc.bits(4n, _) == U32.shrn(U32{WCon{z0, WCon{z1, WCon{z2, WCon{z3, WCon{z4, WCon{z5, WCon{z6, WCon{z7, r}}}}}}}}}, 8n) : U32}
  %Equal.sym(U32, D.crc.bit(U32{WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, Word.shr.pad(27n, Word.shr.pad(26n, Word.shr.pad(25n, Word.shr.pad(24n, r))))}}}}}), U32{Word.shr.pad(31n, WCon{False{}, WCon{False{}, WCon{False{}, Word.shr.pad(27n, Word.shr.pad(26n, Word.shr.pad(25n, Word.shr.pad(24n, r))))}}})}, bitc(False{}, WCon{False{}, WCon{False{}, WCon{False{}, Word.shr.pad(27n, Word.shr.pad(26n, Word.shr.pad(25n, Word.shr.pad(24n, r))))}}})) :
    {D.crc.bits(3n, _) == U32.shrn(U32{WCon{z0, WCon{z1, WCon{z2, WCon{z3, WCon{z4, WCon{z5, WCon{z6, WCon{z7, r}}}}}}}}}, 8n) : U32}
  %Equal.sym(U32, D.crc.bit(U32{WCon{False{}, WCon{False{}, WCon{False{}, Word.shr.pad(28n, Word.shr.pad(27n, Word.shr.pad(26n, Word.shr.pad(25n, Word.shr.pad(24n, r)))))}}}}), U32{Word.shr.pad(31n, WCon{False{}, WCon{False{}, Word.shr.pad(28n, Word.shr.pad(27n, Word.shr.pad(26n, Word.shr.pad(25n, Word.shr.pad(24n, r)))))}})}, bitc(False{}, WCon{False{}, WCon{False{}, Word.shr.pad(28n, Word.shr.pad(27n, Word.shr.pad(26n, Word.shr.pad(25n, Word.shr.pad(24n, r)))))}})) :
    {D.crc.bits(2n, _) == U32.shrn(U32{WCon{z0, WCon{z1, WCon{z2, WCon{z3, WCon{z4, WCon{z5, WCon{z6, WCon{z7, r}}}}}}}}}, 8n) : U32}
  %Equal.sym(U32, D.crc.bit(U32{WCon{False{}, WCon{False{}, Word.shr.pad(29n, Word.shr.pad(28n, Word.shr.pad(27n, Word.shr.pad(26n, Word.shr.pad(25n, Word.shr.pad(24n, r))))))}}}), U32{Word.shr.pad(31n, WCon{False{}, Word.shr.pad(29n, Word.shr.pad(28n, Word.shr.pad(27n, Word.shr.pad(26n, Word.shr.pad(25n, Word.shr.pad(24n, r))))))})}, bitc(False{}, WCon{False{}, Word.shr.pad(29n, Word.shr.pad(28n, Word.shr.pad(27n, Word.shr.pad(26n, Word.shr.pad(25n, Word.shr.pad(24n, r))))))})) :
    {D.crc.bits(1n, _) == U32.shrn(U32{WCon{z0, WCon{z1, WCon{z2, WCon{z3, WCon{z4, WCon{z5, WCon{z6, WCon{z7, r}}}}}}}}}, 8n) : U32}
  %Equal.sym(U32, D.crc.bit(U32{WCon{False{}, Word.shr.pad(30n, Word.shr.pad(29n, Word.shr.pad(28n, Word.shr.pad(27n, Word.shr.pad(26n, Word.shr.pad(25n, Word.shr.pad(24n, r)))))))}}), U32{Word.shr.pad(31n, Word.shr.pad(30n, Word.shr.pad(29n, Word.shr.pad(28n, Word.shr.pad(27n, Word.shr.pad(26n, Word.shr.pad(25n, Word.shr.pad(24n, r))))))))}, bitc(False{}, Word.shr.pad(30n, Word.shr.pad(29n, Word.shr.pad(28n, Word.shr.pad(27n, Word.shr.pad(26n, Word.shr.pad(25n, Word.shr.pad(24n, r))))))))) :
    {D.crc.bits(0n, _) == U32.shrn(U32{WCon{z0, WCon{z1, WCon{z2, WCon{z3, WCon{z4, WCon{z5, WCon{z6, WCon{z7, r}}}}}}}}}, 8n) : U32}
  {==}


# the table's cell at each byte is the byte's eight CRC bits
def tab(+z0: Bool, +z1: Bool, +z2: Bool, +z3: Bool, +z4: Bool, +z5: Bool, +z6: Bool, +z7: Bool) ->
  {D.crc.cell(D.crc.tab(), lo(z0, z1, z2, z3, z4, z5, z6, z7)) == D.crc.entry(lo(z0, z1, z2, z3, z4, z5, z6, z7)) : U32}:
  match z0 z1 z2 z3 z4 z5 z6 z7:
    case False{} False{} False{} False{} False{} False{} False{} False{}:
      {==}
    case False{} False{} False{} False{} False{} False{} False{} True{}:
      {==}
    case False{} False{} False{} False{} False{} False{} True{} False{}:
      {==}
    case False{} False{} False{} False{} False{} False{} True{} True{}:
      {==}
    case False{} False{} False{} False{} False{} True{} False{} False{}:
      {==}
    case False{} False{} False{} False{} False{} True{} False{} True{}:
      {==}
    case False{} False{} False{} False{} False{} True{} True{} False{}:
      {==}
    case False{} False{} False{} False{} False{} True{} True{} True{}:
      {==}
    case False{} False{} False{} False{} True{} False{} False{} False{}:
      {==}
    case False{} False{} False{} False{} True{} False{} False{} True{}:
      {==}
    case False{} False{} False{} False{} True{} False{} True{} False{}:
      {==}
    case False{} False{} False{} False{} True{} False{} True{} True{}:
      {==}
    case False{} False{} False{} False{} True{} True{} False{} False{}:
      {==}
    case False{} False{} False{} False{} True{} True{} False{} True{}:
      {==}
    case False{} False{} False{} False{} True{} True{} True{} False{}:
      {==}
    case False{} False{} False{} False{} True{} True{} True{} True{}:
      {==}
    case False{} False{} False{} True{} False{} False{} False{} False{}:
      {==}
    case False{} False{} False{} True{} False{} False{} False{} True{}:
      {==}
    case False{} False{} False{} True{} False{} False{} True{} False{}:
      {==}
    case False{} False{} False{} True{} False{} False{} True{} True{}:
      {==}
    case False{} False{} False{} True{} False{} True{} False{} False{}:
      {==}
    case False{} False{} False{} True{} False{} True{} False{} True{}:
      {==}
    case False{} False{} False{} True{} False{} True{} True{} False{}:
      {==}
    case False{} False{} False{} True{} False{} True{} True{} True{}:
      {==}
    case False{} False{} False{} True{} True{} False{} False{} False{}:
      {==}
    case False{} False{} False{} True{} True{} False{} False{} True{}:
      {==}
    case False{} False{} False{} True{} True{} False{} True{} False{}:
      {==}
    case False{} False{} False{} True{} True{} False{} True{} True{}:
      {==}
    case False{} False{} False{} True{} True{} True{} False{} False{}:
      {==}
    case False{} False{} False{} True{} True{} True{} False{} True{}:
      {==}
    case False{} False{} False{} True{} True{} True{} True{} False{}:
      {==}
    case False{} False{} False{} True{} True{} True{} True{} True{}:
      {==}
    case False{} False{} True{} False{} False{} False{} False{} False{}:
      {==}
    case False{} False{} True{} False{} False{} False{} False{} True{}:
      {==}
    case False{} False{} True{} False{} False{} False{} True{} False{}:
      {==}
    case False{} False{} True{} False{} False{} False{} True{} True{}:
      {==}
    case False{} False{} True{} False{} False{} True{} False{} False{}:
      {==}
    case False{} False{} True{} False{} False{} True{} False{} True{}:
      {==}
    case False{} False{} True{} False{} False{} True{} True{} False{}:
      {==}
    case False{} False{} True{} False{} False{} True{} True{} True{}:
      {==}
    case False{} False{} True{} False{} True{} False{} False{} False{}:
      {==}
    case False{} False{} True{} False{} True{} False{} False{} True{}:
      {==}
    case False{} False{} True{} False{} True{} False{} True{} False{}:
      {==}
    case False{} False{} True{} False{} True{} False{} True{} True{}:
      {==}
    case False{} False{} True{} False{} True{} True{} False{} False{}:
      {==}
    case False{} False{} True{} False{} True{} True{} False{} True{}:
      {==}
    case False{} False{} True{} False{} True{} True{} True{} False{}:
      {==}
    case False{} False{} True{} False{} True{} True{} True{} True{}:
      {==}
    case False{} False{} True{} True{} False{} False{} False{} False{}:
      {==}
    case False{} False{} True{} True{} False{} False{} False{} True{}:
      {==}
    case False{} False{} True{} True{} False{} False{} True{} False{}:
      {==}
    case False{} False{} True{} True{} False{} False{} True{} True{}:
      {==}
    case False{} False{} True{} True{} False{} True{} False{} False{}:
      {==}
    case False{} False{} True{} True{} False{} True{} False{} True{}:
      {==}
    case False{} False{} True{} True{} False{} True{} True{} False{}:
      {==}
    case False{} False{} True{} True{} False{} True{} True{} True{}:
      {==}
    case False{} False{} True{} True{} True{} False{} False{} False{}:
      {==}
    case False{} False{} True{} True{} True{} False{} False{} True{}:
      {==}
    case False{} False{} True{} True{} True{} False{} True{} False{}:
      {==}
    case False{} False{} True{} True{} True{} False{} True{} True{}:
      {==}
    case False{} False{} True{} True{} True{} True{} False{} False{}:
      {==}
    case False{} False{} True{} True{} True{} True{} False{} True{}:
      {==}
    case False{} False{} True{} True{} True{} True{} True{} False{}:
      {==}
    case False{} False{} True{} True{} True{} True{} True{} True{}:
      {==}
    case False{} True{} False{} False{} False{} False{} False{} False{}:
      {==}
    case False{} True{} False{} False{} False{} False{} False{} True{}:
      {==}
    case False{} True{} False{} False{} False{} False{} True{} False{}:
      {==}
    case False{} True{} False{} False{} False{} False{} True{} True{}:
      {==}
    case False{} True{} False{} False{} False{} True{} False{} False{}:
      {==}
    case False{} True{} False{} False{} False{} True{} False{} True{}:
      {==}
    case False{} True{} False{} False{} False{} True{} True{} False{}:
      {==}
    case False{} True{} False{} False{} False{} True{} True{} True{}:
      {==}
    case False{} True{} False{} False{} True{} False{} False{} False{}:
      {==}
    case False{} True{} False{} False{} True{} False{} False{} True{}:
      {==}
    case False{} True{} False{} False{} True{} False{} True{} False{}:
      {==}
    case False{} True{} False{} False{} True{} False{} True{} True{}:
      {==}
    case False{} True{} False{} False{} True{} True{} False{} False{}:
      {==}
    case False{} True{} False{} False{} True{} True{} False{} True{}:
      {==}
    case False{} True{} False{} False{} True{} True{} True{} False{}:
      {==}
    case False{} True{} False{} False{} True{} True{} True{} True{}:
      {==}
    case False{} True{} False{} True{} False{} False{} False{} False{}:
      {==}
    case False{} True{} False{} True{} False{} False{} False{} True{}:
      {==}
    case False{} True{} False{} True{} False{} False{} True{} False{}:
      {==}
    case False{} True{} False{} True{} False{} False{} True{} True{}:
      {==}
    case False{} True{} False{} True{} False{} True{} False{} False{}:
      {==}
    case False{} True{} False{} True{} False{} True{} False{} True{}:
      {==}
    case False{} True{} False{} True{} False{} True{} True{} False{}:
      {==}
    case False{} True{} False{} True{} False{} True{} True{} True{}:
      {==}
    case False{} True{} False{} True{} True{} False{} False{} False{}:
      {==}
    case False{} True{} False{} True{} True{} False{} False{} True{}:
      {==}
    case False{} True{} False{} True{} True{} False{} True{} False{}:
      {==}
    case False{} True{} False{} True{} True{} False{} True{} True{}:
      {==}
    case False{} True{} False{} True{} True{} True{} False{} False{}:
      {==}
    case False{} True{} False{} True{} True{} True{} False{} True{}:
      {==}
    case False{} True{} False{} True{} True{} True{} True{} False{}:
      {==}
    case False{} True{} False{} True{} True{} True{} True{} True{}:
      {==}
    case False{} True{} True{} False{} False{} False{} False{} False{}:
      {==}
    case False{} True{} True{} False{} False{} False{} False{} True{}:
      {==}
    case False{} True{} True{} False{} False{} False{} True{} False{}:
      {==}
    case False{} True{} True{} False{} False{} False{} True{} True{}:
      {==}
    case False{} True{} True{} False{} False{} True{} False{} False{}:
      {==}
    case False{} True{} True{} False{} False{} True{} False{} True{}:
      {==}
    case False{} True{} True{} False{} False{} True{} True{} False{}:
      {==}
    case False{} True{} True{} False{} False{} True{} True{} True{}:
      {==}
    case False{} True{} True{} False{} True{} False{} False{} False{}:
      {==}
    case False{} True{} True{} False{} True{} False{} False{} True{}:
      {==}
    case False{} True{} True{} False{} True{} False{} True{} False{}:
      {==}
    case False{} True{} True{} False{} True{} False{} True{} True{}:
      {==}
    case False{} True{} True{} False{} True{} True{} False{} False{}:
      {==}
    case False{} True{} True{} False{} True{} True{} False{} True{}:
      {==}
    case False{} True{} True{} False{} True{} True{} True{} False{}:
      {==}
    case False{} True{} True{} False{} True{} True{} True{} True{}:
      {==}
    case False{} True{} True{} True{} False{} False{} False{} False{}:
      {==}
    case False{} True{} True{} True{} False{} False{} False{} True{}:
      {==}
    case False{} True{} True{} True{} False{} False{} True{} False{}:
      {==}
    case False{} True{} True{} True{} False{} False{} True{} True{}:
      {==}
    case False{} True{} True{} True{} False{} True{} False{} False{}:
      {==}
    case False{} True{} True{} True{} False{} True{} False{} True{}:
      {==}
    case False{} True{} True{} True{} False{} True{} True{} False{}:
      {==}
    case False{} True{} True{} True{} False{} True{} True{} True{}:
      {==}
    case False{} True{} True{} True{} True{} False{} False{} False{}:
      {==}
    case False{} True{} True{} True{} True{} False{} False{} True{}:
      {==}
    case False{} True{} True{} True{} True{} False{} True{} False{}:
      {==}
    case False{} True{} True{} True{} True{} False{} True{} True{}:
      {==}
    case False{} True{} True{} True{} True{} True{} False{} False{}:
      {==}
    case False{} True{} True{} True{} True{} True{} False{} True{}:
      {==}
    case False{} True{} True{} True{} True{} True{} True{} False{}:
      {==}
    case False{} True{} True{} True{} True{} True{} True{} True{}:
      {==}
    case True{} False{} False{} False{} False{} False{} False{} False{}:
      {==}
    case True{} False{} False{} False{} False{} False{} False{} True{}:
      {==}
    case True{} False{} False{} False{} False{} False{} True{} False{}:
      {==}
    case True{} False{} False{} False{} False{} False{} True{} True{}:
      {==}
    case True{} False{} False{} False{} False{} True{} False{} False{}:
      {==}
    case True{} False{} False{} False{} False{} True{} False{} True{}:
      {==}
    case True{} False{} False{} False{} False{} True{} True{} False{}:
      {==}
    case True{} False{} False{} False{} False{} True{} True{} True{}:
      {==}
    case True{} False{} False{} False{} True{} False{} False{} False{}:
      {==}
    case True{} False{} False{} False{} True{} False{} False{} True{}:
      {==}
    case True{} False{} False{} False{} True{} False{} True{} False{}:
      {==}
    case True{} False{} False{} False{} True{} False{} True{} True{}:
      {==}
    case True{} False{} False{} False{} True{} True{} False{} False{}:
      {==}
    case True{} False{} False{} False{} True{} True{} False{} True{}:
      {==}
    case True{} False{} False{} False{} True{} True{} True{} False{}:
      {==}
    case True{} False{} False{} False{} True{} True{} True{} True{}:
      {==}
    case True{} False{} False{} True{} False{} False{} False{} False{}:
      {==}
    case True{} False{} False{} True{} False{} False{} False{} True{}:
      {==}
    case True{} False{} False{} True{} False{} False{} True{} False{}:
      {==}
    case True{} False{} False{} True{} False{} False{} True{} True{}:
      {==}
    case True{} False{} False{} True{} False{} True{} False{} False{}:
      {==}
    case True{} False{} False{} True{} False{} True{} False{} True{}:
      {==}
    case True{} False{} False{} True{} False{} True{} True{} False{}:
      {==}
    case True{} False{} False{} True{} False{} True{} True{} True{}:
      {==}
    case True{} False{} False{} True{} True{} False{} False{} False{}:
      {==}
    case True{} False{} False{} True{} True{} False{} False{} True{}:
      {==}
    case True{} False{} False{} True{} True{} False{} True{} False{}:
      {==}
    case True{} False{} False{} True{} True{} False{} True{} True{}:
      {==}
    case True{} False{} False{} True{} True{} True{} False{} False{}:
      {==}
    case True{} False{} False{} True{} True{} True{} False{} True{}:
      {==}
    case True{} False{} False{} True{} True{} True{} True{} False{}:
      {==}
    case True{} False{} False{} True{} True{} True{} True{} True{}:
      {==}
    case True{} False{} True{} False{} False{} False{} False{} False{}:
      {==}
    case True{} False{} True{} False{} False{} False{} False{} True{}:
      {==}
    case True{} False{} True{} False{} False{} False{} True{} False{}:
      {==}
    case True{} False{} True{} False{} False{} False{} True{} True{}:
      {==}
    case True{} False{} True{} False{} False{} True{} False{} False{}:
      {==}
    case True{} False{} True{} False{} False{} True{} False{} True{}:
      {==}
    case True{} False{} True{} False{} False{} True{} True{} False{}:
      {==}
    case True{} False{} True{} False{} False{} True{} True{} True{}:
      {==}
    case True{} False{} True{} False{} True{} False{} False{} False{}:
      {==}
    case True{} False{} True{} False{} True{} False{} False{} True{}:
      {==}
    case True{} False{} True{} False{} True{} False{} True{} False{}:
      {==}
    case True{} False{} True{} False{} True{} False{} True{} True{}:
      {==}
    case True{} False{} True{} False{} True{} True{} False{} False{}:
      {==}
    case True{} False{} True{} False{} True{} True{} False{} True{}:
      {==}
    case True{} False{} True{} False{} True{} True{} True{} False{}:
      {==}
    case True{} False{} True{} False{} True{} True{} True{} True{}:
      {==}
    case True{} False{} True{} True{} False{} False{} False{} False{}:
      {==}
    case True{} False{} True{} True{} False{} False{} False{} True{}:
      {==}
    case True{} False{} True{} True{} False{} False{} True{} False{}:
      {==}
    case True{} False{} True{} True{} False{} False{} True{} True{}:
      {==}
    case True{} False{} True{} True{} False{} True{} False{} False{}:
      {==}
    case True{} False{} True{} True{} False{} True{} False{} True{}:
      {==}
    case True{} False{} True{} True{} False{} True{} True{} False{}:
      {==}
    case True{} False{} True{} True{} False{} True{} True{} True{}:
      {==}
    case True{} False{} True{} True{} True{} False{} False{} False{}:
      {==}
    case True{} False{} True{} True{} True{} False{} False{} True{}:
      {==}
    case True{} False{} True{} True{} True{} False{} True{} False{}:
      {==}
    case True{} False{} True{} True{} True{} False{} True{} True{}:
      {==}
    case True{} False{} True{} True{} True{} True{} False{} False{}:
      {==}
    case True{} False{} True{} True{} True{} True{} False{} True{}:
      {==}
    case True{} False{} True{} True{} True{} True{} True{} False{}:
      {==}
    case True{} False{} True{} True{} True{} True{} True{} True{}:
      {==}
    case True{} True{} False{} False{} False{} False{} False{} False{}:
      {==}
    case True{} True{} False{} False{} False{} False{} False{} True{}:
      {==}
    case True{} True{} False{} False{} False{} False{} True{} False{}:
      {==}
    case True{} True{} False{} False{} False{} False{} True{} True{}:
      {==}
    case True{} True{} False{} False{} False{} True{} False{} False{}:
      {==}
    case True{} True{} False{} False{} False{} True{} False{} True{}:
      {==}
    case True{} True{} False{} False{} False{} True{} True{} False{}:
      {==}
    case True{} True{} False{} False{} False{} True{} True{} True{}:
      {==}
    case True{} True{} False{} False{} True{} False{} False{} False{}:
      {==}
    case True{} True{} False{} False{} True{} False{} False{} True{}:
      {==}
    case True{} True{} False{} False{} True{} False{} True{} False{}:
      {==}
    case True{} True{} False{} False{} True{} False{} True{} True{}:
      {==}
    case True{} True{} False{} False{} True{} True{} False{} False{}:
      {==}
    case True{} True{} False{} False{} True{} True{} False{} True{}:
      {==}
    case True{} True{} False{} False{} True{} True{} True{} False{}:
      {==}
    case True{} True{} False{} False{} True{} True{} True{} True{}:
      {==}
    case True{} True{} False{} True{} False{} False{} False{} False{}:
      {==}
    case True{} True{} False{} True{} False{} False{} False{} True{}:
      {==}
    case True{} True{} False{} True{} False{} False{} True{} False{}:
      {==}
    case True{} True{} False{} True{} False{} False{} True{} True{}:
      {==}
    case True{} True{} False{} True{} False{} True{} False{} False{}:
      {==}
    case True{} True{} False{} True{} False{} True{} False{} True{}:
      {==}
    case True{} True{} False{} True{} False{} True{} True{} False{}:
      {==}
    case True{} True{} False{} True{} False{} True{} True{} True{}:
      {==}
    case True{} True{} False{} True{} True{} False{} False{} False{}:
      {==}
    case True{} True{} False{} True{} True{} False{} False{} True{}:
      {==}
    case True{} True{} False{} True{} True{} False{} True{} False{}:
      {==}
    case True{} True{} False{} True{} True{} False{} True{} True{}:
      {==}
    case True{} True{} False{} True{} True{} True{} False{} False{}:
      {==}
    case True{} True{} False{} True{} True{} True{} False{} True{}:
      {==}
    case True{} True{} False{} True{} True{} True{} True{} False{}:
      {==}
    case True{} True{} False{} True{} True{} True{} True{} True{}:
      {==}
    case True{} True{} True{} False{} False{} False{} False{} False{}:
      {==}
    case True{} True{} True{} False{} False{} False{} False{} True{}:
      {==}
    case True{} True{} True{} False{} False{} False{} True{} False{}:
      {==}
    case True{} True{} True{} False{} False{} False{} True{} True{}:
      {==}
    case True{} True{} True{} False{} False{} True{} False{} False{}:
      {==}
    case True{} True{} True{} False{} False{} True{} False{} True{}:
      {==}
    case True{} True{} True{} False{} False{} True{} True{} False{}:
      {==}
    case True{} True{} True{} False{} False{} True{} True{} True{}:
      {==}
    case True{} True{} True{} False{} True{} False{} False{} False{}:
      {==}
    case True{} True{} True{} False{} True{} False{} False{} True{}:
      {==}
    case True{} True{} True{} False{} True{} False{} True{} False{}:
      {==}
    case True{} True{} True{} False{} True{} False{} True{} True{}:
      {==}
    case True{} True{} True{} False{} True{} True{} False{} False{}:
      {==}
    case True{} True{} True{} False{} True{} True{} False{} True{}:
      {==}
    case True{} True{} True{} False{} True{} True{} True{} False{}:
      {==}
    case True{} True{} True{} False{} True{} True{} True{} True{}:
      {==}
    case True{} True{} True{} True{} False{} False{} False{} False{}:
      {==}
    case True{} True{} True{} True{} False{} False{} False{} True{}:
      {==}
    case True{} True{} True{} True{} False{} False{} True{} False{}:
      {==}
    case True{} True{} True{} True{} False{} False{} True{} True{}:
      {==}
    case True{} True{} True{} True{} False{} True{} False{} False{}:
      {==}
    case True{} True{} True{} True{} False{} True{} False{} True{}:
      {==}
    case True{} True{} True{} True{} False{} True{} True{} False{}:
      {==}
    case True{} True{} True{} True{} False{} True{} True{} True{}:
      {==}
    case True{} True{} True{} True{} True{} False{} False{} False{}:
      {==}
    case True{} True{} True{} True{} True{} False{} False{} True{}:
      {==}
    case True{} True{} True{} True{} True{} False{} True{} False{}:
      {==}
    case True{} True{} True{} True{} True{} False{} True{} True{}:
      {==}
    case True{} True{} True{} True{} True{} True{} False{} False{}:
      {==}
    case True{} True{} True{} True{} True{} True{} False{} True{}:
      {==}
    case True{} True{} True{} True{} True{} True{} True{} False{}:
      {==}
    case True{} True{} True{} True{} True{} True{} True{} True{}:
      {==}

def zz(z0: Bool, z1: Bool, z2: Bool, z3: Bool, z4: Bool, z5: Bool, z6: Bool, z7: Bool,
  r: Word(24n)) -> U32:
  U32{WCon{z0, WCon{z1, WCon{z2, WCon{z3, WCon{z4, WCon{z5, WCon{z6, WCon{z7, r}}}}}}}}}

# a byte by the table is the byte a bit at a time: z is its low byte and
# the rest; the table gives the low byte's eight bits, and since the
# step is linear the rest's eight bits are the rest shifted
# (tb, a table right at every byte, as crc.tab is by tab)
def byte_z(+tb: Bytes(), h: @+z0: Bool -> @+z1: Bool -> @+z2: Bool -> @+z3: Bool -> @+z4: Bool ->
  @+z5: Bool -> @+z6: Bool -> @+z7: Bool ->
  {D.crc.cell(tb, lo(z0, z1, z2, z3, z4, z5, z6, z7)) == D.crc.entry(lo(z0, z1, z2, z3, z4, z5, z6, z7)) : U32},
  +z: U32) -> {D.crc.byte.z(tb, z) == D.crc.bits(8n, z) : U32}:
  match z:
    case U32{WCon{+z0, WCon{+z1, WCon{+z2, WCon{+z3, WCon{+z4, WCon{+z5, WCon{+z6, WCon{+z7, +r}}}}}}}}}:
      +w = zz(z0, z1, z2, z3, z4, z5, z6, z7, r)
      +l = lo(z0, z1, z2, z3, z4, z5, z6, z7)
      %Equal.sym(U32, U32.and(w, 255), l, low(z0, z1, z2, z3, z4, z5, z6, z7, r)) :
        {U32.xor(D.crc.cell(tb, _), U32.shrn(w, 8n)) == D.crc.bits(8n, w) : U32}
      %Equal.sym(U32, D.crc.cell(tb, l), D.crc.entry(l), h(z0, z1, z2, z3, z4, z5, z6, z7)) :
        {U32.xor(_, U32.shrn(w, 8n)) == D.crc.bits(8n, w) : U32}
      %split(z0, z1, z2, z3, z4, z5, z6, z7, r) :
        {U32.xor(D.crc.entry(l), U32.shrn(w, 8n)) == D.crc.bits(8n, _) : U32}
      %Equal.sym(U32, D.crc.bits(8n, U32.xor(l, hi(r))), U32.xor(D.crc.bits(8n, l), D.crc.bits(8n, hi(r))),
        bits_lin(8n, l, hi(r))) :
        {U32.xor(D.crc.entry(l), U32.shrn(w, 8n)) == _ : U32}
      %Equal.sym(U32, D.crc.bits(8n, hi(r)), U32.shrn(w, 8n), hi8(r, z0, z1, z2, z3, z4, z5, z6, z7)) :
        {U32.xor(D.crc.entry(l), U32.shrn(w, 8n)) == U32.xor(D.crc.bits(8n, l), _) : U32}
      {==}

# the table's CRC is the bit-at-a-time CRC, for every input and start
def run_spec(+x: Bytes(), +c: U32) -> {D.crc.run(x, D.crc.tab(), c) == Laws.crc_ref(x, c) : U32}:
  match x:
    case SNil{}:
      {==}
    case SCon{Chr{+b}, +t}:
      %Equal.sym(U32, D.crc.byte.z(D.crc.tab(), U32.xor(c, U32.and(b, 255))),
        D.crc.bits(8n, U32.xor(c, U32.and(b, 255))), byte_z(D.crc.tab(), tab, U32.xor(c, U32.and(b, 255)))) :
        {D.crc.run(t, D.crc.tab(), _) == Laws.crc_ref(t, D.crc.bits(8n, U32.xor(c, U32.and(b, 255)))) : U32}
      run_spec(t, D.crc.bits(8n, U32.xor(c, U32.and(b, 255))))

def Laws.crc32_ref(x, prev):
  %Equal.sym(U32, D.crc.run(x, D.crc.tab(), U32.not(prev)), Laws.crc_ref(x, U32.not(prev)),
    run_spec(x, U32.not(prev))) : {U32.not(_) == U32.not(Laws.crc_ref(x, U32.not(prev))) : U32}
  {==}

# The stored round trip
# =====================
#
# deflate(x, 0) writes x as stored blocks of 65535 bytes and one of the
# rest; the proof runs both machines over bits. wbits is what the bit
# writer holds (its whole bytes, then its pending bits), bitsof what a
# stream is, bit by bit as the reader takes it; bfeed is the inflate
# machine a bit at a time, which feeding a byte is (feed_bits). A block
# written at a byte (stored_bits) is its header, LEN and NLEN from its
# count's bits, and its bytes; read at a header (block) it lands at the
# next header with the bytes out, the count read back as the length,
# NLEN as its complement, every byte as itself (byte_back) and each
# under the cap. run strings the blocks together.

# Numbers
# -------

def add_zero(+a: Nat) -> {Nat.add(a, 0n) == a : Nat}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      Equal.cong(Nat, Nat, x => 1n+x, Nat.add(p, 0n), p, add_zero(p))

def add_succ(+a: Nat, +b: Nat) -> {Nat.add(a, 1n+b) == 1n+Nat.add(a, b) : Nat}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      Equal.cong(Nat, Nat, x => 1n+x, Nat.add(p, 1n+b), 1n+Nat.add(p, b), add_succ(p, b))

def lt_one(+x: Nat) -> {Nat.is_lt(x, 1n) == True{} : Bool} -> {x == 0n : Nat}:
  match x:
    case 0n:
      e => {==}
    case 1n+p:
      match p:
        case 0n:
          e => Bool.no({1n == 0n : Nat}, e)
        case 1n+q:
          e => Bool.no({2n+q == 0n : Nat}, e)

# the bits of a number from high first, after v
def V(bs: List<&2, Bool>, +v: Nat) -> Nat:
  match bs:
    case Nil{}:
      v
    case Con{b, t}:
      Nat.bit(b, V(t, v))

def V_val(+bs: List<&2, Bool>) -> {V(bs, 0n) == D.val(bs) : Nat}:
  match bs:
    case Nil{}:
      {==}
    case Con{+b, +t}:
      Equal.cong(Nat, Nat, x => Nat.bit(b, x), V(t, 0n), D.val(t), V_val(t))

def hval_rev.go(+bs: List<&2, Bool>, +a: List<&2, Bool>, +v: Nat) ->
  {D.hval(D.revapp(bs, a), v) == D.hval(a, V(bs, v)) : Nat}:
  match bs:
    case Nil{}:
      {==}
    case Con{+b, +t}:
      hval_rev.go(t, Con{b, a}, v)

# what the reader collects, newest first, read back
def hval_rev(+bs: List<&2, Bool>) -> {D.hval(D.revapp(bs, Nil{}), 0n) == D.val(bs) : Nat}:
  Equal.trans(Nat, D.hval(D.revapp(bs, Nil{}), 0n), V(bs, 0n), D.val(bs), hval_rev.go(bs, Nil{}, 0n),
    V_val(bs))

# a byte made of eight bits gives them back, low first
def unbyte_of(+b0: Bool, +b1: Bool, +b2: Bool, +b3: Bool, +b4: Bool, +b5: Bool, +b6: Bool, +b7: Bool) ->
  {D.unbyte(D.byte_of([b7, b6, b5, b4, b3, b2, b1, b0])) == [b0, b1, b2, b3, b4, b5, b6, b7] : List<&2, Bool>}:
  match b0 b1 b2 b3 b4 b5 b6 b7:
    case False{} False{} False{} False{} False{} False{} False{} False{}:
      {==}
    case False{} False{} False{} False{} False{} False{} False{} True{}:
      {==}
    case False{} False{} False{} False{} False{} False{} True{} False{}:
      {==}
    case False{} False{} False{} False{} False{} False{} True{} True{}:
      {==}
    case False{} False{} False{} False{} False{} True{} False{} False{}:
      {==}
    case False{} False{} False{} False{} False{} True{} False{} True{}:
      {==}
    case False{} False{} False{} False{} False{} True{} True{} False{}:
      {==}
    case False{} False{} False{} False{} False{} True{} True{} True{}:
      {==}
    case False{} False{} False{} False{} True{} False{} False{} False{}:
      {==}
    case False{} False{} False{} False{} True{} False{} False{} True{}:
      {==}
    case False{} False{} False{} False{} True{} False{} True{} False{}:
      {==}
    case False{} False{} False{} False{} True{} False{} True{} True{}:
      {==}
    case False{} False{} False{} False{} True{} True{} False{} False{}:
      {==}
    case False{} False{} False{} False{} True{} True{} False{} True{}:
      {==}
    case False{} False{} False{} False{} True{} True{} True{} False{}:
      {==}
    case False{} False{} False{} False{} True{} True{} True{} True{}:
      {==}
    case False{} False{} False{} True{} False{} False{} False{} False{}:
      {==}
    case False{} False{} False{} True{} False{} False{} False{} True{}:
      {==}
    case False{} False{} False{} True{} False{} False{} True{} False{}:
      {==}
    case False{} False{} False{} True{} False{} False{} True{} True{}:
      {==}
    case False{} False{} False{} True{} False{} True{} False{} False{}:
      {==}
    case False{} False{} False{} True{} False{} True{} False{} True{}:
      {==}
    case False{} False{} False{} True{} False{} True{} True{} False{}:
      {==}
    case False{} False{} False{} True{} False{} True{} True{} True{}:
      {==}
    case False{} False{} False{} True{} True{} False{} False{} False{}:
      {==}
    case False{} False{} False{} True{} True{} False{} False{} True{}:
      {==}
    case False{} False{} False{} True{} True{} False{} True{} False{}:
      {==}
    case False{} False{} False{} True{} True{} False{} True{} True{}:
      {==}
    case False{} False{} False{} True{} True{} True{} False{} False{}:
      {==}
    case False{} False{} False{} True{} True{} True{} False{} True{}:
      {==}
    case False{} False{} False{} True{} True{} True{} True{} False{}:
      {==}
    case False{} False{} False{} True{} True{} True{} True{} True{}:
      {==}
    case False{} False{} True{} False{} False{} False{} False{} False{}:
      {==}
    case False{} False{} True{} False{} False{} False{} False{} True{}:
      {==}
    case False{} False{} True{} False{} False{} False{} True{} False{}:
      {==}
    case False{} False{} True{} False{} False{} False{} True{} True{}:
      {==}
    case False{} False{} True{} False{} False{} True{} False{} False{}:
      {==}
    case False{} False{} True{} False{} False{} True{} False{} True{}:
      {==}
    case False{} False{} True{} False{} False{} True{} True{} False{}:
      {==}
    case False{} False{} True{} False{} False{} True{} True{} True{}:
      {==}
    case False{} False{} True{} False{} True{} False{} False{} False{}:
      {==}
    case False{} False{} True{} False{} True{} False{} False{} True{}:
      {==}
    case False{} False{} True{} False{} True{} False{} True{} False{}:
      {==}
    case False{} False{} True{} False{} True{} False{} True{} True{}:
      {==}
    case False{} False{} True{} False{} True{} True{} False{} False{}:
      {==}
    case False{} False{} True{} False{} True{} True{} False{} True{}:
      {==}
    case False{} False{} True{} False{} True{} True{} True{} False{}:
      {==}
    case False{} False{} True{} False{} True{} True{} True{} True{}:
      {==}
    case False{} False{} True{} True{} False{} False{} False{} False{}:
      {==}
    case False{} False{} True{} True{} False{} False{} False{} True{}:
      {==}
    case False{} False{} True{} True{} False{} False{} True{} False{}:
      {==}
    case False{} False{} True{} True{} False{} False{} True{} True{}:
      {==}
    case False{} False{} True{} True{} False{} True{} False{} False{}:
      {==}
    case False{} False{} True{} True{} False{} True{} False{} True{}:
      {==}
    case False{} False{} True{} True{} False{} True{} True{} False{}:
      {==}
    case False{} False{} True{} True{} False{} True{} True{} True{}:
      {==}
    case False{} False{} True{} True{} True{} False{} False{} False{}:
      {==}
    case False{} False{} True{} True{} True{} False{} False{} True{}:
      {==}
    case False{} False{} True{} True{} True{} False{} True{} False{}:
      {==}
    case False{} False{} True{} True{} True{} False{} True{} True{}:
      {==}
    case False{} False{} True{} True{} True{} True{} False{} False{}:
      {==}
    case False{} False{} True{} True{} True{} True{} False{} True{}:
      {==}
    case False{} False{} True{} True{} True{} True{} True{} False{}:
      {==}
    case False{} False{} True{} True{} True{} True{} True{} True{}:
      {==}
    case False{} True{} False{} False{} False{} False{} False{} False{}:
      {==}
    case False{} True{} False{} False{} False{} False{} False{} True{}:
      {==}
    case False{} True{} False{} False{} False{} False{} True{} False{}:
      {==}
    case False{} True{} False{} False{} False{} False{} True{} True{}:
      {==}
    case False{} True{} False{} False{} False{} True{} False{} False{}:
      {==}
    case False{} True{} False{} False{} False{} True{} False{} True{}:
      {==}
    case False{} True{} False{} False{} False{} True{} True{} False{}:
      {==}
    case False{} True{} False{} False{} False{} True{} True{} True{}:
      {==}
    case False{} True{} False{} False{} True{} False{} False{} False{}:
      {==}
    case False{} True{} False{} False{} True{} False{} False{} True{}:
      {==}
    case False{} True{} False{} False{} True{} False{} True{} False{}:
      {==}
    case False{} True{} False{} False{} True{} False{} True{} True{}:
      {==}
    case False{} True{} False{} False{} True{} True{} False{} False{}:
      {==}
    case False{} True{} False{} False{} True{} True{} False{} True{}:
      {==}
    case False{} True{} False{} False{} True{} True{} True{} False{}:
      {==}
    case False{} True{} False{} False{} True{} True{} True{} True{}:
      {==}
    case False{} True{} False{} True{} False{} False{} False{} False{}:
      {==}
    case False{} True{} False{} True{} False{} False{} False{} True{}:
      {==}
    case False{} True{} False{} True{} False{} False{} True{} False{}:
      {==}
    case False{} True{} False{} True{} False{} False{} True{} True{}:
      {==}
    case False{} True{} False{} True{} False{} True{} False{} False{}:
      {==}
    case False{} True{} False{} True{} False{} True{} False{} True{}:
      {==}
    case False{} True{} False{} True{} False{} True{} True{} False{}:
      {==}
    case False{} True{} False{} True{} False{} True{} True{} True{}:
      {==}
    case False{} True{} False{} True{} True{} False{} False{} False{}:
      {==}
    case False{} True{} False{} True{} True{} False{} False{} True{}:
      {==}
    case False{} True{} False{} True{} True{} False{} True{} False{}:
      {==}
    case False{} True{} False{} True{} True{} False{} True{} True{}:
      {==}
    case False{} True{} False{} True{} True{} True{} False{} False{}:
      {==}
    case False{} True{} False{} True{} True{} True{} False{} True{}:
      {==}
    case False{} True{} False{} True{} True{} True{} True{} False{}:
      {==}
    case False{} True{} False{} True{} True{} True{} True{} True{}:
      {==}
    case False{} True{} True{} False{} False{} False{} False{} False{}:
      {==}
    case False{} True{} True{} False{} False{} False{} False{} True{}:
      {==}
    case False{} True{} True{} False{} False{} False{} True{} False{}:
      {==}
    case False{} True{} True{} False{} False{} False{} True{} True{}:
      {==}
    case False{} True{} True{} False{} False{} True{} False{} False{}:
      {==}
    case False{} True{} True{} False{} False{} True{} False{} True{}:
      {==}
    case False{} True{} True{} False{} False{} True{} True{} False{}:
      {==}
    case False{} True{} True{} False{} False{} True{} True{} True{}:
      {==}
    case False{} True{} True{} False{} True{} False{} False{} False{}:
      {==}
    case False{} True{} True{} False{} True{} False{} False{} True{}:
      {==}
    case False{} True{} True{} False{} True{} False{} True{} False{}:
      {==}
    case False{} True{} True{} False{} True{} False{} True{} True{}:
      {==}
    case False{} True{} True{} False{} True{} True{} False{} False{}:
      {==}
    case False{} True{} True{} False{} True{} True{} False{} True{}:
      {==}
    case False{} True{} True{} False{} True{} True{} True{} False{}:
      {==}
    case False{} True{} True{} False{} True{} True{} True{} True{}:
      {==}
    case False{} True{} True{} True{} False{} False{} False{} False{}:
      {==}
    case False{} True{} True{} True{} False{} False{} False{} True{}:
      {==}
    case False{} True{} True{} True{} False{} False{} True{} False{}:
      {==}
    case False{} True{} True{} True{} False{} False{} True{} True{}:
      {==}
    case False{} True{} True{} True{} False{} True{} False{} False{}:
      {==}
    case False{} True{} True{} True{} False{} True{} False{} True{}:
      {==}
    case False{} True{} True{} True{} False{} True{} True{} False{}:
      {==}
    case False{} True{} True{} True{} False{} True{} True{} True{}:
      {==}
    case False{} True{} True{} True{} True{} False{} False{} False{}:
      {==}
    case False{} True{} True{} True{} True{} False{} False{} True{}:
      {==}
    case False{} True{} True{} True{} True{} False{} True{} False{}:
      {==}
    case False{} True{} True{} True{} True{} False{} True{} True{}:
      {==}
    case False{} True{} True{} True{} True{} True{} False{} False{}:
      {==}
    case False{} True{} True{} True{} True{} True{} False{} True{}:
      {==}
    case False{} True{} True{} True{} True{} True{} True{} False{}:
      {==}
    case False{} True{} True{} True{} True{} True{} True{} True{}:
      {==}
    case True{} False{} False{} False{} False{} False{} False{} False{}:
      {==}
    case True{} False{} False{} False{} False{} False{} False{} True{}:
      {==}
    case True{} False{} False{} False{} False{} False{} True{} False{}:
      {==}
    case True{} False{} False{} False{} False{} False{} True{} True{}:
      {==}
    case True{} False{} False{} False{} False{} True{} False{} False{}:
      {==}
    case True{} False{} False{} False{} False{} True{} False{} True{}:
      {==}
    case True{} False{} False{} False{} False{} True{} True{} False{}:
      {==}
    case True{} False{} False{} False{} False{} True{} True{} True{}:
      {==}
    case True{} False{} False{} False{} True{} False{} False{} False{}:
      {==}
    case True{} False{} False{} False{} True{} False{} False{} True{}:
      {==}
    case True{} False{} False{} False{} True{} False{} True{} False{}:
      {==}
    case True{} False{} False{} False{} True{} False{} True{} True{}:
      {==}
    case True{} False{} False{} False{} True{} True{} False{} False{}:
      {==}
    case True{} False{} False{} False{} True{} True{} False{} True{}:
      {==}
    case True{} False{} False{} False{} True{} True{} True{} False{}:
      {==}
    case True{} False{} False{} False{} True{} True{} True{} True{}:
      {==}
    case True{} False{} False{} True{} False{} False{} False{} False{}:
      {==}
    case True{} False{} False{} True{} False{} False{} False{} True{}:
      {==}
    case True{} False{} False{} True{} False{} False{} True{} False{}:
      {==}
    case True{} False{} False{} True{} False{} False{} True{} True{}:
      {==}
    case True{} False{} False{} True{} False{} True{} False{} False{}:
      {==}
    case True{} False{} False{} True{} False{} True{} False{} True{}:
      {==}
    case True{} False{} False{} True{} False{} True{} True{} False{}:
      {==}
    case True{} False{} False{} True{} False{} True{} True{} True{}:
      {==}
    case True{} False{} False{} True{} True{} False{} False{} False{}:
      {==}
    case True{} False{} False{} True{} True{} False{} False{} True{}:
      {==}
    case True{} False{} False{} True{} True{} False{} True{} False{}:
      {==}
    case True{} False{} False{} True{} True{} False{} True{} True{}:
      {==}
    case True{} False{} False{} True{} True{} True{} False{} False{}:
      {==}
    case True{} False{} False{} True{} True{} True{} False{} True{}:
      {==}
    case True{} False{} False{} True{} True{} True{} True{} False{}:
      {==}
    case True{} False{} False{} True{} True{} True{} True{} True{}:
      {==}
    case True{} False{} True{} False{} False{} False{} False{} False{}:
      {==}
    case True{} False{} True{} False{} False{} False{} False{} True{}:
      {==}
    case True{} False{} True{} False{} False{} False{} True{} False{}:
      {==}
    case True{} False{} True{} False{} False{} False{} True{} True{}:
      {==}
    case True{} False{} True{} False{} False{} True{} False{} False{}:
      {==}
    case True{} False{} True{} False{} False{} True{} False{} True{}:
      {==}
    case True{} False{} True{} False{} False{} True{} True{} False{}:
      {==}
    case True{} False{} True{} False{} False{} True{} True{} True{}:
      {==}
    case True{} False{} True{} False{} True{} False{} False{} False{}:
      {==}
    case True{} False{} True{} False{} True{} False{} False{} True{}:
      {==}
    case True{} False{} True{} False{} True{} False{} True{} False{}:
      {==}
    case True{} False{} True{} False{} True{} False{} True{} True{}:
      {==}
    case True{} False{} True{} False{} True{} True{} False{} False{}:
      {==}
    case True{} False{} True{} False{} True{} True{} False{} True{}:
      {==}
    case True{} False{} True{} False{} True{} True{} True{} False{}:
      {==}
    case True{} False{} True{} False{} True{} True{} True{} True{}:
      {==}
    case True{} False{} True{} True{} False{} False{} False{} False{}:
      {==}
    case True{} False{} True{} True{} False{} False{} False{} True{}:
      {==}
    case True{} False{} True{} True{} False{} False{} True{} False{}:
      {==}
    case True{} False{} True{} True{} False{} False{} True{} True{}:
      {==}
    case True{} False{} True{} True{} False{} True{} False{} False{}:
      {==}
    case True{} False{} True{} True{} False{} True{} False{} True{}:
      {==}
    case True{} False{} True{} True{} False{} True{} True{} False{}:
      {==}
    case True{} False{} True{} True{} False{} True{} True{} True{}:
      {==}
    case True{} False{} True{} True{} True{} False{} False{} False{}:
      {==}
    case True{} False{} True{} True{} True{} False{} False{} True{}:
      {==}
    case True{} False{} True{} True{} True{} False{} True{} False{}:
      {==}
    case True{} False{} True{} True{} True{} False{} True{} True{}:
      {==}
    case True{} False{} True{} True{} True{} True{} False{} False{}:
      {==}
    case True{} False{} True{} True{} True{} True{} False{} True{}:
      {==}
    case True{} False{} True{} True{} True{} True{} True{} False{}:
      {==}
    case True{} False{} True{} True{} True{} True{} True{} True{}:
      {==}
    case True{} True{} False{} False{} False{} False{} False{} False{}:
      {==}
    case True{} True{} False{} False{} False{} False{} False{} True{}:
      {==}
    case True{} True{} False{} False{} False{} False{} True{} False{}:
      {==}
    case True{} True{} False{} False{} False{} False{} True{} True{}:
      {==}
    case True{} True{} False{} False{} False{} True{} False{} False{}:
      {==}
    case True{} True{} False{} False{} False{} True{} False{} True{}:
      {==}
    case True{} True{} False{} False{} False{} True{} True{} False{}:
      {==}
    case True{} True{} False{} False{} False{} True{} True{} True{}:
      {==}
    case True{} True{} False{} False{} True{} False{} False{} False{}:
      {==}
    case True{} True{} False{} False{} True{} False{} False{} True{}:
      {==}
    case True{} True{} False{} False{} True{} False{} True{} False{}:
      {==}
    case True{} True{} False{} False{} True{} False{} True{} True{}:
      {==}
    case True{} True{} False{} False{} True{} True{} False{} False{}:
      {==}
    case True{} True{} False{} False{} True{} True{} False{} True{}:
      {==}
    case True{} True{} False{} False{} True{} True{} True{} False{}:
      {==}
    case True{} True{} False{} False{} True{} True{} True{} True{}:
      {==}
    case True{} True{} False{} True{} False{} False{} False{} False{}:
      {==}
    case True{} True{} False{} True{} False{} False{} False{} True{}:
      {==}
    case True{} True{} False{} True{} False{} False{} True{} False{}:
      {==}
    case True{} True{} False{} True{} False{} False{} True{} True{}:
      {==}
    case True{} True{} False{} True{} False{} True{} False{} False{}:
      {==}
    case True{} True{} False{} True{} False{} True{} False{} True{}:
      {==}
    case True{} True{} False{} True{} False{} True{} True{} False{}:
      {==}
    case True{} True{} False{} True{} False{} True{} True{} True{}:
      {==}
    case True{} True{} False{} True{} True{} False{} False{} False{}:
      {==}
    case True{} True{} False{} True{} True{} False{} False{} True{}:
      {==}
    case True{} True{} False{} True{} True{} False{} True{} False{}:
      {==}
    case True{} True{} False{} True{} True{} False{} True{} True{}:
      {==}
    case True{} True{} False{} True{} True{} True{} False{} False{}:
      {==}
    case True{} True{} False{} True{} True{} True{} False{} True{}:
      {==}
    case True{} True{} False{} True{} True{} True{} True{} False{}:
      {==}
    case True{} True{} False{} True{} True{} True{} True{} True{}:
      {==}
    case True{} True{} True{} False{} False{} False{} False{} False{}:
      {==}
    case True{} True{} True{} False{} False{} False{} False{} True{}:
      {==}
    case True{} True{} True{} False{} False{} False{} True{} False{}:
      {==}
    case True{} True{} True{} False{} False{} False{} True{} True{}:
      {==}
    case True{} True{} True{} False{} False{} True{} False{} False{}:
      {==}
    case True{} True{} True{} False{} False{} True{} False{} True{}:
      {==}
    case True{} True{} True{} False{} False{} True{} True{} False{}:
      {==}
    case True{} True{} True{} False{} False{} True{} True{} True{}:
      {==}
    case True{} True{} True{} False{} True{} False{} False{} False{}:
      {==}
    case True{} True{} True{} False{} True{} False{} False{} True{}:
      {==}
    case True{} True{} True{} False{} True{} False{} True{} False{}:
      {==}
    case True{} True{} True{} False{} True{} False{} True{} True{}:
      {==}
    case True{} True{} True{} False{} True{} True{} False{} False{}:
      {==}
    case True{} True{} True{} False{} True{} True{} False{} True{}:
      {==}
    case True{} True{} True{} False{} True{} True{} True{} False{}:
      {==}
    case True{} True{} True{} False{} True{} True{} True{} True{}:
      {==}
    case True{} True{} True{} True{} False{} False{} False{} False{}:
      {==}
    case True{} True{} True{} True{} False{} False{} False{} True{}:
      {==}
    case True{} True{} True{} True{} False{} False{} True{} False{}:
      {==}
    case True{} True{} True{} True{} False{} False{} True{} True{}:
      {==}
    case True{} True{} True{} True{} False{} True{} False{} False{}:
      {==}
    case True{} True{} True{} True{} False{} True{} False{} True{}:
      {==}
    case True{} True{} True{} True{} False{} True{} True{} False{}:
      {==}
    case True{} True{} True{} True{} False{} True{} True{} True{}:
      {==}
    case True{} True{} True{} True{} True{} False{} False{} False{}:
      {==}
    case True{} True{} True{} True{} True{} False{} False{} True{}:
      {==}
    case True{} True{} True{} True{} True{} False{} True{} False{}:
      {==}
    case True{} True{} True{} True{} True{} False{} True{} True{}:
      {==}
    case True{} True{} True{} True{} True{} True{} False{} False{}:
      {==}
    case True{} True{} True{} True{} True{} True{} False{} True{}:
      {==}
    case True{} True{} True{} True{} True{} True{} True{} False{}:
      {==}
    case True{} True{} True{} True{} True{} True{} True{} True{}:
      {==}

# Bits
# ----

def app(a: List<&2, Bool>, b: List<&2, Bool>) -> List<&2, Bool>:
  List.append(&2, Bool, a, b)

def app_nil(+a: List<&2, Bool>) -> {app(a, Nil{}) == a : List<&2, Bool>}:
  match a:
    case Nil{}:
      {==}
    case Con{+h, +t}:
      Equal.cong(List<&2, Bool>, List<&2, Bool>, x => Con{h, x}, app(t, Nil{}), t, app_nil(t))

def app_assoc(+a: List<&2, Bool>, +b: List<&2, Bool>, +c: List<&2, Bool>) ->
  {app(app(a, b), c) == app(a, app(b, c)) : List<&2, Bool>}:
  match a:
    case Nil{}:
      {==}
    case Con{+h, +t}:
      Equal.cong(List<&2, Bool>, List<&2, Bool>, x => Con{h, x}, app(app(t, b), c), app(t, app(b, c)),
        app_assoc(t, b, c))

# the bits of a stream, each byte's low first
def bitsof(s: Bytes()) -> List<&2, Bool>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{Chr{c}, t}:
      app(D.unbyte(c), bitsof(t))

def bitsof_app(+a: Bytes(), +b: Bytes()) ->
  {bitsof(String.append(a, b)) == app(bitsof(a), bitsof(b)) : List<&2, Bool>}:
  match a:
    case SNil{}:
      {==}
    case SCon{Chr{+c}, +t}:
      %Equal.sym(List<&2, Bool>, bitsof(String.append(t, b)), app(bitsof(t), bitsof(b)), bitsof_app(t, b)) :
        {app(D.unbyte(c), _) == app(app(D.unbyte(c), bitsof(t)), bitsof(b)) : List<&2, Bool>}
      Equal.sym(List<&2, Bool>, app(app(D.unbyte(c), bitsof(t)), bitsof(b)),
        app(D.unbyte(c), app(bitsof(t), bitsof(b))), app_assoc(D.unbyte(c), bitsof(t), bitsof(b)))

def bitsof_push(+a: Bytes(), +c: U32) ->
  {bitsof(Bytes.push(a, c)) == app(bitsof(a), D.unbyte(c)) : List<&2, Bool>}:
  %Equal.sym(List<&2, Bool>, bitsof(String.append(a, SCon{Chr{c}, SNil{}})),
    app(bitsof(a), bitsof(SCon{Chr{c}, SNil{}})), bitsof_app(a, SCon{Chr{c}, SNil{}})) :
    {_ == app(bitsof(a), D.unbyte(c)) : List<&2, Bool>}
  %Equal.sym(List<&2, Bool>, app(D.unbyte(c), Nil{}), D.unbyte(c), app_nil(D.unbyte(c))) :
    {app(bitsof(a), _) == app(bitsof(a), D.unbyte(c)) : List<&2, Bool>}
  {==}

# the machine over bits
def bfeed(bs: List<&2, Bool>, st: D.St) -> D.St:
  match bs:
    case Nil{}:
      st
    case Con{b, t}:
      bfeed(t, D.bstep(st, b))

def bfeed_app(+a: List<&2, Bool>, +b: List<&2, Bool>, +st: D.St) ->
  {bfeed(app(a, b), st) == bfeed(b, bfeed(a, st)) : D.St}:
  match a:
    case Nil{}:
      {==}
    case Con{+h, +t}:
      bfeed_app(t, b, D.bstep(st, h))

# a stream's bytes, fed, are its bits fed
def feed_bits(+s: Bytes(), +st: D.St) -> {D.feed_list(Bytes.to_list(s), st) == bfeed(bitsof(s), st) : D.St}:
  match s:
    case SNil{}:
      {==}
    case SCon{Chr{+c}, +t}:
      %Equal.sym(D.St, bfeed(app(D.unbyte(c), bitsof(t)), st), bfeed(bitsof(t), bfeed(D.unbyte(c), st)),
        bfeed_app(D.unbyte(c), bitsof(t), st)) :
        {D.feed_list(Bytes.to_list(t), D.step(st, c)) == _ : D.St}
      feed_bits(t, D.step(st, c))

# The writer's bits
# -----------------

def wbits(w: D.W) -> List<&2, Bool>:
  match w:
    case D.W{out, pend}:
      app(bitsof(out), D.revapp(pend, Nil{}))

def revapp_app(+p: List<&2, Bool>, +a: List<&2, Bool>, +c: List<&2, Bool>) ->
  {D.revapp(p, app(a, c)) == app(D.revapp(p, a), c) : List<&2, Bool>}:
  match p:
    case Nil{}:
      {==}
    case Con{+h, +t}:
      revapp_app(t, Con{h, a}, c)

# a bit onto the pending ones
def cons_bits(+out: Bytes(), +pend: List<&2, Bool>, +b: Bool) ->
  {wbits(D.W{out, Con{b, pend}}) == app(wbits(D.W{out, pend}), [b]) : List<&2, Bool>}:
  %Equal.sym(List<&2, Bool>, D.revapp(pend, app(Nil{}, [b])), app(D.revapp(pend, Nil{}), [b]),
    revapp_app(pend, Nil{}, [b])) :
    {app(bitsof(out), _) == app(app(bitsof(out), D.revapp(pend, Nil{})), [b]) : List<&2, Bool>}
  Equal.sym(List<&2, Bool>, app(app(bitsof(out), D.revapp(pend, Nil{})), [b]),
    app(bitsof(out), app(D.revapp(pend, Nil{}), [b])), app_assoc(bitsof(out), D.revapp(pend, Nil{}), [b]))

# a bit put is a bit after the writer's
def put_bits(+w: D.W, +b: Bool) -> {wbits(D.put(w, b)) == app(wbits(w), [b]) : List<&2, Bool>}:
  match w:
    case D.W{+out, +pend}:
      match pend:
        case Nil{}:
          cons_bits(out, Nil{}, b)
        case Con{+p6, +t0}:
          match t0:
            case Nil{}:
              cons_bits(out, Con{p6, Nil{}}, b)
            case Con{+p5, +t1}:
              match t1:
                case Nil{}:
                  cons_bits(out, Con{p6, Con{p5, Nil{}}}, b)
                case Con{+p4, +t2}:
                  match t2:
                    case Nil{}:
                      cons_bits(out, Con{p6, Con{p5, Con{p4, Nil{}}}}, b)
                    case Con{+p3, +t3}:
                      match t3:
                        case Nil{}:
                          cons_bits(out, Con{p6, Con{p5, Con{p4, Con{p3, Nil{}}}}}, b)
                        case Con{+p2, +t4}:
                          match t4:
                            case Nil{}:
                              cons_bits(out, Con{p6, Con{p5, Con{p4, Con{p3, Con{p2, Nil{}}}}}}, b)
                            case Con{+p1, +t5}:
                              match t5:
                                case Nil{}:
                                  cons_bits(out, Con{p6, Con{p5, Con{p4, Con{p3, Con{p2, Con{p1, Nil{}}}}}}}, b)
                                case Con{+p0, +t6}:
                                  match t6:
                                    case Nil{}:
                                      Equal.trans(List<&2, Bool>, app(bitsof(Bytes.push(out, D.byte_of([b, p6, p5, p4, p3, p2, p1, p0]))), Nil{}), bitsof(Bytes.push(out, D.byte_of([b, p6, p5, p4, p3, p2, p1, p0]))), app(app(bitsof(out), [p0, p1, p2, p3, p4, p5, p6]), [b]),
                                        app_nil(bitsof(Bytes.push(out, D.byte_of([b, p6, p5, p4, p3, p2, p1, p0])))),
                                        Equal.trans(List<&2, Bool>, bitsof(Bytes.push(out, D.byte_of([b, p6, p5, p4, p3, p2, p1, p0]))), app(bitsof(out), D.unbyte(D.byte_of([b, p6, p5, p4, p3, p2, p1, p0]))), app(app(bitsof(out), [p0, p1, p2, p3, p4, p5, p6]), [b]),
                                          bitsof_push(out, D.byte_of([b, p6, p5, p4, p3, p2, p1, p0])),
                                          Equal.trans(List<&2, Bool>, app(bitsof(out), D.unbyte(D.byte_of([b, p6, p5, p4, p3, p2, p1, p0]))), app(bitsof(out), [p0, p1, p2, p3, p4, p5, p6, b]), app(app(bitsof(out), [p0, p1, p2, p3, p4, p5, p6]), [b]),
                                            Equal.cong(List<&2, Bool>, List<&2, Bool>, y => app(bitsof(out), y), D.unbyte(D.byte_of([b, p6, p5, p4, p3, p2, p1, p0])), [p0, p1, p2, p3, p4, p5, p6, b],
                                              unbyte_of(p0, p1, p2, p3, p4, p5, p6, b)),
                                            Equal.sym(List<&2, Bool>, app(app(bitsof(out), [p0, p1, p2, p3, p4, p5, p6]), [b]), app(bitsof(out), app([p0, p1, p2, p3, p4, p5, p6], [b])), app_assoc(bitsof(out), [p0, p1, p2, p3, p4, p5, p6], [b])))))
                                    case Con{+q, +r}:
                                      cons_bits(out, Con{p6, Con{p5, Con{p4, Con{p3, Con{p2, Con{p1, Con{p0, Con{q, r}}}}}}}}, b)

# the same, before any bits
def put_k(+w: D.W, +b: Bool, +s: List<&2, Bool>) ->
  {app(wbits(D.put(w, b)), s) == app(wbits(w), Con{b, s}) : List<&2, Bool>}:
  Equal.trans(List<&2, Bool>, app(wbits(D.put(w, b)), s), app(app(wbits(w), [b]), s),
    app(wbits(w), Con{b, s}),
    Equal.cong(List<&2, Bool>, List<&2, Bool>, y => app(y, s), wbits(D.put(w, b)), app(wbits(w), [b]),
      put_bits(w, b)),
    app_assoc(wbits(w), [b], s))

# a field put is its bits, low first, after the writer's
def putx_k(+n: Nat, +w: D.W, +v: Nat, +s: List<&2, Bool>) ->
  {app(wbits(D.putx(n, w, v)), s) == app(wbits(w), app(D.xbits(n, v), s)) : List<&2, Bool>}:
  match n:
    case 0n:
      {==}
    case 1n+p:
      +b0 = Nat.is_eq(Nat.mod(v, 2n), 1n)
      +v2 = Nat.div(v, 2n)
      Equal.trans(List<&2, Bool>, app(wbits(D.putx(p, D.put(w, b0), v2)), s),
        app(wbits(D.put(w, b0)), app(D.xbits(p, v2), s)), app(wbits(w), Con{b0, app(D.xbits(p, v2), s)}),
        putx_k(p, D.put(w, b0), v2, s), put_k(w, b0, app(D.xbits(p, v2), s)))

# bytes put at a byte are their bits after the writer's
def raw_bits(+out: Bytes(), +b: Bytes()) ->
  {wbits(D.put_raw(D.W{out, Nil{}}, b)) == app(wbits(D.W{out, Nil{}}), bitsof(b)) : List<&2, Bool>}:
  Equal.trans(List<&2, Bool>, app(bitsof(String.append(out, b)), Nil{}), bitsof(String.append(out, b)),
    app(app(bitsof(out), Nil{}), bitsof(b)), app_nil(bitsof(String.append(out, b))),
    Equal.trans(List<&2, Bool>, bitsof(String.append(out, b)), app(bitsof(out), bitsof(b)),
      app(app(bitsof(out), Nil{}), bitsof(b)), bitsof_app(out, b),
      Equal.cong(List<&2, Bool>, List<&2, Bool>, y => app(y, bitsof(b)), bitsof(out), app(bitsof(out), Nil{}),
        Equal.sym(List<&2, Bool>, app(bitsof(out), Nil{}), bitsof(out), app_nil(bitsof(out))))))

# the first n bits of bs as the writer takes them
def takeN(n: Nat, +bs: List<&2, Bool>) -> List<&2, Bool>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Con{D.hd(bs), takeN(p, D.tl(bs))}

# n bits put from a list are its first n after the writer's
def putn_k(+n: Nat, +bs: List<&2, Bool>, +w: D.W, +s: List<&2, Bool>) ->
  {app(wbits(D.putn(n, bs, w)), s) == app(wbits(w), app(takeN(n, bs), s)) : List<&2, Bool>}:
  match n:
    case 0n:
      {==}
    case 1n+p:
      Equal.trans(List<&2, Bool>, app(wbits(D.putn(p, D.tl(bs), D.put(w, D.hd(bs)))), s),
        app(wbits(D.put(w, D.hd(bs))), app(takeN(p, D.tl(bs)), s)),
        app(wbits(w), Con{D.hd(bs), app(takeN(p, D.tl(bs)), s)}),
        putn_k(p, D.tl(bs), D.put(w, D.hd(bs)), s), put_k(w, D.hd(bs), app(takeN(p, D.tl(bs)), s)))

def pred(n: Nat) -> Nat:
  match n:
    case 0n:
      0n
    case 1n+p:
      p

# no length is both 0 and more
def len_no(-g: Type, +n: Nat, e: {0n == 1n+n : Nat}) -> g:
  Bool.no(g, Equal.sym(Bool, True{}, False{}, Equal.cong(Nat, Bool, x => Nat.is_eq(x, 0n), 0n, 1n+n, e)))

# a list of n bits, its first n: itself
def take_all(+bs: List<&2, Bool>, +n: Nat, e: {List.length(&2, Bool, bs) == n : Nat}) ->
  {takeN(n, bs) == bs : List<&2, Bool>}:
  match bs n:
    case Nil{} 0n:
      {==}
    case Nil{} 1n+p:
      len_no({takeN(1n+p, Nil{}) == Nil{} : List<&2, Bool>}, p, e)
    case Con{+h, +t} 0n:
      len_no({takeN(0n, Con{h, t}) == Con{h, t} : List<&2, Bool>}, List.length(&2, Bool, t),
        Equal.sym(Nat, 1n+List.length(&2, Bool, t), 0n, e))
    case Con{+h, +t} 1n+p:
      Equal.cong(List<&2, Bool>, List<&2, Bool>, y => Con{h, y}, takeN(p, t), t,
        take_all(t, p, Equal.cong(Nat, Nat, pred, 1n+List.length(&2, Bool, t), 1n+p, e)))

def len_nots(+bs: List<&2, Bool>) ->
  {List.length(&2, Bool, D.nots(bs)) == List.length(&2, Bool, bs) : Nat}:
  match bs:
    case Nil{}:
      {==}
    case Con{+h, +t}:
      Equal.cong(Nat, Nat, y => 1n+y, List.length(&2, Bool, D.nots(t)), List.length(&2, Bool, t),
        len_nots(t))

# a stored block's bits: the header, zeros to the byte, LEN, NLEN, the bytes
def SB(+cur: Bytes(), +cnt: List<&2, Bool>, last: Bool) -> List<&2, Bool>:
  app([last, False{}, False{}, False{}, False{}, False{}, False{}, False{}],
    app(takeN(16n, cnt), app(takeN(16n, D.nots(cnt)), bitsof(cur))))

def A3(+ow: Bytes(), last: Bool) -> D.W:
  D.W{ow, [False{}, False{}, last]}

def P1(+ow: Bytes(), +cnt: List<&2, Bool>, last: Bool) -> D.W:
  D.putn(16n, cnt, D.align(D.put(D.put(D.put(D.W{ow, Nil{}}, last), False{}), False{})))

def P2(+ow: Bytes(), +cnt: List<&2, Bool>, last: Bool) -> D.W:
  D.putn(16n, D.nots(cnt), P1(ow, cnt, last))

# a stored block written at a byte
def stored_bits(+ow: Bytes(), +cur: Bytes(), +cnt: List<&2, Bool>, +last: Bool) ->
  {wbits(D.stored_one(D.W{ow, Nil{}}, cur, cnt, last)) == app(bitsof(ow), SB(cur, cnt, last)) :
    List<&2, Bool>}:
  +xs = takeN(16n, D.nots(cnt))
  +bc = bitsof(cur)
  +a3 = A3(ow, last)
  Equal.trans(List<&2, Bool>, wbits(D.put_raw(D.W{D.w_out(P2(ow, cnt, last)), Nil{}}, cur)),
    app(wbits(P2(ow, cnt, last)), bc), app(bitsof(ow), SB(cur, cnt, last)),
    raw_bits(D.w_out(P2(ow, cnt, last)), cur),
    Equal.trans(List<&2, Bool>, app(wbits(P2(ow, cnt, last)), bc), app(wbits(P1(ow, cnt, last)), app(xs, bc)),
      app(bitsof(ow), SB(cur, cnt, last)),
      putn_k(16n, D.nots(cnt), P1(ow, cnt, last), bc),
      Equal.trans(List<&2, Bool>, app(wbits(P1(ow, cnt, last)), app(xs, bc)),
        app(wbits(D.putx(5n, a3, 0n)), app(takeN(16n, cnt), app(xs, bc))), app(bitsof(ow), SB(cur, cnt, last)),
        putn_k(16n, cnt, D.putx(5n, a3, 0n), app(xs, bc)),
        Equal.trans(List<&2, Bool>, app(wbits(D.putx(5n, a3, 0n)), app(takeN(16n, cnt), app(xs, bc))),
          app(wbits(a3), app(D.xbits(5n, 0n), app(takeN(16n, cnt), app(xs, bc)))),
          app(bitsof(ow), SB(cur, cnt, last)),
          putx_k(5n, a3, 0n, app(takeN(16n, cnt), app(xs, bc))),
          app_assoc(bitsof(ow), [last, False{}, False{}],
            app(D.xbits(5n, 0n), app(takeN(16n, cnt), app(xs, bc))))))))

# the n-bit word of k: k increments of zero
def it(+n: Nat, k: Nat) -> Word(n):
  match k:
    case 0n:
      Word.zero(n)
    case 1n+j:
      Word.inc(n, it(n, j))

# two increments of a word whose low bit is clear step the rest once
def it_double(+p: Nat, +m: Nat) -> {it(1n+p, Nat.double(m)) == WCon{False{}, it(p, m)} : Word(1n+p)}:
  match m:
    case 0n:
      {==}
    case 1n+j:
      %Equal.sym(Word(1n+p), it(1n+p, Nat.double(j)), WCon{False{}, it(p, j)}, it_double(p, j)) :
        {Word.inc(1n+p, Word.inc(1n+p, _)) == WCon{False{}, Word.inc(p, it(p, j))} : Word(1n+p)}
      {==}

def it_bit(+p: Nat, +b: Bool, +m: Nat) -> {it(1n+p, Nat.bit(b, m)) == WCon{b, it(p, m)} : Word(1n+p)}:
  match b:
    case False{}:
      it_double(p, m)
    case True{}:
      %Equal.sym(Word(1n+p), it(1n+p, Nat.double(m)), WCon{False{}, it(p, m)}, it_double(p, m)) :
        {Word.inc(1n+p, _) == WCon{True{}, it(p, m)} : Word(1n+p)}
      {==}

# a word is its value's word
def it_val(+n: Nat, +w: Word(n)) -> {it(n, Word.to_nat(n, w)) == w : Word(n)}:
  match n:
    case 0n:
      match w:
        case WNil{}:
          {==}
    case 1n+p:
      match w:
        case WCon{+b, +t}:
          %Equal.sym(Nat, Word.to_nat(1n+p, WCon{b, t}), Nat.bit(b, Word.to_nat(p, t)),
            Word.to_nat_bit(p, b, t)) : {it(1n+p, _) == WCon{b, t} : Word(1n+p)}
          %Equal.sym(Word(1n+p), it(1n+p, Nat.bit(b, Word.to_nat(p, t))), WCon{b, it(p, Word.to_nat(p, t))},
            it_bit(p, b, Word.to_nat(p, t))) : {_ == WCon{b, t} : Word(1n+p)}
          %Equal.sym(Word(p), it(p, Word.to_nat(p, t)), t, it_val(p, t)) :
            {WCon{b, _} == WCon{b, t} : Word(1n+p)}
          {==}


# the byte of eight bits
def b8(b0: Bool, b1: Bool, b2: Bool, b3: Bool, b4: Bool, b5: Bool, b6: Bool, b7: Bool) -> U32:
  U32{WCon{b0, WCon{b1, WCon{b2, WCon{b3, WCon{b4, WCon{b5, WCon{b6, WCon{b7, Word.zero(24n)}}}}}}}}}

# a clear low bit of the right side decides nothing a < b does not
def peel(+b: Bool, +x: Cmp) -> {Cmp.is_lt(Word.cmp.fin(b, False{}, x)) == Cmp.is_lt(x) : Bool}:
  match b x:
    case False{} LT{}:
      {==}
    case False{} EQ{}:
      {==}
    case False{} GT{}:
      {==}
    case True{} LT{}:
      {==}
    case True{} EQ{}:
      {==}
    case True{} GT{}:
      {==}

def peel.go(+b: Bool, +x: Cmp, e: {Cmp.is_lt(Word.cmp.fin(b, False{}, x)) == True{} : Bool}) ->
  {Cmp.is_lt(x) == True{} : Bool}:
  Equal.trans(Bool, Cmp.is_lt(x), Cmp.is_lt(Word.cmp.fin(b, False{}, x)), True{},
    Equal.sym(Bool, Cmp.is_lt(Word.cmp.fin(b, False{}, x)), Cmp.is_lt(x), peel(b, x)), e)

def high0.at(+b0: Bool, +b1: Bool, +b2: Bool, +b3: Bool, +b4: Bool, +b5: Bool, +b6: Bool, +b7: Bool,
  +r: Word(24n), lt: {Cmp.is_lt(Word.cmp.fin(b0, False{}, Word.cmp.fin(b1, False{},
    Word.cmp.fin(b2, False{}, Word.cmp.fin(b3, False{}, Word.cmp.fin(b4, False{},
    Word.cmp.fin(b5, False{}, Word.cmp.fin(b6, False{}, Word.cmp.fin(b7, False{},
    Word.cmp(24n, r, it(24n, 1n))))))))))) == True{} : Bool}) -> {r == Word.zero(24n) : Word(24n)}:
  +t8 = Word.cmp(24n, r, it(24n, 1n))
  +t7 = Word.cmp.fin(b7, False{}, t8)
  +t6 = Word.cmp.fin(b6, False{}, t7)
  +t5 = Word.cmp.fin(b5, False{}, t6)
  +t4 = Word.cmp.fin(b4, False{}, t5)
  +t3 = Word.cmp.fin(b3, False{}, t4)
  +t2 = Word.cmp.fin(b2, False{}, t3)
  +t1 = Word.cmp.fin(b1, False{}, t2)
  e8 = peel.go(b7, t8, peel.go(b6, t7, peel.go(b5, t6, peel.go(b4, t5, peel.go(b3, t4,
    peel.go(b2, t3, peel.go(b1, t2, peel.go(b0, t1, lt))))))))
  e9 = Equal.trans(Bool, Nat.is_lt(Word.to_nat(24n, r), 1n), Cmp.is_lt(t8), True{},
    Equal.cong(Cmp, Bool, Cmp.is_lt, Nat.cmp(Word.to_nat(24n, r), 1n), t8,
      Equal.sym(Cmp, t8, Nat.cmp(Word.to_nat(24n, r), 1n), Word.cmp_nat(24n, r, it(24n, 1n)))), e8)
  %it_val(24n, r) : {_ == Word.zero(24n) : Word(24n)}
  %Equal.sym(Nat, Word.to_nat(24n, r), 0n, lt_one(Word.to_nat(24n, r))(e9)) :
    {it(24n, _) == Word.zero(24n) : Word(24n)}
  {==}

# below 256: the three high bytes are 0
def high0(+b0: Bool, +b1: Bool, +b2: Bool, +b3: Bool, +b4: Bool, +b5: Bool, +b6: Bool, +b7: Bool,
  +r: Word(24n)) ->
  {U32.is_lt(U32{WCon{b0, WCon{b1, WCon{b2, WCon{b3, WCon{b4, WCon{b5, WCon{b6, WCon{b7, r}}}}}}}}},
    256) == True{} : Bool} -> {r == Word.zero(24n) : Word(24n)}:
  lt => high0.at(b0, b1, b2, b3, b4, b5, b6, b7, r, lt)

# a byte read back from its bits, eight bits at a time
def byte_back.at(+b0: Bool, +b1: Bool, +b2: Bool, +b3: Bool, +b4: Bool, +b5: Bool, +b6: Bool, +b7: Bool) ->
  {U32.from_nat(D.hval(D.revapp(D.unbyte(b8(b0, b1, b2, b3, b4, b5, b6, b7)), Nil{}), 0n)) == b8(b0, b1, b2, b3, b4, b5, b6, b7) : U32}:
  match b0 b1 b2 b3 b4 b5 b6 b7:
    case False{} False{} False{} False{} False{} False{} False{} False{}:
      {==}
    case False{} False{} False{} False{} False{} False{} False{} True{}:
      {==}
    case False{} False{} False{} False{} False{} False{} True{} False{}:
      {==}
    case False{} False{} False{} False{} False{} False{} True{} True{}:
      {==}
    case False{} False{} False{} False{} False{} True{} False{} False{}:
      {==}
    case False{} False{} False{} False{} False{} True{} False{} True{}:
      {==}
    case False{} False{} False{} False{} False{} True{} True{} False{}:
      {==}
    case False{} False{} False{} False{} False{} True{} True{} True{}:
      {==}
    case False{} False{} False{} False{} True{} False{} False{} False{}:
      {==}
    case False{} False{} False{} False{} True{} False{} False{} True{}:
      {==}
    case False{} False{} False{} False{} True{} False{} True{} False{}:
      {==}
    case False{} False{} False{} False{} True{} False{} True{} True{}:
      {==}
    case False{} False{} False{} False{} True{} True{} False{} False{}:
      {==}
    case False{} False{} False{} False{} True{} True{} False{} True{}:
      {==}
    case False{} False{} False{} False{} True{} True{} True{} False{}:
      {==}
    case False{} False{} False{} False{} True{} True{} True{} True{}:
      {==}
    case False{} False{} False{} True{} False{} False{} False{} False{}:
      {==}
    case False{} False{} False{} True{} False{} False{} False{} True{}:
      {==}
    case False{} False{} False{} True{} False{} False{} True{} False{}:
      {==}
    case False{} False{} False{} True{} False{} False{} True{} True{}:
      {==}
    case False{} False{} False{} True{} False{} True{} False{} False{}:
      {==}
    case False{} False{} False{} True{} False{} True{} False{} True{}:
      {==}
    case False{} False{} False{} True{} False{} True{} True{} False{}:
      {==}
    case False{} False{} False{} True{} False{} True{} True{} True{}:
      {==}
    case False{} False{} False{} True{} True{} False{} False{} False{}:
      {==}
    case False{} False{} False{} True{} True{} False{} False{} True{}:
      {==}
    case False{} False{} False{} True{} True{} False{} True{} False{}:
      {==}
    case False{} False{} False{} True{} True{} False{} True{} True{}:
      {==}
    case False{} False{} False{} True{} True{} True{} False{} False{}:
      {==}
    case False{} False{} False{} True{} True{} True{} False{} True{}:
      {==}
    case False{} False{} False{} True{} True{} True{} True{} False{}:
      {==}
    case False{} False{} False{} True{} True{} True{} True{} True{}:
      {==}
    case False{} False{} True{} False{} False{} False{} False{} False{}:
      {==}
    case False{} False{} True{} False{} False{} False{} False{} True{}:
      {==}
    case False{} False{} True{} False{} False{} False{} True{} False{}:
      {==}
    case False{} False{} True{} False{} False{} False{} True{} True{}:
      {==}
    case False{} False{} True{} False{} False{} True{} False{} False{}:
      {==}
    case False{} False{} True{} False{} False{} True{} False{} True{}:
      {==}
    case False{} False{} True{} False{} False{} True{} True{} False{}:
      {==}
    case False{} False{} True{} False{} False{} True{} True{} True{}:
      {==}
    case False{} False{} True{} False{} True{} False{} False{} False{}:
      {==}
    case False{} False{} True{} False{} True{} False{} False{} True{}:
      {==}
    case False{} False{} True{} False{} True{} False{} True{} False{}:
      {==}
    case False{} False{} True{} False{} True{} False{} True{} True{}:
      {==}
    case False{} False{} True{} False{} True{} True{} False{} False{}:
      {==}
    case False{} False{} True{} False{} True{} True{} False{} True{}:
      {==}
    case False{} False{} True{} False{} True{} True{} True{} False{}:
      {==}
    case False{} False{} True{} False{} True{} True{} True{} True{}:
      {==}
    case False{} False{} True{} True{} False{} False{} False{} False{}:
      {==}
    case False{} False{} True{} True{} False{} False{} False{} True{}:
      {==}
    case False{} False{} True{} True{} False{} False{} True{} False{}:
      {==}
    case False{} False{} True{} True{} False{} False{} True{} True{}:
      {==}
    case False{} False{} True{} True{} False{} True{} False{} False{}:
      {==}
    case False{} False{} True{} True{} False{} True{} False{} True{}:
      {==}
    case False{} False{} True{} True{} False{} True{} True{} False{}:
      {==}
    case False{} False{} True{} True{} False{} True{} True{} True{}:
      {==}
    case False{} False{} True{} True{} True{} False{} False{} False{}:
      {==}
    case False{} False{} True{} True{} True{} False{} False{} True{}:
      {==}
    case False{} False{} True{} True{} True{} False{} True{} False{}:
      {==}
    case False{} False{} True{} True{} True{} False{} True{} True{}:
      {==}
    case False{} False{} True{} True{} True{} True{} False{} False{}:
      {==}
    case False{} False{} True{} True{} True{} True{} False{} True{}:
      {==}
    case False{} False{} True{} True{} True{} True{} True{} False{}:
      {==}
    case False{} False{} True{} True{} True{} True{} True{} True{}:
      {==}
    case False{} True{} False{} False{} False{} False{} False{} False{}:
      {==}
    case False{} True{} False{} False{} False{} False{} False{} True{}:
      {==}
    case False{} True{} False{} False{} False{} False{} True{} False{}:
      {==}
    case False{} True{} False{} False{} False{} False{} True{} True{}:
      {==}
    case False{} True{} False{} False{} False{} True{} False{} False{}:
      {==}
    case False{} True{} False{} False{} False{} True{} False{} True{}:
      {==}
    case False{} True{} False{} False{} False{} True{} True{} False{}:
      {==}
    case False{} True{} False{} False{} False{} True{} True{} True{}:
      {==}
    case False{} True{} False{} False{} True{} False{} False{} False{}:
      {==}
    case False{} True{} False{} False{} True{} False{} False{} True{}:
      {==}
    case False{} True{} False{} False{} True{} False{} True{} False{}:
      {==}
    case False{} True{} False{} False{} True{} False{} True{} True{}:
      {==}
    case False{} True{} False{} False{} True{} True{} False{} False{}:
      {==}
    case False{} True{} False{} False{} True{} True{} False{} True{}:
      {==}
    case False{} True{} False{} False{} True{} True{} True{} False{}:
      {==}
    case False{} True{} False{} False{} True{} True{} True{} True{}:
      {==}
    case False{} True{} False{} True{} False{} False{} False{} False{}:
      {==}
    case False{} True{} False{} True{} False{} False{} False{} True{}:
      {==}
    case False{} True{} False{} True{} False{} False{} True{} False{}:
      {==}
    case False{} True{} False{} True{} False{} False{} True{} True{}:
      {==}
    case False{} True{} False{} True{} False{} True{} False{} False{}:
      {==}
    case False{} True{} False{} True{} False{} True{} False{} True{}:
      {==}
    case False{} True{} False{} True{} False{} True{} True{} False{}:
      {==}
    case False{} True{} False{} True{} False{} True{} True{} True{}:
      {==}
    case False{} True{} False{} True{} True{} False{} False{} False{}:
      {==}
    case False{} True{} False{} True{} True{} False{} False{} True{}:
      {==}
    case False{} True{} False{} True{} True{} False{} True{} False{}:
      {==}
    case False{} True{} False{} True{} True{} False{} True{} True{}:
      {==}
    case False{} True{} False{} True{} True{} True{} False{} False{}:
      {==}
    case False{} True{} False{} True{} True{} True{} False{} True{}:
      {==}
    case False{} True{} False{} True{} True{} True{} True{} False{}:
      {==}
    case False{} True{} False{} True{} True{} True{} True{} True{}:
      {==}
    case False{} True{} True{} False{} False{} False{} False{} False{}:
      {==}
    case False{} True{} True{} False{} False{} False{} False{} True{}:
      {==}
    case False{} True{} True{} False{} False{} False{} True{} False{}:
      {==}
    case False{} True{} True{} False{} False{} False{} True{} True{}:
      {==}
    case False{} True{} True{} False{} False{} True{} False{} False{}:
      {==}
    case False{} True{} True{} False{} False{} True{} False{} True{}:
      {==}
    case False{} True{} True{} False{} False{} True{} True{} False{}:
      {==}
    case False{} True{} True{} False{} False{} True{} True{} True{}:
      {==}
    case False{} True{} True{} False{} True{} False{} False{} False{}:
      {==}
    case False{} True{} True{} False{} True{} False{} False{} True{}:
      {==}
    case False{} True{} True{} False{} True{} False{} True{} False{}:
      {==}
    case False{} True{} True{} False{} True{} False{} True{} True{}:
      {==}
    case False{} True{} True{} False{} True{} True{} False{} False{}:
      {==}
    case False{} True{} True{} False{} True{} True{} False{} True{}:
      {==}
    case False{} True{} True{} False{} True{} True{} True{} False{}:
      {==}
    case False{} True{} True{} False{} True{} True{} True{} True{}:
      {==}
    case False{} True{} True{} True{} False{} False{} False{} False{}:
      {==}
    case False{} True{} True{} True{} False{} False{} False{} True{}:
      {==}
    case False{} True{} True{} True{} False{} False{} True{} False{}:
      {==}
    case False{} True{} True{} True{} False{} False{} True{} True{}:
      {==}
    case False{} True{} True{} True{} False{} True{} False{} False{}:
      {==}
    case False{} True{} True{} True{} False{} True{} False{} True{}:
      {==}
    case False{} True{} True{} True{} False{} True{} True{} False{}:
      {==}
    case False{} True{} True{} True{} False{} True{} True{} True{}:
      {==}
    case False{} True{} True{} True{} True{} False{} False{} False{}:
      {==}
    case False{} True{} True{} True{} True{} False{} False{} True{}:
      {==}
    case False{} True{} True{} True{} True{} False{} True{} False{}:
      {==}
    case False{} True{} True{} True{} True{} False{} True{} True{}:
      {==}
    case False{} True{} True{} True{} True{} True{} False{} False{}:
      {==}
    case False{} True{} True{} True{} True{} True{} False{} True{}:
      {==}
    case False{} True{} True{} True{} True{} True{} True{} False{}:
      {==}
    case False{} True{} True{} True{} True{} True{} True{} True{}:
      {==}
    case True{} False{} False{} False{} False{} False{} False{} False{}:
      {==}
    case True{} False{} False{} False{} False{} False{} False{} True{}:
      {==}
    case True{} False{} False{} False{} False{} False{} True{} False{}:
      {==}
    case True{} False{} False{} False{} False{} False{} True{} True{}:
      {==}
    case True{} False{} False{} False{} False{} True{} False{} False{}:
      {==}
    case True{} False{} False{} False{} False{} True{} False{} True{}:
      {==}
    case True{} False{} False{} False{} False{} True{} True{} False{}:
      {==}
    case True{} False{} False{} False{} False{} True{} True{} True{}:
      {==}
    case True{} False{} False{} False{} True{} False{} False{} False{}:
      {==}
    case True{} False{} False{} False{} True{} False{} False{} True{}:
      {==}
    case True{} False{} False{} False{} True{} False{} True{} False{}:
      {==}
    case True{} False{} False{} False{} True{} False{} True{} True{}:
      {==}
    case True{} False{} False{} False{} True{} True{} False{} False{}:
      {==}
    case True{} False{} False{} False{} True{} True{} False{} True{}:
      {==}
    case True{} False{} False{} False{} True{} True{} True{} False{}:
      {==}
    case True{} False{} False{} False{} True{} True{} True{} True{}:
      {==}
    case True{} False{} False{} True{} False{} False{} False{} False{}:
      {==}
    case True{} False{} False{} True{} False{} False{} False{} True{}:
      {==}
    case True{} False{} False{} True{} False{} False{} True{} False{}:
      {==}
    case True{} False{} False{} True{} False{} False{} True{} True{}:
      {==}
    case True{} False{} False{} True{} False{} True{} False{} False{}:
      {==}
    case True{} False{} False{} True{} False{} True{} False{} True{}:
      {==}
    case True{} False{} False{} True{} False{} True{} True{} False{}:
      {==}
    case True{} False{} False{} True{} False{} True{} True{} True{}:
      {==}
    case True{} False{} False{} True{} True{} False{} False{} False{}:
      {==}
    case True{} False{} False{} True{} True{} False{} False{} True{}:
      {==}
    case True{} False{} False{} True{} True{} False{} True{} False{}:
      {==}
    case True{} False{} False{} True{} True{} False{} True{} True{}:
      {==}
    case True{} False{} False{} True{} True{} True{} False{} False{}:
      {==}
    case True{} False{} False{} True{} True{} True{} False{} True{}:
      {==}
    case True{} False{} False{} True{} True{} True{} True{} False{}:
      {==}
    case True{} False{} False{} True{} True{} True{} True{} True{}:
      {==}
    case True{} False{} True{} False{} False{} False{} False{} False{}:
      {==}
    case True{} False{} True{} False{} False{} False{} False{} True{}:
      {==}
    case True{} False{} True{} False{} False{} False{} True{} False{}:
      {==}
    case True{} False{} True{} False{} False{} False{} True{} True{}:
      {==}
    case True{} False{} True{} False{} False{} True{} False{} False{}:
      {==}
    case True{} False{} True{} False{} False{} True{} False{} True{}:
      {==}
    case True{} False{} True{} False{} False{} True{} True{} False{}:
      {==}
    case True{} False{} True{} False{} False{} True{} True{} True{}:
      {==}
    case True{} False{} True{} False{} True{} False{} False{} False{}:
      {==}
    case True{} False{} True{} False{} True{} False{} False{} True{}:
      {==}
    case True{} False{} True{} False{} True{} False{} True{} False{}:
      {==}
    case True{} False{} True{} False{} True{} False{} True{} True{}:
      {==}
    case True{} False{} True{} False{} True{} True{} False{} False{}:
      {==}
    case True{} False{} True{} False{} True{} True{} False{} True{}:
      {==}
    case True{} False{} True{} False{} True{} True{} True{} False{}:
      {==}
    case True{} False{} True{} False{} True{} True{} True{} True{}:
      {==}
    case True{} False{} True{} True{} False{} False{} False{} False{}:
      {==}
    case True{} False{} True{} True{} False{} False{} False{} True{}:
      {==}
    case True{} False{} True{} True{} False{} False{} True{} False{}:
      {==}
    case True{} False{} True{} True{} False{} False{} True{} True{}:
      {==}
    case True{} False{} True{} True{} False{} True{} False{} False{}:
      {==}
    case True{} False{} True{} True{} False{} True{} False{} True{}:
      {==}
    case True{} False{} True{} True{} False{} True{} True{} False{}:
      {==}
    case True{} False{} True{} True{} False{} True{} True{} True{}:
      {==}
    case True{} False{} True{} True{} True{} False{} False{} False{}:
      {==}
    case True{} False{} True{} True{} True{} False{} False{} True{}:
      {==}
    case True{} False{} True{} True{} True{} False{} True{} False{}:
      {==}
    case True{} False{} True{} True{} True{} False{} True{} True{}:
      {==}
    case True{} False{} True{} True{} True{} True{} False{} False{}:
      {==}
    case True{} False{} True{} True{} True{} True{} False{} True{}:
      {==}
    case True{} False{} True{} True{} True{} True{} True{} False{}:
      {==}
    case True{} False{} True{} True{} True{} True{} True{} True{}:
      {==}
    case True{} True{} False{} False{} False{} False{} False{} False{}:
      {==}
    case True{} True{} False{} False{} False{} False{} False{} True{}:
      {==}
    case True{} True{} False{} False{} False{} False{} True{} False{}:
      {==}
    case True{} True{} False{} False{} False{} False{} True{} True{}:
      {==}
    case True{} True{} False{} False{} False{} True{} False{} False{}:
      {==}
    case True{} True{} False{} False{} False{} True{} False{} True{}:
      {==}
    case True{} True{} False{} False{} False{} True{} True{} False{}:
      {==}
    case True{} True{} False{} False{} False{} True{} True{} True{}:
      {==}
    case True{} True{} False{} False{} True{} False{} False{} False{}:
      {==}
    case True{} True{} False{} False{} True{} False{} False{} True{}:
      {==}
    case True{} True{} False{} False{} True{} False{} True{} False{}:
      {==}
    case True{} True{} False{} False{} True{} False{} True{} True{}:
      {==}
    case True{} True{} False{} False{} True{} True{} False{} False{}:
      {==}
    case True{} True{} False{} False{} True{} True{} False{} True{}:
      {==}
    case True{} True{} False{} False{} True{} True{} True{} False{}:
      {==}
    case True{} True{} False{} False{} True{} True{} True{} True{}:
      {==}
    case True{} True{} False{} True{} False{} False{} False{} False{}:
      {==}
    case True{} True{} False{} True{} False{} False{} False{} True{}:
      {==}
    case True{} True{} False{} True{} False{} False{} True{} False{}:
      {==}
    case True{} True{} False{} True{} False{} False{} True{} True{}:
      {==}
    case True{} True{} False{} True{} False{} True{} False{} False{}:
      {==}
    case True{} True{} False{} True{} False{} True{} False{} True{}:
      {==}
    case True{} True{} False{} True{} False{} True{} True{} False{}:
      {==}
    case True{} True{} False{} True{} False{} True{} True{} True{}:
      {==}
    case True{} True{} False{} True{} True{} False{} False{} False{}:
      {==}
    case True{} True{} False{} True{} True{} False{} False{} True{}:
      {==}
    case True{} True{} False{} True{} True{} False{} True{} False{}:
      {==}
    case True{} True{} False{} True{} True{} False{} True{} True{}:
      {==}
    case True{} True{} False{} True{} True{} True{} False{} False{}:
      {==}
    case True{} True{} False{} True{} True{} True{} False{} True{}:
      {==}
    case True{} True{} False{} True{} True{} True{} True{} False{}:
      {==}
    case True{} True{} False{} True{} True{} True{} True{} True{}:
      {==}
    case True{} True{} True{} False{} False{} False{} False{} False{}:
      {==}
    case True{} True{} True{} False{} False{} False{} False{} True{}:
      {==}
    case True{} True{} True{} False{} False{} False{} True{} False{}:
      {==}
    case True{} True{} True{} False{} False{} False{} True{} True{}:
      {==}
    case True{} True{} True{} False{} False{} True{} False{} False{}:
      {==}
    case True{} True{} True{} False{} False{} True{} False{} True{}:
      {==}
    case True{} True{} True{} False{} False{} True{} True{} False{}:
      {==}
    case True{} True{} True{} False{} False{} True{} True{} True{}:
      {==}
    case True{} True{} True{} False{} True{} False{} False{} False{}:
      {==}
    case True{} True{} True{} False{} True{} False{} False{} True{}:
      {==}
    case True{} True{} True{} False{} True{} False{} True{} False{}:
      {==}
    case True{} True{} True{} False{} True{} False{} True{} True{}:
      {==}
    case True{} True{} True{} False{} True{} True{} False{} False{}:
      {==}
    case True{} True{} True{} False{} True{} True{} False{} True{}:
      {==}
    case True{} True{} True{} False{} True{} True{} True{} False{}:
      {==}
    case True{} True{} True{} False{} True{} True{} True{} True{}:
      {==}
    case True{} True{} True{} True{} False{} False{} False{} False{}:
      {==}
    case True{} True{} True{} True{} False{} False{} False{} True{}:
      {==}
    case True{} True{} True{} True{} False{} False{} True{} False{}:
      {==}
    case True{} True{} True{} True{} False{} False{} True{} True{}:
      {==}
    case True{} True{} True{} True{} False{} True{} False{} False{}:
      {==}
    case True{} True{} True{} True{} False{} True{} False{} True{}:
      {==}
    case True{} True{} True{} True{} False{} True{} True{} False{}:
      {==}
    case True{} True{} True{} True{} False{} True{} True{} True{}:
      {==}
    case True{} True{} True{} True{} True{} False{} False{} False{}:
      {==}
    case True{} True{} True{} True{} True{} False{} False{} True{}:
      {==}
    case True{} True{} True{} True{} True{} False{} True{} False{}:
      {==}
    case True{} True{} True{} True{} True{} False{} True{} True{}:
      {==}
    case True{} True{} True{} True{} True{} True{} False{} False{}:
      {==}
    case True{} True{} True{} True{} True{} True{} False{} True{}:
      {==}
    case True{} True{} True{} True{} True{} True{} True{} False{}:
      {==}
    case True{} True{} True{} True{} True{} True{} True{} True{}:
      {==}

# a byte read back from its bits
def byte_back(+c: U32) -> {U32.is_lt(c, 256) == True{} : Bool} ->
  {U32.from_nat(D.hval(D.revapp(D.unbyte(c), Nil{}), 0n)) == c : U32}:
  match c:
    case U32{WCon{+b0, WCon{+b1, WCon{+b2, WCon{+b3, WCon{+b4, WCon{+b5, WCon{+b6, WCon{+b7, +r}}}}}}}}}:
      lt =>
        %Equal.sym(Word(24n), r, Word.zero(24n), high0(b0, b1, b2, b3, b4, b5, b6, b7, r)(lt)) :
          {U32.from_nat(D.hval(D.revapp(D.unbyte(U32{WCon{b0, WCon{b1, WCon{b2, WCon{b3, WCon{b4, WCon{b5, WCon{b6, WCon{b7, _}}}}}}}}}), Nil{}), 0n)) == U32{WCon{b0, WCon{b1, WCon{b2, WCon{b3, WCon{b4, WCon{b5, WCon{b6, WCon{b7, _}}}}}}}}} : U32}
        byte_back.at(b0, b1, b2, b3, b4, b5, b6, b7)

# Reading a stored block
# ----------------------

def bl(s: Bytes()) -> Nat:
  match s:
    case SNil{}:
      0n
    case SCon{h, t}:
      1n+bl(t)

def le_pred(+x: Nat, +c: Nat) -> {Nat.is_le(1n+x, c) == True{} : Bool} -> {Nat.is_le(x, c) == True{} : Bool}:
  match x c:
    case 0n 0n:
      e => Bool.no({Nat.is_le(0n, 0n) == True{} : Bool}, e)
    case 0n 1n+d:
      e => {==}
    case 1n+p 0n:
      e => Bool.no({Nat.is_le(1n+p, 0n) == True{} : Bool}, e)
    case 1n+p 1n+d:
      e => le_pred(p, d)(e)

def le_lt(+x: Nat, +c: Nat) -> {Nat.is_le(1n+x, c) == True{} : Bool} -> {Nat.is_lt(x, c) == True{} : Bool}:
  match x c:
    case 0n 0n:
      e => Bool.no({Nat.is_lt(0n, 0n) == True{} : Bool}, e)
    case 0n 1n+d:
      e => {==}
    case 1n+p 0n:
      e => Bool.no({Nat.is_lt(1n+p, 0n) == True{} : Bool}, e)
    case 1n+p 1n+d:
      e => le_lt(p, d)(e)

# room for a+1 more after m: room for one
def room_lt(+a: Nat, +m: Nat, +cap: Nat) -> {Nat.is_le(Nat.add(1n+a, m), cap) == True{} : Bool} ->
  {Nat.is_lt(m, cap) == True{} : Bool}:
  match a:
    case 0n:
      e => le_lt(m, cap)(e)
    case 1n+p:
      e => room_lt(p, m, cap)(le_pred(Nat.add(1n+p, m), cap)(e))

def push_app(+a: Bytes(), +c: U32, +r: Bytes()) ->
  {String.append(Bytes.push(a, c), r) == String.append(a, SCon{Chr{c}, r}) : Bytes()}:
  match a:
    case SNil{}:
      {==}
    case SCon{+h, +t}:
      Equal.cong(Bytes(), Bytes(), y => SCon{h, y}, String.append(Bytes.push(t, c), r),
        String.append(t, SCon{Chr{c}, r}), push_app(t, c, r))

def sc(+c: U32, +t: Bytes()) -> Bytes():
  SCon{Chr{c}, t}

def Ob(+dd: Bytes(), +m: Nat, +cap: Nat, +tb: D.Tabs) -> D.O:
  D.O{dd, 0n, m, cap, tb}

def SBy(+last: Bool, +left: Nat, +dd: Bytes(), +m: Nat, +cap: Nat, +tb: D.Tabs) -> D.St:
  D.St{D.Get{7n, Nil{}, D.KByte{last, left}}, Ob(dd, m, cap, tb), 0n}

def Aft(+last: Bool, +dd: Bytes(), +m: Nat, +cap: Nat, +tb: D.Tabs) -> D.St:
  D.next_block(last, Ob(dd, m, cap, tb), 0n)

def RB(+c: U32) -> U32:
  U32.from_nat(D.hval(D.revapp(D.unbyte(c), Nil{}), 0n))

# the rest of a stored block's bytes, read
def data(+last: Bool, +t: Bytes(), +c: U32, +dd: Bytes(), +m: Nat, +cap: Nat, +tb: D.Tabs,
  vc: {U32.is_lt(c, 256) == True{} : Bool}, +vt: {D.valid(t) == True{} : Bool},
  +room: {Nat.is_le(Nat.add(1n+bl(t), m), cap) == True{} : Bool}) ->
  {bfeed(bitsof(SCon{Chr{c}, t}), SBy(last, bl(t), dd, m, cap, tb)) ==
    Aft(last, String.append(dd, SCon{Chr{c}, t}), Nat.add(1n+bl(t), m), cap, tb) : D.St}:
  match last t:
    case True{} SNil{}:
      %Equal.sym(Bool, Nat.is_lt(m, cap), True{}, room_lt(0n, m, cap)(room)) :
        {D.emit.if(_, dd, 0n, m, cap, tb, RB(c), D.End{}, 0n) ==
          D.St{D.End{}, Ob(Bytes.push(dd, c), 1n+m, cap, tb), 0n} : D.St}
      %Equal.sym(U32, RB(c), c, byte_back(c)(vc)) :
        {D.St{D.End{}, Ob(Bytes.push(dd, _), 1n+m, cap, tb), 0n} ==
          D.St{D.End{}, Ob(Bytes.push(dd, c), 1n+m, cap, tb), 0n} : D.St}
      {==}
    case False{} SNil{}:
      %Equal.sym(Bool, Nat.is_lt(m, cap), True{}, room_lt(0n, m, cap)(room)) :
        {D.emit.if(_, dd, 0n, m, cap, tb, RB(c), D.Get{2n, Nil{}, D.KHead{}}, 0n) ==
          D.St{D.Get{2n, Nil{}, D.KHead{}}, Ob(Bytes.push(dd, c), 1n+m, cap, tb), 0n} : D.St}
      %Equal.sym(U32, RB(c), c, byte_back(c)(vc)) :
        {D.St{D.Get{2n, Nil{}, D.KHead{}}, Ob(Bytes.push(dd, _), 1n+m, cap, tb), 0n} ==
          D.St{D.Get{2n, Nil{}, D.KHead{}}, Ob(Bytes.push(dd, c), 1n+m, cap, tb), 0n} : D.St}
      {==}
    case True{} SCon{Chr{+c2}, +t2}:
      +r = sc(c2, t2)
      +b = bl(t2)
      +out = Aft(True{}, String.append(dd, SCon{Chr{c}, r}), Nat.add(2n+b, m), cap, tb)
      %Equal.sym(Bool, Nat.is_lt(m, cap), True{}, room_lt(1n+b, m, cap)(room)) :
        {bfeed(bitsof(r), D.emit.if(_, dd, 0n, m, cap, tb, RB(c), D.Get{7n, Nil{}, D.KByte{True{}, b}}, 0n))
          == out : D.St}
      %Equal.sym(U32, RB(c), c, byte_back(c)(vc)) :
        {bfeed(bitsof(r), SBy(True{}, b, Bytes.push(dd, _), 1n+m, cap, tb)) == out : D.St}
      %push_app(dd, c, r) : {bfeed(bitsof(r), SBy(True{}, b, Bytes.push(dd, c), 1n+m, cap, tb)) ==
        Aft(True{}, _, Nat.add(2n+b, m), cap, tb) : D.St}
      %add_succ(1n+b, m) : {bfeed(bitsof(r), SBy(True{}, b, Bytes.push(dd, c), 1n+m, cap, tb)) ==
        Aft(True{}, String.append(Bytes.push(dd, c), r), _, cap, tb) : D.St}
      data(True{}, t2, c2, Bytes.push(dd, c), 1n+m, cap, tb, Bool.and_l(U32.is_lt(c2, 256), D.valid(t2), vt),
        Bool.and_r(U32.is_lt(c2, 256), D.valid(t2), vt),
        Equal.trans(Bool, Nat.is_le(Nat.add(1n+b, 1n+m), cap), Nat.is_le(Nat.add(2n+b, m), cap), True{},
          Equal.cong(Nat, Bool, y => Nat.is_le(y, cap), Nat.add(1n+b, 1n+m), Nat.add(2n+b, m),
            add_succ(1n+b, m)), room))
    case False{} SCon{Chr{+c2}, +t2}:
      +r = sc(c2, t2)
      +b = bl(t2)
      +out = Aft(False{}, String.append(dd, SCon{Chr{c}, r}), Nat.add(2n+b, m), cap, tb)
      %Equal.sym(Bool, Nat.is_lt(m, cap), True{}, room_lt(1n+b, m, cap)(room)) :
        {bfeed(bitsof(r), D.emit.if(_, dd, 0n, m, cap, tb, RB(c), D.Get{7n, Nil{}, D.KByte{False{}, b}}, 0n))
          == out : D.St}
      %Equal.sym(U32, RB(c), c, byte_back(c)(vc)) :
        {bfeed(bitsof(r), SBy(False{}, b, Bytes.push(dd, _), 1n+m, cap, tb)) == out : D.St}
      %push_app(dd, c, r) : {bfeed(bitsof(r), SBy(False{}, b, Bytes.push(dd, c), 1n+m, cap, tb)) ==
        Aft(False{}, _, Nat.add(2n+b, m), cap, tb) : D.St}
      %add_succ(1n+b, m) : {bfeed(bitsof(r), SBy(False{}, b, Bytes.push(dd, c), 1n+m, cap, tb)) ==
        Aft(False{}, String.append(Bytes.push(dd, c), r), _, cap, tb) : D.St}
      data(False{}, t2, c2, Bytes.push(dd, c), 1n+m, cap, tb, Bool.and_l(U32.is_lt(c2, 256), D.valid(t2), vt),
        Bool.and_r(U32.is_lt(c2, 256), D.valid(t2), vt),
        Equal.trans(Bool, Nat.is_le(Nat.add(1n+b, 1n+m), cap), Nat.is_le(Nat.add(2n+b, m), cap), True{},
          Equal.cong(Nat, Bool, y => Nat.is_le(y, cap), Nat.add(1n+b, 1n+m), Nat.add(2n+b, m),
            add_succ(1n+b, m)), room))

def str_nil(+a: Bytes()) -> {String.append(a, "") == a : Bytes()}:
  match a:
    case SNil{}:
      {==}
    case SCon{+h, +t}:
      Equal.cong(Bytes(), Bytes(), y => SCon{h, y}, String.append(t, ""), t, str_nil(t))

def str_assoc(+a: Bytes(), +b: Bytes(), +c: Bytes()) ->
  {String.append(String.append(a, b), c) == String.append(a, String.append(b, c)) : Bytes()}:
  match a:
    case SNil{}:
      {==}
    case SCon{+h, +t}:
      Equal.cong(Bytes(), Bytes(), y => SCon{h, y}, String.append(String.append(t, b), c),
        String.append(t, String.append(b, c)), str_assoc(t, b, c))

# NLEN, read against LEN: every bit its complement
def compl_nots(+bs: List<&2, Bool>, +a: List<&2, Bool>, +b: List<&2, Bool>) ->
  {D.compl(D.revapp(bs, a), D.revapp(D.nots(bs), b)) == D.compl(a, b) : Bool}:
  match bs:
    case Nil{}:
      {==}
    case Con{+h, +t}:
      match h:
        case True{}:
          compl_nots(t, Con{True{}, a}, Con{False{}, b})
        case False{}:
          compl_nots(t, Con{False{}, a}, Con{True{}, b})

# the stream a stored block is read from: at a header, at a byte
def Dec(+dd: Bytes(), +m: Nat, +cap: Nat, +tb: D.Tabs) -> D.St:
  D.St{D.Get{2n, Nil{}, D.KHead{}}, Ob(dd, m, cap, tb), 0n}

# a stored block's bytes, LEN of them
def body(+last: Bool, +cur: Bytes(), +dd: Bytes(), +m: Nat, +cap: Nat, +tb: D.Tabs,
  +vcur: {D.valid(cur) == True{} : Bool}, +room: {Nat.is_le(Nat.add(bl(cur), m), cap) == True{} : Bool}) ->
  {bfeed(bitsof(cur), D.stored_body(last, bl(cur), Ob(dd, m, cap, tb), 0n)) ==
    Aft(last, String.append(dd, cur), Nat.add(bl(cur), m), cap, tb) : D.St}:
  match cur:
    case SNil{}:
      %Equal.sym(Bytes(), String.append(dd, ""), dd, str_nil(dd)) :
        {Aft(last, dd, m, cap, tb) == Aft(last, _, m, cap, tb) : D.St}
      {==}
    case SCon{Chr{+c}, +t}:
      data(last, t, c, dd, m, cap, tb, Bool.and_l(U32.is_lt(c, 256), D.valid(t), vcur),
        Bool.and_r(U32.is_lt(c, 256), D.valid(t), vcur), room)

# a stored block, read at a header
def block(+last: Bool, +cur: Bytes(), +cnt: List<&2, Bool>, +dd: Bytes(), +m: Nat, +cap: Nat, +tb: D.Tabs,
  +el: {List.length(&2, Bool, cnt) == 16n : Nat}, ev: {D.val(cnt) == bl(cur) : Nat},
  +vcur: {D.valid(cur) == True{} : Bool}, +room: {Nat.is_le(Nat.add(bl(cur), m), cap) == True{} : Bool}) ->
  {bfeed(SB(cur, cnt, last), Dec(dd, m, cap, tb)) ==
    Aft(last, String.append(dd, cur), Nat.add(bl(cur), m), cap, tb) : D.St}:
  +out = Aft(last, String.append(dd, cur), Nat.add(bl(cur), m), cap, tb)
  +o = Ob(dd, m, cap, tb)
  +t2 = takeN(16n, D.nots(cnt))
  +el2 = Equal.trans(Nat, List.length(&2, Bool, D.nots(cnt)), List.length(&2, Bool, cnt), 16n, len_nots(cnt), el)
  %Equal.sym(List<&2, Bool>, takeN(16n, cnt), cnt, take_all(cnt, 16n, el)) :
    {bfeed(bitsof(cur), D.stored_nlen(D.compl(D.revapp(_, Nil{}), D.revapp(t2, Nil{})), last,
      D.hval(D.revapp(_, Nil{}), 0n), o, 0n)) == out : D.St}
  %Equal.sym(List<&2, Bool>, t2, D.nots(cnt), take_all(D.nots(cnt), 16n, el2)) :
    {bfeed(bitsof(cur), D.stored_nlen(D.compl(D.revapp(cnt, Nil{}), D.revapp(_, Nil{})), last,
      D.hval(D.revapp(cnt, Nil{}), 0n), o, 0n)) == out : D.St}
  %Equal.sym(Bool, D.compl(D.revapp(cnt, Nil{}), D.revapp(D.nots(cnt), Nil{})), True{},
    compl_nots(cnt, Nil{}, Nil{})) :
    {bfeed(bitsof(cur), D.stored_nlen(_, last, D.hval(D.revapp(cnt, Nil{}), 0n), o, 0n)) == out : D.St}
  %Equal.sym(Nat, D.hval(D.revapp(cnt, Nil{}), 0n), D.val(cnt), hval_rev(cnt)) :
    {bfeed(bitsof(cur), D.stored_body(last, _, o, 0n)) == out : D.St}
  %Equal.sym(Nat, D.val(cnt), bl(cur), ev) :
    {bfeed(bitsof(cur), D.stored_body(last, _, o, 0n)) == out : D.St}
  body(last, cur, dd, m, cap, tb, vcur, room)

# The count
# ---------

def len_inc(+bs: List<&2, Bool>) -> {List.length(&2, Bool, D.inc(bs)) == List.length(&2, Bool, bs) : Nat}:
  match bs:
    case Nil{}:
      {==}
    case Con{+h, +t}:
      match h:
        case True{}:
          Equal.cong(Nat, Nat, y => 1n+y, List.length(&2, Bool, D.inc(t)), List.length(&2, Bool, t),
            len_inc(t))
        case False{}:
          {==}

# a count not yet full, one more
def val_inc(+bs: List<&2, Bool>) -> {D.all1(bs) == False{} : Bool} -> {D.val(D.inc(bs)) == 1n+D.val(bs) : Nat}:
  match bs:
    case Nil{}:
      e => Bool.no({D.val(D.inc(Nil{})) == 1n+D.val(Nil{}) : Nat}, Equal.sym(Bool, True{}, False{}, e))
    case Con{+h, +t}:
      match h:
        case True{}:
          e => Equal.cong(Nat, Nat, Nat.double, D.val(D.inc(t)), 1n+D.val(t), val_inc(t)(e))
        case False{}:
          e => {==}

def bl_push(+a: Bytes(), +c: U32) -> {bl(Bytes.push(a, c)) == 1n+bl(a) : Nat}:
  match a:
    case SNil{}:
      {==}
    case SCon{+h, +t}:
      Equal.cong(Nat, Nat, y => 1n+y, bl(Bytes.push(t, c)), 1n+bl(t), bl_push(t, c))

def valid_push(+a: Bytes(), +c: U32, +va: {D.valid(a) == True{} : Bool},
  +vc: {U32.is_lt(c, 256) == True{} : Bool}) -> {D.valid(Bytes.push(a, c)) == True{} : Bool}:
  match a:
    case SNil{}:
      %Equal.sym(Bool, U32.is_lt(c, 256), True{}, vc) : {Bool.and(_, True{}) == True{} : Bool}
      {==}
    case SCon{Chr{+h}, +t}:
      %Equal.sym(Bool, U32.is_lt(h, 256), True{}, Bool.and_l(U32.is_lt(h, 256), D.valid(t), va)) :
        {Bool.and(_, D.valid(Bytes.push(t, c))) == True{} : Bool}
      valid_push(t, c, Bool.and_r(U32.is_lt(h, 256), D.valid(t), va), vc)

def add_swap(+a: Nat, +b: Nat, +c: Nat) -> {Nat.add(a, Nat.add(b, c)) == Nat.add(b, Nat.add(a, c)) : Nat}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      Equal.trans(Nat, 1n+Nat.add(p, Nat.add(b, c)), 1n+Nat.add(b, Nat.add(p, c)), Nat.add(b, 1n+Nat.add(p, c)),
        Equal.cong(Nat, Nat, y => 1n+y, Nat.add(p, Nat.add(b, c)), Nat.add(b, Nat.add(p, c)), add_swap(p, b, c)),
        Equal.sym(Nat, Nat.add(b, 1n+Nat.add(p, c)), 1n+Nat.add(b, Nat.add(p, c)), add_succ(b, Nat.add(p, c))))

def le_addl(+b: Nat, +y: Nat, +cap: Nat) -> {Nat.is_le(Nat.add(b, y), cap) == True{} : Bool} ->
  {Nat.is_le(y, cap) == True{} : Bool}:
  match b:
    case 0n:
      e => e
    case 1n+p:
      e => le_addl(p, y, cap)(le_pred(Nat.add(p, y), cap)(e))

def le_by(+a: Nat, +b: Nat, +cap: Nat, e: {a == b : Nat}, le: {Nat.is_le(b, cap) == True{} : Bool}) ->
  {Nat.is_le(a, cap) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(a, cap), Nat.is_le(b, cap), True{},
    Equal.cong(Nat, Bool, y => Nat.is_le(y, cap), a, b, e), le)

# The blocks, one after another
# -----------------------------

# a block written at a byte, read at a header
def flush(+last: Bool, +cur: Bytes(), +cnt: List<&2, Bool>, +ow: Bytes(), +dd: Bytes(), +m: Nat, +cap: Nat,
  +tb: D.Tabs, +s0: D.St, +el: {List.length(&2, Bool, cnt) == 16n : Nat}, ev: {D.val(cnt) == bl(cur) : Nat},
  hdec: {bfeed(bitsof(ow), s0) == Dec(dd, m, cap, tb) : D.St}, +vcur: {D.valid(cur) == True{} : Bool},
  +room: {Nat.is_le(Nat.add(bl(cur), m), cap) == True{} : Bool}) ->
  {bfeed(bitsof(D.w_out(D.stored_one(D.W{ow, Nil{}}, cur, cnt, last))), s0) ==
    Aft(last, String.append(dd, cur), Nat.add(bl(cur), m), cap, tb) : D.St}:
  +so = D.stored_one(D.W{ow, Nil{}}, cur, cnt, last)
  +sb = SB(cur, cnt, last)
  +e1 = Equal.trans(List<&2, Bool>, bitsof(D.w_out(so)), app(bitsof(D.w_out(so)), Nil{}), app(bitsof(ow), sb),
    Equal.sym(List<&2, Bool>, app(bitsof(D.w_out(so)), Nil{}), bitsof(D.w_out(so)), app_nil(bitsof(D.w_out(so)))),
    stored_bits(ow, cur, cnt, last))
  Equal.trans(D.St, bfeed(bitsof(D.w_out(so)), s0), bfeed(app(bitsof(ow), sb), s0),
    Aft(last, String.append(dd, cur), Nat.add(bl(cur), m), cap, tb),
    Equal.cong(List<&2, Bool>, D.St, y => bfeed(y, s0), bitsof(D.w_out(so)), app(bitsof(ow), sb), e1),
    Equal.trans(D.St, bfeed(app(bitsof(ow), sb), s0), bfeed(sb, bfeed(bitsof(ow), s0)),
      Aft(last, String.append(dd, cur), Nat.add(bl(cur), m), cap, tb),
      bfeed_app(bitsof(ow), sb, s0),
      Equal.trans(D.St, bfeed(sb, bfeed(bitsof(ow), s0)), bfeed(sb, Dec(dd, m, cap, tb)),
        Aft(last, String.append(dd, cur), Nat.add(bl(cur), m), cap, tb),
        Equal.cong(D.St, D.St, y => bfeed(sb, y), bfeed(bitsof(ow), s0), Dec(dd, m, cap, tb), hdec),
        block(last, cur, cnt, dd, m, cap, tb, el, ev, vcur, room))))

# the stored blocks of the rest of x, cur filling with cnt its count,
# the stream so far read to dd, m written
def run(+x: Bytes(), +full: Bool, +last: Bool, +cur: Bytes(), +cnt: List<&2, Bool>, +ow: Bytes(), +dd: Bytes(),
  +m: Nat, +cap: Nat, +tb: D.Tabs, +s0: D.St, +ef: {D.all1(cnt) == full : Bool},
  +el: {List.length(&2, Bool, cnt) == 16n : Nat}, +ev: {D.val(cnt) == bl(cur) : Nat},
  +hdec: {bfeed(bitsof(ow), s0) == Dec(dd, m, cap, tb) : D.St}, +vcur: {D.valid(cur) == True{} : Bool},
  +vx: {D.valid(x) == True{} : Bool},
  +room: {Nat.is_le(Nat.add(bl(cur), Nat.add(bl(x), m)), cap) == True{} : Bool}) ->
  {bfeed(bitsof(D.w_out(D.stored.go(x, last, D.SS{cur, cnt, D.W{ow, Nil{}}}))), s0) ==
    Aft(last, String.append(dd, String.append(cur, x)), Nat.add(bl(cur), Nat.add(bl(x), m)), cap, tb) : D.St}:
  match x full:
    case SNil{} _:
      %Equal.sym(Bytes(), String.append(cur, ""), cur, str_nil(cur)) :
        {bfeed(bitsof(D.w_out(D.stored_one(D.W{ow, Nil{}}, cur, cnt, last))), s0) ==
          Aft(last, String.append(dd, _), Nat.add(bl(cur), m), cap, tb) : D.St}
      flush(last, cur, cnt, ow, dd, m, cap, tb, s0, el, ev, hdec, vcur, room)
    case SCon{Chr{+c}, +t} True{}:
      +so = D.stored_one(D.W{ow, Nil{}}, cur, cnt, False{})
      +r = sc(c, t)
      +bc = bl(cur)
      +bt = bl(t)
      +vc = Bool.and_l(U32.is_lt(c, 256), D.valid(t), vx)
      +n1 = Equal.trans(Nat, Nat.add(bc, 1n+Nat.add(bt, m)), 1n+Nat.add(bc, Nat.add(bt, m)),
        1n+Nat.add(bt, Nat.add(bc, m)), add_succ(bc, Nat.add(bt, m)),
        Equal.cong(Nat, Nat, y => 1n+y, Nat.add(bc, Nat.add(bt, m)), Nat.add(bt, Nat.add(bc, m)),
          add_swap(bc, bt, m)))
      %Equal.sym(Bool, D.all1(cnt), True{}, ef) :
        {bfeed(bitsof(D.w_out(D.stored.go(t, last, D.stored.add.at(_, cur, cnt, D.W{ow, Nil{}}, c)))), s0) ==
          Aft(last, String.append(dd, String.append(cur, r)), Nat.add(bc, 1n+Nat.add(bt, m)), cap, tb) : D.St}
      %str_assoc(dd, cur, r) :
        {bfeed(bitsof(D.w_out(D.stored.go(t, last, D.SS{Bytes.push("", c), D.one16(), so}))), s0) ==
          Aft(last, _, Nat.add(bc, 1n+Nat.add(bt, m)), cap, tb) : D.St}
      %Equal.sym(Nat, Nat.add(bc, 1n+Nat.add(bt, m)), 1n+Nat.add(bt, Nat.add(bc, m)), n1) :
        {bfeed(bitsof(D.w_out(D.stored.go(t, last, D.SS{Bytes.push("", c), D.one16(), so}))), s0) ==
          Aft(last, String.append(String.append(dd, cur), r), _, cap, tb) : D.St}
      run(t, False{}, last, Bytes.push("", c), D.one16(), D.w_out(so), String.append(dd, cur), Nat.add(bc, m), cap,
        tb, s0, {==}, {==}, {==},
        flush(False{}, cur, cnt, ow, dd, m, cap, tb, s0, el, ev, hdec, vcur,
          le_addl(1n+bt, Nat.add(bc, m), cap)(le_by(Nat.add(1n+bt, Nat.add(bc, m)), Nat.add(bc, Nat.add(1n+bt, m)),
            cap, add_swap(1n+bt, bc, m), room))),
        valid_push("", c, {==}, vc), Bool.and_r(U32.is_lt(c, 256), D.valid(t), vx),
        le_by(1n+Nat.add(bt, Nat.add(bc, m)), Nat.add(bc, 1n+Nat.add(bt, m)), cap,
          Equal.sym(Nat, Nat.add(bc, 1n+Nat.add(bt, m)), 1n+Nat.add(bt, Nat.add(bc, m)), n1), room))
    case SCon{Chr{+c}, +t} False{}:
      +r = sc(c, t)
      +bt = bl(t)
      +n2 = Equal.trans(Nat, Nat.add(bl(Bytes.push(cur, c)), Nat.add(bt, m)), 1n+Nat.add(bl(cur), Nat.add(bt, m)),
        Nat.add(bl(cur), 1n+Nat.add(bt, m)),
        Equal.cong(Nat, Nat, y => Nat.add(y, Nat.add(bt, m)), bl(Bytes.push(cur, c)), 1n+bl(cur), bl_push(cur, c)),
        Equal.sym(Nat, Nat.add(bl(cur), 1n+Nat.add(bt, m)), 1n+Nat.add(bl(cur), Nat.add(bt, m)),
          add_succ(bl(cur), Nat.add(bt, m))))
      %Equal.sym(Bool, D.all1(cnt), False{}, ef) :
        {bfeed(bitsof(D.w_out(D.stored.go(t, last, D.stored.add.at(_, cur, cnt, D.W{ow, Nil{}}, c)))), s0) ==
          Aft(last, String.append(dd, String.append(cur, r)), Nat.add(bl(cur), 1n+Nat.add(bt, m)), cap, tb) : D.St}
      %push_app(cur, c, t) :
        {bfeed(bitsof(D.w_out(D.stored.go(t, last, D.SS{Bytes.push(cur, c), D.inc(cnt), D.W{ow, Nil{}}}))), s0) ==
          Aft(last, String.append(dd, _), Nat.add(bl(cur), 1n+Nat.add(bt, m)), cap, tb) : D.St}
      %n2 :
        {bfeed(bitsof(D.w_out(D.stored.go(t, last, D.SS{Bytes.push(cur, c), D.inc(cnt), D.W{ow, Nil{}}}))), s0) ==
          Aft(last, String.append(dd, String.append(Bytes.push(cur, c), t)), _, cap, tb) : D.St}
      run(t, D.all1(D.inc(cnt)), last, Bytes.push(cur, c), D.inc(cnt), ow, dd, m, cap, tb, s0, {==},
        Equal.trans(Nat, List.length(&2, Bool, D.inc(cnt)), List.length(&2, Bool, cnt), 16n, len_inc(cnt), el),
        Equal.trans(Nat, D.val(D.inc(cnt)), 1n+D.val(cnt), bl(Bytes.push(cur, c)), val_inc(cnt)(ef),
          Equal.trans(Nat, 1n+D.val(cnt), 1n+bl(cur), bl(Bytes.push(cur, c)),
            Equal.cong(Nat, Nat, y => 1n+y, D.val(cnt), bl(cur), ev),
            Equal.sym(Nat, bl(Bytes.push(cur, c)), 1n+bl(cur), bl_push(cur, c)))),
        hdec, valid_push(cur, c, vcur, Bool.and_l(U32.is_lt(c, 256), D.valid(t), vx)),
        Bool.and_r(U32.is_lt(c, 256), D.valid(t), vx),
        le_by(Nat.add(bl(Bytes.push(cur, c)), Nat.add(bt, m)), Nat.add(bl(cur), 1n+Nat.add(bt, m)), cap, n2, room))

# The stream
# ----------

def blen(+s: Bytes()) -> {Bytes.len(s) == bl(s) : Nat}:
  match s:
    case SNil{}:
      {==}
    case SCon{+h, +t}:
      Equal.trans(Nat, String.length.go(t, 1n), 1n+String.length.go(t, 0n), 1n+bl(t), Bytes.len.shift(t, 0n),
        Equal.cong(Nat, Nat, y => 1n+y, String.length.go(t, 0n), bl(t), blen(t)))

def drop0(+s: Bytes()) -> {Bytes.drop(s, 0n) == s : Bytes()}:
  match s:
    case SNil{}:
      {==}
    case SCon{+h, +t}:
      {==}

# the stored stream of x, read bit by bit, whatever the tables
def stored_read(+x: Bytes(), +cap: Nat, +tb: D.Tabs, +vx: {D.valid(x) == True{} : Bool},
  fits: {Nat.is_le(Bytes.len(x), cap) == True{} : Bool}) ->
  {bfeed(bitsof(D.deflate(x, 0n)), Dec("", 0n, cap, tb)) ==
    D.St{D.End{}, D.O{x, 0n, Nat.add(bl(x), 0n), cap, tb}, 0n} : D.St}:
  run(x, False{}, True{}, "", D.z16(), "", "", 0n, cap, tb, Dec("", 0n, cap, tb), {==}, {==}, {==}, {==}, {==}, vx,
    le_by(Nat.add(bl(x), 0n), bl(x), cap, add_zero(bl(x)),
      le_by(bl(x), Bytes.len(x), cap, Equal.sym(Nat, Bytes.len(x), bl(x), blen(x)), fits)))

# the machine at the end of the stored stream of x
def ended_at(+x: Bytes(), +cap: Nat, +tb: D.Tabs) -> D.St:
  D.St{D.End{}, Ob(x, Nat.add(bl(x), 0n), cap, tb), 0n}

# the stored stream of x, inflated, whatever the tables
def round_trip(+x: Bytes(), +cap: Nat, +tb: D.Tabs, +vx: {D.valid(x) == True{} : Bool},
  +fits: {Nat.is_le(Bytes.len(x), cap) == True{} : Bool}) ->
  {D.finish(D.feed(D.deflate(x, 0n), Dec("", 0n, cap, tb))) == Done{x} : Result<&2, &2, D.Why, Bytes()>}:
  +d = D.deflate(x, 0n)
  +s0 = Dec("", 0n, cap, tb)
  +fin = ended_at(x, cap, tb)
  +e = Equal.trans(D.St, D.feed(d, s0), D.feed_list(Bytes.to_list(d), s0), fin,
    Laws.inflate_buf(d, s0),
    Equal.trans(D.St, D.feed_list(Bytes.to_list(d), s0), bfeed(bitsof(d), s0), fin,
      feed_bits(d, s0), stored_read(x, cap, tb, vx, fits)))
  %Equal.sym(D.St, D.feed(d, s0), fin, e) : {D.finish(_) == Done{x} : Result<&2, &2, D.Why, Bytes()>}
  Equal.cong(Bytes(), Result<&2, &2, D.Why, Bytes()>, y => Done{y}, Bytes.drop(x, 0n), x, drop0(x))

def Laws.stored_round_trip(x, cap, vx, fits):
  Equal.trans(Result<&2, &2, D.Why, Bytes()>, D.inflate(cap, D.deflate(x, 0n)),
    D.finish(D.feed(D.deflate(x, 0n), D.new(cap))), Done{x}, IP.inflate_fast(cap, D.deflate(x, 0n)),
    round_trip(x, cap, D.tabs(), vx, fits))

# The code tables, closed: each side computed
def Laws.length_codes():
  ({==}, {==})

def Laws.dist_codes():
  ({==}, {==})

def Laws.tables_written():
  ({==}, {==}, {==}, {==}, {==}, {==}, {==}, {==})

# The codes and the fixed tables, closed
def Laws.canonical():
  ({==}, {==}, {==})

def Laws.fixed_tables():
  ({==}, {==})

# The cap
# =======
#
# The machine never writes past its cap: n, the bytes written, stays at
# most cap, and the output (the bytes not yet taken and the window) at
# most n. Each step either keeps its output or goes through emit or
# copy, which check the cap first. sok is the invariant; each lemma below
# follows one function of the machine's step to where it builds a St.

def inv(+cc: Nat, o: D.O) -> Bool:
  match o:
    case D.O{out, keep, +n, +cap, t}:
      Nat.is_le(bl(out), n) && (Nat.is_le(n, cap) && Nat.is_le(cap, cc))

def sok(+cc: Nat, st: D.St) -> Bool:
  match st:
    case D.St{m, o, bp}:
      inv(cc, o)

def and_tt(+a: Bool, +b: Bool, ea: {a == True{} : Bool}, eb: {b == True{} : Bool}) ->
  {Bool.and(a, b) == True{} : Bool}:
  %Equal.sym(Bool, a, True{}, ea) : {Bool.and(_, b) == True{} : Bool}
  eb

def add_comm(+a: Nat, +b: Nat) -> {Nat.add(a, b) == Nat.add(b, a) : Nat}:
  match a:
    case 0n:
      Equal.sym(Nat, Nat.add(b, 0n), b, add_zero(b))
    case 1n+p:
      Equal.trans(Nat, 1n+Nat.add(p, b), 1n+Nat.add(b, p), Nat.add(b, 1n+p),
        Equal.cong(Nat, Nat, x => 1n+x, Nat.add(p, b), Nat.add(b, p), add_comm(p, b)),
        Equal.sym(Nat, Nat.add(b, 1n+p), 1n+Nat.add(b, p), add_succ(b, p)))

def le0(+d: Nat) -> {Nat.is_le(0n, d) == True{} : Bool}:
  match d:
    case 0n:
      {==}
    case 1n+p:
      {==}

def lt_le(+x: Nat, +c: Nat) -> {Nat.is_lt(x, c) == True{} : Bool} -> {Nat.is_le(1n+x, c) == True{} : Bool}:
  match x c:
    case 0n 0n:
      e => Bool.no({Nat.is_le(1n, 0n) == True{} : Bool}, e)
    case 0n 1n+d:
      e => le0(d)
    case 1n+p 0n:
      e => Bool.no({Nat.is_le(2n+p, 0n) == True{} : Bool}, e)
    case 1n+p 1n+d:
      e => lt_le(p, d)(e)

def le_add(+k: Nat, +a: Nat, +b: Nat) -> {Nat.is_le(a, b) == True{} : Bool} ->
  {Nat.is_le(Nat.add(k, a), Nat.add(k, b)) == True{} : Bool}:
  match k:
    case 0n:
      e => e
    case 1n+p:
      e => le_add(p, a, b)(e)

def bl_copy(+len: Nat, +out: Bytes(), +dist: Nat) -> {bl(D.copy.go(len, out, dist)) == Nat.add(len, bl(out)) : Nat}:
  match len:
    case 0n:
      {==}
    case 1n+p:
      +c = Bytes.get(out, Nat.sub(Bytes.len(out), dist))
      Equal.trans(Nat, bl(D.copy.go(p, Bytes.push(out, c), dist)), Nat.add(p, bl(Bytes.push(out, c))),
        1n+Nat.add(p, bl(out)), bl_copy(p, Bytes.push(out, c), dist),
        Equal.trans(Nat, Nat.add(p, bl(Bytes.push(out, c))), Nat.add(p, 1n+bl(out)), 1n+Nat.add(p, bl(out)),
          Equal.cong(Nat, Nat, y => Nat.add(p, y), bl(Bytes.push(out, c)), 1n+bl(out), bl_push(out, c)),
          add_succ(p, bl(out))))

# The writes
# ----------

def cap.emit.if(+ok: Bool, +out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +t: D.Tabs, +c: U32, +next: D.Mode,
  +bp: Nat, +cc: Nat, e: {ok == Nat.is_lt(n, cap) : Bool}, +h: {inv(cc, D.O{out, keep, n, cap, t}) == True{} : Bool}) ->
  {sok(cc, D.emit.if(ok, out, keep, n, cap, t, c, next, bp)) == True{} : Bool}:
  match ok:
    case True{}:
      +h2 = Bool.and_r(Nat.is_le(bl(out), n), Nat.is_le(n, cap) && Nat.is_le(cap, cc), h)
      %Equal.sym(Nat, bl(Bytes.push(out, c)), 1n+bl(out), bl_push(out, c)) :
        {Bool.and(Nat.is_le(_, 1n+n), Nat.is_le(1n+n, cap) && Nat.is_le(cap, cc)) == True{} : Bool}
      and_tt(Nat.is_le(bl(out), n), Nat.is_le(1n+n, cap) && Nat.is_le(cap, cc),
        Bool.and_l(Nat.is_le(bl(out), n), Nat.is_le(n, cap) && Nat.is_le(cap, cc), h),
        and_tt(Nat.is_le(1n+n, cap), Nat.is_le(cap, cc), lt_le(n, cap)(Equal.sym(Bool, True{}, Nat.is_lt(n, cap), e)),
          Bool.and_r(Nat.is_le(n, cap), Nat.is_le(cap, cc), h2)))
    case False{}:
      h

def cap.emit(+o: D.O, +c: U32, +next: D.Mode, +bp: Nat, +cc: Nat, +h: {inv(cc, o) == True{} : Bool}) ->
  {sok(cc, D.emit(o, c, next, bp)) == True{} : Bool}:
  match o:
    case D.O{+out, +keep, +n, +cap, +t}:
      cap.emit.if(Nat.is_lt(n, cap), out, keep, n, cap, t, c, next, bp, cc, {==}, h)

def cap.copy.big(+big: Bool, +out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +t: D.Tabs, +len: Nat, +dist: Nat,
  +next: D.Mode, +bp: Nat, +cc: Nat, e: {big == Nat.is_lt(cap, Nat.add(n, len)) : Bool},
  +h: {inv(cc, D.O{out, keep, n, cap, t}) == True{} : Bool}) ->
  {sok(cc, D.copy.big(big, out, keep, n, cap, t, len, dist, next, bp)) == True{} : Bool}:
  match big:
    case True{}:
      h
    case False{}:
      +h2 = Bool.and_r(Nat.is_le(bl(out), n), Nat.is_le(n, cap) && Nat.is_le(cap, cc), h)
      +le1 = Equal.trans(Bool, Nat.is_le(bl(D.copy.go(len, out, dist)), Nat.add(n, len)),
        Nat.is_le(Nat.add(len, bl(out)), Nat.add(len, n)), True{},
        Equal.trans(Bool, Nat.is_le(bl(D.copy.go(len, out, dist)), Nat.add(n, len)),
          Nat.is_le(Nat.add(len, bl(out)), Nat.add(n, len)), Nat.is_le(Nat.add(len, bl(out)), Nat.add(len, n)),
          Equal.cong(Nat, Bool, y => Nat.is_le(y, Nat.add(n, len)), bl(D.copy.go(len, out, dist)),
            Nat.add(len, bl(out)), bl_copy(len, out, dist)),
          Equal.cong(Nat, Bool, y => Nat.is_le(Nat.add(len, bl(out)), y), Nat.add(n, len), Nat.add(len, n),
            add_comm(n, len))),
        le_add(len, bl(out), n)(Bool.and_l(Nat.is_le(bl(out), n), Nat.is_le(n, cap) && Nat.is_le(cap, cc), h)))
      +le2 = Equal.trans(Bool, Nat.is_le(Nat.add(n, len), cap), Bool.not(Nat.is_lt(cap, Nat.add(n, len))), True{},
        Equal.sym(Bool, Bool.not(Nat.is_lt(cap, Nat.add(n, len))), Nat.is_le(Nat.add(n, len), cap),
          Nat.lt_flip(cap, Nat.add(n, len))),
        Equal.cong(Bool, Bool, Bool.not, Nat.is_lt(cap, Nat.add(n, len)), False{},
          Equal.sym(Bool, False{}, Nat.is_lt(cap, Nat.add(n, len)), e)))
      and_tt(Nat.is_le(bl(D.copy.go(len, out, dist)), Nat.add(n, len)),
        Nat.is_le(Nat.add(n, len), cap) && Nat.is_le(cap, cc), le1,
        and_tt(Nat.is_le(Nat.add(n, len), cap), Nat.is_le(cap, cc), le2,
          Bool.and_r(Nat.is_le(n, cap), Nat.is_le(cap, cc), h2)))

def cap.copy.if(+far: Bool, +big: Bool, +out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +t: D.Tabs, +len: Nat,
  +dist: Nat, +next: D.Mode, +bp: Nat, +cc: Nat, e: {big == Nat.is_lt(cap, Nat.add(n, len)) : Bool},
  +h: {inv(cc, D.O{out, keep, n, cap, t}) == True{} : Bool}) ->
  {sok(cc, D.copy.if(far, big, out, keep, n, cap, t, len, dist, next, bp)) == True{} : Bool}:
  match far:
    case True{}:
      h
    case False{}:
      cap.copy.big(big, out, keep, n, cap, t, len, dist, next, bp, cc, e, h)

def cap.copy(+o: D.O, +len: Nat, +dist: Nat, +next: D.Mode, +bp: Nat, +cc: Nat, +h: {inv(cc, o) == True{} : Bool}) ->
  {sok(cc, D.copy(o, len, dist, next, bp)) == True{} : Bool}:
  match o:
    case D.O{+out, +keep, +n, +cap, +t}:
      cap.copy.if(Nat.is_lt(Bytes.len(out), dist), Nat.is_lt(cap, Nat.add(n, len)), out, keep, n, cap, t, len,
        dist, next, bp, cc, {==}, h)

# The step
# --------

def cap.next_block(+last: Bool, +o: D.O, +bp: Nat, +cc: Nat, +h: {inv(cc, o) == True{} : Bool}) ->
  {sok(cc, D.next_block(last, o, bp)) == True{} : Bool}:
  match last:
    case True{}:
      h
    case False{}:
      h

def cap.stored_head(+last: Bool, +aligned: Bool, +o: D.O, +bp: Nat, +cc: Nat, +h: {inv(cc, o) == True{} : Bool}) ->
  {sok(cc, D.stored_head(last, aligned, o, bp)) == True{} : Bool}:
  match aligned:
    case True{}:
      h
    case False{}:
      h

def cap.fixed(+last: Bool, +o: D.O, +bp: Nat, +cc: Nat, +h: {inv(cc, o) == True{} : Bool}) ->
  {sok(cc, D.fixed(last, o, bp)) == True{} : Bool}:
  match o:
    case D.O{+out, +keep, +n, +cap, +t}:
      match t:
        case D.Tabs{+fll, +fd, +lb, +lx, +db, +dx}:
          h

def cap.block(+last: Bool, +b1: Bool, +b2: Bool, +o: D.O, +bp: Nat, +cc: Nat, +h: {inv(cc, o) == True{} : Bool}) ->
  {sok(cc, D.block(last, b1, b2, o, bp)) == True{} : Bool}:
  match b1 b2:
    case False{} False{}:
      cap.stored_head(last, Nat.is_eq(bp, 0n), o, bp, cc, h)
    case True{} False{}:
      cap.fixed(last, o, bp, cc, h)
    case False{} True{}:
      h
    case True{} True{}:
      h

def cap.head(+acc: List<&2, Bool>, +o: D.O, +bp: Nat, +cc: Nat, +h: {inv(cc, o) == True{} : Bool}) ->
  {sok(cc, D.head(acc, o, bp)) == True{} : Bool}:
  match acc:
    case Nil{}:
      h
    case Con{+b2, +t2}:
      match t2:
        case Nil{}:
          h
        case Con{+b1, +t1}:
          match t1:
            case Nil{}:
              h
            case Con{+last, +t0}:
              match t0:
                case Nil{}:
                  cap.block(last, b1, b2, o, bp, cc, h)
                case Con{+x, +r}:
                  h

def cap.stored_body(+last: Bool, +len: Nat, +o: D.O, +bp: Nat, +cc: Nat, +h: {inv(cc, o) == True{} : Bool}) ->
  {sok(cc, D.stored_body(last, len, o, bp)) == True{} : Bool}:
  match len:
    case 0n:
      cap.next_block(last, o, bp, cc, h)
    case 1n+p:
      h

def cap.stored_nlen(+okb: Bool, +last: Bool, +len: Nat, +o: D.O, +bp: Nat, +cc: Nat,
  +h: {inv(cc, o) == True{} : Bool}) -> {sok(cc, D.stored_nlen(okb, last, len, o, bp)) == True{} : Bool}:
  match okb:
    case True{}:
      cap.stored_body(last, len, o, bp, cc, h)
    case False{}:
      h

def cap.stored_byte(+last: Bool, +left: Nat, +c: U32, +o: D.O, +bp: Nat, +cc: Nat,
  +h: {inv(cc, o) == True{} : Bool}) -> {sok(cc, D.stored_byte(last, left, c, o, bp)) == True{} : Bool}:
  match last left:
    case True{} 0n:
      cap.emit(o, c, D.End{}, bp, cc, h)
    case False{} 0n:
      cap.emit(o, c, D.Get{2n, Nil{}, D.KHead{}}, bp, cc, h)
    case True{} 1n+p:
      cap.emit(o, c, D.Get{7n, Nil{}, D.KByte{True{}, p}}, bp, cc, h)
    case False{} 1n+p:
      cap.emit(o, c, D.Get{7n, Nil{}, D.KByte{False{}, p}}, bp, cc, h)

def cap.dyn_end.tabs(+last: Bool, +ml: Maybe<&2, String>, +md: Maybe<&2, String>, +o: D.O, +bp: Nat, +cc: Nat,
  +h: {inv(cc, o) == True{} : Bool}) -> {sok(cc, D.dyn_end.tabs(last, ml, md, o, bp)) == True{} : Bool}:
  match ml:
    case None{}:
      h
    case Some{+ll}:
      match md:
        case None{}:
          h
        case Some{+d}:
          h

def cap.dyn_end.at(+noend: Bool, +last: Bool, +ll: List<&2, Nat>, +d: List<&2, Nat>, +o: D.O, +bp: Nat, +cc: Nat,
  +h: {inv(cc, o) == True{} : Bool}) -> {sok(cc, D.dyn_end.at(noend, last, ll, d, o, bp)) == True{} : Bool}:
  match noend:
    case True{}:
      h
    case False{}:
      cap.dyn_end.tabs(last, D.table(ll, False{}), D.table(d, False{}), o, bp, cc, h)

def cap.dyn_next(+hd: D.Dyn, +o: D.O, +bp: Nat, +cc: Nat, +h: {inv(cc, o) == True{} : Bool}) ->
  {sok(cc, D.dyn_next(hd, o, bp)) == True{} : Bool}:
  match hd:
    case D.Dyn{+last, +nlit, +ndist, +left, +lens, +cl}:
      match left:
        case 0n:
          +all = List.reverse(&2, Nat, lens)
          +ll = List.take(&2, Nat, all, nlit)
          cap.dyn_end.at(Nat.is_eq(D.nth(ll, 256n), 0n), last, ll, List.drop(&2, Nat, all, nlit), o, bp, cc, h)
        case 1n+p:
          h

def cap.cl_done(+last: Bool, +nlit: Nat, +ndist: Nat, +m: Maybe<&2, String>, +o: D.O, +bp: Nat, +cc: Nat,
  +h: {inv(cc, o) == True{} : Bool}) -> {sok(cc, D.cl_done(last, nlit, ndist, m, o, bp)) == True{} : Bool}:
  match m:
    case None{}:
      h
    case Some{+t}:
      cap.dyn_next(D.Dyn{last, nlit, ndist, Nat.add(nlit, ndist), Nil{}, t}, o, bp, cc, h)

def cap.rep.if(+over: Bool, +last: Bool, +nlit: Nat, +ndist: Nat, +left: Nat, +lens: List<&2, Nat>, +cl: String,
  +count: Nat, +v: Nat, +o: D.O, +bp: Nat, +cc: Nat, +h: {inv(cc, o) == True{} : Bool}) ->
  {sok(cc, D.rep.if(over, last, nlit, ndist, left, lens, cl, count, v, o, bp)) == True{} : Bool}:
  match over:
    case True{}:
      h
    case False{}:
      cap.dyn_next(D.Dyn{last, nlit, ndist, Nat.sub(left, count), D.rep_n(count, v, lens), cl}, o, bp, cc, h)

def cap.rep(+hd: D.Dyn, +count: Nat, +v: Nat, +o: D.O, +bp: Nat, +cc: Nat, +h: {inv(cc, o) == True{} : Bool}) ->
  {sok(cc, D.rep(hd, count, v, o, bp)) == True{} : Bool}:
  match hd:
    case D.Dyn{+last, +nlit, +ndist, +left, +lens, +cl}:
      cap.rep.if(Nat.is_lt(left, count), last, nlit, ndist, left, lens, cl, count, v, o, bp, cc, h)

def cap.hclen.if(+okb: Bool, +last: Bool, +nlit: Nat, +ndist: Nat, +ncl: Nat, +o: D.O, +bp: Nat, +cc: Nat,
  +h: {inv(cc, o) == True{} : Bool}) -> {sok(cc, D.hclen.if(okb, last, nlit, ndist, ncl, o, bp)) == True{} : Bool}:
  match okb:
    case True{}:
      h
    case False{}:
      h

def cap.cl_got(+last: Bool, +nlit: Nat, +ndist: Nat, +left: Nat, +got: List<&2, Nat>, +o: D.O, +bp: Nat, +cc: Nat,
  +h: {inv(cc, o) == True{} : Bool}) -> {sok(cc, D.cl_got(last, nlit, ndist, left, got, o, bp)) == True{} : Bool}:
  match left:
    case 0n:
      cap.cl_done(last, nlit, ndist, D.table(D.cl_lens(19n, List.reverse(&2, Nat, got), 0n), True{}), o, bp, cc, h)
    case 1n+p:
      h

def cap.len_x(+blk: D.Blk, +base: Nat, +x: Nat, +o: D.O, +bp: Nat, +cc: Nat, +h: {inv(cc, o) == True{} : Bool}) ->
  {sok(cc, D.len_x(blk, base, x, o, bp)) == True{} : Bool}:
  match x:
    case 0n:
      h
    case 1n+p:
      h

def cap.len_code(+blk: D.Blk, +i: Nat, +o: D.O, +bp: Nat, +cc: Nat, +h: {inv(cc, o) == True{} : Bool}) ->
  {sok(cc, D.len_code(blk, i, o, bp)) == True{} : Bool}:
  match o:
    case D.O{+out, +keep, +n, +cap, +t}:
      match t:
        case D.Tabs{+fll, +fd, +lb, +lx, +db, +dx}:
          cap.len_x(blk, U32.to_nat(Bytes.get(lb, i)), U32.to_nat(Bytes.get(lx, i)),
            D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}, bp, cc, h)

def cap.lit.c(+okb: Bool, +blk: D.Blk, +i: Nat, +o: D.O, +bp: Nat, +cc: Nat, +h: {inv(cc, o) == True{} : Bool}) ->
  {sok(cc, D.lit.c(okb, blk, i, o, bp)) == True{} : Bool}:
  match okb:
    case True{}:
      cap.len_code(blk, i, o, bp, cc, h)
    case False{}:
      h

def cap.lit.b(+eob: Bool, +blk: D.Blk, +s: Nat, +o: D.O, +bp: Nat, +cc: Nat, +h: {inv(cc, o) == True{} : Bool}) ->
  {sok(cc, D.lit.b(eob, blk, s, o, bp)) == True{} : Bool}:
  match eob:
    case True{}:
      cap.next_block(D.blk_last(blk), o, bp, cc, h)
    case False{}:
      cap.lit.c(Nat.is_lt(s, U32.to_nat(286)), blk, Nat.sub(s, U32.to_nat(257)), o, bp, cc, h)

def cap.lit(+is_lit: Bool, +blk: D.Blk, +s: Nat, +o: D.O, +bp: Nat, +cc: Nat, +h: {inv(cc, o) == True{} : Bool}) ->
  {sok(cc, D.lit(is_lit, blk, s, o, bp)) == True{} : Bool}:
  match is_lit:
    case True{}:
      cap.emit(o, U32.from_nat(s), D.lit_mode(blk), bp, cc, h)
    case False{}:
      cap.lit.b(Nat.is_eq(s, 256n), blk, s, o, bp, cc, h)

def cap.dist_x(+blk: D.Blk, +len: Nat, +base: Nat, +x: Nat, +o: D.O, +bp: Nat, +cc: Nat,
  +h: {inv(cc, o) == True{} : Bool}) -> {sok(cc, D.dist_x(blk, len, base, x, o, bp)) == True{} : Bool}:
  match x:
    case 0n:
      cap.copy(o, len, base, D.lit_mode(blk), bp, cc, h)
    case 1n+p:
      h

def cap.dist_code(+blk: D.Blk, +len: Nat, +s: Nat, +o: D.O, +bp: Nat, +cc: Nat, +h: {inv(cc, o) == True{} : Bool}) ->
  {sok(cc, D.dist_code(blk, len, s, o, bp)) == True{} : Bool}:
  match o:
    case D.O{+out, +keep, +n, +cap, +t}:
      match t:
        case D.Tabs{+fll, +fd, +lb, +lx, +db, +dx}:
          cap.dist_x(blk, len, U32.to_nat(Bytes.get(db, s)), U32.to_nat(Bytes.get(dx, s)),
            D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}, bp, cc, h)

def cap.dist(+okb: Bool, +blk: D.Blk, +len: Nat, +s: Nat, +o: D.O, +bp: Nat, +cc: Nat,
  +h: {inv(cc, o) == True{} : Bool}) -> {sok(cc, D.dist(okb, blk, len, s, o, bp)) == True{} : Bool}:
  match okb:
    case True{}:
      cap.dist_code(blk, len, s, o, bp, cc, h)
    case False{}:
      h

def cap.cl_len(+hd: D.Dyn, +s: Nat, +o: D.O, +bp: Nat, +cc: Nat, +h: {inv(cc, o) == True{} : Bool}) ->
  {sok(cc, D.cl_len(hd, s, o, bp)) == True{} : Bool}:
  match hd:
    case D.Dyn{+last, +nlit, +ndist, +left, +lens, +cl}:
      cap.dyn_next(D.Dyn{last, nlit, ndist, Nat.sub(left, 1n), Con{s, lens}, cl}, o, bp, cc, h)

def cap.cl_16(+hd: D.Dyn, +o: D.O, +bp: Nat, +cc: Nat, +h: {inv(cc, o) == True{} : Bool}) ->
  {sok(cc, D.cl_16(hd, o, bp)) == True{} : Bool}:
  match hd:
    case D.Dyn{+last, +nlit, +ndist, +left, +lens, +cl}:
      match lens:
        case Nil{}:
          h
        case Con{+v, +t}:
          h

def cap.clsym(+hd: D.Dyn, +s: Nat, +o: D.O, +bp: Nat, +cc: Nat, +h: {inv(cc, o) == True{} : Bool}) ->
  {sok(cc, D.clsym(hd, s, o, bp)) == True{} : Bool}:
  match s:
    case 0n:
      cap.cl_len(hd, 0n, o, bp, cc, h)
    case 1n:
      cap.cl_len(hd, 1n, o, bp, cc, h)
    case 2n:
      cap.cl_len(hd, 2n, o, bp, cc, h)
    case 3n:
      cap.cl_len(hd, 3n, o, bp, cc, h)
    case 4n:
      cap.cl_len(hd, 4n, o, bp, cc, h)
    case 5n:
      cap.cl_len(hd, 5n, o, bp, cc, h)
    case 6n:
      cap.cl_len(hd, 6n, o, bp, cc, h)
    case 7n:
      cap.cl_len(hd, 7n, o, bp, cc, h)
    case 8n:
      cap.cl_len(hd, 8n, o, bp, cc, h)
    case 9n:
      cap.cl_len(hd, 9n, o, bp, cc, h)
    case 10n:
      cap.cl_len(hd, 10n, o, bp, cc, h)
    case 11n:
      cap.cl_len(hd, 11n, o, bp, cc, h)
    case 12n:
      cap.cl_len(hd, 12n, o, bp, cc, h)
    case 13n:
      cap.cl_len(hd, 13n, o, bp, cc, h)
    case 14n:
      cap.cl_len(hd, 14n, o, bp, cc, h)
    case 15n:
      cap.cl_len(hd, 15n, o, bp, cc, h)
    case 16n:
      cap.cl_16(hd, o, bp, cc, h)
    case 17n:
      h
    case 18n:
      h
    case 19n+q:
      cap.cl_len(hd, 19n+q, o, bp, cc, h)

def cap.sym(+k: D.SK, +s: Nat, +o: D.O, +bp: Nat, +cc: Nat, +h: {inv(cc, o) == True{} : Bool}) ->
  {sok(cc, D.sym(k, s, o, bp)) == True{} : Bool}:
  match k:
    case D.SLit{+blk}:
      cap.lit(Nat.is_lt(s, 256n), blk, s, o, bp, cc, h)
    case D.SDist{+blk, +len}:
      cap.dist(Nat.is_lt(s, 30n), blk, len, s, o, bp, cc, h)
    case D.SCl{+hd}:
      cap.clsym(hd, s, o, bp, cc, h)

def cap.walk.lr(+tab: String, +q: Nat, +leaf: Bool, +k: D.SK, +o: D.O, +bp: Nat, +cc: Nat,
  +h: {inv(cc, o) == True{} : Bool}) -> {sok(cc, D.walk.lr(tab, q, leaf, k, o, bp)) == True{} : Bool}:
  match leaf:
    case True{}:
      cap.sym(k, q, o, bp, cc, h)
    case False{}:
      h

def cap.walk.at(+tab: String, +zero: Bool, qr: Nat & Nat, +k: D.SK, +o: D.O, +bp: Nat, +cc: Nat,
  +h: {inv(cc, o) == True{} : Bool}) -> {sok(cc, D.walk.at(tab, zero, qr, k, o, bp)) == True{} : Bool}:
  match zero:
    case True{}:
      h
    case False{}:
      match qr:
        case (+q, +r):
          cap.walk.lr(tab, q, Nat.is_eq(r, 1n), k, o, bp, cc, h)

def cap.walk(+tab: String, +x: Nat, +k: D.SK, +o: D.O, +bp: Nat, +cc: Nat, +h: {inv(cc, o) == True{} : Bool}) ->
  {sok(cc, D.walk(tab, x, k, o, bp)) == True{} : Bool}:
  cap.walk.at(tab, Nat.is_eq(x, 0n), Nat.divmod(x, 2n), k, o, bp, cc, h)

def cap.fire(+k: D.K, +acc: List<&2, Bool>, +o: D.O, +bp: Nat, +cc: Nat, +h: {inv(cc, o) == True{} : Bool}) ->
  {sok(cc, D.fire(k, acc, o, bp)) == True{} : Bool}:
  match k:
    case D.KHead{}:
      cap.head(acc, o, bp, cc, h)
    case D.KLen{+last}:
      h
    case D.KNLen{+last, +len}:
      cap.stored_nlen(D.compl(len, acc), last, D.hval(len, 0n), o, bp, cc, h)
    case D.KByte{+last, +left}:
      cap.stored_byte(last, left, U32.from_nat(D.hval(acc, 0n)), o, bp, cc, h)
    case D.KLenX{+blk, +base}:
      h
    case D.KDistX{+blk, +len, +base}:
      cap.copy(o, len, Nat.add(base, D.hval(acc, 0n)), D.lit_mode(blk), bp, cc, h)
    case D.KHlit{+last}:
      h
    case D.KHdist{+last, +nlit}:
      h
    case D.KHclen{+last, +nlit, +ndist}:
      cap.hclen.if(D.counts_ok(nlit, ndist), last, nlit, ndist, Nat.add(3n, D.hval(acc, 0n)), o, bp, cc, h)
    case D.KCl{+last, +nlit, +ndist, +left, +got}:
      cap.cl_got(last, nlit, ndist, left, Con{D.hval(acc, 0n), got}, o, bp, cc, h)
    case D.KRep{+hd, +base, +v}:
      cap.rep(hd, Nat.add(base, D.hval(acc, 0n)), v, o, bp, cc, h)

def cap.mode(+m: D.Mode, +b: Bool, +o: D.O, +bp: Nat, +cc: Nat, +h: {inv(cc, o) == True{} : Bool}) ->
  {sok(cc, D.mode(m, b, o, bp)) == True{} : Bool}:
  match m:
    case D.Get{+left, +acc, +k}:
      match left:
        case 0n:
          cap.fire(k, Con{b, acc}, o, bp, cc, h)
        case 1n+p:
          h
    case D.Walk{+node, +tab, +k}:
      cap.walk(tab, U32.to_nat(Bytes.get(tab, Nat.add(Nat.double(node), Nat.bit(b, 0n)))), k, o, bp, cc, h)
    case D.Skip{+last}:
      cap.stored_head(last, Nat.is_eq(bp, 0n), o, bp, cc, h)
    case D.End{}:
      h
    case D.Bad{+why}:
      h

def cap.bstep(+st: D.St, +b: Bool, +cc: Nat, +h: {sok(cc, st) == True{} : Bool}) ->
  {sok(cc, D.bstep(st, b)) == True{} : Bool}:
  match st:
    case D.St{+m, +o, +bp}:
      cap.mode(m, b, o, D.next_bp(bp), cc, h)

def cap.step(+st: D.St, +c: U32, +cc: Nat, +h: {sok(cc, st) == True{} : Bool}) ->
  {sok(cc, D.step(st, c)) == True{} : Bool}:
  +s1 = D.bstep(st, D.bit(c, 0n))
  +s2 = D.bstep(s1, D.bit(c, 1n))
  +s3 = D.bstep(s2, D.bit(c, 2n))
  +s4 = D.bstep(s3, D.bit(c, 3n))
  +s5 = D.bstep(s4, D.bit(c, 4n))
  +s6 = D.bstep(s5, D.bit(c, 5n))
  +s7 = D.bstep(s6, D.bit(c, 6n))
  cap.bstep(s7, D.bit(c, 7n), cc, cap.bstep(s6, D.bit(c, 6n), cc, cap.bstep(s5, D.bit(c, 5n), cc,
    cap.bstep(s4, D.bit(c, 4n), cc, cap.bstep(s3, D.bit(c, 3n), cc, cap.bstep(s2, D.bit(c, 2n), cc,
    cap.bstep(s1, D.bit(c, 1n), cc, cap.bstep(st, D.bit(c, 0n), cc, h))))))))

def cap.feed(+bs: List<&2, U32>, +st: D.St, +cc: Nat, +h: {sok(cc, st) == True{} : Bool}) ->
  {sok(cc, D.feed_list(bs, st)) == True{} : Bool}:
  match bs:
    case Nil{}:
      h
    case Con{+c, +t}:
      cap.feed(t, D.step(st, c), cc, cap.step(st, c, cc, h))

# The ends
# --------

def le_refl(+a: Nat) -> {Nat.is_le(a, a) == True{} : Bool}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      le_refl(p)

def le_succ(+a: Nat, +b: Nat) -> {Nat.is_le(a, b) == True{} : Bool} -> {Nat.is_le(a, 1n+b) == True{} : Bool}:
  match a b:
    case 0n _:
      e => {==}
    case 1n+p 0n:
      e => Bool.no({Nat.is_le(1n+p, 1n) == True{} : Bool}, e)
    case 1n+p 1n+q:
      e => le_succ(p, q)(e)

# a drop is no longer than what it drops from
def drop_le(+s: Bytes(), +k: Nat) -> {Nat.is_le(bl(Bytes.drop(s, k)), bl(s)) == True{} : Bool}:
  match s k:
    case SNil{} _:
      {==}
    case SCon{+h, +t} 0n:
      le_refl(1n+bl(t))
    case SCon{+h, +t} 1n+p:
      le_succ(bl(Bytes.drop(t, p)), bl(t))(drop_le(t, p))

# the machine at the start holds the invariant
def cap.new(+cap: Nat, +tb: D.Tabs) -> {sok(cap, D.St{D.Get{2n, Nil{}, D.KHead{}}, D.O{"", 0n, 0n, cap, tb}, 0n}) == True{} : Bool}:
  %Equal.sym(Bool, Nat.is_le(0n, cap), True{}, le0(cap)) :
    {Bool.and(True{}, Bool.and(_, Nat.is_le(cap, cap))) == True{} : Bool}
  le_refl(cap)

def cap.written(+st: D.St, +cc: Nat, +h: {sok(cc, st) == True{} : Bool}) ->
  {Nat.is_le(D.written(st), cc) == True{} : Bool}:
  match st:
    case D.St{+m, +o, +bp}:
      match o:
        case D.O{+out, +keep, +n, +capf, +t}:
          +h2 = Bool.and_r(Nat.is_le(bl(out), n), Nat.is_le(n, capf) && Nat.is_le(capf, cc), h)
          Nat.is_le_trans(n, capf, cc, Bool.and_l(Nat.is_le(n, capf), Nat.is_le(capf, cc), h2),
            Bool.and_r(Nat.is_le(n, capf), Nat.is_le(capf, cc), h2))

def is_done(r: Result<&2, &2, D.Why, Bytes()>) -> Bool:
  match r:
    case Fail{w}:
      False{}
    case Done{x}:
      True{}

def done_of(r: Result<&2, &2, D.Why, Bytes()>) -> Bytes():
  match r:
    case Fail{w}:
      ""
    case Done{x}:
      x

def not_done(-g: Type, +w: D.Why, +y: Bytes(),
  e: {Fail{w} == Done{y} : Result<&2, &2, D.Why, Bytes()>}) -> g:
  Bool.no(g, Equal.cong(Result<&2, &2, D.Why, Bytes()>, Bool, is_done, Fail{w}, Done{y}, e))

# what the machine hands out at its end is at most cc bytes
def cap.finish(+st: D.St, +cc: Nat, +y: Bytes(), +h: {sok(cc, st) == True{} : Bool},
  e: {D.finish(st) == Done{y} : Result<&2, &2, D.Why, Bytes()>}) -> {Nat.is_le(bl(y), cc) == True{} : Bool}:
  match st:
    case D.St{+m, +o, +bp}:
      match m o:
        case D.End{} D.O{+out, +keep, +n, +capf, +t}:
          +h2 = Bool.and_r(Nat.is_le(bl(out), n), Nat.is_le(n, capf) && Nat.is_le(capf, cc), h)
          +ey = Equal.cong(Result<&2, &2, D.Why, Bytes()>, Bytes(), done_of, Done{Bytes.drop(out, keep)}, Done{y}, e)
          %ey : {Nat.is_le(bl(_), cc) == True{} : Bool}
          Nat.is_le_trans(bl(Bytes.drop(out, keep)), bl(out), cc, drop_le(out, keep),
            Nat.is_le_trans(bl(out), n, cc, Bool.and_l(Nat.is_le(bl(out), n), Nat.is_le(n, capf) && Nat.is_le(capf, cc), h),
              Nat.is_le_trans(n, capf, cc, Bool.and_l(Nat.is_le(n, capf), Nat.is_le(capf, cc), h2),
                Bool.and_r(Nat.is_le(n, capf), Nat.is_le(capf, cc), h2))))
        case D.Get{+left, +acc, +k} +o2:
          not_done({Nat.is_le(bl(y), cc) == True{} : Bool}, D.Truncated{}, y, e)
        case D.Walk{+node, +tab, +k} +o2:
          not_done({Nat.is_le(bl(y), cc) == True{} : Bool}, D.Truncated{}, y, e)
        case D.Skip{+last} +o2:
          not_done({Nat.is_le(bl(y), cc) == True{} : Bool}, D.Truncated{}, y, e)
        case D.Bad{+why} +o2:
          not_done({Nat.is_le(bl(y), cc) == True{} : Bool}, why, y, e)

# The window
# ==========

def lt_succ_r(+i: Nat, +b: Nat) -> {Nat.is_lt(i, b) == True{} : Bool} -> {Nat.is_lt(i, 1n+b) == True{} : Bool}:
  match i b:
    case 0n _:
      e => {==}
    case 1n+p 0n:
      e => Bool.no({Nat.is_lt(1n+p, 1n) == True{} : Bool}, e)
    case 1n+p 1n+q:
      e => lt_succ_r(p, q)(e)

def nsub_le(+b: Nat, +d: Nat) -> {Nat.is_le(Nat.sub(b, d), b) == True{} : Bool}:
  match b d:
    case 0n 0n:
      {==}
    case 0n 1n+q:
      {==}
    case 1n+p 0n:
      le_refl(1n+p)
    case 1n+p 1n+q:
      le_succ(Nat.sub(p, q), p)(nsub_le(p, q))

def le_lt_succ(+a: Nat, +b: Nat) -> {Nat.is_le(a, b) == True{} : Bool} -> {Nat.is_lt(a, 1n+b) == True{} : Bool}:
  match a b:
    case 0n _:
      e => {==}
    case 1n+p 0n:
      e => Bool.no({Nat.is_lt(1n+p, 1n) == True{} : Bool}, e)
    case 1n+p 1n+q:
      e => le_lt_succ(p, q)(e)

# a distance of at least 1 within b: its byte is before b
def lt_sub(+d: Nat, +b: Nat, d1: {Nat.is_lt(0n, d) == True{} : Bool}, dle: {Nat.is_le(d, b) == True{} : Bool}) ->
  {Nat.is_lt(Nat.sub(b, d), b) == True{} : Bool}:
  match d b:
    case 0n _:
      Bool.no({Nat.is_lt(Nat.sub(b, 0n), b) == True{} : Bool}, d1)
    case 1n+p 0n:
      Bool.no({Nat.is_lt(Nat.sub(0n, 1n+p), 0n) == True{} : Bool}, dle)
    case 1n+p 1n+q:
      le_lt_succ(Nat.sub(q, p), q)(nsub_le(q, p))

def get_app_lt(+a: Bytes(), +b: Bytes(), +i: Nat, lt: {Nat.is_lt(i, bl(a)) == True{} : Bool}) ->
  {String.get(String.append(a, b), i) == String.get(a, i) : Maybe<&2, Char>}:
  match a i:
    case SNil{} _:
      Nat.lt_zero({String.get(String.append(SNil{}, b), i) == String.get(SNil{}, i) : Maybe<&2, Char>}, i, lt)
    case SCon{+h, +t} 0n:
      {==}
    case SCon{+h, +t} 1n+p:
      get_app_lt(t, b, p, lt)

def get_app_len(+a: Bytes(), +b: Bytes()) -> {String.get(String.append(a, b), bl(a)) == String.get(b, 0n) : Maybe<&2, Char>}:
  match a:
    case SNil{}:
      {==}
    case SCon{+h, +t}:
      get_app_len(t, b)

# a copy only appends: what was there reads the same
def copy_prefix(+len: Nat, +out: Bytes(), +d: Nat, +i: Nat, +lt: {Nat.is_lt(i, bl(out)) == True{} : Bool}) ->
  {String.get(D.copy.go(len, out, d), i) == String.get(out, i) : Maybe<&2, Char>}:
  match len:
    case 0n:
      {==}
    case 1n+p:
      +c = Bytes.get(out, Nat.sub(Bytes.len(out), d))
      +lt2 = Equal.trans(Bool, Nat.is_lt(i, bl(Bytes.push(out, c))), Nat.is_lt(i, 1n+bl(out)), True{},
        Equal.cong(Nat, Bool, y => Nat.is_lt(i, y), bl(Bytes.push(out, c)), 1n+bl(out), bl_push(out, c)),
        lt_succ_r(i, bl(out))(lt))
      Equal.trans(Maybe<&2, Char>, String.get(D.copy.go(p, Bytes.push(out, c), d), i), String.get(Bytes.push(out, c), i),
        String.get(out, i), copy_prefix(p, Bytes.push(out, c), d, i, lt2),
        get_app_lt(out, SCon{Chr{c}, SNil{}}, i, lt))

# each copied byte is the byte dist before it
def copy_back.go(+len: Nat, +j: Nat, +out: Bytes(), +d: Nat, +d1: {Nat.is_lt(0n, d) == True{} : Bool},
  +dle: {Nat.is_le(d, bl(out)) == True{} : Bool}, jl: {Nat.is_lt(j, len) == True{} : Bool}) ->
  {Bytes.get(D.copy.go(len, out, d), Nat.add(j, bl(out))) ==
    Bytes.get(D.copy.go(len, out, d), Nat.sub(Nat.add(j, bl(out)), d)) : U32}:
  match len j:
    case 0n _:
      Nat.lt_zero({Bytes.get(D.copy.go(0n, out, d), Nat.add(j, bl(out))) ==
        Bytes.get(D.copy.go(0n, out, d), Nat.sub(Nat.add(j, bl(out)), d)) : U32}, j, jl)
    case 1n+p 0n:
      +c = Bytes.get(out, Nat.sub(Bytes.len(out), d))
      +o2 = Bytes.push(out, c)
      +r = D.copy.go(p, o2, d)
      +lt1 = Equal.trans(Bool, Nat.is_lt(bl(out), bl(o2)), Nat.is_lt(bl(out), 1n+bl(out)), True{},
        Equal.cong(Nat, Bool, y => Nat.is_lt(bl(out), y), bl(o2), 1n+bl(out), bl_push(out, c)),
        le_lt_succ(bl(out), bl(out))(le_refl(bl(out))))
      +ls = lt_sub(d, bl(out), d1, dle)
      +lt3 = Equal.trans(Bool, Nat.is_lt(Nat.sub(bl(out), d), bl(o2)), Nat.is_lt(Nat.sub(bl(out), d), 1n+bl(out)), True{},
        Equal.cong(Nat, Bool, y => Nat.is_lt(Nat.sub(bl(out), d), y), bl(o2), 1n+bl(out), bl_push(out, c)),
        lt_succ_r(Nat.sub(bl(out), d), bl(out))(ls))
      +e1 = Equal.trans(Maybe<&2, Char>, String.get(r, bl(out)), String.get(o2, bl(out)), String.get(SCon{Chr{c}, SNil{}}, 0n),
        copy_prefix(p, o2, d, bl(out), lt1), get_app_len(out, SCon{Chr{c}, SNil{}}))
      +e2 = Equal.trans(Maybe<&2, Char>, String.get(r, Nat.sub(bl(out), d)), String.get(o2, Nat.sub(bl(out), d)),
        String.get(out, Nat.sub(bl(out), d)), copy_prefix(p, o2, d, Nat.sub(bl(out), d), lt3),
        get_app_lt(out, SCon{Chr{c}, SNil{}}, Nat.sub(bl(out), d), ls))
      Equal.trans(U32, Bytes.byte(String.get(r, bl(out))), c, Bytes.byte(String.get(r, Nat.sub(bl(out), d))),
        Equal.cong(Maybe<&2, Char>, U32, Bytes.byte, String.get(r, bl(out)), String.get(SCon{Chr{c}, SNil{}}, 0n), e1),
        Equal.trans(U32, c, Bytes.get(out, Nat.sub(bl(out), d)), Bytes.byte(String.get(r, Nat.sub(bl(out), d))),
          Equal.cong(Nat, U32, y => Bytes.get(out, Nat.sub(y, d)), Bytes.len(out), bl(out), blen(out)),
          Equal.sym(U32, Bytes.byte(String.get(r, Nat.sub(bl(out), d))), Bytes.get(out, Nat.sub(bl(out), d)),
            Equal.cong(Maybe<&2, Char>, U32, Bytes.byte, String.get(r, Nat.sub(bl(out), d)),
              String.get(out, Nat.sub(bl(out), d)), e2))))
    case 1n+p 1n+q:
      +c = Bytes.get(out, Nat.sub(Bytes.len(out), d))
      +o2 = Bytes.push(out, c)
      +ih = copy_back.go(p, q, o2, d, d1,
        Equal.trans(Bool, Nat.is_le(d, bl(o2)), Nat.is_le(d, 1n+bl(out)), True{},
          Equal.cong(Nat, Bool, y => Nat.is_le(d, y), bl(o2), 1n+bl(out), bl_push(out, c)),
          le_succ(d, bl(out))(dle)), jl)
      +ea = Equal.trans(Nat, Nat.add(q, bl(o2)), Nat.add(q, 1n+bl(out)), 1n+Nat.add(q, bl(out)),
        Equal.cong(Nat, Nat, y => Nat.add(q, y), bl(o2), 1n+bl(out), bl_push(out, c)), add_succ(q, bl(out)))
      %ea :
        {Bytes.get(D.copy.go(p, o2, d), _) == Bytes.get(D.copy.go(p, o2, d), Nat.sub(_, d)) : U32}
      ih

def drop_len(+s: Bytes(), +k: Nat) -> {bl(Bytes.drop(s, k)) == Nat.sub(bl(s), k) : Nat}:
  match s k:
    case SNil{} 0n:
      {==}
    case SNil{} 1n+p:
      {==}
    case SCon{+h, +t} 0n:
      {==}
    case SCon{+h, +t} 1n+p:
      drop_len(t, p)

def sub_self(+a: Nat) -> {Nat.sub(a, a) == 0n : Nat}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      sub_self(p)

def sub_succ_l(+p: Nat, +s: Nat) -> {Nat.is_le(s, p) == True{} : Bool} -> {Nat.sub(1n+p, s) == 1n+Nat.sub(p, s) : Nat}:
  match p s:
    case 0n 0n:
      e => {==}
    case 1n+q 0n:
      e => {==}
    case 0n 1n+r:
      e => Bool.no({Nat.sub(1n, 1n+r) == 1n+Nat.sub(0n, 1n+r) : Nat}, e)
    case 1n+q 1n+r:
      e => sub_succ_l(q, r)(e)

def sub_sub_min(+a: Nat, +k: Nat) -> {Nat.sub(a, Nat.sub(a, k)) == Nat.min(a, k) : Nat}:
  match a k:
    case 0n 0n:
      {==}
    case 0n 1n+q:
      {==}
    case 1n+p 0n:
      sub_self(p)
    case 1n+p 1n+q:
      Equal.trans(Nat, Nat.sub(1n+p, Nat.sub(p, q)), 1n+Nat.sub(p, Nat.sub(p, q)), 1n+Nat.min(p, q),
        sub_succ_l(p, Nat.sub(p, q))(nsub_le(p, q)),
        Equal.cong(Nat, Nat, y => 1n+y, Nat.sub(p, Nat.sub(p, q)), Nat.min(p, q), sub_sub_min(p, q)))

def take_drop(+s: Bytes(), +k: Nat) -> {String.append(String.take(s, k), String.drop(s, k)) == s : Bytes()}:
  match s k:
    case SNil{} _:
      {==}
    case SCon{+h, +t} 0n:
      {==}
    case SCon{+h, +t} 1n+p:
      Equal.cong(Bytes(), Bytes(), y => SCon{h, y}, String.append(String.take(t, p), String.drop(t, p)), t,
        take_drop(t, p))

# the window kept: the last min(len, 32768) bytes of the output
def win_len(+out: Bytes(), +k: Nat) ->
  {Bytes.len(Bytes.drop(out, Nat.sub(Bytes.len(out), k))) == Nat.min(Bytes.len(out), k) : Nat}:
  +w = Nat.sub(Bytes.len(out), k)
  +e = blen(out)
  Equal.trans(Nat, Bytes.len(Bytes.drop(out, w)), bl(Bytes.drop(out, w)), Nat.min(Bytes.len(out), k),
    blen(Bytes.drop(out, w)),
    Equal.trans(Nat, bl(Bytes.drop(out, w)), Nat.sub(bl(out), w), Nat.min(Bytes.len(out), k), drop_len(out, w),
      Equal.trans(Nat, Nat.sub(bl(out), w), Nat.sub(bl(out), Nat.sub(bl(out), k)), Nat.min(Bytes.len(out), k),
        Equal.cong(Nat, Nat, y => Nat.sub(bl(out), Nat.sub(y, k)), Bytes.len(out), bl(out), e),
        Equal.trans(Nat, Nat.sub(bl(out), Nat.sub(bl(out), k)), Nat.min(bl(out), k), Nat.min(Bytes.len(out), k),
          sub_sub_min(bl(out), k),
          Equal.cong(Nat, Nat, y => Nat.min(y, k), bl(out), Bytes.len(out), Equal.sym(Nat, Bytes.len(out), bl(out), e))))))

# the laws at any tables: new(cap) is Dec("", 0n, cap, D.tabs())
def cap.output(+s: List<&2, U32>, +cap: Nat, +tb: D.Tabs) ->
  {Nat.is_le(D.written(D.feed_list(s, Dec("", 0n, cap, tb))), cap) == True{} : Bool}:
  cap.written(D.feed_list(s, Dec("", 0n, cap, tb)), cap, cap.feed(s, Dec("", 0n, cap, tb), cap, cap.new(cap, tb)))

def cap.inflate(+s: Bytes(), +cap: Nat, +tb: D.Tabs, +y: Bytes(),
  e: {D.finish(D.feed(s, Dec("", 0n, cap, tb))) == Done{y} : Result<&2, &2, D.Why, Bytes()>}) ->
  {Nat.is_le(Bytes.len(y), cap) == True{} : Bool}:
  +s0 = Dec("", 0n, cap, tb)
  +st = D.feed_list(Bytes.to_list(s), s0)
  +e2 = Equal.trans(Result<&2, &2, D.Why, Bytes()>, D.finish(st), D.finish(D.feed(s, s0)), Done{y},
    Equal.cong(D.St, Result<&2, &2, D.Why, Bytes()>, D.finish, st, D.feed(s, s0),
      Equal.sym(D.St, D.feed(s, s0), st, Laws.inflate_buf(s, s0))), e)
  le_by(Bytes.len(y), bl(y), cap, blen(y), cap.finish(st, cap, y, cap.feed(Bytes.to_list(s), s0, cap,
    cap.new(cap, tb)), e2))

def Laws.output_cap(s, cap):
  cap.output(s, cap, D.tabs())

def Laws.inflate_cap(s, cap, y, e):
  cap.inflate(s, cap, D.tabs(), y, Equal.trans(Result<&2, &2, D.Why, Bytes()>, D.finish(D.feed(s, D.new(cap))),
    D.inflate(cap, s), Done{y}, Equal.sym(Result<&2, &2, D.Why, Bytes()>, D.inflate(cap, s),
      D.finish(D.feed(s, D.new(cap))), IP.inflate_fast(cap, s)), e))

def Laws.copy_far(out, keep, n, cap, t, len, dist, next, bp, far):
  %Equal.sym(Bool, Nat.is_lt(Bytes.len(out), dist), True{}, far) :
    {D.copy.if(_, Nat.is_lt(cap, Nat.add(n, len)), out, keep, n, cap, t, len, dist, next, bp) ==
      D.St{D.Bad{D.FarBack{}}, D.O{out, keep, n, cap, t}, bp} : D.St}
  {==}

def Laws.copy_near(out, keep, n, cap, t, len, dist, next, bp, near, room):
  +nf = Equal.trans(Bool, Nat.is_lt(Bytes.len(out), dist), Bool.not(Nat.is_le(dist, Bytes.len(out))), False{},
    Equal.sym(Bool, Bool.not(Nat.is_le(dist, Bytes.len(out))), Nat.is_lt(Bytes.len(out), dist),
      Nat.le_flip(dist, Bytes.len(out))),
    Equal.cong(Bool, Bool, Bool.not, Nat.is_le(dist, Bytes.len(out)), True{}, near))
  +nb = Equal.trans(Bool, Nat.is_lt(cap, Nat.add(n, len)), Bool.not(Nat.is_le(Nat.add(n, len), cap)), False{},
    Equal.sym(Bool, Bool.not(Nat.is_le(Nat.add(n, len), cap)), Nat.is_lt(cap, Nat.add(n, len)),
      Nat.le_flip(Nat.add(n, len), cap)),
    Equal.cong(Bool, Bool, Bool.not, Nat.is_le(Nat.add(n, len), cap), True{}, room))
  %Equal.sym(Bool, Nat.is_lt(Bytes.len(out), dist), False{}, nf) :
    {D.copy.if(_, Nat.is_lt(cap, Nat.add(n, len)), out, keep, n, cap, t, len, dist, next, bp) ==
      D.St{next, D.O{D.copy.go(len, out, dist), keep, Nat.add(n, len), cap, t}, bp} : D.St}
  %Equal.sym(Bool, Nat.is_lt(cap, Nat.add(n, len)), False{}, nb) :
    {D.copy.big(_, out, keep, n, cap, t, len, dist, next, bp) ==
      D.St{next, D.O{D.copy.go(len, out, dist), keep, Nat.add(n, len), cap, t}, bp} : D.St}
  {==}

def Laws.copy_back(len, out, dist, j, d1, dle, jl):
  +e = blen(out)
  %Equal.sym(Nat, Bytes.len(out), bl(out), e) :
    {Bytes.get(D.copy.go(len, out, dist), Nat.add(j, _)) ==
      Bytes.get(D.copy.go(len, out, dist), Nat.sub(Nat.add(j, _), dist)) : U32}
  copy_back.go(len, j, out, dist, d1,
    Equal.trans(Bool, Nat.is_le(dist, bl(out)), Nat.is_le(dist, Bytes.len(out)), True{},
      Equal.cong(Nat, Bool, y => Nat.is_le(dist, y), bl(out), Bytes.len(out), Equal.sym(Nat, Bytes.len(out), bl(out), e)),
      dle), jl)

def Laws.take_window(m, out, keep, n, cap, t, bp):
  (win_len(out, 32768n), take_drop(out, Nat.sub(Bytes.len(out), 32768n)))

# The fixed round trip
# ====================
#
# deflate_fixed writes one block with the fixed code, its tokens checked
# against the input as they are written (fixtoks: every literal the byte
# it stands for, every copy within the window over bytes that agree, its
# length and distance carried back by their codes; else the bytes as
# literals). The proof runs the writer and the machine over bits as the
# stored one does: each symbol's code walks the written-out fixed table
# to the symbol (sym_ll, sym_d, symbol by symbol), each extra field reads
# back its bits (len_x_e, dist_x_e), a literal is emitted as itself
# (dlit), a copy is the input further on (dref, copyx), and a checked
# run of tokens is the input from its start to its end (dtoks).


# The fixed codes
# ---------------

# the n low bits of c, high first: a code as putm writes it
def mbits(+n: Nat, +c: U32) -> List<&2, Bool>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Con{D.bit(c, p), mbits(p, c)}

# the bit offset n bits on
def advn(n: Nat, bp: Nat) -> Nat:
  match n:
    case 0n:
      bp
    case 1n+p:
      advn(p, D.next_bp(bp))


# every sym_ll symbol's code walks the table to the symbol
def sym_ll(+s: Nat, +k: D.SK, +o: D.O, +bp: Nat, +rest: List<&2, Bool>) -> {Nat.is_lt(s, 286n) == True{} : Bool} ->
  {bfeed(app(mbits(D.nat_at(D.HLLL(), s), Bytes.get(D.HLLC(), s)), rest), D.St{D.Walk{0n, D.FLL(), k}, o, bp}) ==
    bfeed(rest, D.sym(k, s, o, advn(D.nat_at(D.HLLL(), s), bp))) : D.St}:
  match s:
    case 0n:
      e => {==}
    case 1n:
      e => {==}
    case 2n:
      e => {==}
    case 3n:
      e => {==}
    case 4n:
      e => {==}
    case 5n:
      e => {==}
    case 6n:
      e => {==}
    case 7n:
      e => {==}
    case 8n:
      e => {==}
    case 9n:
      e => {==}
    case 10n:
      e => {==}
    case 11n:
      e => {==}
    case 12n:
      e => {==}
    case 13n:
      e => {==}
    case 14n:
      e => {==}
    case 15n:
      e => {==}
    case 16n:
      e => {==}
    case 17n:
      e => {==}
    case 18n:
      e => {==}
    case 19n:
      e => {==}
    case 20n:
      e => {==}
    case 21n:
      e => {==}
    case 22n:
      e => {==}
    case 23n:
      e => {==}
    case 24n:
      e => {==}
    case 25n:
      e => {==}
    case 26n:
      e => {==}
    case 27n:
      e => {==}
    case 28n:
      e => {==}
    case 29n:
      e => {==}
    case 30n:
      e => {==}
    case 31n:
      e => {==}
    case 32n:
      e => {==}
    case 33n:
      e => {==}
    case 34n:
      e => {==}
    case 35n:
      e => {==}
    case 36n:
      e => {==}
    case 37n:
      e => {==}
    case 38n:
      e => {==}
    case 39n:
      e => {==}
    case 40n:
      e => {==}
    case 41n:
      e => {==}
    case 42n:
      e => {==}
    case 43n:
      e => {==}
    case 44n:
      e => {==}
    case 45n:
      e => {==}
    case 46n:
      e => {==}
    case 47n:
      e => {==}
    case 48n:
      e => {==}
    case 49n:
      e => {==}
    case 50n:
      e => {==}
    case 51n:
      e => {==}
    case 52n:
      e => {==}
    case 53n:
      e => {==}
    case 54n:
      e => {==}
    case 55n:
      e => {==}
    case 56n:
      e => {==}
    case 57n:
      e => {==}
    case 58n:
      e => {==}
    case 59n:
      e => {==}
    case 60n:
      e => {==}
    case 61n:
      e => {==}
    case 62n:
      e => {==}
    case 63n:
      e => {==}
    case 64n:
      e => {==}
    case 65n:
      e => {==}
    case 66n:
      e => {==}
    case 67n:
      e => {==}
    case 68n:
      e => {==}
    case 69n:
      e => {==}
    case 70n:
      e => {==}
    case 71n:
      e => {==}
    case 72n:
      e => {==}
    case 73n:
      e => {==}
    case 74n:
      e => {==}
    case 75n:
      e => {==}
    case 76n:
      e => {==}
    case 77n:
      e => {==}
    case 78n:
      e => {==}
    case 79n:
      e => {==}
    case 80n:
      e => {==}
    case 81n:
      e => {==}
    case 82n:
      e => {==}
    case 83n:
      e => {==}
    case 84n:
      e => {==}
    case 85n:
      e => {==}
    case 86n:
      e => {==}
    case 87n:
      e => {==}
    case 88n:
      e => {==}
    case 89n:
      e => {==}
    case 90n:
      e => {==}
    case 91n:
      e => {==}
    case 92n:
      e => {==}
    case 93n:
      e => {==}
    case 94n:
      e => {==}
    case 95n:
      e => {==}
    case 96n:
      e => {==}
    case 97n:
      e => {==}
    case 98n:
      e => {==}
    case 99n:
      e => {==}
    case 100n:
      e => {==}
    case 101n:
      e => {==}
    case 102n:
      e => {==}
    case 103n:
      e => {==}
    case 104n:
      e => {==}
    case 105n:
      e => {==}
    case 106n:
      e => {==}
    case 107n:
      e => {==}
    case 108n:
      e => {==}
    case 109n:
      e => {==}
    case 110n:
      e => {==}
    case 111n:
      e => {==}
    case 112n:
      e => {==}
    case 113n:
      e => {==}
    case 114n:
      e => {==}
    case 115n:
      e => {==}
    case 116n:
      e => {==}
    case 117n:
      e => {==}
    case 118n:
      e => {==}
    case 119n:
      e => {==}
    case 120n:
      e => {==}
    case 121n:
      e => {==}
    case 122n:
      e => {==}
    case 123n:
      e => {==}
    case 124n:
      e => {==}
    case 125n:
      e => {==}
    case 126n:
      e => {==}
    case 127n:
      e => {==}
    case 128n:
      e => {==}
    case 129n:
      e => {==}
    case 130n:
      e => {==}
    case 131n:
      e => {==}
    case 132n:
      e => {==}
    case 133n:
      e => {==}
    case 134n:
      e => {==}
    case 135n:
      e => {==}
    case 136n:
      e => {==}
    case 137n:
      e => {==}
    case 138n:
      e => {==}
    case 139n:
      e => {==}
    case 140n:
      e => {==}
    case 141n:
      e => {==}
    case 142n:
      e => {==}
    case 143n:
      e => {==}
    case 144n:
      e => {==}
    case 145n:
      e => {==}
    case 146n:
      e => {==}
    case 147n:
      e => {==}
    case 148n:
      e => {==}
    case 149n:
      e => {==}
    case 150n:
      e => {==}
    case 151n:
      e => {==}
    case 152n:
      e => {==}
    case 153n:
      e => {==}
    case 154n:
      e => {==}
    case 155n:
      e => {==}
    case 156n:
      e => {==}
    case 157n:
      e => {==}
    case 158n:
      e => {==}
    case 159n:
      e => {==}
    case 160n:
      e => {==}
    case 161n:
      e => {==}
    case 162n:
      e => {==}
    case 163n:
      e => {==}
    case 164n:
      e => {==}
    case 165n:
      e => {==}
    case 166n:
      e => {==}
    case 167n:
      e => {==}
    case 168n:
      e => {==}
    case 169n:
      e => {==}
    case 170n:
      e => {==}
    case 171n:
      e => {==}
    case 172n:
      e => {==}
    case 173n:
      e => {==}
    case 174n:
      e => {==}
    case 175n:
      e => {==}
    case 176n:
      e => {==}
    case 177n:
      e => {==}
    case 178n:
      e => {==}
    case 179n:
      e => {==}
    case 180n:
      e => {==}
    case 181n:
      e => {==}
    case 182n:
      e => {==}
    case 183n:
      e => {==}
    case 184n:
      e => {==}
    case 185n:
      e => {==}
    case 186n:
      e => {==}
    case 187n:
      e => {==}
    case 188n:
      e => {==}
    case 189n:
      e => {==}
    case 190n:
      e => {==}
    case 191n:
      e => {==}
    case 192n:
      e => {==}
    case 193n:
      e => {==}
    case 194n:
      e => {==}
    case 195n:
      e => {==}
    case 196n:
      e => {==}
    case 197n:
      e => {==}
    case 198n:
      e => {==}
    case 199n:
      e => {==}
    case 200n+q:
      match q:
        case 0n:
          e => {==}
        case 1n:
          e => {==}
        case 2n:
          e => {==}
        case 3n:
          e => {==}
        case 4n:
          e => {==}
        case 5n:
          e => {==}
        case 6n:
          e => {==}
        case 7n:
          e => {==}
        case 8n:
          e => {==}
        case 9n:
          e => {==}
        case 10n:
          e => {==}
        case 11n:
          e => {==}
        case 12n:
          e => {==}
        case 13n:
          e => {==}
        case 14n:
          e => {==}
        case 15n:
          e => {==}
        case 16n:
          e => {==}
        case 17n:
          e => {==}
        case 18n:
          e => {==}
        case 19n:
          e => {==}
        case 20n:
          e => {==}
        case 21n:
          e => {==}
        case 22n:
          e => {==}
        case 23n:
          e => {==}
        case 24n:
          e => {==}
        case 25n:
          e => {==}
        case 26n:
          e => {==}
        case 27n:
          e => {==}
        case 28n:
          e => {==}
        case 29n:
          e => {==}
        case 30n:
          e => {==}
        case 31n:
          e => {==}
        case 32n:
          e => {==}
        case 33n:
          e => {==}
        case 34n:
          e => {==}
        case 35n:
          e => {==}
        case 36n:
          e => {==}
        case 37n:
          e => {==}
        case 38n:
          e => {==}
        case 39n:
          e => {==}
        case 40n:
          e => {==}
        case 41n:
          e => {==}
        case 42n:
          e => {==}
        case 43n:
          e => {==}
        case 44n:
          e => {==}
        case 45n:
          e => {==}
        case 46n:
          e => {==}
        case 47n:
          e => {==}
        case 48n:
          e => {==}
        case 49n:
          e => {==}
        case 50n:
          e => {==}
        case 51n:
          e => {==}
        case 52n:
          e => {==}
        case 53n:
          e => {==}
        case 54n:
          e => {==}
        case 55n:
          e => {==}
        case 56n:
          e => {==}
        case 57n:
          e => {==}
        case 58n:
          e => {==}
        case 59n:
          e => {==}
        case 60n:
          e => {==}
        case 61n:
          e => {==}
        case 62n:
          e => {==}
        case 63n:
          e => {==}
        case 64n:
          e => {==}
        case 65n:
          e => {==}
        case 66n:
          e => {==}
        case 67n:
          e => {==}
        case 68n:
          e => {==}
        case 69n:
          e => {==}
        case 70n:
          e => {==}
        case 71n:
          e => {==}
        case 72n:
          e => {==}
        case 73n:
          e => {==}
        case 74n:
          e => {==}
        case 75n:
          e => {==}
        case 76n:
          e => {==}
        case 77n:
          e => {==}
        case 78n:
          e => {==}
        case 79n:
          e => {==}
        case 80n:
          e => {==}
        case 81n:
          e => {==}
        case 82n:
          e => {==}
        case 83n:
          e => {==}
        case 84n:
          e => {==}
        case 85n:
          e => {==}
        case 86n+r:
          e => Nat.lt_zero({bfeed(app(mbits(D.nat_at(D.HLLL(), 286n+r), Bytes.get(D.HLLC(), 286n+r)), rest), D.St{D.Walk{0n, D.FLL(), k}, o, bp}) == bfeed(rest, D.sym(k, 286n+r, o, advn(D.nat_at(D.HLLL(), 286n+r), bp))) : D.St}, r, e)

# every sym_d symbol's code walks the table to the symbol
def sym_d(+s: Nat, +k: D.SK, +o: D.O, +bp: Nat, +rest: List<&2, Bool>) -> {Nat.is_lt(s, 30n) == True{} : Bool} ->
  {bfeed(app(mbits(D.nat_at(D.HDL(), s), Bytes.get(D.HDC(), s)), rest), D.St{D.Walk{0n, D.FD(), k}, o, bp}) ==
    bfeed(rest, D.sym(k, s, o, advn(D.nat_at(D.HDL(), s), bp))) : D.St}:
  match s:
    case 0n:
      e => {==}
    case 1n:
      e => {==}
    case 2n:
      e => {==}
    case 3n:
      e => {==}
    case 4n:
      e => {==}
    case 5n:
      e => {==}
    case 6n:
      e => {==}
    case 7n:
      e => {==}
    case 8n:
      e => {==}
    case 9n:
      e => {==}
    case 10n:
      e => {==}
    case 11n:
      e => {==}
    case 12n:
      e => {==}
    case 13n:
      e => {==}
    case 14n:
      e => {==}
    case 15n:
      e => {==}
    case 16n:
      e => {==}
    case 17n:
      e => {==}
    case 18n:
      e => {==}
    case 19n:
      e => {==}
    case 20n:
      e => {==}
    case 21n:
      e => {==}
    case 22n:
      e => {==}
    case 23n:
      e => {==}
    case 24n:
      e => {==}
    case 25n:
      e => {==}
    case 26n:
      e => {==}
    case 27n:
      e => {==}
    case 28n:
      e => {==}
    case 29n:
      e => {==}
    case 30n+q:
      e => Nat.lt_zero({bfeed(app(mbits(D.nat_at(D.HDL(), 30n+q), Bytes.get(D.HDC(), 30n+q)), rest), D.St{D.Walk{0n, D.FD(), k}, o, bp}) == bfeed(rest, D.sym(k, 30n+q, o, advn(D.nat_at(D.HDL(), 30n+q), bp))) : D.St}, q, e)


# a length code's extra bits read: base and extra carry the length

def len_x_e(+e: Nat, +blk: D.Blk, +b: Nat, +v: Nat, +o: D.O, +bp: Nat, +rest: List<&2, Bool>) -> {Nat.is_lt(e, 14n) == True{} : Bool} ->
  {bfeed(app(D.xbits(e, v), rest), D.len_x(blk, b, e, o, bp)) == bfeed(rest, D.St{D.dist_mode(blk, Nat.add(b, D.hval(D.revapp(D.xbits(e, v), Nil{}), 0n))), o, advn(e, bp)}) : D.St}:
  match e:
    case 0n:
      c => %Equal.sym(Nat, Nat.add(b, 0n), b, add_zero(b)) :
        {bfeed(rest, D.St{D.dist_mode(blk, b), o, bp}) == bfeed(rest, D.St{D.dist_mode(blk, _), o, bp}) : D.St}
        {==}
    case 1n:
      c => {==}
    case 2n:
      c => {==}
    case 3n:
      c => {==}
    case 4n:
      c => {==}
    case 5n:
      c => {==}
    case 6n:
      c => {==}
    case 7n:
      c => {==}
    case 8n:
      c => {==}
    case 9n:
      c => {==}
    case 10n:
      c => {==}
    case 11n:
      c => {==}
    case 12n:
      c => {==}
    case 13n:
      c => {==}
    case 14n+q:
      c => Nat.lt_zero({bfeed(app(D.xbits(14n+q, v), rest), D.len_x(blk, b, 14n+q, o, bp)) == bfeed(rest, D.St{D.dist_mode(blk, Nat.add(b, D.hval(D.revapp(D.xbits(14n+q, v), Nil{}), 0n))), o, advn(14n+q, bp)}) : D.St}, q, c)

# a distance code's extra bits read: the copy, base and extra carrying its distance

def dist_x_e(+e: Nat, +blk: D.Blk, +len: Nat, +b: Nat, +v: Nat, +o: D.O, +bp: Nat, +rest: List<&2, Bool>) -> {Nat.is_lt(e, 14n) == True{} : Bool} ->
  {bfeed(app(D.xbits(e, v), rest), D.dist_x(blk, len, b, e, o, bp)) == bfeed(rest, D.copy(o, len, Nat.add(b, D.hval(D.revapp(D.xbits(e, v), Nil{}), 0n)), D.lit_mode(blk), advn(e, bp))) : D.St}:
  match e:
    case 0n:
      c => %Equal.sym(Nat, Nat.add(b, 0n), b, add_zero(b)) :
        {bfeed(rest, D.copy(o, len, b, D.lit_mode(blk), bp)) == bfeed(rest, D.copy(o, len, _, D.lit_mode(blk), bp)) : D.St}
        {==}
    case 1n:
      c => {==}
    case 2n:
      c => {==}
    case 3n:
      c => {==}
    case 4n:
      c => {==}
    case 5n:
      c => {==}
    case 6n:
      c => {==}
    case 7n:
      c => {==}
    case 8n:
      c => {==}
    case 9n:
      c => {==}
    case 10n:
      c => {==}
    case 11n:
      c => {==}
    case 12n:
      c => {==}
    case 13n:
      c => {==}
    case 14n+q:
      c => Nat.lt_zero({bfeed(app(D.xbits(14n+q, v), rest), D.dist_x(blk, len, b, 14n+q, o, bp)) == bfeed(rest, D.copy(o, len, Nat.add(b, D.hval(D.revapp(D.xbits(14n+q, v), Nil{}), 0n)), D.lit_mode(blk), advn(14n+q, bp))) : D.St}, q, c)


# Prefixes of the input
# ---------------------

def take0(+x: Bytes()) -> {String.take(x, 0n) == "" : Bytes()}:
  match x:
    case SNil{}:
      {==}
    case SCon{+h, +t}:
      {==}

def take_bl(+x: Bytes(), +pos: Nat) -> {Nat.is_le(pos, bl(x)) == True{} : Bool} -> {bl(String.take(x, pos)) == pos : Nat}:
  match x pos:
    case SNil{} 0n:
      e => {==}
    case SNil{} 1n+p:
      e => Bool.no({bl(String.take(SNil{}, 1n+p)) == 1n+p : Nat}, e)
    case SCon{+h, +t} 0n:
      e => {==}
    case SCon{+h, +t} 1n+p:
      e => Equal.cong(Nat, Nat, y => 1n+y, bl(String.take(t, p)), p, take_bl(t, p)(e))

def get_take(+x: Bytes(), +pos: Nat, +i: Nat) -> {Nat.is_lt(i, pos) == True{} : Bool} ->
  {String.get(String.take(x, pos), i) == String.get(x, i) : Maybe<&2, Char>}:
  match x pos i:
    case SNil{} _ _:
      e => {==}
    case SCon{+h, +t} 0n _:
      e => Nat.lt_zero({String.get(String.take(SCon{h, t}, 0n), i) == String.get(SCon{h, t}, i) : Maybe<&2, Char>}, i, e)
    case SCon{+h, +t} 1n+p 0n:
      e => {==}
    case SCon{+h, +t} 1n+p 1n+j:
      e => get_take(t, p, j)(e)

def take_push(+x: Bytes(), +pos: Nat) -> {Nat.is_lt(pos, bl(x)) == True{} : Bool} ->
  {Bytes.push(String.take(x, pos), Bytes.get(x, pos)) == String.take(x, 1n+pos) : Bytes()}:
  match x pos:
    case SNil{} _:
      e => Nat.lt_zero({Bytes.push(String.take(SNil{}, pos), Bytes.get(SNil{}, pos)) == String.take(SNil{}, 1n+pos) : Bytes()}, pos, e)
    case SCon{Chr{+c}, +t} 0n:
      e =>
        %Equal.sym(Bytes(), String.take(t, 0n), "", take0(t)) : {SCon{Chr{c}, ""} == SCon{Chr{c}, _} : Bytes()}
        {==}
    case SCon{Chr{+c}, +t} 1n+p:
      e => Equal.cong(Bytes(), Bytes(), y => SCon{Chr{c}, y}, Bytes.push(String.take(t, p), Bytes.get(t, p)),
        String.take(t, 1n+p), take_push(t, p)(e))

def take_whole(+x: Bytes()) -> {String.take(x, bl(x)) == x : Bytes()}:
  match x:
    case SNil{}:
      {==}
    case SCon{+h, +t}:
      Equal.cong(Bytes(), Bytes(), y => SCon{h, y}, String.take(t, bl(t)), t, take_whole(t))

def valid_get(+x: Bytes(), +pos: Nat) -> {D.valid(x) == True{} : Bool} -> {Nat.is_lt(pos, bl(x)) == True{} : Bool} ->
  {U32.is_lt(Bytes.get(x, pos), 256) == True{} : Bool}:
  match x pos:
    case SNil{} _:
      v => e => Nat.lt_zero({U32.is_lt(Bytes.get(SNil{}, pos), 256) == True{} : Bool}, pos, e)
    case SCon{Chr{+c}, +t} 0n:
      v => e => Bool.and_l(U32.is_lt(c, 256), D.valid(t), v)
    case SCon{Chr{+c}, +t} 1n+p:
      v => e => valid_get(t, p)(Bool.and_r(U32.is_lt(c, 256), D.valid(t), v))(e)

def nat_eq(+a: Nat, +b: Nat) -> {Nat.is_eq(a, b) == True{} : Bool} -> {a == b : Nat}:
  match a b:
    case 0n 0n:
      e => {==}
    case 0n 1n+q:
      e => Bool.no({0n == 1n+q : Nat}, e)
    case 1n+p 0n:
      e => Bool.no({1n+p == 0n : Nat}, e)
    case 1n+p 1n+q:
      e => Equal.cong(Nat, Nat, y => 1n+y, p, q, nat_eq(p, q)(e))

def nat_eq_refl(+a: Nat) -> {Nat.is_eq(a, a) == True{} : Bool}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      nat_eq_refl(p)

def from_it(+k: Nat) -> {U32.from_nat(k) == U32{it(32n, k)} : U32}:
  match k:
    case 0n:
      {==}
    case 1n+j:
      %Equal.sym(U32, U32.from_nat(j), U32{it(32n, j)}, from_it(j)) :
        {U32.inc(_) == U32{Word.inc(32n, it(32n, j))} : U32}
      {==}

# a U32 is the U32 of its value
def from_to(+c: U32) -> {U32.from_nat(U32.to_nat(c)) == c : U32}:
  match c:
    case U32{+w}:
      %Equal.sym(U32, U32.from_nat(Word.to_nat(32n, w)), U32{it(32n, Word.to_nat(32n, w))},
        from_it(Word.to_nat(32n, w))) : {_ == U32{w} : U32}
      %Equal.sym(Word(32n), it(32n, Word.to_nat(32n, w)), w, it_val(32n, w)) :
        {U32{_} == U32{w} : U32}
      {==}

def u32_eq(+a: U32, +b: U32) -> {U32.is_eq(a, b) == True{} : Bool} -> {a == b : U32}:
  e =>
    +en = nat_eq(U32.to_nat(a), U32.to_nat(b))(Equal.trans(Bool, Nat.is_eq(U32.to_nat(a), U32.to_nat(b)),
      U32.is_eq(a, b), True{}, Equal.sym(Bool, U32.is_eq(a, b), Nat.is_eq(U32.to_nat(a), U32.to_nat(b)),
      U32.eq_nat(a, b)), e))
    Equal.trans(U32, a, U32.from_nat(U32.to_nat(a)), b, Equal.sym(U32, U32.from_nat(U32.to_nat(a)), a, from_to(a)),
      Equal.trans(U32, U32.from_nat(U32.to_nat(a)), U32.from_nat(U32.to_nat(b)), b,
        Equal.cong(Nat, U32, U32.from_nat, U32.to_nat(a), U32.to_nat(b), en), from_to(b)))

def u32_refl(+a: U32) -> {U32.is_eq(a, a) == True{} : Bool}:
  Equal.trans(Bool, U32.is_eq(a, a), Nat.is_eq(U32.to_nat(a), U32.to_nat(a)), True{}, U32.eq_nat(a, a),
    nat_eq_refl(U32.to_nat(a)))

def sub0(+k: Nat) -> {Nat.sub(k, 0n) == k : Nat}:
  match k:
    case 0n:
      {==}
    case 1n+p:
      {==}


# The fixed path's tokens
# -----------------------

def lx14(+k: Nat) -> {Nat.is_lt(k, 29n) == True{} : Bool} -> {Nat.is_lt(D.nat_at(D.LXS(), k), 14n) == True{} : Bool}:
  match k:
    case 0n:
      e => {==}
    case 1n:
      e => {==}
    case 2n:
      e => {==}
    case 3n:
      e => {==}
    case 4n:
      e => {==}
    case 5n:
      e => {==}
    case 6n:
      e => {==}
    case 7n:
      e => {==}
    case 8n:
      e => {==}
    case 9n:
      e => {==}
    case 10n:
      e => {==}
    case 11n:
      e => {==}
    case 12n:
      e => {==}
    case 13n:
      e => {==}
    case 14n:
      e => {==}
    case 15n:
      e => {==}
    case 16n:
      e => {==}
    case 17n:
      e => {==}
    case 18n:
      e => {==}
    case 19n:
      e => {==}
    case 20n:
      e => {==}
    case 21n:
      e => {==}
    case 22n:
      e => {==}
    case 23n:
      e => {==}
    case 24n:
      e => {==}
    case 25n:
      e => {==}
    case 26n:
      e => {==}
    case 27n:
      e => {==}
    case 28n:
      e => {==}
    case 29n+q:
      e => Nat.lt_zero({Nat.is_lt(D.nat_at(D.LXS(), 29n+q), 14n) == True{} : Bool}, q, e)

def dx14(+k: Nat) -> {Nat.is_lt(k, 30n) == True{} : Bool} -> {Nat.is_lt(D.nat_at(D.DXS(), k), 14n) == True{} : Bool}:
  match k:
    case 0n:
      e => {==}
    case 1n:
      e => {==}
    case 2n:
      e => {==}
    case 3n:
      e => {==}
    case 4n:
      e => {==}
    case 5n:
      e => {==}
    case 6n:
      e => {==}
    case 7n:
      e => {==}
    case 8n:
      e => {==}
    case 9n:
      e => {==}
    case 10n:
      e => {==}
    case 11n:
      e => {==}
    case 12n:
      e => {==}
    case 13n:
      e => {==}
    case 14n:
      e => {==}
    case 15n:
      e => {==}
    case 16n:
      e => {==}
    case 17n:
      e => {==}
    case 18n:
      e => {==}
    case 19n:
      e => {==}
    case 20n:
      e => {==}
    case 21n:
      e => {==}
    case 22n:
      e => {==}
    case 23n:
      e => {==}
    case 24n:
      e => {==}
    case 25n:
      e => {==}
    case 26n:
      e => {==}
    case 27n:
      e => {==}
    case 28n:
      e => {==}
    case 29n:
      e => {==}
    case 30n+q:
      e => Nat.lt_zero({Nat.is_lt(D.nat_at(D.DXS(), 30n+q), 14n) == True{} : Bool}, q, e)

# the block being read: its tables the fixed ones
def FB(+last: Bool) -> D.Blk:
  D.Blk{last, D.FLL(), D.FD()}

# the output so far: x up to pos
def OX(+x: Bytes(), +pos: Nat, +cap: Nat) -> D.O:
  D.O{String.take(x, pos), 0n, pos, cap, D.tabs()}

# the machine between tokens
def LS(+last: Bool, +x: Bytes(), +pos: Nat, +cap: Nat, +bp: Nat) -> D.St:
  D.St{D.lit_mode(FB(last)), OX(x, pos, cap), bp}

def L257(+k: Nat) -> Nat:
  Nat.add(U32.to_nat(257), k)

def kof(+len: Nat) -> Nat:
  D.nat_at(D.LCS(), D.lidx(len))

def qof(+dist: Nat) -> Nat:
  D.nat_at(D.DCS(), D.didx(dist))

# a token's bits, s after them
def tk(tok: D.Tok, s: List<&2, Bool>) -> List<&2, Bool>:
  match tok:
    case D.Lit{+c}:
      app(mbits(D.nat_at(D.HLLL(), U32.to_nat(c)), Bytes.get(D.HLLC(), U32.to_nat(c))), s)
    case D.Ref{+len, +dist}:
      +k = kof(len)
      +q = qof(dist)
      app(mbits(D.nat_at(D.HLLL(), L257(k)), Bytes.get(D.HLLC(), L257(k))),
        app(D.xbits(D.nat_at(D.LXS(), k), Nat.sub(len, D.nat_at(D.LBS(), k))),
          app(mbits(D.nat_at(D.HDL(), q), Bytes.get(D.HDC(), q)),
            app(D.xbits(D.nat_at(D.DXS(), q), Nat.sub(dist, D.nat_at(D.DBS(), q))), s))))

# the bit offset after a token
def adv(tok: D.Tok, bp: Nat) -> Nat:
  match tok:
    case D.Lit{+c}:
      advn(D.nat_at(D.HLLL(), U32.to_nat(c)), bp)
    case D.Ref{+len, +dist}:
      +k = kof(len)
      +q = qof(dist)
      advn(D.nat_at(D.DXS(), q), advn(D.nat_at(D.HDL(), q), advn(D.nat_at(D.LXS(), k),
        advn(D.nat_at(D.HLLL(), L257(k)), bp))))

# A literal
def dlit.at(+last: Bool, +x: Bytes(), +pos: Nat, +cap: Nat, +bp: Nat, +s: List<&2, Bool>, +c: U32,
  +n256: {Nat.is_lt(U32.to_nat(c), 256n) == True{} : Bool}, +lt: {Nat.is_lt(pos, bl(x)) == True{} : Bool},
  +ceq: {c == Bytes.get(x, pos) : U32}, +pcap: {Nat.is_lt(pos, cap) == True{} : Bool}) ->
  {bfeed(s, D.sym(D.SLit{FB(last)}, U32.to_nat(c), OX(x, pos, cap), bp)) == bfeed(s, LS(last, x, 1n+pos, cap, bp)) : D.St}:
  +rhs = bfeed(s, LS(last, x, 1n+pos, cap, bp))
  %Equal.sym(Bool, Nat.is_lt(U32.to_nat(c), 256n), True{}, n256) :
    {bfeed(s, D.lit(_, FB(last), U32.to_nat(c), OX(x, pos, cap), bp)) == rhs : D.St}
  %Equal.sym(Bool, Nat.is_lt(pos, cap), True{}, pcap) :
    {bfeed(s, D.emit.if(_, String.take(x, pos), 0n, pos, cap, D.tabs(), U32.from_nat(U32.to_nat(c)),
      D.lit_mode(FB(last)), bp)) == rhs : D.St}
  %Equal.sym(U32, U32.from_nat(U32.to_nat(c)), c, from_to(c)) :
    {bfeed(s, D.St{D.lit_mode(FB(last)), D.O{Bytes.push(String.take(x, pos), _), 0n, 1n+pos, cap, D.tabs()}, bp}) ==
      rhs : D.St}
  %Equal.sym(U32, c, Bytes.get(x, pos), ceq) :
    {bfeed(s, D.St{D.lit_mode(FB(last)), D.O{Bytes.push(String.take(x, pos), _), 0n, 1n+pos, cap, D.tabs()}, bp}) ==
      rhs : D.St}
  %Equal.sym(Bytes(), Bytes.push(String.take(x, pos), Bytes.get(x, pos)), String.take(x, 1n+pos), take_push(x, pos)(lt)) :
    {bfeed(s, D.St{D.lit_mode(FB(last)), D.O{_, 0n, 1n+pos, cap, D.tabs()}, bp}) == rhs : D.St}
  {==}

def dlit(+last: Bool, +x: Bytes(), +pos: Nat, +cap: Nat, +bp: Nat, +s: List<&2, Bool>, +c: U32,
  +vx: {D.valid(x) == True{} : Bool}, +lt: {Nat.is_lt(pos, bl(x)) == True{} : Bool},
  +ceq: {c == Bytes.get(x, pos) : U32}, +capok: {Nat.is_le(bl(x), cap) == True{} : Bool}) ->
  {bfeed(tk(D.Lit{c}, s), LS(last, x, pos, cap, bp)) ==
    bfeed(s, LS(last, x, 1n+pos, cap, adv(D.Lit{c}, bp))) : D.St}:
  +n = U32.to_nat(c)
  +c256 = Equal.trans(Bool, U32.is_lt(c, 256), U32.is_lt(Bytes.get(x, pos), 256), True{},
    Equal.cong(U32, Bool, y => U32.is_lt(y, 256), c, Bytes.get(x, pos), ceq), valid_get(x, pos)(vx)(lt))
  +n256 = Equal.trans(Bool, Nat.is_lt(n, 256n), U32.is_lt(c, 256), True{},
    Equal.sym(Bool, U32.is_lt(c, 256), Nat.is_lt(n, 256n), U32.lt_nat(c, 256)), c256)
  +bp1 = advn(D.nat_at(D.HLLL(), n), bp)
  Equal.trans(D.St, bfeed(tk(D.Lit{c}, s), LS(last, x, pos, cap, bp)), bfeed(s, D.sym(D.SLit{FB(last)}, n, OX(x, pos, cap), bp1)),
    bfeed(s, LS(last, x, 1n+pos, cap, bp1)),
    sym_ll(n, D.SLit{FB(last)}, OX(x, pos, cap), bp, s)(Nat.is_lt_le_trans(n, 256n, 286n, n256, {==})),
    dlit.at(last, x, pos, cap, bp1, s, c, n256, lt, ceq, Nat.is_lt_le_trans(pos, bl(x), cap, lt, capok)))


# a sum within c: its right part is
def le_right(+a: Nat, +b: Nat, +c: Nat, e: {Nat.is_le(Nat.add(a, b), c) == True{} : Bool}) ->
  {Nat.is_le(a, c) == True{} : Bool}:
  le_addl(b, a, c)(le_by(Nat.add(b, a), Nat.add(a, b), c, add_comm(b, a), e))

# a copy over bytes that agree with the ones dist before them: the input
# further on
def copyx(+len: Nat, +x: Bytes(), +pos: Nat, +d: Nat, +sm: {D.same(len, x, pos, d) == True{} : Bool},
  +d1: {Nat.is_lt(0n, d) == True{} : Bool}, +dle: {Nat.is_le(d, pos) == True{} : Bool},
  +fit: {Nat.is_le(Nat.add(pos, len), bl(x)) == True{} : Bool}) ->
  {D.copy.go(len, String.take(x, pos), d) == String.take(x, Nat.add(pos, len)) : Bytes()}:
  match len:
    case 0n:
      %Equal.sym(Nat, Nat.add(pos, 0n), pos, add_zero(pos)) :
        {String.take(x, pos) == String.take(x, _) : Bytes()}
      {==}
    case 1n+p:
      +t = String.take(x, pos)
      +c = Bytes.get(t, Nat.sub(Bytes.len(t), d))
      +f1 = le_by(Nat.add(1n+pos, p), Nat.add(pos, 1n+p), bl(x), Equal.sym(Nat, Nat.add(pos, 1n+p),
        1n+Nat.add(pos, p), add_succ(pos, p)), fit)
      +ple = le_right(pos, 1n+p, bl(x), fit)
      +plt = le_lt(pos, bl(x))(le_right(1n+pos, p, bl(x), f1))
      +lent = Equal.trans(Nat, Bytes.len(t), bl(t), pos, blen(t), take_bl(x, pos)(ple))
      +ls = lt_sub(d, pos, d1, dle)
      +g1 = Equal.trans(U32, c, Bytes.get(t, Nat.sub(pos, d)), Bytes.get(x, Nat.sub(pos, d)),
        Equal.cong(Nat, U32, y => Bytes.get(t, Nat.sub(y, d)), Bytes.len(t), pos, lent),
        Equal.cong(Maybe<&2, Char>, U32, Bytes.byte, String.get(t, Nat.sub(pos, d)), String.get(x, Nat.sub(pos, d)),
          get_take(x, pos, Nat.sub(pos, d))(ls)))
      +sm1 = Bool.and_l(U32.is_eq(Bytes.get(x, pos), Bytes.get(x, Nat.sub(pos, d))), D.same(p, x, 1n+pos, d), sm)
      +ceq = Equal.trans(U32, c, Bytes.get(x, Nat.sub(pos, d)), Bytes.get(x, pos), g1,
        Equal.sym(U32, Bytes.get(x, pos), Bytes.get(x, Nat.sub(pos, d)),
          u32_eq(Bytes.get(x, pos), Bytes.get(x, Nat.sub(pos, d)))(sm1)))
      +ep = Equal.trans(Bytes(), Bytes.push(t, c), Bytes.push(t, Bytes.get(x, pos)), String.take(x, 1n+pos),
        Equal.cong(U32, Bytes(), y => Bytes.push(t, y), c, Bytes.get(x, pos), ceq), take_push(x, pos)(plt))
      %Equal.sym(Bytes(), Bytes.push(t, c), String.take(x, 1n+pos), ep) :
        {D.copy.go(p, _, d) == String.take(x, Nat.add(pos, 1n+p)) : Bytes()}
      %Equal.sym(Nat, Nat.add(pos, 1n+p), 1n+Nat.add(pos, p), add_succ(pos, p)) :
        {D.copy.go(p, String.take(x, 1n+pos), d) == String.take(x, _) : Bytes()}
      copyx(p, x, 1n+pos, d, Bool.and_r(U32.is_eq(Bytes.get(x, pos), Bytes.get(x, Nat.sub(pos, d))),
        D.same(p, x, 1n+pos, d), sm), d1, le_succ(d, pos)(dle), f1)

# A copy
def dref.a(+last: Bool, +x: Bytes(), +pos: Nat, +cap: Nat, +bpA: Nat, +r1: List<&2, Bool>, +k: Nat,
  +hk: {Nat.is_lt(k, 29n) == True{} : Bool}) ->
  {bfeed(r1, D.sym(D.SLit{FB(last)}, L257(k), OX(x, pos, cap), bpA)) ==
    bfeed(r1, D.len_x(FB(last), D.nat_at(D.LBS(), k), D.nat_at(D.LXS(), k), OX(x, pos, cap), bpA)) : D.St}:
  +rhs = bfeed(r1, D.len_x(FB(last), D.nat_at(D.LBS(), k), D.nat_at(D.LXS(), k), OX(x, pos, cap), bpA))
  %Equal.sym(Bool, Nat.is_lt(k, 29n), True{}, hk) :
    {bfeed(r1, D.lit.c(_, FB(last), Nat.sub(L257(k), U32.to_nat(257)), OX(x, pos, cap), bpA)) == rhs : D.St}
  %Equal.sym(Nat, Nat.sub(k, 0n), k, sub0(k)) :
    {bfeed(r1, D.len_code(FB(last), _, OX(x, pos, cap), bpA)) == rhs : D.St}
  {==}

def dref.b(+last: Bool, +x: Bytes(), +pos: Nat, +cap: Nat, +bpC: Nat, +r2: List<&2, Bool>, +len: Nat, +k: Nat,
  +cl: {D.coded(D.LBS(), D.LXS(), k, len) == True{} : Bool}) ->
  {bfeed(r2, D.St{D.dist_mode(FB(last), Nat.add(D.nat_at(D.LBS(), k), D.hval(D.revapp(D.xbits(D.nat_at(D.LXS(), k),
    Nat.sub(len, D.nat_at(D.LBS(), k))), Nil{}), 0n))), OX(x, pos, cap), bpC}) ==
    bfeed(r2, D.St{D.dist_mode(FB(last), len), OX(x, pos, cap), bpC}) : D.St}:
  +b1 = D.nat_at(D.LBS(), k)
  +xb = D.xbits(D.nat_at(D.LXS(), k), Nat.sub(len, b1))
  +rhs = bfeed(r2, D.St{D.dist_mode(FB(last), len), OX(x, pos, cap), bpC})
  %Equal.sym(Nat, D.hval(D.revapp(xb, Nil{}), 0n), D.val(xb), hval_rev(xb)) :
    {bfeed(r2, D.St{D.dist_mode(FB(last), Nat.add(b1, _)), OX(x, pos, cap), bpC}) == rhs : D.St}
  %Equal.sym(Nat, Nat.add(b1, D.val(xb)), len, nat_eq(Nat.add(b1, D.val(xb)), len)(cl)) :
    {bfeed(r2, D.St{D.dist_mode(FB(last), _), OX(x, pos, cap), bpC}) == rhs : D.St}
  {==}

def dref.c(+last: Bool, +x: Bytes(), +pos: Nat, +cap: Nat, +bpD: Nat, +r3: List<&2, Bool>, +len: Nat, +q: Nat,
  +hq: {Nat.is_lt(q, 30n) == True{} : Bool}) ->
  {bfeed(r3, D.sym(D.SDist{FB(last), len}, q, OX(x, pos, cap), bpD)) ==
    bfeed(r3, D.dist_x(FB(last), len, D.nat_at(D.DBS(), q), D.nat_at(D.DXS(), q), OX(x, pos, cap), bpD)) : D.St}:
  %Equal.sym(Bool, Nat.is_lt(q, 30n), True{}, hq) :
    {bfeed(r3, D.dist(_, FB(last), len, q, OX(x, pos, cap), bpD)) ==
      bfeed(r3, D.dist_x(FB(last), len, D.nat_at(D.DBS(), q), D.nat_at(D.DXS(), q), OX(x, pos, cap), bpD)) : D.St}
  {==}

def dref.d(+last: Bool, +x: Bytes(), +pos: Nat, +end: Nat, +cap: Nat, +bpE: Nat, +s: List<&2, Bool>, +len: Nat,
  +dist: Nat, +q: Nat, +cd: {D.coded(D.DBS(), D.DXS(), q, dist) == True{} : Bool},
  +d1: {Nat.is_lt(0n, dist) == True{} : Bool}, +dle: {Nat.is_le(dist, pos) == True{} : Bool},
  +fit: {Nat.is_le(Nat.add(pos, len), end) == True{} : Bool}, +sm: {D.same(len, x, pos, dist) == True{} : Bool},
  +endle: {Nat.is_le(end, bl(x)) == True{} : Bool}, +capok: {Nat.is_le(bl(x), cap) == True{} : Bool}) ->
  {bfeed(s, D.copy(OX(x, pos, cap), len, Nat.add(D.nat_at(D.DBS(), q), D.hval(D.revapp(D.xbits(D.nat_at(D.DXS(), q),
    Nat.sub(dist, D.nat_at(D.DBS(), q))), Nil{}), 0n)), D.lit_mode(FB(last)), bpE)) ==
    bfeed(s, LS(last, x, Nat.add(pos, len), cap, bpE)) : D.St}:
  +b2 = D.nat_at(D.DBS(), q)
  +xb = D.xbits(D.nat_at(D.DXS(), q), Nat.sub(dist, b2))
  +t = String.take(x, pos)
  +rhs = bfeed(s, LS(last, x, Nat.add(pos, len), cap, bpE))
  +fitx = Nat.is_le_trans(Nat.add(pos, len), end, bl(x), fit, endle)
  +ple = le_right(pos, len, bl(x), fitx)
  +lent = Equal.trans(Nat, Bytes.len(t), bl(t), pos, blen(t), take_bl(x, pos)(ple))
  +near = Equal.trans(Bool, Nat.is_le(dist, Bytes.len(t)), Nat.is_le(dist, pos), True{},
    Equal.cong(Nat, Bool, y => Nat.is_le(dist, y), Bytes.len(t), pos, lent), dle)
  +room = Nat.is_le_trans(Nat.add(pos, len), bl(x), cap, fitx, capok)
  %Equal.sym(Nat, D.hval(D.revapp(xb, Nil{}), 0n), D.val(xb), hval_rev(xb)) :
    {bfeed(s, D.copy(OX(x, pos, cap), len, Nat.add(b2, _), D.lit_mode(FB(last)), bpE)) == rhs : D.St}
  %Equal.sym(Nat, Nat.add(b2, D.val(xb)), dist, nat_eq(Nat.add(b2, D.val(xb)), dist)(cd)) :
    {bfeed(s, D.copy(OX(x, pos, cap), len, _, D.lit_mode(FB(last)), bpE)) == rhs : D.St}
  Equal.cong(D.St, D.St, y => bfeed(s, y), D.copy(OX(x, pos, cap), len, dist, D.lit_mode(FB(last)), bpE),
    LS(last, x, Nat.add(pos, len), cap, bpE),
    Equal.trans(D.St, D.copy(D.O{t, 0n, pos, cap, D.tabs()}, len, dist, D.lit_mode(FB(last)), bpE),
      D.St{D.lit_mode(FB(last)), D.O{D.copy.go(len, t, dist), 0n, Nat.add(pos, len), cap, D.tabs()}, bpE},
      LS(last, x, Nat.add(pos, len), cap, bpE),
      Laws.copy_near(t, 0n, pos, cap, D.tabs(), len, dist, D.lit_mode(FB(last)), bpE, near, room),
      Equal.cong(Bytes(), D.St, y => D.St{D.lit_mode(FB(last)), D.O{y, 0n, Nat.add(pos, len), cap, D.tabs()}, bpE},
        D.copy.go(len, t, dist), String.take(x, Nat.add(pos, len)), copyx(len, x, pos, dist, sm, d1, dle, fitx))))

def dref(+last: Bool, +x: Bytes(), +pos: Nat, +end: Nat, +cap: Nat, +bp: Nat, +s: List<&2, Bool>, +len: Nat,
  +dist: Nat, +hk: {Nat.is_lt(kof(len), 29n) == True{} : Bool}, +hq: {Nat.is_lt(qof(dist), 30n) == True{} : Bool},
  +cl: {D.coded(D.LBS(), D.LXS(), kof(len), len) == True{} : Bool},
  +cd: {D.coded(D.DBS(), D.DXS(), qof(dist), dist) == True{} : Bool},
  +d1: {Nat.is_lt(0n, dist) == True{} : Bool}, +dle: {Nat.is_le(dist, pos) == True{} : Bool},
  +fit: {Nat.is_le(Nat.add(pos, len), end) == True{} : Bool}, +sm: {D.same(len, x, pos, dist) == True{} : Bool},
  +endle: {Nat.is_le(end, bl(x)) == True{} : Bool}, +capok: {Nat.is_le(bl(x), cap) == True{} : Bool}) ->
  {bfeed(tk(D.Ref{len, dist}, s), LS(last, x, pos, cap, bp)) ==
    bfeed(s, LS(last, x, Nat.add(pos, len), cap, adv(D.Ref{len, dist}, bp))) : D.St}:
  +k = kof(len)
  +q = qof(dist)
  +o = OX(x, pos, cap)
  +b1 = D.nat_at(D.LBS(), k)
  +e1 = D.nat_at(D.LXS(), k)
  +v1 = Nat.sub(len, b1)
  +b2 = D.nat_at(D.DBS(), q)
  +e2 = D.nat_at(D.DXS(), q)
  +v2 = Nat.sub(dist, b2)
  +r3 = app(D.xbits(e2, v2), s)
  +r2 = app(mbits(D.nat_at(D.HDL(), q), Bytes.get(D.HDC(), q)), r3)
  +r1 = app(D.xbits(e1, v1), r2)
  +bpA = advn(D.nat_at(D.HLLL(), L257(k)), bp)
  +bpC = advn(e1, bpA)
  +bpD = advn(D.nat_at(D.HDL(), q), bpC)
  +bpE = advn(e2, bpD)
  +end_st = bfeed(s, LS(last, x, Nat.add(pos, len), cap, bpE))
  Equal.trans(D.St, bfeed(tk(D.Ref{len, dist}, s), LS(last, x, pos, cap, bp)),
    bfeed(r1, D.sym(D.SLit{FB(last)}, L257(k), o, bpA)), end_st,
    sym_ll(L257(k), D.SLit{FB(last)}, o, bp, r1)(hk),
  Equal.trans(D.St, bfeed(r1, D.sym(D.SLit{FB(last)}, L257(k), o, bpA)), bfeed(r1, D.len_x(FB(last), b1, e1, o, bpA)),
    end_st, dref.a(last, x, pos, cap, bpA, r1, k, hk),
  Equal.trans(D.St, bfeed(r1, D.len_x(FB(last), b1, e1, o, bpA)),
    bfeed(r2, D.St{D.dist_mode(FB(last), Nat.add(b1, D.hval(D.revapp(D.xbits(e1, v1), Nil{}), 0n))), o, bpC}),
    end_st, len_x_e(e1, FB(last), b1, v1, o, bpA, r2)(lx14(k)(hk)),
  Equal.trans(D.St, bfeed(r2, D.St{D.dist_mode(FB(last), Nat.add(b1, D.hval(D.revapp(D.xbits(e1, v1), Nil{}), 0n))), o, bpC}),
    bfeed(r2, D.St{D.dist_mode(FB(last), len), o, bpC}), end_st, dref.b(last, x, pos, cap, bpC, r2, len, k, cl),
  Equal.trans(D.St, bfeed(r2, D.St{D.dist_mode(FB(last), len), o, bpC}),
    bfeed(r3, D.sym(D.SDist{FB(last), len}, q, o, bpD)), end_st,
    sym_d(q, D.SDist{FB(last), len}, o, bpC, r3)(hq),
  Equal.trans(D.St, bfeed(r3, D.sym(D.SDist{FB(last), len}, q, o, bpD)), bfeed(r3, D.dist_x(FB(last), len, b2, e2, o, bpD)),
    end_st, dref.c(last, x, pos, cap, bpD, r3, len, q, hq),
  Equal.trans(D.St, bfeed(r3, D.dist_x(FB(last), len, b2, e2, o, bpD)),
    bfeed(s, D.copy(o, len, Nat.add(b2, D.hval(D.revapp(D.xbits(e2, v2), Nil{}), 0n)), D.lit_mode(FB(last)), bpE)),
    end_st, dist_x_e(e2, FB(last), len, b2, v2, o, bpD, s)(dx14(q)(hq)),
    dref.d(last, x, pos, end, cap, bpE, s, len, dist, q, cd, d1, dle, fit, sm, endle, capok))))))))


# A checked run of tokens
# -----------------------

def tks(toks: List<&2, D.Tok>, s: List<&2, Bool>) -> List<&2, Bool>:
  match toks:
    case Nil{}:
      s
    case Con{t, r}:
      tk(t, tks(r, s))

def advs(toks: List<&2, D.Tok>, bp: Nat) -> Nat:
  match toks:
    case Nil{}:
      bp
    case Con{t, r}:
      advs(r, adv(t, bp))

def dtoks(+toks: List<&2, D.Tok>, +last: Bool, +x: Bytes(), +pos: Nat, +end: Nat, +cap: Nat, +bp: Nat,
  +s: List<&2, Bool>, +vx: {D.valid(x) == True{} : Bool}, +endle: {Nat.is_le(end, bl(x)) == True{} : Bool},
  +capok: {Nat.is_le(bl(x), cap) == True{} : Bool}, +ok: {D.ck(toks, x, pos, end) == True{} : Bool}) ->
  {bfeed(tks(toks, s), LS(last, x, pos, cap, bp)) == bfeed(s, LS(last, x, end, cap, advs(toks, bp))) : D.St}:
  match toks:
    case Nil{}:
      %nat_eq(pos, end)(ok) : {bfeed(s, LS(last, x, pos, cap, bp)) == bfeed(s, LS(last, x, _, cap, bp)) : D.St}
      {==}
    case Con{+tok, +r}:
      match tok:
        case D.Lit{+c}:
          +ab = Nat.is_lt(pos, end) && U32.is_eq(c, Bytes.get(x, pos))
          +o1 = Bool.and_l(ab, D.ck(r, x, 1n+pos, end), ok)
          +lt = Nat.is_lt_le_trans(pos, end, bl(x), Bool.and_l(Nat.is_lt(pos, end), U32.is_eq(c, Bytes.get(x, pos)), o1),
            endle)
          +ceq = u32_eq(c, Bytes.get(x, pos))(Bool.and_r(Nat.is_lt(pos, end), U32.is_eq(c, Bytes.get(x, pos)), o1))
          Equal.trans(D.St, bfeed(tk(D.Lit{c}, tks(r, s)), LS(last, x, pos, cap, bp)),
            bfeed(tks(r, s), LS(last, x, 1n+pos, cap, adv(D.Lit{c}, bp))),
            bfeed(s, LS(last, x, end, cap, advs(r, adv(D.Lit{c}, bp)))),
            dlit(last, x, pos, cap, bp, tks(r, s), c, vx, lt, ceq, capok),
            dtoks(r, last, x, 1n+pos, end, cap, adv(D.Lit{c}, bp), s, vx, endle, capok,
              Bool.and_r(ab, D.ck(r, x, 1n+pos, end), ok)))
        case D.Ref{+len, +dist}:
          +k = kof(len)
          +q = qof(dist)
          +ro = D.ref_ok(x, pos, end, len, dist)
          +rest = D.ck(r, x, Nat.add(pos, len), end)
          +a0 = Bool.and_l(ro, rest, ok)
          +cK = Nat.is_lt(k, 29n)
          +cQ = Nat.is_lt(q, 30n)
          +cL = D.coded(D.LBS(), D.LXS(), k, len)
          +cD = D.coded(D.DBS(), D.DXS(), q, dist)
          +c1 = Nat.is_lt(0n, dist)
          +cle = Nat.is_le(dist, pos)
          +cf = Nat.is_le(Nat.add(pos, len), end)
          +cs = D.same(len, x, pos, dist)
          +p1 = cK && cQ
          +p2 = p1 && cL
          +p3 = p2 && cD
          +p4 = p3 && c1
          +p5 = p4 && cle
          +p6 = p5 && cf
          +t6 = Bool.and_l(p6, cs, a0)
          +t5 = Bool.and_l(p5, cf, t6)
          +t4 = Bool.and_l(p4, cle, t5)
          +t3 = Bool.and_l(p3, c1, t4)
          +t2 = Bool.and_l(p2, cD, t3)
          +t1 = Bool.and_l(p1, cL, t2)
          Equal.trans(D.St, bfeed(tk(D.Ref{len, dist}, tks(r, s)), LS(last, x, pos, cap, bp)),
            bfeed(tks(r, s), LS(last, x, Nat.add(pos, len), cap, adv(D.Ref{len, dist}, bp))),
            bfeed(s, LS(last, x, end, cap, advs(r, adv(D.Ref{len, dist}, bp)))),
            dref(last, x, pos, end, cap, bp, tks(r, s), len, dist,
              Bool.and_l(cK, cQ, t1), Bool.and_r(cK, cQ, t1), Bool.and_r(p1, cL, t2), Bool.and_r(p2, cD, t3),
              Bool.and_r(p3, c1, t4), Bool.and_r(p4, cle, t5), Bool.and_r(p5, cf, t6), Bool.and_r(p6, cs, a0),
              endle, capok),
            dtoks(r, last, x, Nat.add(pos, len), end, cap, adv(D.Ref{len, dist}, bp), s, vx, endle, capok,
              Bool.and_r(ro, rest, ok)))

# The fixed block
# ---------------

def EOB() -> List<&2, Bool>:
  mbits(D.nat_at(D.HLLL(), 256n), Bytes.get(D.HLLC(), 256n))

def fbk(toks: List<&2, D.Tok>, last: Bool, s: List<&2, Bool>) -> List<&2, Bool>:
  Con{last, Con{True{}, Con{False{}, tks(toks, app(EOB(), s))}}}

# the machine at a block's header
def HS(+x: Bytes(), +pos: Nat, +cap: Nat, +bp: Nat) -> D.St:
  D.St{D.Get{2n, Nil{}, D.KHead{}}, OX(x, pos, cap), bp}

def bp3(+bp: Nat) -> Nat:
  D.next_bp(D.next_bp(D.next_bp(bp)))

def dblock(+toks: List<&2, D.Tok>, +last: Bool, +x: Bytes(), +pos: Nat, +end: Nat, +cap: Nat, +bp: Nat,
  +s: List<&2, Bool>, +vx: {D.valid(x) == True{} : Bool}, +endle: {Nat.is_le(end, bl(x)) == True{} : Bool},
  +capok: {Nat.is_le(bl(x), cap) == True{} : Bool}, +ok: {D.ck(toks, x, pos, end) == True{} : Bool}) ->
  {bfeed(fbk(toks, last, s), HS(x, pos, cap, bp)) ==
    bfeed(s, D.next_block(last, OX(x, end, cap), advn(D.nat_at(D.HLLL(), 256n), advs(toks, bp3(bp))))) : D.St}:
  +bt = advs(toks, bp3(bp))
  Equal.trans(D.St, bfeed(tks(toks, app(EOB(), s)), LS(last, x, pos, cap, bp3(bp))),
    bfeed(app(EOB(), s), LS(last, x, end, cap, bt)),
    bfeed(s, D.next_block(last, OX(x, end, cap), advn(D.nat_at(D.HLLL(), 256n), bt))),
    dtoks(toks, last, x, pos, end, cap, bp3(bp), app(EOB(), s), vx, endle, capok, ok),
    sym_ll(256n, D.SLit{FB(last)}, OX(x, end, cap), bt, s)({==}))

# The writer's side
# -----------------

def ECF() -> D.EC:
  D.ec_fixed(True{})

def sub1(+p: Nat) -> {Nat.sub(1n+p, 1n) == p : Nat}:
  match p:
    case 0n:
      {==}
    case 1n+q:
      {==}

def putm_k(+n: Nat, +w: D.W, +c: U32, +s: List<&2, Bool>) ->
  {app(wbits(D.putm(n, w, c)), s) == app(wbits(w), app(mbits(n, c), s)) : List<&2, Bool>}:
  match n:
    case 0n:
      {==}
    case 1n+p:
      %Equal.sym(Nat, Nat.sub(1n+p, 1n), p, sub1(p)) :
        {app(wbits(D.putm(p, D.put(w, D.bit(c, _)), c)), s) == app(wbits(w), app(mbits(1n+p, c), s)) : List<&2, Bool>}
      Equal.trans(List<&2, Bool>, app(wbits(D.putm(p, D.put(w, D.bit(c, p)), c)), s),
        app(wbits(D.put(w, D.bit(c, p))), app(mbits(p, c), s)), app(wbits(w), Con{D.bit(c, p), app(mbits(p, c), s)}),
        putm_k(p, D.put(w, D.bit(c, p)), c, s), put_k(w, D.bit(c, p), app(mbits(p, c), s)))

def wtok(tok: D.Tok, w: D.W) -> D.W:
  match tok:
    case D.Lit{+c}:
      D.put_sym(w, D.Hc{D.HLLC(), D.HLLL()}, U32.to_nat(c))
    case D.Ref{+len, +dist}:
      D.put_ref(w, D.Hc{D.HLLC(), D.HLLL()}, D.Hc{D.HDC(), D.HDL()}, D.LCS(), D.DCS(), D.LBS(), D.LXS(), D.DBS(), D.DXS(),
        len, dist)

def put_tok_eq(+tok: D.Tok, +w: D.W) -> {D.put_tok(tok, w, ECF()) == (wtok(tok, w), ECF()) : D.W & D.EC}:
  match tok:
    case D.Lit{+c}:
      {==}
    case D.Ref{+len, +dist}:
      {==}

def wtok_k(+tok: D.Tok, +w: D.W, +s: List<&2, Bool>) -> {app(wbits(wtok(tok, w)), s) == app(wbits(w), tk(tok, s)) : List<&2, Bool>}:
  match tok:
    case D.Lit{+c}:
      putm_k(D.nat_at(D.HLLL(), U32.to_nat(c)), w, Bytes.get(D.HLLC(), U32.to_nat(c)), s)
    case D.Ref{+len, +dist}:
      +k = kof(len)
      +q = qof(dist)
      +l1 = D.nat_at(D.HLLL(), L257(k))
      +c1 = Bytes.get(D.HLLC(), L257(k))
      +e1 = D.nat_at(D.LXS(), k)
      +v1 = Nat.sub(len, D.nat_at(D.LBS(), k))
      +l2 = D.nat_at(D.HDL(), q)
      +c2 = Bytes.get(D.HDC(), q)
      +e2 = D.nat_at(D.DXS(), q)
      +v2 = Nat.sub(dist, D.nat_at(D.DBS(), q))
      +w1 = D.putm(l1, w, c1)
      +w2 = D.putx(e1, w1, v1)
      +w3 = D.putm(l2, w2, c2)
      +s3 = app(D.xbits(e2, v2), s)
      +s2 = app(mbits(l2, c2), s3)
      +s1 = app(D.xbits(e1, v1), s2)
      Equal.trans(List<&2, Bool>, app(wbits(D.putx(e2, w3, v2)), s), app(wbits(w3), s3), app(wbits(w), app(mbits(l1, c1), s1)),
        putx_k(e2, w3, v2, s),
      Equal.trans(List<&2, Bool>, app(wbits(w3), s3), app(wbits(w2), s2), app(wbits(w), app(mbits(l1, c1), s1)),
        putm_k(l2, w2, c2, s3),
      Equal.trans(List<&2, Bool>, app(wbits(w2), s2), app(wbits(w1), s1), app(wbits(w), app(mbits(l1, c1), s1)),
        putx_k(e1, w1, v1, s2), putm_k(l1, w, c1, s1))))

def wtoks(toks: List<&2, D.Tok>, w: D.W) -> D.W:
  match toks:
    case Nil{}:
      w
    case Con{t, r}:
      wtoks(r, wtok(t, w))

def put_toks_eq(+toks: List<&2, D.Tok>, +w: D.W) -> {D.put_toks(toks, (w, ECF())) == (wtoks(toks, w), ECF()) : D.W & D.EC}:
  match toks:
    case Nil{}:
      {==}
    case Con{+t, +r}:
      %Equal.sym(D.W & D.EC, D.put_tok(t, w, ECF()), (wtok(t, w), ECF()), put_tok_eq(t, w)) : {D.put_toks(r, _) == (wtoks(r, wtok(t, w)), ECF()) : D.W & D.EC}
      put_toks_eq(r, wtok(t, w))

def wtoks_k(+toks: List<&2, D.Tok>, +w: D.W, +s: List<&2, Bool>) ->
  {app(wbits(wtoks(toks, w)), s) == app(wbits(w), tks(toks, s)) : List<&2, Bool>}:
  match toks:
    case Nil{}:
      {==}
    case Con{+t, +r}:
      Equal.trans(List<&2, Bool>, app(wbits(wtoks(r, wtok(t, w))), s), app(wbits(wtok(t, w)), tks(r, s)),
        app(wbits(w), tk(t, tks(r, s))), wtoks_k(r, wtok(t, w), s), wtok_k(t, w, tks(r, s)))

def w3h(+w: D.W, +last: Bool) -> D.W:
  D.put(D.put(D.put(w, last), True{}), False{})

def fb_eq(+toks: List<&2, D.Tok>, +w: D.W, +last: Bool) ->
  {D.fixed_block(toks, w, last, ECF()) == D.put_sym(wtoks(toks, w3h(w, last)), D.Hc{D.HLLC(), D.HLLL()}, 256n) : D.W}:
  %Equal.sym(D.W & D.EC, D.put_toks(toks, (w3h(w, last), ECF())), (wtoks(toks, w3h(w, last)), ECF()),
    put_toks_eq(toks, w3h(w, last))) :
    {D.dyn_block.at(D.put_body.at(_)) == D.put_sym(wtoks(toks, w3h(w, last)), D.Hc{D.HLLC(), D.HLLL()}, 256n) : D.W}
  {==}

# a fixed block's bits after the writer's
def fb_k(+toks: List<&2, D.Tok>, +w: D.W, +last: Bool, +s: List<&2, Bool>) ->
  {app(wbits(D.fixed_block(toks, w, last, ECF())), s) == app(wbits(w), fbk(toks, last, s)) : List<&2, Bool>}:
  +wt = wtoks(toks, w3h(w, last))
  +e0 = Equal.cong(D.W, List<&2, Bool>, y => app(wbits(y), s), D.fixed_block(toks, w, last, ECF()),
    D.put_sym(wt, D.Hc{D.HLLC(), D.HLLL()}, 256n), fb_eq(toks, w, last))
  +w1 = D.put(w, last)
  +w2 = D.put(w1, True{})
  Equal.trans(List<&2, Bool>, app(wbits(D.fixed_block(toks, w, last, ECF())), s),
    app(wbits(D.put_sym(wt, D.Hc{D.HLLC(), D.HLLL()}, 256n)), s), app(wbits(w), fbk(toks, last, s)), e0,
  Equal.trans(List<&2, Bool>, app(wbits(D.put_sym(wt, D.Hc{D.HLLC(), D.HLLL()}, 256n)), s), app(wbits(wt), app(EOB(), s)),
    app(wbits(w), fbk(toks, last, s)), putm_k(D.nat_at(D.HLLL(), 256n), wt, Bytes.get(D.HLLC(), 256n), s),
  Equal.trans(List<&2, Bool>, app(wbits(wt), app(EOB(), s)), app(wbits(w3h(w, last)), tks(toks, app(EOB(), s))),
    app(wbits(w), fbk(toks, last, s)), wtoks_k(toks, w3h(w, last), app(EOB(), s)),
  Equal.trans(List<&2, Bool>, app(wbits(D.put(w2, False{})), tks(toks, app(EOB(), s))),
    app(wbits(w2), Con{False{}, tks(toks, app(EOB(), s))}), app(wbits(w), fbk(toks, last, s)),
    put_k(w2, False{}, tks(toks, app(EOB(), s))),
  Equal.trans(List<&2, Bool>, app(wbits(w2), Con{False{}, tks(toks, app(EOB(), s))}),
    app(wbits(w1), Con{True{}, Con{False{}, tks(toks, app(EOB(), s))}}), app(wbits(w), fbk(toks, last, s)),
    put_k(w1, True{}, Con{False{}, tks(toks, app(EOB(), s))}),
    put_k(w, last, Con{True{}, Con{False{}, tks(toks, app(EOB(), s))}}))))))


# The writer's pending bits: never a whole byte
def pl(w: D.W) -> Nat:
  match w:
    case D.W{out, pend}:
      List.length(&2, Bool, pend)

def pl_put(+w: D.W, +b: Bool) -> {Nat.is_le(pl(w), 7n) == True{} : Bool} -> {Nat.is_le(pl(D.put(w, b)), 7n) == True{} : Bool}:
  match w:
    case D.W{+out, +pend}:
      match pend:
        case Nil{}:
          e => {==}
        case Con{+p0, +t0}:
          match t0:
            case Nil{}:
              e => {==}
            case Con{+p1, +t1}:
              match t1:
                case Nil{}:
                  e => {==}
                case Con{+p2, +t2}:
                  match t2:
                    case Nil{}:
                      e => {==}
                    case Con{+p3, +t3}:
                      match t3:
                        case Nil{}:
                          e => {==}
                        case Con{+p4, +t4}:
                          match t4:
                            case Nil{}:
                              e => {==}
                            case Con{+p5, +t5}:
                              match t5:
                                case Nil{}:
                                  e => {==}
                                case Con{+p6, +t6}:
                                  match t6:
                                    case Nil{}:
                                      e => {==}
                                    case Con{+q, +r}:
                                      e => Bool.no({Nat.is_le(pl(D.put(D.W{out, Con{p0, Con{p1, Con{p2, Con{p3, Con{p4, Con{p5, Con{p6, Con{q, r}}}}}}}}}, b)), 7n) == True{} : Bool}, e)


def pl_putx(+n: Nat, +w: D.W, +v: Nat) -> {Nat.is_le(pl(w), 7n) == True{} : Bool} ->
  {Nat.is_le(pl(D.putx(n, w, v)), 7n) == True{} : Bool}:
  match n:
    case 0n:
      h => h
    case 1n+p:
      h => pl_putx(p, D.put(w, Nat.is_eq(Nat.mod(v, 2n), 1n)), Nat.div(v, 2n))(pl_put(w, Nat.is_eq(Nat.mod(v, 2n), 1n))(h))

def pl_putm(+n: Nat, +w: D.W, +c: U32) -> {Nat.is_le(pl(w), 7n) == True{} : Bool} ->
  {Nat.is_le(pl(D.putm(n, w, c)), 7n) == True{} : Bool}:
  match n:
    case 0n:
      h => h
    case 1n+p:
      h =>
        %Equal.sym(Nat, Nat.sub(1n+p, 1n), p, sub1(p)) :
          {Nat.is_le(pl(D.putm(p, D.put(w, D.bit(c, _)), c)), 7n) == True{} : Bool}
        pl_putm(p, D.put(w, D.bit(c, p)), c)(pl_put(w, D.bit(c, p))(h))

def pl_wtok(+tok: D.Tok, +w: D.W) -> {Nat.is_le(pl(w), 7n) == True{} : Bool} ->
  {Nat.is_le(pl(wtok(tok, w)), 7n) == True{} : Bool}:
  match tok:
    case D.Lit{+c}:
      h => pl_putm(D.nat_at(D.HLLL(), U32.to_nat(c)), w, Bytes.get(D.HLLC(), U32.to_nat(c)))(h)
    case D.Ref{+len, +dist}:
      h =>
        +k = kof(len)
        +q = qof(dist)
        +w1 = D.putm(D.nat_at(D.HLLL(), L257(k)), w, Bytes.get(D.HLLC(), L257(k)))
        +w2 = D.putx(D.nat_at(D.LXS(), k), w1, Nat.sub(len, D.nat_at(D.LBS(), k)))
        +w3 = D.putm(D.nat_at(D.HDL(), q), w2, Bytes.get(D.HDC(), q))
        pl_putx(D.nat_at(D.DXS(), q), w3, Nat.sub(dist, D.nat_at(D.DBS(), q)))(
          pl_putm(D.nat_at(D.HDL(), q), w2, Bytes.get(D.HDC(), q))(
          pl_putx(D.nat_at(D.LXS(), k), w1, Nat.sub(len, D.nat_at(D.LBS(), k)))(
          pl_putm(D.nat_at(D.HLLL(), L257(k)), w, Bytes.get(D.HLLC(), L257(k)))(h))))

def pl_wtoks(+toks: List<&2, D.Tok>, +w: D.W) -> {Nat.is_le(pl(w), 7n) == True{} : Bool} ->
  {Nat.is_le(pl(wtoks(toks, w)), 7n) == True{} : Bool}:
  match toks:
    case Nil{}:
      h => h
    case Con{+t, +r}:
      h => pl_wtoks(r, wtok(t, w))(pl_wtok(t, w)(h))

def pl_fb(+toks: List<&2, D.Tok>, +w: D.W, +last: Bool) -> {Nat.is_le(pl(w), 7n) == True{} : Bool} ->
  {Nat.is_le(pl(D.fixed_block(toks, w, last, ECF())), 7n) == True{} : Bool}:
  h =>
    +wt = wtoks(toks, w3h(w, last))
    %Equal.sym(D.W, D.fixed_block(toks, w, last, ECF()), D.put_sym(wt, D.Hc{D.HLLC(), D.HLLL()}, 256n), fb_eq(toks, w, last)) :
      {Nat.is_le(pl(_), 7n) == True{} : Bool}
    pl_putm(D.nat_at(D.HLLL(), 256n), wt, Bytes.get(D.HLLC(), 256n))(pl_wtoks(toks, w3h(w, last))(
      pl_put(D.put(D.put(w, last), True{}), False{})(pl_put(D.put(w, last), True{})(pl_put(w, last)(h)))))

# The checks
# ----------

def lt_add_succ(+pos: Nat, +p: Nat) -> {Nat.is_lt(pos, Nat.add(pos, 1n+p)) == True{} : Bool}:
  match pos:
    case 0n:
      {==}
    case 1n+q:
      lt_add_succ(q, p)

# literals check out
def lits_ok(+n: Nat, +x: Bytes(), +pos: Nat) -> {D.ck(D.lits(n, x, pos), x, pos, Nat.add(pos, n)) == True{} : Bool}:
  match n:
    case 0n:
      %Equal.sym(Nat, Nat.add(pos, 0n), pos, add_zero(pos)) : {D.ck(Nil{}, x, pos, _) == True{} : Bool}
      nat_eq_refl(pos)
    case 1n+p:
      +e = Equal.sym(Nat, Nat.add(pos, 1n+p), 1n+Nat.add(pos, p), add_succ(pos, p))
      %Equal.sym(Bool, Nat.is_lt(pos, Nat.add(pos, 1n+p)), True{}, lt_add_succ(pos, p)) :
        {Bool.and(Bool.and(_, U32.is_eq(Bytes.get(x, pos), Bytes.get(x, pos))),
          D.ck(D.lits(p, x, 1n+pos), x, 1n+pos, Nat.add(pos, 1n+p))) == True{} : Bool}
      %Equal.sym(Bool, U32.is_eq(Bytes.get(x, pos), Bytes.get(x, pos)), True{}, u32_refl(Bytes.get(x, pos))) :
        {Bool.and(Bool.and(True{}, _), D.ck(D.lits(p, x, 1n+pos), x, 1n+pos, Nat.add(pos, 1n+p))) == True{} : Bool}
      %e : {Bool.and(Bool.and(True{}, True{}), D.ck(D.lits(p, x, 1n+pos), x, 1n+pos, _)) == True{} : Bool}
      lits_ok(p, x, 1n+pos)

def fixtoks_ok.at(+b: Bool, +toks: List<&2, D.Tok>, +x: Bytes(), +at: Nat, +len: Nat,
  e: {D.ck(toks, x, at, Nat.add(at, len)) == b : Bool}) ->
  {D.ck(D.fixtoks.at(b, toks, x, at, len), x, at, Nat.add(at, len)) == True{} : Bool}:
  match b:
    case True{}:
      e
    case False{}:
      lits_ok(len, x, at)

# what the fixed path writes checks out
def fixtoks_ok(+toks: List<&2, D.Tok>, +x: Bytes(), +at: Nat, +len: Nat) ->
  {D.ck(D.fixtoks(toks, x, at, len), x, at, Nat.add(at, len)) == True{} : Bool}:
  fixtoks_ok.at(D.ck(toks, x, at, Nat.add(at, len)), toks, x, at, len, {==})

# The blocks, one after another
# -----------------------------

def bpf(st: D.St) -> Nat:
  match st:
    case D.St{m, o, bp}:
      bp

# a checked block written after w, w's bits read to a header at bs
def blockP(+x: Bytes(), +cap: Nat, +bs: Nat, +len: Nat, +w: D.W, +toks: List<&2, D.Tok>, +last: Bool, +s0: D.St,
  +vx: {D.valid(x) == True{} : Bool}, +capok: {Nat.is_le(bl(x), cap) == True{} : Bool},
  +hw: {bfeed(wbits(w), s0) == HS(x, bs, cap, bpf(bfeed(wbits(w), s0))) : D.St},
  +hl: {Nat.is_le(Nat.add(bs, len), bl(x)) == True{} : Bool}) ->
  {bfeed(wbits(D.fixed_block(D.fixtoks(toks, x, bs, len), w, last, ECF())), s0) ==
    D.next_block(last, OX(x, Nat.add(bs, len), cap), advn(D.nat_at(D.HLLL(), 256n),
      advs(D.fixtoks(toks, x, bs, len), bp3(bpf(bfeed(wbits(w), s0)))))) : D.St}:
  +tt = D.fixtoks(toks, x, bs, len)
  +fb = D.fixed_block(tt, w, last, ECF())
  +bp = bpf(bfeed(wbits(w), s0))
  +fin = D.next_block(last, OX(x, Nat.add(bs, len), cap), advn(D.nat_at(D.HLLL(), 256n), advs(tt, bp3(bp))))
  Equal.trans(D.St, bfeed(wbits(fb), s0), bfeed(app(wbits(w), fbk(tt, last, Nil{})), s0), fin,
    Equal.cong(List<&2, Bool>, D.St, y => bfeed(y, s0), wbits(fb), app(wbits(w), fbk(tt, last, Nil{})),
      Equal.trans(List<&2, Bool>, wbits(fb), app(wbits(fb), Nil{}), app(wbits(w), fbk(tt, last, Nil{})),
        Equal.sym(List<&2, Bool>, app(wbits(fb), Nil{}), wbits(fb), app_nil(wbits(fb))), fb_k(tt, w, last, Nil{}))),
  Equal.trans(D.St, bfeed(app(wbits(w), fbk(tt, last, Nil{})), s0), bfeed(fbk(tt, last, Nil{}), bfeed(wbits(w), s0)), fin,
    bfeed_app(wbits(w), fbk(tt, last, Nil{}), s0),
  Equal.trans(D.St, bfeed(fbk(tt, last, Nil{}), bfeed(wbits(w), s0)), bfeed(fbk(tt, last, Nil{}), HS(x, bs, cap, bp)), fin,
    Equal.cong(D.St, D.St, y => bfeed(fbk(tt, last, Nil{}), y), bfeed(wbits(w), s0), HS(x, bs, cap, bp), hw),
    dblock(tt, last, x, bs, Nat.add(bs, len), cap, bp, Nil{}, vx, hl, capok, fixtoks_ok(toks, x, bs, len)))))


# a writer with a partial byte, aligned: all its bits are whole bytes
def alP(+out: Bytes(), +pend: List<&2, Bool>) -> {Nat.is_le(pl(D.W{out, pend}), 7n) == True{} : Bool} ->
  {wbits(D.align(D.W{out, pend})) == app(bitsof(D.w_out(D.align(D.W{out, pend}))), Nil{}) : List<&2, Bool>}:
  match pend:
    case Nil{}:
      e => {==}
    case Con{+p0, +t0}:
      match t0:
        case Nil{}:
          e => {==}
        case Con{+p1, +t1}:
          match t1:
            case Nil{}:
              e => {==}
            case Con{+p2, +t2}:
              match t2:
                case Nil{}:
                  e => {==}
                case Con{+p3, +t3}:
                  match t3:
                    case Nil{}:
                      e => {==}
                    case Con{+p4, +t4}:
                      match t4:
                        case Nil{}:
                          e => {==}
                        case Con{+p5, +t5}:
                          match t5:
                            case Nil{}:
                              e => {==}
                            case Con{+p6, +t6}:
                              match t6:
                                case Nil{}:
                                  e => {==}
                                case Con{+q, +r}:
                                  e => Bool.no({wbits(D.align(D.W{out, Con{p0, Con{p1, Con{p2, Con{p3, Con{p4, Con{p5, Con{p6, Con{q, r}}}}}}}}})) == app(bitsof(D.w_out(D.align(D.W{out, Con{p0, Con{p1, Con{p2, Con{p3, Con{p4, Con{p5, Con{p6, Con{q, r}}}}}}}}}))), Nil{}) : List<&2, Bool>}, e)

# The end
# -------

def advl(bs: List<&2, Bool>, bp: Nat) -> Nat:
  match bs:
    case Nil{}:
      bp
    case Con{b, t}:
      advl(t, D.next_bp(bp))

def endfeed(+bs: List<&2, Bool>, +o: D.O, +bp: Nat) -> {bfeed(bs, D.St{D.End{}, o, bp}) == D.St{D.End{}, o, advl(bs, bp)} : D.St}:
  match bs:
    case Nil{}:
      {==}
    case Con{+b, +t}:
      endfeed(t, o, D.next_bp(bp))

def mkO(+out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +tb: D.Tabs) -> D.O:
  D.O{out, keep, n, cap, tb}

# a stream at its end, aligned: what it read is what it hands out
def alignE(+w: D.W, +s0: D.St, +out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +tb: D.Tabs, +bp: Nat,
  +hp: {Nat.is_le(pl(w), 7n) == True{} : Bool},
  +he: {bfeed(wbits(w), s0) == D.St{D.End{}, D.O{out, keep, n, cap, tb}, bp} : D.St}) ->
  {D.finish(bfeed(bitsof(D.w_out(D.align(w))), s0)) == Done{Bytes.drop(out, keep)} : Result<&2, &2, D.Why, Bytes()>}:
  match w:
    case D.W{+wo, +pend}:
      +a = D.align(D.W{wo, pend})
      +m = Nat.mod(Nat.sub(8n, List.length(&2, Bool, pend)), 8n)
      +z = D.xbits(m, 0n)
      +o = mkO(out, keep, n, cap, tb)
      +eb = Equal.trans(List<&2, Bool>, bitsof(D.w_out(a)), app(bitsof(D.w_out(a)), Nil{}), app(wbits(D.W{wo, pend}), app(z, Nil{})),
        Equal.sym(List<&2, Bool>, app(bitsof(D.w_out(a)), Nil{}), bitsof(D.w_out(a)), app_nil(bitsof(D.w_out(a)))),
        Equal.trans(List<&2, Bool>, app(bitsof(D.w_out(a)), Nil{}), app(wbits(a), Nil{}), app(wbits(D.W{wo, pend}), app(z, Nil{})),
          Equal.trans(List<&2, Bool>, app(bitsof(D.w_out(a)), Nil{}), wbits(a), app(wbits(a), Nil{}),
            Equal.sym(List<&2, Bool>, wbits(a), app(bitsof(D.w_out(a)), Nil{}), alP(wo, pend)(hp)),
            Equal.sym(List<&2, Bool>, app(wbits(a), Nil{}), wbits(a), app_nil(wbits(a)))),
          putx_k(m, D.W{wo, pend}, 0n, Nil{})))
      +ef = Equal.trans(D.St, bfeed(bitsof(D.w_out(a)), s0), bfeed(app(wbits(D.W{wo, pend}), app(z, Nil{})), s0),
        D.St{D.End{}, o, advl(app(z, Nil{}), bp)},
        Equal.cong(List<&2, Bool>, D.St, y => bfeed(y, s0), bitsof(D.w_out(a)), app(wbits(D.W{wo, pend}), app(z, Nil{})), eb),
        Equal.trans(D.St, bfeed(app(wbits(D.W{wo, pend}), app(z, Nil{})), s0), bfeed(app(z, Nil{}), bfeed(wbits(D.W{wo, pend}), s0)),
          D.St{D.End{}, o, advl(app(z, Nil{}), bp)}, bfeed_app(wbits(D.W{wo, pend}), app(z, Nil{}), s0),
          Equal.trans(D.St, bfeed(app(z, Nil{}), bfeed(wbits(D.W{wo, pend}), s0)), bfeed(app(z, Nil{}), D.St{D.End{}, o, bp}),
            D.St{D.End{}, o, advl(app(z, Nil{}), bp)},
            Equal.cong(D.St, D.St, y => bfeed(app(z, Nil{}), y), bfeed(wbits(D.W{wo, pend}), s0), D.St{D.End{}, o, bp}, he),
            endfeed(app(z, Nil{}), o, bp))))
      Equal.cong(D.St, Result<&2, &2, D.Why, Bytes()>, D.finish, bfeed(bitsof(D.w_out(a)), s0),
        D.St{D.End{}, o, advl(app(z, Nil{}), bp)}, ef)

def hw0(+x: Bytes(), +cap: Nat) -> {bfeed(wbits(D.w_new()), D.new(cap)) == HS(x, 0n, cap, bpf(bfeed(wbits(D.w_new()), D.new(cap)))) : D.St}:
  %Equal.sym(Bytes(), String.take(x, 0n), "", take0(x)) :
    {D.new(cap) == D.St{D.Get{2n, Nil{}, D.KHead{}}, D.O{_, 0n, 0n, cap, D.tabs()}, 0n} : D.St}
  {==}

# the fixed stream of x, read from the start: x
def fixed_read(+x: Bytes(), +tt: List<&2, D.Tok>, +cap: Nat, +vx: {D.valid(x) == True{} : Bool},
  +capok: {Nat.is_le(bl(x), cap) == True{} : Bool}) ->
  {D.finish(bfeed(bitsof(D.w_out(D.align(D.fixed_block(D.fixtoks(tt, x, 0n, Bytes.len(x)), D.w_new(), True{}, ECF())))),
    D.new(cap))) == Done{x} : Result<&2, &2, D.Why, Bytes()>}:
  +n = Bytes.len(x)
  +fb = D.fixed_block(D.fixtoks(tt, x, 0n, n), D.w_new(), True{}, ECF())
  +en = blen(x)
  +hl = le_by(n, bl(x), bl(x), en, le_refl(bl(x)))
  +ex = Equal.trans(Bytes(), Bytes.drop(String.take(x, n), 0n), String.take(x, n), x, drop0(String.take(x, n)),
    Equal.trans(Bytes(), String.take(x, n), String.take(x, bl(x)), x,
      Equal.cong(Nat, Bytes(), y => String.take(x, y), n, bl(x), en), take_whole(x)))
  Equal.trans(Result<&2, &2, D.Why, Bytes()>, D.finish(bfeed(bitsof(D.w_out(D.align(fb))), D.new(cap))),
    Done{Bytes.drop(String.take(x, n), 0n)}, Done{x},
    alignE(fb, D.new(cap), String.take(x, n), 0n, n, cap, D.tabs(),
      advn(D.nat_at(D.HLLL(), 256n), advs(D.fixtoks(tt, x, 0n, n), bp3(bpf(bfeed(wbits(D.w_new()), D.new(cap)))))),
      pl_fb(D.fixtoks(tt, x, 0n, n), D.w_new(), True{})({==}),
      blockP(x, cap, 0n, n, D.w_new(), tt, True{}, D.new(cap), vx, capok, hw0(x, cap), hl)),
    Equal.cong(Bytes(), Result<&2, &2, D.Why, Bytes()>, y => Done{y}, Bytes.drop(String.take(x, n), 0n), x, ex))

def fixed_rt(+x: Bytes(), +lvl: Nat, +cap: Nat, +vx: {D.valid(x) == True{} : Bool},
  fits: {Nat.is_le(Bytes.len(x), cap) == True{} : Bool}) ->
  {D.finish(D.feed(D.deflate_fixed(x, lvl), D.new(cap))) == Done{x} : Result<&2, &2, D.Why, Bytes()>}:
  +d = D.deflate_fixed(x, lvl)
  +e = Equal.trans(D.St, D.feed(d, D.new(cap)), D.feed_list(Bytes.to_list(d), D.new(cap)), bfeed(bitsof(d), D.new(cap)),
    Laws.inflate_buf(d, D.new(cap)), feed_bits(d, D.new(cap)))
  %Equal.sym(D.St, D.feed(d, D.new(cap)), bfeed(bitsof(d), D.new(cap)), e) :
    {D.finish(_) == Done{x} : Result<&2, &2, D.Why, Bytes()>}
  fixed_read(x, D.lz_toks(D.lz_all(x, Nat.max(1n, lvl), True{})), cap, vx, le_by(bl(x), Bytes.len(x), cap, Equal.sym(Nat, Bytes.len(x), bl(x), blen(x)), fits))

def Laws.fixed_round_trip(x, lvl, cap, vx, fits):
  Equal.trans(Result<&2, &2, D.Why, Bytes()>, D.inflate(cap, D.deflate_fixed(x, lvl)),
    D.finish(D.feed(D.deflate_fixed(x, lvl), D.new(cap))), Done{x}, IP.inflate_fast(cap, D.deflate_fixed(x, lvl)),
    fixed_rt(x, lvl, cap, vx, fits))
