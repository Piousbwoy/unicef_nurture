# CareBridge AI — Day 1 Deck: Content Only (17 slides)

Copy and facts only. Arrangement, colour, type and spacing are the designer's call.
Every number, DOI, URL and file reference below is read from the repository and must
be reproduced exactly — do not round, abbreviate or "tidy" them.

Coverage: context · problem · architecture · storage · security · referral system ·
worker and caregiver flows · voice and the lightweight NLP system · the AI system
(datasets, technique, confidence, measurement) · its limits · compliance and
accountability.

**Day 1 is about six minutes on stage.** Read the deck as a source of truth to cut
from, not a run sheet. If she needs a shorter deck, cut 2, 4 and 11 — and keep 15.
The limits slide is what earns the other sixteen.

---

## SLIDE 1 · Cover

**Headline**
> We built the part **that comes after** the tick box.

**Sub-line**
> CareBridge AI — offline-first decision support for CHPS workers, and a mother's answer in her own language.

**Speaker notes**
> "A child in Savelugu was referred on the fourteenth. The register recorded that she did not attend. There is no column for what happened next — so nobody was ever asked. Everything I'm about to show you is the part that comes after the tick box."

---

## SLIDE 2 · The context

**Kicker:** THE CONTEXT
**Headline:** Survival in the Northern Region is decided far from a clinic

**Figure 1 — 234**
> maternal deaths per 100,000 live births in Ghana. SDG 3.1 target: under 70 by 2030.
> Source: UNICEF Ghana / MEST Africa hackathon brief.

**Figure 2 — ~30 %**
> of children stunted in the Northern and North East regions.
> Source: same brief.

**Figure 3 — 15–20 %**
> of the Northern Region population carries a sickle-cell allele.
> Source: Kintampo HRC data, 2023, recorded in the app's clinical schema.

**Supporting line**
> Distance here is measured in money for a motorking, in a flooded road, in an elder who has to agree, in a closed health post. The brief names four constraints on frontline care: fragmented records, supply gaps, transport barriers, low connectivity.

**Speaker notes**
> "Three numbers. The first two are from your own brief. The third is why a sickle-cell question sits in the child assessment — one in five carries the trait here. And what kills is rarely clinical alone: it's the road, the money, and a decision that isn't the mother's to make."

---

## SLIDE 3 · The problem

**Kicker:** THE PROBLEM
**Headline:** The record stops where the risk begins

**What a register knows**
- a household is registered
- a visit was attended or not attended
- a referral was written

**What a register does not know**
- whether she reached the facility
- what care was actually given
- whether the child is sitting untreated at home
- why six families in one zone all reported the same closed health post

**Closing line**
> CareBridge is built across the brief's five thematic areas: predicting risk before the crisis (slides 8, 12–15), smarter CHPS workflows (7–8), the last-mile follow-up (9), voice-first caregiver support (10–11), and the hidden barriers (8, 9).

**Speaker notes**
> "A paper register is honest about what it doesn't know — it just never gets to ask. Every gap on the right is a place a child gets lost."

---

## SLIDE 4 · The system

**Kicker:** WHAT WE BUILT
**Headline:** One handset, one district register, one accountability spine

**Layer 1 — on the handset, no network required**
Flutter app · SQLCipher-encrypted SQLite where the platform supports it · Ghana IMCI/CHPS protocol engine · four on-device risk models (TFLite int8) · on-device speech synthesis and neural translation · offline write queue

**Layer 2 — to the district, when a signal appears**
Node.js sync API · MariaDB register · scoped delta pull with watermarks · server-side read audit of what was handed out

**Layer 3 — the accountability spine**
Append-only consent history · hash-chained access ledger · chain anchors the district verifies independently · data-rights queue with a deadline · a privacy register generated from the database schema

**Facts on the face of the slide**
- 2 roles, one app
- 26 local tables, 23 district tables
- **1,239 automated tests passing, 9 skipped, 0 failures**
- works with the network off

**Speaker notes**
> "Three layers. Everything clinical happens on the handset with no network. Sync is a queue, not a dependency. And the third layer is the one nobody else will show you — a record of who looked at a family's file, that the family can read."

> **On the test number:** 1,239 passed / 9 skipped / 0 failures, measured by `flutter test` on 21 October 2026. State the number, not a rounded one. The honest limit, if a judge asks what those tests do *not* cover: the suite runs on a desktop host, which has no SQLCipher engine, so the encrypted copy itself is only exercised on a real Android or iOS device. `lib/data/local/database_conversion.dart` says so in its own header.

---

## SLIDE 5 · Storage architecture

**Kicker:** STORAGE ARCHITECTURE
**Headline:** Two registers, one transaction, and a queue that never lies about itself

**On the handset**
- SQLite, opened under **SQLCipher on Android and iOS**; plain SQLite on web and desktop, with the posture printed on screen rather than hidden
- **26 tables.** The clinical record, the register tally, the consent history and the access trail all live in the same file the worker carries
- Saving an encounter commits the record **and** its sync intent in **one transaction** — or neither commits. A dead battery cannot leave a half-finished child. The pattern is not one lucky call site: it holds across the visit, household, referral, follow-up, consent and rights DAOs, and the code names it plainly — *"Opens a visit and its roll call in one transaction"*
- **`INSERT OR REPLACE` is banned on cascade parents.** Correcting a household's name must not delete its members, their growth curves and their referrals. CI reads the DDL for those parents and fails the build if any is written with a replace again

**To the district, when signal appears**
- Outbox drained in batches of 25, on a 15-minute timer **and** immediately the moment connectivity returns — the listener matters more than the timer, because a CHO walking back into range of a mast should have her morning's work leave the phone within seconds
- Runs are re-entrancy guarded: a timer and a connectivity callback firing together would otherwise double-send and double-count
- A network failure stops the batch instead of burning retry counters on rows that were never going to send, and failing rows stay visible with their last error and a manual retry
- **A field build with no server configured uses `NotConfiguredTransport`, not a stub that accepts everything.** The stub would mark every record synced, drop it from the pending queue, and let the UI claim the district had it. Records stay honestly pending
- Pull is a **scoped delta**: six tables, ordered so parents arrive before children, `pull_updated_at` after the caller's watermark, paged by cursor with a clamped page size. A malformed watermark returns a 400 instead of quietly becoming a full-district pull
- Scope is enforced server-side: a caregiver receives exactly her bound household; a worker with no region on her account receives only her own rows — an honest narrow page beats an unbounded one
- Users returned by the API are scrubbed: never `pin_hash`, never `pin_salt`

**The integrity rules**
- Push and pull are **separate lists**. Consent, the access trail, the anchors and the rights queue go up and never come back down onto another handset
- Every writable table and column is declared in one file; anything not on that list is rejected, so a compromised handset can write only what the app itself writes
- The server records what **it handed out** — scope, counts, watermark — in a table no client may write to
- The register reconciles these four artefacts — local schema, district schema, write whitelist, pull list — in CI. An undocumented widening of the pull stream fails the build

**Speaker notes**
> "Offline-first is not a feature, it is a set of promises about what happens when there is no network. One write, so nothing is half-saved. One queue, so nothing is claimed as sent. And a transport that refuses to pretend a server exists."

---

## SLIDE 6 · Security on the handset

**Kicker:** SECURITY
**Headline:** The app tells the truth about its own protection

**At rest**
- SQLCipher where the platform supports it. **Three distinct plaintext states are named separately**, not collapsed into one warning: this platform has no encryption engine · this register predates the control · this device would not keep a key
- *"The app refuses to use a key it cannot store: that does not protect a database, it makes the database unopenable."*
- Pre-encryption installs are converted by **copy-verify-swap**: the plaintext is copied to an encrypted file at a side path, every table is counted on both sides, and only a match renames over the original. A refusal or a mismatch leaves the register untouched with its rows intact. It is not attempted automatically on a midwife's phone at 3am while she holds an unsent register
- `PRAGMA secure_delete = ON` at every open on every engine — because SQLite otherwise leaves deleted rows readable in the file until they are overwritten, so "the record was deleted" is a claim about bytes, not a fact. Stated limit: it overwrites within the file; it cannot reach blocks the filesystem already relocated

**In transit**
- One rule enforced at the single HTTP door: **https required**, with a loopback exception that must be switched on deliberately by a test or a developer build. Android additionally refuses cleartext in its platform configuration
- The code rule is what protects the web, iOS and desktop builds — the manifest only governs Android, which is why the check lives in the client and not only in configuration
- No analytics, crash-reporting or advertising dependency is permitted in the manifest, and CI fails if one appears. The only outbound traffic is to the district the account is configured for

**Who is holding the device**
- A stretched local verifier on the handset; the cloud authenticates against a **domain-separated derivation** of it, in its own table, never in the synced user row — whose server-side copy has no PIN columns at all
- **A watchdog per role.** A field worker's session locks on an idle window and after enough time backgrounded, evaluated on resume rather than by timer, because Android suspends Dart timers
- A caregiver's own handset is deliberately **not** locked on idle: the person holding it is the data subject, and a lock that stops a mother reaching infant-feeding advice at 3am is a worse outcome than the risk it prevents
- `FLAG_SECURE` in every non-debug build, so capture is refused by the operating system rather than asked nicely of the user. Stated limit: it stops the OS, not a second phone photographing the screen

**The line to finish on**
> Security posture is computed at runtime from the engine that actually opened the file, and printed on the profile tab and the supervision desk with its reason. **There is no constant in this app that says "secure".**

**Known gap, volunteered rather than discovered**
> There is no key rotation and no escrow. A handset that will not keep a key produces an honest unencrypted register; there is not yet a district-side procedure to re-key a device that has already issued one.

**Speaker notes**
> "The most common compliance failure in software is a shield icon claiming encryption the build does not have. Ours is computed from the engine that actually opened the file. If it cannot encrypt, the app says so, on screen, to the worker. And I'll tell you what we have not built: key rotation and escrow."

---

## SLIDE 7 · The worker's day

**Kicker:** THEMATIC AREA · SMARTER CHPS WORKFLOWS
**Headline:** Every morning the day plans itself — and every position has a reason

1. **Unconfirmed urgent referrals first** — "referred 14 Oct, arrival not confirmed"
2. **Overdue newborn visits** — "day 9 of 14, never weighed"
3. **Missed antenatal contact** — "ANC 4 overdue by 11 days"
4. **Households with an open barrier** — "no money for transport, reported twice"
5. **Immunisation and growth defaults** — "6-week vaccines not given"

> The reason is printed under every line, because a ranked list a worker cannot argue with is a list she ignores.

**Also on this slide**
- The daily register tally counts **children, not assessments**, keeps maternal records out of the under-five columns, and never counts a positive outside its test
- It is **this worker's own day on this device** — a starting point for the paper register, not the facility's total, which also holds colleagues' work and anything recorded on paper alone
- On a shared handset, one worker's column is not shown to another

**Speaker notes**
> "Not by memory, not by proximity — by what is most likely to harm someone this week. And the tally knows whose day it is: two CHOs, one phone, two separate columns."

---

## SLIDE 8 · The visit

**Kicker:** THEMATIC AREAS · RISK BEFORE THE CRISIS · THE HIDDEN BARRIERS
**Headline:** One encounter, in the order care actually happens

1. **What's getting in the way?** The visit opens on barriers — transport money, a flooded road, the elder who must agree. Not on a form. The barrier engine runs **before** a referral is issued, predicting which barriers are most likely to stop this one, each with a stated basis and a preemptive action
2. **Who is here today?** Roll call. The child who was not brought is the child who never gets measured, so absence is recorded, not skipped
3. **Right protocol, by age.** Chosen from the child's age and re-derived as they grow: a six-week-old moves off the newborn pathway onto IMCI on its own
4. **A plan, not a paragraph.** Feeding from local seasonal foods with measured nutrient coverage, the vaccines actually due, and a referral that names the facility for the job
5. **Saved offline in one write.** The record and the intent to sync it commit in the same transaction, or neither

**On the vulnerability engine**
- Bands carry an action — "See today", "See this week" — and every point is attached to a named, sourced weight, so a CHO can see the whole arithmetic and disagree with a line of it
- **Completeness is printed with the score:** "this score is built on 6 of 12 things"
- Modifiable and fixed risk are separated: a 40 made of distance and poverty needs a different response from a 40 made of missed contacts and untreated anaemia
- **Absent data raises uncertainty and never lowers risk.** A household nobody has measured is not a safe household
- Weights come from published epidemiology, not fitted parameters, because there is no Northern Ghana training set we could honestly fit to — and the app says so

**Speaker notes**
> "The barrier question comes first, while the family is still standing there. Two days later, transport money is a statistic. And the score tells you how much of it we actually know, and which half you can change this week."

---

## SLIDE 9 · The referral system

**Kicker:** THEMATIC AREA · SOLVING THE LAST-MILE FOLLOW-UP
**Headline:** Did she arrive? And then what?

**Today's paper loop**
- Referral issued
- Attended ☐  Not attended ☒
- Nothing after this. No question is ever asked of the facility, and none of the family.

**What CareBridge records instead**
- **Arrival confirmed** at the facility, by reference code, by name and time
- Follow-up contact: **what care did she actually get**
- Condition recorded — better · same · worse · died · not seen
- **Chained escalation** when the answer is "sent home untreated"
- Barriers recorded in the family's own words, and whether they were resolved

**How the loop is closed honestly**
- Referral codes are four characters from an ambiguity-safe alphabet, collision-checked against a UNIQUE index and widened if the space ever fills — short because a facility reads them off a slip or hears them down a crackly phone line
- A facility confirmation accepts only the three outcomes a witness can actually see — arrived, treated, died — records the verifier by name, and **never reopens a settled case**
- The follow-up check-in asks four questions and **derives** the referral's status from them; a worker is never asked to pick a status
- SBAR handover is composed from records that already exist, and the clinic queue is a ticket per open session in arrival order — no new schema for either

**Punch line**
> Six households reporting the same closed facility becomes one line item the district can fix — not six excuses in six registers.

**Ceiling we state rather than hide**
> There is no facility role in this build. Arrival is confirmed by the health worker, usually after a phone call. The district sees the confirmation; the facility never touches the system. Closing that loop needs a kiosk or lookup mode on a facility handset.

**Speaker notes**
> "This is the column that was never there. We confirm arrival, then ask the question nobody asks — what care did she actually get? If the answer is sent home untreated, it escalates on its own. And I'll tell you the honest limit: the loop closes on a worker's phone, not on the facility's system. That is the first thing a pilot has to fix."

---

## SLIDE 10 · The caregiver's side

**Kicker:** THEMATIC AREA · VOICE-FIRST CAREGIVER SUPPORT
**Headline:** A mother's app, for a mother who may not read yours

- **Bound to one family.** A caregiver signs in with a family code that binds the account to exactly one household on the day it is created. There is no search box and no route to another family's file
- **Three answers, never a diagnosis.** A danger-sign check-in — yes, no, or *not sure* — returns one of three: go now · see the nurse soon · keep going. The app never says what the child has
- **Deliberately conservative.** Only a completed all-no check is routine. One "not sure" prevents reassurance. Every positive sign is urgent even on a partial check, and a healthy arm-tape reading **never downgrades a reported danger sign**
- **Speaking, not writing.** Guidance is read aloud on the handset in Dagbani, Hausa or Twi. If a mother asks for Dagbani, the app refuses to read English aloud and let her believe it was her language
- **Asking for help is a record.** A request raised from an urgent check queues out of the device in the same transaction; a second tap returns the first request rather than summoning two workers; an answered request cannot be withdrawn over the reply

**Speaker notes**
> "Her scope is fixed the day the account is made. She gets three answers, one of which is 'go now', the app will never reassure her on a partial check, and it will not read her English and call it her language."

---

## SLIDE 11 · The lightweight NLP system

**Kicker:** THEMATIC AREA · VOICE, IN THREE LANGUAGES, WITH NO CLOUD
**Headline:** It has to speak the language and survive the network

**The chain, in the order the app tries it**
1. **Recorded sentence bank** — 41 clips per language, Dagbani · Hausa · Twi; folder per language, language-neutral clip ids
2. **On-device Piper / VITS synthesis** — Twi (`twi-6`) and Hausa, running on the same ONNX runtime as translation, so no second native dependency
3. **System device TTS** as fallback, then readable text
4. **Neural translation upstream** — Helsinki-NLP OPUS-MT MarianMT, encoder + decoder + projection exported to ONNX and int8-quantised, running on the handset

**Constraints we honour**
- One shared ONNX runtime across translation, synthesis and speech input; the planned sherpa-onnx route was dropped rather than ship a second native dependency
- No per-utterance cost and no cloud call — a mother's danger-sign question never leaves the phone to be spoken
- Never a wrong-language fallback, and no answer the pack's alphabet cannot spell: the app refuses rather than mis-read or mis-hear
- Honest labelling: the Dagbani bank is a **machine voice generated with Meta MMS over wording that is still a draft awaiting a native-speaker sign-off**, and the UI says so. A Dagbani neural checkpoint exists on disk but carries **no declared licence**, so it is not in the build. The MMS voices are **CC-BY-NC**, which is why this is a pilot and not a product

**Measured, on our own harness** (`tool/asr_eval`, 8 held-out clips per language, 2026-10-20)
> Twi dictation median **CER 0.162**, 5 of 8 clips under 0.25 · Dagbani median **CER 0.420** — not good enough as an input, and the app says so · Twi synthesis **RTF ≈ 0.3** on two CPU threads · model weights verified SHA-256-identical to the upstream release; eight community fine-tunes auditioned and rejected

**Speaker notes**
> "One runtime, three languages, no cloud. And the part I'd ask you to notice: it will not read English to a woman who asked for Dagbani, and it tells her the Dagbani wording is still a draft. Our first ask is a native speaker to fix that."

---

## SLIDE 12 · The AI — architecture

**Kicker:** THE AI · HOW IT IS PUT TOGETHER
**Headline:** The protocol is the referee. The models raise concern.

**Deterministic and auditable — the rule engine**
- Ghana IMCI / CHPS danger-sign classification and the WHO young-infant assessment
- WHO growth-standard z-scores, MUAC cut-offs, bilateral oedema and palmar pallor
- Immunisation schedule and catch-up logic
- Nutrient coverage computed from foods actually sold in Northern markets
- Pre-eclampsia and postnatal sign clusters from the Maternal Health Record Book

**Learned, on the handset — four TFLite int8 models**
- Neonatal sepsis (0–59 d stream) · child pneumonia (2–59 m) · pre-eclampsia (ANC ≥20 w) · LBW/SGA
- Each ships with a metrics file recording dataset, SHA-256, calibration, validation and citations — and **the app reads that same file at runtime**
- Every recommendation prints the value, the cut-off it crossed and the guideline it came from
- A *what would change this* counterfactual is shown with the verdict
- Determinism is a test: the same record must produce the identical index and narrative, and measurements just inside a cut-off must grade near zero

**Integrity, enforced in code**
> The app computes each model's SHA-256 at load and **blocks** it on mismatch, falling back to a deterministic noisy-OR engine. Triage colour is decided by the rules: the selector ORs AI risk with clinical danger signs, so a model can raise concern but can never downgrade a red flag.

**Speaker notes**
> "We started from the protocol, not the model. The learned layer adds a graded risk on top, and it is fenced — tampered weights cannot report as verified, and a model can never overrule a danger sign."

---

## SLIDE 13 · The AI — datasets and provenance

**Kicker:** WHERE THE DATA CAME FROM
**Headline:** Every training source is recorded in the artifact, per model

| Model | Data actually used | Link / DOI | n | Setting |
|---|---|---|---|---|
| Neonatal sepsis | **Real patient records** — Mbarara Regional Referral Hospital neonatal admissions EMR, Uganda (756 cases / 208 controls) | `https://raw.githubusercontent.com/Helenaden/Neonatal-Sepsis-Prediction/main/Dennis_Neonatal_Sepsis_D.csv` and `…_N.csv` | 964 | Mbarara RRH, Uganda |
| Pre-eclampsia | Boafo 2025, pre-eclampsia in Ghana — systematic review and meta-analysis | doi:10.1002/hsr2.72622 | 14 studies | Ghana, 2015–2025 |
| Pre-eclampsia | Bugri 2023, hypertensive disorders and pregnancy outcomes | doi:10.3390/ijerph20126153 | 843 | Tamale Teaching Hospital |
| Pre-eclampsia | Charadan 2025, pregnancy-induced hypertension | doi:10.4236/oalib.1113362 | 115 | Tamale Teaching Hospital |
| Pre-eclampsia | Adokiya 2022, third-trimester anaemia | doi:10.1080/03630242.2022.2030450 | 359 | Tatale-Sanguli + Zabzugu, Northern Region |
| LBW / SGA | Adjei-Gyamfi 2023, maternal risk factors for low birthweight | doi:10.1186/s41043-023-00443-0 | 356 | **Savelugu municipality, 2022** |
| LBW / SGA | Fosu 2013, low birth weight and associated maternal factors | iiste.org/Journals/index.php/JBAH/article/view/6341 | 10,963 | Ghana MICS 2011, national + regional |
| LBW / SGA | Abubakari 2023, dietary habits and gestational weight gain | doi:10.11604/pamj.2023.44.19.38036 | 316 | Tamale Metropolis |
| Child pneumonia | WHO IMCI Chart Booklet 2014 (pneumonia cut-offs) with Opiyo 2011, signs of severe illness in 0–59 d | doi:10.1136/adc.2010.186049 | — | WHO + systematic review |
| Child pneumonia | Baiden 2011, under-five clinical assessment in rural Ghana — respiratory-rate under-counting correction | doi:10.1371/journal.pone.0028944 | 1,983 | Kintampo, 10 health centres + 5 district hospitals |
| External checks for all four | UCI Maternal Health Risk Data Set (Ahmed M., 2018) and PhysioNet 2019 adult ICU challenge | held out, never used for training | 1,006 / 4,000 | Bangladesh · adult ICU, out-of-domain |

**Footnote**
> Recorded per model in `assets/models/*_metrics.json`. Speech and translation models: `KhayaAI/w2v-bert-dga` and `asr-africa/wav2vec2-xls-r-akan-20-hours` (both Apache-2.0), Helsinki-NLP OPUS-MT MarianMT exported to ONNX, and Piper/VITS voices. Licences are recorded in each pack's `PROVENANCE.md`.

**Speaker notes**
> "One model is trained on real patient records — 964 neonatal admissions from Mbarara. The other three are simulators seeded from Ghanaian studies, and every prior is a citable paper with its sample size and its district attached. Two of them are Savelugu and Tamale — the district we are asking to pilot in."

---

## SLIDE 14 · The AI — technique and measurement

**Kicker:** TECHNIQUE AND MEASUREMENT
**Headline:** Distilled, calibrated, quantised — and scored on data it has never seen

**How each model was produced**
1. A teacher model is fitted per task; a **student MLP is distilled** from it
2. Training and serving use the **same `[0,1]` SCHEMA_NORM tensor** the app feeds at inference. v1.0 distilled from raw feature scales, so int8 quantisation clamped every input to about zero — a train/serve skew, found, fixed and documented
3. **Platt scaling** fitted on out-of-fold predictions; the A and B coefficients ship in the metrics file
4. **Prior re-anchoring:** the sepsis Platt intercept is shifted by −5.1823 logits so probabilities express P(sepsis) at the **2 % Ghana CHPS prior**, not the 78 %-positive hospital cohort. Discrimination is unchanged
5. **Post-training int8 quantisation** — each model is a 5 KB TFLite file with a pinned SHA-256
6. **Uncertainty:** a 95 % CI from per-bin Platt-residual standard deviation, plus a **conformal band**, `q95 = 0.9955` on the sepsis model, published in the same file
7. **Drift detection:** per-feature z-score against the normalised training distribution

**What was measured, and what it means**

| Model | Internal | External, unseen data | The verdict we publish |
|---|---|---|---|
| Neonatal sepsis | **AUC 0.90** — 5-fold stratified CV, pooled out-of-fold; fold mean 0.9039 ± 0.0326 · sens 0.778 · spec 0.933 · Youden J 0.711 | PhysioNet adult ICU, n=4,000: **AUC 0.511** | Real-data discrimination. The 0.511 is a deliberate out-of-domain transfer check — near chance is the expected result, and we ship the number |
| Pre-eclampsia | AUC 1.000 — **circular: the model predicting its own simulator. A sanity check, not evidence** | UCI Maternal Health, n=1,006: **AUC 0.7365** · sens 0.528 · spec 0.961 · Brier 0.185 | We lead with 0.7365, not with 1.000 |
| Child pneumonia | AUC 0.742 · sens 0.878 · **spec 0.483** | none yet | Weak specificity. Screening aid only |
| LBW / SGA | AUC 0.965 · sens 0.898 · spec 0.901 | none yet | Internal number is a simulator self-check; no patient-facing output |

**Speaker notes**
> "Distilled student, Platt calibration, prior re-anchoring from a hospital cohort to a two-percent community prior, int8 quantisation, and a conformal band we publish even though ours is nearly useless at that prior. We score on data the model never saw, and where the internal number is circular we label it circular. Two of these four have no external check at all."

---

## SLIDE 15 · What we do not claim

**Kicker:** LIMITS, STATED BY US BEFORE ANYONE FINDS THEM
**Headline:** None of this is validated for a Ghanaian facility

- All four models carry **`clinical_use_allowed: false`** in their contract file, and three carry **`patient_output_allowed: false`**. The app enforces the flag; it is not a slide promise
- Evaluation is recorded as **`legacy_teacher_only`**: published metrics describe the teacher, not an independently re-evaluated exported int8 model
- The sepsis model's real cohort is **age 0–3 days**; the app's newborn stream runs to 59 days. A coverage gap, stated
- Thirteen features absent from that cohort are learned as constants; the WHO/GHS rules cover those red lines at runtime. Population transfer from Uganda to Northern Ghana is **unvalidated**
- The path out is already built: de-identified recalibration records created on-device → exported by hand under the Kintampo HRC / Navrongo HDSS agreement → quarterly Platt refit → at roughly 5,000 outcome-linked records, retrain and promote. The version ladder is in the artifact: `v1.1 → v2.0-kintampo-cohort → v3.0-prospective-pilot`

**The research export, because that is where trust is won or lost**
> The export carries **no direct identifier at all**: a salted SHA-256 for linkage, district instead of community, month instead of date, age band instead of birthday, and only the numeric inputs the model consumed. The device is armed with a salt **GHS issues and which does not ship with the app**; an unarmed device collects nothing, and revoking the salt stops collection immediately. Residual risk named plainly: whoever holds the salt can join two batches of the same child, which is exactly why the salt stays with GHS.

**Speaker notes**
> "We are not claiming a validated clinical AI. The contract file forbids clinical use and the application obeys it. What we built is the mechanism that turns that into evidence — a recalibration pipeline with a research partner, a salt we do not hold, and a version ladder only a real Ghanaian cohort can advance. That is the pilot we're asking for."

---

## SLIDE 16 · Compliance and accountability

**Kicker:** FOR THE DISTRICT AND THE REGULATOR
**Headline:** A privacy register that is code, and a trail the family can read

**Built against Ghana's Data Protection Act 2012 (Act 843)**
- Sections cited where they apply: **s.24** registration of data controllers · **s.26** security of processed data · **s.37** special personal data. HIPAA and GDPR articles are mapped alongside, so a reviewer with either background can find their control
- **27 controls in the register: 15 in place, 8 in place with a stated limit, and 4 recorded as not this software's to implement** — retention periods, controller registration, breach notification, and the impact assessment, each with the owner named
- The register is generated from code and reconciled against four artefacts that are not opinions. **A table with no declared purpose fails the build, and so does a purpose whose table has disappeared**
- The document a district reads is the render output of that register, and the test fails when the checked-in file stops matching a fresh render. **The document cannot be edited into a lie.** It deliberately carries no generation date, because a timestamp would make it differ from itself every day and turn the check back into a PDF nobody reads

**A mother can see who opened her record**
- Each access entry carries the hash of the one before it, keyed with an HMAC secret held in secure storage and **never transmitted**. The DAOs expose no update and no delete, and the trail is never cascaded from a patient row
- **Every tenth entry the device commits its chain position — sequence, head hash, entry count — to the district**, out of band from the entries themselves. Database triggers make that table append-only with no privilege granted to the connection, so the server cannot be talked into revising a commitment
- Stated to an auditor as plainly as it should be: an anchor proves nothing was removed **after** it was sent. A device determined to lie from its very first entry can anchor a fiction. Closing that last gap needs a key the device does not hold alone — a decision for the district's PKI, not something to invent in a migration
- The district also logs what it **handed out**: the sharper exposure is not who changed a record, it is who downloaded how many records onto a handset that leaves the compound in a pocket

**Decision, not ceremony**
- Every read goes through a policy decision point that returns a **basis** — care relationship, consent, emergency, official authority — and every repository asks it before it touches a data layer. The decision, not the button, is the control
- **Protected records** — HIV or STI status, adolescent reproductive health, violence, mental health — open without a reason only for the worker responsible for them. Anyone else must say why, in words, and **that reason is shown to the family**. The marking lives on the person row so it travels with the data: a handset that never saw the marking still enforces it
- **Care is never blocked by a record.** Where policy would refuse, the screen asks for a reason, grants it for the length of the sitting, and files the reason as the basis. Refusals are recorded too, so the trail shows the attempt as well as the access. Honest limit: a reason is a deterrent and a record, not a verification
- Two aggregate questions asked of the trail — who opened an unusual number of unrelated families in a day, and which protected record was opened by several workers — reported as **shapes worth a conversation, not accusations**. Both detectors have ordinary explanations: a shared caseload, a campaign day, a family that moved

**Rights that are work, not a checkbox**
- Erasure removes every direct identifier — name, phone, NHIS number — and keeps the clinical history **without names**, writes the act itself into the trail, and closes the request only when those have happened. Statutory retention is not this software's to decide, and the screen says so to the family in those words
- Consent is append-only history: scope, decision, which version of the notice was read out, the language, and an optional **voice artefact for a family who cannot read**. A withdrawal supersedes without erasing the grant, because if the row is overwritten the record no longer shows that the care given in between was authorised
- The request and its answer are queued **out** of the device in the same transaction that records them, the desk counts days against the same constant the notice promised, and an overdue item is marked late in words as well as in colour

**Speaker notes**
> "Last slide for the district and the regulator. Twenty-seven controls, and four of them say plainly that they are the controller's job, not ours. A privacy register that fails the build when the schema drifts. A trail the worker who wrote it cannot quietly rewrite, with anchors the district checks itself — and I'll tell you the limit of those anchors before you ask. One family's HIV result travels with a marking a handset enforces even if it never saw the rule."

---

## SLIDE 17 · The ask

**Kicker:** WHAT WE NEED
**Headline:** One CHPS zone, six months, and a language officer

> **A pilot, not a cheque.**
> One CHPS zone in the Northern Region. Six months. A **GHS-issued export salt**, a **native-speaker reviewer for the 41 Dagbani sentences**, and an **outcome-linked cohort** — so the models, and the Dagbani, are written by the people they belong to.

**What the district gets out of it**
- A recalibration path that turns `clinical_use_allowed: false` into evidence with a version number on it
- Barrier patterns as counts the district can act on, rather than six explanations in six registers
- An access trail, an anchor checker and a processing register that answer the regulator instead of describing the product

**Speaker notes**
> "We are not asking for funding. We are asking for a zone, six months, a salt only GHS should hold, a native speaker, and outcome-linked records. Thank you."

---

## Facts a judge may probe, and where they come from

| Claim | Where it is recorded |
|---|---|
| 1,239 tests passing, 9 skipped, 0 failures | `flutter test`, full suite, 21 October 2026 |
| 26 local tables, 23 district tables | `lib/data/local/app_database.dart`, `server/schema.sql` + migrations — reconciled automatically by `test/governance_test.dart` |
| Record + sync intent commit in one transaction | `db.transaction` wrapping `OutboxDao.enqueue` in `lib/data/local/visit_dao.dart`, `household_dao.dart`, `compliance_dao.dart`, `care_request_dao.dart` |
| `NotConfiguredTransport` keeps records honestly pending | `lib/data/sync/sync_service.dart` |
| Scoped delta pull, watermark, cursor, page clamp, FK ordering | `server/src/pull.js`, tested by `test/pull_service_test.dart` |
| Write whitelist rejects anything undeclared | `server/src/tables.js`, `test/sync_no_server_test.dart` |
| Read audit of what the server handed out | `server/src/read_audit.js`, `server/migrations/009_hardening.sql` |
| SQLCipher on Android/iOS only; three named plaintext postures | `lib/data/local/db_engine_io.dart`, `lib/data/local/app_database.dart`, `test/encryption_posture_test.dart` |
| Copy-verify-swap conversion | `lib/data/local/database_conversion.dart`, `test/database_conversion_test.dart` |
| `secure_delete` at every open | `lib/data/local/app_database.dart`, `test/hardening_test.dart` |
| https enforced at one door | `lib/data/sync/transport_policy.dart`, `lib/data/sync/http_client.dart`, `test/transport_policy_test.dart` |
| Credential separation, no PIN columns server-side | `lib/data/local/user_dao.dart`, `server/src/auth.js` |
| Role-aware idle lock; caregiver exempt on purpose | `lib/core/auth/idle_lock.dart`, `test/idle_lock_test.dart` |
| FLAG_SECURE in non-debug builds | `android/app/src/main/kotlin/gh/carebridge/carebridge_ai/MainActivity.kt` |
| 27 controls, maturity split 15 / 8 / 4 | `lib/domain/governance.dart` → rendered into `docs/GOVERNANCE.md` |
| Register reconciled against schema, whitelist and pull list | `test/governance_test.dart` |
| Hash-chained trail, HMAC secret, no update or delete | `lib/domain/compliance.dart`, `lib/data/local/compliance_dao.dart`, `test/accountability_test.dart` |
| Anchors every tenth entry, append-only by trigger | `server/src/anchors.js`, `server/migrations/009_hardening.sql` |
| Policy decision point and protection class | `lib/data/repositories/record_access.dart`, `test/rbac_test.dart` |
| Break-glass reason recorded verbatim; refusals recorded | `test/hardening_test.dart`, `test/accountability_test.dart` |
| Erasure by pseudonymisation, consent as history, rights deadline | `lib/data/repositories/care_repository.dart`, `CareNotice.serviceDeadline` |
| Export minimisation and GHS-held salt | `lib/core/ml/recalibration_export.dart`, `test/recalibration_export_test.dart` |
| Cascade-safe upsert | `lib/data/local/upsert.dart`, `test/cascade_safety_test.dart` |
| Referral codes four chars, collision-checked | `lib/data/local/visit_dao.dart: mintReferenceCode` |
| Only witnessed outcomes, settled cases never reopened | `CareRepository.confirmReferralOutcome`, `ReferralStatus.isFacilityConfirmable` |
| Barrier prediction before the referral | `lib/domain/engines/barrier_engine.dart` |
| Dataset citations and metrics | `assets/models/*_metrics.json`, `assets/models/research_contracts.json` |
| Speech licences and provenance | `assets/audio/*/PROVENANCE.md`, `assets/tts/*/PROVENANCE.md`, `assets/asr/README.md` |

---

## Three things to fix before anyone else reads this

1. **Do not open the in-app "AI Pitch Copilot" during the demo.** `lib/presentation/shared/ai_pitch_copilot.dart` auto-speaks a 1,069-word script — 7.1 minutes at a natural pace, before any tapping — and it narrates *"over 160 automated tests"*, *"a trinity of deterministic rules engines"* with the learned models unmentioned, and *"life-saving precision"*. All three contradict slides 4, 12 and 15. Set `_autoSpeak = false`, or leave the panel closed.
2. **The Dagbani neural weights are committed to git against their own provenance instruction.** `assets/tts/dagbani_piper/PROVENANCE.md` says the licence is undeclared and the file must stay untracked and out of `pubspec.yaml`; `git ls-files` shows `model.onnx` tracked anyway. It is not shipped, but the exposure is real in front of UNICEF and GHS.
3. **One citation in the control register is wrong.** `cascade-safe-parent-writes` cites `OWASP MASVS-RESILIENCE`, which is about resisting device tampering — not silent data corruption. Fix it before a security reviewer reads `docs/GOVERNANCE.md`; the control itself is sound and worth keeping.
