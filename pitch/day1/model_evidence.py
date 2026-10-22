"""Dump, verbatim, the provenance + calibration + validation fields of each shipped
model, so the deck can carry real links, real techniques and real numbers.

Read-only. Output to a text file because the Windows console cannot encode every
codepoint in the citation strings.
"""

from __future__ import annotations

import json
from pathlib import Path

MODELS = Path(r"C:\Users\Alhaji_stunner\Videos\unicef\assets\models")
OUT = Path(r"C:\Users\Alhaji_stunner\Videos\unicef\pitch\day1\model_evidence.txt")

SCALARS = (
    "holdout_auc",
    "auc",
    "sensitivity",
    "specificity",
    "youden_j",
    "best_threshold",
    "fold_auc_mean",
    "fold_auc_std",
    "brier_score_cohort_scale",
    "n",
    "dataset",
    "method",
)


def walk(label: str, obj, depth: int, lines: list[str]) -> None:
    if isinstance(obj, dict):
        for k, v in obj.items():
            if isinstance(v, (dict, list)):
                walk(f"{k}", v, depth + 1, lines)
            else:
                lines.append(f"{'  ' * depth}{k}: {v}")
    elif isinstance(obj, list):
        for item in obj:
            if isinstance(item, dict):
                walk(label, item, depth + 1, lines)
                lines.append("")
            else:
                lines.append(f"{'  ' * depth}- {item}")


def main() -> None:
    out: list[str] = []
    for path in sorted(MODELS.glob("*_metrics.json")):
        m = json.loads(path.read_text(encoding="utf-8"))
        out.append("=" * 78)
        out.append(path.name)
        out.append("=" * 78)
        out.append(f"model_version: {m.get('model_version')}   trained_on: {m.get('trained_on')}")
        out.append(f"training_dataset: {m.get('training_dataset')}")
        out.append("")
        out.append("--- validation ---")
        walk("validation", m.get("validation", {}), 1, out)
        out.append("")
        out.append("--- external_validation (top level) ---")
        walk("external_validation", m.get("external_validation"), 1, out)
        out.append("")
        out.append("--- ghana_calibration ---")
        walk("ghana_calibration", m.get("ghana_calibration", {}), 1, out)
        out.append("")
        out.append("--- provenance (every cited source) ---")
        walk("provenance", m.get("provenance", {}), 1, out)
        out.append("")
        out.append("--- clinical_note ---")
        out.append(str(m.get("clinical_note")))
        out.append("")
        out.append("--- version_ladder ---")
        walk("version_ladder", m.get("version_ladder", {}), 1, out)
        out.append("")

    OUT.write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"wrote {OUT} ({OUT.stat().st_size/1024:.0f} KB)")


if __name__ == "__main__":
    main()
