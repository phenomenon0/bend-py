# drift, sequential: one Page-Hinkley detector walked over 33,554,432 samples of
# a square wave, firing and re-arming every time the level moves. This is the
# lane's headline loop and it does not fork -- a changepoint detector is a scan,
# each step reading the state the step before it wrote. drift_par.bend is where
# the threads are, over the half of this lane that IS associative: the Welford
# merge.
#
# The checksum is deliberately expensive to agree on. It mixes, for every alarm,
# the index it fired at, the changepoint it estimated, and the QUANTIZED means of
# the before and after windows -- so twin_drift.c only prints this number if its
# Welford recurrence, its tail (the after window is an algebraic difference, not
# a buffer) and its Page-Hinkley state machine all agree with Bend's to the last
# bit of an F64. A reassociated sum would not.
import Base
import ../../../power/drift.bend as D

def h.fin2(+v: U32) -> U32:
  U32.xor(v, U32.shrn(v, 13n))

def h.fin(+u: U32) -> U32:
  h.fin2(U32.mul(U32.xor(u, U32.shrn(u, 15n)), 2246822519))

def h(+p: U32) -> U32:
  h.fin(U32.mul(U32.inc(p), 2654435761))

# noise in [-2, 2) in steps of 1/2048: an integer under 2^13 cast to F64 and
# divided by a power of two, so the twin starts from identical floats
def nz(+p: U32) -> F64:
  F64.div(F64.sub(U32.to_f64(U32.shrn(h(p), 19n)), 4096.0d), 2048.0d)

# a square wave of amplitude 3 with a half period of 65,536: 512 level changes
# over the run, so the detector spends its life alarming and re-arming instead
# of sitting in one long quiet stretch
def sq(+p: U32) -> F64:
  F64.add(F64.mul(3.0d, U32.to_f64(U32.and(U32.shrn(p, 16n), 1))), nz(p))

def rot7(+v: U32) -> U32:
  U32.or(U32.shln(v, 7n), U32.shrn(v, 25n))

def mix(+acc: U32, +x: U32) -> U32:
  rot7(U32.add(U32.mul(acc, 31), x))

# F64.round is floor(x + 0.5) in base.bend, so the twin writes floor, not round.
# The shift by 8 keeps every mean this bench sees inside f64_to_u32's range.
def qu(+x: F64) -> U32:
  F64.to_u32(F64.floor(F64.add(F64.mul(F64.add(x, 8.0d), 1048576.0d), 0.5d)))

type Acc is Data:
  Acc{d: D.PH, s: U32}

def land.ev(e: D.Ev, +s: U32) -> U32:
  match e:
    case D.Ev{dir, at, since, before, after}:
      mix(mix(mix(mix(s, at), since), qu(D.mean(before))), qu(D.mean(after)))

def land(r: D.PH & Maybe<&2, D.Ev>, +s: U32) -> Acc:
  (d, m) = r
  match m:
    case None{}:
      Acc{d, s}
    case Some{e}:
      Acc{d, land.ev(e, s)}

def go(i: Nat, +p: U32, a: Acc) -> Acc:
  match i:
    case 0n:
      a
    case 1n++k:
      match a:
        case Acc{d, s}:
          go(k, U32.inc(p), land(D.step(d, sq(p)), s))

def out(a: Acc) -> U32:
  match a:
    case Acc{d, s}:
      mix(s, D.seen(d))

def main() -> U32:
  out(go(33554432n, 0, Acc{D.new(D.Up{}, 0.5d, 16.0d, 30), 0}))
