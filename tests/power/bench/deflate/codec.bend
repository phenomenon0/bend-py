# The deflate bench's codec: a file compressed at a level, or a raw deflate
# stream inflated, and the result written out; prints the length out.
# run.py holds what is written to CPython's.
#   bun bend2/main.ts tests/power/bench/deflate/codec.bend -o codec
#   ./codec c LEVEL IN OUT        ./codec d IN OUT
# OUT "-" writes nothing: the codec alone, what run.py times.
import Base
import ../../../../power/deflate.bend as D

type Pl is Data:
  More{acc: Bytes()}
  Stop{acc: Bytes()}

def plan.at(acc: Bytes(), +b: Bytes(), empty: Bool) -> Pl:
  match empty:
    case True{}:
      Stop{acc}
    case False{}:
      More{Bytes.append(acc, b)}

def plan(acc: Bytes(), res: Result<&1, &1, U32 & String, Bytes()>) -> Pl:
  match res:
    case Fail{e}:
      Stop{acc}
    case Done{+b}:
      plan.at(acc, b, Nat.is_eq(Bytes.len(b), 0n))

def plan2(acc: Bytes(), r: File & Result<&1, &1, U32 & String, Bytes()>) -> File & Pl:
  (f, res) = r
  (f, plan(acc, res))

def loop(n: Nat, fp: File & Pl) -> IO(Bytes()):
  match n:
    case 0n:
      (f, pl) = fp
      match pl:
        case More{acc}:
          do IO<Bytes()>:
            File.close(f)
            return acc
        case Stop{acc}:
          do IO<Bytes()>:
            File.close(f)
            return acc
    case 1n+p:
      (f, pl) = fp
      match pl:
        case Stop{acc}:
          do IO<Bytes()>:
            File.close(f)
            return acc
        case More{acc}:
          IO.bind(File & Result<&1, &1, U32 & String, Bytes()>, Bytes(), File.read_buf(f, 1048576),
            r => loop(p, plan2(acc, r)))

def opened(r: Result<&1, &1, U32 & String, File>) -> IO(Bytes()):
  match r:
    case Fail{e}:
      IO.pure(Bytes(), "")
    case Done{f}:
      loop(4096n, (f, More{""}))

def read_all(path: String) -> IO(Bytes()):
  do IO<Bytes()>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    opened(r)

def wr.fin(r: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, x) = r
  File.close(f)

def wr.at(r: Result<&1, &1, U32 & String, File>, +z: Bytes()) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.print("cannot write")
    case Done{f}:
      IO.bind(File & Result<&1, &1, U32 & String, Unit>, Unit, File.write_bytes(f, Bytes.to_list(z)), wr.fin)

def wr(path: String, +z: Bytes()) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "w")
    wr.at(r, z)

def said(+z: Bytes()) -> String:
  Nat.show(Bytes.len(z))

def lvl.at(m: Maybe<&2, U32>) -> Nat:
  match m:
    case None{}:
      6n
    case Some{v}:
      U32.to_nat(v)

def put.at(skip: Bool, o: String, +z: Bytes()) -> IO(Unit):
  match skip:
    case True{}:
      IO.print(said(z))
    case False{}:
      do IO<Unit>:
        IO.print(said(z))
        wr(o, z)

def put(+o: String, +z: Bytes()) -> IO(Unit):
  put.at(String.eq(o, "-"), o, z)

def comp(a: String, l: String, o: String) -> IO(Unit):
  do IO<Unit>:
    b : Bytes() <- read_all(a)
    put(o, D.deflate(b, lvl.at(U32.read(l))))

def dec.at(r: Result<&2, &2, D.Why, Bytes()>, o: String) -> IO(Unit):
  match r:
    case Done{+y}:
      put(o, y)
    case Fail{why}:
      IO.print("refused: " ++ D.why.show(why))

def dec(a: String, o: String) -> IO(Unit):
  do IO<Unit>:
    b : Bytes() <- read_all(a)
    dec.at(D.inflate(U32.to_nat(1073741824), b), o)

def go(args: List<String>) -> IO(Unit):
  match args:
    case Con{m, Con{a, Con{b, Con{c, t}}}}:
      comp(b, a, c)
    case Con{m, Con{a, Con{b, Nil{}}}}:
      dec(a, b)
    case _:
      IO.print("usage: c LEVEL IN OUT | d IN OUT")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(args)
