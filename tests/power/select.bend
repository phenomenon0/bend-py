# Select against a plain O(n^2) CPython greedy (select_gen.py prints this file).
# A row is "<why> <room> <total> <count> [item:gain:cost ...]": why the run
# stopped, the cost budget left, the objective reached, how many were picked,
# and every pick with the marginal gain it was taken for. The lazy greedy here
# and the full rescan there must agree item for item and gain for gain.
#
# The ground is computed, not tabulated: `sm`, `wt` and `ct` are the same
# integers select_gen.py computes, so a row pins the algebra and not a table.
# Row 44 of this file is the one that says why the primitive exists -- on a
# ground of one cluster, where every item is a near-duplicate, ranking by
# standalone score per cost takes 8 1 12 10 15 14 7 5 0 3 and this takes 8 1 12 10 7 5 11 15 14.
import Base
import ../../power/vec.bend as Vec
import ../../power/select.bend as Select

def h(+p: U32) -> U32:
  U32.xor(U32.mul(U32.inc(p), 2654435761), U32.shrn(p, 3n))

def mix(a: U32, b: U32) -> U32:
  h(U32.xor(U32.mul(a, 2654435761), b))

def cl(s: U32, nc: U32, i: U32) -> U32:
  U32.mod(U32.shrn(mix(U32.add(s, 17), i), 8n), nc)

def wt(s: U32, i: U32) -> U32:
  U32.add(1024, U32.mod(U32.shrn(mix(U32.add(s, 101), i), 7n), 3073))

# k scales every cost, and a row with k large is the regime where a real gain
# over a real cost floors to zero -- which is the only thing that can tell
# `ratio`'s floor at 1 from its absence
def ct(s: U32, i: U32, k: U32) -> U32:
  U32.mul(k, U32.add(1, U32.mod(U32.shrn(mix(U32.add(s, 211), i), 9n), 12)))

def sm.g(+g: U32, same: Bool) -> U32:
  match same:
    case True{}:
      U32.add(2600, U32.mod(g, 1200))
    case False{}:
      U32.mod(g, 700)

def sm.ne(+s: U32, +nc: U32, +j: U32, +i: U32) -> U32:
  sm.g(U32.shrn(mix(U32.add(U32.mul(s, 7), U32.mul(j, 65537)), i), 5n),
    U32.is_eq(cl(s, nc, j), cl(s, nc, i)))

def sm.if(s: U32, nc: U32, j: U32, i: U32, diag: Bool) -> U32:
  match diag:
    case True{}:
      4096
    case False{}:
      sm.ne(s, nc, j, i)

def sm(s: U32, nc: U32, +j: U32, +i: U32) -> U32:
  sm.if(s, nc, j, i, U32.is_eq(j, i))

# the n * n coverage rows, flat: cell p is row p / n, column p % n
def gs(fuel: Nat, +p: U32, +s: U32, +nc: U32, +n: U32, v: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      v
    case 1n++q:
      gs(q, U32.inc(p), s, nc, n, Vec.push(v, sm(s, nc, U32.div(p, n), U32.mod(p, n))))

def gv(fuel: Nat, +i: U32, +s: U32, v: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      v
    case 1n++q:
      gv(q, U32.inc(i), s, Vec.push(v, wt(s, i)))

def gc(fuel: Nat, +i: U32, +s: U32, +k: U32, v: Vec.Vec) -> Vec.Vec:
  match fuel:
    case 0n:
      v
    case 1n++q:
      gc(q, U32.inc(i), s, k, Vec.push(v, ct(s, i, k)))

def ground(+s: U32, +n: U32, nc: U32, k: U32) -> Select.Ground:
  Select.Ground{n, gs(U32.to_nat(U32.mul(n, n)), 0, s, nc, n, Vec.new(0)),
    gv(U32.to_nat(n), 0, s, Vec.new(0)), gc(U32.to_nat(n), 0, s, k, Vec.new(0))}

def pk(x: Select.Pick) -> String:
  match x:
    case Select.Pick{i, g, c}:
      U32.show(i) ++ ":" ++ U32.show(g) ++ ":" ++ U32.show(c)

def pks(xs: List<&2, Select.Pick>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{x, t}:
      Con{pk(x), pks(t)}

def out(+r: Select.Run) -> String:
  Select.show(Select.why(r)) ++ " " ++ U32.show(Select.room(r)) ++ " "
    ++ U32.show(Select.total(r)) ++ " " ++ U32.show(Select.count(r)) ++ " ["
    ++ String.join(pks(Select.chosen(r)), " ") ++ "]"

# the Ground comes back because the caller still owns it; this file is done
# with it and drops it
def line(x: Select.Ground & Select.Run) -> String:
  (g, r) = x
  out(r)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [], 0, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [], 1, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [], 2, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [], 4, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [], 7, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [], 11, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [], 16, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [], 23, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [], 32, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [], 48, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [], 70, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [], 100, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [], 150, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [0], 12, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [0], 40, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [0], 100, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [5], 12, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [5], 40, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [5], 100, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [11], 12, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [11], 40, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [11], 100, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [0, 5], 12, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [0, 5], 40, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [0, 5], 100, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [5, 0], 12, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [5, 0], 40, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [5, 0], 100, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [3, 7, 9], 12, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [3, 7, 9], 40, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [3, 7, 9], 100, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [12], 100, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [3, 3], 100, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [1, 4, 6, 8], 6, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [5], 0, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [], 0, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [], 1, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [], 40, 0)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [5], 40, 0)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [7, 2], 40, 0)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 1), [12], 40, 0)))
    IO.print(line(Select.budgeted(ground(2, 16, 1, 1), [], 10, 292)))
    IO.print(line(Select.budgeted(ground(2, 16, 1, 1), [], 25, 292)))
    IO.print(line(Select.budgeted(ground(2, 16, 1, 1), [], 50, 292)))
    IO.print(line(Select.budgeted(ground(2, 16, 1, 1), [], 90, 292)))
    IO.print(line(Select.budgeted(ground(3, 16, 16, 1), [], 10, 292)))
    IO.print(line(Select.budgeted(ground(3, 16, 16, 1), [], 25, 292)))
    IO.print(line(Select.budgeted(ground(3, 16, 16, 1), [], 50, 292)))
    IO.print(line(Select.budgeted(ground(3, 16, 16, 1), [], 90, 292)))
    IO.print(line(Select.budgeted(ground(4, 20, 4, 1), [], 8, 444)))
    IO.print(line(Select.budgeted(ground(4, 20, 4, 1), [], 20, 444)))
    IO.print(line(Select.budgeted(ground(4, 20, 4, 1), [], 40, 444)))
    IO.print(line(Select.budgeted(ground(4, 20, 4, 1), [], 70, 444)))
    IO.print(line(Select.budgeted(ground(4, 20, 4, 1), [], 120, 444)))
    IO.print(line(Select.budgeted(ground(4, 20, 4, 1), [1, 13], 20, 444)))
    IO.print(line(Select.budgeted(ground(4, 20, 4, 1), [1, 13], 60, 444)))
    IO.print(line(Select.budgeted(ground(4, 20, 4, 1), [1, 13], 120, 444)))
    IO.print(line(Select.budgeted(ground(4, 20, 4, 1), [19], 20, 444)))
    IO.print(line(Select.budgeted(ground(4, 20, 4, 1), [19], 60, 444)))
    IO.print(line(Select.budgeted(ground(4, 20, 4, 1), [19], 120, 444)))
    IO.print(line(Select.budgeted(ground(5, 24, 6, 1), [], 10, 628)))
    IO.print(line(Select.budgeted(ground(5, 24, 6, 1), [], 30, 628)))
    IO.print(line(Select.budgeted(ground(5, 24, 6, 1), [], 60, 628)))
    IO.print(line(Select.budgeted(ground(5, 24, 6, 1), [], 100, 628)))
    IO.print(line(Select.budgeted(ground(5, 24, 6, 1), [], 160, 628)))
    IO.print(line(Select.budgeted(ground(5, 24, 6, 1), [0, 23], 60, 628)))
    IO.print(line(Select.budgeted(ground(5, 24, 6, 1), [11], 160, 628)))
    IO.print(line(Select.budgeted(ground(6, 14, 2, 1), [], 6, 228)))
    IO.print(line(Select.budgeted(ground(6, 14, 2, 1), [], 18, 228)))
    IO.print(line(Select.budgeted(ground(6, 14, 2, 1), [], 44, 228)))
    IO.print(line(Select.budgeted(ground(6, 14, 2, 1), [], 90, 228)))
    IO.print(line(Select.budgeted(ground(7, 14, 7, 1), [], 6, 228)))
    IO.print(line(Select.budgeted(ground(7, 14, 7, 1), [], 18, 228)))
    IO.print(line(Select.budgeted(ground(7, 14, 7, 1), [], 44, 228)))
    IO.print(line(Select.budgeted(ground(7, 14, 7, 1), [], 90, 228)))
    IO.print(line(Select.budgeted(ground(8, 1, 1, 1), [], 0, 7)))
    IO.print(line(Select.budgeted(ground(8, 1, 1, 1), [], 1, 7)))
    IO.print(line(Select.budgeted(ground(8, 1, 1, 1), [], 3, 7)))
    IO.print(line(Select.budgeted(ground(8, 1, 1, 1), [], 12, 7)))
    IO.print(line(Select.budgeted(ground(8, 1, 1, 1), [], 60, 7)))
    IO.print(line(Select.budgeted(ground(8, 2, 1, 1), [], 0, 12)))
    IO.print(line(Select.budgeted(ground(8, 2, 1, 1), [], 1, 12)))
    IO.print(line(Select.budgeted(ground(8, 2, 1, 1), [], 3, 12)))
    IO.print(line(Select.budgeted(ground(8, 2, 1, 1), [], 12, 12)))
    IO.print(line(Select.budgeted(ground(8, 2, 1, 1), [], 60, 12)))
    IO.print(line(Select.budgeted(ground(8, 3, 1, 1), [], 0, 19)))
    IO.print(line(Select.budgeted(ground(8, 3, 1, 1), [], 1, 19)))
    IO.print(line(Select.budgeted(ground(8, 3, 1, 1), [], 3, 19)))
    IO.print(line(Select.budgeted(ground(8, 3, 1, 1), [], 12, 19)))
    IO.print(line(Select.budgeted(ground(8, 3, 1, 1), [], 60, 19)))
    IO.print(line(Select.budgeted(ground(8, 1, 1, 1), [0], 60, 7)))
    IO.print(line(Select.budgeted(ground(8, 2, 1, 1), [1], 60, 12)))
    IO.print(line(Select.budgeted(ground(8, 3, 2, 1), [2, 0], 60, 19)))
    IO.print(line(Select.budgeted(ground(5, 24, 6, 4096), [], 900000, 628)))
    IO.print(line(Select.budgeted(ground(5, 24, 6, 4096), [], 300000, 628)))
    IO.print(line(Select.budgeted(ground(5, 24, 6, 4096), [], 60000, 628)))
    IO.print(line(Select.budgeted(ground(2, 16, 1, 8192), [], 700000, 292)))
    IO.print(line(Select.budgeted(ground(2, 16, 1, 8192), [], 200000, 292)))
    IO.print(line(Select.budgeted(ground(5, 24, 6, 4096), [3, 17], 900000, 628)))
    IO.print(line(Select.budgeted(ground(2, 16, 1, 8192), [0], 700000, 292)))
    IO.print(line(Select.budgeted(ground(3, 16, 16, 4096), [], 500000, 292)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 4096), [], 40000, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 4096), [], 4096, 172)))
    IO.print(line(Select.budgeted(ground(1, 12, 3, 4096), [], 4095, 172)))
#|full 0 0 0 []
#|full 0 14876 1 [9:14876:1]
#|full 1 14876 1 [9:14876:1]
#|full 0 17789 2 [9:14876:1 11:2913:3]
#|full 1 27495 2 [9:14876:1 7:12619:5]
#|full 2 29750 3 [9:14876:1 7:12619:5 11:2255:3]
#|full 1 31551 4 [9:14876:1 7:12619:5 11:2255:3 0:1801:6]
#|full 2 32112 5 [9:14876:1 7:12619:5 11:2255:3 0:1801:6 1:561:6]
#|full 1 33024 6 [9:14876:1 7:12619:5 11:2255:3 0:1801:6 1:561:6 4:912:10]
#|full 3 33956 8 [9:14876:1 7:12619:5 11:2255:3 0:1801:6 1:561:6 4:912:10 5:638:7 2:294:7]
#|full 3 34884 10 [9:14876:1 7:12619:5 11:2255:3 0:1801:6 1:561:6 4:912:10 5:638:7 6:617:12 2:294:7 10:311:10]
#|full 9 35460 12 [9:14876:1 7:12619:5 11:2255:3 0:1801:6 1:561:6 4:912:10 5:638:7 6:617:12 2:294:7 10:311:10 3:305:12 8:271:12]
#|full 59 35460 12 [9:14876:1 7:12619:5 11:2255:3 0:1801:6 1:561:6 4:912:10 5:638:7 6:617:12 2:294:7 10:311:10 3:305:12 8:271:12]
#|full 2 30658 3 [0:16236:6 9:12237:1 11:2185:3]
#|full 2 33662 7 [0:16236:6 9:12237:1 11:2185:3 7:893:5 1:561:6 4:912:10 5:638:7]
#|full 9 35460 12 [0:16236:6 9:12237:1 11:2185:3 7:893:5 1:561:6 4:912:10 5:638:7 6:617:12 2:294:7 10:311:10 3:305:12 8:271:12]
#|full 0 27825 2 [5:15745:7 7:12080:5]
#|full 2 33661 7 [5:15745:7 7:12080:5 9:900:1 11:1662:3 0:1801:6 1:561:6 4:912:10]
#|full 9 35459 12 [5:15745:7 7:12080:5 9:900:1 11:1662:3 0:1801:6 1:561:6 4:912:10 6:617:12 2:294:7 10:311:10 3:305:12 8:271:12]
#|full 3 29749 3 [11:15528:3 7:12774:5 9:1447:1]
#|full 2 33661 7 [11:15528:3 7:12774:5 9:1447:1 0:1801:6 1:561:6 4:912:10 5:638:7]
#|full 9 35459 12 [11:15528:3 7:12774:5 9:1447:1 0:1801:6 1:561:6 4:912:10 5:638:7 6:617:12 2:294:7 10:311:10 3:305:12 8:271:12]
#|over 6 16236 1 [0:16236:6]
#|full 2 33662 7 [0:16236:6 5:12587:7 9:881:1 11:1592:3 7:893:5 1:561:6 4:912:10]
#|full 9 35460 12 [0:16236:6 5:12587:7 9:881:1 11:1592:3 7:893:5 1:561:6 4:912:10 6:617:12 2:294:7 10:311:10 3:305:12 8:271:12]
#|over 5 15745 1 [5:15745:7]
#|full 2 33661 7 [5:15745:7 0:13077:6 9:881:1 11:1592:3 7:893:5 1:561:6 4:912:10]
#|full 9 35459 12 [5:15745:7 0:13077:6 9:881:1 11:1592:3 7:893:5 1:561:6 4:912:10 6:617:12 2:294:7 10:311:10 3:305:12 8:271:12]
#|over 0 15562 1 [3:15562:12]
#|full 3 33262 6 [3:15562:12 7:1684:5 9:11796:1 11:2255:3 0:1053:6 4:912:10]
#|full 9 35458 12 [3:15562:12 7:1684:5 9:11796:1 11:2255:3 0:1053:6 4:912:10 5:638:7 1:372:6 2:294:7 10:311:10 6:310:12 8:271:12]
#|bad 100 0 0 []
#|bad 88 15562 1 [3:15562:12]
#|over 0 15113 1 [1:15113:6]
#|over 0 0 0 []
#|full 0 0 0 []
#|full 0 14876 1 [9:14876:1]
#|dry 40 0 0 []
#|dry 33 15745 1 [5:15745:7]
#|dry 28 16110 2 [7:15349:5 2:761:7]
#|bad 40 0 0 []
#|full 2 39339 3 [8:34742:2 1:3229:3 12:1368:3]
#|full 1 41471 6 [8:34742:2 1:3229:3 12:1368:3 10:895:4 7:634:5 5:603:7]
#|full 6 42500 9 [8:34742:2 1:3229:3 12:1368:3 10:895:4 7:634:5 5:603:7 11:657:11 15:177:4 14:195:5]
#|full 0 43763 14 [8:34742:2 1:3229:3 12:1368:3 10:895:4 7:634:5 5:603:7 11:657:11 15:177:4 14:195:5 3:319:9 13:316:10 0:237:8 6:255:10 2:136:9]
#|full 0 17415 3 [14:6447:1 5:5240:2 9:5728:7]
#|full 0 26926 5 [14:6447:1 5:5240:2 9:5728:7 3:5156:8 13:4355:7]
#|full 1 37183 10 [14:6447:1 5:5240:2 9:5728:7 3:5156:8 13:4355:7 7:1827:3 6:2284:4 1:2723:6 10:2109:6 15:1314:5]
#|full 6 39935 15 [14:6447:1 5:5240:2 9:5728:7 3:5156:8 13:4355:7 7:1827:3 6:2284:4 1:2723:6 10:2109:6 15:1314:5 2:842:5 0:633:7 11:620:9 8:418:8 4:239:6]
#|full 2 38926 3 [5:13538:1 19:14486:2 14:10902:3]
#|full 0 50281 6 [5:13538:1 19:14486:2 14:10902:3 18:8557:5 0:1638:5 17:1160:4]
#|full 4 53148 9 [5:13538:1 19:14486:2 14:10902:3 18:8557:5 0:1638:5 17:1160:4 13:1282:6 16:1168:7 2:417:3]
#|full 1 55952 13 [5:13538:1 19:14486:2 14:10902:3 18:8557:5 0:1638:5 17:1160:4 13:1282:6 16:1168:7 2:417:3 6:1381:10 12:754:10 9:400:7 1:269:6]
#|full 1 57959 18 [5:13538:1 19:14486:2 14:10902:3 18:8557:5 0:1638:5 17:1160:4 13:1282:6 16:1168:7 2:417:3 6:1381:10 12:754:10 9:400:7 11:483:9 1:269:6 4:506:12 3:268:7 15:424:12 8:326:10]
#|full 0 48056 5 [1:15099:6 13:15043:6 5:8524:1 18:8491:5 19:899:2]
#|full 1 55203 12 [1:15099:6 13:15043:6 5:8524:1 18:8491:5 14:1380:3 19:899:2 0:1638:5 17:763:4 16:1168:7 2:417:3 6:1381:10 9:400:7]
#|full 1 57964 18 [1:15099:6 13:15043:6 5:8524:1 18:8491:5 14:1380:3 19:899:2 0:1638:5 17:763:4 16:1168:7 2:417:3 6:1381:10 12:754:10 9:400:7 11:483:9 4:506:12 3:268:7 15:424:12 8:326:10]
#|full 0 50284 6 [19:18180:2 5:9847:1 14:10902:3 18:8557:5 0:1638:5 17:1160:4]
#|full 4 55286 11 [19:18180:2 5:9847:1 14:10902:3 18:8557:5 0:1638:5 17:1160:4 13:1282:6 16:1168:7 2:417:3 6:1381:10 12:754:10]
#|full 1 57962 18 [19:18180:2 5:9847:1 14:10902:3 18:8557:5 0:1638:5 17:1160:4 13:1282:6 16:1168:7 2:417:3 6:1381:10 12:754:10 9:400:7 11:483:9 1:269:6 4:506:12 3:268:7 15:424:12 8:326:10]
#|full 1 43315 4 [19:16437:1 13:13963:2 20:8021:2 18:4894:4]
#|full 1 52147 7 [19:16437:1 13:13963:2 20:8021:2 18:4894:4 1:5331:5 0:2432:8 21:1069:7]
#|full 1 55157 12 [19:16437:1 13:13963:2 20:8021:2 18:4894:4 1:5331:5 0:2432:8 21:1069:7 14:1002:7 17:841:8 6:520:5 12:418:5 23:229:5]
#|full 0 57499 16 [19:16437:1 13:13963:2 20:8021:2 18:4894:4 1:5331:5 0:2432:8 21:1069:7 14:1002:7 17:841:8 6:520:5 12:418:5 11:550:8 10:682:11 2:610:10 4:562:12 23:167:5]
#|full 8 58874 21 [19:16437:1 13:13963:2 20:8021:2 18:4894:4 1:5331:5 0:2432:8 21:1069:7 14:1002:7 17:841:8 6:520:5 12:418:5 11:550:8 10:682:11 2:610:10 4:562:12 8:360:10 23:167:5 16:297:11 22:296:12 3:170:7 5:252:12]
#|full 1 55157 12 [0:20869:8 23:1554:5 19:10619:1 20:7497:2 18:4691:4 1:5331:5 13:746:2 21:1069:7 14:1002:7 17:841:8 6:520:5 12:418:5]
#|full 8 58871 21 [11:16930:8 13:13912:2 20:7843:2 18:5114:4 1:5392:5 19:514:1 0:2432:8 21:1069:7 17:841:8 6:520:5 12:418:5 14:490:7 10:682:11 2:610:10 4:562:12 8:360:10 23:167:5 16:297:11 22:296:12 3:170:7 5:252:12]
#|full 1 32358 2 [4:17963:2 9:14395:3]
#|full 1 36597 5 [4:17963:2 9:14395:3 5:2625:5 6:1011:4 12:603:3]
#|full 0 38701 9 [4:17963:2 9:14395:3 5:2625:5 6:1011:4 12:603:3 13:880:6 7:504:7 8:243:4 0:477:10]
#|full 7 39836 13 [4:17963:2 9:14395:3 5:2625:5 6:1011:4 12:603:3 13:880:6 7:504:7 8:243:4 0:477:10 11:383:9 3:381:11 10:209:9 1:162:10]
#|full 0 15807 3 [5:9622:1 6:5408:2 7:777:3]
#|full 0 25866 5 [5:9622:1 6:5408:2 4:4478:4 3:5581:8 7:777:3]
#|full 5 34718 8 [5:9622:1 6:5408:2 4:4478:4 3:5581:8 12:5075:9 11:3402:9 7:677:3 9:475:3]
#|full 3 38053 13 [5:9622:1 6:5408:2 4:4478:4 3:5581:8 12:5075:9 11:3402:9 7:677:3 9:475:3 8:1044:10 1:872:9 10:900:12 2:245:7 13:274:10]
#|full 0 0 0 []
#|full 1 0 0 []
#|full 3 0 0 []
#|full 2 3540 1 [0:3540:10]
#|full 50 3540 1 [0:3540:10]
#|full 0 0 0 []
#|full 1 0 0 []
#|full 3 0 0 []
#|full 5 6765 1 [1:6765:7]
#|full 43 7447 2 [1:6765:7 0:682:10]
#|full 0 0 0 []
#|full 1 0 0 []
#|full 3 0 0 []
#|full 1 9989 2 [2:9591:4 1:398:7]
#|full 39 10672 3 [2:9591:4 0:685:10 1:396:7]
#|full 50 3540 1 [0:3540:10]
#|full 43 7447 2 [1:6765:7 0:682:10]
#|full 39 10671 3 [2:4109:4 0:5893:10 1:669:7]
#|full 150432 59420 24 [19:16437:4096 13:13963:8192 20:8021:8192 18:4894:16384 1:5331:20480 0:2432:32768 21:1069:28672 11:1062:32768 6:520:20480 17:841:32768 12:418:20480 14:490:28672 2:610:40960 10:682:45056 4:562:49152 8:360:40960 23:167:20480 3:170:28672 5:252:49152 7:201:40960 9:180:40960 15:165:45056 16:297:45056 22:296:49152]
#|full 5088 56088 13 [19:16437:4096 13:13963:8192 20:8021:8192 18:4894:16384 1:5331:20480 0:2432:32768 21:1069:28672 11:1062:32768 6:520:20480 17:841:32768 12:418:20480 14:490:28672 2:610:40960]
#|full 2656 48646 5 [19:16437:4096 13:13963:8192 20:8021:8192 18:4894:16384 1:5331:20480]
#|full 28256 43151 12 [8:34742:16384 1:3229:24576 10:1803:32768 7:901:40960 5:613:57344 0:237:65536 2:136:73728 3:348:73728 4:271:98304 6:478:81920 9:206:81920 12:187:24576]
#|full 3392 41475 6 [8:34742:16384 1:3229:24576 10:1803:32768 7:901:40960 5:613:57344 12:187:24576]
#|full 150432 59421 24 [3:19167:28672 17:2611:32768 19:11025:4096 20:7887:8192 18:4839:16384 1:5238:20480 21:1069:28672 0:1096:32768 11:1062:32768 13:227:8192 6:520:20480 12:418:20480 14:490:28672 2:610:40960 10:682:45056 4:562:49152 8:360:40960 23:167:20480 5:252:49152 7:201:40960 9:180:40960 15:165:45056 16:297:45056 22:296:49152]
#|full 28256 43155 12 [0:36878:65536 1:2019:24576 12:1004:24576 8:545:16384 10:459:32768 3:645:73728 2:136:73728 4:271:98304 5:209:57344 6:478:81920 7:305:40960 9:206:81920]
#|full 106784 40411 16 [14:6447:4096 5:5240:8192 9:5728:28672 3:5156:32768 0:4308:28672 7:1809:12288 6:2284:16384 1:2705:24576 10:2109:24576 15:1314:20480 2:842:20480 13:716:28672 11:620:36864 8:418:32768 4:239:24576 12:476:49152]
#|full 3136 29750 3 [9:14876:4096 7:12619:20480 11:2255:12288]
#|full 0 14876 1 [9:14876:4096]
#|full 4095 0 0 []
