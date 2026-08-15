Local-language audio guidance recordings.

Files are picked up automatically by lib/core/audio/voice_service.dart using
the naming convention:

    <id>_<language-slug>.mp3

The slug is the first word of the language name, lowercased, letters and
digits only — e.g.:

    child_danger_signs_dagbani.mp3
    newborn_danger_signs_hausa.mp3
    mother_danger_signs_likpakpaln.mp3   (Likpakpaln (Konkomba))
    referral_english.mp3

Two kinds of ids exist:

  * Topics (5): child_danger_signs, newborn_danger_signs,
    mother_danger_signs, feeding, referral.
  * Triage questions (18 unique): q_feed, q_fast, q_fits, q_sleepy, q_temp,
    q_yellow, q_cord, q_vomit, q_drink, q_breath, q_blood, q_thin, q_fever,
    q_bleed, q_head, q_pain, q_smell, q_move. One file per sign — a sign
    shared by several client streams (e.g. q_fits serves newborn, child and
    mother) uses one recording with the generic sign wording.

Until recordings exist, the app speaks the script through the phone's TTS,
falls back to the Hausa bridge, then to read-aloud — care never waits on
an MP3.

=====================================================================
DAGBANI V1 — RECORDING PROTOCOL (the first verified pack)
=====================================================================

Checklist: dagbani_pack_manifest.json (23 files, all "pending").

1. THE VOICE
   - One voice for all 23 files: a trusted native-Dagbani speaker — a CHO,
     a CHPS-compound volunteer, or a community radio voice.
   - Speak to one imagined listener: a grandmother in a village, not a
     classroom. Steady, warm, unhurried.

2. THE SCRIPT
   - Read the lines exactly as the app shows them: open the Voice test
     screen in the app and record line by line (29 script lines -> 23
     files; the 6 per-client wordings of shared signs are recorded once,
     using the generic sign wording).
   - The Dagbani text of every line lives in
     lib/core/i18n/dagbani_strings.dart next to its English source.

3. THE ROOM
   - Quiet room, no fan, no open window facing a road. A room with soft
     furnishings (curtains, mattresses) kills echo.
   - Phone or recorder 20-30 cm from the mouth, slightly off-axis to avoid
     plosive pops.

4. THE FILES
   - Record WAV or high-quality M4A; convert to MP3 mono, 64-96 kbps,
     22.05 kHz or better.
   - Leave ~0.3 s of silence at the head and tail. Loudness-normalize all
     23 files to the same level so the voice never jumps between cards.
   - Name each file exactly as the manifest lists it and drop it in this
     folder. The app finds it on next launch — no code change, no rebuild
     of logic.

5. THE EAR-TEST (what "verified" means)
   - Play each file to at least 3 native Dagbani speakers at a CHPS
     compound, without telling them the topic first.
   - Each listener must correctly say which danger sign or topic the file
     is about. Any file that is misheard gets re-recorded.
   - Two independent sign-offs (CHO + district officer or radio
     proofreader), then:
       a) set the file's manifest status to "verified" with the date and
          reviewer initials, and
       b) flip verified=true on the matching entries in
          lib/core/i18n/dagbani_strings.dart so the app starts showing the
          Dagbani text too.

=====================================================================
KHAYA AI PIPELINE (machine-drafted voice — same trust gates)
=====================================================================

Khaya AI (NLP Ghana — https://translation.ghananlp.org) offers Dagbani
machine translation AND text-to-speech. tool/khaya_voice_pack.py uses it
at build time; the app itself still never touches the network for voice.

What changes and what does not:

  * SPEED — Khaya can draft all 23 lines in minutes and synthesize a first
    full Dagbani voice pack the same day, instead of waiting for a studio
    session.
  * TRUST — nothing is auto-verified. Khaya output is a DRAFT. The same
    ear-test (step 5 above) decides whether each file ships, and
    verified=true still waits for two human sign-offs. A machine voice
    that mispronounces a danger sign is worse than no voice.
  * FALLBACK — any file Khaya renders poorly gets re-recorded by a human
    under the protocol above. The manifest tracks each file's origin.

Workflow:

  1. python tool/khaya_voice_pack.py --dry-run     # shows the full plan
  2. $env:KHAYA_API_KEY="..."                       # portal subscription key
  3. python tool/khaya_voice_pack.py --drafts      # drafts JSON for review
  4. Native speaker reviews tool/out/khaya_dagbani_drafts.json; approved
     wording is merged into dagbani_strings.dart (still verified=false).
  5. python tool/khaya_voice_pack.py --tts         # writes the 23 MP3s here
  6. Ear-test every file (step 5 of the protocol). Passed files flip their
     manifest status and their strings' verified flag — together.

The Khaya subscription key is a build-time secret: it lives in the
KHAYA_API_KEY environment variable, never in the repo and never in the
app.
