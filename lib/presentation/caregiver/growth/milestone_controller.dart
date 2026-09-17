import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../../data/repositories/care_repository.dart';
import '../../../domain/engines/nurturing_care_engine.dart';
import '../../../domain/entities/caregiver.dart';
import '../../../domain/entities/core.dart';
import '../../../domain/entities/visit.dart';
import '../../../domain/services/caregiver_milestone_policy.dart';
import '../check/check_controller.dart'
    show CaregiverCheckStage, CaregiverSaveState;

class CaregiverMilestoneController extends ChangeNotifier {
  CaregiverMilestoneController({
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
  NcAgeBand? band;
  CaregiverDraft? draft;
  MilestoneCheck? report;
  CaregiverCheckStage stage = CaregiverCheckStage.loading;
  CaregiverSaveState saveState = CaregiverSaveState.unsaved;
  String? notice;
  Future<void> _tail = Future.value();
  bool _disposed = false;
  int _revision = 0;
  bool get _live => !_disposed && isCurrent();
  Future<void> get settled => _tail;
  void _notify() {
    if (_live) notifyListeners();
  }

  Future<void> load() async {
    try {
      final fresh = await repository.person(user, person.id);
      if (!_live) return;
      if (fresh == null) {
        throw const CaregiverDataException('Person unavailable.');
      }
      person = fresh;
      band = CaregiverMilestonePolicy.bandFor(person, clock());
      if (band == null) {
        stage = CaregiverCheckStage.unsupported;
        _notify();
        return;
      }
      final saved = await repository.caregiverDraft(
        user,
        scope,
        person.id,
        CaregiverDraftKind.milestone,
      );
      if (!_live) return;
      if (saved != null &&
          CaregiverMilestonePolicy.compatible(saved, person, clock())) {
        draft = saved;
        stage = CaregiverCheckStage.resume;
        saveState = CaregiverSaveState.saved;
        _notify();
        return;
      }
      if (saved != null) {
        await repository.discardCaregiverDraft(
          user,
          scope,
          person.id,
          CaregiverDraftKind.milestone,
        );
        notice =
            'The age band or questions changed. The old draft was discarded; start again.';
      }
      _newSession();
    } catch (_) {
      if (!_live) return;
      stage = CaregiverCheckStage.loadFailed;
      notice =
          'Saved milestone answers could not be read. No answers were restored.';
      _notify();
    }
  }

  void _newSession() {
    if (!_live) return;
    band = CaregiverMilestonePolicy.bandFor(person, clock());
    if (band == null) {
      stage = CaregiverCheckStage.unsupported;
      _notify();
      return;
    }
    final now = clock();
    draft = CaregiverDraft(
      id: const Uuid().v4(),
      scope: scope,
      personId: person.id,
      kind: CaregiverDraftKind.milestone,
      questionVersion: CaregiverMilestonePolicy.questionVersion,
      cohortKey: CaregiverMilestonePolicy.cohortKey(person, band!),
      answers: {},
      startedAt: now,
      updatedAt: now,
    );
    report = null;
    stage = CaregiverCheckStage.questions;
    saveState = CaregiverSaveState.unsaved;
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
        CaregiverDraftKind.milestone,
      );
      notice = null;
      _newSession();
    } catch (_) {
      notice = 'Could not clear the saved draft. Please retry.';
      _notify();
    }
  }

  bool _compatible() {
    if (draft != null &&
        CaregiverMilestonePolicy.compatible(draft!, person, clock())) {
      return true;
    }
    stage = CaregiverCheckStage.loadFailed;
    notice =
        'The age band or questions changed. Start a new check; no conclusion was made.';
    _notify();
    return false;
  }

  void confirmResume() {
    if (!_live || stage != CaregiverCheckStage.resume || !_compatible()) return;
    stage = CaregiverCheckStage.questions;
    _change(index: 0);
    _notify();
  }

  void _change({Map<String, CaregiverAnswer>? answers, int? index}) {
    final old = draft!;
    draft = CaregiverDraft(
      id: old.id,
      scope: scope,
      personId: person.id,
      kind: old.kind,
      questionVersion: old.questionVersion,
      cohortKey: old.cohortKey,
      answers: answers ?? old.answers,
      startedAt: old.startedAt,
      updatedAt: clock(),
      questionIndex: index ?? old.questionIndex,
    );
    _revision++;
  }

  void answer(CaregiverAnswer value) {
    if (!_live ||
        stage != CaregiverCheckStage.questions ||
        value == CaregiverAnswer.unsure ||
        !_compatible()) {
      return;
    }
    final question = band!.milestones[draft!.questionIndex];
    _change(answers: {...draft!.answers, question.id: value});
    _persist();
    _notify();
  }

  void next() {
    if (!_live || stage != CaregiverCheckStage.questions || !_compatible()) {
      return;
    }
    final index = draft!.questionIndex;
    if (!draft!.answers.containsKey(band!.milestones[index].id)) return;
    if (index + 1 < band!.milestones.length) {
      _change(index: index + 1);
      _persist();
    } else if (draft!.answers.length == band!.milestones.length) {
      report = CaregiverMilestonePolicy.report(draft!, person, clock());
      stage = CaregiverCheckStage.result;
      _persist(finalize: true);
    }
    _notify();
  }

  void back() {
    if (!_live ||
        stage != CaregiverCheckStage.questions ||
        draft!.questionIndex == 0) {
      return;
    }
    _change(index: draft!.questionIndex - 1);
    _persist();
    _notify();
  }

  void retry() {
    if (!_live || draft == null || saveState == CaregiverSaveState.saving) {
      return;
    }
    _persist(finalize: stage == CaregiverCheckStage.result);
    _notify();
  }

  void _persist({bool finalize = false}) {
    final snapshot = draft!;
    final revision = _revision;
    saveState = CaregiverSaveState.saving;
    _tail = _tail.then((_) async {
      if (!isCurrent()) return;
      try {
        if (finalize) {
          try {
            await repository.saveCaregiverDraft(user, snapshot);
          } catch (_) {
            /* Retry may already be complete. */
          }
          if (!isCurrent()) return;
          final saved = await repository.finalizeCaregiverMilestone(
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

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
