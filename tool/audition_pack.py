"""Rebuild the voice audition pack under build/voice_eval/.

`flutter clean` wipes build/, so this re-renders the candidate samples that
tool/eval_voices.py produced and scored (weight hashes, language ID, ASR
round-trip). Two clips per candidate — a triage question and an urgent
referral message — plus the current bank clips copied in for direct A/B.

The machine verdict: the current banks are already canonical Meta weights
and every community fine-tune either failed the language check or was
LID-identical to official. This pack exists so a human ear can make the
final call; if one wins, swap the "model" line for that bank in
tool/generate_dagbani_speech.py and regenerate.

Run:  python tool/audition_pack.py
"""

import gc
import os
import shutil
import sys
from pathlib import Path

os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

import soundfile as sf
import torch

ROOT = Path(__file__).resolve().parent.parent
AUDIO = ROOT / "assets" / "audio"
TMP = ROOT / "build" / "voice_eval"

sys.path.insert(0, str(ROOT / "tool"))
from generate_dagbani_speech import BANKS  # exact bank texts

HAUSA = [
    "facebook/mms-tts-hau",
    "PlotweaverAI/hausa-mms-tts-bible",
    "suleiman2003/mms-tts-hau-2speaker",
    "Shinzmann/mms-tts-hau-train",
    "rnjema-unima/mms-tts-hau-baseline",
]
TWI = [
    "IanKobby/mms-tts-twi-ghana",
    "rnjema-unima/mms-tts-twi-baseline",
    "herwoww/mms-tts-twi",
]
CLIPS = ["q_child.fits", "level_urgent"]


def synth(repo, text, out_path):
    from transformers import AutoTokenizer, VitsModel

    model = VitsModel.from_pretrained(repo)
    tok = AutoTokenizer.from_pretrained(repo)
    torch.manual_seed(0)
    inputs = tok(text, return_tensors="pt")
    with torch.inference_mode():
        out = model(**inputs)
    sf.write(out_path, out.waveform.squeeze().numpy(), 16000)
    del model, tok, out, inputs
    gc.collect()


def main():
    for bank, prefix, candidates in (
        ("hausa_mms", "hau", HAUSA),
        ("twi_mms", "twi", TWI),
    ):
        phrases = BANKS[bank]["phrases"]
        # The voice in the app today, copied in for direct A/B.
        current = TMP / f"{bank}_current"
        current.mkdir(parents=True, exist_ok=True)
        for clip in CLIPS:
            shutil.copy2(AUDIO / bank / f"{clip}.wav", current / f"{clip}.wav")
        print(f"  {bank}_current: copied", flush=True)
        for repo in candidates:
            tag = repo.split("/")[0]
            cdir = TMP / f"{prefix}_{tag}"
            cdir.mkdir(parents=True, exist_ok=True)
            try:
                for clip in CLIPS:
                    synth(repo, phrases[clip], str(cdir / f"{clip}.wav"))
                print(f"  {repo}: synthesized", flush=True)
            except Exception as e:  # noqa: BLE001
                print(f"  {repo}: FAILED — {type(e).__name__}: {e}", flush=True)
    print("AUDITION PACK DONE — listen in build/voice_eval/", flush=True)


if __name__ == "__main__":
    main()
