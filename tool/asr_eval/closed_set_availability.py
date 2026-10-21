"""Throwaway - measurement only, not shippable code.

How often do the three clinical answers actually occur in the WaxalNLP gold
text? If they do not occur, closed-set answer accuracy is undefined on this
eval set and must be measured on app sentences instead.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from scoring import norm  # noqa: E402

ROOT = Path(__file__).resolve().parent
ANSWERS = {"dag": ["Ee", "Ayi", "Mi b\u025b mi"], "aka": []}

out = {}
for lang in ("dag", "aka"):
    rows = [json.loads(l) for l in
            (ROOT / "data" / lang / "manifest.jsonl").open(encoding="utf8")]
    per = {}
    for tgt in ANSWERS[lang]:
        tn = norm(tgt)
        exact = [r for r in rows if norm(r["text"]).split() == [tn]]
        word = [r for r in rows if tn in norm(r["text"]).split()]
        substr = [r for r in rows if tn in norm(r["text"])]
        per[tgt] = {"normalised_form": tn, "gold_rows_whole_utterance": len(exact),
                    "gold_rows_as_word": len(word), "gold_rows_as_substring": len(substr),
                    "example_ids": [r["id"] for r in word[:5]]}
    out[lang] = {"n_rows": len(rows), "answers": per}

(OUT := ROOT / "out" / "closed_set_availability.json").write_text(
    json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf8")
print("wrote closed_set_availability.json", flush=True)
sys.exit(0)
