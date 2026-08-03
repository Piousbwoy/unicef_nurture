/// Background sync.
///
/// The honest framing: this app does not need the network to work. Sync is how
/// records eventually reach the district, not how care gets delivered. Every
/// design choice below follows from that.
///
/// **Opportunistic, never blocking.** Sync runs when connectivity appears and on
/// a slow timer. No screen ever waits for it, and no button says "upload" as
/// though the CHO were responsible for the network.
///
/// **Small batches, committed individually.** In Gushegu you might get ninety
/// seconds of EDGE signal. Twenty-five rows at a time, each marked synced on its
/// own success, means a window that closes halfway still made progress.
///
/// **Priority order.** An urgent referral leaves before eighty routine household
/// registrations. This is the difference between a sync queue and a sync queue
/// that saves someone.
///
/// **A stub transport.** There is no district server to talk to yet, and
/// pretending otherwise would be dishonest. [SyncTransport] is the seam: swap in
/// an HTTP or DHIMS2 implementation and nothing else in the app changes. The
/// bundled [LoopbackTransport] lets the whole pipeline be demonstrated and tested
/// end to end without inventing a backend.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../local/outbox_dao.dart';

/// The result of trying to send one entry.
sealed class SendOutcome {
  const SendOutcome();
}

class SendAccepted extends SendOutcome {
  const SendAccepted();
}

/// The server said no, and it will keep saying no. Stop retrying and show a
/// human.
class SendRejected extends SendOutcome {
  const SendRejected(this.reason);
  final String reason;
}

/// The network failed. Try again later; nothing is wrong with the record.
class SendUnavailable extends SendOutcome {
  const SendUnavailable(this.reason);
  final String reason;
}

/// The seam between this app and whatever it eventually uploads to — a district
/// endpoint, DHIMS2, or a facility server on a local network.
abstract interface class SyncTransport {
  Future<SendOutcome> send(OutboxEntry entry);
}

/// Accepts everything, so the outbox lifecycle can be demonstrated and tested
/// without a backend. Named for what it is; nobody should mistake it for
/// integration.
class LoopbackTransport implements SyncTransport {
  const LoopbackTransport({this.delay = const Duration(milliseconds: 40)});

  final Duration delay;

  @override
  Future<SendOutcome> send(OutboxEntry entry) async {
    await Future<void>.delayed(delay);
    return const SendAccepted();
  }
}

class SyncRunReport {
  const SyncRunReport({
    required this.attempted,
    required this.accepted,
    required this.rejected,
    required this.deferred,
  });

  final int attempted;
  final int accepted;
  final int rejected;
  final int deferred;

  bool get madeProgress => accepted > 0;

  @override
  String toString() =>
      'sync: $accepted sent, $rejected rejected, $deferred deferred '
      'of $attempted attempted';
}

class SyncService {
  SyncService({
    SyncTransport? transport,
    this.interval = const Duration(minutes: 15),
    this.batchSize = 25,
  }) : transport = transport ?? const LoopbackTransport();

  final SyncTransport transport;
  final Duration interval;
  final int batchSize;

  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _running = false;

  final _statusController = StreamController<SyncStatusSummary>.broadcast();
  final _connectivityController = StreamController<bool>.broadcast();

  /// Drives the banner at the top of the dashboard.
  Stream<SyncStatusSummary> get status => _statusController.stream;

  /// Whether the device currently has any kind of network connectivity.
  /// Every screen can listen to this; the dashboard pill is the most visible
  /// consumer, but a form screen could also warn before a submission attempt.
  Stream<bool> get connectivity => _connectivityController.stream;

  /// Starts opportunistic sync: on a timer, and immediately whenever
  /// connectivity returns.
  ///
  /// The connectivity listener matters more than the timer. A CHO walking back
  /// into range of a mast should have their morning's work leave the phone within
  /// seconds, without touching anything.
  Future<void> start() async {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => runOnce());

    _connectivitySub?.cancel();

    // Seed the connectivity stream with the current state so the first paint
    // is correct — no flash of "offline" on a device that has always been
    // online.
    final initial = await isOnline;
    if (!_connectivityController.isClosed) {
      _connectivityController.add(initial);
    }

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (!_connectivityController.isClosed) {
        _connectivityController.add(online);
      }
      if (online) runOnce();
    });

    await publishStatus();
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  Future<void> dispose() async {
    await stop();
    await _statusController.close();
    await _connectivityController.close();
  }

  Future<bool> get isOnline async {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  /// Sends one batch.
  ///
  /// Re-entrancy guarded: the timer and the connectivity listener can fire
  /// together, and two concurrent passes would double-send and double-count.
  Future<SyncRunReport> runOnce() async {
    if (_running) {
      return const SyncRunReport(
        attempted: 0,
        accepted: 0,
        rejected: 0,
        deferred: 0,
      );
    }
    _running = true;

    var accepted = 0;
    var rejected = 0;
    var deferred = 0;
    var attempted = 0;

    try {
      if (!await isOnline) {
        await publishStatus();
        return const SyncRunReport(
          attempted: 0,
          accepted: 0,
          rejected: 0,
          deferred: 0,
        );
      }

      final batch = await OutboxDao.pending(limit: batchSize);
      for (final entry in batch) {
        attempted++;
        final outcome = await transport.send(entry);
        switch (outcome) {
          case SendAccepted():
            await OutboxDao.markSynced(entry.id);
            accepted++;
          case SendRejected(reason: final r):
            await OutboxDao.markFailed(entry.id, 'Rejected: $r');
            rejected++;
          case SendUnavailable(reason: final r):
            await OutboxDao.markFailed(entry.id, r);
            deferred++;
            // The network has gone again. Stop the batch rather than burning
            // attempt counters on rows that were never going to send.
            return SyncRunReport(
              attempted: attempted,
              accepted: accepted,
              rejected: rejected,
              deferred: deferred,
            );
        }
      }
      return SyncRunReport(
        attempted: attempted,
        accepted: accepted,
        rejected: rejected,
        deferred: deferred,
      );
    } finally {
      _running = false;
      await publishStatus();
    }
  }

  /// Sends everything, in batches, until nothing is left or nothing moves.
  ///
  /// Behind the manual "send now" button, which exists purely so a CHO with a
  /// briefly good connection can feel in control of it.
  Future<SyncRunReport> drain({int maxBatches = 20}) async {
    var totals = const SyncRunReport(
      attempted: 0,
      accepted: 0,
      rejected: 0,
      deferred: 0,
    );
    for (var i = 0; i < maxBatches; i++) {
      final report = await runOnce();
      totals = SyncRunReport(
        attempted: totals.attempted + report.attempted,
        accepted: totals.accepted + report.accepted,
        rejected: totals.rejected + report.rejected,
        deferred: totals.deferred + report.deferred,
      );
      if (report.attempted == 0 || !report.madeProgress) break;
    }
    await OutboxDao.pruneSynced();
    return totals;
  }

  Future<SyncStatusSummary> publishStatus() async {
    final summary = await OutboxDao.summary();
    if (!_statusController.isClosed) _statusController.add(summary);
    return summary;
  }

  /// Rows a human has to look at, with their last error.
  Future<List<OutboxEntry>> stuck() => OutboxDao.failing();

  Future<void> retry(int outboxId) async {
    await OutboxDao.resetAttempts(outboxId);
    await runOnce();
  }
}
