#!/usr/bin/env python3
"""Export MarianMT models to ONNX for onnx_translation Flutter package.

Uses torch.onnx.export directly (no optimum dependency).
Produces: encoder_model.onnx, decoder_model.onnx, tokenizer files.

Usage:
    python tool/export_marian_onnx.py
"""
import sys, os, json
from pathlib import Path

os.environ["TOKENIZERS_PARALLELISM"] = "false"

REPO_ROOT = Path(__file__).resolve().parent.parent
ASSETS = REPO_ROOT / "assets" / "models"

import torch
torch.set_grad_enabled(False)
from transformers import MarianTokenizer, MarianMTModel

def export_marian(model_id: str, output_dir: Path):
    print(f"\n{'='*60}")
    print(f"  Model:  {model_id}")
    print(f"  Output: {output_dir}")
    print(f"{'='*60}")
    
    output_dir.mkdir(parents=True, exist_ok=True)
    
    print("[1/5] Loading tokenizer...")
    tok = MarianTokenizer.from_pretrained(model_id)
    tok.save_pretrained(output_dir)
    
    print("[2/5] Loading model...")
    model = MarianMTModel.from_pretrained(model_id)
    model.eval()
    
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
    decoder_start = model.config.decoder_start_token_id or model.config.pad_token_id
    decoder_input_ids = torch.tensor([[decoder_start]], dtype=torch.long)
    
    decoder_path = output_dir / "decoder_model.onnx"
    
    # We need a wrapper since model.decoder takes different inputs.
    class DecoderWrapper(torch.nn.Module):
        def __init__(self, decoder, config):
            super().__init__()
            self.decoder = decoder
            self.config = config
        def forward(self, decoder_input_ids, encoder_hidden_states, attention_mask):
            # Cross-attention mask for encoder output.
            enc_mask = attention_mask
            out = self.decoder(
                input_ids=decoder_input_ids,
                encoder_hidden_states=encoder_hidden_states,
                encoder_attention_mask=enc_mask,
                return_dict=False,
            )
            return out[0]  # last hidden state
    
    # In transformers 5.x, decoder is at model.model.decoder.
    decoder_module = getattr(model, 'decoder', None) or model.model.decoder
    decoder_wrapper = DecoderWrapper(decoder_module, model.config)
    decoder_wrapper.eval()
    
    torch.onnx.export(
        decoder_wrapper,
        (decoder_input_ids, hidden_states, attention_mask),
        str(decoder_path),
        input_names=["decoder_input_ids", "encoder_hidden_states", "encoder_attention_mask"],
        output_names=["decoder_hidden_states"],
        dynamic_axes={
            "decoder_input_ids": {0: "batch", 1: "dec_seq"},
            "encoder_hidden_states": {0: "batch", 1: "enc_seq"},
            "encoder_attention_mask": {0: "batch", 1: "enc_seq"},
            "decoder_hidden_states": {0: "batch", 1: "dec_seq"},
        },
        opset_version=14,
        dynamo=False,
    )
    print(f"  Saved: {decoder_path.name} ({decoder_path.stat().st_size/1024/1024:.1f} MB)")
    
    print("[5/5] Saving generation config...")
    gen_cfg = model.generation_config
    gen_cfg_dict = gen_cfg.to_diff_dict()
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
    
    total_size = sum(f.stat().st_size for f in output_dir.iterdir() if f.is_file()) / 1024 / 1024
    print(f"\n  DONE. Total: {total_size:.1f} MB")


def main():
    models = {
        "hausa": ("Helsinki-NLP/opus-mt-en-ha", ASSETS / "translation_hausa"),
        "twi": ("Helsinki-NLP/opus-mt-en-tw", ASSETS / "translation_twi"),
    }
    
    target = sys.argv[1].lower() if len(sys.argv) > 1 else "all"
    
    if target == "all":
        for name, (model_id, out) in models.items():
            export_marian(model_id, out)
    elif target in models:
        model_id, out = models[target]
        export_marian(model_id, out)
    else:
        print(f"Usage: python {sys.argv[0]} [hausa|twi|all]")
        sys.exit(1)
    
    print("\n" + "="*60)
    print("  Models exported! Run: flutter pub get")
    print("  App will auto-load on native platforms.")
    print("="*60)


if __name__ == "__main__":
    main()
