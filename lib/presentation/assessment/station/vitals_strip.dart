/// The vitals strip under the verdict: every station vital this visit
/// recorded, as a horizontal row of glass chips with the band tone on the
/// number and the change since the previous visit.
///
/// Display guidance only. The tone comes from the same band tables the
/// station showed while the value was being taken; the engines that decided
/// the verdict are untouched and remain the single source of truth.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/glass.dart';
import '../../../core/theme/motion.dart';
import '../../../domain/entities/visit.dart';
import '../types.dart';
import 'vital_spec.dart';
import 'vitals_station_screen.dart';

class VitalsStrip extends ConsumerWidget {
  const VitalsStrip({
    super.key,
    required this.input,
    required this.inputs,
    this.omitKeys = const {},
  });

  final AssessmentContext input;

  /// The verbatim assessment inputs map.
  final Map<String, Object?> inputs;

  /// Station keys to leave off the strip even when captured — a measured
  /// value that drove no finding is still saved in the inputs, it just
  /// doesn't headline the verdict. Breathing rate is the case in point:
  /// it matters only when the assessment found a respiratory problem.
  final Set<String> omitKeys;

  static double? _num(Object? raw) => raw is num ? raw.toDouble() : null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctx = vitalContextFor(input);
    final captured = <VitalSpec>[
      for (final spec in stationSpecsFor(input))
        if (_num(inputs[spec.key]) != null && !omitKeys.contains(spec.key))
          spec,
    ];
    if (captured.isEmpty) return const SizedBox.shrink();

    final previous = ref
        .watch(latestAssessmentProvider(input.person.id))
        .valueOrNull;

    return Semantics(
      container: true,
      label: 'Vitals recorded this visit',
      child: SizedBox(
        height: 112,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          itemCount: captured.length,
          separatorBuilder: (_, _) => const SizedBox(width: Gap.sm),
          itemBuilder: (_, i) {
            final spec = captured[i];
            return StaggeredReveal(
              index: i,
              child: _VitalChip(
                spec: spec,
                ctx: ctx,
                value: _num(inputs[spec.key])!,
                pairValue: spec.pair == null
                    ? null
                    : _num(inputs[spec.pair!.key]),
                previous: previous,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _VitalChip extends StatelessWidget {
  const _VitalChip({
    required this.spec,
    required this.ctx,
    required this.value,
    required this.pairValue,
    required this.previous,
  });

  final VitalSpec spec;
  final VitalContext ctx;
  final double value;
  final double? pairValue;
  final Assessment? previous;

  @override
  Widget build(BuildContext context) {
    final p = ClinicalPaletteScope.of(context);
    // The pair (diastolic) can only worsen the tone, never soften it.
    var band = spec.bandFor(value, ctx);
    if (pairValue != null && spec.pair != null) {
      final pairBand = spec.pair!.bandFor(pairValue!, ctx);
      if (pairBand != null &&
          (band == null || pairBand.tone.index > band.tone.index)) {
        band = pairBand;
      }
    }
    final tone = band?.tone;
    final numberColour = tone?.fg ?? p.ink;

    final readout = pairValue == null
        ? spec.format(value)
        : '${spec.format(value)}/${spec.pair!.format(pairValue!)}';

    final prevRaw = previous?.inputs[spec.key];
    final prev = prevRaw is num ? prevRaw.toDouble() : null;
    String? delta;
    if (previous != null && prev != null) {
      final d = value - prev;
      final arrow = d > 0 ? '▲' : (d < 0 ? '▼' : '=');
      final sign = d > 0 ? '+' : '';
      delta =
          '$arrow $sign${spec.format(d)} · '
          '${DateFormat('d MMM').format(previous!.performedAt)}';
    }

    return GlassSurface(
      tier: GlassTier.chip,
      blur: false,
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 104),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(spec.icon, size: 13, color: p.inkMuted),
                const SizedBox(width: Gap.xs),
                Text(
                  spec.label.toUpperCase(),
                  style: AppType.eyebrow.copyWith(
                    fontSize: 9.5,
                    color: p.inkMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.xs),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: readout,
                    style: AppType.numeral.copyWith(
                      fontSize: 22,
                      color: numberColour,
                    ),
                  ),
                  TextSpan(
                    text: ' ${spec.unit}',
                    style: AppType.numeralUnit.copyWith(
                      fontSize: 11,
                      color: p.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (delta != null) ...[
              const SizedBox(height: 2),
              Text(
                delta,
                style: AppType.caption.copyWith(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: p.primaryDark,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
