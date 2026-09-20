import Base
import ../../demos/python/intake.bend as I
import ../../demos/python/syntax.bend as S

def main() -> Bool:
  +initial = {I.Decoder{0, 0, 0, ""} : I.Decoder}
  good = Result.is_done(&2, &2, S.Error, I.Decoder, I.decode([65, 240, 159, 152, 128], initial))
  bad = Result.is_fail(&2, &2, S.Error, I.Decoder, I.decode([237, 160, 128], initial))
  good && bad

#|True{}
