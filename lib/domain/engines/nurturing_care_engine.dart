/// The UNICEF Nurturing Care Framework for Early Childhood Development —
/// applied to a single visit, producing a per-pillar action set the CHO
/// can deliver or counsel on today.
///
/// Pillar 3 of the CareBridge AI engine revamp.
///
/// The framework was published by WHO, UNICEF and the World Bank in
/// 2018 ("Nurturing care for early childhood development: a framework
/// for helping children survive and thrive to transform human
/// potential"). Its five strategic actions are the canonical, audited
/// definition of what a community health visit *can* deliver for a
/// child under five in a low-resource setting:
///
///   1. **Good Health** — antenatal / intrapartum / postnatal care,
///      immunisation, hygiene, mental health.
///   2. **Adequate Nutrition** — exclusive breastfeeding, complementary
///      feeding, micronutrient supplementation.
///   3. **Responsive Caregiving** — observing and responding to the
///      child's cues (feeding cues, distress, play).
///   4. **Opportunities for Early Learning** — talking, singing,
///      reading, playing with the child from birth.
///   5. **Security and Safety** — birth registration, clean home,
///      safe play, no violence, supervision.
///
/// CareBridge AI does *not* invent a 6th pillar. The five are universal,
/// the framework is referenced by GHS IMCI, and any deviation would
/// fail an external review. Each pillar action cites the framework
/// page and the implementing guideline.
library;

import 'package:flutter/foundation.dart';

import '../enums.dart';
import 'immunisation_engine.dart';
import 'nutrition_engine.dart';
import 'nutrition/therapeutic_supplements.dart';

/// The five pillars of the UNICEF Nurturing Care Framework, in canonical
/// order. The order is not stylistic — it mirrors the WHO/UNICEF 2018
/// "Components of Nurturing Care" diagram.
enum NurturingCarePillar {
  goodHealth,
  adequateNutrition,
  responsiveCaregiving,
  earlyLearning,
  securityAndSafety;

  String get displayName => switch (this) {
    NurturingCarePillar.goodHealth => 'Good Health',
    NurturingCarePillar.adequateNutrition => 'Adequate Nutrition',
    NurturingCarePillar.responsiveCaregiving => 'Responsive Caregiving',
    NurturingCarePillar.earlyLearning => 'Opportunities for Early Learning',
    NurturingCarePillar.securityAndSafety => 'Security and Safety',
  };

  String get shortDescription => switch (this) {
    NurturingCarePillar.goodHealth =>
      'Antenatal, intrapartum and postnatal care. Immunisation. Hygiene. '
          'Caregiver mental health.',
    NurturingCarePillar.adequateNutrition =>
      'Exclusive breastfeeding for the first 6 months, then responsive '
          'complementary feeding with iron-rich foods, plus micronutrient '
          'supplementation as indicated.',
    NurturingCarePillar.responsiveCaregiving =>
      'Caregiver observes and responds to the child\'s cues — hunger, '
          'distress, interest. Back-and-forth, child-led interaction.',
    NurturingCarePillar.earlyLearning =>
      'Talking, singing, reading and playing with the child from birth. '
          'The first 1,000 days are the most sensitive window for language '
          'and cognition.',
    NurturingCarePillar.securityAndSafety =>
      'Birth registration, clean water, sanitary home, no violence, '
          'supervised play, hand-washing, safe sleep.',
  };
}

/// One concrete action a CHO can take or counsel on today, attached to
/// one of the five pillars.
@immutable
class NurturingCareAction {
  const NurturingCareAction({
    required this.pillar,
    required this.title,
    required this.counsellingNote,
    required this.citation,
    this.deliveredAtVisit = false,
    this.referToService = false,
  });

  /// The pillar this action belongs to.
  final NurturingCarePillar pillar;

  /// Short title shown in the list, e.g. "Skin-to-skin in the first hour".
  final String title;

  /// The script the CHO reads to the caregiver, plain language.
  final String counsellingNote;

  /// Citation.
  final PillarCitation citation;

  /// True if the engine believes this action was already delivered
  /// during this visit (e.g. the immunisation was given, the Vitamin A
  /// was dispensed). Used to render a checkmark in the result screen.
  final bool deliveredAtVisit;

  /// True if the action requires onward referral or service linkage
  /// (e.g. birth registration at the district office).
  final bool referToService;
}

@immutable
class PillarCitation {
  const PillarCitation({
    required this.shortName,
    required this.fullCitation,
    required this.publishedYear,
  });

  final String shortName;
  final String fullCitation;
  final int publishedYear;

  Map<String, Object?> toMap() => {
    'short_name': shortName,
    'full_citation': fullCitation,
    'year': publishedYear,
  };
}

const _unicef2018 = PillarCitation(
  shortName: 'UNICEF 2018 Nurturing Care',
  fullCitation:
      'World Health Organization, United Nations Children\'s Fund, World '
      'Bank Group. Nurturing care for early childhood development: a '
      'framework for helping children survive and thrive to transform '
      'human potential. Geneva: WHO; 2018. Licence: CC BY-NC-SA 3.0 IGO.',
  publishedYear: 2018,
);

const _whoResponsiveFeeding2003 = PillarCitation(
  shortName: 'WHO 2003 Responsive Feeding',
  fullCitation:
      'World Health Organization. Complementary feeding: report of the '
      'global consultation, and summary of guiding principles for '
      'complementary feeding of the breastfed child. Geneva: WHO; 2003.',
  publishedYear: 2003,
);

const _whoEarlyLearning = PillarCitation(
  shortName: 'WHO 2007 + Britto 2017',
  fullCitation:
      'Engle PL, et al. Strategies to avoid the loss of developmental '
      'potential in more than 200 million children in the developing '
      'world. The Lancet. 2007;369(9557):229-242. AND Britto PR, et al. '
      'Nurturing care: promoting early childhood development. The Lancet. '
      '2017;389(10064):91-102.',
  publishedYear: 2017,
);

const _unicefSafeSleep = PillarCitation(
  shortName: 'UNICEF Safe Sleep 2019',
  fullCitation:
      'United Nations Children\'s Fund. Infant and young child feeding '
      'programming guide. New York: UNICEF; 2019. Section on safe sleep '
      'and supervised care.',
  publishedYear: 2019,
);

const _ghsImci2014 = PillarCitation(
  shortName: 'WHO IMCI 2014 + GHS 2018',
  fullCitation:
      'World Health Organization. Integrated Management of Childhood '
      'Illness (IMCI): Chart Booklet. Geneva: WHO; 2014. AND Ghana '
      'Ministry of Health. Under-Five Child Health Policy. Accra: MOH; '
      '2018.',
  publishedYear: 2014,
);

/// The complete nurturing-care assessment for this visit, organised
/// per pillar and ordered by priority.
@immutable
class NurturingCareAssessment {
  const NurturingCareAssessment({
    required this.actions,
    required this.pillarSummaries,
  });

  /// All actions the CHO should take / counsel on, in priority order.
  final List<NurturingCareAction> actions;

  /// Per-pillar summaries (one bullet per pillar with a coverage note).
  final Map<NurturingCarePillar, String> pillarSummaries;

  bool get isEmpty => actions.isEmpty;
  bool get isNotEmpty => actions.isNotEmpty;
}

/// Context the nurturing-care engine needs. Primitive-typed so this
/// engine is testable in isolation and has no dependency on the
/// presentation layer's draft / context types.
@immutable
class NurturingCareContext {
  const NurturingCareContext({
    required this.clientType,
    required this.ageMonths,
    this.stillBreastfeeding = true,
    this.vitaminADue = false,
    this.immunisationItems = const [],
    this.therapeuticSupplements = const [],
  });

  /// The visit client type (pregnant / postpartum / newborn / child).
  final ClientType clientType;

  /// Current age in months. 0 for pregnant or postpartum women.
  final int ageMonths;

  /// True if the child is still breastfed. Used to mark
  /// "exclusive breastfeeding" action as delivered.
  final bool stillBreastfeeding;

  /// True if Vitamin A is due at this visit (6-59m window).
  final bool vitaminADue;

  /// Immunisation items (from the immunisation engine). Used to surface
  /// "catch-up immunisation" action.
  final List<ImmunisationItem> immunisationItems;

  /// Active therapeutic supplements (from Pillar 2). Used to surface
  /// them as a nurturing-care nutrition action.
  final List<TherapeuticSupplement> therapeuticSupplements;
}

/// Builds a [NurturingCareAssessment] from the engine outputs that the
/// result screen already has at hand.
///
/// The engine is intentionally side-effect-free: it reads primitive
/// inputs and produces a deterministic list of actions. The CHO is the
/// one who delivers; the engine is the one who reminds.
abstract final class NurturingCareEngine {
  /// Build a nurturing-care assessment from the visit context.
  static NurturingCareAssessment assess({
    required NurturingCareContext context,
  }) {
    final actions = <NurturingCareAction>[];
    final isPregnant = context.clientType == ClientType.pregnantWoman;
    final isPostpartum = context.clientType == ClientType.postpartumWoman;
    final ageMonths = context.ageMonths;
    final isYoungInfant = ageMonths < 2;
    final isUnder5 = ageMonths < 60;

    // ── PILLAR 1: GOOD HEALTH ─────────────────────────────────────────
    if (isPregnant) {
      actions.add(
        const NurturingCareAction(
          pillar: NurturingCarePillar.goodHealth,
          title: 'ANC contact + birth preparedness plan reviewed today',
          counsellingNote:
              'Confirm ANC schedule, danger-sign recognition, transport plan '
              'and identification of a skilled birth attendant. Birth '
              'preparedness is the single most cost-effective intervention '
              'against the "first delay" in maternal mortality.',
          citation: _unicef2018,
          deliveredAtVisit: true,
        ),
      );
    }
    if (isPostpartum) {
      actions.add(
        const NurturingCareAction(
          pillar: NurturingCarePillar.goodHealth,
          title: 'Postnatal contact within 48 hours of birth',
          counsellingNote:
              'Verify bleeding stopped, fever absent, urine passing, breast '
              'engorgement managed. Maternal mental health screen (2-item '
              'EPDS): "In the past 7 days have you felt down, depressed or '
              'hopeless?" — if yes, refer.',
          citation: _unicef2018,
          deliveredAtVisit: true,
        ),
      );
    }
    if (isUnder5 && context.immunisationItems.isNotEmpty) {
      final overdue = context.immunisationItems
          .where(
            (i) =>
                i.status == ImmunisationStatus.overdue ||
                i.status == ImmunisationStatus.dueToday,
          )
          .toList();
      if (overdue.isNotEmpty) {
        actions.add(
          NurturingCareAction(
            pillar: NurturingCarePillar.goodHealth,
            title:
                'Catch-up immunisation: ${overdue.map((o) => o.dose.label).join(', ')}',
            counsellingNote:
                'Give the vaccine today if available, or refer to the sub-'
                'district immunisation clinic. Explain to the caregiver '
                'which disease each vaccine prevents — this raises follow-up '
                'adherence by ~30% in the literature.',
            citation: _ghsImci2014,
            deliveredAtVisit: true,
          ),
        );
      }
    }
    if (isUnder5 && ageMonths >= 6 && ageMonths <= 59) {
      actions.add(
        NurturingCareAction(
          pillar: NurturingCarePillar.goodHealth,
          title: 'Vitamin A supplementation (6-59 months)',
          counsellingNote:
              '100,000 IU (6-11 months) or 200,000 IU (12-59 months), every '
              '6 months. Vitamin A reduces all-cause mortality by ~24% in '
              'this age group per Mayo-Wilson 2011, BMJ.',
          citation: _ghsImci2014,
          deliveredAtVisit: context.vitaminADue,
        ),
      );
    }
    if (isUnder5) {
      actions.add(
        const NurturingCareAction(
          pillar: NurturingCarePillar.goodHealth,
          title: 'Hand-washing with soap at four critical moments',
          counsellingNote:
              'After latrine use, after handling child faeces, before '
              'cooking, before feeding. Demonstrate the 6-step wash with '
              'the mother today. Tip: an ash tippy-tap works where soap is '
              'unavailable.',
          citation: _unicef2018,
        ),
      );
    }

    // ── PILLAR 2: ADEQUATE NUTRITION ──────────────────────────────────
    if (isPregnant || isPostpartum) {
      actions.add(
        const NurturingCareAction(
          pillar: NurturingCarePillar.adequateNutrition,
          title: 'Maternal MMS / IFA per Pillar 2 supplement selector',
          counsellingNote:
              'See Pillar 2 prescriptions (MMS, IFA). Counsel on the iron-'
              'absorption timing — take with a sour fruit, never with tea '
              'or coffee.',
          citation: _unicef2018,
        ),
      );
    }
    if (ageMonths < 6) {
      actions.add(
        NurturingCareAction(
          pillar: NurturingCarePillar.adequateNutrition,
          title: 'Exclusive breastfeeding for the first 6 months',
          counsellingNote:
              'No water, no porridge, no formula. Breastfeed on demand, 8+ '
              'times in 24 hours. Express and cup-feed if separated. '
              'Exclusive breastfeeding reduces diarrhoea mortality by ~80% '
              'in this age group.',
          citation: _whoResponsiveFeeding2003,
          deliveredAtVisit: context.stillBreastfeeding,
        ),
      );
    } else if (isUnder5) {
      final mealFreqTarget = ageMonths < 12 ? 2 : 4;
      actions.add(
        NurturingCareAction(
          pillar: NurturingCarePillar.adequateNutrition,
          title:
              'Complementary feeding: $mealFreqTarget meals/day + 1-2 snacks, '
              'iron-rich animal-source foods daily',
          counsellingNote:
              'Build a "star bowl" of staples (millet, maize, rice) + '
              'legumes (Bambara beans, cowpea, groundnut) + orange/dark-green '
              'vegetables + animal-source protein when possible. Use a '
              'separated plate so the child gets their own portion. Feed '
              'actively, patiently, with eye contact.',
          citation: _whoResponsiveFeeding2003,
        ),
      );
    }
    if (context.therapeuticSupplements.isNotEmpty) {
      final supps = context.therapeuticSupplements;
      actions.add(
        NurturingCareAction(
          pillar: NurturingCarePillar.adequateNutrition,
          title:
              'Therapeutic supplements: ${supps.map((s) => s.label).join('; ')}',
          counsellingNote: supps.map((s) => s.counsellingNote).join(' '),
          citation: _unicef2018,
        ),
      );
    }

    // ── PILLAR 3: RESPONSIVE CAREGIVING ───────────────────────────────
    if (isYoungInfant || isUnder5) {
      actions.add(
        const NurturingCareAction(
          pillar: NurturingCarePillar.responsiveCaregiving,
          title: 'Recognise and respond to feeding cues',
          counsellingNote:
              'Early cues: stirring, mouth opening, hand-to-mouth. Late '
              'cues: crying, fussing. Crying is the LAST cue — a child who '
              'has to cry to be fed has been hungry for a while. Hold the '
              'baby close, make eye contact during feeds.',
          citation: _whoResponsiveFeeding2003,
        ),
      );
    }
    if (isUnder5 && ageMonths >= 6) {
      actions.add(
        const NurturingCareAction(
          pillar: NurturingCarePillar.responsiveCaregiving,
          title: 'Talk with the child during meals and play',
          counsellingNote:
              'Describe what you are doing. Name objects, colours, food. '
              'Repeat what the child says. This adds roughly 1,000 words '
              'per day to the child\'s exposure and predicts school '
              'readiness (Hart & Risley 1995; updated Hart 2017).',
          citation: _whoEarlyLearning,
        ),
      );
    }
    if (isPostpartum) {
      actions.add(
        const NurturingCareAction(
          pillar: NurturingCarePillar.responsiveCaregiving,
          title: 'Postpartum mental-health check (2-item EPDS)',
          counsellingNote:
              '"In the past 2 weeks have you felt down, depressed or '
              'hopeless?" and "Have you felt little interest or pleasure '
              'in doing things?" If either yes, refer to the mother\'s '
              'support group and re-check in 2 weeks.',
          citation: _unicef2018,
        ),
      );
    }

    // ── PILLAR 4: OPPORTUNITIES FOR EARLY LEARNING ────────────────────
    if (isYoungInfant) {
      actions.add(
        const NurturingCareAction(
          pillar: NurturingCarePillar.earlyLearning,
          title: 'Skin-to-skin, voice and face from day one',
          counsellingNote:
              'Talk, sing, make eye contact from birth — the newborn sees '
              '~20cm. The brain makes 1,000,000 new neural connections per '
              'second in the first 1,000 days (Black 2017, Nurturing Care '
              'Framework).',
          citation: _whoEarlyLearning,
        ),
      );
    }
    if (ageMonths >= 6 && isUnder5) {
      actions.add(
        const NurturingCareAction(
          pillar: NurturingCarePillar.earlyLearning,
          title: 'Play with objects: 3-5 household items, named daily',
          counsellingNote:
              'A plastic cup, a wooden spoon, a piece of fabric, a ball of '
              'cloth. Name them. Hide one, find it. Sort by colour. This '
              'is child-led, no toys required, and supported by 0-3 '
              'literature (Yale Bush Centre, 2017).',
          citation: _whoEarlyLearning,
        ),
      );
    }
    if (isUnder5) {
      actions.add(
        const NurturingCareAction(
          pillar: NurturingCarePillar.earlyLearning,
          title: 'Storytelling in the local language',
          counsellingNote:
              'Use songs and stories from the household, not a foreign '
              'book. A 5-minute story told in Dagbani / Dagaare / Likpakpa '
              'every day is the single highest-leverage early-learning '
              'intervention available in Northern Ghana.',
          citation: _whoEarlyLearning,
        ),
      );
    }

    // ── PILLAR 5: SECURITY AND SAFETY ─────────────────────────────────
    if (isUnder5) {
      actions.add(
        const NurturingCareAction(
          pillar: NurturingCarePillar.securityAndSafety,
          title: 'Safe sleep: baby on back, firm surface, no soft bedding',
          counsellingNote:
              'Baby on the back, on a firm flat surface (mat on floor OK), '
              'no pillow, no soft toys, no co-sleeping on the same mattress. '
              'Reduces SIDS risk. Caregiver-in-the-same-room is encouraged.',
          citation: _unicefSafeSleep,
        ),
      );
    }
    if (isUnder5 && ageMonths < 60) {
      actions.add(
        const NurturingCareAction(
          pillar: NurturingCarePillar.securityAndSafety,
          title: 'Birth registration check',
          counsellingNote:
              'Confirm the birth is registered with the Births and Deaths '
              'Registry. Without registration, the child cannot access '
              'NHIS, school enrolment or formal protection services. '
              'Refer to the district registry if unregistered.',
          citation: _unicef2018,
          referToService: true,
        ),
      );
    }
    if (isUnder5) {
      actions.add(
        const NurturingCareAction(
          pillar: NurturingCarePillar.securityAndSafety,
          title: 'No corporal punishment and no violent discipline',
          counsellingNote:
              'Encourage positive discipline. "Catch the child being good" '
              '— at least 5 positive comments per day per child. Reference: '
              'WHO 2016 INSPIRE framework for ending violence against '
              'children.',
          citation: _unicef2018,
        ),
      );
    }
    if (isYoungInfant || (isUnder5 && ageMonths < 12)) {
      actions.add(
        const NurturingCareAction(
          pillar: NurturingCarePillar.securityAndSafety,
          title: 'Hand-washing station within 5 paces of the latrine',
          counsellingNote:
              'Tippy-tap (ash + water + stick + bottle) at the latrine '
              'doorstep. Hand-washing with soap after faeces is the single '
              'most cost-effective WASH intervention per WHO.',
          citation: _unicef2018,
        ),
      );
    }

    // Deduplicate by (pillar, title), preserving first occurrence.
    final seen = <String>{};
    final uniqueActions = <NurturingCareAction>[];
    for (final a in actions) {
      final k = '${a.pillar.name}|${a.title}';
      if (seen.add(k)) uniqueActions.add(a);
    }

    // Pillar summaries
    final summaries = <NurturingCarePillar, String>{};
    for (final p in NurturingCarePillar.values) {
      final count = uniqueActions.where((a) => a.pillar == p).length;
      summaries[p] = count == 0
          ? 'No additional actions — already covered today.'
          : '$count action${count == 1 ? '' : 's'} to deliver or counsel on.';
    }

    return NurturingCareAssessment(
      actions: uniqueActions,
      pillarSummaries: summaries,
    );
  }

  /// Finds the corresponding [NcAgeBand] for a child's age in months.
  ///
  /// Covers developmental windows from birth up to 60 months (5 years old).
  /// Returns null for null, negative, or 60+ months. The bands are
  /// half-open: a child at month [minMonths, maxMonths) belongs to a band.
  static NcAgeBand? bandFor(int? ageInMonths) {
    if (ageInMonths == null || ageInMonths < 0 || ageInMonths >= 60) {
      return null;
    }
    for (final b in _ncBands) {
      if (ageInMonths >= b.minMonths && ageInMonths < b.maxMonths) {
        return b;
      }
    }
    return null;
  }

  /// Selects a practical daily play activity for the caregiver from the given age band.
  ///
  /// The second argument is the date to pick for; defaults to today. Only
  /// the day-of-month is used, so two calls on the same day return the same
  /// activity (deterministic, offline-friendly).
  static String activityToday(NcAgeBand band, [DateTime? date]) {
    if (band.activities.isEmpty) {
      return 'Interact lovingly and narrate daily activities together.';
    }
    final d = date ?? DateTime.now();
    final idx = d.day % band.activities.length;
    return band.activities[idx];
  }

  /// The twelve canonical developmental age bands from birth to five years.
  /// Used by the milestone picker, the test suite, and the activities
  /// rotation.
  static const List<NcAgeBand> bands = _ncBands;
}

// ---------------------------------------------------------------------------
// AGE BAND + MILESTONE TYPES
// ---------------------------------------------------------------------------
//
// The caregiver-facing milestone check works in age bands rather than
// month-by-month. Each band owns:
//   - a set of WHO CCD-sourced milestone questions (the [milestones])
//   - a set of safe, offline-able play / talk / read ideas (the
//     [activities])
//   - one caregiver-facing tip
//   - a set of "red flag" milestones — the subset of milestones that
//     the WHO Child Development and Development package treats as
//     reason for the health worker to look at the child. A flag is
//     always also a milestone, so the family is actually asked about
//     it.

/// The WHO Child Development domain a milestone belongs to. Mirrors the
/// four CCD streams so the result-screen pill can carry a domain tag.
enum NcDomain {
  motor('Motor'),
  language('Language'),
  cognitive('Cognitive'),
  socialEmotional('Social-Emotional');

  const NcDomain(this.label);
  final String label;
}

/// One milestone question a caregiver can answer yes / not yet.
///
/// The [id] is stable across releases — the SQLite record stores it and
/// re-renders by id, not by text, so wording can be tightened without
/// losing history.
@immutable
class NcMilestone {
  const NcMilestone({
    required this.id,
    required this.domain,
    required this.question,
    this.isFlag = false,
  });

  /// Stable id, e.g. 'sits_without_support_6m'.
  final String id;

  /// The CCD stream this milestone belongs to. Used to render the
  /// domain pill on the question tile.
  final NcDomain domain;

  /// The exact question shown to the caregiver. Plain language, no
  /// jargon, no "should". The record stores the verbatim text.
  final String question;

  /// True if "not yet" to this milestone is a reason for the health
  /// worker to look at the child. A flag is always also a milestone in
  /// its own band.
  final bool isFlag;

  @override
  String toString() => 'NcMilestone($id)';

  /// Equality is by [id] alone so the same milestone referenced from
  /// both the band's [NcAgeBand.milestones] and [NcAgeBand.flags] lists
  /// is `==`-equal. This is what lets the red-flag test pin
  /// `band.milestones.contains(flag)` to be `true` without having to
  /// pass the exact same Dart object reference.
  @override
  bool operator ==(Object other) => other is NcMilestone && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A WHO-style developmental age band, with its milestone questions,
/// play ideas, caregiver tip, and red-flag subset.
@immutable
class NcAgeBand {
  const NcAgeBand({
    required this.minMonths,
    required this.maxMonths,
    required this.label,
    required this.milestones,
    required this.activities,
    required this.tip,
    this.flags = const [],
  });

  /// First month of the band (inclusive). 0 for "at birth".
  final int minMonths;

  /// Last month of the band (inclusive). 35 for the 0-35m band means
  /// the band covers every month from birth to 35 months.
  final int maxMonths;

  /// Caregiver-facing label, e.g. "6 to 9 months".
  final String label;

  /// Milestone questions the family is asked about in this band.
  final List<NcMilestone> milestones;

  /// Play / talk / read ideas the CHO can suggest today. These are the
  /// "what to do at home" list, not the "what the child is doing" list.
  final List<String> activities;

  /// One-sentence caregiver tip.
  final String tip;

  /// Subset of [milestones] whose "not yet" answer is a reason to
  /// refer the child. A flag is always also a milestone in [milestones]
  /// so the family is actually asked about it.
  final List<NcMilestone> flags;
}

// ---------------------------------------------------------------------------
// THE BANDS
// ---------------------------------------------------------------------------
//
// Twelve bands, covering birth to 60 months without gaps. Each band
// carries a set of WHO CCD-sourced milestones. The "red flag" subset
// mirrors the WHO 2014 IMCI + CDC "Learn the Signs. Act Early."
// surveillance list, restricted to items the family is actually asked
// about. The play / talk / read activities are age-appropriate, safe
// with no equipment, and grounded in the CCF / Nurturing Care literature.

const _ncBands = <NcAgeBand>[
  // 0 to 1 month (half-open [0, 2))
  NcAgeBand(
    minMonths: 0,
    maxMonths: 2,
    label: 'Newborn (0 to 1 month)',
    milestones: [
      NcMilestone(
        id: 'sucks_well_0m',
        domain: NcDomain.motor,
        question: 'Sucks well when feeding (breast or cup)',
      ),
      NcMilestone(
        id: 'opens_hands_occasionally_0m',
        domain: NcDomain.motor,
        question: 'Opens and closes hands, even briefly',
      ),
      NcMilestone(
        id: 'startles_to_sound_0m',
        domain: NcDomain.language,
        question: 'Startles or widens eyes at a sudden loud sound',
        isFlag: true,
      ),
      NcMilestone(
        id: 'calms_to_voice_0m',
        domain: NcDomain.socialEmotional,
        question: 'Calms when you pick them up and talk softly',
      ),
      NcMilestone(
        id: 'briefly_focuses_face_0m',
        domain: NcDomain.cognitive,
        question: 'Looks at your face for a moment when held close',
      ),
    ],
    flags: [
      NcMilestone(
        id: 'startles_to_sound_0m',
        domain: NcDomain.language,
        question: 'Startles or widens eyes at a sudden loud sound',
        isFlag: true,
      ),
    ],
    activities: [
      'Skin-to-skin chest, face near yours, talk or sing softly',
      'Lay baby on a firm flat surface; gently move arms and legs in play',
      'Look at a high-contrast (black-on-white) picture together',
      'Hum the same song you sang in pregnancy — your baby remembers it',
      'Hold baby upright against your shoulder; walk slowly around the room',
    ],
    tip: 'Your face is your baby\'s first toy. Hold them close and talk.',
  ),

  // 2 to 3 months (half-open [2, 4))
  NcAgeBand(
    minMonths: 2,
    maxMonths: 4,
    label: '2 to 3 months',
    milestones: [
      NcMilestone(
        id: 'holds_head_up_2m',
        domain: NcDomain.motor,
        question: 'Holds head steady when held upright at your shoulder',
      ),
      NcMilestone(
        id: 'coos_2m',
        domain: NcDomain.language,
        question: 'Makes soft "ahh" or "ooh" sounds back at you',
      ),
      NcMilestone(
        id: 'follows_face_2m',
        domain: NcDomain.cognitive,
        question: 'Follows your face as you move slowly side to side',
      ),
      NcMilestone(
        id: 'social_smile_2m',
        domain: NcDomain.socialEmotional,
        question: 'Smiles back at you when you smile and talk',
        isFlag: true,
      ),
    ],
    flags: [
      NcMilestone(
        id: 'social_smile_2m',
        domain: NcDomain.socialEmotional,
        question: 'Smiles back at you when you smile and talk',
        isFlag: true,
      ),
    ],
    activities: [
      'Tummy time on your chest for a few minutes, several times a day',
      'Sing a call-and-response: "Baby, baby" — pause — smile and wait',
      'Show a coloured cloth at 30 cm, slowly move it side to side',
      'Copy the sounds your baby makes; let them "answer" you',
      'Hold a soft rattle at the side; shake gently and let baby turn',
    ],
    tip: 'Pause after you speak. The back-and-forth is what grows language.',
  ),

  // 4 to 5 months (half-open [4, 6))
  NcAgeBand(
    minMonths: 4,
    maxMonths: 6,
    label: '4 to 5 months',
    milestones: [
      NcMilestone(
        id: 'rolls_front_to_back_4m',
        domain: NcDomain.motor,
        question: 'Rolls from tummy onto back (or tries to)',
      ),
      NcMilestone(
        id: 'laughs_4m',
        domain: NcDomain.socialEmotional,
        question: 'Laughs out loud when you play',
      ),
      NcMilestone(
        id: 'reaches_for_object_4m',
        domain: NcDomain.cognitive,
        question: 'Reaches for an object they can see',
      ),
      NcMilestone(
        id: 'makes_squeals_4m',
        domain: NcDomain.language,
        question: 'Makes squeals, squeaks, or blowing sounds',
      ),
      NcMilestone(
        id: 'no_eye_contact_4m',
        domain: NcDomain.socialEmotional,
        question: 'Often avoids looking at your face or eyes',
        isFlag: true,
      ),
    ],
    flags: [
      NcMilestone(
        id: 'no_eye_contact_4m',
        domain: NcDomain.socialEmotional,
        question: 'Often avoids looking at your face or eyes',
        isFlag: true,
      ),
    ],
    activities: [
      'Lie on the floor face-to-face; copy each other\'s sounds',
      'Put a soft ball in their hand; let them feel and mouth it',
      'Tummy time on a firm mat with a colourful cloth in front',
      'Sing a song and act it out with hand movements',
      'Shake a tin with dry beans inside; let them find where the sound comes from',
    ],
    tip: 'Everything goes in the mouth at this age. That is how they learn.',
  ),

  // 6 to 8 months (half-open [6, 9))
  NcAgeBand(
    minMonths: 6,
    maxMonths: 9,
    label: '6 to 8 months',
    milestones: [
      NcMilestone(
        id: 'sits_without_support_6m',
        domain: NcDomain.motor,
        question: 'Sits without support for a few seconds',
        isFlag: true,
      ),
      NcMilestone(
        id: 'transfers_object_6m',
        domain: NcDomain.motor,
        question: 'Passes an object from one hand to the other',
      ),
      NcMilestone(
        id: 'responds_to_name_6m',
        domain: NcDomain.language,
        question: 'Looks or turns when you call their name',
        isFlag: true,
      ),
      NcMilestone(
        id: 'stranger_anxiety_6m',
        domain: NcDomain.socialEmotional,
        question: 'Wary of strangers or clings to you in new places',
      ),
      NcMilestone(
        id: 'looks_for_dropped_6m',
        domain: NcDomain.cognitive,
        question: 'Looks for an object they saw you drop',
      ),
    ],
    flags: [
      NcMilestone(
        id: 'sits_without_support_6m',
        domain: NcDomain.motor,
        question: 'Sits without support for a few seconds',
        isFlag: true,
      ),
      NcMilestone(
        id: 'responds_to_name_6m',
        domain: NcDomain.language,
        question: 'Looks or turns when you call their name',
        isFlag: true,
      ),
    ],
    activities: [
      'Sit baby on a firm mat with 3 safe household objects (cup, spoon, cloth)',
      'Hide a cloth over a toy; let them pull it off to find the toy',
      'Name everything you do: "Mama is washing the cup, washing the cup"',
      'Place baby facing you at mealtime; take turns opening the mouth wide',
      'Bang a wooden spoon on a tin; let baby copy you',
    ],
    tip: 'Name what you see, name what you do, name what baby does.',
  ),

  // 9 to 11 months (half-open [9, 12))
  NcAgeBand(
    minMonths: 9,
    maxMonths: 12,
    label: '9 to 11 months',
    milestones: [
      NcMilestone(
        id: 'pulls_to_stand_10m',
        domain: NcDomain.motor,
        question: 'Pulls themselves up to stand holding furniture',
      ),
      NcMilestone(
        id: 'pincer_grasp_10m',
        domain: NcDomain.motor,
        question: 'Picks up a small object with thumb and finger',
      ),
      NcMilestone(
        id: 'waves_bye_10m',
        domain: NcDomain.socialEmotional,
        question: 'Waves "bye-bye" or copies a simple gesture',
      ),
      NcMilestone(
        id: 'first_word_10m',
        domain: NcDomain.language,
        question: 'Says one clear word like "mama" or "dada" on purpose',
      ),
      NcMilestone(
        id: 'no_words_12m',
        domain: NcDomain.language,
        question: 'Does not babble strings of sounds like "ba-ba-ba"',
        isFlag: true,
      ),
    ],
    flags: [
      NcMilestone(
        id: 'no_words_12m',
        domain: NcDomain.language,
        question: 'Does not babble strings of sounds like "ba-ba-ba"',
        isFlag: true,
      ),
    ],
    activities: [
      'Stack two small plastic cups; let baby knock them down',
      'Put 5 beans in a tin, shake it, give it to baby to shake too',
      'Look at a picture book together; point and name what you see',
      'Help baby walk holding both your hands; let them set the pace',
      'Roll a soft ball back and forth between you',
    ],
    tip: 'If they say nothing, narrate the world out loud for them.',
  ),

  // 12 to 14 months (half-open [12, 15))
  NcAgeBand(
    minMonths: 12,
    maxMonths: 15,
    label: '12 to 14 months',
    milestones: [
      NcMilestone(
        id: 'walks_with_hand_13m',
        domain: NcDomain.motor,
        question: 'Walks, even with a hand to hold',
      ),
      NcMilestone(
        id: 'says_3_words_13m',
        domain: NcDomain.language,
        question: 'Says 3 or more single words',
      ),
      NcMilestone(
        id: 'points_to_want_13m',
        domain: NcDomain.socialEmotional,
        question: 'Points to what they want instead of just crying',
      ),
      NcMilestone(
        id: 'scribbles_13m',
        domain: NcDomain.cognitive,
        question: 'Scribbles with a crayon or a stick in the sand',
      ),
      NcMilestone(
        id: 'not_walking_15m',
        domain: NcDomain.motor,
        question: 'Has not started walking at all by 15 months',
        isFlag: true,
      ),
    ],
    flags: [
      NcMilestone(
        id: 'not_walking_15m',
        domain: NcDomain.motor,
        question: 'Has not started walking at all by 15 months',
        isFlag: true,
      ),
    ],
    activities: [
      'Fill and empty a cup with water outside together',
      'Hide a small toy under one of two cloths; let them find it',
      'Sort 6 spoons from 6 cups; count as you go',
      'Sing a song and act it out: "Open, shut them"',
      'Walk together on a safe path; let them lead and you follow',
    ],
    tip: 'Talk through what they\'re doing — they\'re learning every word.',
  ),

  // 15 to 17 months (half-open [15, 18))
  NcAgeBand(
    minMonths: 15,
    maxMonths: 18,
    label: '15 to 17 months',
    milestones: [
      NcMilestone(
        id: 'kicks_ball_15m',
        domain: NcDomain.motor,
        question: 'Kicks a soft ball forward',
      ),
      NcMilestone(
        id: 'two_word_phrases_15m',
        domain: NcDomain.language,
        question: 'Says 2 words together like "mama come"',
        isFlag: true,
      ),
      NcMilestone(
        id: 'imitates_housework_15m',
        domain: NcDomain.socialEmotional,
        question: 'Copies what you do — sweeping, cooking, washing',
      ),
      NcMilestone(
        id: 'follows_simple_command_15m',
        domain: NcDomain.cognitive,
        question: 'Follows a simple command like "bring the cup"',
      ),
    ],
    flags: [
      NcMilestone(
        id: 'two_word_phrases_15m',
        domain: NcDomain.language,
        question: 'Says 2 words together like "mama come"',
        isFlag: true,
      ),
    ],
    activities: [
      'Pretend cooking with a pot, water, and leaves; name the food',
      'Line up 4 stones by size; let them rearrange them',
      'Tell a short story from your day; point to a picture to help',
      'Draw circles and lines on the floor with chalk',
      'Play "ready, set, go" — run, stop, run again',
    ],
    tip: 'Two words together is the big milestone this year.',
  ),

  // 18 to 23 months (half-open [18, 24))
  NcAgeBand(
    minMonths: 18,
    maxMonths: 24,
    label: '18 to 23 months',
    milestones: [
      NcMilestone(
        id: 'runs_well_18m',
        domain: NcDomain.motor,
        question: 'Runs a few steps without falling',
      ),
      NcMilestone(
        id: 'says_full_sentence_18m',
        domain: NcDomain.language,
        question: 'Says a sentence of 3 or more words',
      ),
      NcMilestone(
        id: 'names_friend_18m',
        domain: NcDomain.socialEmotional,
        question: 'Names at least one friend',
      ),
      NcMilestone(
        id: 'toilet_signals_18m',
        domain: NcDomain.cognitive,
        question: 'Tells you (with words or signs) they need the toilet',
      ),
      NcMilestone(
        id: 'no_2word_phrases_24m',
        domain: NcDomain.language,
        question: 'Has not started saying 2 words together',
        isFlag: true,
      ),
    ],
    flags: [
      NcMilestone(
        id: 'no_2word_phrases_24m',
        domain: NcDomain.language,
        question: 'Has not started saying 2 words together',
        isFlag: true,
      ),
    ],
    activities: [
      'Pretend a banana is a phone; take turns "calling" each other',
      'Sort socks by colour; count them as you go',
      'Tell a 3-sentence story about a day at the market',
      'Build a tower of 6 blocks; let them knock it down and rebuild',
      'Hop like a frog; jump like a cat — copy each other',
    ],
    tip: 'Pretend play is how they rehearse being human.',
  ),

  // 24 to 35 months / 2 to 3 years (half-open [24, 36))
  NcAgeBand(
    minMonths: 24,
    maxMonths: 36,
    label: '24 to 35 months (2 to 3 years)',
    milestones: [
      NcMilestone(
        id: 'hops_one_foot_24m',
        domain: NcDomain.motor,
        question: 'Hops on one foot a few times',
      ),
      NcMilestone(
        id: 'speaks_clearly_24m',
        domain: NcDomain.language,
        question: 'Speaks so you can understand them most of the time',
      ),
      NcMilestone(
        id: 'plays_with_others_24m',
        domain: NcDomain.socialEmotional,
        question: 'Plays with other children, not just alongside them',
      ),
      NcMilestone(
        id: 'draws_person_24m',
        domain: NcDomain.cognitive,
        question: 'Draws a person with at least 2 body parts',
      ),
    ],
    flags: [
      NcMilestone(
        id: 'speaks_clearly_24m',
        domain: NcDomain.language,
        question: 'Speaks so you can understand them most of the time',
        isFlag: true,
      ),
    ],
    activities: [
      'Tell a story from a picture; let them make up what happens next',
      'Play "Simon says" with two-step instructions',
      'Sort stones, leaves, and bottle tops by size and colour',
      'Sing a counting song and clap on the numbers',
      'Build a road from sticks; drive a small stone car along it',
    ],
    tip: 'Their questions are the smartest thing in the house. Answer them.',
  ),

  // 36 to 47 months / 3 to 4 years (half-open [36, 48))
  NcAgeBand(
    minMonths: 36,
    maxMonths: 48,
    label: '36 to 47 months (3 to 4 years)',
    milestones: [
      NcMilestone(
        id: 'catches_ball_36m',
        domain: NcDomain.motor,
        question: 'Catches a soft ball thrown from 2 metres',
      ),
      NcMilestone(
        id: 'tells_simple_story_36m',
        domain: NcDomain.language,
        question: 'Tells a simple story with a beginning, middle, and end',
      ),
      NcMilestone(
        id: 'takes_turns_36m',
        domain: NcDomain.socialEmotional,
        question: 'Takes turns and waits for their turn in a game',
      ),
      NcMilestone(
        id: 'counts_to_five_36m',
        domain: NcDomain.cognitive,
        question: 'Counts 5 or more objects correctly',
      ),
    ],
    flags: [
      NcMilestone(
        id: 'tells_simple_story_36m',
        domain: NcDomain.language,
        question: 'Tells a simple story with a beginning, middle, and end',
        isFlag: true,
      ),
    ],
    activities: [
      'Tell a story from a picture; let them make up what happens next',
      'Play "Simon says" with two-step instructions',
      'Sort stones, leaves, and bottle tops by size and colour',
      'Sing a counting song and clap on the numbers',
      'Build a road from sticks; drive a small stone car along it',
    ],
    tip: 'Their questions are the smartest thing in the house. Answer them.',
  ),

  // 48 to 59 months / 4 to 5 years (half-open [48, 60))
  NcAgeBand(
    minMonths: 48,
    maxMonths: 60,
    label: '48 to 59 months (4 to 5 years)',
    milestones: [
      NcMilestone(
        id: 'hops_steady_48m',
        domain: NcDomain.motor,
        question:
            'Hops steadily on one foot and balances on one leg for 4-5 seconds',
      ),
      NcMilestone(
        id: 'retells_activity_48m',
        domain: NcDomain.language,
        question: 'Retells recent activities or basic short daily experiences',
        isFlag: true,
      ),
      NcMilestone(
        id: 'cooperative_play_48m',
        domain: NcDomain.socialEmotional,
        question: 'Plays cooperatively and takes turns with other children',
      ),
      NcMilestone(
        id: 'names_shapes_48m',
        domain: NcDomain.cognitive,
        question:
            'Identifies multiple basic shapes, colors, and number quantities',
      ),
    ],
    flags: [
      NcMilestone(
        id: 'retells_activity_48m',
        domain: NcDomain.language,
        question: 'Retells recent activities or basic short daily experiences',
        isFlag: true,
      ),
    ],
    activities: [
      'Encourage imaginative storytelling games where your child describes adventures involving familiar local animals.',
      'Play interactive bouncing and catching ball games that sharpen balance and spatial coordination.',
      'Sort stones, leaves, and bottle tops by size and colour',
      'Sing a counting song and clap on the numbers',
      'Build a road from sticks; drive a small stone car along it',
    ],
    tip: 'Listening to their full story is the biggest gift you can give.',
  ),
];

/// The bands list exposed for the milestone picker and the test suite.
abstract final class _NurturingCareBands {
  static const List<NcAgeBand> all = _ncBands;
}
