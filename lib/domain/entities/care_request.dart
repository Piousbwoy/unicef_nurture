/// The one record a family chooses to send.
///
/// A home check is a clinical report and stays on the device. This is not a
/// clinical report: it says who the family is worried about, how urgent the
/// check judged it, and that they asked. `homeCheckId` is an opaque identifier
/// for a row the server cannot read — it exists so a health worker can ask the
/// family to show the check in person, which is how symptom detail is meant to
/// travel: spoken, not synced.
library;

import '../enums.dart';
import 'visit.dart';

class CareRequest {
  const CareRequest({
    required this.id,
    required this.householdId,
    required this.personId,
    required this.level,
    required this.homeCheckId,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.status = CareRequestStatus.open,
    this.answeredAt,
    this.syncState = SyncState.pending,
  });

  /// The request a completed check raises, or null when the verdict asks for
  /// nothing. One request per check, keyed on its id: `HomeCheck.id` is the
  /// draft id, which the result screen already holds, so a family tapping twice
  /// cannot create two rows.
  static CareRequest? fromCheck({
    required HomeCheck check,
    required String userId,
    required DateTime at,
  }) {
    final level = levelFor(check.verdict);
    if (level == null) return null;
    return CareRequest(
      id: 'req-${check.id}',
      householdId: check.householdId,
      personId: check.personId,
      level: level,
      homeCheckId: check.id,
      createdBy: userId,
      createdAt: at,
      updatedAt: at,
    );
  }

  static CareRequestLevel? levelFor(HomeCheckVerdict verdict) =>
      switch (verdict) {
        HomeCheckVerdict.urgent => CareRequestLevel.urgent,
        HomeCheckVerdict.caution => CareRequestLevel.today,
        HomeCheckVerdict.fine => null,
      };

  final String id;
  final String householdId;
  final String personId;
  final CareRequestLevel level;
  final String homeCheckId;
  final String createdBy;
  final DateTime createdAt;

  /// Bumped with every status change. The delta pull merges this table
  /// last-write-wins, which compares exactly this column as a string, so a
  /// request without it could never carry a worker's answer home.
  final DateTime updatedAt;

  final CareRequestStatus status;
  final DateTime? answeredAt;
  final SyncState syncState;

  bool get isOpen => status == CareRequestStatus.open;

  Map<String, Object?> toMap() => {
    'id': id,
    'household_id': householdId,
    'person_id': personId,
    'level': level.wireValue,
    'home_check_id': homeCheckId,
    'created_by': createdBy,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'status': status.wireValue,
    'answered_at': answeredAt?.toIso8601String(),
    'sync_state': syncState.name,
  };

  factory CareRequest.fromMap(Map<String, Object?> map) => CareRequest(
    id: map['id'] as String,
    householdId: map['household_id'] as String,
    personId: map['person_id'] as String,
    // Only this device writes the column, and only ever one of two values, so
    // an unreadable level is a corrupt row. The milder reading is kept rather
    // than throwing the request away: a row that fails to parse is a row the
    // family would never learn about.
    level: CareRequestLevel.fromWire(map['level'] as String) ??
        CareRequestLevel.today,
    homeCheckId: map['home_check_id'] as String,
    createdBy: map['created_by'] as String,
    createdAt: DateTime.parse(map['created_at'] as String),
    updatedAt: DateTime.parse(map['updated_at'] as String),
    status: CareRequestStatus.fromWire(map['status'] as String? ?? 'open'),
    answeredAt: map['answered_at'] == null
        ? null
        : DateTime.parse(map['answered_at'] as String),
    syncState: SyncState.values.firstWhere(
      (value) => value.name == map['sync_state'],
      orElse: () => SyncState.pending,
    ),
  );
}
