"""Throwaway - measurement only, not shippable code.

Build a 100-clip held-out eval set per language from google/WaxalNLP.

Method A (default): datasets-server /rows + /audios endpoints, offset at the
END of the split. Cheap: no 600 MB shard download.
Method B (fallback): fsspec HTTP range read of the last parquet row group
(pattern copied from tool/track_b/fetch_dagbani.py).

Writes tool/asr_eval/data/<lang>/wav/*.wav + manifest.jsonl
{audio, text, duration, split, id} and out/evalset_stats.json.
"""
import argparse
import io
import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path

import soundfile as sf

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "data"
OUT = ROOT / "out"

LANGS = {
    "dag": {"config": "dag_asr", "code": "dga", "label": "Dagbani"},
    "aka": {"config": "aka_asr", "code": "aka", "label": "Akan/Twi"},
}
BASE = "https://datasets-server.huggingface.co"
UA = {"user-agent": "asr-eval-probe/0.1"}


def get(url, timeout=120):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def server_rows(cfg, code, n, split_pref=("test", "validation", "train")):
    """Return rows taken from the END of the best available split."""
    info = json.loads(get(f"{BASE}/info?dataset=google%2FWaxalNLP").decode("utf8"))
    builder = info["dataset_info"][cfg]
    splits = {name: meta["num_examples"]
              for name, meta in (builder.get("splits") or {}).items()}
    chosen = None
    for cand in split_pref:
        if cand in splits:
            chosen = (cand, splits[cand])
            break
    if chosen is None:
        raise RuntimeError(f"no split for {cfg}: {list(splits)}")
    split, total = chosen
    offset = max(0, total - n)
    rows = []
    page = 100
    while len(rows) < n and offset < total:
        take = min(page, total - offset, n - len(rows))
        url = (f"{BASE}/rows?dataset=google%2FWaxalNLP&config={cfg}"
               f"&split={urllib.parse.quote(split, safe='')}&offset={offset}&length={take}")
        batch = json.loads(get(url).decode("utf8"))
        rows.extend(item["row"] for item in batch["rows"])
        offset += take
    return rows, split, total, offset


def audio_of(row, code):
    """Return (samples, rate, head) for the audio column of one row.

    The /rows endpoint returns audio as a LIST of {"src": url}; the parquet
    returns {"bytes": raw}. Handle both.
    """
    audio = row.get("audio")
    if isinstance(audio, list):
        audio = audio[0] if audio else {}
    if isinstance(audio, str):
        audio = {"src": audio}
    raw = None
    if isinstance(audio, dict):
        if audio.get("bytes"):
            raw = bytes(audio["bytes"])
        elif audio.get("src"):
            raw = get(audio["src"], timeout=180)
    if raw is None:
        raise KeyError("no audio bytes/src")
    samples, rate = sf.read(io.BytesIO(raw))
    return samples, rate, raw[:4]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=100)
    ap.add_argument("--max-total-seconds", type=float, default=900.0)
    ap.add_argument("--min-seconds", type=float, default=0.8)
    ap.add_argument("--max-seconds", type=float, default=20.0)
    ap.add_argument("--lang", default="dag,aka")
    args = ap.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)
    stats = {}
    errors = []
    for lang in args.lang.split(","):
        cfg = LANGS[lang]["config"]
        code = LANGS[lang]["code"]
        wdir = DATA / lang / "wav"
        wdir.mkdir(parents=True, exist_ok=True)
        manifest = DATA / lang / "manifest.jsonl"
        try:
            rows, split, total, up_to = server_rows(cfg, code, args.n)
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{lang}: rows fetch failed {type(exc).__name__}: {str(exc)[:300]}")
            continue
        kept, dur_total, wrote = [], 0.0, 0
        for idx, row in enumerate(rows):
            text = row.get("transcription") or row.get("text")
            if isinstance(text, list):
                text = text[0]
            nbest = row.get("nbest")
            if not text and nbest:
                text = nbest[0] if isinstance(nbest, list) else nbest
            text = (text or "").strip()
            if not text:
                continue
            try:
                samples, rate, head = audio_of(row, code)
            except Exception as exc:  # noqa: BLE001
                errors.append(f"{lang}[{idx}]: audio {type(exc).__name__}: {str(exc)[:200]}")
                continue
            seconds = len(samples) / rate
            if not args.min_seconds <= seconds:
                continue
            if dur_total + min(seconds, args.max_seconds) > args.max_total_seconds:
                errors.append(f"{lang}: stopped at {wrote} rows due to duration cap")
                break
            name = f"{code}_{wrote:04d}.wav"
            # Store as 16 kHz mono PCM_16: every candidate model consumes 16 kHz
            # and 44.1 kHz stereo would bloat the throwaway set ~8x.
            if samples.ndim > 1:
                samples = samples.mean(axis=1)
            orig_rate = rate
            if int(rate) != 16000:
                from math import gcd

                from scipy.signal import resample_poly
                g = gcd(16000, int(rate))
                samples = resample_poly(samples, 16000 // g, int(rate) // g)
                rate = 16000
            try:
                sf.write(wdir / name, samples, rate, subtype="PCM_16")
            except Exception as exc:  # noqa: BLE001
                errors.append(f"{lang}[{idx}]: write {type(exc).__name__}: {str(exc)[:160]}")
                continue
            rec = {
                "audio": f"data/{lang}/wav/{name}",
                "text": text,
                "duration": round(seconds, 3),
                "sample_rate": int(rate),
                "source_sample_rate": int(orig_rate),
                "split": split,
                "id": row.get("id") or idx,
                "abs_path": str(wdir / name),
            }
            kept.append(rec)
            dur_total += seconds
            wrote += 1
        with manifest.open("w", encoding="utf8") as sink:
            for rec in kept:
                sink.write(json.dumps(rec, ensure_ascii=False) + "\n")
        stats[lang] = {
            "config": cfg, "split": split, "split_rows": total,
            "utterances": len(kept), "total_seconds": round(dur_total, 1),
            "source_sample_rates": sorted({r["sample_rate"] for r in kept}),
            "mean_seconds": round(dur_total / max(len(kept), 1), 2),
            "manifest": str(manifest),
        }
    stats["_errors"] = errors[:40]
    (OUT / "evalset_stats.json").write_text(
        json.dumps(stats, indent=2, ensure_ascii=False) + "\n", encoding="utf8")
    print("wrote evalset_stats.json", flush=True)
    return 0 if stats else 1


if __name__ == "__main__":
    sys.exit(main())
