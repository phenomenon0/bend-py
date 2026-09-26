# The csv laws as a specimen: the check lane loads power/csv_proof.bend with
# everything it imports and fails on any hole or open law, so the nine laws of
# power/csv_laws.bend are a gate of this runner like any other row. The other
# lanes run the one row below: a document read, and the grammar's reading of it.
import Base
import ../../power/csv.bend as Csv
import ../../power/csv_spec.bend as Spec
import ../../power/csv_proof.bend as Proof

def same(a: Csv.Out, b: Csv.Out) -> String:
  match a b:
    case Csv.Read{h, r} Csv.Read{i, s}:
      "read, as the grammar reads it"
    case _ _:
      "not read"

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(same(Csv.read(Csv.rfc(), "a,\"b\r\n\"\"\"\r\n"),
      Spec.parse(Bytes.to_list("a,\"b\r\n\"\"\"\r\n"), Csv.rfc())))
#|read, as the grammar reads it
