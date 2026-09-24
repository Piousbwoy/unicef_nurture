/// WHO Child Growth Standards (2006) — weight-for-age reference data.
///
/// This is the table behind the Road-to-Health chart: a child's weight placed
/// against the WHO median for their age in months and sex, which is what the
/// green / yellow / red zones on a Ghanaian Road to Health card mean.
///
/// ## Data provenance — verbatim, and checkable
///
/// The `L`, `M` and `S` columns below are the official WHO Child Growth
/// Standards (2006) weight-for-age LMS parameters for 0–60 months, taken
/// directly from the two workbooks the WHO publishes for this indicator:
///
///   * boys:  https://cdn.who.int/media/docs/default-source/child-growth/child-growth-standards/indicators/weight-for-age/wfa_boys_0-to-5-years_zscores.xlsx
///   * girls: https://cdn.who.int/media/docs/default-source/child-growth/child-growth-standards/indicators/weight-for-age/wfa_girls_0-to-5-years_zscores.xlsx
///
/// Those same workbooks publish the weight at every z-score from −3 to +3 SD
/// for each month, rounded to 0.1 kg. That published column is the check on
/// this file: [WeightForAgeReference.weightAt] inverts the LMS formula from
/// `L`, `M` and `S` alone, and all 854 published values (both sexes, 0–60
/// months, seven z-scores) round to exactly what the WHO prints — the largest
/// gap was 0.05 kg, which is the WHO's own rounding step. Nothing here is
/// fitted, smoothed or hand-picked.
///
/// ## The LMS method
///
/// ```
/// z = ((X / M)^L − 1) / (L · S)      when L != 0
/// z = ln(X / M) / S                  when L == 0
/// X = M · (1 + L · S · z)^(1 / L)    inverted, for a curve at a chosen z
/// ```
///
/// The same arithmetic drives `GrowthZScoreEngine`, against the *height*-indexed
/// table in `growth_reference.dart`. Two indicators, one formula, so the chart
/// and the wasting finding can never disagree about what a z-score is.
///
/// ## Where this must not be stretched
///
///   * **No extrapolation.** Nothing is produced outside 0–60 months. The chart
///     says the child is past the end of the standard rather than drawing a
///     curve WHO does not publish.
///   * **Between whole months** L, M and S are interpolated linearly from the
///     adjacent tabulated months. The WHO tables are monthly, so this reads the
///     standard between its samples; it is not a separate claim.
///   * **Weight-for-age is a composite.** A low line can mean a child is thin,
///     short, or both, and this table cannot tell them apart. That is why the
///     chart sits beside the MUAC tape and the weight-for-height z-score rather
///     than instead of them.
library;

import 'dart:math' as math;

import '../../domain/enums.dart';

/// One month of the WHO weight-for-age standard: the LMS parameters that place
/// a weight at that age and sex on the WHO distribution.
class AgeLmsPoint {
  const AgeLmsPoint(this.month, this.l, this.m, this.s);

  /// Age in whole months this row applies to.
  final double month;

  /// Lambda — the Box–Cox power that normalises the skew of the distribution.
  final double l;

  /// Mu — the WHO median weight (kg) at this age and sex.
  final double m;

  /// Sigma — the coefficient of variation.
  final double s;
}

/// The WHO 2006 weight-for-age standard, and the only place that formula is
/// allowed to live.
abstract final class WeightForAgeReference {
  /// The span the WHO publishes, in months. Outside it, nothing is computed.
  static const double minAgeMonths = 0;
  static const double maxAgeMonths = 60;

  /// Boys, weight-for-age LMS parameters, 0–60 months, one row per month.
  static const List<AgeLmsPoint> boys = [
    AgeLmsPoint(0, 0.3487, 3.3464, 0.14602),
    AgeLmsPoint(1, 0.2297, 4.4709, 0.13395),
    AgeLmsPoint(2, 0.197, 5.5675, 0.12385),
    AgeLmsPoint(3, 0.1738, 6.3762, 0.11727),
    AgeLmsPoint(4, 0.1553, 7.0023, 0.11316),
    AgeLmsPoint(5, 0.1395, 7.5105, 0.1108),
    AgeLmsPoint(6, 0.1257, 7.934, 0.10958),
    AgeLmsPoint(7, 0.1134, 8.297, 0.10902),
    AgeLmsPoint(8, 0.1021, 8.6151, 0.10882),
    AgeLmsPoint(9, 0.0917, 8.9014, 0.10881),
    AgeLmsPoint(10, 0.082, 9.1649, 0.10891),
    AgeLmsPoint(11, 0.073, 9.4122, 0.10906),
    AgeLmsPoint(12, 0.0644, 9.6479, 0.10925),
    AgeLmsPoint(13, 0.0563, 9.8749, 0.10949),
    AgeLmsPoint(14, 0.0487, 10.0953, 0.10976),
    AgeLmsPoint(15, 0.0413, 10.3108, 0.11007),
    AgeLmsPoint(16, 0.0343, 10.5228, 0.11041),
    AgeLmsPoint(17, 0.0275, 10.7319, 0.11079),
    AgeLmsPoint(18, 0.0211, 10.9385, 0.11119),
    AgeLmsPoint(19, 0.0148, 11.143, 0.11164),
    AgeLmsPoint(20, 0.0087, 11.3462, 0.11211),
    AgeLmsPoint(21, 0.0029, 11.5486, 0.11261),
    AgeLmsPoint(22, -0.0028, 11.7504, 0.11314),
    AgeLmsPoint(23, -0.0083, 11.9514, 0.11369),
    AgeLmsPoint(24, -0.0137, 12.1515, 0.11426),
    AgeLmsPoint(25, -0.0189, 12.3502, 0.11485),
    AgeLmsPoint(26, -0.024, 12.5466, 0.11544),
    AgeLmsPoint(27, -0.0289, 12.7401, 0.11604),
    AgeLmsPoint(28, -0.0337, 12.9303, 0.11664),
    AgeLmsPoint(29, -0.0385, 13.1169, 0.11723),
    AgeLmsPoint(30, -0.0431, 13.3, 0.11781),
    AgeLmsPoint(31, -0.0476, 13.4798, 0.11839),
    AgeLmsPoint(32, -0.052, 13.6567, 0.11896),
    AgeLmsPoint(33, -0.0564, 13.8309, 0.11953),
    AgeLmsPoint(34, -0.0606, 14.0031, 0.12008),
    AgeLmsPoint(35, -0.0648, 14.1736, 0.12062),
    AgeLmsPoint(36, -0.0689, 14.3429, 0.12116),
    AgeLmsPoint(37, -0.0729, 14.5113, 0.12168),
    AgeLmsPoint(38, -0.0769, 14.6791, 0.1222),
    AgeLmsPoint(39, -0.0808, 14.8466, 0.12271),
    AgeLmsPoint(40, -0.0846, 15.014, 0.12322),
    AgeLmsPoint(41, -0.0883, 15.1813, 0.12373),
    AgeLmsPoint(42, -0.092, 15.3486, 0.12425),
    AgeLmsPoint(43, -0.0957, 15.5158, 0.12478),
    AgeLmsPoint(44, -0.0993, 15.6828, 0.12531),
    AgeLmsPoint(45, -0.1028, 15.8497, 0.12586),
    AgeLmsPoint(46, -0.1063, 16.0163, 0.12643),
    AgeLmsPoint(47, -0.1097, 16.1827, 0.127),
    AgeLmsPoint(48, -0.1131, 16.3489, 0.12759),
    AgeLmsPoint(49, -0.1165, 16.515, 0.12819),
    AgeLmsPoint(50, -0.1198, 16.6811, 0.1288),
    AgeLmsPoint(51, -0.123, 16.8471, 0.12943),
    AgeLmsPoint(52, -0.1262, 17.0132, 0.13005),
    AgeLmsPoint(53, -0.1294, 17.1792, 0.13069),
    AgeLmsPoint(54, -0.1325, 17.3452, 0.13133),
    AgeLmsPoint(55, -0.1356, 17.5111, 0.13197),
    AgeLmsPoint(56, -0.1387, 17.6768, 0.13261),
    AgeLmsPoint(57, -0.1417, 17.8422, 0.13325),
    AgeLmsPoint(58, -0.1447, 18.0073, 0.13389),
    AgeLmsPoint(59, -0.1477, 18.1722, 0.13453),
    AgeLmsPoint(60, -0.1506, 18.3366, 0.13517),
  ];

  /// Girls, weight-for-age LMS parameters, 0–60 months, one row per month.
  static const List<AgeLmsPoint> girls = [
    AgeLmsPoint(0, 0.3809, 3.2322, 0.14171),
    AgeLmsPoint(1, 0.1714, 4.1873, 0.13724),
    AgeLmsPoint(2, 0.0962, 5.1282, 0.13),
    AgeLmsPoint(3, 0.0402, 5.8458, 0.12619),
    AgeLmsPoint(4, -0.005, 6.4237, 0.12402),
    AgeLmsPoint(5, -0.043, 6.8985, 0.12274),
    AgeLmsPoint(6, -0.0756, 7.297, 0.12204),
    AgeLmsPoint(7, -0.1039, 7.6422, 0.12178),
    AgeLmsPoint(8, -0.1288, 7.9487, 0.12181),
    AgeLmsPoint(9, -0.1507, 8.2254, 0.12199),
    AgeLmsPoint(10, -0.17, 8.48, 0.12223),
    AgeLmsPoint(11, -0.1872, 8.7192, 0.12247),
    AgeLmsPoint(12, -0.2024, 8.9481, 0.12268),
    AgeLmsPoint(13, -0.2158, 9.1699, 0.12283),
    AgeLmsPoint(14, -0.2278, 9.387, 0.12294),
    AgeLmsPoint(15, -0.2384, 9.6008, 0.12299),
    AgeLmsPoint(16, -0.2478, 9.8124, 0.12303),
    AgeLmsPoint(17, -0.2562, 10.0226, 0.12306),
    AgeLmsPoint(18, -0.2637, 10.2315, 0.12309),
    AgeLmsPoint(19, -0.2703, 10.4393, 0.12315),
    AgeLmsPoint(20, -0.2762, 10.6464, 0.12323),
    AgeLmsPoint(21, -0.2815, 10.8534, 0.12335),
    AgeLmsPoint(22, -0.2862, 11.0608, 0.1235),
    AgeLmsPoint(23, -0.2903, 11.2688, 0.12369),
    AgeLmsPoint(24, -0.2941, 11.4775, 0.1239),
    AgeLmsPoint(25, -0.2975, 11.6864, 0.12414),
    AgeLmsPoint(26, -0.3005, 11.8947, 0.12441),
    AgeLmsPoint(27, -0.3032, 12.1015, 0.12472),
    AgeLmsPoint(28, -0.3057, 12.3059, 0.12506),
    AgeLmsPoint(29, -0.308, 12.5073, 0.12545),
    AgeLmsPoint(30, -0.3101, 12.7055, 0.12587),
    AgeLmsPoint(31, -0.312, 12.9006, 0.12633),
    AgeLmsPoint(32, -0.3138, 13.093, 0.12683),
    AgeLmsPoint(33, -0.3155, 13.2837, 0.12737),
    AgeLmsPoint(34, -0.3171, 13.4731, 0.12794),
    AgeLmsPoint(35, -0.3186, 13.6618, 0.12855),
    AgeLmsPoint(36, -0.3201, 13.8503, 0.12919),
    AgeLmsPoint(37, -0.3216, 14.0385, 0.12988),
    AgeLmsPoint(38, -0.323, 14.2265, 0.13059),
    AgeLmsPoint(39, -0.3243, 14.414, 0.13135),
    AgeLmsPoint(40, -0.3257, 14.601, 0.13213),
    AgeLmsPoint(41, -0.327, 14.7873, 0.13293),
    AgeLmsPoint(42, -0.3283, 14.9727, 0.13376),
    AgeLmsPoint(43, -0.3296, 15.1573, 0.1346),
    AgeLmsPoint(44, -0.3309, 15.341, 0.13545),
    AgeLmsPoint(45, -0.3322, 15.524, 0.1363),
    AgeLmsPoint(46, -0.3335, 15.7064, 0.13716),
    AgeLmsPoint(47, -0.3348, 15.8882, 0.138),
    AgeLmsPoint(48, -0.3361, 16.0697, 0.13884),
    AgeLmsPoint(49, -0.3374, 16.2511, 0.13968),
    AgeLmsPoint(50, -0.3387, 16.4322, 0.14051),
    AgeLmsPoint(51, -0.34, 16.6133, 0.14132),
    AgeLmsPoint(52, -0.3414, 16.7942, 0.14213),
    AgeLmsPoint(53, -0.3427, 16.9748, 0.14293),
    AgeLmsPoint(54, -0.344, 17.1551, 0.14371),
    AgeLmsPoint(55, -0.3453, 17.3347, 0.14448),
    AgeLmsPoint(56, -0.3466, 17.5136, 0.14525),
    AgeLmsPoint(57, -0.3479, 17.6916, 0.146),
    AgeLmsPoint(58, -0.3492, 17.8686, 0.14675),
    AgeLmsPoint(59, -0.3505, 18.0445, 0.14748),
    AgeLmsPoint(60, -0.3518, 18.2193, 0.14821),
  ];

  /// The reference series for a given sex.
  static List<AgeLmsPoint> forSex(Sex sex) => sex == Sex.male ? boys : girls;

  /// True when [ageMonths] lies inside the span the WHO publishes.
  static bool covers(double ageMonths) =>
      ageMonths >= minAgeMonths && ageMonths <= maxAgeMonths;

  /// The LMS parameters at an age between two tabulated months, or null when
  /// the age falls outside 0–60 months. Never an extrapolated guess.
  static AgeLmsPoint? lmsAt(Sex sex, double ageMonths) {
    if (!covers(ageMonths)) return null;
    final table = forSex(sex);
    final lo = ageMonths.floor().clamp(0, table.length - 1);
    final hi = ageMonths.ceil().clamp(0, table.length - 1);
    final a = table[lo];
    final b = table[hi];
    if (lo == hi) return a;
    final t = (ageMonths - a.month) / (b.month - a.month);
    return AgeLmsPoint(
      ageMonths,
      a.l + t * (b.l - a.l),
      a.m + t * (b.m - a.m),
      a.s + t * (b.s - a.s),
    );
  }

  /// A child's weight-for-age z-score against the standard, or null when it
  /// cannot be placed: an age outside the standard, or a weight too broken to
  /// mean anything. A null here is an honest refusal, not a zero.
  static double? zScore({
    required Sex sex,
    required double ageMonths,
    required double weightKg,
  }) {
    final lms = lmsAt(sex, ageMonths);
    if (lms == null || weightKg <= 0) return null;
    final ratio = weightKg / lms.m;
    if (lms.l == 0) return math.log(ratio) / lms.s;
    return (math.pow(ratio, lms.l).toDouble() - 1) / (lms.l * lms.s);
  }

  /// The WHO weight (kg) at [z] standard deviations from the median for this
  /// age and sex — one point on a chart curve, or null outside the standard.
  static double? weightAt(Sex sex, double ageMonths, double z) {
    final lms = lmsAt(sex, ageMonths);
    if (lms == null) return null;
    if (lms.l == 0) return lms.m * math.exp(z * lms.s);
    final base = 1 + lms.l * lms.s * z;
    // The Box–Cox inverse is undefined for a non-positive base, which happens
    // far out on the negative-L tail. Refuse rather than emit a NaN that would
    // tear the chart open.
    if (base <= 0) return null;
    return lms.m * math.pow(base, 1 / lms.l);
  }
}
