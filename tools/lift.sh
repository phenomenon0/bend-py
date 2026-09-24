#!/usr/bin/env bash
# lift.sh — refresh this package from a fork checkout, or check it has not drifted.
#
#   tools/lift.sh [--check] [FORK_DIR]      FORK_DIR defaults to $BEND_DIR, then .bend/
#
# The fork (phenomenon0/bend) is where the bridge is developed; this repo is the
# package. A lift copies the fork's tracked files for the zones below, mirrors
# deletions, and leaves this repo's own adaptations alone. --check copies
# nothing: it lists every file that differs and exits 1 if any does. The fork
# commit a lift came from goes in BEND_PIN, so the package and its Bend always
# travel as one pair.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
check=0
if [ "${1:-}" = "--check" ]; then check=1; shift; fi
fork="${1:-${BEND_DIR:-$root/.bend}}"
[ -f "$fork/bend2/main.ts" ] || { echo "lift: $fork is not a Bend checkout" >&2; exit 2; }

# zone in the fork -> place here
map=(
  "demos/python:python"
  "tests/lint:tests/lint"
  "tests/translator:tests/translator"
  "tests/parser:tests/parser"
  "tests/power:tests/power"
  "power:power"
)
# this repo's own versions: never overwritten, never deleted
keep=(
  "tests/parser/manifest.py"   # PKG_TOOLS_DIR / PKG_CORPUS_TREE / PKG_FORBIDDEN_DIR
  "tests/parser/CORPUS.md"     # corpus provisioning for a clone
)
kept() { local p; for p in "${keep[@]}"; do [ "$1" = "$p" ] && return 0; done; return 1; }

drift=0
for m in "${map[@]}"; do
  src=${m%%:*} dst=${m##*:}
  want=$(git -C "$fork" ls-files -- "$src" | sed "s#^$src/##" | sort)
  have=$( (cd "$root" && git ls-files -- "$dst"; cd "$root" && find "$dst" -type f 2>/dev/null) \
    | grep -v '/_out/\|__pycache__' | sed "s#^$dst/##" | sort -u)
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    kept "$dst/$f" && continue
    if ! cmp -s "$fork/$src/$f" "$root/$dst/$f"; then
      drift=$((drift + 1))
      if [ $check = 1 ]; then echo "differs  $dst/$f"; else
        mkdir -p "$(dirname "$root/$dst/$f")"; cp "$fork/$src/$f" "$root/$dst/$f"; echo "lifted   $dst/$f"; fi
    fi
  done <<< "$want"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    kept "$dst/$f" && continue
    grep -qxF -- "$f" <<< "$want" && continue
    drift=$((drift + 1))
    if [ $check = 1 ]; then echo "extra    $dst/$f"; else rm -f "$root/$dst/$f"; echo "removed  $dst/$f"; fi
  done <<< "$have"
done

pin=$(git -C "$fork" rev-parse HEAD)
if [ $check = 1 ]; then
  [ $drift = 0 ] && echo "lift: in step with $pin" || echo "lift: $drift file(s) drift from $pin"
  [ $drift = 0 ]
else
  printf 'repo    phenomenon0/bend\ncommit  %s\n' "$pin" > "$root/BEND_PIN"
  echo "lift: $drift file(s) changed; BEND_PIN -> $pin"
fi
