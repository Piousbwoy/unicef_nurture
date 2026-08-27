"""Forensics for the Hausa/Twi speech-bank mirrors.

The Dagbani mirror (IanKobby/mms-tts-dag-ghana) produces native-sounding
speech; the Hausa/Twi mirrors were chosen by shape alone and the user reports
they sound wrong (English-like, boring). This script gathers objective
evidence, no listening required:

 1. Are the official facebook/mms-tts-* repos gated today?
 2. What do the mirror configs and vocabs look like vs each other — hidden
    size, layers, speaker embeddings, and the exact character sets (a Hausa
    model trained on real Hausa data must carry the hooked letters).
 3. Community signal: download/like counts for every candidate mirror.

Run:  python tool/diag_mms.py
"""

import json
import sys
import urllib.request

# Windows consoles default to cp1252, which cannot print ɛ/ɔ/ɓ/ɗ/ƙ.
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

UA = {"User-Agent": "diag/1.0"}


def get(url, timeout=30):
    req = urllib.request.Request(url, headers=UA)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, b""
    except Exception as e:  # noqa: BLE001 - diagnostic tool
        return None, str(e).encode()


def fetch_json(url):
    status, body = get(url)
    if status != 200:
        return status, None
    try:
        return 200, json.loads(body)
    except json.JSONDecodeError:
        return 200, None


print("=== 1. Official repo accessibility (401/403 = gated) ===")
for repo in [
    "facebook/mms-tts-hau",
    "facebook/mms-tts-twi",
    "facebook/mms-tts-dag",
    "facebook/mms-tts-eng",
]:
    status, _ = get(
        f"https://huggingface.co/{repo}/resolve/main/config.json"
    )
    print(f"  {repo:<28} HTTP {status}")

print("\n=== 2. Mirror configs ===")
mirrors = [
    "IanKobby/mms-tts-dag-ghana",  # known-good reference
    "facebook/mms-tts-hau",  # OFFICIAL — public today
    "laztopaz/mms-tts-hau-custom",  # current Hausa source
    "IanKobby/mms-tts-twi-ghana",  # current Twi source
]
for repo in mirrors:
    status, cfg = fetch_json(
        f"https://huggingface.co/{repo}/resolve/main/config.json"
    )
    if status != 200 or cfg is None:
        print(f"  {repo}: config HTTP {status}")
        continue
    h = cfg.get("model_type", "?")
    hid = cfg.get("hidden_size")
    layers = cfg.get("speech_encoder_layers", cfg.get("num_hidden_layers"))
    speakers = cfg.get("num_speakers")
    print(
        f"  {repo:<32} type={h} hidden={hid} layers={layers} "
        f"speakers={speakers}"
    )

print("\n=== 3. Vocab character sets ===")
def vocab_chars(repo):
    status, body = get(
        f"https://huggingface.co/{repo}/resolve/main/vocab.json"
    )
    if status != 200:
        return status, None
    v = json.loads(body)
    # MMS TTS vocabs are flat char maps; collect the symbols.
    chars = set()
    for k in v.keys() if isinstance(v, dict) else []:
        chars.update(k)
    return status, chars


charsets = {}
for repo in mirrors:
    status, chars = vocab_chars(repo)
    if chars is None:
        print(f"  {repo}: vocab HTTP {status}")
        continue
    charsets[repo] = chars
    print(f"  {repo:<32} {len(chars)} symbols")

if "facebook/mms-tts-hau" in charsets:
    ref = charsets["facebook/mms-tts-hau"]
    for repo, chars in charsets.items():
        if repo == "facebook/mms-tts-hau":
            continue
        missing = sorted(ref - chars)
        extra = sorted(chars - ref)
        print(f"\n  vs OFFICIAL hau reference — {repo}")
        print(f"    missing from this mirror: {''.join(missing) or '—'}")
        print(f"    extra in this mirror:     {''.join(extra) or '—'}")

for repo, chars in charsets.items():
    print(f"\n  symbols of {repo}:")
    print(f"    {''.join(sorted(chars))}")

print("\n=== 4. Hausa/Twi special letters present? ===")
checks = {
    "Hausa hooked:      ɓ ɗ ƙ": "ɓɗƙ",
    "Twi open vowels:   ɛ ɔ": "ɛɔ",
}
for repo, chars in charsets.items():
    for label, letters in checks.items():
        have = all(ch in chars for ch in letters)
        print(f"  {repo:<32} {label}: {'YES' if have else 'NO'}")

print("\n=== 5. Meta direct-download checkpoints (never gated) ===")
for lang in ["hau", "twi", "dag"]:
    status, _ = get(
        f"https://dl.fbaipublicfiles.com/mms/tts/{lang}.pt",
        timeout=20,
    )
    print(f"  {lang}.pt: HTTP {status}")

print("\n=== 6. Community signal: candidate mirrors on the Hub ===")
for query in ["mms-tts-hau", "mms-tts-twi", "mms-tts-dag"]:
    status, models = fetch_json(
        f"https://huggingface.co/api/models?search={query}&limit=20"
    )
    if models is None:
        print(f"  search {query}: HTTP {status}")
        continue
    print(f"  -- {query}")
    for m in models:
        print(
            f"     {m.get('id','?'):<40} dl={m.get('downloads',0):<8} "
            f"likes={m.get('likes',0)} modified={str(m.get('lastModified',''))[:10]}"
        )
