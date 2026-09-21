#!/usr/bin/env python3
"""
Download and export ONNX translation models for CareBridge AI.

Usage:
    python tool/export_translation_models.py hausa
    python tool/export_translation_models.py twi
    python tool/export_translation_models.py all

Requirements:
    pip install torch transformers optimum onnx runtime

This script:
  1. Downloads the model from Hugging Face Hub
  2. Exports to ONNX (encoder + decoder graphs)
  3. Saves tokenizer files (vocab.json, tokenizer_config.json, etc.)
  4. Places output in assets/models/translation_<lang>/

Models used:
  - Hausa: qvac/TranslatePsy-AfriNano (Apache 2.0, 17 MB Tiny, Marian/Bergamot)
  - Twi:   Helsinki-NLP/opus-mt-en-tw (CC-BY-4.0, ~80 MB INT8 quantized)
"""

import sys
import shutil
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
ASSETS_BASE = REPO_ROOT / "assets" / "models"

# ─── Model configurations ──────────────────────────────────────────────────────

MODELS = {
    "hausa": {
        "hf_model": "qvac/TranslatePsy-AfriNano",
        "output_dir": ASSETS_BASE / "translation_hausa",
        "lang_token": "##HA",
        "description": "TranslatePsy-AfriNano Tiny (17 MB, Marian/Bergamot)",
    },
    "twi": {
        "hf_model": "Helsinki-NLP/opus-mt-en-tw",
        "output_dir": ASSETS_BASE / "translation_twi",
        "lang_token": None,  # Monodirectional model — no language token needed
        "description": "Helsinki-NLP OPUS-MT English→Twi",
    },
}


def export_model(name: str) -> None:
    """Export a single model to ONNX format."""
    config = MODELS[name]
    model_id = config["hf_model"]
    output_dir = config["output_dir"]

    print(f"\n{'='*60}")
    print(f"  Exporting: {name.upper()}")
    print(f"  Model:     {model_id}")
    print(f"  Info:      {config['description']}")
    print(f"  Output:    {output_dir}")
    print(f"{'='*60}\n")

    try:
        from optimum.onnxruntime import ORTModelForSeq2SeqLM
        from transformers import AutoTokenizer
    except ImportError as e:
        print(f"ERROR: Missing dependency. Run: pip install optimum[exporters] transformers torch")
        print(f"       Details: {e}")
        sys.exit(1)

    # 1. Download and load model
    print("[1/4] Loading model from Hugging Face Hub...")
    try:
        model = ORTModelForSeq2SeqLM.from_pretrained(
            model_id,
            export=True,  # Export to ONNX if not already
        )
    except Exception as e:
        print(f"ERROR: Could not load model '{model_id}': {e}")
        print("Try: pip install --upgrade optimum transformers")
        sys.exit(1)

    # 2. Load tokenizer
    print("[2/4] Loading tokenizer...")
    tokenizer = AutoTokenizer.from_pretrained(model_id)

    # 3. Prepare output directory
    print("[3/4] Saving ONNX model and tokenizer files...")
    output_dir.mkdir(parents=True, exist_ok=True)

    # Save model (creates encoder_model.onnx, decoder_model.onnx, etc.)
    model.save_pretrained(output_dir)

    # Save tokenizer (creates vocab.json, tokenizer_config.json, etc.)
    tokenizer.save_pretrained(output_dir)

    # 4. Verify required files
    print("[4/4] Verifying export...")
    required_files = [
        "encoder_model.onnx",
        "decoder_model.onnx",
        "vocab.json",
        "tokenizer_config.json",
        "generation_config.json",
    ]

    missing = []
    for fname in required_files:
        fpath = output_dir / fname
        if fpath.exists():
            size_mb = fpath.stat().st_size / (1024 * 1024)
            print(f"  ✓ {fname} ({size_mb:.1f} MB)")
        else:
            missing.append(fname)
            print(f"  ✗ {fname} — MISSING")

    # Check for alternative naming (some models use different names)
    alternatives = {
        "encoder_model.onnx": ["encoder.onnx", "model.onnx"],
        "decoder_model.onnx": ["decoder.onnx", "decoder_with_past_model.onnx"],
    }
    for required, alts in alternatives.items():
        if required in missing:
            for alt in alts:
                if (output_dir / alt).exists():
                    print(f"  → Found alternative: {alt} (may need manual rename)")
                    break

    if missing:
        print(f"\nWARNING: {len(missing)} required file(s) missing.")
        print("The onnx_translation package may need these renamed.")
        print(f"Check {output_dir} contents manually.")
    else:
        total_size = sum(
            f.stat().st_size for f in output_dir.iterdir() if f.is_file()
        ) / (1024 * 1024)
        print(f"\n✓ Export complete! Total size: {total_size:.1f} MB")
        print(f"  Run 'flutter build' and the model will be bundled in assets.")

    # Write metadata
    meta_path = output_dir / "MODEL_INFO.txt"
    with open(meta_path, "w") as f:
        f.write(f"Model: {model_id}\n")
        f.write(f"Language: {name.capitalize()}\n")
        f.write(f"Lang token: {config['lang_token'] or 'N/A (monodirectional)'}\n")
        f.write(f"Exported: {__import__('datetime').datetime.now().isoformat()}\n")
        f.write(f"License: See HuggingFace model card\n")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        print(f"Available models: {', '.join(MODELS.keys())}")
        sys.exit(0)

    target = sys.argv[1].lower()

    if target == "all":
        for name in MODELS:
            export_model(name)
    elif target in MODELS:
        export_model(target)
    else:
        print(f"ERROR: Unknown model '{target}'. Available: {', '.join(MODELS.keys())}")
        sys.exit(1)

    print("\n" + "="*60)
    print("  Done! Run 'flutter pub get' to bundle new assets.")
    print("  The app will load models automatically on native platforms.")
    print("="*60)


if __name__ == "__main__":
    main()
