# The optimizer's module door: an empty `name` is the whole module here as it is
# in translate.bend, so a program -- not just a def -- can be rewritten. `same`
# is byte identity with the faithful module; `log` is the rewrite log. A module
# with no site is left byte for byte; a module with a site in two defs logs them
# in the KERNEL'S RANK order (the callee first), not the source's; and the
# postconditions cross the door: the last module's `top` is only emittable
# because `key` puts `k:` in its result, and the rank is recomputed on the
# rewritten defs, so a rewrite that dropped that claim would be refused at `top`.
import Base
import ../../demos/python/syntax.bend as S
import ../../demos/python/translate.bend as Tr
import ../../demos/python/optimize.bend as O

def show(r: Result<&2, &2, S.Error, String>) -> String:
  match r:
    case Done{s}:
      s
    case Fail{e}:
      S.error_text(e)

def after(+s: String, +sep: String) -> String:
  Pair.snd(String, String, Pair.snd(String, String & String, String.partition(s, sep)))

def opt(+source: String) -> String:
  show(O.optimize_as(source, "", Tr.contracts(), ""))

def faithful(+source: String) -> String:
  show(Tr.translate_as(source, "", Tr.contracts(), ""))

def same(+source: String) -> String:
  Bool.show(String.eq(opt(source), faithful(source)))

def log(+source: String) -> String:
  after(opt(source), "# rewrites: rule, Python span, grade: evidence\n")

def main() -> String:
  "no match, a module: same " ++ same("def top(t: str) -> str:\n    return stem(t)\n\ndef stem(t: str) -> str:\n    return t.strip().lower()\n") ++
  "\ntwo defs, two sites, the callee's first:\n" ++ log("def top(t: str, s: str) -> bool:\n    return under(t, s) or t.startswith(s + '.')\n\ndef under(t: str, s: str) -> bool:\n    return t.startswith(s + '-')\n") ++
  "the key without its colon: " ++ opt("def top(t: str, s: str) -> bool:\n    k = key(t)\n    v = k.split(':', 1)[1]\n    return v.startswith(s + '-')\n\ndef key(t: str) -> str:\n    return 'k' + t\n") ++
  "\n=====\n" ++ opt("def top(t: str, s: str) -> bool:\n    k = key(t)\n    v = k.split(':', 1)[1]\n    return v.startswith(s + '-')\n\ndef key(t: str) -> str:\n    return 'k:' + t\n")
#|"no match, a module: same True\ntwo defs, two sites, the callee's first:\n# hoist_append 5:11-5:32 Proven: law starts_append, demos/python/optimize.bend\n# hoist_append 2:26-2:47 Proven: law starts_append, demos/python/optimize.bend\nthe key without its colon: error Unsupported 1 0 primitive Py.after is not granted by a contract (or its guard is not known here) at 3:8\n=====\n# Optimized translation (tier 3) of Python `key` 6:0-7:19, `top` 1:0-4:32 by demos/python/optimize.bend; the rewrite log ends the file.\nimport Base\n\ndef Py.after(+s: String, +sep: String) -> String:\n  Pair.snd(String, String, Pair.snd(String, String & String, String.partition(s, sep)))\n\ndef key(t: String) -> String:\n  String.append(\"k:\", t)\n\ndef top.and_4_24(_c: Bool, v: String, s: String) -> Bool:\n  match _c:\n    case True{}:\n      String.starts_with(String.drop(v, String.length(s)), \"-\")\n    case False{}:\n      False{}\n\ndef top(t: String, +s: String) -> Bool:\n  k = {key(t) : String}\n  +v = {Py.after(k, \":\") : String}\n  top.and_4_24(String.starts_with(v, s), v, s)\n\n# spans: emitted Bend <- Python source, node : type\n# 7:8-7:17 <- py 6:8-6:14 Param t : String\n# 8:2-8:24 <- py 7:4-7:19 Return : String\n# 8:2-8:24 <- py 7:11-7:19 Prim String.append : String\n# 8:16-8:20 <- py 7:11-7:15 Lit \"k:\" : String\n# 8:22-8:23 <- py 7:18-7:19 Var t : String\n# 13:6-13:63 <- py 4:11-4:32 Prim String.starts_with : Bool\n# 13:25-13:57 <- py 4:24-4:31 Prim String.drop : String\n# 13:37-13:38 <- py 4:11-4:12 Var v : String\n# 13:40-13:56 <- py 4:24-4:31 Prim String.length : Nat\n# 13:54-13:55 <- py 4:24-4:25 Var s : String\n# 13:59-13:62 <- py 4:28-4:31 Lit \"-\" : String\n# 15:6-15:13 <- py 4:24-4:31 Lit False{} : Bool\n# 17:8-17:17 <- py 1:8-1:14 Param t : String\n# 17:19-17:29 <- py 1:16-1:22 Param s : String\n# 18:2-18:23 <- py 2:4-2:14 Let k : String\n# 18:7-18:13 <- py 2:8-2:14 Call key : String\n# 18:11-18:12 <- py 2:12-2:13 Var t : String\n# 19:2-19:34 <- py 3:4-3:26 Let v : String\n# 19:8-19:24 <- py 3:8-3:26 Prim Py.after : String\n# 19:17-19:18 <- py 3:8-3:9 Var k : String\n# 19:20-19:23 <- py 3:16-3:19 Lit \":\" : String\n# 20:2-20:46 <- py 4:4-4:32 Return : Bool\n# 20:2-20:46 <- py 4:24-4:31 Branch and : Bool\n# 20:15-20:39 <- py 4:11-4:32 Prim String.starts_with : Bool\n# 20:34-20:35 <- py 4:11-4:12 Var v : String\n# 20:37-20:38 <- py 4:24-4:25 Var s : String\n# rewrites: rule, Python span, grade: evidence\n# hoist_append 4:11-4:32 Proven: law starts_append, demos/python/optimize.bend\n"
