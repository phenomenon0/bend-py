"""Measure the large pure-interpreter boundary without disguising it as a pass.

These generated fixtures stay in _out. Exit 1 means at least one interpreter
failure; emitted C/JS stress evidence is reported separately by adversarial.py.
"""
from normalize import ROOT, OUT
import json
import subprocess
import time


def main():
    sources = {
        "baseline_string5000": 'Nat.is_eq(String.length(String.repeat("-", 50n * 100n)), 50n * 100n)',
        "unary5000": 'verdict(L.lex(String.repeat("-", 50n * 100n) ++ "0"))',
        "binops100000": 'verdict(L.lex(String.repeat("0+", 100n * 100n * 10n) ++ "0"))',
        "line10mb": 'verdict(L.lex(String.repeat("#", 64n * 64n * 256n * 10n)))',
    }
    prefix = '''import Base
import ../../../demos/python/syntax.bend as S
import ../../../demos/python/lexer.bend as L
import ../../../demos/python/parser.bend as P

def parsed(r: Result<&2, &2, S.Error, S.Module>) -> Nat:
  match r:
    case Done{m}:
      0n
    case Fail{e}:
      1n

def verdict(r: Result<&2, &2, S.Error, List<&2, S.Tok>>) -> Nat:
  match r:
    case Done{ts}:
      parsed(P.parse(ts))
    case Fail{e}:
      1n

'''
    records = []
    for name, expression in sources.items():
        path = OUT / ("reference-" + name + ".bend")
        main_type = "Bool" if name.startswith("baseline") else "Nat"
        path.write_text(prefix + "def main() -> " + main_type + ":\n  " + expression + "\n")
        started = time.monotonic()
        try:
            p = subprocess.run(["bun", "bend2/main.ts", str(path)], cwd=ROOT, text=True,
                               capture_output=True, timeout=60)
            row = {"case": name, "exit": p.returncode, "output": p.stdout + p.stderr,
                   "passed": p.returncode == 0}
        except subprocess.TimeoutExpired:
            row = {"case": name, "passed": False, "output": "timeout (60 seconds)"}
        row["seconds"] = time.monotonic() - started
        records.append(row)
        print(name + ": " + ("PASS" if row["passed"] else "FAIL") + " " + row["output"].strip(), flush=True)
    (OUT / "reference-results.json").write_text(json.dumps(records, indent=2) + "\n")
    return any(not r["passed"] for r in records)


if __name__ == "__main__":
    raise SystemExit(main())
