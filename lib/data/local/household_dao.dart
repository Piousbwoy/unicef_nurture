/// Households and the people inside them.
///
/// Every write here goes through a transaction that also queues an outbox row,
/// so a record can never exist on the device without the intent to send it.
///
/// The queries are shaped by what a CHO actually needs rather than by what is
/// tidy to model. [PersonDao.clientsForVisit] is the clearest example: when
/// Mariama walks into the compound with a newborn twin on her back and a
/// three-year-old holding her hand, the app must produce *that queue* in one
/// query — mother, then newborns, then under-fives — not three screens of
/// searching while she waits.
library;

import 'package:sqflite/sqflite.dart';

import '../../domain/entities/core.dart';
import '../../domain/enums.dart';
import '../../domain/family_code.dart';
import 'app_database.dart';
import 'outbox_dao.dart';

abstract final class HouseholdDao {
  static Future<void> upsert(Household h) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final map = h.toMap();
      await txn.insert(
        Tables.households,
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await OutboxDao.enqueue(
        txn,
        table: Tables.households,
        entityId: h.id,
        operation: SyncOperation.update,
        payload: map,
        priority: SyncPriority.routine,
      );
    });
  }

  static Future<Household?> byId(String id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.households,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Household.fromMap(rows.first);
  }

  /// All households in a CHPS zone. [community] narrows to a single village,
  /// which is how a CHO plans a day on foot.
  static Future<List<Household>> inZone({
    required String region,
    required String district,
    String? community,
  }) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.households,
      where: community == null
          ? 'region = ? AND district = ?'
          : 'region = ? AND district = ? AND community = ?',
      whereArgs: community == null
          ? [region, district]
          : [region, district, community],
      orderBy: 'community ASC, name ASC',
    );
    return rows.map(Household.fromMap).toList(growable: false);
  }

  /// Every household one worker is actually responsible for.
  ///
  /// Not a pure geographic query, because a CHO's caseload is not a rectangle on
  /// a map. It is every compound in their own register — including the ones
  /// picked up on an outreach run across a district boundary, which for a zone
  /// bordered by the White Volta happens most weeks — plus anything registered
  /// anywhere in their region by a colleague, because a worker posted across a
  /// district within the same region must still be able to find the family in
  /// front of her. [district] narrows the geographic arm to one MMDA — the
  /// day plan and zone analytics keep that scope; the register does not.
  ///
  /// Getting this wrong is not a cosmetic bug: a household missing from the
  /// caseload is a household that never appears in the day plan.
  static Future<List<Household>> caseloadFor({
    required String workerId,
    required String region,
    String? district,
    String? community,
  }) async {
    final db = await AppDatabase.instance.database;
    final where = district == null
        ? (community == null
              ? 'created_by = ? OR region = ?'
              : 'created_by = ? OR (region = ? AND community = ?)')
        : (community == null
              ? 'created_by = ? OR (region = ? AND district = ?)'
              : 'created_by = ? OR (region = ? AND district = ? AND community = ?)');
    final args = district == null
        ? (community == null
              ? [workerId, region]
              : [workerId, region, community])
        : (community == null
              ? [workerId, region, district]
              : [workerId, region, district, community]);
    final rows = await db.query(
      Tables.households,
      where: where,
      whereArgs: args,
      orderBy: 'community ASC, name ASC',
    );
    return rows.map(Household.fromMap).toList(growable: false);
  }

  /// Resolves the code a CHO read out to a caregiver.
  ///
  /// A scan rather than an indexed lookup, because the code is derived from the
  /// id rather than stored. At zone scale — a few hundred compounds — that is a
  /// single query and a loop, and it buys a code that needs no column, no
  /// migration and no coordination between devices.
  static Future<Household?> byFamilyCode(String typedCode) async {
    if (!FamilyCode.looksValid(typedCode)) return null;
    final db = await AppDatabase.instance.database;
    final rows = await db.query(Tables.households, columns: ['id']);
    for (final row in rows) {
      final id = row['id'] as String;
      if (FamilyCode.matches(id, typedCode)) return byId(id);
    }
    return null;
  }

  static Future<List<Household>> all() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(Tables.households, orderBy: 'updated_at DESC');
    return rows.map(Household.fromMap).toList(growable: false);
  }

  /// Name, head, community or landmark, narrowed to the worker's own region.
  /// Landmark is included deliberately: in a village with no addresses,
  /// "behind the mosque" is how a compound is found, and a CHO covering for a
  /// colleague will search for exactly that. The region arm means a worker
  /// posted anywhere in her region finds every family in it — while a record
  /// synced from another region never surfaces on her phone.
  static Future<List<Household>> search(String query, {required String region}) async {
    final db = await AppDatabase.instance.database;
    final q = '%${query.trim()}%';
    final rows = await db.query(
      Tables.households,
      where:
          '(name LIKE ? OR head_name LIKE ? OR community LIKE ? OR landmark LIKE ?) AND region = ?',
      whereArgs: [q, q, q, q, region],
      orderBy: 'name ASC',
      limit: 50,
    );
    return rows.map(Household.fromMap).toList(growable: false);
  }

  /// Distinct communities that have at least one registered household — used to
  /// offer only places the CHO actually works, not all 55 MMDAs.
  static Future<List<String>> knownCommunities() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT community FROM ${Tables.households} ORDER BY community ASC',
    );
    return rows.map((r) => r['community'] as String).toList(growable: false);
  }

  static Future<int> count() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${Tables.households}',
    );
    return (rows.first['c'] as num).toInt();
  }
}

abstract final class PersonDao {
  static Future<void> upsert(Person person) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final map = person.toMap();
      await txn.insert(
        Tables.persons,
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await OutboxDao.enqueue(
        txn,
        table: Tables.persons,
        entityId: person.id,
        operation: SyncOperation.update,
        payload: map,
        priority: SyncPriority.routine,
      );
    });
  }

  /// Registers a mother and her newborns in one atomic write.
  ///
  /// This exists because the delivery scenario is a single event, not a sequence
  /// of independent registrations. A twin birth recorded halfway — mother saved,
  /// second twin lost because the battery died — produces exactly the invisible
  /// newborn this app is meant to prevent.
  static Future<void> registerFamily({
    required Household household,
    Person? mother,
    MaternalRecord? maternalRecord,
    List<Person> children = const [],
    Map<String, BirthRecord> birthRecords = const {},
  }) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final hm = household.toMap();
      await txn.insert(
        Tables.households,
        hm,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await OutboxDao.enqueue(
        txn,
        table: Tables.households,
        entityId: household.id,
        operation: SyncOperation.update,
        payload: hm,
      );

      if (mother != null) {
        final mm = mother.toMap();
        await txn.insert(
          Tables.persons,
          mm,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await OutboxDao.enqueue(
          txn,
          table: Tables.persons,
          entityId: mother.id,
          operation: SyncOperation.update,
          payload: mm,
        );
      }

      if (maternalRecord != null) {
        final rm = maternalRecord.toMap();
        await txn.insert(
          Tables.maternalRecords,
          rm,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await OutboxDao.enqueue(
          txn,
          table: Tables.maternalRecords,
          entityId: maternalRecord.personId,
          operation: SyncOperation.update,
          payload: rm,
          priority: SyncPriority.clinical,
        );
      }

      for (final child in children) {
        final cm = child.toMap();
        await txn.insert(
          Tables.persons,
          cm,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await OutboxDao.enqueue(
          txn,
          table: Tables.persons,
          entityId: child.id,
          operation: SyncOperation.update,
          payload: cm,
        );

        final birth = birthRecords[child.id];
        if (birth != null) {
          final bm = birth.toMap();
          await txn.insert(
            Tables.birthRecords,
            bm,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          await OutboxDao.enqueue(
            txn,
            table: Tables.birthRecords,
            entityId: birth.personId,
            operation: SyncOperation.update,
            payload: bm,
            priority: SyncPriority.clinical,
          );
        }
      }
    });
  }

  static Future<Person?> byId(String id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.persons,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Person.fromMap(rows.first);
  }

  static Future<List<Person>> inHousehold(String householdId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.persons,
      where: 'household_id = ? AND is_active = 1',
      whereArgs: [householdId],
      orderBy: 'client_type ASC, date_of_birth ASC',
    );
    return rows.map(Person.fromMap).toList(growable: false);
  }

  /// The multi-client queue for one visit, ordered the way care is actually
  /// delivered: the mother first, then any newborn (most fragile, and the young
  /// infant protocol has the tightest time constraints), then the under-fives
  /// by age.
  ///
  /// Sorting in Dart rather than SQL because the ordering depends on
  /// [Person.effectiveClientType], which is derived from age at *this moment* —
  /// a baby registered as a newborn six weeks ago now belongs to the child
  /// protocol, and the stored label no longer tells the truth.
  static Future<List<Person>> clientsForVisit(String householdId) async {
    final people = await inHousehold(householdId);
    int rank(Person p) => switch (p.effectiveClientType) {
      ClientType.pregnantWoman => 0,
      ClientType.postpartumWoman => 1,
      ClientType.newborn => 2,
      ClientType.childUnderFive => 3,
      // A woman presenting for general or family-planning care is seen after
      // the children: nothing in her queue position is time-critical in the way
      // a newborn's is.
      ClientType.womanOfReproductiveAge => 4,
    };
    final sorted = [...people]
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        if (byRank != 0) return byRank;
        final aDob = a.dateOfBirth;
        final bDob = b.dateOfBirth;
        if (aDob == null || bDob == null) return a.fullName.compareTo(b.fullName);
        return aDob.compareTo(bDob);
      });
    return sorted;
  }

  /// A mother's children. Pulls maternal history into a child's assessment, and
  /// lets a CHO seeing one sibling ask about the others.
  static Future<List<Person>> childrenOf(String motherId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.persons,
      where: 'mother_id = ? AND is_active = 1',
      whereArgs: [motherId],
      orderBy: 'date_of_birth DESC',
    );
    return rows.map(Person.fromMap).toList(growable: false);
  }

  static Future<List<Person>> byClientType(ClientType type) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.persons,
      where: 'client_type = ? AND is_active = 1',
      whereArgs: [type.name],
      orderBy: 'updated_at DESC',
    );
    return rows.map(Person.fromMap).toList(growable: false);
  }

  static Future<List<Person>> search(String query) async {
    final db = await AppDatabase.instance.database;
    final q = '%${query.trim()}%';
    final rows = await db.query(
      Tables.persons,
      where: '(full_name LIKE ? OR nhis_number LIKE ?) AND is_active = 1',
      whereArgs: [q, q],
      orderBy: 'full_name ASC',
      limit: 50,
    );
    return rows.map(Person.fromMap).toList(growable: false);
  }

  /// Deactivates rather than deletes. A person who has moved away, or died, must
  /// stay in the record — their history is why the next assessment is safe, and
  /// a deleted stillbirth is a statistic that never gets counted.
  static Future<void> deactivate(String id) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.update(
        Tables.persons,
        {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
      await OutboxDao.enqueue(
        txn,
        table: Tables.persons,
        entityId: id,
        operation: SyncOperation.update,
        payload: {'id': id, 'is_active': 0},
      );
    });
  }

  /// Households with at least one person, plus who is in them — used by the
  /// dashboard so it does not run one query per household.
  static Future<Map<String, List<Person>>> groupedByHousehold() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.persons,
      where: 'is_active = 1',
      orderBy: 'household_id ASC, client_type ASC',
    );
    final grouped = <String, List<Person>>{};
    for (final row in rows) {
      final person = Person.fromMap(row);
      grouped.putIfAbsent(person.householdId, () => <Person>[]).add(person);
    }
    return grouped;
  }
}

abstract final class MaternalRecordDao {
  static Future<void> upsert(MaternalRecord record) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final map = record.toMap();
      await txn.insert(
        Tables.maternalRecords,
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await OutboxDao.enqueue(
        txn,
        table: Tables.maternalRecords,
        entityId: record.personId,
        operation: SyncOperation.update,
        payload: map,
        priority: SyncPriority.clinical,
      );
    });
  }

  static Future<MaternalRecord?> forPerson(String personId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.maternalRecords,
      where: 'person_id = ?',
      whereArgs: [personId],
      limit: 1,
    );
    return rows.isEmpty ? null : MaternalRecord.fromMap(rows.first);
  }

  /// Every woman currently pregnant, so the ANC-defaulter query does not have
  /// to load the whole register.
  static Future<List<MaternalRecord>> pregnant() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.maternalRecords,
      where: 'delivery_date IS NULL AND last_menstrual_period IS NOT NULL',
    );
    return rows
        .map(MaternalRecord.fromMap)
        .where((r) => r.gestationalWeeks != null)
        .toList(growable: false);
  }

  /// Women within 42 days of delivery — the window in which most maternal
  /// deaths in this region happen.
  static Future<List<MaternalRecord>> postpartum() async {
    final db = await AppDatabase.instance.database;
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 42))
        .toIso8601String();
    final rows = await db.query(
      Tables.maternalRecords,
      where: 'delivery_date IS NOT NULL AND delivery_date >= ?',
      whereArgs: [cutoff],
      orderBy: 'delivery_date DESC',
    );
    return rows.map(MaternalRecord.fromMap).toList(growable: false);
  }
}

abstract final class BirthRecordDao {
  static Future<void> upsert(BirthRecord record) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final map = record.toMap();
      await txn.insert(
        Tables.birthRecords,
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await OutboxDao.enqueue(
        txn,
        table: Tables.birthRecords,
        entityId: record.personId,
        operation: SyncOperation.update,
        payload: map,
        priority: SyncPriority.clinical,
      );
    });
  }

  static Future<BirthRecord?> forPerson(String personId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.birthRecords,
      where: 'person_id = ?',
      whereArgs: [personId],
      limit: 1,
    );
    return rows.isEmpty ? null : BirthRecord.fromMap(rows.first);
  }

  /// All birth records for a set of people, in one query. Twins are common and
  /// the young-infant assessment needs both siblings' birth facts at once.
  static Future<Map<String, BirthRecord>> forPeople(
    Iterable<String> personIds,
  ) async {
    if (personIds.isEmpty) return const {};
    final db = await AppDatabase.instance.database;
    final placeholders = List.filled(personIds.length, '?').join(',');
    final rows = await db.query(
      Tables.birthRecords,
      where: 'person_id IN ($placeholders)',
      whereArgs: personIds.toList(),
    );
    return {
      for (final row in rows)
        row['person_id'] as String: BirthRecord.fromMap(row),
    };
  }
}

abstract final class GrowthDao {
  /// Append-only by design. A CHO who mis-reads a tape adds a new measurement;
  /// the trajectory engine needs the series, and a clinical reading that can be
  /// quietly rewritten is not a clinical reading.
  static Future<void> insert(GrowthMeasurement m) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final map = m.toMap();
      await txn.insert(
        Tables.growthMeasurements,
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await OutboxDao.enqueue(
        txn,
        table: Tables.growthMeasurements,
        entityId: m.id,
        operation: SyncOperation.insert,
        payload: map,
        priority: SyncPriority.clinical,
      );
    });
  }

  /// Oldest first, because that is the order the trajectory engine wants and
  /// the order a growth chart is drawn in.
  static Future<List<GrowthMeasurement>> series(String personId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.growthMeasurements,
      where: 'person_id = ?',
      whereArgs: [personId],
      orderBy: 'taken_at ASC',
    );
    return rows.map(GrowthMeasurement.fromMap).toList(growable: false);
  }

  static Future<GrowthMeasurement?> latest(String personId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.growthMeasurements,
      where: 'person_id = ?',
      whereArgs: [personId],
      orderBy: 'taken_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : GrowthMeasurement.fromMap(rows.first);
  }

  /// The most recent measurement for many children at once, in a single query.
  ///
  /// The correlated subquery is there so the dashboard can rank 245 households
  /// without issuing 245 round trips on a low-end phone.
  static Future<Map<String, GrowthMeasurement>> latestForAll() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT g.* FROM ${Tables.growthMeasurements} g
      WHERE g.taken_at = (
        SELECT MAX(g2.taken_at) FROM ${Tables.growthMeasurements} g2
        WHERE g2.person_id = g.person_id
      )
      GROUP BY g.person_id
    ''');
    return {
      for (final row in rows)
        row['person_id'] as String: GrowthMeasurement.fromMap(row),
    };
  }

  /// Children whose most recent MUAC is in or near the danger zone. Powers the
  /// nutrition watchlist without loading every measurement ever taken.
  static Future<List<GrowthMeasurement>> atNutritionalRisk({
    double muacBelow = 12.5,
  }) async {
    final latest = await latestForAll();
    return latest.values
        .where(
          (m) =>
              m.hasBilateralOedema ||
              (m.muacCm != null && m.muacCm! < muacBelow),
        )
        .toList(growable: false)
      ..sort((a, b) => (a.muacCm ?? 0).compareTo(b.muacCm ?? 0));
  }
}
