import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../domain/entities/caregiver.dart';
import '../../../domain/entities/core.dart';
import '../../../domain/entities/visit.dart';
import '../../../domain/services/caregiver_check_policy.dart';
import '../caregiver_providers.dart';
import '../widgets/companion.dart';

class CaregiverNurseSummary extends ConsumerStatefulWidget {
  const CaregiverNurseSummary({
    super.key,
    required this.person,
    required this.report,
    this.draft,
    this.questions,
  });
  final Person person;
  final HomeCheck report;
  final CaregiverDraft? draft;
  final CaregiverQuestionSet? questions;
  @override
  ConsumerState<CaregiverNurseSummary> createState() =>
      _CaregiverNurseSummaryState();
}

class _CaregiverNurseSummaryState extends ConsumerState<CaregiverNurseSummary> {
  bool _share = false;
  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(caregiverScopeProvider);
    if (scope == null || scope.householdId != widget.report.householdId) {
      return const SizedBox.shrink();
    }
    final writer = ref.watch(caregiverWriterProvider(scope));
    final activity = ref.watch(caregiverActivityProvider(scope));
    final report = widget.report;
    final contextRecord = activity.valueOrNull
        ?.where(
          (a) =>
              a.kind == CaregiverActivityKind.homeCheckContext &&
              a.sourceId == report.id &&
              a.personId == report.personId,
        )
        .firstOrNull;
    Map<String, CaregiverAnswer>? recorded = widget.draft?.answers;
    List<CaregiverQuestion>? questions = widget.questions?.questions;
    String? onset = widget.draft?.onsetNote;
    // Pre-care and worry context: from the live draft when reviewing, or
    // from the immutable saved context for older checks.
    String? durationKey = widget.draft?.durationKey;
    Set<String> given = widget.draft?.givenCare ?? const {};
    List<String> concerns = widget.draft?.concerns ?? const [];
    bool unreadable = false;
    if (recorded == null && contextRecord != null) {
      try {
        questions = CaregiverCheckPolicy.historicalQuestions(
          contextRecord.detail['cohort'] as String,
          contextRecord.detail['questionVersion'] as int,
        );
        final raw = Map<String, Object?>.from(
          contextRecord.detail['answers'] as Map,
        );
        recorded = raw.map(
          (k, v) => MapEntry(k, CaregiverAnswer.values.byName(v as String)),
        );
        onset = contextRecord.note;
        durationKey = contextRecord.detail['duration'] as String?;
        given = contextRecord.detail['given'] == null
            ? const {}
            : (contextRecord.detail['given'] as List).cast<String>().toSet();
        concerns = contextRecord.detail['concerns'] == null
            ? const []
            : (contextRecord.detail['concerns'] as List).cast<String>();
        if (questions == null ||
            recorded.keys.any((k) => !questions!.any((q) => q.key == k))) {
          throw const FormatException('Unknown saved questions');
        }
      } catch (_) {
        unreadable = true;
        recorded = null;
        questions = null;
      }
    }
    final unasked = questions
        ?.where((q) => recorded?[q.key] == null)
        .map((q) => q.label)
        .toList();
    final answers = questions
        ?.map(
          (q) =>
              '${q.label}: ${switch (recorded?[q.key]) {
                CaregiverAnswer.yes => 'YES',
                CaregiverAnswer.no => 'NO',
                CaregiverAnswer.unsure => 'Not sure',
                null => 'Unanswered',
              }}',
        )
        .join('\n');
    final arrived =
        activity.valueOrNull?.any(
          (a) =>
              a.kind == CaregiverActivityKind.arrival &&
              a.sourceId == report.id,
        ) ??
        false;
    final payload = jsonEncode({
      'version': 1,
      'type': 'caregiver_report',
      'id': report.id,
      'personId': report.personId,
      'name': widget.person.fullName,
      'time': report.checkedAt.toIso8601String(),
      'dateOfBirth': widget.person.dateOfBirth?.toIso8601String(),
      'estimatedBirthDate': widget.person.isDobEstimated,
      'yes': report.yesSigns,
      'unsure': report.unsureSigns,
      'unanswered': unasked,
      'answers': recorded?.map((k, v) => MapEntry(k, v.name)),
      'onset': onset,
      if (durationKey != null) 'duration': durationKey,
      if (given.isNotEmpty) 'given': given.toList()..sort(),
      if (concerns.isNotEmpty) 'concerns': concerns,
    });
    final durationLine = CaregiverDuration.byKey(durationKey);
    final givenLabels = [
      for (final key in given)
        if (CaregiverGivenCare.byKey(key) != null)
          CaregiverGivenCare.byKey(key)!.label,
    ];
    return CompanionPage(
      title: 'Show the nurse',
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          CompanionCard(
            title: widget.person.fullName,
            eyebrow: 'CAREGIVER REPORT • NOT A DIAGNOSIS OR REFERRAL',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Original check: ${caregiverWhen(report.checkedAt)}'),
                Text('Current age: ${caregiverAge(widget.person)}'),
                if (widget.person.dateOfBirth != null)
                  Text(
                    'Recorded birth date: ${caregiverDateKey(widget.person.dateOfBirth!)}',
                  ),
                const SizedBox(height: 16),
                Text(
                  'What I noticed: ${report.yesSigns.isEmpty ? 'No YES answers recorded' : report.yesSigns.join('; ')}',
                ),
                Text(
                  'Not sure: ${report.unsureSigns.isEmpty ? 'None recorded' : report.unsureSigns.join('; ')}',
                ),
                Text(
                  'Unanswered: ${unasked == null
                      ? 'Not available for this older report'
                      : unasked.isEmpty
                      ? 'None'
                      : unasked.join('; ')}',
                ),
                if (durationLine != null)
                  Text('Signs started: ${durationLine.label}'),
                if (givenLabels.isNotEmpty)
                  Text('Already given before checking: ${givenLabels.join(', ')}'),
                if (concerns.isNotEmpty)
                  Text('Caregiver was worried about: ${concerns.join(', ')}'),
                if (activity.isLoading)
                  const Text('Loading saved answer details…'),
                if (activity.hasError || unreadable)
                  const Text(
                    'Saved answer details could not be read. Do not assume missing answers were NO.',
                  ),
                if (onset?.isNotEmpty ?? false) Text('Onset note: $onset'),
                if (answers != null)
                  ExpansionTile(
                    title: const Text('All recorded answers'),
                    children: [Text(answers)],
                  ),
                const SizedBox(height: 12),
                const Text(
                  'Show these words directly. A health worker still needs to examine the person. This screen has not been sent to a clinic.',
                ),
              ],
            ),
          ),
          CompanionCard(
            title: 'Optional QR sharing',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'The QR includes the identity, birth date if recorded, original check time, answers, and onset note shown above. Anyone who scans it may read that information. Clinic scanning or import is not guaranteed.',
                ),
                OutlinedButton(
                  onPressed: () => setState(() => _share = !_share),
                  child: Text(_share ? 'Hide QR' : 'Reveal QR to share'),
                ),
                if (_share)
                  LayoutBuilder(
                    builder: (context, constraints) => Center(
                      child: Semantics(
                        label: 'QR containing the caregiver report shown above',
                        child: QrImageView(
                          data: payload,
                          size: constraints.maxWidth.clamp(0, 220).toDouble(),
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          CompanionCard(
            title: 'At the facility',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Arrival is only your local note. It does not confirm a referral, mean a nurse has seen the person, or mean they have recovered.',
                ),
                if (activity.isLoading) const Text('Loading arrival note…'),
                if (activity.hasError)
                  CompanionLoadError(
                    onRetry: () =>
                        ref.invalidate(caregiverActivityProvider(scope)),
                  ),
                if (arrived) const Text('Arrival noted on this phone'),
                if (!arrived &&
                    activity.hasValue &&
                    !activity.isLoading &&
                    !activity.hasError)
                  CaregiverSaveAction(
                    label: 'I have arrived',
                    onSave: () => writer.activity(
                      writer.entry(
                        kind: CaregiverActivityKind.arrival,
                        personId: report.personId,
                        sourceId: report.id,
                        itemKey: 'arrival',
                        occurrenceKey: report.id,
                        note: 'Caregiver reported arrival at a facility.',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back to guidance'),
          ),
        ],
      ),
    );
  }
}
