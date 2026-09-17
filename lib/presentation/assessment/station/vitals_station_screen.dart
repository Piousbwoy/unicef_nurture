/// The Vitals Station.
///
/// Sits between roll call and the protocol chart. One vital at a time, big
/// readout, clinical keypad, live range band, previous-visit delta, re-take,
/// "not measured" with a reason, and a 60-second breath counter. It only
/// *pre-fills* the protocol form — every classification still happens in the
/// engines, on the chart, exactly as before. Nothing here writes to the
/// database, and nothing here uses the system keyboard.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/glass.dart';
import '../../../core/theme/motion.dart';
import '../../../domain/enums.dart';
import '../types.dart';
import 'station_specs.dart';
import 'vital_capture_card.dart';
import 'vital_spec.dart';

/// What the station hands to the form.
class StationResult {
  const StationResult({
    this.values = const {},
    this.notMeasured = const {},
    this.retakes = const {},
    this.capturedAt,
  });

  static const empty = StationResult();

  /// Vital key → value. Includes `rr_timer_secs` when the breath counter ran.
  final Map<String, num> values;

  /// Vital key → reason ('No equipment' | 'Patient refused' | 'Not indicated').
  final Map<String, String> notMeasured;

  /// Vital key → how many times it was re-taken.
  final Map<String, int> retakes;

  /// When the station was completed (null when skipped).
  final DateTime? capturedAt;

  bool get isEmpty => values.isEmpty && notMeasured.isEmpty;

  /// The per-vital entries this result was built from, so the form can send
  /// the nurse back to one vital with everything else intact.
  static StationResult fromEntries(
    Map<String, VitalEntry> entries,
    List<VitalSpec> specs,
  ) {
    final values = <String, num>{};
    final notMeasured = <String, String>{};
    final retakes = <String, int>{};
    for (final spec in specs) {
      final e = entries[spec.key];
      if (e == null) continue;
      if (e.notMeasured != null) notMeasured[spec.key] = e.notMeasured!;
      final v = e.value;
      if (v != null) values[spec.key] = spec.decimals == 0 ? v.round() : v;
      final p = spec.pair;
      final pv = e.pairValue;
      if (p != null && pv != null) {
        values[p.key] = p.decimals == 0 ? pv.round() : pv;
      }
      if (e.rrTimerSecs != null && spec.key == 'respiratory_rate') {
        values['rr_timer_secs'] = e.rrTimerSecs!;
      }
      if (e.retakes > 0) retakes[spec.key] = e.retakes;
    }
    return StationResult(
      values: values,
      notMeasured: notMeasured,
      retakes: retakes,
      capturedAt: DateTime.now(),
    );
  }

  /// Rebuilds editable entries from a result (used for a per-vital re-take
  /// from the form).
  Map<String, VitalEntry> toEntries(List<VitalSpec> specs) {
    final out = <String, VitalEntry>{};
    for (final spec in specs) {
      final v = values[spec.key];
      final pv = spec.pair == null ? null : values[spec.pair!.key];
      out[spec.key] = VitalEntry(
        text: v == null ? '' : spec.format(v),
        pairText: pv == null ? '' : spec.pair!.format(pv),
        notMeasured: notMeasured[spec.key],
        retakes: retakes[spec.key] ?? 0,
        capturedAt: v == null && notMeasured[spec.key] == null
            ? null
            : capturedAt,
        rrTimerSecs: spec.key == 'respiratory_rate'
            ? values['rr_timer_secs']?.toInt()
            : null,
      );
    }
    return out;
  }
}

/// Builds the ordered vitals for this patient.
List<VitalSpec> stationSpecsFor(AssessmentContext input) {
  final p = input.person;
  return switch (p.effectiveClientType) {
    ClientType.pregnantWoman => maternalStationVitals(isPregnant: true),
    ClientType.postpartumWoman || ClientType.womanOfReproductiveAge =>
      maternalStationVitals(isPregnant: false),
    ClientType.newborn => childStationVitals(
      isYoungInfant: true,
      ageMonths: p.ageInMonths,
    ),
    ClientType.childUnderFive => childStationVitals(
      isYoungInfant: false,
      ageMonths: p.ageInMonths,
    ),
  };
}

VitalContext vitalContextFor(AssessmentContext input) => VitalContext(
  clientType: input.person.effectiveClientType,
  ageDays: input.person.ageInDays,
  ageMonths: input.person.ageInMonths,
  gestationWeeks: input.maternal?.gestationalWeeks,
);

class VitalsStationScreen extends ConsumerStatefulWidget {
  const VitalsStationScreen({
    super.key,
    required this.input,
    required this.onContinue,
    required this.onSkip,
    required this.onDanger,
    this.initial,
    this.startAtKey,
  });

  final AssessmentContext input;

  /// 'Continue to chart' with the captured vitals.
  final ValueChanged<StationResult> onContinue;

  /// 'Skip to chart' — straight to the form with nothing pre-filled.
  final VoidCallback onSkip;

  /// 'Danger sign now?' — straight to the form; the chart's danger-sign
  /// section is the right place, not a vitals screen.
  final VoidCallback onDanger;

  /// Previously captured values (re-take from the form).
  final StationResult? initial;

  /// Open on this vital instead of the first.
  final String? startAtKey;

  @override
  ConsumerState<VitalsStationScreen> createState() =>
      _VitalsStationScreenState();
}

class _VitalsStationScreenState extends ConsumerState<VitalsStationScreen> {
  late final List<VitalSpec> _specs = stationSpecsFor(widget.input);
  late final VitalContext _ctx = vitalContextFor(widget.input);
  late final Map<String, VitalEntry> _entries;
  late final PageController _pager;
  late int _page;

  int get _reviewPage => _specs.length;

  @override
  void initState() {
    super.initState();
    _entries =
        widget.initial?.toEntries(_specs) ??
        {for (final s in _specs) s.key: const VitalEntry()};
    final startIndex = widget.startAtKey == null
        ? -1
        : _specs.indexWhere((s) => s.key == widget.startAtKey);
    _page = startIndex < 0 ? 0 : startIndex;
    _pager = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _go(int page) {
    final fx = VisualEffects.of(context);
    setState(() => _page = page);
    if (fx.motion) {
      _pager.animateToPage(
        page,
        duration: AppMotion.fast,
        curve: AppMotion.curve,
      );
    } else {
      _pager.jumpToPage(page);
    }
  }

  void _continue() =>
      widget.onContinue(StationResult.fromEntries(_entries, _specs));

  VitalTone? _toneOf(VitalSpec spec) {
    final e = _entries[spec.key];
    final v = e?.value;
    if (v == null) return null;
    final a = spec.bandFor(v, _ctx)?.tone;
    final pv = e?.pairValue;
    final b = spec.pair == null || pv == null
        ? null
        : spec.pair!.bandFor(pv, _ctx)?.tone;
    if (a == null) return b;
    if (b == null) return a;
    return b.index > a.index ? b : a;
  }

  @override
  Widget build(BuildContext context) {
    final person = widget.input.person;
    final isReview = _page == _reviewPage;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(
        title: Text(isReview ? 'Review vitals' : 'Vitals'),
        actions: [
          // Bounded so a 320px phone at 200% text keeps the title and the
          // shortcut on one bar; the label scales down rather than clips.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.45,
            ),
            child: TextButton(
              onPressed: widget.onSkip,
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Skip to chart'),
              ),
            ),
          ),
        ],
      ),
      body: AmbientBackdrop(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, 0),
              child: _IdentityStrip(input: widget.input),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, 0),
              child: _ProgressRail(
                specs: _specs,
                entries: _entries,
                current: _page,
                toneOf: _toneOf,
                onTap: _go,
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pager,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: _specs.length + 1,
                itemBuilder: (context, i) {
                  if (i == _reviewPage) {
                    return _ReviewPage(
                      specs: _specs,
                      ctx: _ctx,
                      entries: _entries,
                      onRetake: (key) =>
                          _go(_specs.indexWhere((s) => s.key == key)),
                      onContinue: _continue,
                    );
                  }
                  final spec = _specs[i];
                  return ListView(
                    padding: const EdgeInsets.all(Gap.md),
                    children: [
                      VitalCaptureCard(
                        key: ValueKey('capture-${spec.key}'),
                        spec: spec,
                        ctx: _ctx,
                        personId: person.id,
                        entry: _entries[spec.key] ?? const VitalEntry(),
                        onChanged: (e) =>
                            setState(() => _entries[spec.key] = e),
                        onNext: () => _go(i + 1),
                        isLast: i == _specs.length - 1,
                      ),
                      const SizedBox(height: Gap.md),
                      Center(
                        child: TextButton.icon(
                          onPressed: widget.onDanger,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.triageRed,
                          ),
                          icon: const Icon(
                            Icons.warning_amber_rounded,
                            size: 18,
                          ),
                          label: const Text('Danger sign now?'),
                        ),
                      ),
                      const SizedBox(height: Gap.xl),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _initialsOf(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  final first = parts.first[0];
  final second = parts.length > 1 ? parts.last[0] : '';
  return '$first$second'.toUpperCase();
}

class _IdentityStrip extends ConsumerWidget {
  const _IdentityStrip({required this.input});

  final AssessmentContext input;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = input.person;
    final last = ref.watch(latestAssessmentProvider(p.id)).valueOrNull;
    return GlassSurface(
      tier: GlassTier.card,
      blur: false,
      padding: const EdgeInsets.all(Gap.md),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              gradient: AppColors.brandGradient,
              shape: BoxShape.circle,
            ),
            child: Text(
              _initialsOf(p.fullName),
              style: AppType.label.copyWith(color: Colors.white),
            ),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.fullName,
                  style: AppType.title.copyWith(fontSize: 17),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: Gap.sm,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(p.ageLabel, style: AppType.caption),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Gap.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(Gap.radiusXs),
                      ),
                      child: Text(
                        p.effectiveClientType.protocolLabel,
                        style: AppType.caption.copyWith(
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    Text(
                      last == null
                          ? 'First assessment'
                          : 'Last visit ${DateFormat('d MMM').format(last.performedAt)}',
                      style: AppType.caption,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One segment per vital plus one for Review. Filled with the band tone once
/// captured (colour on the segment because it *is* the clinical reading, not
/// decoration); grey when not measured; outline when pending.
class _ProgressRail extends StatelessWidget {
  const _ProgressRail({
    required this.specs,
    required this.entries,
    required this.current,
    required this.toneOf,
    required this.onTap,
  });

  final List<VitalSpec> specs;
  final Map<String, VitalEntry> entries;
  final int current;
  final VitalTone? Function(VitalSpec) toneOf;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final fx = VisualEffects.of(context);
    final total = specs.length + 1;
    return Semantics(
      label: 'Vital ${current + 1} of $total',
      child: Row(
        children: [
          for (var i = 0; i < total; i++) ...[
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(i),
                child: SizedBox(
                  height: 24,
                  child: Center(
                    child: AnimatedContainer(
                      duration: fx.scale(AppMotion.fast),
                      height: i == current ? 8 : 5,
                      decoration: BoxDecoration(
                        color: _colour(i),
                        borderRadius: BorderRadius.circular(4),
                        border: i == current
                            ? Border.all(color: AppColors.primary, width: 1.5)
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (i < total - 1) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }

  Color _colour(int i) {
    if (i == specs.length) {
      return i == current ? AppColors.primaryLight : AppColors.line;
    }
    final spec = specs[i];
    final e = entries[spec.key];
    if (e?.notMeasured != null) return AppColors.lineStrong;
    final tone = toneOf(spec);
    if (tone != null) return tone.fg;
    if (e?.hasValue == true) return AppColors.primary;
    return i == current ? AppColors.primaryLight : AppColors.line;
  }
}

class _ReviewPage extends StatelessWidget {
  const _ReviewPage({
    required this.specs,
    required this.ctx,
    required this.entries,
    required this.onRetake,
    required this.onContinue,
  });

  final List<VitalSpec> specs;
  final VitalContext ctx;
  final Map<String, VitalEntry> entries;
  final ValueChanged<String> onRetake;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final captured = specs
        .where((s) => entries[s.key]?.hasValue == true)
        .length;
    final skipped = specs
        .where((s) => entries[s.key]?.notMeasured != null)
        .length;
    final pending = specs.length - captured - skipped;
    return ListView(
      padding: const EdgeInsets.all(Gap.md),
      children: [
        StaggeredReveal(
          index: 0,
          child: GlassSurface(
            tier: GlassTier.hero,
            padding: const EdgeInsets.all(Gap.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Vitals taken', style: AppType.headline),
                const SizedBox(height: Gap.xs),
                Text(
                  '$captured recorded · $skipped not measured'
                  '${pending > 0 ? ' · $pending still blank' : ''}. '
                  'The chart decides what they mean.',
                  style: AppType.caption.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Gap.md),
        for (var i = 0; i < specs.length; i++) ...[
          VitalSummaryTile(
            spec: specs[i],
            ctx: ctx,
            entry: entries[specs[i].key] ?? const VitalEntry(),
            onRetake: () => onRetake(specs[i].key),
            index: i + 1,
          ),
          const SizedBox(height: Gap.sm),
        ],
        const SizedBox(height: Gap.md),
        GradientButton(
          label: 'Continue to chart',
          icon: Icons.arrow_forward_rounded,
          onPressed: onContinue,
        ),
        const SizedBox(height: Gap.xl),
      ],
    );
  }
}
