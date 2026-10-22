# CareBridge AI — model & dataset provenance, and what you may say out loud

Every line here is read from files in this repository: `assets/models/research_contracts.json`,
the four `assets/models/*_metrics.json`, the `PROVENANCE.md` files beside each voice/ASR pack,
`assets/models/README.md`, and `pubspec.yaml`. Nothing is reconstructed from memory.
If a judge asks, you can open the file and show them.

---

## 1. The two red flags — deal with these first

**A. Do not say "Dagbani neural voice" and do not say the translations are verified.**
`assets/audio/dagbani_mms/PROVENANCE.md` says, in its own words: *"These are NOT human
recordings and NOT verified Dagbani. The underlying Dagbani translations in
`lib/core/i18n/dagbani_strings.dart` are drafts awaiting a native-speaker sign-off, and the
voice itself is a machine voice."* The bank is **41 clips**, not 43. Say what it is —
it is still a strong story (section 4).

**B. Licence exposure in the repo, today.**
- `assets/tts/dagbani_piper/model.onnx` is **committed to git**, but its own `PROVENANCE.md`
  says: *"Licence: none declared on the hub… Do not commit or publish these weights… this
  directory stays untracked and out of `pubspec.yaml`."* It is not in `pubspec.yaml`, so it is
  **not in the shipped app** — but it is in the repository a judge may open. Either remove it
  from tracking or be ready to say "untracked candidate, not shipped, licence unresolved".
- The Dagbani and Hausa audio banks inherit **CC-BY-NC 4.0** from Meta MMS. Non-commercial.
  Fine for a hackathon and a pilot; it must be replaced with studio recordings before any
  deployment. Say that proactively — it is the answer to "is this deployable", not a weakness.
- `assets/models/translation_hausa/provenance.json` and `translation_twi/provenance.json` are
  **empty files**. The MarianMT models ship in the app (they are in `pubspec.yaml`), so their
  licence needs recording before you claim anything about commercial use.

---

## 2. The four risk models — what they are, exactly

All four are int8 TFLite, ≤20 inputs, run on-device. **All four carry
`clinical_use_allowed: false` in the contract, and three carry `patient_output_allowed: false`.**
The app enforces this, not the slide deck.

| Model | Where the data came from | Licence / source | Evidence actually recorded | What you may say |
|---|---|---|---|---|
| **Neonatal sepsis** (0–59d stream) | **Real patient records**: Mbarara Regional Referral Hospital neonatal sepsis EMR, Uganda. 964 rows (756 positive / 208 negative), age **0–3 days**, vitals + feeding/lethargy signs. CSV: `mbarara_neonatal_sepsis_cases.csv` | Public GitHub mirror (`Helenaden/Neonatal-Sepsis-Prediction`, Dennis et al.), anonymised, no PHI in the mirror | Internal: 5-fold stratified CV, pooled out-of-fold **AUC 0.90** (fold mean 0.9039 ± 0.0326), sens 0.778, spec 0.933. External: PhysioNet 2019 adult ICU, n=4000, **AUC 0.511** | "Our only real-patient model. Cross-validation AUC 0.90 on 964 records from Mbarara in Uganda. We also ran it on an adult ICU dataset on purpose, and it scored 0.51 — near chance — which is what out-of-domain transfer should look like, and we publish that number too." |
| **Pre-eclampsia** (ANC ≥20w) | **Simulator seeded from published Ghana studies** — Adokiya 2022 (anaemia, *Women & Health*, doi:10.1080/03630242.2022.2030450), Charadan 2025 (PIH), Bugri 2023 (HTN), Boafo 2025 (PE meta-analysis) | Citations recorded per-input in `provenance` | Internal hold-out **AUC 1.0** — *circular, the model predicting its own simulator; labelled a sanity check in the repo*. External: **UCI Maternal Health Risk (Bangladesh, n=1006) AUC 0.7365**, sens 0.528, spec 0.961 | "Trained on a simulator whose priors come from four Ghanaian studies. Its internal number is a sanity check, not evidence — we say so in the artifact. The number we lead with is 0.74 AUC on real Bangladeshi patients it never saw." |
| **Child pneumonia** (2–59m) | Simulator seeded from **WHO IMCI 2014** cutoffs + **Baiden 2011** (community health worker under-counting of respiratory rate) | as above | Internal AUC 0.7424 (sens 0.878, spec 0.483). **`external_validation: null`** | "Screening aid. No external validation yet — that is exactly why the recalibration pathway exists." |
| **LBW / SGA** | Simulator seeded from **Adjei-Gyamfi 2023 (Savelugu, Northern Region)**, **Fosu 2013 Northern MICS**, Adokiya 2022 | as above | Internal AUC 0.9646. **`external_validation: null`** | "Its training priors are from Savelugu — the district we are asking to pilot in. It has no external validation, so it does not produce a patient-facing number." |

**Three limits you should volunteer before anyone finds them:**
1. The sepsis model's supported age range is **0–3 days**; the app's newborn stream is **0–59 days**. That is a coverage gap, not a bug to hide.
2. The sepsis cohort is **78% positive**; the app re-anchors the Platt intercept to a **2% Ghana CHPS prior**, so probabilities are expressed for the real population, and discrimination is unchanged. That is a deliberate, documented decision.
3. The contract records `evaluation_kind: legacy_teacher_only` for all four, with the limitation *"published metrics describe the teacher, not an independently evaluated exported model."* The exported int8 artefact has not been independently re-evaluated. **This is the single most likely technical question in the room.**

**Two engineering facts that play very well with software judges:**
- v1.1 fixed a real **train/serve skew**: v1.0 distilled from raw feature scales while the app fed a normalised [0,1] tensor, so every input quantised to ~0. Documented in `clinical_note`.
- The app computes the **SHA-256 of each `.tflite` on first use** and blocks the model if it does not match the metrics file, falling back to a deterministic noisy-OR engine. Tampered weights cannot report "verified".

---

## 3. Speech, language and translation

| Capability | Model | Source | Licence | Shipped? | Measured |
|---|---|---|---|---|---|
| Twi voice | Piper VITS, Stable-Twi `twi-6` | `assets/tts/twi_piper` | **verify before claiming** | **Yes** (in `pubspec.yaml`) | RTF ≈ 0.3 on 2 CPU threads, fp32 80 MB |
| Hausa voice | Piper | `assets/tts/hausa_piper` | **verify** | **Yes** | 77 MB |
| Dagbani voice | Meta **MMS** `facebook/mms-tts-dag` (community mirror `IanKobby/mms-tts-dag-ghana`) generating a **41-clip bank** | `assets/audio/dagbani_mms` | **CC-BY-NC 4.0** | Yes (bank) | machine voice; translations are unverified drafts |
| Dagbani neural voice | `ghananlpcommunity/dagbani_tts-2025_v2` | `assets/tts/dagbani_piper` | **none declared** | **No** — not in pubspec; committed to git against its own instruction | int8 RTF 4.3 (5× too slow) |
| Farmerline Twi voice | `FarmerlineML/main_twi_TTS` | `assets/tts/twi_farmerline` | **CC-BY-4.0** — the only commercially shippable Twi voice found | No — auditioned, RTF 2.6, too slow | documented A/B candidate |
| Dictation, Twi | `asr-africa/wav2vec2-xls-r-akan-20-hours` (300M, int8 355 MB) | Hugging Face | **Apache-2.0** | Yes | **median CER 0.162**, 5 of 8 clips under 0.25 |
| Dictation, Dagbani | `KhayaAI/w2v-bert-dga` (DONDO, 606M, int8 876 MB) | Hugging Face | **Apache-2.0** | Yes | **median CER 0.420** — poor, and the app says so |
| Translation Hausa / Twi | Helsinki-NLP **MarianMT**, exported + int8-quantised to ONNX, runs on-device | `assets/models/translation_*` | `provenance.json` **empty — record it** | Yes | generation + tokenizer fixtures tested |

The measured numbers came from **your own harnesses** (`tool/asr_eval/score_ctc.py`,
`score_dondo.py`, n=8 held-out clips per language, dated 2026-10-20), not from model cards.
That is a legitimate answer to "how do you know": *we measured it ourselves on 8 real clips,
and 8 is too few, which is why we quote it as a median with the sample size attached.*

The app also **refuses to answer when the pack's alphabet cannot spell the word** rather than
mis-hearing it, and **refuses to speak English to a mother who asked for Dagbani**. Both are
real code paths and both are excellent answers to "how is this safe".

---

## 4. "How did the AI system come about?" — the 60-second answer

> "We started from the protocol, not the model. Ghana's IMCI and CHPS rules, WHO growth
> standards, MUAC cutoffs, the immunisation schedule, and nutrient data for foods actually
> sold in Northern markets — that is a deterministic engine where every recommendation prints
> the value, the cutoff and the guideline. Only then did we add learned models, and we put
> them in a contract file that records, per model, where the data came from, what evidence
> exists, and whether clinical use is allowed. Right now that flag is **false for all four**,
> and the app enforces it. One model is trained on real patients — 964 records from Mbarara —
> and cross-validates at 0.90. Three are simulators seeded from Ghanaian literature, so we
> label their internal numbers as sanity checks and lead with external checks where they
> exist. Everything runs on the handset: ONNX and TFLite, no cloud call, SHA-256 verified at
> load, with a deterministic fallback if a model is missing or its bytes don't match. And
> because a simulator is not evidence, we built the way out — de-identified recalibration
> records on-device, exported only by hand under the Kintampo and Navrongo agreements, which
> refit calibration quarterly and, at about 5,000 records with outcome linkage, retrain and
> promote the model to a Ghanaian headline. The version ladder is already in the artefact."

That answer is fully supported by files in the repo. It is also a *better* pitch than an
inflated AUC, because it shows the thing none of the other nine teams will have: a
governance boundary around the model.

---

## 5. Judge questions, and the safe answer

1. **"What accuracy does your model have?"**
   "The sepsis model cross-validates at 0.90 on 964 real records from Mbarara, Uganda — sensitivity 0.78, specificity 0.93. The pre-eclampsia model gets 0.74 on real Bangladeshi patients it never saw. The other two have no external validation, so we don't quote a headline for them."
2. **"Is it validated for Ghana?"**
   "No. That's stated in the contract file and in the UI. The Ghana-specific priors come from published Northern Region studies, and the recalibration pathway with Kintampo and Navrongo is how it earns validation. We're asking for a pilot zone to start that clock."
3. **"Where did the data come from?"**
   "Real patient records from Mbarara via a public anonymised mirror for the sepsis model; the other three are simulators seeded from named, cited studies — Adokiya 2022, Adjei-Gyamfi 2023 in Savelugu, Fosu 2013 MICS, Baiden 2011, WHO IMCI 2014 — with DOIs recorded per input feature."
4. **"Why should we trust a simulator?"**
   "You shouldn't, for discrimination. We use it to get the priors and the feature distributions right, we label the internal score a sanity check, and we ship a version ladder that ends in a real cohort."
5. **"What's in the black box?"**
   "Nothing that reaches a patient. All four models are flagged `clinical_use_allowed: false`, three are flagged `patient_output_allowed: false`, and the rule engine, not the model, decides triage colour."
6. **"How do you know your speech models work?"**
   "We measured them ourselves on held-out clips — Twi dictation at 0.162 CER, Dagbani at 0.420, eight clips each. Dagbani is not good enough yet, and we say so on screen."
7. **"What about the Dagbani voice?"**
   "Today it's 41 on-device clips generated with Meta MMS, and the translations are drafts awaiting a native-speaker sign-off — that's our first ask. We found a Dagbani neural checkpoint but it carries no licence, so we are not shipping it."
8. **"Licences?"**
   "Apache-2.0 for both ASR models, CC-BY-NC for the MMS audio bank which is why it's pilot-only, and the unlicensed Dagbani checkpoint is excluded from the build."
9. **"Why on-device instead of an API?"**
   "Because the connectivity the brief describes is the constraint, and because sending a mother's HIV status to a third party to classify it is a decision we don't get to make for her."
10. **"What breaks first in a real deployment?"**
    "The data. The models need Ghanaian outcome-linked records, and the language content needs a native speaker. Both are in the ask."

## 6. Never say

- "Validated", "clinically proven", "FDA/GHS approved", "90% accurate at detecting sepsis".
- "Dagbani voice" without "machine-generated, awaiting native-speaker review".
- Any number without its dataset and sample size attached.
- "Blockchain", "autonomous diagnosis", or anything implying the app decides care.

## 7. Files to open if pressed

`assets/models/research_contracts.json` · `assets/models/*_metrics.json` (per-model
`provenance` block with full citations and DOIs) · `assets/models/README.md` (how to read the
numbers, and the recalibration ladder) · `assets/tts/*/PROVENANCE.md` ·
`assets/audio/*/PROVENANCE.md` · `assets/asr/README.md` (measured CER table) ·
`tool/train_real_models.py`, `tool/train_model_pack.py`, `tool/evaluate_research_models.py`
(the pipeline) · `lib/core/ml/offline_inference_service.dart` (fallbacks and gating).
