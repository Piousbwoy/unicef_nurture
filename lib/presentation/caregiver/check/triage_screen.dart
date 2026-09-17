import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../core/audio/caregiver_playback.dart';
import '../../../core/i18n/speech_bank.dart';
import '../../../domain/services/offline_narration.dart';
import '../../shared/speech_language_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/motion.dart';
import '../../../domain/entities/caregiver.dart';
import '../../../domain/entities/core.dart';
import '../../../domain/entities/visit.dart';
import '../../../domain/enums.dart';
import '../../../domain/services/caregiver_check_policy.dart';
import '../caregiver_providers.dart';
import '../family/add_member.dart';
import '../help/caregiver_voice.dart';
import '../widgets/companion.dart';
import '../widgets/premium_button.dart';
import 'check_controller.dart';
import 'check_widgets.dart';
import 'nurse_summary.dart';

class CaregiverTriageScreen extends ConsumerStatefulWidget {
  const CaregiverTriageScreen({
    super.key,
    required this.householdId,
    this.onDone,
    this.personId,
  });
  final String householdId;
  final String? personId;
  final VoidCallback? onDone;
  @override
  ConsumerState<CaregiverTriageScreen> createState() => _TriageScreenState();
}

class _TriageScreenState extends ConsumerState<CaregiverTriageScreen> {
  CaregiverCheckController? _check;
  CaregiverVoiceController? _voice;
  String? _spokenKey;

  /// The speech language chosen for this check session. The FIRST "hear this
  /// question" asks once; after that, questions speak immediately in the
  /// remembered language — a worried caregiver should not re-negotiate a
  /// picker eight times.
  String? _speechLanguage;
  Timer? _noteDebounce;
  bool _reviewing = false;
  bool _confirmed = false;
  bool _initialSelected = false;

  @override
  void dispose() {
    _noteDebounce?.cancel();
    _voice?.stop(notify: false);
    _check?.removeListener(_changed);
    _check?.dispose();
    super.dispose();
  }

  void _pick(Person person) {
    final scope = ref.read(caregiverScopeProvider);
    final user = ref.read(currentUserProvider);
    if (scope == null || user == null) return;
    _voice?.stop();
    _check?.removeListener(_changed);
    _check?.dispose();
    final container = ProviderScope.containerOf(context, listen: false);
    bool current() {
      try {
        return container.read(caregiverScopeProvider) == scope;
      } catch (_) {
        return false;
      }
    }

    _spokenKey = null;
    _speechLanguage = null;
    _reviewing = false;
    _confirmed = false;
    final controller = CaregiverCheckController(
      repository: ref.read(careRepositoryProvider),
      user: user,
      scope: scope,
      person: person,
      clock: ref.read(caregiverClockProvider),
      isCurrent: current,
      onSaved: () {
        container.invalidate(householdHomeChecksProvider(scope.householdId));
        container.invalidate(latestHomeCheckProvider(person.id));
        container.invalidate(caregiverActivityProvider(scope));
        container.invalidate(caregiverClinicalProvider(scope));
      },
    );
    setState(() => _check = controller);
    controller.addListener(_changed);
    unawaited(controller.load());
  }

  CaregiverSpeech _questionSpeech(CaregiverCheckController check) {
    final question = check.questions!.questions[check.draft!.questionIndex];
    final id = 'q_${check.questions!.speechId(question)}';
    return CaregiverSpeech(
      id: id,
      english: SpeechBank.byId(id)?.english ?? question.label,
      language: ref.read(currentUserProvider)?.preferredLanguage ?? 'English',
      clipId: id,
    );
  }

  Future<void> _listenToQuestion(CaregiverCheckController check) async {
    final voice = _voice;
    if (voice == null) return;
    if (voice.active) {
      voice.stop();
      return;
    }
    final speech = _questionSpeech(check);
    final scope = ref.read(caregiverScopeProvider);
    final user = ref.read(currentUserProvider);
    // The first ask in this session picks a language; every later question
    // speaks straight away in the remembered one.
    final chosen =
        _speechLanguage ?? await chooseSpeechLanguage(context, speech);
    if (!mounted ||
        chosen == null ||
        _check != check ||
        ref.read(caregiverScopeProvider) != scope ||
        ref.read(currentUserProvider) != user ||
        check.stage != CaregiverCheckStage.questions ||
        _questionSpeech(check).id != speech.id) {
      return;
    }
    setState(() => _speechLanguage = chosen);
    await voice.play(speech.withLanguage(chosen));
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    final check = _check!;
    if (check.stage != CaregiverCheckStage.questions) {
      if (_spokenKey != null) _voice?.stop();
      _spokenKey = null;
      return;
    }
    final speech = _questionSpeech(check);
    if (_spokenKey == speech.id) return;
    _spokenKey = speech.id;
    _voice?.stop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _check != check ||
          check.stage != CaregiverCheckStage.questions ||
          _spokenKey != speech.id) {
        return;
      }
      final settings = ref
          .read(caregiverSettingsProvider(check.scope))
          .valueOrNull;
      if (settings?.autoRead ?? false) unawaited(_voice?.play(speech));
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(caregiverScopeProvider);
    if (scope == null ||
        scope.householdId != widget.householdId ||
        (_check != null && _check!.scope != scope)) {
      return const CompanionPage(
        title: 'Danger-sign check',
        child: Center(
          child: Text('Reopen the check from your current family.'),
        ),
      );
    }
    _voice = ref.watch(caregiverVoiceProvider(scope));
    ref.watch(caregiverSettingsProvider(scope));
    final check = _check;
    return CompanionPage(
      title: check == null
          ? 'Who are you checking?'
          : switch (check.stage) {
              CaregiverCheckStage.result => 'What to do now',
              CaregiverCheckStage.questions => check.needsConcerns
                  ? 'What is worrying you?'
                  : 'What have you noticed?',
              CaregiverCheckStage.duration =>
                'How long has it been like this?',
              CaregiverCheckStage.context => 'Before you see the nurse',
              _ => 'Danger-sign check',
            },
      child: check == null
          ? _picker()
          : switch (check.stage) {
              CaregiverCheckStage.loading => const Center(
                child: CircularProgressIndicator(),
              ),
              CaregiverCheckStage.resume => _resume(check),
              CaregiverCheckStage.questions =>
                check.needsConcerns ? _concerns(check) : _questions(check),
              CaregiverCheckStage.duration => _duration(check),
              CaregiverCheckStage.context => _context(check),
              CaregiverCheckStage.result => _result(check),
              CaregiverCheckStage.unsupported ||
              CaregiverCheckStage.loadFailed => _limitation(check),
            },
    );
  }

  Widget _picker() => ref
      .watch(householdMembersProvider(widget.householdId))
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: CaregiverSaveAction(
            label: 'Retry family members',
            onSave: () async {
              ref.invalidate(householdMembersProvider(widget.householdId));
              await ref.read(
                householdMembersProvider(widget.householdId).future,
              );
            },
          ),
        ),
        data: (members) {
          if (!_initialSelected && widget.personId != null) {
            _initialSelected = true;
            final selected = members
                .where((p) => p.id == widget.personId)
                .firstOrNull;
            if (selected != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _pick(selected);
              });
            }
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Gap.radius),
                  gradient: AppColors.checkHeroGradient,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.group_rounded,
                        color: AppColors.checkBlue,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Who needs a check today?',
                            style: TextStyle(
                              fontFamily: 'Sora',
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.2,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Choose a family member to begin',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Color(0xB3FFFFFF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              for (final person in members)
                CaregiverPersonCard(
                  person: person,
                  onTap: () => _pick(person),
                ),
              if (members.isEmpty)
                CompanionCard(
                  title: 'No family members yet',
                  child: const Text(
                    'Add someone you care for to begin checking danger signs.',
                  ),
                ),
              const SizedBox(height: 12),
              CaregiverAddMemberButton(householdId: widget.householdId),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => showCaregiverEmergency(context),
                icon: const Icon(Icons.emergency_outlined),
                label: const Text('Emergency — do not wait for a check'),
              ),
            ],
          );
        },
      );

  Widget _resume(CaregiverCheckController check) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      CompanionCard(
        title: 'A check for ${check.person.fullName} is unfinished',
        eyebrow: 'DRAFT',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Draft saved ${caregiverWhen(check.draft!.updatedAt)}. This is not a completed check.',
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => setState(() => _reviewing = true),
              child: const Text('Review saved answers'),
            ),
            if (_reviewing) ...[
              const SizedBox(height: 16),
              for (final q in check.questions!.questions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${q.label}: ${_answerLabel(check.draft!.answers[q.key])}',
                  ),
                ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _confirmed,
                onChanged: (value) =>
                    setState(() => _confirmed = value ?? false),
                title: const Text(
                  'These answers still describe this person now',
                ),
              ),
              FilledButton(
                onPressed: _confirmed ? check.confirmResume : null,
                child: const Text('Continue this check'),
              ),
            ],
            const SizedBox(height: 12),
            CaregiverSaveAction(
              label: 'Start a new check',
              onSave: check.startNew,
            ),
          ],
        ),
      ),
    ],
  );

  Widget _limitation(CaregiverCheckController check) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      CompanionCard(
        title: 'A check cannot be completed yet',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              check.stage == CaregiverCheckStage.unsupported
                  ? 'This check supports children under five with a recorded birth date, and people recorded as pregnant or postpartum. Confirm missing or incorrect details with a health worker. No health conclusion has been made for ${check.person.fullName}.'
                  : check.notice!,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => showCaregiverEmergency(context),
              child: const Text('Get help'),
            ),
            if (check.stage == CaregiverCheckStage.loadFailed) ...[
              const SizedBox(height: 8),
              CaregiverSaveAction(
                label: 'Start a new check',
                onSave: check.startNew,
              ),
            ],
          ],
        ),
      ),
    ],
  );

  Widget _saveStatus(CaregiverCheckController check) {
    final isSaved = check.saveState == CaregiverSaveState.saved;
    final isSaving = check.saveState == CaregiverSaveState.saving;
    final isFailed = check.saveState == CaregiverSaveState.failed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isFailed
            ? AppColors.triageRedBg
            : isSaved
            ? AppColors.triageGreenBg
            : AppColors.checkBlueTint,
        borderRadius: BorderRadius.circular(Gap.radiusXs),
      ),
      child: Row(
        children: [
          Icon(
            isFailed
                ? Icons.error_outline_rounded
                : isSaving
                ? Icons.cloud_upload_outlined
                : isSaved
                ? Icons.cloud_done_rounded
                : Icons.cloud_queue_rounded,
            size: 18,
            color: isFailed
                ? AppColors.triageRed
                : isSaved
                ? AppColors.triageGreen
                : AppColors.checkBlue,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                switch (check.saveState) {
                  CaregiverSaveState.unsaved => 'Not saved yet',
                  CaregiverSaveState.saving => 'Saving…',
                  CaregiverSaveState.saved =>
                    check.report == null
                        ? 'Draft saved on this phone'
                        : 'Saved on this phone',
                  CaregiverSaveState.failed =>
                    'Could not save. Guidance is still available.',
                },
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isFailed
                      ? AppColors.triageRed
                      : isSaved
                      ? AppColors.triageGreen
                      : AppColors.inkMuted,
                ),
              ),
            ),
          ),
          if (isFailed)
            TextButton(
              onPressed: check.retry,
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------- Step 0: the worry

  /// The check opens with what SHE noticed, not a questionnaire. Concerns
  /// only reorder the battery — every danger sign is still asked.
  Widget _concerns(CaregiverCheckController check) {
    final options = CaregiverCheckPolicy.concernsFor(check.questions!);
    return _CheckStepScaffold(
      progressLabel: 'BEFORE WE START',
      personName: check.person.fullName,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'What is worrying you about '
            '${check.person.fullName.split(' ').first} today?',
            style: const TextStyle(
              fontFamily: 'Sora',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.3,
              color: AppColors.checkNavy,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Choose anything that worries you — the check still asks every '
            'danger sign, but starts with yours.',
            style: TextStyle(
              fontSize: 13.5,
              color: AppColors.inkMuted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          _ConcernPicker(options: options, onChosen: check.setConcerns),
          const SizedBox(height: 24),
          const Text(
            'A YES at any point takes you straight to what to do.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.inkMuted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------- Question screen

  Widget _questions(CaregiverCheckController check) {
    final draft = check.draft!;
    final questions = check.questions!.questions;
    final index = draft.questionIndex;
    final question = questions[index];
    final progress = (index + 1) / questions.length;
    final answered = draft.answers[question.key];
    return ListView(
      key: ValueKey('question:$index'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        _CheckStepHeader(
          stepLabel: 'Question ${index + 1} of ${questions.length}',
          personName: check.person.fullName,
          language: _speechLanguage,
          onPickLanguage: () async {
            final speech = _questionSpeech(check);
            final chosen = await chooseSpeechLanguage(context, speech);
            if (chosen != null && mounted) {
              setState(() => _speechLanguage = chosen);
            }
          },
          progress: progress,
        ),
        if (check.notice != null) ...[
          const SizedBox(height: 16),
          _NoticeBanner(message: check.notice!),
        ],
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.checkNavyDeep.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                question.label,
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                  color: AppColors.checkNavy,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () => unawaited(_listenToQuestion(check)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.checkBlue,
                    side: const BorderSide(
                      color: AppColors.checkNavy,
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.volume_up_rounded, size: 20),
                  label: const Text(
                    'Hear this question',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _PremiumAnswerButton(
                label: 'YES',
                icon: Icons.check_rounded,
                selected: answered == CaregiverAnswer.yes,
                onTap: () {
                  _voice?.stop();
                  check.answer(question.key, CaregiverAnswer.yes);
                },
              ),
              const SizedBox(height: 12),
              _PremiumAnswerButton(
                label: 'NO',
                icon: Icons.close_rounded,
                selected: answered == CaregiverAnswer.no,
                onTap: () {
                  _voice?.stop();
                  check.answer(question.key, CaregiverAnswer.no);
                },
              ),
              const SizedBox(height: 12),
              _PremiumAnswerButton(
                label: 'NOT SURE',
                icon: Icons.help_rounded,
                selected: answered == CaregiverAnswer.unsure,
                onTap: () {
                  _voice?.stop();
                  check.answer(question.key, CaregiverAnswer.unsure);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        PremiumCheckButton(
          label: index == questions.length - 1
              ? 'Continue — almost done'
              : 'Next',
          icon: Icons.arrow_forward_rounded,
          trailingIcon: Icons.arrow_forward_rounded,
          height: 56,
          enabled: answered != null,
          onPressed: () {
            _voice?.stop();
            check.next();
          },
        ),
        if (index > 0) ...[
          const SizedBox(height: 10),
          TextButton(
            onPressed: () {
              _voice?.stop();
              check.back();
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.checkNavy,
            ),
            child: const Text('Back to previous question'),
          ),
        ],
        const SizedBox(height: 16),
        _saveStatus(check),
        const SizedBox(height: 16),
        const Text(
          'A YES takes you straight to what to do. Everything else waits '
          'for you — you control the pace. These are your observations, '
          'not an examination.',
          style: TextStyle(
            fontSize: 12.5,
            color: AppColors.inkMuted,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  // ------------------------------------------- Step 2: how long has it been

  Widget _duration(CaregiverCheckController check) {
    final selected = check.draft!.durationKey;
    return _CheckStepScaffold(
      progressLabel: 'LAST STEP',
      personName: check.person.fullName,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'How long has this been going on?',
            style: const TextStyle(
              fontFamily: 'Sora',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.3,
              color: AppColors.checkNavy,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'The nurse will ask exactly this. It does not change what the '
            'check says — that comes from the danger signs alone.',
            style: TextStyle(
              fontSize: 13.5,
              color: AppColors.inkMuted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          for (final option in CaregiverDuration.values) ...[
            _SelectChip(
              label: option.label,
              icon: Icons.schedule_rounded,
              selected: selected == option.key,
              onTap: () {
                _voice?.stop();
                check.setDuration(option.key);
              },
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          _OnsetNoteField(
            initialValue: check.draft!.onsetNote,
            onChanged: check.onset,
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              _noteDebounce?.cancel();
              _voice?.stop();
              check.back();
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.checkNavy,
            ),
            child: const Text('Back to the signs'),
          ),
          const SizedBox(height: 16),
          _saveStatus(check),
        ],
      ),
    );
  }

  // ------------------------------------------- Step 3: what has been given

  Widget _context(CaregiverCheckController check) {
    return _CheckStepScaffold(
      progressLabel: 'FOR THE NURSE',
      personName: check.person.fullName,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Have you already given anything?',
            style: const TextStyle(
              fontFamily: 'Sora',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.3,
              color: AppColors.checkNavy,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'The nurse asks this first. Whatever it was — herbs, kiosk '
            'medicine, ORS — recording it honestly helps. This is only a '
            'note; nothing here is advice.',
            style: TextStyle(
              fontSize: 13.5,
              color: AppColors.inkMuted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          _GivenCarePicker(
            initial: check.draft!.givenCare,
            onDone: (keys) {
              check.setGivenCare(keys);
              check.finishContext();
            },
            onSkip: () {
              _voice?.stop();
              check.setGivenCare(const {});
              check.finishContext();
            },
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              _voice?.stop();
              check.back();
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.inkMuted,
            ),
            child: const Text('Back'),
          ),
          const SizedBox(height: 8),
          _saveStatus(check),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- Result

  Widget _result(CaregiverCheckController check) {
    final urgent = check.decision == CaregiverCheckDecision.urgent;
    final routine = check.decision == CaregiverCheckDecision.routine;
    final first = check.person.fullName.split(' ').first;
    final mother =
        check.person.effectiveClientType != ClientType.newborn &&
        check.person.effectiveClientType != ClientType.childUnderFive;
    final title = urgent
        ? 'Go to the health facility now'
        : routine
        ? '$first is doing well today'
        : 'Contact a health worker today';
    final advice = CaregiverCheckPolicy.contextualAdvice(
      person: check.person,
      decision: check.decision,
      set: check.questions!,
      answers: check.draft!.answers,
    );
    final observations = OfflineNarrator.reportedSigns(
      questions: check.questions!,
      answers: check.draft!.answers,
      decision: check.decision,
    );
    final nurseMsg = 'For ${check.person.fullName}. ${observations.english}'
        '${check.draft!.onsetNote.trim().isEmpty ? '' : ' Note: ${check.draft!.onsetNote}'}';
    final language =
        ref.watch(currentUserProvider)?.preferredLanguage ?? 'English';
    final feedingAdvice = CaregiverCheckPolicy.feedingSupport(
      check.person,
      check.clock(),
    );
    final yesSigns = CaregiverCheckPolicy.signsFound(
      check.questions!,
      check.draft!.answers,
    );
    final verdictColor = urgent
        ? AppColors.triageRed
        : routine
        ? AppColors.triageGreen
        : AppColors.triageAmber;
    final verdictIcon = urgent
        ? Icons.emergency_rounded
        : routine
        ? Icons.check_circle_rounded
        : Icons.info_rounded;
    final steps = _resultSteps(
      check: check,
      first: first,
      mother: mother,
      urgent: urgent,
      routine: routine,
    );
    final answeredCount = check.questions!.questions
        .where((q) => check.draft!.answers[q.key] != null)
        .length;
    final totalCount = check.questions!.questions.length;
    // The one-line verdict word. Urgent already says it in the title, so the
    // chip only appears where it adds information.
    final verdictChip = switch (check.decision) {
      CaregiverCheckDecision.urgent => null,
      CaregiverCheckDecision.contactToday => 'Visit your CHW soon',
      CaregiverCheckDecision.routine => 'Continue routine care',
      _ => null,
    };
    final adviceCard = _AdviceCard(
      advice: advice,
      yesSigns: yesSigns,
      chip: verdictChip,
    );
    final stepsCard = _ActionStepsCard(
      routine: routine,
      verdictColor: verdictColor,
      steps: steps,
      report: check.report,
      personId: check.person.id,
    );

    final Widget whatToDo = routine
        ? // A green verdict stays calm: the plan folds away until asked.
        Theme(
          data: Theme.of(
            context,
          ).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: false,
            iconColor: AppColors.checkNavy,
            collapsedIconColor: AppColors.checkNavy,
            title: const Text(
              'What should I do?',
              style: TextStyle(
                fontFamily: 'Sora',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.checkNavy,
              ),
            ),
            children: [
              adviceCard,
              const SizedBox(height: 12),
              stepsCard,
            ],
          ),
        )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [adviceCard, const SizedBox(height: 12), stepsCard],
          );

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _VerdictHero(
          personName: check.person.fullName,
          title: title,
          verdictColor: verdictColor,
          verdictIcon: verdictIcon,
        ),
        const SizedBox(height: 12),
        Text(
          '$answeredCount of $totalCount danger signs answered'
          '${check.draft!.durationKey == null
              ? ''
              : ' — started ${_durationPhrase(check.draft!.durationKey)}'}',
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.inkMuted,
          ),
        ),
        const SizedBox(height: 16),
        _saveStatus(check),
        const SizedBox(height: 20),
        if (!routine) ...[
          Container(
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: AppColors.checkUrgentGradient,
              boxShadow: [
                BoxShadow(
                  color: AppColors.triageRed.withValues(alpha: 0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => showCaregiverEmergency(context),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.phone_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Get help now',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        whatToDo,
        const SizedBox(height: 16),
        if (check.report != null) ...[
          if (urgent) _GettingThereCard(report: check.report!),
          if (urgent) const SizedBox(height: 16),
          _TellSomeoneCard(message: nurseMsg),
          const SizedBox(height: 16),
          if (!routine)
            _WatchCard(check: check, routine: routine)
          else
            _RecheckPromiseCard(report: check.report!),
          if (!routine) const SizedBox(height: 16),
          PremiumCheckButton(
            label: 'Show the nurse',
            icon: Icons.badge_outlined,
            trailingIcon: Icons.qr_code_2_rounded,
            onPressed: () => Navigator.of(context).push(
              GlassPageRoute<void>(
                builder: (_) => CaregiverNurseSummary(
                  person: check.person,
                  report: check.report!,
                  draft: check.draft,
                  questions: check.questions,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        CompanionCard(
          title: 'Feeding and comfort',
          child: Text(feedingAdvice),
        ),
        const SizedBox(height: 16),
        CaregiverListen(
          label: 'Hear the complete guidance',
          speech: CaregiverSpeech(
            id: 'check_guidance:${check.draft!.id}',
            english: OfflineNarrator.homeGuidance(
              personName: check.person.fullName,
              observations: observations,
              steps: steps.values.toList(),
              feedingAdvice: feedingAdvice,
              advice: advice,
              onsetNote: check.draft!.onsetNote,
            ),
            language: language,
          ),
        ),
        if (!routine) ...[
          const SizedBox(height: 16),
          _NurseMessageCard(
            message: nurseMsg,
            speech: CaregiverSpeech(
              id: 'nurse_signs:${check.draft!.id}',
              english: observations.english,
              language: language,
              clipIds: observations.clipIds,
            ),
            onCopy: () {
              Clipboard.setData(ClipboardData(text: nurseMsg));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
        const SizedBox(height: 16),
        _ObservationsCard(
          questions: check.questions!.questions,
          answers: check.draft!.answers,
          startedAt: check.draft!.startedAt,
          durationKey: check.draft!.durationKey,
          givenCare: check.draft!.givenCare,
        ),
        const SizedBox(height: 16),
        // A wrong answer is corrected by a new check, never by editing the
        // saved one — history stays append-only.
        OutlinedButton.icon(
          onPressed: () {
            _voice?.stop();
            unawaited(
              check.reviewAnswers().then((_) {
                if (mounted) setState(() {});
              }),
            );
          },
          icon: const Icon(Icons.edit_note_rounded, size: 18),
          label: const Text(
            'An answer was wrong — check again with answers filled in',
          ),
        ),
        const SizedBox(height: 8),
        CaregiverSaveAction(
          label: 'Start a new check',
          onSave: check.startNew,
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () {
            _voice?.stop();
            Navigator.pop(context);
            widget.onDone?.call();
          },
          child: const Text('Back to home'),
        ),
      ],
    );
  }

  Map<String, String> _resultSteps({
    required CaregiverCheckController check,
    required String first,
    required bool mother,
    required bool urgent,
    required bool routine,
  }) {
    if (routine) {
      return {
        'feed': mother
            ? 'Rest when the baby rests, and eat one extra meal a day.'
            : 'Keep feeding $first as you are \u2014 breastmilk, thick porridge and family foods.',
        'check': 'Check again tomorrow, or any time something worries you.',
        'play': mother
            ? 'Talk, sing and cuddle the baby every day \u2014 a child who is played with, learns.'
            : 'Play and talk with $first every day \u2014 a child who is played with, learns.',
      };
    }
    if (urgent) {
      return {
        'book': 'Carry the health record book \u2014 the nurse will ask for it.',
        'ride': 'Arrange a ride now. A neighbour\u2019s motorbike is fine \u2014 do not wait for a better one.',
        'feed': mother
            ? 'If she can swallow, give sips of water. If not, do not force anything by mouth.'
            : 'If $first can swallow, keep breastfeeding or give sips of fluid. If not, do not force anything by mouth.',
        'company': 'Go with someone if you can \u2014 a second person helps to carry and to explain.',
        'words': 'At the gate, say what you noticed and when it started \u2014 or show the message above.',
      };
    }
    return {
      'see': 'Show $first to your health worker or CHPS compound today \u2014 do not wait for the next scheduled visit.',
      'watch': 'Watch morning and evening. If any danger sign appears, go to the facility the same day.',
      'feed': 'Keep feeding and drinking as normal \u2014 small amounts, often.',
      'note': 'Remember when each sign started \u2014 the nurse will ask.',
    };
  }
}

/// Shared scaffold for the worry, duration and pre-care screens — one calm
/// card per step, in the same navy-on-white language as the questions.
class _CheckStepScaffold extends StatelessWidget {
  const _CheckStepScaffold({
    required this.progressLabel,
    required this.personName,
    required this.child,
  });

  final String progressLabel;
  final String personName;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        _CheckStepHeader(stepLabel: progressLabel, personName: personName),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.checkNavyDeep.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ],
    );
  }
}

/// Progress header shared by every step, with the language affordance.
class _CheckStepHeader extends StatelessWidget {
  const _CheckStepHeader({
    required this.stepLabel,
    required this.personName,
    this.language,
    this.onPickLanguage,
    this.progress = 1,
  });

  final String stepLabel;
  final String personName;
  final String? language;
  final VoidCallback? onPickLanguage;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 4),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.checkNavy,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  stepLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontFamily: 'Sora',
                  ),
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  personName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkMuted,
                  ),
                ),
              ),
              if (onPickLanguage != null) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: onPickLanguage,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.translate_rounded,
                          size: 15,
                          color: AppColors.checkBlue,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          language ?? 'Language',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.checkBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.checkNavy.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.checkBlue,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The worry grid: multi-select chips, plus an explicit no-worry path so
/// the question never blocks a routine check.
class _ConcernPicker extends StatefulWidget {
  const _ConcernPicker({required this.options, required this.onChosen});

  final List<CaregiverConcern> options;
  final ValueChanged<List<String>> onChosen;

  @override
  State<_ConcernPicker> createState() => _ConcernPickerState();
}

class _ConcernPickerState extends State<_ConcernPicker> {
  final selected = <String>{};

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final concern in widget.options)
              _ConcernChip(
                label: concern.label,
                icon: _concernIcon(concern.key),
                selected: selected.contains(concern.key),
                onTap: () => setState(() {
                  if (!selected.add(concern.key)) {
                    selected.remove(concern.key);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _ConcernChip(
          label: 'No specific worry — just check',
          icon: Icons.check_circle_outline_rounded,
          selected: false,
          onTap: () => widget.onChosen(const []),
        ),
        const SizedBox(height: 24),
        PremiumCheckButton(
          label: 'Start the check',
          enabled: selected.isNotEmpty,
          onPressed: () => widget.onChosen(selected.toList()),
        ),
      ],
    );
  }
}

/// Pre-care picker: multi-select chips with an exclusive "nothing yet", and
/// an explicit skip so context never blocks guidance.
class _GivenCarePicker extends StatefulWidget {
  const _GivenCarePicker({required this.initial, required this.onDone, required this.onSkip});

  final Set<String> initial;
  final ValueChanged<Set<String>> onDone;
  final VoidCallback onSkip;

  @override
  State<_GivenCarePicker> createState() => _GivenCarePickerState();
}

class _GivenCarePickerState extends State<_GivenCarePicker> {
  late final Set<String> selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in CaregiverGivenCare.values)
              _ConcernChip(
                label: option.label,
                icon: option == CaregiverGivenCare.nothing
                    ? Icons.do_not_disturb_on_outlined
                    : Icons.medication_liquid_rounded,
                selected: selected.contains(option.key),
                onTap: () => setState(() {
                  if (option == CaregiverGivenCare.nothing) {
                    selected
                      ..clear()
                      ..add(option.key);
                  } else {
                    selected.remove(CaregiverGivenCare.nothing.key);
                    if (!selected.add(option.key)) selected.remove(option.key);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 24),
        PremiumCheckButton(
          label: 'Save and show me what to do',
          onPressed: () => widget.onDone(selected),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: widget.onSkip,
          style: TextButton.styleFrom(foregroundColor: AppColors.checkNavy),
          child: const Text('Skip — just show me what to do'),
        ),
      ],
    );
  }
}

/// The onset free-text, debounced so a note does not write the draft on
/// every keystroke.
class _OnsetNoteField extends StatefulWidget {
  const _OnsetNoteField({required this.initialValue, required this.onChanged});

  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  State<_OnsetNoteField> createState() => _OnsetNoteFieldState();
}

class _OnsetNoteFieldState extends State<_OnsetNoteField> {
  Timer? _debounce;
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      maxLength: 500,
      maxLines: 3,
      decoration: const InputDecoration(
        labelText: 'Anything else to tell the nurse? (optional)',
        border: OutlineInputBorder(),
      ),
      onChanged: (value) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 600), () {
          widget.onChanged(value);
        });
      },
    );
  }
}

/// One selectable worry / pre-care option chip — pill-shaped, navy fill on
/// selection, with button + selected semantics.
class _ConcernChip extends StatelessWidget {
  const _ConcernChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          splashColor: AppColors.checkBlue.withValues(alpha: 0.12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppColors.checkNavy : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? AppColors.checkNavy
                    : AppColors.checkNavy.withValues(alpha: 0.25),
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? Colors.white : AppColors.checkBlue,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : AppColors.checkNavy,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A single-select option row for the duration screen.
class _SelectChip extends StatelessWidget {
  const _SelectChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? AppColors.checkNavy : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? AppColors.checkNavy
                  : AppColors.checkNavy.withValues(alpha: 0.25),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? Colors.white : AppColors.checkBlue,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.checkNavy,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.check_rounded, size: 20, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _concernIcon(String key) => switch (key) {
  'hot' || 'fever' => Icons.thermostat_rounded,
  'feeding' || 'drinking' => Icons.local_drink_rounded,
  'breathing' => Icons.air_rounded,
  'fits' => Icons.bolt_rounded,
  'sleepy' => Icons.bedtime_rounded,
  'yellow' || 'discharge' => Icons.opacity_rounded,
  'cord' => Icons.healing_rounded,
  'vomiting' => Icons.sick_rounded,
  'blood' => Icons.bloodtype_rounded,
  'thin' => Icons.monitor_weight_outlined,
  'bleeding' => Icons.water_drop_rounded,
  'headache' => Icons.visibility_rounded,
  'pain' => Icons.emergency_rounded,
  'movement' => Icons.pregnant_woman_rounded,
  _ => Icons.help_outline_rounded,
};

String _durationPhrase(String? key) =>
    CaregiverDuration.byKey(key)?.label.toLowerCase() ?? 'today';

/// Premium answer button — navy border, fills navy on selection with blue
/// glow. Semantics + ink ripple so assistive tech and a worried thumb both
/// get confirmation.
class _PremiumAnswerButton extends StatelessWidget {
  const _PremiumAnswerButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: AppColors.checkBlue.withValues(alpha: 0.15),
          highlightColor: AppColors.checkBlue.withValues(alpha: 0.08),
          child: Ink(
            decoration: BoxDecoration(
              color: selected ? AppColors.checkNavy : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? AppColors.checkNavy
                    : AppColors.checkNavy.withValues(alpha: 0.3),
                width: selected ? 2 : 1.5,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.checkBlue.withValues(alpha: 0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : const [],
            ),
            child: Container(
              height: 72,
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 24,
                    color: selected ? Colors.white : AppColors.checkNavy,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: selected ? Colors.white : AppColors.checkNavy,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.triageAmberBg,
        borderRadius: BorderRadius.circular(Gap.radius),
        border: Border.all(
          color: AppColors.triageAmber.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 20,
            color: AppColors.triageAmber,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: AppColors.ink,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerdictHero extends StatelessWidget {
  const _VerdictHero({
    required this.personName,
    required this.title,
    required this.verdictColor,
    required this.verdictIcon,
  });

  final String personName;
  final String title;
  final Color verdictColor;
  final IconData verdictIcon;

  @override
  Widget build(BuildContext context) {
    final isUrgent = verdictColor == AppColors.triageRed;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: isUrgent
            ? AppColors.checkUrgentGradient
            : AppColors.checkButtonGradient,
        boxShadow: [
          BoxShadow(
            color: (isUrgent ? AppColors.triageRed : AppColors.checkBlue)
                .withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(verdictIcon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  personName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The advice card with the found signs and, where it adds information, the
/// one-line verdict word.
class _AdviceCard extends StatelessWidget {
  const _AdviceCard({
    required this.advice,
    required this.yesSigns,
    required this.chip,
  });

  final String advice;
  final List<String> yesSigns;
  final String? chip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.checkSilver, width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.checkNavyDeep.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (chip != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.checkBlueTint,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                chip!,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.checkBlue,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            advice,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppColors.ink,
              height: 1.5,
            ),
          ),
          if (yesSigns.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.checkBlue.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SIGNS FOUND',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: AppColors.checkNavy,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final sign in yesSigns)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            size: 14,
                            color: AppColors.triageRed,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              sign,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionStepsCard extends StatelessWidget {
  const _ActionStepsCard({
    required this.routine,
    required this.verdictColor,
    required this.steps,
    required this.report,
    required this.personId,
  });

  final bool routine;
  final Color verdictColor;
  final Map<String, String> steps;
  final HomeCheck? report;
  final String personId;

  @override
  Widget build(BuildContext context) {
    return CompanionCard(
      title: routine ? 'Keep doing these' : 'Do these now \u2014 even on the way',
      eyebrow: routine ? 'ROUTINE' : 'ACTION STEPS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < steps.entries.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            Builder(builder: (_) {
              final entry = steps.entries.elementAt(i);
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.checkSilver, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.checkNavyDeep.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 4,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.checkBlue,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: AppColors.checkNavy,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            fontFamily: 'Sora',
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (report != null)
                              CaregiverTaskToggle(
                                personId: personId,
                                kind: CaregiverActivityKind.preparation,
                                sourceId: report!.id,
                                itemKey: entry.key,
                                occurrenceKey: report!.id,
                                label: entry.value,
                              )
                            else
                              Text(
                                entry.value,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.checkNavy,
                                  height: 1.45,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

/// Step 4 of the realistic journey, for urgent verdicts: the journey to the
/// facility as a plan she can execute — the bag, the ride, the person — not
/// a paragraph of advice. Night travel changes the first move.
class _GettingThereCard extends ConsumerWidget {
  const _GettingThereCard({required this.report});

  final HomeCheck report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(caregiverClockProvider)();
    final isNight = now.hour >= 19 || now.hour < 6;
    final walking =
        ref
            .watch(householdProvider(report.householdId))
            .valueOrNull
            ?.walkingMinutesToFacility;
    const prepItems = [
      ('prep-book', 'Health record book'),
      ('prep-nhis', 'NHIS card'),
      ('prep-water', 'Water and a small cloth'),
      ('prep-money', 'Money for transport and medicine'),
      ('prep-company', 'Someone to come with you'),
    ];
    return CompanionCard(
      title: isNight ? 'Getting there \u2014 it is night' : 'Getting there',
      eyebrow: isNight ? 'GO NOW \u2014 CALL AHEAD' : 'THE PLAN',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isNight)
            const Text(
              'It is night. Call 112 first, and go with two people — do not '
              'travel alone in the dark.',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.triageRed,
                height: 1.4,
              ),
            ),
          if (walking != null) ...[
            const SizedBox(height: 8),
            Text(
              walking >= 60
                  ? 'The facility is about ${walking ~/ 60} hour${walking >= 120 ? 's' : ''}\u2019 walk away \u2014 arrange a ride and phone ahead now.'
                  : 'The facility is about $walking minutes\u2019 walk away.',
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.inkMuted,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Tick as you gather. The nurse will ask for these.',
            style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 8),
          for (final (key, label) in prepItems)
            CaregiverTaskToggle(
              personId: report.personId,
              kind: CaregiverActivityKind.preparation,
              sourceId: report.id,
              itemKey: key,
              occurrenceKey: report.id,
              label: label,
            ),
          const SizedBox(height: 12),
          _RideField(report: report),
        ],
      ),
    );
  }
}

/// "Who will take you?" — naming the person turns a scary abstract
/// instruction into a social plan. Saved as a note on the check.
class _RideField extends ConsumerStatefulWidget {
  const _RideField({required this.report});

  final HomeCheck report;

  @override
  ConsumerState<_RideField> createState() => _RideFieldState();
}

class _RideFieldState extends ConsumerState<_RideField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(caregiverScopeProvider);
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _controller,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Who will take you?',
              hintText: 'e.g. Musah, her father',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onFieldSubmitted: (name) {
              final trimmed = name.trim();
              if (scope == null || trimmed.isEmpty) return;
              final writer = ref.read(caregiverWriterProvider(scope));
              writer.activity(
                writer.entry(
                  kind: CaregiverActivityKind.preparation,
                  personId: widget.report.personId,
                  sourceId: widget.report.id,
                  itemKey: 'ride-with',
                  occurrenceKey: widget.report.id,
                  note: 'Ride arranged with $trimmed',
                ),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Ride noted: $trimmed'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Step 5 of the realistic journey: the caregiver's first instinct is to
/// tell a person, not an app. This opens her OWN messaging app with the
/// nurse message ready — CareBridge sends nothing itself, and says so.
class _TellSomeoneCard extends ConsumerWidget {
  const _TellSomeoneCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(caregiverScopeProvider);
    if (scope == null) return const SizedBox.shrink();
    final contacts =
        ref
            .watch(caregiverSettingsProvider(scope))
            .valueOrNull
            ?.contacts
            .where(
              (c) =>
                  c.kind == SupportContactKind.healthWorker ||
                  c.kind == SupportContactKind.trustedPerson,
            )
            .toList() ??
        const [];
    return CompanionCard(
      title: 'Tell your health worker',
      eyebrow: 'THERE IS A PERSON BEHIND THIS ADVICE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (contacts.isEmpty)
            const Text(
              'No health worker contact saved yet. Add one under the Help '
              'tab \u2014 then the words for the nurse below can go straight '
              'to them from here.',
              style: TextStyle(fontSize: 13.5, height: 1.45),
            )
          else ...[
            const Text(
              'CareBridge sends nothing itself \u2014 this opens your own '
              'messages with the words ready. Sending never replaces going: '
              'if the verdict says go, go.',
              style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
            ),
            const SizedBox(height: 12),
            for (final contact in contacts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.checkBlueTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${contact.name} \u2022 ${contact.kind == SupportContactKind.healthWorker ? 'health worker' : 'trusted person'}',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.checkNavy,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _SendButton(
                            label: 'WhatsApp',
                            icon: Icons.chat_rounded,
                            onTap: () => _launch(
                              context,
                              'https://wa.me/${contact.number.replaceAll(RegExp(r'[^0-9]'), '')}?text=${Uri.encodeComponent(message)}',
                            ),
                          ),
                          _SendButton(
                            label: 'Text',
                            icon: Icons.sms_rounded,
                            onTap: () => _launch(
                              context,
                              'sms:${contact.number.replaceAll(RegExp(r'[^0-9+]'), '')}?body=${Uri.encodeComponent(message)}',
                            ),
                          ),
                          _SendButton(
                            label: 'Call',
                            icon: Icons.call_rounded,
                            onTap: () => caregiverDial(context, contact.number),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.checkNavy,
          side: const BorderSide(color: AppColors.checkNavy, width: 1.2),
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        icon: Icon(icon, size: 16),
        label: Text(
          label,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

Future<void> _launch(BuildContext context, String uri) async {
  try {
    final ok = await launchUrl(
      Uri.parse(uri),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open messaging on this phone.')),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open messaging on this phone.')),
      );
    }
  }
}

/// Step 6 of the realistic journey: what "watch" actually means — one
/// concrete cue per sign she was unsure about, plus the promise she can
/// make to re-check tomorrow. The hours after guidance are where children
/// are lost.
class _WatchCard extends ConsumerWidget {
  const _WatchCard({required this.check, required this.routine});

  final CaregiverCheckController check;
  final bool routine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unsureSigns = [
      for (final q in check.questions!.questions)
        if (check.draft!.answers[q.key] == CaregiverAnswer.unsure)
          (q, CaregiverCheckPolicy.watchCue(q.key)),
    ];
    return CompanionCard(
      title: routine ? 'Watch for these' : 'While you arrange the visit',
      eyebrow: 'WHAT WATCHING MEANS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (unsureSigns.isEmpty)
            const Text(
              'You answered every sign clearly. If anything new appears '
              'before the visit, go to the facility the same day.',
              style: TextStyle(fontSize: 14, height: 1.45),
            )
          else ...[
            const Text(
              'You were not sure about these. Here is exactly what to look '
              'for at home:',
              style: TextStyle(fontSize: 14, height: 1.45),
            ),
            const SizedBox(height: 12),
            for (final (question, cue) in unsureSigns)
              if (cue != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.visibility_outlined,
                        size: 16,
                        color: AppColors.checkBlue,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${question.label.replaceAll('Is ', '').replaceAll('?', '')} \u2014 $cue',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                            color: AppColors.checkNavy,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
          const SizedBox(height: 8),
          if (check.report != null)
            CaregiverTaskToggle(
              personId: check.person.id,
              kind: CaregiverActivityKind.dailyTask,
              sourceId: check.report!.id,
              itemKey: 'recheck',
              occurrenceKey: caregiverDateKey(
                check.clock().add(const Duration(days: 1)),
              ),
              label:
                  'I will check ${check.person.fullName.split(' ').first} again tomorrow',
            ),
        ],
      ),
    );
  }
}

/// Routine-verdict promise: the same tomorrow-check ritual, without the
/// worry framing.
class _RecheckPromiseCard extends ConsumerWidget {
  const _RecheckPromiseCard({required this.report});

  final HomeCheck report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clock = ref.watch(caregiverClockProvider);
    return CompanionCard(
      title: 'Check again tomorrow',
      eyebrow: 'THE HABIT THAT CATCHES THINGS EARLY',
      child: CaregiverTaskToggle(
        personId: report.personId,
        kind: CaregiverActivityKind.dailyTask,
        sourceId: report.id,
        itemKey: 'recheck',
        occurrenceKey: caregiverDateKey(clock().add(const Duration(days: 1))),
        label: 'I will check again tomorrow',
      ),
    );
  }
}

class _NurseMessageCard extends StatelessWidget {
  const _NurseMessageCard({
    required this.message,
    required this.speech,
    required this.onCopy,
  });

  final String message;
  final CaregiverSpeech speech;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return CompanionCard(
      title: 'Your words for the nurse',
      eyebrow: 'SHOW THIS AT THE CLINIC',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.checkBlueTint,
              borderRadius: BorderRadius.circular(Gap.radius),
            ),
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                height: 1.5,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 14),
          CaregiverListen(
            speech: speech,
            label: 'Hear urgency and reported signs',
          ),
          const SizedBox(height: 8),
          const Text(
            'This short audio covers urgency and reported signs only. Show the written name, notes and full guidance to the health worker.',
            style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onCopy,
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy the words'),
          ),
        ],
      ),
    );
  }
}

class _ObservationsCard extends StatelessWidget {
  const _ObservationsCard({
    required this.questions,
    required this.answers,
    required this.startedAt,
    this.durationKey,
    this.givenCare = const {},
  });

  final List<CaregiverQuestion> questions;
  final Map<String, CaregiverAnswer> answers;
  final DateTime startedAt;
  final String? durationKey;
  final Set<String> givenCare;

  @override
  Widget build(BuildContext context) {
    final duration = CaregiverDuration.byKey(durationKey);
    final given = [
      for (final key in givenCare)
        if (CaregiverGivenCare.byKey(key) != null)
          CaregiverGivenCare.byKey(key)!.label,
    ];
    return CompanionCard(
      title: 'Your recorded observations',
      eyebrow: 'WHAT YOU ANSWERED',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Original check: ${caregiverWhen(startedAt)}',
            style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
          ),
          if (duration != null)
            Text(
              'Started: ${duration.label}',
              style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
            ),
          if (given.isNotEmpty)
            Text(
              'Already given: ${given.join(', ')}',
              style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
            ),
          const SizedBox(height: 12),
          for (final q in questions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: switch (answers[q.key]) {
                        CaregiverAnswer.yes => AppColors.triageRed,
                        CaregiverAnswer.unsure => AppColors.triageAmber,
                        _ => AppColors.triageGreen,
                      },
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${q.label} \u2014 ${_answerLabel(answers[q.key])}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _answerLabel(CaregiverAnswer? answer) => switch (answer) {
  CaregiverAnswer.yes => 'YES',
  CaregiverAnswer.no => 'NO',
  CaregiverAnswer.unsure => 'Not sure',
  null => 'Unanswered',
};
