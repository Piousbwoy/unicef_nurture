import json, sys
from pathlib import Path
import numpy as np
sys.path.insert(0, "tool/asr_export")
from make_frontend_fixture import SR, labels_of, probe_geometry, recipe, write_pack
from transformers import SeamlessM4TFeatureExtractor
cache = "tool/asr_eval/data/hf"
ex = SeamlessM4TFeatureExtractor.from_pretrained("KhayaAI/w2v-bert-dga", cache_dir=cache, local_files_only=True)
model_config = json.loads(Path(ex.model_input_names and list(Path(cache).glob("models--KhayaAI--w2v-bert-dga/snapshots/*/config.json"))[0]).read_text(encoding="utf8"))
fl, hop = probe_geometry(ex)
labels, blank = labels_of("KhayaAI/w2v-bert-dga", cache, model_config)
write_pack(Path("test/fixtures/asr/pack"), ex, "dag", "Dagbani", fl, hop, 49.1667, labels, blank, 400)
r = recipe(ex)
Path("tool/asr_export/_recipe.json").write_text(json.dumps({**r, "labels": labels, "blank": blank}, indent=1), encoding="utf8")
print("ok", fl, hop, len(labels), blank)
