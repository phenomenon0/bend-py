#!/usr/bin/env python3
# The deflate laws are not vacuous: each mutant below breaks power/deflate.bend
# the way a real codec goes wrong, and power/deflate_proof.bend must then fail
# to check. Every mutant is applied to a copy of power/ in a temporary
# directory, beside a copy of wire/ (the checked-in files never change); its
# snippet must occur exactly once, and the mutated deflate.bend must still
# check on its own -- a mutant that does not type is a broken test, not a
# killed one. The fixture is built for the C lane and run on the copy too, to
# show which mutants the oracle alone would also catch.
#
#   python3 tests/power/deflate_mutants.py        (from the repo root)
import os, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FILES = ['deflate.bend', 'gzip.bend', 'deflate_laws.bend', 'deflate_proof.bend', 'inflate_proof.bend']

MUTANTS = [
  ('the final block is written without BFINAL', 'deflate.bend', [(
    'align(put(put(put(w, last), False{}), False{}))',
    'align(put(put(put(w, False{}), False{}), False{}))')]),
  ('a length code has one extra bit too few', 'deflate.bend', [(
    '4n, 5n, 5n, 5n, 5n, 0n]',
    '4n, 5n, 5n, 5n, 4n, 0n]')]),
  ('a distance code has one extra bit too few', 'deflate.bend', [(
    '11n, 11n, 12n, 12n, 13n, 13n]',
    '11n, 11n, 12n, 12n, 13n, 12n]')]),
  ('the window is one byte short', 'deflate.bend', [(
    'def K32() -> Nat:\n  32768n',
    'def K32() -> Nat:\n  32767n')]),
  ('a copy reads one byte too far back', 'deflate.bend', [(
    '+c = Bytes.get(o, Nat.sub(Bytes.len(o), dist))',
    '+c = Bytes.get(o, Nat.sub(Bytes.len(o), 1n+dist))')]),
  ('a distance reaching the first byte out is refused', 'deflate.bend', [(
    'copy.if(Nat.is_lt(Bytes.len(out), dist),',
    'copy.if(Nat.is_le(Bytes.len(out), dist),')]),
  ('the CRC polynomial has a typo', 'deflate.bend', [(
    'def POLY() -> U32:\n  3988292384',
    'def POLY() -> U32:\n  3988292386')]),
  ('the CRC register is not preset to ones', 'deflate.bend', [(
    'U32.not(crc.run(x, crc.tab(), U32.not(prev)))',
    'U32.not(crc.run(x, crc.tab(), prev))')]),
  ('the cap lets one byte past', 'deflate.bend', [(
    'emit.if(Nat.is_lt(n, cap), out, keep, n, cap, t, c, next, bp)',
    'emit.if(Nat.is_le(n, cap), out, keep, n, cap, t, c, next, bp)')]),
  ('a copy is not held to the cap', 'deflate.bend', [(
    'Nat.is_lt(cap, Nat.add(n, len)), out, keep, n,',
    'Nat.is_lt(cap, n), out, keep, n,')]),
  ('a stored block after a full one counts from 0', 'deflate.bend', [(
    'def one16() -> List<&2, Bool>:\n  [True{},',
    'def one16() -> List<&2, Bool>:\n  [False{},')]),
  ('NLEN is written as LEN', 'deflate.bend', [(
    'putn(16n, nots(cnt), putn(16n, cnt,',
    'putn(16n, cnt, putn(16n, cnt,')]),
  ('a stored byte is read high bit first', 'deflate.bend', [(
    '      stored_byte(last, left, U32.from_nat(hval(acc, 0n)), o, bp)',
    '      stored_byte(last, left, U32.from_nat(val(acc)), o, bp)')]),
  ('the written-out length table has one extra bit too few', 'deflate.bend', [(
    '\\u{4}\\u{5}\\u{5}\\u{5}\\u{5}\\u{0}"',
    '\\u{4}\\u{5}\\u{5}\\u{5}\\u{4}\\u{0}"')]),
  ('a code is walked with its 1 bits taken as 0', 'deflate.bend', [(
    'walk(tab, U32.to_nat(Bytes.get(tab, Nat.add(Nat.double(node), Nat.bit(b, 0n)))), k, o, bp)',
    'walk(tab, U32.to_nat(Bytes.get(tab, Nat.add(Nat.double(node), Nat.bit(Bool.not(b), 0n)))), k, o, bp)')]),
  ('the fixed path writes a copy it has not checked', 'deflate.bend', [(
    'ref_ok(x, pos, end, len, dist) && ck(r, x, Nat.add(pos, len), end)',
    'ck(r, x, Nat.add(pos, len), end)')]),
  ('a copy is checked without its first byte', 'deflate.bend', [(
    'U32.is_eq(Bytes.get(x, pos), Bytes.get(x, Nat.sub(pos, dist))) && same(p, x, 1n+pos, dist)',
    'same(p, x, 1n+pos, dist)')]),
  ('the fixed code gives one literal too few 8 bits', 'deflate.bend', [(
    'reps(144n, 8n, reps(112n, 9n,',
    'reps(143n, 8n, reps(113n, 9n,')]),
  # the fast path (law inflate_fast): each reads a stream as the machine does not
  ('the fast path reads the bit after the one it is at', 'deflate.bend', [(
    '  bit(Bytes.get(s, q), r)',
    '  bit(Bytes.get(s, q), 1n+r)')]),
  ('the fast path walks a code with its 1 bits taken as 0', 'deflate.bend', [(
    'U32.to_nat(Bytes.get(tab, Nat.add(Nat.double(node), Nat.bit(b, 0n))))\n',
    'U32.to_nat(Bytes.get(tab, Nat.add(Nat.double(node), Nat.bit(Bool.not(b), 0n))))\n')]),
  ('a fast copy reads one byte too far back', 'deflate.bend', [(
    '  Bytes.get(o, Nat.sub(Bytes.len(o), dist))',
    '  Bytes.get(o, Nat.sub(Bytes.len(o), 1n+dist))')]),
  ('the fast path lets a literal past the cap', 'deflate.bend', [(
    'fi.emit(Nat.is_lt(n, cap), sy, q, r)',
    'fi.emit(Nat.is_le(n, cap), sy, q, r)')]),
  ("the fast path reads a length's extra bits oldest first", 'deflate.bend', [(
    'fi.dwalk(Nat.add(base, hval(acc, 0n))',
    'fi.dwalk(Nat.add(base, val(acc))')]),
  ('the fast path lets a distance one past the output', 'deflate.bend', [(
    'fi.cp(Nat.is_lt(olen, dist),',
    'fi.cp(Nat.is_lt(1n+olen, dist),')]),
  ('the fast path starts at any offset', 'deflate.bend', [(
    'fi.at.bp(Nat.is_eq(bp, r),',
    'fi.at.bp(True{},')]),
]

OK_BEND = '''import Base
import ./deflate.bend as D
import ./gzip.bend as Z

def main() -> Nat:
  0n
'''

def run(args, cwd, timeout=3600):
  env = dict(os.environ, BEND_NO_TELEMETRY='1')
  r = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=timeout, env=env)
  return r.returncode, (r.stdout + r.stderr).strip()

def where(out):
  loc = [l for l in out.split('\n') if l.startswith('Location')]
  return (loc[0] if loc else out.split('\n')[0])[:90]

def main():
  bend = os.path.join(ROOT, 'bend2', 'main.ts')
  fixture = os.path.join(ROOT, 'tests', 'power', 'deflate.bend')
  want = ''.join(l[2:] + '\n' for l in open(fixture) if l.startswith('#|'))
  bad = 0
  for name, target, edits in MUTANTS:
    tmp = tempfile.mkdtemp(prefix='bend-deflate-mutant.')
    try:
      os.makedirs(os.path.join(tmp, 'power'))
      os.makedirs(os.path.join(tmp, 'tests', 'power'))
      for f in FILES:
        shutil.copy(os.path.join(ROOT, 'power', f), os.path.join(tmp, 'power', f))
      for f in ['deflate.bend', 'deflate.dat']:
        shutil.copy(os.path.join(ROOT, 'tests', 'power', f), os.path.join(tmp, 'tests', 'power', f))
      shutil.copytree(os.path.join(ROOT, 'wire'), os.path.join(tmp, 'wire'))
      src_path = os.path.join(tmp, 'power', target)
      src = open(src_path).read()
      missing = [a for a, b in edits if src.count(a) != 1]
      if missing:
        print('MISSING  %s' % name); bad += 1; continue
      for a, b in edits:
        src = src.replace(a, b)
      open(src_path, 'w').write(src)
      open(os.path.join(tmp, 'power', 'ok.bend'), 'w').write(OK_BEND)
      code, out = run(['bun', bend, 'power/ok.bend'], tmp)
      if code != 0:
        print('ILLTYPED %s -- %s' % (name, where(out))); bad += 1; continue
      code, out = run(['bun', bend, 'power/deflate_proof.bend'], tmp)
      exe = os.path.join(tmp, 'fx')
      code2, got = run(['bun', bend, 'tests/power/deflate.bend', '-o', exe], tmp)
      if code2 == 0:
        code2, got = run([exe, '--gpu', 'off'], tmp)
      oracle = 'fixture passes' if code2 == 0 and got + '\n' == want else 'fixture fails'
      if out == 'All terms check.':
        print('SURVIVED %s (%s)' % (name, oracle)); bad += 1
      else:
        print('KILLED   %s -- %s (%s)' % (name, where(out), oracle))
      sys.stdout.flush()
    finally:
      shutil.rmtree(tmp)
  print('mutants: %d / %d killed' % (len(MUTANTS) - bad, len(MUTANTS)))
  sys.exit(1 if bad else 0)

main()
