/// Widget smoke tests for the Patients tab — the register a health worker
/// searches before adding anyone.
///
/// Three behaviours would silently break the fastest path into an assessment
/// if they regressed: the capability gate must degrade to a clear restricted
/// state rather than a broken screen, patient-name search must survive the
/// household list being unavailable, and every record row must carry its own
/// assess shortcut next to the household it belongs to.
library;

import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/fhw/assess_tab.dart';
import 'package:carebridge_ai/presentation/fhw/home_tab.dart' show clinicQueueProvider;
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

const _household = Household(
  id: 'h-1',
  name: "Mariama's household",
  region: 'Northern Region',
  district: 'Gushegu',
  community: 'Gushegu',
  createdBy: 'u-frontlineHealthWorker',
);

const _saliha = Person(
  id: 'p-1',
  householdId: 'h-1',
  fullName: 'Saliha Fuseini',
  clientType: ClientType.pregnantWoman,
);

const _baby = Person(
  id: 'p-2',
  householdId: 'h-1',
  fullName: 'Abdul Fuseini',
  clientType: ClientType.childUnderFive,
);

/// The tab reads people through the repository, which needs a real database.
/// Every case here is about the list, so the member map is supplied directly.
Widget _wrap({
  required List<Household> households,
  Map<String, List<Person>> people = const {},
  bool peopleFail = false,
}) => ProviderScope(
  overrides: [
    currentUserProvider.overrideWithValue(_user(UserRole.frontlineHealthWorker)),
    visibleHouseholdsProvider.overrideWith((ref) async => households),
    clinicQueueProvider.overrideWith((ref) async => const []),
    if (peopleFail)
      clinicPeopleProvider.overrideWith((ref) async => throw StateError('db'))
    else
      clinicPeopleProvider.overrideWith((ref) async => people),
  ],
  child: const MaterialApp(home: Scaffold(body: AssessTab())),
);

void main() {
  // The tab's buttons use GoogleFonts; keep the test offline and deterministic.
  GoogleFonts.config.allowRuntimeFetching = false;

  group('AssessTab', () {
    testWidgets('degrades to a restricted state without the capability', (
      tester,
    ) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(_user(UserRole.caregiver)),
        ],
        child: const MaterialApp(home: Scaffold(body: AssessTab())),
      ));

      expect(find.text('Assessments restricted'), findsOneWidget);
      expect(find.text('Receive a patient'), findsNothing);
    });

    testWidgets('shows the intake action, search and an honest empty record', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(households: const []));
      await tester.pump();

      expect(find.text('Receive a patient'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('No household records yet'), findsOneWidget);
    });

    testWidgets('finds a household by the name of a person inside it', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          households: const [_household],
          people: const {'h-1': [_saliha, _baby]},
        ),
      );
      await tester.pump();

      expect(find.text("Mariama's household"), findsOneWidget);
      expect(find.text('Saliha Fuseini · Abdul Fuseini'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'saliha');
      await tester.pump();

      expect(find.text('Saliha Fuseini'), findsOneWidget);
      expect(find.text('Abdul Fuseini'), findsNothing);
    });

    testWidgets('filters the register to one care group', (tester) async {
      await tester.pumpWidget(
        _wrap(
          households: const [_household],
          people: const {'h-1': [_saliha, _baby]},
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Child care'));
      await tester.pump();

      expect(find.text('Abdul Fuseini'), findsOneWidget);
      expect(find.text('Saliha Fuseini · Abdul Fuseini'), findsNothing);
    });

    testWidgets('gives every record row its own assess shortcut', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          households: const [_household],
          people: const {'h-1': [_saliha]},
        ),
      );
      await tester.pump();

      expect(find.text('Assess'), findsOneWidget);
      expect(find.text('Open record'), findsOneWidget);
    });

    testWidgets('keeps household search when patient names cannot load', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(households: const [_household], peopleFail: true),
      );
      await tester.pump();

      expect(
        find.text(
          'Patient names could not be loaded. Household search is still '
          'available. Tap to retry.',
        ),
        findsOneWidget,
      );
      expect(find.text('Assess'), findsOneWidget);
    });
  });
}
