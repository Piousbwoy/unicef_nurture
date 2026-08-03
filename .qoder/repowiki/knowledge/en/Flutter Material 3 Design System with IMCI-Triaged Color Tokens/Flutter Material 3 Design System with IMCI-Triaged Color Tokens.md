---
kind: frontend_style
name: Flutter Material 3 Design System with IMCI-Triaged Color Tokens
category: frontend_style
scope:
    - '**'
source_files:
    - lib/core/theme/app_theme.dart
    - lib/main.dart
    - lib/core/router/app_router.dart
    - pubspec.yaml
---

The CareBridge AI Flutter app uses a centralized, token-driven styling system built on Flutter's Material 3 framework. All visual consistency flows from a single theme definition that is applied at the root `MaterialApp` level.

**System and approach**
- Theme source of truth: `lib/core/theme/app_theme.dart` defines three cohesive layers — `AppColors` (semantic color tokens), `Gap` (spacing/radius/tap-target scale), and `AppTheme.light` (a `ThemeData` factory).
- The app entry point (`lib/main.dart`) instantiates `MaterialApp.router` with `theme: AppTheme.light`, so every screen inherits the same palette, typography, and component styles automatically.
- No CSS/SCSS/Tailwind is used; styling is purely Dart-based via Flutter widgets and `Theme.of(context)` / direct token imports.

**Design tokens and conventions**
- Colors are organized by purpose rather than hue: brand (`primary`, `primaryDark`, `primaryLight`, `accent`), WHO IMCI triage bands (`triageRed`, `triageAmber`, `triageGreen` plus their background variants), neutrals (`ink`, `inkMuted`, `inkFaint`, `line`, `surface`, `canvas`), and semantic states (`offline`, `info`). Comments explicitly forbid re-purposing triage colors for decoration.
- Spacing follows a fixed scale (`xs=4, sm=8, md=12, lg=16, xl=24, xxl=32`) with an enforced minimum tap target of 56dp (above Material's 48dp floor) to accommodate one-handed use while holding an infant.
- Typography uses a slightly enlarged default (`fontSizeFactor: 1.02`) for field legibility in bright sunlight; button text is consistently `fontSize: 16, fontWeight: w700`.
- Component themes are fully specified: `AppBarTheme` (flat, no elevation), `CardThemeData` (zero elevation, bordered, rounded corners), `FilledButtonThemeData` / `OutlinedButtonThemeData` (shared radius and minimum height), `InputDecorationTheme` (filled inputs with consistent border/focus states), `ChipThemeData`, `DividerThemeData`, `ListTileThemeData`, and `BottomNavigationBarThemeData`.

**Architecture and conventions**
- Presentation screens import `core/theme/app_theme.dart` directly and consume `AppColors.*` and `Gap.*` constants rather than hardcoding values or calling `Theme.of`. This pattern is visible across assessment, auth, and router files.
- Dark mode is not implemented; only `AppTheme.light` exists, which is appropriate for the offline-first, daylight-field-use context described in the comments.
- The `uses-material-design: true` flag in `pubspec.yaml` enables Material icons; Google Fonts is listed as a dependency but the current theme relies on the default Material font family.

**Constraints enforced by code**
- Triage colors must not be reused for decorative purposes (documented in the `AppColors` class comment).
- Minimum interactive height is 56dp, enforced through `Gap.tapTarget` on all button themes.
- Border radii are centralized through `Gap.radius` (cards) and `Gap.radiusSm` (buttons, inputs, chips) — ad-hoc radius values are not introduced elsewhere.

**Key files**
- `lib/core/theme/app_theme.dart` — complete design token and theme definition
- `lib/main.dart` — root `MaterialApp` applying the theme
- `lib/core/router/app_router.dart` — route-level UI elements (e.g., redirect page) that consume the theme tokens
- `pubspec.yaml` — declares `flutter`, `cupertino_icons`, `google_fonts`, and `uses-material-design: true`
- `analysis_options.yaml` — applies `flutter_lints/flutter.yaml` for consistent code style (no custom style lints beyond the defaults)