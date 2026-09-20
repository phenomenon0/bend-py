"""Deterministic hashed corpus manifests, never imports or executes corpus code."""
from normalize import OUT, intake
import argparse
import hashlib
import json
import os
import sysconfig
from pathlib import Path

TOOLS = Path.home() / "Documents/Project/llm-wiki/tools"
FORBIDDEN = Path.home() / "Documents/Project/bend"


def paths(tier):
    if tier == "1":
        return sorted(TOOLS.glob("*.py"))
    base = Path(sysconfig.get_path("stdlib")) if tier in {"3", "lex"} else Path.home() / "Documents/Project"
    found = list(TOOLS.glob("*.py")) if tier == "lex" else []
    for root, dirs, files in os.walk(base, followlinks=False):
        dirs[:] = sorted(d for d in dirs if d not in {".git", ".venv", "venv", "node_modules", "site-packages", "_out", "__pycache__"}
                         and not (Path(root) / d).is_symlink() and Path(root) / d != FORBIDDEN)
        found.extend(Path(root) / f for f in sorted(files) if f.endswith(".py"))
    ordered = sorted(set(found))
    if tier == "lex":
        tools = sorted(TOOLS.glob("*.py"))
        return tools + [p for p in ordered if p not in tools]
    return ordered


def manifest(tier="1", limit=None):
    records, eligible = [], 0
    for path in paths(tier):
        row = {"path": str(path), "sha256": None, "size": None, "exclusion": None}
        if path.is_symlink():
            row["exclusion"] = "symlink"
        else:
            try:
                raw = path.read_bytes()
                row.update(size=len(raw), sha256=hashlib.sha256(raw).hexdigest())
                if len(raw) > 1048576:
                    row["exclusion"] = "over-1-MiB"
                else:
                    intake(raw)
            except (OSError, UnicodeError, ValueError, SyntaxError) as exc:
                row["exclusion"] = type(exc).__name__ + ":" + str(exc)
        records.append(row)
        eligible += row["exclusion"] is None
        if limit is not None and eligible >= limit:
            break
    target = OUT / ("corpus-" + tier + ".jsonl")
    target.write_text("".join(json.dumps(r) + "\n" for r in records))
    return records


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--tier", default="1", choices=["1", "2", "3", "lex"])
    p.add_argument("--limit", type=int)
    a = p.parse_args()
    rows = manifest(a.tier, a.limit)
    print(f"manifest: {len(rows)} files, {sum(r['exclusion'] is None for r in rows)} eligible")
