/// Role-based access control: the exact permission boundary between the two
/// roles, pinned in tests so a casual edit to the permission sets cannot
/// quietly give a caregiver clinical write access.
library;

import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

AppUser _user(UserRole role) => AppUser(
  id: 'u-${role.name}',
  fullName: role.isFhw ? 'Amina Fuseini' : 'Mariama Alhassan',
  phone: '0244000000',
  role: role,
  region: 'Northern Region',
  district: 'Gushegu',
  community: 'Gushegu',
);

void main() {
  group('Caregiver permissions', () {
    final caregiver = _user(UserRole.caregiver);

    test('are exactly the three family-scoped capabilities', () {
      expect(
        caregiver.permissions,
        {
          Permission.viewOwnFamilyOnly,
          Permission.runCaregiverTriage,
          Permission.recordBarrier,
        },
      );
    });

    test('never include clinical write access', () {
      const forbidden = [
        Permission.runClinicalAssessment,
        Permission.recordClinicalVitals,
        Permission.issueReferral,
        Permission.confirmReferralArrival,
        Permission.overrideAiRecommendation,
        Permission.registerHousehold,
        Permission.viewAllHouseholds,
        Permission.viewCommunityInsights,
        Permission.planVisitRoute,
        Permission.exportRecords,
      ];

      for (final p in forbidden) {
        expect(caregiver.can(p), isFalse, reason: p.name);
      }
    });
  });

  group('Frontline health worker permissions', () {
    final fhw = _user(UserRole.frontlineHealthWorker);

    test('hold the full clinical scope', () {
      const required = [
        Permission.registerHousehold,
        Permission.viewAllHouseholds,
        Permission.recordClinicalVitals,
        Permission.runClinicalAssessment,
        Permission.issueReferral,
        Permission.confirmReferralArrival,
        Permission.overrideAiRecommendation,
        Permission.viewCommunityInsights,
        Permission.recordBarrier,
        Permission.planVisitRoute,
        Permission.exportRecords,
      ];

      for (final p in required) {
        expect(fhw.can(p), isTrue, reason: p.name);
      }
    });

    test('do not hold the caregiver-only family scope flag', () {
      expect(fhw.can(Permission.viewOwnFamilyOnly), isFalse);
    });
  });

  group('Role routing', () {
    test('each role lands on its own home', () {
      expect(UserRole.frontlineHealthWorker.isFhw, isTrue);
      expect(UserRole.caregiver.isCaregiver, isTrue);
      expect(UserRole.caregiver.isFhw, isFalse);
    });
  });
}
