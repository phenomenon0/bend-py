# Radix: counting sort by a bucket function, and the four passes of it that sort
# a full 32-bit key. histogram counts a Vec by any key function; sort is stable
# LSD radix, eight bits a pass; unique and tally are sort plus Scan.rle.
#
# Written for the compiled lanes: the bucket function is a template parameter, so
# each pass compiles with its shift as a literal -- a shift threaded as a runtime
# Nat would make U32.shrn a 24-step loop per element. Two buffers ping-pong,
# allocated once and reused by all four passes (four is even, so the answer comes
# back in the caller's own buffer). Every pass is two index loops, no fork: an
# Array pays a full copy per fork level (power-1) and a parallel call anywhere
# taxes the whole program ~3x (power-3), which counting an add cannot repay.
import Base
import ./vec.bend as Vec
import ./scan.bend as Scan

# a Vec of n zeros: the count table, and the pass's output buffer
def zeros.go(fuel: Nat, v: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      v
    case 1n++p:
      zeros.go(p, Vec.push(v, 0))

def zeros(n: U32) -> Vec.Vec:
  zeros.go(U32.to_nat(n), Vec.new(0))

# histogram: how many of v fall in each of `buckets` buckets, by key. The Vec
# comes back untouched beside the table. Scan.offsets of the table is where each
# bucket starts -- the CSR row pointers, the scatter's write cursors.
type Hist is Type:
  Hist{v: Vec.Vec, cnts: Vec.Vec}

def hist.at(v: Vec.Vec, d: U32, r: Vec.Vec & U32) -> Hist:
  (cnts, c) = r
  Hist{v, Vec.put(cnts, d, U32.inc(c))}

def hist.dig(v: Vec.Vec, cnts: Vec.Vec, +d: U32) -> Hist:
  hist.at(v, d, Vec.at(cnts, d))

def hist.got(~key: U32 -> U32, cnts: Vec.Vec, r: Vec.Vec & U32) -> Hist:
  (v, x) = r
  hist.dig(v, cnts, key(x))

def hist.go(~key: U32 -> U32, fuel: Nat, +i: U32, h: Hist) -> Hist:
  match fuel:
    case 0n:
      h
    case 1n++p:
      match h:
        case Hist{v, cnts}:
          hist.go(~key, p, U32.inc(i), hist.got(~key, cnts, Vec.at(v, i)))

def hist.fin(h: Hist) -> Vec.Vec & Vec.Vec:
  match h:
    case Hist{v, cnts}:
      (v, cnts)

def hist.len(~key: U32 -> U32, buckets: U32, r: Vec.Vec & U32) -> Vec.Vec & Vec.Vec:
  (v, n) = r
  hist.fin(hist.go(~key, U32.to_nat(n), 0, Hist{v, zeros(buckets)}))

def histogram(~key: U32 -> U32, buckets: U32, v: Vec.Vec) -> Vec.Vec & Vec.Vec:
  hist.len(~key, buckets, Vec.len(v))

# the four digits of a 32-bit key, least significant first. Literal shifts.
def d0(x: U32) -> U32:
  U32.and(x, 255)

def d8(x: U32) -> U32:
  U32.and(U32.shrn(x, 8n), 255)

def d16(x: U32) -> U32:
  U32.and(U32.shrn(x, 16n), 255)

def d24(x: U32) -> U32:
  U32.shrn(x, 24n)

# the counts of v, scanned into write cursors
def offs.drop(r: Vec.Vec & U32) -> Vec.Vec:
  (offs, total) = r
  offs

def offs.of(r: Vec.Vec & Vec.Vec) -> Vec.Vec & Vec.Vec:
  (v, cnts) = r
  (v, offs.drop(Scan.offsets(cnts)))

# scatter: one counting-sort pass. Each element lands at its bucket's next free
# slot, so the pass is stable and four of them compose into a sort.
type Pass is Type:
  Pass{v: Vec.Vec, offs: Vec.Vec, out: Vec.Vec}

def scat.put(v: Vec.Vec, offs: Vec.Vec, out: Vec.Vec, d: U32, +at: U32, x: U32) -> Pass:
  Pass{v, Vec.put(offs, d, U32.inc(at)), Vec.put(out, at, x)}

def scat.slot(v: Vec.Vec, out: Vec.Vec, d: U32, x: U32, r: Vec.Vec & U32) -> Pass:
  (offs, at) = r
  scat.put(v, offs, out, d, at, x)

def scat.dig(v: Vec.Vec, offs: Vec.Vec, out: Vec.Vec, x: U32, +d: U32) -> Pass:
  scat.slot(v, out, d, x, Vec.at(offs, d))

def scat.got(~key: U32 -> U32, offs: Vec.Vec, out: Vec.Vec, r: Vec.Vec & U32) -> Pass:
  (v, +x) = r
  scat.dig(v, offs, out, x, key(x))

def scat.go(~key: U32 -> U32, fuel: Nat, +i: U32, p: Pass) -> Pass:
  match fuel:
    case 0n:
      p
    case 1n++q:
      match p:
        case Pass{v, offs, out}:
          scat.go(~key, q, U32.inc(i), scat.got(~key, offs, out, Vec.at(v, i)))

# the buffers come back swapped: what was written is the next pass's input, and
# the cursor table is spent
def scat.fin(p: Pass) -> Vec.Vec & Vec.Vec:
  match p:
    case Pass{v, offs, out}:
      (out, v)

def pass.n(~key: U32 -> U32, out: Vec.Vec, offs: Vec.Vec, r: Vec.Vec & U32) -> Vec.Vec & Vec.Vec:
  (v, n) = r
  scat.fin(scat.go(~key, U32.to_nat(n), 0, Pass{v, offs, out}))

def pass.on(~key: U32 -> U32, out: Vec.Vec, r: Vec.Vec & Vec.Vec) -> Vec.Vec & Vec.Vec:
  (v, offs) = r
  pass.n(~key, out, offs, Vec.len(v))

def pass(~key: U32 -> U32, v: Vec.Vec, out: Vec.Vec) -> Vec.Vec & Vec.Vec:
  pass.on(~key, out, offs.of(histogram(~key, 256, v)))

# sort: four passes, eight bits each, least significant first
def sort.p4(r: Vec.Vec & Vec.Vec) -> Vec.Vec & Vec.Vec:
  (v, out) = r
  pass(~d24, v, out)

def sort.p3(r: Vec.Vec & Vec.Vec) -> Vec.Vec & Vec.Vec:
  (v, out) = r
  sort.p4(pass(~d16, v, out))

def sort.p2(r: Vec.Vec & Vec.Vec) -> Vec.Vec & Vec.Vec:
  (v, out) = r
  sort.p3(pass(~d8, v, out))

def sort.fst(r: Vec.Vec & Vec.Vec) -> Vec.Vec:
  (v, scratch) = r
  v

def sort.len(r: Vec.Vec & U32) -> Vec.Vec:
  (v, n) = r
  sort.fst(sort.p2(pass(~d0, v, zeros(n))))

def sort(v: Vec.Vec) -> Vec.Vec:
  sort.len(Vec.len(v))

# tally: every distinct value of v, ascending, and how many times it occurs --
# sort, then Scan.rle, whose runs are exactly the groups
def tally(v: Vec.Vec) -> Vec.Vec & Vec.Vec:
  Scan.rle(sort(v))

def unique.fst(r: Vec.Vec & Vec.Vec) -> Vec.Vec:
  (vals, cnts) = r
  vals

def unique(v: Vec.Vec) -> Vec.Vec:
  unique.fst(tally(v))

# sort_by_key: the same four passes moving a second Vec alongside, so a value
# rides with its key. The two scratch buffers stay in the record and the roles
# swap each pass, so four passes allocate twice and no more.
type Pair is Type:
  Pair{k: Vec.Vec, v: Vec.Vec, offs: Vec.Vec, ko: Vec.Vec, vo: Vec.Vec}

def pscat.put(k: Vec.Vec, v: Vec.Vec, offs: Vec.Vec, ko: Vec.Vec, vo: Vec.Vec, d: U32, +at: U32, x: U32, y: U32) -> Pair:
  Pair{k, v, Vec.put(offs, d, U32.inc(at)), Vec.put(ko, at, x), Vec.put(vo, at, y)}

def pscat.slot(k: Vec.Vec, v: Vec.Vec, ko: Vec.Vec, vo: Vec.Vec, d: U32, x: U32, y: U32, r: Vec.Vec & U32) -> Pair:
  (offs, at) = r
  pscat.put(k, v, offs, ko, vo, d, at, x, y)

def pscat.dig(k: Vec.Vec, v: Vec.Vec, offs: Vec.Vec, ko: Vec.Vec, vo: Vec.Vec, x: U32, y: U32, +d: U32) -> Pair:
  pscat.slot(k, v, ko, vo, d, x, y, Vec.at(offs, d))

def pscat.val(~key: U32 -> U32, k: Vec.Vec, offs: Vec.Vec, ko: Vec.Vec, vo: Vec.Vec, +x: U32, r: Vec.Vec & U32) -> Pair:
  (v, y) = r
  pscat.dig(k, v, offs, ko, vo, x, y, key(x))

def pscat.got(~key: U32 -> U32, v: Vec.Vec, offs: Vec.Vec, ko: Vec.Vec, vo: Vec.Vec, +i: U32, r: Vec.Vec & U32) -> Pair:
  (k, x) = r
  pscat.val(~key, k, offs, ko, vo, x, Vec.at(v, i))

def pscat.go(~key: U32 -> U32, fuel: Nat, +i: U32, p: Pair) -> Pair:
  match fuel:
    case 0n:
      p
    case 1n++q:
      match p:
        case Pair{k, v, offs, ko, vo}:
          pscat.go(~key, q, U32.inc(i), pscat.got(~key, v, offs, ko, vo, i, Vec.at(k, i)))

# what was written becomes the next pass's input; the spent table is dropped and
# the next pass's counts take its place
def ppass.swap(p: Pair) -> Pair:
  match p:
    case Pair{k, v, offs, ko, vo}:
      Pair{ko, vo, offs, k, v}

def ppass.set(v: Vec.Vec, ko: Vec.Vec, vo: Vec.Vec, r: Vec.Vec & Vec.Vec) -> Pair:
  (k, offs) = r
  Pair{k, v, offs, ko, vo}

def ppass.cnt(~key: U32 -> U32, p: Pair) -> Pair:
  match p:
    case Pair{k, v, offs, ko, vo}:
      ppass.set(v, ko, vo, offs.of(histogram(~key, 256, k)))

def ppass(~key: U32 -> U32, +n: U32, p: Pair) -> Pair:
  ppass.swap(pscat.go(~key, U32.to_nat(n), 0, ppass.cnt(~key, p)))

def sort_by_key.fin(p: Pair) -> Vec.Vec & Vec.Vec:
  match p:
    case Pair{k, v, offs, ko, vo}:
      (k, v)

def sort_by_key.n(+n: U32, k: Vec.Vec, v: Vec.Vec) -> Vec.Vec & Vec.Vec:
  sort_by_key.fin(ppass(~d24, n, ppass(~d16, n, ppass(~d8, n, ppass(~d0, n, Pair{k, v, Vec.new(0), zeros(n), zeros(n)})))))

def sort_by_key.len(v: Vec.Vec, r: Vec.Vec & U32) -> Vec.Vec & Vec.Vec:
  (k, +n) = r
  sort_by_key.n(n, k, v)

def sort_by_key(keys: Vec.Vec, vals: Vec.Vec) -> Vec.Vec & Vec.Vec:
  sort_by_key.len(vals, Vec.len(keys))

# reduce_by_key: sort the pairs, then fold each run of equal keys with f. One
# walk, not a segmented scan -- the runs are already adjacent.
type Red is Type:
  Red{k: Vec.Vec, v: Vec.Vec, ks: Vec.Vec, vs: Vec.Vec, key: U32, acc: U32}

def red.if(~f: U32 -> U32 -> U32, k: Vec.Vec, v: Vec.Vec, ks: Vec.Vec, vs: Vec.Vec, key: U32, acc: U32, x: U32, y: U32, same: Bool) -> Red:
  match same:
    case True{}:
      Red{k, v, ks, vs, key, f(acc, y)}
    case False{}:
      Red{k, v, Vec.push(ks, key), Vec.push(vs, acc), x, y}

def red.got(~f: U32 -> U32 -> U32, k: Vec.Vec, ks: Vec.Vec, vs: Vec.Vec, +key: U32, acc: U32, +x: U32, r: Vec.Vec & U32) -> Red:
  (v, y) = r
  red.if(~f, k, v, ks, vs, key, acc, x, y, U32.is_eq(x, key))

def red.step(~f: U32 -> U32 -> U32, v: Vec.Vec, ks: Vec.Vec, vs: Vec.Vec, key: U32, acc: U32, +i: U32, r: Vec.Vec & U32) -> Red:
  (k, x) = r
  red.got(~f, k, ks, vs, key, acc, x, Vec.at(v, i))

def red.go(~f: U32 -> U32 -> U32, fuel: Nat, +i: U32, s: Red) -> Red:
  match fuel:
    case 0n:
      s
    case 1n++p:
      match s:
        case Red{k, v, ks, vs, key, acc}:
          red.go(~f, p, U32.inc(i), red.step(~f, v, ks, vs, key, acc, i, Vec.at(k, i)))

def red.fin(s: Red) -> Vec.Vec & Vec.Vec:
  match s:
    case Red{k, v, ks, vs, key, acc}:
      (Vec.push(ks, key), Vec.push(vs, acc))

def red.open(~f: U32 -> U32 -> U32, k: Vec.Vec, n: U32, key: U32, r: Vec.Vec & U32) -> Vec.Vec & Vec.Vec:
  (v, y) = r
  red.fin(red.go(~f, U32.to_nat(U32.sub(n, 1)), 1, Red{k, v, Vec.new(0), Vec.new(0), key, y}))

def red.first(~f: U32 -> U32 -> U32, v: Vec.Vec, n: U32, r: Vec.Vec & U32) -> Vec.Vec & Vec.Vec:
  (k, key) = r
  red.open(~f, k, n, key, Vec.at(v, 0))

def red.if0(~f: U32 -> U32 -> U32, k: Vec.Vec, v: Vec.Vec, n: U32, empty: Bool) -> Vec.Vec & Vec.Vec:
  match empty:
    case True{}:
      (Vec.new(0), Vec.new(0))
    case False{}:
      red.first(~f, v, n, Vec.at(k, 0))

def red.len(~f: U32 -> U32 -> U32, v: Vec.Vec, r: Vec.Vec & U32) -> Vec.Vec & Vec.Vec:
  (k, +n) = r
  red.if0(~f, k, v, n, U32.is_zero(n))

def red.pairs(~f: U32 -> U32 -> U32, r: Vec.Vec & Vec.Vec) -> Vec.Vec & Vec.Vec:
  (k, v) = r
  red.len(~f, v, Vec.len(k))

# the distinct keys, ascending, and their values folded by f
def reduce_by_key(~f: U32 -> U32 -> U32, keys: Vec.Vec, vals: Vec.Vec) -> Vec.Vec & Vec.Vec:
  red.pairs(~f, sort_by_key(keys, vals))
