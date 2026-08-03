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
import 'package:google_fonts/google_fonts.dart';

import '../../app/providers.dart';
import '../../core/auth/session.dart';
import '../../data/local/preferences_store.dart';
import '../../domain/enums.dart';
import '../../presentation/auth/forgot_pin_screen.dart';
import '../../presentation/auth/onboarding_screen.dart';
import '../../presentation/auth/setup_screen.dart';
import '../../presentation/auth/sign_in_screen.dart';
import '../../presentation/caregiver/caregiver_home.dart';
import '../../presentation/fhw/fhw_home.dart';
import '../../presentation/settings/voice_test_screen.dart';
import '../../presentation/shared/app_image.dart';
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
        builder: (_, _) => const _SplashScreen(),
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
    if (user == null) return const _SplashScreen();
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

/// Splash — master flow screen [1].
///
/// Logo, wordmark and the "Works Offline" badge; auto-advances after ~2s or
/// on tap, whichever comes first.
class _SplashScreen extends ConsumerStatefulWidget {
  const _SplashScreen();

  @override
  ConsumerState<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<_SplashScreen> {
  bool _routed = false;

  @override
  void initState() {
    super.initState();
    // Wait for the bootstrap to settle (which is what makes the session
    // non-Loading) before reading the preferences. Reading the flag too early
    // would race with the database open and could show onboarding to a
    // returning user.
    Future.microtask(_route);
  }

  Future<void> _route() async {
    // Hold the splash for ~2s total (master flow [1]) while the session
    // resolves; whichever takes longer wins.
    await Future<void>.delayed(const Duration(milliseconds: 1900));
    if (!mounted || _routed) return;

    // Watch the session until it leaves Loading. The redirect keeps us on the
    // splash while the database is being opened, so by the time we get past
    // here the session is one of the steady states.
    while (ref.read(sessionProvider) is SessionLoading) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
    }
    _advance();
  }

  void _advance() {
    if (!mounted || _routed) return;
    _routed = true;
    _go();
  }

  Future<void> _go() async {
    final session = ref.read(sessionProvider);
    if (session is SessionActive) {
      // Already signed in from a previous launch; the redirect will move us.
      return;
    }

    // First-run intro runs for everyone, fresh install or not: onboarding
    // [2][3][4] then straight to the role choice [7]. The privacy notice is
    // already part of the registration form, so it does not need its own screen.
    final seenOnboarding = await PreferencesStore.hasSeenOnboarding();
    if (!mounted) return;
    if (!seenOnboarding) {
      context.go(Routes.onboarding);
      return;
    }
    context.go(session is SessionNeedsSetup ? Routes.setup : Routes.signIn);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: _advance,
    child: Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: Column(
              children: [
                const SizedBox(height: Gap.xl),
                // Brand mark — the heart-and-cross logo, large and clear.
                _SplashLogo(),
                const SizedBox(height: Gap.lg),
                // Hero image — a real CHW with a real mother and baby.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: AspectRatio(
                      aspectRatio: 4 / 3.2,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Container(color: AppColors.surfaceTint),
                          AppImage(src: AppImages.splashHero),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Gap.lg),
                // Three feature pills in a single rounded card.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                  child: _FeatureRow(),
                ),
                const SizedBox(height: Gap.md),
                // "Works Offline" reassurance pill.
                const _OfflinePill(),
                const SizedBox(height: Gap.lg),
                // Loading bar + caption.
                const _LoadingBar(),
                const SizedBox(height: Gap.sm),
                Text(
                  'Empowering healthier communities',
                  textAlign: TextAlign.center,
                  style: AppType.caption.copyWith(
                    color: AppColors.inkMuted,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: Gap.lg),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// The brand mark at the top of the splash: a heart with a medical cross,
/// drawn in the signature royal-blue gradient so it reads as premium product
/// rather than a hobby illustration.
class _SplashLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 108,
          height: 108,
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            shape: BoxShape.circle,
            boxShadow: const [AppShadows.glow],
          ),
          child: const Icon(
            Icons.favorite_rounded,
            color: Colors.white,
            size: 56,
          ),
        ),
        const SizedBox(height: Gap.md),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            children: [
              TextSpan(
                text: 'CareBridge',
                style: GoogleFonts.sora(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: AppColors.primaryDeep,
                ),
              ),
              TextSpan(
                text: ' AI',
                style: GoogleFonts.sora(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: AppColors.primaryGlow,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'AI-ASSISTED COMMUNITY HEALTHCARE',
          style: AppType.eyebrow.copyWith(
            letterSpacing: 2.0,
            color: AppColors.primary,
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }
}

/// The three feature pills — Works Offline, AI Guidance, Community First.
class _FeatureRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Gap.md,
        vertical: Gap.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Gap.radius),
        border: Border.all(color: AppColors.line, width: Gap.hairline),
        boxShadow: const [AppShadows.card],
      ),
      child: Row(
        children: [
          Expanded(
            child: _FeaturePill(
              icon: Icons.wifi_off_rounded,
              title: 'Works Offline',
              subtitle: 'Always available',
            ),
          ),
          Container(
            width: 1,
            height: 36,
            color: AppColors.line,
            margin: const EdgeInsets.symmetric(horizontal: Gap.sm),
          ),
          Expanded(
            child: _FeaturePill(
              icon: Icons.psychology_outlined,
              title: 'AI Guidance',
              subtitle: 'Smarter decisions',
            ),
          ),
          Container(
            width: 1,
            height: 36,
            color: AppColors.line,
            margin: const EdgeInsets.symmetric(horizontal: Gap.sm),
          ),
          Expanded(
            child: _FeaturePill(
              icon: Icons.groups_2_outlined,
              title: 'Community First',
              subtitle: 'Better together',
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 19, color: AppColors.primary),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 9.5,
            color: AppColors.inkMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// "Works Offline" reassurance pill — small, with a green dot.
class _OfflinePill extends StatelessWidget {
  const _OfflinePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Gap.md,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: AppColors.triageGreenBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.triageGreen.withValues(alpha: 0.30),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(
              color: AppColors.triageGreen,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'WORKS OFFLINE',
            style: GoogleFonts.manrope(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: AppColors.triageGreen,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '·',
            style: TextStyle(color: AppColors.triageGreen, fontSize: 12),
          ),
          Flexible(
            child: Text(
              'Your data is safe on this device',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.triageGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The animated loading bar at the bottom of the splash.
class _LoadingBar extends StatefulWidget {
  const _LoadingBar();

  @override
  State<_LoadingBar> createState() => _LoadingBarState();
}

class _LoadingBarState extends State<_LoadingBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Loading CareBridge AI…',
          style: GoogleFonts.manrope(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (_, _) => LinearProgressIndicator(
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
              backgroundColor: AppColors.line,
              value: 0.4 + (_controller.value * 0.6),
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }
}
