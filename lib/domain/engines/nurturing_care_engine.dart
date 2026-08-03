/// Nurturing care — the half of child survival the clinic never sees.
///
/// The hackathon is called *AI for Nurturing Care*, and that name is not
/// decoration. The WHO/UNICEF nurturing care framework rests on five pillars:
/// good health, adequate nutrition, safety and security, **responsive
/// caregiving** and **opportunities for early learning**. A community health
/// app that only measures MUAC and counts danger signs serves two of the five
/// and walks past the rest — the exact rest that builds the brain doing the
/// surviving.
///
/// The evidence base here is the WHO/UNICEF *Care for Child Development*
/// package, adapted for a Northern Ghanaian home: no purchased toys, no
/// literacy required, everything phrased as something a mother, grandmother
/// or older sibling can *do today* with what is already in the compound.
///
/// Design decisions, all deliberate:
///
/// **Age bands, not exact months.** Milestones are ranges; a mother told her
/// eight-month-old should sit who only sees a band boundary will either relax
/// wrongly or panic wrongly. Bands carry their own windows.
///
/// **Red flags are conservative.** A flag means "show the health worker",
/// never "something is wrong". Screening language in a family's pocket must
/// not diagnose; it must route. Every flag here is one the WHO CCD package
/// teaches health workers to act on, so the FHW who receives the report
/// recognises it instantly.
///
/// **Play rotates daily** ([activityToday]) from a deterministic function of
/// the date, so the same phone shows something new each morning without any
/// network at all.
///
/// Like every other engine in this app, it is a pure function over its
/// inputs — testable against the published tables without a database in sight.
library;

/// The four pillars of nurturing care, phrased the way a family speaks them.
enum NcDomain {
  move('Moving'),
  communicate('Talking and hearing'),
  learn('Thinking'),
  love('Loving and playing');

  const NcDomain(this.label);
  final String label;
}

/// One thing a child in this band is learning to do.
///
/// [question] is phrased exactly as the caregiver sees it, because it is what
/// gets stored and shown to the health worker — the family's words, not coded
/// keys. [isFlag] marks the milestones whose absence by the end of the band
/// the WHO CCD package treats as a reason for a health worker to look at the
/// child.
class NcMilestone {
  const NcMilestone({
    required this.id,
    required this.question,
    required this.domain,
    this.isFlag = false,
  });

  final String id;
  final String question;
  final NcDomain domain;
  final bool isFlag;
}

/// One age band: the milestones to ask about, the play ideas to rotate, and
/// one responsive-caregiving tip. [minMonths] is inclusive, [maxMonths]
/// exclusive — a child of exactly [maxMonths] belongs to the next band.
class NcAgeBand {
  const NcAgeBand({
    required this.minMonths,
    required this.maxMonths,
    required this.label,
    required this.milestones,
    required this.activities,
    required this.tip,
  });

  final int minMonths;
  final int maxMonths;
  final String label;
  final List<NcMilestone> milestones;

  /// Zero-cost play ideas, phrased as instructions, using only what exists in
  /// a typical household: calabashes, cloths, seeds too big to swallow, songs.
  final List<String> activities;

  /// One sentence of responsive caregiving — noticing and answering the
  /// child's signals — which is the pillar the clinics almost never touch.
  final String tip;

  List<NcMilestone> get flags =>
      milestones.where((m) => m.isFlag).toList(growable: false);
}

class NurturingCareEngine {
  NurturingCareEngine._();

  /// The bands, ordered by age. Content adapted from the WHO/UNICEF Care for
  /// Child Development package and the CDC milestone tables, rewritten for a
  /// Dagbani-speaking household.
  static const List<NcAgeBand> bands = [
    NcAgeBand(
      minMonths: 0,
      maxMonths: 2,
      label: 'Birth to 2 months',
      milestones: [
        NcMilestone(
          id: 'calms',
          question: 'Calms down when you hold or speak to them',
          domain: NcDomain.love,
        ),
        NcMilestone(
          id: 'looks-face',
          question: 'Looks at your face when you talk',
          domain: NcDomain.love,
          isFlag: true,
        ),
        NcMilestone(
          id: 'sounds',
          question: 'Makes sounds other than crying',
          domain: NcDomain.communicate,
        ),
        NcMilestone(
          id: 'lifts-head',
          question: 'Lifts the head for a moment when lying on the tummy',
          domain: NcDomain.move,
        ),
      ],
      activities: [
        'Hold the baby skin-to-skin against your chest and talk softly. '
            'Your voice is the first lesson they ever get.',
        'Move your face slowly from side to side and let the baby follow '
            'it with their eyes.',
        'When the baby makes a sound, pause, then answer. That turn-taking '
            'is their first conversation.',
      ],
      tip:
          'Answer the baby quickly when they cry. A baby who is answered '
          'learns the world is safe — that is not spoiling, that is wiring.',
    ),
    NcAgeBand(
      minMonths: 2,
      maxMonths: 4,
      label: '2 to 4 months',
      milestones: [
        NcMilestone(
          id: 'smiles-back',
          question: 'Smiles back when you smile',
          domain: NcDomain.love,
          isFlag: true,
        ),
        NcMilestone(
          id: 'holds-head',
          question: 'Holds the head steady when held upright',
          domain: NcDomain.move,
          isFlag: true,
        ),
        NcMilestone(
          id: 'laughs',
          question: 'Laughs, squeals or chuckles aloud',
          domain: NcDomain.communicate,
        ),
        NcMilestone(
          id: 'follows',
          question: 'Follows a moving thing with the eyes',
          domain: NcDomain.learn,
        ),
      ],
      activities: [
        'Make a rattle from a closed bottle or gourd with a few big seeds '
            'inside. Shake it and watch the baby turn toward the sound.',
        'Give the baby tummy time on the mat every day while you sit close '
            'and talk — strong neck, strong everything after.',
        'Copy the baby\u2019s face and sounds, then wait for them to copy '
            'you back.',
      ],
      tip:
          'Get face-to-face before you play. A baby learns best from a face '
          'that is close, bright and answering.',
    ),
    NcAgeBand(
      minMonths: 4,
      maxMonths: 6,
      label: '4 to 6 months',
      milestones: [
        NcMilestone(
          id: 'reaches',
          question: 'Reaches out and takes hold of a thing',
          domain: NcDomain.move,
          isFlag: true,
        ),
        NcMilestone(
          id: 'rolls',
          question: 'Rolls over from tummy to back or back to tummy',
          domain: NcDomain.move,
        ),
        NcMilestone(
          id: 'turns-sound',
          question: 'Turns the head toward a sound or their name',
          domain: NcDomain.communicate,
          isFlag: true,
        ),
        NcMilestone(
          id: 'mouths',
          question: 'Brings things to the mouth to feel them',
          domain: NcDomain.learn,
        ),
      ],
      activities: [
        'Roll a clean calabash or cup just within reach and let the baby '
            'work to grab it.',
        'Sit the baby supported on your lap facing the world, and name the '
            'things you both see: water, fire, goat, cloth.',
        'Play the sound game: shake something behind them and celebrate '
            'when they turn to find it.',
      ],
      tip:
          'Talking to the baby while you work is teaching. Every word you '
            'say over the cooking pot is food for the brain.',
    ),
    NcAgeBand(
      minMonths: 6,
      maxMonths: 9,
      label: '6 to 9 months',
      milestones: [
        NcMilestone(
          id: 'sits',
          question: 'Sits without support',
          domain: NcDomain.move,
          isFlag: true,
        ),
        NcMilestone(
          id: 'passes',
          question: 'Passes a thing from one hand to the other',
          domain: NcDomain.learn,
        ),
        NcMilestone(
          id: 'knows-name',
          question: 'Looks or answers when you call their name',
          domain: NcDomain.communicate,
          isFlag: true,
        ),
        NcMilestone(
          id: 'peekaboo',
          question: 'Smiles and plays when you cover your face with a cloth',
          domain: NcDomain.love,
        ),
      ],
      activities: [
        'Play peekaboo with your cloth — hiding and reappearing teaches '
            'that things come back, and that the world can be trusted.',
        'Sit together and bang two safe things gently together. Sound they '
            'made themselves is science they will remember.',
        'Let them feel safe things of different touch: smooth gourd, soft '
            'cloth, cool water.',
      ],
      tip:
          'When the baby points or reaches, answer the signal. Noticing and '
            'answering is the whole game of responsive care.',
    ),
    NcAgeBand(
      minMonths: 9,
      maxMonths: 12,
      label: '9 to 12 months',
      milestones: [
        NcMilestone(
          id: 'crawls',
          question: 'Crawls, creeps or moves around somehow',
          domain: NcDomain.move,
        ),
        NcMilestone(
          id: 'stands-hold',
          question: 'Stands while holding on to something',
          domain: NcDomain.move,
        ),
        NcMilestone(
          id: 'gestures',
          question: 'Uses a gesture — waves, reaches up, points',
          domain: NcDomain.communicate,
          isFlag: true,
        ),
        NcMilestone(
          id: 'understands',
          question: 'Understands a firm \u201cno\u201d or simple words',
          domain: NcDomain.learn,
        ),
      ],
      activities: [
        'Hide a thing under a cup and help them find it. Hidden things that '
            'still exist is a whole new kind of thinking.',
        'Fill a bowl with things too big to swallow and let them pour it '
            'out and fill it again, a hundred times. Repetition is the work.',
        'Clap and sing a song with their name in it.',
      ],
      tip:
          'Let the child explore a safe corner of the compound. A child who '
            'moves, learns — protect the space, not the stillness.',
    ),
    NcAgeBand(
      minMonths: 12,
      maxMonths: 18,
      label: '1 to 1\u00bd years',
      milestones: [
        NcMilestone(
          id: 'steps',
          question: 'Walks, even with a hand to hold',
          domain: NcDomain.move,
        ),
        NcMilestone(
          id: 'first-words',
          question: 'Says a real word, like \u201cmama\u201d or \u201cnaa\u201d',
          domain: NcDomain.communicate,
          isFlag: true,
        ),
        NcMilestone(
          id: 'points-ask',
          question: 'Points to ask for something they want',
          domain: NcDomain.communicate,
        ),
        NcMilestone(
          id: 'cup',
          question: 'Drinks from a cup held for them',
          domain: NcDomain.learn,
        ),
      ],
      activities: [
        'Name things as you work: \u201cThis is water. This is millet. This '
            'is your foot.\u201d Naming is reading, before reading.',
        'Let them walk holding the edge of the bench, the wall, your finger '
            '— and celebrate every fall-and-up.',
        'Give them a safe pot and spoon to bang and fill while you cook.',
      ],
      tip:
          'Say the word for what they point at. A point answered with a '
            'name is worth ten words heard by accident.',
    ),
    NcAgeBand(
      minMonths: 18,
      maxMonths: 24,
      label: '1\u00bd to 2 years',
      milestones: [
        NcMilestone(
          id: 'walks-well',
          question: 'Walks well without holding on',
          domain: NcDomain.move,
          isFlag: true,
        ),
        NcMilestone(
          id: 'six-words',
          question: 'Uses several words (about six or more)',
          domain: NcDomain.communicate,
          isFlag: true,
        ),
        NcMilestone(
          id: 'copies',
          question: 'Copies the work they see you doing',
          domain: NcDomain.learn,
        ),
        NcMilestone(
          id: 'points-show',
          question: 'Points at things just to show them to you',
          domain: NcDomain.love,
        ),
      ],
      activities: [
        'Give them small real work — carrying something light, stirring, '
            'fetching. Helping is how a child learns to belong.',
        'Make a ball from rolled cloth and kick it back and forth.',
        'Ask \u201cWhere is your nose?\u201d and celebrate when they find '
            'it. Body-part games are free and endless.',
      ],
      tip:
          'When the child shows you something, stop and look. Being seen is '
            'how a child learns they are worth hearing.',
    ),
    NcAgeBand(
      minMonths: 24,
      maxMonths: 36,
      label: '2 to 3 years',
      milestones: [
        NcMilestone(
          id: 'two-words',
          question: 'Puts two words together, like \u201cgive water\u201d',
          domain: NcDomain.communicate,
          isFlag: true,
        ),
        NcMilestone(
          id: 'runs',
          question: 'Runs and kicks a ball or cloth bundle',
          domain: NcDomain.move,
        ),
        NcMilestone(
          id: 'plays-with',
          question: 'Plays near or with other children',
          domain: NcDomain.love,
        ),
        NcMilestone(
          id: 'follows',
          question: 'Follows a simple instruction, like \u201cbring the cup\u201d',
          domain: NcDomain.learn,
        ),
      ],
      activities: [
        'Sing and clap songs in Dagbani, and leave a pause for them to fill '
            'in the last word.',
        'Sort things into two piles — big seeds here, small stones there. '
            'Sorting is mathematics before numbers.',
        'Tell a short story about an animal and let them finish it with '
            'sounds and words.',
      ],
      tip:
          'Answer the endless \u201cwhy\u201d and \u201cwhat\u201d questions '
            'patiently. Every question answered is a child who keeps asking.',
    ),
    NcAgeBand(
      minMonths: 36,
      maxMonths: 60,
      label: '3 to 5 years',
      milestones: [
        NcMilestone(
          id: 'clear-speech',
          question: 'Speaks so the family can understand most of it',
          domain: NcDomain.communicate,
          isFlag: true,
        ),
        NcMilestone(
          id: 'draws',
          question: 'Draws or makes marks — in sand, on slate, with a stick',
          domain: NcDomain.learn,
        ),
        NcMilestone(
          id: 'turns',
          question: 'Plays with other children, taking turns',
          domain: NcDomain.love,
        ),
        NcMilestone(
          id: 'hops',
          question: 'Hops, climbs, or pedals something with wheels',
          domain: NcDomain.move,
        ),
      ],
      activities: [
        'Play market: sell and buy pretend things. Counting, talking and '
            'taking turns all happen at once.',
        'Draw shapes in the sand together and name them.',
        'Count stones, seeds or steps out loud — ten of anything, every day.',
      ],
      tip:
          'Let the child choose a game and follow their rules for a while. '
            'Being led by the child once a day is powerful medicine.',
    ),
  ];

  /// The band a child of [ageMonths] belongs to, or null outside the tracked
  /// window (before birth, or 5 years and older — school-age development is
  /// a different instrument).
  static NcAgeBand? bandFor(int? ageMonths) {
    if (ageMonths == null || ageMonths < 0) return null;
    for (final band in bands) {
      if (ageMonths >= band.minMonths && ageMonths < band.maxMonths) {
        return band;
      }
    }
    return null;
  }

  /// Today's play idea for a band — a deterministic rotation by date, so the
  /// card shows something new each morning without any network.
  static String activityToday(NcAgeBand band, [DateTime? now]) {
    final day = (now ?? DateTime.now()).toUtc().day;
    return band.activities[day % band.activities.length];
  }

  /// Every milestone that should worry somebody when answered "not yet" in
  /// its own band — what the FHW screen filters on.
  static List<NcMilestone> get allFlags => [
    for (final band in bands) ...band.flags,
  ];
}
