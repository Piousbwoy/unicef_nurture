"""Is IanKobby/mms-tts-twi-ghana a faithful copy of the official MMS Twi
weights, or a fine-tune?

The official facebook/mms-tts-twi is gated, so we compare against an
INDEPENDENT third-party conversion (waxal-benchmarking/mms-tts-twi). If the
two safetensors files hash identically, both are straight copies of the
canonical weights. If they differ, at least one is a fine-tune — and the
ASR round-trip decides which one actually speaks Twi.

Also prints the file inventory and config of both repos.

Run:  python tool/twi_weight_compare.py
"""

import hashlib
import os
import sys

os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from huggingface_hub import hf_hub_download, list_repo_files
import json
import urllib.request


def show_repo(repo):
    print(f"\n--- {repo} ---")
    try:
        files = list_repo_files(repo)
        for f in files:
            print(f"    {f}")
    except Exception as e:  # noqa: BLE001
        print(f"    list failed: {e}")
        return
    try:
        raw = urllib.request.urlopen(
            f"https://huggingface.co/{repo}/raw/main/config.json", timeout=30
        ).read()
        cfg = json.loads(raw)
        print(
            f"    config: hidden={cfg.get('hidden_size')} "
            f"layers={cfg.get('speech_encoder_layers')} "
            f"speakers={cfg.get('num_speakers')}"
        )
    except Exception:  # noqa: BLE001
        print("    config: unreadable")


REPOS = ["IanKobby/mms-tts-twi-ghana", "waxal-benchmarking/mms-tts-twi"]

for repo in REPOS:
    show_repo(repo)

print("\nDownloading weight files for hashing...")
paths = {}
for repo in REPOS:
    try:
        p = hf_hub_download(repo, "model.safetensors")
        paths[repo] = p
        print(f"  {repo}: {p}")
    except Exception as e:  # noqa: BLE001
        print(f"  {repo}: download failed: {e}")

if len(paths) == 2:
    print("\nHashing (sha256, ~145 MB each)...")
    hashes = {}
    for repo, p in paths.items():
        h = hashlib.sha256()
        with open(p, "rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b""):
                h.update(chunk)
        hashes[repo] = h.hexdigest()
        print(f"  {repo}\n    {hashes[repo]}")
    if hashes[REPOS[0]] == hashes[REPOS[1]]:
        print("\nVERDICT: IDENTICAL — both are faithful copies of the "
              "canonical weights.")
    else:
        print("\nVERDICT: DIFFERENT — at least one is a fine-tune. The "
              "ASR round-trip decides which speaks real Twi.")
else:
    print("\nCould not obtain both weight files; verdict deferred.")
