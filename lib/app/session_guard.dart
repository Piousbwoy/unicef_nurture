/// The app shell's inactivity lock.
///
/// One widget, mounted once, that owns the whole question — so no screen has to
/// remember to report activity and no screen can forget. A lock implemented as a
/// callback inside each feature is a lock that the next feature does not have.
///
/// ## What it does
/// Watches the signed-in user's role, gives [IdleLockPolicy.forRole] a watchdog,
/// counts every pointer-down as activity, ticks slowly to catch an untouched
/// screen, and evaluates the away-from-app window on resume rather than by timer
/// — because Android suspends Dart timers with the app, so a periodic check would
/// be the one thing that never fires while she is away.
///
/// ## What it deliberately does not do
/// It does not treat `inactive` as leaving. On Android that state covers an
/// incoming-call overlay, a permission dialog and a notification shade pulled
/// down over the record — moments when she is still standing at the compound
/// with the phone in her hand. Locking on those would train a worker to distrust
/// the app during a delivery, which is worse than the risk being managed.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/idle_lock.dart';
import '../domain/entities/core.dart';
import 'providers.dart';

class SessionGuard extends ConsumerStatefulWidget {
  const SessionGuard({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SessionGuard> createState() => _SessionGuardState();
}

class _SessionGuardState extends ConsumerState<SessionGuard> {
  static const _tickInterval = Duration(seconds: 30);

  AppLifecycleListener? _lifecycle;
  IdleWatchdog? _watchdog;
  Timer? _ticker;
  String _armedForUserId;

  _SessionGuardState() : _armedForUserId = '';

  @override
  Widget build(BuildContext context) {
    _adopt(ref.watch(currentUserProvider));
    return Listener(
      // Translucent so a tap is seen whether or not a descendant claims it. The
      // Listener never absorbs anything itself, so children still receive it.
      onPointerDown: (_) => _watchdog?.touched(),
      behavior: HitTestBehavior.translucent,
      child: widget.child,
    );
  }

  /// Installs or drops the watchdog as the session changes.
  void _adopt(AppUser? user) {
    final id = user?.id ?? '';
    if (id == _armedForUserId) return;
    _armedForUserId = id;

    _ticker?.cancel();
    _ticker = null;
    _watchdog = null;
    _lifecycle?.dispose();
    _lifecycle = null;

    if (user == null) return;
    final policy = IdleLockPolicy.forRole(user.role);
    // A family's own handset gets no watchdog at all, and no lifecycle listener
    // to pay for.
    if (!policy.isLive) return;

    _watchdog = IdleWatchdog(policy: policy)..rearm();
    _lifecycle = AppLifecycleListener(
      // `paused` is the leaving signal. `inactive` is deliberately not used:
      // on Android it also covers an incoming-call overlay, a permission dialog
      // and a pulled notification shade — moments when the phone is still in her
      // hand at the compound.
      onPause: _wentAway,
      onResume: _cameBack,
    );
    _ticker = Timer.periodic(_tickInterval, (_) => _tick());
  }

  void _wentAway() => _watchdog?.backgrounded();

  void _cameBack() => _lockFor(_watchdog?.onResumed());

  void _tick() => _lockFor(_watchdog?.onTick());

  Future<void> _lockFor(LockReason? reason) async {
    if (reason == null || !mounted) return;
    // Idempotent by construction: the notifier refuses when there is no active
    // session, so a resume that lands twice writes one audit row, not two.
    await ref.read(sessionProvider.notifier).lockIfIdle(reason);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }
}
