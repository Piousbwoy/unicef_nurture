"""Audit the local conversation transcripts: what exists, how big, what date range.

Nothing here edits or deletes anything. It counts lines, roles and timestamps per
JSONL file so we can see which sessions survive on disk and whether an export is
worth doing. Output goes to a text file because the Windows console cannot encode
every codepoint that appears in chat text.
"""

from __future__ import annotations

import json
from collections import Counter
from datetime import datetime
from pathlib import Path

ROOT = Path(r"C:\Users\Alhaji_stunner\.qoder\cache\projects\unicef-f0a26800")
OUT = Path(r"C:\Users\Alhaji_stunner\Videos\unicef\pitch\day1\chat_audit.txt")


def text_of(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict):
                parts.append(str(block.get("text") or block.get("type") or ""))
            else:
                parts.append(str(block))
        return " ".join(parts)
    return str(content)


def main() -> None:
    lines_out: list[str] = []
    files = sorted(ROOT.rglob("*.jsonl"))
    lines_out.append(f"transcript files found: {len(files)}")
    for f in files:
        raw = f.read_bytes()
        lines = [ln for ln in raw.decode("utf-8", "replace").splitlines() if ln.strip()]
        roles: Counter[str] = Counter()
        stamps: list[str] = []
        kinds: Counter[str] = Counter()
        bad = 0
        for ln in lines:
            try:
                obj = json.loads(ln)
            except Exception:
                bad += 1
                continue
            kinds.update([str(obj.get("type") or obj.get("role") or "?")])
            roles.update([str(obj.get("role") or obj.get("type") or "?")])
            for key in ("timestamp", "created_at", "createdAt", "ts", "time"):
                v = obj.get(key)
                if isinstance(v, str) and v:
                    stamps.append(v)
                elif isinstance(v, (int, float)):
                    stamps.append(str(v))
        lines_out.append("")
        lines_out.append("=" * 72)
        lines_out.append(str(f.relative_to(ROOT)))
        lines_out.append(
            f"  size {len(raw)/1024:.0f} KB   records {len(lines)}   unparseable {bad}"
        )
        lines_out.append(f"  roles  {dict(roles.most_common(8))}")
        lines_out.append(f"  kinds  {dict(kinds.most_common(8))}")
        if stamps:
            lines_out.append(f"  first  {stamps[0]}")
            lines_out.append(f"  last   {stamps[-1]}")
        else:
            lines_out.append("  first/last  no timestamp field found in any record")
        mtime = datetime.fromtimestamp(f.stat().st_mtime)
        lines_out.append(f"  file mtime  {mtime:%Y-%m-%d %H:%M}")

    # Other caches that may hold conversation state the UI reads.
    lines_out.append("")
    lines_out.append("=" * 72)
    lines_out.append("other entries directly under the project cache root")
    lines_out.append("=" * 72)
    for p in sorted(ROOT.iterdir()):
        tag = "dir " if p.is_dir() else "file"
        lines_out.append(f"  {tag}  {p.name}")

    OUT.write_text("\n".join(lines_out) + "\n", encoding="utf-8")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
