---
kind: dependency_management
name: Flutter Pub Dependency Management
category: dependency_management
scope:
    - '**'
source_files:
    - pubspec.yaml
    - pubspec.lock
    - analysis_options.yaml
---

This repository uses the standard Flutter/Dart dependency management system via `pub`, with a single top-level `pubspec.yaml` manifest and a committed `pubspec.lock` lockfile. There is no monorepo tooling (e.g., melos, fvm workspaces); Android and iOS native shells are managed through their own Gradle and Xcode configurations respectively, but Dart dependencies are centralized in one place.

**System and tools**
- Package manager: `pub` (Dart/Flutter SDK).
- Registry: public `https://pub.dev` hosted registry; no private registries or custom repositories are configured.
- Lockfile: `pubspec.lock` is committed to version control, pinning every transitive dependency by name, version, sha256, and source URL.
- Version constraints: direct dependencies use caret (`^`) semantic-version ranges in `pubspec.yaml`; the SDK constraint is `^3.10.0`.
- Publishing: `publish_to: 'none'` disables publishing this package to pub.dev.

**Key files**
- `pubspec.yaml` — declares all direct dependencies under `dependencies:` and `dev_dependencies:`, plus the `environment.sdk` constraint and Flutter asset declarations.
- `pubspec.lock` — generated lockfile that pins exact versions of all direct and transitive packages resolved from pub.dev.
- `analysis_options.yaml` — enforces lint rules via `flutter_lints` (a dev dependency), indirectly constraining dependency usage through static analysis.

**Architecture and conventions**
- Single-package layout: all Dart code lives under `lib/` with one `pubspec.yaml` at the repo root; there are no sub-packages or workspace configuration.
- Dependencies are grouped by concern in comments within `pubspec.yaml` (state management, routing, offline-first storage, secure storage, device/connectivity, UI, audio, QR, utilities) making it easy to audit what each area pulls in.
- Dev-only tooling (`flutter_test`, `flutter_lints`, `test`) is separated into `dev_dependencies`, keeping runtime dependencies minimal.
- No vendoring strategy (no `packages/` directory or `dependency_overrides` for local paths); all third-party code is fetched from pub.dev at resolve time.

**Constraints and observed rules**
- The SDK is constrained to `^3.10.0`, so any Dart SDK outside that range will be rejected by `pub get`.
- All dependencies must be resolvable from the public `pub.dev` registry; no `pubspec_overrides.yaml` or custom `pubspec.yaml` `dependency_overrides` entries are present.
- The lockfile is tracked in version control, meaning dependency resolution is reproducible across environments without re-resolving from the network on every build.