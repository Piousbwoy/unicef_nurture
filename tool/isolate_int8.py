#!/usr/bin/env python3
"""Isolate where the int8 quantized path diverges from fp32.

Compares encoder output, decoder step-0 hidden states, and step-0 logits
between the fp32 and int8 sessions for a well-formed sentence.
"""
import json
import sys
from pathlib import Path

import numpy as np
import onnxruntime as ort
import sentencepiece as spm

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets" / "models"
Q = ROOT / "build" / "quantized"

SENT = "Do not give the child any other medicine."


def enc_ids(src, text):
    vocab = json.load(open(src / "vocab.json"))
    sp = spm.SentencePieceProcessor(model_file=str(src / "source.spm"))
    pieces = sp.encode(text, out_type=str)
    return [vocab.get(p, 1) for p in pieces] + [0]


def load(tag, pair):
    base = ASSETS / pair if tag == "fp32" else Q / pair
    proj = (Q / pair / "_proj_fp32.onnx") if tag == "fp32" else (Q / pair / "proj_model.onnx")
    return {
        "enc": ort.InferenceSession(str(base / "encoder_model.onnx")),
        "dec": ort.InferenceSession(str(base / "decoder_model.onnx")),
        "proj": ort.InferenceSession(str(proj)),
    }


def main():
    pair = sys.argv[1] if len(sys.argv) > 1 else "translation_hausa"
    src = ASSETS / pair
    cfg = json.load(open(src / "config.json"))
    pad = int(cfg["pad_token_id"])

    fp32 = load("fp32", pair)
    int8 = load("int8", pair)

    ids = [enc_ids(src, SENT)]
    mask = [[1] * len(ids[0])]
    feed = {
        "input_ids": np.array(ids, np.int64),
        "attention_mask": np.array(mask, np.int64),
    }
    enc_fp = fp32["enc"].run(None, feed)[0]
    enc_i8 = int8["enc"].run(None, feed)[0]
    d = np.abs(enc_fp - enc_i8)
    print(f"encoder out: fp32 norm={np.linalg.norm(enc_fp):.3f} int8 norm={np.linalg.norm(enc_i8):.3f} "
          f"max abs diff={d.max():.5f} mean abs diff={d.mean():.6f}")

    def step0(dec, enc):
        out = dec.run(None, {
            "decoder_input_ids": np.array([[pad]], np.int64),
            "encoder_hidden_states": enc,
            "encoder_attention_mask": np.array(mask, np.int64),
        })[0]
        return out

    dec_fp = step0(fp32["dec"], enc_fp)
    dec_i8_ownenc = step0(int8["dec"], enc_i8)
    dec_i8_fpenc = step0(int8["dec"], enc_fp)
    print(f"decoder step0 (own enc): fp32 norm={np.linalg.norm(dec_fp):.3f} int8 norm={np.linalg.norm(dec_i8_ownenc):.3f} "
          f"max abs diff={np.abs(dec_fp - dec_i8_ownenc).max():.5f}")
    print(f"decoder step0 (fp32 enc): int8 norm={np.linalg.norm(dec_i8_fpenc):.3f} "
          f"max abs diff={np.abs(dec_fp - dec_i8_fpenc).max():.5f}")

    def logits(proj, dec_out):
        return proj.run(None, {"hidden_states": dec_out})[0][0, -1]

    l_fp = logits(fp32["proj"], dec_fp)
    l_i8_own = logits(fp32["proj"], dec_i8_ownenc)
    l_i8_fpenc = logits(fp32["proj"], dec_i8_fpenc)
    l_i8_proj = logits(int8["proj"], dec_fp)
    print(f"step0 argmax: fp32={int(np.argmax(l_fp))} | int8 dec+fp32 proj (own enc)={int(np.argmax(l_i8_own))} "
          f"(fp enc)={int(np.argmax(l_i8_fpenc))} | fp32 dec+int8 proj={int(np.argmax(l_i8_proj))}")
    top = np.argsort(l_fp)[-5:][::-1]
    print(f"fp32 top5 ids: {top.tolist()}")

    rev = {v: k for k, v in json.load(open(src / "vocab.json")).items()}
    for name, arr in [
        ("fp32 proj on fp32 dec", l_fp),
        ("fp32 proj on int8 dec (own enc)", l_i8_own),
        ("fp32 proj on int8 dec (fp enc)", l_i8_fpenc),
        ("int8 proj on fp32 dec", l_i8_proj),
    ]:
        t = np.argsort(arr)[-3:][::-1]
        print(f"  {name}: top3 {[(rev[int(i)], round(float(arr[i]), 2)) for i in t]}")


if __name__ == "__main__":
    main()
