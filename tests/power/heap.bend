# Heap against CPython's heapq (heap_gen.py prints this file): a seeded script
# of operations, every observation one line, the final drain the last.
import Base
import ../../power/heap.bend as Heap

type Op is Data:
  Push{k: U32, x: U32}
  Pop{}
  Peek{}
  Replace{k: U32, x: U32}
  Len{}

def St() -> Type:
  Heap.Heap & List<&2, String>

def show(e: Heap.Entry) -> String:
  match e:
    case Heap.Entry{k, x}:
      U32.show(k) ++ ":" ++ U32.show(x)

def seen(r: Heap.Heap & Maybe<&2, Heap.Entry>, out: List<&2, String>) -> St():
  (h, m) = r
  match m:
    case None{}:
      (h, Con{"none", out})
    case Some{e}:
      (h, Con{show(e), out})

def sized(r: Heap.Heap & U32, out: List<&2, String>) -> St():
  (h, n) = r
  (h, Con{U32.show(n), out})

def step(o: Op, h: Heap.Heap, out: List<&2, String>) -> St():
  match o:
    case Push{k, x}:
      (Heap.push(h, k, x), out)
    case Pop{}:
      seen(Heap.pop(h), out)
    case Peek{}:
      seen(Heap.peek(h), out)
    case Replace{k, x}:
      (Heap.replace(h, k, x), out)
    case Len{}:
      sized(Heap.len(h), out)

def open(o: Op, st: St()) -> St():
  (h, out) = st
  step(o, h, out)

def run(ops: List<&2, Op>, st: St()) -> St():
  match ops:
    case Nil{}:
      st
    case Con{o, t}:
      run(t, open(o, st))

def shows(xs: List<&2, Heap.Entry>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{e, t}:
      Con{show(e), shows(t)}

def last(r: Heap.Heap & List<&2, Heap.Entry>, out: List<&2, String>) -> List<&2, String>:
  (h, xs) = r
  Con{String.join(shows(xs), " "), out}

def report(st: St()) -> String:
  (h, out) = st
  String.join(List.reverse(&2, String, last(Heap.drain(h), out)), "\n")

def script() -> List<&2, Op>:
  [
    Pop{}, Peek{}, Replace{0, 104}, Pop{}, Peek{}, Push{4294967295, 686},
    Pop{}, Push{8, 4294967295}, Push{4, 400}, Push{4294967295, 210}, Peek{}, Push{2, 0},
    Replace{0, 1}, Replace{0, 0}, Push{0, 0}, Peek{}, Replace{10, 1}, Push{0, 212},
    Pop{}, Push{9, 363}, Peek{}, Replace{0, 356}, Peek{}, Pop{},
    Pop{}, Push{0, 152}, Len{}, Pop{}, Push{4294967295, 0}, Push{4294967295, 4294967295},
    Push{0, 4294967295}, Replace{0, 54}, Pop{}, Push{6, 4294967295}, Push{4294967295, 4294967295}, Len{},
    Push{0, 4294967295}, Pop{}, Push{4294967295, 4294967295}, Push{0, 0}, Pop{}, Push{0, 0},
    Push{0, 2}, Push{11, 4294967295}, Push{4294967295, 2}, Push{1, 4294967295}, Replace{0, 0}, Push{10, 2},
    Push{8, 0}, Push{11, 1}, Push{0, 4294967295}, Push{4294967295, 4294967295}, Pop{}, Push{4, 0},
    Push{11, 646}, Push{9, 0}, Pop{}, Push{4, 0}, Replace{7, 0}, Push{0, 0},
    Pop{}, Pop{}, Push{0, 0}, Push{4294967295, 4294967295}, Pop{}, Push{11, 0},
    Len{}, Pop{}, Pop{}, Pop{}, Replace{4294967295, 3}, Replace{4294967295, 2},
    Push{3, 0}, Push{0, 0}, Push{4294967295, 293}, Push{4, 328}, Push{5, 0}, Len{},
    Push{0, 4294967295}, Peek{}, Pop{}, Push{6, 0}, Push{4294967295, 31}, Push{4294967295, 4294967295},
    Pop{}, Replace{0, 2}, Push{5, 0}, Push{0, 4294967295}, Push{4294967295, 0}, Push{4294967295, 964},
    Push{3, 2}, Pop{}, Push{0, 3}, Len{}, Pop{}, Pop{},
    Pop{}, Pop{}, Pop{}, Pop{}, Pop{}, Pop{},
    Pop{}, Pop{}, Pop{}, Pop{}, Pop{}, Pop{},
    Pop{}, Pop{}, Pop{}, Pop{}, Pop{}, Pop{},
    Pop{}, Pop{}, Pop{}, Pop{}, Pop{}, Pop{},
    Pop{}, Pop{}, Pop{}, Pop{}, Pop{}, Pop{},
    Pop{}, Replace{6, 0}, Push{1, 1}, Peek{}, Len{}, Replace{7, 433},
    Push{7, 0}, Push{4294967295, 0}, Pop{}, Push{0, 4294967295}, Len{}, Push{4294967295, 423},
    Push{2, 0}, Pop{}, Push{3, 0}, Push{10, 207}, Replace{0, 0}, Push{6, 467},
    Replace{0, 0}, Push{10, 0}, Push{9, 1}, Push{0, 4294967295}, Pop{}, Pop{},
    Replace{0, 4294967295}, Pop{}, Push{4294967295, 0}, Pop{}, Replace{0, 4294967295}, Push{4294967295, 0},
    Push{0, 230}, Peek{}, Push{6, 962}, Peek{}, Push{0, 0}, Replace{11, 4294967295},
    Push{6, 4294967295}, Len{}, Push{0, 2}, Pop{}, Push{4294967295, 0}, Push{4294967295, 4294967295},
    Push{4294967295, 482}, Push{0, 4294967295}, Replace{4294967295, 0}, Peek{}, Peek{}, Push{2, 2},
    Peek{}, Replace{0, 632}, Pop{}, Replace{0, 932}, Peek{}, Pop{},
    Replace{4294967295, 2}, Push{4294967295, 258}, Pop{}, Pop{}, Pop{}, Pop{},
    Pop{}, Replace{11, 4294967295}, Push{4294967295, 0}, Peek{}, Push{4294967295, 0}, Push{3, 908},
    Push{0, 0}, Len{}, Peek{}, Push{4, 0}, Push{0, 0}, Push{5, 868},
    Push{0, 0}, Push{10, 4294967295}, Push{4, 1}, Len{}, Peek{}, Push{11, 2},
    Replace{9, 0}, Push{4294967295, 4294967295}, Push{0, 2}, Pop{}, Replace{0, 4294967295}, Push{0, 0},
    Replace{4294967295, 178}, Push{7, 3}, Replace{4294967295, 2}, Replace{0, 0}, Push{0, 0}, Len{},
    Push{0, 4294967295}, Len{}
  ]

def main() -> IO(Unit):
  IO.print(report(run(script(), (Heap.new(), []))))

#|none
#|none
#|0:104
#|none
#|4294967295:686
#|4:400
#|0:0
#|0:0
#|0:212
#|0:356
#|0:356
#|4:400
#|5
#|0:152
#|0:54
#|8
#|0:4294967295
#|0:0
#|0:0
#|0:2
#|0:0
#|1:4294967295
#|0:0
#|22
#|4:0
#|4:0
#|6:4294967295
#|24
#|0:0
#|0:0
#|0:4294967295
#|0:2
#|31
#|0:3
#|0:4294967295
#|3:2
#|4:328
#|5:0
#|5:0
#|6:0
#|8:4294967295
#|9:0
#|9:363
#|10:1
#|10:2
#|11:0
#|11:1
#|11:646
#|11:4294967295
#|4294967295:0
#|4294967295:0
#|4294967295:2
#|4294967295:2
#|4294967295:3
#|4294967295:31
#|4294967295:210
#|4294967295:293
#|4294967295:964
#|4294967295:4294967295
#|4294967295:4294967295
#|4294967295:4294967295
#|4294967295:4294967295
#|4294967295:4294967295
#|4294967295:4294967295
#|none
#|none
#|1:1
#|2
#|6:0
#|4
#|0:4294967295
#|0:0
#|0:4294967295
#|0:4294967295
#|6:467
#|0:230
#|0:230
#|13
#|0:2
#|0:4294967295
#|0:4294967295
#|0:4294967295
#|0:632
#|0:932
#|0:932
#|6:962
#|6:4294967295
#|7:433
#|9:1
#|10:0
#|11:4294967295
#|16
#|0:0
#|22
#|0:0
#|0:0
#|27
#|28
#|4294967295:4294967295 4294967295:4294967295 4294967295:482 4294967295:423 4294967295:258 4294967295:178 4294967295:2 4294967295:2 4294967295:0 4294967295:0 4294967295:0 4294967295:0 4294967295:0 4294967295:0 4294967295:0 11:4294967295 11:4294967295 11:2 10:4294967295 9:0 7:3 5:868 4:1 4:0 3:908 0:4294967295 0:0 0:0
