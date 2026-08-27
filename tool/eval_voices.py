"""Objective voice-quality battery for the Hausa/Twi speech banks.

The Dagbani bank sounds native to the user; the Hausa/Twi banks were reported
as "an English man talking, boring and annoying". Nobody here can listen, so
this script gathers machine evidence instead:

  0. Weight hashes — is laztopaz/mms-tts-hau-custom byte-identical to the
     official (and now public) facebook/mms-tts-hau, i.e. a faithful copy or
     a degraded fine-tune? Same for two independent Twi uploads.
  1. Fresh synthesis — official Hausa weights + every viable Twi candidate
     render the exact bank phrases.
  2. Language ID (facebook/mms-lid-2048) — what language does each clip
     actually sound like? If a "Hausa" bank clip classifies as English, the
     user's complaint is confirmed mechanically.
  3. ASR round-trip (facebook/mms-1b-all, hau adapter) — how much of the
     script survives speaking→listening, laztopaz vs official.

Run:  python tool/eval_voices.py          (several minutes; background it)
"""

import difflib
import gc
import hashlib
import os
import re
import sys
import unicodedata
from pathlib import Path

os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

import soundfile as sf
import torch

ROOT = Path(__file__).resolve().parent.parent
AUDIO = ROOT / "assets" / "audio"
TMP = ROOT / "build" / "voice_eval"
TMP.mkdir(parents=True, exist_ok=True)

sys.path.insert(0, str(ROOT / "tool"))
from generate_dagbani_speech import BANKS  # exact bank texts

ASR_IDS = ["q_child.fits", "q_newborn.feed", "q_mother.bleed", "level_urgent"]


def sha256_file(p):
    h = hashlib.sha256()
    with open(p, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def cached_safetensors(repo):
    from huggingface_hub import hf_hub_download

    try:
        return hf_hub_download(repo, "model.safetensors")
    except Exception as e:  # noqa: BLE001
        print(f"    ({repo}: no weights — {type(e).__name__})", flush=True)
        return None


def hash_pair(label, pa, pb):
    if not (pa and pb):
        print(f"  {label}: comparison unavailable", flush=True)
        return None
    ha, hb = sha256_file(pa), sha256_file(pb)
    same = ha == hb
    print(
        f"  {label}: {'IDENTICAL' if same else 'DIFFERENT'}\n"
        f"    a: {ha[:20]}…\n    b: {hb[:20]}…",
        flush=True,
    )
    return same


def synth(repo, text, out_path):
    from transformers import AutoTokenizer, VitsModel

    model = VitsModel.from_pretrained(repo)
    tok = AutoTokenizer.from_pretrained(repo)
    torch.manual_seed(0)
    inputs = tok(text, return_tensors="pt")
    with torch.inference_mode():
        out = model(**inputs)
    wav = out.waveform.squeeze().numpy()
    sf.write(out_path, wav, 16000)
    del model, tok, out, inputs
    gc.collect()
    return out_path


def load_lid():
    from transformers import AutoFeatureExtractor, AutoModelForAudioClassification

    name = "facebook/mms-lid-2048"
    # LID inference needs only the feature extractor; the repo's tokenizer
    # stanza is malformed for AutoProcessor on current transformers.
    proc = AutoFeatureExtractor.from_pretrained(name)
    model = AutoModelForAudioClassification.from_pretrained(name)
    labels = set(model.config.id2label.values())
    print(f"  {name}: {len(labels)} labels", flush=True)
    for want in ("eng", "hau", "twi", "dag"):
        print(f"    supports '{want}': {want in labels}", flush=True)
    return proc, model


def lid_top(proc, model, wav_path, k=3):
    audio, sr = sf.read(wav_path)
    if audio.ndim > 1:
        audio = audio[:, 0]
    inputs = proc(audio, sampling_rate=sr, return_tensors="pt")
    with torch.inference_mode():
        logits = model(**inputs).logits
    top = logits.softmax(-1)[0].topk(k)
    return [
        (model.config.id2label[i.item()], round(p.item(), 3))
        for i, p in zip(top.indices, top.values)
    ]


def norm_text(s):
    s = unicodedata.normalize("NFC", s).lower().replace(" ", "")
    return re.sub(r"[^a-zɓɗƙɛɔãõĩŋũāăūáʼ']", "", s)


def ratio(ref, hyp):
    return round(
        difflib.SequenceMatcher(None, norm_text(ref), norm_text(hyp)).ratio(), 3
    )


print("=== 0. Weight hashes ===", flush=True)
hausa_same = hash_pair(
    "Hausa laztopaz vs OFFICIAL facebook/mms-tts-hau",
    cached_safetensors("laztopaz/mms-tts-hau-custom"),
    cached_safetensors("facebook/mms-tts-hau"),
)
twi_same = hash_pair(
    "Twi IanKobby vs rnjema-unima baseline (independent upload)",
    cached_safetensors("IanKobby/mms-tts-twi-ghana"),
    cached_safetensors("rnjema-unima/mms-tts-twi-baseline"),
)

print("\n=== 1. Fresh synthesis from candidates ===", flush=True)
hau_phrases = BANKS["hausa_mms"]["phrases"]
twi_phrases = BANKS["twi_mms"]["phrases"]
official_dir = TMP / "official_hau"
official_dir.mkdir(parents=True, exist_ok=True)
for clip_id in ASR_IDS:
    out = official_dir / f"{clip_id}.wav"
    synth("facebook/mms-tts-hau", hau_phrases[clip_id], str(out))
    print(f"  official hau: {clip_id}.wav", flush=True)

TWI_CANDIDATES = [
    "IanKobby/mms-tts-twi-ghana",
    "rnjema-unima/mms-tts-twi-baseline",
    "herwoww/mms-tts-twi",
]
twi_samples = {}
for repo in TWI_CANDIDATES:
    tag = repo.split("/")[0]
    cdir = TMP / f"twi_{tag}"
    cdir.mkdir(parents=True, exist_ok=True)
    try:
        for clip_id in ("q_child.fits", "level_urgent"):
            out = cdir / f"{clip_id}.wav"
            synth(repo, twi_phrases[clip_id], str(out))
            twi_samples.setdefault(repo, []).append(out)
        print(f"  twi {tag}: synthesized", flush=True)
    except Exception as e:  # noqa: BLE001
        print(f"  twi {tag}: FAILED — {e}", flush=True)

# Canonical Hausa is already in the bank (hashes matched), so audition
# community fine-tunes — Bible-audio fine-tunes usually speak with far
# more expressive prosody than the flat VOA-news speaker.
HAUSA_CANDIDATES = [
    "facebook/mms-tts-hau",
    "PlotweaverAI/hausa-mms-tts-bible",
    "suleiman2003/mms-tts-hau-2speaker",
    "Shinzmann/mms-tts-hau-train",
    "rnjema-unima/mms-tts-hau-baseline",
]
hau_samples = {}
for repo in HAUSA_CANDIDATES:
    tag = repo.split("/")[0] if "/" in repo else repo
    cdir = TMP / f"hau_{tag}"
    cdir.mkdir(parents=True, exist_ok=True)
    try:
        for clip_id in ("q_child.fits", "level_urgent"):
            out = cdir / f"{clip_id}.wav"
            synth(repo, hau_phrases[clip_id], str(out))
            hau_samples.setdefault(repo, []).append(out)
        print(f"  hau {tag}: synthesized", flush=True)
    except Exception as e:  # noqa: BLE001
        print(f"  hau {tag}: FAILED — {e}", flush=True)

print("\n=== 2. Language ID on real bank clips + fresh samples ===", flush=True)
lid_proc, lid_model = load_lid()
LID_CLIPS = [
    ("dagbani_mms", "child_danger_signs"),
    ("dagbani_mms", "q_child.fits"),
    ("hausa_mms", "child_danger_signs"),
    ("hausa_mms", "q_child.fits"),
    ("twi_mms", "child_danger_signs"),
    ("twi_mms", "q_child.fits"),
    ("OFFICIAL-hau", str(official_dir / "q_child.fits.wav")),
    ("OFFICIAL-hau", str(official_dir / "level_urgent.wav")),
]
for tag, clip in LID_CLIPS:
    path = clip if str(clip).endswith(".wav") else AUDIO / tag / f"{clip}.wav"
    try:
        top = lid_top(lid_proc, lid_model, str(path))
        pretty = ", ".join(f"{lang}:{p}" for lang, p in top)
        print(f"  {tag:<12} {Path(path).name:<26} → {pretty}", flush=True)
    except Exception as e:  # noqa: BLE001
        print(f"  {tag:<12} {Path(path).name:<26} → LID failed: {e}", flush=True)
for repo, paths in twi_samples.items():
    for p in paths:
        try:
            top = lid_top(lid_proc, lid_model, str(p))
            pretty = ", ".join(f"{lang}:{pr}" for lang, pr in top)
            print(f"  twi/{repo.split('/')[0]:<10} {p.name:<26} → {pretty}", flush=True)
        except Exception as e:  # noqa: BLE001
            print(f"  twi/{repo.split('/')[0]:<10} {p.name} → LID failed: {e}", flush=True)
for repo, paths in hau_samples.items():
    for p in paths:
        try:
            top = lid_top(lid_proc, lid_model, str(p))
            pretty = ", ".join(f"{lang}:{pr}" for lang, pr in top)
            print(f"  hau/{repo.split('/')[0]:<10} {p.name:<26} → {pretty}", flush=True)
        except Exception as e:  # noqa: BLE001
            print(f"  hau/{repo.split('/')[0]:<10} {p.name} → LID failed: {e}", flush=True)
del lid_model, lid_proc
gc.collect()

print("\n=== 3. ASR round-trip — Hausa (mms-1b-all, hau adapter) ===", flush=True)
from transformers import AutoProcessor, Wav2Vec2ForCTC

asr_proc = AutoProcessor.from_pretrained("facebook/mms-1b-all")
asr = Wav2Vec2ForCTC.from_pretrained("facebook/mms-1b-all")
asr_proc.tokenizer.set_target_lang("hau")
asr.load_adapter("hau")


def transcribe(path):
    audio, sr = sf.read(path)
    if audio.ndim > 1:
        audio = audio[:, 0]
    inputs = asr_proc(audio, sampling_rate=sr, return_tensors="pt")
    with torch.inference_mode():
        logits = asr(**inputs).logits
    ids = torch.argmax(logits, dim=-1)[0]
    return asr_proc.decode(ids).strip()


print(
    f"  {'clip':<18} {'laztopaz bank':<22} {'official fresh':<22}",
    flush=True,
)
scores = []
for clip_id in ASR_IDS:
    ref = hau_phrases[clip_id]
    heard_bank = transcribe(AUDIO / "hausa_mms" / f"{clip_id}.wav")
    heard_off = transcribe(official_dir / f"{clip_id}.wav")
    r_bank = ratio(ref, heard_bank)
    r_off = ratio(ref, heard_off)
    scores.append((clip_id, r_bank, r_off))
    print(
        f"  {clip_id:<18} match={r_bank:<10} match={r_off:<10}",
        flush=True,
    )
    print(f"    bank heard:     {heard_bank}", flush=True)
    print(f"    official heard: {heard_off}", flush=True)
avg_bank = round(sum(s[1] for s in scores) / len(scores), 3)
avg_off = round(sum(s[2] for s in scores) / len(scores), 3)
print(f"\n  AVERAGE script survival — laztopaz bank: {avg_bank}  official: {avg_off}", flush=True)

print("\n=== VERDICT SUMMARY ===", flush=True)
print(f"  Hausa weights identical to official: {hausa_same}", flush=True)
print(f"  Twi weights identical to independent upload: {twi_same}", flush=True)
print("  See LID + ASR tables above.", flush=True)
print("EVAL DONE", flush=True)
