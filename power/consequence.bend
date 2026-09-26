# Consequence: group readings of an ambiguous request by what they would do.
#
# A request with N readings does not need an N-way question. Run each reading
# through a deterministic preview and you get N action traces; two readings
# whose traces agree are the same reading as far as the world is concerned, so
# asking which one was meant is a question with one answer. collapse keeps one
# representative a distinct trace, and the question a caller asks then has
# exactly as many branches as there are outcomes -- often one, which is no
# question at all.
#
# The preview is the caller's: this file never runs it. It takes the traces it
# produced and answers "how many different things could happen, and which
# reading stands for each".
#
# Written for the compiled lanes: a Vec holds an Array, so it is kind Type and
# cannot sit inside another Vec -- the N traces arrive concatenated with their
# lengths beside them, the CSR shape the rest of power uses. The per-trace
# digest is then one segmented scan over that one flat block (scan.bend), and
# the grouping is one stable sort_by_key plus one walk of the runs it makes
# adjacent (radix.bend). No nested loop anywhere, and nothing here allocates
# per trace.
import Base
import ./vec.bend as Vec
import ./scan.bend as Scan
import ./radix.bend as Radix
import ./sketch.bend as Sketch

# the distinct consequences, ascending by digest: what each one hashes to, the
# lowest-numbered reading that produces it, and how many readings do
type Groups is Type:
  Groups{keys: Vec.Vec, reps: Vec.Vec, cnts: Vec.Vec}

# -- the digest --------------------------------------------------------------

# 0, 1, .. n-1: the reading numbers, the payload the sort carries
def iota.go(fuel: Nat, +i: U32, v: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      v
    case 1n++p:
      iota.go(p, U32.inc(i), Vec.push(v, i))

def iota(n: U32) -> Vec.Vec:
  iota.go(U32.to_nat(n), 0, Vec.new(0))

# heads: one flag a cell over the flat block, set where a trace starts. An
# empty trace sets the flag its successor would have set, which is the same
# flag, so the marks stay correct and the cursor still lands right.
type Heads is Type:
  Heads{lens: Vec.Vec, hs: Vec.Vec, at: U32}

def heads.adv(hs: Vec.Vec, at: U32, r: Vec.Vec & U32) -> Heads:
  (lens, l) = r
  Heads{lens, hs, U32.add(at, l)}

def heads.put(at: U32, lens: Vec.Vec, i: U32, r: Vec.Vec & Bool) -> Heads:
  (hs, ok) = r
  heads.adv(hs, at, Vec.at(lens, i))

def heads.step(lens: Vec.Vec, hs: Vec.Vec, +at: U32, +i: U32) -> Heads:
  heads.put(at, lens, i, Vec.set(hs, at, 1))

def heads.go(fuel: Nat, +i: U32, s: Heads) -> Heads:
  match fuel:
    case 0n:
      s
    case 1n++p:
      match s:
        case Heads{lens, hs, at}:
          heads.go(p, U32.inc(i), heads.step(lens, hs, at, i))

def heads.fin(s: Heads) -> Vec.Vec & Vec.Vec:
  match s:
    case Heads{lens, hs, at}:
      (lens, hs)

def heads.n(total: U32, r: Vec.Vec & U32) -> Vec.Vec & Vec.Vec:
  (lens, n) = r
  heads.fin(heads.go(U32.to_nat(n), 0, Heads{lens, Radix.zeros(total), 0}))

def heads(lens: Vec.Vec, total: U32) -> Vec.Vec & Vec.Vec:
  heads.n(total, Vec.len(lens))

# gather: the scan wrote a running digest into every cell, so trace j's digest
# is the cell its last action landed in. A trace of no actions never reached a
# cell and keeps the seed, which is what "this reading does nothing" hashes to.
type Gath is Type:
  Gath{sc: Vec.Vec, lens: Vec.Vec, out: Vec.Vec, at: U32}

def gath.got(lens: Vec.Vec, at: U32, l: U32, out: Vec.Vec, r: Vec.Vec & U32) -> Gath:
  (sc, x) = r
  Gath{sc, lens, Vec.push(out, x), U32.add(at, l)}

def gath.take(sc: Vec.Vec, lens: Vec.Vec, +at: U32, out: Vec.Vec, seed: U32, +l: U32, empty: Bool) -> Gath:
  match empty:
    case True{}:
      Gath{sc, lens, Vec.push(out, seed), at}
    case False{}:
      gath.got(lens, at, l, out, Vec.at(sc, U32.sub(U32.add(at, l), 1)))

def gath.step(sc: Vec.Vec, out: Vec.Vec, seed: U32, at: U32, r: Vec.Vec & U32) -> Gath:
  (lens, +l) = r
  gath.take(sc, lens, at, out, seed, l, U32.is_zero(l))

def gath.go(fuel: Nat, +j: U32, +seed: U32, s: Gath) -> Gath:
  match fuel:
    case 0n:
      s
    case 1n++p:
      match s:
        case Gath{sc, lens, out, at}:
          gath.go(p, U32.inc(j), seed, gath.step(sc, out, seed, at, Vec.at(lens, j)))

def gath.fin(s: Gath) -> Vec.Vec:
  match s:
    case Gath{sc, lens, out, at}:
      out

def dig.run(seed: U32, sc: Vec.Vec, r: Vec.Vec & U32) -> Vec.Vec:
  (lens, n) = r
  gath.fin(gath.go(U32.to_nat(n), 0, seed, Gath{sc, lens, Vec.new(0), 0}))

def dig.fst(r: Vec.Vec & Vec.Vec) -> Vec.Vec:
  (sc, hs) = r
  sc

# the fold step, unmarked: a `~f` parameter takes a plain arrow, and hash's own
# binders are marked, so the scan needs this one-line face of it
def fold(acc: U32, x: U32) -> U32:
  Sketch.hash(acc, x)

# Murmur3's finalizer folded left, seeded: full avalanche a step, so a trace
# that differs anywhere differs everywhere, and order counts.
# ponytail: 32 bits, so two unrelated traces collide at ~2^-32 a pair and get
# merged into one group silently. A 64-bit digest (two lanes of this fold) is
# the upgrade if a caller ever previews enough readings to care.
def dig.seg(+seed: U32, lens: Vec.Vec, acts: Vec.Vec, hs: Vec.Vec) -> Vec.Vec:
  dig.run(seed, dig.fst(Scan.segmented(~fold, seed, acts, hs)), Vec.len(lens))

def dig.heads(seed: U32, acts: Vec.Vec, r: Vec.Vec & Vec.Vec) -> Vec.Vec:
  (lens, hs) = r
  dig.seg(seed, lens, acts, hs)

def dig.total(seed: U32, lens: Vec.Vec, r: Vec.Vec & U32) -> Vec.Vec:
  (acts, total) = r
  dig.heads(seed, acts, heads(lens, total))

# one digest a reading, from the N traces laid end to end and their lengths
def digest(seed: U32, acts: Vec.Vec, lens: Vec.Vec) -> Vec.Vec:
  dig.total(seed, lens, Vec.len(acts))

# -- the grouping ------------------------------------------------------------

# sort_by_key is stable, so the readings inside a run stay in reading order and
# the first of a run is the lowest-numbered reading that reaches that outcome
type Runs is Type:
  Runs{k: Vec.Vec, v: Vec.Vec, g: Groups, key: U32, rep: U32, run: U32}

def runs.push(k: Vec.Vec, v: Vec.Vec, g: Groups, key: U32, rep: U32, run: U32, x: U32, y: U32) -> Runs:
  match g:
    case Groups{keys, reps, cnts}:
      Runs{k, v, Groups{Vec.push(keys, key), Vec.push(reps, rep), Vec.push(cnts, run)}, x, y, 1}

def runs.if(k: Vec.Vec, v: Vec.Vec, g: Groups, key: U32, rep: U32, +run: U32, x: U32, y: U32, same: Bool) -> Runs:
  match same:
    case True{}:
      Runs{k, v, g, key, rep, U32.inc(run)}
    case False{}:
      runs.push(k, v, g, key, rep, run, x, y)

def runs.got(k: Vec.Vec, g: Groups, +key: U32, rep: U32, run: U32, +x: U32, r: Vec.Vec & U32) -> Runs:
  (v, y) = r
  runs.if(k, v, g, key, rep, run, x, y, U32.is_eq(x, key))

def runs.step(v: Vec.Vec, g: Groups, key: U32, rep: U32, run: U32, i: U32, r: Vec.Vec & U32) -> Runs:
  (k, x) = r
  runs.got(k, g, key, rep, run, x, Vec.at(v, i))

def runs.go(fuel: Nat, +i: U32, s: Runs) -> Runs:
  match fuel:
    case 0n:
      s
    case 1n++p:
      match s:
        case Runs{k, v, g, key, rep, run}:
          runs.go(p, U32.inc(i), runs.step(v, g, key, rep, run, i, Vec.at(k, i)))

def runs.fin(s: Runs) -> Groups:
  match s:
    case Runs{k, v, g, key, rep, run}:
      match g:
        case Groups{keys, reps, cnts}:
          Groups{Vec.push(keys, key), Vec.push(reps, rep), Vec.push(cnts, run)}

def runs.open(k: Vec.Vec, n: U32, key: U32, r: Vec.Vec & U32) -> Groups:
  (v, rep) = r
  runs.fin(runs.go(U32.to_nat(U32.sub(n, 1)), 1, Runs{k, v, Groups{Vec.new(0), Vec.new(0), Vec.new(0)}, key, rep, 1}))

def runs.first(v: Vec.Vec, n: U32, r: Vec.Vec & U32) -> Groups:
  (k, key) = r
  runs.open(k, n, key, Vec.at(v, 0))

def runs.if0(k: Vec.Vec, v: Vec.Vec, n: U32, empty: Bool) -> Groups:
  match empty:
    case True{}:
      Groups{Vec.new(0), Vec.new(0), Vec.new(0)}
    case False{}:
      runs.first(v, n, Vec.at(k, 0))

def runs.len(v: Vec.Vec, r: Vec.Vec & U32) -> Groups:
  (k, +n) = r
  runs.if0(k, v, n, U32.is_zero(n))

def runs.pairs(r: Vec.Vec & Vec.Vec) -> Groups:
  (k, v) = r
  runs.len(v, Vec.len(k))

def collapse.idx(r: Vec.Vec & U32) -> Groups:
  (digs, n) = r
  runs.pairs(Radix.sort_by_key(digs, iota(n)))

# the distinct consequences of N readings, given one digest a reading
def collapse(digs: Vec.Vec) -> Groups:
  collapse.idx(Vec.len(digs))

# the whole move: N previews in, the questions worth asking out
def collapse_traces(seed: U32, acts: Vec.Vec, lens: Vec.Vec) -> Groups:
  collapse(digest(seed, acts, lens))

# -- reading the answer ------------------------------------------------------

def count.k(reps: Vec.Vec, cnts: Vec.Vec, r: Vec.Vec & U32) -> Groups & U32:
  (keys, n) = r
  (Groups{keys, reps, cnts}, n)

# how many different things could happen
def count(g: Groups) -> Groups & U32:
  match g:
    case Groups{keys, reps, cnts}:
      count.k(reps, cnts, Vec.len(keys))

def settled.eq(g: Groups, +n: U32) -> Groups & Bool:
  (g, U32.is_eq(n, 1))

def settled.n(r: Groups & U32) -> Groups & Bool:
  (g, n) = r
  settled.eq(g, n)

# True when every reading does the same thing, so there is nothing to ask
def settled(g: Groups) -> Groups & Bool:
  settled.n(count(g))

# the readings to offer, and how many readings each one stands for
def representatives(g: Groups) -> Vec.Vec & Vec.Vec:
  match g:
    case Groups{keys, reps, cnts}:
      (reps, cnts)
