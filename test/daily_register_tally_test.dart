/// The CHPS daily register tally.
///
/// Two things are pinned here, and both are about the number being defensible
/// at the district rather than about the code running.
///
/// At the domain layer: the tally counts *children*, so a child assessed twice
/// in one day is one child seen; the malnutrition columns resolve to the last
/// MUAC the day produced rather than listing one child as SAM and MAM; an RDT
/// positive can never be counted outside a test; and maternal records stay out
/// of the under-five columns while their referrals still count.
///
/// At the data layer: the day is the local one, half-open from midnight, and
/// the rows are the signed-in worker's own — a shared phone must not show one
/// CHPS staffer's register column to another.
library;

import 'dart:io';

import 'package:carebridge_ai/data/local/app_database.dart';
import 'package:carebridge_ai/data/local/household_dao.dart';
import 'package:carebridge_ai/data/local/visit_dao.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _worker = 'u-nurse';
const _colleague = 'u-nurse-two';

Assessment _assessment(
  String id, {
  String personId = 'p-1',
  String visitId = 'v-1',
  String worker = _worker,
  DateTime? at,
  ClientType clientType = ClientType.childUnderFive,
  bool? rdtDone,
  bool? rdtPositive,
  List<String> vaccines = const [],
  NutritionStatus? band,
}) => Assessment(
  id: id,
  visitId: visitId,
  personId: personId,
  clientType: clientType,
  performedBy: worker,
  performedAt: at ?? DateTime(2026, 9, 22, 9),
  inputs: {
    'rdt_done': ?rdtDone,
    'rdt_positive': ?rdtPositive,
    'vaccines_given': vaccines,
  },
  result: AssessmentResult(
    clientType: clientType,
    triage: TriageLevel.routine,
    classification: 'ROUTINE CARE',
    findings: const [],
    actions: const [],
    confidence: RecommendationConfidence.high,
    nutritionStatus: band,
  ),
);

Referral _referral(String id, {String worker = _worker, DateTime? at}) =>
    Referral(
      id: id,
      referenceCode: 'CB-$id',
      personId: 'p-1',
      assessmentId: 'a-1',
      facilityName: 'Savelugu Health Centre',
      reason: 'Needs a capacity this compound does not have',
      urgency: ReferralUrgency.sameDay,
      issuedBy: worker,
      issuedAt: at ?? DateTime(2026, 9, 22, 10),
    );

/// A private database file per test, the way the clinic queue tests get one:
/// the tally is only worth testing against the real schema and the real TEXT
/// date columns it has to range over.
void _useTempDb(WidgetTester tester, String tag) {
  final dir = Directory.systemTemp.createTempSync('carebridge_$tag');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async =>
        call.method == 'getApplicationDocumentsDirectory' ? dir.path : null,
  );
  AppDatabase.initialiseForDesktopAndTests();
  addTearDown(() async {
    await AppDatabase.instance.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
}

/// The household, child and session the assessment and referral rows point at.
Future<void> _seed() async {
  await HouseholdDao.upsert(
    Household(
      id: 'h1',
      name: 'Test household',
      region: 'Northern Region',
      district: 'Savelugu Municipal',
      community: 'Tamale Central',
      createdBy: _worker,
    ),
  );
  await PersonDao.upsert(
    Person(
      id: 'p-1',
      householdId: 'h1',
      fullName: 'Test child',
      clientType: ClientType.childUnderFive,
      dateOfBirth: DateTime(2024, 3, 4),
    ),
  );
  await VisitDao.start(
    Visit(
      id: 'v-1',
      householdId: 'h1',
      conductedBy: _worker,
      startedAt: DateTime(2026, 9, 22, 8),
      reasons: const [VisitReason.childUnwell],
    ),
    const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DailyRegisterTally.of', () {
    test('counts children, not assessments', () {
      final tally = DailyRegisterTally.of(
        assessments: [
          _assessment('a1', personId: 'p-1'),
          _assessment('a2', personId: 'p-1'),
          _assessment('a3', personId: 'p-2'),
        ],
        referralsIssued: 0,
      );
      expect(tally.childrenSeen, 2);
    });

    test('a newborn is an under-five for the register', () {
      final tally = DailyRegisterTally.of(
        assessments: [_assessment('a1', clientType: ClientType.newborn)],
        referralsIssued: 0,
      );
      expect(tally.childrenSeen, 1);
    });

    test('maternal records stay out of the under-five columns', () {
      final tally = DailyRegisterTally.of(
        assessments: [
          _assessment(
            'a1',
            personId: 'm-1',
            clientType: ClientType.pregnantWoman,
          ),
          _assessment(
            'a2',
            personId: 'm-2',
            clientType: ClientType.postpartumWoman,
          ),
        ],
        referralsIssued: 2,
      );
      expect(tally.childrenSeen, 0);
      // The referrals column still counts them: a maternal referral is work
      // the day did.
      expect(tally.referralsIssued, 2);
      expect(tally.isEmpty, isFalse);
    });

    test('a positive is never counted outside a test', () {
      final tally = DailyRegisterTally.of(
        assessments: [
          _assessment('a1', personId: 'p-1', rdtDone: true, rdtPositive: true),
          // A row carrying a positive with no test recorded — the numerator
          // must not follow it past the denominator.
          _assessment('a2', personId: 'p-2', rdtPositive: true),
        ],
        referralsIssued: 0,
      );
      expect(tally.rdtDone, 1);
      expect(tally.rdtPositive, 1);
    });

    test('a dose ticked on any pass today counts the child once', () {
      final tally = DailyRegisterTally.of(
        assessments: [
          _assessment('a1', personId: 'p-1', vaccines: ['OPV 0']),
          _assessment('a2', personId: 'p-1'),
          _assessment('a3', personId: 'p-2'),
        ],
        referralsIssued: 0,
      );
      expect(tally.immunised, 1);
    });

    test(
      'the malnutrition columns carry the last reading, not every reading',
      () {
        // Handed over newest-first on purpose: "last of the day" cannot be
        // allowed to depend on the caller's order.
        final tally = DailyRegisterTally.of(
          assessments: [
            // Re-measured after she ate: one child, one column.
            _assessment(
              'late',
              personId: 'p-1',
              at: DateTime(2026, 9, 22, 11),
              band: NutritionStatus.moderateAcute,
            ),
            _assessment(
              'early',
              personId: 'p-1',
              at: DateTime(2026, 9, 22, 9),
              band: NutritionStatus.severeAcute,
            ),
            // A later reading with no MUAC at all leaves the earlier band alone.
            _assessment(
              'band',
              personId: 'p-2',
              at: DateTime(2026, 9, 22, 9),
              band: NutritionStatus.severeAcute,
            ),
            _assessment(
              'clear',
              personId: 'p-2',
              at: DateTime(2026, 9, 22, 12),
            ),
            // A measured band does supersede, including back to adequate.
            _assessment(
              'mild',
              personId: 'p-3',
              at: DateTime(2026, 9, 22, 9),
              band: NutritionStatus.moderateAcute,
            ),
            _assessment(
              'ok',
              personId: 'p-3',
              at: DateTime(2026, 9, 22, 10),
              band: NutritionStatus.normal,
            ),
          ],
          referralsIssued: 0,
        );
        expect(tally.sam, 1);
        expect(tally.mam, 1);
        expect(tally.childrenSeen, 3);
      },
    );

    test('a day with no records is empty, so nothing is rendered', () {
      expect(const DailyRegisterTally().isEmpty, isTrue);
      expect(
        DailyRegisterTally.of(
          assessments: const [],
          referralsIssued: 0,
        ).isEmpty,
        isTrue,
      );
    });
  });

  group('the day window and the worker who owns it', () {
    testWidgets("assessments are one worker's, inside local midnight", (
      tester,
    ) async {
      _useTempDb(tester, 'tally_window');

      await tester.runAsync(() async {
        await _seed();
        final day = DateTime(2026, 9, 22, 14);
        for (final at in [
          DateTime(2026, 9, 21, 23, 59),
          DateTime(2026, 9, 22),
          DateTime(2026, 9, 22, 23, 59),
          DateTime(2026, 9, 23),
        ]) {
          await AssessmentDao.save(
            _assessment('a-${at.millisecondsSinceEpoch}', at: at),
          );
        }
        await AssessmentDao.save(_assessment('colleague', worker: _colleague));

        final rows = await AssessmentDao.forWorkerOn(_worker, day);
        expect(rows, hasLength(2));
        for (final a in rows) {
          expect(a.performedBy, _worker);
          expect(a.performedAt.day, 22);
        }
        // Two passes on the same child are still one child in the register.
        expect(
          DailyRegisterTally.of(
            assessments: rows,
            referralsIssued: 0,
          ).childrenSeen,
          1,
        );
      });
    });

    testWidgets('referrals are counted per worker per day', (tester) async {
      _useTempDb(tester, 'tally_referrals');

      await tester.runAsync(() async {
        await _seed();
        await AssessmentDao.saveWithReferral(
          _assessment('a-today'),
          _referral('r-today'),
        );
        await AssessmentDao.saveWithReferral(
          _assessment('a-yesterday', at: DateTime(2026, 9, 21, 11)),
          _referral('r-yesterday', at: DateTime(2026, 9, 21, 11)),
        );
        await AssessmentDao.saveWithReferral(
          _assessment('a-colleague', worker: _colleague),
          _referral('r-colleague', worker: _colleague),
        );

        expect(
          await ReferralDao.countIssuedBy(_worker, DateTime(2026, 9, 22)),
          1,
        );
        expect(
          await ReferralDao.countIssuedBy(_worker, DateTime(2026, 9, 21)),
          1,
        );
        expect(
          await ReferralDao.countIssuedBy(_colleague, DateTime(2026, 9, 22)),
          1,
        );
      });
    });
  });
}
