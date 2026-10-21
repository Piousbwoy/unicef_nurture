"""Export the measured Akan/Twi recogniser into the app's `asr-v1` pack shape.

`asr-africa/wav2vec2-xls-r-akan-20-hours` is the model that cleared the project's
own accuracy bar on held-out speech (median CER 0.162, RTF 0.69 on four CPU
threads; see `tool/track_b/ASR_OPTIONS.md`). Its graph is
`input_values [1, samples] + attention_mask [1, samples]` -> `output
[1, frames, labels]`, and unlike DONDO it needs no mel frontend in the app: the
feature extractor is `do_normalize` over the raw waveform, and the seven learned
convolution layers do the rest. So this script moves weights and writes a
contract, and there are no filter tables to carry.

  python tool/asr_export/export_akan.py               # fp32
  python tool/asr_export/export_akan.py --quantize    # + int8 weights

Output goes to `data/` (gitignored). A 300 M-parameter recogniser is not a $60
phone model yet; the point of the pack is to measure what the app's own engine
gets from it, in size, latency and accuracy.
"""
import argparse
import json
import sys
from pathlib import Path

import torch

REPO_ROOT = Path(__file__).resolve().parents[2]
# One second of audio: the conv frontend halves its input twice, so this is
# enough to prove the dynamic axis without pretending to be a take.
SAMPLES = 16000


class Graph(torch.nn.Module):
    def __init__(self, inner):
        super().__init__()
        self.inner = inner

    def forward(self, input_values, attention_mask):
        return self.inner(
            input_values=input_values, attention_mask=attention_mask
        ).logits


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default="asr-africa/wav2vec2-xls-r-akan-20-hours")
    ap.add_argument("--out", default=str(REPO_ROOT / "data/asr_dev/twi_akan"))
    ap.add_argument("--quantize", action="store_true")
    ap.add_argument("--language", default="twi")
    args = ap.parse_args()

    from transformers import AutoModelForCTC, AutoTokenizer

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    torch.set_num_threads(4)
    model = AutoModelForCTC.from_pretrained(args.repo).to("cpu").eval()
    tokenizer = AutoTokenizer.from_pretrained(args.repo)
    graph = Graph(model).eval()

    vocab = dict(tokenizer.get_vocab())
    labels = [None] * len(vocab)
    for token, index in vocab.items():
        labels[index] = token
    if any(label is None for label in labels):
        raise SystemExit("tokenizer vocabulary has gaps; cannot pin a label list")
    blank = tokenizer.pad_token_id
    if blank is None:
        raise SystemExit("no pad token: the CTC blank would be a guess")

    values = torch.linspace(-1.0, 1.0, SAMPLES, dtype=torch.float32).view(1, -1)
    mask = torch.ones((1, SAMPLES), dtype=torch.int64)
    with torch.no_grad():
        logits = graph(values, mask)
    print(f"reference run: {tuple(logits.shape)} -> {len(labels)} labels, blank {blank}")

    onnx = out / "model.onnx"
    torch.onnx.export(
        graph,
        (values, mask),
        str(onnx),
        # torch 2.13 defaults to dynamo, which cannot trace the weight_norm'd
        # convolutional feature extractor of this architecture.
        dynamo=False,
        input_names=["input_values", "attention_mask"],
        output_names=["output"],
        dynamic_axes={
            "input_values": {1: "samples"},
            "attention_mask": {1: "samples"},
            "output": {1: "frames"},
        },
        opset_version=17,
    )
    print(f"fp32: {onnx.stat().st_size / 1e6:.0f} MB")

    contract = {
        "language": {"code": args.language},
        "audio": {
            "sample_rate": 16000,
            # The app layers the waveform and the model builds its own
            # spectrogram; `1` is one value per sample, not a mel bank width.
            "features": "waveform",
            "input_dim": 1,
            # transformers' zero_mean_unit_var_norm, which uses the population
            # variance and this epsilon.
            "normalize_epsilon": 1e-7,
            "frames_per_second": 16000,
            # Four seconds at 16 kHz: the app's own capture ceiling.
            "max_frames": 64000,
        },
        "model": {
            "inputs": ["input_values", "attention_mask"],
            "labels": labels,
            "num_labels": len(labels),
            "blank_index": int(blank),
        },
    }
    text = json.dumps(contract, indent=1)
    (out / "frontend.json").write_text(text, encoding="utf8")
    (out / "model.onnx.json").write_text(text, encoding="utf8")

    if args.quantize:
        from onnxruntime.quantization import QuantType, quantize_dynamic

        quantized = out / "model.int8.onnx"
        quantize_dynamic(
            str(onnx),
            str(quantized),
            weight_type=QuantType.QInt8,
            op_types_to_quantize=["MatMul"],
        )
        print(f"int8: {quantized.stat().st_size / 1e6:.0f} MB")

    print(
        f"\nwrote {out}\nNext: flutter test test/asr_native_pack_test.dart "
        "--dart-define=RUN_NATIVE_VOICE=true (point ASR_PACK at this folder)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
