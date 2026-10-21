# Speech-input packs (`asr-v1`) — two recipes, no pack shipped yet

Voice input is wired through the app and switched off by the absence of a pack,
not by a feature flag. `AsrService.assetPath(language)` looks for
`assets/asr/{language}` containing:

```
model.onnx            # encoder: features in, frame posteriors out
frontend.json         # the contract below
mel_filters.json      # the pack's own mel matrix, (frequency bin, mel band)
window.json           # the 400-sample analysis window it was trained with
model_manifest.json   # contract "asr-v1", sha256 + bytes per file
```

`mel_filters.json` and `window.json` belong to the mel recipe only. A
raw-waveform pack that ships them is refused, not ignored: carrying a filter bank
the model never asked for means the pack and the app disagree about what a
feature is.

`frontend.json`, mel recipe (`seamless-fbank`, what DONDO is):

```json
{
  "language": {"code": "dag", "name": "Dagbani"},
  "audio": {
    "sample_rate": 16000, "features": "seamless-fbank",
    "frame_length": 400, "hop_length": 160, "fft_length": 512,
    "mel_bins": 80, "input_dim": 160, "stride": 2,
    "power": 2.0, "preemphasis": 0.97, "remove_dc_offset": true,
    "mel_floor": 1.192092955078125e-07, "log": "log",
    "per_band_normalize": {"mode": "zero-mean-unit-variance", "epsilon": 1e-7, "ddof": 1},
    "pad_with": 1, "frames_per_second": 49.1667, "max_frames": 400
  },
  "model": {
    "inputs": ["input_features", "attention_mask"],
    "labels": ["|", "[", "]", "a", …], "num_labels": 39, "blank_index": 36
  }
}
```

`frontend.json`, raw-waveform recipe (what the Akan/Twi model is):

```json
{
  "language": {"code": "twi"},
  "audio": {
    "sample_rate": 16000, "features": "waveform", "input_dim": 1,
    "normalize_epsilon": 1e-7, "frames_per_second": 16000, "max_frames": 64000
  },
  "model": {
    "inputs": ["input_values", "attention_mask"],
    "labels": ["|", "a", …], "num_labels": 36, "blank_index": 33
  }
}
```

`tool/asr_export/make_frontend_fixture.py` writes the mel files from the
HuggingFace processor the model was trained on, so the app never has to re-derive
Kaldi's filter bank: `MelFrontend` applies the 2^15 scaling, DC-offset removal,
pre-emphasis, the carried window, a radix-2 FFT that zero-pads the 400-sample
frame into 512 bins, the carried mel matrix, `log(max(x, mel_floor))`, per-band
zero-mean/unit-variance over time, then stacks `stride` frames into `input_dim`.
What that must equal is not a matter of opinion —
`test/asr_frontend_fixture_test.dart` replays clips pushed through the real
`SeamlessM4TFeatureExtractor` and fails past 1e-5, currently 1.7e-6.

`WaveformFrontend` is the other half: `Wav2Vec2FeatureExtractor` with
`feature_size: 1, do_normalize: true` asks for the samples themselves,
zero-mean/unit-variance over the whole take, and the model's seven learned
convolutions build the spectrogram. Population variance and an epsilon inside the
root, both pinned by `test/asr_waveform_fixture_test.dart` against the real
extractor. It looks trivial, which is exactly why it has a fixture: sample
versus population variance, or epsilon outside the root, still transcribes
fluently.

A pack naming a third `features` value is refused when it loads rather than fed
features nobody computed.

Labels are characters, in the app's orthography (`ɛ ɔ ŋ ɣ ʋ Ɛ Ɔ`). `AsrEngine`
refuses to offer an answer it cannot spell, so a Dagbani pack without `ɛ` simply
turns voice input off rather than mis-hearing `Ee`. DONDO's inventory
(`KhayaAI/w2v-bert-dga`, `vocab.json`, 39 labels, blank `|` at 0) does spell
`Ee`, `Ayi` and `Mi bɛ mi`.

## What exists on disk, and what it measures

Both Ghanaian models have been exported into this contract and run through the
app's own engine (`ASR_PACK=data/asr_dev/... flutter test
test/asr_native_pack_test.dart --dart-define=RUN_NATIVE_VOICE=true`). The packs
are in gitignored `data/asr_dev/`, because neither is phone-sized yet:

| pack | source | size | median CER, held-out | RTF |
| --- | --- | --- | --- | --- |
| `dagbani_dondo` | `KhayaAI/w2v-bert-dga` int8 | 876 MB | **0.420** Dagbani | 1.89× desktop |
| `twi_akan` | `asr-africa/wav2vec2-xls-r-akan-20-hours` int8 | 355 MB | **0.162** Twi | 0.69× desktop |

The Twi pack was scored with `tool/asr_eval/score_pack.py` on the same eight
held-out clips as the fp32 model and reproduced it exactly (mean CER 0.2075 both
ways, 5 of 8 clips under 0.25), so int8 weight quantisation cost no accuracy.
`openai/whisper-tiny` untuned is at 0.91 / 0.78 and drifts into Arabic, Indonesian
and English on Ghanaian audio.

Two corrections to earlier notes in this repo: the WaxalNLP *labelled* ASR rows
are about 17.8 k (Dagbani) and 12.7 k (Akan) — the ~186 k figures are mostly
unlabelled; and `KhayaAI/DONDO-v1_w2v-bert2_conformer_Dagbani` no longer exists
on the Hub (404), which is what `tool/track_b/eval_voice.py` defaulted to.

## It hears real audio now, and here is what that found

`test/asr_native_pack_test.dart` opens each pack exactly as the app does and
scores actual spoken answer words from `data/closed_set/probe/` (built by
`tool/closed_set/make_answer_probe.py`: the app's own MMS voices saying `Ɛyɛ`,
`Aane`, `Nni`, `Mmo`, `Ee`, and the 41 bundled narration sentences as
everything-that-answers-nothing). Five of five Twi yes/no clips and the Dagbani
`Ee` are heard as the right answer.

Getting there surfaced two defects that no mock could have caught:

1. **The encoder was handing the decoder logits.** The graph ends in a linear
   layer, and `CtcDecoder` takes a probability distribution and logs it — so
   every CTC score the app produced was `log(logit)`, which is not a
   log-probability. The symptom was a per-frame score of **+2.1**, and the
   consequences were all the safety: an absolute floor compared against it
   refused nothing, and `meanFrameProbability` (the dictation gate) was always
   above 0.85. `AsrNativeEngine.encode` now applies softmax to each row.
2. **The CTC pass charged a blank frame between every pair of letters.** Only
   identical labels need one. Fixing it moved a correct answer from −17.4 nats to
   −0.003 on a three-frame fixture, and it was not cosmetic: leaving the skip out
   penalises long words more than short ones, so `Minnim` lost to `Yes` by
   construction. Both scoring paths — the app's and the Python harness that set
   the thresholds — are now derived from the same rule, and the harness is
   labelled as the approximation it is.

**What the probe could not do is calibrate a refusal, and the reason is the
probe's shape, not the model's.** Under the corrected decoder the four-second
narration sentences score *higher* per frame (−0.66 to −1.08) than the isolated
answers (−0.83 to −1.61): CTC will find a two-letter word somewhere inside four
seconds of speech every time. So no threshold separates them, the per-language
floors that were briefly written from the broken numbers have been reverted to
one conservative default, and `SpeechConfidence.forLanguage` is left as the seam
where a measured floor will go. What refuses a wrong answer today is the take
itself — the endpointer hands the model one utterance, not a paragraph — plus an
unverified answer set that may only ever propose.

## Running a pack on your own machine

```
python tool/asr_export/build_asr_manifests.py     # hashes packs into data/serve
python -m http.server 8000 -d data/serve          # the pack origin
flutter run -d windows --dart-define=VOICE_PACK_BASE_URL=http://localhost:8000
```

`NativePackStore` accepts loopback HTTP (anything else must be HTTPS), installs
into a `ready-*` revision and verifies every file's sha256 before loading, so
this exercises the same path a real CDN would, without putting 1.2 GB of weights
in git or in an APK.

## What has to happen before this ships

1. **Dagbani needs a better recogniser than DONDO** for anything but the closed
   set. 0.42 median CER and 1.89× is a transcription nobody should sign; the
   route is fine-tuning a small model on the labelled WaxalNLP rows and measuring
   held-out CER before believing it. Twi already clears the bar at 0.16.
2. **Size and latency on a phone.** Both RTF numbers are four threads on a
   desktop. 355 MB is over the store's bundled-asset shape and needs the hosted
   pack path, and a phone's four slow cores are not this machine's four fast ones.
3. **Record the closed set for real.** 10 speakers × 3 answers per language
   (`data/closed_set/record.csv`), one phrase per take. The synthetic probe
   answers "can the decoder rank these words" and cannot answer "what does a
   caregiver's voice sound like on this phone", and the second question is the
   one the floors depend on.
4. Get `Ee / Ayi / Mi bɛ mi` and the Twi forms signed off by a native speaker.
   They are marked `verified: false` in `lib/core/audio/speech_answers.dart`, and
   until then a hearing may only ever propose, never record.
5. Set the two confidence floors in `SpeechConfidence` from that recording set.
