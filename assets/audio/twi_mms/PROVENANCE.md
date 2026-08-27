# Twi (Asante) on-device voice bank — provenance

**What this is.** 41 WAV clips (16 kHz, mono, PCM16, ~6.5 MB) of the app's
Twi scripts, synthesized so the app can *speak* Twi on any phone, fully
offline, until real studio recordings exist. Coverage: the five audio
topics, the 24 triage questions, the four triage-level family messages
(`level_*`), the three caregiver verdicts (`caregiver_verdict_*`), the
words-for-the-nurse frame (`nurse_*`), the language preview
(`setup_preview_Twi`) and the voice-test phrase (`voice_test_Twi`).
Composed messages (the words for the nurse) play several clips in sequence.

**What this is not.** These are NOT human recordings and NOT verified Twi.
The Twi drafts in `lib/core/i18n/speech_bank.dart` are plain-language
drafts whose clinical terms — `sɛsɛa` (fits/convulsions), `dua` (stool),
`pampɔn` (umbilical cord), `abere` (yellow), `rebu` (foetal kicks),
`abubuo` (beans) — need a Twi-speaking health educator's ear before the
words are trusted for teaching. The `notes` field on each entry lists what
to confirm. The voice itself is a machine voice; the UI shows a "Twi
voice • on-device" pill and the script sheet says exactly this.

## Model

| | |
|---|---|
| Base model | Meta MMS text-to-speech for Twi (`facebook/mms-tts-twi`, VITS) |
| Checkpoint source | Community mirror `IanKobby/mms-tts-twi-ghana` (transformers format, canonical MMS VITS shape: hidden 192, 6 layers, 1 speaker) — the same trusted mirror author as the Dagbani bank |
| Upstream licence | CC-BY-NC 4.0 (inherited from the MMS release; non-commercial use) |
| Sampling rate | 16 000 Hz |
| Generator | `tool/generate_dagbani_speech.py twi_mms` (see `manifest.json` for per-clip data) |
| Generated | 2026-08-27 |

## Regeneration

```
python tool\generate_dagbani_speech.py twi_mms
```

Requires `torch`, `transformers`, `soundfile`. The phrase list in the
script mirrors `speech_bank.dart` (the clip map) — if a draft changes
there, regenerate here. `test/speech_bank_test.dart` fails when a clip id
and a bank file drift apart.

## The honest chain

This bank sits at step 2 of `VoiceService.speak`, below studio recordings
(`audio/<id>_<language>.mp3`) and above system TTS / the Hausa bridge /
read-aloud. A phone with a Twi TTS voice would otherwise speak the English
display text in a Twi accent — the bank speaks actual Twi words instead.
When a real Twi recording lands in the assets folder it automatically
wins; this bank only fills the gap.
