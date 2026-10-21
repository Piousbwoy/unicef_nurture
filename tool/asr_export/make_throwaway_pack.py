"""Throwaway: a random-init `Wav2Vec2BertForCTC` exported to the `asr-v1` shape.

NOT a recogniser — the weights are initialised, so its transcripts are noise.
It exists to prove the pack plumbing that `test/asr_frontend_fixture_test.dart`
cannot reach: that the Dart engine feeds `input_features` [1, frames, 160] plus
`attention_mask` [1, frames] into a session whose declared inputs match, and
reads back `frames x labels`. Delete it once a real export lands.

Run:  python tool/asr_export/make_throwaway_pack.py
Then: ORT_TEST_LIBRARY=build/voice_compare_deps/Scripts/onnxruntime.dll \
      flutter test test/asr_native_pack_test.dart --dart-define=RUN_NATIVE_VOICE=true
"""
import json
import shutil
import sys
from pathlib import Path

import torch
import torch.nn as nn
from transformers import Wav2Vec2BertConfig, Wav2Vec2BertForCTC

REPO = Path(__file__).resolve().parents[2]
PACK = REPO / "data/asr_dev/dagbani_tiny"
SOURCE = REPO / "test/fixtures/asr/pack"
FRAMES, DIM = 59, 160  # the fixture's own geometry: 1.2 s of audio


def main() -> int:
    # Sized to the contract, not to accuracy: 160 in, 39 labels, 24 layers and
    # 1024 wide are what DONDO will be, and the graph is the same either way.
    config = Wav2Vec2BertConfig(
        vocab_size=39,
        hidden_size=64,
        num_hidden_layers=2,
        num_attention_heads=4,
        intermediate_size=128,
        feature_projection_input_dim=DIM,
        classifier_proj_size=32,
        output_hidden_size=64,
        tdnn_dim=[32, 32, 32, 32, 64],
        tdnn_kernel=[3, 3, 3, 1, 1],
        tdnn_dilation=[1, 2, 3, 1, 1],
        conv_depthwise_kernel_size=5,
        add_adapter=True,
        adapter_kernel_size=3,
        adapter_stride=2,
        num_adapter_layers=1,
        attention_dropout=0.0,
        hidden_dropout=0.0,
        activation_dropout=0.0,
        final_dropout=0.0,
        layerdrop=0.0,
        apply_spec_augment=False,
        mask_time_prob=0.0,
        mask_feature_prob=0.0,
    )
    model = Wav2Vec2BertForCTC(config).eval()

    class Graph(nn.Module):
        def __init__(self, inner):
            super().__init__()
            self.inner = inner

        def forward(self, input_features, attention_mask):
            return self.inner(
                input_features=input_features, attention_mask=attention_mask
            ).logits

    graph = Graph(model).eval()
    features = torch.zeros((1, FRAMES, DIM), dtype=torch.float32)
    mask = torch.ones((1, FRAMES), dtype=torch.int64)
    with torch.no_grad():
        logits = graph(features, mask)
    assert logits.shape[0] == 1 and logits.shape[2] == 39, tuple(logits.shape)

    PACK.mkdir(parents=True, exist_ok=True)
    onnx = PACK / "model.onnx"
    torch.onnx.export(
        graph,
        (features, mask),
        str(onnx),
        # torch 2.13 defaults to dynamo, and dynamo dies on this architecture's
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
    contract = json.loads((SOURCE / "frontend.json").read_text(encoding="utf8"))
    contract["model"]["inputs"] = ["input_features", "attention_mask"]
    (PACK / "frontend.json").write_text(json.dumps(contract, indent=1), encoding="utf8")
    shutil.copy(SOURCE / "mel_filters.json", PACK / "mel_filters.json")
    shutil.copy(SOURCE / "window.json", PACK / "window.json")
    print(
        f"throwaway pack: {onnx.stat().st_size} bytes, "
        f"frames out {logits.shape[1]} of {logits.shape[2]} labels"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
