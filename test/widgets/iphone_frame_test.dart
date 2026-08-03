import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/core/auth/session.dart';
import 'package:carebridge_ai/core/router/app_router.dart';
import 'package:carebridge_ai/core/theme/app_theme.dart';
import 'package:carebridge_ai/presentation/auth/sign_in_screen.dart';
import 'package:carebridge_ai/presentation/shared/iphone_frame.dart';
import 'package:flutter/gestures.dart';
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

  testWidgets(
    'IPhoneFrame: caregiver registration step 0 -> step 1 stays rendered '
    'and hit-tests cleanly under a mouse pointer (web regression)',
    (tester) async {
      SharedPreferences.setMockInitialValues({'onboarding_seen': true});
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith(() => _FixedSession(const SessionNeedsSetup())),
          ],
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

      // On the web the pointer is a mouse; use a mouse gesture for the
      // whole walk so hit-testing matches the real runtime.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.moveTo(const Offset(640, 400));
      await tester.pump();

      await tester.ensureVisible(find.text('Caregiver').first);
      await tester.pump();
      await tester.tap(find.text('Caregiver').first);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(SignInScreen), findsOneWidget);

      await tester.ensureVisible(find.text('Create a new account'));
      await tester.tap(find.text('Create a new account'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Your details'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'e.g. Abdul-Rahman Suleimana'),
        'Amina Iddrisu',
      );
      await tester.enterText(
        find.widgetWithText(TextField, '024 000 0000'),
        '0244 111 222',
      );
      await tester.enterText(find.widgetWithText(TextField, '4 digits'), '5729');
      await tester.enterText(
        find.widgetWithText(TextField, 'Repeat your PIN'),
        '5729',
      );
      // DIAGNOSTIC: what is on screen right before "Continue"?
      debugPrint('GradientButtons: ${find.byType(GradientButton).evaluate().length}');
      for (final t in find.byType(Text).evaluate()) {
        final w = t.widget as Text;
        if ((w.data ?? '').trim().isNotEmpty) debugPrint('TEXT: ${w.data}');
      }
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The family step must render inside the simulated phone screen.
      expect(find.text('Your family'), findsWidgets);
      expect(find.text('FAMILY CODE'), findsOneWidget);

      // Regression: the theme gives every OutlinedButton an infinite minimum
      // width (Size.fromHeight). On web the Check button received unbounded
      // constraints inside its Row and threw "BoxConstraints forces an
      // infinite width", blanking the step. It must now have a finite size.
      final checkButton = find.widgetWithText(OutlinedButton, 'Check');
      expect(checkButton, findsOneWidget);
      expect(tester.getSize(checkButton).width.isFinite, isTrue);

      // Sweep the mouse across the phone screen the way a presenter's
      // cursor would; any size-less render box throws on hit test here.
      for (var i = 0; i <= 10; i++) {
        await mouse.moveTo(Offset(480.0 + i * 32, 200.0 + i * 40));
        await tester.pump();
      }

      expect(tester.takeException(), isNull);
      await mouse.removePointer();
    },
  );
}
