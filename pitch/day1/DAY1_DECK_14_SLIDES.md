# CareBridge AI — Day 1 Deck (14 slides)

**Target:** UNICEF StartUp Lab · AI for Nurturing Care Hackathon · Day 1 presentation slot
**Prompt we are answering:** *"Develop a practical, low-connectivity, community-level AI solution that empowers frontline health workers and caregivers to accelerate maternal, newly born and under-five survival in Northern Ghana."*
**Slot:** ~6 minutes including changeover. The per-slide scripts below sum to **6:22**, which is too long — rehearse to cut. If running late, drop **S6** (0:25) then **S13** (0:18), landing at **5:39**.

**Rules for layout:** the text under `ON SCREEN` is final copy — use it verbatim, do not add, remove or reword facts or numbers. `SPEAK` is the presenter script and does not go on the slide. `BIG NUMBER` is the one figure worth making large. Every number in this deck is taken from a file in the repository and can be produced if a judge asks.

---

## Slide 1 — Title

**ON SCREEN**
> **CareBridge AI**
> A CHPS compound in the Northern Region, with no signal, and a midwife who still knows who is sick.
> Offline-first decision support for frontline health workers and the families they serve.
> Maternal · Newborn · Under-five survival · Northern Ghana
> Team name · Hackathon Day 1 · 21 October 2026

**SPEAK (0:12)**
"CareBridge AI. One sentence: an offline-first clinical companion that lets a CHPS worker in Savelugu assess, refer and follow up without a network — and lets the family ask for help in their own language."

---

## Slide 2 — The problem we built against

**ON SCREEN**
> **The register answers *did they come*. It cannot answer *why they didn't*.**
> - A paper register has one column for a missed referral, and it says DID NOT ATTEND.
> - The reason is a flooded road, a facility closed at 2pm, no NHIS card, no transport money, farm work that could not be left, or a husband's permission.
> - Those reasons decide the next action. Three families saying "the facility was closed" is a staffing fact; one family needing transport money is a visit.
> - Connectivity is not a bonus condition here. It is the condition: work happens on foot, on ninety seconds of EDGE, in a zone of a thousand-plus residents per worker.
> - Care is delivered twice: once by the worker with the child, once by the family at home — mostly in Dagbani, Twi and Hausa, and often not in English.

**SPEAK (0:28)**
"We started from the field, not from a model. The failure in community health is not that nobody assesses — it is that the answer to 'why didn't you go' is collected and then thrown away, and the two halves of care, the worker and the family, never share one record. So we built the whole thing around three constraints: no network, two audiences, and a reason that has to survive the walk."

---

## Slide 3 — What CareBridge is

**ON SCREEN**
> **Two apps, one record, zero required network.**
> - **Health worker app** — roll call, vitals, IMCI-based assessment, verdict with doses, referral, follow-up desk, visit route.
> - **Caregiver app** — a guided danger-sign check at home, spoken in the family's language, with a care plan and a way to ask for help.
> - One local database, one sync contract, one permission model between them.
> - 16 guideline engines plus the stabilisation and dispensing protocols decide care. Machine learning supports, it never decides.
> - Runs on a low-end Android handset. The same code also builds for Windows and the browser.

**SPEAK (0:20)**
"Two apps and one spine. The worker's app is a clinic session. The family's app is a check at home. They share one database design, one permission model, and one sync contract — and both work with the network off."

---

## Slide 4 — The caregiver flow

**ON SCREEN**
> **A mother can run a real triage on a phone she can barely read, in her own language.**
> - Languages: Dagbani, Twi, Hausa, English.
> - 18 triage question lines and 5 danger-sign guidance topics, pre-recorded per language — 41 audio clips in each.
> - A "YES" continues the check; it does not jump to a verdict.
> - Every answer is read back aloud before it counts.
> - The result stage gives what to do tonight, what to watch for, and when to go.
> - **"Ask for help"** — the family can request a worker. `Permission.requestCare` is held by caregivers only and is deliberately not bundled with running the check screen.
> - A family can create its own household before a worker ever arrives. The repository refuses any household but their own, and no clinical field is writable with that permission.

**SPEAK (0:26)**
"The caregiver flow is the part nobody else is building. A mother answers danger signs in Dagbani, hears every answer read back, gets what to do tonight — and if it is serious, she can ask for help herself. That ask is a record with a permission behind it, and it goes to the worker's desk."

---

## Slide 5 — The health worker flow

**ON SCREEN**
> **A clinic session, not a form.**
> - Register a household, hold **several open sessions at once**, call people back in the order they arrived.
> - Roll call: whoever is actually in front of you gets ticked off; a person absent is recorded as absent, not skipped.
> - Vitals on purpose-built instruments: an MUAC tape reading that feeds the verdict, a draggable zone scale for weight, measurement-safety checks before any dose.
> - One verdict screen: classification, the reason for it, weight-based doses, referral when needed — the care plan folded into the same page.
> - EPI status folded into the immunisation section instead of a second list.
> - Day plan and route: the zone ranked by who is due, so a referral can be put on a walk the worker is already making.
> - Supervisor desk: consent, access and review queues, with the coverage limit stated on the screen.

**SPEAK (0:26)**
"For the worker it is a session, not a form. She can hold several visits open, tick whoever is actually in the room, measure with instruments that carry safety checks, and get one verdict with doses in it. And because the route is ranked, a referral can be attached to a walk she was already doing."

---

## Slide 6 — The clinical core: rules decide, AI supports

**ON SCREEN**
> **16 guideline engines. Every decision reproducible from the guideline, not from a weight file.**
> - ANC, postnatal, young infant, child, nutrition and z-scores, immunisation, barrier, vulnerability, treatment response, growth trajectory, measurement safety, nurturing care, road-to-health, recommendation.
> - Cited to WHO IMCI 2014 thresholds and Ghana Health Service practice; 31 IMCI references inside the engine code.
> - Danger signs are triggers, not scores. Chest indrawing does not compete with a probability.
> - Doses are weight-based against a protocol table, and the stabilisation selector fires on clinical danger signs across all ages.
> - `overrideAiRecommendation` is a real permission a worker can use — and the override is recorded.
> - A model that is out of its training window is drift-flagged rather than trusted.

**SPEAK (0:25)**
"This is the part we would defend in front of a clinical reviewer. The decision is made by guideline engines, so any verdict can be traced to a rule, not to a weight file. The models sit underneath as support, and when a case is outside a model's training window, the app says so."

---

## Slide 7 — The referral system: care with a receipt

**ON SCREEN**
> **A referral is a case with a state machine, and every answer leaves a trace.**
> - States: `issued → travelling → arrived → treated`, plus `didNotAttend`, `refused`, `cancelled`, `died`.
> - **Arrival is not treatment.** A child confirmed on a bench and untreated stays open on the chase list.
> - **Settled means settled.** `treated / refused / cancelled / died` are never reopened by a later answer.
> - One atomic write per follow-up: the answer, the status it implies, the barrier behind the failure, the next visit, and a chained referral for a worsening child — in one transaction or in none.
> - A facility verifier working from a staff code can confirm only what they witnessed: arrived, treated, died. A facility can never record a family-side refusal.
> - Two unanswered visits turn a case into a trace, not a bad afternoon.
> - **Barriers become evidence:** the reason is counted by *households*, not reports, and names who owns the fix — household, community, facility, system, or season. Three households is the pattern threshold; the window is 30 days, because a sub-district reports monthly.
> - SBAR handover is generated from the same record.

**SPEAK (0:38)**
"The referral is where most digital tools quietly die: you issue it and never find out. So a referral here is a state machine. Arrival alone doesn't close it, and settled cases don't reopen. Every follow-up answer is one atomic write — status, barrier, next visit, and a second referral if the child got worse. A facility can only confirm what it witnessed. And the reason a family didn't go is now counted across households and routed to whoever can fix it: three families saying the facility closed at 2pm stops being nine missed appointments and becomes one sub-district escalation."

---

## Slide 8 — The AI system: what we trained, and how we measured it

**BIG NUMBER:** `clinical_use_allowed: false`

**ON SCREEN**
> **Four on-device int8 risk models. Total size: under 6 KB each.**

| Model | Trained on | Held-out discrimination | Calibration | Out-of-domain check |
| --- | --- | --- | --- | --- |
| Neonatal sepsis | **Real records** — Mbarara RRH EMR, Uganda, 964 rows (756 positive, 208 negative), age 0–3 days | AUC **0.90**, sens 0.778, spec 0.933 | Platt scaling, Brier 0.411 | — |
| Pre-eclampsia risk | Ghana-prior simulator cohort (8,000 train / 2,000 test) built on published Northern Region prevalence | Internal AUC 1.00 **on the simulator** | Brier 0.136 | **UCI Maternal Health Risk (Ahmed M., 2018), n=1,006, held out: AUC 0.7365**, sens 0.528, spec 0.961, calibrated Brier 0.1846 |
| Low birth weight / SGA | Ghana-prior simulator cohort (8,000 / 2,000) | AUC 0.9646, sens 0.898, spec 0.901 | Brier 0.241 | — |
| Child pneumonia | IMCI 2014 cutoffs + a measured CHO respiratory-rate under-counting correction | AUC 0.7424, sens 0.878, spec 0.483 | Brier 0.293 | — |

> **How they were made:** Ghanaian prevalence and risk priors from published Northern Region studies are used to build the cohort; a teacher is fit on it; a small dense network is **distilled** onto the exact `[0,1]` tensor the app feeds at inference; then **post-training int8 quantisation** (scale 0.003922, zero point −128).
> **How they are measured:** held-out AUC, sensitivity and specificity at a chosen Youden threshold, **Platt-scaling calibration with per-bin residual confidence intervals and a Brier score**, and **per-feature drift detection** as a z-score against the training distribution — a 14-day-old is correctly drift-flagged by the sepsis model, and a test asserts it.
> **How they are gated:** the exported artifact's shape, quantisation and `sha256` are pinned in a contract the runtime checks. `clinical_use_allowed: false` is enforced in code, not in prose — these models cannot produce a clinical instruction.
> **Two honest corrections we already made:** v1.0 distilled on raw feature scales while the app served normalised ones, so every input clamped to about zero — a train/serve skew, fixed in v1.1; and the sepsis cohort is **78% positive**, so its high specificity partly reflects the class prior, not only the signal. It has never seen a Ghanaian patient.
> **The out-of-domain check is a feature:** the sepsis model scored against PhysioNet 2019 adult ICU (n=4,000) returns **AUC 0.5112 — near chance, exactly as it should** for neonates against adults. A model that failed to notice it was out of its depth would be the dangerous one.
> **Sources pinned in the repo:** Mbarara — `github.com/Helenaden/Neonatal-Sepsis-Prediction` (`Dennis_Neonatal_Sepsis_D.csv` / `_N.csv`, sha256 recorded). Anaemia in the Northern Region — Adokiya et al. 2022, *Women & Health*, doi:10.1080/03630242.2022.2030450, n=359, Tatale-Sanguli and Zabzugu. Full citation list per model lives in `assets/models/*_metrics.json` under `provenance`, with dataset and artifact hashes.

**SPEAK (0:45)**
"Four int8 models, each under six kilobytes, because they run on the handset. The sepsis model is trained on 964 real neonatal records from Mbarara; the other three are distilled from Ghana-prior simulator cohorts built on published Northern Region studies — which is why we report the external number, not the internal one: pre-eclampsia is 1.0 on the simulator and 0.74 on held-out UCI maternal data. Every model carries calibration, Brier, a chosen threshold and a drift check, and the contract enforces that none of them is allowed to make a clinical decision. We also documented our own two bugs — a train/serve skew we found and fixed, and a 78-percent-positive cohort that inflates specificity."

---

## Slide 9 — The lightweight NLP system: speech in, speech out, no cloud

**ON SCREEN**
> **Twi and Dagbani are not on Google's speech list. So we ran the models on the phone.**

| Capability | Model | Source | Size | Measured |
| --- | --- | --- | --- | --- |
| Translation en → Twi | MarianMT | `Helsinki-NLP/opus-mt-en-tw` (Apache-2.0) | ONNX encoder/decoder | Contract `marian-v1`, per-file sha256 |
| Translation en → Hausa | MarianMT | `Helsinki-NLP/opus-mt-en-ha` (Apache-2.0) | ONNX encoder/decoder | Contract `marian-v1`, per-file sha256 |
| Voice out | Piper VITS | 4 packs, incl. `FarmerlineML/main_twi_TTS` (CC-BY-4.0); one CC-BY-NC-4.0, one CC-BY-NC-SA-4.0, one held pending its author's licence | 37–80 MB | 41 narration lines per language, spoken offline |
| Voice in — Dagbani | `KhayaAI/w2v-bert-dga` (DONDO), int8 | WaxalNLP | 876 MB | **median CER 0.420**, RTF 1.89× on desktop |
| Voice in — Twi | `asr-africa/wav2vec2-xls-r-akan-20-hours`, int8 | WaxalNLP | 355 MB | **median CER 0.162**, RTF 0.69×; int8 reproduces the fp32 score exactly (mean CER 0.2075 both ways) |

> - Corpus: **WaxalNLP** (`huggingface.co/datasets/google-research-datasets/WaxalNLP`) — about 17.8k labelled Dagbani and 12.7k labelled Akan ASR rows. `openai/whisper-tiny` untuned sits at 0.91 / 0.78 on the same clips and drifts into Arabic, Indonesian and English on Ghanaian audio.
> - **Two ASR recipes, one contract (`asr-v1`):** DONDO needs a SeamlessM4T 80-band filter bank, reimplemented in Dart and replayed against the real HuggingFace processor to under 1e-5 (currently 1.7e-6); the Akan model takes raw normalised samples and builds its own spectrogram in seven learned convolutions. A pack that ships filter tables it never asked for is refused.
> - **Refusal is the safety layer.** Recognition is scored with an exact CTC forward algorithm over all spellable spoken forms of each answer — so a synonym is one answer, not two. Answers must be spellable in the model's own character inventory: a Dagbani pack without `ɛ` turns voice input off rather than mis-hearing `Ee`.
> - **What it can hear today, from real audio:** 5 of 5 spoken Twi yes/no clips and the Dagbani `Ee` are heard as the right answer, through the app's own engine.
> - **What we will not claim:** no threshold separates a spoken answer from four seconds of prose, so nothing is refused by a score — the take length and an unverified answer set are what refuse. Every closed-set answer carries `verified: false` until a native ear signs it off, so voice can only ever **propose** an answer, never record one.
> - **Free dictation is gated on the measurement, not on the model loading:** Twi at 0.162 clears a 0.25 CER ceiling; **Dagbani at 0.420 is refused** — the app hides the microphone rather than transcribing one word in three wrong into a clinical record.
> - **Not shipped yet, and stated as such:** the ASR packs are 355 MB and 876 MB and live in a gitignored dev directory. Voice input is switched off by the absence of a pack, not by a feature flag. Browser builds carry no microphone at all, because ONNX Runtime's FFI cannot compile to JavaScript.

**SPEAK (0:38)**
"NLP is where this project either becomes real or becomes a demo. Twi and Dagbani aren't supported by cloud speech, so translation, voices and recognition all run on-device with pinned sources and licences. We measured recognition on held-out WaxalNLP clips: 0.16 character error rate for Twi, 0.42 for Dagbani — and that second number is why the app refuses to open Dagbani's microphone: at that error rate you cannot put a transcript in a clinical record. It hears real spoken yes and no through the app's own engine today, but the packs are 355 and 876 megabytes, they are not shipped, and we say so."

---

## Slide 10 — Storage architecture: hybrid, and honest about which half is real

**ON SCREEN**
> **Local-first SQLite, with the district as the system of record.**
> - One encrypted database per installation, schema **v12**, **26 local tables**; the district holds **24 tables**.
> - Four declared travel scopes per table: *device only*, *device and district*, ***pushed but never stored locally***, *district only*. A credential verifier lives in the third: the derivation that lets the cloud authenticate a PIN must not sit beside the record it unlocks.
> - Every clinical write is transactional with its own outbox row, so a half-saved visit cannot exist.
> - Append-only by contract, not by trigger: consent events, the access ledger and the audit log are never cascaded from a patient row — deleting a person must not delete the evidence of who read them.
> - Delta pull with a per-user watermark: caseload merges last-writer-wins, clinical history is insert-if-absent, referrals merge on the server's own revision marker, so re-delivery is harmless and device clocks are only ever used for display.
> - **Model and voice packs are a separate storage plane:** a `ready-*` revision is downloaded, every file's sha256 and byte count verified against `model_manifest.json` before it loads, under a 2 GB cap. Anything that disagrees with its contract is refused at open, not at first inference.

**SPEAK (0:26)**
"Storage is one encrypted SQLite file on the handset and the district as the system of record. Each table declares how far its contents travel, and one table deliberately pushes without ever being stored locally. Writes are transactional with their sync row, evidence tables are append-only, and models live on a separate plane where nothing loads that doesn't match its own hash."

---

## Slide 11 — Offline connectivity, and the sync that survives it

**ON SCREEN**
> **The app does not need the network to work. Sync is how records reach the district, not how care is delivered.**
> - Sync is opportunistic and never blocks: it runs when signal appears and on a slow timer. No screen waits, and no button says "upload" as though the worker were responsible for the network.
> - Batches of 25 rows, each committed on its own success — a ninety-second EDGE window still makes progress.
> - Priority ordered: an urgent referral leaves before eighty routine household registrations.
> - Transport policy is enforced **inside the app**, in the one door every request passes through, so it holds on web and desktop too — where no platform TLS config exists to hold it. Cleartext is permitted only in debug or demo builds, and the refusal message tells the worker what to do instead of retrying until the battery dies.
> - A lost handset is recovered by identity first, caseload second: credentials are verified locally against the district's salt and hash, then the worker's own records are pulled down. No fabricated accounts in any build that isn't in demo mode.
> - **Stated plainly, on the device:** there is no live district server yet. `SyncTransport` is the seam; the bundled loopback transport exercises the full push-and-pull pipeline end to end without inventing a backend.
> - No analytics. No telemetry. Nothing leaves the handset that the sync whitelist did not declare.

**SPEAK (0:22)**
"Connectivity is treated as a bonus, never a dependency. Small batches that each commit on their own, urgent referrals first, an in-app transport rule that applies even where the operating system has none, and device recovery that verifies identity before it moves a single record. And we say out loud that the district server is not live yet — the pipeline is real, the backend is a loopback."

---

## Slide 12 — Security and compliance: a register that cannot drift

**ON SCREEN**
> **27 named controls. 15 in place, 8 in place with a stated limit, 4 owned by the district rather than by software.**
> - **At rest:** the whole database is a SQLCipher file with a per-installation 256-bit key read back from secure storage before use. An install **refuses to encrypt with a key it could not retrieve** — that is how records get destroyed by well-meaning software.
> - **Migration:** pre-encryption installs move by copy-verify-swap; every table is counted on both sides and only a match renames over the original.
> - **Deleted is deleted:** `PRAGMA secure_delete = ON` at every open, on every engine.
> - **Access:** role permissions enforced in the repository, not the UI; a family account is bound to one household and cannot write a clinical field; sensitive-record class, break-glass access, inactivity lock, screen-capture block.
> - **Accountability spine:** consent stored as history, an access ledger of who read what, tamper-evident trail, chain anchoring, district-side read audit and pattern monitoring, erasure and access rights with a statutory deadline.
> - **The register is code.** `lib/domain/governance.dart` declares every table's purpose, lawful basis, retention rule and place in the access matrix — and CI reconciles it against the local schema, `server/schema.sql`, the sync whitelist and the pull list. Add a table without declaring it and the build fails.
> - **Frameworks mapped, not name-dropped:** Ghana **Data Protection Act 843** (s.26 security of processed data, s.27 responsibility), **HIPAA 45 CFR 164.312**, **OWASP MASVS** STORAGE/PLATFORM/CRYPTO.
> - **Controls that are not ours to implement are labelled as the district's** — rosters, training, retention enforcement, breach notification to the Data Protection Commission — rather than quietly dropped from the map.
> - **The app states its own weakness:** web and desktop builds have no SQLCipher engine, so the posture card says *"not encrypted at rest"* instead of claiming protection it does not have.

**SPEAK (0:30)**
"Compliance in most projects is a PDF somebody wrote once. Here the privacy register is data in the same language as the system, and the build reconciles it against the schema, the sync whitelist and the pull list — so the document cannot lie about the database. Encryption refuses to proceed on a key it can't read back, deletion is byte-level, permissions are enforced server-side in the repository, and every read is on an append-only ledger. Twenty-seven controls, twenty of them with a test that proves them, and the four that belong to the district are named as the district's instead of hidden."

---

## Slide 13 — How we know any of this works

**ON SCREEN**
> **1,239 tests passing, 9 skipped, across 111 test files and 234 Dart source files. Clean analyzer. Browser build compiles.**
> - **Fixtures, not assertions:** the Dart reimplementation of DONDO's filter bank is replayed against clips pushed through the real HuggingFace processor and fails past 1e-5 — it currently measures 1.7e-6. The raw-waveform frontend is pinned the same way.
> - **Real audio through the app's own engine:** exported packs are opened exactly as the phone opens them and scored on actual spoken answer words. That is how we found two defects no mock could catch — an encoder handing the decoder raw logits instead of probabilities, and a CTC path that charged a blank frame between every pair of letters.
> - **Safety properties are tested, not reviewed:** a settled referral cannot be reopened, arrival never reads as treatment, a facility cannot record a family refusal, a drift-flagged age is caught, an unspellable answer turns voice off, an encrypted install refuses a key it cannot read back.
> - **Governance is reconciled in CI.** If the register and the schema disagree, the build fails.
> - **What is not done, said plainly:** the district server is a loopback; the ASR packs are not phone-sized and are not shipped; no native ear has signed off an accent, which is why every spoken answer is `verified: false`; the human-recorded Dagbani voice pack is `recording-pending`; the risk models are decision support on a `clinical_use_allowed: false` contract; and nothing here has been clinically validated in Northern Ghana yet.

**SPEAK (0:18)**
"We don't ask you to take any of this on faith. One thousand two hundred thirty-nine tests, frontends pinned against the tooling that trained them, recognition scored on real audio through the app's own engine — which is exactly how we caught two bugs a mock would have hidden — and the safety rules tested as properties. And the last line on this slide is the honest one: here is what is not finished."

---

## Slide 14 — Where this goes, and what we are asking for

**ON SCREEN**
> **The next version has a name: a cohort, not a checkpoint.**
> - **v2.0 Kintampo cohort** — replace the Ghana-prior simulators with a real for-purpose dataset; the version ladder is already recorded per model.
> - **A Ghanaian recogniser that earns the microphone** — Dagbani needs a better model than DONDO for anything but a closed set, and the closed set needs recording by real speakers to calibrate refusal.
> - **A Dagbani and Twi voice a native ear signs off**, and a phone-sized ASR pack: distillation and quantisation, the same route the 6 KB risk models took.
> - **The district half:** HTTP transport against the real server contract, the supervisor role scoped to its download, and a barrier pattern that leaves the handset as a submitted escalation instead of a sentence on a screen.
> - **A 90-day CHPS pilot** in one sub-district: measure whether referral answers get collected, whether a family's ask-for-help is acted on, and whether "did not attend" stops being the end of the record.
> - **What we need from UNICEF:** a clinical champion to sign the guideline mapping, a data-use agreement and an ethics route to a Ghanaian cohort, one district to pilot in, and a phone that is not a flagship.
>
> CareBridge AI — the reason a family didn't come, counted until it becomes a fact somebody has to fix.

**SPEAK (0:28)**
"Everything we shipped today is engineered to the edge of what we could prove alone. The next step isn't a bigger model — it's a Ghanaian cohort, a native ear, a real district server and one sub-district to pilot in. That's what we're asking UNICEF for. Because when the register stops saying 'did not attend' and starts saying 'three households, closed facility, this month' — that's when the system can no longer look away."

---

## Appendix — Answers to the questions this deck will attract

*(Reference only. Not part of the 14.)*

**"Where did the data come from?"**
Mbarara RRH neonatal sepsis EMR, Uganda, mirrored publicly: `github.com/Helenaden/Neonatal-Sepsis-Prediction` (`Dennis_Neonatal_Sepsis_D.csv`, `Dennis_Neonatal_Sepsis_N.csv`), 964 rows, 756 positive and 208 negative, age 0–3 days, sha256 recorded per file. Pre-eclampsia external validation: UCI Machine Learning Repository, *Maternal Health Risk* (Ahmed M., 2018, Bangladesh-origin), n=1,006, held out and scored through the app's own normalisation. Out-of-domain check: PhysioNet 2019 adult ICU, n=4,000. Ghana priors from published Northern Region studies — Adokiya et al. 2022 (`doi:10.1080/03630242.2022.2030450`, n=359, Tatale-Sanguli and Zabzugu), Adjei-Gyamfi 2023, Fosu 2013 Northern MICS, Charadan 2025, Bugri 2023, Boafo 2025, Baiden 2011, WHO IMCI 2014. Full per-model citation blocks: `assets/models/*_metrics.json` → `provenance`.

**Speech and language data:** WaxalNLP (`google-research-datasets/WaxalNLP`), recognisers from `KhayaAI` and `asr-africa`, voices from `FarmerlineML`, `Helsinki-NLP`, `adab-tech`, `GhanaNLP`. Translation and voice manifests record source, revision, licence and per-file sha256.

**"Why are three of the four models trained on simulators?"**
Because no public Ghanaian cohort with matched vitals and outcomes exists. The prior-based simulator lets us build and measure the whole runtime today; the version ladder names the replacement (`v2.0-kintampo-cohort`), and the contract refuses to let any of them issue a clinical instruction until it has.

**"Isn't an internal AUC of 1.0 suspicious?"**
Yes — and that is the point of reporting it. It measures how well the student copies the teacher on the simulator. The number that means anything is the external one: 0.7365 on held-out UCI maternal data.

**"What happens if the AI is wrong?"**
The AI cannot refer, dose or triage. `clinical_use_allowed: false` is enforced where the model output enters the runtime. Guidelines decide; drift-flagged cases are marked; a worker with `overrideAiRecommendation` can override, and the override is recorded.

**"Where is the privacy boundary for a family that never consents?"**
Caregiver self-service creates only its own household, cannot write a clinical field, and consent is stored as history rather than a checkbox. Access to a record writes a ledger row. Erasure and access requests carry a statutory deadline. Rights that belong to the district are named as theirs.

**"Does it run on a real handset?"**
It builds for Android, iOS, Windows and the browser from one codebase. Windows and browser are exercised in CI here. The shipped APK size for the voice and language packs is the open constraint, which is why the ASR packs are stated as not shipped rather than quietly demoed from a laptop.
