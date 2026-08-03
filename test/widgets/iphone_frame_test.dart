import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/core/auth/session.dart';
import 'package:carebridge_ai/core/router/app_router.dart';
import 'package:carebridge_ai/presentation/shared/iphone_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FixedSession extends SessionNotifier {
  _FixedSession(this.initial);
  final SessionState initial;
  @override
  SessionState build() => initial;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('IPhoneFrame wrapping MaterialApp.router (web simulation) throws NO errors', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1280, 800));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionProvider.overrideWith(() => _FixedSession(const SessionNeedsSetup()))],
        child: Consumer(
          builder: (context, ref, _) {
            final router = ref.watch(routerProvider);
            return MaterialApp.router(
              title: 'CareBridge AI',
              routerConfig: router,
              builder: (context, child) => IPhoneFrame(child: child!),
            );
          },
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
