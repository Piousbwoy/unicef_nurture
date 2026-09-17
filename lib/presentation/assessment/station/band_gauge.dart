/// A horizontal band gauge: the visible range as a track, band zones as
/// faint tints, and a marker that slides to the value. Triage colour is
/// applied to the marker and the note only — the zones are tints, so the
/// gauge never reads as a red/amber/green decoration when empty.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/glass.dart';
import 'vital_spec.dart';

class BandGauge extends StatelessWidget {
  const BandGauge({
    super.key,
    required this.spec,
    required this.ctx,
    required this.value,
  });

  final VitalSpec spec;
  final VitalContext ctx;

  /// Parsed value, or null while the readout is empty.
  final double? value;

  @override
  Widget build(BuildContext context) {
    final bands = spec.bands(ctx);
    final v = value;
    final band = v == null ? null : spec.bandFor(v, ctx);
    final fx = VisualEffects.of(context);
    final target = v == null
        ? 0.0
        : ((v - spec.gaugeMin) / (spec.gaugeMax - spec.gaugeMin)).clamp(
            0.0,
            1.0,
          );
    final markerColour = band?.tone.fg ?? AppColors.primary;
    final implausible = v != null && spec.implausible(v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 28,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: target),
            duration: fx.scale(const Duration(milliseconds: 380)),
            curve: AppMotion.curve,
            builder: (context, t, _) => CustomPaint(
              painter: _GaugePainter(
                bands: bands,
                min: spec.gaugeMin,
                max: spec.gaugeMax,
                t: v == null ? null : t,
                markerColour: markerColour,
              ),
            ),
          ),
        ),
        const SizedBox(height: Gap.xs),
        Row(
          children: [
            Text(
              spec.format(spec.gaugeMin),
              style: AppType.caption.copyWith(fontSize: 11),
            ),
            const Spacer(),
            Text(
              spec.format(spec.gaugeMax),
              style: AppType.caption.copyWith(fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: Gap.sm),
        AnimatedSwitcher(
          duration: fx.scale(AppMotion.fast),
          child: _note(v, band, implausible),
        ),
      ],
    );
  }

  Widget _note(double? v, VitalBand? band, bool implausible) {
    if (v == null) {
      return Text(
        _hint(),
        key: const ValueKey('hint'),
        style: AppType.caption.copyWith(height: 1.45),
      );
    }
    if (implausible) {
      final p = spec.plausible!;
      return Row(
        key: const ValueKey('implausible'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.help_outline_rounded,
            size: 16,
            color: AppColors.inkMuted,
          ),
          const SizedBox(width: Gap.xs),
          Expanded(
            child: Text(
              'Outside the plausible range (${p.min.toStringAsFixed(0)}–'
              '${p.max.toStringAsFixed(0)} ${p.unit}). ${p.advice}',
              style: AppType.caption.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
          ),
        ],
      );
    }
    if (band == null) {
      return Text(
        'Recorded. No range band for this measurement.',
        key: const ValueKey('none'),
        style: AppType.caption.copyWith(height: 1.45),
      );
    }
    return Row(
      key: ValueKey(band.note),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(_toneIcon(band.tone), size: 16, color: band.tone.fg),
        const SizedBox(width: Gap.xs),
        Expanded(
          child: Text(
            band.note,
            style: AppType.caption.copyWith(
              color: band.tone.fg,
              fontWeight: FontWeight.w700,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }

  String _hint() => spec.bands(ctx).isEmpty
      ? 'Enter the reading. Checked for plausibility only.'
      : 'Enter the reading to see where it sits.';

  static IconData _toneIcon(VitalTone t) => switch (t) {
    VitalTone.normal => Icons.check_circle_outline_rounded,
    VitalTone.watch => Icons.visibility_outlined,
    VitalTone.danger => Icons.priority_high_rounded,
  };
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({
    required this.bands,
    required this.min,
    required this.max,
    required this.t,
    required this.markerColour,
  });

  final List<VitalBand> bands;
  final double min;
  final double max;

  /// 0–1 marker position, or null for no marker.
  final double? t;
  final Color markerColour;

  double _x(double v, double w) =>
      ((v - min) / (max - min)).clamp(0.0, 1.0) * w;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    const trackH = 10.0;
    final top = (size.height - trackH) / 2;
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, top, w, trackH),
      const Radius.circular(trackH / 2),
    );
    canvas.drawRRect(track, Paint()..color = AppColors.line);

    // Zone tints, clipped to the rounded track.
    canvas.save();
    canvas.clipRRect(track);
    for (final b in bands) {
      final x0 = _x(b.min ?? min, w);
      final x1 = _x(b.max ?? max, w);
      if (x1 <= x0) continue;
      canvas.drawRect(
        Rect.fromLTWH(x0, top, x1 - x0, trackH),
        Paint()..color = b.tone.fg.withValues(alpha: 0.18),
      );
    }
    canvas.restore();

    final pos = t;
    if (pos == null) return;
    final cx = pos * w;
    final cy = size.height / 2;
    canvas.drawCircle(Offset(cx, cy), 11, Paint()..color = Colors.white);
    canvas.drawCircle(
      Offset(cx, cy),
      11,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.lineStrong,
    );
    canvas.drawCircle(Offset(cx, cy), 6.5, Paint()..color = markerColour);
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.t != t ||
      old.markerColour != markerColour ||
      old.bands != bands ||
      old.min != min ||
      old.max != max;
}
