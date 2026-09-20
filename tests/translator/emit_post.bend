# The T5 milestone: a fact crosses a call. `keyed` keys every item of its
# result and `one` keys its whole result; the kernel recomputes that from each
# body, mints it into the signature, and grants it at the call. `stems` and
# `head` then split on the key -- a guard no contract could discharge from
# their own text, since nothing in either body says the colon is there. The
# expected block is the emitted file plus its span map: drop one colon from
# either callee and the caller stops emitting (tests/translator/refuse.bend).
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
  show(Tr.translate("def stems(text: str) -> list[str]:\n    v = keyed(text)\n    return [s.split(':', 1)[1] for s in v]\n\ndef head(text: str) -> str:\n    k = one(text)\n    return k.split(':', 1)[1]\n\ndef keyed(text: str) -> list[str]:\n    return ['stem:' + s for s in text.split(',')]\n\ndef one(text: str) -> str:\n    return 'stem:' + text.strip()\n", Tr.contracts(), ""))
#|"# Faithful translation (tiers 1-2) of Python `keyed` 9:0-10:49, `stems` 1:0-3:42, `one` 12:0-13:33, `head` 5:0-7:29 by demos/python/translate.bend.\nimport Base\n\ndef Py.after(+s: String, +sep: String) -> String:\n  Pair.snd(String, String, Pair.snd(String, String & String, String.partition(s, sep)))\n\ndef keyed.comp_10_11(_xs: List<&2, String>) -> List<&2, String>:\n  match _xs:\n    case Nil{}:\n      []\n    case Con{s, _rest}:\n      String.append(\"stem:\", s) <> keyed.comp_10_11(_rest)\n\ndef keyed(text: String) -> List<&2, String>:\n  keyed.comp_10_11(String.split_on(text, \",\"))\n\ndef stems.comp_3_11(_xs: List<&2, String>) -> List<&2, String>:\n  match _xs:\n    case Nil{}:\n      []\n    case Con{s, _rest}:\n      Py.after(s, \":\") <> stems.comp_3_11(_rest)\n\ndef stems(text: String) -> List<&2, String>:\n  v = {keyed(text) : List<&2, String>}\n  stems.comp_3_11(v)\n\ndef one(text: String) -> String:\n  String.append(\"stem:\", String.trim(text))\n\ndef head(text: String) -> String:\n  k = {one(text) : String}\n  Py.after(k, \":\")\n\n# spans: emitted Bend <- Python source, node : type\n# 12:6-12:31 <- py 10:12-10:23 Prim String.append : String\n# 12:20-12:27 <- py 10:12-10:19 Lit \"stem:\" : String\n# 12:29-12:30 <- py 10:22-10:23 Var s : String\n# 14:10-14:22 <- py 9:10-9:19 Param text : String\n# 15:2-15:46 <- py 10:4-10:49 Return : List<&2, String>\n# 15:2-15:46 <- py 10:11-10:49 Map s : List<&2, String>\n# 15:19-15:45 <- py 10:33-10:48 Prim String.split_on : List<&2, String>\n# 15:35-15:39 <- py 10:33-10:37 Var text : String\n# 15:41-15:44 <- py 10:44-10:47 Lit \",\" : String\n# 22:6-22:22 <- py 3:12-3:30 Prim Py.after : String\n# 22:15-22:16 <- py 3:12-3:13 Var s : String\n# 22:18-22:21 <- py 3:20-3:23 Lit \":\" : String\n# 24:10-24:22 <- py 1:10-1:19 Param text : String\n# 25:2-25:38 <- py 2:4-2:19 Let v : List<&2, String>\n# 25:7-25:18 <- py 2:8-2:19 Call keyed : List<&2, String>\n# 25:13-25:17 <- py 2:14-2:18 Var text : String\n# 26:2-26:20 <- py 3:4-3:42 Return : List<&2, String>\n# 26:2-26:20 <- py 3:11-3:42 Map s : List<&2, String>\n# 26:18-26:19 <- py 3:40-3:41 Var v : List<&2, String>\n# 28:8-28:20 <- py 12:8-12:17 Param text : String\n# 29:2-29:43 <- py 13:4-13:33 Return : String\n# 29:2-29:43 <- py 13:11-13:33 Prim String.append : String\n# 29:16-29:23 <- py 13:11-13:18 Lit \"stem:\" : String\n# 29:25-29:42 <- py 13:21-13:33 Prim String.trim : String\n# 29:37-29:41 <- py 13:21-13:25 Var text : String\n# 31:9-31:21 <- py 5:9-5:18 Param text : String\n# 32:2-32:26 <- py 6:4-6:17 Let k : String\n# 32:7-32:16 <- py 6:8-6:17 Call one : String\n# 32:11-32:15 <- py 6:12-6:16 Var text : String\n# 33:2-33:18 <- py 7:4-7:29 Return : String\n# 33:2-33:18 <- py 7:11-7:29 Prim Py.after : String\n# 33:11-33:12 <- py 7:11-7:12 Var k : String\n# 33:14-33:17 <- py 7:19-7:22 Lit \":\" : String\n"
