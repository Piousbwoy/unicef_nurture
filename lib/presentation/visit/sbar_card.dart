/// A SBAR handover note composed from records the app already holds.
///
/// When a child must go up the referral chain — or a nurse hands a case to a
/// CHO, a midwife or a call centre — what travels is a structured story, not
/// the whole chart. SBAR (Situation, Background, Assessment, Recommendation)
/// is the handover format clinicians are actually trained on, so this card
/// renders one from an [Assessment] or a [Referral] with no extra typing at
/// the door. Everything on it is selectable, so it can be read down a phone
/// line or copied into a paper referral book.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/core.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../fhw/clinic_widgets.dart';

class SbarCard extends StatelessWidget {
  const SbarCard({
    super.key,
    required this.patientLine,
    required this.situation,
    required this.background,
    required this.assessment,
    required this.recommendation,
    this.urgent = false,
  });

  /// Who this is about, one line — name, client type, triage or urgency.
  final String patientLine;
  final List<String> situation;
  final List<String> background;
  final List<String> assessment;
  final List<String> recommendation;

  /// Colours the S chip red and edges the card in triage red. Reserved for
  /// urgent acuity — the same rule as everywhere else in the app.
  final bool urgent;

  factory SbarCard.fromAssessment(Assessment a, Person? person) {
    final result = a.result;
    final name = (person?.fullName.trim().isNotEmpty ?? false)
        ? person!.fullName.trim()
        : 'Patient';
    final situation = <String>[
      result.classification,
      if (result.dangerSignsPresent.isNotEmpty)
        'Danger signs: ${result.dangerSignsPresent.join(', ')}',
      'Recorded ${DateFormat('d MMM yyyy, HH:mm').format(a.performedAt.toLocal())}',
    ];
    final background = <String>[
      if (person != null)
        '${person.effectiveClientType.label} · ${person.ageLabel}',
      if (result.nutritionStatus != null) result.nutritionStatus!.label,
      if (result.missingData.isNotEmpty)
        'Not measured: ${result.missingData.join(', ')}',
      'Protocol confidence ${result.effectiveConfidenceScore}/100',
    ];
    final sorted = [...result.findings]
      ..sort((x, y) => y.severity.severity.compareTo(x.severity.severity));
    final assessmentLines = <String>[
      for (final f in sorted.take(4)) '${f.label}: ${f.detail}',
    ];
    final handoverActions = result.actions.where(
      (x) => x.isReferral || x.isPrereferralTreatment,
    );
    final recommendation = <String>[
      for (final action in handoverActions) action.instruction,
      if (result.followUpInDays != null)
        'Review in ${result.followUpInDays} days',
      if (a.wasOverridden)
        'Triage overridden by ${a.overrideBy ?? 'staff'}'
            '${a.overrideReason != null ? ': ${a.overrideReason}' : ''}',
    ];
    return SbarCard(
      patientLine: '$name · ${a.effectiveTriage.label}',
      situation: situation,
      background: background.isEmpty ? const ['No background recorded.'] : background,
      assessment: assessmentLines.isEmpty
          ? const ['No findings recorded.']
          : assessmentLines,
      recommendation: recommendation.isEmpty
          ? const ['Continue routine care and counselling.']
          : recommendation,
      urgent: a.effectiveTriage == TriageLevel.urgent,
    );
  }

  factory SbarCard.fromReferral(Referral r, Person? person) {
    final name = (person?.fullName.trim().isNotEmpty ?? false)
        ? person!.fullName.trim()
        : 'Patient';
    final open = r.status.isOpen;
    return SbarCard(
      patientLine: '$name · ${r.urgency.label} referral',
      urgent: r.urgency == ReferralUrgency.immediate,
      situation: [
        'Referral to ${r.facilityName}',
        r.reason,
        'Code ${r.referenceCode} · issued '
            '${DateFormat('d MMM yyyy, HH:mm').format(r.issuedAt.toLocal())}',
      ],
      background: [
        if (r.clinicalSummary?.isNotEmpty ?? false)
          r.clinicalSummary!
        else
          'No clinical summary recorded on the referral.',
      ],
      assessment: ['Current status: ${r.status.label}'],
      recommendation: [
        if (open) ...[
          'Confirm arrival at ${r.facilityName} and record the outcome.',
          if (r.needsEscalation)
            'Over 48 hours with no confirmed arrival — trace now.',
          if (r.escalatedAt != null)
            'Escalated for tracing on '
                '${DateFormat('d MMM yyyy').format(r.escalatedAt!.toLocal())}.',
        ] else ...[
          'Referral is closed (${r.status.label}).',
          if (r.outcomeNotes?.isNotEmpty ?? false)
            'Recorded outcome: ${r.outcomeNotes}',
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClinicCard(
      accent: urgent ? AppColors.triageRed : AppColors.primary,
      title: 'Handover note',
      subtitle: patientLine,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Section(
            letter: 'S',
            title: 'Situation',
            lines: situation,
            color: urgent ? AppColors.triageRed : AppColors.primary,
          ),
          const SizedBox(height: 14),
          _Section(
            letter: 'B',
            title: 'Background',
            lines: background,
            color: AppColors.brassDeep,
          ),
          const SizedBox(height: 14),
          _Section(
            letter: 'A',
            title: 'Assessment',
            lines: assessment,
            color: AppColors.primaryDeep,
          ),
          const SizedBox(height: 14),
          _Section(
            letter: 'R',
            title: 'Recommendation',
            lines: recommendation,
            color: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.letter,
    required this.title,
    required this.lines,
    required this.color,
  });

  final String letter;
  final String title;
  final List<String> lines;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            letter,
            style: AppType.label.copyWith(color: Colors.white, fontSize: 13),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppType.label.copyWith(
                  fontSize: 12,
                  color: AppColors.inkMuted,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 4),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: SelectableText(
                    line,
                    style: AppType.body.copyWith(fontSize: 13.5),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shows a handover note as a modal sheet, ready to be read down a phone line.
Future<void> showSbarSheet(BuildContext context, SbarCard sbar) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: SingleChildScrollView(child: sbar),
    ),
  );
}
