"""Verify the offline release payload; does not certify browser caching or clinical use."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODELS = {"neonatal_sepsis", "child_pneumonia", "preeclampsia_risk", "lbw_sga"}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(build):
    copied = []

    def identical(source):
        relative = source.relative_to(ROOT)
        released = build / "assets" / relative
        if not released.is_file() or sha256(source) != sha256(released):
            raise ValueError(f"Release asset missing or different: {relative}")
        copied.append(relative.as_posix())
        return released

    contracts_path = ROOT / "assets/models/research_contracts.json"
    contracts = json.loads(identical(contracts_path).read_text(encoding="utf-8"))
    if contracts.get("schema_version") != 1 or set(contracts["models"]) != MODELS:
        raise ValueError("Unexpected research contract/model set")
    artifacts = {}
    for name in sorted(MODELS):
        model = identical(ROOT / f"assets/models/{name}_int8_v1.tflite")
        metadata = identical(ROOT / f"assets/models/{name}_int8_v1_metrics.json")
        metrics = json.loads(metadata.read_text(encoding="utf-8"))
        contract = contracts["models"][name]
        digest = sha256(model)
        if digest != metrics["tflite_sha256"] or digest != contract["artifact_sha256"]:
            raise ValueError(f"Model/metadata hash mismatch: {name}")
        if contract["model_version"] != metrics["model_version"]:
            raise ValueError(f"Model version mismatch: {name}")
        if contract["clinical_use_allowed"] or contract["patient_output_allowed"]:
            raise ValueError(f"Unapproved patient output in release: {name}")
        artifacts[name] = digest

    audio = sorted((ROOT / "assets/audio").rglob("*.wav"))
    if len(audio) != 123:
        raise ValueError(f"Expected 123 preserved WAV assets, found {len(audio)}")
    for source in audio:
        released = identical(source)
        header = released.read_bytes()[:12]
        if header[:4] != b"RIFF" or header[8:12] != b"WAVE":
            raise ValueError(f"Invalid WAV header: {source.name}")
    for font in sorted((ROOT / "assets/fonts").glob("*.ttf")):
        identical(font)
    for required in ["index.html", "main.dart.js", "flutter_bootstrap.js",
                     "sqlite3.wasm", "canvaskit/canvaskit.wasm"]:
        path = build / required
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f"Missing local runtime: {required}")
    html = (build / "index.html").read_text(encoding="utf-8")
    if "fonts.googleapis.com" in html or "fonts.gstatic.com" in html:
        raise ValueError("Release HTML still loads external fonts")
    return {"passed": True, "model_sha256": artifacts, "wav_count": len(audio),
            "identical_source_assets": len(copied), "clinical_use_allowed": False,
            "scope": "Release payload integrity only; browser offline save/reload requires a separate test"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=Path, default=ROOT / "build/web")
    args = parser.parse_args()
    print(json.dumps(verify(args.build.resolve()), indent=2))
