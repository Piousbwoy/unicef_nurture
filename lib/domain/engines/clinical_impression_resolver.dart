/// Names the child's condition, ranked the way the IMCI chart ranks it.
///
/// The verdict page previously showed every engine's classification joined with
/// " + ", which reads like a pile of stamps rather than a diagnosis. A nurse
/// needs one condition first — the one that kills the child — with the
/// measurement that produced it, and the rest kept on the record below.
///
/// This resolver does not decide treatment, triage or referral. Those stay
/// where they always were: in the guideline engines and the synthesizer. All it
/// does is order and translate findings that have already been classified, so
/// the ordering cannot soften a verdict and the translation cannot invent one.
///
/// Classification codes come from the engines themselves:
///   child        VERY SEVERE DISEASE, SEVERE PNEUMONIA OR VERY SEVERE DISEASE,
///                PNEUMONIA, COUGH OR COLD, SEVERE/SOME/NO DEHYDRATION,
///                PERSISTENT DIARRHOEA, DYSENTERY, VERY SEVERE FEBRILE DISEASE,
///                MALARIA, MEASLES, SEVERE COMPLICATED MEASLES
///   ANC          ECLAMPSIA, SEVERE PRE-ECLAMPSIA, PRE-ECLAMPSIA, GESTATIONAL
///                HYPERTENSION, SEVERE/MODERATE/MILD ANAEMIA
///   postnatal    POSTPARTUM HAEMORRHAGE, PUERPERAL SEPSIS, FEVER AFTER DELIVERY,
///                POSTPARTUM ECLAMPSIA, SEVERE POSTPARTUM HYPERTENSION
///
/// A code this table has not been taught resolves to [ImpressionTier.needsReview]
/// with its original string preserved. Guessing a tier for an unfamiliar code
/// would be exactly the invention this file exists to avoid.
library;

import '../entities/visit.dart';

/// Where the named condition sends the patient, per the guideline's own column
/// header. Ordered from most urgent — the index is the sort key.
enum ImpressionTier {
  /// Refer now, after any pre-referral dose given on the spot.
  emergency,

  /// Treat here and follow up — real disease, no transport needed.
  treat,

  /// Supportive home care with danger-sign advice.
  supportive,

  /// Not a condition: a test the guideline requires has not been done.
  needsTest,

  /// A classification this resolver has not been taught. Never silently ranked.
  needsReview,

  /// Nothing classified.
  well,
}

/// One measurement or sign, quoted with the cut-off it crossed.
class ImpressionEvidence {
  const ImpressionEvidence({
    required this.label,
    this.measuredValue,
    this.threshold,
    this.protocolSource,
  });

  final String label;
  final String? measuredValue;
  final String? threshold;
  final String? protocolSource;

  /// The line a worker can defend at the facility gate: the sign, the number,
  /// and the threshold that made it count.
  String get statement {
    if (measuredValue == null) return label;
    final cut = threshold == null ? '' : ' (cut-off $threshold)';
    return '$label · $measuredValue$cut';
  }
}

/// The single ranked condition, in the form the result screen shows.
class ClinicalImpression {
  const ClinicalImpression({
    required this.tier,
    required this.conditionName,
    required this.recordCode,
    required this.headline,
    required this.plainWords,
    required this.evidence,
    required this.alsoPresent,
    required this.unresolved,
    required this.needsReferral,
  });

  final ImpressionTier tier;

  /// Human-facing name, e.g. "Severe pneumonia".
  final String conditionName;

  /// The engine's own classification string, kept verbatim for the register.
  final String recordCode;

  /// The action sentence: "Refer now — after the first dose here."
  final String headline;

  /// One plain sentence for the family and the worker, with no code words in it.
  final String plainWords;

  /// The signs and measurements that produced this condition.
  final List<ImpressionEvidence> evidence;

  /// Every other classification, still on the record, ranked behind the first.
  final List<String> alsoPresent;

  /// Codes that name a required test rather than a disease.
  final List<String> unresolved;

  final bool needsReferral;
}

/// A code's meaning, as taught to this resolver.
class _CodeRule {
  const _CodeRule({
    required this.tier,
    required this.name,
    required this.words,
    this.keywords = const [],
  });

  final ImpressionTier tier;
  final String name;
  final String words;

  /// Finding labels that evidence this code, lower-cased for matching.
  final List<String> keywords;
}

abstract final class ClinicalImpressionResolver {
  /// The guideline's own disposition for each classification the engines emit.
  static const Map<String, _CodeRule> _codes = {
    // ── Child: IMCI sick-child classifications ──────────────────────────
    'VERY SEVERE DISEASE': _CodeRule(
      tier: ImpressionTier.emergency,
      name: 'Very severe disease',
      words:
          'A general danger sign was found. The child may not be able to drink, '
          'is vomiting everything, is convulsing or is unusually sleepy — any '
          'one of these means the illness is deep and needs a hospital now.',
      keywords: ['danger sign', 'not able to drink', 'vomits everything', 'convuls', 'sleepy', 'unconscious'],
    ),
    'SEVERE PNEUMONIA OR VERY SEVERE DISEASE': _CodeRule(
      tier: ImpressionTier.emergency,
      name: 'Severe pneumonia',
      words:
          'The chest pulls in with every breath (or there is a noisy breath at '
          'rest). That is a deep chest infection — the child needs injectable '
          'antibiotic treatment and transport to a facility.',
      keywords: ['chest indrawing', 'stridor'],
    ),
    'VERY SEVERE FEBRILE DISEASE': _CodeRule(
      tier: ImpressionTier.emergency,
      name: 'Very severe febrile illness',
      words:
          'Fever together with a danger sign or a stiff neck. This must be '
          'treated as a serious infection of the blood or the brain until a '
          'facility says otherwise.',
      keywords: ['stiff neck', 'fever with a danger sign'],
    ),
    'SEVERE DEHYDRATION': _CodeRule(
      tier: ImpressionTier.emergency,
      name: 'Severe dehydration',
      words:
          'Two or more severe dehydration signs with diarrhoea or vomiting. The '
          'child has lost too much water to drink it back fast enough and needs '
          'intravenous fluid now.',
      keywords: ['severe dehydration', 'lethargic', 'sunken eyes', 'not able to drink'],
    ),
    'SEVERE COMPLICATED MEASLES': _CodeRule(
      tier: ImpressionTier.emergency,
      name: 'Measles with complications',
      words:
          'Measles with eye, mouth or breathing complications. This needs '
          'facility care and vitamin A given under supervision.',
      keywords: ['measles', 'cornea', 'mouth ulcers'],
    ),
    'PNEUMONIA': _CodeRule(
      tier: ImpressionTier.treat,
      name: 'Pneumonia',
      words:
          'The breathing rate is above the cut-off for this age with no chest '
          'pulling — a chest infection that oral antibiotic treatment clears at '
          'home, with a return date set.',
      keywords: ['fast breathing'],
    ),
    'MALARIA': _CodeRule(
      tier: ImpressionTier.treat,
      name: 'Malaria',
      words:
          'Fever with a positive rapid test. Full-dose antimalarial treatment '
          'starts today, at the dose for this child\'s weight.',
      keywords: ['malaria', 'rdt positive', 'fever'],
    ),
    'DYSENTERY': _CodeRule(
      tier: ImpressionTier.treat,
      name: 'Dysentery',
      words:
          'Blood in the stool. ORS alone will not clear this — it needs the '
          'right antibiotic and a review in two days.',
      keywords: ['blood in the stool', 'dysentery'],
    ),
    'SOME DEHYDRATION': _CodeRule(
      tier: ImpressionTier.treat,
      name: 'Some dehydration',
      words:
          'Plan B: ORS given here over a few hours, then a plan for the rest of '
          'the day at home. Recheck before the child leaves the compound.',
      keywords: ['some dehydration', 'drinks eagerly', 'sunken eyes'],
    ),
    'PERSISTENT DIARRHOEA': _CodeRule(
      tier: ImpressionTier.treat,
      name: 'Persistent diarrhoea',
      words:
          'Diarrhoea of two weeks or more. It damages the gut lining and drives '
          'malnutrition, so feeding support and a facility review are both '
          'needed.',
      keywords: ['persistent diarrhoea', '14 days'],
    ),
    'MEASLES': _CodeRule(
      tier: ImpressionTier.treat,
      name: 'Measles',
      words:
          'Measles without complications today. Nursing, fever control and '
          'vitamin A — and return immediately if the eyes, breathing or alertness '
          'change.',
      keywords: ['measles rash'],
    ),
    'COUGH OR COLD': _CodeRule(
      tier: ImpressionTier.supportive,
      name: 'Cough or cold',
      words:
          'No fast breathing and no chest pulling. This is a simple airway '
          'virus: keep feeding, keep fluids going, and come back if the '
          'breathing speeds up.',
      keywords: ['cough'],
    ),
    'NO DEHYDRATION': _CodeRule(
      tier: ImpressionTier.supportive,
      name: 'Diarrhoea, no dehydration',
      words:
          'Fluids are still balanced. Treat at home with extra fluids, ORS and '
          'zinc, and keep feeding — the plan changes if drinking falls or the '
          'child becomes listless.',
      keywords: ['diarrhoea'],
    ),
    'FEVER — MALARIA UNLIKELY': _CodeRule(
      tier: ImpressionTier.supportive,
      name: 'Fever, malaria unlikely',
      words:
          'Fever with a negative rapid test. Do not give an antimalarial; treat '
          'the fever, look for another source, and return if it persists.',
      keywords: ['negative', 'fever'],
    ),

    // ── A required test is a gap, never a diagnosis ────────────────────
    'FEVER — MALARIA TEST NEEDED': _CodeRule(
      tier: ImpressionTier.needsTest,
      name: 'Fever — malaria test not done',
      words:
          'Fever in a district with year-round transmission, and no rapid test '
          'recorded yet. The verdict cannot be settled until the test is done.',
      keywords: ['fever'],
    ),

    // ── Maternal: ANC ─────────────────────────────────────────────────
    'ECLAMPSIA': _CodeRule(
      tier: ImpressionTier.emergency,
      name: 'Eclampsia',
      words:
          'Convulsions in pregnancy. This is the highest-acuity obstetric '
          'emergency the register carries: magnesium sulfate first, then '
          'transport, with the airway protected throughout.',
      keywords: ['convuls', 'seizure'],
    ),
    'POSTPARTUM ECLAMPSIA': _CodeRule(
      tier: ImpressionTier.emergency,
      name: 'Eclampsia after delivery',
      words:
          'Convulsions in the first weeks after birth. Treat and refer on the '
          'same footing as eclampsia in pregnancy.',
      keywords: ['convuls', 'seizure'],
    ),
    'SEVERE PRE-ECLAMPSIA': _CodeRule(
      tier: ImpressionTier.emergency,
      name: 'Severe pre-eclampsia',
      words:
          'Very high blood pressure with protein, headache, visual disturbance '
          'or upper-abdominal pain. Delivery is the only cure, so this woman '
          'needs a facility now.',
      keywords: ['severe headache', 'blurred vision', 'protein', 'hypertension'],
    ),
    'SEVERE POSTPARTUM HYPERTENSION': _CodeRule(
      tier: ImpressionTier.emergency,
      name: 'Severe hypertension after delivery',
      words:
          'Blood pressure in the severe range after birth. Treat and refer — '
          'postpartum eclampsia is missed more often than the antenatal kind.',
      keywords: ['hypertension', 'blood pressure'],
    ),
    'POSTPARTUM HAEMORRHAGE': _CodeRule(
      tier: ImpressionTier.emergency,
      name: 'Heavy bleeding after delivery',
      words:
          'Bleeding beyond what delivery should produce. Uterine massage and '
          'oxytocin start here, immediately, while transport is arranged.',
      keywords: ['heavy bleeding', 'haemorrhage', 'blood loss'],
    ),
    'PUERPERAL SEPSIS': _CodeRule(
      tier: ImpressionTier.emergency,
      name: 'Childbed sepsis',
      words:
          'Fever with a foul discharge or a tender womb after delivery. '
          'Antibiotics start now; this deteriorates faster than it looks.',
      keywords: ['foul', 'discharge', 'sepsis', 'tender'],
    ),
    'SEVERE ANAEMIA IN PREGNANCY': _CodeRule(
      tier: ImpressionTier.emergency,
      name: 'Severe anaemia in pregnancy',
      words:
          'Haemoglobin low enough that labour would be dangerous. She needs '
          'facility assessment, and delivery must not happen at the compound.',
      keywords: ['haemoglobin', 'anaemia'],
    ),
    'PRE-ECLAMPSIA': _CodeRule(
      tier: ImpressionTier.treat,
      name: 'Pre-eclampsia',
      words:
          'Raised blood pressure with protein in the urine. She needs closer '
          'monitoring, a defined return interval and a clear instruction on '
          'what sends her to hospital.',
      keywords: ['protein', 'blood pressure'],
    ),
    'GESTATIONAL HYPERTENSION': _CodeRule(
      tier: ImpressionTier.treat,
      name: 'Gestational hypertension',
      words:
          'Raised blood pressure without protein. Watch it on a shorter interval '
          'and recheck for the pre-eclampsia symptoms.',
      keywords: ['blood pressure'],
    ),
    'MODERATE ANAEMIA': _CodeRule(
      tier: ImpressionTier.treat,
      name: 'Moderate anaemia',
      words:
          'Haemoglobin in the moderate range. Therapeutic iron, a diet review '
          'against the foods this market sells, and a retest date.',
      keywords: ['haemoglobin', 'anaemia'],
    ),
    'FEVER AFTER DELIVERY': _CodeRule(
      tier: ImpressionTier.treat,
      name: 'Fever after delivery',
      words:
          'Fever in the postpartum period without sepsis signs yet. Find the '
          'source — breast, wound, urine, uterus — and treat before it climbs.',
      keywords: ['fever'],
    ),
    'MILD ANAEMIA': _CodeRule(
      tier: ImpressionTier.supportive,
      name: 'Mild anaemia',
      words:
          'Haemoglobin mildly low. Routine iron and food support, rechecked at '
          'the next scheduled visit.',
      keywords: ['haemoglobin', 'anaemia'],
    ),
  };

  /// Codes that mean "nothing classified", so a well child is named as well
  /// rather than as an empty string.
  static const Set<String> _wellCodes = {
    'WELL CHILD',
    'NO IMCI CLASSIFICATION',
    'NO IMCI CLASSIFICATION — WELL CHILD',
    'ROUTINE CARE',
    'WELL NEWBORN — NO IMCI CLASSIFICATION',
  };

  /// A human-facing name for any classification code, falling back to the code
  /// itself. Screens use this rather than printing an engine's uppercase string.
  static String displayNameFor(String code) => _codes[code]?.name ?? code;

  /// Rank the classifications the engines already produced.
  static ClinicalImpression resolve({
    required List<String> classifications,
    required List<ClinicalFinding> findings,
  }) {
    final codes = classifications.where((c) => c.trim().isNotEmpty).toList();

    if (codes.isEmpty || codes.every(_wellCodes.contains)) {
      return const ClinicalImpression(
        tier: ImpressionTier.well,
        conditionName: 'No illness classified',
        recordCode: 'WELL CHILD',
        headline: 'Nothing found today needs referral',
        plainWords:
            'No danger sign, no fast breathing, no dehydration and no fever '
            'pattern was found. Prevention and feeding are still on the record '
            'below — a well child today is not a finished schedule.',
        evidence: [],
        alsoPresent: [],
        unresolved: [],
        needsReferral: false,
      );
    }

    // Sort by tier, then by the order the engines contributed them, so the
    // same record always reads the same way. A stable secondary key is what
    // makes this reproducible rather than whatever the map iteration produced.
    final ranked = [...codes]
      ..sort((a, b) {
        final ta = _tierOf(a).index;
        final tb = _tierOf(b).index;
        if (ta != tb) return ta.compareTo(tb);
        return codes.indexOf(a).compareTo(codes.indexOf(b));
      });

    final primary = ranked.first;
    final rule = _codes[primary];
    final tier = _tierOf(primary);

    return ClinicalImpression(
      tier: tier,
      conditionName: rule?.name ?? primary,
      recordCode: primary,
      headline: _headlineFor(tier, rule?.name ?? primary),
      plainWords: rule?.words ?? _unreviewedWords(),
      evidence: _evidenceFor(rule, findings),
      alsoPresent: ranked.skip(1).toList(growable: false),
      unresolved: ranked
          .where((c) => _tierOf(c) == ImpressionTier.needsTest)
          .toList(growable: false),
      needsReferral: tier == ImpressionTier.emergency,
    );
  }

  /// An unfamiliar code keeps its own name and asks for a human. Ranking it
  /// would be guessing; dropping it would hide a condition.
  static ImpressionTier _tierOf(String code) {
    final rule = _codes[code];
    if (rule != null) return rule.tier;
    if (_wellCodes.contains(code)) return ImpressionTier.well;
    return ImpressionTier.needsReview;
  }

  static String _headlineFor(ImpressionTier tier, String name) => switch (tier) {
    ImpressionTier.emergency => '$name — refer now, after the dose given here',
    ImpressionTier.treat => '$name — treat here today',
    ImpressionTier.supportive => '$name — home care, with return signs',
    ImpressionTier.needsTest => '$name — a test is needed before this settles',
    ImpressionTier.needsReview => '$name — classification needs review',
    ImpressionTier.well => 'Nothing found today needs referral',
  };

  /// Shown when a classification is real but this table has no wording for it.
  ///
  /// Deliberately two lines, not a paragraph: this sentence appears on urgent
  /// verdicts, where every extra line pushes the referral action further down the
  /// phone. It states the limit, points at the human who can settle it, and says
  /// what is *not* in doubt — the guideline still governs the care.
  static String _unreviewedWords() =>
      'Not in the app\'s wording table, so it is shown exactly as recorded — '
      'confirm the name with the reviewer. Urgency and treatment are not in '
      'doubt: the guideline engines set them.';

  /// The findings that evidence this code. Danger signs are pulled in for the
  /// emergency codes even when the keyword misses, because a general danger
  /// sign is exactly what makes those classifications true.
  static List<ImpressionEvidence> _evidenceFor(
    _CodeRule? rule,
    List<ClinicalFinding> findings,
  ) {
    if (rule == null) return const [];
    final picked = <ClinicalFinding>[];
    for (final f in findings) {
      final label = f.label.toLowerCase();
      final hitsKeyword = rule.keywords.any(label.contains);
      final isDangerSign = f.isDangerSign &&
          rule.tier == ImpressionTier.emergency;
      if (hitsKeyword || isDangerSign) picked.add(f);
    }
    if (picked.isEmpty) return const [];
    picked.sort((a, b) => b.weight.compareTo(a.weight));
    return [
      for (final f in picked)
        ImpressionEvidence(
          label: f.label,
          measuredValue: f.measuredValue,
          threshold: f.threshold,
          protocolSource: f.protocolSource,
        ),
    ];
  }
}
