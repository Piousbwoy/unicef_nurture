# CareBridge AI — narrated demo script (full loop)

**Format:** 12 beats, ~2.5–3 min. Each beat = one screen capture + one narration line (David voice) + on-screen caption.
**Story spine:** Recognition → Decision → Request → Handoff → Arrival → Answer. A chain that does not break without signal.

| # | Screen | Narration | Caption |
|---|--------|-----------|---------|
| 1 | Title card | "Every year, mothers and children in the last mile die in the gap between a symptom and a health worker. CareBridge AI closes that gap — even with no network." | CareBridge AI — the last mile, connected |
| 2 | Caregiver sign-up / family hub | "On a family's phone, Aura Nurture asks nothing of the mother except what she already knows. No forms. No medical words." | For caregivers, in their own language |
| 3 | Family dashboard | "One tap per child. The app keeps a private record for the family — born here, on this device." | The family's own health record |
| 4 | Danger-sign check — person picker | "When something feels wrong, she starts a danger-sign check. It is not a diagnosis. It is the same first questions a nurse would ask." | IMCI-aligned questions, conversational |
| 5 | Question with voice + Hausa | "Every question is read aloud, in her language — Hausa or Twi — translated and spoken entirely on the phone. No data plan needed." | On-device voice: English, Hausa, Twi |
| 6 | Danger sign answered — red alarm card | "She answers yes to one danger sign. The app raises an alarm she can act on — and never ends the check. She stays in control." | An alarm you can act on — never a dead end |
| 7 | Result — verdict hero + action steps | "The result tells her exactly what to do now — even on the way to the facility — in one card per action, ticked off like the nurse's own checklist." | Do these now — even on the way |
| 8 | Ask for help — CareRequest card | "And she can ask her health worker for help — from the phone, in the village, with no signal. The request holds the name and the urgency. Nothing else." | A privacy-bounded request, queued for the network |
| 9 | Sync lands (server log / DB row) | "The moment any phone in the family reaches signal, the request travels — through an offline outbox that never loses what a mother has already said." | Offline-first sync — nothing is lost |
| 10 | FHW workspace — referral trace line | "At the CHPS compound, the community health worker sees it on a trace line: raised, received, acted on. A referral cannot silently disappear here." | The referral desk with a trace line |
| 11 | FHW responds / follow-up recorded | "She answers, schedules the follow-up, and records what happened — the same screen that already tracks her clinic register." | One workspace: queue, vitals, follow-ups |
| 12 | Caregiver sees the answer + closing card | "Back home, the mother's phone shows the answer. Not a dispatch promise — an honest reply. CareBridge AI: recognition, decision, request, handoff, answer. A chain that survives the last mile." | CareBridge AI — every handoff, accounted for |

## Build notes
- Web build: `flutter build web --release` → served statically.
- Sync server: `server/` on :3000 with MariaDB (seed-auth/seed-demo scripts available).
- Narration: PowerShell System.Speech, voice "Microsoft David Desktop", one WAV per beat.
- Assembly: ffmpeg — slide images (looped) + per-beat audio + burned captions, 1920x1080.
