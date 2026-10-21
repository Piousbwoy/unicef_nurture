#!/usr/bin/env bash
set -e
cd /c/Users/Alhaji_stunner/Videos/unicef
for repo in asr-africa/wav2vec2-xls-r-akan-20-hours KhayaAI/w2v-bert-dga; do
  name=$(echo "$repo" | tr '/' '__')
  echo "=== $name $(date +%T)"
  python -c "
import sys
from huggingface_hub import snapshot_download
snapshot_download('$repo', cache_dir='tool/asr_eval/data/hf',
  allow_patterns=['model.safetensors','config.json','preprocessor_config.json',
                  'vocab.json','added_tokens.json','special_tokens_map.json','tokenizer_config.json'])
print('done $repo')
"
done
echo "ALL_DOWNLOADS_COMPLETE"
