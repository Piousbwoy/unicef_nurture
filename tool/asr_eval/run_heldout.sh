#!/usr/bin/env bash
set -x
python tool/asr_eval/score_ctc.py --repo KhayaAI/w2v-bert-dga \
  --manifest tool/asr_eval/data/dag/manifest.jsonl --answers dagbani \
  --clips 8 --out tool/asr_eval/out/dondo_dag_test.jsonl
python tool/asr_eval/score_ctc.py --repo asr-africa/wav2vec2-xls-r-akan-20-hours \
  --manifest tool/asr_eval/data/aka/manifest.jsonl --answers twi \
  --clips 8 --out tool/asr_eval/out/akan_aka_test.jsonl
echo HELDOUT_COMPLETE
