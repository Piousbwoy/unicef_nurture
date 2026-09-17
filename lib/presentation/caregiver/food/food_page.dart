import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/motion.dart';
import '../../../data/reference/local_foods.dart';
import '../../../domain/entities/caregiver.dart';
import '../../../domain/services/caregiver_food_planner.dart';
import '../../shared/app_image.dart';
import '../caregiver_providers.dart';
import '../care_plan/saved_advice.dart';
import '../widgets/companion.dart';

class CaregiverFoodPage extends ConsumerStatefulWidget {
  const CaregiverFoodPage({
    super.key,
    required this.householdId,
    this.personId,
  });
  final String householdId;
  final String? personId;
  @override
  ConsumerState<CaregiverFoodPage> createState() => _CaregiverFoodPageState();
}

class _CaregiverFoodPageState extends ConsumerState<CaregiverFoodPage> {
  String? _person;
  bool _choosing = false;
  @override
  void initState() {
    super.initState();
    _person = widget.personId;
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(caregiverScopeProvider);
    if (scope == null || scope.householdId != widget.householdId) {
      return const SizedBox.shrink();
    }
    final now = ref.watch(caregiverCalendarProvider);
    final writer = ref.watch(caregiverWriterProvider(scope));
    return CompanionPage(
      title: 'Food for today',
      child: ref
          .watch(caregiverSettingsProvider(scope))
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => CompanionLoadError(
              onRetry: () => ref.invalidate(caregiverSettingsProvider(scope)),
            ),
            data: (settings) => ref
                .watch(caregiverClinicalProvider(scope))
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => CompanionLoadError(
                    message:
                        'Could not check for saved clinic advice. Retry before choosing meal ideas.',
                    onRetry: () =>
                        ref.invalidate(caregiverClinicalProvider(scope)),
                  ),
                  data: (data) {
                    final person = data.members
                        .where(
                          (p) => p.id == (_person ?? settings.selectedPersonId),
                        )
                        .firstOrNull;
                    if (_choosing || person == null) {
                      return ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          const CompanionCard(
                            title: 'Who are we preparing food for?',
                            child: Text(
                              'Choose a family member so that age and feeding restrictions are respected.',
                            ),
                          ),
                          if (data.members.isEmpty)
                            const Text(
                              'Add a member from Family to get started.',
                            ),
                          for (final p in data.members)
                            CaregiverSaveAction(
                              label: '${p.fullName} • ${caregiverAge(p)}',
                              onSave: () async {
                                await writer.settings(
                                  (s) => s.copyWith(selectedPersonId: p.id),
                                );
                                if (mounted) {
                                  setState(() {
                                    _person = p.id;
                                    _choosing = false;
                                  });
                                }
                              },
                            ),
                        ],
                      );
                    }
                    final planner = CaregiverFoodPlanner(clock: () => now);
                    final ideas = planner.build(person, settings);
                    final records =
                        data.assessments
                            .where((a) => a.personId == person.id)
                            .toList()
                          ..sort(
                            (a, b) => b.performedAt.compareTo(a.performedAt),
                          );
                    // The saved plan is the evidence. Never invent an assessment or rerun
                    // a clinical nutrition engine from a household food preference.
                    final latest = records.firstOrNull;
                    return ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        CompanionCard(
                          title: person.fullName,
                          eyebrow: caregiverAge(person),
                          child: OutlinedButton(
                            onPressed: () => setState(() => _choosing = true),
                            child: const Text('Choose someone else'),
                          ),
                        ),
                        CompanionCard(
                          title: 'From your clinic',
                          child: latest == null
                              ? const Text(
                                  'No clinic plan is saved for this person. The food ideas below are general education, not a nutrition assessment.',
                                )
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      'Saved ${caregiverWhen(latest.performedAt)}',
                                    ),
                                    const Text(
                                      'Follow the clinician’s feeding advice first. Ordinary foods must not replace prescribed therapeutic feeding. Ask the clinic if advice is unclear or out of date.',
                                    ),
                                    ExpansionTile(
                                      title: const Text(
                                        'Read saved clinic advice',
                                      ),
                                      initiallyExpanded: true,
                                      children: [
                                        CaregiverSavedAdvice(
                                          key: ValueKey(latest.id),
                                          person: person,
                                          assessment: latest,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                        ),
                        CompanionCard(
                          title: ideas.gate == CaregiverFoodGate.ready
                              ? 'Your household, your ingredients'
                              : 'Feeding support',
                          eyebrow: 'EVERYDAY GUIDANCE • NOT A PRESCRIBED DIET',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(ideas.message),
                              const SizedBox(height: 12),
                              const Text(CaregiverFoodIdeas.disclaimer),
                              if (ideas.gate ==
                                  CaregiverFoodGate.feedingSupport)
                                const ExpansionTile(
                                  title: Text(
                                    'Future-food education — not for feeding now',
                                  ),
                                  children: [
                                    Text(
                                      'Around six months, ask your health worker about introducing suitable complementary foods. This is preparation for later, not a meal plan for this baby now.',
                                    ),
                                  ],
                                ),
                              if (ideas.gate == CaregiverFoodGate.ready) ...[
                                Text(
                                  'Foods we have: ${settings.foodsHave.isEmpty ? 'None selected' : settings.foodsHave.join(', ')}',
                                ),
                                Text(
                                  'Foods we avoid: ${settings.foodsAvoid.isEmpty ? 'None selected' : settings.foodsAvoid.join(', ')}',
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.of(context).push(
                                    GlassPageRoute<void>(
                                      builder: (_) =>
                                          _FoodChoices(settings: settings),
                                    ),
                                  ),
                                  child: const Text(
                                    'Choose foods we have or avoid',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (ideas.gate == CaregiverFoodGate.ready) ...[
                          for (final meal in ideas.meals)
                            CompanionCard(
                              title: meal.title,
                              eyebrow: 'A SIMPLE FOOD IDEA',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final ingredient in meal.ingredients)
                                    _Ingredient(food: ingredient),
                                  ExpansionTile(
                                    title: const Text('Prepare it safely'),
                                    children: [
                                      for (
                                        var i = 0;
                                        i < meal.preparation.length;
                                        i++
                                      )
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 12,
                                          ),
                                          child: Text(
                                            '${i + 1}. ${meal.preparation[i]}',
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          CompanionCard(
                            title: 'Ingredients and alternatives',
                            child: Column(
                              children: [
                                if (ideas.available.isEmpty)
                                  const Text(
                                    'No suitable selected ingredients. Add foods you have; avoided foods are always excluded.',
                                  ),
                                for (final food in ideas.available)
                                  ExpansionTile(
                                    title: Text(food.name),
                                    subtitle: Text(food.group.label),
                                    children: [
                                      _Ingredient(food: food),
                                      const Text(
                                        'Same-group alternatives retain age and preparation restrictions. These are possibilities, not guaranteed stock.',
                                      ),
                                      if (planner
                                          .alternatives(food, person, settings)
                                          .isEmpty)
                                        const Text(
                                          'No suitable alternative remains with these preferences.',
                                        ),
                                      for (final alternative
                                          in planner
                                              .alternatives(
                                                food,
                                                person,
                                                settings,
                                              )
                                              .take(3))
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            _Ingredient(food: alternative),
                                            _ShoppingAdd(
                                              food: alternative.name,
                                            ),
                                          ],
                                        ),
                                      _ShoppingAdd(food: food.name),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                          const _ShoppingList(),
                        ],
                      ],
                    );
                  },
                ),
          ),
    );
  }
}

class _Ingredient extends StatelessWidget {
  const _Ingredient({required this.food});
  final LocalFood food;
  @override
  Widget build(BuildContext context) {
    final image = switch (food.name) {
      'Millet' => AppImages.foodMilletPorridge,
      'Cowpea (beans)' => AppImages.foodCowpeaStew,
      'Groundnut paste' => AppImages.foodGroundnutPaste,
      'Dried / smoked fish' => AppImages.foodDriedFish,
      'Egg' => AppImages.foodBoiledEgg,
      'Orange-fleshed sweet potato' => AppImages.foodSweetPotato,
      'Pawpaw (papaya)' => AppImages.foodPawpaw,
      'Dawadawa (locust bean)' => AppImages.foodDawadawa,
      _ => null,
    };
    final caution = CaregiverFoodPlanner.cautionFor(food);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (image != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(
                image,
                height: 110,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.restaurant_outlined),
              ),
            ),
          Text(food.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('Household measure: ${food.householdMeasure}'),
          const Text(
            'A measure describes an ingredient, not a required serving.',
          ),
          Text(CaregiverFoodPlanner.preparationFor(food)),
          if (caution != null) Text('Caution: $caution'),
          Text(
            'Typical months: ${food.monthsAvailable.map((m) => DateFormat.MMM().format(DateTime(2026, m))).join(', ')}',
          ),
          Text(
            'General cost guide: ${food.cost.rank <= 2 ? 'Lower cost' : 'Higher cost'}; local prices vary.',
          ),
        ],
      ),
    );
  }
}

class _FoodChoices extends ConsumerStatefulWidget {
  const _FoodChoices({required this.settings});
  final CaregiverSettings settings;
  @override
  ConsumerState<_FoodChoices> createState() => _FoodChoicesState();
}

class _FoodChoicesState extends ConsumerState<_FoodChoices> {
  late final Set<String> _have = {...widget.settings.foodsHave};
  late final Set<String> _avoid = {...widget.settings.foodsAvoid};
  late bool _lowCost = widget.settings.lowCost;
  bool _saving = false;
  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(caregiverScopeProvider);
    if (scope == null || scope != widget.settings.scope) {
      return const SizedBox.shrink();
    }
    final writer = ref.watch(caregiverWriterProvider(scope));
    return CompanionPage(
      title: 'Foods at home',
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Choose what you actually have. Mark allergies or other exclusions under Avoid. Avoid always wins over Have.',
          ),
          SwitchListTile(
            title: const Text('Prefer lower-cost ideas'),
            value: _lowCost,
            onChanged: _saving ? null : (v) => setState(() => _lowCost = v),
          ),
          for (final food in LocalFoods.all)
            CompanionCard(
              title: food.name,
              child: Column(
                children: [
                  CheckboxListTile(
                    title: const Text('We have this'),
                    value: _have.contains(food.name),
                    onChanged: _saving
                        ? null
                        : (v) => setState(
                            () => v!
                                ? _have.add(food.name)
                                : _have.remove(food.name),
                          ),
                  ),
                  CheckboxListTile(
                    title: const Text('Avoid this food'),
                    value: _avoid.contains(food.name),
                    onChanged: _saving
                        ? null
                        : (v) => setState(
                            () => v!
                                ? _avoid.add(food.name)
                                : _avoid.remove(food.name),
                          ),
                  ),
                ],
              ),
            ),
          CaregiverSaveAction(
            primary: true,
            label: 'Save food choices',
            onSave: () async {
              setState(() => _saving = true);
              try {
                await writer.settings(
                  (s) => s.copyWith(
                    foodsHave: _have,
                    foodsAvoid: _avoid,
                    lowCost: _lowCost,
                  ),
                );
                if (context.mounted) Navigator.pop(context);
              } finally {
                if (mounted) setState(() => _saving = false);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _ShoppingAdd extends ConsumerWidget {
  const _ShoppingAdd({required this.food});
  final String food;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(caregiverScopeProvider);
    if (scope == null) return const SizedBox.shrink();
    final writer = ref.watch(caregiverWriterProvider(scope));
    final activity = ref.watch(caregiverActivityProvider(scope));
    if (activity.isLoading) return const Text('Loading shopping list…');
    if (activity.hasError) {
      return CompanionLoadError(
        onRetry: () => ref.invalidate(caregiverActivityProvider(scope)),
      );
    }
    if (activity.requireValue.any(
      (a) => a.kind == CaregiverActivityKind.shopping && a.itemKey == food,
    )) {
      return const Text('On your saved shopping list');
    }
    return CaregiverSaveAction(
      label: 'Add $food to shopping',
      icon: Icons.shopping_basket_outlined,
      onSave: () => writer.activity(
        writer.entry(
          kind: CaregiverActivityKind.shopping,
          sourceId: 'household-shopping',
          itemKey: food,
          occurrenceKey: 'current',
          done: false,
        ),
      ),
    );
  }
}

class _ShoppingList extends ConsumerWidget {
  const _ShoppingList();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(caregiverScopeProvider);
    if (scope == null) return const SizedBox.shrink();
    return CompanionCard(
      title: 'Saved shopping checklist',
      child: ref
          .watch(caregiverActivityProvider(scope))
          .when(
            loading: () => const Text('Loading your list…'),
            error: (_, _) => CompanionLoadError(
              onRetry: () => ref.invalidate(caregiverActivityProvider(scope)),
            ),
            data: (entries) {
              final items = entries
                  .where((a) => a.kind == CaregiverActivityKind.shopping)
                  .toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (items.isEmpty)
                    const Text(
                      'Add an ingredient above. This list stays on this phone.',
                    ),
                  for (final item in items)
                    CaregiverTaskToggle(
                      personId: null,
                      kind: CaregiverActivityKind.shopping,
                      sourceId: item.sourceId,
                      itemKey: item.itemKey,
                      occurrenceKey: item.occurrenceKey,
                      label: item.itemKey,
                    ),
                  const Text(
                    'Ticking groceries does not prove nutritional adequacy.',
                  ),
                ],
              );
            },
          ),
    );
  }
}
