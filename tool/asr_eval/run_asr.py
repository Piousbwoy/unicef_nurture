"""Throwaway - measurement only, not shippable code.

Transcribe the eval manifest with one candidate model and score CER/WER +
closed-set answer survival. Streams results so a partial run is still truthful.

torch is pinned to 2 intra-op threads (the app's phone budget proxy).
"""
import argparse
import json
import os
import sys
import time
from pathlib import Path

import numpy as np
import soundfile as sf

sys.path.insert(0, str(Path(__file__).resolve().parent))
from scoring import norm, scores  # noqa: E402

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "out"

ANSWERS = {
    "dag": ["Ee", "Ayi", "Mi bɛ mi"],
    "aka": [],  # no localised Twi answer words exist in the app yet
}


def load_audio(path, want_sr):
    x, sr = sf.read(path)
    if x.ndim > 1:
        x = x.mean(axis=1)
    if int(sr) != int(want_sr):
        from math import gcd

        from scipy.signal import resample_poly
        g = gcd(int(want_sr), int(sr))
        x = resample_poly(x, int(want_sr) // g, int(sr) // g)
    # return the rate the buffer is ACTUALLY at, or the feature extractor
    # rejects it ("trained using a sampling rate of 16000")
    return np.asarray(x, dtype=np.float32), int(want_sr)


def build(model_id, device_threads=2):
    import torch
    torch.set_num_threads(device_threads)
    torch.set_grad_enabled(False)
    from transformers import AutoConfig, AutoProcessor

    cfg = AutoConfig.from_pretrained(model_id)
    mtype = cfg.model_type
    processor = AutoProcessor.from_pretrained(model_id)
    sr = getattr(processor.feature_extractor, "sampling_rate", None) or \
        getattr(cfg, "sampling_rate", 16000)
    if mtype == "whisper":
        from transformers import AutoModelForSpeechSeq2Seq as CLS
        model = CLS.from_pretrained(model_id)
        kind = "whisper"
    else:
        from transformers import AutoModelForCTC as CLS
        model = CLS.from_pretrained(model_id)
        kind = "ctc"
    model.eval()
    n_params = sum(p.numel() for p in model.parameters())
    return model, processor, kind, mtype, int(sr), n_params


def transcribe_one(model, processor, kind, wave, sr, model_sr, lang_hint):
    if kind == "whisper":
        feats = processor.feature_extractor(
            wave, sampling_rate=sr, return_tensors="pt"
        ).input_features
        gen = model.generate(
            feats, max_new_tokens=112, task="transcribe",
            language=lang_hint if lang_hint else None,
        )
        return processor.batch_decode(gen, skip_special_tokens=True)[0]
    feats = processor(wave, sampling_rate=sr, return_tensors="pt").input_features
    logits = model(feats).logits
    ids = logits.argmax(-1)[0]
    return processor.batch_decode([ids], skip_special_tokens=True)[0]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--lang", required=True, choices=["dag", "aka"])
    ap.add_argument("--tag", default=None)
    ap.add_argument("--limit", type=int, default=100)
    ap.add_argument("--deadline", type=float, default=0, help="wall-clock seconds, 0=none")
    ap.add_argument("--threads", type=int, default=2)
    ap.add_argument("--whisper-language", default=None)
    args = ap.parse_args()

    tag = args.tag or args.model.replace("/", "__")
    rows = [json.loads(l) for l in (ROOT / "data" / args.lang / "manifest.jsonl").open(encoding="utf8")]
    rows = rows[: args.limit]
    out_path = OUT / f"hyp_{tag}.jsonl"
    res_path = OUT / f"score_{tag}.json"

    started = time.time()
    model, processor, kind, mtype, model_sr, n_params = build(args.model, args.threads)
    load_seconds = time.time() - started
    fp32_bytes = sum(
        f.stat().st_size for f in Path(os.path.expanduser(
            f"~/.cache/huggingface/hub/models--{args.model.replace('/', '--')}")).rglob("*.safetensors")
    ) if True else 0

    hyps, timings = [], []
    with out_path.open("w", encoding="utf8") as sink:
        for i, row in enumerate(rows):
            if args.deadline and time.time() - started > args.deadline:
                print("DEADLINE HIT at clip", i, flush=True)
                break
            wave, sr = load_audio(ROOT / row["audio"], model_sr)
            t0 = time.time()
            try:
                hyp = transcribe_one(model, processor, kind, wave, sr, model_sr,
                                     args.whisper_language)
            except Exception as exc:  # noqa: BLE001
                hyp = f"__ERROR__ {type(exc).__name__}: {exc}"[:200]
            dt = time.time() - t0
            timings.append({"clip_seconds": row["duration"], "wall_seconds": round(dt, 3)})
            rec = dict(row)
            rec["hypothesis"] = hyp
            rec["infer_seconds"] = round(dt, 3)
            rec.update(scores(row["text"], hyp))
            sink.write(json.dumps(rec, ensure_ascii=False) + "\n")
            sink.flush()
            hyps.append(rec)

    # ---- aggregate ----
    n = len(hyps)
    ok = [h for h in hyps if not h["hypothesis"].startswith("__ERROR__")]
    if not ok:
        # never report 0.0 for a run that scored nothing - that is a fabricated
        # perfect score. Report null and the first error instead.
        first_err = hyps[0]["hypothesis"] if hyps else "no clips"
        summary = {"model": args.model, "tag": tag, "lang": args.lang,
                   "clips_scored": n, "clips_ok": 0, "FAILED": True,
                   "mean_cer": None, "mean_wer": None, "first_error": first_err}
        res_path.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n",
                            encoding="utf8")
        print("ALL CLIPS FAILED:", tag, flush=True)
        return 3
    cer = sum(h["cer"] for h in ok) / len(ok)
    wer = sum(h["wer"] for h in ok) / len(ok)
    gold_chars = sum(len(h["norm_gold"].replace(" ", "")) for h in ok)
    gold_words = sum(len(h["norm_gold"].split()) for h in ok)
    err_chars = sum(h["cer"] * len(h["norm_gold"].replace(" ", "")) for h in ok)
    err_words = sum(h["wer"] * max(len(h["norm_gold"].split()), 1) for h in ok)

    targets = ANSWERS[args.lang]
    closed = {}
    for tgt in targets:
        tn = norm(tgt)
        gold_hits = [h for h in ok if tn in h["norm_gold"].split()]
        survives = sum(1 for h in gold_hits if tn in h["norm_hyp"].split())
        contains = [h for h in ok if tn in h["norm_gold"]]
        anywhere = sum(1 for h in contains if tn in h["norm_hyp"])
        closed[tgt] = {
            "gold_clips_exact_word": len(gold_hits),
            "target_survives": survives,
            "accuracy_exact": round(survives / len(gold_hits), 4) if gold_hits else None,
            "gold_clips_contains": len(contains),
            "survives_contains": anywhere,
            "accuracy_contains": round(anywhere / len(contains), 4) if contains else None,
        }
    audio_s = sum(t["clip_seconds"] for t in timings)
    wall_s = sum(t["wall_seconds"] for t in timings)
    ten_s = [t for t in timings if t["clip_seconds"] >= 8.0]

    summary = {
        "model": args.model, "tag": tag, "lang": args.lang,
        "kind": kind, "model_type": mtype, "params": n_params,
        "model_sample_rate": model_sr, "threads": args.threads,
        "load_seconds": round(load_seconds, 1),
        "clips_scored": n, "clips_ok": len(ok),
        "mean_cer": round(cer, 4), "mean_wer": round(wer, 4),
        "micro_cer": round(err_chars / gold_chars, 4) if gold_chars else None,
        "micro_wer": round(err_words / gold_words, 4) if gold_words else None,
        "closed_set": closed,
        "audio_seconds": round(audio_s, 1), "wall_seconds": round(wall_s, 1),
        "rtf_mean": round(wall_s / audio_s, 3) if audio_s else None,
        "rtf_on_ge8s_clips": round(
            sum(t["wall_seconds"] for t in ten_s) / sum(t["clip_seconds"] for t in ten_s), 3
        ) if ten_s else None,
        "fp32_weight_bytes": fp32_bytes,
        "total_elapsed": round(time.time() - started, 1),
    }
    res_path.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf8")
    print(json.dumps({k: summary[k] for k in
                      ("tag", "clips_scored", "mean_cer", "mean_wer", "rtf_mean")}), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
