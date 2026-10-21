"""Throwaway - measurement only, not shippable code.

Step 1 loadability inventory WITHOUT pulling weights: fetch the small json
configs, record sampling rate / vocab / language support, and check that the
architecture class each repo declares actually exists in the installed
transformers build.
"""
import json
import sys
from pathlib import Path

OUT = Path(__file__).resolve().parent / "out"
REPOS = {
    "KhayaAI/w2v-bert-dga": "dag",
    "asr-africa/wav2vec2-xls-r-akan-20-hours": "aka",
    "jdapaah/whisper-small-twi-arxiv": "aka",
    "openai/whisper-tiny": "floor",
}
SMALL = ["config.json", "preprocessor_config.json", "tokenizer_config.json",
         "generation_config.json", "special_tokens_map.json", "added_tokens.json"]

report = {}
for repo in REPOS:
    rec = {"repo": repo}
    try:
        from huggingface_hub import hf_hub_download
        files = {}
        for name in SMALL:
            try:
                p = hf_hub_download(repo_id=repo, filename=name)
                files[name] = json.loads(Path(p).read_text(encoding="utf8"))
            except Exception as exc:  # noqa: BLE001
                files[name] = {"__missing__": f"{type(exc).__name__}"[:60]}
        rec["files"] = {k: sorted(v.keys())[:25] if isinstance(v, dict) else v
                        for k, v in files.items()}
        cfg = files.get("config.json", {})
        pp = files.get("preprocessor_config.json", {})
        rec["model_type"] = cfg.get("model_type")
        rec["architectures"] = cfg.get("architectures")
        rec["vocab_size"] = cfg.get("vocab_size")
        rec["sampling_rate_preprocessor"] = pp.get("sampling_rate")
        rec["feature_extractor_type"] = pp.get("feature_extractor_type")
        rec["processor_class"] = cfg.get("processor_class") or pp.get("processor_class")
        rec["tokenizer_class"] = files.get("tokenizer_config.json", {}).get("tokenizer_class")
        rec["padded_vocab"] = pp.get("pad_token_id")
    except Exception as exc:  # noqa: BLE001
        rec["error"] = f"{type(exc).__name__}: {exc}"[:300]
    report[repo] = rec

# does the installed transformers expose the declared class?
import transformers  # noqa: E402
avail = {}
for cls in ["Wav2Vec2BertForCTC", "Wav2Vec2ForCTC", "WhisperForConditionalGeneration",
            "AutoModelForCTC", "AutoModelForSpeechSeq2Seq", "AutoProcessor",
            "Wav2Vec2BertProcessor", "Data2VecAudioForCTC"]:
    avail[cls] = hasattr(transformers, cls)
report["_transformers_version"] = transformers.__version__
report["_classes_available"] = avail

# whisper language coverage for the two target languages
try:
    from transformers import WhisperTokenizer
    tok = None
    from huggingface_hub import hf_hub_download
    tok = WhisperTokenizer.from_pretrained("openai/whisper-tiny")
    langs = getattr(tok, "lang_code_to_language", None) or getattr(tok, "lang_code_to_symbol", {})
    report["_whisper_tiny_languages"] = {
        "n": len(langs),
        "has_dag": "dag" in langs,
        "has_aka": "aka" in langs,
        "has_twi": "twi" in langs,
        "has_akan_name": any("akan" in str(v).lower() or "twi" in str(v).lower() for v in langs.values()),
    }
except Exception as exc:  # noqa: BLE001
    report["_whisper_tiny_languages_error"] = f"{type(exc).__name__}: {exc}"[:250]

(OUT / "loadability.json").write_text(
    json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf8")
print("wrote loadability.json", flush=True)
sys.exit(0)
