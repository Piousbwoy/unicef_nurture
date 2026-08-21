/// Paint regression for the kit's card scaffolds. A [BoxDecoration] that
/// combines a non-uniform [Border] with a `borderRadius` throws at paint
/// time ("A borderRadius can only be given on borders with uniform
/// colors"), which on a real device renders as a blank white card — this
/// test pumps the accent-bearing scaffolds and fails if any exception
/// surfaces or if the card's text fails to lay out.
library;

import 'package:carebridge_ai/core/theme/app_theme.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/shared/recommendation_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('accent cards paint without exceptions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              CohortCallout(
                cohort: ClientType.childUnderFive,
                note: 'Cohort callout note text probe.',
              ),
              const SafetyNetNote(text: 'Safety net note probe.'),
              const KitCard(
                accent: AppColors.triageAmber,
                child: Text('KITCARD TEXT PROBE'),
              ),
              const KitCard(child: Text('QUIET KITCARD PROBE')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The defect this guards: paint-phase FlutterError left blank cards.
    expect(tester.takeException(), isNull);

    // And the content must actually occupy space — a silent blank card
    // would still pass the exception check if the crash ever moved.
    final card = tester.getSize(find.text('KITCARD TEXT PROBE'));
    expect(card.width, greaterThan(0));
    expect(card.height, greaterThan(0));
  });
}
