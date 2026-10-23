# CareBridge AI — 8-Slide Deck: Sequence and Script

**Use:** read top to bottom; each slide is one beat. Slide text is what goes on the screen.
`SAY` is the one line you speak. `EVIDENCE` is only for answering a judge — never read aloud.
`DON'T SAY` prevents the four overclaims that cost credibility last time.

**Run time:** 9 slides × ~45 s = **7 minutes**. If you are held to 6, deliver slides 1–2 and 4–5
as one block and drop slide 3 (the permission table answers a question nobody asked yet).

| # | Slide | Beat | Time |
|---|-------|------|------|
| 1 | CareBridge AI | Thesis | 30 s |
| 2 | The problem | Why it hurts | 50 s |
| 3 | Who it is for | Three users | 40 s |
| 4 | How care happens | The loop | 60 s |
| 4b | The verdict screen | What the nurse actually reads | 45 s |
| 5 | The referral | Closing the loop | 50 s |
| 6 | Data protection: security | Bars, not promises | 50 s |
| 7 | Data protection: compliance | Proof, not policy | 45 s |
| 8 | AI, recommendation, language | What is trained, gated, refused | 65 s |

---

## Slide 1 — CareBridge AI

**On screen**
- CareBridge AI
- Guidelines decide. Models support. Nothing leaves the phone.
- Offline maternal, newborn and child care for Northern Ghana

**SAY:** "Every clinical decision in this app is made by a Ghana IMCI guideline, on the phone, with no network — and the AI is deliberately not allowed to overrule it."

**EVIDENCE:** `lib/domain/engines/` (16 engines), `assets/models/research_contracts.json` (`clinical_use_allowed: false` on all four models).

**DON'T SAY:** "AI-powered diagnosis", "world-class", "state of the art".

---

## Slide 2 — The problem

**On screen**
- One frontline worker. A zone of a thousand-plus people. Ninety seconds of EDGE signal.
- A missed referral is one field on paper — the *reason* is never written down, so it is never counted.
- Twelve named barriers, with different owners: transport money, distance, husband's permission, no NHIS card, no one to mind the children, facility closed, a bad experience before, traditional care preferred, fear of injection, farm workload, flooded road, "didn't think it was serious".
- Mothers, newborns and under-fives die of delays that are *known* and *countable* — just not counted.

**SAY:** "The register records that a mother didn't go. It has no field for why. So the district can see a number, and can never act on it."

**EVIDENCE:** `CareBarrier` enum — 12 values (`lib/domain/enums.dart`); `lib/data/sync/sync_service.dart` written for intermittent EDGE; districts named in code: Savelugu, Gushegu, Bawku, Tatale-Sanguli, Zabzugu.

**DON'T SAY:** any mortality figure you cannot cite — the app contains none.

---

## Slide 3 — Who it is for

**On screen**

| User | Gets | Enforced by |
|---|---|---|
| CHPS nurse / frontline worker | register, roll call, vitals, IMCI assessment, verdict with weight-based doses, referral, follow-up desk, ranked route | 12 FHW permissions |
| Mother / caregiver | danger-sign check **in her language, read aloud**, care plan, food and milestones, "ask for help" | 5 caregiver permissions — no clinical write |
| Supervisor / district | consent, access and review queues, read audit, barrier patterns | append-only ledger |

- A family can register itself before a worker ever arrives — and still cannot write a clinical field.

**SAY:** "Three users, one record, one permission model — and the caregiver's permission physically cannot write a clinical value."

**EVIDENCE:** `Permission._fhw` (12), `Permission._caregiver` (`viewOwnFamilyOnly`, `runCaregiverTriage`, `recordBarrier`, `requestCare`, `manageOwnFamily`); refusal enforced in `care_repository.dart`, not the UI.

---

## Slide 4 — How care happens

**On screen**
- **Worker loop:** register / roll call → measure → assess → refer → follow up → route
- Absent is **recorded absent**, never silently skipped.
- A plausibility screen runs before any dose is calculated.
- **Caregiver loop:** danger-sign check in Dagbani, Twi, Hausa or English — 18 questions, 5 guidance topics, **41 spoken clips per language**, every answer read back before it counts.
- "Ask for help" writes a request that reaches the district and returns with an answer.
- The day plan ranks the zone, so a chase visit rides a walk already being made.

**SAY:** "The nurse never has to open a document to find out what to do — and the mother never has to read to be told what to do."

**EVIDENCE:** `VisitDao.openVisitsFor`, `measurement_safety_engine.dart`, `assets/audio/{dagbani,hausa,twi}_mms`, `speech_bank.dart`, `dayPlanProvider`.

**DON'T SAY:** "voice input works" — see slide 8.

---

## Slide 4b — The verdict screen

*This is the answer to "we want a sleeker UI and more information from the AI". Put the real
screen on the slide, or open the app and point at it. Every line below is computed, and the app
stays silent rather than guessing.*

**On screen** — one verdict card, top to bottom:
- **The condition, named the way the guideline names it** — "Pneumonia", not a score. Ranked in IMCI precedence: a general danger sign outranks the symptom cluster, severe absorbs mild.
- **The measurement that earned it, beside the cut-off it crossed** — "Fast breathing · 62/min (cut-off ≥ 50/min at this age)".
- **What is still outstanding** — a malaria test not done reads as a pending test, never as a diagnosis and never as all-clear.
- **"Would a re-count change it"** — the app re-runs its own engine and reports the nearest number at which the verdict flips, and flags a call sitting within 10% of the line.
- **The family's sentence, assembled from her record** — name, age, weight, review date; where a value was never taken, the card says *not recorded*.
- **The action list, ordered by a rule it shows you** — urgency, then kind of action, then what this household can reach.

**SAY:** "Judges asked for a sleeker screen and a confidence number. We gave the screen something better than a confidence number: the measurement, the line it crossed, and what would have to change to change the answer — and if the record cannot support that sentence, the screen leaves it blank instead of inventing one."

**EVIDENCE:** `clinical_impression_resolver.dart` (33 real engine classifications), `protocol_counterfactual.dart`, `child_input_from_record.dart` (refuses to render unless it reproduces the stored verdict), `care_slots.dart`, `action_prioritizer.dart`, `guideline_conformance_test.dart`.

**DON'T SAY:** "the AI is 92% confident", "the model diagnosed". The engines classify against the guideline; the models have no clinical authority.

---

## Slide 5 — The referral

**On screen**
- Eight states: issued → travelling → arrived → treated; plus did-not-attend, refused, cancelled, died.
- **Arrival is not treatment.** A child seen but untreated stays on the chase list.
- Settled stays settled — a later answer is evidence, not permission to rewrite the file.
- One atomic write captures the answer, the status, the **barrier**, the next visit and a chained referral — all or nothing.
- Verification is bounded: a facility may confirm *arrived / treated / died* — never a family's refusal.
- Two unanswered visits escalate to a trace.
- Barriers become district evidence: **distinct households**, 30 days, threshold **3 households** — each pattern names its owner: household, community, facility, system, season.

**SAY:** "The loop does not close when the child arrives. It closes when the child is treated — and when we know why the last one wasn't."

**EVIDENCE:** `ReferralStatus` (8), `CareRepository.recordFollowUp`, `isFacilityConfirmable`, `barrier_evidence.dart`, `BarrierDao.withinDays`.

---

## Slide 6 — Data protection: security

**On screen**
- Whole database is a **SQLCipher** file; the key comes from secure storage before use. An install **refuses** to encrypt with a key it cannot read back.
- Old installs migrate by **copy-verify-swap** — every table counted on both sides; a mismatch leaves the original intact.
- `PRAGMA secure_delete = ON` at every open.
- Four declared scopes per table — including a credential verifier that is **pushed but never stored locally**.
- Transport policy enforced **inside the app**, in the one door every request passes through.
- 27 named controls: **15 in place, 8 in place with a stated limit, 4 marked as not this software's to implement.**
- The app prints its own weakness: on web and desktop there is no SQLCipher engine, so the posture card says **"not encrypted at rest"**.

**SAY:** "Where we are strong, we can show you the test. Where we are limited, the screen says so — that is why you can trust the rest."

**EVIDENCE:** `lib/domain/governance.dart` (27 controls, 20 name their test), `database_conversion.dart`, `transport_policy.dart`, `db_engine_io.dart`.

---

## Slide 7 — Data protection: compliance

**On screen**
- **Consent stored as history**, never as a single overwritten flag.
- **Access ledger**: who read what, when — tamper-evident, chain-anchored, district-side read audit.
- Those tables are append-only and never cascade from a patient row: deleting a person must not delete the evidence that made the deletion lawful.
- Right to erase and right of access carry a **statutory deadline**.
- Mapped, not name-dropped: **Ghana DPA 843 s.26 / s.27**, HIPAA 45 CFR 164.312, OWASP MASVS STORAGE / PLATFORM / CRYPTO.
- **The register is code, not a PDF:** every table's purpose, lawful basis, retention and place in the access matrix. CI reconciles it against the schema, the sync whitelist and the pull list — add a table without declaring it and the build fails.
- Four controls belong to the district (retention, registration, breach notice, impact assessment) — recorded as theirs, with the owner named.

**SAY:** "We do not claim compliance. We claim that every control is either tested, bounded, or assigned to the district — and the build fails if we lose track of one."

**EVIDENCE:** `GovernanceRegister`, `consent_events`, `access_ledger`, `server_read_log`, `docs/GOVERNANCE.md`.

**DON'T SAY:** "fully compliant with Act 843". Mapping is not certification.

---

## Slide 8 — AI, recommendation, language

**On screen**

**The rule:** guidelines decide, models support, and the flag that forbids clinical use is enforced where output enters the app.

| | What it is | Honest number |
|---|---|---|
| **Models** | 4 on-device int8 TFLite, **under 6 KB each** | Sepsis: **real** cohort (Uganda, n=964), AUC 0.90, sens 0.778 / spec 0.933. Three others: simulator-trained — pneumonia AUC 0.742, pre-eclampsia external **0.7365** on a held-out public set |
| **Recommendation** | findings classified — clinical, preventive, data-quality, experimental; one ranked condition named in IMCI precedence order, with the cut-off it crossed | A missed vaccine can no longer make a well child "urgent". **11 of 11** seeded encounters produce the classification and the action the guideline mandates — re-runnable in CI. **1,353 tests** green on the whole app |
| **Language** | offline MarianMT translation, Piper speech, on-device ASR | **Twi speech: 0.162 CER — allowed. Dagbani: 0.420 — the microphone stays off** |

- Out of its depth, the sepsis model returns **AUC 0.511 (chance) on adult ICU data** — and says so. That is the behaviour we want.
- **Nothing here is clinically validated in Northern Ghana.** Four models, one real cohort, zero clinical authority.

**SAY:** "We can show you a model that admits it is out of its depth, and a language feature that switches itself off when it cannot spell the answer. That is the whole design."

**EVIDENCE:** `*_metrics.json`, `research_contracts.json`, `clinical_evidence_graph.dart`, `clinical_brief_engine.dart`, `clinical_impression_resolver.dart`, `protocol_counterfactual.dart`, `guideline_conformance_test.dart`, `asr_contract.dart`, `marian_contract.dart`, `piper_contract.dart`, `docs/MODEL_CARD.md`.

**IF ASKED FOR AN ACCURACY NUMBER:** "The guideline layer is measured by conformance, not
accuracy: 11 of 11 seeded encounters produce the classification and the mandated first action, and
the build fails if that drifts. That is a count of cases in a test file, not a rate over a
population — we are not going to dress it up as more than it is. The model layer is measured by
AUC, and the only real patient cohort here is Ugandan."

**DON'T SAY:** "trained on Ghanaian patients" (the cohort is Ugandan), "clinically validated", "diagnosis".

---

## If a judge asks — three answers, ready

1. **"Where does the AI change a decision?"** — "It doesn't. 16 guideline engines decide; every model carries `clinical_use_allowed: false` and that is enforced where its output enters the runtime."
2. **"Is this just rules with a model bolted on?"** — "Rules are the safety layer. The models are research artefacts we refuse to overstate — three are simulator-trained and we show you which."
3. **"What is not finished?"** — "No live district server, ASR packs not shipped, Dagbani voice awaiting native sign-off, three of four models awaiting a real Ghanaian cohort. And one thing we chose not to build: a model could be allowed to issue a referral on its own, and we left that gate off — the code today forbids a research signal from adding a treatment or a referral, and that prohibition is tested. We say all five before you ask."

## What not to claim, ever

- No death or morbidity reduction figures — none are measured.
- No "validated in Ghana" — nothing is.
- No accuracy percentage on a slide that is not in a metrics file.
- **Never call the 11/11 an accuracy.** It is guideline conformance over seeded cases in a test
  file. Saying "100% accurate" would be the exact overclaim the rest of the deck is built to avoid.
- No "voice input" without "Twi only, and it may propose, never record."
- No "the AI decided" or a percentage of confidence. The guideline engines classify; the app now
  reports a measurement, a cut-off and a flip point — never a probability it does not have.
