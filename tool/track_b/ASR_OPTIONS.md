# ASR without an ASR budget

We have no speech recognition, and the model everyone measures Ghanaian ASR
against — Khaya's DONDO — is 2.4 GB per language. That is not a reason to
cancel voice input; it is a reason to choose a different shape of model. Sizes
and licences below were read from the Hub on 2026-10-18.

## What already exists, and what it costs

| model | languages | params | on disk | licence | fits a phone? |
| --- | --- | --- | --- | --- | --- |
| `KhayaAI/w2v-bert-dga` (DONDO) | Dagbani; also kus, xsm, ada, gaa, tem, maw, nzi, wlx, men | ~600 M | 2 423 MB | Apache-2.0 | no |
| `asr-africa/wav2vec2-xls-r-akan-20-hours` | Akan/Twi | 300 M | 1 262 MB | Apache-2.0 | no |
| `jdapaah/whisper-small-twi-arxiv` | Twi | 244 M | ~790 MB | Apache-2.0 | borderline |
| `openai/whisper-tiny` (base for fine-tuning) | 100 languages, not Ghanaian | 39 M | 609 MB fp32 (~75 MB in fp16, ~40 MB int8) | MIT | yes |

Training data for our own: `google/WaxalNLP` `dag_asr` and `aka_asr`,
CC-BY-4.0 / CC-BY-SA-4.0. **Corrected on 2026-10-18:** the splits are
train 14 231 / val 1 750 / test 1 838 for Dagbani and 10 107 / 1 123 / 1 522 for
Akan — roughly 17.8 k and 12.7 k *labelled* rows. The ~186 k figures quoted here
for weeks are the whole parquet, most of it unlabelled. Fine-tuning is a
20 k-row problem, not a 185 k-row problem, which changes what a small model can
reasonably be expected to learn.

## Route 1 — closed-vocabulary voice input, no training (MEASURED: does not work)

The premise was sound: the app rarely needs open dictation, and the caregiver
flow has a tiny answer set — `Ee` / `Ayi` / `Mi bɛ mi` reused across 153
questions, ~31 distinct caregiver-facing answers in total. So don't recognise
speech; recognise *which of these N things was said*, with templates generated
by our own TTS and matched with MFCC windows. No logits, no fine-tune, no licence.

`tool/asr_kws_probe.py` built exactly that and measured it on the licensed
Dagbani corpus. Two numbers, in this order:

| measurement | mean AUC | per word |
| --- | --- | --- |
| **control** — our TTS vs our TTS: 3-word slices, same voice, same channel, no real audio at all | **0.597** | dauda 0.642, mini 0.854, maa 0.572, nyɛ 0.468, ŋun 0.449 |
| **real speech** — the same templates slid across 400 real ~10 s sentences | **0.484** | chance on every word |

The control is the killer. A working matcher must score near 1.0 there — same
speaker, same synthesiser, same recording conditions. It scored 0.597 with two
words *below* chance, so the representation (duration-normalised MFCC windows
plus cosine, with per-window normalisation, silence trimming and windows matched
to each word's own length) does not encode word identity. The real-speech number
is therefore not a domain-gap result; the matcher was never working.

The shape of the failure matters for what we ship next. The two words that fell
below chance are `nyɛ` and `ŋun` — single short syllables, 0.5 s of speech. The
word that scored 0.854, `mini`, is two syllables. Our clinical answers are
exactly the hard class: `Ee` and `Ayi` are single syllables under half a second.
A matcher that cannot hear `nyɛ` in its own synthetic voice will not hear `Ee`
through a phone microphone in a compound in Tamale.

Closed-vocabulary voice input is still the right *product* shape — the answer
set is small, and a confidence gate that falls back to the buttons is mandatory
either way. But it needs a real acoustic encoder underneath it, which is Route 2.

**Prerequisite found while measuring:** the app cannot capture audio at all
today. `pubspec.yaml` has playback only (`audioplayers`, `flutter_tts`), there
is no microphone permission in `AndroidManifest.xml`, and no
`NSMicrophoneUsageDescription` in `Info.plist`. Any route needs a recorder, a
permission, and a listening state in the triage UI before a single model runs.

Tradeoff: it only works inside the closed set. Free text ("describe the
swelling") still needs typing or a CHO reading it aloud. That is acceptable
here, because the clinical questions are structured by design.

## Route 2 — whisper-tiny fine-tuned per language (the honest model)

`openai/whisper-tiny` (39 M; the Hub tag reads apache-2.0 even though OpenAI
publishes it as MIT — worth confirming before it goes in a clinical pack)
fine-tuned on WaxalNLP `dag_asr` / `aka_asr`, scored as CER against DONDO, then
exported to the `asr-v1` contract in `assets/asr/README.md`.

**Measured baseline (2026-10-18, `tool/asr_eval/`, throwaway):** the untuned
model is useless, and that is the useful part of the result.

| language | CER | WER | RTF, 4 desktop cores |
| --- | --- | --- | --- |
| Dagbani (n=15) | **0.910** | 1.203 | 1.8–2.3× |
| Akan/Twi (n=17) | **0.780** | 1.131 | 1.80× |

Hypotheses drift into Arabic, Indonesian and English (`Tɛnis agoprama mu…` came
back as "tennis are good for men very much now I say I go"). Gold transcripts use
`ɛ ɔ ŋ ɣ ʋ Ɛ Ɔ`, matching the app's orthography, so CER is comparable.
A 39 M model running slower than real time also settles the size question: the
600 M DONDO is not a phone model even if it is accurate.

Cost: one GPU day per language, plus the usual failure mode — a small model on
185 k rows of radio-style audio can come out mediocre, and a mediocre
recogniser in a health app is worse than none, because users will trust it.
Mitigation: measure CER first on 200 held-out clips, and only ship if it clears
a bar we set out loud (say, CER under 25% on the answer vocabulary).

## Measured 2026-10-20 — the two models that already exist

Held-out WaxalNLP **test** speech, 8 clips per language (142 s of audio each),
`tool/asr_eval/score_ctc.py`, 4 threads on a desktop CPU, no fine-tuning by us:

| model | language | median CER | mean CER | mean WER | mean RTF | clips under 0.25 CER |
| --- | --- | --- | --- | --- | --- | --- |
| `KhayaAI/w2v-bert-dga` (DONDO, 606 M) | Dagbani | **0.420** | 0.427 | 0.891 | 1.89× | 0 / 8 |
| `asr-africa/wav2vec2-xls-r-akan-20-hours` (300 M) | Akan/Twi | **0.162** | 0.208 | 0.400 | 0.69× | 5 / 8 |

Read the median, not the mean: DONDO is 0.356 at best and 0.552 at worst, so the
number is "roughly two words in five", not "sometimes fine". The Akan model is
the first recogniser in this project to clear the 25% bar that was set out loud
before anyone built anything, and it is also the smaller and faster of the two —
250 M fewer parameters and 2.7× the speed. Both RTF figures are CPU-thread counts
on a development machine, not a phone; nothing here says either model runs in
real time on a $60 handset.

**Two things this run did not measure, and cannot.**

1. *The closed set.* These are picture-description narrations, and the answer
   words essentially never appear in them as isolated words. The whole-word
   count across all 16 clips: `Ee` 0, `Ayi` 0, `Nni` 0, `Mmo` 0, `Ɛyɛ` 1 — and
   that one is the verb ("ɛyɛ" = *it is*), not the answer. An earlier version of
   the table matched substrings instead and reported `Ee` surviving in three
   clips; what it had actually found was `ʒee`, `shee`, `teebuli`, and `Ayi`
   inside `dibaayi` (*stranger*). Substring matching on a 19-second transcript is
   noise, and it was recorded as noise rather than kept as a result. The real
   closed-set number needs people answering questions out loud, which is what
   `data/closed_set/record.csv` (10 speakers × 3 answers) is for.
2. *The ruler.* `score_dondo.py` carried its own copy of `normalise`, and that
   copy dropped every space — so `wer()` compared one token against one token and
   returned 1.0 for any two different sentences. The earlier whisper-tiny WER
   column came from the other copy (`scoring.py`) and is real; every WER from
   this file was not. The duplicate is gone, `score_dondo.py` now imports the
   single ruler, and CER itself is unchanged (0.4267 both ways). `scoring.py`'s
   own docstring warned that two copies of a scoring rule is how two models end
   up measured on different rulers. That is exactly what happened.

**What the app now does with these numbers.** Free dictation and the closed set
are different claims, so they are gated separately:
`SpeechInputService.dictates()` reads the measured median CER and refuses any
language above 0.25. Dagbani keeps the three-word closed set and dictates
nothing; Twi is allowed to dictate, and `VoiceDictate` hides its microphone where
the measurement does not back it. Dropping a DONDO pack into `assets/asr/dagbani`
therefore cannot put a 42%-wrong sentence into a caregiver's note.

## The packs themselves (2026-10-21)

Both models are exported into `asr-v1` and run through the app's own engine —
`ASR_PACK=data/asr_dev/twi_akan flutter test test/asr_native_pack_test.dart
--dart-define=RUN_NATIVE_VOICE=true`. They live in gitignored `data/asr_dev/`;
neither is a shippable asset yet.

| pack | size | what the app measured |
| --- | --- | --- |
| `dagbani_dondo` (int8) | 876 MB | 59 frames → 30 rows × 39 labels, 1.49 s for 1.2 s of audio |
| `twi_akan` (int8) | 355 MB | 19200 samples → 59 rows × 36 labels, 1.80 s for 1.2 s of audio |

The Twi number needed a second frontend recipe: `Wav2Vec2FeatureExtractor` for
this model is `feature_size: 1, do_normalize: true`, which means the app is asked
for the **layer-normalised waveform**, not a mel bank — the spectrogram lives in
the model's seven learned convolutions. `asr-v1` now carries `features:
"waveform"` packs (`input_values [1, samples]`), and they ship no filter tables
at all. That recipe is pinned against the real extractor by
`test/asr_waveform_fixture_test.dart` for the same reason the mel one is: the
arithmetic is three lines, and both plausible ways to get it wrong (sample rather
than population variance, epsilon outside the root) still transcribe fluently.

Quantisation cost nothing measurable: scoring the int8 Twi pack with
`tool/asr_eval/score_pack.py` on the same eight held-out clips returns mean CER
**0.2075** and 5 of 8 clips under 0.25 — the fp32 model's numbers to four
decimals. One caveat about that comparison, because it cuts both ways: the eight
clips are 19–20 s long, and the pack's own `max_frames` is 64000 samples (4 s),
which is what the app can actually record. The parity run therefore feeds 20 s
and says so in its output. A four-second take is a stricter, different condition
and is what the closed set will be measured on.

### Hearing a real answer word (2026-10-21)

`test/asr_native_pack_test.dart` now scores actual spoken answers through the
app's own frontend, encoder and decoder: five Twi yes/no clips and the Dagbani
`Ee` come back as the right answer. Building it found two defects worth more than
the result. The encoder was handing the decoder **logits**, so every CTC score the
app made was `log(logit)` — which is why a per-frame floor compared against it
refused nothing, and why the dictation confidence gate was always satisfied. And
the CTC pass required a blank frame between **every** pair of letters rather than
only between identical ones, which silently penalised long answers more than short
ones (a correct three-frame answer moved from −17.4 nats to −0.003).

The probe could not calibrate refusal, and that is a fact about the probe: its
negatives are four-second narration sentences, and under the corrected decoder
those score *higher* per frame (−0.66 to −1.08) than the isolated answers (−0.83
to −1.61), because CTC always finds a two-letter word somewhere inside four
seconds of speech. The per-language floors briefly derived from the broken scorer
have been reverted to one conservative default. What protects a record today is
that the endpointer hands the model one utterance and that an unverified answer
set may only propose. The floors need `data/closed_set/record.csv` — one phrase
per take, from a human mouth.

## Route 3 — DONDO on the big device only

The FHW side runs on tablets that the CHO carries, not a $60 phone. 2.4 GB is
already the shape of our translation-plus-voice packs, and the store supports
packs up to 2 GB with hash verification. Shipping Khaya's own Apache-2.0 model,
offline, inside a clinical workflow they don't have, is a legitimate answer to
"who are you trying to fool": we are not competing with their model, we are
using theirs where it fits and ours where it does not.

## Recommendation

Route 1 is measured out and Route 3 has now been measured too, which rewrote the
list. What the 2026-10-20 numbers leave:

1. **Mic plumbing — done, and invisible until a pack arrives.** Recorder,
   `RECORD_AUDIO`, `NSMicrophoneUsageDescription`, endpointing, propose-and-confirm
   UI, and the closed-set decoder are all in the app and under test (see below).
2. **Twi is the language to build on.** The Akan XLS-R pack cleared the 25% bar
   (median CER 0.162) and ran at RTF 0.69 on four desktop CPU threads. Export it
   to `asr-v1`, quantise it, and *then* measure the pack itself — a 300 M model at
   0.69× on a desktop is a promise, not a phone result.
3. **Dagbani needs its own recogniser, not DONDO.** 0.42 median CER at 1.89× and
   606 M params fails on all three counts. Fine-tuning
   `openai/whisper-tiny` (MIT, 39 M) on WaxalNLP `dag_asr` in the same Colab
   session as the Dagbani TTS run is still the cheapest route to a Dagbani
   listener; until something clears 25%, Dagbani has the closed set only.
4. **Before either ships: the recordings.** 10 speakers × 3 answers
   (`data/closed_set/record.csv`), scored through `CtcDecoder.restricted`, is the
   only measurement that can set `SpeechConfidence`'s floors and flip
   `verified: false`. No number available today does, because the corpora contain
   no isolated answer words (above).

A recogniser that is wrong 1 time in 5 is worse in a clinical flow than no
recogniser, because people trust speech. The closed set and the visible refusal
are what make a mediocre model safe to ship; they do not make it work.

## What is already built (so the model is the only missing part)

Voice input is wired through the app and stays invisible until an `asr-v1` pack
is dropped into `assets/asr/{language}`. No feature flag, no stub: absence of a
pack is what switches it off.

- `lib/core/audio/voice_activity.dart` — energy endpointing with hysteresis:
  spoke / silent / too-short / over-ceiling.
- `lib/core/audio/recording_gate.dart` — `package:record`, linear PCM 16 kHz mono,
  permission asked once per session, buffer zeroed after every take.
- `lib/core/ml/asr_contract.dart` + `asr_features.dart` + `asr_decoder.dart` —
  the `asr-v1` contract, a Dart log-mel frontend, greedy CTC for dictation and
  the exact forward algorithm per candidate for a closed set.
- `lib/core/audio/speech_input_service.dart` — the decision: posterior **and**
  absolute per-frame likelihood must clear, and the free reading must not
  contradict the closed set. Anything else is `unclear`.
- `lib/presentation/shared/voice_ask.dart` — propose-and-confirm on the 153
  clinical questions; `VoiceDictate` writes straight into a note field.
- `lib/core/audio/speech_answers.dart` — `Ee / Ayi / Mi bɛ mi` (Dagbani) and
  `Ɛyɛ·Aane / Nni / Minnim` (Twi), all `verified: false`.

Two gaps that are not code: the closed set cannot be scored from any public
corpus (in 100 Dagbani test rows `Ee` occurs 0 times, `Mi bɛ mi` 0, `Ayi` 9 —
narrative sentences, not answers), so validating it means recording speakers; and
the confidence floors in `SpeechConfidence` are placeholders that refuse often
until someone sets them from a measured ROC.
