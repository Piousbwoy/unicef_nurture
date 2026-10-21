"""Scratch: measure what the live SeamlessM4T extractor actually does.

Throwaway diagnostic; `make_frontend_fixture.py` is the thing that ships.
"""
import ast
import inspect
import json
import textwrap
from pathlib import Path

import numpy as np
import transformers
from transformers import SeamlessM4TFeatureExtractor

SR = 16000
CACHE = "tool/asr_eval/data/hf"
ex = SeamlessM4TFeatureExtractor.from_pretrained(
    "KhayaAI/w2v-bert-dga", cache_dir=CACHE, local_files_only=True
)
out = {}
out["mel_shape"] = list(np.asarray(ex.mel_filters).shape)
out["win_shape"] = list(np.asarray(ex.window).shape)
out["mel_dtype"] = str(np.asarray(ex.mel_filters).dtype)
out["stride"] = ex.stride
out["padding_value"] = ex.padding_value
out["model_input_names"] = list(ex.model_input_names)
out["num_mel_bins"] = ex.num_mel_bins
out["feature_size"] = ex.feature_size
out["transformers"] = transformers.__version__

src = textwrap.dedent(inspect.getsource(type(ex)._extract_fbank_features))
for node in ast.walk(ast.parse(src)):
    if isinstance(node, ast.Call) and getattr(node.func, "id", None) == "spectrogram":
        out["fbank"] = {
            k.arg: k.value.value
            for k in node.keywords
            if isinstance(k.value, ast.Constant)
        }
out["norm_lines"] = [
    line.strip()
    for line in textwrap.dedent(inspect.getsource(type(ex).__call__)).splitlines()
    if "ddof" in line or "do_normalize_per_mel_bins" in line
]
out["init_lines"] = [
    line.strip()
    for line in textwrap.dedent(inspect.getsource(type(ex).__init__)).splitlines()
    if "num_frequency_bins" in line or "min_frequency" in line or "max_frequency" in line
    or "window_function" in line or "mel_scale" in line
]


def rows(n: int) -> int:
    try:
        return int(ex._extract_fbank_features(np.zeros(n, dtype=np.float32)).shape[0])
    except Exception:
        return -1


def first_n(predicate, low, high):
    while low < high:
        mid = (low + high) // 2
        if predicate(mid):
            high = mid
        else:
            low = mid + 1
    return low


frame_length = first_n(lambda n: rows(n) >= 1, 1, 4000)
hop_length = first_n(lambda n: rows(n) >= 2, frame_length, frame_length + 4000) - frame_length
out["measured_frame_length"] = frame_length
out["measured_hop"] = hop_length
out["rows_check"] = {str(n): rows(n) for n in (16000, 19200, 19280, 19440, 19600)}


def tone(n: int) -> np.ndarray:
    """Non-silent probe: a flat all-zero clip normalises to all-zero, which
    would hide a padding row (padding_value=1) from us."""
    return (0.4 * np.sin(2 * np.pi * 300 * np.arange(n) / SR)).astype(np.float32)


def call(n: int):
    encoded = ex(
        tone(n),
        sampling_rate=SR,
        return_attention_mask=True,
        padding=False,
        return_tensors="np",
    )
    feats = np.asarray(encoded["input_features"])
    mask = np.asarray(encoded["attention_mask"])
    return {
        "mel_rows": rows(n),
        "feat_shape": list(feats.shape),
        "mask_shape": list(mask.shape),
        "mask_head": [int(v) for v in mask.ravel()][:4],
        "mask_sum": int(mask.sum()),
        "dtype": str(feats.dtype),
        "last_frame": [round(float(v), 4) for v in feats[0][-1][:4]] if feats[0].size else None,
        "last_is_pad": bool(np.all(feats[0][-1] == 1.0)) if feats[0].size else None,
    }


for name, n in (
    ("even_19200", 19200),
    ("odd_19280", 19280),
    ("odd_19440", 19440),
    ("tiny_400", 400),
    ("short_500", 500),
):
    out[name] = call(n)

Path("tool/asr_export/_probe.json").write_text(
    json.dumps(out, indent=1), encoding="utf8"
)
print("done")
