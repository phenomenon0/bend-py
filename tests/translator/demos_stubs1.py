"""The stub pass's allow list: ten mined defs, judged by `judge.py --demo <name>`.

Separate from judge.py only because judge.py is at 88% of its ttok cap; the entries
are the same shape, and `demos(ALPHABET, WS)` takes the judge's value contract rather
than restating it.

Six of the ten are unannotated in their source: the reviewed signature is the stub in
`sig`, passed as PY_SIG, and it is a CLAIM, not a coercion -- the kernel checks it
against the body. Each demo's `refuse` control is the minimal edit to that claim (one
type in the stub, or in the source's own header for the four already-annotated defs):
every one must be refused with a positioned diagnostic, not quietly emitted. Stubs whose
types could not be defended from the body AND its call sites are not here; see
docs/omen/lanes/stubs1.md for the ones that were refused for that reason.
"""

from pathlib import Path

H = Path.home() / "Documents/Project"


def demos(ALPHABET, WS):
    def word(rng, chars, hi=14):
        return "".join(rng.choice(chars) for _ in range(rng.randrange(0, hi)))

    def glue(rng, parts, hi=5):
        return "".join(rng.choice(parts) for _ in range(rng.randrange(0, hi)))

    return {
        # Ninja's path escaping. Order is the whole contract: '$ ' is doubled before the
        # bare-space pass, so the space inside '$$ ' is escaped again ('$ ' -> '$$$ ').
        "escape_path": {
            "path": H / "instant-ngp/dependencies/tinyexr/kuroga.py",
            "sha256": "771bba52cd7791f23d6492908e6d94ea43fe27d4cbab1bd3e7109a5388322032",
            "sig": "def escape_path(word: str) -> str:\n    pass\n",
            "builtins": {},
            "wrong": ('String.replace(word, "$ ", "$$ ")', "word", "translation without the '$ ' pass"),
            "refuse": [("word: str", "word: bool", "the parameter claimed bool", "no verified contract for .replace")],
            "examples": [
                (("a b",), "a$ b"),
                (("C:\\x",), "C$:\\x"),
                (("$ ",), "$$$ "),  # the doubling, then the space of '$$ ' escaped again
                (("",), ""),
                (("plain",), "plain"),
                (("a:b c",), "a$:b$ c"),
                (("$",), "$"),
            ],
            "edges": [": :", "$$  ", "  ", "$", "$$", "$ $", " $", ":", "::", " : ", "$:", "$$ ", ":$ ", "\t", "\n", WS, "a" + WS + "b", ALPHABET, "$" * 8, " " * 8],
            "generate": lambda rng: (word(rng, "$ :ab/\\", 16),),
            "c3": "tested fragment, no theorem. One return, no control flow: three chained str.replace = three "
            "String.replace on the ASCII value contract, assumed like SOUNDNESS.md A3 and only tested here. The "
            "signature is a stub -- unannotated in the source -- and the kernel checks it against the body: the "
            "control claims `word: bool` and .replace has no contract there.",
        },
        # A guard, a for over a literal list, and an early return: the fragment's Step fold.
        # The list's order decides, not the URL's: '_540._500.' upgrades the '_500.'.
        "upgrade_tumblr_url": {
            "path": H / "archi-lab/src/enrich/match_and_download_hq.py",
            "sha256": "97b387d3c65373e3c1d1fd0fc255d8be0ea22fa2046a6019427ac341117271b2",
            "builtins": {"str": str},
            "wrong": ('String.replace(url, old_size, "_1280.")', "url", "the loop that upgrades nothing"),
            "refuse": [("url: str", "url: bool", "the parameter claimed bool", "no verified contract for .__contains__")],
            "examples": [
                (("http://x.tumblr.com/a_500.jpg",), "http://x.tumblr.com/a_1280.jpg"),
                (("http://x.com/a_500.jpg",), "http://x.com/a_500.jpg"),  # the guard
                (("http://x.tumblr.com/a_9.jpg",), "http://x.tumblr.com/a_9.jpg"),  # no size matches
                (("tumblr.com/_540._500.",), "tumblr.com/_540._1280."),  # the list's order, not the url's
                (("tumblr.com/_500.x_500.",), "tumblr.com/_1280.x_1280."),  # replace is not first-only
                (("tumblr.com",), "tumblr.com"),
                (("_250.tumblr.com",), "_1280.tumblr.com"),
                (("tumblr.com_400._250.",), "tumblr.com_1280._250."),
            ],
            "edges": ["", "tumblr.com_500.", "TUMBLR.COM_500.", "tumblr_com_500.", "tumblr.com_500", "tumblr.com_1280.",
                      "_500._540._400._250.tumblr.com", "tumblr.com" + "_250." * 4, "tumblr.com/_400.", "tumblr.com/_250.",
                      "tumblr.com/_540.", "x" + WS + "tumblr.com_500.", "tumblr.com\n_500.", ALPHABET + "tumblr.com_500."],
            "generate": lambda rng: (glue(rng, ["tumblr.com", "_500.", "_540.", "_400.", "_250.", "_1280.", "/", "x", ".com"], 6),),
            "c3": "tested fragment, no theorem. The early return inside the for is a Step fold (Continue/Stop) over "
            "the literal list, then a match on the Maybe for the fall-through return; str.__contains__ and "
            "str.replace are the primitive contracts (A3). The def is annotated in its own source, so the control "
            "edits that header: `url: bool` and the `not in` guard has no contract.",
        },
        # A parameter rebound by its own lowercase, then an equality ladder. No strip: 'yes ' is 'no'.
        "sc_feas_class": {
            "path": H / "footydata/docs/site/build_ideas.py",
            "sha256": "84d9214c6e05e9ab050584b65ccff04f75c0b46500a9541bbd17992ca8815ad3",
            "sig": "def sc_feas_class(f: str) -> str:\n    pass\n",
            "builtins": {},
            "wrong": ("String.to_lower(f)", "f", "translation without the lowercase"),
            "refuse": [("f: str", "f: bool", "the parameter claimed bool", "no verified contract for .lower")],
            "examples": [
                (("yes",), "fz--yes"),
                (("YES",), "fz--yes"),
                (("Partial",), "fz--part"),
                (("partial",), "fz--part"),
                (("no",), "fz--no"),
                (("",), "fz--no"),
                (("yes ",), "fz--no"),  # no strip
                (("maybe",), "fz--no"),
            ],
            "edges": ["Yes", "yEs", "PARTIAL", "partia", "partiall", " yes", "yes\n", "NO", "fz--yes", "y", "p", WS, ALPHABET, "YES" + WS],
            "generate": lambda rng: (rng.choice(["yes", "YES", "Yes", "partial", "Partial", "PARTIAL", "no", "", "yes ", " partial", word(rng, "yesparticalNO ", 9)]),),
            "c3": "tested fragment, no theorem. Assign-to-a-parameter is a rebinding let, and the two ifs are "
            "nested matches on String.eq; str.lower is the one primitive contract (A3). The stub claims `f: str`; "
            "the control claims bool and .lower has no contract there.",
        },
        # not (a or b or c) over three substring tests: the or-chain short-circuits as nested matches.
        "is_unet_key": {
            "path": H / "kohya_ss/sd-scripts/tools/merge_models.py",
            "sha256": "32bb6b256534a1391097fdfecfa6402dff58bfccf76668010c187a92603e1a72",
            "sig": "def is_unet_key(key: str) -> bool:\n    pass\n",
            "builtins": {},
            "wrong": ('String.contains(key, "conditioner.")', "False{}", "the third guard dropped"),
            "refuse": [("-> bool", "-> str", "the return claimed str", "type mismatch")],
            "examples": [
                (("model.diffusion_model.input_blocks.0",), True),
                (("first_stage_model.encoder.norm",), False),
                (("cond_stage_model.transformer",), False),
                (("conditioner.embedders.0.weight",), False),
                (("conditioner",), True),  # the trailing dot is part of the needle
                (("",), True),
                (("xfirst_stage_modelx",), False),  # a substring test, not a prefix test
            ],
            "edges": ["conditioner.", "conditioner_", "first_stage_model", "cond_stage_model", "stage_model",
                      "first_stage_modelcond_stage_modelconditioner.", "COND_STAGE_MODEL", "model.", "." , WS,
                      "a" + WS + "conditioner.", ALPHABET, "cond_stage_mode", "first_stage_mode"],
            "generate": lambda rng: (glue(rng, ["first_stage_model", "cond_stage_model", "conditioner.", "conditioner", "model.", "x", ".", "_"], 5),),
            "c3": "tested fragment, no theorem. `not (a or b or c)` is Bool.not over two nested matches -- the "
            "or-chain's short circuit is the match itself, not an operator; str.__contains__ is the primitive "
            "contract (A3). The stub claims `-> bool`; the control claims str and the body's Bool is a type "
            "mismatch at the return.",
        },
        # LLVM lit's word regex: a backslash literal on both sides of the argument. The pin is
        # what makes the escaping testable end to end -- Python r"\b", Bend "\\b", four lanes.
        "make_word_regex": {
            "path": H / "ipad-lab/tools/build-src/apple-libtapi/src/llvm/utils/lit/lit/util.py",
            "sha256": "db00f5c2f2c20c0844765b8375a121f6cfd77795ee9c86e4cb6c0af7b8ebfe3a",
            "sig": "def make_word_regex(word: str) -> str:\n    pass\n",
            "builtins": {},
            "wrong": ('String.append("\\\\b", word)', "word", "the leading \\b dropped"),
            "refuse": [("-> str", "-> bool", "the return claimed bool", "type mismatch")],
            "examples": [
                (("foo",), "\\bfoo\\b"),
                (("",), "\\b\\b"),
                (("a b",), "\\ba b\\b"),
                (("\\b",), "\\b\\b\\b"),
                (("\\",), "\\b\\\\b"),
                (("b",), "\\bb\\b"),
            ],
            "edges": ["\\", "\\\\", "b", "\\b\\b", "x\\y", '"', "'", "\n", "\t", WS, ALPHABET, "\\" * 6, "b" * 6, "\\n"],
            "generate": lambda rng: (word(rng, "\\bnrt\"'ab ", 12),),
            "c3": "tested fragment, no theorem. Two String.appends of one raw literal; str.__add__ is the primitive "
            "contract (A3). The def has no call site in lit/, so the claim is defended from the body alone: `+` "
            "against a str literal forces both the parameter and the return. The control claims `-> bool`.",
        },
        # A parameter literally named `str`, shadowing the builtin inside the body.
        "string_begins_with": {
            "path": H / "Maestro/app/models/TTS/index_tts2/utils/xtransformers.py",
            "sha256": "3eae7a30aaaa82e82e00e3287abe9b49b30398ae00d052473695bb8860914e26",
            "sig": "def string_begins_with(prefix: str, str: str) -> bool:\n    pass\n",
            "builtins": {},
            "wrong": ("String.starts_with(str, prefix)", "String.starts_with(prefix, str)", "the arguments swapped"),
            "refuse": [("-> bool", "-> str", "the return claimed str", "type mismatch")],
            "examples": [
                (("ab", "abc"), True),
                (("", "x"), True),
                (("abc", "ab"), False),
                (("x", ""), False),
                (("", ""), True),
                (("abc", "abc"), True),
                (("b", "abc"), False),
            ],
            "edges": [("a", "a"), ("a", "A"), (WS, WS + "x"), ("\n", "\n"), (" ", " a"), ("a ", "a"),
                      ("ab", "aab"), ("aa", "aaa"), (ALPHABET[:8], ALPHABET), (ALPHABET, ALPHABET[:8]),
                      ("$", "$x"), ("\\", "\\\\"), ('"', '"q"'), ("ab", "ab")],
            "generate": lambda rng: (word(rng, "ab ", 4), word(rng, "ab ", 8)),
            "c3": "tested fragment, no theorem. One primitive contract (str.startswith = String.starts_with, A3). "
            "The interest is the header: the second parameter is named `str`, shadowing the builtin inside the "
            "body, and the stub must name it the same way. The C2 control swaps the two arguments -- the same "
            "call, the wrong way round -- and the refusal control claims `-> str`.",
        },
        # An or-chain mixing a substring test with two prefix tests.
        "is_remote_or_virtual_path": {
            "path": H / "img2threejs/forge/stage4_review/append_review.py",
            "sha256": "0ffcafa7f5e77a32c17d93ad041b88207e074d0a9b32cc6a99850ceac2195742",
            "builtins": {"str": str, "bool": bool},
            "wrong": ('String.starts_with(value, "blob:")', "False{}", "the blob: prefix dropped"),
            "refuse": [("-> bool", "-> str", "the return claimed str", "type mismatch")],
            "examples": [
                (("https://x/y.png",), True),
                (("data:image/png;base64,AA",), True),
                (("blob:http://x/1",), True),
                (("/local/p.png",), False),
                (("",), False),
                (("x://",), True),
                (("Data:x",), False),  # startswith is case-sensitive
                (("xdata:y",), False),  # a prefix test, not a substring test
            ],
            "edges": ["://", ":/", "//", "data:", "blob:", "DATA:", "blob", "a://b", " data:", "data", "\ndata:",
                      WS, ALPHABET, "blob:data://"],
            "generate": lambda rng: (glue(rng, ["://", "data:", "blob:", "http", "/", "x", ":", "Data:"], 5),),
            "c3": "tested fragment, no theorem. `a or b or c` is two nested matches; str.__contains__ and "
            "str.startswith are the primitive contracts (A3). The def is annotated in its own source, so the "
            "control edits that header to `-> bool`'s opposite and the body's Bool is a type mismatch.",
        },
        # Five chained replaces. '.pdf' is a SUBSTRING test, not a suffix test: 'x.pdfy' -> 'xy'.
        "safe_name": {
            "path": H / "Richiebot-m7/scripts/batch_gemini_ocr.py",
            "sha256": "dbe911413c3f23aeaf5d1f795ade1da067a4b4ea28aa37c3c10c56f651c081a7",
            "sig": "def safe_name(pdf_name: str) -> str:\n    pass\n",
            "builtins": {},
            "wrong": ('String.replace(pdf_name, ".pdf", "")', "pdf_name", "the .pdf pass dropped"),
            "refuse": [("pdf_name: str", "pdf_name: bool", "the parameter claimed bool", "no verified contract for .replace")],
            "examples": [
                (("My Doc.pdf",), "My_Doc"),
                (("a.pdf.pdf",), "a"),
                (("x.pdfy",), "xy"),  # a substring, not a suffix
                (("A & B (2).pdf",), "A_and_B_2"),
                (("",), ""),
                ((".pdf",), ""),
                (("()& ",), "and_"),
            ],
            "edges": [".pdf.pdf", "x.PDF", ".pdfpdf", "a(b)c", "&&", "( )", "  ", "a&b", "(", ")", "&",
                      WS, ALPHABET, "a .pdf b"],
            "generate": lambda rng: (glue(rng, [".pdf", " ", "&", "(", ")", "a", ".", "pdf"], 7),),
            "c3": "tested fragment, no theorem. Five chained str.replace = five String.replace (A3). The same body "
            "is copied into three files in that repo; this is the one with call sites, and they pass a filename "
            "row, so `pdf_name: str` is defended from the body and from them. The control claims bool.",
        },
        # HTML escaping. '&' must go first or the ampersands it introduces are escaped again.
        "esc": {
            "path": H / "voice-clone-lab/meetnow-2014-main-voice/richie-compare-2026-09-08/build_page.py",
            "sha256": "7d28c6549e007328b60f0d43d1789af57341f32cbf403ca2b335449f6370e737",
            "builtins": {"str": str},
            "wrong": ('String.replace(s, "&", "&amp;")', "s", "the ampersand pass dropped"),
            "refuse": [("-> str", "-> bool", "the return claimed bool", "type mismatch")],
            "examples": [
                (("<a>&",), "&lt;a&gt;&amp;"),
                (("&amp;",), "&amp;amp;"),  # already-escaped text is escaped again
                (("",), ""),
                (("<>&",), "&lt;&gt;&amp;"),
                (("&&",), "&amp;&amp;"),
                (("a<b>c",), "a&lt;b&gt;c"),
            ],
            "edges": ["&", "<", ">", "&lt;", "<&>", "&#39;", '"', "'", "<a href=\"x\">", "&" * 5, "<" * 5,
                      WS, ALPHABET, "a\n<b>\n&"],
            "generate": lambda rng: (word(rng, "&<>a;\"' ", 14),),
            "c3": "tested fragment, no theorem. Three chained str.replace (A3), and the order is the contract: "
            "the '&' pass runs first, so the ampersands the later passes introduce are not escaped again -- the "
            "C2 control drops exactly that pass. The def is annotated in its source; the refusal control edits "
            "that header.",
        },
        # A bool parameter and a conditional expression. Two inputs is the WHOLE domain, so C2
        # here is exhaustive rather than sampled -- the only demo in the battery of which that is true.
        "canon_bool": {
            "path": H / "glyph/py/glyph/loose.py",
            "sha256": "24a41ad9b22c5c86be3fdf20c78ab2fb099cf26032b48767939eda2096c30fae",
            "builtins": {"bool": bool, "str": str},
            "wrong": ('"t"', '"f"', "both branches the same"),
            "refuse": [("v: bool", "v: str", "the parameter claimed str", "truthiness of a non-bool is outside the fragment")],
            "examples": [((True,), "t"), ((False,), "f")],
            "edges": [True, False],
            "generate": lambda rng: (rng.random() < 0.5,),
            "c3": "tested fragment, no theorem -- but the fixtures are the entire input domain: bool has two "
            "values and both are here, so C2 for this def is exhaustive, not sampled, and no primitive string "
            "contract is assumed (the IfExp is a match on the parameter itself). That is a stronger C2 than any "
            "other demo in the battery, and it is still not C3: the claim tested is `canon_bool` in Bend agrees "
            "with `canon_bool` in CPython, not a theorem about either.",
        },
    }
