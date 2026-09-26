# knn against plain CPython lists and floats (knn_gen.py prints this file). Every
# row is a U32: a distance is shown as Knn.key of it, which is that float's
# exact 32-bit pattern, so a row pins the arithmetic to the last bit and no
# decimal printer sits between the answer and the check.
import Base
import ../../power/heap.bend as Heap
import ../../power/knn.bend as Knn

# the store the rows build: cell p is a hash into [-32, 32) in steps of 1/128,
# an integer under 2^24 cast to F32 and divided by a power of two, so both steps
# are exact and the fixture pins the arithmetic and not the decimal parser
def h(+p: U32) -> U32:
  U32.xor(U32.mul(U32.inc(p), 2654435761), U32.shrn(p, 3n))

def v(+p: U32) -> F32:
  F32.div(F32.sub(U32.to_f32(U32.shrn(h(p), 19n)), 4096.0), 128.0)

def mk.go(fuel: Nat, +p: U32, f: Knn.Flat) -> Knn.Flat:
  match fuel:
    case 0n:
      f
    case 1n++q:
      mk.go(q, U32.inc(p), Knn.push(f, v(p)))

def mk(+base: U32, +n: U32, +d: U32) -> Knn.Flat:
  mk.go(U32.to_nat(U32.mul(n, d)), base, Knn.new(d))

def zeros.go(fuel: Nat, f: Knn.Flat) -> Knn.Flat:
  match fuel:
    case 0n:
      f
    case 1n++q:
      zeros.go(q, Knn.push(f, 0.0))

def zeros(+n: U32, +d: U32) -> Knn.Flat:
  zeros.go(U32.to_nat(U32.mul(n, d)), Knn.new(d))

def u(+x: U32) -> String:
  U32.show(x)

def sz(r: Knn.Flat & U32) -> String:
  (f, n) = r
  U32.show(n)

def n1(r: Knn.Flat & F32) -> String:
  (f, x) = r
  U32.show(Knn.key(x))

def d2(r: Knn.Flat & Knn.Flat & F32) -> String:
  (f, q, x) = r
  U32.show(Knn.key(x))

def ents(xs: List<&2, Heap.Entry>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{Heap.Entry{k, val}, t}:
      Con{U32.show(val) ++ ":" ++ U32.show(k), ents(t)}

def res(r: Knn.Flat & Knn.Flat & List<&2, Heap.Entry>) -> String:
  (f, q, xs) = r
  String.join(ents(xs), " ")

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(u(Knn.key(F32.neg(32.0))))
    IO.print(u(Knn.key(F32.neg(1.5))))
    IO.print(u(Knn.key(F32.neg(0.125))))
    IO.print(u(Knn.key(F32.neg(0.0))))
    IO.print(u(Knn.key(0.0)))
    IO.print(u(Knn.key(0.125)))
    IO.print(u(Knn.key(1.5)))
    IO.print(u(Knn.key(32.0)))
    IO.print(u(Knn.key(4096.0)))
    IO.print(u(Knn.near(0.0)))
    IO.print(u(Knn.near(0.125)))
    IO.print(u(Knn.near(1.5)))
    IO.print(u(Knn.near(32.0)))
    IO.print(u(Knn.near(4096.0)))
    IO.print(sz(Knn.size(mk(0, 12, 8))))
    IO.print(sz(Knn.dim(mk(0, 12, 8))))
    IO.print(n1(Knn.at(mk(0, 12, 8), 0, 0)))
    IO.print(n1(Knn.at(mk(0, 12, 8), 0, 7)))
    IO.print(n1(Knn.at(mk(0, 12, 8), 1, 3)))
    IO.print(n1(Knn.at(mk(0, 12, 8), 6, 4)))
    IO.print(n1(Knn.at(mk(0, 12, 8), 11, 0)))
    IO.print(n1(Knn.at(mk(0, 12, 8), 11, 7)))
    IO.print(d2(Knn.l2(mk(0, 12, 8), 0, mk(1000000, 5, 8), 0)))
    IO.print(d2(Knn.ip(mk(0, 12, 8), 0, mk(1000000, 5, 8), 0)))
    IO.print(d2(Knn.l2(mk(0, 12, 8), 1, mk(1000000, 5, 8), 0)))
    IO.print(d2(Knn.ip(mk(0, 12, 8), 1, mk(1000000, 5, 8), 0)))
    IO.print(d2(Knn.l2(mk(0, 12, 8), 2, mk(1000000, 5, 8), 0)))
    IO.print(d2(Knn.ip(mk(0, 12, 8), 2, mk(1000000, 5, 8), 0)))
    IO.print(d2(Knn.l2(mk(0, 12, 8), 3, mk(1000000, 5, 8), 0)))
    IO.print(d2(Knn.ip(mk(0, 12, 8), 3, mk(1000000, 5, 8), 0)))
    IO.print(d2(Knn.l2(mk(0, 12, 8), 4, mk(1000000, 5, 8), 0)))
    IO.print(d2(Knn.ip(mk(0, 12, 8), 4, mk(1000000, 5, 8), 0)))
    IO.print(d2(Knn.l2(mk(0, 12, 8), 5, mk(1000000, 5, 8), 0)))
    IO.print(d2(Knn.ip(mk(0, 12, 8), 5, mk(1000000, 5, 8), 0)))
    IO.print(d2(Knn.l2(mk(0, 12, 8), 6, mk(1000000, 5, 8), 0)))
    IO.print(d2(Knn.ip(mk(0, 12, 8), 6, mk(1000000, 5, 8), 0)))
    IO.print(d2(Knn.l2(mk(0, 12, 8), 7, mk(1000000, 5, 8), 0)))
    IO.print(d2(Knn.ip(mk(0, 12, 8), 7, mk(1000000, 5, 8), 0)))
    IO.print(d2(Knn.l2(mk(0, 12, 8), 8, mk(1000000, 5, 8), 0)))
    IO.print(d2(Knn.ip(mk(0, 12, 8), 8, mk(1000000, 5, 8), 0)))
    IO.print(d2(Knn.l2(mk(0, 12, 8), 9, mk(1000000, 5, 8), 0)))
    IO.print(d2(Knn.ip(mk(0, 12, 8), 9, mk(1000000, 5, 8), 0)))
    IO.print(d2(Knn.l2(mk(0, 12, 8), 10, mk(1000000, 5, 8), 0)))
    IO.print(d2(Knn.ip(mk(0, 12, 8), 10, mk(1000000, 5, 8), 0)))
    IO.print(d2(Knn.l2(mk(0, 12, 8), 11, mk(1000000, 5, 8), 0)))
    IO.print(d2(Knn.ip(mk(0, 12, 8), 11, mk(1000000, 5, 8), 0)))
    IO.print(d2(Knn.l2(mk(0, 12, 8), 0, mk(1000000, 5, 8), 1)))
    IO.print(d2(Knn.ip(mk(0, 12, 8), 0, mk(1000000, 5, 8), 1)))
    IO.print(d2(Knn.l2(mk(0, 12, 8), 5, mk(1000000, 5, 8), 1)))
    IO.print(d2(Knn.ip(mk(0, 12, 8), 5, mk(1000000, 5, 8), 1)))
    IO.print(d2(Knn.l2(mk(0, 12, 8), 11, mk(1000000, 5, 8), 1)))
    IO.print(d2(Knn.ip(mk(0, 12, 8), 11, mk(1000000, 5, 8), 1)))
    IO.print(d2(Knn.l2(mk(0, 12, 8), 0, mk(1000000, 5, 8), 2)))
    IO.print(d2(Knn.ip(mk(0, 12, 8), 0, mk(1000000, 5, 8), 2)))
    IO.print(d2(Knn.l2(mk(0, 12, 8), 5, mk(1000000, 5, 8), 2)))
    IO.print(d2(Knn.ip(mk(0, 12, 8), 5, mk(1000000, 5, 8), 2)))
    IO.print(d2(Knn.l2(mk(0, 12, 8), 11, mk(1000000, 5, 8), 2)))
    IO.print(d2(Knn.ip(mk(0, 12, 8), 11, mk(1000000, 5, 8), 2)))
    IO.print(d2(Knn.l2(mk(0, 12, 8), 0, mk(1000000, 5, 8), 3)))
    IO.print(d2(Knn.ip(mk(0, 12, 8), 0, mk(1000000, 5, 8), 3)))
    IO.print(d2(Knn.l2(mk(0, 12, 8), 5, mk(1000000, 5, 8), 3)))
    IO.print(d2(Knn.ip(mk(0, 12, 8), 5, mk(1000000, 5, 8), 3)))
    IO.print(d2(Knn.l2(mk(0, 12, 8), 11, mk(1000000, 5, 8), 3)))
    IO.print(d2(Knn.ip(mk(0, 12, 8), 11, mk(1000000, 5, 8), 3)))
    IO.print(d2(Knn.l2(mk(0, 12, 8), 0, mk(1000000, 5, 8), 4)))
    IO.print(d2(Knn.ip(mk(0, 12, 8), 0, mk(1000000, 5, 8), 4)))
    IO.print(d2(Knn.l2(mk(0, 12, 8), 5, mk(1000000, 5, 8), 4)))
    IO.print(d2(Knn.ip(mk(0, 12, 8), 5, mk(1000000, 5, 8), 4)))
    IO.print(d2(Knn.l2(mk(0, 12, 8), 11, mk(1000000, 5, 8), 4)))
    IO.print(d2(Knn.ip(mk(0, 12, 8), 11, mk(1000000, 5, 8), 4)))
    IO.print(d2(Knn.l2(mk(0, 12, 8), 3, mk(0, 12, 8), 3)))
    IO.print(n1(Knn.norm(mk(0, 12, 8), 0)))
    IO.print(n1(Knn.norm(mk(0, 12, 8), 1)))
    IO.print(n1(Knn.norm(mk(0, 12, 8), 2)))
    IO.print(n1(Knn.norm(mk(0, 12, 8), 3)))
    IO.print(n1(Knn.norm(mk(0, 12, 8), 4)))
    IO.print(n1(Knn.norm(mk(0, 12, 8), 5)))
    IO.print(n1(Knn.norm(mk(0, 12, 8), 6)))
    IO.print(n1(Knn.norm(mk(0, 12, 8), 7)))
    IO.print(n1(Knn.norm(mk(0, 12, 8), 8)))
    IO.print(n1(Knn.norm(mk(0, 12, 8), 9)))
    IO.print(n1(Knn.norm(mk(0, 12, 8), 10)))
    IO.print(n1(Knn.norm(mk(0, 12, 8), 11)))
    IO.print(n1(Knn.norm(Knn.normalize(mk(0, 12, 8)), 0)))
    IO.print(n1(Knn.norm(Knn.normalize(mk(0, 12, 8)), 1)))
    IO.print(n1(Knn.norm(Knn.normalize(mk(0, 12, 8)), 2)))
    IO.print(n1(Knn.norm(Knn.normalize(mk(0, 12, 8)), 3)))
    IO.print(n1(Knn.norm(Knn.normalize(mk(0, 12, 8)), 4)))
    IO.print(n1(Knn.norm(Knn.normalize(mk(0, 12, 8)), 5)))
    IO.print(n1(Knn.norm(Knn.normalize(mk(0, 12, 8)), 6)))
    IO.print(n1(Knn.norm(Knn.normalize(mk(0, 12, 8)), 7)))
    IO.print(n1(Knn.norm(Knn.normalize(mk(0, 12, 8)), 8)))
    IO.print(n1(Knn.norm(Knn.normalize(mk(0, 12, 8)), 9)))
    IO.print(n1(Knn.norm(Knn.normalize(mk(0, 12, 8)), 10)))
    IO.print(n1(Knn.norm(Knn.normalize(mk(0, 12, 8)), 11)))
    IO.print(d2(Knn.ip(Knn.normalize(mk(0, 12, 8)), 0, Knn.normalize(mk(1000000, 5, 8)), 0)))
    IO.print(d2(Knn.ip(Knn.normalize(mk(0, 12, 8)), 0, Knn.normalize(mk(1000000, 5, 8)), 1)))
    IO.print(d2(Knn.ip(Knn.normalize(mk(0, 12, 8)), 0, Knn.normalize(mk(1000000, 5, 8)), 2)))
    IO.print(d2(Knn.ip(Knn.normalize(mk(0, 12, 8)), 0, Knn.normalize(mk(1000000, 5, 8)), 3)))
    IO.print(d2(Knn.ip(Knn.normalize(mk(0, 12, 8)), 0, Knn.normalize(mk(1000000, 5, 8)), 4)))
    IO.print(n1(Knn.norm(Knn.normalize(zeros(3, 8)), 1)))
    IO.print(d2(Knn.ip(Knn.normalize(zeros(3, 8)), 1, mk(1000000, 5, 8), 0)))
    IO.print(res(Knn.search_l2(mk(0, 12, 8), mk(1000000, 5, 8), 0, 1)))
    IO.print(res(Knn.search_ip(mk(0, 12, 8), mk(1000000, 5, 8), 0, 1)))
    IO.print(res(Knn.search_l2(mk(0, 12, 8), mk(1000000, 5, 8), 0, 3)))
    IO.print(res(Knn.search_ip(mk(0, 12, 8), mk(1000000, 5, 8), 0, 3)))
    IO.print(res(Knn.search_l2(mk(0, 12, 8), mk(1000000, 5, 8), 0, 12)))
    IO.print(res(Knn.search_ip(mk(0, 12, 8), mk(1000000, 5, 8), 0, 12)))
    IO.print(res(Knn.search_l2(mk(0, 12, 8), mk(1000000, 5, 8), 0, 20)))
    IO.print(res(Knn.search_ip(mk(0, 12, 8), mk(1000000, 5, 8), 0, 20)))
    IO.print(res(Knn.search_l2(mk(0, 12, 8), mk(1000000, 5, 8), 1, 1)))
    IO.print(res(Knn.search_ip(mk(0, 12, 8), mk(1000000, 5, 8), 1, 1)))
    IO.print(res(Knn.search_l2(mk(0, 12, 8), mk(1000000, 5, 8), 1, 3)))
    IO.print(res(Knn.search_ip(mk(0, 12, 8), mk(1000000, 5, 8), 1, 3)))
    IO.print(res(Knn.search_l2(mk(0, 12, 8), mk(1000000, 5, 8), 1, 12)))
    IO.print(res(Knn.search_ip(mk(0, 12, 8), mk(1000000, 5, 8), 1, 12)))
    IO.print(res(Knn.search_l2(mk(0, 12, 8), mk(1000000, 5, 8), 1, 20)))
    IO.print(res(Knn.search_ip(mk(0, 12, 8), mk(1000000, 5, 8), 1, 20)))
    IO.print(res(Knn.search_l2(mk(0, 12, 8), mk(1000000, 5, 8), 2, 1)))
    IO.print(res(Knn.search_ip(mk(0, 12, 8), mk(1000000, 5, 8), 2, 1)))
    IO.print(res(Knn.search_l2(mk(0, 12, 8), mk(1000000, 5, 8), 2, 3)))
    IO.print(res(Knn.search_ip(mk(0, 12, 8), mk(1000000, 5, 8), 2, 3)))
    IO.print(res(Knn.search_l2(mk(0, 12, 8), mk(1000000, 5, 8), 2, 12)))
    IO.print(res(Knn.search_ip(mk(0, 12, 8), mk(1000000, 5, 8), 2, 12)))
    IO.print(res(Knn.search_l2(mk(0, 12, 8), mk(1000000, 5, 8), 2, 20)))
    IO.print(res(Knn.search_ip(mk(0, 12, 8), mk(1000000, 5, 8), 2, 20)))
    IO.print(res(Knn.search_l2(mk(0, 12, 8), mk(1000000, 5, 8), 3, 1)))
    IO.print(res(Knn.search_ip(mk(0, 12, 8), mk(1000000, 5, 8), 3, 1)))
    IO.print(res(Knn.search_l2(mk(0, 12, 8), mk(1000000, 5, 8), 3, 3)))
    IO.print(res(Knn.search_ip(mk(0, 12, 8), mk(1000000, 5, 8), 3, 3)))
    IO.print(res(Knn.search_l2(mk(0, 12, 8), mk(1000000, 5, 8), 3, 12)))
    IO.print(res(Knn.search_ip(mk(0, 12, 8), mk(1000000, 5, 8), 3, 12)))
    IO.print(res(Knn.search_l2(mk(0, 12, 8), mk(1000000, 5, 8), 3, 20)))
    IO.print(res(Knn.search_ip(mk(0, 12, 8), mk(1000000, 5, 8), 3, 20)))
    IO.print(res(Knn.search_l2(mk(0, 12, 8), mk(1000000, 5, 8), 4, 1)))
    IO.print(res(Knn.search_ip(mk(0, 12, 8), mk(1000000, 5, 8), 4, 1)))
    IO.print(res(Knn.search_l2(mk(0, 12, 8), mk(1000000, 5, 8), 4, 3)))
    IO.print(res(Knn.search_ip(mk(0, 12, 8), mk(1000000, 5, 8), 4, 3)))
    IO.print(res(Knn.search_l2(mk(0, 12, 8), mk(1000000, 5, 8), 4, 12)))
    IO.print(res(Knn.search_ip(mk(0, 12, 8), mk(1000000, 5, 8), 4, 12)))
    IO.print(res(Knn.search_l2(mk(0, 12, 8), mk(1000000, 5, 8), 4, 20)))
    IO.print(res(Knn.search_ip(mk(0, 12, 8), mk(1000000, 5, 8), 4, 20)))
    IO.print(res(Knn.search_ip(Knn.normalize(mk(0, 12, 8)), Knn.normalize(mk(1000000, 5, 8)), 0, 4)))
    IO.print(res(Knn.search_ip(Knn.normalize(mk(0, 12, 8)), Knn.normalize(mk(1000000, 5, 8)), 1, 4)))
    IO.print(res(Knn.search_ip(Knn.normalize(mk(0, 12, 8)), Knn.normalize(mk(1000000, 5, 8)), 2, 4)))
    IO.print(res(Knn.search_ip(Knn.normalize(mk(0, 12, 8)), Knn.normalize(mk(1000000, 5, 8)), 3, 4)))
    IO.print(res(Knn.search_ip(Knn.normalize(mk(0, 12, 8)), Knn.normalize(mk(1000000, 5, 8)), 4, 4)))
    IO.print(res(Knn.search_l2(mk(0, 12, 8), mk(1000000, 5, 8), 0, 0)))
    IO.print(res(Knn.search_l2(mk(0, 1, 8), mk(1000000, 5, 8), 2, 4)))
    IO.print(res(Knn.search_l2(mk(0, 12, 1), mk(1000000, 5, 1), 1, 3)))
    IO.print(res(Knn.search_ip(zeros(5, 8), mk(1000000, 5, 8), 0, 3)))
#|1040187391
#|1077936127
#|1107296255
#|2147483648
#|2147483648
#|3187671040
#|3217031168
#|3254779904
#|3313500160
#|2147483647
#|1107296255
#|1077936127
#|1040187391
#|981467135
#|12
#|8
#|3237052416
#|3252908032
#|1062518783
#|3246583808
#|1040355327
#|1054023679
#|3233169408
#|3307549835
#|3261903760
#|3307415344
#|3311498929
#|3293789784
#|3311516607
#|3293253353
#|3312366280
#|3292719748
#|3317711970
#|1010674095
#|3321034672
#|996907863
#|3320839408
#|996640581
#|3321062976
#|996372845
#|3321893328
#|994725212
#|3321953928
#|994457475
#|3322222510
#|994190363
#|3273379196
#|3307317464
#|3317805740
#|1010524309
#|3321953838
#|995415152
#|3311403025
#|3293885688
#|3311517237
#|3294336679
#|3321702280
#|995871263
#|3311815240
#|3292955236
#|3311501014
#|3294263102
#|3321062366
#|997098079
#|3317707458
#|1012133767
#|3261926064
#|3307957789
#|3318773748
#|1006682257
#|2147483648
#|3259903045
#|3259872013
#|3259916017
#|3259759719
#|3260120596
#|3260112328
#|3260175963
#|3259769668
#|3259881686
#|3259895479
#|3259879731
#|3260372739
#|3212836864
#|3212836864
#|3212836863
#|3212836864
#|3212836864
#|3212836864
#|3212836864
#|3212836863
#|3212836864
#|3212836863
#|3212836864
#|3212836864
#|3212818944
#|3212346414
#|3198473639
#|3197777504
#|1107225589
#|2147483648
#|2147483648
#|0:1061797887
#|0:3307549835
#|0:1061797887 1:1033063535 2:983468366
#|0:3307549835 1:3307415344 2:3293789784
#|0:1061797887 1:1033063535 2:983468366 3:983450688 4:982601015 5:977255325 7:974127887 6:973932623 8:973904319 9:973073967 10:973013367 11:972744785
#|0:3307549835 1:3307415344 2:3293789784 3:3293253353 4:3292719748 5:1010674095 6:996907863 7:996640581 8:996372845 9:994725212 10:994457475 11:994190363
#|0:1061797887 1:1033063535 2:983468366 3:983450688 4:982601015 5:977255325 7:974127887 6:973932623 8:973904319 9:973073967 10:973013367 11:972744785
#|0:3307549835 1:3307415344 2:3293789784 3:3293253353 4:3292719748 5:1010674095 6:996907863 7:996640581 8:996372845 9:994725212 10:994457475 11:994190363
#|1:1061631231
#|1:3307599757
#|1:1061631231 0:1021588099 3:983466281
#|1:3307599757 0:3307317464 4:3294720548
#|1:1061631231 0:1021588099 3:983466281 4:983451319 2:982650161 5:977161555 8:974126107 7:973932547 6:973320157 10:973073419 11:973013457 9:972925456
#|1:3307599757 0:3307317464 4:3294720548 3:3293584732 2:3292453569 5:1010524309 8:996966516 7:996400000 6:995833027 11:995415152 10:994847781 9:994281265
#|1:1061631231 0:1021588099 3:983466281 4:983451319 2:982650161 5:977161555 8:974126107 7:973932547 6:973320157 10:973073419 11:973013457 9:972925456
#|1:3307599757 0:3307317464 4:3294720548 3:3293584732 2:3292453569 5:1010524309 8:996966516 7:996400000 6:995833027 11:995415152 10:994847781 9:994281265
#|2:1061797887
#|2:3307546763
#|2:1061797887 3:1033052383 4:1013041775
#|2:3307546763 3:3307311880 4:3307076568
#|2:1061797887 3:1033052383 4:1013041775 0:983564270 5:983450058 1:983143208 7:977256829 6:977163931 8:976932943 9:974125839 10:973904319 11:973265015
#|2:3307546763 3:3307311880 4:3307076568 5:3294336679 0:3293885688 1:3292943710 6:1010252071 7:1008364011 8:1006561735 9:996811028 10:996342653 11:995871263
#|2:1061797887 3:1033052383 4:1013041775 0:983564270 5:983450058 1:983143208 7:977256829 6:977163931 8:976932943 9:974125839 10:973904319 11:973265015
#|2:3307546763 3:3307311880 4:3307076568 5:3294336679 0:3293885688 1:3292943710 6:1010252071 7:1008364011 8:1006561735 9:996811028 10:996342653 11:995871263
#|3:1061631231
#|4:3307576983
#|3:1061631231 4:1033074687 2:1021583583
#|4:3307576983 3:3307394825 2:3307212696
#|3:1061631231 4:1033074687 2:1021583583 1:983564790 5:983466281 0:983152055 8:977256955 7:977163601 6:976653463 10:974126879 9:973931157 11:973904929
#|4:3307576983 3:3307394825 2:3307212696 5:3294263102 1:3293680851 0:3292955236 8:1008870567 7:1007406139 6:1006294615 11:997098079 10:996734759 9:996368652
#|3:1061631231 4:1033074687 2:1021583583 1:983564790 5:983466281 0:983152055 8:977256955 7:977163601 6:976653463 10:974126879 9:973931157 11:973904929
#|4:3307576983 3:3307394825 2:3307212696 5:3294263102 1:3293680851 0:3292955236 8:1008870567 7:1007406139 6:1006294615 11:997098079 10:996734759 9:996368652
#|5:1033041231
#|5:3307957789
#|5:1033041231 2:983564271 6:983468365
#|5:3307957789 6:3296027256 2:3295372800
#|5:1033041231 2:983564271 6:983468365 7:983453522 3:983143491 8:982601015 4:981886175 0:977259837 9:977256829 1:976948302 10:976932943 11:976193547
#|5:3307957789 6:3296027256 2:3295372800 7:3294681951 3:3294030165 8:3293335731 4:3292681276 0:1012133767 9:1012060979 1:1009441779 10:1009368543 11:1006682257
#|5:1033041231 2:983564271 6:983468365 7:983453522 3:983143491 8:982601015 4:981886175 0:977259837 9:977256829 1:976948302 10:976932943 11:976193547
#|5:3307957789 6:3296027256 2:3295372800 7:3294681951 3:3294030165 8:3293335731 4:3292681276 0:1012133767 9:1012060979 1:1009441779 10:1009368543 11:1006682257
#|0:3212818944 1:3212648862 2:3198375592 3:3198081118
#|1:3212818868 0:3212346414 4:3198847620 3:3198266934
#|2:3212819127 3:3212647129 4:3211852199 5:3198653029
#|3:3212818366 4:3212656394 2:3212341990 5:3198623876
#|5:3212658730 6:3199496140 2:3199232933 7:3198835988
#|
#|0:983564270
#|1:1086963711 9:1058240511 6:1037097455
#|4:2147483648 3:2147483648 2:2147483648
