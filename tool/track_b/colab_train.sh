#!/usr/bin/env bash
# Train a Dagbani voice with the maintained Piper trainer, then export the pack
# the CareBridge app loads. Run this on a GPU box or a Colab L4/L200 notebook;
# the data stage (tool/track_b/fetch_dagbani.py + prepare_symbols.py) already
# ran locally and produced metadata.csv, phonemes.json and audio/.
#
# Usage:  CORPUS=/content/dagbani bash colab_train.sh
#
# Verified against OHF-Voice/piper1-gpl docs/TRAINING.md on 2026-10-18:
#   - text phoneme type:  --data.phoneme_type text, CSV "file.wav|symbols"
#   - pinned inventory:   --data.phonemes_path
#   - warmstart:          --model.vocoder_warmstart_ckpt (allows a new inventory)
#   - export:             python3 -m piper.train.export_onnx
set -euo pipefail

CORPUS="${CORPUS:-/content/dagbani}"
EPOCHS="${EPOCHS:-60}"
BATCH="${BATCH:-32}"
EARS="${EARS:-50}"          # utterances held out for the listening sample
WORK="${WORK:-/content/piper-work}"

apt-get update -qq && apt-get install -y -qq build-essential cmake ninja-build python3-venv >/dev/null

# Data stage, when the corpus was not prepared beforehand. Upload
# fetch_dagbani.py, prepare_symbols.py and app_lines.txt (from
# `prepare_symbols.py --app-lines-out`) alongside this run.
if [[ ! -s "$CORPUS/metadata.csv" ]]; then
  python3 -m pip install -q pyarrow fsspec soundfile requests
  TOOL="${TOOL_DIR:-/content/track_b}"
  python3 "$TOOL/fetch_dagbani.py" --out "$CORPUS" --shards "${SHARDS:-37}"
  python3 "$TOOL/prepare_symbols.py" --corpus "$CORPUS" --app-lines "$TOOL/app_lines.txt"
fi

mkdir -p "$WORK"
cd "$WORK"
if [[ ! -d piper1-gpl ]]; then
  git clone --depth 1 https://github.com/OHF-Voice/piper1-gpl.git
fi
cd piper1-gpl
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -q -U pip
python3 -m pip install -q -e '.[train]'
./build_monotonic_align.sh

# 933 MB; holds the vocoder weights, so only the text side learns from scratch.
if [[ ! -f base_model.ckpt ]]; then
  wget -q -O base_model.ckpt \
    "https://huggingface.co/datasets/rhasspy/piper-checkpoints/resolve/main/_base_model/base_model.ckpt"
fi

SYMBOLS="$(python3 -c "import json;print(len(json.load(open('$CORPUS/phonemes.json'))))")"

# Upstream also keeps a second ModelCheckpoint monitoring "val_mos". If the
# UTMOS predictor cannot be downloaded (no egress), val_mos is never logged and
# current Lightning aborts at the END OF THE FIRST EPOCH rather than warning and
# skipping -- after hours of training. MOS=off drops the predictor and that
# callback. Same reasoning for TORCH_EXPORT_LEGACY: torch>=2.13 defaults
# torch.onnx.export to the dynamo front end, which fails on the flow modules.
MOS_ARGS=""
if [[ "${MOS:-on}" == "off" ]]; then
  python3 - <<'PY'
import pathlib, re
path = pathlib.Path("src/piper/train/__main__.py")
source = path.read_text()
trimmed, count = re.subn(
    r"\n *ModelCheckpoint\(\s*monitor=\"val_mos\",.*?\),\n", "\n", source, flags=re.S)
if count != 1:
    raise SystemExit(f"expected to remove one val_mos checkpoint, removed {count}")
path.write_text(trimmed)
print("disabled UTMOS checkpoint monitoring for this run")
PY
  MOS_ARGS="--model.mos_metric none"
fi
if [[ "${TORCH_EXPORT_LEGACY:-0}" == "1" ]]; then
  python3 - <<'PY'
import pathlib
path = pathlib.Path("src/piper/train/export_onnx.py")
source = path.read_text()
if "dynamo=False" not in source:
    path.write_text(source.replace("opset_version=OPSET_VERSION,",
                                   "opset_version=OPSET_VERSION,\n        dynamo=False,", 1))
print("export will use the legacy ONNX front end")
PY
fi

echo "inventory: $SYMBOLS symbols, epochs $EPOCHS, batch $BATCH"

# --data.espeak_voice is a required CLI argument but is not consulted when
# phoneme_type is text; the Dagbani alphabet is pinned by phonemes.json instead.
python3 -m piper.train fit \
  $MOS_ARGS \
  --data.voice_name dagbani \
  --data.csv_path "$CORPUS/metadata.csv" \
  --data.audio_dir "$CORPUS/audio" \
  --data.phoneme_type text \
  --data.espeak_voice en-us \
  --data.phonemes_path "$CORPUS/phonemes.json" \
  --data.num_symbols "$SYMBOLS" \
  --data.cache_dir "$CORPUS/cache" \
  --data.config_path "$CORPUS/model.onnx.json" \
  --data.batch_size "$BATCH" \
  --model.sample_rate 22050 \
  --model.vocoder_warmstart_ckpt base_model.ckpt \
  --trainer.max_epochs "$EPOCHS" \
  --trainer.devices 1 \
  --trainer.default_root_dir "$WORK/run"

CKPT="$(find "$WORK/run" -name '*.ckpt' -not -name 'base_model.ckpt' | sort | tail -1)"
echo "checkpoint: $CKPT"

python3 -m piper.train.export_onnx \
  --checkpoint "$CKPT" \
  --output-file "$CORPUS/model.onnx"

# Sample what the app must be able to say, straight from the trained model.
python3 -m piper.infer \
  --config "$CORPUS/model.onnx.json" \
  --speech-text "Ti bɔri nyɛ o tɛn'shɛga." \
  --output "$CORPUS/earcheck_1.wav" || \
  echo "piper.infer CLI differs; run eval_voice.py with the exported pack instead"

echo
echo "Done. Copy back: $CORPUS/model.onnx $CORPUS/model.onnx.json"
echo "Then locally:  python tool/track_b/eval_voice.py --pack <dir>"
echo "and:           python tool/build_voice_manifests.py"
