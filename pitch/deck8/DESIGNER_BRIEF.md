# CareBridge AI — 8-Slide Deck: Designer Build Sheet

**What this document is:** the build instructions. Everything here is slide-ready — exact strings,
positions, sizes, colours, click order. Hand this file to the designer as-is.
**What it is not:** the speaker script. That stays in `pitch/deck8/SEQUENCE.md`. Where this file
gives a `SPEAKER` line it is copied from `SEQUENCE.md` and must not be reworded on stage.
**Deliverable:** one `.pptx`, 8 slides, 16:9, plus a PDF export. Section 7 lists what to hand back.
**Hard rule:** no string on any slide may be changed without checking `SEQUENCE.md`'s `DON'T SAY`
list. Truncating is allowed. Rewording a clinical or accuracy claim is not.

---

## 0. The idea that governs every slide

This deck is judged by nurses, engineers and officials in six minutes, after teams who promised
validated AI. Our whole argument is that **we can be checked**. So the layout does the arguing:

### 0.1 The Proof Line (signature element — all 8 slides)

A single small monospaced line, bottom-left, in the same position and size on every slide:

```
PROVEN BY · lib/domain/governance.dart + 20 test files
```

- Consolas 15px, `#A8C2E8` at 85%, letterspacing 0.6px, uppercase only for the words `PROVEN BY`.
- It names a real file (or artefact) from the repository. It is never a URL, never "internal data".
- **Rule that decides content:** if a number or claim cannot fill its proof line, it does not go on
  the slide. The proof line is the editor, not a caption.
- Never animated, never coloured, never larger. It is the deck's spine.

### 0.2 The Limit Chip (recurring element — slides 2, 6, 7, 8)

An admitted weakness, drawn as a labelled chip rather than hidden in a footnote. Same chip design
everywhere: 2px outline in triage amber `#ED9B00`, transparent fill, Manrope SemiBold 17px, amber
text, 8px radius, height 44px.

The four chips, verbatim:

| Slide | Chip text |
|---|---|
| 2 | `REASON FOR A MISSED REFERRAL — NEVER CAPTURED ON PAPER` |
| 6 | `WEB / DESKTOP: NOT ENCRYPTED AT REST` |
| 7 | `4 CONTROLS ARE NOT OURS TO IMPLEMENT — OWNER NAMED` |
| 8 | `DAGBANI SPEECH INPUT OFF · CER 0.420` |

- This is the second-most important visual in the deck. It is what makes the first 7 slides
  believable. Do not soften it, do not turn it red (red is reserved for clinical urgency, and there
  is none on this deck), do not add a warning triangle.
- Slide 6's chip should sit inside a mock of the app's own posture card (see 3.6) so it reads as
  *the app saying it*, not us apologising.

### 0.3 The paper insert (slides 2 and 5 only)

One panel per those two slides uses the register palette: background paper `#FBF8F1`, text
paper-ink `#0A192F`, 1px dashed rules `#9AA3B2`. Everywhere else the deck is dark. Paper means
*the old way*; it must never be used for our own data.

### 0.4 What is forbidden on every slide

Stock photography of children or clinics (we have no licensed images and dignity comes first) ·
icons standing in for meaning · gradients except the two in section 1.4 · emoji · logos of UNICEF,
GHS, WHO or MEST (the event is not an endorsement) · any accuracy figure absent from
`assets/models/*_metrics.json` · the words *revolutionary*, *state-of-the-art*, *AI-powered
diagnosis*, *100% secure*, *fully compliant*, *validated in Ghana*.

---

## 1. Design system

### 1.1 Canvas

1920 × 1080 px, 16:9, dark deck. Build at 1920 and scale; do not build at 1280.

### 1.2 Palette — taken from the shipped app, do not invent values

| Token | Hex | Use |
|---|---|---|
| `midnight` | `#081938` | slide background, all slides |
| `deep` | `#0D285F` | primary panel |
| `command` | `#0B2354` | secondary panel, table body |
| `electric` | `#2970FF` | the single accent: numbers, active states, the ask |
| `ice` | `#E8F1FF` | primary text |
| `ink-dim` | `#A8C2E8` | secondary text, proof line, captions |
| `rule` | `#1C3A72` | 1px dividers, table row rules |
| `paper` | `#FBF8F1` | the two register panels only |
| `paper-ink` | `#0A192F` | text on paper |
| `amber` | `#ED9B00` | Limit Chips only |
| `red` | `#D32F2F` | **unused on this deck.** It is the app's clinical urgency colour; nothing here is urgent |
| `green` | `#2E7D4F` | the "in place" tally on slide 6 only |

Source of truth for the three clinical hues: `lib/core/theme/app_theme.dart` (`AppColors`, commented
*clinical safety, never decoration*). Keeping red off the deck is a deliberate choice — a judge
should not see our brand colour doing the same job as a triage badge.

### 1.3 Type

Bundled in the repository at `assets/fonts/` — install from there, do not download anything
(the venue may be offline).

| Role | Font | Size | Weight | Colour | Notes |
|---|---|---|---|---|---|
| Display line | Sora | 76 | ExtraBold 800 | `ice` | slides 1, 5 closing line |
| Slide headline | Sora | 48 | Bold 700 | `ice` | left-aligned, max two lines |
| Panel title | Manrope | 26 | ExtraBold | `ice` | |
| Body | Manrope | 21 | Medium 500 | `ice` at 92% | line-height 1.5, max 62 characters |
| Secondary | Manrope | 18 | Regular | `ink-dim` | |
| Eyebrow / tag | Consolas | 14 | Regular | `electric` | 2.4px letterspacing, uppercase |
| Big number | Sora | 96–120 | ExtraBold | `electric` | tabular figures |
| Proof line | Consolas | 15 | Regular | `ink-dim` 85% | see 0.1 |
| Table text | Manrope | 19 | Regular / SemiBold | `ice` | |

If the tool cannot install TTFs, fall back to Segoe UI for body and keep the sizes; **do not
substitute a serif or a condensed face.** Embed fonts in the `.pptx` (File → Options → Save →
Embed fonts) so the venue laptop renders them.

### 1.4 Surfaces

- Panels: `deep`, 8px radius, no shadow except a 1px top hairline at 18% white (the app's lacquer
  edge — one pixel, structural, not a glow).
- Two gradients are permitted, both copied from `lib/core/theme/lumen.dart`, used once each:
  slide 4's rail line (`#2E73FF → #1B56DB → #0D2E73`) and slide 8's table header fill
  (`#0C2350 → #123E93`). Nothing else gets a gradient.
- No drop shadows, no blur, no cards inside cards.

### 1.5 Grid and chrome

- Margins: 100px left and right, 80px top, 64px bottom. 12 columns, 24px gutters.
- Every slide carries the same chrome:
  - **top-left eyebrow** (Consolas 14px, `electric`, uppercase) — the section name:
    `01 THESIS` · `02 PROBLEM` · `03 USERS` · `04 WORKFLOW` · `05 REFERRAL` · `06 SECURITY` ·
    `07 COMPLIANCE` · `08 AI + LANGUAGE`
  - **bottom-left proof line** (0.1)
  - **bottom-right pagination** — Consolas 14px `ink-dim` 60%: `CAREBRIDGE AI · 04 / 08`
- Content never touches the margins. Nothing overlaps the chrome.

### 1.6 Motion

PowerPoint click builds, **maximum one build per slide**, 300ms fade, no wipes, no flight paths, no
motion on the chrome or the Limit Chips. Each slide's build order is listed per slide below; if the
tool or the projector is unreliable, ship static and lose nothing.

---

## 2. Flow and timing

| # | Slide | Beat | Time | Cumulative |
|---|---|---|---|---|
| 1 | CareBridge AI | Thesis | 0:30 | 0:30 |
| 2 | The problem | Why it hurts | 0:50 | 1:20 |
| 3 | Who it is for | Three users | 0:40 | 2:00 |
| 4 | How care happens | The loop | 1:00 | 3:00 |
| 5 | The referral | Closing the loop | 0:50 | 3:50 |
| 6 | Security | Bars, not promises | 0:50 | 4:40 |
| 7 | Compliance | Proof, not policy | 0:45 | 5:25 |
| 8 | AI, recommendation, language | What is trained, gated, refused | 0:35 | 6:00 |

Slide 5 and slide 8 are the two that win marks. If the room runs late, cut slide 3's third row
never — cut words from slides 2 and 4 instead. Slides 5 and 8 are never shortened.

---

## 3. Slide-by-slide build sheets

### 3.1 SLIDE 1 — CareBridge AI · 0:00–0:30

**Job:** set the honesty contract before anyone suspects it.

**Layout** — deliberately near-empty. Three lines of display type, left-aligned, starting at
column 1, vertically centred slightly above middle. Below them a 1px `rule` hairline, 620px wide.
Under that, one line of body. Nothing else on the slide. No image, no logo, no gradient.

**On-slide copy** (columns show the element, not the layout):

> **CareBridge AI**  — Manrope 26 ExtraBold, `electric`, eyebrow position above the display block
>
> Guidelines decide.
> Models support.
> Nothing leaves the phone.
> — Sora ExtraBold 76, `ice`, one line each, tight 1.05 leading. The three lines are the same size;
> do **not** make "Nothing leaves the phone" bigger or coloured — the rule is that none of them is.
>
> *Offline maternal, newborn and child care for Northern Ghana*
> — Manrope 21 Medium, `ink-dim`

**Proof line:** `PROVEN BY · 16 guideline engines in lib/domain/engines/`
**Build:** the three display lines fade in as one block, on the speaker's first breath.
**SPEAKER (30s):** "Every clinical decision in this app is made by a Ghana IMCI guideline, on the
phone, with no network — and the AI is deliberately not allowed to overrule it."
**Rules:** no sub-headline, no "hackathon entry" line, no team names on this slide.

---

### 3.2 SLIDE 2 — The problem · 0:30–1:20

**Job:** make an invisible paperwork gap visible. This slide must feel like a document, not a list.

**Layout:** headline top-left. Under it a row of three fact cells (columns 1–4, 5–8, 9–12).
Middle band: a paper panel on the left (columns 1–5) and a barrier cloud on the right (columns
6–12). Bottom: one pull line, left-aligned, with a 3px `electric` rule on its left.

**Headline:** `Survival here is decided by paperwork that stops early`

**Fact cells** (Sora ExtraBold 96 `electric`, label Manrope 18 `ink-dim` beneath):

| Value | Label |
|---|---|
| **1,000+** | residents per frontline worker in a CHPS zone |
| **90 s** | of usable signal — the design condition, not an edge case |
| **12** | named barriers that stop a referral — each with a different owner |

**Paper panel (left, `#FBF8F1`)** — style as a register extract, 1px dashed rules between rows,
Consolas 16 `paper-ink`:

```
SAVELEGU ZONE B · CHPS SUB-DISTRIBUTION REGISTER
FAMILY ................ AKOSIA Y.
REFERRAL .............. 14 OCT
ATTENDED .............. ☐
NOT ATTENDED .......... ☒
REASON ................ ____________________
```

The `REASON` line is blank, and it is the whole point. Put the Limit Chip directly beneath it,
inside the paper panel but with the amber outline on the paper (it must read as an annotation the
paper cannot make): `REASON FOR A MISSED REFERRAL — NEVER CAPTURED ON PAPER`.

**Barrier cloud (right)** — 12 chips, no icons, Manrope 18 Regular `ice` at 90%, `command` fill,
4px radius, wrap in 3 rows. Exact 12 strings, from the `CareBarrier` enum:

`no money for transport` · `facility too far` · `needs permission from husband or family` ·
`no valid NHIS card` · `no one to mind the other children` · `facility closed / no staff` ·
`bad experience at the facility before` · `prefers traditional or spiritual care` ·
`fear of injection / surgery / blood test` · `farm or market workload` · `road flooded` ·
`did not think it was serious`

**Pull line (bottom, Manrope 21 Medium `ice`):**
> These twelve are written in code and counted by household. On paper, none of them exists.

**Proof line:** `PROVEN BY · CareBarrier enum, 12 values — lib/domain/enums.dart`
**Build:** the 12 barrier chips fade in together, after the paper panel is read.
**SPEAKER (50s):** "The register records that a mother didn't go. It has no field for why. So the
district can see a number, and can never act on it."
**Rules:** no mortality or death figures anywhere — the repository contains none to cite. Do not
illustrate the paper panel with a photograph. Do not tick the ☒ in red.

---

### 3.3 SLIDE 3 — Who it is for · 1:20–2:00

**Job:** one permission model, three people, and the fact that the weakest user still cannot write
clinical data.

**Layout:** headline, then a real 3-row table (not three cards — the row alignment is the point).
Column widths: user 3 | what they get 6 | enforced by 3. Row height 150px, 1px `rule` between rows,
no zebra striping, `command` fill on the header row only.

**Headline:** `Three users. One record. One permission model.`

| User | What they get | Enforced by |
|---|---|---|
| **CHPS nurse / frontline worker** | household register, roll call, vitals, IMCI assessment, verdict with weight-based doses, referral, follow-up desk, ranked visit route | 12 FHW permissions |
| **Mother / caregiver** | a danger-sign check **in her language, read aloud**, a care plan, food and milestone support, "ask for help" | 5 caregiver permissions — **no clinical write** |
| **Supervisor / district** | consent, access and review queues, read audit, barrier patterns | append-only ledger |

- Table text Manrope 19 Regular `ice`; user column SemiBold. The bold phrases inside cells stay
  bold and take `electric`.
- Below the table, one full-width `deep` panel with a 3px `electric` left rule, Manrope 21:
  > A family can register itself before a worker ever arrives — and still cannot write a single
  > clinical value. The rule lives in the repository, not in the interface.

**Proof line:** `PROVEN BY · Permission._fhw / ._caregiver + care_repository.dart`
**Build:** none (static).
**SPEAKER (40s):** "Three users, one record, one permission model — and the caregiver's permission
physically cannot write a clinical value."
**Rules:** do not add a fourth "researcher" row; it is not in the facts document. Do not photograph
any person on this slide.

---

### 3.4 SLIDE 4 — How care happens · 2:00–3:00

**Job:** show a working day, not an architecture diagram.

**Layout:** headline, then the worker rail across the top half (6 nodes), then a full-width
caregiver band in the bottom half. The two bands must be visually different weights — the rail is
light and linear, the band is a panel — because they are two different users.

**Headline:** `What actually happens on a Tuesday`

**Worker rail** — 6 nodes on a 2px line using the permitted gradient (`#2E73FF → #1B56DB →
#0D2E73`), left to right. Each node: 44px circle, `midnight` fill, 2px `electric` outline, Sora
Bold number 22; title Manrope ExtraBold 22 `ice`; one-line body Manrope 17 `ink-dim`.

| # | Title | Body (one line, 17px) |
|---|---|---|
| 1 | Roll call | absent is **recorded absent**, never skipped |
| 2 | Measure | a **plausibility screen** runs before any dose is calculated |
| 3 | Assess | 16 guideline engines → classification + the reason for it |
| 4 | Refer | a referral with 8 states behind it |
| 5 | Follow up | **one atomic write** — answer, status, barrier, next visit |
| 6 | Route | the day plan ranks the zone, so a chase visit rides a walk already being made |

**Caregiver band** — full-width `deep` panel, tag `CAREGIVER LOOP · NO NETWORK, NO READING
REQUIRED`, then one line and one chip row:

> A danger-sign check in Dagbani, Twi, Hausa or English — 18 questions, 5 guidance topics,
> **41 spoken clips per language** — every answer read back before it counts.

Chips (Manrope 18, `command` fill, `ice` text — these are neutral, so no amber):
`ASK FOR HELP → REACHES THE DISTRICT` · `ANSWER PULLED BACK HOME` · `WORKS AT 320 px AND 200% TEXT`

**Screenshot (optional, recommended):** place `result-ui-urgent.png` (see section 5) at the right
end of the rail, 460px wide, straight, no device mockup, no shadow, no drop tilt. If the capture is
not available, take the image out — the slide is complete without it.

**Proof line:** `PROVEN BY · VisitDao.openVisitsFor · measurement_safety_engine.dart · assets/audio/`
**Build:** nodes 1–6 fade in left to right on one click (all six together, not six clicks — there
is no time).
**SPEAKER (60s):** "The nurse never has to open a document to find out what to do — and the mother
never has to read to be told what to do."
**Rules:** do not call node 3 "AI assessment". Do not add "voice input" anywhere on this slide —
that claim is handled on slide 8 with its limit attached.

---

### 3.5 SLIDE 5 — The referral · 3:00–3:50 · **give this slide the most design attention**

**Job:** the single most clinically important claim in the deck — arrival is not treatment.

**Layout:** headline; the state track as the hero, centred, occupying the middle third; below it a
three-column band of rules; at the bottom, the display-size closing line.

**Headline:** `A referral is a state machine, not a piece of paper`

**State track** — the four happy-path states as 220 × 88px panels on a line, `deep` fill, Manrope
ExtraBold 24 `ice`, arrow connectors in `electric` 2px:

`ISSUED` → `TRAVELLING` → `ARRIVED` → `TREATED`

Under the line, offset beneath `ARRIVED`, four exception states as smaller ghost panels (1px
`rule` outline, transparent fill, Manrope 18 `ink-dim`):
`DID NOT ATTEND` · `REFUSED` · `CANCELLED` · `DIED`

**The key visual event:** a short **stop bar** (2px `amber`, 8px tall, 120px wide) drawn across the
gap between `ARRIVED` and `TREATED`, with one caption under it in Manrope SemiBold 20 `amber`:
> **ARRIVED IS NOT TREATED** — a child seen and sent home stays on the chase list.

That caption and bar are the argument of the slide. They must be the most prominent thing after the
headline. Do not render them in red.

**Three rules (columns, Manrope 18):**
1. **One atomic write.** Answer, status, barrier, next visit, chained referral — all of them or
   none. A second tap cannot invent a second answer.
2. **Verification is bounded.** A facility may confirm *arrived, treated, died*. It can never
   record a family's refusal.
3. **Silence escalates.** Two unanswered visits become a trace, not a bad afternoon.

**Barrier-evidence strip (full width, `command` panel):** four tallies in Sora Bold 40 `electric`
with 16px `ink-dim` labels, then one sentence.
`DISTINCT HOUSEHOLDS, NOT REPORTS` · `30-DAY WINDOW` · `3 HOUSEHOLDS = A PATTERN` ·
`OWNER: household / community / facility / system / season`
> Six households reporting the same closed facility become one line item the district can fix.

**Closing display line** — Sora ExtraBold 60, `ice`, left-aligned, full width, 40px above the
bottom chrome:
> The loop closes when the child is treated — and when we know why the last one wasn't.

**Proof line:** `PROVEN BY · ReferralStatus (8 states) · CareRepository.recordFollowUp · barrier_evidence.dart`
**Build:** one click — the stop bar and its caption fade in after the track is on screen.
**SPEAKER (50s):** "The loop does not close when the child arrives. It closes when the child is
treated — and when we know why the last one wasn't."
**Rules:** the four happy states and four exceptions must be visually unequal (solid vs ghost) —
that difference is the honesty. Do not use a circular "closed loop" diagram; the process is not a
circle and the metaphor would cost us the arrival distinction.

---

### 3.6 SLIDE 6 — Data protection: security · 3:50–4:40

**Job:** replace "we take security seriously" with a countable register.

**Layout:** headline; left third is the tally; right two-thirds is three stacked control groups;
bottom band is the app's own posture card mock with the Limit Chip.

**Headline:** `Bars, not promises`

**Tally block (left, columns 1–4)** — three rows, number in Sora ExtraBold 96:

| | number | label | colour |
|---|---|---|---|
| 1 | **15** | controls in place | `green #2E7D4F` |
| 2 | **8** | in place **with a stated limit** | `amber #ED9B00` |
| 3 | **4** | **not this software's to implement** | `ink-dim` |

Above them, Manrope ExtraBold 22 `ice`: `27 named controls in the governance register`.
Below them, Manrope 17 `ink-dim`: `20 of the 27 name the test that proves them · 14 state their own
boundary.` — that line covers all three rows; do **not** attach "tested" to the 15 alone, because
the register does not claim that.
Use no bar chart. Three numbers, stacked, is stronger and needs no axis.

**Control groups (right, columns 5–12)** — three `deep` panels stacked, each with a Consolas 14
`electric` tag and two lines of Manrope 19:

| Tag | Lines |
|---|---|
| `AT REST` | Whole database is a **SQLCipher** file; the 256-bit key is read back from secure storage **before** use — an install **refuses to encrypt with a key it cannot retrieve**. / Old installs migrate by **copy-verify-swap**: every table counted on both sides; a mismatch leaves the original intact. `PRAGMA secure_delete = ON` at every open. |
| `IN TRANSIT` | Four declared scopes per table — device only · device + district · **pushed but never stored locally** · district only. The credential verifier lives in the third. / A sync whitelist decides what may leave the handset; minimisation happens at the edge. **No analytics. No telemetry.** |
| `ON ACCESS` | Permissions enforced in the repository. Sensitive-record class, break-glass with a stated reason, inactivity lock, screen-capture block. / Transport policy is enforced **inside the app**, in the one door every request passes through — so it holds on web and desktop where no platform TLS setting exists. |

Key phrases in `electric`, never in bold-only-grey.

**Bottom band** — a mock of the app's own security posture card: `command` panel, Manrope SemiBold
20 `ice`, containing the Limit Chip `WEB / DESKTOP: NOT ENCRYPTED AT REST` and one line:
> The app prints its own weakness on screen rather than implying protection it does not have.

**Proof line:** `PROVEN BY · lib/domain/governance.dart · database_conversion.dart · transport_policy.dart`
**Build:** none.
**SPEAKER (50s):** "Where we are strong, we can show you the test. Where we are limited, the screen
says so — that is why you can trust the rest."
**Rules:** 15 + 8 + 4 = 27 must be visibly the same total as the header line. If any panel is
crowded, delete a clause — do not drop the type below 18px. No padlock icons, no shield icons.

---

### 3.7 SLIDE 7 — Data protection: compliance · 4:40–5:25

**Job:** prove the register is alive in CI, and name the things we do not own.

**Layout:** headline; top band the three accountability tables; middle band the CI reconciliation
figure; bottom band the framework mapping. Three horizontal bands, one idea each.

**Headline:** `Proof, not policy`

**Band 1 — three `deep` panels, equal width:**

| Tag | Body |
|---|---|
| `CONSENT` | Stored as **history**, never as one overwritten flag. |
| `WHO READ WHAT` | An **access ledger** — tamper-evident, chain-anchored, audited on the district side. |
| `DELETION` | Both tables are append-only and **never cascade from a patient row**: deleting a person must not delete the evidence that made the deletion lawful. |

Add under band 1, Manrope 18 `ink-dim`: `Right to erase and right of access carry a statutory
deadline.` — no date, no invented SLA number.

**Band 2 — the reconciliation figure** (drawn with rectangles and arrows, no icons):

```
GovernanceRegister  ─┐
local schema        ─┼─►  CI reconciles  ─►  BUILD FAILS
server/schema.sql   ─┤                            ▲
tables.js (whitelist)┤                            │
pull.js (pull list) ─┘        add a table without declaring it
```

Caption, Manrope 17 `ink-dim`: `The register is code, not a PDF. Governance drift breaks the
build, so it cannot rot quietly.`
The words `BUILD FAILS` in Sora Bold 24 `electric` — it is the strongest claim on the slide.

**Band 3 — frameworks mapped, not name-dropped.** Three cells, Consolas 14 tag above Manrope 19
body, separated by 1px `rule` verticals:

| | |
|---|---|
| `GHANA DPA 843` | s.26 security of processed data · s.27 responsibility |
| `HIPAA` | 45 CFR 164.312 — encryption at rest |
| `OWASP MASVS` | STORAGE · PLATFORM · CRYPTO |

Beside them, the Limit Chip `4 CONTROLS ARE NOT OURS TO IMPLEMENT — OWNER NAMED`, plus one line in
Manrope 19 `ice`: `Retention enforcement · controller registration · breach notification · impact
assessment — recorded with the district as owner, not dropped.`

**Proof line:** `PROVEN BY · GovernanceRegister · consent_events · access_ledger · server_read_log`
**Build:** band 2's `BUILD FAILS` fades in on one click.
**SPEAKER (45s):** "We do not claim compliance. We claim that every control is either tested,
bounded, or assigned to the district — and the build fails if we lose track of one."
**Rules:** never write "fully compliant with Act 843" or "GDPR-ready". Mapping is not
certification. No certification badges, no seals, no checkmarks.

---

### 3.8 SLIDE 8 — AI, recommendation, language · 5:25–6:00

**Job:** the honesty exhibit. It has to be legible from the back of the room at a glance and
survive a close read by an ML judge.

**Layout:** headline; the three-row claim/limit table as the hero (full width); two honest-number
cards beneath it, side by side; one closing line. Dense — this is the only slide allowed four
bands, and only because the speaker spends 35 seconds here.

**Headline:** `Guidelines decide. Models support. The gate is in the code.`

**Table** — header row `command` fill with the permitted gradient (`#0C2350 → #123E93`), column
widths 2 | 5 | 5, row height 110px, body Manrope 19.

| | What it is | The honest number |
|---|---|---|
| **4 models** | on-device int8 TFLite, **under 6 KB each**, `clinical_use_allowed: false` enforced where output enters the app | Sepsis: **real cohort** — Uganda neonatal EMR, n = 964 · **AUC 0.90**, sens 0.778 / spec 0.933, Brier 0.411 · Pre-eclampsia: **AUC 0.7365** on a held-out public set, outside its own simulator · the other two simulator-trained, shown as such |
| **Recommendation** | every finding classified — clinical · preventive · data-quality · experimental — then ranked with its reason attached | A missed vaccine can no longer make a **well child urgent** |
| **Language** | offline MarianMT translation, Piper speech synthesis, on-device ASR | Twi speech **CER 0.162 — allowed**. Dagbani **0.420 — the microphone stays off** |

**Two honest-number cards** (`deep` panels, 3px `amber` left rule, Sora Bold 36 `ice` figure,
Manrope 18 `ink-dim` caption):

| Card | Figure | Caption |
|---|---|---|
| A | `AUC 0.511` | Out of its training window — adult ICU data — the sepsis model performs at **chance**, and the report says so. That refusal is the behaviour we want. |
| B | `0.420 CER` | Dagbani speech recognition is **disabled in the app**, not demoed. Shown here so nobody has to ask. |

Place the `DAGBANI SPEECH INPUT OFF · CER 0.420` Limit Chip on card B's header line, not floating.

**Closing line** — full width, `midnight` background, no panel, Sora ExtraBold 44 `ice`:
> Four models. One real cohort. **Zero clinical authority.**

`Zero clinical authority` in `electric`. This is the last thing on screen when the talk ends.

**Proof line:** `PROVEN BY · assets/models/*_metrics.json · research_contracts.json · asr_contract.dart`
**Build:** the closing line fades in on the last sentence.
**SPEAKER (35s):** "We can show you a model that admits it is out of its depth, and a language
feature that switches itself off when it cannot spell the answer. That is the whole design."
**Rules:** do not say or write *trained on Ghanaian patients* (the real cohort is Ugandan),
*clinically validated*, *diagnosis*, or *confidence score*. Every figure must appear character-for-
character as it does in `docs/MODEL_CARD.md` — a judge may ask to see it. If the table will not
fit, drop the pre-eclampsia external number before dropping the closing line.

---

## 4. Speaker notes pane — fill it before export

Paste the matching `SPEAKER` line and the `DON'T SAY` list from `SEQUENCE.md` into each slide's
notes. The notes are the only place the evidence file paths appear in long form. Nothing from
`EVIDENCE` may be moved onto the slide face — it is answered only if asked.

Three answers to keep in the notes of slide 8 (from `SEQUENCE.md`):

1. *Where does the AI change a decision?* — "It doesn't. 16 guideline engines decide; every model
   carries `clinical_use_allowed: false`, enforced where its output enters the runtime."
2. *Is this just rules with a model bolted on?* — "Rules are the safety layer. The models are
   research artefacts we refuse to overstate — three are simulator-trained and we show you which."
3. *What is not finished?* — "No live district server, ASR packs not shipped, Dagbani voice
   awaiting native sign-off, three of four models awaiting a real Ghanaian cohort. We say all four
   before you ask."

---

## 5. Screenshots the designer must request (do not reuse the old ones)

`pitch/day1/shot_*.png` were captured **before** the results page was redesigned. They are stale.
Use them for reference only; request fresh captures for any app imagery.

The current results UI renders itself to PNG through the widget-test harness:

```
flutter test test/widgets/result_page_simplification_test.dart
```

which writes, into `.dart_tool/`:

| File | Shows | Use on |
|---|---|---|
| `result-ui-urgent.png` | danger signs present, priority actions | slide 4 (optional) |
| `result-ui-routine.png` | well child with prevention outstanding | slide 5 (optional, if a real record beats the diagram) |
| `result-ui-night.png` | the result screen with observation completeness at 100% | slide 3 (optional) |
| `result-ui-evidence.png` | the experimental model card, labelled | slide 8 — **preferred over any chart** |

Rules for app imagery: straight-on, no device frame, no mockup, no shadow, no reflection; 460–520px
wide; cropped to the content with 8px of `midnight` breathing room so it sits on the slide
background; never annotated with drawn arrows — say it in the caption text instead.

---

## 6. Print and projection checks

Assume a projector in a hall in Tamale: low contrast, no calibration, viewers 6 metres back.

- Body text never below 18px on a 1920 canvas. Nothing under 14px except the proof line and chrome.
- Test every slide in greyscale: the amber Limit Chips must still read as *different* from `ice`
  text. (That is why red is unused and why colour is never the only signal — every chip also has a
  word.)
- Check contrast: `ink-dim #A8C2E8` on `midnight #081938` and `ice #E8F1FF` on `deep #0D285F` both
  clear 4.5:1. Do not darken `ink-dim` further, and do not put `ice` on `command`.
- No text in the outer 60px of any edge; projectors crop.
- Keep one full-width empty band per slide (slides 1 and 5 especially). Density reads as distrust.

---

## 7. What to hand back

1. `CareBridge_AI_Deck8.pptx` — 8 slides, 16:9, fonts embedded, notes pane filled (section 4).
2. `CareBridge_AI_Deck8.pdf` — same 8 slides, for the platform upload.
3. The **Proof Line** and **Limit Chip** as reusable components with the four chip states, so a
   Day-2 deck inherits them rather than reinventing them.
4. Any slide where a copy string was cut for fit, listed with what was cut — so nothing clinical
   quietly disappears.

**Escalate rather than improvise if:** a headline seems to need a metric we do not have (the answer
is to lose the headline, not to invent the metric) · the state track on slide 5 reads as a closed
circle · slide 8's table tempts anyone to drop the `clinical_use_allowed: false` phrase or the Dagbani
limit. Those three are the deck's credibility, and they are the layout's job to protect.
