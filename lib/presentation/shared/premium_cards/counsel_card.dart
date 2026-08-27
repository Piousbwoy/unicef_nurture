/// Counsel Card - Visual Memory Grid
/// Icon-based counseling for low-literacy contexts
/// Part of the CareBridge Premium Design System

import 'package:flutter/material.dart';
import '../../../../core/theme/premium_design_tokens.dart';

class CounselCard extends StatelessWidget {
  const CounselCard({
    super.key,
    required this.counselPoints,
    this.onPointTapped,
    this.languageCode = 'en',
    this.animationDuration = PremiumDesignTokens.standardTransition,
  });

  final List<CounselPoint> counselPoints;
  final void Function(CounselPoint)? onPointTapped;
  final String languageCode;
  final Duration animationDuration;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: PremiumDesignTokens.elevatedCard(),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: PremiumDesignTokens.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.lightbulb,
                    color: PremiumDesignTokens.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Key Messages',
                        style: PremiumDesignTokens.headlineSmall.copyWith(
                          color: PremiumDesignTokens.neutral800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap any icon to learn more',
                        style: PremiumDesignTokens.bodyMedium.copyWith(
                          color: PremiumDesignTokens.neutral500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Icon grid
            _CounselGrid(
              points: counselPoints,
              onPointTapped: onPointTapped,
            ),

            // Share button
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  // Generate shareable summary
                },
                icon: Icon(
                  Icons.share,
                  color: PremiumDesignTokens.primary,
                  size: 18,
                ),
                label: Text(
                  'Send to Caregiver',
                  style: PremiumDesignTokens.labelLarge.copyWith(
                    color: PremiumDesignTokens.primary,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: BorderSide(
                    color: PremiumDesignTokens.primary.withOpacity(0.3),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 2x3 grid of counsel points
class _CounselGrid extends StatelessWidget {
  const _CounselGrid({
    required this.points,
    this.onPointTapped,
  });

  final List<CounselPoint> points;
  final void Function(CounselPoint)? onPointTapped;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.85,
      children: points.map((point) => _CounselTile(
        point: point,
        onTap: onPointTapped != null ? () => onPointTapped!(point) : null,
      )).toList(),
    );
  }
}

/// Individual counsel tile
class _CounselTile extends StatelessWidget {
  const _CounselTile({
    required this.point,
    this.onTap,
  });

  final CounselPoint point;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: point.backgroundColor ?? PremiumDesignTokens.neutral50,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: point.iconColor?.withOpacity(0.15) ??
                      PremiumDesignTokens.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  point.icon,
                  color: point.iconColor ?? PremiumDesignTokens.primary,
                  size: 24,
                ),
              ),

              const SizedBox(height: 10),

              // Title
              Text(
                point.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: PremiumDesignTokens.labelLarge.copyWith(
                  color: PremiumDesignTokens.neutral800,
                  height: 1.3,
                ),
              ),

              // Subtitle if exists
              if (point.subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  point.subtitle!,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PremiumDesignTokens.labelSmall.copyWith(
                    color: PremiumDesignTokens.neutral500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Counsel point model
class CounselPoint {
  const CounselPoint({
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.backgroundColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  final Color? backgroundColor;
}
