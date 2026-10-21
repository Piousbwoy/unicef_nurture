"""Scratch: how lossy is the fixture itself?

Re-feeds the stored (7-decimal) samples to the real extractor and compares the
result to the stored features. Whatever difference shows up here is the
fixture's own quantisation, not the Dart port's, and it bounds the tolerance.
"""
import json

import numpy as np
from transformers import SeamlessM4TFeatureExtractor

ex = SeamlessM4TFeatureExtractor.from_pretrained(
    "KhayaAI/w2v-bert-dga", cache_dir="tool/asr_eval/data/hf", local_files_only=True
)
fx = json.load(open("test/fixtures/asr/frontend_fixtures.json", encoding="utf8"))
for clip in fx:
    stored = np.asarray(clip["input_features"], dtype=np.float64)
    again = ex(
        np.asarray(clip["samples"], dtype=np.float32),
        sampling_rate=16000,
        return_attention_mask=True,
        padding=False,
        return_tensors="np",
    )
    fresh = np.asarray(again["input_features"], dtype=np.float64)[0]
    diff = np.abs(fresh - stored)
    lm = ex._extract_fbank_features(np.asarray(clip["samples"], dtype=np.float32))
    stds = lm.std(0, ddof=1)
    print(
        f"{clip['name']}: refed-vs-stored max {diff.max():.4g} at "
        f"{np.unravel_index(diff.argmax(), diff.shape)} | lm range "
        f"[{lm.min():.3f}, {lm.max():.3f}] | smallest band std "
        f"{stds.min():.3e} (band {stds.argmin()}), largest {stds.max():.3f}"
    )
    worst = diff.argmax()
    band = worst % 160
    print(
        f"   band {band} (analysis band {band % 80}, std {stds[band % 80]:.3e}): "
        f"stored {stored.ravel()[worst]:.6f} fresh {fresh.ravel()[worst]:.6f}"
    )
