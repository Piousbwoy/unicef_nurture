# %% [markdown]
# # CareBridge — Twi voice (Piper/VITS) from WaxalNLP TTS audio
#
# Trains a Twi voice on `google/WaxalNLP` `data/TTS/twi` (University of Ghana,
# CC-BY-4.0 — clean for a shipped model) and exports the ONNX pack the app loads.
#
# Mirrors `tool/track_b/colab_train.sh` flag-for-flag so both languages produce
# comparable packs. Two known upstream traps are handled the same way: the UTMOS
# checkpoint is dropped (Lightning aborts at the end of epoch 1 without it), and
# ONNX export uses the legacy front end (torch 2.13's dynamo path asserts on the
# flow modules).
#
# **The honest expectation:** this corpus is ~1.6 hours. Dagbani has 137. A voice
# this small will be intelligible, not rich. `coverage.json` and an ear check
# decide whether it beats the Farmerline voice already installed — if it does
# not, we keep Farmerline and spend Twi compute on the listener instead.

# %%
import io
import json
import os
import re
import subprocess
import sys
import unicodedata
from pathlib import Path

AUDIO_SR = 22050
CORPUS = Path("/tmp/twi")
WORK = Path("/kaggle/working/twi-work")
SHARDS = [
    "data/TTS/twi/twi-train-00000.parquet",
    "data/TTS/twi/twi-validation-00000.parquet",
]
BASE_CKPT = "https://huggingface.co/datasets/rhasspy/piper-checkpoints/resolve/main/_base_model/base_model.ckpt"
EPOCHS = int(os.environ.get("EPOCHS", "60"))
BATCH = int(os.environ.get("BATCH", "32"))


def run(*cmd, cwd=None, shell=False):
    print("+", " ".join(cmd) if isinstance(cmd[0], str) else cmd, flush=True)
    subprocess.run(cmd, cwd=cwd, check=True, shell=shell)


# %% [markdown]
# ## 1. Corpus: embedded parquet audio -> 22.05 kHz wav + pinned alphabet
# The transcript inventory, not a guess, is what the model is allowed to say.

# %%
import numpy as np
import pyarrow.parquet as pq
import soundfile as sf


def to_rate(samples, source_sr, target=AUDIO_SR):
    """Linear interpolation. Deliberately the same rule the app's Dart frontend
    uses, so a pack trained here is not calibrated to a different resampler."""
    if source_sr == target:
        return samples
    count = int(round(len(samples) * target / source_sr))
    position = np.linspace(0, len(samples) - 1, count)
    return np.interp(position, np.arange(len(samples)), samples).astype(np.float32)


def letters(text):
    """NFD, lowercase, keep only letters — the alphabet the trainer pins."""
    decomposed = unicodedata.normalize("NFD", text.lower())
    return [c for c in decomposed if unicodedata.category(c).startswith("L")]


CORPUS.mkdir(parents=True, exist_ok=True)
(CORPUS / "audio").mkdir(parents=True, exist_ok=True)

rows = []
for shard in SHARDS:
    url = f"https://huggingface.co/datasets/google/WaxalNLP/resolve/main/{shard}"
    local = Path("/tmp") / Path(shard).name
    if not local.exists():
        run("wget", "-q", "-O", str(local), url)
    table = pq.read_table(local, columns=["id", "speaker_id", "text", "audio"])
    for row in table.to_pylist():
        samples, source_sr = sf.read(io.BytesIO(row["audio"]["bytes"]))
        samples = np.asarray(samples, dtype=np.float32)
        if samples.ndim > 1:
            samples = samples.mean(axis=1)
        samples = to_rate(samples, source_sr)
        name = f"{row['id']}.wav"
        sf.write(CORPUS / "audio" / name, samples, AUDIO_SR)
        rows.append({"audio": f"audio/{name}", "text": row["text"],
                     "speaker": row["speaker_id"],
                     "seconds": round(len(samples) / AUDIO_SR, 2)})

(CORPUS / "metadata.jsonl").write_text(
    "\n".join(json.dumps(r, ensure_ascii=False) for r in rows) + "\n", encoding="utf8")
hours = sum(r["seconds"] for r in rows) / 3600
print(f"{len(rows)} utterances, {hours:.2f} hours at {AUDIO_SR} Hz")

inventory = sorted({c for r in rows for c in letters(r["text"])})
# Piper's text mode wants a word separator; without it, multi-word answers run
# together and the duration model has nothing to breathe on.
symbols = ["_"] + inventory
(CORPUS / "phonemes.json").write_text(
    json.dumps({c: i for i, c in enumerate(symbols)}, ensure_ascii=False), encoding="utf8")

with (CORPUS / "metadata.csv").open("w", encoding="utf8") as handle:
    for row in rows:
        text = unicodedata.normalize("NFD", row["text"].lower())
        text = "".join(c if unicodedata.category(c).startswith("L") else " " for c in text)
        text = " ".join(text.split()).replace(" ", "_")
        handle.write(f"{row['audio']}|{text}\n")
(CORPUS / "corpus_stats.json").write_text(json.dumps(
    {"hours": round(hours, 2), "utterances": len(rows), "letters": len(inventory),
     "license": "CC-BY-4.0 (University of Ghana, WaxalNLP)"}, indent=1), encoding="utf8")
print("alphabet:", "".join(inventory))

# %% [markdown]
# ## 2. Trainer

# %%
WORK.mkdir(parents=True, exist_ok=True)
repo = WORK / "piper1-gpl"
if not repo.exists():
    run("git", "clone", "--depth", "1", "https://github.com/OHF-Voice/piper1-gpl.git", cwd=WORK)
run(sys.executable, "-m", "pip", "install", "-q", "-e", ".[train]", cwd=repo)
run("./build_monotonic_align.sh", cwd=repo, shell=True)

base = repo / "base_model.ckpt"
if not base.exists():
    run("wget", "-q", "-O", str(base), BASE_CKPT)

# Without the UTMOS predictor, val_mos is never logged and Lightning aborts at
# the end of the first epoch rather than warning and skipping.
main_py = repo / "src/piper/train/__main__.py"
source = main_py.read_text()
trimmed = __import__("re").subn(
    r"\n *ModelCheckpoint\(\s*monitor=\"val_mos\",.*?\),\n", "\n", source, flags=__import__("re").S)
if trimmed[1] != 1:
    raise SystemExit(f"expected to remove one val_mos checkpoint, removed {trimmed[1]}")
main_py.write_text(trimmed[0])

export_py = repo / "src/piper/train/export_onnx.py"
text = export_py.read_text()
if "dynamo=False" not in text:
    export_py.write_text(
        text.replace("opset_version=OPSET_VERSION,",
                     "opset_version=OPSET_VERSION,\n        dynamo=False,", 1))

# %%
run(sys.executable, "-m", "piper.train", "fit",
    "--data.voice_name", "twi",
    "--data.csv_path", str(CORPUS / "metadata.csv"),
    "--data.audio_dir", str(CORPUS / "audio"),
    "--data.phoneme_type", "text",
    "--data.espeak_voice", "en-us",
    "--data.phonemes_path", str(CORPUS / "phonemes.json"),
    "--data.num_symbols", str(len(symbols)),
    "--data.cache_dir", str(CORPUS / "cache"),
    "--data.batch_size", str(BATCH),
    "--model.sample_rate", str(AUDIO_SR),
    "--model.vocoder_warmstart_ckpt", str(base),
    "--model.mos_metric", "none",
    "--trainer.max_epochs", str(EPOCHS),
    "--trainer.devices", "1",
    "--trainer.default_root_dir", str(WORK / "run"),
    cwd=repo)

# %% [markdown]
# ## 3. Export, audition clips, and a downloadable bundle

# %%
checkpoints = sorted(WORK.rglob("*.ckpt"), key=lambda p: p.stat().st_mtime)
checkpoints = [c for c in checkpoints if c.name != "base_model.ckpt"]
if not checkpoints:
    raise SystemExit("no checkpoint produced")
latest = checkpoints[-1]
print("checkpoint:", latest)

run(sys.executable, "-m", "piper.train.export_onnx",
    "--checkpoint", str(latest), "--output-file", str(CORPUS / "model.onnx"), cwd=repo)

# These are the sentences the app must be able to say. Coverage is measured here
# so a thin voice is visible in a number, not discovered in a demo.
APP_LINES = [
    "Wo ma kyerɛɛ wo sɛ wobɛhwehwɛ ɔba no yare.",
    "Ɔba no rensua nono yie.",
    "Kyerɛ sɛ ɔyare no dɛn kɛseyɛ.",
    "Fa ɔba no kɔ apɔmuden.",
    "Nnyire mu yɛ den.",
]
def letters_of(line):
    return {c for c in unicodedata.normalize("NFD", line.lower())
            if unicodedata.category(c).startswith("L")}


speakable = [line for line in APP_LINES if letters_of(line) <= set(inventory)]
(CORPUS / "coverage.json").write_text(json.dumps(
    {"app_lines": len(APP_LINES), "speakable": len(speakable),
     "alphabet": "".join(inventory), "hours": round(hours, 2)}, indent=1), encoding="utf8")

run("zip", "-qr", "twi-voice.zip", "model.onnx", "model.onnx.json", "coverage.json",
    "corpus_stats.json", "phonemes.json", cwd=CORPUS)
print("\nDownload twi-voice.zip from the Output panel, then locally:")
print("  python tool/track_b/eval_voice.py --pack <unzipped folder>")
print("  python tool/build_voice_manifests.py")
