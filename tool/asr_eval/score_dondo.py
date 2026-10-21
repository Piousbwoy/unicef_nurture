"""Is an existing Ghanaian ASR model accurate enough to ship? Answer with CER.

Scores `KhayaAI/w2v-bert-dga` (DONDO, Apache-2.0) on the licensed Dagbani corpus
we already hold: real speech, real transcripts, no synthesis anywhere near it.
Also reports what survives when the app's clinical answers are searched for in
the hypothesis, because that is the only accuracy that matters for voice input.

Console is cp1252, so every non-ASCII result goes to a file, never stdout.

  python tool/asr_eval/score_dondo.py --clips 12 --out tool/asr_eval/out/dondo.json
"""
import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np
import soundfile as sf
import torch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from scoring import norm, scores  # noqa: E402

torch.set_num_threads(4)

REPO = "KhayaAI/w2v-bert-dga"
ANSWERS = {"yes": ["ee"], "no": ["ayi"], "unsure": ["mibɛmi", "mi bɛ mi"]}


def to_16k(samples: np.ndarray, source_sr: int) -> np.ndarray:
    """Linear interpolation, the same rule the app's Dart frontend uses, so this
    measurement is not quietly scoring a different signal than the phone feeds."""
    if source_sr == 16000:
        return samples
    count = int(round(len(samples) * 16000 / source_sr))
    position = np.linspace(0, len(samples) - 1, count)
    return np.interp(position, np.arange(len(samples)), samples).astype(np.float32)


def normalise(text: str) -> str:
    """The one ruler, imported from `scoring.py` rather than restated here.

    An earlier copy of this function dropped every space, which made `wer()`
    compare two single tokens: it returned 1.0 for any two different sentences
    and hid the fact that it was measuring nothing. `scoring.norm` keeps word
    boundaries, so WER means word error rate again.
    """
    return norm(text)


def cer(gold: str, hypothesis: str) -> float:
    return scores(gold, hypothesis)["cer"]


def wer(gold: str, hypothesis: str) -> float:
    return scores(gold, hypothesis)["wer"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", default="data/dagbani")
    ap.add_argument("--clips", type=int, default=12)
    ap.add_argument("--skip", type=int, default=0)
    ap.add_argument("--repo", default=REPO)
    ap.add_argument("--out", default="tool/asr_eval/out/dondo.json")
    ap.add_argument("--max-seconds", type=float, default=20.0)
    args = ap.parse_args()

    from transformers import AutoModelForCTC, AutoProcessor

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    handle = out_path.open("w", encoding="utf8")

    rows = [
        json.loads(line)
        for line in Path(args.corpus, "metadata.jsonl").read_text(encoding="utf8").splitlines()
        if line.strip()
    ]
    # Longest-first would bias the timing sample; take them in corpus order.
    rows = rows[args.skip: args.skip + args.clips]

    processor = AutoProcessor.from_pretrained(args.repo)
    model = AutoModelForCTC.from_pretrained(args.repo).to("cpu").eval()
    print(f"loaded {args.repo}: {sum(p.numel() for p in model.parameters()) / 1e6:.0f}M params")

    results = []
    for index, row in enumerate(rows):
        samples, source_sr = sf.read(Path(args.corpus) / row["audio"])
        samples = np.asarray(samples, dtype=np.float32)
        if samples.ndim > 1:
            # Some corpus files are stereo; the mic and every model here are mono.
            samples = samples.mean(axis=1)
        samples = samples[: int(args.max_seconds * source_sr)]
        audio_seconds = len(samples) / source_sr
        samples = to_16k(samples, source_sr)
        started = time.time()
        with torch.no_grad():
            inputs = processor(
                samples,
                sampling_rate=16000,
                return_tensors="pt",
                padding=True,
            )
            logits = model(**inputs).logits
            ids = logits.argmax(dim=-1)[0].tolist()
            text = processor.tokenizer.decode(ids)
        took = time.time() - started
        seconds = audio_seconds
        hypothesis = normalise(text)
        found = {
            answer: any(form.replace(" ", "") in hypothesis.replace(" ", "") for form in forms)
            for answer, forms in ANSWERS.items()
        }
        record = {
            "file": row["audio"],
            "gold": row["text"],
            "hypothesis": text,
            "audio_seconds": round(seconds, 2),
            "wall_seconds": round(took, 2),
            "rtf": round(took / seconds, 2),
            "cer": round(cer(row["text"], text), 4),
            "wer": round(wer(row["text"], text), 4),
            "answer_words_in_gold": {
                answer: any(f in normalise(row["text"]) for f in forms)
                for answer, forms in ANSWERS.items()
            },
            "answer_words_heard": found,
        }
        results.append(record)
        print(
            f"{index + 1}/{len(rows)} cer={record['cer']:.3f} rtf={record['rtf']:.2f} "
            f"({record['audio_seconds']}s audio in {record['wall_seconds']}s)",
            flush=True,
        )
        handle.write(json.dumps({"summary": summary(results), "records": results}, ensure_ascii=False))
        handle.write("\n")
        handle.flush()

    final = summary(results)
    handle.write(json.dumps({"final": final}, ensure_ascii=False) + "\n")
    handle.close()
    print(json.dumps(final))
    return 0


def summary(results):
    if not results:
        return {}
    return {
        "clips": len(results),
        "audio_seconds": round(sum(r["audio_seconds"] for r in results), 1),
        "mean_cer": round(float(np.mean([r["cer"] for r in results])), 4),
        "median_cer": round(float(np.median([r["cer"] for r in results])), 4),
        "mean_wer": round(float(np.mean([r["wer"] for r in results])), 4),
        "mean_rtf": round(float(np.mean([r["rtf"] for r in results])), 2),
        "clips_under_035_cer": sum(1 for r in results if r["cer"] < 0.35),
    }


if __name__ == "__main__":
    raise SystemExit(main())
