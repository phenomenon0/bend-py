#!/usr/bin/env python3
# The oracle for bm25.bend: prints the whole fixture. The reference below is
# plain CPython -- dicts and floats, no Vec, no radix, no CSR -- so a row checks
# the index, not a second copy of it.
#
# The one hazard is the logarithm. A weight is quantized with
# floor(w * 2^20 + 0.5), and V8's Math.log, glibc's log and CPython's math.log
# need not agree in the last ulp; where that matters is a weight whose scaled
# value sits on an integer boundary. `guard()` refuses to print a fixture
# holding one, the same move json_gen.py's agree() makes -- so a disagreement
# between the three hosts becomes a generator failure here rather than a flaky
# lane later.
import math
import random

rng = random.Random(20260926)
SCALE = float(1 << 20)
M = 0xFFFFFFFF


def quant(x):
    return int(math.floor(x * SCALE + 0.5))


def guard(x):
    v = x * SCALE + 0.5
    if abs(v - round(v)) < 1e-6:
        raise SystemExit(
            "bm25_gen: weight %r quantizes on an integer boundary; reseed" % x
        )
    return x


class Ref:
    """BM25 exactly as power/bm25.bend spells it, in floats and dicts."""

    def __init__(self, pairs, nt, nd, k1, b):
        self.nt, self.nd, self.k1, self.b = nt, nd, k1, b
        self.dl = [0] * nd
        tf = {}
        for t, d in pairs:
            self.dl[d] += 1
            tf[(t, d)] = tf.get((t, d), 0) + 1
        self.avgdl = float(sum(self.dl)) / float(nd)
        self.rows = {}
        for (t, d), n in sorted(tf.items()):
            self.rows.setdefault(t, []).append((d, n))
        self.w = {}
        for t, posts in self.rows.items():
            df = float(len(posts))
            idf = math.log(1.0 + ((float(nd) - df) + 0.5) / (df + 0.5))
            for d, n in posts:
                norm = k1 * ((1.0 - b) + b * (float(self.dl[d]) / self.avgdl))
                self.w[(t, d)] = quant(guard(idf * (float(n) / (float(n) + norm))))

    def df(self, t):
        return len(self.rows.get(t, []))

    def postings(self, t):
        return [d for d, _ in self.rows.get(t, [])]

    def explain(self, t, d):
        return self.w.get((t, d), 0)

    def query(self, qs):
        acc = [0] * self.nd
        for t in qs:
            if t < self.nt:
                for d, _ in self.rows.get(t, []):
                    acc[d] = min(acc[d] + self.w[(t, d)], M)
        return acc

    def rank(self, qs, k):
        acc = self.query(qs)
        hits = [(s, d) for d, s in enumerate(acc) if s]
        hits.sort(reverse=True)
        return ["%d:%d" % (d, s) for s, d in hits[:k]]

    def fold(self, ts, d):
        acc = 0
        for t in ts:
            acc = min(acc + self.explain(t, d), M)
        return acc

    def keep(self, qs, ids):
        acc = self.query(qs)
        return [acc[d] if d in ids else 0 for d in range(self.nd)]


def lit(xs):
    return "[%s]" % ", ".join(map(str, xs))


def show(xs):
    return " ".join(map(str, xs))


corpora, rows, want = [], [], []


def corpus(name, nt, nd, occ, k1, b, zipf=1.0):
    """occ (term, doc) pairs; a zipf exponent above 0 gives the vocabulary the
    skew a real one has, so the common terms carry long rows and the rare ones
    a single posting."""
    weights = [1.0 / (i + 1) ** zipf for i in range(nt)]
    pairs = []
    for _ in range(occ):
        t = rng.choices(range(nt), weights)[0]
        pairs.append((t, rng.randrange(nd)))
    ts, ds = [t for t, _ in pairs], [d for _, d in pairs]
    corpora.append(
        "def %s() -> Bm25.Index:\n  Bm25.build(of(%s), of(%s), %d, %d, %s, %s)\n"
        % (name, lit(ts), lit(ds), nt, nd, f64(k1), f64(b))
    )
    return Ref(pairs, nt, nd, k1, b)


def f64(x):
    return repr(float(x)) + "d"


# the hand-checked corpus from the lane's own probe: three documents, three
# terms, every tf and every document length different
HAND = [(0, 0), (1, 0), (1, 0), (1, 1), (2, 1), (0, 2), (2, 2), (2, 2), (2, 2)]
corpora.append(
    "def c0() -> Bm25.Index:\n  Bm25.build(of(%s), of(%s), 3, 3, 1.2d, 0.75d)\n"
    % (lit([t for t, _ in HAND]), lit([d for _, d in HAND]))
)
hand = Ref(HAND, 3, 3, 1.2, 0.75)

# Lucene's defaults, a skewed vocabulary, and two documents that share no term
c1 = corpus("c1", 12, 9, 60, 1.2, 0.75, zipf=1.2)
# b = 0: no length normalization at all, so a long document is not penalised
c2 = corpus("c2", 20, 14, 90, 0.9, 0.0, zipf=0.8)
# a wider index, k1 low so tf saturates fast
c3 = corpus("c3", 40, 30, 220, 0.4, 0.4, zipf=1.0)

for name, ref in [("c0", hand), ("c1", c1), ("c2", c2), ("c3", c3)]:
    live = sorted(ref.rows)
    qs = [
        [live[0]],
        [live[len(live) // 2]],
        live[:3],
        live[:1] * 2,
        [ref.nt + 5],
        [],
        live[:6] + live[:2],
    ]
    for q in qs:
        rows.append("q(%s(), %s)" % (name, lit(q)))
        want.append(show(ref.query(q)))
    big = live[:4]
    for k in [1, 3, ref.nd, 0]:
        rows.append("rk(Bm25.query(%s(), of(%s)), %d)" % (name, lit(big), k))
        want.append(" ".join(ref.rank(big, k)))
    for t in [live[0], live[-1], ref.nt + 1]:
        rows.append("dout(Bm25.df(%s(), %d))" % (name, t))
        want.append(str(ref.df(t)))
        rows.append("pout(Bm25.postings(%s(), %d))" % (name, t))
        want.append(show(ref.postings(t)))
    t = live[0]
    for d in [ref.postings(t)[0], ref.postings(t)[-1], ref.nd - 1]:
        rows.append("dout(Bm25.explain(%s(), %d, %d))" % (name, t, d))
        want.append(str(ref.explain(t, d)))
    # the whole point of the pair: a boolean filter narrowing a ranking
    keep = sorted(set(ref.postings(live[0])) | {0})
    rows.append(
        "kout(Bm25.query(%s(), of(%s)), Postings.of_list(%s), %d)"
        % (name, lit(big), lit(keep), ref.nd)
    )
    want.append(show(ref.keep(big, set(keep))))
    # every posting of every term explained, summed back to the query score:
    # explain is the query's own arithmetic, one term at a time
    rows.append("q(%s(), %s)" % (name, lit(live)))
    want.append(show([ref.fold(live, d) for d in range(ref.nd)]))

print("""# Bm25 against a plain-CPython reference (bm25_gen.py prints this file). A score
# row is one fixed point score a document, at 2^20; a rank row is "doc:score"
# best first; a postings row the documents of one term.
import Base
import ../../power/vec.bend as Vec
import ../../power/heap.bend as Heap
import ../../power/postings.bend as Postings
import ../../power/bm25.bend as Bm25

def of(xs: List<&2, U32>) -> Vec.Vec:
  Vec.from_list(xs, Vec.new(0))

def shows(xs: List<&2, U32>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{x, t}:
      Con{U32.show(x), shows(t)}

def text(r: Vec.Vec & List<&2, U32>) -> String:
  (v, xs) = r
  String.join(shows(xs), " ")

def one(v: Vec.Vec) -> String:
  text(Vec.to_list(v))

def ents(xs: List<&2, Heap.Entry>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{Heap.Entry{k, x}, t}:
      Con{U32.show(x) ++ ":" ++ U32.show(k), ents(t)}

def qout(r: Bm25.Index & Vec.Vec) -> String:
  (i, v) = r
  one(v)

def q(ix: Bm25.Index, qs: List<&2, U32>) -> String:
  qout(Bm25.query(ix, of(qs)))

def rout(r: Vec.Vec & List<&2, Heap.Entry>) -> String:
  (v, xs) = r
  String.join(ents(xs), " ")

def rk(r: Bm25.Index & Vec.Vec, +k: U32) -> String:
  (i, v) = r
  rout(Bm25.rank(v, k))

def dout(r: Bm25.Index & U32) -> String:
  (i, n) = r
  U32.show(n)

def pout(r: Bm25.Index & Postings.Set) -> String:
  (i, s) = r
  one(Postings.to_vec(s))

def kout(r: Bm25.Index & Vec.Vec, s: Postings.Set, +nd: U32) -> String:
  (i, v) = r
  one(Bm25.keep(v, s, nd))
""")
for c in corpora:
    print(c)
print("""def main() -> IO(Unit):
  do IO<Unit>:""")
for r in rows:
    print("    IO.print(%s)" % r)
for w in want:
    print("#|" + w)
