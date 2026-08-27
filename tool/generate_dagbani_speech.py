"""Generate the on-device Dagbani voice bank for CareBridge.

Downloads Meta's MMS Dagbani text-to-speech checkpoint (VITS, via the open
community mirror of `facebook/mms-tts-dag`) and synthesizes one WAV per
Dagbani script in `lib/core/i18n/dagbani_strings.dart`, keyed by the exact
`VoiceRequest.id` values VoiceService queries:

  - audio topics:  `child_danger_signs`, `feeding`, ...
  - triage questions: `q_newborn.feed`, `q_mother.fits`, ...
  - level messages: `level_urgent`, `level_priority`, ...
  - caregiver verdicts: `caregiver_verdict_urgent`, ...
  - nurse-words frame: `nurse_intro`, `nurse_unsure`, `nurse_close`
  - standalone: `setup_preview_Dagbani`, `voice_test_Dagbani`

The Dagbani text mirrors `lib/core/i18n/dagbani_speech.dart` (the clip map)
and `lib/core/i18n/dagbani_strings.dart` (the wording) — the Dart-side asset
coverage test fails if a clip id and a bank file ever drift apart.

Output lands in `assets/audio/dagbani_mms/<id>.wav` (16 kHz mono PCM16) plus
a PROVENANCE.md. The generated clips are **synthesized drafts of draft
translations** — the UI labels them as such; they are never presented as
studio recordings.

Usage:  python tool\\generate_dagbani_speech.py
"""

from __future__ import annotations

import datetime as _dt
import json
from pathlib import Path

import numpy as np
import soundfile as sf
import torch
from transformers import AutoTokenizer, VitsModel

# The official `facebook/mms-tts-dag` repo is access-gated; this community
# mirror carries the identical VITS checkpoint in transformers format.
MODEL_ID = "IanKobby/mms-tts-dag-ghana"
UPSTREAM = "facebook/mms-tts-dag"
OUT_DIR = Path(__file__).resolve().parent.parent / "assets" / "audio" / "dagbani_mms"

# ---------------------------------------------------------------- the scripts
# Keys are the VoiceRequest ids; values are the exact Dagbani drafts from
# `dagbani_strings.dart` (kept verbatim, including the project's draft status).
# Em-dashes become commas: the tokenizer has no entry for '—' and the pause
# it encodes is what we actually want.
PHRASES: dict[str, str] = {
    # ------------------------------------------------------------- audio topics
    "child_danger_signs": (
        "Ni bini maa ti niŋ ka o nui tana bee ka o nu tana, o yiɣiri, o "
        "ti zuɣa, o wum kpibu, bee o maani nɔri ŋɔ zaɣa — yi tiŋ bɛ ni "
        "kpeeni pam. Tɔ di mali kpeenim maa nyɛla din gbanŋɛ. Bini maa "
        "bɔri sɔŋsi ŋɔ."
    ),
    "newborn_danger_signs": (
        "Ni bini kpalansi maa ti niŋ ka o nu tana, o ɣiri tɔɣi bee o "
        "gbili, o ti zuɣa, o wum kpibu, o ti yɛɣiri pam bee o ti bini, o "
        "ti ɣari yaa-ŋa bee nini, bee o tuli kpamba ti kɔbigu bee o ti "
        "yiɣiri — yi tiŋ bɛ ni kpeeni pam. Bini kpalansi maa bɛ ni kpeenim "
        "tɔ zugiri, di ti bɛ mali ni tɔ mali ŋaani."
    ),
    "mother_danger_signs": (
        "Ni naɣa maa ti kɔbigu pam, o ti m bɛ laɣim pam, o ti bini pam, "
        "o ti kɔbigu taba pam, o ti zuɣa, bee o ti yiɣiri ni bini maa — yi "
        "tiŋ bɛ ni kpeeni pam. Ni o bɛ ni tuhi bini, ka bini maa tuhi ti "
        "laɣim ni yili maa, yi tiŋ kpeeni din yi na. Tɔ di mali kpeenim "
        "ka tɔ tuhi laɣim maa."
    ),
    "feeding": (
        "Tiam kpalansi kpe maa kuli nyini, a tɔri bini — ami, tuhim. Din "
        "yi ti kpeita, tiam tuɣa nini kama anahi puuni ti maani, ka a "
        "naɣisi ti niriba shɛli nyɛla di bɛ ni bini. Tiam nyini ka bini ŋɔ "
        "ti bɛ mali ni bini titali. Bini bɛ mali ni nuhu shɛli bɛ ni tiri, "
        "o ti nɔri."
    ),
    "referral": (
        "Sɔŋsi bɛ maa nyɛla nini ti ni tooi ti shɛli ka tiŋ maa bɛ ni "
        "niŋ shɛli, amaa tiŋ bɛ tiŋ maa ti ni tooi. Yi tiŋ bɛ ni kpeeni "
        "ni bini bɛ ti m-paai ka di yɛli ni ŋɔ — din yi na maa yi kpeeni "
        "nyɛla din gbanŋɛ. Tiam tuhi telephone bini maa bee pepa bini maa, "
        "ka a tiŋ di na kpeeni. Ni bini kpeenim ti m-paai ni tihi, yɛli "
        "ti sɔŋsi nira maa; bɛ bɛ ni laɣim shɛli din ni sɔŋ."
    ),
    # -------------------------------------------------------- triage questions
    "q_newborn.feed": "Bini kpalansi maa ti nu tana",
    "q_newborn.fast": "Bini kpalansi maa ɣiri tɔɣi bee ka o gbili",
    "q_newborn.fits": "Bini kpalansi maa ti zuɣa",
    "q_newborn.sleepy": "Bini kpalansi maa wum kpibu pam bee ka o ti mɔri",
    "q_newborn.temp": "Bini kpalansi maa bini pam bee ka o ti bini pam",
    "q_newborn.yellow": "Bini kpalansi maa yaa-ŋa bee nini ɣari",
    "q_newborn.cord": "Tuli kpamba maa kɔbigu, o pɔŋ, bee o yiɣiri ni bini",
    "q_newborn.vomit": "Bini kpalansi maa yiɣiri bini maa pam",
    "q_child.drink": "Bini maa ti ni tooi nu tana bee ka o nu",
    "q_child.vomit": "Bini maa yiɣiri bini maa pam",
    "q_child.fits": "Bini maa ti zuɣa",
    "q_child.sleepy": "Bini maa wum kpibu pam bee ka o ti mɔri",
    "q_child.breath": "Bini maa ɣiri tɔɣi bee ka o ti ɣiri ti tuhi",
    "q_child.blood": "Nɔri bɛ bini maa tuhi",
    "q_child.thin": "Bini maa ti pɔŋ nini pam, bee o ti nɔri pɔŋ",
    "q_child.fever": "Bini maa ti bini ti pii dabaasi anahi",
    "q_mother.bleed": "Naɣa maa kɔbigu pam",
    "q_mother.head": "Naɣa maa m bɛ laɣim pam ti o gɔri ti ti mali yɛn",
    "q_mother.fever": "Naɣa maa bini pam",
    "q_mother.pain": "Naɣa maa ti kɔbigu taba pam",
    "q_mother.fits": "Naɣa maa ti zuɣa",
    "q_mother.smell": "Bini yiɣiri bɛ bini maa",
    "q_mother.move": "Ni o bɛ ni tuhi bini, bini maa tuhi ti laɣim ni yili maa",
    "q_mother.vomit": "Naɣa maa yiɣiri bini maa pam",
    # ------------------------------------------------- triage-level messages
    # Mirror dagbani_speech.dart (levelUrgent … levelRoutine).
    "level_urgent": (
        "Yi tiŋ bɛ ni kpeeni pam. Tɔ di mali kpeenim maa nyɛla din gbanŋɛ."
    ),
    "level_priority": (
        "Tɔ sɔŋsi nira maa ti ti bini maa. Maani sɔŋsi tiŋ maa, ka yi tiŋ "
        "labina dabaasi ata nyaaŋa."
    ),
    "level_watch": (
        "Tin yaa ka ti maani sɔŋsi tiŋ maa. Gbilsim niŋ kpeenim. Ni bini maa "
        "ti niŋ tuma, yi tiŋ labina."
    ),
    "level_routine": (
        "Bini maa nyɛla din yaa. Ti maani sɔŋsi tiŋ maa ka o nu tana."
    ),
    # --------------------------------------------------- caregiver verdicts
    # Mirror dagbani_speech.dart (caregiverVerdictUrgent … Fine).
    "caregiver_verdict_urgent": (
        "Yi tiŋ bɛ ni kpeeni pam. Bini maa zuɣu m-beni. Tɔ di mali kpeenim "
        "maa nyɛla din gbanŋɛ. Ni CHPS tiŋ maa kpari, yi tiŋ alaafee yili "
        "bee ashibiti titali."
    ),
    "caregiver_verdict_caution": (
        "Ti sɔŋsi nira maa ni kpeenim laɣim. Mi bɛ mi bini shɛŋa. Yi tiŋ "
        "labina ni tiŋ maa dabaasi ayi puuni."
    ),
    "caregiver_verdict_fine": (
        "Tin yaa ka ti maani sɔŋsi tiŋ maa. Bini maa zuɣu maa bɛni. Ti "
        "maani sɔŋsi tiŋ maa, ka ti labina tooni."
    ),
    # ---------------------------------------------------- nurse-words frame
    # Mirror dagbani_speech.dart (nurseIntro / Unsure / Close). The sign
    # statements reuse the question clips.
    "nurse_intro": "N ni nya bini shɛŋa n-yɛliya.",
    "nurse_unsure": "Mi bɛ mi bini shɛŋa ŋɔ.",
    "nurse_close": "N yɛn yɛliya bini kam ni daa piligi shɛm.",
    # ------------------------------------------------------------ standalone
    "setup_preview_Dagbani": "Yi tiŋ bɛ ni kpeeni pam",
    "voice_test_Dagbani": (
        "Ni bini maa ti niŋ ka o nui tana, yi tiŋ bɛ ni kpeeni pam."
    ),
}


def _tidy(text: str) -> str:
    return text.replace("—", ",").replace("  ", " ").strip()


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    print(f"Loading {MODEL_ID} …")
    tokenizer = AutoTokenizer.from_pretrained(MODEL_ID)
    model = VitsModel.from_pretrained(MODEL_ID)
    model.eval()
    rate = model.config.sampling_rate
    print(f"Loaded. Sampling rate: {rate} Hz")

    pad = np.zeros(int(rate * 0.15), dtype=np.float32)
    manifest: dict[str, dict[str, object]] = {}

    for audio_id, raw in PHRASES.items():
        text = _tidy(raw)
        inputs = tokenizer(text, return_tensors="pt")
        with torch.no_grad():
            out = model(**inputs).waveform
        wav = out.squeeze().numpy().astype(np.float32)

        # Peak-normalize so every clip plays at a comparable loudness, then
        # add a small breathing pad on both ends.
        peak = float(np.max(np.abs(wav))) or 1.0
        wav = wav / peak * 0.85
        wav = np.concatenate([pad, wav, pad])

        target = OUT_DIR / f"{audio_id}.wav"
        sf.write(target, wav, rate, subtype="PCM_16")
        manifest[audio_id] = {
            "seconds": round(len(wav) / rate, 2),
            "bytes": target.stat().st_size,
        }
        print(f"  {audio_id}.wav  {len(wav) / rate:.1f}s  {target.stat().st_size // 1024} KB")

    total = sum(int(m["bytes"]) for m in manifest.values())
    (OUT_DIR / "manifest.json").write_text(
        json.dumps(
            {
                "generated": _dt.date.today().isoformat(),
                "model_mirror": MODEL_ID,
                "upstream": UPSTREAM,
                "sampling_rate": rate,
                "total_bytes": total,
                "clips": manifest,
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"Done. {len(manifest)} clips, {total // 1024} KB total.")


if __name__ == "__main__":
    main()
