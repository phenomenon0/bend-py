# Text against CPython (text_gen.py prints this file). unicodedata.normalize
# and str.casefold answer every normalizing row; regex's \X answers every
# grapheme row; bytes.decode answers every validity row. The `rt` rows are the
# law the lane exists for -- "1" then the code points of one normalized
# segment, where the 1 is Bend agreeing that re-normalizing the original bytes
# back(o) pointed at reproduces exactly those code points. Both sides of the
# claim are in one string, so a Bend that mapped the offset to the wrong
# segment cannot print the row at all.
import Base
import ../../power/vec.bend as Vec
import ../../power/bytes.bend as By
import ../../power/text.bend as Text

def yn(b: Bool) -> String:
  match b:
    case True{}:
      "1"
    case False{}:
      "0"

def w(s: String) -> String:
  "<" ++ s ++ ">"

def cp.s(r: Bytes() & String) -> String:
  (b, s) = r
  w(s)

def cp(b: Bytes()) -> String:
  cp.s(Text.cps(b))

def vd.s(r: Bytes() & Bool) -> String:
  (b, x) = r
  yn(x)

def vd(b: Bytes()) -> String:
  vd.s(Text.valid(b))

def nc.s(r: Text.Norm & String) -> String:
  (m, s) = r
  w(s)

def nc(m: Text.Norm) -> String:
  nc.s(Text.ncps(m))

# the inputs: code points folded through Text.emit, so the encoder is on the
# hook for every row the decoder answers
def mk.go(xs: List<&2, U32>, b: Bytes()) -> Bytes():
  match xs:
    case Nil{}:
      b
    case Con{x, t}:
      mk.go(t, Text.emit(b, x))

def mk(xs: List<&2, U32>) -> Bytes():
  mk.go(xs, By.new())

type Bv is Type:
  Bv{i: U32, b: Bytes(), s: String}

def bv.put(+i: U32, s: String, r: Bytes() & U32) -> Bv:
  (b, x) = r
  Bv{U32.inc(i), b, s ++ U32.show(x) ++ " "}

def bv.step(t: Bv) -> Bv:
  match t:
    case Bv{+i, b, s}:
      bv.put(i, s, By.at(b, i))

def bv.go(fuel: Nat, t: Bv) -> Bv:
  match fuel:
    case 0n:
      t
    case 1n++p:
      bv.go(p, bv.step(t))

def bv.take(t: Bv) -> String:
  match t:
    case Bv{i, b, s}:
      w(s)

def bv.n(r: Bytes() & U32) -> String:
  (b, +n) = r
  bv.take(bv.go(U32.to_nat(n), Bv{0, b, ""}))

def bv(b: Bytes()) -> String:
  bv.n(By.len(b))

type Vs is Type:
  Vs{i: U32, v: Vec.Vec, s: String}

def vs.put(+i: U32, s: String, r: Vec.Vec & U32) -> Vs:
  (v, x) = r
  Vs{U32.inc(i), v, s ++ U32.show(x) ++ " "}

def vs.step(t: Vs) -> Vs:
  match t:
    case Vs{+i, v, s}:
      vs.put(i, s, Vec.at(v, i))

def vs.go(fuel: Nat, t: Vs) -> Vs:
  match fuel:
    case 0n:
      t
    case 1n++p:
      vs.go(p, vs.step(t))

def vs.take(t: Vs) -> String:
  match t:
    case Vs{i, v, s}:
      w(s)

def vs.n(r: Vec.Vec & U32) -> String:
  (v, +n) = r
  vs.take(vs.go(U32.to_nat(n), Vs{0, v, ""}))

def gv(r: Bytes() & Vec.Vec) -> String:
  (b, v) = r
  vs.n(Vec.len(v))

# the original has to outlive the normalizer for the law to be checkable at
# all, and norm takes its input: a copy through the byte list is the cheapest
# honest way to hold one
def dup.mk(r: Bytes() & List<&2, U32>) -> Bytes() & Bytes():
  (b, xs) = r
  (b, By.from_list(xs, By.new()))

def dup(b: Bytes()) -> Bytes() & Bytes():
  dup.mk(By.to_list(b))

def dims.s(n: U32, r: Text.Norm & U32) -> String:
  (m, k) = r
  U32.show(n) ++ " " ++ U32.show(k)

def dims.l(r: Text.Norm & U32) -> String:
  (m, n) = r
  dims.s(n, Text.nsegs(m))

def dims(b: Bytes(), +f: Text.Form) -> String:
  dims.l(Text.nlen(Text.norm(b, f)))

def rt.cmp(+a: String, b: String) -> String:
  yn(String.eq(a, b)) ++ " " ++ a

def rt.re(seg: String, f: Text.Form, r: Bytes() & Bytes()) -> String:
  (o, sl) = r
  rt.cmp(seg, nc(Text.norm(sl, f)))

def rt.sl(seg: String, f: Text.Form, orig: Bytes(), +s: U32, +e: U32) -> String:
  rt.re(seg, f, Text.slice(orig, s, e))

def rt.ns(orig: Bytes(), f: Text.Form, +s: U32, +e: U32,
  r: Text.Norm & Bytes()) -> String:
  (m, x) = r
  rt.sl(cp(x), f, orig, s, e)

def rt.fwd2(orig: Bytes(), f: Text.Form, +s: U32, +e: U32, m: Text.Norm,
  dd: U32 & U32) -> String:
  (ds, de) = dd
  rt.ns(orig, f, s, e, Text.nslice(m, ds, de))

def rt.fwd(orig: Bytes(), f: Text.Form, +s: U32, +e: U32,
  r: Text.Norm & (U32 & U32)) -> String:
  (m, dd) = r
  rt.fwd2(orig, f, s, e, m, dd)

def rt.se(orig: Bytes(), f: Text.Form, m: Text.Norm, +s: U32, +e: U32) -> String:
  rt.fwd(orig, f, s, e, Text.fwd(m, s))

def rt.se2(orig: Bytes(), f: Text.Form, m: Text.Norm, se: U32 & U32) -> String:
  (s, e) = se
  rt.se(orig, f, m, s, e)

def rt.back(orig: Bytes(), f: Text.Form, r: Text.Norm & (U32 & U32)) -> String:
  (m, se) = r
  rt.se2(orig, f, m, se)

def rt.m(f: Text.Form, +o: U32, orig: Bytes(), m: Text.Norm) -> String:
  rt.back(orig, f, Text.back(m, o))

def rt.d(+f: Text.Form, +o: U32, r: Bytes() & Bytes()) -> String:
  (a, b) = r
  rt.m(f, o, a, Text.norm(b, f))

# rt: back(o) to a range of the original, slice it out, normalize that slice
# alone, and hold it against the normalized segment fwd says it became
def rt(b: Bytes(), +f: Text.Form, +o: U32) -> String:
  rt.d(f, o, dup(b))

def sp.f(+d: U32, +v: U32, r: Text.Norm & (U32 & U32)) -> String:
  (m, ab) = r
  Text.span.show(Text.span(d, v, ab))

# a citation: the byte range of the original, carried with the document and the
# revision it was read against, because a range without a revision is a range
# that will one day point at the wrong bytes
def sp(b: Bytes(), +f: Text.Form, +d: U32, +v: U32, +o: U32) -> String:
  sp.f(d, v, Text.back(Text.norm(b, f), o))

def s1() -> Bytes():
  By.from_list([65], By.new())

def s2() -> Bytes():
  By.from_list([72, 101, 108, 108, 111, 44, 32, 119, 111, 114, 108, 100], By.new())

def s3() -> Bytes():
  By.from_list([101, 204, 129], By.new())

def s4() -> Bytes():
  By.from_list([195, 169], By.new())

def s5() -> Bytes():
  By.from_list([195, 169, 204, 163], By.new())

def s6() -> Bytes():
  By.from_list([101, 204, 163, 204, 129], By.new())

def s7() -> Bytes():
  By.from_list([101, 204, 129, 204, 163], By.new())

def s8() -> Bytes():
  By.from_list([113, 204, 135, 204, 163], By.new())

def s9() -> Bytes():
  By.from_list([225, 184, 139, 204, 163], By.new())

def s10() -> Bytes():
  By.from_list([225, 184, 140, 204, 135], By.new())

def s11() -> Bytes():
  By.from_list([65, 204, 129, 66, 67, 204, 167], By.new())

def s12() -> Bytes():
  By.from_list([195, 128, 195, 168, 225, 186, 155], By.new())

def s13() -> Bytes():
  By.from_list([83, 84, 82, 65, 83, 83, 69], By.new())

def s14() -> Bytes():
  By.from_list([77, 97, 115, 115, 101], By.new())

def s15() -> Bytes():
  By.from_list([234, 176, 128, 225, 134, 168], By.new())

def s16() -> Bytes():
  By.from_list([225, 132, 128, 225, 133, 161, 225, 134, 168], By.new())

def s17() -> Bytes():
  By.from_list([234, 176, 129, 225, 132, 128, 225, 133, 161], By.new())

def s18() -> Bytes():
  By.from_list([225, 186, 155, 204, 163], By.new())

def s19() -> Bytes():
  By.from_list([226, 137, 160, 226, 137, 174, 226, 137, 175], By.new())

def s20() -> Bytes():
  By.from_list([206, 133], By.new())

def s21() -> Bytes():
  By.from_list([65, 204, 133, 204, 128, 204, 129, 204, 130, 204, 131], By.new())

def s22() -> Bytes():
  By.from_list([97, 204, 150, 204, 128, 204, 129, 98], By.new())

def s23() -> Bytes():
  By.from_list([228, 184, 173, 230, 150, 135, 97, 204, 129], By.new())

def s24() -> Bytes():
  By.from_list([240, 159, 152, 128, 204, 129, 65], By.new())

def s25() -> Bytes():
  By.from_list([67, 97, 102, 195, 169, 32, 228, 184, 173, 230, 150, 135, 32, 234, 176, 128], By.new())

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(cp(By.from_list([], By.new())))
    IO.print(cp(By.from_list([72, 105], By.new())))
    IO.print(cp(By.from_list([110, 204, 131], By.new())))
    IO.print(cp(By.from_list([226, 130, 172, 53], By.new())))
    IO.print(cp(By.from_list([240, 159, 152, 128, 33], By.new())))
    IO.print(cp(By.from_list([234, 176, 128, 225, 134, 168], By.new())))
    IO.print(cp(By.from_list([204, 129, 204, 163], By.new())))
    IO.print(cp(mk([])))
    IO.print(cp(mk([72, 105])))
    IO.print(cp(mk([110, 771])))
    IO.print(cp(mk([8364, 53])))
    IO.print(cp(mk([128512, 33])))
    IO.print(cp(mk([44032, 4520])))
    IO.print(cp(mk([769, 803])))
    IO.print(bv(mk([])))
    IO.print(bv(mk([72, 105])))
    IO.print(bv(mk([110, 771])))
    IO.print(bv(mk([8364, 53])))
    IO.print(bv(mk([128512, 33])))
    IO.print(bv(mk([44032, 4520])))
    IO.print(bv(mk([769, 803])))
    IO.print(vd(By.from_list([], By.new())))
    IO.print(vd(By.from_list([65], By.new())))
    IO.print(vd(By.from_list([195, 169], By.new())))
    IO.print(vd(By.from_list([226, 130, 172], By.new())))
    IO.print(vd(By.from_list([240, 159, 152, 128], By.new())))
    IO.print(vd(By.from_list([244, 143, 191, 191], By.new())))
    IO.print(vd(By.from_list([128], By.new())))
    IO.print(vd(By.from_list([191, 191], By.new())))
    IO.print(vd(By.from_list([195], By.new())))
    IO.print(vd(By.from_list([194, 65], By.new())))
    IO.print(vd(By.from_list([192, 128], By.new())))
    IO.print(vd(By.from_list([193, 191], By.new())))
    IO.print(vd(By.from_list([224, 128, 128], By.new())))
    IO.print(vd(By.from_list([226, 130], By.new())))
    IO.print(vd(By.from_list([237, 160, 128], By.new())))
    IO.print(vd(By.from_list([237, 191, 191], By.new())))
    IO.print(vd(By.from_list([240, 128, 128, 128], By.new())))
    IO.print(vd(By.from_list([244, 144, 128, 128], By.new())))
    IO.print(vd(By.from_list([245, 128, 128, 128], By.new())))
    IO.print(vd(By.from_list([255], By.new())))
    IO.print(vd(By.from_list([65, 195, 169, 128], By.new())))
    IO.print(gv(Text.graphemes(By.from_list([], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([65], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([97, 98, 99], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([13, 10], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([10, 13], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([13, 13, 10, 10], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([97, 13, 10, 98], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([9, 97, 0, 98], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([101, 204, 129], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([101, 204, 129, 204, 163, 204, 167], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([204, 129], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([65, 194, 173, 32, 66], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([226, 128, 139, 65], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([240, 159, 135, 166, 240, 159, 135, 167], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([240, 159, 135, 166, 240, 159, 135, 167, 240, 159, 135, 168], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([240, 159, 135, 166, 240, 159, 135, 167, 240, 159, 135, 168, 240, 159, 135, 169], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([65, 240, 159, 135, 166, 240, 159, 135, 167, 66], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([240, 159, 135, 186, 240, 159, 135, 184, 240, 159, 135, 186, 240, 159, 135, 184], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([240, 159, 145, 168, 226, 128, 141, 240, 159, 145, 169, 226, 128, 141, 240, 159, 145, 166], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([240, 159, 145, 169, 240, 159, 143, 187, 226, 128, 141, 240, 159, 167, 145], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([240, 159, 152, 128, 226, 128, 141, 65], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([65, 226, 128, 141, 240, 159, 152, 128], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([240, 159, 152, 128, 239, 184, 143], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([226, 157, 164, 239, 184, 143], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([226, 153, 165, 226, 173, 144], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([226, 128, 188, 226, 129, 137], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([240, 159, 155, 179, 240, 159, 152, 128], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([234, 176, 128, 235, 147, 140], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([225, 132, 128, 225, 133, 161, 225, 134, 168], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([225, 132, 128, 225, 133, 161], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([234, 176, 128, 225, 134, 168], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([234, 176, 129, 225, 134, 168], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([225, 133, 161, 225, 132, 128], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([224, 164, 149, 224, 164, 190, 224, 164, 130], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([224, 164, 149, 224, 164, 188, 224, 164, 130, 224, 164, 149], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([216, 128, 224, 164, 149], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([224, 181, 142, 65], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([216, 128, 13], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([239, 187, 191, 65, 228, 184, 173], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([228, 184, 173, 204, 129, 228, 184, 173], By.new()))))
    IO.print(gv(Text.graphemes(By.from_list([97, 204, 136, 240, 159, 135, 166, 240, 159, 135, 167, 13, 10, 234, 176, 128, 225, 134, 168], By.new()))))
    IO.print(nc(Text.norm(By.new(), Text.Nfc{})))
    IO.print(dims(By.new(), Text.Nfd{}))
    IO.print(nc(Text.norm(s1(), Text.Nfd{})))
    IO.print(nc(Text.norm(s1(), Text.Nfc{})))
    IO.print(nc(Text.norm(s1(), Text.Fold{})))
    IO.print(nc(Text.norm(s2(), Text.Nfd{})))
    IO.print(nc(Text.norm(s2(), Text.Nfc{})))
    IO.print(nc(Text.norm(s2(), Text.Fold{})))
    IO.print(nc(Text.norm(s3(), Text.Nfd{})))
    IO.print(nc(Text.norm(s3(), Text.Nfc{})))
    IO.print(nc(Text.norm(s3(), Text.Fold{})))
    IO.print(nc(Text.norm(s4(), Text.Nfd{})))
    IO.print(nc(Text.norm(s4(), Text.Nfc{})))
    IO.print(nc(Text.norm(s4(), Text.Fold{})))
    IO.print(nc(Text.norm(s5(), Text.Nfd{})))
    IO.print(nc(Text.norm(s5(), Text.Nfc{})))
    IO.print(nc(Text.norm(s5(), Text.Fold{})))
    IO.print(nc(Text.norm(s6(), Text.Nfd{})))
    IO.print(nc(Text.norm(s6(), Text.Nfc{})))
    IO.print(nc(Text.norm(s6(), Text.Fold{})))
    IO.print(nc(Text.norm(s7(), Text.Nfd{})))
    IO.print(nc(Text.norm(s7(), Text.Nfc{})))
    IO.print(nc(Text.norm(s7(), Text.Fold{})))
    IO.print(nc(Text.norm(s8(), Text.Nfd{})))
    IO.print(nc(Text.norm(s8(), Text.Nfc{})))
    IO.print(nc(Text.norm(s8(), Text.Fold{})))
    IO.print(nc(Text.norm(s9(), Text.Nfd{})))
    IO.print(nc(Text.norm(s9(), Text.Nfc{})))
    IO.print(nc(Text.norm(s9(), Text.Fold{})))
    IO.print(nc(Text.norm(s10(), Text.Nfd{})))
    IO.print(nc(Text.norm(s10(), Text.Nfc{})))
    IO.print(nc(Text.norm(s10(), Text.Fold{})))
    IO.print(nc(Text.norm(s11(), Text.Nfd{})))
    IO.print(nc(Text.norm(s11(), Text.Nfc{})))
    IO.print(nc(Text.norm(s11(), Text.Fold{})))
    IO.print(nc(Text.norm(s12(), Text.Nfd{})))
    IO.print(nc(Text.norm(s12(), Text.Nfc{})))
    IO.print(nc(Text.norm(s12(), Text.Fold{})))
    IO.print(nc(Text.norm(s13(), Text.Nfd{})))
    IO.print(nc(Text.norm(s13(), Text.Nfc{})))
    IO.print(nc(Text.norm(s13(), Text.Fold{})))
    IO.print(nc(Text.norm(s14(), Text.Nfd{})))
    IO.print(nc(Text.norm(s14(), Text.Nfc{})))
    IO.print(nc(Text.norm(s14(), Text.Fold{})))
    IO.print(nc(Text.norm(s15(), Text.Nfd{})))
    IO.print(nc(Text.norm(s15(), Text.Nfc{})))
    IO.print(nc(Text.norm(s15(), Text.Fold{})))
    IO.print(nc(Text.norm(s16(), Text.Nfd{})))
    IO.print(nc(Text.norm(s16(), Text.Nfc{})))
    IO.print(nc(Text.norm(s16(), Text.Fold{})))
    IO.print(nc(Text.norm(s17(), Text.Nfd{})))
    IO.print(nc(Text.norm(s17(), Text.Nfc{})))
    IO.print(nc(Text.norm(s17(), Text.Fold{})))
    IO.print(nc(Text.norm(s18(), Text.Nfd{})))
    IO.print(nc(Text.norm(s18(), Text.Nfc{})))
    IO.print(nc(Text.norm(s18(), Text.Fold{})))
    IO.print(nc(Text.norm(s19(), Text.Nfd{})))
    IO.print(nc(Text.norm(s19(), Text.Nfc{})))
    IO.print(nc(Text.norm(s19(), Text.Fold{})))
    IO.print(nc(Text.norm(s20(), Text.Nfd{})))
    IO.print(nc(Text.norm(s20(), Text.Nfc{})))
    IO.print(nc(Text.norm(s20(), Text.Fold{})))
    IO.print(nc(Text.norm(s21(), Text.Nfd{})))
    IO.print(nc(Text.norm(s21(), Text.Nfc{})))
    IO.print(nc(Text.norm(s21(), Text.Fold{})))
    IO.print(nc(Text.norm(s22(), Text.Nfd{})))
    IO.print(nc(Text.norm(s22(), Text.Nfc{})))
    IO.print(nc(Text.norm(s22(), Text.Fold{})))
    IO.print(nc(Text.norm(s23(), Text.Nfd{})))
    IO.print(nc(Text.norm(s23(), Text.Nfc{})))
    IO.print(nc(Text.norm(s23(), Text.Fold{})))
    IO.print(nc(Text.norm(s24(), Text.Nfd{})))
    IO.print(nc(Text.norm(s24(), Text.Nfc{})))
    IO.print(nc(Text.norm(s24(), Text.Fold{})))
    IO.print(nc(Text.norm(s25(), Text.Nfd{})))
    IO.print(nc(Text.norm(s25(), Text.Nfc{})))
    IO.print(nc(Text.norm(s25(), Text.Fold{})))
    IO.print(dims(s1(), Text.Nfc{}))
    IO.print(dims(s2(), Text.Nfc{}))
    IO.print(dims(s3(), Text.Nfc{}))
    IO.print(dims(s4(), Text.Nfc{}))
    IO.print(dims(s5(), Text.Nfc{}))
    IO.print(dims(s6(), Text.Nfc{}))
    IO.print(rt(s1(), Text.Nfd{}, 0))
    IO.print(rt(s1(), Text.Nfc{}, 0))
    IO.print(rt(s1(), Text.Fold{}, 0))
    IO.print(rt(s2(), Text.Nfd{}, 7))
    IO.print(rt(s2(), Text.Nfc{}, 10))
    IO.print(rt(s2(), Text.Fold{}, 1))
    IO.print(rt(s3(), Text.Nfd{}, 2))
    IO.print(rt(s3(), Text.Nfc{}, 1))
    IO.print(rt(s3(), Text.Fold{}, 0))
    IO.print(rt(s4(), Text.Nfd{}, 0))
    IO.print(rt(s4(), Text.Nfc{}, 0))
    IO.print(rt(s4(), Text.Fold{}, 1))
    IO.print(rt(s5(), Text.Nfd{}, 3))
    IO.print(rt(s5(), Text.Nfc{}, 1))
    IO.print(rt(s5(), Text.Fold{}, 4))
    IO.print(rt(s6(), Text.Nfd{}, 0))
    IO.print(rt(s6(), Text.Nfc{}, 3))
    IO.print(rt(s6(), Text.Fold{}, 1))
    IO.print(rt(s7(), Text.Nfd{}, 2))
    IO.print(rt(s7(), Text.Nfc{}, 0))
    IO.print(rt(s7(), Text.Fold{}, 3))
    IO.print(rt(s8(), Text.Nfd{}, 4))
    IO.print(rt(s8(), Text.Nfc{}, 2))
    IO.print(rt(s8(), Text.Fold{}, 0))
    IO.print(rt(s9(), Text.Nfd{}, 1))
    IO.print(rt(s9(), Text.Nfc{}, 4))
    IO.print(rt(s9(), Text.Fold{}, 2))
    IO.print(rt(s10(), Text.Nfd{}, 3))
    IO.print(rt(s10(), Text.Nfc{}, 1))
    IO.print(rt(s10(), Text.Fold{}, 4))
    IO.print(rt(s11(), Text.Nfd{}, 0))
    IO.print(rt(s11(), Text.Nfc{}, 3))
    IO.print(rt(s11(), Text.Fold{}, 1))
    IO.print(rt(s12(), Text.Nfd{}, 7))
    IO.print(rt(s12(), Text.Nfc{}, 3))
    IO.print(rt(s12(), Text.Fold{}, 6))
    IO.print(rt(s13(), Text.Nfd{}, 0))
    IO.print(rt(s13(), Text.Nfc{}, 3))
    IO.print(rt(s13(), Text.Fold{}, 6))
    IO.print(rt(s14(), Text.Nfd{}, 1))
    IO.print(rt(s14(), Text.Nfc{}, 4))
    IO.print(rt(s14(), Text.Fold{}, 2))
    IO.print(rt(s15(), Text.Nfd{}, 8))
    IO.print(rt(s15(), Text.Nfc{}, 2))
    IO.print(rt(s15(), Text.Fold{}, 2))
    IO.print(rt(s16(), Text.Nfd{}, 6))
    IO.print(rt(s16(), Text.Nfc{}, 0))
    IO.print(rt(s16(), Text.Fold{}, 0))
    IO.print(rt(s17(), Text.Nfd{}, 7))
    IO.print(rt(s17(), Text.Nfc{}, 1))
    IO.print(rt(s17(), Text.Fold{}, 4))
    IO.print(rt(s18(), Text.Nfd{}, 5))
    IO.print(rt(s18(), Text.Nfc{}, 2))
    IO.print(rt(s18(), Text.Fold{}, 2))
    IO.print(rt(s19(), Text.Nfd{}, 0))
    IO.print(rt(s19(), Text.Nfc{}, 3))
    IO.print(rt(s19(), Text.Fold{}, 6))
    IO.print(rt(s20(), Text.Nfd{}, 1))
    IO.print(rt(s20(), Text.Nfc{}, 0))
    IO.print(rt(s20(), Text.Fold{}, 1))
    IO.print(rt(s21(), Text.Nfd{}, 8))
    IO.print(rt(s21(), Text.Nfc{}, 0))
    IO.print(rt(s21(), Text.Fold{}, 3))
    IO.print(rt(s22(), Text.Nfd{}, 3))
    IO.print(rt(s22(), Text.Nfc{}, 3))
    IO.print(rt(s22(), Text.Fold{}, 6))
    IO.print(rt(s23(), Text.Nfd{}, 1))
    IO.print(rt(s23(), Text.Nfc{}, 5))
    IO.print(rt(s23(), Text.Fold{}, 0))
    IO.print(rt(s24(), Text.Nfd{}, 0))
    IO.print(rt(s24(), Text.Nfc{}, 3))
    IO.print(rt(s24(), Text.Fold{}, 6))
    IO.print(rt(s25(), Text.Nfd{}, 8))
    IO.print(rt(s25(), Text.Nfc{}, 11))
    IO.print(rt(s25(), Text.Fold{}, 14))
    IO.print(rt(s2(), Text.Nfc{}, 0))
    IO.print(rt(s2(), Text.Nfc{}, 1))
    IO.print(rt(s2(), Text.Nfc{}, 2))
    IO.print(rt(s2(), Text.Nfc{}, 3))
    IO.print(rt(s2(), Text.Nfc{}, 4))
    IO.print(rt(s2(), Text.Nfc{}, 5))
    IO.print(rt(s2(), Text.Nfc{}, 6))
    IO.print(rt(s2(), Text.Nfc{}, 7))
    IO.print(rt(s2(), Text.Nfc{}, 8))
    IO.print(rt(s2(), Text.Nfc{}, 9))
    IO.print(rt(s2(), Text.Nfc{}, 10))
    IO.print(rt(s2(), Text.Nfc{}, 11))
    IO.print(sp(s1(), Text.Nfc{}, 7, 3, 0))
    IO.print(sp(s2(), Text.Nfc{}, 7, 3, 11))
    IO.print(sp(s3(), Text.Nfc{}, 7, 3, 1))
    IO.print(sp(s4(), Text.Nfc{}, 7, 3, 1))
#|<>
#|<72 105 >
#|<110 771 >
#|<8364 53 >
#|<128512 33 >
#|<44032 4520 >
#|<769 803 >
#|<>
#|<72 105 >
#|<110 771 >
#|<8364 53 >
#|<128512 33 >
#|<44032 4520 >
#|<769 803 >
#|<>
#|<72 105 >
#|<110 204 131 >
#|<226 130 172 53 >
#|<240 159 152 128 33 >
#|<234 176 128 225 134 168 >
#|<204 129 204 163 >
#|1
#|1
#|1
#|1
#|1
#|1
#|0
#|0
#|0
#|0
#|0
#|0
#|0
#|0
#|0
#|0
#|0
#|0
#|0
#|0
#|0
#|<0 >
#|<0 1 >
#|<0 1 2 3 >
#|<0 2 >
#|<0 1 2 >
#|<0 1 3 4 >
#|<0 1 3 4 >
#|<0 1 2 3 4 >
#|<0 3 >
#|<0 7 >
#|<0 2 >
#|<0 1 3 4 5 >
#|<0 3 4 >
#|<0 8 >
#|<0 8 12 >
#|<0 8 16 >
#|<0 1 9 10 >
#|<0 8 16 >
#|<0 18 >
#|<0 15 >
#|<0 7 8 >
#|<0 4 8 >
#|<0 7 >
#|<0 6 >
#|<0 3 6 >
#|<0 3 6 >
#|<0 4 8 >
#|<0 3 6 >
#|<0 9 >
#|<0 6 >
#|<0 6 >
#|<0 6 >
#|<0 3 6 >
#|<0 9 >
#|<0 9 12 >
#|<0 5 >
#|<0 4 >
#|<0 2 3 >
#|<0 3 4 7 >
#|<0 5 8 >
#|<0 3 11 13 19 >
#|<>
#|0 0
#|<65 >
#|<65 >
#|<97 >
#|<72 101 108 108 111 44 32 119 111 114 108 100 >
#|<72 101 108 108 111 44 32 119 111 114 108 100 >
#|<104 101 108 108 111 44 32 119 111 114 108 100 >
#|<101 769 >
#|<233 >
#|<233 >
#|<101 769 >
#|<233 >
#|<233 >
#|<101 803 769 >
#|<7865 769 >
#|<7865 769 >
#|<101 803 769 >
#|<7865 769 >
#|<7865 769 >
#|<101 803 769 >
#|<7865 769 >
#|<7865 769 >
#|<113 803 775 >
#|<113 803 775 >
#|<113 803 775 >
#|<100 803 775 >
#|<7693 775 >
#|<7693 775 >
#|<68 803 775 >
#|<7692 775 >
#|<7693 775 >
#|<65 769 66 67 807 >
#|<193 66 199 >
#|<225 98 231 >
#|<65 768 101 768 383 775 >
#|<192 232 7835 >
#|<224 232 7777 >
#|<83 84 82 65 83 83 69 >
#|<83 84 82 65 83 83 69 >
#|<115 116 114 97 115 115 101 >
#|<77 97 115 115 101 >
#|<77 97 115 115 101 >
#|<109 97 115 115 101 >
#|<4352 4449 4520 >
#|<44033 >
#|<44033 >
#|<4352 4449 4520 >
#|<44033 >
#|<44033 >
#|<4352 4449 4520 4352 4449 >
#|<44033 44032 >
#|<44033 44032 >
#|<383 803 775 >
#|<7835 803 >
#|<7785 >
#|<61 824 60 824 62 824 >
#|<8800 8814 8815 >
#|<8800 8814 8815 >
#|<168 769 >
#|<901 >
#|<901 >
#|<65 773 768 769 770 771 >
#|<65 773 768 769 770 771 >
#|<97 773 768 769 770 771 >
#|<97 790 768 769 98 >
#|<224 790 769 98 >
#|<224 790 769 98 >
#|<20013 25991 97 769 >
#|<20013 25991 225 >
#|<20013 25991 225 >
#|<128512 769 65 >
#|<128512 769 65 >
#|<128512 769 97 >
#|<67 97 102 101 769 32 20013 25991 32 4352 4449 >
#|<67 97 102 233 32 20013 25991 32 44032 >
#|<99 97 102 233 32 20013 25991 32 44032 >
#|1 1
#|12 12
#|2 1
#|2 1
#|5 1
#|5 1
#|1 <65 >
#|1 <65 >
#|1 <97 >
#|1 <119 >
#|1 <108 >
#|1 <101 >
#|1 <101 769 >
#|1 <233 >
#|1 <233 >
#|1 <101 769 >
#|1 <233 >
#|1 <233 >
#|1 <101 803 769 >
#|1 <7865 769 >
#|1 <7865 769 >
#|1 <101 803 769 >
#|1 <7865 769 >
#|1 <7865 769 >
#|1 <101 803 769 >
#|1 <7865 769 >
#|1 <7865 769 >
#|1 <113 803 775 >
#|1 <113 803 775 >
#|1 <113 803 775 >
#|1 <100 803 775 >
#|1 <7693 775 >
#|1 <7693 775 >
#|1 <68 803 775 >
#|1 <7692 775 >
#|1 <7693 775 >
#|1 <65 769 >
#|1 <199 >
#|1 <225 >
#|1 <383 775 >
#|1 <232 >
#|1 <7777 >
#|1 <83 >
#|1 <65 >
#|1 <101 >
#|1 <97 >
#|1 <101 >
#|1 <115 >
#|1 <4352 4449 4520 >
#|1 <44033 >
#|1 <44033 >
#|1 <4352 4449 4520 >
#|1 <44033 >
#|1 <44033 >
#|1 <4352 4449 4520 >
#|1 <44033 >
#|1 <44032 >
#|1 <383 803 775 >
#|1 <7835 803 >
#|1 <7785 >
#|1 <61 824 >
#|1 <8814 >
#|1 <8815 >
#|1 <168 769 >
#|1 <901 >
#|1 <901 >
#|1 <65 773 768 769 770 771 >
#|1 <65 773 768 769 770 771 >
#|1 <97 773 768 769 770 771 >
#|1 <97 790 768 769 >
#|1 <224 790 769 >
#|1 <98 >
#|1 <20013 >
#|1 <25991 >
#|1 <20013 >
#|1 <128512 769 >
#|1 <128512 769 >
#|1 <97 >
#|1 <20013 >
#|1 <25991 >
#|1 <44032 >
#|1 <72 >
#|1 <101 >
#|1 <108 >
#|1 <108 >
#|1 <111 >
#|1 <44 >
#|1 <32 >
#|1 <119 >
#|1 <111 >
#|1 <114 >
#|1 <108 >
#|1 <100 >
#|7:3:0-1
#|7:3:11-12
#|7:3:0-3
#|7:3:0-2
