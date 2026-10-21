"""Build a closed-set probe folder out of real Dagbani and Twi speech.

The clinical answer set has never been measured against audio: the WaxalNLP
recordings are picture narrations that contain no isolated `Ee` or `Ayi` (see
`tool/track_b/ASR_OPTIONS.md`). This is the second-best thing, and it is labelled
as such: the app's own MMS voice renders the answer words, and the same voice's
already-bundled sentences become the negatives.

What that measures: whether the recogniser's lattice separates *this word* from
*that word* in genuine Dagbani and Twi phonetics, and what silence-looking speech
scores. What it does not measure: an accented, noisy, half-swallowed answer from a
caregiver's phone in a compound. That is still `data/closed_set/record.csv`, and
until a native ear has signed the forms off the floors from here are a starting
point, not an approval.

  python tool/closed_set/make_answer_probe.py --language dagbani
  python tool/closed_set/make_answer_probe.py --language twi
"""
import argparse
import csv
import json
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[2]
VOICES = {
    "dagbani": ("IanKobby/mms-tts-dag-ghana", "dag", "assets/audio/dagbani_mms"),
    "twi": ("facebook/mms-tts-aka", "aka", "assets/audio/twi_mms"),
}
NEGATIVE_SECONDS = 4.0


def resample(wave: np.ndarray, source: int, target: int) -> np.ndarray:
    if source == target:
        return wave
    count = int(round(wave.shape[0] * target / source))
    position = np.linspace(0, wave.shape[0] - 1, count)
    return np.interp(position, np.arange(wave.shape[0]), wave).astype(np.float32)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--language", required=True, choices=sorted(VOICES))
    ap.add_argument("--out", default=str(ROOT / "data/closed_set/probe"))
    args = ap.parse_args()

    repo, code, narration = VOICES[args.language]
    answers = json.loads(
        (ROOT / "tool/closed_set/answers.json").read_text(encoding="utf8")
    )[args.language]
    out = Path(args.out) / args.language
    out.mkdir(parents=True, exist_ok=True)
    rows = []

    from transformers import AutoTokenizer, VitsModel

    model = VitsModel.from_pretrained(repo)
    tokenizer = AutoTokenizer.from_pretrained(repo, language=code)
    rate = model.config.sampling_rate
    import torch

    for answer_id, forms in answers["answers_by_id"].items():
        for form in forms:
            with torch.no_grad():
                wave = model(**tokenizer(form, return_tensors="pt")).waveform
            samples = resample(wave[0].numpy().astype(np.float32), rate, 16000)
            # Trim the voice's trailing silence: a padded take is exactly the
            # case the endpointer is supposed to have removed already.
            energy = np.abs(samples)
            voiced = np.nonzero(energy > 0.01 * max(energy.max(), 1e-6))[0]
            if voiced.size:
                samples = samples[voiced[0] : voiced[-1] + 800]
            name = f"pos_{answer_id}_{form.replace(' ', '_')}.wav"
            sf.write(out / name, samples, 16000)
            rows.append({"file": name, "answer": answer_id, "speaker": "mms-voice"})
            print(f"  said   {name}: {len(samples) / 16000:.2f} s")

    manifest = json.loads((ROOT / narration / "manifest.json").read_text(encoding="utf8"))
    for name in sorted(manifest["clips"]):
        source = ROOT / narration / f"{name}.wav"
        if not source.exists():
            continue
        samples, sample_rate = sf.read(source, dtype="float32")
        if samples.ndim > 1:
            samples = samples.mean(axis=1)
        samples = resample(np.asarray(samples, np.float32), sample_rate, 16000)
        samples = samples[: int(NEGATIVE_SECONDS * 16000)]
        target = f"neg_{name}.wav"
        sf.write(out / target, samples, 16000)
        rows.append({"file": target, "answer": "none", "speaker": "mms-voice"})

    with (out / "manifest.csv").open("w", encoding="utf8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["file", "answer", "speaker"])
        writer.writeheader()
        writer.writerows(rows)
    positives = sum(1 for r in rows if r["answer"] != "none")
    print(
        f"\n{out}: {positives} spoken forms, "
        f"{len(rows) - positives} sentences that answer nothing"
    )
    print(
        f"Next: python tool/closed_set/eval_closed_set.py --clips {out} "
        f"--language {args.language} --repo <the pack this app ships>"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
