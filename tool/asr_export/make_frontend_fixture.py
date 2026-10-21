"""Pin the Dart ASR frontend against HuggingFace's own feature extractor.

A recogniser fed the wrong features still transcribes fluently — it just means
nothing. So the export step ships a fixture produced by the *real* processor,
and `test/asr_frontend_fixture_test.dart` replays it through the Dart frontend
and fails on disagreement. Same trick that caught the tokenizer inversion in
Track A.

The same run writes the pack-shaped directory the app loads: the extractor's own
mel matrix and window plus the scalars of its recipe, so Dart consumes the
tables instead of re-deriving Kaldi's filter bank.

Run:  python tool/asr_export/make_frontend_fixture.py
      --repo KhayaAI/w2v-bert-dga --corpus data/dagbani --out test/fixtures/asr
"""
import argparse
import ast
import inspect
import json
import re
import textwrap
from pathlib import Path

import numpy as np
import soundfile as sf
from huggingface_hub import hf_hub_download
from transformers import SeamlessM4TFeatureExtractor

SR = 16000


def to_16k(samples: np.ndarray, source_sr: int) -> np.ndarray:
    """Linear interpolation, byte-for-byte the rule in recording_gate/speech
    probe, so the fixture tests the frontend and not a resampler difference."""
    if source_sr == SR:
        return samples
    count = int(round(len(samples) * SR / source_sr))
    pos = np.linspace(0, len(samples) - 1, count)
    return np.interp(pos, np.arange(len(samples)), samples).astype(np.float32)


def synthetic(seconds: float) -> np.ndarray:
    """Vibrato tone + a fricative band + a silence gap: energy in the places a
    word has energy, and a boundary the windowing has to land on exactly."""
    n = int(seconds * SR)
    t = np.arange(n, dtype=np.float32) / SR
    carrier = 0.5 * np.sin(2 * np.pi * 220 * t * (1 + 0.05 * np.sin(2 * np.pi * 5 * t)))
    noise = np.zeros(n, dtype=np.float32)
    rng = np.random.default_rng(3)
    band = rng.standard_normal(n).astype(np.float32)
    start, stop = int(0.45 * SR), int(0.75 * SR)
    noise[start:stop] = band[start:stop] * 0.25
    gap = np.ones(n, dtype=np.float32)
    gap[int(0.8 * SR):] = 0.0
    return ((carrier + noise) * gap * 0.6).astype(np.float32)


def probe_geometry(extractor) -> tuple[int, int]:
    """Window and hop in samples, measured by asking the real extractor how many
    analysis frames a clip of a given length yields. They set the frame count,
    and a wrong one warps every duration the decoder is shown."""

    def rows(n: int) -> int:
        try:
            return int(extractor._extract_fbank_features(np.zeros(n, np.float32)).shape[0])
        except Exception:
            return -1

    def first(predicate, low: int, high: int) -> int:
        while low < high:
            mid = (low + high) // 2
            if predicate(mid):
                high = mid
            else:
                low = mid + 1
        return low

    frame_length = first(lambda n: rows(n) >= 1, 1, 4000)
    hop_length = first(lambda n: rows(n) >= 2, frame_length, frame_length + 4000) - frame_length
    assert rows(frame_length + hop_length) == 2, "framing is not the linear rule"
    return frame_length, hop_length


def recipe(extractor) -> dict:
    """The frontend's scalars, read out of the installed transformers source.

    They are literals inside `_extract_fbank_features`, not attributes of the
    object, so parsing them keeps this tool honest: if the library changes the
    recipe, the pack changes with it instead of going on describing the old one.
    """
    tree = ast.parse(
        textwrap.dedent(inspect.getsource(type(extractor)._extract_fbank_features))
    )
    call = next(
        node
        for node in ast.walk(tree)
        if isinstance(node, ast.Call) and getattr(node.func, "id", "") == "spectrogram"
    )
    values = {
        kw.arg: kw.value.value
        for kw in call.keywords
        if isinstance(kw.value, ast.Constant)
    }
    source = textwrap.dedent(inspect.getsource(type(extractor).__call__))
    # ddof matters as much as epsilon: on a two-second clip 1 and 0 differ by
    # ~0.9% of scale, far more than the model tolerates.
    normalized = next(
        (line for line in source.splitlines() if "ddof" in line and "mean" in line), None
    )
    assert normalized and "np.sqrt" in normalized, (
        "per-band normalisation moved; read it before shipping it"
    )
    values["normalize_ddof"] = int(re.search(r"ddof\s*=\s*(\d+)", normalized).group(1))
    values["normalize_epsilon"] = float(
        re.search(r"\+\s*([0-9.eE+-]+)\)", normalized).group(1)
    )
    init = textwrap.dedent(inspect.getsource(type(extractor).__init__))
    bank = re.search(r"mel_filter_bank\((.*?)\n\s*\)", init, re.S).group(1)

    def constant(name: str):
        text = re.search(rf"{name}=([^,\n]+)", bank).group(1).strip()
        return eval(text, {"__builtins__": {}}, {"sampling_rate": extractor.sampling_rate})

    values["num_frequency_bins"] = constant("num_frequency_bins")
    values["min_frequency"] = constant("min_frequency")
    values["max_frequency"] = constant("max_frequency")
    values["mel_scale"] = re.search(r'mel_scale="(\w+)"', bank).group(1)
    values["window"] = re.search(r'window_function\(\d+, "(\w+)", periodic=(True|False)\)', init).groups()
    return values


def labels_of(repo: str, cache: str, model_config: dict) -> tuple[list[str], int]:
    """Index-ordered label inventory. Gaps in the vocabulary stay as their id
    string, because the CTC decoder indexes by position and a shifted label is a
    shifted answer."""
    vocab = json.loads(
        Path(hf_hub_download(repo, "vocab.json", cache_dir=cache)).read_text(encoding="utf8")
    )
    try:
        added = json.loads(
            Path(hf_hub_download(repo, "added_tokens.json", cache_dir=cache)).read_text(
                encoding="utf8"
            )
        )
    except Exception:
        added = {}
    by_id = {int(i): t for t, i in {**vocab, **added}.items()}
    count = int(model_config["vocab_size"])
    return [by_id.get(i, f"<{i}>") for i in range(count)], int(vocab["|"])


def write_pack(pack: Path, extractor, code: str, name: str, frame_length: int,
               hop_length: int, per_second: float, labels: list[str], blank_index: int,
               max_frames: int) -> None:
    mel = np.asarray(extractor.mel_filters, dtype=np.float64)
    window = np.asarray(extractor.window, dtype=np.float64)
    spec = recipe(extractor)
    assert spec["frame_length"] == frame_length and spec["hop_length"] == hop_length
    assert spec["fft_length"] == 2 * (spec["num_frequency_bins"] - 1), "onesided FFT width"
    assert mel.shape == (spec["num_frequency_bins"], extractor.num_mel_bins)
    assert window.shape == (spec["frame_length"],)
    quantized = lambda v: float(f"{float(v):.9g}")
    pack.mkdir(parents=True, exist_ok=True)
    (pack / "mel_filters.json").write_text(
        json.dumps(
            {
                # Row-major values[bin][band]. Saying which axis is which is the
                # point of this file: the transposed bank still produces a
                # plausible-looking spectrogram.
                "axes": ["frequency_bin", "mel_filter"],
                "shape": list(mel.shape),
                "num_frequency_bins": spec["num_frequency_bins"],
                "num_mel_filters": extractor.num_mel_bins,
                "min_frequency": spec["min_frequency"],
                "max_frequency": spec["max_frequency"],
                "mel_scale": spec["mel_scale"],
                "triangularize_in_mel_space": True,
                "norm": None,
                "values": [[quantized(v) for v in row] for row in mel],
            },
            separators=(",", ":"),
        ),
        encoding="utf8",
    )
    (pack / "window.json").write_text(
        json.dumps(
            {
                "name": spec["window"][0],
                "periodic": spec["window"][1] == "True",
                "length": int(window.shape[0]),
                "values": [quantized(v) for v in window],
            },
            separators=(",", ":"),
        ),
        encoding="utf8",
    )
    (pack / "frontend.json").write_text(
        json.dumps(
            {
                "language": {"code": code, "name": name},
                "audio": {
                    "sample_rate": SR,
                    "features": "seamless-fbank",
                    "frame_length": frame_length,
                    "hop_length": hop_length,
                    "fft_length": spec["fft_length"],
                    "mel_bins": extractor.num_mel_bins,
                    "input_dim": extractor.num_mel_bins * extractor.stride,
                    "stride": extractor.stride,
                    "power": spec["power"],
                    "preemphasis": spec["preemphasis"],
                    "remove_dc_offset": spec["remove_dc_offset"],
                    "mel_floor": spec["mel_floor"],
                    "log": spec["log_mel"],
                    "per_band_normalize": {
                        "mode": "zero-mean-unit-variance",
                        "epsilon": spec["normalize_epsilon"],
                        "ddof": spec["normalize_ddof"],
                    },
                    "pad_with": extractor.padding_value,
                    "frames_per_second": per_second,
                    "max_frames": max_frames,
                },
                "model": {
                    "inputs": list(extractor.model_input_names),
                    "labels": labels,
                    "num_labels": len(labels),
                    "blank_index": blank_index,
                },
            },
            indent=1,
        ),
        encoding="utf8",
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default="KhayaAI/w2v-bert-dga")
    ap.add_argument("--corpus", default="data/dagbani")
    ap.add_argument("--out", default="test/fixtures/asr")
    ap.add_argument("--pack", default="test/fixtures/asr/pack")
    ap.add_argument("--code", default="dag")
    ap.add_argument("--language", default="Dagbani")
    ap.add_argument("--max-frames", type=int, default=400)
    ap.add_argument("--seconds", type=float, default=1.2)
    ap.add_argument("--cache", default="tool/asr_eval/data/hf")
    args = ap.parse_args()

    cache = Path(args.cache)
    extractor = SeamlessM4TFeatureExtractor.from_pretrained(
        args.repo, cache_dir=str(cache)
    )
    preprocessor = json.loads(
        Path(hf_hub_download(args.repo, "preprocessor_config.json", cache_dir=str(cache))).read_text(
            encoding="utf8"
        )
    )
    model_config = json.loads(
        Path(hf_hub_download(args.repo, "config.json", cache_dir=str(cache))).read_text(
            encoding="utf8"
        )
    )

    clips = {"synthetic": synthetic(args.seconds)}
    manifest = Path(args.corpus, "metadata.jsonl")
    if manifest.exists():
        row = json.loads(manifest.read_text(encoding="utf8").splitlines()[0])
        samples, source_sr = sf.read(Path(args.corpus) / row["audio"])
        clips["real"] = to_16k(
            np.asarray(samples, dtype=np.float32)[: int(args.seconds * source_sr)],
            source_sr,
        )

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    fixtures = []
    for name, samples in clips.items():
        encoded = extractor(
            samples,
            sampling_rate=SR,
            return_attention_mask=True,
            padding=False,
            return_tensors="np",
        )
        features = np.asarray(encoded["input_features"], dtype=np.float32)
        if features.ndim == 3:
            assert features.shape[0] == 1, features.shape
            features = features[0]
        mask = np.asarray(encoded["attention_mask"], dtype=np.int32)
        if mask.ndim == 2:
            mask = mask[0]
        fixtures.append(
            {
                "name": name,
                "sample_rate": SR,
                # Full precision both ways. Rounded to seven decimals, the
                # samples alone re-feed the extractor a 1.4e-2 different feature,
                # which would be the fixture's error rather than the port's, and
                # would set a tolerance loose enough to hide a real recipe bug.
                "samples": [float(v) for v in samples],
                "input_features": [[float(v) for v in frame] for frame in features],
                "attention_mask": mask.tolist(),
            }
        )
        print(
            f"{name}: {len(samples) / SR:.2f}s -> "
            f"{features.shape[0]} x {features.shape[1]} features, {mask.sum()} frames attended"
        )

    recipe = {
        "repo": args.repo,
        "extractor": type(extractor).__name__,
        "preprocessor": preprocessor,
        # What the model consumes per frame, measured here rather than guessed:
        # the conv stack plus this stride reshape decide the frame rate, and an
        # error in it warps every duration the decoder sees.
        "model_input_dim": int(fixtures[0]["input_features"][0].__len__()),
        "frames_per_second": round(
            len(fixtures[0]["input_features"]) / args.seconds, 4
        ),
        "feature_projection": {
            k: model_config.get(k)
            for k in (
                "input_feat_per_channel",
                "feature_projection_input_dim",
                "feat_proj_dropout",
                "adapter_kernel_size_list",
                "adapter_stride_list",
                "num_adapter_layers",
            )
        },
    }
    (out / "frontend_recipe.json").write_text(
        json.dumps(recipe, indent=1), encoding="utf8"
    )
    (out / "frontend_fixtures.json").write_text(
        json.dumps(fixtures), encoding="utf8"
    )
    print(f"wrote {out}/frontend_fixtures.json ({(out / 'frontend_fixtures.json').stat().st_size} bytes)")

    frame_length, hop_length = probe_geometry(extractor)
    inventory, blank_index = labels_of(args.repo, args.cache, model_config)
    pack = Path(args.pack)
    write_pack(
        pack,
        extractor,
        args.code,
        args.language,
        frame_length,
        hop_length,
        recipe["frames_per_second"],
        inventory,
        blank_index,
        args.max_frames,
    )
    # cp1252 console: the inventory's glyphs go to the file, never to stdout.
    print(
        f"pack {pack}: {frame_length}/{hop_length} framing, {len(inventory)} labels, "
        f"blank={blank_index}, inputs={list(extractor.model_input_names)}, "
        f"mel {np.asarray(extractor.mel_filters).shape}, "
        f"{(pack / 'mel_filters.json').stat().st_size} byte bank"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
