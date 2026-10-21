"""Throwaway - measurement only, not shippable code.

Inventory candidate ASR repos from the Hub: model type, sampling rate, licence,
files, param count, and whether an AutoModel* class is plausible.
Writes JSON + a text report; never prints non-ASCII to cp1252 stdout.
"""
import json
import sys
from pathlib import Path

from huggingface_hub import HfApi

CANDIDATES = [
    "KhayaAI/w2v-bert-dga",
    "asr-africa/wav2vec2-xls-r-akan-20-hours",
    "jdapaah/whisper-small-twi-arxiv",
    "openai/whisper-tiny",
    "KhayaAI/DONDO-v1_w2v-bert2_conformer_Dagbani",
]

DATASETS_TO_LIST = [
    "google/WaxalNLP",
    "google-research-datasets/WaxalNLP",
]

OUT = Path(__file__).resolve().parent / "out"
OUT.mkdir(parents=True, exist_ok=True)


def main() -> int:
    api = HfApi()
    report = {}
    for repo in CANDIDATES:
        rec = {"repo": repo}
        try:
            info = api.model_info(
                repo,
                files_metadata=True,
            )
            rec["exists"] = True
            rec["id"] = info.id
            rec["pipeline_tag"] = info.pipeline_tag
            rec["library_name"] = info.library_name
            rec["tags"] = list(info.tags or [])
            rec["downloads"] = info.downloads
            # licence usually lives in tags or card_data
            lic = [t for t in (info.tags or []) if t.startswith("license:")]
            rec["licence_tag"] = lic[0].split(":", 1)[1] if lic else None
            rec["model_type_from_config"] = getattr(info, "model_type", None)
            try:
                cd = api.model_info(repo, files_metadata=False)
                rec["card_data_licences"] = [
                    str(getattr(l, "id", l)) for l in (cd.card_data.licenses or [])
                ] if getattr(cd, "card_data", None) and getattr(cd.card_data, "licenses", None) else None
            except Exception as exc:  # noqa: BLE001
                rec["card_data_licences_error"] = f"{type(exc).__name__}: {exc}"[:200]
            files = list(info.siblings or [])
            rec["n_files"] = len(files)
            rec["files"] = [
                {"name": f.rfilename,
                 "size": f.size,
                 "lfs": getattr(getattr(f, "lfs", None), "size", None)}
                for f in files
            ]
            rec["total_bytes"] = sum(
                (f.size or 0) for f in files
            )
            rec["config_present"] = any(f.rfilename == "config.json" for f in files)
            rec["model_index_present"] = any(f.rfilename == "model.safetensors.index.json" for f in files)
            rec["has_remote_code"] = any(f.rfilename.endswith(".py") for f in files)
            rec["safetensors_shards"] = sorted(
                f.rfilename for f in files if f.rfilename.endswith(".safetensors")
            )[:6]
            rec["weight_bytes"] = sum(
                (f.size or 0) for f in files if f.rfilename.endswith((".safetensors", ".bin", ".pt"))
            )
        except Exception as exc:  # noqa: BLE001
            rec["exists"] = False
            rec["error"] = f"{type(exc).__name__}: {exc}"[:400]
        # read config.json for model_type / sampling rate / architectures
        try:
            import urllib.request
            url = f"https://huggingface.co/{repo}/resolve/main/config.json"
            cfg = json.loads(urllib.request.urlopen(url, timeout=60).read().decode("utf8"))
            rec["config"] = {
                k: cfg.get(k)
                for k in (
                    "model_type", "_name_or_path", "architectures", "auto_class",
                    "sampling_rate", "processor_class", "feature_extractor_type",
                    "tokenizer_class", "vocab_size", "hidden_size", "num_hidden_layers",
                    "num_attention_heads", "intermediate_size", "max_position_embeddings",
                    "trust_remote_code", "language", "task",
                )
                if k in cfg
            }
            rec["config_extra_keys"] = sorted(cfg.keys())[:40]
        except Exception as exc:  # noqa: BLE001
            rec["config_error"] = f"{type(exc).__name__}: {exc}"[:250]
        report[repo] = rec

    (OUT / "inventory.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf8"
    )

    dsets = {}
    for repo in DATASETS_TO_LIST:
        rec = {}
        try:
            files = list(api.list_repo_files(repo, repo_type="dataset"))
            meta = {f.rfilename: (f.size or 0)
                    for f in api.list_repo_tree(repo, repo_type="dataset", recursive=True)
                    if hasattr(f, "size")}
            rec["ok"] = True
            rec["n_files"] = len(files)
            rec["files"] = files[:400]
            rec["sizes"] = dict(list(meta.items())[:400])
        except Exception as exc:  # noqa: BLE001
            rec["ok"] = False
            rec["error"] = f"{type(exc).__name__}: {exc}"[:300]
        dsets[repo] = rec
    (OUT / "datasets.json").write_text(
        json.dumps(dsets, indent=2, ensure_ascii=False) + "\n", encoding="utf8"
    )
    print("wrote", OUT / "inventory.json", "and datasets.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
