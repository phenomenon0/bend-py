# The T1 milestone: `normalize_stem` (llm-wiki tools/wiki.py:92-94, verbatim)
# through lex -> parse -> elaborate -> verify -> emit. The expected block is the
# emitted file plus its span map; the judge compiles the same text.
import Base
import ../../demos/python/syntax.bend as S
import ../../demos/python/translate.bend as Tr

def show(r: Result<&2, &2, S.Error, String>) -> String:
  match r:
    case Done{s}:
      s
    case Fail{e}:
      S.error_text(e)

def main() -> String:
  show(Tr.translate("def normalize_stem(s: str) -> str:\n    \"\"\"Lowercase and replace spaces with hyphens.\"\"\"\n    return s.strip().lower().replace(\" \", \"-\")\n", Tr.contracts(), "normalize_stem"))
#|"# Faithful translation (tiers 1-2) of Python `normalize_stem` 1:0-3:46 by demos/python/translate.bend.\nimport Base\n\ndef normalize_stem(s: String) -> String:\n  String.replace(String.to_lower(String.trim(s)), \" \", \"-\")\n\n# spans: emitted Bend <- Python source, node : type\n# 4:19-4:28 <- py 1:19-1:25 Param s : String\n# 5:2-5:59 <- py 3:4-3:46 Return : String\n# 5:2-5:59 <- py 3:11-3:46 Prim String.replace : String\n# 5:17-5:48 <- py 3:11-3:28 Prim String.to_lower : String\n# 5:33-5:47 <- py 3:11-3:20 Prim String.trim : String\n# 5:45-5:46 <- py 3:11-3:12 Var s : String\n# 5:50-5:53 <- py 3:37-3:40 Lit \" \" : String\n# 5:55-5:58 <- py 3:42-3:45 Lit \"-\" : String\n"
