# Hausa neural translation model (en → ha)

MarianMT encoder/decoder pair used by the offline caregiver voice pipeline.

- **Source weights:** `Helsinki-NLP/opus-mt-en-ha` — see `provenance.json` for the
  pinned revision and the `weights_sha256` the export was built from. The license
  recorded there is Apache-2.0; confirm it against the upstream model card before
  redistributing this app.
- **Contract:** `marian-v1` (schema 1), validated in `model_manifest.json`.

## Files

The runtime loads exactly the eleven files listed in `model_manifest.json`, and
verifies each one's sha256 before use:

| File | Role |
| --- | --- |
| `encoder_model.onnx` | source encoder → `encoder_hidden_states` |
| `decoder_model.onnx` | target decoder → `decoder_hidden_states` (512-d, **not** logits) |
| `proj_model.onnx` | output layer: `hidden @ Eᵀ + final_logits_bias` → `logits` |
| `source.spm` / `target.spm` / `vocab.json` | SentencePiece tokenizer |
| `config.json` / `tokenizer_config.json` / `generation_config.json` | architecture and decoding settings |
| `tokenizer_fixtures.json` | tokenizer parity fixtures, checked at load |
| `generation_fixtures.json` | greedy-decode parity fixtures, checked at load |
| `provenance.json` | upstream revision and weight digest |

The decoder deliberately stops at `decoder_hidden_states`. Marian ties the output
projection to the decoder embedding, and ONNX export would otherwise inline that
58,089 × 512 matrix a second time. Splitting it into `proj_model.onnx` is what
keeps every file under GitHub's 100 MB limit.

## Quantization

Weight-only, so activations stay fp32:

- embedding tables: per-token-row **int8** (one scale per vocabulary row)
- MatMul weights: per-output-column **int16**
- dequantization is `Cast` + `Mul`, not `DequantizeLinear` — opset 14 has no int16
  `DequantizeLinear`, and the ONNX Runtime bundled in the app predates it

Rebuild with `python tool/quantize_translation_models.py` then `--package`. The
packaging step refuses to write unless all six fixtures in
`generation_fixtures.json` reproduce the fp32, PyTorch-validated reference in
`build/marian_reference/translation_hausa/` token-for-token.
