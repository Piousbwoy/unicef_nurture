import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/glass.dart';
import '../../../domain/engines/immunisation_engine.dart';
import '../../../domain/entities/core.dart';
import '../../../domain/enums.dart';
import '../../../domain/services/caregiver_today_planner.dart';
import '../caregiver_providers.dart';
import '../widgets/companion.dart';
import 'clinic_sections.dart';
import 'preparation.dart';
import 'saved_advice.dart';

class CaregiverCarePlanTab extends ConsumerWidget {
  const CaregiverCarePlanTab({super.key, required this.householdId});
  final String householdId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(caregiverScopeProvider);
    if (scope == null) return const SizedBox.shrink();
    final settings = ref.watch(caregiverSettingsProvider(scope));
    final selected = settings.valueOrNull?.selectedPersonId;
    final now = ref.watch(caregiverCalendarProvider);
    return ref
        .watch(caregiverClinicalProvider(scope))
        .when(
          loading: () => const Text('Loading saved family records…'),
          error: (_, _) => CompanionLoadError(
            onRetry: () => ref.invalidate(caregiverClinicalProvider(scope)),
          ),
          data: (data) {
            final people = data.members
                .where((p) => selected == null || p.id == selected)
                .toList();
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                GlassSurface(
                  tier: GlassTier.hero,
                  blur: false,
                  padding: EdgeInsets.zero,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(GlassTier.hero.radius),
                      gradient: AppColors.caregiverGradient,
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.event_note_rounded,
                                color: Colors.white,
                                size: 32,
                              ),
                              SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  'Next clinic step',
                                  style: TextStyle(
                                    fontFamily: 'Sora',
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 14),
                          Text(
                            'Saved requests from your clinic, followed by advice and your preparation. This app does not book appointments.',
                            style: TextStyle(
                              color: AppColors.white85,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ref
                    .watch(caregiverTodayProvider(scope))
                    .when(
                      loading: () => const Text('Loading clinic steps…'),
                      error: (_, _) => CompanionLoadError(
                        onRetry: () =>
                            ref.invalidate(caregiverTodayProvider(scope)),
                      ),
                      data: (day) {
                        final steps = [...day.attention, ...day.routine]
                            .where(
                              (f) => f.source == CaregiverFocusSource.clinic,
                            )
                            .toList();
                        return Column(
                          children: [
                            if (steps.isEmpty)
                              const CompanionCard(
                                title: 'No open clinic step saved',
                                child: Text(
                                  'This does not mean no care is needed. Check the paper record or contact your health worker.',
                                ),
                              ),
                            for (final step in steps)
                              CompanionCard(
                                title: step.title,
                                eyebrow: step.source.label,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      data.members
                                          .where((p) => p.id == step.personId)
                                          .map(
                                            (p) =>
                                                '${p.fullName} • ${caregiverAge(p)}',
                                          )
                                          .join(),
                                    ),
                                    Text(step.detail),
                                    if (step.dueDate != null)
                                      Text(
                                        "Due: ${DateFormat('d MMM y').format(step.dueDate!)}",
                                      ),
                                    Text(
                                      'Original record: ${caregiverWhen(step.sourceTime)}',
                                    ),
                                    const Text(
                                      'A preparation checkmark or arrival note cannot close this clinic step.',
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                CaregiverPersonSelector(members: data.members),
                const CompanionCard(
                  title: 'Advice from the clinic',
                  child: Text(
                    "Each saved plan keeps its original date. Contact the clinic if advice is unclear or the person's condition changes.",
                  ),
                ),
                if (people.isEmpty)
                  const Text('Add a family member to see their clinic plans.'),
                for (final person in people)
                  Builder(
                    builder: (context) {
                      final records =
                          data.assessments
                              .where((a) => a.personId == person.id)
                              .toList()
                            ..sort(
                              (a, b) => b.performedAt.compareTo(a.performedAt),
                            );
                      return records.isEmpty
                          ? CompanionCard(
                              title: person.fullName,
                              eyebrow: caregiverAge(person),
                              child: const Text(
                                'No clinic advice is saved for this person yet.',
                              ),
                            )
                          : CaregiverSavedAdvice(
                              key: ValueKey(records.first.id),
                              person: person,
                              assessment: records.first,
                            );
                    },
                  ),
                for (final person in people)
                  CaregiverPreparation(person: person),
                CompanionCard(
                  title: 'Digital Yellow Card',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Due by age—check the paper card. Age cannot tell us which doses were received. Past age windows are not completed vaccinations. A health worker must check dose dates and eligibility.',
                      ),
                      for (final child in people.where(
                        (p) =>
                            p.clientType == ClientType.newborn ||
                            p.clientType == ClientType.childUnderFive,
                      ))
                        _AgeSchedule(child: child, now: now),
                    ],
                  ),
                ),
                CaregiverBarrierCard(householdId: householdId),
              ],
            );
          },
        );
  }
}

class _AgeSchedule extends StatelessWidget {
  const _AgeSchedule({required this.child, required this.now});
  final Person child;
  final DateTime now;
  @override
  Widget build(BuildContext context) {
    final dob = child.dateOfBirth;
    if (dob == null || dob.isAfter(now)) {
      return Text(
        '${child.fullName}: confirm the birth date before showing age-based dates.',
      );
    }
    final byWeek = <int, List<String>>{};
    for (final dose in GhanaEpi.schedule) {
      byWeek.putIfAbsent(dose.dueAtWeeks, () => []).add(dose.label);
    }
    return ExpansionTile(
      title: Text(child.fullName),
      subtitle: Text(caregiverAge(child)),
      children: [
        for (final week in byWeek.keys.toList()..sort())
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  week == 0 ? 'Birth' : '$week weeks',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(byWeek[week]!.join(', ')),
                Text(
                  "Age-based date: ${DateFormat('d MMM y').format(dob.add(Duration(days: week * 7)))}${child.isDobEstimated ? ' (estimated)' : ''}",
                ),
                Text(
                  now.isBefore(dob.add(Duration(days: week * 7)))
                      ? 'Future age window — not a booked appointment'
                      : 'Due by age—check the paper card; dose status unknown',
                ),
              ],
            ),
          ),
      ],
    );
  }
}
