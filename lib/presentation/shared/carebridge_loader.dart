import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';

/// A premium, circular, animated lazy-loading indicator that matches the
/// CareBridge AI splash language exactly.
///
/// Design language ("Clinical Luxe"):
///   * Concentric royal-blue rings — evokes both a Sahelian compound wall
///     (Northern Ghana architectural motif) and a clinical diagnostic scanner.
///   * One ring rotates clockwise; a narrower, brighter ring rotates
///     counter-clockwise at a faster cadence — gives the luxurious feeling of
///     precision machinery, not a generic spinner.
///   * Central royal-blue brand gradient disc with a faint white sheen that
///     sweeps across it.
///   * Optional `label` parameter displays a small line of Sora text beneath
///     the spinner so screen-level call sites can provide operational context
///     (e.g. "Saving household…", "Syncing to MariaDB Main Server…") without
///     reaching for a separate Text widget every time.
///
/// Drop-in replacement for every `CircularProgressIndicator()` currently in
/// the app. Zero API friction:
///
/// ```
/// loading: () => const Center(child: CareBridgeLoader())
/// ```
class CareBridgeLoader extends StatefulWidget {
  const CareBridgeLoader({
    super.key,
    this.size = 56,
    this.strokeWidth = 3.2,
    this.label,
    this.labelStyle,
  });

  final double size;
  final double strokeWidth;
  final String? label;
  final TextStyle? labelStyle;

  @override
  State<CareBridgeLoader> createState() => _CareBridgeLoaderState();
}

class _CareBridgeLoaderState extends State<CareBridgeLoader>
    with TickerProviderStateMixin {
  late final AnimationController _slow;
  late final AnimationController _fast;
  late final AnimationController _sweep;

  @override
  void initState() {
    super.initState();
    _slow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
    _fast = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _slow.dispose();
    _fast.dispose();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Outer static halo ring — quiet luxury, always present.
              Padding(
                padding: EdgeInsets.all(widget.strokeWidth * 0.35),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primaryLight,
                      width: widget.strokeWidth * 0.65,
                    ),
                  ),
                ),
              ),
              // Slow wide arc — the dignified outer rotation.
              AnimatedBuilder(
                animation: _slow,
                builder: (_, _) {
                  return Transform.rotate(
                    angle: _slow.value * math.pi * 2,
                    child: Padding(
                      padding: EdgeInsets.all(widget.strokeWidth * 0.25),
                      child: CustomPaint(
                        painter: _ArcPainter(
                          strokeWidth: widget.strokeWidth,
                          color: AppColors.primary.withValues(alpha: 0.85),
                          sweep: 0.55,
                          soft: true,
                        ),
                      ),
                    ),
                  );
                },
              ),
              // Fast narrow arc — the bright inner counter-rotation.
              AnimatedBuilder(
                animation: _fast,
                builder: (_, _) {
                  return Transform.rotate(
                    angle: -_fast.value * math.pi * 2,
                    child: Padding(
                      padding: EdgeInsets.all(widget.strokeWidth * 3.0),
                      child: CustomPaint(
                        painter: _ArcPainter(
                          strokeWidth: widget.strokeWidth * 0.75,
                          color: AppColors.primaryGlow,
                          sweep: 0.85,
                        ),
                      ),
                    ),
                  );
                },
              ),
              // Central disc — royal gradient brand mark, sweeping sheen.
              Center(
                child: SizedBox(
                  width: widget.size * 0.34,
                  height: widget.size * 0.34,
                  child: AnimatedBuilder(
                    animation: _sweep,
                    builder: (_, _) {
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: SweepGradient(
                            startAngle: 0,
                            endAngle: math.pi * 2,
                            transform: GradientRotation(_sweep.value * math.pi * 2),
                            colors: const [
                              Color(0xFF1240C4),
                              Color(0xFF3B76F6),
                              Color(0xFFFFFFFF),
                              Color(0xFF1240C4),
                            ],
                            stops: const [0.0, 0.45, 0.5, 1.0],
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x221B56DB),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        if (label != null && label.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            label,
            textAlign: TextAlign.center,
            style: widget.labelStyle ??
                GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.inkMuted,
                  letterSpacing: 0.2,
                ),
          ),
        ],
      ],
    );
  }
}

/// Paints a single open arc used by [CareBridgeLoader].
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
          color.withValues(alpha: 0.15),
          Colors.transparent,
        ],
        stops: const [0.0, 0.2, 0.75, 1.0],
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
