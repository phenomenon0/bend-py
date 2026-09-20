# Bm25: an inverted index whose postings carry their score already computed, and
# a query that is one add per posting. That is BM25S's move: BM25's term
# frequency and length terms depend only on the document, and its idf only on
# the term, so the whole per-posting weight is known at index time and a query
# stops being arithmetic and becomes a gather.
#
# The scores are fixed point U32 at 2^20, not floats, and that is the one
# decision worth arguing. Vec holds U32; a float would have to ride as its own
# bit pattern, and base.bend hands out F32.bits with no way back. Integers also
# add associatively, so a document's score does not depend on the order its
# terms arrived in and a forked query sums to the same bits as a straight one --
# the exact / ordered split power-1 had to draw for Scan does not arise here.
# And TopK ranks U32 keys already, so no float-keyed heap is needed at all.
#
# Written for the compiled lanes: build is two stable radix passes (so the
# postings come out grouped by term with their documents ascending), one walk
# that turns the (term, document) runs into postings, one prefix sum for the CSR
# row table, and one nested loop that prices them -- one logarithm per term, not
# per posting. A query touches each posting once: read the document, read the
# weight, add.
#
# Contract: document ids are below nd, and a query term at or past nt is a word
# the index never saw and scores nothing (a query is text, so that is normal).
import Base
import ./vec.bend as Vec
import ./scan.bend as Scan
import ./radix.bend as Radix
import ./heap.bend as Heap
import ./topk.bend as TopK
import ./postings.bend as Postings

type Index is Type:
  Index{nd: U32, nt: U32, ptr: Vec.Vec, docs: Vec.Vec, wgt: Vec.Vec}

# k1, b and the average document length, carried through the scoring loops as
# one copyable value
type Cfg is Data:
  Cfg{k1: F64, b: F64, avgdl: F64, nd: U32}

def cfg.nd(c: Cfg) -> U32:
  match c:
    case Cfg{k1, b, avgdl, nd}:
      nd

# where one term's postings start and end; empty for a term outside the
# vocabulary
type Span is Data:
  Span{s: U32, e: U32}

def sp.s(x: Span) -> U32:
  match x:
    case Span{s, e}:
      s

def sp.e(x: Span) -> U32:
  match x:
    case Span{s, e}:
      e

def sp.len(x: Span) -> U32:
  match x:
    case Span{s, e}:
      U32.sub(e, s)

def span.e(+s: U32, r: Vec.Vec & U32) -> Vec.Vec & Span:
  (ptr, e) = r
  (ptr, Span{s, e})

def span.s(+t: U32, r: Vec.Vec & U32) -> Vec.Vec & Span:
  (ptr, s) = r
  span.e(s, Vec.at(ptr, U32.inc(t)))

def span.if(ptr: Vec.Vec, +t: U32, ok: Bool) -> Vec.Vec & Span:
  match ok:
    case True{}:
      span.s(t, Vec.at(ptr, t))
    case False{}:
      (ptr, Span{0, 0})

# the row table has nt + 1 entries, so term t's row is [ptr[t], ptr[t+1])
def span(ptr: Vec.Vec, +t: U32, +nt: U32) -> Vec.Vec & Span:
  span.if(ptr, t, U32.is_lt(t, nt))

# -- the arithmetic ----------------------------------------------------------

# 2^20: a weight is at most the largest idf, under 23 for any corpus that fits
# in a U32 document count, so a sum over a few hundred query terms still has
# room. The quantum is one part in a million of a score of 1.
def scale() -> F64:
  1048576.0d

def quant(x: F64) -> U32:
  F64.to_u32(F64.add(F64.mul(x, scale()), 0.5d))

# the fixed point score as a float, for a caller that wants to print it
def score(+q: U32) -> F64:
  F64.div(U32.to_f64(q), scale())

# the Lucene / BM25S idf, which is positive for every df -- an idf that could go
# negative could not ride in a U32
def idf(+df: U32, +nd: U32) -> F64:
  F64.log(F64.add(1.0d,
    F64.div(F64.add(F64.sub(U32.to_f64(nd), U32.to_f64(df)), 0.5d),
            F64.add(U32.to_f64(df), 0.5d))))

# w = idf * tf / (tf + k1 * (1 - b + b * dl / avgdl))
def weight(id: F64, +tf: U32, +dl: U32, c: Cfg) -> F64:
  match c:
    case Cfg{k1, +b, avgdl, nd}:
      norm = F64.mul(k1, F64.add(F64.sub(1.0d, b), F64.mul(b, F64.div(U32.to_f64(dl), avgdl))))
      F64.mul(id, F64.div(U32.to_f64(tf), F64.add(U32.to_f64(tf), norm)))

# saturating: a document that somehow tops 2^32 in fixed point clamps rather
# than wrapping, which would rank it last instead of first
def sat.if(+a: U32, +x: U32, over: Bool) -> U32:
  match over:
    case True{}:
      4294967295
    case False{}:
      U32.add(a, x)

def sat(+a: U32, +x: U32) -> U32:
  sat.if(a, x, U32.is_lt(U32.sub(4294967295, a), x))

# -- the (term, document) runs -----------------------------------------------

type Out is Type:
  Out{pd: Vec.Vec, tf: Vec.Vec, dfs: Vec.Vec}

def run.inc(+key: U32, r: Vec.Vec & U32) -> Vec.Vec:
  (dfs, c) = r
  Vec.put(dfs, key, U32.inc(c))

# one run becomes one posting: its document, its term frequency, and one more
# document for the term's df
def emit(o: Out, +key: U32, +doc: U32, +run: U32) -> Out:
  match o:
    case Out{pd, tf, dfs}:
      Out{Vec.push(pd, doc), Vec.push(tf, run), run.inc(key, Vec.at(dfs, key))}

type Run is Type:
  Run{t: Vec.Vec, d: Vec.Vec, o: Out, key: U32, doc: U32, run: U32}

def run.same(t: Vec.Vec, d: Vec.Vec, o: Out, +key: U32, +doc: U32, +run: U32, +ti: U32, +di: U32, same: Bool) -> Run:
  match same:
    case True{}:
      Run{t, d, o, key, doc, U32.inc(run)}
    case False{}:
      Run{t, d, emit(o, key, doc, run), ti, di, 1}

def run.di(t: Vec.Vec, o: Out, +key: U32, +doc: U32, +run: U32, +ti: U32, r: Vec.Vec & U32) -> Run:
  (d, +di) = r
  run.same(t, d, o, key, doc, run, ti, di, Bool.and(U32.is_eq(ti, key), U32.is_eq(di, doc)))

def run.ti(d: Vec.Vec, o: Out, +key: U32, +doc: U32, +run: U32, +i: U32, r: Vec.Vec & U32) -> Run:
  (t, ti) = r
  run.di(t, o, key, doc, run, ti, Vec.at(d, i))

# the pairs arrive sorted by term and, within a term, by document, so a run
# breaks when either column changes -- which is why this is a walk of its own
# and not Scan.rle over one column
def run.go(fuel: Nat, +i: U32, s: Run) -> Run:
  match fuel:
    case 0n:
      s
    case 1n++p:
      match s:
        case Run{t, d, o, key, doc, run}:
          run.go(p, U32.inc(i), run.ti(d, o, key, doc, run, i, Vec.at(t, i)))

def run.seed.d(t: Vec.Vec, +key: U32, +nt: U32, r: Vec.Vec & U32) -> Run:
  (d, doc) = r
  Run{t, d, Out{Vec.new(0), Vec.new(0), Radix.zeros(nt)}, key, doc, 1}

def run.seed(d: Vec.Vec, +nt: U32, r: Vec.Vec & U32) -> Run:
  (t, key) = r
  run.seed.d(t, key, nt, Vec.at(d, 0))

# the last run has no successor to close it, so it is flushed here; the two
# sorted columns are spent
def run.fin(s: Run) -> Out:
  match s:
    case Run{t, d, o, key, doc, run}:
      emit(o, key, doc, run)

def group.if(t: Vec.Vec, d: Vec.Vec, +nt: U32, +n: U32, empty: Bool) -> Out:
  match empty:
    case True{}:
      Out{Vec.new(0), Vec.new(0), Radix.zeros(nt)}
    case False{}:
      run.fin(run.go(U32.to_nat(U32.sub(n, 1)), 1, run.seed(d, nt, Vec.at(t, 0))))

def group.len(d: Vec.Vec, +nt: U32, r: Vec.Vec & U32) -> Out:
  (t, +n) = r
  group.if(t, d, nt, n, U32.is_zero(n))

def group(t: Vec.Vec, d: Vec.Vec, +nt: U32) -> Out:
  group.len(d, nt, Vec.len(t))

# -- pricing the postings ----------------------------------------------------

type Sc is Type:
  Sc{tf: Vec.Vec, pd: Vec.Vec, dl: Vec.Vec, w: Vec.Vec}

def sc.w(tf: Vec.Vec, pd: Vec.Vec, w: Vec.Vec, +i: U32, id: F64, +tfi: U32, c: Cfg, r: Vec.Vec & U32) -> Sc:
  (dl, li) = r
  Sc{tf, pd, dl, Vec.put(w, i, quant(weight(id, tfi, li, c)))}

def sc.doc(tf: Vec.Vec, dl: Vec.Vec, w: Vec.Vec, +i: U32, id: F64, +tfi: U32, c: Cfg, r: Vec.Vec & U32) -> Sc:
  (pd, doc) = r
  sc.w(tf, pd, w, i, id, tfi, c, Vec.at(dl, doc))

def sc.tf(pd: Vec.Vec, dl: Vec.Vec, w: Vec.Vec, +i: U32, id: F64, c: Cfg, r: Vec.Vec & U32) -> Sc:
  (tf, tfi) = r
  sc.doc(tf, dl, w, i, id, tfi, c, Vec.at(pd, i))

# the inner loop: one term's postings, its idf already in hand
def sc.go(fuel: Nat, +i: U32, +id: F64, +c: Cfg, s: Sc) -> Sc:
  match fuel:
    case 0n:
      s
    case 1n++p:
      match s:
        case Sc{tf, pd, dl, w}:
          sc.go(p, U32.inc(i), id, c, sc.tf(pd, dl, w, i, id, c, Vec.at(tf, i)))

type Bd is Type:
  Bd{ptr: Vec.Vec, sc: Sc}

# one logarithm a term, not a posting: df is the row's own length
def bd.run(ptr: Vec.Vec, +c: Cfg, x: Sc, +sp: Span) -> Bd:
  Bd{ptr, sc.go(U32.to_nat(sp.len(sp)), sp.s(sp), idf(sp.len(sp), cfg.nd(c)), c, x)}

def bd.sp(+c: Cfg, x: Sc, r: Vec.Vec & Span) -> Bd:
  (ptr, sp) = r
  bd.run(ptr, c, x, sp)

def bd.go(fuel: Nat, +t: U32, +nt: U32, +c: Cfg, x: Bd) -> Bd:
  match fuel:
    case 0n:
      x
    case 1n++p:
      match x:
        case Bd{ptr, s}:
          bd.go(p, U32.inc(t), nt, c, bd.sp(c, s, span(ptr, t, nt)))

# -- build -------------------------------------------------------------------

def same(x: U32) -> U32:
  x

def build.mk(+nt: U32, +nd: U32, ptr: Vec.Vec, s: Sc) -> Index:
  match s:
    case Sc{tf, pd, dl, w}:
      Index{nd, nt, ptr, pd, w}

def build.fin(+nt: U32, +nd: U32, x: Bd) -> Index:
  match x:
    case Bd{ptr, s}:
      build.mk(nt, nd, ptr, s)

def build.sc(+nt: U32, +c: Cfg, x: Bd) -> Index:
  build.fin(nt, cfg.nd(c), bd.go(U32.to_nat(nt), 0, nt, c, x))

def build.ptr(dl: Vec.Vec, +nt: U32, +c: Cfg, pd: Vec.Vec, tf: Vec.Vec, r: Vec.Vec & U32) -> Index:
  (ptr, +np) = r
  build.sc(nt, c, Bd{Vec.push(ptr, np), Sc{tf, pd, dl, Radix.zeros(np)}})

def build.out(dl: Vec.Vec, +nt: U32, +c: Cfg, o: Out) -> Index:
  match o:
    case Out{pd, tf, dfs}:
      build.ptr(dl, nt, c, pd, tf, Scan.offsets(dfs))

def build.grp(dl: Vec.Vec, +nt: U32, +c: Cfg, r: Vec.Vec & Vec.Vec) -> Index:
  (t2, d2) = r
  build.out(dl, nt, c, group(t2, d2, nt))

# the second pass is by term and stable, so the first pass's document order
# survives inside every term: two counting sorts, no comparison anywhere
def build.srt(dl: Vec.Vec, +nt: U32, +c: Cfg, r: Vec.Vec & Vec.Vec) -> Index:
  (d1, t1) = r
  build.grp(dl, nt, c, Radix.sort_by_key(t1, d1))

def build.tot(terms: Vec.Vec, dl: Vec.Vec, +nt: U32, +nd: U32, k1: F64, b: F64, r: Vec.Vec & U32) -> Index:
  (docs, tot) = r
  build.srt(dl, nt, Cfg{k1, b, F64.div(U32.to_f64(tot), U32.to_f64(nd)), nd}, Radix.sort_by_key(docs, terms))

def build.dl(terms: Vec.Vec, +nt: U32, +nd: U32, k1: F64, b: F64, r: Vec.Vec & Vec.Vec) -> Index:
  (docs, dl) = r
  build.tot(terms, dl, nt, nd, k1, b, Vec.len(docs))

# build: one occurrence per (term, document) row -- terms[i] appears in
# docs[i] -- repeated as often as it occurs. Lucene's defaults are k1 = 1.2 and
# b = 0.75. A document length is its occurrence count, so a document with no
# terms has length 0 and still exists.
def build(terms: Vec.Vec, docs: Vec.Vec, +nt: U32, +nd: U32, k1: F64, b: F64) -> Index:
  build.dl(terms, nt, nd, k1, b, Radix.histogram(~same, nd, docs))

# -- query -------------------------------------------------------------------

type Qy is Type:
  Qy{ptr: Vec.Vec, docs: Vec.Vec, wgt: Vec.Vec, acc: Vec.Vec}

def qy.put(ptr: Vec.Vec, docs: Vec.Vec, wgt: Vec.Vec, +doc: U32, +wi: U32, r: Vec.Vec & U32) -> Qy:
  (acc, a) = r
  Qy{ptr, docs, wgt, Vec.put(acc, doc, sat(a, wi))}

def qy.acc(ptr: Vec.Vec, docs: Vec.Vec, acc: Vec.Vec, +doc: U32, r: Vec.Vec & U32) -> Qy:
  (wgt, wi) = r
  qy.put(ptr, docs, wgt, doc, wi, Vec.at(acc, doc))

def qy.doc(ptr: Vec.Vec, wgt: Vec.Vec, acc: Vec.Vec, +i: U32, r: Vec.Vec & U32) -> Qy:
  (docs, doc) = r
  qy.acc(ptr, docs, acc, doc, Vec.at(wgt, i))

# one posting: read the document, read the weight, add. No arithmetic.
def qy.go(fuel: Nat, +i: U32, q: Qy) -> Qy:
  match fuel:
    case 0n:
      q
    case 1n++p:
      match q:
        case Qy{ptr, docs, wgt, acc}:
          qy.go(p, U32.inc(i), qy.doc(ptr, wgt, acc, i, Vec.at(docs, i)))

type Qt is Type:
  Qt{q: Vec.Vec, y: Qy}

def qt.run(qv: Vec.Vec, ptr: Vec.Vec, docs: Vec.Vec, wgt: Vec.Vec, acc: Vec.Vec, +sp: Span) -> Qt:
  Qt{qv, qy.go(U32.to_nat(sp.len(sp)), sp.s(sp), Qy{ptr, docs, wgt, acc})}

def qt.sp(qv: Vec.Vec, docs: Vec.Vec, wgt: Vec.Vec, acc: Vec.Vec, r: Vec.Vec & Span) -> Qt:
  (ptr, sp) = r
  qt.run(qv, ptr, docs, wgt, acc, sp)

def qt.term(docs: Vec.Vec, wgt: Vec.Vec, acc: Vec.Vec, ptr: Vec.Vec, +nt: U32, r: Vec.Vec & U32) -> Qt:
  (qv, t) = r
  qt.sp(qv, docs, wgt, acc, span(ptr, t, nt))

# a repeated query term adds its postings twice, which is the query term
# frequency doing its work
def qt.go(fuel: Nat, +j: U32, +nt: U32, x: Qt) -> Qt:
  match fuel:
    case 0n:
      x
    case 1n++p:
      match x:
        case Qt{qv, y}:
          match y:
            case Qy{ptr, docs, wgt, acc}:
              qt.go(p, U32.inc(j), nt, qt.term(docs, wgt, acc, ptr, nt, Vec.at(qv, j)))

def query.mk(+nd: U32, +nt: U32, y: Qy) -> Index & Vec.Vec:
  match y:
    case Qy{ptr, docs, wgt, acc}:
      (Index{nd, nt, ptr, docs, wgt}, acc)

def query.out(+nd: U32, +nt: U32, x: Qt) -> Index & Vec.Vec:
  match x:
    case Qt{qv, y}:
      query.mk(nd, nt, y)

def query.len(+nd: U32, +nt: U32, ptr: Vec.Vec, docs: Vec.Vec, wgt: Vec.Vec, r: Vec.Vec & U32) -> Index & Vec.Vec:
  (qv, n) = r
  query.out(nd, nt, qt.go(U32.to_nat(n), 0, nt, Qt{qv, Qy{ptr, docs, wgt, Radix.zeros(nd)}}))

# query: the score of every document, in fixed point, one entry per document.
# The query is a Vec of term ids and is spent.
def query(ix: Index, qv: Vec.Vec) -> Index & Vec.Vec:
  match ix:
    case Index{+nd, +nt, ptr, docs, wgt}:
      query.len(nd, nt, ptr, docs, wgt, Vec.len(qv))

# -- ranking -----------------------------------------------------------------

type Rk is Type:
  Rk{v: Vec.Vec, t: TopK.TopK}

def rk.off(t: TopK.TopK, +doc: U32, +s: U32, hit: Bool) -> TopK.TopK:
  match hit:
    case True{}:
      TopK.offer(t, s, doc)
    case False{}:
      t

def rk.at(t: TopK.TopK, +doc: U32, r: Vec.Vec & U32) -> Rk:
  (v, +s) = r
  Rk{v, rk.off(t, doc, s, U32.is_ne(s, 0))}

def rk.go(fuel: Nat, +i: U32, x: Rk) -> Rk:
  match fuel:
    case 0n:
      x
    case 1n++p:
      match x:
        case Rk{v, t}:
          rk.go(p, U32.inc(i), rk.at(t, i, Vec.at(v, i)))

def rk.drain(v: Vec.Vec, r: TopK.TopK & List<&2, Heap.Entry>) -> Vec.Vec & List<&2, Heap.Entry>:
  (t, xs) = r
  (v, xs)

def rk.out(x: Rk) -> Vec.Vec & List<&2, Heap.Entry>:
  match x:
    case Rk{v, t}:
      rk.drain(v, TopK.drain(t))

def rank.n(+k: U32, r: Vec.Vec & U32) -> Vec.Vec & List<&2, Heap.Entry>:
  (v, n) = r
  rk.out(rk.go(U32.to_nat(n), 0, Rk{v, TopK.new(k)}))

# rank: the k best documents as (score, document), best first. A document no
# query term touched scores zero and is not a hit, so it is never offered.
def rank(v: Vec.Vec, +k: U32) -> Vec.Vec & List<&2, Heap.Entry>:
  rank.n(k, Vec.len(v))

# -- the filter meets the ranking --------------------------------------------

type Kp is Type:
  Kp{src: Vec.Vec, m: Vec.Vec, out: Vec.Vec}

def kp.set(m: Vec.Vec, +doc: U32, out: Vec.Vec, r: Vec.Vec & U32) -> Kp:
  (src, s) = r
  Kp{src, m, Vec.put(out, doc, s)}

def kp.doc(out: Vec.Vec, src: Vec.Vec, r: Vec.Vec & U32) -> Kp:
  (m, +doc) = r
  kp.set(m, doc, out, Vec.at(src, doc))

def kp.go(fuel: Nat, +j: U32, x: Kp) -> Kp:
  match fuel:
    case 0n:
      x
    case 1n++p:
      match x:
        case Kp{src, m, out}:
          kp.go(p, U32.inc(j), kp.doc(out, src, Vec.at(m, j)))

def kp.out(x: Kp) -> Vec.Vec:
  match x:
    case Kp{src, m, out}:
      out

def keep.n(src: Vec.Vec, +nd: U32, r: Vec.Vec & U32) -> Vec.Vec:
  (m, nm) = r
  kp.out(kp.go(U32.to_nat(nm), 0, Kp{src, m, Radix.zeros(nd)}))

# keep: the scores of the documents the filter admits and zero everywhere else,
# which is a boolean filter applied to a ranking without a second pass over the
# postings. The filter walks its own members, so a narrow one is cheap whatever
# the corpus is.
def keep(v: Vec.Vec, s: Postings.Set, +nd: U32) -> Vec.Vec:
  keep.n(v, nd, Vec.len(Postings.to_vec(s)))

# -- reading the index -------------------------------------------------------

def df.out(+nd: U32, +nt: U32, docs: Vec.Vec, wgt: Vec.Vec, r: Vec.Vec & Span) -> Index & U32:
  (ptr, sp) = r
  (Index{nd, nt, ptr, docs, wgt}, sp.len(sp))

# df: in how many documents term t occurs
def df(ix: Index, +t: U32) -> Index & U32:
  match ix:
    case Index{nd, +nt, ptr, docs, wgt}:
      df.out(nd, nt, docs, wgt, span(ptr, t, nt))

type Cp is Type:
  Cp{src: Vec.Vec, out: Vec.Vec}

def cp.push(out: Vec.Vec, r: Vec.Vec & U32) -> Cp:
  (src, x) = r
  Cp{src, Vec.push(out, x)}

def cp.go(fuel: Nat, +i: U32, x: Cp) -> Cp:
  match fuel:
    case 0n:
      x
    case 1n++p:
      match x:
        case Cp{src, out}:
          cp.go(p, U32.inc(i), cp.push(out, Vec.at(src, i)))

def cp.out(x: Cp) -> Vec.Vec & Vec.Vec:
  match x:
    case Cp{src, out}:
      (src, out)

def slice(v: Vec.Vec, +sp: Span) -> Vec.Vec & Vec.Vec:
  cp.out(cp.go(U32.to_nat(sp.len(sp)), sp.s(sp), Cp{v, Vec.new(0)}))

def pl.out(+nd: U32, +nt: U32, ptr: Vec.Vec, wgt: Vec.Vec, r: Vec.Vec & Vec.Vec) -> Index & Postings.Set:
  (docs, row) = r
  (Index{nd, nt, ptr, docs, wgt}, Postings.Sparse{row})

def pl.sp(+nd: U32, +nt: U32, docs: Vec.Vec, wgt: Vec.Vec, r: Vec.Vec & Span) -> Index & Postings.Set:
  (ptr, sp) = r
  pl.out(nd, nt, ptr, wgt, slice(docs, sp))

# postings: the documents holding term t, as a set the boolean algebra takes.
# The row is already ascending and unique, which is exactly a sparse set.
def postings(ix: Index, +t: U32) -> Index & Postings.Set:
  match ix:
    case Index{nd, +nt, ptr, docs, wgt}:
      pl.sp(nd, nt, docs, wgt, span(ptr, t, nt))

def ex.out(+nd: U32, +nt: U32, ptr: Vec.Vec, docs: Vec.Vec, r: Vec.Vec & U32) -> Index & U32:
  (wgt, w) = r
  (Index{nd, nt, ptr, docs, wgt}, w)

def ex.get(+nd: U32, +nt: U32, ptr: Vec.Vec, docs: Vec.Vec, wgt: Vec.Vec, +i: U32, hit: Bool) -> Index & U32:
  match hit:
    case True{}:
      ex.out(nd, nt, ptr, docs, Vec.at(wgt, i))
    case False{}:
      (Index{nd, nt, ptr, docs, wgt}, 0)

def ex.cmp(+nd: U32, +nt: U32, ptr: Vec.Vec, wgt: Vec.Vec, +doc: U32, +i: U32, r: Vec.Vec & U32) -> Index & U32:
  (docs, y) = r
  ex.get(nd, nt, ptr, docs, wgt, i, U32.is_eq(y, doc))

def ex.eq(+nd: U32, +nt: U32, ptr: Vec.Vec, wgt: Vec.Vec, +doc: U32, +i: U32, docs: Vec.Vec, ok: Bool) -> Index & U32:
  match ok:
    case True{}:
      ex.cmp(nd, nt, ptr, wgt, doc, i, Vec.at(docs, i))
    case False{}:
      (Index{nd, nt, ptr, docs, wgt}, 0)

def ex.chk(+nd: U32, +nt: U32, ptr: Vec.Vec, wgt: Vec.Vec, +doc: U32, +e: U32, r: Vec.Vec & U32) -> Index & U32:
  (docs, +i) = r
  ex.eq(nd, nt, ptr, wgt, doc, i, docs, U32.is_lt(i, e))

def ex.lo(+nd: U32, +nt: U32, ptr: Vec.Vec, wgt: Vec.Vec, +doc: U32, docs: Vec.Vec, +sp: Span) -> Index & U32:
  ex.chk(nd, nt, ptr, wgt, doc, sp.e(sp), Postings.lower(docs, doc, sp.s(sp), sp.e(sp)))

def ex.sp(+nd: U32, +nt: U32, docs: Vec.Vec, wgt: Vec.Vec, +doc: U32, r: Vec.Vec & Span) -> Index & U32:
  (ptr, sp) = r
  ex.lo(nd, nt, ptr, wgt, doc, docs, sp)

# explain: what term t contributes to document doc, in the same fixed point the
# query sums. Zero if the term is not in that document. The row is ascending, so
# this is a binary search and not a scan.
def explain(ix: Index, +t: U32, +doc: U32) -> Index & U32:
  match ix:
    case Index{nd, +nt, ptr, docs, wgt}:
      ex.sp(nd, nt, docs, wgt, doc, span(ptr, t, nt))
