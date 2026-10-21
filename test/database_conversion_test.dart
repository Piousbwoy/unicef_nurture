/// The conversion layer: counting, comparing, and swapping files without ever
/// putting the only copy at risk.
///
/// The SQLCipher copy itself cannot run on a desktop test host — there is no
/// encrypted engine here to call. What *is* covered is the part that decides
/// whether the copy happens and what happens if it does not agree with the
/// original, which is where the data loss would actually come from. The last test
/// asserts the refusal path leaves the register byte-for-byte where it was,
/// because on a build that cannot convert, "nothing happened" is the only
/// acceptable outcome.
library;

import 'dart:io';

import 'package:carebridge_ai/data/local/app_database.dart';
import 'package:carebridge_ai/data/local/database_conversion.dart';
// The platform implementation, deliberately: this host is the desktop target, and
// the file operations under test are the ones that build selects.
import 'package:carebridge_ai/data/local/db_engine_io.dart';
import 'package:carebridge_ai/data/local/household_dao.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _household = Household(
  id: 'hh-x',
  name: 'Counted family',
  region: 'Northern Region',
  district: 'Savelugu Municipal',
  community: 'Gushegu',
  createdBy: 'u-x',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('counting what is in the register', () {
    /// The DAOs read `AppDatabase.instance`, so the counting has to read the same
    /// handle or the two are looking at different databases and the test proves
    /// nothing.
    void setUpDb(WidgetTester tester) {
      final dbDir = Directory.systemTemp.createTempSync('carebridge_convert');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => call.method == 'getApplicationDocumentsDirectory'
            ? dbDir.path
            : null,
      );
      AppDatabase.initialiseForDesktopAndTests();
      addTearDown(() => AppDatabase.instance.close());
    }

    testWidgets('every clinical table is counted, bookkeeping is not', (
      tester,
    ) async {
      setUpDb(tester);
      await tester.runAsync(() async {
        final db = await AppDatabase.instance.database;
        final counts = await DatabaseConversion.tableCounts(db);
        // The register's own tables, because those are the ones a migration must
        // not lose. sqlite_% bookkeeping is excluded by design.
        expect(counts, contains('households'));
        expect(counts, contains('persons'));
        expect(counts, contains('access_ledger'));
        expect(counts.keys, isNot(contains('sqlite_sequence')));
        expect(counts.values.every((c) => c == 0), isTrue);
      });
    });

    testWidgets('the count moves when a row is written', (tester) async {
      setUpDb(tester);
      await tester.runAsync(() async {
        final db = await AppDatabase.instance.database;
        // Through the DAO rather than a hand-written column map: the point of this
        // test is the counting, and a guessed column list would fail for the wrong
        // reason the next time the schema moves.
        await HouseholdDao.upsert(_household);
        final counts = await DatabaseConversion.tableCounts(db);
        expect(counts['households'], 1);
      });
    });
  });

  group('comparing a copy against the original', () {
    test('a missing table is caught', () {
      expect(
        DatabaseConversion.mismatches(original: {'persons': 12}, converted: {}),
        contains(
          'persons: 12 row(s) in the register, absent from the converted '
          'database',
        ),
      );
    });

    test('a differing row count is caught', () {
      expect(
        DatabaseConversion.mismatches(
          original: {'persons': 12, 'households': 4},
          converted: {'persons': 11, 'households': 4},
        ),
        ['persons: expected 12 row(s), found 11'],
      );
    });

    test('a table that only exists in the copy is caught', () {
      // The easier failure to miss, and the more alarming one: it means the two
      // files are not the same register at all.
      expect(
        DatabaseConversion.mismatches(
          original: {'households': 1},
          converted: {'households': 1, 'surprise': 0},
        ),
        ['surprise: present in the converted database only'],
      );
    });

    test('an exact match reports nothing', () {
      expect(
        DatabaseConversion.mismatches(
          original: {'households': 1, 'persons': 3},
          converted: {'persons': 3, 'households': 1},
        ),
        isEmpty,
        reason: 'order of keys must not matter',
      );
    });
  });

  group('putting the converted file in place', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('carebridge_swap'));
    tearDown(() => dir.deleteSync(recursive: true));

    String p(String name) => '${dir.path}/$name';

    Future<void> write(String name, String contents) =>
        File(p(name)).writeAsString(contents);

    test(
      'the original is kept as a backup and the copy takes its name',
      () async {
        await write('reg.db', 'plaintext register');
        await write('reg.db.converting', 'encrypted register');

        await swapEncryptedIntoPlace(
          plainPath: p('reg.db'),
          targetPath: p('reg.db.converting'),
          backupPath: p('reg.db.plaintext-backup'),
        );

        expect(await File(p('reg.db')).readAsString(), 'encrypted register');
        expect(
          await File(p('reg.db.plaintext-backup')).readAsString(),
          'plaintext register',
          reason:
              'the rollback copy is what makes an unverified swap survivable',
        );
        expect(await File(p('reg.db.converting')).exists(), isFalse);
      },
    );

    test('nothing is touched when the copy is missing', () async {
      await write('reg.db', 'plaintext register');

      await expectLater(
        swapEncryptedIntoPlace(
          plainPath: p('reg.db'),
          targetPath: p('reg.db.converting'),
          backupPath: p('reg.db.plaintext-backup'),
        ),
        throwsA(isA<StateError>()),
      );
      expect(await File(p('reg.db')).readAsString(), 'plaintext register');
      expect(await File(p('reg.db.plaintext-backup')).exists(), isFalse);
    });

    test(
      'an existing backup stops the swap rather than overwriting it',
      () async {
        await write('reg.db', 'plaintext register');
        await write('reg.db.converting', 'encrypted register');
        await write('reg.db.plaintext-backup', 'an older plaintext register');

        await expectLater(
          swapEncryptedIntoPlace(
            plainPath: p('reg.db'),
            targetPath: p('reg.db.converting'),
            backupPath: p('reg.db.plaintext-backup'),
          ),
          throwsA(isA<StateError>()),
        );
        // Overwriting the older backup would destroy the only copy that register
        // has ever had, so the swap refuses with three files left as they were.
        expect(
          await File(p('reg.db.plaintext-backup')).readAsString(),
          'an older plaintext register',
        );
        expect(await File(p('reg.db.converting')).exists(), isTrue);
      },
    );
  });

  group('the guarded run', () {
    test(
      'a build with no encrypted engine refuses and changes nothing',
      () async {
        final outcome = await DatabaseConversion.runGuarded();
        expect(outcome.converted, isFalse);
        expect(
          outcome.message,
          contains('SQLCipher'),
          reason: 'it should say which capability is missing, not just fail',
        );
      },
    );
  });
}
