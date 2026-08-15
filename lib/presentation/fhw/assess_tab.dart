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

        // The relocated register: the exact search + browse the Families tab
        // had, now pinned under the assessment launch point.
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.sm),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Search name, head of household, community, or landmark',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Gap.radius),
              ),
            ),
          ),
        ),

        Expanded(
          child: households.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(
              error: e is AccessDenied ? e.message : e,
            ),
            data: (list) {
              final q = _search.text.trim().toLowerCase();
              final filtered = q.isEmpty
                  ? list
                  : list
                        .where(
                          (h) =>
                              h.name.toLowerCase().contains(q) ||
                              (h.headName?.toLowerCase().contains(q) ?? false) ||
                              h.community.toLowerCase().contains(q) ||
                              (h.landmark?.toLowerCase().contains(q) ?? false),
                        )
                        .toList(growable: false);

              if (filtered.isEmpty) {
                return EmptyState(
                  icon: Icons.search_off_rounded,
                  title: q.isEmpty ? 'No families yet' : 'No match',
                  message: q.isEmpty
                      ? 'Register the first household to begin the register.'
                      : 'Nothing matches "$q". Try a name, the head of the '
                            'household, or the landmark.',
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(Gap.lg),
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final household = filtered[i];
                  return HouseholdTile(
                    household: household,
                    onTap: () => _open(household.id),
                    // The permission gate above means everyone who reaches
                    // this list can assess, so every row carries the shortcut.
                    onAssess: () => openVisit(context, household),
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
      MaterialPageRoute(builder: (_) => HouseholdScreen(householdId: id)),
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
}
