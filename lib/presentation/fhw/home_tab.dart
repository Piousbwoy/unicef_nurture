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

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/motion.dart';
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
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, 96),
        children: [
          StaggeredReveal(
            index: 0,
            child: _HeroHeader(
              user: user,
              sync: sync,
              online: online,
              households: households,
              plan: plan,
            ),
          ),
          const SizedBox(height: Gap.lg),

          StaggeredReveal(
            index: 1,
            child: _QuickActions(
              households: households,
              onOpenFamilies: onOpenFamilies,
            ),
          ),
          const SizedBox(height: Gap.lg),

          // ------------------------------------- The day at a glance [13a]
          StaggeredReveal(
            index: 2,
            child: _CountsGrid(
              households: households,
              plan: plan,
              referrals: referrals,
              sync: sync,
            ),
          ),
          const SizedBox(height: Gap.lg),

          StaggeredReveal(
            index: 3,
            child: _DailyImpactCard(referrals: referrals),
          ),
          const SizedBox(height: Gap.lg),

          const StaggeredReveal(index: 4, child: _FamilyReportsCard()),
          const SizedBox(height: Gap.lg),

          StaggeredReveal(
            index: 5,
            child: _PendingFollowUpsCard(referrals: referrals),
          ),
          const SizedBox(height: Gap.lg),

          plan.maybeWhen(
            data: (p) => StaggeredReveal(
              index: 6,
              child: _TopThreeCard(plan: p, onOpenQueue: onOpenQueue),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: Gap.lg),

          sync.maybeWhen(
            data: (s) => s.pending > 0
                ? StaggeredReveal(index: 7, child: _SyncPromptCard(summary: s))
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

/// The dashboard header — a glass hero over a royal-blue gradient blob with
/// the health-worker illustration. This is the first thing a CHO sees each
/// morning, so it carries the brand, the greeting, the zone, the offline state
/// and three live counts in one glance.
class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.user,
    required this.sync,
    required this.online,
    required this.households,
    required this.plan,
  });

  final AppUser user;
  final AsyncValue<SyncStatusSummary> sync;
  final AsyncValue<bool> online;
  final AsyncValue<List<Household>> households;
  final AsyncValue<DayPlan> plan;

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
    final familyCount = households.maybeWhen(
      data: (l) => l.length,
      orElse: () => null,
    );
    final seeFirst = plan.maybeWhen(
      data: (p) => p.critical.length + p.high.length,
      orElse: () => null,
    );

    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(GlassTier.hero.radius),
        boxShadow: const [AppShadows.glow],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -40,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            left: -40,
            bottom: -50,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.04),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: Gap.xs),
                        Text(
                          '$part,',
                          style: AppType.headline.copyWith(
                            fontSize: 26,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          first,
                          style: AppType.headline.copyWith(
                            fontSize: 26,
                            color: Colors.white,
                          ),
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
              const SizedBox(height: Gap.md),
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                children: [
                  ConnectivityPill(isOnline: isOnline),
                  if (pending > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Gap.md,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cloud_off_rounded,
                            size: 13,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$pending to sync',
                            style: AppType.label.copyWith(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Gap.lg),
              _StatGrid(
                familyCount: familyCount,
                seeFirst: seeFirst,
                pending: pending,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({
    required this.familyCount,
    required this.seeFirst,
    required this.pending,
  });

  final int? familyCount;
  final int? seeFirst;
  final int pending;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _StatCard(
          icon: Icons.groups_rounded,
          label: 'Families',
          value: familyCount,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1E40AF),
              Color(0xFF3B82F6),
            ],
          ),
          iconColor: Colors.white,
          valueColor: Colors.white,
          labelColor: Colors.white.withValues(alpha: 0.75),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _StatCard(
          icon: Icons.priority_high_rounded,
          label: 'See first',
          value: seeFirst,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFDC2626),
              Color(0xFFF87171),
            ],
          ),
          iconColor: Colors.white,
          valueColor: Colors.white,
          labelColor: Colors.white.withValues(alpha: 0.75),
          live: true,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _StatCard(
          icon: Icons.cloud_upload_rounded,
          label: 'To sync',
          value: pending,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF7C3AED),
              Color(0xFFA78BFA),
            ],
          ),
          iconColor: Colors.white,
          valueColor: Colors.white,
          labelColor: Colors.white.withValues(alpha: 0.75),
          syncing: pending > 0,
        ),
      ),
    ],
  );
}

class _StatCard extends StatefulWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.gradient,
    required this.iconColor,
    required this.valueColor,
    required this.labelColor,
    this.live = false,
    this.syncing = false,
  });

  final IconData icon;
  final String label;
  final int? value;
  final Gradient gradient;
  final Color iconColor;
  final Color valueColor;
  final Color labelColor;
  final bool live;
  final bool syncing;

  @override
  State<_StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<_StatCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The ambient pulse only runs when motion is actually allowed. A
    // repeating controller that keeps ticking behind a static decoration
    // burns battery for nothing and never lets a pumpAndSettle settle.
    final fx = VisualEffects.of(context);
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (fx.motion && !reducedMotion) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fx = VisualEffects.of(context);
    final pulseOpacity = fx.motion
        ? Tween<double>(begin: 0.25, end: 0.6).animate(
            CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
          )
        : const AlwaysStoppedAnimation(0.4);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            gradient: widget.gradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: widget.gradient.colors.first.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Icon badge with pulse
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) => Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(
                      alpha: 0.15 + (fx.motion ? pulseOpacity.value * 0.1 : 0),
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                      width: 1.5,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        widget.icon,
                        size: 20,
                        color: widget.iconColor,
                      ),
                      if (widget.live)
                        Positioned(
                          right: 2,
                          top: 2,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: const Color(0xFF4ADE80),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      if (widget.syncing)
                        Positioned(
                          right: 1,
                          top: 1,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: const Color(0xFFA78BFA),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                            ),
                            child: fx.motion
                                ? AnimatedBuilder(
                                    animation: _pulse,
                                    builder: (context, _) => Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFA78BFA)
                                            .withValues(
                                                alpha: 1 - _pulse.value),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Value with shimmer
              widget.value == null
                  ? Text(
                      '…',
                      style: AppType.numeral.copyWith(
                        fontSize: 26,
                        color: widget.valueColor,
                      ),
                    )
                  : _ShimmerText(
                      text: widget.value!.toString(),
                      style: AppType.numeral.copyWith(
                        fontSize: 26,
                        color: widget.valueColor,
                      ),
                    ),
              const SizedBox(height: 3),
              // Label
              Text(
                widget.label,
                textAlign: TextAlign.center,
                style: AppType.caption.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: widget.labelColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShimmerText extends StatefulWidget {
  const _ShimmerText({
    required this.text,
    required this.style,
  });

  final String text;
  final TextStyle style;

  @override
  State<_ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<_ShimmerText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Same contract as the stat-card pulse: tick only when motion is
    // allowed; the static render path below needs no ticking controller.
    final fx = VisualEffects.of(context);
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (fx.motion && !reducedMotion) {
      if (!_shimmer.isAnimating) _shimmer.repeat();
    } else {
      _shimmer.stop();
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fx = VisualEffects.of(context);
    if (!fx.motion) {
      return Text(widget.text, style: widget.style);
    }
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, _) {
        final shimmerOpacity = 0.3 + 0.7 * (0.5 + 0.5 * _shimmer.value);
        return Opacity(
          opacity: shimmerOpacity,
          child: Text(widget.text, style: widget.style),
        );
      },
    );
  }
}

// -------------------------------------------------------------- Quick actions

/// The quick actions from master flow [13a]: Register & assess / Add
/// household / Search / Sync. **Register & assess is the signature gradient
/// CTA** — it matches the dominant reality at the CHPS compound, where
/// families come to the CHO, so it owns a full-width banner. The three
/// supporting actions sit beside each other as quiet glass chips. "Add
/// household" covers the rarer case of registering a new family *before*
/// they turn up (a referral letter mentions a new hamlet, a community
/// volunteer reports a new family).
class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.households, required this.onOpenFamilies});

  final AsyncValue<List<Household>> households;
  final VoidCallback onOpenFamilies;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The signature action owns a full-width gradient banner — the family is
    // standing in front of the CHO and this is the door they came for. The
    // three supporting actions sit beside each other as compact glass chips
    // so the row reads as one quiet toolbar, not a second grid.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PrimaryCta(
          icon: Icons.person_add_alt_1_rounded,
          label: 'Register & assess',
          helper: 'The family in front of you — everyone who came, one session',
          onTap: () => _registerAndAssess(context, ref),
        ),
        const SizedBox(height: Gap.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _ActionChip(
                icon: Icons.add_home_rounded,
                label: 'Add Household',
                helper: 'New to your zone',
                onTap: () => _addHousehold(context, ref),
              ),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: _ActionChip(
                icon: Icons.search_rounded,
                label: 'Search',
                helper: 'Find a family',
                onTap: onOpenFamilies,
              ),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: _ActionChip(
                icon: Icons.cloud_sync_rounded,
                label: 'Sync',
                helper: 'Send to district',
                onTap: () => _sync(context, ref),
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
      GlassPageRoute<String>(
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

  Future<void> _sync(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(syncServiceProvider).valueOrNull;
    if (service == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Sync is still starting — try again.')),
      );
      return;
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('Sending records to the district…')),
    );
    final report = await service.drain();
    if (!context.mounted) return;
    ref.invalidate(syncStatusProvider);
    final message = report.attempted == 0
        ? 'Nothing waiting to send — every record is with the district.'
        : '${report.accepted} of ${report.attempted} records reached the '
              'district server'
              '${report.deferred > 0 ? ' — ${report.deferred} held, no '
                        'connection' : ''}.';
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Starts a household assessment session: barriers check (which never
/// blocks care) then roll call. Only an explicit "Save & continue" or
/// "Skip — continue" on the barriers screen proceeds to roll call —
/// pressing back there is a change of mind and must land on the dashboard,
/// not inside a half-open session.
Future<void> openVisit(BuildContext context, Household h) async {
  final proceed = await Navigator.of(context).push<bool>(
    GlassPageRoute<bool>(builder: (_) => BarrierCheckScreen(householdId: h.id)),
  );
  if (proceed != true || !context.mounted) return;
  await Navigator.of(context).push(
    GlassPageRoute<void>(builder: (_) => RollCallScreen(householdId: h.id)),
  );
}

/// The signature action: brand-gradient fill, frosted icon disc, white type
/// and a forward arrow — the same visual contract as [GradientButton], so
/// the dashboard keeps one obvious door.
class _PrimaryCta extends StatelessWidget {
  const _PrimaryCta({
    required this.icon,
    required this.label,
    required this.helper,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String helper;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(GlassTier.card.radius);
    return PressScale(
      onTap: onTap,
      radius: radius,
      child: Semantics(
        button: true,
        label: label,
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: Gap.lg,
            horizontal: Gap.lg,
          ),
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: radius,
            boxShadow: const [AppShadows.glow],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppType.title.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      helper,
                      style: AppType.caption.copyWith(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.82),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Gap.sm),
              const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A supporting dashboard action: flat glass, tinted icon disc, label plus a
/// one-line helper. The helper line matters — "Sync" could mean push,
/// refresh or download, and only the caption says which.
class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.helper,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String helper;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(GlassTier.card.radius);
    return PressScale(
      onTap: onTap,
      radius: radius,
      child: Semantics(
        button: true,
        label: label,
        // Inside a scrolling list: glass look, no per-tile blur.
        child: GlassSurface(
          blur: false,
          radius: radius,
          padding: const EdgeInsets.symmetric(
            vertical: Gap.md,
            horizontal: Gap.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.primary, size: 17),
              ),
              const SizedBox(height: Gap.sm),
              Text(
                label,
                style: AppType.label.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                helper,
                style: AppType.caption.copyWith(
                  fontSize: 11,
                  color: AppColors.inkMuted,
                  height: 1.25,
                ),
              ),
            ],
          ),
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

    // One glass instrument: five horizontal rows — tinted icon disc and
    // label left, live numeral right, hairlines between. Rows grow with
    // 200% text instead of overflowing a fixed grid cell.
    final rows = <Widget>[
      _StatRow(
        icon: Icons.home_rounded,
        label: 'Registered Families',
        value: householdCount,
        colour: AppColors.primary,
      ),
      _StatRow(
        icon: Icons.event_available_rounded,
        label: 'Check-ups Due',
        value: pendingCount,
        colour: AppColors.info,
      ),
      _StatRow(
        icon: Icons.priority_high_rounded,
        label: 'See First',
        value: highRiskCount,
        colour: AppColors.triageRed,
      ),
      _StatRow(
        icon: Icons.local_hospital_rounded,
        label: 'Referrals Open',
        value: referralsCount,
        colour: AppColors.triageAmber,
      ),
      _StatRow(
        icon: Icons.cloud_off_rounded,
        label: 'Waiting to Sync',
        value: offlineCount,
        colour: AppColors.offline,
      ),
    ];

    return GlassSurface(
      blur: false,
      padding: const EdgeInsets.symmetric(horizontal: Gap.md),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, thickness: 1, color: AppColors.line),
            rows[i],
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------- Pending follow-ups card

class _PendingFollowUpsCard extends StatelessWidget {
  const _PendingFollowUpsCard({required this.referrals});

  final AsyncValue<List<Referral>> referrals;

  @override
  Widget build(BuildContext context) {
    final count = referrals.maybeWhen(
      data: (l) => l.length,
      orElse: () => null,
    );

    return SectionCard(
      title: 'Pending follow-ups',
      subtitle: count == 0
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
            onPressed: count == null
                ? null
                : () => Navigator.of(context).push(
                    GlassPageRoute<void>(
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

    // The "see first" queue wears the brand gradient — the same visual
    // weight as the Register & assess CTA, because acting on this list is
    // the most important thing the dashboard offers after the CTA itself.
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(GlassTier.card.radius),
        boxShadow: const [AppShadows.glow],
      ),
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.route_rounded,
                  size: 19,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'See these families first',
                      style: AppType.title.copyWith(
                        fontSize: 16.5,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'The families in your zone with the most worrying '
                      'recent records, ranked — the reason is printed on '
                      'every card.',
                      style: AppType.caption.copyWith(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          for (final p in plan.priorities.take(3)) _TopThreeTile(priority: p),
          const SizedBox(height: Gap.sm),
          FilledButton.icon(
            onPressed: onOpenQueue,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('Open the full visits list'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.colour,
  });

  final IconData icon;
  final String label;
  final int? value;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final numeral = AppType.numeral.copyWith(fontSize: 24, color: colour);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.md),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colour.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: colour, size: 17),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Text(label, style: AppType.label.copyWith(fontSize: 13.5)),
          ),
          const SizedBox(width: Gap.sm),
          value == null
              ? Text('…', style: numeral)
              : CountUpText(value: value!, style: numeral),
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
    final radius = BorderRadius.circular(Gap.radiusSm);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.xs),
      child: PressScale(
        radius: radius,
        onTap: () => Navigator.of(context).push(
          GlassPageRoute<void>(
            builder: (_) => HouseholdScreen(householdId: priority.household.id),
          ),
        ),
        // The triage edge carries the clinical colour; the row itself stays
        // neutral glass so the colour means what it says.
        child: AccentEdge(
          accent: c.fg,
          borderRadius: radius,
          child: GlassSurface(
            tier: GlassTier.chip,
            blur: false,
            radius: radius,
            shadow: false,
            padding: const EdgeInsets.all(Gap.md),
            child: Row(
              children: [
                _InitialsAvatar(
                  name: priority.household.name,
                  foreground: c.fg,
                  background: c.bg,
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Text(
                  '${priority.score.score.round()}',
                  style: AppType.numeral.copyWith(fontSize: 18, color: c.fg),
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

/// Two-letter initials on a tinted disc. Used for the "see first" queue so a
/// row is recognisable before the name is read.
class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({
    required this.name,
    required this.foreground,
    required this.background,
  });

  final String name;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
    final initials = parts.isEmpty
        ? '?'
        : parts.length == 1
        ? parts.first[0]
        : '${parts.first[0]}${parts.last[0]}';

    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: Border.all(color: foreground.withValues(alpha: 0.30), width: 1),
      ),
      child: Text(
        initials.toUpperCase(),
        style: AppType.title.copyWith(
          color: foreground,
          fontSize: 14,
          fontWeight: FontWeight.w800,
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
    final days = DateTime.now().dateOnly
        .difference(check.checkedAt.dateOnly)
        .inDays;
    final when = switch (days) {
      <= 0 => 'today',
      1 => 'yesterday',
      _ => '$days days ago',
    };

    final radius = BorderRadius.circular(Gap.radiusSm);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xs),
      child: PressScale(
        radius: radius,
        onTap: () => Navigator.of(context).push(
          GlassPageRoute<void>(
            builder: (_) => HouseholdScreen(householdId: check.householdId),
          ),
        ),
        child: GlassSurface(
          tier: GlassTier.chip,
          blur: false,
          radius: radius,
          shadow: false,
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

// ---------------------------------------------------------------- Daily impact

/// Today's impact summary — a slim banner between the counts and the
/// briefing, not another card. "Households" counts visits actually made
/// since midnight, never household rows merely edited — an edit is not a
/// visit. "Referrals" counts referrals *issued* today, so it agrees with
/// the "Referrals Open" row above whenever the day's referral is still
/// open (a referral closed the same day still counts — it was made today).
class _DailyImpactCard extends ConsumerWidget {
  const _DailyImpactCard({required this.referrals});

  final AsyncValue<List<Referral>> referrals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    // Visit-based, not edit-based: only a real visit since local midnight
    // counts as a household visited today.
    final visitedToday =
        ref.watch(householdsVisitedTodayProvider).valueOrNull ?? 0;

    // Referrals issued today. The provider lists open referrals, and a
    // referral made today is open by definition — so this number tracks the
    // "Referrals Open" row for the current day's work instead of silently
    // dropping same-day referrals that have not "reached care" yet.
    final issuedToday = referrals.maybeWhen(
      data: (list) => list.where((r) => r.issuedAt.isAfter(startOfDay)).length,
      orElse: () => 0,
    );

    // Only show the card if there's something to report, or if it's still
    // morning (encourage the CHO to get started).
    final isMorning = today.hour < 12;
    if (visitedToday == 0 && issuedToday == 0 && !isMorning) {
      return const SizedBox.shrink();
    }

    final fresh = visitedToday == 0 && issuedToday == 0;

    // The day's two numbers sit beside the title so the strip reads in one
    // glance; the encouragement only appears before the first visit.
    return GlassSurface(
      blur: false,
      tint: AppColors.primaryGlow,
      padding: const EdgeInsets.all(Gap.md),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.insights_rounded,
              size: 19,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Today\'s Impact',
                  style: AppType.eyebrow.copyWith(color: AppColors.primary),
                ),
                if (fresh) ...[
                  const SizedBox(height: 2),
                  Text(
                    'A fresh day. Every household you visit today matters.',
                    style: AppType.caption.copyWith(color: AppColors.inkMuted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Gap.md),
          _MiniStat(label: 'Households', value: visitedToday),
          const SizedBox(width: Gap.lg),
          _MiniStat(label: 'Referrals', value: issuedToday),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        CountUpText(
          value: value,
          style: AppType.numeral.copyWith(fontSize: 22, color: AppColors.ink),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppType.caption.copyWith(
            fontSize: 11,
            color: AppColors.inkMuted,
          ),
        ),
      ],
    );
  }
}
