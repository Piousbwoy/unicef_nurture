# CareBridge AI — Day 1 Presentation: Design Brief & Verbatim Script

**Target:** the Day 1 daily bounty, **Most Creative Approach** ("the most innovative conceptual approach").
**Slot:** 10 teams in 60 minutes → **6:00 hard stop**. The script below is timed to exactly 6:00; section 4 is how the speaker buys margin if the room runs late.
**Venue:** HOPin Academy, Tamale. Mixed panel: GHS/UNICEF health professionals, AI/ML engineers, software engineers, government officials.
**Deliverable from you:** 7 slides, 16:9, built exactly to the copy and states below.
**Working wireframe already exists:** `pitch/day1/slides.md` (Slidev, running at localhost:3030). Treat it as the layout wireframe and this document as the source of truth for copy, concept and states. Where they disagree, this document wins.
**Companion document:** `pitch/day1/AI_PROVENANCE_QA.md` — what the models were trained on, their licences, and the exact sentences you may say about accuracy. The copy below already reflects it.

---

## 1. The concept — read this first, it governs every decision

Every CHPS register in Ghana ends at the same place. A child is referred; the child does not come back; the worker ticks **DID NOT ATTEND**; and the page runs out of columns. Nobody is ever asked what happened next, because there is nowhere to write it.

**So the entire deck is one register row, and each slide adds the column that was never there.**

- Slide 1 shows the row exactly as paper leaves it: four cells, the fourth struck through, then an empty dashed cell labelled *no further column exists*.
- Slides 3 and 4 **fill cells in that same row** — barriers, who was home, protocol, plan, arrived, care received, condition. The row is not a metaphor the speaker explains; it is a persistent strip at the top of every slide that visibly completes itself as the talk progresses.
- Slide 4 flips the struck cell: **DID NOT ATTEND** becomes **ATTENDED · 21 OCT**.
- Slide 7 ends on the completed row plus **one empty dashed cell labelled "NEXT COLUMN — YOURS"**, and the ask (a pilot zone) is written as the content of that cell. The closing ask is literally the next column of the register.

Why this wins *Most Creative Approach* specifically: the other nine teams will present features. This deck's **layout is the argument** — the missing column is the problem, the filling of it is the product, and the ask is the next column. A judge who remembers one visual from the day will remember a paper row completing itself.

### The three moments you must not flatten

1. **The completing register strip.** It appears on all seven slides, in the same position, same width, same type. It gains cells; it never moves or restyles. Consistency is the trick.
2. **The eight seconds of Dagbani (slide 6).** The speaker stops talking and the phone plays recorded Dagbani guidance out loud. The slide must be quiet enough to hold silence: no dense text, one chip row, generous space.
3. **The paper/app split (slide 4).** Left half is the app's own warm paper colour `#FBF8F1` with ink `#0A192F`; right half is the app's sapphire `#0D285F`. The palette *is* the comparison — old world, new world. Do not make both sides the same background.

---

## 2. Design system

**Canvas:** 1920×1080 (or 1280×720; keep ratios). Dark deck.

**Palette — taken from the shipped app, do not invent new colours:**

| Token | Hex | Use |
|---|---|---|
| midnight | `#081938` | slide background |
| deep | `#0D285F` | panels, the app-side of comparisons |
| command | `#0B2354` | secondary panels |
| electric | `#2970FF` | the single accent: numbers, the completing cells, the ask |
| ice | `#E8F1FF` | primary text on dark |
| ink-dim | `#A8C2E8` | secondary text |
| paper | `#FBF8F1` | the register strip and the paper-side panel only |
| paper-ink | `#0A192F` | text on paper |

One accent colour for the whole deck. No gradients. No emoji. No icon packs standing in for meaning.

**Type:** a single humanist sans (system-ui / Inter / Segoe UI — the venue may be offline, so **no web-font dependency**). Scale: display 72–84, headline 44–48, body 19–21, caption 14–15, register strip 13–15 uppercase tabular.

**The register strip (persistent element, all slides):**
- Full width, top of the slide, 64–72px tall, paper background, ink text, 4px radius, subtle drop shadow.
- Header line inside it, 11px letterspaced: `CHPS SUB-DISTRIBUTION REGISTER · SAVELEGU ZONE B`.
- Cell row in uppercase tabular figures. Cells that are not yet filled are **dashed-outline empty cells** in `#9AA3B2`.
- Struck cell: `DID NOT ATTEND` with a 2px strike in `#CBD5E1`.
- Filled-on-this-slide cells get a 2px `#2970FF` underline and a 300ms fade-in if the tool allows; otherwise static is fine. **Never animate the strip on slide 1** — it must read as dead paper.

**Grid:** 76px side margins, 64px top, 56px bottom. Content sits below the strip. Nothing touches the edges.

**Forbidden:** stock photography of African children or clinics (dignity, and we have none licensed); fake metrics of any kind; the words "blockchain", "revolutionary", "game-changing", "100% secure"; a logo wall; a thank-you slide with contact icons.

---

## 3. Slide-by-slide: layout, exact copy, strip state, speaker script

Timing marks are cumulative. The speaker script is **verbatim** — do not paraphrase on stage.

---

### SLIDE 1 — The row as paper leaves it · 0:00–0:40

**Strip state:** `AKOSIA Y.` · `9 MONTHS` · `REFERRAL — 14 OCT` · `~~DID NOT ATTEND~~` · `[dashed empty cell: no further column exists]`

**Layout:** strip at top. Below it, left-aligned, a three-line display headline occupying the upper-middle. Bottom-left: product name in 26px bold, then one line of 19px secondary text. Bottom edge: 13px letterspaced event line.

**On-slide copy:**

> We built the part
> **that comes after**
> the tick box.

> CareBridge AI — offline-first decision support for CHPS workers, and a mother's answer in her own language.

> UNICEF STARTUP LAB · AI FOR NURTURING CARE · HOPIN ACADEMY, TAMALE · 21 OCTOBER 2026

**Speaker (40s):**
> "A child in Savelugu was referred on the fourteenth of October. The register recorded that she did not attend." *(pause, gesture at the struck cell)* "There is no column for what happened next. So nobody was ever asked. Everything we built is the part that comes after the tick box."

---

### SLIDE 2 — The two numbers · 0:40–1:15

**Strip state:** unchanged, at 40% opacity (it is context now, not the subject).

**Layout:** headline top-left. Two giant numbers side by side, separated by a 1px vertical rule in `#1C3A72`. Under each: one line of 21px ice text, then one line of 16px dim text. Bottom: a full-width deep panel with one sentence. Tiny source line at the very bottom.

**On-slide copy:**

Headline: **Survival is decided far from the clinic**

Left number: **234** — "maternal deaths per 100,000 live births, national" / "SDG 3.1 target: under 70 by 2030"
Right number: **~30%** — "of children stunted in the Northern and North East regions" / "the cause is rarely clinical alone — road, money, the decision-maker"

Panel: "Frontline workers are hindered by fragmented records, supply gaps, transport barriers and low connectivity. Those four things are what this app is shaped around — not a dashboard bolted onto a spreadsheet."

Source: "Both figures from the hackathon brief, UNICEF Ghana / MEST Africa."

**Speaker (35s):**
> "Two numbers from your own brief. Two hundred and thirty-four maternal deaths per hundred thousand births, against an SDG target of seventy. Nearly a third of children stunted in the regions we are standing in. We did not set out to build an AI tool. We set out to fix the four things the brief names."

---

### SLIDE 3 — The visit rail · 1:15–2:05

**Strip state:** four new cells fill in, left to right, as the speaker names them: `BARRIERS: TRANSPORT` · `PRESENT: 2 OF 4` · `PROTOCOL: IMCI CHILD` · `PLAN: RUTF + REFER`.

**Layout:** headline. Then a horizontal rail of four numbered nodes on a 2px line that runs behind the node circles (royal→electric). Each node: 42px circle with number, 21px bold title, 16px dim body. Bottom: a full-width deep panel containing node 5 as a circle-plus-sentence.

**On-slide copy:**

Headline: **One encounter, in the order care actually happens**

1. **What's getting in the way?** — "The visit opens on barriers: transport money, a flooded road, the elder who must agree. Not on a form."
2. **Who is here today?** — "Roll call. The child not brought is the child never measured, so absence is recorded, not skipped."
3. **Right protocol, by age** — "Re-derived as the child grows: a six-week-old moves off the newborn pathway onto IMCI on its own."
4. **A plan, not a paragraph** — "Feeding from local seasonal foods, the vaccines actually due, and a referral that names the facility for the job."

Panel 5: "Every step is saved **offline, in one write** — the record and the intent to sync it, or neither. A dead battery cannot leave a half-finished child."

**Speaker (50s):**
> "One visit, in the order care actually happens. It opens with what is getting in the way — because a referral note is not care, and transport money can only be solved while the family is still in front of her. Then who is here today, because the child who was not brought is the one who never gets measured. Then the right protocol for each age, then a plan built from foods this market actually sells. And all of it is saved offline in one write — the record and the intent to sync it, or neither."

---

### SLIDE 4 — Did she arrive? · 2:05–3:05  *(the money slide — give it the most design attention)*

**Strip state:** three more cells fill: `ARRIVED: YES · 21 OCT` · `CARE: SEEN + TREATED` · `CONDITION: BETTER`. **And the struck cell flips:** the strike lifts and it reads `ATTENDED · 21 OCT` in electric. This flip is the single most important visual event in the deck.

**Layout:** headline. Then a two-panel split, equal height. Left panel on **paper** with a 13px letterspaced tag; three lines styled like register entries with dashed rules and two checkbox glyphs; an italic grey line at the bottom. Right panel on **deep** with an electric tag and four rungs, each a 9px electric dot plus 19px ice text. Below both, a full-width punch line with a 3px electric left rule.

**On-slide copy:**

Headline: **Did she arrive? And then what?**

Left (paper): tag `TODAY'S PAPER LOOP`
- "Referral issued"
- "Attended ☐  Not attended ☒"
- italic: "Nothing after this. No question is ever asked of the facility, and none of the family."

Right (deep): tag `CAREBRIDGE CLOSES IT`
- "**Arrival confirmed** at the facility, by name and time"
- "Follow-up contact: **what care did she actually get**"
- "Condition recorded — better, same, worse, died, not seen"
- "**Chained escalation** when the answer is 'sent home untreated'"

Punch: "And six households reporting the same closed facility becomes **one line item the district can fix** — not six excuses in six registers."

**Speaker (60s):**
> "This is the column that was never there. Today the loop closes at attended or not attended, and nothing is ever asked of the facility or of the family. CareBridge confirms arrival by name and time. Then it asks the question nobody asks: what care did she actually get? Condition is recorded. And if the answer is 'sent home untreated', the referral chains upward on its own." *(point at the strip)* "Watch the row. The strike comes off. She attended on the twenty-first — because somebody was required to ask."

---

### SLIDE 5 — The AI, stated honestly · 3:05–4:00

**Strip state:** unchanged from slide 4, at 40% opacity.

**Layout:** headline. Two equal deep panels side by side, each with an electric 14px letterspaced tag, a five/four-item list at 17.5px, and a footnote separated by a 1px rule. Below, a full-width confession panel: deep background, 3px electric left rule, 20px text.

**On-slide copy:**

Headline: **The AI, stated honestly**

Panel A tag: `DETERMINISTIC · AUDITABLE`
- Ghana IMCI and CHPS danger-sign classification
- WHO growth-standard z-scores and MUAC cut-offs
- Immunisation schedule and catch-up logic
- Nutrient coverage built from local seasonal foods
- Pre-eclampsia and postnatal sign clusters
- footnote: "Every recommendation prints the value, the cut-off it crossed, and the guideline it came from — so a worker can defend the decision."

Panel B tag: `LEARNED · ON THE HANDSET`
- ONNX risk models for the newborn and child streams
- A shown confidence band and a *what would change this* counterfactual
- On-device speech synthesis in three Ghanaian languages
- Neural translation — no cloud call, no cost per utterance
- footnote: "The rule engine stays the referee: a model may raise concern, it cannot overrule a protocol danger sign."

Confession: "We have not validated these models for a Ghanaian facility, and we will not quote an accuracy we do not have. The recalibration pathway signed with Kintampo HRC and Navrongo HDSS exists to change that — de-identified, salted for linkage, and exported by a human hand, never silently."

**Speaker (55s):**
> "For the engineers: two columns, and the line between them is the honest one. On the left, deterministic protocol logic — IMCI danger signs, WHO z-scores, MUAC cut-offs — and every recommendation prints the value, the cut-off and the guideline, so a worker can defend it. On the right, learned models that run on the handset: risk scores with a shown confidence band, on-device speech, on-device translation. The rules stay the referee; a model can raise concern, it cannot overrule a danger sign. And we have not validated these models for a Ghanaian facility. We will not quote an accuracy we do not have. The signed recalibration pathway with Kintampo and Navrongo exists precisely to earn one."

---

### SLIDE 6 — Voice and reach · 4:00–5:00  *(the live-audio slide: keep it quiet)*

**Strip state:** unchanged, 40% opacity, plus one new cell: `LANGUAGE: DAG`.

**Layout:** headline. A row of three equal chips (command background): language name in 30px electric bold, caption in 15.5px dim. Below, one full-width deep panel with the safety rule, key phrase in electric. Below that, two equal panels. **Leave at least 120px of empty space at the bottom of this slide** — it is where the silence happens.

**On-slide copy:**

Headline: **It has to work where the work is**

Chips: **Dagbani** — "41 on-device clips generated with Meta MMS — machine voice, wording still a draft awaiting a native-speaker sign-off" · **Hausa** — "same engine, on the device, with no network round trip" · **Twi** — "on-device synthesis, plus written guidance in all three"

Safety panel: "And a rule we will not trade for a demo: when a mother asks for Dagbani, the app **refuses to read English aloud** and let her believe it was her language. Guidance understood in the wrong tongue is a safety problem, not a fallback."

Panel A tag `NO MAST REQUIRED`: "Records, assessments and referrals are written offline and queued. A delta pull brings back what changed on another handset — so the answer a family asked for reaches the phone it came from."
Panel B tag `LEGIBLE IN REAL HANDS`: "Tested at 320 pixels and 200% text. Colour never carries meaning alone. Reduced motion honoured. Guidance, never a diagnosis."

**Speaker (60s, including 8s of silence):**
> "We are in Tamale, so let us do this in the language of Tamale." *(pick up the phone, tap speak on a Dagbani guidance card, put the phone down or hold it toward the panel — say nothing for eight seconds)* "That is a machine voice running on the handset with no network — and the wording behind it is a draft our first ask fixes: a native speaker to sign it off. And the rule behind it: if a mother asks for Dagbani, this app will not read English aloud and let her believe it was her language. Everything else follows the same discipline — written offline, queued, and legible on a 320-pixel phone at 200% text."

---

### SLIDE 7 — Trust, and the next column · 5:00–6:00

**Strip state:** fully complete, at 100% opacity, plus one final **dashed empty cell** labelled `NEXT COLUMN — YOURS`. This is the closing image.

**Layout:** headline. A 2×2 grid of four command panels, 17.5px, key phrase bold ice. Below, a full-width deep panel: 13px letterspaced label, then the ask in 30px electric bold. The dashed cell in the strip and the ask panel must be visually linked (same electric, same dashed treatment on the panel's top edge if you want the rhyme).

**On-slide copy:**

Headline: **Trust is something you can check**

- "**Encrypted at rest** on the Android build — and where a platform cannot do it, the app says so on screen rather than implying it did."
- "**A mother can see who opened her record.** A hash-chained trail the worker who wrote it cannot quietly rewrite, with chain positions the district verifies independently."
- "**Protected records** — HIV status, adolescent health, violence — open outside the responsible worker's hand only with a **stated reason**, and that reason is shown to the family."
- "**Ghana's Data Protection Act 2012 (Act 843).** The processing register is generated from the database schema and fails the build when the two drift apart. 1,215 automated tests behind it."

Ask label: `WHAT WE ARE ASKING FOR`
Ask: "One CHPS zone, six months, and a language officer — so the Dagbani guidance is written by the people who speak it."

**Speaker (60s):**
> "Last slide, and it is the one for the district. The register is encrypted at rest on the Android build, and where a platform cannot do that the app says so on screen instead of implying it did. A mother can see who opened her record — a hash-chained trail her own health worker cannot quietly rewrite. Records carrying HIV status or a disclosure of violence open outside the responsible worker's hand only with a stated reason, and the family sees that reason. All of it is written against Act 843, and our processing register is generated from the schema and fails the build when they drift." *(gesture at the dashed cell)* "The row is complete. The next column is empty, and it is yours: one CHPS zone, six months, and a language officer. Thank you."

---

## 4. Stage directions and contingencies

- **Order of operations on stage:** deck on the projector from the laptop; phone in the left hand from slide 1, screen asleep; speaker notes on the laptop's second screen only.
- **The phone moment (slide 6):** unlock and open the caregiver guidance card *during slide 5*, so slide 6 needs one tap. Rehearse the tap twice. If the speaker or audio fails: say "recorded Dagbani, on the phone, no network — the room's speakers and I disagree" and move on. Do not apologise, do not retry on stage.
- **If you are running long:** cut slide 3 to the single sentence "barriers first, roll call, protocol by age, plan from local foods, saved offline in one write" (saves 30s). Never cut slide 4 and never cut the eight seconds of silence.
- **Wi-Fi is irrelevant:** the deck and the app are both offline-first. Do not mention connectivity as a risk; it is the product.
- **Q&A lines, memorised:**
  - *Accuracy numbers?* "We have held-out evaluation harnesses wired up and their outputs are not yet published. We would rather show you the harness than invent an AUC."
  - *Does it replace the nurse?* "No. It prints the guideline beside every recommendation so the worker can overrule it, and the override is recorded with a reason — the override is the training signal we want."
  - *Data Protection Commission registration?* "That is the controller's filing to make. Our register is written so they can file it."
  - *Why not DHIS2 integration now?* "Because a sync that silently loses a referral is worse than none. We would integrate at the point where the district owns the interface spec, not before."

## 5. Do-not-say list (the honesty contract)

No accuracy, sensitivity or AUC figures. No "AI diagnoses" — it is guidance and decision support. No claim of GHS, UNICEF or MEST endorsement beyond the event itself. No "100% secure" or "unhackable". No patient names or real photographs of identifiable people. No promise of a live sync to a server on stage — the demo is offline by design, and saying otherwise invites a failure we do not need. And specifically on language: never "recorded Dagbani" and never "verified Dagbani" — the bank is machine-generated over draft wording, and the repo's own provenance file says so.

## 6. What the designer should hand back

Seven slides in one file, plus: the register strip as a reusable component with its seven states (S1, S2-dim, S3, S4-flip, S5-dim, S6-dim+DAG, S7-complete+empty), and a PDF export for the platform upload. If anything in section 3 cannot be built in the tool, change the tool, not the strip.
