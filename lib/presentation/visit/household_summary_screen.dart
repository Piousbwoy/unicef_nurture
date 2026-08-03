/// The household assessment summary — master flow [47], and the sign-off [58].
///
/// This is the screen that makes a multi-person session feel like *one*
/// encounter rather than three separate ones. After the last person in the
/// queue is assessed, the CHO lands here and sees the whole household at a
/// glance: every person seen today with their risk badge, the referrals that
/// went out, and the clinic note. Only then do they sign the encounter off.
///
/// It is deliberately the calmest screen in the app. The clinical work is
/// done; this is the moment of confirmation. The offline banner is never an
/// error — "saved locally, will sync when connected" — because a CHO who
/// just finished a three-person session needs to trust that the record is
/// safe, not worry about the network.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../shared/app_image.dart';
import '../shared/ui.dart';

class HouseholdSummaryScreen extends ConsumerStatefulWidget {
  const HouseholdSummaryScreen({
    super.key,
    required this.visit,
    required this.householdId,
    required this.assessedIds,
    this.notes,
  });

  final Visit visit;
  final String householdId;

  /// Everyone assessed in this session, in the order they were seen.
  final List<String> assessedIds;

  final String? notes;

  @override
  ConsumerState<HouseholdSummaryScreen> createState() =>
      _HouseholdSummaryScreenState();
}

class _HouseholdSummaryScreenState
    extends ConsumerState<HouseholdSummaryScreen> {
  bool _saving = false;

  Future<void> _save() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    setState(() => _saving = true);
    await ref.read(careRepositoryProvider).completeVisit(
      user,
      widget.visit.id,
      notes: widget.notes?.trim().isEmpty == true ? null : widget.notes?.trim(),
    );

    // The session is now a closed encounter. Everything downstream — the day
    // plan, the history, the referral tracker — is stale until it reloads.
    ref.invalidate(dayPlanProvider);
    ref.invalidate(visitHistoryProvider(widget.householdId));
    ref.invalidate(openReferralsProvider);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final household = ref.watch(householdProvider(widget.householdId));
    final referrals = ref.watch(openReferralsProvider);

    // Referrals issued for anyone seen today. The reference codes reappear
    // here so the loop is visibly closed: refer → confirm → see it again.
    final sessionReferrals = referrals.maybeWhen(
      data: (list) => list
          .where((r) => widget.assessedIds.contains(r.personId))
          .toList(growable: false),
      orElse: () => const <Referral>[],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Assessment summary')),
      body: ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: [
          _SummaryHero(
            householdName: household.valueOrNull?.name ?? 'This household',
            assessedCount: widget.assessedIds.length,
          ),
          const SizedBox(height: Gap.lg),

          SectionCard(
            title: 'Everyone seen today',
            subtitle:
                'One encounter, ${widget.assessedIds.length} '
                '${widget.assessedIds.length == 1 ? 'person' : 'people'}. '
                'Each row is the verdict the protocol reached.',
            icon: Icons.groups_2_rounded,
            child: Column(
              children: [
                for (final id in widget.assessedIds) _SummaryTile(personId: id),
              ],
            ),
          ),
          const SizedBox(height: Gap.lg),

          if (sessionReferrals.isNotEmpty) ...[
            SectionCard(
              title: 'Referrals issued today',
              subtitle:
                  'Show the code at the facility gate. It is also kept in the '
                  'referral tracker and on this household\u2019s record.',
              icon: Icons.local_hospital_outlined,
              accent: AppColors.triageRed,
              child: Column(
                children: [
                  for (final r in sessionReferrals)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Gap.sm),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Gap.md,
                              vertical: Gap.xs,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              r.referenceCode,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                          const SizedBox(width: Gap.md),
                          Expanded(
                            child: Text(
                              '${r.facilityName} · ${r.urgency.label}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.inkMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Gap.lg),
          ],

          if (widget.notes?.trim().isNotEmpty == true) ...[
            SectionCard(
              title: 'Clinic note',
              icon: Icons.edit_note_rounded,
              child: Text(
                widget.notes!.trim(),
                style: const TextStyle(fontSize: 13.5, height: 1.5),
              ),
            ),
            const SizedBox(height: Gap.lg),
          ],

          // Master flow [60] — the offline state is always calm, never an
          // error. The record is safe on the phone; the network can wait.
          Container(
            padding: const EdgeInsets.all(Gap.md),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(Gap.radiusSm),
            ),
            child: Row(
              children: [
                const Icon(Icons.cloud_done_rounded, color: AppColors.primary),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Text(
                    'Saved on this phone. It will sync to the district system '
                    'the next time you are connected.',
                    style: GoogleFonts.manrope(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.xxl),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(Gap.lg),
        child: GradientButton(
          label: _saving ? 'Saving session…' : 'Save & close session',
          icon: _saving ? Icons.hourglass_top_rounded : Icons.check_circle_rounded,
          onPressed: _saving ? null : _save,
        ),
      ),
    );
  }
}

/// The gradient header — a quiet "the work is done" banner, not a clinical
/// table. The household's name is the headline because the session belongs to
/// the household, not to any single patient.
class _SummaryHero extends StatelessWidget {
  const _SummaryHero({
    required this.householdName,
    required this.assessedCount,
  });

  final String householdName;
  final int assessedCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(Gap.radius),
        boxShadow: const [AppShadows.glow],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(Gap.md),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.task_alt_rounded,
              color: AppColors.primary,
              size: 30,
            ),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  householdName,
                  style: AppType.headline.copyWith(
                    color: Colors.white,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: Gap.xs),
                Text(
                  assessedCount == 1
                      ? '1 person seen today'
                      : '$assessedCount people seen today',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One row per person seen: category illustration, name, risk badge and the
/// protocol's classification. The illustration keeps the screen visual — the
/// CHO has been reading forms for an hour; this is the part they glance at.
class _SummaryTile extends ConsumerWidget {
  const _SummaryTile({required this.personId});

  final String personId;

  String _image(ClientType type) => switch (type) {
    ClientType.newborn => AppImages.cardNewborn,
    ClientType.childUnderFive => AppImages.cardChild,
    _ => AppImages.cardMother,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = ref.watch(personProvider(personId));
    final latest = ref.watch(latestAssessmentProvider(personId));

    return Container(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          person.maybeWhen(
            data: (p) => p == null
                ? const SizedBox(width: 48, height: 48)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(Gap.radiusXs),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: AppImage(src: _image(p.effectiveClientType)),
                    ),
                  ),
            orElse: () => const SizedBox(width: 48, height: 48),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.valueOrNull?.fullName ?? '…',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                latest.maybeWhen(
                  data: (a) => a == null
                      ? const SizedBox.shrink()
                      : Text(
                          a.result.classification,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.inkMuted,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          const SizedBox(width: Gap.sm),
          latest.maybeWhen(
            data: (a) => a == null
                ? const SizedBox.shrink()
                : TriageBadge(a.effectiveTriage, compact: true),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
