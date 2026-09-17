/// The Assess tab — the primary launch point for a clinical assessment.
///
/// This tab replaces the old Families tab. Assessment is the reason a CHO
/// browses the register, so the register (search + browse) now lives directly
/// under a prominent "Start Assessment" action instead of behind a household
/// detail screen. Two entry depths, both one tap from the bottom nav:
///
///  * **Start Assessment** (the signature gradient CTA) — no household is
///    pre-selected, so the CHO picks a household from a searchable sheet and
///    is taken through the canonical session flow (barriers check → roll call).
///  * **Per-row Assess** — when the CHO already knows which household, the
///    quiet play button on each register row jumps straight into that
///    household's roll call, skipping the detail screen entirely.
///
/// This is a new, faster entry point — it does not replace the household
/// screen's "Start assessment" button or the roll call's per-person actions,
/// which all still run the same underlying flow.
///
/// The whole tab is gated on `Permission.runClinicalAssessment`. The role
/// system should never route a user without that capability here, and the
/// repository re-checks on every write anyway — but defense-in-depth means the
/// UI degrades to a clear restricted state rather than a broken screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/motion.dart';
import '../../data/repositories/care_repository.dart';
import '../../domain/entities/core.dart';
import '../../domain/enums.dart';
import '../shared/ui.dart';
import 'families_tab.dart';
import 'home_tab.dart';
import 'household_screen.dart';

class AssessTab extends ConsumerStatefulWidget {
  const AssessTab({super.key});

  @override
  ConsumerState<AssessTab> createState() => _AssessTabState();
}

class _AssessTabState extends ConsumerState<AssessTab> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();

    // Capability gate: degrade to a clear state, never a broken screen.
    if (!user.can(Permission.runClinicalAssessment)) {
      return const EmptyState(
        icon: Icons.verified_user_outlined,
        title: 'Assessments restricted',
        message:
            'This account cannot run clinical assessments. Sign in with a '
            'community health nurse account to run an assessment.',
      );
    }

    final households = ref.watch(visibleHouseholdsProvider);

    return Column(
      children: [
        // The signature primary action: start an assessment. It sits at the
        // top so the single most important thing a CHO does is the first
        // thing they see.
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.sm),
          child: GradientButton(
            label: 'Start Assessment',
            icon: Icons.play_circle_outline_rounded,
            onPressed: _startAssessment,
          ),
        ),

        // Register-and-assess in one visit: the family is new, so the CHO
        // adds the household here and it lands in the register below, ready
        // to assess in the same sitting.
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.sm),
          child: OutlinedButton.icon(
            onPressed: _registerHousehold,
            icon: const Icon(Icons.add_home_work_outlined, size: 18),
            label: const Text('Register a new household'),
          ),
        ),

        // The relocated register: the exact search + browse the Families tab
        // had, now pinned under the assessment launch point. A glass field
        // rather than an outlined one so it sits on the ambient backdrop
        // like the cards below it.
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.sm),
          child: GlassSurface(
            blur: false,
            radius: BorderRadius.circular(Gap.radius),
            padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                isDense: true,
                filled: false,
                prefixIcon: Icon(Icons.search_rounded),
                hintText:
                    'Search name, head of household, community, or landmark',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
        ),

        Expanded(
          child: households.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                ErrorView(error: e is AccessDenied ? e.message : e),
            data: (list) {
              final q = _search.text.trim().toLowerCase();
              final filtered = q.isEmpty
                  ? list
                  : list
                        .where(
                          (h) =>
                              h.name.toLowerCase().contains(q) ||
                              (h.headName?.toLowerCase().contains(q) ??
                                  false) ||
                              h.community.toLowerCase().contains(q) ||
                              (h.landmark?.toLowerCase().contains(q) ?? false),
                        )
                        .toList(growable: false);

              if (filtered.isEmpty) {
                return EmptyState(
                  icon: Icons.search_off_rounded,
                  title: q.isEmpty ? 'No families yet' : 'No match',
                  message: q.isEmpty
                      ? 'Tap "Register a new household" above to add the '
                            'first family.'
                      : 'Nothing matches "$q". Try a name, the head of the '
                            'household, or the landmark.',
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, 96),
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final household = filtered[i];
                  return StaggeredReveal(
                    index: i,
                    child: _RegisterRow(
                      household: household,
                      onTap: () => _open(household.id),
                      // The permission gate above means everyone who reaches
                      // this list can assess, so every row carries the
                      // shortcut.
                      onAssess: () => openVisit(context, household),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _open(String id) {
    Navigator.of(context).push(
      GlassPageRoute<void>(builder: (_) => HouseholdScreen(householdId: id)),
    );
  }

  /// The top CTA. No household is pre-selected, so prompt the CHO to pick one
  /// from the searchable sheet, then run the canonical session flow — the same
  /// barriers-check → roll-call navigation the household screen's "Start
  /// assessment" already uses.
  Future<void> _startAssessment() async {
    final list = ref.read(visibleHouseholdsProvider).valueOrNull;
    if (list == null || list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No households yet \u2014 register a household first.'),
        ),
      );
      return;
    }

    final picked = await showModalBottomSheet<Household>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => HouseholdPicker(list: list),
    );
    if (picked != null && mounted) {
      await openVisit(context, picked);
    }
  }

  /// Opens the shared household form; on success the new family is already
  /// in the register below, ready to assess in the same sitting.
  Future<void> _registerHousehold() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const HouseholdFormSheet(),
    );
    if (created == true && mounted) {
      ref.invalidate(visibleHouseholdsProvider);
      ref.invalidate(dayPlanProvider);
    }
  }
}

// ------------------------------------------------------------ Register row

/// One household in the register: glass row, initials disc, member count and
/// the quiet play button that jumps straight to roll call. Mirrors the
/// Families tab tile so the two lists read as the same register.
class _RegisterRow extends ConsumerWidget {
  const _RegisterRow({
    required this.household,
    required this.onTap,
    required this.onAssess,
  });

  final Household household;
  final VoidCallback onTap;
  final VoidCallback onAssess;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(householdMembersProvider(household.id));
    final count = members.valueOrNull?.length;
    final radius = BorderRadius.circular(Gap.radius);

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: PressScale(
        onTap: onTap,
        radius: radius,
        child: GlassSurface(
          // In a scrolling list: glass look, no per-row blur filter.
          blur: false,
          radius: radius,
          padding: const EdgeInsets.all(Gap.md),
          child: Row(
            children: [
              Container(
                height: 42,
                width: 42,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  _initials(household.name),
                  style: AppType.title.copyWith(
                    color: AppColors.primaryDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      household.name,
                      style: AppType.label.copyWith(fontSize: 14.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${household.community} · ${household.district}',
                      style: AppType.caption.copyWith(fontSize: 12),
                    ),
                    if (household.landmark != null &&
                        household.landmark!.isNotEmpty)
                      Text(
                        household.landmark!,
                        style: AppType.caption.copyWith(
                          fontSize: 11.5,
                          color: AppColors.inkFaint,
                        ),
                      ),
                  ],
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: Gap.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Gap.sm,
                    vertical: Gap.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.glassFill,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Text(
                    '$count',
                    style: AppType.label.copyWith(fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(width: Gap.sm),
              Tooltip(
                message: 'Start assessment',
                child: Semantics(
                  button: true,
                  label: 'Start assessment',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Gap.radiusSm),
                    onTap: onAssess,
                    child: Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(Gap.radiusSm),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.22),
                        ),
                      ),
                      child: const Icon(
                        Icons.play_circle_outline_rounded,
                        color: AppColors.primary,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Gap.xs),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}
