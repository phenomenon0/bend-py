"""CPython tokenize parity: discard COMMENT/NL/ENCODING, postclassify KW as NAME."""
from normalize import OUT, pin, intake, differences
from manifest import manifest
from diff import build, run
import argparse
import io
import json
import token
import tokenize
from pathlib import Path

CASES = [
    "00x1 0_0x1 00e5 0_0.2\n", "'a\\\r\nb'\n",
    "", "# comment\n", "if x:\n\tpass\n\t# ignored\npass\n",
    "x = (1 +\n 2) # comment\n", "x = 1 + \\\n 2\n", "if x:\r\n\tpass\r\n",
    "if x:\n \f  pass\n", "r'a\\\\b' b'abc' u'é' f'{x}' br'hi' RF'''a\nb'''\n",
    "0 00 012 0x1_F 0b_11 0o77 1_000 1.2 .5 1. 1e-3 1_2.3_4e+5_6 1j 00j\n",
    "**= //= <<= >>= != == <= >= -> := ... @= &= |= ^=\n",
    "x = ('a' # concatenation\n 'b')", "a = '''a\r\nb'''\r\n", "é = '😀'\n",
]


def oracle_tokens(source):
    return [{"kind": token.tok_name[t.type], "text": t.string,
             "start": list(t.start), "end": list(t.end)}
            for t in tokenize.generate_tokens(io.StringIO(source).readline)
            if t.type not in {tokenize.COMMENT, tokenize.NL, tokenize.ENCODING}]


def norm(tokens, positions=False):
    return [{"kind": "NAME" if t["kind"] == "KW" else t["kind"], "text": t["text"],
             **({"start": t["start"], "end": t["end"]} if positions else {})} for t in tokens]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--files", type=int, default=200)
    a = p.parse_args()
    pin()
    build()
    rows = []
    for i, source in enumerate(CASES):
        path = OUT / f"lex-fixture-{i}.py"
        path.write_bytes(source.encode())
        rows.append({"path": str(path), "exclusion": None, "fixture": True})
    rows += manifest("lex", a.files)
    results = []
    for i, row in enumerate(rows):
        rec = dict(row)
        if row["exclusion"]:
            rec["status"] = "excluded"
            results.append(rec)
            continue
        try:
            want = oracle_tokens(intake(Path(row["path"]).read_bytes()))
        except (SyntaxError, tokenize.TokenError) as exc:
            rec.update(status="oracle-failure", message=str(exc))
            results.append(rec)
            continue
        got = run(row["path"], mode="lex")
        rec.update({k: v for k, v in got.items() if k != "value"})
        if got["status"] == "parsed":
            rec["diffs"] = differences(norm(want), norm(got["value"]))
            rec["position_diffs"] = differences(norm(want, True), norm(got["value"], True))
            if rec["diffs"]:
                (OUT / f"lex-failure-{i}.json").write_text(json.dumps({"want": want, "got": got["value"]}, indent=2))
        if row.get("fixture") or i % 20 == 0:
            js = run(row["path"], "js", "lex")
            rec["js_parity"] = js.get("value") == got.get("value") and js["status"] == got["status"]
        results.append(rec)
    counts = {"corpus_files": sum(not r.get("fixture") for r in results),
              "fixtures": len(CASES), "parsed": sum(r["status"] == "parsed" for r in results),
              "kind_text_diffs": sum(len(r.get("diffs", [])) for r in results),
              "position_diffs": sum(len(r.get("position_diffs", [])) for r in results),
              "fail_stops": sum(r["status"] == "fail-stop" for r in results),
              "refusals": sum(r["status"] not in {"parsed", "excluded", "oracle-failure"} for r in results),
              "oracle_failures": sum(r["status"] == "oracle-failure" for r in results),
              "js_samples": sum("js_parity" in r for r in results),
              "js_diffs": sum(r.get("js_parity") is False for r in results)}
    (OUT / "lex-results.json").write_text(json.dumps({"counts": counts, "records": results}, indent=2) + "\n")
    print(json.dumps(counts, indent=2))
    return int(bool(counts["kind_text_diffs"] or counts["fail_stops"] or counts["refusals"] or counts["js_diffs"]))


if __name__ == "__main__":
    raise SystemExit(main())
