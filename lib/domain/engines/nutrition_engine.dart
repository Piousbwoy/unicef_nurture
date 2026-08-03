/// Turns a nutrition classification into a plan a household in Northern Ghana
/// can actually follow this month.
///
/// This engine exists because of a specific, avoidable failure mode: showing a
/// child with MUAC 10.9 cm — severe acute malnutrition — a list of millet
/// porridge and moringa. That advice is correct for prevention and for moderate
/// wasting, and dangerously wrong for SAM, which needs therapeutic food. So the
/// pathway is decided first, and only then does food counselling appear, and
/// only where it belongs.
///
/// Everything it recommends is filtered by three things the paper protocols
/// ignore:
///   1. **Season** — the lean season (June–August) is precisely when granaries
///      are empty and wasting peaks. Advice must name what exists this month.
///   2. **Cost** — 73.7% food insecurity in the Upper East means a recommendation
///      the family cannot buy is not a recommendation.
///   3. **Age** — a 7-month-old and a 4-year-old need different textures,
///      frequencies and cautions.
library;

import '../../data/reference/local_foods.dart';
import '../enums.dart';
import '../entities/visit.dart';

/// One concrete, costed, seasonal food suggestion with the words to say.
class FoodSuggestion {
  const FoodSuggestion({
    required this.food,
    required this.reason,
    required this.householdMeasure,
    this.localName,
    this.preparation,
    this.caution,
  });

  final String food;

  /// Why this food, in a sentence a CHO can repeat.
  final String reason;

  /// "Two milk tins of millet flour", never "45 grams".
  final String householdMeasure;

  final String? localName;
  final String? preparation;
  final String? caution;

  Map<String, Object?> toJson() => {
    'food': food,
    'reason': reason,
    'household_measure': householdMeasure,
    'local_name': localName,
    'preparation': preparation,
    'caution': caution,
  };
}

/// The complete nutrition plan attached to an assessment.
class NutritionPlan {
  const NutritionPlan({
    required this.status,
    required this.pathway,
    required this.headline,
    required this.seasonNote,
    required this.suggestions,
    required this.feedingRules,
    this.mealsPerDayTarget,
    this.diversityGapsFilled = const {},
    this.therapeuticFoodRequired = false,
    this.reviewInDays,
  });

  final NutritionStatus status;
  final NutritionPathway pathway;

  /// One sentence the CHO reads to the caregiver first.
  final String headline;

  /// What this month means for food availability — the honest version.
  final String seasonNote;

  final List<FoodSuggestion> suggestions;

  /// Non-food behaviours: frequency, texture, responsive feeding, hygiene.
  final List<String> feedingRules;

  final int? mealsPerDayTarget;

  /// Which of the 8 food groups were missing, and what could fill each.
  final Map<String, List<String>> diversityGapsFilled;

  /// True when RUTF or F-75 is required — the flag that stops home-diet advice
  /// from being presented as the treatment.
  final bool therapeuticFoodRequired;

  final int? reviewInDays;

  Map<String, Object?> toJson() => {
    'status': status.name,
    'pathway': pathway.name,
    'headline': headline,
    'season_note': seasonNote,
    'suggestions': suggestions.map((s) => s.toJson()).toList(),
    'feeding_rules': feedingRules,
    'meals_per_day_target': mealsPerDayTarget,
    'diversity_gaps_filled': diversityGapsFilled,
    'therapeutic_food_required': therapeuticFoodRequired,
    'review_in_days': reviewInDays,
  };
}

/// Who the plan is for. Mothers and children need different plans from the same
/// food list.
enum NutritionSubject { child, pregnantWoman, breastfeedingWoman }

abstract final class NutritionEngine {
  /// Builds a plan. [month] is 1–12 so the caller can pass a fixed month in
  /// tests and demos rather than depending on the clock.
  static NutritionPlan plan({
    required NutritionSubject subject,
    required NutritionStatus status,
    required int month,
    int ageMonths = 0,
    bool? stillBreastfeeding,
    Set<FoodGroup> groupsEatenYesterday = const {},
    CostTier maxCost = CostTier.low,
    bool hasBilateralOedema = false,
    bool? appetiteTestPassed,
    bool? hasAnyDangerSign,
    bool isAnaemic = false,
  }) {
    final season = NorthernGhanaSeason.counsellingNote(month);
    final pathway = _pathway(
      status: status,
      subject: subject,
      ageMonths: ageMonths,
      hasBilateralOedema: hasBilateralOedema,
      appetiteTestPassed: appetiteTestPassed,
      hasAnyDangerSign: hasAnyDangerSign,
    );

    // -------------------------------------------------------------------
    // SAM: therapeutic food. Home-diet advice is deliberately withheld as a
    // treatment and reframed as what to do *after* recovery starts.
    // -------------------------------------------------------------------
    if (pathway.needsTherapeuticFood) {
      final inpatient = pathway == NutritionPathway.inpatientTherapeutic;
      return NutritionPlan(
        status: status,
        pathway: pathway,
        headline: inpatient
            ? 'This child needs inpatient therapeutic care with F-75 today. '
                  'Ordinary food at home cannot treat this, and delay costs '
                  'lives.'
            : 'This child needs RUTF from the Outpatient Therapeutic Programme, '
                  'with weekly review. Ordinary food at home cannot treat this '
                  'on its own.',
        seasonNote: season,
        therapeuticFoodRequired: true,
        reviewInDays: inpatient ? 1 : 7,
        suggestions: const [],
        feedingRules: [
          if (inpatient)
            'Refer today for inpatient care. Do not send the family home with a '
                'food list instead.'
          else
            'Refer to the nearest OTP site for RUTF. Give the first sachet under '
                'observation if you hold stock.',
          'Keep breastfeeding if the child is still breastfed — breast milk is '
              'given before RUTF at each feed, never after.',
          'Give RUTF before any family food, so the child is not too full to '
              'finish the ration.',
          'No water added to RUTF. Offer clean drinking water separately, in '
              'small sips.',
          'Continue routine treatment as prescribed: antibiotics, vitamin A per '
              'protocol, and deworming once recovering.',
          'Weigh and re-measure MUAC weekly. Discharge is decided on the '
              'measurements, not on how the child looks.',
          'Once the child is recovering, move to the local-food plan so the gain '
              'is not lost when RUTF stops. Relapse after discharge is common '
              'and preventable.',
          if (hasBilateralOedema)
            'Oedema must reduce before weight gain means anything — a swollen '
                'child can lose weight while getting better.',
        ],
      );
    }

    // -------------------------------------------------------------------
    // MAM, at-risk and prevention: this is where local foods belong.
    // -------------------------------------------------------------------
    final suggestions = <FoodSuggestion>[];
    final seen = <String>{};

    void take(List<LocalFood> foods, String reason) {
      for (final f in foods) {
        if (seen.contains(f.name)) continue;
        seen.add(f.name);
        suggestions.add(
          FoodSuggestion(
            food: f.name,
            reason: reason,
            householdMeasure: f.householdMeasure,
            localName: f.localNames.values.firstOrNull,
            preparation: f.preparation,
            caution: f.caution,
          ),
        );
      }
    }

    final effectiveAge = subject == NutritionSubject.child
        ? ageMonths
        : 60; // adults clear every child age gate

    // Energy density first — a wasted child needs calories before variety.
    if (status == NutritionStatus.moderateAcute ||
        status == NutritionStatus.atRisk) {
      take(
        LocalFoods.recommend(
          month: month,
          ageMonths: effectiveAge,
          nutrient: Nutrient.energy,
          maxCost: maxCost,
          limit: 3,
        ),
        'Energy-dense and available this month — this is what puts weight back '
        'on.',
      );
      take(
        LocalFoods.recommend(
          month: month,
          ageMonths: effectiveAge,
          nutrient: Nutrient.protein,
          maxCost: maxCost,
          limit: 3,
        ),
        'Protein for rebuilding muscle after wasting.',
      );
    }

    if (isAnaemic ||
        subject == NutritionSubject.pregnantWoman ||
        subject == NutritionSubject.breastfeedingWoman) {
      take(
        LocalFoods.recommend(
          month: month,
          ageMonths: effectiveAge,
          nutrient: Nutrient.iron,
          maxCost: maxCost,
          limit: 4,
        ),
        'Iron-rich. Maternal anaemia reaches 44% in parts of this region, and '
        'iron tablets alone rarely close the gap.',
      );
      take(
        LocalFoods.recommend(
          month: month,
          ageMonths: effectiveAge,
          nutrient: Nutrient.vitaminC,
          maxCost: maxCost,
          limit: 2,
        ),
        'Eaten with the iron food, this roughly doubles how much iron the body '
        'takes up.',
      );
    }

    take(
      LocalFoods.recommend(
        month: month,
        ageMonths: effectiveAge,
        nutrient: Nutrient.vitaminA,
        maxCost: maxCost,
        limit: 3,
      ),
      'Vitamin A protects sight and cuts the risk of dying from measles and '
      'diarrhoea.',
    );

    // Fill the specific diversity gaps for the complementary-feeding window.
    final gapsFilled = <String, List<String>>{};
    if (subject == NutritionSubject.child &&
        ageMonths >= 6 &&
        ageMonths <= 23 &&
        groupsEatenYesterday.isNotEmpty) {
      final gaps = LocalFoods.fillDiversityGaps(
        month: month,
        ageMonths: ageMonths,
        groupsEaten: groupsEatenYesterday,
        maxCost: maxCost,
      );
      for (final entry in gaps.entries) {
        gapsFilled[entry.key.label] =
            entry.value.map((f) => f.name).toList(growable: false);
        take(
          entry.value.take(1).toList(),
          'Fills the missing "${entry.key.label}" group — the child ate '
          '${groupsEatenYesterday.length} of 8 groups yesterday, and 5 is the '
          'minimum.',
        );
      }
    }

    return NutritionPlan(
      status: status,
      pathway: pathway,
      headline: _headline(status, subject, month),
      seasonNote: season,
      suggestions: suggestions.take(8).toList(growable: false),
      feedingRules: _rules(
        subject: subject,
        status: status,
        ageMonths: ageMonths,
        stillBreastfeeding: stillBreastfeeding,
        month: month,
      ),
      mealsPerDayTarget: _mealTarget(subject, ageMonths, stillBreastfeeding),
      diversityGapsFilled: gapsFilled,
      reviewInDays: switch (status) {
        NutritionStatus.severeAcute => 7,
        NutritionStatus.moderateAcute => 14,
        NutritionStatus.atRisk => 30,
        NutritionStatus.normal => 90,
      },
    );
  }

  static NutritionPathway _pathway({
    required NutritionStatus status,
    required NutritionSubject subject,
    required int ageMonths,
    required bool hasBilateralOedema,
    bool? appetiteTestPassed,
    bool? hasAnyDangerSign,
  }) {
    if (status != NutritionStatus.severeAcute) {
      return switch (status) {
        NutritionStatus.moderateAcute => NutritionPathway.supplementaryFeeding,
        NutritionStatus.atRisk => NutritionPathway.supplementaryFeeding,
        _ => NutritionPathway.preventiveCounselling,
      };
    }

    // A severely malnourished mother is not managed in a child OTP.
    if (subject != NutritionSubject.child) {
      return NutritionPathway.supplementaryFeeding;
    }

    final complicated = hasBilateralOedema ||
        appetiteTestPassed == false ||
        hasAnyDangerSign == true ||
        ageMonths < 6;

    return complicated
        ? NutritionPathway.inpatientTherapeutic
        : NutritionPathway.outpatientTherapeutic;
  }

  static String _headline(
    NutritionStatus status,
    NutritionSubject subject,
    int month,
  ) {
    final lean = NorthernGhanaSeason.isLean(month);
    return switch (status) {
      NutritionStatus.severeAcute =>
        'Severe undernutrition. Supplementary feeding plus intensive '
            'counselling, and a facility review.',
      NutritionStatus.moderateAcute => subject == NutritionSubject.child
          ? 'This child is becoming too thin. Acting now, with food the family '
                'already has, is what stops this becoming severe.'
          : 'She is undernourished while ${subject == NutritionSubject.pregnantWoman ? 'pregnant' : 'breastfeeding'}. '
                'She needs one extra meal a day, not just advice to "eat well".',
      NutritionStatus.atRisk =>
        'Not malnourished yet, but heading the wrong way. Two changes made now '
            'are worth ten made in three months.',
      NutritionStatus.normal => lean
          ? 'Nutrition is adequate. The lean season is when this slips, so agree '
                'now on what the family will do if food runs short.'
          : 'Nutrition is adequate. Name what the family is doing well, so they '
                'keep doing it.',
    };
  }

  static int? _mealTarget(
    NutritionSubject subject,
    int ageMonths,
    bool? stillBreastfeeding,
  ) {
    if (subject != NutritionSubject.child) return 4; // 3 meals + 1 extra
    if (ageMonths < 6) return null; // exclusive breastfeeding, on demand
    if (stillBreastfeeding == false) return 4;
    if (ageMonths <= 8) return 2;
    if (ageMonths <= 23) return 3;
    return 3;
  }

  static List<String> _rules({
    required NutritionSubject subject,
    required NutritionStatus status,
    required int ageMonths,
    required int month,
    bool? stillBreastfeeding,
  }) {
    final rules = <String>[];

    if (subject == NutritionSubject.child) {
      if (ageMonths < 6) {
        rules.addAll([
          'Breast milk only until 6 months — no water, no herbal preparations, '
              'no porridge. Water fills a small stomach and brings diarrhoea.',
          'Feed on demand, at least 8 to 12 times in 24 hours, including at '
              'night.',
          'If the mother believes her milk is "not enough", watch a full feed '
              'before accepting it. Almost always the problem is attachment or '
              'frequency, not supply.',
        ]);
      } else {
        final target = _mealTarget(subject, ageMonths, stillBreastfeeding);
        rules.addAll([
          if (stillBreastfeeding != false)
            'Keep breastfeeding until at least 2 years, and breastfeed *before* '
                'the meal so the child does not fill up on staple alone.',
          'Feed at least $target times a day, plus snacks. A small stomach '
              'cannot take a day\'s food in two sittings.',
          'Thick, not watery. If the porridge runs off the spoon it is mostly '
              'water and the child will stay hungry.',
          'Add one spoon of groundnut paste or red palm oil to the porridge. It '
              'costs almost nothing and roughly doubles the energy in the same '
              'volume.',
          'Feed the child from their own bowl so you can see how much they '
              'actually ate, and sit with them — a young child eating from the '
              'family bowl loses out.',
          'Be patient and encourage; do not force. Offer again later if they '
              'refuse.',
          if (ageMonths >= 6 && ageMonths <= 11)
            'Mash and soften everything at this age. Whole groundnuts, hard '
                'pieces and small bones choke children under one.',
          'Wash hands with soap before preparing food and before feeding, and '
              'feed with a clean cup and spoon rather than a bottle.',
          'Feed more, not less, during illness, and add an extra meal a day for '
              'two weeks after recovery to make up the lost ground.',
        ]);
      }
    } else {
      rules.addAll([
        subject == NutritionSubject.pregnantWoman
            ? 'One extra meal a day through pregnancy, and two extra in the last '
                  'three months.'
            : 'Two extra meals a day while breastfeeding, and drink whenever '
                  'thirsty. Milk production costs her about 500 extra calories a '
                  'day.',
        'Take the iron and folic acid tablet every day, with a sour fruit or '
            'orange if you have one.',
        'Do not drink tea or coffee with meals — it blocks iron absorption. '
            'Leave an hour either side.',
        'Use iodised salt.',
        'Eat the food first, not last. In many compounds the mother eats what '
            'is left, and that is exactly the wrong order when she is feeding '
            'two.',
      ]);
    }

    if (NorthernGhanaSeason.isLean(month)) {
      rules.add(
        'This is the lean season, when granaries are lowest and children lose '
            'weight. Prioritise the free gathered foods — moringa, baobab leaf, '
            'ayoyo, kapok leaf — and check this child again in two weeks rather '
            'than one month.',
      );
    } else if (NorthernGhanaSeason.isHarvest(month)) {
      rules.add(
        'It is harvest time. This is the month to build reserves and to dry and '
            'store leaves and vegetables for the lean months, when there will be '
            'none.',
      );
    }

    if (status == NutritionStatus.moderateAcute) {
      rules.add(
        'Agree on two changes, not ten. Write them down, and check those two at '
            'the next visit rather than starting again.',
      );
    }

    return rules;
  }

  /// Convenience for the assessment screens: attaches the plan's headline and
  /// first suggestions as recommended actions so nutrition never gets lost at
  /// the bottom of a clinical list.
  static List<RecommendedAction> asActions(NutritionPlan plan) {
    return [
      RecommendedAction(
        instruction: plan.headline,
        urgency: plan.therapeuticFoodRequired
            ? ReferralUrgency.immediate
            : ReferralUrgency.scheduled,
        rationale: plan.pathway.rationale,
        protocolSource: plan.therapeuticFoodRequired
            ? 'Ghana CMAM / WHO SAM guidelines'
            : 'WHO IYCF / Ghana nutrition counselling',
        isReferral: plan.therapeuticFoodRequired,
        isCounselling: !plan.therapeuticFoodRequired,
      ),
      if (plan.suggestions.isNotEmpty)
        RecommendedAction(
          instruction:
              'Start with: ${plan.suggestions.take(3).map((s) => s.food).join(', ')}. '
              '${plan.suggestions.first.householdMeasure}.',
          urgency: ReferralUrgency.scheduled,
          rationale: plan.seasonNote,
          protocolSource: 'Seasonal local-food counselling',
          isCounselling: true,
        ),
    ];
  }
}
