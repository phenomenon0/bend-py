# Drift against a plain-CPython Welford and a transcription of Page-Hinkley
# (drift_gen.py prints this file). Every float leaves through q() as
# floor(x * 2^20 + 0.5) and never through F64.show: the scale is a power of two,
# so an exactly-representable sample scales without rounding and lands half a
# quantum from the edge, and the generator refuses to emit anything that lands
# nearer than that. The rows that carry a " | " carry both sides of one claim in
# one string -- a merge that lost its count weighting, or a detector whose state
# is not a value, prints two different halves and cannot pass by luck.
import Base
import ../../power/drift.bend as D

def yn(b: Bool) -> String:
  match b:
    case True{}:
      "1"
    case False{}:
      "0"

def qn(+v: F64) -> String:
  U32.show(F64.to_u32(v))

def q.go(+v: F64, neg: Bool) -> String:
  match neg:
    case True{}:
      "-" ++ qn(F64.neg(v))
    case False{}:
      qn(v)

def q.at(+v: F64) -> String:
  q.go(v, F64.is_lt(v, 0.0d))

def q(+x: F64) -> String:
  q.at(F64.round(F64.mul(x, 1048576.0d)))

def st(+s: D.Stat) -> String:
  U32.show(D.count(s)) ++ " " ++ q(D.mean(s)) ++ " " ++ q(D.variance(s))

# count and variance only, for the row whose mean is deliberately far outside
# the quantum's range
def sv(+s: D.Stat) -> String:
  U32.show(D.count(s)) ++ " " ++ q(D.variance(s))

def mg(+a: D.Stat, +b: D.Stat) -> String:
  st(a) ++ " | " ++ st(b)

# -- the stream --------------------------------------------------------------

# a multiply-shift-xor finalizer, not the bare Knuth multiply the rest of this
# tree uses. The bare multiply is a Weyl sequence: its cumulative deviation from
# its own mean stays inside +/-4 over three thousand samples, lag-1 correlation
# -0.42. The statistic this lane computes IS a discrepancy, so a low-discrepancy
# source is the one input that cannot exercise it -- the quiet rows below would
# pass against a detector that had been broken open. Two xor-shift rounds cost
# nothing and buy lag-1 0.0000 and a real random walk.
def h.fin2(+v: U32) -> U32:
  U32.xor(v, U32.shrn(v, 13n))

def h.fin(+u: U32) -> U32:
  h.fin2(U32.mul(U32.xor(u, U32.shrn(u, 15n)), 2246822519))

def h(+p: U32) -> U32:
  h.fin(U32.mul(U32.inc(p), 2654435761))

# noise in [-2, 2) in steps of 1/2048. The thirteen bits come off the TOP of the
# hash and not from a mod: a multiply moves information upward only, so the low
# bits of (p + 1) * C see only the low bits of p. An integer under 2^13 cast to
# F64 and divided by a power of two is exact, so every sample is the same number
# on the interpreter, in V8 and in C.
def nz(+p: U32) -> F64:
  F64.div(F64.sub(U32.to_f64(U32.shrn(h(p), 19n)), 4096.0d), 2048.0d)

# shape 0 is a step of `jump` at `at0`, shape 1 a ramp of `jump` a sample from
# `at0`. A stationary stream is either shape with at0 past the end of the run.
#
# Both guards branch through `match` rather than Bool.pick. Bool.pick is a
# function and so evaluates BOTH arms: before the change point `U32.sub(p, at0)`
# wraps, and the ramp arm computes jump * 4.29e9 -- a number the answer never
# uses. A match never builds it. See docs/omen/lanes/power-13.md.
def lvl.ramp(+p: U32, +at0: U32, +jump: F64, step: Bool) -> F64:
  match step:
    case True{}:
      jump
    case False{}:
      F64.mul(jump, U32.to_f64(U32.sub(p, at0)))

def lvl.at(+shape: U32, +p: U32, +at0: U32, +jump: F64, before: Bool) -> F64:
  match before:
    case True{}:
      0.0d
    case False{}:
      lvl.ramp(p, at0, jump, U32.is_eq(shape, 0))

def lvl(+shape: U32, +p: U32, +at0: U32, +jump: F64) -> F64:
  lvl.at(shape, p, at0, jump, U32.is_lt(p, at0))

def sx(+shape: U32, +p: U32, +at0: U32, +jump: F64) -> F64:
  F64.add(lvl(shape, p, at0, jump), nz(p))

# -- Welford over a range ----------------------------------------------------

def fold(i: Nat, +p: U32, +shape: U32, +at0: U32, +jump: F64, s: D.Stat) -> D.Stat:
  match i:
    case 0n:
      s
    case 1n++k:
      fold(k, U32.inc(p), shape, at0, jump, D.push(s, sx(shape, p, at0, jump)))

# the accumulator over [lo, lo + n), by a straight left fold
def acc(+lo: U32, n: Nat, +shape: U32, +at0: U32, +jump: F64) -> D.Stat:
  fold(n, lo, shape, at0, jump, D.empty())

# the same range merged over a binary tree of depth d: the association a fork
# makes, which is NOT the association the fold above makes. F64 addition is not
# associative, so the two agree to the last few bits and not to the last one --
# the quantum every row prints at is where they are made to agree, and
# drift_gen.py asserts that agreement before it emits a single line.
def tree(d: Nat, +lo: U32, +n: U32, +shape: U32, +at0: U32, +jump: F64) -> D.Stat:
  match d:
    case 0n:
      acc(lo, U32.to_nat(n), shape, at0, jump)
    case 1n++k:
      +hf = U32.shr(n)
      a b = tree(k, lo, hf, shape, at0, jump) tree(k, U32.add(lo, hf), hf, shape, at0, jump)
      D.merge(a, b)

# -- the detector over a range -----------------------------------------------

type Run is Data:
  Run{d: D.PH, ev: D.Ev, hits: U32}

def blank() -> D.Ev:
  D.Ev{D.Up{}, 0, 0, D.empty(), D.empty()}

def start(+dir: D.Dir, +delta: F64, +lam: F64, +warm: U32) -> Run:
  Run{D.new(dir, delta, lam, warm), blank(), 0}

# the configured corner: delta 1/2, lambda 16, warm-up 30. The cheapest cell of
# the sweep in docs/omen/lanes/power-13.md with a measured zero false-positive
# count over 3,000 stationary samples, in BOTH directions.
def up() -> Run:
  start(D.Up{}, 0.5d, 16.0d, 30)

# the FIRST report is the one kept, so a detector that fires twice on one change
# cannot hide the second behind the first -- the count is printed beside it
def land.first(d: D.PH, ev: D.Ev, e: D.Ev, +hits: U32, first: Bool) -> Run:
  match first:
    case True{}:
      Run{d, e, U32.inc(hits)}
    case False{}:
      Run{d, ev, U32.inc(hits)}

def land(r: D.PH & Maybe<&2, D.Ev>, +ev: D.Ev, +hits: U32) -> Run:
  (d, m) = r
  match m:
    case None{}:
      Run{d, ev, hits}
    case Some{e}:
      land.first(d, ev, e, hits, U32.is_eq(hits, 0))

# feed takes a Run and gives one back, so a run can be cut anywhere and resumed
def feed(i: Nat, +p: U32, +shape: U32, +at0: U32, +jump: F64, r: Run) -> Run:
  match i:
    case 0n:
      r
    case 1n++k:
      match r:
        case Run{d, ev, hits}:
          feed(k, U32.inc(p), shape, at0, jump, land(D.step(d, sx(shape, p, at0, jump)), ev, hits))

def eshow(e: D.Ev) -> String:
  match e:
    case D.Ev{dir, at, since, before, after}:
      D.show.dir(dir) ++ " @" ++ U32.show(at) ++ " ~" ++ U32.show(since) ++ " | " ++ st(before) ++ " | " ++ st(after)

def rshow(r: Run) -> String:
  match r:
    case Run{d, ev, hits}:
      U32.show(hits) ++ " " ++ eshow(ev)

def cut(a: Run, b: Run) -> String:
  rshow(a) ++ " | " ++ rshow(b)

def hits(r: Run) -> String:
  match r:
    case Run{d, ev, hits}:
      U32.show(hits)

def rstat.at(+d: D.PH) -> String:
  U32.show(D.seen(d)) ++ " " ++ st(D.stat(d))

def rstat(r: Run) -> String:
  match r:
    case Run{d, ev, hits}:
      rstat.at(d)

def evsig(r: Run, +rng: F64, +lnid: F64) -> Bool:
  match r:
    case Run{d, ev, hits}:
      D.ev.differs(ev, rng, lnid)

# the report and its significance in one row: Page-Hinkley says when, and the
# Hoeffding cut says whether the gap it found is wider than luck allows
def rsig(+r: Run, +rng: F64, +lnid: F64) -> String:
  rshow(r) ++ " sig=" ++ yn(evsig(r, rng, lnid))

def dly.ev(e: D.Ev, +at0: U32, +hits: U32) -> String:
  match e:
    case D.Ev{dir, at, since, before, after}:
      U32.show(hits) ++ " delay=" ++ U32.show(U32.sub(at, at0)) ++ " since=" ++ U32.show(since)

def dly(r: Run, +at0: U32) -> String:
  match r:
    case Run{d, ev, hits}:
      dly.ev(ev, at0, hits)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(st(D.empty()))
    IO.print(st(D.one(3.5d)))
    IO.print(st(D.push(D.empty(), 1.0d)))
    IO.print(st(D.push(D.push(D.push(D.empty(), 1.0d), 2.0d), 6.0d)))
    IO.print(st(D.push(D.push(D.push(D.push(D.empty(), 4.0d), 4.0d), 4.0d), 4.0d)))
    IO.print(st(D.push(D.push(D.push(D.push(D.empty(), 0.5d), 0.25d), 0.125d), 8.0d)))
    IO.print(sv(D.push(D.push(D.push(D.empty(), 100000000.0d), 100000000.25d), 100000000.5d)))
    IO.print(q(D.variance(D.empty())))
    IO.print(q(D.variance(D.one(9.0d))))
    IO.print(U32.show(D.count(D.one(9.0d))))
    IO.print(st(acc(0, 1n, 0, 9999, 0.0d)))
    IO.print(st(acc(0, 2n, 0, 9999, 0.0d)))
    IO.print(st(acc(0, 17n, 0, 9999, 0.0d)))
    IO.print(st(acc(0, 64n, 0, 9999, 0.0d)))
    IO.print(st(acc(0, 300n, 0, 9999, 0.0d)))
    IO.print(st(acc(0, 64n, 0, 200, 2.0d)))
    IO.print(st(acc(0, 300n, 0, 200, 2.0d)))
    IO.print(st(acc(0, 64n, 0, 128, 4.0d)))
    IO.print(st(acc(0, 300n, 0, 128, 4.0d)))
    IO.print(st(acc(0, 64n, 1, 150, 0.015625d)))
    IO.print(st(acc(0, 300n, 1, 150, 0.015625d)))
    IO.print(mg(D.merge(acc(0, 0n, 0, 9999, 0.0d), acc(0, 256n, 0, 9999, 0.0d)), acc(0, 256n, 0, 9999, 0.0d)))
    IO.print(mg(D.tail(acc(0, 256n, 0, 9999, 0.0d), acc(0, 0n, 0, 9999, 0.0d)), acc(0, 256n, 0, 9999, 0.0d)))
    IO.print(mg(D.merge(acc(0, 1n, 0, 9999, 0.0d), acc(1, 255n, 0, 9999, 0.0d)), acc(0, 256n, 0, 9999, 0.0d)))
    IO.print(mg(D.tail(acc(0, 256n, 0, 9999, 0.0d), acc(0, 1n, 0, 9999, 0.0d)), acc(1, 255n, 0, 9999, 0.0d)))
    IO.print(mg(D.merge(acc(0, 200n, 0, 9999, 0.0d), acc(200, 56n, 0, 9999, 0.0d)), acc(0, 256n, 0, 9999, 0.0d)))
    IO.print(mg(D.tail(acc(0, 256n, 0, 9999, 0.0d), acc(0, 200n, 0, 9999, 0.0d)), acc(200, 56n, 0, 9999, 0.0d)))
    IO.print(mg(D.merge(acc(0, 256n, 0, 9999, 0.0d), acc(256, 0n, 0, 9999, 0.0d)), acc(0, 256n, 0, 9999, 0.0d)))
    IO.print(mg(D.tail(acc(0, 256n, 0, 9999, 0.0d), acc(0, 256n, 0, 9999, 0.0d)), acc(256, 0n, 0, 9999, 0.0d)))
    IO.print(mg(D.merge(acc(0, 0n, 0, 200, 2.0d), acc(0, 256n, 0, 200, 2.0d)), acc(0, 256n, 0, 200, 2.0d)))
    IO.print(mg(D.tail(acc(0, 256n, 0, 200, 2.0d), acc(0, 0n, 0, 200, 2.0d)), acc(0, 256n, 0, 200, 2.0d)))
    IO.print(mg(D.merge(acc(0, 1n, 0, 200, 2.0d), acc(1, 255n, 0, 200, 2.0d)), acc(0, 256n, 0, 200, 2.0d)))
    IO.print(mg(D.tail(acc(0, 256n, 0, 200, 2.0d), acc(0, 1n, 0, 200, 2.0d)), acc(1, 255n, 0, 200, 2.0d)))
    IO.print(mg(D.merge(acc(0, 200n, 0, 200, 2.0d), acc(200, 56n, 0, 200, 2.0d)), acc(0, 256n, 0, 200, 2.0d)))
    IO.print(mg(D.tail(acc(0, 256n, 0, 200, 2.0d), acc(0, 200n, 0, 200, 2.0d)), acc(200, 56n, 0, 200, 2.0d)))
    IO.print(mg(D.merge(acc(0, 256n, 0, 200, 2.0d), acc(256, 0n, 0, 200, 2.0d)), acc(0, 256n, 0, 200, 2.0d)))
    IO.print(mg(D.tail(acc(0, 256n, 0, 200, 2.0d), acc(0, 256n, 0, 200, 2.0d)), acc(256, 0n, 0, 200, 2.0d)))
    IO.print(mg(D.merge(acc(0, 0n, 0, 128, 4.0d), acc(0, 256n, 0, 128, 4.0d)), acc(0, 256n, 0, 128, 4.0d)))
    IO.print(mg(D.tail(acc(0, 256n, 0, 128, 4.0d), acc(0, 0n, 0, 128, 4.0d)), acc(0, 256n, 0, 128, 4.0d)))
    IO.print(mg(D.merge(acc(0, 1n, 0, 128, 4.0d), acc(1, 255n, 0, 128, 4.0d)), acc(0, 256n, 0, 128, 4.0d)))
    IO.print(mg(D.tail(acc(0, 256n, 0, 128, 4.0d), acc(0, 1n, 0, 128, 4.0d)), acc(1, 255n, 0, 128, 4.0d)))
    IO.print(mg(D.merge(acc(0, 200n, 0, 128, 4.0d), acc(200, 56n, 0, 128, 4.0d)), acc(0, 256n, 0, 128, 4.0d)))
    IO.print(mg(D.tail(acc(0, 256n, 0, 128, 4.0d), acc(0, 200n, 0, 128, 4.0d)), acc(200, 56n, 0, 128, 4.0d)))
    IO.print(mg(D.merge(acc(0, 256n, 0, 128, 4.0d), acc(256, 0n, 0, 128, 4.0d)), acc(0, 256n, 0, 128, 4.0d)))
    IO.print(mg(D.tail(acc(0, 256n, 0, 128, 4.0d), acc(0, 256n, 0, 128, 4.0d)), acc(256, 0n, 0, 128, 4.0d)))
    IO.print(mg(D.merge(acc(0, 0n, 1, 150, 0.015625d), acc(0, 256n, 1, 150, 0.015625d)), acc(0, 256n, 1, 150, 0.015625d)))
    IO.print(mg(D.tail(acc(0, 256n, 1, 150, 0.015625d), acc(0, 0n, 1, 150, 0.015625d)), acc(0, 256n, 1, 150, 0.015625d)))
    IO.print(mg(D.merge(acc(0, 1n, 1, 150, 0.015625d), acc(1, 255n, 1, 150, 0.015625d)), acc(0, 256n, 1, 150, 0.015625d)))
    IO.print(mg(D.tail(acc(0, 256n, 1, 150, 0.015625d), acc(0, 1n, 1, 150, 0.015625d)), acc(1, 255n, 1, 150, 0.015625d)))
    IO.print(mg(D.merge(acc(0, 200n, 1, 150, 0.015625d), acc(200, 56n, 1, 150, 0.015625d)), acc(0, 256n, 1, 150, 0.015625d)))
    IO.print(mg(D.tail(acc(0, 256n, 1, 150, 0.015625d), acc(0, 200n, 1, 150, 0.015625d)), acc(200, 56n, 1, 150, 0.015625d)))
    IO.print(mg(D.merge(acc(0, 256n, 1, 150, 0.015625d), acc(256, 0n, 1, 150, 0.015625d)), acc(0, 256n, 1, 150, 0.015625d)))
    IO.print(mg(D.tail(acc(0, 256n, 1, 150, 0.015625d), acc(0, 256n, 1, 150, 0.015625d)), acc(256, 0n, 1, 150, 0.015625d)))
    IO.print(mg(D.merge(D.merge(acc(0, 16n, 0, 9999, 0.0d), acc(16, 48n, 0, 9999, 0.0d)), acc(64, 192n, 0, 9999, 0.0d)), D.merge(acc(0, 16n, 0, 9999, 0.0d), D.merge(acc(16, 48n, 0, 9999, 0.0d), acc(64, 192n, 0, 9999, 0.0d)))))
    IO.print(mg(tree(1n, 0, 256, 0, 9999, 0.0d), acc(0, 256n, 0, 9999, 0.0d)))
    IO.print(mg(tree(4n, 0, 256, 0, 9999, 0.0d), acc(0, 256n, 0, 9999, 0.0d)))
    IO.print(mg(tree(6n, 0, 256, 0, 9999, 0.0d), acc(0, 256n, 0, 9999, 0.0d)))
    IO.print(mg(D.merge(D.merge(acc(0, 16n, 0, 200, 2.0d), acc(16, 48n, 0, 200, 2.0d)), acc(64, 192n, 0, 200, 2.0d)), D.merge(acc(0, 16n, 0, 200, 2.0d), D.merge(acc(16, 48n, 0, 200, 2.0d), acc(64, 192n, 0, 200, 2.0d)))))
    IO.print(mg(tree(1n, 0, 256, 0, 200, 2.0d), acc(0, 256n, 0, 200, 2.0d)))
    IO.print(mg(tree(4n, 0, 256, 0, 200, 2.0d), acc(0, 256n, 0, 200, 2.0d)))
    IO.print(mg(tree(6n, 0, 256, 0, 200, 2.0d), acc(0, 256n, 0, 200, 2.0d)))
    IO.print(mg(D.merge(D.merge(acc(0, 16n, 0, 128, 4.0d), acc(16, 48n, 0, 128, 4.0d)), acc(64, 192n, 0, 128, 4.0d)), D.merge(acc(0, 16n, 0, 128, 4.0d), D.merge(acc(16, 48n, 0, 128, 4.0d), acc(64, 192n, 0, 128, 4.0d)))))
    IO.print(mg(tree(1n, 0, 256, 0, 128, 4.0d), acc(0, 256n, 0, 128, 4.0d)))
    IO.print(mg(tree(4n, 0, 256, 0, 128, 4.0d), acc(0, 256n, 0, 128, 4.0d)))
    IO.print(mg(tree(6n, 0, 256, 0, 128, 4.0d), acc(0, 256n, 0, 128, 4.0d)))
    IO.print(mg(D.merge(D.merge(acc(0, 16n, 1, 150, 0.015625d), acc(16, 48n, 1, 150, 0.015625d)), acc(64, 192n, 1, 150, 0.015625d)), D.merge(acc(0, 16n, 1, 150, 0.015625d), D.merge(acc(16, 48n, 1, 150, 0.015625d), acc(64, 192n, 1, 150, 0.015625d)))))
    IO.print(mg(tree(1n, 0, 256, 1, 150, 0.015625d), acc(0, 256n, 1, 150, 0.015625d)))
    IO.print(mg(tree(4n, 0, 256, 1, 150, 0.015625d), acc(0, 256n, 1, 150, 0.015625d)))
    IO.print(mg(tree(6n, 0, 256, 1, 150, 0.015625d), acc(0, 256n, 1, 150, 0.015625d)))
    IO.print(st(D.merge(D.empty(), D.empty())))
    IO.print(st(D.merge(D.empty(), D.one(7.0d))))
    IO.print(st(D.merge(D.one(7.0d), D.empty())))
    IO.print(mg(D.merge(D.empty(), acc(0, 64n, 0, 200, 2.0d)), acc(0, 64n, 0, 200, 2.0d)))
    IO.print(st(D.tail(D.empty(), D.empty())))
    IO.print(st(D.tail(D.one(7.0d), D.one(7.0d))))
    IO.print(st(D.tail(acc(0, 16n, 0, 200, 2.0d), acc(0, 64n, 0, 200, 2.0d))))
    IO.print(st(D.tail(D.push(D.one(1.0d), 3.0d), D.empty())))
    IO.print(rsig(feed(600n, 0, 0, 200, 0.75d, up()), 8.0d, 3.0d))
    IO.print(rsig(feed(600n, 0, 0, 200, 1.0d, up()), 8.0d, 3.0d))
    IO.print(rsig(feed(600n, 0, 0, 200, 2.0d, up()), 8.0d, 3.0d))
    IO.print(rsig(feed(600n, 0, 0, 200, 4.0d, up()), 8.0d, 3.0d))
    IO.print(rsig(feed(600n, 0, 0, 200, 8.0d, up()), 8.0d, 3.0d))
    IO.print(rsig(feed(600n, 0, 0, 200, F64.neg(0.75d), start(D.Down{}, 0.5d, 16.0d, 30)), 8.0d, 3.0d))
    IO.print(rsig(feed(600n, 0, 0, 200, F64.neg(1.0d), start(D.Down{}, 0.5d, 16.0d, 30)), 8.0d, 3.0d))
    IO.print(rsig(feed(600n, 0, 0, 200, F64.neg(2.0d), start(D.Down{}, 0.5d, 16.0d, 30)), 8.0d, 3.0d))
    IO.print(rsig(feed(600n, 0, 0, 200, F64.neg(4.0d), start(D.Down{}, 0.5d, 16.0d, 30)), 8.0d, 3.0d))
    IO.print(rsig(feed(600n, 0, 0, 200, F64.neg(8.0d), start(D.Down{}, 0.5d, 16.0d, 30)), 8.0d, 3.0d))
    IO.print(rsig(feed(600n, 0, 0, 200, 2.0d, start(D.Down{}, 0.5d, 16.0d, 30)), 8.0d, 3.0d))
    IO.print(rsig(feed(600n, 0, 0, 200, F64.neg(2.0d), up()), 8.0d, 3.0d))
    IO.print(rsig(feed(600n, 0, 0, 200, 2.0d, start(D.Up{}, 0.5d, 2.0d, 30)), 8.0d, 3.0d))
    IO.print(rsig(feed(600n, 0, 0, 200, 2.0d, start(D.Up{}, 0.5d, 4.0d, 30)), 8.0d, 3.0d))
    IO.print(rsig(feed(600n, 0, 0, 200, 2.0d, start(D.Up{}, 0.5d, 8.0d, 30)), 8.0d, 3.0d))
    IO.print(rsig(feed(600n, 0, 0, 200, 2.0d, start(D.Up{}, 0.5d, 32.0d, 30)), 8.0d, 3.0d))
    IO.print(rsig(feed(600n, 0, 0, 200, 2.0d, start(D.Up{}, 0.0d, 16.0d, 30)), 8.0d, 3.0d))
    IO.print(rsig(feed(600n, 0, 0, 200, 2.0d, start(D.Up{}, 0.25d, 16.0d, 30)), 8.0d, 3.0d))
    IO.print(rsig(feed(600n, 0, 0, 200, 2.0d, start(D.Up{}, 1.0d, 16.0d, 30)), 8.0d, 3.0d))
    IO.print(rsig(feed(600n, 0, 0, 200, 2.0d, start(D.Up{}, 1.5d, 16.0d, 30)), 8.0d, 3.0d))
    IO.print(rsig(feed(600n, 0, 0, 200, 2.0d, start(D.Up{}, 0.5d, 16.0d, 1)), 8.0d, 3.0d))
    IO.print(rsig(feed(600n, 0, 0, 200, 2.0d, start(D.Up{}, 0.5d, 16.0d, 250)), 8.0d, 3.0d))
    IO.print(rsig(feed(400n, 0, 1, 150, 0.015625d, up()), 8.0d, 3.0d))
    IO.print(rsig(feed(400n, 0, 1, 150, 0.03125d, up()), 8.0d, 3.0d))
    IO.print(rsig(feed(400n, 0, 1, 150, 0.0625d, up()), 8.0d, 3.0d))
    IO.print(rsig(feed(400n, 0, 0, 0, 2.0d, up()), 8.0d, 3.0d))
    IO.print(rsig(feed(400n, 0, 0, 390, 2.0d, up()), 8.0d, 3.0d))
    IO.print(dly(feed(600n, 0, 0, 200, 0.75d, up()), 200))
    IO.print(dly(feed(600n, 0, 0, 200, 1.0d, up()), 200))
    IO.print(dly(feed(600n, 0, 0, 200, 2.0d, up()), 200))
    IO.print(dly(feed(600n, 0, 0, 200, 4.0d, up()), 200))
    IO.print(dly(feed(600n, 0, 0, 200, 8.0d, up()), 200))
    IO.print(cut(feed(299n, 1, 0, 9999, 0.0d, feed(1n, 0, 0, 9999, 0.0d, up())), feed(300n, 0, 0, 9999, 0.0d, up())))
    IO.print(cut(feed(270n, 30, 0, 9999, 0.0d, feed(30n, 0, 0, 9999, 0.0d, up())), feed(300n, 0, 0, 9999, 0.0d, up())))
    IO.print(cut(feed(150n, 150, 0, 9999, 0.0d, feed(150n, 0, 0, 9999, 0.0d, up())), feed(300n, 0, 0, 9999, 0.0d, up())))
    IO.print(cut(feed(1n, 299, 0, 9999, 0.0d, feed(299n, 0, 0, 9999, 0.0d, up())), feed(300n, 0, 0, 9999, 0.0d, up())))
    IO.print(cut(feed(299n, 1, 0, 200, 2.0d, feed(1n, 0, 0, 200, 2.0d, up())), feed(300n, 0, 0, 200, 2.0d, up())))
    IO.print(cut(feed(270n, 30, 0, 200, 2.0d, feed(30n, 0, 0, 200, 2.0d, up())), feed(300n, 0, 0, 200, 2.0d, up())))
    IO.print(cut(feed(150n, 150, 0, 200, 2.0d, feed(150n, 0, 0, 200, 2.0d, up())), feed(300n, 0, 0, 200, 2.0d, up())))
    IO.print(cut(feed(1n, 299, 0, 200, 2.0d, feed(299n, 0, 0, 200, 2.0d, up())), feed(300n, 0, 0, 200, 2.0d, up())))
    IO.print(cut(feed(299n, 1, 0, 128, 4.0d, feed(1n, 0, 0, 128, 4.0d, up())), feed(300n, 0, 0, 128, 4.0d, up())))
    IO.print(cut(feed(270n, 30, 0, 128, 4.0d, feed(30n, 0, 0, 128, 4.0d, up())), feed(300n, 0, 0, 128, 4.0d, up())))
    IO.print(cut(feed(150n, 150, 0, 128, 4.0d, feed(150n, 0, 0, 128, 4.0d, up())), feed(300n, 0, 0, 128, 4.0d, up())))
    IO.print(cut(feed(1n, 299, 0, 128, 4.0d, feed(299n, 0, 0, 128, 4.0d, up())), feed(300n, 0, 0, 128, 4.0d, up())))
    IO.print(cut(feed(299n, 1, 1, 150, 0.015625d, feed(1n, 0, 1, 150, 0.015625d, up())), feed(300n, 0, 1, 150, 0.015625d, up())))
    IO.print(cut(feed(270n, 30, 1, 150, 0.015625d, feed(30n, 0, 1, 150, 0.015625d, up())), feed(300n, 0, 1, 150, 0.015625d, up())))
    IO.print(cut(feed(150n, 150, 1, 150, 0.015625d, feed(150n, 0, 1, 150, 0.015625d, up())), feed(300n, 0, 1, 150, 0.015625d, up())))
    IO.print(cut(feed(1n, 299, 1, 150, 0.015625d, feed(299n, 0, 1, 150, 0.015625d, up())), feed(300n, 0, 1, 150, 0.015625d, up())))
    IO.print(hits(feed(3000n, 0, 0, 9999, 0.0d, start(D.Up{}, 0.25d, 8.0d, 30))))
    IO.print(hits(feed(3000n, 0, 0, 9999, 0.0d, start(D.Down{}, 0.25d, 8.0d, 30))))
    IO.print(hits(feed(3000n, 0, 0, 9999, 0.0d, start(D.Up{}, 0.5d, 4.0d, 30))))
    IO.print(hits(feed(3000n, 0, 0, 9999, 0.0d, start(D.Down{}, 0.5d, 4.0d, 30))))
    IO.print(hits(feed(3000n, 0, 0, 9999, 0.0d, start(D.Up{}, 0.5d, 8.0d, 30))))
    IO.print(hits(feed(3000n, 0, 0, 9999, 0.0d, start(D.Down{}, 0.5d, 8.0d, 30))))
    IO.print(hits(feed(3000n, 0, 0, 9999, 0.0d, up())))
    IO.print(hits(feed(3000n, 0, 0, 9999, 0.0d, start(D.Down{}, 0.5d, 16.0d, 30))))
    IO.print(hits(feed(3000n, 0, 0, 9999, 0.0d, start(D.Up{}, 1.0d, 8.0d, 30))))
    IO.print(hits(feed(3000n, 0, 0, 9999, 0.0d, start(D.Down{}, 1.0d, 8.0d, 30))))
    IO.print(hits(feed(3000n, 0, 0, 9999, 0.0d, start(D.Up{}, 0.0d, 16.0d, 30))))
    IO.print(rstat(feed(300n, 0, 0, 9999, 0.0d, up())))
    IO.print(rstat(feed(300n, 0, 0, 200, 2.0d, up())))
    IO.print(rstat(feed(300n, 0, 0, 128, 4.0d, up())))
    IO.print(rstat(feed(300n, 0, 1, 150, 0.015625d, up())))
    IO.print(D.show.dir(D.Up{}))
    IO.print(D.show.dir(D.Down{}))
    IO.print(q(D.eps(1, 1, 8.0d, 3.0d)))
    IO.print(q(D.eps(100, 100, 8.0d, 3.0d)))
    IO.print(q(D.eps(198, 8, 8.0d, 3.0d)))
    IO.print(q(D.eps(8, 198, 8.0d, 3.0d)))
    IO.print(q(D.eps(3000, 1, 8.0d, 3.0d)))
    IO.print(q(D.eps(198, 8, 4.0d, 2.0d)))
    IO.print(yn(D.differs(acc(0, 128n, 0, 9999, 0.0d), acc(128, 128n, 0, 9999, 0.0d), 8.0d, 3.0d)))
    IO.print(yn(D.differs(acc(0, 128n, 0, 9999, 0.0d), acc(128, 128n, 0, 9999, 0.0d), 0.5d, 3.0d)))
    IO.print(yn(D.differs(acc(0, 128n, 0, 200, 2.0d), acc(128, 128n, 0, 200, 2.0d), 8.0d, 3.0d)))
    IO.print(yn(D.differs(acc(0, 128n, 0, 200, 2.0d), acc(128, 128n, 0, 200, 2.0d), 0.5d, 3.0d)))
    IO.print(yn(D.differs(acc(0, 128n, 0, 128, 4.0d), acc(128, 128n, 0, 128, 4.0d), 8.0d, 3.0d)))
    IO.print(yn(D.differs(acc(0, 128n, 0, 128, 4.0d), acc(128, 128n, 0, 128, 4.0d), 0.5d, 3.0d)))
    IO.print(yn(D.differs(acc(0, 128n, 1, 150, 0.015625d), acc(128, 128n, 1, 150, 0.015625d), 8.0d, 3.0d)))
    IO.print(yn(D.differs(acc(0, 128n, 1, 150, 0.015625d), acc(128, 128n, 1, 150, 0.015625d), 0.5d, 3.0d)))
    IO.print(yn(D.differs(D.empty(), D.one(1000.0d), 8.0d, 3.0d)))
    IO.print(yn(D.differs(D.one(1000.0d), D.empty(), 8.0d, 3.0d)))
#|0 0 0
#|1 3670016 0
#|1 1048576 0
#|3 3145728 4893355
#|4 4194304 0
#|4 2326528 11701248
#|3 43691
#|0
#|0
#|1
#|1 -572416 0
#|2 409856 920161
#|17 -21805 2135286
#|64 90656 1377143
#|300 -87334 1319236
#|64 90656 1377143
#|300 611717 2220900
#|64 90656 1377143
#|300 2317401 5355140
#|64 90656 1377143
#|300 522970 1946496
#|256 -109146 1330698 | 256 -109146 1330698
#|256 -109146 1330698 | 256 -109146 1330698
#|256 -109146 1330698 | 256 -109146 1330698
#|255 -107329 1335111 | 255 -107329 1335111
#|256 -109146 1330698 | 256 -109146 1330698
#|56 -227767 1424751 | 56 -227767 1424751
#|256 -109146 1330698 | 256 -109146 1330698
#|0 0 0 | 0 0 0
#|256 349606 1943705 | 256 349606 1943705
#|256 349606 1943705 | 256 349606 1943705
#|256 349606 1943705 | 256 349606 1943705
#|255 353222 1948135 | 255 353222 1948135
#|256 349606 1943705 | 256 349606 1943705
#|56 1869385 1424751 | 56 1869385 1424751
#|256 349606 1943705 | 256 349606 1943705
#|0 0 0 | 0 0 0
#|256 1988006 5357858 | 256 1988006 5357858
#|256 1988006 5357858 | 256 1988006 5357858
#|256 1988006 5357858 | 256 1988006 5357858
#|255 1998047 5354255 | 255 1998047 5354255
#|256 1988006 5357858 | 256 1988006 5357858
#|56 3966537 1424751 | 56 3966537 1424751
#|256 1988006 5357858 | 256 1988006 5357858
#|0 0 0 | 0 0 0
#|256 247014 1558836 | 256 247014 1558836
#|256 247014 1558836 | 256 247014 1558836
#|256 247014 1558836 | 256 247014 1558836
#|255 250227 1562428 | 255 250227 1562428
#|256 247014 1558836 | 256 247014 1558836
#|56 1041993 1616392 | 56 1041993 1616392
#|256 247014 1558836 | 256 247014 1558836
#|0 0 0 | 0 0 0
#|256 -109146 1330698 | 256 -109146 1330698
#|256 -109146 1330698 | 256 -109146 1330698
#|256 -109146 1330698 | 256 -109146 1330698
#|256 -109146 1330698 | 256 -109146 1330698
#|256 349606 1943705 | 256 349606 1943705
#|256 349606 1943705 | 256 349606 1943705
#|256 349606 1943705 | 256 349606 1943705
#|256 349606 1943705 | 256 349606 1943705
#|256 1988006 5357858 | 256 1988006 5357858
#|256 1988006 5357858 | 256 1988006 5357858
#|256 1988006 5357858 | 256 1988006 5357858
#|256 1988006 5357858 | 256 1988006 5357858
#|256 247014 1558836 | 256 247014 1558836
#|256 247014 1558836 | 256 247014 1558836
#|256 247014 1558836 | 256 247014 1558836
#|256 247014 1558836 | 256 247014 1558836
#|0 0 0
#|1 7340032 0
#|1 7340032 0
#|64 90656 1377143 | 64 90656 1377143
#|0 0 0
#|0 0 0
#|0 0 0
#|2 2097152 1048576
#|1 up @293 ~220 | 220 -58896 1281042 | 73 818190 1289884 sig=0
#|1 up @256 ~220 | 220 -35065 1294202 | 36 1069255 1459520 sig=0
#|1 up @217 ~200 | 200 -75932 1299554 | 17 1525549 1088537 sig=0
#|1 up @206 ~200 | 200 -75932 1299554 | 6 3899307 1554343 sig=0
#|1 up @202 ~200 | 200 -75932 1299554 | 2 8978944 348690 sig=1
#|1 down @220 ~202 | 202 -77122 1290274 | 18 -1601991 956627 sig=0
#|1 down @218 ~202 | 202 -79717 1291506 | 16 -1743136 945199 sig=0
#|1 down @210 ~200 | 200 -75932 1299554 | 10 -2510131 1212665 sig=0
#|1 down @205 ~200 | 200 -75932 1299554 | 5 -4523418 1858552 sig=0
#|1 down @203 ~200 | 200 -75932 1299554 | 3 -8667136 1672365 sig=1
#|0 up @0 ~0 | 0 0 0 | 0 0 0 sig=0
#|0 up @0 ~0 | 0 0 0 | 0 0 0 sig=0
#|15 up @30 ~12 | 12 -531413 1706718 | 18 748572 1334664 sig=0
#|3 up @202 ~200 | 200 -75932 1299554 | 2 2687488 348690 sig=0
#|1 up @207 ~200 | 200 -75932 1299554 | 7 1958693 1472508 sig=0
#|1 up @229 ~200 | 200 -75932 1299554 | 29 1727470 1452513 sig=0
#|2 up @207 ~152 | 152 -99934 1379585 | 55 249353 1500423 sig=0
#|1 up @211 ~200 | 200 -75932 1299554 | 11 1799354 1228945 sig=0
#|1 up @228 ~200 | 200 -75932 1299554 | 28 1724965 1504215 sig=0
#|1 up @301 ~220 | 220 60260 1455165 | 81 2149686 1354520 sig=1
#|1 up @217 ~200 | 200 -75932 1299554 | 17 1525549 1088537 sig=0
#|1 up @250 ~200 | 200 -75932 1299554 | 50 1827615 1396332 sig=1
#|2 up @248 ~220 | 220 49462 1303712 | 28 1321198 1390796 sig=0
#|4 up @202 ~152 | 152 -99719 1379236 | 50 892037 1038378 sig=0
#|5 up @180 ~152 | 152 -99503 1378899 | 28 1171986 1083179 sig=0
#|0 up @0 ~0 | 0 0 0 | 0 0 0 sig=0
#|1 up @399 ~390 | 390 -67228 1327589 | 9 2471538 1410173 sig=0
#|1 delay=93 since=220
#|1 delay=56 since=220
#|1 delay=17 since=200
#|1 delay=6 since=200
#|1 delay=2 since=200
#|0 up @0 ~0 | 0 0 0 | 0 0 0 | 0 up @0 ~0 | 0 0 0 | 0 0 0
#|0 up @0 ~0 | 0 0 0 | 0 0 0 | 0 up @0 ~0 | 0 0 0 | 0 0 0
#|0 up @0 ~0 | 0 0 0 | 0 0 0 | 0 up @0 ~0 | 0 0 0 | 0 0 0
#|0 up @0 ~0 | 0 0 0 | 0 0 0 | 0 up @0 ~0 | 0 0 0 | 0 0 0
#|1 up @217 ~200 | 200 -75932 1299554 | 17 1525549 1088537 | 1 up @217 ~200 | 200 -75932 1299554 | 17 1525549 1088537
#|1 up @217 ~200 | 200 -75932 1299554 | 17 1525549 1088537 | 1 up @217 ~200 | 200 -75932 1299554 | 17 1525549 1088537
#|1 up @217 ~200 | 200 -75932 1299554 | 17 1525549 1088537 | 1 up @217 ~200 | 200 -75932 1299554 | 17 1525549 1088537
#|1 up @217 ~200 | 200 -75932 1299554 | 17 1525549 1088537 | 1 up @217 ~200 | 200 -75932 1299554 | 17 1525549 1088537
#|1 up @132 ~127 | 127 -72115 1394605 | 5 4472218 3954635 | 1 up @132 ~127 | 127 -72115 1394605 | 5 4472218 3954635
#|1 up @132 ~127 | 127 -72115 1394605 | 5 4472218 3954635 | 1 up @132 ~127 | 127 -72115 1394605 | 5 4472218 3954635
#|1 up @132 ~127 | 127 -72115 1394605 | 5 4472218 3954635 | 1 up @132 ~127 | 127 -72115 1394605 | 5 4472218 3954635
#|1 up @132 ~127 | 127 -72115 1394605 | 5 4472218 3954635 | 1 up @132 ~127 | 127 -72115 1394605 | 5 4472218 3954635
#|1 up @248 ~220 | 220 49462 1303712 | 28 1321198 1390796 | 1 up @248 ~220 | 220 49462 1303712 | 28 1321198 1390796
#|1 up @248 ~220 | 220 49462 1303712 | 28 1321198 1390796 | 1 up @248 ~220 | 220 49462 1303712 | 28 1321198 1390796
#|1 up @248 ~220 | 220 49462 1303712 | 28 1321198 1390796 | 1 up @248 ~220 | 220 49462 1303712 | 28 1321198 1390796
#|1 up @248 ~220 | 220 49462 1303712 | 28 1321198 1390796 | 1 up @248 ~220 | 220 49462 1303712 | 28 1321198 1390796
#|9
#|7
#|15
#|19
#|1
#|1
#|0
#|0
#|0
#|0
#|11
#|300 300 -87334 1319236
#|83 83 2081533 1362903
#|168 168 4059630 1247890
#|52 52 2096463 1372171
#|up
#|down
#|14529495
#|1452950
#|3705028
#|3705028
#|10275617
#|1512572
#|0
#|1
#|0
#|1
#|1
#|1
#|0
#|1
#|0
#|0
