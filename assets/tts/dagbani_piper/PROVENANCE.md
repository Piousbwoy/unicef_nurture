# Dagbani dynamic voice pack — local candidate, not for publication

| field | value |
| --- | --- |
| Source | https://huggingface.co/ghananlpcommunity/dagbani_tts-2025_v2 |
| Licence | **none declared on the hub** (empty auto-generated model card) |
| Export | `nlp_upgrade/export_vits.py` → ONNX opset 17, dynamic int64 `input`/`input_lengths`, single `output` |
| Quantisation | int8 weight-only dynamic (38.4 MB). Measured RTF 4.3 on 2 CPU threads, versus 0.9 for fp32 — see below |
| Frontend | character orthography with alias `ɔ → ↄ` (the corpus used the U+21C4 glyph for open o) |

## Do not commit or publish these weights

An undeclared licence means all rights are reserved by the uploader. Shipping
this file inside the app needs written permission from GhanaNLP Community, or a
replacement model that carries a licence. Until then this directory stays
untracked and out of `pubspec.yaml`, so the app simply has no Dagbani neural
voice and keeps using the exact bundled recordings.

## Known limits of this checkpoint

* Vocabulary has no `ɣ` or `ʒ`, both used in Dagbani orthography, so sentences
  such as `yɔɣu` are refused by the frontend rather than mispronounced.
* int8 makes it roughly five times too slow for on-device use. The fast path is
  fp32 (114 MB), which must be delivered as a downloaded language pack rather
  than committed, because it exceeds the 100 MB object limit.
