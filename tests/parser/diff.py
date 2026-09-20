"""C per file + deterministic 5% JS sample, with separate structural/location diffs."""
from normalize import ROOT, OUT, pin, intake, oracle, normalize, split, differences, supported
import argparse
import copy
import fcntl
import hashlib
import json
import os
import statistics
import subprocess
import time
from pathlib import Path
from manifest import manifest
from fixtures import EXPRESSIONS, STATEMENTS

FIXTURES = ["", "pass\n", "x = 1\n", "x += 2\n", "-2**2\n", "2**-2\n",
            "not a in b\n", "a is not b\n", "a < b <= c\n", "a if b else c\n",
            "f(a, x=2)\n", "a.b[1]\n", "[a, b]\n", "(a,)\n", "{'x': 1}\n",
            "'a' 'b'\n", "('a' # comment\n 'b')\n", "'é😀'\n",
            "if a:\n    pass\nelse:\n    break\n", "while a:\n    continue\n"]


def build():
    sources = sorted((ROOT / "demos/python").glob("*.bend")) + [ROOT / "bend2" / f for f in ("bend.ts", "comp.ts", "base.bend", "main.ts")]
    digest = hashlib.sha256(b"".join(p.read_bytes() for p in sources)).hexdigest()
    stamp = OUT / "build.sha256"
    with (OUT / "build.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if stamp.exists() and stamp.read_text() == digest and all((OUT / f).exists() for f in ("parser", "parser.js")):
            return
        for name in ("parser", "parser.js"):
            pending = OUT / ("building-" + name)
            p = subprocess.run(["bun", "bend2/main.ts", "demos/python/main.bend", "-o", str(pending)], cwd=ROOT,
                               text=True, capture_output=True, timeout=180)
            if p.returncode:
                raise RuntimeError(p.stdout + p.stderr)
            pending.replace(OUT / name)
        stamp.write_text(digest)


def run(path, lane="c", mode="parse", timeout=30):
    cmd = [str(OUT / "parser"), "--gpu", "off"] if lane == "c" else ["bun", str(OUT / "parser.js")]
    env = dict(os.environ, PY_SOURCE=str(path), PY_MODE=mode)
    start = time.perf_counter()
    try:
        p = subprocess.run(cmd, cwd=ROOT, env=env, text=True, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return {"status": "fail-stop", "message": "timeout", "ms": timeout * 1000}
    ms = (time.perf_counter() - start) * 1000
    if p.returncode == 0:
        try:
            return {"status": "parsed", "value": json.loads(p.stdout), "ms": ms}
        except ValueError:
            pass
    text = (p.stdout + p.stderr).strip()
    for kind in ("Syntax", "Unsupported", "Limit"):
        if p.returncode == 1 and text.startswith("error " + kind + " "):
            return {"status": kind.lower(), "message": text, "ms": ms}
    return {"status": "fail-stop", "code": p.returncode, "message": text[:2000], "ms": ms}


def compare(want, got):
    ws, wl = split(want)
    gs, gl = split(normalize(got))
    return differences(ws, gs), differences(wl, gl)


def self_test():
    pin()
    for source in FIXTURES:
        want, _ = oracle(source)
        # The encoder/decoder round trip, plus oracle-shaped raw literal transport.
        wire = json.loads(json.dumps(want, ensure_ascii=False))
        assert compare(want, wire) == ([], [])
    a, _ = oracle("x = ('a' # comment\n 'b')\n")
    b = copy.deepcopy(a)
    const = b["body"][0]["value"]
    const["_raw"] = "'a' # comment\n 'b'"
    del const["value"]
    assert compare(a, b) == ([], [])
    b["body"][0]["targets"][0]["ctx"]["tag"] = "Load"
    assert compare(a, b)[0], "ctx corruption undetected"
    b = copy.deepcopy(a)
    b["body"][0]["value"]["_loc"][3] += 1
    assert compare(a, b)[1] and not compare(a, b)[0], "end-span corruption undetected"
    assert literal_control()
    oracle("(" * 200 + "0" + ")" * 200)
    try:
        oracle("(" * 201 + "0" + ")" * 201)
        raise AssertionError("oracle nesting bound changed")
    except SyntaxError:
        pass
    for source in ("return 1", "break", "continue"):
        oracle(source)
    for raw in (b"\xff", b"\xed\xa0\x80", b"\xf0\x80\x80\x80", b"\xe2\x82"):
        try:
            intake(raw)
            raise AssertionError("invalid UTF-8 accepted")
        except (UnicodeError, SyntaxError):
            pass
    (OUT / "self-test.json").write_text(json.dumps({"round_trips": 20, "corruption_controls": ["ctx", "constant", "end-span"], "pass": True}, indent=2) + "\n")
    print("Harness self-test: 20/20 round trips; ctx/constant/end-span corruption detected")


def literal_control():
    a, _ = oracle("0x10")
    b = copy.deepcopy(a)
    b["body"][0]["value"]["value"] = "17"
    return bool(compare(a, b)[0])


def segments(rows, label):
    # Later-slice productions refuse most real files whole, so the evidence is per statement:
    # every top-level statement the oracle tags supported (members of an unsupported class too), whole lines verbatim
    # (class members under an `if 1:` header, columns kept), one synthetic file per source file.
    import ast
    out = []
    for n, row in enumerate(rows):
        if row.get("exclusion"):
            continue
        source = intake(Path(row["path"]).read_bytes())
        try:
            tree = ast.parse(source)
        except (SyntaxError, RecursionError, MemoryError, ValueError):
            continue
        lines, parts = source.splitlines(True), []

        def walk(body, floor, wrapped):
            spans = [(min([s.lineno] + [d.lineno for d in getattr(s, "decorator_list", [])]), s.end_lineno) for s in body]
            for i, (stmt, (lo, hi)) in enumerate(zip(body, spans)):
                alone = lo > (spans[i - 1][1] if i else floor) and (i + 1 == len(body) or hi < spans[i + 1][0])
                ok = False
                if alone:
                    text = "".join(lines[lo - 1:hi])
                    text += "" if text.endswith("\n") else "\n"
                    try:
                        ok = supported(stmt, text)
                    except Exception:
                        ok = False
                    if ok:
                        parts.append(("if 1:\n" if wrapped else "") + text)
                # A class that is not supported whole still yields its supported members.
                if isinstance(stmt, ast.ClassDef) and not ok:
                    head = max([stmt.lineno] + [x.end_lineno for x in stmt.bases + stmt.keywords])
                    walk(stmt.body, head, True)

        walk(tree.body, 0, False)
        if parts:
            path = OUT / f"seg-{label}-{n:04}.py"
            path.write_text("".join(parts))
            out.append({"path": str(path), "origin": row["path"], "exclusion": None, "segments": len(parts),
                        "bytes": len("".join(parts).encode())})
    return out


def evaluate(rows, label):
    build()
    pin()
    records = []
    for i, row in enumerate(rows):
        rec = dict(row)
        if row.get("exclusion"):
            rec["status"] = "excluded"
            records.append(rec)
            continue
        source = intake(Path(row["path"]).read_bytes())
        try:
            want, tree = oracle(source)
            rec["supported"] = supported(tree, source)
        except (SyntaxError, RecursionError, MemoryError) as exc:
            rec.update(status="oracle-failure", message=str(exc))
            records.append(rec)
            continue
        got = run(row["path"])
        rec.update({k: v for k, v in got.items() if k != "value"})
        if got["status"] == "parsed":
            rec["structural_diffs"], rec["location_diffs"] = compare(want, got["value"])
            rec["exact"] = not rec["structural_diffs"] and not rec["location_diffs"]
        if i % 20 == 0:
            js = run(row["path"], "js")
            rec["js_status"] = js["status"]
            rec["js_parity"] = js["status"] == got["status"] and js.get("value") == got.get("value")
        records.append(rec)
    counts = {k: sum(r.get("status") == k for r in records) for k in
              ["parsed", "unsupported", "limit", "syntax", "oracle-failure", "fail-stop", "excluded"]}
    counts.update(total=len(records), eligible=sum(not r.get("exclusion") for r in records),
                  supported=sum(r.get("supported", False) for r in records),
                  exact=sum(r.get("exact", False) for r in records),
                  structural_diffs=sum(len(r.get("structural_diffs", [])) for r in records),
                  location_diffs=sum(len(r.get("location_diffs", [])) for r in records),
                  supported_refusals=sum(r.get("supported", False) and r["status"] != "parsed" for r in records))
    if any("segments" in r for r in records):
        counts.update(segments=sum(r.get("segments", 0) for r in records), bytes=sum(r.get("bytes", 0) for r in records))
    times = sorted(r["ms"] for r in records if "ms" in r)
    counts["error"] = counts["syntax"]
    counts["supported_parsed"] = sum(r.get("supported", False) and r["status"] == "parsed" for r in records)
    counts["supported_exact"] = sum(r.get("supported", False) and r.get("exact", False) for r in records)
    counts["p50_ms"] = statistics.median(times) if times else None
    counts["p95_ms"] = times[min(len(times) - 1, int(len(times) * .95))] if times else None
    counts["parse_pct_eligible"] = 100 * counts["parsed"] / max(1, counts["eligible"])
    (OUT / (label + ".json")).write_text(json.dumps({"counts": counts, "records": records}, indent=2) + "\n")
    report = "# Parser results: " + label + "\n\n" + "\n".join(f"- {k}: {v}" for k, v in counts.items()) + "\n"
    report += "\nSupported subset determined independently by oracle AST tags. Zero supported corpus files is no positive parser evidence.\n"
    (OUT / "RESULTS.md").write_text(report)
    print(json.dumps(counts, indent=2))
    return not (counts["structural_diffs"] or counts["location_diffs"] or counts["supported_refusals"] or counts["fail-stop"] or any(r.get("js_parity") is False for r in records))


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--self-test", action="store_true")
    p.add_argument("--corpus", choices=["1", "2", "3"])
    p.add_argument("--segments", action="store_true", help="per-statement evidence: the supported statements of each corpus file")
    p.add_argument("--skip", type=int, default=0)
    p.add_argument("--files", type=int)
    p.add_argument("--fixtures", choices=["schema", "expressions", "statements", "all"])
    a = p.parse_args()
    if a.self_test or a.fixtures == "schema":
        self_test()
    elif a.corpus:
        rows, label = manifest(a.corpus), "tier-" + a.corpus
        if a.skip or a.files:
            rows, label = rows[a.skip:a.skip + a.files if a.files else None], f"{label}-{a.skip}"
        if a.segments:
            rows, label = segments(rows, label), label + "-segments"
        raise SystemExit(0 if evaluate(rows, label) else 1)
    else:
        rows = []
        for i, source in enumerate(EXPRESSIONS if a.fixtures == "expressions" else STATEMENTS if a.fixtures == "statements" else FIXTURES + EXPRESSIONS + STATEMENTS):
            path = OUT / f"fixture-{i:02}.py"
            path.write_text(source)
            rows.append({"path": str(path), "exclusion": None})
        raise SystemExit(0 if evaluate(rows, "fixtures") else 1)
