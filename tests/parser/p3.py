"""Reproducible whole-corpus P3 experiment; candidate is never production default.
Timings include process launch, strict input, lexing, JSON output and capture;
exclude build and oracle. Alternating order, no host regex recognition in Bend.
"""
from normalize import ROOT, OUT, pin, intake, differences
from manifest import manifest
from lexdiff import oracle_tokens, norm, CASES
import argparse
import hashlib
import json
import os
import statistics
import subprocess
import time
from pathlib import Path


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--files', type=int, default=200)
    p.add_argument('--runs', type=int, default=3)
    p.add_argument('--skip', type=int, default=0, help='eligible files to skip: chunked whole-corpus runs')
    a = p.parse_args()
    pin()
    rows = [r for r in manifest('lex', a.skip + a.files) if not r['exclusion']][a.skip:]
    paths = [(r, oracle_tokens(intake(Path(r['path']).read_bytes()))) for r in rows]
    builds = {}
    for lane, name in [('c', 'p3'), ('js', 'p3.js')]:
        dest = OUT / name
        subprocess.run(['bun', 'bend2/main.ts', 'tests/parser/p3/main.bend', '-o', str(dest)], cwd=ROOT, check=True, capture_output=True)
        builds[lane] = [str(dest), '--gpu', 'off'] if lane == 'c' else ['bun', str(dest)]
    records, totals, hashes = [], {}, set()
    for repeat in range(a.runs):
        for lane, cmd in builds.items():
            for mode in (['hand', 'regex'] if repeat % 2 == 0 else ['regex', 'hand']):
                elapsed, byte_hash = 0, hashlib.sha256()
                for row, want in paths:
                    start = time.perf_counter()
                    proc = subprocess.run(cmd, cwd=ROOT, env=dict(os.environ, PY_SOURCE=row['path'], PY_LEXER=mode), capture_output=True, timeout=120)
                    seconds = time.perf_counter() - start
                    elapsed += seconds
                    assert proc.returncode == 0, (row['path'], lane, mode, proc.stderr, proc.stdout)
                    got = json.loads(proc.stdout)
                    assert not differences(norm(want, True), norm(got, True)), (row['path'], lane, mode)
                    byte_hash.update(proc.stdout)
                    records.append(dict(path=row['path'], repeat=repeat, lane=lane, mode=mode, seconds=seconds))
                totals.setdefault(lane + '/' + mode, []).append(elapsed)
                hashes.add(byte_hash.hexdigest())
                print(lane, mode, repeat, round(elapsed, 3), byte_hash.hexdigest(), flush=True)
    assert len(hashes) == 1, 'stdout not byte-identical across lanes/modes/runs'
    summary = dict(skip=a.skip, stdout_sha256=hashes.pop(), files=len(paths), bytes=sum(r['size'] for r, _ in paths), runs=a.runs,
                   totals_seconds=totals, medians_seconds={k: statistics.median(v) for k, v in totals.items()},
                   records=records, manifest=rows)
    (OUT / f'p3-{a.skip}-{a.files}.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps({k:v for k,v in summary.items() if k not in {'records', 'manifest'}}, indent=2))


if __name__ == '__main__':
    main()
