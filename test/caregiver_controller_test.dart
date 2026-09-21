import 'dart:async';

import 'package:carebridge_ai/core/audio/caregiver_playback.dart';
import 'package:carebridge_ai/data/repositories/care_repository.dart';
import 'package:carebridge_ai/domain/entities/caregiver.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/domain/services/caregiver_check_policy.dart';
import 'package:carebridge_ai/domain/services/caregiver_milestone_policy.dart';
import 'package:carebridge_ai/presentation/caregiver/growth/milestone_controller.dart';
import 'package:carebridge_ai/presentation/caregiver/caregiver_providers.dart';
import 'package:carebridge_ai/presentation/caregiver/check/check_controller.dart';
import 'package:carebridge_ai/presentation/caregiver/help/caregiver_voice.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const user = AppUser(id: 'user', fullName: 'Caregiver', phone: '0240000001', role: UserRole.caregiver,
  region: 'Northern Region', district: 'Karaga', community: 'Karaga');
const scope = CaregiverScope(userId: 'user', householdId: 'family');
final now = DateTime(2026, 8, 10, 9);
final baby = Person(id: 'baby', householdId: 'family', fullName: 'Awah', clientType: ClientType.newborn,
  dateOfBirth: DateTime(2026, 8, 1));

class MemoryRepository extends CareRepository {
  CaregiverDraft? saved;
  CaregiverSettings? settings;
  final reports = <HomeCheck>[];
  final milestoneReports = <MilestoneCheck>[];
  final attempts = <String>[];
  bool fail = false;
  bool failFinalization = false;
  Completer<void>? blocked;
  @override
  Future<Person?> person(AppUser user, String id) async => baby;
  @override
  Future<CaregiverDraft?> caregiverDraft(AppUser user, CaregiverScope scope, String id, CaregiverDraftKind kind) async => saved;
  @override
  Future<void> discardCaregiverDraft(AppUser user, CaregiverScope scope, String id, CaregiverDraftKind kind) async { saved = null; }
  @override
  Future<void> saveCaregiverDraft(AppUser user, CaregiverDraft draft) async {
    if (fail) throw StateError('Storage unavailable');
    saved = draft;
  }
  @override
  Future<HomeCheck> finalizeCaregiverHomeCheck(AppUser user, CaregiverDraft draft) async {
    attempts.add(draft.id);
    await blocked?.future;
    if (fail || failFinalization) throw StateError('Storage unavailable');
    final policy = CaregiverCheckPolicy(clock: () => now);
    final decision = policy.decide(policy.questionsFor(baby), draft.answers);
    final report = HomeCheck(id: draft.id, householdId: scope.householdId, personId: baby.id,
      clientType: ClientType.newborn, verdict: switch (decision) {
        CaregiverCheckDecision.urgent => HomeCheckVerdict.urgent,
        CaregiverCheckDecision.contactToday => HomeCheckVerdict.caution,
        _ => HomeCheckVerdict.fine,
      }, yesSigns: const [], unsureSigns: const [], checkedBy: user.id, checkedAt: draft.startedAt);
    reports.add(report);
    saved = null;
    return report;
  }
  @override
  Future<MilestoneCheck> finalizeCaregiverMilestone(AppUser user, CaregiverDraft draft) async {
    attempts.add(draft.id);
    await blocked?.future;
    if (fail || failFinalization) throw StateError('Storage unavailable');
    final report = CaregiverMilestonePolicy.report(draft, baby, now);
    milestoneReports.add(report);
    saved = null;
    return report;
  }
  @override
  Future<CaregiverSettings?> caregiverSettings(AppUser user, CaregiverScope scope) async => settings;
  @override
  Future<void> saveCaregiverSettings(AppUser user, CaregiverSettings value) async {
    if (fail) throw StateError('Storage unavailable');
    settings = value;
  }
}

class FakeVoice implements CaregiverVoiceBackend {
  final events = <void Function(CaregiverPlayback)>[];
  int stops = 0;
  bool disposed = false;
  @override
  Future<void> play(CaregiverSpeech speech, void Function(CaregiverPlayback) event) async { events.add(event); }
  @override
  Future<void> stop() async { stops++; }
  @override
  Future<void> dispose() async { disposed = true; }
  void emit(int request, CaregiverPlaybackPhase phase) => events[request](CaregiverPlayback(
    phase: phase, transcript: 'Actual spoken words', language: 'Dagbani', source: 'Bundled synthetic voice'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryRepository repo;
  late CaregiverCheckController controller;
  late DateTime time;
  late bool current;
  setUp(() {
    repo = MemoryRepository(); time = now; current = true;
    controller = CaregiverCheckController(repository: repo, user: user, scope: scope, person: baby,
      clock: () => time, isCurrent: () => current, onSaved: () {});
  });
  tearDown(() => controller.dispose());

  CaregiverMilestoneController milestone() => CaregiverMilestoneController(
    repository: repo, user: user, scope: scope, person: baby,
    clock: () => time, isCurrent: () => current, onSaved: () {});

  test('milestone draft resumes after confirmation and finalization retries once', () async {
    final first = milestone();
    await first.load();
    first.answer(CaregiverAnswer.no);
    await first.settled;
    final id = first.draft!.id;
    expect(repo.milestoneReports, isEmpty);
    first.dispose();
    final resumed = milestone();
    addTearDown(resumed.dispose);
    await resumed.load();
    expect(resumed.stage, CaregiverCheckStage.resume);
    resumed.answer(CaregiverAnswer.yes);
    expect(resumed.draft!.answers.values.single, CaregiverAnswer.no);
    resumed.confirmResume();
    repo.failFinalization = true;
    for (var i = 0; i < resumed.band!.milestones.length; i++) {
      resumed.answer(CaregiverAnswer.no);
      resumed.next();
    }
    await resumed.settled;
    expect(resumed.stage, CaregiverCheckStage.result);
    expect(resumed.saveState, CaregiverSaveState.failed);
    expect(repo.saved!.id, id);
    expect(repo.milestoneReports, isEmpty);
    repo.failFinalization = false;
    resumed.retry(); resumed.retry();
    await resumed.settled;
    expect(resumed.saveState, CaregiverSaveState.saved);
    expect(repo.milestoneReports.single.id, id);
    expect(resumed.report!.verdict, MilestoneVerdict.flag);
    expect(resumed.report!.checkedAt, now);
  });

  test('milestone drafts cannot cross question versions or account switches', () async {
    final first = milestone();
    await first.load();
    first.answer(CaregiverAnswer.yes);
    await first.settled;
    final previous = first.draft!;
    first.dispose();
    repo.saved = CaregiverDraft(id: previous.id, scope: scope, personId: baby.id,
      kind: CaregiverDraftKind.milestone, questionVersion: 1, cohortKey: previous.cohortKey,
      answers: previous.answers, startedAt: now, updatedAt: now);
    final next = milestone(); addTearDown(next.dispose);
    await next.load();
    expect(next.stage, CaregiverCheckStage.questions);
    expect(next.draft!.answers, isEmpty);
    expect(next.draft!.id, isNot(previous.id));
    current = false;
    next.answer(CaregiverAnswer.yes);
    await next.settled;
    expect(repo.saved, isNull);
  });

  test('stopping for urgent guidance does not wait for storage; retry keeps ID/time', () async {
    await controller.load();
    final original = controller.draft!;
    repo.blocked = Completer<void>();
    repo.fail = true;
    controller.answer('feed', CaregiverAnswer.yes);
    // The YES itself no longer ends the check: it raises the alarm and leaves
    // her in the battery, where she can answer or choose to go.
    expect(controller.stage, CaregiverCheckStage.questions);
    expect(controller.alarmRaised, isTrue);
    expect(controller.signsNoticed, ['Not feeding well']);
    controller.stopForVerdict();
    expect(controller.stage, CaregiverCheckStage.result);
    expect(controller.decision, CaregiverCheckDecision.urgent);
    expect(controller.saveState, CaregiverSaveState.saving);
    expect(controller.report, isNull);
    controller.retry(); // Double tap while saving does nothing.
    repo.blocked!.complete();
    await controller.settled;
    expect(controller.saveState, CaregiverSaveState.failed);
    repo.fail = false;
    time = now.add(const Duration(minutes: 10));
    controller.retry();
    await controller.settled;
    expect(controller.saveState, CaregiverSaveState.saved);
    expect(controller.report!.id, original.id);
    expect(controller.report!.checkedAt, original.startedAt);
    expect(repo.attempts, [original.id, original.id]);
    expect(controller.draft!.answers.keys, ['feed']);
  });

  test('without a danger sign there is no early verdict to stop for', () async {
    await controller.load();
    controller.answer('feed', CaregiverAnswer.no);
    controller.stopForVerdict();
    expect(controller.stage, CaregiverCheckStage.questions);
    expect(controller.report, isNull);
    expect(repo.reports, isEmpty);
  });

  test('urgent answer survives a failed finalization and restart', () async {
    await controller.load();
    repo.failFinalization = true;
    controller.answer('feed', CaregiverAnswer.yes);
    controller.stopForVerdict();
    await controller.settled;
    expect(controller.saveState, CaregiverSaveState.failed);
    expect(repo.saved!.answers, {'feed': CaregiverAnswer.yes});
    final resumed = CaregiverCheckController(repository: repo, user: user,
      scope: scope, person: baby, clock: () => time,
      isCurrent: () => true, onSaved: () {});
    addTearDown(resumed.dispose);
    await resumed.load();
    expect(resumed.stage, CaregiverCheckStage.resume);
    repo.failFinalization = false;
    resumed.confirmResume();
    // The draft stopped after one answer, so the battery continues with the
    // alarm up rather than a verdict printing on the spot.
    expect(resumed.stage, CaregiverCheckStage.questions);
    expect(resumed.alarmRaised, isTrue);
    expect(resumed.remainingQuestions, 7);
    resumed.stopForVerdict();
    expect(resumed.stage, CaregiverCheckStage.result);
    await resumed.settled;
    expect(resumed.report!.id, controller.draft!.id);
    expect(resumed.report!.verdict, HomeCheckVerdict.urgent);
  });

  test('NO never auto-advances; all NO and explicit Next are required', () async {
    await controller.load();
    controller.answer('feed', CaregiverAnswer.no);
    await controller.settled;
    expect(controller.draft!.questionIndex, 0);
    expect(controller.decision, CaregiverCheckDecision.incomplete);
    for (final question in controller.questions!.questions) {
      controller.answer(question.key, CaregiverAnswer.no);
      controller.next();
    }
    await controller.settled;
    // Navigate through duration and context stages
    controller.setDuration('today');
    controller.finishContext();
    await controller.settled;
    expect(controller.report!.verdict, HomeCheckVerdict.fine);
    expect(repo.reports, hasLength(1));
    controller.answer('feed', CaregiverAnswer.yes);
    expect(controller.report!.verdict, HomeCheckVerdict.fine); // History is immutable.
  });

  test('one unsure prevents routine guidance', () async {
    await controller.load();
    for (final q in controller.questions!.questions) {
      controller.answer(q.key, q.key == 'feed' ? CaregiverAnswer.unsure : CaregiverAnswer.no);
      controller.next();
    }
    await controller.settled;
    // Navigate through duration and context stages
    controller.setDuration('today');
    controller.finishContext();
    await controller.settled;
    expect(controller.report!.verdict, HomeCheckVerdict.caution);
  });

  test('concerns reorder the battery, persist, and survive resume', () async {
    await controller.load();
    expect(controller.needsConcerns, isTrue);
    controller.setConcerns(['hot']);
    await controller.settled;
    expect(controller.questions!.questions.first.key, 'temp');
    expect(controller.needsConcerns, isFalse);
    expect(controller.draft!.concerns, ['hot']);
    // Every question is still asked — concerns only lead.
    expect(controller.questions!.questions.length, 8);
    final resumed = CaregiverCheckController(repository: repo, user: user,
      scope: scope, person: baby, clock: () => time,
      isCurrent: () => true, onSaved: () {});
    addTearDown(resumed.dispose);
    await resumed.load();
    expect(resumed.stage, CaregiverCheckStage.resume);
    resumed.confirmResume();
    expect(resumed.questions!.questions.first.key, 'temp');
    expect(resumed.needsConcerns, isFalse);
  });

  test('a danger sign is followed by the questions the nurse asks', () async {
    await controller.load();
    controller.setConcerns(const []);
    controller.answer('feed', CaregiverAnswer.yes);
    expect(controller.stage, CaregiverCheckStage.questions);
    for (final q in controller.questions!.questions) {
      controller.answer(q.key, q.key == 'feed' ? CaregiverAnswer.yes : CaregiverAnswer.no);
      controller.next();
    }
    await controller.settled;
    // Urgent or not, how long it has been going on and what has been given are
    // the next two things a health worker asks.
    expect(controller.stage, CaregiverCheckStage.duration);
    controller.setDuration('fewDays');
    controller.finishContext();
    await controller.settled;
    expect(controller.report!.verdict, HomeCheckVerdict.urgent);
    expect(controller.draft!.durationKey, 'fewDays');
  });

  test('stopping early records what was answered and what was not', () async {
    await controller.load();
    controller.setConcerns(const []);
    controller.answer('feed', CaregiverAnswer.yes);
    controller.answer('fast', CaregiverAnswer.no);
    controller.stopForVerdict();
    await controller.settled;
    expect(controller.stage, CaregiverCheckStage.result);
    expect(controller.draft!.answers.length, 2);
    expect(controller.remainingQuestions, 6);
    expect(controller.report!.verdict, HomeCheckVerdict.urgent);
    expect(controller.draft!.durationKey, isNull);
  });

  test('reviewAnswers starts a fresh prefilled session; history is append-only', () async {
    await controller.load();
    controller.setConcerns(const ['feeding']);
    for (final q in controller.questions!.questions) {
      controller.answer(q.key, CaregiverAnswer.no);
      controller.next();
    }
    controller.setDuration('fewDays');
    controller.setGivenCare({'ors'});
    controller.finishContext();
    await controller.settled;
    final original = controller.draft!;
    expect(controller.report!.verdict, HomeCheckVerdict.fine);
    expect(repo.reports, hasLength(1));
    time = now.add(const Duration(minutes: 30));
    await controller.reviewAnswers();
    expect(controller.stage, CaregiverCheckStage.questions);
    expect(controller.draft!.id, isNot(original.id));
    expect(controller.draft!.startedAt, isNot(original.startedAt));
    expect(controller.draft!.answers['feed'], CaregiverAnswer.no);
    expect(controller.draft!.durationKey, 'fewDays');
    expect(controller.draft!.givenCare, {'ors'});
    expect(controller.draft!.concerns, ['feeding']);
    expect(controller.report, isNull);
    // The completed report is untouched.
    expect(repo.reports, hasLength(1));
  });

  test('draft resumption needs confirmation and preserves original time', () async {
    await controller.load();
    controller.answer('feed', CaregiverAnswer.no);
    controller.onset('Since morning');
    await controller.settled;
    final original = controller.draft!;
    final resumed = CaregiverCheckController(repository: repo, user: user, scope: scope, person: baby,
      clock: () => time, isCurrent: () => true, onSaved: () {});
    addTearDown(resumed.dispose);
    await resumed.load();
    expect(resumed.stage, CaregiverCheckStage.resume);
    resumed.answer('feed', CaregiverAnswer.yes);
    expect(resumed.draft!.answers['feed'], CaregiverAnswer.no);
    resumed.confirmResume();
    expect(resumed.stage, CaregiverCheckStage.questions);
    expect(resumed.draft!.startedAt, original.startedAt);
    expect(resumed.draft!.onsetNote, 'Since morning');
    await resumed.startNew();
    expect(resumed.draft!.id, isNot(original.id));
    expect(resumed.draft!.answers, isEmpty);
  });

  test('cohort change while open cannot produce a reassuring result', () async {
    await controller.load();
    time = DateTime(2026, 10, 1);
    controller.answer('feed', CaregiverAnswer.no);
    expect(controller.stage, CaregiverCheckStage.loadFailed);
    expect(controller.report, isNull);
  });

  test('switching owner cancels queued writes', () async {
    await controller.load();
    current = false;
    controller.answer('feed', CaregiverAnswer.yes);
    await controller.settled;
    expect(repo.attempts, isEmpty);
    expect(repo.saved, isNull);
  });

  test('serialized setting edits preserve unrelated choices and failure is retryable', () async {
    final writer = CaregiverWriter(scope: scope, user: user, repository: repo, clock: () => now,
      isCurrent: () => current, changed: () {});
    await Future.wait([
      writer.settings((s) => s.copyWith(foodsHave: {'Millet'})),
      writer.settings((s) => s.copyWith(autoRead: true)),
    ]);
    expect(repo.settings!.foodsHave, {'Millet'});
    expect(repo.settings!.autoRead, isTrue);
    repo.fail = true;
    await expectLater(writer.settings((s) => s.copyWith(lowCost: false)), throwsStateError);
    expect(repo.settings!.lowCost, isTrue);
    repo.fail = false;
    await writer.settings((s) => s.copyWith(lowCost: false));
    expect(repo.settings!.lowCost, isFalse);
    current = false;
    await expectLater(writer.settings((s) => s.copyWith(autoRead: false)), throwsA(isA<CaregiverDataException>()));
  });

  test('calendar refresh uses local day and resume refreshes dependencies', () {
    var resumes = 0;
    final calendar = CaregiverCalendar(() => time, onResume: () => resumes++);
    addTearDown(calendar.dispose);
    time = DateTime(2026, 8, 11);
    calendar.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(caregiverDateKey(calendar.state), '2026-08-11');
    expect(resumes, 1);
  });

  test('voice exposes actual completion, transcript and language; ignores stale events', () async {
    final backend = FakeVoice();
    final voice = CaregiverVoiceController(backend);
    const first = CaregiverSpeech(id: 'first', english: 'First', language: 'Dagbani');
    const second = CaregiverSpeech(id: 'second', english: 'Second', language: 'English');
    await voice.play(first);
    expect(voice.playback!.phase, CaregiverPlaybackPhase.loading);
    backend.emit(0, CaregiverPlaybackPhase.playing);
    expect(voice.playback!.language, 'Dagbani');
    expect(voice.playback!.transcript, 'Actual spoken words');
    backend.emit(0, CaregiverPlaybackPhase.completed);
    expect(voice.active, isFalse);
    await voice.play(second);
    backend.emit(0, CaregiverPlaybackPhase.completed);
    expect(voice.playback!.phase, CaregiverPlaybackPhase.loading);
    voice.didChangeAppLifecycleState(AppLifecycleState.paused);
    backend.emit(1, CaregiverPlaybackPhase.playing);
    expect(voice.playback!.phase, CaregiverPlaybackPhase.stopped);
    expect(backend.stops, 1);
    voice.dispose();
    backend.emit(1, CaregiverPlaybackPhase.completed);
    expect(backend.disposed, isTrue);
  });

  test('only identical registered copy is eligible for translated bank playback', () {
    expect(const CaregiverSpeech(id: 'q', english: 'Not breastfeeding or feeding well',
      language: 'Dagbani', clipId: 'q_newborn.feed').matchingClip, isNotNull);
    expect(const CaregiverSpeech(id: 'new', english: 'Contact a health worker today',
      language: 'Dagbani', clipId: 'caregiver_verdict_caution').matchingClip, isNull);
    expect(const CaregiverSpeech(id: 'dynamic', english: 'Awah needs support', language: 'Hausa').matchingClip, isNull);
  });
}
