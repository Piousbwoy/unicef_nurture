"""Quantize complete, validated Marian graphs without touching installed assets."""
import argparse
import json
import shutil
from pathlib import Path

import numpy as np
from onnxruntime.quantization import QuantType, quantize_dynamic
from transformers import GenerationConfig

from marian_validation import greedy, sessions, write_json, write_manifest

ROOT = Path(__file__).resolve().parents[1]


def build(language, *, verify_only=False):
    source = ROOT / "build" / "marian_reference" / f"translation_{language}"
    target = ROOT / "build" / "marian_int8" / f"translation_{language}"
    manifest = json.loads((source / "model_manifest.json").read_text(encoding="utf-8"))
    target.mkdir(parents=True, exist_ok=True)
    if not verify_only:
        for record in manifest["files"]:
            name = record["name"]
            if name.endswith(".onnx"):
                quantize_dynamic(str(source / name), str(target / name),
                    weight_type=QuantType.QInt8, per_channel=True,
                    op_types_to_quantize=["MatMul", "Gather"])
            else:
                shutil.copyfile(source / name, target / name)
    encoder, decoder = sessions(target)
    config = GenerationConfig.from_pretrained(target, local_files_only=True)
    reference = json.loads((source / "generation_fixtures.json").read_text(encoding="utf-8"))
    comparisons = []
    for fixture in reference:
        actual = greedy(encoder, decoder, np.array([fixture["source_ids"]], dtype=np.int64), config)
        comparisons.append({"text": fixture["text"], "reference_ids": fixture["generated_ids"],
            "candidate_ids": actual, "exact_match": actual == fixture["generated_ids"]})
    size = sum(path.stat().st_size for path in target.iterdir() if path.is_file())
    voice = ROOT / "assets" / "tts" / f"{language}_piper" / "model.onnx"
    report = {"translation_bytes": size, "translation_and_voice_bytes": size + voice.stat().st_size,
        "within_250_mib_target": size + voice.stat().st_size <= 250 * 1024 * 1024,
        "all_reference_ids_match": all(item["exact_match"] for item in comparisons),
        "comparisons": comparisons, "wasm_verified": False, "clinical_reviewed": False}
    write_json(target / "quantization_report.json", report)
    if report["all_reference_ids_match"]:
        provenance = json.loads((target / "provenance.json").read_text(encoding="utf-8"))
        provenance["quantization"] = "dynamic-QInt8-MatMul-Gather-per-channel"
        write_json(target / "provenance.json", provenance)
        write_manifest(target, provenance)
    print(json.dumps({key: value for key, value in report.items() if key != "comparisons"}, indent=2))
    if not report["all_reference_ids_match"]:
        raise SystemExit("Candidate differs from reference. Not activated; review required.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("language", choices=["hausa", "twi"])
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    build(args.language, verify_only=args.verify_only)
