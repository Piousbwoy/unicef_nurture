/// The 60-second emergency triage tunnel.
///
/// When a mother runs in with a convulsing child there is no time for
/// intake: no household search, no names, no forms. One red button on the
/// FHW home opens a full-screen tunnel — pick the patient, answer the
/// IMCI danger-sign questions with big YES/NO taps, and the verdict lands
/// with the pre-referral steps already written.
///
/// Engineering notes:
///   * The tunnel is deliberately self-contained: it needs no person, no
///     household and no network. Its medicine is the published IMCI
///     danger-sign set and the GHS maternal red flags — the same rules the
///     full assessment runs, asked in the order a CHO asks them under
///     pressure.
///   * The breathing question carries a real 60-second count-down timer
///     (finite, disposed on exit — nothing here can run away).
///   * The verdict never invents severity: any danger sign is URGENT,
///     fast breathing alone is PRIORITY, a clean screen says so in green.
///     The wording is guideline text, not model output.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/enums.dart';
import '../shared/ui.dart';

/// What the tunnel returns: true when the CHO asked to continue into a
/// full assessment, so the home shell can land them on the Assess tab.
class EmergencyTunnelScreen extends StatefulWidget {
  const EmergencyTunnelScreen({super.key});

  @override
  State<EmergencyTunnelScreen> createState() => _EmergencyTunnelScreenState();
}

enum _Path { child, mother }

enum _Stage { path, age, question, breathing, verdict }

/// One danger-sign question: the big sentence and the quiet hint beneath.
class _TunnelQuestion {
  const _TunnelQuestion({required this.text, required this.hint});

  final String text;
  final String hint;
}

/// The IMCI general danger signs, asked exactly as a CHO asks them, in the
/// order that finds the dying child first. Source: IMCI 2019, WHO.
const _childQuestions = [
  _TunnelQuestion(
    text: 'Is the child unable to drink or breastfeed?',
    hint: 'Not “drinks poorly” — cannot drink at all.',
  ),
  _TunnelQuestion(
    text: 'Does the child vomit everything?',
    hint: 'Every feed, every time — not one or twice.',
  ),
  _TunnelQuestion(
    text: 'Has the child had convulsions during this illness?',
    hint: 'Seen now, or reported by the mother.',
  ),
  _TunnelQuestion(
    text: 'Is the child unusually sleepy or hard to wake?',
    hint: 'Lethargy or unconsciousness.',
  ),
  _TunnelQuestion(
    text: 'Do you see severe chest indrawing?',
    hint: 'Watch the lower chest while the child breathes in.',
  ),
];

/// The maternal red flags, maternal drugs only — the child checklist is a
/// different list and the two are never mixed.
const _motherQuestions = [
  _TunnelQuestion(
    text: 'Has she had convulsions or fits?',
    hint: 'Now, or during this pregnancy.',
  ),
  _TunnelQuestion(
    text: 'Severe headache or blurred vision?',
    hint: 'The pre-eclampsia warning pair.',
  ),
  _TunnelQuestion(
    text: 'Heavy vaginal bleeding?',
    hint: 'Soaking through, or clots.',
  ),
  _TunnelQuestion(
    text: 'Severe abdominal pain or difficulty breathing?',
    hint: 'Either one, on its own, counts.',
  ),
  _TunnelQuestion(
    text: 'Reduced or absent fetal movements?',
    hint: 'Ask if she is pregnant.',
  ),
];

/// WHO IMCI fast-breathing cut-offs by age band: at or above the number,
/// the breathing is fast.
const _ageBands = [
  (label: 'Under 2 months', cutOff: 60),
  (label: '2–11 months', cutOff: 50),
  (label: '12–59 months', cutOff: 40),
];

class _EmergencyTunnelScreenState extends State<EmergencyTunnelScreen> {
  _Stage _stage = _Stage.path;
  _Path _path = _Path.child;
  int _ageBand = 1;
  int _qIndex = 0;
  final Map<int, bool> _answers = {};

  // Breathing step: a real 60-second count, then the number they counted.
  Timer? _timer;
  int _secondsLeft = 60;
  bool _countDone = false;
  final _breaths = TextEditingController();
  bool? _fastBreathing; // null = could not count

  @override
  void dispose() {
    _timer?.cancel();
    _breaths.dispose();
    super.dispose();
  }

  List<_TunnelQuestion> get _questions =>
      _path == _Path.child ? _childQuestions : _motherQuestions;

  void _answer(bool yes) {
    _answers[_qIndex] = yes;
    if (_qIndex + 1 < _questions.length) {
      setState(() => _qIndex++);
      return;
    }
    // Child path ends with the breathing count; maternal path is done.
    if (_path == _Path.child) {
      _startBreathCount();
    } else {
      setState(() => _stage = _Stage.verdict);
    }
  }

  void _startBreathCount() {
    _secondsLeft = 60;
    _countDone = false;
    setState(() => _stage = _Stage.breathing);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _secondsLeft--;
        if (_secondsLeft <= 0) {
          _countDone = true;
          t.cancel();
        }
      });
    });
  }

  void _finishBreathing() {
    final rr = int.tryParse(_breaths.text.trim());
    _fastBreathing = rr == null ? null : rr >= _ageBands[_ageBand].cutOff;
    setState(() => _stage = _Stage.verdict);
  }

  // ----------------------------------------------------------- The verdict

  bool get _anyDangerSign =>
      _answers.values.any((yes) => yes) ||
      (_path == _Path.child && _answers.isNotEmpty && _answers[2] == true);

  ({TriageLevel level, String title, String subtitle, List<String> steps})
  get _verdict {
    if (_path == _Path.mother) {
      if (_answers[0] == true) {
        return (
          level: TriageLevel.urgent,
          title: 'Convulsions — treat as eclampsia',
          subtitle: 'This is an emergency. Stabilise first, then move her.',
          steps: const [
            'Give the MgSO₄ loading dose per the GHS eclampsia protocol.',
            'Turn her onto her side, protect the airway, stay with her.',
            'Refer urgently — call the receiving facility ahead if you can.',
          ],
        );
      }
      if (_anyDangerSign) {
        return (
          level: TriageLevel.urgent,
          title: 'Red flag — urgent referral today',
          subtitle: 'A maternal danger sign was answered yes.',
          steps: const [
            'Arrange urgent referral today — do not send her home to wait.',
            'Keep her accompanied; watch for convulsions and bleeding.',
            'Send this quick assessment with her.',
          ],
        );
      }
      return (
        level: TriageLevel.routine,
        title: 'No red flag on this quick check',
        subtitle: 'Continue the ANC/PNC consultation as planned.',
        steps: const [
          'Complete the routine visit — blood pressure and urine if due.',
          'Remind her of the danger signs and when to come back at once.',
        ],
      );
    }

    if (_answers.values.any((yes) => yes)) {
      return (
        level: TriageLevel.urgent,
        title: 'Danger sign — severe illness',
        subtitle: 'Stabilise first. Every minute here counts.',
        steps: const [
          'Keep the child warm — skin-to-skin against the mother if possible.',
          'Prevent low sugar: breastfeed, or sugar water if able to swallow.',
          'Give the first antibiotic dose per protocol if referral will take time.',
          'Refer urgently — send this quick assessment with the child.',
        ],
      );
    }
    if (_fastBreathing == true) {
      return (
        level: TriageLevel.priority,
        title: 'Fast breathing — possible pneumonia',
        subtitle:
            'At ${_ageBands[_ageBand].label.toLowerCase()}, ${_breaths.text.trim()} '
            'breaths a minute is at or above the ${_ageBands[_ageBand].cutOff}-breath cut-off.',
        steps: const [
          'Calm the child and count again for a full 60 seconds.',
          'Fast breathing at this age is a pneumonia sign — assess fully today.',
          'Arrange same-day review; refer at once if any danger sign appears.',
        ],
      );
    }
    if (_fastBreathing == null) {
      return (
        level: TriageLevel.watch,
        title: 'Breathing not confirmed',
        subtitle: 'The count was not completed — do not file this as clear.',
        steps: const [
          'Count the breaths again for a full 60 seconds while the child is calm.',
          'Assess fully today before sending the child home.',
        ],
      );
    }
    return (
      level: TriageLevel.routine,
      title: 'No danger sign found',
      subtitle: 'Continue the routine consultation.',
      steps: const [
        'Proceed with the normal assessment for this visit.',
        'Tell the mother which signs mean she should come back at once.',
      ],
    );
  }

  // ------------------------------------------------------------- The build

  @override
  Widget build(BuildContext context) {
    final v = _verdict;
    final c = triageColours(
      _stage == _Stage.verdict ? v.level : TriageLevel.urgent,
    );
    return Scaffold(
      backgroundColor: _stage == _Stage.verdict
          ? c.bg
          : const Color(0xFF2B0708),
      body: SafeArea(
        child: _stage == _Stage.path
            ? _buildPath()
            : _stage == _Stage.age
            ? _buildAge()
            : _stage == _Stage.breathing
            ? _buildBreathing()
            : _stage == _Stage.verdict
            ? _buildVerdict(v)
            : _buildQuestion(),
      ),
    );
  }

  Widget _tunnelChrome({required Widget child, Color bar = Colors.white}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: () => _back(),
                icon: Icon(Icons.arrow_back_rounded, color: bar),
                tooltip: 'Back',
              ),
              Expanded(
                child: Text(
                  'EMERGENCY TRIAGE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: bar.withValues(alpha: 0.7),
                  ),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  void _back() {
    setState(() {
      switch (_stage) {
        case _Stage.age:
          _stage = _Stage.path;
        case _Stage.question:
          if (_qIndex > 0) {
            _qIndex--;
          } else if (_path == _Path.child) {
            _stage = _Stage.age;
          } else {
            _stage = _Stage.path;
          }
        case _Stage.breathing:
          _timer?.cancel();
          _stage = _Stage.question;
        case _Stage.verdict:
        case _Stage.path:
          Navigator.of(context).maybePop();
      }
    });
  }

  Widget _buildPath() {
    return _tunnelChrome(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            Container(
              width: 74,
              height: 74,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.triageRed,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.triageRed.withValues(alpha: 0.45),
                    blurRadius: 34,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                size: 40,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: Gap.lg),
            const Text(
              'Someone needs help right now',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.25,
              ),
            ),
            const SizedBox(height: Gap.sm),
            Text(
              'No names, no registers — six questions and a verdict. '
              'Who is in front of you?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.72),
                height: 1.45,
              ),
            ),
            const SizedBox(height: Gap.xl),
            _PathButton(
              icon: Icons.child_care_rounded,
              title: 'A child',
              subtitle: 'Under five years',
              onTap: () => setState(() {
                _path = _Path.child;
                _stage = _Stage.age;
              }),
            ),
            const SizedBox(height: Gap.md),
            _PathButton(
              icon: Icons.pregnant_woman_rounded,
              title: 'A pregnant or just-delivered mother',
              subtitle: 'ANC, labour or postnatal red flags',
              onTap: () => setState(() {
                _path = _Path.mother;
                _qIndex = 0;
                _answers.clear();
                _stage = _Stage.question;
              }),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildAge() {
    return _tunnelChrome(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            const Text(
              'How old is the child?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: Gap.xs),
            Text(
              'The fast-breathing cut-off depends on the age.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: Gap.xl),
            for (var i = 0; i < _ageBands.length; i++) ...[
              if (i > 0) const SizedBox(height: Gap.sm),
              _PathButton(
                icon: Icons.cake_outlined,
                title: _ageBands[i].label,
                subtitle: 'Fast breathing: ${_ageBands[i].cutOff}+ per minute',
                onTap: () => setState(() {
                  _ageBand = i;
                  _qIndex = 0;
                  _answers.clear();
                  _stage = _Stage.question;
                }),
              ),
            ],
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion() {
    final q = _questions[_qIndex];
    return _tunnelChrome(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Gap.lg),
            // Progress: one dot per question, impossible to lose count.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _questions.length; i++)
                  Container(
                    width: i == _qIndex ? 22 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      color: i == _qIndex
                          ? Colors.white
                          : Colors.white.withValues(
                              alpha: i < _qIndex ? 0.65 : 0.25,
                            ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              q.text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.3,
              ),
            ),
            const SizedBox(height: Gap.sm),
            Text(
              q.hint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.7),
                height: 1.4,
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: _AnswerButton(
                    label: 'NO',
                    background: Colors.white.withValues(alpha: 0.12),
                    foreground: Colors.white,
                    onTap: () => _answer(false),
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: _AnswerButton(
                    label: 'YES',
                    background: AppColors.triageRed,
                    foreground: Colors.white,
                    onTap: () => _answer(true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.lg),
          ],
        ),
      ),
    );
  }

  Widget _buildBreathing() {
    final band = _ageBands[_ageBand];
    return _tunnelChrome(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Gap.lg),
            Text(
              _countDone
                  ? 'What did you count?'
                  : 'Count the breaths for 60 seconds',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: Gap.xs),
            Text(
              'Watch the chest rise. At ${band.label.toLowerCase()}, '
              '${band.cutOff} or more breaths a minute is fast breathing.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.7),
                height: 1.4,
              ),
            ),
            const Spacer(),
            if (!_countDone)
              Center(
                child: Text(
                  '$_secondsLeft',
                  style: TextStyle(
                    fontSize: 96,
                    fontWeight: FontWeight.w900,
                    color: Colors.white.withValues(alpha: 0.92),
                    height: 1,
                  ),
                ),
              )
            else ...[
              Center(
                child: SizedBox(
                  width: 180,
                  child: TextField(
                    controller: _breaths,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                    decoration: InputDecoration(
                      hintText: 'breaths',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 20,
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Gap.radiusSm),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Gap.lg),
              _AnswerButton(
                label: 'DONE — GIVE ME THE VERDICT',
                background: AppColors.triageRed,
                foreground: Colors.white,
                onTap: _finishBreathing,
              ),
              const SizedBox(height: Gap.sm),
              Center(
                child: TextButton(
                  onPressed: () {
                    _fastBreathing = null;
                    setState(() => _stage = _Stage.verdict);
                  },
                  child: Text(
                    'Could not count — assess fully instead',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildVerdict(
    ({TriageLevel level, String title, String subtitle, List<String> steps}) v,
  ) {
    final c = triageColours(v.level);
    final dark = v.level != TriageLevel.watch && v.level != TriageLevel.routine;
    final onV = dark
        ? Colors.white
        : v.level == TriageLevel.routine
        ? AppColors.ink
        : AppColors.ink;
    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        const SizedBox(height: Gap.lg),
        Center(
          child: Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: dark ? Colors.white.withValues(alpha: 0.16) : c.fg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              v.level == TriageLevel.urgent
                  ? Icons.emergency_share_rounded
                  : v.level == TriageLevel.routine
                  ? Icons.check_circle_outline_rounded
                  : Icons.hourglass_top_rounded,
              size: 42,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: Gap.lg),
        Text(
          v.level.label.toUpperCase(),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.4,
            color: onV.withValues(alpha: 0.75),
          ),
        ),
        const SizedBox(height: Gap.xs),
        Text(
          v.title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: onV,
            height: 1.25,
          ),
        ),
        const SizedBox(height: Gap.sm),
        Text(
          v.subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: onV.withValues(alpha: 0.85),
            height: 1.45,
          ),
        ),
        const SizedBox(height: Gap.xl),
        // The steps on a white card: readable on any severity colour.
        Container(
          padding: const EdgeInsets.all(Gap.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(Gap.radius),
            boxShadow: const [AppShadows.card],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'DO THIS NOW',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                  color: AppColors.inkMuted,
                ),
              ),
              const SizedBox(height: Gap.sm),
              for (var i = 0; i < v.steps.length; i++) ...[
                if (i > 0) const SizedBox(height: Gap.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.fg.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          color: c.fg,
                        ),
                      ),
                    ),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      child: Text(
                        v.steps[i],
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Gap.lg),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.assignment_turned_in_outlined, size: 18),
          label: const Text('Continue with a full assessment'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(Gap.tapTarget),
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.ink,
          ),
        ),
        const SizedBox(height: Gap.sm),
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Close',
              style: TextStyle(
                color: onV.withValues(alpha: 0.85),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: Gap.lg),
      ],
    );
  }
}

/// One of the two big doorway buttons on the path / age screens.
class _PathButton extends StatelessWidget {
  const _PathButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(Gap.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Gap.radius),
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Row(
            children: [
              Icon(icon, size: 30, color: Colors.white),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

/// A giant tap target: NO on the left, YES in red on the right.
class _AnswerButton extends StatelessWidget {
  const _AnswerButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(Gap.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Gap.radius),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.xl),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.6,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
