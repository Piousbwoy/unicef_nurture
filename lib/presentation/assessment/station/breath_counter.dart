/// The 60-second breath counter.
///
/// A CHO taps the pad once per breath while the ring fills over a minute.
/// When time is up the count is the respiratory rate. "Count 30s ×2" is
/// offered because IMCI allows it for a restless child, and the seconds
/// actually counted are recorded alongside the rate so the register is
/// honest about how the number was made.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/glass.dart';
import '../../../core/theme/motion.dart';
import '../../shared/ui.dart';

class BreathCounter extends StatefulWidget {
  const BreathCounter({super.key, required this.onResult});

  /// Called when a count finishes with the per-minute rate and the seconds
  /// actually counted (60 or 30).
  final void Function(int ratePerMinute, int secondsCounted) onResult;

  @override
  State<BreathCounter> createState() => _BreathCounterState();
}

class _BreathCounterState extends State<BreathCounter> {
  int _windowSecs = 60;
  int _count = 0;
  int _elapsedTenths = 0;
  Timer? _timer;
  bool get _running => _timer != null;
  bool _finished = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    setState(() {
      _count = 0;
      _elapsedTenths = 0;
      _finished = false;
    });
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() => _elapsedTenths++);
      if (_elapsedTenths >= _windowSecs * 10) _finish();
    });
  }

  void _tap() {
    if (_finished) return;
    if (!_running) _start();
    setState(() => _count++);
    HapticFeedback.lightImpact();
  }

  void _finish() {
    _timer?.cancel();
    _timer = null;
    setState(() => _finished = true);
    widget.onResult(_rate, _secondsCounted);
  }

  /// Seconds actually counted: the full window, or the elapsed time when the
  /// count was stopped early (never less than one second).
  int get _secondsCounted {
    final elapsed = (_elapsedTenths / 10).round();
    return elapsed >= _windowSecs ? _windowSecs : (elapsed < 1 ? 1 : elapsed);
  }

  int get _rate => (_count * 60 / _secondsCounted).round();

  void _reset() {
    _timer?.cancel();
    _timer = null;
    setState(() {
      _count = 0;
      _elapsedTenths = 0;
      _finished = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_elapsedTenths / (_windowSecs * 10)).clamp(0.0, 1.0);
    final remaining = ((_windowSecs * 10 - _elapsedTenths) / 10).ceil();
    final fx = VisualEffects.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Window choice — disabled once a count is running.
        SegmentedButton<int>(
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            minimumSize: WidgetStatePropertyAll(Size(48, 40)),
          ),
          segments: const [
            ButtonSegment(value: 60, label: Text('Count 60s')),
            ButtonSegment(value: 30, label: Text('Count 30s ×2')),
          ],
          selected: {_windowSecs},
          onSelectionChanged: _running
              ? null
              : (s) => setState(() {
                  _windowSecs = s.first;
                  _count = 0;
                  _elapsedTenths = 0;
                  _finished = false;
                }),
        ),
        const SizedBox(height: Gap.md),
        Semantics(
          button: true,
          label: _finished
              ? 'Count finished, $_count breaths'
              : (_running
                    ? 'Tap for each breath. $remaining seconds left'
                    : 'Tap for each breath to start the count'),
          child: PressScale(
            onTap: _finished ? null : _tap,
            pressedScale: 0.96,
            radius: BorderRadius.circular(Gap.radius),
            child: GlassSurface(
              tier: GlassTier.card,
              blur: false,
              padding: const EdgeInsets.symmetric(vertical: Gap.md),
              child: Column(
                children: [
                  PulseRing(
                    active: _running,
                    progress: progress,
                    size: 180,
                    // The ring is a fixed 180px; at 200% text the count and
                    // its caption shrink to fit rather than spill out.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$_count',
                            style: AppType.numeral.copyWith(fontSize: 48),
                          ),
                          Text(
                            _finished
                                ? 'breaths'
                                : (_running
                                      ? '${remaining}s left'
                                      : 'tap to start'),
                            style: AppType.numeralUnit,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Gap.sm),
                  Text(
                    _finished
                        ? 'Done — $_rate breaths/min'
                        : 'Tap once for every breath',
                    style: AppType.label.copyWith(color: AppColors.inkMuted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: Gap.sm),
        // AnimatedSize with a zero duration re-dirties itself during layout,
        // so under reduced motion the buttons are laid out plainly.
        fx.motion
            ? AnimatedSize(duration: AppMotion.fast, child: _actions)
            : _actions,
      ],
    );
  }

  Widget get _actions => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: Gap.sm,
    children: [
      if (_running)
        TextButton.icon(
          onPressed: _finish,
          icon: const Icon(Icons.stop_circle_outlined, size: 18),
          label: const Text('Stop early'),
        ),
      if (_running || _finished)
        TextButton.icon(
          onPressed: _reset,
          icon: const Icon(Icons.replay_rounded, size: 18),
          label: const Text('Restart count'),
        ),
    ],
  );
}
