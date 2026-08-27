# Dagbani on-device voice bank — provenance

**What this is.** 41 WAV clips (16 kHz, mono, PCM16, 9.3 MB) of the app's
Dagbani scripts, synthesized so the app can *speak* Dagbani on any phone,
fully offline, until real studio recordings exist. Coverage: the five audio
topics, the 24 triage questions, the four triage-level family messages
(`level_*`), the three caregiver verdicts (`caregiver_verdict_*`), the
words-for-the-nurse frame (`nurse_*`), the language preview
(`setup_preview_Dagbani`) and the voice-test phrase (`voice_test_Dagbani`).
Composed messages (the words for the nurse) play several clips in sequence.

**What this is not.** These are NOT human recordings and NOT verified
Dagbani. The underlying Dagbani translations in
`lib/core/i18n/dagbani_strings.dart` are drafts awaiting a native-speaker
sign-off, and the voice itself is a machine voice. The UI shows a
"Dagbani voice • on-device" pill and the script sheet says exactly this.

## Model

| | |
|---|---|
| Base model | Meta MMS text-to-speech for Dagbani (`facebook/mms-tts-dag`, VITS) |
| Checkpoint source | Community mirror `IanKobby/mms-tts-dag-ghana` (transformers format) |
| Upstream licence | CC-BY-NC 4.0 (inherited from the MMS release; non-commercial use) |
| Sampling rate | 16 000 Hz |
| Generator | `tool/generate_dagbani_speech.py` (see `manifest.json` for per-clip data) |
| Generated | 2026-08-27 |

## Regeneration

```
python tool\generate_dagbani_speech.py dagbani_mms
```

Requires `torch`, `transformers`, `soundfile`. The phrase list in the
script mirrors `speech_bank.dart` (the clip map) and
`dagbani_strings.dart` (the wording) — if a draft changes there,
regenerate here. `test/speech_bank_test.dart` fails when a clip
id and a bank file drift apart.

## The honest chain

This bank sits at step 2 of `VoiceService.speak`, below studio
recordings (`audio/<id>_<language>.mp3`) and above system TTS / the
Hausa bridge / read-aloud. When a real Dagbani recording lands in the
assets folder it automatically wins; this bank only fills the gap.
