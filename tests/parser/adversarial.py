"""Bounded crash/timeout detection on the real strict-input CLI (C and emitted JS)."""
from normalize import OUT, pin
from diff import build
import ast
import json
import os
import subprocess
import time


CASES = [
    ("nesting200", b"(" * 200 + b"0" + b")" * 200, "parsed"),
    ("nesting201", b"(" * 201 + b"0" + b")" * 201, "limit"),
    ("unary5000", b"-" * 5000 + b"0", None),
    ("binops100000", b"0+" * 100000 + b"0", None),
    ("line10mb", b"#" + b"a" * (10 * 1024 * 1024 - 1) + b"\n", "parsed"),
    ("mixed_tabs", b"if a:\n\tpass\n        pass\n", "syntax"),
    ("nul_string", b"x='\0'\n", "syntax"),
    ("nul_comment", b"#\0\n", "syntax"),
    ("nul", b"x=\0\n", "syntax"),
    ("invalid_utf8", b"x='\xff'\n", "syntax"),
    ("triple", b"'''unfinished", "syntax"),
    ("dedent", b"if x:\n    pass\n  pass\n", "syntax"),
    # Header-only backtracking: a body inside the `with (` choice reparsed 2^depth times.
    ("with_paren60", b"".join(b" " * i + b"with (a, b):\n" for i in range(60)) + b" " * 60 + b"x = )\n", "syntax"),
    ("soup", b"+ * : ; = ? )) }", "syntax"),
]


def main():
    pin()
    build()
    records = []
    for name, raw, expected in CASES:
        path = OUT / ("adversarial-" + name + ".py")
        path.write_bytes(raw)
        try:
            ast.parse(raw.decode("utf-8"), feature_version=(3, 11), type_comments=False)
            oracle_status = "accepted"
        except (UnicodeError, SyntaxError, RecursionError, MemoryError) as exc:
            oracle_status = type(exc).__name__
        for lane in ("c", "js"):
            cmd = [str(OUT / "parser"), "--gpu", "off"] if lane == "c" else ["bun", str(OUT / "parser.js")]
            start = time.monotonic()
            try:
                p = subprocess.run(cmd, env=dict(os.environ, PY_SOURCE=str(path), PY_MODE="parse"),
                                   capture_output=True, timeout=60)
                message = p.stdout + p.stderr
                status = "fail-stop"
                if p.returncode == 0 and p.stdout.startswith(b'{"tag":"Module",') and p.stdout.endswith(b"}\n"):
                    # Avoid converting arbitrarily deep JSON into the oracle host's call stack.
                    status = "parsed"
                for kind in ("Syntax", "Unsupported", "Limit"):
                    if p.returncode == 1 and message.startswith(("error " + kind + " ").encode()):
                        status = kind.lower()
                rec = {"case": name, "lane": lane, "bytes": len(raw), "status": status,
                       "exit": p.returncode, "output_bytes": len(message),
                       "message": message[:500].decode("utf-8", "replace") if status != "parsed" else None}
            except subprocess.TimeoutExpired:
                rec = {"case": name, "lane": lane, "bytes": len(raw), "status": "fail-stop", "message": "timeout"}
            rec.update(oracle=oracle_status, seconds=time.monotonic() - start,
                       expected=expected, passed=rec["status"] != "fail-stop" and (expected is None or rec["status"] == expected))
            records.append(rec)
            print(f"{name} {lane}: {rec['status']} {rec['seconds']:.3f}s", flush=True)
    counts = {"runs": len(records), "passed": sum(r["passed"] for r in records),
              "fail_stops": sum(r["status"] == "fail-stop" for r in records)}
    (OUT / "adversarial-results.json").write_text(json.dumps({"counts": counts, "records": records}, indent=2) + "\n")
    print(json.dumps(counts))
    return counts["passed"] != counts["runs"]


if __name__ == "__main__":
    raise SystemExit(main())
