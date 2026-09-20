# Scan: running totals over a Vec, and what falls out of them. scan / scan_ex
# (inclusive / exclusive, any operator), segmented (the total restarts at every
# head), filter and compact (keep-to-dense), rle (runs to values and counts).
# scan_ex over counts is offsets: the CSR row table, a partition's write
# positions, a frontier's slots.
#
# Written for the compiled lanes: every one is a single left-to-right index loop,
# in place where the output is no longer than the input (scan, segmented, filter,
# compact all are); the operator and the predicate are template parameters, so
# each instance compiles with them inline. Not a fork tree: an Array pays a full
# copy per fork level (docs/omen/lanes/power-1.md), and an add is a nanosecond.
# One loop is also the one fixed order, so a scan of a non-associative operator
# has one answer on every lane and every schedule.
import Base
import ./vec.bend as Vec

# scan: y[i] = f(y[i-1], x[i]), y[-1] = id. The total comes back beside the Vec.
def scan.set(+i: U32, v: Vec.Vec, +y: U32) -> Vec.Vec & U32:
  (Vec.put(v, i, y), y)

def scan.put(~f: U32 -> U32 -> U32, +i: U32, acc: U32, r: Vec.Vec & U32) -> Vec.Vec & U32:
  (v, x) = r
  scan.set(i, v, f(acc, x))

def scan.step(~f: U32 -> U32 -> U32, +i: U32, va: Vec.Vec & U32) -> Vec.Vec & U32:
  (v, acc) = va
  scan.put(~f, i, acc, Vec.at(v, i))

def scan.go(~f: U32 -> U32 -> U32, fuel: Nat, +i: U32, va: Vec.Vec & U32) -> Vec.Vec & U32:
  match fuel:
    case 0n:
      va
    case 1n++p:
      scan.go(~f, p, U32.inc(i), scan.step(~f, i, va))

def scan.len(~f: U32 -> U32 -> U32, id: U32, r: Vec.Vec & U32) -> Vec.Vec & U32:
  (v, n) = r
  scan.go(~f, U32.to_nat(n), 0, (v, id))

def scan(~f: U32 -> U32 -> U32, id: U32, v: Vec.Vec) -> Vec.Vec & U32:
  scan.len(~f, id, Vec.len(v))

# scan_ex: y[i] = f(... f(id, x[0]) ..., x[i-1]); the total is the element past
# the end
def scan_ex.put(~f: U32 -> U32 -> U32, +i: U32, +acc: U32, r: Vec.Vec & U32) -> Vec.Vec & U32:
  (v, x) = r
  (Vec.put(v, i, acc), f(acc, x))

def scan_ex.step(~f: U32 -> U32 -> U32, +i: U32, va: Vec.Vec & U32) -> Vec.Vec & U32:
  (v, acc) = va
  scan_ex.put(~f, i, acc, Vec.at(v, i))

def scan_ex.go(~f: U32 -> U32 -> U32, fuel: Nat, +i: U32, va: Vec.Vec & U32) -> Vec.Vec & U32:
  match fuel:
    case 0n:
      va
    case 1n++p:
      scan_ex.go(~f, p, U32.inc(i), scan_ex.step(~f, i, va))

def scan_ex.len(~f: U32 -> U32 -> U32, id: U32, r: Vec.Vec & U32) -> Vec.Vec & U32:
  (v, n) = r
  scan_ex.go(~f, U32.to_nat(n), 0, (v, id))

def scan_ex(~f: U32 -> U32 -> U32, id: U32, v: Vec.Vec) -> Vec.Vec & U32:
  scan_ex.len(~f, id, Vec.len(v))

# the two every caller wants: prefix sums, and counts to offsets
def sums(v: Vec.Vec) -> Vec.Vec & U32:
  scan(~U32.add, 0, v)

def offsets(v: Vec.Vec) -> Vec.Vec & U32:
  scan_ex(~U32.add, 0, v)

# segmented: a scan that restarts from id wherever heads[i] is not zero
type Seg is Type:
  Seg{v: Vec.Vec, heads: Vec.Vec, acc: U32}

def seg.from(head: Bool, id: U32, acc: U32) -> U32:
  match head:
    case True{}:
      id
    case False{}:
      acc

def seg.set(+i: U32, hs: Vec.Vec, r: Vec.Vec & U32) -> Seg:
  (v, y) = r
  Seg{v, hs, y}

def seg.put(~f: U32 -> U32 -> U32, +i: U32, hs: Vec.Vec, from: U32, r: Vec.Vec & U32) -> Seg:
  (v, x) = r
  seg.set(i, hs, scan.set(i, v, f(from, x)))

def seg.head(~f: U32 -> U32 -> U32, +i: U32, id: U32, v: Vec.Vec, acc: U32, r: Vec.Vec & U32) -> Seg:
  (hs, h) = r
  seg.put(~f, i, hs, seg.from(U32.is_ne(h, 0), id, acc), Vec.at(v, i))

def seg.go(~f: U32 -> U32 -> U32, fuel: Nat, +i: U32, +id: U32, s: Seg) -> Seg:
  match fuel:
    case 0n:
      s
    case 1n++p:
      match s:
        case Seg{v, hs, acc}:
          seg.go(~f, p, U32.inc(i), id, seg.head(~f, i, id, v, acc, Vec.at(hs, i)))

def seg.fin(s: Seg) -> Vec.Vec & Vec.Vec:
  match s:
    case Seg{v, hs, acc}:
      (v, hs)

def seg.len(~f: U32 -> U32 -> U32, +id: U32, hs: Vec.Vec, r: Vec.Vec & U32) -> Vec.Vec & Vec.Vec:
  (v, n) = r
  seg.fin(seg.go(~f, U32.to_nat(n), 0, id, Seg{v, hs, id}))

# the values scanned, and the heads handed back
def segmented(~f: U32 -> U32 -> U32, +id: U32, v: Vec.Vec, heads: Vec.Vec) -> Vec.Vec & Vec.Vec:
  seg.len(~f, id, heads, Vec.len(v))

# filter: the elements p holds for, dense, in order, in place (the write index
# never passes the read index)
def filter.if(v: Vec.Vec, +j: U32, x: U32, keep: Bool) -> Vec.Vec & U32:
  match keep:
    case True{}:
      (Vec.put(v, j, x), U32.inc(j))
    case False{}:
      (v, j)

def filter.got(~p: U32 -> Bool, j: U32, r: Vec.Vec & U32) -> Vec.Vec & U32:
  (v, +x) = r
  filter.if(v, j, x, p(x))

def filter.step(~p: U32 -> Bool, +i: U32, vj: Vec.Vec & U32) -> Vec.Vec & U32:
  (v, j) = vj
  filter.got(~p, j, Vec.at(v, i))

def filter.go(~p: U32 -> Bool, fuel: Nat, +i: U32, vj: Vec.Vec & U32) -> Vec.Vec & U32:
  match fuel:
    case 0n:
      vj
    case 1n++p1:
      filter.go(~p, p1, U32.inc(i), filter.step(~p, i, vj))

def filter.fin(vj: Vec.Vec & U32) -> Vec.Vec:
  (v, j) = vj
  Vec.truncate(v, j)

def filter.len(~p: U32 -> Bool, r: Vec.Vec & U32) -> Vec.Vec:
  (v, n) = r
  filter.fin(filter.go(~p, U32.to_nat(n), 0, (v, 0)))

def filter(~p: U32 -> Bool, v: Vec.Vec) -> Vec.Vec:
  filter.len(~p, Vec.len(v))

# compact: the elements whose flag is not zero; the flags are handed back
type Cmp is Type:
  Cmp{v: Vec.Vec, flags: Vec.Vec, j: U32}

def compact.fin(fs: Vec.Vec, vj: Vec.Vec & U32) -> Cmp:
  (v, j) = vj
  Cmp{v, fs, j}

def compact.got(fs: Vec.Vec, j: U32, keep: Bool, r: Vec.Vec & U32) -> Cmp:
  (v, x) = r
  compact.fin(fs, filter.if(v, j, x, keep))

def compact.flag(+i: U32, v: Vec.Vec, j: U32, r: Vec.Vec & U32) -> Cmp:
  (fs, f) = r
  compact.got(fs, j, U32.is_ne(f, 0), Vec.at(v, i))

def compact.go(fuel: Nat, +i: U32, c: Cmp) -> Cmp:
  match fuel:
    case 0n:
      c
    case 1n++p:
      match c:
        case Cmp{v, fs, j}:
          compact.go(p, U32.inc(i), compact.flag(i, v, j, Vec.at(fs, i)))

def compact.out(c: Cmp) -> Vec.Vec & Vec.Vec:
  match c:
    case Cmp{v, fs, j}:
      (Vec.truncate(v, j), fs)

def compact.len(fs: Vec.Vec, r: Vec.Vec & U32) -> Vec.Vec & Vec.Vec:
  (v, n) = r
  compact.out(compact.go(U32.to_nat(n), 0, Cmp{v, fs, 0}))

def compact(v: Vec.Vec, flags: Vec.Vec) -> Vec.Vec & Vec.Vec:
  compact.len(flags, Vec.len(v))

# rle: the runs of v as (values, counts); v is spent
type Rle is Type:
  Rle{v: Vec.Vec, vals: Vec.Vec, cnts: Vec.Vec, prev: U32, run: U32}

def rle.if(v: Vec.Vec, vals: Vec.Vec, cnts: Vec.Vec, prev: U32, run: U32, x: U32, same: Bool) -> Rle:
  match same:
    case True{}:
      Rle{v, vals, cnts, prev, U32.inc(run)}
    case False{}:
      Rle{v, Vec.push(vals, prev), Vec.push(cnts, run), x, 1}

def rle.got(vals: Vec.Vec, cnts: Vec.Vec, +prev: U32, run: U32, r: Vec.Vec & U32) -> Rle:
  (v, +x) = r
  rle.if(v, vals, cnts, prev, run, x, U32.is_eq(x, prev))

def rle.go(fuel: Nat, +i: U32, s: Rle) -> Rle:
  match fuel:
    case 0n:
      s
    case 1n++p:
      match s:
        case Rle{v, vals, cnts, prev, run}:
          rle.go(p, U32.inc(i), rle.got(vals, cnts, prev, run, Vec.at(v, i)))

def rle.fin(s: Rle) -> Vec.Vec & Vec.Vec:
  match s:
    case Rle{v, vals, cnts, prev, run}:
      (Vec.push(vals, prev), Vec.push(cnts, run))

# the first element opens the first run; the loop takes the rest
def rle.first(+n: U32, r: Vec.Vec & U32) -> Vec.Vec & Vec.Vec:
  (v, x) = r
  rle.fin(rle.go(U32.to_nat(U32.sub(n, 1)), 1, Rle{v, Vec.new(0), Vec.new(0), x, 1}))

def rle.if0(+n: U32, v: Vec.Vec, empty: Bool) -> Vec.Vec & Vec.Vec:
  match empty:
    case True{}:
      (Vec.new(0), Vec.new(0))
    case False{}:
      rle.first(n, Vec.at(v, 0))

def rle.len(r: Vec.Vec & U32) -> Vec.Vec & Vec.Vec:
  (v, +n) = r
  rle.if0(n, v, U32.is_zero(n))

def rle(v: Vec.Vec) -> Vec.Vec & Vec.Vec:
  rle.len(Vec.len(v))
