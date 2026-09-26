#!/usr/bin/env bash
# `run.sh [prefix]`, e.g. `run.sh totality` (L1), `run.sh alias` (L2), `run.sh coverage` (L3) or `run.sh modules` (L4). Four lanes per specimen: strict check,
# interpreter, emitted JS, C; then the CPython evidence (semantics.py).
set -uo pipefail
cd "$(dirname "$0")/../.."
export PATH="$HOME/.local/bin:$PATH"
# Pin the environment alongside the bytes: the interpreter's daily check
# prints a one-line update notice to stderr when upstream has a newer
# release, and these lanes byte-compare raw stdout+stderr. The notice is
# network state, not output; the switch is the interpreter's own.
export BEND_NO_TELEMETRY=1
mkdir -p tests/lint/_out
work=$(mktemp -d /tmp/bend-lint.XXXXXX)
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

run() {
  local label=$1 expected=$2 status=0
  shift 2
  : > "$work/diff"
  timeout "${LINT_TIMEOUT:-300}" "$@" > "$work/actual" 2>&1 || status=$?
  if [ "$status" -eq 0 ] && diff -u "$expected" "$work/actual" > "$work/diff"; then
    printf 'ok   %-20s [%s]\n' "$name" "$label"
    pass=$((pass + 1))
  else
    printf 'FAIL %-20s [%s] status=%s\n' "$name" "$label" "$status"
    head -15 "$work/actual" "$work/diff"
    fail=$((fail + 1))
  fi
}

# Exercise the SAME comparison path with a deliberately wrong #| fixture.
cat > tests/lint/_out/wrong.bend <<'BEND'
import Base
def main() -> Nat:
  1n
#|2n
BEND
name=wrong_fixture_control
sed -n 's/^#|//p' tests/lint/_out/wrong.bend > "$work/wrong-expected"
before=$fail
run interpret "$work/wrong-expected" bun bend2/main.ts tests/lint/_out/wrong.bend > "$work/control"
if [ "$fail" -eq "$((before + 1))" ] && [ "$(cat "$work/actual")" = "1n" ]; then
  fail=$before
  printf 'ok   wrong #| fixture detected as failing\n'
else
  printf 'FAIL wrong #| fixture escaped detection\n'
  fail=$((fail + 1))
fi

# Tripwire (shapefix): a single string LITERAL over 1200 chars expands to a Cons
# spine and can overflow the bun frontend stack under load; shape literals with
# ++ chains of <=512-char pieces (byte-identical).
python3 - <<'GUARD' || fail=$((fail + 1))
import re, glob, sys
worst = (0, "", 0)
for f in sorted(glob.glob("tests/lint/*.bend")):
    for n, line in enumerate(open(f, encoding="utf-8"), 1):
        if line.startswith("#|"): continue  # expected output is a comment, not a literal
        for m in re.finditer(r'"(?:\\.|[^"\\])*"', line):
            L = len(m.group(0)) - 2
            if L > worst[0]: worst = (L, f, n)
if worst[0] > 1200:
    print(f"FAIL fixture literal guard: literal of {worst[0]} chars at {worst[1]}:{worst[2]} (shape with ++ chains)")
    sys.exit(1)
print(f"ok   fixture literal guard (longest {worst[0]} chars)")
GUARD

for t in tests/lint/*.bend; do
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
  if rg -q '@unsafe|\?TODO' "$t" demos/python/lint.bend; then
    printf 'FAIL unsafe or open goal\n'; fail=$((fail + 1)); continue
  fi
  # A shell function cannot be invoked by timeout; check via exported function.
  export -f check
  run check "$work/checked" bash -c 'check "$1"' _ "$t"
  run interpret "$work/expected" bun bend2/main.ts "$t"
  for lane in js c; do
    target="$work/$name"
    [ "$lane" = js ] && target="$target.js"
    if timeout 180 bun bend2/main.ts "$t" -o "$target" > "$work/build" 2>&1; then
      if [ "$lane" = js ]; then
        run js "$work/expected" bun "$target"
      else
        run c "$work/expected" "$target" --gpu off
      fi
    else
      printf 'FAIL %-20s [%s build]\n' "$name" "$lane"
      head -20 "$work/build"
      fail=$((fail + 1))
    fi
  done
done
python3 tests/lint/semantics.py || fail=$((fail + 1))
printf '\nLint PASS: %d, FAIL: %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
