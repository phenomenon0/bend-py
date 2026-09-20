"""Lexer scaling guard: PY_MODE=lex wall time at N and 4N tokens (C lane).

Linear lexing gives a ratio near 4, quadratic 16. The hand lexer re-conses the
head it peeked (`SCon{h, t}` in scanner.bend's span/quoted); that is O(1) only
while the runtime keeps cons-after-uncons a view (8f782000). Before that commit
this same lexer measured 137 s at 986 KB (4x-size ratio 15.6); this guard reads 13.7 there, 3.8 now.

PY_MODE=parse rides the same file: its N lines are one block of N statements.
The Block state appended each line to its statements (quadratic: 0.98 s at
10000 lines, 12.3 s at 40000, ratio 12.5); it now pushes reversed and reverses
once (0.30 s, 1.18 s, ratio 3.9). `;` chains (Simple) had and lost the same shape.
"""

from normalize import OUT
from diff import build
import os
import subprocess
import time

LINE = b"x = f(a, 'b') + 12  # c\n"
SIZES = (10000, 40000)
LIMIT = {"lex": 8.0, "parse": 6.0}  # parse carries the linear lex: the old Block reads 8.7 here


def seconds(lines, mode):
    path = OUT / f"lexscale-{lines}.py"
    path.write_bytes(LINE * lines)
    best = None
    for _ in range(3):
        # timeout= makes subprocess poll the child on a 50 ms grid: readings are that coarse.
        start = time.monotonic()
        p = subprocess.run(
            [str(OUT / "parser"), "--gpu", "off"],
            env=dict(os.environ, PY_SOURCE=str(path), PY_MODE=mode),
            stdout=subprocess.DEVNULL,
            timeout=300,
        )
        took = time.monotonic() - start
        assert p.returncode == 0, p.returncode
        best = took if best is None else min(best, took)
    return best


def main():
    build()
    bad = False
    for mode in ("lex", "parse"):
        small, large = (seconds(n, mode) for n in SIZES)
        ratio = large / small
        print(
            f"lexscale {mode}: {SIZES[0]} lines {small:.3f}s, {SIZES[1]} lines {large:.3f}s, ratio {ratio:.2f} (limit {LIMIT[mode]})"
        )
        bad = bad or ratio > LIMIT[mode]
    return bad


if __name__ == "__main__":
    raise SystemExit(main())
