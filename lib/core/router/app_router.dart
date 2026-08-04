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
import '../../presentation/settings/data_inspector_screen.dart';
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
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final screenW = MediaQuery.of(context).size.width;
    // Hero photo takes ~60% of screen height so the footer is always visible.
    final heroH = screenH * 0.60;

    return GestureDetector(
      onTap: _advance,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            // ── Full-bleed hero photo ──────────────────────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: heroH,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AppImage(src: AppImages.motherChild),
                  // Subtle top gradient so the logo is readable over the photo.
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.center,
                        colors: [
                          Color(0xCCFFFFFF),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Wave clip that hides the photo bottom edge ─────────────────
            Positioned(
              top: heroH - 40,
              left: 0,
              right: 0,
              child: ClipPath(
                clipper: _WaveClipper(),
                child: Container(
                  height: 60,
                  color: Colors.white,
                ),
              ),
            ),

            // ── Logo + wordmark over the photo (top-centre) ───────────────
            Positioned(
              top: MediaQuery.of(context).padding.top + 24,
              left: 0,
              right: 0,
              child: _SplashLogo(),
            ),

            // ── Bottom sheet: feature icons + footer ──────────────────────
            Positioned(
              top: heroH + 8,
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                children: [
                  // 4 feature icons
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _FeatureRow(),
                  ),
                  const Spacer(),
                  // Deep navy footer
                  Container(
                    width: screenW,
                    color: const Color(0xFF0A2540),
                    padding: const EdgeInsets.symmetric(
                      vertical: 20,
                      horizontal: 24,
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.favorite_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                        const SizedBox(height: 8),
                        RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: GoogleFonts.sora(
                              fontSize: 15,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              height: 1.5,
                            ),
                            children: const [
                              TextSpan(text: 'Empowering '),
                              TextSpan(
                                text: 'every',
                                style: TextStyle(
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(text: ' mother.\nProtecting '),
                              TextSpan(
                                text: 'every',
                                style: TextStyle(
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(text: ' life.'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        const _LoadingBar(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wave path clipper — creates the smooth curved transition between the
/// full-bleed hero photo and the white feature-icon section below it.
class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, 30);
    path.quadraticBezierTo(size.width / 2, 0, size.width, 30);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_WaveClipper old) => false;
}

/// The brand mark at the top of the splash, overlaid on the hero photo.
/// Uses the real `logo.png` asset provided by the design team.
class _SplashLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Real logo image with a circular white backing so it pops over photo.
        Container(
          width: 100,
          height: 100,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(6),
          child: ClipOval(
            child: AppImage(
              src: AppImages.logo,
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: 12),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            children: [
              TextSpan(
                text: 'CareBridge',
                style: GoogleFonts.sora(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: const Color(0xFF0A2540),
                ),
              ),
              TextSpan(
                text: ' AI',
                style: GoogleFonts.sora(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // — MATERNAL CARE — divider
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 32, height: 1.5, color: const Color(0xFF0A2540)),
            const SizedBox(width: 8),
            Text(
              'MATERNAL CARE',
              style: GoogleFonts.sora(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 2.5,
                color: const Color(0xFF0A2540),
              ),
            ),
            const SizedBox(width: 8),
            Container(width: 32, height: 1.5, color: const Color(0xFF0A2540)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Smart Support. Healthier Mothers. Brighter Futures.',
          textAlign: TextAlign.center,
          style: GoogleFonts.sora(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            fontStyle: FontStyle.italic,
            color: const Color(0xFF0A2540),
          ),
        ),
      ],
    );
  }
}

/// Four feature icons matching the design mockup:
/// Works Offline · AI Guidance · Trusted Care · Community Focused
class _FeatureRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const pillColor = Color(0xFFE8F4FD);
    const iconColor = Color(0xFF0A6B9C);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _FeaturePill(
          icon: Icons.wifi_off_rounded,
          title: 'Works Offline',
          pillColor: pillColor,
          iconColor: iconColor,
        ),
        _FeaturePill(
          icon: Icons.psychology_outlined,
          title: 'AI Guidance',
          pillColor: pillColor,
          iconColor: iconColor,
        ),
        _FeaturePill(
          icon: Icons.verified_user_outlined,
          title: 'Trusted Care',
          pillColor: pillColor,
          iconColor: iconColor,
        ),
        _FeaturePill(
          icon: Icons.groups_2_outlined,
          title: 'Community\nFocused',
          pillColor: pillColor,
          iconColor: iconColor,
        ),
      ],
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({
    required this.icon,
    required this.title,
    required this.pillColor,
    required this.iconColor,
  });

  final IconData icon;
  final String title;
  final Color pillColor;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: pillColor,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 24, color: iconColor),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          textAlign: TextAlign.center,
          style: GoogleFonts.sora(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF0A2540),
            height: 1.3,
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
