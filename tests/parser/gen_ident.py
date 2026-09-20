"""Prints demos/python/unicode.bend's identifier tables from the pinned oracle (CPython 3.11, Unicode 14.0.0).

Identifier tokens are runs of `\\w` (the lexer's `word`), so three tables decide a non-ASCII one:
  not_continue = \\w - XID_Continue            -> Syntax anywhere
  not_start    = (\\w & XID_Continue) - XID_Start -> Syntax in first place
  unstable     = \\w & (NFKC changes it | ccc != 0 | second of a composition pair) -> Unsupported
An identifier with no `unstable` scalar is its own NFKC form (asserted below), so it is emitted as written.
"""
import re
import sys
import unicodedata as u

assert sys.version_info[:2] == (3, 11) and u.unidata_version == "14.0.0"
ALL = range(128, 0x110000)
W = {c for c in ALL if re.fullmatch(r"\w", chr(c))}
XC = {c for c in ALL if ("a" + chr(c)).isidentifier()}
XS = {c for c in ALL if chr(c).isidentifier()}
SECONDS = set(range(0x1161, 0x1176)) | set(range(0x11A8, 0x11C3))
for c in range(0x110000):
    d = u.decomposition(chr(c)).split()
    if len(d) == 2 and not d[0].startswith("<"):
        SECONDS.add(int(d[1], 16))
UNSTABLE = {c for c in XC if u.normalize("NFKC", chr(c)) != chr(c) or u.combining(chr(c)) or c in SECONDS}
for c in XC - UNSTABLE:  # a stable scalar never joins what precedes it
    head = u.normalize("NFKD", chr(c))[0]
    assert not u.combining(head) and ord(head) not in SECONDS, hex(c)


def ranges(cs):
    out = []
    for c in sorted(cs):
        if out and c == out[-1][1] + 1:
            out[-1][1] = c
        else:
            out.append([c, c])
    return out


def tree(rs):
    if not rs:
        return "Empty{}"
    m = len(rs) // 2
    return "Range{%d, %d, %s, %s}" % (rs[m][0], rs[m][1], tree(rs[:m]), tree(rs[m + 1:]))


if __name__ == "__main__":
    for name, cs in (("not_continue", W - XC), ("not_start", (W & XC) - XS), ("unstable", W & UNSTABLE)):
        print("def %s(n: U32) -> Bool:\n  member(%s, n)\n" % (name, tree(ranges(cs))))
