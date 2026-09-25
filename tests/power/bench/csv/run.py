#!/usr/bin/env python3
# The csv bench: a generated CSV of MB megabytes (default 50) through
# Csv.fold_file in the C lane, beside CPython's csv and a naive C reader.
# All three must print the same records, fields and content bytes before
# any time is kept. Medians of three runs; peak RSS from wait4.
#   python3 tests/power/bench/csv/run.py [MB]
import csv
import os
import statistics
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(HERE))))
MB = int(sys.argv[1]) if len(sys.argv) > 1 else 50

PY = r'''
import csv, sys
recs = fields = size = 0
with open(sys.argv[1], newline="", encoding="latin-1") as f:
    for r in csv.reader(f, strict=True):
        recs += 1
        fields += len(r)
        size += sum(len(x) for x in r)
print(recs, fields, size)
'''


# a child forked from this Python would inherit its high-water mark, so the
# peak is taken by a small C launcher instead
RSS_C = r'''
#include <stdio.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>
int main(int argc, char **argv) {
  pid_t p = fork();
  if (p == 0) { execv(argv[1], argv + 1); return 127; }
  int st; struct rusage ru;
  wait4(p, &st, 0, &ru);
  fprintf(stderr, "maxrss %ld\n", ru.ru_maxrss);
  return WEXITSTATUS(st);
}
'''


def timed(cmd, launcher):
    t = time.perf_counter()
    r = subprocess.run([launcher] + cmd, capture_output=True, text=True)
    sec = time.perf_counter() - t
    rss = int([l for l in r.stderr.split("\n") if l.startswith("maxrss ")][-1].split()[1])
    return sec, rss, r.stdout.strip(), r.returncode


def main():
    work = tempfile.mkdtemp(prefix="bend-csv-bench.")
    data = os.path.join(work, "bench.csv")
    subprocess.run([sys.executable, os.path.join(HERE, "gen.py"), data, str(MB)], check=True)
    size = os.path.getsize(data)
    env = dict(os.environ, BEND_NO_TELEMETRY="1")
    subprocess.run(["bun", "bend2/main.ts", os.path.join(HERE, "read.bend"), "-o",
                    os.path.join(work, "read")], cwd=ROOT, check=True, env=env)
    subprocess.run([os.environ.get("CC", "cc"), "-O3", "-o", os.path.join(work, "naive"),
                    os.path.join(HERE, "naive.c")], check=True)
    open(os.path.join(work, "py.py"), "w").write(PY)
    open(os.path.join(work, "rss.c"), "w").write(RSS_C)
    launcher = os.path.join(work, "rss")
    subprocess.run([os.environ.get("CC", "cc"), "-O2", "-o", launcher, os.path.join(work, "rss.c")], check=True)
    rows = [
        ("bend csv, 1 thread", [os.path.join(work, "read"), "--gpu", "off", "--threads", "1", data]),
        ("bend csv", [os.path.join(work, "read"), "--gpu", "off", data]),
        ("naive C", [os.path.join(work, "naive"), data]),
        ("CPython csv", [sys.executable, os.path.join(work, "py.py"), data]),
    ]
    want = None
    print("%d bytes (%.1f MB), %s" % (size, size / 1e6, open("/proc/loadavg").read().split()[0]
                                      + " load"))
    print("%-20s %8s %9s %10s  %s" % ("reader", "sec", "MB/s", "peak RSS", "records fields bytes"))
    for name, cmd in rows:
        runs = [timed(cmd, launcher) for _ in range(3)]
        outs = {r[2] for r in runs}
        assert len(outs) == 1 and all(r[3] == 0 for r in runs), (name, runs)
        out = outs.pop()
        if want is None:
            want = out
        assert out == want, (name, out, want)
        sec = statistics.median(r[0] for r in runs)
        rss = max(r[1] for r in runs)
        print("%-20s %8.2f %9.1f %8.1f MB  %s" % (name, sec, size / 1e6 / sec, rss / 1024, out))
    subprocess.run(["rm", "-rf", work])


main()
