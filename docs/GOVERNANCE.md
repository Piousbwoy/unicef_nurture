<!-- Generated from lib/domain/governance.dart. Do not hand-edit: test/governance_test.dart fails if this file stops matching the register. Regenerate with WRITE_GOVERNANCE_DOC=1 flutter test test/governance_test.dart -->

# Record of processing, access matrix and control map

CareBridge AI — community maternal and newborn care for Ghana CHPS compounds. This is the privacy register in the form Act 843 and Article 30 both ask for: what is processed, on what basis, for how long, who may see it, and which safeguard covers it.

It is generated from code and reconciled against four artefacts that are not opinions — the local schema, `server/schema.sql`, the sync whitelist in `server/src/tables.js` and the pull list in `server/src/pull.js`. A table with no declared purpose fails the build, and so does a purpose whose table has disappeared.

## 1. Processing activities

### Account identity and cloud authentication

`identity`

Tables: `users`, `user_verifiers`.

- **Purpose** — To know whose hands the handset is in, to scope every query to the caseload that account is responsible for, and to let the same worker sign in on a replacement device after a loss.
- **Lawful basis** — Legal obligation of the data controller
- **Whose data** — Health workers and enrolled caregivers, not patients.
- **Retention** — For as long as the account is in use. The district copy holds no PIN material, so there is nothing there to compromise when an account ends.
- **Enforced by** — AuthenticationService, and the per-role capability set in Permission.forRole.
- **Readable with** — viewCommunityInsights
- **Writable with** — registerHousehold

### Server-issued session material

`sessions`

Tables: `refresh_tokens`.

- **Purpose** — To end a stolen bearer token without waiting for it to expire, and to revoke every session on a device reported lost.
- **Lawful basis** — System operation, no personal data processed
- **Whose data** — Health workers and enrolled caregivers.
- **Retention** — Until expiry or revocation. No app role reads this table; the server does, on its own authority.
- **Enforced by** — server/src/auth.js, which stores hashes and honours revocation.

### Household registration and the visit to the dwelling

`household`

Tables: `households`, `home_checks`.

- **Purpose** — To find the family at all, to reach them in an emergency, and to record the shared risks — water, sanitation, sleeping arrangement, net use — that belong to the dwelling rather than to one person.
- **Lawful basis** — Consent of the data subject
- **Whose data** — Every person resident in the household, including those not otherwise enrolled.
- **Retention** — While the household is under the CHPS zone’s care. Environmental check history stays on the device that recorded it; the district keeps the household itself.
- **Enforced by** — CareRepository._requireHouseholdScope, which refuses a household outside the account’s own scope.
- **Readable with** — viewAllHouseholds, viewOwnFamilyOnly
- **Writable with** — registerHousehold, manageOwnFamily

### The person register

`person`

Tables: `persons`.

- **Purpose** — To name the individual care is being given to, to link a newborn to its mother, and to check NHIS cover before a referral is sent.
- **Lawful basis** — Consent of the data subject
- **Whose data** — Enrolled individuals.
- **Retention** — While the person is in the programme. A erasure request removes the name, phone and NHIS number and leaves the clinical history without identifiers.
- **Enforced by** — RecordAccessPolicy, which is where the protection class and the caseload relationship are actually decided.
- **Readable with** — viewAllHouseholds, viewOwnFamilyOnly
- **Writable with** — registerHousehold, manageOwnFamily

### Pregnancy, birth and postnatal health

`maternal` · **special personal data**

Tables: `maternal_records`.

- **Purpose** — To run the antenatal and postnatal schedule, to detect pre-eclampsia and postpartum danger signs while they are still actionable, and to screen for PMTCT and the mother’s mental health.
- **Lawful basis** — Consent of the data subject
- **Whose data** — Pregnant and postpartum women.
- **Retention** — Per Ghana Health Service health-records retention, which this build does not decide. Deletion on request is handled by erasing identifiers and keeping the de-identified history.
- **Enforced by** — RecordAccessPolicy plus the HIV, syphilis, hepatitis B, sickling and Edinburgh self-harm columns, which are the reason the protection class exists.
- **Readable with** — viewAllHouseholds, viewOwnFamilyOnly
- **Writable with** — recordClinicalVitals, runClinicalAssessment

### Newborn health at and after birth

`newborn` · **special personal data**

Tables: `birth_records`.

- **Purpose** — To resuscitate and thermal-care the newborn on evidence, to run the day-by-day danger-sign checks, and to complete birth screening including sickle cell and hearing.
- **Lawful basis** — Consent of the data subject
- **Whose data** — Newborns.
- **Retention** — As for maternal health records.
- **Enforced by** — RecordAccessPolicy.
- **Readable with** — viewAllHouseholds, viewOwnFamilyOnly
- **Writable with** — recordClinicalVitals, runClinicalAssessment

### Child growth, development and illness classification

`child` · **special personal data**

Tables: `milestone_checks`, `growth_measurements`, `child_assessment_snapshots`.

- **Purpose** — To plot growth against WHOs standards and catch faltering early, to record developmental milestones, and to classify a sick child into the right IMCI category at the point of care.
- **Lawful basis** — Consent of the data subject
- **Whose data** — Newborns and children under five.
- **Retention** — As for maternal health records.
- **Enforced by** — RecordAccessPolicy.
- **Readable with** — viewAllHouseholds, viewOwnFamilyOnly
- **Writable with** — recordClinicalVitals, runClinicalAssessment, runCaregiverTriage

### The visit, the roll call and the assessment verdict

`encounter` · **special personal data**

Tables: `visits`, `visit_participants`, `assessments`.

- **Purpose** — To evidence that a visit happened and whom it reached, to carry the classification and care plan forward, and to keep an AI recommendation overridable by a named human with a stated reason.
- **Lawful basis** — Necessary to provide the health care recorded
- **Whose data** — Everyone present at the visit.
- **Retention** — As for health records.
- **Enforced by** — VisitDao and the override columns on assessments, which refuse an override without a reason and a person.
- **Readable with** — viewAllHouseholds, viewOwnFamilyOnly
- **Writable with** — runClinicalAssessment, overrideAiRecommendation, planVisitRoute

### Referral, arrival and follow-up

`referral` · **special personal data**

Tables: `referrals`, `follow_up_contacts`, `scheduled_contacts`.

- **Purpose** — To get a mother to a facility that knows she is coming, and then to answer the question the paper system never closes: did she arrive, and what care did she actually receive?
- **Lawful basis** — Necessary to provide the health care recorded
- **Whose data** — The referred person and the household that followed up.
- **Retention** — Until the episode is closed and reported, then as a health record.
- **Enforced by** — RecordAccessPolicy and the referral scope checks in CareRepository.
- **Readable with** — viewAllHouseholds
- **Writable with** — issueReferral, confirmReferralArrival

### Barriers the family reports

`barrier`

Tables: `barrier_reports`.

- **Purpose** — To record in the family’s own words why care did not happen, so the compound plans around it rather than logging a default.
- **Lawful basis** — Consent of the data subject
- **Whose data** — The household or person reporting.
- **Retention** — Until resolved, then kept as history of the obstacle.
- **Enforced by** — CareRepository scope checks; no clinical field is writable here.
- **Readable with** — viewAllHouseholds, viewOwnFamilyOnly
- **Writable with** — recordBarrier

### A family asking for care

`familyRequest`

Tables: `care_requests`, `caregiver_drafts`.

- **Purpose** — To let a household call a worker to the door, and to make sure the answer — not silence — reaches the handset the question came from.
- **Lawful basis** — Consent of the data subject
- **Whose data** — The requesting household.
- **Retention** — Until answered, plus the record of the answer.
- **Enforced by** — CareRepository, which binds a caregiver account to exactly one household; drafts stay on this device until sent.
- **Readable with** — viewAllHouseholds, viewOwnFamilyOnly
- **Writable with** — requestCare, manageOwnFamily

### What the family read and asked on their own handset

`familyVoice`

Tables: `caregiver_activity`, `caregiver_settings`.

- **Purpose** — To resume the guidance where the family left off, on this handset, in their language.
- **Lawful basis** — Consent of the data subject
- **Whose data** — The caregiver account and the household it is bound to.
- **Retention** — Until the family clears it, on this device only.
- **Enforced by** — Storage scope: these rows are deliberately absent from the sync whitelist, so reading about infant feeding does not create a file at the district.
- **Readable with** — viewOwnFamilyOnly
- **Writable with** — manageOwnFamily

### The consent history

`consent`

Tables: `consent_events`.

- **Purpose** — To be able to say, months later, which notice was read out, in what language, on what date, and what was agreed to — including what was later withdrawn.
- **Lawful basis** — Necessary for the accountability record
- **Whose data** — The consenting individual and the household.
- **Retention** — Longer than the record it authorises. A withdrawal is a new row, so the fact that care was lawful between two dates survives.
- **Enforced by** — ConsentDao, which exposes no update and no delete.
- **Readable with** — viewAllHouseholds
- **Writable with** — registerHousehold

### The tamper-evident access ledger and its anchors

`accessTrail`

Tables: `access_ledger`, `ledger_anchors`.

- **Purpose** — To answer a family’s question “who looked at my record”, and to let the district notice a trail that was rewritten after the fact.
- **Lawful basis** — Necessary for the accountability record
- **Whose data** — The worker who looked, and the person looked at.
- **Retention** — Retained after erasure of the record it describes: destroying the evidence of an access would destroy the account of whether it was lawful.
- **Enforced by** — AccessLedgerDao, which appends only; the HMAC chain key lives in secure storage and is never transmitted; ledger_anchors is immutable by server trigger.
- **Readable with** — viewCommunityInsights
- **Writable with** — viewAllHouseholds

### Data-rights requests and the answers to them

`dataRights`

Tables: `data_rights_requests`.

- **Purpose** — To turn a family’s statutory request into visible work with a deadline, rather than a message nobody is accountable for answering.
- **Lawful basis** — Legal obligation of the data controller
- **Whose data** — The requesting individual.
- **Retention** — Kept after fulfilment — the answer is the evidence.
- **Enforced by** — DataRightsDao and the supervisor desk queue.
- **Answered within** — 30 days
- **Readable with** — viewCommunityInsights
- **Writable with** — viewOwnFamilyOnly, viewAllHouseholds

### What the district handed out

`districtReads`

Tables: `server_read_log`.

- **Purpose** — To cover the half of the trail a handset cannot see: the device that downloaded a caseload is not the device that read a record, and a recovery restore moves thousands of rows at once.
- **Lawful basis** — Necessary for the accountability record
- **Whose data** — The account that pulled, and the scope it was served.
- **Retention** — District retention policy, which this build does not set.
- **Enforced by** — server/src/read_audit.js — the only writer.

### Synchronisation and operational state

`machinery`

Tables: `sync_outbox`, `sync_state`, `audit_log`.

- **Purpose** — To get work done offline and admit it exactly once when a signal arrives.
- **Lawful basis** — System operation, no personal data processed
- **Whose data** — No data subject — these rows describe the device.
- **Retention** — Until admitted, then cleared.
- **Enforced by** — SyncService and the outbox, which is inside the encrypted database because it temporarily holds patient payloads.

### The district’s own admission log

`districtIngest`

Tables: `sync_log`.

- **Purpose** — To keep the server’s receipt for what it accepted and refused, which is where a dispute about a lost change is settled.
- **Lawful basis** — Necessary for the accountability record
- **Whose data** — The account that sent the change.
- **Retention** — District retention policy.
- **Enforced by** — server/src/sync.js — not on the pull list, so it cannot spread.

### De-identified export for model recalibration

`modelRecalibration` · **special personal data**

- **Held outside SQLite** — A JSONL batch file in the app documents directory, and the linkage salt in secure storage. Not a SQLite table, and never on the sync whitelist.
- **Purpose** — To let the risk checks be retrained on real Northern Ghana data under a signed Kintampo HRC / Navrongo HDSS agreement, without the research dataset ever containing a name, a phone number, a community, a household id, a GPS point or a birthday.
- **Lawful basis** — Consent of the data subject
- **Whose data** — Children and mothers whose completed assessment contributed a model prediction. Re-identification is prevented by construction, not by redaction.
- **Retention** — On the handset until the district officer exports the monthly batch and clears it in front of the worker. Revoking the salt stops collection at once.
- **Enforced by** — RecalibrationStore.append, which is a no-op until the GHS-issued salt is provisioned — an unarmed device collects nothing — plus RecalibrationRecord, which holds only a salted SHA-256 person key, a month, an age band and numeric model inputs.
- **Writable with** — exportRecords

## 2. Where the data is allowed to go

Scope is the difference between a register and a leak. Push and pull are separate decisions here, and the accountability evidence is deliberately one-way.

### On this device only

- `home_checks` — The environmental checks a worker performs at the dwelling: water, sanitation, sleeping arrangement, insecticide-treated net use.
- `milestone_checks` — Which developmental milestones a child was observed to reach, and when.
- `caregiver_drafts` — A caregiver’s unfinished entry, held on this handset until it is sent or discarded. It is not a record of anything the district holds.
- `caregiver_activity` — What the family did in the app themselves: which guidance they opened, which questions they asked. Deliberately not whitelisted for sync — a family’s own reading is not data the service gets to collect about them.
- `caregiver_settings` — This handset’s preferences for a caregiver account: language, reminder times, notice acknowledgement.
- `sync_outbox` — The queue of writes waiting for a network. It carries copies of patient payloads until they are admitted, which is why it lives inside the encrypted database rather than in a plain text file.
- `sync_state` — This device’s watermarks and last admitted sequence. Nothing about a family is in this table.
- `audit_log` — The device’s own operational log of authentication and synchronisation events. Distinct from the access ledger: this records that a session opened, not that a record was read.

### This device and the district

- `users` — A health worker’s name, phone number, role and the CHPS zone they are assigned to; or a caregiver’s name, phone number and the one household their account is bound to. On the district copy the PIN columns do not exist.
- `households` — Household name, head of household, contact phone, GPS point, walking time to the facility, NHIS validity and household size.
- `persons` — Full name, client type, sex, date of birth (sometimes estimated), phone, NHIS number, the mother a newborn links to, and the protection class marking.
- `maternal_records` — Pregnancy and postnatal history, antenatal interventions, laboratory results including HIV, syphilis and hepatitis B testing, pre-eclampsia signs, birth-outcome data, breastfeeding findings and the full Edinburgh postnatal depression scale — including the self-harm item.
- `birth_records` — Birth measurements, delivery circumstances, Apgar scores, newborn danger signs,Kangaroo Mother Care details, sickle cell screening and hearing screening.
- `growth_measurements` — Weight, length or height, MUAC, bilateral oedema and palmar pallor, each tied to the child and the time it was taken.
- `child_assessment_snapshots` — The IMCI assessment as performed: symptom history, vital signs, classification inputs, immunisation and feeding detail, malaria RDT result, and the HIV exposure status of the child.
- `visits` — Which household was walked to, by whom, when, the GPS point, the reasons recorded and free-text notes.
- `visit_participants` — The roll call: who in the household was present, who was absent and the note explaining the absence.
- `assessments` — The stored verdict of an assessment — inputs, result and care plan as JSON — plus any override of the AI recommendation, the reason for it and who made it.
- `referrals` — The referral letter itself: reference code, the person referred, the facility, urgency, clinical summary, and who confirmed arrival or escalated it.
- `follow_up_contacts` — Each check-in after a referral: whether the family was reached, what care they actually received, their condition, and the barriers named.
- `scheduled_contacts` — The next contact a family is due, its purpose and priority.
- `barrier_reports` — The obstacles a family reports in their own terms — money, distance, an elder who must agree, a closed post — with notes and whether the barrier was later resolved.
- `care_requests` — A family asking a health worker to come, at what urgency, and the answer the worker gave on another handset.
- `consent_events` — Every consent decision ever made, as its own row: the scope, the decision, which version of the notice was read out, the language, an optional voice artefact and the witness. Withdrawal is a new row, never an edit.
- `access_ledger` — One row per opening of a record: who, in what role, on which device, doing what to whom, for which purpose, on what basis, with the hash that chains it to the row before it.
- `data_rights_requests` — A family’s request to see, correct, object, erase or carry away their data, the 30-day clock it started, and the answer given.

### Sent from the device, kept only at the district

- `user_verifiers` — The salted, domain-separated derivation the cloud authenticates against. Never stored in local SQLite, because a verifier kept beside the records it unlocks is a second key in the same pocket.
- `ledger_anchors` — Every tenth entry, the device’s commitment to its own chain position — the hash and the count. Immutable on the server by trigger, which is what makes a shortened trail detectable rather than merely possible.

### District only

- `refresh_tokens` — Server-issued session material, hashed, with its expiry. A handset cannot write this table even if it is compromised.
- `server_read_log` — What the district handed out: which account pulled which scope, how many rows, and every recovery download. Written only by the server — a read log a handset could write to is a read log that can be emptied.
- `sync_log` — The server’s receipt for every admitted change: who sent it, which entity, whether it was accepted or refused. Never delivered to a handset — the receipt for somebody else’s sync is not data to sync.

Returned to a *different* handset on pull: `households`, `persons`, `visits`, `assessments`, `referrals`, `care_requests`.

Never allowed onto the pull list, because a consent history, the trail of who read a family, an open rights request and the district's own logs are no business of any other handset: `user_verifiers`, `refresh_tokens`, `consent_events`, `access_ledger`, `ledger_anchors`, `data_rights_requests`, `server_read_log`, `sync_log`.

## 3. Access matrix by role

Generated by asking the capability set the app actually enforces (`Permission.forRole`), so this table cannot drift from the code that hides a button or refuses a query. The verdict is a ceiling: the caseload scope and the protection class narrow it further, per row, at the enforcement point named in section 1.

### Frontline Health Worker

- **Account identity and cloud authentication** — Read and write
- **Household registration and the visit to the dwelling** — Read and write
- **The person register** — Read and write
- **Pregnancy, birth and postnatal health** — Read and write
- **Newborn health at and after birth** — Read and write
- **Child growth, development and illness classification** — Read and write
- **The visit, the roll call and the assessment verdict** — Read and write
- **Referral, arrival and follow-up** — Read and write
- **Barriers the family reports** — Read and write
- **A family asking for care** — Read only
- **What the family read and asked on their own handset** — Not reachable
- **The consent history** — Read and write
- **The tamper-evident access ledger and its anchors** — Read and write
- **Data-rights requests and the answers to them** — Read and write
- **De-identified export for model recalibration** — Write only

### Caregiver

- **Account identity and cloud authentication** — Not reachable
- **Household registration and the visit to the dwelling** — Read and write
- **The person register** — Read and write
- **Pregnancy, birth and postnatal health** — Read only
- **Newborn health at and after birth** — Read only
- **Child growth, development and illness classification** — Read and write
- **The visit, the roll call and the assessment verdict** — Read only
- **Referral, arrival and follow-up** — Not reachable
- **Barriers the family reports** — Read and write
- **A family asking for care** — Read and write
- **What the family read and asked on their own handset** — Read and write
- **The consent history** — Not reachable
- **The tamper-evident access ledger and its anchors** — Not reachable
- **Data-rights requests and the answers to them** — Write only
- **De-identified export for model recalibration** — Not reachable

## 4. Control map

Each safeguard names the failure it prevents, the files that implement it and the test that proves it. What it does **not** cover is printed in the same entry, because a control map that only lists successes is marketing.

### `at-rest-encryption`

In place, with a stated limit — owned by this software

- **Failure prevented** — A handset left in a taxi, or sold on, carries every family in a CHPS zone on its storage.
- **What the software does** — The whole database is a SQLCipher file with a per-installation 256-bit key, read back from secure storage before it is used: an install refuses to encrypt with a key it could not retrieve, because that is how records get destroyed by well-meaning software.
- **Cited against** — OWASP MASVS-STORAGE-1 (sensitive data at rest); HIPAA 45 CFR 164.312(a)(2)(iv) encryption; Act 843 s.26 — security of processed data
- **In** — `lib/data/local/db_engine_io.dart`, `lib/data/local/database_secret.dart`, `lib/data/local/app_database.dart`
- **Proved by** — `test/encryption_posture_test.dart`
- **Does not cover** — Web and desktop builds have no SQLCipher engine, so the posture card says "not encrypted at rest" on those platforms instead of the app claiming protection it does not have.

### `conversion-of-existing-data`

In place — owned by this software

- **Failure prevented** — Installs that existed before encryption keep their plaintext file, and the honest word for that is a breach still sitting on disk.
- **What the software does** — A copy-verify-swap migration: the plaintext is copied into an encrypted file at a side path, every table is counted on both sides, and only a match renames over the original. A refusal or a mismatch leaves the original untouched with its rows intact.
- **Cited against** — OWASP MASVS-STORAGE-1; Act 843 s.26
- **In** — `lib/data/local/database_conversion.dart`
- **Proved by** — `test/database_conversion_test.dart`

### `secure-delete`

In place, with a stated limit — owned by this software

- **Failure prevented** — SQLite leaves deleted rows and freed pages readable in the file until they are overwritten, so "the record was deleted" is a claim about bytes, not a fact.
- **What the software does** — `PRAGMA secure_delete = ON` at every open, on every engine, read with rawQuery because the pragma returns a row and the Android engine rejects row-returning statements through execute.
- **Cited against** — OWASP MASVS-STORAGE-2 (data must not be inadvertently exposed); HIPAA 45 CFR 164.310(d)(2)(i) disposal
- **In** — `lib/data/local/app_database.dart`
- **Proved by** — `test/hardening_test.dart`
- **Does not cover** — It overwrites within the database file. It cannot reach blocks the filesystem has already relocated, and it does nothing about blocks that were freed before this build — which is why the conversion exists.

### `transport-security`

In place, with a stated limit — owned by this software

- **Failure prevented** — A health record sent over plain HTTP, or to a server a synthetic credential points at, leaves the compound permanently.
- **What the software does** — One rule enforced at the single HTTP door: https required, with a loopback exception that must be switched on deliberately by a test or a developer build. Android additionally refuses cleartext in its platform configuration.
- **Cited against** — OWASP MASVS-NETWORK-1 (data in transit); HIPAA 45 CFR 164.312(e)(1) transmission security
- **In** — `lib/data/sync/transport_policy.dart`, `lib/data/sync/http_client.dart`, `android/app/src/main/res/xml/network_security_config.xml`, `android/app/src/main/AndroidManifest.xml`
- **Proved by** — `test/transport_policy_test.dart`
- **Does not cover** — The manifest only governs Android. The code rule is what protects the web, iOS and desktop builds, which is why the check lives in the client rather than only in configuration.

### `credential-separation`

In place — owned by this software

- **Failure prevented** — A PIN database sitting beside the records it unlocks turns one leaked file into both a key and a vault.
- **What the software does** — The device holds a stretched local verifier; the cloud authenticates against a domain-separated derivation of it, stored in its own table and never in the synced user row, whose server-side copy has no PIN columns at all.
- **Cited against** — OWASP MASVS-AUTH-1 / MASVS-CRYPTO-2 (key management); HIPAA 45 CFR 164.312(d) person or entity authentication
- **In** — `lib/data/local/user_dao.dart`, `server/src/auth.js`
- **Proved by** — `test/recovery_and_registration_test.dart`

### `inactivity-lock`

In place, with a stated limit — owned by this software

- **Failure prevented** — One Android phone is shared between a CHO, a nurse and a caregiver in a waiting area. A screen left on a bench is an open file on a family.
- **What the software does** — A watchdog per role: a field worker's session locks after an idle window and after the app has been backgrounded long enough, evaluated on resume rather than by timer because Android suspends Dart timers.
- **Cited against** — OWASP MASVS-AUTH-1; HIPAA 45 CFR 164.312(a)(2)(iii); Act 843 s.26
- **In** — `lib/core/auth/idle_lock.dart`, `lib/app/session_guard.dart`, `lib/core/auth/session.dart`
- **Proved by** — `test/idle_lock_test.dart`
- **Does not cover** — A caregiver's own handset is deliberately not locked on idle: the person holding it is the data subject, and a lock that stops a mother reaching infant-feeding advice at 3am is a worse outcome than the risk it prevents.

### `screen-capture`

In place, with a stated limit — owned by this software

- **Failure prevented** — A record on screen is a record in somebody's camera roll, a screenshot in a chat, and a thumbnail in the recent-apps switcher.
- **What the software does** — FLAG_SECURE is set on the activity in every build that is not debuggable, so capture is refused by the platform rather than asked nicely of the user.
- **Cited against** — OWASP MASVS-STORAGE-2; OWASP MASVS-PRIVACY
- **In** — `android/app/src/main/kotlin/gh/carebridge/carebridge_ai/MainActivity.kt`
- **Does not cover** — Android only, and it stops the operating system, not a second phone photographing the screen. Debug builds leave capture working so the screenshot is still possible when the app is being reviewed.

### `access-enforcement`

In place — owned by this software

- **Failure prevented** — A role list on a screen proves that a widget was hidden. It does not prove the data was never read by an account that should not have seen it.
- **What the software does** — Every read goes through a policy decision point that returns a basis — care relationship, consent, emergency, official authority — and every repository method asks it before it touches a DAO. The decision, not the button, is the control.
- **Cited against** — OWASP MASVS-AUTH-1; HIPAA 45 CFR 164.312(a)(1) access control; GDPR Art 25 (protection by design)
- **In** — `lib/data/repositories/record_access.dart`
- **Proved by** — `test/accountability_test.dart`, `test/rbac_test.dart`

### `sensitive-record-class`

In place — owned by this software

- **Failure prevented** — A worker with a legitimate caseload is still a worker with a caseload: for a record carrying HIV status, or a mother's self-harm answer, being entitled to look is not the same as needing to.
- **What the software does** — A protection class on the person row. A marked record opens without a reason only for the worker responsible for it; anyone else must state why, and the stated reason is written into the trail the family can read.
- **Cited against** — Act 843 s.37 (special personal data); HIPAA 45 CFR 164.312(b) audit controls; GDPR Art 9 (data revealing health or beliefs)
- **In** — `lib/domain/entities/core.dart`, `lib/data/local/app_database.dart`, `lib/presentation/fhw/household_screen.dart`
- **Proved by** — `test/hardening_test.dart`

### `break-glass`

In place — owned by this software

- **Failure prevented** — A refusal that cannot be overridden is a refusal that gets worked around with somebody else's login — and in a convulsing child, the answer must not be a argument.
- **What the software does** — Care is never blocked by a record. Where the policy would refuse, the screen asks for a reason in words, grants it for the length of the sitting, and files the reason as the basis. Refusals are recorded too, so the trail shows the attempt as well as the access.
- **Cited against** — HIPAA 45 CFR 164.312(b); GDPR Art 32(p)
- **In** — `lib/data/repositories/record_access.dart`
- **Proved by** — `test/hardening_test.dart`
- **Does not cover** — A reason is a deterrent and a record, not a verification. Nothing here can prove a stated reason was true; the supervision queue is where a human decides whether it looked plausible.

### `tamper-evident-trail`

In place — owned by this software

- **Failure prevented** — An audit log that the account it describes can edit is a story told afterwards by the person with the least to lose.
- **What the software does** — Each entry carries the hash of the one before it, keyed with an HMAC secret held in secure storage and never transmitted. The DAOs expose no update and no delete, and the trail is never cascaded from a patient row.
- **Cited against** — HIPAA 45 CFR 164.312(c)(1) integrity; HIPAA 45 CFR 164.308(a)(1)(ii)(D) system activity review
- **In** — `lib/domain/compliance.dart`, `lib/data/local/compliance_dao.dart`
- **Proved by** — `test/accountability_test.dart`
- **Does not cover** — Verification of a chain an adversary controlled end to end is not possible from the device alone — which is what the anchors are for.

### `chain-anchoring`

In place, with a stated limit — owned by this software

- **Failure prevented** — A device that rewrites its own history can also re-sign it, and the forgery is invisible from inside the chain.
- **What the software does** — Every tenth entry, the device commits its chain position to the district. The rows are append-only by database trigger, so the server cannot be talked into changing them, and a comparison finds an entry whose hash no longer matches or a history that got shorter.
- **Cited against** — HIPAA 45 CFR 164.312(c)(1); GDPR Art 5(2) accountability
- **In** — `lib/data/local/compliance_dao.dart`, `server/src/anchors.js`, `server/migrations/009_hardening.sql`
- **Does not cover** — The device sends its own anchors, so an anchor defeats rewriting history after it was admitted and does not defeat a device that lied from the first entry. Recorded in the migration and said on the desk.

### `read-audit-at-the-district`

In place — owned by this software

- **Failure prevented** — A device-side trail records what was read on that handset. It cannot see the day a caseload was downloaded, or a recovery that moved every row in a district onto a new phone.
- **What the software does** — The server writes what it handed out — scope, counts, watermark — into a table no client may write to, because a read log a device can edit is a read log that can be emptied.
- **Cited against** — HIPAA 45 CFR 164.312(b); GDPR Art 30
- **In** — `server/src/read_audit.js`, `server/src/pull.js`, `server/src/recovery.js`
- **Does not cover** — It records volumes and scope, not individual row ids: a pull page of five hundred records does not become five hundred log rows on a connectivity-limited server.

### `pattern-monitoring`

In place — owned by this software

- **Failure prevented** — One flagged read is a story about one worker. Forty flagged reads across forty unrelated families is a story about a habit, and no single entry in the trail shows it.
- **What the software does** — Two aggregate questions asked of the trail: who opened an unusual number of unrelated families in a day, and which protected record was opened by several workers. Reported as counts on the supervision desk, phrased as shapes worth a conversation rather than as accusations.
- **Cited against** — HIPAA 45 CFR 164.308(a)(1)(ii)(D); GDPR Art 5(2) accountability
- **In** — `lib/data/local/compliance_dao.dart`
- **Proved by** — `test/hardening_test.dart`
- **Does not cover** — Both detectors have ordinary explanations — a shared caseload, a campaign day, a family that moved. The count is the prompt; the decision belongs to the supervisor reading it.

### `right-to-erase`

In place, with a stated limit — owned by this software

- **Failure prevented** — A family asks for their record to be deleted, and the software has to answer with something other than a checkbox.
- **What the software does** — The request is honoured by erasing every direct identifier — name, phone, NHIS number — from the register, keeping the clinical history without names, writing the act itself into the access trail, and closing the request only when those have happened. A request that cannot be honoured throws a refusal that says what must happen first.
- **Cited against** — GDPR Art 17 erasure; Act 843 — correction and deletion
- **In** — `lib/data/repositories/care_repository.dart`
- **Proved by** — `test/hardening_test.dart`
- **Does not cover** — Statutory retention periods for health records are not this software to decide, so clinical rows are kept de-identified rather than destroyed, and the screen says so to the family in those words.

### `consent-as-history`

In place — owned by this software

- **Failure prevented** — If withdrawal overwrites the consent row, the record no longer shows that the care given in between was authorised — and the family looks like they were treated unlawfully.
- **What the software does** — A consent decision is its own append-only row: scope, decision, which version of the notice was read out, the language, and an optional voice artefact for a family who cannot read.
- **Cited against** — Act 843 s.26; GDPR Art 7
- **In** — `lib/domain/compliance.dart`, `lib/data/local/compliance_dao.dart`
- **Proved by** — `test/accountability_test.dart`

### `rights-with-a-deadline`

In place, with a stated limit — owned by this software

- **Failure prevented** — A request that reaches only the handset it was typed on is a request nobody is accountable for answering, and a lost phone is a lost obligation.
- **What the software does** — The request and its answer are queued out of the device in the same transaction that records them, the desk counts the days against the same constant the notice promised, and an overdue item is marked late in words as well as in colour.
- **Cited against** — Act 843 — data subject rights; GDPR Art 12(3)
- **In** — `lib/data/local/compliance_dao.dart`, `server/migrations/008_data_rights_requests.sql`
- **Proved by** — `test/accountability_test.dart`
- **Does not cover** — There is no supervisory role in this build, so the queue a worker sees is this device's, not the district's. The desk states that limit on screen rather than implying coverage it does not have.

### `sync-whitelist`

In place — owned by this software

- **Failure prevented** — A client names the table and columns it wants written. Trusting that is an invitation for a compromised handset to rewrite the audit log or add a column to a health record.
- **What the software does** — Every writable table and column is declared in one file and anything not on the list is rejected, with identifiers backtick-quoted and values parameterised. A malicious client can write only what the app itself writes.
- **Cited against** — OWASP MASVS-PLATFORM; HIPAA 45 CFR 164.312(c)(1)
- **In** — `server/src/tables.js`, `server/src/db.js`, `server/src/sync.js`
- **Proved by** — `test/sync_no_server_test.dart`

### `minimisation-at-the-edge`

In place — owned by this software

- **Failure prevented** — Syncing everything to everybody means a family's HIV status exists on every handset in the region, each one a copy that can be lost.
- **What the software does** — Push and pull are separate lists. The consent record, the access trail, the anchors and the rights queue go to the district and never come back down onto another handset; the server's own logs are not on the whitelist at all. The register reconciles these lists against the code in CI, so an undocumented widening of the pull stream fails the build.
- **Cited against** — GDPR Art 5(1)(c) minimisation; Act 843 s.26
- **In** — `server/src/pull.js`, `server/src/tables.js`
- **Proved by** — `test/governance_test.dart`, `test/pull_service_test.dart`

### `no-telemetry`

In place — owned by this software

- **Failure prevented** — Analytics is how a health app quietly becomes a data broker: a crash report carrying a mother's name, an event stream describing which families have epilepsy.
- **What the software does** — No analytics, crash-reporting or advertising dependency is permitted in the manifest, and CI fails if one appears. The only outbound traffic is to the district the account is configured for.
- **Cited against** — GDPR Art 25; OWASP MASVS-PRIVACY
- **In** — `pubspec.yaml`, `lib/data/sync/transport_policy.dart`
- **Proved by** — `test/governance_test.dart`

### `posture-said-out-loud`

In place — owned by this software

- **Failure prevented** — The most common compliance failure in software is a shield icon that claims encryption the build does not have.
- **What the software does** — The security posture is computed at runtime from the engine that actually opened the file, and printed on the profile tab and the supervision desk with its reason. There is no constant in the app that says "secure".
- **Cited against** — GDPR Art 30; OWASP MASVS-STORAGE-1
- **In** — `lib/data/local/app_database.dart`, `lib/presentation/fhw/profile_tab.dart`
- **Proved by** — `test/encryption_posture_test.dart`, `test/hardening_test.dart`

### `research-export-minimisation`

In place — owned by this software

- **Failure prevented** — An app that improves its models needs real data, and the fastest route is an export of the records. That route turns a health worker into a data collector without a receipt.
- **What the software does** — The export carries no direct identifier at all — a salted SHA-256 for linkage, district instead of community, month instead of date, age band instead of birthday, and only the numeric inputs the model consumed. The device is armed with a salt GHS issues and never ships with the app, an unarmed device collects nothing, and the batch leaves the handset only by a handover the worker performs and can see the count of.
- **Cited against** — GDPR Art 5(1)(e) pseudonymisation; GDPR Art 89 (research processing); Act 843 s.37
- **In** — `lib/core/ml/recalibration_export.dart`, `lib/core/ml/recalibration_store.dart`
- **Proved by** — `test/recalibration_export_test.dart`, `test/recalibration_store_test.dart`
- **Does not cover** — Linkage is the residual risk: whoever holds the salt can join two batches of the same child. The salt stays with GHS, which is why the app cannot do that join and why revoking it stops collection immediately.

### `cascade-safe-parent-writes`

In place — owned by this software

- **Failure prevented** — A record can be destroyed by an edit. `INSERT OR REPLACE` deletes the conflicting row before re-inserting it, and the register turns foreign keys on deliberately, so that implicit delete cascades: correcting a household's name would delete its members, and with them the growth curves, the assessments and the referrals. No error was raised and nothing was written to the trail.
- **What the software does** — Every write of a row that other rows cascade from goes through upsertWithoutCascade — look for the row, update it, insert only if absent — so no deletion is on the path. CI reads the DDL for the cascade parents and fails if any of them is written with ConflictAlgorithm.replace again, on any table, in any file.
- **Cited against** — HIPAA 45 CFR 164.312(c)(1) integrity; Act 843 s.26 — accuracy of processed data; OWASP MASVS-RESILIENCE (a failure that cannot be seen cannot be fixed)
- **In** — `lib/data/local/upsert.dart`, `lib/data/local/household_dao.dart`, `lib/data/local/visit_dao.dart`, `lib/data/sync/recovery_service.dart`
- **Proved by** — `test/cascade_safety_test.dart`
- **Does not cover** — It protects against this specific mechanism. Deleting a row on purpose still cascades — which is correct, and is why the deletion paths name their deletes.

### `retention-periods`

Not this software’s to implement — owned by the deploying health authority

- **Failure prevented** — Someone must decide how long a maternal record is kept, and when it stops being needed.
- **What the software does** — Not this software. Ghana Health Service records policy sets it, the district data protection supervisor applies it, and this build's job is to make the row findable and erasable when they do.
- **Cited against** — Act 843 s.26; GDPR Art 5(1)(e)
- **In** — `lib/domain/governance.dart`

### `controller-registration`

Not this software’s to implement — owned by the deploying health authority

- **Failure prevented** — Processing personal data without registering with the Data Protection Commission is an offence in itself, whatever the software does.
- **What the software does** — A filing the District Directorate makes as data controller, with this register as the input it has to describe. The Secretariat's enforcement is outside this repository.
- **Cited against** — Act 843 s.24 (registration of data controllers)
- **In** — `lib/domain/governance.dart`

### `breach-notification`

Not this software’s to implement — owned by the deployment, with the software providing the evidence

- **Failure prevented** — A lost handset is a reportable event, and the clock starts when it is noticed, not when it is investigated.
- **What the software does** — A process, not a feature. What the software contributes is the trail and the anchors, so the report can say which records that device had opened rather than guess.
- **Cited against** — Act 843 — disclosure; GDPR Art 33
- **In** — `lib/data/local/compliance_dao.dart`

### `impact-assessment`

Not this software’s to implement — owned by the deploying health authority

- **Failure prevented** — Processing special personal data at scale is exactly the case in which a data protection impact assessment is required before the deployment, not after the pilot.
- **What the software does** — Owned by the controller. This register, the matrix and the control map are written to be the evidence base an assessment cites, which is why the boundaries are recorded rather than smoothed over.
- **Cited against** — GDPR Art 35
- **In** — `lib/domain/governance.dart`

## 5. What this register does not claim

It does not say the deployment is compliant. Compliance is a state a data controller achieves with an organisation around the software: registering with the Commission, setting retention periods, training the workers who hold the handsets, reporting a breach. Those rows appear above with an owner and the words "not this software's to implement", because quietly dropping them is the one edit that would make this document false.

31 tables are registered, of which 20 may leave a handset and 6 are handed to another one. Those two numbers are the whole minimisation argument, and they are computed rather than asserted.

