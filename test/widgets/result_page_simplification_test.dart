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
import 'dart:io';
import 'dart:ui' as ui;

import 'package:carebridge_ai/core/theme/app_theme.dart';
import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/core/ml/offline_inference_service.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/assessment/result_screen.dart';
import 'package:carebridge_ai/presentation/assessment/decision_workspace.dart';
import 'package:carebridge_ai/presentation/shared/recommendation_kit.dart';
import 'package:carebridge_ai/presentation/assessment/station/vitals_strip.dart';
import 'package:carebridge_ai/presentation/assessment/types.dart';
import 'package:carebridge_ai/presentation/assessment/widgets/cockpit_gauge.dart';
import 'package:carebridge_ai/presentation/shared/premium_cards/ai_insight_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _captureScreens = bool.fromEnvironment('RESULT_UI_SNAPSHOTS');

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
  String classification = _classification,
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
    classification: classification,
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
      artifactSha256: blocked ? null : OfflineInferenceService.neonatalArtifact,
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
  Size size = const Size(1080, 6000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.runAsync(() => OfflineInferenceService.instance.modelStatuses());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [bootstrapProvider.overrideWith((ref) async {})],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _captureScreens ? AppTheme.light : null,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1), disableAnimations: true),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('result-ui-capture'),
          child: AssessmentResultScreen(
            input: _context(),
            draft: draft,
            visitId: 'v1',
            inferenceService: service,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// Optional local rendering evidence; no patient data or golden baselines.
Future<void> _capture(WidgetTester tester, String name) async {
  if (!_captureScreens) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('result-ui-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '.dart_tool/result-ui-$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

/// `RecSection` paints its title in upper case.
Finder _section(String title) => find.text(title.toUpperCase());

Finder _inHero(Pattern pattern) => find.descendant(
  of: find.byType(AiInsightCard),
  matching: find.textContaining(pattern),
);

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(() async {
    if (!_captureScreens) return;
    // flutter_test ships no bundled fonts, so a capture would otherwise show
    // Ahem boxes. Load exactly the families the app declares.
    Future<void> load(String family, List<String> files) async {
      final loader = FontLoader(family);
      for (final file in files) {
        loader.addFont(rootBundle.load(file));
      }
      await loader.load();
    }

    await load('Roboto', ['assets/fonts/Inter-Regular.ttf']);
    await load('Manrope', [
      'assets/fonts/Manrope-Regular.ttf',
      'assets/fonts/Manrope-Medium.ttf',
      'assets/fonts/Manrope-SemiBold.ttf',
      'assets/fonts/Manrope-Bold.ttf',
    ]);
    await load('Sora', [
      'assets/fonts/Sora-Bold.ttf',
      'assets/fonts/Sora-ExtraBold.ttf',
    ]);
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    final icons = flutterRoot == null
        ? null
        : File(
            '$flutterRoot/bin/cache/artifacts/material_fonts/'
            'MaterialIcons-Regular.otf',
          );
    if (icons != null && icons.existsSync()) {
      final bytes = await icons.readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
    }
  });

  testWidgets('the experimental score never calls itself confidence', (
    tester,
  ) async {
    await _pump(tester, _draft(), service: _StubService(_prediction()));
    await tester.pumpAndSettle();

    // A research index is never presented as patient-level certainty.
    expect(find.text('Experimental model score'), findsOneWidget);
    expect(find.byType(CockpitGauge), findsNothing);
    expect(find.text('Full data confidence'), findsNothing);
    expect(_inHero(RegExp('confidence', caseSensitive: false)), findsNothing);
    expect(_inHero(RegExp(r'95\s*%')), findsNothing);
    expect(_inHero(RegExp('error bar', caseSensitive: false)), findsNothing);
  });

  testWidgets('a blocked model draws no ring', (tester) async {
    await _pump(
      tester,
      _draft(),
      service: _StubService(_prediction(blocked: true)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CockpitGauge), findsNothing);
    expect(find.text('Experimental model score'), findsNothing);
  });

  testWidgets('danger signs are visible on the first phone screen', (
    tester,
  ) async {
    await _pump(
      tester,
      _draft(
        signs: const ['convulsions'],
        dangerSigns: const ['Convulsions'],
        classification: 'POSSIBLE SERIOUS BACTERIAL INFECTION',
      ),
      size: const Size(390, 844),
    );
    await tester.pumpAndSettle();

    expect(find.text('DANGER SIGNS PRESENT').hitTestable(), findsOneWidget);
    await _capture(tester, 'urgent');
    expect(tester.takeException(), isNull);
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

  testWidgets('decisive evidence is visible and full detail opens on demand', (
    tester,
  ) async {
    await _pump(
      tester,
      _draft(findings: const [_fastBreathing]),
      service: _StubService(_prediction()),
    );
    await tester.pumpAndSettle();

    // Measurements and their cutoff remain visible without opening the dossier.
    expect(find.textContaining('62/min'), findsOneWidget);
    expect(find.textContaining('≥ 50/min'), findsOneWidget);
    expect(find.byType(VitalsStrip), findsNothing);
    expect(_section('What we found'), findsNothing);
    expect(find.text('Handoff brief'), findsNothing);
    expect(find.text('Full clinical detail'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(ActionWorklist)).dy,
      lessThan(tester.getTopLeft(find.byType(AiInsightCard)).dy),
    );
    expect(
      tester.getTopLeft(find.byType(ClinicalDecisionHeader)).dy,
      lessThan(tester.getTopLeft(find.byType(ActionWorklist)).dy),
    );

    await tester.tap(find.text('Full clinical detail'));
    await tester.pumpAndSettle();
    expect(find.byType(VitalsStrip), findsOneWidget);
    expect(_section('What we found'), findsOneWidget);

    await tester.tap(find.text('Full clinical detail'));
    await tester.pumpAndSettle();
    expect(find.byType(VitalsStrip), findsNothing);
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

  testWidgets(
    'routine actions are reachable without opening evidence on a phone',
    (tester) async {
      await _pump(
        tester,
        _draft(
          actions: const [
            RecommendedAction(
              instruction: 'Review feeding with the caregiver',
              urgency: ReferralUrgency.scheduled,
            ),
          ],
        ),
        size: const Size(390, 844),
        service: _StubService(_prediction(blocked: true)),
      );
      expect(find.byType(ClinicalDecisionHeader).hitTestable(), findsOneWidget);
      expect(find.text('PRIORITIZED ACTIONS').hitTestable(), findsOneWidget);
      await _capture(tester, 'routine');
      await tester.scrollUntilVisible(
        find.text('Review feeding with the caregiver'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(
        find.text('Review feeding with the caregiver'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Review feeding with the caregiver').hitTestable(),
        findsOneWidget,
      );
      expect(find.byType(VitalsStrip), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('night mode keeps coverage and clinical decisions readable', (
    tester,
  ) async {
    await _pump(
      tester,
      _draft(),
      size: const Size(390, 844),
      service: _StubService(_prediction(blocked: true)),
    );
    await tester.tap(find.byTooltip('Night mode'));
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);
    expect(find.text(_classification).hitTestable(), findsOneWidget);
    await _capture(tester, 'night');
    expect(tester.takeException(), isNull);
  });

  testWidgets('experimental evidence remains reachable below care on a phone', (
    tester,
  ) async {
    await _pump(
      tester,
      _draft(),
      size: const Size(390, 844),
      service: _StubService(_prediction()),
    );
    await tester.scrollUntilVisible(
      find.byType(AiInsightCard),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byType(AiInsightCard));
    await tester.pumpAndSettle();
    expect(find.text('Experimental model score').hitTestable(), findsOneWidget);
    await _capture(tester, 'evidence');
    expect(tester.takeException(), isNull);
  });

  testWidgets('each action shows the finding it answers, once', (tester) async {
    await _pump(
      tester,
      _draft(
        findings: const [_fastBreathing],
        actions: const [
          RecommendedAction(
            instruction: 'Treat fast breathing now',
            urgency: ReferralUrgency.immediate,
          ),
          RecommendedAction(
            instruction: 'Book the next weighing',
            urgency: ReferralUrgency.scheduled,
          ),
        ],
      ),
      service: _StubService(_prediction(blocked: true)),
    );
    await tester.pumpAndSettle();

    // The traceable action names its finding; the untraceable one stays silent
    // rather than borrowing a plausible reason.
    expect(find.textContaining('Because: Fast breathing'), findsWidgets);
    expect(find.textContaining('Because: Book'), findsNothing);
    // The measurement is stated once — in the brief — not twice.
    expect(find.textContaining('62/min'), findsOneWidget);
  });

  testWidgets('one doorway to the report, not three', (tester) async {
    await _pump(
      tester,
      _draft(findings: const [_fastBreathing]),
      service: _StubService(_prediction()),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining(RegExp('full clinical report', caseSensitive: false)),
      findsOneWidget,
    );
  });
}
