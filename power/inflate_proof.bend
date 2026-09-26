# inflate_proof.bend: deflate.bend's fast inflate (fi.drv) is its
# machine over the stream's bits, whatever the stream. Every read of the
# fast path is one of the machine's steps: a bit (rs), a code's walk
# (wl), extra bits (gl), a symbol whole (dec), symbols one after another
# (rn), and the driver that falls back to a bit wherever the fast path
# stops (drv). deflate_proof.bend states it as law inflate_fast.
import Base
import ./deflate.bend as D
import ../wire/reader.bend as Wr

# The input's bits
# ================

# the bits from bit r of byte q on
def R(+s: Bytes(), +q: Nat, +r: Nat) -> List<&2, Bool>:
  D.fi.rest(Bytes.drop(s, q), r)

def pk(+b: Bool, +p: Nat) -> {1n+D.pick(b, 1n+p, p) == D.pick(b, 2n+p, 1n+p) : Nat}:
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

def in_tail(+h: Char, +u: Bytes(), +p: Nat, e: {D.fi.in(SCon{h, u}, 1n+p) == True{} : Bool}) ->
  {D.fi.in(u, p) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_lt(1n+p, 1n+String.length.go(u, 0n)), Nat.is_lt(1n+p, String.length.go(u, 1n)), True{},
    Equal.cong(Nat, Bool, x => Nat.is_lt(1n+p, x), 1n+String.length.go(u, 0n), String.length.go(u, 1n),
      Equal.sym(Nat, String.length.go(u, 1n), 1n+String.length.go(u, 0n), Bytes.len.shift(u, 0n))), e)

def RS.t(+s: Bytes(), +q: Nat, +r: Nat, +st: D.St) -> Type:
  {D.fi.bfeed(R(s, q, r), st) ==
    D.fi.bfeed(R(s, D.fi.nq(q, r), D.next_bp(r)), D.bstep(st, D.fi.b(s, q, r))) : D.St}

# one bit read: the machine a bit on, the rest from the next bit
def rs(+s: Bytes(), +q: Nat, +r: Nat, +st: D.St) -> {D.fi.in(s, q) == True{} : Bool} ->
  {Nat.is_lt(r, 8n) == True{} : Bool} -> RS.t(s, q, r, st):
  match s q:
    case SNil{} 0n:
      e => h => Bool.no(RS.t(SNil{}, 0n, r, st), e)
    case SNil{} 1n+p:
      e => h => Bool.no(RS.t(SNil{}, 1n+p, r, st), e)
    case SCon{Chr{c}, SNil{}} 0n:
      match r:
        case 0n:
          e => hr => {==}
        case 1n+r1:
          match r1:
            case 0n:
              e => hr => {==}
            case 1n+r2:
              match r2:
                case 0n:
                  e => hr => {==}
                case 1n+r3:
                  match r3:
                    case 0n:
                      e => hr => {==}
                    case 1n+r4:
                      match r4:
                        case 0n:
                          e => hr => {==}
                        case 1n+r5:
                          match r5:
                            case 0n:
                              e => hr => {==}
                            case 1n+r6:
                              match r6:
                                case 0n:
                                  e => hr => {==}
                                case 1n+r7:
                                  match r7:
                                    case 0n:
                                      e => hr => {==}
                                    case 1n+r8:
                                      match r8:
                                        case 0n:
                                          e => hr => Bool.no(RS.t(SCon{Chr{c}, SNil{}}, 0n, 8n, st), hr)
                                        case 1n+r9:
                                          e => hr => Bool.no(RS.t(SCon{Chr{c}, SNil{}}, 0n, 9n+r9, st), hr)

    case SCon{Chr{c}, SCon{Chr{c2}, u2}} 0n:
      match r:
        case 0n:
          e => hr => {==}
        case 1n+r1:
          match r1:
            case 0n:
              e => hr => {==}
            case 1n+r2:
              match r2:
                case 0n:
                  e => hr => {==}
                case 1n+r3:
                  match r3:
                    case 0n:
                      e => hr => {==}
                    case 1n+r4:
                      match r4:
                        case 0n:
                          e => hr => {==}
                        case 1n+r5:
                          match r5:
                            case 0n:
                              e => hr => {==}
                            case 1n+r6:
                              match r6:
                                case 0n:
                                  e => hr => {==}
                                case 1n+r7:
                                  match r7:
                                    case 0n:
                                      e => hr => {==}
                                    case 1n+r8:
                                      match r8:
                                        case 0n:
                                          e => hr => Bool.no(RS.t(SCon{Chr{c}, SCon{Chr{c2}, u2}}, 0n, 8n, st), hr)
                                        case 1n+r9:
                                          e => hr => Bool.no(RS.t(SCon{Chr{c}, SCon{Chr{c2}, u2}}, 0n, 9n+r9, st), hr)

    case SCon{h, u} 1n+p:
      e => hr => Equal.trans(D.St, D.fi.bfeed(R(SCon{h, u}, 1n+p, r), st),
        D.fi.bfeed(D.fi.rest(Bytes.drop(SCon{h, u}, 1n+D.fi.nq(p, r)), D.next_bp(r)),
          D.bstep(st, D.fi.b(SCon{h, u}, 1n+p, r))),
        D.fi.bfeed(D.fi.rest(Bytes.drop(SCon{h, u}, D.fi.nq(1n+p, r)), D.next_bp(r)),
          D.bstep(st, D.fi.b(SCon{h, u}, 1n+p, r))),
        rs(u, p, r, st)(in_tail(h, u, p, e))(hr),
        Equal.cong(Nat, D.St, x => D.fi.bfeed(D.fi.rest(Bytes.drop(SCon{h, u}, x), D.next_bp(r)),
          D.bstep(st, D.fi.b(SCon{h, u}, 1n+p, r))), 1n+D.fi.nq(p, r), D.fi.nq(1n+p, r),
          pk(Nat.is_eq(r, 7n), p)))

# the offset of the next bit is an offset in a byte
def nb(+r: Nat) -> {Nat.is_lt(r, 8n) == True{} : Bool} -> {Nat.is_lt(D.next_bp(r), 8n) == True{} : Bool}:
  match r:
    case 0n:
      h => {==}
    case 1n+r1:
      match r1:
        case 0n:
          h => {==}
        case 1n+r2:
          match r2:
            case 0n:
              h => {==}
            case 1n+r3:
              match r3:
                case 0n:
                  h => {==}
                case 1n+r4:
                  match r4:
                    case 0n:
                      h => {==}
                    case 1n+r5:
                      match r5:
                        case 0n:
                          h => {==}
                        case 1n+r6:
                          match r6:
                            case 0n:
                              h => {==}
                            case 1n+r7:
                              match r7:
                                case 0n:
                                  h => {==}
                                case 1n+r8:
                                  match r8:
                                    case 0n:
                                      h => Bool.no({Nat.is_lt(D.next_bp(8n), 8n) == True{} : Bool}, h)
                                    case 1n+r9:
                                      h => Bool.no({Nat.is_lt(D.next_bp(9n+r9), 8n) == True{} : Bool}, h)

# The walk
# ========

# the machine where a cell leads: on from a node, a symbol read, no code
def MS(w: D.Wn, +tab: String, +sk: D.SK, +o: D.O, +bp: Nat) -> D.St:
  match w:
    case D.WGo{+n}:
      D.St{D.Walk{n, tab, sk}, o, bp}
    case D.WSym{+sy}:
      D.sym(sk, sy, o, bp)
    case D.WBad{}:
      D.fail(o, bp, D.BadCode{})

def msw.lr(+q: Nat, leaf: Bool, +tab: String, +sk: D.SK, +o: D.O, +bp: Nat) ->
  {MS(D.fi.step.lr(q, leaf), tab, sk, o, bp) == D.walk.lr(tab, q, leaf, sk, o, bp) : D.St}:
  match leaf:
    case True{}:
      {==}
    case False{}:
      {==}

def msw.at(zero: Bool, qr: Nat & Nat, +tab: String, +sk: D.SK, +o: D.O, +bp: Nat) ->
  {MS(D.fi.step.at(zero, qr), tab, sk, o, bp) == D.walk.at(tab, zero, qr, sk, o, bp) : D.St}:
  match zero:
    case True{}:
      {==}
    case False{}:
      match qr:
        case (q, r):
          msw.lr(q, Nat.is_eq(r, 1n), tab, sk, o, bp)

# a cell as the fast walk reads it is the cell as the machine does
def msw(+x: Nat, +tab: String, +sk: D.SK, +o: D.O, +bp: Nat) ->
  {MS(D.fi.step(x), tab, sk, o, bp) == D.walk(tab, x, sk, o, bp) : D.St}:
  msw.at(Nat.is_eq(x, 0n), Nat.divmod(x, 2n), tab, sk, o, bp)

# X is Z, and Z is Y with B beside it: X is Y with B beside it
def pair.tr(-T: Data, +X: T, +Z: T, +Y: T, -B: Type, p: {X == Z : T}, ih: {Z == Y : T} & B) ->
  {X == Y : T} & B:
  (a, b) = ih
  (Equal.trans(T, X, Z, Y, p, a), b)

# what the walk's end says of the machine at X: where it read a symbol,
# X is the machine from there on, at an offset in a byte
def WL.T(w: D.Wk, +s: Bytes(), +sk: D.SK, +o: D.O, +X: D.St) -> Type:
  match w:
    case D.WLeaf{+sy, +q, +r}:
      {X == D.fi.bfeed(R(s, q, r), D.sym(sk, sy, o, r)) : D.St} & {Nat.is_lt(r, 8n) == True{} : Bool}
    case D.WStop{}:
      Unit

def wl.tr(+w: D.Wk, +s: Bytes(), +sk: D.SK, +o: D.O, +X: D.St, +Z: D.St, p: {X == Z : D.St}) ->
  WL.T(w, s, sk, o, Z) -> WL.T(w, s, sk, o, X):
  match w:
    case D.WLeaf{+sy, +q, +r}:
      ih => pair.tr(D.St, X, Z, D.fi.bfeed(R(s, q, r), D.sym(sk, sy, o, r)), {Nat.is_lt(r, 8n) == True{} : Bool},
        p, ih)
    case D.WStop{}:
      ih => Unit{}

def WX(w: D.Wn, +s: Bytes(), +q: Nat, +r: Nat, +tab: String, +sk: D.SK, +o: D.O) -> D.St:
  D.fi.bfeed(R(s, q, r), MS(w, tab, sk, o, r))

# the fast walk is the machine's, bit by bit
def wl(+k: Nat, +w: D.Wn, +ok: Bool, +s: Bytes(), +q: Nat, +r: Nat, +tab: String, +sk: D.SK, +o: D.O) ->
  {D.fi.in(s, q) == ok : Bool} -> {Nat.is_lt(r, 8n) == True{} : Bool} ->
  WL.T(D.fi.walk(k, w, ok, tab, s, q, r), s, sk, o, WX(w, s, q, r, tab, sk, o)):
  match k w ok:
    case 0n D.WSym{+sy} _:
      e => hr => ({==}, hr)
    case 1n+p D.WSym{+sy} _:
      e => hr => ({==}, hr)
    case 0n D.WGo{+n} _:
      e => hr => Unit{}
    case 1n+p D.WGo{+n} False{}:
      e => hr => Unit{}
    case 1n+p D.WGo{+n} True{}:
      e => h0 =>
        +hr = h0
        +b = D.fi.b(s, q, r)
        +q2 = D.fi.nq(q, r)
        +r2 = D.next_bp(r)
        +x = D.fi.cell(tab, n, b)
        +X = WX(D.WGo{n}, s, q, r, tab, sk, o)
        +Z = WX(D.fi.step(x), s, q2, r2, tab, sk, o)
        +xz = Equal.trans(D.St, X, D.fi.bfeed(R(s, q2, r2), D.walk(tab, x, sk, o, r2)), Z,
          rs(s, q, r, D.St{D.Walk{n, tab, sk}, o, r})(e)(hr),
          Equal.cong(D.St, D.St, y => D.fi.bfeed(R(s, q2, r2), y), D.walk(tab, x, sk, o, r2),
            MS(D.fi.step(x), tab, sk, o, r2), Equal.sym(D.St, MS(D.fi.step(x), tab, sk, o, r2),
              D.walk(tab, x, sk, o, r2), msw(x, tab, sk, o, r2))))
        wl.tr(D.fi.walk(p, D.fi.step(x), D.fi.in(s, q2), tab, s, q2, r2), s, sk, o, X, Z, xz)(
          wl(p, D.fi.step(x), D.fi.in(s, q2), s, q2, r2, tab, sk, o)({==})(nb(r)(hr)))
    case 0n D.WBad{} _:
      e => hr => Unit{}
    case 1n+p D.WBad{} _:
      e => hr => Unit{}

# The extra bits
# ==============

def GL.T(g: D.Gt, +s: Bytes(), +kk: D.K, +o: D.O, +X: D.St) -> Type:
  match g:
    case D.Gt{+acc, +q, +r}:
      {X == D.fi.bfeed(R(s, q, r), D.fire(kk, acc, o, r)) : D.St} & {Nat.is_lt(r, 8n) == True{} : Bool}
    case D.GStop{}:
      Unit

def gl.tr(+g: D.Gt, +s: Bytes(), +kk: D.K, +o: D.O, +X: D.St, +Z: D.St, p: {X == Z : D.St}) ->
  GL.T(g, s, kk, o, Z) -> GL.T(g, s, kk, o, X):
  match g:
    case D.Gt{+acc, +q, +r}:
      ih => pair.tr(D.St, X, Z, D.fi.bfeed(R(s, q, r), D.fire(kk, acc, o, r)), {Nat.is_lt(r, 8n) == True{} : Bool},
        p, ih)
    case D.GStop{}:
      ih => Unit{}

def GX(+left: Nat, +acc: List<&2, Bool>, +kk: D.K, +s: Bytes(), +q: Nat, +r: Nat, +o: D.O) -> D.St:
  D.fi.bfeed(R(s, q, r), D.St{D.Get{left, acc, kk}, o, r})

# the fast reader's bits are the machine's Get, bit by bit
def gl(+left: Nat, +acc: List<&2, Bool>, +ok: Bool, +kk: D.K, +s: Bytes(), +q: Nat, +r: Nat, +o: D.O) ->
  {D.fi.in(s, q) == ok : Bool} -> {Nat.is_lt(r, 8n) == True{} : Bool} ->
  GL.T(D.fi.get(1n+left, ok, s, q, r, acc), s, kk, o, GX(left, acc, kk, s, q, r, o)):
  match left ok:
    case _ False{}:
      e => hr => Unit{}
    case 0n True{}:
      e => h0 =>
        +hr = h0
        (rs(s, q, r, D.St{D.Get{0n, acc, kk}, o, r})(e)(hr), nb(r)(hr))
    case 1n+p True{}:
      e => h0 =>
        +hr = h0
        +b = D.fi.b(s, q, r)
        +q2 = D.fi.nq(q, r)
        +r2 = D.next_bp(r)
        gl.tr(D.fi.get(1n+p, D.fi.in(s, q2), s, q2, r2, Con{b, acc}), s, kk, o, GX(1n+p, acc, kk, s, q, r, o),
          GX(p, Con{b, acc}, kk, s, q2, r2, o), rs(s, q, r, D.St{D.Get{1n+p, acc, kk}, o, r})(e)(hr))(
          gl(p, Con{b, acc}, D.fi.in(s, q2), kk, s, q2, r2, o)({==})(nb(r)(hr)))

# The copy
# ========

def cp(+len: Nat, +out: Bytes(), +dist: Nat) -> {D.fi.copy(len, out, dist) == D.copy.go(len, out, dist) : Bytes()}:
  match len:
    case 0n:
      {==}
    case 1n+p:
      cp(p, Bytes.push(out, Bytes.get(out, Nat.sub(Bytes.len(out), dist))), dist)


# The symbols
# ===========
#
# Each step of a symbol, as the fast path reads it, is the machine's:
# given X is the machine at that step, X is the machine after the whole
# symbol wherever the fast path read one. The block, the output and the
# tables are the context every lemma takes.

def RD.T(dc: D.Dc, +s: Bytes(), +last: Bool, +ll: String, +d: String, +out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St) -> Type:
  match dc:
    case D.DLit{+c, +q, +r}:
      {X == D.fi.bfeed(R(s, q, r), D.St{D.lit_mode(D.Blk{last, ll, d}), D.O{Bytes.push(out, U32.from_nat(c)), keep, 1n+n, cap, D.Tabs{fll, fd, lb, lx, db, dx}},
        r}) : D.St} & {Nat.is_lt(r, 8n) == True{} : Bool}
    case D.DCopy{+len, +dist, +q, +r}:
      {X == D.fi.bfeed(R(s, q, r), D.St{D.lit_mode(D.Blk{last, ll, d}), D.O{D.fi.copy(len, out, dist), keep, Nat.add(n, len), cap,
        D.Tabs{fll, fd, lb, lx, db, dx}}, r}) : D.St} & {Nat.is_lt(r, 8n) == True{} : Bool}
    case D.DStop{}:
      Unit

def cpy.at(+far: Bool, +big: Bool, +len: Nat, +dist: Nat, +q: Nat, +r: Nat, +s: Bytes(), +last: Bool, +ll: String, +d: String, +out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St) ->
  {X == D.fi.bfeed(R(s, q, r), D.copy.if(far, big, out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}, len, dist, D.lit_mode(D.Blk{last, ll, d}), r)) : D.St} ->
  {Nat.is_lt(r, 8n) == True{} : Bool} -> RD.T(D.fi.cp(far, big, len, dist, q, r), s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X):
  match far big:
    case False{} False{}:
      hX => hr => (Equal.trans(D.St, X,
        D.fi.bfeed(R(s, q, r), D.St{D.lit_mode(D.Blk{last, ll, d}), D.O{D.copy.go(len, out, dist), keep, Nat.add(n, len), cap, D.Tabs{fll, fd, lb, lx, db, dx}}, r}),
        D.fi.bfeed(R(s, q, r), D.St{D.lit_mode(D.Blk{last, ll, d}), D.O{D.fi.copy(len, out, dist), keep, Nat.add(n, len), cap, D.Tabs{fll, fd, lb, lx, db, dx}}, r}),
        hX, Equal.cong(Bytes(), D.St, y => D.fi.bfeed(R(s, q, r), D.St{D.lit_mode(D.Blk{last, ll, d}), D.O{y, keep, Nat.add(n, len), cap,
          D.Tabs{fll, fd, lb, lx, db, dx}}, r}), D.copy.go(len, out, dist), D.fi.copy(len, out, dist),
          Equal.sym(Bytes(), D.fi.copy(len, out, dist), D.copy.go(len, out, dist), cp(len, out, dist)))), hr)
    case False{} True{}:
      hX => hr => Unit{}
    case True{} _:
      hX => hr => Unit{}

def cpy(+len: Nat, +dist: Nat, +q: Nat, +r: Nat, +s: Bytes(), +last: Bool, +ll: String, +d: String, +out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St,
  hX: {X == D.fi.bfeed(R(s, q, r), D.copy(D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}, len, dist, D.lit_mode(D.Blk{last, ll, d}), r)) : D.St}, hr: {Nat.is_lt(r, 8n) == True{} : Bool}) ->
  RD.T(D.fi.copy.ok(len, dist, q, r, Bytes.len(out), n, cap), s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X):
  cpy.at(Nat.is_lt(Bytes.len(out), dist), Nat.is_lt(cap, Nat.add(n, len)), len, dist, q, r, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X)(hX)(hr)

def dg.leaf(+acc: List<&2, Bool>, +q: Nat, +r: Nat, +len: Nat, +base: Nat, +s: Bytes(), +last: Bool, +ll: String, +d: String, +out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St,
  h: {X == D.fi.bfeed(R(s, q, r), D.fire(D.KDistX{D.Blk{last, ll, d}, len, base}, acc, D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}, r)) : D.St} & {Nat.is_lt(r, 8n) == True{} : Bool}) ->
  RD.T(D.fi.copy.ok(len, Nat.add(base, D.hval(acc, 0n)), q, r, Bytes.len(out), n, cap), s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X):
  (a, b) = h
  cpy(len, Nat.add(base, D.hval(acc, 0n)), q, r, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X, a, b)

def dg(+g: D.Gt, +len: Nat, +base: Nat, +s: Bytes(), +last: Bool, +ll: String, +d: String, +out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St) ->
  GL.T(g, s, D.KDistX{D.Blk{last, ll, d}, len, base}, D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}, X) -> RD.T(D.fi.dist.g(g, len, base, Bytes.len(out), n, cap), s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X):
  match g:
    case D.Gt{+acc, +q, +r}:
      h => dg.leaf(acc, q, r, len, base, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X, h)
    case D.GStop{}:
      h => Unit{}

def dxl(+x: Nat, +base: Nat, +len: Nat, +q: Nat, +r: Nat, +s: Bytes(), +last: Bool, +ll: String, +d: String, +out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St) ->
  {X == D.fi.bfeed(R(s, q, r), D.dist_x(D.Blk{last, ll, d}, len, base, x, D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}, r)) : D.St} -> {Nat.is_lt(r, 8n) == True{} : Bool} ->
  RD.T(D.fi.dist_x(x, base, s, len, q, r, Bytes.len(out), n, cap), s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X):
  match x:
    case 0n:
      hX => hr => cpy(len, base, q, r, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X, hX, hr)
    case 1n+p:
      hX => hr => dg(D.fi.get(1n+p, D.fi.in(s, q), s, q, r, Nil{}), len, base, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X)(
        gl.tr(D.fi.get(1n+p, D.fi.in(s, q), s, q, r, Nil{}), s, D.KDistX{D.Blk{last, ll, d}, len, base}, D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}, X,
          GX(p, Nil{}, D.KDistX{D.Blk{last, ll, d}, len, base}, s, q, r, D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}), hX)(
          gl(p, Nil{}, D.fi.in(s, q), D.KDistX{D.Blk{last, ll, d}, len, base}, s, q, r, D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}})({==})(hr)))

def dd(+ok: Bool, +ds: Nat, +len: Nat, +q: Nat, +r: Nat, +s: Bytes(), +last: Bool, +ll: String, +d: String, +out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St) ->
  {X == D.fi.bfeed(R(s, q, r), D.dist(ok, D.Blk{last, ll, d}, len, ds, D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}, r)) : D.St} -> {Nat.is_lt(r, 8n) == True{} : Bool} ->
  RD.T(D.fi.dist(ok, ds, s, len, q, r, db, dx, Bytes.len(out), n, cap), s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X):
  match ok:
    case True{}:
      hX => hr => dxl(D.fi.at(dx, ds), D.fi.at(db, ds), len, q, r, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X)(hX)(hr)
    case False{}:
      hX => hr => Unit{}

def ds.leaf(+ds: Nat, +q: Nat, +r: Nat, +len: Nat, +s: Bytes(), +last: Bool, +ll: String, +d: String, +out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St,
  h: {X == D.fi.bfeed(R(s, q, r), D.sym(D.SDist{D.Blk{last, ll, d}, len}, ds, D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}, r)) : D.St} & {Nat.is_lt(r, 8n) == True{} : Bool}) ->
  RD.T(D.fi.dist(Nat.is_lt(ds, 30n), ds, s, len, q, r, db, dx, Bytes.len(out), n, cap), s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X):
  (a, b) = h
  dd(Nat.is_lt(ds, 30n), ds, len, q, r, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X)(a)(b)

def dsy(+w: D.Wk, +len: Nat, +s: Bytes(), +last: Bool, +ll: String, +d: String, +out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St) ->
  WL.T(w, s, D.SDist{D.Blk{last, ll, d}, len}, D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}, X) -> RD.T(D.fi.dsym(w, s, len, db, dx, Bytes.len(out), n, cap), s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X):
  match w:
    case D.WLeaf{+ds, +q, +r}:
      h => ds.leaf(ds, q, r, len, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X, h)
    case D.WStop{}:
      h => Unit{}

def dw(+len: Nat, +q: Nat, +r: Nat, +s: Bytes(), +last: Bool, +ll: String, +d: String, +out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St,
  hX: {X == D.fi.bfeed(R(s, q, r), D.St{D.dist_mode(D.Blk{last, ll, d}, len), D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}, r}) : D.St}, hr: {Nat.is_lt(r, 8n) == True{} : Bool}) ->
  RD.T(D.fi.dwalk(len, s, q, r, d, db, dx, Bytes.len(out), n, cap), s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X):
  +w = D.fi.walk(16n, D.WGo{0n}, D.fi.in(s, q), d, s, q, r)
  dsy(w, len, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X)(wl.tr(w, s, D.SDist{D.Blk{last, ll, d}, len}, D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}, X, WX(D.WGo{0n}, s, q, r, d, D.SDist{D.Blk{last, ll, d}, len},
    D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}), hX)(wl(16n, D.WGo{0n}, D.fi.in(s, q), s, q, r, d, D.SDist{D.Blk{last, ll, d}, len}, D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}})({==})(hr)))

def lg.leaf(+acc: List<&2, Bool>, +q: Nat, +r: Nat, +base: Nat, +s: Bytes(), +last: Bool, +ll: String, +d: String, +out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St,
  h: {X == D.fi.bfeed(R(s, q, r), D.fire(D.KLenX{D.Blk{last, ll, d}, base}, acc, D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}, r)) : D.St} & {Nat.is_lt(r, 8n) == True{} : Bool}) ->
  RD.T(D.fi.dwalk(Nat.add(base, D.hval(acc, 0n)), s, q, r, d, db, dx, Bytes.len(out), n, cap), s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X):
  (a, b) = h
  dw(Nat.add(base, D.hval(acc, 0n)), q, r, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X, a, b)

def lg(+g: D.Gt, +base: Nat, +s: Bytes(), +last: Bool, +ll: String, +d: String, +out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St) ->
  GL.T(g, s, D.KLenX{D.Blk{last, ll, d}, base}, D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}, X) -> RD.T(D.fi.len.g(g, base, s, d, db, dx, Bytes.len(out), n, cap), s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X):
  match g:
    case D.Gt{+acc, +q, +r}:
      h => lg.leaf(acc, q, r, base, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X, h)
    case D.GStop{}:
      h => Unit{}

def lxl(+x: Nat, +base: Nat, +q: Nat, +r: Nat, +s: Bytes(), +last: Bool, +ll: String, +d: String, +out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St) ->
  {X == D.fi.bfeed(R(s, q, r), D.len_x(D.Blk{last, ll, d}, base, x, D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}, r)) : D.St} -> {Nat.is_lt(r, 8n) == True{} : Bool} ->
  RD.T(D.fi.len_x(x, base, s, q, r, d, db, dx, Bytes.len(out), n, cap), s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X):
  match x:
    case 0n:
      hX => hr => dw(base, q, r, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X, hX, hr)
    case 1n+p:
      hX => hr => lg(D.fi.get(1n+p, D.fi.in(s, q), s, q, r, Nil{}), base, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X)(
        gl.tr(D.fi.get(1n+p, D.fi.in(s, q), s, q, r, Nil{}), s, D.KLenX{D.Blk{last, ll, d}, base}, D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}, X,
          GX(p, Nil{}, D.KLenX{D.Blk{last, ll, d}, base}, s, q, r, D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}), hX)(
          gl(p, Nil{}, D.fi.in(s, q), D.KLenX{D.Blk{last, ll, d}, base}, s, q, r, D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}})({==})(hr)))

def lc(+ok: Bool, +i: Nat, +q: Nat, +r: Nat, +s: Bytes(), +last: Bool, +ll: String, +d: String, +out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St) ->
  {X == D.fi.bfeed(R(s, q, r), D.lit.c(ok, D.Blk{last, ll, d}, i, D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}, r)) : D.St} -> {Nat.is_lt(r, 8n) == True{} : Bool} ->
  RD.T(D.fi.lit.c(ok, i, s, q, r, d, lb, lx, db, dx, Bytes.len(out), n, cap), s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X):
  match ok:
    case True{}:
      hX => hr => lxl(D.fi.at(lx, i), D.fi.at(lb, i), q, r, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X)(hX)(hr)
    case False{}:
      hX => hr => Unit{}

def lbq(+eob: Bool, +sy: Nat, +q: Nat, +r: Nat, +s: Bytes(), +last: Bool, +ll: String, +d: String, +out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St) ->
  {X == D.fi.bfeed(R(s, q, r), D.lit.b(eob, D.Blk{last, ll, d}, sy, D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}, r)) : D.St} -> {Nat.is_lt(r, 8n) == True{} : Bool} ->
  RD.T(D.fi.lit.b(eob, sy, s, q, r, d, lb, lx, db, dx, Bytes.len(out), n, cap), s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X):
  match eob:
    case True{}:
      hX => hr => Unit{}
    case False{}:
      hX => hr => lc(Nat.is_lt(sy, U32.to_nat(286)), Nat.sub(sy, U32.to_nat(257)), q, r, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X)(hX)(hr)

def em(+ok: Bool, +sy: Nat, +q: Nat, +r: Nat, +s: Bytes(), +last: Bool, +ll: String, +d: String, +out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St) ->
  {X == D.fi.bfeed(R(s, q, r), D.emit.if(ok, out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}, U32.from_nat(sy), D.lit_mode(D.Blk{last, ll, d}), r)) : D.St} ->
  {Nat.is_lt(r, 8n) == True{} : Bool} -> RD.T(D.fi.emit(ok, sy, q, r), s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X):
  match ok:
    case True{}:
      hX => hr => (hX, hr)
    case False{}:
      hX => hr => Unit{}

def li(+il: Bool, +sy: Nat, +q: Nat, +r: Nat, +s: Bytes(), +last: Bool, +ll: String, +d: String, +out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St) ->
  {X == D.fi.bfeed(R(s, q, r), D.lit(il, D.Blk{last, ll, d}, sy, D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}, r)) : D.St} -> {Nat.is_lt(r, 8n) == True{} : Bool} ->
  RD.T(D.fi.lit(il, sy, s, q, r, d, lb, lx, db, dx, Bytes.len(out), n, cap), s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X):
  match il:
    case True{}:
      hX => hr => em(Nat.is_lt(n, cap), sy, q, r, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X)(hX)(hr)
    case False{}:
      hX => hr => lbq(Nat.is_eq(sy, 256n), sy, q, r, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X)(hX)(hr)

def ls.leaf(+sy: Nat, +q: Nat, +r: Nat, +s: Bytes(), +last: Bool, +ll: String, +d: String, +out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St,
  h: {X == D.fi.bfeed(R(s, q, r), D.sym(D.SLit{D.Blk{last, ll, d}}, sy, D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}, r)) : D.St} & {Nat.is_lt(r, 8n) == True{} : Bool}) ->
  RD.T(D.fi.lit(Nat.is_lt(sy, 256n), sy, s, q, r, d, lb, lx, db, dx, Bytes.len(out), n, cap), s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X):
  (a, b) = h
  li(Nat.is_lt(sy, 256n), sy, q, r, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X)(a)(b)

def lsy(+w: D.Wk, +s: Bytes(), +last: Bool, +ll: String, +d: String, +out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St) ->
  WL.T(w, s, D.SLit{D.Blk{last, ll, d}}, D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}, X) -> RD.T(D.fi.lsym(w, s, d, lb, lx, db, dx, Bytes.len(out), n, cap), s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X):
  match w:
    case D.WLeaf{+sy, +q, +r}:
      h => ls.leaf(sy, q, r, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X, h)
    case D.WStop{}:
      h => Unit{}

def DX(+q: Nat, +r: Nat, +tab: String, +s: Bytes(), +last: Bool, +ll: String, +d: String, +out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String) -> D.St:
  D.fi.bfeed(R(s, q, r), D.St{D.Walk{0n, tab, D.SLit{D.Blk{last, ll, d}}}, D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}, r})

# a symbol read whole is the machine's, bit by bit
def dec(+q: Nat, +r: Nat, +tab: String, +s: Bytes(), +last: Bool, +ll: String, +d: String, +out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, hr: {Nat.is_lt(r, 8n) == True{} : Bool}) ->
  RD.T(D.fi.dec(s, q, r, tab, d, lb, lx, db, dx, Bytes.len(out), n, cap), s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, DX(q, r, tab, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx)):
  lsy(D.fi.walk(16n, D.WGo{0n}, D.fi.in(s, q), tab, s, q, r), s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, DX(q, r, tab, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx))(
    wl(16n, D.WGo{0n}, D.fi.in(s, q), s, q, r, tab, D.SLit{D.Blk{last, ll, d}}, D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}})({==})(hr))

def rd.tr(+dc: D.Dc, +s: Bytes(), +last: Bool, +ll: String, +d: String, +out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St, +Z: D.St, p: {X == Z : D.St}) ->
  RD.T(dc, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, Z) -> RD.T(dc, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X):
  match dc:
    case D.DLit{+c, +q, +r}:
      ih => pair.tr(D.St, X, Z, D.fi.bfeed(R(s, q, r), D.St{D.lit_mode(D.Blk{last, ll, d}), D.O{Bytes.push(out, U32.from_nat(c)), keep, 1n+n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}, r}), {Nat.is_lt(r, 8n) == True{} : Bool}, p, ih)
    case D.DCopy{+len, +dist, +q, +r}:
      ih => pair.tr(D.St, X, Z, D.fi.bfeed(R(s, q, r), D.St{D.lit_mode(D.Blk{last, ll, d}), D.O{D.fi.copy(len, out, dist), keep, Nat.add(n, len), cap, D.Tabs{fll, fd, lb, lx, db, dx}}, r}), {Nat.is_lt(r, 8n) == True{} : Bool}, p, ih)
    case D.DStop{}:
      ih => Unit{}

# The run
# =======

def RF.T(f: D.Fr, +s: Bytes(), +last: Bool, +ll: String, +d: String, +keep: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St) -> Type:
  match f:
    case D.Fr{+q, +r, +out, +n}:
      {X == D.fi.bfeed(R(s, q, r), D.St{D.lit_mode(D.Blk{last, ll, d}), D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}, r}) : D.St} & {Nat.is_lt(r, 8n) == True{} : Bool}

def LTT(+r: Nat) -> Type:
  {Nat.is_lt(r, 8n) == True{} : Bool}

def EQS(+X: D.St, +Y: D.St) -> Type:
  {X == Y : D.St}

# what the run carries: the next symbol read whole, and X the machine
# here, at an offset in a byte
def RN.H(dc: D.Dc, +q: Nat, +r: Nat, +out: Bytes(), +n: Nat, +s: Bytes(), +last: Bool, +ll: String, +d: String, +keep: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St) -> Type:
  RD.T(dc, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X) & ({X == D.fi.bfeed(R(s, q, r), D.St{D.lit_mode(D.Blk{last, ll, d}), D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}, r}) : D.St} & {Nat.is_lt(r, 8n) == True{} : Bool})

def rn.end(+dc: D.Dc, +q: Nat, +r: Nat, +out: Bytes(), +n: Nat, +s: Bytes(), +last: Bool, +ll: String, +d: String, +keep: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St,
  h: RN.H(dc, q, r, out, n, s, last, ll, d, keep, cap, fll, fd, lb, lx, db, dx, X)) -> {X == D.fi.bfeed(R(s, q, r), D.St{D.lit_mode(D.Blk{last, ll, d}), D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}, r}) : D.St} & {Nat.is_lt(r, 8n) == True{} : Bool}:
  (x, y) = h
  y

def rn.fst(+dc: D.Dc, +q: Nat, +r: Nat, +out: Bytes(), +n: Nat, +s: Bytes(), +last: Bool, +ll: String, +d: String, +keep: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St,
  h: RN.H(dc, q, r, out, n, s, last, ll, d, keep, cap, fll, fd, lb, lx, db, dx, X)) -> RD.T(dc, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X):
  (x, y) = h
  x

def rn.lit(+c: Nat, +q2: Nat, +r2: Nat, +out: Bytes(), +n: Nat, +s: Bytes(), +last: Bool, +ll: String, +d: String, +keep: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St,
  h: RD.T(D.DLit{c, q2, r2}, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X)) ->
  RN.H(D.fi.dec(s, q2, r2, ll, d, lb, lx, db, dx, Bytes.len(Bytes.push(out, U32.from_nat(c))), 1n+n, cap), q2, r2,
    Bytes.push(out, U32.from_nat(c)), 1n+n, s, last, ll, d, keep, cap, fll, fd, lb, lx, db, dx, X):
  (a0, b0) = h
  +a = a0
  +b = b0
  +o2 = Bytes.push(out, U32.from_nat(c))
  (rd.tr(D.fi.dec(s, q2, r2, ll, d, lb, lx, db, dx, Bytes.len(o2), 1n+n, cap), s, last, ll, d, o2, keep, 1n+n, cap, fll, fd, lb, lx, db, dx, X,
    DX(q2, r2, ll, s, last, ll, d, o2, keep, 1n+n, cap, fll, fd, lb, lx, db, dx), a)(dec(q2, r2, ll, s, last, ll, d, o2, keep, 1n+n, cap, fll, fd, lb, lx, db, dx, b)), (a, b))

def rn.copy(+len: Nat, +dist: Nat, +q2: Nat, +r2: Nat, +out: Bytes(), +n: Nat, +s: Bytes(), +last: Bool, +ll: String, +d: String, +keep: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St,
  h: RD.T(D.DCopy{len, dist, q2, r2}, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X)) ->
  RN.H(D.fi.dec(s, q2, r2, ll, d, lb, lx, db, dx, Bytes.len(D.fi.copy(len, out, dist)), Nat.add(n, len), cap),
    q2, r2, D.fi.copy(len, out, dist), Nat.add(n, len), s, last, ll, d, keep, cap, fll, fd, lb, lx, db, dx, X):
  (a0, b0) = h
  +a = a0
  +b = b0
  +o2 = D.fi.copy(len, out, dist)
  (rd.tr(D.fi.dec(s, q2, r2, ll, d, lb, lx, db, dx, Bytes.len(o2), Nat.add(n, len), cap),
    s, last, ll, d, o2, keep, Nat.add(n, len), cap, fll, fd, lb, lx, db, dx, X, DX(q2, r2, ll, s, last, ll, d, o2, keep, Nat.add(n, len), cap, fll, fd, lb, lx, db, dx), a)(
    dec(q2, r2, ll, s, last, ll, d, o2, keep, Nat.add(n, len), cap, fll, fd, lb, lx, db, dx, b)), (a, b))

# symbols read whole, one after another, are the machine's
def rn(+k: Nat, +dc: D.Dc, +q: Nat, +r: Nat, +out: Bytes(), +n: Nat, +s: Bytes(), +last: Bool, +ll: String, +d: String, +keep: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St) ->
  RN.H(dc, q, r, out, n, s, last, ll, d, keep, cap, fll, fd, lb, lx, db, dx, X) ->
  RF.T(D.fi.run(k, dc, s, ll, d, lb, lx, db, dx, q, r, out, n, cap), s, last, ll, d, keep, cap, fll, fd, lb, lx, db, dx, X):
  match k dc:
    case 0n _:
      h => rn.end(dc, q, r, out, n, s, last, ll, d, keep, cap, fll, fd, lb, lx, db, dx, X, h)
    case 1n+p D.DStop{}:
      h => rn.end(D.DStop{}, q, r, out, n, s, last, ll, d, keep, cap, fll, fd, lb, lx, db, dx, X, h)
    case 1n+p D.DLit{+c, +q2, +r2}:
      h => rn(p, D.fi.dec(s, q2, r2, ll, d, lb, lx, db, dx, Bytes.len(Bytes.push(out, U32.from_nat(c))), 1n+n, cap),
        q2, r2, Bytes.push(out, U32.from_nat(c)), 1n+n, s, last, ll, d, keep, cap, fll, fd, lb, lx, db, dx, X)(rn.lit(c, q2, r2, out, n, s, last, ll, d, keep, cap, fll, fd, lb, lx, db, dx, X,
          rn.fst(D.DLit{c, q2, r2}, q, r, out, n, s, last, ll, d, keep, cap, fll, fd, lb, lx, db, dx, X, h)))
    case 1n+p D.DCopy{+len, +dist, +q2, +r2}:
      h => rn(p, D.fi.dec(s, q2, r2, ll, d, lb, lx, db, dx, Bytes.len(D.fi.copy(len, out, dist)), Nat.add(n, len),
        cap), q2, r2, D.fi.copy(len, out, dist), Nat.add(n, len), s, last, ll, d, keep, cap, fll, fd, lb, lx, db, dx, X)(
        rn.copy(len, dist, q2, r2, out, n, s, last, ll, d, keep, cap, fll, fd, lb, lx, db, dx, X, rn.fst(D.DCopy{len, dist, q2, r2}, q, r, out, n, s, last, ll, d, keep, cap, fll, fd, lb, lx, db, dx, X, h)))

# The driver
# ==========

# where the driver is: the input goes on as go says, at an offset in a
# byte, and X is the machine from there on
def NV.T(v: D.Dv, +s: Bytes(), +X: D.St) -> Type:
  match v:
    case D.Dv{+q, +r, +st, +go}:
      {D.fi.in(s, q) == go : Bool} & ({Nat.is_lt(r, 8n) == True{} : Bool} & {X == D.fi.bfeed(R(s, q, r), st) : D.St})

def bit(+s: Bytes(), +q: Nat, +r: Nat, +st: D.St, +X: D.St, e: {D.fi.in(s, q) == True{} : Bool}, +hr: {Nat.is_lt(r, 8n) == True{} : Bool},
  hX: {X == D.fi.bfeed(R(s, q, r), st) : D.St}) -> NV.T(D.fi.bit(s, q, r, st), s, X):
  ({==}, (nb(r)(hr), Equal.trans(D.St, X, D.fi.bfeed(R(s, q, r), st),
    D.fi.bfeed(R(s, D.fi.nq(q, r), D.next_bp(r)), D.bstep(st, D.fi.b(s, q, r))), hX, rs(s, q, r, st)(e)(hr))))

def fr.at(+q: Nat, +r: Nat, +out: Bytes(), +n: Nat, +s: Bytes(), +last: Bool, +ll: String, +d: String, +keep: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St,
  h: {X == D.fi.bfeed(R(s, q, r), D.St{D.lit_mode(D.Blk{last, ll, d}), D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}, r}) : D.St} & {Nat.is_lt(r, 8n) == True{} : Bool}) ->
  NV.T(D.fi.fr(D.Fr{q, r, out, n}, s, last, ll, d, keep, cap, D.Tabs{fll, fd, lb, lx, db, dx}), s, X):
  (a, b) = h
  ({==}, (b, a))

def fr(+f: D.Fr, +s: Bytes(), +last: Bool, +ll: String, +d: String, +keep: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St) -> RF.T(f, s, last, ll, d, keep, cap, fll, fd, lb, lx, db, dx, X) ->
  NV.T(D.fi.fr(f, s, last, ll, d, keep, cap, D.Tabs{fll, fd, lb, lx, db, dx}), s, X):
  match f:
    case D.Fr{+q, +r, +out, +n}:
      h => fr.at(q, r, out, n, s, last, ll, d, keep, cap, fll, fd, lb, lx, db, dx, X, h)

def WS(+q: Nat, +r: Nat, +tab: String, +s: Bytes(), +last: Bool, +ll: String, +d: String, +out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String) -> D.St:
  D.St{D.Walk{0n, tab, D.SLit{D.Blk{last, ll, d}}}, D.O{out, keep, n, cap, D.Tabs{fll, fd, lb, lx, db, dx}}, r}

def first(+dc: D.Dc, +q: Nat, +r: Nat, +tab: String, +s: Bytes(), +last: Bool, +ll: String, +d: String, +out: Bytes(), +keep: Nat, +n: Nat, +cap: Nat, +fll: String, +fd: String, +lb: String, +lx: String, +db: String, +dx: String, +X: D.St) ->
  RD.T(dc, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X) -> {X == D.fi.bfeed(R(s, q, r), WS(q, r, tab, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx)) : D.St} ->
  {D.fi.in(s, q) == True{} : Bool} -> {Nat.is_lt(r, 8n) == True{} : Bool} ->
  NV.T(D.fi.first(dc, s, q, r, tab, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx), s, X):
  match dc:
    case D.DStop{}:
      h => hX => e => hr => bit(s, q, r, WS(q, r, tab, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx), X, e, hr, hX)
    case D.DLit{+c, +q2, +r2}:
      h => hX => e => hr =>
        fr(D.fi.run(Bytes.len(s), D.fi.dec(s, q2, r2, ll, d, lb, lx, db, dx, Bytes.len(Bytes.push(out, U32.from_nat(c))),
          1n+n, cap), s, ll, d, lb, lx, db, dx, q2, r2, Bytes.push(out, U32.from_nat(c)), 1n+n, cap), s, last, ll, d, keep, cap, fll, fd, lb, lx, db, dx, X)(
          rn(Bytes.len(s), D.fi.dec(s, q2, r2, ll, d, lb, lx, db, dx, Bytes.len(Bytes.push(out, U32.from_nat(c))), 1n+n,
            cap), q2, r2, Bytes.push(out, U32.from_nat(c)), 1n+n, s, last, ll, d, keep, cap, fll, fd, lb, lx, db, dx, X)(rn.lit(c, q2, r2, out, n, s, last, ll, d, keep, cap, fll, fd, lb, lx, db, dx, X, h)))
    case D.DCopy{+len, +dist, +q2, +r2}:
      h => hX => e => hr =>
        fr(D.fi.run(Bytes.len(s), D.fi.dec(s, q2, r2, ll, d, lb, lx, db, dx, Bytes.len(D.fi.copy(len, out, dist)),
          Nat.add(n, len), cap), s, ll, d, lb, lx, db, dx, q2, r2, D.fi.copy(len, out, dist), Nat.add(n, len), cap),
          s, last, ll, d, keep, cap, fll, fd, lb, lx, db, dx, X)(
          rn(Bytes.len(s), D.fi.dec(s, q2, r2, ll, d, lb, lx, db, dx, Bytes.len(D.fi.copy(len, out, dist)),
            Nat.add(n, len), cap), q2, r2, D.fi.copy(len, out, dist), Nat.add(n, len), s, last, ll, d, keep, cap, fll, fd, lb, lx, db, dx, X)(
            rn.copy(len, dist, q2, r2, out, n, s, last, ll, d, keep, cap, fll, fd, lb, lx, db, dx, X, h)))

def fast(+s: Bytes(), +q: Nat, +r: Nat, +tab: String, +last: Bool, +ll: String, +d: String, +o: D.O,
  +X: D.St) -> {X == D.fi.bfeed(R(s, q, r), D.St{D.Walk{0n, tab, D.SLit{D.Blk{last, ll, d}}}, o, r}) : D.St} ->
  {D.fi.in(s, q) == True{} : Bool} -> {Nat.is_lt(r, 8n) == True{} : Bool} -> NV.T(D.fi.fast(s, q, r, tab, last, ll, d, o), s, X):
  match o:
    case D.O{+out, +keep, +n, +cap, +t}:
      match t:
        case D.Tabs{+fll, +fd, +lb, +lx, +db, +dx}:
          hX0 => e => h0 =>
            +hr = h0
            +hX = hX0
            first(D.fi.dec(s, q, r, tab, d, lb, lx, db, dx, Bytes.len(out), n, cap), q, r, tab, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X)(
              rd.tr(D.fi.dec(s, q, r, tab, d, lb, lx, db, dx, Bytes.len(out), n, cap), s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, X, DX(q, r, tab, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx),
                hX)(dec(q, r, tab, s, last, ll, d, out, keep, n, cap, fll, fd, lb, lx, db, dx, hr)))(hX)(e)(hr)

def eqn(+a: Nat, +b: Nat) -> {Nat.is_eq(a, b) == True{} : Bool} -> {a == b : Nat}:
  match a b:
    case 0n 0n:
      e => {==}
    case 0n 1n+q:
      e => Bool.no({0n == 1n+q : Nat}, e)
    case 1n+p 0n:
      e => Bool.no({1n+p == 0n : Nat}, e)
    case 1n+p 1n+q:
      e => Equal.cong(Nat, Nat, x => 1n+x, p, q, eqn(p, q)(e))

def atbp(+same: Bool, +s: Bytes(), +q: Nat, +r: Nat, +tab: String, +last: Bool, +ll: String, +d: String,
  +o: D.O, +bp: Nat, +X: D.St) -> {Nat.is_eq(bp, r) == same : Bool} ->
  {X == D.fi.bfeed(R(s, q, r), D.St{D.Walk{0n, tab, D.SLit{D.Blk{last, ll, d}}}, o, bp}) : D.St} ->
  {D.fi.in(s, q) == True{} : Bool} -> {Nat.is_lt(r, 8n) == True{} : Bool} ->
  NV.T(D.fi.at.bp(same, s, q, r, tab, last, ll, d, o, bp), s, X):
  match same:
    case True{}:
      hs => hX => e => hr => fast(s, q, r, tab, last, ll, d, o, X)(Equal.trans(D.St, X,
        D.fi.bfeed(R(s, q, r), D.St{D.Walk{0n, tab, D.SLit{D.Blk{last, ll, d}}}, o, bp}),
        D.fi.bfeed(R(s, q, r), D.St{D.Walk{0n, tab, D.SLit{D.Blk{last, ll, d}}}, o, r}), hX,
        Equal.cong(Nat, D.St, y => D.fi.bfeed(R(s, q, r), D.St{D.Walk{0n, tab, D.SLit{D.Blk{last, ll, d}}}, o, y}), bp, r,
          eqn(bp, r)(hs))))(e)(hr)
    case False{}:
      hs => hX => e => hr => bit(s, q, r, D.St{D.Walk{0n, tab, D.SLit{D.Blk{last, ll, d}}}, o, bp}, X, e, hr, hX)

# a step of the driver: the fast path, or a bit
def node(+s: Bytes(), +q: Nat, +r: Nat, +st: D.St, +X: D.St) ->
  {X == D.fi.bfeed(R(s, q, r), st) : D.St} -> {D.fi.in(s, q) == True{} : Bool} -> {Nat.is_lt(r, 8n) == True{} : Bool} ->
  NV.T(D.fi.node(s, q, r, st), s, X):
  match st:
    case D.St{+m, +o, +bp}:
      match m:
        case D.Walk{+nd, +tab, +sk}:
          match nd sk:
            case 0n D.SLit{+blk}:
              match blk:
                case D.Blk{+last, +ll, +d}:
                  hX => e => hr => atbp(Nat.is_eq(bp, r), s, q, r, tab, last, ll, d, o, bp, X)({==})(hX)(e)(hr)
            case 0n D.SDist{+blk, +len}:
              hX => e => hr => bit(s, q, r, D.St{D.Walk{0n, tab, D.SDist{blk, len}}, o, bp}, X, e, hr, hX)
            case 0n D.SCl{+h}:
              hX => e => hr => bit(s, q, r, D.St{D.Walk{0n, tab, D.SCl{h}}, o, bp}, X, e, hr, hX)
            case 1n+p _:
              hX => e => hr => bit(s, q, r, D.St{D.Walk{1n+p, tab, sk}, o, bp}, X, e, hr, hX)
        case D.Get{+left, +acc, +k}:
          hX => e => hr => bit(s, q, r, D.St{D.Get{left, acc, k}, o, bp}, X, e, hr, hX)
        case D.Skip{+last}:
          hX => e => hr => bit(s, q, r, D.St{D.Skip{last}, o, bp}, X, e, hr, hX)
        case D.End{}:
          hX => e => hr => bit(s, q, r, D.St{D.End{}, o, bp}, X, e, hr, hX)
        case D.Bad{+why}:
          hX => e => hr => bit(s, q, r, D.St{D.Bad{why}, o, bp}, X, e, hr, hX)

# past the input there is nothing to read
def dq_nil(+s: Bytes(), +q: Nat) -> {D.fi.in(s, q) == False{} : Bool} -> {Bytes.drop(s, q) == SNil{} : Bytes()}:
  match s q:
    case SNil{} _:
      e => {==}
    case SCon{+h, +u} 0n:
      e => Bool.no({Bytes.drop(SCon{h, u}, 0n) == SNil{} : Bytes()}, Equal.sym(Bool, True{}, False{},
        Equal.trans(Bool, Nat.is_lt(0n, 1n+String.length.go(u, 0n)), Nat.is_lt(0n, String.length.go(u, 1n)), False{},
          Equal.cong(Nat, Bool, x => Nat.is_lt(0n, x), 1n+String.length.go(u, 0n), String.length.go(u, 1n),
            Equal.sym(Nat, String.length.go(u, 1n), 1n+String.length.go(u, 0n), Bytes.len.shift(u, 0n))), e)))
    case SCon{+h, +u} 1n+p:
      e => dq_nil(u, p)(Equal.trans(Bool, Nat.is_lt(1n+p, 1n+String.length.go(u, 0n)),
        Nat.is_lt(1n+p, String.length.go(u, 1n)), False{},
        Equal.cong(Nat, Bool, x => Nat.is_lt(1n+p, x), 1n+String.length.go(u, 0n), String.length.go(u, 1n),
          Equal.sym(Nat, String.length.go(u, 1n), 1n+String.length.go(u, 0n), Bytes.len.shift(u, 0n))), e))

def rest_nil(+t: Bytes(), +r: Nat, +st: D.St, e: {t == SNil{} : Bytes()}) ->
  {D.fi.bfeed(D.fi.rest(t, r), st) == st : D.St}:
  %Equal.sym(Bytes(), t, SNil{}, e) : {D.fi.bfeed(D.fi.rest(_, r), st) == st : D.St}
  {==}

def NVA(+s: Bytes(), +q: Nat, +r: Nat, +st: D.St, +go: Bool, +X: D.St) -> Type:
  {D.fi.in(s, q) == go : Bool} & ({Nat.is_lt(r, 8n) == True{} : Bool} & {X == D.fi.bfeed(R(s, q, r), st) : D.St})

def drv.step(+s: Bytes(), +q: Nat, +r: Nat, +st: D.St, +X: D.St, h: NVA(s, q, r, st, True{}, X)) ->
  NV.T(D.fi.node(s, q, r, st), s, X):
  (e, t) = h
  (hr, hX) = t
  node(s, q, r, st, X)(hX)(e)(hr)

def drv.zero(+s: Bytes(), +q: Nat, +r: Nat, +st: D.St, +X: D.St, h: NVA(s, q, r, st, True{}, X)) ->
  {D.fi.bfeed(D.fi.rest(Bytes.drop(s, q), r), st) == X : D.St}:
  (e, t) = h
  (hr, hX) = t
  Equal.sym(D.St, X, D.fi.bfeed(R(s, q, r), st), hX)

def drv.end(+s: Bytes(), +q: Nat, +r: Nat, +st: D.St, +X: D.St, h: NVA(s, q, r, st, False{}, X)) ->
  {st == X : D.St}:
  (e, t) = h
  (hr, hX) = t
  Equal.sym(D.St, X, st, Equal.trans(D.St, X, D.fi.bfeed(R(s, q, r), st), st, hX,
    rest_nil(Bytes.drop(s, q), r, st, dq_nil(s, q)(e))))

# the driver, wherever it is, runs the machine over the rest of the input
def drv(+k: Nat, +v: D.Dv, +s: Bytes(), +X: D.St) -> NV.T(v, s, X) -> {D.fi.drv(k, s, v) == X : D.St}:
  match k v:
    case 1n+p D.Dv{+q, +r, +st, True{}}:
      h => drv(p, D.fi.node(s, q, r, st), s, X)(drv.step(s, q, r, st, X, h))
    case 0n D.Dv{+q, +r, +st, True{}}:
      h => drv.zero(s, q, r, st, X, h)
    case 0n D.Dv{+q, +r, +st, False{}}:
      h => drv.end(s, q, r, st, X, h)
    case 1n+p D.Dv{+q, +r, +st, False{}}:
      h => drv.end(s, q, r, st, X, h)

# The stream
# ==========

def fb_app(+a: List<&2, Bool>, +b: List<&2, Bool>, +st: D.St) ->
  {D.fi.bfeed(List.append(&2, Bool, a, b), st) == D.fi.bfeed(b, D.fi.bfeed(a, st)) : D.St}:
  match a:
    case Nil{}:
      {==}
    case Con{+h, +t}:
      fb_app(t, b, D.bstep(st, h))

# a stream's bytes, fed, are its bits fed
def fbits(+s: Bytes(), +st: D.St) -> {D.feed_list(Bytes.to_list(s), st) == D.fi.bfeed(D.fi.bits(s), st) : D.St}:
  match s:
    case SNil{}:
      {==}
    case SCon{Chr{+c}, +t}:
      %Equal.sym(D.St, D.fi.bfeed(List.append(&2, Bool, D.unbyte(c), D.fi.bits(t)), st),
        D.fi.bfeed(D.fi.bits(t), D.fi.bfeed(D.unbyte(c), st)), fb_app(D.unbyte(c), D.fi.bits(t), st)) :
        {D.feed_list(Bytes.to_list(t), D.step(st, c)) == _ : D.St}
      fbits(t, D.step(st, c))

# from the first bit, the rest is the stream's bits
def r00(+s: Bytes(), +st: D.St) -> {D.fi.bfeed(R(s, 0n, 0n), st) == D.fi.bfeed(D.fi.bits(s), st) : D.St}:
  match s:
    case SNil{}:
      {==}
    case SCon{Chr{+c}, +t}:
      {==}

def adv_ok(+e: Unit, +s: Bytes(), p: D.St) ->
  {Wr.feed_buf.last(~Unit, ~D.St, ~D.wstep, e, D.wadv(e, s, p)) ==
    Wr.feed_buf.slow(~Unit, ~D.St, ~D.wstep, e, s, p) : D.St}:
  Wr.one.step_ok(~Unit, ~D.St, ~D.wstep, e, s, p)

def v0(+cap: Nat, +s: Bytes()) -> D.Dv:
  D.Dv{0n, 0n, D.new(cap), D.fi.in(s, 0n)}

# the fast inflate is the machine's
def inflate_fast(+cap: Nat, +s: Bytes()) ->
  {D.inflate(cap, s) == D.finish(D.feed(s, D.new(cap))) : Result<&2, &2, D.Why, Bytes()>}:
  +X = D.fi.bfeed(R(s, 0n, 0n), D.new(cap))
  +k = Nat.add(Nat.mul(8n, Bytes.len(s)), 1n)
  +v = v0(cap, s)
  Equal.cong(D.St, Result<&2, &2, D.Why, Bytes()>, D.finish, D.fi.drv(k, s, v), D.feed(s, D.new(cap)),
    Equal.trans(D.St, D.fi.drv(k, s, v), X, D.feed(s, D.new(cap)), drv(k, v, s, X)(({==}, ({==}, {==}))),
      Equal.trans(D.St, X, D.fi.bfeed(D.fi.bits(s), D.new(cap)), D.feed(s, D.new(cap)), r00(s, D.new(cap)),
        Equal.trans(D.St, D.fi.bfeed(D.fi.bits(s), D.new(cap)), D.feed_list(Bytes.to_list(s), D.new(cap)),
          D.feed(s, D.new(cap)),
          Equal.sym(D.St, D.feed_list(Bytes.to_list(s), D.new(cap)), D.fi.bfeed(D.fi.bits(s), D.new(cap)),
            fbits(s, D.new(cap))),
          Equal.sym(D.St, D.feed(s, D.new(cap)), D.feed_list(Bytes.to_list(s), D.new(cap)),
            Wr.feed_buf_is_feed(~Unit, ~D.St, ~D.wstep, ~D.wadv, ~adv_ok, Unit{}, s, D.new(cap)))))))
