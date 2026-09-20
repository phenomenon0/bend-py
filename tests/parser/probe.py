"""Production intake and classified exit-1 checks, on both emitted backends."""
from normalize import OUT, pin
from diff import build, run
import json


def main():
    pin()
    build()
    cases = [("empty", b"", "parsed"), ("invalid", b"\xff", "syntax"),
             ("truncated", b"\xf0\x9f", "syntax"), ("surrogate", b"\xed\xa0\x80", "syntax"),
             ("overlong", b"\xc0\x80", "syntax"), ("bom", b"\xef\xbb\xbf", "parsed")]
    records = []
    for name, raw, expected in cases:
        path = OUT / ("intake-" + name + ".py")
        path.write_bytes(raw)
        for lane in ("c", "js"):
            got = run(path, lane)
            records.append({"case": name, "lane": lane, **got})
            assert got["status"] == expected, records[-1]
    # Place a two-byte scalar across the 64 KiB File.read_bytes boundary.
    boundary = OUT / "intake-boundary.py"
    boundary.write_bytes(b"#" + b" " * 65534 + "é\n".encode())
    for lane in ("c", "js"):
        got = run(boundary, lane, "lex")
        assert got["status"] == "parsed", got
        records.append({"case": "chunk-boundary", "lane": lane, **got})
    (OUT / "intake.json").write_text(json.dumps(records, indent=2) + "\n")
    print(f"Intake/exit-1: {len(records)}/{len(records)} C/JS checks")


if __name__ == "__main__":
    main()
