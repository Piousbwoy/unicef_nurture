import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/fhw_luxe.dart';
import '../../core/theme/lumen.dart';
import '../../domain/entities/core.dart';
import '../../domain/entities/visit.dart';
import '../../domain/engines/vulnerability_engine.dart';
import '../../domain/enums.dart';
import '../registration/patient_intake_screen.dart';
import 'clinic_widgets.dart';
import 'household_screen.dart';

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
    final queue = ref.watch(clinicQueueProvider);

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

    return RefreshIndicator(
      onRefresh: () async => refresh(),
      child: ListView(
        key: const PageStorageKey('fhw-today'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: [
          // The header now carries the live queue and the sync readout, so the
          // body opens with what the day has actually produced. A failed queue
          // check still surfaces here — the honest way to retry it.
          if (queue.hasError)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ClinicStatusLine(
                text: 'Open sessions could not be checked. Tap to retry.',
                icon: Icons.refresh_rounded,
                onTap: () => ref.invalidate(clinicQueueProvider),
              ),
            ),
          if (plan.hasError || referrals.hasError || households.hasError)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ClinicStatusLine(
                text: 'Some records could not be loaded. Tap to retry.',
                icon: Icons.refresh_rounded,
                onTap: refresh,
              ),
            ),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionSpine('From saved records'),
                    LumenCard(
                      title: 'Bring these records forward',
                      subtitle:
                          'Priorities from saved records—not a diagnosis of who is unwell now.',
                      count: priority.length,
                      // The one card on the desk you are meant to act on wears
                      // the electric rail; every other panel stays plain
                      // lacquer, so the accent alone carries the hierarchy.
                      accent: FhwLuxePalette.sapphireElectric,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          RuledColumn(
                            rule: Colors.white.withValues(alpha: 0.12),
                            children: [
                              for (final item in priority)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    item.household.name,
                                    style: AppType.label.copyWith(
                                      color: Colors.white,
                                    ),
                                  ),
                                  subtitle: Text(
                                    item.reason,
                                    style: AppType.caption.copyWith(
                                      color: FhwLuxePalette.lacquerInk,
                                    ),
                                  ),
                                  trailing: const Icon(
                                    Icons.chevron_right_rounded,
                                    color: Colors.white70,
                                  ),
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => HouseholdScreen(
                                        householdId: item.household.id,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          TextButton(
                            onPressed: onOpenQueue,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Open care reviews'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
          const _FamilyReports(),
          const SizedBox(height: 10),
          // The way into search, finished in the desk's own material: the same
          // hairline edge and soft drop the porcelain cards carry, with the
          // glyph seated in sapphire ice. On a white canvas a bare outline reads
          // as an unfinished input; this reads as an instrument on the desk.
          // The label is unchanged.
          Container(
            decoration: BoxDecoration(
              color: FhwLuxePalette.cardSurface,
              borderRadius: BorderRadius.circular(Gap.radiusSm),
              border: Border.all(color: FhwLuxePalette.hairLine),
              boxShadow: Chiaroscuro.alabaster,
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(Gap.radiusSm),
              child: InkWell(
                onTap: onOpenFamilies,
                borderRadius: BorderRadius.circular(Gap.radiusSm),
                child: Container(
                  height: Gap.tapTarget,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: FhwLuxePalette.sapphireIce,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(
                          Icons.search_rounded,
                          size: 17,
                          color: FhwLuxePalette.sapphireRoyal,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Find a patient or household',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.label.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: FhwLuxePalette.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: FhwLuxePalette.textFaint,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // The desk's own caveat, set in the system's caption voice rather than
          // a bare TextStyle, and inset to sit on the card's text column.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              'This workspace shows records available on this phone. A quiet list does not rule out urgent care needs.',
              style: AppType.caption.copyWith(
                color: FhwLuxePalette.textSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionSpine('Recorded today'),
                  LumenCard(
                    title: 'Today’s tally',
                    subtitle:
                        'Counted from records you saved on this phone today. Each '
                        'child counts once, however often they were seen.',
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final narrow =
                            constraints.maxWidth < 320 ||
                            MediaQuery.textScalerOf(context).scale(12) > 18;
                        final cells = [
                          _TallyStat(
                            value: '${day.childrenSeen}',
                            label: 'Under-5 seen',
                          ),
                          _TallyStat(
                            // The denominator is the honest half: five
                            // positives out of five tested and five out of
                            // forty are different days.
                            value: day.rdtDone == 0
                                ? '—'
                                : '${day.rdtPositive}/${day.rdtDone}',
                            label: 'RDT positive / tested',
                          ),
                          _TallyStat(
                            value: '${day.sam}',
                            label: 'SAM (severe)',
                            tone: AppColors.triageRed,
                          ),
                          _TallyStat(
                            value: '${day.mam}',
                            label: 'MAM (moderate)',
                            tone: AppColors.triageAmber,
                          ),
                          _TallyStat(
                            value: '${day.immunised}',
                            label: 'Immunisations given',
                          ),
                          _TallyStat(
                            value: '${day.referralsIssued}',
                            label: 'Referrals issued',
                          ),
                        ];
                        // A tally sheet reads as a table, not a wall of big
                        // numbers: two aligned columns of quiet figures divided
                        // by hairlines. On a narrow phone or at the 200% text
                        // floor it folds to a single ruled column.
                        if (narrow) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var i = 0; i < cells.length; i++) ...[
                                if (i > 0) const _TallyRule(),
                                cells[i],
                              ],
                            ],
                          );
                        }
                        return Column(
                          children: [
                            for (var r = 0; r < 3; r++) ...[
                              if (r > 0) const _TallyRule(),
                              IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(child: cells[r * 2]),
                                    const _TallyVRule(),
                                    Expanded(child: cells[r * 2 + 1]),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// One figure in the tally table: a quiet tabular number over its label, with
/// a small clinical swatch when the column is a nutrition verdict (SAM / MAM).
/// The hue marks the class of measure; it never recolours the figure.
class _TallyStat extends StatelessWidget {
  const _TallyStat({required this.value, required this.label, this.tone});

  final String value;
  final String label;
  final Color? tone;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Scaled down inside a fixed ceiling so a wide numerator ('3/5') or the
        // 200% text floor can never overflow the column.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 132),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppType.numeral.copyWith(
                fontSize: 26,
                height: 1.0,
                letterSpacing: -0.6,
                color: Colors.white,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            if (tone != null) ...[
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: tone,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 7),
            ],
            Expanded(
              child: Text(
                label,
                style: AppType.caption.copyWith(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: FhwLuxePalette.lacquerInk,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// A hairline between tally rows.
class _TallyRule extends StatelessWidget {
  const _TallyRule();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 1,
    child: DecoratedBox(decoration: BoxDecoration(color: Color(0x1FFFFFFF))),
  );
}

/// A hairline between the two tally columns, stretched to the row height by the
/// enclosing [IntrinsicHeight].
class _TallyVRule extends StatelessWidget {
  const _TallyVRule();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 1,
    child: DecoratedBox(decoration: BoxDecoration(color: Color(0x1FFFFFFF))),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionSpine('Reported at home'),
                  LumenCard(
                    title: 'What families reported',
                    subtitle:
                        'Home checks on this shared phone. Reported observations, not clinical examinations.',
                    count: reports.length,
                    child: RuledColumn(
                      rule: Colors.white.withValues(alpha: 0.12),
                      children: [
                        for (final report in reports) _ReportRow(report),
                      ],
                    ),
                  ),
                ],
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
    final urgent = report.verdict == HomeCheckVerdict.urgent;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      // On the lacquer panel a quiet report sits in a glass well with a white
      // glyph; an urgent report keeps the true triage red on a soft red well,
      // so the clinical verdict is still the only colour that raises its voice.
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: urgent
              ? FhwLuxePalette.clinicalRed.withValues(alpha: 0.28)
              : Colors.white.withValues(alpha: 0.16),
        ),
        child: Icon(
          Icons.description_outlined,
          size: 17,
          color: urgent ? AppColors.triageRed : Colors.white,
        ),
      ),
      title: Text(
        person.valueOrNull?.fullName ?? 'Open household record',
        style: AppType.label.copyWith(color: Colors.white),
      ),
      subtitle: Text(
        '${report.verdict.label} · ${DateFormat('d MMM, HH:mm').format(report.checkedAt)}',
        style: AppType.caption.copyWith(color: FhwLuxePalette.lacquerInk),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white70),
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
