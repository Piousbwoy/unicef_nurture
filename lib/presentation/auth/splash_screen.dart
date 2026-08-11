/// Splash Screen matching the CareBridge AI maternal care brand identity.
///
/// Features the signature Mother & Infant portrait framed by dynamic blue wave curves,
/// high-contrast diagnostic badges, and a deep royal blue Sahelian footer centered
/// around a pulsating heartbeat emblem.
///
/// The brand moment never auto-advances: it rests on screen until the health
/// worker taps it, so nobody is rushed past the logo on a slow day in the field.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/providers.dart';
import '../../core/auth/session.dart';
import '../../core/router/app_router.dart';
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
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _route() async {
    // The splash is tap-to-continue; this is only ever called from the tap
    // gesture. Session readiness is awaited here so a very eager tap on a
    // cold start never routes against a database that is still opening.
    while (ref.read(sessionProvider) is SessionLoading) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
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
      onTap: _route,
      behavior: HitTestBehavior.opaque,
      child: Scaffold(
        backgroundColor: const Color(0xFFE6F2FF), // Soft baby-blue tint behind features
        body: Column(
          children: [
            // ── 1. Header Zone: Logo & Typography ────────────────────────────
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(20, topPadding + 24, 20, 14),
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
                    height: 108,
                    width: 122,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                      builder: (context, t, child) => Opacity(
                        opacity: t,
                        child: Transform.scale(
                          scale: 0.92 + 0.08 * t,
                          child: child,
                        ),
                      ),
                      // Raw Image.asset, not AppImage: the brand mark is
                      // transparent and must float on the header gradient,
                      // never on a placeholder tint.
                      child: Image.asset(
                        AppImages.logo,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'CareBridge',
                          style: GoogleFonts.sora(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                            color: const Color(0xFF0C41AC),
                            height: 1.1,
                          ),
                        ),
                        TextSpan(
                          text: ' AI',
                          style: GoogleFonts.sora(
                            fontSize: 32,
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
                  Transform(
                    // The bundled font set ships no italic cut, so the
                    // tagline gets a hand-set oblique instead.
                    transform: Matrix4.skewX(-0.18),
                    alignment: Alignment.center,
                    child: Text(
                      'Smart Support. Healthier Mothers. Brighter Futures.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.manrope(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF3B5E94),
                      ),
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
                  // Clipped mother & child photo with rural clinic background
                  ClipPath(
                    clipper: const _HeroWaveClipper(bottomOffset: 6.0),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const AppImage(
                          src: AppImages.motherChild,
                          fit: BoxFit.cover,
                          placeholderIcon: Icons.family_restroom_rounded,
                        ),
                        // Soft sky scrim so the header's pale gradient melts
                        // seamlessly into the photograph's horizon.
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: 64,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  const Color(0xFFEBF5FF),
                                  const Color(
                                    0xFFEBF5FF,
                                  ).withValues(alpha: 0),
                                ],
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

            // ── 3. Feature Badges Row ───────────────────────────────────────
            Container(
              color: const Color(0xFFE6F2FF),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  const Expanded(
                    child: _FeatureBadge.custom(
                      painter: _OfflineIconPainter(),
                      label: 'Works Offline',
                    ),
                  ),
                  _buildDivider(),
                  const Expanded(
                    child: _FeatureBadge.custom(
                      painter: _AiGuidanceIconPainter(),
                      label: 'AI Guidance',
                    ),
                  ),
                  _buildDivider(),
                  const Expanded(
                    child: _FeatureBadge.custom(
                      painter: _TrustedCareIconPainter(),
                      label: 'Trusted Care',
                    ),
                  ),
                  _buildDivider(),
                  const Expanded(
                    child: _FeatureBadge.custom(
                      painter: _CommunityIconPainter(),
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
                  color: Color(0xFF11408F),
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
                      padding: EdgeInsets.fromLTRB(20, 64, 20, math.max(20, bottomPadding + 12)),
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
                            style: GoogleFonts.manrope(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.96),
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Protecting every life.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.manrope(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.96),
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 14),
                          AnimatedBuilder(
                            animation: _pulse,
                            builder: (context, child) => Opacity(
                              opacity: 0.45 + 0.25 * math.sin(_pulse.value * math.pi),
                              child: child,
                            ),
                            child: Text(
                              'TAP ANYWHERE TO CONTINUE',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.manrope(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.6,
                                color: Colors.white,
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
  const _FeatureBadge.custom({
    required this.painter,
    required this.label,
  });

  final CustomPainter painter;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 34,
          height: 34,
          child: CustomPaint(painter: painter),
        ),
        const SizedBox(height: 7),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.manrope(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1B4FA8),
            height: 1.25,
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
    final dip = w * 0.18;
    final path = Path()
      ..lineTo(0, h - dip)
      ..quadraticBezierTo(w * 0.5, h + dip, w, h - dip)
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
      ..moveTo(0, 0)
      ..quadraticBezierTo(w * 0.5, w * 0.24, w, 0)
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
    // Rows of alternating triangle motifs — the woven zigzag of a Sahelian
    // smock, kept faint so the footer reads as fabric, not wallpaper.
    const rowH = 26.0;
    const triW = 30.0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = const Color(0xFFFFFFFF);
    var row = 0;
    for (double y = -rowH; y < size.height + rowH; y += rowH) {
      final up = row.isEven;
      for (double x = -triW; x < size.width + triW; x += triW) {
        final path = Path();
        if (up) {
          path
            ..moveTo(x, y + rowH * 0.8)
            ..lineTo(x + triW / 2, y + rowH * 0.2)
            ..lineTo(x + triW, y + rowH * 0.8)
            ..close();
        } else {
          path
            ..moveTo(x, y + rowH * 0.2)
            ..lineTo(x + triW / 2, y + rowH * 0.8)
            ..lineTo(x + triW, y + rowH * 0.2)
            ..close();
        }
        canvas.drawPath(path, paint);
      }
      row++;
    }
  }

  @override
  bool shouldRepaint(covariant _SahelianLatticePainter oldDelegate) => false;
}

/// Circled Wi-Fi with a diagonal slash — Works Offline icon.
class _OfflineIconPainter extends CustomPainter {
  const _OfflineIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final c = Offset(size.width / 2, size.height / 2);
    final stroke = Paint()
      ..color = const Color(0xFF1B4FA8)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Enclosing circle
    canvas.drawCircle(c, s * 0.44, stroke..strokeWidth = s * 0.075);

    // Wi-Fi arcs opening downward, anchored below centre
    final arcCenter = Offset(c.dx, c.dy + s * 0.16);
    for (final r in [0.13, 0.23, 0.33]) {
      canvas.drawPath(
        Path()
          ..arcTo(
            Rect.fromCircle(center: arcCenter, radius: s * r),
            -2.20,
            1.25,
            false,
          ),
        stroke..strokeWidth = s * 0.07,
      );
    }

    // Antenna dot
    canvas.drawCircle(
      Offset(c.dx, c.dy + s * 0.20),
      s * 0.05,
      Paint()..color = const Color(0xFF1B4FA8),
    );

    // Diagonal slash
    canvas.drawLine(
      Offset(c.dx - s * 0.30, c.dy - s * 0.30),
      Offset(c.dx + s * 0.30, c.dy + s * 0.30),
      stroke..strokeWidth = s * 0.09,
    );
  }

  @override
  bool shouldRepaint(covariant _OfflineIconPainter oldDelegate) => false;
}

/// Solid head silhouette with a white brain-circuit — AI Guidance icon.
class _AiGuidanceIconPainter extends CustomPainter {
  const _AiGuidanceIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final headPath = Path()
      ..moveTo(w * 0.52, h * 0.04)
      ..cubicTo(w * 0.30, h * 0.04, w * 0.17, h * 0.20, w * 0.17, h * 0.42)
      ..cubicTo(w * 0.17, h * 0.54, w * 0.21, h * 0.63, w * 0.27, h * 0.70)
      ..lineTo(w * 0.27, h * 0.94)
      ..lineTo(w * 0.62, h * 0.94)
      ..lineTo(w * 0.62, h * 0.78)
      ..cubicTo(w * 0.72, h * 0.70, w * 0.79, h * 0.58, w * 0.79, h * 0.42)
      ..cubicTo(w * 0.79, h * 0.20, w * 0.70, h * 0.04, w * 0.52, h * 0.04)
      ..close();

    canvas.drawPath(headPath, Paint()..color = const Color(0xFF1B4FA8));

    // White circuit: nodes + wires inside the head
    final wire = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.05
      ..strokeCap = StrokeCap.round;
    final node = Paint()..color = const Color(0xFFFFFFFF);

    final n1 = Offset(w * 0.40, h * 0.34);
    final n2 = Offset(w * 0.58, h * 0.30);
    final n3 = Offset(w * 0.50, h * 0.48);
    final n4 = Offset(w * 0.36, h * 0.52);

    final wires = Path()
      ..moveTo(n1.dx, n1.dy)
      ..lineTo(n3.dx, n3.dy)
      ..moveTo(n2.dx, n2.dy)
      ..lineTo(n3.dx, n3.dy)
      ..moveTo(n1.dx, n1.dy)
      ..lineTo(n4.dx, n4.dy);
    canvas.drawPath(wires, wire);

    for (final n in [n1, n2, n3, n4]) {
      canvas.drawCircle(n, w * 0.045, node);
    }
  }

  @override
  bool shouldRepaint(covariant _AiGuidanceIconPainter oldDelegate) => false;
}

/// Two-tone quadrant shield — Trusted Care icon.
class _TrustedCareIconPainter extends CustomPainter {
  const _TrustedCareIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final shieldPath = Path()
      ..moveTo(w * 0.5, h * 0.02)
      ..lineTo(w * 0.90, h * 0.16)
      ..lineTo(w * 0.90, h * 0.52)
      ..cubicTo(w * 0.90, h * 0.74, w * 0.72, h * 0.90, w * 0.50, h * 0.98)
      ..cubicTo(w * 0.28, h * 0.90, w * 0.10, h * 0.74, w * 0.10, h * 0.52)
      ..lineTo(w * 0.10, h * 0.16)
      ..close();

    // Light base fill
    canvas.drawPath(shieldPath, Paint()..color = const Color(0xFFBBD7F6));

    // Dark quadrants (top-left, bottom-right), clipped to the shield
    canvas.save();
    canvas.clipPath(shieldPath);
    final dark = Paint()..color = const Color(0xFF1B4FA8);
    canvas.drawRect(Rect.fromLTRB(w * 0.10, h * 0.02, w * 0.50, h * 0.50), dark);
    canvas.drawRect(Rect.fromLTRB(w * 0.50, h * 0.50, w * 0.90, h * 0.98), dark);
    canvas.restore();

    // Outline
    canvas.drawPath(
      shieldPath,
      Paint()
        ..color = const Color(0xFF1B4FA8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.06
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _TrustedCareIconPainter oldDelegate) => false;
}

/// Three solid figures — Community Focused icon.
class _CommunityIconPainter extends CustomPainter {
  const _CommunityIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fill = Paint()..color = const Color(0xFF1B4FA8);

    // Side figures first (behind)
    for (final side in [-1.0, 1.0]) {
      final cx = w * 0.5 + side * w * 0.28;
      canvas.drawCircle(Offset(cx, h * 0.30), h * 0.10, fill);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(cx - w * 0.12, h * 0.46, cx + w * 0.12, h * 0.76),
          topLeft: const Radius.circular(6),
          topRight: const Radius.circular(6),
        ),
        fill,
      );
    }

    // Centre figure in front, slightly larger
    canvas.drawCircle(Offset(w * 0.5, h * 0.22), h * 0.12, fill);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTRB(w * 0.34, h * 0.42, w * 0.66, h * 0.86),
        topLeft: const Radius.circular(7),
        topRight: const Radius.circular(7),
      ),
      fill,
    );
  }

  @override
  bool shouldRepaint(covariant _CommunityIconPainter oldDelegate) => false;
}
