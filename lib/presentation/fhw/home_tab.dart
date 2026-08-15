/// The frontline health worker's home: a glance, not a feed.
///
/// The design intent is that this screen answers four questions in under
/// three seconds — *how many households, how many pending, how many at risk,
/// how many offline* — and one big question out loud: *who just walked in?*
/// A CHO opening the app at 6am should not have to scroll to find their day.
///
/// In the CHPS-compound reality of Northern Ghana, **patients come to the
/// health worker, not the other way around** — the walk-in mother with a
/// feverish newborn, the defaulter who finally turned up, the toddler whose
/// uncle brought him in. So the signature action is "Register & assess":
/// the family standing in front of you, all of them, in one session.
/// Households are still registered, but as the address behind a person, not
/// as the unit the CHO reasons about.
///
/// Planned follow-up contacts (ANC, PNC, defaulter tracing) exist — but they
/// are reached through the day plan and the household detail screen, not the
/// primary action.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/outbox_dao.dart';
import '../../data/repositories/insight_repository.dart';
import '../../domain/entities/core.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../registration/patient_intake_screen.dart';
import '../shared/app_image.dart';
import '../shared/ui.dart';
import '../visit/barrier_check_screen.dart';
import '../visit/roll_call_screen.dart';
import 'families_tab.dart';
import 'household_screen.dart';
import 'pending_followups_screen.dart';

class FhwHomeTab extends ConsumerWidget {
  const FhwHomeTab({
    super.key,
    required this.onOpenFamilies,
    required this.onOpenQueue,
  });

  /// Switches the shell to the Families tab — the "Search" quick action.
  final VoidCallback onOpenFamilies;

  /// Switches the shell to the Queue tab — the "full queue" action. A tab
  /// switch, not a pushed page: the queue is a peer of this screen, not a
  /// detail underneath it.
  final VoidCallback onOpenQueue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();

    final households = ref.watch(visibleHouseholdsProvider);
    final plan = ref.watch(dayPlanProvider);
    final referrals = ref.watch(openReferralsProvider);
    final sync = ref.watch(syncStatusProvider);
    final online = ref.watch(connectivityProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(visibleHouseholdsProvider);
        ref.invalidate(dayPlanProvider);
        ref.invalidate(openReferralsProvider);
        ref.invalidate(zoneHomeChecksProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: [
          _HeroHeader(user: user, sync: sync, online: online),
          const SizedBox(height: Gap.lg),

          _QuickActions(
            households: households,
            onOpenFamilies: onOpenFamilies,
          ),
          const SizedBox(height: Gap.lg),

          // ------------------------------------- The five dashboard cards [13a]
          _CountsGrid(
            households: households,
            plan: plan,
            referrals: referrals,
            sync: sync,
          ),
          const SizedBox(height: Gap.lg),

          const _FamilyReportsCard(),
          const SizedBox(height: Gap.lg),

          _PendingFollowUpsCard(referrals: referrals),
          const SizedBox(height: Gap.lg),

          plan.maybeWhen(
            data: (p) => _TopThreeCard(plan: p, onOpenQueue: onOpenQueue),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: Gap.lg),

          sync.maybeWhen(
            data: (s) => s.pending > 0
                ? _SyncPromptCard(summary: s)
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: Gap.xxl),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Hero header

/// The dashboard header — a royal-blue gradient card with the health-worker
/// illustration. This is the first thing a CHO sees each morning, so it carries
/// the brand, the greeting, the zone, and the offline state in one glance.
class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.user, required this.sync, required this.online});

  final AppUser user;
  final AsyncValue<SyncStatusSummary> sync;
  final AsyncValue<bool> online;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final part = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final first = user.fullName.split(' ').first;
    final pending = sync.maybeWhen(data: (s) => s.pending, orElse: () => 0);
    final isOnline = online.maybeWhen(data: (o) => o, orElse: () => false);

    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(Gap.radius),
        boxShadow: const [AppShadows.glow],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (user.chpsZone ??
                          '${user.community}, ${user.district}')
                      .toUpperCase(),
                  style: AppType.eyebrow.copyWith(
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: Gap.sm),
                Text(
                  '$part,\n$first',
                  style: AppType.headline.copyWith(
                    color: Colors.white,
                    fontSize: 26,
                  ),
                ),
                const SizedBox(height: Gap.md),
                Row(
                  children: [
                    // Always-visible connectivity pill.
                    ConnectivityPill(isOnline: isOnline),
                    // Pending-sync badge — only when records are waiting.
                    if (pending > 0) ...[ 
                      const SizedBox(width: Gap.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Gap.md,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.cloud_off_rounded,
                              size: 13,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$pending to sync',
                              style: GoogleFonts.manrope(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: Gap.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(Gap.radiusSm),
            child: SizedBox(
              width: 96,
              height: 96,
              child: AppImage(src: AppImages.fhwHero),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- Quick actions

/// The three quick actions from master flow [13a]: Register & assess / Add
/// household / Search / Sync. **Register & assess is the signature gradient
/// CTA** — it matches the dominant reality at the CHPS compound, where
/// families come to the CHO. "Add household" is a supporting tile for the
/// rarer case where the CHO is registering a new family *before* they turn
/// up (a referral letter mentions a new hamlet, a community volunteer
/// reports a new family).
class _QuickActions extends ConsumerWidget {
  const _QuickActions({
    required this.households,
    required this.onOpenFamilies,
  });

  final AsyncValue<List<Household>> households;
  final VoidCallback onOpenFamilies;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The signature CTA: a family just walked in — register everyone who
        // came, then assess them one by one in a single session.
        GradientButton(
          label: 'Register & assess',
          icon: Icons.person_add_alt_1_rounded,
          onPressed: () => _registerAndAssess(context, ref),
        ),
        const SizedBox(height: Gap.md),
        Text(
          'A family has walked in. Register everyone who came, then assess them one by one in the same session.',
          style: AppType.caption.copyWith(
            color: AppColors.inkMuted,
            fontSize: 12,
            height: 1.35,
          ),
        ),
        const SizedBox(height: Gap.md),
        Row(
          children: [
            Expanded(
              child: _ActionTile(
                icon: Icons.add_home_rounded,
                label: 'Add Household',
                onTap: () => _addHousehold(context, ref),
                helper: 'A family new to your zone',
              ),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: _ActionTile(
                icon: Icons.search_rounded,
                label: 'Search',
                onTap: onOpenFamilies,
                helper: 'Find a family',
              ),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: _ActionTile(
                icon: Icons.cloud_sync_rounded,
                label: 'Sync',
                onTap: () => _sync(context, ref),
                helper: 'Send records to the district',
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Clinic intake. The family is in front of the CHO. The intake screen
  /// chains: pick a household (or register a new one) → mark who came →
  /// open one assessment session for everyone. Each step has its own back
  /// button so a CHO can recover from a wrong pick without losing the work
  /// that came before.
  Future<void> _registerAndAssess(BuildContext context, WidgetRef ref) async {
    final list = ref.read(visibleHouseholdsProvider).valueOrNull ?? const [];
    final householdId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => PatientIntakeScreen(knownHouseholds: list),
      ),
    );
    if (householdId != null) {
      // The intake screen ran the session to sign-off and has already
      // invalidated the caches; nothing left to do here.
      return;
    }
  }

  Future<void> _addHousehold(BuildContext context, WidgetRef ref) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const HouseholdFormSheet(),
    );
    if (created == true) {
      ref.invalidate(visibleHouseholdsProvider);
      ref.invalidate(dayPlanProvider);
    }
  }

  void _sync(BuildContext context, WidgetRef ref) {
    ref.read(syncServiceProvider).valueOrNull?.drain();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Syncing records\u2026')),
    );
  }
}

/// Starts a household assessment session: barriers check (which never blocks
/// care) then roll call.
Future<void> openVisit(BuildContext context, Household h) async {
  await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => BarrierCheckScreen(householdId: h.id)),
  );
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => RollCallScreen(householdId: h.id)),
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.helper,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// One-line secondary caption. The FHW has been burned too many times by
  /// icon-only tiles that mean three different things in three different
  /// apps — a tile that says "Sync" might be "push records", "refresh from
  /// server", or "open a download queue", and only the helper line disam-
  /// biguates it.
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      radius: BorderRadius.circular(Gap.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Gap.md, horizontal: Gap.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Gap.radiusSm),
          border: Border.all(color: AppColors.line, width: Gap.hairline),
        ),
        child: Column(
          children: [
            // Brand-gradient icon medallion. The eye reads a small royal
            // disc as "primary action" the way it reads a flat icon as
            // "toolbar", and FHWs scan a row of three tiles left-to-right
            // for the one they want.
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x221B56DB),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 17),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppType.caption.copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            if (helper != null) ...[
              const SizedBox(height: 2),
              Text(
                helper!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.caption.copyWith(
                  fontSize: 10,
                  color: AppColors.inkFaint,
                  height: 1.2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- Counts

class _CountsGrid extends StatelessWidget {
  const _CountsGrid({
    required this.households,
    required this.plan,
    required this.referrals,
    required this.sync,
  });

  final AsyncValue<List<Household>> households;
  final AsyncValue<DayPlan> plan;
  final AsyncValue<List<Referral>> referrals;
  final AsyncValue<SyncStatusSummary> sync;

  @override
  Widget build(BuildContext context) {
    final householdCount = households.maybeWhen(
      data: (l) => l.length,
      orElse: () => null,
    );
    final pendingCount = plan.maybeWhen(
      data: (p) => p.dueContacts.length + p.overdueContacts.length,
      orElse: () => null,
    );
    final highRiskCount = plan.maybeWhen(
      data: (p) => p.critical.length + p.high.length,
      orElse: () => null,
    );
    final referralsCount = referrals.maybeWhen(
      data: (l) => l.length,
      orElse: () => null,
    );
    final offlineCount = sync.maybeWhen(
      data: (s) => s.pending,
      orElse: () => null,
    );

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: Gap.md,
      crossAxisSpacing: Gap.md,
      childAspectRatio: 1.15,
      children: [
        _CountTile(
          icon: Icons.home_rounded,
          label: 'Registered Families',
          value: householdCount,
          colour: AppColors.primary,
        ),
        _CountTile(
          icon: Icons.event_available_rounded,
          label: 'Check-ups Due',
          value: pendingCount,
          colour: AppColors.info,
        ),
        _CountTile(
          icon: Icons.priority_high_rounded,
          label: 'See First',
          value: highRiskCount,
          colour: AppColors.triageRed,
        ),
        _CountTile(
          icon: Icons.local_hospital_rounded,
          label: 'Referrals Open',
          value: referralsCount,
          colour: AppColors.triageAmber,
        ),
        _CountTile(
          icon: Icons.cloud_off_rounded,
          label: 'Waiting to Sync',
          value: offlineCount,
          colour: AppColors.offline,
          fullWidth: true,
        ),
      ],
    );
  }
}

// ---------------------------------------------------- Pending follow-ups card

class _PendingFollowUpsCard extends StatelessWidget {
  const _PendingFollowUpsCard({required this.referrals});

  final AsyncValue<List<Referral>> referrals;

  @override
  Widget build(BuildContext context) {
    final count = referrals.maybeWhen(data: (l) => l.length, orElse: () => null);

    return SectionCard(
      title: 'Pending follow-ups',
      subtitle:
          count == 0
              ? 'Every referred family has been accounted for.'
              : 'Referred but not yet confirmed to have reached care.',
      icon: Icons.contact_phone_outlined,
      accent: AppColors.triageAmber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (count != null && count > 0)
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Gap.md,
                    vertical: Gap.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.triageAmberBg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.triageAmber.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Text(
                    '$count need checking',
                    style: AppType.label.copyWith(
                      color: AppColors.triageAmber,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: Gap.md),
          FilledButton.icon(
            onPressed:
                count == null
                    ? null
                    : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PendingFollowUpsScreen(),
                      ),
                    ),
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(count == 0 ? 'View history' : 'Check them now'),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------- Top three to see

class _TopThreeCard extends StatelessWidget {
  const _TopThreeCard({required this.plan, required this.onOpenQueue});
  final DayPlan plan;
  final VoidCallback onOpenQueue;

  @override
  Widget build(BuildContext context) {
    if (plan.priorities.isEmpty) {
      return SectionCard(
        title: 'Today\u2019s plan',
        subtitle:
            'No households are flagged in your zone. Use the day for routine check-ups.',
        icon: Icons.wb_sunny_outlined,
        child: const SizedBox.shrink(),
      );
    }

    return SectionCard(
      title: 'See these families first',
      subtitle:
          'Ranked from each family\u2019s own records — the reason is printed on every card.',
      icon: Icons.route_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final p in plan.priorities.take(3))
            _TopThreeTile(priority: p),
          const SizedBox(height: Gap.sm),
          OutlinedButton.icon(
            onPressed: onOpenQueue,
            icon: const Icon(Icons.people_alt_outlined),
            label: const Text('Open the full queue'),
          ),
        ],
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.colour,
    this.fullWidth = false,
  });

  final IconData icon;
  final String label;
  final int? value;
  final Color colour;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Gap.radius),
        border: Border.all(color: AppColors.line, width: Gap.hairline),
        boxShadow: const [AppShadows.card],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colour, size: 19),
          const Spacer(),
          Text(
            value == null ? '…' : '$value',
            style: AppType.display.copyWith(
              fontSize: 30,
              fontWeight: FontWeight.w600,
              color: colour,
            ),
          ),
          const SizedBox(height: Gap.xs),
          Text(
            label,
            style: AppType.caption.copyWith(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------- Household picker

/// A searchable "choose a household" sheet.
///
/// Public so the Assess tab's "Start Assessment" action can reuse the exact
/// same picker rather than growing a second one — there is one way to pick a
/// household from a list on this shell.
class HouseholdPicker extends StatefulWidget {
  const HouseholdPicker({super.key, required this.list});
  final List<Household> list;

  @override
  State<HouseholdPicker> createState() => _HouseholdPickerState();
}

class _HouseholdPickerState extends State<HouseholdPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.list
        : widget.list
              .where(
                (h) =>
                    h.name.toLowerCase().contains(q) ||
                    h.community.toLowerCase().contains(q),
              )
              .toList(growable: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.lg),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Text('Choose a household', style: AppType.title),
            const SizedBox(height: Gap.md),
            TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search_rounded, size: 19),
                hintText: 'Search by name or community',
              ),
            ),
            const SizedBox(height: Gap.md),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.home_outlined,
                    size: 19,
                    color: AppColors.inkMuted,
                  ),
                  title: Text(
                    filtered[i].name,
                    style: AppType.label.copyWith(fontSize: 14.5),
                  ),
                  subtitle: Text(
                    '${filtered[i].community} · ${filtered[i].district}',
                    style: AppType.caption,
                  ),
                  onTap: () => Navigator.of(context).pop(filtered[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------- Top three to see

class _TopThreeTile extends StatelessWidget {
  const _TopThreeTile({required this.priority});
  final HouseholdPriority priority;

  @override
  Widget build(BuildContext context) {
    final band = priority.band;
    final c = triageColours(band.triage);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.xs),
      child: Material(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(Gap.radiusSm),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  HouseholdScreen(householdId: priority.household.id),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.bg,
                    borderRadius: BorderRadius.circular(Gap.radiusSm),
                    border: Border.all(
                      color: c.fg.withValues(alpha: 0.30),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '${priority.score.score.round()}',
                    style: AppType.title.copyWith(
                      color: c.fg,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        priority.household.name,
                        style: AppType.label.copyWith(fontSize: 14.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        priority.reason,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
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

// ------------------------------------------------------------- Sync prompt

/// The morning briefing. Home checks are deliberately local-only — they
/// never enter the outbox — but caregiver mode runs on this same device, so
/// what a mother saw at midnight is what the CHO reads at 6am. A red report
/// here outranks the route plan: a family that found danger before the
/// worker arrived should see the worker first.
class _FamilyReportsCard extends ConsumerWidget {
  const _FamilyReportsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checks = ref.watch(zoneHomeChecksProvider).valueOrNull;
    if (checks == null || checks.isEmpty) return const SizedBox.shrink();

    final urgent = checks
        .where((c) => c.verdict == HomeCheckVerdict.urgent)
        .length;

    return SectionCard(
      title: 'Families checked at home',
      subtitle: urgent > 0
          ? '$urgent ${urgent == 1 ? 'family' : 'families'} found danger '
                'signs this week. See them first.'
          : 'What families saw at home this week, in their own words.',
      icon: Icons.family_restroom_rounded,
      accent: urgent > 0 ? AppColors.triageRed : AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final check in checks.take(5)) _BriefingTile(check: check),
          const SizedBox(height: Gap.xs),
          const Text(
            'These reports stay on the family\u2019s phone — they appear '
            'here because caregiver mode shares this device.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.inkFaint,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// One family report in the briefing. The verdict dot carries the colour so
/// a red report is visible before it is read; tapping opens the household so
/// the worker can act on it, not just read it.
class _BriefingTile extends ConsumerWidget {
  const _BriefingTile({required this.check});

  final HomeCheck check;

  Color get _colour => switch (check.verdict) {
    HomeCheckVerdict.urgent => AppColors.triageRed,
    HomeCheckVerdict.caution => AppColors.triageAmber,
    HomeCheckVerdict.fine => AppColors.triageGreen,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = ref.watch(personProvider(check.personId));
    final days = DateTime.now().dateOnly.difference(
      check.checkedAt.dateOnly,
    ).inDays;
    final when = switch (days) {
      <= 0 => 'today',
      1 => 'yesterday',
      _ => '$days days ago',
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xs),
      child: Material(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(Gap.radiusSm),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  HouseholdScreen(householdId: check.householdId),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: _colour,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.valueOrNull?.fullName ?? '…',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.label.copyWith(fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${check.verdict.label} · $when',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption.copyWith(
                          fontSize: 12,
                          color: check.verdict == HomeCheckVerdict.fine
                              ? AppColors.inkMuted
                              : _colour,
                          fontWeight: check.verdict == HomeCheckVerdict.fine
                              ? FontWeight.w500
                              : FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (check.yesSigns.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.sm,
                      vertical: Gap.xs,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.triageRedBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${check.yesSigns.length} '
                      '${check.yesSigns.length == 1 ? 'sign' : 'signs'}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.triageRed,
                      ),
                    ),
                  ),
                  const SizedBox(width: Gap.xs),
                ],
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
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

// ------------------------------------------------------------- Sync prompt

class _SyncPromptCard extends StatelessWidget {
  const _SyncPromptCard({required this.summary});
  final SyncStatusSummary summary;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Records still on this phone',
      subtitle: summary.detail,
      icon: Icons.cloud_sync_rounded,
      accent: AppColors.offline,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.md,
              vertical: Gap.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.offlineBg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppColors.offline.withValues(alpha: 0.28),
                width: 1,
              ),
            ),
            child: Text(
              '${summary.pending} waiting',
              style: AppType.label.copyWith(
                color: AppColors.offline,
                fontSize: 12.5,
              ),
            ),
          ),
          if (summary.criticalPending > 0) ...[
            const SizedBox(width: Gap.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.md,
                vertical: Gap.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.triageRedBg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppColors.triageRed.withValues(alpha: 0.28),
                  width: 1,
                ),
              ),
              child: Text(
                '${summary.criticalPending} urgent',
                style: AppType.label.copyWith(
                  color: AppColors.triageRed,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
