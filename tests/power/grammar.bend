# Grammar against CPython (grammar_gen.py prints this file). A `doc` row is one
# document fed whole -- json.loads decided accept or reject for every one of
# them and the generator refuses to print a row it disagrees with. A `pin` row
# is the claim the lane exists for: the mask the module *derives* from its node,
# then the mask *brute-forced* by stepping all 256 bytes, printed side by side.
# They are different code paths, so a row where they differ is the constrained
# decoding bug caught in the act. A `fork` row takes three continuations from
# one state value and then prints that state again unchanged.
import Base
import ../../power/bytes.bend as Bytes
import ../../power/grammar.bend as Gr

# ascii only: this is a byte grammar and utf-8 inside a string is not its job
def of.push(c: Char, b: Bytes()) -> Bytes():
  match c:
    case Chr{code}:
      Bytes.push(b, code)

def of.go(s: String, b: Bytes()) -> Bytes():
  match s:
    case SNil{}:
      b
    case SCon{h, t}:
      of.go(t, of.push(h, b))

def of(s: String) -> Bytes():
  of.go(s, Bytes.new())

def yn(t: Bool) -> String:
  match t:
    case True{}:
      "Y"
    case False{}:
      "n"

# the Bytes is dropped here and the St kept: affine lets the document go, Data
# lets the state stay
def stt(w: Gr.Walk) -> Gr.St:
  match w:
    case Gr.Walk{b, s}:
      s

def at(d: String) -> Gr.St:
  stt(Gr.run(of(d), Gr.start()))

def on(+s: Gr.St, d: String) -> Gr.St:
  stt(Gr.run(of(d), s))

def end(+s: Gr.St) -> String:
  Gr.show(s) ++ " done=" ++ yn(Gr.done(s)) ++ " live=" ++ yn(Gr.live(s))

def doc(d: String) -> String:
  end(at(d))

# the mask the hard way: 256 steps, one bit a survivor. The module never does
# this -- it reads the node -- which is exactly why the two are worth printing
# in the same row.
def probe.b(+acc: U32, +j: U32, hit: Bool) -> U32:
  match hit:
    case True{}:
      U32.or(acc, U32.shln(1, U32.to_nat(j)))
    case False{}:
      acc

def probe.w(k: Nat, +c: U32, +j: U32, +s: Gr.St, acc: U32) -> U32:
  match k:
    case 0n:
      acc
    case 1n++p:
      probe.w(p, U32.inc(c), U32.inc(j), s, probe.b(acc, j, Gr.live(Gr.step(s, c))))

def probe(+s: Gr.St) -> Gr.Mask:
  Gr.Mask{probe.w(32n, 0, 0, s, 0), probe.w(32n, 32, 0, s, 0),
    probe.w(32n, 64, 0, s, 0), probe.w(32n, 96, 0, s, 0),
    probe.w(32n, 128, 0, s, 0), probe.w(32n, 160, 0, s, 0),
    probe.w(32n, 192, 0, s, 0), probe.w(32n, 224, 0, s, 0)}

def pin(+s: Gr.St) -> String:
  Gr.show(s) ++ " |" ++ Gr.Mask.show(Gr.mask(s)) ++ " |" ++ Gr.Mask.show(probe(s)) ++ " |"

# one parent value, three continuations, and the parent again
def fork3(+s: Gr.St, a: String, b: String, c: String) -> String:
  Gr.show(s) ++ " -> " ++ Gr.show(on(s, a)) ++ " " ++ Gr.show(on(s, b)) ++ " " ++ Gr.show(on(s, c)) ++ " -> " ++ Gr.show(s)

def nest(k: Nat, acc: String) -> String:
  match k:
    case 0n:
      acc
    case 1n++p:
      nest(p, "[" ++ acc ++ "]")

def deep(k: Nat) -> String:
  end(at(nest(k, "1")))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(doc("1"))
    IO.print(doc("0"))
    IO.print(doc("-0"))
    IO.print(doc("-1"))
    IO.print(doc("12"))
    IO.print(doc("1.5"))
    IO.print(doc("0.5"))
    IO.print(doc("-0.5"))
    IO.print(doc("1e2"))
    IO.print(doc("1E2"))
    IO.print(doc("1e+2"))
    IO.print(doc("1e-2"))
    IO.print(doc("0e0"))
    IO.print(doc("1.5e10"))
    IO.print(doc("-12.25E-3"))
    IO.print(doc("\"\""))
    IO.print(doc("\"a\""))
    IO.print(doc("\"a b\""))
    IO.print(doc("\"\\\"\""))
    IO.print(doc("\"\\\\\""))
    IO.print(doc("\"\\/\""))
    IO.print(doc("\"\\b\\f\\n\\r\\t\""))
    IO.print(doc("\"\\u00e9\""))
    IO.print(doc("\"\\uD83D\\uDE00\""))
    IO.print(doc("true"))
    IO.print(doc("false"))
    IO.print(doc("null"))
    IO.print(doc("[]"))
    IO.print(doc("{}"))
    IO.print(doc("[1]"))
    IO.print(doc("[1,2]"))
    IO.print(doc("[\"a\",1,true]"))
    IO.print(doc("{\"a\":1}"))
    IO.print(doc("{\"a\":1,\"b\":2}"))
    IO.print(doc("{\"a\":{\"b\":[1,{\"c\":null}]}}"))
    IO.print(doc("[[[]]]"))
    IO.print(doc("  1  "))
    IO.print(doc(" [ 1 , 2 ] "))
    IO.print(doc("{ \"a\" : 1 }"))
    IO.print(doc("[{}]"))
    IO.print(doc("[[],[]]"))
    IO.print(doc("{\"\":0}"))
    IO.print(doc("{\"a\":[],\"b\":{}}"))
    IO.print(doc("[0,-0,1e0]"))
    IO.print(doc("\t[\n1\r]\t"))
    IO.print(doc(""))
    IO.print(doc(" "))
    IO.print(doc("01"))
    IO.print(doc("-"))
    IO.print(doc("1."))
    IO.print(doc(".5"))
    IO.print(doc("1e"))
    IO.print(doc("1e+"))
    IO.print(doc("+1"))
    IO.print(doc("00"))
    IO.print(doc("0x1"))
    IO.print(doc("1 2"))
    IO.print(doc("["))
    IO.print(doc("]"))
    IO.print(doc("{"))
    IO.print(doc("}"))
    IO.print(doc("[,]"))
    IO.print(doc("[1,]"))
    IO.print(doc("[1 2]"))
    IO.print(doc("{\"a\"}"))
    IO.print(doc("{\"a\":}"))
    IO.print(doc("{:1}"))
    IO.print(doc("{\"a\":1,}"))
    IO.print(doc("{a:1}"))
    IO.print(doc("{'a':1}"))
    IO.print(doc("[1}"))
    IO.print(doc("{\"a\":1]"))
    IO.print(doc("tru"))
    IO.print(doc("truu"))
    IO.print(doc("fals"))
    IO.print(doc("nul"))
    IO.print(doc("nulll"))
    IO.print(doc("TRUE"))
    IO.print(doc("\""))
    IO.print(doc("\"a"))
    IO.print(doc("\"\\x\""))
    IO.print(doc("\"\\u12\""))
    IO.print(doc("\"\\u12g4\""))
    IO.print(doc("\"a\tb\""))
    IO.print(doc("\"a\nb\""))
    IO.print(doc("[]]"))
    IO.print(doc("{}}"))
    IO.print(doc("nan"))
    IO.print(doc("Infinity"))
    IO.print(doc("-Infinity"))
    IO.print(doc("NaN"))
    IO.print(doc("[1,,2]"))
    IO.print(doc("{\"a\" 1}"))
    IO.print(doc("--1"))
    IO.print(doc("1..2"))
    IO.print(doc("1e2e3"))
    IO.print(pin(at("1")))
    IO.print(pin(at("0")))
    IO.print(pin(at("-")))
    IO.print(pin(at("1.")))
    IO.print(pin(at("1.5")))
    IO.print(pin(at("1e")))
    IO.print(pin(at("1e2")))
    IO.print(pin(at("1e+")))
    IO.print(pin(at("\"")))
    IO.print(pin(at("\"\"")))
    IO.print(pin(at("\"\\")))
    IO.print(pin(at("\"\\u")))
    IO.print(pin(at("\"\\u0")))
    IO.print(pin(at("\"\\u00")))
    IO.print(pin(at("\"\\u00e")))
    IO.print(pin(at("t")))
    IO.print(pin(at("tr")))
    IO.print(pin(at("tru")))
    IO.print(pin(at("f")))
    IO.print(pin(at("fa")))
    IO.print(pin(at("fal")))
    IO.print(pin(at("fals")))
    IO.print(pin(at("n")))
    IO.print(pin(at("nu")))
    IO.print(pin(at("nul")))
    IO.print(pin(at("[")))
    IO.print(pin(at("{")))
    IO.print(pin(at("[1")))
    IO.print(pin(at("[1,")))
    IO.print(pin(at("[\"")))
    IO.print(pin(at("[\"a\"")))
    IO.print(pin(at("[\"a\",1,t")))
    IO.print(pin(at("[\"a\",1,tr")))
    IO.print(pin(at("[\"a\",1,tru")))
    IO.print(pin(at("{\"")))
    IO.print(pin(at("{\"a\"")))
    IO.print(pin(at("{\"a\":")))
    IO.print(pin(at("{\"a\":1")))
    IO.print(pin(at("{\"a\":1,")))
    IO.print(pin(at("{\"a\":{")))
    IO.print(pin(at("{\"a\":{\"")))
    IO.print(pin(at("{\"a\":{\"b\"")))
    IO.print(pin(at("{\"a\":{\"b\":")))
    IO.print(pin(at("{\"a\":{\"b\":[")))
    IO.print(pin(at("{\"a\":{\"b\":[1")))
    IO.print(pin(at("{\"a\":{\"b\":[1,")))
    IO.print(pin(at("{\"a\":{\"b\":[1,{")))
    IO.print(pin(at("{\"a\":{\"b\":[1,{\"")))
    IO.print(pin(at("{\"a\":{\"b\":[1,{\"c\"")))
    IO.print(pin(at("{\"a\":{\"b\":[1,{\"c\":")))
    IO.print(pin(at("{\"a\":{\"b\":[1,{\"c\":n")))
    IO.print(pin(at("{\"a\":{\"b\":[1,{\"c\":nu")))
    IO.print(pin(at("{\"a\":{\"b\":[1,{\"c\":nul")))
    IO.print(pin(at("{\"a\":{\"b\":[1,{\"c\":null")))
    IO.print(pin(at("{\"a\":{\"b\":[1,{\"c\":null}")))
    IO.print(pin(at("{\"a\":{\"b\":[1,{\"c\":null}]")))
    IO.print(pin(at("{\"a\":{\"b\":[1,{\"c\":null}]}")))
    IO.print(pin(at("[[")))
    IO.print(pin(at("[[[")))
    IO.print(pin(at("[[[]")))
    IO.print(pin(at(" ")))
    IO.print(pin(at("[{")))
    IO.print(pin(at("{\"\":0")))
    IO.print(pin(at("{\"a\":[")))
    IO.print(pin(at("[0")))
    IO.print(pin(at("[0,-")))
    IO.print(pin(at("[0,-0,1e")))
    IO.print(pin(at("[0,-0,1e0")))
    IO.print(pin(at("[[[[1")))
    IO.print(pin(at("[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[")))
    IO.print(pin(at("[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[{\"a\":")))
    IO.print(pin(at("[,")))
    IO.print(fork3(at("{\"a\":"), "1", "\"x\"", "["))
    IO.print(fork3(at("[1,"), "2]", "tru", "{"))
    IO.print(fork3(at("{\"a\":1"), ",", "}", "e"))
    IO.print(fork3(at(""), "{", "[", "1"))
    IO.print(fork3(at("[["), "]", "1", "]]"))
    IO.print(fork3(at("\"ab"), "c\"", "\\\\", "\""))
    IO.print(deep(1n))
    IO.print(deep(32n))
    IO.print(deep(63n))
    IO.print(deep(64n))
    IO.print(deep(65n))
#|int/0 done=Y live=Y
#|zero/0 done=Y live=Y
#|zero/0 done=Y live=Y
#|int/0 done=Y live=Y
#|int/0 done=Y live=Y
#|frac/0 done=Y live=Y
#|frac/0 done=Y live=Y
#|frac/0 done=Y live=Y
#|expd/0 done=Y live=Y
#|expd/0 done=Y live=Y
#|expd/0 done=Y live=Y
#|expd/0 done=Y live=Y
#|expd/0 done=Y live=Y
#|expd/0 done=Y live=Y
#|expd/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|val/0 done=n live=Y
#|val/0 done=n live=Y
#|dead/0 done=n live=n
#|min/0 done=n live=Y
#|dot/0 done=n live=Y
#|dead/0 done=n live=n
#|exp/0 done=n live=Y
#|esgn/0 done=n live=Y
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|vale/1 done=n live=Y
#|dead/0 done=n live=n
#|keye/1 done=n live=Y
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|t.e/0 done=n live=Y
#|dead/0 done=n live=n
#|f.e/0 done=n live=Y
#|n.l2/0 done=n live=Y
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|str/0 done=n live=Y
#|str/0 done=n live=Y
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|dead/0 done=n live=n
#|int/0 | 9-10 13 32 46 48-57 69 101 | 9-10 13 32 46 48-57 69 101 |
#|zero/0 | 9-10 13 32 46 69 101 | 9-10 13 32 46 69 101 |
#|min/0 | 48-57 | 48-57 |
#|dot/0 | 48-57 | 48-57 |
#|frac/0 | 9-10 13 32 48-57 69 101 | 9-10 13 32 48-57 69 101 |
#|exp/0 | 43 45 48-57 | 43 45 48-57 |
#|expd/0 | 9-10 13 32 48-57 | 9-10 13 32 48-57 |
#|esgn/0 | 48-57 | 48-57 |
#|str/0 | 32-255 | 32-255 |
#|fin/0 | 9-10 13 32 | 9-10 13 32 |
#|esc/0 | 34 47 92 98 102 110 114 116-117 | 34 47 92 98 102 110 114 116-117 |
#|u1/0 | 48-57 65-70 97-102 | 48-57 65-70 97-102 |
#|u2/0 | 48-57 65-70 97-102 | 48-57 65-70 97-102 |
#|u3/0 | 48-57 65-70 97-102 | 48-57 65-70 97-102 |
#|u4/0 | 48-57 65-70 97-102 | 48-57 65-70 97-102 |
#|t.r/0 | 114 | 114 |
#|t.u/0 | 117 | 117 |
#|t.e/0 | 101 | 101 |
#|f.a/0 | 97 | 97 |
#|f.l/0 | 108 | 108 |
#|f.s/0 | 115 | 115 |
#|f.e/0 | 101 | 101 |
#|n.u/0 | 117 | 117 |
#|n.l/0 | 108 | 108 |
#|n.l2/0 | 108 | 108 |
#|vale/1 | 9-10 13 32 34 45 48-57 91 93 102 110 116 123 | 9-10 13 32 34 45 48-57 91 93 102 110 116 123 |
#|keye/1 | 9-10 13 32 34 125 | 9-10 13 32 34 125 |
#|int/1 | 9-10 13 32 44 46 48-57 69 93 101 | 9-10 13 32 44 46 48-57 69 93 101 |
#|val/1 | 9-10 13 32 34 45 48-57 91 102 110 116 123 | 9-10 13 32 34 45 48-57 91 102 110 116 123 |
#|str/1 | 32-255 | 32-255 |
#|sep/1 | 9-10 13 32 44 93 | 9-10 13 32 44 93 |
#|t.r/1 | 114 | 114 |
#|t.u/1 | 117 | 117 |
#|t.e/1 | 101 | 101 |
#|str/1k | 32-255 | 32-255 |
#|colon/1 | 9-10 13 32 58 | 9-10 13 32 58 |
#|val/1 | 9-10 13 32 34 45 48-57 91 102 110 116 123 | 9-10 13 32 34 45 48-57 91 102 110 116 123 |
#|int/1 | 9-10 13 32 44 46 48-57 69 101 125 | 9-10 13 32 44 46 48-57 69 101 125 |
#|key/1 | 9-10 13 32 34 | 9-10 13 32 34 |
#|keye/2 | 9-10 13 32 34 125 | 9-10 13 32 34 125 |
#|str/2k | 32-255 | 32-255 |
#|colon/2 | 9-10 13 32 58 | 9-10 13 32 58 |
#|val/2 | 9-10 13 32 34 45 48-57 91 102 110 116 123 | 9-10 13 32 34 45 48-57 91 102 110 116 123 |
#|vale/3 | 9-10 13 32 34 45 48-57 91 93 102 110 116 123 | 9-10 13 32 34 45 48-57 91 93 102 110 116 123 |
#|int/3 | 9-10 13 32 44 46 48-57 69 93 101 | 9-10 13 32 44 46 48-57 69 93 101 |
#|val/3 | 9-10 13 32 34 45 48-57 91 102 110 116 123 | 9-10 13 32 34 45 48-57 91 102 110 116 123 |
#|keye/4 | 9-10 13 32 34 125 | 9-10 13 32 34 125 |
#|str/4k | 32-255 | 32-255 |
#|colon/4 | 9-10 13 32 58 | 9-10 13 32 58 |
#|val/4 | 9-10 13 32 34 45 48-57 91 102 110 116 123 | 9-10 13 32 34 45 48-57 91 102 110 116 123 |
#|n.u/4 | 117 | 117 |
#|n.l/4 | 108 | 108 |
#|n.l2/4 | 108 | 108 |
#|sep/4 | 9-10 13 32 44 125 | 9-10 13 32 44 125 |
#|sep/3 | 9-10 13 32 44 93 | 9-10 13 32 44 93 |
#|sep/2 | 9-10 13 32 44 125 | 9-10 13 32 44 125 |
#|sep/1 | 9-10 13 32 44 125 | 9-10 13 32 44 125 |
#|vale/2 | 9-10 13 32 34 45 48-57 91 93 102 110 116 123 | 9-10 13 32 34 45 48-57 91 93 102 110 116 123 |
#|vale/3 | 9-10 13 32 34 45 48-57 91 93 102 110 116 123 | 9-10 13 32 34 45 48-57 91 93 102 110 116 123 |
#|sep/2 | 9-10 13 32 44 93 | 9-10 13 32 44 93 |
#|val/0 | 9-10 13 32 34 45 48-57 91 102 110 116 123 | 9-10 13 32 34 45 48-57 91 102 110 116 123 |
#|keye/2 | 9-10 13 32 34 125 | 9-10 13 32 34 125 |
#|zero/1 | 9-10 13 32 44 46 69 101 125 | 9-10 13 32 44 46 69 101 125 |
#|vale/2 | 9-10 13 32 34 45 48-57 91 93 102 110 116 123 | 9-10 13 32 34 45 48-57 91 93 102 110 116 123 |
#|zero/1 | 9-10 13 32 44 46 69 93 101 | 9-10 13 32 44 46 69 93 101 |
#|min/1 | 48-57 | 48-57 |
#|exp/1 | 43 45 48-57 | 43 45 48-57 |
#|expd/1 | 9-10 13 32 44 48-57 93 | 9-10 13 32 44 48-57 93 |
#|int/4 | 9-10 13 32 44 46 48-57 69 93 101 | 9-10 13 32 44 46 48-57 69 93 101 |
#|vale/64 | 9-10 13 32 34 45 48-57 93 102 110 116 | 9-10 13 32 34 45 48-57 93 102 110 116 |
#|val/64 | 9-10 13 32 34 45 48-57 102 110 116 | 9-10 13 32 34 45 48-57 102 110 116 |
#|dead/0 | | |
#|val/1 -> int/1 sep/1 vale/2 -> val/1
#|val/1 -> fin/0 t.e/1 keye/2 -> val/1
#|int/1 -> key/1 fin/0 exp/1 -> int/1
#|val/0 -> keye/1 vale/1 int/0 -> val/0
#|vale/2 -> sep/1 int/2 fin/0 -> vale/2
#|str/0 -> fin/0 str/0 fin/0 -> str/0
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|fin/0 done=Y live=Y
#|dead/0 done=n live=n
