"""Score any CTC pack against a held-out WaxalNLP split.

Same normalisation and the same CER/WER code as `score_dondo.py` — imported, not
copied, because two copies of a scoring rule is how two models end up measured on
different rulers.

  python tool/asr_eval/score_ctc.py --repo KhayaAI/w2v-bert-dga \\
      --manifest tool/asr_eval/data/dag/manifest.jsonl --answers dagbani --clips 24
"""
import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np
import soundfile as sf
import torch

sys.path.insert(0, str(Path(__file__).parent))
from score_dondo import cer, to_16k, wer, normalise  # noqa: E402

torch.set_num_threads(4)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--answers", required=True, choices=["dagbani", "twi"])
    ap.add_argument("--clips", type=int, default=24)
    ap.add_argument("--skip", type=int, default=0)
    ap.add_argument("--max-seconds", type=float, default=20.0)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    from transformers import AutoModelForCTC, AutoProcessor

    forms = json.loads(
        Path("tool/closed_set/answers.json").read_text(encoding="utf8")
    )[args.answers]["answers_by_id"]
    # The app hears spaces between words; a character-label model emits them as
    # its own token, so compare with whitespace removed on both sides.
    forms = {k: [f.replace(" ", "").casefold() for f in v] for k, v in forms.items()}

    rows = [
        json.loads(line)
        for line in Path(args.manifest).read_text(encoding="utf8").splitlines()
        if line.strip()
    ][args.skip: args.skip + args.clips]

    processor = AutoProcessor.from_pretrained(args.repo)
    model = AutoModelForCTC.from_pretrained(args.repo).to("cpu").eval()
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    handle = out.open("w", encoding="utf8")
    records = []

    for index, row in enumerate(rows):
        path = Path(row.get("abs_path") or Path(args.manifest).parent / row["audio"])
        if not path.exists():
            path = Path("tool/asr_eval") / row["audio"]
        samples, source_sr = sf.read(path)
        samples = np.asarray(samples, dtype=np.float32)
        if samples.ndim > 1:
            # Some corpus files are stereo; the mic and every model here are mono.
            samples = samples.mean(axis=1)
        samples = samples[: int(args.max_seconds * source_sr)]
        seconds = len(samples) / source_sr
        samples = to_16k(samples, source_sr)
        started = time.time()
        with torch.no_grad():
            inputs = processor(samples, sampling_rate=16000, return_tensors="pt", padding=True)
            ids = model(**inputs).logits.argmax(dim=-1)[0].tolist()
            text = processor.tokenizer.decode(ids)
        took = time.time() - started
        heard = normalise(text).replace(" ", "")
        record = {
            "id": row.get("id", path.stem),
            "gold": row["text"],
            "hypothesis": text,
            "audio_seconds": round(seconds, 2),
            "wall_seconds": round(took, 2),
            "rtf": round(took / seconds, 2),
            "cer": round(cer(row["text"], text), 4),
            "wer": round(wer(row["text"], text), 4),
            "answer_in_gold": {
                a: any(f in normalise(row["text"]).replace(" ", "") for f in fs)
                for a, fs in forms.items()
            },
            "answer_heard": {a: any(f in heard for f in fs) for a, fs in forms.items()},
        }
        records.append(record)
        print(
            f"{index + 1}/{len(rows)} cer={record['cer']:.3f} rtf={record['rtf']:.2f}",
            flush=True,
        )
        handle.write(json.dumps(records[-1], ensure_ascii=False) + "\n")
        handle.flush()

    cers = [r["cer"] for r in records]
    summary = {
        "repo": args.repo,
        "language": args.answers,
        "split": rows[0].get("split") if rows else None,
        "clips": len(records),
        "audio_seconds": round(sum(r["audio_seconds"] for r in records), 1),
        "mean_cer": round(float(np.mean(cers)), 4) if cers else None,
        "median_cer": round(float(np.median(cers)), 4) if cers else None,
        "mean_wer": round(float(np.mean([r["wer"] for r in records])), 4) if records else None,
        "mean_rtf": round(float(np.mean([r["rtf"] for r in records])), 2) if records else None,
        "clips_under_025_cer": sum(1 for c in cers if c < 0.25),
        "clips_under_035_cer": sum(1 for c in cers if c < 0.35),
    }
    handle.write(json.dumps({"summary": summary}, ensure_ascii=False) + "\n")
    handle.close()
    print(json.dumps(summary))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
