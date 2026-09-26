# Csv against CPython (csv_gen.py prints this file). A read row is one
# document through Csv.read; it must also agree with the same bytes fed a
# byte a read and with csv_spec.bend's parse, or it says DISAGREE. A write
# row is the bytes Csv.show writes, which must be CPython's csv.writer's,
# then what reading them back gives. Bytes are printed as they are when
# they are printable ASCII, else \xHH (and \ | [ ] always).
import Base
import ../../power/csv.bend as Csv
import ../../power/csv_spec.bend as Spec

def u32.pick(b: Bool, x: U32, y: U32) -> U32:
  match b:
    case True{}:
      x
    case False{}:
      y

def hex1(+n: U32) -> String:
  SCon{Chr{U32.add(n, u32.pick(U32.is_lt(n, 10), 48, 87))}, SNil{}}

def esc.c(+c: U32, ok: Bool) -> String:
  match ok:
    case True{}:
      SCon{Chr{c}, SNil{}}
    case False{}:
      "\\x" ++ hex1(U32.shrn(c, 4n)) ++ hex1(U32.and(c, 15))

def plain(+c: U32) -> Bool:
  U32.is_ge(c, 32) && U32.is_lt(c, 127) && U32.is_ne(c, 92) && U32.is_ne(c, 124) &&
    U32.is_ne(c, 91) && U32.is_ne(c, 93)

def esc(b: Bytes()) -> String:
  match b:
    case SNil{}:
      ""
    case SCon{Chr{+c}, t}:
      esc.c(c, plain(c)) ++ esc(t)

def fields(r: List<&2, Bytes()>) -> String:
  match r:
    case Nil{}:
      ""
    case Con{f, t}:
      match t:
        case Nil{}:
          esc(f)
        case Con{g, u}:
          esc(f) ++ "|" ++ fields(Con{g, u})

def rec(r: List<&2, Bytes()>) -> String:
  "[" ++ fields(r) ++ "]"

def recs(rs: List<&2, List<&2, Bytes()>>) -> String:
  match rs:
    case Nil{}:
      ""
    case Con{r, t}:
      rec(r) ++ recs(t)

def head(h: Maybe<&2, List<&2, Bytes()>>) -> String:
  match h:
    case None{}:
      ""
    case Some{r}:
      "H" ++ rec(r) ++ " "

def out(o: Csv.Out) -> String:
  match o:
    case Csv.Refused{at, why}:
      "bad@" ++ Nat.show(at) ++ ":" ++ Csv.why.show(why)
    case Csv.Read{h, +rs}:
      "ok " ++ head(h) ++ Nat.show(List.length(&2, List<&2, Bytes()>, rs)) ++ ":" ++ recs(rs)

# the same bytes, one byte a read
def bytewise(+d: Csv.Dialect, s: Bytes(), p: Csv.P) -> Csv.P:
  match s:
    case SNil{}:
      p
    case SCon{h, t}:
      bytewise(d, t, Csv.feed_buf(d, SCon{h, SNil{}}, p))

def mark(ok: Bool) -> String:
  match ok:
    case True{}:
      ""
    case False{}:
      " DISAGREE"

def rd.all(+a: String, +b: String, +c: String) -> String:
  a ++ mark(String.eq(a, b) && String.eq(a, c))

def rd(+d: Csv.Dialect, +xs: List<&2, U32>) -> String:
  rd.all(out(Csv.read(d, Bytes.from_list(xs))),
    out(Csv.result(d, Csv.finish(d, bytewise(d, Bytes.from_list(xs), Csv.new(d))))),
    out(Spec.parse(xs, d)))

def wr.at(+d: Csv.Dialect, +b: Bytes()) -> String:
  esc(b) ++ " => " ++ out(Csv.read(d, b))

def wr(+d: Csv.Dialect, rs: List<&2, List<&2, Bytes()>>) -> String:
  wr.at(d, Csv.show(d, rs))

# Files: a document written, then read back through File.read_buf in
# chunks, whole and folded a record at a time
def put.close(r: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, x) = r
  File.close(f)

def put(path: String, data: String) -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open(path, "w"))
    r : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, data)
    put.close(r)

def count(n: Nat, r: List<&2, Bytes()>) -> Nat:
  1n+n

def rf(r: Result<&1, &1, U32 & String, Csv.Out>) -> String:
  match r:
    case Fail{e}:
      "no file"
    case Done{o}:
      out(o)

def ff(r: Result<&1, &1, U32 & String, Nat & Csv.Out>) -> String:
  match r:
    case Fail{e}:
      "no file"
    case Done{(n, o)}:
      Nat.show(n) ++ " records, then " ++ out(o)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, []))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 44, 98]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 44, 98, 13, 10]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 44, 98, 13, 10, 99, 44, 100, 13, 10]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 44, 98, 13, 10, 99, 44, 100]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [44]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [44, 44, 13, 10]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 44, 44, 98, 13, 10]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [13, 10]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [13, 10, 13, 10]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 13, 10, 13, 10, 98]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 44, 13, 10]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [32, 97, 32, 44, 32, 98, 32]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [34, 97, 34]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [34, 34]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [34, 34, 34, 34]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [34, 97, 34, 34, 98, 34]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [34, 97, 44, 98, 34]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [34, 97, 13, 10, 98, 34, 44, 99, 13, 10]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [34, 13, 10, 34]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [34, 97, 34, 13, 10, 34, 98, 34]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [120, 44, 34, 121, 34, 34, 122, 34, 13, 10]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [34, 97, 34, 34, 34, 44, 98]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [34, 34, 34, 97, 34, 34, 34]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 34, 98]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [34, 97, 34, 98]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [34, 97, 98, 99]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [34, 97, 34, 34]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [34]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 44, 34, 98]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [34, 97, 34, 32, 44, 98]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 98, 34]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 13, 98]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 10, 98]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 13, 13, 98]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 10, 10]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 13]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [34, 97, 34, 13]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [34, 97, 34, 13, 98]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 13, 10, 10, 98]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 10, 13, 10, 98]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [195, 169, 44, 195, 188, 13, 10]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [34, 230, 151, 165, 230, 156, 172, 34, 44, 232, 170, 158]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [239, 187, 191, 97, 44, 98, 13, 10]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 0, 98, 44, 127, 13, 10]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [34, 97, 13, 98, 34]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [34, 97, 10, 98, 34]))
    IO.print(rd(Csv.Dialect{9, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 9, 98, 13, 10]))
    IO.print(rd(Csv.Dialect{9, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 9, 98, 13, 10, 34, 99, 9, 100, 34, 9, 101, 13, 10]))
    IO.print(rd(Csv.Dialect{9, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 44, 98, 9, 99]))
    IO.print(rd(Csv.Dialect{9, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [34, 120, 34, 9, 9, 34, 34, 10]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 3n, 2n, True{}, False{}}, [97, 98, 99]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 3n, 2n, True{}, False{}}, [97, 98, 99, 100]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 3n, 2n, True{}, False{}}, [34, 97, 98, 99, 34]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 3n, 2n, True{}, False{}}, [34, 97, 98, 99, 100, 34]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 3n, 2n, True{}, False{}}, [34, 97, 98, 34, 34, 99, 34]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 3n, 2n, True{}, False{}}, [34, 97, 34, 34, 98, 34]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 3n, 2n, True{}, False{}}, [34, 97, 13, 10, 98, 34]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 3n, 2n, True{}, False{}}, [34, 97, 98, 13, 10, 34]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 3n, 2n, True{}, False{}}, [97, 44, 98]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 3n, 2n, True{}, False{}}, [97, 44, 98, 44, 99]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 3n, 2n, True{}, False{}}, [97, 44, 98, 13, 10, 99, 44, 100, 44, 101, 13, 10]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 3n, 2n, True{}, False{}}, [44, 44]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 3n, 2n, True{}, False{}}, [97, 44, 98, 13, 10]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, False{}, False{}, False{}, 131072n, 65536n, False{}, False{}}, [97, 44, 98, 13, 10, 99, 44, 100, 13, 10]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, False{}, False{}, False{}, 131072n, 65536n, False{}, False{}}, [97, 10, 98]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, False{}, False{}, False{}, 131072n, 65536n, False{}, False{}}, [97, 13, 98]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, False{}, False{}, False{}, 131072n, 65536n, False{}, False{}}, [97, 44, 98, 13, 10, 99, 13, 10]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, False{}, False{}, False{}, 131072n, 65536n, False{}, False{}}, [97, 13]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, False{}, False{}, False{}, 131072n, 65536n, False{}, False{}}, [34, 97, 10, 98, 34, 13, 10]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, False{}, False{}, False{}, 131072n, 65536n, False{}, False{}}, [97, 44, 98, 13, 10, 99, 44, 100, 44, 101]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, False{}, False{}, False{}, 131072n, 65536n, False{}, False{}}, [13, 10]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, False{}, False{}, False{}, 131072n, 65536n, False{}, False{}}, [97, 13, 13, 10]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, False{}, False{}, False{}, 131072n, 65536n, False{}, False{}}, [34, 97, 34, 10]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, True{}, 131072n, 65536n, False{}, False{}}, [104, 49, 44, 104, 50, 13, 10, 49, 44, 50, 13, 10]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, True{}, 131072n, 65536n, False{}, False{}}, [104, 49, 44, 104, 50, 13, 10]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, True{}, 131072n, 65536n, False{}, False{}}, []))
    IO.print(rd(Csv.Dialect{44, 34, True{}, True{}, True{}, True{}, 131072n, 65536n, False{}, False{}}, [104, 49, 44, 104, 50, 13, 10, 49, 13, 10]))
    IO.print(rd(Csv.Dialect{44, 34, False{}, True{}, False{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 10, 98, 10]))
    IO.print(rd(Csv.Dialect{44, 34, False{}, True{}, False{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 13, 10, 98]))
    IO.print(rd(Csv.Dialect{44, 34, False{}, True{}, False{}, False{}, 131072n, 65536n, True{}, False{}}, [34, 97, 13, 10, 98, 34, 10]))
    IO.print(rd(Csv.Dialect{44, 34, False{}, False{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 13, 98, 13]))
    IO.print(rd(Csv.Dialect{44, 34, False{}, False{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 13, 10, 98]))
    IO.print(rd(Csv.Dialect{44, 34, False{}, False{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 10]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, False{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 13, 10, 98]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, False{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 13, 98]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, False{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 13, 13, 10]))
    IO.print(rd(Csv.Dialect{44, 34, True{}, False{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 10, 98]))
    IO.print(rd(Csv.Dialect{59, 39, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [39, 97, 59, 98, 39, 59, 99]))
    IO.print(rd(Csv.Dialect{59, 39, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [97, 59, 39, 98, 39, 39, 99, 39, 13, 10]))
    IO.print(rd(Csv.Dialect{59, 39, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [34, 97, 34, 59, 98]))
    IO.print(wr(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [[Bytes.from_list([97]), Bytes.from_list([98, 44, 99]), Bytes.from_list([100, 34, 101]), Bytes.from_list([102, 13, 10, 103]), Bytes.from_list([])]]))
    IO.print(wr(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [[Bytes.from_list([])]]))
    IO.print(wr(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [[Bytes.from_list([32, 120, 32])]]))
    IO.print(wr(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [[Bytes.from_list([97])], [Bytes.from_list([98])]]))
    IO.print(wr(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [[Bytes.from_list([34])]]))
    IO.print(wr(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [[Bytes.from_list([]), Bytes.from_list([])]]))
    IO.print(wr(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [[Bytes.from_list([13])], [Bytes.from_list([10])]]))
    IO.print(wr(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [[Bytes.from_list([195, 169]), Bytes.from_list([230, 151, 165, 44, 230, 156, 172])]]))
    IO.print(wr(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [[Bytes.from_list([104, 49]), Bytes.from_list([104, 50])], [Bytes.from_list([49]), Bytes.from_list([50])], [Bytes.from_list([]), Bytes.from_list([34, 34])]]))
    IO.print(wr(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, []))
    IO.print(wr(Csv.Dialect{9, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [[Bytes.from_list([97]), Bytes.from_list([98, 9, 99]), Bytes.from_list([100, 44, 101])]]))
    IO.print(wr(Csv.Dialect{44, 34, True{}, False{}, False{}, False{}, 131072n, 65536n, False{}, False{}}, [[Bytes.from_list([97]), Bytes.from_list([98])], [Bytes.from_list([99, 13, 10]), Bytes.from_list([100])]]))
    IO.print(wr(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, True{}}, [[Bytes.from_list([32, 120]), Bytes.from_list([121, 32]), Bytes.from_list([122]), Bytes.from_list([32])]]))
    IO.print(wr(Csv.Dialect{59, 39, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [[Bytes.from_list([97, 59, 98]), Bytes.from_list([99, 39, 100]), Bytes.from_list([101])]]))
    IO.print(wr(Csv.Dialect{44, 34, True{}, True{}, True{}, False{}, 131072n, 65536n, True{}, False{}}, [[Bytes.from_list([97])], [], [Bytes.from_list([98])]]))
    put("/tmp/bend-power-csv.csv", "a,b\r\n\"x\r\ny\",\"z\"\"\"\r\n,\r\nlast")
    r1 : Result<&1, &1, U32 & String, Csv.Out> <- Csv.read_file("/tmp/bend-power-csv.csv", Csv.excel())
    IO.print(rf(r1))
    f0 : Result<&1, &1, U32 & String, Nat & Csv.Out> <- Csv.fold_file(~Nat, ~count, "/tmp/bend-power-csv.csv", Csv.excel(), 1, 0n)
    IO.print(ff(f0))
    f1 : Result<&1, &1, U32 & String, Nat & Csv.Out> <- Csv.fold_file(~Nat, ~count, "/tmp/bend-power-csv.csv", Csv.excel(), 2, 0n)
    IO.print(ff(f1))
    f2 : Result<&1, &1, U32 & String, Nat & Csv.Out> <- Csv.fold_file(~Nat, ~count, "/tmp/bend-power-csv.csv", Csv.excel(), 3, 0n)
    IO.print(ff(f2))
    r2 : Result<&1, &1, U32 & String, Csv.Out> <- Csv.read_file("/tmp/bend-power-csv-none.csv", Csv.excel())
    IO.print(rf(r2))
#|ok 0:
#|ok 1:[a]
#|ok 1:[a|b]
#|ok 1:[a|b]
#|ok 2:[a|b][c|d]
#|ok 2:[a|b][c|d]
#|ok 1:[|]
#|ok 1:[||]
#|ok 1:[a||b]
#|ok 1:[]
#|ok 2:[][]
#|ok 3:[a][][b]
#|ok 1:[a|]
#|ok 1:[ a | b ]
#|ok 1:[a]
#|ok 1:[]
#|ok 1:["]
#|ok 1:[a"b]
#|ok 1:[a,b]
#|ok 1:[a\x0d\x0ab|c]
#|ok 1:[\x0d\x0a]
#|ok 2:[a][b]
#|ok 1:[x|y"z]
#|ok 1:[a"|b]
#|ok 1:["a"]
#|bad@1:quote-in-field
#|bad@3:after-quote
#|bad@4:unclosed
#|bad@4:unclosed
#|bad@1:unclosed
#|bad@4:unclosed
#|bad@3:after-quote
#|bad@2:quote-in-field
#|ok 2:[a][b]
#|ok 2:[a][b]
#|ok 3:[a][][b]
#|ok 2:[a][]
#|ok 1:[a]
#|ok 1:[a]
#|ok 2:[a][b]
#|ok 3:[a][][b]
#|ok 3:[a][][b]
#|ok 1:[\xc3\xa9|\xc3\xbc]
#|ok 1:[\xe6\x97\xa5\xe6\x9c\xac|\xe8\xaa\x9e]
#|ok 1:[\xef\xbb\xbfa|b]
#|ok 1:[a\x00b|\x7f]
#|ok 1:[a\x0db]
#|ok 1:[a\x0ab]
#|ok 1:[a|b]
#|ok 2:[a|b][c\x09d|e]
#|ok 1:[a,b|c]
#|ok 1:[x||]
#|ok 1:[abc]
#|bad@3:field-too-long
#|ok 1:[abc]
#|bad@4:field-too-long
#|bad@5:field-too-long
#|ok 1:[a"b]
#|bad@4:field-too-long
#|bad@4:field-too-long
#|ok 1:[a|b]
#|bad@5:too-many-fields
#|bad@10:too-many-fields
#|bad@2:too-many-fields
#|ok 1:[a|b]
#|ok 2:[a|b][c|d]
#|bad@1:bare-lf
#|bad@1:bare-cr
#|bad@6:ragged
#|bad@1:bare-cr
#|ok 1:[a\x0ab]
#|bad@10:ragged
#|ok 1:[]
#|bad@1:bare-cr
#|bad@3:bare-lf
#|ok H[h1|h2] 1:[1|2]
#|ok H[h1|h2] 0:
#|ok 0:
#|bad@8:ragged
#|ok 2:[a][b]
#|bad@1:bare-cr
#|ok 1:[a\x0d\x0ab]
#|ok 2:[a][b]
#|bad@2:bare-lf
#|bad@1:bare-lf
#|ok 2:[a][b]
#|ok 2:[a][b]
#|ok 2:[a][]
#|bad@1:bare-lf
#|ok 1:[a;b|c]
#|ok 1:[a|b'c]
#|ok 1:["a"|b]
#|a,"b,c","d""e","f\x0d\x0ag",\x0d\x0a => ok 1:[a|b,c|d"e|f\x0d\x0ag|]
#|""\x0d\x0a => ok 1:[]
#| x \x0d\x0a => ok 1:[ x ]
#|a\x0d\x0ab\x0d\x0a => ok 2:[a][b]
#|""""\x0d\x0a => ok 1:["]
#|,\x0d\x0a => ok 1:[|]
#|"\x0d"\x0d\x0a"\x0a"\x0d\x0a => ok 2:[\x0d][\x0a]
#|\xc3\xa9,"\xe6\x97\xa5,\xe6\x9c\xac"\x0d\x0a => ok 1:[\xc3\xa9|\xe6\x97\xa5,\xe6\x9c\xac]
#|h1,h2\x0d\x0a1,2\x0d\x0a,""""""\x0d\x0a => ok 3:[h1|h2][1|2][|""]
#| => ok 0:
#|a\x09"b\x09c"\x09d,e\x0d\x0a => ok 1:[a|b\x09c|d,e]
#|a,b\x0d\x0a"c\x0d\x0a",d\x0d\x0a => ok 2:[a|b][c\x0d\x0a|d]
#|" x","y ",z," "\x0d\x0a => ok 1:[ x|y |z| ]
#|'a;b';'c''d';e\x0d\x0a => ok 1:[a;b|c'd|e]
#|a\x0d\x0a\x0d\x0ab\x0d\x0a => ok 3:[a][][b]
#|ok 4:[a|b][x\x0d\x0ay|z"][|][last]
#|4 records, then ok 0:
#|4 records, then ok 0:
#|4 records, then ok 0:
#|no file
