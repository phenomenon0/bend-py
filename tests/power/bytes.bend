# Bytes against a CPython bytearray (bytes_gen.py prints this file): a seeded script of
# operations, every observation one line, the final contents the last.
import Base
import ../../power/bytes.bend as Bytes

type Op is Data:
  Push{x: U32}
  Pop{}
  Get{i: U32}
  Set{i: U32, x: U32}
  Trunc{k: U32}
  Len{}

def St() -> Type:
  Bytes.Bytes & List<&2, String>

def seen(r: Bytes.Bytes & Maybe<&2, U32>, out: List<&2, String>) -> St():
  (v, m) = r
  match m:
    case None{}:
      (v, Con{"none", out})
    case Some{x}:
      (v, Con{U32.show(x), out})

def told(r: Bytes.Bytes & Bool, out: List<&2, String>) -> St():
  (v, b) = r
  match b:
    case True{}:
      (v, Con{"true", out})
    case False{}:
      (v, Con{"false", out})

def sized(r: Bytes.Bytes & U32, out: List<&2, String>) -> St():
  (v, n) = r
  (v, Con{U32.show(n), out})

def step(o: Op, v: Bytes.Bytes, out: List<&2, String>) -> St():
  match o:
    case Push{x}:
      (Bytes.push(v, x), out)
    case Pop{}:
      seen(Bytes.pop(v), out)
    case Get{i}:
      seen(Bytes.get(v, i), out)
    case Set{i, x}:
      told(Bytes.set(v, i, x), out)
    case Trunc{k}:
      (Bytes.truncate(v, k), out)
    case Len{}:
      sized(Bytes.len(v), out)

def open(o: Op, st: St()) -> St():
  (v, out) = st
  step(o, v, out)

def run(ops: List<&2, Op>, st: St()) -> St():
  match ops:
    case Nil{}:
      st
    case Con{op, t}:
      run(t, open(op, st))

def shows(xs: List<&2, U32>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{x, t}:
      Con{U32.show(x), shows(t)}

def last(r: Bytes.Bytes & List<&2, U32>, out: List<&2, String>) -> List<&2, String>:
  (v, xs) = r
  Con{String.join(shows(xs), ", "), out}

def report(st: St()) -> String:
  (v, out) = st
  String.join(List.reverse(&2, String, last(Bytes.to_list(v), out)), "\n")

def script() -> List<&2, Op>:
  [
    Pop{}, Get{0}, Len{}, Trunc{0}, Trunc{0}, Push{0},
    Push{0}, Push{0}, Push{1}, Get{11}, Push{237}, Set{12, 1},
    Pop{}, Push{145}, Push{1}, Set{4294967295, 1403297626}, Push{1}, Set{14, 11},
    Push{2882472384}, Push{792924342}, Push{116}, Push{1}, Push{1}, Push{2546116342},
    Push{0}, Trunc{3}, Trunc{1}, Set{8, 211}, Push{1}, Set{4294967295, 1},
    Set{2, 0}, Push{0}, Trunc{4294967295}, Pop{}, Len{}, Push{26},
    Trunc{0}, Set{0, 0}, Push{184}, Pop{}, Push{1}, Push{0},
    Len{}, Push{4294967295}, Get{3}, Set{3, 109}, Set{10, 218}, Push{4294967295},
    Get{4294967295}, Push{1}, Pop{}, Push{125}, Push{30}, Len{},
    Push{0}, Push{1}, Set{4294967295, 756898656}, Push{1}, Set{0, 4294967295}, Trunc{4294967295},
    Get{4294967295}, Push{4294967295}, Push{512320681}, Push{1}, Push{0}, Trunc{4294967295},
    Set{4294967295, 255}, Trunc{20}, Get{10}, Push{1}, Get{13}, Trunc{4294967295},
    Push{0}, Len{}, Pop{}, Pop{}, Pop{}, Pop{},
    Pop{}, Pop{}, Pop{}, Pop{}, Pop{}, Pop{},
    Pop{}, Pop{}, Pop{}, Pop{}, Pop{}, Pop{},
    Pop{}, Push{1}, Push{0}, Set{1, 3844350184}, Get{1}, Set{2, 0},
    Push{4294967295}, Push{0}, Pop{}, Trunc{0}, Push{855047769}, Trunc{0},
    Push{0}, Set{4294967295, 0}, Push{4294967295}, Push{0}, Push{534595498}, Push{4294967295},
    Trunc{0}, Push{0}, Push{1}, Set{2, 0}, Len{}, Trunc{9},
    Len{}, Push{1}, Get{10}, Trunc{3}, Set{0, 233}, Trunc{4294967295},
    Push{4294967295}, Push{1}, Set{12, 4294967295}, Push{1}, Trunc{4294967295}, Push{2956525077},
    Push{1}, Push{4294967295}, Len{}, Get{4294967295}, Push{0}, Push{45},
    Set{18, 4294967295}, Push{196}, Set{19, 3916058436}, Push{947697481}, Trunc{8}, Set{3, 0},
    Push{3451754886}, Push{1}, Push{27}, Push{1}, Get{10}, Push{0},
    Push{2471972044}, Get{4294967295}, Push{2139149980}, Trunc{22}, Push{4294967295}, Push{2105972037},
    Push{1}, Push{4168124716}, Push{4294967295}, Push{0}, Set{21, 85}, Push{4294967295},
    Len{}, Set{4294967295, 4294967295}, Push{209}, Push{3611258040}, Pop{}, Len{}
  ]

def main() -> IO(Unit):
  IO.print(report(run(script(), (Bytes.new(), []))))

#|none
#|none
#|0
#|none
#|false
#|237
#|false
#|false
#|false
#|false
#|false
#|0
#|2
#|false
#|184
#|2
#|none
#|false
#|false
#|none
#|1
#|6
#|false
#|true
#|none
#|false
#|169
#|1
#|15
#|0
#|1
#|0
#|1
#|169
#|255
#|1
#|1
#|0
#|30
#|125
#|255
#|255
#|0
#|255
#|none
#|none
#|true
#|232
#|false
#|0
#|false
#|false
#|2
#|2
#|none
#|true
#|false
#|9
#|none
#|false
#|false
#|true
#|27
#|none
#|false
#|22
#|false
#|184
#|23
#|233, 1, 1, 0, 1, 1, 21, 1, 134, 1, 27, 1, 0, 204, 156, 255, 69, 1, 44, 255, 0, 255, 209
