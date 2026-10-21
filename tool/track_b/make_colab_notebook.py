"""Build tool/track_b/colab_dagbani_voice.ipynb from the real scripts.

The notebook is generated, not hand-written, so the code that runs on the GPU is
byte-identical to the code in this repo. Copying these steps into a Colab cell by
hand is how a training run ends up differing from the one that was tested.

Run:  python tool/track_b/make_colab_notebook.py
"""
import json
from pathlib import Path

HERE = Path(__file__).parent
# Order matters: the data stage reads the two Python tools and the must-say list.
EMBED = [
    "fetch_dagbani.py",
    "prepare_symbols.py",
    "colab_train.sh",
]
APP_LINES = Path("data/dagbani/app_lines.txt")

MOUNT = r'''# Colab -> Drive is the only place a checkpoint survives a session ending.
# A T4/L4 run of this length WILL be disconnected at some point.
from google.colab import drive
import os
drive.mount("/content/drive")
WORK_DIR = "/content/drive/MyDrive/carebridge-dagbani"
os.makedirs(WORK_DIR, exist_ok=True)
print("checkpoints will survive in:", WORK_DIR)
!nvidia-smi --query-gpu=name,memory.total --format=csv
'''

HEADER = """### CareBridge — train the Dagbani voice (Track B)

Trains a Piper/VITS Dagbani voice on the licensed corpus, then exports the ONNX
pack the app loads. Everything here is the repository's own
`tool/track_b/` scripts, embedded verbatim by `make_colab_notebook.py` — do not
edit the cells below, edit the scripts in the repo and regenerate.

- **Data**: `fiifinketia/dagbani-bible-audio-text-tts`, CC-BY-4.0, ~137 h at 24 kHz.
- **Warm start**: `_base_model/base_model.ckpt` (933 MB) holds the vocoder, so only
  the text side learns from scratch.
- **Runtime**: expect 6–12 h on an L4. Checkpoints live in Google Drive, so a
  disconnected session does not lose the run — it costs ~4 GB of Drive space.
- **Do not commit the resulting weights** to the repo until the licence is settled;
  see `assets/tts/dagbani_piper/PROVENANCE.md`.

Set the two knobs in the next cell, then Run all.
"""

KNOBS = r'''EPOCHS = 60      # 20 gives a listening sample sooner; 60 is the real run
BATCH = 32
SHARDS = 37      # 37 shards is the whole licensed split; 3 is a smoke test
MOS = "off"      # the UTMOS predictor needs egress; leaving it on aborts epoch 1
'''

RUN = r'''%%bash -s "$EPOCHS" "$BATCH" "$SHARDS" "$MOS" "$WORK_DIR"
# Scripts stay on local disk; only the training root goes to Drive, so a
# disconnected session keeps its checkpoints without copying a 14 GB corpus.
set -eux
CORPUS=/content/dagbani TOOL_DIR=/content/track_b WORK="$5/piper-work" \
  EPOCHS="$1" BATCH="$2" SHARDS="$3" MOS="$4" TORCH_EXPORT_LEGACY=1 \
  bash /content/track_b/colab_train.sh
'''

FETCH_LINES = r'''# The must-say sentences the voice has to be able to pronounce; measured against
# these is what decides whether the pack is usable in the app at all.
import os
from pathlib import Path
os.makedirs("/content/track_b", exist_ok=True)
Path("/content/track_b/app_lines.txt").write_text(APP_LINES_TEXT, encoding="utf8")
print(len(Path("/content/track_b/app_lines.txt").read_text(encoding="utf8").splitlines()), "must-say lines")
'''

TAIL = """### After the run

`colab_train.sh` leaves `model.onnx`, `model.onnx.json`, `coverage.json` and
`earcheck_1.wav` in `/content/dagbani`. Copy that folder into
`MyDrive/carebridge-dagbani/final/`, then on this machine:

```
python tool/track_b/eval_voice.py --pack <the folder>   # contract + RTF + listening clips
python tool/build_voice_manifests.py                   # writes model_manifest.json
```

`coverage.json` must read 73/73 before the pack goes anywhere near the app, and a
native Dagbani ear has to sign the accent off — the app's own invariant, and the
reason this is not a number we get to decide alone.
"""


def cell(source, kind="code"):
    if kind == "markdown":
        return {"cell_type": "markdown", "metadata": {}, "source": source.splitlines(True)}
    return {
        "cell_type": "code",
        "execution_count": None,
        "metadata": {},
        "outputs": [],
        "source": source.splitlines(True),
    }


def writefile(name, text):
    return f"%%writefile /content/track_b/{name}\n{text}"


def main() -> int:
    cells = [cell(HEADER, "markdown"), cell(MOUNT)]
    knobs = KNOBS + '\nAPP_LINES_TEXT = r"""\n' + APP_LINES.read_text(encoding="utf8") + '\n"""\n'
    cells.append(cell(knobs))
    cells.append(cell(FETCH_LINES))
    for name in EMBED:
        cells.append(cell(writefile(name, Path(HERE, name).read_text(encoding="utf8"))))
    cells.append(cell(RUN))
    cells.append(cell(TAIL, "markdown"))

    notebook = {
        "nbformat": 4,
        "nbformat_minor": 0,
        "metadata": {
            "colab": {"provenance": [], "gpu_type": "NVIDIA L4"},
            "kernelspec": {"name": "python3", "display_name": "Python 3"},
            "accelerator": "gpu",
        },
        "cells": cells,
    }
    out = Path(HERE, "colab_dagbani_voice.ipynb")
    out.write_text(json.dumps(notebook, indent=1), encoding="utf8")
    print(f"wrote {out} with {len(cells)} cells")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
