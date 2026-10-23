/// The stability line, proven on the real screen.
///
/// The domain tests show the counterfactual computes correctly; this shows the
/// nurse actually sees it — and, just as importantly, that a record outside the
/// sick-child protocol shows *nothing*. A line like this earns trust by being
/// silent when it has no business speaking.
library;

import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/core/ml/offline_inference_service.dart';
import 'package:carebridge_ai/domain/engines/child_engine.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/assessment/result_screen.dart';
import 'package:carebridge_ai/presentation/assessment/types.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _household = Household(
  id: 'h1',
  name: 'Test household',
  region: 'Northern',
  district: 'Gushegu',
  community: 'Gushegu',
  createdBy: 'u1',
);

AssessmentContext _context({
  required int ageInMonths,
  ClientType type = ClientType.childUnderFive,
}) => AssessmentContext(
  user: AppUser(
    id: 'u1',
    fullName: 'Test nurse',
    phone: '0244000000',
    role: UserRole.frontlineHealthWorker,
    region: 'Northern',
    district: 'Gushegu',
    community: 'Gushegu',
  ),
  household: _household,
  person: Person(
    id: 'p1',
    householdId: 'h1',
    fullName: 'Amina Baba',
    clientType: type,
    dateOfBirth: DateTime.now().subtract(Duration(days: ageInMonths * 30)),
  ),
);

/// A child record written the way `child_form.dart` writes one, classified by the
/// real engine — so the screen's reconstruction has to agree with it.
AssessmentDraft _childDraft({required int ageInMonths, required int respiratoryRate}) {
  final input = ChildInput(
    ageInMonths: ageInMonths,
    respiratoryRate: respiratoryRate,
    temperatureCelsius: 37.0,
    weightKg: 7.6,
    cough: true,
  );
  final verdict = ChildEngine.assess(input);
  return AssessmentDraft(
    inputs: {
      'protocol': 'imci_child',
      'age_in_months': ageInMonths,
      'respiratory_rate': respiratoryRate,
      'temperature_celsius': 37.0,
      'weight_kg': 7.6,
      'danger_signs': const <String>['cough'],
      'skin_pinch_result': 'none',
      'palmar_pallor_severity': 'none',
      'rdt_done': false,
      'vaccines_given': const <String>[],
    },
    result: AssessmentResult(
      clientType: ClientType.childUnderFive,
      triage: verdict.triage,
      classification: verdict.classification,
      findings: verdict.findings,
      actions: const [],
      confidence: RecommendationConfidence.high,
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  AssessmentDraft draft, {
  required int ageInMonths,
  ClientType type = ClientType.childUnderFive,
}) async {
  tester.view.physicalSize = const Size(1080, 7000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.runAsync(() => OfflineInferenceService.instance.modelStatuses());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [bootstrapProvider.overrideWith((ref) async {})],
      child: MaterialApp(
        home: AssessmentResultScreen(
          input: _context(ageInMonths: ageInMonths, type: type),
          draft: draft,
          visitId: 'v1',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('a call sitting on the line shows the re-count line', (tester) async {
    // 51/min against a 50/min cut-off at six months: one breath decides it.
    await _pump(
      tester,
      _childDraft(ageInMonths: 6, respiratoryRate: 51),
      ageInMonths: 6,
    );

    final eyebrow = find.textContaining('WOULD A RE-COUNT CHANGE IT');
    expect(eyebrow, findsOneWidget, reason: 'the stability heading is missing');

    // The note must carry the numbers, not just a mood.
    expect(
      find.textContaining('51', findRichText: true),
      findsWidgets,
      reason: 'the line should quote the rate that sits on the cut-off',
    );
  });

  testWidgets('a comfortable call does not warn about nothing', (tester) async {
    // 60/min at six months clears 50 by 10 breaths — 20% over, not borderline.
    // With MUAC uncounted the honest line is the gap, so the heading stays and
    // the warning wording must not appear.
    await _pump(
      tester,
      _childDraft(ageInMonths: 6, respiratoryRate: 60),
      ageInMonths: 6,
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('worth counting once more'),
      findsNothing,
    );
  });

  testWidgets('a non-child record says nothing about re-counts', (tester) async {
    // A maternal assessment is a different protocol with different thresholds;
    // the child probe has no business commenting on it.
    final draft = AssessmentDraft(
      inputs: const {
        'protocol': 'anc',
        'age_in_months': null,
        'danger_signs': <String>[],
      },
      result: AssessmentResult(
        clientType: ClientType.pregnantWoman,
        triage: TriageLevel.routine,
        classification: 'NORMAL PREGNANCY',
        findings: const [],
        actions: const [],
        confidence: RecommendationConfidence.high,
      ),
    );
    await _pump(tester, draft, ageInMonths: 28, type: ClientType.pregnantWoman);

    expect(
      find.textContaining('WOULD A RE-COUNT CHANGE IT'),
      findsNothing,
      reason: 'the child probe must stay silent outside its own protocol',
    );
  });

  testWidgets('the verdict reads as one plate with labelled fact rows', (tester) async {
    // Sleek here means scannable: one plate, one accent, and each fact carrying
    // its own label instead of four facts crammed into run-on sentences.
    await _pump(
      tester,
      _childDraft(ageInMonths: 6, respiratoryRate: 51),
      ageInMonths: 6,
    );

    expect(
      find.byKey(const ValueKey('verdict-plate')),
      findsOneWidget,
      reason: 'the decision brief should sit in a single plate',
    );
    expect(find.textContaining('MEASUREMENT'), findsOneWidget);
    expect(
      find.textContaining('51', findRichText: true),
      findsWidgets,
      reason: 'the rate that produced the verdict stays on the card',
    );
    // One condition name, once: the plate must not restate it as a sentence too.
    expect(
      find.textContaining('WOULD A RE-COUNT CHANGE IT'),
      findsOneWidget,
    );
  });

  testWidgets('the plate does not repeat a condition the header already names', (tester) async {
    // Seen in a rendered screenshot, not in a spec: an untaught classification
    // arrived as the hero headline, again as the plate's condition header, and a
    // third time inside the explanation. Three copies of a name is the crowding
    // this card exists to remove.
    final draft = AssessmentDraft(
      inputs: const {
        'protocol': 'young_infant',
        'age_in_days': 2,
        'danger_signs': <String>[],
      },
      result: AssessmentResult(
        clientType: ClientType.newborn,
        triage: TriageLevel.urgent,
        classification: 'POSSIBLE SERIOUS BACTERIAL INFECTION',
        findings: const [],
        actions: const [],
        confidence: RecommendationConfidence.high,
      ),
    );
    await _pump(tester, draft, ageInMonths: 0, type: ClientType.newborn);

    final named = find.byWidgetPredicate(
      (w) =>
          w is Text &&
          (w.data ?? '').toUpperCase().contains('POSSIBLE SERIOUS BACTERIAL'),
    );
    // Two, not four: the verdict header and the line that will be read aloud.
    // The plate header repeated the name for no reason, and the explanation
    // quoted it a third time while apologising for eight lines — on an urgent
    // card, that is what pushes the referral off the screen.
    expect(named, findsNWidgets(2));
  });
}
