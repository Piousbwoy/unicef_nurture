# Hausa on-device voice bank — provenance

**What this is.** 41 WAV clips (16 kHz, mono, PCM16, ~6.7 MB) of the app's
Hausa scripts, synthesized so the app can *speak* Hausa on any phone, fully
offline, until real studio recordings exist. Coverage: the five audio
topics, the 24 triage questions, the four triage-level family messages
(`level_*`), the three caregiver verdicts (`caregiver_verdict_*`), the
words-for-the-nurse frame (`nurse_*`), the language preview
(`setup_preview_Hausa`) and the voice-test phrase (`voice_test_Hausa`).
Composed messages (the words for the nurse) play several clips in sequence.

**What this is not.** These are NOT human recordings and NOT verified
Hausa. The Hausa drafts in `lib/core/i18n/speech_bank.dart` were written in
the plain, descriptive health register (trade-language Hausa) and still
need a native-speaker sign-off, and the voice itself is a machine voice.
The UI shows a "Hausa voice • on-device" pill and the script sheet says
exactly this.

## Model

| | |
|---|---|
| Base model | Meta MMS text-to-speech for Hausa (`facebook/mms-tts-hau`, VITS) |
| Checkpoint source | Community mirror `laztopaz/mms-tts-hau-custom` (transformers format, canonical MMS VITS shape: hidden 192, 6 layers, 1 speaker) |
| Upstream licence | CC-BY-NC 4.0 (inherited from the MMS release; non-commercial use) |
| Sampling rate | 16 000 Hz |
| Generator | `tool/generate_dagbani_speech.py hausa_mms` (see `manifest.json` for per-clip data) |
| Generated | 2026-08-27 |

## Verification (2026-08-27, `tool/eval_voices.py`)

Machine verification against the official Meta release — no human earing
required:

- **Weights are byte-identical to the official checkpoint.** The sha256 of
  `laztopaz/mms-tts-hau-custom`'s `model.safetensors` equals the official
  `facebook/mms-tts-hau` (now public): `8a68b8c658853a92fd50…`. The bank
  speaks with Meta's canonical Hausa voice, not a degraded copy.
- **Language ID** (`facebook/mms-lid-2048`) classifies the bank's
  `child_danger_signs` clip as Hausa with p=1.0 and `q_child.fits` with
  p=0.999 — the model hears real Hausa, not English words in an accent.
- **ASR round-trip** (`facebook/mms-1b-all`, `hau` adapter) recovers an
  average 0.929 of the script across four clips — identical to fresh
  synthesis from the official weights ("yaron na tonsiya", "ku tafi
  asibiti yanzu karku jira har gobe").
- **Community fine-tunes were auditioned and rejected.** Every expressive
  candidate failed the language check (one classified as Norwegian,
  nno:0.282); the only candidates that passed were LID-identical to the
  official voice, so swapping them buys nothing. The canonical voice
  stays until a native speaker records real audio.

## Why the bank runs before the phone's own Hausa voice

A phone that "has" a Hausa TTS voice would speak the English *display*
text (draft display is gated) in a Hausa accent — English words, wrong
language. The bank speaks actual Hausa words, works on the web demo where
no Hausa voice exists, and keeps the voice consistent across devices. The
system TTS Hausa voice remains the honest backup if a bank clip is
missing.

## Regeneration

```
python tool\generate_dagbani_speech.py hausa_mms
```

Requires `torch`, `transformers`, `soundfile`. The phrase list in the
script mirrors `speech_bank.dart` (the clip map) — if a draft changes
there, regenerate here. `test/speech_bank_test.dart` fails when a clip id
and a bank file drift apart.

## The honest chain

This bank sits at step 2 of `VoiceService.speak`, below studio recordings
(`audio/<id>_<language>.mp3`) and above system TTS / the Hausa bridge /
read-aloud. When a real Hausa recording lands in the assets folder it
automatically wins; this bank only fills the gap.
