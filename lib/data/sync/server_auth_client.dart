/// Per-user JWT auth client for the sync server.
///
/// Replaces the old one-size-fits-all SYNC_API_TOKEN with:
///   - /api/auth/login    → access_token (JWT) + refresh_token (opaque)
///   - /api/auth/refresh  → exchange refresh for a fresh access token
///   - /api/auth/logout   → revoke a refresh token (or all, for lost device)
///
/// Tokens live in [FlutterSecureStorage] (device-scoped, encrypted on Android
/// Keystore / iOS Keychain). They are:
///   - Written at sign-in (if a server URL is configured)
///   - Read on every HTTP call made by [HttpSyncTransport], and attached as
///     the Bearer authorization value. If the server returns 401, we
///     silently try refresh once, then retry the original call.
///   - Cleared at sign-out (and the server-side refresh token is revoked).
///
/// Legacy fallback: if no JWT is present (e.g. a device that hasn't signed in
/// with the server yet), we fall back to the static SYNC_API_TOKEN preference
/// the old flow used. The server supports both modes during a rollout window.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../local/preferences_store.dart';
import '../local/user_dao.dart';

class Tokens {
  const Tokens({
    required this.accessToken,
    required this.accessExpiresAt,
    required this.refreshToken,
  });

  final String accessToken;
  final DateTime accessExpiresAt;
  final String refreshToken;

  bool get isAccessExpired => DateTime.now().isAfter(accessExpiresAt);
}

class ServerAuthResult {
  const ServerAuthResult.ok(this.tokens, this.user) : error = null;
  const ServerAuthResult.err(this.error)
      : tokens = null,
        user = null;

  final Tokens? tokens;
  final Map<String, Object?>? user;
  final String? error;

  bool get isOk => tokens != null;
}

abstract final class ServerAuthClient {
  static const _kAccess = 'carebridge.auth.access_token';
  static const _kRefresh = 'carebridge.auth.refresh_token';
  static const _kAccessExp = 'carebridge.auth.access_expires_at_iso';
  static const _kDeviceId = 'carebridge.auth.device_id';

  static FlutterSecureStorage? _storageOverride;
  // ignore: use_setters_to_change_properties
  static void injectStorage(FlutterSecureStorage s) => _storageOverride = s;
  static FlutterSecureStorage get _storage =>
      _storageOverride ?? const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
        iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
      );

  static String? _cachedDeviceId;
  static Future<String> deviceId() async {
    final c = _cachedDeviceId;
    if (c != null) return c;
    final existing = await _safeRead(_kDeviceId);
    if (existing != null && existing.isNotEmpty) {
      _cachedDeviceId = existing;
      return existing;
    }
    final bytes = List<int>.generate(16, (i) => _randByte());
    final buf = StringBuffer('cb-');
    for (final b in bytes) {
      buf.write(b.toRadixString(16).padLeft(2, '0'));
    }
    final id = buf.toString();
    await _safeWrite(_kDeviceId, id);
    _cachedDeviceId = id;
    return id;
  }

  static int _randByte() {
    try {
      return (DateTime.now().microsecondsSinceEpoch.hashCode ^
              (Zone.current['hash'] as int? ?? 0)) &
          0xFF;
    } catch (_) {
      return DateTime.now().microsecond & 0xFF;
    }
  }

  // -------------------------------------------------------------------- store
  static Future<Tokens?> loadTokens() async {
    final access = await _safeRead(_kAccess);
    final refresh = await _safeRead(_kRefresh);
    final exp = await _safeRead(_kAccessExp);
    if (access == null || refresh == null || exp == null) return null;
    final expiresAt = DateTime.tryParse(exp);
    if (expiresAt == null) return null;
    return Tokens(
      accessToken: access,
      accessExpiresAt: expiresAt,
      refreshToken: refresh,
    );
  }

  static Future<void> saveTokens(Tokens t) async {
    await _safeWrite(_kAccess, t.accessToken);
    await _safeWrite(_kRefresh, t.refreshToken);
    await _safeWrite(_kAccessExp, t.accessExpiresAt.toIso8601String());
  }

  static Future<void> clearTokens() async {
    await Future.wait([
      _safeDelete(_kAccess),
      _safeDelete(_kRefresh),
      _safeDelete(_kAccessExp),
    ]);
  }

  // ------------------------------------------------------------- token picker
  /// Returns the current best Authorization header value, or null if there is
  /// no credential at all. Prefers JWT; falls back to legacy sync API token.
  static Future<String?> pickAuthorization() async {
    final t = await loadTokens();
    if (t != null && !t.isAccessExpired) return 'Bearer ${t.accessToken}';
    final legacy = await PreferencesStore.syncApiToken();
    if (legacy != null && legacy.trim().isNotEmpty) return 'Bearer $legacy';
    // Still might have a JWT that just needs refresh — caller must decide
    // whether to trigger a refresh based on 401 responses. Here we return
    // the expired access token if we have one; the HTTP layer will know to
    // refresh on 401.
    if (t != null) return 'Bearer ${t.accessToken}';
    return null;
  }

  // -------------------------------------------------------------------- login
  static Future<ServerAuthResult> signIn({
    required String phone,
    required String pin,
  }) async {
    final base = await PreferencesStore.syncApiUrl();
    if (base == null || base.isEmpty) {
      return const ServerAuthResult.err(
        'No sync server URL is configured. Use the demo mode or configure a server.',
      );
    }
    final cleanPhone = phone.trim();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      // ─── Step 1: CHALLENGE ────────────────────────────────────────────────
      // Unauthenticated fetch. Server returns user_id + server_salt (public,
      // non-secret). The PIN is NEVER placed on the wire here or at any step.
      final challengeUri = Uri.parse('$base/api/auth/challenge')
          .replace(queryParameters: {'phone': cleanPhone});
      final challengeReq = await client.getUrl(challengeUri);
      challengeReq.headers.set('Accept', 'application/json');
      final challengeResp = await challengeReq.close().timeout(const Duration(seconds: 15));
      final challengeTxt = await challengeResp.transform(utf8.decoder).join();
      final csc = challengeResp.statusCode;
      if (csc == 429) {
        final retry = (jsonDecode(challengeTxt) as Map<String, Object?>?)?['retry_after_seconds'];
        final s = retry is int ? ' Retry after $retry seconds.' : '';
        return ServerAuthResult.err('Too many sign-in attempts.$s');
      }
      if (csc != 200) {
        final msg = (jsonDecode(challengeTxt) as Map<String, Object?>?)?['error'] ??
            'Challenge endpoint returned HTTP $csc';
        return ServerAuthResult.err(msg.toString());
      }
      final challengeJson = jsonDecode(challengeTxt) as Map<String, Object?>;
      final serverSalt = challengeJson['server_salt'] as String?;
      if (serverSalt == null || serverSalt.isEmpty) {
        return const ServerAuthResult.err('Server did not issue a challenge salt.');
      }

      // ─── Step 2: LOCAL VERIFIER COMPUTATION ───────────────────────────────
      // Pin, phone, and server_salt are transformed into a domain-separated
      // iterated HMAC (120k iterations). The on-device pin_hash/pin_salt are
      // never referenced here — a blank replacement device never needs them.
      // The server never sees the raw PIN.
      final verifierResponse = Credentials.computeCloudVerifierFromPin(
        pin: pin,
        phone: cleanPhone,
        serverSalt: serverSalt,
      );

      // ─── Step 3: LOGIN WITH VERIFIER RESPONSE ─────────────────────────────
      // Post verifier_response (NOT pin) + phone + device_id. Server performs
      // constant-time compare against the isolated user_verifiers table.
      final uri = Uri.parse('$base/api/auth/login');
      final req = await client.postUrl(uri);
      req.headers.set('Content-Type', 'application/json; charset=utf-8');
      final body = utf8.encode(jsonEncode({
        'phone': cleanPhone,
        'verifier_response': verifierResponse,
        'device_id': await deviceId(),
      }));
      req.contentLength = body.length;
      req.add(body);
      final resp = await req.close().timeout(const Duration(seconds: 20));
      final txt = await resp.transform(utf8.decoder).join();
      final sc = resp.statusCode;
      if (sc == 429) {
        final retry = (jsonDecode(txt) as Map<String, Object?>?)?['retry_after_seconds'];
        final s = retry is int ? ' Retry after $retry seconds.' : '';
        return ServerAuthResult.err('Too many sign-in attempts.$s');
      }
      if (sc != 200) {
        final msg = (jsonDecode(txt) as Map<String, Object?>?)?['error'] ??
            'Server returned HTTP $sc';
        return ServerAuthResult.err(msg.toString());
      }
      final data = jsonDecode(txt) as Map<String, Object?>;
      final access = data['access_token'] as String?;
      final refresh = data['refresh_token'] as String?;
      final expIn = (data['expires_in'] as num?)?.toInt();
      final user = data['user'] as Map<String, Object?>?;
      if (access == null || refresh == null || expIn == null) {
        return const ServerAuthResult.err('Invalid server response.');
      }
      final tokens = Tokens(
        accessToken: access,
        accessExpiresAt:
            DateTime.now().add(Duration(seconds: expIn.clamp(60, 86400 * 7))),
        refreshToken: refresh,
      );
      await saveTokens(tokens);
      return ServerAuthResult.ok(tokens, user);
    } on SocketException catch (e) {
      return ServerAuthResult.err('Network error: ${e.message}');
    } on TimeoutException {
      return const ServerAuthResult.err('Sign-in timed out. Try again when network is available.');
    } on FormatException catch (e) {
      return ServerAuthResult.err('Invalid URL: ${e.message}');
    } catch (e) {
      return ServerAuthResult.err('Sign-in error: $e');
    } finally {
      client.close();
    }
  }

  // ------------------------------------------------------------------- refresh
  static Future<ServerAuthResult> refreshAccessToken() async {
    final base = await PreferencesStore.syncApiUrl();
    final t = await loadTokens();
    if (base == null || base.isEmpty || t == null) {
      return const ServerAuthResult.err('Nothing to refresh.');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final uri = Uri.parse('$base/api/auth/refresh');
      final req = await client.postUrl(uri);
      req.headers.set('Content-Type', 'application/json; charset=utf-8');
      final body = utf8.encode(jsonEncode({
        'refresh_token': t.refreshToken,
        'device_id': await deviceId(),
      }));
      req.contentLength = body.length;
      req.add(body);
      final resp = await req.close().timeout(const Duration(seconds: 20));
      final txt = await resp.transform(utf8.decoder).join();
      if (resp.statusCode != 200) {
        await clearTokens();
        final msg = (jsonDecode(txt) as Map<String, Object?>?)?['error'] ??
            'Refresh failed (HTTP ${resp.statusCode}). Please sign in again.';
        return ServerAuthResult.err(msg.toString());
      }
      final data = jsonDecode(txt) as Map<String, Object?>;
      final access = data['access_token'] as String?;
      final expIn = (data['expires_in'] as num?)?.toInt();
      if (access == null || expIn == null) {
        return const ServerAuthResult.err('Invalid refresh response.');
      }
      final updated = Tokens(
        accessToken: access,
        accessExpiresAt: DateTime.now().add(Duration(seconds: expIn.clamp(60, 86400 * 7))),
        refreshToken: t.refreshToken,
      );
      await saveTokens(updated);
      return ServerAuthResult.ok(updated, null);
    } catch (e) {
      return ServerAuthResult.err(e.toString());
    } finally {
      client.close();
    }
  }

  // ------------------------------------------------------------------ logout
  static Future<void> signOut({bool allDevices = false}) async {
    final base = await PreferencesStore.syncApiUrl();
    final t = await loadTokens();
    if (base != null && base.isNotEmpty && t != null) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      try {
        final uri = Uri.parse('$base/api/auth/logout');
        final req = await client.postUrl(uri);
        req.headers.set('Content-Type', 'application/json; charset=utf-8');
        req.headers.set('Authorization', 'Bearer ${t.accessToken}');
        final body = utf8.encode(jsonEncode({
          'refresh_token': t.refreshToken,
          'all_devices': allDevices,
        }));
        req.contentLength = body.length;
        req.add(body);
        await req.close().timeout(const Duration(seconds: 15));
      } catch (_) {
        // Offline — just wipe the local tokens; server-side revocation is
        // best-effort. The user will still be signed out locally and any
        // remaining refresh token lifetime is bounded by JWT_REFRESH_TTL_DAYS.
      } finally {
        client.close();
      }
    }
    await clearTokens();
  }

  // ------------------------------------------------------------------ helpers
  static Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _safeWrite(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      /* Ignored. */
    }
  }

  static Future<void> _safeDelete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {
      /* Ignored. */
    }
  }
}
