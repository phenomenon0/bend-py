# Separate File.read probe; the production path validates raw bytes instead.
import Base

def finish(got: File & Result<&1, &1, U32 & String, String>) -> IO(Unit):
  (file, r) = got
  do IO<Unit>:
    source : String <- IO.pass(String, r)
    File.close(file)
    IO.print(Nat.show(String.length(source)))

def main() -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File, File.open("tests/parser/_out/multi_mb.py", "r"))
    got : File & Result<&1, &1, U32 & String, String> <- File.read(file, 4194304)
    finish(got)

#|3145728
