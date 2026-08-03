/// Ghana Expanded Programme on Immunisation (EPI) schedule, with a catch-up
/// planner that does what a paper card cannot.
///
/// The problem this solves is mundane and enormous: a CHO holding a child's
/// weighing card has to work out, mentally, which of about twenty doses are due
/// or overdue today, honouring minimum intervals. Under time pressure, in a
/// queue, this is where missed opportunities come from — and a missed
/// opportunity is the commonest reason a child in a rural district ends up
/// under-immunised.
///
/// The engine states, for any child on any day: what is due, what is overdue and
/// by how long, what can be given *today in the same session*, and what must
/// wait — and why.
library;

import 'package:collection/collection.dart';

import '../enums.dart';
import '../entities/visit.dart';

/// A scheduled antigen dose in the Ghana EPI schedule.
class VaccineDose {
  const VaccineDose({
    required this.antigen,
    required this.doseNumber,
    required this.dueAtWeeks,
    required this.protectsAgainst,
    this.maxAgeWeeks,
    this.minIntervalWeeks,
    this.notes,
  });

  /// "Penta", "OPV", "MR", "PCV", "Rota", "BCG", "IPV", "MenA", "Malaria".
  final String antigen;
  final int doseNumber;

  /// Age in completed weeks at which this dose becomes due. 0 = at birth.
  final int dueAtWeeks;

  final String protectsAgainst;

  /// Some antigens cannot be started after a certain age — rotavirus in
  /// particular, because of the intussusception risk.
  final int? maxAgeWeeks;

  /// Minimum gap from the previous dose of the same antigen.
  final int? minIntervalWeeks;

  final String? notes;

  String get label => doseNumber == 0
      ? antigen
      : '$antigen $doseNumber';
}

/// A single line in the catch-up plan.
class ImmunisationItem {
  const ImmunisationItem({
    required this.dose,
    required this.status,
    required this.detail,
    this.weeksOverdue = 0,
  });

  final VaccineDose dose;
  final ImmunisationStatus status;
  final String detail;
  final int weeksOverdue;
}

enum ImmunisationStatus {
  given('Given'),
  dueToday('Due today'),
  overdue('Overdue'),
  notYetDue('Not yet due'),
  ageBarred('Too old — cannot be given');

  const ImmunisationStatus(this.label);
  final String label;
}

class ImmunisationPlan {
  const ImmunisationPlan({
    required this.items,
    required this.giveToday,
    required this.overdue,
    required this.summary,
    required this.isFullyUpToDate,
    this.nextDueInDays,
    this.nextDueLabel,
  });

  final List<ImmunisationItem> items;

  /// Doses that can and should be given in this session.
  final List<VaccineDose> giveToday;

  final List<ImmunisationItem> overdue;

  final String summary;
  final bool isFullyUpToDate;
  final int? nextDueInDays;
  final String? nextDueLabel;

  List<String> get overdueLabels =>
      overdue.map((o) => o.dose.label).toList(growable: false);
}

abstract final class GhanaEpi {
  /// The national childhood schedule. Weeks are used throughout rather than
  /// months, because EPI intervals are defined in weeks and mixing the two units
  /// is how off-by-a-fortnight errors get made.
  static const List<VaccineDose> schedule = [
    VaccineDose(
      antigen: 'BCG',
      doseNumber: 0,
      dueAtWeeks: 0,
      protectsAgainst: 'Tuberculosis, especially TB meningitis',
      notes: 'At birth or first contact. Still give up to 12 months if missed.',
    ),
    VaccineDose(
      antigen: 'OPV',
      doseNumber: 0,
      dueAtWeeks: 0,
      protectsAgainst: 'Polio',
      maxAgeWeeks: 2,
      notes: 'Birth dose. Only counts if given within the first 14 days.',
    ),
    VaccineDose(
      antigen: 'Penta',
      doseNumber: 1,
      dueAtWeeks: 6,
      protectsAgainst:
          'Diphtheria, tetanus, whooping cough, hepatitis B, Hib meningitis',
    ),
    VaccineDose(
      antigen: 'OPV',
      doseNumber: 1,
      dueAtWeeks: 6,
      protectsAgainst: 'Polio',
    ),
    VaccineDose(
      antigen: 'PCV',
      doseNumber: 1,
      dueAtWeeks: 6,
      protectsAgainst: 'Pneumococcal pneumonia and meningitis',
    ),
    VaccineDose(
      antigen: 'Rota',
      doseNumber: 1,
      dueAtWeeks: 6,
      protectsAgainst: 'Rotavirus diarrhoea',
      maxAgeWeeks: 15,
      notes: 'Cannot be started after 15 weeks of age.',
    ),
    VaccineDose(
      antigen: 'Penta',
      doseNumber: 2,
      dueAtWeeks: 10,
      protectsAgainst:
          'Diphtheria, tetanus, whooping cough, hepatitis B, Hib meningitis',
      minIntervalWeeks: 4,
    ),
    VaccineDose(
      antigen: 'OPV',
      doseNumber: 2,
      dueAtWeeks: 10,
      protectsAgainst: 'Polio',
      minIntervalWeeks: 4,
    ),
    VaccineDose(
      antigen: 'PCV',
      doseNumber: 2,
      dueAtWeeks: 10,
      protectsAgainst: 'Pneumococcal pneumonia and meningitis',
      minIntervalWeeks: 4,
    ),
    VaccineDose(
      antigen: 'Rota',
      doseNumber: 2,
      dueAtWeeks: 10,
      protectsAgainst: 'Rotavirus diarrhoea',
      maxAgeWeeks: 32,
      minIntervalWeeks: 4,
      notes: 'Last dose must be given by 32 weeks of age.',
    ),
    VaccineDose(
      antigen: 'Penta',
      doseNumber: 3,
      dueAtWeeks: 14,
      protectsAgainst:
          'Diphtheria, tetanus, whooping cough, hepatitis B, Hib meningitis',
      minIntervalWeeks: 4,
    ),
    VaccineDose(
      antigen: 'OPV',
      doseNumber: 3,
      dueAtWeeks: 14,
      protectsAgainst: 'Polio',
      minIntervalWeeks: 4,
    ),
    VaccineDose(
      antigen: 'PCV',
      doseNumber: 3,
      dueAtWeeks: 14,
      protectsAgainst: 'Pneumococcal pneumonia and meningitis',
      minIntervalWeeks: 4,
    ),
    VaccineDose(
      antigen: 'IPV',
      doseNumber: 1,
      dueAtWeeks: 14,
      protectsAgainst: 'Polio — injectable dose, given alongside OPV 3',
    ),
    VaccineDose(
      antigen: 'Malaria',
      doseNumber: 1,
      dueAtWeeks: 26,
      protectsAgainst: 'Malaria',
      notes: 'Malaria vaccine, first dose at about 6 months.',
    ),
    VaccineDose(
      antigen: 'Malaria',
      doseNumber: 2,
      dueAtWeeks: 30,
      protectsAgainst: 'Malaria',
      minIntervalWeeks: 4,
    ),
    VaccineDose(
      antigen: 'MR',
      doseNumber: 1,
      dueAtWeeks: 39,
      protectsAgainst: 'Measles and rubella',
      notes: 'At 9 months. Measles kills malnourished children fastest.',
    ),
    VaccineDose(
      antigen: 'Yellow Fever',
      doseNumber: 1,
      dueAtWeeks: 39,
      protectsAgainst: 'Yellow fever',
    ),
    VaccineDose(
      antigen: 'Malaria',
      doseNumber: 3,
      dueAtWeeks: 39,
      protectsAgainst: 'Malaria',
      minIntervalWeeks: 4,
    ),
    VaccineDose(
      antigen: 'MR',
      doseNumber: 2,
      dueAtWeeks: 78,
      protectsAgainst: 'Measles and rubella',
      minIntervalWeeks: 4,
      notes: 'At 18 months. The dose most often missed, because the child is '
          'past the weighing-card habit.',
    ),
    VaccineDose(
      antigen: 'MenA',
      doseNumber: 1,
      dueAtWeeks: 78,
      protectsAgainst: 'Meningitis A — the northern meningitis belt',
      notes: 'At 18 months. All five northern regions sit in the belt.',
    ),
    VaccineDose(
      antigen: 'Malaria',
      doseNumber: 4,
      dueAtWeeks: 78,
      protectsAgainst: 'Malaria',
      minIntervalWeeks: 4,
    ),
  ];
}

abstract final class ImmunisationEngine {
  /// A dose is considered overdue once this many weeks have passed beyond its
  /// due age. Four weeks is the operational grace period used in practice.
  static const int _graceWeeks = 4;

  /// [givenLabels] holds labels of doses already received, e.g. `{'Penta 1',
  /// 'OPV 1', 'BCG'}` — matching [VaccineDose.label].
  static ImmunisationPlan plan({
    required int ageInDays,
    required Set<String> givenLabels,
  }) {
    final ageWeeks = ageInDays ~/ 7;
    final items = <ImmunisationItem>[];
    final giveToday = <VaccineDose>[];
    final overdue = <ImmunisationItem>[];

    for (final dose in GhanaEpi.schedule) {
      if (givenLabels.contains(dose.label)) {
        items.add(
          ImmunisationItem(
            dose: dose,
            status: ImmunisationStatus.given,
            detail: 'Already given.',
          ),
        );
        continue;
      }

      // Age-barred antigens: rotavirus and the OPV birth dose.
      if (dose.maxAgeWeeks != null && ageWeeks > dose.maxAgeWeeks!) {
        items.add(
          ImmunisationItem(
            dose: dose,
            status: ImmunisationStatus.ageBarred,
            detail: dose.antigen == 'Rota'
                ? 'The child is now $ageWeeks weeks old, past the '
                      '${dose.maxAgeWeeks}-week limit. Rotavirus vaccine must not '
                      'be given late. Counsel on ORS and zinc for diarrhoea '
                      'instead, and on hand washing.'
                : 'Past the ${dose.maxAgeWeeks}-week window for this dose. Move '
                      'on to the next dose in the series.',
          ),
        );
        continue;
      }

      if (ageWeeks < dose.dueAtWeeks) {
        items.add(
          ImmunisationItem(
            dose: dose,
            status: ImmunisationStatus.notYetDue,
            detail:
                'Due at ${_weeksLabel(dose.dueAtWeeks)} — in '
                '${dose.dueAtWeeks - ageWeeks} weeks.',
          ),
        );
        continue;
      }

      // Due or overdue. Check the minimum interval from the previous dose of
      // the same antigen, since giving a catch-up dose too soon wastes it.
      final previousMissing = dose.doseNumber > 1 &&
          !givenLabels.contains('${dose.antigen} ${dose.doseNumber - 1}');

      final weeksLate = ageWeeks - dose.dueAtWeeks;

      if (previousMissing) {
        items.add(
          ImmunisationItem(
            dose: dose,
            status: ImmunisationStatus.overdue,
            weeksOverdue: weeksLate,
            detail:
                '${dose.antigen} ${dose.doseNumber - 1} has not been given, so '
                'give that first today. This dose follows at least '
                '${dose.minIntervalWeeks ?? 4} weeks later.',
          ),
        );
        overdue.add(items.last);
        continue;
      }

      if (weeksLate > _graceWeeks) {
        final item = ImmunisationItem(
          dose: dose,
          status: ImmunisationStatus.overdue,
          weeksOverdue: weeksLate,
          detail:
              '${dose.label} was due at ${_weeksLabel(dose.dueAtWeeks)} and is '
              '$weeksLate weeks overdue. Give it today. '
              '${dose.protectsAgainst}.',
        );
        items.add(item);
        overdue.add(item);
        giveToday.add(dose);
      } else {
        items.add(
          ImmunisationItem(
            dose: dose,
            status: ImmunisationStatus.dueToday,
            detail:
                '${dose.label} is due now. ${dose.protectsAgainst}.',
          ),
        );
        giveToday.add(dose);
      }
    }

    final nextNotDue = items
        .where((i) => i.status == ImmunisationStatus.notYetDue)
        .sorted((a, b) => a.dose.dueAtWeeks.compareTo(b.dose.dueAtWeeks))
        .firstOrNull;

    final upToDate = overdue.isEmpty && giveToday.isEmpty;

    return ImmunisationPlan(
      items: items,
      giveToday: giveToday,
      overdue: overdue,
      isFullyUpToDate: upToDate,
      nextDueInDays: nextNotDue == null
          ? null
          : (nextNotDue.dose.dueAtWeeks * 7) - ageInDays,
      nextDueLabel: nextNotDue?.dose.label,
      summary: _summary(overdue, giveToday, upToDate, nextNotDue),
    );
  }

  static String _summary(
    List<ImmunisationItem> overdue,
    List<VaccineDose> giveToday,
    bool upToDate,
    ImmunisationItem? next,
  ) {
    if (upToDate) {
      return next == null
          ? 'Fully immunised for age. Nothing further due.'
          : 'Up to date. Next is ${next.dose.label} at '
                '${_weeksLabel(next.dose.dueAtWeeks)}.';
    }
    if (overdue.isEmpty) {
      return 'Due today: ${giveToday.map((d) => d.label).join(', ')}.';
    }
    final worst = overdue.reduce(
      (a, b) => a.weeksOverdue >= b.weeksOverdue ? a : b,
    );
    return '${overdue.length} dose${overdue.length == 1 ? '' : 's'} overdue — '
        'the longest is ${worst.dose.label}, ${worst.weeksOverdue} weeks late. '
        'Give ${giveToday.map((d) => d.label).join(', ')} today.';
  }

  static String _weeksLabel(int weeks) {
    if (weeks == 0) return 'birth';
    if (weeks < 9) return '$weeks weeks';
    final months = (weeks / 4.345).round();
    return '$months months';
  }

  /// Findings and actions ready to merge into an [AssessmentResult].
  static ({List<ClinicalFinding> findings, List<RecommendedAction> actions})
  asAssessmentParts(ImmunisationPlan plan) {
    final findings = <ClinicalFinding>[];
    final actions = <RecommendedAction>[];

    for (final item in plan.overdue) {
      findings.add(
        ClinicalFinding(
          label: '${item.dose.label} overdue',
          detail: item.detail,
          severity: item.weeksOverdue >= 12
              ? TriageLevel.priority
              : TriageLevel.watch,
          protocolSource: 'Ghana EPI schedule',
          measuredValue: '${item.weeksOverdue} weeks late',
          threshold: 'due at ${_weeksLabel(item.dose.dueAtWeeks)}',
          weight: item.weeksOverdue >= 12 ? 4 : 2,
        ),
      );
    }

    for (final item in plan.items.where(
      (i) => i.status == ImmunisationStatus.ageBarred,
    )) {
      findings.add(
        ClinicalFinding(
          label: '${item.dose.label} can no longer be given',
          detail: item.detail,
          severity: TriageLevel.watch,
          protocolSource: 'Ghana EPI schedule',
          weight: 1,
        ),
      );
    }

    if (plan.giveToday.isNotEmpty) {
      actions.add(
        RecommendedAction(
          instruction:
              'Give today: ${plan.giveToday.map((d) => d.label).join(', ')}. '
              'All of these can be given in the same session, in different '
              'sites.',
          urgency: ReferralUrgency.sameDay,
          rationale:
              'A sick visit is a vaccination opportunity. Mild illness, '
              'diarrhoea and mild fever are not contraindications, and sending '
              'the child away to "come back well" is how doses get lost.',
          protocolSource: 'Ghana EPI schedule',
          isTreatment: true,
        ),
      );
    }

    return (findings: findings, actions: actions);
  }
}
