/// The Road-to-Health card: the child's weighings drawn on the WHO
/// weight-for-age standard, in the green / yellow / red the card has always
/// used.
///
/// This is a rendering job only. The placement maths — age at each weighing,
/// z-score, which band, whether the last step crossed down — lives in
/// `domain/engines/road_to_health.dart`, so the numbers can be tested without
/// a canvas and reused without fl_chart.
///
/// ## Why the zones are drawn from the reference curves
///
/// The bands are not decoration painted at fixed pixel heights. Each boundary
/// is the WHO's own weight at −3, −2 and +2 SD interpolated month by month from
/// `WeightForAgeReference`, and the fills sit between those curves. So the
/// green/yellow/red on screen is the same boundary the paper card prints, for
/// this child's sex, at every age — including the months the child was never
/// weighed.
///
/// ## What the card refuses to do
///
///   * It does not draw when it cannot place the child. No date of birth, no
///     weights, or a child past the 60-month end of the standard each get their
///     own sentence instead of an empty axis that reads as "growing normally".
///   * It does not hide skipped visits. A weighing-less visit is stated,
///     because a gap in the line is clinical information.
///   * It does not speak alone: weight-for-age cannot separate thin from short,
///     so the caption keeps the MUAC tape and weight-for-height in the frame.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/reference/weight_for_age_reference.dart';
import '../../../domain/engines/road_to_health.dart';
import '../../../domain/enums.dart';
import '../../fhw/clinic_widgets.dart';

/// The plot itself: reference bands behind, the child's track in front.
class RoadToHealthChart extends StatelessWidget {
  const RoadToHealthChart({super.key, required this.reading});

  final RoadToHealthReading reading;

  /// The axis floor. Weight starts at zero; a truncated weight axis would
  /// steepen every slope on the card and make a normal gain look like a fall.
  static const double _minWeight = 0;

  @override
  Widget build(BuildContext context) {
    final sex = reading.sex;
    final horizon = _horizonMonths(reading);
    final top = _topOfAxis(sex, reading, horizon);
    final months = List.generate(horizon.toInt() + 1, (i) => i.toDouble());

    double? curveAt(double z, double month) =>
        WeightForAgeReference.weightAt(sex, month, z);

    List<FlSpot> curve(double z) => [
      for (final m in months)
        if (curveAt(z, m) != null) FlSpot(m, curveAt(z, m)!),
    ];

    final track = [
      for (final p in reading.points) FlSpot(p.ageMonths, p.weightKg),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: _spoken(sex, reading),
          child: SizedBox(
            height: 210,
            child: Padding(
              padding: const EdgeInsets.only(top: Gap.xs),
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: horizon.toDouble(),
                  minY: _minWeight,
                  maxY: top,
                  clipData: const FlClipData.all(),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  lineTouchData: const LineTouchData(enabled: false),
                  titlesData: _titles(horizon),
                  // index 0 = +2 SD, 1 = −2 SD, 2 = −3 SD, 3 = this child.
                  lineBarsData: [
                    _boundary(curve(2)),
                    _boundary(curve(-2)),
                    // The red band hangs off the −3 line down to the axis.
                    _boundary(curve(-3)).copyWith(
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.triageRed.withValues(alpha: 0.16),
                        cutOffY: _minWeight,
                        applyCutOffY: true,
                      ),
                    ),
                    LineChartBarData(
                      spots: track,
                      isCurved: false,
                      color: AppColors.ink,
                      barWidth: 2.6,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, index) =>
                            FlDotCirclePainter(
                              radius: 4,
                              color: AppColors.ink,
                              strokeWidth: 1.6,
                              strokeColor: Colors.white,
                            ),
                      ),
                      belowBarData: BarAreaData(show: false),
                      aboveBarData: BarAreaData(show: false),
                    ),
                  ],
                  betweenBarsData: [
                    BetweenBarsData(
                      fromIndex: 0,
                      toIndex: 1,
                      color: AppColors.triageGreen.withValues(alpha: 0.15),
                    ),
                    BetweenBarsData(
                      fromIndex: 1,
                      toIndex: 2,
                      color: AppColors.triageAmber.withValues(alpha: 0.20),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Gap.xs),
        Text(
          'Weight in kilograms, against months completed at each weighing',
          style: AppType.caption.copyWith(
            fontSize: 11,
            color: AppColors.inkFaint,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  LineChartBarData _boundary(List<FlSpot> spots) => LineChartBarData(
    spots: spots,
    isCurved: false,
    color: AppColors.inkFaint.withValues(alpha: 0.55),
    barWidth: 1,
    dashArray: const [3, 3],
    dotData: const FlDotData(show: false),
  );

  /// How far along the age axis the card runs: the next twelve-month mark
  /// after this child's newest weighing, plus a little paper ahead of them,
  /// clamped to the 0–60 months the standard covers.
  ///
  /// A twenty-month-old's whole life is under two years long. Drawing the full
  /// sixty months anyway puts their track in the left third of the card and
  /// leaves the rest as empty grid — the one thing the paper card never does,
  /// because its chart is printed at the child's age. The bands are unchanged;
  /// only the window moves.
  static double _horizonMonths(RoadToHealthReading reading) {
    final newest = reading.points.last.ageMonths;
    final span = ((newest / 12).ceil() * 12 + 6).clamp(
      24.0,
      WeightForAgeReference.maxAgeMonths,
    );
    return span.toDouble();
  }

  /// The axis top: a clean five kilograms above the highest +2 SD line inside
  /// the window, unless the child themselves weighs more than the band.
  double _topOfAxis(
    Sex sex,
    RoadToHealthReading reading,
    double horizonMonths,
  ) {
    var highest = 0.0;
    for (var m = 0.0; m <= horizonMonths; m += 6) {
      final v = WeightForAgeReference.weightAt(sex, m, 2);
      if (v != null && v > highest) highest = v;
    }
    for (final p in reading.points) {
      if (p.weightKg > highest) highest = p.weightKg;
    }
    return ((highest + 2) / 5).ceil() * 5;
  }

  /// The unit is in the caption under the plot, not on the axis: fl_chart
  /// draws a vertical `axisNameWidget` on top of the tick labels it shares the
  /// reserved strip with, and "kg" colliding with "10" is unreadable.
  FlTitlesData _titles(double horizon) => FlTitlesData(
    show: true,
    topTitles: const AxisTitles(),
    rightTitles: const AxisTitles(),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 30,
        // Whole kilograms. A weight axis that ticks in 6.25 kg steps is a
        // reminder that the number came from the software, not the scale.
        interval: 5,
        getTitlesWidget: (value, meta) => Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(
            value.toStringAsFixed(0),
            style: AppType.caption.copyWith(
              fontSize: 10,
              color: AppColors.inkFaint,
            ),
          ),
        ),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 26,
        // Six-monthly on a short window so the last tick is the edge of the
        // paper rather than a number crowded against the one before it.
        interval: horizon <= 30 ? 6 : 12,
        getTitlesWidget: (value, meta) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            value.toStringAsFixed(0),
            style: AppType.caption.copyWith(
              fontSize: 10,
              color: AppColors.inkFaint,
            ),
          ),
        ),
      ),
    ),
  );

  String _spoken(Sex sex, RoadToHealthReading reading) {
    final last = reading.last;
    if (last == null) return 'Weight-for-age chart, nothing to plot.';
    return 'Weight-for-age on the WHO standard, '
        '${sex == Sex.male ? 'boys' : 'girls'} chart. '
        '${reading.points.length} weighings plotted. '
        'Most recent: ${last.weightKg.toStringAsFixed(1)} kilograms at '
        '${last.ageMonths.toStringAsFixed(1)} months, '
        '${RoadToHealth.zText(last.z)} standard deviations from the median, '
        'in the ${last.zone.label} band.';
  }
}

/// The card that mounts on a screen: chart, band reading, and the limits of
/// what a weight-for-age line can say.
class RoadToHealthCard extends StatelessWidget {
  const RoadToHealthCard({super.key, required this.reading});

  final RoadToHealthReading reading;

  @override
  Widget build(BuildContext context) {
    final gap = reading.gap;
    if (gap != null || reading.points.isEmpty) {
      final why = gap ?? RoadToHealthGap.noWeighings;
      return ClinicCard(
        title: 'Road to Health',
        subtitle: 'Why the chart is not drawn',
        child: _GapNote(gap: why),
      );
    }

    final zone = reading.zone!;
    final accent = switch (zone) {
      RoadToHealthZone.red => AppColors.triageRed,
      RoadToHealthZone.yellow => AppColors.triageAmber,
      RoadToHealthZone.green || RoadToHealthZone.high => AppColors.triageGreen,
    };

    return ClinicCard(
      accent: accent.withValues(alpha: 0.5),
      title: 'Road to Health',
      subtitle:
          'Weight against the WHO weight-for-age standard for a '
          '${reading.sex == Sex.male ? 'boy' : 'girl'}, '
          'from the weighings saved on this phone.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WhereTheLineSits(zone: zone, movedDown: reading.movedDown),
          const SizedBox(height: Gap.sm),
          RoadToHealthChart(reading: reading),
          const SizedBox(height: Gap.sm),
          const _BandKey(),
          const SizedBox(height: Gap.sm),
          _Points(reading: reading),
          const SizedBox(height: Gap.sm),
          Text(
            'Weight-for-age cannot tell a thin child from a short one. The MUAC '
            'tape and the weight-for-height z-score still decide how this child '
            'is managed.\nReference: WHO Child Growth Standards (2006), '
            'weight-for-age, 0–60 months.',
            style: AppType.caption.copyWith(
              fontSize: 11,
              height: 1.45,
              color: AppColors.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _WhereTheLineSits extends StatelessWidget {
  const _WhereTheLineSits({required this.zone, required this.movedDown});

  final RoadToHealthZone zone;
  final bool movedDown;

  @override
  Widget build(BuildContext context) {
    final tone = switch (zone) {
      RoadToHealthZone.red => AppColors.triageRed,
      RoadToHealthZone.yellow => AppColors.triageAmber,
      RoadToHealthZone.green || RoadToHealthZone.high => AppColors.triageGreen,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(top: 4, right: Gap.sm),
          decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
        ),
        Expanded(
          child: Text(
            '${zone.label}. ${zone.meaning}'
            '${movedDown ? ' The line has crossed down into this band since '
                      'the last weighing — a fall matters even when the band is '
                      'still readable as acceptable.' : ''}',
            style: AppType.body.copyWith(
              fontSize: 14,
              color: AppColors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// The three bands, in the words the card itself uses.
class _BandKey extends StatelessWidget {
  const _BandKey();

  @override
  Widget build(BuildContext context) {
    const entries = [
      (AppColors.triageGreen, 'On the standard: −2 to +2 SD'),
      (AppColors.triageAmber, 'Watch: −3 to −2 SD'),
      (AppColors.triageRed, 'Act: below −3 SD'),
    ];
    return Wrap(
      spacing: Gap.md,
      runSpacing: Gap.xs,
      children: [
        for (final (color, label) in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.28),
                  border: Border.all(color: color, width: 1),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Flexible(
                child: Text(
                  label,
                  style: AppType.caption.copyWith(
                    fontSize: 11,
                    height: 1.35,
                    color: AppColors.inkMuted,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// Every weighing, oldest first — so the line can be checked digit by digit
/// against the paper card rather than trusted.
class _Points extends StatelessWidget {
  const _Points({required this.reading});

  final RoadToHealthReading reading;

  @override
  Widget build(BuildContext context) {
    final omitted = <String>[
      if (reading.unweighedVisits > 0)
        '${reading.unweighedVisits} visit'
            '${reading.unweighedVisits == 1 ? '' : 's'} with no weight',
      if (reading.offStandardVisits > 0)
        '${reading.offStandardVisits} weighing past 60 months',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in reading.points)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              '${p.ageMonths.toStringAsFixed(1)} months · '
              '${p.weightKg.toStringAsFixed(1)} kg · '
              '${p.z >= 0 ? '+' : ''}${RoadToHealth.zText(p.z)} SD',
              style: AppType.caption.copyWith(
                fontSize: 12,
                color: AppColors.inkMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        if (omitted.isNotEmpty)
          Text(
            'Not plotted: ${omitted.join(' and ')}. A break in the line is a '
            'missing weighing, not a child who stopped growing.',
            style: AppType.caption.copyWith(
              fontSize: 11,
              height: 1.4,
              color: AppColors.inkFaint,
            ),
          ),
      ],
    );
  }
}

class _GapNote extends StatelessWidget {
  const _GapNote({required this.gap});

  final RoadToHealthGap gap;

  @override
  Widget build(BuildContext context) => Text(
    '${gap.label}. ${gap.detail}',
    style: AppType.body.copyWith(fontSize: 14, color: AppColors.inkMuted),
  );
}
