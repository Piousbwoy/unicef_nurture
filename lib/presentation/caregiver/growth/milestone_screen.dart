import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/audio/caregiver_playback.dart';
import '../../../domain/entities/caregiver.dart';
import '../../../domain/entities/core.dart';
import '../../../domain/enums.dart';
import '../caregiver_providers.dart';
import '../check/check_controller.dart';
import '../help/caregiver_voice.dart';
import '../widgets/companion.dart';
import 'milestone_controller.dart';

class CaregiverMilestoneScreen extends ConsumerStatefulWidget {
  const CaregiverMilestoneScreen({super.key, required this.person});
  final Person person;
  @override
  ConsumerState<CaregiverMilestoneScreen> createState() =>
      _MilestoneScreenState();
}

class _MilestoneScreenState extends ConsumerState<CaregiverMilestoneScreen> {
  CaregiverMilestoneController? _check;
  CaregiverVoiceController? _voice;
  bool _review = false;
  bool _confirmed = false;
  String? _spoken;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_check != null) return;
    final scope = ref.read(caregiverScopeProvider);
    final user = ref.read(currentUserProvider);
    if (scope == null || user == null) return;
    final container = ProviderScope.containerOf(context, listen: false);
    bool current() {
      try {
        return container.read(caregiverScopeProvider) == scope;
      } catch (_) {
        return false;
      }
    }

    _check = CaregiverMilestoneController(
      repository: ref.read(careRepositoryProvider),
      user: user,
      scope: scope,
      person: widget.person,
      clock: ref.read(caregiverClockProvider),
      isCurrent: current,
      onSaved: () {
        container.invalidate(
          householdMilestoneChecksProvider(scope.householdId),
        );
        container.invalidate(latestMilestoneCheckProvider(widget.person.id));
        container.invalidate(caregiverActivityProvider(scope));
        container.invalidate(caregiverClinicalProvider(scope));
      },
    )..addListener(_changed);
    unawaited(_check!.load());
  }

  CaregiverSpeech _speech(CaregiverMilestoneController c) {
    final q = c.band!.milestones[c.draft!.questionIndex];
    return CaregiverSpeech(
      id: 'milestone_${c.draft!.id}_${q.id}',
      english: q.question,
      language: ref.read(currentUserProvider)?.preferredLanguage ?? 'English',
    );
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    final c = _check!;
    final next = c.stage == CaregiverCheckStage.questions ? _speech(c) : null;
    if (next?.id == _spoken) return;
    _voice?.stop();
    _spoken = next?.id;
    if (next == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          c.isCurrent() &&
          _spoken == next.id &&
          (ref.read(caregiverSettingsProvider(c.scope)).valueOrNull?.autoRead ??
              false)) {
        unawaited(_voice?.play(next));
      }
    });
  }

  @override
  void dispose() {
    _voice?.stop(notify: false);
    _check?.removeListener(_changed);
    _check?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(caregiverScopeProvider);
    final c = _check;
    if (scope == null || c == null || c.scope != scope) {
      return const CompanionPage(
        title: 'Milestone check',
        child: Text('Reopen this check from your current family.'),
      );
    }
    _voice = ref.watch(caregiverVoiceProvider(scope));
    ref.watch(caregiverSettingsProvider(scope));
    return CompanionPage(
      title: 'Milestone check',
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '${c.person.fullName} • ${caregiverAge(c.person)}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const Text(
            'Your observations, not a diagnosis. Trying a play activity does not mean a child can do a milestone.',
          ),
          if (c.notice != null) Text(c.notice!),
          const SizedBox(height: 16),
          if (c.stage == CaregiverCheckStage.loading)
            const Center(child: CircularProgressIndicator()),
          if (c.stage == CaregiverCheckStage.unsupported)
            const Text(
              'Milestone checks need a valid child age from birth to under five years. Ask a health worker to confirm the date of birth.',
            ),
          if (c.stage == CaregiverCheckStage.loadFailed) ...[
            OutlinedButton(
              onPressed: c.load,
              child: const Text('Retry saved answers'),
            ),
            CaregiverSaveAction(
              label: 'Start a new milestone check',
              onSave: c.startNew,
            ),
          ],
          if (c.stage == CaregiverCheckStage.resume) ...[
            CompanionCard(
              title: 'You have a saved milestone draft',
              child: Text(
                'Saved ${caregiverWhen(c.draft!.updatedAt)}. It is not a completed check.',
              ),
            ),
            OutlinedButton(
              onPressed: () => setState(() => _review = true),
              child: const Text('Review saved answers'),
            ),
            if (_review) ...[
              for (final m in c.band!.milestones)
                Text(
                  '${m.question}: ${switch (c.draft!.answers[m.id]) {
                    CaregiverAnswer.yes => 'Yes',
                    CaregiverAnswer.no => 'Not yet',
                    _ => 'Unanswered',
                  }}',
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _confirmed,
                onChanged: (v) => setState(() => _confirmed = v ?? false),
                title: const Text(
                  'These answers still describe this child now',
                ),
              ),
              FilledButton(
                onPressed: _confirmed ? c.confirmResume : null,
                child: const Text('Continue reviewing the check'),
              ),
            ],
            CaregiverSaveAction(
              label: 'Start a new milestone check',
              onSave: c.startNew,
            ),
          ],
          if (c.stage == CaregiverCheckStage.questions) ..._questions(c),
          if (c.stage == CaregiverCheckStage.result) ..._result(c),
          if (c.draft != null && c.stage != CaregiverCheckStage.resume) ...[
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text(switch (c.saveState) {
                CaregiverSaveState.unsaved => 'Not saved yet',
                CaregiverSaveState.saving => 'Saving…',
                CaregiverSaveState.saved =>
                  c.stage == CaregiverCheckStage.result
                      ? 'Saved on this phone'
                      : 'Draft saved on this phone',
                CaregiverSaveState.failed => 'Could not save — Retry',
              }),
            ),
            if (c.saveState == CaregiverSaveState.failed)
              OutlinedButton(
                onPressed: c.retry,
                child: const Text('Retry saving'),
              ),
          ],
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back to Grow & Play'),
          ),
        ],
      ),
    );
  }

  List<Widget> _questions(CaregiverMilestoneController c) {
    final i = c.draft!.questionIndex;
    final q = c.band!.milestones[i];
    final answer = c.draft!.answers[q.id];
    return [
      Text(
        '${i + 1} of ${c.band!.milestones.length} • ${c.band!.label}',
        semanticsLabel: 'Question ${i + 1} of ${c.band!.milestones.length}',
      ),
      CompanionCard(
        title: q.question,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CaregiverListen(speech: _speech(c), label: 'Hear question'),
            for (final option in [CaregiverAnswer.yes, CaregiverAnswer.no])
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  selected: answer == option,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(72, 72),
                      backgroundColor: answer == option
                          ? AppColors.checkBlueTint
                          : null,
                    ),
                    onPressed: () => c.answer(option),
                    child: Text(
                      option == CaregiverAnswer.yes
                          ? 'Yes — my child can do this'
                          : 'Not yet',
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            const Text(
              'If you are unsure or worried, leave the question unanswered and discuss it with a health worker. Loss of a skill or a child who is very unwell needs prompt help.',
            ),
            if (q.isFlag && answer == CaregiverAnswer.no)
              const Text(
                'Tell your health worker about this observation. You do not have to finish or save this check before seeking help.',
              ),
          ],
        ),
      ),
      FilledButton(
        onPressed: answer == null ? null : c.next,
        child: Text(
          i + 1 == c.band!.milestones.length ? 'Show me the result' : 'Next',
        ),
      ),
      if (i > 0) OutlinedButton(onPressed: c.back, child: const Text('Back')),
    ];
  }

  List<Widget> _result(CaregiverMilestoneController c) {
    final report = c.report!;
    final title = switch (report.verdict) {
      MilestoneVerdict.flag => 'Show these observations to a health worker',
      MilestoneVerdict.watch => 'Discuss the skills not yet observed',
      MilestoneVerdict.onTrack => 'Your milestone observations',
    };
    return [
      CompanionCard(
        title: title,
        child: Text(
          'Original check: ${caregiverWhen(report.checkedAt)}\nThis screening report cannot diagnose development or guarantee that all is well. Contact your health worker if you have concerns, even without a flag.',
        ),
      ),
      if (report.flags.isNotEmpty)
        Text('For your health worker:\n${report.flags.join('\n')}'),
      if (report.canDo.isNotEmpty)
        Text('You observed:\n${report.canDo.join('\n')}'),
      if (report.notYet.isNotEmpty)
        Text('Not yet observed:\n${report.notYet.join('\n')}'),
      const Text(
        'Saving does not notify a health worker. You can show this readable report in person.',
      ),
      CaregiverSaveAction(
        label: 'Start a new milestone check',
        onSave: c.startNew,
      ),
    ];
  }
}
