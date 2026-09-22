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

  /// The speech language for this check session. It starts as the account's
  /// own preference and only changes when she picks another one from the word
  /// rail — the play button never interrupts her with a question.
  String? _speechLanguage;
  bool _railOpen = false;
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
      language: _voiceLanguage,
      clipId: id,
    );
  }

  /// The language this check speaks in: her pick for the session, otherwise
  /// the language already on her account.
  String get _voiceLanguage => OfflineSpeechLanguage.resolve(
    temporary: _speechLanguage,
    account: ref.read(narrationLanguageProvider),
  );

  bool get _canSpeak => mounted &&
      (ModalRoute.of(context)?.isCurrent ?? true) && TickerMode.valuesOf(context).enabled &&
      (WidgetsBinding.instance.lifecycleState == null ||
       WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!(ModalRoute.isCurrentOf(context) ?? true) || !TickerMode.valuesOf(context).enabled) {
      _voice?.stop(notify: false);
    }
  }

  void _resetNarration() {
    _spokenKey = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _check != null) _changed();
    });
  }

  Future<void> _listenToQuestion(CaregiverCheckController check) async {
    final voice = _voice;
    if (voice == null) return;
    if (voice.active) {
      voice.stop();
      return;
    }
    // Tap always means "say it", in the language she already has. Changing
    // language is a separate, visible control — never a question asked by the
    // play button.
    await _speakQuestion(check, _voiceLanguage);
  }

  Future<void> _speakQuestion(
    CaregiverCheckController check,
    String language,
  ) async {
    final voice = _voice;
    if (voice == null) return;
    final speech = _questionSpeech(check);
    final scope = ref.read(caregiverScopeProvider);
    final user = ref.read(currentUserProvider);
    if (!_canSpeak ||
        _check != check ||
        ref.read(caregiverScopeProvider) != scope ||
        ref.read(currentUserProvider) != user ||
        check.stage != CaregiverCheckStage.questions ||
        _questionSpeech(check).id != speech.id) {
      return;
    }
    setState(() => _speechLanguage = language);
    await voice.play(speech.withLanguage(language));
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
    final speechKey = '${speech.id}/${speech.language}/${speech.english}';
    if (_spokenKey == speechKey) return;
    _spokenKey = speechKey;
    _voice?.stop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_canSpeak ||
          _check != check ||
          check.stage != CaregiverCheckStage.questions ||
          _spokenKey != speechKey) {
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
        heroChrome: false,
        child: Center(
          child: Text('Reopen the check from your current family.'),
        ),
      );
    }
    _voice = ref.watch(caregiverVoiceProvider(scope));
    ref.listen(narrationLanguageProvider, (_, _) {
      _speechLanguage = null;
      _voice?.stop();
      _resetNarration();
    });
    ref.listen(caregiverSettingsProvider(scope).select((value) => value.valueOrNull?.autoRead), (_, next) {
      if (next != true) _voice?.stop();
      _resetNarration();
    });
    ref.watch(caregiverSettingsProvider(scope));
    final check = _check;
    return CompanionPage(
      title: check == null
          ? 'Who are you checking?'
          : switch (check.stage) {
              CaregiverCheckStage.result => 'What to do now',
              CaregiverCheckStage.questions =>
                check.needsConcerns
                    ? 'What is worrying you?'
                    : 'What have you noticed?',
              CaregiverCheckStage.duration => 'How long has it been like this?',
              CaregiverCheckStage.context => 'Before you see the nurse',
              _ => 'Danger-sign check',
            },
      // The check opens with its own navy hero card; a gradient bar above it
      // would stack two blue bands.
      heroChrome: false,
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
              CaregiverCheckStage.loadFailed => _blocked(check),
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
                CaregiverPersonCard(person: person, onTap: () => _pick(person)),
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

  void _chooseSomeoneElse() {
    _voice?.stop();
    _check?.removeListener(_changed);
    _check?.dispose();
    setState(() => _check = null);
  }

  /// The person is outside the check's scope, or their saved answers could
  /// not be read. Either way the caregiver needs the specific reason, what
  /// the record actually says, and a way forward — a paragraph and a "Get
  /// help" button reads as a broken app.
  Widget _blocked(CaregiverCheckController check) =>
      check.stage == CaregiverCheckStage.loadFailed
      ? _loadFailed(check)
      : _outOfScope(check);

  Widget _outOfScope(CaregiverCheckController check) {
    final person = check.person;
    final reason =
        check.blockReason ??
        const (
          headline: 'This check cannot cover them yet',
          detail:
              'The danger-sign check covers children under five, pregnancy, '
              'and the six weeks after birth.',
        );
    final dob = person.dateOfBirth;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _BlockedHero(headline: reason.headline, detail: reason.detail),
        const SizedBox(height: 16),
        CompanionCard(
          title: 'What the record says',
          eyebrow: 'THE RECORD',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RecordRow(label: 'Name', value: person.fullName),
              _RecordRow(label: 'Recorded as', value: person.clientType.label),
              _RecordRow(
                label: 'Birth date',
                value: dob == null ? 'Not recorded' : caregiverDateLabel(dob),
                missing: dob == null,
              ),
              _RecordRow(label: 'Age', value: caregiverAge(person)),
            ],
          ),
        ),
        CompanionCard(
          title: 'Who this check is for',
          eyebrow: 'COVERAGE',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [
              _CoverRow('A child under five, with a birth date on the record'),
              _CoverRow('A woman recorded as pregnant'),
              _CoverRow('A mother in the six weeks after giving birth'),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: _chooseSomeoneElse,
          icon: const Icon(Icons.groups_rounded),
          label: const Text('Check someone else'),
        ),
        const SizedBox(height: 12),
        CaregiverAddMemberButton(householdId: widget.householdId),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => showCaregiverEmergency(context),
          icon: const Icon(Icons.emergency_outlined),
          label: const Text('Emergency — do not wait for a check'),
        ),
        const SizedBox(height: 16),
        Text(
          'Nothing was saved. No danger-sign check was done and no health '
          'conclusion has been made for ${person.fullName}.',
          style: caregiverBody(
            size: 12.5,
            height: 1.45,
            color: CompanionColors.muted,
          ),
        ),
      ],
    );
  }

  Widget _loadFailed(CaregiverCheckController check) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      _BlockedHero(
        headline: 'Saved answers could not be read',
        detail:
            '${check.notice ?? 'This phone holds the answers, not the network.'} '
            'The check can start again from the first question.',
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: () => unawaited(check.load()),
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Try reading them again'),
      ),
      const SizedBox(height: 12),
      CaregiverSaveAction(label: 'Start a new check', onSave: check.startNew),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _chooseSomeoneElse,
        icon: const Icon(Icons.groups_rounded),
        label: const Text('Check someone else'),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () => showCaregiverEmergency(context),
        icon: const Icon(Icons.emergency_outlined),
        label: const Text('Emergency — do not wait for a check'),
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
            TextButton(onPressed: check.retry, child: const Text('Retry')),
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
            'If a danger sign comes up, the screen turns red and tells you — '
            'then you decide whether to go now or finish the check first.',
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

  /// The alarm belongs to the check, not to the question screen: once she
  /// leaves the battery, the way out has to travel with her.
  Widget _alarm(CaregiverCheckController check) => _DangerAlarm(
    signs: check.signsNoticed,
    remaining: check.remainingQuestions,
    onAct: () {
      _voice?.stop();
      check.stopForVerdict();
    },
  );

  Widget _questions(CaregiverCheckController check) {
    final draft = check.draft!;
    final questions = check.questions!.questions;
    final index = draft.questionIndex;
    final question = questions[index];
    final answered = draft.answers[question.key];
    final speech = _questionSpeech(check);
    final language = _voiceLanguage;
    final localized = language == 'English'
        ? null
        : speech.withLanguage(language).localizedText;
    final answeredTicks = {
      for (var i = 0; i < questions.length; i++)
        if (draft.answers[questions[i].key] != null) i,
    };
    final noticedTicks = {
      for (var i = 0; i < questions.length; i++)
        if (draft.answers[questions[i].key] == CaregiverAnswer.yes) i,
    };
    return ListView(
      key: ValueKey('question:$index'),
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 28),
      children: [
        _QuestionHero(
          index: index,
          total: questions.length,
          answered: answeredTicks,
          noticed: noticedTicks,
          personName: check.person.fullName,
          question: question.label,
          speech: speech,
          language: language,
          localized: localized,
          playing: _voice?.active ?? false,
          railOpen: _railOpen,
          onOpenRail: () => setState(() => _railOpen = !_railOpen),
          onSpeak: () => unawaited(_listenToQuestion(check)),
          onLanguage: (chosen) {
            setState(() => _railOpen = false);
            unawaited(_speakQuestion(check, chosen));
          },
          onPrevious: index == 0
              ? null
              : () {
                  _voice?.stop();
                  check.back();
                },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (check.alarmRaised) ...[
                _alarm(check),
                const SizedBox(height: 16),
              ],
              if (check.notice != null) ...[
                _NoticeBanner(message: check.notice!),
                const SizedBox(height: 16),
              ],
              _AnswerDeck(
                answered: answered,
                continueLabel: index == questions.length - 1
                    ? 'Continue — almost done'
                    : 'Continue',
                onAnswer: (answer) {
                  _voice?.stop();
                  check.answer(question.key, answer);
                },
                onContinue: () {
                  _voice?.stop();
                  check.next();
                },
              ),
              const SizedBox(height: 18),
              _saveStatus(check),
              const SizedBox(height: 14),
              Text(
                check.alarmRaised
                    ? 'The alarm stays while you finish. Nothing is taken '
                          'away from you, and nothing is decided for you.'
                    : 'Everything waits for you — you control the pace. A '
                          'danger sign raises an alarm you can act on at once; '
                          'it does not end the check. These are your '
                          'observations, not an examination.',
                style: caregiverBody(
                  size: 12.5,
                  height: 1.5,
                  color: CompanionColors.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------- Step 2: how long has it been

  Widget _duration(CaregiverCheckController check) {
    final selected = check.draft!.durationKey;
    return _CheckStepScaffold(
      progressLabel: check.alarmRaised ? 'ALMOST DONE' : 'LAST STEP',
      personName: check.person.fullName,
      alarm: check.alarmRaised ? _alarm(check) : null,
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
            style: TextButton.styleFrom(foregroundColor: AppColors.checkNavy),
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
      alarm: check.alarmRaised ? _alarm(check) : null,
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
            style: TextButton.styleFrom(foregroundColor: AppColors.inkMuted),
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
    final first = check.person.fullName
        .split(' ')
        .first
        .replaceFirstMapped(
          RegExp(r'^[a-z]'),
          (m) => m.group(0)!.toUpperCase(),
        );
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
    final nurseMsg =
        'For ${check.person.fullName}. ${observations.english}'
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
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
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
              children: [adviceCard, const SizedBox(height: 12), stepsCard],
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
          '${check.draft!.durationKey == null ? '' : ' — started ${_durationPhrase(check.draft!.durationKey)}'}',
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.inkMuted,
          ),
        ),
        const SizedBox(height: 12),
        // The verdict in her own words: this listen is wired to the
        // registered verdict clip in the speech bank, so Twi, Dagbani and
        // Hausa speakers hear the one sentence that matters in their
        // language — reviewed wording, not machine output.
        if (_verdictClipId(check.decision) != null)
          CaregiverListen(
            label: 'Hear the verdict in your language',
            speech: CaregiverSpeech(
              id: 'check_verdict:${check.draft!.id}',
              english: SpeechBank.byId(
                _verdictClipId(check.decision)!,
              )!.english,
              language: language,
              clipId: _verdictClipId(check.decision),
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
        CompanionCard(title: 'Feeding and comfort', child: Text(feedingAdvice)),
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
        CaregiverSaveAction(label: 'Start a new check', onSave: check.startNew),
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
        'book':
            'Carry the health record book \u2014 the nurse will ask for it.',
        'ride':
            'Arrange a ride now. A neighbour\u2019s motorbike is fine \u2014 do not wait for a better one.',
        'feed': mother
            ? 'If she can swallow, give sips of water. If not, do not force anything by mouth.'
            : 'If $first can swallow, keep breastfeeding or give sips of fluid. If not, do not force anything by mouth.',
        'company':
            'Go with someone if you can \u2014 a second person helps to carry and to explain.',
        'words':
            'At the gate, say what you noticed and when it started \u2014 or show the message above.',
      };
    }
    return {
      'see':
          'Show $first to your health worker or CHPS compound today \u2014 do not wait for the next scheduled visit.',
      'watch':
          'Watch morning and evening. If any danger sign appears, go to the facility the same day.',
      'feed':
          'Keep feeding and drinking as normal \u2014 small amounts, often.',
      'note': 'Remember when each sign started \u2014 the nurse will ask.',
    };
  }
}

/// Shared scaffold for the worry, duration and pre-care screens: the same navy
/// band the questions open with, then one calm white card.
class _CheckStepScaffold extends StatelessWidget {
  const _CheckStepScaffold({
    required this.progressLabel,
    required this.personName,
    required this.child,
    this.alarm,
  });

  final String progressLabel;
  final String personName;
  final Widget child;

  /// The danger-sign alarm rides above the step card, so a family that is
  /// part-way through a serious check never loses the way out.
  final Widget? alarm;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
      children: [
        _StepBand(label: progressLabel, personName: personName),
        if (alarm != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: alarm!,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.checkNavy.withValues(alpha: 0.07),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.checkNavyDeep.withValues(alpha: 0.08),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}

/// The navy band that opens every non-question step, so the check reads as one
/// system rather than a hero screen followed by plain cards.
class _StepBand extends StatelessWidget {
  const _StepBand({required this.label, required this.personName});

  final String label;
  final String personName;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.checkNavyDeep,
          AppColors.checkNavy,
          AppColors.checkNavyMid,
        ],
        stops: [0, 0.58, 1],
      ),
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      boxShadow: [
        BoxShadow(
          color: AppColors.checkNavyDeep.withValues(alpha: 0.3),
          blurRadius: 26,
          offset: const Offset(0, 12),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: Stack(
      children: [
        Positioned(
          top: -88,
          right: -58,
          child: _Glow(210, AppColors.checkBlue, 0.45),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 26),
          child: Row(
            children: [
              Flexible(child: _GlassPill(label: label)),
              const SizedBox(width: 8),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _PersonChip(name: personName),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
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
  const _GivenCarePicker({
    required this.initial,
    required this.onDone,
    required this.onSkip,
  });

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

/// The registered verdict clip for a decision, or null when the decision
/// cannot produce a verdict.
String? _verdictClipId(CaregiverCheckDecision decision) => switch (decision) {
  CaregiverCheckDecision.urgent => 'caregiver_verdict_urgent',
  CaregiverCheckDecision.contactToday => 'caregiver_verdict_caution',
  CaregiverCheckDecision.routine => 'caregiver_verdict_fine',
  _ => null,
};

/// The question stage: a full-bleed navy panel that owns the reading — the
/// question, the voice control and the word-first language rail — so the
/// answer tiles below never compete with the words for the same white card.
class _QuestionHero extends StatelessWidget {
  const _QuestionHero({
    required this.index,
    required this.total,
    required this.answered,
    required this.noticed,
    required this.personName,
    required this.question,
    required this.speech,
    required this.language,
    required this.localized,
    required this.playing,
    required this.railOpen,
    required this.onOpenRail,
    required this.onSpeak,
    required this.onLanguage,
    this.onPrevious,
  });

  final int index;
  final int total;

  /// Which positions she has answered, and which of those are a YES, so the
  /// progress bar can show the picture filling in as she goes.
  final Set<int> answered;
  final Set<int> noticed;
  final String personName;
  final String question;
  final CaregiverSpeech speech;
  final String language;
  final String? localized;
  final bool playing;
  final bool railOpen;
  final VoidCallback onOpenRail;
  final VoidCallback onSpeak;
  final ValueChanged<String> onLanguage;
  final VoidCallback? onPrevious;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.checkNavyDeep,
            AppColors.checkNavy,
            AppColors.checkNavyMid,
          ],
          stops: [0, 0.58, 1],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: AppColors.checkNavyDeep.withValues(alpha: 0.32),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            top: -96,
            right: -64,
            child: _Glow(230, AppColors.checkBlue, 0.5),
          ),
          Positioned(
            bottom: -120,
            left: -78,
            child: _Glow(250, AppColors.checkBlueLight, 0.24),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (onPrevious != null) ...[
                      _GlassButton(
                        icon: Icons.chevron_left_rounded,
                        tooltip: 'Previous question',
                        onTap: onPrevious!,
                      ),
                      const SizedBox(width: 10),
                    ],
                    Flexible(
                      child: _GlassPill(
                        label: 'QUESTION ${index + 1} OF $total',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _PersonChip(name: personName),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _ProgressTicks(
                  index: index,
                  total: total,
                  answered: answered,
                  noticed: noticed,
                ),
                const SizedBox(height: 24),
                AnimatedSwitcher(
                  duration: reduced
                      ? Duration.zero
                      : const Duration(milliseconds: 340),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.10),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Text(
                    key: ValueKey(question),
                    question,
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      height: 1.18,
                      letterSpacing: -0.5,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (localized != null) ...[
                  const SizedBox(height: 16),
                  _GlassQuote(language: language, words: localized!),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    _PlayDial(playing: playing, onTap: onSpeak),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            playing ? 'Playing…' : 'Hear this question',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            playing
                                ? 'Tap the button to stop'
                                : 'Spoken on this phone, in $language',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.66),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _GlassButton(
                      icon: railOpen
                          ? Icons.close_rounded
                          : Icons.translate_rounded,
                      tooltip: railOpen
                          ? 'Close the language list'
                          : 'Read this in another language',
                      onTap: onOpenRail,
                      active: railOpen,
                    ),
                  ],
                ),
                if (railOpen) ...[
                  const SizedBox(height: 16),
                  SpeechLanguageRail(
                    speech: speech,
                    selected: language,
                    onSelected: onLanguage,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Each card shows the words that language can give for '
                    'this question. Tap one and it reads it out.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A soft radial light on the navy — depth without decoration.
class _Glow extends StatelessWidget {
  const _Glow(this.size, this.color, this.opacity);

  final double size;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [
          color.withValues(alpha: opacity),
          color.withValues(alpha: 0),
        ],
      ),
    ),
  );
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: Colors.white,
      ),
    ),
  );
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: active ? Colors.white : Colors.white.withValues(alpha: 0.13),
      shape: const CircleBorder(
        side: BorderSide(color: Color(0x38FFFFFF), width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            size: 21,
            color: active ? AppColors.checkNavy : Colors.white,
          ),
        ),
      ),
    ),
  );
}

class _PersonChip extends StatelessWidget {
  const _PersonChip({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
          ),
          child: Text(
            initial,
            style: const TextStyle(
              fontFamily: 'Sora',
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.86),
            ),
          ),
        ),
      ],
    );
  }
}

/// One tick per question: answered, current, still to come. A rail of ticks
/// tells her how much is left faster than a bar does.
class _ProgressTicks extends StatelessWidget {
  const _ProgressTicks({
    required this.index,
    required this.total,
    required this.answered,
    required this.noticed,
  });

  final int index;
  final int total;

  /// Question positions she has answered, and the ones answered YES — so the
  /// bar shows a picture being filled in, not a countdown to a verdict.
  final Set<int> answered;
  final Set<int> noticed;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Row(
      children: [
        for (var tick = 0; tick < total; tick++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: tick == total - 1 ? 0 : 4),
              child: AnimatedContainer(
                duration: reduced
                    ? Duration.zero
                    : const Duration(milliseconds: 280),
                curve: Curves.easeOut,
                height: tick == index ? 6 : 4,
                decoration: BoxDecoration(
                  color: noticed.contains(tick)
                      ? AppColors.triageRed
                      : tick == index
                      ? Colors.white
                      : answered.contains(tick)
                      ? Colors.white.withValues(alpha: 0.85)
                      : Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    if (tick == index)
                      BoxShadow(
                        color: AppColors.checkBlueLight.withValues(alpha: 0.75),
                        blurRadius: 10,
                      ),
                    if (noticed.contains(tick))
                      BoxShadow(
                        color: AppColors.triageRed.withValues(alpha: 0.8),
                        blurRadius: 10,
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The question in her language, sitting under the English so the two read as
/// one message rather than a translation footnote.
class _GlassQuote extends StatelessWidget {
  const _GlassQuote({required this.language, required this.words});

  final String language;
  final String words;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 11, 14, 13),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          language.toUpperCase(),
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          words,
          style: const TextStyle(
            fontSize: 15,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    ),
  );
}

/// The play control. It is a play button, so a tap plays — the language lives
/// on its own control beside it.
class _PlayDial extends StatelessWidget {
  const _PlayDial({required this.playing, required this.onTap});

  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return AnimatedScale(
      duration: reduced ? Duration.zero : const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      scale: playing ? 1.06 : 1,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                center: Alignment(-0.5, -0.6),
                colors: [AppColors.checkBlue, AppColors.checkNavyMid],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.35),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.checkBlue.withValues(
                    alpha: playing ? 0.6 : 0.32,
                  ),
                  blurRadius: playing ? 26 : 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(
              playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
              size: 30,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// The three answers plus the step control. The step control is never dead:
/// with no answer yet it asks for one and pulses the tiles instead of
/// greying out.
class _AnswerDeck extends StatefulWidget {
  const _AnswerDeck({
    required this.answered,
    required this.continueLabel,
    required this.onAnswer,
    required this.onContinue,
  });

  final CaregiverAnswer? answered;
  final String continueLabel;
  final ValueChanged<CaregiverAnswer> onAnswer;
  final VoidCallback onContinue;

  @override
  State<_AnswerDeck> createState() => _AnswerDeckState();
}

class _AnswerDeckState extends State<_AnswerDeck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final answered = widget.answered;
    final glow = Curves.easeOutSine.transform(
      _pulse.value < 0.5 ? _pulse.value * 2 : (1 - _pulse.value) * 2,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 18,
              height: 2,
              decoration: BoxDecoration(
                color: AppColors.checkBlue,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'YOUR ANSWER',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.3,
                color: CompanionColors.muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) => Transform.translate(
            offset: Offset(4 * glow * glow - 4 * glow, 0),
            child: child,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AnswerTile(
                label: 'Yes',
                hint: 'This is happening',
                icon: Icons.check_rounded,
                tone: AppColors.checkBlue,
                selected: answered == CaregiverAnswer.yes,
                onTap: () => widget.onAnswer(CaregiverAnswer.yes),
              ),
              const SizedBox(height: 12),
              _AnswerTile(
                label: 'No',
                hint: 'Not happening',
                icon: Icons.close_rounded,
                tone: AppColors.checkNavy,
                selected: answered == CaregiverAnswer.no,
                onTap: () => widget.onAnswer(CaregiverAnswer.no),
              ),
              const SizedBox(height: 12),
              _AnswerTile(
                label: 'Not sure',
                hint: 'I cannot tell',
                icon: Icons.help_rounded,
                tone: AppColors.caregiverMuted,
                selected: answered == CaregiverAnswer.unsure,
                onTap: () => widget.onAnswer(CaregiverAnswer.unsure),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (answered != null)
          PremiumCheckButton(
            label: widget.continueLabel,
            trailingIcon: Icons.arrow_forward_rounded,
            height: 58,
            onPressed: widget.onContinue,
          )
        else
          Material(
            color: AppColors.checkBlueTint,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                if (MediaQuery.disableAnimationsOf(context)) return;
                _pulse.forward(from: 0);
              },
              child: Container(
                height: 58,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.checkNavy.withValues(alpha: 0.14),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.touch_app_rounded,
                      size: 20,
                      color: AppColors.checkBlue,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Choose one to continue',
                        style: const TextStyle(
                          fontFamily: 'Sora',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.checkNavy,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 20,
                      color: AppColors.checkNavy,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One answer: a medallion, the word, what the word means, and a state ring.
class _AnswerTile extends StatelessWidget {
  const _AnswerTile({
    required this.label,
    required this.hint,
    required this.icon,
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String hint;
  final IconData icon;
  final Color tone;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          splashColor: AppColors.checkBlue.withValues(alpha: 0.12),
          child: AnimatedContainer(
            duration: reduced
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            // A floor, not a fixed height: at 200% text the answer and its
            // hint need the room, and a clipped answer is the worst place to
            // clip it.
            constraints: const BoxConstraints(minHeight: 78),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              gradient: selected
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.checkNavyDeep, AppColors.checkNavy],
                    )
                  : null,
              color: selected ? null : Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected
                    ? AppColors.checkNavy
                    : AppColors.checkNavy.withValues(alpha: 0.10),
                width: selected ? 1.4 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.checkNavyDeep.withValues(
                    alpha: selected ? 0.26 : 0.05,
                  ),
                  blurRadius: selected ? 22 : 12,
                  offset: Offset(0, selected ? 10 : 4),
                ),
              ],
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: reduced
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? Colors.white.withValues(alpha: 0.16)
                        : tone.withValues(alpha: 0.10),
                  ),
                  child: Icon(
                    icon,
                    size: 23,
                    color: selected ? Colors.white : tone,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontFamily: 'Sora',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: selected ? Colors.white : AppColors.checkNavy,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hint,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: selected
                              ? Colors.white.withValues(alpha: 0.78)
                              : CompanionColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedContainer(
                  duration: reduced
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? Colors.white
                          : AppColors.checkNavy.withValues(alpha: 0.22),
                      width: 1.8,
                    ),
                    color: selected
                        ? Colors.white.withValues(alpha: 0.14)
                        : null,
                  ),
                  child: selected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 17,
                          color: Colors.white,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The answer the check gives to a danger sign is not a screen change — it is
/// something she can act on. This band appears the moment a YES lands and stays
/// for the rest of the check: it names what she saw, keeps the remaining
/// questions in front of her because the nurse will ask them, and puts the way
/// out one tap away. Red is used because it means danger, never because it
/// looks urgent.
class _DangerAlarm extends StatelessWidget {
  const _DangerAlarm({
    required this.signs,
    required this.remaining,
    required this.onAct,
  });

  final List<String> signs;
  final int remaining;
  final VoidCallback onAct;

  static String _alarmBody(String named, int remaining) {
    final choice = remaining > 0
        ? 'Go now, or answer the $remaining '
              '${remaining == 1 ? "question" : "questions"} left first'
        : 'Go now, or finish what is left first';
    return 'You saw $named. $choice — the nurse will ask either way.';
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final seen = [
      for (final s in signs)
        '${s.substring(0, 1).toLowerCase()}${s.substring(1)}',
    ];
    final named = seen.length == 1
        ? seen.single
        : '${seen.take(seen.length - 1).join(', ')} and ${seen.last}';
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7C1A16), AppColors.triageRed],
          stops: [0, 0.82],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.triageRed.withValues(alpha: 0.30),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            top: -70,
            right: -46,
            child: _Glow(170, Colors.white, reduced ? 0.10 : 0.20),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.30),
                        ),
                      ),
                      child: const Icon(
                        Icons.emergency_share_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DANGER SIGN NOTED',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                              color: Colors.white.withValues(alpha: 0.78),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            signs.length == 1
                                ? 'This needs attention now.'
                                : '${signs.length} signs need attention now.',
                            style: const TextStyle(
                              fontFamily: 'Sora',
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _alarmBody(named, remaining),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.93),
                  ),
                ),
                const SizedBox(height: 14),
                Semantics(
                  button: true,
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: onAct,
                      child: SizedBox(
                        height: 52,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.directions_walk_rounded,
                              size: 20,
                              color: Color(0xFF7C1A16),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                remaining > 0
                                    ? 'Stop and see what to do'
                                    : 'See what to do now',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Sora',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF7C1A16),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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

/// The navy hero for a check that cannot go ahead. Same visual language as
/// the verdict hero, so a blocked screen still looks like the app rather
/// than an error dialog.
class _BlockedHero extends StatelessWidget {
  const _BlockedHero({required this.headline, required this.detail});

  final String headline;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      gradient: AppColors.checkHeroGradient,
      boxShadow: [
        BoxShadow(
          color: AppColors.checkNavyDeep.withValues(alpha: 0.18),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.info_outline_rounded,
            color: AppColors.checkBlue,
            size: 26,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                headline,
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                detail,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xE6FFFFFF),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// One line of the record the caregiver can compare against reality.
class _RecordRow extends StatelessWidget {
  const _RecordRow({
    required this.label,
    required this.value,
    this.missing = false,
  });

  final String label;
  final String value;
  final bool missing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: caregiverBody(
              size: 13,
              height: 1.35,
              color: CompanionColors.muted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: caregiverBody(
              size: 14.5,
              height: 1.35,
              color: missing ? AppColors.triageAmber : CompanionColors.ink,
            ),
          ),
        ),
      ],
    ),
  );
}

class _CoverRow extends StatelessWidget {
  const _CoverRow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.check_circle_outline_rounded,
          size: 18,
          color: AppColors.checkBlue,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: caregiverBody(size: 14, height: 1.4)),
        ),
      ],
    ),
  );
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

/// The plan she can work through. Each line is one tap, the thread between the
/// markers is the order, and the meter counts only what storage has confirmed —
/// so "3 of 4" means three things she can prove, not three things she meant to
/// do. The card itself stays plain: the steps are the content, and a box around
/// every step would bury them.
class _ActionStepsCard extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = report;
    final scope = ref.watch(caregiverScopeProvider);
    final entries = scope == null
        ? null
        : ref.watch(caregiverActivityProvider(scope)).valueOrNull;
    final done = saved == null || entries == null
        ? 0
        : entries
              .where(
                (a) =>
                    a.kind == CaregiverActivityKind.preparation &&
                    a.personId == personId &&
                    a.sourceId == saved.id &&
                    a.occurrenceKey == saved.id &&
                    a.done &&
                    steps.keys.contains(a.itemKey),
              )
              .length;
    final items = steps.entries.toList();

    return CompanionCard(
      title: routine
          ? 'Keep doing these'
          : 'Do these now \u2014 even on the way',
      eyebrow: routine ? 'ROUTINE' : 'ACTION STEPS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (saved != null) ...[
            _StepMeter(
              done: done,
              total: items.length,
              tone: verdictColor,
              routine: routine,
            ),
            const SizedBox(height: 14),
          ],
          for (var i = 0; i < items.length; i++)
            if (saved == null)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == items.length - 1 ? 0 : 10,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 5, right: 12),
                      child: Icon(
                        Icons.circle,
                        size: 7,
                        color: AppColors.checkBlueLight,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        items[i].value,
                        style: caregiverBody(size: 15, height: 1.45),
                      ),
                    ),
                  ],
                ),
              )
            else
              CaregiverTaskToggle(
                personId: personId,
                kind: CaregiverActivityKind.preparation,
                sourceId: saved.id,
                itemKey: items[i].key,
                occurrenceKey: saved.id,
                label: items[i].value,
                step: i + 1,
                totalSteps: items.length,
                tone: verdictColor,
              ),
        ],
      ),
    );
  }
}

/// Confirmed progress, in the verdict's own colour. Nothing moves until the
/// write lands, so the bar is a record rather than a reward.
class _StepMeter extends StatelessWidget {
  const _StepMeter({
    required this.done,
    required this.total,
    required this.tone,
    required this.routine,
  });

  final int done;
  final int total;
  final Color tone;
  final bool routine;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final allDone = total > 0 && done >= total;
    final fraction = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                allDone
                    ? (routine
                          ? 'All $total done — keep going tomorrow'
                          : 'All $total done — take them and go')
                    : '$done of $total done',
                style: TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 13,
                  fontWeight: allDone ? FontWeight.w800 : FontWeight.w700,
                  height: 1.3,
                  color: allDone
                      ? AppColors.checkNavy
                      : AppColors.caregiverFaded,
                ),
              ),
            ),
            if (allDone) Icon(Icons.verified_rounded, size: 18, color: tone),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Container(
            height: 7,
            color: AppColors.checkSilver,
            alignment: Alignment.centerLeft,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: fraction),
              duration: reduced
                  ? Duration.zero
                  : const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => FractionallySizedBox(
                widthFactor: value,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    gradient: LinearGradient(
                      colors: [tone.withValues(alpha: 0.75), tone],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
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
    final walking = ref
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
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.inkMuted,
                height: 1.4,
              ),
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
        const SnackBar(
          content: Text('Could not open messaging on this phone.'),
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open messaging on this phone.'),
        ),
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
