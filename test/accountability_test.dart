/// Tests for the accountability spine: the verifiable access trail, the consent
/// ledger, the policy decision, and the family's data-rights queue.
///
/// Two of these matter more than the rest. The tamper tests, because a hash chain
/// nobody tries to break is a decoration — the property only exists if editing a
/// row is *detected*. And the refusal test, because a policy engine only ever
/// asked "may she look?" has never been asked the question that matters.
library;

import 'dart:io';

import 'package:carebridge_ai/data/local/app_database.dart';
import 'package:carebridge_ai/data/local/compliance_dao.dart';
import 'package:carebridge_ai/data/local/household_dao.dart';
import 'package:carebridge_ai/data/repositories/record_access.dart';
import 'package:carebridge_ai/domain/compliance.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Database;

final _t0 = DateTime.utc(2026, 10, 18, 9, 14);

const _nurse = AppUser(
  id: 'u-worker',
  fullName: 'Aminata Fusena',
  phone: '0244000001',
  role: UserRole.frontlineHealthWorker,
  region: 'Northern Region',
  district: 'Savelugu Municipal',
  community: 'Gushegu',
);

const _otherDistrictNurse = AppUser(
  id: 'u-other',
  fullName: 'Ibrahim Lukpin',
  phone: '0244000002',
  role: UserRole.frontlineHealthWorker,
  region: 'Northern Region',
  district: 'Tamale Metropolitan',
  community: 'Vittin',
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
  createdBy: 'u-worker',
);

const _farHousehold = Household(
  id: 'hh-far',
  name: 'The outside family',
  region: 'Ashanti Region',
  district: 'Ejisu Municipal',
  community: 'Ejisu',
  createdBy: 'u-someone-else',
);

const _child = Person(
  id: 'p-child',
  householdId: 'hh-1',
  fullName: 'Akosia Yeboah',
  clientType: ClientType.childUnderFive,
  ageYearsApprox: 2,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Fresh database per test, with the chain key pinned so verification runs
  /// against the same secret the appends used. Otherwise the test would assert
  /// that two different keys agree, which is not the property under test.
  void setUpDb(WidgetTester tester) {
    final dbDir = Directory.systemTemp.createTempSync('carebridge_accounting');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async =>
          call.method == 'getApplicationDocumentsDirectory' ? dbDir.path : null,
    );
    AppDatabase.initialiseForDesktopAndTests();
    LedgerKey.pinnedForTesting =
        '00000000000000000000000000000000000000000000000000000000000000aa';
    RecordAccess.clearTrailCache();
    addTearDown(() {
      LedgerKey.pinnedForTesting = null;
      RecordAccess.clearTrailCache();
    });
    addTearDown(() => AppDatabase.instance.close());
  }

  Future<Database> db() => AppDatabase.instance.database;

  Future<void> appendTwo(Database db, {int count = 2, String? subject}) async {
    for (var i = 0; i < count; i++) {
      await AccessLedgerDao.append(
        db,
        actor: _nurse,
        deviceId: 'cb-test',
        action: 'open_record',
        entityTable: Tables.households,
        entityId: _household.id,
        subjectPersonId: subject ?? _child.id,
        purpose: AccessPurpose.continuingCare,
        basis: AccessBasis.careRelationship,
        at: _t0.add(Duration(minutes: i)),
      );
    }
  }

  group('the access trail', () {
    testWidgets('chains every entry and verifies intact', (tester) async {
      setUpDb(tester);
      await tester.runAsync(() async {
        await appendTwo(await db(), count: 3);
        final result = await AccessLedgerDao.verify();
        expect(result.isValid, isTrue, reason: result.humanMessage);
        expect((result as ChainIntact).entries, 3);
      });
    });

    testWidgets('editing one row invalidates every row after it', (
      tester,
    ) async {
      setUpDb(tester);
      await tester.runAsync(() async {
        final database = await db();
        await appendTwo(database, count: 3);

        // The realistic attack is not a hacked app. It is an edited database:
        // one quiet change to erase an awkward access from the record.
        await database.update(
          Tables.accessLedger,
          {'note': 'nothing to see here'},
          where: 'seq = ?',
          whereArgs: [1],
        );

        final result = await AccessLedgerDao.verify();
        expect(result.isValid, isFalse);
        expect(result, isA<ChainBroken>());
        expect((result as ChainBroken).seq, 1);
      });
    });

    testWidgets('deleting a row is detected as clearly as editing one', (
      tester,
    ) async {
      setUpDb(tester);
      await tester.runAsync(() async {
        final database = await db();
        await appendTwo(database, count: 3);
        await database.delete(
          Tables.accessLedger,
          where: 'seq = ?',
          whereArgs: [2],
        );

        final result = await AccessLedgerDao.verify();
        expect(
          result.isValid,
          isFalse,
          reason: 'removal must not look like history',
        );
        expect((result as ChainBroken).seq, 3);
      });
    });

    testWidgets('the evidence row is queued with the access, in one write', (
      tester,
    ) async {
      setUpDb(tester);
      await tester.runAsync(() async {
        await appendTwo(await db(), count: 1);

        // Same offline guarantee a clinical record gets: the trail cannot live
        // only on the handset that made it, or a lost phone takes the evidence.
        final queued = await (await db()).query(
          Tables.outbox,
          where: 'entity_table = ?',
          whereArgs: [Tables.accessLedger],
        );
        expect(queued, hasLength(1));
        expect(queued.single['synced_at'], isNull);
      });
    });

    testWidgets('the disclosure names the worker and the reason, not an id', (
      tester,
    ) async {
      setUpDb(tester);
      await tester.runAsync(() async {
        final database = await db();
        await database.insert(Tables.users, {
          'id': _nurse.id,
          'full_name': _nurse.fullName,
          'phone': _nurse.phone,
          'role': _nurse.role.name,
          'region': _nurse.region,
          'district': _nurse.district,
          'community': _nurse.community,
          'preferred_language': 'English',
          'created_at': _t0.toIso8601String(),
        });
        await appendTwo(database);
        await AccessLedgerDao.append(
          database,
          actor: _nurse,
          deviceId: 'cb-test',
          action: 'open_record',
          entityTable: Tables.persons,
          entityId: _child.id,
          subjectPersonId: _child.id,
          purpose: AccessPurpose.emergency,
          basis: AccessBasis.vitalInterest,
          at: _t0.add(const Duration(minutes: 5)),
          flagged: true,
        );

        // A family asks once. Household-level and person-level accesses are
        // recorded under different subject ids and both belong in the answer —
        // showing half of a disclosure reads as a clean bill of health.
        final lines = await AccessLedgerDao.disclosureFor([
          _child.id,
          _household.id,
        ]);
        expect(lines, hasLength(3));
        expect(lines.first.actorName, _nurse.fullName);
        expect(lines.first.purpose, AccessPurpose.emergency);
        expect(lines.first.flagged, isTrue);
      });
    });
  });

  group('the policy decision', () {
    AccessContext ctx({
      required AppUser actor,
      required Household household,
      bool ownCaseload = false,
      bool dataSubject = false,
      bool consent = false,
    }) => AccessContext(
      actor: actor,
      household: household,
      subjectPersonId: _child.id,
      isOwnCaseload: ownCaseload,
      isDataSubject: dataSubject,
      crossFacilityConsent: consent,
      now: _t0,
    );

    testWidgets('her own caseload opens without ceremony and is not flagged', (
      tester,
    ) async {
      final decision = RecordAccess.decide(
        ctx(actor: _nurse, household: _household, ownCaseload: true),
        purpose: AccessPurpose.continuingCare,
      );
      expect(decision.allowed, isTrue);
      expect(decision.basis, AccessBasis.careRelationship);
      expect(decision.flagged, isFalse);
    });

    testWidgets('a family that opted in is opened on their consent', (
      tester,
    ) async {
      final decision = RecordAccess.decide(
        ctx(actor: _otherDistrictNurse, household: _household, consent: true),
        purpose: AccessPurpose.continuingCare,
      );
      expect(decision.allowed, isTrue);
      expect(decision.basis, AccessBasis.consent);
      expect(
        decision.flagged,
        isFalse,
        reason: 'consented access is not a finding',
      );
    });

    testWidgets(
      'an out-of-caseload look with no consent is allowed but flagged',
      (tester) async {
        final decision = RecordAccess.decide(
          ctx(actor: _otherDistrictNurse, household: _household),
          purpose: AccessPurpose.continuingCare,
        );
        expect(
          decision.allowed,
          isTrue,
          reason: 'care is never blocked by a log',
        );
        expect(decision.flagged, isTrue);
        expect(decision.note, contains('no recorded consent'));
      },
    );

    testWidgets('a break-the-glass reason is recorded verbatim', (
      tester,
    ) async {
      final decision = RecordAccess.decide(
        ctx(actor: _otherDistrictNurse, household: _household),
        purpose: AccessPurpose.continuingCare,
        breakGlassReason:
            'Mother travelled from my zone; child is overdue for vaccines',
      );
      expect(decision.basis, AccessBasis.breakGlass);
      expect(decision.flagged, isTrue);
      expect(decision.note, contains('overdue for vaccines'));
    });

    testWidgets('an emergency is recorded as an emergency, and reviewed', (
      tester,
    ) async {
      final decision = RecordAccess.decide(
        ctx(actor: _otherDistrictNurse, household: _household),
        purpose: AccessPurpose.emergency,
      );
      expect(decision.allowed, isTrue);
      expect(decision.basis, AccessBasis.vitalInterest);
      expect(decision.flagged, isTrue);
    });

    testWidgets('another region is refused, with a way forward', (
      tester,
    ) async {
      final decision = RecordAccess.decide(
        ctx(actor: _nurse, household: _farHousehold),
        purpose: AccessPurpose.continuingCare,
      );
      expect(decision.allowed, isFalse);
      expect(decision.basis, AccessBasis.none);
      expect(decision.reason, contains('outside your region'));
    });

    testWidgets('a family reading its own record is not a finding', (
      tester,
    ) async {
      final decision = RecordAccess.decide(
        ctx(
          actor: _mother,
          household: _household,
          ownCaseload: true,
          dataSubject: true,
        ),
        purpose: AccessPurpose.ownRecord,
      );
      expect(decision.allowed, isTrue);
      expect(decision.basis, AccessBasis.dataSubject);
      expect(decision.flagged, isFalse);
    });
  });

  group('consent', () {
    testWidgets('a withdrawal supersedes without erasing the grant', (
      tester,
    ) async {
      setUpDb(tester);
      await tester.runAsync(() async {
        final database = await db();
        await ConsentLedgerDao.record(
          database,
          event: ConsentEvent(
            id: 'c-1',
            subjectPersonId: _child.id,
            scope: ConsentScope.crossFacilitySearch,
            decision: ConsentDecision.granted,
            noticeVersion: CareNotice.currentVersion,
            occurredAt: _t0,
            capturedBy: _nurse.id,
          ),
        );
        expect(
          ConsentLedgerDao.isGranted(
            await ConsentLedgerDao.current(
              _child.id,
              ConsentScope.crossFacilitySearch,
            ),
          ),
          isTrue,
        );

        await ConsentLedgerDao.record(
          database,
          event: ConsentEvent(
            id: 'c-2',
            subjectPersonId: _child.id,
            scope: ConsentScope.crossFacilitySearch,
            decision: ConsentDecision.withdrawn,
            noticeVersion: CareNotice.currentVersion,
            occurredAt: _t0.add(const Duration(days: 30)),
            capturedBy: _nurse.id,
          ),
        );

        final current = await ConsentLedgerDao.current(
          _child.id,
          ConsentScope.crossFacilitySearch,
        );
        expect(current?.decision, ConsentDecision.withdrawn);
        expect(ConsentLedgerDao.isGranted(current), isFalse);
        // The earlier grant survives as the defence of an access made in June.
        expect(await ConsentLedgerDao.historyFor(_child.id), hasLength(2));
      });
    });

    testWidgets('never being asked is not the same as agreeing', (
      tester,
    ) async {
      setUpDb(tester);
      await tester.runAsync(() async {
        expect(
          await ConsentLedgerDao.current(
            _child.id,
            ConsentScope.researchSecondary,
          ),
          isNull,
        );
        expect(
          await ConsentLedgerDao.needsReconsent(
            _child.id,
            ConsentScope.researchSecondary,
          ),
          isTrue,
          reason: 'an unanswered scope must resolve to not-granted',
        );
      });
    });

    testWidgets('a spoken consent records the artefact that voiced it', (
      tester,
    ) async {
      setUpDb(tester);
      await tester.runAsync(() async {
        await ConsentLedgerDao.record(
          await db(),
          event: ConsentEvent(
            id: 'c-audio',
            subjectPersonId: _child.id,
            scope: ConsentScope.shareCareTeam,
            decision: ConsentDecision.granted,
            noticeVersion: CareNotice.currentVersion,
            occurredAt: _t0,
            capturedBy: _nurse.id,
            language: 'Hausa',
            voiceArtifact: 'hausa_piper:consent-notice-2026-10',
            witnessName: 'Community health management committee chair',
          ),
        );
        final current = await ConsentLedgerDao.current(
          _child.id,
          ConsentScope.shareCareTeam,
        );
        expect(current?.language, 'Hausa');
        expect(current?.voiceArtifact, contains('hausa_piper'));
        expect(
          await ConsentLedgerDao.needsReconsent(
            _child.id,
            ConsentScope.shareCareTeam,
          ),
          isFalse,
        );
      });
    });
  });

  group('data rights', () {
    testWidgets('a request is open work until it is answered', (tester) async {
      setUpDb(tester);
      await tester.runAsync(() async {
        await DataRightsDao.open(
          id: 'r-1',
          subjectPersonId: _child.id,
          right: DataRight.access,
          requestedBy: _mother.id,
          at: _t0,
        );
        var list = await DataRightsDao.forSubject(_child.id);
        expect(list.single.status, RequestStatus.open);
        expect(
          list.single.isOverdue(_t0.add(const Duration(days: 31))),
          isTrue,
        );
        expect(
          list.single.isOverdue(_t0.add(const Duration(days: 3))),
          isFalse,
        );

        await DataRightsDao.resolve(
          'r-1',
          status: RequestStatus.fulfilled,
          resolution:
              'Gave the family a printed list of the 4 recorded accesses.',
          at: _t0.add(const Duration(days: 4)),
        );
        list = await DataRightsDao.forSubject(_child.id);
        expect(list.single.status, RequestStatus.fulfilled);
        expect(await DataRightsDao.openQueue(), isEmpty);
      });
    });
  });

  testWidgets('the register still reaches the whole region', (tester) async {
    setUpDb(tester);
    await tester.runAsync(() async {
      await HouseholdDao.upsert(_household);
      await HouseholdDao.upsert(
        const Household(
          id: 'hh-colleague',
          name: 'A colleague family in another district',
          region: 'Northern Region',
          district: 'Tamale Metropolitan',
          community: 'Vittin',
          createdBy: 'u-colleague',
        ),
      );
      // The accountability layer must not shrink the reach the cross-worker
      // search was built for. Reach is the point; evidence is the condition.
      final visible = await HouseholdDao.caseloadFor(
        workerId: _nurse.id,
        region: _nurse.region,
      );
      expect(visible.map((h) => h.id), containsAll(['hh-1', 'hh-colleague']));
    });
  });
}
