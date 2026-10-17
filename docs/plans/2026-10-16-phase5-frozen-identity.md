# Phase 5 — frozen UI identity on the judge click-path

Date: 2026-10-16 · Owner: design/systems pass · Status: **shipped**, incl. the verdict's signature

## Verification record (2026-10-16)

- `flutter analyze --no-pub`: 20 issues, zero errors — identical to the pre-work
  baseline.
- Judge-path widget sweep green across `result_screen_triage`,
  `result_page_simplification`, `assess_tab`, `fhw_today_tab`,
  `fhw_clinic_header`, `day_plan_worklist`, `referral_follow_up`,
  `fhw_flow_overflow`, `sbar_card`, `luxe_components`, `clinic_queue`,
  `caregiver_flow`, `glass_surface`, `vitals_station` (137 in one batch, 61 in
  another), plus `follow_up_desk` (19) and `household_region_scope` (1).
- Full suite: **997 passed, 4 skipped, 8 failed.** All 8 failures pre-date this
  work and sit outside its edit set — 2 in `caregiver_planners_test` and 2 in
  `follow_up_record_test` (both exercising the working tree's in-flight domain
  changes), and 4 in `pre_referral_dispensing_test`, which asserts a
  `FOR THIS CHILD` label that exists in neither HEAD nor the working tree
  (`git grep -in "for this child" HEAD -- lib` proves it). Not caused here, not
  fixed here.

## What shipped

**Clinical colour, one source.** `AppColors` now owns the verdict as a surface:
`triageRedDeep/AmberDeep/GreenDeep`, `redPlate/amberPlate/greenPlate`,
`verdictInkOnRed/Amber/Green`, `emergencyGround`. `shared/ui.dart` adds
`triagePlate(level)` beside `triageColours(level)` — the only place a level
becomes a full-bleed plate. Every Tailwind red/amber/green on the verdict hero,
the handoff brief, the tunnel ground and the (unread) banner fields is gone.
Two real defects closed with it: white on `F59E0B` measures 2.2:1, so the amber
band now carries a near-black brown ink — the same choice the paper booklet
makes — and Priority/Watch deliberately share one amber plate instead of
inventing a fourth hue, since the words already name the level.

**The desk, one identity.** Lacquer ink and rules promoted to
`FhwLuxePalette.lacquerInk/lacquerRule/lacquerRuleQuiet`; warm ivory ink, cream
`line`, brass chrome and the borrowed `checkNavy/checkBlue` field left the desk
across `assess_tab`, `clinic_widgets`, `clinic_queue_screen`, `day_plan_tab`,
`referrals_tab`, `household_screen`, `families_tab`, `community_support_screen`,
`follow_up_check_in_screen`, `receive_patient_sheet` and `home_tab`. The step
rail is now one blue in three depths; the waiting chip is sapphire ice; a queue
accent no longer wears triage green, because green belongs to a child, not to a
ticket.

## The verdict's one risk

The handoff brief is drawn as a document, not another glass card. Its plate
keeps the clinical hue and gains a single lit hairline across the crown — one
pixel, the difference between a coloured rectangle and a stamped label. Beneath
the plate the brass rule is **perforated**: a line of punches, fading in from
the left and running out at the right, marking the fold between the verdict
that was decided and the reasoning that defends it. A divider here had to mean
a real division, and the division this record has is the one the paper chart
has — the part that is settled, and the part that goes with the child. Static
paint, no blur, no loops, no new string, so every pinned assertion on the page
still holds.

## Follow-on same day: the cross-worker caseload (the storage complaint)

The judges returned to storage: a patient seen by one FHW must be findable by a
different FHW the next day, on a different handset, and the record must be
reportable to a hospital. Two real defects were behind it, both half-built work:

1. **Client and server defined the same permission differently.** The local
   register is region-wide (`HouseholdDao.caseloadFor`: `created_by OR region`),
   pinned by `test/household_region_scope_test.dart`. The server read paths
   (`pull.js householdScope`, `recovery.js handleCaseloadRestore`) used
   `(region = ? AND district = ? AND community = ?) OR created_by = ?`. A
   colleague's rows were lawful for a nurse to see and never crossed the wire,
   so her search came back short with no error raised. Both now use
   `created_by = ? OR` a tolerant mutual-prefix region match, so an account
   whose region reads 'Northern' still receives families stored as 'Northern
   Region'.
2. **Referrals could not propagate downward.** `pull_service.dart` merged
   referrals with insert-if-absent on the theory that the table is append-only.
   It is not — a status is revised in place on the same row id. So a facility
   confirming arrival, or a colleague recording that the family never came,
   never reached the nurse who issued the referral. `_mergeReferral` now applies
   the newer server state, refuses to overwrite a local row whose outbox entry
   has not been pushed, and refuses to reopen a settled referral.

Proof, not assertion: `node scripts/verify-caseload.js` drives only the public
API as two handsets do — 9/9, including the privacy boundary (a North East nurse
receives nothing) and a delta pull re-offering a referral whose status changed.

Also restored the same day: `caregiver_today_planner.dart` had lost two shipped
features to an over-broad edit in the working tree — the "I have arrived" cue
that stops nagging a family who already went to the facility, and the recheck
promise that surfaces today until discharged. Nothing of value was in the deleted
state (the diff was deletions plus brace formatting), and the diff is preserved
in `.d_tp.txt`.

Suite after all of this: **1008 passed, 4 skipped, 0 failed** — green for the
first time this session. Open items unchanged: LWW clock skew on households and
persons, and recovery's blind `ConflictAlgorithm.replace`.

## What the judges click through

`demo/DEMO_SCRIPT.md` beats 2–12 map to these surfaces, and only these:

| Beat | Surface | File |
|---|---|---|
| 2–8 | caregiver check → verdict → ask for help | `caregiver/check/triage_screen.dart`, `assessment/result_screen.dart` |
| 10–11 | FHW desk: queue, register, referrals trace line | `fhw/home_tab.dart`, `fhw/assess_tab.dart`, `fhw/referrals_tab.dart` |
| 6–7 | the clinical verdict itself | `assessment/decision_workspace.dart`, `assessment/emergency_tunnel.dart` |

## Audit findings (evidence, not vibes)

### A — Clinical colour leak (severity: **high**, breaks the load-bearing rule)

`lib/core/theme/app_theme.dart:15-20` states the one rule that must never be
relaxed: the IMCI red/amber/green belong to clinical safety and are kept exactly
as trained. `AppColors.triageRed/Amber/Green` = `D32F2F / ED9B00 / 2E7D4F`, and
`ui.dart:triageColours()` is the single mapper. These surfaces bypass both and
paint Tailwind defaults (`DC2626 / F59E0B / FBBF24 / 10B981`) — a different red,
a different green — on the two screens a clinician audits hardest:

- `assessment/result_screen.dart:1664-1685` — `_DecisionBriefCard._headerGradient`
  (the handoff brief plate a receiving doctor reads)
- `assessment/decision_workspace.dart:58-83,146-151` — `ClinicalDecisionHeader`
  plate + shadow (the verdict hero itself)
- `shared/premium_cards/triage_banner.dart:46-63` — plate + shadow (unused today)
- `core/theme/premium_design_tokens.dart:70,75` — `urgentCard()` (unused today)
- `assessment/emergency_tunnel.dart:277` — raw `2B0708` tunnel ground

A second, real defect hides in the same code: white text on `F59E0B` measures
~2.2:1. The amber verdict hero has been failing AA on the classification line.

### B — Warm identity left inside the cool FHW desk (severity: medium)

`fhw_luxe.dart` froze the desk as *Pure White & Royal Sapphire* (porcelain
canvas, sapphire lacquer, cool slate ink). The warm "Clinical Luxe, ivory +
brass" tokens still leak onto the desk the judges see:

- `fhw/assess_tab.dart:118-186,408-455` — search field on `checkNavy/checkBlue`,
  `inkMuted` body ink, and a **brass** waiting chip on a sapphire desk
- `fhw/clinic_widgets.dart:749-804` — `ClinicStepHeader` runs completed steps
  into `brassEdge` and rests the track on warm `AppColors.line`
- `fhw/clinic_widgets.dart:270-277,806-865` — card/status ink is warm `inkMuted`
- `fhw/day_plan_tab.dart:120-476`, `fhw/referrals_tab.dart:359` — body text in
  warm `AppColors.ink` (teal-charcoal) on a cool white desk

### C — Unpromoted magic numbers (severity: low, but they are the drift risk)

`0xFFDCE9FF` (body ink on a lacquer panel) is hard-coded 6× across
`home_tab.dart`, `referrals_tab.dart`, `clinic_widgets.dart`; the panel rules
`0x24FFFFFF` / `0x14FFFFFF` likewise. They are *in* the identity but not *of* it.

## The fix, in order

1. **Plate tokens** in `AppColors`: `triageRedDeep/AmberDeep/GreenDeep`,
   `redPlate/amberPlate/greenPlate`, `verdictInkOnRed/Amber/Green`. One hue
   source, depth added by darkening the trained hue, never by swapping it.
2. **`triagePlate(level)`** in `shared/ui.dart` next to `triageColours()` — the
   only place a level becomes a full-bleed surface. Amber's ink inverts to deep
   brown because no white can clear AA on a yellow, which is why the paper IMCI
   chart prints amber rows in black.
3. Replace every raw clinical hex from §A with those two seams.
4. **Lacquer tokens** in `FhwLuxePalette`: `lacquerInk`, `lacquerRule`,
   `lacquerHairline`.
5. Bring §B surfaces onto `FhwLuxePalette` ink and retire brass from the desk
   (brass stays in the caregiver/warm app, where it still belongs).
6. Verify: `dart format`, `flutter analyze` (baseline: 0 errors, pre-existing
   infos only), full widget sweep.

## Not doing

- No new blur (`BackdropFilter` is rejected for low-end handsets — see the
  frozen decision).
- No dark mode for the desk; a field compound is bright sunlight.
- No third font; only bundled Sora/Manrope/Inter render offline.
- `profile_tab.dart` warm tokens stay — it is not on the click-path and was
  already corrupted once by an over-broad edit. Touch it only if the verdict
  screen work needs it.
