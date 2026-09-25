# Assign: the cheapest one-to-one matching of rows to columns of a U32 cost
# matrix, and the dual prices that prove it is the cheapest. Jonker-Volgenant
# by shortest augmenting path, O(nr^2 * nc): each row in turn grows the matching
# along a cheapest alternating path, which is a Dijkstra over reduced costs.
# SciPy's linear_sum_assignment is the same algorithm and is the oracle.
#
# The answer is not only the matching. `u` and `w` are the dual prices, and
#
#     u[i] <= c[i][j] + w[j]  at every cell,  with equality on every assigned
#     cell, and w[j] = 0 at every column left over
#
# is a certificate that no matching is cheaper: it is LP duality, and checking
# it is one pass over the matrix, O(nr * nc), against O(nr^2 * nc) to solve
# again. `certify` is that pass. A consumer that does not trust this file can
# run it; a consumer that ships the answer somewhere else can ship the prices
# with it and let the far end check.
#
# Signs. The row price is >= 0 and the column price is <= 0 at every step of
# this algorithm, and a Vec holds U32, so the column price is stored negated:
# w[j] = -v[j] >= 0. Every reduced cost is then read as c[i][j] + w[j] - u[i],
# and dual feasibility is exactly what keeps that subtraction from going under.
# Nothing signed is ever stored, and no cell of the matrix is ever negated.
#
# The ceiling that buys it: `big` = 2^31. A cost at or above `big` is a
# forbidden pairing -- no matching may use that cell -- and every finite cost,
# every price and every reduced cost has to stay below it. Costs under C over
# nr rows need nr * C < 2^31, which is the contract the caller owes. Past it
# the arithmetic wraps and `certify` is what says so.
#
# Written for the compiled lanes: one Vec an array, every write in place; the
# inner scan hoists the row price out of the loop and reads four flat cells a
# column; the residual form of the algorithm (each column keeps its distance
# relative to the frontier) means the whole dual update is one add of one delta
# per column instead of a subtraction against a stored path length.
import Base
import ./vec.bend as Vec

# -- the number line ---------------------------------------------------------

# at or above: forbidden, unreachable, out of contract
def big() -> U32:
  2147483648

def inf() -> U32:
  4294967295

# the column of a row that nothing was matched to
def none() -> U32:
  4294967295

# a <= b, without the +1 that would wrap on an out-of-contract matrix
def le.of(lt: Bool) -> Bool:
  match lt:
    case True{}:
      False{}
    case False{}:
      True{}

def le(a: U32, b: U32) -> Bool:
  le.of(U32.is_lt(b, a))

# -- scratch -----------------------------------------------------------------

def fill.go(k: Nat, +x: U32, v: Vec.Vec) -> Vec.Vec:
  match k:
    case 0n:
      v
    case 1n++q:
      fill.go(q, x, Vec.push(v, x))

def fill(+n: U32, +x: U32) -> Vec.Vec:
  fill.go(U32.to_nat(n), x, Vec.new(x))

# reset: n cells back to x, keeping the block that is already there
def reset.go(k: Nat, +x: U32, v: Vec.Vec) -> Vec.Vec:
  match k:
    case 0n:
      v
    case 1n++q:
      reset.go(q, x, Vec.put(v, U32.from_nat(q), x))

def reset(v: Vec.Vec, +n: U32, +x: U32) -> Vec.Vec:
  reset.go(U32.to_nat(n), x, v)

# read-modify-write, the shape the dual update wants
def add_at.fin(+i: U32, +d: U32, r: Vec.Vec & U32) -> Vec.Vec:
  (v, x) = r
  Vec.put(v, i, U32.add(x, d))

def add_at(v: Vec.Vec, +i: U32, +d: U32) -> Vec.Vec:
  add_at.fin(i, d, Vec.at(v, i))

def sub_at.fin(+i: U32, +d: U32, r: Vec.Vec & U32) -> Vec.Vec:
  (v, x) = r
  Vec.put(v, i, U32.sub(x, d))

def sub_at(v: Vec.Vec, +i: U32, +d: U32) -> Vec.Vec:
  sub_at.fin(i, d, Vec.at(v, i))

# -- the answer --------------------------------------------------------------

# c4r[i] is the column matched to row i, or none(). u has nr+1 cells and w has
# nc+1: index 0 of each is the scratch slot the path walk starts from, so a row
# is u[i+1] and a column is w[j+1]. `ok` is False when no full matching exists,
# and then c4r is all none() and the cost is 0. c4r is last because a `+` marker is
# not allowed on a constructor pattern's final field and the accessors below
# need one on every scalar.
type Sol is Type:
  Sol{nr: U32, nc: U32, ok: Bool, sum: U32, u: Vec.Vec, w: Vec.Vec, c4r: Vec.Vec}

def cost(s: Sol) -> Sol & U32:
  match s:
    case Sol{nr, nc, ok, +k, u, w, c4r}:
      (Sol{nr, nc, ok, k, u, w, c4r}, k)

def solved(s: Sol) -> Sol & Bool:
  match s:
    case Sol{nr, nc, +ok, k, u, w, c4r}:
      (Sol{nr, nc, ok, k, u, w, c4r}, ok)

def at.fin(nr: U32, nc: U32, ok: Bool, k: U32, u: Vec.Vec, w: Vec.Vec, r: Vec.Vec & U32) -> Sol & U32:
  (c4r, x) = r
  (Sol{nr, nc, ok, k, u, w, c4r}, x)

# the column matched to row i, or none()
def at(s: Sol, +i: U32) -> Sol & U32:
  match s:
    case Sol{nr, nc, ok, k, u, w, c4r}:
      at.fin(nr, nc, ok, k, u, w, Vec.at(c4r, i))

def price_row.fin(nr: U32, nc: U32, ok: Bool, k: U32, w: Vec.Vec, c4r: Vec.Vec, r: Vec.Vec & U32) -> Sol & U32:
  (u, x) = r
  (Sol{nr, nc, ok, k, u, w, c4r}, x)

# u[i]: what row i pays. Non-negative.
def price_row(s: Sol, +i: U32) -> Sol & U32:
  match s:
    case Sol{nr, nc, ok, k, u, w, c4r}:
      price_row.fin(nr, nc, ok, k, w, c4r, Vec.at(u, U32.inc(i)))

def price_col.fin(nr: U32, nc: U32, ok: Bool, k: U32, u: Vec.Vec, c4r: Vec.Vec, r: Vec.Vec & U32) -> Sol & U32:
  (w, x) = r
  (Sol{nr, nc, ok, k, u, w, c4r}, x)

# w[j] = -v[j]: what column j is discounted by. Non-negative, 0 if unmatched.
def price_col(s: Sol, +j: U32) -> Sol & U32:
  match s:
    case Sol{nr, nc, ok, k, u, w, c4r}:
      price_col.fin(nr, nc, ok, k, u, c4r, Vec.at(w, U32.inc(j)))

# -- the inner scan: one row of reduced costs against the frontier ------------

# mv[j] is column j's distance from the tree, measured from the frontier: the
# dual update moves the frontier by dl and every column outside the tree keeps
# its distance by losing dl, so no absolute path length is ever stored.
type Sc is Type:
  Sc{c: Vec.Vec, w: Vec.Vec, way: Vec.Vec, mv: Vec.Vec, us: Vec.Vec, dl: U32, j1: U32}

# the reduced cost of reaching column j from row i0. A forbidden cell has none:
# nothing may travel through it.
def price(cij: U32, wj: U32, ui: U32, finite: Bool) -> U32:
  match finite:
    case True{}:
      U32.sub(U32.add(cij, wj), ui)
    case False{}:
      inf()

def sc.take(c: Vec.Vec, w: Vec.Vec, way: Vec.Vec, mv: Vec.Vec, us: Vec.Vec, j: U32, dl: U32, j1: U32, m: U32, wins: Bool) -> Sc:
  match wins:
    case True{}:
      Sc{c, w, way, mv, us, m, j}
    case False{}:
      Sc{c, w, way, mv, us, dl, j1}

def sc.cmp(c: Vec.Vec, w: Vec.Vec, way: Vec.Vec, mv: Vec.Vec, us: Vec.Vec, j: U32, +dl: U32, j1: U32, +m: U32) -> Sc:
  sc.take(c, w, way, mv, us, j, dl, j1, m, U32.is_lt(m, dl))

# relax: if the path through row i0 reaches column j for less than anything
# known, column j remembers the price and the column it was reached from
def sc.relax(c: Vec.Vec, w: Vec.Vec, way: Vec.Vec, mv: Vec.Vec, us: Vec.Vec, +j: U32, j0: U32, dl: U32, j1: U32, +cur: U32, m0: U32, better: Bool) -> Sc:
  match better:
    case True{}:
      sc.cmp(c, w, Vec.put(way, j, j0), Vec.put(mv, j, cur), us, j, dl, j1, cur)
    case False{}:
      sc.cmp(c, w, way, mv, us, j, dl, j1, m0)

def sc.mv(c: Vec.Vec, w: Vec.Vec, way: Vec.Vec, us: Vec.Vec, +j: U32, j0: U32, dl: U32, j1: U32, +cur: U32, r: Vec.Vec & U32) -> Sc:
  (mv, +m0) = r
  sc.relax(c, w, way, mv, us, j, j0, dl, j1, cur, m0, U32.is_lt(cur, m0))

def sc.cij(w: Vec.Vec, way: Vec.Vec, mv: Vec.Vec, us: Vec.Vec, +j: U32, j0: U32, dl: U32, j1: U32, wj: U32, ui: U32, r: Vec.Vec & U32) -> Sc:
  (c, +cij) = r
  sc.mv(c, w, way, us, j, j0, dl, j1, price(cij, wj, ui, U32.is_lt(cij, big())), Vec.at(mv, j))

def sc.wj(c: Vec.Vec, way: Vec.Vec, mv: Vec.Vec, us: Vec.Vec, +j: U32, +base: U32, ui: U32, j0: U32, dl: U32, j1: U32, r: Vec.Vec & U32) -> Sc:
  (w, wj) = r
  sc.cij(w, way, mv, us, j, j0, dl, j1, wj, ui, Vec.at(c, U32.sub(U32.add(base, j), 1)))

# a column already in the tree is settled: its price will not move again
def sc.skip(c: Vec.Vec, w: Vec.Vec, way: Vec.Vec, mv: Vec.Vec, us: Vec.Vec, +j: U32, base: U32, ui: U32, j0: U32, dl: U32, j1: U32, free: Bool) -> Sc:
  match free:
    case True{}:
      sc.wj(c, way, mv, us, j, base, ui, j0, dl, j1, Vec.at(w, j))
    case False{}:
      Sc{c, w, way, mv, us, dl, j1}

def sc.used(c: Vec.Vec, w: Vec.Vec, way: Vec.Vec, mv: Vec.Vec, j: U32, base: U32, ui: U32, j0: U32, dl: U32, j1: U32, r: Vec.Vec & U32) -> Sc:
  (us, f) = r
  sc.skip(c, w, way, mv, us, j, base, ui, j0, dl, j1, U32.is_zero(f))

def sc.one(+j: U32, base: U32, ui: U32, j0: U32, x: Sc) -> Sc:
  match x:
    case Sc{c, w, way, mv, us, dl, j1}:
      sc.used(c, w, way, mv, j, base, ui, j0, dl, j1, Vec.at(us, j))

def sc.go(fuel: Nat, +base: U32, +ui: U32, +j0: U32, x: Sc) -> Sc:
  match fuel:
    case 0n:
      x
    case 1n++q:
      sc.go(q, base, ui, j0, sc.one(U32.inc(U32.from_nat(q)), base, ui, j0, x))

# -- the dual update ---------------------------------------------------------

# one delta closes it: every column in the tree pays dl (and so does the row it
# holds), every column outside keeps its distance by losing dl.
type Du is Type:
  Du{u: Vec.Vec, p: Vec.Vec, w: Vec.Vec, mv: Vec.Vec, us: Vec.Vec}

def du.pay(u: Vec.Vec, w: Vec.Vec, mv: Vec.Vec, us: Vec.Vec, +j: U32, +dl: U32, r: Vec.Vec & U32) -> Du:
  (p, i) = r
  Du{add_at(u, i, dl), p, add_at(w, j, dl), mv, us}

def du.if(u: Vec.Vec, p: Vec.Vec, w: Vec.Vec, mv: Vec.Vec, us: Vec.Vec, +j: U32, +dl: U32, free: Bool) -> Du:
  match free:
    case True{}:
      Du{u, p, w, sub_at(mv, j, dl), us}
    case False{}:
      du.pay(u, w, mv, us, j, dl, Vec.at(p, j))

def du.used(u: Vec.Vec, p: Vec.Vec, w: Vec.Vec, mv: Vec.Vec, +j: U32, +dl: U32, r: Vec.Vec & U32) -> Du:
  (us, f) = r
  du.if(u, p, w, mv, us, j, dl, U32.is_zero(f))

def du.one(+j: U32, +dl: U32, x: Du) -> Du:
  match x:
    case Du{u, p, w, mv, us}:
      du.used(u, p, w, mv, j, dl, Vec.at(us, j))

def du.go(fuel: Nat, +dl: U32, x: Du) -> Du:
  match fuel:
    case 0n:
      x
    case 1n++q:
      du.go(q, dl, du.one(U32.from_nat(q), dl, x))

# -- the path ----------------------------------------------------------------

type St is Type:
  St{c: Vec.Vec, u: Vec.Vec, w: Vec.Vec, p: Vec.Vec, way: Vec.Vec, mv: Vec.Vec, us: Vec.Vec}

# Walk: the cheapest column reached is already matched, so the path goes on
# through the row holding it. Sink: it is free, and the path ends there.
# Dead: nothing is reachable at all, and no full matching exists.
type Path is Type:
  Walk{s: St, j0: U32}
  Sink{s: St, j0: U32}
  Dead{s: St}

def path.end(s: St, j1: U32, free: Bool) -> Path:
  match free:
    case True{}:
      Sink{s, j1}
    case False{}:
      Walk{s, j1}

def path.next(c: Vec.Vec, u: Vec.Vec, w: Vec.Vec, way: Vec.Vec, mv: Vec.Vec, us: Vec.Vec, j1: U32, r: Vec.Vec & U32) -> Path:
  (p, f) = r
  path.end(St{c, u, w, p, way, mv, us}, j1, U32.is_zero(f))

def path.dual(c: Vec.Vec, way: Vec.Vec, +j1: U32, x: Du) -> Path:
  match x:
    case Du{u, p, w, mv, us}:
      path.next(c, u, w, way, mv, us, j1, Vec.at(p, j1))

def path.live(c: Vec.Vec, u: Vec.Vec, w: Vec.Vec, p: Vec.Vec, way: Vec.Vec, mv: Vec.Vec, us: Vec.Vec, +nc: U32, dl: U32, j1: U32, live: Bool) -> Path:
  match live:
    case True{}:
      path.dual(c, way, j1, du.go(U32.to_nat(U32.inc(nc)), dl, Du{u, p, w, mv, us}))
    case False{}:
      Dead{St{c, u, w, p, way, mv, us}}

def path.scan(u: Vec.Vec, p: Vec.Vec, +nc: U32, x: Sc) -> Path:
  match x:
    case Sc{c, w, way, mv, us, +dl, j1}:
      path.live(c, u, w, p, way, mv, us, nc, dl, j1, U32.is_lt(dl, big()))

def path.ui(c: Vec.Vec, w: Vec.Vec, p: Vec.Vec, way: Vec.Vec, mv: Vec.Vec, us: Vec.Vec, j0: U32, +nc: U32, base: U32, r: Vec.Vec & U32) -> Path:
  (u, ui) = r
  path.scan(u, p, nc, sc.go(U32.to_nat(nc), base, ui, j0, Sc{c, w, way, mv, us, inf(), 0}))

def path.i0(c: Vec.Vec, u: Vec.Vec, w: Vec.Vec, way: Vec.Vec, mv: Vec.Vec, us: Vec.Vec, j0: U32, +nc: U32, r: Vec.Vec & U32) -> Path:
  (p, +i0) = r
  path.ui(c, w, p, way, mv, us, j0, nc, U32.mul(U32.sub(i0, 1), nc), Vec.at(u, i0))

def path.step(s: St, +j0: U32, nc: U32) -> Path:
  match s:
    case St{c, u, w, p, way, mv, us}:
      path.i0(c, u, w, way, mv, Vec.put(us, j0, 1), j0, nc, Vec.at(p, j0))

def path.go(fuel: Nat, +nc: U32, x: Path) -> Path:
  match fuel:
    case 0n:
      x
    case 1n++q:
      match x:
        case Walk{s, j0}:
          path.go(q, nc, path.step(s, j0, nc))
        case Sink{s, j0}:
          Sink{s, j0}
        case Dead{s}:
          Dead{s}

# -- the augment -------------------------------------------------------------

# walking the way chain back from the sink, every column on it takes the row
# its predecessor held; the chain ends at the scratch column, which holds the
# row this round started from, so the matching grows by exactly one
type Aug is Type:
  Go{p: Vec.Vec, way: Vec.Vec, j0: U32}
  Fin{p: Vec.Vec, way: Vec.Vec}

def aug.done(p: Vec.Vec, way: Vec.Vec, j1: U32, fin: Bool) -> Aug:
  match fin:
    case True{}:
      Fin{p, way}
    case False{}:
      Go{p, way, j1}

def aug.mv(way: Vec.Vec, j0: U32, +j1: U32, r: Vec.Vec & U32) -> Aug:
  (p, x) = r
  aug.done(Vec.put(p, j0, x), way, j1, U32.is_zero(j1))

def aug.w(p: Vec.Vec, j0: U32, r: Vec.Vec & U32) -> Aug:
  (way, +j1) = r
  aug.mv(way, j0, j1, Vec.at(p, j1))

def aug.step(p: Vec.Vec, way: Vec.Vec, +j0: U32) -> Aug:
  aug.w(p, j0, Vec.at(way, j0))

def aug.go(fuel: Nat, x: Aug) -> Aug:
  match fuel:
    case 0n:
      x
    case 1n++q:
      match x:
        case Go{p, way, j0}:
          aug.go(q, aug.step(p, way, j0))
        case Fin{p, way}:
          Fin{p, way}

# -- one row at a time -------------------------------------------------------

type Rows is Type:
  Live{s: St}
  Bust{s: St}

def rows.fin(c: Vec.Vec, u: Vec.Vec, w: Vec.Vec, mv: Vec.Vec, us: Vec.Vec, x: Aug) -> Rows:
  match x:
    case Fin{p, way}:
      Live{St{c, u, w, p, way, mv, us}}
    case Go{p, way, j0}:
      Bust{St{c, u, w, p, way, mv, us}}

def rows.aug(+nc: U32, j0: U32, s: St) -> Rows:
  match s:
    case St{c, u, w, p, way, mv, us}:
      rows.fin(c, u, w, mv, us, aug.go(U32.to_nat(U32.inc(nc)), Go{p, way, j0}))

def rows.walk(+nc: U32, x: Path) -> Rows:
  match x:
    case Walk{s, j0}:
      Bust{s}
    case Sink{s, j0}:
      rows.aug(nc, j0, s)
    case Dead{s}:
      Bust{s}

def rows.one(+i: U32, +nc: U32, s: St) -> Rows:
  match s:
    case St{c, u, w, p, way, mv, us}:
      rows.walk(nc, path.go(U32.to_nat(U32.inc(nc)), nc, Walk{St{c, u, w, Vec.put(p, 0, i), way, reset(mv, U32.inc(nc), inf()), reset(us, U32.inc(nc), 0)}, 0}))

def rows.go(fuel: Nat, +i: U32, +nc: U32, x: Rows) -> Rows:
  match fuel:
    case 0n:
      x
    case 1n++q:
      match x:
        case Live{s}:
          rows.go(q, U32.inc(i), nc, rows.one(i, nc, s))
        case Bust{s}:
          Bust{s}

# -- reading the answer out --------------------------------------------------

type Out is Type:
  Out{c: Vec.Vec, p: Vec.Vec, c4r: Vec.Vec, sum: U32}

def out.add(p: Vec.Vec, c4r: Vec.Vec, +sum: U32, r: Vec.Vec & U32) -> Out:
  (c, x) = r
  Out{c, p, c4r, U32.add(sum, x)}

def out.if(c: Vec.Vec, p: Vec.Vec, c4r: Vec.Vec, sum: U32, +j: U32, nc: U32, +i: U32, empty: Bool) -> Out:
  match empty:
    case True{}:
      Out{c, p, c4r, sum}
    case False{}:
      out.add(p, Vec.put(c4r, U32.sub(i, 1), U32.sub(j, 1)), sum, Vec.at(c, U32.add(U32.mul(U32.sub(i, 1), nc), U32.sub(j, 1))))

def out.row(c: Vec.Vec, c4r: Vec.Vec, sum: U32, j: U32, nc: U32, r: Vec.Vec & U32) -> Out:
  (p, +i) = r
  out.if(c, p, c4r, sum, j, nc, i, U32.is_zero(i))

def out.one(+j: U32, nc: U32, x: Out) -> Out:
  match x:
    case Out{c, p, c4r, sum}:
      out.row(c, c4r, sum, j, nc, Vec.at(p, j))

def out.go(fuel: Nat, +nc: U32, x: Out) -> Out:
  match fuel:
    case 0n:
      x
    case 1n++q:
      out.go(q, nc, out.one(U32.inc(U32.from_nat(q)), nc, x))

# -- solve -------------------------------------------------------------------

def solve.out(+nr: U32, +nc: U32, u: Vec.Vec, w: Vec.Vec, x: Out) -> Vec.Vec & Sol:
  match x:
    case Out{c, p, c4r, sum}:
      (c, Sol{nr, nc, True{}, sum, u, w, c4r})

def solve.rows(+nr: U32, +nc: U32, s: St) -> Vec.Vec & Sol:
  match s:
    case St{c, u, w, p, way, mv, us}:
      solve.out(nr, nc, u, w, out.go(U32.to_nat(nc), nc, Out{c, p, fill(nr, none()), 0}))

# infeasible: the prices are still dual-feasible, but there is no matching for
# them to certify, so the matching comes back empty and the cost 0
def solve.bust(+nr: U32, nc: U32, s: St) -> Vec.Vec & Sol:
  match s:
    case St{c, u, w, p, way, mv, us}:
      (c, Sol{nr, nc, False{}, 0, u, w, fill(nr, none())})

def solve.done(+nr: U32, +nc: U32, x: Rows) -> Vec.Vec & Sol:
  match x:
    case Live{s}:
      solve.rows(nr, nc, s)
    case Bust{s}:
      solve.bust(nr, nc, s)

def solve.st(c: Vec.Vec, nr: U32, +nc: U32) -> St:
  St{c, fill(U32.inc(nr), 0), fill(U32.inc(nc), 0), fill(U32.inc(nc), 0), fill(U32.inc(nc), 0), fill(U32.inc(nc), inf()), fill(U32.inc(nc), 0)}

def solve.if(c: Vec.Vec, +nr: U32, +nc: U32, wide: Bool) -> Vec.Vec & Sol:
  match wide:
    case True{}:
      (c, Sol{nr, nc, False{}, 0, fill(U32.inc(nr), 0), fill(U32.inc(nc), 0), fill(nr, none())})
    case False{}:
      solve.done(nr, nc, rows.go(U32.to_nat(nr), 1, nc, Live{solve.st(c, nr, nc)}))

# solve: match every row to a column of its own, as cheaply as possible. Needs
# nr <= nc -- a taller problem has no full matching and comes back ok = False,
# and so does one whose reachable cells cannot cover every row. The cost matrix
# is row-major, nr * nc cells, and comes back beside the answer.
def solve(c: Vec.Vec, +nr: U32, +nc: U32) -> Vec.Vec & Sol:
  solve.if(c, nr, nc, U32.is_lt(nc, nr))

# -- opting out --------------------------------------------------------------

type Pad is Type:
  Pad{c: Vec.Vec, o: Vec.Vec}

def pad.slot(gate: U32, mine: Bool) -> U32:
  match mine:
    case True{}:
      gate
    case False{}:
      inf()

# the fuel counts down, so the slot being pushed is nr-1-q, not q: written the
# other way the dummy block comes out reversed and row i's opt-out column is
# nc + (nr-1-i), which still solves and still certifies -- every cost is the
# same -- and only the permutation says so.
def pad.dummy(fuel: Nat, +i: U32, +nr: U32, +gate: U32, o: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      o
    case 1n++q:
      pad.dummy(q, i, nr, gate, Vec.push(o, pad.slot(gate, U32.is_eq(U32.sub(U32.sub(nr, 1), U32.from_nat(q)), i))))

def pad.cell(o: Vec.Vec, r: Vec.Vec & U32) -> Pad:
  (c, x) = r
  Pad{c, Vec.push(o, x)}

def pad.real(fuel: Nat, +base: U32, +nc: U32, x: Pad) -> Pad:
  match fuel:
    case 0n:
      x
    case 1n++q:
      match x:
        case Pad{c, o}:
          pad.real(q, base, nc, pad.cell(o, Vec.at(c, U32.add(base, U32.sub(U32.sub(nc, 1), U32.from_nat(q))))))

def pad.tail(+i: U32, +nr: U32, +gate: U32, x: Pad) -> Pad:
  match x:
    case Pad{c, o}:
      Pad{c, pad.dummy(U32.to_nat(nr), i, nr, gate, o)}

def pad.go(fuel: Nat, +i: U32, +nr: U32, +nc: U32, +gate: U32, x: Pad) -> Pad:
  match fuel:
    case 0n:
      x
    case 1n++q:
      pad.go(q, U32.inc(i), nr, nc, gate, pad.tail(i, nr, gate, pad.real(U32.to_nat(nc), U32.mul(i, nc), nc, x)))

def pad.out(x: Pad) -> Vec.Vec:
  match x:
    case Pad{c, o}:
      o

# pad: nr extra columns, one per row, so row i may opt out at cost `gate` and
# nothing else may take that slot. One shared opt-out column would not do it --
# a column absorbs one row, so a shared one lets exactly one row out. The price
# is nc + nr columns wide instead of nc; for a tracker whose rows and columns
# are the same order of size that is a factor of two on an O(nr^2 * nc) solve.
def pad(c: Vec.Vec, +nr: U32, +nc: U32, +gate: U32) -> Vec.Vec:
  pad.out(pad.go(U32.to_nat(nr), 0, nr, nc, gate, Pad{c, Vec.new(0)}))

# solve_opt: as solve, but a row may go unmatched at cost `gate`. The Vec that
# comes back is the padded matrix, not the one handed in, and the Sol's nc is
# nc + nr, which is what `certify` needs to check: c4r[i] >= nc means row i
# opted out (and then c4r[i] is exactly nc + i).
def solve_opt(c: Vec.Vec, +nr: U32, +nc: U32, gate: U32) -> Vec.Vec & Sol:
  solve(pad(c, nr, nc, gate), nr, U32.add(nc, nr))

# -- the certificate ---------------------------------------------------------

type Fe is Type:
  Fe{c: Vec.Vec, w: Vec.Vec, ok: Bool}

type Fa is Type:
  Fa{c: Vec.Vec, u: Vec.Vec, w: Vec.Vec, ok: Bool}

# dual feasibility at one cell: u[i] <= c[i][j] + w[j]. A forbidden cell is
# vacuous -- no matching may use it, so no price has to fit under it.
def fe.hold(c: Vec.Vec, w: Vec.Vec, ok: Bool, cij: U32, wj: U32, ui: U32, live: Bool) -> Fe:
  match live:
    case True{}:
      Fe{c, w, Bool.and(ok, le(ui, U32.add(cij, wj)))}
    case False{}:
      Fe{c, w, ok}

def fe.wj(c: Vec.Vec, ok: Bool, +cij: U32, ui: U32, r: Vec.Vec & U32) -> Fe:
  (w, wj) = r
  fe.hold(c, w, ok, cij, wj, ui, U32.is_lt(cij, big()))

def fe.cij(w: Vec.Vec, ok: Bool, ui: U32, +j: U32, r: Vec.Vec & U32) -> Fe:
  (c, cij) = r
  fe.wj(c, ok, cij, ui, Vec.at(w, U32.inc(j)))

def fe.one(+j: U32, base: U32, ui: U32, x: Fe) -> Fe:
  match x:
    case Fe{c, w, ok}:
      fe.cij(w, ok, ui, j, Vec.at(c, U32.add(base, j)))

def fe.go(fuel: Nat, +base: U32, +ui: U32, x: Fe) -> Fe:
  match fuel:
    case 0n:
      x
    case 1n++q:
      fe.go(q, base, ui, fe.one(U32.from_nat(q), base, ui, x))

def fa.scan(u: Vec.Vec, x: Fe) -> Fa:
  match x:
    case Fe{c, w, ok}:
      Fa{c, u, w, ok}

def fa.ui(c: Vec.Vec, w: Vec.Vec, ok: Bool, +nc: U32, base: U32, r: Vec.Vec & U32) -> Fa:
  (u, ui) = r
  fa.scan(u, fe.go(U32.to_nat(nc), base, ui, Fe{c, w, ok}))

def fa.one(+i: U32, +nc: U32, x: Fa) -> Fa:
  match x:
    case Fa{c, u, w, ok}:
      fa.ui(c, w, ok, nc, U32.mul(i, nc), Vec.at(u, U32.inc(i)))

def fa.go(fuel: Nat, +nc: U32, x: Fa) -> Fa:
  match fuel:
    case 0n:
      x
    case 1n++q:
      fa.go(q, nc, fa.one(U32.from_nat(q), nc, x))

# the matching itself: every row holds a real column, no two rows hold the
# same one, and the price is tight there -- u[i] == c[i][j] + w[j]
type Tg is Type:
  Tg{c: Vec.Vec, u: Vec.Vec, w: Vec.Vec, c4r: Vec.Vec, seen: Vec.Vec, ok: Bool}

def tg.chk(c: Vec.Vec, u: Vec.Vec, w: Vec.Vec, c4r: Vec.Vec, seen: Vec.Vec, ok: Bool, ui: U32, cij: U32, wj: U32) -> Tg:
  Tg{c, u, w, c4r, seen, Bool.and(ok, U32.is_eq(ui, U32.add(cij, wj)))}

def tg.w(c: Vec.Vec, u: Vec.Vec, c4r: Vec.Vec, seen: Vec.Vec, ok: Bool, ui: U32, cij: U32, r: Vec.Vec & U32) -> Tg:
  (w, wj) = r
  tg.chk(c, u, w, c4r, seen, ok, ui, cij, wj)

def tg.c(u: Vec.Vec, w: Vec.Vec, c4r: Vec.Vec, seen: Vec.Vec, ok: Bool, ui: U32, +j: U32, r: Vec.Vec & U32) -> Tg:
  (c, cij) = r
  tg.w(c, u, c4r, seen, ok, ui, cij, Vec.at(w, U32.inc(j)))

def tg.mark(c: Vec.Vec, u: Vec.Vec, w: Vec.Vec, c4r: Vec.Vec, seen: Vec.Vec, ok: Bool, base: U32, +j: U32, ui: U32, fresh: Bool) -> Tg:
  match fresh:
    case True{}:
      tg.c(u, w, c4r, Vec.put(seen, j, 1), ok, ui, j, Vec.at(c, U32.add(base, j)))
    case False{}:
      Tg{c, u, w, c4r, seen, False{}}

def tg.seen(c: Vec.Vec, u: Vec.Vec, w: Vec.Vec, c4r: Vec.Vec, ok: Bool, base: U32, +j: U32, ui: U32, r: Vec.Vec & U32) -> Tg:
  (seen, f) = r
  tg.mark(c, u, w, c4r, seen, ok, base, j, ui, U32.is_zero(f))

def tg.col(c: Vec.Vec, u: Vec.Vec, w: Vec.Vec, c4r: Vec.Vec, seen: Vec.Vec, ok: Bool, base: U32, +j: U32, ui: U32, real: Bool) -> Tg:
  match real:
    case True{}:
      tg.seen(c, u, w, c4r, ok, base, j, ui, Vec.at(seen, j))
    case False{}:
      Tg{c, u, w, c4r, seen, False{}}

def tg.j(c: Vec.Vec, u: Vec.Vec, w: Vec.Vec, seen: Vec.Vec, ok: Bool, base: U32, +nc: U32, ui: U32, r: Vec.Vec & U32) -> Tg:
  (c4r, +j) = r
  tg.col(c, u, w, c4r, seen, ok, base, j, ui, U32.is_lt(j, nc))

def tg.ui(c: Vec.Vec, w: Vec.Vec, c4r: Vec.Vec, seen: Vec.Vec, ok: Bool, +i: U32, +nc: U32, r: Vec.Vec & U32) -> Tg:
  (u, ui) = r
  tg.j(c, u, w, seen, ok, U32.mul(i, nc), nc, ui, Vec.at(c4r, i))

def tg.one(+i: U32, +nc: U32, x: Tg) -> Tg:
  match x:
    case Tg{c, u, w, c4r, seen, ok}:
      tg.ui(c, w, c4r, seen, ok, i, nc, Vec.at(u, U32.inc(i)))

def tg.go(fuel: Nat, +nc: U32, x: Tg) -> Tg:
  match fuel:
    case 0n:
      x
    case 1n++q:
      tg.go(q, nc, tg.one(U32.from_nat(q), nc, x))

# a column nothing was matched to has to carry no discount, or the dual sum is
# not the matching's cost and the two sides of the duality do not meet
type Zp is Type:
  Zp{w: Vec.Vec, seen: Vec.Vec, ok: Bool}

def zp.w(seen: Vec.Vec, ok: Bool, r: Vec.Vec & U32) -> Zp:
  (w, wj) = r
  Zp{w, seen, Bool.and(ok, U32.is_zero(wj))}

def zp.if(w: Vec.Vec, seen: Vec.Vec, ok: Bool, +j: U32, free: Bool) -> Zp:
  match free:
    case True{}:
      zp.w(seen, ok, Vec.at(w, U32.inc(j)))
    case False{}:
      Zp{w, seen, ok}

def zp.seen(w: Vec.Vec, ok: Bool, +j: U32, r: Vec.Vec & U32) -> Zp:
  (seen, f) = r
  zp.if(w, seen, ok, j, U32.is_zero(f))

def zp.one(+j: U32, x: Zp) -> Zp:
  match x:
    case Zp{w, seen, ok}:
      zp.seen(w, ok, j, Vec.at(seen, j))

def zp.go(fuel: Nat, x: Zp) -> Zp:
  match fuel:
    case 0n:
      x
    case 1n++q:
      zp.go(q, zp.one(U32.from_nat(q), x))

type Ck is Type:
  Ck{c: Vec.Vec, s: Sol, ok: Bool}

def ck.c(c: Vec.Vec, u: Vec.Vec, c4r: Vec.Vec, nr: U32, nc: U32, sok: Bool, sum: U32, x: Zp) -> Ck:
  match x:
    case Zp{w, seen, ok}:
      Ck{c, Sol{nr, nc, sok, sum, u, w, c4r}, ok}

def ck.b(nr: U32, +nc: U32, sok: Bool, sum: U32, x: Tg) -> Ck:
  match x:
    case Tg{c, u, w, c4r, seen, ok}:
      ck.c(c, u, c4r, nr, nc, sok, sum, zp.go(U32.to_nat(nc), Zp{w, seen, ok}))

def ck.a(+nr: U32, +nc: U32, sok: Bool, sum: U32, c4r: Vec.Vec, x: Fa) -> Ck:
  match x:
    case Fa{c, u, w, ok}:
      ck.b(nr, nc, sok, sum, tg.go(U32.to_nat(nr), nc, Tg{c, u, w, c4r, fill(nc, 0), ok}))

# certify: one pass over the matrix says whether these prices prove this
# matching optimal. O(nr * nc) against O(nr^2 * nc) to solve again, and it
# shares no line with the solver above it -- the arithmetic here is three
# comparisons, not a search. It checks what the solver claims, so a Sol that
# came back ok = False fails it: there is nothing to certify.
def certify(c: Vec.Vec, s: Sol) -> Ck:
  match s:
    case Sol{+nr, +nc, +sok, sum, u, w, c4r}:
      ck.a(nr, nc, sok, sum, c4r, fa.go(U32.to_nat(nr), nc, Fa{c, u, w, sok}))
