# CareBridge AI — How the App Works, Start to Finish

> An offline-first, AI-assisted community health companion for **frontline health
> workers (FHWs)** and **caregivers** in Northern Ghana. This document walks the
> whole product the way a person actually experiences it: from the first tap on
> the icon, through a complete household visit, down to the moment a record
> lands in the district database.

---

## 1. The big picture

Two people share one app, and they see two completely different products:

| | **Frontline Health Worker (FHW)** | **Caregiver (a mother / father)** |
|---|---|---|
| **Who** | The community health nurse covering a zone of 200+ compounds | A parent looking after one family |
| **Gets** | A ranked daily plan, clinical assessment tools, referrals, zone insights | Danger-sign triage, family schedule, a way to report problems |
| **Cannot do** | — | No clinical forms, no measurements, no diagnosis — by design |

Three ideas hold the whole thing together:

1. **Offline-first.** The phone's own database is the source of truth. Every
   record is saved locally *first*, then synced when there is signal. A visit
   in a compound with no network works exactly the same as one with full bars.
2. **AI that explains itself.** Every recommendation shows the measurement, the
   cut-off it crossed, and the guideline it came from. A health worker who
   cannot see the arithmetic cannot defend the decision — and a decision they
   cannot defend gets ignored.
3. **The referral is not the end.** The app tracks whether a referral was
   actually completed, asks *why* a family couldn't get care, and turns those
   answers into evidence the district can act on.

---

## 2. Opening the app — first run

```
Splash  →  Onboarding  →  "Who are you?"  →  Sign in / Create account  →  Home
```

1. **Splash.** The heart-and-cross logo, a photo of a real community health
   worker with a mother and baby, three promises (*Works Offline · AI Guidance ·
   Community First*), and a green **"WORKS OFFLINE — your data is safe on this
   device"** badge. It moves on by itself after ~2 seconds, or on a tap.

2. **Onboarding** (first launch only). Three short screens explaining what the
   app does — mothers, newborns and under-fives are assessed together in one
   visit, no child is left out.

3. **"Who are you?"** The single most important fork in the app. Pick
   **Frontline Health Worker** or **Caregiver**. The choice decides everything
   that follows.

4. **Sign in / Create account.** A real, on-device sign-in: phone number +
   PIN. No demo shortcuts.
   - A **health worker** registering fills in their *professional identity*:
     the zone they cover, the facility they refer to, their staff number. These
     are not decoration — the zone decides which households appear in their day
     plan, and the facility is printed on every referral slip they issue.
   - A **caregiver** enters a **family code** the health worker reads out to
     them. Their account is permanently bound to that one household. There is
     no field that could widen that scope — a caregiver can only ever see their
     own family.

5. **Home.** The worker lands on their dashboard; the caregiver lands on their
   family. From now on, opening the app goes straight to the right home.

---

## 3. The health worker's day — five tabs

The bottom navigation is ordered the way a working day actually runs.

### Home ("Today")
A glance, not a list. Counts of what matters this morning and a way to start a
visit. The first question every morning is *"what does my day look like?"* and
the answer is a number.

### Visits ("Plan My Day")
The ranked queue of who to see, **and the reason for every position**. This is
the answer to *"predict risk before the crisis"*: a worker with a paper
register visits by proximity and memory, so the quiet household with the
declining child is seen last. Here the order is computed. The ranking is a
clinical judgement, in three sections:

1. **Unconfirmed urgent referrals** — someone was told to go to a facility and
   nobody knows whether they did. Nothing outranks this.
2. **Overdue scheduled contacts** — a missed day-3 postnatal visit is the
   interval where most newborn deaths in this region happen.
3. **Ranked households**, most critical first, each with its reason.

### Assess
The register with a fast launch point. Search any compound and start a clinical
assessment straight from the bottom nav, without opening the detail screen
first.

### Referrals
Open work that does not depend on a household visit — referrals that need a
phone call, not a walk. Track who confirmed, who completed, who needs a
follow-up.

### Me
Sync status, account details, voice/language settings, and an **obvious sign
out** — because handing the phone to a mother to use caregiver mode is a normal
part of the day, not an edge case.

---

## 4. A household visit, step by step (the heart of the app)

This is the core journey. It is designed so a multi-person visit feels like
**one encounter**, not three separate ones.

```
Start the visit
      │
      ▼
"What's getting in the way?"        ← barriers to care (once per visit)
      │
      ▼
"Who is here today?"                ← roll call: mark who is present
      │
      ▼
Assess each person (in clinical order: mother → newborns → under-fives)
      │
      ▼
Result screen per person            ← findings, nutrition, immunisation, referral
      │
      ▼
Household summary + sign-off        ← the whole compound at a glance
```

### Step 1 — Start the visit
From the household screen, **Start the visit**.

### Step 2 — "What's getting in the way?"
Before anyone is seen, one quick question: *"What makes it hard for this family
to get care?"* — no money for transport, the facility is too far, needs a
husband's permission, no NHIS card, a flooded road, a bad past experience, and
more.

This is not a formality. It does two things:
- **Solve the problem while the family is still there.** If transport is the
  barrier, arrange a *motorking* or link them to a transport fund *today* —
  instead of discovering two days later that the referral failed. The app uses
  past answers to *predict* what will stop this specific family and estimates
  whether a referral issued right now is likely to be completed.
- **Turn individual answers into evidence.** Six unrelated families all
  reporting *"the facility was closed"* is not six family problems — it is one
  facility problem. The app aggregates these into zone-level patterns a
  supervisor can escalate.

It **never blocks care** — there is always a *Skip*.

### Step 3 — "Who is here today?" (the roll call)
Everyone registered in the compound is listed; the worker unticks anyone who is
not here and notes where they are. Two deliberate rules:
- **Absence is recorded, not skipped.** *"The baby is with the grandmother"* is
  exactly the signal that finds a child who is never brought for care.
- **The queue is in clinical order** — mother, then newborns, then under-fives
  by age — the order care is actually delivered. If someone new showed up, they
  are registered on the spot and loop straight back into the same roll call, so
  they are seen in *this* visit, never a second trip.

### Step 4 — Assess each person
The app picks the right protocol automatically from the person's **age-derived
type** — a baby registered as a newborn who has turned three months is assessed
on the sick-child chart without anyone relabelling them. Protocols cover the
young infant, the sick child, and the mother (ANC/PNC).

The worker enters measurements (a live **MUAC gauge** shows the nutrition zone
as the tape value is typed), answers danger-sign questions, and the clinical
engines run.

### Step 5 — The result screen
What the protocol found, and what to do about it — always explainable:
- **Findings** carry the value, the cut-off it crossed, and the guideline.
- **Growth** is plotted against WHO standards with a trend (a child *losing*
  weight while on treatment is escalated immediately).
- **A nutrition plan** built from *local, seasonal foods* — not a generic
  leaflet.
- **Immunisation** status and what is due.
- **A referral** that names the specific facility and the capability it needs,
  if one is warranted.

Saving is **one action**: the assessment, its referral, and its follow-up
schedule land together or not at all.

### Step 6 — Household summary & sign-off
After the last person, the worker sees the whole compound at a glance: everyone
seen today with their risk badge, the referrals that went out, and a visit
note. Then they sign the encounter off. If the phone is offline, the banner is
never an error — *"saved locally, will sync when connected"* — because a worker
who just finished a three-person visit with no signal needs to trust the record
is safe.

---

## 5. The caregiver's experience — four tabs

The caregiver's app is defined by what it *deliberately lacks*: no clinical
forms, no measurements, no diagnosis.

### Home
A greeting, the family they care for, and a **"check someone now"** button.

### My family
Every member with their last-known triage, upcoming visits, and open referrals.
Where to look when the health worker calls and asks *"is the family OK?"*

### Check-In (the danger-sign triage)
A calm, five-step check: pick the person → answer danger-sign questions →
result → tell the CHW → what to watch for.

Every question allows **yes / no / not sure** — because a mother who is *"not
sure"* is not lying, and forcing a yes/no gives the wrong answer. The result is
one of three clear recommendations:

- 🔴 **Go to the health facility now**
- 🟡 **Visit your CHW soon**
- 🟢 **Continue routine care**

This is **guidance, never a diagnosis** — the app must never turn a mother's
checklist into a clinical record.

### Profile
The language they hear advice in (including **Dagbani voice guidance**),
sign-out, and the help line.

---

## 6. How the data flows — offline-first, then up to the district

```
        ON THE PHONE (always works)              TO THE DISTRICT (when online)
 ┌──────────────────────────────────┐    ┌──────────────────────────────────┐
 │  Every save does TWO things      │    │  Phone SQLite                    │
 │  in ONE transaction:             │    │     │  (queued "outbox" rows)     │
 │   1. write the record            │    │     ▼                            │
 │   2. queue it in the outbox      │    │  Sync service — opportunistic,   │
 │                                  │    │  priority-ordered, batched,      │
 │  SQLite = source of truth        │    │  retries with backoff            │
 └──────────────────────────────────┘    │     │  HTTPS + token             │
                                         │     ▼                            │
                                         │  Node/Express sync server        │
                                         │     │  (validates, whitelists)   │
                                         │     ▼                            │
                                         │  MariaDB (carebridge database)   │
                                         │     + sync_log audit trail       │
                                         └──────────────────────────────────┘
```

- **Local first.** The phone never needs the network to do its job. Records are
  written to an on-device SQLite database, and a matching "outbox" row is queued
  in the *same* transaction — so a record is either fully saved-and-queued, or
  not at all.
- **Sync is opportunistic.** A background service pushes queued records when
  connectivity returns (and every so often as a safety net). **Urgent referrals
  go first.** Failed sends are retried with backoff; they are never lost.
- **The phone never touches the database directly.** It talks to a small
  Node/Express server over HTTPS with a token. Embedding database credentials
  in the app would be a security disaster, so the server is the only bridge.
- **Idempotent by design.** If a send is retried (lost signal mid-upload), the
  server *upserts* — it can never create a duplicate child.
- **Audited.** Every record that arrives is logged in a `sync_log` table
  (what, when, which device) — without storing any patient details in the log.

**To see the data:** open a `mysql` terminal and query the `carebridge`
database — `SELECT * FROM carebridge.sync_log ORDER BY id DESC;` shows every
record the phones have pushed, with timestamps.

---

## 7. Safety, privacy and trust

- **Three layers of access control.** Route guards keep a caregiver away from
  worker screens, the UI hides what you cannot do, and — the real boundary —
  the **repository re-checks permission on every single write** and writes an
  audit row on refusal. A forged deep link still stops at the repository.
- **Capability-based, not role-based.** Screens declare *what needs doing*
  (e.g. "run a clinical assessment"), not *who is allowed*. Adding a new role
  later means editing one permission set, not hunting through the UI.
- **Credentials stay on the device.** The PIN is stored as a salted hash
  (HMAC-SHA256), never in plain text, and is **never synced** to the server.
  The session lives in secure storage.
- **The caregiver's scope is fixed at account creation** — bound to one
  household by a family code, with no way to widen it.
- **Explainable AI is a safety feature, not a nice-to-have.** Every
  recommendation shows its working and states its confidence (*protocol-based /
  high / moderate / low — follow protocol*). A tool that admits when it is
  guessing gets trusted when it is not.

---

## 8. The intelligence underneath (the clinical engines)

All clinical logic lives in pure, testable "engines" — no UI, no database —
so every rule can be verified on its own.

| Engine | What it does |
|---|---|
| **Young infant / sick child / ANC / PNC** | The clinical protocols (IMCI-style danger signs, antenatal & postnatal care) |
| **Growth Z-score** | MUAC, weight & height against WHO standards |
| **Trajectory** | Growth *trends* — a falling curve is caught before it crosses a line |
| **Treatment response** | Weight gain on therapeutic feeding — flags a child not responding |
| **Nutrition** | Feeding plans from local, seasonal foods |
| **Immunisation** | What is due, what is overdue |
| **Barrier** | Predicts what will stop a referral; finds zone-wide patterns |
| **Vulnerability** | Scores households to rank the day plan |
| **Measurement safety** | Rejects implausible readings before they poison the record |
| **Recommendation** | Combines it all into explainable, confidence-rated guidance |

---

## 9. Quick reference — the journey in one line

**First run:** Splash → Onboarding → "Who are you?" → Sign in / Register → Home.

**A worker's visit:** Start the visit → "What's getting in the way?" → "Who is
here today?" → Assess each person → Result (findings · nutrition · referral) →
Household summary → Sign off → *record queued* → Sync to MariaDB when online.

**A caregiver's check:** Open app → Check someone now → Answer danger signs
(yes / no / not sure) → One of three clear actions → Tell the CHW → Watch for.

**The data:** Saved on the phone first, always → synced to the district
database when there is signal → visible in `mysql` under `carebridge`.
