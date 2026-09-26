# bend-wire: the reader kit.
#
# A protocol reader, as the HTTP engine found it and RESP and CSV
# confirmed: one structural walk over whatever bytes arrive, the whole
# state in one value, one byte-step function, never stopping. Written
# here once, over the protocol as template parameters, with the laws
# every such reader has proven once for all of them:
#
#   ~E: Data               what a step reads beside the state (CSV's
#                          dialect; Unit for a protocol with none)
#   ~S: Data               the reader's state
#   ~step: E -> S -> U32 -> S
#                          one byte
#   ~adv: E -> Bytes() -> S -> S & Bytes()
#                          one move of the block walk: a run of bytes the
#                          protocol takes whole (a field, a body), or one
#                          byte. one.step is the move that takes one byte.
#
# What a protocol proves about its own code, and hands in as a template
# argument, is one obligation per law that needs it:
#
#   adv_ok   a move lands where stepping its bytes one at a time lands:
#            feed_buf.last(e, adv(e, s, p)) == feed_buf.slow(e, s, p)
#            (one.step discharges it with one.step_ok)
#   absorbs  a refused state is a fixed point of the step:
#            step(e, bad(x), c) == bad(x)
#
# and what it gets for them is below: chunking never changes a read
# (feed_split, feed_buf_split, slow_split, reads_split), a refusal is
# never left (bad_feeds, bad_feeds_buf, bad_feeds_slow), the block walk
# is the byte machine (feed_buf_is_feed), and however a stream is cut
# into reads the reader reads it as the stream whole (reads_is).
import Base

# Bytes
# =====
#
# The byte helpers every reader wants, on the list of bytes the laws
# speak of: an ASCII literal, joining, reversing, comparing.

def bytes(s: String) -> List<&2, U32>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{Chr{c}, t}:
      Con{c, bytes(t)}

# A field line as a reader framed it: its name, lowercased, and its
# value as it came between the colon and the line's end (the whitespace
# at either end is still on it: RFC 9110 5.5 says it is no part of the
# value, and a reader that passes the field on may cut it or keep it).
type Field is Data:
  Field{name: Bytes(), value: Bytes()}

def cat(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, a, b)

def rev(a: List<&2, U32>) -> List<&2, U32>:
  List.reverse(&2, U32, a)

def beq(a: List<&2, U32>, b: List<&2, U32>, acc: Bool) -> Bool:
  match a b:
    case Nil{} Nil{}:
      acc
    case Nil{} Con{y, u}:
      False{}
    case Con{x, t} Nil{}:
      False{}
    case Con{x, t} Con{y, u}:
      beq(t, u, acc && U32.is_eq(x, y))

def digit(+c: U32) -> Bool:
  U32.is_le(48, c) && U32.is_le(c, 57)

# The machine
# ===========

# feed: the machine over a list of bytes, one at a time. The state that
# comes out is the state to feed the next read.
def feed(~E: Data, ~S: Data, ~step: E -> S -> U32 -> S, +e: E, bs: List<&2, U32>, p: S) -> S:
  match bs:
    case Nil{}:
      p
    case Con{c, t}:
      feed(~E, ~S, ~step, e, t, step(e, p, c))

# The same walk over Bytes, a byte at a time.
def feed_buf.slow(~E: Data, ~S: Data, ~step: E -> S -> U32 -> S, +e: E, s: Bytes(), p: S) -> S:
  match s:
    case SNil{}:
      p
    case SCon{Chr{c}, t}:
      feed_buf.slow(~E, ~S, ~step, e, t, step(e, p, c))

# the rest of a walk the fuel ran out on, a byte at a time
def feed_buf.last(~E: Data, ~S: Data, ~step: E -> S -> U32 -> S, +e: E, q: S & Bytes()) -> S:
  (p, s) = q
  feed_buf.slow(~E, ~S, ~step, e, s, p)

# the move that takes one byte: the walk of a protocol with no runs
def one.step(~E: Data, ~S: Data, ~step: E -> S -> U32 -> S, e: E, s: Bytes(), p: S) ->
  S & Bytes():
  match s:
    case SNil{}:
      (p, SNil{})
    case SCon{Chr{c}, t}:
      (step(e, p, c), t)

# n bounds the moves; every move takes at least one byte, so a walk over
# n bytes never runs out
def feed_buf.go(
  ~E: Data, ~S: Data, ~step: E -> S -> U32 -> S, ~adv: E -> Bytes() -> S -> S & Bytes(),
  +e: E, n: Nat, q: S & Bytes()
) -> S:
  match n:
    case 0n:
      feed_buf.last(~E, ~S, ~step, e, q)
    case 1n+m:
      (p, s) = q
      match s:
        case SNil{}:
          p
        case SCon{h, t}:
          feed_buf.go(~E, ~S, ~step, ~adv, e, m, adv(e, SCon{h, t}, p))

# The walk a server runs on a read: one packed block, moved through by
# the protocol's own moves.
def feed_buf(
  ~E: Data, ~S: Data, ~step: E -> S -> U32 -> S, ~adv: E -> Bytes() -> S -> S & Bytes(),
  +e: E, +s: Bytes(), p: S
) -> S:
  feed_buf.go(~E, ~S, ~step, ~adv, e, Bytes.len(s), (p, s))

# the reads of a stream, each fed in turn
def reads(
  ~E: Data, ~S: Data, ~step: E -> S -> U32 -> S, ~adv: E -> Bytes() -> S -> S & Bytes(),
  +e: E, rs: List<&2, Bytes()>, p: S
) -> S:
  match rs:
    case Nil{}:
      p
    case Con{r, t}:
      reads(~E, ~S, ~step, ~adv, e, t, feed_buf(~E, ~S, ~step, ~adv, e, r, p))

# The laws
# ========

# LAW: chunking does not change the read. Feeding a chunk and then the
# next lands exactly where feeding the two joined would have, for every
# step function and every state type.
law feed_split:
  for ~E: Data
  for ~S: Data
  for ~step: E -> S -> U32 -> S
  for +e: E
  for +a: List<&2, U32>
  for +b: List<&2, U32>
  for +p: S
  {feed(~E, ~S, ~step, e, List.append(&2, U32, a, b), p) ==
    feed(~E, ~S, ~step, e, b, feed(~E, ~S, ~step, e, a, p)) : S}

def feed_split(E, S, step, e, a, b, p):
  match a:
    case Nil{}:
      {==}
    case Con{c, t}:
      feed_split(~E, ~S, ~step, e, t, b, step(e, p, c))

# LAW: a refusal is never left. When every refused state (bad(x), for
# each x a refusal can carry) is a fixed point of the step, no input
# moves the reader out of one: nothing after a refused byte is read.
law bad_feeds:
  for ~E: Data
  for ~S: Data
  for ~step: E -> S -> U32 -> S
  for ~X: Data
  for ~bad: X -> S
  for ~absorbs: @+e: E -> @+x: X -> @+c: U32 -> {step(e, bad(x), c) == bad(x) : S}
  for +e: E
  for +s: List<&2, U32>
  for +x: X
  {feed(~E, ~S, ~step, e, s, bad(x)) == bad(x) : S}

def bad_feeds(E, S, step, X, bad, absorbs, e, s, x):
  match s:
    case Nil{}:
      {==}
    case Con{c, t}:
      %Equal.sym(S, step(e, bad(x), c), bad(x), absorbs(e, x, c)) :
        {feed(~E, ~S, ~step, e, t, _) == bad(x) : S}
      bad_feeds(~E, ~S, ~step, ~X, ~bad, ~absorbs, e, t, x)

# the byte-at-a-time walk over Bytes is feed on its bytes
law slow_is_feed:
  for ~E: Data
  for ~S: Data
  for ~step: E -> S -> U32 -> S
  for +e: E
  for +s: Bytes()
  for +p: S
  {feed_buf.slow(~E, ~S, ~step, e, s, p) == feed(~E, ~S, ~step, e, Bytes.to_list(s), p) : S}

def slow_is_feed(E, S, step, e, s, p):
  match s:
    case SNil{}:
      {==}
    case SCon{Chr{c}, t}:
      slow_is_feed(~E, ~S, ~step, e, t, step(e, p, c))

# LAW: a protocol that walks a read a byte at a time (feed_buf.slow, no
# moves to prove) has the block laws with no obligation at all.
law slow_split:
  for ~E: Data
  for ~S: Data
  for ~step: E -> S -> U32 -> S
  for +e: E
  for +a: Bytes()
  for +b: Bytes()
  for +p: S
  {feed_buf.slow(~E, ~S, ~step, e, Bytes.append(a, b), p) ==
    feed_buf.slow(~E, ~S, ~step, e, b, feed_buf.slow(~E, ~S, ~step, e, a, p)) : S}

def slow_split(E, S, step, e, a, b, p):
  match a:
    case SNil{}:
      {==}
    case SCon{Chr{c}, t}:
      slow_split(~E, ~S, ~step, e, t, b, step(e, p, c))

law bad_feeds_slow:
  for ~E: Data
  for ~S: Data
  for ~step: E -> S -> U32 -> S
  for ~X: Data
  for ~bad: X -> S
  for ~absorbs: @+e: E -> @+x: X -> @+c: U32 -> {step(e, bad(x), c) == bad(x) : S}
  for +e: E
  for +s: Bytes()
  for +x: X
  {feed_buf.slow(~E, ~S, ~step, e, s, bad(x)) == bad(x) : S}

def bad_feeds_slow(E, S, step, X, bad, absorbs, e, s, x):
  match s:
    case SNil{}:
      {==}
    case SCon{Chr{c}, t}:
      %Equal.sym(S, step(e, bad(x), c), bad(x), absorbs(e, x, c)) :
        {feed_buf.slow(~E, ~S, ~step, e, t, _) == bad(x) : S}
      bad_feeds_slow(~E, ~S, ~step, ~X, ~bad, ~absorbs, e, t, x)

# the one-byte move keeps the obligation: a protocol with no runs hands
# in one.step and one.step_ok
law one.step_ok:
  for ~E: Data
  for ~S: Data
  for ~step: E -> S -> U32 -> S
  for +e: E
  for +s: Bytes()
  for p: S
  {feed_buf.last(~E, ~S, ~step, e, one.step(~E, ~S, ~step, e, s, p)) ==
    feed_buf.slow(~E, ~S, ~step, e, s, p) : S}

def one.step_ok(E, S, step, e, s, p):
  match s:
    case SNil{}:
      {==}
    case SCon{Chr{c}, t}:
      {==}

# the fuel never matters: however many moves are left, the walk ends
# where the byte-at-a-time walk does, given that each move does
law go_is_slow:
  for ~E: Data
  for ~S: Data
  for ~step: E -> S -> U32 -> S
  for ~adv: E -> Bytes() -> S -> S & Bytes()
  for ~adv_ok: @+e: E -> @+s: Bytes() -> @p: S ->
    {feed_buf.last(~E, ~S, ~step, e, adv(e, s, p)) == feed_buf.slow(~E, ~S, ~step, e, s, p) : S}
  for +e: E
  for n: Nat
  for q: S & Bytes()
  {feed_buf.go(~E, ~S, ~step, ~adv, e, n, q) == feed_buf.last(~E, ~S, ~step, e, q) : S}

def go_is_slow(E, S, step, adv, adv_ok, e, n, q):
  match n:
    case 0n:
      {==}
    case 1n+m:
      match q:
        case (p, SNil{}):
          {==}
        case (+p, SCon{+h, +t}):
          Equal.trans(S, feed_buf.go(~E, ~S, ~step, ~adv, e, m, adv(e, SCon{h, t}, p)),
            feed_buf.last(~E, ~S, ~step, e, adv(e, SCon{h, t}, p)),
            feed_buf.slow(~E, ~S, ~step, e, SCon{h, t}, p),
            go_is_slow(~E, ~S, ~step, ~adv, ~adv_ok, e, m, adv(e, SCon{h, t}, p)),
            adv_ok(e, SCon{h, t}, p))

# LAW: the walk a server runs is the byte machine. feed_buf moves through
# a read by the protocol's own moves, runs taken whole; for every block
# and every state it lands where feed does on the block's bytes. So
# every law of feed is a law of feed_buf.
law feed_buf_is_feed:
  for ~E: Data
  for ~S: Data
  for ~step: E -> S -> U32 -> S
  for ~adv: E -> Bytes() -> S -> S & Bytes()
  for ~adv_ok: @+e: E -> @+s: Bytes() -> @p: S ->
    {feed_buf.last(~E, ~S, ~step, e, adv(e, s, p)) == feed_buf.slow(~E, ~S, ~step, e, s, p) : S}
  for +e: E
  for +b: Bytes()
  for +p: S
  {feed_buf(~E, ~S, ~step, ~adv, e, b, p) == feed(~E, ~S, ~step, e, Bytes.to_list(b), p) : S}

def feed_buf_is_feed(E, S, step, adv, adv_ok, e, b, p):
  Equal.trans(S, feed_buf(~E, ~S, ~step, ~adv, e, b, p), feed_buf.slow(~E, ~S, ~step, e, b, p),
    feed(~E, ~S, ~step, e, Bytes.to_list(b), p),
    go_is_slow(~E, ~S, ~step, ~adv, ~adv_ok, e, Bytes.len(b), (p, b)),
    slow_is_feed(~E, ~S, ~step, e, b, p))

# LAW: and chunking does not change the read on blocks either.
law feed_buf_split:
  for ~E: Data
  for ~S: Data
  for ~step: E -> S -> U32 -> S
  for ~adv: E -> Bytes() -> S -> S & Bytes()
  for ~adv_ok: @+e: E -> @+s: Bytes() -> @p: S ->
    {feed_buf.last(~E, ~S, ~step, e, adv(e, s, p)) == feed_buf.slow(~E, ~S, ~step, e, s, p) : S}
  for +e: E
  for +a: Bytes()
  for +b: Bytes()
  for +p: S
  {feed_buf(~E, ~S, ~step, ~adv, e, Bytes.append(a, b), p) ==
    feed_buf(~E, ~S, ~step, ~adv, e, b, feed_buf(~E, ~S, ~step, ~adv, e, a, p)) : S}

def feed_buf_split(E, S, step, adv, adv_ok, e, a, b, p):
  %Equal.sym(S, feed_buf(~E, ~S, ~step, ~adv, e, Bytes.append(a, b), p),
    feed(~E, ~S, ~step, e, Bytes.to_list(Bytes.append(a, b)), p),
    feed_buf_is_feed(~E, ~S, ~step, ~adv, ~adv_ok, e, Bytes.append(a, b), p)) :
    {_ == feed_buf(~E, ~S, ~step, ~adv, e, b, feed_buf(~E, ~S, ~step, ~adv, e, a, p)) : S}
  %Equal.sym(List<&2, U32>, Bytes.to_list(Bytes.append(a, b)),
    List.append(&2, U32, Bytes.to_list(a), Bytes.to_list(b)), Bytes.to_list_append(a, b)) :
    {feed(~E, ~S, ~step, e, _, p) ==
      feed_buf(~E, ~S, ~step, ~adv, e, b, feed_buf(~E, ~S, ~step, ~adv, e, a, p)) : S}
  %Equal.sym(S, feed(~E, ~S, ~step, e, List.append(&2, U32, Bytes.to_list(a), Bytes.to_list(b)), p),
    feed(~E, ~S, ~step, e, Bytes.to_list(b), feed(~E, ~S, ~step, e, Bytes.to_list(a), p)),
    feed_split(~E, ~S, ~step, e, Bytes.to_list(a), Bytes.to_list(b), p)) :
    {_ == feed_buf(~E, ~S, ~step, ~adv, e, b, feed_buf(~E, ~S, ~step, ~adv, e, a, p)) : S}
  %feed_buf_is_feed(~E, ~S, ~step, ~adv, ~adv_ok, e, a, p) :
    {feed(~E, ~S, ~step, e, Bytes.to_list(b), _) ==
      feed_buf(~E, ~S, ~step, ~adv, e, b, feed_buf(~E, ~S, ~step, ~adv, e, a, p)) : S}
  Equal.sym(S, feed_buf(~E, ~S, ~step, ~adv, e, b, feed_buf(~E, ~S, ~step, ~adv, e, a, p)),
    feed(~E, ~S, ~step, e, Bytes.to_list(b), feed_buf(~E, ~S, ~step, ~adv, e, a, p)),
    feed_buf_is_feed(~E, ~S, ~step, ~adv, ~adv_ok, e, b, feed_buf(~E, ~S, ~step, ~adv, e, a, p)))

# LAW: a refusal is never left, on blocks.
law bad_feeds_buf:
  for ~E: Data
  for ~S: Data
  for ~step: E -> S -> U32 -> S
  for ~adv: E -> Bytes() -> S -> S & Bytes()
  for ~adv_ok: @+e: E -> @+s: Bytes() -> @p: S ->
    {feed_buf.last(~E, ~S, ~step, e, adv(e, s, p)) == feed_buf.slow(~E, ~S, ~step, e, s, p) : S}
  for ~X: Data
  for ~bad: X -> S
  for ~absorbs: @+e: E -> @+x: X -> @+c: U32 -> {step(e, bad(x), c) == bad(x) : S}
  for +e: E
  for +s: Bytes()
  for +x: X
  {feed_buf(~E, ~S, ~step, ~adv, e, s, bad(x)) == bad(x) : S}

def bad_feeds_buf(E, S, step, adv, adv_ok, X, bad, absorbs, e, s, x):
  %Equal.sym(S, feed_buf(~E, ~S, ~step, ~adv, e, s, bad(x)),
    feed(~E, ~S, ~step, e, Bytes.to_list(s), bad(x)),
    feed_buf_is_feed(~E, ~S, ~step, ~adv, ~adv_ok, e, s, bad(x))) :
    {_ == bad(x) : S}
  bad_feeds(~E, ~S, ~step, ~X, ~bad, ~absorbs, e, Bytes.to_list(s), x)

# LAW: however a stream is cut into reads, the reader fed each read in
# turn lands where feed lands on the stream whole ...
law reads_is:
  for ~E: Data
  for ~S: Data
  for ~step: E -> S -> U32 -> S
  for ~adv: E -> Bytes() -> S -> S & Bytes()
  for ~adv_ok: @+e: E -> @+s: Bytes() -> @p: S ->
    {feed_buf.last(~E, ~S, ~step, e, adv(e, s, p)) == feed_buf.slow(~E, ~S, ~step, e, s, p) : S}
  for +e: E
  for +rs: List<&2, Bytes()>
  for +p: S
  {reads(~E, ~S, ~step, ~adv, e, rs, p) ==
    feed(~E, ~S, ~step, e, Bytes.to_list(Bytes.concat(rs)), p) : S}

def reads_is(E, S, step, adv, adv_ok, e, rs, p):
  match rs:
    case Nil{}:
      {==}
    case Con{+r, +t}:
      %Equal.sym(List<&2, U32>, Bytes.to_list(Bytes.append(r, Bytes.concat(t))),
        List.append(&2, U32, Bytes.to_list(r), Bytes.to_list(Bytes.concat(t))),
        Bytes.to_list_append(r, Bytes.concat(t))) :
        {reads(~E, ~S, ~step, ~adv, e, t, feed_buf(~E, ~S, ~step, ~adv, e, r, p)) ==
          feed(~E, ~S, ~step, e, _, p) : S}
      %Equal.sym(S,
        feed(~E, ~S, ~step, e, List.append(&2, U32, Bytes.to_list(r), Bytes.to_list(Bytes.concat(t))), p),
        feed(~E, ~S, ~step, e, Bytes.to_list(Bytes.concat(t)), feed(~E, ~S, ~step, e, Bytes.to_list(r), p)),
        feed_split(~E, ~S, ~step, e, Bytes.to_list(r), Bytes.to_list(Bytes.concat(t)), p)) :
        {reads(~E, ~S, ~step, ~adv, e, t, feed_buf(~E, ~S, ~step, ~adv, e, r, p)) == _ : S}
      %feed_buf_is_feed(~E, ~S, ~step, ~adv, ~adv_ok, e, r, p) :
        {reads(~E, ~S, ~step, ~adv, e, t, feed_buf(~E, ~S, ~step, ~adv, e, r, p)) ==
          feed(~E, ~S, ~step, e, Bytes.to_list(Bytes.concat(t)), _) : S}
      reads_is(~E, ~S, ~step, ~adv, ~adv_ok, e, t, feed_buf(~E, ~S, ~step, ~adv, e, r, p))

# LAW: ... and where the walk lands on the stream whole: any list of
# reads reads as their concatenation read at once.
law reads_split:
  for ~E: Data
  for ~S: Data
  for ~step: E -> S -> U32 -> S
  for ~adv: E -> Bytes() -> S -> S & Bytes()
  for ~adv_ok: @+e: E -> @+s: Bytes() -> @p: S ->
    {feed_buf.last(~E, ~S, ~step, e, adv(e, s, p)) == feed_buf.slow(~E, ~S, ~step, e, s, p) : S}
  for +e: E
  for +rs: List<&2, Bytes()>
  for +p: S
  {reads(~E, ~S, ~step, ~adv, e, rs, p) == feed_buf(~E, ~S, ~step, ~adv, e, Bytes.concat(rs), p) : S}

def reads_split(E, S, step, adv, adv_ok, e, rs, p):
  Equal.trans(S, reads(~E, ~S, ~step, ~adv, e, rs, p),
    feed(~E, ~S, ~step, e, Bytes.to_list(Bytes.concat(rs)), p),
    feed_buf(~E, ~S, ~step, ~adv, e, Bytes.concat(rs), p),
    reads_is(~E, ~S, ~step, ~adv, ~adv_ok, e, rs, p),
    Equal.sym(S, feed_buf(~E, ~S, ~step, ~adv, e, Bytes.concat(rs), p),
      feed(~E, ~S, ~step, e, Bytes.to_list(Bytes.concat(rs)), p),
      feed_buf_is_feed(~E, ~S, ~step, ~adv, ~adv_ok, e, Bytes.concat(rs), p)))

# Taking a body as it comes
# =========================
#
# A reader that frames a body gathers it in its state. A consumer that
# streams the body takes what the reader holds after each read, and the
# reader goes on holding none: ~take answers the bytes and the state
# without them, and ~give puts bytes back in front of what a state
# holds. drain is a stream read that way -- each read fed, then taken --
# with its takes joined in order.
#
# What the protocol proves of its take and give, as template arguments:
# a state is open (~open) once it is in a body, and from then on stays
# open (step_open) and steps the same with bytes put back in front as
# without, the bytes staying in front (step_give); a state not open
# holds none (shut_take); and take and give are inverse (give_take),
# with give of nothing nothing (give_nil) and of two joined, the two in
# turn (give_app). take_open: taking leaves a state as open as it was.
#
# What it gets: drain_reads, the takes of a stream, joined, put back in
# front of the reader that took them, are the reader fed the stream
# whole: the concatenation of the chunks a consumer was handed, then
# what the reader still holds, is the body exactly, whatever the cuts.

def drain.s(-S: Type, q: S & Bytes()) -> S:
  (p, x) = q
  p

def drain.b(-S: Type, q: S & Bytes()) -> Bytes():
  (p, x) = q
  x

def drain.on(
  -S: Type, q: S & Bytes(), +acc: Bytes(), again: S -> Bytes() -> S & Bytes()
) -> S & Bytes():
  (p, x) = q
  again(p, Bytes.append(acc, x))

def drain(
  ~E: Data, ~S: Data, ~step: E -> S -> U32 -> S, ~adv: E -> Bytes() -> S -> S & Bytes(),
  ~take: S -> S & Bytes(), +e: E, rs: List<&2, Bytes()>, p: S, +acc: Bytes()
) -> S & Bytes():
  match rs:
    case Nil{}:
      (p, acc)
    case Con{r, t}:
      drain.on(S, take(feed_buf(~E, ~S, ~step, ~adv, e, r, p)), acc,
        q => a => drain(~E, ~S, ~step, ~adv, ~take, e, t, q, a))

# a byte list fed to an open state with bytes put back in front lands
# where it lands without them, the bytes still in front
law feed_give:
  for ~E: Data
  for ~S: Data
  for ~step: E -> S -> U32 -> S
  for ~give: Bytes() -> S -> S
  for ~open: S -> Bool
  for ~step_open: @+e: E -> @+p: S -> @+c: U32 -> @o: {open(p) == True{} : Bool} ->
    {open(step(e, p, c)) == True{} : Bool}
  for ~step_give: @+e: E -> @+x: Bytes() -> @+p: S -> @+c: U32 ->
    @o: {open(p) == True{} : Bool} -> {step(e, give(x, p), c) == give(x, step(e, p, c)) : S}
  for +e: E
  for +bs: List<&2, U32>
  for +x: Bytes()
  for +p: S
  for +o: {open(p) == True{} : Bool}
  {feed(~E, ~S, ~step, e, bs, give(x, p)) == give(x, feed(~E, ~S, ~step, e, bs, p)) : S}

def feed_give(E, S, step, give, open, step_open, step_give, e, bs, x, p, o):
  match bs:
    case Nil{}:
      {==}
    case Con{+c, +t}:
      %Equal.sym(S, step(e, give(x, p), c), give(x, step(e, p, c)), step_give(e, x, p, c, o)) :
        {feed(~E, ~S, ~step, e, t, _) ==
          give(x, feed(~E, ~S, ~step, e, t, step(e, p, c))) : S}
      feed_give(~E, ~S, ~step, ~give, ~open, ~step_open, ~step_give, e, t, x, step(e, p, c),
        step_open(e, p, c, o))

# ... and so does a stream of reads
law reads_give:
  for ~E: Data
  for ~S: Data
  for ~step: E -> S -> U32 -> S
  for ~adv: E -> Bytes() -> S -> S & Bytes()
  for ~adv_ok: @+e: E -> @+s: Bytes() -> @p: S ->
    {feed_buf.last(~E, ~S, ~step, e, adv(e, s, p)) == feed_buf.slow(~E, ~S, ~step, e, s, p) : S}
  for ~give: Bytes() -> S -> S
  for ~open: S -> Bool
  for ~step_open: @+e: E -> @+p: S -> @+c: U32 -> @o: {open(p) == True{} : Bool} ->
    {open(step(e, p, c)) == True{} : Bool}
  for ~step_give: @+e: E -> @+x: Bytes() -> @+p: S -> @+c: U32 ->
    @o: {open(p) == True{} : Bool} -> {step(e, give(x, p), c) == give(x, step(e, p, c)) : S}
  for +e: E
  for +rs: List<&2, Bytes()>
  for +x: Bytes()
  for +p: S
  for +o: {open(p) == True{} : Bool}
  {reads(~E, ~S, ~step, ~adv, e, rs, give(x, p)) == give(x, reads(~E, ~S, ~step, ~adv, e, rs, p)) :
    S}

def reads_give(E, S, step, adv, adv_ok, give, open, step_open, step_give, e, rs, x, p, o):
  %Equal.sym(S, reads(~E, ~S, ~step, ~adv, e, rs, give(x, p)),
    feed(~E, ~S, ~step, e, Bytes.to_list(Bytes.concat(rs)), give(x, p)),
    reads_is(~E, ~S, ~step, ~adv, ~adv_ok, e, rs, give(x, p))) :
    {_ == give(x, reads(~E, ~S, ~step, ~adv, e, rs, p)) : S}
  %Equal.sym(S, reads(~E, ~S, ~step, ~adv, e, rs, p),
    feed(~E, ~S, ~step, e, Bytes.to_list(Bytes.concat(rs)), p),
    reads_is(~E, ~S, ~step, ~adv, ~adv_ok, e, rs, p)) :
    {feed(~E, ~S, ~step, e, Bytes.to_list(Bytes.concat(rs)), give(x, p)) == give(x, _) : S}
  feed_give(~E, ~S, ~step, ~give, ~open, ~step_open, ~step_give, e,
    Bytes.to_list(Bytes.concat(rs)), x, p, o)

# the bytes a take took, put back in front of the rest of the stream
# read from the state it left, are the stream read from the state it
# took them from: open, by reads_give; not open, it took none
law take_back.at:
  for ~E: Data
  for ~S: Data
  for ~step: E -> S -> U32 -> S
  for ~adv: E -> Bytes() -> S -> S & Bytes()
  for ~adv_ok: @+e: E -> @+s: Bytes() -> @p: S ->
    {feed_buf.last(~E, ~S, ~step, e, adv(e, s, p)) == feed_buf.slow(~E, ~S, ~step, e, s, p) : S}
  for ~take: S -> S & Bytes()
  for ~give: Bytes() -> S -> S
  for ~open: S -> Bool
  for ~step_open: @+e: E -> @+p: S -> @+c: U32 -> @o: {open(p) == True{} : Bool} ->
    {open(step(e, p, c)) == True{} : Bool}
  for ~step_give: @+e: E -> @+x: Bytes() -> @+p: S -> @+c: U32 ->
    @o: {open(p) == True{} : Bool} -> {step(e, give(x, p), c) == give(x, step(e, p, c)) : S}
  for ~take_open: @+p: S -> {open(drain.s(S, take(p))) == open(p) : Bool}
  for ~shut_take: @+p: S -> @o: {open(p) == False{} : Bool} -> {drain.b(S, take(p)) == "" : Bytes()}
  for ~give_take: @+p: S -> {give(drain.b(S, take(p)), drain.s(S, take(p))) == p : S}
  for ~give_nil: @+p: S -> {give("", p) == p : S}
  for +e: E
  for +t: List<&2, Bytes()>
  for +f: S
  for b: Bool
  for +eb: {open(drain.s(S, take(f))) == b : Bool}
  {give(drain.b(S, take(f)), reads(~E, ~S, ~step, ~adv, e, t, drain.s(S, take(f)))) ==
    reads(~E, ~S, ~step, ~adv, e, t, f) : S}

def take_back.at(E, S, step, adv, adv_ok, take, give, open, step_open, step_give, take_open,
  shut_take, give_take, give_nil, e, t, f, b, eb):
  match b:
    case True{}:
      %give_take(f) :
        {give(drain.b(S, take(f)), reads(~E, ~S, ~step, ~adv, e, t, drain.s(S, take(f)))) ==
          reads(~E, ~S, ~step, ~adv, e, t, _) : S}
      Equal.sym(S, reads(~E, ~S, ~step, ~adv, e, t,
          give(drain.b(S, take(f)), drain.s(S, take(f)))),
        give(drain.b(S, take(f)), reads(~E, ~S, ~step, ~adv, e, t, drain.s(S, take(f)))),
        reads_give(~E, ~S, ~step, ~adv, ~adv_ok, ~give, ~open, ~step_open, ~step_give, e, t,
          drain.b(S, take(f)), drain.s(S, take(f)), eb))
    case False{}:
      %give_take(f) :
        {give(drain.b(S, take(f)), reads(~E, ~S, ~step, ~adv, e, t, drain.s(S, take(f)))) ==
          reads(~E, ~S, ~step, ~adv, e, t, _) : S}
      %Equal.sym(Bytes(), drain.b(S, take(f)), "",
        shut_take(f, Equal.trans(Bool, open(f), open(drain.s(S, take(f))), False{},
          Equal.sym(Bool, open(drain.s(S, take(f))), open(f), take_open(f)), eb))) :
        {give(_, reads(~E, ~S, ~step, ~adv, e, t, drain.s(S, take(f)))) ==
          reads(~E, ~S, ~step, ~adv, e, t, give(drain.b(S, take(f)), drain.s(S, take(f)))) : S}
      %Equal.sym(Bytes(), drain.b(S, take(f)), "",
        shut_take(f, Equal.trans(Bool, open(f), open(drain.s(S, take(f))), False{},
          Equal.sym(Bool, open(drain.s(S, take(f))), open(f), take_open(f)), eb))) :
        {give("", reads(~E, ~S, ~step, ~adv, e, t, drain.s(S, take(f)))) ==
          reads(~E, ~S, ~step, ~adv, e, t, give(_, drain.s(S, take(f)))) : S}
      %Equal.sym(S, give("", reads(~E, ~S, ~step, ~adv, e, t, drain.s(S, take(f)))),
        reads(~E, ~S, ~step, ~adv, e, t, drain.s(S, take(f))),
        give_nil(reads(~E, ~S, ~step, ~adv, e, t, drain.s(S, take(f))))) :
        {_ == reads(~E, ~S, ~step, ~adv, e, t, give("", drain.s(S, take(f)))) : S}
      %Equal.sym(S, give("", drain.s(S, take(f))), drain.s(S, take(f)),
        give_nil(drain.s(S, take(f)))) :
        {reads(~E, ~S, ~step, ~adv, e, t, drain.s(S, take(f))) ==
          reads(~E, ~S, ~step, ~adv, e, t, _) : S}
      {==}

# one read of drain: what it took joins what came before, and the rest
# of the stream is drained from the state it left
law drain_on:
  for ~E: Data
  for ~S: Data
  for ~step: E -> S -> U32 -> S
  for ~adv: E -> Bytes() -> S -> S & Bytes()
  for ~take: S -> S & Bytes()
  for ~give: Bytes() -> S -> S
  for ~give_app: @+a: Bytes() -> @+b: Bytes() -> @+p: S ->
    {give(Bytes.append(a, b), p) == give(a, give(b, p)) : S}
  for +e: E
  for +t: List<&2, Bytes()>
  for q: S & Bytes()
  for +acc: Bytes()
  for ih: @+p: S -> @+a: Bytes() ->
    {give(drain.b(S, drain(~E, ~S, ~step, ~adv, ~take, e, t, p, a)),
      drain.s(S, drain(~E, ~S, ~step, ~adv, ~take, e, t, p, a))) ==
      give(a, reads(~E, ~S, ~step, ~adv, e, t, p)) : S}
  {give(drain.b(S, drain.on(S, q, acc, p => a => drain(~E, ~S, ~step, ~adv, ~take, e, t, p, a))),
    drain.s(S, drain.on(S, q, acc, p => a => drain(~E, ~S, ~step, ~adv, ~take, e, t, p, a)))) ==
    give(acc, give(drain.b(S, q), reads(~E, ~S, ~step, ~adv, e, t, drain.s(S, q)))) : S}

def drain_on(E, S, step, adv, take, give, give_app, e, t, q, acc, ih):
  (+p, +x) = q
  Equal.trans(S,
    give(drain.b(S, drain(~E, ~S, ~step, ~adv, ~take, e, t, p, Bytes.append(acc, x))),
      drain.s(S, drain(~E, ~S, ~step, ~adv, ~take, e, t, p, Bytes.append(acc, x)))),
    give(Bytes.append(acc, x), reads(~E, ~S, ~step, ~adv, e, t, p)),
    give(acc, give(x, reads(~E, ~S, ~step, ~adv, e, t, p))),
    ih(p, Bytes.append(acc, x)),
    give_app(acc, x, reads(~E, ~S, ~step, ~adv, e, t, p)))

law drain_give:
  for ~E: Data
  for ~S: Data
  for ~step: E -> S -> U32 -> S
  for ~adv: E -> Bytes() -> S -> S & Bytes()
  for ~adv_ok: @+e: E -> @+s: Bytes() -> @p: S ->
    {feed_buf.last(~E, ~S, ~step, e, adv(e, s, p)) == feed_buf.slow(~E, ~S, ~step, e, s, p) : S}
  for ~take: S -> S & Bytes()
  for ~give: Bytes() -> S -> S
  for ~open: S -> Bool
  for ~step_open: @+e: E -> @+p: S -> @+c: U32 -> @o: {open(p) == True{} : Bool} ->
    {open(step(e, p, c)) == True{} : Bool}
  for ~step_give: @+e: E -> @+x: Bytes() -> @+p: S -> @+c: U32 ->
    @o: {open(p) == True{} : Bool} -> {step(e, give(x, p), c) == give(x, step(e, p, c)) : S}
  for ~take_open: @+p: S -> {open(drain.s(S, take(p))) == open(p) : Bool}
  for ~shut_take: @+p: S -> @o: {open(p) == False{} : Bool} -> {drain.b(S, take(p)) == "" : Bytes()}
  for ~give_take: @+p: S -> {give(drain.b(S, take(p)), drain.s(S, take(p))) == p : S}
  for ~give_nil: @+p: S -> {give("", p) == p : S}
  for ~give_app: @+a: Bytes() -> @+b: Bytes() -> @+p: S ->
    {give(Bytes.append(a, b), p) == give(a, give(b, p)) : S}
  for +e: E
  for +rs: List<&2, Bytes()>
  for +p: S
  for +acc: Bytes()
  {give(drain.b(S, drain(~E, ~S, ~step, ~adv, ~take, e, rs, p, acc)),
    drain.s(S, drain(~E, ~S, ~step, ~adv, ~take, e, rs, p, acc))) ==
    give(acc, reads(~E, ~S, ~step, ~adv, e, rs, p)) : S}

def drain_give(E, S, step, adv, adv_ok, take, give, open, step_open, step_give, take_open, shut_take,
  give_take, give_nil, give_app, e, rs, p, acc):
  match rs:
    case Nil{}:
      {==}
    case Con{+r, +t}:
      Equal.trans(S,
        give(drain.b(S, drain.on(S, take(feed_buf(~E, ~S, ~step, ~adv, e, r, p)), acc,
            q => a => drain(~E, ~S, ~step, ~adv, ~take, e, t, q, a))),
          drain.s(S, drain.on(S, take(feed_buf(~E, ~S, ~step, ~adv, e, r, p)), acc,
            q => a => drain(~E, ~S, ~step, ~adv, ~take, e, t, q, a)))),
        give(acc, give(drain.b(S, take(feed_buf(~E, ~S, ~step, ~adv, e, r, p))),
          reads(~E, ~S, ~step, ~adv, e, t, drain.s(S, take(feed_buf(~E, ~S, ~step, ~adv, e, r, p)))))),
        give(acc, reads(~E, ~S, ~step, ~adv, e, t, feed_buf(~E, ~S, ~step, ~adv, e, r, p))),
        drain_on(~E, ~S, ~step, ~adv, ~take, ~give, ~give_app, e, t,
          take(feed_buf(~E, ~S, ~step, ~adv, e, r, p)), acc,
          q => a => drain_give(~E, ~S, ~step, ~adv, ~adv_ok, ~take, ~give, ~open, ~step_open,
            ~step_give, ~take_open, ~shut_take, ~give_take, ~give_nil, ~give_app, e, t, q, a)),
        Equal.cong(S, S, y => give(acc, y),
          give(drain.b(S, take(feed_buf(~E, ~S, ~step, ~adv, e, r, p))),
            reads(~E, ~S, ~step, ~adv, e, t, drain.s(S, take(feed_buf(~E, ~S, ~step, ~adv, e, r, p))))),
          reads(~E, ~S, ~step, ~adv, e, t, feed_buf(~E, ~S, ~step, ~adv, e, r, p)),
          take_back.at(~E, ~S, ~step, ~adv, ~adv_ok, ~take, ~give, ~open, ~step_open, ~step_give,
            ~take_open, ~shut_take, ~give_take, ~give_nil, e, t,
            feed_buf(~E, ~S, ~step, ~adv, e, r, p),
            open(drain.s(S, take(feed_buf(~E, ~S, ~step, ~adv, e, r, p)))), {==})))

# LAW: a body taken as it comes is the body. However a stream is cut
# into reads, the bytes taken after each read, joined in order, put back
# in front of what the reader still holds, are the reader fed the
# stream: no byte a consumer was handed is out of order, doubled, or
# missing, and none it was not handed is lost.
law drain_reads:
  for ~E: Data
  for ~S: Data
  for ~step: E -> S -> U32 -> S
  for ~adv: E -> Bytes() -> S -> S & Bytes()
  for ~adv_ok: @+e: E -> @+s: Bytes() -> @p: S ->
    {feed_buf.last(~E, ~S, ~step, e, adv(e, s, p)) == feed_buf.slow(~E, ~S, ~step, e, s, p) : S}
  for ~take: S -> S & Bytes()
  for ~give: Bytes() -> S -> S
  for ~open: S -> Bool
  for ~step_open: @+e: E -> @+p: S -> @+c: U32 -> @o: {open(p) == True{} : Bool} ->
    {open(step(e, p, c)) == True{} : Bool}
  for ~step_give: @+e: E -> @+x: Bytes() -> @+p: S -> @+c: U32 ->
    @o: {open(p) == True{} : Bool} -> {step(e, give(x, p), c) == give(x, step(e, p, c)) : S}
  for ~take_open: @+p: S -> {open(drain.s(S, take(p))) == open(p) : Bool}
  for ~shut_take: @+p: S -> @o: {open(p) == False{} : Bool} -> {drain.b(S, take(p)) == "" : Bytes()}
  for ~give_take: @+p: S -> {give(drain.b(S, take(p)), drain.s(S, take(p))) == p : S}
  for ~give_nil: @+p: S -> {give("", p) == p : S}
  for ~give_app: @+a: Bytes() -> @+b: Bytes() -> @+p: S ->
    {give(Bytes.append(a, b), p) == give(a, give(b, p)) : S}
  for +e: E
  for +rs: List<&2, Bytes()>
  for +p: S
  {give(drain.b(S, drain(~E, ~S, ~step, ~adv, ~take, e, rs, p, "")),
    drain.s(S, drain(~E, ~S, ~step, ~adv, ~take, e, rs, p, ""))) ==
    reads(~E, ~S, ~step, ~adv, e, rs, p) : S}

def drain_reads(E, S, step, adv, adv_ok, take, give, open, step_open, step_give, take_open,
  shut_take, give_take, give_nil, give_app, e, rs, p):
  Equal.trans(S,
    give(drain.b(S, drain(~E, ~S, ~step, ~adv, ~take, e, rs, p, "")),
      drain.s(S, drain(~E, ~S, ~step, ~adv, ~take, e, rs, p, ""))),
    give("", reads(~E, ~S, ~step, ~adv, e, rs, p)),
    reads(~E, ~S, ~step, ~adv, e, rs, p),
    drain_give(~E, ~S, ~step, ~adv, ~adv_ok, ~take, ~give, ~open, ~step_open, ~step_give,
      ~take_open, ~shut_take, ~give_take, ~give_nil, ~give_app, e, rs, p, ""),
    give_nil(reads(~E, ~S, ~step, ~adv, e, rs, p)))
