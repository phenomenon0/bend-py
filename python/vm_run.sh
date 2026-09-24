#!/usr/bin/env bash
# `vm_run.sh [prefix]`. The Python VM lane: for each fixture in demos/python/vm_*.py,
# CPython 3.11.15 runs it and demos/python/vm.bend runs it, and the two outputs are
# compared byte for byte. Four lanes: the VM checks strictly once (it is one program,
# the fixtures are its data), then every fixture runs on the interpreter, the emitted
# JS and the emitted C. Two controls ride along: a mutated expectation must be caught
# by the same comparison path, and a construct outside the subset must be REFUSED by
# the compiler rather than miscompiled. Prints `VM PASS: n, FAIL: 0`.
# This script belongs at tests/vm/run.sh and is not there: gates/repo.ts has no allow
# row for tests/vm/**, and this lane may not edit gates/. See docs/omen/lanes/pyspike.md.
# Its scratch still lives under tests/vm/_out/ (gitignored) because /tmp is blocked.
set -uo pipefail
cd "$(dirname "$0")/../.."
# Pin the environment alongside the bytes: the interpreter's daily check prints a
# one-line update notice to stderr when upstream has a newer release, and these
# lanes byte-compare raw stdout+stderr.
export BEND_NO_TELEMETRY=1
work=tests/vm/_out
vm=demos/python/vm.bend
mkdir -p "$work"
pass=0
fail=0
name=""

# The oracle is pinned: CPython's print formatting IS the specification here.
want=3.11.15
got=$(python3 -c 'import platform; print(platform.python_version())' 2>/dev/null)
if [ "$got" != "$want" ]; then
  printf 'FAIL oracle: python3 is %s, the lane is pinned to %s\n' "${got:-missing}" "$want"
  printf '\nVM PASS: 0, FAIL: 1\n'
  exit 1
fi

run() {
  local label=$1 expected=$2 status=0
  shift 2
  : > "$work/diff"
  timeout "${VM_TIMEOUT:-600}" "$@" > "$work/actual" 2>&1 || status=$?
  if [ "$status" -eq 0 ] && diff -u "$expected" "$work/actual" > "$work/diff"; then
    printf 'ok   %-12s [%s]\n' "$name" "$label"
    pass=$((pass + 1))
  else
    printf 'FAIL %-12s [%s] status=%s\n' "$name" "$label" "$status"
    head -15 "$work/actual" "$work/diff"
    fail=$((fail + 1))
  fi
}

check() {
  bun -e '
    import * as B from "./bend2/bend.ts";
    const book = B.book_nil();
    await B.book_load(book, process.argv[1], "", new Map());
    B.book_valid(book);
    if (book.hols + book.open) process.exit(1);
    console.log("All terms check.");' "$1"
}

name=vm
printf 'All terms check.\n' > "$work/checked"
export -f check
run check "$work/checked" bash -c 'check "$1"' _ "$vm"

for lane in js c; do
  target="$work/vm.js"
  [ "$lane" = c ] && target="$work/vm.bin"
  if ! timeout "${VM_BUILD_TIMEOUT:-1800}" bun bend2/main.ts "$vm" -o "$target" > "$work/build" 2>&1; then
    printf 'FAIL %-12s [%s build]\n' vm "$lane"
    head -20 "$work/build"
    fail=$((fail + 1))
  fi
done

for f in demos/python/vm_*.py; do
  name=$(basename "$f" .py)
  if [ -n "${1:-}" ] && [[ "$name" != "$1"* ]]; then
    continue
  fi
  python3 "$f" > "$work/expected" 2>&1
  export PY_SOURCE=$f
  run interpret "$work/expected" bun bend2/main.ts "$vm"
  run js "$work/expected" bun "$work/vm.js"
  run c "$work/expected" "$work/vm.bin" --gpu off
done

# Control 1: the same comparison path, handed an expectation that is off by one
# line, must report the failure. A green lane that cannot go red proves nothing.
name=mutation_control
printf 'print(6 * 7)\n' > "$work/control.py"
printf '43\n' > "$work/control-expected"
before=$fail
export PY_SOURCE=$work/control.py
run c "$work/control-expected" "$work/vm.bin" --gpu off
if [ "$fail" -eq "$((before + 1))" ] && [ "$(cat "$work/actual")" = "42" ]; then
  fail=$before
  pass=$((pass + 1))
  printf 'ok   %-12s [mutated expectation caught]\n' "$name"
else
  printf 'FAIL %-12s [mutated expectation escaped]\n' "$name"
  fail=$((fail + 1))
fi

# Control 2: outside the subset is REFUSED, not miscompiled. One line each for the
# three refusals the subset leans on, exact message and a non-zero exit.
name=refusal_control
refused() {
  printf '%s\n' "$1" > "$work/refuse.py"
  local status=0
  PY_SOURCE=$work/refuse.py "$work/vm.bin" --gpu off > "$work/refused" 2>&1 || status=$?
  # shellcheck disable=SC2034
  if [ "$status" -ne 0 ] && grep -qF "$2" "$work/refused"; then
    pass=$((pass + 1))
    printf 'ok   %-12s [%s]\n' "$name" "$2"
  else
    fail=$((fail + 1))
    printf 'FAIL %-12s [%s] status=%s\n' "$name" "$2" "$status"
    head -5 "$work/refused"
  fi
}
refused 'print(1 < 2 < 3)' 'chained comparisons are outside the subset'
refused 'print(["a"])'     'lists are outside the subset'
refused 'print(3 - 9)'     'a negative result is outside the subset'
# A name is unset until its first store -- global, local, or a def's own
# binding -- and a read before it faults as CPython raises, never a None.
refused 'print(x)'         'a name read before assignment (NameError)'
refused $'def f():\n    print(y)\n    y = 1\nf()' 'a local read before assignment (UnboundLocalError)'
refused $'print(f(1))\ndef f(a):\n    return a' 'a name read before assignment (NameError)'
refused $'def f():\n    return 1\nf = 3\nprint(f())' 'calling a non-function is outside the subset'
refused $'def f(a):\n    return a\nprint(f)' 'functions as values are outside the subset'
# Ints stop at 2**48 - 1 on every lane: past it is refused, not wrapped.
refused 'print(16777216 * 16777216)' 'an int past 2**48 - 1 is outside the subset'
refused 'print(281474976710655 + 1)' 'an int past 2**48 - 1 is outside the subset'
refused 'print(281474976710656)' 'an int past 2**48 - 1 is outside the subset'
# A builtin read as a value is refused by its name, never a NameError.
refused 'u = print'        'the builtin print is outside the subset'
refused 'print(abs)'       'the builtin abs is outside the subset'
# A string stops at 2**24 characters, however it grows.
refused 'print(len("ab" * 9000000))' 'a string past 2**24 characters is outside the subset'
refused $'s = "ab"\nk = 30\nwhile k > 0:\n    k -= 1\n    s = s + s\nprint(len(s))' 'a string past 2**24 characters is outside the subset'
# CPython holds 999 calls in flight; the 1000th is its RecursionError.
refused $'def f(n):\n    if n <= 0:\n        return 0\n    return f(n - 1)\nprint(f(999))' 'maximum recursion depth exceeded (RecursionError)'
# A \x escape takes exactly two hex digits: CPython's SyntaxError, a refusal here.
refused 'print("\x4")' 'an invalid \x escape'
refused 'print("\x4g")' 'an invalid \x escape'

# Optional: VM_FUZZ=n runs n generated programs through fuzz_vm.py on the
# binaries just built (CPython the oracle, the C and JS lanes the suspects);
# its findings count as one failure. Seeded by VM_FUZZ_SEED (default 1).
if [ -n "${VM_FUZZ:-}" ]; then
  name=fuzz
  if python3 demos/python/fuzz_vm.py --n "$VM_FUZZ" --seed "${VM_FUZZ_SEED:-1}" > "$work/fuzz" 2>&1; then
    pass=$((pass + 1))
    printf 'ok   %-12s [%s]\n' "$name" "$(tail -1 "$work/fuzz")"
  else
    fail=$((fail + 1))
    printf 'FAIL %-12s [%s]\n' "$name" "$(tail -1 "$work/fuzz")"
    grep -A12 '^FAIL' "$work/fuzz" | head -40
  fi
fi

printf '\nVM PASS: %d, FAIL: %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
