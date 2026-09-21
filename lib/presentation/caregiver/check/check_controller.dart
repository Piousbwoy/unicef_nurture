import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../data/repositories/care_repository.dart';
import '../../../domain/entities/caregiver.dart';
import '../../../domain/entities/core.dart';
import '../../../domain/entities/visit.dart';
import '../../../domain/services/caregiver_check_policy.dart';

enum CaregiverCheckStage {
  loading,
  resume,
  questions,
  duration,
  context,
  result,
  unsupported,
  loadFailed,
}

enum CaregiverSaveState { unsaved, saving, saved, failed }

/// Navigation never waits for storage. Writes are ordered and finalization uses
/// the same immutable session ID and original time on every retry.
class CaregiverCheckController extends ChangeNotifier {
  CaregiverCheckController({
    required this.repository,
    required this.user,
    required this.scope,
    required this.person,
    required this.clock,
    required this.isCurrent,
    required this.onSaved,
  });
  final CareRepository repository;
  final AppUser user;
  final CaregiverScope scope;
  Person person;
  final DateTime Function() clock;
  final bool Function() isCurrent;
  final VoidCallback onSaved;
  CaregiverCheckPolicy get policy => CaregiverCheckPolicy(clock: clock);
  CaregiverQuestionSet? questions;
  CaregiverDraft? draft;
  HomeCheck? report;
  CaregiverCheckStage stage = CaregiverCheckStage.loading;

  /// Set with [stage] when a person falls outside the check's scope — the
  /// blocked screen reads it instead of guessing at the cause.
  ({String headline, String detail})? blockReason;
  CaregiverSaveState saveState = CaregiverSaveState.unsaved;
  String? notice;
  Future<void> _tail = Future.value();
  int _revision = 0;
  bool _disposed = false;
  bool get _live => !_disposed && isCurrent();
  CaregiverCheckDecision get decision =>
      policy.decide(questions, draft?.answers ?? {});

  /// The danger signs she has already said YES to, in the order the battery
  /// asks them, in the short form an alarm can speak. The alarm names them so
  /// the check reads as building a picture rather than springing a verdict.
  List<String> get signsNoticed {
    final set = questions;
    final answers = draft?.answers;
    if (set == null || answers == null) return const [];
    return [
      for (final q in set.questions)
        if (answers[q.key] == CaregiverAnswer.yes)
          CaregiverCheckPolicy.shortSigns[q.key] ?? q.label,
    ];
  }

  /// A YES is enough to fix the verdict, so the questions left after it are
  /// evidence for the nurse and not a delay — and they stay hers to skip.
  bool get alarmRaised => decision == CaregiverCheckDecision.urgent;

  /// Questions she has not answered yet.
  int get remainingQuestions {
    final set = questions;
    final answers = draft?.answers;
    if (set == null || answers == null) return 0;
    return set.questions.where((q) => answers[q.key] == null).length;
  }

  /// True while the worry screen has not been answered for a fresh session.
  /// The concern picker is a presentation step inside the questions stage: it
  /// sits before question 1 and only while no answer exists, so the order can
  /// never shuffle under an answered session.
  bool get needsConcerns =>
      stage == CaregiverCheckStage.questions &&
      draft != null &&
      draft!.concerns == null &&
      draft!.answers.isEmpty &&
      draft!.questionIndex == 0;
  void _notify() {
    if (_live) notifyListeners();
  }

  Future<void> load() async {
    try {
      final fresh = await repository.person(user, person.id);
      if (!_live) return;
      if (fresh == null) {
        throw const CaregiverDataException(
          'This family member is no longer available.',
        );
      }
      person = fresh;
      questions = policy.questionsFor(person);
      if (questions == null) {
        blockReason = policy.blockReasonFor(person);
        stage = CaregiverCheckStage.unsupported;
        _notify();
        return;
      }
      final saved = await repository.caregiverDraft(
        user,
        scope,
        person.id,
        CaregiverDraftKind.homeCheck,
      );
      if (!_live) return;
      if (saved != null && !policy.compatible(saved, person)) {
        await repository.discardCaregiverDraft(
          user,
          scope,
          person.id,
          CaregiverDraftKind.homeCheck,
        );
        notice =
            'The age group or questions changed. The old draft was discarded; please start again.';
      } else if (saved != null) {
        draft = saved;
        // A resumed session replays the worry order it was started with.
        questions = policy.questionsFor(person, concerns: saved.concerns);
        stage = CaregiverCheckStage.resume;
        saveState = CaregiverSaveState.saved;
        _notify();
        return;
      }
      _newSession();
    } catch (_) {
      if (!_live) return;
      stage = CaregiverCheckStage.loadFailed;
      notice = 'Saved answers could not be read. No answers were restored.';
      _notify();
    }
  }

  void _newSession() {
    if (!_live) return;
    questions = policy.questionsFor(person);
    if (questions == null) {
      blockReason = policy.blockReasonFor(person);
      stage = CaregiverCheckStage.unsupported;
      _notify();
      return;
    }
    final now = clock();
    draft = CaregiverDraft(
      id: const Uuid().v4(),
      scope: scope,
      personId: person.id,
      kind: CaregiverDraftKind.homeCheck,
      questionVersion: CaregiverCheckPolicy.questionVersion,
      cohortKey: questions!.cohortKey,
      answers: {},
      startedAt: now,
      updatedAt: now,
    );
    report = null;
    saveState = CaregiverSaveState.unsaved;
    stage = CaregiverCheckStage.questions;
    _notify();
  }

  Future<void> startNew() async {
    await _tail;
    if (!_live) return;
    try {
      await repository.discardCaregiverDraft(
        user,
        scope,
        person.id,
        CaregiverDraftKind.homeCheck,
      );
      notice = null;
    } catch (_) {
      notice =
          'Could not clear the saved draft. You can still check for danger signs; saving may need a retry.';
    }
    _newSession();
  }

  /// Start a fresh check with the previous answers filled in, used from the
  /// result screen when a caregiver realises an answer was wrong. The old
  /// completed report stays in history — checks are append-only, so a
  /// mistake is corrected by a new check, never by editing the record.
  Future<void> reviewAnswers() async {
    await _tail;
    if (!_live || stage != CaregiverCheckStage.result || draft == null) return;
    final previous = draft!;
    final now = clock();
    draft = CaregiverDraft(
      id: const Uuid().v4(),
      scope: previous.scope,
      personId: previous.personId,
      kind: previous.kind,
      questionVersion: previous.questionVersion,
      cohortKey: previous.cohortKey,
      answers: previous.answers,
      startedAt: now,
      updatedAt: now,
      onsetNote: previous.onsetNote,
      concerns: previous.concerns,
      durationKey: previous.durationKey,
      givenCare: previous.givenCare,
    );
    report = null;
    saveState = CaregiverSaveState.unsaved;
    stage = CaregiverCheckStage.questions;
    _persist();
    _notify();
  }

  void confirmResume() {
    if (!_live || stage != CaregiverCheckStage.resume || draft == null) return;
    if (!policy.compatible(draft!, person)) {
      notice = 'The age group changed. Start a new check.';
      stage = CaregiverCheckStage.loadFailed;
    } else if (decision == CaregiverCheckDecision.urgent &&
        remainingQuestions == 0) {
      stage = CaregiverCheckStage.result;
      _persist(finalize: true);
    } else {
      // Including a saved YES: she picks up where the draft stopped, with the
      // alarm already up so the advice is one tap away.
      stage = CaregiverCheckStage.questions;
      _change(index: 0);
    }
    _notify();
  }

  void _change({
    Map<String, CaregiverAnswer>? answers,
    int? index,
    String? onset,
    List<String>? concerns,
    String? durationKey,
    Set<String>? givenCare,
  }) {
    final old = draft!;
    draft = CaregiverDraft(
      id: old.id,
      scope: old.scope,
      personId: old.personId,
      kind: old.kind,
      questionVersion: old.questionVersion,
      cohortKey: old.cohortKey,
      answers: answers ?? old.answers,
      startedAt: old.startedAt,
      updatedAt: clock(),
      onsetNote: onset ?? old.onsetNote,
      questionIndex: index ?? old.questionIndex,
      concerns: concerns ?? old.concerns,
      durationKey: durationKey ?? old.durationKey,
      givenCare: givenCare ?? old.givenCare,
    );
    _revision++;
  }

  bool _currentCohort() {
    if (draft != null && policy.compatible(draft!, person)) return true;
    stage = CaregiverCheckStage.loadFailed;
    notice =
        'The age group or questions changed. Start a new check; no health conclusion was made.';
    _notify();
    return false;
  }

  /// Record the worries she named and lead the battery with them. Only
  /// allowed before any answers exist, so the order can never shuffle under
  /// an answered session.
  void setConcerns(List<String> concernKeys) {
    if (!_live ||
        stage != CaregiverCheckStage.questions ||
        !needsConcerns ||
        !_currentCohort()) {
      return;
    }
    questions = policy.questionsFor(person, concerns: concernKeys);
    _change(concerns: concernKeys);
    _persist();
    _notify();
  }

  /// How long the signs have been present — asked once, after the battery,
  /// instead of a buried note. Duration feeds the nurse summary; it never
  /// changes the verdict, which the answered danger signs alone decide.
  void setDuration(String durationKey) {
    if (!_live || stage != CaregiverCheckStage.duration || !_currentCohort()) {
      return;
    }
    _change(durationKey: durationKey);
    stage = CaregiverCheckStage.context;
    _persist();
    _notify();
  }

  /// What the family already tried — recorded for the nurse, never judged
  /// and never advised about here.
  void setGivenCare(Set<String> givenKeys) {
    if (!_live || stage != CaregiverCheckStage.context || !_currentCohort()) {
      return;
    }
    _change(givenCare: givenKeys);
    _persist();
    _notify();
  }

  /// Leave the context screen for the result. Skippable — pre-care context
  /// is valuable but must never block guidance.
  void finishContext() {
    if (!_live || stage != CaregiverCheckStage.context || !_currentCohort()) {
      return;
    }
    final d = decision;
    if (d != CaregiverCheckDecision.incomplete) {
      stage = CaregiverCheckStage.result;
      _persist(finalize: true);
    } else {
      // Incomplete answers cannot produce a verdict; send her back.
      stage = CaregiverCheckStage.questions;
    }
    _notify();
  }

  void answer(String key, CaregiverAnswer answer) {
    if (!_live ||
        stage != CaregiverCheckStage.questions ||
        !questions!.questions.any((q) => q.key == key)) {
      return;
    }
    if (!_currentCohort()) return;
    _change(answers: {...draft!.answers, key: answer});
    // A YES used to end the check on the spot. It no longer does: the nurse at
    // the facility asks which signs, for how long, and what has already been
    // given, and those answers only exist if she finishes. Urgency is carried
    // by [stopForVerdict] instead — one tap for as long as the alarm is up —
    // so advice is never withheld behind questions she has already answered.
    _persist();
    _notify();
  }

  /// Leave the check for the advice with the answers on hand. Only offered
  /// once a YES has fixed the verdict: stopping earlier could print a
  /// conclusion the unanswered questions contradict.
  void stopForVerdict() {
    if (!_live ||
        !alarmRaised ||
        (stage != CaregiverCheckStage.questions &&
            stage != CaregiverCheckStage.duration &&
            stage != CaregiverCheckStage.context) ||
        !_currentCohort()) {
      return;
    }
    stage = CaregiverCheckStage.result;
    _persist(finalize: true);
    _notify();
  }

  void onset(String note) {
    if (!_live ||
        (stage != CaregiverCheckStage.questions &&
            stage != CaregiverCheckStage.duration)) {
      return;
    }
    _change(onset: note);
    _persist();
    _notify();
  }

  void next() {
    if (!_live || stage != CaregiverCheckStage.questions || !_currentCohort()) {
      return;
    }
    final index = draft!.questionIndex;
    if (draft!.answers[questions!.questions[index].key] == null) return;
    if (index + 1 < questions!.questions.length) {
      _change(index: index + 1);
      _persist();
    } else {
      final verdict = decision;
      if (verdict != CaregiverCheckDecision.incomplete) {
        // The battery is complete. How long this has been going on, and what
        // the family already tried, are the nurse's next two questions — a
        // danger sign needs those answers as much as a routine one does.
        stage = CaregiverCheckStage.duration;
        _persist();
      }
    }
    _notify();
  }

  void back() {
    if (!_live || !_currentCohort()) return;
    switch (stage) {
      case CaregiverCheckStage.questions:
        if (draft!.questionIndex == 0) return;
        _change(index: draft!.questionIndex - 1);
        _persist();
      case CaregiverCheckStage.duration:
        stage = CaregiverCheckStage.questions;
      case CaregiverCheckStage.context:
        stage = CaregiverCheckStage.duration;
      case CaregiverCheckStage.result:
        return;
      case CaregiverCheckStage.loading:
      case CaregiverCheckStage.resume:
      case CaregiverCheckStage.unsupported:
      case CaregiverCheckStage.loadFailed:
        return;
    }
    _notify();
  }

  void retry() {
    if (saveState == CaregiverSaveState.saving || draft == null) return;
    _persist(finalize: stage == CaregiverCheckStage.result);
    _notify();
  }

  void _persist({bool finalize = false}) {
    final snapshot = draft!;
    final revision = _revision;
    saveState = CaregiverSaveState.saving;
    _tail = _tail.then((_) async {
      // A disposed screen may finish an authorized queued save, but an account
      // switch cannot begin another write or publish state into a new account.
      if (!isCurrent()) return;
      try {
        if (finalize) {
          // Keep the latest answer recoverable even if finalization fails. A
          // completed retry may reject a draft but still return its saved report.
          try {
            await repository.saveCaregiverDraft(user, snapshot);
          } catch (_) {
            // Only the transaction below can establish a saved completed report.
          }
          if (!isCurrent()) return;
          final saved = await repository.finalizeCaregiverHomeCheck(
            user,
            snapshot,
          );
          if (_live) {
            report = saved;
            onSaved();
          }
        } else {
          await repository.saveCaregiverDraft(user, snapshot);
        }
        if (_live && revision == _revision) {
          saveState = CaregiverSaveState.saved;
        }
      } catch (_) {
        if (_live && revision == _revision) {
          saveState = CaregiverSaveState.failed;
        }
      }
      _notify();
    });
  }

  Future<void> get settled => _tail;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
