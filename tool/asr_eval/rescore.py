"""Throwaway - measurement only, not shippable code.

Re-score an existing hyp_*.jsonl (partial runs included) so a killed job still
yields honest numbers with the true clip count.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from scoring import norm  # noqa: E402

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "out"

ANSWERS = {"dag": ["Ee", "Ayi", "Mi b\u025b mi"], "aka": []}


def rescore(path: Path, lang: str) -> dict:
    rows, truncated = [], 0
    for line in path.open(encoding="utf8"):
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            truncated += 1  # a killed run can leave a partial last line
    errs = [r for r in rows if str(r["hypothesis"]).startswith("__ERROR__")]
    ok = [r for r in rows if r not in errs]
    gold_chars = sum(len(r["norm_gold"].replace(" ", "")) for r in ok)
    gold_words = sum(max(len(r["norm_gold"].split()), 1) for r in ok)
    closed = {}
    for tgt in ANSWERS.get(lang, []):
        tn = norm(tgt)
        # a clip counts if the answer is a WORD of the gold text
        hits = [r for r in ok if tn in r["norm_gold"].split()]
        survives = sum(1 for r in hits if tn in r["norm_hyp"].split())
        closed[tgt] = {"gold_clips": len(hits), "survives": survives,
                       "accuracy": round(survives / len(hits), 4) if hits else None}
    audio = sum(r["duration"] for r in rows)
    wall = sum(r["infer_seconds"] for r in rows)
    return {
        "file": path.name, "lang": lang, "clips": len(rows), "clips_ok": len(ok),
        "errors": len(errs), "truncated_lines": truncated,
        "mean_cer": round(sum(r["cer"] for r in ok) / len(ok), 4) if ok else None,
        "mean_wer": round(sum(r["wer"] for r in ok) / len(ok), 4) if ok else None,
        "micro_cer": round(sum(r["cer"] * len(r["norm_gold"].replace(" ", "")) for r in ok)
                           / gold_chars, 4) if gold_chars else None,
        "micro_wer": round(sum(r["wer"] * max(len(r["norm_gold"].split()), 1) for r in ok)
                           / gold_words, 4) if gold_words else None,
        "closed_set": closed,
        "audio_seconds": round(audio, 1), "wall_seconds": round(wall, 1),
        "rtf_mean": round(wall / audio, 3) if audio else None,
    }


def main() -> int:
    out = {}
    for p in sorted(OUT.glob("hyp_*.jsonl")):
        tag = p.stem.replace("hyp_", "")
        sfp = OUT / f"score_{tag}.json"
        lang = None
        if sfp.exists():
            lang = json.loads(sfp.read_text(encoding="utf8")).get("lang")
        if lang is None:
            lang = "aka" if "aka" in tag else "dag"
        out[tag] = rescore(p, lang)
    (OUT / "rescore.json").write_text(
        json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf8")
    print("wrote rescore.json", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
