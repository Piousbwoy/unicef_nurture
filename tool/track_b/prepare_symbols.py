"""Turn the fetched Dagbani corpus into what piper1-gpl trains on.

The trainer's `--data.phoneme_type text` mode takes UTF-8 codepoints as the
symbol sequence, so the symbol inventory is ours to fix. This pins it, filters
the corpus to it, and answers the only question that matters before spending
GPU hours: can this data teach a voice that says everything the app needs?

Outputs in --out:
  metadata.csv     piper training CSV:  file.wav|characters
  phonemes.json    pinned symbol -> id map (given to --data.phonemes_path)
  coverage.json    hours, letters, kept/dropped lines, missing letters

Run:  python tool/track_b/prepare_symbols.py --corpus data/dagbani
"""
import argparse, json, re, sys, unicodedata
from pathlib import Path

PAD, BOS, EOS = "_", "^", "$"
# Piper adds these boundaries itself; they must be in the pinned inventory.
SPECIALS = [PAD, BOS, EOS]
APP_STRING_FILES = (
    "lib/core/i18n/dagbani_strings.dart",
    "lib/core/i18n/speech_bank.dart",
)
# The trainer lowercases and NFD-normalises, so the inventory must be built on
# exactly that form or the ids would not line up.
SEPARATORS = (" ", ",", ".", ":", ";", "-", "?", "!", "'")


def app_dagbani_lines(repo: Path, from_file: Path | None) -> list[str]:
    """The sentences the voice must be able to say.

    Read from the app's own string files when the repo is present, otherwise
    from a dump made on the machine that has it (`--app-lines-out`), so this
    gate can also run on a training box that has no checkout.
    """
    if from_file is not None:
        return [
            line.strip()
            for line in from_file.read_text(encoding="utf8").splitlines()
            if line.strip()
        ]
    lines = []
    for rel in APP_STRING_FILES:
        path = repo / rel
        if not path.exists():
            continue
        for line in path.read_text(encoding="utf8").splitlines():
            match = re.search(r"dagbani:\s*['\"](.+)['\"],?\s*$", line)
            if match:
                lines.append(match.group(1))
    return lines


def symbols_of(text: str) -> set[str]:
    folded = unicodedata.normalize("NFD", text.lower())
    return {c for c in folded if not c.isspace()}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", default="data/dagbani")
    ap.add_argument("--repo", default=".")
    ap.add_argument("--max-lines", type=int, default=0, help="cap training rows")
    ap.add_argument("--app-lines", help="read the must-say sentences from a file instead of the repo")
    ap.add_argument("--app-lines-out", help="write the must-say sentences for a machine with no checkout")
    args = ap.parse_args()

    corpus = Path(args.corpus)
    rows = [
        json.loads(line)
        for line in (corpus / "metadata.jsonl").read_text(encoding="utf8").splitlines()
        if line.strip()
    ]
    stats = json.loads((corpus / "corpus_stats.json").read_text(encoding="utf8"))
    if not rows:
        print("no metadata.jsonl rows; run fetch_dagbani.py first")
        return 1

    wanted = app_dagbani_lines(Path(args.repo), Path(args.app_lines) if args.app_lines else None)
    if args.app_lines_out:
        Path(args.app_lines_out).write_text("\n".join(wanted) + "\n", encoding="utf8")
    needed = {c for line in wanted for c in symbols_of(line)}
    seen: set[str] = set()
    for row in rows:
        seen |= symbols_of(row["text"])
    # The inventory comes from the audio, not from wish lists: a symbol with no
    # spoken example would train an un pronounceable embedding.
    inventory = sorted(seen | set(SEPARATORS) | set(SPECIALS))
    # Letters the app must say that this slice of the corpus never spoke. They
    # shrink as more shards are fetched, and must be empty before training.
    needed_not_seen = sorted(needed - seen)

    allowed = set(inventory)
    kept, dropped = [], []
    for row in rows:
        folded = unicodedata.normalize("NFD", row["text"].lower())
        if {c for c in folded} - allowed:
            dropped.append(row["audio"])
            continue
        kept.append(row)
    if args.max_lines:
        kept = kept[: args.max_lines]

    phonemes = {symbol: index for index, symbol in enumerate(inventory)}
    (corpus / "phonemes.json").write_text(
        json.dumps(phonemes, ensure_ascii=False, indent=2) + "\n", encoding="utf8")

    with (corpus / "metadata.csv").open("w", encoding="utf8", newline="") as sink:
        for row in kept:
            name = Path(row["audio"]).name
            text = unicodedata.normalize("NFD", row["text"].lower())
            sink.write(f"{name}|{text}\n")

    app_speakable = [line for line in wanted
                     if not ({c for c in symbols_of(line)} - set(phonemes))]
    coverage = {
        "dataset": stats["dataset"],
        "licence": stats["licence"],
        "corpusHours": stats["hours"],
        "trainingRows": len(kept),
        "droppedRows": len(dropped),
        "symbols": len(phonemes),
        "appLines": len(wanted),
        "appLinesSpeakable": len(app_speakable),
        "letters": "".join(s for s in inventory if s not in SPECIALS),
        "neededButUnseen": needed_not_seen,
    }
    (corpus / "coverage.json").write_text(
        json.dumps(coverage, indent=2, ensure_ascii=False) + "\n", encoding="utf8")

    print(
        f"rows {len(kept)} kept / {len(dropped)} dropped | symbols {len(phonemes)} | "
        f"app lines speakable {len(app_speakable)}/{len(wanted)} | {stats['hours']} h"
    )
    unprovable = [line for line in wanted if line not in app_speakable]
    if unprovable:
        print("BLOCKED, corpus cannot teach:", " ".join(sorted(
            {c for line in unprovable for c in symbols_of(line)} - set(phonemes)
        )))
        return 2
    print("ready: every letter the app needs is in the training inventory")
    return 0


if __name__ == "__main__":
    sys.exit(main())
