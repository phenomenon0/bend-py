#!/usr/bin/env python3
# The oracle for knn.bend: prints the whole fixture. The reference below is
# plain CPython -- lists and floats, no Flat, no TopK -- so a row checks the
# index, not a second copy of it.
#
# Every number this fixture prints is a U32, and that is the point rather than a
# convenience: a distance is printed as `key(distance)`, which is its exact
# 32-bit pattern, so a row pins the float to the last bit instead of to however
# many digits a printer chose to show.
#
# Emulating F32 in CPython is exact, not approximate. Both emitters compute in
# double and round the result to float32 -- comp.ts emits `Math.fround(a op b)`
# for JS and `(f32)(double op)` for C -- and `f32()` below is that same
# construction through `struct`. For +, -, *, / and sqrt the double rounding is
# provably identical to a native float32 operation, because float64 carries more
# than twice float32's precision; this file uses no other operation, and uses no
# transcendental at all, which is the hazard bm25_gen.py had to guard.
#
# What is left to guard is the input. A literal that is not exactly
# representable would be rounded by the parser, and a cast or a divide that
# rounded would put the three hosts on different numbers before the first
# distance is taken. `guard()` refuses to print a fixture holding one, the same
# move bm25_gen.py's guard() and json_gen.py's agree() make -- so a
# disagreement becomes a generator failure here rather than a flaky lane later.
import math
import struct

M = 0xFFFFFFFF
D = 8  # the dimension; every store and query below is D wide
N = 12  # the store's rows
NQ = 5  # the query set's rows
QBASE = 1000000  # the query hash offset, so no query equals a stored row


def f32(x):
    return struct.unpack("<f", struct.pack("<f", x))[0]


def bits(x):
    return struct.unpack("<I", struct.pack("<f", x))[0]


def guard(x):
    if f32(x) != x or not math.isfinite(x):
        raise SystemExit("knn_gen: %r is not an exact finite F32; retune" % x)
    return x


def lit(x):
    # a negative float literal does not parse -- the language has no unary minus
    # on a term -- so a negative is written as the law that makes it one
    return ("F32.neg(%r)" % -x) if math.copysign(1.0, x) < 0 else repr(x)


# -- the store, as the fixture builds it -------------------------------------


def h(p):
    return ((p + 1) * 2654435761 & M) ^ (p >> 3)


# a hash into [-32, 32) in steps of 1/128: an integer under 2^24 cast to F32 and
# divided by a power of two, so both steps are exact and every stored float is
# the same number on all three hosts.
#
# The thirteen bits are taken off the TOP and not with a mod. A multiply moves
# information upward only, so the low bits of (p + 1) * C see only the low bits
# of p -- and `% 8192` would then make v blind to any base that is a multiple of
# 2^13, which is every base anyone would pick. The benches were written that way
# first: their queries came out byte-identical to their store, and their shards
# to each other, and the C twin agreed all the way because it reproduced the
# same degenerate data.
def v(p):
    return guard(((h(p) >> 19) - 4096) / 128.0)


def mk(base, n, d):
    return [[v(base + i * d + c) for c in range(d)] for i in range(n)]


# -- the reference -----------------------------------------------------------


def key(x):
    b = bits(f32(x + 0.0))
    return (~b & M) if b >= 0x80000000 else (b | 0x80000000)


def near(x):
    return M - key(x)


def l2(a, b):
    s = 0.0
    for x, y in zip(a, b):
        t = f32(x - y)
        s = f32(s + f32(t * t))
    return s


def ip(a, b):
    s = 0.0
    for x, y in zip(a, b):
        s = f32(s + f32(x * y))
    return s


def norm(a):
    s = 0.0
    for x in a:
        s = f32(s + f32(x * x))
    return f32(math.sqrt(s))


def normalize(rows):
    out = []
    for a in rows:
        r = norm(a)
        out.append(a if r == 0.0 else [f32(x / r) for x in a])
    return out


# the K greatest (key, val) pairs, best first: TopK's own order, so a tie in the
# key is settled by the greater row and never by the scan order
def search(rows, q, k, score, rank):
    pairs = sorted(((rank(score(a, q)), i) for i, a in enumerate(rows)), reverse=True)
    return " ".join("%d:%d" % (i, kk) for kk, i in pairs[:k])


# -- the fixture -------------------------------------------------------------

rows, want = [], []


def row(call, answer):
    rows.append(call)
    want.append(str(answer))


ST, QS = mk(0, N, D), mk(QBASE, NQ, D)
NS = normalize(ST)
NQS = normalize(QS)
S = "mk(0, %d, %d)" % (N, D)
Q = "mk(%d, %d, %d)" % (QBASE, NQ, D)

# the map itself, on the floats that make its claim hard: -0.0 must land on
# +0.0's key, every negative must land under every positive, and the nine must
# come out ascending, because that ordering is the whole of what the search
# relies on
for x in [-32.0, -1.5, -0.125, -0.0, 0.0, 0.125, 1.5, 32.0, 4096.0]:
    row("u(Knn.key(%s))" % lit(x), key(x))
for x in [0.0, 0.125, 1.5, 32.0, 4096.0]:
    row("u(Knn.near(%s))" % lit(x), near(x))

# the shape of the store it builds, and six of its cells
row("sz(Knn.size(%s))" % S, N)
row("sz(Knn.dim(%s))" % S, D)
for i, c in [(0, 0), (0, 7), (1, 3), (6, 4), (11, 0), (11, 7)]:
    row("n1(Knn.at(%s, %d, %d))" % (S, i, c), key(ST[i][c]))

# every row against query 0, then three rows against every query: the first
# sweeps the store, the second sweeps the query set, and together they cover the
# index arithmetic in both arguments without printing the full 60
for i in range(N):
    row("d2(Knn.l2(%s, %d, %s, 0))" % (S, i, Q), key(l2(ST[i], QS[0])))
    row("d2(Knn.ip(%s, %d, %s, 0))" % (S, i, Q), key(ip(ST[i], QS[0])))
for j in range(1, NQ):
    for i in [0, 5, 11]:
        row("d2(Knn.l2(%s, %d, %s, %d))" % (S, i, Q, j), key(l2(ST[i], QS[j])))
        row("d2(Knn.ip(%s, %d, %s, %d))" % (S, i, Q, j), key(ip(ST[i], QS[j])))

# a row against itself is 0, which is the one distance whose bits are worth
# naming: key(0.0), not key(-0.0), and not a near-zero sum of eight cancelling
# squares
row("d2(Knn.l2(%s, 3, %s, 3))" % (S, S), key(0.0))

# the norms, then the norms after normalize -- which are 1.0 to whatever the
# divide leaves, and the fixture prints the bits rather than assuming it is 1.0
for i in range(N):
    row("n1(Knn.norm(%s, %d))" % (S, i), key(norm(ST[i])))
for i in range(N):
    row("n1(Knn.norm(Knn.normalize(%s), %d))" % (S, i), key(norm(NS[i])))

# cosine: normalize both sides, then inner product. Every value lands in
# [-1, 1], which is where the key map's sign handling earns its keep.
for j in range(NQ):
    row(
        "d2(Knn.ip(Knn.normalize(%s), 0, Knn.normalize(%s), %d))" % (S, Q, j),
        key(ip(NS[0], NQS[j])),
    )

# a zero row keeps its zeros instead of becoming eight NaNs, and its inner
# product with everything stays 0 -- the answer a cosine search should give it
row("n1(Knn.norm(Knn.normalize(zeros(3, %d)), 1))" % D, key(0.0))
row("d2(Knn.ip(Knn.normalize(zeros(3, %d)), 1, %s, 0))" % (D, Q), key(0.0))

# the searches, at a K under the store, at K = n, and at a K over it
for j in range(NQ):
    for k in [1, 3, N, N + 8]:
        row(
            "res(Knn.search_l2(%s, %s, %d, %d))" % (S, Q, j, k),
            search(ST, QS[j], k, l2, near),
        )
        row(
            "res(Knn.search_ip(%s, %s, %d, %d))" % (S, Q, j, k),
            search(ST, QS[j], k, ip, key),
        )

# the same search on a normalized store, which is what a cosine index is
for j in range(NQ):
    row(
        "res(Knn.search_ip(Knn.normalize(%s), Knn.normalize(%s), %d, 4))" % (S, Q, j),
        search(NS, NQS[j], 4, ip, key),
    )

# the edges: K = 0, a one-row store, a one-column store, and a store whose rows
# are all equal, where every key ties and only the row number separates them
row("res(Knn.search_l2(%s, %s, 0, 0))" % (S, Q), "")
row(
    "res(Knn.search_l2(mk(0, 1, %d), %s, 2, 4))" % (D, Q),
    search(mk(0, 1, D), QS[2], 4, l2, near),
)
row(
    "res(Knn.search_l2(mk(0, %d, 1), mk(%d, %d, 1), 1, 3))" % (N, QBASE, NQ),
    search(mk(0, N, 1), mk(QBASE, NQ, 1)[1], 3, l2, near),
)
row(
    "res(Knn.search_ip(zeros(5, %d), %s, 0, 3))" % (D, Q),
    search([[0.0] * D] * 5, QS[0], 3, ip, key),
)

print(
    """# knn against plain CPython lists and floats (knn_gen.py prints this file). Every
# row is a U32: a distance is shown as Knn.key of it, which is that float's
# exact 32-bit pattern, so a row pins the arithmetic to the last bit and no
# decimal printer sits between the answer and the check.
import Base
import ../../power/heap.bend as Heap
import ../../power/knn.bend as Knn

# the store the rows build: cell p is a hash into [-32, 32) in steps of 1/128,
# an integer under 2^24 cast to F32 and divided by a power of two, so both steps
# are exact and the fixture pins the arithmetic and not the decimal parser
def h(+p: U32) -> U32:
  U32.xor(U32.mul(U32.inc(p), 2654435761), U32.shrn(p, 3n))

def v(+p: U32) -> F32:
  F32.div(F32.sub(U32.to_f32(U32.shrn(h(p), 19n)), 4096.0), 128.0)

def mk.go(fuel: Nat, +p: U32, f: Knn.Flat) -> Knn.Flat:
  match fuel:
    case 0n:
      f
    case 1n++q:
      mk.go(q, U32.inc(p), Knn.push(f, v(p)))

def mk(+base: U32, +n: U32, +d: U32) -> Knn.Flat:
  mk.go(U32.to_nat(U32.mul(n, d)), base, Knn.new(d))

def zeros.go(fuel: Nat, f: Knn.Flat) -> Knn.Flat:
  match fuel:
    case 0n:
      f
    case 1n++q:
      zeros.go(q, Knn.push(f, 0.0))

def zeros(+n: U32, +d: U32) -> Knn.Flat:
  zeros.go(U32.to_nat(U32.mul(n, d)), Knn.new(d))

def u(+x: U32) -> String:
  U32.show(x)

def sz(r: Knn.Flat & U32) -> String:
  (f, n) = r
  U32.show(n)

def n1(r: Knn.Flat & F32) -> String:
  (f, x) = r
  U32.show(Knn.key(x))

def d2(r: Knn.Flat & Knn.Flat & F32) -> String:
  (f, q, x) = r
  U32.show(Knn.key(x))

def ents(xs: List<&2, Heap.Entry>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{Heap.Entry{k, val}, t}:
      Con{U32.show(val) ++ ":" ++ U32.show(k), ents(t)}

def res(r: Knn.Flat & Knn.Flat & List<&2, Heap.Entry>) -> String:
  (f, q, xs) = r
  String.join(ents(xs), " ")

def main() -> IO(Unit):
  do IO<Unit>:"""
)
for r in rows:
    print("    IO.print(%s)" % r)
for w in want:
    print("#|" + w)
