/// Local imagery for CareBridge AI.
///
/// Every illustration ships inside the app bundle: the first design constraint
/// is *works offline*, and a photograph fetched from a CDN is not an image on
/// a phone with no network. All subjects are dark-skinned Northern Ghanaian
/// mothers, newborns and children — the people who actually use this app.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Central registry of bundled illustrations.
///
/// Keeping every asset path here means a swapped image is a one-line change
/// and no screen hard-codes an asset string.
abstract final class AppImages {
  static const String _base = 'assets/images/';

  // ── Onboarding ─────────────────────────────────────────────────────
  /// CHW with a pregnant/postpartum woman — onboarding page 1.
  static const String onboardingMaternal = '${_base}onboarding_maternal.png';

  /// Newborn + toddler together, same household — onboarding page 2.
  static const String onboardingNewborn = '${_base}onboarding_newborn.png';

  /// Offline & AI-assisted foreshadowing — onboarding page 3.
  static const String onboardingOffline = '${_base}onboarding_offline.png';

  // ── Heroes ─────────────────────────────────────────────────────────
  /// Mother cradling baby — splash / brand mark.
  static const String splashHero = '${_base}splash_hero.png';

  /// Health worker greeting a household — FHW dashboard header.
  static const String fhwHero = '${_base}fhw_hero.png';

  /// Mother playing with baby at home — caregiver dashboard header.
  static const String caregiverHero = '${_base}caregiver_hero.png';

  // ── Category cards ─────────────────────────────────────────────────
  /// Pregnant woman — Mother/Woman category.
  static const String cardMother = '${_base}card_mother.png';

  /// Sleeping newborn — Newborn category.
  static const String cardNewborn = '${_base}card_newborn.png';

  /// Happy toddler — Child Under 5 category.
  static const String cardChild = '${_base}card_child.png';

  // ── Nutrition (real Northern Ghana foods) ──────────────────────────
  static const String foodMilletPorridge = '${_base}food_millet_porridge.png';
  static const String foodCowpeaStew = '${_base}food_cowpea_stew.png';
  static const String foodMoringaBaobab = '${_base}food_moringa_baobab.png';
}

/// A bundled illustration that fades in and degrades gracefully.
class AppImage extends StatelessWidget {
  const AppImage({
    super.key,
    required this.src,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholderIcon = Icons.image_outlined,
  });

  final String src;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) {
    Widget content = Stack(
      fit: StackFit.expand,
      children: [
        // Holds the space while decoding, and remains if the asset is missing.
        _ImagePlaceholder(icon: placeholderIcon),
        Image.asset(
          src,
          fit: fit,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: AppMotion.duration,
              curve: AppMotion.curve,
              child: child,
            );
          },
          errorBuilder: (context, error, stackTrace) =>
              const SizedBox.shrink(),
        ),
      ],
    );

    if (borderRadius != null) {
      content = ClipRRect(borderRadius: borderRadius!, child: content);
    }
    return content;
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.surfaceTint,
    alignment: Alignment.center,
    child: Icon(icon, size: 30, color: AppColors.inkFaint),
  );
}
