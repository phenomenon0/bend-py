# Tier-0 sugar, all untrusted rewrites the kernel then checks as written: an
# f-string of plain fields is a sum of strings, a keyword call to a module def
# is put in parameter order (with the header's literal defaults filling the
# rest), and a capital local (SEP) is renamed to a lower-case ident (u_s_e_p).
# The expected block is the emitted module plus its span map.
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
  show(Tr.translate("def tag(s: str, sep: str = \"-\", end: str = \"!\") -> str:\n    SEP = f\"<{s}>{sep}\"\n    return SEP + end\n\ndef use(s: str) -> str:\n    return tag(s, end=\"?\") + tag(end=\".\", s=s.strip(), sep=\"=\") + f\"{{{s.upper()}}}\"\n", Tr.contracts(), ""))
#|"# Faithful translation (tiers 1-2) of Python `tag` 1:0-3:20, `use` 5:0-6:84 by demos/python/translate.bend.\nimport Base\n\ndef tag(s: String, sep: String, end: String) -> String:\n  u_s_e_p = {String.append(String.append(String.append(\"<\", s), \">\"), sep) : String}\n  String.append(u_s_e_p, end)\n\ndef use(+s: String) -> String:\n  String.append(String.append(tag(s, \"-\", \"?\"), tag(String.trim(s), \"=\", \".\")), String.append(String.append(\"{\", String.to_upper(s)), \"}\"))\n\n# spans: emitted Bend <- Python source, node : type\n# 4:8-4:17 <- py 1:8-1:14 Param s : String\n# 4:19-4:30 <- py 1:16-1:24 Param sep : String\n# 4:32-4:43 <- py 1:32-1:40 Param end : String\n# 5:2-5:84 <- py 2:4-2:23 Let u_s_e_p : String\n# 5:13-5:74 <- py 2:10-2:23 Prim String.append : String\n# 5:27-5:68 <- py 2:10-2:23 Prim String.append : String\n# 5:41-5:62 <- py 2:10-2:23 Prim String.append : String\n# 5:55-5:58 <- py 2:10-2:23 Lit \"<\" : String\n# 5:60-5:61 <- py 2:14-2:15 Var s : String\n# 5:64-5:67 <- py 2:10-2:23 Lit \">\" : String\n# 5:70-5:73 <- py 2:18-2:21 Var sep : String\n# 6:2-6:29 <- py 3:4-3:20 Return : String\n# 6:2-6:29 <- py 3:11-3:20 Prim String.append : String\n# 6:16-6:23 <- py 3:11-3:14 Var u_s_e_p : String\n# 6:25-6:28 <- py 3:17-3:20 Var end : String\n# 8:8-8:18 <- py 5:8-5:14 Param s : String\n# 9:2-9:139 <- py 6:4-6:84 Return : String\n# 9:2-9:139 <- py 6:11-6:84 Prim String.append : String\n# 9:16-9:78 <- py 6:11-6:63 Prim String.append : String\n# 9:30-9:46 <- py 6:11-6:26 Call tag : String\n# 9:34-9:35 <- py 6:15-6:16 Var s : String\n# 9:37-9:40 <- py 1:27-1:30 Lit \"-\" : String\n# 9:42-9:45 <- py 6:22-6:25 Lit \"?\" : String\n# 9:48-9:77 <- py 6:29-6:63 Call tag : String\n# 9:52-9:66 <- py 6:44-6:53 Prim String.trim : String\n# 9:64-9:65 <- py 6:44-6:45 Var s : String\n# 9:68-9:71 <- py 6:59-6:62 Lit \"=\" : String\n# 9:73-9:76 <- py 6:37-6:40 Lit \".\" : String\n# 9:80-9:138 <- py 6:66-6:84 Prim String.append : String\n# 9:94-9:132 <- py 6:66-6:84 Prim String.append : String\n# 9:108-9:111 <- py 6:66-6:84 Lit \"{\" : String\n# 9:113-9:131 <- py 6:71-6:80 Prim String.to_upper : String\n# 9:129-9:130 <- py 6:71-6:72 Var s : String\n# 9:134-9:137 <- py 6:66-6:84 Lit \"}\" : String\n"
