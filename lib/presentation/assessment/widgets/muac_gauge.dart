/// A semicircle MUAC gauge for the WHO/Ghana CMAM cutoffs.
///
/// The arc runs left (low, severe) → right (high, healthy) and is coloured
/// red → amber → green. A needle points to the measured value, the zone
/// banner below restates the clinical meaning in plain language, and the
/// whole thing updates live as the CHO types into the underlying
/// [TextEditingController]. The needle tweens between values so a small edit
/// is visible, not a jump.
///
/// Why a dedicated widget and not a stock slider: the wireframe's gauge is
/// the screening moment — the CHO's first read of the tape should be the
/// zone, not the number. The widget does the zone-by-colour read so the form
/// does not have to.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class MuacGauge extends StatefulWidget {
  const MuacGauge({super.key, required this.controller});

  final TextEditingController controller;

  @override
  State<MuacGauge> createState() => _MuacGaugeState();
}

class _MuacGaugeState extends State<MuacGauge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  Animatable<double>? _tween;
  double _needleValue = _min;

  /// The visible scale — 9 cm sits well below SAM, 16 cm well above adequate.
  /// Anything typed is clamped into this range so the needle never leaves the
  /// arc.
  static const double _min = 9.0;
  static const double _max = 16.0;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    )..addListener(_onTick);
    widget.controller.addListener(_onChanged);
    _onChanged();
  }

  @override
  void didUpdateWidget(covariant MuacGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
      _onChanged();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _anim.dispose();
    super.dispose();
  }

  void _onChanged() {
    final v = double.tryParse(widget.controller.text.trim());
    final target = (v ?? _min).clamp(_min, _max);
    _tween = Tween<double>(begin: _needleValue, end: target.toDouble());
    _anim
      ..stop()
      ..value = 0
      ..forward();
  }

  void _onTick() {
    final t = _tween;
    if (t == null) return;
    setState(() => _needleValue = t.transform(_anim.value));
  }

  MuacZone _zoneFor(double? v) {
    if (v == null) return MuacZone.empty;
    if (v < 11.5) return MuacZone.sam;
    if (v < 12.5) return MuacZone.mam;
    if (v < 13.5) return MuacZone.atRisk;
    return MuacZone.adequate;
  }

  @override
  Widget build(BuildContext context) {
    final v = double.tryParse(widget.controller.text.trim());
    final zone = _zoneFor(v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Spacer(),
            _Tag(label: zone.tag, fg: zone.fg, bg: zone.bg),
          ],
        ),
        const SizedBox(height: Gap.xs),
        AspectRatio(
          aspectRatio: 2.0,
          child: CustomPaint(
            painter: _MuacGaugePainter(
              needleValue: _needleValue,
              showNeedle: v != null,
            ),
          ),
        ),
        const SizedBox(height: Gap.sm),
        Center(
          child: v == null
              ? const Text(
                  'Enter MUAC to see the zone',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.inkMuted,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'MUAC ${v.toStringAsFixed(1)} cm',
                      style: AppType.title.copyWith(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        color: zone.fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'WHO cutoffs: SAM <11.5 · MAM <12.5 · At risk <13.5',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppColors.inkFaint,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: Gap.sm),
        _ZoneBanner(zone: zone),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.fg, required this.bg});

  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: fg.withValues(alpha: 0.35)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.flag_rounded, size: 12, color: fg),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: fg,
            letterSpacing: 0.4,
          ),
        ),
      ],
    ),
  );
}

class _ZoneBanner extends StatelessWidget {
  const _ZoneBanner({required this.zone});

  final MuacZone zone;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: Gap.md,
      vertical: Gap.sm,
    ),
    decoration: BoxDecoration(
      color: zone.bg,
      borderRadius: BorderRadius.circular(Gap.radiusSm),
      border: Border.all(color: zone.fg.withValues(alpha: 0.3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(zone.icon, size: 18, color: zone.fg),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                zone.banner,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: zone.fg,
                  letterSpacing: 0.2,
                  height: 1.25,
                ),
              ),
              if (zone.detail != null) ...[
                const SizedBox(height: 2),
                Text(
                  zone.detail!,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.ink,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

enum MuacZone {
  empty(
    tag: 'MUAC SCREENING',
    banner: 'No MUAC recorded',
    detail:
        'Type the MUAC in cm below. The needle and zone update as you type, '
        'so the number is checked twice — by the tape and by the colour.',
    icon: Icons.straighten_outlined,
    fg: AppColors.inkMuted,
    bg: AppColors.canvas,
  ),
  sam(
    tag: 'AT RISK ASSESSMENT',
    banner: 'RED ZONE — Severe Acute Malnutrition',
    detail:
        'Refer for therapeutic feeding. Oedema or appetite loss is a same-day '
        'referral regardless of what the tape says.',
    icon: Icons.warning_amber_rounded,
    fg: AppColors.triageRed,
    bg: AppColors.triageRedBg,
  ),
  mam(
    tag: 'AT RISK ASSESSMENT',
    banner: 'YELLOW ZONE — Moderate Acute Malnutrition',
    detail:
        'Enrol in supplementary feeding. Recheck in 2 weeks; if MUAC keeps '
        'falling or appetite is poor, refer.',
    icon: Icons.warning_amber_rounded,
    fg: AppColors.triageAmber,
    bg: AppColors.triageAmberBg,
  ),
  atRisk(
    tag: 'WATCH',
    banner: 'WATCH — Borderline nutrition',
    detail:
        'Counselling on feeding, deworming and Vitamin A. Recheck at the next '
        'visit — a child this close to MAM deserves a closer look.',
    icon: Icons.visibility_outlined,
    fg: AppColors.info,
    bg: AppColors.primaryLight,
  ),
  adequate(
    tag: 'ADEQUATE',
    banner: 'GREEN ZONE — Healthy MUAC',
    detail:
        'Continue routine counselling and immunisations. Recheck at the next '
        'scheduled visit.',
    icon: Icons.check_circle_rounded,
    fg: AppColors.triageGreen,
    bg: AppColors.triageGreenBg,
  );

  const MuacZone({
    required this.tag,
    required this.banner,
    required this.detail,
    required this.icon,
    required this.fg,
    required this.bg,
  });

  final String tag;
  final String banner;
  final String? detail;
  final IconData icon;
  final Color fg;
  final Color bg;
}

class _MuacGaugePainter extends CustomPainter {
  _MuacGaugePainter({
    required this.needleValue,
    required this.showNeedle,
  });

  final double needleValue;
  final bool showNeedle;

  static const double _min = 9.0;
  static const double _max = 16.0;
  static const double _sam = 11.5;
  static const double _mam = 12.5;
  static const double _atrisk = 13.5;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Arc geometry. The pivot sits near the bottom of the box and the arc
    // sweeps left → top → right (a Canvas angle of pi → 2*pi).
    final pad = 16.0;
    final cx = w / 2;
    final cy = h * 0.92;
    final radius = math.min(w / 2, cy) - pad;

    final arcRect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);

    // Track (light grey full semicircle) sits under the coloured arc.
    final track = Paint()
      ..color = AppColors.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, math.pi, math.pi, false, track);

    // Coloured gradient arc on top of the track.
    final gradient = SweepGradient(
      startAngle: math.pi,
      endAngle: 2 * math.pi,
      stops: const [0.0, 0.5, 1.0],
      colors: const [
        AppColors.triageRed,
        AppColors.triageAmber,
        AppColors.triageGreen,
      ],
    );
    final colored = Paint()
      ..shader = gradient.createShader(arcRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, math.pi, math.pi, false, colored);

    // Cutoff tick marks (longer and red for the SAM line, the one that
    // actually drives referrals).
    _drawTick(canvas, cx, cy, radius, _sam, 26, AppColors.triageRed);
    _drawTick(canvas, cx, cy, radius, _mam, 22, AppColors.triageAmber);
    _drawTick(canvas, cx, cy, radius, _atrisk, 22, AppColors.triageGreen);

    _drawTickLabel(canvas, cx, cy, radius, _sam, '11.5');
    _drawTickLabel(canvas, cx, cy, radius, _mam, '12.5');
    _drawTickLabel(canvas, cx, cy, radius, _atrisk, '13.5');

    // Needle, drawn only once a value is present.
    if (showNeedle) {
      final theta = _angleFor(needleValue);
      final cosT = math.cos(theta);
      final sinT = math.sin(theta);
      final tip = Offset(
        cx + (radius - 6) * cosT,
        cy + (radius - 6) * sinT,
      );
      final base = Offset(cx - 8 * cosT, cy - 8 * sinT);

      final needle = Paint()
        ..color = AppColors.ink
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(base, tip, needle);
    }

    // Pivot: dark dot with a thin white ring so the needle reads as fixed
    // against the canvas.
    final pivotFill = Paint()..color = AppColors.ink;
    canvas.drawCircle(Offset(cx, cy), 6, pivotFill);
    final pivotRing = Paint()
      ..color = AppColors.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(Offset(cx, cy), 6, pivotRing);
  }

  /// Normalised MUAC value → Canvas angle (radians). The arc is on the top
  /// of the box, so angle 0 maps to the right edge and pi to the left.
  double _angleFor(double v) {
    final t = ((v - _min) / (_max - _min)).clamp(0.0, 1.0);
    return math.pi + t * math.pi;
  }

  void _drawTick(
    Canvas canvas,
    double cx,
    double cy,
    double radius,
    double value,
    double length,
    Color color,
  ) {
    final theta = _angleFor(value);
    final cosT = math.cos(theta);
    final sinT = math.sin(theta);
    final outer = Offset(cx + radius * cosT, cy + radius * sinT);
    final inner = Offset(
      cx + (radius - length) * cosT,
      cy + (radius - length) * sinT,
    );
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(inner, outer, paint);
  }

  void _drawTickLabel(
    Canvas canvas,
    double cx,
    double cy,
    double radius,
    double value,
    String text,
  ) {
    final theta = _angleFor(value);
    final r = radius - 36;
    final x = cx + r * math.cos(theta);
    final y = cy + r * math.sin(theta);
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 10,
          color: AppColors.inkMuted,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _MuacGaugePainter old) =>
      old.needleValue != needleValue || old.showNeedle != showNeedle;
}
