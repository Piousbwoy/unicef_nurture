/// Hidden barriers to care — challenge area 6.
///
/// The clinical engines answer "what is wrong with this person". This one
/// answers the question that actually decides whether they live: **why didn't
/// they go?**
///
/// A referral note is not care. Between the note and the treatment sit money,
/// distance, a husband's permission, a flooded road, a market day, an unpaid
/// NHIS premium, a bad experience three years ago, and a grandmother who
/// disagrees. Registers record "did not attend" and stop there, which is
/// precisely the point at which the information becomes useless.
///
/// Two things happen here:
///
/// **1. Prediction before failure.** Given what is known about a household, the
/// engine flags the barriers most likely to stop *this* referral, before it is
/// issued — so the CHO can solve the transport problem while the family is still
/// in front of them, not discover it two days later.
///
/// **2. Pattern detection across a zone.** Six unrelated families reporting
/// "facility was closed" is not six family problems, it is one facility problem.
/// Aggregating barriers turns individual excuses into evidence a CHO can escalate.
library;

import '../enums.dart';
import '../entities/core.dart';
import '../entities/visit.dart';

/// A barrier the engine believes is likely, with the reason it thinks so.
class PredictedBarrier {
  const PredictedBarrier({
    required this.barrier,
    required this.likelihood,
    required this.basis,
    required this.preemptiveAction,
  });

  final CareBarrier barrier;

  /// 0–1. Deliberately coarse: this is a prompt to ask a question, not a
  /// probability anyone should quote.
  final double likelihood;

  /// Why the engine raised it — always traceable to a recorded fact.
  final String basis;

  /// What to do *now*, before the family leaves.
  final String preemptiveAction;

  String get likelihoodLabel {
    if (likelihood >= 0.7) return 'Very likely';
    if (likelihood >= 0.45) return 'Likely';
    return 'Possible';
  }
}

/// A barrier pattern across several households in a zone.
class BarrierPattern {
  const BarrierPattern({
    required this.barrier,
    required this.householdCount,
    required this.share,
    required this.interpretation,
    required this.escalation,
  });

  final CareBarrier barrier;
  final int householdCount;

  /// Share of all reported barriers in the period.
  final double share;

  /// What this pattern means, as opposed to what the individual reports say.
  final String interpretation;

  /// Who should be told, and what should be asked for.
  final String escalation;

  /// A systemic pattern is one a CHO cannot fix household by household.
  bool get isSystemic =>
      barrier == CareBarrier.facilityClosed ||
      barrier == CareBarrier.noNhisCard ||
      barrier == CareBarrier.floodedRoad ||
      barrier == CareBarrier.distanceTooFar ||
      barrier == CareBarrier.pastBadExperience;
}

class BarrierForecast {
  const BarrierForecast({
    required this.predicted,
    required this.referralFeasibility,
    required this.feasibilityNote,
    this.findings = const [],
    this.actions = const [],
  });

  final List<PredictedBarrier> predicted;

  /// 0–1 estimate that a referral issued now would actually be completed.
  final double referralFeasibility;

  final String feasibilityNote;

  final List<ClinicalFinding> findings;
  final List<RecommendedAction> actions;

  bool get isHighRisk => referralFeasibility < 0.5;
}

abstract final class BarrierEngine {
  /// Predicts what will stop this household completing a referral.
  ///
  /// [urgency] matters: an immediate referral at night over a flooded road is a
  /// different proposition from a scheduled appointment next month.
  static BarrierForecast forecast({
    Household? household,
    Person? client,
    List<CareBarrier> previouslyReported = const [],
    int missedContactsCount = 0,
    ReferralUrgency urgency = ReferralUrgency.sameDay,
    int? month,
    bool? isNightTime,
    int? childrenUnderFiveInHousehold,
    bool? decisionMakerPresent,
  }) {
    final predicted = <PredictedBarrier>[];

    // A barrier reported before is the strongest predictor of the same barrier
    // again. Nothing in the data beats simply having been told.
    for (final b in previouslyReported) {
      predicted.add(
        PredictedBarrier(
          barrier: b,
          likelihood: 0.8,
          basis:
              'This household has reported "${b.label.toLowerCase()}" before. '
              'Unless something changed, it will apply again.',
          preemptiveAction: b.suggestedAction,
        ),
      );
    }

    final already = previouslyReported.toSet();

    void predict(
      CareBarrier b,
      double likelihood,
      String basis, {
      String? action,
    }) {
      if (already.contains(b)) return;
      predicted.add(
        PredictedBarrier(
          barrier: b,
          likelihood: likelihood,
          basis: basis,
          preemptiveAction: action ?? b.suggestedAction,
        ),
      );
    }

    // ------------------------------------------------------------------
    // Distance and transport
    // ------------------------------------------------------------------
    final walk = household?.walkingMinutesToFacility;
    if (walk != null) {
      if (walk > 120) {
        predict(
          CareBarrier.distanceTooFar,
          0.8,
          '$walk minutes on foot to the nearest facility. For an urgent '
              'referral that is most of a day, carrying a sick child.',
          action:
              'Refer to the nearest *adequate* facility rather than the usual '
              'one, and arrange a motorking before the family leaves.',
        );
        predict(
          CareBarrier.noTransportMoney,
          0.7,
          'At $walk minutes walking, this journey needs paid transport, which '
              'means cash the household may not have today.',
        );
      } else if (walk > 60) {
        predict(
          CareBarrier.distanceTooFar,
          0.5,
          '$walk minutes on foot.',
        );
        predict(
          CareBarrier.noTransportMoney,
          0.5,
          'Over an hour on foot usually means paying for transport.',
        );
      }
    }

    // ------------------------------------------------------------------
    // Cost
    // ------------------------------------------------------------------
    if (household?.hasValidNhis == false) {
      predict(
        CareBarrier.noNhisCard,
        0.75,
        'No valid NHIS card on record. Families routinely stay away rather than '
            'arrive unable to pay.',
        action:
            'Tell the family plainly that maternal and child emergency care is '
            'not refused for lack of a card, and start registration today.',
      );
    } else if (household?.hasValidNhis == null) {
      predict(
        CareBarrier.noNhisCard,
        0.4,
        'NHIS status has never been recorded, so cost cannot be ruled out as a '
            'barrier.',
        action: 'Ask about NHIS and record the answer.',
      );
    }

    // ------------------------------------------------------------------
    // Decision-making and household structure
    // ------------------------------------------------------------------
    if (decisionMakerPresent == false) {
      predict(
        CareBarrier.noPermission,
        0.7,
        'The person who decides is not here. In most compounds a woman cannot '
            'commit to travelling without the husband or a senior relative '
            'agreeing.',
        action:
            'Do not leave the decision with her alone. Send for the '
            'decision-maker now, or go and speak to them yourself.',
      );
    }

    final age = client?.ageInYears;
    if (age != null && age < 18) {
      predict(
        CareBarrier.noPermission,
        0.6,
        'An adolescent mother rarely controls either the money or the decision '
            'to travel.',
      );
    }

    if ((childrenUnderFiveInHousehold ?? 0) >= 3) {
      predict(
        CareBarrier.noChildcare,
        0.6,
        '$childrenUnderFiveInHousehold children under five in the compound. '
            'Leaving for a facility means finding someone to mind the rest.',
      );
    }

    if ((household?.familySize ?? 0) >= 10) {
      predict(
        CareBarrier.noChildcare,
        0.4,
        'A large compound usually means the mother is the one holding it '
            'together.',
      );
    }

    // ------------------------------------------------------------------
    // Season, roads and work
    // ------------------------------------------------------------------
    if (month != null) {
      final rainy = month >= 6 && month <= 9;
      final harvest = month >= 10 && month <= 12;
      final planting = month == 5 || month == 6;

      if (rainy) {
        predict(
          CareBarrier.floodedRoad,
          0.55,
          'This is the height of the single rainy season. Feeder roads and '
              'culverts in this region flood, and some communities are cut off '
              'for days.',
          action:
              'Ask about the road today before promising the family it is '
              'passable. If it is not, plan a phone follow-up and pre-position '
              'advice.',
        );
      }
      if (harvest || planting) {
        predict(
          CareBarrier.farmWorkload,
          0.5,
          harvest
              ? 'Harvest season. A day at a facility is a day of crop not '
                    'brought in.'
              : 'Planting season. Missing the rains costs the household a year '
                    'of food.',
          action:
              'Offer an early-morning or evening contact, and plan around '
              'market days.',
        );
      }
    }

    if (isNightTime == true && urgency == ReferralUrgency.immediate) {
      predict(
        CareBarrier.distanceTooFar,
        0.65,
        'An urgent referral at night. There is usually no transport, and '
            'families are reluctant to travel after dark.',
        action:
            'Find a motorking driver by name and phone number now. Do not send '
            'a family into the night without knowing how they will travel.',
      );
    }

    // ------------------------------------------------------------------
    // Belief, trust and prior experience
    // ------------------------------------------------------------------
    if (missedContactsCount >= 2) {
      predict(
        CareBarrier.didNotThinkItSerious,
        0.55,
        '$missedContactsCount appointments already missed. Either the reason '
            'for going was never clear, or something practical keeps getting in '
            'the way.',
        action:
            'Before they leave, ask the caregiver to name three signs that mean '
            'come back at once. If they cannot, the message did not land.',
      );
      predict(
        CareBarrier.pastBadExperience,
        0.4,
        'Repeated non-attendance sometimes reflects how the family was treated '
            'last time, which they will not volunteer unless asked directly.',
      );
    }

    // ------------------------------------------------------------------
    // Feasibility of the referral, given all of the above
    // ------------------------------------------------------------------
    var feasibility = 1.0;
    for (final p in predicted) {
      // Each likely barrier multiplicatively erodes the chance of arrival.
      feasibility *= (1 - (p.likelihood * 0.35));
    }
    feasibility = feasibility.clamp(0.05, 1.0);

    // Urgency does not create barriers, but it shortens the time to solve them.
    if (urgency == ReferralUrgency.immediate) feasibility *= 0.9;

    final findings = <ClinicalFinding>[];
    final actions = <RecommendedAction>[];

    if (predicted.isNotEmpty) {
      final top = ([...predicted]
        ..sort((a, b) => b.likelihood.compareTo(a.likelihood)));
      findings.add(
        ClinicalFinding(
          label: 'Referral may not be completed',
          detail:
              'Likely obstacles: '
              '${top.take(3).map((p) => p.barrier.label.toLowerCase()).join('; ')}. '
              'Writing the note is the easy part. '
              '${(feasibility * 100).round()}% estimated chance this referral is '
              'completed unless these are dealt with now.',
          severity: feasibility < 0.5
              ? TriageLevel.priority
              : TriageLevel.watch,
          protocolSource: 'CareBridge barrier analysis',
          measuredValue: '${(feasibility * 100).round()}% feasibility',
          threshold: 'below 50% needs active support',
          weight: feasibility < 0.5 ? 6 : 3,
        ),
      );

      for (final p in top.take(3)) {
        actions.add(
          RecommendedAction(
            instruction: p.preemptiveAction,
            urgency: urgency == ReferralUrgency.immediate
                ? ReferralUrgency.immediate
                : ReferralUrgency.sameDay,
            rationale: '${p.likelihoodLabel}: ${p.basis}',
            protocolSource: 'CareBridge barrier analysis',
            isCounselling: true,
          ),
        );
      }
    }

    return BarrierForecast(
      predicted: ([...predicted]
        ..sort((a, b) => b.likelihood.compareTo(a.likelihood))),
      referralFeasibility: feasibility,
      feasibilityNote: _feasibilityNote(feasibility, predicted.length),
      findings: findings,
      actions: actions,
    );
  }

  static String _feasibilityNote(double f, int barrierCount) {
    if (barrierCount == 0) {
      return 'No obvious obstacles on record. Still ask — the barriers that '
          'matter are the ones nobody wrote down.';
    }
    if (f >= 0.7) {
      return 'This referral has a fair chance of being completed. Confirm the '
          'transport arrangement and move on.';
    }
    if (f >= 0.5) {
      return 'This referral is at real risk of not happening. Solve at least the '
          'top obstacle before the family leaves.';
    }
    return 'This referral will probably fail as it stands. Do not hand over a '
        'note and hope. Either remove the obstacles now, or bring the care to '
        'the household instead.';
  }

  /// Aggregates reported barriers across a zone into patterns.
  ///
  /// This is what turns a CHO from a recorder into a witness: a single family
  /// saying "the facility was closed" is an anecdote; nine families saying it in
  /// one month is a staffing problem with evidence attached.
  static List<BarrierPattern> detectPatterns(
    List<BarrierReport> reports, {
    int minHouseholds = 3,
  }) {
    if (reports.isEmpty) return const [];

    final counts = <CareBarrier, Set<String>>{};
    var totalMentions = 0;

    for (final r in reports) {
      for (final b in r.barriers) {
        counts.putIfAbsent(b, () => <String>{}).add(r.householdId);
        totalMentions++;
      }
    }

    final patterns = <BarrierPattern>[];
    for (final entry in counts.entries) {
      final households = entry.value.length;
      if (households < minHouseholds) continue;

      final share = totalMentions == 0 ? 0.0 : households / totalMentions;
      patterns.add(
        BarrierPattern(
          barrier: entry.key,
          householdCount: households,
          share: share,
          interpretation: _interpret(entry.key, households),
          escalation: _escalate(entry.key),
        ),
      );
    }

    patterns.sort((a, b) => b.householdCount.compareTo(a.householdCount));
    return patterns;
  }

  static String _interpret(CareBarrier b, int households) {
    return switch (b) {
      CareBarrier.facilityClosed =>
        '$households households found the facility closed or unstaffed. This is '
            'not a community problem — it is a service problem, and it needs '
            'reporting with these numbers attached.',
      CareBarrier.noNhisCard =>
        '$households households are uninsured. That is a registration drive, '
            'not $households separate conversations.',
      CareBarrier.floodedRoad =>
        '$households households are cut off by water. Pre-position supplies and '
            'shift to phone follow-up for the rest of the rains.',
      CareBarrier.noTransportMoney =>
        '$households households could not afford to travel. A community '
            'transport fund or a rota of motorking drivers would reach all of '
            'them at once.',
      CareBarrier.distanceTooFar =>
        '$households households are too far from care. This is an argument for '
            'an outreach point or a maternity waiting home in this zone.',
      CareBarrier.noPermission =>
        '$households women needed permission they did not get. Engage the '
            'chief, the imam and the men\'s groups rather than repeating the '
            'same conversation compound by compound.',
      CareBarrier.pastBadExperience =>
        '$households households avoid the facility because of how they were '
            'treated. This will not improve by referring harder.',
      CareBarrier.preferredTraditional =>
        '$households households chose traditional or spiritual care. Work with '
            'those providers on danger signs rather than against them — they '
            'will see these families whatever the register says.',
      CareBarrier.farmWorkload =>
        '$households households could not leave farm or market work. Clinic '
            'hours are fighting the farming calendar and losing.',
      CareBarrier.didNotThinkItSerious =>
        '$households households did not recognise the danger. That is a '
            'communication failure on our side, not ignorance on theirs.',
      CareBarrier.noChildcare =>
        '$households mothers had no one to mind the other children. Outreach '
            'reaches them; appointments do not.',
      CareBarrier.fearOfProcedure =>
        '$households households were afraid of a procedure. Local-language '
            'explanation before the referral, not after.',
    };
  }

  static String _escalate(CareBarrier b) {
    return switch (b) {
      CareBarrier.facilityClosed =>
        'Report to the sub-district health team with the dates and household '
            'count.',
      CareBarrier.noNhisCard =>
        'Request an NHIS registration outreach for this zone.',
      CareBarrier.floodedRoad =>
        'Flag to the district assembly for culvert repair; plan around it '
            'meanwhile.',
      CareBarrier.noTransportMoney =>
        'Propose a community emergency transport fund through the CHPS '
            'committee.',
      CareBarrier.distanceTooFar =>
        'Propose an additional outreach point to the sub-district.',
      CareBarrier.noPermission =>
        'Request community engagement through the chief and religious leaders.',
      CareBarrier.pastBadExperience =>
        'Raise through the CHPS client-feedback route; ask for a service review.',
      CareBarrier.preferredTraditional =>
        'Propose formal danger-sign orientation for traditional providers.',
      CareBarrier.farmWorkload =>
        'Propose early-morning or market-day clinic hours.',
      CareBarrier.didNotThinkItSerious =>
        'Request local-language danger-sign materials and run a durbar session.',
      CareBarrier.noChildcare => 'Increase outreach frequency in this zone.',
      CareBarrier.fearOfProcedure =>
        'Request local-language counselling aids for the procedures involved.',
    };
  }
}
