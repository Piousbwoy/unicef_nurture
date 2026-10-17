import 'package:flutter/material.dart';
import 'package:carebridge_ai/core/theme/app_theme.dart';
import 'package:carebridge_ai/core/theme/lumina.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/shared/app_image.dart';

// ----------------------------------------------------- Tri-state question tile

/// [40-C] One family member, wearing the category illustration used across
/// the whole app — the same three pictures a health worker sees. The tile
/// wears the same hero dive as every other caregiver card.
class CaregiverPersonCard extends StatelessWidget {
  const CaregiverPersonCard({
    super.key,
    required this.person,
    required this.onTap,
  });

  final Person person;
  final VoidCallback onTap;

  String get _image => switch (person.effectiveClientType) {
    ClientType.newborn => AppImages.cardNewborn,
    ClientType.childUnderFive => AppImages.cardChild,
    ClientType.womanOfReproductiveAge => AppImages.cardWoman,
    _ => AppImages.cardMother,
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Semantics(
        button: true,
        label: 'Check ${person.fullName}',
        child: LumenCard(
          onTap: onTap,
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
                        color: Lumina.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${person.ageLabel} · '
                      '${person.effectiveClientType.label}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Lumina.inkMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Lumina.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}
