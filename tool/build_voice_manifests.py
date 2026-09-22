"""Hash the existing ONNX voice artifacts and their matching frontend metadata."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODELS = {
    "hausa_piper": ("Hausa", "adab-tech/murya-piper-hausa-tts", "CC-BY-NC-SA-4.0"),
    "twi_piper": ("Twi", "michsethowusu/stable-twi-tts", "CC-BY-NC-4.0"),
}


def main():
    for folder, (language, source, license_name) in MODELS.items():
        base = ROOT / "assets" / "tts" / folder
        names = ["model.onnx", "model.onnx.json"]
        if language == "Twi":
            names += ["twi_rules.json", "voices.json", "frontend_provenance.json"]
        records = []
        for name in names:
            path = base / name
            with path.open("rb") as stream:
                if name.endswith(".onnx") and stream.read(64).startswith(b"version https://git-lfs"):
                    raise ValueError(f"LFS pointer, not model weights: {path}")
                stream.seek(0)
                digest = hashlib.file_digest(stream, "sha256").hexdigest()
            records.append({"name": name, "bytes": path.stat().st_size, "sha256": digest})
        manifest = {
            "schema": 1, "contract": "piper-v1", "language": language,
            "source": f"https://huggingface.co/{source}", "license": license_name,
            "revision": records[0]["sha256"], "files": records,
        }
        (base / "model_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        print(f"{language}: {sum(r['bytes'] for r in records):,} bytes, {len(records)} verified artifacts")


if __name__ == "__main__":
    main()
