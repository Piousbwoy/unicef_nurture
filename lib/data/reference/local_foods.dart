/// Local-food nutrition intelligence for Northern Ghana.
///
/// The hackathon challenge asks: *"What can this household afford and access?"*
/// A generic food list cannot answer that. This dataset therefore carries, for
/// every food, the three things that decide whether advice is actionable:
///
///   1. **Seasonality** — which months it is actually available. Recommending
///      fresh leafy vegetables in February, or telling a household to buy maize
///      in July when stores are empty and prices peak, destroys trust.
///   2. **Cost tier** — what a household in the lowest quintile can reach.
///   3. **Household measure** — advice is given in milk tins, handfuls and
///      ladles, never grams. Nobody in Wantugu owns a kitchen scale.
///
/// Northern Ghana has a **single rainy season** (May–October) and a long dry
/// Harmattan season (November–April). The **lean season is June–August**, when
/// last year's harvest is exhausted and the new one is not yet in. Harvest runs
/// August–December. Nutrition advice must bend around that calendar.
library;

/// The eight WHO/UNICEF food groups used to compute Minimum Dietary Diversity
/// (MDD) for children 6–23 months. A child meets MDD at **>= 5 of 8** groups
/// in the previous 24 hours.
enum FoodGroup {
  breastMilk('Breast milk'),
  grainsRootsTubers('Grains, roots, tubers'),
  pulsesNutsSeeds('Beans, nuts, seeds'),
  dairy('Milk and dairy'),
  fleshFoods('Meat, fish, poultry'),
  eggs('Eggs'),
  vitaminARichProduce('Vitamin-A rich fruits & vegetables'),
  otherProduce('Other fruits & vegetables');

  const FoodGroup(this.label);
  final String label;
}

/// Nutrients that drive maternal and child survival in this context.
/// Iron and vitamin A dominate because maternal anaemia in the Upper West runs
/// above 44% and child vitamin-A deficiency drives measles and diarrhoea deaths.
enum Nutrient {
  energy('Energy'),
  protein('Protein'),
  iron('Iron'),
  vitaminA('Vitamin A'),
  zinc('Zinc'),
  calcium('Calcium'),
  folate('Folate'),
  vitaminC('Vitamin C');

  const Nutrient(this.label);
  final String label;
}

/// What a household in the poorest quintile can realistically reach.
enum CostTier {
  /// Grown at home, gathered wild, or effectively free.
  freeOrGathered('Free / gathered', 0),

  /// A few pesewas. Reachable even in the lean season.
  veryLow('Very cheap', 1),

  /// Affordable on a market day.
  low('Cheap', 2),

  /// Occasional purchase; a stretch for the poorest.
  moderate('Moderate', 3),

  /// Festival or emergency purchase only.
  high('Expensive', 4);

  const CostTier(this.label, this.rank);
  final String label;
  final int rank;
}

class LocalFood {
  const LocalFood({
    required this.name,
    required this.group,
    required this.nutrients,
    required this.monthsAvailable,
    required this.cost,
    required this.householdMeasure,
    required this.minAgeMonths,
    this.localNames = const {},
    this.preparation,
    this.caution,
  });

  final String name;
  final FoodGroup group;

  /// Nutrients this food meaningfully contributes, strongest first.
  final List<Nutrient> nutrients;

  /// Months (1 = January) when the food is genuinely available in northern
  /// markets or households. Storable staples list all twelve.
  final List<int> monthsAvailable;

  final CostTier cost;

  /// Practical measure a caregiver can act on without any equipment.
  final String householdMeasure;

  /// Youngest age in months at which this is appropriate as a complementary
  /// food. 6 = from start of complementary feeding.
  final int minAgeMonths;

  /// Local-language names, keyed by language. Saying "Zogale" instead of
  /// "moringa" is the difference between advice landing and bouncing.
  final Map<String, String> localNames;

  final String? preparation;

  /// Safety note the CHO must voice — e.g. choking risk, aflatoxin.
  final String? caution;

  bool availableIn(int month) => monthsAvailable.contains(month);

  bool suitableFor(int ageMonths) => ageMonths >= minAgeMonths;

  bool provides(Nutrient n) => nutrients.contains(n);

  String localName(String language) => localNames[language] ?? name;
}

abstract final class NorthernGhanaSeason {
  static const List<int> _all = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];

  /// Depleted stores, peak food prices, peak child wasting. June–August.
  static const List<int> leanSeason = [6, 7, 8];

  /// Harvest and relative plenty. August–December.
  static const List<int> harvestSeason = [8, 9, 10, 11, 12];

  /// Rains: wild and cultivated green leaves are abundant. May–October.
  static const List<int> rainySeason = [5, 6, 7, 8, 9, 10];

  /// Harmattan. Fresh produce scarce except near irrigation dams.
  static const List<int> drySeason = [11, 12, 1, 2, 3, 4];

  static bool isLean(int month) => leanSeason.contains(month);
  static bool isHarvest(int month) => harvestSeason.contains(month);

  static String label(int month) {
    if (isLean(month)) return 'Lean season — food stores are low';
    if (isHarvest(month)) return 'Harvest season — more food available';
    if (drySeason.contains(month)) return 'Dry season — fresh leaves are scarce';
    return 'Rainy season';
  }

  /// Plain-language note the CHO can read aloud to a caregiver.
  static String counsellingNote(int month) {
    if (isLean(month)) {
      return 'Food is short and prices are high this month. Focus on Zogale '
          '(moringa), dawadawa, groundnut paste and dried fish — these stay '
          'available and cheap when the granary is empty.';
    }
    if (isHarvest(month)) {
      return 'Harvest is in. This is the best month to build the child up and '
          'to dry and store leaves for the dry season ahead.';
    }
    if (drySeason.contains(month)) {
      return 'Fresh leaves are scarce. Use dried baobab and moringa leaf '
          'powder, and vegetables from the dam gardens.';
    }
    return 'Rains have started. Wild and garden leaves are coming in — add a '
        'handful of green leaves to the porridge every day.';
  }
}

abstract final class LocalFoods {
  static const List<int> _yearRound = NorthernGhanaSeason._all;

  static const List<LocalFood> all = [
    // ------------------------------------------- Grains, roots and tubers
    LocalFood(
      name: 'Millet',
      group: FoodGroup.grainsRootsTubers,
      nutrients: [Nutrient.energy, Nutrient.iron, Nutrient.zinc],
      monthsAvailable: _yearRound,
      cost: CostTier.veryLow,
      householdMeasure: 'One milk tin of millet flour',
      minAgeMonths: 6,
      localNames: {'Dagbani': 'Za', 'Gurene (Frafra)': 'Naara'},
      preparation:
          'Roast lightly then grind. Cook a thick porridge (koko) that sits on '
          'the spoon — thin porridge fills the stomach without feeding.',
    ),
    LocalFood(
      name: 'Sorghum',
      group: FoodGroup.grainsRootsTubers,
      nutrients: [Nutrient.energy, Nutrient.iron],
      monthsAvailable: _yearRound,
      cost: CostTier.veryLow,
      householdMeasure: 'One milk tin of sorghum flour',
      minAgeMonths: 6,
      localNames: {'Dagbani': 'Kaɣili'},
      preparation: 'Ferment overnight for easier digestion and more iron uptake.',
    ),
    LocalFood(
      name: 'Maize',
      group: FoodGroup.grainsRootsTubers,
      nutrients: [Nutrient.energy],
      monthsAvailable: _yearRound,
      cost: CostTier.veryLow,
      householdMeasure: 'One milk tin of maize flour',
      minAgeMonths: 6,
      localNames: {'Dagbani': 'Kawana'},
      caution:
          'Discard mouldy or discoloured grain — aflatoxin harms growth and the '
          'liver, and children are most at risk.',
    ),
    LocalFood(
      name: 'Rice',
      group: FoodGroup.grainsRootsTubers,
      nutrients: [Nutrient.energy],
      monthsAvailable: _yearRound,
      cost: CostTier.low,
      householdMeasure: 'One milk tin of cooked rice, mashed soft',
      minAgeMonths: 6,
      localNames: {'Dagbani': 'Shinkaafa'},
    ),
    LocalFood(
      name: 'Yam',
      group: FoodGroup.grainsRootsTubers,
      nutrients: [Nutrient.energy, Nutrient.vitaminC],
      monthsAvailable: [10, 11, 12, 1, 2, 3],
      cost: CostTier.low,
      householdMeasure: 'Two slices, boiled and mashed',
      minAgeMonths: 6,
      localNames: {'Dagbani': 'Nyuya'},
    ),
    LocalFood(
      name: 'Orange-fleshed sweet potato',
      group: FoodGroup.vitaminARichProduce,
      nutrients: [Nutrient.vitaminA, Nutrient.energy, Nutrient.vitaminC],
      monthsAvailable: [9, 10, 11, 12, 1, 2],
      cost: CostTier.veryLow,
      householdMeasure: 'One small tuber, boiled and mashed',
      minAgeMonths: 6,
      preparation:
          'Choose the orange-fleshed kind, not white. One tuber covers a young '
          'child\'s vitamin A need for the day.',
    ),
    LocalFood(
      name: 'Cassava',
      group: FoodGroup.grainsRootsTubers,
      nutrients: [Nutrient.energy],
      monthsAvailable: _yearRound,
      cost: CostTier.veryLow,
      householdMeasure: 'One ladle of mashed cassava',
      minAgeMonths: 6,
      caution:
          'Low in protein. Never give cassava alone — always add groundnut '
          'paste, beans or fish.',
    ),

    // ------------------------------------------------- Pulses, nuts, seeds
    LocalFood(
      name: 'Groundnut paste',
      group: FoodGroup.pulsesNutsSeeds,
      nutrients: [Nutrient.energy, Nutrient.protein, Nutrient.iron, Nutrient.zinc],
      monthsAvailable: _yearRound,
      cost: CostTier.veryLow,
      householdMeasure: 'One heaped spoon stirred into the porridge',
      minAgeMonths: 6,
      localNames: {'Dagbani': 'Sinkpam', 'Dagaare': 'Sinkaane'},
      preparation:
          'Stir a spoon of paste into every bowl of porridge. This is the '
          'cheapest way to add energy and protein in the lean season.',
      caution:
          'Give as smooth paste only. Whole nuts choke children under three. '
          'Reject mouldy nuts — aflatoxin risk.',
    ),
    LocalFood(
      name: 'Cowpea (beans)',
      group: FoodGroup.pulsesNutsSeeds,
      nutrients: [Nutrient.protein, Nutrient.iron, Nutrient.folate, Nutrient.zinc],
      monthsAvailable: _yearRound,
      cost: CostTier.veryLow,
      householdMeasure: 'Half a milk tin, well cooked and mashed',
      minAgeMonths: 6,
      localNames: {'Dagbani': 'Tuya'},
      preparation:
          'Soak, then cook until very soft and mash through the skin. Serve '
          'with a vitamin-C food such as tomato or baobab to lift iron uptake.',
    ),
    LocalFood(
      name: 'Soybean',
      group: FoodGroup.pulsesNutsSeeds,
      nutrients: [Nutrient.protein, Nutrient.iron, Nutrient.calcium],
      monthsAvailable: _yearRound,
      cost: CostTier.veryLow,
      householdMeasure: 'One spoon of roasted soy flour per bowl',
      minAgeMonths: 6,
      preparation:
          'Roast, dehull and grind. Blend with millet at one part soy to three '
          'parts millet — a complete protein at almost no cost.',
    ),
    LocalFood(
      name: 'Bambara beans',
      group: FoodGroup.pulsesNutsSeeds,
      nutrients: [Nutrient.protein, Nutrient.energy, Nutrient.iron],
      monthsAvailable: [10, 11, 12, 1, 2, 3, 4],
      cost: CostTier.low,
      householdMeasure: 'Half a milk tin, boiled soft',
      minAgeMonths: 8,
      localNames: {'Dagbani': 'Suma'},
    ),
    LocalFood(
      name: 'Dawadawa (locust bean)',
      group: FoodGroup.pulsesNutsSeeds,
      nutrients: [Nutrient.iron, Nutrient.protein, Nutrient.calcium],
      monthsAvailable: _yearRound,
      cost: CostTier.freeOrGathered,
      householdMeasure: 'One ball crumbled into the soup or stew',
      minAgeMonths: 6,
      localNames: {'Dagbani': 'Kpalgu', 'Gurene (Frafra)': 'Doo'},
      preparation:
          'Already in almost every northern kitchen and unusually rich in iron. '
          'Add a ball to the daily soup rather than buying anything new.',
    ),
    LocalFood(
      name: 'Sesame (beniseed)',
      group: FoodGroup.pulsesNutsSeeds,
      nutrients: [Nutrient.calcium, Nutrient.iron, Nutrient.energy],
      monthsAvailable: [10, 11, 12, 1, 2],
      cost: CostTier.low,
      householdMeasure: 'One spoon of ground seed per bowl',
      minAgeMonths: 6,
    ),

    // --------------------------------------------- Vitamin-A rich produce
    LocalFood(
      name: 'Moringa leaves',
      group: FoodGroup.vitaminARichProduce,
      nutrients: [
        Nutrient.vitaminA,
        Nutrient.iron,
        Nutrient.calcium,
        Nutrient.protein,
        Nutrient.vitaminC,
      ],
      monthsAvailable: _yearRound,
      cost: CostTier.freeOrGathered,
      householdMeasure: 'One handful fresh, or one spoon of dried leaf powder',
      minAgeMonths: 6,
      localNames: {
        'Dagbani': 'Zogale',
        'Gurene (Frafra)': 'Zogale',
        'Dagaare': 'Zogale',
      },
      preparation:
          'The single most valuable food in this region: drought-resistant, '
          'grows in the compound, available every month of the year. Dry the '
          'leaves in shade, grind, and stir a spoon into every porridge.',
    ),
    LocalFood(
      name: 'Baobab leaves',
      group: FoodGroup.vitaminARichProduce,
      nutrients: [Nutrient.vitaminA, Nutrient.calcium, Nutrient.iron],
      monthsAvailable: _yearRound,
      cost: CostTier.freeOrGathered,
      householdMeasure: 'One spoon of dried baobab leaf powder',
      minAgeMonths: 6,
      localNames: {'Dagbani': 'Kuka'},
      preparation:
          'Dried leaf powder keeps through the whole dry season — the reason it '
          'matters so much between November and April.',
    ),
    LocalFood(
      name: 'Ayoyo (jute) leaves',
      group: FoodGroup.vitaminARichProduce,
      nutrients: [Nutrient.vitaminA, Nutrient.iron, Nutrient.calcium],
      monthsAvailable: [5, 6, 7, 8, 9, 10],
      cost: CostTier.freeOrGathered,
      householdMeasure: 'One handful, chopped fine into the soup',
      minAgeMonths: 6,
      localNames: {'Dagbani': 'Ayoyo'},
    ),
    LocalFood(
      name: 'Kapok leaves',
      group: FoodGroup.vitaminARichProduce,
      nutrients: [Nutrient.vitaminA, Nutrient.iron],
      monthsAvailable: [5, 6, 7, 8, 9],
      cost: CostTier.freeOrGathered,
      householdMeasure: 'One handful in the soup',
      minAgeMonths: 6,
      localNames: {'Dagbani': 'Vuŋa'},
    ),
    LocalFood(
      name: 'Amaranth leaves (alefu)',
      group: FoodGroup.vitaminARichProduce,
      nutrients: [Nutrient.vitaminA, Nutrient.iron, Nutrient.calcium],
      monthsAvailable: [5, 6, 7, 8, 9, 10, 11],
      cost: CostTier.freeOrGathered,
      householdMeasure: 'One handful, chopped and cooked briefly',
      minAgeMonths: 6,
    ),
    LocalFood(
      name: 'Pumpkin / pumpkin leaves',
      group: FoodGroup.vitaminARichProduce,
      nutrients: [Nutrient.vitaminA, Nutrient.iron],
      monthsAvailable: [8, 9, 10, 11, 12],
      cost: CostTier.freeOrGathered,
      householdMeasure: 'Two spoons of mashed pumpkin, or a handful of leaves',
      minAgeMonths: 6,
    ),
    LocalFood(
      name: 'Red palm oil',
      group: FoodGroup.vitaminARichProduce,
      nutrients: [Nutrient.vitaminA, Nutrient.energy],
      monthsAvailable: _yearRound,
      cost: CostTier.veryLow,
      householdMeasure: 'Half a teaspoon stirred into the food',
      minAgeMonths: 6,
      preparation:
          'Unrefined red palm oil adds both energy and vitamin A. Half a '
          'teaspoon per bowl is enough; it also helps the body absorb the '
          'vitamin A in green leaves.',
    ),
    LocalFood(
      name: 'Mango',
      group: FoodGroup.vitaminARichProduce,
      nutrients: [Nutrient.vitaminA, Nutrient.vitaminC, Nutrient.energy],
      monthsAvailable: [3, 4, 5, 6],
      cost: CostTier.freeOrGathered,
      householdMeasure: 'Half a ripe mango, mashed',
      minAgeMonths: 6,
      localNames: {'Dagbani': 'Mangoro'},
      preparation:
          'Ripe mango arrives just as the lean season begins — a free source of '
          'vitamin A in the hardest months. Use it while it lasts.',
    ),
    LocalFood(
      name: 'Pawpaw (papaya)',
      group: FoodGroup.vitaminARichProduce,
      nutrients: [Nutrient.vitaminA, Nutrient.vitaminC],
      monthsAvailable: _yearRound,
      cost: CostTier.veryLow,
      householdMeasure: 'Two spoons of mashed ripe pawpaw',
      minAgeMonths: 6,
    ),

    // ------------------------------------------------------- Flesh foods
    LocalFood(
      name: 'Dried / smoked fish',
      group: FoodGroup.fleshFoods,
      nutrients: [
        Nutrient.protein,
        Nutrient.iron,
        Nutrient.calcium,
        Nutrient.zinc,
      ],
      monthsAvailable: _yearRound,
      cost: CostTier.veryLow,
      householdMeasure: 'One small fish, pounded to powder',
      minAgeMonths: 6,
      localNames: {'Dagbani': 'Zahim'},
      preparation:
          'Pound the whole fish, bones included, into a fine powder and stir a '
          'spoon into the porridge. The bones are where the calcium is. This is '
          'the cheapest animal-source food in the north.',
      caution: 'Remove any large bones for children under two.',
    ),
    LocalFood(
      name: 'Fresh tilapia',
      group: FoodGroup.fleshFoods,
      nutrients: [Nutrient.protein, Nutrient.zinc, Nutrient.iron],
      monthsAvailable: _yearRound,
      cost: CostTier.low,
      householdMeasure: 'A piece the size of the child\'s palm',
      minAgeMonths: 6,
      preparation: 'Debone carefully, then flake into the food.',
    ),
    LocalFood(
      name: 'Guinea fowl',
      group: FoodGroup.fleshFoods,
      nutrients: [Nutrient.protein, Nutrient.iron, Nutrient.zinc],
      monthsAvailable: _yearRound,
      cost: CostTier.moderate,
      householdMeasure: 'A piece the size of the child\'s palm, shredded',
      minAgeMonths: 8,
      localNames: {'Dagbani': 'Kpaŋa'},
    ),
    LocalFood(
      name: 'Liver (goat, guinea fowl or beef)',
      group: FoodGroup.fleshFoods,
      nutrients: [
        Nutrient.iron,
        Nutrient.vitaminA,
        Nutrient.protein,
        Nutrient.zinc,
      ],
      monthsAvailable: _yearRound,
      cost: CostTier.low,
      householdMeasure: 'One small piece, boiled and mashed fine',
      minAgeMonths: 6,
      preparation:
          'The strongest iron and vitamin A food available locally, and cheaper '
          'than muscle meat. Twice a week transforms a pale child.',
    ),
    LocalFood(
      name: 'Goat meat',
      group: FoodGroup.fleshFoods,
      nutrients: [Nutrient.protein, Nutrient.iron, Nutrient.zinc],
      monthsAvailable: _yearRound,
      cost: CostTier.high,
      householdMeasure: 'A piece the size of the child\'s palm, shredded',
      minAgeMonths: 8,
    ),

    // -------------------------------------------------------------- Eggs
    LocalFood(
      name: 'Guinea fowl eggs',
      group: FoodGroup.eggs,
      nutrients: [
        Nutrient.protein,
        Nutrient.vitaminA,
        Nutrient.iron,
        Nutrient.zinc,
      ],
      monthsAvailable: [4, 5, 6, 7, 8, 9, 10],
      cost: CostTier.veryLow,
      householdMeasure: 'One egg, boiled and mashed',
      minAgeMonths: 6,
      preparation:
          'Guinea fowl lay through the rains — often the household\'s own birds, '
          'so the cost is nothing. One egg a day is transformative.',
    ),
    LocalFood(
      name: 'Chicken eggs',
      group: FoodGroup.eggs,
      nutrients: [Nutrient.protein, Nutrient.vitaminA, Nutrient.zinc],
      monthsAvailable: _yearRound,
      cost: CostTier.low,
      householdMeasure: 'One egg, boiled and mashed',
      minAgeMonths: 6,
      caution: 'Always fully cooked — never raw or soft.',
    ),

    // ------------------------------------------------------------- Dairy
    LocalFood(
      name: 'Fresh cow milk',
      group: FoodGroup.dairy,
      nutrients: [Nutrient.calcium, Nutrient.protein, Nutrient.energy],
      monthsAvailable: [6, 7, 8, 9, 10, 11],
      cost: CostTier.low,
      householdMeasure: 'Half a cup, boiled',
      minAgeMonths: 9,
      localNames: {'Dagbani': 'Bihim'},
      caution:
          'Must be boiled. Never replaces breastfeeding under two years, and '
          'never given as the main drink under one year.',
    ),
    LocalFood(
      name: 'Wagashi (local cheese)',
      group: FoodGroup.dairy,
      nutrients: [Nutrient.protein, Nutrient.calcium, Nutrient.energy],
      monthsAvailable: [6, 7, 8, 9, 10, 11],
      cost: CostTier.low,
      householdMeasure: 'A piece the size of two fingers, mashed',
      minAgeMonths: 9,
      preparation: 'Fry or boil before giving to a child.',
    ),

    // ---------------------------------------------------- Other produce
    LocalFood(
      name: 'Baobab fruit pulp',
      group: FoodGroup.otherProduce,
      nutrients: [Nutrient.vitaminC, Nutrient.calcium, Nutrient.iron],
      monthsAvailable: [12, 1, 2, 3, 4, 5],
      cost: CostTier.freeOrGathered,
      householdMeasure: 'One spoon of pulp powder stirred into water or porridge',
      minAgeMonths: 6,
      localNames: {'Dagbani': 'Tua'},
      preparation:
          'Very high in vitamin C, which multiplies the iron the child absorbs '
          'from beans and leaves. Pair it with them in the same meal.',
    ),
    LocalFood(
      name: 'Tomato',
      group: FoodGroup.otherProduce,
      nutrients: [Nutrient.vitaminC, Nutrient.vitaminA],
      monthsAvailable: _yearRound,
      cost: CostTier.veryLow,
      householdMeasure: 'One tomato in the stew',
      minAgeMonths: 6,
    ),
    LocalFood(
      name: 'Okra',
      group: FoodGroup.otherProduce,
      nutrients: [Nutrient.folate, Nutrient.vitaminC, Nutrient.calcium],
      monthsAvailable: [6, 7, 8, 9, 10],
      cost: CostTier.freeOrGathered,
      householdMeasure: 'Three pods, chopped into the soup',
      minAgeMonths: 6,
      localNames: {'Dagbani': 'Manna'},
    ),
    LocalFood(
      name: 'Garden eggs',
      group: FoodGroup.otherProduce,
      nutrients: [Nutrient.vitaminC, Nutrient.folate],
      monthsAvailable: [7, 8, 9, 10, 11, 12],
      cost: CostTier.veryLow,
      householdMeasure: 'Two, boiled and mashed into the stew',
      minAgeMonths: 6,
    ),
    LocalFood(
      name: 'Orange',
      group: FoodGroup.otherProduce,
      nutrients: [Nutrient.vitaminC, Nutrient.folate],
      monthsAvailable: [11, 12, 1, 2, 3],
      cost: CostTier.veryLow,
      householdMeasure: 'Juice of one orange, no added sugar',
      minAgeMonths: 8,
    ),
  ];

  // -------------------------------------------------------------- Queries

  static List<LocalFood> availableIn(int month) =>
      all.where((f) => f.availableIn(month)).toList(growable: false);

  static List<LocalFood> inGroup(FoodGroup g) =>
      all.where((f) => f.group == g).toList(growable: false);

  /// Foods that are in season, age-appropriate, within a household's budget,
  /// and supply a specific nutrient — ranked cheapest first.
  ///
  /// This is the query that answers the challenge question directly.
  static List<LocalFood> recommend({
    required int month,
    required int ageMonths,
    required Nutrient nutrient,
    CostTier maxCost = CostTier.moderate,
    int limit = 6,
  }) {
    final matches = all
        .where(
          (f) =>
              f.availableIn(month) &&
              f.suitableFor(ageMonths) &&
              f.provides(nutrient) &&
              f.cost.rank <= maxCost.rank,
        )
        .toList()
      // Cheapest first; within a cost tier, prefer foods where the nutrient
      // ranks highest (i.e. the food is a stronger source of it).
      ..sort((a, b) {
        final byCost = a.cost.rank.compareTo(b.cost.rank);
        if (byCost != 0) return byCost;
        return a.nutrients.indexOf(nutrient).compareTo(
              b.nutrients.indexOf(nutrient),
            );
      });

    return matches.take(limit).toList(growable: false);
  }

  /// A seasonal, affordable food from each of the groups a child is missing —
  /// the concrete route from "this child fails MDD" to "cook this tomorrow".
  static Map<FoodGroup, List<LocalFood>> fillDiversityGaps({
    required int month,
    required int ageMonths,
    required Set<FoodGroup> groupsEaten,
    CostTier maxCost = CostTier.low,
  }) {
    final gaps = <FoodGroup, List<LocalFood>>{};
    for (final group in FoodGroup.values) {
      if (group == FoodGroup.breastMilk || groupsEaten.contains(group)) continue;
      final options = all
          .where(
            (f) =>
                f.group == group &&
                f.availableIn(month) &&
                f.suitableFor(ageMonths) &&
                f.cost.rank <= maxCost.rank,
          )
          .toList()
        ..sort((a, b) => a.cost.rank.compareTo(b.cost.rank));
      if (options.isNotEmpty) gaps[group] = options.take(3).toList();
    }
    return gaps;
  }

  static LocalFood? byName(String name) =>
      all.where((f) => f.name == name).firstOrNull;
}
