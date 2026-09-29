# Caregiver action chain — the request that leaves the device

Date: 2026-09-28
Status: approved in chat; caregiver half in scope, FHW half specified only
Owner decision: a request to come, no symptom detail; assigned CHO with end-of-day
escalation; build the caregiver half now.

## The problem

The caregiver realism audit scored the flow 54% field-realistic and put the heaviest
gap here: an urgent home check produces an outcome on the screen and nothing anywhere
else. The family is told "go to the health facility now" and, in the field, often
cannot go today — no transport, no money, someone else holding the baby. The app
knows the child is in danger and knows which health worker owns the household, and it
passes neither fact to anyone.

This is not a copy or layout problem. Nothing can be fixed on the result page because
there is no record for a health worker to receive.

## What already exists, verified in this pass

- `Permission._caregiver` (enums.dart:61) holds `viewOwnFamilyOnly`,
  `runCaregiverTriage`, `recordBarrier`, `manageOwnFamily`. No caregiver writes
  anything clinical or anything that summons a worker.
- `Referral` (visit.dart:683) requires a non-null `assessmentId` and issues a
  facility-facing `referenceCode`. A home check has no assessment, so a caregiver
  cannot honestly produce a referral. Rejected.
- `ScheduledContact` (visit.dart:1000) means "a health worker committed to come". It
  carries `assessmentId` and `referralId`. Reusing it for a family-authored ask would
  erase the difference between a promise and a request. Rejected.
- `home_checks` exists locally (app_database.dart:387) and has **no** counterpart in
  `server/schema.sql` or `server/src/tables.js`. The check staying on the device is a
  deliberate privacy decision, recorded at care_repository.dart:888.
- **The pull path is six tables wide, at both ends.** `server/src/pull.js`
  `PULL_TABLES` and `lib/data/sync/pull_service.dart` (lines 359 and 391) both carry
  only households, persons, visits, assessments, referrals and users.
  `barrier_reports` and `scheduled_contacts` are push-only: a caregiver's barrier
  report reaches the server and is never delivered to a worker's device. This design
  must not repeat that, and the finding is recorded as separate work.
- A table missing from `tables.js` is not a silent gap: `sync.js` answers 400
  `Unknown entity_table`, the client classifies 4xx as permanent `SendRejected`, and
  the entry "never retries and never lands" (comment at tables.js:207). Registering
  the table is part of the feature, not follow-up.
- `SyncPriority.critical = 0` is documented as "someone may die today". That is what
  an urgent request is.
- Item A of the previous pass made a recorded arrival discharge the family's Today
  focus, using `referrals` — which *is* pulled, so that mechanism works.

## Decision: what leaves the device

A new record, `CareRequest`.

| field | meaning |
|---|---|
| `id` | uuid |
| `household_id` | routing and scope |
| `person_id` | who the family is worried about |
| `level` | `urgent` or `today`, from the check's verdict |
| `home_check_id` | opaque uuid; lets a worker say "about your check this morning" |
| `created_by` | the caregiver account |
| `created_at` | device time |
| `status` | `open` or `answered` |
| `answered_at` | set when a worker answers |

Never in the payload, and enforced by a test: the question answers, the sign names,
the MUAC reading, the tape band, the arm-tape note, the free-text context answers.

`home_checks` remains device-only. The privacy boundary moves from a comment to the
schema: there is no server table to put answers in.

Why an opaque `home_check_id` is acceptable when the answers are not: it identifies a
row on the family's own device that the server cannot read. It grants no clinical
content. It exists so a worker can ask the family to show the check in person, which
is how the audit said this data should travel.

## The pull path is the feature

`care_requests` is registered on both ends, or the request dies in a database nobody
opens:

1. `server/schema.sql` plus `server/migrations/004_care_requests.sql`.
2. `TABLES` in `server/src/tables.js` — the push whitelist.
3. `PULL_TABLES` in `server/src/pull.js`, with a `tableFilter` case keyed on
   `household_id` in the same shape as `persons` and `visits`.
4. The client merge lists in `pull_service.dart` (both the apply loop and the
   table-name list).

Scope rules are inherited unchanged and are not renegotiated here: a caregiver pulls
rows for the household bound to its account; a worker pulls rows for households in its
`(region, district, community)` tuple or that it created. The client's querystring is
never trusted for scope.

A consequence worth naming: because the family's device pulls its own household's
rows, the read-back of `status = answered` needs no new channel. It arrives on the
next pull.

## Caregiver-side behaviour

Shown on the result stage for `CaregiverCheckDecision.urgent` and
`.contactToday` — the two verdicts whose own advice says to reach a health worker
today, and which currently offer no way to do it. Not shown for `routine`: a request
that means "come because I am worried" stops meaning anything if it is also a
scheduling convenience.

The control is primary and does exactly what its label promises: write the request,
enqueued in the same transaction, then become a state rather than a repeatable tap.
One request per open check; a second tap on the same check does not create a second
row.

Three states, and none of them may over-promise:

- **Sending** — the row is written locally, the outbox entry is queued.
- **Waiting for signal** — the row has not left the device. The copy carries
  "go to the health facility now; this button is not a call-out and will not bring
  anyone today". In Gushegu a signal window may not open for hours, and a family that
  believes help is coming on the strength of a queued row is worse off than one that
  walked.
- **Reached your health worker** — only on server acknowledgement of the row.

The "go now" advice stays on screen above the control in every state. This design
adds a route to ask for help; it does not under any circumstance become a reason to
wait.

An unsent request can be withdrawn by the family. A sent one is answered by a person,
not un-sent by a button — the worker may already be travelling.

## Permission

New `Permission.requestCare`, granted to the caregiver set only.

Deliberately narrower than `runCaregiverTriage`: running a check must not imply the
authority to summon a worker. Enforced in `CareRepository` with `_require(...)` plus
`_requireHouseholdScope(...)`, which must be passed the account's own bound household
— the pattern item C made honest, where `AccessDenied` now propagates instead of
surfacing as a storage failure.

## Out of scope for this pass (specified, not built)

- The day-plan card on the CHO's device.
- End-of-day escalation to the supervisor's zone list, following the
  `Referral.escalatedAt` pattern.
- The worker's answer action.

Until those exist, `status` stays `open` and family-facing copy must not imply that a
response is coming. `answered` is a schema commitment now so the deferred half does
not need a second migration.

## Testing

Written first, failing, in this order:

1. Policy — which verdicts raise a request; `routine` never does.
2. Payload — a test that fails if `answers`, sign names or the MUAC value appear in
   the serialized request. This is the privacy guarantee, so it is a test and not a
   comment.
3. DAO atomicity — kill the transaction and neither the row nor its outbox entry
   survives; a committed one is ordered at `SyncPriority.critical`.
4. Repository gate — the right household passes, another household raises
   `AccessDenied`, and a role without `requestCare` raises `AccessDenied`.
5. Idempotency — a second confirm on the same check does not create a second row.
6. Widget — the three states render, and the waiting state carries the go-now line.
7. Offline — a full run with no transport: the check completes, the request is
   written, nothing pretends to have been sent.

`flutter analyze --no-pub` must hold its 0-error baseline; the full suite is expected
to keep the concurrent session's 4 known `pre_referral_dispensing_test.dart`
failures, which are not mine to fix.

## Collision note

The other session in this worktree wrote `home_tab.dart`, `care_repository.dart`,
`follow_up_check_in_screen.dart`, `follow_up_policy.dart` and
`nurturing_care_engine.dart` at 10:22 on 2026-09-28. `care_repository.dart` is on this
feature's path and `003_follow_up_contacts.sql` is theirs, so this spec takes
`004`. Their `follow_up_contacts` whitelist comment says `visit_dao.dart` enqueues
one row per check-in: if that work is still moving, the migration number and the
repository hunk are the two places this could collide.
