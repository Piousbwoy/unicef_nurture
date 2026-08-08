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

import 'dart:math' as math;

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
import '../../presentation/shared/carebridge_loader.dart';
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
      // The _SplashScreen widget manages its own dwell duration before calling context.go().
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
/// Luxurious, deliberately-paced brand introduction that every CHO in the
/// Northern Region can feel proud opening. A Sahelian concentric-ring emblem
/// (evoking a Tamale compound wall and a clinical scanner together), a shimmer
/// sweep over the royal-blue gradient background, the "Built with Pride in
/// Northern Ghana" cultural tagline, and a 2.5s deliberate dwell so the
/// opening feels like an event rather than a flash. Tap to skip; session
/// readiness is waited on independently so the splash never rushes an
/// unprepared database.
class _SplashScreen extends ConsumerStatefulWidget {
  const _SplashScreen();

  @override
  ConsumerState<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<_SplashScreen>
    with TickerProviderStateMixin {
  bool _routed = false;

  late final AnimationController _reveal;
  late final AnimationController _shimmer;
  late final AnimationController _emblem;
  late final AnimationController _tagFade;

  @override
  void initState() {
    super.initState();
    _reveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
    _emblem = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    )..repeat();
    _tagFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (mounted) _tagFade.forward();
    });
    Future.microtask(_route);
  }

  @override
  void dispose() {
    _reveal.dispose();
    _shimmer.dispose();
    _emblem.dispose();
    _tagFade.dispose();
    super.dispose();
  }

  Future<void> _route() async {
    // Minimum luxurious dwell (7.5 seconds). Rushing this defeats the purpose — a splash
    // that vanishes before the eye can register it cuts short our diagnostic badges,
    // concentric Sahelian emblems, and cultural pride tagline.
    const minDwell = Duration(milliseconds: 7500);
    final min = Future<void>.delayed(minDwell);
    final ready = () async {
      while (ref.read(sessionProvider) is SessionLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }();
    await Future.wait([min, ready]);
    if (!mounted || _routed) return;
    _advance();
  }

  void _advance() {
    if (!mounted || _routed) return;
    _routed = true;
    _go();
  }

  Future<void> _go() async {
    final session = ref.read(sessionProvider);
    if (!mounted) return;
    if (session is SessionActive) {
      context.go(Routes.homeFor(session.user.role));
      return;
    }
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
    final paddingTop = MediaQuery.of(context).padding.top;
    final h = MediaQuery.of(context).size.height;
    final w = MediaQuery.of(context).size.width;

    return GestureDetector(
      onTap: _advance,
      behavior: HitTestBehavior.opaque,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // ── 1. Royal gradient canvas with Sahelian dawn atmosphere ─────
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _shimmer,
                builder: (_, _) => DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: const Alignment(1.2, 1.4),
                      colors: const [
                        Color(0xFFFFFFFF),
                        Color(0xFFF3F7FE),
                        Color(0xFFE2ECFC),
                        Color(0xFFCFDDFB),
                        Color(0xFF1240C4),
                        Color(0xFF0C2B73),
                      ],
                      stops: [
                        0.0,
                        0.22 + 0.04 * (0.5 + 0.5 * _shimmer.value),
                        0.42,
                        0.62,
                        0.88,
                        1.0,
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── 2. Sahelian geometric pattern overlay ───────────────────────
            // Soft repeating diamond lattice, inspired by Northern Ghana
            // woven smock patterns (fugu / batakari). Tinted in royal blue at
            // 4% opacity so it feels like luxury, not decoration.
            Positioned.fill(
              child: Opacity(
                opacity: 0.05,
                child: CustomPaint(
                  painter: const _SahelianLatticePainter(),
                ),
              ),
            ),

            // ── 3. Bottom atmospheric light spill ──────────────────────────
            Positioned(
              left: -w * 0.25,
              right: -w * 0.25,
              bottom: -h * 0.28,
              height: h * 0.7,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primaryGlow.withValues(alpha: 0.55),
                      AppColors.primaryDeep.withValues(alpha: 0.22),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.4, 1.0],
                  ),
                ),
              ),
            ),

            // ── 4. Ornate concentric emblem — Northern compound + scanner ──
            AnimatedBuilder(
              animation: _emblem,
              builder: (_, _) {
                return Positioned(
                  top: paddingTop + h * 0.10,
                  left: 0,
                  right: 0,
                  child: _AnimatedOrnateEmblem(
                    t: _emblem.value,
                    shimmerT: _shimmer.value,
                    revealT: _reveal.value,
                  ),
                );
              },
            ),

            // ── 5. Wordmark + subtitle stagger-reveal ──────────────────────
            Positioned(
              top: paddingTop + h * 0.47,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: _reveal,
                builder: (_, _) {
                  final t = Curves.easeOutCubic.transform(_reveal.value);
                  return Transform.translate(
                    offset: Offset(0, (1 - t) * 30),
                    child: Opacity(
                      opacity: t,
                      child: const _SplashWordmark(),
                    ),
                  );
                },
              ),
            ),

            // ── 6. "Built with Pride in Northern Ghana" cultural tagline ───
            Positioned(
              left: 0,
              right: 0,
              top: paddingTop + h * 0.615,
              child: AnimatedBuilder(
                animation: _tagFade,
                builder: (_, _) {
                  final t = Curves.easeOut.transform(_tagFade.value);
                  return Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, (1 - t) * 14),
                      child: const _NorthernPrideTagline(),
                    ),
                  );
                },
              ),
            ),

            // ── 7. Feature pill row (luxury, flat, white-on-blue tint) ─────
            Positioned(
              left: 24,
              right: 24,
              top: paddingTop + h * 0.70,
              child: AnimatedBuilder(
                animation: _reveal,
                builder: (_, _) {
                  final t = Curves.easeOutCubic
                      .transform(((_reveal.value - 0.25) / 0.75).clamp(0.0, 1.0));
                  return Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, (1 - t) * 20),
                      child: const _FeaturePillRow(),
                    ),
                  );
                },
              ),
            ),

            // ── 8. Footer: GHS audit badge + royal blue loader ─────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _SplashFooter(shimmerT: _shimmer.value),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sahelian diamond-lattice pattern painter.
///
/// Produces a lightweight, evenly-spaced lattice of rotated squares that
/// echoes the geometric motifs of Northern Ghanaian fugu / batakari smocks
/// and the painted walls of traditional compound homes. Rendered at a fixed
/// stroke width so the pattern reads crisp on every device density.
class _SahelianLatticePainter extends CustomPainter {
  const _SahelianLatticePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const step = 46.0;
    const size2 = 14.0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = const Color(0xFF0C2B73);
    for (double y = -step; y < size.height + step; y += step) {
      for (double x = -step; x < size.width + step; x += step) {
        final off = ((y / step).floor().isEven) ? step / 2 : 0.0;
        final cx = x + off;
        final cy = y;
        canvas.drawRect(
          Rect.fromCenter(center: Offset(cx, cy), width: size2, height: size2),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SahelianLatticePainter oldDelegate) => false;
}

/// The jewel of the splash: the 4-ring ceremonial ornate emblem.
///
/// Inspired by two simultaneous references the audience will recognise on a
/// subconscious level:
///   (1) the concentric mud-brick compound walls of a Northern Ghana home,
///       ring by ring, enclosing the family in safety — exactly what this app
///       does for a mother and her newborn;
///   (2) the rotating scanning rings of a clinical ultrasound or diagnostic
///       scanner, telling the health worker immediately that this tool is
///       trustworthy, serious, and clinical in origin.
///
/// Three rings rotate at different velocities; a shimmer sweep passes across
/// the central logo disc every 2.6 seconds; the whole thing blooms in scale
/// on open, then settles at rest with a gentle continuous breath pulse.
class _AnimatedOrnateEmblem extends StatelessWidget {
  const _AnimatedOrnateEmblem({
    required this.t,
    required this.shimmerT,
    required this.revealT,
  });

  final double t;
  final double shimmerT;
  final double revealT;

  @override
  Widget build(BuildContext context) {
    final breath = 1.0 + 0.018 * (0.5 + 0.5 * math.sin(t * 6.28318));
    final bloom = Curves.easeOutBack.transform(revealT.clamp(0.0, 1.0));
    final scale = (0.65 + 0.35 * bloom) * breath;

    return Center(
      child: Transform.scale(
        scale: scale,
        child: SizedBox(
          width: 224,
          height: 224,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // (4) Outermost halo ring — slow, wide, quiet.
              Transform.rotate(
                angle: t * math.pi * 0.3,
                child: Container(
                  width: 224,
                  height: 224,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFFFFFF).withValues(alpha: 0.38),
                      width: 1.4,
                    ),
                  ),
                ),
              ),
              // (3) Dotted ring, counter-rotating, Sahelian compound gate.
              Transform.rotate(
                angle: -t * math.pi * 0.6,
                child: CustomPaint(
                  size: const Size.square(192),
                  painter: const _DottedRingPainter(dots: 36),
                ),
              ),
              // (2) Sweep arc ring, royal brand color.
              Transform.rotate(
                angle: t * math.pi * 1.8,
                child: SizedBox(
                  width: 164,
                  height: 164,
                  child: CustomPaint(
                    painter: _ArcPainter(
                      strokeWidth: 3.0,
                      color: AppColors.canvas.withValues(alpha: 0.95),
                      sweep: 0.35,
                      soft: true,
                    ),
                  ),
                ),
              ),
              // (1) Inner counter-sweep, bright azure.
              Transform.rotate(
                angle: -t * math.pi * 2.6,
                child: SizedBox(
                  width: 140,
                  height: 140,
                  child: CustomPaint(
                    painter: _ArcPainter(
                      strokeWidth: 2.4,
                      color: AppColors.primaryGlow,
                      sweep: 0.55,
                      soft: true,
                    ),
                  ),
                ),
              ),
              // Central logo medallion: white, embossed, softly glowing.
              Container(
                width: 118,
                height: 118,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x3F1B56DB),
                      blurRadius: 48,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 22,
                      offset: Offset(0, 12),
                    ),
                  ],
                  border: Border.all(
                    color: const Color(0xFFCFDDFB),
                    width: 1.6,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: AppImage(src: AppImages.logo, fit: BoxFit.contain),
                    ),
                    // Diagonal shimmer sweep that crosses the logo once per
                    // _shimmer loop — the high-end flagship-product finish.
                    IgnorePointer(
                      child: ClipOval(
                        child: SizedBox(
                          width: 118,
                          height: 118,
                          child: AnimatedBuilder(
                            animation: AlwaysStoppedAnimation(shimmerT),
                            builder: (_, _) {
                              const w = 0.38;
                              final left = -0.2 + shimmerT * (1.0 + 2 * w);
                              return FractionallySizedBox(
                                alignment: Alignment(
                                  ((left + w / 2) - 0.5) * 2,
                                  0,
                                ),
                                widthFactor: w,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.white.withValues(alpha: 0.0),
                                        Colors.white.withValues(alpha: 0.55),
                                        Colors.white.withValues(alpha: 0.0),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints the dotted ring of the ornate emblem — a Sahelian compound gate.
class _DottedRingPainter extends CustomPainter {
  const _DottedRingPainter({required this.dots});
  final int dots;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFFFFEFE);
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.shortestSide / 2 - 4;
    for (var i = 0; i < dots; i++) {
      final angle = (i / dots) * math.pi * 2;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      final big = i % 6 == 0;
      canvas.drawCircle(Offset(x, y), big ? 2.3 : 1.15, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DottedRingPainter oldDelegate) =>
      dots != oldDelegate.dots;
}

/// A generic ring-arc painter shared by both the emblem and the loaders.
class _ArcPainter extends CustomPainter {
  _ArcPainter({
    required this.strokeWidth,
    required this.color,
    required this.sweep,
    this.soft = false,
  });

  final double strokeWidth;
  final Color color;
  final double sweep;
  final bool soft;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth
      ..color = color;
    if (soft) {
      paint.shader = SweepGradient(
        colors: [
          Colors.transparent,
          color,
          color.withValues(alpha: 0.3),
          Colors.transparent,
        ],
        stops: const [0.0, 0.15, 0.7, 1.0],
      ).createShader(rect);
    }
    canvas.drawArc(
      rect.deflate(strokeWidth / 2),
      -math.pi / 2,
      math.pi * 2 * sweep,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ArcPainter oldDelegate) =>
      strokeWidth != oldDelegate.strokeWidth ||
      color != oldDelegate.color ||
      sweep != oldDelegate.sweep ||
      soft != oldDelegate.soft;
}

/// Wordmark — "CareBridge AI" bold headline with tag strap below.
class _SplashWordmark extends StatelessWidget {
  const _SplashWordmark();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            children: [
              TextSpan(
                text: 'CareBridge',
                style: GoogleFonts.sora(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                  color: AppColors.ink,
                  height: 1.0,
                ),
              ),
              TextSpan(
                text: ' AI',
                style: GoogleFonts.sora(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                  foreground: Paint()
                    ..shader = const LinearGradient(
                      colors: [Color(0xFF1240C4), Color(0xFF3B76F6)],
                    ).createShader(const Rect.fromLTWH(0, 0, 120, 60)),
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.canvas.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: const Color(0xFFCFDDFB),
              width: 1.1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x181B56DB),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Text(
            'NURTURING CARE  ·  CLINICAL PROTOCOLS  ·  HYBRID OFFLINE',
            textAlign: TextAlign.center,
            style: GoogleFonts.sora(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
              color: AppColors.primaryDeep,
            ),
          ),
        ),
      ],
    );
  }
}

/// The cultural pride tagline. Sits between the wordmark and the feature row.
class _NorthernPrideTagline extends StatelessWidget {
  const _NorthernPrideTagline();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 28,
            height: 1.2,
            color: const Color(0xFFFFFFFF).withValues(alpha: 0.75),
          ),
          const SizedBox(width: 12),
          Icon(Icons.flag_circle_rounded, color: AppColors.canvas, size: 16),
          const SizedBox(width: 8),
          Text(
            'BUILT WITH PRIDE IN NORTHERN GHANA',
            style: GoogleFonts.sora(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.canvas,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.favorite_rounded, color: const Color(0xFFF87171), size: 16),
          const SizedBox(width: 12),
          Container(
            width: 28,
            height: 1.2,
            color: const Color(0xFFFFFFFF).withValues(alpha: 0.75),
          ),
        ],
      ),
    );
  }
}

/// Four compact, luxurious feature chips on a shared pill plate.
///
/// Replaces the older, visually busy, brightly-coloured `_FeatureCard` row
/// with a cleaner, quieter premium presentation. The old row read like a
/// pitch deck; the new row reads like a flagship banking app.
class _FeaturePillRow extends StatelessWidget {
  const _FeaturePillRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.canvas.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFCFDDFB),
          width: 1.0,
        ),
        boxShadow: const [AppShadows.soft],
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _FeaturePill(
            icon: Icons.wifi_off_rounded,
            label: 'Offline',
            accent: Color(0xFF059669),
          ),
          _FeaturePill(
            icon: Icons.psychology_rounded,
            label: 'AI Copilot',
            accent: Color(0xFF1240C4),
          ),
          _FeaturePill(
            icon: Icons.family_restroom_rounded,
            label: 'Nurturing',
            accent: Color(0xFFEA580C),
          ),
          _FeaturePill(
            icon: Icons.cloud_sync_rounded,
            label: 'Hybrid',
            accent: Color(0xFF0284C7),
          ),
        ],
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({
    required this.icon,
    required this.label,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.12),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            style: GoogleFonts.sora(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Footer: "GHS CLINICAL COMPLIANT · HYBRID ARCHITECTURE" with a live royal
/// blue circular lazy loader and a friendly rotating milestone line.
class _SplashFooter extends StatelessWidget {
  const _SplashFooter({required this.shimmerT});
  final double shimmerT;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 16 + bottom),
      decoration: BoxDecoration(
        color: const Color(0xFF081B37).withValues(alpha: 0.94),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 22,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                flex: 2,
                child: _StepText(),
              ),
              const SizedBox(width: 18),
              Transform.scale(
                scale: 0.9,
                child: CareBridgeLoader(
                  size: 42,
                  strokeWidth: 2.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.verified_rounded,
                color: AppColors.triageGreen,
                size: 17,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'GHS CLINICAL COMPLIANT  ·  HYBRID ARCHITECTURE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.sora(
                    fontSize: 10.5,
                    color: const Color(0xFF9DB0CA),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Tap anywhere to continue →',
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF7C91B0),
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Rotating milestone line — short, dignified, warm, localised to the region.
class _StepText extends StatefulWidget {
  const _StepText();

  @override
  State<_StepText> createState() => _StepTextState();
}

class _StepTextState extends State<_StepText> {
  int _i = 0;
  static const _steps = [
    'Waking the offline SQLite engine…',
    'Loading WHO & Ghana Health Service protocols…',
    'Preparing Dagbani & Hausa voice prompts…',
    'Handshaking the MariaDB hybrid outbox…',
    'Ready — welcome, community health worker.',
  ];

  @override
  void initState() {
    super.initState();
    _tick();
  }

  Future<void> _tick() async {
    for (var s = 0; s < _steps.length - 1; s++) {
      await Future<void>.delayed(const Duration(milliseconds: 1650));
      if (!mounted) return;
      setState(() => _i = s + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) {
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.35),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        );
      },
      child: Text(
        key: ValueKey<int>(_i),
        _steps[_i],
        maxLines: 2,
        style: GoogleFonts.manrope(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: const Color(0xFFF8FAFC),
          height: 1.35,
        ),
      ),
    );
  }
}

