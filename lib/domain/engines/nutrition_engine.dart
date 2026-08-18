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
import 'nutrition/therapeutic_supplements.dart';

/// One concrete, costed, seasonal food suggestion with the words to say.
class FoodSuggestion {
  const FoodSuggestion({
    required this.food,
    required this.reason,
    required this.householdMeasure,
    required this.group,
    this.localName,
    this.preparation,
    this.caution,
  });

  final String food;

  /// Why this food, in a sentence a CHO can repeat.
  final String reason;

  /// "Two milk tins of millet flour", never "45 grams".
  final String householdMeasure;

  /// The WHO food group this food belongs to — the hook the day-plan
  /// composer uses to place it at breakfast, lunch or dinner.
  final FoodGroup group;

  final String? localName;
  final String? preparation;
  final String? caution;

  Map<String, Object?> toJson() => {
    'food': food,
    'reason': reason,
    'household_measure': householdMeasure,
    'group': group.name,
    'local_name': localName,
    'preparation': preparation,
    'caution': caution,
  };
}

/// One slot in a day's plate: a moment, the foods from the chosen
/// basket that fill it, and the texture / measure note for this age.
/// A basket of foods is a shopping list; slots make it a day the
/// caregiver can actually cook.
class MealSlot {
  const MealSlot({required this.moment, required this.foods, this.note});

  /// "Breakfast", "Lunch", "Her extra meal"…
  final String moment;

  /// Food names drawn from the plan's basket.
  final List<String> foods;

  final String? note;

  Map<String, Object?> toJson() => {
    'moment': moment,
    'foods': foods,
    'note': note,
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
    this.therapeuticPlan,
    this.dayPlan = const [],
    this.dayPlanNote,
    this.nutrientCoverage = const {},
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

  /// Pillar 2: targeted therapeutic supplements (MMS, IFA, RUTF, KMC).
  /// Empty for normal nutrition status, populated for anaemia in
  /// pregnancy, LBW, or SAM. Each supplement carries its own WHO/GHS
  /// citation for the audit log.
  final TherapeuticPlan? therapeuticPlan;

  /// The basket composed into meals: what to cook at each moment of
  /// the day, in the texture and measure this age can take. Empty when
  /// food counselling does not apply (SAM — therapeutic food first;
  /// infants under six months — breast milk only).
  final List<MealSlot> dayPlan;

  /// The age-band sentence that governs the day plan: texture, cup
  /// size, frequency. Null when [dayPlan] is empty.
  final String? dayPlanNote;

  /// The explainability audit for the recommender: for every nutrient
  /// need this assessment raised, which basket foods answer it. A plan
  /// that can show its coverage can defend its choices.
  final Map<String, List<String>> nutrientCoverage;

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
    'day_plan': [for (final m in dayPlan) m.toJson()],
    'day_plan_note': dayPlanNote,
    'nutrient_coverage': nutrientCoverage,
    if (therapeuticPlan != null)
      'therapeutic_plan': {
        'counselling_headline': therapeuticPlan!.counsellingHeadline,
        'supplements': [
          for (final s in therapeuticPlan!.supplements)
            {
              'id': s.id,
              'label': s.label,
              'dose': s.dose,
              'schedule': s.schedule,
              'duration': s.duration,
              'counselling_note': s.counsellingNote,
              'contraindications': s.contraindications,
              'local_sources': s.localSources,
              'citation': s.citation.toMap(),
            },
        ],
        'activated_by': therapeuticPlan!.activatedBy,
      },
  };
}

/// Who the plan is for. Mothers and children need different plans from the same
/// food list.
enum NutritionSubject { child, pregnantWoman, breastfeedingWoman }

/// Sentinel used by [NutritionEngine.plan] when a named food in the
/// regional stack is not present in the local-food list. Empty name
/// causes the [LocalFoods.recommend] loop to skip it.
const _emptyLocalFood = LocalFood(
  name: '',
  group: FoodGroup.grainsRootsTubers,
  nutrients: [],
  monthsAvailable: [],
  cost: CostTier.veryLow,
  householdMeasure: '',
  minAgeMonths: 0,
);

abstract final class NutritionEngine {
  /// Builds a plan. [month] is 1–12 so the caller can pass a fixed month in
  /// tests and demos rather than depending on the clock.
  ///
  /// [therapeuticContext] feeds the Pillar 2 supplement selector. When
  /// provided, the plan includes MMS, IFA, KMC and RUTF recommendations
  /// alongside the local-food list. Each supplement carries its own
  /// WHO/GHS citation for the audit log.
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
    bool hasDiarrhoea = false,
    TherapeuticContext? therapeuticContext,
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
    // Pillar 2: targeted therapeutic supplements. Computed once, used in
    // both the SAM and the non-SAM branches. The selector picks MMS for
    // any pregnant woman, IFA for non-pregnant anaemic women, KMC for
    // LBW infants, and RUTF for SAM children in the OTP age window.
    // -------------------------------------------------------------------
    final therapeuticPlan = TherapeuticSupplementSelector.select(
      context: therapeuticContext ?? const TherapeuticContext(),
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
        therapeuticPlan: therapeuticPlan,
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
    // MAM, at-risk and prevention: local foods — chosen by what *this*
    // assessment found, never read off a fixed list. The engine first
    // derives a weighted nutrient-need profile from the results (wasting
    // → energy + protein; anaemia or a mother → iron plus the vitamin C
    // that doubles its uptake; everyone → vitamin A), then scores every
    // seasonal, affordable, age-right local food against that profile.
    // Same compound, same month — a different child gets a different
    // basket, and every food can say why it is there.
    // -------------------------------------------------------------------
    final effectiveAge = subject == NutritionSubject.child
        ? ageMonths
        : 60; // adults clear every child age gate

    final needs = _nutrientNeeds(
      status: status,
      subject: subject,
      isAnaemic: isAnaemic,
      hasDiarrhoea: hasDiarrhoea,
    );
    final ironPriority = needs.any((n) => n.$1 == Nutrient.iron);

    // Candidates: right for the child's age, and either in season inside
    // the household's cost ceiling — or one of the four regional iron
    // anchors when iron is the priority. The anchors bypass the season
    // and cost gates deliberately: the literature (Adokiya 2022, Saaka
    // 2015) names them the available, affordable, culturally-resonant
    // carriers of iron in this region, year-round.
    final candidates = LocalFoods.all.where(
      (f) =>
          f.suitableFor(effectiveAge) &&
          ((ironPriority && _regionalIronAnchors.contains(f.name)) ||
              (f.availableIn(month) && f.cost.rank <= maxCost.rank)),
    );
    final scored = <(LocalFood, double)>[
      for (final f in candidates) (f, _foodScore(f, needs)),
    ]..sort((a, b) => b.$2.compareTo(a.$2));

    final suggestions = <FoodSuggestion>[];
    final chosen = <LocalFood>[];
    final seen = <String>{};
    for (final (food, score) in scored) {
      if (score <= 0 || suggestions.length >= 8) break;
      seen.add(food.name);
      chosen.add(food);
      suggestions.add(
        FoodSuggestion(
          food: food.name,
          reason: _reasonFor(
            food,
            needs,
            subject: subject,
            isAnaemic: isAnaemic,
          ),
          householdMeasure: food.householdMeasure,
          group: food.group,
          localName: food.localNames.values.firstOrNull,
          preparation: food.preparation,
          caution: food.caution,
        ),
      );
    }

    // Fill the specific diversity gaps for the complementary-feeding
    // window — the one food per missing group, chosen by the food list
    // itself, appended after the scored basket.
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
      for (final gap in gaps.entries) {
        gapsFilled[gap.key.label] = gap.value
            .map((f) => f.name)
            .toList(growable: false);
        if (suggestions.length >= 8) continue;
        final fill = gap.value.firstWhere(
          (f) => !seen.contains(f.name),
          orElse: () => _emptyLocalFood,
        );
        if (fill.name.isEmpty) continue;
        seen.add(fill.name);
        chosen.add(fill);
        suggestions.add(
          FoodSuggestion(
            food: fill.name,
            reason: 'Fills the missing "${gap.key.label}" group — the child '
                'ate ${groupsEatenYesterday.length} of 8 groups yesterday, '
                'and 5 is the minimum.',
            householdMeasure: fill.householdMeasure,
            group: fill.group,
            localName: fill.localNames.values.firstOrNull,
            preparation: fill.preparation,
            caution: fill.caution,
          ),
        );
      }
    }

    // The explainability audit: for every need this assessment raised,
    // name the basket foods that answer it.
    final coverage = <String, List<String>>{};
    for (final (nutrient, _) in needs) {
      final covers = [
        for (final f in chosen)
          if (f.provides(nutrient)) f.name,
      ];
      if (covers.isNotEmpty) coverage[nutrient.label] = covers;
    }

    // The basket composed into a day: meals, in the texture and measure
    // this age can take. Under six months the day plan is deliberately
    // empty — breast milk only is the entire message.
    final dayPlanNote = _dayPlanNote(subject, ageMonths);
    final dayPlan = (subject == NutritionSubject.child && ageMonths < 6)
        ? const <MealSlot>[]
        : _composeDayPlan(
            subject: subject,
            status: status,
            basket: suggestions,
          );

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
        hasDiarrhoea: hasDiarrhoea,
      ),
      mealsPerDayTarget: _mealTarget(subject, ageMonths, stillBreastfeeding),
      diversityGapsFilled: gapsFilled,
      therapeuticPlan: therapeuticPlan,
      dayPlan: dayPlan,
      dayPlanNote: dayPlanNote,
      nutrientCoverage: coverage,
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

    final complicated =
        hasBilateralOedema ||
        appetiteTestPassed == false ||
        hasAnyDangerSign == true ||
        ageMonths < 6;

    return complicated
        ? NutritionPathway.inpatientTherapeutic
        : NutritionPathway.outpatientTherapeutic;
  }

  // ------------------------------------------- Result-driven food selection

  /// The four literature-backed carriers of iron and protein in Northern
  /// Ghana (Adokiya 2022 maternal anaemia, n=420; Saaka 2015 IYCF). They
  /// carry a scoring bonus and bypass the season / cost gates when iron
  /// is the priority — the region's year-round anchors.
  static const Set<String> _regionalIronAnchors = {
    'Moringa leaves',
    'Dawadawa (locust bean)',
    'Bambara beans',
    'Groundnut paste',
  };

  /// The nutrient-need profile this assessment's results demand, weighted
  /// by how badly. This is the hinge of the recommender: the basket a
  /// family hears is derived from *their* findings — wasting, anaemia,
  /// the mother's life stage — never from a fixed list.
  static List<(Nutrient, double)> _nutrientNeeds({
    required NutritionStatus status,
    required NutritionSubject subject,
    required bool isAnaemic,
    required bool hasDiarrhoea,
  }) {
    final needs = <(Nutrient, double)>[];
    // Wasting: calories before variety.
    if (status == NutritionStatus.moderateAcute ||
        status == NutritionStatus.atRisk) {
      needs.add((Nutrient.energy, 3.0));
      needs.add((Nutrient.protein, 2.5));
    }
    // Anaemia — measured, or carried by pregnancy / lactation, where it
    // is the region's most common hidden deficit.
    if (isAnaemic ||
        subject == NutritionSubject.pregnantWoman ||
        subject == NutritionSubject.breastfeedingWoman) {
      needs.add((Nutrient.iron, 3.0));
      // Vitamin C alongside: it roughly doubles iron uptake, so it is
      // weighted as part of the iron answer, not a separate topic.
      needs.add((Nutrient.vitaminC, 2.0));
      needs.add((Nutrient.protein, 1.5));
    }
    // Everyone: vitamin A guards sight and survival.
    needs.add((Nutrient.vitaminA, 1.0));
    // Diarrhoea drains zinc faster than any other illness, and zinc is
    // what shortens the episode and protects the next one (WHO/UNICEF
    // zinc protocol: 10–14 days alongside continued feeding).
    if (hasDiarrhoea) {
      needs.add((Nutrient.zinc, 2.5));
    }
    return needs;
  }

  /// Scores one food against the need profile. A food scores only for
  /// nutrients it actually provides; the earlier a nutrient ranks in the
  /// food's own list, the stronger the source it is.
  static double _foodScore(LocalFood food, List<(Nutrient, double)> needs) {
    var score = 0.0;
    for (final (nutrient, weight) in needs) {
      final index = food.nutrients.indexOf(nutrient);
      if (index < 0) continue;
      final strength =
          (food.nutrients.length - index) / food.nutrients.length;
      score += weight * strength;
    }
    if (_regionalIronAnchors.contains(food.name)) {
      score += 2.5; // the regional anchors stay visible in the basket
    }
    if (food.cost == CostTier.freeOrGathered) {
      score += 0.4; // free gathered foods win ties in the lean season
    }
    return score;
  }

  /// Why this food, in the voice of the need that earned it a place —
  /// so the counselling adapts to the assessment instead of repeating a
  /// stock line.
  static String _reasonFor(
    LocalFood food,
    List<(Nutrient, double)> needs, {
    required NutritionSubject subject,
    required bool isAnaemic,
  }) {
    (Nutrient, double)? best;
    for (final need in needs) {
      if (!food.provides(need.$1)) continue;
      if (best == null || need.$2 > best.$2) best = need;
    }
    return switch (best?.$1) {
      Nutrient.energy =>
        'Chosen for this assessment: energy-dense and available this month '
            '— this is what puts weight back on.',
      Nutrient.protein =>
        subject == NutritionSubject.child
            ? 'Protein for rebuilding muscle after the wasting this '
                  'assessment found.'
            : 'Protein — she is feeding two, and this food was picked for '
                  'her results, not from a fixed list.',
      Nutrient.iron =>
        isAnaemic
            ? 'Iron for the blood — this assessment found anaemia. Give it '
                  'with a sour fruit or baobab so the body takes up more.'
            : 'Regional iron anchor. Maternal anaemia reaches 44% in parts '
                  'of this region (Adokiya 2022), and iron tablets alone '
                  'rarely close the gap.',
      Nutrient.vitaminC =>
        'Eaten with the iron food, this roughly doubles how much iron the '
            'body takes up.',
      _ =>
        'Vitamin A protects sight and cuts the risk of dying from measles '
            'and diarrhoea.',
    };
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
      NutritionStatus.moderateAcute =>
        subject == NutritionSubject.child
            ? 'This child is becoming too thin. Acting now, with food the family '
                  'already has, is what stops this becoming severe.'
            : 'She is undernourished while ${subject == NutritionSubject.pregnantWoman ? 'pregnant' : 'breastfeeding'}. '
                  'She needs one extra meal a day, not just advice to "eat well".',
      NutritionStatus.atRisk =>
        'Not malnourished yet, but heading the wrong way. Two changes made now '
            'are worth ten made in three months.',
      NutritionStatus.normal =>
        lean
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
    bool hasDiarrhoea = false,
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

    if (hasDiarrhoea) {
      rules.add(
        subject == NutritionSubject.child
            ? 'Diarrhoea drains fluids and zinc. Give zinc for 10 days (10 mg '
                  'a day under 6 months, 20 mg from 6 months), extra fluid '
                  'after every loose stool, and keep feeding — food rebuilds '
                  'the gut, starving it makes the episode last longer.'
            : 'With diarrhoea, take more fluids than usual and keep eating '
                  'small, regular meals. If there is blood in the stool, '
                  'fever, or signs of dehydration, seek care the same day.',
      );
      if (subject == NutritionSubject.child && stillBreastfeeding != false) {
        rules.add(
          'Breastfeed more often during diarrhoea, not less — breast milk is '
          'the safest fluid and the best medicine the child has right now.',
        );
      }
    }

    return rules;
  }

  // ----------------------------------------------------- The day's plate

  /// The age-band sentence that governs the day plan: texture, cup size,
  /// frequency — WHO IYCF indicators translated into words a caregiver
  /// can cook by.
  static String? _dayPlanNote(NutritionSubject subject, int ageMonths) {
    if (subject != NutritionSubject.child) {
      return subject == NutritionSubject.pregnantWoman
          ? 'Three meals plus one extra meal every day — two extra meals in '
                'the last three months. She eats first, not last.'
          : 'Three meals plus two extra meals every day, and drink whenever '
                'thirsty — milk production costs her 500 calories a day.';
    }
    if (ageMonths < 6) {
      return 'Breast milk only — no food, no water, no porridge yet. Feed on '
          'demand, day and night.';
    }
    if (ageMonths <= 8) {
      return 'Mash everything until it is thick enough to stay on the spoon. '
          'Start each feed with 2–3 spoonfuls, building to half a cup.';
    }
    if (ageMonths <= 11) {
      return 'Chop soft or mash. Half a cup per meal, plus one or two '
          'snacks.';
    }
    if (ageMonths <= 23) {
      return 'Family food, cut small. Three-quarters of a cup per meal, plus '
          'one or two snacks.';
    }
    return 'Family food — serve the child first, from their own bowl.';
  }

  /// The basket composed into a day. Staples carry breakfast and dinner,
  /// the body-builders carry lunch, the protectors fill the gaps between.
  /// Every food comes from the scored basket — the day plan never
  /// recommends anything the plan has not already justified.
  static List<MealSlot> _composeDayPlan({
    required NutritionSubject subject,
    required NutritionStatus status,
    required List<FoodSuggestion> basket,
  }) {
    if (basket.isEmpty) return const [];

    const proteinGroups = {
      FoodGroup.pulsesNutsSeeds,
      FoodGroup.fleshFoods,
      FoodGroup.eggs,
      FoodGroup.dairy,
    };
    const produceGroups = {
      FoodGroup.vitaminARichProduce,
      FoodGroup.otherProduce,
    };

    /// The first unused food from [groups], else the first unused food at
    /// all, else the first food — a slot is never left empty while the
    /// basket still has something to give.
    String pick(Set<FoodGroup> groups, Set<String> used) {
      for (final s in basket) {
        if (groups.contains(s.group) && used.add(s.food)) return s.food;
      }
      for (final s in basket) {
        if (used.add(s.food)) return s.food;
      }
      return basket.first.food;
    }

    final wasting = status == NutritionStatus.moderateAcute ||
        status == NutritionStatus.atRisk;
    final fortify = wasting
        ? 'Stir in one spoon of groundnut paste or red palm oil — it roughly '
              'doubles the energy in the same bowl.'
        : null;

    final breakfast = pick({FoodGroup.grainsRootsTubers}, {});
    final slots = <MealSlot>[
      MealSlot(moment: 'Breakfast', foods: [breakfast], note: fortify),
    ];

    if (subject == NutritionSubject.child) {
      final used = {breakfast};
      final lunchMain = pick(proteinGroups, used);
      final lunchVeg = pick(produceGroups, used);
      slots.add(
        MealSlot(moment: 'Lunch', foods: [lunchMain, lunchVeg]),
      );
      final snack = pick(produceGroups, used);
      slots.add(
        MealSlot(
          moment: 'Snack',
          foods: [snack],
          note: wasting ? 'A snack between meals protects the weight gain.' : null,
        ),
      );
      final dinnerStaple = pick({FoodGroup.grainsRootsTubers}, used);
      final dinnerSide = pick(proteinGroups, used);
      slots.add(
        MealSlot(moment: 'Dinner', foods: [dinnerStaple, dinnerSide]),
      );
    } else {
      final used = {breakfast};
      final lunchMain = pick(proteinGroups, used);
      final lunchVeg = pick(produceGroups, used);
      slots.add(
        MealSlot(moment: 'Lunch', foods: [lunchMain, lunchVeg]),
      );
      final dinnerStaple = pick({FoodGroup.grainsRootsTubers}, used);
      final dinnerSide = pick(proteinGroups, used);
      slots.add(
        MealSlot(moment: 'Dinner', foods: [dinnerStaple, dinnerSide]),
      );
      slots.add(
        MealSlot(
          moment: 'Her extra meal',
          foods: [pick({...produceGroups, ...proteinGroups}, used)],
          note: 'The meal she is owed for feeding two — small, but every day.',
        ),
      );
    }

    return slots;
  }

  /// Convenience for the assessment screens: attaches the plan's headline and
  /// first suggestions as recommended actions so nutrition never gets lost at
  /// the bottom of a clinical list. Pillar 2 therapeutic supplements are
  /// surfaced as their own actions (MMS, IFA, RUTF, KMC) so the audit log
  /// records each prescription individually.
  static List<RecommendedAction> asActions(NutritionPlan plan) {
    final actions = <RecommendedAction>[
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

    // Pillar 2 supplements as individual recommended actions.
    final tp = plan.therapeuticPlan;
    if (tp != null) {
      for (final s in tp.supplements) {
        actions.add(
          RecommendedAction(
            instruction: '${s.label}: ${s.dose}',
            urgency: switch (s.id) {
              'sam_rutf_who2023_v1' => ReferralUrgency.immediate,
              'kmc_lbw_who2015_v1' => ReferralUrgency.immediate,
              'anc_mms_who2020_v1' => ReferralUrgency.scheduled,
              _ => ReferralUrgency.scheduled,
            },
            rationale: s.counsellingNote,
            protocolSource: s.citation.shortName,
            isTreatment: true,
            isCounselling: true,
          ),
        );
      }
    }

    return actions;
  }
}
