/// The caregiver's whole world: one household, one family.
///
/// The role boundary is enforced by what this screen *lacks*. There is no
/// assessment form here, no measurements, no diagnosis — a caregiver gets
/// danger-sign triage (a structured "go now / see the nurse / continue care"
/// answer), their own family's schedule and referrals, a channel to report
/// barriers, and voice guidance. Every clinical write still goes through
/// [CareRepository], which would refuse a caregiver anyway; the screen simply
/// never offers what would be refused.
///
/// Nothing the caregiver does here enters the clinical record as clinical
/// data. The triage result is guidance, deliberately: the app must never turn
/// a mother's checklist into a diagnosis.
///
/// Four tabs in the order a caregiver's day actually runs:
///
/// **Home** — greeting, the family they care for, and the "check someone now"
/// button. This is where they land when they open the app to ask "is everyone
/// alright today?"
///
/// **My family** — the detail: every member with their last-known triage, the
/// visits coming up, the open referrals. Where to look when the health worker
/// calls and asks "is the family OK?"
///
/// **Check-in** — the danger-sign triage. Asks yes / no / not sure, gives one
/// of three recommendations: go now, see the CHW soon, or continue care.
///
/// **Profile** — the language they hear advice in, the sign-out, the help line.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/audio/audio_guide.dart';
import '../../core/audio/voice_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/reference/northern_ghana.dart';
import '../../data/repositories/care_repository.dart';
import '../../domain/engines/nurturing_care_engine.dart';
import '../../domain/entities/core.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../settings/voice_test_screen.dart';
import '../shared/app_image.dart';
import '../shared/ui.dart';

const _uuid = Uuid();

// ---------------------------------------------------------------- Tri-state

/// One answer to a danger-sign question.
///
/// The third state is the whole point: a mother who is "not sure" is not
/// lying, and a system that forces her into yes or no will get the wrong
/// answer. Counting "not sure" as caution is what makes the recommendation
/// a real three-way decision.
enum _SignAnswer { unset, yes, no, unsure }

extension on _SignAnswer {
  Color get colour => switch (this) {
    _SignAnswer.unset => AppColors.line,
    _SignAnswer.yes => AppColors.triageRed,
    _SignAnswer.no => AppColors.triageGreen,
    _SignAnswer.unsure => AppColors.triageAmber,
  };
}

/// The five screens of the caregiver Quick Home Check — master flow
/// [40-C] → [44-C]. They live inside one route so a caregiver never sees a
/// back stack: only forward, one calm step at a time, with the app bar back
/// arrow walking the stages in reverse.
enum _Stage { pick, questions, result, tellChw, watchFor }

/// The three outcomes the triage can end in.
enum _TriageVerdict { urgent, caution, fine }

extension on _TriageVerdict {
  String get headline => switch (this) {
    _TriageVerdict.urgent => 'Go to the health facility now',
    _TriageVerdict.caution => 'Visit your CHW soon',
    _TriageVerdict.fine => 'Continue routine care',
  };

  String get advice => switch (this) {
    _TriageVerdict.urgent =>
      'Danger signs are present. Do not wait until tomorrow. If the CHPS '
          'compound is closed, go to the health centre or district hospital.',
    _TriageVerdict.caution =>
      'Some answers are not clear. Bring this person to the clinic at the '
          'next scheduled contact and ask the nurse to look. Watch closely '
          'for the next two days.',
    _TriageVerdict.fine =>
      'None of the danger signs are present. Keep feeding, keep drinking, '
          'and check again tomorrow.',
  };

  Color get colour => switch (this) {
    _TriageVerdict.urgent => AppColors.triageRed,
    _TriageVerdict.caution => AppColors.triageAmber,
    _TriageVerdict.fine => AppColors.triageGreen,
  };
}

// ---------------------------------------------------------------- Caregiver

class CaregiverHome extends ConsumerStatefulWidget {
  const CaregiverHome({super.key});

  @override
  ConsumerState<CaregiverHome> createState() => _CaregiverHomeState();
}

class _CaregiverHomeState extends ConsumerState<CaregiverHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final linked = ref.watch(linkedHouseholdProvider);
    if (user == null) return const SizedBox.shrink();

    if (linked == null) {
      return Scaffold(
        appBar: AppBar(title: Text('CareBridge AI', style: AppType.title)),
        body: EmptyState(
          icon: Icons.family_restroom_rounded,
          title: 'Your family is not linked to this phone yet',
          message:
              'Ask the health worker at your CHPS compound to link your '
              'family. Once linked, you will see your family\u2019s visits, '
              'referrals and danger-sign guidance here.',
          action: OutlinedButton(
            onPressed: () => ref.read(sessionProvider.notifier).signOut(),
            child: const Text('Sign out'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('My family', style: AppType.title),
            const SizedBox(height: 2),
            Text(user.community, style: AppType.caption.copyWith(fontSize: 11.5)),
          ],
        ),
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _HomeTab(householdId: linked, onSwitch: (i) => setState(() => _tab = i)),
          _MyFamilyTab(householdId: linked),
          _CheckInTab(householdId: linked),
          _ProfileTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.family_restroom_outlined),
            activeIcon: Icon(Icons.family_restroom_rounded),
            label: 'My Family',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.health_and_safety_outlined),
            activeIcon: Icon(Icons.health_and_safety_rounded),
            label: 'Check-In',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline_rounded),
            activeIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- Home tab

class _HomeTab extends ConsumerWidget {
  const _HomeTab({required this.householdId, required this.onSwitch});

  final String householdId;
  final ValueChanged<int> onSwitch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final hour = DateTime.now().hour;
    final part = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final first = user?.fullName.split(' ').first ?? 'Friend';

    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        _CaregiverHero(greeting: '$part, $first'),
        const SizedBox(height: Gap.lg),
        _FamilySummary(householdId: householdId),
        const SizedBox(height: Gap.lg),
        // The one big action — master flow [13b] → [40-C]. A caregiver
        // opening the app to ask "is everyone alright?" goes straight into
        // the check, and lands back on this Home tab when it is done.
        GradientButton(
          label: 'Check on someone now',
          icon: Icons.health_and_safety_rounded,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _TriageScreen(
                householdId: householdId,
                onDone: () => onSwitch(0),
              ),
            ),
          ),
        ),
        const SizedBox(height: Gap.md),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _AudioGuideScreen(householdId: householdId),
            ),
          ),
          icon: const Icon(Icons.volume_up_rounded),
          label: const Text('Hear advice aloud'),
        ),
        const SizedBox(height: Gap.xs),
        // One-tap "test this phone's voice" link — the audit-the-capability
        // gate before relying on the audio card in a real visit.
        TextButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const VoiceTestScreen(),
            ),
          ),
          icon: const Icon(Icons.science_outlined, size: 16),
          label: const Text(
            'Test what this phone can speak',
            style: TextStyle(fontSize: 12.5),
          ),
        ),
      ],
    );
  }
}

/// The caregiver dashboard header — master flow [13b]. Deliberately lighter
/// and warmer than the FHW hero: this is a mother's app, not a worker's console.
class _CaregiverHero extends StatelessWidget {
  const _CaregiverHero({required this.greeting});

  final String greeting;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(Gap.radius),
        boxShadow: const [AppShadows.glow],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Gap.radiusSm),
            child: SizedBox(
              width: 88,
              height: 88,
              child: AppImage(src: AppImages.caregiverHero),
            ),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: AppType.headline.copyWith(
                    color: Colors.white,
                    fontSize: 24,
                  ),
                ),
                const SizedBox(height: Gap.xs),
                Text(
                  'How is everyone in your family today?',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FamilySummary extends ConsumerWidget {
  const _FamilySummary({required this.householdId});
  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final household = ref.watch(householdProvider(householdId));
    final members = ref.watch(householdMembersProvider(householdId));

    return SectionCard(
      title: 'Our family',
      icon: Icons.home_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          household.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => ErrorView(error: e),
            data: (h) => h == null
                ? const SizedBox.shrink()
                : Text(
                    '${h.name} · ${h.community}'
                    '${h.landmark == null || h.landmark!.isEmpty ? '' : ' · ${h.landmark}'}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.inkMuted,
                    ),
                  ),
          ),
          const SizedBox(height: Gap.md),
          members.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(error: e),
            data: (list) {
              if (list.isEmpty) {
                return const Text(
                  'No family members are registered yet. The health worker '
                  'will add everyone at the next clinic contact.',
                  style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
                );
              }
              return Column(
                children: [
                  for (final p in list) _MemberTile(person: p),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = ref.watch(latestAssessmentProvider(person.id));
    final check = ref.watch(latestHomeCheckProvider(person.id));

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Row(
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(Gap.radiusSm),
            ),
            child: Icon(
              person.effectiveClientType == ClientType.newborn
                  ? Icons.child_care_rounded
                  : person.effectiveClientType == ClientType.childUnderFive
                  ? Icons.emoji_people_rounded
                  : Icons.person_rounded,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.fullName,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                // The age is the standing fact; the family's last home check
                // joins it once there is one — fresher, and theirs.
                check.maybeWhen(
                  data: (c) => c == null
                      ? Text(
                          person.ageLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.inkMuted,
                          ),
                        )
                      : Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: c.verdict.colour,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: Gap.xs),
                            Flexible(
                              child: Text(
                                '${person.ageLabel} · checked at home '
                                '${_ago(c.checkedAt)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.inkMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                  orElse: () => Text(
                    person.ageLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          latest.maybeWhen(
            data: (a) => a == null
                ? const SizedBox.shrink()
                : TriageBadge(a.effectiveTriage, compact: true),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- My Family tab

class _MyFamilyTab extends ConsumerWidget {
  const _MyFamilyTab({required this.householdId});
  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        _ReferralsSection(),
        const SizedBox(height: Gap.md),
        _ContactsSection(householdId: householdId),
        const SizedBox(height: Gap.md),
        _BarrierCard(householdId: householdId),
        const SizedBox(height: Gap.xl),
      ],
    );
  }
}

// ------------------------------------------------------------- Check-In tab

/// The danger-sign check. This is the only "clinical" thing a caregiver can
/// run, and it is deliberately not an assessment: it asks what anyone can
/// observe — no counting breaths, no temperatures — and answers in one
/// sentence a grandmother could repeat.
class _CheckInTab extends ConsumerWidget {
  const _CheckInTab({required this.householdId});
  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        SectionCard(
          title: 'Is someone unwell?',
          subtitle:
              'Answer yes, no, or not sure for each sign. The app will tell '
              'you whether to go to the health facility now, see the CHW '
              'soon, or continue care at home.',
          icon: Icons.healing_rounded,
          accent: AppColors.triageRed,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.triageRed),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _TriageScreen(householdId: householdId),
                ),
              );
            },
            icon: const Icon(Icons.warning_amber_rounded),
            label: const Text('Check the danger signs'),
          ),
        ),
        const SizedBox(height: Gap.md),
        _RecentChecksCard(householdId: householdId),
        const SizedBox(height: Gap.md),
        _GrowPlayCard(householdId: householdId),
        const SizedBox(height: Gap.md),
        _AudioCard(householdId: householdId),
      ],
    );
  }
}

// ---------------------------------------------------------------- Profile tab

class _ProfileTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        SectionCard(
          title: 'Account',
          icon: Icons.badge_outlined,
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.accent.withValues(alpha: 0.18),
                child: Text(
                  user.initials,
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.fullName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Caregiver · ${user.phone}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.inkMuted,
                      ),
                    ),
                    Text(
                      'Guidance language: ${user.preferredLanguage}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),
        SectionCard(
          title: 'Help',
          subtitle:
              'This app is for one family. If you need help, ask the health '
              'worker at your CHPS compound, or call the district health line.',
          icon: Icons.support_agent_rounded,
          child: const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.call_rounded, color: AppColors.primary),
            title: Text(
              'Talk to your health worker',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              'Bring the phone to your next CHPS visit and they will help.',
            ),
          ),
        ),
        const SizedBox(height: Gap.lg),
        FilledButton.icon(
          onPressed: () => ref.read(sessionProvider.notifier).signOut(),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Hand the phone back'),
        ),
        const SizedBox(height: Gap.xl),
      ],
    );
  }
}

// ------------------------------------------------------------------ Triage

class _TriageScreen extends ConsumerStatefulWidget {
  const _TriageScreen({required this.householdId, this.onDone});

  final String householdId;

  /// Fired after the final "Back to home" on [44-C] — the dashboard uses it
  /// to land the caregiver on the Home tab, per the master flow's
  /// [44-C] → [13b] arrow.
  final VoidCallback? onDone;

  @override
  ConsumerState<_TriageScreen> createState() => _TriageScreenState();
}

class _TriageScreenState extends ConsumerState<_TriageScreen> {
  Person? _person;
  final Map<String, _SignAnswer> _answers = {};
  _Stage _stage = _Stage.pick;

  /// The family's report is saved to this phone exactly once per check run,
  /// the moment the recommendation is shown — back-navigating to the result
  /// must never write a second row.
  bool _checkSaved = false;

  static const _newbornSigns = [
    ('feed', 'Not breastfeeding or feeding well'),
    ('fast', 'Breathing fast or grunting'),
    ('fits', 'Fits or convulsions'),
    ('sleepy', 'Very sleepy or hard to wake'),
    ('temp', 'Very hot or very cold to touch'),
    ('yellow', 'Hands or feet look yellow'),
    ('cord', 'Cord is red, swollen or smells bad'),
    ('vomit', 'Vomiting everything'),
  ];

  static const _childSigns = [
    ('drink', 'Cannot drink or breastfeed'),
    ('vomit', 'Vomiting everything'),
    ('fits', 'Fits or convulsions'),
    ('sleepy', 'Very sleepy or hard to wake'),
    ('breath', 'Breathing fast or with difficulty'),
    ('blood', 'Blood in the stool'),
    ('thin', 'Becoming very thin, or swollen feet'),
    ('fever', 'Fever for more than three days'),
  ];

  static const _motherSigns = [
    ('bleed', 'Heavy bleeding'),
    ('head', 'Severe headache with blurred eyes'),
    ('fever', 'High fever'),
    ('pain', 'Severe belly pain'),
    ('fits', 'Fits or convulsions'),
    ('smell', 'Foul-smelling discharge'),
    ('move', 'Baby moving less than before (if pregnant)'),
    ('vomit', 'Vomiting everything'),
  ];

  List<(String, String)> get _signs {
    final type = _person?.effectiveClientType;
    return switch (type) {
      ClientType.newborn => _newbornSigns,
      ClientType.childUnderFive => _childSigns,
      _ => _motherSigns,
    };
  }

  AudioTopic get _topic {
    final type = _person?.effectiveClientType;
    return switch (type) {
      ClientType.newborn => AudioTopic.newbornDangerSigns,
      ClientType.childUnderFive => AudioTopic.childDangerSigns,
      _ => AudioTopic.motherDangerSigns,
    };
  }

  _TriageVerdict _verdict() {
    final yes = _answers.values.where((a) => a == _SignAnswer.yes).length;
    final unsure =
        _answers.values.where((a) => a == _SignAnswer.unsure).length;
    if (yes > 0) return _TriageVerdict.urgent;
    if (unsure >= 2) return _TriageVerdict.caution;
    return _TriageVerdict.fine;
  }

  void _set(String key, _SignAnswer value) => setState(() {
    _answers[key] = value;
  });

  /// Keeps the family's report on this device. Deliberately fire-and-forget:
  /// a save hiccup must never stand between a mother and the advice "go to
  /// the facility now". The record is local-only anyway — nothing leaves
  /// the phone until the family says so.
  Future<void> _saveHomeCheck() async {
    if (_checkSaved) return;
    final user = ref.read(currentUserProvider);
    final person = _person;
    if (user == null || person == null) return;
    _checkSaved = true;

    final report = HomeCheck(
      id: _uuid.v4(),
      householdId: widget.householdId,
      personId: person.id,
      clientType: person.effectiveClientType,
      verdict: switch (_verdict()) {
        _TriageVerdict.urgent => HomeCheckVerdict.urgent,
        _TriageVerdict.caution => HomeCheckVerdict.caution,
        _TriageVerdict.fine => HomeCheckVerdict.fine,
      },
      yesSigns: _signs
          .where((s) => _answers[s.$1] == _SignAnswer.yes)
          .map((s) => s.$2)
          .toList(growable: false),
      unsureSigns: _signs
          .where((s) => _answers[s.$1] == _SignAnswer.unsure)
          .map((s) => s.$2)
          .toList(growable: false),
      checkedBy: user.id,
      checkedAt: DateTime.now(),
    );

    try {
      await ref.read(careRepositoryProvider).recordHomeCheck(user, report);
      ref.invalidate(householdHomeChecksProvider);
      ref.invalidate(latestHomeCheckProvider(person.id));
    } catch (_) {
      if (mounted) _checkSaved = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final members = ref.watch(householdMembersProvider(widget.householdId));
    final household = ref.watch(householdProvider(widget.householdId));

    // The route guard already checked this; checking again is cheap and means
    // the screen cannot be reached by any future navigation change.
    if (user == null || !user.can(Permission.runCaregiverTriage)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Danger-sign check')),
        body: const AccessDeniedView(
          message: 'The danger-sign check is for caregiver accounts.',
        ),
      );
    }

    return PopScope(
      // The system back gesture walks the five screens in reverse instead of
      // dropping the caregiver out of the check entirely.
      canPop: _stage == _Stage.pick,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _stage == _Stage.pick
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: _back,
                ),
          title: Text(
            switch (_stage) {
              _Stage.pick => 'Who are you checking?',
              _Stage.questions => 'What have you noticed?',
              _Stage.result => 'What to do now',
              _Stage.tellChw => 'Tell your CHW',
              _Stage.watchFor => 'Watch for these at home',
            },
          ),
        ),
        body: members.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorView(error: e),
          data: (list) => switch (_stage) {
            _Stage.pick => _buildPersonPicker(list),
            _Stage.questions => _buildChecklist(),
            _Stage.result => _buildResult(household.valueOrNull),
            _Stage.tellChw => _buildTellChw(),
            _Stage.watchFor => _buildWatchFor(),
          },
        ),
      ),
    );
  }

  void _back() => setState(() {
    _stage = switch (_stage) {
      _Stage.questions => _Stage.pick,
      _Stage.result => _Stage.questions,
      _Stage.tellChw || _Stage.watchFor => _Stage.result,
      _Stage.pick => _Stage.pick,
    };
  });

  void _restart() => setState(() {
    _stage = _Stage.pick;
    _person = null;
    _answers.clear();
    _checkSaved = false;
  });

  /// [44-C] → [13b]: stop any audio, leave the check, and let the dashboard
  /// land the caregiver on the Home tab.
  void _finish() {
    AudioGuide.stop();
    Navigator.of(context).pop();
    widget.onDone?.call();
  }

  /// [40-C] Who are you checking on? — the caregiver's own household, each
  /// member wearing the same category illustration used across the app.
  Widget _buildPersonPicker(List<Person> list) {
    if (list.isEmpty) {
      return const EmptyState(
        icon: Icons.person_off_outlined,
        title: 'No family members yet',
        message:
            'The health worker will register everyone at the next visit. If '
            'someone is seriously ill now, go straight to the health '
            'facility.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        const Text(
          'Choose who you are checking today.',
          style: TextStyle(
            fontSize: 14.5,
            color: AppColors.inkMuted,
            height: 1.4,
          ),
        ),
        const SizedBox(height: Gap.md),
        for (final p in list)
          _PersonCard(
            person: p,
            onTap: () => setState(() {
              _person = p;
              _answers.clear();
              _stage = _Stage.questions;
            }),
          ),
      ],
    );
  }

  /// [41-C] The Quick Home Check — one adaptive screen, voice-first: every
  /// question carries a speaker that plays it aloud *before* the caregiver
  /// answers. That is what makes it genuinely voice-first, not just
  /// voice-output-at-the-end.
  Widget _buildChecklist() {
    final person = _person!;
    final language =
        ref.read(currentUserProvider)?.preferredLanguage ?? 'English';
    final answered =
        _signs.where((s) => _answers[s.$1] != _SignAnswer.unset).length;
    final allAnswered = answered == _signs.length;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Gap.lg),
            children: [
              Container(
                padding: const EdgeInsets.all(Gap.md),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(Gap.radiusSm),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.volume_up_rounded,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      child: Text(
                        'Tap the speaker beside each question to hear it in '
                        '$language before you answer.',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.md),
              Text(
                'About ${person.fullName} — tap YES, NO, or NOT SURE for each '
                'sign.',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.inkMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: Gap.md),
              for (final (key, label) in _signs)
                _SignQuestionTile(
                  question: label,
                  answer: _answers[key] ?? _SignAnswer.unset,
                  onChanged: (v) => _set(key, v),
                  onPlay: () => _playQuestion(key, language),
                ),
              const SizedBox(height: Gap.md),
              const Text(
                'These questions are about what anyone can see. They do not '
                'replace the health worker\u2019s examination.',
                style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
              ),
            ],
          ),
        ),
        SafeArea(
          minimum: const EdgeInsets.all(Gap.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$answered of ${_signs.length} signs answered',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: allAnswered
                      ? AppColors.primary
                      : AppColors.inkMuted,
                ),
              ),
              const SizedBox(height: Gap.sm),
              FilledButton(
                onPressed: allAnswered
                    ? () {
                        setState(() => _stage = _Stage.result);
                        _saveHomeCheck();
                      }
                    : null,
                child: const Text('What should I do?'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResult(Household? household) {
    final verdict = _verdict();
    final chosenYes = _signs
        .where((s) => _answers[s.$1] == _SignAnswer.yes)
        .map((s) => s.$2)
        .toList(growable: false);
    final chosenUnsure = _signs
        .where((s) => _answers[s.$1] == _SignAnswer.unsure)
        .map((s) => s.$2)
        .toList(growable: false);
    final walk = household?.walkingMinutesToFacility;

    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        // ------------------------- Verdict banner
        Container(
          padding: const EdgeInsets.all(Gap.lg),
          decoration: BoxDecoration(
            color: verdict.colour.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(Gap.radius),
            border: Border.all(
              color: verdict.colour.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_iconFor(verdict), color: verdict.colour, size: 28),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(
                      verdict.headline,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: verdict.colour,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.sm),
              Text(
                '${verdict.advice}${verdict == _TriageVerdict.urgent && walk != null
                    ? ' The facility is about $walk minutes on foot.'
                    : ''}',
                style: const TextStyle(fontSize: 14, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),

        // ------------------------- Three big action buttons
        // Master flow [42-C]: red and amber both route through "Tell your
        // CHW" [43-C]; green goes straight to the home-watch card [44-C].
        _RecommendationActions(
          verdict: verdict,
          language:
              ref.read(currentUserProvider)?.preferredLanguage ?? 'English',
          onPrimary: () => setState(() {
            _stage = verdict == _TriageVerdict.fine
                ? _Stage.watchFor
                : _Stage.tellChw;
          }),
          onHearAloud: _playTopic,
          onCheckAnother: _restart,
        ),
        const SizedBox(height: Gap.md),

        // ------------------------- Reasons the recommendation rests on
        if (chosenYes.isNotEmpty)
          SectionCard(
            title: 'Signs you said YES to',
            icon: Icons.campaign_outlined,
            accent: AppColors.triageRed,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in chosenYes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.xs),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.arrow_right_rounded,
                          color: AppColors.triageRed,
                        ),
                        Expanded(
                          child: Text(
                            s,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Text(
                  'Say when each sign started, and what has been eaten, '
                  'drunk or vomited since.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                ),
              ],
            ),
          ),
        if (chosenUnsure.isNotEmpty) ...[
          const SizedBox(height: Gap.md),
          SectionCard(
            title: 'Signs you were not sure about',
            icon: Icons.help_outline_rounded,
            accent: AppColors.triageAmber,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in chosenUnsure)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.xs),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.arrow_right_rounded,
                          color: AppColors.triageAmber,
                        ),
                        Expanded(
                          child: Text(s, style: const TextStyle(fontSize: 14)),
                        ),
                      ],
                    ),
                  ),
                const Text(
                  'These are the signs the nurse should look at first.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  IconData _iconFor(_TriageVerdict v) => switch (v) {
    _TriageVerdict.urgent => Icons.local_hospital_rounded,
    _TriageVerdict.caution => Icons.medical_services_rounded,
    _TriageVerdict.fine => Icons.check_circle_rounded,
  };

  /// [43-C] Tell your CHW. A caregiver never dispatches a clinical referral —
  /// that authority stays with the FHW. What she gets instead is her own
  /// words, pre-filled from what she just answered, sendable from her own
  /// phone — or a plain prompt to walk to the compound.
  Widget _buildTellChw() {
    final user = ref.read(currentUserProvider);
    final person = _person!;
    final message = _chwMessage(user, person, _verdict());

    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        SectionCard(
          title: 'Message for your CHW',
          subtitle:
              'Filled in from what you just answered. Read it before you '
              'send — they are your words, not the app\u2019s.',
          icon: Icons.mark_chat_read_rounded,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Gap.md),
            decoration: BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(Gap.radiusSm),
              border: Border.all(color: AppColors.line),
            ),
            child: Text(
              message,
              style: const TextStyle(fontSize: 13.5, height: 1.55),
            ),
          ),
        ),
        const SizedBox(height: Gap.md),
        const Text(
          'Send it from your own phone, or walk to the CHPS compound and '
          'show this screen. You are only telling the nurse what you saw — '
          'she decides what happens next.',
          style: TextStyle(
            fontSize: 12.5,
            color: AppColors.inkMuted,
            height: 1.45,
          ),
        ),
        const SizedBox(height: Gap.lg),
        GradientButton(
          label: 'Open your SMS app',
          icon: Icons.sms_outlined,
          onPressed: () => _sendSms(message),
        ),
        const SizedBox(height: Gap.sm),
        OutlinedButton.icon(
          onPressed: () => _copyMessage(message),
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Copy the message'),
        ),
        const SizedBox(height: Gap.sm),
        FilledButton.icon(
          onPressed: () => setState(() => _stage = _Stage.watchFor),
          icon: const Icon(Icons.directions_walk_rounded),
          label: const Text('I will go in person'),
        ),
      ],
    );
  }

  /// [44-C] What to watch for at home — shown on every outcome, even green,
  /// because the return-immediately list is the single habit that saves the
  /// most mothers and children.
  Widget _buildWatchFor() {
    final person = _person!;
    final verdict = _verdict();
    final image = switch (person.effectiveClientType) {
      ClientType.newborn => AppImages.cardNewborn,
      ClientType.childUnderFive => AppImages.cardChild,
      _ => AppImages.cardMother,
    };

    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(Gap.radius),
          child: SizedBox(height: 150, child: AppImage(src: image)),
        ),
        const SizedBox(height: Gap.lg),
        Container(
          padding: const EdgeInsets.all(Gap.lg),
          decoration: BoxDecoration(
            color: AppColors.triageRedBg,
            borderRadius: BorderRadius.circular(Gap.radius),
            border: const Border(
              left: BorderSide(color: AppColors.triageRed, width: 5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: AppColors.triageRed,
                    size: 24,
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(
                      'Come back immediately if\u2026',
                      style: AppType.title.copyWith(
                        color: AppColors.triageRed,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.md),
              for (final (_, label) in _signs)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.arrow_right_rounded,
                        color: AppColors.triageRed,
                      ),
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (verdict == _TriageVerdict.fine) ...[
          const SizedBox(height: Gap.md),
          Container(
            padding: const EdgeInsets.all(Gap.md),
            decoration: BoxDecoration(
              color: AppColors.triageGreen.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(Gap.radiusSm),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: AppColors.triageGreen),
                SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    'None of these signs are present today. Keep feeding, '
                    'keep drinking, and check again tomorrow.',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.triageGreen,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: Gap.xl),
        GradientButton(
          label: 'Back to home',
          icon: Icons.home_rounded,
          onPressed: _finish,
        ),
      ],
    );
  }

  /// The caregiver's own words for the CHW, assembled from her answers.
  /// Never a placeholder — every line comes from something she tapped.
  String _chwMessage(AppUser? user, Person person, _TriageVerdict verdict) {
    final yes = _signs
        .where((s) => _answers[s.$1] == _SignAnswer.yes)
        .map((s) => s.$2)
        .toList(growable: false);
    final unsure = _signs
        .where((s) => _answers[s.$1] == _SignAnswer.unsure)
        .map((s) => s.$2)
        .toList(growable: false);

    final lines = <String>[
      'CareBridge AI - message for the CHW',
      if (user != null) 'From: ${user.fullName}',
      'About: ${person.fullName} (${person.ageLabel})',
      if (yes.isNotEmpty) 'Signs I noticed: ${yes.join('; ')}',
      if (unsure.isNotEmpty) 'Not sure about: ${unsure.join('; ')}',
      'Advice the app gave: ${verdict.headline}.',
    ];
    return lines.join('\n');
  }

  /// Hands the message to the phone's SMS app. If this device cannot open
  /// one — a tablet, the web preview — the message is copied instead, so it
  /// is never lost.
  Future<void> _sendSms(String message) async {
    final uri = Uri.parse('sms:?body=${Uri.encodeComponent(message)}');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return;
      }
    } catch (_) {
      // Fall through to the clipboard.
    }
    if (!mounted) return;
    _copyMessage(message);
  }

  void _copyMessage(String message) {
    Clipboard.setData(ClipboardData(text: message));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Message copied. Paste it into any message app.'),
      ),
    );
  }

  /// One question, heard aloud. Falls back to system TTS, then the Hausa
  /// bridge, then the on-screen text — care never waits on an MP3.
  Future<void> _playQuestion(String key, String language) async {
    final outcome = await AudioGuide.playQuestion(key, language);
    if (!mounted) return;
    if (outcome.source == VoiceSource.readAloud) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'The $language recording of this question is not on this phone '
            'yet. Read it aloud, or ask someone to.',
          ),
        ),
      );
    }
  }

  Future<void> _playTopic() async {
    final user = ref.read(currentUserProvider);
    final outcome = await AudioGuide.play(
      _topic,
      user?.preferredLanguage ?? 'English',
    );
    if (!mounted) return;
    if (outcome.source == VoiceSource.readAloud) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'The ${user?.preferredLanguage ?? 'local'} recording is not on '
            'this phone yet. The words are on the screen — read them aloud '
            'or ask someone to.',
          ),
        ),
      );
    }
  }
}

// ----------------------------------------------------- Tri-state question tile

/// [40-C] One family member, wearing the category illustration used across
/// the whole app — the same three pictures a health worker sees.
class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person, required this.onTap});

  final Person person;
  final VoidCallback onTap;

  String get _image => switch (person.effectiveClientType) {
    ClientType.newborn => AppImages.cardNewborn,
    ClientType.childUnderFive => AppImages.cardChild,
    _ => AppImages.cardMother,
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(Gap.radiusSm),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(Gap.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Gap.radiusSm),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Gap.radiusXs),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: AppImage(src: _image),
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.fullName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${person.ageLabel} · '
                        '${person.effectiveClientType.label}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.inkMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.inkFaint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SignQuestionTile extends StatelessWidget {
  const _SignQuestionTile({
    required this.question,
    required this.answer,
    required this.onChanged,
    required this.onPlay,
  });

  final String question;
  final _SignAnswer answer;
  final ValueChanged<_SignAnswer> onChanged;

  /// Voice-first, master flow [41-C]: hear the question before answering it.
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Container(
        padding: const EdgeInsets.all(Gap.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Gap.radiusSm),
          border: Border.all(
            color: answer == _SignAnswer.unset
                ? AppColors.line
                : answer.colour,
            width: answer == _SignAnswer.unset ? 1 : 1.6,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    question,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
                // The speaker is not a decoration — it is the first thing a
                // non-reading caregiver should touch.
                SizedBox(
                  width: 40,
                  height: 40,
                  child: IconButton(
                    tooltip: 'Hear this question aloud',
                    padding: EdgeInsets.zero,
                    iconSize: 26,
                    onPressed: onPlay,
                    icon: const Icon(
                      Icons.volume_up_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            Row(
              children: [
                Expanded(
                  child: _AnswerChip(
                    label: 'YES',
                    icon: Icons.check_rounded,
                    selected: answer == _SignAnswer.yes,
                    colour: AppColors.triageRed,
                    onTap: () => onChanged(_SignAnswer.yes),
                  ),
                ),
                const SizedBox(width: Gap.xs),
                Expanded(
                  child: _AnswerChip(
                    label: 'NO',
                    icon: Icons.close_rounded,
                    selected: answer == _SignAnswer.no,
                    colour: AppColors.triageGreen,
                    onTap: () => onChanged(_SignAnswer.no),
                  ),
                ),
                const SizedBox(width: Gap.xs),
                Expanded(
                  child: _AnswerChip(
                    label: 'NOT SURE',
                    icon: Icons.help_rounded,
                    selected: answer == _SignAnswer.unsure,
                    colour: AppColors.triageAmber,
                    onTap: () => onChanged(_SignAnswer.unsure),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AnswerChip extends StatelessWidget {
  const _AnswerChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.colour,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? colour : colour.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: selected ? Colors.white : colour),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : colour,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------ Three-button recommendation

class _RecommendationActions extends StatelessWidget {
  const _RecommendationActions({
    required this.verdict,
    required this.language,
    required this.onPrimary,
    required this.onHearAloud,
    required this.onCheckAnother,
  });

  final _TriageVerdict verdict;

  /// The caregiver's guidance language, named on the audio button so she
  /// knows which recording she is about to hear.
  final String language;
  final VoidCallback onPrimary;
  final VoidCallback onHearAloud;
  final VoidCallback onCheckAnother;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The one action the verdict picks — full-width, the colour of the
        // verdict, so the eye does not have to search.
        _ActionButton(
          label: switch (verdict) {
            _TriageVerdict.urgent => 'Go to Clinic Now',
            _TriageVerdict.caution => 'Visit Your CHW Soon',
            _TriageVerdict.fine => 'Continue Routine Care',
          },
          icon: switch (verdict) {
            _TriageVerdict.urgent => Icons.local_hospital_rounded,
            _TriageVerdict.caution => Icons.medical_services_rounded,
            _TriageVerdict.fine => Icons.check_circle_rounded,
          },
          colour: verdict.colour,
          filled: true,
          onTap: onPrimary,
        ),
        const SizedBox(height: Gap.sm),
        // Master flow [42-C]: the full recommendation read aloud, prominent.
        _ActionButton(
          label: 'Play $language audio',
          icon: Icons.volume_up_rounded,
          colour: AppColors.primary,
          filled: false,
          onTap: onHearAloud,
        ),
        const SizedBox(height: Gap.sm),
        TextButton.icon(
          onPressed: onCheckAnother,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Check someone else'),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.colour,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color colour;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return filled
        ? FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: colour,
              minimumSize: const Size.fromHeight(60),
            ),
            onPressed: onTap,
            icon: Icon(icon, size: 22),
            label: Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          )
        : OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: colour,
              side: BorderSide(color: colour, width: 1.4),
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: onTap,
            icon: Icon(icon, size: 20),
            label: Text(
              label,
              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
            ),
          );
  }
}

// ----------------------------------------------------------------- Referrals

class _ReferralsSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final referrals = ref.watch(openReferralsProvider);

    return referrals.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => ErrorView(error: e),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return SectionCard(
          title: 'Referrals to complete',
          subtitle:
              'Show the code at the facility gate. It tells them why you '
              'were sent, before you say a word.',
          icon: Icons.local_hospital_outlined,
          child: Column(
            children: [for (final r in list) _ReferralTile(referral: r)],
          ),
        );
      },
    );
  }
}

class _ReferralTile extends ConsumerWidget {
  const _ReferralTile({required this.referral});

  final Referral referral;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = ref.watch(personProvider(referral.personId));

    return Container(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.md,
                  vertical: Gap.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  referral.referenceCode,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  person.valueOrNull?.fullName ?? '…',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          Text(
            referral.reason,
            style: const TextStyle(fontSize: 13.5, height: 1.35),
          ),
          const SizedBox(height: Gap.xs),
          Text(
            'Go to: ${referral.facilityName} · ${referral.urgency.label} · '
                '${referral.status.label}',
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.inkMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Contacts

class _ContactsSection extends ConsumerWidget {
  const _ContactsSection({required this.householdId});

  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(householdContactsProvider(householdId));

    return contacts.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => ErrorView(error: e),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return SectionCard(
          title: 'Appointments coming up',
          subtitle:
              'The clinic plans to see your family on these days. '
              'Arriving on the day saves a second trip.',
          icon: Icons.event_available_rounded,
          child: Column(
            children: [
              for (final c in list) _ContactTile(contact: c),
            ],
          ),
        );
      },
    );
  }
}

class _ContactTile extends ConsumerWidget {
  const _ContactTile({required this.contact});

  final ScheduledContact contact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = ref.watch(personProvider(contact.personId));
    final overdue = contact.daysUntilDue < 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.sm,
              vertical: Gap.xs,
            ),
            decoration: BoxDecoration(
              color: overdue ? AppColors.triageAmberBg : AppColors.primaryLight,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              DateFormat('d MMM').format(contact.dueDate),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: overdue ? AppColors.triageAmber : AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.purpose,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${person.valueOrNull?.fullName ?? ''} · '
                  '${_dueLabel(contact.daysUntilDue)}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: overdue
                        ? AppColors.triageAmber
                        : AppColors.inkMuted,
                    fontWeight: overdue ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _dueLabel(int days) => switch (days) {
    0 => 'today',
    1 => 'tomorrow',
    > 1 => 'in $days days',
    -1 => 'yesterday — please attend soon',
    _ => '${-days} days overdue',
  };
}

// ------------------------------------------------------------------- Barriers

/// The channel through which the family tells the system why care is hard.
/// A caregiver's "no transport money" is more reliable than any CHO guess,
/// which is why both roles hold [Permission.recordBarrier].
class _BarrierCard extends ConsumerWidget {
  const _BarrierCard({required this.householdId});

  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final history = ref.watch(barrierHistoryProvider(householdId));

    if (user == null || !user.can(Permission.recordBarrier)) {
      return const SizedBox.shrink();
    }

    return SectionCard(
      title: 'What makes care difficult?',
      subtitle:
          'Tell us once and we stop asking you to do the impossible. Your '
          'answer goes to your health worker.',
      icon: Icons.report_problem_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          history.maybeWhen(
            data: (list) => list.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: Gap.md),
                    child: Text(
                      'You have told us about: '
                      '${list.map((b) => b.label).toSet().join(', ')}.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.inkMuted,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
          OutlinedButton.icon(
            onPressed: () => _report(context, ref),
            icon: const Icon(Icons.add_comment_outlined),
            label: const Text('Report a difficulty'),
          ),
        ],
      ),
    );
  }

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BarrierSheet(householdId: householdId),
    );
    if (saved == true) {
      ref.invalidate(barrierHistoryProvider);
    }
  }
}

class _BarrierSheet extends ConsumerStatefulWidget {
  const _BarrierSheet({required this.householdId});

  final String householdId;

  @override
  ConsumerState<_BarrierSheet> createState() => _BarrierSheetState();
}

class _BarrierSheetState extends ConsumerState<_BarrierSheet> {
  final Set<CareBarrier> _chosen = {};
  final _notes = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    if (_chosen.isEmpty) {
      setState(() => _error = 'Choose at least one difficulty.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final report = BarrierReport(
      id: _uuid.v4(),
      householdId: widget.householdId,
      barriers: _chosen.toList(growable: false),
      recordedBy: user.id,
      recordedAt: DateTime.now(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );

    try {
      await ref.read(careRepositoryProvider).recordBarrier(user, report);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AccessDenied catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      left: Gap.lg,
      right: Gap.lg,
      bottom: MediaQuery.of(context).viewInsets.bottom + Gap.lg,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'What stood in the way?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: Gap.sm),
          const Text(
            'Choose everything that applies. There are no wrong answers and '
            'nothing here is a complaint against you.',
            style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
          ),
          const SizedBox(height: Gap.md),
          for (final barrier in CareBarrier.values)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _chosen.contains(barrier),
              title: Text(
                barrier.label,
                style: const TextStyle(fontSize: 14.5),
              ),
              onChanged: (v) => setState(() {
                v == true ? _chosen.add(barrier) : _chosen.remove(barrier);
              }),
            ),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Anything else (optional)',
            ),
          ),
          const SizedBox(height: Gap.md),
          if (_error != null) ...[
            Text(
              _error!,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.triageRed,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Gap.md),
          ],
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.send_rounded),
            label: Text(_busy ? 'Sending…' : 'Tell the health worker'),
          ),
          const SizedBox(height: Gap.lg),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------- Recent checks

/// The danger-sign checks this family has already run. Saved on this phone,
/// newest first, so "has anything changed since the last contact?" has an
/// answer even when the network does not.
class _RecentChecksCard extends ConsumerWidget {
  const _RecentChecksCard({required this.householdId});
  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checks = ref.watch(householdHomeChecksProvider(householdId));

    return checks.maybeWhen(
      data: (list) => list.isEmpty
          ? const SizedBox.shrink()
          : SectionCard(
              title: 'Checks you have done',
              subtitle:
                  'Saved on this phone. Show this list to the health worker '
                  'when you arrive — it tells them what you noticed.',
              icon: Icons.history_rounded,
              child: Column(
                children: [
                  for (final c in list.take(3)) _RecentCheckTile(check: c),
                ],
              ),
            ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _RecentCheckTile extends ConsumerWidget {
  const _RecentCheckTile({required this.check});

  final HomeCheck check;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = ref.watch(personProvider(check.personId));

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: check.verdict.colour,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.valueOrNull?.fullName ?? '…',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${check.verdict.label} · ${_ago(check.checkedAt)}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: check.verdict == HomeCheckVerdict.fine
                        ? AppColors.inkMuted
                        : check.verdict.colour,
                    fontWeight: check.verdict == HomeCheckVerdict.fine
                        ? FontWeight.w500
                        : FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (check.yesSigns.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.sm,
                vertical: Gap.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.triageRedBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${check.yesSigns.length} ${check.yesSigns.length == 1 ? 'sign' : 'signs'}',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.triageRed,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------- Audio guidance

class _AudioCard extends ConsumerWidget {
  const _AudioCard({required this.householdId});
  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SectionCard(
      title: 'Listen to health advice',
      subtitle:
          'Short messages about danger signs and feeding, written to be '
          'heard. Play them to the whole family.',
      icon: Icons.record_voice_over_rounded,
      child: OutlinedButton.icon(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _AudioGuideScreen(householdId: householdId),
            ),
          );
        },
        icon: const Icon(Icons.play_circle_outline_rounded),
        label: const Text('Open the voice guide'),
      ),
    );
  }
}

class _AudioGuideScreen extends ConsumerStatefulWidget {
  const _AudioGuideScreen({required this.householdId});

  final String householdId;

  @override
  ConsumerState<_AudioGuideScreen> createState() => _AudioGuideScreenState();
}

class _AudioGuideScreenState extends ConsumerState<_AudioGuideScreen> {
  String? _language;
  String? _playing;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final household = ref.watch(householdProvider(widget.householdId));
    final region = household.valueOrNull?.region ?? user?.region ?? 'Northern Region';
    final languages = NorthernGhana.languagesOf(region);
    final language = _language ?? user?.preferredLanguage ?? 'English';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice guide'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Gap.md),
            child: DropdownButton<String>(
              value: languages.contains(language) ? language : languages.last,
              underline: const SizedBox.shrink(),
              items: [
                for (final l in languages)
                  DropdownMenuItem(value: l, child: Text(l)),
              ],
              onChanged: (l) => setState(() => _language = l),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: [
          for (final topic in AudioTopic.values)
            Card(
              margin: const EdgeInsets.only(bottom: Gap.md),
              child: Padding(
                padding: const EdgeInsets.all(Gap.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            topic.title,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Play aloud',
                          iconSize: 34,
                          onPressed: () => _play(topic, language),
                          icon: Icon(
                            _playing == topic.id
                                ? Icons.stop_circle_rounded
                                : Icons.play_circle_fill_rounded,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Gap.xs),
                    Text(
                      topic.script,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const Text(
            'Recordings in local languages are added to this phone by your '
            'health facility. Until then, the words above can be read aloud '
            'in any language.',
            style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
          ),
        ],
      ),
    );
  }

  Future<void> _play(AudioTopic topic, String language) async {
    if (_playing == topic.id) {
      await AudioGuide.stop();
      if (mounted) setState(() => _playing = null);
      return;
    }
    final outcome = await AudioGuide.play(topic, language);
    if (!mounted) return;
    setState(() => _playing =
        outcome.source == VoiceSource.readAloud ? null : topic.id);
    if (outcome.source == VoiceSource.readAloud) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'The $language recording is not on this phone yet. Read the '
            'words aloud instead.',
          ),
        ),
      );
    }
  }
}

// ------------------------------------------------------------------- Helpers

extension on HomeCheckVerdict {
  Color get colour => switch (this) {
    HomeCheckVerdict.urgent => AppColors.triageRed,
    HomeCheckVerdict.caution => AppColors.triageAmber,
    HomeCheckVerdict.fine => AppColors.triageGreen,
  };
}

/// "today", "yesterday", or "3 days ago" — the way a family talks about
/// time, never a date format. Older than a week falls back to the date.
String _ago(DateTime when) {
  final days = DateTime.now().dateOnly.difference(when.dateOnly).inDays;
  return switch (days) {
    <= 0 => 'today',
    1 => 'yesterday',
    < 7 => '$days days ago',
    _ => DateFormat('d MMM').format(when),
  };
}

// ------------------------------------------------------- Nurturing care

/// Grow and play — the nurturing-care half of the caregiver app.
///
/// Growing is more than weight: the WHO/UNICEF Care for Child Development
/// package says what a child should be doing at each age, and what play
/// builds it. This card offers both, in the family's own words, using only
/// what is already in the compound. It appears only when the household has
/// a child inside the tracked window (birth to five years).
class _GrowPlayCard extends ConsumerWidget {
  const _GrowPlayCard({required this.householdId});

  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(householdMembersProvider(householdId));

    return members.maybeWhen(
      data: (people) {
        final children = people
            .where((p) => NurturingCareEngine.bandFor(p.ageInMonths) != null)
            .toList(growable: false);
        if (children.isEmpty) return const SizedBox.shrink();

        return SectionCard(
          title: 'Grow and play',
          subtitle:
              'Growing is more than weight. Answer a few questions about '
              'what your child can do, and get a play idea for today — '
              'free, with things you already have.',
          icon: Icons.child_care_rounded,
          child: Column(
            children: [
              for (final child in children) _GrowChildTile(child: child),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _GrowChildTile extends StatelessWidget {
  const _GrowChildTile({required this.child});

  final Person child;

  @override
  Widget build(BuildContext context) {
    final band = NurturingCareEngine.bandFor(child.ageInMonths)!;

    return Container(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  child.fullName,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${child.ageLabel} · ${band.label}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          Text(
            'Play today: ${NurturingCareEngine.activityToday(band)}',
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.inkMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: Gap.sm),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _MilestoneScreen(
                  householdId: child.householdId,
                  personId: child.id,
                ),
              ),
            ),
            icon: const Icon(Icons.checklist_rounded, size: 18),
            label: const Text('Check the milestones'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, Gap.tapTarget),
            ),
          ),
        ],
      ),
    );
  }
}

/// The milestone check — nurturing care's answer to the danger-sign check.
///
/// Same calm pattern: one child, a short list of questions phrased as "can
/// they do this?", two answers ("yes" and "not yet" — never "wrong"), and a
/// result that routes, not diagnoses. "Show the health worker" is the only
/// red this screen produces, and it means exactly what it says.
class _MilestoneScreen extends ConsumerStatefulWidget {
  const _MilestoneScreen({required this.householdId, required this.personId});

  final String householdId;
  final String personId;

  @override
  ConsumerState<_MilestoneScreen> createState() => _MilestoneScreenState();
}

class _MilestoneScreenState extends ConsumerState<_MilestoneScreen> {
  /// True per milestone the child can do; false means "not yet". Missing key
  /// means unanswered — the save button stays closed until every question
  /// has an answer, exactly like the danger-sign checklist.
  final Map<String, bool> _answers = {};
  bool _saved = false;
  bool _showResult = false;

  @override
  Widget build(BuildContext context) {
    final personAsync = ref.watch(personProvider(widget.personId));

    return Scaffold(
      appBar: AppBar(title: const Text('Grow and play')),
      body: personAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e),
        data: (person) {
          if (person == null) {
            return const EmptyState(
              icon: Icons.child_care_rounded,
              title: 'Child not found',
              message: 'This child is no longer on this phone.',
            );
          }
          final band = NurturingCareEngine.bandFor(person.ageInMonths);
          if (band == null) {
            return const EmptyState(
              icon: Icons.cake_outlined,
              title: 'We need the child\u2019s age',
              message:
                  'Milestone checks work from birth to five years. Ask the '
                  'health worker to record the child\u2019s date of birth.',
            );
          }
          return _showResult
              ? _buildResult(person, band)
              : _buildQuestions(person, band);
        },
      ),
    );
  }

  Widget _buildQuestions(Person person, NcAgeBand band) {
    final answered =
        band.milestones.where((m) => _answers.containsKey(m.id)).length;
    final allAnswered = answered == band.milestones.length;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Gap.lg),
            children: [
              Text(
                'About ${person.fullName} (${band.label}). For each one, '
                'answer what you see most days. "Not yet" is never wrong — '
                'children grow at their own pace.',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.inkMuted,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: Gap.md),
              for (final m in band.milestones) _MilestoneQuestionTile(
                milestone: m,
                answer: _answers[m.id],
                onChanged: (v) => setState(() => _answers[m.id] = v),
              ),
              const SizedBox(height: Gap.md),
              const Text(
                'This is your report, not a diagnosis. The health worker '
                'examines; you tell them what you see.',
                style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
              ),
            ],
          ),
        ),
        SafeArea(
          minimum: const EdgeInsets.all(Gap.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$answered of ${band.milestones.length} answered',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: allAnswered
                      ? AppColors.primary
                      : AppColors.inkMuted,
                ),
              ),
              const SizedBox(height: Gap.sm),
              FilledButton(
                onPressed: allAnswered
                    ? () {
                        setState(() => _showResult = true);
                        _save(person, band);
                      }
                    : null,
                child: const Text('Show me the result'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResult(Person person, NcAgeBand band) {
    final notYet = band.milestones
        .where((m) => _answers[m.id] == false)
        .toList(growable: false);
    final flags = notYet.where((m) => m.isFlag).toList(growable: false);
    final verdict = flags.isNotEmpty
        ? MilestoneVerdict.flag
        : notYet.length >= 2
        ? MilestoneVerdict.watch
        : MilestoneVerdict.onTrack;

    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        Container(
          padding: const EdgeInsets.all(Gap.lg),
          decoration: BoxDecoration(
            color: verdict.colour.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(Gap.radius),
            border: Border.all(color: verdict.colour.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    switch (verdict) {
                      MilestoneVerdict.onTrack => Icons.emoji_events_rounded,
                      MilestoneVerdict.watch => Icons.visibility_rounded,
                      MilestoneVerdict.flag => Icons.medical_information_rounded,
                    },
                    color: verdict.colour,
                    size: 28,
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(
                      verdict.label,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: verdict.colour,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.sm),
              Text(
                switch (verdict) {
                  MilestoneVerdict.onTrack =>
                    '${person.fullName.split(' ').first} is doing what children '
                        'this age usually do. Keep playing — play is how the '
                        'brain grows.',
                  MilestoneVerdict.watch =>
                    'Some things are still coming. Play the ideas below every '
                        'day and check again in a few weeks. Every child has '
                        'their own pace.',
                  MilestoneVerdict.flag =>
                    'Show ${person.fullName.split(' ').first} to the health '
                        'worker at the next contact. This is not a diagnosis '
                        '— it means these are worth a proper look.',
                },
                style: const TextStyle(fontSize: 14, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),

        if (notYet.isNotEmpty)
          SectionCard(
            title: 'Still coming — not yet',
            icon: Icons.hourglass_bottom_rounded,
            accent: flags.isNotEmpty
                ? AppColors.triageRed
                : AppColors.triageAmber,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final m in notYet)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.xs),
                    child: Row(
                      children: [
                        Icon(
                          Icons.arrow_right_rounded,
                          color: m.isFlag
                              ? AppColors.triageRed
                              : AppColors.triageAmber,
                        ),
                        Expanded(
                          child: Text(
                            m.question,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: m.isFlag
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (m.isFlag)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Gap.sm,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.triageRedBg,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'show health worker',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: AppColors.triageRed,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                const Text(
                  'Tell the health worker exactly this list when you arrive.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                ),
              ],
            ),
          ),
        const SizedBox(height: Gap.md),

        SectionCard(
          title: 'Play idea for today',
          icon: Icons.toys_rounded,
          child: Text(
            NurturingCareEngine.activityToday(band),
            style: const TextStyle(fontSize: 14.5, height: 1.5),
          ),
        ),
        const SizedBox(height: Gap.md),
        SectionCard(
          title: 'One thing to remember',
          icon: Icons.favorite_outline_rounded,
          child: Text(
            band.tip,
            style: const TextStyle(fontSize: 14.5, height: 1.5),
          ),
        ),
        const SizedBox(height: Gap.xxl),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to my family'),
        ),
        const SizedBox(height: Gap.lg),
      ],
    );
  }

  /// Saved once per run, the moment the result is shown — same contract as
  /// the danger-sign check: the family's words, on this phone, never as a
  /// clinical record.
  Future<void> _save(Person person, NcAgeBand band) async {
    if (_saved) return;
    _saved = true;

    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final canDo = [
      for (final m in band.milestones)
        if (_answers[m.id] == true) m.question,
    ];
    final notYet = [
      for (final m in band.milestones)
        if (_answers[m.id] == false) m.question,
    ];
    final flags = [
      for (final m in band.milestones)
        if (_answers[m.id] == false && m.isFlag) m.question,
    ];
    final verdict = flags.isNotEmpty
        ? MilestoneVerdict.flag
        : notYet.length >= 2
        ? MilestoneVerdict.watch
        : MilestoneVerdict.onTrack;

    final check = MilestoneCheck(
      id: _uuid.v4(),
      householdId: widget.householdId,
      personId: person.id,
      ageMonths: person.ageInMonths ?? 0,
      bandLabel: band.label,
      verdict: verdict,
      canDo: canDo,
      notYet: notYet,
      flags: flags,
      checkedBy: user.id,
      checkedAt: DateTime.now(),
    );

    try {
      await ref.read(careRepositoryProvider).recordMilestoneCheck(user, check);
      ref.invalidate(householdMilestoneChecksProvider(widget.householdId));
      ref.invalidate(latestMilestoneCheckProvider(person.id));
    } catch (_) {
      // A failed save must never look like a saved check.
      if (mounted) setState(() => _saved = false);
    }
  }
}

class _MilestoneQuestionTile extends StatelessWidget {
  const _MilestoneQuestionTile({
    required this.milestone,
    required this.answer,
    required this.onChanged,
  });

  final NcMilestone milestone;
  final bool? answer;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  milestone.domain.label,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  milestone.question,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Row(
            children: [
              Expanded(
                child: _AnswerButton(
                  label: 'Yes, can do',
                  selected: answer == true,
                  colour: AppColors.triageGreen,
                  onTap: () => onChanged(true),
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: _AnswerButton(
                  label: 'Not yet',
                  selected: answer == false,
                  colour: AppColors.triageAmber,
                  onTap: () => onChanged(false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnswerButton extends StatelessWidget {
  const _AnswerButton({
    required this.label,
    required this.selected,
    required this.colour,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? colour.withValues(alpha: 0.12) : AppColors.canvas,
      borderRadius: BorderRadius.circular(Gap.radiusSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        onTap: onTap,
        child: Container(
          height: Gap.tapTarget,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Gap.radiusSm),
            border: Border.all(
              color: selected ? colour : AppColors.line,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: selected ? colour : AppColors.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}

extension on MilestoneVerdict {
  Color get colour => switch (this) {
    MilestoneVerdict.onTrack => AppColors.triageGreen,
    MilestoneVerdict.watch => AppColors.triageAmber,
    MilestoneVerdict.flag => AppColors.triageRed,
  };
}

