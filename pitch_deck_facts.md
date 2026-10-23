# CareBridge AI — 7-Slide Pitch Deck Facts
*Every claim below is verified against the shipped code, models, and server. No theatre.*

---

## SLIDE 1 — TITLE / HOOK

**CareBridge AI**
*Offline-first clinical decision support for Ghana's last-mile health system.*

Tagline options:
- "The clinic that works when the network doesn't."
- "Every danger sign caught. Every referral followed. No signal required."

One-liner for the speaker:
> CareBridge AI puts a WHO-guideline triage engine, on-device AI risk models, and a closed-loop referral system into the hands of Ghana's Community Health Officers — fully offline, in their own language, with zero patient data ever at risk.

Key numbers for the hero slide:
- **4** on-device AI risk models (neonatal sepsis, child pneumonia, pre-eclampsia, LBW/SGA)
- **18-table** encrypted local database — full clinic works with zero connectivity
- **2** on-device neural translation models (English → Twi, English → Hausa) + recorded speech bank
- **AUC 0.90** cross-validated on **real patient records** (neonatal sepsis, Mbarara RRH EMR, n=964)
- **240+** automated tests pinning clinical thresholds and offline behaviour

---

## SLIDE 2 — THE PROBLEM & OUR TARGET USERS

### The problem
- Ghana's Community-based Health Planning and Services (CHPS) compounds are the **first and often only** point of care for rural mothers, newborns, and under-fives.
- The killers are well known and **time-critical**: neonatal sepsis, childhood pneumonia, pre-eclampsia/eclampsia, low birth weight. Outcomes are decided in hours, not days.
- Frontline workers (CHOs, midwives) face four compounding gaps:
  1. **No connectivity** — many CHPS zones have no reliable network; cloud-dependent tools simply stop working.
  2. **Paper registers** — referrals are written on slips; nobody knows if the family ever arrived at the district hospital. Referrals vanish.
  3. **Guideline load** — IMCI danger signs, ANC schedules, EPI immunisation catch-up rules, WHO growth standards are too much to hold in memory under pressure.
  4. **Language & literacy** — caregivers often cannot read English clinical advice; counselling is lost.
- The result: danger signs missed, referrals un-tracked, follow-ups forgotten, and families who never learn what to watch for.

### Target users
| User | Who they are | What they get |
|---|---|---|
| **Frontline Health Workers** (CHOs, midwives, CHPS staff) | The primary user. Runs clinic sessions, assessments, referrals. | Full offline clinic: day plan, roll call, AI-assisted triage, referral tracking |
| **Caregivers** (mothers, fathers, kinship carers) | Linked to one household via a family code. Low literacy assumed. | Danger-sign home checks in their language, voice playback, referral status visibility |
| **Health system / GHS** (district officers, researchers) | Secondary beneficiary. | De-identified recalibration exports, auditable sync log, no-PHI reporting pipeline |

Role separation is hard-coded: the app is two distinct products behind one login — a caregiver can never reach clinical screens, and a worker can never see a family outside their scope.

---

## SLIDE 3 — HOW THE SYSTEM WORKS (AND WHY IT WINS OFFLINE)

### The frontline workflow (a real clinic day)
1. **Today tab** — honest status line ("Working offline · 3 changes waiting to send"), live clinic queue, urgent referrals awaiting arrival, workload at a glance.
2. **Receive a patient** — WHO ETAT "look before you log": three thumb-sized observations route an unwell child straight to the **60-second emergency tunnel** — no forms, no names, IMCI danger signs as big YES/NO taps, real 60-second respiratory-rate timer, verdict with pre-referral steps.
3. **Clinic session** — pick the household, deliberate roll call ("Who is here?" — absence is recorded, not skipped), per-person assessment queue, resumable if interrupted.
4. **Assessment** — age-branched clinical forms (newborn/child/maternal), WHO IMCI + GHS protocols, danger signs escalate regardless of scores.
5. **Result** — triage verdict (urgent/priority/watch/routine) with colour-coded hero, AI risk insight (suppressed on data drift), stabilisation steps, treatment and counselling guidance, referral issuance with a printed code.
6. **Follow-up** — day plan (overdue/due-today care reviews), referral desk (arrival vs treatment tracked separately), household risk priorities labelled honestly as "saved records, not a diagnosis."

### Offline-first architecture (the engineering claim judges should probe)
- **SQLite is the source of truth** — 18 tables, foreign keys enforced, versioned migrations. Every screen works with zero network.
- **Atomic outbox pattern** — every clinical write enqueues a sync intent *in the same database transaction*. A record literally cannot exist without its sync intent. Verified across all 30+ write sites in the codebase.
- **Priority sync queue** — critical referrals (priority 0) ship before routine data (priority 5); batches of 25; exponential backoff 1→2→4→…→120 min; ≥5 failed attempts flags the item for human attention on the dashboard.
- **Honest connectivity** — the UI names "Working offline," counts pending changes, and never implies data has left the device when it hasn't.
- **Hybrid cloud** — Node.js + MariaDB backend receives idempotent upserts (`INSERT … ON DUPLICATE KEY UPDATE`); a strict 16-table × 3-operation whitelist and parameterised queries close the injection surface; no server-side foreign keys because priority-ordered arrival must never 4xx an urgent referral.
- **Recovery** — a new device restores the worker's scoped caseload over JWT; local PIN is regenerated on-device, never downloaded.

---

## SLIDE 4 — DATA PROTECTION, SECURITY & COMPLIANCE

This is a clinical system handling mothers and children; the security posture is designed to survive hostile audit.

### Credential architecture — dual-hash, zero-knowledge
- **Local PIN**: HMAC-SHA256, 20,000 iterations (release), per-device random salt, stored only on the device. **Never synced.**
- **Cloud verifier**: a *further* 120,000-iteration domain-separated HMAC stretch of the already-stretched local hash, bound to phone + server salt, stored in a **physically separate `user_verifiers` table** — constant-time comparison, never returned to any client.
- **Login is challenge-response** — the PIN never crosses the wire; the server sees only the one-way verifier and issues a short-lived JWT (+ refresh token).
- **Theft scenario**: an attacker with the full MariaDB backup cannot reverse into any on-device PIN, and cannot sign in. Hashes are one-way *and* the local hash never leaves the device.
- Weak PINs (1111, 1234, 4321, 0123) rejected at registration.

### Access control — RBAC at the data boundary
- Every repository read/write passes three guards: capability permission → household scope → person scope.
- Denials are audit-logged with the attempted permission and entity, then throw `AccessDenied`.
- Workers see only their region/district/community caseload; caregivers see only their linked household. The router hard-blocks cross-role navigation.

### Compliance & governance posture
- **Recalibration exports are de-identified by construction**: numeric/boolean model inputs only, no names, no phone numbers, no community, no exact dates, no raw person IDs — age *bands*, month granularity, and a salted SHA-256 linkage key whose salt is held by GHS, not shipped in the app.
- **Export requires a human gate**: district health information officer signs every export; designed for Kintampo HRC / Navrongo HDSS pipelines.
- **Server sync audit log contains no PHI** — entity table, entity ID, operation, timestamp, authenticated user only.
- **Server strips credentials at the boundary**: `pin_hash`/`pin_salt` are removed from all user payloads by the API whitelist layer; recovery responses contain no hashes.
- **Model integrity chain**: SHA-256 of every `.tflite` verified at first use against the metrics manifest; mismatch → model blocked, deterministic fallback runs. Tampered weights can never produce a false "Verified" status.

---

## SLIDE 5 — THE AI & RECOMMENDATION SYSTEM

### Four on-device TFLite risk models (int8-quantised, fully offline)
| Model | Population | Trained on | Evidence |
|---|---|---|---|
| **Neonatal sepsis** (0–59d PSBI) | Newborns | **Real patient records** — Mbarara RRH EMR, Uganda, n=964 | **5-fold cross-validation AUC 0.90** |
| **Child pneumonia** (2–59m) | Under-fives | Simulator seeded from WHO IMCI + Baiden 2011 | Screening aid; external validation pending |
| **Pre-eclampsia** (ANC 20w+) | Pregnant women | Simulator seeded from published Ghana studies | External check on real UCI Bangladesh cohort: **AUC 0.74** |
| **LBW / SGA** | Newborns | Simulator seeded from Savelugu + MICS studies | Screening aid; external validation pending |

### Honesty is engineered, not claimed
- **Real-data models lead with cross-validation; simulator models lead with their external check** — the code enforces which number the UI is allowed to headline (`OfflineModelStatus.headlineValidation`). Internal simulator self-checks are labelled "sanity check, not evidence."
- **Drift guard** — per-feature z-score monitoring against training distributions (z thresholds 2.5–3.5); when a patient's inputs drift out of the training window, the risk probability is **suppressed** ("n/a · out of training window") instead of confidently wrong.
- **Platt calibration** applied on the logit side (the v1.0 bug — scaling the probability directly — was found in audit and fixed in the v2.0 trainer).
- **Two-tier inference**: TFLite interpreter primary; a deterministic noisy-OR Bayesian fallback runs if the model is missing, corrupted, or SHA-mismatched. The app never silently stops assessing.
- **Human override with accountability** — a clinician can override any AI verdict, but must give a reason of at least 10 characters; it is persisted to the audit trail.
- **Recalibration pathway**: v1.0 → v2.0-kintampo-cohort → v3.0-prospective-pilot. Quarterly Platt re-fits per district; retrain and re-ship only when ~5,000 linked outcomes justify it — only then does the headline become Ghanaian patient data.

### The deterministic recommendation engines (no ML black box where guidelines exist)
- WHO IMCI child illness classification, ANC/PNC contact engines, EPI immunisation catch-up engine (minimum intervals, what can never be given late), WHO growth z-scores, nutrition/CMAM logic, vulnerability scoring with modifiable vs non-modifiable risk separated ("No IPTp doses: fixable today" outranks "previous stillbirth: real but unfixable").
- Clinical thresholds are pinned in code and locked by tests (e.g. anaemia 10.4 g/dL; sepsis/pneumonia/pre-eclampsia probability tiers), so a refactor can never silently move a triage cut-off.

---

## SLIDE 6 — NLP & LANGUAGE ACCESSIBILITY

Care advice that can't be understood is care advice that doesn't exist.

### Three-layer offline language stack
1. **Recorded speech bank (layer 1)** — human-recorded audio for fixed clinical phrases (Dagbani recorded; Mampruli/Kusaal drafted with speakers). Highest trust: real voice, fixed meaning.
2. **On-device neural translation (layer 2)** — MarianMT encoder/decoder ONNX models (Helsinki-NLP opus-mt), quantised int8/int16 with per-row/per-column scales, running fully offline:
   - **English → Twi** and **English → Hausa** model packs shipped
   - SentencePiece tokeniser re-implemented in Dart with **token-for-token parity fixtures checked at model load** — if the tokeniser ever diverges from the PyTorch reference, the model refuses to run rather than mistranslate clinical advice
   - Greedy-decode generation fixtures validated at packaging time; packaging refuses to ship unless all fixtures reproduce the fp32 reference exactly
3. **Clinician-curated phrase dictionary (layer 3)** — deterministic fallback for greetings and stock phrases.

### Safety guardrails (the part that matters clinically)
- **Dynamic clinical text is never machine-translated blindly** — translation only proceeds when the text matches a vetted clip/reference; stale or unverifiable references are blocked and shown in English with an explicit notice.
- **Protected clinical content** (dosages, thresholds, referral codes) is never altered by the translation path.
- Narration buttons across both apps speak key guidance aloud — built for low-literacy users, not as a gimmick.
- Model provenance pinned (upstream revision + weights SHA-256 recorded; Apache-2.0 license tracked).

---

## SLIDE 7 — THE REFERRAL SYSTEM (CLOSING THE LOOP) + ASK

### The problem it solves
A paper referral slip tells nobody whether the family travelled, arrived, was treated, or went home. In this system a referral is a **tracked lifecycle**, not a slip.

### How it works
- **Issuance** — every referral gets a secure random **CB-XXXX reference code** (crypto-secure RNG), urgency tier (immediate / same-day / routine), reason, facility, and an SBAR handover note.
- **Lifecycle states** — `issued → travelling (family-reported) → arrived → treated & discharged`, plus honest failure states: `did not attend`, `family declined`, `cancelled`, `died`. Arrival and treatment are **separate outcomes** — the app never implies arrival equals care received.
- **Two confirmation channels, kept distinct** — family self-report (flagged "not facility-verified") vs staff code confirmation (a verified action gated behind a permission).
- **Auto-escalation** — an urgent referral open over 48 hours with no confirmed arrival is flagged "trace now" on the referral desk and pushed into the worker's day plan as an urgent chase item.
- **Follow-up is scheduled, not hoped for** — referral checks appear in the care-review worklist; re-referrals chain to the original code; the household screen shows the referral timeline in context.
- **Closed loop to the caregiver app** — the family sees their own referral status and code; the worker sees what the family reported; both sides stay honest.
- **Barrier intelligence** — when a referral fails, the reason (transport cost, distance, card/registration, refusal) is recorded and surfaced *before the next referral* — a barrier already named never has to be discovered twice.

### Why this wins (closing line)
> Other apps digitise the form. CareBridge AI closes the loop: the danger sign is caught offline, the AI is honest about what it knows, the advice is spoken in the family's language, and no referral is ever lost between the compound and the hospital.

### The ask / next steps
- Pilot cohort in Northern Region CHPS zones with GHS blessing
- Recalibration data pipeline through Kintampo HRC / Navrongo HDSS → earn the Ghanaian-patient-data headline for all four models
- Extend recorded speech to Mampruli and Kusaal with community speakers

---

## APPENDIX — BACKUP FACTS FOR Q&A
- Sync outbox: priorities critical=0 / clinical=3 / routine=5 / background=8; batch 25; backoff capped 1–120 min; attention threshold ≥5 attempts; 14-day pruning of synced rows.
- Server: 16-table whitelist, operations limited to insert/update/delete, JWT scope claims derive caseload — the server ignores client-supplied scope parameters.
- Tests: 240+ automated tests including pinned triage strings, offline outbox atomicity, RBAC denial, drift suppression, 320px/200%-text accessibility layouts, and finite-animation contracts.
- Emergency tunnel: IMCI general danger signs (inability to drink/breastfeed, vomits everything, convulsions, lethargy/unconsciousness, severe chest indrawing) + maternal red flags (convulsions, severe headache/blurred vision, heavy bleeding, severe abdominal pain/difficulty breathing, reduced fetal movements) + WHO fast-breathing cut-offs by age (≥60 under 2m, ≥50 at 2–11m, ≥40 at 12–59m) with a real 60-second timer.
