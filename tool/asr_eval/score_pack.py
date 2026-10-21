"""Score an exported `asr-v1` pack, not the HuggingFace model it came from.

The held-out CER in `tool/track_b/ASR_OPTIONS.md` is the fp32 model's number. A
quantised pack is a different artefact: int8 weights, an ONNX graph, and the
app's own frontend in front of it. This runs the eight held-out clips through
exactly that path with onnxruntime, so "the pack measures what the model
measured" is a claim with a number behind it.

  python tool/asr_eval/score_pack.py --pack data/asr_dev/twi_akan \\
      --manifest tool/asr_eval/data/aka/manifest.jsonl --clips 8
"""
import argparse
import json
import statistics
import sys
import time
from pathlib import Path

import numpy as np
import onnxruntime as ort
import soundfile as sf

sys.path.insert(0, str(Path(__file__).resolve().parent))
from score_dondo import cer, to_16k, wer  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", required=True)
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--clips", type=int, default=8)
    ap.add_argument("--skip", type=int, default=0)
    ap.add_argument("--threads", type=int, default=4)
    ap.add_argument(
        "--max-seconds",
        type=float,
        default=4.0,
        help="clip length to feed. The pack's own ceiling is 4 s, which is what "
        "the app can record; parity against the HuggingFace run needs the whole "
        "20 s clip the fp32 model was scored on, and says so in its output.",
    )
    ap.add_argument("--out", default=str(ROOT / "tool/asr_eval/out/pack_score.json"))
    args = ap.parse_args()

    pack = Path(args.pack)
    contract = json.loads((pack / "frontend.json").read_text(encoding="utf8"))
    audio, model = contract["audio"], contract["model"]
    if audio["features"] != "waveform":
        raise SystemExit(
            "this scorer feeds the raw-waveform recipe; a mel pack needs its "
            "tables and the python extractor that made them"
        )
    rate = audio["sample_rate"]
    epsilon = float(audio["normalize_epsilon"])
    labels = model["labels"]
    blank = model["blank_index"]
    limit = int(args.max_seconds * rate)
    if limit > int(audio["max_frames"]):
        print(
            f"note: feeding {args.max_seconds:.1f} s, past this pack's "
            f"max_frames={audio['max_frames']} ({int(audio['max_frames']) / rate:.1f} s) "
            "ceiling, so the number is comparable to the fp32 run rather than "
            "to a take the app could actually record",
            flush=True,
        )

    session = ort.InferenceSession(
        str(pack / "model.onnx"),
        providers=[
            p for p in ("CPUExecutionProvider",) if p in ort.get_available_providers()
        ],
    )

    rows = [
        json.loads(line)
        for line in Path(args.manifest).read_text(encoding="utf8").splitlines()
        if line.strip()
    ][args.skip : args.skip + args.clips]

    cers, wers_, rtfs, records = [], [], [], []
    for index, row in enumerate(rows, 1):
        samples, source = sf.read(row["abs_path"], dtype="float32")
        if samples.ndim > 1:
            samples = samples.mean(axis=1)
        samples = to_16k(np.asarray(samples, dtype=np.float32), source)[:limit]
        values = (samples - samples.mean()) / np.sqrt(samples.var() + epsilon)
        mask = np.ones((1, len(values)), dtype=np.int64)
        started = time.perf_counter()
        logits = session.run(
            ["output"],
            {
                "input_values": values.reshape(1, -1).astype(np.float32),
                "attention_mask": mask,
            },
        )[0]
        took = time.perf_counter() - started
        path, previous = [], -1
        for frame in logits.argmax(axis=-1)[0]:
            token = int(frame)
            if token != blank and token != previous:
                path.append(labels[token])
            previous = token
        text = "".join(t if t != "|" else " " for t in path).strip()
        score_cer, score_wer = cer(row["text"], text), wer(row["text"], text)
        cers.append(score_cer)
        wers_.append(score_wer)
        rtfs.append(took / (len(values) / rate))
        records.append(
            {
                "id": row.get("id", index),
                "cer": round(score_cer, 4),
                "wer": round(score_wer, 4),
                "rtf": round(took / (len(values) / rate), 3),
                "hypothesis": text,
            }
        )
        print(
            f"{index}/{len(rows)} cer={score_cer:.3f} rtf={took / (len(values) / rate):.2f}",
            flush=True,
        )

    summary = {
        "pack": str(pack),
        "clips": len(rows),
        "max_seconds": args.max_seconds,
        "mean_cer": round(statistics.mean(cers), 4) if cers else None,
        "median_cer": round(statistics.median(cers), 4) if cers else None,
        "mean_wer": round(statistics.mean(wers_), 4) if wers_ else None,
        "mean_rtf": round(statistics.mean(rtfs), 3) if rtfs else None,
        "clips_under_025_cer": sum(c < 0.25 for c in cers),
        "records": records,
    }
    Path(args.out).write_text(json.dumps(summary, indent=1), encoding="utf8")
    print(json.dumps({k: v for k, v in summary.items() if k != "records"}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
