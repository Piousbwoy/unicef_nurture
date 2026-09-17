/// Glass layer guardrails.
///
/// The frosted look is a GPU budget, not a decoration: a `BackdropFilter`
/// must exist in Full mode, and must disappear entirely under the user's
/// Lite choice or the platform's reduced-motion setting. The floating nav
/// bar must keep every label visible and every item at a 48px tap target.
library;

import 'package:carebridge_ai/core/theme/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(Widget child, {bool disableAnimations = false}) => MaterialApp(
  builder: (context, page) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
    child: page!,
  ),
  home: Scaffold(body: Center(child: child)),
);

const _labels = ['Today', 'Visits', 'Assess', 'Referrals', 'Profile'];

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('full mode renders a BackdropFilter for a blurred surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const GlassSurface(tier: GlassTier.hero, child: Text('hero'))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(RepaintBoundary), findsWidgets);
    expect(find.text('hero'), findsOneWidget);
  });

  testWidgets('list cards opt out of the filter with blur: false', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const GlassSurface(blur: false, child: Text('card'))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('card'), findsOneWidget);
  });

  testWidgets('reduced motion removes every BackdropFilter', (tester) async {
    await tester.pumpWidget(
      _app(
        const Column(
          children: [
            GlassSurface(tier: GlassTier.hero, child: Text('hero')),
            GlassAppBar(title: Text('bar')),
            GlassActionBar(child: Text('action')),
          ],
        ),
        disableAnimations: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('hero'), findsOneWidget);
    expect(find.text('bar'), findsOneWidget);
    expect(find.text('action'), findsOneWidget);
  });

  testWidgets('the persisted Lite choice removes every BackdropFilter', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'reduced_effects': true});
    await tester.pumpWidget(
      ProviderScope(
        child: VisualEffectsScope(
          child: _app(
            const GlassSurface(tier: GlassTier.hero, child: Text('hero')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('hero'), findsOneWidget);
  });

  testWidgets('VisualEffects.of scales every duration to zero when off', (
    tester,
  ) async {
    late VisualEffects fx;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) {
            fx = VisualEffects.of(context);
            return const SizedBox.shrink();
          },
        ),
        disableAnimations: true,
      ),
    );
    expect(fx.motion, isFalse);
    expect(fx.blur, isFalse);
    expect(fx.scale(const Duration(milliseconds: 300)), Duration.zero);
  });

  testWidgets(
    'GlassNavBar keeps every label visible at 48px on a 320px phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var tapped = -1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: GlassNavBar(
              currentIndex: 0,
              onTap: (i) => tapped = i,
              items: [
                for (final l in _labels)
                  GlassNavItem(icon: Icons.circle_outlined, label: l),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      for (final label in _labels) {
        expect(find.text(label), findsOneWidget);
        final item = tester.getSize(
          find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
        );
        expect(item.height, greaterThanOrEqualTo(48), reason: label);
        expect(item.width, greaterThanOrEqualTo(48), reason: label);
      }

      await tester.tap(find.text('Referrals'));
      expect(tapped, 3);
    },
  );
}
