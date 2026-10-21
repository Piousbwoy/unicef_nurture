"""Throwaway - measurement only, not shippable code. Final consolidation."""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rescore import rescore  # noqa: E402

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "out"

# regenerate manifests for both languages from the fetched clips
import unicodedata  # noqa: E402
from scoring import norm  # noqa: E402

summary = {}
for tag, lang in [("tiny_dag", "dag"), ("tiny_aka", "aka")]:
    p = OUT / f"hyp_{tag}.jsonl"
    if p.exists():
        summary[tag] = rescore(p, lang)

summary["_rtf_probe"] = json.loads((OUT / "rtf_probe.json").open(encoding="utf8").read()) \
    if (OUT / "rtf_probe.json").exists() else None
summary["_downloads"] = json.loads((OUT / "downloads.json").open(encoding="utf8").read()) \
    if (OUT / "downloads.json").exists() else None
summary["_closed_availability"] = json.loads(
    (OUT / "closed_set_availability.json").open(encoding="utf8").read())
summary["_ortho"] = json.loads((OUT / "orthography.json").open(encoding="utf8").read())
summary["_evalset"] = json.loads((OUT / "evalset_stats.json").open(encoding="utf8").read())

# what the app actually asks a listener to get right
app_answers = {"dag": ["Ee", "Ayi", "Mi b\u025b mi"], "aka": "none localised in app"}
summary["_app_answers"] = app_answers

# gold/hyp examples for the report
ex = {}
for tag in ("tiny_dag", "tiny_aka"):
    p = OUT / f"hyp_{tag}.jsonl"
    rows = []
    for line in p.open(encoding="utf8"):
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    ex[tag] = [{"gold": r["text"][:70], "hyp": r["hypothesis"][:90], "cer": r["cer"],
                "wer": r["wer"]} for r in rows[:3]]
summary["_examples"] = ex

(OUT / "final_summary.json").write_text(
    json.dumps(summary, indent=1, ensure_ascii=False) + "\n", encoding="utf8")
print("wrote final_summary.json", flush=True)
sys.exit(0)
