/// Administrative and health-system geography of the five northern regions of
/// Ghana, used to ground every record CareBridge AI captures.
///
/// District and capital data is taken from the Ghana Local Government Service
/// register of MMDAs (Metropolitan / Municipal / District Assemblies):
///   * Northern Region     — 16 MMDAs
///   * North East Region    — 6 MMDAs
///   * Savannah Region      — 7 MMDAs
///   * Upper East Region   — 15 MMDAs
///   * Upper West Region   — 11 MMDAs
///
/// Community lists are representative settlements within each district. They
/// seed the offline community picker; a CHO can always add an unlisted
/// settlement, because gazetteers never keep up with real hamlets.
library;

enum AssemblyType {
  metropolitan('Metropolitan'),
  municipal('Municipal'),
  district('District');

  const AssemblyType(this.label);
  final String label;
}

class GhRegion {
  const GhRegion({
    required this.code,
    required this.name,
    required this.capital,
    required this.districts,
    required this.languages,
  });

  final String code;
  final String name;
  final String capital;
  final List<GhDistrict> districts;

  /// Languages in rough order of prevalence. Kept as a regional record —
  /// the guidance picker is fixed to the four spoken languages (see
  /// [NorthernGhana.guidanceLanguages]).
  final List<String> languages;
}

class GhDistrict {
  const GhDistrict({
    required this.name,
    required this.capital,
    required this.type,
    required this.communities,
  });

  final String name;
  final String capital;
  final AssemblyType type;
  final List<String> communities;

  String get displayName => '$name ${type.label}';
}

abstract final class NorthernGhana {
  static const List<GhRegion> regions = [
    _northern,
    _northEast,
    _savannah,
    _upperEast,
    _upperWest,
  ];

  static List<String> get regionNames =>
      regions.map((r) => r.name).toList(growable: false);

  static GhRegion? regionByName(String name) =>
      regions.where((r) => r.name == name).firstOrNull;

  static List<GhDistrict> districtsOf(String regionName) =>
      regionByName(regionName)?.districts ?? const [];

  static GhDistrict? districtByName(String regionName, String districtName) =>
      districtsOf(regionName).where((d) => d.name == districtName).firstOrNull;

  static List<String> communitiesOf(String regionName, String districtName) =>
      districtByName(regionName, districtName)?.communities ?? const [];

  /// The languages CareBridge speaks, in picker order: the three
  /// on-device bank voices plus the universal English fallback.
  static const guidanceLanguages = <String>[
    'Dagbani',
    'Hausa',
    'Twi',
    'English',
  ];

  /// Languages available for audio guidance. The same four everywhere:
  /// Dagbani, Hausa, Twi and English. Region prevalence no longer widens
  /// the list — offering Likpakpaln or Nanuni would promise a voice the
  /// app cannot play, and the audio button must never overpromise.
  static List<String> languagesOf(String regionName) => guidanceLanguages;

  static int get totalDistricts =>
      regions.fold(0, (sum, r) => sum + r.districts.length);

  // ---------------------------------------------------------------- Northern

  static const _northern = GhRegion(
    code: 'NR',
    name: 'Northern Region',
    capital: 'Tamale',
    languages: [
      'Dagbani',
      'Likpakpaln (Konkomba)',
      'Nanuni (Nanumba)',
      'Anufo (Chokosi)',
      'Gonja',
    ],
    districts: [
      GhDistrict(
        name: 'Tamale',
        capital: 'Tamale',
        type: AssemblyType.metropolitan,
        communities: [
          'Tamale Central',
          'Aboabo',
          'Lamashegu',
          'Choggu',
          'Kalpohin',
          'Vittin',
          'Nyohini',
          'Zogbeli',
          'Moshie Zongo',
          'Gumbihini',
          'Bilpela',
          'Tishigu',
          'Dakpema',
          'Sakasaka',
          'Changli',
        ],
      ),
      GhDistrict(
        name: 'Sagnarigu',
        capital: 'Sagnarigu',
        type: AssemblyType.municipal,
        communities: [
          'Sagnarigu',
          'Kamina',
          'Jisonayili',
          'Gumani',
          'Katariga',
          'Zagyuri',
          'Kpalsi',
          'Malshegu',
          'Tuutingli',
          'Gurugu',
          'Choggu Yapalsi',
          'Vittin Tarikpaa',
        ],
      ),
      GhDistrict(
        name: 'Savelugu',
        capital: 'Savelugu',
        type: AssemblyType.municipal,
        communities: [
          'Savelugu',
          'Pong-Tamale',
          'Diare',
          'Nabogu',
          'Tampion',
          'Moglaa',
          'Libga',
          'Zoggu',
          'Kadia',
          'Gushei',
          'Yong',
        ],
      ),
      GhDistrict(
        name: 'Yendi',
        capital: 'Yendi',
        type: AssemblyType.municipal,
        communities: [
          'Yendi',
          'Adibo',
          'Sunson',
          'Gbungbaliga',
          'Kuga',
          'Bunbonayili',
          'Malzeri',
          'Gbaringa',
          'Sang Naa',
          'Kpasoya',
        ],
      ),
      GhDistrict(
        name: 'Gushegu',
        capital: 'Gushegu',
        type: AssemblyType.municipal,
        communities: [
          'Gushegu',
          'Kpatinga',
          'Nabuli',
          'Katani',
          'Zamashegu',
          'Gaa',
          'Nawuhugu',
          'Pishigu',
          'Sakogu',
        ],
      ),
      GhDistrict(
        name: 'Nanumba North',
        capital: 'Bimbilla',
        type: AssemblyType.municipal,
        communities: [
          'Bimbilla',
          'Nakpayili',
          'Juo',
          'Dakpam',
          'Bincheratanga',
          'Kpayansi',
          'Nakpaa',
          'Gbungbaliga',
        ],
      ),
      GhDistrict(
        name: 'Nanumba South',
        capital: 'Wulensi',
        type: AssemblyType.district,
        communities: [
          'Wulensi',
          'Juale',
          'Lungni',
          'Chamba',
          'Nakpaa',
          'Kpandai Road',
          'Sabonjida',
        ],
      ),
      GhDistrict(
        name: 'Karaga',
        capital: 'Karaga',
        type: AssemblyType.district,
        communities: [
          'Karaga',
          'Pishigu',
          'Nyong',
          'Sung',
          'Tamaligu',
          'Bulbia',
          'Kpatinga Road',
          'Tuvuu',
        ],
      ),
      GhDistrict(
        name: 'Kpandai',
        capital: 'Kpandai',
        type: AssemblyType.district,
        communities: [
          'Kpandai',
          'Kumdi',
          'Katiejeli',
          'Bladjai',
          'Nkanchina',
          'Balai',
          'Kitare',
          'Sabonjida',
        ],
      ),
      GhDistrict(
        name: 'Kumbungu',
        capital: 'Kumbungu',
        type: AssemblyType.district,
        communities: [
          'Kumbungu',
          'Dalun',
          'Gupanarigu',
          'Voggu',
          'Kpalsogu',
          'Zangbalun',
          'Kpendua',
          'Tibung',
          'Wuba',
          'Gbanjong',
        ],
      ),
      GhDistrict(
        name: 'Mion',
        capital: 'Sang',
        type: AssemblyType.district,
        communities: [
          'Sang',
          'Kpabia',
          'Jimle',
          'Sambu',
          'Warivi',
          'Kulkpanga',
          'Tusani',
        ],
      ),
      GhDistrict(
        name: 'Nanton',
        capital: 'Nanton',
        type: AssemblyType.district,
        communities: [
          'Nanton',
          'Nanton Kurugu',
          'Gbanjong',
          'Zoggu',
          'Janjori-Kukuo',
          'Tarikpaa',
          'Dalung',
        ],
      ),
      GhDistrict(
        name: 'Saboba',
        capital: 'Saboba',
        type: AssemblyType.district,
        communities: [
          'Saboba',
          'Wapuli',
          'Sobiba',
          'Gbangbani',
          'Demon',
          'Toma',
          'Kpalba',
          'Nalongni',
        ],
      ),
      GhDistrict(
        name: 'Tatale Sanguli',
        capital: 'Tatale',
        type: AssemblyType.district,
        communities: [
          'Tatale',
          'Sanguli',
          'Nalongni',
          'Kpalgun',
          'Bulbia',
          'Kunkon',
        ],
      ),
      GhDistrict(
        name: 'Tolon',
        capital: 'Tolon',
        type: AssemblyType.district,
        communities: [
          'Tolon',
          'Nyankpala',
          'Wantugu',
          'Gbullung',
          'Kasuliyili',
          'Woribogu',
          'Lungbunga',
          'Zangbalung',
          'Yipeligu',
          'Tingoli',
          'Cheshegu',
        ],
      ),
      GhDistrict(
        name: 'Zabzugu',
        capital: 'Zabzugu',
        type: AssemblyType.district,
        communities: [
          'Zabzugu',
          'Kpalba',
          'Tabdo',
          'Sabare',
          'Kworli',
          'Nakpali',
        ],
      ),
    ],
  );

  // -------------------------------------------------------------- North East

  static const _northEast = GhRegion(
    code: 'NER',
    name: 'North East Region',
    capital: 'Nalerigu',
    languages: [
      'Mampruli',
      'Bimoba (Moba)',
      'Likpakpaln (Konkomba)',
      'Dagbani',
    ],
    districts: [
      GhDistrict(
        name: 'East Mamprusi',
        capital: 'Gambaga',
        type: AssemblyType.municipal,
        communities: [
          'Gambaga',
          'Nalerigu',
          'Langbinsi',
          'Gbintiri',
          'Sakogu',
          'Zangum',
          'Bongbini',
          'Samini',
        ],
      ),
      GhDistrict(
        name: 'West Mamprusi',
        capital: 'Walewale',
        type: AssemblyType.municipal,
        communities: [
          'Walewale',
          'Wungu',
          'Kpasenkpe',
          'Guabuliga',
          'Nasia',
          'Janga',
          'Wulugu',
          'Kukua',
        ],
      ),
      GhDistrict(
        name: 'Bunkpurugu Nakpanduri',
        capital: 'Bunkpurugu',
        type: AssemblyType.district,
        communities: [
          'Bunkpurugu',
          'Nakpanduri',
          'Binde',
          'Jimbale',
          'Kambatiak',
          'Najong',
          'Bimbagu',
        ],
      ),
      GhDistrict(
        name: 'Chereponi',
        capital: 'Chereponi',
        type: AssemblyType.district,
        communities: [
          'Chereponi',
          'Wenchiki',
          'Tambong',
          'Kanjo',
          'Nasuan Road',
          'Bunbon',
        ],
      ),
      GhDistrict(
        name: 'Mamprugu Moagduri',
        capital: 'Yagaba',
        type: AssemblyType.district,
        communities: [
          'Yagaba',
          'Kubori',
          'Loagri',
          'Zanwara',
          'Yizeisi',
          'Kunkwa',
        ],
      ),
      GhDistrict(
        name: 'Yunyoo Nasuan',
        capital: 'Yunyoo',
        type: AssemblyType.district,
        communities: [
          'Yunyoo',
          'Nasuan',
          'Gbangbani',
          'Chegbani',
          'Tinguri',
          'Kpemale',
        ],
      ),
    ],
  );

  // ---------------------------------------------------------------- Savannah

  static const _savannah = GhRegion(
    code: 'SR',
    name: 'Savannah Region',
    capital: 'Damongo',
    languages: ['Gonja', 'Vagla', 'Safaliba', 'Birifor', 'Deg', 'Hanga'],
    districts: [
      GhDistrict(
        name: 'West Gonja',
        capital: 'Damongo',
        type: AssemblyType.municipal,
        communities: [
          'Damongo',
          'Larabanga',
          'Mognori',
          'Busunu',
          'Kananto',
          'Murugu',
          'Jonokponto',
          'Kadelso',
        ],
      ),
      GhDistrict(
        name: 'East Gonja',
        capital: 'Salaga',
        type: AssemblyType.municipal,
        communities: [
          'Salaga',
          'Kpembe',
          'Makango',
          'Kafaba',
          'Bunjai',
          'Sabonjida',
          'Kitoe',
        ],
      ),
      GhDistrict(
        name: 'Bole',
        capital: 'Bole',
        type: AssemblyType.district,
        communities: [
          'Bole',
          'Bamboi',
          'Tinga',
          'Mandari',
          'Maluwe',
          'Chache',
          'Jama',
          'Kakiase',
        ],
      ),
      GhDistrict(
        name: 'Sawla-Tuna-Kalba',
        capital: 'Sawla',
        type: AssemblyType.district,
        communities: [
          'Sawla',
          'Tuna',
          'Kalba',
          'Gindabuor',
          'Bisikan',
          'Gbalpuo',
        ],
      ),
      GhDistrict(
        name: 'Central Gonja',
        capital: 'Buipe',
        type: AssemblyType.district,
        communities: [
          'Buipe',
          'Yapei',
          'Mpaha',
          'Kusawgu',
          'Lito',
          'Tuluwe',
        ],
      ),
      GhDistrict(
        name: 'North Gonja',
        capital: 'Daboya',
        type: AssemblyType.district,
        communities: [
          'Daboya',
          'Mankarigu',
          'Lingbinsi',
          'Yapala',
          'Kunfosi',
        ],
      ),
      GhDistrict(
        name: 'North East Gonja',
        capital: 'Kpalbe',
        type: AssemblyType.district,
        communities: [
          'Kpalbe',
          'Bunjai',
          'Nanjuro',
          'Wulasi',
          'Sabonjida',
        ],
      ),
    ],
  );

  // -------------------------------------------------------------- Upper East

  static const _upperEast = GhRegion(
    code: 'UER',
    name: 'Upper East Region',
    capital: 'Bolgatanga',
    languages: [
      'Gurene (Frafra)',
      'Kusaal',
      'Kasem (Kassena)',
      'Nankam (Nankani)',
      'Buli (Builsa)',
    ],
    districts: [
      GhDistrict(
        name: 'Bolgatanga',
        capital: 'Bolgatanga',
        type: AssemblyType.municipal,
        communities: [
          'Bolgatanga',
          'Sumbrungu',
          'Tanzui',
          'Yikene',
          'Sherigu',
          'Zaare',
          'Kumbosgo',
          'Soe',
          'Bukere',
        ],
      ),
      GhDistrict(
        name: 'Bolgatanga East',
        capital: 'Zuarungu',
        type: AssemblyType.district,
        communities: [
          'Zuarungu',
          'Nyariga',
          'Dachio',
          'Zuarungu-Moshie',
          'Gambibgo',
          'Kumbangre',
        ],
      ),
      GhDistrict(
        name: 'Bawku',
        capital: 'Bawku',
        type: AssemblyType.municipal,
        communities: [
          'Bawku',
          'Missiga',
          'Gozesi',
          'Manga',
          'Zongoyiri',
          'Sapeliga',
          'Kuka',
        ],
      ),
      GhDistrict(
        name: 'Bawku West',
        capital: 'Zebilla',
        type: AssemblyType.district,
        communities: [
          'Zebilla',
          'Tilli',
          'Googo',
          'Widnaba',
          'Kusanaba',
          'Sapeliga',
          'Binaba',
        ],
      ),
      GhDistrict(
        name: 'Kassena Nankana East',
        capital: 'Navrongo',
        type: AssemblyType.municipal,
        communities: [
          'Navrongo',
          'Doba',
          'Bonia',
          'Kologo',
          'Naaga',
          'Pungu',
          'Telania',
          'Manyoro',
        ],
      ),
      GhDistrict(
        name: 'Kassena Nankana West',
        capital: 'Paga',
        type: AssemblyType.district,
        communities: [
          'Paga',
          'Chiana',
          'Sirigu',
          'Mirigu',
          'Kandiga',
          'Nakong',
          'Katiu',
        ],
      ),
      GhDistrict(
        name: 'Bongo',
        capital: 'Bongo',
        type: AssemblyType.district,
        communities: [
          'Bongo',
          'Gowrie',
          'Zorko',
          'Beo',
          'Namoo',
          'Vea',
          'Adaboya',
          'Balungu',
          'Feo',
        ],
      ),
      GhDistrict(
        name: 'Builsa North',
        capital: 'Sandema',
        type: AssemblyType.municipal,
        communities: [
          'Sandema',
          'Wiaga',
          'Chuchuliga',
          'Kadema',
          'Siniensi',
          'Kanjarga',
        ],
      ),
      GhDistrict(
        name: 'Builsa South',
        capital: 'Fumbisi',
        type: AssemblyType.district,
        communities: [
          'Fumbisi',
          'Gbedema',
          'Wiesi',
          'Uwasi',
          'Doninga',
          'Kanjarga',
        ],
      ),
      GhDistrict(
        name: 'Talensi',
        capital: 'Tongo',
        type: AssemblyType.district,
        communities: [
          'Tongo',
          'Winkogo',
          'Datuko',
          'Shia',
          'Gbeogo',
          'Pwalugu',
          'Balungu',
        ],
      ),
      GhDistrict(
        name: 'Nabdam',
        capital: 'Nangodi',
        type: AssemblyType.district,
        communities: [
          'Nangodi',
          'Kongo',
          'Zanlerigu',
          'Pelungu',
          'Sakote',
          'Dasabligo',
        ],
      ),
      GhDistrict(
        name: 'Binduri',
        capital: 'Binduri',
        type: AssemblyType.district,
        communities: [
          'Binduri',
          'Atuba',
          'Yarugu',
          'Azuwera',
          'Kugri',
          'Gozesi',
        ],
      ),
      GhDistrict(
        name: 'Garu',
        capital: 'Garu',
        type: AssemblyType.district,
        communities: [
          'Garu',
          'Worikambo',
          'Kugri',
          'Denugu',
          'Bugri',
          'Songo',
        ],
      ),
      GhDistrict(
        name: 'Tempane',
        capital: 'Tempane',
        type: AssemblyType.district,
        communities: [
          'Tempane',
          'Woriyanga',
          'Kpikpira',
          'Bugri',
          'Diare',
        ],
      ),
      GhDistrict(
        name: 'Pusiga',
        capital: 'Pusiga',
        type: AssemblyType.district,
        communities: [
          'Pusiga',
          'Kulungugu',
          'Widana',
          'Kubongo',
          'Tesnatinga',
        ],
      ),
    ],
  );

  // -------------------------------------------------------------- Upper West

  static const _upperWest = GhRegion(
    code: 'UWR',
    name: 'Upper West Region',
    capital: 'Wa',
    languages: [
      'Waali (Waala)',
      'Dagaare',
      'Sissali',
      'Lobi',
      'Birifor',
    ],
    districts: [
      GhDistrict(
        name: 'Wa',
        capital: 'Wa',
        type: AssemblyType.municipal,
        communities: [
          'Wa',
          'Mangu',
          'Kambali',
          'Bamahu',
          'Charia',
          'Busa',
          'Kperisi',
          'Nakori',
          'Guli',
        ],
      ),
      GhDistrict(
        name: 'Wa East',
        capital: 'Funsi',
        type: AssemblyType.district,
        communities: [
          'Funsi',
          'Bulenga',
          'Kundungu',
          'Loggu',
          'Yaala',
          'Kandia',
        ],
      ),
      GhDistrict(
        name: 'Wa West',
        capital: 'Wechiau',
        type: AssemblyType.district,
        communities: [
          'Wechiau',
          'Dorimon',
          'Ga',
          'Vieri',
          'Guropisi',
          'Poyentanga',
        ],
      ),
      GhDistrict(
        name: 'Nadowli/Kaleo',
        capital: 'Nadowli',
        type: AssemblyType.district,
        communities: [
          'Nadowli',
          'Kaleo',
          'Charikpong',
          'Sankana',
          'Jang',
          'Takpo',
        ],
      ),
      GhDistrict(
        name: 'Daffiama Bussie Issa',
        capital: 'Issa',
        type: AssemblyType.district,
        communities: [
          'Issa',
          'Daffiama',
          'Bussie',
          'Kojokperi',
          'Nator',
        ],
      ),
      GhDistrict(
        name: 'Jirapa',
        capital: 'Jirapa',
        type: AssemblyType.municipal,
        communities: [
          'Jirapa',
          'Ullo',
          'Han',
          'Tizza',
          'Duori',
          'Baazu',
          'Konzokala',
        ],
      ),
      GhDistrict(
        name: 'Lambussie',
        capital: 'Lambussie',
        type: AssemblyType.district,
        communities: [
          'Lambussie',
          'Karni',
          'Piina',
          'Samoa',
          'Billaw',
          'Hamile',
        ],
      ),
      GhDistrict(
        name: 'Lawra',
        capital: 'Lawra',
        type: AssemblyType.municipal,
        communities: [
          'Lawra',
          'Babile',
          'Eremon',
          'Zambo',
          'Boo',
          'Dikpe',
        ],
      ),
      GhDistrict(
        name: 'Nandom',
        capital: 'Nandom',
        type: AssemblyType.municipal,
        communities: [
          'Nandom',
          'Ko',
          'Puffien',
          'Guo',
          'Baseble',
          'Burutu',
        ],
      ),
      GhDistrict(
        name: 'Sissala East',
        capital: 'Tumu',
        type: AssemblyType.municipal,
        communities: [
          'Tumu',
          'Kong',
          'Sakai',
          'Bujan',
          'Nabugubelle',
          'Wellembelle',
          'Pieng',
        ],
      ),
      GhDistrict(
        name: 'Sissala West',
        capital: 'Gwollu',
        type: AssemblyType.district,
        communities: [
          'Gwollu',
          'Fielmuo',
          'Jeffisi',
          'Zini',
          'Dolbizan',
          'Kunchogu',
        ],
      ),
    ],
  );
}
