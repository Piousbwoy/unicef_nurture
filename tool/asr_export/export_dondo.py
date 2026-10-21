"""Export DONDO (KhayaAI/w2v-bert-dga) into the app's `asr-v1` pack shape.

The graph is `input_features [1, frames, 160] + attention_mask [1, frames]` ->
`output [1, frames, labels]`. The feature tables (`mel_filters.json`,
`window.json`, `frontend.json`) are the ones `make_frontend_fixture.py` produced
from DONDO's own SeamlessM4T processor, and `test/asr_frontend_fixture_test.dart`
already proves the Dart frontend reproduces that processor to float32 noise — so
the only thing left to do here is move the weights.

  python tool/asr_export/export_dondo.py                # fp32, ~2.4 GB
  python tool/asr_export/export_dondo.py --quantize     # + int8 weights

Output goes to `data/` (gitignored). Nothing here is a shipping decision: a
600 M-parameter recogniser is a tablet or demo-machine model, and this script's
job is to prove the app can hear it, not to pretend it fits a $60 phone.
"""
import argparse
import json
import shutil
import sys
from pathlib import Path

import torch

REPO_ROOT = Path(__file__).resolve().parents[2]
TABLES = REPO_ROOT / "test/fixtures/asr/pack"
# The fixture's own geometry: 1.2 s of audio at DONDO's frame rate.
FRAMES, DIM = 59, 160


class Graph(torch.nn.Module):
    def __init__(self, inner):
        super().__init__()
        self.inner = inner

    def forward(self, input_features, attention_mask):
        return self.inner(
            input_features=input_features, attention_mask=attention_mask
        ).logits


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default="KhayaAI/w2v-bert-dga")
    ap.add_argument("--out", default=str(REPO_ROOT / "data/asr_dev/dagbani_dondo"))
    ap.add_argument("--quantize", action="store_true")
    ap.add_argument("--language", default="dag")
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
        blank = labels.index("<pad>") if "<pad>" in labels else 0

    features = torch.zeros((1, FRAMES, DIM), dtype=torch.float32)
    mask = torch.ones((1, FRAMES), dtype=torch.int64)
    with torch.no_grad():
        logits = graph(features, mask)
    print(f"reference run: {tuple(logits.shape)} -> {len(labels)} labels, blank {blank}")

    onnx = out / "model.onnx"
    torch.onnx.export(
        graph,
        (features, mask),
        str(onnx),
        # torch 2.13 defaults to dynamo, which dies on this architecture's
        # relative-position matmul with a negative-discriminant sqrt assert.
        dynamo=False,
        input_names=["input_features", "attention_mask"],
        output_names=["output"],
        dynamic_axes={
            "input_features": {1: "frames"},
            "attention_mask": {1: "frames"},
            "output": {1: "frames"},
        },
        opset_version=17,
    )
    print(f"fp32: {onnx.stat().st_size / 1e6:.0f} MB")

    contract = json.loads((TABLES / "frontend.json").read_text(encoding="utf8"))
    contract["language"] = {"code": args.language}
    contract["model"] = {
        **contract["model"],
        "inputs": ["input_features", "attention_mask"],
        "labels": labels,
        "num_labels": len(labels),
        "blank_index": int(blank),
    }
    (out / "model.onnx.json").write_text(json.dumps(contract, indent=1), encoding="utf8")
    (out / "frontend.json").write_text(json.dumps(contract, indent=1), encoding="utf8")
    shutil.copy(TABLES / "mel_filters.json", out / "mel_filters.json")
    shutil.copy(TABLES / "window.json", out / "window.json")

    if args.quantize:
        from onnxruntime.quantization import QuantType, quantize_dynamic

        quantized = out / "model.int8.onnx"
        quantize_dynamic(
            str(onnx), str(quantized), weight_type=QuantType.QInt8, op_types_to_quantize=["MatMul"]
        )
        print(f"int8: {quantized.stat().st_size / 1e6:.0f} MB")

    print(
        f"\nwrote {out}\nNext: flutter test test/asr_native_pack_test.dart "
        "--dart-define=RUN_NATIVE_VOICE=true (point it at this folder)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
