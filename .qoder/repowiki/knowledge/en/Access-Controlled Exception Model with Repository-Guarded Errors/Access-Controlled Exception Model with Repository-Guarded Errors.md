---
kind: error_handling
name: Access-Controlled Exception Model with Repository-Guarded Errors
category: error_handling
scope:
    - '**'
source_files:
    - lib/data/repositories/care_repository.dart
    - lib/app/providers.dart
    - lib/presentation/shared/ui.dart
    - lib/presentation/assessment/assessment_screen.dart
    - lib/core/auth/session.dart
    - lib/data/local/app_database.dart
---

The CareBridge AI Flutter app uses a single, repository-enforced exception model for error handling, centered on one custom exception type and consistent try/catch patterns at the data boundary.

**System/approach used**
- A dedicated `AccessDenied` exception class (implements `Exception`) is thrown whenever a user lacks the required `Permission`. It carries an `action`, an optional `Permission`, and an optional `detail`, and exposes a user-facing `message` getter. The comment in `care_repository.dart` explicitly states that permission failures are treated as exceptions rather than null returns so they cannot be ignored accidentally.
- Presentation layers use Riverpod `FutureProvider`s which propagate errors upward; screens handle them via `.when(error: ...)` callbacks and render either `AccessDeniedView` or `ErrorView` from `lib/presentation/shared/ui.dart`.
- Low-level I/O (secure storage, SQLite) uses bare `try/catch (_) {}` blocks that degrade gracefully to null/no-op, because the app must remain usable even when keystore or storage fails.

**Key files and packages**
- `lib/data/repositories/care_repository.dart` — defines `AccessDenied` and all `_require*` guard methods (`_require`, `_requireHouseholdScope`, `_requirePersonScope`) that enforce permissions before any DAO call. Every public method delegates through these guards.
- `lib/app/providers.dart` — Riverpod providers that throw `AccessDenied` early when the current user lacks a permission (e.g., `dayPlanProvider`, `householdScoreProvider`).
- `lib/presentation/shared/ui.dart` — `AccessDeniedView` and `ErrorView` widgets that present permission denials and generic async errors to users with human-readable messages.
- `lib/presentation/assessment/assessment_screen.dart` and other screens — catch `AccessDenied` in `.when(error: ...)` branches and display `e is AccessDenied ? e.message : e`.
- `lib/core/auth/session.dart` — shows the graceful-degradation pattern: secure-storage reads/writes/deletes are wrapped in `try/catch (_) {}` returning null or no-op.
- `lib/data/local/app_database.dart` — database opening rethrows errors after completing the in-flight completer; table names are constants to avoid runtime SQL typos.

**Architecture and conventions**
- **Single source of truth for access control**: Widgets never call DAOs directly; all data flows through `CareRepository`, which centralizes permission checks. The file header explains this design: hidden buttons are not access control, and enforcement belongs at the data boundary once.
- **Denials are audited**: Before throwing `AccessDenied`, `_require*` methods call `AuditDao.denied(...)` with action, actor, permission, entity table, and id, so every denial is recorded.
- **Scope checks are separate from role checks**: `_require` validates a `Permission`; `_requireHouseholdScope` and `_requirePersonScope` additionally verify that a caregiver can only access their linked household/person.
- **User-facing messages are explicit**: `AccessDenied.message` defaults to `"Your role does not allow you to $action on this device."` and can be overridden with a `detail` string (used for caregiver-scoped violations and minimum-length reason validation).
- **Presentation distinguishes permission vs. technical errors**: Screens check `e is AccessDenied` to show the friendly message; otherwise they fall back to `$error` via `ErrorView`.
- **I/O failures degrade silently**: Secure storage and DB operations wrap throws in `catch (_) {}` and return safe defaults rather than bubbling up, keeping the app functional on broken devices.

**Conventions and constraints**
- Permission failures must be propagated as `AccessDenied` exceptions, never returned as null or handled silently inside the repository.
- Every repository method that touches another user's data must pass through `_require` or `_require*` guards before calling a DAO.
- UI code must render `AccessDeniedView` for permission errors and `ErrorView` for other async errors; there is no ad-hoc error text in screens.
- Secure storage calls must be wrapped in `try/catch (_) {}` and treat failures as "not remembered", never crashing the app.