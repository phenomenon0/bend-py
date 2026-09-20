"""Pinned, non-executing CPython oracle and the two independent comparison passes."""
import os
import sys

ORACLE = "/home/omen/.hermes/hermes-agent/venv/bin/python3"
VERSION = (3, 11, 15)
if os.path.abspath(sys.executable) != ORACLE:
    os.execv(ORACLE, [ORACLE, *sys.argv])
if sys.version_info[:3] != VERSION or sys.implementation.name != "cpython":
    raise SystemExit(f"Pinned oracle changed: {ORACLE}: {sys.version}")

import ast
import hashlib
import io
import json
import platform
import re
import tokenize
import warnings
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "tests/parser/_out"
OUT.mkdir(exist_ok=True)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def pin():
    data = {
        "executable": sys.executable, "realpath": os.path.realpath(sys.executable),
        "version": sys.version, "implementation": platform.python_implementation(),
        "sha256": {str(p): sha(p) for p in [sys.executable, ast.__file__, tokenize.__file__]},
        "ast_call": "ast.parse(source, feature_version=(3,11), type_comments=False)",
        "notes": [
            "200 nested parentheses accepted; 201 rejected by ast.parse",
            "ast.parse accepts return/break/continue outside a function/loop (no compile scope checks)",
            "AST columns are UTF-8 bytes; tokenize columns and Bend columns are code points",
            "RecursionError/MemoryError/timeouts are oracle failures, never parser verdicts",
            "Constant value = repr(literal_eval(raw)); implicit strings wrapped in parentheses",
            "type_comments=False; trivia and incidental parentheses are omitted",
            "f-string text Constants: the wire carries `_parts` [kind, text] pieces (s: plain token, f: f-string literal text, v: verbatim) decoded and joined here; the oracle side uses repr(node.value) because their source spans cover the whole string run",
        ],
    }
    (OUT / "oracle.json").write_text(json.dumps(data, indent=2) + "\n")
    return data


def intake(raw):
    """Strict UTF-8/BOM, coding cookies excluded before decoding."""
    encoding, _ = tokenize.detect_encoding(io.BytesIO(raw).readline)
    if encoding.lower().replace("_", "-") not in {"utf-8", "utf-8-sig"}:
        raise ValueError("coding-cookie:" + encoding)
    return raw.decode("utf-8-sig")


def boundaries(source):
    result = []
    for line in source.split("\n"):
        mapping, byte = {0: 0}, 0
        for col, char in enumerate(line, 1):
            byte += len(char.encode("utf-8"))
            mapping[byte] = col
        result.append(mapping)
    return result


def literal(raw):
    # Newline protects a closing parenthesis from a final concatenation comment.
    return repr(ast.literal_eval("(" + raw + "\n)"))


def part(kind, text):
    """One `_parts` piece of an f-string Constant: a plain token, f-string literal text, or verbatim text."""
    if kind == "s":
        return ast.literal_eval("(" + text + "\n)")
    if kind == "v":
        return text.replace("\r\n", "\n")
    body = re.sub(r'\\.|["\n\r]|\\$', lambda m: m[0] if len(m[0]) == 2 else
                  {'"': '\\"', "\n": "\\n", "\r": "\\r", "\\": "\\\\"}[m[0]], text, flags=re.S)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        return ast.literal_eval('"' + body + '"')


def oracle(source):
    tree = ast.parse(source, feature_version=(3, 11), type_comments=False)
    maps = boundaries(source)
    lines = ast._splitlines_no_ff(source)

    def segment(node):
        # ast.get_source_segment with the line split hoisted: per call it is O(source), quadratic on ~1 MB files.
        lo, hi, a, b = node.lineno - 1, node.end_lineno - 1, node.col_offset, node.end_col_offset
        if lo == hi:
            return lines[lo].encode()[a:b].decode()
        return "".join([lines[lo].encode()[a:].decode()] + lines[lo + 1:hi] + [lines[hi].encode()[:b].decode()])

    def convert(node, in_fstring=False):
        if isinstance(node, ast.AST):
            d = {"tag": type(node).__name__}
            for field, value in ast.iter_fields(node):
                if isinstance(node, ast.Constant) and field == "value":
                    d[field] = repr(node.value) if in_fstring else literal(segment(node))
                else:
                    d[field] = convert(value, isinstance(node, ast.JoinedStr))
            if hasattr(node, "lineno"):
                d["_loc"] = [node.lineno, maps[node.lineno - 1][node.col_offset],
                             node.end_lineno, maps[node.end_lineno - 1][node.end_col_offset]]
            return d
        if isinstance(node, list):
            return [convert(x, in_fstring) for x in node]
        return node

    return convert(tree), tree


def normalize(value):
    """The Bend wire carries raw constants; only literal values use the host."""
    if isinstance(value, list):
        return [normalize(x) for x in value]
    if not isinstance(value, dict):
        return value
    if value.get("tag") == "Constant" and "_raw" in value:
        value = {"tag": "Constant", "value": literal(value["_raw"]),
                 "kind": value.get("kind"), "_loc": value["_loc"]}
    if value.get("tag") == "Constant" and "_parts" in value:
        value = {"tag": "Constant", "value": repr("".join(part(k, t) for k, t in value["_parts"])),
                 "kind": value.get("kind"), "_loc": value["_loc"]}
    return {k: normalize(v) for k, v in value.items()}


def split(value, path="$", locations=None):
    """Every location is compared by AST path; no span sampling."""
    if locations is None:
        locations = {}
    if isinstance(value, dict):
        if "_loc" in value:
            locations[path] = value["_loc"]
        return ({k: split(v, path + "." + k, locations)[0]
                 for k, v in value.items() if k != "_loc"}, locations)
    if isinstance(value, list):
        return ([split(v, f"{path}[{i}]", locations)[0] for i, v in enumerate(value)], locations)
    return value, locations


def differences(want, got, path="$"):
    if type(want) is not type(got):
        return [{"path": path, "want": want, "got": got}]
    if isinstance(want, dict):
        result = []
        for key in dict.fromkeys([*want, *got]):
            if key not in want or key not in got:
                result.append({"path": path + "." + key, "missing": "want" if key not in want else "got"})
            else:
                result.extend(differences(want[key], got[key], path + "." + key))
        return result
    if isinstance(want, list):
        if len(want) != len(got):
            return [{"path": path, "lengths": [len(want), len(got)]}]
        return [d for i, (a, b) in enumerate(zip(want, got)) for d in differences(a, b, f"{path}[{i}]")]
    return [] if want == got else [{"path": path, "want": want, "got": got}]


SUPPORTED = set("""Module Constant Name Load Store Del Attribute Subscript Tuple List Starred
Set Dict UnaryOp UAdd USub Invert Not BinOp Add Sub Mult MatMult Div FloorDiv Mod Pow
LShift RShift BitOr BitXor BitAnd BoolOp And Or Compare Eq NotEq Lt LtE Gt GtE Is IsNot In NotIn
IfExp Call keyword Assign AugAssign Expr If While Return Pass Break Continue
Lambda arguments arg FunctionDef For Global Nonlocal Delete Assert Raise Try ExceptHandler With withitem
Import ImportFrom alias ClassDef Slice JoinedStr FormattedValue
ListComp SetComp DictComp GeneratorExp comprehension AnnAssign Yield YieldFrom
AsyncFunctionDef AsyncFor AsyncWith Await NamedExpr TryStar
Match match_case MatchValue MatchSingleton MatchSequence MatchMapping MatchClass MatchStar MatchAs MatchOr""".split())


def supported(tree, source=None):
    # A non-ASCII identifier is in the slice when NFKC leaves it alone (gen_ident's UNSTABLE, scalar by scalar). One with a
    # mark is not: tokenize's NAME is `\w`, which has no marks, so it reads ERRORTOKEN there and the lexer follows tokenize.
    if source is not None:
        for t in tokenize.generate_tokens(io.StringIO(source).readline):
            # An f-string is one STRING token here: an unstable scalar anywhere in it counts, its literal text included.
            fstring = t.type == tokenize.STRING and "f" in t.string[:t.string.index(t.string[-1])].lower()
            if (fstring or t.type in (tokenize.NAME, tokenize.ERRORTOKEN)) and not t.string.isascii():
                from gen_ident import UNSTABLE
                if t.type == tokenize.ERRORTOKEN or any(ord(c) in UNSTABLE for c in t.string):
                    return False
        return all(type(node).__name__ in SUPPORTED for node in ast.walk(tree))
    return all(type(node).__name__ in SUPPORTED and
               not (isinstance(node, ast.Name) and not node.id.isascii()) and
               not (isinstance(node, ast.Attribute) and not node.attr.isascii())
               for node in ast.walk(tree))
