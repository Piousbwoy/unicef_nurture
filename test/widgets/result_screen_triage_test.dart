/// Widget tests for the two-tier triage (rule-in / screening) on the
/// neonatal sepsis model, rendered end-to-end through the result screen.
///
/// The three cases the clinical reviewer cares about:
///   * HIGH tier  — the AI alone labels the newborn a "rule-in candidate"
///     (probability >= 0.15 on the 2%-prior scale): the urgent PSBI
///     finding appears and the pre-referral protocol activates with an
///     "AI rule-in candidate" reason.
///   * LOW tier   — below the rule-in threshold with no IMCI danger sign:
///     no AI finding, no protocol activation; the model card reads
///     "screening tier".
///   * DRIFT      — out-of-training-window input (14-day-old vs the 0-3d
///     real-data window): riskProbability is null, no AI finding, and the
///     deterministic GHS rules keep the rule-out coverage by activating
///     the protocol on the danger sign alone.
library;

import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/assessment/result_screen.dart';
import 'package:carebridge_ai/presentation/assessment/types.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

AppUser _user() => AppUser(
  id: 'u-fhw-1',
  fullName: 'Amina Fuseini',
  phone: '0244000000',
  role: UserRole.frontlineHealthWorker,
  region: 'Northern Region',
  district: 'Gushegu',
  community: 'Gushegu',
);

const _household = Household(
  id: 'h-1',
  name: "Mariama's household",
  region: 'Northern Region',
  district: 'Gushegu',
  community: 'Gushegu',
  createdBy: 'u-fhw-1',
);

AssessmentResult _routineResult() => const AssessmentResult(
  clientType: ClientType.newborn,
  triage: TriageLevel.routine,
  classification: 'WELL NEWBORN — NO IMCI CLASSIFICATION',
  findings: [],
  actions: [],
  confidence: RecommendationConfidence.high,
);

/// A newborn whose ONLY risk signals are the ones the test scenario needs.
/// Everything else is a normal 2-day-old (or the requested age). The vitals
/// are required: the service zero-imputes missing features, and a mostly-
/// empty tensor drifts against the v2.0 training baseline — which would
/// null riskProbability even in-window (the real form always captures
/// vitals, so the test bags mirror that).
AssessmentDraft _draft({
  required int ageDays,
  List<String> dangerSigns = const [],
  double? temperatureCelsius,
  int? respiratoryRate,
  int? pulse,
  int? oxygenSaturation,
  double? birthWeightKg,
}) => AssessmentDraft(
  inputs: {
    'age_in_days': ageDays,
    'danger_signs': dangerSigns,
    'temperature_celsius': ?temperatureCelsius,
    'respiratory_rate': ?respiratoryRate,
    'pulse': ?pulse,
    'oxygen_saturation': ?oxygenSaturation,
    'birth_weight_kg': ?birthWeightKg,
  },
  result: _routineResult(),
);

/// Vitals of a well 2-day-old: all inside the WHO IMCI normal bands, so
/// none of them trips a deterministic PSBI trigger (fever >= 37.5,
/// hypothermia < 35.5, SpO2 < 90, RR >= 60) — any activation below is the
/// AI rule-in tier acting alone. Passed to [_draft] in every scenario.
({double temp, int rr, int pulse, int spo2, double bw}) _normalVitals() =>
    (temp: 37.0, rr: 48, pulse: 140, spo2: 97, bw: 3.1);

AssessmentContext _context(int ageDays) => AssessmentContext(
  user: _user(),
  household: _household,
  person: Person(
    id: 'p-newborn-1',
    householdId: _household.id,
    fullName: 'Baby Fuseini',
    clientType: ClientType.newborn,
    dateOfBirth: DateTime.now().subtract(Duration(days: ageDays)),
  ),
);

Future<void> _pump(
  WidgetTester tester,
  AssessmentContext input,
  AssessmentDraft draft,
) async {
  // The verdict screen is a lazy ListView; make the viewport tall enough
  // that the pre-referral section (top) and the AI predictions card
  // (below the fold) are both inflated.
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // The ML predictions resolve through real asset-bundle I/O (model SHA
  // probes + metrics JSON + drift baselines), so the widget needs real
  // event-loop time before the FutureBuilder can settle. The first test
  // to run pays the cold-start cost of the asset checks; wait until the
  // predictions spinner is gone (or give up after 10 s) instead of
  // guessing a fixed delay.
  await tester.runAsync(() async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: AssessmentResultScreen(
            input: input,
            draft: draft,
            visitId: 'v-1',
          ),
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await tester.pump();
      if (!tester.any(find.byType(CircularProgressIndicator))) break;
    }
  });
  await tester.pumpAndSettle();
}

/// Opens the second page — the full clinical report — where the AI
/// evidence cards live. The result experience is two pages by design:
/// the verdict moment first, the documentation behind it. The AI
/// predictions resolve through real asset-bundle I/O, so the wait loop
/// runs on the real event loop until the analysis spinner is gone.
Future<void> _openReport(WidgetTester tester) async {
  await tester.tap(find.text('Open full clinical report'));
  await tester.runAsync(() async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await tester.pump();
      if (!tester.any(find.byType(CircularProgressIndicator))) break;
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('result screen — two-tier triage: HIGH tier (rule-in candidate)', () {
    testWidgets(
      'nasal flaring + grunting + bleeding (no IMCI danger sign) push the '
      'fallback past 0.15: AI alone activates PSBI',
      (tester) async {
        // None of these three are IMCI "pink row" danger signs in the
        // stabilization selector, so any PSBI activation below is the AI
        // rule-in tier acting alone — the deterministic rules add nothing.
        final v = _normalVitals();
        await _pump(
          tester,
          _context(2),
          _draft(
            ageDays: 2,
            dangerSigns: ['nasalFlaring', 'grunting', 'bleeding'],
            temperatureCelsius: v.temp,
            respiratoryRate: v.rr,
            pulse: v.pulse,
            oxygenSaturation: v.spo2,
            birthWeightKg: v.bw,
          ),
        );

        // The pre-referral section renders with an AI-only reason.
        expect(find.text('Pre-referral stabilisation'), findsOneWidget);
        expect(find.textContaining('AI rule-in candidate'), findsOneWidget);
        expect(find.textContaining('IMCI danger sign'), findsNothing);

        // The AI evidence lives on the full clinical report page.
        await _openReport(tester);

        // The AI finding names the tier and its cut-off. (The label also
        // appears in the verdict banner rationale and the synthesised
        // summary, so it can legitimately match several Text widgets.)
        expect(
          find.textContaining('Rule-in candidate: possible severe bacterial'),
          findsWidgets,
        );
        expect(find.textContaining('Rule-in ≥ 15%'), findsOneWidget);

        // The model card shows the rule-in badge + tier label.
        expect(find.text('rule-in'), findsOneWidget);
        expect(find.textContaining('rule-in candidate'), findsWidgets);
      },
    );
  });

  group('result screen — two-tier triage: LOW tier (screening)', () {
    testWidgets(
      'healthy newborn at the 0.02 baseline: no AI finding, no protocol, '
      'card reads screening tier',
      (tester) async {
        await _pump(
          tester,
          _context(2),
          _draft(
            ageDays: 2,
            temperatureCelsius: 36.8,
            respiratoryRate: 42,
            pulse: 130,
            oxygenSaturation: 98,
            birthWeightKg: 3.0,
          ),
        );

        // No rule-in, no danger sign -> nothing activates.
        expect(find.text('Pre-referral stabilisation'), findsNothing);

        // The model card lives on the full clinical report page, and it
        // still surfaces the honest screening number.
        await _openReport(tester);
        expect(
          find.textContaining('Rule-in candidate: possible severe bacterial'),
          findsNothing,
        );
        expect(find.text('rule-in'), findsNothing);
        expect(find.textContaining('screening tier'), findsOneWidget);
        expect(find.textContaining('Risk 2.0%'), findsOneWidget);
      },
    );
  });

  group('result screen — two-tier triage: DRIFT-suppressed AI', () {
    testWidgets(
      '14-day-old is outside the 0-3d training window: no AI number, no AI '
      'finding, deterministic rules carry PSBI',
      (tester) async {
        final v = _normalVitals();
        await _pump(
          tester,
          _context(14),
          _draft(
            ageDays: 14,
            dangerSigns: ['convulsions'],
            temperatureCelsius: v.temp,
            respiratoryRate: v.rr,
            pulse: v.pulse,
            oxygenSaturation: v.spo2,
            birthWeightKg: v.bw,
          ),
        );

        // The deterministic GHS rules keep the rule-out coverage: the
        // protocol activates on the danger sign even with null AI risk.
        expect(find.text('Pre-referral stabilisation'), findsOneWidget);
        expect(find.textContaining('IMCI danger sign'), findsOneWidget);

        // The AI evidence lives on the full clinical report page.
        await _openReport(tester);

        // The AI is suppressed: no confident number, no rule-in finding.
        // (More than one model can sit out-of-window for a newborn, so
        // several cards can read n/a at once.)
        expect(find.textContaining('out of training window'), findsWidgets);
        expect(find.text('rule-in'), findsNothing);
        expect(
          find.textContaining('Rule-in candidate: possible severe bacterial'),
          findsNothing,
        );
      },
    );
  });
}
