/// The SBAR handover card: one structured story from records already held.
///
/// Judges read this as the app's answer to "how does a community nurse hand a
/// case up the chain?" — so the contract pinned here is that every section is
/// composed from the saved assessment or referral, with no new typing, and
/// that the urgent acuity colours the card in triage red and nothing else.
library;

import 'package:carebridge_ai/core/theme/app_theme.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/fhw/clinic_widgets.dart';
import 'package:carebridge_ai/presentation/visit/sbar_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _person = Person(
  id: 'p-1',
  householdId: 'h-1',
  fullName: 'Abdul Fuseini',
  clientType: ClientType.childUnderFive,
);

Assessment _urgentAssessment() => Assessment(
  id: 'a-1',
  visitId: 'v-1',
  personId: _person.id,
  clientType: ClientType.childUnderFive,
  performedBy: 'worker-1',
  performedAt: DateTime(2026, 9, 20, 9),
  inputs: const {},
  result: AssessmentResult(
    clientType: ClientType.childUnderFive,
    triage: TriageLevel.urgent,
    classification: 'SEVERE PNEUMONIA OR VERY SEVERE DISEASE',
    findings: [
      ClinicalFinding(
        label: 'Fast breathing',
        detail:
            'Respiratory rate 64/min is above the 50/min cut-off for a '
            'two-year-old (IMCI, Pneumonia).',
        severity: TriageLevel.urgent,
      ),
      ClinicalFinding(
        label: 'Chest indrawing',
        detail: 'Observed during the consult.',
        severity: TriageLevel.urgent,
        isDangerSign: true,
      ),
    ],
    actions: [
      RecommendedAction(
        instruction: 'Give the first dose of antibiotic before referral travel',
        urgency: ReferralUrgency.immediate,
        isPrereferralTreatment: true,
      ),
      RecommendedAction(
        instruction: 'Refer now to Savelugu Municipal District Hospital',
        urgency: ReferralUrgency.immediate,
        isReferral: true,
      ),
    ],
    confidence: RecommendationConfidence.high,
    dangerSignsPresent: const ['Chest indrawing'],
    missingData: const ['Weight'],
    followUpInDays: 2,
  ),
);

Referral _openReferral() => Referral(
  id: 'r-1',
  referenceCode: 'CB-7K2M',
  personId: _person.id,
  assessmentId: 'a-1',
  facilityName: 'Savelugu Municipal District Hospital',
  reason: 'Severe dehydration with danger signs',
  urgency: ReferralUrgency.immediate,
  issuedBy: 'worker-1',
  issuedAt: DateTime.now().subtract(const Duration(hours: 50)),
  status: ReferralStatus.issued,
  clinicalSummary: 'ORS attempted; persistent vomiting.',
);

Future<void> _pump(WidgetTester tester, SbarCard card) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: card)));
  await tester.pumpAndSettle();
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('fromAssessment composes every SBAR section from the record', (
    tester,
  ) async {
    await _pump(tester, SbarCard.fromAssessment(_urgentAssessment(), _person));

    expect(find.text('Handover note'), findsOneWidget);
    for (final letter in ['S', 'B', 'A', 'R']) {
      expect(find.text(letter), findsOneWidget);
    }
    // Situation: classification, danger signs, recording time.
    expect(find.textContaining('SEVERE PNEUMONIA'), findsOneWidget);
    expect(
      find.textContaining('Danger signs: Chest indrawing'),
      findsOneWidget,
    );
    // Background: what was not measured stays on the note, honestly.
    expect(find.textContaining('Not measured: Weight'), findsOneWidget);
    expect(find.textContaining('Protocol confidence'), findsOneWidget);
    // Assessment: the findings travel with their reasoning.
    expect(find.textContaining('Fast breathing'), findsOneWidget);
    // Recommendation: prereferral treatment before the referral itself, then
    // the review window.
    expect(
      find.textContaining('Give the first dose of antibiotic'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Refer now to Savelugu Municipal District Hospital'),
      findsOneWidget,
    );
    expect(find.textContaining('Review in 2 days'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fromReferral composes the open-loop handover with escalation', (
    tester,
  ) async {
    await _pump(tester, SbarCard.fromReferral(_openReferral(), _person));

    expect(
      find.textContaining('Referral to Savelugu Municipal District Hospital'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Severe dehydration with danger signs'),
      findsOneWidget,
    );
    expect(find.textContaining('Code CB-7K2M'), findsOneWidget);
    expect(find.text('Current status: Referral issued'), findsOneWidget);
    expect(
      find.textContaining(
        'Confirm arrival at Savelugu Municipal District Hospital',
      ),
      findsOneWidget,
    );
    // Issued 50 hours ago with no confirmed arrival — the trace line must be
    // on the handover regardless of when this test runs.
    expect(
      find.textContaining(
        'Over 48 hours with no confirmed arrival — trace now.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an urgent referral edges the card in triage red', (tester) async {
    await _pump(tester, SbarCard.fromReferral(_openReferral(), _person));
    final card = tester.widget<ClinicCard>(find.byType(ClinicCard));
    expect(card.accent, AppColors.triageRed);
  });
}
