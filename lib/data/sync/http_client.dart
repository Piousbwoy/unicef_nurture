/// Platform-neutral HTTP for the sync stack.
///
/// The web build runs inside a browser, where `dart:io`'s [HttpClient] does
/// not exist. Every request the old sync/auth files made there failed before
/// it ever reached the network, and the surrounding best-effort catch blocks
/// turned that into silent data loss. This file is now the single door through
/// which every request to the district server passes.
///
/// `package:http` picks the correct transport for the running platform
/// automatically: `IOClient` on Android/desktop, `BrowserClient` (XHR) on web.
///
/// Errors are translated into one small taxonomy ([HttpFailure]) so callers
/// never need platform-specific catch blocks:
///   - [HttpFailureKind.network] — DNS failure, refused connection, offline
///     browser, CORS block: anything where no reply was received.
///   - [HttpFailureKind.timeout] — the server did not answer in time.
///   - [HttpFailureKind.malformedUrl] — the configured address is not usable.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A complete HTTP reply: status code plus decoded body text.
class HttpReply {
  const HttpReply(this.statusCode, this.bodyText);

  final int statusCode;
  final String bodyText;

  /// Parsed JSON body when it is a JSON object, else null. Never throws —
  /// HTML error pages from captive portals are a normal condition here.
  Map<String, dynamic>? get jsonBody {
    try {
      final decoded = jsonDecode(bodyText);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

/// Why a request never produced an [HttpReply].
enum HttpFailureKind {
  /// No reply at all: DNS, refused socket, offline browser, CORS block.
  network,

  /// The server did not answer within the caller's timeout.
  timeout,

  /// The configured address is not a usable URL.
  malformedUrl,
}

class HttpFailure implements Exception {
  const HttpFailure(this.kind, this.message);

  final HttpFailureKind kind;
  final String message;

  @override
  String toString() => 'HttpFailure(${kind.name}): $message';
}

/// The single entry point for every sync-stack HTTP request.
abstract final class PlatformHttpClient {
  /// Default request timeout. Long enough for a 2G link to answer, short
  /// enough that a dead server cannot stall a sync batch for minutes.
  static const Duration defaultTimeout = Duration(seconds: 15);

  /// Test seam: when set, [send] routes through this instead of the network.
  /// Fakes return an [HttpReply] directly, or throw [HttpFailure] to simulate
  /// transport-level problems.
  static Future<HttpReply> Function(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  )? override;

  static Future<HttpReply> send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    String? body,
    Duration timeout = defaultTimeout,
  }) async {
    final viaOverride = override;
    if (viaOverride != null) {
      return viaOverride(method, uri, Map.of(headers), body);
    }
    final client = http.Client();
    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) {
        request.bodyBytes = utf8.encode(body);
        request.contentLength = request.bodyBytes.length;
      }
      final streamed = await client.send(request).timeout(timeout);
      final text = await streamed.stream
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      return HttpReply(streamed.statusCode, text);
    } on TimeoutException {
      throw HttpFailure(
        HttpFailureKind.timeout,
        'no answer within ${timeout.inSeconds}s',
      );
    } on ArgumentError catch (e) {
      throw HttpFailure(
        HttpFailureKind.malformedUrl,
        e.message?.toString() ?? 'unusable URL',
      );
    } on Exception catch (e) {
      // Refused sockets, DNS failure, ClientException from package:http (which
      // also covers CORS blocks and "Failed to fetch" in the browser), and any
      // other transport-level exception. None of these are dart:io types, so
      // this works identically on every platform.
      throw HttpFailure(HttpFailureKind.network, e.toString());
    } finally {
      client.close();
    }
  }

  static Future<HttpReply> get(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration timeout = defaultTimeout,
  }) =>
      send('GET', uri, headers: headers, timeout: timeout);

  static Future<HttpReply> post(
    Uri uri, {
    Map<String, String> headers = const {},
    String? body,
    Duration timeout = defaultTimeout,
  }) =>
      send('POST', uri, headers: headers, body: body, timeout: timeout);
}
