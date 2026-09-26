# The deflate laws as a specimen: the check lane loads power/deflate_proof.bend
# with everything it imports and fails on any hole or open law, so every law of
# power/deflate_laws.bend is a gate of this runner like any other row. The other
# lanes run the row below: a stored stream and a fixed one, written and read back.
import Base
import ../../power/deflate.bend as D
import ../../power/deflate_proof.bend as Proof

def same(r: Result<&2, &2, D.Why, Bytes()>) -> String:
  match r:
    case Done{b}:
      Bool.pick(String, String.eq(b, "stored and fixed, back as they were"), "read back", "not read back")
    case Fail{why}:
      "refused: " ++ D.why.show(why)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(same(D.inflate(1000n, D.deflate("stored and fixed, back as they were", 0n))))
    IO.print(same(D.inflate(1000n, D.deflate_fixed("stored and fixed, back as they were", 6n))))
#|read back
#|read back
