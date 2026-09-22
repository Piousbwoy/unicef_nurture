"""Reproducible Marian tokenizer/logit/generation gates; no clinical certification."""
import hashlib
import json
from pathlib import Path

import numpy as np
import onnxruntime as ort
import torch
from transformers import GenerationConfig

TEXTS = [
    "The child is healthy.", "Good morning! How are you?", "Wash your hands with soap and clean water.",
    "Please return to the clinic.", "Akosua, Kwame and Amina.", "12 children; 3.5 kg; 2026-04-05.",
    "  Multiple   spaces\tand\nnew lines.  ", "Café, cafe\u0301, ɔ, ɛ, ɓ, ƙ.",
    "“Hello”—she said… It's okay.", "ＡＢＣ ① ﬁ \u00a0space", "🙂 unknown symbol", "", " ",
]
TARGETS = ["Akwaaba, wo ho te sɛn?", "Me da wo ase.", "Sannu, yaya kake?", "12.5 kg", "Ɔba no ho yɛ."]


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def write_fixtures(tokenizer, output):
    encoded = [{"text": text, "ids": tokenizer(text)["input_ids"]} for text in TEXTS]
    decoded = []
    for text in TARGETS:
        ids = tokenizer(text_target=text)["input_ids"]
        decoded.append({"text": text, "ids": ids,
            "decoded": tokenizer.decode(ids, skip_special_tokens=True, clean_up_tokenization_spaces=False)})
    fixture = {"contract": "marian-sentencepiece-v1", "encode": encoded, "decode": decoded,
        "special": {"eos": tokenizer.eos_token_id, "pad": tokenizer.pad_token_id, "unk": tokenizer.unk_token_id}}
    write_json(output / "tokenizer_fixtures.json", fixture)
    test_dir = Path(__file__).resolve().parents[1] / "test" / "fixtures" / "translation"
    test_dir.mkdir(parents=True, exist_ok=True)
    write_json(test_dir / f"{output.name}.json", fixture)


def sessions(base):
    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    options.inter_op_num_threads = 1
    return tuple(ort.InferenceSession(str(base / name), sess_options=options,
        providers=["CPUExecutionProvider"]) for name in ["encoder_model.onnx", "decoder_model.onnx"])


def greedy(encoder, decoder, ids, config, proj_weight=None, logits_bias=None):
    """Bounded greedy decoding of full logits or an explicit split projection."""
    mask = np.ones_like(ids)
    hidden = encoder.run(None, {"input_ids": ids, "attention_mask": mask})[0]
    prefix = [config.decoder_start_token_id]
    for step in range(config.max_length - 1):
        dec_out = decoder.run(None, {"decoder_input_ids": np.array([prefix], dtype=np.int64),
            "encoder_hidden_states": hidden, "encoder_attention_mask": mask})[0]
        scores = (dec_out[0, -1] if proj_weight is None else
                  dec_out[0, -1] @ proj_weight + logits_bias).copy()
        for word in config.bad_words_ids or []:
            if len(word) != 1:
                raise ValueError("Unsupported generation suppression rule")
            scores[word[0]] = -np.inf
        token = int(np.argmax(scores))
        if step == config.max_length - 2 and config.forced_eos_token_id is not None:
            token = config.forced_eos_token_id
        prefix.append(token)
        if token == config.eos_token_id:
            return prefix
    raise ValueError("Generation did not terminate")


def validate_export(model, tokenizer, output):
    encoder, decoder = sessions(output)
    config = GenerationConfig.from_pretrained(output, local_files_only=True)
    # Tied embeddings: the projection weight is the transposed decoder
    # embedding, shared with the encoder (Marian tie_word_embeddings).
    split = decoder.get_outputs()[0].name == 'decoder_hidden_states'
    proj_weight = model.lm_head.weight.detach().numpy().T if split else None
    logits_bias = model.final_logits_bias.detach().numpy().reshape(-1) if split else None
    fixtures = []
    for text in TEXTS[:6]:
        inputs = tokenizer(text, return_tensors="pt")
        ids = inputs["input_ids"].numpy()
        mask = inputs["attention_mask"].numpy()
        hidden = encoder.run(None, {"input_ids": ids, "attention_mask": mask})[0]
        # Check multiple decoder lengths, including the single-token runtime start.
        for prefix in [[config.decoder_start_token_id], [config.decoder_start_token_id, 3, 4, 5]]:
            actual = decoder.run(None, {"decoder_input_ids": np.array([prefix], dtype=np.int64),
                "encoder_hidden_states": hidden, "encoder_attention_mask": mask})[0]
            if split:
                actual = actual @ proj_weight + logits_bias
            expected = model(**inputs, decoder_input_ids=torch.tensor([prefix]), use_cache=False).logits.numpy()
            if actual.shape[-1] != model.config.vocab_size:
                raise ValueError("Decoder does not return vocabulary logits")
            np.testing.assert_allclose(actual, expected, atol=0.002, rtol=0.002)
        reference = model.generate(**inputs, generation_config=config)[0].tolist()
        actual = greedy(encoder, decoder, ids, config, proj_weight, logits_bias)
        if actual != reference:
            raise ValueError("ONNX generation differs from PyTorch reference")
        translation = tokenizer.decode(reference, skip_special_tokens=True, clean_up_tokenization_spaces=False)
        if len(reference) >= config.max_length or not translation.strip():
            raise ValueError('Reference produced empty or length-limited translation; do not activate')
        fixtures.append({"text": text, "source_ids": ids[0].tolist(), "generated_ids": reference,
            "translation": translation})
    write_json(output / "generation_fixtures.json", fixtures)
    print(f"Validated vocabulary logits and exact greedy generation for {len(fixtures)} fixtures")


def write_manifest(output, provenance):
    names = ["encoder_model.onnx", "decoder_model.onnx", "source.spm", "target.spm", "vocab.json",
        "config.json", "generation_config.json", "tokenizer_fixtures.json", "generation_fixtures.json", "provenance.json"]
    records = []
    for name in names:
        path = output / name
        with path.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        records.append({"name": name, "bytes": path.stat().st_size, "sha256": digest})
    write_json(output / "model_manifest.json", {"schema": 1, "contract": "marian-v1",
        "revision": records[1]["sha256"], "source_revision": provenance["revision"],
        "license": provenance["license"], "files": records})
