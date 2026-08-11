/// Routing, with role enforcement at the route level.
///
/// This is the *second* of three places access is checked, and it is the least
/// important of the three. The repository is the real boundary: it takes the
/// acting user, checks a permission, and writes an audit row on refusal. Route
/// guards cannot be trusted on their own — a deep link is just a string, and a
/// guard is only as good as the developer who remembered to add it.
///
/// They are here anyway, because the alternative is a caregiver reaching an
/// assessment form, filling it in, and *then* being refused at save time. Failing
/// at the door is kinder than failing at the till.
///
/// The redirect logic has exactly one job: keep the visible screen consistent
/// with the session. Everything else — which tab, which household — is ordinary
/// navigation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/auth/session.dart';
import '../../domain/enums.dart';
import '../../presentation/auth/forgot_pin_screen.dart';
import '../../presentation/auth/onboarding_screen.dart';
import '../../presentation/auth/setup_screen.dart';
import '../../presentation/auth/sign_in_screen.dart';
import '../../presentation/auth/splash_screen.dart';
import '../../presentation/caregiver/caregiver_home.dart';
import '../../presentation/fhw/fhw_home.dart';
import '../../presentation/settings/data_inspector_screen.dart';
import '../../presentation/settings/voice_test_screen.dart';
import '../../presentation/shared/ui.dart';
import '../theme/app_theme.dart';

abstract final class Routes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const setup = '/setup';
  static const signIn = '/sign-in';
  static const forgotPin = '/forgot-pin';

  /// Frontline health worker.
  static const fhwHome = '/fhw';

  /// Caregiver.
  static const family = '/family';

  /// Diagnostic for the CHO — what can this phone actually speak?
  static const voiceTest = '/voice-test';

  /// The on-device SQLite database, made visible.
  static const database = '/database';

  /// Where a role should land after signing in.
  static String homeFor(UserRole role) => role.isFhw ? fhwHome : family;
}

/// Rebuilds the router's redirect whenever the session changes.
///
/// A [ChangeNotifier] rather than a stream because that is what `go_router`'s
/// `refreshListenable` takes, and one adapter here is cheaper than a listener in
/// every route.
class _SessionRefresh extends ChangeNotifier {
  _SessionRefresh(this.ref) {
    ref.listen<SessionState>(sessionProvider, (_, _) => notifyListeners());
  }

  final Ref ref;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _SessionRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final here = state.matchedLocation;

      // Ensure the splash screen is never cut short by rapid SQLite session loading.
      // The SplashScreen widget is tap-to-continue and waits for session
      // readiness before calling context.go().
      if (here == Routes.splash || here.isEmpty) return null;

      switch (session) {
        // Still opening the database. Hold on the splash rather than flashing a
        // sign-in form at someone who is already signed in.
        case SessionLoading():
          return here == Routes.splash ? null : Routes.splash;

        case SessionNeedsSetup():
          // A fresh device still gets the full first-run welcome — splash,
          // onboarding, the role choice and the sign-in screen are all
          // reachable before the user has an account. "Create a new account"
          // on the sign-in screen brings them back to the registration form.
          // The privacy notice is folded into the registration form, so it
          // does not need a separate route.
          if (here == Routes.splash ||
              here == Routes.onboarding ||
              here == Routes.setup ||
              here == Routes.signIn) {
            return null;
          }
          return Routes.setup;

        case SessionSignedOut():
          // The role choice [7] is reachable the first time a user signs out
          // of a shared device, so they can pick a different account. After
          // that, signed-out users land on sign-in.
          if (here == Routes.onboarding ||
              here == Routes.setup ||
              here == Routes.forgotPin) {
            return null;
          }
          return here == Routes.signIn ? null : Routes.signIn;

        case SessionActive(user: final user):
          final home = Routes.homeFor(user.role);

          // Bounce off the pre-auth screens.
          if (here == Routes.splash ||
              here == Routes.signIn ||
              here == Routes.setup ||
              here == Routes.forgotPin) {
            return home;
          }

          // A caregiver cannot be anywhere under /fhw, and vice versa. This is
          // the coarse role separation; per-action permissions are still checked
          // inside the repository.
          if (here.startsWith(Routes.fhwHome) && !user.role.isFhw) return home;
          if (here.startsWith(Routes.family) && !user.role.isCaregiver) {
            return home;
          }
          return null;
      }
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (_, _) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.onboarding,
        pageBuilder: (_, _) => _fadePage(const OnboardingScreen()),
      ),
      GoRoute(
        path: Routes.setup,
        pageBuilder: (_, _) => _fadePage(const SetupScreen()),
      ),
      GoRoute(
        path: Routes.signIn,
        pageBuilder: (_, _) => _fadePage(const SignInScreen()),
      ),
      GoRoute(
        path: Routes.forgotPin,
        pageBuilder: (_, _) => _fadePage(const ForgotPinScreen()),
      ),
      GoRoute(
        path: Routes.fhwHome,
        pageBuilder: (_, _) => _fadePage(
          const RequirePermission(
            permission: Permission.viewAllHouseholds,
            child: FhwHome(),
          ),
        ),
      ),
      GoRoute(
        path: Routes.family,
        pageBuilder: (_, _) => _fadePage(
          const RequirePermission(
            permission: Permission.runCaregiverTriage,
            child: CaregiverHome(),
          ),
        ),
      ),
      GoRoute(
        path: Routes.voiceTest,
        pageBuilder: (_, _) => _fadePage(const VoiceTestScreen()),
      ),
      GoRoute(
        path: Routes.database,
        pageBuilder: (_, _) => _fadePage(const DataInspectorScreen()),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: EmptyState(
        icon: Icons.explore_off_outlined,
        title: 'That screen does not exist',
        message: state.error?.message ?? 'The link may be out of date.',
        action: FilledButton(
          onPressed: () {
            final user = ref.read(currentUserProvider);
            context.go(
              user == null ? Routes.signIn : Routes.homeFor(user.role),
            );
          },
          child: const Text('Back to start'),
        ),
      ),
    ),
  );
});

/// A slow fade + subtle rise, the app's signature page transition.
Page<void> _fadePage(Widget child, {LocalKey? key}) => CustomTransitionPage<void>(
  key: key,
  child: child,
  transitionDuration: AppMotion.duration,
  reverseTransitionDuration: AppMotion.duration,
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.015),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  },
);

/// Wraps a screen in a capability check.
///
/// Deliberately capability-based rather than role-based, matching [Permission]:
/// a screen declares what it needs done, not who is allowed to be there. Adding a
/// CHV or a district officer later means editing one permission set, not hunting
/// through widgets for `role == ...`.
class RequirePermission extends ConsumerWidget {
  const RequirePermission({
    super.key,
    required this.permission,
    required this.child,
    this.message,
  });

  final Permission permission;
  final Widget child;
  final String? message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SplashScreen();
    if (user.can(permission)) return child;

    return Scaffold(
      appBar: AppBar(title: const Text('Not available')),
      body: AccessDeniedView(
        message:
            message ??
            'This part of the app is for ${UserRole.frontlineHealthWorker.label}s. '
                'Your account is a ${user.role.label} account.',
        onBack: () => context.go(Routes.homeFor(user.role)),
      ),
    );
  }
}
