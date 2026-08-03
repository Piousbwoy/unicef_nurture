/// WHO Child Growth Standards (2006) — weight-for-height reference data.
///
/// This file carries the **LMS parameters** (Lambda–Mu–Sigma) that turn a
/// child's weight and height into a **weight-for-height z-score (WHZ)** — the
/// WHO's indicator for *wasting* (acute malnutrition). MUAC bands alone miss
/// a child whose weight has collapsed but whose arm is still just above the
/// tape's cut-off; WHZ catches them, and it is the measure the WHO and Ghana's
/// CMAM protocol use to define severe and moderate acute malnutrition.
///
/// ## The LMS method
///
/// For a measurement `X` (here, weight in kg) and age/height-specific
/// parameters `L`, `M` (the median) and `S` (the coefficient of variation):
///
/// ```
/// z = ((X / M)^L - 1) / (L * S)     when L != 0
/// z = ln(X / M) / S                 when L == 0
/// ```
///
/// This is the exact, published WHO method — no approximation in the formula
/// itself. See: WHO Multicentre Growth Reference Study Group, *WHO Child
/// Growth Standards: Methods and development* (2006).
///
/// ## Data provenance
///
/// The tables below are the **official WHO Child Growth Standards (2006)**
/// weight-for-length LMS parameters, taken verbatim from the CDC's published
/// WHO data files (which reproduce the WHO 2006 standard): see
/// https://www.cdc.gov/growthcharts/who-data-files.htm — "Weight-for-length
/// charts, LMS parameters and selected smoothed weight percentiles in
/// kilograms, by recumbent length (in centimeters)". They are sampled at
/// 1 cm steps (45–103.5 cm) and the engine interpolates between samples.
///
/// The engine **never extrapolates**: a height outside the tabulated range
/// returns "insufficient reference data" rather than a guessed z-score, so the
/// app can only ever be *conservative*, never wrong. Above 103.5 cm the MUAC
/// band continues to screen, so no child is left unassessed.
library;

import '../../domain/enums.dart';

/// One LMS sample: the parameters needed to compute a z-score at a given
/// height.
class LmsPoint {
  const LmsPoint(this.heightCm, this.l, this.m, this.s);

  /// Height in centimetres this sample applies to.
  final double heightCm;

  /// Lambda — the Box–Cox power that normalises the skew of the distribution.
  final double l;

  /// Mu — the median weight (kg) at this height.
  final double m;

  /// Sigma — the coefficient of variation.
  final double s;
}

/// Weight-for-length LMS reference, sampled at 1 cm steps from 45 to 103.5 cm.
///
/// Covers the programme-relevant range for children roughly 6–59 months.
/// Below 45 cm or above 103.5 cm the engine declines to compute rather than
/// extrapolate.
abstract final class GrowthReference {
  /// Boys, weight-for-length. WHO Child Growth Standards (2006), official LMS
  /// parameters (45–103.5 cm, 1 cm steps).
  static const List<LmsPoint> weightForHeightBoys = [
    LmsPoint(45, 1.44903689, 2.289757735, 0.149236691),
    LmsPoint(45.5, 1.31794165, 2.38617219, 0.144790131),
    LmsPoint(46.5, 1.041730589, 2.587097922, 0.1365472),
    LmsPoint(47.5, 0.756615683, 2.797952593, 0.129156077),
    LmsPoint(48.5, 0.472617587, 3.017679791, 0.122589498),
    LmsPoint(49.5, 0.197455933, 3.245225583, 0.116802688),
    LmsPoint(50.5, -0.063272822, 3.479567767, 0.111734963),
    LmsPoint(51.5, -0.305663778, 3.719739648, 0.107316407),
    LmsPoint(52.5, -0.527210764, 3.964838222, 0.10347453),
    LmsPoint(53.5, -0.726356263, 4.214033476, 0.100139369),
    LmsPoint(54.5, -0.902380499, 4.466562625, 0.097246097),
    LmsPoint(55.5, -1.055126826, 4.721730669, 0.09473644),
    LmsPoint(56.5, -1.184933443, 4.978903744, 0.092558749),
    LmsPoint(57.5, -1.292531809, 5.237504753, 0.09066765),
    LmsPoint(58.5, -1.378973111, 5.497008915, 0.089023438),
    LmsPoint(59.5, -1.445563111, 5.756939907, 0.087591418),
    LmsPoint(60.5, -1.49380121, 6.016866693, 0.086341291),
    LmsPoint(61.5, -1.525332827, 6.276400575, 0.085246598),
    LmsPoint(62.5, -1.541839648, 6.535195541, 0.084284401),
    LmsPoint(63.5, -1.545098045, 6.792942366, 0.083434649),
    LmsPoint(64.5, -1.536863318, 7.049370425, 0.08268004),
    LmsPoint(65.5, -1.518786093, 7.304248994, 0.082005843),
    LmsPoint(66.5, -1.49249029, 7.557381995, 0.081399411),
    LmsPoint(67.5, -1.459487925, 7.808610136, 0.080850107),
    LmsPoint(68.5, -1.421167427, 8.057810266, 0.08034908),
    LmsPoint(69.5, -1.378835366, 8.304892397, 0.079888977),
    LmsPoint(70.5, -1.333634661, 8.549802669, 0.079463915),
    LmsPoint(71.5, -1.286605147, 8.792519752, 0.079069193),
    LmsPoint(72.5, -1.238665517, 9.033054944, 0.07870118),
    LmsPoint(73.5, -1.19066716, 9.271448675, 0.078357096),
    LmsPoint(74.5, -1.143316882, 9.507773605, 0.078035021),
    LmsPoint(75.5, -1.097263403, 9.742129356, 0.077733651),
    LmsPoint(76.5, -1.053083813, 9.974642178, 0.077452242),
    LmsPoint(77.5, -1.011294273, 10.20546331, 0.077190512),
    LmsPoint(78.5, -0.972360231, 10.43476723, 0.076948562),
    LmsPoint(79.5, -0.936705887, 10.66274993, 0.076726804),
    LmsPoint(80.5, -0.904722736, 10.88962699, 0.076525901),
    LmsPoint(81.5, -0.876777097, 11.11563177, 0.076346711),
    LmsPoint(82.5, -0.853216568, 11.34101346, 0.076190236),
    LmsPoint(83.5, -0.834375406, 11.56603512, 0.076057579),
    LmsPoint(84.5, -0.820578855, 11.79097176, 0.075949901),
    LmsPoint(85.5, -0.81214646, 12.01610828, 0.075868383),
    LmsPoint(86.5, -0.809394398, 12.24173753, 0.075814185),
    LmsPoint(87.5, -0.812636889, 12.46815824, 0.075788413),
    LmsPoint(88.5, -0.822186712, 12.69567298, 0.075792075),
    LmsPoint(89.5, -0.838354876, 12.92458613, 0.075826044),
    LmsPoint(90.5, -0.861449493, 13.15520182, 0.075891019),
    LmsPoint(91.5, -0.891773904, 13.38782185, 0.075987476),
    LmsPoint(92.5, -0.929617736, 13.6227442, 0.076115636),
    LmsPoint(93.5, -0.975268944, 13.86025986, 0.076275395),
    LmsPoint(94.5, -1.028990493, 14.10065234, 0.076466299),
    LmsPoint(95.5, -1.091024455, 14.34419522, 0.076687482),
    LmsPoint(96.5, -1.161574946, 14.59115139, 0.076937631),
    LmsPoint(97.5, -1.240820737, 14.84177007, 0.077214912),
    LmsPoint(98.5, -1.328879402, 15.0962879, 0.077516968),
    LmsPoint(99.5, -1.425809463, 15.35492729, 0.077840877),
    LmsPoint(100.5, -1.531575592, 15.61789822, 0.078183177),
    LmsPoint(101.5, -1.646081976, 15.88539464, 0.078539804),
    LmsPoint(102.5, -1.769082483, 16.15760201, 0.078906277),
    LmsPoint(103.5, -1.900221246, 16.43469418, 0.079277694),
  ];

  /// Girls, weight-for-length. WHO Child Growth Standards (2006), official LMS
  /// parameters (45–103.5 cm, 1 cm steps).
  static const List<LmsPoint> weightForHeightGirls = [
    LmsPoint(45, 0.666839915, 2.305396985, 0.168969897),
    LmsPoint(45.5, 0.699616404, 2.403256702, 0.157654766),
    LmsPoint(46.5, 0.747915684, 2.606020484, 0.139389663),
    LmsPoint(47.5, 0.751754737, 2.817114082, 0.125837223),
    LmsPoint(48.5, 0.691329975, 3.035356101, 0.115888948),
    LmsPoint(49.5, 0.559107556, 3.259693318, 0.108648608),
    LmsPoint(50.5, 0.361549127, 3.48922017, 0.103402703),
    LmsPoint(51.5, 0.116436203, 3.723195489, 0.099599651),
    LmsPoint(52.5, -0.152509094, 3.961034945, 0.096830356),
    LmsPoint(53.5, -0.421478627, 4.202270022, 0.09480477),
    LmsPoint(54.5, -0.671388289, 4.446476028, 0.093323068),
    LmsPoint(55.5, -0.889973526, 4.693220151, 0.092246459),
    LmsPoint(56.5, -1.071844454, 4.942029343, 0.091473166),
    LmsPoint(57.5, -1.216671445, 5.192403337, 0.090923715),
    LmsPoint(58.5, -1.327360462, 5.443830096, 0.090532906),
    LmsPoint(59.5, -1.408261687, 5.69581328, 0.090246768),
    LmsPoint(60.5, -1.464051065, 5.947889759, 0.090021128),
    LmsPoint(61.5, -1.499105627, 6.199640267, 0.089820688),
    LmsPoint(62.5, -1.517197913, 6.450695818, 0.089618171),
    LmsPoint(63.5, -1.521479703, 6.700736725, 0.089393174),
    LmsPoint(64.5, -1.514481331, 6.949493534, 0.089131254),
    LmsPoint(65.5, -1.498204976, 7.196744733, 0.088822943),
    LmsPoint(66.5, -1.474231858, 7.442313819, 0.088462854),
    LmsPoint(67.5, -1.443808911, 7.686067039, 0.088048963),
    LmsPoint(68.5, -1.407959107, 7.92790936, 0.087581916),
    LmsPoint(69.5, -1.367521025, 8.167783677, 0.087064605),
    LmsPoint(70.5, -1.32324327, 8.405666621, 0.086501667),
    LmsPoint(71.5, -1.275834578, 8.641566305, 0.085899159),
    LmsPoint(72.5, -1.226014257, 8.875519723, 0.085264271),
    LmsPoint(73.5, -1.174555804, 9.107590221, 0.084605096),
    LmsPoint(74.5, -1.122323639, 9.337865054, 0.083930435),
    LmsPoint(75.5, -1.070302348, 9.566453061, 0.083249631),
    LmsPoint(76.5, -1.019617172, 9.793482492, 0.082572421),
    LmsPoint(77.5, -0.971544123, 10.01909902, 0.081908788),
    LmsPoint(78.5, -0.927495981, 10.24346467, 0.081268832),
    LmsPoint(79.5, -0.889046221, 10.46675386, 0.080662561),
    LmsPoint(80.5, -0.857844783, 10.6891553, 0.080099785),
    LmsPoint(81.5, -0.835600041, 10.91086924, 0.079589888),
    LmsPoint(82.5, -0.824007806, 11.13210717, 0.079141623),
    LmsPoint(83.5, -0.824673085, 11.35309164, 0.078762888),
    LmsPoint(84.5, -0.839021353, 11.57405623, 0.078460511),
    LmsPoint(85.5, -0.868191531, 11.79524697, 0.078240047),
    LmsPoint(86.5, -0.912987527, 12.0169203, 0.078105554),
    LmsPoint(87.5, -0.973732843, 12.23934838, 0.078059544),
    LmsPoint(88.5, -1.050238631, 12.46281861, 0.078102898),
    LmsPoint(89.5, -1.141750538, 12.68763627, 0.078234935),
    LmsPoint(90.5, -1.246935039, 12.9141268, 0.078453576),
    LmsPoint(91.5, -1.363881842, 13.1426393, 0.078755652),
    LmsPoint(92.5, -1.490235591, 13.37354263, 0.079137144),
    LmsPoint(93.5, -1.623204367, 13.60723197, 0.079593737),
    LmsPoint(94.5, -1.759750536, 13.84412275, 0.080121122),
    LmsPoint(95.5, -1.896722704, 14.08464853, 0.080715361),
    LmsPoint(96.5, -2.031079769, 14.32925018, 0.081372938),
    LmsPoint(97.5, -2.159985258, 14.57837334, 0.082090922),
    LmsPoint(98.5, -2.280992946, 14.8324557, 0.082866693),
    LmsPoint(99.5, -2.392125361, 15.09192012, 0.083697706),
    LmsPoint(100.5, -2.491985117, 15.35716167, 0.08458092),
    LmsPoint(101.5, -2.579688446, 15.62854849, 0.085512655),
    LmsPoint(102.5, -2.654922113, 15.90640903, 0.086487929),
    LmsPoint(103.5, -2.717782155, 16.19103966, 0.087500575),
  ];

  /// The reference series for a given sex.
  static List<LmsPoint> weightForHeight(Sex sex) =>
      sex == Sex.male ? weightForHeightBoys : weightForHeightGirls;

  /// The shortest and tallest heights the bundled table covers. Outside this
  /// span the engine returns insufficient-reference-data rather than guess.
  static double minHeight(Sex sex) => weightForHeight(sex).first.heightCm;
  static double maxHeight(Sex sex) => weightForHeight(sex).last.heightCm;

  /// Linearly interpolates the LMS parameters for an arbitrary height between
  /// two sampled points. Returns `null` when the height is outside the table.
  ///
  /// With the official 1 cm tables, linear interpolation of L, M and S between
  /// adjacent samples is accurate to well within programmatic tolerance.
  static LmsPoint? interpolate(Sex sex, double heightCm) {
    final table = weightForHeight(sex);
    if (heightCm < table.first.heightCm || heightCm > table.last.heightCm) {
      return null;
    }
    for (var i = 0; i < table.length - 1; i++) {
      final lo = table[i];
      final hi = table[i + 1];
      if (heightCm >= lo.heightCm && heightCm <= hi.heightCm) {
        if (hi.heightCm == lo.heightCm) return lo;
        final t = (heightCm - lo.heightCm) / (hi.heightCm - lo.heightCm);
        return LmsPoint(
          heightCm,
          lo.l + t * (hi.l - lo.l),
          lo.m + t * (hi.m - lo.m),
          lo.s + t * (hi.s - lo.s),
        );
      }
    }
    return null;
  }
}
