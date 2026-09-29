/// Referral codes resolve a family at the facility and carry a UNIQUE index, so
/// two referrals must never share one. A plain 4-character random code collides
/// with real probability once a device holds a few hundred referrals, and a
/// collision throws at insert and fails the save. [ReferralDao.mintReferenceCode]
/// draws candidates until one is unused; these tests pin that guarantee down.
library;

import 'dart:io';

import 'package:carebridge_ai/data/local/app_database.dart';
import 'package:carebridge_ai/data/local/household_dao.dart';
import 'package:carebridge_ai/data/local/visit_dao.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Referral _ref(String id, String code) => Referral(
  id: id,
  referenceCode: code,
  personId: 'p-1',
  assessmentId: 'a-$id',
  facilityName: 'Bawku Municipal Hospital',
  reason: 'Referred for assessment',
  urgency: ReferralUrgency.sameDay,
  issuedBy: 'worker-1',
  issuedAt: DateTime(2026, 1, 1),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('carebridge_code');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? dir.path
              : null,
        );
    AppDatabase.initialiseForDesktopAndTests();
    await HouseholdDao.upsert(
      Household(
        id: 'h-1',
        name: 'The Test family',
        region: 'Upper East Region',
        district: 'Bawku Municipal',
        community: 'Zenuoye',
        createdBy: 'worker-1',
      ),
    );
    await PersonDao.upsert(
      Person(
        id: 'p-1',
        householdId: 'h-1',
        fullName: 'Test Person',
        clientType: ClientType.childUnderFive,
        dateOfBirth: DateTime(2024),
      ),
    );
  });
  tearDown(() async {
    await AppDatabase.instance.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('codeExists detects a stored code case-insensitively', () async {
    expect(await ReferralDao.codeExists('CB-7K2M'), isFalse);
    await ReferralDao.upsert(_ref('ref-1', 'CB-7K2M'));
    expect(await ReferralDao.codeExists('CB-7K2M'), isTrue);
    expect(await ReferralDao.codeExists('cb-7k2m'), isTrue);
    expect(await ReferralDao.codeExists(' CB-7K2M '), isTrue);
    expect(await ReferralDao.codeExists('CB-9999'), isFalse);
  });

  test('a minted code is well-formed and not already in the register',
      () async {
    await ReferralDao.upsert(_ref('ref-1', 'CB-7K2M'));
    final minted = await ReferralDao.mintReferenceCode();
    expect(minted, matches(RegExp(r'^CB-[A-Z2-9]{4}$')));
    expect(minted, isNot('CB-7K2M'));
    expect(await ReferralDao.codeExists(minted), isFalse);
  });

  test('repeated mints over a growing register never repeat a live code',
      () async {
    // Each minted code is committed before the next draw, so any draw that did
    // not check uniqueness would eventually hand back a code already stored —
    // the exact collision the UNIQUE index would turn into a failed save.
    final seen = <String>{};
    for (var i = 0; i < 40; i++) {
      final code = await ReferralDao.mintReferenceCode();
      expect(seen, isNot(contains(code)));
      expect(await ReferralDao.codeExists(code), isFalse);
      await ReferralDao.upsert(_ref('ref-$i', code));
      seen.add(code);
    }
    expect(await ReferralDao.codeExists(seen.first), isTrue);
  });
}
