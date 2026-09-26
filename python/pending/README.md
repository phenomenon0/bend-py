# pending fixtures — waiting for their feature

Fixtures here are FINISHED, CPython-verified, and parked until the VM supports
what they exercise. The battery globs `demos/python/vm_*.py`, so a fixture in
this directory is invisible to it — by design, a red fixture for an
unimplemented feature would be a wrong red.

To activate a fixture when its feature lands:

    git mv demos/python/pending/vm_lists.py demos/python/

The next battery run picks it up automatically and compares it byte-for-byte
against the pinned CPython 3.11.15 oracle.

Rules for fixtures in this directory:

- Deterministic output only (the battery diffs raw stdout).
- CPython 3.11.15 exact: verify by running `python3 fixture.py` on this box.
- Stay inside the planned subset: non-negative integers, no classes, no
  exceptions, no imports. Features still ahead of the VM are allowed (that is
  the point) — they must name the missing slice in a header comment.
