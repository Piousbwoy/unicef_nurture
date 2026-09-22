"""Compare the nano-twi Matcha-Vocos voice against the bundled Piper Twi baseline.

This is a *candidate comparison* tool, not a shipping dependency. It never touches
the Flutter app's models, never replaces the default speaker, and its output is not
a certification of naturalness — only a fluent human listener can approve a voice.

Safety / provenance (matches the approved plan boundaries):
- Only the pinned repository revision is downloaded, and only the four default
  acoustic/vocoder/token/espeak artifacts. No repository Python is executed and no
  unsafe checkpoint formats (.bin/.pt/.ckpt) are loaded — Matcha runs from ONNX.
- Every binary is checked against the SHA-256 recorded from the Hugging Face LFS
  metadata for that exact revision before it is used.
- sherpa-onnx is imported only from the isolated build/voice_compare_deps directory.
- The fixed public corpus is the SAME set already synthesized by
  test/piper_native_inference_test.dart (build/voice_samples/twi_baseline.json), so
  the two voices are heard on identical text.

Run (after `pip install --target build/voice_compare_deps sherpa-onnx==1.13.8`):
    python tool/compare_nano_twi.py
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVISION = "99862c520e5ae25fc0cc47a554c4bdcd17ce9967"
REPO = "ghananlpcommunity/nano-twi"
BASE_URL = f"https://huggingface.co/{REPO}/resolve/{REVISION}/sherpa-onnx/"
DEPS = ROOT / "build" / "voice_compare_deps"
CACHE = ROOT / "build" / "nano_twi"
OUTDIR = ROOT / "build" / "voice_samples" / "nano_twi"
BASELINE = ROOT / "build" / "voice_samples" / "twi_baseline.json"

# SHA-256 of the LFS payload at the pinned revision (Hugging Face `lfs.oid`).
# Files that are plain git blobs (tokens.txt) fall back to a size-only check and
# are re-verified by loading, so we never run code we cannot account for.
ARTIFACTS = {
    "twi_ep045_steps4.onnx": {
        "sha256": "2d11d0a75a12083c59d78a4c2aeb8c6ecd40b66c2b78dd26a0a8f08763ac2bc8",
        "bytes": 74053240,
    },
    "vocos-22khz-univ.onnx": {
        "sha256": "0574a135aa1db2de6e181050db2ec528496cacd4a4701fc5d7faf9f9804c0081",
        "bytes": 53884024,
    },
    "tokens.txt": {"bytes": 1098},
}


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def fetch(name: str) -> Path:
    """Download one pinned artifact and verify it before it is ever loaded."""
    target = CACHE / name
    if target.exists():
        meta = ARTIFACTS[name]
        if "sha256" in meta and _sha256(target) == meta["sha256"]:
            return target
        target.unlink()
    CACHE.mkdir(parents=True, exist_ok=True)
    url = BASE_URL + name
    print(f"downloading {url}", file=sys.stderr)
    tmp = target.with_suffix(target.suffix + ".part")
    with urllib.request.urlopen(url) as response, tmp.open("wb") as out:
        while chunk := response.read(1 << 20):
            out.write(chunk)
    meta = ARTIFACTS[name]
    if tmp.stat().st_size != meta["bytes"]:
        tmp.unlink()
        raise SystemExit(f"{name}: size mismatch after download")
    if "sha256" in meta and _sha256(tmp) != meta["sha256"]:
        tmp.unlink()
        raise SystemExit(f"{name}: SHA-256 mismatch against pinned revision")
    tmp.replace(target)
    return target


def fetch_espeak_data() -> Path:
    """Fetch the espeak-ng-data tree the repo bundles for this Matcha model.

    Only data files under the pinned path are downloaded; no code is executed.
    """
    data_dir = CACHE / "espeak-ng-data"
    if (data_dir / "phontab").exists():
        return data_dir
    api = (
        f"https://huggingface.co/api/models/{REPO}/tree/{REVISION}"
        "/sherpa-onnx/espeak-ng-data?recursive=true&limit=1000"
    )
    with urllib.request.urlopen(api) as response:
        entries = json.load(response)
    files = [e for e in entries if e.get("type") == "file"]
    if not files:
        raise SystemExit("no espeak-ng-data files found at the pinned revision")
    for entry in files:
        rel = entry["path"].split("sherpa-onnx/", 1)[1]
        dest = CACHE / rel
        if dest.exists():
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        lfs = entry.get("lfs")
        name = dest.name
        url = BASE_URL + rel
        with urllib.request.urlopen(url) as response, dest.open("wb") as out:
            while chunk := response.read(1 << 20):
                out.write(chunk)
        if lfs and _sha256(dest) != lfs["oid"]:
            dest.unlink()
            raise SystemExit(f"{rel}: espeak data SHA-256 mismatch")
    return data_dir


def build_engine():
    if str(DEPS) not in sys.path:
        sys.path.insert(0, str(DEPS))
    try:
        import sherpa_onnx  # type: ignore
    except Exception as exc:  # noqa: BLE001
        raise SystemExit(
            "sherpa-onnx is not importable from build/voice_compare_deps.\n"
            "Install it there first: python -m pip install --target "
            "build/voice_compare_deps --only-binary=:all: sherpa-onnx==1.13.8"
        ) from exc
    acoustic = fetch("twi_ep045_steps4.onnx")
    vocoder = fetch("vocos-22khz-univ.onnx")
    tokens = fetch("tokens.txt")
    data_dir = fetch_espeak_data()
    config = sherpa_onnx.OfflineTtsConfig(
        model=sherpa_onnx.OfflineTtsModelConfig(
            matcha=sherpa_onnx.OfflineTtsMatchaModelConfig(
                acoustic_model=str(acoustic),
                vocoder=str(vocoder),
                lexicon="",
                tokens=str(tokens),
                data_dir=str(data_dir),
                noise_scale=0.667,
                length_scale=1.0,
            ),
            num_threads=2,
            provider="cpu",
        ),
        max_num_sentences=1,
    )
    return sherpa_onnx.OfflineTts(config)


def write_wav(path: Path, samples, sample_rate: int) -> None:
    import wave
    import array

    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(sample_rate)
        pcm = array.array("h", [int(max(-1.0, min(1.0, s)) * 32767) for s in samples])
        handle.writeframes(pcm.tobytes())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sid", type=int, default=0)
    args = parser.parse_args()

    if not BASELINE.exists():
        raise SystemExit(
            "Run the Piper baseline first: flutter test "
            "test/piper_native_inference_test.dart --dart-define=RUN_NATIVE_VOICE=true"
        )
    baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
    corpus = [
        row
        for row in baseline["samples"]
        if row.get("category") == "upstream-reference" and row.get("status") == "generated"
    ]
    if not corpus:
        raise SystemExit("baseline contains no generated upstream-reference samples")

    OUTDIR.mkdir(parents=True, exist_ok=True)
    os.environ.setdefault("GLOG_logtostderr", "0")
    engine = build_engine()
    rows = []
    for index, row in enumerate(corpus):
        audio = engine.generate(row["text"], sid=args.sid, speed=1.0)
        name = f"nano_twi_{index:02d}.wav"
        write_wav(OUTDIR / name, list(audio.samples), audio.sample_rate)
        rows.append(
            {
                "category": row["category"],
                "text": row["text"],
                "file": name,
                "sampleRate": audio.sample_rate,
                "durationSeconds": len(audio.samples) / audio.sample_rate,
            }
        )
    report = {
        "candidate": f"{REPO}@{REVISION}",
        "acoustic": "twi_ep045_steps4.onnx",
        "vocoder": "vocos-22khz-univ.onnx",
        "sid": args.sid,
        "clinicalApproved": False,
        "humanListeningApproved": False,
        "baselineModel": "piper twi_piper speaker 29",
        "samples": rows,
    }
    (OUTDIR / "nano_twi_compare.json").write_text(
        json.dumps(report, indent=2), encoding="utf-8"
    )
    print(
        f"Wrote {len(rows)} candidate samples to {OUTDIR}.\n"
        "Listen against build/voice_samples/twi_baseline_*.wav. Automated checks do "
        "NOT certify naturalness — a fluent speaker must approve before any adoption."
    )


if __name__ == "__main__":
    main()
