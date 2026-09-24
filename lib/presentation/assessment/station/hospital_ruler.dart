/// A hospital-monitor scale for one vital.
///
/// The old passive gauge grew a hand: drag the knob to the rough value
/// (snapped to the spec's step), read the graduations like a ward chart,
/// and the interpretation line names the zone the reading sits in. Tap the
/// scale to jump, fine-tune with the − / + jog buttons beside it. Display
/// guidance only — the engines still own every verdict.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/glass.dart';
import 'vital_spec.dart';

class HospitalRuler extends StatefulWidget {
  const HospitalRuler({
    super.key,
    required this.spec,
    required this.ctx,
    required this.value,
    required this.onChanged,
  });

  final VitalSpec spec;
  final VitalContext ctx;

  /// Current reading; null while the readout is empty (no knob yet).
  final double? value;

  /// Called with a snapped value on tap, drag and accessibility nudge.
  final ValueChanged<double> onChanged;

  @override
  State<HospitalRuler> createState() => _HospitalRulerState();
}

class _HospitalRulerState extends State<HospitalRuler> {
  /// True while a finger is down on the scale — the knob tracks the finger
  /// instead of tweening to the committed (snapped) value.
  bool _dragging = false;

  /// Raw 0–1 knob position during a drag.
  double? _dragT;

  /// Last zone tone seen, so a zone crossing clicks once.
  VitalTone? _lastTone;

  /// Track width from the last layout pass.
  double _width = 0;

  double _t(double v) => ((v - widget.spec.gaugeMin) /
        (widget.spec.gaugeMax - widget.spec.gaugeMin))
      .clamp(0.0, 1.0);

  double _valueAt(double t) {
    final spec = widget.spec;
    final raw = spec.gaugeMin + t * (spec.gaugeMax - spec.gaugeMin);
    final snapped = (raw / spec.step).roundToDouble() * spec.step;
    return snapped.clamp(spec.gaugeMin, spec.gaugeMax).toDouble();
  }

  void _commit(double t) {
    final v = _valueAt(t);
    final tone = widget.spec.bandFor(v, widget.ctx)?.tone;
    if (_lastTone != null && tone != null && tone != _lastTone) {
      HapticFeedback.selectionClick();
    }
    _lastTone = tone;
    if (v != widget.value) widget.onChanged(v);
  }

  /// Accessibility nudge: one step up or down; from empty, lands at the
  /// nearer end of the scale.
  void _nudge(int direction) {
    final spec = widget.spec;
    final v = widget.value ??
        (direction < 0 ? spec.gaugeMax : spec.gaugeMin);
    final next = (v + direction * spec.step)
        .clamp(spec.gaugeMin, spec.gaugeMax);
    if (next != v) _commit(_t(next));
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final fx = VisualEffects.of(context);
    final v = widget.value;
    final band = v == null ? null : spec.bandFor(v, widget.ctx);
    final implausible = v != null && spec.implausible(v);
    final target = _dragging ? _dragT! : (v == null ? 0.0 : _t(v));
    final markerColour = band?.tone.fg ?? AppColors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          slider: true,
          label: '${spec.label} scale',
          value: v == null ? 'No reading' : spec.format(v),
          increasedValue: spec.format(
            ((v ?? spec.gaugeMin) + spec.step).clamp(
              spec.gaugeMin,
              spec.gaugeMax,
            ),
          ),
          decreasedValue: spec.format(
            ((v ?? spec.gaugeMax) - spec.step).clamp(
              spec.gaugeMin,
              spec.gaugeMax,
            ),
          ),
          onIncrease: () => _nudge(1),
          onDecrease: () => _nudge(-1),
          child: SizedBox(
            height: 64,
            child: LayoutBuilder(
              builder: (context, c) {
                _width = c.maxWidth;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _commit(
                    (d.localPosition.dx / _width).clamp(0.0, 1.0),
                  ),
                  onHorizontalDragStart: (d) {
                    final t = (d.localPosition.dx / _width).clamp(0.0, 1.0);
                    setState(() {
                      _dragging = true;
                      _dragT = t;
                    });
                    _commit(t);
                  },
                  onHorizontalDragUpdate: (d) {
                    final t = (d.localPosition.dx / _width).clamp(0.0, 1.0);
                    setState(() => _dragT = t);
                    _commit(t);
                  },
                  onHorizontalDragEnd: (_) => setState(() {
                    _dragging = false;
                    _dragT = null;
                  }),
                  onHorizontalDragCancel: () => setState(() {
                    _dragging = false;
                    _dragT = null;
                  }),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: target),
                    duration: _dragging
                        ? Duration.zero
                        : fx.scale(const Duration(milliseconds: 380)),
                    curve: AppMotion.curve,
                    builder: (context, t, _) => CustomPaint(
                      size: const Size(double.infinity, 64),
                      painter: _RulerPainter(
                        spec: spec,
                        bands: spec.bands(widget.ctx),
                        t: (v == null && !_dragging) ? null : t,
                        markerColour: markerColour,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
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
      final p = widget.spec.plausible!;
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

  String _hint() => widget.spec.bands(widget.ctx).isEmpty
      ? 'Drag the knob or tap the scale. Checked for plausibility only.'
      : 'Drag the knob or tap the scale to set the reading.';

  static IconData _toneIcon(VitalTone t) => switch (t) {
    VitalTone.normal => Icons.check_circle_outline_rounded,
    VitalTone.watch => Icons.visibility_outlined,
    VitalTone.danger => Icons.priority_high_rounded,
  };
}

enum _LabelAlign { left, centre, right }

class _RulerPainter extends CustomPainter {
  const _RulerPainter({
    required this.spec,
    required this.bands,
    required this.t,
    required this.markerColour,
  });

  final VitalSpec spec;
  final List<VitalBand> bands;

  /// 0–1 knob position, or null for no knob.
  final double? t;
  final Color markerColour;

  static const _trackH = 12.0;
  static const _centreY = 30.0;

  /// Round steps so the numbers read like a ward chart (4, 6, 8 …).
  static const _nice = [
    0.1, 0.2, 0.25, 0.5, 1.0, 2.0, 2.5, 5.0, 10.0, 20.0, 25.0, 50.0, 100.0,
  ];

  double _x(double v, double w) =>
      ((v - spec.gaugeMin) / (spec.gaugeMax - spec.gaugeMin)).clamp(0.0, 1.0) *
      w;

  List<double> _ticks() {
    final range = spec.gaugeMax - spec.gaugeMin;
    var step = _nice.last;
    for (final n in _nice) {
      if (range / n <= 6) {
        step = n;
        break;
      }
    }
    final first = (spec.gaugeMin / step).ceil() * step;
    final ticks = <double>[];
    for (var v = first; v <= spec.gaugeMax + 1e-6; v += step) {
      ticks.add(v);
    }
    return ticks;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final top = _centreY - _trackH / 2;
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, top, w, _trackH),
      const Radius.circular(_trackH / 2),
    );

    canvas.save();
    canvas.clipRRect(track);
    canvas.drawRRect(track, Paint()..color = AppColors.line);
    for (final b in bands) {
      final x0 = _x(b.min ?? spec.gaugeMin, w);
      final x1 = _x(b.max ?? spec.gaugeMax, w);
      if (x1 <= x0) continue;
      canvas.drawRect(
        Rect.fromLTWH(x0, top, x1 - x0, _trackH),
        Paint()..color = b.tone.fg.withValues(alpha: 0.22),
      );
    }
    // Graduations on the bar itself, like a clinical scale.
    final tickPaint = Paint()
      ..color = AppColors.ink.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (final v in _ticks()) {
      final x = _x(v, w);
      canvas.drawLine(
        Offset(x, top + 3),
        Offset(x, top + _trackH - 3),
        tickPaint,
      );
    }
    canvas.restore();

    // Numbering under the scale.
    for (final (v, x, align) in _labels(w)) {
      final tp = TextPainter(
        text: TextSpan(
          text: spec.format(v),
          style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final left = switch (align) {
        _LabelAlign.left => 0.0,
        _LabelAlign.right => w - tp.width,
        _LabelAlign.centre => (x - tp.width / 2).clamp(0.0, w - tp.width),
      };
      tp.paint(canvas, Offset(left, _centreY + _trackH / 2 + 6));
    }

    final pos = t;
    if (pos == null) return;
    final c = Offset(pos * w, _centreY);
    canvas.drawCircle(
      c,
      15,
      Paint()
        ..color = markerColour.withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(c, 12.5, Paint()..color = Colors.white);
    canvas.drawCircle(
      c,
      12.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = AppColors.lineStrong,
    );
    canvas.drawCircle(c, 6.5, Paint()..color = markerColour);
  }

  List<(double, double, _LabelAlign)> _labels(double w) {
    final out = <(double, double, _LabelAlign)>[];
    for (final v in _ticks()) {
      final x = _x(v, w);
      // Keep interior labels clear of the corner labels.
      if (x < 26 || x > w - 26) continue;
      out.add((v, x, _LabelAlign.centre));
    }
    out.add((spec.gaugeMin, 0, _LabelAlign.left));
    out.add((spec.gaugeMax, w, _LabelAlign.right));
    return out;
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.t != t ||
      old.markerColour != markerColour ||
      old.bands != bands ||
      old.spec.gaugeMin != spec.gaugeMin ||
      old.spec.gaugeMax != spec.gaugeMax ||
      old.spec.decimals != spec.decimals;
}
