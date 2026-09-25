// Clinical decisions must remain independent of research model availability.
import 'dart:async';
import 'dart:convert';
import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/data/repositories/care_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:carebridge_ai/core/ml/offline_inference_service.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/assessment/result_screen.dart';
import 'package:carebridge_ai/presentation/assessment/assessment_feature_adapter.dart';
import 'package:carebridge_ai/presentation/assessment/decision_workspace.dart';
import 'package:carebridge_ai/presentation/assessment/station/vitals_strip.dart';
import 'package:carebridge_ai/presentation/assessment/types.dart';
import 'package:carebridge_ai/presentation/shared/recommendation_kit.dart';
import 'package:carebridge_ai/presentation/shared/premium_cards/ai_insight_card.dart';
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
  int age = 2,
  ClientType type = ClientType.newborn,
  BirthRecord? birth,
  MaternalRecord? maternal,
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
    fullName: 'Test patient',
    clientType: type,
    dateOfBirth: DateTime.now().subtract(Duration(days: age)),
  ),
  birth: birth,
  maternal: maternal,
);
AssessmentDraft _draft({
  int age = 2,
  List<String> signs = const [],
  ClientType type = ClientType.newborn,
  Map<String, Object?>? inputs,
  List<String> dangerSigns = const [],
  NutritionStatus? nutritionStatus,
  List<String>? vaccinesGiven,
}) => AssessmentDraft(
  inputs:
      inputs ??
      {
        'age_in_days': age,
        'danger_signs': signs,
        'temperature_celsius': 37.0,
        'respiratory_rate': 48,
        'pulse': 140,
        if (vaccinesGiven != null) ...{'vaccines_given': vaccinesGiven},
      },
  result: AssessmentResult(
    clientType: type,
    triage: TriageLevel.routine,
    classification: 'WELL NEWBORN — NO IMCI CLASSIFICATION',
    findings: const [],
    actions: const [],
    dangerSignsPresent: dangerSigns,
    nutritionStatus: nutritionStatus,
    confidence: RecommendationConfidence.high,
  ),
);

/// A finding this visit produced that is nobody else's: the deck owns it.
const _fastBreathing = ClinicalFinding(
  label: 'Fast breathing',
  detail: 'Breathing is faster than the band for this age.',
  severity: TriageLevel.watch,
  protocolSource: 'IMCI child',
  measuredValue: '62/min',
  threshold: '≥ 50/min',
  weight: 2,
);

/// Nine months old with nothing given, so a long list of doses is overdue.
/// [findings] decides whether anything besides the schedule is wrong too.
AssessmentDraft _epiDraft({
  List<ClinicalFinding> findings = const [_fastBreathing],
}) => AssessmentDraft(
  inputs: {
    'age_in_days': 270,
    'danger_signs': const <String>[],
    'temperature_celsius': 37.0,
    'respiratory_rate': 62,
    'pulse': 110,
    'vaccines_given': const <String>[],
  },
  result: AssessmentResult(
    clientType: ClientType.newborn,
    triage: TriageLevel.routine,
    classification: 'WELL NEWBORN — NO IMCI CLASSIFICATION',
    findings: findings,
    actions: const [],
    confidence: RecommendationConfidence.high,
  ),
);

Future<void> _pump(
  WidgetTester tester,
  AssessmentDraft draft, {
  int age = 2,
  OfflineInferenceService? service,
  CareRepository? repository,
  Size size = const Size(1080, 6000),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.runAsync(() => OfflineInferenceService.instance.modelStatuses());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bootstrapProvider.overrideWith((ref) async {}),
        if (repository != null)
          careRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: AssessmentResultScreen(
          input: _context(age: age),
          draft: draft,
          visitId: 'v1',
          inferenceService: service,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The working sheet is part of the result page now: scroll down to it rather
/// than opening a page. `RecSection` paints its title in upper case.
final _actionsHeader = find.text('PRIORITIZED ACTIONS');

/// The page scrollable: the merged sheet nests smaller ones (chip rows,
/// worklists), so the outermost is the one that scrolls.
final _page = find.byType(Scrollable).first;

Future<void> _toSheet(WidgetTester tester) async {
  await tester.scrollUntilVisible(_actionsHeader, 400, scrollable: _page);
  await tester.ensureVisible(_actionsHeader);
  await tester.pumpAndSettle();
}

/// Opens the clinical-detail fold. `pumpWidget` reuses the screen's state
/// across re-pumps within one test, so the fold may already be open from a
/// previous scenario — only tap when it is closed, and gate on `evaluate()`
/// (the truthful built-tree signal) so the helper is idempotent.
Future<void> _openDetail(WidgetTester tester) async {
  for (var i = 0; i < 2; i++) {
    if (find.byType(VitalsStrip).evaluate().isNotEmpty) return;
    await tester.tap(find.text('Full clinical detail'));
    await tester.pumpAndSettle();
  }
}

Future<void> _report(WidgetTester tester, {bool experimental = false}) async {
  // The report doorway is the whole teaser card now — one tap target,
  // labelled once. `ensureVisible` (not just `scrollUntilVisible`) because
  // the widget may already be built but dragged outside the viewport: it
  // exists, so the "is it visible yet" loop no-ops and the tap misses.
  final doorway = find.text('Full clinical report');
  await tester.scrollUntilVisible(doorway, 400, scrollable: _page);
  await tester.ensureVisible(doorway);
  await tester.pumpAndSettle();
  await tester.tap(doorway);
  await tester.pumpAndSettle();
  if (experimental) {
    await tester.scrollUntilVisible(find.byType(AiInsightCard), 300);
    expect(find.byType(ResearchAnalysisPanel), findsNothing);
    return;
  }
  await tester.scrollUntilVisible(find.byType(ResearchAnalysisPanel), 300);
  final panel = tester.widget<ResearchAnalysisPanel>(
    find.byType(ResearchAnalysisPanel),
  );
  await tester.runAsync(
    () => panel.statuses.timeout(const Duration(seconds: 2)),
  );
  await tester.pumpAndSettle();
}

OfflineRiskPrediction _prediction({
  ModelExecution execution = ModelExecution.completed,
  ModelApplicability applicability = ModelApplicability.applicable,
  ModelInputQuality quality = ModelInputQuality.complete,
  ModelEvidence evidence = ModelEvidence.retrospectiveResearch,
  double score = .987,
  bool experimental = false,
}) => OfflineRiskPrediction(
  modelName: 'neonatal_sepsis',
  usingModel: true,
  riskProbability: .99,
  classification: 'high',
  featuresUsed: const ['temperature_celsius'],
  featuresMissing: quality == ModelInputQuality.missingObservations
      ? const ['pulse']
      : const [],
  predictedAt: DateTime(2026),
  modelVersion: 'test-research',
  researchOutput: score,
  rawNeuralOutput: .8,
  patientOutputAllowed: experimental,
  runtimeVerified: experimental,
  outputScope: experimental ? 'clinician_experimental' : null,
  artifactSha256: experimental
      ? OfflineInferenceService.neonatalArtifact
      : null,
  inputPolicyVersion: experimental
      ? OfflineInferenceService.neonatalPolicy
      : null,
  observedValues: experimental
      ? const {
          'age_days': 2,
          'temperature_celsius': 37,
          'respiratory_rate_per_min': 48,
          'heart_rate_per_min': 140,
          'current_weight_kg': 3,
        }
      : const {},
  execution: execution,
  applicability: applicability,
  inputQuality: quality,
  evidence: experimental ? ModelEvidence.legacyRealData : evidence,
  ruleInCandidate: true,
);

class _CaptureRepository extends CareRepository {
  Assessment? assessment;
  Referral? referral;
  @override
  Future<void> saveAssessment(
    AppUser user,
    Assessment assessment, {
    Referral? referral,
    List<ScheduledContact> followUps = const [],
  }) async {
    this.assessment = assessment;
    this.referral = referral;
  }
}

class _DelayedService extends OfflineInferenceService {
  final predictions = Completer<Map<String, OfflineRiskPrediction>>();
  @override
  Future<List<OfflineModelStatus>> modelStatuses() async => [];
  @override
  Future<Map<String, OfflineRiskPrediction>> runAllPredictions(
    OfflineFeatureBag bag, {
    bool includeNeonatal = true,
    bool includeChildPneumonia = true,
    bool includePreeclampsia = true,
    bool includeLbwSga = true,
  }) => predictions.future;
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  test(
    'analysis uses the same experimental display permission as reasoning',
    () {
      expect(
        AnalysisViewModel(_prediction(experimental: true)).mayShowOutput,
        isTrue,
      );
      expect(AnalysisViewModel(_prediction()).mayShowOutput, isFalse);
    },
  );

  testWidgets(
    'experimental card leads clinical findings without changing urgent care',
    (tester) async {
      final service = _DelayedService();
      await _pump(tester, _draft(signs: ['convulsions']), service: service);
      expect(find.textContaining('Model analysis pending'), findsOneWidget);
      expect(find.text('Pre-referral stabilisation'), findsOneWidget);
      service.predictions.complete({
        'neonatal_sepsis': _prediction(experimental: true, score: .01),
      });
      await tester.pumpAndSettle();
      expect(find.text('Experimental model score'), findsOneWidget);
      expect(
        find.textContaining('regardless of the experimental score'),
        findsWidgets,
      );
      expect(
        tester.getTopLeft(find.byType(AiInsightCard)).dy,
        lessThan(tester.getTopLeft(find.byType(ClinicalDecisionHeader)).dy),
      );
      expect(find.text('Clinical Protocol Check'), findsOneWidget);
      expect(find.byType(ResearchAnalysisPanel), findsNothing);
      expect(find.text('Pre-referral stabilisation'), findsOneWidget);
    },
  );

  testWidgets('pending save is explicit and late inference cannot rewrite it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final service = _DelayedService();
    final repository = _CaptureRepository();
    await _pump(tester, _draft(), service: service, repository: repository);
    await tester.tap(find.text('Save assessment'));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    final saved = repository.assessment!;
    final before = jsonEncode(saved.inputs);
    final snapshot =
        (saved.inputs['ml_predictions'] as Map)['neonatal_sepsis'] as Map;
    expect(snapshot['save_state'], 'pending_at_save');
    expect(snapshot['experimental_adjusted_output'], isNull);
    service.predictions.complete({
      'neonatal_sepsis': _prediction(experimental: true),
    });
    await tester.pumpAndSettle();
    expect(jsonEncode(saved.inputs), before);
    expect(saved.result.findings, isEmpty);
  });

  testWidgets('failed inference save is explicit and keeps protocol care', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final service = _DelayedService();
    final repository = _CaptureRepository();
    await _pump(tester, _draft(), service: service, repository: repository);
    service.predictions.completeError(
      StateError('test interpreter unavailable'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Model analysis failed'), findsOneWidget);
    await tester.tap(find.text('Save assessment'));
    await tester.pumpAndSettle();
    final saved = repository.assessment!;
    expect(
      ((saved.inputs['ml_predictions'] as Map)['neonatal_sepsis']
          as Map)['save_state'],
      'failed',
    );
    expect(saved.result.findings, isEmpty);
  });

  testWidgets('research-only signals cannot add a PSBI treatment or referral', (
    tester,
  ) async {
    await _pump(
      tester,
      _draft(signs: ['nasalFlaring', 'grunting', 'bleeding']),
    );
    expect(find.text('Pre-referral stabilisation'), findsNothing);
    expect(find.textContaining('AI rule-in candidate'), findsNothing);
    expect(find.text('PROTOCOL DECISION'), findsOneWidget);
    await _report(tester);
    expect(find.text('Missing observations'), findsOneWidget);
    expect(find.textContaining('Rule-in candidate:'), findsNothing);
    expect(find.textContaining('Risk 2.0%'), findsNothing);
  });

  testWidgets(
    'healthy newborn has no experimental reassurance or clinical score',
    (tester) async {
      await _pump(tester, _draft());
      expect(find.text('Pre-referral stabilisation'), findsNothing);
      await _report(tester);
      expect(find.text('Missing observations'), findsOneWidget);
      await tester.tap(find.text('Neonatal sepsis research'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Experimental model output — not a diagnosis'),
        findsOneWidget,
      );
      final evidenceText = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
          .join('\n');
      expect(evidenceText, contains('File integrity'));
      expect(evidenceText, contains('Checked'));
      expect(
        find.textContaining('saw no pattern of severe infection'),
        findsNothing,
      );
      expect(find.textContaining('screening tier'), findsNothing);
    },
  );

  testWidgets(
    '14-day-old convulsions activate clinical PSBI outside model support',
    (tester) async {
      await _pump(tester, _draft(age: 14, signs: ['convulsions']), age: 14);
      expect(find.text('Pre-referral stabilisation'), findsOneWidget);
      expect(find.textContaining('IMCI danger sign'), findsOneWidget);
      await _report(tester);
      expect(find.text('Outside model support'), findsOneWidget);
      expect(find.textContaining('Rule-in candidate:'), findsNothing);
    },
  );

  test(
    'historical negative never masks a current positive; old positive is not current',
    () {
      final context = _context(
        birth: const BirthRecord(
          personId: 'p1',
          historyOfConvulsions: false,
          feedingDifficulty: true,
          birthWeightKg: 2.4,
        ),
      );
      final current = AssessmentFeatureAdapter(
        context,
        _draft(signs: ['convulsions']),
      ).features;
      expect(current.historyOfConvulsions, isTrue);
      expect(current.feedingDifficulty, isFalse);
      expect(current.birthWeightKg, 2.4);
      expect(current.currentWeightKg, isNull);
      final measured = AssessmentFeatureAdapter(
        context,
        _draft(inputs: const {'weight_kg': 3.1, 'pulse': 140}),
      ).features;
      expect(measured.currentWeightKg, 3.1);
      expect(measured.birthWeightKg, 2.4);
      final unknown = AssessmentFeatureAdapter(
        context,
        _draft(inputs: const {}),
      ).features;
      expect(unknown.feedingDifficulty, isNull);
      expect(unknown.historyOfConvulsions, isNull);
    },
  );

  test('uncollected symptoms and ambiguous cord redness stay unknown', () {
    final bag = AssessmentFeatureAdapter(
      _context(),
      _draft(signs: ['cordRed']),
    ).features;
    expect(bag.cordPus, isNull);
    expect(bag.grunting, isNull);
    expect(bag.bleedingFromAnySite, isNull);
    expect(bag.abdominalDistension, isNull);
    expect(bag.historyOfConvulsions, isFalse);
  });

  test(
    'current maternal symptoms override historical false and ignore old positives',
    () {
      final context = _context(
        type: ClientType.pregnantWoman,
        maternal: const MaternalRecord(
          personId: 'p1',
          headacheSevere: false,
          blurredVision: true,
          gravida: 3,
        ),
      );
      final bag = AssessmentFeatureAdapter(
        context,
        _draft(
          type: ClientType.pregnantWoman,
          inputs: const {
            'danger_signs': ['headache'],
            'pre_eclampsia_flags': <String>[],
            'gestational_weeks': 32,
          },
        ),
      ).features;
      expect(bag.headacheSevere, isTrue);
      expect(bag.blurredVision, isFalse);
      expect(bag.gravida, 3);
      expect(bag.ageDays, isNull);
    },
  );

  test('general adult visit does not imply obstetric eligibility', () {
    final adapter = AssessmentFeatureAdapter(
      _context(type: ClientType.womanOfReproductiveAge),
      _draft(
        type: ClientType.womanOfReproductiveAge,
        inputs: const {
          'systolic': 180,
          'diastolic': 120,
          'danger_signs': ['convulsions'],
        },
      ),
    );
    expect(adapter.stabilization.isMaternal, isFalse);
    expect(adapter.stabilization.hasEclampsiaConvulsions, isFalse);
    expect(adapter.features.gestationalWeeks, isNull);
  });

  test('invalid explicit age does not fall back to stored age', () {
    final adapter = AssessmentFeatureAdapter(
      _context(),
      _draft(inputs: const {'age_in_days': 1.5}),
    );
    expect(adapter.features.ageDays, isNull);
  });

  testWidgets(
    'analysis states suppress numbers and preserve input correction',
    (tester) async {
      var edited = false;
      final cases = <(OfflineRiskPrediction, String)>[
        (
          _prediction(execution: ModelExecution.integrityFailure),
          'Integrity failure',
        ),
        (
          _prediction(execution: ModelExecution.invalidMetadata),
          'Invalid metadata',
        ),
        (_prediction(execution: ModelExecution.failed), 'Execution failure'),
        (
          _prediction(execution: ModelExecution.unavailable),
          'Model unavailable',
        ),
        (
          _prediction(applicability: ModelApplicability.unsupportedCohort),
          'Unsupported or unknown cohort',
        ),
        (
          _prediction(quality: ModelInputQuality.missingObservations),
          'Missing observations',
        ),
        (
          _prediction(quality: ModelInputQuality.invalidValues),
          'Review measurements',
        ),
        (
          _prediction(quality: ModelInputQuality.outsideSupport),
          'Outside model support',
        ),
        (_prediction(evidence: ModelEvidence.synthetic), 'Research only'),
      ];
      for (final (prediction, message) in cases) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ResearchAnalysisPanel(
                  key: ValueKey(message),
                  predictions: Future.value({'neonatal_sepsis': prediction}),
                  statuses: Future.value([]),
                  showEvidence: true,
                  onEdit: () => edited = true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(message), findsOneWidget);
        if (message == 'Missing observations') {
          await tester.tap(find.text('Review assessment inputs'));
          expect(edited, isTrue);
        }
        await tester.tap(find.text('Neonatal sepsis research'));
        await tester.pumpAndSettle();
        expect(find.text('0.987'), findsNothing);
        expect(
          find.textContaining('not a diagnosis or treatment threshold'),
          findsOneWidget,
        );
      }
    },
  );

  testWidgets('research output requires matching usable permitted evidence', (
    tester,
  ) async {
    for (final (version, usable, allowed, shown) in [
      ('test-research', true, true, true),
      ('different-version', true, true, false),
      ('test-research', false, true, false),
      ('test-research', true, false, false),
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ResearchAnalysisPanel(
                predictions: Future.value({
                  'neonatal_sepsis': _prediction(experimental: true),
                }),
                statuses: Future.value([
                  OfflineModelStatus(
                    name: 'neonatal_sepsis',
                    modelAssetPath: 'test-artifact',
                    metricsAssetPath: 'test-metadata',
                    isModelPresent: true,
                    isModelUsable: usable,
                    hasMetrics: true,
                    expectedSha256: 'test-hash',
                    actualSha256: 'test-hash',
                    integrityVerified: usable,
                    metadataValid: usable,
                    modelVersion: version,
                    contract: {'patient_output_allowed': allowed},
                  ),
                ]),
                showEvidence: true,
                onEdit: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0.987'), findsNothing);
      await tester.tap(find.text('Neonatal sepsis research'));
      await tester.pumpAndSettle();
      // Research output is now shown as a percentage in the gauge
      expect(find.text('98.7/100'), shown ? findsOneWidget : findsNothing);
      expect(find.textContaining('99%'), findsNothing);
      expect(
        find.text('Experimental model score'),
        shown ? findsOneWidget : findsNothing,
      );
      expect(
        find.textContaining('not a diagnosis or treatment threshold'),
        findsOneWidget,
      );
    }
  });

  testWidgets('metadata failure does not hide analysis state or show output', (
    tester,
  ) async {
    final statuses = Completer<List<OfflineModelStatus>>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ResearchAnalysisPanel(
              predictions: Future.value({'neonatal_sepsis': _prediction()}),
              statuses: statuses.future,
              showEvidence: true,
              onEdit: () {},
            ),
          ),
        ),
      ),
    );
    // Use pump() instead of pumpAndSettle() because Shimmer has infinite animation
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Research only'), findsOneWidget);
    // Loading state now shows a skeleton loader
    expect(find.byType(ResearchAnalysisPanel), findsOneWidget);
    statuses.completeError(StateError('missing metadata'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Evidence metadata unavailable'),
      findsOneWidget,
    );
    await tester.tap(find.text('Neonatal sepsis research'));
    await tester.pumpAndSettle();
    expect(find.text('0.987'), findsNothing);
  });

  testWidgets(
    'late experimental output preserves referral and worklist choices',
    (tester) async {
      final service = _DelayedService();
      await _pump(tester, _draft(), service: service);
      expect(find.text('PROTOCOL DECISION'), findsOneWidget);
      // Loading state now shows a skeleton loader instead of text
      expect(find.byType(ResearchAnalysisPanel), findsOneWidget);
      await _toSheet(tester);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      final checks = find.descendant(
        of: find.byType(ActionWorklist),
        matching: find.byType(Checkbox),
      );
      final before = tester
          .widgetList<Checkbox>(checks)
          .map((w) => w.value)
          .toList();
      final referral = find.text('Add a referral (clinical judgement)');
      // No referral ordered: the sheet says so in one quiet row, and the
      // arrangement controls stay out of the way until one is added.
      expect(referral, findsOneWidget);
      expect(find.text('HOW SOON?'), findsNothing);
      await tester.tap(referral);
      await tester.pumpAndSettle();
      service.predictions.complete({
        'neonatal_sepsis': _prediction(experimental: true),
      });
      await tester.pumpAndSettle();
      expect(find.text('Remove referral'), findsOneWidget);
      expect(find.text('HOW SOON?'), findsOneWidget);
      await _report(tester, experimental: true);
      expect(find.textContaining('Rule-in candidate:'), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await _toSheet(tester);
      expect(find.text('Remove referral'), findsOneWidget);
      expect(
        tester.widgetList<Checkbox>(checks).map((w) => w.value).toList(),
        before,
      );
      expect(find.text('Pre-referral stabilisation'), findsNothing);
    },
  );

  testWidgets('saved clinical findings never acquire an experimental score', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final service = _DelayedService();
    final repository = _CaptureRepository();
    await _pump(tester, _draft(), service: service, repository: repository);
    service.predictions.complete({
      'neonatal_sepsis': _prediction(experimental: true),
    });
    await tester.pumpAndSettle();
    expect(find.text('High model score'), findsOneWidget);
    expect(find.text('Pre-referral stabilisation'), findsNothing);
    await tester.tap(find.text('Save assessment'));
    await tester.pumpAndSettle();
    final saved = repository.assessment!;
    expect(repository.referral, isNull);
    expect(saved.result.findings, isEmpty);
    final serialized =
        (saved.inputs['ml_predictions'] as Map)['neonatal_sepsis'] as Map;
    expect(serialized['save_state'], 'completed');
    expect(serialized['experimental_raw_output'], .8);
    expect(serialized['experimental_adjusted_output'], .987);
    expect(serialized['clinical_use_allowed'], isFalse);
    final reloaded = jsonDecode(jsonEncode(saved.inputs)) as Map;
    expect(reloaded['ml_predictions']['neonatal_sepsis'], serialized);
    expect(serialized['risk_probability'], isNull);
    expect(serialized['classification'], 'unavailable');
    expect(serialized['rule_in_candidate'], 0);
    expect(saved.carePlanJson, isNot(contains('0.987')));
    expect(saved.carePlanJson, isNot(contains('neonatal_sepsis')));
    expect(
      (jsonDecode(saved.carePlanJson!) as Map)['overall_triage'],
      'routine',
    );
  });

  testWidgets(
    'clinical override reason survives analysis and evidence navigation',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final service = _DelayedService();
      final repository = _CaptureRepository();
      await _pump(tester, _draft(), service: service, repository: repository);
      await _toSheet(tester);
      await tester.ensureVisible(
        find.text('Disagree with this plan? Record a clinical override'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Disagree with this plan? Record a clinical override'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(ChoiceChip, TriageLevel.watch.label),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Clinical review needed for persistent caregiver concern',
      );
      service.predictions.complete({
        'neonatal_sepsis': _prediction(execution: ModelExecution.failed),
      });
      await tester.pumpAndSettle();
      await _report(tester);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await _toSheet(tester);
      expect(
        find.text('Disagree with this plan? Record a clinical override'),
        findsNothing,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Clinical review needed for persistent caregiver concern',
      );
      await tester.tap(find.text('Save assessment'));
      await tester.pumpAndSettle();
      expect(repository.assessment!.overriddenTriage, TriageLevel.watch);
      expect(
        repository.assessment!.overrideReason,
        'Clinical review needed for persistent caregiver concern',
      );
      expect(repository.referral, isNull);
    },
  );

  testWidgets('complete decision workspace supports 320px and 200% text', (
    tester,
  ) async {
    await _pump(tester, _draft(), size: const Size(320, 1000), textScale: 2);
    await _toSheet(tester);
    await tester.scrollUntilVisible(
      find.text('Full clinical report'),
      400,
      scrollable: _page,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    await _report(tester);
    await tester.scrollUntilVisible(find.text('Neonatal sepsis research'), 300);
    await tester.ensureVisible(find.text('Neonatal sepsis research'));
    await tester.pumpAndSettle();
    expect(find.text('Neonatal sepsis research').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Neonatal sepsis research'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('decision header and worklist support 320px and 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ProviderScope(
          child: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    ClinicalDecisionHeader(
                      classification: 'URGENT REFERRAL',
                      level: TriageLevel.urgent,
                      missingCount: 1,
                      rationale: 'Convulsions observed during this visit.',
                    ),
                    const ActionWorklist(
                      actions: [
                        RecommendedAction(
                          instruction: 'Arrange referral now',
                          urgency: ReferralUrgency.immediate,
                          rationale: 'Observed danger sign',
                          protocolSource: 'Existing protocol',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // The header is a verdict, not a doorway: the sheet is on the same page.
    expect(find.text('Open care plan'), findsNothing);
    expect(find.byType(ActionWorklist), findsOneWidget);
  });

  testWidgets(
    'the sheet lists each action once: EPI and food sit in their own sections',
    (tester) async {
      // Nine months old, nothing given yet, and at risk of malnutrition: the
      // plan the engines synthesize is mostly EPI and food lines.
      await _pump(
        tester,
        _draft(
          age: 270,
          nutritionStatus: NutritionStatus.atRisk,
          vaccinesGiven: const [],
        ),
        age: 270,
      );
      await _toSheet(tester);

      final shown = tester
          .widget<ActionWorklist>(find.byType(ActionWorklist))
          .actions
          .map((a) => a.instruction)
          .toList();
      expect(shown, isNotEmpty);
      expect(shown.where((s) => s.startsWith('Give today:')), isEmpty);
      expect(shown.where((s) => s.startsWith('Start with:')), isEmpty);

      // The detail is one tap away rather than one scroll further down. The
      // dose card is also the proof the EPI action existed to be filtered:
      // both are generated from the same non-empty `giveToday` list.
      final epi = find.text('IMMUNISATION');
      final giveToday = find.text('GIVE TODAY — IN THIS SAME SESSION');
      expect(epi, findsOneWidget);
      expect(giveToday.hitTestable(), findsNothing);
      await tester.scrollUntilVisible(epi, 300, scrollable: _page);
      await tester.ensureVisible(epi);
      await tester.pumpAndSettle();
      await tester.tap(epi);
      await tester.pumpAndSettle();
      expect(giveToday.hitTestable(), findsOneWidget);
    },
  );

  testWidgets('a dose reads once: the schedule is only under IMMUNISATION', (
    tester,
  ) async {
    // Fast breathing plus a long list of overdue doses: the deck has a real
    // finding of its own, and must still keep the doses out.
    await _pump(tester, _epiDraft(), age: 270);

    // The deck is the working material behind the verdict — it lives inside
    // the clinical-detail fold, so open it before asserting on the deck.
    await tester.tap(find.text('Full clinical detail'));
    await tester.pumpAndSettle();

    // No measured value is restated as a chip row above the findings deck.
    expect(find.text('THE NUMBERS BEHIND THE VERDICT'), findsNothing);

    // The two sentences that name the leading findings both fold to a count:
    // the verdict line and the family's takeaway. Neither recites a dose.
    expect(find.textContaining('immunisation gaps'), findsNWidgets(2));
    expect(find.textContaining('because of: BCG'), findsNothing);
    expect(find.textContaining('Driven by BCG'), findsNothing);

    final deck = find.ancestor(
      of: find.text('WHAT WE FOUND'),
      matching: find.byType(RecSection),
    );
    expect(deck, findsOneWidget);
    expect(
      find.descendant(of: deck, matching: find.textContaining('BCG')),
      findsNothing,
    );
    expect(
      find.descendant(of: deck, matching: find.textContaining('breath')),
      findsWidgets,
    );

    // The full report is the record: it still lists every dose.
    await _report(tester);
    expect(find.textContaining('BCG'), findsWidgets);
  });

  testWidgets('a folded sentence keeps the clinical driver beside the count', (
    tester,
  ) async {
    // Something genuinely wrong as well as the schedule: the fold replaces the
    // dose list inside a sentence it did not write, so the neighbouring driver
    // and each sentence's own separator have to survive.
    await _pump(
      tester,
      _epiDraft(
        findings: const [
          ClinicalFinding(
            label: 'Some swelling of the feet',
            detail: 'Both feet swell and leave a dent after pressing.',
            severity: TriageLevel.priority,
            protocolSource: 'IMCI child',
            weight: 9,
          ),
        ],
      ),
      age: 270,
    );

    expect(
      find.textContaining('because of: Some swelling of the feet; 16 '),
      findsOneWidget,
    );
    expect(
      find.textContaining('Driven by Some swelling of the feet, 16 '),
      findsOneWidget,
    );
  });

  testWidgets(
    'with the schedule folded away, the deck says nothing rather than all-clear',
    (tester) async {
      await _pump(tester, _epiDraft(findings: const []), age: 270);

      // Every finding this visit produced is a dose. The section that would
      // otherwise answer with a green all-clear card under a priority verdict
      // is skipped outright — inside the fold too, so open it first.
      await tester.tap(find.text('Full clinical detail'));
      await tester.pumpAndSettle();
      expect(find.text('WHAT WE FOUND'), findsNothing);
      expect(find.text('No concerning findings'), findsNothing);
      expect(find.text('IMMUNISATION'), findsOneWidget);
    },
  );

  testWidgets('with no immunisation gap the verdict line is the saved one', (
    tester,
  ) async {
    await _pump(tester, _draft());
    expect(find.text('No abnormal findings — routine care.'), findsOneWidget);
    expect(find.textContaining('immunisation gap'), findsNothing);
  });

  testWidgets(
    'action completion survives reordering without losing distinct indications',
    (tester) async {
      const a = RecommendedAction(
        instruction: 'Review patient',
        urgency: ReferralUrgency.sameDay,
        rationale: 'First indication',
        protocolSource: 'Protocol A',
      );
      const b = RecommendedAction(
        instruction: 'Review patient',
        urgency: ReferralUrgency.scheduled,
        rationale: 'Second indication',
        protocolSource: 'Protocol B',
      );
      Future<void> render(List<RecommendedAction> actions) => tester.pumpWidget(
        MaterialApp(
          home: ProviderScope(
            child: Scaffold(
              body: ActionWorklist(
                key: const ValueKey('work'),
                actions: actions,
              ),
            ),
          ),
        ),
      );
      await render([a, b, a]);
      expect(find.text('0 of 2 done'), findsOneWidget);
      await tester.tap(find.text('Review patient').first);
      await tester.pump();
      expect(find.text('1 of 2 done'), findsOneWidget);
      await render([b, a]);
      expect(find.text('1 of 2 done'), findsOneWidget);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('FOLLOW-UP'), findsOneWidget);
    },
  );

  testWidgets(
    'vitals strip shows decision-relevant vitals and hides when none',
    (tester) async {
      await _pump(tester, _draft());
      await _openDetail(tester);
      expect(find.byType(VitalsStrip), findsOneWidget);
      expect(
        find.bySemanticsLabel('Vitals recorded this visit'),
        findsOneWidget,
      );
      expect(find.text('TEMPERATURE'), findsOneWidget);
      // Breathing rate decided nothing in this assessment, so it stays off
      // the headline strip — it remains saved in the visit inputs.
      expect(find.text('BREATHING RATE'), findsNothing);
      expect(find.textContaining('37.0'), findsWidgets);

      // A respiratory danger sign earns the breathing-rate chip its place.
      await _pump(tester, _draft(dangerSigns: const ['Difficulty breathing']));
      await _openDetail(tester);
      expect(find.byType(VitalsStrip), findsOneWidget);
      expect(find.text('BREATHING RATE'), findsOneWidget);

      await _pump(
        tester,
        _draft(inputs: const {'age_in_days': 2, 'danger_signs': <String>[]}),
      );
      await _openDetail(tester);
      expect(find.byType(VitalsStrip), findsOneWidget);
      expect(find.bySemanticsLabel('Vitals recorded this visit'), findsNothing);
      expect(find.text('TEMPERATURE'), findsNothing);
    },
  );
}
