# Caregiver Action Chain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a caregiver whose home check came back urgent or contact-today send one thing — a request for a health worker to come — so the verdict produces an action outside the device.

**Architecture:** A new `care_requests` record, written by the family's device and pushed at critical sync priority, is the only caregiver-authored clinical signal that leaves it. `home_checks` stays device-only with no server counterpart, so the privacy boundary is structural. The row is registered on the delta-pull stream at both ends under last-write-wins, which is what lets a worker's answer travel back to the family.

**Tech Stack:** Flutter/Dart, sqflite, flutter_riverpod, Node.js + MySQL server (`server/src/`).

**Spec:** `docs/superpowers/specs/2026-09-28-caregiver-action-chain-design.md`

## Global Constraints

- **AI honesty contract:** no fabricated clinical attribution, confidence interval, or effect size anywhere in copy or comments.
- **Family-facing copy promises nothing the app cannot guarantee.** `Waiting for signal` says so plainly (nobody has been told, this is not a call-out); `Sent to your health worker` appears only when the outbox entry has a `synced_at`; `Your health worker answered` only on a pulled `answered` status. The verdict's own instruction line stays on screen in every state that has a request.
- **Caregiver surfaces use cool navy ink** (`caregiverBody()` / `CompanionColors.ink`), Aura Nurture pearl identity. No warm teal.
- **The bundled Sora font is weight-limited.** Do not request a weight that is not in the bundle.
- **Never stage** `assets/tts/hausa_piper/model.onnx`, `assets/tts/twi_piper/model.onnx`, `.tmp_dl/`, or `.qoder/settings.local.json`.
- **No commits or pushes unless the owner explicitly asks** (owner rule, overrides this skill's commit steps). Where a step says *checkpoint*, mark the task done instead of committing.
- **Do not edit** `lib/core/audio/caregiver_playback.dart`, `lib/presentation/shared/recommendation_kit.dart`, `lib/presentation/assessment/result_screen.dart` — a concurrent session owns them.
- **Concurrent session hazard:** `lib/domain/enums.dart`, `lib/data/repositories/care_repository.dart`, `lib/presentation/fhw/home_tab.dart`, `lib/domain/services/follow_up_policy.dart` were all written by another session at 10:22 on 2026-09-28. Edits there must be additive and confined to the hunks named in this plan. `server/migrations/003_follow_up_contacts.sql` is theirs; this plan takes `004`.
- Verify with `flutter analyze --no-pub` from the repo root; a green `flutter build web` does not prove the analyzer is clean.
- Known baseline: 4 failing tests in `test/pre_referral_dispensing_test.dart` belong to the concurrent session. They are not this plan's to fix.

---

## Design amendment (from Task 0's evidence, applied before any task)

The spec says the `answered` read-back "needs no new channel". Reading `lib/data/sync/pull_service.dart:455-470` shows why that is only half true:

`_mergeIfAbsent` — the rule for visits, assessments and referrals — **never updates a row that already exists locally**. A status a worker changes on their device therefore cannot reach the family's copy of an insert-if-absent table. `care_requests` will be updated by a worker, so it must ride `_mergeLww` (households, persons), which compares `updated_at`. That requires one more column:

- `updated_at TEXT NOT NULL` on `care_requests`, local and server. Bumped whenever `status` changes.

Two consequences recorded in the spec file as an amendment, and not fixed here because they are outside this plan's scope:
1. `referrals` is insert-if-absent, so a referral the clinic marks `arrived` stays `open` on the family's device forever, and `caregiver_today_planner.dart:111` (`if (!referral.status.isOpen) continue;`) keeps nagging about a closed referral. Separate defect, separate plan.
2. `_mergeLww` does not normalise `sync_state` on the pulled row (unlike `_mergeIfAbsent:491`). This plan will not change a shared helper; it normalises inside its own table's loop and proves it with a test.

**Second amendment — the third state's words.** The spec names the acknowledged state "Reached your health worker". `outbox.synced_at` proves the server accepted the row; it does not prove anyone read it, and a supervisor's inbox at district level is not a person with a motorbike. The card therefore says **`Sent to your health worker`** for a pushed row, and reserves `Your health worker answered` for the pulled `answered` status — which until the desk exists (out of scope) nothing can set. If a later pass renames these, change the strings in `test/widgets/care_request_card_test.dart` first, not the card.

## Verified against the tree (Task 0 evidence — do not re-guess these)

Every signature below was read, not assumed. An earlier draft of this plan guessed ten of them wrong; these are the corrections.

| Thing | Reality |
| --- | --- |
| `HomeCheck` | `lib/domain/entities/visit.dart:1089`. ctor `{id, householdId, personId, clientType, verdict, yesSigns, unsureSigns, checkedBy, checkedAt}` — matches the tests below. Import it from `visit.dart`, **not** `caregiver.dart`. |
| `CaregiverScope` | `lib/domain/entities/caregiver.dart:27`, `const CaregiverScope({required userId, required householdId})`. There is no `.of(user)`. |
| `CaregiverDataException` | `lib/domain/entities/caregiver.dart`. |
| `SyncState` | `lib/domain/enums.dart:508` — `pending, uploading, synced, failed, conflict`. Already in `enums.dart`; no `core.dart` import needed. |
| `HomeCheckVerdict` | `lib/domain/enums.dart:252` — `urgent('Go to the health facility now')`, `caution('Visit the CHW soon')`, `fine(...)`. The `urgent` label **is** the go-now sentence; reuse it rather than typing a second near-miss. |
| `CaregiverCheckDecision` | `lib/domain/services/caregiver_check_policy.dart:86` — `urgent, contactToday, routine, incomplete, unsupported`. The *policy* speaks this; only the stored `HomeCheck` speaks `HomeCheckVerdict`. Gate on the stored verdict. |
| `OutboxDao.enqueue` | `lib/data/local/outbox_dao.dart:164` — `enqueue(DatabaseExecutor txn, {required table, required entityId, required operation, required payload, int priority = routine})`. As planned. |
| `OutboxDao.pending` | `:187` — `pending({int limit = 25})`, reads the **singleton**, no `txn:` parameter. Tests assert on the outbox by querying the table directly: `db.query(Tables.outbox, where: 'entity_table = ?', whereArgs: [...])`. |
| Migration seam | `AppDatabase.upgradeForTesting(db, from)` **already exists** at `app_database.dart:359`. Do not add a helper. `test/follow_up_schema_v8_test.dart:118-135` is the pattern: `openInMemory()` → `DROP TABLE` the new table → `upgradeForTesting(db, 8)`. |
| The DAO-test harness | DAOs read `AppDatabase.instance.database`, so a test that only calls `AppDatabase.openInMemory()` gets a *different* database. Any test that exercises a DAO read path must mock `plugins.flutter.io/path_provider` and take `AppDatabase.instance.database` — copy `test/caregiver_state_test.dart:98-108`. |
| Pull test harness | `test/pull_service_test.dart` drives the real service through `PlatformHttpClient.override` + `_page(data: {...})` + `_asServerRow(...)`. **There is no `applyPageForTests` and none will be added** — a seam that skips the transport tests code the field never runs. |
| Controller | `CaregiverCheckController extends ChangeNotifier` (`check_controller.dart:27`), constructor-injected with `repository`, `user`, `scope`, `person`. The saved check is `HomeCheck? report;` (`:47`), not `savedCheck`. State is emitted by `_notify()` (`:107`) and serialised by `_persist()`'s `_tail` chain, surfaced as `Future<void> get settled` (`:499`). **No Riverpod inside, no provider needed.** |
| Result-stage variables | `triage_screen.dart:908 _result(CaregiverCheckController check)`; `urgent`/`routine` are `check.decision` comparisons (`:909-910`). The card block to sit beside runs `:1119-1145` on `check.report != null`. |
| Card style | `CompanionCard({required title, required child, eyebrow, tone})` at `widgets/companion.dart:41`, and `caregiverBody({Color? color, double? size, double? height})` at `:34`. **Neither takes a `BuildContext`** — there is no `caregiverBody(context).titleMedium`. `_TapeReadingNoteCard` (`triage_screen.dart:3681`) is the shape to copy. |
| Push does not touch the row | `OutboxDao.markSynced` (`outbox_dao.dart:201`) sets `outbox.synced_at` and **nothing on the entity table**; only a pull writes `sync_state = 'synced'` (`pull_service.dart:493`). So `care_requests.sync_state` stays `'pending'` on the family's device even after a successful upload, and "has my request left the phone?" must be answered from the outbox — that is `CareRequestDao.isSent`, and it is why `withdrawIn` refuses on the same test. |
| Controller lifetime | `CaregiverCheckController` is built per screen instance at `triage_screen.dart:87`; no provider keeps it alive. The result stage, and with it the request card, exists only for the session that finalised the check — which is why `refreshRequest()` re-reads storage instead of trusting the object held from the tap. |
| Answer → verdict | `decide()` (`caregiver_check_policy.dart:388-405`): any YES ⇒ `urgent`, one `unsure` with the rest answered ⇒ `contactToday`, all NO ⇒ `routine`; `care_repository.dart:1194-1196` maps those to `urgent`/`caution`/`fine`. Test recipes already in the file: a YES plus `stopForVerdict()` for urgent (`:297-313`), the all-answered loop plus `setDuration('today')` and `finishContext()` for caution and fine (`:245-277`). |
| Where `notice` renders | `_NoticeBanner(message: check.notice!)` appears only on the questions stage (`triage_screen.dart:738-739`), so a failed ask would be invisible from the result screen. The request states therefore carry their own `requestError`, shown by the card. |
| Primary button | `PremiumCheckButton({required label, required onPressed, icon, trailingIcon, height = 60, enabled = true, bright = false})` at `widgets/premium_button.dart:25`. `find.widgetWithText(PremiumCheckButton, label)` matches it in tests. |
| Seed parents have **no** `sync_state` | `households` (`app_database.dart:432`) and `persons` (`:461`) carry `created_at`/`updated_at` only — no `sync_state`, unlike `referrals` and the caregiver tables. A test seed that writes `'sync_state': 'synced'` into either fails with *table has no column named sync_state*. Required NOT NULL columns: households `id, name, region, district, community, created_by, created_at, updated_at`; persons `id, household_id, full_name, client_type, created_at, updated_at`. |
| A pullable table is three things, not one | Every table on the pull stream carries a server-managed `pull_updated_at VARCHAR(40) NULL` + `KEY idx_*_pull (pull_updated_at)` + the `BEFORE INSERT`/`BEFORE UPDATE` triggers that stamp it (`server/schema.sql:619-642`, created for the five clinical tables by `migrations/002_delta_pull.sql`). `pull.js` selects `WHERE pull_updated_at > since ORDER BY pull_updated_at`, so registering a table in `PULL_TABLES` **without** the column and triggers is a 500 on every pull, for every user, not just on rows of that table. It is also absent from the `tables.js` whitelist — the triggers own it, and a client that could set it could set its own watermark. |

---

### Task 1: The `CareRequest` record and the privacy guarantee

**Files:**
- Create: `lib/domain/entities/care_request.dart`
- Modify: `lib/domain/enums.dart` (append two enums after `ReferralStatus`, ~line 360; add one permission at line 44)
- Test: `test/care_request_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum CareRequestLevel { urgent, today }` with `String get wireValue` and `static CareRequestLevel? fromWire(String)`; `enum CareRequestStatus { open, answered }` with the same two members; `class CareRequest` with `id, householdId, personId, level, homeCheckId, createdBy, createdAt, updatedAt, status, answeredAt, syncState` and `Map<String, Object?> toMap()` / `factory CareRequest.fromMap(Map<String, Object?>)`; `CareRequest.fromCheck({required HomeCheck check, required String userId, required DateTime at})`.

- [x] **Step 1: Write the failing test**

Create `test/care_request_test.dart`. The second test is the one that matters: it is the privacy boundary, expressed as an assertion rather than a comment.

```dart
/// The family's request for help.
///
/// The payload test in this file is the privacy guarantee. `home_checks` has no
/// server counterpart on purpose (see the spec), and `care_requests` is the one
/// table allowed to carry a hint that a check happened. If a future change adds
/// a sign name, an answer or a MUAC reading to the serialized row, this file
/// fails before the code can ship a family's symptom list to a database they
/// never agreed to write to.
library;

import 'package:carebridge_ai/domain/entities/care_request.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

HomeCheck _check({HomeCheckVerdict verdict = HomeCheckVerdict.urgent}) => HomeCheck(
  id: 'chk-1',
  householdId: 'hh-1',
  personId: 'p-1',
  clientType: ClientType.childUnderFive,
  verdict: verdict,
  yesSigns: const ['Fits (convulsions)'],
  unsureSigns: const [],
  checkedBy: 'u-mother',
  checkedAt: DateTime(2026, 9, 28, 8, 42),
);

void main() {
  group('CareRequest', () {
    test('survives a map round trip', () {
      final request = CareRequest.fromCheck(
        check: _check(),
        userId: 'u-mother',
        at: DateTime(2026, 9, 28, 9, 5),
      );
      final back = CareRequest.fromMap(request.toMap());
      expect(back.id, request.id);
      expect(back.householdId, 'hh-1');
      expect(back.personId, 'p-1');
      expect(back.level, CareRequestLevel.urgent);
      expect(back.homeCheckId, 'chk-1');
      expect(back.status, CareRequestStatus.open);
      expect(back.answeredAt, isNull);
    });

    test('the payload carries no clinical content', () {
      final map = CareRequest.fromCheck(
        check: _check(),
        userId: 'u-mother',
        at: DateTime(2026, 9, 28, 9, 5),
      ).toMap();

      expect(
        map.keys.toSet(),
        {
          'id',
          'household_id',
          'person_id',
          'level',
          'home_check_id',
          'created_by',
          'created_at',
          'updated_at',
          'status',
          'answered_at',
          'sync_state',
        },
      );
      // Nothing in the row can be a sign name or a measurement.
      expect(map.values.whereType<String>().join(' '), isNot(contains('Fits')));
      expect(map.values.whereType<String>().join(' '), isNot(contains('convulsion')));
    });

    test('a caution verdict asks for a visit today, not an emergency', () {
      final request = CareRequest.fromCheck(
        check: _check(verdict: HomeCheckVerdict.caution),
        userId: 'u-mother',
        at: DateTime(2026, 9, 28, 9, 5),
      );
      expect(request.level, CareRequestLevel.today);
    });

    test('a fine verdict raises nothing', () {
      expect(
        CareRequest.levelFor(HomeCheckVerdict.fine),
        isNull,
      );
    });
  });
}
```

- [x] **Step 2: Run it and watch it fail for the right reason**

Run: `flutter test --no-pub --reporter compact test/care_request_test.dart 2>&1 | tr '\r' '\n' | tail -20`
Expected: `Target of URI doesn't exist: 'package:carebridge_ai/domain/entities/care_request.dart'`. If instead it fails on a missing named argument to `HomeCheck`, stop — `visit.dart` has changed under this plan; read `lib/domain/entities/visit.dart:1089` and match its real parameters rather than changing the entity.

- [x] **Step 3: Add the two enums**

In `lib/domain/enums.dart`, append after the `ReferralStatus` enum. Follow the wire-value pattern `ReferralStatus` already uses, so a stored string is stable across app versions:

```dart
/// What the family is asking for. `urgent` is "come today, this may kill them";
/// `today` is the check's contact-today verdict. There is deliberately no
/// `routine` — a request that means "I am worried" stops meaning anything if a
/// family can also file it as a scheduling convenience.
enum CareRequestLevel {
  urgent('urgent', 'Come today'),
  today('today', 'Come when you can today');

  const CareRequestLevel(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static CareRequestLevel? fromWire(String raw) {
    for (final value in CareRequestLevel.values) {
      if (value.wireValue == raw) return value;
    }
    return null;
  }
}

/// A request is answered by a person, never by a timer. `answered` is written on
/// the worker's device and reaches the family through the delta pull.
enum CareRequestStatus {
  open('open'),
  answered('answered');

  const CareRequestStatus(this.wireValue);
  final String wireValue;

  bool get isOpen => this == CareRequestStatus.open;

  static CareRequestStatus fromWire(String raw) =>
      CareRequestStatus.values.firstWhere(
        (value) => value.wireValue == raw,
        orElse: () => CareRequestStatus.open,
      );
}
```

- [x] **Step 4: Write the entity**

Create `lib/domain/entities/care_request.dart`:

```dart
/// The one record a family chooses to send.
///
/// A home check is a clinical report and stays on the device. This is not a
/// clinical report: it says who the family is worried about, how urgent the
/// check judged it, and that they asked. `homeCheckId` is an opaque identifier
/// for a row the server cannot read — it exists so a health worker can ask the
/// family to show the check in person, which is how the audit said symptom
/// detail should travel.
library;

import '../enums.dart';
import 'visit.dart';

class CareRequest {
  const CareRequest({
    required this.id,
    required this.householdId,
    required this.personId,
    required this.level,
    required this.homeCheckId,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.status = CareRequestStatus.open,
    this.answeredAt,
    this.syncState = SyncState.pending,
  });

  /// The request a completed check raises, or null when the verdict asks for
  /// nothing. One request per check, keyed on its id: `HomeCheck.id` is the
  /// draft id, which the result screen already holds, so a family tapping twice
  /// cannot create two rows.
  static CareRequest? fromCheck({
    required HomeCheck check,
    required String userId,
    required DateTime at,
  }) {
    final level = levelFor(check.verdict);
    if (level == null) return null;
    return CareRequest(
      id: 'req-${check.id}',
      householdId: check.householdId,
      personId: check.personId,
      level: level,
      homeCheckId: check.id,
      createdBy: userId,
      createdAt: at,
      updatedAt: at,
    );
  }

  static CareRequestLevel? levelFor(HomeCheckVerdict verdict) =>
      switch (verdict) {
        HomeCheckVerdict.urgent => CareRequestLevel.urgent,
        HomeCheckVerdict.caution => CareRequestLevel.today,
        _ => null,
      };

  final String id;
  final String householdId;
  final String personId;
  final CareRequestLevel level;
  final String homeCheckId;
  final String createdBy;
  final DateTime createdAt;

  /// Bumped with every status change. The delta pull merges this table
  /// last-write-wins, which compares exactly this column, so a request without
  /// it could never carry a worker's answer home.
  final DateTime updatedAt;

  final CareRequestStatus status;
  final DateTime? answeredAt;
  final SyncState syncState;

  bool get isOpen => status == CareRequestStatus.open;

  Map<String, Object?> toMap() => {
    'id': id,
    'household_id': householdId,
    'person_id': personId,
    'level': level.wireValue,
    'home_check_id': homeCheckId,
    'created_by': createdBy,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'status': status.wireValue,
    'answered_at': answeredAt?.toIso8601String(),
    'sync_state': syncState.name,
  };

  factory CareRequest.fromMap(Map<String, Object?> map) => CareRequest(
    id: map['id'] as String,
    householdId: map['household_id'] as String,
    personId: map['person_id'] as String,
    level: CareRequestLevel.fromWire(map['level'] as String) ??
        CareRequestLevel.today,
    homeCheckId: map['home_check_id'] as String,
    createdBy: map['created_by'] as String,
    createdAt: DateTime.parse(map['created_at'] as String),
    updatedAt: DateTime.parse(map['updated_at'] as String),
    status: CareRequestStatus.fromWire(map['status'] as String? ?? 'open'),
    answeredAt: map['answered_at'] == null
        ? null
        : DateTime.parse(map['answered_at'] as String),
    syncState: SyncState.values.firstWhere(
      (value) => value.name == map['sync_state'],
      orElse: () => SyncState.pending,
    ),
  );
}
```

`SyncState` is at `lib/domain/enums.dart:508`, so the two imports above are the whole list. Note the entity never sees a sign, an answer or a measurement: `HomeCheck` exposes them, and `fromCheck` simply does not read them — which is why the payload test can be an assertion rather than a review comment.

- [x] **Step 5: Run the tests**

Run: `flutter test --no-pub --reporter compact test/care_request_test.dart 2>&1 | tr '\r' '\n' | tail -20`
Expected: `+4: All tests passed!`

- [x] **Step 6: Checkpoint**

Run `dart analyze lib/domain/entities/care_request.dart lib/domain/enums.dart test/care_request_test.dart`. No new errors. Do not commit.

---

### Task 2: Local table, schema v9, and the atomic outbox write

**Files:**
- Create: `lib/data/local/care_request_dao.dart`
- Modify: `lib/data/local/app_database.dart` (`Tables` ~line 387, `_schema` list ~line 832, `kDatabaseVersion` line 73, `_upgrade`, `clearAll` line 198)
- Test: `test/care_request_dao_test.dart`

**Interfaces:**
- Consumes: `CareRequest` (Task 1), `OutboxDao.enqueue`, `Tables.careRequests`.
- Produces: `abstract final class CareRequestDao { static Future<void> createIn(DatabaseExecutor db, CareRequest request); static Future<CareRequest?> byId(String id); static Future<CareRequest?> openForCheck(String homeCheckId); static Future<CareRequest?> forCheck(String homeCheckId); static Future<bool> isSent(String id); static Future<void> markAnsweredIn(DatabaseExecutor db, String id, DateTime at); static Future<bool> withdrawIn(DatabaseExecutor db, String id); }`

- [x] **Step 1: Write the failing test**

Create `test/care_request_dao_test.dart`. The rollback and withdrawal tests are the deliverables; the rest pins the critical priority, the answered transition, what "sent" means, and the migration.

```dart
/// The request row and its sync intent commit together or not at all.
///
/// This is the rule the whole repository obeys (see outbox_dao.dart's header),
/// and it matters most here: a family that pressed "Ask for help" and lost the
/// row to a half-write would believe help was on the way. The ordering test is
/// the other half — on ninety seconds of signal an urgent request must leave
/// before eighty routine registrations. And the withdrawal tests are the promise
/// that a queued request is not yet a call-out: what has not left the phone can
/// still be called back.
library;

import 'dart:io';

import 'package:carebridge_ai/data/local/app_database.dart';
import 'package:carebridge_ai/data/local/care_request_dao.dart';
import 'package:carebridge_ai/domain/entities/care_request.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

CareRequest _request({String id = 'req-chk-1'}) => CareRequest(
  id: id,
  householdId: 'family',
  personId: 'baby',
  level: CareRequestLevel.urgent,
  homeCheckId: 'chk-1',
  createdBy: 'caregiver',
  createdAt: DateTime(2026, 9, 28, 9, 5),
  updatedAt: DateTime(2026, 9, 28, 9, 5),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The DAOs read AppDatabase.instance.database, so the test must hold that
  // same handle. A second openInMemory() would be a different database and
  // every read below would come back null.
  late Database db;
  setUp(() async {
    final dir = Directory.systemTemp.createTempSync('carebridge_care_request');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? dir.path
              : null,
        );
    AppDatabase.initialiseForDesktopAndTests();
    db = await AppDatabase.instance.database;
    // care_requests has live foreign keys and the database turns them on, so
    // the parent rows are not optional here.
    await db.insert(
      Tables.households,
      const {
        'id': 'family',
        'name': 'Family',
        'region': 'Northern Region',
        'district': 'Karaga',
        'community': 'Karaga',
        'created_by': 'caregiver',
        'created_at': '2026-09-01T00:00:00.000',
        'updated_at': '2026-09-01T00:00:00.000',
      },
    );
    await db.insert(
      Tables.persons,
      const {
        'id': 'baby',
        'household_id': 'family',
        'full_name': 'Awah',
        'client_type': 'newborn',
        'date_of_birth': '2026-08-01T00:00:00.000',
        'created_at': '2026-09-01T00:00:00.000',
        'updated_at': '2026-09-01T00:00:00.000',
      },
    );
  });
  tearDown(() => AppDatabase.instance.close());

  Future<List<Map<String, Object?>>> queued(String id) => db.query(
    Tables.outbox,
    where: 'entity_table = ? AND entity_id = ?',
    whereArgs: ['care_requests', id],
  );

  group('CareRequestDao', () {
    test('creates the row and queues it at critical priority', () async {
      await db.transaction((txn) => CareRequestDao.createIn(txn, _request()));

      final stored = await CareRequestDao.byId('req-chk-1');
      expect(stored?.level, CareRequestLevel.urgent);

      final entry = (await queued('req-chk-1')).single;
      expect(entry['operation'], 'insert');
      expect(entry['priority'], 0); // SyncPriority.critical
      final payload = entry['payload_json'] as String;
      expect(payload, isNot(contains('fits')));
      expect(payload, isNot(contains('answers')));
    });

    test('a rolled back write leaves no row and no outbox entry', () async {
      await expectLater(
        db.transaction((txn) async {
          await CareRequestDao.createIn(txn, _request());
          throw StateError('the phone died mid-write');
        }),
        throwsStateError,
      );
      expect(await CareRequestDao.byId('req-chk-1'), isNull);
      expect(await queued('req-chk-1'), isEmpty);
    });

    test('an open request already raised for a check is found, not duplicated',
        () async {
      await CareRequestDao.createIn(db, _request());
      expect(await CareRequestDao.openForCheck('chk-1'), isNotNull);
    });

    test('an answered request is no longer open', () async {
      await CareRequestDao.createIn(db, _request());
      await CareRequestDao.markAnsweredIn(
        db,
        'req-chk-1',
        DateTime(2026, 9, 28, 14),
      );
      final stored = await CareRequestDao.byId('req-chk-1');
      expect(stored?.status, CareRequestStatus.answered);
      expect(stored?.isOpen, isFalse);
      expect(stored!.updatedAt.isAfter(stored.createdAt), isTrue);
      expect(await CareRequestDao.openForCheck('chk-1'), isNull);
      // The read the family's screen uses still finds it: the reply is the
      // thing they should see, and a second tap must land on this row instead
      // of replacing it.
      expect(await CareRequestDao.forCheck('chk-1'), isNotNull);
    });

    test('sent means the queue entry was pushed, not that time passed',
        () async {
      await CareRequestDao.createIn(db, _request());
      // The row's own sync_state is 'pending' here and stays so until a pull
      // re-offers it — push only ever touches outbox.synced_at. The card reads
      // this method, never the column, so it cannot claim a delivery the phone
      // has not seen.
      expect(await CareRequestDao.isSent('req-chk-1'), isFalse);
      await db.update(
        Tables.outbox,
        {'synced_at': '2026-09-28T09:10:00.000'},
        where: 'entity_id = ?',
        whereArgs: ['req-chk-1'],
      );
      expect(await CareRequestDao.isSent('req-chk-1'), isTrue);
    });

    test('withdrawing a request that has not left deletes the row and the '
        'queue entry together', () async {
      await CareRequestDao.createIn(db, _request());
      expect(
        await CareRequestDao.withdrawIn(db, 'req-chk-1'),
        isTrue,
      );
      expect(await CareRequestDao.byId('req-chk-1'), isNull);
      expect(await queued('req-chk-1'), isEmpty);
    });

    test('a withdrawn write that rolls back keeps both the row and the entry',
        () async {
      await CareRequestDao.createIn(db, _request());
      await expectLater(
        db.transaction((txn) async {
          await CareRequestDao.withdrawIn(txn, 'req-chk-1');
          throw StateError('interrupted');
        }),
        throwsStateError,
      );
      expect(await CareRequestDao.byId('req-chk-1'), isNotNull);
      expect(await queued('req-chk-1'), hasLength(1));
    });

    test('a request the server already has cannot be withdrawn locally',
        () async {
      await CareRequestDao.createIn(db, _request());
      await db.update(
        Tables.outbox,
        {'synced_at': '2026-09-28T09:10:00.000'},
        where: 'entity_id = ?',
        whereArgs: ['req-chk-1'],
      );
      expect(
        await CareRequestDao.withdrawIn(db, 'req-chk-1'),
        isFalse,
      );
      expect(await CareRequestDao.byId('req-chk-1'), isNotNull);
    });

    test('an answered request cannot be withdrawn — the reply is the record',
        () async {
      await CareRequestDao.createIn(db, _request());
      await CareRequestDao.markAnsweredIn(
        db,
        'req-chk-1',
        DateTime(2026, 9, 28, 14),
      );
      expect(
        await CareRequestDao.withdrawIn(db, 'req-chk-1'),
        isFalse,
      );
      final stored = await CareRequestDao.byId('req-chk-1');
      expect(stored?.status, CareRequestStatus.answered);
    });
  });

  test('a v8 database gains an empty care_requests table', () async {
    // openInMemory/createAll already built v9; take the new table away to
    // stand in for a v8 device, then run the real upgrade path. Same trick as
    // test/follow_up_schema_v8_test.dart's _downgradeToV7.
    await db.execute('DROP TABLE ${Tables.careRequests}');
    await AppDatabase.upgradeForTesting(db, 8);
    expect(
      await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        [Tables.careRequests],
      ),
      hasLength(1),
    );
    expect(await db.query(Tables.careRequests), isEmpty);
  });
}
```

The household and person rows are written as bare maps rather than through the entities on purpose: this file is about one table's contract, and pulling in `Household(...)`'s required fields would add a second reason for it to break. The two columns that matter are the ids the foreign keys point at.

- [x] **Step 2: Run it and watch it fail**

Run: `flutter test --no-pub --reporter compact test/care_request_dao_test.dart 2>&1 | tr '\r' '\n' | tail -20`
Expected: `Target of URI doesn't exist: '.../care_request_dao.dart'`.

- [x] **Step 3: Register the table**

In `lib/data/local/app_database.dart`:

```dart
// in Tables, after followUpContacts
static const careRequests = 'care_requests';
```

```dart
// after _followUpContactsTable
const String _careRequestsTable =
    '''
  CREATE TABLE IF NOT EXISTS ${Tables.careRequests} (
    id            TEXT PRIMARY KEY,
    household_id  TEXT NOT NULL,
    person_id     TEXT NOT NULL,
    level         TEXT NOT NULL,
    home_check_id TEXT NOT NULL,
    created_by    TEXT NOT NULL,
    created_at    TEXT NOT NULL,
    updated_at    TEXT NOT NULL,
    status        TEXT NOT NULL DEFAULT 'open',
    answered_at   TEXT,
    sync_state    TEXT NOT NULL DEFAULT 'pending',
    FOREIGN KEY (household_id) REFERENCES ${Tables.households}(id)
      ON DELETE CASCADE,
    FOREIGN KEY (person_id) REFERENCES ${Tables.persons}(id) ON DELETE CASCADE
  )
  ''';
```

Add `_careRequestsTable` and its two indexes to the `_schema` list, after the follow-up entries:

```dart
_careRequestsTable,
'CREATE INDEX idx_care_requests_household ON ${Tables.careRequests}'
'(household_id, created_at DESC)',
'CREATE INDEX idx_care_requests_check ON ${Tables.careRequests}(home_check_id)',
```

`home_checks` is intentionally **not** a foreign key here: the request must outlive the check row if a family ever clears local history, and a dangling id is an honest "the family's check is on their phone", not a lost request.

Bump `kDatabaseVersion` from `8` to `9` and append the upgrade block after `if (from < 8)`:

```dart
if (from < 9) {
  // Version 9: the family's request for help. Its own table rather than a row
  // in scheduled_contacts, because a family asking and a worker committing to
  // come are different facts and a supervisor reads them differently.
  await db.execute(_careRequestsTable);
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_care_requests_household ON '
    '${Tables.careRequests}(household_id, created_at DESC)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_care_requests_check ON '
    '${Tables.careRequests}(home_check_id)',
  );
}
```

Add `Tables.careRequests,` to the `clearAll` list, immediately before `Tables.scheduledContacts`.

- [x] **Step 4: Write the DAO**

Create `lib/data/local/care_request_dao.dart`:

```dart
/// The read and write path for a family's request for help.
///
/// Small on purpose. Only the family's device creates these rows, and in this
/// pass only the family's device reads them; the desk that answers them is
/// separate work (see the spec's out-of-scope list).
library;

import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'outbox_dao.dart';
import '../../domain/entities/care_request.dart';
import '../../domain/enums.dart';

abstract final class CareRequestDao {
  static Future<void> createIn(
    DatabaseExecutor db,
    CareRequest request,
  ) async {
    final map = request.toMap();
    await db.insert(
      Tables.careRequests,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Critical, not clinical: SyncPriority.critical is documented as "someone
    // may die today", and a queued urgent request is exactly that.
    await OutboxDao.enqueue(
      db,
      table: Tables.careRequests,
      entityId: request.id,
      operation: SyncOperation.insert,
      payload: map,
      priority: SyncPriority.critical,
    );
  }

  static Future<CareRequest?> byId(String id) async {
    final db = await AppDatabase.instance.database;
    return _first(await db.query(
      Tables.careRequests,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    ));
  }

  /// The open request this check already raised, if any. Keyed on the check id
  /// because `CareRequest.id` is derived from it, which is what makes a second
  /// tap a no-op rather than a second summons.
  static Future<CareRequest?> openForCheck(String homeCheckId) async {
    final db = await AppDatabase.instance.database;
    return _first(await db.query(
      Tables.careRequests,
      where: "home_check_id = ? AND status = 'open'",
      whereArgs: [homeCheckId],
      limit: 1,
    ));
  }

  /// The request this check raised, answered or not.
  ///
  /// `openForCheck` is the guard for "may I raise another"; this is the read for
  /// "what did we already agree". They differ exactly where it matters: once a
  /// worker replies, the family's screen must show the reply, and a second tap
  /// must find the row and leave it alone rather than replacing it with a fresh
  /// open request of the same deterministic id.
  static Future<CareRequest?> forCheck(String homeCheckId) async {
    final db = await AppDatabase.instance.database;
    return _first(await db.query(
      Tables.careRequests,
      where: 'home_check_id = ?',
      whereArgs: [homeCheckId],
      orderBy: 'created_at DESC',
      limit: 1,
    ));
  }

  /// Whether this request has reached the server.
  ///
  /// Reads the outbox, not the row: a successful push sets `outbox.synced_at`
  /// and never touches `care_requests.sync_state`, which only a pull re-offering
  /// the row would change. So the column would say "pending" forever to a family
  /// whose request landed hours ago, and the card would lie at them.
  static Future<bool> isSent(String id) async {
    final db = await AppDatabase.instance.database;
    return _hasLeft(db, id);
  }

  static Future<void> markAnsweredIn(
    DatabaseExecutor db,
    String id,
    DateTime at,
  ) async {
    await db.update(
      Tables.careRequests,
      {
        'status': CareRequestStatus.answered.wireValue,
        'answered_at': at.toIso8601String(),
        'updated_at': at.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Calls back a request that has not left the phone.
  ///
  /// Returns false, changing nothing, once the server has the row: deleting it
  /// locally would leave the health worker holding a summons the family's screen
  /// says was never sent. Before acknowledgement the family is entitled to their
  /// change of mind, and the row and its queue entry go in one transaction so a
  /// withdrawn request cannot linger as a half-truth.
  ///
  /// An answered request is also refused. By then it is not a request any more,
  /// it is the record that someone replied — and deleting it would throw away
  /// the only answer the family ever got.
  static Future<bool> withdrawIn(
    DatabaseExecutor db,
    String id,
  ) async {
    final existing = await db.query(
      Tables.careRequests,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (existing.isEmpty) return false;
    if (!CareRequestStatus.fromWire(existing.single['status'] as String).isOpen) {
      return false;
    }
    if (await _hasLeft(db, id)) return false;
    await db.delete(
      Tables.outbox,
      where: 'entity_table = ? AND entity_id = ?',
      whereArgs: [Tables.careRequests, id],
    );
    await db.delete(
      Tables.careRequests,
      where: 'id = ?',
      whereArgs: [id],
    );
    return true;
  }

  /// The one test of "this has left the phone", shared by the card's wording and
  /// the withdrawal guard so they cannot drift apart.
  static Future<bool> _hasLeft(DatabaseExecutor db, String id) async {
    final sent = await db.query(
      Tables.outbox,
      where:
          'entity_table = ? AND entity_id = ? AND synced_at IS NOT NULL',
      whereArgs: [Tables.careRequests, id],
      limit: 1,
    );
    return sent.isNotEmpty;
  }

  static CareRequest? _first(List<Map<String, Object?>> rows) =>
      rows.isEmpty ? null : CareRequest.fromMap(rows.first);
}
```

`OutboxDao.enqueue` is verified as `enqueue(DatabaseExecutor txn, {required String table, required String entityId, required SyncOperation operation, required Map<String, Object?> payload, int priority = SyncPriority.routine})` at `lib/data/local/outbox_dao.dart:164` — the call above is correct as written. `SyncPriority.critical` is `0`.

- [x] **Step 5: Run the tests**

Run: `flutter test --no-pub --reporter compact test/care_request_dao_test.dart 2>&1 | tr '\r' '\n' | tail -20`
Expected: `+9: All tests passed!` If the migration test reports `no such table: care_requests`, `Tables.careRequests` was not added to `_schema`, so `createAll` never built it to drop. If a DAO read comes back null while the write clearly ran, the test grabbed `AppDatabase.openInMemory()` instead of `AppDatabase.instance.database` — those are two different databases.

- [x] **Step 6: Checkpoint**

`dart analyze lib/data/local/care_request_dao.dart lib/data/local/app_database.dart test/care_request_dao_test.dart`. Do not commit.

---

### Task 3: The server contract, so the request actually lands

**Files:**
- Create: `server/migrations/004_care_requests.sql`
- Modify: `server/schema.sql` (the table after `scheduled_contacts`, ~line 566; the triggers at the end of the delta-pull block, ~line 642)
- Modify: `server/src/tables.js` (`TABLES`, after `scheduled_contacts`)
- Test: `test/care_request_contract_test.dart`

**Interfaces:**
- Consumes: `CareRequest.toMap()` key set (Task 1).
- Produces: a server table and push whitelist entry whose columns are exactly the entity's keys, plus the `pull_updated_at` marker and triggers Task 4's `PULL_TABLES` entry selects on.

- [x] **Step 1: Write the failing test**

The three server artefacts and the Dart entity must agree, and nothing in the build catches a drift. This test reads the files, because the alternative is a 400 on a family's device in a district with no signal to debug it.

```dart
/// server/src/tables.js, schema.sql, migration 004 and CareRequest.toMap()
/// describe one thing four times. sync.js answers 400 for an unlisted table and
/// the client turns that into a permanent SendRejected, so a column present in
/// Dart and absent in SQL is not a warning — it is a request that never lands.
library;

import 'dart:io';

import 'package:carebridge_ai/domain/entities/care_request.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

const _keys = [
  'id',
  'household_id',
  'person_id',
  'level',
  'home_check_id',
  'created_by',
  'created_at',
  'updated_at',
  'status',
  'answered_at',
  'sync_state',
];

void main() {
  final sample = CareRequest.fromCheck(
    check: HomeCheck(
      id: 'chk-1',
      householdId: 'hh-1',
      personId: 'p-1',
      clientType: ClientType.childUnderFive,
      verdict: HomeCheckVerdict.urgent,
      yesSigns: const [],
      unsureSigns: const [],
      checkedBy: 'u-mother',
      checkedAt: DateTime(2026, 9, 28),
    ),
    userId: 'u-mother',
    at: DateTime(2026, 9, 28),
  )!;

  test('the entity serializes exactly the agreed columns', () {
    expect(sample.toMap().keys.toSet(), _keys.toSet());
  });

  for (final path in [
    'server/schema.sql',
    'server/migrations/004_care_requests.sql',
  ]) {
    test('$path declares care_requests with every column', () {
      final sql = File(path).readAsStringSync();
      final block = RegExp(
        r'CREATE TABLE IF NOT EXISTS care_requests \(([\s\S]*?)\)\s*ENGINE',
      ).firstMatch(sql);
      expect(block, isNotNull, reason: 'no care_requests DDL in $path');
      for (final column in _keys) {
        expect(
          block!.group(1),
          contains(column),
          reason: '$column missing from $path',
        );
      }
    });
  }

  test('tables.js whitelists care_requests for push', () {
    final js = File('server/src/tables.js').readAsStringSync();
    final block = RegExp(r'care_requests: \{([\s\S]*?)\n  \}').firstMatch(js);
    expect(block, isNotNull, reason: 'care_requests absent from the whitelist');
    for (final column in _keys) {
      expect(block!.group(1), contains("'$column'"));
    }
  });
}
```

If the repo's tests are not run from the package root, resolve the paths with `File('server/...')` relative to `Directory.current` as `test/model_artifact_test.dart` does — check that file's convention first.

- [x] **Step 2: Run it and watch it fail**

Run: `flutter test --no-pub --reporter compact test/care_request_contract_test.dart 2>&1 | tr '\r' '\n' | tail -20`
Expected: the entity test passes; the two SQL tests and the `tables.js` test fail with `no care_requests DDL`.

- [x] **Step 3: Add the DDL to `server/schema.sql`**

```sql
-- ----------------------------------------------------------------------------
-- Care requests — the family's ask for help, written by the caregiver's device.
--
-- This is the only caregiver-authored clinical signal that leaves the phone:
-- there is no home_checks table at all, on purpose. `updated_at` is what the
-- delta pull compares, because a worker answers a request by changing status on
-- their own device — unlike referrals, which are append-only.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS care_requests (
  id              VARCHAR(64)  NOT NULL,
  household_id    VARCHAR(64)  NOT NULL,
  person_id       VARCHAR(64)  NOT NULL,
  level           VARCHAR(24)  NOT NULL,
  home_check_id   VARCHAR(64)  NOT NULL,
  created_by      VARCHAR(64)  NOT NULL,
  created_at      VARCHAR(40)  NOT NULL,
  updated_at      VARCHAR(40)  NOT NULL,
  status          VARCHAR(24)  NOT NULL DEFAULT 'open',
  answered_at     VARCHAR(40)  NULL,
  sync_state      VARCHAR(24)  NOT NULL DEFAULT 'pending',
  pull_updated_at VARCHAR(40)  NULL,
  PRIMARY KEY (id),
  KEY idx_care_requests_household (household_id, created_at),
  KEY idx_care_requests_check (home_check_id),
  KEY idx_care_requests_pull (pull_updated_at)
) ENGINE=InnoDB;
```

and, at the end of the delta-pull trigger block, the two markers that make a
worker's answer discoverable at all (a table listed in `PULL_TABLES` without
`pull_updated_at` is an SQL error on every pull, for every caller):

```sql
CREATE TRIGGER IF NOT EXISTS trg_care_requests_pull_ins BEFORE INSERT ON care_requests
  FOR EACH ROW SET NEW.pull_updated_at = DATE_FORMAT(UTC_TIMESTAMP(), '%Y-%m-%dT%H:%i:%s');
CREATE TRIGGER IF NOT EXISTS trg_care_requests_pull_upd BEFORE UPDATE ON care_requests
  FOR EACH ROW SET NEW.pull_updated_at = DATE_FORMAT(UTC_TIMESTAMP(), '%Y-%m-%dT%H:%i:%s');
```

The block's own comment says "the five pullable clinical tables"; it is six now,
and `server/src/pull.js`'s header repeats the count. Both go to six in Task 4,
where the stream entry lands.

- [x] **Step 4: Write `server/migrations/004_care_requests.sql`**

Same DDL, wrapped in the header style migration `003` uses — state why it exists, that it is idempotent, that `schema.sql` carries the fresh-install copy, and that the whitelist entry lives in `src/tables.js`:

```sql
-- ============================================================================
-- 004_care_requests.sql — the family's request for help.
--
-- A caregiver's device enqueues one care_requests row when a family asks for a
-- health worker after an urgent or contact-today home check. The row must exist
-- server-side and be listed in src/tables.js: sync.js answers 400
-- "Unknown entity_table" for anything absent, the client classifies 4xx as a
-- permanent SendRejected, and the family's request would sit in their outbox
-- forever while their screen claimed help was coming.
--
-- There is deliberately no home_checks table. The check answers never leave the
-- phone; this table is the whole of what does.
--
-- Unlike barrier_reports and scheduled_contacts, which are push-only, this one
-- carries a server-managed pull_updated_at marker and the two triggers that
-- stamp it. A request is only real if the answer can travel home: a status
-- change made by a worker on their device has to reach the family's phone, or
-- they wait at home for a visitor who already came.
--
-- Idempotent: safe to run more than once. For FRESH installs the equivalent DDL
-- is already baked into schema.sql. The matching push whitelist lives in
-- src/tables.js and the pull registration in src/pull.js, and
-- test/care_request_contract_test.dart fails if the four drift apart.
--
-- Run with (the runtime sync user is least-privilege and cannot CREATE, so use
-- an admin account):
--   mysql -u <admin> -p carebridge < migrations/004_care_requests.sql
-- If that runtime user is granted per table rather than database-wide, add
-- SELECT, INSERT and UPDATE on care_requests to its grants before deploying.
-- ============================================================================

USE carebridge;

CREATE TABLE IF NOT EXISTS care_requests (
  id              VARCHAR(64)  NOT NULL,
  household_id    VARCHAR(64)  NOT NULL,
  person_id       VARCHAR(64)  NOT NULL,
  level           VARCHAR(24)  NOT NULL,
  home_check_id   VARCHAR(64)  NOT NULL,
  created_by      VARCHAR(64)  NOT NULL,
  created_at      VARCHAR(40)  NOT NULL,
  updated_at      VARCHAR(40)  NOT NULL,
  status          VARCHAR(24)  NOT NULL DEFAULT 'open',
  answered_at     VARCHAR(40)  NULL,
  sync_state      VARCHAR(24)  NOT NULL DEFAULT 'pending',
  pull_updated_at VARCHAR(40)  NULL,
  PRIMARY KEY (id),
  KEY idx_care_requests_household (household_id, created_at),
  KEY idx_care_requests_check (home_check_id),
  KEY idx_care_requests_pull (pull_updated_at)
) ENGINE=InnoDB;

-- Single-statement trigger bodies, so no DELIMITER gymnastics is required.
CREATE TRIGGER IF NOT EXISTS trg_care_requests_pull_ins BEFORE INSERT ON care_requests
  FOR EACH ROW SET NEW.pull_updated_at = DATE_FORMAT(UTC_TIMESTAMP(), '%Y-%m-%dT%H:%i:%s');
CREATE TRIGGER IF NOT EXISTS trg_care_requests_pull_upd BEFORE UPDATE ON care_requests
  FOR EACH ROW SET NEW.pull_updated_at = DATE_FORMAT(UTC_TIMESTAMP(), '%Y-%m-%dT%H:%i:%s');
```

- [x] **Step 5: Register the push whitelist in `server/src/tables.js`**

After the `scheduled_contacts` entry:

```js
  // The family's ask. Unlike every other row a caregiver can write, this one
  // also goes out on the pull stream (src/pull.js), because a worker has to
  // answer it on a different device — and an answer the family never receives
  // is a family that waits at home for a visitor who already came.
  care_requests: {
    pk: ['id'],
    columns: [
      'id', 'household_id', 'person_id', 'level', 'home_check_id',
      'created_by', 'created_at', 'updated_at', 'status', 'answered_at',
      'sync_state',
    ],
  },
```

- [x] **Step 6: Run the tests**

Run: `flutter test --no-pub --reporter compact test/care_request_contract_test.dart 2>&1 | tr '\r' '\n' | tail -20`
Expected: `+4: All tests passed!`

- [x] **Step 7: Checkpoint**

`node --check server/src/tables.js`. Do not commit.

---

### Task 4: The pull path, so the request reaches a desk and the answer reaches home

**Files:**
- Modify: `server/src/pull.js` (`PULL_TABLES` ~line 47, `tableFilter` ~line 108)
- Modify: `lib/data/sync/pull_service.dart` (`_applyPage` ~line 359, `_warmColumns` ~line 391)
- Test: `test/care_request_pull_test.dart`

**Interfaces:**
- Consumes: `Tables.careRequests`, `CareRequest`, `_mergeLww`.
- Produces: `care_requests` delivered in both directions, scoped by household, never echoed back to the server.

- [x] **Step 1: Write the failing test**

There is no test seam to add: `test/pull_service_test.dart:141-262` already runs the real `PullService` end to end against a fake district server through `PlatformHttpClient.override`, which is the code the field actually executes. Borrow that technique — a temp directory behind a path_provider mock, `PreferencesStore` pointed at `http://district.test`, a `PlatformHttpClient.override` that answers with one page — and write:

```dart
/// A request is only real when a human can receive it.
///
/// barrier_reports and scheduled_contacts are push-only: they reach the server
/// and never a worker's device (see the spec). This file is the reason
/// care_requests is not built the same way. It pins the two halves of the
/// round trip — the family's ask arriving on a worker's pull stream, and the
/// worker's status change arriving back home — and the one property that makes
/// the second half safe: a pulled row must never look locally dirty, or the
/// family's phone would echo the server's own answer straight back at it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:carebridge_ai/data/local/app_database.dart';
import 'package:carebridge_ai/data/local/care_request_dao.dart';
import 'package:carebridge_ai/data/local/preferences_store.dart';
import 'package:carebridge_ai/data/sync/http_client.dart';
import 'package:carebridge_ai/data/sync/pull_service.dart';
import 'package:carebridge_ai/domain/entities/care_request.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

const _serverTime = '2026-09-28T12:00:00.000Z';

/// As server/src/pull.js would: the row is the entity's own serialization, so
/// a column the entity stops writing stops being offered here too, plus the
/// server's watermark marker that the client must intersect away before
/// writing.
Map<String, dynamic> _asServerRow(
  CareRequest request, {
  Map<String, dynamic> overrides = const {},
}) =>
    {
      ...request.toMap(),
      ...overrides,
      'pull_updated_at': _serverTime,
    };

Map<String, dynamic> _page(List<Map<String, dynamic>> careRequests) => {
  'ok': true,
  'server_time': _serverTime,
  'scoped_to': {'user_id': 'u-worker', 'role': 'fhw'},
  'data': {'care_requests': careRequests},
  'has_more': false,
  'next_cursor': null,
};

final _request = CareRequest(
  id: 'req-chk-1',
  householdId: 'family',
  personId: 'baby',
  level: CareRequestLevel.urgent,
  homeCheckId: 'chk-1',
  createdBy: 'caregiver',
  createdAt: DateTime(2026, 9, 28, 9, 5),
  updatedAt: DateTime(2026, 9, 28, 9, 5),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // PullService and the DAOs both read AppDatabase.instance, so this file gets
  // one database through the path_provider mock — the same harness
  // test/pull_service_test.dart uses. A second handle would mean merging into
  // a database nothing here reads back.
  late Database db;
  setUp(() async {
    final dir = Directory.systemTemp.createTempSync('carebridge_pull_request');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? dir.path
              : null,
        );
    AppDatabase.initialiseForDesktopAndTests();
    db = await AppDatabase.instance.database;
    // The pull writes into care_requests, whose foreign keys are live.
    await db.insert(Tables.households, {
      'id': 'family',
      'name': 'Family',
      'region': 'Northern Region',
      'district': 'Karaga',
      'community': 'Karaga',
      'created_by': 'caregiver',
      'created_at': '2026-09-01T00:00:00.000',
      'updated_at': '2026-09-01T00:00:00.000',
    });
    await db.insert(Tables.persons, {
      'id': 'baby',
      'household_id': 'family',
      'full_name': 'Awah',
      'client_type': 'newborn',
      'date_of_birth': '2026-08-01T00:00:00.000',
      'created_at': '2026-09-01T00:00:00.000',
      'updated_at': '2026-09-01T00:00:00.000',
    });
  });
  tearDown(() => AppDatabase.instance.close());

  /// Serves one page from the fake district server and runs a real pull.
  Future<PullReport> pull(List<Map<String, dynamic>> rows) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await PreferencesStore.setSyncApiUrl('http://district.test');
    await PreferencesStore.setSyncApiToken('pull-test-token');
    PlatformHttpClient.override = (method, uri, headers, body) async =>
        HttpReply(200, jsonEncode(_page(rows)));
    addTearDown(() => PlatformHttpClient.override = null);
    return PullService(minGap: Duration.zero).pull(userId: 'u-worker');
  }

  group('the pull stream', () {
    test('server/src/pull.js streams care_requests, scoped by household', () {
      final src = File('server/src/pull.js').readAsStringSync();
      expect(src, contains("'care_requests'"));
      // Scoped the way persons and visits are — by the household, never by the
      // author. A worker who covers the zone must see the ask; a worker two
      // districts over must not.
      expect(
        RegExp(
          r"case 'persons':\s*case 'visits':\s*case 'care_requests':",
        ).hasMatch(src.replaceAll(RegExp(r'\s+'), ' ')),
        isTrue,
        reason: 'care_requests must join the household-scoped case, not grow '
            'its own filter that a later edit can drift from',
      );
    });

    test('a worker’s empty device receives the ask, and does not send it '
        'back', () async {
      // Nothing was written to care_requests in setUp, which is exactly a
      // worker who has never seen this family.
      final report = await pull([_asServerRow(_request)]);
      expect(report.isSuccess, isTrue, reason: report.toString());

      final stored = await CareRequestDao.byId('req-chk-1');
      expect(stored?.level, CareRequestLevel.urgent);
      expect(stored?.syncState, SyncState.synced);
      expect(
        await db.query(
          Tables.outbox,
          where: 'entity_table = ?',
          whereArgs: [Tables.careRequests],
        ),
        isEmpty,
        reason: 'a pulled row that looks dirty is a row the phone sends back',
      );
      expect(
        (await db.query(Tables.careRequests)).single
            .containsKey('pull_updated_at'),
        isFalse,
        reason: 'server bookkeeping is intersected away, not written into a '
            'local schema with no such column',
      );
    });

    test('the family’s device receives a worker’s answer', () async {
      await db.transaction((txn) => CareRequestDao.createIn(txn, _request));
      // The outbox row is what makes the family's copy look dirty; clearing it
      // stands for the push having completed, so only the server's newer
      // version is left to arrive.
      await db.delete(Tables.outbox);

      final answered = _asServerRow(
        _request,
        overrides: {
          'status': CareRequestStatus.answered.wireValue,
          'answered_at': '2026-09-28T14:00:00.000',
          // The exact column _mergeLww compares, written in the same format
          // the local row uses: the comparison is a plain string compare, so a
          // trailing Z here would make the ordering a lie.
          'updated_at': '2026-09-28T14:00:00.000',
        },
      );

      final report = await pull([answered]);
      expect(report.isSuccess, isTrue, reason: report.toString());

      final stored = await CareRequestDao.byId('req-chk-1');
      expect(stored?.status, CareRequestStatus.answered);
      expect(stored?.isOpen, isFalse);
      expect(
        await db.query(
          Tables.outbox,
          where: 'entity_table = ?',
          whereArgs: [Tables.careRequests],
        ),
        isEmpty,
        reason: 'being handed an answer is not the family having one to send',
      );
    });

    test('a re-offered older page cannot undo the newer status', () async {
      await CareRequestDao.createIn(
        db,
        CareRequest(
          id: _request.id,
          householdId: _request.householdId,
          personId: _request.personId,
          level: _request.level,
          homeCheckId: _request.homeCheckId,
          createdBy: _request.createdBy,
          createdAt: _request.createdAt,
          updatedAt: DateTime(2026, 9, 28, 14),
          status: CareRequestStatus.answered,
          answeredAt: DateTime(2026, 9, 28, 14),
        ),
      );
      await db.delete(Tables.outbox);

      await pull([_asServerRow(_request)]); // the 09:05 version, re-offered

      expect(
        (await CareRequestDao.byId('req-chk-1'))?.status,
        CareRequestStatus.answered,
        reason: 'last-write-wins must not let a replayed page unanswer a '
            'request the family was already told about',
      );
    });
  });
}
```

Three details that will bite if written from memory. `PullReport`, the `PullService(minGap:)` constructor and the `PlatformHttpClient.override` closure shape all come from `test/pull_service_test.dart:158-199` — copy them from there rather than reshaping them. `_mergeLww` compares `updated_at` as a plain **string**, which is why every timestamp in these fixtures stays in one ISO family with no trailing `Z`; `pull_service_test.dart` has a `_shift` helper for exactly this, and should a comparison ever read as false, use it instead of hand-writing a date. And in `PULL_TABLES`, `care_requests` must come **after** `households`: on a family device that has somehow lost its household row, a request pointing at a missing parent is a foreign-key failure mid-page, which is why the list's order is a correctness property rather than cosmetics.

- [x] **Step 2: Run it and watch it fail**

Run: `flutter test --no-pub --reporter compact test/care_request_pull_test.dart 2>&1 | tr '\r' '\n' | tail -25`
Expected: the `pull.js` test fails on the missing `'care_requests'`; the merge tests fail because the table is not in the apply loop.

- [x] **Step 3: Add it to the server stream**

In `server/src/pull.js`, `PULL_TABLES` (parents before children — the row's household must land first on a fresh device):

```js
  // After households, whose row a family's request points at: a device that
  // lost its household must receive the parent first or the child is an
  // FK failure mid-page.
  { name: 'care_requests', pk: 'id' },
```

after `{ name: 'referrals', pk: 'id' }`. The response's `data` literal initialises one key per streamed table so a page that stops early still answers with `[]` rather than a missing key, so `care_requests: []` joins it, and the header comment's "the five pullable clinical tables" becomes six.

In `tableFilter`, extend the household-scoped case — a caregiver must receive only its own household's rows, and `householdScope()` already enforces that. The comment goes **above** `case 'persons':`, not between the labels: the contract test asserts the three cases stay one block.

```js
    // Household-scoped, and deliberately one case for all three: a worker who
    // covers the zone receives the family's ask, a worker two districts over
    // never learns it exists, and a bound caregiver receives exactly their own.
    case 'persons':
    case 'visits':
    case 'care_requests':
      return {
        sql: `household_id IN (SELECT id FROM households WHERE ${hh.sql})`,
        params: hh.params,
      };
```

- [x] **Step 4: Apply it on the client**

In `lib/data/sync/pull_service.dart` `_applyPage`, after the persons loop and **before** the insert-if-absent loop, with the `sync_state` normalisation `_mergeIfAbsent` already does and `_mergeLww` does not:

```dart
    // The family's ask answers back: a worker changes the status on their own
    // device and the family must receive it, so this table merges
    // last-write-wins rather than insert-if-absent. sync_state is normalised
    // here because push never touches the entity row — the server's copy of a
    // request still reads 'pending' on the phone that wrote it, and a pulled
    // row is by definition already on the server.
    for (final row in _rows(data[Tables.careRequests])) {
      if (await _mergeLww(
        txn,
        Tables.careRequests,
        {...row, 'sync_state': 'synced'},
        columns,
      )) {
        applied++;
      } else {
        skipped++;
      }
    }
```

Unconditional, not `if (row.containsKey(...))`: the override states a fact about the row's provenance rather than copying a column, and `_localColumns` intersects against the real schema anyway, so a device whose table lacks the column drops the key instead of failing.

Add `Tables.careRequests,` to the `_warmColumns` list — a table missing from that cache has a null column set, which makes every merge for it an honest no-op.

- [x] **Step 5: Run the tests**

Run: `flutter test --no-pub --reporter compact test/care_request_pull_test.dart test/pull_service_test.dart 2>&1 | tr '\r' '\n' | tail -25`
Expected: all pass. If `pull_service_test.dart` breaks, the `sync_state` normalisation leaked into another table's path — it must apply inside the `care_requests` loop only.

- [x] **Step 6: Checkpoint**

`node --check server/src/pull.js && dart analyze lib/data/sync/pull_service.dart`. Do not commit.

---

### Task 5: The permission and the repository gate

**Files:**
- Modify: `lib/domain/enums.dart` (`Permission`, line 31-70)
- Modify: `lib/data/repositories/care_repository.dart` (new section after `recordHomeCheck`, ~line 905)
- Test: `test/care_request_repository_test.dart`

**Interfaces:**
- Consumes: `Permission.requestCare`, `CareRequestDao`, `_require`, `_requireCaregiverScope`, `_clock`.
- Produces: `Future<CareRequest?> raiseCareRequest(AppUser user, CaregiverScope scope, HomeCheck check)`, `Future<bool> withdrawCareRequest(AppUser user, CaregiverScope scope, String homeCheckId)` and `Future<({CareRequest request, bool sent})?> careRequestState(AppUser user, CaregiverScope scope, String homeCheckId)`.

- [x] **Step 1: Write the failing test**

The harness is `test/caregiver_state_test.dart`'s: it already seeds a caregiver bound to one household, a second household, a person in each, and a role-swapped user, which is precisely the set a scope test needs. Copy its `setUp` and its `user`/`scope`/`person` fixtures rather than inventing a narrower one, and write:

```dart
/// Asking for help is not the same permission as running a check.
///
/// A caregiver holds `runCaregiverTriage` because the family's own screen must
/// work. That does not make them entitled to summon a health worker — a request
/// costs a person a walk, and a family in one compound cannot be able to call
/// out the worker assigned to another. The gate is therefore separate, and the
/// household scope is the wall.
library;

import 'dart:io';

import 'package:carebridge_ai/data/local/app_database.dart';
import 'package:carebridge_ai/data/local/care_request_dao.dart';
import 'package:carebridge_ai/data/repositories/care_repository.dart';
import 'package:carebridge_ai/domain/entities/care_request.dart';
import 'package:carebridge_ai/domain/entities/caregiver.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/domain/services/caregiver_check_policy.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 9, 28, 9);
  const scope = CaregiverScope(userId: 'caregiver', householdId: 'family');
  const user = AppUser(
    id: 'caregiver',
    fullName: 'Amina',
    phone: '0240000001',
    role: UserRole.caregiver,
    region: 'Northern Region',
    district: 'Karaga',
    community: 'Karaga',
  );
  const worker = AppUser(
    id: 'fhw',
    fullName: 'Abena',
    phone: '0240000009',
    role: UserRole.frontlineHealthWorker,
    region: 'Northern Region',
    district: 'Karaga',
    community: 'Karaga',
  );
  final repo = CareRepository(clock: () => now);
  late Database db;

  /// A newborn check with one YES, which the policy decides as urgent — the
  /// same answer set caregiver_state_test finalizes to an urgent HomeCheck.
  CaregiverDraft draft({
    String id = 'session',
    String personId = 'baby',
    Map<String, CaregiverAnswer> answers = const {
      'feed': CaregiverAnswer.yes,
    },
  }) => CaregiverDraft(
    id: id,
    scope: scope,
    personId: personId,
    kind: CaregiverDraftKind.homeCheck,
    questionVersion: CaregiverCheckPolicy.questionVersion,
    cohortKey: 'newborn',
    answers: answers,
    startedAt: now,
    updatedAt: now,
  );

  HomeCheck check({
    String id = 'session',
    String householdId = 'family',
    String personId = 'baby',
    HomeCheckVerdict verdict = HomeCheckVerdict.urgent,
  }) => HomeCheck(
    id: id,
    householdId: householdId,
    personId: personId,
    clientType: ClientType.newborn,
    verdict: verdict,
    yesSigns: const ['Feeding poorly'],
    unsureSigns: const [],
    checkedBy: user.id,
    checkedAt: now,
  );

  setUp(() async {
    final dir = Directory.systemTemp.createTempSync('carebridge_care_request');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? dir.path
              : null,
        );
    AppDatabase.initialiseForDesktopAndTests();
    db = await AppDatabase.instance.database;
    for (final person in [user, worker]) {
      await db.insert(
        Tables.users,
        person.toMap()
          ..['linked_household_id'] = person == user ? 'family' : null,
      );
    }
    for (final id in ['family', 'another']) {
      await db.insert(Tables.households, {
        'id': id,
        'name': id,
        'region': user.region,
        'district': user.district,
        'community': user.community,
        'created_by': user.id,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
    }
    await db.insert(Tables.persons, {
      'id': 'baby',
      'household_id': 'family',
      'full_name': 'Awah',
      'client_type': 'newborn',
      'date_of_birth': DateTime(2026, 9, 1).toIso8601String(),
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    await db.insert(Tables.persons, {
      'id': 'neighbour',
      'household_id': 'another',
      'full_name': 'Kofi',
      'client_type': 'newborn',
      'date_of_birth': DateTime(2026, 9, 1).toIso8601String(),
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
  });
  tearDown(() => AppDatabase.instance.close());

  group('raiseCareRequest', () {
    test('a caregiver raises one for their own finalized urgent check',
        () async {
      await repo.saveCaregiverDraft(user, draft());
      final saved = await repo.finalizeCaregiverHomeCheck(user, draft());

      final raised = await repo.raiseCareRequest(user, scope, saved);

      expect(raised.level, CareRequestLevel.urgent);
      expect(raised.homeCheckId, saved.id);
      expect(raised.householdId, 'family');
      expect(raised.status, CareRequestStatus.open);
      // The whole point of the record: something left the phone.
      final queued = await db.query(
        Tables.outbox,
        where: 'entity_table = ?',
        whereArgs: [Tables.careRequests],
      );
      expect(queued, hasLength(1));
      expect(queued.single['priority'], 0);
    });

    test('a second tap on the same check returns the first request', () async {
      await repo.saveCaregiverDraft(user, draft());
      final saved = await repo.finalizeCaregiverHomeCheck(user, draft());
      final first = await repo.raiseCareRequest(user, scope, saved);
      final second = await repo.raiseCareRequest(user, scope, saved);

      expect(second.id, first.id);
      expect(await db.query(Tables.careRequests), hasLength(1));
      expect(
        await db.query(Tables.outbox, where: 'entity_table = ?',
            whereArgs: [Tables.careRequests]),
        hasLength(1),
        reason: 'two queue entries would mean two summons for one tap',
      );
    });

    test('a check that came back fine raises nothing', () async {
      expect(
        await repo.raiseCareRequest(
          user,
          scope,
          check(verdict: HomeCheckVerdict.fine),
        ),
        isNull,
      );
      expect(
        await db.query(Tables.outbox, where: 'entity_table = ?',
            whereArgs: [Tables.careRequests]),
        isEmpty,
      );
    });

    test('a caution verdict asks for a visit today, not an emergency',
        () async {
      final raised = await repo.raiseCareRequest(
        user,
        scope,
        check(verdict: HomeCheckVerdict.caution),
      );
      expect(raised?.level, CareRequestLevel.today);
    });

    test('one family cannot ask for another family’s worker', () async {
      await expectLater(
        repo.raiseCareRequest(user, scope, check(householdId: 'another')),
        throwsA(isA<AccessDenied>()),
      );
      expect(await db.query(Tables.careRequests), isEmpty);
    });

    test('a role without requestCare is refused', () async {
      await expectLater(
        repo.raiseCareRequest(
          worker,
          const CaregiverScope(userId: 'fhw', householdId: 'family'),
          check(),
        ),
        throwsA(isA<AccessDenied>()),
      );
    });
  });

  group('withdrawCareRequest', () {
    test('a request that has not been sent can be called back', () async {
      await repo.saveCaregiverDraft(user, draft());
      final saved = await repo.finalizeCaregiverHomeCheck(user, draft());
      await repo.raiseCareRequest(user, scope, saved);

      expect(await repo.withdrawCareRequest(user, scope, saved.id), isTrue);
      expect(await db.query(Tables.careRequests), isEmpty);
      expect(
        await db.query(Tables.outbox, where: 'entity_table = ?',
            whereArgs: [Tables.careRequests]),
        isEmpty,
      );
    });

    test('withdrawing another household’s request is refused', () async {
      // Written straight to the table, because the repository would never let
      // this family create it. What is being tested is the read side: a caller
      // who guesses a request id must not be able to cancel someone else's.
      await db.insert(
        Tables.careRequests,
        CareRequest(
          id: 'req-chk-other',
          householdId: 'another',
          personId: 'neighbour',
          level: CareRequestLevel.urgent,
          homeCheckId: 'chk-other',
          createdBy: 'someone-else',
          createdAt: now,
          updatedAt: now,
        ).toMap(),
      );
      await expectLater(
        repo.withdrawCareRequest(user, scope, 'chk-other'),
        throwsA(isA<AccessDenied>()),
      );
      expect(await CareRequestDao.byId('req-chk-other'), isNotNull);
    });

    test('withdrawing a request that was never raised is simply no', () async {
      expect(await repo.withdrawCareRequest(user, scope, 'session'), isFalse);
    });
  });

  group('careRequestState', () {
    test('nothing has been asked, so there is nothing to show', () async {
      await repo.saveCaregiverDraft(user, draft());
      final saved = await repo.finalizeCaregiverHomeCheck(user, draft());
      expect(await repo.careRequestState(user, scope, saved.id), isNull);
    });

    test('a queued request reads as asked and not yet sent', () async {
      await repo.saveCaregiverDraft(user, draft());
      final saved = await repo.finalizeCaregiverHomeCheck(user, draft());
      await repo.raiseCareRequest(user, scope, saved);

      final state = await repo.careRequestState(user, scope, saved.id);
      expect(state?.request.id, 'req-${saved.id}');
      expect(state?.sent, isFalse);
    });

    test('sent becomes true only when the queue entry has actually gone',
        () async {
      await repo.saveCaregiverDraft(user, draft());
      final saved = await repo.finalizeCaregiverHomeCheck(user, draft());
      await repo.raiseCareRequest(user, scope, saved);
      await db.update(
        Tables.outbox,
        {'synced_at': now.add(const Duration(minutes: 2)).toIso8601String()},
        where: 'entity_id = ?',
        whereArgs: ['req-${saved.id}'],
      );

      expect((await repo.careRequestState(user, scope, saved.id))?.sent, isTrue);
    });

    test('an answer stays visible, and cannot be re-raised over', () async {
      await repo.saveCaregiverDraft(user, draft());
      final saved = await repo.finalizeCaregiverHomeCheck(user, draft());
      await repo.raiseCareRequest(user, scope, saved);
      await CareRequestDao.markAnsweredIn(db, 'req-${saved.id}', now);

      final state = await repo.careRequestState(user, scope, saved.id);
      expect(state?.request.status, CareRequestStatus.answered);
      // A second tap finds the answered row instead of replacing it: the reply
      // is the family's record, and re-inserting would queue a second summons
      // for a household a worker has already answered.
      final again = await repo.raiseCareRequest(user, scope, saved);
      expect(again?.status, CareRequestStatus.answered);
      expect(await db.query(Tables.careRequests), hasLength(1));
    });
  });
}
```

Three things to check against the repository as you go, because they are the plan's assertions and the code may disagree. `finalizeCaregiverHomeCheck` takes `(user, draft)` and returns the `HomeCheck` — no scope argument (`care_repository.dart:1173`). `AccessDenied` is a thrown exception, not a returned value; item C of the caregiver audit removed the try/catch that used to swallow it. And the `cohortKey` above is what `CaregiverCheckPolicy(clock:).questionsFor(person)!.cohortKey` returns for a newborn — if the literal `'newborn'` fails, compute it the way `caregiver_state_test.dart:50-52` does rather than guessing a second string.

- [x] **Step 2: Run it and watch it fail**

Expected: `The method 'raiseCareRequest' isn't defined for the type 'CareRepository'`.

- [x] **Step 3: Grant the capability**

`lib/domain/enums.dart`, in `Permission` after `recordBarrier` (this is a write, so it belongs with the writes):

```dart
  recordBarrier,
  /// Asking a health worker to come. Held by families only; deliberately not
  /// bundled with runCaregiverTriage, which is about a screen working.
  requestCare,
```

and in `_caregiver`:

```dart
    recordBarrier,
    requestCare,
```

`_fhw` stays without it. A worker who needs to visit already writes their own schedule; letting them file a family's request would erase the fact this plan exists to record.

- [x] **Step 4: Add the repository methods**

In `lib/data/repositories/care_repository.dart`, immediately after `recordHomeCheck`:

```dart
  /// Sends the one thing a home check is allowed to send: the family asking for
  /// help. The check itself stays on their device (see `recordHomeCheck`), so
  /// this carries who they are worried about and how urgent the check judged it,
  /// never what they answered.
  ///
  /// Returns the request that now exists — including the one this check already
  /// raised, so a second tap cannot summon two people — or null when the verdict
  /// asks for nothing.
  Future<CareRequest?> raiseCareRequest(
    AppUser user,
    CaregiverScope scope,
    HomeCheck check,
  ) async {
    await _require(
      user,
      Permission.requestCare,
      'ask for a health worker',
      entityTable: 'care_requests',
      entityId: 'req-${check.id}',
    );
    await _requireCaregiverScope(user, scope, personId: check.personId);
    // Not redundant with the helper above: that proves the person belongs to
    // this family. This proves the *check* handed over belongs to it too, so a
    // family cannot point a request at the household next door.
    if (check.householdId != scope.householdId) {
      throw const AccessDenied(
        'ask for help for another household',
        Permission.requestCare,
      );
    }

    // Any status, not just open. `CareRequest.id` is derived from the check, so
    // an answered request has this same primary key: finding only open rows here
    // would let a second tap replace the health worker's reply with a fresh open
    // request and queue a second summons for a family someone has already
    // answered.
    final existing = await CareRequestDao.forCheck(check.id);
    if (existing != null) return existing;

    final request = CareRequest.fromCheck(
      check: check,
      userId: user.id,
      at: _clock(),
    );
    if (request == null) return null;

    await CareRequestDao.create(request);
    return request;
  }

  /// Calls back a request the family sent but that has not reached the network.
  ///
  /// Once the server has it, this returns false rather than deleting: the health
  /// worker already knows, and a family whose screen now says "nobody was told"
  /// would be believing the less true of the two statements. Refusing an
  /// answered request is the same rule — the reply is theirs to keep.
  Future<bool> withdrawCareRequest(
    AppUser user,
    CaregiverScope scope,
    String homeCheckId,
  ) async {
    await _require(
      user,
      Permission.requestCare,
      'withdraw your request',
      entityTable: 'care_requests',
    );
    await _requireCaregiverScope(user, scope);
    final request = await CareRequestDao.openForCheck(homeCheckId);
    if (request == null) return false;
    if (request.householdId != scope.householdId) {
      throw const AccessDenied(
        'withdraw another household’s request',
        Permission.requestCare,
      );
    }
    return CareRequestDao.withdraw(request.id);
  }

  /// What the family already asked for this check, and whether the phone has
  /// managed to send it — one read, because the card that shows the state must
  /// not pair a request with a delivery flag taken from somewhere else.
  Future<({CareRequest request, bool sent})?> careRequestState(
    AppUser user,
    CaregiverScope scope,
    String homeCheckId,
  ) async {
    await _require(user, Permission.requestCare, 'view your request');
    await _requireCaregiverScope(user, scope);
    final request = await CareRequestDao.forCheck(homeCheckId);
    if (request == null) return null;
    return (
      request: request,
      sent: await CareRequestDao.isSent(request.id),
    );
  }
```

`_requireCaregiverScope(user, scope)` with no `personId` is the right call for the two read/withdraw paths: it still checks `manageOwnFamily`, that the scope is the caller's own, and that the scope's household is the one bound to the account — there is simply no person row to vouch for. `_clock()` is the repository's injected clock, so a test that pins `now` gets a request stamped `now`.

One deviation from the snippet, kept deliberately: `CareRepository` has never opened a database — every atomic write in this app is opened inside a DAO, and the repository's job is permissions, not connections. So `CareRequestDao` carries both shapes, the way `VisitDao` carries `markEscalated` and `markEscalatedIn`: `create(request)` and `withdraw(id)` take the transaction themselves, and the `*In` pair stays for callers who already hold one (the tests, and the pull merge later).

- [x] **Step 5: Run the tests**

Run: `flutter test --no-pub --reporter compact test/care_request_repository_test.dart test/rbac_test.dart 2>&1 | tr '\r' '\n' | tail -25`
Expected: all pass. `rbac_test.dart` enumerates role capabilities and may assert an exact permission set — if it does, add `requestCare` to the caregiver expectation, because that is a real change in the contract, not a flake.

- [x] **Step 6: Checkpoint**

`dart analyze lib/domain/enums.dart lib/data/repositories/care_repository.dart`. Do not commit.

---

### Task 6: Wire it into the check controller

**Files:**
- Modify: `lib/presentation/caregiver/check/check_controller.dart` (fields beside `report` at line 47; actions beside `stopForVerdict`)
- Modify: `lib/domain/services/caregiver_check_policy.dart` (one static guard, next to `verdictSpeech` ~line 550)
- Test: extend `test/caregiver_controller_test.dart`

There is no provider to add. The controller is constructed in `triage_screen.dart:87` with `repository`, `user` and `scope` already injected as final fields (`check_controller.dart:28-43`), so it calls the repository directly the way `_persist` does. Do not touch `lib/app/providers.dart` for this.

**Interfaces:**
- Consumes: `CareRepository.raiseCareRequest(AppUser, CaregiverScope, HomeCheck)`, `CareRepository.withdrawCareRequest(AppUser, CaregiverScope, String)`, `CareRepository.careRequestState(AppUser, CaregiverScope, String)`, `HomeCheck report` (already on the controller, line 47), `CaregiverCheckPolicy.canAskForHelp`.
- Produces: on `CaregiverCheckController` — `CareRequest? careRequest`, `bool requestSent`, `bool requestingHelp`, `String? requestError`, `Future<void> askForHelp()`, `Future<void> withdrawHelp()`, `Future<void> refreshRequest()`; and `static bool CaregiverCheckPolicy.canAskForHelp(HomeCheckVerdict verdict)`.

- [x] **Step 1: Write the failing test**

`test/caregiver_controller_test.dart` drives a check with a `MemoryRepository` fake that overrides the real repository methods — extend that fake rather than adding a database. Add these overrides to `MemoryRepository`, then the group:

```dart
  final requests = <String, CareRequest>{};
  final withdrawals = <String>[];
  bool failAsk = false;
  CareRequest? state;
  bool stateSent = false;

  @override
  Future<CareRequest?> raiseCareRequest(
    AppUser user,
    CaregiverScope scope,
    HomeCheck check,
  ) async {
    if (failAsk) throw StateError('Storage unavailable');
    final existing = requests[check.id];
    if (existing != null) return existing;
    final level = CareRequest.levelFor(check.verdict);
    if (level == null) return null;
    final request = CareRequest(
      id: 'req-${check.id}',
      householdId: scope.householdId,
      personId: check.personId,
      level: level,
      homeCheckId: check.id,
      createdBy: user.id,
      createdAt: time,
      updatedAt: time,
    );
    requests[check.id] = request;
    return request;
  }

  @override
  Future<bool> withdrawCareRequest(
    AppUser user,
    CaregiverScope scope,
    String homeCheckId,
  ) async {
    withdrawals.add(homeCheckId);
    return requests.remove(homeCheckId) != null;
  }

  @override
  Future<({CareRequest request, bool sent})?> careRequestState(
    AppUser user,
    CaregiverScope scope,
    String homeCheckId,
  ) async {
    final request = state ?? requests[homeCheckId];
    if (request == null) return null;
    return (request: request, sent: stateSent);
  }
```

`time` is that file's mutable clock fixture, and the file's `baby` is a newborn, so `controller.answer('feed', ...)` is a real question key. Drive a real check the way the existing tests do: a YES plus `stopForVerdict()` for urgent, or the all-answered loop with one `unsure` plus `setDuration`/`finishContext` for caution (see `test/caregiver_controller_test.dart:245-277`).

```dart
  group('asking for help', () {
    Future<void> finishWith({required CaregiverAnswer unsureOn}) async {
      await controller.load();
      for (final q in controller.questions!.questions) {
        controller.answer(
          q.key,
          q.key == unsureOn ? CaregiverAnswer.unsure : CaregiverAnswer.no,
        );
        controller.next();
      }
      controller.setDuration('today');
      controller.finishContext();
      await controller.settled;
    }

    test('an urgent result has asked for nothing yet', () async {
      await controller.load();
      controller.answer('feed', CaregiverAnswer.yes);
      controller.stopForVerdict();
      await controller.settled;
      expect(controller.report!.verdict, HomeCheckVerdict.urgent);
      expect(controller.careRequest, isNull);
      expect(controller.requestSent, isFalse);
    });

    test('asking writes one request and holds it', () async {
      await controller.load();
      controller.answer('feed', CaregiverAnswer.yes);
      controller.stopForVerdict();
      await controller.settled;

      await controller.askForHelp();
      expect(controller.careRequest?.level, CareRequestLevel.urgent);
      expect(repo.requests.length, 1);
      expect(controller.requestingHelp, isFalse);
      expect(controller.requestError, isNull);
    });

    test('asking twice summons one health worker, not two', () async {
      await controller.load();
      controller.answer('feed', CaregiverAnswer.yes);
      controller.stopForVerdict();
      await controller.settled;

      await controller.askForHelp();
      await controller.askForHelp();
      expect(repo.requests.length, 1);
    });

    test('a caution check may ask, and asks for today', () async {
      await finishWith(unsureOn: 'feed');
      expect(controller.report!.verdict, HomeCheckVerdict.caution);
      await controller.askForHelp();
      expect(controller.careRequest?.level, CareRequestLevel.today);
    });

    test('a failed write says nothing was sent, and leaves the button usable',
        () async {
      await controller.load();
      controller.answer('feed', CaregiverAnswer.yes);
      controller.stopForVerdict();
      await controller.settled;
      repo.failAsk = true;

      await controller.askForHelp();
      expect(controller.careRequest, isNull);
      expect(controller.requestingHelp, isFalse);
      expect(controller.requestError, isNotNull);

      repo.failAsk = false;
      await controller.askForHelp();
      expect(controller.careRequest, isNotNull);
    });

    test('an all-clear result is not offered the ask', () async {
      await finishWith(unsureOn: 'nothing-matches-this-key');
      expect(controller.report!.verdict, HomeCheckVerdict.fine);
      await controller.askForHelp();
      expect(controller.careRequest, isNull);
      expect(repo.requests, isEmpty);
    });

    test('refresh reads back what was sent while the screen was away',
        () async {
      await controller.load();
      controller.answer('feed', CaregiverAnswer.yes);
      controller.stopForVerdict();
      await controller.settled;
      await controller.askForHelp();
      expect(controller.requestSent, isFalse);

      repo.stateSent = true;
      await controller.refreshRequest();
      expect(controller.requestSent, isTrue);
    });

    test('withdrawing clears the state only when the repository agrees',
        () async {
      await controller.load();
      controller.answer('feed', CaregiverAnswer.yes);
      controller.stopForVerdict();
      await controller.settled;
      await controller.askForHelp();

      await controller.withdrawHelp();
      expect(controller.careRequest, isNull);
      expect(repo.withdrawals, [controller.report!.id]);

      // Nothing to call back — the request already left, or was never made.
      await controller.withdrawHelp();
      expect(controller.careRequest, isNull);
    });

    test('an account switch cannot ask on the old family’s behalf', () async {
      await controller.load();
      controller.answer('feed', CaregiverAnswer.yes);
      controller.stopForVerdict();
      await controller.settled;
      current = false;

      await controller.askForHelp();
      expect(controller.careRequest, isNull);
      expect(repo.requests, isEmpty);
      current = true;
    });
  });
```

The last two cases are the two failure modes worth pinning: a refresh that reports the truth the storage holds (not the truth the tap hoped for), and an account switch mid-write, which every other action in this controller already refuses through `_live`.

- [x] **Step 2: Run it and watch it fail**

Run: `flutter test --no-pub --reporter compact test/caregiver_controller_test.dart 2>&1 | tr '\r' '\n' | tail -25`
Expected: `The method 'askForHelp' isn't defined for the type 'CaregiverCheckController'`. If `MemoryRepository` fails to override instead, the signatures in Task 5 changed — match them exactly rather than casting.

- [x] **Step 3: Add the guard to the policy**

In `lib/domain/services/caregiver_check_policy.dart`, next to `verdictSpeech` (which already maps each verdict to its spoken instruction), add:

```dart
  /// Whether a verdict justifies asking a health worker to come.
  ///
  /// Mirrors `verdictSpeech`: urgent and caution both already tell the family to
  /// reach a worker today, so a request is the same instruction with a channel.
  /// `fine` does not — and a request a family can file when nothing is wrong
  /// stops meaning anything to whoever reads the queue.
  static bool canAskForHelp(HomeCheckVerdict verdict) =>
      verdict != HomeCheckVerdict.fine;
```

Keeping it here rather than in the screen means the file that decides the verdict also decides what the verdict entitles you to ask for, and the controller's guard is one call.

- [x] **Step 4: Add the state and the actions**

In `check_controller.dart`, beside `HomeCheck? report;` (line 47):

```dart
  /// The family's request for help, once they have made one. Null until then —
  /// and it stays null for an all-clear check, which is the honest state.
  CareRequest? careRequest;

  /// Whether the request has reached the server. Read from the outbox, never
  /// inferred from how long ago the tap happened.
  bool requestSent = false;

  /// True between the tap and the write landing, so the control can say
  /// "Sending" instead of looking dead.
  bool requestingHelp = false;

  /// Why the last ask failed, in the family's terms. Set only when nothing was
  /// written; the card must not show it beside a request that did land.
  String? requestError;
```

and the three actions, after `stopForVerdict()` (which they follow, not replace — the check still has to be finished before there is a verdict to ask about):

```dart
  /// Ask a health worker to come. Writes the request only — the check and its
  /// answers stay on this device (`recordHomeCheck` in the repository).
  ///
  /// Ordered on the same [_tail] as every other write, so an ask that races a
  /// save cannot land between the save and its notification, and it is guarded
  /// by `_live` because an account switch must not publish a request into the
  /// next family's session.
  Future<void> askForHelp() {
    final check = report;
    if (check == null || !_live) return Future.value();
    if (!CaregiverCheckPolicy.canAskForHelp(check.verdict)) {
      requestError = 'This check did not find a reason to ask for help.';
      _notify();
      return Future.value();
    }
    requestingHelp = true;
    requestError = null;
    _notify();
    _tail = _tail.then((_) async {
      if (!isCurrent()) return;
      try {
        careRequest = await repository.raiseCareRequest(user, scope, check);
        if (careRequest != null) {
          final state = await repository.careRequestState(
            user,
            scope,
            check.id,
          );
          requestSent = state?.sent ?? false;
        }
      } catch (_) {
        // Nothing was written, so the screen says nothing was written. The
        // alternative — a silent failure — leaves a family believing help is
        // coming when the row does not exist.
        requestError =
            'Your phone could not write the request. Nothing was sent.';
      }
      requestingHelp = false;
      _notify();
    });
    return _tail;
  }
```

The read goes through the repository, never through `CareRequestDao`: the presentation layer must not import storage, and Task 5's `careRequestState` is exactly the read that answers "has it gone?" — the fresh write will say `false`, which is the truth on a phone with no signal.

The two remaining actions follow the same shape:

```dart
  /// Call back a request that has not left the phone. The repository refuses once
  /// the server holds the row, and returns false once a worker has answered —
  /// both of which the card has to reflect rather than promise.
  Future<void> withdrawHelp() {
    final check = report;
    if (check == null || !_live) return Future.value();
    _tail = _tail.then((_) async {
      if (!isCurrent()) return;
      final removed = await repository.withdrawCareRequest(
        user,
        scope,
        check.id,
      );
      if (removed) {
        careRequest = null;
        requestSent = false;
      } else if (careRequest != null) {
        // It exists and it will not go away: say which of the two reasons the
        // family is being told, instead of a button that does nothing.
        requestError = requestSent
            ? 'Your request has already reached the health worker. It cannot '
                  'be called back.'
            : 'Your health worker has already answered. That reply stays.';
      }
      _notify();
    });
    return _tail;
  }

  /// Re-read what the phone has actually done with the request. This is the only
  /// honest way for the state to change while the family is looking at it: sync
  /// runs elsewhere, and a pull can bring an answer in between two taps.
  Future<void> refreshRequest() {
    final check = report;
    if (check == null || !_live) return Future.value();
    _tail = _tail.then((_) async {
      if (!isCurrent()) return;
      final state = await repository.careRequestState(user, scope, check.id);
      careRequest = state?.request;
      requestSent = state?.sent ?? false;
      requestError = null;
      _notify();
    });
    return _tail;
  }
```

Add the two imports the new fields need: `../../../domain/entities/care_request.dart` and (for the guard, already present) `../../../domain/services/caregiver_check_policy.dart`. `_notify()` and the `_tail = _tail.then(...)` idiom are copied from `_persist` at `check_controller.dart:458-497`; `_live` is `!_disposed && isCurrent()` at line 64, and `settled` still returns `_tail`, so every test above can await it.

Note the guard branches do not throw. This controller's whole style is that a blocked action leaves a visible reason (`notice`, `blockReason`, `saveState.failed`) rather than an exception the screen has to catch, and the card is a pure widget with no try/catch of its own.

- [x] **Step 5: Run the tests**

Run: `flutter test --no-pub --reporter compact test/caregiver_controller_test.dart 2>&1 | tr '\r' '\n' | tail -25`
Expected: all pass, existing cases unaffected.

- [x] **Step 6: Checkpoint**

`flutter analyze --no-pub 2>&1 | tail -5` must still report 0 errors. Do not commit.

---

### Task 7: The control the family sees

**Files:**
- Create: `lib/presentation/caregiver/check/care_request_card.dart`
- Modify: `lib/presentation/caregiver/check/triage_screen.dart` (inside the `if (check.report != null)` block of `_result`, lines 1119-1145)
- Test: `test/widgets/care_request_card_test.dart`

**Interfaces:**
- Consumes: `CaregiverCheckController.careRequest/requestSent/requestingHelp/requestError`, `askForHelp()`, `withdrawHelp()`, `refreshRequest()` (Task 6), `CaregiverCheckPolicy.canAskForHelp`, `HomeCheckVerdict.label`, `CompanionCard`, `PremiumCheckButton`, `caregiverBody()`.
- Produces: `CareRequestCard({required bool urgent, required String verdictLabel, CareRequest? request, required bool sent, required bool sending, String? error, required VoidCallback onAsk, required VoidCallback onWithdraw, required VoidCallback onRefresh})`.

Verified shapes so the executor does not re-derive them: `CompanionCard({required String title, required Widget child, String? eyebrow, Color? tone})` at `lib/presentation/caregiver/widgets/companion.dart:41`, and `caregiverBody({Color? color, double? size, double? height})` at line 34 of the same file — a plain function, **no `BuildContext`**. `PremiumCheckButton({required String label, required VoidCallback onPressed, IconData? icon, IconData trailingIcon, double height, bool enabled, bool bright})` at `lib/presentation/caregiver/widgets/premium_button.dart:25`. `_result` already has `urgent` and `routine` in scope from `check.decision` (`triage_screen.dart:908-910`), and the file already imports `../widgets/companion.dart`, `../widgets/premium_button.dart`, `../../../core/theme/app_theme.dart` and `../../../domain/services/caregiver_check_policy.dart`.

- [x] **Step 1: Write the failing test**

```dart
/// What the card may and may not promise.
///
/// The waiting state is the dangerous one: a family who believes the app has
/// already called someone may decide not to walk. So every state before a
/// worker's reply repeats the instruction the verdict already gave, no state
/// claims a delivery the phone has not seen, and the primary control does the
/// thing its label says — which is why a withdrawn ask is a state the card
/// enters, not a button it disables.
library;

import 'package:carebridge_ai/domain/entities/care_request.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/caregiver/check/care_request_card.dart';
import 'package:carebridge_ai/presentation/caregiver/widgets/premium_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CareRequest _request({
  CareRequestStatus status = CareRequestStatus.open,
}) =>
    CareRequest(
      id: 'req-chk-1',
      householdId: 'family',
      personId: 'baby',
      level: CareRequestLevel.urgent,
      homeCheckId: 'chk-1',
      createdBy: 'caregiver',
      createdAt: DateTime(2026, 9, 28, 9),
      updatedAt: DateTime(2026, 9, 28, 9),
      status: status,
    );

int asks = 0, withdraws = 0, refreshes = 0;

Future<void> _pump(
  WidgetTester tester, {
  CareRequest? request,
  bool sent = false,
  bool sending = false,
  String? error,
  HomeCheckVerdict verdict = HomeCheckVerdict.urgent,
}) {
  asks = 0;
  withdraws = 0;
  refreshes = 0;
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CareRequestCard(
            urgent: verdict == HomeCheckVerdict.urgent,
            verdictLabel: verdict.label,
            request: request,
            sent: sent,
            sending: sending,
            error: error,
            onAsk: () => asks++,
            onWithdraw: () => withdraws++,
            onRefresh: () => refreshes++,
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an untouched urgent check offers the ask as a real button',
      (tester) async {
    await _pump(tester, request: null);
    expect(find.text('Ask for help'), findsOneWidget);
    expect(find.text('Go to the health facility now'), findsOneWidget);
    await tester.tap(find.widgetWithText(PremiumCheckButton, 'Ask for help'));
    expect(asks, 1);
  });

  testWidgets('the offer says what leaves the phone and what does not',
      (tester) async {
    await _pump(tester, request: null);
    expect(
      find.textContaining("It does not send your answers"),
      findsOneWidget,
    );
  });

  testWidgets('a caution check is told to visit soon, not to run',
      (tester) async {
    await _pump(
      tester,
      request: null,
      verdict: HomeCheckVerdict.caution,
    );
    expect(find.text('Visit the CHW soon'), findsOneWidget);
    expect(find.text('Go to the health facility now'), findsNothing);
  });

  testWidgets('unsent says waiting, says it is not a call-out, and still says '
      'go', (tester) async {
    await _pump(tester, request: _request(), sent: false);
    expect(find.text('Waiting for signal'), findsOneWidget);
    expect(find.textContaining('not a call-out'), findsOneWidget);
    expect(find.text('Go to the health facility now'), findsOneWidget);
    expect(find.widgetWithText(PremiumCheckButton, 'Ask for help'),
        findsNothing);
  });

  testWidgets('a delivery is never claimed before the queue entry is pushed',
      (tester) async {
    await _pump(tester, request: _request(), sent: false);
    expect(find.textContaining('Reached your health worker'), findsNothing);
    expect(find.textContaining('Sent to your health worker'), findsNothing);
  });

  testWidgets('sent says sent, and takes the withdraw away', (tester) async {
    await _pump(tester, request: _request(), sent: true);
    expect(find.textContaining('Sent to your health worker'), findsOneWidget);
    expect(find.text('Waiting for signal'), findsNothing);
    expect(find.text('Cancel the request'), findsNothing);
  });

  testWidgets('an answered request stops telling the family to act alone',
      (tester) async {
    await _pump(
      tester,
      request: _request(status: CareRequestStatus.answered),
      sent: true,
    );
    expect(find.textContaining('Your health worker answered'), findsOneWidget);
    expect(find.text('Cancel the request'), findsNothing);
  });

  testWidgets('an unsent request can be called back', (tester) async {
    await _pump(tester, request: _request(), sent: false);
    await tester.tap(find.text('Cancel the request'));
    await tester.pumpAndSettle();
    expect(withdraws, 1);
  });

  testWidgets('checking is a real action, not a spinner that lies',
      (tester) async {
    await _pump(tester, request: _request(), sent: false);
    await tester.tap(find.text('Check if it has been sent'));
    await tester.pumpAndSettle();
    expect(refreshes, 1);
  });

  testWidgets('sending shows work and offers nothing else', (tester) async {
    await _pump(tester, request: null, sending: true);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.widgetWithText(PremiumCheckButton, 'Ask for help'),
        findsNothing);
  });

  testWidgets('a failed write is named, and the ask stays available',
      (tester) async {
    await _pump(
      tester,
      request: null,
      error: 'Your phone could not write the request. Nothing was sent.',
    );
    expect(find.textContaining('Nothing was sent'), findsOneWidget);
    expect(find.widgetWithText(PremiumCheckButton, 'Ask for help'),
        findsOneWidget);
  });
}
```

- [x] **Step 2: Run it and watch it fail**

Run: `flutter test --no-pub --reporter compact test/widgets/care_request_card_test.dart 2>&1 | tr '\r' '\n' | tail -20`
Expected: `Target of URI doesn't exist: '.../care_request_card.dart'`.

- [x] **Step 3: Write the card**

Create `lib/presentation/caregiver/check/care_request_card.dart`:

```dart
/// The family's request for help, and the only honest thing it can promise at
/// each moment: not yet asked, written but not sent, sent, answered.
///
/// The middle state is the trap. A queued row is not a person on a motorbike, so
/// every state before a worker's reply repeats the instruction the verdict
/// already gave. Nothing here infers delivery from elapsed time — `sent` is read
/// from the outbox by the controller, and `Check if it has been sent` is the
/// family's own way to ask the same question again.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/care_request.dart';
import '../../../domain/enums.dart';
import '../widgets/companion.dart';
import '../widgets/premium_button.dart';

class CareRequestCard extends StatelessWidget {
  const CareRequestCard({
    super.key,
    required this.urgent,
    required this.verdictLabel,
    required this.request,
    required this.sent,
    required this.sending,
    required this.error,
    required this.onAsk,
    required this.onWithdraw,
    required this.onRefresh,
  });

  final bool urgent;
  final String verdictLabel;
  final CareRequest? request;
  final bool sent;
  final bool sending;
  final String? error;
  final VoidCallback onAsk;
  final VoidCallback onWithdraw;
  final VoidCallback onRefresh;

  bool get _answered => request?.status == CareRequestStatus.answered;

  String get _title => switch (request) {
    null => 'Ask for help',
    _ when _answered => 'Your health worker answered',
    _ when sent => 'Sent to your health worker',
    _ => 'Waiting for signal',
  };

  String get _body => switch (request) {
    null =>
      'Send your health worker a request to come to your household today. It '
          'sends the name of the family member you are worried about and how '
          'urgent the check said it is. It does not send your answers.',
    _ when _answered =>
      'They have read your request. ${urgent ? 'Still go now if you can — a '
          'reply does not replace coming to the facility.' : 'Go as the check '
          'advised.'}',
    _ when sent =>
      'Your request is with your health worker. ${urgent ? 'Going to the '
          'facility yourself is still faster than waiting for a visit.' : 'A '
          'visit depends on their day plan, so do not wait at home.'}',
    _ =>
      'Your phone has not reached the network yet, so nobody has been told. '
          'This is not a call-out and will not bring anyone today.',
  };

  @override
  Widget build(BuildContext context) {
    return CompanionCard(
      title: _title,
      eyebrow: request == null ? 'FROM THIS CHECK' : 'YOUR REQUEST',
      tone: urgent ? AppColors.triageRed : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_body),
          if (request != null) const SizedBox(height: 12),
          if (request != null)
            Text(
              urgent ? verdictLabel : 'What the check said: $verdictLabel',
              style: caregiverBody(
                size: 15,
                color: urgent ? AppColors.triageRed : CompanionColors.ink,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error!,
              style: caregiverBody(size: 14, color: AppColors.triageRed),
            ),
          ],
          if (sending)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            )
          else if (request == null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: PremiumCheckButton(
                label: 'Ask for help',
                icon: Icons.campaign_outlined,
                trailingIcon: Icons.arrow_forward_rounded,
                height: 54,
                onPressed: onAsk,
              ),
            )
          else if (!_answered && !sent)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextButton.icon(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Check if it has been sent'),
                  ),
                  TextButton.icon(
                    onPressed: onWithdraw,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.triageRed,
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Cancel the request'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
```

Two wording decisions, one of them corrected on the way in. The instruction line is **prefixed** — `The check said: $verdictLabel` — and shown only once a request exists. The plan's draft printed `HomeCheckVerdict.label` bare (`'Go to the health facility now'`, `lib/domain/enums.dart`), but the result stage's own hero already carries that exact sentence, so a second copy on the same screen reads as a rendering fault rather than emphasis, and it breaks `find.text('Go to the health facility now')`'s `findsOneWidget` in `test/widgets/caregiver_flow_test.dart`. Prefixed-and-conditional keeps one statement per fact. The second half of the decision stands: the phrasing still uses the verdict's own label, not a near-miss invented for the card. And the Twi/Hausa/Dagbani wording for every new English string in this file is **registered work**, not translation-in-place: the card ships English-only, exactly as the rest of the caregiver flow does when a clip is missing.

The titles and bodies that shipped differ from the draft above in wording only, not in meaning — say what the phone knows, never more: `'Ask a health worker to come'` / `'Waiting for network'` / `'Reached your health worker'` / `'Your health worker answered'`, with the unsent body keeping `This is not a call-out and will not bring anyone today.` and the answered body keeping `A reply is not the same thing as someone arriving.` Read `lib/presentation/caregiver/check/care_request_card.dart` for the exact strings; `test/widgets/care_request_card_test.dart` pins all eleven of them.

- [x] **Step 4: Run the widget tests**

Run: `flutter test --no-pub --reporter compact test/widgets/care_request_card_test.dart 2>&1 | tr '\r' '\n' | tail -25`
Expected: `+11: All tests passed!` If `PremiumCheckButton` is not found by `widgetWithText`, read `premium_button.dart`'s build: it renders the label in a `Text` inside its own subtree, which `widgetWithText` does match — so a failure there means the button was not built at all (the `sending`/`request != null` branch).

- [x] **Step 5: Mount it on the result stage**

In `triage_screen.dart`, inside the `if (check.report != null) ...[` collection at line 1119, immediately after `_TellSomeoneCard(message: nurseMsg); const SizedBox(height: 16),` (lines 1122-1123) and before the `_WatchCard`/`_RecheckPromiseCard` branch:

```dart
          if (CaregiverCheckPolicy.canAskForHelp(check.report!.verdict)) ...[
            CareRequestCard(
              urgent: check.report!.verdict == HomeCheckVerdict.urgent,
              verdictLabel: check.report!.verdict.label,
              request: check.careRequest,
              sent: check.requestSent,
              sending: check.requestingHelp,
              error: check.requestError,
              onAsk: () {
                check.askForHelp();
              },
              onWithdraw: () {
                check.withdrawHelp();
              },
              onRefresh: () {
                check.refreshRequest();
              },
            ),
            const SizedBox(height: 16),
          ],
```

Placing it there, rather than at the bottom by `Feeding and comfort`, is the point: it sits between "tell someone" and "watch for this", which is where a family deciding whether to leave the house right now reads it. The gate is `canAskForHelp(report!.verdict)`, not the local `urgent`/`routine` booleans from `check.decision` — the request is about the report that was actually saved, and an all-clear check must show nothing at all rather than a greyed-out ask. Add `import 'care_request_card.dart';` alongside the sibling `check_controller.dart` import.

- [x] **Step 6: Run the caregiver set**

Run: `flutter test --no-pub --reporter compact test/widgets/caregiver_check_entry_test.dart test/widgets/caregiver_question_stage_test.dart test/widgets/caregiver_flow_test.dart test/caregiver_planners_test.dart test/caregiver_state_test.dart 2>&1 | tr '\r' '\n' | tail -25`
Expected: all pass, and the new card does not push the existing result-stage cases out of view — if a `caregiver_flow_test` case looks for a widget by `find.text` on the result stage and now matches two, the card has duplicated a line the stage already said; change the card's wording, not the assertion.

What happened: `+69 -1`, `A RenderFlex overflowed by 70 pixels on the right` in *the stage holds together on a 320px handset at 200% text* (`test/widgets/caregiver_question_stage_test.dart:253`). Attributed before fixing, as this plan requires: with the mount gate temporarily forced false the failure reproduced identically, and a `FlutterError.onError` probe named the culprit — `_CareConstellation`'s header `Row` (`triage_screen.dart:2116`), where an unshrinkable `YOUR CARE PATH` plus a trailing `Spacer` and `N of 8 answered` exceed 280px at 2× text. That widget is part of the uncommitted caregiver restyle already in this tree, not of this plan; the questions stage never builds the card. Fixed here anyway because the caregiver set must be green to hand over: the eyebrow is now `Expanded` with `overflow: TextOverflow.ellipsis` and the count keeps its own trailing slot, so the layout is unchanged at normal text and the count is never pushed off at large text. The probe edits were reverted; the six-file run (the five above plus `test/widgets/care_request_card_test.dart`) ends `+81: All tests passed!`.

- [x] **Step 7: Checkpoint**

`flutter analyze --no-pub 2>&1 | tail -5`: 0 errors. Do not commit.

---

### Task 8: Verify, including the part only a picture shows

**Files:** none (verification only).

- [x] **Step 1: Full suite**

Run: `flutter test --no-pub --reporter compact 2>&1 | tr '\r' '\n' | tail -30`
Expected: the suite grows by roughly 53 tests across the seven new and extended files (`care_request_test`, `care_request_dao_test`, the server-contract test, `care_request_pull_test`, `care_request_repository_test`, the `asking for help` group in `caregiver_controller_test`, `care_request_card_test`), and the only failures left are the four in `test/pre_referral_dispensing_test.dart` named in Global Constraints. Everything else is this plan's to fix. Do not assume that list stayed still: the FHW desk and the audio files are being edited in this worktree by another session, so a failure in `referral_follow_up_test.dart` or any audio test must be attributed before it is fixed. If one of them fails in a full run but passes when run alone, it is tool contention or the other session, not this plan.

Outcome: `+984 ~4 -28`. All six `care_request*` files and the extended caregiver files passed — none appears in the failure list. The four allowed `pre_referral_dispensing_test` failures are present. The other 24 are **not** contention: each file reproduces its failures when run alone (`caregiver_hub_test` `+3 -8`, `caregiver_language_warmup_test` `+0 -8`, `fhw_clinic_header_test` `+17 -4`, `fhw_today_tab_test` `+6 -4`), and each names a widget this plan never opened —

- 16 in the caregiver hub and warm-up group: `A RenderFlex overflowed by 66 pixels on the right`, error-causing widget `Row` at `lib/presentation/caregiver/family/family_tab.dart:387`, plus a missing `'Local-only notes and home checks are not…'` line. `family_tab.dart` was last written by the concurrent Aura Nurture session, and contains no reference to `CareRequest`, `care_request` or `requestCare` (grep count 0).
- 4 in `fhw_clinic_header_test`: `'Nakpayili & Kpalbusi CHPS Zone'` now matches two widgets and `'Care starts here.'` matches none — FHW header copy, another session's file.
- 4 in `fhw_today_tab_test`: missing `'Care starts here.'`, `'1 patient in the clinic queue'`, `'1 urgent referral awaiting arrival'`, `'Working offline · 0 changes waiting to…'` — the FHW Today tab, another session's file.

Left unfixed deliberately: all four groups are the concurrent session's in-flight surfaces in a shared worktree, and a second hand in a layout they are mid-way through rewriting destroys more than it repairs. They are reported instead, with the counts above so the owner can see the suite is not green because of this plan or despite it.

- [x] **Step 2: Analyzer baseline**

Run: `flutter analyze --no-pub 2>&1 | tail -5`
Expected: no line matching `^\s+(error|warning)`. The issue *count* belongs to whoever moves last in this shared tree, so compare it with the count recorded before this plan's first edit and check that none of the remaining lines name a file this plan touched.

Outcome: `30 issues found` — identical to the count recorded before this plan's first edit, zero lines matching `error`, and the only two `warning` lines are unused imports in `test/widgets/result_page_simplification_test.dart`, which this plan never touched. Filtering the report for every file this plan edited returns nothing.

- [x] **Step 3: Scratch goldens of the four states**

The waiting state is where a wrong layout could make a family stay home. Follow the project's throwaway-golden recipe: `test/care_request_golden_scratch_test.dart`, `GoogleFonts.config.allowRuntimeFetching = false`, `tester.view.physicalSize`, `--update-goldens`, Read the PNGs, copy them to the gitignored `.qoder_screens/`, then delete the scratch file and the goldens it wrote. Raw `fontFamily: 'Sora'` renders as black boxes under that harness — an artefact of the font bundling, not a bug.

Pump `CareRequestCard` in all four states — no request, request unsent, request sent, request answered — plus the `sending` and `error` variants, at 320dp width and again at 200% text scale. Check three things in the pictures, in this order: the verdict instruction line is visible in every state that has a request; no state shows both the ask button and a status title; and the cancel/check row does not push the go-now line off the card at large text.

Outcome: 14 PNGs (`ask`, `sending`, `error`, `waiting`, `sent`, `answered`, `caution` at 1× and 2×; the first pass was retaken with a 2000px-tall viewport because at 2× the card is taller than 900px and the first capture clipped the cancel row). All three checks hold: the `The check said: …` line is present in `waiting`, `sent`, `answered` and `caution` and absent only in the states with no request; the ask button appears in `ask`/`sending`/`error` and never beside a status title; and at 2× the go-now line sits above both controls with nothing pushed off. Two artefacts named so nobody chases them: the card title renders as solid red/navy blocks (raw `Sora` under `allowRuntimeFetching = false`) and Material glyphs as empty squares — both harness-only. One real observation kept: at 2× the ask label wraps to two lines inside the 54px pill, which is `PremiumCheckButton`'s documented contract (`maxLines: 2`, "the label wraps instead of overflowing at large text scales") and not clipped, so the card passes the blame upward rather than working around it. Scratch file and `test/goldens/` deleted; the PNGs live in `.qoder_screens/`.

- [x] **Step 4: Confirm nothing leaked into git**

Run: `git status --short`. `assets/tts/hausa_piper/model.onnx`, `assets/tts/twi_piper/model.onnx`, `.tmp_dl/` and `.qoder/settings.local.json` must remain untracked and unstaged. Do not commit or push unless the owner asks.

Outcome: all four still read `??` (untracked, unstaged). `git diff --cached --name-only` lists exactly two paths — the `check_types.dart` and `feeding_card.dart` deletions that were already staged when this plan started — so this plan staged nothing and committed nothing. The scratch golden harness and `test/goldens/` are gone from the tree.

- [x] **Step 5: Report**

State plainly what a family can now do (ask for a worker from an urgent or caution result, see whether it left the phone, call it back while it has not), and what still does not exist:

- the CHO day-plan card and the desk that answers a request — specified in the spec, deliberately not built;
- end-of-day escalation to the supervisor zone list;
- the worker's own answer action (a pulled `answered` status can only arrive from a server row a worker writes, and nothing writes one yet);
- Twi, Hausa and Dagbani wording for every new English string in `care_request_card.dart` — registered speech-bank work, never translated in place.

Name the defects found on the way, with file:line — checked against the tree before being repeated, because two of the three this plan suspected turned out differently:

- **Holds:** `barrier_reports` and `scheduled_contacts` are push-only. `PULL_TABLES` in `server/src/pull.js:48-57` carries households, persons, visits, assessments, referrals and now care_requests, and nothing else, so a row written to either of those tables is invisible to every other device. `care_requests` was registered there precisely to avoid joining that list.
- **Corrected:** the referral nag is not in the planner. `lib/data/sync/pull_service.dart:377-384` merges visits, assessments and referrals with `_mergeIfAbsent`, so a worker's status change never lands on the family's phone and `caregiver_today_planner.dart:110` (`if (!referral.status.isOpen) continue;`) keeps surfacing a referral the clinic already closed. The planner is right; the merge is the defect.
- **Corrected:** `_mergeLww` does normalise `sync_state` — for `care_requests` only, at `pull_service.dart:365-371`, which passes `{...row, 'sync_state': 'synced'}`. The general gap is on the other side: a push never rewrites an entity row, only `outbox.synced_at` (`lib/data/local/outbox_dao.dart:201`), so a locally-written request still reads `pending` in its own `sync_state` after delivery. That is why `CareRequestDao.isSent` asks the outbox.
- **Closed during verification:** `server/scripts/verify-pull.js`'s two hand-maintained table lists (the delta-pull check) now include `care_requests`, so the server verifier proves the table arrives in a pull response; `node --check` passes, and the script itself needs a live MySQL, so it was not executed here. `lib/data/local/app_database.dart:16` claimed a 14-table schema where the file hand-creates 23; corrected.
- **Left where it belongs:** 24 suite failures in `family_tab.dart`, the FHW clinic header and the FHW Today tab, all in the concurrent session's in-flight surfaces (attribution in Task 8 Step 1).

---

---

## Spec coverage (self-review)

The spec's seven testing commitments, and where each one is actually enforced:

| Spec item | Task |
| --- | --- |
| 1. Policy — which verdicts raise a request; routine never does | Task 1 (`CareRequest.levelFor(fine)` is null, `test/care_request_test.dart`) and Task 6 Step 3 (`canAskForHelp`), pinned by the controller's all-clear case |
| 2. Payload — fails if answers, sign names or MUAC reach the serialized request | Task 1 Step 1, the key-set and two content assertions |
| 3. DAO atomicity and `SyncPriority.critical` | Task 2 Step 1, the create and rollback tests (`priority == 0`) |
| 4. Repository gate — own household passes, another household and a worker without `requestCare` raise `AccessDenied` | Task 5 Step 1 |
| 5. Idempotency — a second confirm does not create a second row | Task 5 (`forCheck` returns the existing row) and Task 6's "asking twice summons one health worker" |
| 6. Widget — the states render and the waiting state carries the go-now line | Task 7 Step 1 |
| 7. Offline — the check completes, the request is written, nothing pretends to have been sent | Task 2 (`isSent` false until `synced_at`), Task 6's failed-write case, Task 7's "a delivery is never claimed before the queue entry is pushed" |

And the parts of the spec this plan deliberately does **not** build, so an executor does not start them: the CHO day-plan card, end-of-day escalation to the supervisor's zone list, and the worker's answer action. `CareRequestStatus.answered` exists in the schema and in the pull merge so that half needs no second migration, but nothing in this pass writes it — a family's card can therefore only ever read `open`.
