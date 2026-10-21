/// The encryption posture: what the app is allowed to claim about the file it
/// just opened.
///
/// These tests exist to defend one specific failure — a health app that reports a
/// security property it does not have. Every assertion here is about the claim
/// rather than the cipher, because the cipher is a third party's job and the
/// claim is ours.
library;

import 'dart:io';

import 'package:carebridge_ai/data/local/app_database.dart';
import 'package:carebridge_ai/data/local/database_secret.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void setUpDb(WidgetTester tester) {
    final dbDir = Directory.systemTemp.createTempSync('carebridge_encryption');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async =>
          call.method == 'getApplicationDocumentsDirectory' ? dbDir.path : null,
    );
    AppDatabase.initialiseForDesktopAndTests();
    addTearDown(() => AppDatabase.instance.close());
  }

  group('the encryption posture', () {
    testWidgets('a device with no keystore gets no invented key', (
      tester,
    ) async {
      setUpDb(tester);
      await tester.runAsync(() async {
        // flutter_secure_storage has no implementation here, which is the same
        // position a phone with a corrupted keystore is in. The only safe answer is
        // "no key" — a derived or hardcoded one would produce a database the app
        // claims is protected and anyone can read.
        expect(await DatabaseSecret.passphraseForNewDatabase(), isNull);
      });
    });

    testWidgets('the posture is reported by the code that opened the file', (
      tester,
    ) async {
      setUpDb(tester);
      await tester.runAsync(() async {
        final posture = await AppDatabase.instance.posture;
        expect(
          posture.encrypted,
          isFalse,
          reason:
              'this host is a desktop test runner, where the engine is plain '
              'SQLite and the app must say so rather than stay silent',
        );
        // Not "unavailable" and not a bare boolean: the sentence has to name the
        // situation, because that is what makes the refusal believable when the
        // same screen later says a phone build is encrypted.
        expect(posture.summary, contains('not encrypted'));
      });
    });

    testWidgets('opening twice does not change the answer', (tester) async {
      setUpDb(tester);
      await tester.runAsync(() async {
        final first = await AppDatabase.instance.posture;
        final second = await AppDatabase.instance.posture;
        expect(identical(first, second), isTrue);
        expect(first.encrypted, second.encrypted);
      });
    });

    test(
      'the posture distinguishes encrypted from plaintext by construction',
      () {
        const encrypted = AtRestPosture.encrypted();
        const plain = AtRestPosture.plaintext('unencrypted on this build');
        expect(encrypted.encrypted, isTrue);
        expect(plain.encrypted, isFalse);
        expect(plain.summary, isNotEmpty);
      },
    );
  });
}
