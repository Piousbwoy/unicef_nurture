// The verdict page must stay short enough to act from.
//
// These guards pin the properties that the simplification is allowed to change
// the *look* of but not the *substance* of: the decision is stated once, the
// experimental score never borrows the authority of a confidence figure, and
// nothing a clinician acts on — danger signs, pre-referral stabilisation, the
// worklist — ever ends up behind a tap.
//
// The viewport is deliberately tall, not phone-sized: a lazy ListView does not
// build what is off-screen, so on a short screen "not found" cannot be
// distinguished from "not built". Everything here is an assertion about what is
// in the tree, which needs the whole tree to exist.
import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/core/ml/offline_inference_service.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/assessment/assessment_feature_adapter.dart';
import 'package:carebridge_ai/presentation/assessment/result_screen.dart';
import 'package:carebridge_ai/presentation/assessment/station/vitals_strip.dart';
import 'package:carebridge_ai/presentation/assessment/types.dart';
import 'package:carebridge_ai/presentation/assessment/widgets/cockpit_gauge.dart';
import 'package:carebridge_ai/presentation/shared/premium_cards/ai_insight_card.dart';
import 'package:carebridge_ai/presentation/shared/recommendation_kit.dart';
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

AssessmentContext _context() => AssessmentContext(
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
    fullName: 'Test patient',
    clientType: ClientType.newborn,
    dateOfBirth: DateTime.now().subtract(const Duration(days: 2)),
  ),
);

/// The classification this visit resolves to. It is the sentence the page keeps
/// repeating, which is why it doubles as the counter for "stated once".
const _classification = 'WELL NEWBORN — NO IMCI CLASSIFICATION';

AssessmentDraft _draft({
  List<String> signs = const [],
  List<String> dangerSigns = const [],
  List<ClinicalFinding> findings = const [],
  List<RecommendedAction> actions = const [],
}) => AssessmentDraft(
  inputs: {
    'age_in_days': 2,
    'danger_signs': signs,
    'temperature_celsius': 37.0,
    'respiratory_rate': 48,
    'pulse': 140,
  },
  result: AssessmentResult(
    clientType: ClientType.newborn,
    triage: TriageLevel.routine,
    classification: _classification,
    findings: findings,
    actions: actions,
    dangerSignsPresent: dangerSigns,
    confidence: RecommendationConfidence.high,
  ),
);

const _fastBreathing = ClinicalFinding(
  label: 'Fast breathing',
  detail: 'Breathing is faster than the band for this age.',
  severity: TriageLevel.watch,
  protocolSource: 'IMCI child',
  measuredValue: '62/min',
  threshold: '≥ 50/min',
  weight: 2,
);

OfflineRiskPrediction _prediction({bool blocked = false}) =>
    OfflineRiskPrediction(
      modelName: 'neonatal_sepsis',
      usingModel: true,
      riskProbability: .99,
      classification: 'high',
      featuresUsed: const ['temperature_celsius'],
      featuresMissing: const [],
      predictedAt: DateTime(2026),
      modelVersion: 'test-research',
      researchOutput: blocked ? null : .61,
      rawNeuralOutput: blocked ? null : .8,
      patientOutputAllowed: !blocked,
      runtimeVerified: !blocked,
      outputScope: blocked ? null : 'clinician_experimental',
      artifactSha256: blocked
          ? null
          : OfflineInferenceService.neonatalArtifact,
      inputPolicyVersion: blocked
          ? null
          : OfflineInferenceService.neonatalPolicy,
      observedValues: blocked
          ? const {}
          : const {
              'age_days': 2,
              'temperature_celsius': 37,
              'respiratory_rate_per_min': 48,
              'heart_rate_per_min': 140,
              'current_weight_kg': 3,
            },
      execution: ModelExecution.completed,
      applicability: ModelApplicability.applicable,
      inputQuality: ModelInputQuality.complete,
      evidence: ModelEvidence.legacyRealData,
      ruleInCandidate: true,
    );

class _StubService extends OfflineInferenceService {
  _StubService(this.prediction);
  final OfflineRiskPrediction prediction;
  @override
  Future<List<OfflineModelStatus>> modelStatuses() async => [];
  @override
  Future<Map<String, OfflineRiskPrediction>> runAllPredictions(
    OfflineFeatureBag bag, {
    bool includeNeonatal = true,
    bool includeChildPneumonia = true,
    bool includePreeclampsia = true,
    bool includeLbwSga = true,
  }) async => {'neonatal_sepsis': prediction};
}

Future<void> _pump(
  WidgetTester tester,
  AssessmentDraft draft, {
  OfflineInferenceService? service,
}) async {
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.runAsync(() => OfflineInferenceService.instance.modelStatuses());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [bootstrapProvider.overrideWith((ref) async {})],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1), disableAnimations: true),
          child: child!,
        ),
        home: AssessmentResultScreen(
          input: _context(),
          draft: draft,
          visitId: 'v1',
          inferenceService: service,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// `RecSection` paints its title in upper case.
Finder _section(String title) => find.text(title.toUpperCase());

Finder _inHero(Pattern pattern) => find.descendant(
  of: find.byType(AiInsightCard),
  matching: find.textContaining(pattern),
);

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('the experimental score never calls itself confidence', (
    tester,
  ) async {
    await _pump(tester, _draft(), service: _StubService(_prediction()));
    await tester.pumpAndSettle();

    // The honest label survives. The words that would borrow clinical authority
    // are absent from the hero — deliberately scoped to the hero, because
    // "full data confidence" elsewhere on the page honestly means how complete
    // the recorded observations are, not a model statistic.
    expect(find.text('Experimental model score'), findsOneWidget);
    expect(_inHero(RegExp('confidence', caseSensitive: false)), findsNothing);
    expect(_inHero(RegExp(r'95\s*%')), findsNothing);
    expect(_inHero(RegExp('error bar', caseSensitive: false)), findsNothing);
  });

  testWidgets('a blocked model draws no ring', (tester) async {
    await _pump(tester, _draft(), service: _StubService(_prediction(blocked: true)));
    await tester.pumpAndSettle();

    expect(find.byType(CockpitGauge), findsNothing);
    expect(find.text('Experimental model score'), findsNothing);
  });

  testWidgets('danger signs need no tap and no scroll', (tester) async {
    await _pump(
      tester,
      _draft(
        signs: const ['convulsions'],
        dangerSigns: const ['Convulsions'],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DANGER SIGNS PRESENT'), findsOneWidget);
  });

  testWidgets('pre-referral stabilisation still outranks the model hero', (
    tester,
  ) async {
    await _pump(
      tester,
      _draft(signs: const ['convulsions']),
      service: _StubService(_prediction()),
    );
    await tester.pumpAndSettle();

    final preReferral = find.text('Pre-referral stabilisation');
    final hero = find.byType(AiInsightCard);
    expect(preReferral, findsOneWidget);
    expect(hero, findsOneWidget);
    // Life-saving steps are never placed below an experimental number.
    expect(
      tester.getTopLeft(preReferral).dy,
      lessThan(tester.getTopLeft(hero).dy),
    );
  });

  testWidgets('secondary detail is folded behind one control', (tester) async {
    await _pump(
      tester,
      _draft(findings: const [_fastBreathing]),
      service: _StubService(_prediction()),
    );
    await tester.pumpAndSettle();

    // Collapsed by default, so the strip and the deck do not compete with the
    // decision for the worker's attention.
    expect(find.byType(VitalsStrip), findsNothing);
    expect(_section('What we found'), findsNothing);
    expect(find.text('Full clinical detail'), findsOneWidget);

    await tester.tap(find.text('Full clinical detail'));
    await tester.pumpAndSettle();

    expect(find.byType(VitalsStrip), findsOneWidget);
    expect(_section('What we found'), findsOneWidget);
  });

  testWidgets('the decision is stated once, not four times', (tester) async {
    await _pump(
      tester,
      _draft(findings: const [_fastBreathing]),
      service: _StubService(_prediction()),
    );
    await tester.pumpAndSettle();

    // Today the classification is painted by the protocol header, the handoff
    // brief card and the report teaser; a worker reading in a hurry should only
    // have to read it once.
    expect(find.text(_classification), findsOneWidget);
  });

  testWidgets('the worklist keeps the title the queue already uses', (
    tester,
  ) async {
    await _pump(
      tester,
      _draft(
        actions: const [
          RecommendedAction(
            instruction: 'Give the first antibiotic dose',
            urgency: ReferralUrgency.immediate,
            isPrereferralTreatment: true,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(_section('Prioritized actions'), findsOneWidget);
    expect(find.textContaining('antibiotic dose'), findsOneWidget);
  });

  testWidgets('one doorway to the report, not three', (tester) async {
    await _pump(
      tester,
      _draft(findings: const [_fastBreathing]),
      service: _StubService(_prediction()),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        RegExp('full clinical report', caseSensitive: false),
      ),
      findsOneWidget,
    );
  });
}
