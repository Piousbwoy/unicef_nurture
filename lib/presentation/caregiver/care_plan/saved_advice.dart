import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../domain/engines/recommendation_engine.dart';
import '../../../domain/entities/caregiver.dart';
import '../../../domain/entities/core.dart';
import '../../../domain/entities/visit.dart';
import '../../shared/recommendation_kit.dart';
import '../caregiver_providers.dart';
import '../help/caregiver_voice.dart';
import '../widgets/companion.dart';
import '../../../core/audio/caregiver_playback.dart';

/// Only counseling participation can be reported here. Treatment, procedures,
/// referrals and unspecified actions remain read-only clinic decisions.
bool caregiverMayComplete(RecommendedAction action) =>
    CaregiverActivity.mayComplete(action);

class CaregiverSavedAdvice extends ConsumerStatefulWidget {
  const CaregiverSavedAdvice({
    super.key,
    required this.person,
    required this.assessment,
    this.editable = true,
  });
  final Person person;
  final Assessment assessment;
  final bool editable;
  @override
  ConsumerState<CaregiverSavedAdvice> createState() =>
      _CaregiverSavedAdviceState();
}

class _CaregiverSavedAdviceState extends ConsumerState<CaregiverSavedAdvice> {
  bool _saving = false;
  Set<String>? _retry;
  Future<void> _save(
    CaregiverWriter writer,
    Set<String> next,
    Set<String> old,
  ) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _retry = null;
    });
    try {
      for (final item in {...old, ...next}) {
        if (old.contains(item) == next.contains(item)) continue;
        await writer.activity(
          writer.entry(
            kind: CaregiverActivityKind.planAction,
            personId: widget.person.id,
            sourceId: widget.assessment.id,
            itemKey: item,
            occurrenceKey: widget.assessment.id,
            done: next.contains(item),
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _retry = next);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(caregiverScopeProvider);
    if (scope == null || scope.householdId != widget.person.householdId) {
      return const SizedBox.shrink();
    }
    final assessment = widget.assessment;
    final raw = assessment.carePlanJson;
    if (raw == null) {
      return CompanionCard(
        title: 'Saved clinic record',
        eyebrow: caregiverWhen(assessment.performedAt),
        child: Text(
          '${assessment.result.classification}\nA detailed saved plan is not available. Ask your health worker for the current advice.',
        ),
      );
    }
    final CarePlan plan;
    try {
      plan = CarePlan.fromJson(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return CompanionCard(
        title: 'Clinic advice could not be read',
        child: const Text(
          'Ask your health worker to review the saved plan. No completed steps were assumed.',
        ),
      );
    }
    final writer = ref.watch(caregiverWriterProvider(scope));
    final language = ref.watch(currentUserProvider)?.preferredLanguage ?? 'English';
    return ref
        .watch(caregiverActivityProvider(scope))
        .when(
          loading: () => const Text('Loading saved clinic progress…'),
          error: (_, _) => CompanionLoadError(
            onRetry: () => ref.invalidate(caregiverActivityProvider(scope)),
          ),
          data: (activity) {
            final complete = activity
                .where(
                  (a) =>
                      a.personId == widget.person.id &&
                      a.kind == CaregiverActivityKind.planAction &&
                      a.sourceId == assessment.id &&
                      a.occurrenceKey == assessment.id &&
                      a.done,
                )
                .map((a) => a.itemKey)
                .toSet();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Your checkmarks report activity only. They do not confirm treatment, recovery, or clinic attendance.',
                ),
                AbsorbPointer(
                  absorbing: _saving,
                  child: FamilyCarePlanCard(
                    plan: plan,
                    personName:
                        '${widget.person.fullName} • ${caregiverAge(widget.person)}',
                    language: language,
                    savedAt: assessment.performedAt,
                    completed: complete,
                    canComplete: (a) =>
                        widget.editable && caregiverMayComplete(a),
                    onCompletedChanged: (next) => _save(writer, next, complete),
                    voiceControl: CaregiverListen(
                      speech: CaregiverSpeech(
                        id: 'clinic_${assessment.id}',
                        language: 'English',
                        english:
                            'Saved clinic advice from ${caregiverWhen(assessment.performedAt)}. ${plan.caregiverMessage ?? plan.summary}',
                      ),
                    ),
                  ),
                ),
                if (_saving) const Text('Saving…'),
                if (_retry != null)
                  OutlinedButton(
                    onPressed: () => _save(writer, _retry!, complete),
                    child: const Text('Could not save — Retry'),
                  ),
                const SizedBox(height: 16),
              ],
            );
          },
        );
  }
}
