# CareBridge AI

Offline-first maternal, newborn, and child health decision support for Northern Ghana.

CareBridge AI connects the two people who decide whether a mother or child survives: the frontline health worker at the CHPS compound, and the caregiver at home. It runs entirely on the phone, with or without internet, and speaks the languages of the North.

## The problem

CHPS health workers in Northern Ghana screen pregnant mothers, newborns, and children under 5 every day, often offline, under pressure, and with paper records that cannot rank risk or follow referrals home. Meanwhile, the caregiver at home has no way to recognise danger signs between visits.

## What the app does

**For the frontline health worker**
- Guided assessments for pregnant women, young infants (0–59 days), and children (2–59 months), built on WHO IMCI, WHO ANC, and Ghana Health Service protocols
- On-device AI screening models (newborn sepsis, childhood pneumonia, pre-eclampsia, low birth weight) that run first and explain every flag in plain language, with fixed protocol rules that always overrule the model
- Pre-referral stabilisation guidance and referral to the nearest suitable facility
- A ranked daily plan ("Plan My Day"), household register, referral follow-up tracking, and zone-level insights
- Clinician override: the health worker can overrule the AI, and her judgment governs the care plan

**For the caregiver**
- A simple danger-sign check, one tap at a time, with spoken guidance in Dagbani
- Care plans and check history for the family
- PIN privacy, because the family phone is usually shared

## Design principles

- **Offline is the default, not a fallback.** Records live on the phone in SQLite and sync quietly to a central database when signal allows. Urgent referrals always leave the queue first.
- **The AI must be quiet, never wrong.** If a case falls outside the model's training window or a key measurement is missing, the AI says so and steps back while the protocols take over.
- **Nothing replaces the clinician.** Every flag shows its reason and its protocol source, and nothing enters the record without the worker's sign-off.
- **The app never pretends.** Voices are real studio recordings where available, and the app shows plainly which voice is playing.

## Technology

- Flutter (Android, iOS, web demo frame)
- SQLite on-device storage with an opportunistic, priority-ordered sync queue
- On-device TFLite models with integrity verification and a deterministic rule-based fallback
- Voice chain: studio recordings → phone TTS → Hausa bridge → read aloud
- Reference data bundled for the five northern regions: facility referral hierarchy, WHO growth standards, and local foods

## Project layout

```
lib/
  app/            providers and app shell
  core/           audio, auth, i18n (Dagbani), ML inference, routing, theme
  data/           SQLite DAOs, reference data, sync transport
  domain/         entities and clinical engines (ANC, IMCI, nutrition,
                  immunisation, nurturing care, barriers, vulnerability)
  presentation/   assessment, FHW tabs, caregiver home, registration, visit flow
server/           sync server
tool/             model training and data tooling
test/             266 automated tests (engines, protocols, widgets)
```

## Getting started

```bash
flutter pub get
flutter run
flutter test   # 266 tests
```

## Team

Built for the UNICEF hackathon by team CareBridge, focused on maternal, newborn, and under-5 survival in underserved communities of Northern Ghana.
