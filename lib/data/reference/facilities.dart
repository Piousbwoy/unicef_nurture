/// Referral facility hierarchy for the five northern regions.
///
/// Ghana's referral ladder runs:
///   CHPS compound -> Health Centre -> Polyclinic -> District Hospital
///   -> Regional Hospital -> Teaching (tertiary) Hospital
///
/// A CHO refers *upward from where they stand*, so the app must know the
/// nearest facility at each tier — a mother in Wechiau does not get sent to
/// Tamale Teaching Hospital when Wa Regional is three hours closer.
library;

enum FacilityTier {
  chps('CHPS Compound', 1),
  healthCentre('Health Centre', 2),
  polyclinic('Polyclinic', 3),
  districtHospital('District Hospital', 4),
  regionalHospital('Regional Hospital', 5),
  teachingHospital('Teaching Hospital', 6);

  const FacilityTier(this.label, this.rank);
  final String label;
  final int rank;
}

/// Capabilities that determine whether a referral is *clinically adequate*.
/// Referring an obstructed labour to a facility with no theatre wastes the
/// only hours that matter.
enum FacilityCapability {
  caesarean,
  bloodTransfusion,
  newbornCare, // SCBU / NICU
  therapeuticFeeding, // inpatient SAM: F-75 / F-100
  otp, // outpatient therapeutic programme, RUTF
  delivery,
  laboratory,
  ambulance,
}

class Facility {
  const Facility({
    required this.name,
    required this.tier,
    required this.region,
    required this.district,
    required this.capabilities,
  });

  final String name;
  final FacilityTier tier;
  final String region;
  final String district;
  final Set<FacilityCapability> capabilities;

  bool can(FacilityCapability c) => capabilities.contains(c);
}

abstract final class Facilities {
  static const _cemoc = {
    FacilityCapability.caesarean,
    FacilityCapability.bloodTransfusion,
    FacilityCapability.newbornCare,
    FacilityCapability.delivery,
    FacilityCapability.laboratory,
    FacilityCapability.therapeuticFeeding,
    FacilityCapability.otp,
    FacilityCapability.ambulance,
  };

  static const _districtSet = {
    FacilityCapability.caesarean,
    FacilityCapability.bloodTransfusion,
    FacilityCapability.delivery,
    FacilityCapability.laboratory,
    FacilityCapability.otp,
    FacilityCapability.therapeuticFeeding,
  };

  static const _healthCentreSet = {
    FacilityCapability.delivery,
    FacilityCapability.laboratory,
    FacilityCapability.otp,
  };

  static const List<Facility> all = [
    // ------------------------------------------------------ Northern Region
    Facility(
      name: 'Tamale Teaching Hospital',
      tier: FacilityTier.teachingHospital,
      region: 'Northern Region',
      district: 'Tamale',
      capabilities: _cemoc,
    ),
    Facility(
      name: 'Tamale Central Hospital',
      tier: FacilityTier.districtHospital,
      region: 'Northern Region',
      district: 'Tamale',
      capabilities: _districtSet,
    ),
    Facility(
      name: 'Tamale West Hospital',
      tier: FacilityTier.districtHospital,
      region: 'Northern Region',
      district: 'Tamale',
      capabilities: _districtSet,
    ),
    Facility(
      name: 'Savelugu Municipal Hospital',
      tier: FacilityTier.districtHospital,
      region: 'Northern Region',
      district: 'Savelugu',
      capabilities: _districtSet,
    ),
    Facility(
      name: 'Yendi Municipal Hospital',
      tier: FacilityTier.districtHospital,
      region: 'Northern Region',
      district: 'Yendi',
      capabilities: _districtSet,
    ),
    Facility(
      name: 'Gushegu District Hospital',
      tier: FacilityTier.districtHospital,
      region: 'Northern Region',
      district: 'Gushegu',
      capabilities: _districtSet,
    ),
    Facility(
      name: 'Bimbilla District Hospital',
      tier: FacilityTier.districtHospital,
      region: 'Northern Region',
      district: 'Nanumba North',
      capabilities: _districtSet,
    ),
    Facility(
      name: 'Karaga District Hospital',
      tier: FacilityTier.districtHospital,
      region: 'Northern Region',
      district: 'Karaga',
      capabilities: _districtSet,
    ),
    Facility(
      name: 'Tolon District Hospital',
      tier: FacilityTier.districtHospital,
      region: 'Northern Region',
      district: 'Tolon',
      capabilities: _districtSet,
    ),
    Facility(
      name: 'Nyankpala Health Centre',
      tier: FacilityTier.healthCentre,
      region: 'Northern Region',
      district: 'Tolon',
      capabilities: _healthCentreSet,
    ),
    Facility(
      name: 'Kumbungu Health Centre',
      tier: FacilityTier.healthCentre,
      region: 'Northern Region',
      district: 'Kumbungu',
      capabilities: _healthCentreSet,
    ),
    Facility(
      name: 'Dalun Health Centre',
      tier: FacilityTier.healthCentre,
      region: 'Northern Region',
      district: 'Kumbungu',
      capabilities: _healthCentreSet,
    ),
    Facility(
      name: 'Saboba E.P. Hospital',
      tier: FacilityTier.districtHospital,
      region: 'Northern Region',
      district: 'Saboba',
      capabilities: _districtSet,
    ),
    Facility(
      name: 'Kpandai District Hospital',
      tier: FacilityTier.districtHospital,
      region: 'Northern Region',
      district: 'Kpandai',
      capabilities: _districtSet,
    ),
    Facility(
      name: 'Zabzugu District Hospital',
      tier: FacilityTier.districtHospital,
      region: 'Northern Region',
      district: 'Zabzugu',
      capabilities: _districtSet,
    ),
    Facility(
      name: 'Sang Health Centre',
      tier: FacilityTier.healthCentre,
      region: 'Northern Region',
      district: 'Mion',
      capabilities: _healthCentreSet,
    ),
    Facility(
      name: 'Nanton Health Centre',
      tier: FacilityTier.healthCentre,
      region: 'Northern Region',
      district: 'Nanton',
      capabilities: _healthCentreSet,
    ),
    Facility(
      name: 'Wulensi Health Centre',
      tier: FacilityTier.healthCentre,
      region: 'Northern Region',
      district: 'Nanumba South',
      capabilities: _healthCentreSet,
    ),
    Facility(
      name: 'Tatale Health Centre',
      tier: FacilityTier.healthCentre,
      region: 'Northern Region',
      district: 'Tatale Sanguli',
      capabilities: _healthCentreSet,
    ),
    Facility(
      name: 'Sagnarigu Polyclinic',
      tier: FacilityTier.polyclinic,
      region: 'Northern Region',
      district: 'Sagnarigu',
      capabilities: _healthCentreSet,
    ),

    // ---------------------------------------------------- North East Region
    Facility(
      name: 'Baptist Medical Centre, Nalerigu',
      tier: FacilityTier.regionalHospital,
      region: 'North East Region',
      district: 'East Mamprusi',
      capabilities: _cemoc,
    ),
    Facility(
      name: 'Walewale Municipal Hospital',
      tier: FacilityTier.districtHospital,
      region: 'North East Region',
      district: 'West Mamprusi',
      capabilities: _districtSet,
    ),
    Facility(
      name: 'Gambaga District Hospital',
      tier: FacilityTier.districtHospital,
      region: 'North East Region',
      district: 'East Mamprusi',
      capabilities: _districtSet,
    ),
    Facility(
      name: 'Bunkpurugu District Hospital',
      tier: FacilityTier.districtHospital,
      region: 'North East Region',
      district: 'Bunkpurugu Nakpanduri',
      capabilities: _districtSet,
    ),
    Facility(
      name: 'Chereponi District Hospital',
      tier: FacilityTier.districtHospital,
      region: 'North East Region',
      district: 'Chereponi',
      capabilities: _districtSet,
    ),
    Facility(
      name: 'Yagaba Health Centre',
      tier: FacilityTier.healthCentre,
      region: 'North East Region',
      district: 'Mamprugu Moagduri',
      capabilities: _healthCentreSet,
    ),
    Facility(
      name: 'Yunyoo Health Centre',
      tier: FacilityTier.healthCentre,
      region: 'North East Region',
      district: 'Yunyoo Nasuan',
      capabilities: _healthCentreSet,
    ),

    // ------------------------------------------------------ Savannah Region
    Facility(
      name: 'West Gonja Hospital, Damongo',
      tier: FacilityTier.regionalHospital,
      region: 'Savannah Region',
      district: 'West Gonja',
      capabilities: _cemoc,
    ),
    Facility(
      name: 'Bole District Hospital',
      tier: FacilityTier.districtHospital,
      region: 'Savannah Region',
      district: 'Bole',
      capabilities: _districtSet,
    ),
    Facility(
      name: 'Salaga District Hospital',
      tier: FacilityTier.districtHospital,
      region: 'Savannah Region',
      district: 'East Gonja',
      capabilities: _districtSet,
    ),
    Facility(
      name: 'Sawla District Hospital',
      tier: FacilityTier.districtHospital,
      region: 'Savannah Region',
      district: 'Sawla-Tuna-Kalba',
      capabilities: _districtSet,
    ),
    Facility(
      name: 'Buipe Health Centre',
      tier: FacilityTier.healthCentre,
      region: 'Savannah Region',
      district: 'Central Gonja',
      capabilities: _healthCentreSet,
    ),
    Facility(
      name: 'Daboya Health Centre',
      tier: FacilityTier.healthCentre,
      region: 'Savannah Region',
      district: 'North Gonja',
      capabilities: _healthCentreSet,
    ),
    Facility(
      name: 'Kpalbe Health Centre',
      tier: FacilityTier.healthCentre,
      region: 'Savannah Region',
      district: 'North East Gonja',
      capabilities: _healthCentreSet,
    ),

    // ---------------------------------------------------- Upper East Region
    Facility(
      name: 'Upper East Regional Hospital, Bolgatanga',
      tier: FacilityTier.regionalHospital,
      region: 'Upper East Region',
      district: 'Bolgatanga',
      capabilities: _cemoc,
    ),
    Facility(
      name: 'War Memorial Hospital, Navrongo',
      tier: FacilityTier.districtHospital,
      region: 'Upper East Region',
      district: 'Kassena Nankana East',
      capabilities: _cemoc,
    ),
    Facility(
      name: 'Bawku Presbyterian Hospital',
      tier: FacilityTier.districtHospital,
      region: 'Upper East Region',
      district: 'Bawku',
      capabilities: _cemoc,
    ),
    Facility(
      name: 'Zebilla District Hospital',
      tier: FacilityTier.districtHospital,
      region: 'Upper East Region',
      district: 'Bawku West',
      capabilities: _districtSet,
    ),
    Facility(
      name: 'Sandema District Hospital',
      tier: FacilityTier.districtHospital,
      region: 'Upper East Region',
      district: 'Builsa North',
      capabilities: _districtSet,
    ),
    Facility(
      name: 'Bongo District Hospital',
      tier: FacilityTier.districtHospital,
      region: 'Upper East Region',
      district: 'Bongo',
      capabilities: _districtSet,
    ),
    Facility(
      name: 'Garu District Hospital',
      tier: FacilityTier.districtHospital,
      region: 'Upper East Region',
      district: 'Garu',
      capabilities: _districtSet,
    ),
    Facility(
      name: 'Tongo Health Centre',
      tier: FacilityTier.healthCentre,
      region: 'Upper East Region',
      district: 'Talensi',
      capabilities: _healthCentreSet,
    ),
    Facility(
      name: 'Paga Health Centre',
      tier: FacilityTier.healthCentre,
      region: 'Upper East Region',
      district: 'Kassena Nankana West',
      capabilities: _healthCentreSet,
    ),
    Facility(
      name: 'Nangodi Health Centre',
      tier: FacilityTier.healthCentre,
      region: 'Upper East Region',
      district: 'Nabdam',
      capabilities: _healthCentreSet,
    ),
    Facility(
      name: 'Fumbisi Health Centre',
      tier: FacilityTier.healthCentre,
      region: 'Upper East Region',
      district: 'Builsa South',
      capabilities: _healthCentreSet,
    ),
    Facility(
      name: 'Pusiga Health Centre',
      tier: FacilityTier.healthCentre,
      region: 'Upper East Region',
      district: 'Pusiga',
      capabilities: _healthCentreSet,
    ),
    Facility(
      name: 'Binduri Health Centre',
      tier: FacilityTier.healthCentre,
      region: 'Upper East Region',
      district: 'Binduri',
      capabilities: _healthCentreSet,
    ),
    Facility(
      name: 'Tempane Health Centre',
      tier: FacilityTier.healthCentre,
      region: 'Upper East Region',
      district: 'Tempane',
      capabilities: _healthCentreSet,
    ),
    Facility(
      name: 'Zuarungu Health Centre',
      tier: FacilityTier.healthCentre,
      region: 'Upper East Region',
      district: 'Bolgatanga East',
      capabilities: _healthCentreSet,
    ),

    // ---------------------------------------------------- Upper West Region
    Facility(
      name: 'Upper West Regional Hospital, Wa',
      tier: FacilityTier.regionalHospital,
      region: 'Upper West Region',
      district: 'Wa',
      capabilities: _cemoc,
    ),
    Facility(
      name: "St. Joseph's Hospital, Jirapa",
      tier: FacilityTier.districtHospital,
      region: 'Upper West Region',
      district: 'Jirapa',
      capabilities: _cemoc,
    ),
    Facility(
      name: 'Nandom Hospital',
      tier: FacilityTier.districtHospital,
      region: 'Upper West Region',
      district: 'Nandom',
      capabilities: _cemoc,
    ),
    Facility(
      name: 'Lawra Municipal Hospital',
      tier: FacilityTier.districtHospital,
      region: 'Upper West Region',
      district: 'Lawra',
      capabilities: _districtSet,
    ),
    Facility(
      name: 'Tumu District Hospital',
      tier: FacilityTier.districtHospital,
      region: 'Upper West Region',
      district: 'Sissala East',
      capabilities: _districtSet,
    ),
    Facility(
      name: 'Nadowli District Hospital',
      tier: FacilityTier.districtHospital,
      region: 'Upper West Region',
      district: 'Nadowli/Kaleo',
      capabilities: _districtSet,
    ),
    Facility(
      name: 'Wechiau Health Centre',
      tier: FacilityTier.healthCentre,
      region: 'Upper West Region',
      district: 'Wa West',
      capabilities: _healthCentreSet,
    ),
    Facility(
      name: 'Funsi Health Centre',
      tier: FacilityTier.healthCentre,
      region: 'Upper West Region',
      district: 'Wa East',
      capabilities: _healthCentreSet,
    ),
    Facility(
      name: 'Gwollu Health Centre',
      tier: FacilityTier.healthCentre,
      region: 'Upper West Region',
      district: 'Sissala West',
      capabilities: _healthCentreSet,
    ),
    Facility(
      name: 'Lambussie Health Centre',
      tier: FacilityTier.healthCentre,
      region: 'Upper West Region',
      district: 'Lambussie',
      capabilities: _healthCentreSet,
    ),
    Facility(
      name: 'Issa Health Centre',
      tier: FacilityTier.healthCentre,
      region: 'Upper West Region',
      district: 'Daffiama Bussie Issa',
      capabilities: _healthCentreSet,
    ),
  ];

  static List<Facility> inRegion(String region) =>
      all.where((f) => f.region == region).toList(growable: false);

  static List<Facility> inDistrict(String region, String district) =>
      all
          .where((f) => f.region == region && f.district == district)
          .toList(growable: false);

  /// Nearest adequate facility for a referral needing [required] capabilities.
  ///
  /// Prefers the CHO's own district (shortest journey, lowest transport cost),
  /// then falls back to the region. Within each scope the *lowest* adequate
  /// tier wins, because sending every case to the regional hospital is exactly
  /// how referral systems collapse.
  static List<Facility> adequateFor({
    required String region,
    required String district,
    Set<FacilityCapability> required = const {},
  }) {
    bool adequate(Facility f) => required.every(f.can);

    final local = inDistrict(region, district).where(adequate).toList()
      ..sort((a, b) => a.tier.rank.compareTo(b.tier.rank));
    final regional = inRegion(region).where(adequate).toList()
      ..sort((a, b) => a.tier.rank.compareTo(b.tier.rank));

    // Local options first, then anything else in the region not already listed.
    final seen = local.map((f) => f.name).toSet();
    return [...local, ...regional.where((f) => !seen.contains(f.name))];
  }
}
