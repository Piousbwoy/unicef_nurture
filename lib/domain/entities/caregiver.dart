import 'dart:convert';
import 'visit.dart';

/// These records are local-only caregiver reports, never clinical findings.
enum CaregiverDraftKind { homeCheck, milestone }

enum CaregiverAnswer { yes, no, unsure }

enum CaregiverActivityKind {
  dailyTask,
  playSession,
  planAction,
  preparation,
  shopping,
  note,
  observation,
  arrival,
  homeCheckContext,
  milestoneContext,
}

enum CaregiverObservation { better, same, worse, unsure }

enum SupportContactKind { healthWorker, trustedPerson, transport }

/// Identity is part of every query, not a mutable global cache key.
class CaregiverScope {
  const CaregiverScope({required this.userId, required this.householdId});
  final String userId;
  final String householdId;
  @override
  bool operator ==(Object other) =>
      other is CaregiverScope &&
      other.userId == userId &&
      other.householdId == householdId;
  @override
  int get hashCode => Object.hash(userId, householdId);
}

class CaregiverDataException implements Exception {
  const CaregiverDataException(this.message);
  final String message;
  @override
  String toString() => message;
}

Map<String, Object?> _object(Object? raw) {
  try {
    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is! Map) throw const FormatException();
    return Map<String, Object?>.from(decoded);
  } catch (_) {
    throw const CaregiverDataException(
      'Saved data could not be read. No progress was restored.',
    );
  }
}

Map<String, Object?> _versioned(Object? raw) {
  final value = _object(raw);
  if (value['version'] != 1) {
    throw const CaregiverDataException(
      'This saved data uses an unsupported version.',
    );
  }
  return value;
}

T _enum<T extends Enum>(List<T> values, Object? value) =>
    values.asNameMap()[value] ??
    (throw const CaregiverDataException('Unknown saved value.'));
Set<String> _strings(Object? value) {
  if (value is! List || value.any((e) => e is! String)) {
    throw const CaregiverDataException('Saved choices could not be read.');
  }
  return Set.unmodifiable(value.cast<String>());
}

class CaregiverDraft {
  CaregiverDraft({
    required this.id,
    required this.scope,
    required this.personId,
    required this.kind,
    required this.questionVersion,
    required this.cohortKey,
    required Map<String, CaregiverAnswer> answers,
    required this.startedAt,
    required this.updatedAt,
    this.onsetNote = '',
    this.questionIndex = 0,
    List<String>? concerns,
    this.durationKey,
    Set<String> givenCare = const {},
  }) : answers = Map.unmodifiable(answers),
       // Null means "the worry screen has not been answered yet"; an empty
       // list is an explicit "no specific worry" so it is not asked twice.
       concerns = concerns == null ? null : List.unmodifiable(concerns),
       givenCare = Set.unmodifiable(givenCare);
  final String id;
  final CaregiverScope scope;
  final String personId;
  final CaregiverDraftKind kind;
  final int questionVersion;
  final String cohortKey;
  final Map<String, CaregiverAnswer> answers;
  final DateTime startedAt;
  final DateTime updatedAt;
  final String onsetNote;
  final int questionIndex;

  /// Worry chips chosen before the battery (Step 0). Null until chosen;
  /// the battery order is derived from these, so they must persist with
  /// the draft for resume.
  final List<String>? concerns;

  /// How long the signs have been present ([CaregiverDuration] key).
  final String? durationKey;

  /// What the family already tried, recorded for the nurse, never judged.
  final Set<String> givenCare;

  Map<String, Object?> toMap() => {
    'id': id,
    'user_id': scope.userId,
    'household_id': scope.householdId,
    'person_id': personId,
    'kind': kind.name,
    'question_version': questionVersion,
    'cohort_key': cohortKey,
    'content_json': jsonEncode({
      'version': 1,
      'answers': answers.map((k, v) => MapEntry(k, v.name)),
      'onset': onsetNote,
      'questionIndex': questionIndex,
      if (concerns != null) 'concerns': concerns,
      if (durationKey != null) 'duration': durationKey,
      if (givenCare.isNotEmpty) 'given': givenCare.toList()..sort(),
    }),
    'started_at': startedAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
  factory CaregiverDraft.fromMap(Map<String, Object?> row) {
    final content = _versioned(row['content_json']);
    return CaregiverDraft(
      id: row['id'] as String,
      scope: CaregiverScope(
        userId: row['user_id'] as String,
        householdId: row['household_id'] as String,
      ),
      personId: row['person_id'] as String,
      kind: _enum(CaregiverDraftKind.values, row['kind']),
      questionVersion: row['question_version'] as int,
      cohortKey: row['cohort_key'] as String,
      answers: _object(
        content['answers'],
      ).map((k, v) => MapEntry(k, _enum(CaregiverAnswer.values, v))),
      onsetNote: content['onset'] as String,
      questionIndex: content['questionIndex'] as int,
      // Older drafts predate the worry/duration/given screens; tolerate
      // their absence instead of discarding readable sessions.
      concerns: content['concerns'] == null
          ? null
          : _strings(content['concerns']).toList(),
      durationKey: content['duration'] as String?,
      givenCare: content['given'] == null
          ? const {}
          : _strings(content['given']),
      startedAt: DateTime.parse(row['started_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}

class SupportContact {
  const SupportContact({
    required this.kind,
    required this.name,
    required this.number,
    this.landmark = '',
  });
  final SupportContactKind kind;
  final String name;
  final String number;
  final String landmark;

  static bool validNumber(String number) {
    final value = number.trim();
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    return value.length <= 24 &&
        RegExp(r'^\+?[0-9][0-9 ()-]*$').hasMatch(value) &&
        digits.length >= 3 &&
        digits.length <= 15;
  }

  bool get isValid =>
      name.trim().isNotEmpty &&
      name.length <= 80 &&
      validNumber(number) &&
      landmark.length <= 160;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'name': name,
    'number': number,
    'landmark': landmark,
  };
  factory SupportContact.fromJson(Map<String, Object?> json) => SupportContact(
    kind: _enum(SupportContactKind.values, json['kind']),
    name: json['name'] as String,
    number: json['number'] as String,
    landmark: json['landmark'] as String,
  );
}

class CaregiverSettings {
  CaregiverSettings({
    required this.scope,
    required this.updatedAt,
    this.selectedPersonId,
    this.autoRead = false,
    this.lowCost = true,
    Set<String> foodsHave = const {},
    Set<String> foodsAvoid = const {},
    List<SupportContact> contacts = const [],
  }) : foodsHave = Set.unmodifiable(foodsHave),
       foodsAvoid = Set.unmodifiable(foodsAvoid),
       contacts = List.unmodifiable(contacts);
  final CaregiverScope scope;
  final DateTime updatedAt;
  final String? selectedPersonId;
  final bool autoRead;
  final bool lowCost;
  final Set<String> foodsHave;
  final Set<String> foodsAvoid;
  final List<SupportContact> contacts;

  CaregiverSettings copyWith({
    DateTime? updatedAt,
    String? selectedPersonId,
    bool allFamily = false,
    bool? autoRead,
    bool? lowCost,
    Set<String>? foodsHave,
    Set<String>? foodsAvoid,
    List<SupportContact>? contacts,
  }) => CaregiverSettings(
    scope: scope,
    updatedAt: updatedAt ?? this.updatedAt,
    selectedPersonId: allFamily
        ? null
        : selectedPersonId ?? this.selectedPersonId,
    autoRead: autoRead ?? this.autoRead,
    lowCost: lowCost ?? this.lowCost,
    foodsHave: foodsHave ?? this.foodsHave,
    foodsAvoid: foodsAvoid ?? this.foodsAvoid,
    contacts: contacts ?? this.contacts,
  );
  Map<String, Object?> toMap() => {
    'user_id': scope.userId,
    'household_id': scope.householdId,
    'content_json': jsonEncode({
      'version': 1,
      'selectedPersonId': selectedPersonId,
      'autoRead': autoRead,
      'lowCost': lowCost,
      'foodsHave': foodsHave.toList()..sort(),
      'foodsAvoid': foodsAvoid.toList()..sort(),
      'contacts': contacts.map((c) => c.toJson()).toList(),
    }),
    'updated_at': updatedAt.toIso8601String(),
  };
  factory CaregiverSettings.fromMap(Map<String, Object?> row) {
    final content = _versioned(row['content_json']);
    return CaregiverSettings(
      scope: CaregiverScope(
        userId: row['user_id'] as String,
        householdId: row['household_id'] as String,
      ),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      selectedPersonId: content['selectedPersonId'] as String?,
      autoRead: content['autoRead'] as bool,
      lowCost: content['lowCost'] as bool,
      foodsHave: _strings(content['foodsHave']),
      foodsAvoid: _strings(content['foodsAvoid']),
      contacts: (content['contacts'] as List)
          .map((c) => SupportContact.fromJson(_object(c)))
          .toList(),
    );
  }
}

class CaregiverActivity {
  static bool mayComplete(RecommendedAction action) =>
      action.isCounselling &&
      !action.isTreatment &&
      !action.isPrereferralTreatment &&
      !action.isReferral;

  CaregiverActivity({
    required this.id,
    required this.scope,
    this.personId,
    required this.kind,
    this.sourceId = '',
    required this.itemKey,
    required this.occurrenceKey,
    required this.occurredAt,
    required this.updatedAt,
    this.done = true,
    this.note = '',
    this.observation,
    Map<String, Object?> detail = const {},
  }) : detail = Map.unmodifiable(detail);
  final String id;
  final CaregiverScope scope;
  final String? personId;
  final CaregiverActivityKind kind;
  final String sourceId;
  final String itemKey;
  final String occurrenceKey;
  final DateTime occurredAt;
  final DateTime updatedAt;
  final bool done;
  final String note;
  final CaregiverObservation? observation;
  final Map<String, Object?> detail;

  bool get isImmutable => switch (kind) {
    CaregiverActivityKind.note ||
    CaregiverActivityKind.observation ||
    CaregiverActivityKind.arrival ||
    CaregiverActivityKind.homeCheckContext ||
    CaregiverActivityKind.milestoneContext => true,
    _ => false,
  };
  Map<String, Object?> toMap() => {
    'id': id,
    'user_id': scope.userId,
    'household_id': scope.householdId,
    'person_id': personId,
    'kind': kind.name,
    'source_id': sourceId,
    'item_key': itemKey,
    'occurrence_key': occurrenceKey,
    'content_json': jsonEncode({
      'version': 1,
      'done': done,
      'note': note,
      'observation': observation?.name,
      'detail': detail,
    }),
    'occurred_at': occurredAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
  factory CaregiverActivity.fromMap(Map<String, Object?> row) {
    final content = _versioned(row['content_json']);
    return CaregiverActivity(
      id: row['id'] as String,
      scope: CaregiverScope(
        userId: row['user_id'] as String,
        householdId: row['household_id'] as String,
      ),
      personId: row['person_id'] as String?,
      kind: _enum(CaregiverActivityKind.values, row['kind']),
      sourceId: row['source_id'] as String,
      itemKey: row['item_key'] as String,
      occurrenceKey: row['occurrence_key'] as String,
      occurredAt: DateTime.parse(row['occurred_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      done: content['done'] as bool,
      note: content['note'] as String,
      observation: content['observation'] == null
          ? null
          : _enum(CaregiverObservation.values, content['observation']),
      detail: _object(content['detail']),
    );
  }
}

/// Local calendar identity, unaffected by time-of-day or daylight-saving hours.
String caregiverDateKey(DateTime time) {
  final day = time.toLocal();
  return '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
}
