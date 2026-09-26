# Decode: one step of constrained decoding that returns its own proof. A step
# takes a grammar state, a vocabulary and one weight per token, keeps the K
# heaviest tokens the grammar allows, draws one of them in proportion to its
# weight, and advances the state. It returns the token, the new state, and a
# certificate that `check` below can verify without trusting the decoder.
#
#   grammar.bend  the state, its mask, and the law allows(s, c) == live(step(s, c))
#   topk.bend     the exact K heaviest, with ties broken by id
#   rng.bend      the draw, a pure function of (seed, stream, pos)
#
# The certificate is the kept list (best first) plus the draw, and the check is
# two opposed tests, the shape of topk in proof.bend:
#
#   chosen    every kept entry is a real token, holds the weight its logit
#             holds, is reached by the grammar, and the list is strictly best
#             first with at most K entries. Alone, this accepts a list that
#             skips the best token: every entry it names is genuine.
#   frontier  the number of legal tokens at or above the last kept entry (all
#             of them, when fewer than K are kept) equals the kept count.
#             Alone, this accepts a fabricated entry that took the place of a
#             real one, because the count still comes out right.
#
# Together they pin the kept list to the exact top K. The draw and the state
# are then recomputed, because both are pure functions of what was pinned.
#
# The grammar's law is exercised twice. The decoder asks the mask (allows) and
# the checker asks the step (live after step), which are separate code paths.
# The frontier pass also runs both on every token and rejects with Split if they
# disagree anywhere.
#
# Weights are integers, not floats, so every lane computes the same answer and
# the checker compares exactly.
import Base
import ./grammar.bend as Gr
import ./heap.bend as Heap
import ./topk.bend as TopK
import ./rng.bend as Rng

# -- tokens ------------------------------------------------------------------

# A token is up to four bytes packed low byte first, and a zero byte is padding.
# That is safe because NUL is never legal JSON. The vocabulary is a list, and a
# token's id is its index in it.
def byte(t: U32, n: Nat) -> U32:
  U32.and(U32.shrn(t, n), 255)

# ponytail: five or more bytes shift past bit 31; widen to U32 pairs if a vocab needs it
def pack.go(s: String, +sh: Nat, t: U32) -> U32:
  match s:
    case SNil{}:
      t
    case SCon{c, r}:
      pack.go(r, Nat.add(sh, 8n), U32.or(t, U32.shln(Char.to_u32(c), sh)))

def pack(s: String) -> U32:
  pack.go(s, 0n, 0)

def text.if(b: U32, r: String, pad: Bool) -> String:
  match pad:
    case True{}:
      r
    case False{}:
      SCon{Chr{b}, r}

def text.c(+b: U32, r: String) -> String:
  text.if(b, r, U32.is_eq(b, 0))

def text(+t: U32) -> String:
  text.c(byte(t, 0n), text.c(byte(t, 8n), text.c(byte(t, 16n), text.c(byte(t, 24n), ""))))

# -- a token through the grammar ---------------------------------------------

# Each byte is run down both paths at once. ok is the mask path: every byte was
# allowed from the state before it. s is the step path. The byte law lifts to
# tokens, ok == live(s), because a dead state stays dead: the last state is
# live exactly when every state before it was.
type W is Data:
  W{ok: Bool, s: Gr.St}

def walk.if(ok: Bool, +s: Gr.St, +b: U32, pad: Bool) -> W:
  match pad:
    case True{}:
      W{ok, s}
    case False{}:
      W{Bool.and(ok, Gr.allows(s, b)), Gr.step(s, b)}

def walk.b(w: W, +b: U32) -> W:
  match w:
    case W{ok, s}:
      walk.if(ok, s, b, U32.is_eq(b, 0))

def walk(+s: Gr.St, +t: U32) -> W:
  walk.b(walk.b(walk.b(walk.b(W{Gr.live(s), s}, byte(t, 0n)), byte(t, 8n)), byte(t, 16n)), byte(t, 24n))

def ok.of(w: W) -> Bool:
  match w:
    case W{ok, s}:
      ok

def st.of(w: W) -> Gr.St:
  match w:
    case W{ok, s}:
      s

# grammar.bend has no Node equality, so the node is compared by its printed name
def st.eq(a: Gr.St, b: Gr.St) -> Bool:
  match a:
    case Gr.St{n, d, k0, k1, kf}:
      match b:
        case Gr.St{m, e, j0, j1, jf}:
          Bool.and(Bool.and(String.eq(Gr.show.n(n), Gr.show.n(m)), U32.is_eq(d, e)),
            Bool.and(Bool.and(U32.is_eq(k0, j0), U32.is_eq(k1, j1)), U32.is_eq(kf, jf)))

# element i, or None. It walks the whole list with no early exit, which costs
# O(V) per lookup, and it never builds a unary Nat from an index it was handed.
# ponytail: O(V) per lookup; index an Array when a vocab is large
def nth.if(x: U32, m: Maybe<&2, U32>, hit: Bool) -> Maybe<&2, U32>:
  match hit:
    case True{}:
      Some{x}
    case False{}:
      m

def nth.go(xs: List<&2, U32>, +i: U32, +j: U32, m: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match xs:
    case Nil{}:
      m
    case Con{x, rest}:
      nth.go(rest, i, U32.inc(j), nth.if(x, m, U32.is_eq(i, j)))

def nth(xs: List<&2, U32>, i: U32) -> Maybe<&2, U32>:
  nth.go(xs, i, 0, None{})

def same(xs: List<&2, U32>, ys: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}:
      List.is_empty(&2, U32, ys)
    case Con{x, xr}:
      match ys:
        case Nil{}:
          False{}
        case Con{y, yr}:
          same(xr, yr)

# -- the step ----------------------------------------------------------------

# where a draw lives: the seed, the rollout, the position in it
type At is Data:
  At{seed: U32, stream: U32, pos: U32}

# the kept entries, best first, as (weight, id), and the draw in 0..total-1
type Cert is Data:
  Cert{kept: List<&2, Heap.Entry>, draw: U32}

type Step is Data:
  Step{tok: U32, st: Gr.St, cert: Cert}

# Why a step is not a step. The first three are the decoder's refusals: it
# returns them as values rather than quietly emitting some other token. All but
# Empty are also the checker's rejections.
type Bad is Data:
  Shape{}                     # the vocabulary and the logits differ in length
  Empty{}                     # no token with weight is legal here
  Heavy{}                     # the kept weights overflow a U32
  Split{}                     # the mask and the step disagree on a token
  Range{}                     # a kept id is not a token
  Value{}                     # a kept weight is not the logit its id holds
  Illegal{}                   # a kept token is unweighted or kills the state
  Order{}                     # the kept list is not strictly best first
  Over{}                      # more than K kept
  Slack{}                     # a legal token outranks the last kept one and was skipped
  Draw{}                      # the draw or its pick is not the seed's
  State{}                     # the new state is not the chosen token's step

type Vd is Data:
  Ok{}
  No{b: Bad}

def want(b: Bad, ok: Bool) -> Vd:
  match ok:
    case True{}:
      Ok{}
    case False{}:
      No{b}

# the first failure wins, as in proof.bend
def keep(a: Vd, b: Vd) -> Vd:
  match a:
    case Ok{}:
      b
    case No{x}:
      No{x}

def offer.if(t: TopK.TopK, w: U32, id: U32, ok: Bool) -> TopK.TopK:
  match ok:
    case True{}:
      TopK.offer(t, w, id)
    case False{}:
      t

# every legal token with a nonzero weight goes to the TopK. The order is
# (weight, id), so of two equal weights the larger id ranks higher. The
# decoder reads legality off the mask.
def front(vs: List<&2, U32>, ls: List<&2, U32>, +s: Gr.St, +id: U32, t: TopK.TopK) -> TopK.TopK:
  match vs:
    case Nil{}:
      t
    case Con{v, vr}:
      match ls:
        case Nil{}:
          t
        case Con{+w, lr}:
          front(vr, lr, s, U32.inc(id), offer.if(t, w, id, Bool.and(ok.of(walk(s, v)), U32.is_lt(0, w))))

type Ms is Data:
  Ms{sum: U32, whole: Bool}

def mass.add(+s: U32, +w: U32, whole: Bool) -> Ms:
  Ms{U32.add(s, w), Bool.and(whole, U32.is_le(w, U32.sub(4294967295, s)))}

def mass.one(m: Ms, w: U32) -> Ms:
  match m:
    case Ms{s, whole}:
      mass.add(s, w, whole)

def mass(xs: List<&2, Heap.Entry>, m: Ms) -> Ms:
  match xs:
    case Nil{}:
      m
    case Con{Heap.Entry{w, id}, rest}:
      mass(rest, mass.one(m, w))

# the pick: the first entry, best first, whose running weight passes r
type Pk is Data:
  Pk{r: U32, id: U32, got: Bool}

def pick.hit(+r: U32, +w: U32, v: U32, hit: Bool) -> Pk:
  match hit:
    case True{}:
      Pk{r, v, True{}}
    case False{}:
      Pk{U32.sub(r, w), 0, False{}}

def pick.one(p: Pk, +w: U32, v: U32) -> Pk:
  match p:
    case Pk{+r, id, got}:
      match got:
        case True{}:
          Pk{r, id, True{}}
        case False{}:
          pick.hit(r, w, v, U32.is_lt(r, w))

def pick(xs: List<&2, Heap.Entry>, p: Pk) -> Pk:
  match xs:
    case Nil{}:
      p
    case Con{Heap.Entry{w, v}, rest}:
      pick(rest, pick.one(p, w, v))

# ponytail: Rng.below's modulo bias (total / 2^32); fine while total << 2^32
def below(at: At, n: U32) -> U32:
  match at:
    case At{seed, stream, pos}:
      Rng.below(seed, stream, pos, n)

def step.tok(s: Gr.St, kept: List<&2, Heap.Entry>, r: U32, id: U32, m: Maybe<&2, U32>) -> Result<&2, &2, Bad, Step>:
  match m:
    case None{}:
      Fail{Shape{}}
    case Some{t}:
      Done{Step{id, st.of(walk(s, t)), Cert{kept, r}}}

def step.pk(vocab: List<&2, U32>, s: Gr.St, kept: List<&2, Heap.Entry>, r: U32, p: Pk) -> Result<&2, &2, Bad, Step>:
  match p:
    case Pk{x, +id, got}:
      step.tok(s, kept, r, id, nth(vocab, id))

def step.r(vocab: List<&2, U32>, s: Gr.St, +kept: List<&2, Heap.Entry>, +r: U32) -> Result<&2, &2, Bad, Step>:
  step.pk(vocab, s, kept, r, pick(kept, Pk{r, 0, False{}}))

def step.mass(vocab: List<&2, U32>, s: Gr.St, at: At, kept: List<&2, Heap.Entry>, m: Ms) -> Result<&2, &2, Bad, Step>:
  match m:
    case Ms{sum, whole}:
      match whole:
        case False{}:
          Fail{Heavy{}}
        case True{}:
          step.r(vocab, s, kept, below(at, sum))

def step.empty(vocab: List<&2, U32>, s: Gr.St, at: At, +kept: List<&2, Heap.Entry>, none: Bool) -> Result<&2, &2, Bad, Step>:
  match none:
    case True{}:
      Fail{Empty{}}
    case False{}:
      step.mass(vocab, s, at, kept, mass(kept, Ms{0, True{}}))

def step.some(vocab: List<&2, U32>, s: Gr.St, at: At, +kept: List<&2, Heap.Entry>) -> Result<&2, &2, Bad, Step>:
  step.empty(vocab, s, at, kept, List.is_empty(&2, Heap.Entry, kept))

def step.kept(vocab: List<&2, U32>, s: Gr.St, at: At, r: TopK.TopK & List<&2, Heap.Entry>) -> Result<&2, &2, Bad, Step>:
  (t, kept) = r
  step.some(vocab, s, at, kept)

def step.shape(+vocab: List<&2, U32>, +s: Gr.St, logits: List<&2, U32>, k: U32, at: At, ok: Bool) -> Result<&2, &2, Bad, Step>:
  match ok:
    case False{}:
      Fail{Shape{}}
    case True{}:
      step.kept(vocab, s, at, TopK.drain(front(vocab, logits, s, 0, TopK.new(k))))

# one step: logits[i] is token i's weight, k is the width, at is the draw
def decode_step(+vocab: List<&2, U32>, s: Gr.St, +logits: List<&2, U32>, k: U32, at: At) -> Result<&2, &2, Bad, Step>:
  step.shape(vocab, s, logits, k, at, same(vocab, logits))

# -- the check ---------------------------------------------------------------

# The chosen half runs over the kept list, capped at K+1 entries. The witness
# names no sizes, so the cap is the whole budget, and the list's length only
# matters as far as the one entry past K that proves Over. Legality here is read
# off the step path, the opposite of the decoder's.
type Ch is Data:
  Ch{v: Vd, n: U32, last: Maybe<&2, Heap.Entry>}

def ch.val(+w: U32, m: Maybe<&2, U32>) -> Vd:
  match m:
    case None{}:
      No{Range{}}
    case Some{x}:
      want(Value{}, U32.is_eq(x, w))

def ch.legal(+s: Gr.St, +w: U32, m: Maybe<&2, U32>) -> Vd:
  match m:
    case None{}:
      No{Range{}}
    case Some{t}:
      want(Illegal{}, Bool.and(Gr.live(st.of(walk(s, t))), U32.is_lt(0, w)))

def ch.ord(+w: U32, +id: U32, p: Maybe<&2, Heap.Entry>) -> Vd:
  match p:
    case None{}:
      Ok{}
    case Some{Heap.Entry{pw, pid}}:
      want(Order{}, Heap.less(w, id, pw, pid))

def ch.one(c: Ch, vs: List<&2, U32>, ls: List<&2, U32>, +s: Gr.St, +w: U32, +id: U32) -> Ch:
  match c:
    case Ch{v, n, p}:
      Ch{keep(keep(keep(v, ch.val(w, nth(ls, id))), ch.legal(s, w, nth(vs, id))), ch.ord(w, id, p)),
        U32.inc(n), Some{Heap.Entry{w, id}}}

def ch.go(f: Nat, xs: List<&2, Heap.Entry>, +vs: List<&2, U32>, +ls: List<&2, U32>, +s: Gr.St, c: Ch) -> Ch:
  match f:
    case 0n:
      c
    case 1n++p:
      match xs:
        case Nil{}:
          c
        case Con{Heap.Entry{w, id}, rest}:
          ch.go(p, rest, vs, ls, s, ch.one(c, vs, ls, s, w, id))

# The frontier half runs over every token. It counts the legal weighted ones at
# or above the floor, and it holds the mask path against the step path on each.
type Fr is Data:
  Fr{v: Vd, n: U32}

def floor.ok(+w: U32, id: U32, fl: Maybe<&2, Heap.Entry>) -> Bool:
  match fl:
    case None{}:
      True{}
    case Some{Heap.Entry{fw, fid}}:
      Bool.not(Heap.less(w, id, fw, fid))

def fr.cnt(v: Vd, n: U32, hit: Bool) -> Fr:
  match hit:
    case True{}:
      Fr{v, U32.inc(n)}
    case False{}:
      Fr{v, n}

def fr.tok(f: Fr, +x: W, +w: U32, id: U32, fl: Maybe<&2, Heap.Entry>) -> Fr:
  match f:
    case Fr{v, n}:
      fr.cnt(keep(v, want(Split{}, Bool.not(Bool.xor(ok.of(x), Gr.live(st.of(x)))))), n,
        Bool.and(Bool.and(ok.of(x), U32.is_lt(0, w)), floor.ok(w, id, fl)))

def fr.go(vs: List<&2, U32>, ls: List<&2, U32>, +s: Gr.St, +id: U32, +fl: Maybe<&2, Heap.Entry>, f: Fr) -> Fr:
  match vs:
    case Nil{}:
      f
    case Con{t, vr}:
      match ls:
        case Nil{}:
          f
        case Con{w, lr}:
          fr.go(vr, lr, s, U32.inc(id), fl, fr.tok(f, walk(s, t), w, id, fl))

# a full list (K kept) floors the count at its last entry; a short one must
# hold every legal token, so the count has no floor
def floor.of(last: Maybe<&2, Heap.Entry>, full: Bool) -> Maybe<&2, Heap.Entry>:
  match full:
    case True{}:
      last
    case False{}:
      None{}

def picked(p: Pk, +tok: U32) -> Bool:
  match p:
    case Pk{r, id, got}:
      Bool.and(got, U32.is_eq(id, tok))

def check.draw(+kept: List<&2, Heap.Entry>, +r: U32, tok: U32, at: At, m: Ms) -> Vd:
  match m:
    case Ms{sum, whole}:
      keep(want(Heavy{}, whole),
        want(Draw{}, Bool.and(U32.is_eq(r, below(at, sum)), picked(pick(kept, Pk{r, 0, False{}}), tok))))

def check.st(+s: Gr.St, next: Gr.St, m: Maybe<&2, U32>) -> Vd:
  match m:
    case None{}:
      No{State{}}
    case Some{t}:
      want(State{}, st.eq(next, st.of(walk(s, t))))

def check.fr(vocab: List<&2, U32>, +s: Gr.St, +k: U32, at: At, +tok: U32, next: Gr.St, +kept: List<&2, Heap.Entry>, draw: U32, cv: Vd, +n: U32, f: Fr) -> Vd:
  match f:
    case Fr{fv, fn}:
      keep(keep(keep(keep(keep(fv, cv), want(Over{}, U32.is_le(n, k))), want(Slack{}, U32.is_eq(fn, n))),
        check.draw(kept, draw, tok, at, mass(kept, Ms{0, True{}}))), check.st(s, next, nth(vocab, tok)))

def check.ch(+vocab: List<&2, U32>, +s: Gr.St, logits: List<&2, U32>, +k: U32, at: At, tok: U32, next: Gr.St, kept: List<&2, Heap.Entry>, draw: U32, c: Ch) -> Vd:
  match c:
    case Ch{v, +n, last}:
      check.fr(vocab, s, k, at, tok, next, kept, draw, v, n,
        fr.go(vocab, logits, s, 0, floor.of(last, U32.is_eq(n, k)), Fr{Ok{}, 0}))

# check a step against the inputs that made it: Ok, or the first property that broke
def check(+vocab: List<&2, U32>, +s: Gr.St, +logits: List<&2, U32>, +k: U32, at: At, step: Step) -> Vd:
  match step:
    case Step{tok, next, cert}:
      match cert:
        case Cert{+kept, draw}:
          keep(want(Shape{}, same(vocab, logits)),
            check.ch(vocab, s, logits, k, at, tok, next, kept, draw,
              ch.go(Nat.add(U32.to_nat(k), 1n), kept, vocab, logits, s, Ch{Ok{}, 0, None{}})))

# -- showing -----------------------------------------------------------------

def show(b: Bad) -> String:
  match b:
    case Shape{}:
      "shape"
    case Empty{}:
      "empty"
    case Heavy{}:
      "heavy"
    case Split{}:
      "split"
    case Range{}:
      "range"
    case Value{}:
      "value"
    case Illegal{}:
      "illegal"
    case Order{}:
      "order"
    case Over{}:
      "over"
    case Slack{}:
      "slack"
    case Draw{}:
      "draw"
    case State{}:
      "state"

def show.vd(v: Vd) -> String:
  match v:
    case Ok{}:
      "ok"
    case No{b}:
      show(b)

def show.kept.go(xs: List<&2, Heap.Entry>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{Heap.Entry{w, id}, rest}:
      Con{U32.show(w) ++ "@" ++ U32.show(id), show.kept.go(rest)}

# "w@id w@id ...", best first
def show.kept(xs: List<&2, Heap.Entry>) -> String:
  String.join(show.kept.go(xs), " ")
