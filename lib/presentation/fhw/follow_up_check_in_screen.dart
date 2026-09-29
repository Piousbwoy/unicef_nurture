/// Records what a worker found after a referral — as a report, not a status.
///
/// The whole screen exists to answer four questions in the order they are
/// actually asked at a compound, then write the answer once:
///
///   1. where the answer came from,
///   2. whether the family got to the facility,
///   3. what happened there,
///   4. how the patient is now.
///
/// Everything else — the referral's lifecycle, the barrier history, the fresh
/// referral a worsening child needs — is derived from those four by
/// [CareRepository.recordFollowUp], in one commit. The screen never picks a
/// status, because a worker who picks `arrived` has not been asked whether the
/// child was treated, and `arrived` is how an untreated child leaves the chase
/// list.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/fhw_luxe.dart';
import '../../data/local/visit_dao.dart';
import '../../data/repositories/care_repository.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../../domain/services/follow_up_policy.dart';
import '../shared/ui.dart';
import 'clinic_widgets.dart';

class FollowUpCheckInScreen extends ConsumerStatefulWidget {
  const FollowUpCheckInScreen({
    super.key,
    required this.referral,
    this.householdId,
  });

  final Referral referral;

  /// Known when the desk opened this case. Absent when it came from the day
  /// plan, in which case the record is looked up before anything is written —
  /// an answer with nowhere to be filed must not be half-saved.
  final String? householdId;

  @override
  ConsumerState<FollowUpCheckInScreen> createState() =>
      _FollowUpCheckInScreenState();
}

class _FollowUpCheckInScreenState extends ConsumerState<FollowUpCheckInScreen> {
  FollowUpChannel? _channel;
  FollowUpReach? _reach;
  FollowUpCare? _care;
  FollowUpCondition? _condition;
  final Set<CareBarrier> _barriers = {};
  bool _raiseNew = false;

  final TextEditingController _note = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _prompt;

  /// Frozen when the screen opens. A retry after a failed write re-uses the
  /// same contact id, so the answer lands once, and the family is handed the
  /// same code the device stores.
  final String _contactId = const Uuid().v4();
  final String _newReferralId = const Uuid().v4();

  /// Seeded synchronously so the option is present on the first frame exactly
  /// as before, then upgraded only if it collides — see [_ensureCodeIsFree].
  late String _newCode = ReferralDao.randomReferenceCode();

  @override
  void initState() {
    super.initState();
    _ensureCodeIsFree();
  }

  /// The synchronous seed is only a random guess: `reference_code` has a UNIQUE
  /// index and a 4-character space, so a busy device's guess can already be
  /// taken — which would fail the save. If it is, swap in a collision-checked
  /// code. In the overwhelmingly common case the guess is free, so the code the
  /// family is first shown never changes under them.
  Future<void> _ensureCodeIsFree() async {
    try {
      if (await ReferralDao.codeExists(_newCode)) {
        final fresh = await ReferralDao.mintReferenceCode();
        if (mounted) setState(() => _newCode = fresh);
      }
    } catch (_) {
      // No database reachable (e.g. a widget test over a mocked repository).
      // Keep the synchronous fallback code; the save path surfaces any real
      // problem, and this screen must not throw on opening.
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _went => _reach == FollowUpReach.went;
  bool get _answered =>
      _reach != null && _reach != FollowUpReach.unknown;

  /// A patient who is no better needs a clinical decision, not another
  /// check-in. This is the case the old flow lost: "attended" was recorded,
  /// nobody asked how the child was, and the child got sicker at home.
  bool get _offersReReferral =>
      _answered &&
      _care != FollowUpCare.seenTreated &&
      (_condition?.needsAction ?? false);

  /// The first thing the worker still has to say. The primary control carries
  /// this as its label, so it is never a dead button — it names the gap.
  String? get _missing {
    if (_channel == null) return 'Where did this answer come from?';
    if (_reach == null) return 'Did the family get to the facility?';
    if (_went && _care == null) return 'What happened at the facility?';
    if (_reach == FollowUpReach.didNotGo && _barriers.isEmpty) {
      return 'Say what stopped them';
    }
    if (_reach == FollowUpReach.declined && _barriers.isEmpty) {
      return 'Say why the family declined';
    }
    return null;
  }

  String get _missingPrompt =>
      (_reach == FollowUpReach.didNotGo || _reach == FollowUpReach.declined) &&
          _barriers.isEmpty
      ? 'Name it — the barrier is the finding, and it is what changes the next '
            'visit.'
      : 'Answer that first. This desk only records what you established, never '
            'what it could assume.';

  String get _actionLabel =>
      _error != null && _missing == null ? 'Retry save' : (_missing ?? 'Save follow-up');

  @override
  Widget build(BuildContext context) {
    final locked = _busy;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: const Text('Record follow-up'),
          backgroundColor: AppColors.surface,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, Gap.xl),
            children: [
              _Brief(referral: widget.referral),
              const SizedBox(height: Gap.md),
              _Ask<FollowUpChannel>(
                question: 'Where did this answer come from?',
                helper:
                    'A body at the compound and a phone call are different '
                    'kinds of sure.',
                choices: const [
                  _Choice(FollowUpChannel.householdVisit, 'At the household'),
                  _Choice(FollowUpChannel.phoneCall, 'On the phone'),
                ],
                selected: _channel,
                enabled: !locked,
                onTap: (value) => setState(() {
                  _channel = value;
                  _prompt = null;
                }),
              ),
              const SizedBox(height: Gap.md),
              _Ask<FollowUpReach>(
                question: 'Did the family get to the facility?',
                helper: 'As they tell it. Nobody is being graded here.',
                choices: const [
                  _Choice(FollowUpReach.went, 'Went to the facility'),
                  _Choice(FollowUpReach.didNotGo, 'Did not go'),
                  _Choice(FollowUpReach.declined, 'Declined to go'),
                  _Choice(FollowUpReach.unknown, "Don't know yet"),
                ],
                selected: _reach,
                enabled: !locked,
                onTap: (value) => setState(() {
                  _reach = value;
                  if (value != FollowUpReach.went) _care = null;
                  if (value == FollowUpReach.unknown) _condition = null;
                  _raiseNew = false;
                  _prompt = null;
                }),
              ),
              if (_reach != null && _reach != FollowUpReach.unknown) ...[
                if (_went) ...[
                  const SizedBox(height: Gap.md),
                  _Ask<FollowUpCare>(
                    question: 'What happened at the facility?',
                    helper:
                        'Queued from 6am and sent home is not the same as '
                        'treated. Say which it was.',
                    choices: const [
                      _Choice(FollowUpCare.seenTreated, 'Seen and treated'),
                      _Choice(FollowUpCare.seenWaiting, 'Seen, still waiting'),
                      _Choice(FollowUpCare.none, 'Turned away, no care'),
                      _Choice(FollowUpCare.unknown, "Don't know what happened"),
                    ],
                    selected: _care,
                    enabled: !locked,
                    onTap: (value) => setState(() {
                      _care = value;
                      _raiseNew = false;
                      _prompt = null;
                    }),
                  ),
                ],
                const SizedBox(height: Gap.md),
                _Ask<FollowUpCondition>(
                  question: 'And how is the patient now?',
                  helper:
                      'Leave this blank if you did not see them. It is a '
                      'clinical signal, not a formality.',
                  choices: const [
                    _Choice(FollowUpCondition.better, 'Better'),
                    _Choice(FollowUpCondition.same, 'Same'),
                    _Choice(FollowUpCondition.worse, 'Worse'),
                    _Choice(FollowUpCondition.died, 'Died'),
                    _Choice(FollowUpCondition.notSeen, 'Not seen since'),
                  ],
                  selected: _condition,
                  enabled: !locked,
                  onTap: (value) => setState(() {
                    _condition = value;
                    _raiseNew = false;
                    _prompt = null;
                  }),
                ),
              ],
              if (_shouldAskBarriers) ...[
                const SizedBox(height: Gap.md),
                _Barriers(
                  selected: _barriers,
                  enabled: !locked,
                  onToggle: (barrier) => setState(() {
                    if (!_barriers.add(barrier)) _barriers.remove(barrier);
                    _prompt = null;
                  }),
                ),
              ],
              if (_offersReReferral) ...[
                const SizedBox(height: Gap.md),
                _ReRefer(
                  referral: widget.referral,
                  enabled: !locked,
                  code: _newCode,
                  selected: _raiseNew,
                  onToggle: () => setState(() => _raiseNew = !_raiseNew),
                ),
              ],
              const SizedBox(height: Gap.md),
              ClinicCard(
                title: 'One line, in your words',
                child: TextField(
                  controller: _note,
                  enabled: !locked,
                  maxLines: 3,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText:
                        'Who you spoke to, what they said, what you promised',
                  ),
                ),
              ),
              if (_error != null || _prompt != null) ...[
                const SizedBox(height: Gap.md),
                Semantics(
                  liveRegion: true,
                  child: ClinicStatusLine(
                    text: _error ?? _prompt!,
                    icon: Icons.error_outline_rounded,
                  ),
                ),
              ],
              const SizedBox(height: Gap.lg),
              _SaveBar(
                label: _busy ? 'Saving…' : _actionLabel,
                onTap: _busy ? null : _save,
              ),
              const SizedBox(height: Gap.sm),
              const ClinicStatusLine(
                text:
                    'Saved on this phone as your report. No facility record '
                    'reaches this device, so nothing here is verified.',
                icon: Icons.info_outline_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _shouldAskBarriers =>
      _reach == FollowUpReach.didNotGo ||
      _reach == FollowUpReach.declined ||
      (_went && _care != null && _care != FollowUpCare.seenTreated);

  Future<void> _save() async {
    final missing = _missing;
    if (missing != null) {
      setState(() {
        _prompt = _missingPrompt;
        _error = null;
      });
      return;
    }
    if (_busy) return;
    final user = ref.read(currentUserProvider);
    if (user == null) {
      setState(() => _error = 'Sign in again before saving this follow-up.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _prompt = null;
    });
    try {
      final repository = ref.read(careRepositoryProvider);
      final householdId =
          widget.householdId ??
          (await repository.person(user, widget.referral.personId))
              ?.householdId;
      if (householdId == null) {
        throw const _UnfiledAnswer(
          'The patient behind this referral is not on this phone, so the '
          'answer has nowhere to go. Nothing was saved.',
        );
      }
      final answer = FollowUpAnswer(
        channel: _channel!,
        reached: _reach!,
        care: _care ?? FollowUpCare.unknown,
        condition: _condition ?? FollowUpCondition.notSeen,
        barriers: Set<CareBarrier>.unmodifiable(_barriers),
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      final result = await repository.recordFollowUp(
        user,
        referral: widget.referral,
        householdId: householdId,
        contactId: _contactId,
        answer: answer,
        alsoReRefer: _raiseNew && _offersReReferral ? _reReferral() : null,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await _confirm(result.outcome, result.raised);
      if (mounted) Navigator.of(context).pop(true);
    } on AccessDenied catch (error) {
      _fail(error.message);
    } on _UnfiledAnswer catch (error) {
      _fail(error.message);
    } catch (_) {
      _fail(
        'Could not save. Your answers are kept — try again, or write the '
        'result on the paper register and record it later.',
      );
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  FollowUpReReferral _reReferral() => FollowUpReReferral(
    id: _newReferralId,
    referenceCode: _newCode,
    facilityName: widget.referral.facilityName,
    reason:
        'Re-check after ${widget.referral.referenceCode}: '
        '${_condition!.label.toLowerCase()} after ${_carePhrase(_care)}',
    urgency: _condition == FollowUpCondition.worse
        ? ReferralUrgency.immediate
        : ReferralUrgency.sameDay,
  );

  Future<void> _confirm(FollowUpOutcome outcome, Referral? raised) async {
    final message = _confirmation(outcome, raised);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        scrollable: true,
        title: Text(message.title),
        content: Text(message.body),
        actions: [
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  ({String title, String body}) _confirmation(
    FollowUpOutcome outcome,
    Referral? raised,
  ) {
    if (raised != null) {
      return (
        title: 'Re-referred',
        body:
            'A new referral ${raised.referenceCode} is now on your desk for '
            '${raised.facilityName}, at ${raised.urgency.label.toLowerCase()}. '
            'This one stays as the record of what you found.',
      );
    }
    if (outcome == FollowUpOutcome.attemptLogged) {
      return (
        title: 'Attempt logged',
        body:
            'Nobody reached. ${widget.referral.referenceCode} stays open, and '
            'two visits like this one start a trace.',
      );
    }
    if (outcome == FollowUpOutcome.settled) {
      return (
        title: 'Care reported',
        body:
            'The family reports treatment at ${widget.referral.facilityName}. '
            'Reported by you — not verified by facility staff, and no '
            'facility record reaches this phone.',
      );
    }
    if (outcome == FollowUpOutcome.deceased) {
      return (
        title: 'Death recorded',
        body:
            'This referral is closed as the death of the patient. What you '
            'found stays on the record as the reason the chase ends.',
      );
    }
    if (outcome == FollowUpOutcome.closed) {
      return (
        title: 'Case closed',
        body: _reach == FollowUpReach.declined
            ? 'The family declined the referral. It is closed and no longer '
                  'chased, with the reason you recorded on the record.'
            : 'This referral is closed and no longer chased.',
      );
    }
    if (_reach == FollowUpReach.didNotGo) {
      return (
        title: 'Did not attend',
        body:
            'They did not get there. The reason you recorded is what the next '
            'visit has to answer.',
      );
    }
    return (
      title: 'Arrival reported',
      body:
          'Treatment has not been established$_wentDetail. This referral '
          'stays where you can see it.',
    );
  }

  String get _wentDetail => switch (_care) {
    FollowUpCare.seenWaiting => ' — they are still waiting',
    FollowUpCare.none => ' — they went and got no care',
    _ => '. Follow up on the care that is still needed',
  };
}

/// Thrown when an answer cannot be attributed to a household on this device.
class _UnfiledAnswer implements Exception {
  const _UnfiledAnswer(this.message);
  final String message;
}

String _carePhrase(FollowUpCare? care) => switch (care) {
  FollowUpCare.seenWaiting => 'being kept waiting',
  FollowUpCare.none => 'being turned away',
  FollowUpCare.seenTreated => 'treatment',
  _ => 'the visit',
};

// -------------------------------------------------------------------- widgets

class _Brief extends ConsumerWidget {
  const _Brief({required this.referral});

  final Referral referral;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = ref.watch(personProvider(referral.personId)).valueOrNull;
    return ClinicCard(
      accent: FhwLuxePalette.sapphireRoyal,
      title: person?.fullName ?? 'Referral follow-up',
      subtitle:
          '${referral.referenceCode} · ${referral.facilityName} · issued '
          '${DateFormat('d MMM').format(referral.issuedAt.toLocal())}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(referral.reason, style: AppType.body),
          const SizedBox(height: Gap.sm),
          const ClinicStatusLine(
            text:
                'You are recording what the family reports. Nobody at the '
                'facility is being asked, and none of this verifies arrival.',
            icon: Icons.info_outline_rounded,
          ),
        ],
      ),
    );
  }
}

class _Choice<T> {
  const _Choice(this.value, this.label, [this.detail]);
  final T value;
  final String label;
  final String? detail;
}

class _Ask<T> extends StatelessWidget {
  const _Ask({
    required this.question,
    required this.helper,
    required this.choices,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String question;
  final String helper;
  final List<_Choice<T>> choices;
  final T? selected;
  final bool enabled;
  final ValueChanged<T> onTap;

  @override
  Widget build(BuildContext context) => ClinicCard(
    title: question,
    subtitle: helper,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final choice in choices)
          _AnswerTile(
            label: choice.label,
            detail: choice.detail,
            selected: choice.value == selected,
            enabled: enabled,
            onTap: () => onTap(choice.value),
          ),
      ],
    ),
  );
}

class _AnswerTile extends StatelessWidget {
  const _AnswerTile({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.detail,
    this.multiple = false,
  });

  final String label;
  final String? detail;
  final bool selected;
  final bool enabled;
  final bool multiple;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.sm),
    child: Semantics(
      checked: selected,
      inMutuallyExclusiveGroup: !multiple,
      button: true,
      child: PressScale(
        onTap: enabled ? onTap : null,
        radius: BorderRadius.circular(Gap.radiusSm),
        child: Container(
          constraints: const BoxConstraints(minHeight: Gap.tapTarget - 6),
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.md,
            vertical: Gap.sm + 2,
          ),
          decoration: BoxDecoration(
            color: selected
                ? FhwLuxePalette.sapphireIce
                : FhwLuxePalette.pureWhite,
            borderRadius: BorderRadius.circular(Gap.radiusSm),
            border: Border.all(
              color: selected
                  ? FhwLuxePalette.sapphireRoyal
                  : FhwLuxePalette.hairLine,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                multiple
                    ? (selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked)
                    : (selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked),
                size: 20,
                color: selected
                    ? FhwLuxePalette.sapphireRoyal
                    : FhwLuxePalette.textFaint,
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppType.body.copyWith(
                        color: FhwLuxePalette.textPrimary,
                        fontWeight: selected ? FontWeight.w600 : null,
                      ),
                    ),
                    if (detail != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          detail!,
                          style: AppType.caption.copyWith(
                            color: AppColors.inkMuted,
                            height: 1.4,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Barriers extends StatelessWidget {
  const _Barriers({
    required this.selected,
    required this.enabled,
    required this.onToggle,
  });

  final Set<CareBarrier> selected;
  final bool enabled;
  final ValueChanged<CareBarrier> onToggle;

  @override
  Widget build(BuildContext context) => ClinicCard(
    accent: FhwLuxePalette.clinicalAmber,
    title: 'What got in the way?',
    subtitle:
        'Pick every reason they gave. Each one points at a different next '
        'move, which is the whole reason it is worth writing down.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final barrier in CareBarrier.values)
          _AnswerTile(
            label: barrier.label,
            selected: selected.contains(barrier),
            enabled: enabled,
            multiple: true,
            onTap: () => onToggle(barrier),
          ),
      ],
    ),
  );
}

/// The offer that catches the IMCI death case: no better after a referral is a
/// clinical decision, not another check-in.
class _ReRefer extends StatelessWidget {
  const _ReRefer({
    required this.referral,
    required this.selected,
    required this.enabled,
    required this.code,
    required this.onToggle,
  });

  final Referral referral;
  final bool selected;
  final bool enabled;
  final String code;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => ClinicCard(
    accent: FhwLuxePalette.clinicalRed,
    title: 'No better after a referral',
    subtitle:
        'Another visit is not a treatment plan. Raise a fresh referral now and '
        'the receiving facility gets the first visit with it.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AnswerTile(
          label: 'Raise a new referral',
          detail: selected
              ? 'Code $code · ${referral.facilityName} · the family is shown '
                    'this code before you save.'
              : 'Chased under ${referral.referenceCode}, so the two stay '
                    'linked.',
          selected: selected,
          enabled: enabled,
          onTap: onToggle,
        ),
      ],
    ),
  );
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => PressScale(
    // A blocked primary control is a dead end; this one always does the thing
    // its label says, including saving nothing when it says "what stopped
    // them".
    onTap: onTap ?? () {},
    radius: BorderRadius.circular(Gap.radius),
    child: Container(
      constraints: const BoxConstraints(minHeight: Gap.tapTarget),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: Gap.md),
      decoration: BoxDecoration(
        gradient: FhwLuxePalette.sapphireHeroGradient,
        borderRadius: BorderRadius.circular(Gap.radius),
        boxShadow: const [AppShadows.glow],
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: AppType.label.copyWith(
          color: Colors.white,
          fontSize: 15.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
