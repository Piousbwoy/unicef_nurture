# Twi Piper TTS Model (On-Device)

Place the Stable-Twi Piper model files here:
- model.onnx (~65 MB, multi-speaker VITS)
- model.onnx.json (config with phoneme_id_map, sample_rate)

Download:
    huggingface-cli download michsethowusu/stable-twi-tts --local-dir assets/tts/twi_piper

Model: stable-twi-tts (CC-BY-NC-4.0) — 12 voices, 327h broadcast, 22 kHz, IPA-driven.
Voice twi-6 (speaker_id 5): best pure-Twi (26.8% phoneme error vs 25.9% floor).
