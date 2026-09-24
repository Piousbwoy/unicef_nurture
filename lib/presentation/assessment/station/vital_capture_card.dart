/// One vital, one card. The active card on the station — the only glass
/// surface on that screen that blurs.
///
/// Layout, top to bottom: label + why line · big tabular readout with unit ·
/// hospital ruler · "Last …" chip from the previous assessment · captured-at
/// stamp · Re-take / Not measured / Next. Below it, the capture instrument
/// (− /+ jog buttons, then the breath counter, MUAC tape or the collapsible
/// "Type the reading instead" keypad).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/glass.dart';
import '../../../core/theme/motion.dart';
import '../../shared/ui.dart';
import '../widgets/muac_gauge.dart';
import 'breath_counter.dart';
import 'clinical_keypad.dart';
import 'hospital_ruler.dart';
import 'vital_spec.dart';

/// Reasons a vital was not taken. Recorded verbatim in `inputs['not_measured']`.
const notMeasuredReasons = ['No equipment', 'Patient refused', 'Not indicated'];

/// The editable state for one vital (and its paired reading, if any).
class VitalEntry {
  const VitalEntry({
    this.text = '',
    this.pairText = '',
    this.capturedAt,
    this.notMeasured,
    this.retakes = 0,
    this.rrTimerSecs,
  });

  final String text;
  final String pairText;
  final DateTime? capturedAt;
  final String? notMeasured;
  final int retakes;
  final int? rrTimerSecs;

  double? get value => double.tryParse(text);
  double? get pairValue => double.tryParse(pairText);
  bool get hasValue => value != null;

  VitalEntry copyWith({
    String? text,
    String? pairText,
    DateTime? capturedAt,
    Object? notMeasured = _keep,
    int? retakes,
    Object? rrTimerSecs = _keep,
  }) => VitalEntry(
    text: text ?? this.text,
    pairText: pairText ?? this.pairText,
    capturedAt: capturedAt ?? this.capturedAt,
    notMeasured: notMeasured == _keep
        ? this.notMeasured
        : notMeasured as String?,
    retakes: retakes ?? this.retakes,
    rrTimerSecs: rrTimerSecs == _keep ? this.rrTimerSecs : rrTimerSecs as int?,
  );

  static const _keep = Object();
}

class VitalCaptureCard extends ConsumerStatefulWidget {
  const VitalCaptureCard({
    super.key,
    required this.spec,
    required this.ctx,
    required this.personId,
    required this.entry,
    required this.onChanged,
    required this.onNext,
    this.isLast = false,
  });

  final VitalSpec spec;
  final VitalContext ctx;
  final String personId;
  final VitalEntry entry;
  final ValueChanged<VitalEntry> onChanged;
  final VoidCallback onNext;
  final bool isLast;

  @override
  ConsumerState<VitalCaptureCard> createState() => _VitalCaptureCardState();
}

class _VitalCaptureCardState extends ConsumerState<VitalCaptureCard> {
  /// For a paired vital (BP), which reading the ruler and jog are editing.
  bool _editingPair = false;

  /// The MUAC gauge wants a cm controller; we derive it from the mm text.
  final _muacCm = TextEditingController();

  VitalSpec get spec => widget.spec;
  VitalEntry get entry => widget.entry;

  @override
  void didUpdateWidget(VitalCaptureCard old) {
    super.didUpdateWidget(old);
    if (old.spec.key != spec.key) _editingPair = false;
    _syncMuac();
  }

  @override
  void initState() {
    super.initState();
    _syncMuac();
  }

  void _syncMuac() {
    if (!spec.showsMuacGauge) return;
    final mm = entry.value;
    final cm = mm == null ? '' : (mm / 10).toStringAsFixed(1);
    if (_muacCm.text != cm) _muacCm.text = cm;
  }

  @override
  void dispose() {
    _muacCm.dispose();
    super.dispose();
  }

  void _setText(String t) {
    final now = DateTime.now();
    widget.onChanged(
      _editingPair
          ? entry.copyWith(pairText: t, capturedAt: now, notMeasured: null)
          : entry.copyWith(text: t, capturedAt: now, notMeasured: null),
    );
  }

  void _retake() {
    widget.onChanged(VitalEntry(retakes: entry.retakes + 1));
    setState(() => _editingPair = false);
  }

  Future<void> _notMeasured() async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.sm),
              child: Text(
                'Why was ${spec.label.toLowerCase()} not measured?',
                style: AppType.title,
              ),
            ),
            for (final r in notMeasuredReasons)
              ListTile(
                minTileHeight: 48,
                title: Text(r),
                onTap: () => Navigator.of(ctx).pop(r),
              ),
            const SizedBox(height: Gap.sm),
          ],
        ),
      ),
    );
    if (reason == null || !mounted) return;
    widget.onChanged(VitalEntry(retakes: entry.retakes, notMeasured: reason));
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final fx = VisualEffects.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final v = entry.value;
    final band = v == null ? null : spec.bandFor(v, widget.ctx);
    final pair = spec.pair;
    final pairV = entry.pairValue;
    final pairBand = pair == null || pairV == null
        ? null
        : pair.bandFor(pairV, widget.ctx);
    final activeSpec = _editingPair && pair != null ? pair : spec;
    final activeText = _editingPair ? entry.pairText : entry.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassSurface(
          tier: GlassTier.hero,
          padding: const EdgeInsets.all(Gap.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.circular(Gap.radiusSm),
                    ),
                    child: Icon(spec.icon, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(spec.label, style: AppType.title),
                        const SizedBox(height: 2),
                        Text(
                          spec.why,
                          style: AppType.caption.copyWith(height: 1.45),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.lg),

              // Readout(s).
              if (entry.notMeasured != null)
                _NotMeasuredReadout(reason: entry.notMeasured!)
              else if (pair == null)
                _Readout(
                  text: entry.text,
                  unit: spec.unit,
                  tone: band?.tone,
                  scaler: scaler,
                  active: true,
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: _Readout(
                        text: entry.text,
                        unit: spec.unit,
                        caption: 'Systolic',
                        tone: band?.tone,
                        scaler: scaler,
                        compact: true,
                        active: !_editingPair,
                        onTap: () => setState(() => _editingPair = false),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                      child: Text(
                        '/',
                        style: AppType.numeral.copyWith(
                          fontSize: 40,
                          color: AppColors.inkFaint,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _Readout(
                        text: entry.pairText,
                        unit: pair.unit,
                        caption: pair.label,
                        tone: pairBand?.tone,
                        scaler: scaler,
                        compact: true,
                        active: _editingPair,
                        onTap: () => setState(() => _editingPair = true),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: Gap.md),

              if (entry.notMeasured == null)
                HospitalRuler(
                  spec: activeSpec,
                  ctx: widget.ctx,
                  value: _editingPair ? pairV : v,
                  onChanged: (value) => _setText(activeSpec.format(value)),
                ),
              const SizedBox(height: Gap.md),

              // Previous visit + captured-at.
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _PreviousChip(
                    spec: spec,
                    personId: widget.personId,
                    current: v,
                  ),
                  if (entry.capturedAt != null)
                    _Chip(
                      icon: Icons.schedule_rounded,
                      label:
                          'Captured ${DateFormat.Hm().format(entry.capturedAt!)}',
                    ),
                  if (entry.retakes > 0)
                    _Chip(
                      icon: Icons.replay_rounded,
                      label: entry.retakes == 1
                          ? 'Re-taken once'
                          : 'Re-taken ${entry.retakes}×',
                    ),
                ],
              ),
              const SizedBox(height: Gap.lg),

              // Actions. Wrap so 200% text never overflows at 320px.
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (entry.hasValue || entry.notMeasured != null)
                          ? _retake
                          : null,
                      icon: const Icon(Icons.replay_rounded, size: 18),
                      label: const Text('Re-take'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                      ),
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: entry.notMeasured == null
                          ? _notMeasured
                          : null,
                      icon: const Icon(Icons.block_rounded, size: 18),
                      label: const Text('Not measured'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.sm),
              GradientButton(
                label: widget.isLast ? 'Review' : 'Next',
                icon: Icons.arrow_forward_rounded,
                onPressed: widget.onNext,
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),

        // Instrument: the − / + jog, then the capture instrument.
        if (entry.notMeasured == null)
          AnimatedSwitcher(
            duration: fx.scale(AppMotion.fast),
            child: Column(
              key: ValueKey('inst-${activeSpec.key}'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FineTune(
                  spec: activeSpec,
                  value: _editingPair ? pairV : v,
                  onChanged: (value) => _setText(activeSpec.format(value)),
                ),
                const SizedBox(height: Gap.sm),
                _instrument(activeSpec, activeText),
              ],
            ),
          ),
      ],
    );
  }

  Widget _instrument(VitalSpec active, String text) {
    final keypad = ClinicalKeypad(
      key: ValueKey('keypad-${active.key}'),
      value: text,
      onChanged: _setText,
      allowDecimal: active.keypad == KeypadMode.decimal,
      maxDecimals: active.decimals == 0 ? 1 : active.decimals,
    );
    // Exact entry is the fallback now — the ruler and the jog do first pass.
    final typeInstead = ExpansionTile(
      key: ValueKey('type-${active.key}'),
      tilePadding: EdgeInsets.zero,
      title: Text(
        spec.capture == CaptureMode.breathCounter
            ? 'Type the rate instead'
            : 'Type the reading instead',
        style: AppType.label.copyWith(color: AppColors.inkMuted),
      ),
      children: [keypad],
    );
    switch (spec.capture) {
      case CaptureMode.breathCounter:
        return Column(
          key: const ValueKey('breath'),
          children: [
            BreathCounter(
              onResult: (rate, secs) => widget.onChanged(
                entry.copyWith(
                  text: '$rate',
                  capturedAt: DateTime.now(),
                  notMeasured: null,
                  rrTimerSecs: secs,
                ),
              ),
            ),
            const SizedBox(height: Gap.sm),
            typeInstead,
          ],
        );
      case CaptureMode.keypad:
        if (spec.showsMuacGauge) {
          return Column(
            key: const ValueKey('muac'),
            children: [
              GlassSurface(
                tier: GlassTier.card,
                blur: false,
                padding: const EdgeInsets.all(Gap.md),
                child: MuacGauge(controller: _muacCm),
              ),
              const SizedBox(height: Gap.sm),
              typeInstead,
            ],
          );
        }
        return typeInstead;
    }
  }
}

/// The − / + jog under the card: one tap moves the active reading by one
/// step of the spec; hold to repeat.
class _FineTune extends StatelessWidget {
  const _FineTune({
    required this.spec,
    required this.value,
    required this.onChanged,
  });

  final VitalSpec spec;
  final double? value;
  final ValueChanged<double> onChanged;

  void _step(int direction) {
    final v = value;
    final next = v == null
        ? (direction < 0 ? spec.gaugeMax : spec.gaugeMin)
        : (v + direction * spec.step).clamp(spec.gaugeMin, spec.gaugeMax);
    if (next != v) onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final by = spec.format(spec.step);
    return GlassSurface(
      tier: GlassTier.chip,
      blur: false,
      shadow: false,
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          Expanded(
            child: _JogButton(
              icon: Icons.remove_rounded,
              label: 'Decrease ${spec.label.toLowerCase()} by $by ${spec.unit}',
              onStep: () => _step(-1),
            ),
          ),
          Container(width: 1, height: 26, color: AppColors.line),
          Expanded(
            child: _JogButton(
              icon: Icons.add_rounded,
              label: 'Increase ${spec.label.toLowerCase()} by $by ${spec.unit}',
              onStep: () => _step(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _JogButton extends StatefulWidget {
  const _JogButton({
    required this.icon,
    required this.label,
    required this.onStep,
  });

  final IconData icon;
  final String label;
  final VoidCallback onStep;

  @override
  State<_JogButton> createState() => _JogButtonState();
}

class _JogButtonState extends State<_JogButton> {
  static const _repeatEvery = Duration(milliseconds: 140);

  Timer? _autoRepeat;

  void _stopRepeat() {
    _autoRepeat?.cancel();
    _autoRepeat = null;
  }

  /// A hold, not a press: the long-press recognizer wins the arena on its own
  /// timer, so repeating works while the finger is still down and a scroll
  /// that starts on the button never nudges the reading.
  void _startRepeat() {
    widget.onStep();
    _stopRepeat();
    _autoRepeat = Timer.periodic(_repeatEvery, (_) => widget.onStep());
  }

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onStep,
        onLongPress: _startRepeat,
        onLongPressUp: _stopRepeat,
        onLongPressCancel: _stopRepeat,
        child: SizedBox(
          height: 48,
          child: Center(
            child: Icon(widget.icon, size: 22, color: AppColors.inkMuted),
          ),
        ),
      ),
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({
    required this.text,
    required this.unit,
    required this.scaler,
    required this.active,
    this.tone,
    this.caption,
    this.onTap,
    this.compact = false,
  });

  final String text;
  final String unit;
  final TextScaler scaler;
  final bool active;
  final VitalTone? tone;
  final String? caption;
  final VoidCallback? onTap;

  /// Paired readings share one row, so they get a smaller numeral — at 56 a
  /// three-digit systolic fades mid-glyph on a 390dp phone.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colour = tone?.fg ?? AppColors.ink;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (caption != null)
          Text(
            caption!.toUpperCase(),
            style: AppType.eyebrow.copyWith(
              color: active ? AppColors.primary : AppColors.inkMuted,
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Semantics(
                  label: text.isEmpty
                      ? 'No reading yet'
                      : '$text $unit${tone == null ? '' : ', ${tone!.name}'}',
                  child: Text(
                    text.isEmpty ? '—' : text,
                    maxLines: 1,
                    style: AppType.numeral.copyWith(
                      fontSize:
                          (compact ? 40 : 56) *
                          (scaler.scale(1) > 1.3 ? 0.75 : 1.0),
                      color: text.isEmpty ? AppColors.inkFaint : colour,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: Gap.sm),
            Text(unit, style: AppType.numeralUnit),
          ],
        ),
      ],
    );
    if (onTap == null) return body;
    return PressScale(
      onTap: onTap,
      radius: BorderRadius.circular(Gap.radiusSm),
      child: Container(
        padding: const EdgeInsets.all(Gap.sm),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Gap.radiusSm),
          border: Border.all(
            color: active ? AppColors.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: body,
      ),
    );
  }
}

class _NotMeasuredReadout extends StatelessWidget {
  const _NotMeasuredReadout({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.block_rounded, color: AppColors.inkMuted, size: 28),
      const SizedBox(width: Gap.sm),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Not measured', style: AppType.title),
            Text(reason, style: AppType.caption),
          ],
        ),
      ),
    ],
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, this.colour});

  final IconData icon;
  final String label;
  final Color? colour;

  @override
  Widget build(BuildContext context) => GlassSurface(
    tier: GlassTier.chip,
    blur: false,
    shadow: false,
    padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 6),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colour ?? AppColors.inkMuted),
        const SizedBox(width: Gap.xs),
        // Flexible so a long previous-visit label wraps at 200% text on
        // narrow phones instead of overflowing the chip.
        Flexible(
          child: Text(
            label,
            style: AppType.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: colour ?? AppColors.inkMuted,
            ),
          ),
        ),
      ],
    ),
  );
}

/// "Last 4.1 kg · 12 Mar ▲ +0.3" from the person's previous assessment.
class _PreviousChip extends ConsumerWidget {
  const _PreviousChip({
    required this.spec,
    required this.personId,
    required this.current,
  });

  final VitalSpec spec;
  final String personId;
  final double? current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = ref.watch(latestAssessmentProvider(personId)).valueOrNull;
    final raw = last?.inputs[spec.key];
    final prev = raw is num ? raw.toDouble() : null;
    if (last == null || prev == null) return const SizedBox.shrink();

    final date = DateFormat('d MMM').format(last.performedAt);
    var label = 'Last ${spec.format(prev)} ${spec.unit} · $date';
    Color? colour;
    if (current != null) {
      final delta = current! - prev;
      final arrow = delta > 0 ? '▲' : (delta < 0 ? '▼' : '=');
      final sign = delta > 0 ? '+' : '';
      label += ' $arrow $sign${spec.format(delta)}';
      colour = AppColors.primaryDark;
    }
    return _Chip(icon: Icons.history_rounded, label: label, colour: colour);
  }
}

/// Shown on the Review page and in the form: a compact tile per vital.
class VitalSummaryTile extends StatelessWidget {
  const VitalSummaryTile({
    super.key,
    required this.spec,
    required this.ctx,
    required this.entry,
    this.onRetake,
    this.index = 0,
  });

  final VitalSpec spec;
  final VitalContext ctx;
  final VitalEntry entry;
  final VoidCallback? onRetake;
  final int index;

  @override
  Widget build(BuildContext context) {
    final v = entry.value;
    final band = v == null ? null : spec.bandFor(v, ctx);
    final pair = spec.pair;
    final pairV = entry.pairValue;
    final pairBand = pair == null || pairV == null
        ? null
        : pair.bandFor(pairV, ctx);
    // The louder of the two tones wins the tile colour.
    final tone = [band?.tone, pairBand?.tone]
        .whereType<VitalTone>()
        .fold<VitalTone?>(
          null,
          (a, b) => a == null || b.index > a.index ? b : a,
        );
    final colour = tone?.fg ?? AppColors.ink;

    String reading;
    if (entry.notMeasured != null) {
      reading = 'Not measured';
    } else if (v == null) {
      reading = '—';
    } else if (pair != null) {
      reading =
          '${spec.format(v)}/${pairV == null ? '—' : pair.format(pairV)} ${spec.unit}';
    } else {
      reading = '${spec.format(v)} ${spec.unit}';
    }
    final note = entry.notMeasured ?? band?.note ?? pairBand?.note;

    return StaggeredReveal(
      index: index,
      child: GlassSurface(
        tier: GlassTier.card,
        blur: false,
        padding: const EdgeInsets.all(Gap.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: (tone?.fg ?? AppColors.primary).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(Gap.radiusXs),
              ),
              child: Icon(spec.icon, size: 18, color: colour),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(spec.label, style: AppType.label),
                  const SizedBox(height: 2),
                  Text(
                    reading,
                    style: AppType.title.copyWith(
                      fontSize: 18,
                      color: entry.notMeasured != null
                          ? AppColors.inkMuted
                          : colour,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (note != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      note,
                      style: AppType.caption.copyWith(
                        color: tone?.fg ?? AppColors.inkMuted,
                        fontWeight: tone == null
                            ? FontWeight.w500
                            : FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onRetake != null)
              IconButton(
                tooltip: 'Re-take ${spec.label.toLowerCase()}',
                onPressed: onRetake,
                icon: const Icon(Icons.replay_rounded),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              ),
          ],
        ),
      ),
    );
  }
}
