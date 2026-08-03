/// Widget smoke tests for the Assess tab — the bottom-nav launch point for a
/// clinical assessment.
///
/// These pin the three behaviours that would silently break the CHO's fastest
/// path into a visit: the capability gate must degrade to a clear restricted
/// state (never a broken screen), the signature "Start Assessment" action and
/// the relocated register search must always be present for a permitted user,
/// and every register row must carry the quick assess shortcut.
library;

import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/fhw/assess_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

AppUser _user(UserRole role) => AppUser(
  id: 'u-${role.name}',
  fullName: role.isFhw ? 'Amina Fuseini' : 'Mariama Alhassan',
  phone: '0244000000',
  role: role,
  region: 'Northern Region',
  district: 'Gushegu',
  community: 'Gushegu',
);

Widget _wrap(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: const MaterialApp(home: Scaffold(body: AssessTab())),
);

void main() {
  // The tab's buttons use GoogleFonts; keep the test offline and deterministic.
  GoogleFonts.config.allowRuntimeFetching = false;

  group('AssessTab', () {
    testWidgets('degrades to a restricted state without the capability', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap([
        currentUserProvider.overrideWithValue(_user(UserRole.caregiver)),
      ]));

      expect(find.text('Assessments restricted'), findsOneWidget);
      expect(find.text('Start Assessment'), findsNothing);
    });

    testWidgets('shows the primary action and register search when permitted', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap([
        currentUserProvider.overrideWithValue(
          _user(UserRole.frontlineHealthWorker),
        ),
        visibleHouseholdsProvider.overrideWith((ref) async => <Household>[]),
      ]));
      await tester.pump();

      expect(find.text('Start Assessment'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('No families yet'), findsOneWidget);
    });

    testWidgets('gives every register row a quick assess shortcut', (
      tester,
    ) async {
      const household = Household(
        id: 'h-1',
        name: "Mariama's household",
        region: 'Northern Region',
        district: 'Gushegu',
        community: 'Gushegu',
        createdBy: 'u-frontlineHealthWorker',
      );

      await tester.pumpWidget(_wrap([
        currentUserProvider.overrideWithValue(
          _user(UserRole.frontlineHealthWorker),
        ),
        visibleHouseholdsProvider.overrideWith((ref) async => [household]),
        householdMembersProvider.overrideWith((ref, id) async => <Person>[]),
      ]));
      await tester.pump();

      expect(find.text("Mariama's household"), findsOneWidget);
      expect(find.byTooltip('Start assessment'), findsOneWidget);
    });
  });
}
