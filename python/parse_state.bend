# State/result monad for direct recursive parsing; residual fuel is global.
import Base
import ./syntax.bend as S

type State is Data:
  State{tokens: List<&2, S.Tok>, last: S.Pos, fuel: Nat}

type Reply<-A: Data> is Data:
  Reply{value: A, state: State}

def M(-A: Data) -> Type:
  State -> Result<&2, &2, S.Error, Reply<A>>

def M.pure(-A: Data, x: A) -> M(A):
  s => Done{Reply{x, s}}

def bind_reply(-A: Data, -B: Data, f: A -> M(B), r: Reply<A>) -> Result<&2, &2, S.Error, Reply<B>>:
  Reply{x, s} = r
  f(x, s)

def M.bind(-A: Data, -B: Data, m: M(A), f: A -> M(B)) -> M(B):
  s => Result.bind(&2, &2, S.Error, Reply<A>, Reply<B>, m(s), bind_reply(A, B, f))

def first(ts: List<&2, S.Tok>) -> S.Tok:
  match ts:
    case Nil{}:
      S.Tok{"ENDMARKER", "", S.Pos{1n, 0n}, S.Pos{1n, 0n}}
    case Con{h, t}:
      h

def tok_text(t: S.Tok) -> String:
  S.Tok{k, raw, lo, hi} = t
  raw

def tok_kind(t: S.Tok) -> String:
  S.Tok{k, raw, lo, hi} = t
  k

def tok_start(t: S.Tok) -> S.Pos:
  S.Tok{k, raw, lo, hi} = t
  lo

def tok_end(t: S.Tok) -> S.Pos:
  S.Tok{k, raw, lo, hi} = t
  hi

def is_text(+t: S.Tok, raw: String) -> Bool:
  String.eq(tok_text(t), raw)

def is_kind(t: S.Tok, k: String) -> Bool:
  String.eq(tok_kind(t), k)

def peek(s: State) -> Result<&2, &2, S.Error, Reply<S.Tok>>:
  State{+ts, last, fuel} = s
  Done{Reply{first(ts), State{ts, last, fuel}}}

def tokens(s: State) -> Result<&2, &2, S.Error, Reply<List<&2, S.Tok>>>:
  State{+ts, last, fuel} = s
  Done{Reply{ts, State{ts, last, fuel}}}

def second(s: State) -> Result<&2, &2, S.Error, Reply<S.Tok>>:
  State{+ts, last, fuel} = s
  Done{Reply{first(List.tail(&2, S.Tok, ts)), State{ts, last, fuel}}}

def take_tokens(ts: List<&2, S.Tok>, fuel: Nat) -> Result<&2, &2, S.Error, Reply<S.Tok>>:
  match ts:
    case Nil{}:
      Fail{S.PErr{S.Syntax{}, S.Pos{1n, 0n}, "unexpected EOF"}}
    case Con{+t, rest}:
      Done{Reply{t, State{rest, tok_end(t), fuel}}}

def take(s: State) -> Result<&2, &2, S.Error, Reply<S.Tok>>:
  State{ts, last, fuel} = s
  take_tokens(ts, fuel)

def end(s: State) -> Result<&2, &2, S.Error, Reply<S.Pos>>:
  State{ts, +last, fuel} = s
  Done{Reply{last, State{ts, last, fuel}}}

def error(-A: Data, k: S.ErrorKind, msg: String, s: State) -> Result<&2, &2, S.Error, Reply<A>>:
  State{ts, last, fuel} = s
  Fail{S.PErr{k, tok_start(first(ts)), msg}}

def syntax(-A: Data, msg: String) -> M(A):
  error(A, S.Syntax{}, msg)

def unsupported(-A: Data, msg: String) -> M(A):
  error(A, S.Unsupported{}, msg)

def expect_token(+tok: S.Tok, +word: String) -> M(S.Tok):
  S.choose(M(S.Tok), is_text(tok, word) || is_kind(tok, word), u => take, u => syntax(S.Tok, "expected " ++ word))

def expect(word: String) -> M(S.Tok):
  do M<S.Tok>:
    t : S.Tok <- peek
    expect_token(t, word)

def meter_go(-A: Data, act: M(A), s: State) -> Result<&2, &2, S.Error, Reply<A>>:
  match s:
    case State{ts, last, 0n}:
      Fail{S.PErr{S.Limit{}, tok_start(first(ts)), "parser fuel"}}
    case State{ts, last, 1n+left}:
      act(State{ts, last, left})

def meter(-A: Data, act: M(A)) -> M(A):
  meter_go(A, act)

def lift(-A: Data, r: Result<&2, &2, S.Error, A>, s: State) -> Result<&2, &2, S.Error, Reply<A>>:
  match r:
    case Done{x}:
      Done{Reply{x, s}}
    case Fail{e}:
      Fail{e}

# One-statement backtracking (parenthesized `with` items): the saved state also
# restores fuel, so a failed first alternative costs nothing on the second.
def or_else(-A: Data, r: Result<&2, &2, S.Error, Reply<A>>, other: M(A), s: State) -> Result<&2, &2, S.Error, Reply<A>>:
  match r:
    case Done{x}:
      Done{x}
    case Fail{e}:
      other(s)

def either_go(-A: Data, first: M(A), other: M(A), s: State) -> Result<&2, &2, S.Error, Reply<A>>:
  State{+ts, +last, +fuel} = s
  or_else(A, first(State{ts, last, fuel}), other, State{ts, last, fuel})

def either(-A: Data, first: M(A), other: M(A)) -> M(A):
  either_go(A, first, other)

# The `match` header: a Syntax failure of `act` yields `other` on the saved state (fuel too); Unsupported and Limit stand.
def recover(-A: Data, r: Result<&2, &2, S.Error, Reply<A>>, other: A, s: State) -> Result<&2, &2, S.Error, Reply<A>>:
  match r:
    case Done{x}:
      Done{x}
    case Fail{S.PErr{S.Syntax{}, pos, msg}}:
      Done{Reply{other, s}}
    case Fail{e}:
      Fail{e}

def attempt_go(-A: Data, act: M(A), other: A, s: State) -> Result<&2, &2, S.Error, Reply<A>>:
  State{+ts, +last, +fuel} = s
  recover(A, act(State{ts, last, fuel}), other, State{ts, last, fuel})

def attempt(-A: Data, act: M(A), other: A) -> M(A):
  attempt_go(A, act, other)

# An f-string field: `act` parses the field's own tokens on its own budget,
# then the outer tokens, end and fuel resume untouched.
def resume(-A: Data, ts: List<&2, S.Tok>, last: S.Pos, fuel: Nat, r: Result<&2, &2, S.Error, Reply<A>>) -> Result<&2, &2, S.Error, Reply<A>>:
  match r:
    case Done{Reply{x, inner}}:
      Done{Reply{x, State{ts, last, fuel}}}
    case Fail{e}:
      Fail{e}

def within_go(-A: Data, sub: List<&2, S.Tok>, budget: Nat, act: M(A), s: State) -> Result<&2, &2, S.Error, Reply<A>>:
  State{ts, +last, fuel} = s
  resume(A, ts, last, fuel, act(State{sub, last, budget}))

def within(-A: Data, sub: List<&2, S.Tok>, budget: Nat, act: M(A)) -> M(A):
  within_go(A, sub, budget, act)
