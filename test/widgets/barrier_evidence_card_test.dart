/// The populated card.
///
/// The referral-desk tests only ever reached the card with no read behind it,
/// which proves the guard and nothing else. What the card exists for is the
/// other state — several households having said the same thing, and the count
/// that turns their sentences into something a CHO can put in front of a
/// sub-district officer. The read itself is covered against a real database in
/// `test/barrier_evidence_test.dart`; here the provider is given a board and
/// the question is only what the screen does with it.
library;

import 'package:carebridge_ai/domain/engines/barrier_evidence.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/fhw/barrier_evidence_card.dart';
import 'package:carebridge_ai/presentation/fhw/follow_up/follow_up_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

BarrierPattern _pattern(
  CareBarrier barrier, {
  required int households,
  int unresolved = 0,
  int? reports,
}) => BarrierPattern(
  barrier: barrier,
  households: households,
  reports: reports ?? households,
  unresolved: unresolved,
);

Future<void> show(WidgetTester tester, List<BarrierPattern>? patterns) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        barrierPatternsProvider.overrideWith((_) async => patterns ?? const []),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: BarrierEvidenceCard(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('three households saying it is a count, with the owner of the '
      'fix named', (tester) async {
    await show(tester, [
      _pattern(CareBarrier.facilityClosed, households: 3, unresolved: 2),
      _pattern(CareBarrier.noTransportMoney, households: 1),
    ]);

    expect(find.text('Why care did not happen'), findsOneWidget);
    expect(find.text('Facility was closed or no staff'), findsOneWidget);
    // Households, not reports: that is what makes it a pattern rather than one
    // loud family.
    expect(find.text('3'), findsOneWidget);
    expect(find.text('The facility · 2 still open'), findsOneWidget);
    expect(
      find.textContaining('Reported by 3 or more households'),
      findsOneWidget,
    );
    // The one-off is named as a one-off instead of quietly dropped.
    expect(find.textContaining('Plus 1 reported once or twice'), findsOneWidget);
    expect(find.text('No money for transport'), findsNothing);
  });

  testWidgets('two households is not yet a system fact, and the card says so',
      (tester) async {
    await show(tester, [
      _pattern(CareBarrier.floodedRoad, households: 2),
    ]);

    expect(find.text('Road flooded or impassable'), findsOneWidget);
    expect(
      find.textContaining('enough households to be a system fact'),
      findsOneWidget,
    );
  });

  testWidgets('an empty window asks the question instead of showing nothing',
      (tester) async {
    await show(tester, const []);

    expect(
      find.textContaining('Nobody has been asked why a referral did not'),
      findsOneWidget,
    );
  });

  testWidgets('the escalation is stated as a sentence a CHO can read out',
      (tester) async {
    final pattern = _pattern(
      CareBarrier.pastBadExperience,
      households: 4,
      unresolved: 4,
    );

    expect(
      pattern.statement,
      '4 households said "Bad experience at the facility before" in the last '
      '30 days. A staffing, hours or treatment-quality problem. This is a '
      'sub-district escalation, not a family instruction.',
    );
  });
}
