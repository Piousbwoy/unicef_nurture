"""Pin the Dart raw-waveform frontend against the real Python extractor.

`asr-africa/wav2vec2-xls-r-akan-20-hours` is fed `input_values` that are only the
layer-normalised samples, so the app's whole frontend is two passes over the
buffer. That is easy to write and easy to get subtly wrong (sample vs population
variance, epsilon in or out of the root), so it gets a fixture like every other
frontend in this app: real clips, the extractor's own numbers, and
`test/asr_waveform_fixture_test.dart` asserting they agree.

  python tool/asr_export/make_waveform_fixture.py
"""
import json
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tool/asr_eval"))
from score_dondo import to_16k  # noqa: E402

OUT = REPO_ROOT / "test/fixtures/asr/waveform_fixtures.json"
PACK = REPO_ROOT / "test/fixtures/asr/waveform_pack"
CLIP_SECONDS = 1.2


def real_clip() -> np.ndarray:
    manifest = REPO_ROOT / "tool/asr_eval/data/aka/manifest.jsonl"
    row = json.loads(manifest.read_text(encoding="utf8").splitlines()[0])
    samples, rate = sf.read(row["abs_path"], dtype="float32")
    if samples.ndim > 1:
        samples = samples.mean(axis=1)
    samples = to_16k(np.asarray(samples, dtype=np.float32), rate)
    return samples[: int(CLIP_SECONDS * 16000)]


def synthetic_clip() -> np.ndarray:
    # Deterministic, and not white noise: two partials plus a DC offset, so a
    # frontend that forgets to remove the mean cannot pass.
    t = np.arange(int(CLIP_SECONDS * 16000), dtype=np.float32) / 16000.0
    wave = 0.35 * np.sin(2 * np.pi * 220 * t) + 0.15 * np.sin(2 * np.pi * 1400 * t)
    return (wave + 0.05).astype(np.float32)


def main() -> int:
    from transformers import AutoFeatureExtractor, AutoTokenizer

    repo = "asr-africa/wav2vec2-xls-r-akan-20-hours"
    extractor = AutoFeatureExtractor.from_pretrained(repo)
    tokenizer = AutoTokenizer.from_pretrained(repo)

    fixtures = []
    for name, samples in (
        ("synthetic", synthetic_clip()),
        ("real waxal aka clip 0", real_clip()),
    ):
        encoded = extractor([samples], sampling_rate=16000, return_attention_mask=True)
        values = np.asarray(encoded["input_values"], dtype=np.float32)
        mask = np.asarray(encoded["attention_mask"])
        if values.ndim == 3:
            values = values.reshape(values.shape[0], -1)
        assert values.ndim == 2 and values.shape[0] == 1, values.shape
        fixtures.append(
            {
                "name": name,
                "sample_rate": 16000,
                "samples": [float(v) for v in samples],
                # The extractor pads to a multiple of its conv stride; the app
                # feeds an unpadded take, so only the real length is comparable.
                "input_values": [float(v) for v in values[0, : len(samples)]],
                "attention_mask": [int(v) for v in mask[0, : len(samples)]],
            }
        )
        print(
            f"{name}: {len(samples)} samples, mean {samples.mean():+.5f}, "
            f"std {samples.std():.5f} -> normalised std "
            f"{values[0, :len(samples)].std():.5f}"
        )

    OUT.write_text(json.dumps(fixtures), encoding="utf8")

    vocab = dict(tokenizer.get_vocab())
    labels = [None] * len(vocab)
    for token, index in vocab.items():
        labels[index] = token
    contract = {
        "language": {"code": "twi"},
        "audio": {
            "sample_rate": 16000,
            "features": "waveform",
            "input_dim": 1,
            "normalize_epsilon": 1e-7,
            "frames_per_second": 16000,
            "max_frames": 64000,
        },
        "model": {
            "inputs": ["input_values", "attention_mask"],
            "labels": labels,
            "num_labels": len(labels),
            "blank_index": int(tokenizer.pad_token_id),
        },
    }
    PACK.mkdir(parents=True, exist_ok=True)
    (PACK / "frontend.json").write_text(json.dumps(contract, indent=1), encoding="utf8")
    print(f"wrote {OUT.name} and {PACK / 'frontend.json'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
