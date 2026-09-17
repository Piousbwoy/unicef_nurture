/// Vitals Station behaviour.
///
/// The station is a pre-fill layer: the keypad must type what the nurse
/// meant (decimals only where the vital allows them), the band tone must
/// follow the IMCI age cut-offs, the previous-visit delta must read from the
/// last saved assessment, "Not measured" must record its reason, re-takes
/// must be counted, the breath counter must hand back both the rate and the
/// seconds counted, and every shortcut must go straight to the chart. All
/// of it at 320px and 200% text, with no BackdropFilter under reduced motion.
library;

import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/assessment/station/breath_counter.dart';
import 'package:carebridge_ai/presentation/assessment/station/clinical_keypad.dart';
import 'package:carebridge_ai/presentation/assessment/station/vital_spec.dart';
import 'package:carebridge_ai/presentation/assessment/station/vitals_station_screen.dart';
import 'package:carebridge_ai/presentation/assessment/types.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

final _user = AppUser(
  id: 'u1',
  fullName: 'Test nurse',
  phone: '0244000000',
  role: UserRole.frontlineHealthWorker,
  region: 'Northern',
  district: 'Gushegu',
  community: 'Gushegu',
);

const _household = Household(
  id: 'h1',
  name: 'Test household',
  region: 'Northern',
  district: 'Gushegu',
  community: 'Gushegu',
  createdBy: 'u1',
);

AssessmentContext _child({int ageDays = 400}) => AssessmentContext(
  user: _user,
  household: _household,
  person: Person(
    id: 'p1',
    householdId: 'h1',
    fullName: 'Abena Mensah',
    clientType: ClientType.childUnderFive,
    dateOfBirth: DateTime.now().subtract(Duration(days: ageDays)),
  ),
);

Assessment _previous(Map<String, Object?> inputs) => Assessment(
  id: 'a0',
  visitId: 'v0',
  personId: 'p1',
  clientType: ClientType.childUnderFive,
  performedBy: 'u1',
  performedAt: DateTime(2026, 3, 12, 9),
  inputs: inputs,
  result: const AssessmentResult(
    clientType: ClientType.childUnderFive,
    triage: TriageLevel.routine,
    classification: 'WELL CHILD',
    findings: [],
    actions: [],
    confidence: RecommendationConfidence.high,
  ),
);

class _Harness {
  StationResult? result;
  var skipped = false;
  var danger = false;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  AssessmentContext? input,
  Assessment? previous,
  Size size = const Size(390, 1200),
  double textScale = 1,
  bool disableAnimations = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final h = _Harness();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(_user),
        latestAssessmentProvider.overrideWith((ref, id) async => previous),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: child!,
        ),
        home: VitalsStationScreen(
          input: input ?? _child(),
          onContinue: (r) => h.result = r,
          onSkip: () => h.skipped = true,
          onDanger: () => h.danger = true,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return h;
}

/// Taps a key on the on-screen keypad (never the system keyboard).
Future<void> _key(WidgetTester tester, String label) async {
  final key = find.descendant(
    of: find.byType(ClinicalKeypad),
    matching: find.text(label),
  );
  await tester.ensureVisible(key.first);
  await tester.pumpAndSettle();
  await tester.tap(key.hitTestable().first);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await _key(tester, d);
  }
}

Future<void> _next(WidgetTester tester) async {
  // At 200% text the button can sit below the fold of the card's list.
  await tester.ensureVisible(find.text('Next').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Next').hitTestable());
  await tester.pumpAndSettle();
}

/// Advances to the Review page from wherever the pager is.
Future<void> _toReview(WidgetTester tester) async {
  while (find.text('Review').evaluate().isEmpty) {
    await _next(tester);
  }
  await tester.ensureVisible(find.text('Review').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Review').hitTestable());
  await tester.pumpAndSettle();
  expect(find.text('Review vitals'), findsOneWidget);
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('bands', () {
    VitalContext ctx(int months) => VitalContext(
      clientType: ClientType.childUnderFive,
      ageMonths: months,
      ageDays: months * 30,
    );

    test('respiratory rate tone follows the IMCI age cut-offs', () {
      // 55/min: fast for a 13-month-old (≥40), fast for a 6-month-old (≥50),
      // not yet fast for a 3-week-old (≥60).
      expect(
        respiratoryBands(ctx(13)).firstWhere((b) => b.contains(55)).tone,
        VitalTone.danger,
      );
      expect(
        respiratoryBands(ctx(6)).firstWhere((b) => b.contains(55)).tone,
        VitalTone.danger,
      );
      expect(
        respiratoryBands(ctx(0)).firstWhere((b) => b.contains(55)).tone,
        VitalTone.normal,
      );
      expect(
        respiratoryBands(ctx(0)).firstWhere((b) => b.contains(60)).tone,
        VitalTone.danger,
      );
      expect(
        respiratoryBands(ctx(13)).firstWhere((b) => b.contains(38)).tone,
        VitalTone.normal,
      );
      expect(
        respiratoryBands(ctx(13)).firstWhere((b) => b.contains(55)).note,
        'Fast breathing for 12–59 months (IMCI ≥40/min).',
      );
    });

    test('temperature, SpO2 and MUAC mirror the form cut-offs', () {
      final c = ctx(13);
      expect(
        temperatureBands(c).firstWhere((b) => b.contains(37.5)).tone,
        VitalTone.watch,
      );
      expect(
        temperatureBands(c).firstWhere((b) => b.contains(35.4)).tone,
        VitalTone.danger,
      );
      expect(
        spo2Bands(c).firstWhere((b) => b.contains(89)).tone,
        VitalTone.danger,
      );
      expect(
        spo2Bands(c).firstWhere((b) => b.contains(92)).tone,
        VitalTone.watch,
      );
      expect(
        muacMmBands(c).firstWhere((b) => b.contains(114)).tone,
        VitalTone.danger,
      );
      expect(
        muacMmBands(c).firstWhere((b) => b.contains(120)).tone,
        VitalTone.watch,
      );
      expect(
        muacMmBands(c).firstWhere((b) => b.contains(125)).tone,
        VitalTone.normal,
      );
    });
  });

  testWidgets('keypad types a decimal temperature and shows its band', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Vitals'), findsOneWidget);
    expect(find.text('Breathing rate'), findsOneWidget);
    // No system keyboard anywhere on the station.
    expect(find.byType(EditableText), findsNothing);

    await _next(tester);
    expect(find.text('Temperature'), findsOneWidget);
    await _type(tester, '38.1');
    expect(find.text('38.1'), findsOneWidget);
    expect(find.text('Fever (≥37.5 °C).'), findsOneWidget);

    // A second decimal point is ignored; backspace edits one character;
    // a lone leading zero is replaced, and holding backspace clears.
    await _key(tester, '.');
    expect(find.text('38.1'), findsOneWidget);
    final backspace = find.descendant(
      of: find.byType(ClinicalKeypad),
      matching: find.byIcon(Icons.backspace_outlined),
    );
    await tester.tap(backspace.hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('38.'), findsOneWidget);
    await tester.longPress(backspace.hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('38.'), findsNothing);
    await _type(tester, '03');
    expect(find.text('3'), findsNWidgets(2)); // readout + the '3' key
  });

  testWidgets('integer vitals have no decimal point', (tester) async {
    await _pump(tester);
    // Breathing rate → Temperature → Weight → Length → MUAC → SpO₂.
    for (var i = 0; i < 5; i++) {
      await _next(tester);
    }
    expect(find.text('Oxygen saturation'), findsOneWidget);
    await _type(tester, '9');
    await _key(tester, '.');
    await _type(tester, '2');
    expect(find.text('92'), findsOneWidget);
    expect(
      find.text('Borderline (90–93%). Warm the hand and re-check.'),
      findsOneWidget,
    );
  });

  testWidgets('previous-visit chip shows the last value and the delta', (
    tester,
  ) async {
    await _pump(tester, previous: _previous({'weight_kg': 8.0}));
    expect(find.text('Last visit 12 Mar'), findsOneWidget);
    await _next(tester);
    await _next(tester);
    expect(find.text('Weight'), findsOneWidget);
    expect(find.text('Last 8.0 kg · 12 Mar'), findsOneWidget);
    await _type(tester, '8.3');
    expect(find.text('Last 8.0 kg · 12 Mar ▲ +0.3'), findsOneWidget);
  });

  testWidgets('"Not measured" records the reason and moves on', (tester) async {
    final h = await _pump(tester);
    await _next(tester);
    expect(find.text('Temperature'), findsOneWidget);
    await tester.tap(find.text('Not measured').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Why was temperature not measured?'), findsOneWidget);
    for (final r in ['No equipment', 'Patient refused', 'Not indicated']) {
      expect(find.text(r), findsOneWidget);
    }
    await tester.tap(find.text('Patient refused'));
    await tester.pumpAndSettle();
    // Auto-advanced to Weight; the rail and review remember the reason.
    expect(find.text('Weight'), findsOneWidget);

    await _toReview(tester);
    expect(find.text('Patient refused'), findsOneWidget);
    await tester.tap(find.text('Continue to chart'));
    await tester.pumpAndSettle();
    expect(h.result!.notMeasured['temperature_celsius'], 'Patient refused');
    expect(h.result!.values.containsKey('temperature_celsius'), isFalse);
  });

  testWidgets('re-take clears the reading and counts', (tester) async {
    final h = await _pump(tester);
    await _next(tester);
    await _type(tester, '38.1');
    expect(find.textContaining('Captured '), findsOneWidget);
    await tester.tap(find.text('Re-take').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('38.1'), findsNothing);
    expect(find.text('Re-taken once'), findsOneWidget);
    await _type(tester, '37.9');
    await tester.tap(find.text('Re-take').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Re-taken 2×'), findsOneWidget);
    await _type(tester, '37.8');

    await _toReview(tester);
    await tester.tap(find.text('Continue to chart'));
    await tester.pumpAndSettle();
    expect(h.result!.retakes['temperature_celsius'], 2);
    expect(h.result!.values['temperature_celsius'], 37.8);
  });

  testWidgets('breath counter emits the rate and the seconds counted', (
    tester,
  ) async {
    int? rate;
    int? secs;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BreathCounter(
            onResult: (r, s) {
              rate = r;
              secs = s;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final pad = find.text('Tap once for every breath');
    for (var i = 0; i < 5; i++) {
      await tester.tap(pad);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('5'), findsOneWidget);
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();
    expect(rate, 5);
    expect(secs, 60);
    expect(find.text('Done — 5 breaths/min'), findsOneWidget);
  });

  testWidgets('"Count 30s ×2" doubles the count and records 30 seconds', (
    tester,
  ) async {
    int? rate;
    int? secs;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BreathCounter(
            onResult: (r, s) {
              rate = r;
              secs = s;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Count 30s ×2'));
    await tester.pumpAndSettle();
    final pad = find.text('Tap once for every breath');
    for (var i = 0; i < 12; i++) {
      await tester.tap(pad);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(rate, 24);
    expect(secs, 30);
  });

  testWidgets('station carries rr and rr_timer_secs into the result', (
    tester,
  ) async {
    final h = await _pump(tester);
    final pad = find.text('Tap once for every breath');
    for (var i = 0; i < 3; i++) {
      await tester.tap(pad);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Stop early'));
    await tester.pumpAndSettle();
    // Three breaths in ~0.3 s rounds to one second counted → 180/min. The
    // number is honest about how it was made: the seconds go with it.
    expect(find.text('180'), findsOneWidget);
    await _toReview(tester);
    await tester.tap(find.text('Continue to chart'));
    await tester.pumpAndSettle();
    expect(h.result!.values['respiratory_rate'], 180);
    expect(h.result!.values['rr_timer_secs'], 1);
    expect(h.result!.capturedAt, isNotNull);
  });

  testWidgets(
    '"Skip to chart" and "Danger sign now?" go straight to the form',
    (tester) async {
      final h = await _pump(tester);
      await tester.tap(find.text('Danger sign now?').hitTestable());
      await tester.pumpAndSettle();
      expect(h.danger, isTrue);
      await tester.tap(find.text('Skip to chart'));
      await tester.pumpAndSettle();
      expect(h.skipped, isTrue);
      expect(h.result, isNull);
    },
  );

  testWidgets('review page returns a StationResult with every value', (
    tester,
  ) async {
    final h = await _pump(tester);
    await _next(tester);
    await _type(tester, '38.1');
    await _next(tester);
    await _type(tester, '8.3');
    await _toReview(tester);
    expect(find.text('Vitals taken'), findsOneWidget);
    expect(find.text('38.1 °C'), findsOneWidget);
    expect(find.text('8.3 kg'), findsOneWidget);
    expect(find.textContaining('2 recorded · 0 not measured'), findsOneWidget);
    await tester.tap(find.text('Continue to chart'));
    await tester.pumpAndSettle();
    expect(h.result!.values['temperature_celsius'], 38.1);
    expect(h.result!.values['weight_kg'], 8.3);
    expect(h.result!.notMeasured, isEmpty);
    expect(h.result!.isEmpty, isFalse);
  });

  testWidgets('young infant station has no MUAC or height', (tester) async {
    final h = await _pump(
      tester,
      input: AssessmentContext(
        user: _user,
        household: _household,
        person: Person(
          id: 'p2',
          householdId: 'h1',
          fullName: 'Baby Mensah',
          clientType: ClientType.newborn,
          dateOfBirth: DateTime.now().subtract(const Duration(days: 5)),
        ),
      ),
    );
    await _toReview(tester);
    expect(find.text('MUAC'), findsNothing);
    expect(find.text('Length / height'), findsNothing);
    expect(find.text('Breathing rate'), findsOneWidget);
    expect(find.text('Haemoglobin'), findsOneWidget);
    await tester.tap(find.text('Continue to chart'));
    await tester.pumpAndSettle();
    expect(h.result!.values, isEmpty);
    expect(h.result!.isEmpty, isTrue);
  });

  testWidgets('no BackdropFilter under reduced motion', (tester) async {
    await _pump(tester);
    expect(find.byType(BackdropFilter), findsNothing);
    await _next(tester);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('station fits 320px at 200% text without overflow', (
    tester,
  ) async {
    await _pump(
      tester,
      size: const Size(320, 900),
      textScale: 2,
      previous: _previous({'temperature_celsius': 37.2, 'weight_kg': 8.0}),
    );
    expect(tester.takeException(), isNull);
    await _next(tester);
    await _type(tester, '38.1');
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _toReview(tester);
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
