# Vec against a CPython list (vec_gen.py prints this file): a seeded script of
# operations, every observation one line, the final contents the last.
import Base
import ../../power/vec.bend as Vec

type Op is Data:
  Push{x: U32}
  Pop{}
  Get{i: U32}
  Set{i: U32, x: U32}
  Swap{i: U32, j: U32}
  Trunc{k: U32}
  Len{}

def St() -> Type:
  Vec.Vec & List<&2, String>

def seen(r: Vec.Vec & Maybe<&2, U32>, out: List<&2, String>) -> St():
  (v, m) = r
  match m:
    case None{}:
      (v, Con{"none", out})
    case Some{x}:
      (v, Con{U32.show(x), out})

def told(r: Vec.Vec & Bool, out: List<&2, String>) -> St():
  (v, b) = r
  match b:
    case True{}:
      (v, Con{"true", out})
    case False{}:
      (v, Con{"false", out})

def sized(r: Vec.Vec & U32, out: List<&2, String>) -> St():
  (v, n) = r
  (v, Con{U32.show(n), out})

def step(o: Op, v: Vec.Vec, out: List<&2, String>) -> St():
  match o:
    case Push{x}:
      (Vec.push(v, x), out)
    case Pop{}:
      seen(Vec.pop(v), out)
    case Get{i}:
      seen(Vec.get(v, i), out)
    case Set{i, x}:
      told(Vec.set(v, i, x), out)
    case Swap{i, j}:
      (Vec.swap(v, i, j), out)
    case Trunc{k}:
      (Vec.truncate(v, k), out)
    case Len{}:
      sized(Vec.len(v), out)

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

def last(r: Vec.Vec & List<&2, U32>, out: List<&2, String>) -> List<&2, String>:
  (v, xs) = r
  Con{String.join(shows(xs), ", "), out}

def report(st: St()) -> String:
  (v, out) = st
  String.join(List.reverse(&2, String, last(Vec.to_list(v), out)), "\n")

def script() -> List<&2, Op>:
  [
    Pop{}, Get{0}, Len{}, Get{0}, Push{0}, Trunc{4294967295},
    Push{0}, Push{155920079}, Trunc{3}, Swap{2, 0}, Set{2, 0}, Trunc{3},
    Push{347365240}, Push{1091103052}, Set{4294967295, 1}, Push{1}, Push{1}, Set{6, 0},
    Trunc{2}, Push{1}, Push{168}, Get{4}, Push{273755936}, Push{3089482808},
    Swap{3, 1}, Push{4294967295}, Push{1}, Push{1}, Set{16, 0}, Push{4},
    Push{0}, Set{11, 0}, Swap{5, 6}, Push{0}, Push{1}, Set{13, 4294967295},
    Push{1}, Swap{3, 4}, Push{1}, Push{28}, Swap{12, 7}, Pop{},
    Push{0}, Get{5}, Set{7, 19}, Push{37864235}, Swap{5, 2}, Push{1},
    Len{}, Push{3883337434}, Pop{}, Get{18}, Push{0}, Push{4294967295},
    Push{1}, Get{4294967295}, Push{4294967295}, Set{22, 159}, Push{2612045745}, Set{5, 1909821904},
    Pop{}, Push{812049463}, Push{1}, Len{}, Push{87}, Push{4294967295},
    Push{225}, Pop{}, Get{26}, Set{3, 0}, Swap{17, 21}, Push{1},
    Push{4294967295}, Len{}, Pop{}, Pop{}, Pop{}, Pop{},
    Pop{}, Pop{}, Pop{}, Pop{}, Pop{}, Pop{},
    Pop{}, Pop{}, Pop{}, Pop{}, Pop{}, Pop{},
    Pop{}, Pop{}, Pop{}, Pop{}, Pop{}, Pop{},
    Pop{}, Pop{}, Pop{}, Pop{}, Pop{}, Pop{},
    Pop{}, Pop{}, Push{1}, Push{183}, Push{1}, Swap{0, 0},
    Push{91}, Set{1, 0}, Swap{3, 2}, Set{0, 146}, Get{11}, Set{4294967295, 36},
    Len{}, Set{11, 1}, Push{0}, Push{56}, Push{1}, Get{14},
    Swap{2, 4}, Trunc{5}, Push{0}, Get{3}, Push{0}, Set{4, 1},
    Push{876206115}, Pop{}, Push{3544094007}, Swap{0, 7}, Push{122}, Len{},
    Get{9}, Pop{}, Push{4294967295}, Push{4294967295}, Push{0}, Set{11, 0},
    Push{47}, Get{11}, Trunc{19}, Swap{11, 9}, Get{19}, Swap{8, 3},
    Push{1}, Set{13, 0}, Set{3, 4294967295}, Get{2}, Push{0}, Set{14, 0},
    Trunc{14}, Push{4294967295}, Push{175}, Trunc{23}, Push{28}, Swap{1, 8},
    Swap{2, 3}, Push{192}, Push{4203394355}, Trunc{19}, Push{2905009485}, Set{17, 225},
    Pop{}, Push{1}, Set{7, 1}, Push{1}, Pop{}, Push{4294967295},
    Push{1}, Push{1}, Push{1}, Swap{20, 17}, Get{31}, Push{202},
    Len{}
  ]

def main() -> IO(Unit):
  IO.print(report(run(script(), (Vec.new(0), []))))

#|none
#|none
#|0
#|none
#|true
#|false
#|true
#|none
#|false
#|false
#|false
#|28
#|4294967295
#|true
#|18
#|3883337434
#|none
#|none
#|false
#|true
#|2612045745
#|24
#|225
#|none
#|true
#|28
#|4294967295
#|1
#|4294967295
#|87
#|1
#|812049463
#|1
#|1
#|4294967295
#|0
#|4294967295
#|37864235
#|0
#|1
#|1
#|1
#|0
#|0
#|4
#|1
#|19
#|3089482808
#|1909821904
#|0
#|0
#|4294967295
#|168
#|155920079
#|none
#|none
#|true
#|true
#|none
#|false
#|4
#|false
#|none
#|1
#|true
#|876206115
#|9
#|none
#|122
#|false
#|47
#|none
#|false
#|true
#|0
#|false
#|true
#|2905009485
#|true
#|1
#|none
#|25
#|3544094007, 1, 4294967295, 0, 1, 0, 0, 1, 0, 47, 0, 4294967295, 1, 0, 4294967295, 175, 28, 4294967295, 4203394355, 1, 225, 1, 1, 1, 202
