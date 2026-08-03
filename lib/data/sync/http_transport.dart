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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../local/outbox_dao.dart';
import '../local/preferences_store.dart';
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

  HttpClient? _client;

  HttpClient get _http {
    _client?.close();
    _client = HttpClient()
      ..connectionTimeout = timeout;
    return _client!;
  }

  @override
  Future<SendOutcome> send(OutboxEntry entry) async {
    final uri = Uri.parse('$baseUrl/api/sync');

    try {
      final request = await _http.postUrl(uri);
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      if (token != null) {
        request.headers.set('Authorization', 'Bearer $token');
      }

      final body = utf8.encode(jsonEncode({
        'entity_table': entry.entityTable,
        'entity_id': entry.entityId,
        'operation': entry.operation.name,
        'payload': entry.payload,
        'queued_at': entry.queuedAt.toIso8601String(),
        'client_version': '1.0.0',
      }));

      request.contentLength = body.length;
      request.add(body);

      final response = await request.close().timeout(timeout);
      final statusCode = response.statusCode;

      // Drain the response body so the connection can be reused.
      await response.drain<void>();

      if (statusCode >= 200 && statusCode < 300) {
        return const SendAccepted();
      }

      if (statusCode >= 400 && statusCode < 500) {
        return SendRejected(
          'Server rejected the record (HTTP $statusCode). '
          'It will not be retried.',
        );
      }

      // 5xx — server error, try again later.
      return SendUnavailable(
        'Server error (HTTP $statusCode). Will retry when backoff allows.',
      );
    } on TimeoutException {
      return const SendUnavailable(
        'Request timed out. The network may be too slow or the server is '
        'unreachable.',
      );
    } on SocketException catch (e) {
      return SendUnavailable('Network error: ${e.message}');
    } on HttpException catch (e) {
      return SendUnavailable('HTTP error: ${e.message}');
    } on FormatException {
      return SendRejected(
        'The base URL is malformed. Check the sync server address in settings.',
      );
    } catch (e) {
      return SendUnavailable('Unexpected error: $e');
    }
  }

  /// Creates a transport from the configured preferences, or returns null if
  /// no sync URL has been set (in which case [LoopbackTransport] is used).
  static Future<HttpSyncTransport?> fromPreferences() async {
    final url = await PreferencesStore.syncApiUrl();
    if (url == null || url.isEmpty) return null;
    final token = await PreferencesStore.syncApiToken();
    return HttpSyncTransport(baseUrl: url, token: token);
  }
}