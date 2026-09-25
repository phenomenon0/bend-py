# Deflate and gzip against CPython (deflate_gen.py prints this file).
# inflate: CPython's zlib streams of five inputs at levels 0-9, read by
# D.inflate. deflate: each input (got back from its level-9 stream)
# written by D.deflate at every level: the stream's length and CRC-32,
# which must be deflate_gen.py's twin encoder's, a stream CPython
# inflates to the input, and what D.inflate reads back. stream: zlib's
# malformed streams and some crafted ones, accepted or refused as zlib
# does. cap: a bomb against the output cap. reads: a stream fed in
# small reads, taken as it goes. gzip and gunzip: members as CPython's
# gzip module and zlib's gzip decoder read them.
import Base
import ../../power/deflate.bend as D
import ../../power/gzip.bend as Z

# The data file, read whole
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

def read_all(path: String) -> IO(Bytes()):
  do IO<Bytes()>:
    f : File <- IO.try(File, File.open(path, "r"))
    loop(64n, (f, More{""}))

def res(r: Result<&2, &2, D.Why, Bytes()>) -> String:
  match r:
    case Done{+b}:
      "ok " ++ Nat.show(Bytes.len(b)) ++ " " ++ U32.show(D.crc32(b, 0))
    case Fail{why}:
      "bad " ++ D.why.show(why)

def gres(r: Result<&2, &2, Z.Err, Bytes()>) -> String:
  match r:
    case Done{+b}:
      "ok " ++ Nat.show(Bytes.len(b)) ++ " " ++ U32.show(D.crc32(b, 0))
    case Fail{Z.Err{at, why}}:
      "bad " ++ Z.why.show(why)

def blob(+dat: Bytes(), +off: Nat, +len: Nat) -> Bytes():
  Bytes.slice(dat, off, len)

def inf(+b: Bytes(), cap: Nat) -> String:
  res(D.inflate(cap, b))

def gun(+b: Bytes(), cap: Nat) -> String:
  gres(Z.gunzip(cap, b))

def got(r: Result<&2, &2, D.Why, Bytes()>) -> Bytes():
  match r:
    case Done{b}:
      b
    case Fail{e}:
      ""

# x written at lvl: the stream's length and CRC-32, then what reads back
def enc.at(+z: Bytes()) -> String:
  Nat.show(Bytes.len(z)) ++ " " ++ U32.show(D.crc32(z, 0)) ++ " back " ++
    res(D.inflate(U32.to_nat(100000000), z))

def fix(+b: Bytes(), lvl: Nat) -> String:
  enc.at(D.deflate_fixed(got(D.inflate(U32.to_nat(100000000), b)), lvl))

def enc(+b: Bytes(), lvl: Nat) -> String:
  enc.at(D.deflate(got(D.inflate(U32.to_nat(100000000), b)), lvl))

def gz.at(+z: Bytes()) -> String:
  Nat.show(Bytes.len(z)) ++ " " ++ U32.show(D.crc32(z, 0)) ++ " back " ++
    gres(Z.gunzip(U32.to_nat(100000000), z))

def gz(+b: Bytes(), lvl: Nat) -> String:
  gz.at(Z.gzip(got(D.inflate(U32.to_nat(100000000), b)), lvl))

def crc(+b: Bytes()) -> String:
  U32.show(D.crc32(got(D.inflate(U32.to_nat(100000000), b)), 0))

def reads.fin(r: Result<&2, &2, D.Why, Bytes()>, acc: Bytes()) -> Result<&2, &2, D.Why, Bytes()>:
  match r:
    case Done{b}:
      Done{Bytes.append(acc, b)}
    case Fail{e}:
      Fail{e}

# the stream in reads of k bytes, each read's output taken as it comes
def reads.go(n: Nat, +s: Bytes(), +k: Nat, r: Bytes() & D.St, acc: Bytes()) ->
  Result<&2, &2, D.Why, Bytes()>:
  match n:
    case 0n:
      (b, st) = r
      reads.fin(D.finish(st), Bytes.append(acc, b))
    case 1n+p:
      (b, st) = r
      reads.go(p, Bytes.drop(s, k), k, D.take(D.feed(Bytes.slice(s, 0n, k), st)),
        Bytes.append(acc, b))

def reads(+s: Bytes(), +k: Nat) -> String:
  res(reads.go(1n+Nat.div(Bytes.len(s), k), s, k, ("", D.new(U32.to_nat(100000000))), ""))

def main() -> IO(Unit):
  do IO<Unit>:
    +dat : Bytes() <- read_all("tests/power/deflate.dat")
    IO.print("inflate empty L0 " ++ inf(blob(dat, U32.to_nat(0), U32.to_nat(5)), U32.to_nat(100000000)))
    IO.print("inflate empty L1 " ++ inf(blob(dat, U32.to_nat(5), U32.to_nat(2)), U32.to_nat(100000000)))
    IO.print("inflate empty L2 " ++ inf(blob(dat, U32.to_nat(5), U32.to_nat(2)), U32.to_nat(100000000)))
    IO.print("inflate empty L3 " ++ inf(blob(dat, U32.to_nat(5), U32.to_nat(2)), U32.to_nat(100000000)))
    IO.print("inflate empty L4 " ++ inf(blob(dat, U32.to_nat(5), U32.to_nat(2)), U32.to_nat(100000000)))
    IO.print("inflate empty L5 " ++ inf(blob(dat, U32.to_nat(5), U32.to_nat(2)), U32.to_nat(100000000)))
    IO.print("inflate empty L6 " ++ inf(blob(dat, U32.to_nat(5), U32.to_nat(2)), U32.to_nat(100000000)))
    IO.print("inflate empty L7 " ++ inf(blob(dat, U32.to_nat(5), U32.to_nat(2)), U32.to_nat(100000000)))
    IO.print("inflate empty L8 " ++ inf(blob(dat, U32.to_nat(5), U32.to_nat(2)), U32.to_nat(100000000)))
    IO.print("inflate empty L9 " ++ inf(blob(dat, U32.to_nat(5), U32.to_nat(2)), U32.to_nat(100000000)))
    IO.print("inflate one L0 " ++ inf(blob(dat, U32.to_nat(7), U32.to_nat(6)), U32.to_nat(100000000)))
    IO.print("inflate one L1 " ++ inf(blob(dat, U32.to_nat(13), U32.to_nat(3)), U32.to_nat(100000000)))
    IO.print("inflate one L2 " ++ inf(blob(dat, U32.to_nat(13), U32.to_nat(3)), U32.to_nat(100000000)))
    IO.print("inflate one L3 " ++ inf(blob(dat, U32.to_nat(13), U32.to_nat(3)), U32.to_nat(100000000)))
    IO.print("inflate one L4 " ++ inf(blob(dat, U32.to_nat(13), U32.to_nat(3)), U32.to_nat(100000000)))
    IO.print("inflate one L5 " ++ inf(blob(dat, U32.to_nat(13), U32.to_nat(3)), U32.to_nat(100000000)))
    IO.print("inflate one L6 " ++ inf(blob(dat, U32.to_nat(13), U32.to_nat(3)), U32.to_nat(100000000)))
    IO.print("inflate one L7 " ++ inf(blob(dat, U32.to_nat(13), U32.to_nat(3)), U32.to_nat(100000000)))
    IO.print("inflate one L8 " ++ inf(blob(dat, U32.to_nat(13), U32.to_nat(3)), U32.to_nat(100000000)))
    IO.print("inflate one L9 " ++ inf(blob(dat, U32.to_nat(13), U32.to_nat(3)), U32.to_nat(100000000)))
    IO.print("inflate rep L0 " ++ inf(blob(dat, U32.to_nat(16), U32.to_nat(20005)), U32.to_nat(100000000)))
    IO.print("inflate rep L1 " ++ inf(blob(dat, U32.to_nat(20021), U32.to_nat(106)), U32.to_nat(100000000)))
    IO.print("inflate rep L2 " ++ inf(blob(dat, U32.to_nat(20021), U32.to_nat(106)), U32.to_nat(100000000)))
    IO.print("inflate rep L3 " ++ inf(blob(dat, U32.to_nat(20021), U32.to_nat(106)), U32.to_nat(100000000)))
    IO.print("inflate rep L4 " ++ inf(blob(dat, U32.to_nat(20127), U32.to_nat(37)), U32.to_nat(100000000)))
    IO.print("inflate rep L5 " ++ inf(blob(dat, U32.to_nat(20127), U32.to_nat(37)), U32.to_nat(100000000)))
    IO.print("inflate rep L6 " ++ inf(blob(dat, U32.to_nat(20127), U32.to_nat(37)), U32.to_nat(100000000)))
    IO.print("inflate rep L7 " ++ inf(blob(dat, U32.to_nat(20127), U32.to_nat(37)), U32.to_nat(100000000)))
    IO.print("inflate rep L8 " ++ inf(blob(dat, U32.to_nat(20127), U32.to_nat(37)), U32.to_nat(100000000)))
    IO.print("inflate rep L9 " ++ inf(blob(dat, U32.to_nat(20127), U32.to_nat(37)), U32.to_nat(100000000)))
    IO.print("inflate rand L0 " ++ inf(blob(dat, U32.to_nat(20164), U32.to_nat(4101)), U32.to_nat(100000000)))
    IO.print("inflate rand L1 " ++ inf(blob(dat, U32.to_nat(20164), U32.to_nat(4101)), U32.to_nat(100000000)))
    IO.print("inflate rand L2 " ++ inf(blob(dat, U32.to_nat(20164), U32.to_nat(4101)), U32.to_nat(100000000)))
    IO.print("inflate rand L3 " ++ inf(blob(dat, U32.to_nat(20164), U32.to_nat(4101)), U32.to_nat(100000000)))
    IO.print("inflate rand L4 " ++ inf(blob(dat, U32.to_nat(20164), U32.to_nat(4101)), U32.to_nat(100000000)))
    IO.print("inflate rand L5 " ++ inf(blob(dat, U32.to_nat(20164), U32.to_nat(4101)), U32.to_nat(100000000)))
    IO.print("inflate rand L6 " ++ inf(blob(dat, U32.to_nat(20164), U32.to_nat(4101)), U32.to_nat(100000000)))
    IO.print("inflate rand L7 " ++ inf(blob(dat, U32.to_nat(20164), U32.to_nat(4101)), U32.to_nat(100000000)))
    IO.print("inflate rand L8 " ++ inf(blob(dat, U32.to_nat(20164), U32.to_nat(4101)), U32.to_nat(100000000)))
    IO.print("inflate rand L9 " ++ inf(blob(dat, U32.to_nat(20164), U32.to_nat(4101)), U32.to_nat(100000000)))
    IO.print("inflate text L0 " ++ inf(blob(dat, U32.to_nat(24265), U32.to_nat(40010)), U32.to_nat(100000000)))
    IO.print("inflate text L1 " ++ inf(blob(dat, U32.to_nat(64275), U32.to_nat(16368)), U32.to_nat(100000000)))
    IO.print("inflate text L2 " ++ inf(blob(dat, U32.to_nat(80643), U32.to_nat(15872)), U32.to_nat(100000000)))
    IO.print("inflate text L3 " ++ inf(blob(dat, U32.to_nat(96515), U32.to_nat(15287)), U32.to_nat(100000000)))
    IO.print("inflate text L4 " ++ inf(blob(dat, U32.to_nat(111802), U32.to_nat(14869)), U32.to_nat(100000000)))
    IO.print("inflate text L5 " ++ inf(blob(dat, U32.to_nat(126671), U32.to_nat(14399)), U32.to_nat(100000000)))
    IO.print("inflate text L6 " ++ inf(blob(dat, U32.to_nat(141070), U32.to_nat(14126)), U32.to_nat(100000000)))
    IO.print("inflate text L7 " ++ inf(blob(dat, U32.to_nat(155196), U32.to_nat(14066)), U32.to_nat(100000000)))
    IO.print("inflate text L8 " ++ inf(blob(dat, U32.to_nat(169262), U32.to_nat(14021)), U32.to_nat(100000000)))
    IO.print("inflate text L9 " ++ inf(blob(dat, U32.to_nat(183283), U32.to_nat(14021)), U32.to_nat(100000000)))
    IO.print("deflate empty L0 " ++ enc(blob(dat, U32.to_nat(5), U32.to_nat(2)), 0n))
    IO.print("deflate empty L1 " ++ enc(blob(dat, U32.to_nat(5), U32.to_nat(2)), 1n))
    IO.print("deflate empty L2 " ++ enc(blob(dat, U32.to_nat(5), U32.to_nat(2)), 2n))
    IO.print("deflate empty L3 " ++ enc(blob(dat, U32.to_nat(5), U32.to_nat(2)), 3n))
    IO.print("deflate empty L4 " ++ enc(blob(dat, U32.to_nat(5), U32.to_nat(2)), 4n))
    IO.print("deflate empty L5 " ++ enc(blob(dat, U32.to_nat(5), U32.to_nat(2)), 5n))
    IO.print("deflate empty L6 " ++ enc(blob(dat, U32.to_nat(5), U32.to_nat(2)), 6n))
    IO.print("deflate empty L7 " ++ enc(blob(dat, U32.to_nat(5), U32.to_nat(2)), 7n))
    IO.print("deflate empty L8 " ++ enc(blob(dat, U32.to_nat(5), U32.to_nat(2)), 8n))
    IO.print("deflate empty L9 " ++ enc(blob(dat, U32.to_nat(5), U32.to_nat(2)), 9n))
    IO.print("deflate one L0 " ++ enc(blob(dat, U32.to_nat(13), U32.to_nat(3)), 0n))
    IO.print("deflate one L1 " ++ enc(blob(dat, U32.to_nat(13), U32.to_nat(3)), 1n))
    IO.print("deflate one L2 " ++ enc(blob(dat, U32.to_nat(13), U32.to_nat(3)), 2n))
    IO.print("deflate one L3 " ++ enc(blob(dat, U32.to_nat(13), U32.to_nat(3)), 3n))
    IO.print("deflate one L4 " ++ enc(blob(dat, U32.to_nat(13), U32.to_nat(3)), 4n))
    IO.print("deflate one L5 " ++ enc(blob(dat, U32.to_nat(13), U32.to_nat(3)), 5n))
    IO.print("deflate one L6 " ++ enc(blob(dat, U32.to_nat(13), U32.to_nat(3)), 6n))
    IO.print("deflate one L7 " ++ enc(blob(dat, U32.to_nat(13), U32.to_nat(3)), 7n))
    IO.print("deflate one L8 " ++ enc(blob(dat, U32.to_nat(13), U32.to_nat(3)), 8n))
    IO.print("deflate one L9 " ++ enc(blob(dat, U32.to_nat(13), U32.to_nat(3)), 9n))
    IO.print("deflate rep L0 " ++ enc(blob(dat, U32.to_nat(20127), U32.to_nat(37)), 0n))
    IO.print("deflate rep L1 " ++ enc(blob(dat, U32.to_nat(20127), U32.to_nat(37)), 1n))
    IO.print("deflate rep L2 " ++ enc(blob(dat, U32.to_nat(20127), U32.to_nat(37)), 2n))
    IO.print("deflate rep L3 " ++ enc(blob(dat, U32.to_nat(20127), U32.to_nat(37)), 3n))
    IO.print("deflate rep L4 " ++ enc(blob(dat, U32.to_nat(20127), U32.to_nat(37)), 4n))
    IO.print("deflate rep L5 " ++ enc(blob(dat, U32.to_nat(20127), U32.to_nat(37)), 5n))
    IO.print("deflate rep L6 " ++ enc(blob(dat, U32.to_nat(20127), U32.to_nat(37)), 6n))
    IO.print("deflate rep L7 " ++ enc(blob(dat, U32.to_nat(20127), U32.to_nat(37)), 7n))
    IO.print("deflate rep L8 " ++ enc(blob(dat, U32.to_nat(20127), U32.to_nat(37)), 8n))
    IO.print("deflate rep L9 " ++ enc(blob(dat, U32.to_nat(20127), U32.to_nat(37)), 9n))
    IO.print("deflate rand L0 " ++ enc(blob(dat, U32.to_nat(20164), U32.to_nat(4101)), 0n))
    IO.print("deflate rand L1 " ++ enc(blob(dat, U32.to_nat(20164), U32.to_nat(4101)), 1n))
    IO.print("deflate rand L2 " ++ enc(blob(dat, U32.to_nat(20164), U32.to_nat(4101)), 2n))
    IO.print("deflate rand L3 " ++ enc(blob(dat, U32.to_nat(20164), U32.to_nat(4101)), 3n))
    IO.print("deflate rand L4 " ++ enc(blob(dat, U32.to_nat(20164), U32.to_nat(4101)), 4n))
    IO.print("deflate rand L5 " ++ enc(blob(dat, U32.to_nat(20164), U32.to_nat(4101)), 5n))
    IO.print("deflate rand L6 " ++ enc(blob(dat, U32.to_nat(20164), U32.to_nat(4101)), 6n))
    IO.print("deflate rand L7 " ++ enc(blob(dat, U32.to_nat(20164), U32.to_nat(4101)), 7n))
    IO.print("deflate rand L8 " ++ enc(blob(dat, U32.to_nat(20164), U32.to_nat(4101)), 8n))
    IO.print("deflate rand L9 " ++ enc(blob(dat, U32.to_nat(20164), U32.to_nat(4101)), 9n))
    IO.print("deflate text L0 " ++ enc(blob(dat, U32.to_nat(183283), U32.to_nat(14021)), 0n))
    IO.print("deflate text L1 " ++ enc(blob(dat, U32.to_nat(183283), U32.to_nat(14021)), 1n))
    IO.print("deflate text L2 " ++ enc(blob(dat, U32.to_nat(183283), U32.to_nat(14021)), 2n))
    IO.print("deflate text L3 " ++ enc(blob(dat, U32.to_nat(183283), U32.to_nat(14021)), 3n))
    IO.print("deflate text L4 " ++ enc(blob(dat, U32.to_nat(183283), U32.to_nat(14021)), 4n))
    IO.print("deflate text L5 " ++ enc(blob(dat, U32.to_nat(183283), U32.to_nat(14021)), 5n))
    IO.print("deflate text L6 " ++ enc(blob(dat, U32.to_nat(183283), U32.to_nat(14021)), 6n))
    IO.print("deflate text L7 " ++ enc(blob(dat, U32.to_nat(183283), U32.to_nat(14021)), 7n))
    IO.print("deflate text L8 " ++ enc(blob(dat, U32.to_nat(183283), U32.to_nat(14021)), 8n))
    IO.print("deflate text L9 " ++ enc(blob(dat, U32.to_nat(183283), U32.to_nat(14021)), 9n))
    IO.print("fixed empty L1 " ++ fix(blob(dat, U32.to_nat(5), U32.to_nat(2)), 1n))
    IO.print("fixed empty L4 " ++ fix(blob(dat, U32.to_nat(5), U32.to_nat(2)), 4n))
    IO.print("fixed empty L9 " ++ fix(blob(dat, U32.to_nat(5), U32.to_nat(2)), 9n))
    IO.print("fixed one L1 " ++ fix(blob(dat, U32.to_nat(13), U32.to_nat(3)), 1n))
    IO.print("fixed one L4 " ++ fix(blob(dat, U32.to_nat(13), U32.to_nat(3)), 4n))
    IO.print("fixed one L9 " ++ fix(blob(dat, U32.to_nat(13), U32.to_nat(3)), 9n))
    IO.print("fixed rep L1 " ++ fix(blob(dat, U32.to_nat(20127), U32.to_nat(37)), 1n))
    IO.print("fixed rep L4 " ++ fix(blob(dat, U32.to_nat(20127), U32.to_nat(37)), 4n))
    IO.print("fixed rep L9 " ++ fix(blob(dat, U32.to_nat(20127), U32.to_nat(37)), 9n))
    IO.print("fixed rand L1 " ++ fix(blob(dat, U32.to_nat(20164), U32.to_nat(4101)), 1n))
    IO.print("fixed rand L4 " ++ fix(blob(dat, U32.to_nat(20164), U32.to_nat(4101)), 4n))
    IO.print("fixed rand L9 " ++ fix(blob(dat, U32.to_nat(20164), U32.to_nat(4101)), 9n))
    IO.print("fixed text L1 " ++ fix(blob(dat, U32.to_nat(183283), U32.to_nat(14021)), 1n))
    IO.print("fixed text L4 " ++ fix(blob(dat, U32.to_nat(183283), U32.to_nat(14021)), 4n))
    IO.print("fixed text L9 " ++ fix(blob(dat, U32.to_nat(183283), U32.to_nat(14021)), 9n))
    IO.print("stream zlib stored lengths " ++ inf(blob(dat, U32.to_nat(197304), U32.to_nat(5)), U32.to_nat(100000000)))
    IO.print("stream zlib fixed " ++ inf(blob(dat, U32.to_nat(5), U32.to_nat(2)), U32.to_nat(100000000)))
    IO.print("stream zlib block type " ++ inf(blob(dat, U32.to_nat(197309), U32.to_nat(1)), U32.to_nat(100000000)))
    IO.print("stream zlib stored " ++ inf(blob(dat, U32.to_nat(197310), U32.to_nat(6)), U32.to_nat(100000000)))
    IO.print("stream zlib too many symbols " ++ inf(blob(dat, U32.to_nat(197316), U32.to_nat(3)), U32.to_nat(100000000)))
    IO.print("stream zlib code lengths set " ++ inf(blob(dat, U32.to_nat(197319), U32.to_nat(4)), U32.to_nat(100000000)))
    IO.print("stream zlib bit length repeat " ++ inf(blob(dat, U32.to_nat(197323), U32.to_nat(5)), U32.to_nat(100000000)))
    IO.print("stream zlib bit length repeat 2 " ++ inf(blob(dat, U32.to_nat(197328), U32.to_nat(6)), U32.to_nat(100000000)))
    IO.print("stream zlib missing eob " ++ inf(blob(dat, U32.to_nat(197334), U32.to_nat(6)), U32.to_nat(100000000)))
    IO.print("stream zlib literal set " ++ inf(blob(dat, U32.to_nat(197340), U32.to_nat(14)), U32.to_nat(100000000)))
    IO.print("stream zlib distances set " ++ inf(blob(dat, U32.to_nat(197354), U32.to_nat(14)), U32.to_nat(100000000)))
    IO.print("stream zlib literal code " ++ inf(blob(dat, U32.to_nat(197368), U32.to_nat(14)), U32.to_nat(100000000)))
    IO.print("stream zlib distance code " ++ inf(blob(dat, U32.to_nat(197382), U32.to_nat(4)), U32.to_nat(100000000)))
    IO.print("stream zlib too far back " ++ inf(blob(dat, U32.to_nat(197386), U32.to_nat(13)), U32.to_nat(100000000)))
    IO.print("stream zlib long code " ++ inf(blob(dat, U32.to_nat(197399), U32.to_nat(23)), U32.to_nat(100000000)))
    IO.print("stream zlib length extra " ++ inf(blob(dat, U32.to_nat(197422), U32.to_nat(15)), U32.to_nat(100000000)))
    IO.print("stream zlib distance extra " ++ inf(blob(dat, U32.to_nat(197437), U32.to_nat(24)), U32.to_nat(100000000)))
    IO.print("stream sym 286 " ++ inf(blob(dat, U32.to_nat(197461), U32.to_nat(2)), U32.to_nat(100000000)))
    IO.print("stream sym 287 " ++ inf(blob(dat, U32.to_nat(197463), U32.to_nat(2)), U32.to_nat(100000000)))
    IO.print("stream dist 30 " ++ inf(blob(dat, U32.to_nat(197465), U32.to_nat(3)), U32.to_nat(100000000)))
    IO.print("stream dist 31 " ++ inf(blob(dat, U32.to_nat(197468), U32.to_nat(3)), U32.to_nat(100000000)))
    IO.print("stream far by 1 " ++ inf(blob(dat, U32.to_nat(197471), U32.to_nat(4)), U32.to_nat(100000000)))
    IO.print("stream near ok " ++ inf(blob(dat, U32.to_nat(197475), U32.to_nat(4)), U32.to_nat(100000000)))
    IO.print("stream overlap " ++ inf(blob(dat, U32.to_nat(197479), U32.to_nat(6)), U32.to_nat(100000000)))
    IO.print("stream len 258 " ++ inf(blob(dat, U32.to_nat(197485), U32.to_nat(4)), U32.to_nat(100000000)))
    IO.print("stream no final " ++ inf(blob(dat, U32.to_nat(197489), U32.to_nat(2)), U32.to_nat(100000000)))
    IO.print("stream empty input " ++ inf(blob(dat, U32.to_nat(197491), U32.to_nat(0)), U32.to_nat(100000000)))
    IO.print("stream cut header " ++ inf(blob(dat, U32.to_nat(197491), U32.to_nat(1)), U32.to_nat(100000000)))
    IO.print("stream stored cut " ++ inf(blob(dat, U32.to_nat(197492), U32.to_nat(7)), U32.to_nat(100000000)))
    IO.print("stream two blocks " ++ inf(blob(dat, U32.to_nat(197499), U32.to_nat(5)), U32.to_nat(100000000)))
    IO.print("stream trailing " ++ inf(blob(dat, U32.to_nat(197504), U32.to_nat(4)), U32.to_nat(100000000)))
    IO.print("cap 65536 " ++ inf(blob(dat, U32.to_nat(197508), U32.to_nat(78)), U32.to_nat(65536)))
    IO.print("cap 65535 " ++ inf(blob(dat, U32.to_nat(197508), U32.to_nat(78)), U32.to_nat(65535)))
    IO.print("cap 1000 " ++ inf(blob(dat, U32.to_nat(197508), U32.to_nat(78)), U32.to_nat(1000)))
    IO.print("cap 0 " ++ inf(blob(dat, U32.to_nat(197508), U32.to_nat(78)), U32.to_nat(0)))
    IO.print("reads 1 " ++ reads(blob(dat, U32.to_nat(141070), U32.to_nat(14126)), 1n))
    IO.print("reads 7 " ++ reads(blob(dat, U32.to_nat(141070), U32.to_nat(14126)), 7n))
    IO.print("reads 4096 " ++ reads(blob(dat, U32.to_nat(141070), U32.to_nat(14126)), 4096n))
    IO.print("crc32 empty " ++ crc(blob(dat, U32.to_nat(5), U32.to_nat(2))))
    IO.print("crc32 one " ++ crc(blob(dat, U32.to_nat(13), U32.to_nat(3))))
    IO.print("crc32 rep " ++ crc(blob(dat, U32.to_nat(20127), U32.to_nat(37))))
    IO.print("crc32 rand " ++ crc(blob(dat, U32.to_nat(20164), U32.to_nat(4101))))
    IO.print("crc32 text " ++ crc(blob(dat, U32.to_nat(183283), U32.to_nat(14021))))
    IO.print("gunzip plain " ++ gun(blob(dat, U32.to_nat(197586), U32.to_nat(35)), U32.to_nat(100000000)))
    IO.print("gunzip empty file " ++ gun(blob(dat, U32.to_nat(197491), U32.to_nat(0)), U32.to_nat(100000000)))
    IO.print("gunzip empty member " ++ gun(blob(dat, U32.to_nat(197621), U32.to_nat(20)), U32.to_nat(100000000)))
    IO.print("gunzip fname " ++ gun(blob(dat, U32.to_nat(197641), U32.to_nat(36)), U32.to_nat(100000000)))
    IO.print("gunzip all fields " ++ gun(blob(dat, U32.to_nat(197677), U32.to_nat(46)), U32.to_nat(100000000)))
    IO.print("gunzip two members " ++ gun(blob(dat, U32.to_nat(197723), U32.to_nat(55)), U32.to_nat(100000000)))
    IO.print("gunzip zero pad " ++ gun(blob(dat, U32.to_nat(197778), U32.to_nat(27)), U32.to_nat(100000000)))
    IO.print("gunzip pad between " ++ gun(blob(dat, U32.to_nat(197805), U32.to_nat(44)), U32.to_nat(100000000)))
    IO.print("gunzip long extra " ++ gun(blob(dat, U32.to_nat(197849), U32.to_nat(1023)), U32.to_nat(100000000)))
    IO.print("gunzip bad crc " ++ gun(blob(dat, U32.to_nat(198872), U32.to_nat(25)), U32.to_nat(100000000)))
    IO.print("gunzip bad size " ++ gun(blob(dat, U32.to_nat(198897), U32.to_nat(25)), U32.to_nat(100000000)))
    IO.print("gunzip bad magic " ++ gun(blob(dat, U32.to_nat(198922), U32.to_nat(25)), U32.to_nat(100000000)))
    IO.print("gunzip bad method " ++ gun(blob(dat, U32.to_nat(198947), U32.to_nat(25)), U32.to_nat(100000000)))
    IO.print("gunzip reserved flag " ++ gun(blob(dat, U32.to_nat(198972), U32.to_nat(25)), U32.to_nat(100000000)))
    IO.print("gunzip bad hcrc " ++ gun(blob(dat, U32.to_nat(198997), U32.to_nat(27)), U32.to_nat(100000000)))
    IO.print("gunzip truncated " ++ gun(blob(dat, U32.to_nat(199024), U32.to_nat(28)), U32.to_nat(100000000)))
    IO.print("gunzip garbage after " ++ gun(blob(dat, U32.to_nat(199052), U32.to_nat(27)), U32.to_nat(100000000)))
    IO.print("gunzip zero first " ++ gun(blob(dat, U32.to_nat(199079), U32.to_nat(26)), U32.to_nat(100000000)))
    IO.print("gunzip bad stream " ++ gun(blob(dat, U32.to_nat(199105), U32.to_nat(19)), U32.to_nat(100000000)))
    IO.print("gunzip cap 6000 " ++ gun(blob(dat, U32.to_nat(199124), U32.to_nat(76)), U32.to_nat(6000)))
    IO.print("gunzip cap 5999 " ++ gun(blob(dat, U32.to_nat(199124), U32.to_nat(76)), U32.to_nat(5999)))
    IO.print("gunzip cap 3000 " ++ gun(blob(dat, U32.to_nat(199124), U32.to_nat(76)), U32.to_nat(3000)))
    IO.print("gzip empty L0 " ++ gz(blob(dat, U32.to_nat(5), U32.to_nat(2)), 0n))
    IO.print("gzip empty L1 " ++ gz(blob(dat, U32.to_nat(5), U32.to_nat(2)), 1n))
    IO.print("gzip empty L6 " ++ gz(blob(dat, U32.to_nat(5), U32.to_nat(2)), 6n))
    IO.print("gzip empty L9 " ++ gz(blob(dat, U32.to_nat(5), U32.to_nat(2)), 9n))
    IO.print("gzip one L0 " ++ gz(blob(dat, U32.to_nat(13), U32.to_nat(3)), 0n))
    IO.print("gzip one L1 " ++ gz(blob(dat, U32.to_nat(13), U32.to_nat(3)), 1n))
    IO.print("gzip one L6 " ++ gz(blob(dat, U32.to_nat(13), U32.to_nat(3)), 6n))
    IO.print("gzip one L9 " ++ gz(blob(dat, U32.to_nat(13), U32.to_nat(3)), 9n))
    IO.print("gzip rep L0 " ++ gz(blob(dat, U32.to_nat(20127), U32.to_nat(37)), 0n))
    IO.print("gzip rep L1 " ++ gz(blob(dat, U32.to_nat(20127), U32.to_nat(37)), 1n))
    IO.print("gzip rep L6 " ++ gz(blob(dat, U32.to_nat(20127), U32.to_nat(37)), 6n))
    IO.print("gzip rep L9 " ++ gz(blob(dat, U32.to_nat(20127), U32.to_nat(37)), 9n))
    IO.print("gzip rand L0 " ++ gz(blob(dat, U32.to_nat(20164), U32.to_nat(4101)), 0n))
    IO.print("gzip rand L1 " ++ gz(blob(dat, U32.to_nat(20164), U32.to_nat(4101)), 1n))
    IO.print("gzip rand L6 " ++ gz(blob(dat, U32.to_nat(20164), U32.to_nat(4101)), 6n))
    IO.print("gzip rand L9 " ++ gz(blob(dat, U32.to_nat(20164), U32.to_nat(4101)), 9n))
    IO.print("gzip text L0 " ++ gz(blob(dat, U32.to_nat(183283), U32.to_nat(14021)), 0n))
    IO.print("gzip text L1 " ++ gz(blob(dat, U32.to_nat(183283), U32.to_nat(14021)), 1n))
    IO.print("gzip text L6 " ++ gz(blob(dat, U32.to_nat(183283), U32.to_nat(14021)), 6n))
    IO.print("gzip text L9 " ++ gz(blob(dat, U32.to_nat(183283), U32.to_nat(14021)), 9n))
#|inflate empty L0 ok 0 0
#|inflate empty L1 ok 0 0
#|inflate empty L2 ok 0 0
#|inflate empty L3 ok 0 0
#|inflate empty L4 ok 0 0
#|inflate empty L5 ok 0 0
#|inflate empty L6 ok 0 0
#|inflate empty L7 ok 0 0
#|inflate empty L8 ok 0 0
#|inflate empty L9 ok 0 0
#|inflate one L0 ok 1 1505515367
#|inflate one L1 ok 1 1505515367
#|inflate one L2 ok 1 1505515367
#|inflate one L3 ok 1 1505515367
#|inflate one L4 ok 1 1505515367
#|inflate one L5 ok 1 1505515367
#|inflate one L6 ok 1 1505515367
#|inflate one L7 ok 1 1505515367
#|inflate one L8 ok 1 1505515367
#|inflate one L9 ok 1 1505515367
#|inflate rep L0 ok 20000 3401418545
#|inflate rep L1 ok 20000 3401418545
#|inflate rep L2 ok 20000 3401418545
#|inflate rep L3 ok 20000 3401418545
#|inflate rep L4 ok 20000 3401418545
#|inflate rep L5 ok 20000 3401418545
#|inflate rep L6 ok 20000 3401418545
#|inflate rep L7 ok 20000 3401418545
#|inflate rep L8 ok 20000 3401418545
#|inflate rep L9 ok 20000 3401418545
#|inflate rand L0 ok 4096 275690851
#|inflate rand L1 ok 4096 275690851
#|inflate rand L2 ok 4096 275690851
#|inflate rand L3 ok 4096 275690851
#|inflate rand L4 ok 4096 275690851
#|inflate rand L5 ok 4096 275690851
#|inflate rand L6 ok 4096 275690851
#|inflate rand L7 ok 4096 275690851
#|inflate rand L8 ok 4096 275690851
#|inflate rand L9 ok 4096 275690851
#|inflate text L0 ok 40000 1758392975
#|inflate text L1 ok 40000 1758392975
#|inflate text L2 ok 40000 1758392975
#|inflate text L3 ok 40000 1758392975
#|inflate text L4 ok 40000 1758392975
#|inflate text L5 ok 40000 1758392975
#|inflate text L6 ok 40000 1758392975
#|inflate text L7 ok 40000 1758392975
#|inflate text L8 ok 40000 1758392975
#|inflate text L9 ok 40000 1758392975
#|deflate empty L0 5 1164233810 back ok 0 0
#|deflate empty L1 2 1794392380 back ok 0 0
#|deflate empty L2 2 1794392380 back ok 0 0
#|deflate empty L3 2 1794392380 back ok 0 0
#|deflate empty L4 2 1794392380 back ok 0 0
#|deflate empty L5 2 1794392380 back ok 0 0
#|deflate empty L6 2 1794392380 back ok 0 0
#|deflate empty L7 2 1794392380 back ok 0 0
#|deflate empty L8 2 1794392380 back ok 0 0
#|deflate empty L9 2 1794392380 back ok 0 0
#|deflate one L0 6 3762176244 back ok 1 1505515367
#|deflate one L1 3 538398705 back ok 1 1505515367
#|deflate one L2 3 538398705 back ok 1 1505515367
#|deflate one L3 3 538398705 back ok 1 1505515367
#|deflate one L4 3 538398705 back ok 1 1505515367
#|deflate one L5 3 538398705 back ok 1 1505515367
#|deflate one L6 3 538398705 back ok 1 1505515367
#|deflate one L7 3 538398705 back ok 1 1505515367
#|deflate one L8 3 538398705 back ok 1 1505515367
#|deflate one L9 3 538398705 back ok 1 1505515367
#|deflate rep L0 20005 234225597 back ok 20000 3401418545
#|deflate rep L1 106 2982340241 back ok 20000 3401418545
#|deflate rep L2 106 2982340241 back ok 20000 3401418545
#|deflate rep L3 106 2982340241 back ok 20000 3401418545
#|deflate rep L4 37 3888820337 back ok 20000 3401418545
#|deflate rep L5 37 3888820337 back ok 20000 3401418545
#|deflate rep L6 37 3888820337 back ok 20000 3401418545
#|deflate rep L7 37 3888820337 back ok 20000 3401418545
#|deflate rep L8 37 3888820337 back ok 20000 3401418545
#|deflate rep L9 37 3888820337 back ok 20000 3401418545
#|deflate rand L0 4101 2570684344 back ok 4096 275690851
#|deflate rand L1 4101 2570684344 back ok 4096 275690851
#|deflate rand L2 4101 2570684344 back ok 4096 275690851
#|deflate rand L3 4101 2570684344 back ok 4096 275690851
#|deflate rand L4 4101 2570684344 back ok 4096 275690851
#|deflate rand L5 4101 2570684344 back ok 4096 275690851
#|deflate rand L6 4101 2570684344 back ok 4096 275690851
#|deflate rand L7 4101 2570684344 back ok 4096 275690851
#|deflate rand L8 4101 2570684344 back ok 4096 275690851
#|deflate rand L9 4101 2570684344 back ok 4096 275690851
#|deflate text L0 40005 563985101 back ok 40000 1758392975
#|deflate text L1 16199 4208514092 back ok 40000 1758392975
#|deflate text L2 15766 2512167925 back ok 40000 1758392975
#|deflate text L3 15207 4094456343 back ok 40000 1758392975
#|deflate text L4 14839 2617921393 back ok 40000 1758392975
#|deflate text L5 14366 1112654216 back ok 40000 1758392975
#|deflate text L6 14114 3854070424 back ok 40000 1758392975
#|deflate text L7 14055 105383165 back ok 40000 1758392975
#|deflate text L8 14017 1868283740 back ok 40000 1758392975
#|deflate text L9 14018 1597473911 back ok 40000 1758392975
#|fixed empty L1 2 1794392380 back ok 0 0
#|fixed empty L4 2 1794392380 back ok 0 0
#|fixed empty L9 2 1794392380 back ok 0 0
#|fixed one L1 3 538398705 back ok 1 1505515367
#|fixed one L4 3 538398705 back ok 1 1505515367
#|fixed one L9 3 538398705 back ok 1 1505515367
#|fixed rep L1 197 2517186447 back ok 20000 3401418545
#|fixed rep L4 130 965859345 back ok 20000 3401418545
#|fixed rep L9 130 965859345 back ok 20000 3401418545
#|fixed rand L1 4326 2821907903 back ok 4096 275690851
#|fixed rand L4 4326 2821907903 back ok 4096 275690851
#|fixed rand L9 4326 2821907903 back ok 4096 275690851
#|fixed text L1 20767 540296280 back ok 40000 1758392975
#|fixed text L4 18416 521321405 back ok 40000 1758392975
#|fixed text L9 16989 1483173473 back ok 40000 1758392975
#|stream zlib stored lengths bad BadStored
#|stream zlib fixed ok 0 0
#|stream zlib block type bad BadBlock
#|stream zlib stored ok 1 3523407757
#|stream zlib too many symbols bad BadCounts
#|stream zlib code lengths set bad BadCl
#|stream zlib bit length repeat bad BadRepeat
#|stream zlib bit length repeat 2 bad BadRepeat
#|stream zlib missing eob bad NoEnd
#|stream zlib literal set bad BadLit
#|stream zlib distances set bad BadDist
#|stream zlib literal code bad BadCode
#|stream zlib distance code bad BadCode
#|stream zlib too far back bad FarBack
#|stream zlib long code ok 0 0
#|stream zlib length extra ok 516 2893183767
#|stream zlib distance extra ok 518 2207093423
#|stream sym 286 bad BadCode
#|stream sym 287 bad BadCode
#|stream dist 30 bad BadCode
#|stream dist 31 bad BadCode
#|stream far by 1 bad FarBack
#|stream near ok ok 4 2912478533
#|stream overlap ok 259 3984420578
#|stream len 258 ok 259 3840496386
#|stream no final bad Truncated
#|stream empty input bad Truncated
#|stream cut header bad Truncated
#|stream stored cut bad Truncated
#|stream two blocks ok 2 2414225561
#|stream trailing ok 0 0
#|cap 65536 ok 65536 3617033963
#|cap 65535 bad TooBig
#|cap 1000 bad TooBig
#|cap 0 bad TooBig
#|reads 1 ok 40000 1758392975
#|reads 7 ok 40000 1758392975
#|reads 4096 ok 40000 1758392975
#|crc32 empty 0
#|crc32 one 1505515367
#|crc32 rep 3401418545
#|crc32 rand 275690851
#|crc32 text 1758392975
#|gunzip plain ok 240 134865084
#|gunzip empty file ok 0 0
#|gunzip empty member ok 0 0
#|gunzip fname ok 300 3502553220
#|gunzip all fields ok 150 147951193
#|gunzip two members ok 12 1288379315
#|gunzip zero pad ok 4 2918445923
#|gunzip pad between ok 2 2659403885
#|gunzip long extra ok 1 4110462503
#|gunzip bad crc bad BadCrc
#|gunzip bad size bad BadSize
#|gunzip bad magic bad NotGzip
#|gunzip bad method bad BadMethod
#|gunzip reserved flag bad BadFlags
#|gunzip bad hcrc bad BadHcrc
#|gunzip truncated bad Truncated
#|gunzip garbage after bad NotGzip
#|gunzip zero first bad NotGzip
#|gunzip bad stream bad Inflate:BadBlock
#|gunzip cap 6000 ok 6000 4147015640
#|gunzip cap 5999 bad Inflate:TooBig
#|gunzip cap 3000 bad Inflate:TooBig
#|gzip empty L0 23 2782941426 back ok 0 0
#|gzip empty L1 20 1177665071 back ok 0 0
#|gzip empty L6 20 1161266512 back ok 0 0
#|gzip empty L9 20 2836143055 back ok 0 0
#|gzip one L0 24 2795189770 back ok 1 1505515367
#|gzip one L1 21 1823047879 back ok 1 1505515367
#|gzip one L6 21 2886789713 back ok 1 1505515367
#|gzip one L9 21 3427557146 back ok 1 1505515367
#|gzip rep L0 20023 1108590060 back ok 20000 3401418545
#|gzip rep L1 124 1774111641 back ok 20000 3401418545
#|gzip rep L6 55 191117469 back ok 20000 3401418545
#|gzip rep L9 55 3650498135 back ok 20000 3401418545
#|gzip rand L0 4119 3289481243 back ok 4096 275690851
#|gzip rand L1 4119 3882594691 back ok 4096 275690851
#|gzip rand L6 4119 3289481243 back ok 4096 275690851
#|gzip rand L9 4119 3584858327 back ok 4096 275690851
#|gzip text L0 40023 3571019432 back ok 40000 1758392975
#|gzip text L1 16217 4230851943 back ok 40000 1758392975
#|gzip text L6 14132 195874640 back ok 40000 1758392975
#|gzip text L9 14036 2275137769 back ok 40000 1758392975
