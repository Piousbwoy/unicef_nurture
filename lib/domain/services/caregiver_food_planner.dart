import '../../data/reference/local_foods.dart';
import '../entities/caregiver.dart';
import '../entities/core.dart';
import '../enums.dart';

enum CaregiverFoodGate { ready, feedingSupport, confirmAge }

class CaregiverMealIdea {
  CaregiverMealIdea({
    required this.title,
    required List<LocalFood> ingredients,
    this.forChild = true,
  }) : ingredients = List.unmodifiable(ingredients);
  final String title;
  final bool forChild;
  final List<LocalFood> ingredients;
  List<String> get preparation => [
    'Wash hands, utensils and ingredients with safe water.',
    for (final food in ingredients)
      '${food.name}: ${CaregiverFoodPlanner.preparationFor(food)}',
    forChild
        ? 'Serve freshly prepared food at a safe temperature. Sit with the child and respond to their hunger and fullness cues.'
        : 'Serve freshly prepared food at a safe temperature. Adjust the amount and texture to the person’s needs.',
  ];
}

/// Educational household ideas, intentionally not a NutritionPlan or assessment.
/// No nutrition status, adequacy score, treatment, or inferred breastfeeding.
class CaregiverFoodIdeas {
  CaregiverFoodIdeas({
    required this.gate,
    required this.message,
    required this.ageMonths,
    required List<LocalFood> available,
    required List<CaregiverMealIdea> meals,
    required List<FoodGroup> missingGroups,
  }) : available = List.unmodifiable(available),
       meals = List.unmodifiable(meals),
       missingGroups = List.unmodifiable(missingGroups);
  final CaregiverFoodGate gate;
  final String message;
  final int? ageMonths;
  final List<LocalFood> available;
  final List<CaregiverMealIdea> meals;
  final List<FoodGroup> missingGroups;
  static const disclaimer =
      'Everyday guidance, not a prescribed diet. These ideas do not prove nutrient adequacy. '
      'Follow any clinician feeding plan. Seasonal availability and cost are general guides, not live prices or guarantees.';
}

class CaregiverFoodPlanner {
  CaregiverFoodPlanner({required this.clock});
  final DateTime Function() clock;

  static int? ageMonths(Person person, DateTime now) {
    final dob = person.dateOfBirth;
    if (dob == null || dob.isAfter(now)) return null;
    var months = (now.year - dob.year) * 12 + now.month - dob.month;
    if (now.day < dob.day) months--;
    return months;
  }

  bool _child(Person person) =>
      person.clientType == ClientType.newborn ||
      person.clientType == ClientType.childUnderFive;
  bool _suitable(
    LocalFood food,
    Person person,
    int? months,
    Set<String> avoided,
  ) =>
      !avoided.contains(food.name) &&
      (!_child(person) || months != null && food.suitableFor(months)) &&
      !(person.clientType == ClientType.pregnantWoman &&
          food.name.startsWith('Liver'));

  CaregiverFoodIdeas build(Person person, CaregiverSettings settings) {
    final now = clock();
    final months = ageMonths(person, now);
    if (_child(person) && (months == null || months < 6)) {
      return CaregiverFoodIdeas(
        gate: months == null
            ? CaregiverFoodGate.confirmAge
            : CaregiverFoodGate.feedingSupport,
        message: months == null
            ? 'Confirm the child’s age before choosing age-specific foods.'
            : 'Under six months: feeding support comes first. Do not offer water, porridge or family foods now. '
                  'Ask a health worker for individual help if breastfeeding is not possible or feeding is difficult.',
        ageMonths: months,
        available: const [],
        meals: const [],
        missingGroups: const [],
      );
    }
    final available = LocalFoods.all
        .where(
          (food) =>
              settings.foodsHave.contains(food.name) &&
              _suitable(food, person, months, settings.foodsAvoid),
        )
        .toList();
    _sort(available, settings.lowCost, now.month);
    final staples = available
        .where((f) => f.group == FoodGroup.grainsRootsTubers)
        .toList();
    final additions = available
        .where(
          (f) =>
              {
                FoodGroup.pulsesNutsSeeds,
                FoodGroup.fleshFoods,
                FoodGroup.eggs,
              }.contains(f.group) &&
              f.name != 'Dawadawa (locust bean)',
        )
        .toList();
    final produce = available
        .where(
          (f) =>
              {
                FoodGroup.vitaminARichProduce,
                FoodGroup.otherProduce,
              }.contains(f.group) &&
              f.name != 'Red palm oil',
        )
        .toList();
    final meals = <CaregiverMealIdea>[];
    for (final staple in staples.take(3)) {
      if (staple.name == 'Cassava' && additions.isEmpty) continue;
      final ingredients = [
        staple,
        if (additions.isNotEmpty) additions.first,
        if (produce.isNotEmpty) produce.first,
      ];
      meals.add(
        CaregiverMealIdea(
          title: ingredients.map((f) => f.name).join(' + '),
          ingredients: ingredients,
          forChild: _child(person),
        ),
      );
    }
    final groups = available.map((f) => f.group).toSet();
    return CaregiverFoodIdeas(
      gate: CaregiverFoodGate.ready,
      ageMonths: months,
      message: available.isEmpty
          ? 'Choose foods you have. If none are suitable, ask a health worker for feeding support.'
          : staples.isEmpty
          ? 'No suitable staple is selected. You can still explore these ingredients and same-group alternatives.'
          : meals.isEmpty
          ? 'A suitable meal combination is not available. Cassava needs beans, groundnut paste or fish alongside it.'
          : 'Ideas using foods you said you have. Household measures describe ingredients, not required portions.',
      available: available,
      meals: meals,
      missingGroups: [
        for (final group in FoodGroup.values)
          if (group != FoodGroup.breastMilk && !groups.contains(group)) group,
      ],
    );
  }

  List<LocalFood> alternatives(
    LocalFood food,
    Person person,
    CaregiverSettings settings,
  ) {
    final now = clock();
    final months = ageMonths(person, now);
    if (_child(person) && (months == null || months < 6)) return const [];
    final choices = LocalFoods.all
        .where(
          (candidate) =>
              candidate.name != food.name &&
              candidate.group == food.group &&
              _suitable(candidate, person, months, settings.foodsAvoid) &&
              (settings.foodsHave.contains(candidate.name) ||
                  candidate.availableIn(now.month) &&
                      (!settings.lowCost ||
                          candidate.cost.rank <= CostTier.low.rank)),
        )
        .toList();
    _sort(choices, settings.lowCost, now.month);
    return choices;
  }

  void _sort(List<LocalFood> foods, bool lowCost, int month) =>
      foods.sort((a, b) {
        if (lowCost && a.cost.rank != b.cost.rank)
          return a.cost.rank.compareTo(b.cost.rank);
        if (a.availableIn(month) != b.availableIn(month))
          return a.availableIn(month) ? -1 : 1;
        return a.name.compareTo(b.name);
      });

  /// Practical preparation only: the source dataset's promotional nutrient,
  /// price, and health-outcome claims are not reused as caregiver instructions.
  /// Clinical review basis: WHO complementary feeding guideline (2023) and
  /// Five Keys to Safer Food (2006). Restrictions/cautions remain visible.
  static String? cautionFor(LocalFood food) => switch (food.name) {
    'Groundnut paste' =>
      'Use smooth paste mixed into food, never whole nuts or a lump of paste for a young child. Reject moldy nuts.',
    'Dried / smoked fish' ||
    'Fresh tilapia' => 'Remove bones carefully before serving to a child.',
    'Maize' => 'Discard moldy or discolored grain.',
    _ => food.caution,
  };

  static String preparationFor(LocalFood food) {
    switch (food.name) {
      case 'Groundnut paste':
        return 'Use smooth paste, mixed well into food. Never offer whole nuts or a lump of paste.';
      case 'Millet':
      case 'Sorghum':
      case 'Maize':
        return 'Use clean flour. Cook thoroughly into a soft porridge that stays on the spoon.';
      case 'Soybean':
        return 'Roast, dehull and grind; cook the flour thoroughly with the staple.';
      case 'Cassava':
        return 'Use safely processed cassava. Peel and cook thoroughly; never serve raw.';
      case 'Dried / smoked fish':
      case 'Fresh tilapia':
        return 'Remove bones carefully, cook thoroughly and flake or grind finely.';
      case 'Mango':
      case 'Pawpaw (papaya)':
        return 'Wash, peel, remove seeds or stones, and mash ripe flesh.';
      case 'Red palm oil':
        return 'Stir a small amount into cooked food.';
      case 'Dawadawa (locust bean)':
        return 'Crumble into soup or stew and cook thoroughly.';
      case 'Sesame (beniseed)':
        return 'Grind seeds finely and mix into cooked food.';
      case 'Baobab fruit pulp':
        return 'Use clean pulp powder mixed into prepared food.';
      case 'Fresh cow milk':
        return 'Boil before use. Not a main drink under one year; do not replace breastfeeding.';
      case 'Wagashi (local cheese)':
        return 'Cook thoroughly and mash before offering to a child.';
    }
    return switch (food.group) {
      FoodGroup.pulsesNutsSeeds => 'Soak beans, cook until very soft and mash.',
      FoodGroup.eggs => 'Cook both white and yolk fully, then mash.',
      FoodGroup.fleshFoods =>
        'Cook thoroughly, remove bones and shred or mash finely.',
      FoodGroup.grainsRootsTubers =>
        'Cook thoroughly until soft, then mash for a young child.',
      _ =>
        'Wash, chop finely and cook until soft; mash to suit the child’s ability.',
    };
  }
}
