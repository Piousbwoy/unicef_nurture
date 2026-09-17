/// The form's view of what the Vitals Station captured.
///
/// Glass tiles with band tones, one 'Re-take' per vital that sends the nurse
/// back to the station on that vital, and an 'Edit values manually' expander
/// the form fills with its own, unchanged [MeasureField]s. Nothing here
/// classifies anything — the tones are the same display bands the station
/// showed, and the engines still decide on the chart.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/glass.dart';
import '../types.dart';
import 'vital_capture_card.dart';
import 'vitals_station_screen.dart';

/// The additive keys the form merges into its verbatim inputs map. Engines and
/// sync ignore them; the result screen and the next visit's "Last …" chip
/// read them.
Map<String, Object?> stationInputs(StationResult? result) {
  if (result == null || result.isEmpty) return const {};
  return {
    if (result.capturedAt != null)
      'station_captured_at': result.capturedAt!.toIso8601String(),
    if (result.notMeasured.isNotEmpty)
      'not_measured': Map<String, Object?>.from(result.notMeasured),
    if (result.retakes.isNotEmpty)
      'retakes': Map<String, Object?>.from(result.retakes),
  };
}

class CapturedVitalsCard extends StatefulWidget {
  const CapturedVitalsCard({
    super.key,
    required this.input,
    required this.result,
    required this.manualFields,
    this.onRetakeVital,
    this.title = 'Measurements',
    this.subtitle,
  });

  final AssessmentContext input;
  final StationResult result;

  /// The form's own measurement widgets, shown under 'Edit values manually'.
  final List<Widget> manualFields;

  /// Called with the vital key; the shell reopens the station on that vital.
  final ValueChanged<String>? onRetakeVital;

  final String title;
  final String? subtitle;

  @override
  State<CapturedVitalsCard> createState() => _CapturedVitalsCardState();
}

class _CapturedVitalsCardState extends State<CapturedVitalsCard> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final specs = stationSpecsFor(widget.input);
    final ctx = vitalContextFor(widget.input);
    final entries = widget.result.toEntries(specs);
    final at = widget.result.capturedAt;
    final fx = VisualEffects.of(context);

    return GlassSurface(
      tier: GlassTier.card,
      blur: false,
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(Gap.radiusSm),
                ),
                child: const Icon(
                  Icons.monitor_heart_outlined,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: AppType.title),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle ??
                          (at == null
                              ? 'From the vitals station.'
                              : 'From the vitals station at '
                                    '${DateFormat.Hm().format(at)}.'),
                      style: AppType.caption.copyWith(height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          for (var i = 0; i < specs.length; i++) ...[
            VitalSummaryTile(
              spec: specs[i],
              ctx: ctx,
              entry: entries[specs[i].key] ?? const VitalEntry(),
              index: i,
              onRetake: widget.onRetakeVital == null
                  ? null
                  : () => widget.onRetakeVital!(specs[i].key),
            ),
            if (i < specs.length - 1) const SizedBox(height: Gap.sm),
          ],
          if (widget.manualFields.isNotEmpty) ...[
            const SizedBox(height: Gap.md),
            Semantics(
              button: true,
              expanded: _editing,
              child: InkWell(
                borderRadius: BorderRadius.circular(Gap.radiusSm),
                onTap: () => setState(() => _editing = !_editing),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: AppColors.primaryDark,
                      ),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: Text(
                          'Edit values manually',
                          style: AppType.label.copyWith(
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ),
                      AnimatedRotation(
                        turns: _editing ? 0.5 : 0,
                        duration: fx.scale(AppMotion.fast),
                        child: const Icon(
                          Icons.expand_more_rounded,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // AnimatedSize with a zero duration re-dirties itself during
            // layout, so under reduced motion the expander is plain.
            if (fx.motion)
              AnimatedSize(
                duration: AppMotion.fast,
                curve: AppMotion.curve,
                alignment: Alignment.topCenter,
                child: _manualFields,
              )
            else
              _manualFields,
          ],
        ],
      ),
    );
  }

  Widget get _manualFields => _editing
      ? Padding(
          padding: const EdgeInsets.only(top: Gap.sm),
          child: Column(children: widget.manualFields),
        )
      : const SizedBox(width: double.infinity);
}
