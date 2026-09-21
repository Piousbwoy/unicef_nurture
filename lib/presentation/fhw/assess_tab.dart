import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/core.dart';
import '../../domain/enums.dart';
import '../shared/ui.dart';
import '../visit/roll_call_screen.dart';
import 'clinic_widgets.dart';
import 'families_tab.dart';
import 'home_tab.dart';
import 'household_screen.dart';
import 'receive_patient_sheet.dart';

final clinicPeopleProvider =
    FutureProvider.autoDispose<Map<String, List<Person>>>((ref) async {
      final user = ref.watch(currentUserProvider);
      if (user == null || !user.can(Permission.runClinicalAssessment)) {
        return const {};
      }
      await ref.watch(visibleHouseholdsProvider.future);
      return ref.watch(careRepositoryProvider).visibleHouseholdMembers(user);
    });

enum _PatientGroup { all, maternal, children }

class AssessTab extends ConsumerStatefulWidget {
  const AssessTab({super.key});
  @override
  ConsumerState<AssessTab> createState() => _AssessTabState();
}

class _AssessTabState extends ConsumerState<AssessTab> {
  final _search = TextEditingController();
  _PatientGroup _group = _PatientGroup.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(visibleHouseholdsProvider);
    ref.invalidate(clinicPeopleProvider);
    ref.invalidate(dayPlanProvider);
    ref.invalidate(activeClinicSessionProvider);
    ref.invalidate(clinicQueueProvider);
  }

  bool _inGroup(Person person) => switch (_group) {
    _PatientGroup.all => true,
    _PatientGroup.maternal =>
      person.effectiveClientType == ClientType.pregnantWoman ||
          person.effectiveClientType == ClientType.postpartumWoman ||
          person.effectiveClientType == ClientType.womanOfReproductiveAge,
    _PatientGroup.children =>
      person.effectiveClientType == ClientType.newborn ||
          person.effectiveClientType == ClientType.childUnderFive,
  };

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();
    if (!user.can(Permission.runClinicalAssessment)) {
      return const EmptyState(
        icon: Icons.verified_user_outlined,
        title: 'Assessments restricted',
        message:
            'Sign in with a health-worker account to run a clinical assessment.',
      );
    }
    final households = ref.watch(visibleHouseholdsProvider);
    final people = ref.watch(clinicPeopleProvider);
    // Households already received with someone still to assess — the living
    // queue, surfaced right where the nurse is about to search, so a paused
    // consult is one tap away instead of something to remember.
    final waiting = (
          ref.watch(clinicQueueProvider).valueOrNull ?? const <ClinicQueueTicket>[]
      )
      .where((t) => t.pending > 0)
      .toList();
    final query = _search.text.trim().toLowerCase();
    final list = households.valueOrNull ?? const <Household>[];
    final filtered = list.where((household) {
      final members = people.valueOrNull?[household.id] ?? const <Person>[];
      final matchingMembers = members.where(_inGroup);
      if (_group != _PatientGroup.all && matchingMembers.isEmpty) return false;
      final text =
          '${household.name} ${household.headName ?? ''} ${household.community} '
          '${household.landmark ?? ''} ${household.contactPhone ?? ''} '
          '${matchingMembers.map((p) => p.fullName).join(' ')}';
      return text.toLowerCase().contains(query);
    }).toList();

    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: CustomScrollView(
        key: const PageStorageKey('fhw-patients'),
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'The person in front of you.',
                    style: AppType.headline.copyWith(fontSize: 24),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Find their record before adding a new one. People stay linked to their household.',
                    style: AppType.body.copyWith(
                      fontSize: 13,
                      color: AppColors.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.checkNavy,
                    ),
                    cursorColor: AppColors.checkBlue,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      labelText: 'Find patient or household',
                      labelStyle: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkMuted,
                      ),
                      floatingLabelStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.checkBlue,
                      ),
                      hintText: 'Name, phone, community or landmark',
                      hintStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.inkFaint,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 15,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppColors.checkBlue,
                      ),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () => setState(_search.clear),
                              icon: const Icon(
                                Icons.cancel_rounded,
                                size: 20,
                                color: AppColors.inkFaint,
                              ),
                            ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: AppColors.checkNavy.withValues(alpha: 0.16),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: AppColors.checkBlue,
                          width: 1.6,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (waiting.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Waiting now',
                            style: AppType.label.copyWith(
                              fontSize: 12,
                              color: AppColors.brassDeep,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final ticket in waiting)
                                _WaitingChip(
                                  name: ticket.householdName,
                                  onTap: () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => RollCallScreen(
                                          householdId: ticket.visit.householdId,
                                        ),
                                      ),
                                    );
                                    if (mounted) _refresh();
                                  },
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final group in _PatientGroup.values)
                        ChoiceChip(
                          selected: _group == group,
                          label: Text(switch (group) {
                            _PatientGroup.all => 'All',
                            _PatientGroup.maternal => 'Maternal care',
                            _PatientGroup.children => 'Child care',
                          }),
                          onSelected: (_) => setState(() => _group = group),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _startAssessment,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Receive a patient'),
                  ),
                  TextButton.icon(
                    onPressed: _registerHousehold,
                    icon: const Icon(Icons.add_home_outlined, size: 20),
                    label: const Text('Register a new household'),
                  ),
                  const SizedBox(height: 8),
                  if (households.isLoading || people.isLoading)
                    const LinearProgressIndicator(minHeight: 2),
                  if (households.hasError)
                    ClinicStatusLine(
                      text:
                          'Household records could not be loaded. Tap to retry.',
                      onTap: _refresh,
                    )
                  else if (people.hasError)
                    ClinicStatusLine(
                      text:
                          'Patient names could not be loaded. Household search is still available. Tap to retry.',
                      onTap: () => ref.invalidate(clinicPeopleProvider),
                    )
                  else
                    Text(
                      '${filtered.length} household${filtered.length == 1 ? '' : 's'} · records on this phone',
                      style: AppType.caption.copyWith(
                        color: AppColors.inkMuted,
                      ),
                    ),
                  const SizedBox(height: 14),
                ],
              ),
            ),
          ),
          if (filtered.isEmpty && !households.isLoading && !people.isLoading)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(
                child: ClinicCard(
                  title: list.isEmpty
                      ? 'No household records yet'
                      : 'No matching records',
                  child: Text(
                    list.isEmpty
                        ? 'Register a household to begin. Registration and clinical assessments work offline.'
                        : 'Try another name, clear the care filter, or check the community before registering again.',
                    style: AppType.body.copyWith(fontSize: 14),
                  ),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            sliver: SliverList.builder(
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final household = filtered[i];
                final members = people.valueOrNull?[household.id];
                final named = (members ?? const <Person>[])
                    .where(
                      (p) =>
                          _inGroup(p) &&
                          (query.isEmpty ||
                              p.fullName.toLowerCase().contains(query)),
                    )
                    .toList();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: ClinicCard(
                    title: household.name,
                    subtitle: '${household.community} · ${household.district}',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (named.isNotEmpty) ...[
                          Text(
                            named.map((p) => p.fullName).join(' · '),
                            style: AppType.label.copyWith(fontSize: 13),
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (household.landmark?.isNotEmpty == true)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              household.landmark!,
                              style: AppType.caption,
                            ),
                          ),
                        Text(
                          members == null
                              ? 'Patient list unavailable'
                              : '${members.length} registered ${members.length == 1 ? 'person' : 'people'}',
                          style: AppType.caption,
                        ),
                        const SizedBox(height: 14),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final record = OutlinedButton(
                              onPressed: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => HouseholdScreen(
                                      householdId: household.id,
                                    ),
                                  ),
                                );
                                if (mounted) _refresh();
                              },
                              child: const Text('Open record'),
                            );
                            final assess = FilledButton.icon(
                              onPressed: () async {
                                await openVisit(context, household);
                                if (mounted) _refresh();
                              },
                              icon: const Icon(
                                Icons.arrow_forward_rounded,
                                size: 18,
                              ),
                              label: const Text('Assess'),
                            );
                            return constraints.maxWidth < 270 ||
                                    MediaQuery.textScalerOf(context).scale(14) >
                                        21
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      assess,
                                      const SizedBox(height: 8),
                                      record,
                                    ],
                                  )
                                : Row(
                                    children: [
                                      Expanded(child: record),
                                      const SizedBox(width: 10),
                                      Expanded(child: assess),
                                    ],
                                  );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startAssessment() async {
    await showReceivePatientSheet(
      context,
      knownHouseholds:
          ref.read(visibleHouseholdsProvider).valueOrNull ?? const [],
    );
    if (mounted) _refresh();
  }

  Future<void> _registerHousehold() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const HouseholdFormSheet(),
    );
    if (created == true && mounted) _refresh();
  }
}

/// A brass-edged pill for one household already waiting in the clinic queue.
/// Brass is chrome — it marks a pending consult, never a clinical status.
class _WaitingChip extends StatelessWidget {
  const _WaitingChip({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brassLight,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.brass.withValues(alpha: 0.6)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.schedule_rounded, size: 15, color: AppColors.brassDeep),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label.copyWith(
                    fontSize: 13,
                    color: AppColors.brassDeep,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
