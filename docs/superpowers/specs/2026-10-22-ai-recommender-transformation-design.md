# CareBridge AI — Recommender Transformation Master Plan

**Status:** design, awaiting approval before code.
**Author:** built from a read of the shipping engine code, not from intent.
**Purpose:** replace "hardcoded output + a number called confidence" with an AI system that
resolves a condition, generates this child's actions, ranks them for this household, states a
confidence that means something, and can be audited on all four.

---

## 1. What the code actually does today (the honest diagnosis)

Three findings, each with the line that proves it.

### 1.1 Some recommendations are canned strings — the user's "hardcoded" charge is partly true

`RecommendationEngine` mixes two very different kinds of output into one list:

| Kind | Source | Verdict |
|---|---|---|
| Condition-driven actions | the 16 guideline engines, triggered by this encounter's findings | **derived** — legitimate |
| `_cohortActions(cohort)` | `recommendation_engine.dart:669`, a `static const` list per cohort | **template** — identical text for every newborn in the country |
| `_cohortNote(cohort)` | `recommendation_engine.dart:641`, a fixed paragraph | **template** |
| The synthesizer guard-rail | `'Refer now. No engine listed a referral step…'` (`:466`) | **template**, and it admits it |

- A cohort baseline is clinically *correct* — routine newborn care genuinely is the same for every
newborn. The failure is that it is displayed **uninstantiated**: not this age in days, not this
weight, not this vaccine due today, not this dose in millilitres. Uninstantiated truth reads as a
poster on the wall, and a judge calls it a mockup. **Fix direction: instantiate, do not
apologise.**

### 1.2 The confidence number is not a confidence number

`visit.dart:428` computes it as:

```dart
(measuredKeyInputs / keyInputCount * 100).round().clamp(0, 100)
```

That is **measurement coverage**, labelled confidence. It answers "did you look?" not "how sure am
I?" — so a child with RR 51 against a 50 cut-off, all observations present, displays **100**. The
number is arithmetically honest and clinically misleading, which is the worst combination.

### 1.3 A fabricated fallback is on the display path

```dart
int get effectiveConfidenceScore => confidenceScore ?? legacyConfidenceEstimate(confidence);
```

`legacyConfidenceEstimate` (`visit.dart:434`) maps buckets to invented figures: 95 / 82 / 65 / 45.
Commented as "the closest honest number for that bucket", it is nevertheless **a number with no
computation behind it, rendered on a clinical verdict screen**. This must come off the display
path. It is precisely the kind of figure a judge can ask about and a nurse can be harmed by.

### 1.4 What already exists and is under-used (the assets)

`CarePlan` already carries `classifications`, `topDrivers`, `dangerSigns`, `missingData`,
`interactions`, `referralCapabilitiesNeeded`, `followUpInDays`, `triageRationale`,
`guardrailEscalated`. The evidence graph and brief layers are built. `withoutFeature()` re-runs a
model for counterfactuals. `TrajectoryEngine` forecasts when a child crosses into SAM and prints
its own arithmetic. **The raw intelligence is present; it is assembled badly and named
imprecisely.** This is a presentation-and-derivation problem, not a missing-brain problem, and it
is why the plan below is hours, not weeks.

---

## 2. Target architecture

One sentence: **resolve → derive → instantiate → prioritise → justify → abstain.**

```
                 ┌──────────────────────────────────────────────┐
 measurements ──►│ A. CONDITION RESOLVER                        │──► ClinicalImpression
                 │    IMCI precedence: danger sign > severity   │    "Pneumonia (severe)"
                 └──────────────────────────────────────────────┘    + the findings that made it
                                 │
                 ┌───────────────▼──────────────────────────────┐
                 │ B. ACTION DERIVER (no constants)              │
                 │  dose = f(weight, protocol table)             │
                 │  vaccine = f(age, schedule position, gaps)    │
                 │  feed = f(age, z-score, local foods)          │
                 │  follow-up = f(classification)                │
                 │  facility = f(referralCapabilitiesNeeded)     │
                 └───────────────┬──────────────────────────────┘   each carries Derivation
                                 │    {ruleId, engine, inputs[], citation}
                 ┌───────────────▼──────────────────────────────┐
                 │ C. PRIORITISER — utility × feasibility        │
                 │  urgency · benefit · THIS household's barrier │
                 │  · visit-time budget · interaction risk       │
                 └───────────────┬──────────────────────────────┘   ordered plan + weights shown
                                 │
                 ┌───────────────▼──────────────────────────────┐
                 │ D. FUSION GATE — escalate only                │
                 │  model may RAISE urgency, NEVER lower         │
                 │  referralSource: protocol|modelEscalation|    │
                 │               workerOverride                  │
                 └───────────────┬──────────────────────────────┘
                                 │
                 ┌───────────────▼──────────────────────────────┐
                 │ E. JUSTIFIER                                  │
                 │  confidence decomposition · counterfactuals   │
                 │  · decision stability · abstention            │
                 └───────────────┬──────────────────────────────┘
                                 ▼
                            the verdict screen
```

---

## 3. The six stages

### A. Condition resolver — "tell me the problem clearly"

A new pure function, `ClinicalImpression resolve(List<AssessmentResult>, List<ClinicalFinding>)`:

- Applies **IMCI's own precedence**, not an invented one: any general danger sign outranks symptom
  clusters; severe classification absorbs mild ones. This is citable and it is the piece nurses
  will check us on.
- Produces one **primary condition with severity** (`Very severe disease — pneumonia likely`),
  the secondary classifications, and for each, the exact findings with `value vs threshold`
  (`RR 62/min ≥ 50 for 12–59 months`).
- Resolves suppression: a finding that only exists because of an implausible measurement is
  excluded and reported as a data problem, never as a condition.
- Names the cohort and the rule that produced the label, so the string is never a constant:
  the words come from the classification record, the classification comes from the engines.

### B. Action deriver — kill the constants

- `_cohortActions` and `_cohortNote` stop returning fixed text. They become **templates with
  mandatory slots**, and a slot with no value fails the build of that action rather than falling
  back to prose. A newborn action must render as *"day 3 of life — weight 3.1 kg, exclusive
  breastfeeding not established, vit B12 due today at this facility"*, not *"watch the young infant
  closely for the next 48 hours"*.
- Every `RecommendedAction` gains a `derivation` record: rule id, engine, the input values used,
  the citation. Displayed on tap. This is the death of the "mockup" accusation: the action cannot
  be a mockup if its inputs are the numbers the nurse just typed.
- Referral target selection uses the existing `referralCapabilitiesNeeded` set rather than
  generic "refer".

### C. Prioritiser — the ingenuity, and the part no other team will have

Score every derived action on five declared dimensions, then rank:

| Dimension | Where it comes from | Why it is defensible |
|---|---|---|
| **Urgency now** | classification severity, do-before-leaving rules | straight from the guideline |
| **Benefit** | guideline's own ordering of the intervention | cited, not guessed |
| **Feasibility for this household** | the recorded `CareBarrier` values | **novel here**: 12 barriers already in the enum |
| **Visit budget** | how long the action takes; there are patients behind | operational truth |
| **Harm risk** | the existing `ClinicalInteraction` detection | already implemented |

The barrier-aware term is the differentiator. A plan that knows the road is flooded puts the
home-manageable actions first and turns the referral into *"the obstacle to clear is transport
money — here is what to do tonight regardless"*. Same guideline, different child, different plan.
That is what "personalised AI recommendation" means when it is real.

Weights are a named constant list, **shown in the UI as the ordering explanation**, so a judge can
disagree with the weights instead of the output.

### D. Fusion gate — escalate only (needs your approval)

- A model may **raise** urgency when the protocol is silent, never lower a protocol urgency.
- Every referral records `referralSource`: `protocol | modelEscalation | workerOverride`.
- Enforced where output enters the runtime — the existing `clinical_use_allowed: false` contract
  stays for anything unvalidated; escalation applies only to a score that clears a stated,
  auditable bar.
- On screen an escalation reads *"the model raised this; the guideline did not"* and needs the
  nurse's own reason to stand, which is also the training signal we want.

### E. Justifier — confidence that survives being asked about

`confidenceScore` is **split into three named components** and the single number is retired:

1. **Criterion margin** — distance from the nearest threshold that changed the verdict, normalised.
   RR 62 vs 50 is certain; RR 51 vs 50 is the *same classification, flagged borderline*. Pure
   arithmetic on values already stored.
2. **Evidence sufficiency** — today's coverage figure, renamed to what it is.
3. **Model contribution** — present only if a model actually ran, with its calibrated score,
   conformal margin and drift status; `withheld / out-of-domain` **lowers** the total and says why.

Add the two things that make this look world-class on a rule engine because they are exact, not
estimated:

- **Counterfactual**: perturb one input, re-run A→C, show the flip. *"RR 48 instead of 62 → no
  danger sign → refer not."* `withoutFeature()` already proves the pattern.
- **Decision stability**: the range of each measured value over which the verdict does not change.
  A nurse learns where the cliff is; that is the most useful uncertainty in the building.

Delete `legacyConfidenceEstimate` from the display path — render *"not recorded"* for legacy rows.

### F. The auditable metrics — how we win "best AI" without inventing a figure

The recommender gets its own evaluation, computed from the repo at build time, in CI:

| Metric | Definition | Why it is real |
|---|---|---|
| **Guideline conformance** | % of seeded cases where the generated plan's first action matches the guideline-mandated first action | asserted by tests over N cases; reproducible on stage |
| **Borderline detection** | % of near-threshold cases correctly flagged | the confusion matrix is constructed by the test fixtures |
| **Abstention rate** | % of cases the system refuses to score confidently, and the reason | comes from E, not a claim |
| **Model discrimination** | unchanged: from `*_metrics.json` only | already honest |

Judges ask "what is its accuracy?" and the answer becomes: *"on 42 seeded encounters the plan's
first action matches the mandated first action in 42 of 42, and here is the test file; the sepsis
model's AUC on a real Ugandan cohort is 0.90 and it is forbidden from driving treatment."* That is
an audit, not a boast, and it beats every number we could have made up.

---

## 4. Build plan — ordered so the demo works early

| # | Deliverable | Est | Proves |
|---|---|---|---|
| 1 | Remove `legacyConfidenceEstimate` from display; rename coverage honestly | 20 min | the number on screen is defensible *tonight* |
| 2 | `ClinicalImpression` resolver + tests (IMCI precedence) | 90 min | "it tells me the condition clearly" |
| 3 | Slot-filled action derivation (kill the two `static const` lists) + tests | 120 min | "these are not mockups" |
| 4 | Counterfactual + decision-stability on the protocol path + tests | 90 min | the explainability showpiece |
| 5 | Prioritiser: utility × barrier feasibility, weights exposed + tests | 120 min | personalised ranking — the differentiator |
| 6 | Verdict screen hero: condition · urgency · confidence in three bars · top actions with *why now* · what would change this · refer | 120 min | "sleek UI for it" |
| 7 | CI conformance harness over seeded cases → one number, on the slide | 60 min | the auditable metric |
| 8 | Escalate-only fusion gate + `referralSource` (migration, tests) | 90 min | "AI predicted urgent → referral issued" |

Steps 1–4 make the AI *sound* right. 5–6 make it *look* right. 7 gives the number. 8 gives the
headline. **Nothing here touches the clinical thresholds**, so every existing engine test must stay
green throughout — that is the safety rail on the whole plan.

## 5. What must not happen

No new model trained tonight and presented as validated. No accuracy figure absent from a metrics
file. No single blended "confidence %" that hides its components. No wording that says the system
diagnoses: it **classifies against WHO/GHS guidelines**, which for a nurse is the same useful
information and for us is the true one. No model downgrade of a danger sign, ever.

## 6. Decisions — all three approved 2026-10-22

1. **Stage D** — a model may issue a referral on its own: escalate-only, source-labelled, never
   able to downgrade a danger sign. **Approved.** Not yet built (section 7, step 8).
2. **Stage C weights** — publish the ranking weights in the UI as the explanation, so a judge
   disagrees with the weights rather than the output. **Approved.** Not yet built (step 5).
3. **Slot enforcement** — a missing slot marks the action *needs input* for routine/preventive
   care, and blocks the action entirely for pre-referral treatment, where a missing weight must
   block rather than blur. **Approved — implemented for the cohort sentence in step 3**: an absent
   slot is declared inside the text (`weight not recorded`) and the step is never dropped. The
   pre-referral blocking rule is still open, because a blocked dose needs the dispensing path, not
   just a sentence.

---

## 7. Build status — 2026-10-23, from test runs, not from intent

| Step | State | Evidence |
|---|---|---|
| 1 — fabricated numbers off the display path | **done** | `legacyConfidenceEstimate` deleted; `effectiveConfidenceScore` replaced by nullable `evidenceSufficiency`, which reads both the new `evidence_sufficiency` key and the legacy `confidence_score` key. SBAR now prints `Key measurements recorded: n of 100`, or `not captured` — never an invented figure. 6 tests in `test/engines/evidence_sufficiency_test.dart`, 2 in `legacy_enum_deserialization_test.dart`, wording pinned in `sbar_card_test.dart` |
| 2 — condition resolver | **done** | `lib/domain/engines/clinical_impression_resolver.dart`: 33 classification codes copied verbatim from the child, ANC and postnatal engines; 6-tier IMCI precedence; a code it has not been taught resolves to `needsReview` with its string intact rather than being guessed. 10 tests |
| 3 — kill the canned action lists | **done** | `_cohortNote` and `_cohortActions` deleted (95 lines of `static const` prose). Replaced by `lib/domain/engines/care_slots.dart`: `CareSlots` (name, age in days/months, weight, review interval) feeds `CohortCareGuidanceBuilder`, which **assembles** the sentence. The return-immediately signs are a cited data table because they genuinely are cohort-wide; the patient facts are what were missing. A slot with no value renders as `name not recorded` / `weight not recorded` and never interpolates `null`; newborns are stated in days, never months. Two invariants pinned by 12 tests in `care_slots_test.dart`: counselling is never lost to a missing slot, and the counselling action can never outrank a finding. Result screen now passes the real record in, so the callout names the child |
| 4 — margin + counterfactual | **done, and on screen** | `protocol_counterfactual.dart`: criterion margin with a declared 10% borderline band, counterfactual that re-runs `ChildEngine.assess`, nearest-flip search. 11 tests, including a guard that the 63-field `ChildInput.copyWith` cannot silently drop a field. Rendered as "Would a re-count change it" under the decision brief: `child_input_from_record.dart` rebuilds the input from the stored map and is **gated** — the rebuilt input must reproduce the stored classification exactly, or the line shows nothing. 9 domain tests + 3 widget tests, one of which asserts a maternal record stays silent |
| 5 — prioritiser (barrier-aware ordering) | **done, as a rule rather than a score** | `action_prioritizer.dart`. Ordering is lexicographic: urgency (the guideline's), then kind of action, then — only between those two ties — how far the household walks (`farWalkMinutes = 30`, published in the string). Pre-referral treatment is protected before distance is ever considered, and the facility test reads the engine's own `isReferral` flag, never keywords in the instruction. `ActionPrioritizer.explain()` is shown as the subtitle of PRIORITIZED ACTIONS, so the rule can be argued with. 9 tests. No numeric utility score exists, because there is no measured population to derive one from |
| 6 — verdict surface | **done, except the three bars** | The brief card now leads with the ranked condition name, then the urgency line, then the measurement and cut-off that produced it, then `Also classified:` and `Still outstanding:` for a pending test, then "Would a re-count change it" with the borderline value and the nearest flip the real engine would have called. All of it survives 320 px / 200% text (330 widget tests green). Still missing: the three-bar confidence decomposition as separate visual rows — its numbers exist and are truthful (evidence sufficiency, criterion margin, model contribution), but they are shown as sentences, not as gauges |
| 7 — conformance harness | **done** | `test/engines/guideline_conformance_test.dart` prints **`CAREBRIDGE GUIDELINE CONFORMANCE: 11/11`** and asserts it, so CI fails on drift. It caught a live defect: dysentery named ciprofloxacin in its finding while no action carried it. Fixed in `child_engine.dart`; the dose is deliberately *not* computed, because this build holds no cited ciprofloxacin strength table |
| 8 — escalate-only fusion gate | **deliberately not built** | The repo currently guarantees the *stronger* property, and it is tested: "research-only signals cannot add a PSBI treatment or referral" and "an experimental model label cannot force urgent triage". Turning that into an escalate-only permission would weaken a passing safety guarantee in the same week it is being judged, and doing it honestly needs a `referral_source` column plus a migration that cannot be verified without a device. Left as the next unit of work, not half-built |

Also fixed on the way: `ai_pitch_copilot.dart` claimed "over 160 automated tests" (the true figure is over 1,300) and "absolute patient privacy" (the honest claim is data kept on the device by default). Both were contradicting the deck from inside the app.

Verification for this pass: **whole suite — 1353 tests passed, 9 skipped, 0 failed** (1332 before
this pass plus the 21 new tests), including the conformance print; `flutter analyze` — **28 issues,
all pre-existing**, none in a file touched here. Nothing committed.

### Ordering fix found on the way

Adding a cohort teach-back action exposed a latent bug: `_orderActions` sorted by urgency then
category, and **broke no tie between actions of equal rank** — and `List.sort` in Dart is not
stable. Two counselling actions could therefore swap places between builds, so the worklist order,
its screenshots, and a CHO's muscle memory were a coin toss. `_orderActions` now decorates with the
production index and uses it as the final tie-break. `recommendation_engine_test` was updated from
`actions.last == 'Counsel on feeding'` (which had been passing by luck) to asserting the whole
urgency sequence.

### What changed in the honesty position

Two invented numbers are gone from the product. The first was the bucket→percentage estimate
(95/82/65/45) that could appear beside a clinical verdict. The second was the reasoning engine's
`ci95` range and its `confidencePct` blend: the band width and the 45/55 weights were chosen
constants, not measurements, and both fields were dead on every screen anyway. What the system
states now is an evidence figure it actually computes, a margin a clinician can walk through, and a
conformance count anyone can re-run — which is a stronger claim than the invented ones were
pretending to be.
