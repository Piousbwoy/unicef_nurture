/// The FHW register spans her whole region, not just her district.
///
/// Pins the scoping contract of [CareRepository.visibleHouseholds] and
/// [CareRepository.searchHouseholds]: a worker posted anywhere in the region
/// she signed up in can find any family in it — a colleague's household in a
/// neighbouring district is searchable, while a record from another region
/// never surfaces. The day plan keeps the narrower district scope; this test
/// covers the register and the search, which are what a CHO uses when the
/// family in front of her is not on her own list.
library;

import 'dart:io';

import 'package:carebridge_ai/data/local/app_database.dart';
import 'package:carebridge_ai/data/local/household_dao.dart';
import 'package:carebridge_ai/data/repositories/care_repository.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

AppUser _fhw() => AppUser(
  id: 'u-fhw-scope',
  fullName: 'Amina Fuseini',
  phone: '0244000000',
  role: UserRole.frontlineHealthWorker,
  region: 'Northern Region',
  district: 'Savelugu Municipal',
  community: 'Tamale Central',
);

Household _household({
  required String id,
  required String name,
  required String region,
  required String district,
  String createdBy = 'u-colleague',
  String? landmark,
}) => Household(
  id: id,
  name: name,
  region: region,
  district: district,
  community: 'Test community',
  createdBy: createdBy,
  headName: 'Head of $name',
  landmark: landmark,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an FHW sees and searches every household in her region', (
    tester,
  ) async {
    // The database resolves its file through the path_provider channel,
    // which has no plugin in the test VM. Point it at a fresh temp folder.
    final dbDir = Directory.systemTemp.createTempSync('carebridge_scope');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return dbDir.path;
        }
        return null;
      },
    );
    AppDatabase.initialiseForDesktopAndTests();

    // Genuine sqflite FFI IO cannot run inside the FakeAsync zone that
    // testWidgets installs — runAsync lets the real futures complete.
    await tester.runAsync(() async {
      final user = _fhw();

      // A colleague's household in the FHW's own district.
      await HouseholdDao.upsert(
        _household(
          id: 'h-same-district',
          name: 'The Achana family',
          region: 'Northern Region',
          district: 'Savelugu Municipal',
        ),
      );
      // A colleague's household in another district of the same region.
      await HouseholdDao.upsert(
        _household(
          id: 'h-other-district',
          name: 'The Dawura family',
          region: 'Northern Region',
          district: 'Tamale Metropolitan',
          landmark: 'Behind the big mango tree',
        ),
      );
      // A household the FHW herself registered while posted outside her region.
      await HouseholdDao.upsert(
        _household(
          id: 'h-own-outside',
          name: 'The Kanton family',
          region: 'Upper East Region',
          district: 'Bolgatanga Municipal',
          createdBy: user.id,
        ),
      );
      // A colleague's household in a different region entirely.
      await HouseholdDao.upsert(
        _household(
          id: 'h-other-region',
          name: 'The Adongo family',
          region: 'Upper East Region',
          district: 'Bawku West',
          landmark: 'Beside the mango stand at the market',
        ),
      );

      final repo = CareRepository();

      final visible = await repo.visibleHouseholds(user);
      final visibleIds = visible.map((h) => h.id).toSet();
      expect(visibleIds, contains('h-same-district'));
      expect(
        visibleIds,
        contains('h-other-district'),
        reason: 'the register spans the whole region, not one district',
      );
      expect(
        visibleIds,
        contains('h-own-outside'),
        reason: 'a household she registered herself always follows her',
      );
      expect(
        visibleIds,
        isNot(contains('h-other-region')),
        reason: 'another region\u2019s families never surface on her phone',
      );

      final found = await repo.searchHouseholds(user, 'mango');
      final foundIds = found.map((h) => h.id).toSet();
      expect(
        foundIds,
        contains('h-other-district'),
        reason: 'a landmark search reaches across districts in her region',
      );
      expect(
        foundIds,
        isNot(contains('h-other-region')),
        reason: 'search is narrowed to her region',
      );
    });
  });
}
