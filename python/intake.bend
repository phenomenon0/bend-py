# Strict incremental UTF-8, including partial sequences across read boundaries.
import Base
import ./syntax.bend as S

type Decoder is Data:
  Decoder{need: U32, value: U32, minimum: U32, chars: String}

def bad() -> Result<&2, &2, S.Error, Decoder>:
  Fail{S.PErr{S.Syntax{}, S.Pos{1n, 0n}, "invalid UTF-8"}}

def scalar(+n: U32) -> Bool:
  U32.is_le(n, 1114111) && Bool.not(U32.is_ge(n, 55296) && U32.is_le(n, 57343))

def byte(d: Decoder, +b: U32) -> Result<&2, &2, S.Error, Decoder>:
  Decoder{+need, +v, +minimum, +chars} = d
  S.choose(Result<&2, &2, S.Error, Decoder>, U32.is_eq(need, 0), u =>
    S.choose(Result<&2, &2, S.Error, Decoder>, U32.is_lt(b, 128), u =>
      Done{Decoder{0, 0, 0, SCon{Char.from_u32(b), chars}}}, u =>
      S.choose(Result<&2, &2, S.Error, Decoder>, U32.is_ge(b, 194) && U32.is_le(b, 223), u =>
        Done{Decoder{1, (b - 192 : U32), 128, chars}}, u =>
        S.choose(Result<&2, &2, S.Error, Decoder>, U32.is_ge(b, 224) && U32.is_le(b, 239), u =>
          Done{Decoder{2, (b - 224 : U32), 2048, chars}}, u =>
          S.choose(Result<&2, &2, S.Error, Decoder>, U32.is_ge(b, 240) && U32.is_le(b, 244), u =>
            Done{Decoder{3, (b - 240 : U32), 65536, chars}}, u => bad())))), u =>
    S.choose(Result<&2, &2, S.Error, Decoder>, U32.is_ge(b, 128) && U32.is_le(b, 191), u =>
      +n = (v * 64 + b - 128 : U32)
      S.choose(Result<&2, &2, S.Error, Decoder>, U32.is_eq(need, 1), u =>
        S.choose(Result<&2, &2, S.Error, Decoder>, U32.is_ge(n, minimum) && scalar(n), u =>
          Done{Decoder{0, 0, 0, SCon{Char.from_u32(n), chars}}}, u => bad()), u =>
        Done{Decoder{(need - 1 : U32), n, minimum, chars}}), u => bad()))

def decode(bs: List<&2, U32>, d: Decoder) -> Result<&2, &2, S.Error, Decoder>:
  match bs:
    case Nil{}:
      Done{d}
    case Con{b, rest}:
      do Result<&2, &2, S.Error, Decoder>:
        next : Decoder <- byte(d, b)
        decode(rest, next)

def strip_bom(s: String) -> String:
  match s:
    case SCon{Chr{65279}, tail}:
      tail
    case _:
      s

def finish(d: Decoder) -> Result<&2, &2, S.Error, String>:
  Decoder{need, v, minimum, chars} = d
  S.choose(Result<&2, &2, S.Error, String>, U32.is_eq(need, 0),
    u => Done{strip_bom(String.reverse(chars))},
    u => Fail{S.PErr{S.Syntax{}, S.Pos{1n, 0n}, "truncated UTF-8"}})

def unwrap(b, -A: Kind(b), r: Result<&2, b, S.Error, A>) -> IO(A):
  match r:
    case Done{x}:
      IO.pure(A, x)
    case Fail{e}:
      IO.die(A, 1, S.error_text(e))

def chunk(k: File -> List<&2, U32> -> IO(String),
  got: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(String):
  (handle, r) = got
  IO.bind(List<&2, U32>, String, IO.pass(List<&2, U32>, r), k(handle))

def read(fuel: Nat, f: File, d: Decoder) -> IO(String):
  match fuel:
    case 0n:
      do IO<String>:
        File.close(f)
        IO.die(String, 1, "error Limit 1 0 source exceeds 32 MiB")
    case 1n+left:
      IO.bind(File & Result<&1, &1, U32 & String, List<&2, U32>>, String,
        File.read_bytes(f, 65536), chunk(handle => bs =>
          +bytes = bs
          IO.bind(Decoder, String, unwrap(&2, Decoder, decode(bytes, d)), next =>
            +nd = next
            S.choose(File -> IO(String), List.is_empty(&2, U32, bytes), u =>
              handle => do IO<String>:
                File.close(handle)
                unwrap(&2, String, finish(nd)), u =>
              handle => read(left, handle, nd))(handle))))

def load(path: String) -> IO(String):
  do IO<String>:
    f : File <- IO.try(File, File.open(path, "r"))
    read(513n, f, Decoder{0, 0, 0, ""})
