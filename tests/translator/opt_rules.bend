# Rule #1 of the optimizer (hoist_append), row by row. `same` is byte identity with the
# faithful file; `code` compares the code and span map alone (the optimized file's line 1
# names the optimizer, and its log ends it); `log` is the rewrite log. No match leaves the
# faithful file byte for byte; a match whose side-condition fails (the string or its prefix
# not a name) is not applied, the code stays faithful and the log says Unknown with the
# span; a rewrite next to a BoolOp `and` or an IfExp at the call's own position does not
# collide with its helper; several sites log in the order the rewrite visits them.
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

def before(+s: String, +sep: String) -> String:
  Pair.fst(String, String & String, String.partition(s, sep))

def opt(+source: String) -> String:
  show(O.optimize_as(source, "", Tr.contracts(), "f"))

def faithful(+source: String) -> String:
  show(Tr.translate_as(source, "", Tr.contracts(), "f"))

def same(+source: String) -> String:
  Bool.show(String.eq(opt(source), faithful(source)))

def code(+source: String) -> String:
  Bool.show(String.eq(before(after(opt(source), "\n"), "# rewrites:"), after(faithful(source), "\n")))

def log(+source: String) -> String:
  after(opt(source), "# rewrites: rule, Python span, grade: evidence\n")

def main() -> String:
  "no match, normalize_stem: same " ++ same("def f(s: str) -> str:\n    return s.strip().lower().replace(' ', '-')\n") ++
  "\nno match, a literal prefix: same " ++ same("def f(t: str) -> bool:\n    return t.startswith('SRC-')\n") ++
  "\nprefix not a name: code " ++ code("def f(t: str, s: str) -> bool:\n    return t.startswith(s.strip() + '-')\n") ++
  "\n" ++ log("def f(t: str, s: str) -> bool:\n    return t.startswith(s.strip() + '-')\n") ++
  "string not a name: code " ++ code("def f(t: str, s: str) -> bool:\n    return t.strip().startswith(s + '-')\n") ++
  "\n" ++ log("def f(t: str, s: str) -> bool:\n    return t.strip().startswith(s + '-')\n") ++
  "a literal prefix head: code " ++ code("def f(t: str) -> bool:\n    return t.startswith('a' + '-')\n") ++
  "\n" ++ log("def f(t: str) -> bool:\n    return t.startswith('a' + '-')\n") ++
  "two sites, one applied:\n" ++ log("def f(t: str, s: str, u: str) -> bool:\n    return t.startswith(s + '-') or t.startswith(u.lower() + '.')\n") ++
  "the string is the prefix:\n" ++ log("def f(t: str) -> bool:\n    return t.startswith(t + '-')\n") ++
  "=====\n" ++ opt("def f(t: str, s: str, u: bool) -> bool:\n    return t.startswith(s + '-') and u\n") ++
  "=====\n" ++ opt("def f(t: str, s: str, u: bool) -> bool:\n    return t.startswith(s + '-') if u else False\n")
#|"no match, normalize_stem: same True\nno match, a literal prefix: same True\nprefix not a name: code True\n# hoist_append 2:11-2:40 Unknown: not applied, the string or its prefix is not a name (it would be evaluated twice)\nstring not a name: code True\n# hoist_append 2:11-2:40 Unknown: not applied, the string or its prefix is not a name (it would be evaluated twice)\na literal prefix head: code True\n# hoist_append 2:11-2:34 Unknown: not applied, the string or its prefix is not a name (it would be evaluated twice)\ntwo sites, one applied:\n# hoist_append 2:11-2:32 Proven: law starts_append, demos/python/optimize.bend\n# hoist_append 2:36-2:65 Unknown: not applied, the string or its prefix is not a name (it would be evaluated twice)\nthe string is the prefix:\n# hoist_append 2:11-2:32 Proven: law starts_append, demos/python/optimize.bend\n=====\n# Optimized translation (tier 3) of Python `f` 1:0-2:38 by demos/python/optimize.bend; the rewrite log ends the file.\nimport Base\n\ndef f.and_2_24(_c: Bool, t: String, s: String) -> Bool:\n  match _c:\n    case True{}:\n      String.starts_with(String.drop(t, String.length(s)), \"-\")\n    case False{}:\n      False{}\n\ndef f.and_2_11(_c: Bool, u: Bool) -> Bool:\n  match _c:\n    case True{}:\n      u\n    case False{}:\n      False{}\n\ndef f(+t: String, +s: String, u: Bool) -> Bool:\n  f.and_2_11(f.and_2_24(String.starts_with(t, s), t, s), u)\n\n# spans: emitted Bend <- Python source, node : type\n# 7:6-7:63 <- py 2:11-2:32 Prim String.starts_with : Bool\n# 7:25-7:57 <- py 2:24-2:31 Prim String.drop : String\n# 7:37-7:38 <- py 2:11-2:12 Var t : String\n# 7:40-7:56 <- py 2:24-2:31 Prim String.length : Nat\n# 7:54-7:55 <- py 2:24-2:25 Var s : String\n# 7:59-7:62 <- py 2:28-2:31 Lit \"-\" : String\n# 9:6-9:13 <- py 2:24-2:31 Lit False{} : Bool\n# 14:6-14:7 <- py 2:37-2:38 Var u : Bool\n# 16:6-16:13 <- py 2:11-2:38 Lit False{} : Bool\n# 18:6-18:16 <- py 1:6-1:12 Param t : String\n# 18:18-18:28 <- py 1:14-1:20 Param s : String\n# 18:30-18:37 <- py 1:22-1:29 Param u : Bool\n# 19:2-19:59 <- py 2:4-2:38 Return : Bool\n# 19:2-19:59 <- py 2:11-2:38 Branch and : Bool\n# 19:13-19:55 <- py 2:24-2:31 Branch and : Bool\n# 19:24-19:48 <- py 2:11-2:32 Prim String.starts_with : Bool\n# 19:43-19:44 <- py 2:11-2:12 Var t : String\n# 19:46-19:47 <- py 2:24-2:25 Var s : String\n# rewrites: rule, Python span, grade: evidence\n# hoist_append 2:11-2:32 Proven: law starts_append, demos/python/optimize.bend\n=====\n# Optimized translation (tier 3) of Python `f` 1:0-2:48 by demos/python/optimize.bend; the rewrite log ends the file.\nimport Base\n\ndef f.and_2_24(_c: Bool, t: String, s: String) -> Bool:\n  match _c:\n    case True{}:\n      String.starts_with(String.drop(t, String.length(s)), \"-\")\n    case False{}:\n      False{}\n\ndef f.and_2_11(_c: Bool, +t: String, +s: String) -> Bool:\n  match _c:\n    case True{}:\n      f.and_2_24(String.starts_with(t, s), t, s)\n    case False{}:\n      False{}\n\ndef f(t: String, s: String, u: Bool) -> Bool:\n  f.and_2_11(u, t, s)\n\n# spans: emitted Bend <- Python source, node : type\n# 7:6-7:63 <- py 2:11-2:32 Prim String.starts_with : Bool\n# 7:25-7:57 <- py 2:24-2:31 Prim String.drop : String\n# 7:37-7:38 <- py 2:11-2:12 Var t : String\n# 7:40-7:56 <- py 2:24-2:31 Prim String.length : Nat\n# 7:54-7:55 <- py 2:24-2:25 Var s : String\n# 7:59-7:62 <- py 2:28-2:31 Lit \"-\" : String\n# 9:6-9:13 <- py 2:24-2:31 Lit False{} : Bool\n# 14:6-14:48 <- py 2:24-2:31 Branch and : Bool\n# 14:17-14:41 <- py 2:11-2:32 Prim String.starts_with : Bool\n# 14:36-14:37 <- py 2:11-2:12 Var t : String\n# 14:39-14:40 <- py 2:24-2:25 Var s : String\n# 16:6-16:13 <- py 2:43-2:48 Lit False{} : Bool\n# 18:6-18:15 <- py 1:6-1:12 Param t : String\n# 18:17-18:26 <- py 1:14-1:20 Param s : String\n# 18:28-18:35 <- py 1:22-1:29 Param u : Bool\n# 19:2-19:21 <- py 2:4-2:48 Return : Bool\n# 19:2-19:21 <- py 2:11-2:48 Branch and : Bool\n# 19:13-19:14 <- py 2:36-2:37 Var u : Bool\n# rewrites: rule, Python span, grade: evidence\n# hoist_append 2:11-2:32 Proven: law starts_append, demos/python/optimize.bend\n"
