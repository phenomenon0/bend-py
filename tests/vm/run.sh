#!/usr/bin/env bash
# The VM tier's battery. It lives with the VM (python/vm_run.sh, reached through
# setup.sh's demos/python bridge) and runs unchanged from this repo's root:
# check, interpreter, emitted JS and emitted C against CPython 3.11.15, plus
# the refusal controls. VM_FUZZ=n adds n programs from python/fuzz_vm.py.
cd "$(dirname "$0")/../.." && exec bash demos/python/vm_run.sh "$@"
