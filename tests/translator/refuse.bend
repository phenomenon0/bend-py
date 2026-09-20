# Never a silent guess: every source outside the fragment blocks emission with
# a positioned diagnostic. `near` and `let` are the positive controls: a literal
# receiver and a single-use let are inside the fragment. Spelling is not authority (`str.lower(s)`,
# `len(s)`), a method is granted only at its contracted arity and types.
import Base
import ../../demos/python/syntax.bend as S
import ../../demos/python/translate.bend as Tr

def line(r: Result<&2, &2, S.Error, String>) -> String:
  match r:
    case Done{s}:
      "emitted"
    case Fail{e}:
      S.error_text(e)

def one(label: String, body: String) -> String:
  label ++ ": " ++ line(Tr.translate(body, Tr.contracts(), "f")) ++ "\n"

def head() -> String:
  "def f(s: str) -> str:\n    "

# T2: the control idioms. What is refused is what `repo_of` does not need, or
# what Python could make observable: truthiness, a loop with no or several
# accumulators (or, since T3, one that returns and also accumulates), a partial
# operation whose guard is not known on the path (the kernel's refusal,
# positioned at the def).
def opt() -> String:
  "def f(s: str, xs: list[str]) -> str | None:\n    "

# T4: the module. A call between the defs of one source is granted only when
# the callee can be ranked below the caller, at its own arity and types; the
# rest is refused where it is written. `chain` is the positive control: three
# defs, the caller written first.
def mod(label: String, body: String) -> String:
  label ++ ": " ++ line(Tr.translate(body, Tr.contracts(), "")) ++ "\n"

def t4() -> String:
  mod("chain", "def f(s: str) -> str:\n    return g(s)\n\ndef g(s: str) -> str:\n    return h(s)\n\ndef h(s: str) -> str:\n    return s.strip()\n") ++
  mod("self call", "def f(s: str) -> str:\n    return f(s)\n") ++
  mod("cycle", "def f(s: str) -> str:\n    return g(s)\n\ndef g(s: str) -> str:\n    return f(s)\n") ++
  mod("cycle of three", "def f(s: str) -> str:\n    return g(s)\n\ndef g(s: str) -> str:\n    return h(s)\n\ndef h(s: str) -> str:\n    return f(s)\n") ++
  mod("call arity", "def g(s: str, t: str) -> str:\n    return t\n\ndef f(s: str) -> str:\n    return g(s)\n") ++
  mod("call arg type", "def g(xs: list[str]) -> list[str]:\n    return xs\n\ndef f(s: str) -> list[str]:\n    return g(s)\n") ++
  mod("call result type", "def g(s: str) -> str:\n    return s\n\ndef f(s: str) -> list[str]:\n    return g(s)\n") ++
  mod("unknown callee", "def f(s: str) -> str:\n    return h(s)\n") ++
  mod("param shadows", "def g(s: str) -> str:\n    return s\n\ndef f(g: str) -> str:\n    return g(g)\n") ++
  mod("let shadows", "def g(s: str) -> str:\n    return s\n\ndef f(s: str) -> str:\n    g = s.strip()\n    return g(g)\n") ++
  mod("keyword call", "def g(s: str) -> str:\n    return s\n\ndef f(s: str) -> str:\n    return g(s=s)\n") ++
  mod("import", "import re\n\ndef f(s: str) -> str:\n    return s\n") ++
  mod("from import", "from wiki import normalize_stem\n\ndef f(s: str) -> str:\n    return normalize_stem(s)\n") ++
  mod("no def", "\"a module of no def\"\n") ++
  mod("def named len", "def len(s: str) -> str:\n    return s\n\ndef f(s: str) -> str:\n    return len(s)\n") ++
  mod("def named re", "def re(s: str) -> str:\n    return s\n\ndef f(s: str) -> str:\n    return re(s)\n") ++
  mod("two defs of a name", "def g(s: str) -> str:\n    return s\n\ndef g(s: str) -> str:\n    return s.strip()\n")

def t2() -> String:
  one("loop", opt() ++ "best = None\n    for x in xs:\n        if x == s:\n            best = x\n    return best\n") ++
  one("break", opt() ++ "best = None\n    for x in xs:\n        if x == s:\n            best = x\n            break\n    return best\n") ++
  one("guarded split", opt() ++ "if '.' not in s:\n        return None\n    return s.split('.', 1)[1]\n") ++
  one("guard and", opt() ++ "if s.startswith('a') and '.' in s:\n        return s.split('.', 1)[1]\n    return None\n") ++
  one("unguarded split", opt() ++ "return s.split('.', 1)[1]\n") ++
  one("other guard", opt() ++ "if '-' not in s:\n        return None\n    return s.split('.', 1)[1]\n") ++
  one("guard rebound", opt() ++ "if '.' not in s:\n        return None\n    s = s.lower()\n    return s.split('.', 1)[1]\n") ++
  one("guard or", opt() ++ "if '.' in s or s == 'a':\n        return s.split('.', 1)[1]\n    return None\n") ++
  one("empty sep", opt() ++ "if '' not in s:\n        return None\n    return s.split('', 1)[1]\n") ++
  one("split all", opt() ++ "return s.split('.')[1]\n") ++
  one("index", opt() ++ "return s[1]\n") ++
  one("truthy if", opt() ++ "if s:\n        return s\n    return None\n") ++
  one("truthy or", opt() ++ "if s or s == 'a':\n        return s\n    return None\n") ++
  one("early return", opt() ++ "best = None\n    for x in xs:\n        best = x\n        return x\n    return best\n") ++
  one("no accumulator", opt() ++ "for x in xs:\n        y = x\n    return None\n") ++
  one("two accumulators", opt() ++ "a = None\n    b = None\n    for x in xs:\n        a = x\n        b = x\n    return a\n") ++
  one("for else", opt() ++ "a = None\n    for x in xs:\n        a = x\n    else:\n        a = None\n    return a\n") ++
  one("target bound", opt() ++ "a = None\n    for s in xs:\n        a = s\n    return a\n") ++
  one("nested for", opt() ++ "a = None\n    for x in xs:\n        for y in xs:\n            a = y\n    return a\n") ++
  one("after if in loop", opt() ++ "a = None\n    for x in xs:\n        if x == s:\n            a = x\n        a = None\n    return a\n") ++
  one("for over str", opt() ++ "a = None\n    for x in s:\n        a = x\n    return a\n") ++
  one("break outside", opt() ++ "break\n") ++
  one("while", opt() ++ "while s == 'a':\n        return s\n    return None\n") ++
  one("path falls", opt() ++ "if s == 'a':\n        s = 'b'\n    return s\n") ++
  one("is none", opt() ++ "if s is None:\n        return None\n    return s\n") ++
  one("none type", "def f(s: str) -> str:\n    return None\n") ++
  one("retyped", opt() ++ "a = None\n    a = s == 'a'\n    return a\n") ++
  one("user call", opt() ++ "return g(s)\n") ++
  one("chain", opt() ++ "if s == s == s:\n        return s\n    return None\n") ++
  one("augassign", opt() ++ "s += 'a'\n    return s\n") ++
  one("tuple target", opt() ++ "a, b = s, s\n    return a\n") ++
  one("len escapes", opt() ++ "return len(s)\n")

# T3: what `fm_sources` needs, and its near misses. An unannotated def takes
# its types from the reviewed stub; `re.` is offered only if the stub imports it.
def as(label: String, body: String, sig: String) -> String:
  label ++ ": " ++ line(Tr.translate_as("def f(s):\n    " ++ body, sig ++ "def f(s: str) -> list[str]:\n    pass\n", Tr.contracts(), "f")) ++ "\n"

def re(label: String, body: String) -> String:
  as(label, body, "import re\n")

def got(p: String, g: String) -> String:
  "m = re.search(r\"" ++ p ++ "\", s, re.S)\n    if not m:\n        return []\n    return [m.group(" ++ g ++ ")]\n"

def t3() -> String:
  re("group", got("^a(b)", "1")) ++
  as("re unimported", got("^a(b)", "1"), "") ++
  as("re aliased", got("^a(b)", "1"), "import re as re\n") ++
  re("group zero", got("^a(b)", "0")) ++
  re("group absent", got("^a(b)", "2")) ++
  re("group optional", got("^a(b)?", "1")) ++
  re("group lazy", got("^a(b)*?", "1")) ++
  re("group one side", got("(a)|b", "1")) ++
  re("group both sides", got("(a)|(b)", "1")) ++
  re("bad pattern", got("^a(b", "1")) ++
  re("escape in pattern", "m = re.search(\"a\\n(b)\", s, re.S)\n    if not m:\n        return []\n    return [m.group(1)]\n") ++
  re("no flag", "m = re.search(r\"(a)\", s)\n    if not m:\n        return []\n    return [m.group(1)]\n") ++
  re("other flag", "m = re.search(r\"(a)\", s, re.M)\n    if not m:\n        return []\n    return [m.group(1)]\n") ++
  re("pattern name", "m = re.search(s, s, re.S)\n    if not m:\n        return []\n    return [m.group(1)]\n") ++
  re("unnarrowed", "m = re.search(r\"(a)\", s, re.S)\n    return [m.group(1)]\n") ++
  re("narrowed after rebind", "m = re.search(r\"(a)\", s, re.S)\n    if not m:\n        return []\n    s = s.strip()\n    return [m.group(1)]\n") ++
  re("binds re", "re = s\n    return [re]\n") ++
  re("binds len", "len = s\n    return [len]\n") ++
  re("comprehension", "return [x.strip() for x in s.split(',')]\n") ++
  re("comprehension if", "return [x for x in s.split(',') if x == 'a']\n") ++
  re("comprehension two", "return [x for x in s.split(',') for y in s.split(',')]\n") ++
  re("comprehension bound", "return [s for s in s.split(',')]\n") ++
  re("comprehension over str", "return [x for x in s]\n") ++
  re("comprehension type", "return [x == 'a' for x in s.split(',')]\n") ++
  re("list", "return [s, s.strip()]\n") ++
  re("list type", "return [s, s == 'a']\n") ++
  one("empty list", head() ++ "return []\n") ++
  re("slices", "return [s[1:], s[:-1], s[2:-3]]\n") ++
  re("slice zero", "return [s[:-0]]\n") ++
  re("slice head", "return [s[:2]]\n") ++
  re("slice from end", "return [s[-1:]]\n") ++
  re("slice step", "return [s[1::2]]\n") ++
  re("slice name", "return [s[len(s):]]\n") ++
  re("split", "return s.split(',')\n") ++
  re("split empty", "return s.split('')\n") ++
  re("split name", "return s.split(s)\n") ++
  re("split none", "return s.split()\n") ++
  re("splitlines keepends", "return s.splitlines(True)\n") ++
  re("strip chars", "return [s.strip('\"')]\n") ++
  re("early return", "for x in s.split(','):\n        if x == 'a':\n            return [x]\n    return []\n") ++
  re("return and accumulate", "a = s\n    for x in s.split(','):\n        a = x\n        return [a]\n    return [a]\n") ++
  re("return name taken", "ret_3_4 = s\n    for x in s.split(','):\n        return [x]\n    return [ret_3_4]\n") ++
  re("return name read", "for x in s.split(','):\n        return [ret_2_4]\n    return []\n") ++
  re("return then rest", "for x in s.split(','):\n        if x == 'a':\n            return [x]\n        y = x\n    return []\n") ++
  re("if falls then return", "for x in s.split(','):\n        if x == 'a':\n            y = x\n        return [x]\n    return []\n") ++
  re("return after loop falls", "for x in s.split(','):\n        if x == 'a':\n            return [x]\n") ++
  re("return in else loop", "for x in s.split(','):\n        return [x]\n    else:\n        return []\n    return []\n") ++
  re("return from nested loop", "for x in s.split(','):\n        for y in s.split(','):\n            return [y]\n    return []\n")

def main() -> String:
  one("near", head() ++ "return ' A '.strip().lower()\n") ++
  one("let", head() ++ "x = s.strip()\n    return x\n") ++
  one("method", head() ++ "return s.title()\n") ++
  one("arity", head() ++ "return s.lower('x')\n") ++
  one("keyword", head() ++ "return s.replace(' ', new='-')\n") ++
  one("spelling", head() ++ "return str.lower(s)\n") ++
  one("builtin", head() ++ "return len(s)\n") ++
  one("name", head() ++ "return t.strip()\n") ++
  one("escape", head() ++ "return s.replace('\\t', '-')\n") ++
  one("adjacent", head() ++ "return s.replace('a' 'b', '-')\n") ++
  one("unbound method", head() ++ "return s.strip\n") ++
  one("ifexp", head() ++ "return s if s else s\n") ++
  one("after", head() ++ "return s\n    return s.lower()\n") ++
  one("bare", head() ++ "return\n") ++
  one("falls", head() ++ "pass\n") ++
  one("untyped", "def f(s) -> str:\n    return s\n") ++
  one("int", "def f(s: int) -> str:\n    return s\n") ++
  one("returns", "def f(s: str) -> bool:\n    return s\n") ++
  one("default", "def f(s: str = 'a') -> str:\n    return s\n") ++
  one("open module", "import re\n" ++ head() ++ "return s\n") ++
  one("twice", head() ++ "return s\n" ++ head() ++ "return s.lower()\n") ++
  one("absent", "def g(s: str) -> str:\n    return s\n") ++
  t2() ++
  t3() ++
  t4()
#|"near: emitted\nlet: emitted\nmethod: error Unsupported 2 11 no verified contract for .title on (String) with () at 2:11\narity: error Unsupported 2 11 no verified contract for .lower on (String) with (String;) at 2:11\nkeyword: error Unsupported 2 11 outside the fragment: Call at 2:11\nspelling: error Unsupported 2 11 unresolved name str at 2:11\nbuiltin: error Unsupported 2 4 type mismatch: (Nat) where (String) is expected at 2:4\nname: error Unsupported 2 11 unresolved name t at 2:11\nescape: error Unsupported 2 21 literal outside the contract (one plain ASCII string or r-string, no escapes; a decimal natural; True, False, None) at 2:21\nadjacent: error Unsupported 2 21 literal outside the contract (one plain ASCII string or r-string, no escapes; a decimal natural; True, False, None) at 2:21\nunbound method: error Unsupported 2 11 outside the fragment: Attribute at 2:11\nifexp: error Unsupported 2 16 truthiness of a non-bool is outside the fragment at 2:16\nafter: error Unsupported 3 4 statement after return at 3:4\nbare: error Unsupported 2 4 outside the fragment: statement Return at 2:4\nfalls: error Unsupported 2 4 outside the fragment: statement Pass at 2:4\nuntyped: error Unsupported 1 0 missing or non-builtin annotation\nint: error Unsupported 1 9 annotation outside the fragment (str, bool, list[T], T | None) at 1:9\nreturns: error Unsupported 2 4 type mismatch: (String) where (Bool) is expected at 2:4\ndefault: error Unsupported 1 0 decorated or non-simple parameters\nopen module: error Unsupported 2 0 module not closed: Import at 1:0\ntwice: error Unsupported 1 0 no unique def f\nabsent: error Unsupported 0 0 no unique def f\nloop: emitted\nbreak: emitted\nguarded split: emitted\nguard and: emitted\nunguarded split: error Unsupported 1 0 primitive Py.after is not granted by a contract (or its guard is not known here) at 2:11\nother guard: error Unsupported 1 0 primitive Py.after is not granted by a contract (or its guard is not known here) at 4:11\nguard rebound: error Unsupported 1 0 primitive Py.after is not granted by a contract (or its guard is not known here) at 5:11\nguard or: error Unsupported 1 0 primitive Py.after is not granted by a contract (or its guard is not known here) at 3:15\nempty sep: error Unsupported 1 0 primitive Py.after is not granted by a contract (or its guard is not known here) at 4:11\nsplit all: error Unsupported 2 11 outside the fragment: Subscript at 2:11\nindex: error Unsupported 2 11 outside the fragment: Subscript at 2:11\ntruthy if: error Unsupported 2 7 truthiness of a non-bool is outside the fragment at 2:7\ntruthy or: error Unsupported 2 7 truthiness of a non-bool is outside the fragment at 2:7\nearly return: error Unsupported 3 4 for: a loop that returns must not also assign a name bound before it at 3:4\nno accumulator: error Unsupported 2 4 for: the body must assign exactly one name bound before the loop (the accumulator) at 2:4\ntwo accumulators: error Unsupported 4 4 for: the body must assign exactly one name bound before the loop (the accumulator) at 4:4\nfor else: error Unsupported 3 4 for: the target must be one fresh name and there is no else at 3:4\ntarget bound: error Unsupported 3 4 for: the target must be one fresh name and there is no else at 3:4\nnested for: error Unsupported 4 8 outside the fragment: statement For at 4:8\nafter if in loop: error Unsupported 6 8 statement after an if that falls through inside a loop is outside the fragment at 6:8\nfor over str: error Unsupported 3 13 for over a non-list (String) at 3:13\nbreak outside: error Unsupported 2 4 outside the fragment: statement Break at 2:4\nwhile: error Unsupported 2 4 outside the fragment: statement While at 2:4\npath falls: error Unsupported 3 8 no return: falling off the end is outside the fragment at 3:8\nis none: error Unsupported 2 7 `is None` on a name that is not Optional: s at 2:7\nnone type: error Unsupported 2 11 None outside an Optional return type at 2:11\nretyped: error Unsupported 3 4 type mismatch: (Bool) where (Maybe<&2, String>) is expected at 3:4\nuser call: error Unsupported 2 11 outside the fragment: Call at 2:11\nchain: error Unsupported 2 7 outside the fragment: Compare chain at 2:7\naugassign: error Unsupported 2 4 outside the fragment: statement AugAssign at 2:4\ntuple target: error Unsupported 2 4 outside the fragment: statement Assign at 2:4\nlen escapes: error Unsupported 2 4 type mismatch: (Nat) where (Maybe<&2, String>) is expected at 2:4\ngroup: emitted\nre unimported: error Unsupported 2 8 unresolved name re at 2:8\nre aliased: error Unsupported 2 8 unresolved name re at 2:8\ngroup zero: error Unsupported 1 0 primitive Py.group is not granted by a contract (or its guard is not known here) at 5:12\ngroup absent: error Unsupported 1 0 primitive Py.group is not granted by a contract (or its guard is not known here) at 5:12\ngroup optional: error Unsupported 1 0 primitive Py.group is not granted by a contract (or its guard is not known here) at 5:12\ngroup lazy: error Unsupported 1 0 primitive Py.group is not granted by a contract (or its guard is not known here) at 5:12\ngroup one side: error Unsupported 1 0 primitive Py.group is not granted by a contract (or its guard is not known here) at 5:12\ngroup both sides: error Unsupported 1 0 primitive Py.group is not granted by a contract (or its guard is not known here) at 5:12\nbad pattern: error Unsupported 1 0 primitive Py.search is not granted by a contract (or its guard is not known here) at 2:8\nescape in pattern: error Unsupported 2 18 literal outside the contract (one plain ASCII string or r-string, no escapes; a decimal natural; True, False, None) at 2:18\nno flag: error Unsupported 2 8 unresolved name re at 2:8\nother flag: error Unsupported 2 8 unresolved name re at 2:8\npattern name: error Unsupported 1 0 primitive Py.search is not granted by a contract (or its guard is not known here) at 2:8\nunnarrowed: error Unsupported 3 12 no verified contract for .group on (Maybe<&2, Py.Match>) with (Nat;) at 3:12\nnarrowed after rebind: error Unsupported 1 0 primitive Py.group is not granted by a contract (or its guard is not known here) at 6:12\nbinds re: error Unsupported 1 0 the def binds re or len, which Python then reads as a local\nbinds len: error Unsupported 1 0 the def binds re or len, which Python then reads as a local\ncomprehension: emitted\ncomprehension if: error Unsupported 2 11 outside the fragment: ListComp at 2:11\ncomprehension two: error Unsupported 2 11 outside the fragment: ListComp at 2:11\ncomprehension bound: error Unsupported 2 11 outside the fragment: ListComp at 2:11\ncomprehension over str: error Unsupported 2 23 comprehension over a non-list (String) at 2:23\ncomprehension type: error Unsupported 2 4 type mismatch: (List<&2, Bool>) where (List<&2, String>) is expected at 2:4\nlist: emitted\nlist type: error Unsupported 2 11 list of mixed element types, or [] outside a list return type at 2:11\nempty list: error Unsupported 2 11 list of mixed element types, or [] outside a list return type at 2:11\nslices: emitted\nslice zero: error Unsupported 1 0 primitive String.drop_end is not granted by a contract (or its guard is not known here) at 2:12\nslice head: error Unsupported 2 12 outside the fragment: Subscript at 2:12\nslice from end: error Unsupported 2 14 outside the fragment: UnaryOp USub at 2:14\nslice step: error Unsupported 2 12 outside the fragment: Subscript at 2:12\nslice name: emitted\nsplit: emitted\nsplit empty: error Unsupported 1 0 primitive String.split_on is not granted by a contract (or its guard is not known here) at 2:11\nsplit name: error Unsupported 1 0 primitive String.split_on is not granted by a contract (or its guard is not known here) at 2:11\nsplit none: error Unsupported 2 11 no verified contract for .split on (String) with () at 2:11\nsplitlines keepends: error Unsupported 2 11 no verified contract for .splitlines on (String) with (Bool;) at 2:11\nstrip chars: emitted\nearly return: emitted\nreturn and accumulate: error Unsupported 3 4 for: a loop that returns must not also assign a name bound before it at 3:4\nreturn name taken: error Unsupported 3 4 for: the name ret_3_4 is taken at 3:4\nreturn name read: error Unsupported 2 4 for: the name ret_2_4 is taken at 2:4\nreturn then rest: emitted\nif falls then return: error Unsupported 5 8 statement after an if that falls through inside a loop is outside the fragment at 5:8\nreturn after loop falls: error Unsupported 2 4 no return: falling off the end is outside the fragment at 2:4\nreturn in else loop: error Unsupported 2 4 for: the target must be one fresh name and there is no else at 2:4\nreturn from nested loop: error Unsupported 3 8 outside the fragment: statement For at 3:8\nchain: emitted\nself call: error Unsupported 1 0 call f(String;) -> String is granted by no def ranked below this one at 2:11\ncycle: error Unsupported 1 0 call g(String;) -> String is granted by no def ranked below this one at 2:11\ncycle of three: error Unsupported 1 0 call g(String;) -> String is granted by no def ranked below this one at 2:11\ncall arity: error Unsupported 5 11 no def ranked below this one takes g(String;) at 5:11\ncall arg type: error Unsupported 5 11 no def ranked below this one takes g(String;) at 5:11\ncall result type: error Unsupported 5 4 type mismatch: (String) where (List<&2, String>) is expected at 5:4\nunknown callee: error Unsupported 2 11 outside the fragment: Call at 2:11\nparam shadows: error Unsupported 5 11 outside the fragment: Call at 5:11\nlet shadows: error Unsupported 6 11 outside the fragment: Call at 6:11\nkeyword call: error Unsupported 5 11 outside the fragment: Call at 5:11\nimport: error Unsupported 3 0 module not closed: Import at 1:0\nfrom import: error Unsupported 3 0 module not closed: ImportFrom at 1:0\nno def: error Unsupported 1 0 module: no top-level def to translate at 1:0\ndef named len: error Unsupported 1 0 a def of the module is named re or len, which revokes the builtin the contracts assume\ndef named re: error Unsupported 1 0 a def of the module is named re or len, which revokes the builtin the contracts assume\ntwo defs of a name: error Unsupported 1 0 no unique def g\n"
