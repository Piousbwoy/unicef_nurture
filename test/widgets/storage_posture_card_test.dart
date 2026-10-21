/// The storage posture card, at the sizes a real handset uses.
///
/// This is the surface where the app states, in one sentence, whether a family's
/// records are encrypted on this phone. It carries a long technical sentence and a
/// long button label inside a card inside a scrolling column — exactly the shape
/// that breaks at 320px with 200% text, and it breaks by cutting off the words
/// "not encrypted", which is the worst possible sentence to truncate.
///
/// So the test is not about pixels. It asserts that every posture — encrypted,
/// plaintext with the action available, plaintext with the action withheld, and
/// still-checking — is readable whole on the accessibility floor.
library;

import 'dart:async';

import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/data/local/database_secret.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/fhw/storage_posture_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _worker = AppUser(
  id: 'u-desk',
  fullName: 'Aminata Fusena',
  phone: '0244000001',
  role: UserRole.frontlineHealthWorker,
  region: 'Northern Region',
  district: 'Savelugu Municipal',
  community: 'Gushegu',
);

const _caregiver = AppUser(
  id: 'u-home',
  fullName: 'Abena Yeboah',
  phone: '0244000003',
  role: UserRole.caregiver,
  region: 'Northern Region',
  district: 'Savelugu Municipal',
  community: 'Gushegu',
);

const _plainSummary =
    'This device stores its records unencrypted: a lost phone is a lost register.';

Future<void> _pump(
  WidgetTester tester, {
  required AppUser? user,
  required AtRestPosture? posture,
  double width = 320,
  double textScale = 2.0,
  bool? actionOverride,
}) async {
  tester.view.physicalSize = Size(width, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      // Overridden rather than computed: the question here is whether the
      // sentence fits, not whether the engine opened the file. The posture
      // itself is pinned by test/encryption_posture_test.dart.
      overrides: [
        if (user != null) currentUserProvider.overrideWithValue(user),
        atRestPostureProvider.overrideWith((ref) {
          if (posture != null) return Future.value(posture);
          // Left unresolved on purpose: no timer and no pending frame, so the
          // checking state is the only thing the widget has to show.
          return Completer<AtRestPosture>().future;
        }),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: StoragePostureCard(actionOverride: actionOverride),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (posture != null) await tester.pumpAndSettle();
  // A single extra frame so the loading placeholder is definitely painted before
  // the never-resolving case is asserted.
  await tester.pump();
}

void main() {
  group('the storage card at 320px and 200% text', () {
    testWidgets('an encrypted register is readable whole', (tester) async {
      await _pump(
        tester,
        user: _worker,
        posture: const AtRestPosture.encrypted(),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Storage & encryption'), findsOneWidget);
      expect(find.textContaining('Encrypted at rest'), findsOneWidget);
      expect(
        find.textContaining('Nothing further is needed here'),
        findsOneWidget,
      );
      // Nothing to do, so nothing offered.
      expect(find.textContaining('Encrypt the register'), findsNothing);
    });

    testWidgets('a plaintext register says so and offers the act', (
      tester,
    ) async {
      // The action is forced visible because this test host is a desktop build,
      // where the platform genuinely refuses the conversion. What is pinned here
      // is whether the longest string in the card fits — not whether Windows can
      // encrypt.
      await _pump(
        tester,
        user: _worker,
        posture: const AtRestPosture.plaintext(_plainSummary),
        actionOverride: true,
      );

      expect(tester.takeException(), isNull);
      // The failure must be legible in full. A card that ellipsizes here is the
      // one way this screen can lie by omission.
      expect(find.text(_plainSummary), findsOneWidget);
      expect(find.text('Encrypt the register on this device'), findsOneWidget);
      expect(find.byIcon(Icons.lock_open_rounded), findsOneWidget);
    });

    testWidgets('a family account sees the same sentence, with no lever', (
      tester,
    ) async {
      // Layout of the withheld state. Whether withholding is the *right* call for
      // this account is decided by [StoragePostureCard.offersAction], which is
      // tested as a rule below rather than guessed at through a widget.
      await _pump(
        tester,
        user: _caregiver,
        posture: const AtRestPosture.plaintext(_plainSummary),
        actionOverride: false,
      );

      expect(tester.takeException(), isNull);
      expect(find.text(_plainSummary), findsOneWidget);
      expect(
        find.text('Encrypt the register on this device'),
        findsNothing,
        reason:
            'A caregiver handset must not run a migration over the register a '
            'district is accountable for.',
      );
    });

    testWidgets('no account at all still says what it is doing', (
      tester,
    ) async {
      await _pump(
        tester,
        user: null,
        posture: const AtRestPosture.plaintext(_plainSummary),
      );

      expect(tester.takeException(), isNull);
      expect(find.text(_plainSummary), findsOneWidget);
      expect(find.text('Encrypt the register on this device'), findsNothing);
    });

    testWidgets('the checking state does not flash a false claim', (
      tester,
    ) async {
      // Posture unresolved: the sentence must be the honest placeholder, and no
      // lock icon may be drawn as though a verdict existed.
      await _pump(tester, user: _worker, posture: null);

      expect(tester.takeException(), isNull);
      expect(
        find.text('Checking how this device stores its records…'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.hourglass_empty_rounded), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsNothing);
      expect(find.byIcon(Icons.lock_open_rounded), findsNothing);
    });

    testWidgets('the smallest body size on the same layout also fits', (
      tester,
    ) async {
      await _pump(
        tester,
        user: _worker,
        posture: const AtRestPosture.plaintext(_plainSummary),
        width: 320,
        textScale: 1.0,
        actionOverride: true,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Encrypt the register on this device'), findsOneWidget);
    });

    testWidgets('the real platform rule is not bypassed by the seam', (
      tester,
    ) async {
      // No override, on a desktop test host: a worker with a plaintext register is
      // told the state and offered nothing, because this build cannot convert.
      await _pump(
        tester,
        user: _worker,
        posture: const AtRestPosture.plaintext(_plainSummary),
      );
      expect(tester.takeException(), isNull);
      expect(find.text(_plainSummary), findsOneWidget);
      expect(find.text('Encrypt the register on this device'), findsNothing);
    });
  });

  group('the rule that decides whether the action appears', () {
    final plain = const AtRestPosture.plaintext(_plainSummary);
    final encrypted = const AtRestPosture.encrypted();

    bool offers({
      required AtRestPosture? posture,
      required AppUser? user,
      bool mobile = true,
    }) => StoragePostureCard.offersAction(
      posture: posture,
      user: user,
      buildCanConvert: mobile,
    );

    test('a worker on a phone that can convert is offered the act', () {
      expect(offers(posture: plain, user: _worker), isTrue);
    });

    test('nothing is offered when the register is already encrypted', () {
      expect(offers(posture: encrypted, user: _worker), isFalse);
    });

    test('nothing is offered before there is a verdict', () {
      expect(offers(posture: null, user: _worker), isFalse);
    });

    test('a family handset is not handed the migration', () {
      // The register on a caregiver account is part of a district's record, and a
      // storage migration over it is not a family's decision to make.
      expect(offers(posture: plain, user: _caregiver), isFalse);
      expect(offers(posture: plain, user: null), isFalse);
    });

    test(
      'a build without the SQLCipher engine offers nothing it cannot do',
      () {
        expect(offers(posture: plain, user: _worker, mobile: false), isFalse);
      },
    );
  });
}
