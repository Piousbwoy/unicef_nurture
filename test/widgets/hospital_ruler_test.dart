/// The draggable hospital scale on the vitals station.
///
/// The ruler is now the primary instrument, so these tests are about what a
/// finger does to it: a tap or a drag must land on the spec's own step (0.1
/// where the vital allows decimals, whole numbers where it does not), the
/// zone note must follow the knob across a boundary with a single buzz, and
/// the − /+ jog must nudge the same reading the ruler edits — including the
/// diastolic half of a blood-pressure pair. Keypad entry stays as the
/// collapsible fallback. All of it at 320px and 200% text.
library;


import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/assessment/station/breath_counter.dart';
import 'package:carebridge_ai/presentation/assessment/station/clinical_keypad.dart';
import 'package:carebridge_ai/presentation/assessment/station/hospital_ruler.dart';
import 'package:carebridge_ai/presentation/assessment/station/station_specs.dart';
import 'package:carebridge_ai/presentation/assessment/station/vital_capture_card.dart';
import 'package:carebridge_ai/presentation/assessment/station/vital_spec.dart';
import 'package:carebridge_ai/presentation/assessment/widgets/muac_gauge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

final _childSpecs = childStationVitals(isYoungInfant: false, ageMonths: 13);
final _infantSpecs = childStationVitals(isYoungInfant: true, ageMonths: 0);

VitalSpec _spec(String key) => _childSpecs.firstWhere((s) => s.key == key);

VitalSpec _infantSpec(String key) => _infantSpecs.firstWhere((s) => s.key == key);

final _temp = _spec('temperature_celsius');
final _hb = _spec('haemoglobin');
final _muac = _spec('muac_mm');
// Pulse is only on the young-infant chart, and it is the one vital with no
// band table at all.
final _pulse = _infantSpec('pulse');
final _rr = _spec('respiratory_rate');
final _bp = maternalStationVitals(isPregnant: false).first;

const _ctx = VitalContext(
  clientType: ClientType.childUnderFive,
  ageMonths: 13,
  ageDays: 400,
);

const _maternalCtx = VitalContext(
  clientType: ClientType.pregnantWoman,
  gestationWeeks: 30,
);

// ─── Ruler harness ────────────────────────────────────────────────────────

class _Host extends StatefulWidget {
  const _Host({super.key, required this.spec, this.initial, this.ctx = _ctx});

  final VitalSpec spec;
  final double? initial;
  final VitalContext ctx;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final emitted = <double>[];
  late double? value = widget.initial;

  @override
  Widget build(BuildContext context) => HospitalRuler(
    spec: widget.spec,
    ctx: widget.ctx,
    value: value,
    onChanged: (v) => setState(() {
      emitted.add(v);
      value = v;
    }),
  );
}

Future<_HostState> _pumpRuler(
  WidgetTester tester, {
  required VitalSpec spec,
  double? initial,
  VitalContext ctx = _ctx,
  Size size = const Size(390, 600),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final key = GlobalKey<_HostState>();
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Center(child: _Host(key: key, spec: spec, initial: initial, ctx: ctx)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return key.currentState!;
}

/// A point on the scale's bar — the ruler's box also carries the note line,
/// so the bar is a fixed distance below its top edge.
Offset _onBar(WidgetTester tester, double dx) =>
    tester.getTopLeft(find.byType(HospitalRuler)) + const Offset(0, 30) + Offset(dx, 0);

Future<void> _tapBar(WidgetTester tester, double fraction) async {
  final w = tester.getSize(find.byType(HospitalRuler)).width;
  await tester.tapAt(_onBar(tester, w * fraction));
  await tester.pumpAndSettle();
}

/// Drags the knob along the bar in small steps, so the recogniser behaves the
/// way a real slow thumb does instead of teleporting.
Future<void> _dragBar(WidgetTester tester, double from, double to) async {
  final w = tester.getSize(find.byType(HospitalRuler)).width;
  final g = await tester.startGesture(_onBar(tester, w * from));
  await tester.pump();
  for (var i = 1; i <= 6; i++) {
    await g.moveTo(_onBar(tester, w * (from + (to - from) * i / 6)));
    await tester.pump();
  }
  await g.up();
  await tester.pumpAndSettle();
}

/// A value the spec can actually hold — never a ragged float.
void expectOnStep(double v, int decimals) {
  final grid = (v * (decimals == 0 ? 1 : 10)).round() / (decimals == 0 ? 1 : 10);
  expect(v, closeTo(grid, 1e-6));
}

// ─── Card harness ─────────────────────────────────────────────────────────

class _CardHost extends StatefulWidget {
  const _CardHost({super.key, required this.spec, this.ctx = _ctx});

  final VitalSpec spec;
  final VitalContext ctx;

  @override
  State<_CardHost> createState() => _CardHostState();
}

class _CardHostState extends State<_CardHost> {
  VitalEntry entry = const VitalEntry();

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [latestAssessmentProvider.overrideWith((ref, id) async => null)],
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(_scale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: ListView(
          children: [
            VitalCaptureCard(
              spec: widget.spec,
              ctx: widget.ctx,
              personId: 'p1',
              entry: entry,
              onChanged: (e) => setState(() => entry = e),
              onNext: () {},
            ),
          ],
        ),
      ),
    ),
  );
}

double _scale = 1;

Future<_CardHostState> _pumpCard(
  WidgetTester tester, {
  required VitalSpec spec,
  VitalContext ctx = _ctx,
  Size size = const Size(390, 1400),
  double textScale = 1,
}) async {
  _scale = textScale;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final key = GlobalKey<_CardHostState>();
  await tester.pumpWidget(
    _CardHost(key: key, spec: spec, ctx: ctx),
  );
  await tester.pumpAndSettle();
  return key.currentState!;
}

/// The − / + jog buttons, found the way a screen reader finds them.
Finder _jog(String verb) => find.bySemanticsLabel(RegExp('$verb ', caseSensitive: false));

Future<void> _tapJog(WidgetTester tester, String verb) async {
  final button = _jog(verb).first;
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('the scale itself', () {
    testWidgets('a tap lands on the step the vital allows', (tester) async {
      final h = await _pumpRuler(tester, spec: _temp);
      await _tapBar(tester, 0.5);
      // 34–41 °C, midpoint 37.5 — a one-decimal vital, so nothing ragged.
      expect(h.emitted, hasLength(1));
      expectOnStep(h.emitted.first, 1);
      expect(h.value, closeTo(37.5, 1e-9));
      expect(find.text('Fever (≥37.5 °C).'), findsOneWidget);
    });

    testWidgets('integer vitals never land between whole numbers', (tester) async {
      final h = await _pumpRuler(tester, spec: _muac);
      await _tapBar(tester, 0.5);
      expect(h.value, 130);
      expectOnStep(h.emitted.last, 0);
      expect(find.text('Green zone ≥125 mm.'), findsOneWidget);
      await _tapBar(tester, 0.25);
      expect(h.value, closeTo(110, 1e-9));
      expectOnStep(h.emitted.last, 0);
      expect(find.text('Red zone <115 mm — severe acute malnutrition.'), findsOneWidget);
    });

    testWidgets('dragging glides the knob and stays on the grid', (tester) async {
      final h = await _pumpRuler(tester, spec: _temp);
      await _dragBar(tester, 0.2, 0.7);
      expect(h.emitted, isNotEmpty);
      for (final v in h.emitted) {
        expectOnStep(v, 1);
        expect(v, inInclusiveRange(34, 41));
      }
      expect(h.value, closeTo(38.9, 1e-6));
    });

    testWidgets('crossing into a new zone buzzes once', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') calls.add(call);
          return null;
        },
      );
      // Haemoglobin starts comfortably normal; a drag down crosses 11 g/dL
      // into anaemia — one crossing, one click.
      final h = await _pumpRuler(tester, spec: _hb, initial: 12.5);
      expect(find.text('Not anaemic (≥11 g/dL).'), findsOneWidget);
      await _dragBar(tester, 0.75, 0.5);
      expect(calls, hasLength(1));
      expect(h.value, closeTo(10.0, 1e-6));
      expect(find.text('Anaemia (<11 g/dL).'), findsOneWidget);
    });

    testWidgets('an out-of-range reading warns before it bands', (tester) async {
      // 48 °C is inside no thermometer's story — the plausibility engine,
      // not the band table, has to answer it.
      await _pumpRuler(tester, spec: _temp, initial: 48.0);
      expect(
        find.textContaining('Outside the plausible range (30–45 °C)'),
        findsOneWidget,
      );
    });

    testWidgets('the empty scale invites a drag', (tester) async {
      await _pumpRuler(tester, spec: _temp);
      expect(
        find.text('Drag the knob or tap the scale to set the reading.'),
        findsOneWidget,
      );
    });

    testWidgets('a vital with no bands says so honestly', (tester) async {
      await _pumpRuler(tester, spec: _pulse);
      expect(
        find.text(
          'Drag the knob or tap the scale. Checked for plausibility only.',
        ),
        findsOneWidget,
      );
      await _tapBar(tester, 0.5);
      expect(find.text('Recorded. No range band for this measurement.'), findsOneWidget);
    });

    testWidgets('assistive tech can move it', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await _pumpRuler(tester, spec: _temp, initial: 38.1);
      final node = tester.getSemantics(find.bySemanticsLabel('Temperature scale'));
      expect(node.flagsCollection.isSlider, isTrue);
      expect(node.value, '38.1');
      expect(node.increasedValue, '38.2');
      expect(node.decreasedValue, '38.0');
      expect(h.emitted, isEmpty);
      handle.dispose();
    });

    testWidgets('no blur and no overflow at 320px and 200% text', (tester) async {
      await _pumpRuler(
        tester,
        spec: _muac,
        size: const Size(320, 700),
        textScale: 2,
      );
      expect(find.byType(BackdropFilter), findsNothing);
      await _tapBar(tester, 0.4);
      expect(tester.takeException(), isNull);
    });
  });

  group('the scale on the card', () {
    testWidgets('the ruler is the instrument; the keypad is the fallback', (
      tester,
    ) async {
      final h = await _pumpCard(tester, spec: _temp);
      expect(find.byType(HospitalRuler), findsOneWidget);
      expect(find.byType(ClinicalKeypad), findsNothing);
      await _tapBar(tester, 0.6);
      expect(h.entry.value, closeTo(38.2, 1e-9));
      expect(find.text('38.2'), findsOneWidget);
      expect(find.text('Fever (≥37.5 °C).'), findsOneWidget);

      await tester.tap(find.text('Type the reading instead'));
      await tester.pumpAndSettle();
      expect(find.byType(ClinicalKeypad), findsOneWidget);
    });

    testWidgets('the jog steps the reading, and stops at the end of the scale', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final h = await _pumpCard(tester, spec: _temp);
      await _tapJog(tester, 'Increase');
      expect(h.entry.text, '34.0');
      await _tapJog(tester, 'Increase');
      expect(h.entry.text, '34.1');
      await _tapJog(tester, 'Decrease');
      expect(h.entry.text, '34.0');
      await _tapJog(tester, 'Decrease');
      expect(h.entry.text, '34.0');
      handle.dispose();
    });

    testWidgets('holding the jog keeps counting', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await _pumpCard(tester, spec: _temp);
      final button = _jog('Increase').first;
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      final g = await tester.startGesture(tester.getCenter(button));
      await tester.pump(const Duration(milliseconds: 520));
      // Half a second of holding hands over to the repeater.
      expect(h.entry.text, '34.0');
      // Each repeat needs its own frame — one long pump only buys one step.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(double.parse(h.entry.text), greaterThan(34.2));
      handle.dispose();
    });

    testWidgets('the breath counter keeps its pad and gains the scale', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await _pumpCard(tester, spec: _rr);
      expect(find.byType(BreathCounter), findsOneWidget);
      expect(find.byType(HospitalRuler), findsOneWidget);
      expect(find.text('Type the rate instead'), findsOneWidget);
      await _tapJog(tester, 'Increase');
      expect(h.entry.text, '10');
      await _tapJog(tester, 'Increase');
      expect(h.entry.text, '11');
      handle.dispose();
    });

    testWidgets('the MUAC tape and the scale read the same arm', (tester) async {
      final h = await _pumpCard(tester, spec: _muac);
      expect(find.byType(MuacGauge), findsOneWidget);
      expect(find.byType(HospitalRuler), findsOneWidget);
      await _dragBar(tester, 0.1, 0.375);
      expect(h.entry.text, '120');
      expect(find.text('120'), findsOneWidget);
      expect(find.text('Yellow zone 115–124 mm — moderate acute malnutrition.'), findsOneWidget);
    });

    testWidgets('the ruler follows the reading the nurse selected', (tester) async {
      final h = await _pumpCard(tester, spec: _bp, ctx: _maternalCtx);
      await _tapBar(tester, 0.5);
      expect(h.entry.text, '130');
      expect(h.entry.pairText, isEmpty);

      // Tap the diastolic half: the same scale now edits it.
      await tester.tap(find.text('DIASTOLIC'));
      await tester.pumpAndSettle();
      await _tapBar(tester, 0.5);
      expect(h.entry.text, '130');
      expect(h.entry.pairText, '85');
      expect(find.text('Normal (<90).'), findsOneWidget);
    });

    testWidgets('three paired digits fit: the pair shrinks, the single does not', (
      tester,
    ) async {
      double numeralSize(String t) =>
          tester.widget<Text>(find.text(t)).style!.fontSize!;

      await _pumpCard(tester, spec: _bp, ctx: _maternalCtx);
      await _tapBar(tester, 0.5);
      expect(numeralSize('130'), 40);

      await _pumpCard(tester, spec: _temp);
      await _tapBar(tester, 0.5);
      expect(numeralSize('37.5'), 56);
    });

    testWidgets('not measured hides the scale, the jog and the keypad', (tester) async {
      final h = await _pumpCard(tester, spec: _temp);
      await tester.tap(find.text('Not measured'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No equipment'));
      await tester.pumpAndSettle();
      expect(h.entry.notMeasured, 'No equipment');
      expect(find.byType(HospitalRuler), findsNothing);
      expect(find.byIcon(Icons.add_rounded), findsNothing);
      expect(find.text('Type the reading instead'), findsNothing);
    });

    testWidgets('a whole card at 320px and 200% text, mid-drag', (tester) async {
      final h = await _pumpCard(
        tester,
        spec: _temp,
        size: const Size(320, 900),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      final bar = find.byType(HospitalRuler);
      await tester.ensureVisible(bar);
      await tester.pumpAndSettle();
      await _tapBar(tester, 0.5);
      expect(tester.takeException(), isNull);
      final tile = find.text('Type the reading instead');
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile.hitTestable());
      await tester.pumpAndSettle();
      expect(find.byType(ClinicalKeypad), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(h.entry.value, isNotNull);
    });
  });
}
