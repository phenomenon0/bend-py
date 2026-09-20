# Json against CPython (json_gen.py prints this file). An `ev` row is every
# event of one document and the budget it had left; a `chk` row is only the
# event that ended it, which is `eof` or the refusal; `sk` skips the next value
# whole; `rw` reads a span back out of the caller's own bytes. A span is
# `name@offset+length` into the document, never a copy. CPython's json decides
# accept or reject for every document here and its own lexer decides every span
# -- the generator refuses to print a fixture that disagrees with either.
import Base
import ../../power/bytes.bend as Bytes
import ../../power/json.bend as Json

# ascii only: the corpus writes non-ascii as \uXXXX, which is ascii itself
# (ponytail: a utf-8 encoder lands with the first consumer that has a String)
def of.push(c: Char, b: Bytes.Bytes) -> Bytes.Bytes:
  match c:
    case Chr{code}:
      Bytes.push(b, code)

def of.go(s: String, b: Bytes.Bytes) -> Bytes.Bytes:
  match s:
    case SNil{}:
      b
    case SCon{h, t}:
      of.go(t, of.push(h, b))

def of(s: String) -> Bytes.Bytes:
  of.go(s, Bytes.new())

type Run is Type:
  Run{s: Json.St, acc: String, on: Bool}

def run.mk(+e: Json.Event, acc: String, s: Json.St) -> Run:
  Run{s, acc ++ Json.show(e) ++ " ", Json.live(e)}

def run.step(acc: String, r: Json.St & Json.Event) -> Run:
  (s, +e) = r
  run.mk(e, acc, s)

def run.go(fuel: Nat, k: Run) -> Run:
  match fuel:
    case 0n:
      k
    case 1n++p:
      match k:
        case Run{s, acc, on}:
          match on:
            case True{}:
              run.go(p, run.step(acc, Json.next(s)))
            case False{}:
              Run{s, acc, False{}}

def run.left(acc: String, r: Bytes.Bytes & U32) -> String:
  (b, l) = r
  acc ++ "left=" ++ U32.show(l)

def run.out(k: Run) -> String:
  match k:
    case Run{s, acc, on}:
      run.left(acc, Json.finish(s))

def drain(acc: String, s: Json.St) -> String:
  run.out(run.go(4096n, Run{s, acc, True{}}))

def ev(doc: String, +limit: U32) -> String:
  drain("", Json.start(of(doc), limit))

def chk.e(r: Bytes.Bytes & Json.Event) -> String:
  (b, e) = r
  Json.show(e)

def chk(doc: String, +limit: U32) -> String:
  chk.e(Json.check(of(doc), limit))

def pre.s(r: Json.St & Json.Event) -> Json.St:
  (s, e) = r
  s

def pre(k: Nat, s: Json.St) -> Json.St:
  match k:
    case 0n:
      s
    case 1n++p:
      pre(p, pre.s(Json.next(s)))

def sk.run(r: Json.St & Json.Event) -> String:
  (s, +e) = r
  drain(Json.show(e) ++ " ", s)

def sk(doc: String, k: Nat, +limit: U32) -> String:
  sk.run(Json.skip(pre(k, Json.start(of(doc), limit))))

def rw.out(r: Bytes.Bytes & String) -> String:
  (b, s) = r
  s

def rw(doc: String, +at: U32, +len: U32) -> String:
  rw.out(Json.raw(of(doc), at, len))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(ev("1", 1000000))
    IO.print(ev("0", 1000000))
    IO.print(ev("-0", 1000000))
    IO.print(ev("12345", 1000000))
    IO.print(ev("-7", 1000000))
    IO.print(ev("1.5", 1000000))
    IO.print(ev("-2.5e3", 1000000))
    IO.print(ev("0.10", 1000000))
    IO.print(ev("1E+40", 1000000))
    IO.print(ev("1e-0", 1000000))
    IO.print(ev("1e400", 1000000))
    IO.print(ev("\"\"", 1000000))
    IO.print(ev("\"x\"", 1000000))
    IO.print(ev("\"\\u0041\\t\"", 1000000))
    IO.print(ev("\"a\\\\b\"", 1000000))
    IO.print(ev("\"\\\"\\/\\b\\f\\n\\r\"", 1000000))
    IO.print(ev("true", 1000000))
    IO.print(ev("false", 1000000))
    IO.print(ev("null", 1000000))
    IO.print(ev("[]", 1000000))
    IO.print(ev("{}", 1000000))
    IO.print(ev("[1]", 1000000))
    IO.print(ev("[[]]", 1000000))
    IO.print(ev("[{}]", 1000000))
    IO.print(ev("{\"a\":1}", 1000000))
    IO.print(ev("{\"\":null}", 1000000))
    IO.print(ev("{\"a\":{\"b\":[1,2,{\"c\":true}]}}", 1000000))
    IO.print(ev("[1,2,3,[4,[5]],{\"k\":\"v\"}]", 1000000))
    IO.print(ev("  \t\n\r [ 1 , 2 ]  \n", 1000000))
    IO.print(ev("{ \"a\" : 1 , \"b\" : 2 }", 1000000))
    IO.print(ev("[\"\\u00e9\", \"\\ud83d\\ude00\"]", 1000000))
    IO.print(chk("", 1000000))
    IO.print(chk(" ", 1000000))
    IO.print(chk("[", 1000000))
    IO.print(chk("{", 1000000))
    IO.print(chk("[1", 1000000))
    IO.print(chk("{\"a\"", 1000000))
    IO.print(chk("{\"a\":", 1000000))
    IO.print(chk("{\"a\":1", 1000000))
    IO.print(chk("\"abc", 1000000))
    IO.print(chk("\"abc\\", 1000000))
    IO.print(chk("]", 1000000))
    IO.print(chk("}", 1000000))
    IO.print(chk(",", 1000000))
    IO.print(chk(":", 1000000))
    IO.print(chk("x", 1000000))
    IO.print(chk("tru", 1000000))
    IO.print(chk("truE", 1000000))
    IO.print(chk("trues", 1000000))
    IO.print(chk("nul", 1000000))
    IO.print(chk("fals", 1000000))
    IO.print(chk("01", 1000000))
    IO.print(chk("-01", 1000000))
    IO.print(chk("00", 1000000))
    IO.print(chk(".5", 1000000))
    IO.print(chk("1.", 1000000))
    IO.print(chk("1.e5", 1000000))
    IO.print(chk("1e", 1000000))
    IO.print(chk("1e+", 1000000))
    IO.print(chk("-", 1000000))
    IO.print(chk("+1", 1000000))
    IO.print(chk("1 2", 1000000))
    IO.print(chk("[]]", 1000000))
    IO.print(chk("[1,]", 1000000))
    IO.print(chk("[,1]", 1000000))
    IO.print(chk("[1,,2]", 1000000))
    IO.print(chk("{\"a\":1,}", 1000000))
    IO.print(chk("{,}", 1000000))
    IO.print(chk("{\"a\"1}", 1000000))
    IO.print(chk("{\"a\":1:2}", 1000000))
    IO.print(chk("{a:1}", 1000000))
    IO.print(chk("{1:2}", 1000000))
    IO.print(chk("{\"a\":}", 1000000))
    IO.print(chk("[1}", 1000000))
    IO.print(chk("{]", 1000000))
    IO.print(chk("[\"a\" \"b\"]", 1000000))
    IO.print(chk("\"\\q\"", 1000000))
    IO.print(chk("\"\\u12\"", 1000000))
    IO.print(chk("\"\\u12x4\"", 1000000))
    IO.print(chk("\"\\uZZZZ\"", 1000000))
    IO.print(chk("\"\\u123\"", 1000000))
    IO.print(chk("\"a\tb\"", 1000000))
    IO.print(chk("\"a\u{1}b\"", 1000000))
    IO.print(chk("[1, 2", 1000000))
    IO.print(chk("nan", 1000000))
    IO.print(chk("Infinity", 1000000))
    IO.print(chk("'x'", 1000000))
    IO.print(chk("[01]", 1000000))
    IO.print(chk("{\"a\":01}", 1000000))
    IO.print(chk("1.5.5", 1000000))
    IO.print(chk("--1", 1000000))
    IO.print(chk("0x10", 1000000))
    IO.print(ev("[1,]", 1000000))
    IO.print(ev("{\"a\"1}", 1000000))
    IO.print(ev("\"\\u12x4\"", 1000000))
    IO.print(ev("[1 2]", 1000000))
    IO.print(ev("01", 1000000))
    IO.print(ev("[\"abcdefgh\", 1]", 0))
    IO.print(ev("[\"abcdefgh\", 1]", 1))
    IO.print(ev("[\"abcdefgh\", 1]", 2))
    IO.print(ev("[\"abcdefgh\", 1]", 4))
    IO.print(ev("[\"abcdefgh\", 1]", 5))
    IO.print(ev("[\"abcdefgh\", 1]", 6))
    IO.print(ev("[\"abcdefgh\", 1]", 11))
    IO.print(ev("[\"abcdefgh\", 1]", 12))
    IO.print(ev("[\"abcdefgh\", 1]", 13))
    IO.print(ev("[\"abcdefgh\", 1]", 14))
    IO.print(ev("[\"abcdefgh\", 1]", 40))
    IO.print(ev("\"abcdefgh\"", 0))
    IO.print(ev("\"abcdefgh\"", 3))
    IO.print(ev("\"abcdefgh\"", 6))
    IO.print(ev("\"abcdefgh\"", 7))
    IO.print(ev("\"abcdefgh\"", 8))
    IO.print(ev("-2.5e3", 0))
    IO.print(ev("-2.5e3", 1))
    IO.print(ev("-2.5e3", 2))
    IO.print(ev("-2.5e3", 3))
    IO.print(ev("-2.5e3", 6))
    IO.print(ev("false", 0))
    IO.print(ev("false", 3))
    IO.print(ev("false", 4))
    IO.print(ev("false", 5))
    IO.print(ev("   [ 1 ]   ", 2))
    IO.print(ev("[1]", 2))
    IO.print(ev("{\"aa\":1,\"bb\":2}", 9))
    IO.print(chk("[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[1]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]", 1000000))
    IO.print(chk("[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[1]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]", 1000000))
    IO.print(chk("[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[1]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]", 1000000))
    IO.print(chk("[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]", 1000000))
    IO.print(chk("{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":1}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}", 1000000))
    IO.print(chk("{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":1}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}", 1000000))
    IO.print(sk("{\"a\":[1,2,3],\"b\":7}", 2n, 1000000))
    IO.print(sk("[[1,[2,3]],9]", 0n, 1000000))
    IO.print(sk("[{\"a\":{\"b\":1}},2]", 1n, 1000000))
    IO.print(sk("[[1,2],\"x\"]", 0n, 1000000))
    IO.print(rw("{\"a\":123,\"bb\":\"xy\"}", 2, 1))
    IO.print(rw("{\"a\":123,\"bb\":\"xy\"}", 5, 3))
    IO.print(rw("{\"a\":123,\"bb\":\"xy\"}", 10, 2))
    IO.print(rw("{\"a\":123,\"bb\":\"xy\"}", 15, 2))
    IO.print(rw("\"\\u0041\\t\"", 1, 8))
    IO.print(rw("[]", 0, 0))
    IO.print(ev("{\"a\":123,\"bb\":\"xy\"}", 1000000))
    IO.print(ev("[1.5e2,\"\\n\"]", 1000000))
#|num@0+1 eof left=999999
#|num@0+1 eof left=999999
#|num@0+2 eof left=999998
#|num@0+5 eof left=999995
#|num@0+2 eof left=999998
#|num@0+3 eof left=999997
#|num@0+6 eof left=999994
#|num@0+4 eof left=999996
#|num@0+5 eof left=999995
#|num@0+4 eof left=999996
#|num@0+5 eof left=999995
#|str@1+0 eof left=999998
#|str@1+1 eof left=999997
#|str@1+8 eof left=999990
#|str@1+4 eof left=999994
#|str@1+12 eof left=999986
#|true eof left=999996
#|false eof left=999995
#|null eof left=999996
#|[ ] eof left=999998
#|{ } eof left=999998
#|[ num@1+1 ] eof left=999997
#|[ [ ] ] eof left=999996
#|[ { } ] eof left=999996
#|{ key@2+1 num@5+1 } eof left=999993
#|{ key@2+0 null } eof left=999991
#|{ key@2+1 { key@7+1 [ num@11+1 num@13+1 { key@17+1 true } ] } } eof left=999972
#|[ num@1+1 num@3+1 num@5+1 [ num@8+1 [ num@11+1 ] ] { key@17+1 str@21+1 } ] eof left=999975
#|[ num@8+1 num@12+1 ] eof left=999995
#|{ key@3+1 num@8+1 key@13+1 num@18+1 } eof left=999987
#|[ str@2+6 str@12+12 ] eof left=999975
#|!cut@0
#|!cut@1
#|!cut@1
#|!cut@1
#|!cut@2
#|!cut@4
#|!cut@5
#|!cut@6
#|!cut@4
#|!cut@5
#|!char@0
#|!char@0
#|!char@0
#|!char@0
#|!char@0
#|!char@3
#|!char@3
#|!char@4
#|!char@3
#|!char@4
#|!digit@2
#|!digit@3
#|!digit@2
#|!char@0
#|!digit@2
#|!digit@2
#|!digit@2
#|!digit@3
#|!digit@1
#|!char@0
#|!char@2
#|!char@2
#|!char@3
#|!char@1
#|!char@3
#|!char@7
#|!char@1
#|!char@4
#|!char@6
#|!char@1
#|!char@1
#|!char@5
#|!char@2
#|!char@1
#|!char@5
#|!esc@2
#|!esc@5
#|!esc@5
#|!esc@3
#|!esc@6
#|!ctrl@2
#|!ctrl@2
#|!cut@5
#|!char@1
#|!char@0
#|!char@0
#|!digit@3
#|!digit@7
#|!char@3
#|!digit@1
#|!char@1
#|[ num@1+1 !char@3 left=999997
#|{ !char@4 left=999996
#|!esc@5 left=1000000
#|[ num@1+1 !char@3 left=999998
#|!digit@2 left=1000000
#|[ !dry@3 left=0
#|[ !dry@3 left=0
#|[ !dry@4 left=1
#|[ !dry@6 left=3
#|[ !dry@7 left=4
#|[ !dry@8 left=5
#|[ str@2+8 !dry@14 left=0
#|[ str@2+8 !dry@14 left=0
#|[ str@2+8 num@13+1 ] eof left=0
#|[ str@2+8 num@13+1 ] eof left=0
#|[ str@2+8 num@13+1 ] eof left=26
#|!dry@2 left=0
#|!dry@5 left=3
#|!dry@8 left=6
#|!dry@9 left=7
#|!dry@10 left=8
#|!dry@6 left=0
#|!dry@6 left=1
#|!dry@6 left=2
#|!dry@6 left=3
#|num@0+6 eof left=0
#|!dry@5 left=0
#|!dry@5 left=3
#|!dry@5 left=4
#|false eof left=0
#|[ num@5+1 ] eof left=0
#|[ num@1+1 ] eof left=0
#|{ key@2+2 num@6+1 !dry@11 left=1
#|eof
#|eof
#|!deep@256
#|eof
#|eof
#|!deep@1280
#|] key@14+1 num@17+1 } eof left=999981
#|] eof left=999987
#|} num@15+1 ] eof left=999983
#|] eof left=999989
#|a
#|123
#|bb
#|xy
#|\u0041\t
#|
#|{ key@2+1 num@5+3 key@10+2 str@15+2 } eof left=999981
#|[ num@1+5 str@8+2 ] eof left=999988
