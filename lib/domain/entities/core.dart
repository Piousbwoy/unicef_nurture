import '../enums.dart';

/// A CareBridge user. One device may host several users — a CHPS compound often
/// shares one Android phone across the CHO, the community health nurse and, in
/// caregiver mode, visiting mothers.
class AppUser {
  const AppUser({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.role,
    required this.region,
    required this.district,
    required this.community,
    this.chpsZone,
    this.facilityName,
    this.staffId,
    this.preferredLanguage = 'English',
    this.createdAt,
  });

  final String id;
  final String fullName;
  final String phone;
  final UserRole role;
  final String region;
  final String district;
  final String community;

  /// CHPS zones serve roughly 3,000–4,500 people. FHW only.
  final String? chpsZone;
  final String? facilityName;
  final String? staffId;

  /// Language used for audio guidance and, where translated, labels.
  final String preferredLanguage;
  final DateTime? createdAt;

  Set<Permission> get permissions => Permission.forRole(role);
  bool can(Permission p) => permissions.contains(p);

  String get initials {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'full_name': fullName,
    'phone': phone,
    'role': role.name,
    'region': region,
    'district': district,
    'community': community,
    'chps_zone': chpsZone,
    'facility_name': facilityName,
    'staff_id': staffId,
    'preferred_language': preferredLanguage,
    'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
  };

  factory AppUser.fromMap(Map<String, Object?> m) => AppUser(
    id: m['id'] as String,
    fullName: m['full_name'] as String,
    phone: m['phone'] as String,
    role: UserRole.values.firstWhere((r) => r.name == m['role']),
    region: m['region'] as String,
    district: m['district'] as String,
    community: m['community'] as String,
    chpsZone: m['chps_zone'] as String?,
    facilityName: m['facility_name'] as String?,
    staffId: m['staff_id'] as String?,
    preferredLanguage: (m['preferred_language'] as String?) ?? 'English',
    createdAt: DateTime.tryParse((m['created_at'] as String?) ?? ''),
  );

  AppUser copyWith({String? preferredLanguage, String? facilityName}) => AppUser(
    id: id,
    fullName: fullName,
    phone: phone,
    role: role,
    region: region,
    district: district,
    community: community,
    chpsZone: chpsZone,
    facilityName: facilityName ?? this.facilityName,
    staffId: staffId,
    preferredLanguage: preferredLanguage ?? this.preferredLanguage,
    createdAt: createdAt,
  );
}

/// A compound or family unit. The household — not the individual — is the unit
/// a CHO actually visits, and the unit that carries shared risk: one flooded
/// road, one empty granary, one absent decision-maker affects everyone in it.
class Household {
  const Household({
    required this.id,
    required this.name,
    required this.region,
    required this.district,
    required this.community,
    required this.createdBy,
    this.headName,
    this.contactPhone,
    this.latitude,
    this.longitude,
    this.familySize,
    this.hasValidNhis,
    this.walkingMinutesToFacility,
    this.landmark,
    this.createdAt,
    this.updatedAt,
  });

  final String id;

  /// Usually the compound head's name, e.g. "Mariama's household".
  final String name;
  final String region;
  final String district;
  final String community;
  final String createdBy;

  final String? headName;
  final String? contactPhone;
  final double? latitude;
  final double? longitude;
  final int? familySize;

  /// NHIS validity is a barrier predictor, not just an admin field.
  final bool? hasValidNhis;

  /// Walking time, because most households have no vehicle. Drives both route
  /// planning and the referral-feasibility judgement.
  final int? walkingMinutesToFacility;

  /// Free-text wayfinding — "behind the mosque, past the shea tree". GPS alone
  /// does not find a compound in a village with no addresses.
  final String? landmark;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasGps => latitude != null && longitude != null;

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'region': region,
    'district': district,
    'community': community,
    'created_by': createdBy,
    'head_name': headName,
    'contact_phone': contactPhone,
    'latitude': latitude,
    'longitude': longitude,
    'family_size': familySize,
    'has_valid_nhis': hasValidNhis == null ? null : (hasValidNhis! ? 1 : 0),
    'walking_minutes_to_facility': walkingMinutesToFacility,
    'landmark': landmark,
    'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
    'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
  };

  factory Household.fromMap(Map<String, Object?> m) => Household(
    id: m['id'] as String,
    name: m['name'] as String,
    region: m['region'] as String,
    district: m['district'] as String,
    community: m['community'] as String,
    createdBy: m['created_by'] as String,
    headName: m['head_name'] as String?,
    contactPhone: m['contact_phone'] as String?,
    latitude: (m['latitude'] as num?)?.toDouble(),
    longitude: (m['longitude'] as num?)?.toDouble(),
    familySize: (m['family_size'] as num?)?.toInt(),
    hasValidNhis: m['has_valid_nhis'] == null
        ? null
        : (m['has_valid_nhis'] as num) == 1,
    walkingMinutesToFacility: (m['walking_minutes_to_facility'] as num?)?.toInt(),
    landmark: m['landmark'] as String?,
    createdAt: DateTime.tryParse((m['created_at'] as String?) ?? ''),
    updatedAt: DateTime.tryParse((m['updated_at'] as String?) ?? ''),
  );

  Household copyWith({
    String? name,
    String? headName,
    String? contactPhone,
    double? latitude,
    double? longitude,
    int? familySize,
    bool? hasValidNhis,
    int? walkingMinutesToFacility,
    String? landmark,
  }) => Household(
    id: id,
    name: name ?? this.name,
    region: region,
    district: district,
    community: community,
    createdBy: createdBy,
    headName: headName ?? this.headName,
    contactPhone: contactPhone ?? this.contactPhone,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    familySize: familySize ?? this.familySize,
    hasValidNhis: hasValidNhis ?? this.hasValidNhis,
    walkingMinutesToFacility:
        walkingMinutesToFacility ?? this.walkingMinutesToFacility,
    landmark: landmark ?? this.landmark,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );
}

/// An individual within a household — a woman, a newborn or a child under five.
///
/// One flat person record with type-specific detail attached keeps the roll-call
/// simple: a CHO ticks who is present today, whatever their category.
class Person {
  const Person({
    required this.id,
    required this.householdId,
    required this.fullName,
    required this.clientType,
    this.sex,
    this.dateOfBirth,
    this.ageYearsApprox,
    this.phone,
    this.motherId,
    this.isDobEstimated = false,
    this.nhisNumber,
    this.createdAt,
    this.updatedAt,
    this.isActive = true,
  });

  final String id;
  final String householdId;
  final String fullName;
  final ClientType clientType;
  final Sex? sex;

  /// Exact date of birth where known. For newborns and children this is
  /// essential — every IMCI threshold is age-banded.
  final DateTime? dateOfBirth;

  /// Fallback for adults whose birth year is unknown, which is common.
  final int? ageYearsApprox;

  final String? phone;

  /// Links a newborn or child to their mother, so an assessment of the child
  /// can pull maternal history (previous loss, anaemia) into the risk picture.
  final String? motherId;

  /// Estimated dates are flagged, and any age-dependent recommendation built on
  /// one is downgraded in confidence rather than presented as certain.
  final bool isDobEstimated;

  final String? nhisNumber;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isActive;

  int? get ageInDays => dateOfBirth == null
      ? null
      : DateTime.now().difference(dateOfBirth!).inDays;

  /// Whole months, using the mean Gregorian month (30.4375 days) so that the
  /// 2-month and 59-month IMCI boundaries fall where the charts intend.
  int? get ageInMonths {
    final days = ageInDays;
    return days == null ? null : (days / 30.4375).floor();
  }

  int? get ageInYears {
    final months = ageInMonths;
    if (months != null) return months ~/ 12;
    return ageYearsApprox;
  }

  /// Human-readable age suited to a card: "3 yrs 2 mo", "18 days".
  String get ageLabel {
    final days = ageInDays;
    if (days == null) {
      return ageYearsApprox == null ? 'Age unknown' : '~$ageYearsApprox yrs';
    }
    if (days < 1) return 'Born today';
    if (days < 60) return '$days day${days == 1 ? '' : 's'}';
    final months = ageInMonths!;
    if (months < 24) return '$months month${months == 1 ? '' : 's'}';
    final years = months ~/ 12;
    final rem = months % 12;
    return rem == 0 ? '$years yrs' : '$years yrs $rem mo';
  }

  /// Re-derives the client type from the current age. A newborn registered six
  /// weeks ago crosses into the IMCI child protocol on its own; the app must
  /// follow the child, not the label it was given at registration.
  ClientType get effectiveClientType {
    final days = ageInDays;
    if (days == null) return clientType;
    if (clientType == ClientType.newborn || clientType == ClientType.childUnderFive) {
      return ClientType.forChildAgeInDays(days) ?? clientType;
    }
    return clientType;
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'household_id': householdId,
    'full_name': fullName,
    'client_type': clientType.name,
    'sex': sex?.name,
    'date_of_birth': dateOfBirth?.toIso8601String(),
    'age_years_approx': ageYearsApprox,
    'phone': phone,
    'mother_id': motherId,
    'is_dob_estimated': isDobEstimated ? 1 : 0,
    'nhis_number': nhisNumber,
    'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
    'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
    'is_active': isActive ? 1 : 0,
  };

  factory Person.fromMap(Map<String, Object?> m) => Person(
    id: m['id'] as String,
    householdId: m['household_id'] as String,
    fullName: m['full_name'] as String,
    clientType: ClientType.values.firstWhere((c) => c.name == m['client_type']),
    sex: m['sex'] == null
        ? null
        : Sex.values.firstWhere((s) => s.name == m['sex']),
    dateOfBirth: DateTime.tryParse((m['date_of_birth'] as String?) ?? ''),
    ageYearsApprox: (m['age_years_approx'] as num?)?.toInt(),
    phone: m['phone'] as String?,
    motherId: m['mother_id'] as String?,
    isDobEstimated: (m['is_dob_estimated'] as num?) == 1,
    nhisNumber: m['nhis_number'] as String?,
    createdAt: DateTime.tryParse((m['created_at'] as String?) ?? ''),
    updatedAt: DateTime.tryParse((m['updated_at'] as String?) ?? ''),
    isActive: (m['is_active'] as num?) != 0,
  );

  Person copyWith({
    String? fullName,
    ClientType? clientType,
    Sex? sex,
    DateTime? dateOfBirth,
    String? motherId,
    bool? isActive,
    String? nhisNumber,
  }) => Person(
    id: id,
    householdId: householdId,
    fullName: fullName ?? this.fullName,
    clientType: clientType ?? this.clientType,
    sex: sex ?? this.sex,
    dateOfBirth: dateOfBirth ?? this.dateOfBirth,
    ageYearsApprox: ageYearsApprox,
    phone: phone,
    motherId: motherId ?? this.motherId,
    isDobEstimated: isDobEstimated,
    nhisNumber: nhisNumber ?? this.nhisNumber,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
    isActive: isActive ?? this.isActive,
  );
}

/// Obstetric and pregnancy record for a woman. Mirrors the fields in Ghana's
/// Maternal Health Record Book so a CHO can transcribe without translating.
class MaternalRecord {
  const MaternalRecord({
    required this.personId,
    this.gravida,
    this.parity,
    this.previousLosses,
    this.previousCaesarean,
    this.lastMenstrualPeriod,
    this.expectedDeliveryDate,
    this.ancContactsCompleted = 0,
    this.iptpDoses = 0,
    this.tdDoses = 0,
    this.ironFolateSupplied = false,
    this.llinSupplied = false,
    this.haemoglobin,
    this.bloodGroup,
    this.sicklingStatus,
    this.hivTested = false,
    this.deliveryDate,
    this.deliveryPlace,
    this.deliveryMode,
    this.plurality = BirthPlurality.singleton,
    this.familyPlanningMethod,
    this.updatedAt,
  });

  final String personId;

  /// Total pregnancies including this one.
  final int? gravida;

  /// Births after 28 weeks.
  final int? parity;

  /// Miscarriages, stillbirths and neonatal deaths. A strong predictor of the
  /// next outcome, and the reason it is captured explicitly.
  final int? previousLosses;

  final bool? previousCaesarean;
  final DateTime? lastMenstrualPeriod;
  final DateTime? expectedDeliveryDate;

  /// WHO's 2016 ANC model calls for eight contacts. Ghana has adopted it.
  final int ancContactsCompleted;

  /// IPTp-SP for malaria: from 16 weeks, at each contact, at least three doses.
  final int iptpDoses;

  /// Tetanus-diphtheria doses.
  final int tdDoses;

  final bool ironFolateSupplied;
  final bool llinSupplied;

  /// Haemoglobin in g/dL. <11 anaemia, 7–9.9 moderate, <7 severe.
  final double? haemoglobin;

  final String? bloodGroup;
  final String? sicklingStatus;
  final bool hivTested;

  final DateTime? deliveryDate;
  final DeliveryPlace? deliveryPlace;
  final DeliveryMode? deliveryMode;
  final BirthPlurality plurality;
  final String? familyPlanningMethod;
  final DateTime? updatedAt;

  /// Gestational age in completed weeks, from LMP where available, otherwise
  /// back-calculated from the EDD.
  int? get gestationalWeeks {
    if (lastMenstrualPeriod != null) {
      final days = DateTime.now().difference(lastMenstrualPeriod!).inDays;
      if (days < 0 || days > 320) return null;
      return days ~/ 7;
    }
    if (expectedDeliveryDate != null) {
      final daysToEdd = expectedDeliveryDate!.difference(DateTime.now()).inDays;
      final weeks = 40 - (daysToEdd / 7).round();
      if (weeks < 0 || weeks > 45) return null;
      return weeks;
    }
    return null;
  }

  /// Naegele's rule: EDD = LMP + 280 days.
  DateTime? get derivedEdd => lastMenstrualPeriod?.add(const Duration(days: 280));

  /// Days since delivery, used to decide which PNC contact is due.
  int? get postpartumDays => deliveryDate == null
      ? null
      : DateTime.now().difference(deliveryDate!).inDays;

  /// The postpartum period runs to 42 days.
  bool get isPostpartum {
    final d = postpartumDays;
    return d != null && d >= 0 && d <= 42;
  }

  Map<String, Object?> toMap() => {
    'person_id': personId,
    'gravida': gravida,
    'parity': parity,
    'previous_losses': previousLosses,
    'previous_caesarean': previousCaesarean == null
        ? null
        : (previousCaesarean! ? 1 : 0),
    'last_menstrual_period': lastMenstrualPeriod?.toIso8601String(),
    'expected_delivery_date': expectedDeliveryDate?.toIso8601String(),
    'anc_contacts_completed': ancContactsCompleted,
    'iptp_doses': iptpDoses,
    'td_doses': tdDoses,
    'iron_folate_supplied': ironFolateSupplied ? 1 : 0,
    'llin_supplied': llinSupplied ? 1 : 0,
    'haemoglobin': haemoglobin,
    'blood_group': bloodGroup,
    'sickling_status': sicklingStatus,
    'hiv_tested': hivTested ? 1 : 0,
    'delivery_date': deliveryDate?.toIso8601String(),
    'delivery_place': deliveryPlace?.name,
    'delivery_mode': deliveryMode?.name,
    'plurality': plurality.name,
    'family_planning_method': familyPlanningMethod,
    'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
  };

  factory MaternalRecord.fromMap(Map<String, Object?> m) => MaternalRecord(
    personId: m['person_id'] as String,
    gravida: (m['gravida'] as num?)?.toInt(),
    parity: (m['parity'] as num?)?.toInt(),
    previousLosses: (m['previous_losses'] as num?)?.toInt(),
    previousCaesarean: m['previous_caesarean'] == null
        ? null
        : (m['previous_caesarean'] as num) == 1,
    lastMenstrualPeriod: DateTime.tryParse(
      (m['last_menstrual_period'] as String?) ?? '',
    ),
    expectedDeliveryDate: DateTime.tryParse(
      (m['expected_delivery_date'] as String?) ?? '',
    ),
    ancContactsCompleted: (m['anc_contacts_completed'] as num?)?.toInt() ?? 0,
    iptpDoses: (m['iptp_doses'] as num?)?.toInt() ?? 0,
    tdDoses: (m['td_doses'] as num?)?.toInt() ?? 0,
    ironFolateSupplied: (m['iron_folate_supplied'] as num?) == 1,
    llinSupplied: (m['llin_supplied'] as num?) == 1,
    haemoglobin: (m['haemoglobin'] as num?)?.toDouble(),
    bloodGroup: m['blood_group'] as String?,
    sicklingStatus: m['sickling_status'] as String?,
    hivTested: (m['hiv_tested'] as num?) == 1,
    deliveryDate: DateTime.tryParse((m['delivery_date'] as String?) ?? ''),
    deliveryPlace: m['delivery_place'] == null
        ? null
        : DeliveryPlace.values.firstWhere((d) => d.name == m['delivery_place']),
    deliveryMode: m['delivery_mode'] == null
        ? null
        : DeliveryMode.values.firstWhere((d) => d.name == m['delivery_mode']),
    plurality: BirthPlurality.values.firstWhere(
      (p) => p.name == m['plurality'],
      orElse: () => BirthPlurality.singleton,
    ),
    familyPlanningMethod: m['family_planning_method'] as String?,
    updatedAt: DateTime.tryParse((m['updated_at'] as String?) ?? ''),
  );
}

/// Birth details for a newborn. Separated from [Person] because these facts are
/// fixed at birth and drive the young-infant risk model for the first 59 days.
class BirthRecord {
  const BirthRecord({
    required this.personId,
    this.birthWeightKg,
    this.gestationWeeksAtBirth,
    this.deliveryPlace,
    this.deliveryMode,
    this.plurality = BirthPlurality.singleton,
    this.birthOrder = 1,
    this.resuscitationNeeded,
    this.cordCareGiven,
    this.vitaminKGiven,
    this.breastfedWithinOneHour,
    this.updatedAt,
  });

  final String personId;

  /// <2.5 kg is low birth weight; <1.5 kg very low. The strongest single
  /// predictor of neonatal death in this setting.
  final double? birthWeightKg;

  final int? gestationWeeksAtBirth;
  final DeliveryPlace? deliveryPlace;
  final DeliveryMode? deliveryMode;
  final BirthPlurality plurality;

  /// 1 for a singleton or first twin, 2 for the second twin, and so on.
  final int birthOrder;

  /// Birth asphyxia is the leading cause of neonatal death in the Upper East.
  final bool? resuscitationNeeded;

  final bool? cordCareGiven;
  final bool? vitaminKGiven;
  final bool? breastfedWithinOneHour;
  final DateTime? updatedAt;

  bool get isLowBirthWeight =>
      birthWeightKg != null && birthWeightKg! < 2.5;
  bool get isVeryLowBirthWeight =>
      birthWeightKg != null && birthWeightKg! < 1.5;
  bool get isPreterm =>
      gestationWeeksAtBirth != null && gestationWeeksAtBirth! < 37;
  bool get isMultiple => plurality != BirthPlurality.singleton;

  Map<String, Object?> toMap() => {
    'person_id': personId,
    'birth_weight_kg': birthWeightKg,
    'gestation_weeks_at_birth': gestationWeeksAtBirth,
    'delivery_place': deliveryPlace?.name,
    'delivery_mode': deliveryMode?.name,
    'plurality': plurality.name,
    'birth_order': birthOrder,
    'resuscitation_needed': resuscitationNeeded == null
        ? null
        : (resuscitationNeeded! ? 1 : 0),
    'cord_care_given': cordCareGiven == null ? null : (cordCareGiven! ? 1 : 0),
    'vitamin_k_given': vitaminKGiven == null ? null : (vitaminKGiven! ? 1 : 0),
    'breastfed_within_one_hour': breastfedWithinOneHour == null
        ? null
        : (breastfedWithinOneHour! ? 1 : 0),
    'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
  };

  factory BirthRecord.fromMap(Map<String, Object?> m) => BirthRecord(
    personId: m['person_id'] as String,
    birthWeightKg: (m['birth_weight_kg'] as num?)?.toDouble(),
    gestationWeeksAtBirth: (m['gestation_weeks_at_birth'] as num?)?.toInt(),
    deliveryPlace: m['delivery_place'] == null
        ? null
        : DeliveryPlace.values.firstWhere((d) => d.name == m['delivery_place']),
    deliveryMode: m['delivery_mode'] == null
        ? null
        : DeliveryMode.values.firstWhere((d) => d.name == m['delivery_mode']),
    plurality: BirthPlurality.values.firstWhere(
      (p) => p.name == m['plurality'],
      orElse: () => BirthPlurality.singleton,
    ),
    birthOrder: (m['birth_order'] as num?)?.toInt() ?? 1,
    resuscitationNeeded: m['resuscitation_needed'] == null
        ? null
        : (m['resuscitation_needed'] as num) == 1,
    cordCareGiven: m['cord_care_given'] == null
        ? null
        : (m['cord_care_given'] as num) == 1,
    vitaminKGiven: m['vitamin_k_given'] == null
        ? null
        : (m['vitamin_k_given'] as num) == 1,
    breastfedWithinOneHour: m['breastfed_within_one_hour'] == null
        ? null
        : (m['breastfed_within_one_hour'] as num) == 1,
    updatedAt: DateTime.tryParse((m['updated_at'] as String?) ?? ''),
  );
}

/// One anthropometric measurement in time. Stored as a series, not a snapshot,
/// because the *slope* is what detects a child sliding toward malnutrition
/// while every individual reading still reads "yellow".
class GrowthMeasurement {
  const GrowthMeasurement({
    required this.id,
    required this.personId,
    required this.takenAt,
    this.muacCm,
    this.weightKg,
    this.heightCm,
    this.hasBilateralOedema = false,
    this.recordedBy,
  });

  final String id;
  final String personId;
  final DateTime takenAt;

  /// Mid-upper arm circumference, 6–59 months. SAM <11.5, MAM 11.5–12.5.
  final double? muacCm;

  final double? weightKg;
  final double? heightCm;

  /// Bilateral pitting oedema means SAM regardless of MUAC. Never ignore it.
  final bool hasBilateralOedema;

  final String? recordedBy;

  Map<String, Object?> toMap() => {
    'id': id,
    'person_id': personId,
    'taken_at': takenAt.toIso8601String(),
    'muac_cm': muacCm,
    'weight_kg': weightKg,
    'height_cm': heightCm,
    'has_bilateral_oedema': hasBilateralOedema ? 1 : 0,
    'recorded_by': recordedBy,
  };

  factory GrowthMeasurement.fromMap(Map<String, Object?> m) => GrowthMeasurement(
    id: m['id'] as String,
    personId: m['person_id'] as String,
    takenAt: DateTime.parse(m['taken_at'] as String),
    muacCm: (m['muac_cm'] as num?)?.toDouble(),
    weightKg: (m['weight_kg'] as num?)?.toDouble(),
    heightCm: (m['height_cm'] as num?)?.toDouble(),
    hasBilateralOedema: (m['has_bilateral_oedema'] as num?) == 1,
    recordedBy: m['recorded_by'] as String?,
  );
}
