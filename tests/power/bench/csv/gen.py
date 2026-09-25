#!/usr/bin/env python3
# A deterministic CSV of about MB megabytes (default 50) for the csv bench:
#   python3 tests/power/bench/csv/gen.py OUT [MB]
# Ten fields a record, CRLF line ends. Most fields are unquoted (numbers,
# words, empty), about one in six is quoted, and a quoted one may hold a
# comma, a doubled quote or a CRLF -- the shapes that cost a reader. No
# blank lines, so CPython's count of records is this file's.
import random
import sys

out = sys.argv[1]
target = int(sys.argv[2] if len(sys.argv) > 2 else 50) * 1000 * 1000
rng = random.Random(4180)
WORDS = [w.encode() for w in "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi "
         "omicron pi rho sigma tau upsilon phi chi psi omega".split()] + ["café".encode(),
         "naïve".encode(), "日本".encode()]


def field():
    r = rng.random()
    if r < 0.30:
        return str(rng.randrange(0, 10 ** rng.randrange(1, 10))).encode()
    if r < 0.60:
        return b" ".join(rng.choice(WORDS) for _ in range(rng.randrange(1, 4)))
    if r < 0.70:
        return b""
    if r < 0.84:
        return b"%d.%02d" % (rng.randrange(0, 100000), rng.randrange(0, 100))
    # quoted: a comma, a doubled quote, a line end inside
    parts = [rng.choice(WORDS) for _ in range(rng.randrange(1, 5))]
    sep = rng.choice([b", ", b' ""q"" ', b"\r\n", b" "])
    return b'"' + sep.join(parts) + b'"'


n = 0
with open(out, "wb") as f:
    buf = []
    size = 0
    while size < target:
        line = b",".join(field() for _ in range(10)) + b"\r\n"
        buf.append(line)
        size += len(line)
        n += 1
        if len(buf) >= 4096:
            f.write(b"".join(buf))
            buf = []
    f.write(b"".join(buf))
print("%s: %d records, %d bytes" % (out, n, size))
