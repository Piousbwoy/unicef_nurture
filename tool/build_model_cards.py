"""Builds model cards from the evaluation artefacts that already exist.

The rigour in this repository — grouped bootstrap intervals, packaging gates,
dataset SHA lineage, conformal margins — lived in JSON files nobody could see.
This renders it into two artefacts from one source:

  docs/MODEL_CARD.md              for humans (judges, clinicians, reviewers)
  assets/models/model_cards.json  for the app's evidence screen

It invents no numbers. Every value is read from an existing file; anything
absent is reported as absent rather than filled in.
"""

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MODELS = ROOT / "assets" / "models"
DOCS = ROOT / "docs"

# Display order: the only model with real patient data leads, and the three
# simulated artefacts follow so they cannot borrow its credibility.
ORDER = ["neonatal_sepsis", "preeclampsia_risk", "child_pneumonia", "lbw_sga"]


def flatten(node, prefix=""):
    """Dotted key/value pairs for every leaf, so no metric is silently dropped."""
    if isinstance(node, dict):
        for key, value in node.items():
            yield from flatten(value, f"{prefix}{key}.")
    elif isinstance(node, list):
        yield prefix.rstrip("."), node
    else:
        yield prefix.rstrip("."), node


def load_json(path):
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def metrics_for(name):
    for path in sorted(MODELS.glob("*_metrics.json")):
        data = load_json(path)
        if data and data.get("model_name") == name:
            return data
    return None


def contract_for(name, contracts):
    """Tolerant lookup: contracts may key models by name, by list, or nest."""
    def matches(entry):
        return isinstance(entry, dict) and (
            entry.get("model_name") == name or entry.get("name") == name
        )

    def search(node, depth=0):
        if depth > 3:
            return None
        if isinstance(node, dict):
            if matches(node):
                return node
            if name in node and isinstance(node[name], dict):
                inner = node[name]
                return inner if inner else None
            for value in node.values():
                found = search(value, depth + 1)
                if found is not None:
                    return found
        elif isinstance(node, list):
            for entry in node:
                found = search(entry, depth + 1)
                if found is not None:
                    return found
        return None

    found = search(contracts)
    return found or {}


def permitted_use(contract):
    if contract.get("clinical_use_allowed") is True:
        return "clinical use permitted by contract"
    if contract.get("patient_output_allowed") is True:
        scope = contract.get("output_scope") or "research"
        return f"experimental display only ({scope}); clinical use not permitted"
    return "no patient-facing output permitted"


def card(name, metrics, contract):
    validation = (metrics or {}).get("validation") or {}
    internal = validation.get("internal") or {}
    external = validation.get("external") or {}
    limitations = contract.get("limitations") or []
    calibration = contract.get("calibration") or {}
    return {
        "name": name,
        "version": (metrics or {}).get("model_version")
        or contract.get("model_version"),
        "evidence": contract.get("evidence")
        or ("legacy_real_data" if "REAL" in str((metrics or {}).get("training_dataset", "")) else "unknown"),
        "dataset": (metrics or {}).get("training_dataset"),
        "cohort": contract.get("cohort"),
        "artifact_sha256": contract.get("artifact_sha256"),
        "evaluation_kind": contract.get("evaluation_kind"),
        "permitted_use": permitted_use(contract),
        "clinical_use_allowed": contract.get("clinical_use_allowed") is True,
        "patient_output_allowed": contract.get("patient_output_allowed") is True,
        "calibration_validated_for_artifact": calibration.get("validated_for_artifact"),
        "internal_metrics": dict(flatten(internal)),
        "external_metrics": dict(flatten(external)),
        "features_present": (metrics or {}).get("features_present", []),
        "features_zero_imputed": (metrics or {}).get("features_zero_imputed", []),
        "limitations": limitations,
        "notes": (metrics or {}).get("clinical_note"),
        "has_metrics_file": metrics is not None,
    }


def md_table(pairs, empty="not recorded"):
    if not pairs:
        return f"_{empty}._\n"
    lines = ["| metric | value |", "| --- | --- |"]
    for key, value in pairs:
        if isinstance(value, (list, dict)):
            # Long tables belong in the JSON, not in a line of markdown.
            shown = f"{len(value)} entries (see model_cards.json)"
        else:
            shown = value
        lines.append(f"| `{key}` | {shown} |")
    return "\n".join(lines) + "\n"


def render(cards, generated_at):
    out = [
        "# CareBridge AI — Model Cards",
        "",
        "Generated from `assets/models/*_metrics.json` and",
        "`assets/models/research_contracts.json` by `tool/build_model_cards.py`.",
        f"Generated: {generated_at}",
        "",
        "**These cards describe research artefacts.** No model in this repository",
        "is validated for clinical use in Northern Ghana. The deterministic",
        "WHO/GHS protocol engines make every clinical decision; models may supply",
        "an experimental, clearly-labelled signal and never change treatment or",
        "referral.",
        "",
        "## Summary",
        "",
        "| model | evidence | patient output | clinical use | evaluated |",
        "| --- | --- | --- | --- | --- |",
    ]
    for c in cards:
        out.append(
            "| {name} | {evidence} | {po} | {cu} | {ev} |".format(
                name=c["name"],
                evidence=c["evidence"],
                po="yes" if c["patient_output_allowed"] else "no",
                cu="yes" if c["clinical_use_allowed"] else "no",
                ev=c["evaluation_kind"] or "not recorded",
            )
        )
    out.append("")

    for c in cards:
        out += [
            f"## {c['name']}",
            "",
            f"- **Version:** {c['version'] or 'not recorded'}",
            f"- **Training data:** {c['dataset'] or 'not recorded'}",
            f"- **Cohort:** {c['cohort'] or 'not recorded'}",
            f"- **Permitted use:** {c['permitted_use']}",
            f"- **Artifact SHA-256:** `{c['artifact_sha256'] or 'not recorded'}`",
            f"- **Calibration validated for this artifact:** "
            f"{c['calibration_validated_for_artifact'] if c['calibration_validated_for_artifact'] is not None else 'not recorded'}",
            "",
        ]
        if not c["has_metrics_file"]:
            out += ["_No metrics file found for this model._", ""]
        out += ["### Internal validation", ""]
        out.append(md_table(list(c["internal_metrics"].items())))
        if c["external_metrics"]:
            out += ["### External / out-of-domain checks", ""]
            out.append(md_table(list(c["external_metrics"].items())))
        else:
            out += ["### External / out-of-domain checks", "", "_None recorded._", ""]
        if c["features_present"] or c["features_zero_imputed"]:
            out += [
                "### Inputs",
                "",
                f"- Observed at inference: {', '.join(c['features_present']) or 'none'}",
                f"- Fixed / zero-imputed: {len(c['features_zero_imputed'])} "
                f"({', '.join(c['features_zero_imputed']) or 'none'})",
                "",
            ]
        if c["limitations"]:
            out += ["### Limitations", ""]
            out += [f"- {item}" for item in c["limitations"]]
            out.append("")
        if c["notes"]:
            out += ["### Notes", "", c["notes"], ""]
    return "\n".join(out)


def main():
    contracts_path = MODELS / "research_contracts.json"
    contracts = load_json(contracts_path)
    if contracts is None:
        print(f"missing {contracts_path}", file=sys.stderr)
        return 1

    names = list(ORDER)
    for path in sorted(MODELS.glob("*_metrics.json")):
        data = load_json(path) or {}
        name = data.get("model_name")
        if name and name not in names:
            names.append(name)

    cards = []
    for name in names:
        metrics = metrics_for(name)
        contract = contract_for(name, contracts)
        if metrics is None and not contract:
            continue
        cards.append(card(name, metrics, contract))

    from datetime import datetime, timezone

    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    DOCS.mkdir(parents=True, exist_ok=True)
    (DOCS / "MODEL_CARD.md").write_text(render(cards, generated_at), encoding="utf-8")
    (MODELS / "model_cards.json").write_text(
        json.dumps({"generated_at": generated_at, "cards": cards}, indent=2),
        encoding="utf-8",
    )
    print(f"wrote {len(cards)} cards: {', '.join(c['name'] for c in cards)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
