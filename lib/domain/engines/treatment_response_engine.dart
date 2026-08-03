/// Treatment-response monitoring — closing the loop on SAM care.
///
/// A child admitted to outpatient therapeutic care (OTP) for severe acute
/// malnutrition is not "done" when the RUTF is handed over. The question that
/// decides whether the treatment is working is: **is the child gaining weight
/// fast enough?** The paper card records each weight but nobody computes the
/// rate, so a child who is quietly failing to respond is only noticed when
/// they deteriorate — by which point the window for a cheap fix has closed.
///
/// This engine computes the weight-gain rate in **grams per kilogram per day**
/// — the standard CMAM metric — and compares it against the WHO's programme
/// thresholds:
///
///   * **≥ 10 g/kg/day** — a good response. Continue the plan.
///   * **5–9.9 g/kg/day** — a slow response. Reinforce feeding technique,
///     check for intercurrent illness, follow up closely.
///   * **< 5 g/kg/day** — a poor response. Reassess; the protocol is failing
///     and the child may need inpatient care.
///   * **Weight loss** — treat as deterioration until proven otherwise.
///
/// Like everything else in the app, the arithmetic is shown in words so a CHO
/// can check it against the growth card, and the thresholds are cited rather
/// than hidden.
library;

import '../enums.dart';
import '../entities/core.dart';
import '../entities/visit.dart';

/// How a child on therapeutic feeding is responding, by weight-gain rate.
enum TreatmentResponse {
  good(
    'Responding well',
    'Gaining at least 10 g/kg/day — the expected response to therapeutic '
        'feeding.',
    TriageLevel.routine,
  ),
  slow(
    'Slow response',
    'Gaining 5–9.9 g/kg/day. Not failing, but not the expected pace either.',
    TriageLevel.watch,
  ),
  poor(
    'Poor response',
    'Gaining less than 5 g/kg/day. The current plan is not working.',
    TriageLevel.priority,
  ),
  weightLoss(
    'Losing weight on treatment',
    'Weight has fallen since treatment began. This is deterioration until '
        'proven otherwise.',
    TriageLevel.urgent,
  ),
  insufficientData(
    'Too early to judge',
    'Not enough time between weighings to compute a reliable rate.',
    TriageLevel.watch,
  );

  const TreatmentResponse(this.label, this.meaning, this.triage);
  final String label;
  final String meaning;
  final TriageLevel triage;
}

class TreatmentResponseResult {
  const TreatmentResponseResult({
    required this.response,
    required this.explanation,
    this.gainPerKgPerDay,
    this.totalGainKg,
    this.daysObserved,
    this.findings = const [],
    this.actions = const [],
  });

  final TreatmentResponse response;

  /// Grams of weight gained per kilogram of body weight per day. The standard
  /// CMAM metric. `null` when it could not be computed.
  final double? gainPerKgPerDay;

  final double? totalGainKg;
  final int? daysObserved;

  final String explanation;
  final List<ClinicalFinding> findings;
  final List<RecommendedAction> actions;

  /// True when the child is not gaining adequately and needs a change of
  /// plan, not just continuation.
  bool get needsEscalation =>
      response == TreatmentResponse.poor ||
      response == TreatmentResponse.weightLoss;
}

abstract final class TreatmentResponseEngine {
  static const String _source = 'WHO CMAM / OTP weight-gain monitoring';

  /// WHO programme thresholds, in g/kg/day.
  static const double _goodGain = 10.0;
  static const double _poorGain = 5.0;

  /// Below this many days the rate is too noisy to trust — day-to-day weight
  /// swings with hydration. Return "too early" rather than a misleading rate.
  static const int _minimumReliableDays = 3;

  /// Computes the weight-gain rate between two weighings and classifies the
  /// response against WHO CMAM thresholds.
  ///
  /// The rate uses the **average** of the two weights as the denominator
  /// (grams gained ÷ days ÷ average weight in kg), which is symmetric and
  /// stable across a large gain.
  static TreatmentResponseResult assess({
    required double startWeightKg,
    required DateTime startDate,
    required double currentWeightKg,
    required DateTime currentDate,
  }) {
    final days = currentDate.difference(startDate).inDays;

    if (days < _minimumReliableDays) {
      return TreatmentResponseResult(
        response: TreatmentResponse.insufficientData,
        daysObserved: days,
        explanation: 'Only $days day(s) between the two weighings. A reliable '
            'weight-gain rate needs at least $_minimumReliableDays days — '
            'day-to-day weight moves with hydration. Continue the therapeutic '
            'feeding and re-weigh in $_minimumReliableDays–7 days.',
        actions: const [
          RecommendedAction(
            instruction: 'Continue therapeutic feeding and re-weigh in 3–7 '
                'days to establish a reliable trend.',
            urgency: ReferralUrgency.scheduled,
            rationale: 'Weight-gain rate is not reliable over fewer than '
                '3 days.',
            protocolSource: _source,
            isCounselling: true,
          ),
        ],
      );
    }

    final totalGainKg = currentWeightKg - startWeightKg;
    final avgWeightKg = (startWeightKg + currentWeightKg) / 2;
    final gainPerKgPerDay = (totalGainKg * 1000) / days / avgWeightKg;
    final response = _classify(gainPerKgPerDay);

    final explanation = 'From ${_fmt(startWeightKg)} kg to '
        '${_fmt(currentWeightKg)} kg over $days days is '
        '${_fmt(gainPerKgPerDay)} g/kg/day '
        '(total ${totalGainKg >= 0 ? '+' : ''}${_fmt(totalGainKg, decimals: 2)} kg). '
        '${response.meaning}';

    return TreatmentResponseResult(
      response: response,
      gainPerKgPerDay: gainPerKgPerDay,
      totalGainKg: totalGainKg,
      daysObserved: days,
      explanation: explanation,
      findings: [
        ClinicalFinding(
          label: response.label,
          detail: 'Weight-gain rate ${_fmt(gainPerKgPerDay)} g/kg/day over '
              '$days days. ${response.meaning} '
              'Compared against the WHO CMAM thresholds of '
              '≥${_fmt(_goodGain, decimals: 0)} g/kg/day (good) and '
              '<${_fmt(_poorGain, decimals: 0)} g/kg/day (poor).',
          severity: response.triage,
          protocolSource: _source,
          measuredValue: '${_fmt(gainPerKgPerDay)} g/kg/day',
          threshold: '≥ ${_fmt(_goodGain, decimals: 0)} g/kg/day',
          weight: response == TreatmentResponse.weightLoss ? 1 : 0.5,
        ),
      ],
      actions: _actions(response),
    );
  }

  /// Weight-gain monitoring applied to a child's recorded growth series — the
  /// form the result screen uses. The current measurement is compared against
  /// the most recent weight recorded before it, and only when the child is
  /// actually on a feeding programme (SAM or MAM): a well child's routine
  /// weigh-in is not "a good response to treatment", and labelling it as one
  /// would teach CHOs to ignore this line.
  ///
  /// Returns `null` when monitoring does not apply — no current weight, no
  /// earlier weight to compare against, or the child is not malnourished — so
  /// the caller can simply add nothing to the plan.
  static TreatmentResponseResult? assessFromSeries({
    required List<GrowthMeasurement> series,
    required GrowthMeasurement current,
    required NutritionStatus? nutritionStatus,
  }) {
    final onProgramme = nutritionStatus == NutritionStatus.severeAcute ||
        nutritionStatus == NutritionStatus.moderateAcute;
    final currentWeight = current.weightKg;
    if (!onProgramme || currentWeight == null) return null;

    // The start point is the most recent weight recorded before this visit —
    // the gain since the last OTP review, which is what a CHO checks today.
    GrowthMeasurement? start;
    for (final m in series) {
      if (m.weightKg == null) continue;
      if (!m.takenAt.isBefore(current.takenAt)) continue;
      if (start == null || m.takenAt.isAfter(start.takenAt)) start = m;
    }
    if (start == null) return null;

    return assess(
      startWeightKg: start.weightKg!,
      startDate: start.takenAt,
      currentWeightKg: currentWeight,
      currentDate: current.takenAt,
    );
  }

  static TreatmentResponse _classify(double gainPerKgPerDay) {
    if (gainPerKgPerDay < 0) return TreatmentResponse.weightLoss;
    if (gainPerKgPerDay < _poorGain) return TreatmentResponse.poor;
    if (gainPerKgPerDay < _goodGain) return TreatmentResponse.slow;
    return TreatmentResponse.good;
  }

  static List<RecommendedAction> _actions(TreatmentResponse response) =>
      switch (response) {
        TreatmentResponse.good => const [
          RecommendedAction(
            instruction: 'Continue RUTF and feeding counselling. Re-weigh at '
                'the next scheduled OTP visit.',
            urgency: ReferralUrgency.scheduled,
            rationale: 'Weight gain is at the expected ≥10 g/kg/day.',
            protocolSource: _source,
            isCounselling: true,
          ),
        ],
        TreatmentResponse.slow => const [
          RecommendedAction(
            instruction: 'Reinforce feeding technique and RUTF preparation, '
                'check for intercurrent illness, and re-weigh within 3–7 days.',
            urgency: ReferralUrgency.withinTwoDays,
            rationale: 'Gain of 5–9.9 g/kg/day is below the expected pace; '
                'most slow responses correct once technique or illness is '
                'addressed.',
            protocolSource: _source,
            isCounselling: true,
          ),
        ],
        TreatmentResponse.poor => const [
          RecommendedAction(
            instruction: 'Reassess for underlying illness and review the '
                'feeding plan. If the poor response persists, refer for '
                'inpatient therapeutic care.',
            urgency: ReferralUrgency.withinTwoDays,
            rationale: 'Gain below 5 g/kg/day means the current outpatient '
                'plan is not working.',
            protocolSource: _source,
            isReferral: true,
          ),
        ],
        TreatmentResponse.weightLoss => const [
          RecommendedAction(
            instruction: 'Refer for urgent reassessment — weight loss on '
                'therapeutic feeding is a danger sign.',
            urgency: ReferralUrgency.sameDay,
            rationale: 'A child losing weight on treatment needs immediate '
                'clinical review for sepsis, malabsorption or another '
                'underlying cause.',
            protocolSource: _source,
            isReferral: true,
          ),
        ],
        TreatmentResponse.insufficientData => const [],
      };

  static String _fmt(double v, {int decimals = 1}) => v.toStringAsFixed(decimals);
}
