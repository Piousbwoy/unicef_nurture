---
kind: logging_system
name: No Application Logging System — Audit-Only Persistence
category: logging_system
scope:
    - '**'
source_files:
    - lib/data/local/app_database.dart
    - lib/data/local/user_dao.dart
---

This repository does not implement a general-purpose application logging system. There is no logging framework, no logger singleton, and no structured log output anywhere in the Dart codebase. A grep across all `.dart` files finds zero imports of `log`, `logging`, or any third-party logger package, and no calls to `print`, `debugPrint`, or `log(`.

The only logging-like behavior present is an **audit log persisted to SQLite**, implemented as a dedicated DAO (`AuditDao`) that writes records into an `auditLog` table defined in `app_database.dart`. The audit schema captures actor identity, role, action, entity context, outcome, free-form detail, and an ISO-8601 timestamp. The DAO provides a `record` method and a convenience `denied` helper for RBAC denials, plus `recent` and `denials` queries for inspection.

A deliberate design constraint is enforced: audit writes must never throw or block care delivery. The `AuditDao.record` implementation wraps the database insert in a try/catch that swallows all exceptions, ensuring that a failed audit write cannot prevent a clinical assessment from saving. This makes the audit log best-effort rather than critical-path.

In summary, the repo has no runtime application logging (no console output, no file sinks, no log levels, no structured fields beyond the audit table). The sole persistence-based logging is the offline-first audit trail used for compliance and governance.