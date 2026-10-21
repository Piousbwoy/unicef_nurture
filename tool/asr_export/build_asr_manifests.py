"""Hash the exported `asr-v1` packs and lay them out where the app can install them.

The app verifies every file of a hosted pack against `model_manifest.json` before
it will load a recogniser, so the manifest is built from the bytes on disk and
rebuilt whenever a model is swapped. The serve tree mirrors the asset path the
installer resolves against, which is what makes a local run honest: the same
`install()` code path that a real CDN would feed, over loopback HTTP.

  python tool/asr_export/build_asr_manifests.py
  python -m http.server 8000 -d data/serve
  flutter run -d windows --dart-define=VOICE_PACK_BASE_URL=http://localhost:8000
"""
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# pack folder -> the app's language name. Only languages with an answer set can
# be installed, so a stray folder here is a mistake, not a pack.
PACKS = {"dagbani_dondo": "Dagbani", "twi_akan": "Twi"}
SOURCE = {
    "dagbani_dondo": "https://huggingface.co/KhayaAI/w2v-bert-dga",
    "twi_akan": "https://huggingface.co/asr-africa/wav2vec2-xls-r-akan-20-hours",
}
LICENSE = "Apache-2.0"


def digest(path: Path) -> dict:
    with path.open("rb") as stream:
        if path.suffix == ".onnx" and stream.read(64).startswith(
            b"version https://git-lfs"
        ):
            raise ValueError(f"LFS pointer, not model weights: {path}")
        stream.seek(0)
        sha = hashlib.file_digest(stream, "sha256").hexdigest()
    return {"name": path.name, "bytes": path.stat().st_size, "sha256": sha}


def main() -> int:
    dev = ROOT / "data/asr_dev"
    serve = ROOT / "data/serve/assets/asr"
    for folder, language in PACKS.items():
        base = dev / folder
        if not (base / "model.onnx").exists():
            print(f"{folder}: no model.onnx, skipped")
            continue
        # Only the files the contract names. `model.fp32.onnx` and the export's
        # external-data leftovers stay out of the manifest, so they are never
        # downloaded, never hashed, and never mistaken for the pack.
        names = ["model.onnx", "frontend.json"]
        for optional in ("mel_filters.json", "window.json"):
            if (base / optional).exists():
                names.append(optional)
        records = [digest(base / name) for name in names]
        manifest = {
            "schema": 1,
            "contract": "asr-v1",
            "language": language,
            "source": SOURCE[folder],
            "license": LICENSE,
            "revision": records[0]["sha256"],
            "files": records,
        }
        (base / "model_manifest.json").write_text(
            json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
        )
        target = serve / language.lower()
        target.mkdir(parents=True, exist_ok=True)
        for name in names + ["model_manifest.json"]:
            shutil.copyfile(base / name, target / name)
        total = sum(record["bytes"] for record in records)
        print(
            f"{language} {folder}: {total:,} bytes over {len(records)} verified "
            f"artifacts -> {target}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
