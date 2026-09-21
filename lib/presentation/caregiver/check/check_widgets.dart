import 'package:flutter/material.dart';
import 'package:carebridge_ai/core/theme/app_theme.dart';
import 'package:carebridge_ai/core/theme/glass.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/shared/app_image.dart';
import 'package:carebridge_ai/presentation/shared/ui.dart';

// ----------------------------------------------------- Tri-state question tile

/// [40-C] One family member, wearing the category illustration used across
/// the whole app — the same three pictures a health worker sees.
class CaregiverPersonCard extends StatelessWidget {
  const CaregiverPersonCard({
    super.key,
    required this.person,
    required this.onTap,
    this.dark = false,
  });

  final Person person;
  final VoidCallback onTap;

  /// Navy card for the dark caregiver dashboard instead of white glass.
  final bool dark;

  String get _image => switch (person.effectiveClientType) {
    ClientType.newborn => AppImages.cardNewborn,
    ClientType.childUnderFive => AppImages.cardChild,
    _ => AppImages.cardMother,
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: PressScale(
        onTap: onTap,
        radius: BorderRadius.circular(GlassTier.card.radius),
        child: Semantics(
          button: true,
          label: 'Check ${person.fullName}',
          child: dark
              ? Container(
                  padding: const EdgeInsets.all(Gap.md),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.checkNavyMid, AppColors.checkNavy],
                    ),
                    borderRadius: BorderRadius.circular(Gap.radius),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                      width: 1,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x59000000),
                        blurRadius: 24,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(Gap.radiusXs),
                        child: SizedBox(
                          width: 64,
                          height: 64,
                          child: AppImage(src: _image),
                        ),
                      ),
                      const SizedBox(width: Gap.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              person.fullName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${person.ageLabel} · '
                              '${person.effectiveClientType.label}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.white60,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.white60,
                      ),
                    ],
                  ),
                )
              : GlassSurface(
                  blur: false,
                  padding: const EdgeInsets.all(Gap.md),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(Gap.radiusXs),
                        child: SizedBox(
                          width: 64,
                          height: 64,
                          child: AppImage(src: _image),
                        ),
                      ),
                      const SizedBox(width: Gap.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              person.fullName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${person.ageLabel} · '
                              '${person.effectiveClientType.label}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.inkMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.inkFaint,
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
