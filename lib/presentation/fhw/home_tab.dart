import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/lumen.dart';
import '../../domain/entities/core.dart';
import '../../domain/entities/visit.dart';
import '../../domain/engines/vulnerability_engine.dart';
import '../../domain/enums.dart';
import '../registration/patient_intake_screen.dart';
import 'clinic_widgets.dart';
import 'household_screen.dart';
import 'lumen_hero.dart';
import 'lumen_register.dart';
import 'luxe_motion.dart';
import 'receive_patient_sheet.dart';

final activeClinicSessionProvider = FutureProvider.autoDispose<Visit?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null || !user.can(Permission.runClinicalAssessment)) return null;
  return ref.watch(careRepositoryProvider).resumableVisit(user);
});

/// One open clinic session as the nurse sees it on the queue: whose household,
/// how many people were received, and how many are still awaiting a saved
/// assessment. Arrival order is the visit's own [Visit.startedAt].
class ClinicQueueTicket {
  const ClinicQueueTicket({
    required this.visit,
    required this.householdName,
    required this.presentCount,
    required this.assessedCount,
  });

  final Visit visit;
  final String householdName;
  final int presentCount;
  final int assessedCount;

  int get pending => (presentCount - assessedCount).clamp(0, presentCount);
  bool get allAssessed => presentCount > 0 && pending == 0;
}

/// Every session the nurse has left open right now — the real clinic queue.
/// Several households received under one tree, a routine consult paused while
/// an urgent arrival is pulled forward. Built entirely from existing open
/// [Visit] rows; no new schema.
final clinicQueueProvider = FutureProvider.autoDispose<List<ClinicQueueTicket>>(
  (ref) async {
    final user = ref.watch(currentUserProvider);
    if (user == null || !user.can(Permission.runClinicalAssessment)) {
      return const [];
    }
    final repository = ref.watch(careRepositoryProvider);
    final visits = await repository.openClinicVisits(user);
    final tickets = <ClinicQueueTicket>[];
    for (final visit in visits) {
      final household = await repository.household(user, visit.householdId);
      final roll = await repository.rollCall(user, visit.id);
      var present = 0;
      var assessed = 0;
      for (final p in roll) {
        if (!p.wasPresent) continue;
        present++;
        if (p.assessed) assessed++;
      }
      tickets.add(
        ClinicQueueTicket(
          visit: visit,
          householdName: household?.name ?? 'Household record',
          presentCount: present,
          assessedCount: assessed,
        ),
      );
    }
    return tickets;
  },
);

class FhwHomeTab extends ConsumerWidget {
  const FhwHomeTab({
    super.key,
    required this.onOpenFamilies,
    required this.onOpenQueue,
    this.onOpenReferrals,
    this.onOpenProfile,
  });

  final VoidCallback onOpenFamilies;
  final VoidCallback onOpenQueue;
  final VoidCallback? onOpenReferrals;
  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();
    final plan = ref.watch(dayPlanProvider);
    final referrals = ref.watch(openReferralsProvider);
    final households = ref.watch(visibleHouseholdsProvider);
    final sync = ref.watch(syncStatusProvider);
    final network = ref.watch(connectivityProvider);
    final queue = ref.watch(clinicQueueProvider);
    final urgent = referrals.valueOrNull
        ?.where(
          (r) =>
              r.urgency == ReferralUrgency.immediate ||
              r.urgency == ReferralUrgency.sameDay,
        )
        .toList();

    void refresh() {
      ref.invalidate(dayPlanProvider);
      ref.invalidate(openReferralsProvider);
      ref.invalidate(visibleHouseholdsProvider);
      ref.invalidate(activeClinicSessionProvider);
      ref.invalidate(clinicQueueProvider);
      ref.invalidate(zoneHomeChecksProvider);
      ref.invalidate(dailyRegisterProvider);
      ref.invalidate(syncStatusProvider);
    }

    final pending = sync.valueOrNull?.pending;
    final failures = sync.valueOrNull?.failing;
    final tickets = queue.valueOrNull ?? const <ClinicQueueTicket>[];
    final connection = network.when(
      data: (online) => online ? 'Network available' : 'Working offline',
      error: (_, _) => 'Connection unknown',
      loading: () => 'Checking connection',
    );
    final dueToday = plan.valueOrNull?.dueContacts.length ?? 0;
    final overdue = plan.valueOrNull?.overdueContacts.length ?? 0;
    final peopleWaiting = tickets.fold<int>(0, (sum, t) => sum + t.pending);

    Future<void> receivePatient() async {
      await showReceivePatientSheet(
        context,
        knownHouseholds: households.valueOrNull ?? const [],
      );
      if (context.mounted) refresh();
    }

    return Sanctum(
      focus: const Alignment(0, -0.7),
      child: RefreshIndicator(
        onRefresh: () async => refresh(),
        child: ListView(
          key: const PageStorageKey('fhw-today'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          children: [
            StaggeredEntrance(
              children: [
                LumenHero(
                  dateLabel: DateFormat('EEEE, d MMMM').format(DateTime.now()),
                  zone: user.chpsZone ?? user.community,
                  connectionLabel: connection,
                  pendingSync: pending,
                  syncFailures: failures,
                  householdCount: households.valueOrNull?.length ?? 0,
                  openSessions: tickets.length,
                  peopleWaiting: peopleWaiting,
                  dueToday: dueToday,
                  overdue: overdue,
                  urgentReferrals: urgent?.length ?? 0,
                  onReceive: receivePatient,
                  onResume: onOpenQueue,
                  onFollowThrough: onOpenReferrals ?? onOpenQueue,
                  onSync: onOpenProfile ?? onOpenFamilies,
                ),
                const SizedBox(height: 12),
                if (queue.isLoading)
                  const LinearProgressIndicator(minHeight: 2)
                else if (queue.hasError)
                  ClinicStatusLine(
                    text: 'Open sessions could not be checked. Tap to retry.',
                    icon: Icons.refresh_rounded,
                    onTap: () => ref.invalidate(clinicQueueProvider),
                  ),
                if (tickets.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  // The register: the day's open sessions on a carved ledger.
                  // Honest progress only — assessed of received — never a triage
                  // guess.
                  LumenRegister(tickets: tickets, onOpenQueue: onOpenQueue),
                ],
              ],
            ),
            if (plan.hasError || referrals.hasError || households.hasError) ...[
              const SizedBox(height: 12),
              ClinicStatusLine(
                text: 'Some records could not be loaded. Tap to retry.',
                icon: Icons.refresh_rounded,
                onTap: refresh,
              ),
            ],
            const SizedBox(height: 28),
            const _DailyRegisterTally(),
            plan.maybeWhen(
              data: (data) {
                final priority = data.priorities
                    .where(
                      (p) =>
                          p.band == VulnerabilityBand.critical ||
                          p.band == VulnerabilityBand.high,
                    )
                    .take(3)
                    .toList();
                if (priority.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: LumenCard(
                    title: 'Bring these records forward',
                    subtitle:
                        'Priorities from saved records—not a diagnosis of who is unwell now.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final item in priority)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              item.household.name,
                              style: AppType.label,
                            ),
                            subtitle: Text(item.reason, style: AppType.caption),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => HouseholdScreen(
                                  householdId: item.household.id,
                                ),
                              ),
                            ),
                          ),
                        TextButton(
                          onPressed: onOpenQueue,
                          child: const Text('Open care reviews'),
                        ),
                      ],
                    ),
                  ),
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),
            const _FamilyReports(),
            const SizedBox(height: 10),
            // The way into search reuses the hero's magnetic capsule, so the
            // whole page shares one tactile language: it draws inward on the
            // press and settles. The label is unchanged.
            MagneticCapsule(
              radius: Gap.radius,
              onTap: onOpenFamilies,
              child: SizedBox(
                height: Gap.tapTarget,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        size: 19,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          'Find a patient or household',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.label.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'This workspace shows records available on this phone. A quiet list does not rule out urgent care needs.',
              style: TextStyle(
                color: AppColors.inkMuted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The day's register columns, counted from the records this worker saved on
/// this phone. Nothing is captured for this card that the assessments and
/// referrals do not already record.
///
/// Hides itself while loading and on a day with no records yet: a card of
/// zeroes on a quiet morning reads as a broken device rather than as an honest
/// empty day.
class _DailyRegisterTally extends ConsumerWidget {
  const _DailyRegisterTally();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tally = ref.watch(dailyRegisterProvider);
    return tally.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: ClinicStatusLine(
          text: 'Today’s tally could not be counted. Tap to retry.',
          icon: Icons.refresh_rounded,
          onTap: () => ref.invalidate(dailyRegisterProvider),
        ),
      ),
      data: (day) => day.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: LumenCard(
                title: 'Today’s tally',
                subtitle:
                    'Counted from records you saved on this phone today. Each '
                    'child counts once, however often they were seen.',
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow =
                        constraints.maxWidth < 300 ||
                        MediaQuery.textScalerOf(context).scale(12) > 18;
                    final width = narrow
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 16) / 2;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 2,
                      children: [
                        for (final cell in [
                          _TallyCell(
                            value: '${day.childrenSeen}',
                            label: 'Under-5 seen',
                          ),
                          _TallyCell(
                            // The denominator is the honest half: five
                            // positives out of five tested and five out of
                            // forty are different days.
                            value: day.rdtDone == 0
                                ? '—'
                                : '${day.rdtPositive}/${day.rdtDone}',
                            label: 'RDT positive / tested',
                          ),
                          _TallyCell(
                            value: '${day.sam}',
                            label: 'SAM (severe)',
                            tone: AppColors.triageRed,
                          ),
                          _TallyCell(
                            value: '${day.mam}',
                            label: 'MAM (moderate)',
                            tone: AppColors.triageAmber,
                          ),
                          _TallyCell(
                            value: '${day.immunised}',
                            label: 'Immunisations given',
                          ),
                          _TallyCell(
                            value: '${day.referralsIssued}',
                            label: 'Referrals issued',
                          ),
                        ])
                          SizedBox(width: width, child: cell),
                      ],
                    );
                  },
                ),
              ),
            ),
    );
  }
}

class _TallyCell extends StatelessWidget {
  const _TallyCell({required this.value, required this.label, this.tone});

  final String value;
  final String label;
  final Color? tone;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // The figure is carved sapphire — structural light, not painted ink —
        // scaled down inside a fixed well so a wide numerator or the 200% text
        // floor can never overflow the ledger column.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 78),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: tone == null
                ? Monolith(value: value, fontSize: 27, pearled: true)
                : Monolith(
                    value: value,
                    fontSize: 27,
                    pearled: false,
                    tone: tone!,
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: AppType.caption.copyWith(
              fontSize: 12,
              color: AppColors.inkMuted,
            ),
          ),
        ),
      ],
    ),
  );
}

class _FamilyReports extends ConsumerWidget {
  const _FamilyReports();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checks = ref.watch(zoneHomeChecksProvider);
    return checks.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => ClinicStatusLine(
        text: 'Family reports could not be loaded. Tap to retry.',
        onTap: () => ref.invalidate(zoneHomeChecksProvider),
      ),
      data: (reports) => reports.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: LumenCard(
                title: 'What families reported',
                subtitle:
                    'Home checks on this shared phone. Reported observations, not clinical examinations.',
                child: Column(
                  children: [for (final report in reports) _ReportRow(report)],
                ),
              ),
            ),
    );
  }
}

class _ReportRow extends ConsumerWidget {
  const _ReportRow(this.report);
  final HomeCheck report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = ref.watch(personProvider(report.personId));
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.description_outlined,
        color: report.verdict == HomeCheckVerdict.urgent
            ? AppColors.triageRed
            : AppColors.primary,
      ),
      title: Text(
        person.valueOrNull?.fullName ?? 'Open household record',
        style: AppType.label,
      ),
      subtitle: Text(
        '${report.verdict.label} · ${DateFormat('d MMM, HH:mm').format(report.checkedAt)}',
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => HouseholdScreen(householdId: report.householdId),
        ),
      ),
    );
  }
}

Future<void> openVisit(BuildContext context, Household household) async {
  await Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => PatientIntakeScreen(
        initialHousehold: household,
        knownHouseholds: [household],
      ),
    ),
  );
}

class HouseholdPicker extends StatefulWidget {
  const HouseholdPicker({super.key, required this.list});
  final List<Household> list;
  @override
  State<HouseholdPicker> createState() => _HouseholdPickerState();
}

class _HouseholdPickerState extends State<HouseholdPicker> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final filtered = widget.list
        .where(
          (h) =>
              '${h.name} ${h.headName ?? ''} ${h.community} ${h.landmark ?? ''}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Choose a household', style: AppType.title),
              const SizedBox(height: 12),
              TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Name, community or landmark',
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('No matching household'))
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, i) => ListTile(
                          title: Text(filtered[i].name),
                          subtitle: Text(filtered[i].community),
                          onTap: () => Navigator.of(context).pop(filtered[i]),
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
