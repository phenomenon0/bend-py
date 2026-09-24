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
  Word{i: U32}

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
    case Word{i}:
      sized(Bytes.word_le(v, i), out)

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
    Len{}, Set{4294967295, 4294967295}, Push{209}, Push{3611258040}, Pop{}, Len{},
    Push{139}, Push{2779629534}, Push{15}, Push{1}, Push{0}, Push{4294967295},
    Push{1}, Push{1758048286}, Push{122}, Push{0}, Push{2435331766}, Push{97},
    Push{3269686073}, Push{0}, Push{28}, Push{873333697}, Push{1}, Push{3436040399},
    Push{4294967295}, Push{207}, Push{1}, Push{4294967295}, Push{0}, Push{4294967295},
    Push{3947697606}, Push{4294967295}, Push{0}, Push{1}, Push{1}, Push{1},
    Push{2826493483}, Push{1}, Push{4294967295}, Push{45}, Push{4294967295}, Push{126},
    Push{35}, Push{4065706756}, Push{1}, Push{0}, Push{182}, Push{1803023368},
    Push{4294967295}, Push{224}, Push{0}, Push{1}, Push{1}, Push{2980536434},
    Push{1778217622}, Push{1}, Push{2685068594}, Push{68}, Push{4294967295}, Push{213},
    Push{3549507287}, Push{46}, Push{210}, Push{104}, Push{4294967295}, Push{0},
    Push{0}, Push{1897214542}, Push{228}, Push{0}, Push{4294967295}, Push{139},
    Push{181}, Push{0}, Push{1}, Push{2003668703}, Push{22}, Push{1},
    Push{0}, Push{0}, Push{106}, Push{1172043746}, Push{1}, Push{1258181305},
    Push{208}, Push{1}, Len{}, Word{0}, Word{1}, Word{2},
    Word{3}, Word{4}, Word{5}, Word{6}, Word{7}, Word{8},
    Word{9}, Word{10}, Word{11}, Word{16}, Word{17}, Word{30},
    Word{31}, Word{32}, Word{33}, Word{98}, Word{99}
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
#|103
#|66025
#|16777473
#|16842753
#|352387328
#|18153729
#|2248217857
#|25559317
#|453084673
#|18547078
#|72449
#|3422552347
#|2630615041
#|4281073989
#|16722945
#|3053484574
#|1639317626
#|962704896
#|3760566
#|3501785570
#|30456065
#|233, 1, 1, 0, 1, 1, 21, 1, 134, 1, 27, 1, 0, 204, 156, 255, 69, 1, 44, 255, 0, 255, 209, 139, 222, 15, 1, 0, 255, 1, 30, 122, 0, 182, 97, 57, 0, 28, 193, 1, 207, 255, 207, 1, 255, 0, 255, 198, 255, 0, 1, 1, 1, 43, 1, 255, 45, 255, 126, 35, 4, 1, 0, 182, 8, 255, 224, 0, 1, 1, 114, 150, 1, 50, 68, 255, 213, 215, 46, 210, 104, 255, 0, 0, 78, 228, 0, 255, 139, 181, 0, 1, 223, 22, 1, 0, 0, 106, 226, 1, 185, 208, 1
