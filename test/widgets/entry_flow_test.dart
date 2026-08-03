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

/// Runs out the splash's timed routing, then settles the page transition.
Future<void> _leaveSplash(WidgetTester tester) async {
  await tester.pump(); // Schedule the splash's routing microtask.
  await tester.pump(const Duration(milliseconds: 2000)); // Past the ~1.9s hold.
  await tester.pump(const Duration(milliseconds: 100)); // Flush the flag reads.
  await tester.pump(const Duration(milliseconds: 100)); // Flush the navigation.
  await tester.pump(const Duration(milliseconds: 500)); // Settle the fade.
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
