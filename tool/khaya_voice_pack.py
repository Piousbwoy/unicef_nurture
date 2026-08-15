#!/usr/bin/env python3
"""Khaya AI voice-pack bridge — drafts and synthesizes the Dagbani pack.

CareBridge AI's voice chain (lib/core/audio/voice_service.dart) is
offline-first: a real recorded voice is the gold standard, and no phone TTS
speaks Dagbani. Khaya AI (NLP Ghana) now offers machine translation AND
text-to-speech for Dagbani. This script uses Khaya at *build time* — the app
itself never goes near the network for voice:

  1. `drafts`  — translate every English script line into Dagbani via the
     Khaya translation API, writing `tool/out/khaya_dagbani_drafts.json`.
     These are DRAFTS for native-speaker review. Nothing here flips
     `verified = true`; only a human sign-off does that.

  2. `tts`     — synthesize each line with Khaya's Dagbani TTS and write the
     MP3s to `assets/audio/<id>_dagbani.mp3`, the exact convention
     VoiceService picks up automatically. Files still go through the same
     ear-test protocol as a human recording (see assets/audio/README.txt)
     before the pack status becomes `verified`.

Setup
-----
1. Sign up at https://translation.ghananlp.org and grab a subscription key.
2. `set KHAYA_API_KEY=<subscription-key>`   (PowerShell: `$env:KHAYA_API_KEY="..."`)
3. Verify wiring with one live call:
   `python tool/khaya_voice_pack.py --smoke`
4. Dry-run the full plan: `python tool/khaya_voice_pack.py --dry-run`
5. Then:               `python tool/khaya_voice_pack.py --drafts`

Stdlib only — no pip install needed.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path

# Windows consoles default to cp1252 and choke on Dagbani's ɛ/ɔ/ŋ.
# Force UTF-8 output so live API results print instead of crashing.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# --------------------------------------------------------------------------
# Khaya API configuration.
#
# VERIFIED LIVE (Aug 2026): `translation-api.ghananlp.org/v1/translate`
# answers 401 without a key — the base URL and path are real, only the
# subscription key is missing.
#
# The developer portal (https://translation.ghananlp.org) is powered by
# Azure API Management: calls authenticate with a subscription-key header.
# The TTS endpoint is NOT discoverable without portal access, so it is
# overridable via environment variables — after sign-up, copy the exact
# TTS base URL and path the portal shows and set:
#   $env:KHAYA_TTS_BASE_URL="https://..."   $env:KHAYA_TTS_PATH="/v1/..."
# --------------------------------------------------------------------------
KHAYA_BASE_URL = os.environ.get(
    "KHAYA_BASE_URL", "https://translation-api.ghananlp.org"
)
TRANSLATE_PATH = "/v1/translate"
TTS_BASE_URL = os.environ.get("KHAYA_TTS_BASE_URL", KHAYA_BASE_URL)
TTS_PATH = os.environ.get("KHAYA_TTS_PATH", "/v1/tts")
AUTH_HEADER = "Ocp-Apim-Subscription-Key"

# Khaya language-pair code for English <-> Dagbani. Portal examples use
# pairs like "en-tw" for Twi; confirm the Dagbani code in the portal.
LANG_PAIR = os.environ.get("KHAYA_DAGBANI_PAIR", "en-dag")

REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST = REPO_ROOT / "assets" / "audio" / "dagbani_pack_manifest.json"
STRINGS_DART = REPO_ROOT / "lib" / "core" / "i18n" / "dagbani_strings.dart"
AUDIO_OUT = REPO_ROOT / "assets" / "audio"
DRAFTS_OUT = REPO_ROOT / "tool" / "out" / "khaya_dagbani_drafts.json"

# Polite spacing between API calls — this is a batch tool, not a hot path.
CALL_PAUSE_SECONDS = 0.4


def load_manifest() -> list[dict]:
    """The 23-file pack plan: asset id, target filename, script key."""
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    return data["files"]


def extract_english_lines() -> dict[str, str]:
    """Pulls every `key`/`english` pair out of dagbani_strings.dart.

    The Dart file is the single source of truth for wording, so this tool
    parses it rather than duplicating the script. Tolerant regex: keys and
    english strings are always single-quoted in that file.
    """
    src = STRINGS_DART.read_text(encoding="utf-8")
    # Dart writes long strings as adjacent literals ('part one' 'part two'),
    # so capture the whole run of literals and join them — translating a
    # truncated sentence would poison the draft.
    block = re.compile(
        r"key:\s*'(?P<key>[^']+)'\s*,\s*english:\s*"
        r"(?P<strs>'(?:[^'\\]|\\.)*'"
        r"(?:\s*'(?:[^'\\]|\\.)*')*)",
        re.DOTALL,
    )
    literal = re.compile(r"'((?:[^'\\]|\\.)*)'")
    out: dict[str, str] = {}
    for m in block.finditer(src):
        text = "".join(
            lit.group(1).replace("\\'", "'")
            for lit in literal.finditer(m.group("strs"))
        )
        out[m.group("key")] = text
    return out


def resolve_script_key(entry: dict, lines: dict[str, str]) -> str | None:
    """Maps one manifest file to its English source line.

    Topics name their key directly (`scriptKey`). A question file such as
    `q_fits` is shared by every client stream that asks about the sign, so
    it takes the first available per-stream wording — the native-speaker
    reviewer adjusts it to the generic phrasing before verification,
    exactly as the recording protocol already requires.
    """
    if "scriptKey" in entry:
        key = entry["scriptKey"]
        return key if key in lines else None
    sign = entry["id"].removeprefix("q_")
    for stream in ("newborn", "child", "mother"):
        key = f"q.{stream}.{sign}"
        if key in lines:
            return key
    return None


def khaya_post(path: str, payload: dict, binary: bool = False,
               base_url: str | None = None):
    """One authenticated POST. Returns bytes (binary) or parsed JSON."""
    key = os.environ.get("KHAYA_API_KEY")
    if not key:
        sys.exit("KHAYA_API_KEY is not set. Get a subscription key from "
                 "https://translation.ghananlp.org first.")
    req = urllib.request.Request(
        (base_url or KHAYA_BASE_URL) + path,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            AUTH_HEADER: key,
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            body = resp.read()
            return body if binary else json.loads(body.decode("utf-8"))
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:300]
        sys.exit(f"Khaya API error {e.code} on {path}: {detail}\n"
                 f"If 404/401, confirm base URL, path and key header in the "
                 f"developer portal and adjust the constants at the top of "
                 f"this script.")


def cmd_drafts(lines: dict[str, str], dry_run: bool) -> None:
    """Translate each script line en -> dag, writing a review JSON."""
    print(f"DRAFTS: {len(lines)} lines via {LANG_PAIR}")
    drafts: dict[str, dict] = {}
    for key, english in sorted(lines.items()):
        if dry_run:
            print(f"  [dry] {key}: {english[:60]}...")
            continue
        resp = khaya_post(TRANSLATE_PATH, {"in": english, "lang": LANG_PAIR})
        # Portal docs show the translation in the response body; keep the raw
        # response alongside so a reviewer sees exactly what Khaya returned.
        drafts[key] = {
            "english": english,
            "khaya_draft": resp if isinstance(resp, str) else json.dumps(resp),
            "status": "draft — needs native-speaker review",
        }
        print(f"  ok   {key}")
        time.sleep(CALL_PAUSE_SECONDS)
    if not dry_run:
        DRAFTS_OUT.parent.mkdir(parents=True, exist_ok=True)
        DRAFTS_OUT.write_text(
            json.dumps(drafts, indent=2, ensure_ascii=False), encoding="utf-8"
        )
        print(f"Wrote {DRAFTS_OUT}")
        print("Next: a native Dagbani speaker reviews each line; approved "
              "wording goes into dagbani_strings.dart with verified=true.")


def cmd_tts(resolved: dict[str, str], lines: dict[str, str],
            dry_run: bool) -> None:
    """Synthesize one MP3 per manifest file via Khaya Dagbani TTS."""
    print(f"TTS: {len(resolved)} files -> {AUDIO_OUT}")
    for filename, key in resolved.items():
        target = AUDIO_OUT / filename
        text = lines[key]
        if dry_run:
            print(f"  [dry] {filename} <- {key}")
            continue
        audio = khaya_post(TTS_PATH, {"in": text, "lang": LANG_PAIR},
                           binary=True, base_url=TTS_BASE_URL)
        target.write_bytes(audio)
        print(f"  ok   {filename} ({len(audio)} bytes)")
        time.sleep(CALL_PAUSE_SECONDS)
    if not dry_run:
        print("Done. Now follow the ear-test protocol in "
              "assets/audio/README.txt before marking the pack verified.")


def cmd_langs() -> None:
    """GET /v1/languages — costs no translation quota. Proves the key works
    and shows the exact language-pair codes (confirm the Dagbani code here
    before spending any --drafts calls)."""
    key = os.environ.get("KHAYA_API_KEY")
    if not key:
        sys.exit("KHAYA_API_KEY is not set. Get a subscription key from "
                 "https://translation.ghananlp.org first.")
    req = urllib.request.Request(
        KHAYA_BASE_URL + "/v1/languages",
        headers={AUTH_HEADER: key},
        method="GET",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        sys.exit(f"Languages call failed with {e.code}. Check the key and "
                 f"header name in the portal.")
    print("Khaya languages response:")
    print(json.dumps(data, indent=2, ensure_ascii=False))


def cmd_smoke() -> None:
    """One real translation call — proves the key and wiring end-to-end
    before spending a batch on all 23 lines."""
    sample = "If your child cannot drink or breastfeed, go to the hospital now."
    print(f"SMOKE: translating one line via {LANG_PAIR} ...")
    resp = khaya_post(TRANSLATE_PATH, {"in": sample, "lang": LANG_PAIR})
    print(f"  English : {sample}")
    print(f"  Khaya   : {json.dumps(resp, ensure_ascii=False)}")
    print("Wiring confirmed. Run --drafts next.")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--dry-run", action="store_true",
                    help="print the plan; call nothing, write nothing")
    ap.add_argument("--langs", action="store_true",
                    help="free GET /v1/languages — verify key, show pair codes")
    ap.add_argument("--smoke", action="store_true",
                    help="one live translate call to verify key + wiring")
    ap.add_argument("--drafts", action="store_true",
                    help="run the translation-drafting step")
    ap.add_argument("--tts", action="store_true",
                    help="run the TTS synthesis step")
    ap.add_argument("--all", action="store_true", help="drafts + tts")
    args = ap.parse_args()

    if args.langs:
        cmd_langs()
        return
    if args.smoke:
        cmd_smoke()
        return

    manifest = load_manifest()
    lines = extract_english_lines()

    # Resolve every manifest file to its English source line up front so a
    # missing key fails loudly in the dry-run, not halfway through a paid
    # API batch.
    resolved: dict[str, str] = {}
    for entry in manifest:
        key = resolve_script_key(entry, lines)
        if key is None:
            print(f"WARNING: no script line resolves for {entry['file']}")
            continue
        resolved[entry["file"]] = key
    draft_lines = {key: lines[key] for key in resolved.values()}

    if not (args.drafts or args.tts or args.all):
        args.dry_run = True  # default posture: show, don't touch

    if args.dry_run:
        print(f"Pack manifest: {len(manifest)} files; "
              f"{len(resolved)} resolved to English lines.")
        cmd_drafts(draft_lines, dry_run=True)
        cmd_tts(resolved, lines, dry_run=True)
        return
    if args.drafts or args.all:
        cmd_drafts(draft_lines, dry_run=False)
    if args.tts or args.all:
        cmd_tts(resolved, lines, dry_run=False)


if __name__ == "__main__":
    main()
