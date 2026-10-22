# Five-Area Audit — scored against the code, not the pitch

Method: every bullet in the team's five-area list was checked against the repository.
Each area is scored out of 100 on a fixed rubric. Where a claim is false or
overstated, the correction is given in the same row, because a judge who opens the
app and finds a slide that lied will discount everything else on it.

**Rubric (per area):** working depth in code 40 · fit to the brief's wording 20 ·
differentiation vs a plausible rival team 20 · honesty of the claim as currently
phrased 10 · demo-ability in six minutes 10.

| Area | Score | One-line verdict |
|---|---|---|
| 1 · Predicting risk before crisis | **82** | Engines are real and unusually self-aware; the word "predicting" is doing more work than the code does |
| 2 · Last-mile follow-up | **88** | The strongest area in the room; two of its three bullets are phrased wrongly |
| 3 · Voice-first caregiver support | **72** | Real on-device chain; the Dagbani bullet is false as written and the licence position is fragile |
| 4 · Smarter CHPS workflows | **83** | Everything claimed exists; the tally bullet overstates its scope in a way the app itself warns about |
| 5 · Hidden barriers to care | **77** | The most under-shown differentiator in the product; the verb "overcoming" is the weak point |

---

## Area 1 — Predicting risk before crisis · 82/100

**Verified in code**
- `lib/domain/engines/vulnerability_engine.dart` — bands critical/high/moderate/low with an action per band ("See today", "See this week"), a **completeness figure** ("this score is built on 6 of 12 things"), and a split between **modifiable** factors and **fixed history**.
- `lib/domain/engines/trajectory_engine.dart` + `lib/domain/engines/road_to_health.dart` — WHO road-to-health chart; growth faltering read as channel crossings, tested in `test/road_to_health_chart_test.dart`.
- `lib/core/ml/offline_inference_service.dart` — TFLite int8 models with SHA-256 gating and a deterministic noisy-OR fallback; the IMCI/CHPS rule engine as referee.
- Missed-contact and days-since-last-visit inputs (`visit_dao.dart: missedCountFor`, `daysSinceLastVisit`) — silence counts as risk, not as safety.

**Weaknesses**
1. "Predicting before crisis" is really **ranking known risk plus detecting faltering**. There is no prospective model of who *will* deteriorate; the honest verb is "prioritising". The completeness figure is the thing that makes this credible, and it is currently buried.
2. The learned layer is not Ghana-validated (`clinical_use_allowed: false`), so the area's headline rests on rules — which is fine, but the slide must not imply otherwise.
3. No **trend language**: the engine scores today's state; it does not yet say "this child's curve flattened between March and May", which is the sentence a nurse finds persuasive.

**Award moves**
- *Pitch today:* lead with the completeness figure and the modifiable/fixed split. "We show you how much of this score we actually know, and which half you can change this week" is a more innovative sentence than any AUC.
- *Build today (≈1 h):* on the household risk card, add one line naming the **single largest modifiable factor** ("the missed ANC contact is worth 12 of these 47 points"). The data is already in `RiskFactor`.
- *Later:* a faltering sentence from the trajectory engine ("crossed two WHO channels in 60 days") as the first line of the child's growth page.

---

## Area 2 — Last-mile follow-up · 88/100

**Verified in code**
- Closed loop: `referrals` with `reference_code` (UNIQUE index), `arrival_confirmed_by`, `outcome_notes`, `escalated_at`, `link_from_referral_id` for chained re-referral.
- `CareRepository.confirmArrival` and `confirmReferralOutcome` — the latter accepts only `arrived / treated / died`, the three states a verifier can witness, and **never reopens a settled case**, recording the verifier's name. That is a genuinely rare design decision.
- `lib/presentation/visit/sbar_card.dart` — SBAR handover composed from existing records, shown from the roll call and the referral desk.
- `lib/presentation/fhw/clinic_queue_screen.dart` — a ticket per open session in arrival order, built from existing Visit rows, no new schema.
- Follow-up check-in derives the whole lifecycle from four answers in one commit (`follow_up_check_in_screen.dart`).

**Corrections — two bullets are wrong as written**
1. **The code format is `CB-XXXX`, not `#CB-2026-XXXX`.** Four characters from an ambiguity-safe alphabet, collision-checked against the UNIQUE index, widened if the space ever fills (`visit_dao.dart: mintReferenceCode`). It is deliberately short because a facility reads it off a paper slip or hears it down a crackly phone line. Say that; it is a better story than a longer fake format.
2. **The SBAR card is a worker-side handover note, not a card the mother carries.** It renders as a sheet in the FHW app. Nothing today is designed to travel in a mother's hand.

**Weakness**
- **There is no facility role.** `confirmReferralArrival` is an FHW permission, so the loop closes on a health worker's phone — usually after a phone call. The district sees the confirmation but the facility never touches the system. This is the area's real ceiling.

**Award moves**
- *Pitch today:* the four-answer derivation ("we never ask a worker to pick a status; we ask what they saw") plus "a settled case is never reopened" — both are governance-grade design that judges rarely see in a hackathon.
- *Build today (≈1–2 h):* a **carry slip** view of the SBAR card — one screen, huge type, the `CB-XXXX` code, the three danger signs, the facility name, printable/screenshot-able. This makes "the mother takes the card to the clinic" **true** instead of aspirational, and it is the single highest-value 2 hours left in the day.
- *Later:* a kiosk/lookup mode so a facility handset can confirm arrival by code without a full account.

---

## Area 3 — Voice-first caregiver support · 72/100

**Verified in code**
- Chain in `lib/core/audio/caregiver_playback.dart`: recorded bank → Piper VITS → system TTS → readable text; English skips translation.
- Piper voices shipped for **Twi and Hausa** (`assets/tts/twi_piper`, `hausa_piper`, both in `pubspec.yaml`); Twi RTF ≈ 0.3.
- Neural translation on-device (MarianMT ONNX, int8) feeding the same chain.
- Refusal rules: no wrong-language fallback; no answer the pack's alphabet cannot spell.
- Measured dictation CER on a home-built harness: Twi 0.162, Dagbani 0.420 (n=8).

**Corrections — the bullet is false as written**
- **There is no Piper voice for Dagbani in the build.** Dagbani speech is a **41-clip bank generated with Meta MMS** (`facebook/mms-tts-dag`), CC-BY-NC, over translations that the repo's own provenance file calls **drafts awaiting native-speaker sign-off**. The Dagbani Piper checkpoint exists on disk but carries **no licence** and is excluded from `pubspec.yaml`.
- **"Audio storytelling cards" do not exist.** What exists is audio guidance on clinical cards (feeding, danger signs, verdicts). Do not put "storytelling" on a slide.

**Weaknesses**
1. Dagbani dictation at CER 0.42 is not usable as an input; it is honest to show it as a measured limit.
2. The licence position (CC-BY-NC bank, unlicensed candidate weights in git) is the area's biggest professional risk in front of UNICEF and GHS.
3. "Zero medical jargon" is only partly true: the caregiver check-in is plain, but several screens still surface clinical nouns.

**Award moves**
- *Pitch today:* the refusal rule is the innovation — "the app will not read English to a woman who asked for Dagbani and let her believe it was her language." That sentence is worth more than any voice demo.
- *Build today (≈1 h):* a **language sign-off mode**: play each of the 41 Dagbani clips, record approve/reject per clip by a native speaker, export the list. It converts the draft problem into a workflow and matches the ask on slide 14 exactly.
- *Later:* remove the unlicensed weights from git; record MarianMT licences in the two empty `provenance.json` files.

---

## Area 4 — Smarter CHPS workflows · 83/100

**Verified in code**
- Day plan (`dayPlanProvider`) with reasons per position; priority bento deck in the luxe layer; roll call with absence recorded; `clinic_queue_screen.dart` tickets.
- `DailyRegisterTally` (`domain/entities/visit.dart`) — children seen, RDT done/positive, SAM, referrals; deliberately parsed from JSON payloads rather than SQL `LIKE`, tested in `test/daily_register_tally_test.dart`.

**Correction — the tally bullet overstates**
- The tally is scoped to **this worker's own rows on this device**, and the code says so: it is "a starting point for the paper register rather than the facility's total, which also holds colleagues' work and anything recorded on paper alone", and on a shared phone it must not show one worker's column to another. "Auto-aggregating GHS reporting numbers" is not what it does. Say "your own day, read back to you, in the register's columns" — which is what a CHO actually needs at 4pm.

**Weaknesses**
1. No mapping from the tally to the **GHS register column order**, so the worker still transcribes.
2. Workload reduction is asserted, never measured — no before/after time-on-task data exists.

**Award moves**
- *Pitch today:* the shared-phone rule (two CHOs, one handset, separate tallies) is an operational insight judges from GHS will recognise instantly.
- *Build today (≈1 h):* render the tally in the **exact column order of the paper daily register** with a "copy into column 4" caption. Cheap, specific, and it turns a dashboard into a tool.
- *Later:* time-on-task measurement in the pilot.

---

## Area 5 — Hidden barriers to care · 77/100

**Verified in code**
- `lib/domain/engines/barrier_engine.dart` does two things most teams never attempt: **predicts the barriers most likely to stop this referral before it is issued**, each with a stated basis and a `preemptiveAction`; and **aggregates across the zone** so six "facility closed" reports become one facility problem.
- `barrier_reports` with `resolved` flag; barrier history per household; supervision-desk pattern detection.

**Weakness — the verb**
- "Overcoming transport costs, distance, fear" is not what software does. The app **surfaces, predicts, plans around and evidences** barriers. Overclaiming here invites the obvious question ("so you pay for the motorking?") and loses the room. The honest framing — "we move the barrier conversation to before the referral, while the family is still in front of the worker" — is stronger than the overclaim.

**Weaknesses**
1. `preemptiveAction` exists in the engine but is not surfaced as a **checklist with states** (solved today / escalated / still open), so the prediction ends as text.
2. No link from a barrier to a **resource** (NHIS enrolment prompt, community transport scheme, market-day scheduling), which is where "overcoming" would actually live.

**Award moves**
- *Pitch today:* "prediction before failure" — the barrier engine runs **before** the referral is issued. That is the most innovative idea in the product and it is currently the least shown.
- *Build today (≈1 h):* render each predicted barrier with its `preemptiveAction` and a three-state tick on the referral screen.
- *Later:* a resource map per barrier type, maintained by the district.

---

## The three things to fix before 3pm

1. **Delete or correct the three false bullets** in the team's own list: `#CB-2026-XXXX` → `CB-XXXX` (and tell the code's real story); "Piper in Dagbani" → machine-voice bank over draft wording; "SBAR cards mothers take to the clinic" → worker-side handover note (or build the carry slip, which makes it true); "auto-aggregating GHS reporting numbers" → own-day tally in register columns.
2. **Build the carry slip** (area 2) if you build one thing. It makes the strongest area visibly true in a mother's hand.
3. **Rehearse the barrier-prediction moment** (area 5) — it is the idea no other team will have, and it currently has no stage time.

## The three things to say that no rival can

- "A settled referral is never reopened, and only three outcomes can be confirmed by a named witness."
- "The app will not read English to a woman who asked for Dagbani."
- "Every score tells you how much of it we actually know."
