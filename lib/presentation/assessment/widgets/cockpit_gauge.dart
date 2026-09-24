/// The executive cockpit gauge for experimental model output — a glowing
/// circular probability dial with its uncertainty band.
///
/// Honesty contract: this widget only draws the number it is given. Callers
/// decide whether output may be shown at all (see `AnalysisViewModel.
/// mayShowOutput`), and the caption states the research status of the
/// number. The dial colour uses the clinical red/amber/green purely as the
/// severity of a *research* figure, exactly as the app's other model-evidence
/// surfaces do.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/glass.dart';

class CockpitGauge extends StatelessWidget {
  const CockpitGauge({
    super.key,
    required this.value,
    this.label = 'Research output',
    this.interval95,
    this.conformalQ95,
    this.caption = '0–1 scale — experimental, not a diagnosis',
  });

  final double value;
  final String label;
  final ({double low, double high})? interval95;
  final double? conformalQ95;
  final String caption;

  Color get _color {
    if (value >= 0.7) return AppColors.triageRed;
    if (value >= 0.4) return AppColors.triageAmber;
    return AppColors.triageGreen;
  }

  String get _semantics {
    final pct = (value * 100).round();
    final band = interval95 == null
        ? ''
        : '; 95 percent band ${(interval95!.low * 100).round()} to '
            '${(interval95!.high * 100).round()} percent';
    final q95 = conformalQ95 == null
        ? ''
        : '; conformal 95th quantile ${conformalQ95!.toStringAsFixed(2)}';
    return '$label $pct percent$band$q95. $caption';
  }

  @override
  Widget build(BuildContext context) {
    final fx = VisualEffects.of(context);
    final sweep = fx.scale(const Duration(milliseconds: 900));
    final color = _color;
    final pct = (value * 100).round();
    return Semantics(
      label: _semantics,
      child: ExcludeSemantics(
        child: Row(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween<double>(end: value),
              duration: sweep,
              curve: AppMotion.curve,
              builder: (context, v, child) => CustomPaint(
                painter: _GlowArcPainter(fraction: v, color: color),
                size: const Size(92, 92),
                child: child,
              ),
              child: Center(
                child: Text(
                  '$pct%',
                  style: AppType.stat.copyWith(fontSize: 20, color: color),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.label.copyWith(
                      fontSize: 12,
                      color: AppColors.inkMuted,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (interval95 != null)
                        _BandChip(
                          text:
                              '95% band ${(interval95!.low * 100).round()}–'
                              '${(interval95!.high * 100).round()}',
                        ),
                      if (conformalQ95 != null)
                        _BandChip(
                          text: 'Q95 ${conformalQ95!.toStringAsFixed(2)}',
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    caption,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.inkFaint,
                      fontStyle: FontStyle.italic,
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

class _BandChip extends StatelessWidget {
  const _BandChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.surfaceTint,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: AppType.caption.copyWith(fontSize: 11),
    ),
  );
}

class _GlowArcPainter extends CustomPainter {
  const _GlowArcPainter({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 6;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = AppColors.surfaceTint;
    canvas.drawCircle(center, radius, track);

    final f = fraction.clamp(0.0, 1.0);
    if (f <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);
    // The glow pass: the same arc, blurred and faint — a lit edge rather
    // than a flat line.
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawArc(rect, -3.14159 / 2, 2 * 3.14159 * f, false, glow);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, -3.14159 / 2, 2 * 3.14159 * f, false, arc);
  }

  @override
  bool shouldRepaint(_GlowArcPainter old) =>
      old.fraction != fraction || old.color != color;
}
