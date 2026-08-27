/// Caregiver end-to-end test: the whole journey on a fresh device.
///
/// The bug that motivated this suite: caregiver sign-up demanded a family
/// code that could only exist if a health worker had already registered the
/// household *on this same phone*, which is impossible on a fresh device,
/// so the caregiver flow was dead on arrival. The fix added the self-create
/// path ('My family is not registered yet'), and this test walks it for
/// real: no session overrides, a genuine SQLite database, a genuine
/// registration, and everything a family does afterwards: add a member,
/// run the danger-sign check, see the vaccine plan, sign out, and sign
/// back in to find their record still there.
library;

import 'dart:io';

import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/core/router/app_router.dart';
import 'package:carebridge_ai/data/local/app_database.dart';
import 'package:carebridge_ai/data/reference/northern_ghana.dart';
import 'package:carebridge_ai/data/sync/sync_service.dart';
import 'package:carebridge_ai/presentation/auth/setup_screen.dart';
import 'package:carebridge_ai/presentation/auth/sign_in_screen.dart';
import 'package:carebridge_ai/presentation/caregiver/caregiver_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A TextField located by its hint text; the registration and sign-in
/// screens carry no keys, and their hints are the stable copy.
Finder _fieldByHint(String hint) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == hint,
);

/// A TextField located by its label text (the add-member sheet uses labels).
Finder _fieldByLabel(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

/// The real app, un-overridden except for the sync service: the test VM has
/// no connectivity plugin, and the sync timer is irrelevant to what a
/// caregiver does on their own phone. The replacement service is created but
/// never started, so no timers linger after the tree is torn down.
Future<void> _pumpApp(WidgetTester tester) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        syncServiceProvider.overrideWith((ref) async {
          final service = SyncService();
          ref.onDispose(service.dispose);
          return service;
        }),
      ],
      child: Consumer(
        builder: (context, ref, _) =>
            MaterialApp.router(routerConfig: ref.watch(routerProvider)),
      ),
    ),
  );
}

/// Taps the splash (it never auto-advances), then settles the transition.
Future<void> _leaveSplash(WidgetTester tester) async {
  await tester.pump(); // Build the splash.
  await tester.pump(const Duration(milliseconds: 300)); // First paint.
  await tester.tapAt(
    tester.getCenter(find.byType(Scaffold)),
  ); // Tap to continue.
  await tester.pump(const Duration(milliseconds: 100)); // Flush session reads.
  await tester.pump(const Duration(milliseconds: 100)); // Flush the navigation.
  await tester.pump(const Duration(milliseconds: 600)); // Settle the fade.
}

/// Taps a dropdown showing [hint] and picks the menu item labelled [value].
Future<void> _pickFromDropdown(
  WidgetTester tester, {
  required String hint,
  required String value,
}) async {
  final dropdown = find.ancestor(
    of: find.text(hint),
    matching: find.byType(DropdownButtonFormField<String>),
  );
  await tester.ensureVisible(find.text(hint));
  // The hint Text is not itself hit-testable; the form field around it is.
  await tester.tap(dropdown, warnIfMissed: false);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(value).last);
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

/// Waits, on the real clock, for [finder] to match. Needed wherever the
/// SQLite FFI worker is in the loop: that isolate never runs under FakeAsync.
Future<void> _untilVisible(WidgetTester tester, Finder finder) =>
    tester.runAsync(() async {
      for (var i = 0; i < 200; i++) {
        if (finder.evaluate().isNotEmpty) return;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
      }
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets(
    'caregiver: fresh-device sign-up through the whole family experience',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // The test binding has no platform plugins: stub the audio and TTS
      // channels so the voice features degrade silently instead of
      // surfacing a MissingPluginException as a test failure.
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers'),
        (call) async => null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers.player.events'),
        (call) async => null,
      );
      messenger.setMockStreamHandler(
        const EventChannel('xyz.luan/audioplayers.global/events'),
        MockStreamHandler.inline(
          onListen: (args, events) {},
          onCancel: (args) {},
        ),
      );
      messenger.setMockStreamHandler(
        const EventChannel('flutter_tts'),
        MockStreamHandler.inline(
          onListen: (args, events) {},
          onCancel: (args) {},
        ),
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('flutter_tts'),
        (call) async => null,
      );
      // The database resolves its file through the path_provider channel,
      // which has no plugin in the test VM either. Point it at a fresh
      // temp folder so the whole journey (register -> sign out -> sign
      // back in) runs against a genuine, persistent SQLite file. The sync
      // variant is required: an awaited async File IO would deadlock under
      // the FakeAsync test zone.
      final dbDir = Directory.systemTemp.createTempSync('carebridge_e2e');
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return dbDir.path;
          }
          return null;
        },
      );

      AppDatabase.initialiseForDesktopAndTests();
      SharedPreferences.setMockInitialValues({'onboarding_seen': true});

      await _pumpApp(tester);
      await _leaveSplash(tester);
      await _untilVisible(tester, find.byType(SetupScreen));

      expect(find.byType(SetupScreen), findsOneWidget);
      expect(find.text('Who are you?'), findsOneWidget);
      await tester.tap(find.text('Caregiver'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byType(SignInScreen), findsOneWidget);
      await tester.ensureVisible(find.text('Create a new account'));
      await tester.tap(find.text('Create a new account'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Your details'), findsOneWidget);
      await tester.enterText(
        _fieldByHint('e.g. Abdul-Rahman Suleimana'),
        'Mariama Alhassan',
      );
      await tester.enterText(_fieldByHint('024 000 0000'), '0244123456');
      // The app rejects sequential PINs by design, so the PIN is not 1234.
      await tester.enterText(_fieldByHint('4 digits'), '2468');
      await tester.enterText(_fieldByHint('Repeat your PIN'), '2468');
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Your family'), findsWidgets);
      await tester.ensureVisible(
        find.textContaining('My family is not registered yet'),
      );
      await tester.tap(find.textContaining('My family is not registered yet'));
      await tester.pumpAndSettle();

      await tester.enterText(
        _fieldByHint('e.g. The Dawura family'),
        'The Test family',
      );
      const region = 'Northern Region';
      final district = NorthernGhana.districtsOf(region).first.name;
      final community = NorthernGhana.communitiesOf(region, district).first;
      await _pickFromDropdown(
        tester,
        hint: 'Choose your district',
        value: district,
      );
      await _pickFromDropdown(
        tester,
        hint: 'Choose your community',
        value: community,
      );
      await tester.enterText(
        _fieldByHint('e.g. Behind the primary school'),
        'Behind the big mango tree',
      );
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Data & privacy'), findsWidgets);
      expect(find.text('Your data, your control'), findsWidgets);
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Agree & Link My Family'));
      await tester.tap(find.text('Agree & Link My Family'));
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump(const Duration(milliseconds: 600));
      await _untilVisible(tester, find.byType(CaregiverHome));

      expect(find.byType(CaregiverHome), findsOneWidget);
      const caregiverTabs = [
        'Family',
        'Check',
        'Grow & Play',
        'Care plan',
        'Help',
      ];
      for (final label in caregiverTabs) {
        expect(find.text(label), findsWidgets, reason: 'tab $label');
      }
      const fhwTabs = ['Day plan', 'Assess', 'Referrals', 'Me'];
      for (final label in fhwTabs) {
        expect(find.text(label), findsNothing, reason: 'FHW tab $label');
      }
      expect(find.text('Our family'), findsOneWidget);
      // The household row arrives on the real clock via the SQLite isolate.
      await _untilVisible(tester, find.textContaining('The Test family'));
      expect(find.textContaining('The Test family'), findsWidgets);
      expect(find.text('Your family code'), findsOneWidget);

      await tester.ensureVisible(find.text('Add a family member').first);
      await tester.tap(find.text('Add a family member').first);
      await tester.pumpAndSettle();

      await tester.enterText(_fieldByLabel('Name'), 'Awah');
      await tester.tap(find.text('Choose the date of birth'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Male'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pump(const Duration(milliseconds: 300));
      // The sheet pops only once the write lands, and the name field inside
      // it already reads Awah, so wait for the Save button to leave the tree.
      await tester.runAsync(() async {
        for (var i = 0; i < 200; i++) {
          if (find.text('Save').evaluate().isEmpty) return;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump(const Duration(milliseconds: 50));
        }
      });
      expect(find.text('Save'), findsNothing);
      await _untilVisible(tester, find.text('Awah'));
      expect(find.text('Awah'), findsWidgets);

      await tester.tap(find.text('Check').first);
      await tester.pumpAndSettle();
      expect(find.text('Is someone unwell?'), findsWidgets);
      await tester.ensureVisible(find.text('Check the danger signs'));
      await tester.tap(find.text('Check the danger signs'));
      await tester.pumpAndSettle();
      expect(find.text('Who are you checking?'), findsWidgets);
      await _untilVisible(tester, find.text('Awah'));
      await tester.tap(find.text('Awah').last);
      await tester.pumpAndSettle();
      expect(find.text('What have you noticed?'), findsWidgets);
      // The check is a conversation now: one sign at a time, walking on by
      // itself after each answer.
      for (var i = 0; i < 8; i++) {
        await _untilVisible(tester, find.text('NO'));
        expect(find.text('NO'), findsOneWidget);
        await tester.tap(find.text('NO'));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('signs answered'), findsOneWidget);
      await tester.ensureVisible(find.text('What should I do?'));
      await tester.tap(find.text('What should I do?'));
      await tester.pumpAndSettle();
      expect(find.text('Continue routine care'), findsOneWidget);
      // Even a green verdict leaves the family with something to do.
      expect(find.text('Keep doing these'), findsOneWidget);
      await tester.ensureVisible(find.text('Continue Routine Care'));
      await tester.tap(find.text('Continue Routine Care'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Back to home'));
      await tester.tap(find.text('Back to home'));
      await tester.pumpAndSettle();
      expect(find.text('Is someone unwell?'), findsWidgets);

      // Second run, this time with a danger sign: the result must be a
      // plan, not just "go" — tickable steps and the family's own words
      // for the nurse, then the scannable clinic pass.
      await tester.ensureVisible(find.text('Check the danger signs'));
      await tester.tap(find.text('Check the danger signs'));
      await tester.pumpAndSettle();
      await _untilVisible(tester, find.text('Awah'));
      await tester.tap(find.text('Awah').last);
      await tester.pumpAndSettle();
      await _untilVisible(tester, find.text('YES'));
      await tester.tap(find.text('YES'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      for (var i = 0; i < 7; i++) {
        await _untilVisible(tester, find.text('NO'));
        await tester.tap(find.text('NO'));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('What should I do?'));
      await tester.tap(find.text('What should I do?'));
      await tester.pumpAndSettle();
      expect(find.text('Go to the health facility now'), findsOneWidget);
      expect(find.text('Do these now — even on the way'), findsOneWidget);
      expect(find.textContaining('YOUR WORDS FOR THE NURSE'), findsOneWidget);
      expect(find.textContaining('What I noticed:'), findsOneWidget);
      await tester.ensureVisible(find.text('Go to Clinic Now'));
      await tester.tap(find.text('Go to Clinic Now'));
      await tester.pumpAndSettle();
      expect(find.text('SCAN AT CLINIC'), findsOneWidget);
      await tester.ensureVisible(find.text('I have arrived'));
      await tester.tap(find.text('I have arrived'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Back to home'));
      await tester.tap(find.text('Back to home'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Grow & Play'));
      await tester.pumpAndSettle();
      expect(find.text('Grow and play'), findsWidgets);
      expect(find.text('Check the milestones'), findsWidgets);
      expect(find.textContaining('Play today:'), findsOneWidget);

      await tester.tap(find.text('Care plan'));
      await tester.pumpAndSettle();
      expect(find.text('Digital Yellow Card'), findsWidgets);
      expect(find.textContaining('doses may be overdue'), findsWidgets);

      await tester.tap(find.text('Help'));
      await tester.pumpAndSettle();
      expect(find.text('If it is an emergency'), findsWidgets);
      expect(find.text('Test the voice'), findsWidgets);
      await tester.ensureVisible(find.text('Hand the phone back'));
      expect(find.text('Hand the phone back'), findsWidgets);
      await tester.tap(find.text('Hand the phone back'));
      await tester.pump(const Duration(milliseconds: 200));
      await _untilVisible(tester, find.byType(SignInScreen));

      await tester.enterText(_fieldByHint('024 000 0000'), '0244123456');
      await tester.enterText(_fieldByHint('Enter your 4-digit PIN'), '2468');
      await tester.ensureVisible(find.text('Sign in'));
      await tester.tap(find.text('Sign in'));
      await tester.pump(const Duration(milliseconds: 200));
      await _untilVisible(tester, find.byType(CaregiverHome));

      expect(find.byType(CaregiverHome), findsOneWidget);
      await _untilVisible(tester, find.textContaining('The Test family'));
      expect(find.textContaining('The Test family'), findsWidgets);
      expect(find.text('Awah'), findsWidgets);

      // Drain the voice chain: VoiceService polls the TTS engine in
      // 250 ms steps, and the auto-played questions leave those timers
      // in flight. Advance fake time until every chain has finished so
      // the teardown sees no pending timers.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
