"""Throwaway - measurement only, not shippable code.

Clean CPU cost probe: one 10.0 s clip, torch pinned to 2 intra-op threads,
no other job running. Also checks the whisper language token table.
"""
import json
import sys
import time
from pathlib import Path

import soundfile as sf

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "out"

import torch  # noqa: E402
torch.set_num_threads(2)
torch.set_grad_enabled(False)
import numpy as np  # noqa: E402
from transformers import AutoModelForSpeechSeq2Seq, AutoProcessor, WhisperTokenizer  # noqa: E402

model_id = "openai/whisper-tiny"
proc = AutoProcessor.from_pretrained(model_id)
model = AutoModelForSpeechSeq2Seq.from_pretrained(model_id).eval()
sr = proc.feature_extractor.sampling_rate

row = json.loads((ROOT / "data" / "dag" / "manifest.jsonl").open(encoding="utf8").readline())
wav, wrate = sf.read(ROOT / row["audio"])
if wav.ndim > 1:
    wav = wav.mean(axis=1)
ten = wav[: int(10.0 * wrate)]
from math import gcd  # noqa: E402
from scipy.signal import resample_poly  # noqa: E402
if int(wrate) != int(sr):
    g = gcd(int(sr), int(wrate))
    ten16 = resample_poly(ten, int(sr) // g, int(wrate) // g).astype("float32")
else:
    ten16 = ten.astype("float32")
audio_seconds = len(ten16) / sr
assert 9.5 < audio_seconds < 10.5, f"clip is {audio_seconds}s, probe would lie"

feats = proc.feature_extractor(ten16, sampling_rate=sr, return_tensors="pt").input_features
timings = []
for rep in range(3):
    t0 = time.perf_counter()
    ids = model.generate(feats, max_new_tokens=64, task="transcribe")
    timings.append(time.perf_counter() - t0)
heard = proc.batch_decode(ids, skip_special_tokens=True)[0]

warm = time.perf_counter()
for rep in range(2):
    t0 = time.perf_counter()
    model.generate(feats, max_new_tokens=64, task="transcribe")
    timings.append(time.perf_counter() - t0)

tok = WhisperTokenizer.from_pretrained(model_id)
lang_map = {}
try:
    gc = proc.tokenizer  # whisper tokenizer carries lang_code_to_language
    lang_map = {
        "n_langs": len(getattr(tok, "lang_code_to_language", {}) or {}),
        "keys_dag_aka_twi": {c: (getattr(tok, "lang_code_to_language", {}) or {}).get(c)
                             for c in ("dag", "aka", "twi")},
    }
except Exception as exc:  # noqa: BLE001
    lang_map = {"error": f"{type(exc).__name__}: {exc}"[:200]}

fp32 = sum(f.stat().st_size for f in
           Path(sys.argv[1] if len(sys.argv) > 1 else "").glob("**/model.safetensors")) \
    if len(sys.argv) > 1 else 0

res = {
    "model": model_id, "threads": 2, "torch_version": torch.__version__,
    "clip_seconds": round(audio_seconds, 3),
    "wall_seconds_per_run": [round(t, 3) for t in timings],
    "rtf_first": round(timings[0] / audio_seconds, 3),
    "rtf_median": round(sorted(timings)[len(timings) // 2] / audio_seconds, 3),
    "rtf_best": round(min(timings) / audio_seconds, 3),
    "hyp_on_10s_dag_clip": heard,
    "whisper_language_table": lang_map,
    "device_threads_reported": torch.get_num_threads(),
}
(OUT / "rtf_probe.json").write_text(json.dumps(res, indent=2, ensure_ascii=False) + "\n",
                                    encoding="utf8")
print("wrote rtf_probe.json", {k: res[k] for k in ('rtf_first', 'rtf_median', 'rtf_best')})
sys.exit(0)
