/// The Help tab as a care hub: the emergency path first, support contacts
/// as live tiles, and every quiet setting behind a focused sub-screen.
/// These tests pin the hub structure and prove each honesty notice is still
/// reachable verbatim after the progressive-disclosure move.
library;

import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/domain/entities/caregiver.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/caregiver/caregiver_providers.dart';
import 'package:carebridge_ai/presentation/caregiver/help/help_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _scope = CaregiverScope(userId: 'caregiver', householdId: 'household');
const _trusted = SupportContact(
  kind: SupportContactKind.trustedPerson,
  name: 'Habiba Yakubu',
  number: '020 000 0001',
  landmark: 'Near the mosque',
);

Widget _app(Widget child, {double scale = 1}) => MaterialApp(
  builder: (context, built) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
    child: built!,
  ),
  home: Scaffold(body: child),
);

Future<void> _help(
  WidgetTester tester, {
  List<SupportContact> contacts = const [],
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        caregiverScopeProvider.overrideWithValue(_scope),
        currentUserProvider.overrideWithValue(
          AppUser(
            id: 'caregiver',
            fullName: 'Mariama Alhassan',
            phone: '0244123456',
            role: UserRole.caregiver,
            region: 'Northern Region',
            district: 'Tamale',
            community: 'Tamale',
          ),
        ),
        caregiverSettingsProvider.overrideWith(
          (ref, scope) async => CaregiverSettings(
            scope: scope,
            updatedAt: DateTime(2026, 9, 24),
            contacts: contacts,
          ),
        ),
      ],
      child: _app(
        const CaregiverHelpTab(householdId: 'household'),
        scale: scale,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 20; i++) {
    if (finder.evaluate().isNotEmpty) {
      final center = tester.getCenter(finder);
      if (center.dy > 20 && center.dy < 820) return;
    }
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(finder);
}

Future<void> _back(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('emergency path is the first action on the hub', (tester) async {
    await _help(tester);
    expect(find.text('If it is an emergency'), findsOneWidget);
    expect(
      find.text('Call 112 — emergency line').hitTestable(),
      findsOneWidget,
    );
    // The calling caveat is quiet until asked for — but never hidden.
    expect(
      find.textContaining('does not dispatch help', findRichText: true),
      findsNothing,
    );
    await tester.tap(find.text('What to know'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'This app does not dispatch help or arrange transport.',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('hub shows the four care tiles under the people section', (
    tester,
  ) async {
    await _help(tester);
    expect(find.text('Help and support'), findsOneWidget);
    expect(find.text('People who may help'), findsOneWidget);
    for (final tile in [
      'Language & listening',
      'Voice guide',
      'Display',
      'Account & this phone',
    ]) {
      await _scrollTo(tester, find.text(tile));
      expect(find.text(tile).hitTestable(), findsOneWidget, reason: tile);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('contact tiles carry saved and empty states into the editor', (
    tester,
  ) async {
    await _help(tester, contacts: const [_trusted]);
    expect(find.text('Habiba Yakubu'), findsOneWidget);
    expect(find.text('No contact saved.'), findsNWidgets(2));
    // The stay-on-this-phone notice no longer clutters the hub; it lives
    // with the editing action it describes.
    expect(
      find.text(
        'Contacts you enter stay on this phone. Numbers and availability '
        'are not verified; saving a contact does not ask them for help.',
      ),
      findsNothing,
    );
    await _scrollTo(tester, find.text('Transport contact'));
    await tester.tap(find.text('Transport contact'));
    await tester.pumpAndSettle();
    expect(find.text('Phone number'), findsOneWidget);
    expect(
      find.text(
        "Ask permission before saving someone's contact details. The app "
        'cannot verify the number or whether they can help.',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Contacts you enter stay on this phone. Numbers and availability '
        'are not verified; saving a contact does not ask them for help.',
      ),
      findsOneWidget,
    );
    await _back(tester);
    expect(find.text('Habiba Yakubu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('each hub tile opens its screen with the notices intact', (
    tester,
  ) async {
    await _help(tester);

    await _scrollTo(tester, find.text('Language & listening'));
    await tester.tap(find.text('Language & listening'));
    await tester.pumpAndSettle();
    expect(find.text('Preferred language: English'), findsOneWidget);
    expect(find.text('Automatic question reading: Off'), findsOneWidget);
    expect(
      find.textContaining(
        'Bundled synthetic/draft-language audio still needs qualified and '
        'native-speaker review.',
        findRichText: true,
      ),
      findsOneWidget,
    );
    await _back(tester);

    await _scrollTo(tester, find.text('Display'));
    await tester.tap(find.text('Display'));
    await tester.pumpAndSettle();
    expect(find.text('Lite display'), findsOneWidget);
    expect(
      find.textContaining(
        'If device storage is unavailable it may not survive a restart.',
        findRichText: true,
      ),
      findsOneWidget,
    );
    await _back(tester);

    await _scrollTo(tester, find.text('Account & this phone'));
    await tester.tap(find.text('Account & this phone'));
    await tester.pumpAndSettle();
    expect(find.text('Mariama Alhassan'), findsOneWidget);
    expect(
      find.textContaining(
        'are not restored by account recovery on another device',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.text('Hand the phone back'), findsOneWidget);
    await _back(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hub survives 320px at 200% text without losing the call', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _help(tester, contacts: const [_trusted], scale: 2);
    await _scrollTo(tester, find.text('Call 112 — emergency line'));
    expect(
      find.text('Call 112 — emergency line').hitTestable(),
      findsOneWidget,
    );
    await _scrollTo(tester, find.text('Habiba Yakubu'));
    expect(find.text('Habiba Yakubu').hitTestable(), findsOneWidget);
    await _scrollTo(tester, find.text('Account & this phone'));
    expect(find.text('Account & this phone').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
