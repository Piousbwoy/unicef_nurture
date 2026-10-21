"""Dump the shipped model provenance so the pitch never overstates it.

Reads assets/models/research_contracts.json plus each *_metrics.json and prints,
per model, exactly what the repo claims: the dataset string, the evidence kind,
whether clinical use is allowed, the age range the model was actually supported
on, and whatever evaluation numbers exist. Nothing is inferred here; a blank
field prints as blank, which is the point.
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODELS = ROOT / "assets" / "models"

contracts = json.loads((MODELS / "research_contracts.json").read_text(encoding="utf-8"))

for name, c in contracts.get("models", {}).items():
    print("=" * 72)
    print(name)
    print("=" * 72)
    for key in (
        "model_version",
        "model_type",
        "evidence",
        "evaluation_kind",
        "clinical_use_allowed",
        "patient_output_allowed",
        "cohort",
        "age_days_support",
        "dataset",
        "outcome",
    ):
        print(f"  {key:24} {c.get(key, '<<absent>>')}")
    ev = c.get("evaluation") or {}
    print(f"  {'evaluation keys':24} {sorted(ev) or '<<EMPTY - no independent evaluation recorded>>'}")
    for k, v in sorted(ev.items()):
        if isinstance(v, (int, float, str, bool)):
            print(f"      {k:20} {v}")
    lims = c.get("limitations") or []
    print(f"  {'limitations':24} {len(lims)}")
    for line in lims:
        print(f"      - {line}")

print()
print("#" * 72)
print("# metrics JSONs shipped beside the weights")
print("#" * 72)
for path in sorted(MODELS.glob("*_metrics.json")):
    m = json.loads(path.read_text(encoding="utf-8"))
    print(f"\n{path.name}")
    for key in (
        "model_version",
        "training_dataset",
        "trained_on",
        "validation",
        "external_validation",
        "calibration",
        "notes",
        "source",
    ):
        if key in m:
            val = m[key]
            if isinstance(val, dict):
                val = {k: v for k, v in val.items() if isinstance(v, (int, float, str, bool))}
            print(f"  {key:22} {val}")
    print(f"  {'other keys':22} {sorted(k for k in m if k not in {'model_version', 'training_dataset', 'trained_on', 'validation', 'external_validation', 'calibration', 'notes', 'source'})}")
