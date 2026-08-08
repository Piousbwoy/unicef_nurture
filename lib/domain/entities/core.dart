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
/// Maternal Health Record Book (JICA/GHS national rollout since 2018,
/// 1,000,000+ copies printed/year by NHIA + Birth & Deaths Registry) so a
/// CHO transcribes without translating.
///
/// Expanded August 2026 against the actual paper form field list:
///   • Blood group + Rhesus (MCH RB p. 5, ANC contact 1)
///   • Urinalysis strips: protein, glucose, ketones, blood (MCH RB p. 7)
///   • HBsAg (hepatitis B surface antigen), HSV screening, syphilis RST
///     dates (MCH RB p. 5, ANC contact 1 and 6)
///   • Sickle-cell genotype (HbAA / HbAS / HbSS / HbSC / other trait) —
///     clinically mandatory in the Northern Region where 15-20% of the
///     population carries a sickle-cell allele (Kintampo HRC data 2023)
///   • Urine glucose + ketones + blood alongside protein (GHS ANC 2024)
///   • Pre-eclampsia extras: epigastric pain, hand/face oedema, brisk
///     reflexes, oliguria, weight gain >1 kg/wk (MCH RB pre-eclampsia box)
///   • Previous medical history flags (anaemia, HTN, DM, TB, asthma, heart)
///   • Edinburgh Postnatal Depression Scale 10-item score (PNC days 7, 42)
///   • Puerperal: uterine involution in cm, lochia (colour/odour/amount),
///     episiotomy/Caesarean wound, breastfeeding exam (MCH RB pp. 25–26)
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
    this.rhesusPositive,
    this.sicklingStatus,
    this.sickleGenotype,
    this.hivTested = false,
    this.hivTestDate,
    this.syphilisTested = false,
    this.syphilisTestDate,
    this.hbsagTested = false,
    this.hbsagTestDate,
    this.deliveryDate,
    this.deliveryPlace,
    this.deliveryMode,
    this.plurality = BirthPlurality.singleton,
    this.familyPlanningMethod,
    // ── Urinalysis strips (ANC each contact) ────────────────────────────
    this.urineProtein, // 0/1/2/3/4
    this.urineGlucose, // 0/1/2/3/4
    this.urineKetones, // 0/1/2/3
    this.urineBlood,   // 0/1/2/3
    // ── Pre-eclampsia extras ────────────────────────────────────────────
    this.oedemaHandsOrFace = false,
    this.epigastricPain = false,
    this.headacheSevere = false,
    this.blurredVision = false,
    this.briskReflexes = false,
    this.oliguria = false,
    this.weightGainOver1kgPerWeek = false,
    // ── Previous medical history ────────────────────────────────────────
    this.prevHypertension = false,
    this.prevDiabetes = false,
    this.prevAnaemia = false,
    this.prevTb = false,
    this.prevAsthma = false,
    this.prevHeartDisease = false,
    this.prevKidneyDisease = false,
    this.prevHepatitis = false,
    // ── Puerperal / PNC fields (days 1 / 3 / 7 / 42) ────────────────────
    this.involutionCmBelowUmbilicus,
    this.lochiaColour, // rubra / serosa / alba
    this.lochiaOdour,   // normal / offensive
    this.lochiaAmount,  // light / normal / heavy
    this.woundRedness = false,
    this.woundOedema = false,
    this.woundDischarge = false,
    this.woundApproximated,
    this.episiotomyOrLaceration = false,
    this.nipplesCracked = false,
    this.nipplesInverted = false,
    this.breastMastitisSigns = false,
    this.breastAttachmentOk,
    this.breastLetDownOk,
    // ── Edinburgh EPDS 10 items (0..3 each, 0..30 total) ────────────────
    this.edinburghLaugh,
    this.edinburghEnjoy,
    this.edinburghBlame,
    this.edinburghAnxious,
    this.edinburghScared,
    this.edinburghOverwhelm,
    this.edinburghSleep,
    this.edinburghSad,
    this.edinburghCry,
    this.edinburghSelfHarm,
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

  final String? bloodGroup; // A/B/AB/O
  final bool? rhesusPositive; // null = not typed, true = Rh+, false = Rh-
  final String? sicklingStatus; // positive/negative/unknown/untested
  final String? sickleGenotype; // HbAA, HbAS, HbSS, HbSC, HbF (newborn), other

  final bool hivTested;
  final DateTime? hivTestDate;
  final bool syphilisTested;
  final DateTime? syphilisTestDate;
  final bool hbsagTested;
  final DateTime? hbsagTestDate;

  final DateTime? deliveryDate;
  final DeliveryPlace? deliveryPlace;
  final DeliveryMode? deliveryMode;
  final BirthPlurality plurality;
  final String? familyPlanningMethod;

  // Urinalysis strip readings. Values mirror a standard Multistix 10 SG:
  // glucose (neg/trace=0, 1+, 2+, 3+, 4+), ketones 0..3, blood 0..3,
  // protein already captured separately as 0..4 in the existing
  // PregnancyInput (but replicated here for persistence in entity records).
  final int? urineProtein;
  final int? urineGlucose;
  final int? urineKetones;
  final int? urineBlood;

  // Pre-eclampsia / imminent eclampsia red flags.
  final bool oedemaHandsOrFace;
  final bool epigastricPain;
  final bool headacheSevere;
  final bool blurredVision;
  final bool briskReflexes;
  final bool oliguria;
  final bool weightGainOver1kgPerWeek;

  // Previous medical history — important for risk stratification.
  final bool prevHypertension;
  final bool prevDiabetes;
  final bool prevAnaemia;
  final bool prevTb;
  final bool prevAsthma;
  final bool prevHeartDisease;
  final bool prevKidneyDisease;
  final bool prevHepatitis;

  // Puerperal (PNC 1/3/7/42 day checks)
  final int? involutionCmBelowUmbilicus; // day1 = 1-2, day7 = 4-5, day42 = non-palp
  final String? lochiaColour;   // 'rubra' / 'serosa' / 'alba'
  final String? lochiaOdour;    // 'normal' / 'offensive'
  final String? lochiaAmount;   // 'light'/'normal'/'heavy'
  // Breast / wound / perineum
  final bool woundRedness;
  final bool woundOedema;
  final bool woundDischarge;
  final bool? woundApproximated;
  final bool episiotomyOrLaceration;
  final bool nipplesCracked;
  final bool nipplesInverted;
  final bool breastMastitisSigns;
  final bool? breastAttachmentOk;
  final bool? breastLetDownOk;

  // Edinburgh EPDS 10-item answers. Each 0..3. Range 0..30.
  //   ≥13 = probable depression. ≥20 = severe.
  //   Item 10 ≥1 = immediate self-harm referral.
  final int? edinburghLaugh;   // Q1: been able to laugh and see the funny side
  final int? edinburghEnjoy;   // Q2: looked forward with enjoyment
  final int? edinburghBlame;   // Q3: blamed myself unnecessarily
  final int? edinburghAnxious; // Q4: anxious or worried for no good reason
  final int? edinburghScared;  // Q5: felt scared or panicky for no reason
  final int? edinburghOverwhelm;// Q6: things been getting on top of me
  final int? edinburghSleep;   // Q7: difficult to sleep properly
  final int? edinburghSad;     // Q8: felt sad/miserable
  final int? edinburghCry;     // Q9: been so unhappy that I have been crying
  final int? edinburghSelfHarm;// Q10: thought of harming myself

  final DateTime? updatedAt;

  /// Computed Edinburgh EPDS score. Returns null when any item is missing.
  int? get edinburghScore {
    final items = [
      edinburghLaugh, edinburghEnjoy, edinburghBlame,
      edinburghAnxious, edinburghScared, edinburghOverwhelm,
      edinburghSleep, edinburghSad, edinburghCry, edinburghSelfHarm,
    ];
    if (items.any((v) => v == null)) return null;
    return items.fold<int>(0, (a, b) => a + (b ?? 0));
  }

  /// Returns true if a red flag item (self-harm, Q10 ≥ 1) has been affirmed.
  /// Requires immediate psychosocial or mental-health referral regardless of
  /// the overall score (Edinburgh manual, 2003).
  bool get edinburghSelfHarmFlag => (edinburghSelfHarm ?? 0) >= 1;

  /// Severe = score ≥20 OR self-harm ideation (any).
  bool get edinburghSevere {
    final s = edinburghScore;
    return (s != null && s >= 20) || edinburghSelfHarmFlag;
  }

  /// Probable postnatal depression (≥13).
  bool get edinburghProbablePnd {
    final s = edinburghScore;
    return s != null && s >= 13;
  }

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
    'rhesus_positive': rhesusPositive == null
        ? null
        : (rhesusPositive! ? 1 : 0),
    'sickling_status': sicklingStatus,
    'sickle_genotype': sickleGenotype,
    'hiv_tested': hivTested ? 1 : 0,
    'hiv_test_date': hivTestDate?.toIso8601String(),
    'syphilis_tested': syphilisTested ? 1 : 0,
    'syphilis_test_date': syphilisTestDate?.toIso8601String(),
    'hbsag_tested': hbsagTested ? 1 : 0,
    'hbsag_test_date': hbsagTestDate?.toIso8601String(),
    'delivery_date': deliveryDate?.toIso8601String(),
    'delivery_place': deliveryPlace?.name,
    'delivery_mode': deliveryMode?.name,
    'plurality': plurality.name,
    'family_planning_method': familyPlanningMethod,
    'urine_protein': urineProtein,
    'urine_glucose': urineGlucose,
    'urine_ketones': urineKetones,
    'urine_blood': urineBlood,
    'oedema_hands_or_face': oedemaHandsOrFace ? 1 : 0,
    'epigastric_pain': epigastricPain ? 1 : 0,
    'headache_severe': headacheSevere ? 1 : 0,
    'blurred_vision': blurredVision ? 1 : 0,
    'brisk_reflexes': briskReflexes ? 1 : 0,
    'oliguria': oliguria ? 1 : 0,
    'weight_gain_over_1kg_per_week': weightGainOver1kgPerWeek ? 1 : 0,
    'prev_hypertension': prevHypertension ? 1 : 0,
    'prev_diabetes': prevDiabetes ? 1 : 0,
    'prev_anaemia': prevAnaemia ? 1 : 0,
    'prev_tb': prevTb ? 1 : 0,
    'prev_asthma': prevAsthma ? 1 : 0,
    'prev_heart_disease': prevHeartDisease ? 1 : 0,
    'prev_kidney_disease': prevKidneyDisease ? 1 : 0,
    'prev_hepatitis': prevHepatitis ? 1 : 0,
    'involution_cm_below_umbilicus': involutionCmBelowUmbilicus,
    'lochia_colour': lochiaColour,
    'lochia_odour': lochiaOdour,
    'lochia_amount': lochiaAmount,
    'wound_redness': woundRedness ? 1 : 0,
    'wound_oedema': woundOedema ? 1 : 0,
    'wound_discharge': woundDischarge ? 1 : 0,
    'wound_approximated': woundApproximated == null
        ? null
        : (woundApproximated! ? 1 : 0),
    'episiotomy_or_laceration': episiotomyOrLaceration ? 1 : 0,
    'nipples_cracked': nipplesCracked ? 1 : 0,
    'nipples_inverted': nipplesInverted ? 1 : 0,
    'breast_mastitis_signs': breastMastitisSigns ? 1 : 0,
    'breast_attachment_ok': breastAttachmentOk == null
        ? null
        : (breastAttachmentOk! ? 1 : 0),
    'breast_let_down_ok': breastLetDownOk == null
        ? null
        : (breastLetDownOk! ? 1 : 0),
    'edinburgh_laugh': edinburghLaugh,
    'edinburgh_enjoy': edinburghEnjoy,
    'edinburgh_blame': edinburghBlame,
    'edinburgh_anxious': edinburghAnxious,
    'edinburgh_scared': edinburghScared,
    'edinburgh_overwhelm': edinburghOverwhelm,
    'edinburgh_sleep': edinburghSleep,
    'edinburgh_sad': edinburghSad,
    'edinburgh_cry': edinburghCry,
    'edinburgh_self_harm': edinburghSelfHarm,
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
    rhesusPositive: m['rhesus_positive'] == null
        ? null
        : (m['rhesus_positive'] as num) == 1,
    sicklingStatus: m['sickling_status'] as String?,
    sickleGenotype: m['sickle_genotype'] as String?,
    hivTested: (m['hiv_tested'] as num?) == 1,
    hivTestDate: DateTime.tryParse(
      (m['hiv_test_date'] as String?) ?? '',
    ),
    syphilisTested: (m['syphilis_tested'] as num?) == 1,
    syphilisTestDate: DateTime.tryParse(
      (m['syphilis_test_date'] as String?) ?? '',
    ),
    hbsagTested: (m['hbsag_tested'] as num?) == 1,
    hbsagTestDate: DateTime.tryParse(
      (m['hbsag_test_date'] as String?) ?? '',
    ),
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
    urineProtein: (m['urine_protein'] as num?)?.toInt(),
    urineGlucose: (m['urine_glucose'] as num?)?.toInt(),
    urineKetones: (m['urine_ketones'] as num?)?.toInt(),
    urineBlood: (m['urine_blood'] as num?)?.toInt(),
    oedemaHandsOrFace: (m['oedema_hands_or_face'] as num?) == 1,
    epigastricPain: (m['epigastric_pain'] as num?) == 1,
    headacheSevere: (m['headache_severe'] as num?) == 1,
    blurredVision: (m['blurred_vision'] as num?) == 1,
    briskReflexes: (m['brisk_reflexes'] as num?) == 1,
    oliguria: (m['oliguria'] as num?) == 1,
    weightGainOver1kgPerWeek:
        (m['weight_gain_over_1kg_per_week'] as num?) == 1,
    prevHypertension: (m['prev_hypertension'] as num?) == 1,
    prevDiabetes: (m['prev_diabetes'] as num?) == 1,
    prevAnaemia: (m['prev_anaemia'] as num?) == 1,
    prevTb: (m['prev_tb'] as num?) == 1,
    prevAsthma: (m['prev_asthma'] as num?) == 1,
    prevHeartDisease: (m['prev_heart_disease'] as num?) == 1,
    prevKidneyDisease: (m['prev_kidney_disease'] as num?) == 1,
    prevHepatitis: (m['prev_hepatitis'] as num?) == 1,
    involutionCmBelowUmbilicus:
        (m['involution_cm_below_umbilicus'] as num?)?.toInt(),
    lochiaColour: m['lochia_colour'] as String?,
    lochiaOdour: m['lochia_odour'] as String?,
    lochiaAmount: m['lochia_amount'] as String?,
    woundRedness: (m['wound_redness'] as num?) == 1,
    woundOedema: (m['wound_oedema'] as num?) == 1,
    woundDischarge: (m['wound_discharge'] as num?) == 1,
    woundApproximated: m['wound_approximated'] == null
        ? null
        : (m['wound_approximated'] as num) == 1,
    episiotomyOrLaceration:
        (m['episiotomy_or_laceration'] as num?) == 1,
    nipplesCracked: (m['nipples_cracked'] as num?) == 1,
    nipplesInverted: (m['nipples_inverted'] as num?) == 1,
    breastMastitisSigns: (m['breast_mastitis_signs'] as num?) == 1,
    breastAttachmentOk: m['breast_attachment_ok'] == null
        ? null
        : (m['breast_attachment_ok'] as num) == 1,
    breastLetDownOk: m['breast_let_down_ok'] == null
        ? null
        : (m['breast_let_down_ok'] as num) == 1,
    edinburghLaugh: (m['edinburgh_laugh'] as num?)?.toInt(),
    edinburghEnjoy: (m['edinburgh_enjoy'] as num?)?.toInt(),
    edinburghBlame: (m['edinburgh_blame'] as num?)?.toInt(),
    edinburghAnxious: (m['edinburgh_anxious'] as num?)?.toInt(),
    edinburghScared: (m['edinburgh_scared'] as num?)?.toInt(),
    edinburghOverwhelm: (m['edinburgh_overwhelm'] as num?)?.toInt(),
    edinburghSleep: (m['edinburgh_sleep'] as num?)?.toInt(),
    edinburghSad: (m['edinburgh_sad'] as num?)?.toInt(),
    edinburghCry: (m['edinburgh_cry'] as num?)?.toInt(),
    edinburghSelfHarm: (m['edinburgh_self_harm'] as num?)?.toInt(),
    updatedAt: DateTime.tryParse((m['updated_at'] as String?) ?? ''),
  );
}

/// Birth details for a newborn. Separated from [Person] because these facts are
/// fixed at birth and drive the young-infant risk model for the first 59 days.
///
/// Expanded against WHO Young-Infant IMCI 0–59 day danger signs and Ghana CHPS
/// newborn examination checklist (Kintampo HRC newborn home-visit package 2023).
class BirthRecord {
  const BirthRecord({
    required this.personId,
    this.birthWeightKg,
    this.birthLengthCm,
    this.gestationWeeksAtBirth,
    this.deliveryPlace,
    this.deliveryMode,
    this.plurality = BirthPlurality.singleton,
    this.birthOrder = 1,
    this.resuscitationNeeded,
    this.apgar1Minute,
    this.apgar5Minute,
    this.cordCareGiven,
    this.cordChlorhexidineApplied,
    this.vitaminKGiven,
    this.vitaminKDoseMg = 1,
    this.breastfedWithinOneHour,
    this.breastfeedingOkOnDay1,
    this.temperatureCelsius,
    this.respiratoryRatePerMin,
    this.heartRatePerMin,
    this.oxygenSaturationPerCent,
    // ── Neonatal danger signs (Young-Infant IMCI 0–59d) ────────────────────
    this.historyOfConvulsions = false,
    this.severeChestIndrawing = false,
    this.nasalFlaring = false,
    this.grunting = false,
    this.bulgingFontanelle = false,
    this.jaundiceBefore24h = false,
    this.jaundiceOnDay3OrLater,
    this.feedingDifficulty = false,
    this.abdominalDistension = false,
    this.cordRednessBeyondBase = false,
    this.cordPus = false,
    this.cordOedemaBeyondBase = false,
    this.skinPustules = false,
    this.lethargicOrUnconscious = false,
    this.bleedingFromAnySite = false,
    // ── KMC (Kangaroo Mother Care) ────────────────────────────────────────
    this.kmcEligible = false,
    this.kmcInitiated,
    this.kmcSite,
    this.kmcHoursPerDay,
    // ── Newborn screening ─────────────────────────────────────────────────
    this.sickleScreenSampleCollected,
    this.sickleScreenSampleDate,
    this.hearingScreenDone,
    this.hearingScreenResult,
    this.updatedAt,
  });

  final String personId;

  /// <2.5 kg is low birth weight; <1.5 kg very low. The strongest single
  /// predictor of neonatal death in this setting.
  final double? birthWeightKg;

  /// Birth length in cm, for SGA screening.
  final double? birthLengthCm;

  final int? gestationWeeksAtBirth;
  final DeliveryPlace? deliveryPlace;
  final DeliveryMode? deliveryMode;
  final BirthPlurality plurality;

  /// 1 for a singleton or first twin, 2 for the second twin, and so on.
  final int birthOrder;

  /// Birth asphyxia is the leading cause of neonatal death in the Upper East.
  final bool? resuscitationNeeded;
  final int? apgar1Minute;
  final int? apgar5Minute;

  final bool? cordCareGiven;
  final bool? cordChlorhexidineApplied;
  final bool? vitaminKGiven;

  /// Standard dose = 1 mg IM. 0.5 mg for <1500 g newborns.
  final double vitaminKDoseMg;

  final bool? breastfedWithinOneHour;
  final bool? breastfeedingOkOnDay1;

  /// Measured axillary; >37.5 fever, <35.5 hypothermia (both urgent).
  final double? temperatureCelsius;
  final int? respiratoryRatePerMin;
  final int? heartRatePerMin;
  final int? oxygenSaturationPerCent;

  // Young-Infant IMCI 0–59 day danger signs — any one = POSSIBLE SEVERE
  // BACTERIAL INFECTION (PSBI) → urgent referral.
  final bool historyOfConvulsions;
  final bool severeChestIndrawing;
  final bool nasalFlaring;
  final bool grunting;
  final bool bulgingFontanelle;
  final bool jaundiceBefore24h;
  final String? jaundiceOnDay3OrLater; // none / face+trunk / palms+soles
  final bool feedingDifficulty;
  final bool abdominalDistension;
  final bool cordRednessBeyondBase;
  final bool cordPus;
  final bool cordOedemaBeyondBase;
  final bool skinPustules;
  final bool lethargicOrUnconscious;
  final bool bleedingFromAnySite;

  // KMC (Kangaroo Mother Care) — LBW newborns, Northern Region priority.
  final bool kmcEligible;
  final bool? kmcInitiated;
  final String? kmcSite; // CHPS / hospital / home
  final double? kmcHoursPerDay;

  // Newborn screening (GHS national rollout of sickle + hearing 2024).
  final bool? sickleScreenSampleCollected;
  final DateTime? sickleScreenSampleDate;
  final bool? hearingScreenDone;
  final String? hearingScreenResult; // pass / refer / rescreen

  final DateTime? updatedAt;

  bool get isLowBirthWeight =>
      birthWeightKg != null && birthWeightKg! < 2.5;
  bool get isVeryLowBirthWeight =>
      birthWeightKg != null && birthWeightKg! < 1.5;
  bool get isPreterm =>
      gestationWeeksAtBirth != null && gestationWeeksAtBirth! < 37;
  bool get isMultiple => plurality != BirthPlurality.singleton;

  /// Fever or hypothermia — both neonatal red flags.
  bool get hasTemperatureAbnormality {
    if (temperatureCelsius == null) return false;
    return temperatureCelsius! > 37.5 || temperatureCelsius! < 35.5;
  }

  /// True if ANY Young-Infant IMCI PSBI danger sign is affirmed.
  /// PSBI = immediate IMCI referral (injectable gentamicin before transport).
  bool get hasAnyPsbiDangerSign =>
      historyOfConvulsions ||
      severeChestIndrawing ||
      nasalFlaring ||
      grunting ||
      bulgingFontanelle ||
      jaundiceBefore24h ||
      feedingDifficulty ||
      abdominalDistension ||
      cordRednessBeyondBase ||
      cordPus ||
      cordOedemaBeyondBase ||
      skinPustules ||
      lethargicOrUnconscious ||
      bleedingFromAnySite ||
      hasTemperatureAbnormality;

  Map<String, Object?> toMap() => {
    'person_id': personId,
    'birth_weight_kg': birthWeightKg,
    'birth_length_cm': birthLengthCm,
    'gestation_weeks_at_birth': gestationWeeksAtBirth,
    'delivery_place': deliveryPlace?.name,
    'delivery_mode': deliveryMode?.name,
    'plurality': plurality.name,
    'birth_order': birthOrder,
    'resuscitation_needed': resuscitationNeeded == null
        ? null
        : (resuscitationNeeded! ? 1 : 0),
    'apgar_1_minute': apgar1Minute,
    'apgar_5_minute': apgar5Minute,
    'cord_care_given': cordCareGiven == null ? null : (cordCareGiven! ? 1 : 0),
    'cord_chlorhexidine_applied': cordChlorhexidineApplied == null
        ? null
        : (cordChlorhexidineApplied! ? 1 : 0),
    'vitamin_k_given': vitaminKGiven == null ? null : (vitaminKGiven! ? 1 : 0),
    'vitamin_k_dose_mg': vitaminKDoseMg,
    'breastfed_within_one_hour': breastfedWithinOneHour == null
        ? null
        : (breastfedWithinOneHour! ? 1 : 0),
    'breastfeeding_ok_on_day1': breastfeedingOkOnDay1 == null
        ? null
        : (breastfeedingOkOnDay1! ? 1 : 0),
    'temperature_celsius': temperatureCelsius,
    'respiratory_rate_per_min': respiratoryRatePerMin,
    'heart_rate_per_min': heartRatePerMin,
    'oxygen_saturation_per_cent': oxygenSaturationPerCent,
    'history_of_convulsions': historyOfConvulsions ? 1 : 0,
    'severe_chest_indrawing': severeChestIndrawing ? 1 : 0,
    'nasal_flaring': nasalFlaring ? 1 : 0,
    'grunting': grunting ? 1 : 0,
    'bulging_fontanelle': bulgingFontanelle ? 1 : 0,
    'jaundice_before_24h': jaundiceBefore24h ? 1 : 0,
    'jaundice_on_day3_or_later': jaundiceOnDay3OrLater,
    'feeding_difficulty': feedingDifficulty ? 1 : 0,
    'abdominal_distension': abdominalDistension ? 1 : 0,
    'cord_redness_beyond_base': cordRednessBeyondBase ? 1 : 0,
    'cord_pus': cordPus ? 1 : 0,
    'cord_oedema_beyond_base': cordOedemaBeyondBase ? 1 : 0,
    'skin_pustules': skinPustules ? 1 : 0,
    'lethargic_or_unconscious': lethargicOrUnconscious ? 1 : 0,
    'bleeding_from_any_site': bleedingFromAnySite ? 1 : 0,
    'kmc_eligible': kmcEligible ? 1 : 0,
    'kmc_initiated': kmcInitiated == null ? null : (kmcInitiated! ? 1 : 0),
    'kmc_site': kmcSite,
    'kmc_hours_per_day': kmcHoursPerDay,
    'sickle_screen_sample_collected': sickleScreenSampleCollected == null
        ? null
        : (sickleScreenSampleCollected! ? 1 : 0),
    'sickle_screen_sample_date': sickleScreenSampleDate?.toIso8601String(),
    'hearing_screen_done':
        hearingScreenDone == null ? null : (hearingScreenDone! ? 1 : 0),
    'hearing_screen_result': hearingScreenResult,
    'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
  };

  factory BirthRecord.fromMap(Map<String, Object?> m) => BirthRecord(
    personId: m['person_id'] as String,
    birthWeightKg: (m['birth_weight_kg'] as num?)?.toDouble(),
    birthLengthCm: (m['birth_length_cm'] as num?)?.toDouble(),
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
    apgar1Minute: (m['apgar_1_minute'] as num?)?.toInt(),
    apgar5Minute: (m['apgar_5_minute'] as num?)?.toInt(),
    cordCareGiven: m['cord_care_given'] == null
        ? null
        : (m['cord_care_given'] as num) == 1,
    cordChlorhexidineApplied: m['cord_chlorhexidine_applied'] == null
        ? null
        : (m['cord_chlorhexidine_applied'] as num) == 1,
    vitaminKGiven: m['vitamin_k_given'] == null
        ? null
        : (m['vitamin_k_given'] as num) == 1,
    vitaminKDoseMg: (m['vitamin_k_dose_mg'] as num?)?.toDouble() ?? 1,
    breastfedWithinOneHour: m['breastfed_within_one_hour'] == null
        ? null
        : (m['breastfed_within_one_hour'] as num) == 1,
    breastfeedingOkOnDay1: m['breastfeeding_ok_on_day1'] == null
        ? null
        : (m['breastfeeding_ok_on_day1'] as num) == 1,
    temperatureCelsius: (m['temperature_celsius'] as num?)?.toDouble(),
    respiratoryRatePerMin: (m['respiratory_rate_per_min'] as num?)?.toInt(),
    heartRatePerMin: (m['heart_rate_per_min'] as num?)?.toInt(),
    oxygenSaturationPerCent:
        (m['oxygen_saturation_per_cent'] as num?)?.toInt(),
    historyOfConvulsions: (m['history_of_convulsions'] as num?) == 1,
    severeChestIndrawing: (m['severe_chest_indrawing'] as num?) == 1,
    nasalFlaring: (m['nasal_flaring'] as num?) == 1,
    grunting: (m['grunting'] as num?) == 1,
    bulgingFontanelle: (m['bulging_fontanelle'] as num?) == 1,
    jaundiceBefore24h: (m['jaundice_before_24h'] as num?) == 1,
    jaundiceOnDay3OrLater: m['jaundice_on_day3_or_later'] as String?,
    feedingDifficulty: (m['feeding_difficulty'] as num?) == 1,
    abdominalDistension: (m['abdominal_distension'] as num?) == 1,
    cordRednessBeyondBase: (m['cord_redness_beyond_base'] as num?) == 1,
    cordPus: (m['cord_pus'] as num?) == 1,
    cordOedemaBeyondBase: (m['cord_oedema_beyond_base'] as num?) == 1,
    skinPustules: (m['skin_pustules'] as num?) == 1,
    lethargicOrUnconscious: (m['lethargic_or_unconscious'] as num?) == 1,
    bleedingFromAnySite: (m['bleeding_from_any_site'] as num?) == 1,
    kmcEligible: (m['kmc_eligible'] as num?) == 1,
    kmcInitiated: m['kmc_initiated'] == null
        ? null
        : (m['kmc_initiated'] as num) == 1,
    kmcSite: m['kmc_site'] as String?,
    kmcHoursPerDay: (m['kmc_hours_per_day'] as num?)?.toDouble(),
    sickleScreenSampleCollected: m['sickle_screen_sample_collected'] == null
        ? null
        : (m['sickle_screen_sample_collected'] as num) == 1,
    sickleScreenSampleDate: DateTime.tryParse(
      (m['sickle_screen_sample_date'] as String?) ?? '',
    ),
    hearingScreenDone: m['hearing_screen_done'] == null
        ? null
        : (m['hearing_screen_done'] as num) == 1,
    hearingScreenResult: m['hearing_screen_result'] as String?,
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
    this.muacMm,
    this.muacCm,
    this.weightKg,
    this.heightCm,
    this.hasBilateralOedema = false,
    this.palmarPallorSeverity, // none / some / severe (IMCI malnutrition)
    this.recordedBy,
  });

  final String id;
  final String personId;
  final DateTime takenAt;

  /// Mid-upper arm circumference in MILLIMETRES as read directly from the
  /// standard GHS MUAC tape. SAM <115 mm, MAM 115–124 mm, normal ≥125 mm.
  /// This is the "source of truth" — `muacCm` is derived.
  final int? muacMm;

  /// Derived MUAC in centimetres (kept for backwards compatibility with the
  /// existing z-score and chart code that expects cm). Computed as muacMm/10.
  final double? muacCm;

  final double? weightKg;
  final double? heightCm;

  /// Bilateral pitting oedema means SAM regardless of MUAC. Never ignore it.
  final bool hasBilateralOedema;

  /// IMCI malnutrition palmar pallor: none / some / severe.
  /// Severe = anaemia SAM trigger → iron + referral.
  final String? palmarPallorSeverity;

  final String? recordedBy;

  /// Returns true if this is SAM by ANY IMCI criterion (oedema, MUAC mm <115,
  /// WFH z-score < -3). Use alongside the WHZ engine, not in isolation.
  bool get isSamByMuacOrOedema =>
      hasBilateralOedema || (muacMm != null && muacMm! < 115);

  bool get isMamByMuac =>
      muacMm != null && muacMm! >= 115 && muacMm! < 125;

  Map<String, Object?> toMap() => {
    'id': id,
    'person_id': personId,
    'taken_at': takenAt.toIso8601String(),
    'muac_mm': muacMm,
    'muac_cm': muacCm,
    'weight_kg': weightKg,
    'height_cm': heightCm,
    'has_bilateral_oedema': hasBilateralOedema ? 1 : 0,
    'palmar_pallor_severity': palmarPallorSeverity,
    'recorded_by': recordedBy,
  };

  factory GrowthMeasurement.fromMap(Map<String, Object?> m) => GrowthMeasurement(
    id: m['id'] as String,
    personId: m['person_id'] as String,
    takenAt: DateTime.parse(m['taken_at'] as String),
    muacMm: (m['muac_mm'] as num?)?.toInt(),
    muacCm: (m['muac_cm'] as num?)?.toDouble(),
    weightKg: (m['weight_kg'] as num?)?.toDouble(),
    heightCm: (m['height_cm'] as num?)?.toDouble(),
    hasBilateralOedema: (m['has_bilateral_oedema'] as num?) == 1,
    palmarPallorSeverity: m['palmar_pallor_severity'] as String?,
    recordedBy: m['recorded_by'] as String?,
  );
}

/// Structured snapshot of an IMCI sick-child or well-child assessment at a
/// single encounter.
///
/// The layout mirrors the EXACT section order of the Ghana GHS IMCI Sick-Child
/// Case Recording Form (blue book, 2022 revision) used in every CHPS compound:
///
///   1. General danger signs (able to drink/breastfeed? vomits everything?
///      convulsions? lethargic/unconscious?)
///   2. Cough / difficult breathing (RR numeric, age-based cutoffs,
///      chest indrawing, stridor, SaO₂)
///   3. Diarrhoea + dehydration (duration, blood in stool, sunken eyes,
///      drinks eagerly/poorly, skin pinch — slowly/very slowly)
///   4. Fever (duration, stiff neck, runny nose, measles 3Cs, eye discharge,
///      corneal clouding, mouth ulcers, RDT result, tourniquet test for
///      Dengue, petechiae, capillary refill seconds)
///   5. Ear problem (ear pain days, pus draining, tender mastoid — mastoiditis)
///   6. Malnutrition / anaemia (MUAC mm, bilateral oedema, palmar pallor,
///      WFH/L z-score, ability to finish RUTF, BF assessment, complementary)
///   7. HIV screening / ART exposure status
///   8. Immunization status — vaccines due TODAY
///   9. Feeding assessment (6–23 month indicators per WHO 2023)
///  10. Initial vs Follow-up flag (IMCI FU classification rules DIFFER)
///
/// Every field name is aligned with the paper form so a CHO transcribes
/// without mentally translating. This is the #1 requirement for adoption.
class ChildAssessmentSnapshot {
  const ChildAssessmentSnapshot({
    required this.id,
    required this.personId,
    required this.assessedAt,
    this.visitType = 'initial', // initial / follow_up
    this.ageDaysCompleted,
    // ── 1. General danger signs ───────────────────────────────────────────
    this.ableToDrinkOrBreastfeed,
    this.vomitsEverything,
    this.hasConvulsionsThisVisit,
    this.isLethargicOrUnconscious,
    // ── 2. Cough / difficult breathing ────────────────────────────────────
    this.coughPresent = false,
    this.coughDurationDays,
    this.respiratoryRatePerMin,
    this.chestIndrawing = false,
    this.stridorCalm = false,
    this.nasalFlaring = false,
    this.oxygenSaturationPerCent,
    // ── 3. Diarrhoea + dehydration ────────────────────────────────────────
    this.diarrhoeaPresent = false,
    this.diarrhoeaDurationDays,
    this.bloodInStool = false,
    this.restlessOrIrritable,
    this.sunkenEyes,
    this.drinksEagerly,
    this.skinPinchResult, // normal / slowly / very_slowly
    // ── 4. Fever ──────────────────────────────────────────────────────────
    this.feverReported = false,
    this.feverDurationDays,
    this.temperatureCelsius,
    this.stiffNeck = false,
    this.runnyNose = false,
    this.measlesRashPresent = false,
    this.measlesCough = false,
    this.measlesCoryza = false,
    this.measlesConjunctivitis = false,
    this.mouthUlcers = false,
    this.eyeDischarge = false,
    this.cornealClouding = false,
    this.measlesWithinPast3Months = false,
    this.malariaRdtDone = false,
    this.malariaRdtResult, // negative / pf_positive / pv_positive / mixed
    this.tourniquetTestDone = false,
    this.tourniquetTestPositive,
    this.skinPetechiae = false,
    this.capillaryRefillSeconds,
    // ── 5. Ear problem ────────────────────────────────────────────────────
    this.earProblemPresent = false,
    this.earPainDurationDays,
    this.earPusDraining = false,
    this.earPusDurationDays,
    this.tenderSwellingBehindEar = false, // mastoiditis → SEVERE
    // ── 6. Malnutrition / anaemia / HIV ───────────────────────────────────
    this.weightForHeightOrLengthZscore,
    this.hivExposedOrInfectedStatus, // unexposed / exposed_unknown / exposed_on_art / infected_on_art
    this.ableToFinishRutf,
    // ── 7. Feeding assessment (WHO IYCF 2023, 6–23 months) ────────────────
    this.breastfedToday,
    this.nightFeedsPer24h,
    this.complementaryFoodsGivenToday,
    this.minimumDietaryDiversity,
    this.minimumMealFrequency,
    this.minimumAcceptableDiet,
    // ── 8. Immunizations DUE TODAY (EPI Ghana schedule) ───────────────────
    this.immunizationsDueToday,
    this.immunizationsGivenToday,
    // ── Meta ──────────────────────────────────────────────────────────────
    this.assessedByUserId,
    this.recordedByUserId,
    this.updatedAt,
  });

  final String id;
  final String personId;
  final DateTime assessedAt;

  /// IMCI CRITICAL: classification rules are DIFFERENT for initial vs FU.
  /// 'initial' = first visit for this illness episode.
  /// 'follow_up' = return visit → class rules can UPGRADE severity.
  final String visitType;
  final int? ageDaysCompleted;

  // 1. General danger signs — ANY ONE = SEVERE classification.
  final bool? ableToDrinkOrBreastfeed;
  final bool? vomitsEverything;
  final bool? hasConvulsionsThisVisit;
  final bool? isLethargicOrUnconscious;

  // 2. Cough / difficult breathing.
  // RR is the #1 gap (4% of Kintampo CHOs actually counted — Baiden 2011),
  // so we enforce a numeric capture + auto-classify.
  final bool coughPresent;
  final int? coughDurationDays;
  final int? respiratoryRatePerMin;
  final bool chestIndrawing;
  final bool stridorCalm;
  final bool nasalFlaring;
  final int? oxygenSaturationPerCent;

  // 3. Diarrhoea + IMCI dehydration Plan A / B / C.
  final bool diarrhoeaPresent;
  final int? diarrhoeaDurationDays;
  final bool bloodInStool;
  final bool? restlessOrIrritable;
  final bool? sunkenEyes;
  final bool? drinksEagerly;
  final String? skinPinchResult;

  // 4. Fever + measles + malaria + dengue.
  final bool feverReported;
  final int? feverDurationDays;
  final double? temperatureCelsius;
  final bool stiffNeck;
  final bool runnyNose;
  final bool measlesRashPresent;
  final bool measlesCough;
  final bool measlesCoryza;
  final bool measlesConjunctivitis;
  final bool mouthUlcers;
  final bool eyeDischarge;
  final bool cornealClouding;
  final bool measlesWithinPast3Months;
  final bool malariaRdtDone;
  final String? malariaRdtResult;
  final bool tourniquetTestDone;
  final bool? tourniquetTestPositive;
  final bool skinPetechiae;
  final double? capillaryRefillSeconds;

  // 5. Ear. Tender mastoid = SEVERE.
  final bool earProblemPresent;
  final int? earPainDurationDays;
  final bool earPusDraining;
  final int? earPusDurationDays;
  final bool tenderSwellingBehindEar;

  // 6. Malnutrition / HIV / RUTF response.
  final double? weightForHeightOrLengthZscore;
  final String? hivExposedOrInfectedStatus;
  final bool? ableToFinishRutf;

  // 7. IYCF feeding assessment (WHO 2023 8-indicator module, 6–23 months).
  final bool? breastfedToday;
  final int? nightFeedsPer24h;
  final bool? complementaryFoodsGivenToday;
  final bool? minimumDietaryDiversity;
  final bool? minimumMealFrequency;
  final bool? minimumAcceptableDiet;

  // 8. Immunizations due today — GHS EPI schedule.
  final List<String>? immunizationsDueToday;
  final List<String>? immunizationsGivenToday;

  final String? assessedByUserId;
  final String? recordedByUserId;
  final DateTime? updatedAt;

  // ── Convenience getters ────────────────────────────────────────────────

  /// True if any general danger sign is affirmed → SEVERE.
  bool get hasAnyGeneralDangerSign =>
      (ableToDrinkOrBreastfeed == false) ||
      (vomitsEverything == true) ||
      (hasConvulsionsThisVisit == true) ||
      (isLethargicOrUnconscious == true);

  /// IMCI pneumonia classification using RR cutoffs by age.
  ///   <2mo  ≥60  → SEVERE pneumonia
  ///   2–11mo ≥50 → pneumonia
  ///   12–59mo ≥40 → pneumonia
  /// + chest indrawing → upgrade
  String? get imciPneumoniaClass {
    if (!coughPresent || respiratoryRatePerMin == null || ageDaysCompleted == null) {
      return null;
    }
    final rr = respiratoryRatePerMin!;
    final ageDays = ageDaysCompleted!;
    final bool indrawing = chestIndrawing;
    if (ageDays < 60) {
      if (rr >= 60 || indrawing || stridorCalm) return 'severe_pneumonia';
      if (rr >= 60) return 'pneumonia';
      return 'no_pneumonia_cough_or_cold';
    } else if (ageDays < 365) {
      if (indrawing || stridorCalm) return 'severe_pneumonia';
      if (rr >= 50) return 'pneumonia';
      return 'no_pneumonia_cough_or_cold';
    } else {
      if (indrawing || stridorCalm) return 'severe_pneumonia';
      if (rr >= 40) return 'pneumonia';
      return 'no_pneumonia_cough_or_cold';
    }
  }

  /// IMCI dehydration classification (Plan A / B / C).
  String? get imciDehydrationClass {
    if (!diarrhoeaPresent) return null;
    int signs = 0;
    if (restlessOrIrritable == true) signs++;
    if (sunkenEyes == true) signs++;
    if (drinksEagerly == true) signs++;
    if (skinPinchResult == 'slowly') signs++;
    int severeSigns = 0;
    if (isLethargicOrUnconscious == true) severeSigns++;
    if (skinPinchResult == 'very_slowly') severeSigns++;
    if (ableToDrinkOrBreastfeed == false) severeSigns++;
    if (vomitsEverything == true) severeSigns++;
    if (severeSigns >= 1) return 'severe_dehydration_plan_c';
    if (signs >= 2) return 'some_dehydration_plan_b';
    return 'no_dehydration_plan_a';
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'person_id': personId,
    'assessed_at': assessedAt.toIso8601String(),
    'visit_type': visitType,
    'age_days_completed': ageDaysCompleted,
    'able_to_drink_or_breastfeed': ableToDrinkOrBreastfeed == null
        ? null
        : (ableToDrinkOrBreastfeed! ? 1 : 0),
    'vomits_everything':
        vomitsEverything == null ? null : (vomitsEverything! ? 1 : 0),
    'has_convulsions_this_visit': hasConvulsionsThisVisit == null
        ? null
        : (hasConvulsionsThisVisit! ? 1 : 0),
    'is_lethargic_or_unconscious': isLethargicOrUnconscious == null
        ? null
        : (isLethargicOrUnconscious! ? 1 : 0),
    'cough_present': coughPresent ? 1 : 0,
    'cough_duration_days': coughDurationDays,
    'respiratory_rate_per_min': respiratoryRatePerMin,
    'chest_indrawing': chestIndrawing ? 1 : 0,
    'stridor_calm': stridorCalm ? 1 : 0,
    'nasal_flaring': nasalFlaring ? 1 : 0,
    'oxygen_saturation_per_cent': oxygenSaturationPerCent,
    'diarrhoea_present': diarrhoeaPresent ? 1 : 0,
    'diarrhoea_duration_days': diarrhoeaDurationDays,
    'blood_in_stool': bloodInStool ? 1 : 0,
    'restless_or_irritable': restlessOrIrritable == null
        ? null
        : (restlessOrIrritable! ? 1 : 0),
    'sunken_eyes': sunkenEyes == null ? null : (sunkenEyes! ? 1 : 0),
    'drinks_eagerly': drinksEagerly == null ? null : (drinksEagerly! ? 1 : 0),
    'skin_pinch_result': skinPinchResult,
    'fever_reported': feverReported ? 1 : 0,
    'fever_duration_days': feverDurationDays,
    'temperature_celsius': temperatureCelsius,
    'stiff_neck': stiffNeck ? 1 : 0,
    'runny_nose': runnyNose ? 1 : 0,
    'measles_rash_present': measlesRashPresent ? 1 : 0,
    'measles_cough': measlesCough ? 1 : 0,
    'measles_coryza': measlesCoryza ? 1 : 0,
    'measles_conjunctivitis': measlesConjunctivitis ? 1 : 0,
    'mouth_ulcers': mouthUlcers ? 1 : 0,
    'eye_discharge': eyeDischarge ? 1 : 0,
    'corneal_clouding': cornealClouding ? 1 : 0,
    'measles_within_past_3_months': measlesWithinPast3Months ? 1 : 0,
    'malaria_rdt_done': malariaRdtDone ? 1 : 0,
    'malaria_rdt_result': malariaRdtResult,
    'tourniquet_test_done': tourniquetTestDone ? 1 : 0,
    'tourniquet_test_positive': tourniquetTestPositive == null
        ? null
        : (tourniquetTestPositive! ? 1 : 0),
    'skin_petechiae': skinPetechiae ? 1 : 0,
    'capillary_refill_seconds': capillaryRefillSeconds,
    'ear_problem_present': earProblemPresent ? 1 : 0,
    'ear_pain_duration_days': earPainDurationDays,
    'ear_pus_draining': earPusDraining ? 1 : 0,
    'ear_pus_duration_days': earPusDurationDays,
    'tender_swelling_behind_ear': tenderSwellingBehindEar ? 1 : 0,
    'weight_for_height_or_length_zscore': weightForHeightOrLengthZscore,
    'hiv_exposed_or_infected_status': hivExposedOrInfectedStatus,
    'able_to_finish_rutf':
        ableToFinishRutf == null ? null : (ableToFinishRutf! ? 1 : 0),
    'breastfed_today':
        breastfedToday == null ? null : (breastfedToday! ? 1 : 0),
    'night_feeds_per_24h': nightFeedsPer24h,
    'complementary_foods_given_today': complementaryFoodsGivenToday == null
        ? null
        : (complementaryFoodsGivenToday! ? 1 : 0),
    'minimum_dietary_diversity': minimumDietaryDiversity == null
        ? null
        : (minimumDietaryDiversity! ? 1 : 0),
    'minimum_meal_frequency': minimumMealFrequency == null
        ? null
        : (minimumMealFrequency! ? 1 : 0),
    'minimum_acceptable_diet': minimumAcceptableDiet == null
        ? null
        : (minimumAcceptableDiet! ? 1 : 0),
    'immunizations_due_today':
        immunizationsDueToday?.join(','),
    'immunizations_given_today': immunizationsGivenToday?.join(','),
    'assessed_by_user_id': assessedByUserId,
    'recorded_by_user_id': recordedByUserId,
    'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
  };

  factory ChildAssessmentSnapshot.fromMap(Map<String, Object?> m) =>
      ChildAssessmentSnapshot(
        id: m['id'] as String,
        personId: m['person_id'] as String,
        assessedAt: DateTime.parse(m['assessed_at'] as String),
        visitType: (m['visit_type'] as String?) ?? 'initial',
        ageDaysCompleted: (m['age_days_completed'] as num?)?.toInt(),
        ableToDrinkOrBreastfeed: m['able_to_drink_or_breastfeed'] == null
            ? null
            : (m['able_to_drink_or_breastfeed'] as num) == 1,
        vomitsEverything: m['vomits_everything'] == null
            ? null
            : (m['vomits_everything'] as num) == 1,
        hasConvulsionsThisVisit: m['has_convulsions_this_visit'] == null
            ? null
            : (m['has_convulsions_this_visit'] as num) == 1,
        isLethargicOrUnconscious: m['is_lethargic_or_unconscious'] == null
            ? null
            : (m['is_lethargic_or_unconscious'] as num) == 1,
        coughPresent: (m['cough_present'] as num?) == 1,
        coughDurationDays: (m['cough_duration_days'] as num?)?.toInt(),
        respiratoryRatePerMin:
            (m['respiratory_rate_per_min'] as num?)?.toInt(),
        chestIndrawing: (m['chest_indrawing'] as num?) == 1,
        stridorCalm: (m['stridor_calm'] as num?) == 1,
        nasalFlaring: (m['nasal_flaring'] as num?) == 1,
        oxygenSaturationPerCent:
            (m['oxygen_saturation_per_cent'] as num?)?.toInt(),
        diarrhoeaPresent: (m['diarrhoea_present'] as num?) == 1,
        diarrhoeaDurationDays:
            (m['diarrhoea_duration_days'] as num?)?.toInt(),
        bloodInStool: (m['blood_in_stool'] as num?) == 1,
        restlessOrIrritable: m['restless_or_irritable'] == null
            ? null
            : (m['restless_or_irritable'] as num) == 1,
        sunkenEyes:
            m['sunken_eyes'] == null ? null : (m['sunken_eyes'] as num) == 1,
        drinksEagerly: m['drinks_eagerly'] == null
            ? null
            : (m['drinks_eagerly'] as num) == 1,
        skinPinchResult: m['skin_pinch_result'] as String?,
        feverReported: (m['fever_reported'] as num?) == 1,
        feverDurationDays: (m['fever_duration_days'] as num?)?.toInt(),
        temperatureCelsius:
            (m['temperature_celsius'] as num?)?.toDouble(),
        stiffNeck: (m['stiff_neck'] as num?) == 1,
        runnyNose: (m['runny_nose'] as num?) == 1,
        measlesRashPresent: (m['measles_rash_present'] as num?) == 1,
        measlesCough: (m['measles_cough'] as num?) == 1,
        measlesCoryza: (m['measles_coryza'] as num?) == 1,
        measlesConjunctivitis:
            (m['measles_conjunctivitis'] as num?) == 1,
        mouthUlcers: (m['mouth_ulcers'] as num?) == 1,
        eyeDischarge: (m['eye_discharge'] as num?) == 1,
        cornealClouding: (m['corneal_clouding'] as num?) == 1,
        measlesWithinPast3Months:
            (m['measles_within_past_3_months'] as num?) == 1,
        malariaRdtDone: (m['malaria_rdt_done'] as num?) == 1,
        malariaRdtResult: m['malaria_rdt_result'] as String?,
        tourniquetTestDone: (m['tourniquet_test_done'] as num?) == 1,
        tourniquetTestPositive: m['tourniquet_test_positive'] == null
            ? null
            : (m['tourniquet_test_positive'] as num) == 1,
        skinPetechiae: (m['skin_petechiae'] as num?) == 1,
        capillaryRefillSeconds:
            (m['capillary_refill_seconds'] as num?)?.toDouble(),
        earProblemPresent: (m['ear_problem_present'] as num?) == 1,
        earPainDurationDays: (m['ear_pain_duration_days'] as num?)?.toInt(),
        earPusDraining: (m['ear_pus_draining'] as num?) == 1,
        earPusDurationDays: (m['ear_pus_duration_days'] as num?)?.toInt(),
        tenderSwellingBehindEar:
            (m['tender_swelling_behind_ear'] as num?) == 1,
        weightForHeightOrLengthZscore:
            (m['weight_for_height_or_length_zscore'] as num?)?.toDouble(),
        hivExposedOrInfectedStatus:
            m['hiv_exposed_or_infected_status'] as String?,
        ableToFinishRutf: m['able_to_finish_rutf'] == null
            ? null
            : (m['able_to_finish_rutf'] as num) == 1,
        breastfedToday: m['breastfed_today'] == null
            ? null
            : (m['breastfed_today'] as num) == 1,
        nightFeedsPer24h: (m['night_feeds_per_24h'] as num?)?.toInt(),
        complementaryFoodsGivenToday:
            m['complementary_foods_given_today'] == null
                ? null
                : (m['complementary_foods_given_today'] as num) == 1,
        minimumDietaryDiversity: m['minimum_dietary_diversity'] == null
            ? null
            : (m['minimum_dietary_diversity'] as num) == 1,
        minimumMealFrequency: m['minimum_meal_frequency'] == null
            ? null
            : (m['minimum_meal_frequency'] as num) == 1,
        minimumAcceptableDiet: m['minimum_acceptable_diet'] == null
            ? null
            : (m['minimum_acceptable_diet'] as num) == 1,
        immunizationsDueToday: (m['immunizations_due_today'] as String?)
            ?.split(',')
          ?..removeWhere((s) => s.isEmpty),
        immunizationsGivenToday: (m['immunizations_given_today'] as String?)
            ?.split(',')
          ?..removeWhere((s) => s.isEmpty),
        assessedByUserId: m['assessed_by_user_id'] as String?,
        recordedByUserId: m['recorded_by_user_id'] as String?,
        updatedAt: DateTime.tryParse((m['updated_at'] as String?) ?? ''),
      );
}
