# Fft: the radix-2 Cooley-Tukey transform over F32 complex points, out of place,
# decimation in time. exp(-2 pi i k / n) is the forward kernel, so the sign and
# the 1/n on the inverse are numpy's.
#
# Deterministic by construction, not by luck. Every operation here is one of the
# five IEEE-754 requires to be correctly rounded -- add, sub, mul, div, sqrt --
# so the interpreter, V8 and clang all round the same way and the three lanes
# print the same bits. That is why the twiddles come off a half-angle recurrence
#
#     cos(t/2) = sqrt((1 + cos t) / 2)    sin(t/2) = sqrt((1 - cos t) / 2)
#
# seeded at exp(i pi) = (-1, 0), and never off a sin or cos: those two are
# libm's, one implementation per host, and nothing in the standard makes two
# hosts agree on their last bit. The recurrence costs one sqrt a level and is
# exact in the only sense a test can check.
#
# F32, not F64, and the reason is the backend rather than the mathematics. An
# F64 is stored unboxed, so a double's raw bits ride in a Term-shaped slot; the
# C runtime reads bits 56-62 of that slot as a tag and the low 40 as a heap
# address, and frees anything the tag does not call trivial. Which slots get
# walked is decided by `lay_arr` (comp.ts): an element wider than w32 cannot use
# the packed 32-bit block and falls into the one whose cells are walked as
# Terms. `C{re: F64, im: F64}` is exactly that -- so every dropped point is a
# double being freed as if it were a pointer. `C{re: F32, im: F32}` is two w32
# cells, takes the packed block, and is never walked. The fix is mechanical and
# not luck: no rearrangement of the transform could have saved F64, because an
# FFT must drop buffers -- this one discards three at every level of the
# recursion (the source a `split` consumes; the two halves and the twiddle table
# a `comb` consumes). In F64 the forward transform is correct at 2, 4 and 8
# points and dies at 16 with `bend: memory fault (machine stack overflow?)`, on
# one thread and on sixteen, while the interpreter and JS agree bit for bit. In
# F32 every lane agrees. See docs/omen/f64-drop-c-backend.md for the
# derivation, the emitted C, and the exact safety predicate on a double's bits.
# The determinism argument above is unaffected: IEEE-754 requires the same five
# operations to be correctly rounded in binary32 as in binary64.
#
# ponytail: F32 carries 24 mantissa bits, so a transform this deep loses
# roughly log2(n)/2 of them to accumulation -- fine for the spectra and
# convolutions here, not for anything that then inverts a near-singular system.
# The upgrade is one `sed` back to F64 the day the C drop path is fixed; the
# structure is float-width agnostic.
#
# Written for the fork. The transform cannot be the textbook in-place loop over
# one buffer, because an Array has a single owner and a single owner cannot be
# two halves at once. So the tree is the real thing: `split` gathers the even and
# odd points into two new buffers that own themselves, and `go` recurses into
# both sides in parallel. The price is the gather -- n log n cells copied on top
# of the n log n butterflies -- and the price is paid to make the halving tree a
# real fork rather than a loop wearing a tree's name.
#
# Bend's defs must be defined before use, so there is no mutual recursion: `go`
# is the one self-recursive def, and it takes its split as a *parameter* (a match
# cannot scrutinize a computed value) while the recursive calls take theirs as
# arguments, which may be computed.
import Base

# -- complex -----------------------------------------------------------------

type C is Data:
  C{re: F32, im: F32}

def c.zero() -> C:
  C{0.0, 0.0}

def c.one() -> C:
  C{1.0, 0.0}

def c.re(x: C) -> F32:
  match x:
    case C{r, i}:
      r

def c.im(x: C) -> F32:
  match x:
    case C{r, i}:
      i

def cadd.b(+ar: F32, +ai: F32, b: C) -> C:
  match b:
    case C{br, bi}:
      C{F32.add(ar, br), F32.add(ai, bi)}

def cadd(a: C, b: C) -> C:
  match a:
    case C{ar, ai}:
      cadd.b(ar, ai, b)

def csub.b(+ar: F32, +ai: F32, b: C) -> C:
  match b:
    case C{br, bi}:
      C{F32.sub(ar, br), F32.sub(ai, bi)}

def csub(a: C, b: C) -> C:
  match a:
    case C{ar, ai}:
      csub.b(ar, ai, b)

def cmul.f(+ar: F32, +ai: F32, +br: F32, +bi: F32) -> C:
  C{F32.sub(F32.mul(ar, br), F32.mul(ai, bi)), F32.add(F32.mul(ar, bi), F32.mul(ai, br))}

def cmul.b(+ar: F32, +ai: F32, b: C) -> C:
  match b:
    case C{br, bi}:
      cmul.f(ar, ai, br, bi)

def cmul(a: C, b: C) -> C:
  match a:
    case C{ar, ai}:
      cmul.b(ar, ai, b)

def csq(+x: C) -> C:
  cmul(x, x)

def cconj(x: C) -> C:
  match x:
    case C{r, i}:
      C{r, F32.neg(i)}

def cscale(x: C, +f: F32) -> C:
  match x:
    case C{r, i}:
      C{F32.mul(r, f), F32.mul(i, f)}

# -- the buffer --------------------------------------------------------------
# n is 2^d always; d is stored because Array.size walks the tree on the
# interpreter and because the recursion counts in depths, not lengths.

type Sig is Type:
  Sig{n: U32, d: Nat, arr: Array<C>}

def new(+d: Nat) -> Sig:
  +z = c.zero()
  Sig{U32.shln(1, d), d, [z : C^d]}

def len(s: Sig) -> Sig & U32:
  match s:
    case Sig{+n, d, arr}:
      (Sig{n, d, arr}, n)

def at.fin(n: U32, d: Nat, r: Array<C> & C) -> Sig & C:
  (arr, x) = r
  (Sig{n, d, arr}, x)

# at: unchecked, the index wraps at 2^d; for loops that own their bounds
def at(s: Sig, +i: U32) -> Sig & C:
  match s:
    case Sig{n, d, arr}:
      at.fin(n, d, Array.get(C, arr, i))

def put(s: Sig, i: U32, x: C) -> Sig:
  match s:
    case Sig{n, d, arr}:
      Sig{n, d, Array.set(C, arr, i, x)}

def of_list.go(xs: List<&2, C>, +i: U32, s: Sig) -> Sig:
  match xs:
    case Nil{}:
      s
    case Con{x, t}:
      of_list.go(t, U32.inc(i), put(s, i, x))

# xs is read into the first cells; anything past its end stays zero
def of_list(xs: List<&2, C>, +d: Nat) -> Sig:
  of_list.go(xs, 0, new(d))

def of_real.go(xs: List<&2, F32>, +i: U32, s: Sig) -> Sig:
  match xs:
    case Nil{}:
      s
    case Con{x, t}:
      of_real.go(t, U32.inc(i), put(s, i, C{x, 0.0}))

def of_real(xs: List<&2, F32>, +d: Nat) -> Sig:
  of_real.go(xs, 0, new(d))

def to_list.cons(r: Sig & C, acc: List<&2, C>) -> Sig & List<&2, C>:
  (s, x) = r
  (s, Con{x, acc})

def to_list.step(+i: U32, sa: Sig & List<&2, C>) -> Sig & List<&2, C>:
  (s, acc) = sa
  to_list.cons(at(s, i), acc)

def to_list.go(i: Nat, sa: Sig & List<&2, C>) -> Sig & List<&2, C>:
  match i:
    case 0n:
      sa
    case 1n++p:
      to_list.go(p, to_list.step(U32.from_nat(p), sa))

def to_list.n(r: Sig & U32) -> Sig & List<&2, C>:
  (s, n) = r
  to_list.go(U32.to_nat(n), (s, []))

def to_list(s: Sig) -> Sig & List<&2, C>:
  to_list.n(len(s))

# -- the twiddles ------------------------------------------------------------
# half(j) is exp(i pi / 2^j), by the half-angle recurrence from exp(i pi).
# The angle stays in [0, pi], where sin is not negative, so the positive root
# is the right one at every step.

def half.step(+c: F32) -> C:
  C{F32.sqrt(F32.div(F32.add(1.0, c), 2.0)), F32.sqrt(F32.div(F32.sub(1.0, c), 2.0))}

def half.re(x: C) -> C:
  match x:
    case C{cr, ci}:
      half.step(cr)

def half(j: Nat) -> C:
  match j:
    case 0n:
      C{F32.neg(1.0), 0.0}
    case 1n++p:
      half.re(half(p))

# the forward kernel for a combine over m = 2^p points: exp(-i pi / m)
def kernel(p: Nat) -> C:
  cconj(half(p))

# t[k] = b^k for k < m, built by squaring: t[2k] = t[k]^2 and t[2k+1] = t[2k]*b.
# Every entry reads an index below its own, so one ascending pass fills it, and
# the rounding depth is log m rather than the m of a running product.
def tb.dup(+k: U32, r: Array<C> & C) -> Array<C>:
  (a, x) = r
  Array.set(C, a, k, csq(x))

def tb.wr(+k: U32, w: C, r: Array<C> & C) -> Array<C>:
  (a, x) = r
  Array.set(C, a, k, cmul(x, w))

def tb.one(+k: U32, b: C, a: Array<C>, even: Bool) -> Array<C>:
  match even:
    case True{}:
      tb.dup(k, Array.get(C, a, U32.shrn(k, 1n)))
    case False{}:
      tb.wr(k, b, Array.get(C, a, U32.sub(k, 1)))

def tb.go(fuel: Nat, +k: U32, +b: C, a: Array<C>) -> Array<C>:
  match fuel:
    case 0n:
      a
    case 1n++p:
      tb.go(p, U32.inc(k), b, tb.one(k, b, a, U32.is_zero(U32.and(k, 1))))

def table(m: U32, +p: Nat, b: C) -> Array<C>:
  +u = c.one()
  tb.go(U32.to_nat(U32.sub(m, 1)), 1, b, Array.set(C, [u : C^p], 0, u))

# -- the split ---------------------------------------------------------------
# e[i] = s[2i], o[i] = s[2i+1]. The source is read twice a step and then
# dropped: two buffers that own themselves are what the fork needs.

type Sp is Type:
  Sp{e: Sig, o: Sig}

type G is Type:
  G{s: Sig, e: Sig, o: Sig}

def sp.fin(e: Sig, o: Sig, +i: U32, r: Sig & C) -> G:
  (s, x) = r
  G{s, e, put(o, i, x)}

def sp.mid(e: Sig, o: Sig, +i: U32, j: U32, r: Sig & C) -> G:
  (s, x) = r
  sp.fin(put(e, i, x), o, i, at(s, U32.inc(j)))

def sp.at(e: Sig, o: Sig, s: Sig, i: U32, +j: U32) -> G:
  sp.mid(e, o, i, j, at(s, j))

def sp.one(+i: U32, g: G) -> G:
  match g:
    case G{s, e, o}:
      sp.at(e, o, s, i, U32.shln(i, 1n))

def sp.go(fuel: Nat, +i: U32, g: G) -> G:
  match fuel:
    case 0n:
      g
    case 1n++p:
      sp.go(p, U32.inc(i), sp.one(i, g))

def sp.out(g: G) -> Sp:
  match g:
    case G{s, e, o}:
      Sp{e, o}

# s holds 2m = 2^(p+1) points; each half of the answer holds m = 2^p
def split(s: Sig, m: U32, +p: Nat) -> Sp:
  sp.out(sp.go(U32.to_nat(m), 0, G{s, new(p), new(p)}))

# -- the combine -------------------------------------------------------------
# y[k] = e[k] + w^k o[k] and y[k+m] = e[k] - w^k o[k], the butterfly, over a
# twiddle table this combine owns. The table cannot be hoisted out of the
# recursion and shared: one Array, one owner, and the two sides run in parallel.

type Cb is Type:
  Cb{a: Sig, b: Sig, t: Array<C>, o: Sig}

def cb.wr(a: Sig, b: Sig, t: Array<C>, o: Sig, +k: U32, +m: U32, +ek: C, +x: C) -> Cb:
  Cb{a, b, t, put(put(o, k, cadd(ek, x)), U32.add(k, m), csub(ek, x))}

def cb.w(a: Sig, b: Sig, o: Sig, +k: U32, +m: U32, ek: C, ok: C, r: Array<C> & C) -> Cb:
  (t, w) = r
  cb.wr(a, b, t, o, k, m, ek, cmul(w, ok))

def cb.ok(a: Sig, t: Array<C>, o: Sig, +k: U32, +m: U32, ek: C, r: Sig & C) -> Cb:
  (b, ok) = r
  cb.w(a, b, o, k, m, ek, ok, Array.get(C, t, k))

def cb.ek(b: Sig, t: Array<C>, o: Sig, +k: U32, +m: U32, r: Sig & C) -> Cb:
  (a, ek) = r
  cb.ok(a, t, o, k, m, ek, at(b, k))

def cb.one(+k: U32, +m: U32, x: Cb) -> Cb:
  match x:
    case Cb{a, b, t, o}:
      cb.ek(b, t, o, k, m, at(a, k))

def cb.go(fuel: Nat, +k: U32, +m: U32, x: Cb) -> Cb:
  match fuel:
    case 0n:
      x
    case 1n++p:
      cb.go(p, U32.inc(k), m, cb.one(k, m, x))

def cb.out(x: Cb) -> Sig:
  match x:
    case Cb{a, b, t, o}:
      o

# a and b each hold m = 2^p points; the answer holds 2m
def comb(a: Sig, b: Sig, +m: U32, +p: Nat) -> Sig:
  cb.out(cb.go(U32.to_nat(m), 0, m, Cb{a, b, table(m, p, kernel(p)), new(1n+p)}))

# -- the transform -----------------------------------------------------------

def go.up(+p: Nat, a: Sig, b: Sig) -> Sig:
  comb(a, b, U32.shln(2, p), 1n+p)

# go(d, Sp{e, o}) where e and o each hold 2^d points, and the answer holds
# 2^(d+1). The two recursive calls are the fork; their arguments are computed,
# which an argument may be, while the split this call consumes arrived as a
# parameter, which a match scrutinee must be.
def go(d: Nat, x: Sp) -> Sig:
  match d:
    case 0n:
      match x:
        case Sp{e, o}:
          comb(e, o, 1, 0n)
    case 1n++p:
      match x:
        case Sp{e, o}:
          +m = U32.shln(1, p)
          a b = go(p, split(e, m, p)) go(p, split(o, m, p))
          go.up(p, a, b)

def fft.on(+n: U32, +d: Nat, arr: Array<C>) -> Sig:
  match d:
    case 0n:
      Sig{n, 0n, arr}
    case 1n++p:
      go(p, split(Sig{n, 1n+p, arr}, U32.shln(1, p), p))

def fft(s: Sig) -> Sig:
  match s:
    case Sig{n, d, arr}:
      fft.on(n, d, arr)

# -- the inverse -------------------------------------------------------------
# conj . fft . conj, scaled by 1/n: the forward transform is the only kernel,
# so the inverse cannot disagree with it about a twiddle.

def mc.w(+i: U32, r: Sig & C) -> Sig:
  (s, x) = r
  put(s, i, cconj(x))

def mc.go(fuel: Nat, +i: U32, s: Sig) -> Sig:
  match fuel:
    case 0n:
      s
    case 1n++p:
      mc.go(p, U32.inc(i), mc.w(i, at(s, i)))

def mc.n(r: Sig & U32) -> Sig:
  (s, n) = r
  mc.go(U32.to_nat(n), 0, s)

def conj(s: Sig) -> Sig:
  mc.n(len(s))

def ms.w(+i: U32, +f: F32, r: Sig & C) -> Sig:
  (s, x) = r
  put(s, i, cscale(cconj(x), f))

def ms.go(fuel: Nat, +i: U32, +f: F32, s: Sig) -> Sig:
  match fuel:
    case 0n:
      s
    case 1n++p:
      ms.go(p, U32.inc(i), f, ms.w(i, f, at(s, i)))

def ms.n(r: Sig & U32) -> Sig:
  (s, +n) = r
  ms.go(U32.to_nat(n), 0, F32.div(1.0, U32.to_f32(n)), s)

def ifft(s: Sig) -> Sig:
  ms.n(len(fft(conj(s))))

# -- convolution -------------------------------------------------------------

type Pw is Type:
  Pw{a: Sig, b: Sig}

def pw.wr(b: Sig, +i: U32, +bx: C, r: Sig & C) -> Pw:
  (a, ax) = r
  Pw{put(a, i, cmul(ax, bx)), b}

def pw.rb(a: Sig, +i: U32, r: Sig & C) -> Pw:
  (b, bx) = r
  pw.wr(b, i, bx, at(a, i))

def pw.one(+i: U32, x: Pw) -> Pw:
  match x:
    case Pw{a, b}:
      pw.rb(a, i, at(b, i))

def pw.go(fuel: Nat, +i: U32, x: Pw) -> Pw:
  match fuel:
    case 0n:
      x
    case 1n++p:
      pw.go(p, U32.inc(i), pw.one(i, x))

def pw.out(x: Pw) -> Sig:
  match x:
    case Pw{a, b}:
      a

def pw.n(b: Sig, r: Sig & U32) -> Sig:
  (a, n) = r
  pw.out(pw.go(U32.to_nat(n), 0, Pw{a, b}))

# the pointwise product, in a's buffer; b is consumed
def hadamard(a: Sig, b: Sig) -> Sig:
  pw.n(b, len(a))

# circular convolution of two equal-length signals. The two forward transforms
# are independent, so they are the second fork in the file.
def convolve(x: Sig, y: Sig) -> Sig:
  a b = fft(x) fft(y)
  ifft(hadamard(a, b))
