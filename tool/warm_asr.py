"""Pre-download the MMS ASR model + language adapters used by asr_roundtrip.py.

facebook/mms-1b-all is ~4 GB; the language adapters (eng/hau/twi/dag) are
small but only fetched on first use, so warm them all here so the actual
round-trip run is fast and deterministic.

Run:  python tool/warm_asr.py
"""

import os

os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")

import torch
from transformers import AutoProcessor, Wav2Vec2ForCTC

NAME = "facebook/mms-1b-all"

print("downloading base model (this is the ~4 GB part)...", flush=True)
processor = AutoProcessor.from_pretrained(NAME)
model = Wav2Vec2ForCTC.from_pretrained(NAME)
print("base loaded.", flush=True)

for lang in ["eng", "hau", "twi", "dag"]:
    print(f"adapter {lang}: fetching...", flush=True)
    processor.tokenizer.set_target_lang(lang)
    model.load_adapter(lang)
    print(f"adapter {lang}: ok", flush=True)

print("WARM DONE", flush=True)
