# Sketch algebra against a flat CPython list of registers and the truth from
# set(), Counter() and sorted() (sketch_gen.py prints this file). A row that
# carries two numbers carries both sides of one claim: the sketch's answer and
# what it is answering about, or two bracketings of the same merge, so an
# implementation that satisfies one side cannot print the line.
import Base
import ../../power/sketch.bend as Sk

def num(n: U32) -> String:
  U32.show(n)

def sfp(f: Sk.Fp) -> String:
  match f:
    case Sk.Fp{k, s, n}:
      Sk.show.algo(k) ++ ":" ++ U32.show(s) ++ ":" ++ U32.show(n)

def serr(e: Sk.Error) -> String:
  match e:
    case Sk.Mismatch{w, g}:
      "mismatch " ++ sfp(w) ++ " vs " ++ sfp(g)
    case Sk.Undefined{}:
      "undefined"

def sres(r: Sk.Res(Sk.Sketch)) -> String:
  match r:
    case Done{s}:
      U32.show(Sk.digest(s))
    case Fail{e}:
      serr(e)

def jres(r: Sk.Res(U32)) -> String:
  match r:
    case Done{x}:
      U32.show(x)
    case Fail{e}:
      serr(e)

def rr(x: Sk.Res(Sk.Sketch), y: Sk.Res(Sk.Sketch)) -> String:
  sres(x) ++ " " ++ sres(y)

def drow(s: Sk.Sketch) -> String:
  U32.show(Sk.digest(s))

# the estimate beside the truth set() counted
def erow(s: Sk.Sketch, +t: U32) -> String:
  U32.show(Sk.hll.estimate(s)) ++ " " ++ U32.show(t)

def mrow(r: Sk.Res(Sk.Sketch), +t: U32) -> String:
  match r:
    case Done{s}:
      erow(s, t)
    case Fail{e}:
      serr(e)

def crow(s: Sk.Sketch, +x: U32, +t: U32) -> String:
  U32.show(Sk.cm.estimate(s, x)) ++ " " ++ U32.show(t)

def jrow(r: Sk.Res(U32), +t: U32) -> String:
  jres(r) ++ " " ++ U32.show(t)

def qrow(r: Sk.Res(U32), +t: U32) -> String:
  jres(r) ++ " " ++ U32.show(t)

def mq(r: Sk.Res(Sk.Sketch), +q: U32, +t: U32) -> String:
  match r:
    case Done{s}:
      qrow(Sk.dd.quantile(s, q), t)
    case Fail{e}:
      serr(e)

# the streams: value at step t, and the squared variant that spreads a
# DDSketch over four octaves instead of one
def val(+t: U32, +a: U32, +b: U32, +k: U32) -> U32:
  U32.mod(U32.add(U32.mul(t, a), b), k)

def sq(+t: U32, +a: U32, +b: U32, +k: U32) -> U32:
  +v = U32.add(val(t, a, b, k), 1)
  U32.mul(v, v)

def hpart(i: Nat, s: Sk.Sketch, +off: U32, +a: U32, +b: U32, +k: U32) -> Sk.Sketch:
  match i:
    case 0n:
      s
    case 1n++p:
      hpart(p, Sk.hll.add(s, val(U32.add(off, U32.from_nat(p)), a, b, k)), off, a, b, k)

def cpart(i: Nat, s: Sk.Sketch, +off: U32, +a: U32, +b: U32, +k: U32) -> Sk.Sketch:
  match i:
    case 0n:
      s
    case 1n++p:
      +t = U32.add(off, U32.from_nat(p))
      cpart(p, Sk.cm.add(s, val(t, a, b, k), U32.add(U32.mod(t, 3), 1)), off, a, b, k)

def mpart(i: Nat, s: Sk.Sketch, +off: U32, +a: U32, +b: U32, +k: U32) -> Sk.Sketch:
  match i:
    case 0n:
      s
    case 1n++p:
      mpart(p, Sk.mh.add(s, val(U32.add(off, U32.from_nat(p)), a, b, k)), off, a, b, k)

def dpart(i: Nat, s: Sk.Sketch, +off: U32, +a: U32, +b: U32, +k: U32) -> Sk.Sketch:
  match i:
    case 0n:
      s
    case 1n++p:
      dpart(p, Sk.dd.add(s, U32.inc(val(U32.add(off, U32.from_nat(p)), a, b, k))), off, a, b, k)

def dqpart(i: Nat, s: Sk.Sketch, +off: U32, +a: U32, +b: U32, +k: U32) -> Sk.Sketch:
  match i:
    case 0n:
      s
    case 1n++p:
      dqpart(p, Sk.dd.add(s, sq(U32.add(off, U32.from_nat(p)), a, b, k)), off, a, b, k)

# a counter driven to the ceiling and charged again
def cmsat() -> Sk.Sketch:
  Sk.cm.add(Sk.cm.add(Sk.cm.new(7, 4n), 5, 4294967295), 5, 10)

def dz() -> Sk.Sketch:
  Sk.dd.add(Sk.dd.add(Sk.dd.add(Sk.dd.add(Sk.dd.new(7, 7n), 0), 0), 1), 5)

def dbig() -> Sk.Sketch:
  Sk.dd.add(Sk.dd.new(7, 7n), 4294967295)

# the fork tree: 2^d leaves, each its own sketch over its own range of the
# stream, merged back on the way up. The digest is the sequential digest at
# every depth, or the merge is not associative.
def htree(d: Nat, +off: U32, +n: U32, +a: U32, +b: U32, +k: U32) -> Sk.Res(Sk.Sketch):
  match d:
    case 0n:
      Done{hpart(U32.to_nat(n), Sk.hll.new(7, 6n), off, a, b, k)}
    case 1n++p:
      +h = U32.shr(n)
      x y = htree(p, off, h, a, b, k) htree(p, U32.add(off, h), h, a, b, k)
      Sk.merge2(x, y)

def ctree(d: Nat, +off: U32, +n: U32, +a: U32, +b: U32, +k: U32) -> Sk.Res(Sk.Sketch):
  match d:
    case 0n:
      Done{cpart(U32.to_nat(n), Sk.cm.new(7, 6n), off, a, b, k)}
    case 1n++p:
      +h = U32.shr(n)
      x y = ctree(p, off, h, a, b, k) ctree(p, U32.add(off, h), h, a, b, k)
      Sk.merge2(x, y)

def dtree(d: Nat, +off: U32, +n: U32, +a: U32, +b: U32, +k: U32) -> Sk.Res(Sk.Sketch):
  match d:
    case 0n:
      Done{dpart(U32.to_nat(n), Sk.dd.new(7, 7n), off, a, b, k)}
    case 1n++p:
      +h = U32.shr(n)
      x y = dtree(p, off, h, a, b, k) dtree(p, U32.add(off, h), h, a, b, k)
      Sk.merge2(x, y)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(num(Sk.hash(7, 0)))
    IO.print(num(Sk.hash(7, 1)))
    IO.print(num(Sk.hash(7, 2)))
    IO.print(num(Sk.hash(7, 1000)))
    IO.print(num(Sk.hash(7, 4294967295)))
    IO.print(num(Sk.nlz(0)))
    IO.print(num(Sk.nlz(1)))
    IO.print(num(Sk.nlz(255)))
    IO.print(num(Sk.nlz(2147483648)))
    IO.print(num(Sk.nlz(4294967295)))
    IO.print(num(Sk.dd.idx(0)))
    IO.print(num(Sk.dd.idx(1)))
    IO.print(num(Sk.dd.idx(2)))
    IO.print(num(Sk.dd.idx(3)))
    IO.print(num(Sk.dd.idx(4)))
    IO.print(num(Sk.dd.idx(5)))
    IO.print(num(Sk.dd.idx(8)))
    IO.print(num(Sk.dd.idx(17)))
    IO.print(num(Sk.dd.idx(1000)))
    IO.print(num(Sk.dd.idx(65535)))
    IO.print(num(Sk.dd.idx(2147483647)))
    IO.print(sfp(Sk.fp.of(Sk.hll.new(7, 6n))))
    IO.print(num(Sk.digest(Sk.hll.new(7, 6n))))
    IO.print(sfp(Sk.fp.of(Sk.cm.new(7, 6n))))
    IO.print(num(Sk.digest(Sk.cm.new(7, 6n))))
    IO.print(sfp(Sk.fp.of(Sk.mh.new(7, 6n))))
    IO.print(num(Sk.digest(Sk.mh.new(7, 6n))))
    IO.print(sfp(Sk.fp.of(Sk.dd.new(7, 7n))))
    IO.print(num(Sk.digest(Sk.dd.new(7, 7n))))
    IO.print(erow(hpart(400n, Sk.hll.new(7, 6n), 0, 1, 0, 100000), 400))
    IO.print(drow(hpart(400n, Sk.hll.new(7, 6n), 0, 1, 0, 100000)))
    IO.print(erow(hpart(2000n, Sk.hll.new(7, 6n), 0, 1, 0, 100000), 2000))
    IO.print(drow(hpart(2000n, Sk.hll.new(7, 6n), 0, 1, 0, 100000)))
    IO.print(erow(hpart(4096n, Sk.hll.new(7, 6n), 0, 1, 0, 100000), 4096))
    IO.print(drow(hpart(4096n, Sk.hll.new(7, 6n), 0, 1, 0, 100000)))
    IO.print(erow(hpart(4096n, Sk.hll.new(7, 6n), 0, 1, 0, 64), 64))
    IO.print(drow(hpart(4096n, Sk.hll.new(7, 6n), 0, 1, 0, 64)))
    IO.print(erow(hpart(4096n, Sk.hll.new(7, 6n), 0, 1, 0, 700), 700))
    IO.print(drow(hpart(4096n, Sk.hll.new(7, 6n), 0, 1, 0, 700)))
    IO.print(erow(hpart(20000n, Sk.hll.new(7, 6n), 0, 7, 3, 100000), 20000))
    IO.print(drow(hpart(20000n, Sk.hll.new(7, 6n), 0, 7, 3, 100000)))
    IO.print(erow(hpart(64n, Sk.hll.new(7, 6n), 0, 1, 0, 100000), 64))
    IO.print(drow(hpart(64n, Sk.hll.new(7, 6n), 0, 1, 0, 100000)))
    IO.print(erow(hpart(8n, Sk.hll.new(7, 6n), 0, 1, 0, 100000), 8))
    IO.print(drow(hpart(8n, Sk.hll.new(7, 6n), 0, 1, 0, 100000)))
    IO.print(rr(Sk.merge(hpart(200n, Sk.hll.new(7, 6n), 0, 1, 0, 100000), hpart(200n, Sk.hll.new(7, 6n), 200, 1, 0, 100000)), Done{hpart(400n, Sk.hll.new(7, 6n), 0, 1, 0, 100000)}))
    IO.print(rr(Sk.merge(hpart(1000n, Sk.hll.new(7, 6n), 0, 1, 0, 100000), hpart(1000n, Sk.hll.new(7, 6n), 1000, 1, 0, 100000)), Done{hpart(2000n, Sk.hll.new(7, 6n), 0, 1, 0, 100000)}))
    IO.print(rr(Sk.merge(hpart(2048n, Sk.hll.new(7, 6n), 0, 1, 0, 100000), hpart(2048n, Sk.hll.new(7, 6n), 2048, 1, 0, 100000)), Done{hpart(4096n, Sk.hll.new(7, 6n), 0, 1, 0, 100000)}))
    IO.print(rr(Sk.merge(hpart(2048n, Sk.hll.new(7, 6n), 0, 1, 0, 64), hpart(2048n, Sk.hll.new(7, 6n), 2048, 1, 0, 64)), Done{hpart(4096n, Sk.hll.new(7, 6n), 0, 1, 0, 64)}))
    IO.print(rr(Sk.merge(hpart(2048n, Sk.hll.new(7, 6n), 0, 1, 0, 700), hpart(2048n, Sk.hll.new(7, 6n), 2048, 1, 0, 700)), Done{hpart(4096n, Sk.hll.new(7, 6n), 0, 1, 0, 700)}))
    IO.print(rr(Sk.merge2(Sk.merge(hpart(133n, Sk.hll.new(7, 6n), 0, 1, 0, 100000), hpart(133n, Sk.hll.new(7, 6n), 133, 1, 0, 100000)), Done{hpart(133n, Sk.hll.new(7, 6n), 266, 1, 0, 100000)}), Sk.merge2(Done{hpart(133n, Sk.hll.new(7, 6n), 0, 1, 0, 100000)}, Sk.merge(hpart(133n, Sk.hll.new(7, 6n), 133, 1, 0, 100000), hpart(133n, Sk.hll.new(7, 6n), 266, 1, 0, 100000)))))
    IO.print(rr(Sk.merge2(Sk.merge(hpart(666n, Sk.hll.new(7, 6n), 0, 1, 0, 100000), hpart(666n, Sk.hll.new(7, 6n), 666, 1, 0, 100000)), Done{hpart(666n, Sk.hll.new(7, 6n), 1332, 1, 0, 100000)}), Sk.merge2(Done{hpart(666n, Sk.hll.new(7, 6n), 0, 1, 0, 100000)}, Sk.merge(hpart(666n, Sk.hll.new(7, 6n), 666, 1, 0, 100000), hpart(666n, Sk.hll.new(7, 6n), 1332, 1, 0, 100000)))))
    IO.print(rr(Sk.merge2(Sk.merge(hpart(1365n, Sk.hll.new(7, 6n), 0, 1, 0, 100000), hpart(1365n, Sk.hll.new(7, 6n), 1365, 1, 0, 100000)), Done{hpart(1365n, Sk.hll.new(7, 6n), 2730, 1, 0, 100000)}), Sk.merge2(Done{hpart(1365n, Sk.hll.new(7, 6n), 0, 1, 0, 100000)}, Sk.merge(hpart(1365n, Sk.hll.new(7, 6n), 1365, 1, 0, 100000), hpart(1365n, Sk.hll.new(7, 6n), 2730, 1, 0, 100000)))))
    IO.print(rr(Sk.merge2(Sk.merge(hpart(1365n, Sk.hll.new(7, 6n), 0, 1, 0, 64), hpart(1365n, Sk.hll.new(7, 6n), 1365, 1, 0, 64)), Done{hpart(1365n, Sk.hll.new(7, 6n), 2730, 1, 0, 64)}), Sk.merge2(Done{hpart(1365n, Sk.hll.new(7, 6n), 0, 1, 0, 64)}, Sk.merge(hpart(1365n, Sk.hll.new(7, 6n), 1365, 1, 0, 64), hpart(1365n, Sk.hll.new(7, 6n), 2730, 1, 0, 64)))))
    IO.print(rr(Sk.merge(hpart(400n, Sk.hll.new(7, 6n), 0, 1, 0, 100000), hpart(400n, Sk.hll.new(7, 6n), 0, 1, 0, 100000)), Done{hpart(400n, Sk.hll.new(7, 6n), 0, 1, 0, 100000)}))
    IO.print(rr(Sk.merge(hpart(2000n, Sk.hll.new(7, 6n), 0, 1, 0, 100000), hpart(2000n, Sk.hll.new(7, 6n), 0, 1, 0, 100000)), Done{hpart(2000n, Sk.hll.new(7, 6n), 0, 1, 0, 100000)}))
    IO.print(rr(Sk.merge(hpart(4096n, Sk.hll.new(7, 6n), 0, 1, 0, 100000), hpart(4096n, Sk.hll.new(7, 6n), 0, 1, 0, 100000)), Done{hpart(4096n, Sk.hll.new(7, 6n), 0, 1, 0, 100000)}))
    IO.print(mrow(Sk.merge(hpart(200n, Sk.hll.new(7, 6n), 0, 1, 0, 100000), hpart(200n, Sk.hll.new(7, 6n), 200, 1, 0, 100000)), 400))
    IO.print(mrow(Sk.merge(hpart(1000n, Sk.hll.new(7, 6n), 0, 1, 0, 100000), hpart(1000n, Sk.hll.new(7, 6n), 1000, 1, 0, 100000)), 2000))
    IO.print(mrow(Sk.merge(hpart(2048n, Sk.hll.new(7, 6n), 0, 1, 0, 100000), hpart(2048n, Sk.hll.new(7, 6n), 2048, 1, 0, 100000)), 4096))
    IO.print(mrow(Sk.merge(hpart(2048n, Sk.hll.new(7, 6n), 0, 1, 0, 64), hpart(2048n, Sk.hll.new(7, 6n), 2048, 1, 0, 64)), 64))
    IO.print(sres(Sk.merge(Sk.hll.new(7, 6n), Sk.hll.new(9, 6n))))
    IO.print(sres(Sk.merge(Sk.hll.new(7, 6n), Sk.hll.new(7, 5n))))
    IO.print(sres(Sk.merge(Sk.hll.new(7, 6n), Sk.cm.new(7, 6n))))
    IO.print(sres(Sk.merge2(Sk.merge(Sk.hll.new(7, 6n), Sk.hll.new(9, 6n)), Done{Sk.hll.new(7, 6n)})))
    IO.print(sres(htree(0n, 0, 4096, 1, 0, 100000)))
    IO.print(sres(htree(1n, 0, 4096, 1, 0, 100000)))
    IO.print(sres(htree(2n, 0, 4096, 1, 0, 100000)))
    IO.print(sres(htree(3n, 0, 4096, 1, 0, 100000)))
    IO.print(sres(htree(4n, 0, 4096, 1, 0, 100000)))
    IO.print(sres(htree(5n, 0, 4096, 1, 0, 100000)))
    IO.print(drow(hpart(4096n, Sk.hll.new(7, 6n), 0, 1, 0, 100000)))
    IO.print(crow(cpart(2048n, Sk.cm.new(7, 6n), 0, 1, 0, 256), 0, 15))
    IO.print(crow(cpart(2048n, Sk.cm.new(7, 6n), 0, 1, 0, 256), 32, 16))
    IO.print(crow(cpart(2048n, Sk.cm.new(7, 6n), 0, 1, 0, 256), 64, 17))
    IO.print(crow(cpart(2048n, Sk.cm.new(7, 6n), 0, 1, 0, 256), 96, 15))
    IO.print(crow(cpart(2048n, Sk.cm.new(7, 6n), 0, 1, 0, 256), 128, 16))
    IO.print(crow(cpart(2048n, Sk.cm.new(7, 6n), 0, 1, 0, 256), 160, 17))
    IO.print(crow(cpart(2048n, Sk.cm.new(7, 6n), 0, 1, 0, 256), 192, 15))
    IO.print(crow(cpart(2048n, Sk.cm.new(7, 6n), 0, 1, 0, 256), 224, 16))
    IO.print(num(Sk.cm.total(cpart(2048n, Sk.cm.new(7, 6n), 0, 1, 0, 256))))
    IO.print(drow(cpart(2048n, Sk.cm.new(7, 6n), 0, 1, 0, 256)))
    IO.print(crow(cpart(4096n, Sk.cm.new(7, 6n), 0, 3, 1, 1024), 0, 9))
    IO.print(crow(cpart(4096n, Sk.cm.new(7, 6n), 0, 3, 1, 1024), 128, 9))
    IO.print(crow(cpart(4096n, Sk.cm.new(7, 6n), 0, 3, 1, 1024), 256, 8))
    IO.print(crow(cpart(4096n, Sk.cm.new(7, 6n), 0, 3, 1, 1024), 384, 8))
    IO.print(crow(cpart(4096n, Sk.cm.new(7, 6n), 0, 3, 1, 1024), 512, 8))
    IO.print(crow(cpart(4096n, Sk.cm.new(7, 6n), 0, 3, 1, 1024), 640, 7))
    IO.print(crow(cpart(4096n, Sk.cm.new(7, 6n), 0, 3, 1, 1024), 768, 7))
    IO.print(crow(cpart(4096n, Sk.cm.new(7, 6n), 0, 3, 1, 1024), 896, 7))
    IO.print(num(Sk.cm.total(cpart(4096n, Sk.cm.new(7, 6n), 0, 3, 1, 1024))))
    IO.print(drow(cpart(4096n, Sk.cm.new(7, 6n), 0, 3, 1, 1024)))
    IO.print(rr(Sk.merge(cpart(1024n, Sk.cm.new(7, 6n), 0, 1, 0, 256), cpart(1024n, Sk.cm.new(7, 6n), 1024, 1, 0, 256)), Done{cpart(2048n, Sk.cm.new(7, 6n), 0, 1, 0, 256)}))
    IO.print(rr(Sk.merge2(Sk.merge(cpart(682n, Sk.cm.new(7, 6n), 0, 1, 0, 256), cpart(682n, Sk.cm.new(7, 6n), 682, 1, 0, 256)), Done{cpart(682n, Sk.cm.new(7, 6n), 1364, 1, 0, 256)}), Sk.merge2(Done{cpart(682n, Sk.cm.new(7, 6n), 0, 1, 0, 256)}, Sk.merge(cpart(682n, Sk.cm.new(7, 6n), 682, 1, 0, 256), cpart(682n, Sk.cm.new(7, 6n), 1364, 1, 0, 256)))))
    IO.print(rr(Sk.merge(cpart(2048n, Sk.cm.new(7, 6n), 0, 3, 1, 1024), cpart(2048n, Sk.cm.new(7, 6n), 2048, 3, 1, 1024)), Done{cpart(4096n, Sk.cm.new(7, 6n), 0, 3, 1, 1024)}))
    IO.print(rr(Sk.merge2(Sk.merge(cpart(1365n, Sk.cm.new(7, 6n), 0, 3, 1, 1024), cpart(1365n, Sk.cm.new(7, 6n), 1365, 3, 1, 1024)), Done{cpart(1365n, Sk.cm.new(7, 6n), 2730, 3, 1, 1024)}), Sk.merge2(Done{cpart(1365n, Sk.cm.new(7, 6n), 0, 3, 1, 1024)}, Sk.merge(cpart(1365n, Sk.cm.new(7, 6n), 1365, 3, 1, 1024), cpart(1365n, Sk.cm.new(7, 6n), 2730, 3, 1, 1024)))))
    IO.print(crow(cmsat(), 5, 4294967295))
    IO.print(drow(cmsat()))
    IO.print(rr(Sk.merge(cmsat(), cmsat()), Done{cmsat()}))
    IO.print(sres(Sk.merge(Sk.cm.new(7, 6n), Sk.cm.new(7, 4n))))
    IO.print(sres(Sk.merge(Sk.cm.new(3, 6n), Sk.cm.new(7, 6n))))
    IO.print(sres(ctree(0n, 0, 1024, 1, 0, 256)))
    IO.print(sres(ctree(1n, 0, 1024, 1, 0, 256)))
    IO.print(sres(ctree(2n, 0, 1024, 1, 0, 256)))
    IO.print(jrow(Sk.mh.jaccard(mpart(512n, Sk.mh.new(7, 6n), 0, 1, 0, 1024), mpart(512n, Sk.mh.new(7, 6n), 256, 1, 0, 1024)), 333))
    IO.print(jrow(Sk.mh.jaccard(mpart(512n, Sk.mh.new(7, 6n), 0, 1, 0, 1024), mpart(512n, Sk.mh.new(7, 6n), 0, 1, 0, 1024)), 1000))
    IO.print(jrow(Sk.mh.jaccard(mpart(512n, Sk.mh.new(7, 6n), 0, 1, 0, 1024), mpart(512n, Sk.mh.new(7, 6n), 512, 1, 0, 1024)), 0))
    IO.print(jrow(Sk.mh.jaccard(mpart(600n, Sk.mh.new(7, 6n), 0, 1, 0, 1024), mpart(600n, Sk.mh.new(7, 6n), 300, 1, 0, 1024)), 333))
    IO.print(jrow(Sk.mh.jaccard(mpart(256n, Sk.mh.new(7, 6n), 0, 1, 0, 4096), mpart(256n, Sk.mh.new(7, 6n), 64, 1, 0, 4096)), 600))
    IO.print(jrow(Sk.mh.jaccard(mpart(1000n, Sk.mh.new(7, 6n), 0, 3, 1, 2048), mpart(1000n, Sk.mh.new(7, 6n), 500, 3, 1, 2048)), 333))
    IO.print(drow(mpart(512n, Sk.mh.new(7, 6n), 0, 1, 0, 1024)))
    IO.print(drow(mpart(512n, Sk.mh.new(7, 6n), 256, 1, 0, 1024)))
    IO.print(drow(mpart(512n, Sk.mh.new(7, 6n), 512, 1, 0, 1024)))
    IO.print(rr(Sk.merge(mpart(256n, Sk.mh.new(7, 6n), 0, 1, 0, 1024), mpart(256n, Sk.mh.new(7, 6n), 256, 1, 0, 1024)), Done{mpart(512n, Sk.mh.new(7, 6n), 0, 1, 0, 1024)}))
    IO.print(rr(Sk.merge(mpart(256n, Sk.mh.new(7, 6n), 0, 1, 0, 1024), mpart(256n, Sk.mh.new(7, 6n), 0, 1, 0, 1024)), Done{mpart(256n, Sk.mh.new(7, 6n), 0, 1, 0, 1024)}))
    IO.print(jrow(Sk.mh.jaccard(mpart(256n, Sk.mh.new(7, 6n), 0, 1, 0, 1024), mpart(256n, Sk.mh.new(7, 6n), 0, 1, 0, 1024)), 1000))
    IO.print(rr(Sk.merge2(Sk.merge(mpart(170n, Sk.mh.new(7, 6n), 0, 1, 0, 1024), mpart(170n, Sk.mh.new(7, 6n), 170, 1, 0, 1024)), Done{mpart(170n, Sk.mh.new(7, 6n), 340, 1, 0, 1024)}), Sk.merge2(Done{mpart(170n, Sk.mh.new(7, 6n), 0, 1, 0, 1024)}, Sk.merge(mpart(170n, Sk.mh.new(7, 6n), 170, 1, 0, 1024), mpart(170n, Sk.mh.new(7, 6n), 340, 1, 0, 1024)))))
    IO.print(rr(Sk.merge(mpart(300n, Sk.mh.new(7, 6n), 0, 1, 0, 4096), mpart(300n, Sk.mh.new(7, 6n), 300, 1, 0, 4096)), Done{mpart(600n, Sk.mh.new(7, 6n), 0, 1, 0, 4096)}))
    IO.print(rr(Sk.merge(mpart(300n, Sk.mh.new(7, 6n), 0, 1, 0, 4096), mpart(300n, Sk.mh.new(7, 6n), 0, 1, 0, 4096)), Done{mpart(300n, Sk.mh.new(7, 6n), 0, 1, 0, 4096)}))
    IO.print(jrow(Sk.mh.jaccard(mpart(300n, Sk.mh.new(7, 6n), 0, 1, 0, 4096), mpart(300n, Sk.mh.new(7, 6n), 0, 1, 0, 4096)), 1000))
    IO.print(rr(Sk.merge2(Sk.merge(mpart(200n, Sk.mh.new(7, 6n), 0, 1, 0, 4096), mpart(200n, Sk.mh.new(7, 6n), 200, 1, 0, 4096)), Done{mpart(200n, Sk.mh.new(7, 6n), 400, 1, 0, 4096)}), Sk.merge2(Done{mpart(200n, Sk.mh.new(7, 6n), 0, 1, 0, 4096)}, Sk.merge(mpart(200n, Sk.mh.new(7, 6n), 200, 1, 0, 4096), mpart(200n, Sk.mh.new(7, 6n), 400, 1, 0, 4096)))))
    IO.print(sres(Sk.merge(Sk.mh.new(7, 6n), Sk.mh.new(8, 6n))))
    IO.print(jres(Sk.mh.jaccard(Sk.mh.new(7, 6n), Sk.mh.new(7, 5n))))
    IO.print(jres(Sk.mh.jaccard(Sk.mh.new(7, 6n), Sk.dd.new(7, 6n))))
    IO.print(qrow(Sk.dd.quantile(dpart(3000n, Sk.dd.new(7, 7n), 0, 1, 0, 5000), 0), 0))
    IO.print(qrow(Sk.dd.quantile(dpart(3000n, Sk.dd.new(7, 7n), 0, 1, 0, 5000), 100), 33))
    IO.print(qrow(Sk.dd.quantile(dpart(3000n, Sk.dd.new(7, 7n), 0, 1, 0, 5000), 250), 39))
    IO.print(qrow(Sk.dd.quantile(dpart(3000n, Sk.dd.new(7, 7n), 0, 1, 0, 5000), 500), 43))
    IO.print(qrow(Sk.dd.quantile(dpart(3000n, Sk.dd.new(7, 7n), 0, 1, 0, 5000), 750), 45))
    IO.print(qrow(Sk.dd.quantile(dpart(3000n, Sk.dd.new(7, 7n), 0, 1, 0, 5000), 900), 46))
    IO.print(qrow(Sk.dd.quantile(dpart(3000n, Sk.dd.new(7, 7n), 0, 1, 0, 5000), 990), 47))
    IO.print(qrow(Sk.dd.quantile(dpart(3000n, Sk.dd.new(7, 7n), 0, 1, 0, 5000), 1000), 47))
    IO.print(num(Sk.dd.count(dpart(3000n, Sk.dd.new(7, 7n), 0, 1, 0, 5000))))
    IO.print(drow(dpart(3000n, Sk.dd.new(7, 7n), 0, 1, 0, 5000)))
    IO.print(qrow(Sk.dd.quantile(dqpart(3000n, Sk.dd.new(7, 7n), 0, 1, 0, 181), 0), 0))
    IO.print(qrow(Sk.dd.quantile(dqpart(3000n, Sk.dd.new(7, 7n), 0, 1, 0, 181), 100), 34))
    IO.print(qrow(Sk.dd.quantile(dqpart(3000n, Sk.dd.new(7, 7n), 0, 1, 0, 181), 250), 44))
    IO.print(qrow(Sk.dd.quantile(dqpart(3000n, Sk.dd.new(7, 7n), 0, 1, 0, 181), 500), 52))
    IO.print(qrow(Sk.dd.quantile(dqpart(3000n, Sk.dd.new(7, 7n), 0, 1, 0, 181), 750), 57))
    IO.print(qrow(Sk.dd.quantile(dqpart(3000n, Sk.dd.new(7, 7n), 0, 1, 0, 181), 900), 59))
    IO.print(qrow(Sk.dd.quantile(dqpart(3000n, Sk.dd.new(7, 7n), 0, 1, 0, 181), 990), 60))
    IO.print(qrow(Sk.dd.quantile(dqpart(3000n, Sk.dd.new(7, 7n), 0, 1, 0, 181), 1000), 60))
    IO.print(num(Sk.dd.count(dqpart(3000n, Sk.dd.new(7, 7n), 0, 1, 0, 181))))
    IO.print(drow(dqpart(3000n, Sk.dd.new(7, 7n), 0, 1, 0, 181)))
    IO.print(qrow(Sk.dd.quantile(dpart(1024n, Sk.dd.new(7, 7n), 0, 7, 3, 64), 0), 0))
    IO.print(qrow(Sk.dd.quantile(dpart(1024n, Sk.dd.new(7, 7n), 0, 7, 3, 64), 100), 12))
    IO.print(qrow(Sk.dd.quantile(dpart(1024n, Sk.dd.new(7, 7n), 0, 7, 3, 64), 250), 16))
    IO.print(qrow(Sk.dd.quantile(dpart(1024n, Sk.dd.new(7, 7n), 0, 7, 3, 64), 500), 20))
    IO.print(qrow(Sk.dd.quantile(dpart(1024n, Sk.dd.new(7, 7n), 0, 7, 3, 64), 750), 23))
    IO.print(qrow(Sk.dd.quantile(dpart(1024n, Sk.dd.new(7, 7n), 0, 7, 3, 64), 900), 24))
    IO.print(qrow(Sk.dd.quantile(dpart(1024n, Sk.dd.new(7, 7n), 0, 7, 3, 64), 990), 24))
    IO.print(qrow(Sk.dd.quantile(dpart(1024n, Sk.dd.new(7, 7n), 0, 7, 3, 64), 1000), 24))
    IO.print(num(Sk.dd.count(dpart(1024n, Sk.dd.new(7, 7n), 0, 7, 3, 64))))
    IO.print(drow(dpart(1024n, Sk.dd.new(7, 7n), 0, 7, 3, 64)))
    IO.print(rr(Sk.merge(dpart(1500n, Sk.dd.new(7, 7n), 0, 1, 0, 5000), dpart(1500n, Sk.dd.new(7, 7n), 1500, 1, 0, 5000)), Done{dpart(3000n, Sk.dd.new(7, 7n), 0, 1, 0, 5000)}))
    IO.print(rr(Sk.merge2(Sk.merge(dpart(1000n, Sk.dd.new(7, 7n), 0, 1, 0, 5000), dpart(1000n, Sk.dd.new(7, 7n), 1000, 1, 0, 5000)), Done{dpart(1000n, Sk.dd.new(7, 7n), 2000, 1, 0, 5000)}), Sk.merge2(Done{dpart(1000n, Sk.dd.new(7, 7n), 0, 1, 0, 5000)}, Sk.merge(dpart(1000n, Sk.dd.new(7, 7n), 1000, 1, 0, 5000), dpart(1000n, Sk.dd.new(7, 7n), 2000, 1, 0, 5000)))))
    IO.print(mq(Sk.merge(dpart(1500n, Sk.dd.new(7, 7n), 0, 1, 0, 5000), dpart(1500n, Sk.dd.new(7, 7n), 1500, 1, 0, 5000)), 250, 39))
    IO.print(mq(Sk.merge(dpart(1500n, Sk.dd.new(7, 7n), 0, 1, 0, 5000), dpart(1500n, Sk.dd.new(7, 7n), 1500, 1, 0, 5000)), 500, 43))
    IO.print(mq(Sk.merge(dpart(1500n, Sk.dd.new(7, 7n), 0, 1, 0, 5000), dpart(1500n, Sk.dd.new(7, 7n), 1500, 1, 0, 5000)), 900, 46))
    IO.print(rr(Sk.merge(dqpart(1500n, Sk.dd.new(7, 7n), 0, 1, 0, 181), dqpart(1500n, Sk.dd.new(7, 7n), 1500, 1, 0, 181)), Done{dqpart(3000n, Sk.dd.new(7, 7n), 0, 1, 0, 181)}))
    IO.print(rr(Sk.merge2(Sk.merge(dqpart(1000n, Sk.dd.new(7, 7n), 0, 1, 0, 181), dqpart(1000n, Sk.dd.new(7, 7n), 1000, 1, 0, 181)), Done{dqpart(1000n, Sk.dd.new(7, 7n), 2000, 1, 0, 181)}), Sk.merge2(Done{dqpart(1000n, Sk.dd.new(7, 7n), 0, 1, 0, 181)}, Sk.merge(dqpart(1000n, Sk.dd.new(7, 7n), 1000, 1, 0, 181), dqpart(1000n, Sk.dd.new(7, 7n), 2000, 1, 0, 181)))))
    IO.print(mq(Sk.merge(dqpart(1500n, Sk.dd.new(7, 7n), 0, 1, 0, 181), dqpart(1500n, Sk.dd.new(7, 7n), 1500, 1, 0, 181)), 250, 44))
    IO.print(mq(Sk.merge(dqpart(1500n, Sk.dd.new(7, 7n), 0, 1, 0, 181), dqpart(1500n, Sk.dd.new(7, 7n), 1500, 1, 0, 181)), 500, 52))
    IO.print(mq(Sk.merge(dqpart(1500n, Sk.dd.new(7, 7n), 0, 1, 0, 181), dqpart(1500n, Sk.dd.new(7, 7n), 1500, 1, 0, 181)), 900, 59))
    IO.print(jres(Sk.dd.quantile(Sk.dd.new(7, 7n), 500)))
    IO.print(qrow(Sk.dd.quantile(dz(), 0), 0))
    IO.print(qrow(Sk.dd.quantile(dz(), 1000), 10))
    IO.print(num(Sk.dd.count(dz())))
    IO.print(drow(dz()))
    IO.print(num(Sk.dd.idx(4294967295)))
    IO.print(qrow(Sk.dd.quantile(dbig(), 500), 127))
    IO.print(sres(dtree(0n, 0, 1024, 1, 0, 5000)))
    IO.print(sres(dtree(1n, 0, 1024, 1, 0, 5000)))
    IO.print(sres(dtree(2n, 0, 1024, 1, 0, 5000)))
#|2146360224
#|1060665609
#|374637164
#|850515797
#|587193623
#|32
#|31
#|24
#|0
#|0
#|0
#|0
#|4
#|7
#|8
#|10
#|12
#|17
#|40
#|64
#|124
#|hll:7:64
#|1462417689
#|cm:7:64
#|356934492
#|mh:7:64
#|3216607647
#|dd:7:128
#|2601101346
#|415 400
#|1465624862
#|1656 2000
#|921711901
#|3995 4096
#|2091047001
#|65 64
#|3910062659
#|725 700
#|2076849332
#|15054 20000
#|3693707621
#|65 64
#|3910062659
#|8 8
#|3935401044
#|1465624862 1465624862
#|921711901 921711901
#|2091047001 2091047001
#|3910062659 3910062659
#|2076849332 2076849332
#|1465624862 1465624862
#|921711901 921711901
#|2091047001 2091047001
#|3910062659 3910062659
#|1465624862 1465624862
#|921711901 921711901
#|2091047001 2091047001
#|415 400
#|1656 2000
#|3995 4096
#|65 64
#|mismatch hll:7:64 vs hll:9:64
#|mismatch hll:7:64 vs hll:7:32
#|mismatch hll:7:64 vs cm:7:64
#|mismatch hll:7:64 vs hll:9:64
#|2091047001
#|2091047001
#|2091047001
#|2091047001
#|2091047001
#|2091047001
#|2091047001
#|191 15
#|194 16
#|191 17
#|193 15
#|239 16
#|226 17
#|174 15
#|222 16
#|4095
#|1027524772
#|478 9
#|493 9
#|475 8
#|424 8
#|496 8
#|484 7
#|416 7
#|424 7
#|8191
#|449378210
#|1027524772 1027524772
#|2302965566 2302965566
#|449378210 449378210
#|1346418658 1346418658
#|4294967295 4294967295
#|2088720334
#|2088720334 2088720334
#|mismatch cm:7:64 vs cm:7:16
#|mismatch cm:3:64 vs cm:7:64
#|1617423408
#|1617423408
#|1617423408
#|19 333
#|64 1000
#|0 0
#|22 333
#|35 600
#|18 333
#|2257909790
#|1319369274
#|2521031873
#|2257909790 2257909790
#|3400460627 3400460627
#|64 1000
#|2257909790 2257909790
#|3074081777 3074081777
#|2581355641 2581355641
#|64 1000
#|3074081777 3074081777
#|mismatch mh:7:64 vs mh:8:64
#|mismatch mh:7:64 vs mh:7:32
#|mismatch mh:7:64 vs dd:7:64
#|0 0
#|33 33
#|39 39
#|43 43
#|45 45
#|46 46
#|47 47
#|47 47
#|3000
#|4134585730
#|0 0
#|34 34
#|44 44
#|52 52
#|57 57
#|59 59
#|60 60
#|60 60
#|3000
#|754932168
#|0 0
#|12 12
#|16 16
#|20 20
#|23 23
#|24 24
#|24 24
#|24 24
#|1024
#|2815860578
#|4134585730 4134585730
#|4134585730 4134585730
#|39 39
#|43 43
#|46 46
#|754932168 754932168
#|754932168 754932168
#|44 44
#|52 52
#|59 59
#|undefined
#|0 0
#|10 10
#|4
#|2950189662
#|128
#|127 127
#|3436776446
#|3436776446
#|3436776446
