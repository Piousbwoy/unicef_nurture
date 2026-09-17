/// HTTP sync transport — the real bridge to a MariaDB-backed district server.
///
/// Replaces [LoopbackTransport] when an API endpoint is configured. Sends each
/// [OutboxEntry] as a JSON POST to the configured sync endpoint, which persists
/// the record to MariaDB and returns an acknowledgement.
///
/// **Error handling:**
/// - 2xx → [SendAccepted] — the server has the record, mark it synced.
/// - 4xx → [SendRejected] — the server says this record is invalid (wrong
///   schema, duplicate, permission denied). Stop retrying; show a human.
/// - 5xx / network error / timeout → [SendUnavailable] — the server or the
///   network is down. Try again later with backoff.
///
/// **Authentication:** a Bearer token is sent with every request. The token is
/// read from [PreferencesStore] so it can be set once during device setup and
/// survive restarts.
///
/// **Timeout:** 30 seconds per entry. On a 2G connection in Gushegu a single
/// record may take several seconds, but 30 seconds is the point where the user
/// has definitely lost signal and the battery is better spent waiting.
library;

import 'dart:convert';

import '../local/outbox_dao.dart';
import '../local/preferences_store.dart';
import 'http_client.dart';
import 'server_auth_client.dart';
import 'sync_service.dart';

class HttpSyncTransport implements SyncTransport {
  HttpSyncTransport({
    required this.baseUrl,
    this.token,
    this.timeout = const Duration(seconds: 30),
  });

  /// The root URL of the sync API, e.g. `https://district.example.com`.
  /// Entries are POSTed to `$baseUrl/api/sync`.
  final String baseUrl;

  /// Bearer token for authentication. If null, no Authorization header is sent.
  final String? token;

  /// Per-entry request timeout.
  final Duration timeout;

  @override
  Future<SendOutcome> send(OutboxEntry entry) async {
    final uri = Uri.tryParse('$baseUrl/api/sync');
    if (uri == null || uri.host.isEmpty) {
      // A mistyped address is a configuration error, not a network blip —
      // retrying it would never help, so classify as rejected.
      return const SendRejected(
        'The base URL is malformed. Check the sync server address in settings.',
      );
    }
    final initialAuth = await _resolveAuthHeader();

    final HttpReply first;
    try {
      first = await _postOnce(uri: uri, entry: entry, auth: initialAuth);
    } on HttpFailure catch (e) {
      return _mapFailure(e);
    }

    if (first.statusCode == 401 && initialAuth != null) {
      // Silent refresh, then retry once. If refresh fails, fall back to
      // returning the original 401 outcome so the operator sees a
      // "permission denied / please sign in" hint at the drainer layer.
      final refreshed = await ServerAuthClient.refreshAccessToken();
      if (refreshed.isOk) {
        final retryAuth = await _resolveAuthHeader();
        try {
          final retry = await _postOnce(uri: uri, entry: entry, auth: retryAuth);
          return _classify(retry.statusCode);
        } on HttpFailure catch (e) {
          return _mapFailure(e);
        }
      }
    }
    return _classify(first.statusCode);
  }

  /// One POST attempt through the platform-neutral HTTP layer. Throws
  /// [HttpFailure] for anything that never produced a reply.
  Future<HttpReply> _postOnce({
    required Uri uri,
    required OutboxEntry entry,
    required String? auth,
  }) {
    return PlatformHttpClient.post(
      uri,
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': ?auth,
      },
      body: jsonEncode({
        'entity_table': entry.entityTable,
        'entity_id': entry.entityId,
        'operation': entry.operation.name,
        'payload': entry.payload,
        'queued_at': entry.queuedAt.toIso8601String(),
        'client_version': '1.1.0',
      }),
      timeout: timeout,
    );
  }

  /// Translates a transport-level failure into the same honest outcomes the
  /// drainer expects — unavailable (retry later) versus rejected (config error).
  SendOutcome _mapFailure(HttpFailure e) {
    switch (e.kind) {
      case HttpFailureKind.timeout:
        return const SendUnavailable(
          'Request timed out. The network may be too slow or the server is '
          'unreachable.',
        );
      case HttpFailureKind.network:
        return SendUnavailable('Network error: ${e.message}');
      case HttpFailureKind.malformedUrl:
        return const SendRejected(
          'The base URL is malformed. Check the sync server address in settings.',
        );
    }
  }

  SendOutcome _classify(int statusCode) {
    if (statusCode >= 200 && statusCode < 300) {
      return const SendAccepted();
    }
    if (statusCode >= 400 && statusCode < 500) {
      final hint = statusCode == 401
          ? ' Your session may have expired — sign in again if prompted.'
          : '';
      return SendRejected(
        'Server rejected the record (HTTP $statusCode).$hint '
        'It will not be retried.',
      );
    }
    return SendUnavailable(
      'Server error (HTTP $statusCode). Will retry when backoff allows.',
    );
  }

  Future<String?> _resolveAuthHeader() async {
    if (token != null && token!.trim().isNotEmpty) {
      // Explicit token override (e.g. demo server, tests).
      return token!.startsWith('Bearer ') ? token : 'Bearer $token';
    }
    return ServerAuthClient.pickAuthorization();
  }

  /// Creates a transport from the configured preferences, or returns null if
  /// no sync URL has been set (in which case [LoopbackTransport] is used).
  static Future<HttpSyncTransport?> fromPreferences() async {
    final url = await PreferencesStore.effectiveSyncApiUrl();
    if (url.isEmpty) return null;
    // Auth is resolved per-request via ServerAuthClient.pickAuthorization() so
    // we can transparently pick JWT → legacy-token → empty without requiring
    // a rebuild of the transport on sign-in / sign-out events.
    return HttpSyncTransport(baseUrl: url, token: null);
  }
}