"""Throwaway - measurement only, not shippable code.

Download only the weights+preprocessor files needed to run each candidate,
skipping duplicate pytorch_model.bin copies. Writes out/downloads.json.
"""
import json
import sys
import time
from pathlib import Path

from huggingface_hub import snapshot_download

OUT = Path(__file__).resolve().parent / "out"
OUT.mkdir(parents=True, exist_ok=True)

REPOS = [
    "KhayaAI/w2v-bert-dga",
    "asr-africa/wav2vec2-xls-r-akan-20-hours",
    "jdapaah/whisper-small-twi-arxiv",
    "openai/whisper-tiny",
]

ALLOW = [
    "model.safetensors",
    "model.safetensors.index.json",
    "*.safetensors",
    "config.json",
    "generation_config.json",
    "preprocessor_config.json",
    "feature_extractor_config.json",
    "processor_config.json",
    "tokenizer_config.json",
    "tokenizer.json",
    "vocab.json",
    "vocab.txt",
    "spiece.model",
    "special_tokens_map.json",
    "normalizers.json",
    "added_tokens.json",
    "merges.txt",
    "all_results.json",
    "README.md",
]

results = {}
order = sys.argv[1:] or REPOS
for repo in order:
    started = time.time()
    rec = {"repo": repo}
    try:
        path = snapshot_download(
            repo_id=repo,
            allow_patterns=ALLOW,
            ignore_patterns=["*.bin", "*.h5", "*.msgpack", "*.onnx", "*tflite*"],
            local_dir=None,
        )
        p = Path(path)
        total = sum(f.stat().st_size for f in p.rglob("*") if f.is_file())
        rec.update({"ok": True, "local": str(p), "bytes": total,
                    "seconds": round(time.time() - started, 1),
                    "files": sorted(f.name for f in p.iterdir() if f.is_file())})
    except Exception as exc:  # noqa: BLE001
        rec.update({"ok": False,
                    "error": f"{type(exc).__name__}: {exc}"[:600],
                    "seconds": round(time.time() - started, 1)})
    results[repo] = rec
    with (OUT / "downloads.json").open("w", encoding="utf8") as sink:
        sink.write(json.dumps(results, indent=2, ensure_ascii=False) + "\n")
    print("done", repo, rec.get("ok"), rec.get("bytes"), flush=True)
print("ALL DONE")
sys.exit(0)
