#!/usr/bin/env bash
# The Python bridge needs two things from outside this repo:
#   1. a Bend checkout — the language and runtime the suites compile and run with,
#      at the fork commit named in BEND_PIN (the package and its Bend travel as a pair)
#   2. the suites' historical `demos/python` path, which this repo keeps as `python/`
#
#   ./setup.sh                        # ../bend if it is at the pin, else fetch the pin into .bend/
#   BEND_DIR=/path/to/bend ./setup.sh # use that checkout (warns off-pin; BEND_STRICT=1 refuses)
#   bash tests/translator/run.sh      # or tests/vm, tests/lint, tests/power, tests/parser
#
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
repo=$(awk '$1 == "repo" {print $2}' "$root/BEND_PIN")
pin=$(awk '$1 == "commit" {print $2}' "$root/BEND_PIN")

at_pin() { [ "$(git -C "$1" rev-parse HEAD 2>/dev/null)" = "$pin" ]; }

if [ -n "${BEND_DIR:-}" ]; then
  bend=$BEND_DIR
  if [ ! -f "$bend/bend2/main.ts" ]; then
    echo "setup: BEND_DIR=$bend is not a Bend checkout (bend2/main.ts is missing)" >&2
    exit 1
  fi
  if ! at_pin "$bend"; then
    echo "setup: $bend is at $(git -C "$bend" rev-parse --short HEAD 2>/dev/null || echo '?'), BEND_PIN says ${pin:0:7}" >&2
    [ "${BEND_STRICT:-0}" = 1 ] && exit 1
    echo "       continuing off-pin: results are not the package's results" >&2
  fi
elif [ -f "$root/../bend/bend2/main.ts" ] && at_pin "$root/../bend"; then
  bend="$root/../bend"
else
  bend="$root/.bend"
  if ! at_pin "$bend"; then
    echo "setup: fetching $repo@${pin:0:7} into .bend/"
    rm -rf "$bend"
    git init -q "$bend"
    git -C "$bend" fetch -q --depth 1 "https://github.com/$repo" "$pin"
    git -C "$bend" -c advice.detachedHead=false checkout -q FETCH_HEAD
  fi
fi

ln -sfn "$bend/bend2" "$root/bend2"
mkdir -p "$root/demos"
ln -sfn ../python "$root/demos/python"

echo "setup: bend2        -> $bend/bend2 ($(git -C "$bend" rev-parse --short HEAD))"
echo "setup: demos/python -> ../python"
echo "setup: ready — try: bash tests/translator/run.sh"
