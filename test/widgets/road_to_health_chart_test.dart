/// Behavioural tests for the Road-to-Health card.
///
/// The chart is the one screen in this app whose whole job is to be *read as a
/// picture*, so pixels are not what these tests pin. What they pin is the two
/// ways a growth card can mislead a CHPS worker: drawing an axis when there is
/// nothing to plot (which reads as "this child is fine"), and hiding which
/// standard the line was drawn against. The rest is a narrow-screen overflow
/// sweep, because a card that overflows on a low-end Android phone is a card
/// that gets skipped.
library;

import 'package:carebridge_ai/core/theme/app_theme.dart';
import 'package:carebridge_ai/domain/engines/road_to_health.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/assessment/widgets/road_to_health_chart.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

final _dob = DateTime(2025, 1, 1);

DateTime _at(double months) =>
    _dob.add(Duration(days: (months * 30.4375).round()));

GrowthMeasurement _weighing(String id, double months, double kg) =>
    GrowthMeasurement(
      id: id,
      personId: 'p-1',
      takenAt: _at(months),
      weightKg: kg,
    );

RoadToHealthReading _reading({
  Sex sex = Sex.male,
  bool withDob = true,
  List<GrowthMeasurement>? measurements,
}) => RoadToHealth.read(
  sex: sex,
  dateOfBirth: withDob ? _dob : null,
  measurements:
      measurements ?? [_weighing('g1', 14, 10.0), _weighing('g2', 20, 8.0)],
);

Future<void> _pump(
  WidgetTester tester,
  RoadToHealthReading reading, {
  double width = 390,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: RoadToHealthCard(reading: reading),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('RoadToHealthCard', () {
    testWidgets('plots the weighings it can place', (tester) async {
      await _pump(tester, _reading());

      expect(find.text('Road to Health'), findsOneWidget);
      expect(
        find.byType(LineChart),
        findsOneWidget,
        reason: 'two placed weighings must draw a track',
      );
    });

    testWidgets('declines with the reason instead of an empty axis', (
      tester,
    ) async {
      // An axis with no line on it reads as "nothing wrong here". The gap
      // sentence is the whole point of the refusal state.
      await _pump(tester, _reading(withDob: false));

      expect(find.byType(LineChart), findsNothing);
      expect(find.text('Why the chart is not drawn'), findsOneWidget);
      expect(find.textContaining('Date of birth not recorded'), findsOneWidget);
      expect(find.textContaining('MUAC tape'), findsNothing);
    });

    testWidgets('names the band, the sex and the standard', (tester) async {
      await _pump(tester, _reading());

      expect(find.textContaining('Below −3 SD'), findsOneWidget);
      expect(
        find.textContaining('The line has crossed down'),
        findsOneWidget,
        reason: 'a fall across a band line is the finding the card exists for',
      );
      expect(find.textContaining('boy'), findsOneWidget);
      expect(
        find.textContaining('WHO weight-for-age standard'),
        findsOneWidget,
      );
    });

    testWidgets('shows the girls standard to a girl', (tester) async {
      await _pump(
        tester,
        _reading(sex: Sex.female, measurements: [_weighing('g1', 12, 6.8)]),
      );

      expect(find.textContaining('girl'), findsOneWidget);
      expect(
        find.textContaining('Underweight for age'),
        findsOneWidget,
        reason:
            '6.8 kg at twelve months is a fall for a boy and a watch '
            'for a girl; the card must read the girl one',
      );
    });

    testWidgets('lists every weighing and names the ones it left out', (
      tester,
    ) async {
      await _pump(
        tester,
        _reading(
          sex: Sex.female,
          measurements: [
            _weighing('g1', 10, 8.4),
            GrowthMeasurement(
              id: 'g2',
              personId: 'p-1',
              takenAt: _at(13),
              muacMm: 132,
            ),
            _weighing('g3', 16, 8.6),
          ],
        ),
      );

      expect(find.textContaining('10.0 months · 8.4 kg'), findsOneWidget);
      expect(find.textContaining('16.0 months · 8.6 kg'), findsOneWidget);
      expect(
        find.textContaining('Not plotted: 1 visit with no weight'),
        findsOneWidget,
        reason:
            'a dropped visit would read on the line as a child who '
            'stopped growing',
      );
    });

    testWidgets('states the limit of weight-for-age beside the picture', (
      tester,
    ) async {
      await _pump(tester, _reading());

      expect(
        find.textContaining('cannot tell a thin child from a short one'),
        findsOneWidget,
      );
      expect(
        find.textContaining('WHO Child Growth Standards (2006)'),
        findsOneWidget,
      );
      expect(
        find.textContaining('On the standard: −2 to +2 SD'),
        findsOneWidget,
      );
    });

    testWidgets('gives a screen reader the numbers behind the picture', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _reading());

      expect(
        find.bySemanticsLabel(
          RegExp(
            r'8\.0 kilograms at 20\.0 months, -\d\.\d standard deviations',
          ),
        ),
        findsOneWidget,
        reason:
            'the picture has to say its numbers aloud for a worker who '
            'cannot see the plot',
      );
      handle.dispose();
    });

    testWidgets('draws the paper around the child, not around the standard', (
      tester,
    ) async {
      // A twenty-month-old's whole life is under two years. Plotting all sixty
      // months anyway shoves their track into the left third of the card and
      // leaves the rest empty grid, which is the one thing a printed Road to
      // Health card never does.
      LineChartData dataFor(WidgetTester t) =>
          t.widget<LineChart>(find.byType(LineChart)).data;

      await _pump(tester, _reading());
      expect(dataFor(tester).maxX, 30);

      await _pump(
        tester,
        _reading(
          measurements: [_weighing('g1', 30, 13.0), _weighing('g2', 46, 14.4)],
        ),
      );
      expect(dataFor(tester).maxX, 54);

      // And never past the end of what the WHO publishes.
      await _pump(
        tester,
        _reading(
          measurements: [_weighing('g1', 50, 16.0), _weighing('g2', 59, 17.4)],
        ),
      );
      expect(dataFor(tester).maxX, 60);
    });

    testWidgets('holds together on a narrow phone at 200% text', (
      tester,
    ) async {
      await _pump(tester, _reading(), width: 320, textScale: 2.0);

      expect(tester.takeException(), isNull);
      expect(find.byType(RoadToHealthChart), findsOneWidget);
    });

    testWidgets('the refusal note survives a narrow phone at 200% text', (
      tester,
    ) async {
      await _pump(
        tester,
        _reading(
          measurements: [
            GrowthMeasurement(
              id: 'g1',
              personId: 'p-1',
              takenAt: _at(74),
              weightKg: 21.0,
            ),
          ],
        ),
        width: 320,
        textScale: 2.0,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(LineChart), findsNothing);
      expect(
        find.textContaining('Past the end of the standard'),
        findsOneWidget,
      );
    });
  });
}
