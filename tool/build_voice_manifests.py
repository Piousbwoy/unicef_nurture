"""Hash the ONNX voice artifacts and their matching frontend metadata.

Each pack is `assets/tts/<dir>` with model.onnx + model.onnx.json (plus the
IPA rules file for the phoneme-frontend packs). The manifest is what the app
verifies before loading, so it must be rebuilt whenever a model is swapped.

Run:  python tool/build_voice_manifests.py
"""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# dir → (language, source, licence, extra artifacts, rules file)
PACKS = {
    "hausa_piper": ("Hausa", "adab-tech/murya-piper-hausa-tts", "CC-BY-NC-SA-4.0",
                    [], False),
    "twi_piper": ("Twi", "michsethowusu/stable-twi-tts", "CC-BY-NC-4.0",
                  ["voices.json", "frontend_provenance.json"], True),
    # Character-orthography VITS exported straight from the Hugging Face
    # checkpoint (see nlp_upgrade/export_vits.py); inference scales are baked,
    # so the pack carries no scales tensor and no IPA rules file.
    "dagbani_piper": ("Dagbani", "ghananlpcommunity/dagbani_tts-2025_v2",
                      "UNLICENSED - do not publish until the author states a licence",
                      [], False),
    "twi_farmerline": ("Twi", "FarmerlineML/main_twi_TTS", "CC-BY-4.0", [], False),
    "twi_mms": ("Twi", "facebook/mms-tts-aka", "CC-BY-NC-4.0", [], False),
    "hausa_mms": ("Hausa", "facebook/mms-tts-hau", "CC-BY-NC-4.0", [], False),
}


def digest(path: Path) -> dict:
    with path.open("rb") as stream:
        if path.suffix == ".onnx" and stream.read(64).startswith(b"version https://git-lfs"):
            raise ValueError(f"LFS pointer, not model weights: {path}")
        stream.seek(0)
        sha = hashlib.file_digest(stream, "sha256").hexdigest()
    return {"name": path.name, "bytes": path.stat().st_size, "sha256": sha}


def main():
    for folder, (language, source, license_name, extra, has_rules) in PACKS.items():
        base = ROOT / "assets" / "tts" / folder
        if not (base / "model.onnx").exists():
            print(f"{folder}: no model.onnx, skipped")
            continue
        names = ["model.onnx", "model.onnx.json"] + (["twi_rules.json"] if has_rules else []) + extra
        records = [digest(base / name) for name in names]
        manifest = {
            "schema": 1, "contract": "piper-v1", "language": language,
            "source": f"https://huggingface.co/{source}", "license": license_name,
            "revision": records[0]["sha256"], "files": records,
        }
        (base / "model_manifest.json").write_text(
            json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        print(f"{language} {folder}: {sum(r['bytes'] for r in records):,} bytes, "
              f"{len(records)} verified artifacts")


if __name__ == "__main__":
    main()
