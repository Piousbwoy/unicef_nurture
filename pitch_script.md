# CareBridge AI — Pitch Video Script

> **Total runtime:** ~3 minutes · **Narrator voice:** AI (Microsoft "Andrew" neural)
> **How to film:** the app runs in Chrome/Edge inside an iPhone frame, so screen-record
> yourself clicking through the *real, live app* while this narration plays over it.
> The `[ON SCREEN]` lines tell you what to click at each moment.

---

## 0:00 — THE HOOK

**[ON SCREEN]** Black screen, or a slow zoom on the splash hero photo (a community
health worker with a mother and baby).

> In Northern Ghana, the distance between a sick child and care is rarely measured
> in kilometres. It's measured in money for a motorking, in a flooded road, in a
> grandmother's doubt. And when that child never shows up, the register simply
> says: *did not attend* — and stops there.

## 0:22 — THE PRODUCT

**[ON SCREEN]** The CareBridge splash screen — logo, the "Works Offline · AI
Guidance · Community First" pills, and the green WORKS OFFLINE badge.

> CareBridge AI is built for that exact moment. It's an offline-first, AI-assisted
> health companion that puts a clinical decision-support tool in the hands of the
> community health worker — and a lifeline in the hands of a mother. No signal
> required.

## 0:38 — TWO ROLES, ONE APP

**[ON SCREEN]** The "Who are you?" screen. Tap Frontline Health Worker → the
registration form (zone, facility, staff number). Then (briefly) the caregiver's
family-code screen.

> Two people share one app. The health worker signs in with a PIN and registers the
> zone they cover and the facility they refer to. A mother signs in with a family
> code that binds her to her own household — and nothing else. Her scope is fixed
> the day the account is created.

## 0:55 — THE WORKER'S MORNING

**[ON SCREEN]** The Today tab (counts at a glance), then the **Visits / Plan My Day**
tab — scroll the ranked list so the reasons under each household are visible.

> Every morning, the app plans the worker's day. Not by memory, not by proximity —
> by risk. Unconfirmed urgent referrals first. Overdue newborn visits second. Then
> every household, ranked — and this is the part that decides whether a tool gets
> used — every position comes with its *reason*.

## 1:14 — THE VISIT: WHAT'S GETTING IN THE WAY?

**[ON SCREEN]** Open a household → tap **Start the visit** → the
*"What's getting in the way?"* screen. Tap one or two barriers (e.g. "No money for
transport").

> At the compound, a visit is one encounter, not three. It begins with one question:
> *what's getting in the way?* Because a referral note is not care. If transport is
> the barrier, the worker solves it now — while the family is still in front of
> them — not two days after the referral fails.

## 1:33 — WHO IS HERE TODAY?

**[ON SCREEN]** The *"Who is here today?"* roll call — tick the family members
present, then the assessment queue in clinical order.

> Then: *who is here today?* Everyone is ticked off — because the child who wasn't
> brought is the one who never gets measured. Absence is recorded, not skipped.

## 1:47 — THE ASSESSMENT (EXPLAINABLE AI)

**[ON SCREEN]** The child assessment form — type a MUAC value and let the **live
MUAC gauge** move into a nutrition zone; answer a danger-sign question.

> Each person is assessed on the right protocol, chosen automatically from their age.
> A MUAC tape reading becomes a nutrition zone in real time. And every
> recommendation explains itself — the value, the cut-off it crossed, and the
> guideline it came from. A health worker who can see the arithmetic can defend the
> decision.

## 2:07 — THE RESULT: A PLAN, NOT A PARAGRAPH

**[ON SCREEN]** The result screen — scroll past the findings, the feeding plan
(local foods), the immunisation row, and the referral card. Tap **Save**.

> The result is a plan, not a paragraph: a feeding plan built from local, seasonal
> foods, the vaccines that are due, and — when needed — a referral that names the
> right facility for the job. Assessment, referral and follow-up are saved together,
> in one tap, completely offline.

## 2:26 — THE DATA REACHES THE DISTRICT

**[ON SCREEN]** The Me tab → "Send everything now". Then cut to a **terminal** running
`mysql` — `SELECT * FROM carebridge.sync_log ORDER BY id DESC;` showing the rows land.

> When the phone finds signal, everything syncs — securely, and without duplicates —
> up to the district database. And "did not attend" finally becomes evidence: six
> families reporting a closed facility is no longer six excuses. It's one problem
> the district can actually fix.

## 2:47 — THE MOTHER

**[ON SCREEN]** Switch to the caregiver role — the caregiver Home, then the Check-In
danger-sign flow: answer a few questions, land on one of the three colour-coded
recommendations.

> And back at home, a mother opens the app, answers a few danger-sign questions —
> yes, no, or *not sure* — and gets one of three clear answers: go now, see the
> nurse soon, or keep going. Guidance, never a diagnosis.

## 3:02 — THE CLOSE

**[ON SCREEN]** Back to the splash logo, or a still of the health worker and mother.

> CareBridge AI. Offline-first. Explainable. And built so that no child is lost
> between the referral and the treatment. Thank you.

---

## Production notes

- **Voiceover file:** `pitch_voiceover.mp3` (generated with edge-tts, "Andrew" voice).
- **To re-generate or change the voice:** see `make_voiceover.ps1`.
- **Free editors to combine video + voice:** CapCut (easiest) or Clipchamp (built
  into Windows 11). Drop the screen recording on the video track, the MP3 on the
  audio track, and trim the clips to the timing marks above.
- **Record the app:** run `flutter run -d chrome` (or serve `build/web`), put the
  browser in full screen, and record with Windows' built-in **Xbox Game Bar**
  (Win + G) or OBS (free).
