/// Why the desk is still open, counted.
///
/// `BarrierDao.withinDays` has collected the answers to "why didn't you go" for
/// some time, and the only thing that happened to them afterwards was that they
/// were stored. This is the conversion step: the same sentences grouped by how
/// many households said them, with the owner of the fix named — because "three
/// families say the facility closed before noon" is a sub-district escalation,
/// while "one family needs transport money" is a next-contact action. A paper
/// register can show neither; it has one column, and it says DID NOT ATTEND.
///
/// The card never takes the desk down with it. A missing rollup is a missing
/// rollup, not a reason a CHO cannot chase a referral.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/fhw_luxe.dart';
import '../../domain/engines/barrier_evidence.dart';
import '../shared/ui.dart';
import 'follow_up/follow_up_providers.dart';

class BarrierEvidenceCard extends ConsumerWidget {
  const BarrierEvidenceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Nothing is shown while the count is still being read: this sits under the
    // chase list, and flashing "nobody has been asked" for one frame before the
    // real answer arrives would say the opposite of what it means.
    final patterns = ref.watch(barrierPatternsProvider).valueOrNull;
    if (patterns == null) return const SizedBox.shrink();
    final escalated = BarrierEvidence.escalatable(patterns);
    return Padding(
      padding: const EdgeInsets.only(top: Gap.lg),
      child: SectionCard(
        title: 'Why care did not happen',
        subtitle: _subtitle(patterns, escalated),
        icon: Icons.alt_route_rounded,
        accent: escalated.isEmpty ? null : FhwLuxePalette.clinicalAmber,
        child: escalated.isEmpty
            ? _oneOffs(patterns)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final pattern in escalated) ...[
                    _Line(pattern: pattern),
                    const SizedBox(height: Gap.sm),
                  ],
                  if (patterns.length > escalated.length)
                    Text(
                      'Plus ${patterns.length - escalated.length} '
                      'reported once or twice — worth knowing, not worth '
                      'escalating.',
                      style: AppType.caption.copyWith(
                        color: FhwLuxePalette.textSecondary,
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  String _subtitle(
    List<BarrierPattern> patterns,
    List<BarrierPattern> escalated,
  ) {
    if (patterns.isEmpty) {
      return 'Nobody has been asked why a referral did not complete in the '
          'last ${BarrierEvidence.windowDays} days. "Did not attend" is not '
          'the end of the record — ask, and the answer becomes evidence.';
    }
    if (escalated.isEmpty) {
      return 'Nothing here has been said by enough households to be a system '
          'fact yet. Keep asking; the count is the argument.';
    }
    return 'Reported by ${BarrierEvidence.householdsForPattern} or more '
        'households in the last ${BarrierEvidence.windowDays} days. Each line '
        'names who can fix it, which is the difference between an escalation '
        'and a complaint.';
  }

  Widget _oneOffs(List<BarrierPattern> patterns) {
    if (patterns.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final p in patterns) _Line(pattern: p)],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.pattern});

  final BarrierPattern pattern;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 34,
          child: Text(
            '${pattern.households}',
            style: AppType.stat.copyWith(
              color: FhwLuxePalette.textPrimary,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pattern.barrier.label,
                style: AppType.body.copyWith(
                  color: FhwLuxePalette.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${pattern.owner.label} · ${pattern.unresolved} still open',
                style: AppType.caption.copyWith(
                  color: FhwLuxePalette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
