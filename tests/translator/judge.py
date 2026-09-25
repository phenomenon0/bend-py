"""The translator judge: `judge.py --demo normalize_stem | repo_of | first_dash | fm_sources [--optimize [--bench]]`.

Extracts one allow-listed function by `ast` (its module is never imported or
executed), translates it with demos/python/translate.bend, and reports three
separate claims (plan-astra-v2 §6, translator-modes.md C1-C3):

  C1 checker acceptance: no hole / open goal / @unsafe, strict check, four lanes build and run
  C2 source parity: pinned CPython oracle == check-accepted Bend, on literal examples,
     contract edge cases and seeded generated inputs, identically in every lane
  C3 semantic theorem status: reported as-is, never upgraded by C1 or C2

The doctest adapter (T2) is restricted on purpose. A doctest becomes a law only when
it is a CLOSED LITERAL CALL: `>>> f(<literals>)` of the demo's own def, positional
arguments that `ast.literal_eval` reads as str or list[str], and a want that reads
as a literal str / bool / None (no output = None). Each such example becomes
`law doctest_k: {T.f(args) == want : Ret}` proven by `{==}`, so the CHECKER decides
it by computation. The doctest text is parsed, never executed; every other example
(`is None`, a nested call, a name, a keyword, an exception, ...) is counted and
skipped, not approximated. A closed instance is not a universal theorem: C3 says so.

`--optimize` (tier 3, translator-modes.md) then judges demos/python/optimize.bend's file for
the same def: no rewrite logged -> it must be the faithful file byte for byte; else C1 and C2
again on it (not inherited), C3 unchanged, and two more claims apart:

  C4 rewrite equivalence, Bend-vs-Bend: optimized == faithful in every lane on the fixtures and
     on 1000 more generated inputs; each logged step's law, stated against the emitted helper,
     checked by the checker; the log's spans read back off the source by `ast`
  C5 benefit (`--bench`): medians of seven warmed runs per lane, alternated; a lane under 1.05x
     rejects the step there
"""

import os
import sys

# The oracle is $PY_ORACLE, else this interpreter; either way it must be the pinned version.
ORACLE = os.environ.get("PY_ORACLE") or sys.executable
VERSION = (3, 11, 15)
if os.path.abspath(sys.executable) != os.path.abspath(ORACLE):
    os.execv(ORACLE, [ORACLE, *sys.argv])
if sys.version_info[:3] != VERSION or sys.implementation.name != "cpython":
    raise SystemExit(f"Pinned oracle changed: {ORACLE}: {sys.version}")

import argparse
import ast
import doctest
import hashlib
import random
import re
import statistics
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
# The mined trees; $PY_MINED_ROOT re-roots them. Absent, their demos are SKIP (exit 3), not FAIL.
MINED = Path(os.environ.get("PY_MINED_ROOT") or Path.home() / "Documents/Project")
SKIP = 3
WS = " \t\n\r\x0b\x0c"
ALPHABET = (
    "".join(map(chr, range(32, 127))) + WS
)  # the value contract: printable ASCII + six ASCII whitespace

# fm_sources' frontmatter: lines a `sources:` line may sit among, and the text around them.
FM_LINES = [
    "sources: a",
    "sources: [a, b]",
    'sources: ["x", "y"]',
    "sources: []",
    "sources:",
    "sources:[",
    "sources: a:b",
    "sources: [a]x",
    "sources: [ 'a' ,\t\"b\" ,]",
    "  sources: z",
    "title: t",
    "",
]


def fm_text(rng):
    def line():
        if rng.random() < 0.3:
            return "sources:" + "".join(rng.choice(ALPHABET) for _ in range(rng.randrange(0, 12)))
        return rng.choice(FM_LINES)

    return (
        rng.choice(["", "---\n", "---\n", "---\n", "---\n", "x---\n", "---\r\n", "\n---\n"])
        + "".join(line() + rng.choice(["\n", "\n", "\n", "\r\n", "\r", "\x0b"]) for _ in range(rng.randrange(0, 4)))
        + rng.choice(["---", "---", "---\n", "--", "", "---\nsources: late\n---"])
        + rng.choice(["", "body", "\nsources: after\n"]),
    )


# fm_sources' contract edges, also the module demo's: the frontmatter shapes the parse must survive.
DEMOS_FM_EDGES = [
        "",
        "---",
        "---\n---",
        "---\n\n---",  # an empty group: no lines
        "---\n---\n---",
        "---\nsources: a\n---\nsources: b\n---",  # the earliest closing delimiter
        "---\nx: 1\n---\nsources: b\n---",  # a sources line after it is not frontmatter
        "x---\nsources: a\n---",  # ^ is the start of the text (no re.M)
        "\n---\nsources: a\n---",
        "---\nsources: a\nsources: b\n---",  # the first sources line returns
        "---\n sources: a\n---",
        "---\nsources:[\n---",
        "---\nsources: [a,,b]\n---",
        "---\nsources: [ \"a\" , 'b' ]\n---",
        "---\nsources: a:b\n---",
        "---\nsources: [a]x\n---",
        "---\r\nsources: a\r\n---",
        "---\nsources: a\r\n---",
        "---\nt: 1\rsources: a\n---",  # splitlines' boundaries: \r, \v, \f
        "---\nt\x0bsources: a\n---",
        '---\nt\x0csources: "q"\n---',
        '---\nsources:\t["a",\t"b"]\n---',
        '---\nsources: "[a]"\n---',
        '---\nsources: ["""]\n---',
        "---\nsources: a\n--",
        "---\nsources: a\n----",
        "---\n" + "t: x\n" * 20 + "sources: [" + ", ".join("s" * k for k in range(1, 12)) + "]\n---",
]


# Allow list. `sha256` pins the reviewed function text: a changed source is re-reviewed, not re-judged.
# `examples` are hand-written literals (the source has a docstring and no doctest: labeled contract
# fixtures per plan §4); the oracle must agree with them before it is trusted for anything else.
DEMOS = {
    "normalize_stem": {
        "path": MINED / "llm-wiki/tools/wiki.py",
        "sha256": "4af82c046d8931ed49c1034276a54fd82481e69d6ca9a3191c60cf99be17434d",
        "examples": [
            (("Hello World",), "hello-world"),
            (("  My Page  ",), "my-page"),
            (("already-stem",), "already-stem"),
            (("A  B",), "a--b"),
            (("",), ""),
            (("   ",), ""),
            (("MiXeD Case 42",), "mixed-case-42"),
        ],
        "builtins": {"str": str},
        "wrong": ("String.trim(s)", "s", "translation without strip"),
        "edges": [
            *WS,
            WS,
            WS + "x" + WS,
            "\tTab Inside\tX\n",
            "a\nb c\r\nd",
            " - ",
            "-",
            "- -",
            "a b",
            " a b ",
            "\x0b\x0c A \x0c\x0b",
            "Z",
            "AZaz@[`{",
            "\"quoted\" 'single'",
            "back\\slash \\n",
            "x" + " " * 40 + "y",
            ALPHABET,
            ALPHABET[::-1],
            "  " + ALPHABET.upper() + "  ",
        ],
        "generate": lambda rng: (
            "".join(
                rng.choice(ALPHABET if rng.random() < 0.7 else WS + " AZaz-")
                for _ in range(rng.randrange(0, 24))
            ),
        ),
        "c3": "tested fragment, no theorem. The for/if/None idioms are unused; the translation rests on three primitive "
        "contracts (str.strip/lower/replace = String.trim/to_lower/replace on the ASCII value contract), assumed "
        "like SOUNDNESS.md A3 and only tested here. Lint grades this def `ownership Unknown` (method call = "
        "dynamic call in T0/O0): B1-B3 are argued from `str` immutability (A1), a paper-argued candidate.",
    },
    # Unannotated in the source: the reviewed signature is the stub in `sig`, and the judge
    # passes it as PY_SIG. No doctests: the examples are labeled contract fixtures (plan 4).
    "repo_of": {
        "path": MINED / "llm-wiki/tools/overview.py",
        "sha256": "295c526c1ee5ec2b0381ab376ba7e8250320db37fdb5d6510823092b297e6500",
        "sig": "def repo_of(pid: str, slugs: list[str]) -> str | None:\n    pass\n",
        "builtins": {"len": len},
        "wrong": ('String.append(s, "-")', "s", "translation without the '-' boundary"),
        # --optimize: rule #1's site starts_with(x, y + z) as the step law states it; the unsound
        # helper the controls must reject; a variant whose side-condition fails (Unknown).
        "hoist": ("tail", "s", '"-"'),
        "owrong": ('String.starts_with(String.drop(tail, String.length(s)), "-")', "True{}", "helper without the '-' boundary"),
        "unknown": ("s + '-'", "s.strip() + '-'"),
        "examples": [
            (("bend.bend-lang-12", ["bend", "bend-lang"]), "bend-lang"),  # longest prefix
            (("bend.bend-lang-12", ["bend-lang", "bend"]), "bend-lang"),
            (("p.ab-1", ["ab", "ab"]), "ab"),
            (("p.a-b-1", ["a", "a-b", "a-c"]), "a-b"),
            (("p.xy-1", ["xy", "zz", "xy"]), "xy"),
            (("SRC-p.bend-1", ["bend"]), None),  # SRC- guard
            (("nodot", ["nodot"]), None),  # no '.'
            (("p.bend", ["bend"]), "bend"),  # tail == s
            (("p.bendx", ["bend"]), None),  # prefix without the '-' boundary
            (("p.bend-1", []), None),
        ],
        "edges": [
            ("", []),
            (".", [""]),
            (".-", [""]),  # "" + "-" is a prefix of the tail "-"
            ("a.b.c", ["b.c", "b"]),  # split once: the tail keeps its dots
            ("a.b.c-1", ["c", "b.c"]),
            ("src-p.x-1", ["x"]),  # the guard is case-sensitive
            ("xSRC-.x-1", ["x"]),
            ("SRC-", []),
            (".x", ["x", "x"]),
            ("p.ab-cd-ef", ["ab", "ab-cd", "ab-cd-ef", "ab-c"]),  # tail == s wins by length
            ("p.ab-cd", ["ab-cd", "ab", "zz-zz"]),  # same length later does not replace: strict >
            ("p.aa-1", ["aa", "bb"]),
            ("p.--", ["-", ""]),
            ("p. -1", [" ", "\t"]),
            ('p."q"-1', ['"q"', "\\"]),
            ("p." + "s" * 40 + "-t", ["s" * 40, "s" * 39]),
        ],
        "generate": lambda rng: (
            lambda slugs: (
                rng.choice(["", "SRC-", "p.", "p.", "p.", "proj.x.", "."])
                + rng.choice(slugs + ["zz", ""])
                + rng.choice(["", "-1", "-a-b", "x", ".y", "-"]),
                slugs[: rng.randrange(0, len(slugs) + 1)],
            )
        )(
            rng.sample(
                ["bend", "bend-lang", "bend-lang.com", "a", "a-b", "ab", "", "x", "-", "p"],
                6,
            )
        ),
        "c3": "tested fragment, no theorem. if/or/not-in, Optional narrowing and the for-fold are emitted as "
        "helper matches; the translation rests on the primitive contracts (startswith/in/==/+/len/>/not and "
        "guarded split(sep,1)[1] = Py.after under the known fact `sep in s`), assumed like SOUNDNESS.md A3 and "
        "only tested here. The source has no doctests, so no law is stated for it.",
    },
    # A labeled fixture, not a real module: `break` (the Step fold) and the doctest adapter.
    "first_dash": {
        "path": ROOT / "tests/translator/fixtures.py",
        "sha256": "9ee30afe73e14c99e533307134243c8bf9f34defd188fb8d7a5ba17c11ee6e26",
        "builtins": {"str": str, "list": list},
        "wrong": ("      Stop{hit}", "      Continue{hit}", "translation without break"),
        "examples": [
            ((["a", "-b", "-c"],), "-b"),
            (([],), None),
            ((["a", "b"],), None),
            ((["-", "-x"],), "-"),
        ],
        "edges": [([""],), (["", "-"],), (["a-", "-a", "-a"],), ([" -", "--"],)],
        "generate": lambda rng: (
            [
                rng.choice(["a", "-b", "", "-", "c-", "-c d", "\t-"])
                for _ in range(rng.randrange(0, 6))
            ],
        ),
        "c3": "tested fragment, no theorem. `break` is a Step fold (Continue/Stop): items after the stop are "
        "not evaluated. Its closed doctests are checked laws (closed instances, not a universal theorem).",
    },
    # T3: re.search/group, an early return from a loop, a comprehension, slices. Unannotated: the
    # stub is the reviewed signature, and its `import re` is the labeled assumption that `re` is
    # the stdlib module, which `imported` checks against the source module by `ast`.
    "fm_sources": {
        "path": MINED / "llm-wiki/tools/synapse.py",
        "sha256": "e40787adf3abbb7112660ed3c9d36ec9c36c7a9baceb5152498af17ea2c7956f",
        "sig": "import re\ndef fm_sources(text: str) -> list[str]:\n    pass\n",
        "builtins": {},
        "globals": {"re": re},
        "wrong": (r'"^---\\n(.*?)\\n---"', r'"^---\\n(.*)\\n---"', "translation with a greedy group"),
        "examples": [
            (("---\nsources: [a, b]\n---\nbody",), ["a", "b"]),
            (('---\ntitle: t\nsources: ["x", "y"]\n---\n',), ["x", "y"]),
            (("---\nsources: one\n---",), ["one"]),
            (("---\ntitle: t\n---",), []),
            (("no frontmatter",), []),
            (("---\nsources: []\n---",), [""]),
            (("---\nsources:\n---",), [""]),
        ],
        "edges": DEMOS_FM_EDGES,
        "generate": fm_text,
        "c3": "tested fragment, no theorem. The early return is a Step fold of Maybe (Stop{Some{v}}), then a match "
        "on the fold's value; the comprehension is a recursive helper, head first. The translation rests on the "
        "primitive contracts (re.search/m.group = Py.search/Py.group on Base's Regex, splitlines, split, strip, "
        "the slices), assumed like SOUNDNESS.md A3 and only tested here; group 1 is granted because the kernel "
        "reads it off the parsed pattern. The source has no doctests, so no law is stated for it.",
    },
    # T4: a module, not a def. No ~4-def acyclic chain of fragment constructs exists in llm-wiki
    # (surveyed by ast: the candidates want dicts, isinstance, Path, subprocess, sqlite3 or sets),
    # so this is the labeled composite the plan allows: two pinned real defs, each judged on its
    # own above, and a caller written here. `module` names the parts; the caller is the top of the
    # chain and every fixture goes through it. All three calls are real: `fm_sources` under
    # `keyed_sources` (list[str]), `keyed_sources` bound by the caller's let, and `normalize_stem`
    # inside the comprehension's body (str). T5 put `keyed_sources` between the other two so one
    # fact crosses a call; `('stem:' + s).split(':', 1)[1] == s` for every s, so the answers are
    # the same answers, and the 200 fixtures below are unchanged.
    "source_stems": {
        "module": ["fm_sources", "normalize_stem"],
        "caller": "def source_stems(text: str) -> list[str]:\n    v = keyed_sources(text)\n"
        "    return [normalize_stem(s.split(':', 1)[1]) for s in v]\n"
        "\ndef keyed_sources(text: str) -> list[str]:\n    return ['stem:' + s for s in fm_sources(text)]\n",
        "sig": "import re\ndef fm_sources(text: str) -> list[str]:\n    pass\n",
        "builtins": {"str": str, "list": list},
        "globals": {"re": re},
        "wrong": ('normalize_stem(Py.after(s, ":"))', 'Py.after(s, ":")', "the comprehension that normalizes nothing"),
        # T5: the fact that crosses the call is one character of Python. Drop the key's colon and
        # `keyed_sources` still type-checks, still returns list[str] -- and the caller's guarded
        # split is granted by nothing, so the module does not emit at all.
        "refuse": [("'stem:' + s", "'stem' + s", "the key without its colon", "Py.after is not granted by a contract")],
        "examples": [
            (("---\nsources: [a, b]\n---\nbody",), ["a", "b"]),
            (('---\ntitle: t\nsources: ["x", "y"]\n---\n',), ["x", "y"]),
            (("---\nsources: Hello World\n---",), ["hello-world"]),
            (('---\nsources: ["A B", "  C  "]\n---',), ["a-b", "c"]),
            (("---\nsources: one\n---",), ["one"]),
            (("---\ntitle: t\n---",), []),
            (("no frontmatter",), []),
            (("---\nsources: []\n---",), [""]),
            (("---\nsources:\n---",), [""]),
        ],
        "edges": [
            *DEMOS_FM_EDGES,
            "---\nsources: A B\n---",  # the caller's own work: both calls on one item
            "---\nsources: [ A B , C D ]\n---",
            "---\nsources:  \n---",
            "---\nsources: -\n---",
        ],
        "generate": fm_text,
        "c3": "tested fragment, no theorem. The module is the claim: three calls between four defs, ranked by the "
        "kernel (a callee is granted only against the defs it has already accepted, so the rank is the list "
        "position and a cycle cannot be stated). Each call is the plain Bend call; the parts' own contracts are "
        "unchanged and were judged apart above. The caller is written in this file and labeled, not mined: it "
        "carries no reviewed source, so nothing is assumed of it beyond what the fragment already grants. One fact "
        "crosses a call: `keyed_sources` puts every item of its result under the `stem:` key, the kernel "
        "recomputes that from its body and mints it into the signature, and the caller's `split(':', 1)[1]` is "
        "granted by that postcondition and by nothing else -- its own text never says the colon is there.",
    },
    # T5's producer, mined and judged apart. LLVM's opt-viewer names one HTML page per source
    # file: the separators are flattened and `.html` is appended, so every path through the def
    # carries that literal and the kernel reads one postcondition off the body. Unannotated in
    # the source: the reviewed signature is the stub in `sig`, and a stub is types only -- there
    # is no Python syntax for a postcondition, so the claim cannot be smuggled in through it.
    "html_file_name": {
        "path": MINED
        / "ipad-lab/tools/build-src/apple-libtapi/src/llvm/tools/opt-viewer/optrecord.py",
        "sha256": "f8270a39f647ca17dc20a4ff76181129c31ea4a97e8b0e01c70c310302574249",
        "sig": "def html_file_name(filename: str) -> str:\n    pass\n",
        "builtins": {},
        "wrong": ('String.replace(filename, "/", "_")', "filename", "translation without the '/' flattening"),
        "examples": [
            (("tools/opt.cpp",), "tools_opt.cpp.html"),
            (("lib/IR/Value.h",), "lib_IR_Value.h.html"),
            (("main",), "main.html"),
            (("",), ".html"),
            (("a#b",), "a_b.html"),
            (("/",), "_.html"),
            (("#",), "_.html"),
        ],
        "edges": [
            *WS,
            "/#",
            "#/",
            "//",
            "##",
            "a/b#c/d",
            ".",
            "..",
            ".html",
            "x.html",
            "_",
            "a_b",
            " / ",
            "\t#\x0b",
            ALPHABET,
            ALPHABET[::-1],
            "/" * 40 + "x",
        ],
        "generate": lambda rng: (
            "".join(
                rng.choice(ALPHABET if rng.random() < 0.5 else "/#._ab")
                for _ in range(rng.randrange(0, 24))
            ),
        ),
        "c3": "tested fragment, no theorem. One return and no control flow: the translation rests on two primitive "
        "contracts (str.replace/+ = String.replace/String.append on the ASCII value contract), assumed like "
        "SOUNDNESS.md A3 and only tested here. The source has no doctests, so no law is stated for it. The kernel "
        "reads one thing off this body beyond its type -- every path carries `.html` -- and nothing here consumes "
        "it; `page_tail` below is what does.",
    },
    # T5's real-program showcase: a MINED producer, and a guard that its carried literal is the
    # only thing granting. The caller is written here and labeled -- no corpus file calls
    # `html_file_name` from inside the fragment (optrecord.py's own caller, `make_link`, goes
    # through str.format) -- but the guard is the corpus's own shape: `repo_of` above writes the
    # SAME `split('.', 1)[1]` and pays for it with a hand-written `'.' not in pid` test. Here
    # there is no test to write. `html_file_name` puts the dot there on every path, the kernel
    # recomputes that from the mined body and mints it into the signature, and `gives` widens
    # `contains ".html"` to the `contains "."` the split asks for. Both controls below are
    # one character of Python: kill the dot in the producer, or ask for a separator the claim
    # does not hold, and nothing is emitted at all.
    "page_tail": {
        "module": ["html_file_name"],
        "caller": 'def page_tail(filename: str) -> str:\n    page = html_file_name(filename)\n'
        '    return page.split(".", 1)[1]\n',
        "sig": "def html_file_name(filename: str) -> str:\n    pass\n",
        "builtins": {"str": str},
        "wrong": ('Py.after(page, ".")', "page", "the tail that never splits"),
        "refuse": [
            ('+ ".html"', '+ "html"', "the page name without its dot", "Py.after is not granted by a contract"),
            ('split(".", 1)', 'split("!", 1)', "a separator the claim does not hold", "Py.after is not granted by a contract"),
        ],
        "examples": [
            (("tools/opt.cpp",), "cpp.html"),
            (("lib/IR/Value.h",), "h.html"),
            (("main",), "html"),
            (("",), "html"),
            (("a#b",), "html"),
            (("a.b.c",), "b.c.html"),
            ((".",), ".html"),
        ],
        "edges": [
            *WS,
            "/#",
            "#/",
            "..",
            ".html",
            "x.html",
            "a/b#c/d",
            "a.b/c.d",
            ".a.",
            "a..b",
            " . ",
            "\t.\x0b",
            ALPHABET,
            ALPHABET[::-1],
            "." * 40 + "x",
        ],
        "generate": lambda rng: (
            "".join(
                rng.choice(ALPHABET if rng.random() < 0.5 else "/#._ab")
                for _ in range(rng.randrange(0, 24))
            ),
        ),
        "c3": "tested fragment, no theorem. Two defs, one call, and one fact across it. The producer is mined and "
        "was judged apart above; the caller is written in this file and labeled, so nothing is assumed of it "
        "beyond what the fragment already grants. Its `split('.', 1)[1]` is the guarded Py.after contract, and "
        "nothing in the caller's own text says a dot is there: `html_file_name` appends `.html` on every path, "
        "the kernel recomputes that claim from the mined body (a stub carries types, not postconditions) and "
        "mints it into the signature, and the substring widening in `gives` turns `contains \".html\"` into the "
        "`contains \".\"` the split asks for. `repo_of` above is the same split with the test written by hand.",
    },
}

# The stub pass's ten, same shape, in their own file: judge.py is at its ttok cap.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from demos_stubs1 import demos as _stubs1  # noqa: E402

DEMOS.update(_stubs1(ALPHABET, WS, MINED))


def extract(path, name):
    """(def text, line, def node)."""
    source = Path(path).read_text(encoding="utf-8")
    found = [
        n
        for n in ast.parse(source, feature_version=(3, 11)).body
        if isinstance(n, ast.FunctionDef) and n.name == name
    ]
    if len(found) != 1:
        raise SystemExit(
            f"FAIL extract: {len(found)} top-level defs named {name} in {path}"
        )
    return ast.get_source_segment(source, found[0]) + "\n", found[0].lineno, found[0]


def pinned(part):
    """(text, def node) of one reviewed def, with its provenance line and its pin checked."""
    demo = DEMOS[part]
    text, line, node = extract(demo["path"], part)
    digest = hashlib.sha256(text.encode()).hexdigest()
    print(f"source   {demo['path']}:{line} {part} sha256 {digest[:16]} (ast extraction; module never imported)")
    if digest != demo["sha256"]:
        raise SystemExit(
            f"FAIL source text changed (pinned {demo['sha256'][:16]}): re-review the contract, then re-pin"
        )
    imported(demo["path"], demo.get("globals", {}))
    return text, node


def source(name, demo):
    """(the text to translate, the def the fixtures call). A `module` demo is a labeled composite:
    every def the caller calls is pinned like any other demo, and the caller itself is written in
    this file -- it claims no reviewed source, so nothing is assumed of it."""
    if "module" not in demo:
        return pinned(name)
    text = "\n".join([demo["caller"]] + [pinned(part)[0] for part in demo["module"]])
    print(
        f"source   tests/translator/judge.py {name} caller written here "
        f"(labeled composite: {len(demo['module'])} pinned def{'' if len(demo['module']) == 1 else 's'}"
        f" + the caller; the module is never imported)"
    )
    return text, [n for n in ast.parse(text).body if isinstance(n, ast.FunctionDef) and n.name == name][0]


def oracle(text, name, builtins, env):
    # The extracted def alone: nothing of its module, and no builtin or global but the demo's reviewed few.
    scope = {"__builtins__": builtins, **env}
    exec(compile(text, name, "exec"), scope)
    return scope[name]


def imported(path, names):
    """Each global is its stdlib module: the module binds it only by a top-level `import name`.
    A syntactic check (A1-like: nothing rebinds it through globals() or sys.modules)."""
    mod = ast.parse(Path(path).read_text(encoding="utf-8"), feature_version=(3, 11))
    for g in names:
        good = bad = 0
        for n in ast.walk(mod):
            if isinstance(n, (ast.Import, ast.ImportFrom)):
                for a in n.names:
                    if (a.asname or a.name.split(".")[0]) == g:
                        plain = isinstance(n, ast.Import) and a.name == g and a.asname is None and n in mod.body
                        good, bad = good + plain, bad + (not plain)
            elif isinstance(n, ast.Name) and not isinstance(n.ctx, ast.Load):
                bad += n.id == g
            elif isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.ExceptHandler, ast.MatchAs, ast.MatchStar)):
                bad += n.name == g
            elif isinstance(n, ast.arg):
                bad += n.arg == g
            elif isinstance(n, (ast.Global, ast.Nonlocal)):
                bad += g in n.names
        if good < 1 or bad:
            raise SystemExit(f"FAIL {g} is not bound only by `import {g}` in {path}")


def bend_literal(s):
    named = {"\\": "\\\\", '"': '\\"', "\n": "\\n", "\t": "\\t", "\r": "\\r"}
    return (
        '"'
        + "".join(
            named.get(c) or (c if " " <= c <= "~" else "\\u{%x}" % ord(c)) for c in s
        )
        + '"'
    )


def bend_value(v):
    if v is None:
        return "None{}"
    if isinstance(v, bool):
        return "True{}" if v else "False{}"
    if isinstance(v, str):
        return bend_literal(v)
    return "[" + ", ".join(map(bend_value, v)) + "]"


def bend_type(node):
    """The Bend text of a fragment annotation: str, bool, list[T], T | None."""
    if isinstance(node, ast.Name) and node.id in ("str", "bool"):
        return {"str": "String", "bool": "Bool"}[node.id]
    if isinstance(node, ast.Subscript):
        return f"List<&2, {bend_type(node.slice)}>"
    if isinstance(node, ast.BinOp):
        return f"Maybe<&2, {bend_type(node.left)}>"
    raise SystemExit(f"FAIL annotation outside the fragment: {ast.dump(node)}")


def closed(value, ty):
    return {
        "String": lambda: isinstance(value, str),
        "Bool": lambda: isinstance(value, bool),
        "List<&2, String>": lambda: isinstance(value, list)
        and all(isinstance(x, str) for x in value),
        "Maybe<&2, String>": lambda: value is None or isinstance(value, str),
    }.get(ty, lambda: False)()


def doctest_laws(name, fn_node, sig_node):
    """([(args, want)], skipped): the closed literal-call doctests; parsed, never executed."""
    tys = [bend_type(a.annotation) for a in sig_node.args.args]
    laws, skipped = [], 0
    for ex in doctest.DocTestParser().get_examples(ast.get_docstring(fn_node) or ""):
        try:
            call = ast.parse(ex.source.strip(), mode="eval").body
            assert isinstance(call, ast.Call) and isinstance(call.func, ast.Name)
            assert call.func.id == name and not call.keywords and not ex.exc_msg
            args = tuple(ast.literal_eval(a) for a in call.args)
            want = ast.literal_eval(ex.want.strip()) if ex.want.strip() else None
            assert len(args) == len(tys) and all(map(closed, args, tys))
            assert closed(want, bend_type(sig_node.returns))
            laws.append((args, want))
        except (AssertionError, ValueError, SyntaxError):
            skipped += 1
    return laws, skipped


def law_file(name, ret, laws):
    out = ["import Base", f"import ./{name}.bend as T", ""]
    for k, (args, want) in enumerate(laws):
        call = f"T.{name}({', '.join(map(bend_value, args))})"
        value = bend_value(want)
        if ret.startswith("Maybe") and want is not None:
            value = f"Some{{{value}}}"
        out += [
            f"law doctest_{k}:",
            f"  {{{call} == {value} : {ret}}}",
            "",
            f"def doctest_{k}():",
            "  {==}",
            "",
        ]
    return "\n".join(out + ["def main() -> String:", '  "laws"']) + "\n"


def encode(e, maybe):
    if e is None:
        return "N|"
    if isinstance(e, bool):
        return "1|" if e else "0|"
    if isinstance(e, list):
        return "".join("".join(f"{ord(c)} " for c in x) + ";" for x in e) + "|"
    return ("S " if maybe else "") + "".join(f"{ord(c)} " for c in e) + "|"


def harness(name, inputs, expected, maybe):
    """A house-style test: main prints each result as code points (no escaping convention to trust)."""
    parts = [inputs[i : i + 20] for i in range(0, len(inputs), 20)]
    out = [
        "import Base",
        f"import ./{name}.bend as T",
        "",
        "def codes(s: String) -> String:",
        "  match s:",
        "    case SNil{}:",
        '      "|"',
        "    case SCon{h, t}:",
        '      U32.show(Char.to_u32(h)) ++ " " ++ codes(t)',
        "",
    ]
    if maybe:
        out += [
            "def shown(m: Maybe<&2, String>) -> String:",
            "  match m:",
            "    case None{}:",
            '      "N|"',
            "    case Some{s}:",
            '      "S " ++ codes(s)',
            "",
        ]
    flagged = any(isinstance(e, bool) for e in expected)
    if flagged:
        out += [
            "def flag(b: Bool) -> String:",
            "  match b:",
            "    case True{}:",
            '      "1|"',
            "    case False{}:",
            '      "0|"',
            "",
        ]
    listed = any(isinstance(e, list) for e in expected)
    if listed:
        out += [
            "def item(s: String) -> String:",
            "  match s:",
            "    case SNil{}:",
            '      ";"',
            "    case SCon{h, t}:",
            '      U32.show(Char.to_u32(h)) ++ " " ++ item(t)',
            "",
            "def listed(xs: List<&2, String>) -> String:",
            "  match xs:",
            "    case Nil{}:",
            '      "|"',
            "    case Con{h, t}:",
            "      item(h) ++ listed(t)",
            "",
        ]
    for k, part in enumerate(parts):
        out += [
            f"def part{k}() -> String:",
            "  "
            + " ++\n  ".join(
                f"{'shown' if maybe else 'flag' if flagged else 'listed' if listed else 'codes'}(T.{name}({', '.join(map(bend_value, a))}))"
                for a in part
            ),
            "",
        ]
    out += [
        "def main() -> String:",
        "  " + " ++ ".join(f"part{k}()" for k in range(len(parts))),
    ]
    want = '"' + "".join(encode(e, maybe) for e in expected) + '"'
    return "\n".join(out) + "\n#|" + want + "\n", want


def holes(text):
    """C1, textual half: no hole, open goal or @unsafe outside comments and string literals."""
    code = "\n".join(
        re.sub(r'"(?:\\.|[^"\\])*"', '""', l)
        for l in text.splitlines()
        if not l.lstrip().startswith("#")
    )
    return [w for w in ("@unsafe", "?") if w in code]


CHECK = """import * as B from "./bend2/bend.ts";
const book = B.book_nil();
await B.book_load(book, process.argv[1], "", new Map());
B.book_valid(book);
if (book.hols + book.open) process.exit(1);
console.log("All terms check.");"""


def sh(*cmd, env=None):
    r = subprocess.run(
        cmd,
        cwd=ROOT,
        # The daily version check writes to stderr, and stderr is part of an emitted file here.
        env={**os.environ, "BEND_NO_TELEMETRY": "1", **(env or {})},
        capture_output=True,
        text=True,
        timeout=600,
    )
    return r.returncode, (r.stdout + r.stderr).strip()


def lanes(test, work):
    """{lane: output}; a lane that fails to build or run reports its failure text, never a skip."""
    got = {
        "check": sh("bun", "-e", CHECK, str(test))[1],
        "interpret": sh("bun", "bend2/main.ts", str(test))[1],
    }
    for lane, target, run in (
        ("js", work / "t.js", ["bun", str(work / "t.js")]),
        ("c", work / "t", [str(work / "t"), "--gpu", "off"]),
    ):
        rc, log = sh("bun", "bend2/main.ts", str(test), "-o", str(target))
        got[lane] = sh(*run)[1] if rc == 0 else f"build failed: {log[:300]}"
    return got


def emit(tool, work, name, demo, text, sig=None):
    """(rc, file): demos/python/<tool>.bend on the def text, with the demo's reviewed stub."""
    work.mkdir(exist_ok=True)
    (work / f"{name}.py").write_text(text, encoding="utf-8")
    (work / "sig.py").write_text(demo.get("sig", "") if sig is None else sig, encoding="utf-8")
    return sh(
        "bun",
        "bend2/main.ts",
        f"demos/python/{tool}.bend",
        env={
            "PY_SOURCE": str(work / f"{name}.py"),
            "PY_DEF": "" if "module" in demo else name,  # empty: the whole module, every top-level def
            **({"PY_SIG": str(work / "sig.py")} if "sig" in demo else {}),
        },
    )


def judge(name, show):
    demo = DEMOS[name]
    text, node = source(name, demo)
    stub = [n for n in ast.parse(demo.get("sig", "")).body if isinstance(n, ast.FunctionDef) and n.name == name]
    sig_node = stub[0] if stub else node
    ret = bend_type(sig_node.returns)
    maybe = ret.startswith("Maybe")
    fn = oracle(text, name, demo["builtins"], demo.get("globals", {}))
    laws, skipped = doctest_laws(name, node, sig_node)
    bad = [(i, fn(*i), o) for i, o in demo["examples"] + laws if fn(*i) != o]
    if bad:
        raise SystemExit(f"FAIL oracle disagrees with the literal examples: {bad}")
    rng = random.Random(20260919)
    generated = [demo["generate"](rng) for _ in range(160)]
    edges = [e if isinstance(e, tuple) else (e,) for e in demo["edges"]]
    inputs = [i for i, _ in demo["examples"]] + edges + generated
    assert all(set(bend_value(a)) <= set(ALPHABET) for i in inputs for a in i), (
        "fixture outside the value contract"
    )
    expected = [fn(*i) for i in inputs]
    old, new, what = demo["wrong"]

    with tempfile.TemporaryDirectory(prefix="bend-judge.") as tmp:
        work = Path(tmp)
        rc, emitted = emit("translate", work, name, demo, text)
        if rc != 0:
            raise SystemExit(f"FAIL emission blocked: {emitted}")
        (work / f"{name}.bend").write_text(emitted + "\n", encoding="utf-8")
        if show:
            print(emitted)
        test, want = harness(name, inputs, expected, maybe)
        (work / "demo.bend").write_text(test, encoding="utf-8")
        got = lanes(work / "demo.bend", work)

        # Harness controls: a hole must fail C1's text check; an unfaithful translation must fail C2.
        (work / "wrong").mkdir()
        (work / "wrong" / f"{name}.bend").write_text(
            emitted.replace(old, new) + "\n", encoding="utf-8"
        )
        (work / "wrong" / "demo.bend").write_text(test, encoding="utf-8")
        wrong = sh("bun", "bend2/main.ts", str(work / "wrong" / "demo.bend"))[1]

        # A postcondition control: the same module with the claim made false in the PYTHON, which
        # the kernel must refuse outright -- an emission the caller could not have had.
        # The reviewed claim is the stub when there is one, and the source's own header when
        # there is not: a control edits whichever holds it, and both must be refused.
        refused = None
        for rold, rnew, _, rerr in demo.get("refuse", []):
            in_sig = rold in demo.get("sig", "")
            assert in_sig or rold in text, "the refusal control does not apply to this source"
            rc, out = emit(
                "translate", work / "refuse", name, demo,
                text if in_sig else text.replace(rold, rnew),
                demo["sig"].replace(rold, rnew) if in_sig else None,
            )
            refused = (refused in (None, True)) and rc != 0 and rerr in out

        # The doctest laws: the checker decides each by computation; a falsified want must fail.
        lawful = lied = None
        if laws:
            (work / "laws.bend").write_text(law_file(name, ret, laws), encoding="utf-8")
            lawful = sh("bun", "-e", CHECK, str(work / "laws.bend"))[1]
            lie = [(a, "~" if w is None else w + "~") for a, w in laws]
            (work / "laws.bend").write_text(law_file(name, ret, lie), encoding="utf-8")
            lied = sh("bun", "-e", CHECK, str(work / "laws.bend"))[1]
    controls = (
        holes(emitted.replace(old, "?hole")) == ["?"]
        and old in emitted
        and (not laws or "All terms check." not in lied)
        and wrong != want
        and wrong.startswith('"')
        and refused in (None, True)
    )

    c1 = (
        not holes(emitted)
        and got["check"] == "All terms check."
        and all(v.startswith('"') for k, v in got.items() if k != "check")
    )
    same = len({got[k] for k in ("interpret", "js", "c")}) == 1
    per = {
        k: sum(
            a == b
            for a, b in zip(
                got[k].strip('"').split("|"), want.strip('"').split("|")[:-1]
            )
        )
        for k in ("interpret", "js", "c")
    }
    c2 = same and all(got[k] == want for k in per)
    n = len(inputs)
    print(
        f"fixtures {len(demo['examples'])} literal examples + {len(demo['edges'])} contract edges + {len(generated)} generated (seed 20260919) = {n}"
    )
    print(
        f"C1 checker acceptance : {'ok' if c1 else 'FAIL'} (no hole/open goal/@unsafe; strict check; lanes check+interpret+js+c all ran)"
    )
    print(
        f"C2 source parity      : {'ok' if c2 else 'FAIL'} "
        + " ".join(f"{k} {v}/{n}" for k, v in per.items())
        + f"; lanes identical: {same}"
    )
    print(f"C3 theorem status     : {demo['c3']}")
    c3 = "tested-fragment"
    ok = True
    if laws or skipped:
        ok = lawful in (None, "All terms check.")
        c3 += f" + {len(laws) if ok else 0}/{len(laws)} closed doctest laws"
        print(
            f"doctest laws          : {'ok' if ok else 'FAIL'} {len(laws)} closed literal-call examples checked as laws "
            f"({{==}}, by the checker); {skipped} outside the restriction, skipped and not approximated"
        )
        if not ok:
            print(f"  laws: {lawful[:400]}")
    print(
        f"controls              : {'ok' if controls else 'FAIL'} (injected hole rejected by C1; {what} rejected by C2"
        + ("; falsified doctest laws rejected by the checker" if laws else "")
        + "".join(f"; {r[2]} refused by the kernel" for r in demo.get("refuse", []))
        + ")"
    )
    for k, v in got.items():
        if (k == "check" and v != "All terms check.") or (k != "check" and v != want):
            print(f"  lane {k}: {v[:400]}")
    print(
        f"{name}: C1 {'ok' if c1 else 'FAIL'} · C2 {min(per.values())}/{n} · C3 {c3}"
    )
    return c1 and c2 and ok and controls, (demo, text, inputs, expected, maybe, want, got, emitted, c3)


RULE = "# rewrites: rule, Python span, grade: evidence\n"
UNKNOWN = "Unknown: not applied, the string or its prefix is not a name (it would be evaluated twice)"
BENCH = {"c": 20000, "js": 5000, "interpret": 20}  # iterations: seconds per run in each lane


def site(text, prefix):
    """The span the log must name, by `ast`: the one `startswith` call whose argument reads `prefix`."""
    [n] = [
        n
        for n in ast.walk(ast.parse(text))
        if isinstance(n, ast.Call)
        and isinstance(n.func, ast.Attribute)
        and n.func.attr == "startswith"
        and ast.get_source_segment(text, n.args[0]) == prefix
    ]
    return f"{n.lineno}:{n.col_offset}-{n.end_lineno}:{n.end_col_offset}"


def step_law(name, out, emitted, hoist, where):
    """The step's instance of O.starts_append, stated against the helper the rewrite emitted:
    the faithful subterm == the optimized one, for all strings x and y."""
    x, y, z = hoist
    [helper] = set(re.findall(r"^def (\S+)\(", out, re.M)) - set(re.findall(r"^def (\S+)\(", emitted, re.M))
    head = re.search(rf"^def {re.escape(helper)}\(_c: Bool, (.*?)\) ->", out, re.M).group(1)
    ps = ", ".join(p.split(":")[0].lstrip("+") for p in head.split(", "))
    old = f"String.starts_with({x}, String.append({y}, {z}))"
    new = f"T.{helper}(String.starts_with({x}, {y}), {ps})"
    return f"""import Base
import ./{name}.bend as T
import {os.path.relpath(ROOT / "demos/python/optimize.bend", where)} as O

law bridge:
  for b: Bool
  for {x}: String
  for {y}: String
  {{O.hoisted(b, {x}, {y}, {z}) == T.{helper}(b, {ps}) : Bool}}

def bridge(b, {x}, {y}):
  match b:
    case True{{}}:
      {{==}}
    case False{{}}:
      {{==}}

law step:
  for +{x}: String
  for +{y}: String
  {{{old} == {new} : Bool}}

def step({x}, {y}):
  Equal.trans(Bool, {old}, O.hoisted(String.starts_with({x}, {y}), {x}, {y}, {z}), {new}, O.starts_append({x}, {y}, {z}), bridge(String.starts_with({x}, {y}), {x}, {y}))

def main() -> String:
  "laws"
""", helper


def bench_file(name, inputs, n):
    """n iterations of every fixture, summed; the first argument is cut by String.take(_, k) with
    k >= its length, so the value is unchanged but no call is shared across iterations."""
    assert max(len(a[0]) for a in inputs) < 1000

    def add(xs):
        acc = "0n"
        for x in reversed(xs):
            acc = f"Nat.add({x}, {acc})"
        return acc

    calls = [
        f"score(T.{name}({', '.join([f'String.take({bend_value(a[0])}, k)', *map(bend_value, a[1:])])}))"
        for a in inputs
    ]
    parts = [calls[i : i + 20] for i in range(0, len(calls), 20)]
    out = ["import Base", f"import ./{name}.bend as T", "", "def score(m: Maybe<&2, String>) -> Nat:",
           "  match m:", "    case None{}:", "      0n", "    case Some{s}:", "      String.length(s)", ""]
    for k, part in enumerate(parts):
        out += [f"def part{k}(+k: Nat) -> Nat:", "  " + add(part), ""]
    out += ["def all(+k: Nat) -> Nat:", "  " + add([f"part{k}(k)" for k in range(len(parts))]), "",
            "def go(n: Nat, +k: Nat, acc: Nat) -> Nat:", "  match n:", "    case 0n:", "      acc",
            "    case 1n+p:", "      go(p, Nat.add(k, 1n), Nat.add(acc, all(k)))", "",
            # a literal of thousands can overflow the frontend's stack; a product does not
            "def main() -> Nat:", f"  go(Nat.mul({n // 1000 or n}n, {1000 if n >= 1000 else 1}n), 1000n, 0n)", ""]
    return "\n".join(out)


def bench(name, inputs, work, arts):
    """{lane: (faithful s, optimized s, same result)}: per lane, one warmup of each file, then
    seven runs alternated faithful/optimized, wall clock around the process; medians."""
    res = {}
    for lane, n in BENCH.items():
        cmds = {}
        for tag, art in arts.items():
            d = work / f"bench_{lane}_{tag}"
            d.mkdir()
            (d / f"{name}.bend").write_text(art + "\n", encoding="utf-8")
            (d / "b.bend").write_text(bench_file(name, inputs, n), encoding="utf-8")
            cmds[tag] = ["bun", "bend2/main.ts", str(d / "b.bend")]
            if lane != "interpret":
                target = d / ("b.js" if lane == "js" else "b")
                rc, log = sh(*cmds[tag], "-o", str(target))
                if rc != 0:
                    raise SystemExit(f"FAIL C5 {lane} build: {log[:300]}")
                cmds[tag] = ["bun", str(target)] if lane == "js" else [str(target), "--gpu", "off"]
        times, outs = {t: [] for t in cmds}, {t: sh(*c)[1] for t, c in cmds.items()}
        for _ in range(7):
            for t, c in cmds.items():
                start = time.perf_counter()
                outs[t] = sh(*c)[1]
                times[t].append(time.perf_counter() - start)
        res[lane] = (statistics.median(times["f"]), statistics.median(times["o"]), outs["f"] == outs["o"])
    return res


def optimized(name, demo, text, inputs, expected, maybe, want, faithful, emitted, c3, show, timing):
    with tempfile.TemporaryDirectory(prefix="bend-judge.") as tmp:
        work = Path(tmp)
        rc, out = emit("optimize", work, name, demo, text)
        if rc != 0:
            raise SystemExit(f"FAIL optimization blocked: {out}")
        if show:
            print(out)
        log = out.partition(RULE)[2].splitlines()
        if not log:
            same = out == emitted
            print(f"optimized             : {'ok' if same else 'FAIL'} no rewrite logged; byte-identical to the faithful file: {same}")
            print(f"{name} --optimize: C4 no step · {'identical' if same else 'FAIL not identical'}")
            return same
        (work / f"{name}.bend").write_text(out + "\n", encoding="utf-8")
        test, _ = harness(name, inputs, expected, maybe)
        (work / "demo.bend").write_text(test, encoding="utf-8")
        got = lanes(work / "demo.bend", work)
        law, helper = step_law(name, out, emitted, demo["hoist"], work)
        (work / "law.bend").write_text(law, encoding="utf-8")
        lawful = sh("bun", "-e", CHECK, str(work / "law.bend"))[1]

        # C4 beyond the fixtures, Bend-vs-Bend: the faithful file is the reference, no oracle.
        rng = random.Random(20260920)
        more = [demo["generate"](rng) for _ in range(1000)]
        par = {}
        for tag, art in (("f", emitted), ("o", out)):
            (work / tag).mkdir()
            (work / tag / f"{name}.bend").write_text(art + "\n", encoding="utf-8")
            (work / tag / "demo.bend").write_text(harness(name, more, [None] * len(more), maybe)[0], encoding="utf-8")
            par[tag] = lanes(work / tag / "demo.bend", work / tag)

        # Controls: an unsound helper must fail C2, C4's parity and the step law; a site whose
        # side-condition fails must stay faithful and be logged Unknown with its span.
        old, new, what = demo["owrong"]
        (work / "wrong").mkdir()
        (work / "wrong" / f"{name}.bend").write_text(out.replace(old, new) + "\n", encoding="utf-8")
        (work / "wrong" / "demo.bend").write_text(test, encoding="utf-8")
        wrong = sh("bun", "bend2/main.ts", str(work / "wrong" / "demo.bend"))[1]
        (work / "wrong" / "law.bend").write_text(step_law(name, out, emitted, demo["hoist"], work / "wrong")[0], encoding="utf-8")
        lied = sh("bun", "bend2/main.ts", str(work / "wrong" / "law.bend"))[1]  # the reason: bridge fails
        prefix, variant = demo["unknown"]
        vtext = text.replace(prefix, variant)
        rf, vf = emit("translate", work / "unknown", name, demo, vtext)
        ro, vo = emit("optimize", work / "unknown", name, demo, vtext)
        unknown = (
            text.count(prefix) == 1
            and rf == ro == 0
            and vo.partition("\n")[2].partition(RULE)[0] == vf.partition("\n")[2] + "\n"
            and vo.partition(RULE)[2].splitlines() == [f"# hoist_append {site(vtext, variant)} {UNKNOWN}"]
        )
        c5 = bench(name, inputs, work, {"f": emitted, "o": out}) if timing else None
    controls = (
        holes(out.replace(old, "?hole")) == ["?"]
        and old in out
        and wrong.startswith('"')
        and wrong != want
        and wrong != faithful["interpret"]
        and "Location: bridge" in lied
        and unknown
    )
    runs = ("interpret", "js", "c")
    c1 = not holes(out) and got["check"] == "All terms check." and all(got[k].startswith('"') for k in runs)
    per = {k: sum(a == b for a, b in zip(got[k].strip('"').split("|"), want.strip('"').split("|")[:-1])) for k in runs}
    c2 = len({got[k] for k in runs}) == 1 and all(got[k] == want for k in runs)
    logged = log == [f"# hoist_append {site(text, demo['unknown'][0])} Proven: law starts_append, demos/python/optimize.bend"]
    parity = all(got[k] == faithful[k] for k in runs) and all(
        par["o"][k] == par["f"][k] and par["f"][k].startswith('"') for k in runs
    ) and len({par["f"][k] for k in runs}) == 1
    c4 = logged and parity and lawful == "All terms check."
    n = len(inputs)
    print(f"optimized             : demos/python/optimize.bend, {len(log)} step(s) logged")
    for line in log:
        print(f"  {line}")
    print(f"C1 checker acceptance : {'ok' if c1 else 'FAIL'} (again, on the optimized file)")
    print(f"C2 source parity      : {'ok' if c2 else 'FAIL'} " + " ".join(f"{k} {v}/{n}" for k, v in per.items()) + " (again, vs the oracle; not inherited)")
    print(f"C3 theorem status     : unchanged, {c3} (tier 3 never upgrades C3)")
    print(
        f"C4 rewrite equivalence: {'ok' if c4 else 'FAIL'} log spans read back by ast: {logged}; optimized == faithful in "
        f"interpret, js, c on the {n} fixtures and 1000 more generated (seed 20260920): {parity}; step law "
        f"(starts_append at {helper}, stated against the emitted file): {'checked' if lawful == 'All terms check.' else lawful[:300]}"
    )
    print(
        f"controls              : {'ok' if controls else 'FAIL'} (injected hole rejected by C1; {what} rejected by C2, "
        f"C4 parity and the step law; `{variant}` not applied, logged Unknown at its span, code as faithful)"
    )
    for k in runs:
        if got[k] != want:
            print(f"  lane {k}: {got[k][:400]}")
    if c5:
        print("C5 measured benefit   : medians of 7 warmed runs, alternated, wall clock per process (startup included); "
              f"the {len(inputs)} fixtures per iteration; faithful -> optimized:")
        for lane, (f, o, same) in c5.items():
            print(f"  {lane:9} {BENCH[lane]:>6} iterations  {f:.3f} s -> {o:.3f} s  {f / o:.2f}x  "
                  f"{'gain' if f / o >= 1.05 else 'rejected'}{'' if same else '  FAIL results differ'}")
    verdict = " · ".join(f"{lane} {f / o:.2f}x" + ("" if f / o >= 1.05 else " (rejected)") for lane, (f, o, _) in c5.items()) if c5 else "not measured (--bench)"
    print(f"{name} --optimize: C1 {'ok' if c1 else 'FAIL'} · C2 {min(per.values())}/{n} · C3 {c3} · "
          f"C4 {len(log)} step Proven (law starts_append){'' if c4 else ' FAIL'} · C5 {verdict}")
    return c1 and c2 and c4 and controls and all(same for _, _, same in (c5 or {}).values())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--demo", required=True, choices=sorted(DEMOS))
    ap.add_argument("--show", action="store_true", help="print the emitted Bend file(s)")
    ap.add_argument("--optimize", action="store_true", help="then judge demos/python/optimize.bend's file (C1-C4)")
    ap.add_argument("--bench", action="store_true", help="with --optimize: time it against the faithful file (C5)")
    args = ap.parse_args()
    parts = DEMOS[args.demo].get("module", [args.demo])
    missing = [str(DEMOS[p]["path"]) for p in parts if not Path(DEMOS[p]["path"]).exists()]
    if missing:
        print(f"SKIP {args.demo}: source absent: {', '.join(missing)} (set PY_MINED_ROOT)")
        sys.exit(SKIP)
    ok, ctx = judge(args.demo, args.show)
    if args.optimize:
        ok = optimized(args.demo, *ctx, args.show, args.bench) and ok
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
