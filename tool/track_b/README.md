# Track B — train CareBridge's own Dagbani and Twi voices

Track A borrowed other people's voices. Track B makes them, from audio that is
allowed to be used and that covers the letters the borrowed models cannot say.

## Why this exists

| | shipped today | GhanaNLP Dagbani (Track A) | this pipeline |
| --- | --- | --- | --- |
| licence | CC-BY-NC | none declared | CC-BY-4.0 audio |
| letters the app needs | partial | 39 of 73 lines (no `ɣ`) | 73 of 73 |
| CPU real-time factor | ~0.3 | 5.4 when int8-quantised | piper `medium` ~0.3 |
| size | 77–80 MB | 38 MB int8 / 114 MB fp32 | 60–70 MB fp32 |

Measured on one machine, same Dart engine, idle CPU, 2 inference threads:

| pack | audio | synth time | RTF |
| --- | --- | --- | --- |
| Twi piper (shipped, fp32) | 1.46 s | 522 ms | 0.36 |
| Hausa piper (shipped, fp32) | 1.51 s | 435 ms | 0.29 |
| Twi Farmerline, linear-only int8 (112 MB) | 2.02 s | 2661 ms | 1.32 |
| Twi Farmerline, all-int8 (38 MB) | 1.94 s | 6883 ms | 3.55 |
| Dagbani GhanaNLP, all-int8 (38 MB) | 2.62 s | 14227 ms | 5.42 |

The MMS-architecture checkpoints Track A borrows are 3–5× slower than the piper
voices already shipped. That is the whole argument for Track B: train on the
licensed audio, keep piper's architecture, and get a voice that is both allowed
and fast enough for a low-cost phone in the rain.

## Data, with licences verified 2026-10-18

* `fiifinketia/dagbani-bible-audio-text-tts` — 53,410 utterances, about 137 h at
  24 kHz, **CC-BY-4.0**. Text carries `ɣ ʒ ŋ ɛ ɔ`, the letters the community
  checkpoint is missing.
* `google/WaxalNLP` — TTS splits for `twi` and `hau` (CC-BY-4.0/CC-BY-SA-4.0).
  No Dagbani TTS split; Dagbani appears there only as ASR.
* `FarmerlineML/akosua_jed_twi_dataset` — 1,526 Twi utterances, CC-BY-4.0.

## Stages

```sh
# 1. pull a slice and re-encode it (runs locally, no GPU)
python tool/track_b/fetch_dagbani.py --out data/dagbani --shards 1 --limit 400

# 2. pin the symbol inventory and prove coverage before any training
python tool/track_b/prepare_symbols.py --corpus data/dagbani
#    -> metadata.csv (piper text format), phonemes.json, coverage.json

# 3. train + export on a GPU box or Colab (L4 is enough; ~1 day for full data)
CORPUS=/content/dagbani bash tool/track_b/colab_train.sh

# 4. gate the result before it can reach the app
python tool/track_b/eval_voice.py --pack data/dagbani --repo .        # size, RTF, contract
python tool/track_b/eval_voice.py --pack data/dagbani --lid --asr     # language ID + word check

# 5. register the pack like any other voice
python tool/build_voice_manifests.py   # then add the dir to pubspec.yaml
```

`colab_train.sh` runs stages 1 and 2 itself when `metadata.csv` is missing, so a
training box needs three uploaded files and no checkout: `fetch_dagbani.py`,
`prepare_symbols.py`, and `app_lines.txt` from

```sh
python tool/track_b/prepare_symbols.py --corpus data/dagbani \
  --app-lines-out data/dagbani/app_lines.txt
```

That keeps the must-say coverage gate honest on a machine that has no repo.

`--asr` scores the voice with a Dagbani recogniser (`KhayaAI/DONDO-v1`), so the
claim "it says the words" is measured, not asserted. The trainer is
`OHF-Voice/piper1-gpl` (`python3 -m piper.train fit`) with
`--data.phoneme_type text`, `--data.phonemes_path` for the pinned inventory and
`--model.vocoder_warmstart_ckpt` so a new symbol set can start from piper's
base vocoder instead of from zero.

## Running it on Colab

1. `New notebook` → Runtime → Change type → **T4/A100 GPU**, then Runtime →
   **Disconnect** (the run is longer than a free session, so it must be
   reattached, not babysat).
2. One cell to make room for the tools (the script clones the trainer itself):

   ```bash
   %%bash
   mkdir -p /content/track_b /content/dagbani
   ```

   then upload `fetch_dagbani.py`, `prepare_symbols.py`, `colab_train.sh` and
   `app_lines.txt` to `/content/track_b/` (the browser upload button, or
   `drive.mount('/content/drive')` if they live on Drive).
3. The run itself, in the background so a disconnect does not kill it:

   ```bash
   %%bash
   cd /content && CORPUS=/content/dagbani TOOL_DIR=/content/track_b \
     WORK=/content/piper-work EPOCHS=60 \
     nohup bash /content/track_b/colab_train.sh > /content/train.out 2>&1 &
   echo started; sleep 120; tail -5 /content/train.out
   ```

   Keep the tab open, or run the loop in `!while :; do sleep 60; done` in a
   second cell, or Colab will idle-suspend the runtime mid-epoch.

4. Check on it after reconnecting: `tail -30 /content/train.out`, or
   `grep -c . /content/dagbani/metadata.csv` for the data stage.
5. Copy the two finished files out of `/content/dagbani/` — `model.onnx` and
   `model.onnx.json` — into `assets/tts/dagbani_piper/`, run
   `python tool/build_voice_manifests.py`, add the directory to `pubspec.yaml`,
   and run the gate on your own machine:

   ```sh
   python tool/track_b/eval_voice.py --pack assets/tts/dagbani_piper --repo .
   flutter test test/piper_native_inference_test.dart --dart-define=RUN_NATIVE_VOICE=true
   ```

If the VM has no egress to GitHub for the UTMOS predictor, run step 3 with
`MOS=off`; if it also fails the ONNX export on a very new torch, add
`TORCH_EXPORT_LEGACY=1`. Both flags are explained in `colab_train.sh`.

## What has been run, and what has not

Ran end to end on this machine (2026-10-18), on CPU, with 400 licensed
utterances and a 12-utterance smoke corpus: fetch → symbol pinning → coverage
gate → **one full training epoch (exit 0)** → ONNX export (63 MB) → the app's
own gate (`tensor contract: ['input', 'input_lengths', 'scales']`, RTF ~0.4) →
`test/piper_native_inference_test.dart` synthesising 1.16 s of Dagbani audio
from that file through the shipped engine. The audio is unusable — one epoch on
twelve clips is noise — but every *joint* is proven.

Three upstream/CLI facts that would otherwise cost a GPU day, all handled by
flags in `colab_train.sh`:

* `--data.espeak_voice` is required by the CLI even in text mode; it is unused
  there, and the alphabet comes from `phonemes.json`.
* The output dir flag is `--trainer.default_root_dir`, not `--default_root_dir`.
* Two crashes, both reproduced and both guarded: the `val_mos` ModelCheckpoint
  aborts at the end of epoch 1 when UTMOS cannot be downloaded (`MOS=off`), and
  torch>=2.13's dynamo ONNX front end fails on the flow modules, so export needs
  `dynamo=False` (`TORCH_EXPORT_LEGACY=1`).

Not yet done: a real training run on enough data, on a GPU.

## Gates, in order

1. **Coverage** — no app sentence may need a letter the corpus never spoke.
   Measured on the real strings in `lib/core/i18n/`.
2. **Contract** — exported ONNX must advertise exactly the tensors
   `PiperModelSpec` accepts, or the app rejects it at load. `eval_voice.py`
   checks this before anything else.
3. **Speed** — mean real-time factor under 1.0 on two CPU threads.
4. **Intelligibility** — ASR round-trip similarity on the app's own questions.
5. **You** — the earcheck clips. Nothing here can sign off an accent; the pack's
   verdict file keeps `humanListeningApproved: false` until you change it.
