import 'package:flutter/material.dart';
import 'package:carebridge_ai/core/theme/app_theme.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/shared/app_image.dart';
import 'package:carebridge_ai/presentation/shared/ui.dart';
import 'package:carebridge_ai/presentation/caregiver/check/check_types.dart';

/// The check ends with what the family CAN do at the next meal, not only
/// with what is wrong. Real Northern Ghana foods, photographed — advice
/// that shows the actual pot is advice that gets cooked.
class CaregiverFamilyFeedingCard extends StatelessWidget {
  const CaregiverFamilyFeedingCard({
    super.key,
    required this.person,
    required this.verdict,
  });

  final Person person;
  final CaregiverTriageVerdict verdict;

  /// Every food below is drawn from the same LocalFoods dataset the
  /// nutrition engine recommends from: year-round, in the cheapest cost
  /// tiers, and age-appropriate from six months. One card per WHO food
  /// group a child needs for dietary diversity.
  static const _childFoods = [
    (
      image: AppImages.foodMilletPorridge,
      name: 'Millet porridge',
      local: 'Za',
      reason:
          'Gives energy for the whole day. Cook it thick, so it sits on '
          'the spoon — thin porridge fills the stomach without feeding.',
    ),
    (
      image: AppImages.foodGroundnutPaste,
      name: 'Groundnut paste',
      local: 'Sinkpam',
      reason:
          'Stir one spoon into every bowl of porridge. The cheapest way '
          'to add energy and protein. Smooth paste only — whole nuts '
          'choke young children.',
    ),
    (
      image: AppImages.foodCowpeaStew,
      name: 'Cowpea (beans)',
      local: 'Tuya',
      reason:
          'Beans build the body with protein and iron. Cook until very '
          'soft and mash well.',
    ),
    (
      image: AppImages.foodDriedFish,
      name: 'Dried fish powder',
      local: 'Zahim',
      reason:
          'The cheapest animal food in the north. Pound one small fish, '
          'bones included, and stir a spoon into the porridge.',
    ),
    (
      image: AppImages.foodBoiledEgg,
      name: 'Egg',
      local: '',
      reason:
          'One boiled egg a day builds the body and the eyes. Always '
          'fully cooked, never soft.',
    ),
    (
      image: AppImages.foodSweetPotato,
      name: 'Orange-fleshed sweet potato',
      local: '',
      reason:
          'Choose the orange kind, not white. One small tuber covers a '
          'young child\u2019s vitamin A for the day.',
    ),
    (
      image: AppImages.foodMoringaBaobab,
      name: 'Moringa and baobab leaves',
      local: 'Zogale',
      reason:
          'Green leaves protect against illness. Stir a spoon of dried '
          'powder into the porridge every day.',
    ),
    (
      image: AppImages.foodPawpaw,
      name: 'Ripe pawpaw',
      local: '',
      reason:
          'Soft, sweet and available all year. Mash two spoons as a '
          'snack between meals.',
    ),
  ];

  static const _motherFoods = [
    (
      image: AppImages.foodMilletPorridge,
      name: 'Millet porridge',
      local: 'Za',
      reason: 'Warm porridge keeps your strength up and helps your milk flow.',
    ),
    (
      image: AppImages.foodCowpeaStew,
      name: 'Cowpea (beans)',
      local: 'Tuya',
      reason: 'Beans give the protein and iron your body is rebuilding with.',
    ),
    (
      image: AppImages.foodMoringaBaobab,
      name: 'Moringa and baobab leaves',
      local: 'Zogale',
      reason:
          'Green leaves give iron and vitamins for you and your milk. '
          'Free from the compound tree, every month of the year.',
    ),
    (
      image: AppImages.foodGroundnutPaste,
      name: 'Groundnut paste',
      local: 'Sinkpam',
      reason:
          'One spoon in your porridge adds the energy a nursing mother '
          'burns through.',
    ),
    (
      image: AppImages.foodDriedFish,
      name: 'Dried fish powder',
      local: 'Zahim',
      reason:
          'Cheap iron and calcium, especially while you are recovering '
          'after delivery.',
    ),
    (
      image: AppImages.foodBoiledEgg,
      name: 'Egg',
      local: '',
      reason: 'One boiled egg a day helps you rebuild strength quickly.',
    ),
    (
      image: AppImages.foodDawadawa,
      name: 'Dawadawa (locust bean)',
      local: 'Kpalgu',
      reason:
          'Already in almost every northern kitchen and unusually rich '
          'in iron. Add a ball to your daily soup.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final type = person.effectiveClientType;
    final isNewborn = type == ClientType.newborn;
    final isChild = type == ClientType.childUnderFive;
    final foods = isChild ? _childFoods : _motherFoods;

    return SectionCard(
      title: isNewborn ? 'Feeding your newborn today' : 'Feeding today',
      subtitle: isNewborn
          ? 'Breastmilk is the one food and the first medicine.'
          : 'Foods from your own market that help recovery.',
      icon: isNewborn ? Icons.child_care_rounded : Icons.restaurant_rounded,
      accent: AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (verdict == CaregiverTriageVerdict.urgent)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.md),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Gap.md),
                decoration: BoxDecoration(
                  color: AppColors.triageAmber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Gap.radiusSm),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.local_drink_rounded,
                      color: AppColors.triageAmber,
                      size: 20,
                    ),
                    SizedBox(width: Gap.sm),
                    Expanded(
                      child: Text(
                        'Keep offering breastmilk and fluids, even on the '
                        'way to the clinic.',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (isNewborn)
            for (final (icon, line) in const [
              (Icons.favorite_rounded, 'Breastfeed often, day and night.'),
              (
                Icons.water_drop_outlined,
                'Breastmilk alone is enough. No water is needed.',
              ),
              (
                Icons.self_improvement_rounded,
                'Skin-to-skin cuddles keep the baby warm and feeding well.',
              ),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 18, color: AppColors.primary),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      child: Text(
                        line,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              )
          else
            for (final f in foods) _FeedingTile(food: f),
        ],
      ),
    );
  }
}

/// One photographed food: picture, name with its local name, and the
/// reason it helps, in three lines a caregiver can read at a glance.
class _FeedingTile extends StatelessWidget {
  const _FeedingTile({required this.food});

  final ({String image, String name, String local, String reason}) food;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: Gap.sm),
    padding: const EdgeInsets.all(Gap.md),
    decoration: BoxDecoration(
      color: AppColors.canvas,
      borderRadius: BorderRadius.circular(Gap.radiusSm),
      border: Border.all(color: AppColors.line),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(Gap.radiusXs),
          child: SizedBox(
            width: 64,
            height: 64,
            child: AppImage(src: food.image),
          ),
        ),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      food.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (food.local.isNotEmpty) ...[
                    const SizedBox(width: Gap.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Gap.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        food.local,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: Gap.xs),
              Text(
                food.reason,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.inkMuted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
