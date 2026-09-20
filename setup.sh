#!/usr/bin/env bash
# The Python bridge needs two things from outside this repo:
#   1. a Bend checkout — the language and runtime the suites compile and run with
#   2. the suites' historical `demos/python` path, which this repo keeps as `python/`
#
# This script links both, so every suite runs unchanged from the repo root:
#
#   BEND_DIR=/path/to/bend ./setup.sh     # default: a sibling checkout at ../bend
#   bash tests/translator/run.sh          # or tests/lint, tests/power, tests/parser
#
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
bend="${BEND_DIR:-$root/../bend}"

if [ ! -f "$bend/bend2/main.ts" ]; then
  echo "setup: BEND_DIR=$bend does not look like a Bend checkout" >&2
  echo "       (bend2/main.ts is missing). Point BEND_DIR at a Bend tree;" >&2
  echo "       the fork this package is developed against: phenomenon0/bend." >&2
  exit 1
fi

ln -sfn "$bend/bend2" "$root/bend2"
mkdir -p "$root/demos"
ln -sfn ../python "$root/demos/python"

echo "setup: bend2        -> $bend/bend2"
echo "setup: demos/python -> ../python"
echo "setup: ready — try: bash tests/translator/run.sh"
