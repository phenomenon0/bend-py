#!/usr/bin/env python3
# The deflate bench: MB megabytes (default 10) of generated text compressed
# at levels 1, 6 and 9 and inflated back, power/deflate.bend in the C lane
# (codec.bend, one thread) beside CPython's zlib. Before any time is kept,
# zlib must inflate our stream to the input and our inflate must read
# zlib's stream to the input. MB/s of input, medians of three runs; the
# Bend times are whole processes that read the input file and write
# nothing (the checks write in runs of their own).
#   python3 tests/power/bench/deflate/run.py [MB]
import os
import statistics
import subprocess
import sys
import tempfile
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(HERE))))
MB = int(sys.argv[1]) if len(sys.argv) > 1 else 10
LEVELS = [1, 6, 9]

WORDS = ("the of and to in a is that for it as was with be by on not he i this are or his from at "
         "which but have an they you were her she there been one all we their has would when if so "
         "no will more can out about who had them some into time only what could new other than then "
         "server request response header gzip deflate stream window buffer length distance literal "
         "compression huffman table code symbol block bytes data input output chunk proof law bend "
         "parallel thread kernel memory cache latency throughput connection socket client proxy nginx").split()


# deterministic prose: a Zipf-ish vocabulary, some capitals, commas and
# numbers, lines of about 70 characters
def text(n, seed=12345):
    x, out, size, line = seed, [], 0, 0
    while size < n:
        x = (x * 1103515245 + 12345) & 0x7FFFFFFF
        w = WORDS[int(len(WORDS) * (((x >> 8) % 1000) / 1000.0) ** 2.2)]
        if (x >> 4) % 17 == 0:
            w = w.capitalize()
        if (x >> 3) % 23 == 0:
            w += ","
        if (x >> 5) % 29 == 0:
            w += str((x >> 10) % 1000)
        out.append(w)
        size += len(w) + 1
        line += len(w) + 1
        if line > 70:
            out.append("\n")
            line = 0
    return " ".join(out).replace(" \n ", "\n").encode()[:n]


def med(f):
    xs = []
    for _ in range(3):
        t = time.perf_counter()
        r = f()
        xs.append(time.perf_counter() - t)
    return statistics.median(xs), r


def main():
    work = tempfile.mkdtemp(prefix="bend-deflate-bench.")
    exe = os.path.join(work, "codec")
    subprocess.run(["bun", os.path.join(ROOT, "bend2", "main.ts"), os.path.join(HERE, "codec.bend"), "-o", exe],
                   check=True, cwd=ROOT)
    data = text(MB * 1000 * 1000)
    src = os.path.join(work, "in.txt")
    open(src, "wb").write(data)
    mb = len(data) / 1e6
    run = lambda *a: subprocess.run([exe, *a, "--gpu", "off", "--threads", "1"], capture_output=True, text=True)
    print("%.1f MB of text; MB/s of input, medians of 3" % mb)
    print("%-3s %22s %22s %22s %22s" % ("", "zlib compress", "bend compress", "zlib inflate", "bend inflate"))
    for lv in LEVELS:
        def zc():
            c = zlib.compressobj(lv, zlib.DEFLATED, -15)
            return c.compress(data) + c.flush()
        tzc, z = med(zc)
        tzd, back = med(lambda: zlib.decompress(z, -15))
        assert back == data
        ours = os.path.join(work, "ours.%d" % lv)
        run("c", str(lv), src, ours)
        tbc, r = med(lambda: run("c", str(lv), src, "-"))
        oz = open(ours, "rb").read()
        if zlib.decompress(oz, -15) != data:
            sys.exit("L%d: zlib does not inflate our stream to the input" % lv)
        theirs = os.path.join(work, "zlib.%d" % lv)
        open(theirs, "wb").write(z)
        back = os.path.join(work, "back")
        r = run("d", theirs, back)
        tbd, r2 = med(lambda: run("d", theirs, "-"))
        if open(back, "rb").read() != data:
            sys.exit("L%d: our inflate of zlib's stream is not the input: %s" % (lv, r.stdout.strip()))
        print("L%d  %9.1f (%8d B) %9.1f (%8d B) %22.1f %22.1f" % (
            lv, mb / tzc, len(z), mb / tbc, len(oz), mb / tzd, mb / tbd))
        sys.stdout.flush()


main()
