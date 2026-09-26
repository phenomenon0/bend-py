# The join: an `if` whose arms fall through binds one name on both paths, and
# the statements after it run once. `if c: x = a else: x = b` is
# `x = (a if c else b)`; an arm with no statement for x keeps x as bound
# before. The expected block is the emitted file plus its span map.
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
  show(Tr.translate("def label(s: str, loud: bool) -> str:\n    if loud:\n        t = s.strip().replace(\" \", \"!\")\n    else:\n        t = s.lower()\n    u = t + \".\"\n    if \"x\" in u:\n        u = u.replace(\"x\", \"y\")\n    return u\n", Tr.contracts(), "label"))
#|"# Faithful translation (tiers 1-2) of Python `label` 1:0-9:12 by demos/python/translate.bend.\nimport Base\n\ndef label.if_2_4(_c: Bool, s: String) -> String:\n  match _c:\n    case True{}:\n      String.replace(String.trim(s), \" \", \"!\")\n    case False{}:\n      String.to_lower(s)\n\ndef label.if_7_4(_c: Bool, u: String) -> String:\n  match _c:\n    case True{}:\n      String.replace(u, \"x\", \"y\")\n    case False{}:\n      u\n\ndef label(s: String, loud: Bool) -> String:\n  t = {label.if_2_4(loud, s) : String}\n  +u = {String.append(t, \".\") : String}\n  u = {label.if_7_4(String.contains(u, \"x\"), u) : String}\n  u\n\n# spans: emitted Bend <- Python source, node : type\n# 7:6-7:46 <- py 3:12-3:39 Prim String.replace : String\n# 7:21-7:35 <- py 3:12-3:21 Prim String.trim : String\n# 7:33-7:34 <- py 3:12-3:13 Var s : String\n# 7:37-7:40 <- py 3:30-3:33 Lit \" \" : String\n# 7:42-7:45 <- py 3:35-3:38 Lit \"!\" : String\n# 9:6-9:24 <- py 5:12-5:21 Prim String.to_lower : String\n# 9:22-9:23 <- py 5:12-5:13 Var s : String\n# 14:6-14:33 <- py 8:12-8:31 Prim String.replace : String\n# 14:21-14:22 <- py 8:12-8:13 Var u : String\n# 14:24-14:27 <- py 8:22-8:25 Lit \"x\" : String\n# 14:29-14:32 <- py 8:27-8:30 Lit \"y\" : String\n# 16:6-16:7 <- py 7:4-8:31 Var u : String\n# 18:10-18:19 <- py 1:10-1:16 Param s : String\n# 18:21-18:31 <- py 1:18-1:28 Param loud : Bool\n# 19:2-19:38 <- py 2:4-5:21 Let t : String\n# 19:7-19:28 <- py 2:4-5:21 Branch if : String\n# 19:20-19:24 <- py 2:7-2:11 Var loud : Bool\n# 20:2-20:39 <- py 6:4-6:15 Let u : String\n# 20:8-20:29 <- py 6:8-6:15 Prim String.append : String\n# 20:22-20:23 <- py 6:8-6:9 Var t : String\n# 20:25-20:28 <- py 6:12-6:15 Lit \".\" : String\n# 21:2-21:57 <- py 7:4-8:31 Let u : String\n# 21:7-21:47 <- py 7:4-8:31 Branch if : String\n# 21:20-21:43 <- py 7:7-7:15 Prim String.contains : Bool\n# 21:36-21:37 <- py 7:14-7:15 Var u : String\n# 21:39-21:42 <- py 7:7-7:10 Lit \"x\" : String\n# 22:2-22:3 <- py 9:4-9:12 Return : String\n# 22:2-22:3 <- py 9:11-9:12 Var u : String\n"
