/// When a session must be re-authenticated instead of simply resumed.
///
/// ### The tension this sits inside
///
/// [SessionController] deliberately remembers who is signed in, because a CHO
/// whose app is killed by Android's memory manager mid-visit — constantly, on a
/// 2 GB handset — must come back to her own account without retyping anything.
/// That is a real clinical need, and an inactivity lock is the thing that takes
/// it away. So this is not "add a timer": it is a line drawn between an
/// interruption and an unattended device.
///
/// **Away from the app is the short window.** A handset that goes to the lock
/// screen or is switched away is a handset that can be picked up by somebody
/// else, which is the exact shared-device risk this app's threat model names.
///
/// **On screen is the long window.** A worker standing at a CHPS compound with
/// the record open, writing in a paper register beside the phone, is idle in the
/// stopwatch sense and is not idle in the risk sense. Five minutes of untouched
/// screen is long enough to matter and short enough to be survivable.
///
/// ### Why a family's own handset is excluded
///
/// `autoLogoff` in 45 CFR 164.312(a)(2)(iii) is about a *workstation* holding
/// protected health information in a facility. A mother's phone is her own
/// device, and locking her out of her child's record does not reduce a privacy
/// risk — it removes the one person with a legitimate right to look at it. So
/// [IdleLockPolicy.off] applies to caregivers, and this is stated rather than
/// assumed because someone will ask why the family screen behaves differently.
///
/// ### Why the wall clock, not the test clock
///
/// [IdleWatchdog] reads `DateTime.now()` directly. Widget tests advance a fake
/// clock by pumps; if the watchdog followed that clock, any test that pumped a
/// few minutes of clinical flow would find itself locked out mid-assertion. The
/// control is meant to measure real elapsed time on a real device, so that is
/// what it measures.
library;

import '../../domain/enums.dart';

/// Why a session was locked. Carried through to the sign-in screen so the
/// message can say what happened instead of implying she signed out.
enum LockReason { idle, backgrounded }

class IdleLockPolicy {
  const IdleLockPolicy({
    required this.idleInForeground,
    required this.lockAfterBackgrounding,
  });

  /// Never locks. Used for caregiver sessions.
  static const IdleLockPolicy off = IdleLockPolicy(
    idleInForeground: null,
    lockAfterBackgrounding: null,
  );

  static const IdleLockPolicy fieldWorker = IdleLockPolicy(
    idleInForeground: Duration(minutes: 5),
    lockAfterBackgrounding: Duration(minutes: 2),
  );

  static IdleLockPolicy forRole(UserRole role) =>
      role.isCaregiver ? off : fieldWorker;

  /// Null means this dimension never locks.
  final Duration? idleInForeground;
  final Duration? lockAfterBackgrounding;

  bool get isLive => idleInForeground != null || lockAfterBackgrounding != null;

  /// The reason to lock now, or null to leave the session alone.
  ///
  /// [backgroundedFor] is null while the app is in the foreground. Being away
  /// from the app is checked first: it is the stronger signal, and when both are
  /// true the message should describe the phone leaving her hand rather than an
  /// untouched screen.
  LockReason? reasonFor({
    required Duration idleFor,
    Duration? backgroundedFor,
  }) {
    final away = lockAfterBackgrounding;
    if (backgroundedFor != null && away != null && backgroundedFor >= away) {
      return LockReason.backgrounded;
    }
    final onScreen = idleInForeground;
    if (backgroundedFor == null && onScreen != null && idleFor >= onScreen) {
      return LockReason.idle;
    }
    return null;
  }

  /// Written for a keypad screen, in the app's plain register: it says what
  /// happened and what to do, and it never suggests she signed out — because she
  /// did not, and the audit trail will say so too.
  String messageFor(LockReason reason) => switch (reason) {
    LockReason.idle =>
      'Locked after ${_spoken(idleInForeground)} without any taps. Enter your '
          'PIN to continue.',
    LockReason.backgrounded =>
      'Locked because the app was away for ${_spoken(lockAfterBackgrounding)}. '
          'Enter your PIN to continue.',
  };

  static String _spoken(Duration? d) {
    final minutes = d?.inMinutes ?? 0;
    if (minutes <= 0) return 'a moment';
    return '$minutes minute${minutes == 1 ? '' : 's'}';
  }
}

/// Tracks activity and decides when the session has to be re-authenticated.
///
/// A plain class rather than a notifier so it can be driven from a test without
/// a widget tree, and so the app shell owns exactly one clock reading path.
class IdleWatchdog {
  IdleWatchdog({required this.policy, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final IdleLockPolicy policy;
  final DateTime Function() _now;

  DateTime? _lastActivity;
  DateTime? _backgroundedAt;

  /// Any tap, key or scroll. Called from the shell's pointer listener, so no
  /// screen has to remember to report itself — a lock that depends on every
  /// future screen opting in is a lock that some screen will forget.
  void touched() {
    _lastActivity = _now();
    // Interaction while suspended-but-visible means she is looking at the record;
    // the background window only counts from the moment she actually leaves.
    if (_backgroundedAt != null && policy.isLive) _backgroundedAt = null;
  }

  void backgrounded() {
    _backgroundedAt ??= _now();
  }

  /// Called on resume. The background window is evaluated here rather than by a
  /// timer, because Android stops Dart timers with the app — the honest place to
  /// notice she has been away is the moment she comes back.
  LockReason? onResumed() {
    final away = _backgroundedAt;
    _backgroundedAt = null;
    if (away == null || !policy.isLive) return null;
    final reason = policy.reasonFor(
      idleFor: _now().difference(_lastActivity ?? away),
      backgroundedFor: _now().difference(away),
    );
    if (reason != null) _lastActivity = _now();
    return reason;
  }

  /// The foreground idle check, run on a slow tick.
  LockReason? onTick() {
    if (!policy.isLive) return null;
    final since = _lastActivity;
    if (since == null) return null;
    final reason = policy.reasonFor(
      idleFor: _now().difference(since),
      backgroundedFor: _backgroundedAt == null
          ? null
          : _now().difference(_backgroundedAt!),
    );
    // Reset so a lock is offered once rather than re-firing every tick while the
    // sign-in screen is up.
    if (reason != null) _lastActivity = _now();
    return reason;
  }

  /// Starts counting from now. Called when a session becomes active, so the
  /// window is measured from the PIN she just typed and not from whenever the
  /// app last happened to touch a screen.
  void rearm() {
    _lastActivity = _now();
    _backgroundedAt = null;
  }
}
