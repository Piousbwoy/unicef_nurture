/// Behavioural smoke tests for the MUAC gauge widget.
///
/// The full visual rendering is exercised by the manual wireframe check; these
/// tests cover the bits that would silently break a CHO's screen in the field
/// — the wrong zone text, the wrong colour, or a needle that refuses to move
/// when the value is edited.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carebridge_ai/presentation/assessment/widgets/muac_gauge.dart';

Future<void> _pump(
  WidgetTester tester,
  TextEditingController controller, {
  String? value,
}) async {
  if (value != null) controller.text = value;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: MuacGauge(controller: controller),
          ),
        ),
      ),
    ),
  );
  // Let the needle tween settle.
  await tester.pumpAndSettle(const Duration(milliseconds: 500));
}

void main() {
  group('MuacGauge', () {
    testWidgets('shows the empty zone when no value has been typed',
        (tester) async {
      final controller = TextEditingController();
      await _pump(tester, controller);

      expect(find.text('Enter MUAC to see the zone'), findsOneWidget);
      expect(find.text('No MUAC recorded'), findsOneWidget);
    });

    testWidgets('switches to the SAM zone below 11.5 cm', (tester) async {
      final controller = TextEditingController();
      await _pump(tester, controller, value: '10.9');

      expect(find.text('MUAC 10.9 cm'), findsOneWidget);
      expect(
        find.text('RED ZONE — Severe Acute Malnutrition'),
        findsOneWidget,
      );
      expect(find.text('AT RISK ASSESSMENT'), findsOneWidget);
    });

    testWidgets('switches to the MAM zone between 11.5 and 12.5 cm',
        (tester) async {
      final controller = TextEditingController();
      await _pump(tester, controller, value: '12.0');

      expect(find.text('MUAC 12.0 cm'), findsOneWidget);
      expect(
        find.text('YELLOW ZONE — Moderate Acute Malnutrition'),
        findsOneWidget,
      );
    });

    testWidgets('switches to the watch zone between 12.5 and 13.5 cm',
        (tester) async {
      final controller = TextEditingController();
      await _pump(tester, controller, value: '13.0');

      expect(find.text('MUAC 13.0 cm'), findsOneWidget);
      expect(find.text('WATCH — Borderline nutrition'), findsOneWidget);
    });

    testWidgets('switches to the adequate zone at or above 13.5 cm',
        (tester) async {
      final controller = TextEditingController();
      await _pump(tester, controller, value: '14.2');

      expect(find.text('MUAC 14.2 cm'), findsOneWidget);
      expect(find.text('GREEN ZONE — Healthy MUAC'), findsOneWidget);
      expect(find.text('ADEQUATE'), findsOneWidget);
    });

    testWidgets('ignores junk input and stays in the empty zone',
        (tester) async {
      final controller = TextEditingController();
      await _pump(tester, controller, value: 'abc');

      // Non-numeric input must not light up any coloured zone — the gauge
      // is honest about not having a value to interpret.
      expect(find.text('Enter MUAC to see the zone'), findsOneWidget);
      expect(find.text('No MUAC recorded'), findsOneWidget);
    });

    testWidgets('updates live when the controller is changed externally',
        (tester) async {
      final controller = TextEditingController();
      await _pump(tester, controller, value: '10.0');

      expect(
        find.text('RED ZONE — Severe Acute Malnutrition'),
        findsOneWidget,
      );

      controller.text = '14.0';
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      expect(find.text('MUAC 14.0 cm'), findsOneWidget);
      expect(find.text('GREEN ZONE — Healthy MUAC'), findsOneWidget);
    });
  });
}
