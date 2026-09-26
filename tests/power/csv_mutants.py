#!/usr/bin/env python3
# The csv laws are not vacuous: each mutant below breaks power/csv.bend the
# way a real reader or writer goes wrong, and power/csv_proof.bend must then
# fail to check. Every mutant is applied to a copy of power/ in a temporary
# directory, beside a copy of wire/ (the checked-in files never change), its snippet must occur exactly
# once, and the mutated csv.bend must still check on its own -- a mutant that
# does not type is a broken test, not a killed one. The csv fixture is run on
# the copy too, to show which mutants the oracle alone would also catch.
#
#   python3 tests/power/csv_mutants.py        (from the repo root)
import os, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FILES = ['csv.bend', 'csv_spec.bend', 'csv_laws.bend', 'csv_proof.bend']

CRFLUSH = '''def crflush(+d: Dialect, p: P) -> P:
  match p:
    case P{m, fl, cur, out, w, pos}:
      match m:
        case CRp{acc, at}:
          endl(d, acc, fl, cur, out, w, at, pos)
        case _:
          P{m, fl, cur, out, w, pos}

def feed_buf(+d: Dialect, +s: Bytes(), p: P) -> P:
  crflush(d, Wr.feed_buf(~Dialect, ~P, ~wstep, ~wadv, d, s, p))'''

MUTANTS = [
  ('a quote inside an unquoted field is kept as data', [(
    '''    case Unq{acc, left} KQ{}:
      P{Bad{pos, QuoteInField{}}, fl, cur, out, w, pos}''',
    '''    case Unq{acc, left} KQ{}:
      put(False{}, c, acc, left, fl, cur, out, w, pos)''')]),
  ('a doubled quote is dropped, not unescaped', [(
    '''    case QQ{acc, left} KQ{}:
      put(True{}, c, acc, left, fl, cur, out, w, pos)''',
    '''    case QQ{acc, left} KQ{}:
      P{Quo{acc, left}, fl, cur, out, w, 1n+pos}''')]),
  ('a CRLF cut between reads: the CR ending a read is taken as a whole line end', [(
    '''def feed_buf(+d: Dialect, +s: Bytes(), p: P) -> P:
  Wr.feed_buf(~Dialect, ~P, ~wstep, ~wadv, d, s, p)''', CRFLUSH)]),
  ('the writer does not quote a field holding the delimiter', [(
    '''def is_o(k: K) -> Bool:
  match k:
    case KO{}:
      True{}''',
    '''def is_o(k: K) -> Bool:
  match k:
    case KO{}:
      True{}
    case KD{}:
      True{}''')]),
  ('the writer does not double a quote', [(
    '''    case KQ{}:
      push(push(acc, c), c)''',
    '''    case KQ{}:
      push(acc, c)''')]),
  ('the fast path runs through a quote between quotes', [(
    '''    case True{} KQ{}:
      False{}
    case True{} _:''',
    '''    case True{} KQ{}:
      True{}
    case True{} _:''')]),
  ('the find outside quotes runs past an LF', [(
    'cap(left, Bytes.find_any(s, 0n, quote(d), delim(d), 13, 10))',
    'cap(left, Bytes.find_any(s, 0n, quote(d), delim(d), 13, 13))')]),
  ('a field one byte past max_field is kept', [(
    '''    case 0n:
      P{Bad{pos, FieldTooLong{}}, fl, cur, out, w, pos}''',
    '''    case 0n:
      P{grow(q, push(acc, c), 0n), fl, cur, out, w, 1n+pos}''')]),
  ('a ragged record passes with ragged off', [(
    '''      endr.ok(ragged(d) || Nat.is_eq(f, x), d, rec, out, x, at, next, np)''',
    '''      endr.ok(True{}, d, rec, out, x, at, next, np)''')]),
  ('a CR not followed by LF is a line end in a CRLF-only dialect', [(
    '''          fresh.after(d, endl(d, acc, fl, cur, out, w, at, pos), k, c)
        case False{}:
          P{Bad{at, BareCR{}}, fl, cur, out, w, pos}''',
    '''          fresh.after(d, endl(d, acc, fl, cur, out, w, at, pos), k, c)
        case False{}:
          fresh.after(d, endl(d, acc, fl, cur, out, w, at, pos), k, c)''')]),
  ('an LF alone ends a record whatever the dialect says', [(
    '''  lf.at.ok(d, lf(d), acc, fl, cur, out, w, pos)''',
    '''  lf.at.ok(d, True{}, acc, fl, cur, out, w, pos)''')]),
]

OK_BEND = '''import Base
import ./csv.bend as Csv

def main() -> Nat:
  0n
'''

def run(args, cwd):
  env = dict(os.environ, BEND_NO_TELEMETRY='1')
  r = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=1800, env=env)
  return r.returncode, (r.stdout + r.stderr).strip()

def where(out):
  loc = [l for l in out.split('\n') if l.startswith('Location')]
  return (loc[0] if loc else out.split('\n')[0])[:90]

def main():
  bend = os.path.join(ROOT, 'bend2', 'main.ts')
  fixture = os.path.join(ROOT, 'tests', 'power', 'csv.bend')
  want = ''.join(l[2:] + '\n' for l in open(fixture) if l.startswith('#|'))
  bad = 0
  for name, edits in MUTANTS:
    tmp = tempfile.mkdtemp(prefix='bend-csv-mutant.')
    try:
      os.makedirs(os.path.join(tmp, 'power'))
      os.makedirs(os.path.join(tmp, 'tests', 'power'))
      for f in FILES:
        shutil.copy(os.path.join(ROOT, 'power', f), os.path.join(tmp, 'power', f))
      shutil.copy(fixture, os.path.join(tmp, 'tests', 'power', 'csv.bend'))
      shutil.copytree(os.path.join(ROOT, 'wire'), os.path.join(tmp, 'wire'))
      src_path = os.path.join(tmp, 'power', 'csv.bend')
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
      code, out = run(['bun', bend, 'power/csv_proof.bend'], tmp)
      code2, got = run(['bun', bend, 'tests/power/csv.bend'], tmp)
      oracle = 'fixture passes' if got + '\n' == want else 'fixture fails'
      if out == 'All terms check.':
        print('SURVIVED %s (%s)' % (name, oracle)); bad += 1
      else:
        print('KILLED   %s -- %s (%s)' % (name, where(out), oracle))
    finally:
      shutil.rmtree(tmp)
  print('mutants: %d / %d killed' % (len(MUTANTS) - bad, len(MUTANTS)))
  sys.exit(1 if bad else 0)

main()
