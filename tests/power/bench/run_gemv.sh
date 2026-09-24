#!/usr/bin/env bash
# The gemv honesty bench, under POWER.md's protocol:
#
#   bash tests/power/bench/run_gemv.sh
#
# Checksums first -- the interpreter, the C twin, one thread and sixteen -- and
# only then the clock, under /tmp/bend-bench.lock, medians of three. The load is
# printed because a bench run on a loaded machine measures the load.
#
# The last block is the number the twin is not allowed to be. twin_gemv.c is
# strictly ordered and scalar, which is the honest twin of a Bend fold; the same
# file at -march=native -ffast-math is what the hardware can actually do with
# this loop, and its checksum differs because reassociation is exactly what it
# was given permission to do. Bend has no way to ask for that today, so the gap
# is reported rather than hidden inside the twin.
set -u
cd "$(dirname "$0")/../../.."
export BEND_NO_TELEMETRY=1
work=$(mktemp -d); trap 'rm -rf "$work" tests/power/bench/_gemv_small.bend' EXIT
med() { for _ in 1 2 3; do s=$(date +%s.%N); "$@" > /dev/null; e=$(date +%s.%N); echo "$e - $s" | bc; done | sort -n | sed -n 2p; }

echo "== machine =="
uname -srm
${CC:-clang} --version | head -1
echo "bun $(bun --version)"
echo "bend $(bun bend2/main.ts version | tail -1)"
uptime

echo
echo "== the interpret lane, at the size it can reach =="
# gemv.bend's main returns U32, which the interpreter normalizes as a term -- and
# F32 primitives do not reduce there, so a bench main is a symbolic tree the
# interpreter never finishes folding. Routing the same call through U32.show is
# what forces it, and 8 x 8 x 4 is the size it can finish.
cat > tests/power/bench/_gemv_small.bend <<'BEND'
import Base
import ./gemv.bend as G
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(U32.show(G.gemv(4n, 0, 8, 8, 6n, 3n, 3n)))
BEND
${CC:-clang} -O3 -o "$work/twin" tests/power/bench/twin_gemv.c -lm || exit 1
want=$("$work/twin" small)
got=$(bun bend2/main.ts tests/power/bench/_gemv_small.bend | tail -1)
rm -f tests/power/bench/_gemv_small.bend   # out of run.sh's glob before it runs
if [ "$want" != "$got" ]; then echo "FAIL interpret: C $want, interpret $got"; exit 1; fi
echo "interpret $got == C $want"

echo
echo "== the rows =="
# one lock for every clock below: run.sh times inside itself, so the lock is
# held here rather than wrapped around it, and a nested flock would deadlock
exec 9>/tmp/bend-bench.lock; flock 9
bash tests/power/bench/run.sh gemv || exit 1

echo
echo "== reference: the same C loop with reassociation and SIMD allowed =="
${CC:-clang} -O3 -march=native -ffast-math -o "$work/fast" tests/power/bench/twin_gemv.c -lm || exit 1
printf 'twin (ordered, scalar)  %8.2f  checksum %s\n' "$(med "$work/twin")" "$("$work/twin")"
printf 'fast (reassociated)     %8.2f  checksum %s\n' "$(med "$work/fast")" "$("$work/fast")"
