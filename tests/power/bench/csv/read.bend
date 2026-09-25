# The csv bench: a file through Csv.fold_file in 64 KiB reads, each record
# counted as it completes and nothing kept. Prints records, fields and
# content bytes (a doubled quote counts once, the quotes around a field not
# at all), which run.py holds to CPython's csv and a naive C reader.
#   bun bend2/main.ts tests/power/bench/csv/read.bend -o read && ./read FILE
import Base
import ../../../../power/csv.bend as Csv

type Acc is Data:
  Acc{recs: U32, fields: U32, bytes: U32}

def tally.f(fs: List<&2, Bytes()>, a: Acc) -> Acc:
  match fs:
    case Nil{}:
      a
    case Con{f, t}:
      match a:
        case Acc{r, n, b}:
          tally.f(t, Acc{r, (n + 1 : U32), (b + U32.from_nat(Bytes.len(f)) : U32)})

def tally(a: Acc, r: List<&2, Bytes()>) -> Acc:
  match a:
    case Acc{n, f, b}:
      tally.f(r, Acc{(n + 1 : U32), f, b})

def path(args: List<String>) -> String:
  match args:
    case Nil{}:
      "/tmp/bend-csv-bench.csv"
    case Con{p, t}:
      p

def show(r: Result<&1, &1, U32 & String, Acc & Csv.Out>) -> String:
  match r:
    case Fail{e}:
      "no file"
    case Done{(a, o)}:
      match a o:
        case Acc{n, f, b} Csv.Read{h, rs}:
          U32.show(n) ++ " " ++ U32.show(f) ++ " " ++ U32.show(b)
        case Acc{n, f, b} Csv.Refused{at, why}:
          "refused at " ++ Nat.show(at) ++ ": " ++ Csv.why.show(why)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    r : Result<&1, &1, U32 & String, Acc & Csv.Out> <- Csv.fold_file(~Acc, ~tally, path(args), Csv.excel(),
      65536, Acc{0, 0, 0})
    IO.print(show(r))
