#!/usr/bin/env bash
# `run.sh [prefix]`. Per specimen: the oracle (NAME_gen.py prints the whole fixture from CPython; the
# checked-in file must be that byte for byte), then four lanes against its #| block: strict check,
# interpreter, emitted JS, C. The comparison path is first held to a deliberately wrong #| fixture.
set -uo pipefail
cd "$(dirname "$0")/../.."
export PATH="$HOME/.local/bin:$PATH"
# Pin the environment alongside the bytes: the interpreter's daily check
# prints a one-line update notice to stderr when upstream has a newer
# release, and these lanes byte-compare raw stdout+stderr. The notice is
# network state, not output; the switch is the interpreter's own.
export BEND_NO_TELEMETRY=1
work=$(mktemp -d /tmp/bend-power.XXXXXX)
trap 'rm -rf -- "$work"' EXIT
pass=0
fail=0
printf 'All terms check.\n' > "$work/checked"

check() {
  bun -e '
    import * as B from "./bend2/bend.ts";
    const book = B.book_nil();
    await B.book_load(book, process.argv[1], "", new Map());
    B.book_valid(book);
    if (book.hols + book.open) process.exit(1);
    console.log("All terms check.");' "$1"
}
export -f check

run() {
  local label=$1 expected=$2 status=0
  shift 2
  : > "$work/diff"
  timeout "${POWER_TIMEOUT:-300}" "$@" > "$work/actual" 2>&1 || status=$?
  if [ "$status" -eq 0 ] && diff -u "$expected" "$work/actual" > "$work/diff"; then
    printf 'ok   %-20s [%s]\n' "$name" "$label"
    pass=$((pass + 1))
  else
    printf 'FAIL %-20s [%s] status=%s\n' "$name" "$label" "$status"
    head -15 "$work/actual" "$work/diff"
    fail=$((fail + 1))
  fi
}

cat > "$work/wrong.bend" <<'BEND'
import Base
def main() -> Nat:
  1n
#|2n
BEND
name=wrong_fixture_control
sed -n 's/^#|//p' "$work/wrong.bend" > "$work/wrong-expected"
before=$fail
run interpret "$work/wrong-expected" bun bend2/main.ts "$work/wrong.bend" > "$work/control"
if [ "$fail" -eq "$((before + 1))" ] && [ "$(cat "$work/actual")" = "1n" ]; then
  fail=$before
  printf 'ok   wrong #| fixture detected as failing\n'
else
  printf 'FAIL wrong #| fixture escaped detection\n'
  fail=$((fail + 1))
fi

for t in tests/power/*.bend; do
  name=$(basename "$t" .bend)
  if [ -n "${1:-}" ] && [[ "$name" != "$1"* ]]; then
    continue
  fi
  sed -n 's/^#|//p' "$t" > "$work/expected"
  if [ ! -s "$work/expected" ]; then
    printf 'FAIL %s: missing #| block\n' "$name"
    fail=$((fail + 1))
    continue
  fi
  if rg -q '@unsafe|\?TODO' "$t" power/; then
    printf 'FAIL unsafe or open goal\n'; fail=$((fail + 1)); continue
  fi
  if [ -f "tests/power/${name}_gen.py" ]; then
    run oracle "$t" python3 "tests/power/${name}_gen.py"
  fi
  run check "$work/checked" bash -c 'check "$1"' _ "$t"
  # a library that forks one array (Array.fork, base's O(1) shared handle)
  # makes the checker print which defs rely on it; that note is not output
  run interpret "$work/expected" bash -c 'set -o pipefail; bun bend2/main.ts "$1" 2>&1 |
    sed "/^All terms check, but .* on unsafe or foreign code:\$/,/^[^-]/{/^All terms check, but/d;/^- /d}"' _ "$t"
  for lane in js c; do
    target="$work/$name"
    [ "$lane" = js ] && target="$target.js"
    if timeout 180 bun bend2/main.ts "$t" -o "$target" > "$work/build" 2>&1; then
      if [ "$lane" = js ]; then
        run js "$work/expected" bun "$target"
      else
        run c "$work/expected" "$target" --gpu off
        # a schedule must not change an answer: the same binary on one thread
        run c-1thread "$work/expected" "$target" --gpu off --threads 1
      fi
    else
      printf 'FAIL %-20s [%s build]\n' "$name" "$lane"
      head -20 "$work/build"
      fail=$((fail + 1))
    fi
  done
done
printf '\nPower PASS: %d, FAIL: %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
