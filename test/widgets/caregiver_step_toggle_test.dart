/// The action steps of a caregiver verdict are things she must actually do at
/// the facility gate, so the tick has to mean something: it appears only once
/// the write has landed, a failed write says so out loud and stays tappable as
/// the retry, and the whole line — not a 44px box in a corner — is the target.
/// These lists run on the smallest handset in the north at the largest text,
/// where the numbered thread and the label share one row.
library;

import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/data/repositories/care_repository.dart';
import 'package:carebridge_ai/domain/entities/caregiver.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/caregiver/caregiver_providers.dart';
import 'package:carebridge_ai/presentation/caregiver/widgets/companion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const user = AppUser(
  id: 'user',
  fullName: 'Asatu Issah',
  phone: '0240000001',
  role: UserRole.caregiver,
  region: 'Northern Region',
  district: 'Karaga',
  community: 'Karaga',
);
const scope = CaregiverScope(userId: 'user', householdId: 'family');
final now = DateTime(2026, 8, 10, 9);

class _ActivityRepository extends CareRepository {
  _ActivityRepository({this.failFirst = false});

  final bool failFirst;
  final List<CaregiverActivity> saved = [];
  int writes = 0;

  @override
  Future<List<CaregiverActivity>> caregiverActivity(
    AppUser user,
    CaregiverScope scope, {
    String? personId,
  }) async => List.of(saved);

  @override
  Future<void> saveCaregiverActivity(
    AppUser user,
    CaregiverActivity activity,
  ) async {
    writes++;
    // Storage is never instant. The delay is what makes the in-flight state
    // observable, and with it the promise that nothing ticks early.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (failFirst && writes == 1) {
      throw Exception('storage is full');
    }
    saved
      ..removeWhere(
        (a) =>
            a.kind == activity.kind &&
            a.itemKey == activity.itemKey &&
            a.occurrenceKey == activity.occurrenceKey,
      )
      ..add(activity);
  }
}

Future<_ActivityRepository> _pump(
  WidgetTester tester, {
  bool failFirst = false,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repo = _ActivityRepository(failFirst: failFirst);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        careRepositoryProvider.overrideWithValue(repo),
        currentUserProvider.overrideWithValue(user),
        linkedHouseholdProvider.overrideWithValue('family'),
        caregiverScopeProvider.overrideWithValue(scope),
        caregiverClockProvider.overrideWithValue(() => now),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(textScale),
            size: size,
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: CompanionCard(
                title: 'Do these now — even on the way',
                eyebrow: 'ACTION STEPS',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, label) in const [
                      'Carry the health record book — the nurse will ask for it.',
                      "Arrange a ride now. A neighbour's motorbike is fine.",
                      'Go with someone if you can.',
                    ].indexed)
                      CaregiverTaskToggle(
                        personId: 'kid',
                        kind: CaregiverActivityKind.preparation,
                        sourceId: 'report-1',
                        itemKey: 'step-$index',
                        occurrenceKey: 'report-1',
                        label: label,
                        step: index + 1,
                        totalSteps: 3,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

/// A line has to be in view before a finger can reach it, and the write has to
/// outlast the frame that started it before the row can be judged done.
Future<void> _tapLine(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pump();
}

Future<void> _landed(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 120));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a step ticks only after the write lands', (tester) async {
    final repo = await _pump(tester);

    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Done'), findsNothing);
    // The old design buried the state word inside the sentence.
    expect(find.textContaining('Mark done'), findsNothing);

    await _tapLine(
      tester,
      "Arrange a ride now. A neighbour's motorbike is fine.",
    );
    expect(find.text('Saving…'), findsOneWidget);
    expect(find.text('Done'), findsNothing, reason: 'no optimistic tick');

    await _landed(tester);
    expect(repo.writes, 1);
    expect(find.text('Saving…'), findsNothing);
    expect(find.text('Done'), findsOneWidget);
    expect(
      find.text('2'),
      findsNothing,
      reason: 'the check replaces the number',
    );
  });

  testWidgets('a failed write says so and the same tap retries it', (
    tester,
  ) async {
    final repo = await _pump(tester, failFirst: true);

    await _tapLine(tester, 'Go with someone if you can.');
    await _landed(tester);

    expect(find.text('Could not save — tap to try again'), findsOneWidget);
    expect(find.text('Done'), findsNothing);
    expect(find.byIcon(Icons.priority_high_rounded), findsOneWidget);

    await _tapLine(tester, 'Go with someone if you can.');
    await _landed(tester);
    expect(repo.writes, 2);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Could not save — tap to try again'), findsNothing);
  });

  testWidgets('the whole line is the tap target', (tester) async {
    await _pump(tester);
    final line = tester.getSize(
      find.ancestor(
        of: find.text('Go with someone if you can.'),
        matching: find.byType(InkWell),
      ),
    );
    expect(line.height, greaterThanOrEqualTo(48));
    expect(line.width, greaterThanOrEqualTo(300));
  });

  testWidgets('the thread and labels fit 320px at 200% text', (tester) async {
    await _pump(tester, size: const Size(320, 720), textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    await _tapLine(tester, 'Go with someone if you can.');
    await _landed(tester);
    expect(find.text('Done'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
