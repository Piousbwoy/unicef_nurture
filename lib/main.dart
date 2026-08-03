/// CareBridge AI — offline-first, AI-assisted community health companion for
/// frontline health workers and caregivers in Northern Ghana.
///
/// The entry point does three things and nothing else: opens the Riverpod
/// scope, hands routing to [routerProvider] (which owns the session-driven
/// redirect), and applies the theme. Everything else — the database and the
/// sync service — is pulled in lazily by the providers themselves.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/local/app_database.dart';
import 'presentation/shared/iphone_frame.dart';

void main() {
  // Pick the right database factory before any provider tries to open a
  // database — web gets the WASM factory, desktop gets FFI, mobile uses the
  // native sqflite plugin.
  AppDatabase.initialiseForPlatform();
  runApp(const ProviderScope(child: CareBridgeApp()));
}

class CareBridgeApp extends ConsumerWidget {
  const CareBridgeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'CareBridge AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
      builder: (context, child) {
        if (kIsWeb) return IPhoneFrame(child: child!);
        return child!;
      },
    );
  }
}
