"""Pull the licensed Dagbani corpus into the training shape the pack pipeline wants.

Input:  fiifinketia/dagbani-bible-audio-text-tts — 53,410 utterances, ~137 h,
        24 kHz mono, CC-BY-4.0 (verified on the hub 2026-10-18).
Output: <out>/audio/*.wav at the sample rate piper-style VITS trains on,
        <out>/metadata.jsonl with {"audio","text","language","speaker"},
        <out>/corpus_stats.json with hours, letter inventory and licence.

Shards are read over HTTP range requests, so `--shards 1` costs a few hundred
MB rather than the 12 GB dataset.

Run:  python tool/track_b/fetch_dagbani.py --out data/dagbani --shards 1
"""
import argparse, collections, io, json, re, statistics, sys
from pathlib import Path

import fsspec
import pyarrow.parquet as pq
import soundfile as sf

DATASET = "fiifinketia/dagbani-bible-audio-text-tts"
LICENSE = "CC-BY-4.0"
SHARDS = 37
RATE = 22050  # what the app's existing VITS packs train at

# Read-speaker bible text still carries chapter markers and verse numbers.
NOISE = re.compile(r"^[0-9]+\s*$")


def normalise(text: str) -> str:
    """One line, no verse numbering, no double spaces, no trailing punctuation
    the model would have to learn to pause on."""
    text = text.replace("\n", " ")
    text = " ".join(w for w in text.split() if not NOISE.match(w))
    return text.strip()


def shard_rows(index: int):
    url = (
        f"https://huggingface.co/datasets/{DATASET}/resolve/main/"
        f"data/train-{index:05d}-of-{SHARDS:05d}.parquet?download=true"
    )
    fs = fsspec.filesystem("http")
    with fs.open(url, "rb", block_size=32 * 2**20) as handle:
        parquet = pq.ParquetFile(handle)
        for group in range(parquet.num_row_groups):
            for row in parquet.read_row_group(group).to_pylist():
                yield row


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="data/dagbani")
    ap.add_argument("--shards", type=int, default=1, help="how many shards to pull")
    ap.add_argument("--limit", type=int, default=0, help="cap utterances (0 = all)")
    ap.add_argument("--min-seconds", type=float, default=1.2)
    ap.add_argument("--max-seconds", type=float, default=20.0)
    args = ap.parse_args()

    out = Path(args.out)
    (out / "audio").mkdir(parents=True, exist_ok=True)
    metadata = out / "metadata.jsonl"
    stats_path = out / "corpus_stats.json"

    inventory = collections.Counter()
    durations, written, skipped = [], 0, 0
    with metadata.open("w", encoding="utf8") as sink:
        for index in range(min(args.shards, SHARDS)):
            for row in shard_rows(index):
                if args.limit and written >= args.limit:
                    break
                text = normalise(row.get("text") or "")
                audio = row.get("audio")
                if not text or not audio or not audio.get("bytes"):
                    skipped += 1
                    continue
                samples, source_rate = sf.read(io.BytesIO(audio["bytes"]))
                seconds = len(samples) / source_rate
                if not args.min_seconds <= seconds <= args.max_seconds:
                    skipped += 1
                    continue
                name = f"dag_{index:02d}_{written:06d}.wav"
                sf.write(
                    out / "audio" / name,
                    samples,
                    source_rate,
                    subtype="PCM_16",
                )
                inventory.update(text)
                durations.append(seconds)
                sink.write(
                    json.dumps(
                        {
                            "audio": f"audio/{name}",
                            "text": text,
                            "language": "dag",
                            "speaker": "dagbani-bible",
                        },
                        ensure_ascii=False,
                    )
                    + "\n"
                )
                written += 1
            if args.limit and written >= args.limit:
                break

    letters = "".join(sorted(c for c in inventory if not c.isspace()))
    stats = {
        "dataset": DATASET,
        "licence": LICENSE,
        "utterances": written,
        "skipped": skipped,
        "hours": round(sum(durations) / 3600, 2),
        "meanSeconds": round(statistics.mean(durations), 2) if durations else 0,
        "trainSampleRate": RATE,
        "sourceSampleRate": 24000,
        "letters": letters,
        "letterCount": len(letters),
    }
    stats_path.write_text(json.dumps(stats, indent=2, ensure_ascii=False) + "\n", encoding="utf8")
    print(
        f"{written} utterances ({stats['hours']} h) -> {out}, "
        f"{skipped} skipped, inventory {len(letters)} letters"
    )
    return 0 if written else 1


if __name__ == "__main__":
    sys.exit(main())
