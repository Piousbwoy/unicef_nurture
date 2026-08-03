/// Who is using the phone right now.
///
/// The threat model is a shared handset in a CHPS compound, so "session" means
/// something narrower than usual:
///
/// **The session is remembered, but the PIN is not.** The signed-in user id is
/// kept in secure storage so a CHO who is interrupted mid-visit — and the app is
/// killed by Android's memory manager, which happens constantly on a 2 GB
/// phone — comes back to their own account without retyping anything. The PIN
/// itself never leaves [Credentials.hashPin].
///
/// **Sign-out is explicit and cheap.** Handing the phone to a mother so she can
/// use caregiver mode must be one deliberate action, not a settings hunt.
///
/// **Lock-out is per-device and in-memory.** Five wrong PINs and the keypad
/// rests for thirty seconds. Deliberately not persisted: the point is to defeat
/// idle guessing by whoever picked the phone up, not to survive a reboot, and a
/// CHO locked out of a maternal emergency by a counter they cannot clear is a
/// worse outcome than a guessed PIN.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/local/user_dao.dart';
import '../../domain/entities/core.dart';
import '../../domain/enums.dart';

/// The states the app's shell switches on.
sealed class SessionState {
  const SessionState();
}

/// Still reading secure storage. Shows a splash, never a sign-in form — a
/// flash of the sign-in screen for a user who is already signed in reads as a
/// bug and invites a second, confusing login.
class SessionLoading extends SessionState {
  const SessionLoading();
}

/// Nobody has ever registered on this device. First-run setup, not sign-in.
class SessionNeedsSetup extends SessionState {
  const SessionNeedsSetup();
}

class SessionSignedOut extends SessionState {
  const SessionSignedOut({this.lastPhone, this.message});

  /// Pre-fills the phone field. Typing eleven digits on a cracked screen in the
  /// sun is a real cost, paid every single morning.
  final String? lastPhone;
  final String? message;
}

class SessionActive extends SessionState {
  const SessionActive(this.user, {this.linkedHouseholdId});

  final AppUser user;

  /// Only ever set for a caregiver. This is the boundary their whole world is
  /// scoped to, resolved once at sign-in so no screen has to look it up.
  final String? linkedHouseholdId;

  bool get isFhw => user.role.isFhw;
  bool get isCaregiver => user.role.isCaregiver;

  bool can(Permission p) => user.can(p);
}

/// Holds the session and nothing else. No navigation, no database schema
/// knowledge, no widgets — so it can be driven straight from a test.
class SessionController {
  SessionController({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _kUserIdKey = 'carebridge.session.user_id';
  static const _kLastPhoneKey = 'carebridge.session.last_phone';

  static const int maxAttempts = 5;
  static const Duration lockDuration = Duration(seconds: 30);

  final FlutterSecureStorage _storage;

  int _failedAttempts = 0;
  DateTime? _lockedUntil;

  /// Null while locked out.
  Duration? get lockRemaining {
    final until = _lockedUntil;
    if (until == null) return null;
    final left = until.difference(DateTime.now());
    return left.isNegative ? null : left;
  }

  int get attemptsRemaining => (maxAttempts - _failedAttempts).clamp(0, maxAttempts);

  /// Decides the opening screen.
  Future<SessionState> restore() async {
    if (!await UserDao.anyRegistered()) return const SessionNeedsSetup();

    final lastPhone = await _readLastPhone();
    final userId = await _read(_kUserIdKey);
    if (userId == null) return SessionSignedOut(lastPhone: lastPhone);

    final user = await UserDao.byId(userId);
    if (user == null) {
      // The account was removed under us. Clear the stale pointer rather than
      // leaving the app wedged on a user that no longer exists.
      await _delete(_kUserIdKey);
      return SessionSignedOut(lastPhone: lastPhone);
    }
    return SessionActive(user, linkedHouseholdId: await _linkedFor(user));
  }

  Future<SessionState> signIn({
    required String phone,
    required String pin,
  }) async {
    final remaining = lockRemaining;
    if (remaining != null) {
      return SessionSignedOut(
        lastPhone: phone,
        message:
            'Too many wrong attempts. Try again in ${remaining.inSeconds + 1} '
            'seconds.',
      );
    }

    final result = await UserDao.signIn(phone: phone.trim(), pin: pin);
    if (!result.isSuccess) {
      _failedAttempts++;
      if (_failedAttempts >= maxAttempts) {
        _lockedUntil = DateTime.now().add(lockDuration);
        _failedAttempts = 0;
        return SessionSignedOut(
          lastPhone: phone,
          message:
              'Too many wrong attempts. The keypad will unlock in '
              '${lockDuration.inSeconds} seconds.',
        );
      }
      return SessionSignedOut(
        lastPhone: phone,
        message: result.failure!.message,
      );
    }

    _failedAttempts = 0;
    _lockedUntil = null;

    final user = result.user!;
    await _write(_kUserIdKey, user.id);
    await _write(_kLastPhoneKey, user.phone);

    await AuditDao.record(
      action: 'sign in',
      outcome: 'allowed',
      actorId: user.id,
      actorRole: user.role.name,
    );

    return SessionActive(user, linkedHouseholdId: await _linkedFor(user));
  }

  /// Registers and immediately signs in.
  ///
  /// One step on purpose. Making a CHO register, then find the sign-in screen,
  /// then retype the PIN they invented four seconds ago is friction with no
  /// security value.
  Future<SessionState> registerAndSignIn({
    required AppUser user,
    required String pin,
    String? linkedHouseholdId,
  }) async {
    final saved = await UserDao.register(
      user: user,
      pin: pin,
      linkedHouseholdId: linkedHouseholdId,
    );
    await _write(_kUserIdKey, saved.id);
    await _write(_kLastPhoneKey, saved.phone);

    await AuditDao.record(
      action: 'register account',
      outcome: 'allowed',
      actorId: saved.id,
      actorRole: saved.role.name,
      detail: saved.role.label,
    );

    return SessionActive(saved, linkedHouseholdId: await _linkedFor(saved));
  }

  Future<SessionState> signOut(AppUser? current) async {
    if (current != null) {
      await AuditDao.record(
        action: 'sign out',
        outcome: 'allowed',
        actorId: current.id,
        actorRole: current.role.name,
      );
    }
    await _delete(_kUserIdKey);
    _failedAttempts = 0;
    _lockedUntil = null;
    return SessionSignedOut(lastPhone: await _readLastPhone());
  }

  /// Resets the PIN for a registered phone number, then returns a signed-out
  /// state so the user signs in with the new PIN.
  Future<SessionState> resetPin({
    required String phone,
    required String newPin,
  }) async {
    final ok = await UserDao.resetPin(phone: phone, newPin: newPin);
    if (!ok) return SessionSignedOut(lastPhone: phone);
    return SessionSignedOut(lastPhone: phone);
  }

  Future<String?> _linkedFor(AppUser user) async {
    // Only caregivers are scoped to a household. Reading it for an FHW would be
    // a wasted query on every launch.
    if (!user.role.isCaregiver) return null;
    return UserDao.linkedHouseholdFor(user.id);
  }

  Future<String?> _readLastPhone() => _read(_kLastPhoneKey);

  // Secure storage is unavailable on some desktop test hosts and can throw on
  // Android devices with a broken keystore. None of that is worth crashing an
  // app whose records are already safe in SQLite, so every access degrades to
  // "not remembered".
  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      /* Session simply is not remembered across restarts. */
    }
  }

  Future<void> _delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {
      /* Ignored for the same reason. */
    }
  }
}
