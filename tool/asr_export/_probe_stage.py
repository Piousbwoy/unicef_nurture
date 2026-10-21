"""Scratch: which stage of the recipe disagrees with the live extractor?

Compares the numpy re-implementation against the real extractor's own
intermediate (pre-normalisation log-mel) and final features, stage by stage.
"""
import json

import numpy as np
from transformers import SeamlessM4TFeatureExtractor

cache = "tool/asr_eval/data/hf"
ex = SeamlessM4TFeatureExtractor.from_pretrained(
    "KhayaAI/w2v-bert-dga", cache_dir=cache, local_files_only=True
)
fx = json.load(open("test/fixtures/asr/frontend_fixtures.json", encoding="utf8"))
clip = next(c for c in fx if c["name"] == "synthetic")
x = np.asarray(clip["samples"], dtype=np.float32)
bank = json.load(open("test/fixtures/asr/pack/mel_filters.json", encoding="utf8"))
window = np.asarray(
    json.load(open("test/fixtures/asr/pack/window.json", encoding="utf8"))["values"],
    dtype=np.float64,
)
filters = np.asarray(bank["values"], dtype=np.float64)  # (bin, band)
FL, HOP, FFT, P = 400, 160, 512, 0.97
MEL_FLOOR = 1.192092955078125e-07

reference = ex._extract_fbank_features(x)  # (118, 80) float32, pre-normalisation
print("reference", reference.shape, reference.dtype)

scaled = (x * 32768.0).astype(np.float32).astype(np.float64)
n = 1 + (len(scaled) - FL) // HOP
spec = np.empty((n, FFT // 2 + 1), dtype=np.complex128)
for t in range(n):
    b = np.zeros(FFT, dtype=np.float64)
    b[:FL] = scaled[t * HOP : t * HOP + FL]
    b[:FL] -= b[:FL].mean()
    previous = b[0].copy()
    b[0] *= 1 - P
    for i in range(1, FL):
        cur = b[i]
        b[i] = cur - P * previous
        previous = cur
    b[:FL] *= window
    spec[t] = np.fft.rfft(b)

for name, power in (
    ("float64 spectrum", spec.real**2 + spec.imag**2),
    ("complex64 magnitude", np.abs(spec.astype(np.complex64), dtype=np.float64) ** 2),
    ("float32 accumulate", np.abs(spec.astype(np.complex64)).astype(np.float32) ** 2),
):
    lm = np.log(np.maximum(MEL_FLOOR, power @ filters))
    for kind, value in (
        ("float64 lm", lm),
        ("float32 lm", lm.astype(np.float32)),
    ):
        d = np.abs(value - reference)
        print(f"{name:22s} {kind:11s} max {d.max():.3e} at {np.unravel_index(d.argmax(), d.shape)}")

# Post-normalisation, both ddof choices, against the stored fixture.
expected = np.asarray(clip["input_features"], dtype=np.float64)
for ddof in (1, 0):
    for lm in (reference, reference.astype(np.float64)):
        norm = (lm - lm.mean(0)) / np.sqrt(lm.var(0, ddof=ddof) + 1e-7)
        got = norm[: len(norm) // 2 * 2].reshape(-1, 160)
        d = np.abs(got - expected)
        print(
            f"fixture vs HF-intermediate ddof={ddof}: max {d.max():.3e} "
            f"at {np.unravel_index(d.argmax(), d.shape)}"
        )
