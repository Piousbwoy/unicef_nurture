import 'dart:async';
import 'dart:isolate';

/// Request IDs prevent late results from being delivered to another request.
/// Worker failures never forward raw exception messages or input text.
class NativeInferenceWorker {
  NativeInferenceWorker._();
  final _responses = ReceivePort();
  final _ready = Completer<SendPort>();
  final _pending = <int, Completer<Object?>>{};
  late StreamSubscription<dynamic> _subscription;
  SendPort? _commands;
  bool _closed = false;
  int _nextId = 0;
  Future<void>? _disposing;

  static Future<NativeInferenceWorker> start(
    void Function(SendPort) entry,
  ) async {
    final worker = NativeInferenceWorker._();
    worker._subscription = worker._responses.listen(worker._receive);
    try {
      await Isolate.spawn(
        entry,
        worker._responses.sendPort,
        onExit: worker._responses.sendPort,
        onError: worker._responses.sendPort,
      );
      worker._commands = await worker._ready.future;
      return worker;
    } catch (_) {
      await worker.dispose();
      rethrow;
    }
  }

  void _receive(dynamic message) {
    if (message is SendPort) {
      _ready.complete(message);
    } else if (message is Map) {
      final pending = _pending.remove(message['id']);
      if (message['error'] == true) {
        pending?.completeError(
          StateError(
            'Local inference failed (${message['stage'] ?? 'runtime'}: ${message['kind'] ?? 'unknown'})',
          ),
        );
      } else {
        pending?.complete(message['value']);
      }
    } else {
      _closed = true;
      if (!_ready.isCompleted) {
        _ready.completeError(StateError('Inference worker unavailable'));
      }
      for (final pending in _pending.values) {
        pending.completeError(StateError('Inference worker stopped'));
      }
      _pending.clear();
    }
  }

  Future<Object?> request(String operation, [Map<String, Object?>? data]) {
    if (_closed ||
        _commands == null ||
        (_disposing != null && operation != 'dispose')) {
      return Future.error(StateError('Inference worker unavailable'));
    }
    final id = ++_nextId;
    final result = Completer<Object?>();
    _pending[id] = result;
    _commands!.send({'id': id, 'operation': operation, ...?data});
    return result.future;
  }

  Future<void> dispose() => _disposing ??= _dispose();
  Future<void> _dispose() async {
    try {
      if (!_closed && _commands != null) await request('dispose');
    } finally {
      _closed = true;
      await _subscription.cancel();
      _responses.close();
    }
  }
}
