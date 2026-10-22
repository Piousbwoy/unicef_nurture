---
theme: seriph
title: CareBridge AI
info: |
  UNICEF StartUp Lab — AI for Nurturing Care. HOPin Academy, Tamale. Day 1.
  6 minutes. Team CareBridge AI.
class: dark
colorSchema: dark
canvasWidth: 1280
aspectRatio: 1.7777
transition: slide-left
duration: 6min
timer: session
# STAGE RULES FOR THE WHOLE DECK
# - Every number spoken is sourced. No accuracy figure is claimed anywhere.
# - The phone is in your hand. Slide 6 is the live Dagbani moment: do not narrate it, just play it.
# - 6 minutes for 10 teams. If you run long, cut slide 3 to one breath and keep slide 4 whole.
# MARKDOWN RULE FOR ANYONE EDITING THIS FILE
# - Never leave a blank line inside a <div> structure, and never indent a resumed
#   block by 4 spaces: Markdown ends the HTML block at the blank line and reads the
#   next line as a code block, so raw tags get printed on the slide.
---

<div class="stage cover">
  <div class="register">
    <div class="reg-head">CHPS SUB-DISTRIBUTION REGISTER · SAVELEGU ZONE B</div>
    <div class="reg-row"><span class="reg-cell">AKOSIA Y.</span><span class="reg-cell">9 MONTHS</span><span class="reg-cell">REFERRAL — 14 OCT</span><span class="reg-cell strike">DID NOT ATTEND</span></div>
    <div class="reg-foot">no further column exists</div>
  </div>
  <h1 class="ct">We built the part<br/><span class="accentword">that comes after</span><br/>the tick box.</h1>
  <div class="cover-meta">
    <div class="brand">CareBridge AI</div>
    <div class="sub">Offline-first decision support for CHPS workers — and a mother's answer, in her own language.</div>
  </div>
  <div class="foot-note">UNICEF StartUp Lab · AI for Nurturing Care · HOPin Academy, Tamale · 21 October 2026</div>
</div>

<!--
0:00 — 0:35. Say only this, then move:
"A child in Savelugu was referred on the fourteenth. The register recorded that she did not
attend. There is no column for what happened next, so nobody was ever asked. Everything we
built is the part that comes after the tick box."
-->

---
layout: none
---

<div class="stage">
  <div class="eyebrow">The problem the brief names</div>
  <h2 class="st">Survival is decided far from the clinic</h2>
  <div class="num-row">
    <div class="num-block">
      <div class="big">234</div>
      <div class="unit">maternal deaths per 100,000 live births — national</div>
      <div class="vs">SDG 3.1 target: under 70 by 2030</div>
    </div>
    <div class="rule"></div>
    <div class="num-block">
      <div class="big">~30%</div>
      <div class="unit">of children stunted in the Northern and North East regions</div>
      <div class="vs">the cause is rarely clinical alone — road, money, the decision-maker</div>
    </div>
  </div>
  <div class="callout">Frontline workers are hindered by fragmented records, supply gaps, transport barriers and low connectivity. Those four things are what this app is shaped around — not a dashboard bolted onto a spreadsheet.</div>
  <div class="src">Both figures from the hackathon brief (UNICEF Ghana / MEST Africa).</div>
</div>

<!--
0:35 — 1:15. Read the two numbers once. Attribute them out loud — they are the organisers' own
figures, which is why they are on the slide.
Then: "We did not set out to build an AI tool. We set out to fix the four things the brief names."
-->

---
layout: none
---

<div class="stage">
  <div class="eyebrow">The visit</div>
  <h2 class="st">One encounter, in the order care actually happens</h2>
  <div class="rail">
    <div class="node"><div class="k">1</div><div class="nt">What's getting in the way?</div><div class="ns">The visit opens on barriers — transport money, a flooded road, the elder who must agree. Not on a form.</div></div>
    <div class="node"><div class="k">2</div><div class="nt">Who is here today?</div><div class="ns">Roll call. The child not brought is the child never measured, so absence is recorded, not skipped.</div></div>
    <div class="node"><div class="k">3</div><div class="nt">Right protocol, by age</div><div class="ns">Re-derived as the child grows: a six-week-old moves off the newborn pathway onto IMCI on its own.</div></div>
    <div class="node"><div class="k">4</div><div class="nt">A plan, not a paragraph</div><div class="ns">Feeding from local seasonal foods, the vaccines actually due, and a referral that names the facility for the job.</div></div>
  </div>
  <div class="one-write"><span class="ow-n">5</span><span>Every step is saved <b>offline, in one write</b> — the record and the intent to sync it, or neither. A dead battery cannot leave a half-finished child.</span></div>
</div>

<!--
1:15 — 2:10. Land on node 1: "The barrier question comes first, while the family is still in
front of her. Two days later it is a statistic."
Node 5 is for the software judges — say "one write" and keep walking.
-->

---
layout: none
---

<div class="stage">
  <div class="eyebrow accentword">Thematic area 3 — the last mile</div>
  <h2 class="st">Did she arrive? And then what?</h2>
  <div class="duel">
    <div class="paper-side">
      <div class="paper-tag">Today's paper loop</div>
      <div class="paper-line">Referral issued</div>
      <div class="paper-line">Attended&ensp;<span class="box">☐</span>&ensp;Not attended&ensp;<span class="box">☒</span></div>
      <div class="paper-end">Nothing after this. No question is ever asked of the facility, and none of the family.</div>
    </div>
    <div class="app-side">
      <div class="app-tag">CareBridge closes it</div>
      <div class="rung"><span class="dot"></span><span><b>Arrival confirmed</b> at the facility, by name and time</span></div>
      <div class="rung"><span class="dot"></span><span>Follow-up contact: <b>what care did she actually get</b></span></div>
      <div class="rung"><span class="dot"></span><span>Condition recorded — better, same, worse, died, not seen</span></div>
      <div class="rung"><span class="dot"></span><span><b>Chained escalation</b> when the answer is "sent home untreated"</span></div>
    </div>
  </div>
  <div class="punch">And six households reporting the same closed facility becomes <b>one line item the district can fix</b> — not six excuses in six registers.</div>
</div>

<!--
2:10 — 3:10. This is the strongest minute of the deck. Spend it.
Point at the paper half: "The register is honest about what it does not know. It just never gets
to ask."
The last line is the one the GHS officials will remember.
-->

---
layout: none
---

<div class="stage">
  <div class="eyebrow">For the engineers in the room</div>
  <h2 class="st">The AI, stated honestly</h2>
  <div class="duel even">
    <div class="panel">
      <div class="panel-tag">Deterministic · auditable</div>
      <ul class="plist">
        <li>Ghana IMCI and CHPS danger-sign classification</li>
        <li>WHO growth-standard z-scores and MUAC cut-offs</li>
        <li>Immunisation schedule and catch-up logic</li>
        <li>Nutrient coverage built from local seasonal foods</li>
        <li>Pre-eclampsia and postnatal sign clusters</li>
      </ul>
      <div class="panel-note">Every recommendation prints the value, the cut-off it crossed, and the guideline it came from — so a worker can defend the decision.</div>
    </div>
    <div class="panel">
      <div class="panel-tag">Learned · on the handset</div>
      <ul class="plist">
        <li>ONNX risk models for the newborn and child streams</li>
        <li>A shown confidence band and a <i>what would change this</i> counterfactual</li>
        <li>On-device speech synthesis in three Ghanaian languages</li>
        <li>Neural translation — no cloud call, no cost per utterance</li>
      </ul>
      <div class="panel-note">The rule engine stays the referee: a model may raise concern, it cannot overrule a protocol danger sign.</div>
    </div>
  </div>
  <div class="confession">We have not validated these models for a Ghanaian facility, and we will not quote an accuracy we do not have. The recalibration pathway signed with Kintampo HRC and Navrongo HDSS exists to change that — de-identified, salted for linkage, and exported by a human hand, never silently.</div>
</div>

<!--
3:10 — 4:10. Do not soften the bottom paragraph. Delivered straight, it is the most technically
credible thing in the room, and it is the difference between a prototype and a deployment.
If challenged for numbers: "we have held-out evaluation harnesses wired up; their outputs are not
yet published. We would rather show you the harness than invent an AUC."
-->

---
layout: none
---

<div class="stage">
  <div class="eyebrow">Thematic areas 1 and 4 — reach and voice</div>
  <h2 class="st">It has to work where the work is</h2>
  <div class="lang-row">
    <div class="chip"><div class="lang">Dagbani</div><div class="cap">41 on-device clips generated with Meta MMS — machine voice, wording still a draft awaiting a native-speaker sign-off</div></div>
    <div class="chip"><div class="lang">Hausa</div><div class="cap">same engine, on the device, with no network round trip</div></div>
    <div class="chip"><div class="lang">Twi</div><div class="cap">on-device synthesis, plus written guidance in all three</div></div>
  </div>
  <div class="safety">And a rule we will not trade for a demo: when a mother asks for Dagbani, the app <b>refuses to read English aloud</b> and let her believe it was her language. Guidance understood in the wrong tongue is a safety problem, not a fallback.</div>
  <div class="duel even">
    <div class="panel">
      <div class="panel-tag">No mast required</div>
      <div class="panel-note plain">Records, assessments and referrals are written offline and queued. A delta pull brings back what changed on another handset — so the answer a family asked for reaches the phone it came from.</div>
    </div>
    <div class="panel">
      <div class="panel-tag">Legible in real hands</div>
      <div class="panel-note plain">Tested at 320 pixels and 200% text. Colour never carries meaning alone. Reduced motion honoured. Guidance, never a diagnosis.</div>
    </div>
  </div>
</div>

<!--
4:10 — 5:10. LIVE AUDIO HERE. Open the caregiver app on the phone, tap speak on a Dagbani guidance
card, and say nothing for eight seconds. Put the phone toward the panel — say nothing about
quality while you do it.
Then: "That is a machine voice on the handset with no network, and the wording behind it is a
draft our first ask fixes: a native speaker to sign it off."
The bank does play — you have heard it on the handset, so play it without hedging. But call it
what the repo calls it: machine-generated clips over draft wording. If the speaker dies in the
room, say "on-device Dagbani clips, no network" and move on without apologising.
-->

---
layout: none
---

<div class="stage">
  <div class="eyebrow">For the regulators and the district</div>
  <h2 class="st">Trust is something you can check</h2>
  <div class="trust-rail">
    <div class="t-item"><b>Encrypted at rest</b> on the Android build — and where a platform cannot do it, the app says so on screen rather than implying it did.</div>
    <div class="t-item"><b>A mother can see who opened her record.</b> A hash-chained trail the worker who wrote it cannot quietly rewrite, with chain positions the district verifies independently.</div>
    <div class="t-item"><b>Protected records</b> — HIV status, adolescent health, violence — open outside the responsible worker's hand only with a <b>stated reason</b>, and that reason is shown to the family.</div>
    <div class="t-item"><b>Ghana's Data Protection Act 2012 (Act 843).</b> The processing register is generated from the database schema and fails the build when the two drift apart. 1,215 automated tests behind it.</div>
  </div>
  <div class="ask-block">
    <div class="ask-label">What we are asking for</div>
    <div class="ask">One CHPS zone, six months, and a language officer — so the Dagbani guidance is written by the people who speak it.</div>
  </div>
</div>

<!--
5:10 — 6:00. Four lines, no tour. This slide exists to make CareBridge look deployable rather than
clever. Do not explain cryptography.
Deliver the ask, thank the panel, stop talking, and let the phone do the rest.
If asked about Data Protection Commission registration: "that is the controller's filing to make —
our register is written so they can file it."
-->
