# The proofs of power/csv_laws.bend.
#
# feed_split, bad_feeds, feed_buf_is_feed, feed_buf_split and the reads'
# walk are the reader kit's laws (wire/reader.bend), proven once there
# for every reader and instantiated here at Csv.step. What is csv's own
# is the kit's obligation for the block walk, lem.adv: every move lands
# where stepping its bytes one at a time does. One byte is one step; a
# run is its bytes stepped one by one, each keeping the field's mode and
# adding itself (lem.stay), and the run stops where run.len says; a
# field entered by a run steps its first byte as the empty unquoted
# field does (lem.ent.step); after a refusal every byte is ignored. The
# fuel never matters (the kit's go_is_slow). csv_sim is an induction on
# a fuel that bounds the input: at every byte, from every mode, the
# reader and csv_spec.bend's grammar land in states the claim relates
# again (STEP), and at the end of input they read the same (END). The
# cases where the grammar reads CRLF as one symbol, or a byte of a field
# against its room, or a line end against the record's width, go through
# one lemma each (ECR, QCR, PUT, LE); their leaves are written out case
# by case.
import Base
import ../wire/reader.bend as Wr
import ./csv.bend as Csv
import ./csv_spec.bend as Spec
import ./csv_laws.bend as Laws

# The reads
# =========

def Laws.feed_split(d, a, b, p):
  Wr.feed_split(~Csv.Dialect, ~Csv.P, ~Csv.wstep, d, a, b, p)

# a refusal, as the kit's absorbing states: bad(x) for every x a
# refusal carries, each a fixed point of the step
type BadAt is Data:
  BadAt{at: Nat, why: Csv.Why, fl: Nat, cur: List<&2, Bytes()>,
    out: List<&2, List<&2, Bytes()>>, w: Maybe<&2, Nat>, pos: Nat}

def bad(x: BadAt) -> Csv.P:
  match x:
    case BadAt{at, why, fl, cur, out, w, pos}:
      Csv.P{Csv.Bad{at, why}, fl, cur, out, w, pos}

def absorbs(+d: Csv.Dialect, +x: BadAt, +c: U32) -> {Csv.wstep(d, bad(x), c) == bad(x) : Csv.P}:
  match x:
    case BadAt{at, why, fl, cur, out, w, pos}:
      {==}

def Laws.bad_feeds(d, s, at, why, fl, cur, out, w, pos):
  Wr.bad_feeds(~Csv.Dialect, ~Csv.P, ~Csv.wstep, ~BadAt, ~bad, ~absorbs, d, s,
    BadAt{at, why, fl, cur, out, w, pos})

# The walk
# --------

def app_nil(a: Bytes()) -> {Bytes.append(a, "") == a : Bytes()}:
  match a:
    case SNil{}:
      {==}
    case SCon{h, t}:
      %app_nil(t) : {SCon{h, Bytes.append(t, "")} == SCon{h, _} : Bytes()}
      {==}

def app_assoc(a: Bytes(), -b: Bytes(), -c: Bytes()) ->
  {Bytes.append(Bytes.append(a, b), c) == Bytes.append(a, Bytes.append(b, c)) : Bytes()}:
  match a:
    case SNil{}:
      {==}
    case SCon{h, t}:
      %app_assoc(t, b, c) : {SCon{h, Bytes.append(Bytes.append(t, b), c)} == SCon{h, _} : Bytes()}
      {==}

# a field grown by one byte, then by more, is the field grown by all of them
def push_app(acc: Bytes(), -c: U32, -x: Bytes()) ->
  {Bytes.append(Csv.push(acc, c), x) == Bytes.append(acc, SCon{Chr{c}, x}) : Bytes()}:
  app_assoc(acc, Csv.one(c), x)

def add_succ(a: Nat, -b: Nat) -> {Nat.add(a, 1n+b) == 1n+Nat.add(a, b) : Nat}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      %add_succ(p, b) : {1n+Nat.add(p, 1n+b) == 1n+_ : Nat}
      {==}

# anything, from False == True
def BD(b: Bool, tc: Type, fc: Type) -> Type:
  match b:
    case True{}:
      tc
    case False{}:
      fc

def no(-g: Type, e: {False{} == True{} : Bool}) -> g:
  %e : BD(_, g, Unit)
  Unit{}

# a Nat that is one more than something is not zero
def ZN(n: Nat, g: Type) -> Type:
  match n:
    case 0n:
      Unit
    case 1n+p:
      g

# One byte
def lem.one(+d: Csv.Dialect, p: Csv.P, s: Bytes()) ->
  {Csv.feed_buf.last(d, Csv.one.step(d, p, s)) == Csv.feed_buf.slow(d, s, p) : Csv.P}:
  match s:
    case SNil{}:
      {==}
    case SCon{Chr{c}, t}:
      {==}

# A run
# -----

# a byte a run stays on is one step keeps the field on, one byte longer
def SG(+d: Csv.Dialect, -q: Bool, -k: Csv.K, -c: U32, -acc: Bytes(), -l: Nat, -fl: Nat,
  -cur: List<&2, Bytes()>, -out: List<&2, List<&2, Bytes()>>, -w: Maybe<&2, Nat>, -pos: Nat) ->
  Type:
  {Csv.step.at(d, Csv.grow(q, acc, 1n+l), k, c, fl, cur, out, w, pos) ==
    Csv.P{Csv.grow(q, Csv.push(acc, c), l), fl, cur, out, w, 1n+pos} : Csv.P}

def lem.stay(+d: Csv.Dialect, q: Bool, k: Csv.K, -c: U32, -acc: Bytes(), -l: Nat, -fl: Nat,
  -cur: List<&2, Bytes()>, -out: List<&2, List<&2, Bytes()>>, -w: Maybe<&2, Nat>, -pos: Nat) ->
  {Csv.stay(q, k) == True{} : Bool} -> SG(d, q, k, c, acc, l, fl, cur, out, w, pos):
  match q k:
    case True{} Csv.KQ{}:
      e => no(SG(d, True{}, Csv.KQ{}, c, acc, l, fl, cur, out, w, pos), e)
    case True{} Csv.KD{}:
      e => {==}
    case True{} Csv.KCR{}:
      e => {==}
    case True{} Csv.KLF{}:
      e => {==}
    case True{} Csv.KO{}:
      e => {==}
    case False{} Csv.KQ{}:
      e => no(SG(d, False{}, Csv.KQ{}, c, acc, l, fl, cur, out, w, pos), e)
    case False{} Csv.KD{}:
      e => no(SG(d, False{}, Csv.KD{}, c, acc, l, fl, cur, out, w, pos), e)
    case False{} Csv.KCR{}:
      e => no(SG(d, False{}, Csv.KCR{}, c, acc, l, fl, cur, out, w, pos), e)
    case False{} Csv.KLF{}:
      e => no(SG(d, False{}, Csv.KLF{}, c, acc, l, fl, cur, out, w, pos), e)
    case False{} Csv.KO{}:
      e => {==}

def lem.len0(+d: Csv.Dialect, t: Bytes(), -q: Bool, -l: Nat) ->
  {Csv.run.len(d, t, False{}, q, l, 0n) == 0n : Nat}:
  match t:
    case SNil{}:
      {==}
    case SCon{Chr{x}, u}:
      {==}

def lem.shift.at(
  +d: Csv.Dialect, -u: Bytes(), -q: Bool, -l: Nat, -k: Nat, ok: Bool,
  ht: {Csv.run.len(d, u, True{}, q, l, 1n+1n+k) == 1n+Csv.run.len(d, u, True{}, q, l, 1n+k) : Nat},
  hf: {Csv.run.len(d, u, False{}, q, l, 1n+k) == 1n+Csv.run.len(d, u, False{}, q, l, k) : Nat}
) -> {Csv.run.len(d, u, ok, q, l, Csv.inc(ok, 1n+k)) ==
  1n+Csv.run.len(d, u, ok, q, l, Csv.inc(ok, k)) : Nat}:
  match ok:
    case True{}:
      ht
    case False{}:
      hf

# counting from k + 1 is counting from k, plus one
def lem.shift(+d: Csv.Dialect, +t: Bytes(), go: Bool, +q: Bool, +left: Nat, +k: Nat) ->
  {Csv.run.len(d, t, go, q, left, 1n+k) == 1n+Csv.run.len(d, t, go, q, left, k) : Nat}:
  match t go left:
    case SNil{} _ _:
      {==}
    case SCon{Chr{x}, u} False{} _:
      {==}
    case SCon{Chr{x}, u} True{} 0n:
      {==}
    case SCon{Chr{c}, u} True{} 1n+l:
      lem.shift.at(d, u, q, l, k, Csv.stay(q, Csv.cls(d, c)),
        lem.shift(d, u, True{}, q, l, 1n+k), lem.shift(d, u, False{}, q, l, k))

# what a run takes of s, stepped a byte at a time, is the field with
# those bytes added, and what follows is walked from there
def RL(+d: Csv.Dialect, +s: Bytes(), +q: Bool, +left: Nat) -> Nat:
  Csv.run.len(d, s, True{}, q, left, 0n)

def RG(+d: Csv.Dialect, +s: Bytes(), +q: Bool, +acc: Bytes(), +left: Nat, +fl: Nat,
  +cur: List<&2, Bytes()>, +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat) ->
  Type:
  {Csv.feed_buf.slow(d, s, Csv.P{Csv.grow(q, acc, left), fl, cur, out, w, pos}) ==
    Csv.feed_buf.slow(d, String.drop(s, RL(d, s, q, left)),
      Csv.P{Csv.grow(q, Bytes.append(acc, String.take(s, RL(d, s, q, left))),
        Nat.sub(left, RL(d, s, q, left))), fl, cur, out, w, Nat.add(RL(d, s, q, left), pos)}) :
    Csv.P}

def lem.run.at(
  +d: Csv.Dialect, +q: Bool, +c: U32, +t: Bytes(), +acc: Bytes(), +l: Nat, +fl: Nat,
  +cur: List<&2, Bytes()>, +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat,
  ok: Bool, ih: RG(d, t, q, Csv.push(acc, c), l, fl, cur, out, w, 1n+pos)
) -> {Csv.stay(q, Csv.cls(d, c)) == ok : Bool} ->
  RG(d, SCon{Chr{c}, t}, q, acc, 1n+l, fl, cur, out, w, pos):
  match ok:
    case True{}:
      +e =>
        %Equal.sym(Bool, Csv.stay(q, Csv.cls(d, c)), True{}, e) :
          {Csv.feed_buf.slow(d, t, Csv.step.at(d, Csv.grow(q, acc, 1n+l), Csv.cls(d, c), c, fl, cur,
            out, w, pos)) ==
            Csv.feed_buf.slow(d, String.drop(SCon{Chr{c}, t}, Csv.run.len(d, t, _, q, l, Csv.inc(_, 0n))),
              Csv.P{Csv.grow(q, Bytes.append(acc, String.take(SCon{Chr{c}, t},
                Csv.run.len(d, t, _, q, l, Csv.inc(_, 0n)))),
                Nat.sub(1n+l, Csv.run.len(d, t, _, q, l, Csv.inc(_, 0n)))), fl, cur, out, w,
                Nat.add(Csv.run.len(d, t, _, q, l, Csv.inc(_, 0n)), pos)}) : Csv.P}
        %Equal.sym(Nat, Csv.run.len(d, t, True{}, q, l, 1n), 1n+Csv.run.len(d, t, True{}, q, l, 0n),
          lem.shift(d, t, True{}, q, l, 0n)) :
          {Csv.feed_buf.slow(d, t, Csv.step.at(d, Csv.grow(q, acc, 1n+l), Csv.cls(d, c), c, fl, cur,
            out, w, pos)) ==
            Csv.feed_buf.slow(d, String.drop(SCon{Chr{c}, t}, _),
              Csv.P{Csv.grow(q, Bytes.append(acc, String.take(SCon{Chr{c}, t}, _)),
                Nat.sub(1n+l, _)), fl, cur, out, w, Nat.add(_, pos)}) : Csv.P}
        %Equal.sym(Csv.P, Csv.step.at(d, Csv.grow(q, acc, 1n+l), Csv.cls(d, c), c, fl, cur, out, w, pos),
          Csv.P{Csv.grow(q, Csv.push(acc, c), l), fl, cur, out, w, 1n+pos},
          lem.stay(d, q, Csv.cls(d, c), c, acc, l, fl, cur, out, w, pos)(e)) :
          {Csv.feed_buf.slow(d, t, _) ==
            Csv.feed_buf.slow(d, String.drop(t, RL(d, t, q, l)),
              Csv.P{Csv.grow(q, Bytes.append(acc, SCon{Chr{c}, String.take(t, RL(d, t, q, l))}),
                Nat.sub(l, RL(d, t, q, l))), fl, cur, out, w, 1n+Nat.add(RL(d, t, q, l), pos)}) : Csv.P}
        %push_app(acc, c, String.take(t, RL(d, t, q, l))) :
          {Csv.feed_buf.slow(d, t, Csv.P{Csv.grow(q, Csv.push(acc, c), l), fl, cur, out, w, 1n+pos}) ==
            Csv.feed_buf.slow(d, String.drop(t, RL(d, t, q, l)),
              Csv.P{Csv.grow(q, _, Nat.sub(l, RL(d, t, q, l))), fl, cur, out, w,
                1n+Nat.add(RL(d, t, q, l), pos)}) : Csv.P}
        %add_succ(RL(d, t, q, l), pos) :
          {Csv.feed_buf.slow(d, t, Csv.P{Csv.grow(q, Csv.push(acc, c), l), fl, cur, out, w, 1n+pos}) ==
            Csv.feed_buf.slow(d, String.drop(t, RL(d, t, q, l)),
              Csv.P{Csv.grow(q, Bytes.append(Csv.push(acc, c), String.take(t, RL(d, t, q, l))),
                Nat.sub(l, RL(d, t, q, l))), fl, cur, out, w, _}) : Csv.P}
        ih
    case False{}:
      e =>
        %Equal.sym(Bool, Csv.stay(q, Csv.cls(d, c)), False{}, e) :
          {Csv.feed_buf.slow(d, t, Csv.step.at(d, Csv.grow(q, acc, 1n+l), Csv.cls(d, c), c, fl, cur,
            out, w, pos)) ==
            Csv.feed_buf.slow(d, String.drop(SCon{Chr{c}, t}, Csv.run.len(d, t, _, q, l, Csv.inc(_, 0n))),
              Csv.P{Csv.grow(q, Bytes.append(acc, String.take(SCon{Chr{c}, t},
                Csv.run.len(d, t, _, q, l, Csv.inc(_, 0n)))),
                Nat.sub(1n+l, Csv.run.len(d, t, _, q, l, Csv.inc(_, 0n)))), fl, cur, out, w,
                Nat.add(Csv.run.len(d, t, _, q, l, Csv.inc(_, 0n)), pos)}) : Csv.P}
        %Equal.sym(Nat, Csv.run.len(d, t, False{}, q, l, 0n), 0n, lem.len0(d, t, q, l)) :
          {Csv.feed_buf.slow(d, t, Csv.step.at(d, Csv.grow(q, acc, 1n+l), Csv.cls(d, c), c, fl, cur,
            out, w, pos)) ==
            Csv.feed_buf.slow(d, String.drop(SCon{Chr{c}, t}, _),
              Csv.P{Csv.grow(q, Bytes.append(acc, String.take(SCon{Chr{c}, t}, _)),
                Nat.sub(1n+l, _)), fl, cur, out, w, Nat.add(_, pos)}) : Csv.P}
        %Equal.sym(Bytes(), Bytes.append(acc, ""), acc, app_nil(acc)) :
          {Csv.feed_buf.slow(d, t, Csv.step.at(d, Csv.grow(q, acc, 1n+l), Csv.cls(d, c), c, fl, cur,
            out, w, pos)) ==
            Csv.feed_buf.slow(d, t, Csv.step.at(d, Csv.grow(q, _, 1n+l), Csv.cls(d, c), c, fl, cur,
              out, w, pos)) : Csv.P}
        {==}

def lem.run(+d: Csv.Dialect, +s: Bytes(), +q: Bool, +acc: Bytes(), +left: Nat, +fl: Nat,
  +cur: List<&2, Bytes()>, +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat) ->
  RG(d, s, q, acc, left, fl, cur, out, w, pos):
  match s left:
    case SNil{} 0n:
      %Equal.sym(Bytes(), Bytes.append(acc, ""), acc, app_nil(acc)) :
        {Csv.P{Csv.grow(q, acc, 0n), fl, cur, out, w, pos} ==
          Csv.P{Csv.grow(q, _, 0n), fl, cur, out, w, pos} : Csv.P}
      {==}
    case SNil{} 1n+l:
      %Equal.sym(Bytes(), Bytes.append(acc, ""), acc, app_nil(acc)) :
        {Csv.P{Csv.grow(q, acc, 1n+l), fl, cur, out, w, pos} ==
          Csv.P{Csv.grow(q, _, 1n+l), fl, cur, out, w, pos} : Csv.P}
      {==}
    case SCon{Chr{x}, t} 0n:
      %Equal.sym(Bytes(), Bytes.append(acc, ""), acc, app_nil(acc)) :
        {Csv.feed_buf.slow(d, SCon{Chr{x}, t}, Csv.P{Csv.grow(q, acc, 0n), fl, cur, out, w, pos}) ==
          Csv.feed_buf.slow(d, SCon{Chr{x}, t}, Csv.P{Csv.grow(q, _, 0n), fl, cur, out, w, pos}) : Csv.P}
      {==}
    case SCon{Chr{c}, t} 1n+l:
      lem.run.at(d, q, c, t, acc, l, fl, cur, out, w, pos, Csv.stay(q, Csv.cls(d, c)),
        lem.run(d, t, q, Csv.push(acc, c), l, fl, cur, out, w, 1n+pos))({==})

# The finds
# ---------

# run.fast finds where a run ends with Bytes.find_byte (between quotes)
# and Bytes.find_any (outside), each testing a byte as cls does, in its
# order: the quote, the delimiter, CR, LF. lem.fast: it counts what
# run.len does, so the walk is the same walk.

# stay, as the tests a find is written with
def lem.stay.q(x1: Bool, x2: Bool, x3: Bool, x4: Bool) ->
  {Csv.stay(True{}, Csv.k.pick(x1, Csv.KQ{}, Csv.k.pick(x2, Csv.KD{}, Csv.k.pick(x3, Csv.KCR{},
    Csv.k.pick(x4, Csv.KLF{}, Csv.KO{}))))) == Bool.not(x1) : Bool}:
  match x1 x2 x3 x4:
    case True{} True{} True{} True{}:
      {==}
    case True{} True{} True{} False{}:
      {==}
    case True{} True{} False{} True{}:
      {==}
    case True{} True{} False{} False{}:
      {==}
    case True{} False{} True{} True{}:
      {==}
    case True{} False{} True{} False{}:
      {==}
    case True{} False{} False{} True{}:
      {==}
    case True{} False{} False{} False{}:
      {==}
    case False{} True{} True{} True{}:
      {==}
    case False{} True{} True{} False{}:
      {==}
    case False{} True{} False{} True{}:
      {==}
    case False{} True{} False{} False{}:
      {==}
    case False{} False{} True{} True{}:
      {==}
    case False{} False{} True{} False{}:
      {==}
    case False{} False{} False{} True{}:
      {==}
    case False{} False{} False{} False{}:
      {==}

def lem.stay.u(x1: Bool, x2: Bool, x3: Bool, x4: Bool) ->
  {Csv.stay(False{}, Csv.k.pick(x1, Csv.KQ{}, Csv.k.pick(x2, Csv.KD{}, Csv.k.pick(x3, Csv.KCR{},
    Csv.k.pick(x4, Csv.KLF{}, Csv.KO{}))))) ==
    Bool.not(Bool.or(x1, Bool.or(x2, Bool.or(x3, x4)))) : Bool}:
  match x1 x2 x3 x4:
    case True{} True{} True{} True{}:
      {==}
    case True{} True{} True{} False{}:
      {==}
    case True{} True{} False{} True{}:
      {==}
    case True{} True{} False{} False{}:
      {==}
    case True{} False{} True{} True{}:
      {==}
    case True{} False{} True{} False{}:
      {==}
    case True{} False{} False{} True{}:
      {==}
    case True{} False{} False{} False{}:
      {==}
    case False{} True{} True{} True{}:
      {==}
    case False{} True{} True{} False{}:
      {==}
    case False{} True{} False{} True{}:
      {==}
    case False{} True{} False{} False{}:
      {==}
    case False{} False{} True{} True{}:
      {==}
    case False{} False{} True{} False{}:
      {==}
    case False{} False{} False{} True{}:
      {==}
    case False{} False{} False{} False{}:
      {==}

# between quotes: the byte stays exactly when the find's test says no
def lem.st.q(+d: Csv.Dialect, +c: U32, h: Bool) ->
  {U32.is_eq(c, Csv.quote(d)) == h : Bool} -> {Csv.stay(True{}, Csv.cls(d, c)) == Bool.not(h) : Bool}:
  e => Equal.trans(Bool, Csv.stay(True{}, Csv.cls(d, c)), Bool.not(U32.is_eq(c, Csv.quote(d))), Bool.not(h),
    lem.stay.q(U32.is_eq(c, Csv.quote(d)), U32.is_eq(c, Csv.delim(d)), U32.is_eq(c, 13),
      U32.is_eq(c, 10)),
    Equal.cong(Bool, Bool, b => Bool.not(b), U32.is_eq(c, Csv.quote(d)), h, e))

def FQ(+d: Csv.Dialect, +s: Bytes(), +left: Nat) -> Type:
  {Csv.run.len(d, s, True{}, True{}, left, 0n) == Csv.cap(left, Bytes.find_byte.go(s, Csv.quote(d))) : Nat}

def lem.fq.at(+d: Csv.Dialect, +c: U32, +t: Bytes(), +l: Nat, h: Bool, ih: FQ(d, t, l)) ->
  {U32.is_eq(c, Csv.quote(d)) == h : Bool} ->
  {Csv.run.len(d, SCon{Chr{c}, t}, True{}, True{}, 1n+l, 0n) ==
    Csv.cap(1n+l, Bytes.find_byte.at(h, t, Csv.quote(d))) : Nat}:
  match h:
    case True{}:
      e =>
        %Equal.sym(Bool, Csv.stay(True{}, Csv.cls(d, c)), False{}, lem.st.q(d, c, True{})(e)) :
          {Csv.run.len(d, t, _, True{}, l, Csv.inc(_, 0n)) == 0n : Nat}
        lem.len0(d, t, True{}, l)
    case False{}:
      e =>
        %Equal.sym(Bool, Csv.stay(True{}, Csv.cls(d, c)), True{}, lem.st.q(d, c, False{})(e)) :
          {Csv.run.len(d, t, _, True{}, l, Csv.inc(_, 0n)) ==
            1n+Csv.cap(l, Bytes.find_byte.go(t, Csv.quote(d))) : Nat}
        Equal.trans(Nat, Csv.run.len(d, t, True{}, True{}, l, 1n),
          1n+Csv.run.len(d, t, True{}, True{}, l, 0n),
          1n+Csv.cap(l, Bytes.find_byte.go(t, Csv.quote(d))),
          lem.shift(d, t, True{}, True{}, l, 0n),
          Equal.cong(Nat, Nat, y => 1n+y, Csv.run.len(d, t, True{}, True{}, l, 0n),
            Csv.cap(l, Bytes.find_byte.go(t, Csv.quote(d))), ih))

def lem.fq(+d: Csv.Dialect, +s: Bytes(), +left: Nat) -> FQ(d, s, left):
  match s left:
    case SNil{} 0n:
      {==}
    case SNil{} 1n+l:
      {==}
    case SCon{Chr{x}, u} 0n:
      {==}
    case SCon{Chr{+c}, t} 1n+l:
      lem.fq.at(d, c, t, l, U32.is_eq(c, Csv.quote(d)), lem.fq(d, t, l))({==})

# outside quotes: the byte stays exactly when the find's test says no
def lem.st.u(+d: Csv.Dialect, +c: U32, h: Bool) ->
  {Bytes.find_any.in(c, Csv.quote(d), Csv.delim(d), 13, 10) == h : Bool} -> {Csv.stay(False{}, Csv.cls(d, c)) == Bool.not(h) : Bool}:
  e => Equal.trans(Bool, Csv.stay(False{}, Csv.cls(d, c)), Bool.not(Bytes.find_any.in(c, Csv.quote(d), Csv.delim(d), 13, 10)), Bool.not(h),
    lem.stay.u(U32.is_eq(c, Csv.quote(d)), U32.is_eq(c, Csv.delim(d)), U32.is_eq(c, 13),
      U32.is_eq(c, 10)),
    Equal.cong(Bool, Bool, b => Bool.not(b), Bytes.find_any.in(c, Csv.quote(d), Csv.delim(d), 13, 10), h, e))

def FU(+d: Csv.Dialect, +s: Bytes(), +left: Nat) -> Type:
  {Csv.run.len(d, s, True{}, False{}, left, 0n) == Csv.cap(left, Bytes.find_any.go(s, Csv.quote(d), Csv.delim(d), 13, 10)) : Nat}

def lem.fu.at(+d: Csv.Dialect, +c: U32, +t: Bytes(), +l: Nat, h: Bool, ih: FU(d, t, l)) ->
  {Bytes.find_any.in(c, Csv.quote(d), Csv.delim(d), 13, 10) == h : Bool} ->
  {Csv.run.len(d, SCon{Chr{c}, t}, True{}, False{}, 1n+l, 0n) ==
    Csv.cap(1n+l, Bytes.find_any.at(h, t, Csv.quote(d), Csv.delim(d), 13, 10)) : Nat}:
  match h:
    case True{}:
      e =>
        %Equal.sym(Bool, Csv.stay(False{}, Csv.cls(d, c)), False{}, lem.st.u(d, c, True{})(e)) :
          {Csv.run.len(d, t, _, False{}, l, Csv.inc(_, 0n)) == 0n : Nat}
        lem.len0(d, t, False{}, l)
    case False{}:
      e =>
        %Equal.sym(Bool, Csv.stay(False{}, Csv.cls(d, c)), True{}, lem.st.u(d, c, False{})(e)) :
          {Csv.run.len(d, t, _, False{}, l, Csv.inc(_, 0n)) ==
            1n+Csv.cap(l, Bytes.find_any.go(t, Csv.quote(d), Csv.delim(d), 13, 10)) : Nat}
        Equal.trans(Nat, Csv.run.len(d, t, True{}, False{}, l, 1n),
          1n+Csv.run.len(d, t, True{}, False{}, l, 0n),
          1n+Csv.cap(l, Bytes.find_any.go(t, Csv.quote(d), Csv.delim(d), 13, 10)),
          lem.shift(d, t, True{}, False{}, l, 0n),
          Equal.cong(Nat, Nat, y => 1n+y, Csv.run.len(d, t, True{}, False{}, l, 0n),
            Csv.cap(l, Bytes.find_any.go(t, Csv.quote(d), Csv.delim(d), 13, 10)), ih))

def lem.fu(+d: Csv.Dialect, +s: Bytes(), +left: Nat) -> FU(d, s, left):
  match s left:
    case SNil{} 0n:
      {==}
    case SNil{} 1n+l:
      {==}
    case SCon{Chr{x}, u} 0n:
      {==}
    case SCon{Chr{+c}, t} 1n+l:
      lem.fu.at(d, c, t, l, Bytes.find_any.in(c, Csv.quote(d), Csv.delim(d), 13, 10), lem.fu(d, t, l))({==})

# run.fast counts what run.len does
def lem.fast(+d: Csv.Dialect, +s: Bytes(), q: Bool, +left: Nat) ->
  {RL(d, s, q, left) == Csv.run.fast(d, s, q, left) : Nat}:
  match s q:
    case SNil{} True{}:
      lem.fq(d, SNil{}, left)
    case SCon{h, t} True{}:
      lem.fq(d, SCon{h, t}, left)
    case SNil{} False{}:
      lem.fu(d, SNil{}, left)
    case SCon{h, t} False{}:
      lem.fu(d, SCon{h, t}, left)

# a run cut where run.len says: the cut's two halves are what RG names
def lem.cut.took(+d: Csv.Dialect, +q: Bool, +acc: Bytes(), +left: Nat, +s: Bytes(), +fl: Nat,
  +cur: List<&2, Bytes()>, +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat,
  j: Nat, e: {RL(d, s, q, left) == 1n+j : Nat}) ->
  {Csv.feed_buf.slow(d, String.drop(s, 1n+j),
    Csv.P{Csv.grow(q, Bytes.append(acc, String.take(s, 1n+j)), Nat.sub(left, 1n+j)), fl, cur, out,
      w, Nat.add(1n+j, pos)}) ==
    Csv.feed_buf.slow(d, s, Csv.P{Csv.grow(q, acc, left), fl, cur, out, w, pos}) : Csv.P}:
  %e : {Csv.feed_buf.slow(d, String.drop(s, _),
    Csv.P{Csv.grow(q, Bytes.append(acc, String.take(s, _)), Nat.sub(left, _)), fl, cur, out, w,
      Nat.add(_, pos)}) ==
    Csv.feed_buf.slow(d, s, Csv.P{Csv.grow(q, acc, left), fl, cur, out, w, pos}) : Csv.P}
  Equal.sym(Csv.P, Csv.feed_buf.slow(d, s, Csv.P{Csv.grow(q, acc, left), fl, cur, out, w, pos}),
    Csv.feed_buf.slow(d, String.drop(s, RL(d, s, q, left)),
      Csv.P{Csv.grow(q, Bytes.append(acc, String.take(s, RL(d, s, q, left))),
        Nat.sub(left, RL(d, s, q, left))), fl, cur, out, w, Nat.add(RL(d, s, q, left), pos)}),
    lem.run(d, s, q, acc, left, fl, cur, out, w, pos))

def lem.took(+d: Csv.Dialect, +q: Bool, +acc: Bytes(), +left: Nat, +s: Bytes(), +fl: Nat,
  +cur: List<&2, Bytes()>, +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat,
  +j: Nat, e: {RL(d, s, q, left) == 1n+j : Nat}) ->
  {Csv.feed_buf.last(d, Csv.run.took(d, q, acc, left, j, fl, cur, out, w, pos, String.cut(s, 1n+j))) ==
    Csv.feed_buf.slow(d, s, Csv.P{Csv.grow(q, acc, left), fl, cur, out, w, pos}) : Csv.P}:
  Equal.trans(Csv.P,
    Csv.feed_buf.last(d, Csv.one.step(d,
      Csv.P{Csv.grow(q, Bytes.append(acc, String.take(s, 1n+j)), Nat.sub(left, 1n+j)), fl, cur, out,
        w, Nat.add(1n+j, pos)}, String.drop(s, 1n+j))),
    Csv.feed_buf.slow(d, String.drop(s, 1n+j),
      Csv.P{Csv.grow(q, Bytes.append(acc, String.take(s, 1n+j)), Nat.sub(left, 1n+j)), fl, cur, out,
        w, Nat.add(1n+j, pos)}),
    Csv.feed_buf.slow(d, s, Csv.P{Csv.grow(q, acc, left), fl, cur, out, w, pos}),
    lem.one(d, Csv.P{Csv.grow(q, Bytes.append(acc, String.take(s, 1n+j)), Nat.sub(left, 1n+j)), fl,
      cur, out, w, Nat.add(1n+j, pos)}, String.drop(s, 1n+j)),
    lem.cut.took(d, q, acc, left, s, fl, cur, out, w, pos, j, e))

def lem.cut(+d: Csv.Dialect, +q: Bool, +acc: Bytes(), +left: Nat, +s: Bytes(), +fl: Nat,
  +cur: List<&2, Bytes()>, +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat,
  +k: Nat) ->
  {RL(d, s, q, left) == k : Nat} ->
  {Csv.feed_buf.last(d, Csv.run.cut(d, q, acc, left, s, fl, cur, out, w, pos, k)) ==
    Csv.feed_buf.slow(d, s, Csv.P{Csv.grow(q, acc, left), fl, cur, out, w, pos}) : Csv.P}:
  match k:
    case 0n:
      e => lem.one(d, Csv.P{Csv.grow(q, acc, left), fl, cur, out, w, pos}, s)
    case 1n+j:
      e => lem.took(d, q, acc, left, s, fl, cur, out, w, pos, j, e)

def lem.go.run(+d: Csv.Dialect, +q: Bool, +acc: Bytes(), +left: Nat, +s: Bytes(), +fl: Nat,
  +cur: List<&2, Bytes()>, +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat) ->
  {Csv.feed_buf.last(d, Csv.run.go(d, q, acc, left, s, fl, cur, out, w, pos)) ==
    Csv.feed_buf.slow(d, s, Csv.P{Csv.grow(q, acc, left), fl, cur, out, w, pos}) : Csv.P}:
  lem.cut(d, q, acc, left, s, fl, cur, out, w, pos, Csv.run.fast(d, s, q, left))(lem.fast(d, s, q, left))

# A field from its first byte
# ---------------------------

def ent.m(isr: Bool) -> Csv.Mode:
  match isr:
    case True{}:
      Csv.RS{}
    case False{}:
      Csv.FS{}

def ent.ko(+d: Csv.Dialect, isr: Bool, -c: U32, -fl: Nat, -cur: List<&2, Bytes()>,
  -out: List<&2, List<&2, Bytes()>>, -w: Maybe<&2, Nat>, -pos: Nat) ->
  {Csv.step.at(d, ent.m(isr), Csv.KO{}, c, fl, cur, out, w, pos) ==
    Csv.step.at(d, Csv.Unq{"", Csv.max_field(d)}, Csv.KO{}, c, fl, cur, out, w, pos) : Csv.P}:
  match isr:
    case True{}:
      {==}
    case False{}:
      {==}

# the start of a field steps a byte an unquoted run stays on exactly as
# the empty unquoted field does
def lem.ent.step(+d: Csv.Dialect, isr: Bool, k: Csv.K, -c: U32, -fl: Nat, -cur: List<&2, Bytes()>,
  -out: List<&2, List<&2, Bytes()>>, -w: Maybe<&2, Nat>, -pos: Nat) ->
  {Csv.stay(False{}, k) == True{} : Bool} ->
  {Csv.step.at(d, ent.m(isr), k, c, fl, cur, out, w, pos) ==
    Csv.step.at(d, Csv.Unq{"", Csv.max_field(d)}, k, c, fl, cur, out, w, pos) : Csv.P}:
  match k:
    case Csv.KQ{}:
      e => no({Csv.step.at(d, ent.m(isr), Csv.KQ{}, c, fl, cur, out, w, pos) ==
        Csv.step.at(d, Csv.Unq{"", Csv.max_field(d)}, Csv.KQ{}, c, fl, cur, out, w, pos) : Csv.P}, e)
    case Csv.KD{}:
      e => no({Csv.step.at(d, ent.m(isr), Csv.KD{}, c, fl, cur, out, w, pos) ==
        Csv.step.at(d, Csv.Unq{"", Csv.max_field(d)}, Csv.KD{}, c, fl, cur, out, w, pos) : Csv.P}, e)
    case Csv.KCR{}:
      e => no({Csv.step.at(d, ent.m(isr), Csv.KCR{}, c, fl, cur, out, w, pos) ==
        Csv.step.at(d, Csv.Unq{"", Csv.max_field(d)}, Csv.KCR{}, c, fl, cur, out, w, pos) : Csv.P}, e)
    case Csv.KLF{}:
      e => no({Csv.step.at(d, ent.m(isr), Csv.KLF{}, c, fl, cur, out, w, pos) ==
        Csv.step.at(d, Csv.Unq{"", Csv.max_field(d)}, Csv.KLF{}, c, fl, cur, out, w, pos) : Csv.P}, e)
    case Csv.KO{}:
      e => ent.ko(d, isr, c, fl, cur, out, w, pos)

def EG(+d: Csv.Dialect, -isr: Bool, -s: Bytes(), -fl: Nat, -cur: List<&2, Bytes()>,
  -out: List<&2, List<&2, Bytes()>>, -w: Maybe<&2, Nat>, -pos: Nat) -> Type:
  {Csv.feed_buf.slow(d, s, Csv.P{Csv.Unq{"", Csv.max_field(d)}, fl, cur, out, w, pos}) ==
    Csv.feed_buf.slow(d, s, Csv.P{ent.m(isr), fl, cur, out, w, pos}) : Csv.P}

def lem.ent.at(+d: Csv.Dialect, +isr: Bool, +c: U32, +t: Bytes(), +fl: Nat,
  +cur: List<&2, Bytes()>, +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat,
  +l: Nat, j: Nat, ok: Bool) ->
  {Csv.stay(False{}, Csv.cls(d, c)) == ok : Bool} ->
  {Csv.run.len(d, t, ok, False{}, l, Csv.inc(ok, 0n)) == 1n+j : Nat} ->
  EG(d, isr, SCon{Chr{c}, t}, fl, cur, out, w, pos):
  match ok:
    case True{}:
      st => eq =>
        %lem.ent.step(d, isr, Csv.cls(d, c), c, fl, cur, out, w, pos)(st) :
          {Csv.feed_buf.slow(d, t, _) ==
            Csv.feed_buf.slow(d, t, Csv.step.at(d, ent.m(isr), Csv.cls(d, c), c, fl, cur, out, w, pos)) :
            Csv.P}
        {==}
    case False{}:
      st => eq =>
        %Equal.trans(Nat, 0n, Csv.run.len(d, t, False{}, False{}, l, 0n), 1n+j,
          Equal.sym(Nat, Csv.run.len(d, t, False{}, False{}, l, 0n), 0n, lem.len0(d, t, False{}, l)),
          eq) : ZN(_, EG(d, isr, SCon{Chr{c}, t}, fl, cur, out, w, pos))
        Unit{}

# the run's room is the dialect's max_field; a run of one byte or more
# means the first byte stays and the room is not zero
def lem.ent.first(+d: Csv.Dialect, +isr: Bool, s: Bytes(), +mf: Nat, +fl: Nat,
  +cur: List<&2, Bytes()>, +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat,
  j: Nat) ->
  {Csv.max_field(d) == mf : Nat} ->
  {Csv.run.len(d, s, True{}, False{}, mf, 0n) == 1n+j : Nat} -> EG(d, isr, s, fl, cur, out, w, pos):
  match s mf:
    case SNil{} _:
      em => eq =>
        %eq : ZN(_, EG(d, isr, SNil{}, fl, cur, out, w, pos))
        Unit{}
    case SCon{Chr{c}, t} 0n:
      em => eq =>
        %eq : ZN(_, EG(d, isr, SCon{Chr{c}, t}, fl, cur, out, w, pos))
        Unit{}
    case SCon{Chr{+c}, t} 1n+l:
      em => eq => lem.ent.at(d, isr, c, t, fl, cur, out, w, pos, l, j,
        Csv.stay(False{}, Csv.cls(d, c)))({==}, eq)

def lem.ent.cut(+d: Csv.Dialect, +isr: Bool, +s: Bytes(), +fl: Nat, +cur: List<&2, Bytes()>,
  +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat, +k: Nat) ->
  {RL(d, s, False{}, Csv.max_field(d)) == k : Nat} ->
  {Csv.feed_buf.last(d, Csv.ent.cut(d, ent.m(isr), s, fl, cur, out, w, pos, k)) ==
    Csv.feed_buf.slow(d, s, Csv.P{ent.m(isr), fl, cur, out, w, pos}) : Csv.P}:
  match k:
    case 0n:
      eq => lem.one(d, Csv.P{ent.m(isr), fl, cur, out, w, pos}, s)
    case 1n+j:
      +eq => Equal.trans(Csv.P,
        Csv.feed_buf.last(d, Csv.run.took(d, False{}, "", Csv.max_field(d), j, fl, cur, out, w, pos,
          String.cut(s, 1n+j))),
        Csv.feed_buf.slow(d, s, Csv.P{Csv.Unq{"", Csv.max_field(d)}, fl, cur, out, w, pos}),
        Csv.feed_buf.slow(d, s, Csv.P{ent.m(isr), fl, cur, out, w, pos}),
        lem.took(d, False{}, "", Csv.max_field(d), s, fl, cur, out, w, pos, j, eq),
        lem.ent.first(d, isr, s, Csv.max_field(d), fl, cur, out, w, pos, j)({==}, eq))

def lem.ent(+d: Csv.Dialect, +isr: Bool, +s: Bytes(), +fl: Nat, +cur: List<&2, Bytes()>,
  +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat) ->
  {Csv.feed_buf.last(d, Csv.ent.go(d, ent.m(isr), s, fl, cur, out, w, pos)) ==
    Csv.feed_buf.slow(d, s, Csv.P{ent.m(isr), fl, cur, out, w, pos}) : Csv.P}:
  lem.ent.cut(d, isr, s, fl, cur, out, w, pos, Csv.run.fast(d, s, False{}, Csv.max_field(d)))(
    lem.fast(d, s, False{}, Csv.max_field(d)))

# After a refusal
def lem.bad(+d: Csv.Dialect, s: Bytes(), -at: Nat, -why: Csv.Why, -fl: Nat, -cur: List<&2, Bytes()>,
  -out: List<&2, List<&2, Bytes()>>, -w: Maybe<&2, Nat>, -pos: Nat) ->
  {Csv.feed_buf.slow(d, s, Csv.P{Csv.Bad{at, why}, fl, cur, out, w, pos}) ==
    Csv.P{Csv.Bad{at, why}, fl, cur, out, w, pos} : Csv.P}:
  match s:
    case SNil{}:
      {==}
    case SCon{Chr{c}, t}:
      lem.bad(d, t, at, why, fl, cur, out, w, pos)

# Every move
def lem.adv.at(+d: Csv.Dialect, m: Csv.Mode, +s: Bytes(), +fl: Nat, +cur: List<&2, Bytes()>,
  +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat) ->
  {Csv.feed_buf.last(d, Csv.adv.at(d, m, s, fl, cur, out, w, pos)) ==
    Csv.feed_buf.slow(d, s, Csv.P{m, fl, cur, out, w, pos}) : Csv.P}:
  match m:
    case Csv.RS{}:
      lem.ent(d, True{}, s, fl, cur, out, w, pos)
    case Csv.FS{}:
      lem.ent(d, False{}, s, fl, cur, out, w, pos)
    case Csv.Unq{acc, left}:
      lem.go.run(d, False{}, acc, left, s, fl, cur, out, w, pos)
    case Csv.Quo{acc, left}:
      lem.go.run(d, True{}, acc, left, s, fl, cur, out, w, pos)
    case Csv.QQ{acc, left}:
      lem.one(d, Csv.P{Csv.QQ{acc, left}, fl, cur, out, w, pos}, s)
    case Csv.CRp{acc, at}:
      lem.one(d, Csv.P{Csv.CRp{acc, at}, fl, cur, out, w, pos}, s)
    case Csv.Bad{at, why}:
      Equal.sym(Csv.P, Csv.feed_buf.slow(d, s, Csv.P{Csv.Bad{at, why}, fl, cur, out, w, pos}),
        Csv.P{Csv.Bad{at, why}, fl, cur, out, w, pos}, lem.bad(d, s, at, why, fl, cur, out, w, pos))

def lem.adv(+d: Csv.Dialect, +s: Bytes(), p: Csv.P) ->
  {Csv.feed_buf.last(d, Csv.adv(d, s, p)) == Csv.feed_buf.slow(d, s, p) : Csv.P}:
  match p:
    case Csv.P{m, fl, cur, out, w, pos}:
      lem.adv.at(d, m, s, fl, cur, out, w, pos)

# the kit's obligation: every move lands where stepping its bytes does
def adv_ok(+d: Csv.Dialect, +s: Bytes(), p: Csv.P) ->
  {Wr.feed_buf.last(~Csv.Dialect, ~Csv.P, ~Csv.wstep, d, Csv.wadv(d, s, p)) ==
    Wr.feed_buf.slow(~Csv.Dialect, ~Csv.P, ~Csv.wstep, d, s, p) : Csv.P}:
  lem.adv(d, s, p)

# the fuel never matters (the kit's go_is_slow)
def lem.go(+d: Csv.Dialect, n: Nat, q: Csv.P & Bytes()) ->
  {Wr.feed_buf.go(~Csv.Dialect, ~Csv.P, ~Csv.wstep, ~Csv.wadv, d, n, q) == Csv.feed_buf.last(d, q) :
    Csv.P}:
  Wr.go_is_slow(~Csv.Dialect, ~Csv.P, ~Csv.wstep, ~Csv.wadv, ~adv_ok, d, n, q)

def Laws.feed_buf_is_feed(d, b, p):
  Wr.feed_buf_is_feed(~Csv.Dialect, ~Csv.P, ~Csv.wstep, ~Csv.wadv, ~adv_ok, d, b, p)

def Laws.feed_buf_split(d, a, b, p):
  Wr.feed_buf_split(~Csv.Dialect, ~Csv.P, ~Csv.wstep, ~Csv.wadv, ~adv_ok, d, a, b, p)

# The grammar
# ===========
#
# csv_sim is an induction on the input that follows the reader byte by
# byte and the grammar production by production. It runs on the input's
# marks -- each byte with its class -- so the reader and the grammar see
# the same class for a byte by construction, and the classes are shown
# to be the grammar's own once, at the start (kind_is_cls). The spec
# reads CRLF two bytes at a time where the reader holds the CR (CRp),
# so the induction is on a fuel that bounds the input rather than on
# the input itself: a case that looks at the byte after a CR still has
# the whole rest to recurse on.

# the reader fed marks: each byte stepped with its mark's class
def stepk(+d: Csv.Dialect, p: Csv.P, x: Spec.Mark) -> Csv.P:
  match p:
    case Csv.P{m, fl, cur, out, w, pos}:
      match x:
        case Spec.Mark{k, c}:
          Csv.step.at(d, m, k, c, fl, cur, out, w, pos)

def feedk(+d: Csv.Dialect, ms: List<&2, Spec.Mark>, p: Csv.P) -> Csv.P:
  match ms:
    case Nil{}:
      p
    case Con{x, t}:
      feedk(d, t, stepk(d, p, x))

# what the reader reads of the marks, from p, to the end of input
def R(+d: Csv.Dialect, ms: List<&2, Spec.Mark>, p: Csv.P) -> Csv.Out:
  Csv.result(d, Csv.finish(d, feedk(d, ms, p)))

# the classes are the grammar's
def kind_cls(b1: Bool, b2: Bool, b3: Bool, b4: Bool) ->
  {Spec.kind.if(b1, Csv.KQ{}, Spec.kind.if(b2, Csv.KD{}, Spec.kind.if(b3, Csv.KCR{},
    Spec.kind.if(b4, Csv.KLF{}, Csv.KO{})))) ==
    Csv.k.pick(b1, Csv.KQ{}, Csv.k.pick(b2, Csv.KD{}, Csv.k.pick(b3, Csv.KCR{},
      Csv.k.pick(b4, Csv.KLF{}, Csv.KO{})))) : Csv.K}:
  match b1 b2 b3 b4:
    case True{} _ _ _:
      {==}
    case False{} True{} _ _:
      {==}
    case False{} False{} True{} _:
      {==}
    case False{} False{} False{} True{}:
      {==}
    case False{} False{} False{} False{}:
      {==}

def kind_is_cls(d: Csv.Dialect, +c: U32) -> {Spec.kind(d, c) == Csv.cls(d, c) : Csv.K}:
  match d:
    case Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}:
      kind_cls(U32.is_eq(c, q), U32.is_eq(c, dl), U32.is_eq(c, 13), U32.is_eq(c, 10))

def step_k(+d: Csv.Dialect, p: Csv.P, +c: U32) ->
  {Csv.step(d, p, c) == stepk(d, p, Spec.Mark{Csv.cls(d, c), c}) : Csv.P}:
  match p:
    case Csv.P{m, fl, cur, out, w, pos}:
      {==}

# the reader over bytes is the reader over their marks
def feed_is_feedk(+d: Csv.Dialect, bs: List<&2, U32>, +p: Csv.P) ->
  {Csv.feed(d, bs, p) == feedk(d, Spec.marks(d, bs), p) : Csv.P}:
  match bs:
    case Nil{}:
      {==}
    case Con{+c, t}:
      %Equal.sym(Csv.K, Spec.kind(d, c), Csv.cls(d, c), kind_is_cls(d, c)) :
        {Csv.feed(d, t, Csv.step(d, p, c)) ==
          feedk(d, Spec.marks(d, t), stepk(d, p, Spec.Mark{_, c})) : Csv.P}
      %Equal.sym(Csv.P, Csv.step(d, p, c), stepk(d, p, Spec.Mark{Csv.cls(d, c), c}), step_k(d, p, c)) :
        {Csv.feed(d, t, _) == feedk(d, Spec.marks(d, t), stepk(d, p, Spec.Mark{Csv.cls(d, c), c})) :
          Csv.P}
      feed_is_feedk(d, t, stepk(d, p, Spec.Mark{Csv.cls(d, c), c}))

# a refused reader reads the refusal, whatever follows
def BADR(+d: Csv.Dialect, ms: List<&2, Spec.Mark>, -at: Nat, -why: Csv.Why, -fl: Nat,
  -cur: List<&2, Bytes()>, -out: List<&2, List<&2, Bytes()>>, -w: Maybe<&2, Nat>, -pos: Nat) ->
  {R(d, ms, Csv.P{Csv.Bad{at, why}, fl, cur, out, w, pos}) == Csv.Refused{at, why} : Csv.Out}:
  match ms:
    case Nil{}:
      {==}
    case Con{x, t}:
      match x:
        case Spec.Mark{k, c}:
          BADR(d, t, at, why, fl, cur, out, w, pos)

def absurd(-g: Type, e: Empty) -> g:
  match e:

# the header, taken the same way
def tbl(h: Bool, xs: List<&2, List<&2, Bytes()>>) ->
  {Csv.table.at(h, xs) == Spec.done.as(h, xs) : Csv.Out}:
  match h xs:
    case True{} Nil{}:
      {==}
    case True{} Con{r, t}:
      {==}
    case False{} _:
      {==}

# the fuel bounds the marks
def LEb(ms: List<&2, Spec.Mark>, n: Nat) -> Type:
  match ms n:
    case Nil{} _:
      Unit
    case Con{x, t} 0n:
      Empty
    case Con{x, t} 1n+k:
      LEb(t, k)

def lb.tail(-x: Spec.Mark, u: List<&2, Spec.Mark>, k: Nat) -> LEb(Con{x, u}, k) -> LEb(u, k):
  match u k:
    case Nil{} _:
      e => Unit{}
    case Con{y, v} 0n:
      e => absurd(LEb(Con{y, v}, 0n), e)
    case Con{y, v} 1n+j:
      e => lb.tail(y, v, j)(e)

def lb.refl(ms: List<&2, Spec.Mark>) -> LEb(ms, List.length(&2, Spec.Mark, ms)):
  match ms:
    case Nil{}:
      Unit{}
    case Con{x, t}:
      lb.refl(t)

# the grammar's production for a reader mode
def at_of(m: Csv.Mode) -> Spec.At:
  match m:
    case Csv.RS{}:
      Spec.Record{}
    case Csv.FS{}:
      Spec.Field{}
    case Csv.Unq{a, l}:
      Spec.Plain{a, l}
    case Csv.Quo{a, l}:
      Spec.Quoted{a, l}
    case Csv.QQ{a, l}:
      Spec.Closed{a, l}
    case Csv.CRp{a, at}:
      Spec.Record{}
    case Csv.Bad{at, why}:
      Spec.Record{}

# a CR held and a refusal are not modes the grammar is ever in
def Pre(m: Csv.Mode) -> Type:
  match m:
    case Csv.CRp{a, at}:
      Empty
    case Csv.Bad{at, why}:
      Empty
    case _:
      Unit

def lexd(+d: Csv.Dialect, ms: List<&2, Spec.Mark>) -> List<&2, Spec.Lx>:
  Spec.lex(ms, Spec.takes_crlf(d), Spec.takes_cr(d), Spec.takes_lf(d))

# the reader in mode m reads what the grammar in m's production reads
def SIM(-d: Csv.Dialect, -ms: List<&2, Spec.Mark>, -m: Csv.Mode, -fl: Nat, -cur: List<&2, Bytes()>,
  -out: List<&2, List<&2, Bytes()>>, -w: Maybe<&2, Nat>, -pos: Nat) -> Type:
  {R(d, ms, Csv.P{m, fl, cur, out, w, pos}) ==
    Spec.go(lexd(d, ms), d, at_of(m), fl, cur, out, w, pos) : Csv.Out}

# what the induction hands a case: the claim for every input the fuel k
# bounds, from every mode
def IH(-k: Nat, -d: Csv.Dialect) -> Type:
  @ms: List<&2, Spec.Mark> -> @m: Csv.Mode -> @fl: Nat -> @cur: List<&2, Bytes()> ->
    @out: List<&2, List<&2, Bytes()>> -> @w: Maybe<&2, Nat> -> @pos: Nat ->
    LEb(ms, k) -> Pre(m) -> SIM(d, ms, m, fl, cur, out, w, pos)

# Ends of fields and records
# --------------------------

# a record's end, continued: G is what the reader reads from the state
# after it, k what the grammar reads
def HK(-d: Csv.Dialect, -G: Csv.P -> Csv.Out,
  -k: List<&2, List<&2, Bytes()>> -> Maybe<&2, Nat> -> Csv.Out, -np: Nat) -> Type:
  @o: List<&2, List<&2, Bytes()>> -> @x: Maybe<&2, Nat> ->
    {G(Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, o, x, np}) == k(o, x) : Csv.Out}

def HB(-G: Csv.P -> Csv.Out) -> Type:
  @a2: Nat -> @y: Csv.Why -> @f: Nat -> @c2: List<&2, Bytes()> -> @o2: List<&2, List<&2, Bytes()>> ->
    @w2: Maybe<&2, Nat> -> @p2: Nat ->
    {G(Csv.P{Csv.Bad{a2, y}, f, c2, o2, w2, p2}) == Csv.Refused{a2, y} : Csv.Out}

def LE.w(ok: Bool, +d: Csv.Dialect, +rec: List<&2, Bytes()>, +out: List<&2, List<&2, Bytes()>>,
  +x: Nat, +at: Nat, +np: Nat, -G: Csv.P -> Csv.Out,
  -k: List<&2, List<&2, Bytes()>> -> Maybe<&2, Nat> -> Csv.Out) ->
  HK(d, G, k, np) -> HB(G) ->
  {G(Csv.endr.ok(ok, d, rec, out, x, at, Csv.RS{}, np)) == Spec.wide(ok, rec, out, x, at, k) : Csv.Out}:
  match ok:
    case True{}:
      hk => hb => hk(Con{rec, out}, Some{x})
    case False{}:
      hk => hb => hb(at, Csv.Ragged{}, 0n, Nil{}, out, Some{x}, at)

# LEMMA: a line end, read by both: the same refusal, or the same record
# kept and the same state after it
def LE(+d: Csv.Dialect, +text: Bytes(), fl: Nat, +cur: List<&2, Bytes()>,
  +out: List<&2, List<&2, Bytes()>>, w: Maybe<&2, Nat>, +at: Nat, +np: Nat, -G: Csv.P -> Csv.Out,
  -k: List<&2, List<&2, Bytes()>> -> Maybe<&2, Nat> -> Csv.Out) ->
  HK(d, G, k, np) -> HB(G) ->
  {G(Csv.endl(d, text, fl, cur, out, w, at, np)) == Spec.line.end(d, text, fl, cur, out, w, at, k) :
    Csv.Out}:
  match d:
    case Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}:
      match fl:
        case 0n:
          hk => hb => hb(at, Csv.TooManyFields{}, 0n, cur, out, w, at)
        case 1n+f:
          match w:
            case None{}:
              hk => hb => hk(Con{List.reverse(&2, Bytes(), Con{text, cur}), out}, Some{f})
            case Some{+x}:
              LE.w(Bool.or(rg, Nat.is_eq(f, x)), Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd},
                List.reverse(&2, Bytes(), Con{text, cur}), out, x, at, np, G, k)

def hb.r(+d: Csv.Dialect, +ms: List<&2, Spec.Mark>) -> HB(p => R(d, ms, p)):
  a2 => y => f => c2 => o2 => w2 => p2 => BADR(d, ms, a2, y, f, c2, o2, w2, p2)

# LEMMA: a field's end at a delimiter
def FEL(fl: Nat, +d: Csv.Dialect, +text: Bytes(), +cur: List<&2, Bytes()>,
  +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat, +t: List<&2, Spec.Mark>) ->
  (@f: Nat -> @gs: List<&2, Bytes()> -> SIM(d, t, Csv.FS{}, f, gs, out, w, 1n+pos)) ->
  {R(d, t, Csv.endf(text, fl, cur, out, w, pos, Csv.FS{}, 1n+pos)) ==
    Spec.field.end(fl, text, cur, pos, m => gs => Spec.go(lexd(d, t), d, Spec.Field{}, m, gs, out, w,
      1n+pos)) : Csv.Out}:
  match fl:
    case 0n:
      h => BADR(d, t, pos, Csv.TooManyFields{}, 0n, cur, out, w, pos)
    case 1n+f:
      h => h(f, Con{text, cur})

# LEMMA: a byte of a field, if it has room
def PUT(l: Nat, +q: Bool, +d: Csv.Dialect, +c: U32, +acc: Bytes(), +fl: Nat,
  +cur: List<&2, Bytes()>, +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat,
  +t: List<&2, Spec.Mark>) ->
  (@l2: Nat -> SIM(d, t, Csv.grow(q, Csv.push(acc, c), l2), fl, cur, out, w, 1n+pos)) ->
  {R(d, t, Csv.put(q, c, acc, l, fl, cur, out, w, pos)) ==
    Spec.room(l, pos, m => Spec.go(lexd(d, t), d, at_of(Csv.grow(q, Csv.push(acc, c), m)), fl, cur,
      out, w, 1n+pos)) : Csv.Out}:
  match l:
    case 0n:
      h => BADR(d, t, pos, Csv.FieldTooLong{}, fl, cur, out, w, pos)
    case 1n+l2:
      h => h(l2)

# The four modes a field may end in: at the start of a record, after a
# delimiter, in an unquoted field, after a closing quote
type E is Data:
  ERec{}
  EFld{}
  EPl{text: Bytes(), r: Nat}
  ECl{text: Bytes(), r: Nat}

def e.m(e: E) -> Csv.Mode:
  match e:
    case ERec{}:
      Csv.RS{}
    case EFld{}:
      Csv.FS{}
    case EPl{t, r}:
      Csv.Unq{t, r}
    case ECl{t, r}:
      Csv.QQ{t, r}

def e.txt(e: E) -> Bytes():
  match e:
    case ERec{}:
      ""
    case EFld{}:
      ""
    case EPl{t, r}:
      t
    case ECl{t, r}:
      t

def hb.fin(+d: Csv.Dialect) -> HB(p => Csv.result(d, p)):
  a2 => y => f => c2 => o2 => w2 => p2 => {==}

# a delimiter where a field may end
def EKD(+d: Csv.Dialect, ee: E, +c: U32, +t: List<&2, Spec.Mark>, +fl: Nat,
  +cur: List<&2, Bytes()>, +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat,
  -k: Nat) -> IH(k, d) -> LEb(t, k) ->
  {R(d, t, Csv.endf(e.txt(ee), fl, cur, out, w, pos, Csv.FS{}, 1n+pos)) ==
    Spec.go(Con{Spec.LComma{c}, lexd(d, t)}, d, at_of(e.m(ee)), fl, cur, out, w, pos) : Csv.Out}:
  match ee:
    case ERec{}:
      ih => lb => FEL(fl, d, "", cur, out, w, pos, t)(f => gs => ih(t, Csv.FS{}, f, gs, out, w, 1n+pos)(lb)(Unit{}))
    case EFld{}:
      ih => lb => FEL(fl, d, "", cur, out, w, pos, t)(f => gs => ih(t, Csv.FS{}, f, gs, out, w, 1n+pos)(lb)(Unit{}))
    case EPl{tx, r}:
      ih => lb => FEL(fl, d, tx, cur, out, w, pos, t)(f => gs => ih(t, Csv.FS{}, f, gs, out, w, 1n+pos)(lb)(Unit{}))
    case ECl{tx, r}:
      ih => lb => FEL(fl, d, tx, cur, out, w, pos, t)(f => gs => ih(t, Csv.FS{}, f, gs, out, w, 1n+pos)(lb)(Unit{}))

# an LF where a field may end
def ELF(+d: Csv.Dialect, ee: E, +c: U32, +t: List<&2, Spec.Mark>, +fl: Nat,
  +cur: List<&2, Bytes()>, +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat,
  +k: Nat) -> IH(k, d) -> LEb(t, k) ->
  {R(d, t, Csv.lf.at(d, e.txt(ee), fl, cur, out, w, pos)) ==
    Spec.go(Con{Spec.lone.lf(Spec.takes_lf(d), c), lexd(d, t)}, d, at_of(e.m(ee)), fl, cur, out, w, pos) :
    Csv.Out}:
  match d:
    case Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}:
      match b ee:
        case True{} ERec{}:
          ih => lb => LE(Csv.Dialect{dl, q, a, True{}, cr, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, a, True{}, cr, h, mf, mn, rg, pd}, t, p),
            rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, a, True{}, cr, h, mf, mn, rg, pd}, t), Csv.Dialect{dl, q, a, True{}, cr, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
            o => x => ih(t, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(hb.r(Csv.Dialect{dl, q, a, True{}, cr, h, mf, mn, rg, pd}, t))
        case True{} EFld{}:
          ih => lb => LE(Csv.Dialect{dl, q, a, True{}, cr, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, a, True{}, cr, h, mf, mn, rg, pd}, t, p),
            rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, a, True{}, cr, h, mf, mn, rg, pd}, t), Csv.Dialect{dl, q, a, True{}, cr, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
            o => x => ih(t, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(hb.r(Csv.Dialect{dl, q, a, True{}, cr, h, mf, mn, rg, pd}, t))
        case True{} EPl{tx, r}:
          ih => lb => LE(Csv.Dialect{dl, q, a, True{}, cr, h, mf, mn, rg, pd}, tx, fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, a, True{}, cr, h, mf, mn, rg, pd}, t, p),
            rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, a, True{}, cr, h, mf, mn, rg, pd}, t), Csv.Dialect{dl, q, a, True{}, cr, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
            o => x => ih(t, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(hb.r(Csv.Dialect{dl, q, a, True{}, cr, h, mf, mn, rg, pd}, t))
        case True{} ECl{tx, r}:
          ih => lb => LE(Csv.Dialect{dl, q, a, True{}, cr, h, mf, mn, rg, pd}, tx, fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, a, True{}, cr, h, mf, mn, rg, pd}, t, p),
            rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, a, True{}, cr, h, mf, mn, rg, pd}, t), Csv.Dialect{dl, q, a, True{}, cr, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
            o => x => ih(t, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(hb.r(Csv.Dialect{dl, q, a, True{}, cr, h, mf, mn, rg, pd}, t))
        case False{} ERec{}:
          ih => lb => BADR(Csv.Dialect{dl, q, a, False{}, cr, h, mf, mn, rg, pd}, t, pos, Csv.BareLF{}, fl, cur, out, w, pos)
        case False{} EFld{}:
          ih => lb => BADR(Csv.Dialect{dl, q, a, False{}, cr, h, mf, mn, rg, pd}, t, pos, Csv.BareLF{}, fl, cur, out, w, pos)
        case False{} EPl{tx, r}:
          ih => lb => BADR(Csv.Dialect{dl, q, a, False{}, cr, h, mf, mn, rg, pd}, t, pos, Csv.BareLF{}, fl, cur, out, w, pos)
        case False{} ECl{tx, r}:
          ih => lb => BADR(Csv.Dialect{dl, q, a, False{}, cr, h, mf, mn, rg, pd}, t, pos, Csv.BareLF{}, fl, cur, out, w, pos)

# an LF inside quotes
def QLF(+d: Csv.Dialect, +c: U32, +t: List<&2, Spec.Mark>, +acc: Bytes(), +l: Nat, +fl: Nat,
  +cur: List<&2, Bytes()>, +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat,
  -k: Nat) -> IH(k, d) -> LEb(t, k) ->
  {R(d, t, Csv.put(True{}, c, acc, l, fl, cur, out, w, pos)) ==
    Spec.go(Con{Spec.lone.lf(Spec.takes_lf(d), c), lexd(d, t)}, d, Spec.Quoted{acc, l}, fl, cur, out, w,
      pos) : Csv.Out}:
  match d:
    case Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}:
      match b:
        case True{}:
          ih => lb => PUT(l, True{}, Csv.Dialect{dl, q, a, True{}, cr, h, mf, mn, rg, pd}, c, acc, fl, cur, out, w, pos, t)(
            l2 => ih(t, Csv.Quo{Csv.push(acc, c), l2}, fl, cur, out, w, 1n+pos)(lb)(Unit{}))
        case False{}:
          ih => lb => PUT(l, True{}, Csv.Dialect{dl, q, a, False{}, cr, h, mf, mn, rg, pd}, c, acc, fl, cur, out, w, pos, t)(
            l2 => ih(t, Csv.Quo{Csv.push(acc, c), l2}, fl, cur, out, w, 1n+pos)(lb)(Unit{}))

# a CR where a field may end: the reader holds it (CRp) and the byte
# after it says what it was; the grammar's lexer looks at that byte
def ECR(+d: Csv.Dialect, +c: U32, +t: List<&2, Spec.Mark>, ee: E, +fl: Nat,
  +cur: List<&2, Bytes()>, +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat,
  +k: Nat) -> IH(k, d) -> LEb(t, k) ->
  {R(d, t, Csv.cr.at(d, e.txt(ee), fl, cur, out, w, pos)) ==
    Spec.go(Spec.lex(Con{Spec.Mark{Csv.KCR{}, c}, t}, Spec.takes_crlf(d), Spec.takes_cr(d),
      Spec.takes_lf(d)), d, at_of(e.m(ee)), fl, cur, out, w, pos) : Csv.Out}:
  match d:
    case Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}:
      match a cr t:
        case True{} True{} Nil{}:
          match ee:
            case ERec{}:
              ih => lb => LE(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, 1n+pos, p => Csv.result(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, p),
              rs2 => f2 => Spec.go(Nil{}, Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Nil{}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(Unit{})(Unit{}))(hb.fin(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}))
            case EFld{}:
              ih => lb => LE(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, 1n+pos, p => Csv.result(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, p),
              rs2 => f2 => Spec.go(Nil{}, Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Nil{}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(Unit{})(Unit{}))(hb.fin(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}))
            case EPl{tx, r}:
              ih => lb => LE(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, tx, fl, cur, out, w, pos, 1n+pos, p => Csv.result(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, p),
              rs2 => f2 => Spec.go(Nil{}, Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Nil{}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(Unit{})(Unit{}))(hb.fin(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}))
            case ECl{tx, r}:
              ih => lb => LE(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, tx, fl, cur, out, w, pos, 1n+pos, p => Csv.result(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, p),
              rs2 => f2 => Spec.go(Nil{}, Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Nil{}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(Unit{})(Unit{}))(hb.fin(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}))
        case True{} True{} Con{Spec.Mark{k2, b0}, u}:
          match k2 ee:
            case Csv.KQ{} ERec{}:
              ih => lb => LE(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KQ{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KQ{}, b0}, u}), Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KQ{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KQ{} EFld{}:
              ih => lb => LE(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KQ{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KQ{}, b0}, u}), Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KQ{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KQ{} EPl{tx, r}:
              ih => lb => LE(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, tx, fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KQ{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KQ{}, b0}, u}), Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KQ{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KQ{} ECl{tx, r}:
              ih => lb => LE(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, tx, fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KQ{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KQ{}, b0}, u}), Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KQ{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KD{} ERec{}:
              ih => lb => LE(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KD{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KD{}, b0}, u}), Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KD{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KD{} EFld{}:
              ih => lb => LE(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KD{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KD{}, b0}, u}), Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KD{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KD{} EPl{tx, r}:
              ih => lb => LE(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, tx, fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KD{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KD{}, b0}, u}), Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KD{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KD{} ECl{tx, r}:
              ih => lb => LE(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, tx, fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KD{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KD{}, b0}, u}), Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KD{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KCR{} ERec{}:
              ih => lb => LE(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KCR{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KCR{}, b0}, u}), Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KCR{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KCR{} EFld{}:
              ih => lb => LE(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KCR{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KCR{}, b0}, u}), Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KCR{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KCR{} EPl{tx, r}:
              ih => lb => LE(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, tx, fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KCR{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KCR{}, b0}, u}), Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KCR{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KCR{} ECl{tx, r}:
              ih => lb => LE(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, tx, fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KCR{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KCR{}, b0}, u}), Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KCR{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KLF{} ERec{}:
              ih => lb => LE(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, 1n+1n+pos, p => R(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, p),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u), Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+1n+pos))(
              o => x => ih(u, Csv.RS{}, mn, Nil{}, o, x, 1n+1n+pos)(lb.tail(Spec.Mark{Csv.KLF{}, b0}, u, k)(lb))(
                Unit{}))(hb.r(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u))
            case Csv.KLF{} EFld{}:
              ih => lb => LE(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, 1n+1n+pos, p => R(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, p),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u), Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+1n+pos))(
              o => x => ih(u, Csv.RS{}, mn, Nil{}, o, x, 1n+1n+pos)(lb.tail(Spec.Mark{Csv.KLF{}, b0}, u, k)(lb))(
                Unit{}))(hb.r(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u))
            case Csv.KLF{} EPl{tx, r}:
              ih => lb => LE(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, tx, fl, cur, out, w, pos, 1n+1n+pos, p => R(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, p),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u), Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+1n+pos))(
              o => x => ih(u, Csv.RS{}, mn, Nil{}, o, x, 1n+1n+pos)(lb.tail(Spec.Mark{Csv.KLF{}, b0}, u, k)(lb))(
                Unit{}))(hb.r(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u))
            case Csv.KLF{} ECl{tx, r}:
              ih => lb => LE(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, tx, fl, cur, out, w, pos, 1n+1n+pos, p => R(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, p),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u), Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+1n+pos))(
              o => x => ih(u, Csv.RS{}, mn, Nil{}, o, x, 1n+1n+pos)(lb.tail(Spec.Mark{Csv.KLF{}, b0}, u, k)(lb))(
                Unit{}))(hb.r(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u))
            case Csv.KO{} ERec{}:
              ih => lb => LE(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KO{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KO{}, b0}, u}), Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KO{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KO{} EFld{}:
              ih => lb => LE(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KO{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KO{}, b0}, u}), Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KO{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KO{} EPl{tx, r}:
              ih => lb => LE(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, tx, fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KO{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KO{}, b0}, u}), Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KO{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KO{} ECl{tx, r}:
              ih => lb => LE(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, tx, fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KO{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KO{}, b0}, u}), Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KO{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
        case True{} False{} Nil{}:
          match ee:
            case ERec{}:
              ih => lb => {==}
            case EFld{}:
              ih => lb => {==}
            case EPl{tx, r}:
              ih => lb => {==}
            case ECl{tx, r}:
              ih => lb => {==}
        case True{} False{} Con{Spec.Mark{k2, b0}, u}:
          match k2 ee:
            case Csv.KQ{} ERec{}:
              ih => lb => BADR(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, u, pos, Csv.BareCR{}, fl, cur, out, w, 1n+pos)
            case Csv.KQ{} EFld{}:
              ih => lb => BADR(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, u, pos, Csv.BareCR{}, fl, cur, out, w, 1n+pos)
            case Csv.KQ{} EPl{tx, r}:
              ih => lb => BADR(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, u, pos, Csv.BareCR{}, fl, cur, out, w, 1n+pos)
            case Csv.KQ{} ECl{tx, r}:
              ih => lb => BADR(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, u, pos, Csv.BareCR{}, fl, cur, out, w, 1n+pos)
            case Csv.KD{} ERec{}:
              ih => lb => BADR(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, u, pos, Csv.BareCR{}, fl, cur, out, w, 1n+pos)
            case Csv.KD{} EFld{}:
              ih => lb => BADR(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, u, pos, Csv.BareCR{}, fl, cur, out, w, 1n+pos)
            case Csv.KD{} EPl{tx, r}:
              ih => lb => BADR(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, u, pos, Csv.BareCR{}, fl, cur, out, w, 1n+pos)
            case Csv.KD{} ECl{tx, r}:
              ih => lb => BADR(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, u, pos, Csv.BareCR{}, fl, cur, out, w, 1n+pos)
            case Csv.KCR{} ERec{}:
              ih => lb => BADR(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, u, pos, Csv.BareCR{}, fl, cur, out, w, 1n+pos)
            case Csv.KCR{} EFld{}:
              ih => lb => BADR(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, u, pos, Csv.BareCR{}, fl, cur, out, w, 1n+pos)
            case Csv.KCR{} EPl{tx, r}:
              ih => lb => BADR(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, u, pos, Csv.BareCR{}, fl, cur, out, w, 1n+pos)
            case Csv.KCR{} ECl{tx, r}:
              ih => lb => BADR(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, u, pos, Csv.BareCR{}, fl, cur, out, w, 1n+pos)
            case Csv.KLF{} ERec{}:
              ih => lb => LE(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, 1n+1n+pos, p => R(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, u, p),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, u), Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+1n+pos))(
              o => x => ih(u, Csv.RS{}, mn, Nil{}, o, x, 1n+1n+pos)(lb.tail(Spec.Mark{Csv.KLF{}, b0}, u, k)(lb))(
                Unit{}))(hb.r(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, u))
            case Csv.KLF{} EFld{}:
              ih => lb => LE(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, 1n+1n+pos, p => R(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, u, p),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, u), Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+1n+pos))(
              o => x => ih(u, Csv.RS{}, mn, Nil{}, o, x, 1n+1n+pos)(lb.tail(Spec.Mark{Csv.KLF{}, b0}, u, k)(lb))(
                Unit{}))(hb.r(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, u))
            case Csv.KLF{} EPl{tx, r}:
              ih => lb => LE(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, tx, fl, cur, out, w, pos, 1n+1n+pos, p => R(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, u, p),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, u), Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+1n+pos))(
              o => x => ih(u, Csv.RS{}, mn, Nil{}, o, x, 1n+1n+pos)(lb.tail(Spec.Mark{Csv.KLF{}, b0}, u, k)(lb))(
                Unit{}))(hb.r(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, u))
            case Csv.KLF{} ECl{tx, r}:
              ih => lb => LE(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, tx, fl, cur, out, w, pos, 1n+1n+pos, p => R(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, u, p),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, u), Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+1n+pos))(
              o => x => ih(u, Csv.RS{}, mn, Nil{}, o, x, 1n+1n+pos)(lb.tail(Spec.Mark{Csv.KLF{}, b0}, u, k)(lb))(
                Unit{}))(hb.r(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, u))
            case Csv.KO{} ERec{}:
              ih => lb => BADR(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, u, pos, Csv.BareCR{}, fl, cur, out, w, 1n+pos)
            case Csv.KO{} EFld{}:
              ih => lb => BADR(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, u, pos, Csv.BareCR{}, fl, cur, out, w, 1n+pos)
            case Csv.KO{} EPl{tx, r}:
              ih => lb => BADR(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, u, pos, Csv.BareCR{}, fl, cur, out, w, 1n+pos)
            case Csv.KO{} ECl{tx, r}:
              ih => lb => BADR(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, u, pos, Csv.BareCR{}, fl, cur, out, w, 1n+pos)
        case False{} True{} Nil{}:
          match ee:
            case ERec{}:
              ih => lb => LE(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, 1n+pos, p => Csv.result(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, p),
              rs2 => f2 => Spec.go(Nil{}, Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Nil{}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(Unit{})(Unit{}))(hb.fin(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}))
            case EFld{}:
              ih => lb => LE(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, 1n+pos, p => Csv.result(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, p),
              rs2 => f2 => Spec.go(Nil{}, Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Nil{}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(Unit{})(Unit{}))(hb.fin(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}))
            case EPl{tx, r}:
              ih => lb => LE(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, tx, fl, cur, out, w, pos, 1n+pos, p => Csv.result(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, p),
              rs2 => f2 => Spec.go(Nil{}, Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Nil{}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(Unit{})(Unit{}))(hb.fin(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}))
            case ECl{tx, r}:
              ih => lb => LE(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, tx, fl, cur, out, w, pos, 1n+pos, p => Csv.result(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, p),
              rs2 => f2 => Spec.go(Nil{}, Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Nil{}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(Unit{})(Unit{}))(hb.fin(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}))
        case False{} True{} Con{Spec.Mark{k2, b0}, u}:
          match k2 ee:
            case Csv.KQ{} ERec{}:
              ih => lb => LE(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KQ{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KQ{}, b0}, u}), Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KQ{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KQ{} EFld{}:
              ih => lb => LE(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KQ{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KQ{}, b0}, u}), Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KQ{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KQ{} EPl{tx, r}:
              ih => lb => LE(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, tx, fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KQ{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KQ{}, b0}, u}), Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KQ{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KQ{} ECl{tx, r}:
              ih => lb => LE(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, tx, fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KQ{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KQ{}, b0}, u}), Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KQ{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KD{} ERec{}:
              ih => lb => LE(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KD{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KD{}, b0}, u}), Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KD{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KD{} EFld{}:
              ih => lb => LE(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KD{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KD{}, b0}, u}), Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KD{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KD{} EPl{tx, r}:
              ih => lb => LE(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, tx, fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KD{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KD{}, b0}, u}), Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KD{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KD{} ECl{tx, r}:
              ih => lb => LE(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, tx, fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KD{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KD{}, b0}, u}), Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KD{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KCR{} ERec{}:
              ih => lb => LE(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KCR{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KCR{}, b0}, u}), Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KCR{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KCR{} EFld{}:
              ih => lb => LE(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KCR{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KCR{}, b0}, u}), Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KCR{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KCR{} EPl{tx, r}:
              ih => lb => LE(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, tx, fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KCR{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KCR{}, b0}, u}), Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KCR{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KCR{} ECl{tx, r}:
              ih => lb => LE(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, tx, fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KCR{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KCR{}, b0}, u}), Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KCR{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KLF{} ERec{}:
              ih => lb => LE(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KLF{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KLF{}, b0}, u}), Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KLF{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KLF{} EFld{}:
              ih => lb => LE(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KLF{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KLF{}, b0}, u}), Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KLF{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KLF{} EPl{tx, r}:
              ih => lb => LE(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, tx, fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KLF{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KLF{}, b0}, u}), Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KLF{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KLF{} ECl{tx, r}:
              ih => lb => LE(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, tx, fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KLF{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KLF{}, b0}, u}), Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KLF{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KO{} ERec{}:
              ih => lb => LE(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KO{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KO{}, b0}, u}), Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KO{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KO{} EFld{}:
              ih => lb => LE(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KO{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KO{}, b0}, u}), Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KO{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KO{} EPl{tx, r}:
              ih => lb => LE(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, tx, fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KO{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KO{}, b0}, u}), Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KO{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
            case Csv.KO{} ECl{tx, r}:
              ih => lb => LE(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, tx, fl, cur, out, w, pos, 1n+pos, p => R(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, Csv.fresh.after(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, p, Csv.KO{}, b0)),
              rs2 => f2 => Spec.go(lexd(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KO{}, b0}, u}), Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, Spec.Record{}, mn, Nil{}, rs2, f2, 1n+pos))(
              o => x => ih(Con{Spec.Mark{Csv.KO{}, b0}, u}, Csv.RS{}, mn, Nil{}, o, x, 1n+pos)(lb)(Unit{}))(
              a2 => y => f => c2 => o2 => w2 => p2 => BADR(Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, u, a2, y, f, c2, o2, w2, p2))
        case False{} False{} Nil{}:
          match ee:
            case ERec{}:
              ih => lb => BADR(Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, Nil{}, pos, Csv.BareCR{}, fl, cur, out, w, pos)
            case EFld{}:
              ih => lb => BADR(Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, Nil{}, pos, Csv.BareCR{}, fl, cur, out, w, pos)
            case EPl{tx, r}:
              ih => lb => BADR(Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, Nil{}, pos, Csv.BareCR{}, fl, cur, out, w, pos)
            case ECl{tx, r}:
              ih => lb => BADR(Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, Nil{}, pos, Csv.BareCR{}, fl, cur, out, w, pos)
        case False{} False{} Con{Spec.Mark{k2, b0}, u}:
          match k2 ee:
            case Csv.KQ{} ERec{}:
              ih => lb => BADR(Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KQ{}, b0}, u}, pos, Csv.BareCR{}, fl, cur, out, w, pos)
            case Csv.KQ{} EFld{}:
              ih => lb => BADR(Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KQ{}, b0}, u}, pos, Csv.BareCR{}, fl, cur, out, w, pos)
            case Csv.KQ{} EPl{tx, r}:
              ih => lb => BADR(Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KQ{}, b0}, u}, pos, Csv.BareCR{}, fl, cur, out, w, pos)
            case Csv.KQ{} ECl{tx, r}:
              ih => lb => BADR(Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KQ{}, b0}, u}, pos, Csv.BareCR{}, fl, cur, out, w, pos)
            case Csv.KD{} ERec{}:
              ih => lb => BADR(Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KD{}, b0}, u}, pos, Csv.BareCR{}, fl, cur, out, w, pos)
            case Csv.KD{} EFld{}:
              ih => lb => BADR(Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KD{}, b0}, u}, pos, Csv.BareCR{}, fl, cur, out, w, pos)
            case Csv.KD{} EPl{tx, r}:
              ih => lb => BADR(Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KD{}, b0}, u}, pos, Csv.BareCR{}, fl, cur, out, w, pos)
            case Csv.KD{} ECl{tx, r}:
              ih => lb => BADR(Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KD{}, b0}, u}, pos, Csv.BareCR{}, fl, cur, out, w, pos)
            case Csv.KCR{} ERec{}:
              ih => lb => BADR(Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KCR{}, b0}, u}, pos, Csv.BareCR{}, fl, cur, out, w, pos)
            case Csv.KCR{} EFld{}:
              ih => lb => BADR(Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KCR{}, b0}, u}, pos, Csv.BareCR{}, fl, cur, out, w, pos)
            case Csv.KCR{} EPl{tx, r}:
              ih => lb => BADR(Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KCR{}, b0}, u}, pos, Csv.BareCR{}, fl, cur, out, w, pos)
            case Csv.KCR{} ECl{tx, r}:
              ih => lb => BADR(Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KCR{}, b0}, u}, pos, Csv.BareCR{}, fl, cur, out, w, pos)
            case Csv.KLF{} ERec{}:
              ih => lb => BADR(Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KLF{}, b0}, u}, pos, Csv.BareCR{}, fl, cur, out, w, pos)
            case Csv.KLF{} EFld{}:
              ih => lb => BADR(Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KLF{}, b0}, u}, pos, Csv.BareCR{}, fl, cur, out, w, pos)
            case Csv.KLF{} EPl{tx, r}:
              ih => lb => BADR(Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KLF{}, b0}, u}, pos, Csv.BareCR{}, fl, cur, out, w, pos)
            case Csv.KLF{} ECl{tx, r}:
              ih => lb => BADR(Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KLF{}, b0}, u}, pos, Csv.BareCR{}, fl, cur, out, w, pos)
            case Csv.KO{} ERec{}:
              ih => lb => BADR(Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KO{}, b0}, u}, pos, Csv.BareCR{}, fl, cur, out, w, pos)
            case Csv.KO{} EFld{}:
              ih => lb => BADR(Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KO{}, b0}, u}, pos, Csv.BareCR{}, fl, cur, out, w, pos)
            case Csv.KO{} EPl{tx, r}:
              ih => lb => BADR(Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KO{}, b0}, u}, pos, Csv.BareCR{}, fl, cur, out, w, pos)
            case Csv.KO{} ECl{tx, r}:
              ih => lb => BADR(Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KO{}, b0}, u}, pos, Csv.BareCR{}, fl, cur, out, w, pos)

# a CR inside quotes: data, and so is an LF after it, one byte each
def QCR(+d: Csv.Dialect, +c: U32, +t: List<&2, Spec.Mark>, +acc: Bytes(), l: Nat, +fl: Nat,
  +cur: List<&2, Bytes()>, +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat,
  +k: Nat) -> IH(k, d) -> LEb(t, k) ->
  {R(d, t, Csv.put(True{}, c, acc, l, fl, cur, out, w, pos)) ==
    Spec.go(Spec.lex(Con{Spec.Mark{Csv.KCR{}, c}, t}, Spec.takes_crlf(d), Spec.takes_cr(d),
      Spec.takes_lf(d)), d, Spec.Quoted{acc, l}, fl, cur, out, w, pos) : Csv.Out}:
  match d:
    case Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}:
      match a cr t:
        case True{} True{} Nil{}:
          ih => lb => PUT(l, True{}, Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, c, acc, fl, cur, out, w, pos, Nil{})(
            l2 => ih(Nil{}, Csv.Quo{Csv.push(acc, c), l2}, fl, cur, out, w, 1n+pos)(Unit{})(Unit{}))
        case True{} True{} Con{Spec.Mark{k2, b0}, u}:
          match k2 l:
            case Csv.KQ{} _:
              ih => lb => PUT(l, True{}, Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, c, acc, fl, cur, out, w, pos, Con{Spec.Mark{Csv.KQ{}, b0}, u})(
                l2 => ih(Con{Spec.Mark{Csv.KQ{}, b0}, u}, Csv.Quo{Csv.push(acc, c), l2}, fl, cur, out, w, 1n+pos)(lb)(Unit{}))
            case Csv.KD{} _:
              ih => lb => PUT(l, True{}, Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, c, acc, fl, cur, out, w, pos, Con{Spec.Mark{Csv.KD{}, b0}, u})(
                l2 => ih(Con{Spec.Mark{Csv.KD{}, b0}, u}, Csv.Quo{Csv.push(acc, c), l2}, fl, cur, out, w, 1n+pos)(lb)(Unit{}))
            case Csv.KCR{} _:
              ih => lb => PUT(l, True{}, Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, c, acc, fl, cur, out, w, pos, Con{Spec.Mark{Csv.KCR{}, b0}, u})(
                l2 => ih(Con{Spec.Mark{Csv.KCR{}, b0}, u}, Csv.Quo{Csv.push(acc, c), l2}, fl, cur, out, w, 1n+pos)(lb)(Unit{}))
            case Csv.KLF{} 0n:
              ih => lb => BADR(Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KLF{}, b0}, u}, pos, Csv.FieldTooLong{}, fl, cur, out, w, pos)
            case Csv.KLF{} 1n+l2:
              ih => lb => PUT(l2, True{}, Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, b0, Csv.push(acc, c), fl, cur, out, w, 1n+pos, u)(
                j => ih(u, Csv.Quo{Csv.push(Csv.push(acc, c), b0), j}, fl, cur, out, w, 1n+1n+pos)(
                  lb.tail(Spec.Mark{Csv.KLF{}, b0}, u, k)(lb))(Unit{}))
            case Csv.KO{} _:
              ih => lb => PUT(l, True{}, Csv.Dialect{dl, q, True{}, b, True{}, h, mf, mn, rg, pd}, c, acc, fl, cur, out, w, pos, Con{Spec.Mark{Csv.KO{}, b0}, u})(
                l2 => ih(Con{Spec.Mark{Csv.KO{}, b0}, u}, Csv.Quo{Csv.push(acc, c), l2}, fl, cur, out, w, 1n+pos)(lb)(Unit{}))
        case True{} False{} Nil{}:
          ih => lb => PUT(l, True{}, Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, c, acc, fl, cur, out, w, pos, Nil{})(
            l2 => ih(Nil{}, Csv.Quo{Csv.push(acc, c), l2}, fl, cur, out, w, 1n+pos)(Unit{})(Unit{}))
        case True{} False{} Con{Spec.Mark{k2, b0}, u}:
          match k2 l:
            case Csv.KQ{} _:
              ih => lb => PUT(l, True{}, Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, c, acc, fl, cur, out, w, pos, Con{Spec.Mark{Csv.KQ{}, b0}, u})(
                l2 => ih(Con{Spec.Mark{Csv.KQ{}, b0}, u}, Csv.Quo{Csv.push(acc, c), l2}, fl, cur, out, w, 1n+pos)(lb)(Unit{}))
            case Csv.KD{} _:
              ih => lb => PUT(l, True{}, Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, c, acc, fl, cur, out, w, pos, Con{Spec.Mark{Csv.KD{}, b0}, u})(
                l2 => ih(Con{Spec.Mark{Csv.KD{}, b0}, u}, Csv.Quo{Csv.push(acc, c), l2}, fl, cur, out, w, 1n+pos)(lb)(Unit{}))
            case Csv.KCR{} _:
              ih => lb => PUT(l, True{}, Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, c, acc, fl, cur, out, w, pos, Con{Spec.Mark{Csv.KCR{}, b0}, u})(
                l2 => ih(Con{Spec.Mark{Csv.KCR{}, b0}, u}, Csv.Quo{Csv.push(acc, c), l2}, fl, cur, out, w, 1n+pos)(lb)(Unit{}))
            case Csv.KLF{} 0n:
              ih => lb => BADR(Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KLF{}, b0}, u}, pos, Csv.FieldTooLong{}, fl, cur, out, w, pos)
            case Csv.KLF{} 1n+l2:
              ih => lb => PUT(l2, True{}, Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, b0, Csv.push(acc, c), fl, cur, out, w, 1n+pos, u)(
                j => ih(u, Csv.Quo{Csv.push(Csv.push(acc, c), b0), j}, fl, cur, out, w, 1n+1n+pos)(
                  lb.tail(Spec.Mark{Csv.KLF{}, b0}, u, k)(lb))(Unit{}))
            case Csv.KO{} _:
              ih => lb => PUT(l, True{}, Csv.Dialect{dl, q, True{}, b, False{}, h, mf, mn, rg, pd}, c, acc, fl, cur, out, w, pos, Con{Spec.Mark{Csv.KO{}, b0}, u})(
                l2 => ih(Con{Spec.Mark{Csv.KO{}, b0}, u}, Csv.Quo{Csv.push(acc, c), l2}, fl, cur, out, w, 1n+pos)(lb)(Unit{}))
        case False{} True{} Nil{}:
          ih => lb => PUT(l, True{}, Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, c, acc, fl, cur, out, w, pos, Nil{})(
            l2 => ih(Nil{}, Csv.Quo{Csv.push(acc, c), l2}, fl, cur, out, w, 1n+pos)(Unit{})(Unit{}))
        case False{} True{} Con{Spec.Mark{k2, b0}, u}:
          match k2 l:
            case Csv.KQ{} _:
              ih => lb => PUT(l, True{}, Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, c, acc, fl, cur, out, w, pos, Con{Spec.Mark{Csv.KQ{}, b0}, u})(
                l2 => ih(Con{Spec.Mark{Csv.KQ{}, b0}, u}, Csv.Quo{Csv.push(acc, c), l2}, fl, cur, out, w, 1n+pos)(lb)(Unit{}))
            case Csv.KD{} _:
              ih => lb => PUT(l, True{}, Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, c, acc, fl, cur, out, w, pos, Con{Spec.Mark{Csv.KD{}, b0}, u})(
                l2 => ih(Con{Spec.Mark{Csv.KD{}, b0}, u}, Csv.Quo{Csv.push(acc, c), l2}, fl, cur, out, w, 1n+pos)(lb)(Unit{}))
            case Csv.KCR{} _:
              ih => lb => PUT(l, True{}, Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, c, acc, fl, cur, out, w, pos, Con{Spec.Mark{Csv.KCR{}, b0}, u})(
                l2 => ih(Con{Spec.Mark{Csv.KCR{}, b0}, u}, Csv.Quo{Csv.push(acc, c), l2}, fl, cur, out, w, 1n+pos)(lb)(Unit{}))
            case Csv.KLF{} _:
              ih => lb => PUT(l, True{}, Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, c, acc, fl, cur, out, w, pos, Con{Spec.Mark{Csv.KLF{}, b0}, u})(
                l2 => ih(Con{Spec.Mark{Csv.KLF{}, b0}, u}, Csv.Quo{Csv.push(acc, c), l2}, fl, cur, out, w, 1n+pos)(lb)(Unit{}))
            case Csv.KO{} _:
              ih => lb => PUT(l, True{}, Csv.Dialect{dl, q, False{}, b, True{}, h, mf, mn, rg, pd}, c, acc, fl, cur, out, w, pos, Con{Spec.Mark{Csv.KO{}, b0}, u})(
                l2 => ih(Con{Spec.Mark{Csv.KO{}, b0}, u}, Csv.Quo{Csv.push(acc, c), l2}, fl, cur, out, w, 1n+pos)(lb)(Unit{}))
        case False{} False{} Nil{}:
          ih => lb => PUT(l, True{}, Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, c, acc, fl, cur, out, w, pos, Nil{})(
            l2 => ih(Nil{}, Csv.Quo{Csv.push(acc, c), l2}, fl, cur, out, w, 1n+pos)(Unit{})(Unit{}))
        case False{} False{} Con{Spec.Mark{k2, b0}, u}:
          match k2 l:
            case Csv.KQ{} _:
              ih => lb => PUT(l, True{}, Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, c, acc, fl, cur, out, w, pos, Con{Spec.Mark{Csv.KQ{}, b0}, u})(
                l2 => ih(Con{Spec.Mark{Csv.KQ{}, b0}, u}, Csv.Quo{Csv.push(acc, c), l2}, fl, cur, out, w, 1n+pos)(lb)(Unit{}))
            case Csv.KD{} _:
              ih => lb => PUT(l, True{}, Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, c, acc, fl, cur, out, w, pos, Con{Spec.Mark{Csv.KD{}, b0}, u})(
                l2 => ih(Con{Spec.Mark{Csv.KD{}, b0}, u}, Csv.Quo{Csv.push(acc, c), l2}, fl, cur, out, w, 1n+pos)(lb)(Unit{}))
            case Csv.KCR{} _:
              ih => lb => PUT(l, True{}, Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, c, acc, fl, cur, out, w, pos, Con{Spec.Mark{Csv.KCR{}, b0}, u})(
                l2 => ih(Con{Spec.Mark{Csv.KCR{}, b0}, u}, Csv.Quo{Csv.push(acc, c), l2}, fl, cur, out, w, 1n+pos)(lb)(Unit{}))
            case Csv.KLF{} _:
              ih => lb => PUT(l, True{}, Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, c, acc, fl, cur, out, w, pos, Con{Spec.Mark{Csv.KLF{}, b0}, u})(
                l2 => ih(Con{Spec.Mark{Csv.KLF{}, b0}, u}, Csv.Quo{Csv.push(acc, c), l2}, fl, cur, out, w, 1n+pos)(lb)(Unit{}))
            case Csv.KO{} _:
              ih => lb => PUT(l, True{}, Csv.Dialect{dl, q, False{}, b, False{}, h, mf, mn, rg, pd}, c, acc, fl, cur, out, w, pos, Con{Spec.Mark{Csv.KO{}, b0}, u})(
                l2 => ih(Con{Spec.Mark{Csv.KO{}, b0}, u}, Csv.Quo{Csv.push(acc, c), l2}, fl, cur, out, w, 1n+pos)(lb)(Unit{}))

# the end of input, from every mode
def END(+d: Csv.Dialect, +m: Csv.Mode, +fl: Nat, +cur: List<&2, Bytes()>,
  +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat) ->
  Pre(m) -> SIM(d, Nil{}, m, fl, cur, out, w, pos):
  match d:
    case Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}:
      match m:
        case Csv.RS{}:
          pre => tbl(h, List.reverse(&2, List<&2, Bytes()>, out))
        case Csv.FS{}:
          pre => LE(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, "", fl, cur, out, w, pos, pos, p => Csv.result(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, p),
            rs2 => f2 => Spec.done(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, rs2))(
            o => x => tbl(h, List.reverse(&2, List<&2, Bytes()>, o)))(hb.fin(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}))
        case Csv.Unq{acc, l}:
          pre => LE(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, acc, fl, cur, out, w, pos, pos, p => Csv.result(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, p),
            rs2 => f2 => Spec.done(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, rs2))(
            o => x => tbl(h, List.reverse(&2, List<&2, Bytes()>, o)))(hb.fin(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}))
        case Csv.QQ{acc, l}:
          pre => LE(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, acc, fl, cur, out, w, pos, pos, p => Csv.result(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, p),
            rs2 => f2 => Spec.done(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, rs2))(
            o => x => tbl(h, List.reverse(&2, List<&2, Bytes()>, o)))(hb.fin(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}))
        case Csv.Quo{acc, l}:
          pre => {==}
        case Csv.CRp{acc, at}:
          pre => absurd(SIM(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, Nil{}, Csv.CRp{acc, at}, fl, cur, out, w, pos), pre)
        case Csv.Bad{at, why}:
          pre => absurd(SIM(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, Nil{}, Csv.Bad{at, why}, fl, cur, out, w, pos), pre)

# one byte, from every mode the grammar can be in
def STEP(+k: Nat, x: Spec.Mark, +d: Csv.Dialect, +m: Csv.Mode, +t: List<&2, Spec.Mark>, +fl: Nat,
  +cur: List<&2, Bytes()>, +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat) ->
  IH(k, d) -> LEb(t, k) -> Pre(m) -> SIM(d, Con{x, t}, m, fl, cur, out, w, pos):
  match x:
    case Spec.Mark{kk, +c}:
      match kk:
        case Csv.KQ{}:
          match d:
            case Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}:
              match m:
                case Csv.RS{}:
                  ih => lb => pre => ih(t, Csv.Quo{"", mf}, fl, cur, out, w, 1n+pos)(lb)(Unit{})
                case Csv.FS{}:
                  ih => lb => pre => ih(t, Csv.Quo{"", mf}, fl, cur, out, w, 1n+pos)(lb)(Unit{})
                case Csv.Unq{acc, l}:
                  ih => lb => pre => BADR(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, t, pos, Csv.QuoteInField{}, fl, cur, out, w, pos)
                case Csv.Quo{acc, l}:
                  ih => lb => pre => ih(t, Csv.QQ{acc, l}, fl, cur, out, w, 1n+pos)(lb)(Unit{})
                case Csv.QQ{acc, l}:
                  ih => lb => pre => PUT(l, True{}, Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, c, acc, fl, cur, out, w, pos, t)(
                      l2 => ih(t, Csv.Quo{Csv.push(acc, c), l2}, fl, cur, out, w, 1n+pos)(lb)(Unit{}))
                case Csv.CRp{acc, at}:
                  ih => lb => pre => absurd(SIM(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KQ{}, c}, t}, Csv.CRp{acc, at}, fl, cur, out, w, pos), pre)
                case Csv.Bad{at, why}:
                  ih => lb => pre => absurd(SIM(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KQ{}, c}, t}, Csv.Bad{at, why}, fl, cur, out, w, pos), pre)
        case Csv.KD{}:
          match d:
            case Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}:
              match m:
                case Csv.RS{}:
                  ih => lb => pre => EKD(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, ERec{}, c, t, fl, cur, out, w, pos, k)(ih)(lb)
                case Csv.FS{}:
                  ih => lb => pre => EKD(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, EFld{}, c, t, fl, cur, out, w, pos, k)(ih)(lb)
                case Csv.Unq{acc, l}:
                  ih => lb => pre => EKD(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, EPl{acc, l}, c, t, fl, cur, out, w, pos, k)(ih)(lb)
                case Csv.Quo{acc, l}:
                  ih => lb => pre => PUT(l, True{}, Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, c, acc, fl, cur, out, w, pos, t)(
                      l2 => ih(t, Csv.Quo{Csv.push(acc, c), l2}, fl, cur, out, w, 1n+pos)(lb)(Unit{}))
                case Csv.QQ{acc, l}:
                  ih => lb => pre => EKD(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, ECl{acc, l}, c, t, fl, cur, out, w, pos, k)(ih)(lb)
                case Csv.CRp{acc, at}:
                  ih => lb => pre => absurd(SIM(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KD{}, c}, t}, Csv.CRp{acc, at}, fl, cur, out, w, pos), pre)
                case Csv.Bad{at, why}:
                  ih => lb => pre => absurd(SIM(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KD{}, c}, t}, Csv.Bad{at, why}, fl, cur, out, w, pos), pre)
        case Csv.KCR{}:
          match d:
            case Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}:
              match m:
                case Csv.RS{}:
                  ih => lb => pre => ECR(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, c, t, ERec{}, fl, cur, out, w, pos, k)(ih)(lb)
                case Csv.FS{}:
                  ih => lb => pre => ECR(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, c, t, EFld{}, fl, cur, out, w, pos, k)(ih)(lb)
                case Csv.Unq{acc, l}:
                  ih => lb => pre => ECR(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, c, t, EPl{acc, l}, fl, cur, out, w, pos, k)(ih)(lb)
                case Csv.Quo{acc, l}:
                  ih => lb => pre => QCR(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, c, t, acc, l, fl, cur, out, w, pos, k)(ih)(lb)
                case Csv.QQ{acc, l}:
                  ih => lb => pre => ECR(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, c, t, ECl{acc, l}, fl, cur, out, w, pos, k)(ih)(lb)
                case Csv.CRp{acc, at}:
                  ih => lb => pre => absurd(SIM(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KCR{}, c}, t}, Csv.CRp{acc, at}, fl, cur, out, w, pos), pre)
                case Csv.Bad{at, why}:
                  ih => lb => pre => absurd(SIM(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KCR{}, c}, t}, Csv.Bad{at, why}, fl, cur, out, w, pos), pre)
        case Csv.KLF{}:
          match d:
            case Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}:
              match m:
                case Csv.RS{}:
                  ih => lb => pre => ELF(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, ERec{}, c, t, fl, cur, out, w, pos, k)(ih)(lb)
                case Csv.FS{}:
                  ih => lb => pre => ELF(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, EFld{}, c, t, fl, cur, out, w, pos, k)(ih)(lb)
                case Csv.Unq{acc, l}:
                  ih => lb => pre => ELF(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, EPl{acc, l}, c, t, fl, cur, out, w, pos, k)(ih)(lb)
                case Csv.Quo{acc, l}:
                  ih => lb => pre => QLF(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, c, t, acc, l, fl, cur, out, w, pos, k)(ih)(lb)
                case Csv.QQ{acc, l}:
                  ih => lb => pre => ELF(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, ECl{acc, l}, c, t, fl, cur, out, w, pos, k)(ih)(lb)
                case Csv.CRp{acc, at}:
                  ih => lb => pre => absurd(SIM(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KLF{}, c}, t}, Csv.CRp{acc, at}, fl, cur, out, w, pos), pre)
                case Csv.Bad{at, why}:
                  ih => lb => pre => absurd(SIM(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KLF{}, c}, t}, Csv.Bad{at, why}, fl, cur, out, w, pos), pre)
        case Csv.KO{}:
          match d:
            case Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}:
              match m:
                case Csv.RS{}:
                  ih => lb => pre => PUT(mf, False{}, Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, c, "", fl, cur, out, w, pos, t)(
                      l2 => ih(t, Csv.Unq{Csv.push("", c), l2}, fl, cur, out, w, 1n+pos)(lb)(Unit{}))
                case Csv.FS{}:
                  ih => lb => pre => PUT(mf, False{}, Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, c, "", fl, cur, out, w, pos, t)(
                      l2 => ih(t, Csv.Unq{Csv.push("", c), l2}, fl, cur, out, w, 1n+pos)(lb)(Unit{}))
                case Csv.Unq{acc, l}:
                  ih => lb => pre => PUT(l, False{}, Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, c, acc, fl, cur, out, w, pos, t)(
                      l2 => ih(t, Csv.Unq{Csv.push(acc, c), l2}, fl, cur, out, w, 1n+pos)(lb)(Unit{}))
                case Csv.Quo{acc, l}:
                  ih => lb => pre => PUT(l, True{}, Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, c, acc, fl, cur, out, w, pos, t)(
                      l2 => ih(t, Csv.Quo{Csv.push(acc, c), l2}, fl, cur, out, w, 1n+pos)(lb)(Unit{}))
                case Csv.QQ{acc, l}:
                  ih => lb => pre => BADR(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, t, pos, Csv.AfterQuote{}, fl, cur, out, w, pos)
                case Csv.CRp{acc, at}:
                  ih => lb => pre => absurd(SIM(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KO{}, c}, t}, Csv.CRp{acc, at}, fl, cur, out, w, pos), pre)
                case Csv.Bad{at, why}:
                  ih => lb => pre => absurd(SIM(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, Con{Spec.Mark{Csv.KO{}, c}, t}, Csv.Bad{at, why}, fl, cur, out, w, pos), pre)

# THEOREM: on every input the fuel bounds, from every mode the grammar
# can be in, the reader reads what the grammar reads
def sim(+n: Nat, ms: List<&2, Spec.Mark>, +d: Csv.Dialect, +m: Csv.Mode, +fl: Nat,
  +cur: List<&2, Bytes()>, +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat) ->
  LEb(ms, n) -> Pre(m) -> SIM(d, ms, m, fl, cur, out, w, pos):
  match n ms:
    case _ Nil{}:
      lb => pre => END(d, m, fl, cur, out, w, pos)(pre)
    case 0n Con{x, t}:
      lb => pre => absurd(SIM(d, Con{x, t}, m, fl, cur, out, w, pos), lb)
    case 1n+k Con{x, t}:
      lb => pre => STEP(k, x, d, m, t, fl, cur, out, w, pos)(
        ms2 => m2 => fl2 => cur2 => out2 => w2 => pos2 =>
          sim(k, ms2, d, m2, fl2, cur2, out2, w2, pos2))(lb)(pre)

# the laws, whole
def sim.new(+d: Csv.Dialect, +bs: List<&2, U32>) ->
  {R(d, Spec.marks(d, bs), Csv.new(d)) == Spec.parse(bs, d) : Csv.Out}:
  match d:
    case Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}:
      sim(List.length(&2, Spec.Mark, Spec.marks(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, bs)), Spec.marks(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, bs), Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, Csv.RS{}, mn,
        Nil{}, Nil{}, None{}, 0n)(lb.refl(Spec.marks(Csv.Dialect{dl, q, a, b, cr, h, mf, mn, rg, pd}, bs)))(Unit{})

def Laws.csv_sim(d, bs):
  Equal.trans(Csv.Out, Csv.result(d, Csv.finish(d, Csv.feed(d, bs, Csv.new(d)))),
    R(d, Spec.marks(d, bs), Csv.new(d)), Spec.parse(bs, d),
    Equal.cong(Csv.P, Csv.Out, p => Csv.result(d, Csv.finish(d, p)), Csv.feed(d, bs, Csv.new(d)),
      feedk(d, Spec.marks(d, bs), Csv.new(d)), feed_is_feedk(d, bs, Csv.new(d))),
    sim.new(d, bs))

def Laws.csv_sim_buf(d, b):
  %Equal.sym(Csv.P, Csv.feed_buf(d, b, Csv.new(d)), Csv.feed(d, Bytes.to_list(b), Csv.new(d)),
    Laws.feed_buf_is_feed(d, b, Csv.new(d))) :
    {Csv.result(d, Csv.finish(d, _)) == Spec.parse(Bytes.to_list(b), d) : Csv.Out}
  Laws.csv_sim(d, Bytes.to_list(b))

# reads fed one after another are their bytes fed at once (the kit's
# reads_is)
def reads.is(+d: Csv.Dialect, rs: List<&2, Bytes()>, +p: Csv.P) ->
  {Laws.reads(d, rs, p) == Csv.feed(d, Bytes.to_list(Bytes.concat(rs)), p) : Csv.P}:
  Wr.reads_is(~Csv.Dialect, ~Csv.P, ~Csv.wstep, ~Csv.wadv, ~adv_ok, d, rs, p)

def Laws.csv_sim_reads(d, rs):
  %Equal.sym(Csv.P, Laws.reads(d, rs, Csv.new(d)), Csv.feed(d, Bytes.to_list(Bytes.concat(rs)), Csv.new(d)),
    reads.is(d, rs, Csv.new(d))) :
    {Csv.result(d, Csv.finish(d, _)) == Spec.parse(Bytes.to_list(Bytes.concat(rs)), d) : Csv.Out}
  Laws.csv_sim(d, Bytes.to_list(Bytes.concat(rs)))


# The writer
# ==========
#
# round_trip reads show's output back with the byte machine. The writer
# builds its output in an accumulator; pfx.* say every piece it adds is
# the accumulator followed by the piece alone, so the reader reads the
# pieces one after another (slow_app). A field without a special byte
# is read as it is (UR, UF); an escaped one's doubled quotes are read as
# one each (UESC, QF); a delimiter ends a field (TD) and CRLF a record
# (TCRLF); then records (REC) and the document (DOC). pa is the offset
# after the bytes, which the reader keeps.

def slow_app(+d: Csv.Dialect, a: Bytes(), -b: Bytes(), p: Csv.P) ->
  {Csv.feed_buf.slow(d, Bytes.append(a, b), p) ==
    Csv.feed_buf.slow(d, b, Csv.feed_buf.slow(d, a, p)) : Csv.P}:
  match a:
    case SNil{}:
      {==}
    case SCon{Chr{c}, t}:
      slow_app(d, t, b, Csv.step(d, p, c))

def pa(s: Bytes(), pos: Nat) -> Nat:
  match s:
    case SNil{}:
      pos
    case SCon{h, t}:
      pa(t, 1n+pos)

def pa_app(a: Bytes(), -b: Bytes(), pos: Nat) -> {pa(Bytes.append(a, b), pos) == pa(b, pa(a, pos)) : Nat}:
  match a:
    case SNil{}:
      {==}
    case SCon{h, t}:
      pa_app(t, b, 1n+pos)

# a byte whose class is known steps by that class
def STK(+d: Csv.Dialect, +c: U32, -k: Csv.K, e: {Csv.cls(d, c) == k : Csv.K}, +m: Csv.Mode, +fl: Nat,
  +cur: List<&2, Bytes()>, +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat) ->
  {Csv.step(d, Csv.P{m, fl, cur, out, w, pos}, c) == Csv.step.at(d, m, k, c, fl, cur, out, w, pos) : Csv.P}:
  Equal.cong(Csv.K, Csv.P, kk => Csv.step.at(d, m, kk, c, fl, cur, out, w, pos), Csv.cls(d, c), k, e)

# three equalities in a row
def tr3(-A: Type, -x: A, -y: A, -z: A, -v: A, e1: {x == y : A}, e2: {y == z : A}, e3: {z == v : A}) ->
  {x == v : A}:
  Equal.trans(A, x, y, v, e1, Equal.trans(A, y, z, v, e2, e3))

# Every piece is the accumulator, then the piece
def pfx.put(k: Csv.K, -c: U32, +acc: Bytes()) ->
  {Csv.esc.put(k, c, acc) == Bytes.append(acc, Csv.esc.put(k, c, "")) : Bytes()}:
  match k:
    case Csv.KQ{}:
      app_assoc(acc, Csv.one(c), Csv.one(c))
    case Csv.KD{}:
      {==}
    case Csv.KCR{}:
      {==}
    case Csv.KLF{}:
      {==}
    case Csv.KO{}:
      {==}

def pfx.esc(+d: Csv.Dialect, +s: Bytes(), +acc: Bytes()) ->
  {Csv.esc(d, s, acc) == Bytes.append(acc, Csv.esc(d, s, "")) : Bytes()}:
  match s:
    case SNil{}:
      Equal.sym(Bytes(), Bytes.append(acc, ""), acc, app_nil(acc))
    case SCon{Chr{+c}, t}:
      tr3(Bytes(), Csv.esc(d, t, Csv.esc.put(Csv.cls(d, c), c, acc)),
        Bytes.append(Csv.esc.put(Csv.cls(d, c), c, acc), Csv.esc(d, t, "")),
        Bytes.append(Bytes.append(acc, Csv.esc.put(Csv.cls(d, c), c, "")), Csv.esc(d, t, "")),
        Bytes.append(acc, Csv.esc(d, t, Csv.esc.put(Csv.cls(d, c), c, ""))),
        pfx.esc(d, t, Csv.esc.put(Csv.cls(d, c), c, acc)),
        Equal.cong(Bytes(), Bytes(), x => Bytes.append(x, Csv.esc(d, t, "")),
          Csv.esc.put(Csv.cls(d, c), c, acc), Bytes.append(acc, Csv.esc.put(Csv.cls(d, c), c, "")),
          pfx.put(Csv.cls(d, c), c, acc)),
        Equal.trans(Bytes(), Bytes.append(Bytes.append(acc, Csv.esc.put(Csv.cls(d, c), c, "")),
          Csv.esc(d, t, "")),
          Bytes.append(acc, Bytes.append(Csv.esc.put(Csv.cls(d, c), c, ""), Csv.esc(d, t, ""))),
          Bytes.append(acc, Csv.esc(d, t, Csv.esc.put(Csv.cls(d, c), c, ""))),
          app_assoc(acc, Csv.esc.put(Csv.cls(d, c), c, ""), Csv.esc(d, t, "")),
          Equal.cong(Bytes(), Bytes(), x => Bytes.append(acc, x),
            Bytes.append(Csv.esc.put(Csv.cls(d, c), c, ""), Csv.esc(d, t, "")),
            Csv.esc(d, t, Csv.esc.put(Csv.cls(d, c), c, "")),
            Equal.sym(Bytes(), Csv.esc(d, t, Csv.esc.put(Csv.cls(d, c), c, "")),
              Bytes.append(Csv.esc.put(Csv.cls(d, c), c, ""), Csv.esc(d, t, "")),
              pfx.esc(d, t, Csv.esc.put(Csv.cls(d, c), c, ""))))))

def pfx.quoted(+d: Csv.Dialect, +s: Bytes(), +acc: Bytes()) ->
  {Csv.quoted(d, s, acc) == Bytes.append(acc, Csv.quoted(d, s, "")) : Bytes()}:
  tr3(Bytes(), Bytes.append(Csv.esc(d, s, Csv.push(acc, Csv.quote(d))), Csv.one(Csv.quote(d))),
    Bytes.append(Bytes.append(Csv.push(acc, Csv.quote(d)), Csv.esc(d, s, "")), Csv.one(Csv.quote(d))),
    Bytes.append(Bytes.append(acc, Bytes.append(Csv.one(Csv.quote(d)), Csv.esc(d, s, ""))),
      Csv.one(Csv.quote(d))),
    Bytes.append(acc, Bytes.append(Csv.esc(d, s, Csv.one(Csv.quote(d))), Csv.one(Csv.quote(d)))),
    Equal.cong(Bytes(), Bytes(), x => Bytes.append(x, Csv.one(Csv.quote(d))),
      Csv.esc(d, s, Csv.push(acc, Csv.quote(d))),
      Bytes.append(Csv.push(acc, Csv.quote(d)), Csv.esc(d, s, "")),
      pfx.esc(d, s, Csv.push(acc, Csv.quote(d)))),
    Equal.cong(Bytes(), Bytes(), x => Bytes.append(x, Csv.one(Csv.quote(d))),
      Bytes.append(Csv.push(acc, Csv.quote(d)), Csv.esc(d, s, "")),
      Bytes.append(acc, Bytes.append(Csv.one(Csv.quote(d)), Csv.esc(d, s, ""))),
      app_assoc(acc, Csv.one(Csv.quote(d)), Csv.esc(d, s, ""))),
    Equal.trans(Bytes(),
      Bytes.append(Bytes.append(acc, Bytes.append(Csv.one(Csv.quote(d)), Csv.esc(d, s, ""))),
        Csv.one(Csv.quote(d))),
      Bytes.append(acc, Bytes.append(Bytes.append(Csv.one(Csv.quote(d)), Csv.esc(d, s, "")),
        Csv.one(Csv.quote(d)))),
      Bytes.append(acc, Bytes.append(Csv.esc(d, s, Csv.one(Csv.quote(d))), Csv.one(Csv.quote(d)))),
      app_assoc(acc, Bytes.append(Csv.one(Csv.quote(d)), Csv.esc(d, s, "")), Csv.one(Csv.quote(d))),
      Equal.cong(Bytes(), Bytes(), x => Bytes.append(acc, Bytes.append(x, Csv.one(Csv.quote(d)))),
        Bytes.append(Csv.one(Csv.quote(d)), Csv.esc(d, s, "")), Csv.esc(d, s, Csv.one(Csv.quote(d))),
        Equal.sym(Bytes(), Csv.esc(d, s, Csv.one(Csv.quote(d))),
          Bytes.append(Csv.one(Csv.quote(d)), Csv.esc(d, s, "")),
          pfx.esc(d, s, Csv.one(Csv.quote(d)))))))

def pfx.fat(+d: Csv.Dialect, qb: Bool, +s: Bytes(), +acc: Bytes()) ->
  {Csv.field.at(d, qb, s, acc) == Bytes.append(acc, Csv.field.at(d, qb, s, "")) : Bytes()}:
  match qb:
    case True{}:
      pfx.quoted(d, s, acc)
    case False{}:
      {==}

def pfx.crlf(acc: Bytes()) -> {Csv.crlf.put(acc) == Bytes.append(acc, Csv.crlf.put("")) : Bytes()}:
  app_assoc(acc, Csv.one(13), Csv.one(10))

# x ++ (a ++ b) ++ c, reassociated
def asc3(+x: Bytes(), +a: Bytes(), +b: Bytes(), +c: Bytes()) ->
  {Bytes.append(Bytes.append(Bytes.append(x, a), b), c) ==
    Bytes.append(x, Bytes.append(Bytes.append(a, b), c)) : Bytes()}:
  Equal.trans(Bytes(), Bytes.append(Bytes.append(Bytes.append(x, a), b), c),
    Bytes.append(Bytes.append(x, Bytes.append(a, b)), c),
    Bytes.append(x, Bytes.append(Bytes.append(a, b), c)),
    Equal.cong(Bytes(), Bytes(), y => Bytes.append(y, c), Bytes.append(Bytes.append(x, a), b),
      Bytes.append(x, Bytes.append(a, b)), app_assoc(x, a, b)),
    app_assoc(x, Bytes.append(a, b), c))

def pfx.fields(+d: Csv.Dialect, +r: List<&2, Bytes()>, +acc: Bytes()) ->
  {Csv.fields(d, r, acc) == Bytes.append(acc, Csv.fields(d, r, "")) : Bytes()}:
  match r:
    case Nil{}:
      Equal.sym(Bytes(), Bytes.append(acc, ""), acc, app_nil(acc))
    case Con{+f, t}:
      Equal.trans(Bytes(), Csv.fields(d, t, Csv.field(d, f, Csv.push(acc, Csv.delim(d)))),
        Bytes.append(acc, Bytes.append(Bytes.append(Csv.one(Csv.delim(d)), Csv.field(d, f, "")),
          Csv.fields(d, t, ""))),
        Bytes.append(acc, Csv.fields(d, t, Csv.field(d, f, Csv.one(Csv.delim(d))))),
        tr3(Bytes(), Csv.fields(d, t, Csv.field(d, f, Csv.push(acc, Csv.delim(d)))),
          Bytes.append(Csv.field(d, f, Csv.push(acc, Csv.delim(d))), Csv.fields(d, t, "")),
          Bytes.append(Bytes.append(Csv.push(acc, Csv.delim(d)), Csv.field(d, f, "")), Csv.fields(d, t, "")),
          Bytes.append(acc, Bytes.append(Bytes.append(Csv.one(Csv.delim(d)), Csv.field(d, f, "")),
            Csv.fields(d, t, ""))),
          pfx.fields(d, t, Csv.field(d, f, Csv.push(acc, Csv.delim(d)))),
          Equal.cong(Bytes(), Bytes(), x => Bytes.append(x, Csv.fields(d, t, "")),
            Csv.field(d, f, Csv.push(acc, Csv.delim(d))),
            Bytes.append(Csv.push(acc, Csv.delim(d)), Csv.field(d, f, "")),
            pfx.fat(d, Csv.needs(d, f), f, Csv.push(acc, Csv.delim(d)))),
          asc3(acc, Csv.one(Csv.delim(d)), Csv.field(d, f, ""), Csv.fields(d, t, ""))),
        Equal.cong(Bytes(), Bytes(), x => Bytes.append(acc, x),
          Bytes.append(Bytes.append(Csv.one(Csv.delim(d)), Csv.field(d, f, "")), Csv.fields(d, t, "")),
          Csv.fields(d, t, Csv.field(d, f, Csv.one(Csv.delim(d)))),
          Equal.sym(Bytes(), Csv.fields(d, t, Csv.field(d, f, Csv.one(Csv.delim(d)))),
            Bytes.append(Bytes.append(Csv.one(Csv.delim(d)), Csv.field(d, f, "")), Csv.fields(d, t, "")),
            Equal.trans(Bytes(), Csv.fields(d, t, Csv.field(d, f, Csv.one(Csv.delim(d)))),
              Bytes.append(Csv.field(d, f, Csv.one(Csv.delim(d))), Csv.fields(d, t, "")),
              Bytes.append(Bytes.append(Csv.one(Csv.delim(d)), Csv.field(d, f, "")), Csv.fields(d, t, "")),
              pfx.fields(d, t, Csv.field(d, f, Csv.one(Csv.delim(d)))),
              Equal.cong(Bytes(), Bytes(), x => Bytes.append(x, Csv.fields(d, t, "")),
                Csv.field(d, f, Csv.one(Csv.delim(d))),
                Bytes.append(Csv.one(Csv.delim(d)), Csv.field(d, f, "")),
                pfx.fat(d, Csv.needs(d, f), f, Csv.one(Csv.delim(d))))))))

# a record of two fields or more: its first field, the rest after it, CRLF
def rec2.pfx(+d: Csv.Dialect, +f: Bytes(), +gs: List<&2, Bytes()>, +acc: Bytes()) ->
  {Csv.crlf.put(Csv.fields(d, gs, Csv.field(d, f, acc))) ==
    Bytes.append(acc, Csv.crlf.put(Csv.fields(d, gs, Csv.field(d, f, "")))) : Bytes()}:
  tr3(Bytes(), Csv.crlf.put(Csv.fields(d, gs, Csv.field(d, f, acc))),
    Bytes.append(Csv.fields(d, gs, Csv.field(d, f, acc)), Csv.crlf.put("")),
    Bytes.append(Bytes.append(Bytes.append(acc, Csv.field(d, f, "")), Csv.fields(d, gs, "")),
      Csv.crlf.put("")),
    Bytes.append(acc, Csv.crlf.put(Csv.fields(d, gs, Csv.field(d, f, "")))),
    pfx.crlf(Csv.fields(d, gs, Csv.field(d, f, acc))),
    Equal.cong(Bytes(), Bytes(), x => Bytes.append(x, Csv.crlf.put("")),
      Csv.fields(d, gs, Csv.field(d, f, acc)),
      Bytes.append(Bytes.append(acc, Csv.field(d, f, "")), Csv.fields(d, gs, "")),
      Equal.trans(Bytes(), Csv.fields(d, gs, Csv.field(d, f, acc)),
        Bytes.append(Csv.field(d, f, acc), Csv.fields(d, gs, "")),
        Bytes.append(Bytes.append(acc, Csv.field(d, f, "")), Csv.fields(d, gs, "")),
        pfx.fields(d, gs, Csv.field(d, f, acc)),
        Equal.cong(Bytes(), Bytes(), x => Bytes.append(x, Csv.fields(d, gs, "")),
          Csv.field(d, f, acc), Bytes.append(acc, Csv.field(d, f, "")),
          pfx.fat(d, Csv.needs(d, f), f, acc)))),
    Equal.trans(Bytes(),
      Bytes.append(Bytes.append(Bytes.append(acc, Csv.field(d, f, "")), Csv.fields(d, gs, "")),
        Csv.crlf.put("")),
      Bytes.append(acc, Bytes.append(Bytes.append(Csv.field(d, f, ""), Csv.fields(d, gs, "")),
        Csv.crlf.put(""))),
      Bytes.append(acc, Csv.crlf.put(Csv.fields(d, gs, Csv.field(d, f, "")))),
      asc3(acc, Csv.field(d, f, ""), Csv.fields(d, gs, ""), Csv.crlf.put("")),
      Equal.cong(Bytes(), Bytes(), x => Bytes.append(acc, x),
        Bytes.append(Bytes.append(Csv.field(d, f, ""), Csv.fields(d, gs, "")), Csv.crlf.put("")),
        Csv.crlf.put(Csv.fields(d, gs, Csv.field(d, f, ""))),
        Equal.sym(Bytes(), Csv.crlf.put(Csv.fields(d, gs, Csv.field(d, f, ""))),
          Bytes.append(Bytes.append(Csv.field(d, f, ""), Csv.fields(d, gs, "")), Csv.crlf.put("")),
          Equal.trans(Bytes(), Csv.crlf.put(Csv.fields(d, gs, Csv.field(d, f, ""))),
            Bytes.append(Csv.fields(d, gs, Csv.field(d, f, "")), Csv.crlf.put("")),
            Bytes.append(Bytes.append(Csv.field(d, f, ""), Csv.fields(d, gs, "")), Csv.crlf.put("")),
            pfx.crlf(Csv.fields(d, gs, Csv.field(d, f, ""))),
            Equal.cong(Bytes(), Bytes(), x => Bytes.append(x, Csv.crlf.put("")),
              Csv.fields(d, gs, Csv.field(d, f, "")),
              Bytes.append(Csv.field(d, f, ""), Csv.fields(d, gs, "")),
              pfx.fields(d, gs, Csv.field(d, f, ""))))))))

def pfx.record(+d: Csv.Dialect, +r: List<&2, Bytes()>, +acc: Bytes()) ->
  {Csv.record(d, r, acc) == Bytes.append(acc, Csv.record(d, r, "")) : Bytes()}:
  match r:
    case Nil{}:
      pfx.crlf(acc)
    case Con{+f, t}:
      match t:
        case Nil{}:
          tr3(Bytes(), Csv.crlf.put(Csv.field.at(d, Bool.or(Csv.needs(d, f), String.is_empty(f)), f, acc)),
            Bytes.append(Csv.field.at(d, Bool.or(Csv.needs(d, f), String.is_empty(f)), f, acc),
              Csv.crlf.put("")),
            Bytes.append(Bytes.append(acc, Csv.field.at(d, Bool.or(Csv.needs(d, f), String.is_empty(f)), f,
              "")), Csv.crlf.put("")),
            Bytes.append(acc, Csv.crlf.put(Csv.field.at(d, Bool.or(Csv.needs(d, f), String.is_empty(f)), f,
              ""))),
            pfx.crlf(Csv.field.at(d, Bool.or(Csv.needs(d, f), String.is_empty(f)), f, acc)),
            Equal.cong(Bytes(), Bytes(), x => Bytes.append(x, Csv.crlf.put("")),
              Csv.field.at(d, Bool.or(Csv.needs(d, f), String.is_empty(f)), f, acc),
              Bytes.append(acc, Csv.field.at(d, Bool.or(Csv.needs(d, f), String.is_empty(f)), f, "")),
              pfx.fat(d, Bool.or(Csv.needs(d, f), String.is_empty(f)), f, acc)),
            Equal.trans(Bytes(),
              Bytes.append(Bytes.append(acc, Csv.field.at(d, Bool.or(Csv.needs(d, f), String.is_empty(f)),
                f, "")), Csv.crlf.put("")),
              Bytes.append(acc, Bytes.append(Csv.field.at(d, Bool.or(Csv.needs(d, f), String.is_empty(f)),
                f, ""), Csv.crlf.put(""))),
              Bytes.append(acc, Csv.crlf.put(Csv.field.at(d, Bool.or(Csv.needs(d, f), String.is_empty(f)),
                f, ""))),
              app_assoc(acc, Csv.field.at(d, Bool.or(Csv.needs(d, f), String.is_empty(f)), f, ""),
                Csv.crlf.put("")),
              Equal.cong(Bytes(), Bytes(), x => Bytes.append(acc, x),
                Bytes.append(Csv.field.at(d, Bool.or(Csv.needs(d, f), String.is_empty(f)), f, ""),
                  Csv.crlf.put("")),
                Csv.crlf.put(Csv.field.at(d, Bool.or(Csv.needs(d, f), String.is_empty(f)), f, "")),
                Equal.sym(Bytes(),
                  Csv.crlf.put(Csv.field.at(d, Bool.or(Csv.needs(d, f), String.is_empty(f)), f, "")),
                  Bytes.append(Csv.field.at(d, Bool.or(Csv.needs(d, f), String.is_empty(f)), f, ""),
                    Csv.crlf.put("")),
                  pfx.crlf(Csv.field.at(d, Bool.or(Csv.needs(d, f), String.is_empty(f)), f, ""))))))
        case Con{+g, +u}:
          rec2.pfx(d, f, Con{g, u}, acc)

def pfx.show(+d: Csv.Dialect, +rs: List<&2, List<&2, Bytes()>>, +acc: Bytes()) ->
  {Csv.show.go(d, rs, acc) == Bytes.append(acc, Csv.show.go(d, rs, "")) : Bytes()}:
  match rs:
    case Nil{}:
      Equal.sym(Bytes(), Bytes.append(acc, ""), acc, app_nil(acc))
    case Con{+r, t}:
      tr3(Bytes(), Csv.show.go(d, t, Csv.record(d, r, acc)),
        Bytes.append(Csv.record(d, r, acc), Csv.show.go(d, t, "")),
        Bytes.append(Bytes.append(acc, Csv.record(d, r, "")), Csv.show.go(d, t, "")),
        Bytes.append(acc, Csv.show.go(d, t, Csv.record(d, r, ""))),
        pfx.show(d, t, Csv.record(d, r, acc)),
        Equal.cong(Bytes(), Bytes(), x => Bytes.append(x, Csv.show.go(d, t, "")),
          Csv.record(d, r, acc), Bytes.append(acc, Csv.record(d, r, "")), pfx.record(d, r, acc)),
        Equal.trans(Bytes(), Bytes.append(Bytes.append(acc, Csv.record(d, r, "")), Csv.show.go(d, t, "")),
          Bytes.append(acc, Bytes.append(Csv.record(d, r, ""), Csv.show.go(d, t, ""))),
          Bytes.append(acc, Csv.show.go(d, t, Csv.record(d, r, ""))),
          app_assoc(acc, Csv.record(d, r, ""), Csv.show.go(d, t, "")),
          Equal.cong(Bytes(), Bytes(), x => Bytes.append(acc, x),
            Bytes.append(Csv.record(d, r, ""), Csv.show.go(d, t, "")),
            Csv.show.go(d, t, Csv.record(d, r, "")),
            Equal.sym(Bytes(), Csv.show.go(d, t, Csv.record(d, r, "")),
              Bytes.append(Csv.record(d, r, ""), Csv.show.go(d, t, "")),
              pfx.show(d, t, Csv.record(d, r, ""))))))

# Bools and Nats
# --------------

def and.l(a: Bool, -b: Bool) -> {Bool.and(a, b) == True{} : Bool} -> {a == True{} : Bool}:
  match a:
    case True{}:
      e => {==}
    case False{}:
      e => e

def and.r(a: Bool, -b: Bool) -> {Bool.and(a, b) == True{} : Bool} -> {b == True{} : Bool}:
  match a:
    case True{}:
      e => e
    case False{}:
      e => no({b == True{} : Bool}, e)

def not.t(b: Bool) -> {Bool.not(b) == True{} : Bool} -> {b == False{} : Bool}:
  match b:
    case True{}:
      e => no({True{} == False{} : Bool}, e)
    case False{}:
      e => {==}

# a field that must be quoted is quoted: needs is special, or more
def needs.ok(s: Bool, -x: Bool) -> {Bool.or(Bool.not(s), Bool.or(s, x)) == True{} : Bool}:
  match s:
    case True{}:
      {==}
    case False{}:
      {==}

def needs.ok2(s: Bool, -x: Bool, -y: Bool) ->
  {Bool.or(Bool.not(s), Bool.or(Bool.or(s, x), y)) == True{} : Bool}:
  match s:
    case True{}:
      {==}
    case False{}:
      {==}

def or.f(y: Bool) -> {Bool.or(y, False{}) == True{} : Bool} -> {y == True{} : Bool}:
  match y:
    case True{}:
      e => {==}
    case False{}:
      e => e

def nat_eq(a: Nat, b: Nat) -> {Nat.is_eq(a, b) == True{} : Bool} -> {a == b : Nat}:
  match a b:
    case 0n 0n:
      e => {==}
    case 0n 1n+q:
      e => no({0n == 1n+q : Nat}, e)
    case 1n+p 0n:
      e => no({1n+p == 0n : Nat}, e)
    case 1n+p 1n+q:
      e => Equal.cong(Nat, Nat, x => 1n+x, p, q, nat_eq(p, q)(e))

def nat_refl(a: Nat) -> {Nat.is_eq(a, a) == True{} : Bool}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      nat_refl(p)

def sub0(a: Nat) -> {Nat.sub(a, 0n) == a : Nat}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      {==}

def bref(b: Bool) -> {Word.cmp.fin(b, b, EQ{}) == EQ{} : Cmp}:
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

# U32 equality is reflexive
def wref(n: Nat, w: Word(n)) -> {Word.cmp(n, w, w) == EQ{} : Cmp}:
  match n:
    case 0n:
      {==}
    case 1n+p:
      match w:
        case WCon{b, t}:
          %Equal.sym(Cmp, Word.cmp(p, t, t), EQ{}, wref(p, t)) : {Word.cmp.fin(b, b, _) == EQ{} : Cmp}
          bref(b)

def u32ref(x: U32) -> {U32.is_eq(x, x) == True{} : Bool}:
  match x:
    case U32{w}:
      %Equal.sym(Cmp, Word.cmp(32n, w, w), EQ{}, wref(32n, w)) : {Cmp.is_eq(_) == True{} : Bool}
      {==}

def kp.f(b: Bool, -x: Csv.K, -y: Csv.K) -> {b == False{} : Bool} -> {Csv.k.pick(b, x, y) == y : Csv.K}:
  match b:
    case True{}:
      e => no({x == y : Csv.K}, Equal.sym(Bool, True{}, False{}, e))
    case False{}:
      e => {==}

def kp.t(b: Bool, -x: Csv.K, -y: Csv.K) -> {b == True{} : Bool} -> {Csv.k.pick(b, x, y) == x : Csv.K}:
  match b:
    case True{}:
      e => {==}
    case False{}:
      e => no({y == x : Csv.K}, e)

# What sane says
# --------------

def SX(-a: Bool, -b: Bool, -c: Bool, -e: Bool, -f: Bool, -g: Bool) -> Type:
  {a == True{} : Bool} & {b == False{} : Bool} & {c == False{} : Bool} & {e == False{} : Bool} &
    {f == False{} : Bool} & {g == False{} : Bool}

def sa6(+a: Bool, +b: Bool, +c: Bool, +e: Bool, +f: Bool, +g: Bool) ->
  {Bool.and(Bool.and(Bool.and(Bool.and(Bool.and(a, Bool.not(b)), Bool.not(c)), Bool.not(e)), Bool.not(f)),
    Bool.not(g)) == True{} : Bool} -> SX(a, b, c, e, f, g):
  +h =>
    +h5 = and.l(Bool.and(Bool.and(Bool.and(Bool.and(a, Bool.not(b)), Bool.not(c)), Bool.not(e)), Bool.not(f)),
      Bool.not(g))(h)
    +h4 = and.l(Bool.and(Bool.and(Bool.and(a, Bool.not(b)), Bool.not(c)), Bool.not(e)), Bool.not(f))(h5)
    +h3 = and.l(Bool.and(Bool.and(a, Bool.not(b)), Bool.not(c)), Bool.not(e))(h4)
    +h2 = and.l(Bool.and(a, Bool.not(b)), Bool.not(c))(h3)
    (and.l(a, Bool.not(b))(h2),
      (not.t(b)(and.r(a, Bool.not(b))(h2)),
        (not.t(c)(and.r(Bool.and(a, Bool.not(b)), Bool.not(c))(h3)),
          (not.t(e)(and.r(Bool.and(Bool.and(a, Bool.not(b)), Bool.not(c)), Bool.not(e))(h4)),
            (not.t(f)(and.r(Bool.and(Bool.and(Bool.and(a, Bool.not(b)), Bool.not(c)), Bool.not(e)),
              Bool.not(f))(h5)),
              not.t(g)(and.r(Bool.and(Bool.and(Bool.and(Bool.and(a, Bool.not(b)), Bool.not(c)), Bool.not(e)),
                Bool.not(f)), Bool.not(g))(h)))))))

# the sane dialect's facts, one Bool at a time: sane is
# ((((crlf && dq) && q13) && d13) && q10) && d10
def SA(+d: Csv.Dialect) -> Type:
  SX(Csv.crlf(d), U32.is_eq(Csv.delim(d), Csv.quote(d)), U32.is_eq(13, Csv.quote(d)),
    U32.is_eq(13, Csv.delim(d)), U32.is_eq(10, Csv.quote(d)), U32.is_eq(10, Csv.delim(d)))

def sane.sa(+d: Csv.Dialect) -> {Csv.sane(d) == True{} : Bool} -> SA(d):
  h => sa6(Csv.crlf(d), U32.is_eq(Csv.delim(d), Csv.quote(d)), U32.is_eq(13, Csv.quote(d)),
    U32.is_eq(13, Csv.delim(d)), U32.is_eq(10, Csv.quote(d)), U32.is_eq(10, Csv.delim(d)))(h)

# the four bytes the writer writes about the text are the classes it
# means them as
def cls.q(+d: Csv.Dialect) -> {Csv.cls(d, Csv.quote(d)) == Csv.KQ{} : Csv.K}:
  kp.t(U32.is_eq(Csv.quote(d), Csv.quote(d)), Csv.KQ{}, Csv.k.pick(U32.is_eq(Csv.quote(d), Csv.delim(d)),
    Csv.KD{}, Csv.k.pick(U32.is_eq(Csv.quote(d), 13), Csv.KCR{}, Csv.k.pick(U32.is_eq(Csv.quote(d), 10),
    Csv.KLF{}, Csv.KO{}))))(u32ref(Csv.quote(d)))

def cls.d(+d: Csv.Dialect, s: SA(d)) -> {Csv.cls(d, Csv.delim(d)) == Csv.KD{} : Csv.K}:
  (h1, s2) = s
  (h2, s3) = s2
  Equal.trans(Csv.K, Csv.cls(d, Csv.delim(d)),
    Csv.k.pick(U32.is_eq(Csv.delim(d), Csv.delim(d)), Csv.KD{}, Csv.k.pick(U32.is_eq(Csv.delim(d), 13),
      Csv.KCR{}, Csv.k.pick(U32.is_eq(Csv.delim(d), 10), Csv.KLF{}, Csv.KO{}))), Csv.KD{},
    kp.f(U32.is_eq(Csv.delim(d), Csv.quote(d)), Csv.KQ{},
      Csv.k.pick(U32.is_eq(Csv.delim(d), Csv.delim(d)), Csv.KD{}, Csv.k.pick(U32.is_eq(Csv.delim(d), 13),
        Csv.KCR{}, Csv.k.pick(U32.is_eq(Csv.delim(d), 10), Csv.KLF{}, Csv.KO{}))))(h2),
    kp.t(U32.is_eq(Csv.delim(d), Csv.delim(d)), Csv.KD{}, Csv.k.pick(U32.is_eq(Csv.delim(d), 13),
      Csv.KCR{}, Csv.k.pick(U32.is_eq(Csv.delim(d), 10), Csv.KLF{}, Csv.KO{})))(u32ref(Csv.delim(d))))

def cls.cr(+d: Csv.Dialect, s: SA(d)) -> {Csv.cls(d, 13) == Csv.KCR{} : Csv.K}:
  (h1, s2) = s
  (h2, s3) = s2
  (h3, s4) = s3
  (h4, s5) = s4
  Equal.trans(Csv.K, Csv.cls(d, 13),
    Csv.k.pick(U32.is_eq(13, Csv.delim(d)), Csv.KD{}, Csv.k.pick(U32.is_eq(13, 13), Csv.KCR{},
      Csv.k.pick(U32.is_eq(13, 10), Csv.KLF{}, Csv.KO{}))), Csv.KCR{},
    kp.f(U32.is_eq(13, Csv.quote(d)), Csv.KQ{}, Csv.k.pick(U32.is_eq(13, Csv.delim(d)), Csv.KD{},
      Csv.k.pick(U32.is_eq(13, 13), Csv.KCR{}, Csv.k.pick(U32.is_eq(13, 10), Csv.KLF{}, Csv.KO{}))))(h3),
    kp.f(U32.is_eq(13, Csv.delim(d)), Csv.KD{}, Csv.k.pick(U32.is_eq(13, 13), Csv.KCR{},
      Csv.k.pick(U32.is_eq(13, 10), Csv.KLF{}, Csv.KO{})))(h4))

def cls.lf(+d: Csv.Dialect, s: SA(d)) -> {Csv.cls(d, 10) == Csv.KLF{} : Csv.K}:
  (h1, s2) = s
  (h2, s3) = s2
  (h3, s4) = s3
  (h4, s5) = s4
  (h5, h6) = s5
  Equal.trans(Csv.K, Csv.cls(d, 10),
    Csv.k.pick(U32.is_eq(10, Csv.delim(d)), Csv.KD{}, Csv.k.pick(U32.is_eq(10, 13), Csv.KCR{},
      Csv.k.pick(U32.is_eq(10, 10), Csv.KLF{}, Csv.KO{}))), Csv.KLF{},
    kp.f(U32.is_eq(10, Csv.quote(d)), Csv.KQ{}, Csv.k.pick(U32.is_eq(10, Csv.delim(d)), Csv.KD{},
      Csv.k.pick(U32.is_eq(10, 13), Csv.KCR{}, Csv.k.pick(U32.is_eq(10, 10), Csv.KLF{}, Csv.KO{}))))(h5),
    kp.f(U32.is_eq(10, Csv.delim(d)), Csv.KD{}, Csv.k.pick(U32.is_eq(10, 13), Csv.KCR{},
      Csv.k.pick(U32.is_eq(10, 10), Csv.KLF{}, Csv.KO{})))(h6))

# Reading a field back
# --------------------

# a byte that makes a field special is not one an unquoted run stays on
def so(k: Csv.K, -x: Bool) -> {Bool.or(Bool.not(Csv.is_o(k)), x) == False{} : Bool} ->
  {Csv.stay(False{}, k) == True{} : Bool}:
  match k:
    case Csv.KO{}:
      e => {==}
    case Csv.KQ{}:
      e => no({False{} == True{} : Bool}, Equal.sym(Bool, True{}, False{}, e))
    case Csv.KD{}:
      e => no({False{} == True{} : Bool}, Equal.sym(Bool, True{}, False{}, e))
    case Csv.KCR{}:
      e => no({False{} == True{} : Bool}, Equal.sym(Bool, True{}, False{}, e))
    case Csv.KLF{}:
      e => no({False{} == True{} : Bool}, Equal.sym(Bool, True{}, False{}, e))

# the state after a field's text, unquoted
def PU(+a: Bytes(), +l: Nat, +fl: Nat, +cur: List<&2, Bytes()>, +out: List<&2, List<&2, Bytes()>>,
  +w: Maybe<&2, Nat>, +pos: Nat) -> Csv.P:
  Csv.P{Csv.Unq{a, l}, fl, cur, out, w, pos}

def UR.at(+d: Csv.Dialect, +c: U32, k: Csv.K, e: {Csv.cls(d, c) == k : Csv.K}, +t: Bytes(), +a: Bytes(),
  +l2: Nat, +fl: Nat, +cur: List<&2, Bytes()>, +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>,
  +pos: Nat,
  ih: {Csv.special(d, t) == False{} : Bool} -> {Nat.is_le(Csv.size(t), l2) == True{} : Bool} ->
    {Csv.feed_buf.slow(d, t, PU(Csv.push(a, c), l2, fl, cur, out, w, 1n+pos)) ==
      PU(Bytes.append(Csv.push(a, c), t), Nat.sub(l2, Csv.size(t)), fl, cur, out, w, pa(t, 1n+pos)) :
      Csv.P}) ->
  {Bool.or(Bool.not(Csv.is_o(k)), Csv.special(d, t)) == False{} : Bool} ->
  {Nat.is_le(Csv.size(t), l2) == True{} : Bool} ->
  {Csv.feed_buf.slow(d, t, Csv.step(d, PU(a, 1n+l2, fl, cur, out, w, pos), c)) ==
    PU(Bytes.append(a, SCon{Chr{c}, t}), Nat.sub(l2, Csv.size(t)), fl, cur, out, w, pa(t, 1n+pos)) :
    Csv.P}:
  match k:
    case Csv.KO{}:
      hs => hl => tr3(Csv.P, Csv.feed_buf.slow(d, t, Csv.step(d, PU(a, 1n+l2, fl, cur, out, w, pos), c)),
        Csv.feed_buf.slow(d, t, PU(Csv.push(a, c), l2, fl, cur, out, w, 1n+pos)),
        PU(Bytes.append(Csv.push(a, c), t), Nat.sub(l2, Csv.size(t)), fl, cur, out, w, pa(t, 1n+pos)),
        PU(Bytes.append(a, SCon{Chr{c}, t}), Nat.sub(l2, Csv.size(t)), fl, cur, out, w, pa(t, 1n+pos)),
        Equal.cong(Csv.P, Csv.P, x => Csv.feed_buf.slow(d, t, x),
          Csv.step(d, PU(a, 1n+l2, fl, cur, out, w, pos), c),
          Csv.step.at(d, Csv.Unq{a, 1n+l2}, Csv.KO{}, c, fl, cur, out, w, pos),
          STK(d, c, Csv.KO{}, e, Csv.Unq{a, 1n+l2}, fl, cur, out, w, pos)),
        ih(hs)(hl),
        Equal.cong(Bytes(), Csv.P, x => PU(x, Nat.sub(l2, Csv.size(t)), fl, cur, out, w, pa(t, 1n+pos)),
          Bytes.append(Csv.push(a, c), t), Bytes.append(a, SCon{Chr{c}, t}), push_app(a, c, t)))
    case Csv.KQ{}:
      hs => hl => no({Csv.feed_buf.slow(d, t, Csv.step(d, PU(a, 1n+l2, fl, cur, out, w, pos), c)) ==
        PU(Bytes.append(a, SCon{Chr{c}, t}), Nat.sub(l2, Csv.size(t)), fl, cur, out, w, pa(t, 1n+pos)) :
        Csv.P}, Equal.sym(Bool, True{}, False{}, hs))
    case Csv.KD{}:
      hs => hl => no({Csv.feed_buf.slow(d, t, Csv.step(d, PU(a, 1n+l2, fl, cur, out, w, pos), c)) ==
        PU(Bytes.append(a, SCon{Chr{c}, t}), Nat.sub(l2, Csv.size(t)), fl, cur, out, w, pa(t, 1n+pos)) :
        Csv.P}, Equal.sym(Bool, True{}, False{}, hs))
    case Csv.KCR{}:
      hs => hl => no({Csv.feed_buf.slow(d, t, Csv.step(d, PU(a, 1n+l2, fl, cur, out, w, pos), c)) ==
        PU(Bytes.append(a, SCon{Chr{c}, t}), Nat.sub(l2, Csv.size(t)), fl, cur, out, w, pa(t, 1n+pos)) :
        Csv.P}, Equal.sym(Bool, True{}, False{}, hs))
    case Csv.KLF{}:
      hs => hl => no({Csv.feed_buf.slow(d, t, Csv.step(d, PU(a, 1n+l2, fl, cur, out, w, pos), c)) ==
        PU(Bytes.append(a, SCon{Chr{c}, t}), Nat.sub(l2, Csv.size(t)), fl, cur, out, w, pa(t, 1n+pos)) :
        Csv.P}, Equal.sym(Bool, True{}, False{}, hs))

# LEMMA: an unquoted field's text, byte by byte, into the field
def UR(+d: Csv.Dialect, +f: Bytes(), +a: Bytes(), +l: Nat, +fl: Nat, +cur: List<&2, Bytes()>,
  +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat) ->
  {Csv.special(d, f) == False{} : Bool} -> {Nat.is_le(Csv.size(f), l) == True{} : Bool} ->
  {Csv.feed_buf.slow(d, f, PU(a, l, fl, cur, out, w, pos)) ==
    PU(Bytes.append(a, f), Nat.sub(l, Csv.size(f)), fl, cur, out, w, pa(f, pos)) : Csv.P}:
  match f l:
    case SNil{} 0n:
      hs => hl =>
        %Equal.sym(Bytes(), Bytes.append(a, ""), a, app_nil(a)) :
          {PU(a, 0n, fl, cur, out, w, pos) == PU(_, 0n, fl, cur, out, w, pos) : Csv.P}
        {==}
    case SNil{} 1n+x:
      hs => hl =>
        %Equal.sym(Bytes(), Bytes.append(a, ""), a, app_nil(a)) :
          {PU(a, 1n+x, fl, cur, out, w, pos) == PU(_, 1n+x, fl, cur, out, w, pos) : Csv.P}
        {==}
    case SCon{Chr{c}, t} 0n:
      hs => hl => no({Csv.feed_buf.slow(d, SCon{Chr{c}, t}, PU(a, 0n, fl, cur, out, w, pos)) ==
        PU(Bytes.append(a, SCon{Chr{c}, t}), Nat.sub(0n, Csv.size(SCon{Chr{c}, t})), fl, cur, out, w,
          pa(SCon{Chr{c}, t}, pos)) : Csv.P}, hl)
    case SCon{Chr{+c}, t} 1n+l2:
      UR.at(d, c, Csv.cls(d, c), {==}, t, a, l2, fl, cur, out, w, pos,
        UR(d, t, Csv.push(a, c), l2, fl, cur, out, w, 1n+pos))

# where a field starts: at a record's start, or after a delimiter
def e.of(isr: Bool) -> E:
  match isr:
    case True{}:
      ERec{}
    case False{}:
      EFld{}

# the mode an unquoted field leaves the reader in: its start's, if it
# is empty
def ue(isr: Bool, +f: Bytes(), +l: Nat) -> E:
  match f:
    case SNil{}:
      e.of(isr)
    case SCon{h, t}:
      EPl{SCon{h, t}, Nat.sub(l, Csv.size(SCon{h, t}))}

def UF.con(+d: Csv.Dialect, +isr: Bool, +c: U32, +t: Bytes(), +fl: Nat, +cur: List<&2, Bytes()>,
  +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat) ->
  {Csv.special(d, SCon{Chr{c}, t}) == False{} : Bool} ->
  {Nat.is_le(Csv.size(SCon{Chr{c}, t}), Csv.max_field(d)) == True{} : Bool} ->
  {Csv.feed_buf.slow(d, SCon{Chr{c}, t}, Csv.P{ent.m(isr), fl, cur, out, w, pos}) ==
    PU(SCon{Chr{c}, t}, Nat.sub(Csv.max_field(d), Csv.size(SCon{Chr{c}, t})), fl, cur, out, w,
      pa(SCon{Chr{c}, t}, pos)) : Csv.P}:
  +hs => hl => Equal.trans(Csv.P, Csv.feed_buf.slow(d, SCon{Chr{c}, t}, Csv.P{ent.m(isr), fl, cur, out, w, pos}),
    Csv.feed_buf.slow(d, SCon{Chr{c}, t}, PU("", Csv.max_field(d), fl, cur, out, w, pos)),
    PU(SCon{Chr{c}, t}, Nat.sub(Csv.max_field(d), Csv.size(SCon{Chr{c}, t})), fl, cur, out, w,
      pa(SCon{Chr{c}, t}, pos)),
    Equal.cong(Csv.P, Csv.P, x => Csv.feed_buf.slow(d, t, x),
      Csv.step.at(d, ent.m(isr), Csv.cls(d, c), c, fl, cur, out, w, pos),
      Csv.step.at(d, Csv.Unq{"", Csv.max_field(d)}, Csv.cls(d, c), c, fl, cur, out, w, pos),
      lem.ent.step(d, isr, Csv.cls(d, c), c, fl, cur, out, w, pos)(so(Csv.cls(d, c), Csv.special(d, t))(hs))),
    UR(d, SCon{Chr{c}, t}, "", Csv.max_field(d), fl, cur, out, w, pos)(hs)(hl))

# LEMMA: an unquoted field from where it starts
def UF(+d: Csv.Dialect, isr: Bool, +f: Bytes(), +fl: Nat, +cur: List<&2, Bytes()>,
  +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat) ->
  {Csv.special(d, f) == False{} : Bool} -> {Nat.is_le(Csv.size(f), Csv.max_field(d)) == True{} : Bool} ->
  {Csv.feed_buf.slow(d, f, Csv.P{ent.m(isr), fl, cur, out, w, pos}) ==
    Csv.P{e.m(ue(isr, f, Csv.max_field(d))), fl, cur, out, w, pa(f, pos)} : Csv.P}:
  match isr f:
    case True{} SNil{}:
      hs => hl => {==}
    case False{} SNil{}:
      hs => hl => {==}
    case True{} SCon{Chr{c}, t}:
      UF.con(d, True{}, c, t, fl, cur, out, w, pos)
    case False{} SCon{Chr{c}, t}:
      UF.con(d, False{}, c, t, fl, cur, out, w, pos)

# the state inside quotes
def PQ(+a: Bytes(), +l: Nat, +fl: Nat, +cur: List<&2, Bytes()>, +out: List<&2, List<&2, Bytes()>>,
  +w: Maybe<&2, Nat>, +pos: Nat) -> Csv.P:
  Csv.P{Csv.Quo{a, l}, fl, cur, out, w, pos}

# the rest of an escaped text after its first byte (written as W)
def UESC.fin(+d: Csv.Dialect, +W: Bytes(), +c: U32, +t: Bytes(), +a: Bytes(), +l2: Nat, +fl: Nat,
  +cur: List<&2, Bytes()>, +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat,
  inner: {Csv.feed_buf.slow(d, W, PQ(a, 1n+l2, fl, cur, out, w, pos)) ==
    PQ(Csv.push(a, c), l2, fl, cur, out, w, pa(W, pos)) : Csv.P},
  ih: {Csv.feed_buf.slow(d, Csv.esc(d, t, ""), PQ(Csv.push(a, c), l2, fl, cur, out, w, pa(W, pos))) ==
    PQ(Bytes.append(Csv.push(a, c), t), Nat.sub(l2, Csv.size(t)), fl, cur, out, w,
      pa(Csv.esc(d, t, ""), pa(W, pos))) : Csv.P}) ->
  {Csv.feed_buf.slow(d, Csv.esc(d, t, W), PQ(a, 1n+l2, fl, cur, out, w, pos)) ==
    PQ(Bytes.append(a, SCon{Chr{c}, t}), Nat.sub(l2, Csv.size(t)), fl, cur, out, w,
      pa(Csv.esc(d, t, W), pos)) : Csv.P}:
  tr3(Csv.P, Csv.feed_buf.slow(d, Csv.esc(d, t, W), PQ(a, 1n+l2, fl, cur, out, w, pos)),
    Csv.feed_buf.slow(d, Csv.esc(d, t, ""), Csv.feed_buf.slow(d, W, PQ(a, 1n+l2, fl, cur, out, w, pos))),
    Csv.feed_buf.slow(d, Csv.esc(d, t, ""), PQ(Csv.push(a, c), l2, fl, cur, out, w, pa(W, pos))),
    PQ(Bytes.append(a, SCon{Chr{c}, t}), Nat.sub(l2, Csv.size(t)), fl, cur, out, w,
      pa(Csv.esc(d, t, W), pos)),
    Equal.trans(Csv.P, Csv.feed_buf.slow(d, Csv.esc(d, t, W), PQ(a, 1n+l2, fl, cur, out, w, pos)),
      Csv.feed_buf.slow(d, Bytes.append(W, Csv.esc(d, t, "")), PQ(a, 1n+l2, fl, cur, out, w, pos)),
      Csv.feed_buf.slow(d, Csv.esc(d, t, ""), Csv.feed_buf.slow(d, W, PQ(a, 1n+l2, fl, cur, out, w, pos))),
      Equal.cong(Bytes(), Csv.P, x => Csv.feed_buf.slow(d, x, PQ(a, 1n+l2, fl, cur, out, w, pos)),
        Csv.esc(d, t, W), Bytes.append(W, Csv.esc(d, t, "")), pfx.esc(d, t, W)),
      slow_app(d, W, Csv.esc(d, t, ""), PQ(a, 1n+l2, fl, cur, out, w, pos))),
    Equal.cong(Csv.P, Csv.P, x => Csv.feed_buf.slow(d, Csv.esc(d, t, ""), x),
      Csv.feed_buf.slow(d, W, PQ(a, 1n+l2, fl, cur, out, w, pos)),
      PQ(Csv.push(a, c), l2, fl, cur, out, w, pa(W, pos)), inner),
    Equal.trans(Csv.P, Csv.feed_buf.slow(d, Csv.esc(d, t, ""), PQ(Csv.push(a, c), l2, fl, cur, out, w,
      pa(W, pos))),
      PQ(Bytes.append(Csv.push(a, c), t), Nat.sub(l2, Csv.size(t)), fl, cur, out, w,
        pa(Csv.esc(d, t, ""), pa(W, pos))),
      PQ(Bytes.append(a, SCon{Chr{c}, t}), Nat.sub(l2, Csv.size(t)), fl, cur, out, w,
        pa(Csv.esc(d, t, W), pos)),
      ih,
      Equal.trans(Csv.P, PQ(Bytes.append(Csv.push(a, c), t), Nat.sub(l2, Csv.size(t)), fl, cur, out, w,
        pa(Csv.esc(d, t, ""), pa(W, pos))),
        PQ(Bytes.append(a, SCon{Chr{c}, t}), Nat.sub(l2, Csv.size(t)), fl, cur, out, w,
          pa(Csv.esc(d, t, ""), pa(W, pos))),
        PQ(Bytes.append(a, SCon{Chr{c}, t}), Nat.sub(l2, Csv.size(t)), fl, cur, out, w,
          pa(Csv.esc(d, t, W), pos)),
        Equal.cong(Bytes(), Csv.P, x => PQ(x, Nat.sub(l2, Csv.size(t)), fl, cur, out, w,
          pa(Csv.esc(d, t, ""), pa(W, pos))), Bytes.append(Csv.push(a, c), t),
          Bytes.append(a, SCon{Chr{c}, t}), push_app(a, c, t)),
        Equal.cong(Nat, Csv.P, x => PQ(Bytes.append(a, SCon{Chr{c}, t}), Nat.sub(l2, Csv.size(t)), fl, cur,
          out, w, x), pa(Csv.esc(d, t, ""), pa(W, pos)), pa(Csv.esc(d, t, W), pos),
          Equal.sym(Nat, pa(Csv.esc(d, t, W), pos), pa(Csv.esc(d, t, ""), pa(W, pos)),
            Equal.trans(Nat, pa(Csv.esc(d, t, W), pos), pa(Bytes.append(W, Csv.esc(d, t, "")), pos),
              pa(Csv.esc(d, t, ""), pa(W, pos)),
              Equal.cong(Bytes(), Nat, x => pa(x, pos), Csv.esc(d, t, W), Bytes.append(W, Csv.esc(d, t, "")),
                pfx.esc(d, t, W)),
              pa_app(W, Csv.esc(d, t, ""), pos)))))))

# one byte inside quotes, as the writer wrote it: a quote twice, any
# other byte once
def UESC.one(+d: Csv.Dialect, +c: U32, k: Csv.K, +e: {Csv.cls(d, c) == k : Csv.K}, +a: Bytes(), +l2: Nat,
  +fl: Nat, +cur: List<&2, Bytes()>, +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat) ->
  {Csv.feed_buf.slow(d, Csv.esc.put(k, c, ""), PQ(a, 1n+l2, fl, cur, out, w, pos)) ==
    PQ(Csv.push(a, c), l2, fl, cur, out, w, pa(Csv.esc.put(k, c, ""), pos)) : Csv.P}:
  match k:
    case Csv.KQ{}:
      Equal.trans(Csv.P, Csv.step(d, Csv.step(d, PQ(a, 1n+l2, fl, cur, out, w, pos), c), c),
        Csv.step(d, Csv.P{Csv.QQ{a, 1n+l2}, fl, cur, out, w, 1n+pos}, c),
        PQ(Csv.push(a, c), l2, fl, cur, out, w, 1n+1n+pos),
        Equal.cong(Csv.P, Csv.P, x => Csv.step(d, x, c), Csv.step(d, PQ(a, 1n+l2, fl, cur, out, w, pos), c),
          Csv.P{Csv.QQ{a, 1n+l2}, fl, cur, out, w, 1n+pos},
          STK(d, c, Csv.KQ{}, e, Csv.Quo{a, 1n+l2}, fl, cur, out, w, pos)),
        STK(d, c, Csv.KQ{}, e, Csv.QQ{a, 1n+l2}, fl, cur, out, w, 1n+pos))
    case Csv.KD{}:
      STK(d, c, Csv.KD{}, e, Csv.Quo{a, 1n+l2}, fl, cur, out, w, pos)
    case Csv.KCR{}:
      STK(d, c, Csv.KCR{}, e, Csv.Quo{a, 1n+l2}, fl, cur, out, w, pos)
    case Csv.KLF{}:
      STK(d, c, Csv.KLF{}, e, Csv.Quo{a, 1n+l2}, fl, cur, out, w, pos)
    case Csv.KO{}:
      STK(d, c, Csv.KO{}, e, Csv.Quo{a, 1n+l2}, fl, cur, out, w, pos)

# LEMMA: an escaped text, as the writer wrote it, into the field
def UESC(+d: Csv.Dialect, +s: Bytes(), +a: Bytes(), +l: Nat, +fl: Nat, +cur: List<&2, Bytes()>,
  +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat) ->
  {Nat.is_le(Csv.size(s), l) == True{} : Bool} ->
  {Csv.feed_buf.slow(d, Csv.esc(d, s, ""), PQ(a, l, fl, cur, out, w, pos)) ==
    PQ(Bytes.append(a, s), Nat.sub(l, Csv.size(s)), fl, cur, out, w, pa(Csv.esc(d, s, ""), pos)) : Csv.P}:
  match s l:
    case SNil{} 0n:
      hl =>
        %Equal.sym(Bytes(), Bytes.append(a, ""), a, app_nil(a)) :
          {PQ(a, 0n, fl, cur, out, w, pos) == PQ(_, 0n, fl, cur, out, w, pos) : Csv.P}
        {==}
    case SNil{} 1n+x:
      hl =>
        %Equal.sym(Bytes(), Bytes.append(a, ""), a, app_nil(a)) :
          {PQ(a, 1n+x, fl, cur, out, w, pos) == PQ(_, 1n+x, fl, cur, out, w, pos) : Csv.P}
        {==}
    case SCon{Chr{c}, t} 0n:
      hl => no({Csv.feed_buf.slow(d, Csv.esc(d, SCon{Chr{c}, t}, ""), PQ(a, 0n, fl, cur, out, w, pos)) ==
        PQ(Bytes.append(a, SCon{Chr{c}, t}), Nat.sub(0n, Csv.size(SCon{Chr{c}, t})), fl, cur, out, w,
          pa(Csv.esc(d, SCon{Chr{c}, t}, ""), pos)) : Csv.P}, hl)
    case SCon{Chr{+c}, t} 1n+l2:
      hl => UESC.fin(d, Csv.esc.put(Csv.cls(d, c), c, ""), c, t, a, l2, fl, cur, out, w, pos,
        UESC.one(d, c, Csv.cls(d, c), {==}, a, l2, fl, cur, out, w, pos),
        UESC(d, t, Csv.push(a, c), l2, fl, cur, out, w, pa(Csv.esc.put(Csv.cls(d, c), c, ""), pos))(hl))

# the first byte of a field, a quote, opens it
def entq(+d: Csv.Dialect, isr: Bool, -c: U32, -fl: Nat, -cur: List<&2, Bytes()>,
  -out: List<&2, List<&2, Bytes()>>, -w: Maybe<&2, Nat>, -pos: Nat) ->
  {Csv.step.at(d, ent.m(isr), Csv.KQ{}, c, fl, cur, out, w, pos) ==
    PQ("", Csv.max_field(d), fl, cur, out, w, 1n+pos) : Csv.P}:
  match isr:
    case True{}:
      {==}
    case False{}:
      {==}

# LEMMA: a quoted field from where it starts: the reader is after its
# closing quote, holding its text
def QF(+d: Csv.Dialect, +isr: Bool, +s: Bytes(), +fl: Nat, +cur: List<&2, Bytes()>,
  +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat) ->
  {Nat.is_le(Csv.size(s), Csv.max_field(d)) == True{} : Bool} ->
  {Csv.feed_buf.slow(d, Csv.quoted(d, s, ""), Csv.P{ent.m(isr), fl, cur, out, w, pos}) ==
    Csv.P{Csv.QQ{s, Nat.sub(Csv.max_field(d), Csv.size(s))}, fl, cur, out, w,
      pa(Csv.quoted(d, s, ""), pos)} : Csv.P}:
  hl => tr3(Csv.P,
    Csv.feed_buf.slow(d, Csv.quoted(d, s, ""), Csv.P{ent.m(isr), fl, cur, out, w, pos}),
    Csv.step(d, Csv.feed_buf.slow(d, Csv.esc(d, s, ""), Csv.step(d, Csv.P{ent.m(isr), fl, cur, out, w, pos},
      Csv.quote(d))), Csv.quote(d)),
    Csv.step(d, PQ(s, Nat.sub(Csv.max_field(d), Csv.size(s)), fl, cur, out, w,
      pa(Csv.esc(d, s, ""), 1n+pos)), Csv.quote(d)),
    Csv.P{Csv.QQ{s, Nat.sub(Csv.max_field(d), Csv.size(s))}, fl, cur, out, w,
      pa(Csv.quoted(d, s, ""), pos)},
    Equal.trans(Csv.P, Csv.feed_buf.slow(d, Csv.quoted(d, s, ""), Csv.P{ent.m(isr), fl, cur, out, w, pos}),
      Csv.feed_buf.slow(d, Csv.one(Csv.quote(d)), Csv.feed_buf.slow(d, Csv.esc(d, s, Csv.one(Csv.quote(d))),
        Csv.P{ent.m(isr), fl, cur, out, w, pos})),
      Csv.step(d, Csv.feed_buf.slow(d, Csv.esc(d, s, ""), Csv.step(d, Csv.P{ent.m(isr), fl, cur, out, w, pos},
        Csv.quote(d))), Csv.quote(d)),
      slow_app(d, Csv.esc(d, s, Csv.one(Csv.quote(d))), Csv.one(Csv.quote(d)),
        Csv.P{ent.m(isr), fl, cur, out, w, pos}),
      Equal.cong(Csv.P, Csv.P, x => Csv.step(d, x, Csv.quote(d)),
        Csv.feed_buf.slow(d, Csv.esc(d, s, Csv.one(Csv.quote(d))), Csv.P{ent.m(isr), fl, cur, out, w, pos}),
        Csv.feed_buf.slow(d, Csv.esc(d, s, ""), Csv.step(d, Csv.P{ent.m(isr), fl, cur, out, w, pos},
          Csv.quote(d))),
        Equal.trans(Csv.P,
          Csv.feed_buf.slow(d, Csv.esc(d, s, Csv.one(Csv.quote(d))), Csv.P{ent.m(isr), fl, cur, out, w, pos}),
          Csv.feed_buf.slow(d, Bytes.append(Csv.one(Csv.quote(d)), Csv.esc(d, s, "")),
            Csv.P{ent.m(isr), fl, cur, out, w, pos}),
          Csv.feed_buf.slow(d, Csv.esc(d, s, ""), Csv.step(d, Csv.P{ent.m(isr), fl, cur, out, w, pos},
            Csv.quote(d))),
          Equal.cong(Bytes(), Csv.P, x => Csv.feed_buf.slow(d, x, Csv.P{ent.m(isr), fl, cur, out, w, pos}),
            Csv.esc(d, s, Csv.one(Csv.quote(d))), Bytes.append(Csv.one(Csv.quote(d)), Csv.esc(d, s, "")),
            pfx.esc(d, s, Csv.one(Csv.quote(d)))),
          {==}))),
    Equal.cong(Csv.P, Csv.P, x => Csv.step(d, x, Csv.quote(d)),
      Csv.feed_buf.slow(d, Csv.esc(d, s, ""), Csv.step(d, Csv.P{ent.m(isr), fl, cur, out, w, pos},
        Csv.quote(d))),
      PQ(s, Nat.sub(Csv.max_field(d), Csv.size(s)), fl, cur, out, w, pa(Csv.esc(d, s, ""), 1n+pos)),
      Equal.trans(Csv.P,
        Csv.feed_buf.slow(d, Csv.esc(d, s, ""), Csv.step(d, Csv.P{ent.m(isr), fl, cur, out, w, pos},
          Csv.quote(d))),
        Csv.feed_buf.slow(d, Csv.esc(d, s, ""), PQ("", Csv.max_field(d), fl, cur, out, w, 1n+pos)),
        PQ(s, Nat.sub(Csv.max_field(d), Csv.size(s)), fl, cur, out, w, pa(Csv.esc(d, s, ""), 1n+pos)),
        Equal.cong(Csv.P, Csv.P, x => Csv.feed_buf.slow(d, Csv.esc(d, s, ""), x),
          Csv.step(d, Csv.P{ent.m(isr), fl, cur, out, w, pos}, Csv.quote(d)),
          PQ("", Csv.max_field(d), fl, cur, out, w, 1n+pos),
          Equal.trans(Csv.P, Csv.step(d, Csv.P{ent.m(isr), fl, cur, out, w, pos}, Csv.quote(d)),
            Csv.step.at(d, ent.m(isr), Csv.KQ{}, Csv.quote(d), fl, cur, out, w, pos),
            PQ("", Csv.max_field(d), fl, cur, out, w, 1n+pos),
            STK(d, Csv.quote(d), Csv.KQ{}, cls.q(d), ent.m(isr), fl, cur, out, w, pos),
            entq(d, isr, Csv.quote(d), fl, cur, out, w, pos))),
        UESC(d, s, "", Csv.max_field(d), fl, cur, out, w, 1n+pos)(hl))),
    Equal.trans(Csv.P, Csv.step(d, PQ(s, Nat.sub(Csv.max_field(d), Csv.size(s)), fl, cur, out, w,
      pa(Csv.esc(d, s, ""), 1n+pos)), Csv.quote(d)),
      Csv.P{Csv.QQ{s, Nat.sub(Csv.max_field(d), Csv.size(s))}, fl, cur, out, w,
        1n+pa(Csv.esc(d, s, ""), 1n+pos)},
      Csv.P{Csv.QQ{s, Nat.sub(Csv.max_field(d), Csv.size(s))}, fl, cur, out, w,
        pa(Csv.quoted(d, s, ""), pos)},
      STK(d, Csv.quote(d), Csv.KQ{}, cls.q(d), Csv.Quo{s, Nat.sub(Csv.max_field(d), Csv.size(s))}, fl,
        cur, out, w, pa(Csv.esc(d, s, ""), 1n+pos)),
      Equal.cong(Nat, Csv.P, x => Csv.P{Csv.QQ{s, Nat.sub(Csv.max_field(d), Csv.size(s))}, fl, cur, out, w,
        x}, 1n+pa(Csv.esc(d, s, ""), 1n+pos), pa(Csv.quoted(d, s, ""), pos),
        Equal.sym(Nat, pa(Csv.quoted(d, s, ""), pos), 1n+pa(Csv.esc(d, s, ""), 1n+pos),
          Equal.trans(Nat, pa(Csv.quoted(d, s, ""), pos),
            pa(Csv.one(Csv.quote(d)), pa(Csv.esc(d, s, Csv.one(Csv.quote(d))), pos)),
            1n+pa(Csv.esc(d, s, ""), 1n+pos),
            pa_app(Csv.esc(d, s, Csv.one(Csv.quote(d))), Csv.one(Csv.quote(d)), pos),
            Equal.trans(Nat, 1n+pa(Csv.esc(d, s, Csv.one(Csv.quote(d))), pos),
              1n+pa(Bytes.append(Csv.one(Csv.quote(d)), Csv.esc(d, s, "")), pos),
              1n+pa(Csv.esc(d, s, ""), 1n+pos),
              Equal.cong(Bytes(), Nat, x => 1n+pa(x, pos), Csv.esc(d, s, Csv.one(Csv.quote(d))),
                Bytes.append(Csv.one(Csv.quote(d)), Csv.esc(d, s, "")), pfx.esc(d, s, Csv.one(Csv.quote(d)))),
              {==}))))))

# the mode a field leaves the reader in, quoted or not
def fe(qb: Bool, isr: Bool, +f: Bytes(), +mf: Nat) -> E:
  match qb:
    case True{}:
      ECl{f, Nat.sub(mf, Csv.size(f))}
    case False{}:
      ue(isr, f, mf)

def txt_fe(qb: Bool, isr: Bool, f: Bytes(), -mf: Nat) -> {e.txt(fe(qb, isr, f, mf)) == f : Bytes()}:
  match qb isr f:
    case True{} _ _:
      {==}
    case False{} True{} SNil{}:
      {==}
    case False{} False{} SNil{}:
      {==}
    case False{} _ SCon{h, t}:
      {==}

# LEMMA: a field as the writer wrote it, from where it starts
def FLD(+d: Csv.Dialect, qb: Bool, +isr: Bool, +f: Bytes(), +fl: Nat, +cur: List<&2, Bytes()>,
  +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat) ->
  {Bool.or(Bool.not(Csv.special(d, f)), qb) == True{} : Bool} ->
  {Nat.is_le(Csv.size(f), Csv.max_field(d)) == True{} : Bool} ->
  {Csv.feed_buf.slow(d, Csv.field.at(d, qb, f, ""), Csv.P{ent.m(isr), fl, cur, out, w, pos}) ==
    Csv.P{e.m(fe(qb, isr, f, Csv.max_field(d))), fl, cur, out, w, pa(Csv.field.at(d, qb, f, ""), pos)} :
    Csv.P}:
  match qb:
    case True{}:
      hs => hl => QF(d, isr, f, fl, cur, out, w, pos)(hl)
    case False{}:
      hs => hl => UF(d, isr, f, fl, cur, out, w, pos)(not.t(Csv.special(d, f))(or.f(Bool.not(Csv.special(d, f)))(hs)))(hl)

# Reading a record back
# ---------------------

# a delimiter after a field ends it
def TD(+d: Csv.Dialect, ee: E, +fl: Nat, +cur: List<&2, Bytes()>, +out: List<&2, List<&2, Bytes()>>,
  +w: Maybe<&2, Nat>, +pos: Nat, hd: {Csv.cls(d, Csv.delim(d)) == Csv.KD{} : Csv.K}) ->
  {Csv.feed_buf.slow(d, Csv.one(Csv.delim(d)), Csv.P{e.m(ee), fl, cur, out, w, pos}) ==
    Csv.endf(e.txt(ee), fl, cur, out, w, pos, Csv.FS{}, 1n+pos) : Csv.P}:
  match ee:
    case ERec{}:
      STK(d, Csv.delim(d), Csv.KD{}, hd, Csv.RS{}, fl, cur, out, w, pos)
    case EFld{}:
      STK(d, Csv.delim(d), Csv.KD{}, hd, Csv.FS{}, fl, cur, out, w, pos)
    case EPl{t, r}:
      STK(d, Csv.delim(d), Csv.KD{}, hd, Csv.Unq{t, r}, fl, cur, out, w, pos)
    case ECl{t, r}:
      STK(d, Csv.delim(d), Csv.KD{}, hd, Csv.QQ{t, r}, fl, cur, out, w, pos)

def CRS(+d: Csv.Dialect, ee: E, -fl: Nat, -cur: List<&2, Bytes()>, -out: List<&2, List<&2, Bytes()>>,
  -w: Maybe<&2, Nat>, -pos: Nat) ->
  {Csv.step.at(d, e.m(ee), Csv.KCR{}, 13, fl, cur, out, w, pos) == Csv.cr.at(d, e.txt(ee), fl, cur, out, w, pos) :
    Csv.P}:
  match ee:
    case ERec{}:
      {==}
    case EFld{}:
      {==}
    case EPl{t, r}:
      {==}
    case ECl{t, r}:
      {==}

# the LF of a CRLF, after its CR, ends the record there
def TCRLF.cr(+d: Csv.Dialect, +txt: Bytes(), +fl: Nat, +cur: List<&2, Bytes()>,
  +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat,
  hlf: {Csv.cls(d, 10) == Csv.KLF{} : Csv.K}, +hc: {Csv.crlf(d) == True{} : Bool}) ->
  {Csv.step(d, Csv.cr.at(d, txt, fl, cur, out, w, pos), 10) == Csv.endl(d, txt, fl, cur, out, w, pos, 1n+1n+pos) :
    Csv.P}:
  tr3(Csv.P, Csv.step(d, Csv.cr.at(d, txt, fl, cur, out, w, pos), 10),
    Csv.step(d, Csv.P{Csv.CRp{txt, pos}, fl, cur, out, w, 1n+pos}, 10),
    Csv.step.at(d, Csv.CRp{txt, pos}, Csv.KLF{}, 10, fl, cur, out, w, 1n+pos),
    Csv.endl(d, txt, fl, cur, out, w, pos, 1n+1n+pos),
    Equal.cong(Bool, Csv.P, bb => Csv.step(d, Csv.cr.at.ok(Bool.or(bb, Csv.cr(d)), txt, fl, cur, out, w, pos), 10),
      Csv.crlf(d), True{}, hc),
    STK(d, 10, Csv.KLF{}, hlf, Csv.CRp{txt, pos}, fl, cur, out, w, 1n+pos),
    Equal.cong(Bool, Csv.P, bb => Csv.crp.at(d, Bool.and(bb, Csv.is_lf(Csv.KLF{})), Csv.cr(d), txt, pos, Csv.KLF{}, 10,
      fl, cur, out, w, 1n+pos), Csv.crlf(d), True{}, hc))

# CRLF after a field ends the field, then the record
def TCRLF(+d: Csv.Dialect, +ee: E, +fl: Nat, +cur: List<&2, Bytes()>, +out: List<&2, List<&2, Bytes()>>,
  +w: Maybe<&2, Nat>, +pos: Nat, hcr: {Csv.cls(d, 13) == Csv.KCR{} : Csv.K},
  hlf: {Csv.cls(d, 10) == Csv.KLF{} : Csv.K}, hc: {Csv.crlf(d) == True{} : Bool}) ->
  {Csv.feed_buf.slow(d, Csv.crlf.put(""), Csv.P{e.m(ee), fl, cur, out, w, pos}) ==
    Csv.endl(d, e.txt(ee), fl, cur, out, w, pos, 1n+1n+pos) : Csv.P}:
  Equal.trans(Csv.P, Csv.step(d, Csv.step(d, Csv.P{e.m(ee), fl, cur, out, w, pos}, 13), 10),
    Csv.step(d, Csv.cr.at(d, e.txt(ee), fl, cur, out, w, pos), 10),
    Csv.endl(d, e.txt(ee), fl, cur, out, w, pos, 1n+1n+pos),
    Equal.cong(Csv.P, Csv.P, x => Csv.step(d, x, 10), Csv.step(d, Csv.P{e.m(ee), fl, cur, out, w, pos}, 13),
      Csv.cr.at(d, e.txt(ee), fl, cur, out, w, pos),
      Equal.trans(Csv.P, Csv.step(d, Csv.P{e.m(ee), fl, cur, out, w, pos}, 13),
        Csv.step.at(d, e.m(ee), Csv.KCR{}, 13, fl, cur, out, w, pos), Csv.cr.at(d, e.txt(ee), fl, cur, out, w, pos),
        STK(d, 13, Csv.KCR{}, hcr, e.m(ee), fl, cur, out, w, pos), CRS(d, ee, fl, cur, out, w, pos))),
    TCRLF.cr(d, e.txt(ee), fl, cur, out, w, pos, hlf, hc))

# the width check a record's end makes: none for the first record; for
# the rest, what the first left must be what this one leaves
def RW(+d: Csv.Dialect, w: Maybe<&2, Nat>, +f: Nat) -> Type:
  match w:
    case None{}:
      Unit
    case Some{x}:
      {Bool.or(Csv.ragged(d), Nat.is_eq(f, x)) == True{} : Bool}

def wnext(w: Maybe<&2, Nat>, f: Nat) -> Maybe<&2, Nat>:
  match w:
    case None{}:
      Some{f}
    case Some{x}:
      Some{x}

# a record's end, after CRLF
def RFE(+d: Csv.Dialect, w: Maybe<&2, Nat>, +f: Nat, +rec: List<&2, Bytes()>,
  +out: List<&2, List<&2, Bytes()>>, +at: Nat, +np: Nat) -> RW(d, w, f) ->
  {Csv.endr(d, f, rec, out, w, at, Csv.RS{}, np) ==
    Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, Con{rec, out}, wnext(w, f), np} : Csv.P}:
  match w:
    case None{}:
      hw => {==}
    case Some{+x}:
      hw => Equal.cong(Bool, Csv.P, bb => Csv.endr.ok(bb, d, rec, out, x, at, Csv.RS{}, np),
        Bool.or(Csv.ragged(d), Nat.is_eq(f, x)), True{}, hw)

# the bytes of the fields after a record's first, then CRLF
def RFB(+d: Csv.Dialect, +g: Bytes(), +u: List<&2, Bytes()>) ->
  {Bytes.append(Csv.fields(d, Con{g, u}, ""), Csv.crlf.put("")) ==
    SCon{Chr{Csv.delim(d)}, Bytes.append(Csv.field(d, g, ""), Bytes.append(Csv.fields(d, u, ""),
      Csv.crlf.put("")))} : Bytes()}:
  tr3(Bytes(), Bytes.append(Csv.fields(d, Con{g, u}, ""), Csv.crlf.put("")),
    Bytes.append(Bytes.append(Bytes.append(Csv.one(Csv.delim(d)), Csv.field(d, g, "")), Csv.fields(d, u, "")),
      Csv.crlf.put("")),
    Bytes.append(Csv.one(Csv.delim(d)), Bytes.append(Bytes.append(Csv.field(d, g, ""), Csv.fields(d, u, "")),
      Csv.crlf.put(""))),
    Bytes.append(Csv.one(Csv.delim(d)), Bytes.append(Csv.field(d, g, ""), Bytes.append(Csv.fields(d, u, ""),
      Csv.crlf.put("")))),
    Equal.cong(Bytes(), Bytes(), x => Bytes.append(x, Csv.crlf.put("")), Csv.fields(d, Con{g, u}, ""),
      Bytes.append(Bytes.append(Csv.one(Csv.delim(d)), Csv.field(d, g, "")), Csv.fields(d, u, "")),
      Equal.trans(Bytes(), Csv.fields(d, u, Csv.field(d, g, Csv.one(Csv.delim(d)))),
        Bytes.append(Csv.field(d, g, Csv.one(Csv.delim(d))), Csv.fields(d, u, "")),
        Bytes.append(Bytes.append(Csv.one(Csv.delim(d)), Csv.field(d, g, "")), Csv.fields(d, u, "")),
        pfx.fields(d, u, Csv.field(d, g, Csv.one(Csv.delim(d)))),
        Equal.cong(Bytes(), Bytes(), x => Bytes.append(x, Csv.fields(d, u, "")),
          Csv.field(d, g, Csv.one(Csv.delim(d))), Bytes.append(Csv.one(Csv.delim(d)), Csv.field(d, g, "")),
          pfx.fat(d, Csv.needs(d, g), g, Csv.one(Csv.delim(d)))))),
    asc3(Csv.one(Csv.delim(d)), Csv.field(d, g, ""), Csv.fields(d, u, ""), Csv.crlf.put("")),
    Equal.cong(Bytes(), Bytes(), x => Bytes.append(Csv.one(Csv.delim(d)), x),
      Bytes.append(Bytes.append(Csv.field(d, g, ""), Csv.fields(d, u, "")), Csv.crlf.put("")),
      Bytes.append(Csv.field(d, g, ""), Bytes.append(Csv.fields(d, u, ""), Csv.crlf.put(""))),
      app_assoc(Csv.field(d, g, ""), Csv.fields(d, u, ""), Csv.crlf.put(""))))

def RFP(+d: Csv.Dialect, +t: List<&2, Bytes()>, +cur: List<&2, Bytes()>, +txt: Bytes(),
  +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +f: Nat, +pos: Nat) -> Csv.P:
  Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, Con{List.reverse.go(&2, Bytes(), cur, Con{txt, t}), out},
    wnext(w, f), pa(Bytes.append(Csv.fields(d, t, ""), Csv.crlf.put("")), pos)}

def RFQ(+d: Csv.Dialect, +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +f: Nat,
  +rec: List<&2, Bytes()>, +p: Nat) -> Csv.P:
  Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, Con{rec, out}, wnext(w, f), p}

# the step of RF past one delimiter and one field
def RF.con(+d: Csv.Dialect, +g: Bytes(), +u: List<&2, Bytes()>, +ee: E, +f: Nat, +cur: List<&2, Bytes()>,
  +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat,
  hd: {Csv.cls(d, Csv.delim(d)) == Csv.KD{} : Csv.K},
  ih: {Csv.feed_buf.slow(d, Bytes.append(Csv.fields(d, u, ""), Csv.crlf.put("")),
    Csv.P{e.m(fe(Csv.needs(d, g), False{}, g, Csv.max_field(d))), f, Con{e.txt(ee), cur}, out, w,
      pa(Csv.field(d, g, ""), 1n+pos)}) ==
    RFP(d, u, Con{e.txt(ee), cur}, e.txt(fe(Csv.needs(d, g), False{}, g, Csv.max_field(d))), out, w,
      Nat.sub(f, 1n+List.length(&2, Bytes(), u)), pa(Csv.field(d, g, ""), 1n+pos)) : Csv.P},
  hlg: {Nat.is_le(Csv.size(g), Csv.max_field(d)) == True{} : Bool}) ->
  {Csv.feed_buf.slow(d, Bytes.append(Csv.fields(d, Con{g, u}, ""), Csv.crlf.put("")),
    Csv.P{e.m(ee), 1n+f, cur, out, w, pos}) ==
    RFP(d, Con{g, u}, cur, e.txt(ee), out, w, Nat.sub(f, 1n+List.length(&2, Bytes(), u)), pos) : Csv.P}:
  tr3(Csv.P,
    Csv.feed_buf.slow(d, Bytes.append(Csv.fields(d, Con{g, u}, ""), Csv.crlf.put("")),
      Csv.P{e.m(ee), 1n+f, cur, out, w, pos}),
    Csv.feed_buf.slow(d, Bytes.append(Csv.fields(d, u, ""), Csv.crlf.put("")),
      Csv.P{e.m(fe(Csv.needs(d, g), False{}, g, Csv.max_field(d))), f, Con{e.txt(ee), cur}, out, w,
        pa(Csv.field(d, g, ""), 1n+pos)}),
    RFP(d, u, Con{e.txt(ee), cur}, e.txt(fe(Csv.needs(d, g), False{}, g, Csv.max_field(d))), out, w,
      Nat.sub(f, 1n+List.length(&2, Bytes(), u)), pa(Csv.field(d, g, ""), 1n+pos)),
    RFP(d, Con{g, u}, cur, e.txt(ee), out, w, Nat.sub(f, 1n+List.length(&2, Bytes(), u)), pos),
    tr3(Csv.P,
      Csv.feed_buf.slow(d, Bytes.append(Csv.fields(d, Con{g, u}, ""), Csv.crlf.put("")),
        Csv.P{e.m(ee), 1n+f, cur, out, w, pos}),
      Csv.feed_buf.slow(d, Bytes.append(Csv.field(d, g, ""), Bytes.append(Csv.fields(d, u, ""), Csv.crlf.put(""))),
        Csv.step(d, Csv.P{e.m(ee), 1n+f, cur, out, w, pos}, Csv.delim(d))),
      Csv.feed_buf.slow(d, Bytes.append(Csv.field(d, g, ""), Bytes.append(Csv.fields(d, u, ""), Csv.crlf.put(""))),
        Csv.P{Csv.FS{}, f, Con{e.txt(ee), cur}, out, w, 1n+pos}),
      Csv.feed_buf.slow(d, Bytes.append(Csv.fields(d, u, ""), Csv.crlf.put("")),
        Csv.P{e.m(fe(Csv.needs(d, g), False{}, g, Csv.max_field(d))), f, Con{e.txt(ee), cur}, out, w,
          pa(Csv.field(d, g, ""), 1n+pos)}),
      Equal.cong(Bytes(), Csv.P, x => Csv.feed_buf.slow(d, x, Csv.P{e.m(ee), 1n+f, cur, out, w, pos}),
        Bytes.append(Csv.fields(d, Con{g, u}, ""), Csv.crlf.put("")),
        SCon{Chr{Csv.delim(d)}, Bytes.append(Csv.field(d, g, ""), Bytes.append(Csv.fields(d, u, ""),
          Csv.crlf.put("")))}, RFB(d, g, u)),
      Equal.cong(Csv.P, Csv.P, x => Csv.feed_buf.slow(d, Bytes.append(Csv.field(d, g, ""),
        Bytes.append(Csv.fields(d, u, ""), Csv.crlf.put(""))), x),
        Csv.step(d, Csv.P{e.m(ee), 1n+f, cur, out, w, pos}, Csv.delim(d)),
        Csv.P{Csv.FS{}, f, Con{e.txt(ee), cur}, out, w, 1n+pos},
        TD(d, ee, 1n+f, cur, out, w, pos, hd)),
      Equal.trans(Csv.P,
        Csv.feed_buf.slow(d, Bytes.append(Csv.field(d, g, ""), Bytes.append(Csv.fields(d, u, ""),
          Csv.crlf.put(""))), Csv.P{Csv.FS{}, f, Con{e.txt(ee), cur}, out, w, 1n+pos}),
        Csv.feed_buf.slow(d, Bytes.append(Csv.fields(d, u, ""), Csv.crlf.put("")),
          Csv.feed_buf.slow(d, Csv.field(d, g, ""), Csv.P{Csv.FS{}, f, Con{e.txt(ee), cur}, out, w, 1n+pos})),
        Csv.feed_buf.slow(d, Bytes.append(Csv.fields(d, u, ""), Csv.crlf.put("")),
          Csv.P{e.m(fe(Csv.needs(d, g), False{}, g, Csv.max_field(d))), f, Con{e.txt(ee), cur}, out, w,
            pa(Csv.field(d, g, ""), 1n+pos)}),
        slow_app(d, Csv.field(d, g, ""), Bytes.append(Csv.fields(d, u, ""), Csv.crlf.put("")),
          Csv.P{Csv.FS{}, f, Con{e.txt(ee), cur}, out, w, 1n+pos}),
        Equal.cong(Csv.P, Csv.P, x => Csv.feed_buf.slow(d, Bytes.append(Csv.fields(d, u, ""), Csv.crlf.put("")), x),
          Csv.feed_buf.slow(d, Csv.field(d, g, ""), Csv.P{Csv.FS{}, f, Con{e.txt(ee), cur}, out, w, 1n+pos}),
          Csv.P{e.m(fe(Csv.needs(d, g), False{}, g, Csv.max_field(d))), f, Con{e.txt(ee), cur}, out, w,
            pa(Csv.field(d, g, ""), 1n+pos)},
          FLD(d, Csv.needs(d, g), False{}, g, f, Con{e.txt(ee), cur}, out, w, 1n+pos)(
            needs.ok(Csv.special(d, g), Bool.and(Csv.pad(d), Csv.spaced(g))))(hlg)))),
    ih,
    Equal.trans(Csv.P,
      RFQ(d, out, w, Nat.sub(f, 1n+List.length(&2, Bytes(), u)),
        List.reverse.go(&2, Bytes(), cur, Con{e.txt(ee), Con{e.txt(fe(Csv.needs(d, g), False{}, g,
          Csv.max_field(d))), u}}),
        pa(Bytes.append(Csv.fields(d, u, ""), Csv.crlf.put("")), pa(Csv.field(d, g, ""), 1n+pos))),
      RFQ(d, out, w, Nat.sub(f, 1n+List.length(&2, Bytes(), u)),
        List.reverse.go(&2, Bytes(), cur, Con{e.txt(ee), Con{g, u}}),
        pa(Bytes.append(Csv.fields(d, u, ""), Csv.crlf.put("")), pa(Csv.field(d, g, ""), 1n+pos))),
      RFQ(d, out, w, Nat.sub(f, 1n+List.length(&2, Bytes(), u)),
        List.reverse.go(&2, Bytes(), cur, Con{e.txt(ee), Con{g, u}}),
        pa(Bytes.append(Csv.fields(d, Con{g, u}, ""), Csv.crlf.put("")), pos)),
      Equal.cong(Bytes(), Csv.P, x => RFQ(d, out, w, Nat.sub(f, 1n+List.length(&2, Bytes(), u)),
        List.reverse.go(&2, Bytes(), cur, Con{e.txt(ee), Con{x, u}}),
        pa(Bytes.append(Csv.fields(d, u, ""), Csv.crlf.put("")), pa(Csv.field(d, g, ""), 1n+pos))),
        e.txt(fe(Csv.needs(d, g), False{}, g, Csv.max_field(d))), g,
        txt_fe(Csv.needs(d, g), False{}, g, Csv.max_field(d))),
      Equal.cong(Nat, Csv.P, x => RFQ(d, out, w, Nat.sub(f, 1n+List.length(&2, Bytes(), u)),
        List.reverse.go(&2, Bytes(), cur, Con{e.txt(ee), Con{g, u}}), x),
        pa(Bytes.append(Csv.fields(d, u, ""), Csv.crlf.put("")), pa(Csv.field(d, g, ""), 1n+pos)),
        pa(Bytes.append(Csv.fields(d, Con{g, u}, ""), Csv.crlf.put("")), pos),
        Equal.sym(Nat, pa(Bytes.append(Csv.fields(d, Con{g, u}, ""), Csv.crlf.put("")), pos),
          pa(Bytes.append(Csv.fields(d, u, ""), Csv.crlf.put("")), pa(Csv.field(d, g, ""), 1n+pos)),
          Equal.trans(Nat, pa(Bytes.append(Csv.fields(d, Con{g, u}, ""), Csv.crlf.put("")), pos),
            pa(SCon{Chr{Csv.delim(d)}, Bytes.append(Csv.field(d, g, ""), Bytes.append(Csv.fields(d, u, ""),
              Csv.crlf.put("")))}, pos),
            pa(Bytes.append(Csv.fields(d, u, ""), Csv.crlf.put("")), pa(Csv.field(d, g, ""), 1n+pos)),
            Equal.cong(Bytes(), Nat, x => pa(x, pos), Bytes.append(Csv.fields(d, Con{g, u}, ""), Csv.crlf.put("")),
              SCon{Chr{Csv.delim(d)}, Bytes.append(Csv.field(d, g, ""), Bytes.append(Csv.fields(d, u, ""),
                Csv.crlf.put("")))}, RFB(d, g, u)),
            pa_app(Csv.field(d, g, ""), Bytes.append(Csv.fields(d, u, ""), Csv.crlf.put("")), 1n+pos))))))

# LEMMA: the fields after a record's first, then its CRLF: the record,
# kept whole, and the reader at the next record's start
def RF(+d: Csv.Dialect, +t: List<&2, Bytes()>, +ee: E, +fl: Nat, +cur: List<&2, Bytes()>,
  +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat,
  +hd: {Csv.cls(d, Csv.delim(d)) == Csv.KD{} : Csv.K}, +hcr: {Csv.cls(d, 13) == Csv.KCR{} : Csv.K},
  +hlf: {Csv.cls(d, 10) == Csv.KLF{} : Csv.K}, +hc: {Csv.crlf(d) == True{} : Bool}) ->
  {Nat.is_le(1n+List.length(&2, Bytes(), t), fl) == True{} : Bool} ->
  {Csv.fits.fields(d, t) == True{} : Bool} ->
  RW(d, w, Nat.sub(fl, 1n+List.length(&2, Bytes(), t))) ->
  {Csv.feed_buf.slow(d, Bytes.append(Csv.fields(d, t, ""), Csv.crlf.put("")), Csv.P{e.m(ee), fl, cur, out, w, pos}) ==
    RFP(d, t, cur, e.txt(ee), out, w, Nat.sub(fl, 1n+List.length(&2, Bytes(), t)), pos) : Csv.P}:
  match t fl:
    case Nil{} 0n:
      hl => hf => hw => no({Csv.feed_buf.slow(d, Csv.crlf.put(""), Csv.P{e.m(ee), 0n, cur, out, w, pos}) ==
        RFP(d, Nil{}, cur, e.txt(ee), out, w, 0n, pos) : Csv.P}, hl)
    case Nil{} 1n+f:
      match f:
        case 0n:
          hl => hf => hw => Equal.trans(Csv.P,
            Csv.feed_buf.slow(d, Csv.crlf.put(""), Csv.P{e.m(ee), 1n+0n, cur, out, w, pos}),
            Csv.endl(d, e.txt(ee), 1n+0n, cur, out, w, pos, 1n+1n+pos),
            RFP(d, Nil{}, cur, e.txt(ee), out, w, 0n, pos),
            TCRLF(d, ee, 1n+0n, cur, out, w, pos, hcr, hlf, hc),
            RFE(d, w, 0n, List.reverse(&2, Bytes(), Con{e.txt(ee), cur}), out, pos, 1n+1n+pos)(hw))
        case 1n+f2:
          hl => hf => hw => Equal.trans(Csv.P,
            Csv.feed_buf.slow(d, Csv.crlf.put(""), Csv.P{e.m(ee), 1n+1n+f2, cur, out, w, pos}),
            Csv.endl(d, e.txt(ee), 1n+1n+f2, cur, out, w, pos, 1n+1n+pos),
            RFP(d, Nil{}, cur, e.txt(ee), out, w, 1n+f2, pos),
            TCRLF(d, ee, 1n+1n+f2, cur, out, w, pos, hcr, hlf, hc),
            RFE(d, w, 1n+f2, List.reverse(&2, Bytes(), Con{e.txt(ee), cur}), out, pos, 1n+1n+pos)(hw))
    case Con{g, u} 0n:
      hl => hf => hw => no({Csv.feed_buf.slow(d, Bytes.append(Csv.fields(d, Con{g, u}, ""), Csv.crlf.put("")),
        Csv.P{e.m(ee), 0n, cur, out, w, pos}) ==
        RFP(d, Con{g, u}, cur, e.txt(ee), out, w, 0n, pos) : Csv.P}, hl)
    case Con{+g, +u} 1n+f:
      hl => +hf => hw => RF.con(d, g, u, ee, f, cur, out, w, pos, hd,
        RF(d, u, fe(Csv.needs(d, g), False{}, g, Csv.max_field(d)), f, Con{e.txt(ee), cur}, out, w,
          pa(Csv.field(d, g, ""), 1n+pos), hd, hcr, hlf, hc)(hl)(and.r(Nat.is_le(Csv.size(g), Csv.max_field(d)),
          Csv.fits.fields(d, u))(hf))(hw),
        and.l(Nat.is_le(Csv.size(g), Csv.max_field(d)), Csv.fits.fields(d, u))(hf))

# the first field of a record is quoted when it must be, and when it is
# the record's only field and empty
def rb(+d: Csv.Dialect, +f: Bytes(), t: List<&2, Bytes()>) -> Bool:
  match t:
    case Nil{}:
      Bool.or(Csv.needs(d, f), String.is_empty(f))
    case Con{g, u}:
      Csv.needs(d, f)

def rb.ok(+d: Csv.Dialect, +f: Bytes(), t: List<&2, Bytes()>) ->
  {Bool.or(Bool.not(Csv.special(d, f)), rb(d, f, t)) == True{} : Bool}:
  match t:
    case Nil{}:
      needs.ok2(Csv.special(d, f), Bool.and(Csv.pad(d), Csv.spaced(f)), String.is_empty(f))
    case Con{g, u}:
      needs.ok(Csv.special(d, f), Bool.and(Csv.pad(d), Csv.spaced(f)))

# a record's bytes: its first field, then the rest and CRLF
def REC.bytes(+d: Csv.Dialect, +f: Bytes(), t: List<&2, Bytes()>) ->
  {Csv.record(d, Con{f, t}, "") ==
    Bytes.append(Csv.field.at(d, rb(d, f, t), f, ""), Bytes.append(Csv.fields(d, t, ""), Csv.crlf.put(""))) :
    Bytes()}:
  match t:
    case Nil{}:
      pfx.crlf(Csv.field.at(d, Bool.or(Csv.needs(d, f), String.is_empty(f)), f, ""))
    case Con{+g, +u}:
      tr3(Bytes(), Csv.crlf.put(Csv.fields(d, Con{g, u}, Csv.field(d, f, ""))),
        Bytes.append(Csv.fields(d, Con{g, u}, Csv.field(d, f, "")), Csv.crlf.put("")),
        Bytes.append(Bytes.append(Csv.field(d, f, ""), Csv.fields(d, Con{g, u}, "")), Csv.crlf.put("")),
        Bytes.append(Csv.field(d, f, ""), Bytes.append(Csv.fields(d, Con{g, u}, ""), Csv.crlf.put(""))),
        pfx.crlf(Csv.fields(d, Con{g, u}, Csv.field(d, f, ""))),
        Equal.cong(Bytes(), Bytes(), x => Bytes.append(x, Csv.crlf.put("")),
          Csv.fields(d, Con{g, u}, Csv.field(d, f, "")),
          Bytes.append(Csv.field(d, f, ""), Csv.fields(d, Con{g, u}, "")),
          pfx.fields(d, Con{g, u}, Csv.field(d, f, ""))),
        app_assoc(Csv.field(d, f, ""), Csv.fields(d, Con{g, u}, ""), Csv.crlf.put("")))

def REC.con(+d: Csv.Dialect, +f: Bytes(), +t: List<&2, Bytes()>, +out: List<&2, List<&2, Bytes()>>,
  +w: Maybe<&2, Nat>, +pos: Nat, +hd: {Csv.cls(d, Csv.delim(d)) == Csv.KD{} : Csv.K},
  +hcr: {Csv.cls(d, 13) == Csv.KCR{} : Csv.K}, +hlf: {Csv.cls(d, 10) == Csv.KLF{} : Csv.K},
  +hc: {Csv.crlf(d) == True{} : Bool},
  hl: {Nat.is_le(1n+List.length(&2, Bytes(), t), Csv.max_fields(d)) == True{} : Bool},
  +hf: {Csv.fits.fields(d, Con{f, t}) == True{} : Bool},
  hw: RW(d, w, Nat.sub(Csv.max_fields(d), 1n+List.length(&2, Bytes(), t)))) ->
  {Csv.feed_buf.slow(d, Csv.record(d, Con{f, t}, ""), Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, out, w, pos}) ==
    Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, Con{Con{f, t}, out},
      wnext(w, Nat.sub(Csv.max_fields(d), 1n+List.length(&2, Bytes(), t))),
      pa(Csv.record(d, Con{f, t}, ""), pos)} : Csv.P}:
  tr3(Csv.P, Csv.feed_buf.slow(d, Csv.record(d, Con{f, t}, ""), Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, out, w, pos}),
    Csv.feed_buf.slow(d, Bytes.append(Csv.fields(d, t, ""), Csv.crlf.put("")),
      Csv.feed_buf.slow(d, Csv.field.at(d, rb(d, f, t), f, ""), Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, out, w, pos})),
    Csv.feed_buf.slow(d, Bytes.append(Csv.fields(d, t, ""), Csv.crlf.put("")),
      Csv.P{e.m(fe(rb(d, f, t), True{}, f, Csv.max_field(d))), Csv.max_fields(d), Nil{}, out, w,
        pa(Csv.field.at(d, rb(d, f, t), f, ""), pos)}),
    Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, Con{Con{f, t}, out},
      wnext(w, Nat.sub(Csv.max_fields(d), 1n+List.length(&2, Bytes(), t))),
      pa(Csv.record(d, Con{f, t}, ""), pos)},
    Equal.trans(Csv.P,
      Csv.feed_buf.slow(d, Csv.record(d, Con{f, t}, ""), Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, out, w, pos}),
      Csv.feed_buf.slow(d, Bytes.append(Csv.field.at(d, rb(d, f, t), f, ""), Bytes.append(Csv.fields(d, t, ""),
        Csv.crlf.put(""))), Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, out, w, pos}),
      Csv.feed_buf.slow(d, Bytes.append(Csv.fields(d, t, ""), Csv.crlf.put("")),
        Csv.feed_buf.slow(d, Csv.field.at(d, rb(d, f, t), f, ""), Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, out, w,
          pos})),
      Equal.cong(Bytes(), Csv.P, x => Csv.feed_buf.slow(d, x, Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, out, w, pos}),
        Csv.record(d, Con{f, t}, ""),
        Bytes.append(Csv.field.at(d, rb(d, f, t), f, ""), Bytes.append(Csv.fields(d, t, ""), Csv.crlf.put(""))),
        REC.bytes(d, f, t)),
      slow_app(d, Csv.field.at(d, rb(d, f, t), f, ""), Bytes.append(Csv.fields(d, t, ""), Csv.crlf.put("")),
        Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, out, w, pos})),
    Equal.cong(Csv.P, Csv.P, x => Csv.feed_buf.slow(d, Bytes.append(Csv.fields(d, t, ""), Csv.crlf.put("")), x),
      Csv.feed_buf.slow(d, Csv.field.at(d, rb(d, f, t), f, ""), Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, out, w, pos}),
      Csv.P{e.m(fe(rb(d, f, t), True{}, f, Csv.max_field(d))), Csv.max_fields(d), Nil{}, out, w,
        pa(Csv.field.at(d, rb(d, f, t), f, ""), pos)},
      FLD(d, rb(d, f, t), True{}, f, Csv.max_fields(d), Nil{}, out, w, pos)(rb.ok(d, f, t))(
        and.l(Nat.is_le(Csv.size(f), Csv.max_field(d)), Csv.fits.fields(d, t))(hf))),
    Equal.trans(Csv.P,
      Csv.feed_buf.slow(d, Bytes.append(Csv.fields(d, t, ""), Csv.crlf.put("")),
        Csv.P{e.m(fe(rb(d, f, t), True{}, f, Csv.max_field(d))), Csv.max_fields(d), Nil{}, out, w,
          pa(Csv.field.at(d, rb(d, f, t), f, ""), pos)}),
      RFP(d, t, Nil{}, e.txt(fe(rb(d, f, t), True{}, f, Csv.max_field(d))), out, w,
        Nat.sub(Csv.max_fields(d), 1n+List.length(&2, Bytes(), t)), pa(Csv.field.at(d, rb(d, f, t), f, ""), pos)),
      Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, Con{Con{f, t}, out},
        wnext(w, Nat.sub(Csv.max_fields(d), 1n+List.length(&2, Bytes(), t))),
        pa(Csv.record(d, Con{f, t}, ""), pos)},
      RF(d, t, fe(rb(d, f, t), True{}, f, Csv.max_field(d)), Csv.max_fields(d), Nil{}, out, w,
        pa(Csv.field.at(d, rb(d, f, t), f, ""), pos), hd, hcr, hlf, hc)(hl)(
        and.r(Nat.is_le(Csv.size(f), Csv.max_field(d)), Csv.fits.fields(d, t))(hf))(hw),
      Equal.trans(Csv.P,
        RFQ(d, out, w, Nat.sub(Csv.max_fields(d), 1n+List.length(&2, Bytes(), t)),
          Con{e.txt(fe(rb(d, f, t), True{}, f, Csv.max_field(d))), t},
          pa(Bytes.append(Csv.fields(d, t, ""), Csv.crlf.put("")), pa(Csv.field.at(d, rb(d, f, t), f, ""), pos))),
        RFQ(d, out, w, Nat.sub(Csv.max_fields(d), 1n+List.length(&2, Bytes(), t)), Con{f, t},
          pa(Bytes.append(Csv.fields(d, t, ""), Csv.crlf.put("")), pa(Csv.field.at(d, rb(d, f, t), f, ""), pos))),
        RFQ(d, out, w, Nat.sub(Csv.max_fields(d), 1n+List.length(&2, Bytes(), t)), Con{f, t},
          pa(Csv.record(d, Con{f, t}, ""), pos)),
        Equal.cong(Bytes(), Csv.P, x => RFQ(d, out, w, Nat.sub(Csv.max_fields(d), 1n+List.length(&2, Bytes(), t)),
          Con{x, t}, pa(Bytes.append(Csv.fields(d, t, ""), Csv.crlf.put("")),
            pa(Csv.field.at(d, rb(d, f, t), f, ""), pos))),
          e.txt(fe(rb(d, f, t), True{}, f, Csv.max_field(d))), f, txt_fe(rb(d, f, t), True{}, f, Csv.max_field(d))),
        Equal.cong(Nat, Csv.P, x => RFQ(d, out, w, Nat.sub(Csv.max_fields(d), 1n+List.length(&2, Bytes(), t)),
          Con{f, t}, x),
          pa(Bytes.append(Csv.fields(d, t, ""), Csv.crlf.put("")), pa(Csv.field.at(d, rb(d, f, t), f, ""), pos)),
          pa(Csv.record(d, Con{f, t}, ""), pos),
          Equal.sym(Nat, pa(Csv.record(d, Con{f, t}, ""), pos),
            pa(Bytes.append(Csv.fields(d, t, ""), Csv.crlf.put("")), pa(Csv.field.at(d, rb(d, f, t), f, ""), pos)),
            Equal.trans(Nat, pa(Csv.record(d, Con{f, t}, ""), pos),
              pa(Bytes.append(Csv.field.at(d, rb(d, f, t), f, ""), Bytes.append(Csv.fields(d, t, ""),
                Csv.crlf.put(""))), pos),
              pa(Bytes.append(Csv.fields(d, t, ""), Csv.crlf.put("")), pa(Csv.field.at(d, rb(d, f, t), f, ""), pos)),
              Equal.cong(Bytes(), Nat, x => pa(x, pos), Csv.record(d, Con{f, t}, ""),
                Bytes.append(Csv.field.at(d, rb(d, f, t), f, ""), Bytes.append(Csv.fields(d, t, ""),
                  Csv.crlf.put(""))), REC.bytes(d, f, t)),
              pa_app(Csv.field.at(d, rb(d, f, t), f, ""), Bytes.append(Csv.fields(d, t, ""), Csv.crlf.put("")),
                pos)))))))

# LEMMA: a record, as the writer wrote it, from a record's start: kept,
# field for field, and the reader at the next record's start
def REC(+d: Csv.Dialect, r: List<&2, Bytes()>, +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>,
  +pos: Nat, +hd: {Csv.cls(d, Csv.delim(d)) == Csv.KD{} : Csv.K},
  +hcr: {Csv.cls(d, 13) == Csv.KCR{} : Csv.K}, +hlf: {Csv.cls(d, 10) == Csv.KLF{} : Csv.K},
  +hc: {Csv.crlf(d) == True{} : Bool}) ->
  {Bool.not(List.is_empty(&2, Bytes(), r)) == True{} : Bool} ->
  {Nat.is_le(Csv.width(r), Csv.max_fields(d)) == True{} : Bool} ->
  {Csv.fits.fields(d, r) == True{} : Bool} ->
  RW(d, w, Nat.sub(Csv.max_fields(d), Csv.width(r))) ->
  {Csv.feed_buf.slow(d, Csv.record(d, r, ""), Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, out, w, pos}) ==
    Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, Con{r, out}, wnext(w, Nat.sub(Csv.max_fields(d), Csv.width(r))),
      pa(Csv.record(d, r, ""), pos)} : Csv.P}:
  match r:
    case Nil{}:
      hn => hl => hf => hw => no({Csv.feed_buf.slow(d, Csv.record(d, Nil{}, ""), Csv.P{Csv.RS{}, Csv.max_fields(d),
        Nil{}, out, w, pos}) == Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, Con{Nil{}, out},
        wnext(w, Nat.sub(Csv.max_fields(d), Csv.width(Nil{}))), pa(Csv.record(d, Nil{}, ""), pos)} : Csv.P}, hn)
    case Con{+f, +t}:
      hn => hl => +hf => hw => REC.con(d, f, t, out, w, pos, hd, hcr, hlf, hc, hl, hf, hw)

# Reading the document back
# -------------------------

# what the first record left, against the width every record is held
# to (n0, the first record's)
def WI(+d: Csv.Dialect, w: Maybe<&2, Nat>, +n0: Nat) -> Data:
  match w:
    case None{}:
      Unit
    case Some{x}:
      {Bool.or(Csv.ragged(d), Nat.is_eq(x, Nat.sub(Csv.max_fields(d), n0))) == True{} : Bool}

def rwi.b(rg: Bool, +a: Nat, +n0: Nat, +x: Nat, +mn: Nat) ->
  {Bool.or(rg, Nat.is_eq(a, n0)) == True{} : Bool} ->
  {Bool.or(rg, Nat.is_eq(x, Nat.sub(mn, n0))) == True{} : Bool} ->
  {Bool.or(rg, Nat.is_eq(Nat.sub(mn, a), x)) == True{} : Bool}:
  match rg:
    case True{}:
      h1 => h2 => {==}
    case False{}:
      h1 => h2 =>
        %Equal.sym(Nat, a, n0, nat_eq(a, n0)(h1)) : {Nat.is_eq(Nat.sub(mn, _), x) == True{} : Bool}
        %Equal.sym(Nat, x, Nat.sub(mn, n0), nat_eq(x, Nat.sub(mn, n0))(h2)) :
          {Nat.is_eq(Nat.sub(mn, n0), _) == True{} : Bool}
        nat_refl(Nat.sub(mn, n0))

def win.b(rg: Bool, +a: Nat, +n0: Nat, +mn: Nat) ->
  {Bool.or(rg, Nat.is_eq(a, n0)) == True{} : Bool} ->
  {Bool.or(rg, Nat.is_eq(Nat.sub(mn, a), Nat.sub(mn, n0))) == True{} : Bool}:
  match rg:
    case True{}:
      h1 => {==}
    case False{}:
      h1 =>
        %Equal.sym(Nat, a, n0, nat_eq(a, n0)(h1)) : {Nat.is_eq(Nat.sub(mn, _), Nat.sub(mn, n0)) == True{} : Bool}
        nat_refl(Nat.sub(mn, n0))

# the width check a record passes, and the one the next record meets
def RWI(+d: Csv.Dialect, w: Maybe<&2, Nat>, +n0: Nat, +a: Nat) ->
  {Bool.or(Csv.ragged(d), Nat.is_eq(a, n0)) == True{} : Bool} -> WI(d, w, n0) ->
  RW(d, w, Nat.sub(Csv.max_fields(d), a)):
  match w:
    case None{}:
      h1 => h2 => Unit{}
    case Some{+x}:
      h1 => h2 => rwi.b(Csv.ragged(d), a, n0, x, Csv.max_fields(d))(h1)(h2)

def WIN(+d: Csv.Dialect, w: Maybe<&2, Nat>, +n0: Nat, +a: Nat) ->
  {Bool.or(Csv.ragged(d), Nat.is_eq(a, n0)) == True{} : Bool} -> WI(d, w, n0) ->
  WI(d, wnext(w, Nat.sub(Csv.max_fields(d), a)), n0):
  match w:
    case None{}:
      h1 => h2 => win.b(Csv.ragged(d), a, n0, Csv.max_fields(d))(h1)
    case Some{x}:
      h1 => h2 => h2

def wend(+d: Csv.Dialect, rs: List<&2, List<&2, Bytes()>>, w: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match rs:
    case Nil{}:
      w
    case Con{r, t}:
      wend(d, t, wnext(w, Nat.sub(Csv.max_fields(d), Csv.width(r))))

# fits.rec, taken apart: (((has a field && within max_fields) && as wide)
# && its fields fit)
def FR(+d: Csv.Dialect, +n0: Nat, +r: List<&2, Bytes()>) -> Type:
  {Bool.not(List.is_empty(&2, Bytes(), r)) == True{} : Bool} &
    {Nat.is_le(Csv.width(r), Csv.max_fields(d)) == True{} : Bool} &
    {Bool.or(Csv.ragged(d), Nat.is_eq(Csv.width(r), n0)) == True{} : Bool} &
    {Csv.fits.fields(d, r) == True{} : Bool}

def fr(+d: Csv.Dialect, +n0: Nat, +r: List<&2, Bytes()>) -> {Csv.fits.rec(d, n0, r) == True{} : Bool} -> FR(d, n0, r):
  +h =>
    +h3 = and.l(Bool.and(Bool.and(Bool.not(List.is_empty(&2, Bytes(), r)), Nat.is_le(Csv.width(r), Csv.max_fields(d))),
      Bool.or(Csv.ragged(d), Nat.is_eq(Csv.width(r), n0))), Csv.fits.fields(d, r))(h)
    +h2 = and.l(Bool.and(Bool.not(List.is_empty(&2, Bytes(), r)), Nat.is_le(Csv.width(r), Csv.max_fields(d))),
      Bool.or(Csv.ragged(d), Nat.is_eq(Csv.width(r), n0)))(h3)
    (and.l(Bool.not(List.is_empty(&2, Bytes(), r)), Nat.is_le(Csv.width(r), Csv.max_fields(d)))(h2),
      (and.r(Bool.not(List.is_empty(&2, Bytes(), r)), Nat.is_le(Csv.width(r), Csv.max_fields(d)))(h2),
        (and.r(Bool.and(Bool.not(List.is_empty(&2, Bytes(), r)), Nat.is_le(Csv.width(r), Csv.max_fields(d))),
          Bool.or(Csv.ragged(d), Nat.is_eq(Csv.width(r), n0)))(h3),
          and.r(Bool.and(Bool.and(Bool.not(List.is_empty(&2, Bytes(), r)), Nat.is_le(Csv.width(r),
            Csv.max_fields(d))), Bool.or(Csv.ragged(d), Nat.is_eq(Csv.width(r), n0))), Csv.fits.fields(d, r))(h))))

def fr.wd(+d: Csv.Dialect, +n0: Nat, +r: List<&2, Bytes()>, x: FR(d, n0, r)) ->
  {Bool.or(Csv.ragged(d), Nat.is_eq(Csv.width(r), n0)) == True{} : Bool}:
  (a, x2) = x
  (b, x3) = x2
  (c, e) = x3
  c

def sa.crlf(+d: Csv.Dialect, x: SA(d)) -> {Csv.crlf(d) == True{} : Bool}:
  (a, b) = x
  a

def DOCP(+d: Csv.Dialect, +rs: List<&2, List<&2, Bytes()>>, +out: List<&2, List<&2, Bytes()>>,
  +w: Maybe<&2, Nat>, +pos: Nat) -> Csv.P:
  Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, List.reverse.go(&2, List<&2, Bytes()>, rs, out), wend(d, rs, w),
    pa(Csv.show.go(d, rs, ""), pos)}

def DOC.con(+d: Csv.Dialect, +r: List<&2, Bytes()>, +t: List<&2, List<&2, Bytes()>>, +n0: Nat,
  +out: List<&2, List<&2, Bytes()>>, +w: Maybe<&2, Nat>, +pos: Nat,
  +hd: {Csv.cls(d, Csv.delim(d)) == Csv.KD{} : Csv.K}, +hcr: {Csv.cls(d, 13) == Csv.KCR{} : Csv.K},
  +hlf: {Csv.cls(d, 10) == Csv.KLF{} : Csv.K}, +hc: {Csv.crlf(d) == True{} : Bool},
  fr0: FR(d, n0, r), hwi: WI(d, w, n0),
  ih: {Csv.feed_buf.slow(d, Csv.show.go(d, t, ""), Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, Con{r, out},
    wnext(w, Nat.sub(Csv.max_fields(d), Csv.width(r))), pa(Csv.record(d, r, ""), pos)}) ==
    DOCP(d, t, Con{r, out}, wnext(w, Nat.sub(Csv.max_fields(d), Csv.width(r))), pa(Csv.record(d, r, ""), pos)) :
    Csv.P}) ->
  {Csv.feed_buf.slow(d, Csv.show.go(d, Con{r, t}, ""), Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, out, w, pos}) ==
    DOCP(d, Con{r, t}, out, w, pos) : Csv.P}:
  (hn, fr1) = fr0
  (hl, fr2) = fr1
  (hwd, hf) = fr2
  tr3(Csv.P, Csv.feed_buf.slow(d, Csv.show.go(d, Con{r, t}, ""), Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, out, w, pos}),
    Csv.feed_buf.slow(d, Csv.show.go(d, t, ""), Csv.feed_buf.slow(d, Csv.record(d, r, ""),
      Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, out, w, pos})),
    Csv.feed_buf.slow(d, Csv.show.go(d, t, ""), Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, Con{r, out},
      wnext(w, Nat.sub(Csv.max_fields(d), Csv.width(r))), pa(Csv.record(d, r, ""), pos)}),
    DOCP(d, Con{r, t}, out, w, pos),
    Equal.trans(Csv.P,
      Csv.feed_buf.slow(d, Csv.show.go(d, Con{r, t}, ""), Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, out, w, pos}),
      Csv.feed_buf.slow(d, Bytes.append(Csv.record(d, r, ""), Csv.show.go(d, t, "")),
        Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, out, w, pos}),
      Csv.feed_buf.slow(d, Csv.show.go(d, t, ""), Csv.feed_buf.slow(d, Csv.record(d, r, ""),
        Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, out, w, pos})),
      Equal.cong(Bytes(), Csv.P, x => Csv.feed_buf.slow(d, x, Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, out, w, pos}),
        Csv.show.go(d, t, Csv.record(d, r, "")), Bytes.append(Csv.record(d, r, ""), Csv.show.go(d, t, "")),
        pfx.show(d, t, Csv.record(d, r, ""))),
      slow_app(d, Csv.record(d, r, ""), Csv.show.go(d, t, ""), Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, out, w, pos})),
    Equal.cong(Csv.P, Csv.P, x => Csv.feed_buf.slow(d, Csv.show.go(d, t, ""), x),
      Csv.feed_buf.slow(d, Csv.record(d, r, ""), Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, out, w, pos}),
      Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, Con{r, out}, wnext(w, Nat.sub(Csv.max_fields(d), Csv.width(r))),
        pa(Csv.record(d, r, ""), pos)},
      REC(d, r, out, w, pos, hd, hcr, hlf, hc)(hn)(hl)(hf)(RWI(d, w, n0, Csv.width(r))(hwd)(hwi))),
    Equal.trans(Csv.P,
      Csv.feed_buf.slow(d, Csv.show.go(d, t, ""), Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, Con{r, out},
        wnext(w, Nat.sub(Csv.max_fields(d), Csv.width(r))), pa(Csv.record(d, r, ""), pos)}),
      DOCP(d, t, Con{r, out}, wnext(w, Nat.sub(Csv.max_fields(d), Csv.width(r))), pa(Csv.record(d, r, ""), pos)),
      DOCP(d, Con{r, t}, out, w, pos),
      ih,
      Equal.cong(Nat, Csv.P, x => Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{},
        List.reverse.go(&2, List<&2, Bytes()>, t, Con{r, out}),
        wend(d, t, wnext(w, Nat.sub(Csv.max_fields(d), Csv.width(r)))), x},
        pa(Csv.show.go(d, t, ""), pa(Csv.record(d, r, ""), pos)), pa(Csv.show.go(d, Con{r, t}, ""), pos),
        Equal.sym(Nat, pa(Csv.show.go(d, Con{r, t}, ""), pos), pa(Csv.show.go(d, t, ""), pa(Csv.record(d, r, ""), pos)),
          Equal.trans(Nat, pa(Csv.show.go(d, t, Csv.record(d, r, "")), pos),
            pa(Bytes.append(Csv.record(d, r, ""), Csv.show.go(d, t, "")), pos),
            pa(Csv.show.go(d, t, ""), pa(Csv.record(d, r, ""), pos)),
            Equal.cong(Bytes(), Nat, x => pa(x, pos), Csv.show.go(d, t, Csv.record(d, r, "")),
              Bytes.append(Csv.record(d, r, ""), Csv.show.go(d, t, "")), pfx.show(d, t, Csv.record(d, r, ""))),
            pa_app(Csv.record(d, r, ""), Csv.show.go(d, t, ""), pos))))))

# LEMMA: every record, as the writer wrote it: kept in order
def DOC(+d: Csv.Dialect, rs: List<&2, List<&2, Bytes()>>, +n0: Nat, +out: List<&2, List<&2, Bytes()>>,
  +w: Maybe<&2, Nat>, +pos: Nat, +hd: {Csv.cls(d, Csv.delim(d)) == Csv.KD{} : Csv.K},
  +hcr: {Csv.cls(d, 13) == Csv.KCR{} : Csv.K}, +hlf: {Csv.cls(d, 10) == Csv.KLF{} : Csv.K},
  +hc: {Csv.crlf(d) == True{} : Bool}) ->
  {Csv.fits.recs(d, n0, rs) == True{} : Bool} -> WI(d, w, n0) ->
  {Csv.feed_buf.slow(d, Csv.show.go(d, rs, ""), Csv.P{Csv.RS{}, Csv.max_fields(d), Nil{}, out, w, pos}) ==
    DOCP(d, rs, out, w, pos) : Csv.P}:
  match rs:
    case Nil{}:
      hr => hwi => {==}
    case Con{+r, +t}:
      +hr => +hwi =>
        DOC.con(d, r, t, n0, out, w, pos, hd, hcr, hlf, hc,
          fr(d, n0, r)(and.l(Csv.fits.rec(d, n0, r), Csv.fits.recs(d, n0, t))(hr)), hwi,
          DOC(d, t, n0, Con{r, out}, wnext(w, Nat.sub(Csv.max_fields(d), Csv.width(r))), pa(Csv.record(d, r, ""), pos),
            hd, hcr, hlf, hc)(and.r(Csv.fits.rec(d, n0, r), Csv.fits.recs(d, n0, t))(hr))(
            WIN(d, w, n0, Csv.width(r))(fr.wd(d, n0, r,
              fr(d, n0, r)(and.l(Csv.fits.rec(d, n0, r), Csv.fits.recs(d, n0, t))(hr))))(hwi)))

# reversing twice
def rr(xs: List<&2, List<&2, Bytes()>>, -acc: List<&2, List<&2, Bytes()>>) ->
  {List.reverse.go(&2, List<&2, Bytes()>, List.reverse.go(&2, List<&2, Bytes()>, xs, acc), Nil{}) ==
    List.reverse.go(&2, List<&2, Bytes()>, acc, xs) : List<&2, List<&2, Bytes()>>}:
  match xs:
    case Nil{}:
      {==}
    case Con{h, t}:
      rr(t, Con{h, acc})

# The laws, whole
# ---------------

def RT.con(+d: Csv.Dialect, +r: List<&2, Bytes()>, +t: List<&2, List<&2, Bytes()>>) ->
  {Csv.fits(d, Con{r, t}) == True{} : Bool} ->
  {Csv.read(d, Csv.show(d, Con{r, t})) == Csv.table(d, Con{r, t}) : Csv.Out}:
  +ok =>
    Equal.trans(Csv.Out, Csv.read(d, Csv.show(d, Con{r, t})),
      Csv.result(d, Csv.finish(d, Csv.feed_buf.slow(d, Csv.show.go(d, Con{r, t}, ""), Csv.new(d)))),
      Csv.table(d, Con{r, t}),
      Equal.cong(Csv.P, Csv.Out, p => Csv.result(d, Csv.finish(d, p)),
        Csv.feed_buf(d, Csv.show.go(d, Con{r, t}, ""), Csv.new(d)),
        Csv.feed_buf.slow(d, Csv.show.go(d, Con{r, t}, ""), Csv.new(d)),
        lem.go(d, Bytes.len(Csv.show.go(d, Con{r, t}, "")), (Csv.new(d), Csv.show.go(d, Con{r, t}, "")))),
      Equal.trans(Csv.Out,
        Csv.result(d, Csv.finish(d, Csv.feed_buf.slow(d, Csv.show.go(d, Con{r, t}, ""), Csv.new(d)))),
        Csv.result(d, Csv.finish(d, DOCP(d, Con{r, t}, Nil{}, None{}, 0n))),
        Csv.table(d, Con{r, t}),
        Equal.cong(Csv.P, Csv.Out, p => Csv.result(d, Csv.finish(d, p)),
          Csv.feed_buf.slow(d, Csv.show.go(d, Con{r, t}, ""), Csv.new(d)),
          DOCP(d, Con{r, t}, Nil{}, None{}, 0n),
          DOC(d, Con{r, t}, Csv.width(r), Nil{}, None{}, 0n, cls.d(d, sane.sa(d)(and.l(Csv.sane(d), Csv.fits.at(d, Con{r, t}))(ok))), cls.cr(d, sane.sa(d)(and.l(Csv.sane(d), Csv.fits.at(d, Con{r, t}))(ok))),
            cls.lf(d, sane.sa(d)(and.l(Csv.sane(d), Csv.fits.at(d, Con{r, t}))(ok))), sa.crlf(d, sane.sa(d)(and.l(Csv.sane(d), Csv.fits.at(d, Con{r, t}))(ok))))(
            and.r(Csv.sane(d), Csv.fits.at(d, Con{r, t}))(ok))(Unit{})),
        Equal.cong(List<&2, List<&2, Bytes()>>, Csv.Out, xs => Csv.table(d, xs),
          List.reverse(&2, List<&2, Bytes()>, List.reverse.go(&2, List<&2, Bytes()>, Con{r, t}, Nil{})),
          Con{r, t}, rr(Con{r, t}, Nil{}))))

def Laws.round_trip(d, rs, ok):
  match rs:
    case Nil{}:
      {==}
    case Con{r, t}:
      RT.con(d, r, t)(ok)

def Laws.show_valid(d, rs, ok):
  Equal.trans(Csv.Out, Spec.parse(Bytes.to_list(Csv.show(d, rs)), d), Csv.read(d, Csv.show(d, rs)),
    Csv.table(d, rs),
    Equal.sym(Csv.Out, Csv.read(d, Csv.show(d, rs)), Spec.parse(Bytes.to_list(Csv.show(d, rs)), d),
      Laws.csv_sim_buf(d, Csv.show(d, rs))),
    Laws.round_trip(d, rs, ok))
