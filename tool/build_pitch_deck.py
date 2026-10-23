"""Build the CareBridge AI 7-slide pitch deck (.pptx) from pitch_deck_facts.md.

Brand system mirrors the app: deep royal navy hero, triage red/amber/green
used ONLY for clinical meaning, brass as the secondary accent.
"""

from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR

# ------------------------------------------------------------- brand palette
NAVY = RGBColor(0x0B, 0x1F, 0x4B)       # primary deep
ROYAL = RGBColor(0x1B, 0x56, 0xDB)      # brand royal blue
BRASS = RGBColor(0xB8, 0x86, 0x2E)      # brass accent
INK = RGBColor(0x14, 0x1B, 0x2E)        # body ink
MUTED = RGBColor(0x5A, 0x64, 0x78)      # muted ink
CANVAS = RGBColor(0xF6, 0xF8, 0xFC)     # light canvas
WHITE = RGBColor(0xFF, 0xFF, 0xFF)
RED = RGBColor(0xC0, 0x39, 0x2B)        # triage red — clinical only
AMBER = RGBColor(0xD9, 0x7A, 0x16)      # triage amber
GREEN = RGBColor(0x1E, 0x8E, 0x5A)      # triage green

SW, SH = Inches(13.333), Inches(7.5)    # 16:9

prs = Presentation()
prs.slide_width = SW
prs.slide_height = SH
BLANK = prs.slide_layouts[6]


def add_slide():
    return prs.slides.add_slide(BLANK)


def rect(slide, x, y, w, h, fill, line=None):
    from pptx.enum.shapes import MSO_SHAPE
    shp = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, x, y, w, h)
    shp.fill.solid()
    shp.fill.fore_color.rgb = fill
    if line is None:
        shp.line.fill.background()
    else:
        shp.line.color.rgb = line
        shp.line.width = Pt(1)
    shp.shadow.inherit = False
    return shp


def textbox(slide, x, y, w, h):
    tb = slide.shapes.add_textbox(x, y, w, h)
    tf = tb.text_frame
    tf.word_wrap = True
    return tb, tf


def para(tf, text, size=18, color=INK, bold=False, first=False,
         align=PP_ALIGN.LEFT, space_after=6, font="Segoe UI"):
    p = tf.paragraphs[0] if first and not tf.paragraphs[0].runs else tf.add_paragraph()
    p.alignment = align
    p.space_after = Pt(space_after)
    r = p.add_run()
    r.text = text
    r.font.size = Pt(size)
    r.font.bold = bold
    r.font.color.rgb = color
    r.font.name = font
    return p


def bullets(tf, items, size=15, color=INK, gap=8, marker_color=ROYAL):
    for head, body in items:
        p = tf.add_paragraph()
        p.space_after = Pt(gap)
        r1 = p.add_run()
        r1.text = "▪ " + head
        r1.font.size = Pt(size)
        r1.font.bold = True
        r1.font.color.rgb = marker_color
        r1.font.name = "Segoe UI"
        if body:
            r2 = p.add_run()
            r2.text = "  —  " + body
            r2.font.size = Pt(size)
            r2.font.bold = False
            r2.font.color.rgb = color
            r2.font.name = "Segoe UI"


def notes(slide, text):
    slide.notes_slide.notes_text_frame.text = text


def kicker_title(slide, kicker, title, kicker_color=BRASS):
    tb, tf = textbox(slide, Inches(0.7), Inches(0.45), Inches(11.9), Inches(1.5))
    para(tf, kicker.upper(), size=13, color=kicker_color, bold=True, first=True, space_after=4)
    para(tf, title, size=30, color=NAVY, bold=True, space_after=0)
    rect(slide, Inches(0.7), Inches(1.55), Inches(1.2), Pt(4), kicker_color)


def footer(slide, page):
    tb, tf = textbox(slide, Inches(0.7), Inches(7.05), Inches(11.9), Inches(0.35))
    p = tf.paragraphs[0]
    r1 = p.add_run(); r1.text = "CareBridge AI"
    r1.font.size = Pt(10); r1.font.bold = True; r1.font.color.rgb = NAVY; r1.font.name = "Segoe UI"
    r2 = p.add_run(); r2.text = f"   ·   Offline-first CDSS for Ghana's CHPS   ·   {page} / 7"
    r2.font.size = Pt(10); r2.font.color.rgb = MUTED; r2.font.name = "Segoe UI"


# ============================================================== SLIDE 1 — TITLE
s = add_slide()
rect(s, 0, 0, SW, SH, NAVY)
rect(s, 0, 0, Inches(0.18), SH, BRASS)

tb, tf = textbox(s, Inches(1.0), Inches(1.35), Inches(11.3), Inches(3.2))
para(tf, "CAREBRIDGE AI", size=15, color=BRASS, bold=True, first=True, space_after=10)
para(tf, "The clinic that works\nwhen the network doesn't.", size=44, color=WHITE, bold=True, space_after=14)
para(tf, "Offline-first clinical decision support for Ghana's last-mile health system —\nWHO-guideline triage, on-device AI, and closed-loop referrals, in the family's own language.",
     size=17, color=RGBColor(0xC9, 0xD6, 0xF2), space_after=0)

stats = [
    ("4", "on-device AI risk models,\nzero connectivity needed"),
    ("0.90", "cross-validated AUC — sepsis model\ntrained on real patient records"),
    ("18", "table encrypted local DB —\nthe full clinic runs offline"),
    ("3", "layer offline language stack:\nspeech bank, neural MT, dictionary"),
]
x = Inches(1.0)
for num, label in stats:
    card = rect(s, x, Inches(4.9), Inches(2.72), Inches(1.55), RGBColor(0x13, 0x2C, 0x60))
    tb, tf = textbox(s, x + Inches(0.18), Inches(5.05), Inches(2.4), Inches(1.3))
    para(tf, num, size=34, color=BRASS, bold=True, first=True, space_after=2)
    para(tf, label, size=11, color=RGBColor(0xC9, 0xD6, 0xF2), space_after=0)
    x += Inches(2.92)

notes(s, "Open on the problem nobody in the room can argue with: the network. "
         "CareBridge AI is an offline-first clinical decision support system for Ghana's CHPS compounds. "
         "Everything you are about to see — the triage, the AI, the translation, the referral tracking — works with zero connectivity. "
         "Key numbers on screen: four int8 TFLite risk models running on-device; the neonatal sepsis model is cross-validated at AUC 0.90 "
         "on REAL patient records (Mbarara RRH EMR, n=964); an 18-table SQLite database is the source of truth; and a three-layer "
         "language stack carries advice into Twi, Hausa, and recorded local speech. Say the tagline once, slowly, then move on.")

# ====================================================== SLIDE 2 — PROBLEM & USERS
s = add_slide()
rect(s, 0, 0, SW, SH, CANVAS)
kicker_title(s, "The problem", "Danger is local. Help often isn't.", RED)

tb, tf = textbox(s, Inches(0.7), Inches(1.85), Inches(6.1), Inches(4.9))
para(tf, "Four compounding gaps at the CHPS compound", size=16, color=NAVY, bold=True, first=True, space_after=10)
bullets(tf, [
    ("No connectivity", "many CHPS zones have no reliable network — cloud-dependent tools simply stop working"),
    ("Paper referrals vanish", "a slip tells nobody whether the family travelled, arrived, or was ever treated"),
    ("Guideline overload", "IMCI danger signs, ANC schedules, EPI catch-up, WHO growth standards — too much to hold in memory under pressure"),
    ("Language & literacy", "English clinical advice never reaches many caregivers; counselling is lost"),
], size=14, gap=12, marker_color=RED)

tb, tf = textbox(s, Inches(7.1), Inches(1.85), Inches(5.55), Inches(4.9))
para(tf, "Built for three users", size=16, color=NAVY, bold=True, first=True, space_after=10)
for title, body in [
    ("Frontline Health Workers (CHOs, midwives)", "the primary user — full offline clinic: day plan, roll call, AI-assisted triage, referral desk"),
    ("Caregivers (mothers, fathers, kinship carers)", "linked to one household by family code — danger-sign home checks and voice playback in their language"),
    ("Ghana Health Service", "de-identified recalibration exports, auditable sync log, reporting with no PHI"),
]:
    p = tf.add_paragraph(); p.space_after = Pt(12)
    r = p.add_run(); r.text = title
    r.font.size = Pt(14); r.font.bold = True; r.font.color.rgb = ROYAL; r.font.name = "Segoe UI"
    p2 = tf.add_paragraph(); p2.space_after = Pt(12)
    r2 = p2.add_run(); r2.text = body
    r2.font.size = Pt(12.5); r2.font.color.rgb = MUTED; r2.font.name = "Segoe UI"

tb, tf = textbox(s, Inches(0.7), Inches(6.35), Inches(11.9), Inches(0.6))
para(tf, "Two products behind one login — a caregiver can never reach clinical screens; a worker can never see a family outside their scope.",
     size=12.5, color=INK, bold=True, first=True)
footer(s, 2)

notes(s, "The killers are known and time-critical: neonatal sepsis, childhood pneumonia, pre-eclampsia, low birth weight. Outcomes are decided in hours. "
         "But the frontline system has four compounding gaps — walk each one slowly. The referral point lands hardest: on paper, nobody knows if the family ever arrived. "
         "Then introduce the three users. Emphasise the role separation is hard-coded, not a settings page: RBAC with three guards — capability, household scope, person scope — "
         "and the router hard-blocks cross-role navigation. Judges who probe privacy will find this holds.")

# ====================================================== SLIDE 3 — HOW IT WORKS
s = add_slide()
rect(s, 0, 0, SW, SH, WHITE)
kicker_title(s, "How the system works", "One clinic day. Zero signal required.", ROYAL)

steps = [
    ("1 · Today", "honest status line — “Working offline · 3 changes waiting to send” — live queue, urgent referrals"),
    ("2 · Receive", "WHO ETAT “look before you log”: 3 observations route a sick child to the 60-second emergency tunnel"),
    ("3 · Roll call", "“Who is here?” — absence is recorded, not skipped; sessions resume if interrupted"),
    ("4 · Assess", "age-branched forms, WHO IMCI + GHS protocols, real 60-second respiratory-rate timer"),
    ("5 · Verdict", "triage colour hero, AI risk insight (suppressed on drift), stabilisation steps, referral code"),
    ("6 · Follow up", "day plan of overdue/due reviews; referral desk tracks arrival vs treatment separately"),
]
x0, y0 = Inches(0.7), Inches(1.95)
for i, (head, body) in enumerate(steps):
    cx = x0 + Inches(6.25) * (i % 2)
    cy = y0 + Inches(1.32) * (i // 2)
    rect(s, cx, cy, Inches(6.0), Inches(1.14), CANVAS)
    tb, tf = textbox(s, cx + Inches(0.2), cy + Inches(0.12), Inches(5.6), Inches(0.95))
    para(tf, head, size=15, color=ROYAL, bold=True, first=True, space_after=2)
    para(tf, body, size=11.5, color=INK, space_after=0)

tb, tf = textbox(s, Inches(0.7), Inches(6.0), Inches(11.9), Inches(0.9))
para(tf, "Under the hood: atomic outbox — every clinical write enqueues its sync intent in the same database transaction. "
         "Critical referrals sync first (priority 0 of 4 tiers); exponential backoff 1→120 min; idempotent upserts to MariaDB; "
         "a strict 16-table server whitelist closes the injection surface.", size=12.5, color=MUTED, first=True)
footer(s, 3)

notes(s, "Walk the day left to right, top to bottom — this is a real clinic day, not a feature list. "
         "Pause on step 2: the emergency tunnel needs no name, no household, no network — IMCI danger signs as big YES/NO taps, "
         "with a real 60-second respiratory-rate timer and WHO fast-breathing cut-offs by age. "
         "Step 3 is the detail field workers respect: the child who wasn't brought is the one who never gets measured — absence is recorded. "
         "Then the engineering claim for the technical judges, from the bottom strip: the atomic outbox pattern. "
         "A record literally cannot exist without its sync intent — verified across all 30+ write sites. That is the sentence to say out loud.")

# ====================================================== SLIDE 4 — SECURITY
s = add_slide()
rect(s, 0, 0, SW, SH, NAVY)
tb, tf = textbox(s, Inches(0.7), Inches(0.45), Inches(11.9), Inches(1.5))
para(tf, "DATA PROTECTION & COMPLIANCE", size=13, color=BRASS, bold=True, first=True, space_after=4)
para(tf, "Security that survives a hostile audit", size=30, color=WHITE, bold=True, space_after=0)
rect(s, Inches(0.7), Inches(1.55), Inches(1.2), Pt(4), BRASS)

cards = [
    ("Dual-hash, zero-knowledge PIN", [
        "Local PIN: HMAC-SHA256 ×20,000, device-only salt — never synced",
        "Cloud verifier: +120,000 iterations, domain-separated, separate table",
        "Challenge-response login — the PIN never crosses the wire",
        "Full DB theft still yields no usable credential",
    ]),
    ("RBAC at the data boundary", [
        "Three guards on every read/write: permission → household → person",
        "Denials audit-logged, then AccessDenied is thrown",
        "Caseload scoped by JWT claims — server ignores client scope params",
        "Weak PINs (1111/1234/4321/0123) rejected at registration",
    ]),
    ("Compliance by construction", [
        "Recalibration exports: no names, phones, communities, exact dates",
        "Age bands + month granularity; salted linkage key held by GHS",
        "District officer signs every export (Kintampo / Navrongo pipeline)",
        "Sync audit log carries zero PHI; SHA-256 blocks tampered models",
    ]),
]
x = Inches(0.7)
for title, lines in cards:
    rect(s, x, Inches(2.0), Inches(3.95), Inches(4.55), RGBColor(0x13, 0x2C, 0x60))
    tb, tf = textbox(s, x + Inches(0.25), Inches(2.25), Inches(3.45), Inches(4.1))
    para(tf, title, size=16, color=BRASS, bold=True, first=True, space_after=10)
    for line in lines:
        p = tf.add_paragraph(); p.space_after = Pt(8)
        r = p.add_run(); r.text = "• " + line
        r.font.size = Pt(11.5); r.font.color.rgb = RGBColor(0xC9, 0xD6, 0xF2); r.font.name = "Segoe UI"
    x += Inches(4.15)

tb, tf = textbox(s, Inches(0.7), Inches(6.75), Inches(11.9), Inches(0.5))
para(tf, "The privacy claim is architectural, not a policy PDF: the server never holds a reversible credential, and exports are de-identified by construction.",
     size=12.5, color=WHITE, bold=True, first=True)
notes(s, "This slide is built to be attacked. Column one: the dual-hash design — a 20,000-iteration local HMAC never leaves the device; "
         "the server stores a further 120,000-iteration domain-separated verifier in a physically separate table with constant-time comparison. "
         "Login is challenge-response; the PIN never crosses the wire. Column two: RBAC — three guards at the repository boundary, and the server derives "
         "scope from JWT claims, ignoring anything the client asks for. Column three: compliance — recalibration exports are de-identified by construction, "
         "the linkage salt is held by GHS not shipped in the app, and a district officer signs every export. Close with the bottom line: privacy here is architecture, not policy.")

# ====================================================== SLIDE 5 — AI SYSTEM
s = add_slide()
rect(s, 0, 0, SW, SH, CANVAS)
kicker_title(s, "The AI & recommendation system", "Honest AI. On-device. Accountable.", ROYAL)

from pptx.util import Cm
rows = [
    ("Model", "Population", "Trained on", "Evidence", None),
    ("Neonatal sepsis", "0–59 days", "REAL records — Mbarara RRH EMR (n=964)", "CV AUC 0.90", GREEN),
    ("Child pneumonia", "2–59 months", "Simulator seeded from WHO IMCI + Baiden 2011", "Screening aid — ext. validation pending", AMBER),
    ("Pre-eclampsia", "ANC 20w+", "Simulator seeded from published Ghana studies", "External check AUC 0.74 (UCI cohort)", AMBER),
    ("LBW / SGA", "Newborns", "Simulator seeded from Savelugu + MICS", "Screening aid — ext. validation pending", AMBER),
]
tbl_shape = s.shapes.add_table(5, 4, Inches(0.7), Inches(1.85), Inches(11.9), Inches(2.5))
tbl = tbl_shape.table
tbl.columns[0].width = Inches(2.2); tbl.columns[1].width = Inches(1.7)
tbl.columns[2].width = Inches(4.6); tbl.columns[3].width = Inches(3.4)
for ri, (a, b, c, d, color) in enumerate(rows):
    for ci, val in enumerate((a, b, c, d)):
        cell = tbl.cell(ri, ci)
        cell.fill.solid()
        cell.fill.fore_color.rgb = NAVY if ri == 0 else WHITE
        tfp = cell.text_frame.paragraphs[0]
        run = tfp.add_run(); run.text = val
        run.font.size = Pt(12 if ri else 12.5)
        run.font.bold = ri == 0 or ci == 0
        run.font.name = "Segoe UI"
        run.font.color.rgb = WHITE if ri == 0 else (color if ci == 3 and color else INK)

tb, tf = textbox(s, Inches(0.7), Inches(4.65), Inches(11.9), Inches(2.2))
para(tf, "Honesty is engineered, not claimed", size=15, color=NAVY, bold=True, first=True, space_after=8)
bullets(tf, [
    ("Evidence framing enforced in code", "real-data models headline cross-validation; simulator models headline their external check — internals labelled “sanity check, not evidence”"),
    ("Drift guard", "per-feature z-score monitoring; out-of-window inputs suppress the probability (“n/a · out of training window”) instead of a confident wrong answer"),
    ("Calibration done right", "Platt scaling on the logit side; SHA-256 integrity chain blocks tampered weights; deterministic noisy-OR fallback if any model is unavailable"),
    ("Accountable override", "clinicians can override any AI verdict — with a mandatory ≥10-character reason persisted to the audit trail"),
], size=12.5, gap=7)
footer(s, 5)

notes(s, "Four int8 TFLite models run fully offline. Be the most honest AI pitch the judges hear all day: only the sepsis model leads with real patient data — "
         "AUC 0.90 cross-validated on 964 Mbarara records. The other three are simulator-seeded and SAY SO on the slide; the pre-eclampsia model's evidence is its "
         "external check (AUC 0.74 on a real Bangladeshi cohort), not its internal 1.0, which the app itself labels a sanity check. "
         "This framing is not a slide choice — OfflineModelStatus.headlineValidation enforces it in code. "
         "Then the guardrails: drift suppression, logit-side Platt calibration, SHA-256 integrity, deterministic fallback, and the 10-character override audit. "
         "The recalibration pathway (Kintampo/Navrongo, ~5,000 linked outcomes) is how every model earns a Ghanaian-patient-data headline. "
         "Deterministic engines handle what guidelines already solve: IMCI, EPI catch-up, growth z-scores, vulnerability scoring with modifiable risk first.")

# ====================================================== SLIDE 6 — NLP
s = add_slide()
rect(s, 0, 0, SW, SH, WHITE)
kicker_title(s, "Language accessibility", "Advice that isn't understood doesn't exist", BRASS)

layers = [
    ("1 · Recorded speech bank", "human-recorded audio for fixed clinical phrases — Dagbani recorded; Mampruli & Kusaal drafted with community speakers. Highest trust: real voice, fixed meaning.", GREEN),
    ("2 · On-device neural translation", "MarianMT ONNX (Helsinki-NLP), int8/int16-quantised — English → Twi and English → Hausa, fully offline. Tokeniser re-implemented in Dart with token-for-token parity fixtures checked at load.", ROYAL),
    ("3 · Curated phrase dictionary", "deterministic clinician-vetted fallback for greetings and stock phrases — never wrong, never invented.", BRASS),
]
y = Inches(1.95)
for title, body, color in layers:
    rect(s, Inches(0.7), y, Inches(0.14), Inches(1.35), color)
    tb, tf = textbox(s, Inches(1.05), y + Inches(0.05), Inches(11.5), Inches(1.35))
    para(tf, title, size=16, color=NAVY, bold=True, first=True, space_after=3)
    para(tf, body, size=12.5, color=INK, space_after=0)
    y += Inches(1.6)

rect(s, Inches(0.7), y + Inches(0.05), Inches(11.9), Inches(1.15), RGBColor(0xFB, 0xF3, 0xE4))
tb, tf = textbox(s, Inches(1.0), y + Inches(0.2), Inches(11.3), Inches(0.9))
para(tf, "Clinical safety guardrails", size=13.5, color=BRASS, bold=True, first=True, space_after=3)
para(tf, "Dynamic clinical text is never machine-translated blindly — only vetted references translate; stale ones block with an explicit notice. "
         "Dosages, thresholds and referral codes are protected and never altered by the translation path.",
     size=12, color=INK, space_after=0)
footer(s, 6)

notes(s, "Three layers, in order of trust. Layer one is a recorded speech bank — a real human voice for the fixed phrases that matter most; Dagbani is recorded, "
         "Mampruli and Kusaal are drafted with community speakers. Layer two is the engineering flex: full MarianMT neural translation running ON the device — "
         "Twi and Hausa — quantised, with the SentencePiece tokeniser re-implemented in Dart. The parity story is the sentence to land: token-for-token fixtures are "
         "checked at model load, and packaging refuses to ship unless the quantised model reproduces the fp32 reference exactly. If it ever diverges, it refuses to run "
         "rather than mistranslate clinical advice. Layer three is a curated dictionary. Finish on the guardrail box — that is what makes this clinically deployable "
         "rather than a demo: protected content like dosages and referral codes can never be touched by translation.")

# ====================================================== SLIDE 7 — REFERRALS + ASK
s = add_slide()
rect(s, 0, 0, SW, SH, NAVY)
rect(s, 0, 0, Inches(0.18), SH, BRASS)
tb, tf = textbox(s, Inches(0.7), Inches(0.45), Inches(11.9), Inches(1.5))
para(tf, "THE REFERRAL LOOP — AND THE ASK", size=13, color=BRASS, bold=True, first=True, space_after=4)
para(tf, "A referral is a tracked lifecycle, not a paper slip", size=28, color=WHITE, bold=True, space_after=0)
rect(s, Inches(0.7), Inches(1.55), Inches(1.2), Pt(4), BRASS)

flow = ["ISSUED\nCB-code + SBAR note", "TRAVELLING\nfamily-reported", "ARRIVED\nstaff code-verified", "TREATED\n& discharged"]
x = Inches(0.85)
for i, step in enumerate(flow):
    rect(s, x, Inches(2.05), Inches(2.6), Inches(1.0), RGBColor(0x13, 0x2C, 0x60))
    tb, tf = textbox(s, x + Inches(0.12), Inches(2.18), Inches(2.36), Inches(0.8))
    head, _, sub = step.partition("\n")
    para(tf, head, size=14, color=WHITE, bold=True, first=True, align=PP_ALIGN.CENTER, space_after=1)
    para(tf, sub, size=10, color=RGBColor(0xC9, 0xD6, 0xF2), align=PP_ALIGN.CENTER, space_after=0)
    if i < 3:
        tb, tf = textbox(s, x + Inches(2.62), Inches(2.3), Inches(0.35), Inches(0.5))
        para(tf, "→", size=20, color=BRASS, bold=True, first=True, align=PP_ALIGN.CENTER, space_after=0)
    x += Inches(2.95)

tb, tf = textbox(s, Inches(0.85), Inches(3.35), Inches(11.6), Inches(1.85))
bullets(tf, [
    ("Auto-escalation", "urgent referral open 48h with no confirmed arrival → “trace now”, pushed into the day plan"),
    ("Honest outcomes", "arrival ≠ treatment; failure states (did not attend, declined, died) are recorded, not hidden"),
    ("Barrier intelligence", "transport cost, distance, registration — a barrier named once is shown before the next referral"),
    ("Closed loop", "the caregiver app shows the family the same status and code — both sides stay honest"),
], size=12.5, gap=7, marker_color=BRASS)

rect(s, Inches(0.85), Inches(5.35), Inches(11.6), Inches(1.0), RGBColor(0x13, 0x2C, 0x60))
tb, tf = textbox(s, Inches(1.15), Inches(5.5), Inches(11.0), Inches(0.75))
para(tf, "“Other apps digitise the form. CareBridge AI closes the loop.”", size=17, color=WHITE, bold=True, first=True,
     align=PP_ALIGN.CENTER, space_after=0)

tb, tf = textbox(s, Inches(0.85), Inches(6.55), Inches(11.6), Inches(0.8))
para(tf, "THE ASK:  pilot cohort in Northern Region CHPS zones · recalibration pipeline via Kintampo HRC / Navrongo HDSS · extend recorded speech to Mampruli & Kusaal",
     size=12.5, color=BRASS, bold=True, first=True, align=PP_ALIGN.CENTER, space_after=0)

notes(s, "Land the close. Every referral gets a crypto-secure CB reference code, an urgency tier, and an SBAR handover note. Walk the lifecycle across the top — "
         "and stress that arrival and treatment are separate outcomes, and the failure states (did not attend, declined, died) are recorded honestly, not hidden. "
         "The 48-hour auto-escalation is the detail that gets nods from health judges: an urgent referral with no confirmed arrival becomes a “trace now” chase item "
         "in the worker's day plan — automatically. Barrier intelligence means a family that failed once over transport cost is never re-referred blind. "
         "Say the quote on the banner verbatim, pause, then make the ask: a pilot cohort, the recalibration pipeline through Kintampo or Navrongo, and funding to "
         "extend recorded speech into Mampruli and Kusaal. Thank the room and stop talking.")

prs.save(r"c:\Users\Alhaji_stunner\Videos\unicef\CareBridge_AI_Pitch_Deck.pptx")
print("Saved CareBridge_AI_Pitch_Deck.pptx with", len(prs.slides.__iter__.__self__._sldIdLst), "slides")
