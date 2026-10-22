import 'dart:io';

import 'package:carebridge_ai/data/local/app_database.dart';
import 'package:carebridge_ai/data/local/household_dao.dart';
import 'package:carebridge_ai/data/local/visit_dao.dart';
import 'package:carebridge_ai/domain/engines/barrier_evidence.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

BarrierReport _report({
  required String household,
  required CareBarrier barrier,
  String? id,
  bool resolved = false,
}) => BarrierReport(
  id: id ?? '$household-${barrier.name}',
  householdId: household,
  barriers: [barrier],
  recordedBy: 'cho-1',
  recordedAt: DateTime(2026, 10, 20),
  resolved: resolved,
);

void main() {
  group('barrier evidence', () {
    test('counts households, not reports', () {
      // The same family saying it three times is one family.
      final patterns = BarrierEvidence.summarise([
        _report(household: 'h1', barrier: CareBarrier.facilityClosed),
        _report(household: 'h1', barrier: CareBarrier.facilityClosed, id: 'a'),
        _report(household: 'h2', barrier: CareBarrier.facilityClosed, id: 'b'),
      ]);
      final closed = patterns.singleWhere(
        (p) => p.barrier == CareBarrier.facilityClosed,
      );
      expect(closed.households, 2);
      expect(closed.reports, 3);
    });

    test('two households is a coincidence, three is a pattern', () {
      final two = BarrierEvidence.summarise([
        for (final h in ['h1', 'h2'])
          _report(household: h, barrier: CareBarrier.facilityClosed),
      ]);
      expect(BarrierEvidence.escalatable(two), isEmpty);

      final three = BarrierEvidence.summarise([
        for (final h in ['h1', 'h2', 'h3'])
          _report(household: h, barrier: CareBarrier.facilityClosed),
      ]);
      expect(BarrierEvidence.escalatable(three).single.households, 3);
    });

    test('the owner decides who the escalation is for', () {
      expect(CareBarrier.facilityClosed.owner, BarrierOwner.facility);
      expect(CareBarrier.floodedRoad.owner, BarrierOwner.season);
      expect(CareBarrier.noPermission.owner, BarrierOwner.household);
      expect(CareBarrier.noTransportMoney.owner, BarrierOwner.system);
      expect(CareBarrier.preferredTraditional.owner, BarrierOwner.community);
    });

    test('a one-off is kept in the list, and says it is a one-off', () {
      final patterns = BarrierEvidence.summarise([
        for (final h in ['h1', 'h2', 'h3'])
          _report(household: h, barrier: CareBarrier.facilityClosed),
        _report(household: 'h9', barrier: CareBarrier.noNhisCard),
      ]);
      expect(patterns, hasLength(2));
      expect(BarrierEvidence.escalatable(patterns), hasLength(1));
      final nhis = patterns.firstWhere(
        (p) => p.barrier == CareBarrier.noNhisCard,
      );
      expect(nhis.statement, contains('1 household said'));
      expect(nhis.statement, contains('No valid NHIS card'));
      expect(nhis.statement, contains('Financing or infrastructure'));
    });

    test('the escalation sentence carries the count and the owner', () {
      final patterns = BarrierEvidence.summarise([
        for (final h in ['h1', 'h2', 'h3', 'h4'])
          _report(household: h, barrier: CareBarrier.facilityClosed),
      ]);
      final statement = patterns.single.statement;
      expect(statement, contains('4 households'));
      expect(statement, contains('sub-district escalation'));
      // The same sentence for a household-owned barrier reads completely
      // differently, which is the whole point of the owner field.
      final permission = BarrierEvidence.summarise([
        _report(household: 'h1', barrier: CareBarrier.noPermission),
      ]).single;
      expect(permission.statement, contains('next contact'));
    });

    test('worked-around barriers still count, and say how many are open', () {
      final patterns = BarrierEvidence.summarise([
        for (final h in ['h1', 'h2', 'h3'])
          _report(
            household: h,
            barrier: CareBarrier.facilityClosed,
            resolved: h == 'h1',
          ),
      ]);
      final closed = patterns.single;
      expect(closed.households, 3);
      expect(closed.unresolved, 2);
    });

    test('ranked by how many households, so the first line is the argument', () {
      final patterns = BarrierEvidence.summarise([
        for (final h in ['h1', 'h2'])
          _report(household: h, barrier: CareBarrier.noTransportMoney),
        for (final h in ['h3', 'h4', 'h5'])
          _report(household: h, barrier: CareBarrier.facilityClosed),
      ]);
      expect(
        patterns.map((p) => p.households),
        [3, 2],
      );
      expect(patterns.first.barrier, CareBarrier.facilityClosed);
    });

    test('nothing reported is an empty list, not a zero', () {
      expect(BarrierEvidence.summarise(const []), isEmpty);
      expect(BarrierEvidence.escalatable(const []), isEmpty);
    });
  });

  // The other half of the claim: that the rows a check-in writes are the rows
  // the window query gives back. Capture without read-back is a register.
  group('the pattern window against the register', () {
    late Directory dbDir;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      dbDir = Directory.systemTemp.createTempSync('carebridge_barriers');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => call.method == 'getApplicationDocumentsDirectory'
                ? dbDir.path
                : null,
          );
      AppDatabase.initialiseForDesktopAndTests();
      for (final id in ['h-1', 'h-2', 'h-3']) {
        await HouseholdDao.upsert(
          Household(
            id: id,
            name: '$id household',
            region: 'Northern Region',
            district: 'Savelugu Municipal',
            community: 'Tamale Central',
            createdBy: 'cho-1',
          ),
        );
      }
    });

    tearDown(() async {
      await AppDatabase.instance.close();
      if (dbDir.existsSync()) dbDir.deleteSync(recursive: true);
    });

    test('three families saying the facility was closed come back as one '
        'pattern with the count attached', () async {
      final now = DateTime.now();
      for (final (id, household) in [
        ('b-1', 'h-1'),
        ('b-2', 'h-2'),
        ('b-3', 'h-3'),
      ]) {
        await BarrierDao.save(
          BarrierReport(
            id: id,
            householdId: household,
            barriers: const [CareBarrier.facilityClosed],
            recordedBy: 'cho-1',
            recordedAt: now,
          ),
        );
      }
      // A second barrier from one of them: reported twice, said by one family.
      await BarrierDao.save(
        BarrierReport(
          id: 'b-4',
          householdId: 'h-1',
          barriers: const [CareBarrier.noTransportMoney],
          recordedBy: 'cho-1',
          recordedAt: now,
        ),
      );

      final patterns = BarrierEvidence.summarise(
        await BarrierDao.withinDays(BarrierEvidence.windowDays),
      );

      final closed = patterns.first;
      expect(closed.barrier, CareBarrier.facilityClosed);
      expect(closed.households, 3);
      expect(BarrierEvidence.escalatable(patterns), [closed]);
      expect(closed.statement, startsWith('3 households said'));
    });

    test('a barrier answered outside the window is not counted', () async {
      await BarrierDao.save(
        BarrierReport(
          id: 'b-old',
          householdId: 'h-1',
          barriers: const [CareBarrier.floodedRoad],
          recordedBy: 'cho-1',
          recordedAt: DateTime.now().subtract(
            const Duration(days: BarrierEvidence.windowDays + 5),
          ),
        ),
      );

      expect(
        BarrierEvidence.summarise(
          await BarrierDao.withinDays(BarrierEvidence.windowDays),
        ),
        isEmpty,
      );
    });
  });
}
