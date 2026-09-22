#!/usr/bin/env python3
"""Export complete MarianMT logits for the app-owned native/WASM runners.

Uses torch.onnx.export directly (no optimum dependency).
Produces: encoder_model.onnx, decoder_model.onnx, tokenizer files.

Usage:
    python tool/export_marian_onnx.py
"""
import argparse
import os
import json
import hashlib
from pathlib import Path

os.environ["TOKENIZERS_PARALLELISM"] = "false"

REPO_ROOT = Path(__file__).resolve().parent.parent
ASSETS = REPO_ROOT / "build" / "marian_reference"
REVISIONS = {
    "hausa": ("Helsinki-NLP/opus-mt-en-ha", "9736e603aa1c79372d62b3a9d96029d0b51f7466", "a5937358c5c405faf5d6fa8a2a542bc0cad12ace"),
    "twi": ("Helsinki-NLP/opus-mt-en-tw", "d75a505a96de52043b9d57d19b4992564769d6dd", "d79d90e1161397ca820000ce52caeaea613679fd"),
}

import torch
torch.set_grad_enabled(False)
from transformers import MarianTokenizer, MarianMTModel, MarianConfig, GenerationConfig
from marian_validation import write_fixtures, validate_export, write_manifest
from huggingface_hub import hf_hub_download

def export_marian(model_id: str, output_dir: Path, revision: str, weights_revision: str,
                  *, fixtures_only=False, allow_download=False):
    print(f"\n{'='*60}")
    print(f"  Model:  {model_id}")
    print(f"  Output: {output_dir}")
    print(f"{'='*60}")
    
    output_dir.mkdir(parents=True, exist_ok=True)
    
    print("[1/5] Loading tokenizer...")
    tok = MarianTokenizer.from_pretrained(model_id, revision=revision,
                                         local_files_only=not allow_download)
    tok.save_pretrained(output_dir)
    write_fixtures(tok, output_dir)
    if fixtures_only:
        return
    
    print("[2/5] Loading model...")
    config_path = hf_hub_download(model_id, 'config.json', revision=revision,
                                  local_files_only=not allow_download)
    raw_config = json.loads(Path(config_path).read_text(encoding='utf-8'))
    config = MarianConfig.from_dict(raw_config)
    # Transformers 5 removes legacy generation fields from MarianConfig.
    # Preserve the pinned raw generation policy, especially PAD suppression.
    generation = GenerationConfig.from_dict(raw_config)
    weights = Path(hf_hub_download(model_id, "model.safetensors", revision=weights_revision,
                                   local_files_only=not allow_download))
    model = MarianMTModel.from_pretrained(str(weights.parent),
        config=config, use_safetensors=True, local_files_only=True,
        generation_config=generation,
        attn_implementation="eager")
    model.eval()
    model.config.use_cache = False
    
    print("[3/5] Exporting encoder to ONNX...")
    sample_text = "The child is healthy."
    inputs = tok(sample_text, return_tensors="pt", padding=False)
    input_ids = inputs["input_ids"]
    attention_mask = inputs["attention_mask"]
    
    # Export encoder
    encoder = model.get_encoder()
    encoder_path = output_dir / "encoder_model.onnx"
    torch.onnx.export(
        encoder,
        (input_ids, attention_mask),
        str(encoder_path),
        input_names=["input_ids", "attention_mask"],
        output_names=["last_hidden_state"],
        dynamic_axes={
            "input_ids": {0: "batch", 1: "seq"},
            "attention_mask": {0: "batch", 1: "seq"},
            "last_hidden_state": {0: "batch", 1: "seq"},
        },
        opset_version=14,
        dynamo=False,
    )
    print(f"  Saved: {encoder_path.name} ({encoder_path.stat().st_size/1024/1024:.1f} MB)")
    
    print("[4/5] Exporting decoder to ONNX...")
    # For the decoder, we need a dummy encoder output + decoder input.
    encoder_output = encoder(input_ids, attention_mask)
    hidden_states = encoder_output.last_hidden_state
    
    # Decoder input: shifted labels (teacher forcing style for export).
    decoder_start = model.config.decoder_start_token_id
    if decoder_start is None:
        decoder_start = model.config.pad_token_id
    # Trace a multi-token prefix so the causal mask remains in the graph.
    decoder_input_ids = torch.tensor([[decoder_start, 3, 4]], dtype=torch.long)
    
    decoder_path = output_dir / "decoder_model.onnx"
    
    # We need a wrapper since model.decoder takes different inputs.
    class DecoderWrapper(torch.nn.Module):
        def __init__(self, model):
            super().__init__()
            self.decoder = model.model.decoder
            self.lm_head = model.lm_head
            self.register_buffer("final_logits_bias", model.final_logits_bias)
        def forward(self, decoder_input_ids, encoder_hidden_states, attention_mask):
            # Cross-attention mask for encoder output.
            enc_mask = attention_mask
            out = self.decoder(
                input_ids=decoder_input_ids,
                encoder_hidden_states=encoder_hidden_states,
                encoder_attention_mask=enc_mask,
                return_dict=False,
                use_cache=False,
            )
            return self.lm_head(out[0]) + self.final_logits_bias
    
    # In transformers 5.x, decoder is at model.model.decoder.
    decoder_wrapper = DecoderWrapper(model)
    decoder_wrapper.eval()
    
    torch.onnx.export(
        decoder_wrapper,
        (decoder_input_ids, hidden_states, attention_mask),
        str(decoder_path),
        input_names=["decoder_input_ids", "encoder_hidden_states", "encoder_attention_mask"],
        output_names=["logits"],
        dynamic_axes={
            "decoder_input_ids": {0: "batch", 1: "dec_seq"},
            "encoder_hidden_states": {0: "batch", 1: "enc_seq"},
            "encoder_attention_mask": {0: "batch", 1: "enc_seq"},
            "logits": {0: "batch", 1: "dec_seq"},
        },
        opset_version=14,
        dynamo=False,
    )
    print(f"  Saved: {decoder_path.name} ({decoder_path.stat().st_size/1024/1024:.1f} MB)")
    
    print("[5/5] Saving generation config...")
    gen_cfg = model.generation_config
    gen_cfg_dict = gen_cfg.to_dict()
    # A reproducible bounded greedy baseline; original settings remain recorded.
    (output_dir / "upstream_generation_config.json").write_text(
        json.dumps(gen_cfg_dict, indent=2) + "\n", encoding="utf-8")
    gen_cfg_dict.update(num_beams=1, do_sample=False, max_length=128)
    # Remove non-serializable items.
    clean = {}
    for k, v in gen_cfg_dict.items():
        try:
            json.dumps(v)
            clean[k] = v
        except (TypeError, ValueError):
            pass
    
    with open(output_dir / "generation_config.json", "w") as f:
        json.dump(clean, f, indent=2)
    
    # Also save model config.
    with open(output_dir / "config.json", "w") as f:
        json.dump(model.config.to_dict(), f, indent=2, default=str)
    
    provenance = {"source": model_id, "revision": revision,
        "weights_revision": weights_revision, "weights_sha256": hashlib.sha256(weights.read_bytes()).hexdigest(),
        "license": "Apache-2.0",
        "torch": torch.__version__, "contract": "marian-v1"}
    (output_dir / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")
    validate_export(model, tok, output_dir)
    write_manifest(output_dir, provenance)
    total_size = sum(f.stat().st_size for f in output_dir.iterdir() if f.is_file()) / 1024 / 1024
    print(f"\n  DONE. Total: {total_size:.1f} MB")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("language", choices=["hausa", "twi", "all"], default="all", nargs="?")
    parser.add_argument("--fixtures-only", action="store_true")
    parser.add_argument("--allow-download", action="store_true")
    args = parser.parse_args()
    for name in REVISIONS if args.language == "all" else [args.language]:
        model_id, revision, weights_revision = REVISIONS[name]
        export_marian(model_id, ASSETS / f"translation_{name}", revision, weights_revision,
                      fixtures_only=args.fixtures_only, allow_download=args.allow_download)
    print("Reference artifacts exported under build/. Activation requires parity and runtime validation.")


if __name__ == "__main__":
    main()
