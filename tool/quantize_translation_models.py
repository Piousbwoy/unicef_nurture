#!/usr/bin/env python3
"""Shrink the MarianMT translation ONNX models below GitHub's 100 MB file
limit and split the logits projection into a separate proj_model.onnx.

Why this exists: GitHub blocks plain-git files over 100 MB and the account's
LFS quota is exhausted, while the fp32 models are ~200 MB each. The tied
vocab embedding (58k x 512 fp32 = 119 MB) sits in both encoder and decoder
graphs behind Gather ops, so plain dynamic quantization alone does not shrink.

Scheme: weight-only INT8/INT16 with fp32 activations.
  - Embeddings: symmetric per-token-row int8 + Cast/Mul dequant, with the row
    scales looked up by a second Gather on the same indices.
  - MatMul weights: symmetric per-column int16 + Cast/Mul dequant (opset-14
    legal; DequantizeLinear only accepts int16 from opset 21 / ORT 1.16 and
    the app bundles ORT 1.15.1).
  - Activations stay fp32, so every matmul is plain fp32 math against
    slightly-rounded weights (~0.002% error). This deliberately avoids ORT's
    MatMulInteger kernels: the u8s8 activation path miscomputes scattered
    columns on ORT 1.30, and per-tensor activation quantization is too coarse
    for these skewed hidden states (greedy decoding diverges from fp32).
  - proj_model.onnx: the tied embedding as a logits projection MatMul plus the
    trained final_logits_bias (hidden -> vocab), weight-only int16, because the
    Dart runner (lib/core/ml/marian_native_engine.dart) chains
    encoder -> decoder (hidden states) -> proj (logits).

Usage:
    python tool/quantize_translation_models.py            # quantize both pairs
    python tool/quantize_translation_models.py --validate # validate vs fp32
"""

import argparse
import sys
from pathlib import Path

import numpy as np
import onnx
import onnxruntime as ort
from onnx import helper, numpy_helper

REPO_ROOT = Path(__file__).resolve().parent.parent
ASSETS = REPO_ROOT / "assets" / "models"
OUT_ROOT = REPO_ROOT / "build" / "quantized"

PAIRS = ["translation_hausa", "translation_twi"]
MAX_BYTES = 99 * 1024 * 1024  # GitHub hard limit is 100 MB; stay clear of it

SAMPLE_SENTENCES = [
    "The child has a fever and is not eating.",
    "Please give the medicine twice a day after meals.",
    "Wash your hands with soap and clean water.",
    "The baby should drink breast milk.",
    "Come back to the clinic if the child gets worse.",
    "He has been coughing for three days.",
    "Keep the child warm and dry.",
    "The nurse will visit your home tomorrow.",
    "Do not give the child any other medicine.",
    "Thank you for coming today.",
    "The water must be boiled before drinking.",
    "She needs to rest and drink plenty of fluids.",
]


def write_json(path, value):
    import json

    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def find_embed_gather(model, embed_name):
    graph = model.graph
    nodes = [
        n
        for n in graph.node
        if n.op_type == "Gather" and len(n.input) > 0 and n.input[0] == embed_name
    ]
    assert len(nodes) == 1, f"expected exactly one embed Gather for {embed_name}, found {len(nodes)}"
    node = nodes[0]
    other_refs = [
        n for n in graph.node if embed_name in list(n.input) and n != node
    ]
    assert not other_refs, f"{embed_name} referenced by non-Gather node(s): {[n.op_type for n in other_refs]}"
    return node


def patch_embedding(model, embed_name):
    """Replace fp32 embedding with per-row (per-token) int8.

    A single per-column scale spans 57-58k token vectors of very different
    magnitudes and leaves ~0.002 absolute error, which was enough to insert a
    wrong word into a validated Hausa sentence. One scale per token row is the
    same int8 footprint and roughly ten times finer; the row scales are looked
    up with a second tiny Gather on the same indices.
    """
    graph = model.graph
    embed_init = next(t for t in graph.initializer if t.name == embed_name)
    embed = numpy_helper.to_array(embed_init)  # [V, 512]
    vocab, dim = embed.shape
    assert dim == 512, f"unexpected d_model {dim}"

    abs_max = np.max(np.abs(embed), axis=1)  # per token row
    scale = abs_max / 127.0
    scale = np.where(scale == 0, 1e-6, scale).astype(np.float32)
    quant = np.clip(np.round(embed / scale[:, None]), -127, 127).astype(np.int8)
    max_err = float(np.max(np.abs(quant.astype(np.float32) * scale[:, None] - embed)))
    print(f"  embed {embed_name}: {vocab}x{dim} -> per-row int8, max dequant err {max_err:.4f}")

    gather = find_embed_gather(model, embed_name)
    indices = gather.input[1]
    quant_name = f"{embed_name}_int8"
    scale_name = f"{embed_name}_scale"
    graph.initializer.remove(embed_init)
    graph.initializer.extend([
        numpy_helper.from_array(quant, name=quant_name),
        numpy_helper.from_array(scale, name=scale_name),
    ])
    gather.input[0] = quant_name
    consumers = [n for n in graph.node if gather.output[0] in list(n.input)]

    row_scale = f"{gather.output[0]}_row_scale"
    scaled_scale = f"{row_scale}_3d"
    cast_out = f"{gather.output[0]}_cast"
    dequant_out = f"{gather.output[0]}_dequant"
    axes_name = f"{embed_name}_unsqueeze_axis"
    graph.initializer.append(numpy_helper.from_array(np.array([-1], np.int64), name=axes_name))
    index = list(graph.node).index(gather)
    graph.node.insert(index + 1, helper.make_node(
        "Gather", [scale_name, indices], [row_scale],
        name=f"{embed_name}_scale_gather", axis=0))
    # Opset 14 takes Unsqueeze axes as a second input, not an attribute.
    graph.node.insert(index + 2, helper.make_node(
        "Unsqueeze", [row_scale, axes_name], [scaled_scale],
        name=f"{embed_name}_scale_unsqueeze"))
    graph.node.insert(index + 3, helper.make_node(
        "Cast", [gather.output[0]], [cast_out], name=f"{embed_name}_cast",
        to=onnx.TensorProto.FLOAT))
    graph.node.insert(index + 4, helper.make_node(
        "Mul", [cast_out, scaled_scale], [dequant_out], name=f"{embed_name}_dequant"))
    for node in consumers:
        for i, inp in enumerate(node.input):
            if inp == gather.output[0]:
                node.input[i] = dequant_out
    return model


def patch_matmul_weights(model, bits=16):
    """Weight-only quantization: per-column intN weights dequantized with
    Cast + Mul instead of DequantizeLinear.

    Activations stay fp32, so every matmul stays a plain fp32 MatMul on
    dequantized weights. MatMulInteger is never emitted — no dependence on
    ORT's buggy u8s8 kernel or MatMulIntegerToFloat fusion. int16 keeps
    weight rounding ~256x finer than int8: int8 rounding flipped near-tie
    argmaxes and diverged the autoregressive loop (int16 matches fp32).

    DequantizeLinear only accepts int16 from ONNX opset 21 and ORT 1.16,
    while the app bundles ORT 1.15.1 — Cast+Mul is opset-14 legal, exact
    (int16 fits fp32), and identical numerically to a DQ node.
    """
    assert bits in (8, 16)
    limit = (1 << (bits - 1)) - 1
    np_dtype = np.int8 if bits == 8 else np.int16
    graph = model.graph
    init_by_name = {t.name: t for t in graph.initializer}
    patched = 0
    max_err = 0.0
    for node in list(graph.node):
        if node.op_type != "MatMul":
            continue
        w_name = node.input[1]
        init = init_by_name.get(w_name)
        if init is None or init.data_type != onnx.TensorProto.FLOAT:
            continue  # runtime B (e.g. attention QK^T) — leave fp32
        other_users = [
            n for n in graph.node if n is not node and w_name in list(n.input)
        ]
        assert not other_users, f"weight {w_name} also used by {other_users[0].op_type}"
        w = numpy_helper.to_array(init)
        if w.ndim != 2:
            continue
        abs_max = np.max(np.abs(w), axis=0)  # per column
        scale = abs_max / limit
        scale = np.where(scale == 0, 1e-6, scale)
        quant = np.clip(np.round(w / scale), -limit, limit).astype(np_dtype)
        max_err = max(
            max_err,
            float(np.max(np.abs(quant.astype(np.float32) * scale - w))),
        )

        quant_name = f"{w_name}_i{bits}"
        scale_name = f"{w_name}_scale"
        graph.initializer.remove(init)
        graph.initializer.extend(
            [
                numpy_helper.from_array(quant, name=quant_name),
                numpy_helper.from_array(scale.astype(np.float32), name=scale_name),
            ]
        )
        cast_out = f"{w_name}_cast"
        dequant_out = f"{w_name}_deq"
        index = list(graph.node).index(node)
        graph.node.insert(
            index,
            helper.make_node("Cast", [quant_name], [cast_out],
                name=f"{w_name}_cast", to=onnx.TensorProto.FLOAT),
        )
        graph.node.insert(
            index + 1,
            helper.make_node("Mul", [cast_out, scale_name], [dequant_out],
                name=f"{w_name}_deq"),
        )
        node.input[1] = dequant_out
        patched += 1
    print(f"  matmul weights: {patched} quantized (int{bits}), max dequant err {max_err:.4f}")
    return model


def load_final_logits_bias(pair):
    """Marian's output layer is hidden @ E^T + final_logits_bias.

    The bias is trained (absmax ~7.5 hausa, ~9.6 twi) and mostly nonzero, so a
    projection that omits it silently skews every argmax toward high-frequency
    function words and produces repetition loops. Read it from the pinned HF
    snapshot; embeddings in that snapshot are bit-identical to the ONNX export.
    """
    import glob
    import json

    from safetensors import safe_open

    repo = {'translation_hausa': 'opus-mt-en-ha', 'translation_twi': 'opus-mt-en-tw'}[pair]
    revision = json.loads((REPO_ROOT / 'build/marian_reference' / pair / 'provenance.json')
        .read_text(encoding='utf-8'))['weights_revision']
    files = glob.glob(str(Path.home() / '.cache/huggingface/hub' / f'models--Helsinki-NLP--{repo}'
        / 'snapshots' / revision / 'model.safetensors'))
    if not files:
        raise SystemExit(f'missing pinned HF snapshot for {repo} ({revision})')
    with safe_open(files[0], framework='np') as handle:
        return handle.get_tensor('final_logits_bias').astype(np.float32).reshape(-1)


def build_proj_model(embed, vocab, bias, opset=14):
    """Logits projection: hidden [B,S,512] x W[512,V] + bias[V] -> logits [B,S,V]."""
    weight = embed.T.astype(np.float32)  # [512, V]
    assert bias.shape == (vocab,), f'bias shape {bias.shape} != vocab {vocab}'
    inputs = [helper.make_tensor_value_info("hidden_states", onnx.TensorProto.FLOAT, ["batch", "seq", 512])]
    outputs = [helper.make_tensor_value_info("logits", onnx.TensorProto.FLOAT, ["batch", "seq", vocab])]
    initializers = [numpy_helper.from_array(weight, name="proj_weight"),
        numpy_helper.from_array(bias, name="proj_bias")]
    nodes = [
        helper.make_node("MatMul", ["hidden_states", "proj_weight"], ["proj_matmul"], name="proj_matmul"),
        helper.make_node("Add", ["proj_matmul", "proj_bias"], ["logits"], name="proj_bias_add"),
    ]
    graph = helper.make_graph(nodes, "proj", inputs, outputs, initializers)
    model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", opset)])
    model.ir_version = 8
    return model


def quantize_pair(pair):
    src = ASSETS / pair
    out = OUT_ROOT / pair
    out.mkdir(parents=True, exist_ok=True)

    print(f"\n=== {pair} ===")

    enc = onnx.load(str(src / "encoder_model.onnx"))
    dec = onnx.load(str(src / "decoder_model.onnx"))

    print("encoder inputs: ", [(i.name,) for i in enc.graph.input])
    print("decoder inputs: ", [(i.name,) for i in dec.graph.input])

    # Keep the pristine fp32 tied embedding for the projection: building proj
    # from the int8-dequantized copy would quantize the same weights twice.
    tied_embed = numpy_helper.to_array(
        next(t for t in dec.graph.initializer if t.name == "decoder.embed_tokens.weight"))

    enc = patch_embedding(enc, "embed_tokens.weight")
    dec = patch_embedding(dec, "decoder.embed_tokens.weight")
    enc = patch_matmul_weights(enc)
    dec = patch_matmul_weights(dec)

    onnx.checker.check_model(enc, full_check=True)
    onnx.checker.check_model(dec, full_check=True)
    onnx.save_model(enc, str(out / "encoder_model.onnx"))
    onnx.save_model(dec, str(out / "decoder_model.onnx"))

    vocab = tied_embed.shape[0]
    proj = build_proj_model(tied_embed, vocab, load_final_logits_bias(pair))
    proj = patch_matmul_weights(proj)
    onnx.checker.check_model(proj, full_check=True)
    onnx.save_model(proj, str(out / "proj_model.onnx"))

    sizes = {}
    for name in ("encoder_model.onnx", "decoder_model.onnx", "proj_model.onnx"):
        path = out / name
        sizes[name] = path.stat().st_size
        flag = "OK " if path.stat().st_size <= MAX_BYTES else "FAIL"
        print(f"  [{flag}] {name}: {path.stat().st_size / 1e6:.1f} MB")
    if any(s > MAX_BYTES for s in sizes.values()):
        raise SystemExit(f"{pair}: file over {MAX_BYTES / 1e6:.0f} MB limit — needs a different scheme")
    return out


def detok(ids, rev):
    out = []
    for i in ids:
        tok = rev.get(i)
        if tok is None or tok in ("</s>", "<pad>", "<unk>"):
            continue
        if tok.startswith("\u2581"):
            out.append(" " + tok[1:])
        else:
            out.append(tok)
    return "".join(out).strip()


def greedy_decode(sessions, source_ids, gen_cfg, rev):
    """Greedy decode through the real exported sessions.

    Mirrors marian_validation.greedy, which is the gate the fp32 reference was
    certified against. Two rules there are load-bearing and were missing here:
    Marian's ``bad_words_ids`` suppresses the pad token inside the loop (without
    it argmax can settle on pad and truncate the sentence), and ``forced_eos``
    terminates at the length cap. Returns the full id sequence *including* the
    decoder-start token at index 0, matching the fixtures and the Dart engine.
    """
    import json

    cfg = json.load(open(gen_cfg)) if not isinstance(gen_cfg, dict) else gen_cfg
    pad_id = int(cfg["pad_token_id"])
    eos_id = int(cfg["eos_token_id"])
    bad_words = cfg.get("bad_words_ids") or []
    forced_eos = cfg.get("forced_eos_token_id")
    max_length = int(cfg["max_length"])

    ids = np.array([source_ids], np.int64)
    mask = np.ones_like(ids)
    hidden = sessions["encoder"].run(None, {"input_ids": ids, "attention_mask": mask})[0]
    prefix = [pad_id]
    vocab_size = len(rev)
    for step in range(max_length - 1):
        logits = sessions["decoder"].run(
            None,
            {
                "decoder_input_ids": np.array([prefix], np.int64),
                "encoder_hidden_states": hidden,
                "encoder_attention_mask": mask,
            },
        )[0]
        # A split export ends in decoder_hidden_states and needs the projection;
        # a monolithic export already returns vocabulary logits.
        if logits.shape[-1] != vocab_size:
            logits = sessions["proj"].run(None, {"hidden_states": logits})[0]
        scores = logits[0, -1].copy()
        for word in bad_words:
            if len(word) != 1:
                raise ValueError("Unsupported generation suppression rule")
            scores[word[0]] = -np.inf
        token = int(np.argmax(scores))
        if step == max_length - 2 and forced_eos is not None:
            token = int(forced_eos)
        prefix.append(token)
        if token == eos_id:
            return prefix, detok(prefix[1:], rev)
    raise ValueError("Generation did not terminate")


def validate(pair_dir, src_dir, ref_dir):
    vocab = json.load(open(src_dir / "vocab.json"))
    rev = {int(v): k for k, v in vocab.items()}

    def load(base, proj_path):
        return {
            "encoder": ort.InferenceSession(str(base / "encoder_model.onnx"), providers=["CPUExecutionProvider"]),
            "decoder": ort.InferenceSession(str(base / "decoder_model.onnx"), providers=["CPUExecutionProvider"]),
            "proj": ort.InferenceSession(str(proj_path), providers=["CPUExecutionProvider"]),
        }

    fp32 = load(ref_dir, pair_dir / "_proj_fp32.onnx")
    quantized = load(pair_dir, pair_dir / "proj_model.onnx")
    gen_cfg = json.load(open(ref_dir / "generation_config.json"))

    print(f"\n  Validating {ref_dir.name} (pad={gen_cfg['pad_token_id']}, eos={gen_cfg['eos_token_id']})")
    all_match = True
    for fixture in json.load(open(ref_dir / "generation_fixtures.json")):
        ref_ids, ref_text = greedy_decode(fp32, fixture["source_ids"], gen_cfg, rev)
        q_ids, q_text = greedy_decode(quantized, fixture["source_ids"], gen_cfg, rev)
        match = q_ids == fixture["generated_ids"]
        all_match &= match
        print(f"  [{'MATCH ' if match else 'DIFFER'}] {fixture['text']}")
        print(f"          quant: {q_text}")
        if not match:
            print(f"          fp32 : {ref_text}")
    print(f"  => {'ALL GREEDY OUTPUTS MATCH THE PyTORCH-VALIDATED REFERENCE' if all_match else 'MISMATCHES PRESENT — review before shipping'}")
    return all_match


def write_app_package(pair_dir, src_dir, ref_dir):
    """Write the app-consumable package: manifest, fixtures, configs.

    The Dart engine (lib/core/ml/marian_native_engine.dart) loads every file
    listed in model_manifest.json and verifies its sha256, then checks
    generation parity against generation_fixtures.json at load time.
    Tokenizer artifacts are unchanged from fp32, so their fixtures and the
    provenance record come from the fp32 export (ref_dir).
    """
    import hashlib
    import json
    import shutil

    vocab = json.load(open(src_dir / "vocab.json"))
    rev = {int(v): k for k, v in vocab.items()}

    # Tokenizer/SPM artifacts and provenance are identical to the fp32 export.
    for name in ("tokenizer_fixtures.json", "provenance.json", "generation_config.json"):
        shutil.copyfile(ref_dir / name, pair_dir / name)
    for name in ("config.json", "tokenizer_config.json", "source.spm", "target.spm", "vocab.json"):
        shutil.copyfile(src_dir / name, pair_dir / name)

    # Generation fixtures must match the fp32 reference ids exactly; the
    # Dart engine asserts this parity on device at load time.
    ref_fixtures = json.load(open(ref_dir / "generation_fixtures.json"))
    gen_cfg = json.load(open(ref_dir / "generation_config.json"))
    sessions = {
        name: ort.InferenceSession(str(pair_dir / f"{name}_model.onnx"), providers=["CPUExecutionProvider"])
        for name in ("encoder", "decoder", "proj")
    }
    fixtures = []
    for fixture in ref_fixtures:
        generated, text = greedy_decode(sessions, fixture["source_ids"], gen_cfg, rev)
        if generated != fixture["generated_ids"]:
            raise SystemExit(
                f"{pair_dir.name}: quantized greedy differs from the PyTorch-validated "
                f"reference for {fixture['text']!r}\n"
                f"  quantized: {text!r}\n  reference: {fixture['translation']!r}"
            )
        fixtures.append({"text": fixture["text"], "source_ids": fixture["source_ids"],
            "generated_ids": generated, "translation": text})
    if len(fixtures) < 6:
        raise SystemExit(f"{pair_dir.name}: only {len(fixtures)} parity fixtures, refusing to ship")
    write_json(pair_dir / "generation_fixtures.json", fixtures)

    names = ["encoder_model.onnx", "decoder_model.onnx", "proj_model.onnx", "source.spm",
        "target.spm", "vocab.json", "config.json", "generation_config.json",
        "tokenizer_fixtures.json", "generation_fixtures.json", "provenance.json"]
    records = []
    for name in names:
        path = pair_dir / name
        with path.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        records.append({"name": name, "bytes": path.stat().st_size, "sha256": digest})
    provenance = json.load(open(pair_dir / "provenance.json"))
    write_json(pair_dir / "model_manifest.json", {"schema": 1, "contract": "marian-v1",
        "revision": records[1]["sha256"], "source_revision": provenance["revision"],
        "license": provenance["license"], "files": records})
    print(f"  package written: {len(fixtures)} generation fixtures, manifest covers {len(records)} files")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--validate", action="store_true")
    parser.add_argument("--package", action="store_true")
    args = parser.parse_args()

    if args.validate:
        ok = True
        for pair in PAIRS:
            ref = REPO_ROOT / "build" / "marian_reference" / pair
            # fp32 projection for the reference leg, from the same weights the
            # quantized package carries, so the only variable is precision.
            dec = onnx.load(str(ASSETS / pair / "decoder_model.onnx"))
            embed = numpy_helper.to_array(next(t for t in dec.graph.initializer if t.name == "decoder.embed_tokens.weight"))
            (OUT_ROOT / pair).mkdir(parents=True, exist_ok=True)
            onnx.save_model(build_proj_model(embed, embed.shape[0], load_final_logits_bias(pair)),
                str(OUT_ROOT / pair / "_proj_fp32.onnx"))
            ok &= validate(OUT_ROOT / pair, ASSETS / pair, ref)
        sys.exit(0 if ok else 1)

    if args.package:
        for pair in PAIRS:
            write_app_package(OUT_ROOT / pair, ASSETS / pair, REPO_ROOT / "build" / "marian_reference" / pair)
        print("\nApp package written. Copy build/quantized/<pair>/* into assets/models/<pair>/")
        sys.exit(0)

    for pair in PAIRS:
        quantize_pair(pair)
    print("\nAll pairs quantized. Copy build/quantized/<pair>/*.onnx into assets/models/<pair>/")
    print("The Dart runner is lib/core/ml/marian_native_engine.dart.")


if __name__ == "__main__":
    main()
