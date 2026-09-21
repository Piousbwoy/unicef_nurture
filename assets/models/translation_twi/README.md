# Twi Neural Translation Model (ONNX)

Place the exported Helsinki-NLP MarianMT model files here:
- encoder_model.onnx
- decoder_model.onnx
- vocab.json
- tokenizer_config.json
- generation_config.json

Run `python tool/export_translation_models.py twi` to download and convert automatically.

Model: Helsinki-NLP/opus-mt-en-tw (CC-BY-4.0) — ~80 MB INT8 quantized.
No language token needed (monodirectional en→tw model).
