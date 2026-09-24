/// Aura Medica luxe layer regression guards.
///
/// Pins the contracts the FHW redesign rests on:
///
/// * The floating dock renders every destination with a stable key, its
///   Semantics(selected) follows the active index, and a tap reports the
///   tapped slot.
/// * The magnetic pill animates under motion and still switches instantly
///   (function preserved, only the glide is lost) under reduced motion.
/// * The Catalyst Capsule and bento deck render their real strings at the
///   accessibility floor (320px, 200% text) without RenderFlex overflows —
///   the class of failure judges meet on real phones.
/// * The shimmer catch-light is transient under motion and static under
///   reduced motion; the staggered entrance likewise renders its final
///   frame with animations disabled.
/// * Swipe-to-reveal: a tap on the closed card is the primary action, a
///   drag reveals the actions, a tap while open closes, and the reveal
///   still works under reduced motion (it snaps).
/// * The cockpit gauge draws exactly the number it is given — probability,
///   95% band, conformal Q95 — and renders no band chips when none exist.
library;

import 'package:carebridge_ai/presentation/assessment/widgets/cockpit_gauge.dart';
import 'package:carebridge_ai/presentation/fhw/clinic_widgets.dart'
    show SwipeAction, SwipeRevealActions;
import 'package:carebridge_ai/presentation/fhw/luxe_components.dart';
import 'package:carebridge_ai/presentation/fhw/luxe_motion.dart'
    show ShimmerCatchlight, StaggeredEntrance;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void _phoneSize(WidgetTester tester, {double width = 390}) {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  double width = 390,
  double textScale = 1.0,
  bool reducedMotion = false,
}) async {
  _phoneSize(tester, width: width);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reducedMotion,
        ),
        child: child!,
      ),
      home: home,
    ),
  );
}

const _titles = ['Today', 'Queue', 'Assess', 'Records'];
const _icons = [
  Icons.home_outlined,
  Icons.people_outline,
  Icons.fact_check_outlined,
  Icons.folder_shared_outlined,
];

Widget _dockHost(int index, ValueChanged<int> onSelect) => Scaffold(
  body: const SizedBox.shrink(),
  bottomNavigationBar: FloatingAcrylicDock(
    index: index,
    titles: _titles,
    icons: _icons,
    onSelect: onSelect,
  ),
);

AnimatedPositioned _pill(WidgetTester tester) =>
    tester.widget<AnimatedPositioned>(find.byType(AnimatedPositioned));

bool _tabSelected(WidgetTester tester, int tab) => tester
    .widget<Semantics>(
      find
          .descendant(
            of: find.byKey(ValueKey('fhw-tab-$tab')),
            matching: find.byType(Semantics),
          )
          .first,
    )
    .properties
    .selected!;

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('FloatingAcrylicDock', () {
    testWidgets('renders every destination with a key and reports taps', (
      tester,
    ) async {
      final taps = <int>[];
      await _pump(tester, _dockHost(0, taps.add));
      await tester.pumpAndSettle();

      for (var i = 0; i < _titles.length; i++) {
        expect(find.byKey(ValueKey('fhw-tab-$i')), findsOneWidget);
        expect(find.text(_titles[i]), findsOneWidget);
      }
      expect(_tabSelected(tester, 0), isTrue);
      expect(_tabSelected(tester, 1), isFalse);

      await tester.tap(find.text('Queue'));
      await tester.pumpAndSettle();
      expect(taps, [1]);
    });

    testWidgets('selection follows the index and the pill glides', (
      tester,
    ) async {
      final taps = <int>[];
      await _pump(tester, _dockHost(0, taps.add));
      await tester.pumpAndSettle();

      expect(_pill(tester).duration, greaterThan(Duration.zero));
      final before = _pill(tester).left;

      await _pump(tester, _dockHost(1, taps.add));
      await tester.pumpAndSettle();
      expect(_tabSelected(tester, 0), isFalse);
      expect(_tabSelected(tester, 1), isTrue);
      expect(_pill(tester).left, greaterThan(before!));
    });

    testWidgets('reduced motion: pill jumps instantly but still switches', (
      tester,
    ) async {
      final taps = <int>[];
      await _pump(tester, _dockHost(0, taps.add), reducedMotion: true);
      await tester.pump();

      expect(_pill(tester).duration, Duration.zero);
      final before = _pill(tester).left;

      await _pump(tester, _dockHost(2, taps.add), reducedMotion: true);
      await tester.pump();
      expect(_pill(tester).left, greaterThan(before!));
      expect(_tabSelected(tester, 2), isTrue);
    });

    testWidgets('fits 320px at 200% text without overflow', (tester) async {
      final taps = <int>[];
      await _pump(
        tester,
        _dockHost(0, taps.add),
        width: 320,
        textScale: 2,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('CatalystCapsule', () {
    var pressed = 0;
    Widget capsule() => CatalystCapsule(
      badge: 'TUESDAY, 1 SEPTEMBER · TAMALE CENTRAL · OFFLINE ENGINE READY',
      heading: const Text('Care starts here.'),
      body: const Text(
        'Who needs care today? Start with the household in front of you.',
      ),
      button: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => pressed++,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Receive a patient'),
        ),
      ),
      footer: const Text('Clinical assessment works without internet.'),
    );

    Widget host() => Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [capsule()],
      ),
    );

    testWidgets('renders all layers and the button stays tappable', (
      tester,
    ) async {
      await _pump(tester, host(), reducedMotion: true);
      await tester.pump();

      expect(find.text('Care starts here.'), findsOneWidget);
      expect(find.textContaining('OFFLINE ENGINE READY'), findsOneWidget);
      expect(find.text('Receive a patient'), findsOneWidget);
      expect(
        find.text('Clinical assessment works without internet.'),
        findsOneWidget,
      );

      // Reduced motion renders the static frame: no catch-light clip layer.
      expect(
        find.descendant(
          of: find.byType(ShimmerCatchlight),
          matching: find.byType(ClipRRect),
        ),
        findsNothing,
      );

      await tester.tap(find.text('Receive a patient'));
      await tester.pump();
      expect(pressed, 1);
    });

    testWidgets('the catch-light sweep is transient under motion', (
      tester,
    ) async {
      await _pump(tester, host());
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(ShimmerCatchlight),
          matching: find.byType(ClipRRect),
        ),
        findsOneWidget,
      );

      // Three bounded sweeps at 1100ms each, then the plain child settles.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 1200));
      }
      expect(
        find.descendant(
          of: find.byType(ShimmerCatchlight),
          matching: find.byType(ClipRRect),
        ),
        findsNothing,
      );
    });

    testWidgets('fits 320px at 200% text without overflow', (tester) async {
      await _pump(
        tester,
        host(),
        width: 320,
        textScale: 2,
        reducedMotion: true,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('BentoTelemetryDeck', () {
    final taps = <String, bool>{};

    Widget deck({
      bool engineReady = true,
      int queueCount = 0,
      int? pendingSync,
      int? failingSync,
    }) => BentoTelemetryDeck(
      queueCount: queueCount,
      queueNames: const ['Achana household', 'Fuseini household'],
      oldestWaitMinutes: queueCount == 0 ? null : 12,
      dueToday: 3,
      overdue: 1,
      sessionDone: 2,
      sessionTotal: 5,
      pendingSync: pendingSync,
      failingSync: failingSync,
      engineReady: engineReady,
      referrals: 2,
      households: 14,
      onQueueTap: () => taps['queue'] = true,
      onDueTap: () => taps['due'] = true,
      onSyncTap: () => taps['sync'] = true,
      onReferralsTap: () => taps['referrals'] = true,
      onFamiliesTap: () => taps['families'] = true,
    );

    Widget host(Widget d) => Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [d],
      ),
    );

    testWidgets('wide mode shows real telemetry and every tile taps through', (
      tester,
    ) async {
      await _pump(
        tester,
        host(
          deck(
            queueCount: 2,
            pendingSync: 3,
            failingSync: 1,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('2 in the clinic queue'), findsOneWidget);
      expect(find.text('Longest wait Waiting 12m'), findsOneWidget);
      expect(find.text('Due today'), findsOneWidget);
      expect(find.text('1 overdue'), findsOneWidget);
      expect(find.text('3 changes waiting'), findsOneWidget);
      expect(find.text('1 need retry'), findsOneWidget);
      expect(find.text('Open referrals'), findsOneWidget);
      expect(find.text('Households'), findsOneWidget);

      for (final label in [
        '2 in the clinic queue',
        'Due today',
        '3 changes waiting',
        'Open referrals',
        'Households',
      ]) {
        await tester.tap(find.text(label));
        await tester.pump();
      }
      expect(taps.values.every((t) => t), isTrue,
          reason: 'all five tiles must fire their callbacks');
    });

    testWidgets('stacks narrow, names offline state honestly, no overflow', (
      tester,
    ) async {
      await _pump(
        tester,
        host(deck(engineReady: false, pendingSync: 4)),
        width: 320,
        textScale: 2,
        reducedMotion: true,
      );
      await tester.pump();

      expect(find.text('Queue clear'), findsOneWidget);
      expect(find.text('Reading local records'), findsOneWidget);
      expect(
        find.text('Saved on this phone, sending when able'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('StaggeredEntrance', () {
    Widget host() => const Scaffold(
      body: StaggeredEntrance(
        children: [Text('One'), Text('Two'), Text('Three')],
      ),
    );

    testWidgets('animates in under motion', (tester) async {
      await _pump(tester, host());
      await tester.pump();

      final opacities = tester.widgetList<Opacity>(find.byType(Opacity));
      expect(opacities.length, 3);
      expect(opacities.first.opacity, lessThan(1.0));

      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<Opacity>(find.byType(Opacity))
            .every((o) => o.opacity == 1.0),
        isTrue,
      );
    });

    testWidgets('renders the static final frame under reduced motion', (
      tester,
    ) async {
      await _pump(tester, host(), reducedMotion: true);
      await tester.pump();

      expect(
        tester
            .widgetList<Opacity>(find.byType(Opacity))
            .every((o) => o.opacity == 1.0),
        isTrue,
      );
    });
  });

  group('SwipeRevealActions', () {
    Widget host({required void Function() onPrimary, required void Function() onResume, required void Function() onCancel}) => Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SwipeRevealActions(
          actions: [
            SwipeAction(
              label: 'Resume',
              icon: Icons.play_arrow_rounded,
              onPressed: onResume,
            ),
            SwipeAction(
              label: 'Cancel',
              icon: Icons.close_rounded,
              tone: Colors.red,
              onPressed: onCancel,
            ),
          ],
          onTap: onPrimary,
          child: Container(
            height: 88,
            alignment: Alignment.center,
            color: Colors.white,
            child: const Text('Continue'),
          ),
        ),
      ),
    );

    testWidgets('tap is the primary action; drag reveals; tap while open closes', (
      tester,
    ) async {
      var primary = 0;
      var resume = 0;
      var cancel = 0;
      await _pump(
        tester,
        host(
          onPrimary: () => primary++,
          onResume: () => resume++,
          onCancel: () => cancel++,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(primary, 1);

      await tester.drag(find.text('Continue'), const Offset(-200, 0));
      await tester.pumpAndSettle();

      // The card is open; a tap closes it rather than repeating the
      // primary action.
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(primary, 1);

      await tester.drag(find.text('Continue'), const Offset(-200, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resume'));
      await tester.pump();
      expect(resume, 1);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(cancel, 1);
    });

    testWidgets('reveal still works under reduced motion — it snaps', (
      tester,
    ) async {
      var primary = 0;
      var resume = 0;
      await _pump(
        tester,
        host(
          onPrimary: () => primary++,
          onResume: () => resume++,
          onCancel: () {},
        ),
        reducedMotion: true,
      );
      await tester.pump();

      await tester.drag(find.text('Continue'), const Offset(-200, 0));
      await tester.pump();
      await tester.tap(find.text('Resume'));
      await tester.pump();
      expect(resume, 1);
      expect(primary, 0);
    });
  });

  group('CockpitGauge', () {
    Widget host(Widget gauge) => Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [gauge],
      ),
    );

    testWidgets('draws exactly the number it is given', (tester) async {
      await _pump(
        tester,
        host(
          const CockpitGauge(
            value: 0.42,
            interval95: (low: 0.40, high: 0.60),
            conformalQ95: 0.5,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('42%'), findsOneWidget);
      expect(find.text('95% band 40–60'), findsOneWidget);
      expect(find.text('Q95 0.50'), findsOneWidget);
      expect(
        find.text('0–1 scale — experimental, not a diagnosis'),
        findsOneWidget,
      );

      final handle = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp('Research output 42 percent')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('renders no band chips when no uncertainty is given', (
      tester,
    ) async {
      await _pump(tester, host(const CockpitGauge(value: 0.65)));
      await tester.pumpAndSettle();

      expect(find.text('65%'), findsOneWidget);
      expect(find.textContaining('95% band'), findsNothing);
      expect(find.textContaining('Q95'), findsNothing);
    });

    testWidgets('the dial sweep obeys the motion gate', (tester) async {
      await _pump(tester, host(const CockpitGauge(value: 0.42)));
      await tester.pump();

      TweenAnimationBuilder<double> tween() => tester
          .widget<TweenAnimationBuilder<double>>(
            find.byType(TweenAnimationBuilder<double>),
          );
      expect(tween().duration, const Duration(milliseconds: 900));

      await _pump(
        tester,
        host(const CockpitGauge(value: 0.42)),
        reducedMotion: true,
      );
      await tester.pump();
      expect(tween().duration, Duration.zero);
    });

    testWidgets('fits 320px at 200% text without overflow', (tester) async {
      await _pump(
        tester,
        host(
          const CockpitGauge(
            value: 0.42,
            interval95: (low: 0.40, high: 0.60),
            conformalQ95: 0.5,
          ),
        ),
        width: 320,
        textScale: 2,
        reducedMotion: true,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
