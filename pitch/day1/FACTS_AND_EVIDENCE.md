# CareBridge AI — Facts and Evidence

Every line below is taken from a file in this repository. Where a number is measured, the
artefact that holds it is named. Nothing here is a projection, an aspiration, or a rounded-up
claim. This is the document to read before answering a judge's question, and to hand over if a
judge asks "where did that number come from".

Project prompt: *"Develop a practical, low-connectivity, community-level AI solution that
empowers frontline health workers and caregivers to accelerate maternal, newly born and
under-five survival in Northern Ghana."*

---

## 1. The problem, stated in field terms

- A CHPS compound covers a zone of roughly a thousand-plus residents per frontline worker, in
  districts the code names directly: Savelugu Municipal, Gushegu, Bawku Municipal, Tatale-Sanguli,
  Zabzugu — all Northern or Upper East Region.
- Connectivity is the operating condition, not an edge case. The sync layer is written for
  "ninety seconds of EDGE signal" (`lib/data/sync/sync_service.dart`).
- The paper register records that a referral was missed. It has one field for it, and the reason
  for the miss is never captured — so it is never counted, and never becomes anything anyone can
  act on.
- The barriers are heterogeneous and have different owners. The app's own vocabulary
  (`CareBarrier`, `lib/domain/enums.dart`) is twelve of them: no money for transport, facility too
  far, needs permission from husband or family, no valid NHIS card, no one to mind the other
  children, facility closed or no staff, bad experience at the facility before, prefers
  traditional or spiritual care, fear of injection/surgery/blood test, farm or market workload,
  road flooded or impassable, did not think it was serious.
- Care happens in two places. The worker with the child, and the family at home — and at home the
  languages are Dagbani, Twi and Hausa far more often than English.

## 2. Target users

| User | What they get | Where it is enforced |
| --- | --- | --- |
| **Frontline health worker / CHPS nurse** | household registration, roll call, vitals, IMCI assessment, verdict with weight-based doses, referral, follow-up desk, ranked visit route, community insights, exports | `Permission._fhw` — 12 permissions (`lib/domain/enums.dart:50`) |
| **Caregiver / mother / family** | a guided danger-sign check at home in her language, read back aloud, a care plan, food and milestone support, and the ability to ask for help | `Permission._caregiver` — `viewOwnFamilyOnly`, `runCaregiverTriage`, `recordBarrier`, `requestCare`, `manageOwnFamily` (`lib/domain/enums.dart:64`) |
| **Supervisor / district** | consent, access and review queues; read audit; pattern monitoring; the accountability spine | `lib/presentation/fhw/supervisor_desk_screen.dart`, `consent_events`, `access_ledger`, `server_read_log` |

A family can create its own household before a worker ever reaches it. The repository refuses any
household other than the one the account is bound to, and **no clinical field is writable with
that permission** — the rule is enforced in `care_repository.dart`, not in the UI.

## 3. How the system works

**Two apps, one record, one sync contract, one permission model.** One Flutter/Riverpod codebase,
234 Dart source files, building for Android, iOS, Windows and Web.

The worker's loop:

1. **Register / roll call** — several clinic sessions may be open at once; a family can join the
   session already open for them instead of starting a duplicate; whoever is present is ticked,
   and an absent person is recorded absent rather than skipped (`VisitDao.openVisitsFor`,
   `openVisitForHousehold`).
2. **Measure** — MUAC tape reading, weight on a zone scale, temperature, respiratory rate, pulse,
   height/weight z-scores, haemoglobin, blood pressure, urine protein, fundal height, fetal heart.
   A `measurement_safety_engine` checks plausibility before any dose is calculated.
3. **Assess** — the guideline engines produce a classification, the reason for it, actions and
   doses.
4. **Refer** — a referral is issued with a state machine behind it (section 4).
5. **Follow up** — one atomic write per answer (section 4), which also captures the barrier.
6. **Route** — the day plan ranks the zone by who is due, so a chase visit can be attached to a
   walk the worker is already making.

The caregiver's loop: a danger-sign check in Dagbani/Twi/Hausa/English — **18 triage question
lines and 5 guidance topics, 41 spoken clips per language** (`assets/audio/`,
`speech_bank.dart`) — every answer read back before it counts, a result stage that says what to
do tonight and when to go, and **"ask for help"**, which writes a `care_request` that pushes to
the district and whose answer is pulled back home.

### What decides care

**16 guideline engines** in `lib/domain/engines/`: ANC, postnatal, young infant, child, nutrition,
growth z-scores, immunisation, barrier, nurturing care, vulnerability, treatment response,
trajectory, measurement safety, road-to-health, recommendation, barrier evidence — plus
`protocols/` for stabilisation and dispensing.

- Cited to **WHO IMCI 2014** thresholds and Ghana Health Service practice; 31 IMCI references sit
  inside the engine code.
- Danger signs are **triggers, not scores**. Chest indrawing does not compete with a probability.
- Doses are weight-based against a protocol table.
- `Permission.overrideAiRecommendation` is a real permission, and the override is recorded.
- A case outside a model's training window is **drift-flagged rather than trusted** — a 14-day-old
  is caught by the sepsis model's age window, and a test asserts it.

## 4. The referral system

- **Eight states** (`ReferralStatus`): `issued → travelling → arrived → treated`, plus
  `didNotAttend`, `refused`, `cancelled`, `died`.
- **Arrival is not treatment.** A child confirmed at the facility but untreated stays open on the
  chase list — before the follow-up ledger existed, `arrived` closed the case while the child was
  still sick.
- **Settled means settled.** `treated / refused / cancelled / died` are never reopened by a later
  answer; a later answer is evidence, not a licence to rewrite paperwork.
- **One atomic write per follow-up** — `CareRepository.recordFollowUp`: the answer, the status it
  implies, the barrier behind a failure, the visit that produced it, the next visit, and a chained
  referral for a worsening child. One transaction or none. Keyed on the contact id the screen
  froze when it opened, so a second tap cannot invent a second answer.
- **Verification is bounded.** A facility verifier working from a staff code may confirm only
  `arrived`, `treated` or `died` (`isFacilityConfirmable`). A facility can never record a
  family-side refusal — that belongs to the worker's follow-up answer.
- **Two unanswered visits** escalate a case into a trace, not a bad afternoon.
- **The reason becomes evidence** (`lib/domain/engines/barrier_evidence.dart`): barriers are
  grouped by **distinct households, not report count**, over a **30-day window** because a
  sub-district reports monthly. **Three households** is the pattern threshold. Each pattern names
  the owner of the fix — `household`, `community`, `facility`, `system`, `season` — which decides
  whether it is a sub-district escalation or a next-contact action. `BarrierDao.withinDays`
  previously had no callers; the referral desk now reads it.
- **SBAR handover** is generated from the same record.

## 5. Data protection — security and compliance

**27 named security controls** in `lib/domain/governance.dart`: **15 in place**, **8 in place with
a stated limit**, **4 recorded as not this software's to implement**. 20 of the 27 name a test file
that proves them; 14 state their own boundary.

Storage and destruction
- Whole database is a **SQLCipher** file with a per-installation 256-bit key read back from secure
  storage before use. An install **refuses to encrypt with a key it could not retrieve**.
- Pre-encryption installs migrate by **copy-verify-swap**: every table counted on both sides before
  the original is renamed over; a mismatch leaves the original intact.
- `PRAGMA secure_delete = ON` at every open, on every engine.

Travel of data
- Four declared scopes per table: *device only*, *device and district*, **pushed but never stored
  locally**, *district only*. The credential verifier lives in the third — the derivation that lets
  the cloud authenticate a PIN must not sit beside the record it unlocks.
- A sync whitelist decides what may leave a handset; minimisation happens at the edge; research
  export is field-minimised; **no analytics, no telemetry**.
- Transport policy is enforced **inside the app**, in the one door every request passes through, so
  it holds on web and desktop where no platform TLS configuration exists. Cleartext is permitted
  only in debug or demo builds.

Access and accountability
- Role permissions enforced in the repository; sensitive-record class; break-glass access;
  inactivity lock; screen-capture block; cascade-safe parent writes.
- **Consent stored as history**, an **access ledger** of who read what, tamper-evident trail, chain
  anchoring, district-side read audit and pattern monitoring. These tables are append-only by
  contract and never cascaded from a patient row — deleting a person must not delete the evidence
  that made the deletion lawful.
- Right to erase and right of access carry a statutory deadline.

Frameworks mapped, not name-dropped
- **Ghana Data Protection Act 843** — s.26 security of processed data, s.27 responsibility.
- **HIPAA 45 CFR 164.312** (encryption at rest).
- **OWASP MASVS** — STORAGE, PLATFORM, CRYPTO.

The register is code, not a PDF
- `GovernanceRegister` declares every table's purpose, lawful basis, retention rule and place in
  the access matrix. CI reconciles it against the local schema, `server/schema.sql`,
  `server/src/tables.js` (the sync whitelist) and `server/src/pull.js` (the pull list). Add a table
  without declaring it and the build fails.
- Controls that belong to the district — retention enforcement, controller registration, breach
  notification, impact assessment — are marked `notOurs` with the owner named, not dropped.
- The app states its own weakness on screen: web and desktop have no SQLCipher engine, so the
  posture card says **"not encrypted at rest"** on those platforms rather than claiming protection.

## 6. The AI system

Two deliberately separated layers. **Guideline engines decide; machine learning supports.** Every
research model carries `clinical_use_allowed: false`, and that flag is enforced where the output
enters the runtime — a model cannot issue a clinical instruction.

**Four on-device int8 TFLite models, under 6 KB each** (`assets/models/`, metrics in
`*_metrics.json`, contracts in `research_contracts.json`):

| Model | Training data | Held-out discrimination | Calibration | External check |
| --- | --- | --- | --- | --- |
| Neonatal sepsis `v2.0` | **Real records** — Mbarara RRH neonatal EMR, Uganda, 964 rows (756 positive, 208 negative), age 0–3 days | AUC **0.90**, sens 0.778, spec 0.933 | Platt scaling, Brier 0.411 | — |
| Pre-eclampsia risk `v1.1` | Ghana-prior simulator cohort, 8,000 train / 2,000 test | internal AUC 1.00 *(simulator)* | Brier 0.136 | **UCI Maternal Health Risk (Ahmed M., 2018, Bangladesh-origin), n=1,006 held out: AUC 0.7365**, sens 0.528, spec 0.961, calibrated Brier 0.1846 |
| Low birth weight / SGA `v1.1` | Ghana-prior simulator cohort, 8,000 / 2,000 | AUC 0.9646, sens 0.898, spec 0.901 | Brier 0.241 | — |
| Child pneumonia `v1.1` | WHO IMCI 2014 cutoffs + a measured CHO respiratory-rate under-counting correction | AUC 0.7424, sens 0.878, spec 0.483 | Brier 0.293 | — |

**Method.** Published Northern Region prevalence and risk priors build the cohort; a teacher model
is fit on it; a small dense network is **distilled onto the exact `[0,1]` normalised tensor the app
feeds at inference**; then **post-training int8 quantisation** (scale 0.003922, zero point −128).

**Measurement.** Held-out AUC, sensitivity and specificity at a chosen Youden threshold;
**Platt-scaling calibration with per-bin residual intervals and a Brier score**; **per-feature
z-score drift detection** against the training distribution; artifact shape, quantisation and
`sha256` pinned in a runtime-checked contract.

**Honest limits recorded in the same files.** The sepsis cohort is **78% positive**, so its
specificity partly reflects the class prior; it is a Ugandan cohort and has never seen a Ghanaian
patient. The three simulator models' internal numbers measure how well the student copies the
teacher, which is why the external number is the one that matters. `evaluation_kind:
legacy_teacher_only` is recorded verbatim for the sepsis model.

**The out-of-domain check is deliberate.** Scored against PhysioNet 2019 adult ICU (n=4,000) the
sepsis model returns **AUC 0.5112 — near chance**, which is the correct behaviour for neonates
against adults. A model that failed to notice it was out of its depth would be the dangerous one.

**Sources, pinned with sha256.**
- Mbarara RRH EMR: `github.com/Helenaden/Neonatal-Sepsis-Prediction`
  (`Dennis_Neonatal_Sepsis_D.csv`, `Dennis_Neonatal_Sepsis_N.csv`)
- UCI Machine Learning Repository — *Maternal Health Risk* (Ahmed M., 2018), held out
- PhysioNet 2019 adult ICU (out-of-domain check only)
- Ghana priors: Adokiya et al. 2022, *Women & Health*, `doi:10.1080/03630242.2022.2030450`
  (n=359, Tatale-Sanguli and Zabzugu, Northern Region); Adjei-Gyamfi 2023; Fosu 2013 (Northern
  MICS); Charadan 2025; Bugri 2023; Boafo 2025; Baiden 2011; WHO IMCI 2014
- Full citation blocks per model: `assets/models/*_metrics.json` → `provenance`

**Recommendation.** `recommendation_engine.dart` turns an engine verdict into an ordered action
list with confidence; `offline_narration.dart` renders it in the family's language;
`verdict_feedback_store.dart` and `recalibration_store.dart` keep the correction path, with
research export field-minimised and `clinical_use_allowed: false` blocking any clinical use.

## 7. The lightweight NLP system

**Translation — `marian-v1` contract, ONNX, Apache-2.0**
- `Helsinki-NLP/opus-mt-en-tw` (en → Twi) and `Helsinki-NLP/opus-mt-en-ha` (en → Hausa), each with
  a pinned revision and `weights_sha256` in `provenance.json`.
- Encoder / decoder / projection graphs, ~212–214 MB per pack on disk, delivered as a verified
  pack rather than shipped inside the APK.

**Voice out — `piper-v1`, 4 packs, 37–80 MB**
- `twi_farmerline` 38 MB — `huggingface.co/FarmerlineML/main_twi_TTS`, **CC-BY-4.0**
- `twi_piper` 80 MB — **CC-BY-NC-4.0**
- `hausa_piper` 77 MB — **CC-BY-NC-SA-4.0**
- `dagbani_piper` 38 MB — manifest records **UNLICENSED — do not publish until the author states a
  licence**. Flagged in the pack, not hidden.
- Plus 41 pre-recorded-style narration lines per language in `assets/audio/{dagbani,hausa,twi}_mms`.
  The human-recorded Dagbani pack is `status: recording-pending`, with a rule of two independent
  native-speaker sign-offs before a line becomes `verified`.

**Voice in — `asr-v1`, two recipes, no pack shipped yet**

| Pack | Model | Size | Median CER, held-out | RTF |
| --- | --- | --- | --- | --- |
| Dagbani | `huggingface.co/KhayaAI/w2v-bert-dga` (DONDO), int8 | 876 MB | **0.420** | 1.89× desktop |
| Twi | `huggingface.co/asr-africa/wav2vec2-xls-r-akan-20-hours`, int8 | 355 MB | **0.162** | 0.69× desktop |

- Corpus: **WaxalNLP** (`google-research-datasets/WaxalNLP`) — about 17.8k labelled Dagbani and
  12.7k labelled Akan ASR rows. For scale, `openai/whisper-tiny` untuned sits at CER 0.91 / 0.78 on
  the same clips and drifts into Arabic, Indonesian and English on Ghanaian audio.
- **Two frontends, one contract.** DONDO needs a SeamlessM4T 80-band filter bank, reimplemented in
  Dart and replayed against clips pushed through the real HuggingFace processor — the fixture fails
  past 1e-5 and currently measures **1.7e-6**. The Akan model takes raw layer-normalised samples and
  builds its spectrogram in seven learned convolutions. A pack that ships filter tables it never
  asked for is **refused at load**, not ignored.
- **Recognition is scored, not guessed.** An exact CTC forward algorithm over blank-extended states,
  marginalised over every spellable spoken form of an answer, so a synonym set is one answer.
  Labels are characters in the app's own orthography (`ɛ ɔ ŋ ɣ ʋ`): a pack that cannot spell `Ee`
  turns voice input off rather than mis-hearing it.
- **What real audio proved.** Through the app's own engine, **5 of 5** spoken Twi yes/no clips and
  the Dagbani `Ee` are heard as the right answer. Getting there exposed two defects no mock could
  catch: the encoder was handing the decoder **raw logits** instead of probabilities, and the CTC
  pass was charging a blank frame between **every** pair of letters.
- **What it cannot do.** No threshold separates a spoken answer from four seconds of prose — under
  the corrected decoder the narration clips score *higher* per frame than the isolated answers. So
  refusal comes from the take length and from an answer set that is marked `verified: false`:
  **voice may propose, never record.**
- **Dictation is gated on the measurement, not on the model loading.** Ceiling is CER 0.25. Twi at
  0.162 clears it. **Dagbani at 0.420 is refused** — the app hides the microphone rather than
  transcribing one word in three wrong into a clinical record.

## 8. Storage, sync and offline

- Local database: **schema v12**, **26 tables created**; the district keeps **24**.
- Every clinical write is transactional with its own outbox row, so a half-saved visit cannot exist.
- Sync is **opportunistic and never blocking**: 25-row batches, each marked synced on its own
  success, urgent referrals ahead of routine registrations. No screen waits; no button says
  "upload".
- **Delta pull** with a per-user watermark: caseload merges last-writer-wins, clinical history is
  insert-if-absent, referrals merge on the server's own revision marker. A pull that fails at page
  3 of 5 has committed its earlier pages and advanced nothing, so re-delivery is invisible.
- Device recovery verifies identity locally against the district's salt and hash before pulling any
  caseload. No fabricated accounts outside demo mode.
- **Model and voice packs are a separate plane**: a `ready-*` revision is downloaded, every file's
  sha256 and byte count verified against `model_manifest.json` before load, under a 2 GB cap.
  Anything that disagrees with its contract is refused at open, not at first inference.
- **Honest state:** there is no live district server. `SyncTransport` is the seam and the bundled
  loopback transport exercises the whole pipeline end to end.

## 9. Proof

- **1,239 tests passing, 9 skipped**, across **111 test files** and **234 Dart source files**.
  Clean analyzer. The web build compiles (`main.dart.js` ~5.3 MB).
- Frontends pinned against the tooling that trained them (1.7e-6 / 1e-5 tolerance).
- Safety rules tested as properties: a settled referral cannot reopen; arrival is not treatment; a
  facility cannot record a family refusal; a drift-flagged age is caught; an unspellable answer
  turns voice off; an encrypted install refuses a key it cannot read back; the governance register
  must match the schema, whitelist and pull list.
- Recognition measured on real audio through the app's own engine, not on a mock.

## 10. What is not done (say these before you are asked)

1. No live district server — loopback transport only.
2. ASR packs are 355 MB and 876 MB, in a gitignored dev directory, **not shipped**; voice input is
   switched off by the absence of a pack, not by a feature flag.
3. No native ear has signed off an accent, so every recognised answer stays `verified: false`.
4. The human-recorded Dagbani voice pack is `recording-pending`.
5. Three of four risk models are distilled from Ghana-prior simulators pending a real cohort
   (`v2.0-kintampo-cohort` is the named successor in the version ladder).
6. Nothing here is clinically validated in Northern Ghana, and no model may make a clinical
   decision.
7. The barrier-evidence card has never been verified on a physical device screen — it is covered by
   unit, database and widget tests, not by a field trial.

## 11. The ask

A clinical champion to sign the IMCI / Ghana Health Service mapping · a data-use agreement and an
ethics route to a Ghanaian maternal and neonatal cohort · one district to pilot in for 90 days ·
recording sessions with native Dagbani and Twi speakers · a handset that is not a flagship.
