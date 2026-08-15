/// Entry-flow regression tests — the order of the first screens.
///
/// The bug that motivated this suite: on a fresh install the splash routed
/// straight to "Who is using this phone?", skipping the onboarding slides
/// entirely. The master flow is now
/// splash [1] → onboarding [2][3][4] → role choice [7] → sign-in [8]
/// → (create account →) registration, and a returning (signed-out) device
/// lands on sign-in instead of the role choice once the intro screens have
/// been seen. The privacy notice is folded into the registration form, so
/// it does not need its own screen.
library;

import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/core/auth/session.dart';
import 'package:carebridge_ai/core/router/app_router.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/auth/onboarding_screen.dart';
import 'package:carebridge_ai/presentation/auth/setup_screen.dart';
import 'package:carebridge_ai/presentation/auth/sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A session pinned to one state, so the splash's routing logic — not the
/// database — is what the test exercises.
class _FixedSession extends SessionNotifier {
  _FixedSession(this.initial);

  final SessionState initial;

  @override
  SessionState build() => initial;
}

Future<void> _pumpApp(WidgetTester tester, SessionState session) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [sessionProvider.overrideWith(() => _FixedSession(session))],
      child: Consumer(
        builder: (context, ref, _) =>
            MaterialApp.router(routerConfig: ref.watch(routerProvider)),
      ),
    ),
  );
}

/// Taps the splash (it never auto-advances), then settles the page transition.
Future<void> _leaveSplash(WidgetTester tester) async {
  await tester.pump(); // Build the splash.
  await tester.pump(const Duration(milliseconds: 300)); // First paint.
  await tester.tapAt(tester.getCenter(find.byType(Scaffold))); // Tap to continue.
  await tester.pump(const Duration(milliseconds: 100)); // Flush session reads.
  await tester.pump(const Duration(milliseconds: 100)); // Flush the navigation.
  await tester.pump(const Duration(milliseconds: 600)); // Settle the fade.
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('fresh install: splash leads to onboarding, not role choice', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await _pumpApp(tester, const SessionNeedsSetup());

    await _leaveSplash(tester);

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(
      find.text('Supporting mothers through every stage'),
      findsOneWidget,
    );
  });

  testWidgets('fresh install, onboarding seen: splash leads to role choice', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboarding_seen': true});
    await _pumpApp(tester, const SessionNeedsSetup());

    await _leaveSplash(tester);

    expect(find.byType(SetupScreen), findsOneWidget);
    expect(find.text('Who are you?'), findsOneWidget);
  });

  testWidgets('returning signed-out device: splash leads to sign-in', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboarding_seen': true,
    });
    await _pumpApp(tester, const SessionSignedOut(lastPhone: '024 000 0000'));

    await _leaveSplash(tester);

    expect(find.text('Remember me'), findsOneWidget);
  });

  testWidgets(
    'role choice: tapping a role routes to sign-in (no "I already have an '
    'account" shortcut on the role choice anymore)',
    (tester) async {
      SharedPreferences.setMockInitialValues({'onboarding_seen': true});
      await _pumpApp(tester, const SessionNeedsSetup());

      await _leaveSplash(tester);

      // The role choice is showing.
      expect(find.byType(SetupScreen), findsOneWidget);
      expect(find.text('Who are you?'), findsOneWidget);
      expect(find.text('I already have an account'), findsNothing);

      // Pick the FHW role. The flow routes to sign-in, not the
      // registration form, so an existing user can sign in without having
      // to scroll past the form.
      await tester.tap(find.text('Frontline Health Worker'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.text('Create a new account'), findsOneWidget);
      expect(find.text('Remember me'), findsOneWidget);
    },
  );

  testWidgets(
    'caregiver: filling "Your details" and continuing renders the family '
    'step without layout errors (regression: blank screen + hit-test on a '
    'size-less render box)',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({'onboarding_seen': true});
      await _pumpApp(tester, const SessionNeedsSetup());
      await _leaveSplash(tester);

      // Pick the caregiver role, route through sign-in, create an account.
      await tester.tap(
        find.text('Caregiver', findRichText: true).first,
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(SignInScreen), findsOneWidget);
      await tester.tap(find.text('Create a new account'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Your details'), findsOneWidget);

      // Fill step 0: name, phone, PIN, confirm PIN.
      await tester.enterText(
        find.widgetWithText(TextField, 'e.g. Abdul-Rahman Suleimana'),
        'Amina Iddrisu',
      );
      await tester.enterText(
        find.widgetWithText(TextField, '024 000 0000'),
        '0244 111 222',
      );
      await tester.enterText(
        find.widgetWithText(TextField, '4 digits'),
        '5729',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Repeat your PIN'),
        '5729',
      );

      // Continue to the "Your family" step.
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The family step must actually render — the reported freeze was a
      // blank body on this step.
      expect(find.text('Your family'), findsWidgets);
      // FieldLabel renders its text uppercased.
      expect(find.text('OR TYPE THE 6-CHARACTER CODE'), findsOneWidget);
      expect(find.text('Check'), findsOneWidget);

      // Tapping Continue without a code shows the validation error, and
      // the form must still be interactive afterwards.
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(
        find.text(
          'Enter the family code the health worker gave you, then tap Check.',
        ),
        findsOneWidget,
      );
      expect(find.text('OR TYPE THE 6-CHARACTER CODE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sign-in: "Create a new account" returns to the registration form, '
    'pre-applied with the role picked on the role choice',
    (tester) async {
      // The sign-in screen runs a SingleChildScrollView; on a 600-px-tall
      // test surface the "Create a new account" button sits off-screen. The
      // test viewport is sized larger than the surface to keep the bottom
      // button in the hit-test region.
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({'onboarding_seen': true});
      await _pumpApp(tester, const SessionNeedsSetup());

      await _leaveSplash(tester);

      // Pick the FHW role and reach sign-in.
      await tester.tap(find.text('Frontline Health Worker'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(SignInScreen), findsOneWidget);

      // The "Create a new account" button must explicitly route to
      // /setup, because the session is already in [SessionNeedsSetup] and
      // `markNeedsSetup` is a no-op in that state.
      await tester.tap(find.text('Create a new account'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));

      // We are back on the setup screen, but the role choice has been
      // skipped because [pendingRoleProvider] is set. Step 0 ("Your
      // details") is the only step rendered on first paint, so we assert
      // on its title rather than a field that lives on a later step.
      expect(find.text('I already have an account'), findsNothing);
      expect(find.text('Who are you?'), findsNothing);
      expect(find.text('Your details'), findsOneWidget);

      // Sanity-check that the pending role is read in the expected state.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SetupScreen)),
      );
      expect(
        container.read(pendingRoleProvider),
        UserRole.frontlineHealthWorker,
      );
    },
  );
}
