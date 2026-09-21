/// The caregiver pushed screens all open through [CompanionPage], whose bar
/// carries the caregiver gradient. Two things have broken here before: a wide
/// title plus the emergency chip overflowing at 320px and 200% text, and the
/// emergency control being restyled into something that no longer responds.
library;

import 'package:carebridge_ai/domain/entities/caregiver.dart';
import 'package:carebridge_ai/presentation/caregiver/caregiver_providers.dart';
import 'package:carebridge_ai/presentation/caregiver/widgets/companion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _scope = CaregiverScope(userId: 'user-1', householdId: 'hh-1');

Future<void> _pump(
  WidgetTester tester, {
  required bool heroChrome,
  double textScale = 2,
}) {
  tester.view.physicalSize = const Size(320, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    ProviderScope(
      overrides: [caregiverScopeProvider.overrideWithValue(_scope)],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(textScale),
            size: const Size(320, 720),
          ),
          child: CompanionPage(
            title: 'Show the nurse what to check',
            heroChrome: heroChrome,
            child: const SizedBox(height: 40),
          ),
        ),
      ),
    ),
  );
}

void main() {
  for (final hero in [true, false]) {
    testWidgets(
      'CompanionPage heroChrome: $hero fits 320px at 200% text',
      (tester) async {
        await _pump(tester, heroChrome: hero);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final button = tester.getRect(
          find.ancestor(
            of: find.byIcon(Icons.emergency_outlined),
            matching: find.byType(IconButton),
          ),
        );
        expect(button.width, greaterThanOrEqualTo(44));
        expect(button.height, greaterThanOrEqualTo(44));
      },
    );
  }

  testWidgets('the emergency chip still opens the emergency dialog', (
    tester,
  ) async {
    await _pump(tester, heroChrome: true, textScale: 1);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.emergency_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Emergency help'), findsOneWidget);
    expect(find.text('Call 112'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Emergency help'), findsNothing);
  });
}
