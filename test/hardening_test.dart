/// The hardening batch: deletion that deletes, a protection class the policy
/// honours, anchors the district can check, patterns no single entry can show, and
/// an erasure a family can actually receive.
///
/// The pure decisions come first and need no database, because the interesting
/// question about a policy engine is not "does it write rows" but "what does it
/// answer when the answer is uncomfortable" — a mother's own marked record, a
/// convulsing child, a colleague in the same district.
library;

import 'dart:convert';
import 'dart:io';

import 'package:carebridge_ai/data/local/app_database.dart';
import 'package:carebridge_ai/data/local/compliance_dao.dart';
import 'package:carebridge_ai/data/local/household_dao.dart';
import 'package:carebridge_ai/data/repositories/care_repository.dart';
import 'package:carebridge_ai/data/repositories/record_access.dart';
import 'package:carebridge_ai/domain/compliance.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

final _t0 = DateTime.utc(2026, 10, 18, 9, 14);

const _owner = AppUser(
  id: 'u-owner',
  fullName: 'Aminata Fusena',
  phone: '0244000001',
  role: UserRole.frontlineHealthWorker,
  region: 'Northern Region',
  district: 'Savelugu Municipal',
  community: 'Gushegu',
);

/// Same region, same district, not the worker who registered the household — the
/// colleague whose whole relationship to a protected record is the point of the
/// protection class.
const _colleague = AppUser(
  id: 'u-colleague',
  fullName: 'Ibrahim Lukpin',
  phone: '0244000002',
  role: UserRole.frontlineHealthWorker,
  region: 'Northern Region',
  district: 'Savelugu Municipal',
  community: 'Tolon',
);

const _mother = AppUser(
  id: 'u-mother',
  fullName: 'Abena Yeboah',
  phone: '0244000003',
  role: UserRole.caregiver,
  region: 'Northern Region',
  district: 'Savelugu Municipal',
  community: 'Gushegu',
);

const _household = Household(
  id: 'hh-1',
  name: 'The Yeboah family',
  region: 'Northern Region',
  district: 'Savelugu Municipal',
  community: 'Gushegu',
  createdBy: 'u-owner',
);

const _marked = Person(
  id: 'p-marked',
  householdId: 'hh-1',
  fullName: 'Akosia Yeboah',
  clientType: ClientType.childUnderFive,
  ageYearsApprox: 2,
  phone: '0200000009',
  nhisNumber: 'NHIS-7788',
  sensitivity: 'hivAndSti',
);

/// An [AccessContext] assembled by hand, for the decisions that need no store.
AccessContext _ctx({
  required AppUser actor,
  bool sensitive = false,
  bool ownCaseload = false,
  bool responsibleWorker = false,
  bool dataSubject = false,
  bool consent = false,
}) => AccessContext(
  actor: actor,
  household: _household,
  subjectPersonId: _marked.id,
  isOwnCaseload: ownCaseload,
  isDataSubject: dataSubject,
  crossFacilityConsent: consent,
  isSensitive: sensitive,
  isResponsibleWorker: responsibleWorker,
  now: _t0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── The protection class in the policy ──────────────────────────────
  group('the protection class in the policy', () {
    test('a colleague in the same district is refused, with a way forward', () {
      final d = RecordAccess.decide(
        _ctx(
          actor: _colleague,
          sensitive: true,
          ownCaseload: true,
          consent: true,
        ),
        purpose: AccessPurpose.continuingCare,
      );
      expect(d.allowed, isFalse);
      expect(d.canBreakGlass, isTrue);
      expect(
        d.flagged,
        isTrue,
        reason: 'A refused look is still worth reading.',
      );
      expect(d.reason, contains('say why you need it'));
    });

    test('consent to be found does not unlock a protected record', () {
      // The narrowest case in the register: the family agreed to continuity of
      // care, which is not agreement to disclose an HIV status.
      final d = RecordAccess.decide(
        _ctx(actor: _colleague, sensitive: true, consent: true),
        purpose: AccessPurpose.continuingCare,
      );
      expect(d.basis, AccessBasis.none);
      expect(d.allowed, isFalse);
    });

    test('the responsible worker opens it without justifying herself', () {
      final d = RecordAccess.decide(
        _ctx(
          actor: _owner,
          sensitive: true,
          ownCaseload: true,
          responsibleWorker: true,
        ),
        purpose: AccessPurpose.continuingCare,
      );
      expect(d.allowed, isTrue);
      expect(d.basis, AccessBasis.careRelationship);
      expect(d.flagged, isFalse);
      expect(d.note, contains('worker responsible for it'));
    });

    test('an emergency is never blocked by a marking', () {
      final d = RecordAccess.decide(
        _ctx(actor: _colleague, sensitive: true),
        purpose: AccessPurpose.emergency,
      );
      expect(d.allowed, isTrue);
      expect(d.basis, AccessBasis.vitalInterest);
      expect(d.flagged, isTrue);
    });

    test('a stated reason turns the refusal into a recorded opening', () {
      final d = RecordAccess.decide(
        _ctx(actor: _colleague, sensitive: true),
        purpose: AccessPurpose.continuingCare,
        breakGlassReason: 'Referred at the clinic, mother unknown to us',
      );
      expect(d.allowed, isTrue);
      expect(d.basis, AccessBasis.breakGlass);
      expect(d.flagged, isTrue);
      // Verbatim: this is the sentence a reviewer reads and the family is shown.
      expect(d.note, 'Referred at the clinic, mother unknown to us');
    });

    test('a blank reason is not a reason', () {
      final d = RecordAccess.decide(
        _ctx(actor: _colleague, sensitive: true),
        purpose: AccessPurpose.continuingCare,
        breakGlassReason: '   ',
      );
      expect(d.allowed, isFalse);
    });

    test('the family is never asked to justify reading their own record', () {
      final d = RecordAccess.decide(
        _ctx(actor: _mother, sensitive: true, dataSubject: true),
        purpose: AccessPurpose.ownRecord,
      );
      expect(d.allowed, isTrue);
      expect(d.basis, AccessBasis.dataSubject);
      expect(d.flagged, isFalse);
    });

    test('an unreadable marking fails closed', () {
      // A category from a newer build, or a hand-edited value: still protected.
      expect(
        const Person(
          id: 'p',
          householdId: 'h',
          fullName: 'X',
          clientType: ClientType.childUnderFive,
          sensitivity: 'gene_editing_v2',
        ).isSensitive,
        isTrue,
      );
      expect(_marked.isSensitive, isTrue);
      expect(SensitivityCategory.fromStored('gene_editing_v2'), isNull);
      expect(
        SensitivityCategory.fromStored(_marked.sensitivity),
        SensitivityCategory.hivAndSti,
      );
    });

    test('an ordinary record keeps the old, wider rule', () {
      final d = RecordAccess.decide(
        _ctx(actor: _colleague, ownCaseload: true),
        purpose: AccessPurpose.continuingCare,
      );
      expect(d.allowed, isTrue);
      expect(d.flagged, isFalse);
      expect(d.note, contains('caseload'));
    });
  });

  // ── The marking and the erasure are representable ───────────────────
  group('the marking and the erasure are representable', () {
    test('sensitivity survives the map round trip', () {
      final map = _marked.toMap();
      expect(map['sensitivity'], 'hivAndSti');
      expect(Person.fromMap(map).sensitivity, 'hivAndSti');
      expect(Person.fromMap(map).isSensitive, isTrue);
    });

    test('a marking can be lifted and moved', () {
      expect(_marked.withSensitivity(null).isSensitive, isFalse);
      expect(
        _marked.withSensitivity('mentalHealth').sensitivity,
        'mentalHealth',
      );
    });

    test('erasure removes identifiers and keeps the clinical skeleton', () {
      final erased = _marked.withoutIdentifiers();
      expect(erased.isErased, isTrue);
      expect(erased.fullName, Person.erasedName);
      expect(erased.phone, isNull);
      expect(erased.nhisNumber, isNull);
      // What the record is *for* survives: the child stays a child, in the same
      // household, with the same age — otherwise every retained clinical reading
      // becomes a number with no axis.
      expect(erased.id, _marked.id);
      expect(erased.householdId, _marked.householdId);
      expect(erased.clientType, _marked.clientType);
      expect(erased.ageYearsApprox, _marked.ageYearsApprox);
      expect(erased.sensitivity, _marked.sensitivity);
    });

    test('a household erases on the same terms', () {
      final erased = _household.withoutIdentifiers();
      expect(erased.isErased, isTrue);
      expect(erased.contactPhone, isNull);
      expect(erased.headName, isNull);
      // Region and district stay: they name no one and the service is planned on
      // them.
      expect(erased.district, _household.district);
    });
  });

  // ── Deletion that deletes ───────────────────────────────────────────
  group('deletion that deletes', () {
    testWidgets('the register is opened with the pragma in force', (
      tester,
    ) async {
      _prepareRegister(tester);
      await tester.runAsync(() async {
        final db = await AppDatabase.instance.database;
        final rows = await db.rawQuery('PRAGMA secure_delete');
        expect(
          '${rows.first.values.first}',
          anyOf('1', 'on', 'true', 'YES'),
          reason:
              'The register opens with secure_delete off, which means a deleted '
              'name is still readable bytes in the file.',
        );
      });
    });

    /// The contrast, on a throwaway database: without the pragma a deleted name
    /// is still in the file, with it the page is zeroed. Testing only the "after"
    /// would prove nothing, because a plain SQLite delete also appears to work.
    testWidgets('the pragma is what removes the bytes', (tester) async {
      await tester.runAsync(() async {
        const secret = 'Zongomama Watchpole';
        expect(
          await _bytesAfterDelete(secure: false),
          contains(secret),
          reason: 'Control failed: bytes vanished without the pragma.',
        );
        expect(
          await _bytesAfterDelete(secure: true),
          isNot(contains(secret)),
          reason:
              'secure_delete is on and the name is still recoverable, so the '
              'register claims an erasure the engine does not perform.',
        );
      });
    });
  });

  // ── The ledger and its anchors ──────────────────────────────────────
  group('the ledger and its anchors', () {
    testWidgets(
      'every tenth entry commits the chain position out of the device',
      (tester) async {
        _prepareRegister(tester);
        await tester.runAsync(() async {
          final db = await AppDatabase.instance.database;
          await _seedFamily(db);
          for (var i = 0; i < AccessLedgerDao.anchorEvery; i++) {
            await _appendOpen(
              db,
              actor: _owner,
              deviceId: 'cb-anchor',
              at: _t0.add(Duration(minutes: i)),
            );
          }
          expect(
            await _outboxCount(db, Tables.accessLedger),
            AccessLedgerDao.anchorEvery,
          );
          expect(await _outboxCount(db, 'ledger_anchors'), 1);

          final queued = await db.query(
            Tables.outbox,
            columns: ['payload_json'],
            where: 'entity_table = ?',
            whereArgs: ['ledger_anchors'],
          );
          final payload =
              jsonDecode(queued.first['payload_json'] as String)
                  as Map<String, dynamic>;
          expect(payload['device_id'], 'cb-anchor');
          expect(payload['seq'], AccessLedgerDao.anchorEvery);
          expect(payload['entry_count'], AccessLedgerDao.anchorEvery);
          expect(await AccessLedgerDao.verify(), isA<ChainIntact>());
          // The anchor commits to the hash really sitting at that position — which
          // is the only reason a later mismatch means anything.
          final at10 = await db.query(
            Tables.accessLedger,
            columns: ['entry_hash'],
            where: 'seq = ?',
            whereArgs: [AccessLedgerDao.anchorEvery],
          );
          expect(payload['entry_hash'], at10.first['entry_hash']);
        });
      },
    );

    testWidgets('a short trail is not anchored', (tester) async {
      _prepareRegister(tester);
      await tester.runAsync(() async {
        final db = await AppDatabase.instance.database;
        await _seedFamily(db);
        for (var i = 0; i < AccessLedgerDao.anchorEvery - 1; i++) {
          await _appendOpen(
            db,
            actor: _owner,
            deviceId: 'cb-anchor',
            at: _t0.add(Duration(minutes: i)),
          );
        }
        expect(await _outboxCount(db, 'ledger_anchors'), isZero);
      });
    });

    testWidgets('a device with no identity anchors nothing it cannot name', (
      tester,
    ) async {
      _prepareRegister(tester);
      await tester.runAsync(() async {
        final db = await AppDatabase.instance.database;
        await _seedFamily(db);
        for (var i = 0; i < AccessLedgerDao.anchorEvery; i++) {
          await _appendOpen(db, actor: _owner, deviceId: null, at: _t0);
        }
        expect(
          await _outboxCount(db, 'ledger_anchors'),
          isZero,
          reason:
              'An anchor without a device id cannot be checked against anything, '
              'and a server full of them looks like coverage.',
        );
      });
    });
  });

  // ── Patterns no single entry can show ───────────────────────────────
  group('patterns no single entry can show', () {
    testWidgets('one worker, many unrelated families', (tester) async {
      _prepareRegister(tester);
      await tester.runAsync(() async {
        final db = await AppDatabase.instance.database;
        await _insertUser(db, _owner);
        for (var i = 0; i < CareRepository.patternActorThreshold; i++) {
          final hh = Household(
            id: 'hh-out$i',
            name: 'Outside family $i',
            region: 'Ashanti Region',
            district: 'Ejisu Municipal',
            community: 'Ejisu',
            createdBy: _owner.id,
          );
          await HouseholdDao.upsert(hh);
          final p = Person(
            id: 'p-out$i',
            householdId: hh.id,
            fullName: 'Person $i',
            clientType: ClientType.childUnderFive,
            ageYearsApprox: 3,
          );
          await PersonDao.upsert(p);
          await _appendOpen(
            db,
            actor: _owner,
            subject: p.id,
            deviceId: 'cb-pattern',
            at: _t0.add(Duration(minutes: i)),
          );
        }

        final found = await AccessLedgerDao.patterns(
          since: _t0.subtract(const Duration(days: 1)),
          actorThreshold: CareRepository.patternActorThreshold,
        );
        final volume = found.where(
          (p) => p.kind == AccessPatternKind.outOfCaseloadVolume,
        );
        expect(volume, hasLength(1));
        final hit = volume.first;
        expect(hit.count, CareRepository.patternActorThreshold);
        expect(hit.actorName, _owner.fullName);
        // Counts, not accusations: the sentence has to survive being read aloud in
        // a district meeting.
        expect(hit.sentence, contains('different family records'));
        expect(hit.sentence, isNot(contains('misuse')));
      });
    });

    testWidgets('several workers on one protected record', (tester) async {
      _prepareRegister(tester);
      await tester.runAsync(() async {
        final db = await AppDatabase.instance.database;
        await _seedFamily(db);
        for (var i = 0; i < CareRepository.patternSubjectThreshold; i++) {
          final worker = _workerNamed('Worker $i', 'u-w$i', '024499${i}000');
          await _insertUser(db, worker);
          await _appendOpen(
            db,
            actor: worker,
            deviceId: 'cb-pattern',
            at: _t0.add(Duration(minutes: i)),
          );
        }

        final found = await AccessLedgerDao.patterns(
          since: _t0.subtract(const Duration(days: 1)),
          subjectThreshold: CareRepository.patternSubjectThreshold,
        );
        final shared = found.where(
          (p) => p.kind == AccessPatternKind.sharedSensitiveSubject,
        );
        expect(shared, hasLength(1));
        expect(shared.first.count, CareRepository.patternSubjectThreshold);
        expect(shared.first.subjectName, _marked.fullName);
      });
    });

    testWidgets('an unmarked record does not raise the second detector', (
      tester,
    ) async {
      _prepareRegister(tester);
      await tester.runAsync(() async {
        final db = await AppDatabase.instance.database;
        await _seedFamily(db, person: _marked.withSensitivity(null));
        for (var i = 0; i < CareRepository.patternSubjectThreshold; i++) {
          final worker = _workerNamed('Worker $i', 'u-v$i', '024488${i}000');
          await _insertUser(db, worker);
          await _appendOpen(
            db,
            actor: worker,
            deviceId: 'cb-pattern',
            at: _t0.add(Duration(minutes: i)),
          );
        }

        final found = await AccessLedgerDao.patterns(
          since: _t0.subtract(const Duration(days: 1)),
          subjectThreshold: CareRepository.patternSubjectThreshold,
        );
        expect(
          found.where(
            (p) => p.kind == AccessPatternKind.sharedSensitiveSubject,
          ),
          isEmpty,
          reason:
              'Three colleagues sharing one district caseload is ordinary work. '
              'Reporting it would teach the supervisor to skip this queue.',
        );
      });
    });

    testWidgets('a review row is not counted as an access', (tester) async {
      _prepareRegister(tester);
      await tester.runAsync(() async {
        final db = await AppDatabase.instance.database;
        await _insertUser(db, _owner);
        for (var i = 0; i < CareRepository.patternActorThreshold; i++) {
          await _appendOpen(
            db,
            actor: _owner,
            subject: 'p-reviewed-$i',
            deviceId: 'cb-pattern',
            action: AccessLedgerDao.reviewAction,
            at: _t0.add(Duration(minutes: i)),
          );
        }
        final found = await AccessLedgerDao.patterns(
          since: _t0.subtract(const Duration(days: 1)),
          actorThreshold: CareRepository.patternActorThreshold,
        );
        expect(
          found.where((p) => p.kind == AccessPatternKind.outOfCaseloadVolume),
          isEmpty,
          reason:
              'A supervisor writing down conclusions must not become the '
              'pattern the detector is reporting.',
        );
      });
    });

    testWidgets('nothing beyond the window is reported', (tester) async {
      _prepareRegister(tester);
      await tester.runAsync(() async {
        final db = await AppDatabase.instance.database;
        await _seedFamily(db);
        await _insertUser(db, _owner);
        await _appendOpen(
          db,
          actor: _owner,
          deviceId: 'cb-pattern',
          at: _t0.subtract(const Duration(days: 3)),
        );
        final found = await AccessLedgerDao.patterns(
          since: _t0.subtract(CareRepository.patternWindow),
        );
        expect(found, isEmpty);
      });
    });

    testWidgets('the desk asks, and a family account is refused', (
      tester,
    ) async {
      _prepareRegister(tester);
      await tester.runAsync(() async {
        final db = await AppDatabase.instance.database;
        final repo = CareRepository(clock: () => _t0);
        await _seedFamily(db);
        expect(await repo.accessPatterns(_owner), isEmpty);
        await expectLater(
          repo.accessPatterns(_mother),
          throwsA(isA<AccessDenied>()),
        );
      });
    });
  });

  // ── Erasure a family can receive ────────────────────────────────────
  group('erasure a family can receive', () {
    late CareRepository repo;
    setUp(() => repo = CareRepository(clock: () => _t0));

    testWidgets('identifiers go, history stays, the act is on the trail', (
      tester,
    ) async {
      _prepareRegister(tester);
      await tester.runAsync(() async {
        final db = await AppDatabase.instance.database;
        await _seedFamily(db);
        // The clinical history the resolution promises to keep. It is a child row
        // of the person, so an erasure that rewrote the person with INSERT OR
        // REPLACE would cascade it away and the promise would be false.
        await db.insert(Tables.growthMeasurements, {
          'id': 'g-keep',
          'person_id': _marked.id,
          'taken_at': _t0.toIso8601String(),
          'weight_kg': 9.4,
        });
        await DataRightsDao.open(
          id: 'req-1',
          subjectPersonId: _marked.id,
          right: DataRight.erasure,
          requestedBy: _mother.id,
          at: _t0,
        );

        await repo.eraseIdentifiers(_owner, requestId: 'req-1');

        final stored = Person.fromMap(
          (await db.query(
            Tables.persons,
            where: 'id = ?',
            whereArgs: [_marked.id],
          )).first,
        );
        expect(stored.isErased, isTrue);
        expect(stored.phone, isNull);
        expect(stored.nhisNumber, isNull);
        expect(stored.clientType, ClientType.childUnderFive);
        final kept = await db.query(
          Tables.growthMeasurements,
          where: 'person_id = ?',
          whereArgs: [_marked.id],
        );
        expect(
          kept,
          hasLength(1),
          reason:
              'The resolution says clinical history is kept without names. If '
              'the erasure cascades the measurements away, that sentence is a '
              'lie told to a family.',
        );

        final request = await DataRightsDao.byId('req-1');
        expect(request!.status, RequestStatus.fulfilled);
        // The resolution must say what was kept, or the answer reads as a refusal
        // that has been dressed up.
        expect(request.resolution, contains('Clinical history kept'));

        final ledger = await db.query(
          Tables.accessLedger,
          where: 'action = ?',
          whereArgs: ['erase_identifiers'],
        );
        expect(ledger, hasLength(1));
        expect(ledger.first['basis'], AccessBasis.officialAuthority.name);
        expect(ledger.first['flagged'], 0);
        expect(await AccessLedgerDao.verify(), isA<ChainIntact>());
      });
    });

    testWidgets('the erasure travels, in the same writes as the change', (
      tester,
    ) async {
      _prepareRegister(tester);
      await tester.runAsync(() async {
        final db = await AppDatabase.instance.database;
        await _seedFamily(db);
        await DataRightsDao.open(
          id: 'req-2',
          subjectPersonId: _marked.id,
          right: DataRight.erasure,
          requestedBy: _mother.id,
          at: _t0,
        );
        await repo.eraseIdentifiers(_owner, requestId: 'req-2');

        final tables = (await db.query(
          Tables.outbox,
          columns: ['entity_table'],
        )).map((r) => r['entity_table']).toSet();
        // A district that never learns of the erasure keeps serving the name.
        expect(tables, contains(Tables.persons));
        expect(tables, contains(Tables.dataRightsRequests));
        expect(tables, contains(Tables.accessLedger));
      });
    });

    testWidgets('the household goes with the last of its people', (
      tester,
    ) async {
      _prepareRegister(tester);
      await tester.runAsync(() async {
        final db = await AppDatabase.instance.database;
        await _seedFamily(db);
        await DataRightsDao.open(
          id: 'req-3',
          subjectPersonId: _marked.id,
          right: DataRight.erasure,
          requestedBy: _mother.id,
          at: _t0,
        );
        await repo.eraseIdentifiers(_owner, requestId: 'req-3');

        expect((await HouseholdDao.byId(_household.id))!.isErased, isTrue);
      });
    });

    testWidgets('a family with another member standing keeps its name', (
      tester,
    ) async {
      _prepareRegister(tester);
      await tester.runAsync(() async {
        final db = await AppDatabase.instance.database;
        await _seedFamily(db);
        await PersonDao.upsert(
          const Person(
            id: 'p-sibling',
            householdId: 'hh-1',
            fullName: 'Yaw Yeboah',
            clientType: ClientType.childUnderFive,
            ageYearsApprox: 4,
          ),
        );
        await DataRightsDao.open(
          id: 'req-4',
          subjectPersonId: _marked.id,
          right: DataRight.erasure,
          requestedBy: _mother.id,
          at: _t0,
        );
        await repo.eraseIdentifiers(_owner, requestId: 'req-4');

        final hh = await HouseholdDao.byId(_household.id);
        // Erasing a home for one request would punish the child who did not ask.
        expect(hh!.isErased, isFalse);
        expect(hh.name, _household.name);
      });
    });

    testWidgets('a request that is not an erasure cannot destroy anything', (
      tester,
    ) async {
      _prepareRegister(tester);
      await tester.runAsync(() async {
        final db = await AppDatabase.instance.database;
        await _seedFamily(db);
        await DataRightsDao.open(
          id: 'req-5',
          subjectPersonId: _marked.id,
          right: DataRight.rectification,
          requestedBy: _mother.id,
          at: _t0,
        );
        await expectLater(
          repo.eraseIdentifiers(_owner, requestId: 'req-5'),
          throwsA(isA<ErasureRefused>()),
        );
        expect((await PersonDao.byId(_marked.id))!.fullName, _marked.fullName);
      });
    });

    testWidgets('a second erasure of an answered request is refused', (
      tester,
    ) async {
      _prepareRegister(tester);
      await tester.runAsync(() async {
        final db = await AppDatabase.instance.database;
        await _seedFamily(db);
        await DataRightsDao.open(
          id: 'req-6',
          subjectPersonId: _marked.id,
          right: DataRight.erasure,
          requestedBy: _mother.id,
          at: _t0,
        );
        await repo.eraseIdentifiers(_owner, requestId: 'req-6');
        await expectLater(
          repo.eraseIdentifiers(_owner, requestId: 'req-6'),
          throwsA(
            isA<ErasureRefused>().having(
              (e) => e.message,
              'message',
              contains('already been answered'),
            ),
          ),
        );
      });
    });

    testWidgets('a request naming a record not on this device is refused', (
      tester,
    ) async {
      _prepareRegister(tester);
      await tester.runAsync(() async {
        final db = await AppDatabase.instance.database;
        await DataRightsDao.open(
          id: 'req-7',
          subjectPersonId: 'p-nowhere',
          right: DataRight.erasure,
          requestedBy: _mother.id,
          at: _t0,
        );
        await expectLater(
          repo.eraseIdentifiers(_owner, requestId: 'req-7'),
          throwsA(
            isA<ErasureRefused>().having(
              (e) => e.message,
              'message',
              contains('Nothing was changed'),
            ),
          ),
        );
        expect(await _outboxCount(db, Tables.persons), isZero);
      });
    });

    testWidgets('a family account cannot erase on its own authority', (
      tester,
    ) async {
      _prepareRegister(tester);
      await tester.runAsync(() async {
        final db = await AppDatabase.instance.database;
        await _seedFamily(db);
        await DataRightsDao.open(
          id: 'req-8',
          subjectPersonId: _marked.id,
          right: DataRight.erasure,
          requestedBy: _mother.id,
          at: _t0,
        );
        // Honest refusal: otherwise a caregiver opening the desk destroys a
        // register they do not own.
        await expectLater(
          repo.eraseIdentifiers(_mother, requestId: 'req-8'),
          throwsA(isA<AccessDenied>()),
        );
        expect((await PersonDao.byId(_marked.id))!.fullName, _marked.fullName);
      });
    });

    test('a refusal is a refusal, not a permission slip', () {
      const e = ErasureRefused('nothing on this device');
      // Distinct from AccessDenied on purpose: the honest answer to an erasure
      // request is often "not yet, and here is what must happen first", and a
      // message that reads like a permission slip invites somebody to route
      // around it.
      expect(e, isNot(isA<AccessDenied>()));
      expect(e.message, contains('nothing on this device'));
      expect(e.toString(), startsWith('ErasureRefused'));
    });
  });

  // ── Marking a record is itself a permission ─────────────────────────
  group('marking a record is itself a permission', () {
    testWidgets('a worker who can record vitals can protect and lift', (
      tester,
    ) async {
      _prepareRegister(tester);
      await tester.runAsync(() async {
        final db = await AppDatabase.instance.database;
        final repo = CareRepository(clock: () => _t0);
        await _seedFamily(db, person: _marked.withSensitivity(null));

        await repo.markRecordSensitive(
          _owner,
          personId: _marked.id,
          category: SensitivityCategory.violenceOrAbuse,
        );
        expect(
          (await PersonDao.byId(_marked.id))!.sensitivity,
          'violenceOrAbuse',
        );
        // The marking itself is on the device audit log, and it must not be
        // invisible: somebody changed the rule around a family.
        final audit = await db.query(
          Tables.auditLog,
          where: 'action = ?',
          whereArgs: ['mark_record_sensitive'],
        );
        expect(audit, hasLength(1));

        await repo.clearRecordSensitivity(_owner, personId: _marked.id);
        expect((await PersonDao.byId(_marked.id))!.isSensitive, isFalse);
      });
    });

    testWidgets('a caregiver cannot mark somebody else’s record', (
      tester,
    ) async {
      _prepareRegister(tester);
      await tester.runAsync(() async {
        final repo = CareRepository(clock: () => _t0);
        await expectLater(
          repo.markRecordSensitive(
            _mother,
            personId: _marked.id,
            category: SensitivityCategory.mentalHealth,
          ),
          throwsA(isA<AccessDenied>()),
        );
      });
    });

    testWidgets('a marking that arrived by pull is enforced here too', (
      tester,
    ) async {
      _prepareRegister(tester);
      await tester.runAsync(() async {
        final db = await AppDatabase.instance.database;
        // The whole point of a column on the person rather than a table on the
        // device that set it: every handset converges on the same rule.
        await _seedFamily(db);
        await _insertUser(db, _colleague);
        final decision = await RecordAccess.open(
          db,
          actor: _colleague,
          householdId: _household.id,
          subjectPersonId: _marked.id,
          purpose: AccessPurpose.continuingCare,
          action: 'open_record',
        );
        expect(decision.allowed, isFalse);
        expect(decision.canBreakGlass, isTrue);

        final retried = await RecordAccess.open(
          db,
          actor: _colleague,
          householdId: _household.id,
          subjectPersonId: _marked.id,
          purpose: AccessPurpose.continuingCare,
          action: 'open_record',
          breakGlassReason: 'The mother is with us from Tolon, no record yet',
          deviceId: 'cb-pulled',
        );
        expect(retried.allowed, isTrue);
        expect(retried.basis, AccessBasis.breakGlass);
      });
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

AppUser _workerNamed(String name, String id, String phone) => AppUser(
  id: id,
  fullName: name,
  phone: phone,
  role: UserRole.frontlineHealthWorker,
  region: 'Northern Region',
  district: 'Savelugu Municipal',
  community: 'Gushegu',
);

/// Points the register at a temp directory, so the byte-level tests are reading
/// the file the app would actually have written.
///
/// Synchronous on purpose: the database is only awaited inside `tester.runAsync`,
/// because the SQLite isolate never runs under the fake clock.
void _prepareRegister(WidgetTester tester) {
  final dbDir = Directory.systemTemp.createTempSync('carebridge_hardening');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async =>
        call.method == 'getApplicationDocumentsDirectory' ? dbDir.path : null,
  );
  AppDatabase.initialiseForDesktopAndTests();
  LedgerKey.pinnedForTesting =
      '00000000000000000000000000000000000000000000000000000000000000aa';
  RecordAccess.clearTrailCache();
  // Tear-downs run last-in-first-out, so the directory is registered before the
  // close and deleted after it: on Windows an open SQLite handle locks the file
  // and a delete that runs first throws for a reason that has nothing to do with
  // what is being tested. The delete is then tolerant for the same reason —
  // %TEMP% is reclaimed by the operating system, and a leaked probe directory is
  // not a product defect.
  addTearDown(() {
    try {
      dbDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Ignored deliberately.
    }
  });
  addTearDown(() {
    LedgerKey.pinnedForTesting = null;
    RecordAccess.clearTrailCache();
    return AppDatabase.instance.close();
  });
}

Future<void> _insertUser(Database db, AppUser u) => db.insert(Tables.users, {
  'id': u.id,
  'full_name': u.fullName,
  'phone': u.phone,
  'role': u.role.name,
  'region': u.region,
  'district': u.district,
  'community': u.community,
  'created_at': _t0.toIso8601String(),
}, conflictAlgorithm: ConflictAlgorithm.replace);

Future<void> _seedFamily(Database db, {Person? person}) async {
  await _insertUser(db, _owner);
  await HouseholdDao.upsert(_household);
  await PersonDao.upsert(person ?? _marked);
}

Future<void> _appendOpen(
  Database db, {
  required AppUser actor,
  required String? deviceId,
  required DateTime at,
  String? subject,
  String action = 'open_record',
  bool flagged = true,
  AccessBasis basis = AccessBasis.breakGlass,
}) {
  final who = subject ?? _marked.id;
  return AccessLedgerDao.append(
    db,
    actor: actor,
    deviceId: deviceId,
    action: action,
    entityTable: Tables.persons,
    entityId: who,
    subjectPersonId: who,
    purpose: AccessPurpose.continuingCare,
    basis: basis,
    at: at,
    flagged: flagged,
  );
}

Future<int> _outboxCount(Database db, String table) async {
  final rows = await db.rawQuery(
    'SELECT COUNT(*) c FROM ${Tables.outbox} WHERE entity_table = ?',
    [table],
  );
  return (rows.first['c'] as num).toInt();
}

/// A throwaway one-table database in which a secret is written and then deleted.
/// Returns the raw file bytes, as a string, for the containment checks.
Future<String> _bytesAfterDelete({required bool secure}) async {
  final dir = Directory.systemTemp.createTempSync('carebridge_secure_delete');
  final path = '${dir.path}${Platform.pathSeparator}pragma_probe.db';
  AppDatabase.initialiseForDesktopAndTests();
  final db = await openDatabase(
    path,
    version: 1,
    onConfigure: (d) async {
      await d.rawQuery('PRAGMA secure_delete = ${secure ? 'ON' : 'OFF'}');
    },
    onCreate: (d, _) async => d.execute('CREATE TABLE probe (x TEXT)'),
  );
  await db.insert('probe', {'x': 'Zongomama Watchpole'});
  await db.delete('probe');
  await db.close();
  final bytes = Uint8List.fromList(await File(path).readAsBytes());
  try {
    dir.deleteSync(recursive: true);
  } on FileSystemException {
    // The probe file can still be held by the engine on Windows; the assertion
    // has already been made against the bytes.
  }
  return String.fromCharCodes(bytes);
}
