"""Scratch: reproduce the fixture with numpy step by step, Dart's way.

Which step of the SeamlessM4T recipe disagrees? Tests the port's ordering
choices (DC before pre-emphasis, first-sample handling) against the stored
fixture before blaming the Dart code.
"""
import json

import numpy as np

fx = json.load(open("test/fixtures/asr/frontend_fixtures.json", encoding="utf8"))
clip = next(c for c in fx if c["name"] == "synthetic")
x = (np.asarray(clip["samples"], dtype=np.float32) * 32768.0).astype(np.float64)
expected = np.asarray(clip["input_features"], dtype=np.float64)
bank = json.load(open("test/fixtures/asr/pack/mel_filters.json", encoding="utf8"))
window = np.asarray(
    json.load(open("test/fixtures/asr/pack/window.json", encoding="utf8"))["values"],
    dtype=np.float64,
)
filters = np.asarray(bank["values"], dtype=np.float64)  # (bin, band)
FL, HOP, FFT, P = 400, 160, 512, 0.97
MEL_FLOOR = 1.192092955078125e-07


def spectra(wave, order="dc-then-pre", first="scale"):
    n = 1 + (len(wave) - FL) // HOP
    out = np.empty((n, FFT // 2 + 1), dtype=np.complex128)
    for t in range(n):
        b = np.zeros(FFT, dtype=np.float64)
        b[:FL] = wave[t * HOP : t * HOP + FL]

        def pre_emphasis(block):
            previous = block[0].copy()
            block[0] = (1 - P) * block[0] if first == "scale" else (1 - P) * block[0]
            for i in range(1, FL):
                cur = block[i]
                block[i] = cur - P * previous
                previous = cur

        def de_dc(block):
            block -= block.mean()

        steps = {"dc-then-pre": [de_dc, pre_emphasis], "pre-then-dc": [pre_emphasis, de_dc]}
        for step in steps[order]:
            step(b[:FL])
        b[:FL] *= window
        out[t] = np.fft.rfft(b)
    return out


def logmel(spec, truncate=True):
    power = np.abs(spec.astype(np.complex64).astype(np.float64)) ** 2 if truncate else (
        spec.real**2 + spec.imag**2
    )
    return np.log(np.maximum(MEL_FLOOR, power @ filters))


def finish(lm, ddof=1):
    norm = (lm - lm.mean(0)) / np.sqrt(lm.var(0, ddof=ddof) + 1e-7)
    return norm[: len(norm) // 2 * 2].reshape(-1, 160)


for order in ("dc-then-pre", "pre-then-dc"):
    for truncate in (True, False):
        for ddof in (1, 0):
            got = finish(logmel(spectra(x, order), truncate), ddof)
            print(
                f"{order} float32-spectrum={truncate} ddof={ddof}: "
                f"max abs {np.abs(got - expected).max():.6g}"
            )
