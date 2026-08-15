/// De-identified recalibration export — the bridge between a phone in
/// Savelugu and the Kintampo HRC / Navrongo HDSS recalibration pipeline.
///
/// Every assessment the app completes can contribute one record to the next
/// model version, but only if the record is safe to carry off the device.
/// The contract enforced here:
///
///   * **No direct identifiers.** No names, no phone numbers, no community,
///     no household id, no GPS, no exact dates. Location is the district;
///     time is the calendar month; age is a band, never a birthday.
///   * **Linkage without identity.** [personKey] is a salted SHA-256 of the
///     on-device person id, so Kintampo can link repeat visits of the same
///     child without ever learning who the child is. The salt is issued and
///     held by GHS — it is not shipped inside the app.
///   * **Model inputs only.** [features] carries the numeric inputs the
///     model actually consumed (booleans encoded as 0/1 by the caller), so a
///     record can replay the exact inference the phone saw.
///
/// Records are exported as JSONL (one [toJsonLine] per line) and leave the
/// device only with GHS approval. See `assets/models/README.md` for the
/// quarterly recalibration pathway these records feed.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// One de-identified assessment record, ready for the recalibration cohort.
class RecalibrationRecord {
  const RecalibrationRecord._({
    required this.modelName,
    required this.modelVersion,
    required this.district,
    required this.clientType,
    required this.ageBand,
    required this.createdMonth,
    required this.features,
    required this.predictedProbability,
    required this.predictedTier,
    required this.engineTriage,
    required this.finalTriage,
    required this.referralIssued,
    required this.referralUrgency,
    required this.personKey,
  });

  /// Bumped whenever the record shape changes, so the pipeline can route.
  static const int currentSchemaVersion = 1;

  /// Builds a record from primitives, deriving every de-identified field.
  ///
  /// [features] must already be numeric: booleans are encoded 0/1 by the
  /// caller, mirroring `OfflineInferenceService._inputSchemaFor`. [salt] is
  /// the GHS-issued linkage salt; [personId] never leaves this function.
  factory RecalibrationRecord.build({
    required String modelName,
    required String? modelVersion,
    required String district,
    required String clientType,
    required int? ageDays,
    required DateTime createdAt,
    required Map<String, num> features,
    required double? predictedProbability,
    required String predictedTier,
    required String engineTriage,
    required String finalTriage,
    required bool referralIssued,
    required String? referralUrgency,
    required String personId,
    required String salt,
  }) {
    return RecalibrationRecord._(
      modelName: modelName,
      modelVersion: modelVersion ?? 'unknown',
      district: district,
      clientType: clientType,
      ageBand: ageBandForDays(ageDays),
      createdMonth: monthOf(createdAt),
      features: Map<String, num>.unmodifiable(features),
      predictedProbability: predictedProbability,
      predictedTier: predictedTier,
      engineTriage: engineTriage,
      finalTriage: finalTriage,
      referralIssued: referralIssued,
      referralUrgency: referralUrgency,
      personKey: personKeyFor(personId, salt),
    );
  }

  final String modelName;
  final String modelVersion;

  /// District name only — the coarsest location that still lets Kintampo
  /// stratify calibration. Community and GPS are deliberately absent.
  final String district;

  /// `newborn` | `child` | `mother` — the client stream, not an identity.
  final String clientType;

  /// Age band label from [ageBandForDays]; exact ages are never exported.
  final String ageBand;

  /// `YYYY-MM` — month granularity keeps a single visit from identifying a
  /// family while still letting drift be tracked over time.
  final String createdMonth;

  /// The numeric model inputs (booleans as 0/1). Feature names come from the
  /// model schema, which contains no free text by construction.
  final Map<String, num> features;

  /// The calibrated probability the phone showed, or null when drift
  /// suppressed it — a null here is itself a recalibration signal.
  final double? predictedProbability;

  /// `low` | `moderate` | `high` — the model's own tier.
  final String predictedTier;

  /// What the deterministic WHO/GHS engine concluded before any override.
  final String engineTriage;

  /// What the record will say happened — the CHO's override when there was
  /// one, otherwise [engineTriage]. The gap between the two is the most
  /// valuable recalibration signal in the cohort.
  final String finalTriage;

  final bool referralIssued;

  /// Referral urgency label, or null when no referral was issued.
  final String? referralUrgency;

  /// Salted SHA-256 of the on-device person id. Stable across visits,
  /// irreversible without the GHS-held salt.
  final String personKey;

  /// Salted person linkage key: `sha256("$salt:$personId")`, hex-encoded.
  static String personKeyFor(String personId, String salt) =>
      sha256.convert(utf8.encode('$salt:$personId')).toString();

  /// `YYYY-MM` for the export month.
  static String monthOf(DateTime when) =>
      '${when.year}-${when.month.toString().padLeft(2, '0')}';

  /// Coarse age bands matching the models' operating windows. A null age
  /// exports as `unknown` rather than being guessed.
  static String ageBandForDays(int? ageDays) {
    final d = ageDays;
    if (d == null || d < 0) return 'unknown';
    if (d <= 6) return '0-6';
    if (d <= 27) return '7-27';
    if (d <= 59) return '28-59';
    if (d <= 364) return '60-364';
    if (d <= 1825) return '365-1825';
    return '1826+';
  }

  Map<String, Object?> toJson() => {
        'schemaVersion': currentSchemaVersion,
        'modelName': modelName,
        'modelVersion': modelVersion,
        'district': district,
        'clientType': clientType,
        'ageBand': ageBand,
        'createdMonth': createdMonth,
        'features': features,
        'predictedProbability': predictedProbability,
        'predictedTier': predictedTier,
        'engineTriage': engineTriage,
        'finalTriage': finalTriage,
        'referralIssued': referralIssued,
        'referralUrgency': referralUrgency,
        'personKey': personKey,
      };

  /// One JSONL line — the unit of the export file.
  String toJsonLine() => jsonEncode(toJson());
}
