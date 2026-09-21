# Hausa Neural Translation Model (ONNX)

Place the exported TranslatePsy-AfriNano model files here:
- encoder_model.onnx
- decoder_model.onnx
- vocab.json
- tokenizer_config.json
- generation_config.json

Run `python tool/export_translation_models.py hausa` to download and convert automatically.

Model: qvac/TranslatePsy-AfriNano (Apache 2.0) — 17 MB quantized Tiny variant.
Target language token: ##HA
