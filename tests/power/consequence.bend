# Consequence against CPython's own dict (consequence_gen.py prints this file).
# A row is "<k>: <reps> | <cnts>": how many distinct consequences N readings
# have, the lowest-numbered reading standing for each, and how many readings
# each one speaks for. Bend groups by a 32-bit digest of each preview trace and
# CPython groups by tuple equality, so a row matches only when the two agree on
# which readings are the same reading. A "y" row is `settled`: every reading
# does the same thing, so there is no question to ask.
import Base
import ../../power/vec.bend as Vec
import ../../power/radix.bend as Radix
import ../../power/consequence.bend as Conseq

def shows(xs: List<&2, U32>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{x, t}:
      Con{U32.show(x), shows(t)}

def text(r: Vec.Vec & List<&2, U32>) -> String:
  (v, xs) = r
  String.join(shows(xs), " ")

def line(v: Vec.Vec) -> String:
  text(Vec.to_list(v))

def vec(xs: List<&2, U32>) -> Vec.Vec:
  Vec.from_list(xs, Vec.new(0))

# the groups come back ascending by digest, which is this implementation's
# business; sorting them by representative is what makes the row an oracle's
def grp.fin(k: U32, r: Vec.Vec & Vec.Vec) -> String:
  (reps, cnts) = r
  U32.show(k) ++ ": " ++ line(reps) ++ " | " ++ line(cnts)

def grp.n(rc: Vec.Vec & Vec.Vec, k: U32) -> String:
  (reps, cnts) = rc
  grp.fin(k, Radix.sort_by_key(reps, cnts))

def grp.cnt(r: Conseq.Groups & U32) -> String:
  (g, k) = r
  grp.n(Conseq.representatives(g), k)

def grp(g: Conseq.Groups) -> String:
  grp.cnt(Conseq.count(g))

def yn.say(b: Bool) -> String:
  match b:
    case True{}:
      "y"
    case False{}:
      "n"

def yn(r: Conseq.Groups & Bool) -> String:
  (g, b) = r
  yn.say(b)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([1, 2, 3, 1, 2, 3, 1, 2, 3]), vec([3, 3, 3]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([1, 2, 3, 1, 2, 3, 1, 2, 3]), vec([3, 3, 3])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([1, 2, 3, 1, 2, 4, 1, 2, 3]), vec([3, 3, 3]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([1, 2, 3, 1, 2, 4, 1, 2, 3]), vec([3, 3, 3])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([1, 2, 3, 4]), vec([1, 1, 1, 1]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([1, 2, 3, 4]), vec([1, 1, 1, 1])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([7, 7, 7, 7, 7, 7, 7, 7]), vec([1, 1, 1, 1, 1, 1, 1, 1]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([7, 7, 7, 7, 7, 7, 7, 7]), vec([1, 1, 1, 1, 1, 1, 1, 1])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([1, 2, 2, 1]), vec([2, 2]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([1, 2, 2, 1]), vec([2, 2])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([1, 2, 3, 3, 2, 1, 1, 2, 3]), vec([3, 3, 3]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([1, 2, 3, 3, 2, 1, 1, 2, 3]), vec([3, 3, 3])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([1, 1, 2, 1, 2, 1, 2, 1, 1]), vec([3, 3, 3]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([1, 1, 2, 1, 2, 1, 2, 1, 1]), vec([3, 3, 3])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([1, 2, 1, 2, 3]), vec([2, 3]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([1, 2, 1, 2, 3]), vec([2, 3])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([1, 2, 3, 2, 3]), vec([3, 2]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([1, 2, 3, 2, 3]), vec([3, 2])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([1, 2, 3, 1, 2, 3, 1, 2, 3]), vec([3, 6]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([1, 2, 3, 1, 2, 3, 1, 2, 3]), vec([3, 6])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([5, 5, 5, 5, 5, 5]), vec([2, 1, 3]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([5, 5, 5, 5, 5, 5]), vec([2, 1, 3])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([]), vec([0]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([]), vec([0])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([]), vec([0, 0]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([]), vec([0, 0])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([1]), vec([0, 1]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([1]), vec([0, 1])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([1, 1]), vec([1, 0, 1, 0]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([1, 1]), vec([1, 0, 1, 0])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([1, 2, 1, 2]), vec([0, 0, 2, 2, 0]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([1, 2, 1, 2]), vec([0, 0, 2, 2, 0])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([1, 2]), vec([2, 0]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([1, 2]), vec([2, 0])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([1, 2]), vec([0, 1, 0, 1, 0]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([1, 2]), vec([0, 1, 0, 1, 0])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([]), vec([]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([]), vec([])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([1]), vec([1]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([1]), vec([1])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]), vec([12]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]), vec([12])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([1, 2, 3]), vec([3, 0]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([1, 2, 3]), vec([3, 0])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([1, 2]), vec([1, 1, 0]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([1, 2]), vec([1, 1, 0])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([1, 2, 3]), vec([0, 3]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([1, 2, 3]), vec([0, 3])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([1, 1, 1]), vec([2, 1]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([1, 1, 1]), vec([2, 1])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([1, 1, 1, 1, 1, 1, 1, 1, 1, 1]), vec([4, 2, 4]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([1, 1, 1, 1, 1, 1, 1, 1, 1, 1]), vec([4, 2, 4])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([0, 0, 0, 0, 0, 0]), vec([1, 2, 3]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([0, 0, 0, 0, 0, 0]), vec([1, 2, 3])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([0]), vec([1, 0]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([0]), vec([1, 0])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([255, 256, 65535, 65536, 16777215, 16777216]), vec([1, 1, 1, 1, 1, 1]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([255, 256, 65535, 65536, 16777215, 16777216]), vec([1, 1, 1, 1, 1, 1])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([4294967295, 0, 4294967295]), vec([1, 1, 1]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([4294967295, 0, 4294967295]), vec([1, 1, 1])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([2147483648, 2147483647]), vec([1, 1]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([2147483648, 2147483647]), vec([1, 1])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([9, 41, 46, 9, 9, 41, 46, 41, 46]), vec([1, 2, 1, 1, 2, 2]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([9, 41, 46, 9, 9, 41, 46, 41, 46]), vec([1, 2, 1, 1, 2, 2])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([8, 5, 13, 28, 12, 32, 31, 36, 28, 12, 32, 31, 36, 8, 5, 13, 32, 31, 36, 8, 5, 13, 33, 31, 8, 5, 13]), vec([3, 2, 3, 2, 3, 3, 3, 3, 2, 3]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([8, 5, 13, 28, 12, 32, 31, 36, 28, 12, 32, 31, 36, 8, 5, 13, 32, 31, 36, 8, 5, 13, 33, 31, 8, 5, 13]), vec([3, 2, 3, 2, 3, 3, 3, 3, 2, 3])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([39, 5, 44, 20, 29, 37, 39, 5, 44, 20, 44, 12, 13, 29, 37, 29, 37, 19, 29, 37, 19, 12, 13, 19, 19, 29, 37, 44, 19]), vec([4, 2, 4, 1, 2, 2, 2, 1, 2, 1, 2, 1, 1, 2, 1, 1]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([39, 5, 44, 20, 29, 37, 39, 5, 44, 20, 44, 12, 13, 29, 37, 29, 37, 19, 29, 37, 19, 12, 13, 19, 19, 29, 37, 44, 19]), vec([4, 2, 4, 1, 2, 2, 2, 1, 2, 1, 2, 1, 1, 2, 1, 1])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([31, 47, 47, 47, 47, 19, 41, 37, 47, 47, 19, 41, 37, 31, 31, 19, 41, 37, 19, 41, 37, 47, 47, 47, 47, 19, 41, 37, 19, 41, 37, 31]), vec([1, 2, 0, 2, 3, 0, 0, 2, 3, 0, 1, 1, 0, 0, 3, 3, 2, 0, 0, 2, 3, 0, 3, 1]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([31, 47, 47, 47, 47, 19, 41, 37, 47, 47, 19, 41, 37, 31, 31, 19, 41, 37, 19, 41, 37, 47, 47, 47, 47, 19, 41, 37, 19, 41, 37, 31]), vec([1, 2, 0, 2, 3, 0, 0, 2, 3, 0, 1, 1, 0, 0, 3, 3, 2, 0, 0, 2, 3, 0, 3, 1])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([6, 40, 19, 15, 12, 1, 4, 32, 20, 1, 47, 40, 21, 4, 43, 5, 12, 1, 6, 40, 19, 15, 22, 48, 18, 10, 30, 17, 12, 1, 18, 10, 30, 17, 40, 21, 4, 43, 5, 40, 21, 4, 43, 5, 4, 32, 20, 1, 47, 22, 48, 4, 32, 20, 1, 47, 4, 32, 20, 1, 47, 22, 48, 12, 1, 24, 46, 6, 6, 2, 40, 21, 4, 43, 5, 12, 1, 18, 10, 30, 17, 4, 32, 20, 1, 47, 40, 21, 4, 43, 5, 18, 10, 30, 17, 22, 48, 24, 46, 6, 6, 2, 24, 46, 6, 6, 2, 24, 46, 6, 6, 2, 4, 32, 20, 1, 47, 40, 21, 4, 43, 5, 18, 10, 30, 17]), vec([4, 2, 5, 5, 2, 4, 2, 4, 2, 4, 5, 5, 5, 2, 5, 5, 2, 2, 5, 5, 2, 4, 5, 5, 4, 2, 5, 5, 5, 5, 5, 4]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([6, 40, 19, 15, 12, 1, 4, 32, 20, 1, 47, 40, 21, 4, 43, 5, 12, 1, 6, 40, 19, 15, 22, 48, 18, 10, 30, 17, 12, 1, 18, 10, 30, 17, 40, 21, 4, 43, 5, 40, 21, 4, 43, 5, 4, 32, 20, 1, 47, 22, 48, 4, 32, 20, 1, 47, 4, 32, 20, 1, 47, 22, 48, 12, 1, 24, 46, 6, 6, 2, 40, 21, 4, 43, 5, 12, 1, 18, 10, 30, 17, 4, 32, 20, 1, 47, 40, 21, 4, 43, 5, 18, 10, 30, 17, 22, 48, 24, 46, 6, 6, 2, 24, 46, 6, 6, 2, 24, 46, 6, 6, 2, 4, 32, 20, 1, 47, 40, 21, 4, 43, 5, 18, 10, 30, 17]), vec([4, 2, 5, 5, 2, 4, 2, 4, 2, 4, 5, 5, 5, 2, 5, 5, 2, 2, 5, 5, 2, 4, 5, 5, 4, 2, 5, 5, 5, 5, 5, 4])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([0, 0, 1, 7919, 2, 15838, 3, 23757, 4, 31676, 5, 39595, 6, 47514, 7, 55433, 8, 63352, 9, 71271, 10, 79190, 11, 87109, 12, 95028, 13, 102947, 14, 110866, 15, 118785, 16, 126704, 17, 134623, 18, 142542, 19, 150461]), vec([2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([0, 0, 1, 7919, 2, 15838, 3, 23757, 4, 31676, 5, 39595, 6, 47514, 7, 55433, 8, 63352, 9, 71271, 10, 79190, 11, 87109, 12, 95028, 13, 102947, 14, 110866, 15, 118785, 16, 126704, 17, 134623, 18, 142542, 19, 150461]), vec([2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2])))))
    IO.print(grp(Conseq.collapse_traces(2166136261, vec([3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5]), vec([5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5]))))
    IO.print(yn(Conseq.settled(Conseq.collapse_traces(2166136261, vec([3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5, 3, 1, 4, 1, 5]), vec([5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5])))))
#|1: 0 | 3
#|y
#|2: 0 1 | 2 1
#|n
#|4: 0 1 2 3 | 1 1 1 1
#|n
#|1: 0 | 8
#|y
#|2: 0 1 | 1 1
#|n
#|2: 0 1 | 2 1
#|n
#|3: 0 1 2 | 1 1 1
#|n
#|2: 0 1 | 1 1
#|n
#|2: 0 1 | 1 1
#|n
#|2: 0 1 | 1 1
#|n
#|3: 0 1 2 | 1 1 1
#|n
#|1: 0 | 1
#|y
#|1: 0 | 2
#|y
#|2: 0 1 | 1 1
#|n
#|2: 0 1 | 2 2
#|n
#|2: 0 2 | 3 2
#|n
#|2: 0 1 | 1 1
#|n
#|3: 0 1 3 | 3 1 1
#|n
#|0:  | 
#|n
#|1: 0 | 1
#|y
#|1: 0 | 1
#|y
#|2: 0 1 | 1 1
#|n
#|3: 0 1 2 | 1 1 1
#|n
#|2: 0 1 | 1 1
#|n
#|2: 0 1 | 1 1
#|n
#|2: 0 1 | 2 1
#|n
#|3: 0 1 2 | 1 1 1
#|n
#|2: 0 1 | 1 1
#|n
#|6: 0 1 2 3 4 5 | 1 1 1 1 1 1
#|n
#|2: 0 1 | 2 1
#|n
#|2: 0 1 | 1 1
#|n
#|2: 0 1 | 3 3
#|n
#|4: 0 1 2 8 | 4 2 3 1
#|n
#|5: 0 1 3 4 7 | 2 5 2 2 5
#|n
#|4: 0 1 2 4 | 4 5 9 6
#|n
#|7: 0 1 2 3 6 7 18 | 2 5 6 6 4 5 4
#|n
#|20: 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 | 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1
#|n
#|1: 0 | 20
#|y
