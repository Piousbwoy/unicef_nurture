/// The governance register, checked against the system it describes.
///
/// Every test here asks a question a document cannot answer: does the register
/// match the schema, the whitelist and the pull list as they are *today*? That is
/// the only property that keeps a privacy register honest — not the writing, the
/// reconciliation.
///
/// Read the failures as instructions. A red test in this file never means "the
/// register is broken"; it means "the software changed and the record of why is now
/// a false statement". Fix it by declaring the new table's purpose, or by removing
/// the row the code no longer creates.
library;

import 'dart:io';

import 'package:carebridge_ai/data/sync/sync_service.dart';
import 'package:carebridge_ai/domain/compliance.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/domain/governance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) {
    final f = File(path);
    expect(
      f.existsSync(),
      isTrue,
      reason: '$path is part of the reconciliation',
    );
    return f.readAsStringSync();
  }

  /// Tables the handset creates, read out of the DDL that builds them.
  Set<String> localTables() {
    final src = read('lib/data/local/app_database.dart');
    // `static const persons = 'persons';` inside the Tables class — the names the
    // DDL interpolates are resolved to the strings actually used in SQL.
    final names = <String, String>{
      for (final m in RegExp(
        r"static const (\w+)\s*=\s*'([^']+)'",
      ).allMatches(src))
        m.group(1)!: m.group(2)!,
    };
    return {
      for (final m in RegExp(
        r'CREATE TABLE (?:IF NOT EXISTS )?\$\{Tables\.(\w+)\}',
      ).allMatches(src))
        names[m.group(1)!] ?? m.group(1)!,
    };
  }

  /// Tables the district keeps.
  Set<String> serverTables() {
    final src = read('server/schema.sql');
    return {
      for (final m in RegExp(
        r'CREATE TABLE IF NOT EXISTS `?(\w+)`?\s*\(',
      ).allMatches(src))
        m.group(1)!,
    };
  }

  /// Tables a device is allowed to write remotely.
  Set<String> whitelisted() {
    final src = read('server/src/tables.js');
    final body = src.substring(src.indexOf('const TABLES = {'));
    final stop = body.indexOf('\n};');
    final block = stop < 0 ? body : body.substring(0, stop);
    return {
      for (final m in RegExp(
        r'^\s\s(\w+):\s*\{$',
        multiLine: true,
      ).allMatches(block))
        m.group(1)!,
    };
  }

  /// Tables the server will hand to a handset on pull.
  Set<String> pulled() {
    final src = read('server/src/pull.js');
    final body = src.substring(src.indexOf('const PULL_TABLES = ['));
    final stop = body.indexOf('\n];');
    return {
      for (final m in RegExp(
        r"name:\s*'(\w+)'",
      ).allMatches(body.substring(0, stop)))
        m.group(1)!,
    };
  }

  Set<String> scopeOf(bool Function(StorageScope) test) => {
    for (final d in GovernanceRegister.data)
      if (test(d.scope)) d.table,
  };

  group('the register matches the schema', () {
    test('every table created on a handset is declared, with its scope', () {
      final actual = localTables();
      final claimed = scopeOf(
        (s) =>
            s == StorageScope.deviceOnly || s == StorageScope.deviceAndDistrict,
      );
      expect(
        actual.difference(claimed),
        isEmpty,
        reason:
            'A new local table has no declared purpose, lawful basis or '
            'retention rule. Add it to GovernanceRegister.data.',
      );
      expect(
        claimed.difference(actual),
        isEmpty,
        reason:
            'The register claims a local table the schema no longer creates.',
      );
    });

    test('every table the district keeps is declared', () {
      final actual = serverTables();
      final claimed = scopeOf(
        (s) =>
            s == StorageScope.districtOnly ||
            s == StorageScope.deviceAndDistrict ||
            s == StorageScope.pushedNotStored,
      );
      expect(
        actual.difference(claimed),
        isEmpty,
        reason: 'server/schema.sql gained a table nobody has justified.',
      );
      expect(
        claimed.difference(actual),
        isEmpty,
        reason: 'The register claims a district table that does not exist.',
      );
    });

    test('the sync whitelist and the register agree, in both directions', () {
      final actual = whitelisted();
      final claimed = scopeOf(
        (s) =>
            s == StorageScope.deviceAndDistrict ||
            s == StorageScope.pushedNotStored,
      );
      expect(
        actual.difference(claimed),
        isEmpty,
        reason:
            'A table was added to server/src/tables.js, which means a device '
            'may now write it remotely. That is a change to what leaves a '
            'handset and must be registered before it is shipped.',
      );
      expect(
        claimed.difference(actual),
        isEmpty,
        reason:
            'The register says a table travels to the district; the whitelist '
            'refuses it, so the row silently never arrives.',
      );
    });

    test('the pull list is exactly the registered set', () {
      expect(
        pulled(),
        equals(GovernanceRegister.pulledOntoOtherDevices.toSet()),
        reason:
            'The pull list decides which families\' data appears on a handset '
            'that never treated them. Widening it is a minimisation decision, '
            'not a sync one.',
      );
    });

    test('the evidence and the credentials never come back down', () {
      final spread = pulled().intersection(
        GovernanceRegister.mustNotSpread.toSet(),
      );
      expect(
        spread,
        isEmpty,
        reason:
            '${spread.join(', ')} is on the pull list. Consent history, the '
            'access trail, an open rights request, a credential verifier and the '
            'district\'s own logs must not be downloaded onto every handset to '
            'answer a question only a supervisor should ask.',
      );
    });

    test('whitelistedForSync is derived, not a second list', () {
      expect(
        GovernanceRegister.whitelistedForSync.toSet(),
        equals(whitelisted()),
      );
    });
  });

  group('the register is internally honest', () {
    test('every table names an activity that exists', () {
      final ids = GovernanceRegister.activities.map((a) => a.id).toSet();
      for (final d in GovernanceRegister.data) {
        expect(
          ids,
          contains(d.activity),
          reason: 'Table ${d.table} cites unknown activity ${d.activity}.',
        );
        expect(
          d.contains.trim(),
          isNotEmpty,
          reason: '${d.table} has no plain-words description of its contents.',
        );
      }
    });

    test('no activity exists that nothing stores', () {
      for (final a in GovernanceRegister.activities) {
        final rows = GovernanceRegister.tablesFor(a.id);
        if (rows.isEmpty) {
          expect(
            a.nonTableStorage.trim(),
            isNotEmpty,
            reason:
                'Activity "${a.title}" is declared, owns no table, and does not '
                'say where its data actually lives. An undeclared store is the '
                'one way this register can be false.',
          );
        }
      }
    });

    test('no table is claimed by two activities', () {
      final seen = <String, String>{};
      for (final d in GovernanceRegister.data) {
        expect(
          seen[d.table],
          isNull,
          reason:
              '${d.table} is claimed by both ${seen[d.table]} and ${d.activity}; '
              'a table with two purposes has one of them wrong.',
        );
        seen[d.table] = d.activity;
      }
    });

    test(
      'every activity states a basis, a retention rule and an enforcement point',
      () {
        for (final a in GovernanceRegister.activities) {
          expect(a.purpose.trim(), isNotEmpty);
          expect(a.subjects.trim(), isNotEmpty);
          expect(
            a.retention.trim(),
            isNotEmpty,
            reason: '${a.id} processes data with no stated retention.',
          );
          expect(
            a.guard.trim(),
            isNotEmpty,
            reason:
                '${a.id} claims access rules but names no code that enforces '
                'them.',
          );
        }
      },
    );

    test('health rows are registered as special personal data', () {
      final clinical = {
        'maternal_records',
        'birth_records',
        'child_assessment_snapshots',
        'growth_measurements',
        'assessments',
        'referrals',
      };
      for (final t in clinical) {
        final d = GovernanceRegister.data.firstWhere((x) => x.table == t);
        final a = GovernanceRegister.activityById(d.activity)!;
        expect(
          a.specialPersonalData,
          isTrue,
          reason:
              '$t carries health data and must be flagged under Act 843 s.37.',
        );
      }
    });

    test('every capability is accounted for in the matrix', () {
      final covered = <Permission>{};
      for (final a in GovernanceRegister.activities) {
        covered.addAll(a.readBy);
        covered.addAll(a.writeBy);
      }
      expect(
        Permission.values.toSet().difference(covered),
        isEmpty,
        reason:
            'A Permission exists that no registered activity mentions. Either '
            'it grants access to something undocumented, or it is dead code.',
      );
    });

    test('the matrix is generated from the enforced capability set', () {
      // Not a copy of the role definitions: this asks the same function the
      // widgets and the repository ask.
      final fhw = Permission.forRole(UserRole.frontlineHealthWorker);
      final rows = GovernanceRegister.accessMatrix(
        UserRole.frontlineHealthWorker,
      );
      for (final row in rows) {
        expect(
          row.writable,
          row.activity.writeBy.intersection(fhw).isNotEmpty,
          reason: row.activity.title,
        );
      }
      final caregiver = GovernanceRegister.accessMatrix(UserRole.caregiver);
      expect(caregiver, isNotEmpty);
      expect(
        caregiver.any((r) => r.writable && r.activity.id == 'maternal'),
        isFalse,
        reason: 'A family account must not be able to write clinical records.',
      );
    });

    test('the promise in the register is the promise in the notice', () {
      final a = GovernanceRegister.activityById('dataRights')!;
      expect(a.retention, contains('answer'));
      expect(CareNotice.serviceDeadlineLabel, '30 days');
    });
  });

  group('the notice is true of the running system', () {
    test('the notice describes sync the way sync actually runs', () {
      // Consent under Act 843 is only valid against words that are true of the
      // code. SyncService.start() arms a periodic timer and pushes the moment
      // connectivity returns, and nothing in the app asks a family to press a
      // button — so a notice promising otherwise would be a false statement
      // made in the one screen where permission is taken.
      final sync = CareNotice.points.firstWhere((p) => p.$1.startsWith('Sent'));
      expect(sync.$2, contains('by itself'));
      expect(
        sync.$2,
        contains('${CareNotice.syncInterval.inMinutes} minutes'),
        reason: 'The notice must name the interval the timer runs on.',
      );
      expect(
        SyncService().interval,
        CareNotice.syncInterval,
        reason: 'One interval, in the code and in the words.',
      );
      for (final p in CareNotice.points) {
        expect(
          p.$2,
          isNot(contains('only when you')),
          reason: '${p.$1} puts sending back on the family.',
        );
      }
    });

    test('the checks a family keeps for itself are provably device-only', () {
      final byTable = {for (final d in GovernanceRegister.data) d.table: d};
      for (final table in [
        'home_checks',
        'caregiver_drafts',
        'caregiver_activity',
        'caregiver_settings',
      ]) {
        expect(
          byTable[table]?.scope,
          StorageScope.deviceOnly,
          reason:
              'The consent notice tells a family this never leaves the phone. '
              'If it starts travelling, the notice has to change with it.',
        );
        expect(
          whitelisted(),
          isNot(contains(table)),
          reason: '$table is promised as private but is pushable.',
        );
      }
    });
  });

  group('the control map can be gone and read', () {
    test('every implementation file exists', () {
      for (final c in GovernanceRegister.controls) {
        expect(
          c.implementations,
          isNotEmpty,
          reason: '${c.id} claims a control with nowhere to look.',
        );
        for (final p in c.implementations) {
          expect(
            File(p).existsSync(),
            isTrue,
            reason: '${c.id} cites $p, which is not in the repository.',
          );
        }
      }
    });

    test('every proof test exists', () {
      for (final c in GovernanceRegister.controls) {
        for (final p in c.proofTests) {
          expect(
            File(p).existsSync(),
            isTrue,
            reason: '${c.id} claims proof in $p, which does not exist.',
          );
        }
      }
    });

    test(
      'a control claimed to be in place is either tested or concedes a limit',
      () {
        for (final c in GovernanceRegister.controls.where(
          (c) => c.needsProof,
        )) {
          final tested = c.proofTests.isNotEmpty;
          expect(
            tested || c.boundary.trim().isNotEmpty,
            isTrue,
            reason:
                '${c.id} is marked "${c.maturity.label}" with no test and no '
                'stated boundary. Either prove it or say what it does not cover.',
          );
        }
      },
    );

    test('a control not owned by this software says who owns it', () {
      for (final c in GovernanceRegister.controls.where(
        (c) => c.maturity == ControlMaturity.notOurs,
      )) {
        expect(
          c.owner,
          isNot(ControlOwnership.appTeam),
          reason:
              '${c.id} is declared out of scope but leaves the residual risk '
              'with the app team, which cannot discharge it.',
        );
      }
    });

    test('no two controls share an id', () {
      final ids = GovernanceRegister.controls.map((c) => c.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test(
      'framework citations are never empty, so a control can be audited',
      () {
        for (final c in GovernanceRegister.controls) {
          expect(c.frameworks, isNotEmpty, reason: c.id);
        }
      },
    );
  });

  group('nothing phones home', () {
    test('no analytics, crash-reporting or advertising dependency is declared', () {
      const forbidden = {
        'sentry',
        'flutter_hooks_analytics',
        'firebase_analytics',
        'firebase_crashlytics',
        'firebase_performance',
        'mixpanel_flutter',
        'amplitude_flutter',
        'segment_analytics_flutter',
        'posthog_flutter',
        'matomo_tracker',
        'telemetry',
        'google_mobile_ads',
        'appsflyer_sdk',
        'branch_sdk',
      };
      final src = read('pubspec.yaml');
      final declared = {
        for (final m in RegExp(
          r'^\s\s([a-z0-9_]+):\s*(?:\^|~|\d|http|flutter|git|\{)',
          multiLine: true,
        ).allMatches(src))
          m.group(1)!,
      };
      final hit = declared.intersection(forbidden);
      expect(
        hit,
        isEmpty,
        reason:
            '${hit.join(', ')} is now a dependency. Patient payloads would leave '
            'for a third party that is not the district; the register claims this '
            'app has no telemetry, and a claim needs to stay true.',
      );
    });
  });

  group('the document is a build artefact', () {
    test('docs/GOVERNANCE.md matches the register', () {
      final target = File('docs/GOVERNANCE.md');
      final rendered = GovernanceDocs.render();
      if (Platform.environment['WRITE_GOVERNANCE_DOC'] == '1') {
        target.writeAsStringSync(rendered);
        stdout.writeln('docs/GOVERNANCE.md rewritten from the register.');
        return;
      }
      expect(
        target.existsSync(),
        isTrue,
        reason:
            'Missing. Regenerate with '
            'WRITE_GOVERNANCE_DOC=1 flutter test test/governance_test.dart',
      );
      expect(
        target.readAsStringSync().replaceAll('\r\n', '\n'),
        equals(rendered),
        reason:
            'The document no longer matches the register — it was hand-edited, '
            'or the register changed. Regenerate with '
            'WRITE_GOVERNANCE_DOC=1 flutter test test/governance_test.dart',
      );
    });

    test('the render carries no timestamp, so the check stays a check', () {
      final rendered = GovernanceDocs.render();
      expect(rendered, isNot(contains('Generated on')));
      expect(
        RegExp(r'\b\d{4}-\d{2}-\d{2}\b').hasMatch(rendered),
        isFalse,
        reason:
            'A date in a generated file means the file differs from itself every '
            'day, and a check that always fails gets switched off.',
      );
    });

    test('the render names every table and every control', () {
      final rendered = GovernanceDocs.render();
      for (final d in GovernanceRegister.data) {
        expect(rendered, contains('`${d.table}`'), reason: d.table);
      }
      for (final c in GovernanceRegister.controls) {
        expect(rendered, contains('`${c.id}`'), reason: c.id);
      }
    });
  });
}
