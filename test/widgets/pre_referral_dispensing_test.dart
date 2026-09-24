/// The pre-referral card's calculated dose line.
///
/// The card must show the published guideline dose and, separately, what
/// this child's weight works out to — and must fall back to the guideline
/// alone when there is no weight. Both branches are pinned here because the
/// failure mode is silent: a missing weight that still produced a number
/// would look authoritative on the screen.
library;

import 'package:carebridge_ai/domain/engines/protocols/stabilization_protocol_selector.dart';
import 'package:carebridge_ai/domain/engines/recommendation_engine.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/presentation/shared/recommendation_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AssessmentResult _wellChild() => const AssessmentResult(
  clientType: ClientType.childUnderFive,
  triage: TriageLevel.routine,
  classification: 'NO IMCI CLASSIFICATION — WELL CHILD',
  findings: [],
  actions: [],
  confidence: RecommendationConfidence.high,
);

CarePlan _pneumoniaPlan({double? weightKg}) =>
    RecommendationEngine.synthesize(
      results: [_wellChild()],
      stabilizationContext: StabilizationContext(
        patientAgeDays: 30 * 18,
        coughPresent: true,
        severeChestIndrawing: true,
        weightKg: weightKg,
      ),
      stabilizationRisks: const StabilizationAiRisks(),
    );

Future<void> _pump(WidgetTester tester, CarePlan plan) {
  return tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: SingleChildScrollView(
          child: PreReferralRecSection(plan: plan),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a weighed child gets the tablet count under the guideline dose',
      (tester) async {
    await _pump(tester, _pneumoniaPlan(weightKg: 11.2));

    // The published rule, verbatim, still there.
    expect(
      find.textContaining('DOSE: 40 mg/kg per dose PO'),
      findsOneWidget,
    );
    // The derived amount, clearly labelled as derived.
    expect(find.text('FOR THIS CHILD'), findsOneWidget);
    expect(
      find.textContaining('2 × 250 mg dispersible tablet = 500 mg'),
      findsOneWidget,
    );
    // And the working it came from, so the CHO can check it by eye.
    expect(
      find.textContaining('40 mg/kg × 11.2 kg = 448 mg'),
      findsOneWidget,
    );
    expect(find.textContaining('FROM: WHO IMCI Chart Booklet 2014'),
        findsOneWidget);
  });

  testWidgets('an unweighed child shows no number and says why', (tester) async {
    await _pump(tester, _pneumoniaPlan());

    expect(find.text('FOR THIS CHILD'), findsNothing);
    expect(find.textContaining('448'), findsNothing);
    expect(find.textContaining('Weigh the child to get it'), findsOneWidget);
  });

  testWidgets('a rounding too coarse to dispense is warned, not hidden',
      (tester) async {
    // 4.5 kg → 180 mg; the only countable amount is 250 mg, 38.9% over.
    await _pump(tester, _pneumoniaPlan(weightKg: 4.5));

    expect(find.text('FOR THIS CHILD'), findsOneWidget);
    expect(
      find.textContaining('Do not round to this figure'),
      findsOneWidget,
    );
  });

  testWidgets('steps with no weight arithmetic are unaffected',
      (tester) async {
    await _pump(tester, _pneumoniaPlan(weightKg: 11.2));

    // One calculated line only — the oxygen, positioning and IM steps keep
    // their plain dose chips.
    expect(find.text('FOR THIS CHILD'), findsOneWidget);
    expect(find.textContaining('DOSE: 1-2 L/min'), findsOneWidget);
  });
}
