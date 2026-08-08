/// Splash Screen matching the CareBridge AI maternal care brand identity.
///
/// Features the signature Mother & Infant portrait framed by dynamic blue wave curves,
/// high-contrast diagnostic badges, and a deep royal blue Sahelian footer centered
/// around a pulsating heartbeat emblem.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/providers.dart';
import '../../core/auth/session.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/preferences_store.dart';
import '../shared/app_image.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  bool _routed = false;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    Future.microtask(_route);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _route() async {
    // 2.0s dwell time gives users time to register the brand and slogans
    // while remaining fast, responsive, and compatible with widget test timers.
    const minDwell = Duration(milliseconds: 2000);
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
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return GestureDetector(
      onTap: _advance,
      behavior: HitTestBehavior.opaque,
      child: Scaffold(
        backgroundColor: const Color(0xFFE6F2FF), // Soft baby-blue tint behind features
        body: Column(
          children: [
            // ── 1. Header Zone: Logo & Typography ────────────────────────────
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(20, topPadding + 10, 20, 10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFFFFFFF),
                    Color(0xFFF6FAFF),
                    Color(0xFFEBF5FF),
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 72,
                    width: 72,
                    child: AppImage(
                      src: AppImages.logo,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 6),
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'CareBridge',
                          style: GoogleFonts.sora(
                            fontSize: 31,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                            color: const Color(0xFF0C41AC),
                            height: 1.1,
                          ),
                        ),
                        TextSpan(
                          text: ' AI',
                          style: GoogleFonts.sora(
                            fontSize: 31,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                            color: const Color(0xFF148CF5),
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 24,
                        height: 1.4,
                        color: const Color(0xFF2B73DF),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'MATERNAL CARE',
                        style: GoogleFonts.sora(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0C41AC),
                          letterSpacing: 2.6,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 24,
                        height: 1.4,
                        color: const Color(0xFF2B73DF),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'Smart Support. Healthier Mothers. Brighter Futures.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.sora(
                      fontSize: 12.5,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF3B5E94),
                    ),
                  ),
                ],
              ),
            ),

            // ── 2. Hero Portrait with Sweeping Wave Border ──────────────────
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Bottom royal blue curved rim
                  ClipPath(
                    clipper: const _HeroWaveClipper(bottomOffset: 0.0),
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Color(0xFF0949C6),
                            Color(0xFF0078FA),
                            Color(0xFF0E56DE),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Clipped mother & child photo just above the rim
                  ClipPath(
                    clipper: const _HeroWaveClipper(bottomOffset: 10.0),
                    child: const AppImage(
                      src: AppImages.motherChild,
                      fit: BoxFit.cover,
                      placeholderIcon: Icons.family_restroom_rounded,
                    ),
                  ),
                ],
              ),
            ),

            // ── 3. Feature Badges Row ───────────────────────────────────────
            Container(
              color: const Color(0xFFE6F2FF),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  const Expanded(
                    child: _FeatureBadge(
                      icon: Icons.wifi_off_rounded,
                      label: 'Works Offline',
                    ),
                  ),
                  _buildDivider(),
                  const Expanded(
                    child: _FeatureBadge(
                      icon: Icons.psychology_rounded,
                      label: 'AI Guidance',
                    ),
                  ),
                  _buildDivider(),
                  const Expanded(
                    child: _FeatureBadge(
                      icon: Icons.shield_rounded,
                      label: 'Trusted Care',
                    ),
                  ),
                  _buildDivider(),
                  const Expanded(
                    child: _FeatureBadge(
                      icon: Icons.groups_rounded,
                      label: 'Community\nFocused',
                    ),
                  ),
                ],
              ),
            ),

            // ── 4. Deep Royal Blue Footer & Heartbeat Emblem ────────────────
            ClipPath(
              clipper: const _BottomWaveClipper(),
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF072C7A),
                      Color(0xFF041C52),
                      Color(0xFF02123C),
                    ],
                  ),
                ),
                child: Stack(
                  children: [
                    // Subtle Sahelian traditional smock geometric pattern overlay
                    Positioned.fill(
                      child: Opacity(
                        opacity: 0.06,
                        child: CustomPaint(
                          painter: const _SahelianLatticePainter(),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(20, 36, 20, math.max(16, bottomPadding + 10)),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Center(
                            child: AnimatedBuilder(
                              animation: _pulse,
                              builder: (context, child) {
                                final scale = 1.0 + 0.08 * math.sin(_pulse.value * math.pi);
                                return Transform.scale(
                                  scale: scale,
                                  child: child,
                                );
                              },
                              child: const SizedBox(
                                width: 38,
                                height: 34,
                                child: CustomPaint(
                                  painter: _HeartbeatIconPainter(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Empowering every mother.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.sora(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.96),
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Protecting every life.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.sora(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.96),
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 38,
      color: const Color(0xFFABC5EA),
    );
  }
}

class _FeatureBadge extends StatelessWidget {
  const _FeatureBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFD7EAFF),
            border: Border.all(
              color: const Color(0xFF1460DF),
              width: 1.5,
            ),
          ),
          child: Icon(
            icon,
            color: const Color(0xFF0B4CC9),
            size: 22,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.sora(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF0C3D8F),
            height: 1.15,
          ),
        ),
      ],
    );
  }
}

class _HeroWaveClipper extends CustomClipper<Path> {
  const _HeroWaveClipper({this.bottomOffset = 0.0});
  final double bottomOffset;

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height - bottomOffset;
    final path = Path()
      ..lineTo(0, h - 35)
      ..quadraticBezierTo(w * 0.5, h + 22, w, h - 35)
      ..lineTo(w, 0)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant _HeroWaveClipper oldDelegate) =>
      bottomOffset != oldDelegate.bottomOffset;
}

class _BottomWaveClipper extends CustomClipper<Path> {
  const _BottomWaveClipper();

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(0, 24)
      ..quadraticBezierTo(w * 0.5, -16, w, 24)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant _BottomWaveClipper oldDelegate) => false;
}

class _HeartbeatIconPainter extends CustomPainter {
  const _HeartbeatIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    // Outer stylized heart outline
    final heartPath = Path()
      ..moveTo(w * 0.5, h * 0.28)
      ..cubicTo(w * 0.28, -0.02, w * 0.0, h * 0.2, w * 0.05, h * 0.5)
      ..cubicTo(w * 0.12, h * 0.72, w * 0.35, h * 0.88, w * 0.5, h * 0.95)
      ..cubicTo(w * 0.65, h * 0.88, w * 0.88, h * 0.72, w * 0.95, h * 0.5)
      ..cubicTo(w * 1.0, h * 0.2, w * 0.72, -0.02, w * 0.5, h * 0.28);

    canvas.drawPath(heartPath, paint);

    // Inner heartbeat ECG spike
    final ecgPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final ecgPath = Path()
      ..moveTo(w * 0.18, h * 0.5)
      ..lineTo(w * 0.34, h * 0.5)
      ..lineTo(w * 0.42, h * 0.3)
      ..lineTo(w * 0.54, h * 0.72)
      ..lineTo(w * 0.63, h * 0.38)
      ..lineTo(w * 0.70, h * 0.5)
      ..lineTo(w * 0.82, h * 0.5);

    canvas.drawPath(ecgPath, ecgPaint);
  }

  @override
  bool shouldRepaint(covariant _HeartbeatIconPainter oldDelegate) => false;
}

class _SahelianLatticePainter extends CustomPainter {
  const _SahelianLatticePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const step = 44.0;
    const size2 = 14.0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = const Color(0xFFFFFFFF);
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
