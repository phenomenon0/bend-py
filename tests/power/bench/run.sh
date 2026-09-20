#!/usr/bin/env bash
# The power benches against their C twins: bash tests/power/bench/run.sh [prefix]
# A row is only timed once Bend and C print the same checksum. Medians of three.
set -u
cd "$(dirname "$0")/../../.."
here=tests/power/bench
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
${CC:-clang} -O3 -o "$work/twins" $here/twins.c -lm || exit 1
med() { for _ in 1 2 3; do s=$(date +%s.%N); "$@" > /dev/null; e=$(date +%s.%N); echo "$e - $s" | bc; done | sort -n | sed -n 2p; }
bad=0
printf '%-10s %8s %8s %8s %7s %7s\n' bench C bend-1T bend-16T 1T/C 1T/16T
for t in $here/*.bend; do
  # rng and topk fork into their sequential twin's answer; scan's blocks do not
  name=$(basename "$t" .bend); twin=$name
  case $name in rng_par | topk_par) twin=${name%_par} ;; esac
  [ -n "${1:-}" ] && [[ "$name" != "$1"* ]] && continue
  bun bend2/main.ts "$t" -o "$work/$name" > "$work/build" 2>&1 || { echo "FAIL $name build"; head -5 "$work/build"; bad=1; continue; }
  want=$("$work/twins" "$twin"); got1=$("$work/$name" --gpu off --threads 1); got16=$("$work/$name" --gpu off --threads 16)
  if [ "$want" != "$got1" ] || [ "$want" != "$got16" ]; then echo "FAIL $name: C $want, 1T $got1, 16T $got16"; bad=1; continue; fi
  c=$(med "$work/twins" "$twin"); b1=$(med "$work/$name" --gpu off --threads 1); b16=$(med "$work/$name" --gpu off --threads 16)
  printf '%-10s %8.2f %8.2f %8.2f %6.1fx %6.1fx\n' "$name" "$c" "$b1" "$b16" "$(echo "$b1 / $c" | bc -l)" "$(echo "$b1 / $b16" | bc -l)"
done
exit $bad
