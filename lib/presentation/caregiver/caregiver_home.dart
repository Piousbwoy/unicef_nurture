/// The caregiver's whole world: one household, one family.
///
/// The role boundary is enforced by what this screen *lacks*. There is no
/// assessment form here, no measurements, no diagnosis — a caregiver gets
/// danger-sign triage (a structured "go now / see the nurse / continue care"
/// answer), nurturing-care guidance, their family's schedule and referrals,
/// a channel to report barriers, and voice guidance. Every clinical write
/// still goes through [CareRepository], which would refuse a caregiver
/// anyway; the screen simply never offers what would be refused.
///
/// Nothing the caregiver does here enters the clinical record as clinical
/// data. The triage result is guidance, deliberately: the app must never turn
/// a mother's checklist into a diagnosis.
///
/// Five tabs, named for what a family does — never the health worker's
/// labels (no Day plan, no Assess, no Referrals, no Me), because the two
/// roles are different jobs, not one job in two sizes:
///
/// **Family** — greeting, the people they care for, the family code, and the
/// door to adding someone new. This is where they land when they open the app
/// to ask "is everyone alright today?"
///
/// **Check** — the danger-sign triage. Asks yes / no / not sure, gives one of
/// three recommendations: go now, see the CHW soon, or continue care.
///
/// **Grow & Play** — nurturing care: what the children can do at their age,
/// and a play idea for today built from things already in the home.
///
/// **Care plan** — what the family owes the calendar: vaccine days derived
/// from each child's age, appointments the clinic scheduled, open referrals,
/// and the barrier channel.
///
/// **Help** — the emergency plan, the voice guide, the language they hear
/// advice in, and the sign-out.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/audio/audio_guide.dart';
import '../../core/audio/voice_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/reference/northern_ghana.dart';
import '../../data/repositories/care_repository.dart';
import '../../domain/engines/immunisation_engine.dart';
import '../../domain/engines/nurturing_care_engine.dart';
import '../../domain/engines/recommendation_engine.dart';
import '../../domain/engines/trajectory_engine.dart';
import '../../domain/entities/core.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../../domain/family_code.dart';
import '../settings/voice_test_screen.dart';
import '../shared/app_image.dart';
import '../shared/recommendation_kit.dart';
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
enum _Stage { pick, questions, result, clinicPass, watchFor }

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

    // The caregiver's shell shares nothing with the health worker's: no Day
    // plan, no Assess, no Referrals tab, no Me — a family's app is a
    // different product, so it gets different doors.
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('My family', style: AppType.title),
            const SizedBox(height: 2),
            Text(
              user.community,
              style: AppType.caption.copyWith(fontSize: 11.5),
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _FamilyTab(
            householdId: linked,
            onSwitch: (i) => setState(() => _tab = i),
          ),
          _CheckTab(householdId: linked),
          _GrowPlayTab(householdId: linked),
          _CarePlanTab(householdId: linked),
          _HelpTab(householdId: linked),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.family_restroom_outlined),
            activeIcon: Icon(Icons.family_restroom_rounded),
            label: 'Family',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.health_and_safety_outlined),
            activeIcon: Icon(Icons.health_and_safety_rounded),
            label: 'Check',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.toys_outlined),
            activeIcon: Icon(Icons.toys_rounded),
            label: 'Grow & Play',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.event_note_outlined),
            activeIcon: Icon(Icons.event_note_rounded),
            label: 'Care plan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.support_agent_outlined),
            activeIcon: Icon(Icons.support_agent_rounded),
            label: 'Help',
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- Home tab

class _FamilyTab extends ConsumerWidget {
  const _FamilyTab({required this.householdId, required this.onSwitch});

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
        const SizedBox(height: Gap.md),
        _FamilyCodeCard(householdId: householdId),
        const SizedBox(height: Gap.lg),
        // The one big action — master flow [13b] → [40-C]. A caregiver
        // opening the app to ask "is everyone alright?" goes straight into
        // the check, and lands back on this Family tab when it is done.
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
        const SizedBox(height: Gap.xl),
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
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'No one is on your family list yet. Add the people you '
                      'care for and the app will start working for them.',
                      style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
                    ),
                    const SizedBox(height: Gap.md),
                    _AddMemberButton(householdId: householdId),
                  ],
                );
              }
              return Column(
                children: [
                  for (final p in list) _MemberTile(person: p),
                  const SizedBox(height: Gap.xs),
                  _AddMemberButton(householdId: householdId),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Opens the add-member sheet. Deliberately one small widget: it appears in
/// the family card, and the same affordance must exist wherever the family
/// list is empty.
class _AddMemberButton extends StatelessWidget {
  const _AddMemberButton({required this.householdId});

  final String householdId;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: () => _openAddMember(context, householdId),
    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
    label: const Text('Add a family member'),
    style: OutlinedButton.styleFrom(minimumSize: const Size(0, Gap.tapTarget)),
  );
}

/// One entry point to the add-member sheet so both callers stay identical.
void _openAddMember(BuildContext context, String householdId) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AddMemberSheet(householdId: householdId),
  );
}

/// The family's own code — the same six characters the FHW would read out.
///
/// Showing it to a caregiver who started their own family closes the loop:
/// when the health worker finally meets them, the code lets the two records
/// join instead of duplicating.
class _FamilyCodeCard extends ConsumerWidget {
  const _FamilyCodeCard({required this.householdId});
  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SectionCard(
      title: 'Your family code',
      subtitle:
          'Show this code to your health worker when you meet. It links '
          'this phone to your family’s record at the clinic.',
      icon: Icons.qr_code_2_rounded,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.xl,
            vertical: Gap.md,
          ),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(Gap.radius),
          ),
          child: Text(
            FamilyCode.pretty(householdId),
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: 5,
              color: AppColors.primary,
            ),
          ),
        ),
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
                : Flexible(
                    child: TriageBadge(a.effectiveTriage, compact: true),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- Check tab

/// The danger-sign check. This is the only "clinical" thing a caregiver can
/// run, and it is deliberately not an assessment: it asks what anyone can
/// observe — no counting breaths, no temperatures — and answers in one
/// sentence a grandmother could repeat.
class _CheckTab extends ConsumerWidget {
  const _CheckTab({required this.householdId});
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
        const SizedBox(height: Gap.xl),
      ],
    );
  }
}

// ------------------------------------------------------------- Grow & Play

/// Nurturing care gets its own door, not a card squeezed into the check-in:
/// growing is more than weight, and play is a medicine that costs nothing.
/// Every child under five gets their age band, today's play idea, and a
/// milestone check phrased as "can they do this?".
class _GrowPlayTab extends ConsumerWidget {
  const _GrowPlayTab({required this.householdId});
  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(householdMembersProvider(householdId));

    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        SectionCard(
          title: 'Grow and play',
          subtitle:
              'Growing is more than weight. Answer a few questions about '
              'what your child can do, and get a play idea for today — '
              'free, with things you already have.',
          icon: Icons.toys_rounded,
          child: members.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(error: e),
            data: (people) {
              final children = people
                  .where(
                    (p) => NurturingCareEngine.bandFor(p.ageInMonths) != null,
                  )
                  .toList(growable: false);
              if (children.isEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'No children under five are on your family list yet. '
                      'Add your little ones with their date of birth and '
                      'this page will grow with them.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.inkMuted,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: Gap.md),
                    _AddMemberButton(householdId: householdId),
                  ],
                );
              }
              return Column(
                children: [
                  for (final child in children) _GrowChildTile(child: child),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: Gap.xl),
      ],
    );
  }
}

// ------------------------------------------------------------- Care plan tab

/// What the family owes the calendar. The anchor is the vaccine schedule:
/// the app derives, from each child's date of birth, what the Ghana national
/// schedule expects at their age — framed honestly, because the paper card
/// is the record of doses already received, and the app never pretends to
/// know it. Around that: who to call, open referrals from the clinic, and
/// the barrier channel.
class _CarePlanTab extends ConsumerWidget {
  const _CarePlanTab({required this.householdId});
  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        _FamilyCarePlanSection(householdId: householdId),
        _CarePlanTimelineCard(householdId: householdId),
        const SizedBox(height: Gap.md),
        _ContactsSection(householdId: householdId),
        const SizedBox(height: Gap.md),
        _ReferralsSection(),
        const SizedBox(height: Gap.md),
        _BarrierCard(householdId: householdId),
        const SizedBox(height: Gap.xl),
      ],
    );
  }
}

/// The plan the health worker left with the family — the very same
/// [CarePlan] the CHO saw on the result screen, persisted on the
/// assessment and re-rendered here for the family: plain language, no
/// citations, a voice button, and a worklist they can tick off at home.
/// Members who were never assessed simply render nothing.
class _FamilyCarePlanSection extends ConsumerWidget {
  const _FamilyCarePlanSection({required this.householdId});
  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();
    final members = ref.watch(householdMembersProvider(householdId));

    return members.maybeWhen(
      data: (people) => Column(
        children: [
          for (final person in people)
            _MemberCarePlanCard(
              person: person,
              language: user.preferredLanguage,
            ),
        ],
      ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// One family member's saved care plan, decoded from the assessment's
/// persisted `carePlanJson`. A malformed or missing plan renders nothing:
/// the family must never see a crash where a health worker's advice
/// should be.
class _MemberCarePlanCard extends ConsumerWidget {
  const _MemberCarePlanCard({required this.person, required this.language});

  final Person person;
  final String language;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = ref.watch(latestAssessmentProvider(person.id));

    return latest.maybeWhen(
      data: (assessment) {
        final raw = assessment?.carePlanJson;
        if (raw == null) return const SizedBox.shrink();
        final CarePlan plan;
        try {
          plan = CarePlan.fromJson(
            Map<String, Object?>.from(jsonDecode(raw) as Map),
          );
        } catch (_) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: Gap.md),
          child: FamilyCarePlanCard(
            plan: plan,
            personName: person.fullName,
            language: language,
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _CarePlanTimelineCard extends ConsumerWidget {
  const _CarePlanTimelineCard({required this.householdId});
  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(householdMembersProvider(householdId));

    return members.maybeWhen(
      data: (people) {
        final children = people
            .where((p) => p.ageInDays != null && p.ageInDays! < 365 * 5)
            .toList(growable: false);
        if (children.isEmpty) return const SizedBox.shrink();

        return SectionCard(
          title: 'Digital Yellow Card',
          subtitle:
              'The Ghana vaccine schedule as a timeline from each child\u2019s '
              'age. If the paper yellow card is behind what you see here, '
              'doses may be overdue — bring both to the clinic.',
          icon: Icons.timeline_rounded,
          child: Column(
            children: [
              for (final child in children)
                _CarePlanChildTimeline(child: child),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _CarePlanChildTimeline extends StatelessWidget {
  const _CarePlanChildTimeline({required this.child});

  final Person child;

  @override
  Widget build(BuildContext context) {
    // The timeline is drawn from the national schedule; the honesty banner
    // is drawn from the same engine the health worker sees — one source of
    // truth, two honest views of it.
    final timelinePoints = _buildTimelinePoints(child.ageInDays!);
    final plan = ImmunisationEngine.plan(
      ageInDays: child.ageInDays!,
      givenLabels: const {},
    );

    // Find the currently active point (the one due now or next)
    final activeIndex = timelinePoints.indexWhere((p) => p.isCurrentOrNext);
    final displayPoints = timelinePoints
        .take(activeIndex == -1 ? timelinePoints.length : activeIndex + 2)
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: Gap.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Gap.radius),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(Gap.md),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(Gap.radius),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(Gap.xs),
                  decoration: const BoxDecoration(
                    color: Colors.white24,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.child_care_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    child.fullName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Gap.sm,
                    vertical: Gap.xs,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(Gap.radius),
                  ),
                  child: Text(
                    child.ageLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Honesty banner: the timeline shows what the schedule expects;
          // this line shows what that means for this child today, in the
          // same words the health worker's screen uses.
          if (plan.overdue.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.md,
                vertical: Gap.sm,
              ),
              color: AppColors.triageRedBg,
              child: Text(
                'Check the card — ${plan.overdueLabels.join(', ')}: doses may '
                'be overdue. If they are not on the card yet, go to the '
                'clinic this week.',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.triageRed,
                  height: 1.4,
                ),
              ),
            )
          else if (plan.giveToday.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.md,
                vertical: Gap.sm,
              ),
              color: AppColors.triageAmberBg,
              child: Text(
                'Due by age now: ${plan.giveToday.map((d) => d.label).join(', ')} '
                '— a good week for the clinic if the card does not have them yet.',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.triageAmber,
                  height: 1.4,
                ),
              ),
            ),

          // Timeline
          Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < displayPoints.length; i++)
                  _TimelinePointView(
                    point: displayPoints[i],
                    isLast: i == displayPoints.length - 1,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<_TimelinePoint> _buildTimelinePoints(int ageDays) {
    final ageWeeks = ageDays ~/ 7;

    // One source of truth: group the national schedule by due week, so this
    // timeline can never drift from what the clinic expects.
    final byWeek = <int, List<String>>{};
    for (final dose in GhanaEpi.schedule) {
      byWeek.putIfAbsent(dose.dueAtWeeks, () => []).add(dose.label);
    }
    // A few non-vaccine anchors that belong on a mother's timeline.
    const careNotes = <int, String>{
      0: 'First bath after 24 hours',
      26: 'Start thick mashed foods',
      78: 'Deworming and vitamin A',
    };
    String labelFor(int weeks) => weeks == 0
        ? 'Birth'
        : weeks < 20
        ? '$weeks weeks'
        : '${(weeks / 4.33).round()} months';

    final weeks = byWeek.keys.toList()..sort();
    final points = <_TimelinePoint>[
      for (final week in weeks)
        _TimelinePoint(
          ageLabel: labelFor(week),
          events: [
            byWeek[week]!.join(', '),
            if (careNotes[week] != null) careNotes[week]!,
          ],
          dueDays: week * 7,
        ),
    ];

    // Evaluate status against the child's age, with a two-week window
    // either side of each due date reading as "now".
    for (final p in points) {
      final dueWeeks = p.dueDays ~/ 7;
      if (ageWeeks >= dueWeeks + 2) {
        p.status = _TimelineStatus.past;
      } else if (ageWeeks >= dueWeeks - 2) {
        p.status = _TimelineStatus.current;
      } else {
        p.status = _TimelineStatus.future;
      }
    }

    // If no point is 'current', highlight the next upcoming one.
    if (!points.any((p) => p.status == _TimelineStatus.current)) {
      final nextIdx = points.indexWhere(
        (p) => p.status == _TimelineStatus.future,
      );
      if (nextIdx != -1) {
        points[nextIdx].status = _TimelineStatus.current;
      }
    }

    return points;
  }
}

enum _TimelineStatus { past, current, future }

class _TimelinePoint {
  _TimelinePoint({
    required this.ageLabel,
    required this.events,
    required this.dueDays,
  });

  final String ageLabel;
  final List<String> events;
  final int dueDays;
  _TimelineStatus status = _TimelineStatus.future;

  bool get isCurrentOrNext =>
      status == _TimelineStatus.current || status == _TimelineStatus.future;
}

class _TimelinePointView extends StatelessWidget {
  const _TimelinePointView({required this.point, required this.isLast});

  final _TimelinePoint point;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final isPast = point.status == _TimelineStatus.past;
    final isCurrent = point.status == _TimelineStatus.current;

    final dotColor = isCurrent
        ? AppColors.primary
        : (isPast ? AppColors.line : Colors.grey.shade300);
    final lineColor = isCurrent || isPast
        ? AppColors.line
        : Colors.grey.shade200;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Line & Dot Column
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: isPast ? Colors.transparent : dotColor,
                    border: Border.all(color: dotColor, width: isPast ? 2 : 0),
                    shape: BoxShape.circle,
                  ),
                  child: isPast
                      ? const Icon(
                          Icons.check,
                          size: 10,
                          color: AppColors.inkMuted,
                        )
                      : null,
                ),
                if (!isLast)
                  Expanded(child: Container(width: 2, color: lineColor)),
              ],
            ),
          ),

          // Content Column
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: Gap.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    point.ageLabel,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                      color: isPast
                          ? AppColors.inkMuted
                          : (isCurrent
                                ? AppColors.primary
                                : Colors.grey.shade400),
                    ),
                  ),
                  const SizedBox(height: Gap.xs),
                  ...point.events.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '• $e',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isCurrent
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: isPast
                              ? AppColors.inkMuted
                              : (isCurrent
                                    ? AppColors.ink
                                    : Colors.grey.shade400),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Help tab

/// Where a family goes when something is wrong — and before it is. The
/// emergency plan first (it is the one card that must be readable at 2 a.m.),
/// then the voice guide, the account, and the sign-out.
class _HelpTab extends ConsumerWidget {
  const _HelpTab({required this.householdId});
  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        const _EmergencyPlanCard(),
        const SizedBox(height: Gap.md),
        SectionCard(
          title: 'Voice',
          subtitle:
              'The app can read its guidance aloud. Test the voice here '
              'before you need it.',
          icon: Icons.settings_voice_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const VoiceTestScreen()),
                ),
                icon: const Icon(Icons.graphic_eq_rounded),
                label: const Text('Test the voice'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, Gap.tapTarget),
                ),
              ),
              const SizedBox(height: Gap.sm),
              // The chosen language lands on the user record, so every audio
              // button in this flow — questions, topics, the result —
              // follows it from this moment on.
              OutlinedButton.icon(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  isScrollControlled: true,
                  builder: (_) => _GuidanceLanguageSheet(
                    current: user.preferredLanguage,
                    region: user.region,
                  ),
                ),
                icon: const Icon(Icons.translate_rounded),
                label: Text('Guidance language: ${user.preferredLanguage}'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, Gap.tapTarget),
                ),
              ),
              const SizedBox(height: Gap.sm),
              // Short heard messages about danger signs and feeding —
              // play them to the whole family.
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _AudioGuideScreen(householdId: householdId),
                  ),
                ),
                icon: const Icon(Icons.play_circle_outline_rounded),
                label: const Text('Open the voice guide'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, Gap.tapTarget),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),
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

/// The two o'clock in the morning card: when a child is sick at night, no
/// one should have to think about what to do or what to carry. Three steps,
/// one bag, no decisions left to make.
class _EmergencyPlanCard extends StatelessWidget {
  const _EmergencyPlanCard();

  static const _steps = [
    'Do not wait for morning. Danger signs move fast — leave as soon as '
        'you can.',
    'Go to your CHPS compound or health centre. If it is closed, go '
        'straight to the district hospital.',
    'Wake a neighbour or call a family member if you cannot travel alone. '
        'Never wait alone for transport that may not come.',
  ];

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'If it is an emergency',
      icon: Icons.emergency_share_rounded,
      accent: AppColors.triageRed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.triageRed,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(
                      _steps[i],
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.inkMuted,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Gap.md),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(Gap.radiusSm),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.work_history_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
                SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    'Carry this phone, the child\u2019s vaccine card and the '
                    'NHIS card. The phone shows your family code and every '
                    'check you ran at home.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.primaryDark,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),
          // Ghana's free emergency number. One tap, no airtime needed —
          // the most useful button on this tab at two in the morning.
          FilledButton.icon(
            onPressed: () => launchUrl(Uri.parse('tel:112')),
            icon: const Icon(Icons.call_rounded),
            label: const Text('Call 112 — emergency line'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.triageRed,
              minimumSize: const Size(double.infinity, Gap.tapTarget),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Add member

/// Adding someone to the family's own list.
///
/// The categories mirror who this app exists for: babies and young children
/// — the date of birth powers every age-banded thing the app does (danger
/// signs, vaccine days, milestones) — and the women of the family. The write
/// goes through [CareRepository.addFamilyMember], which refuses anything
/// outside this family's household and records the add in the audit log.
class _AddMemberSheet extends ConsumerStatefulWidget {
  const _AddMemberSheet({required this.householdId});

  final String householdId;

  @override
  ConsumerState<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends ConsumerState<_AddMemberSheet> {
  static const _categories = [
    'Baby or young child (0–5 years)',
    'Mother or woman of the family',
  ];

  final _name = TextEditingController();
  final _ageYears = TextEditingController();
  int _category = 0;
  DateTime? _dob;
  Sex? _sex;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _ageYears.dispose();
    super.dispose();
  }

  bool get _isChild => _category == 0;

  String? _validate() {
    if (_name.text.trim().length < 2) return 'Enter their name.';
    if (_isChild && _dob == null) return 'Choose the date of birth.';
    return null;
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? now.subtract(const Duration(days: 365)),
      firstDate: now.subtract(const Duration(days: 365 * 5 + 30)),
      lastDate: now,
      helpText: 'When were they born?',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _save() async {
    final user = ref.read(currentUserProvider);
    final problem = user == null ? 'You are not signed in.' : _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final days = _dob == null ? null : DateTime.now().difference(_dob!).inDays;
    final person = Person(
      id: _uuid.v4(),
      householdId: widget.householdId,
      fullName: _name.text.trim(),
      clientType: _isChild
          ? ClientType.forChildAgeInDays(days!) ?? ClientType.childUnderFive
          : ClientType.womanOfReproductiveAge,
      sex: _isChild ? _sex : Sex.female,
      dateOfBirth: _dob,
      ageYearsApprox: _isChild ? null : int.tryParse(_ageYears.text.trim()),
    );

    try {
      await ref.read(careRepositoryProvider).addFamilyMember(user!, person);
      ref.invalidate(householdMembersProvider(widget.householdId));
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is AccessDenied ? e.message : 'Could not save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: Gap.lg,
        right: Gap.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + Gap.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add a family member', style: AppType.title),
            const SizedBox(height: Gap.xs),
            const Text(
              'Everyone you add stays on this phone and joins your '
              'family\u2019s record when the health worker meets you.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.inkMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: Gap.md),
            for (var i = 0; i < _categories.length; i++)
              InkWell(
                onTap: () => setState(() => _category = i),
                borderRadius: BorderRadius.circular(Gap.radiusSm),
                child: Container(
                  margin: const EdgeInsets.only(bottom: Gap.xs),
                  padding: const EdgeInsets.symmetric(
                    horizontal: Gap.md,
                    vertical: Gap.sm,
                  ),
                  decoration: BoxDecoration(
                    color: _category == i
                        ? AppColors.primaryLight
                        : Colors.white,
                    border: Border.all(
                      color: _category == i
                          ? AppColors.primary
                          : AppColors.line,
                    ),
                    borderRadius: BorderRadius.circular(Gap.radiusSm),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _category == i
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 20,
                        color: _category == i
                            ? AppColors.primary
                            : AppColors.inkFaint,
                      ),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: Text(
                          _categories[i],
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: Gap.sm),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            if (_isChild) ...[
              const SizedBox(height: Gap.md),
              OutlinedButton.icon(
                onPressed: _pickDob,
                icon: const Icon(Icons.cake_outlined, size: 18),
                label: Text(
                  _dob == null
                      ? 'Choose the date of birth'
                      : 'Born ${DateFormat('d MMMM yyyy').format(_dob!)}',
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, Gap.tapTarget),
                ),
              ),
              const SizedBox(height: Gap.md),
              Row(
                children: [
                  const Text(
                    'Boy or girl?',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  for (final s in Sex.values)
                    Padding(
                      padding: const EdgeInsets.only(right: Gap.xs),
                      child: ChoiceChip(
                        label: Text(s.label),
                        selected: _sex == s,
                        onSelected: (_) => setState(() => _sex = s),
                      ),
                    ),
                ],
              ),
            ] else ...[
              const SizedBox(height: Gap.md),
              TextField(
                controller: _ageYears,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'About how old? (years, optional)',
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: Gap.md),
              Text(
                _error!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.triageRed,
                ),
              ),
            ],
            const SizedBox(height: Gap.lg),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: const Text('Save'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, Gap.tapTarget),
              ),
            ),
          ],
        ),
      ),
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

  /// The check runs as a conversation — one sign at a time. This is which
  /// question the caregiver is on.
  int _qIndex = 0;

  /// A calm acknowledgement shown for a beat after each answer, before the
  /// conversation walks on to the next sign.
  String? _ack;
  Timer? _ackTimer;

  /// Steps the family has ticked off on the "do these now" card.
  final Set<String> _doneSteps = {};

  String get _language =>
      ref.read(currentUserProvider)?.preferredLanguage ?? 'English';

  List<String> get _chosenYes => _signs
      .where((s) => _answers[s.$1] == _SignAnswer.yes)
      .map((s) => s.$2)
      .toList(growable: false);

  List<String> get _chosenUnsure => _signs
      .where((s) => _answers[s.$1] == _SignAnswer.unsure)
      .map((s) => s.$2)
      .toList(growable: false);

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

  _TriageVerdict _verdict() {
    final yes = _answers.values.where((a) => a == _SignAnswer.yes).length;
    final unsure = _answers.values.where((a) => a == _SignAnswer.unsure).length;
    if (yes > 0) return _TriageVerdict.urgent;
    if (unsure >= 2) return _TriageVerdict.caution;
    return _TriageVerdict.fine;
  }

  /// One answer in the conversation. The acknowledgement is the warmth —
  /// a mother who says YES to a frightening sign is thanked, not alarmed,
  /// and then the check walks on to the next sign by itself.
  void _answer(String key, _SignAnswer value) {
    _ackTimer?.cancel();
    setState(() {
      _answers[key] = value;
      _ack = switch (value) {
        _SignAnswer.yes =>
          'Thank you for telling me. I have noted it — you did right to check.',
        _SignAnswer.no => 'Good. That is what we hope to hear.',
        _SignAnswer.unsure => 'That is okay. The nurse will look at this one.',
        _SignAnswer.unset => null,
      };
    });
    _ackTimer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      setState(() {
        _ack = null;
        if (_qIndex < _signs.length - 1) _qIndex += 1;
      });
      _playQuestion(_signs[_qIndex].$1, _language, quiet: true);
    });
  }

  /// Jump straight to one question — the progress segments double as a
  /// review strip, so a caregiver can revisit any answer.
  void _showQuestion(int index) {
    _ackTimer?.cancel();
    setState(() {
      _qIndex = index;
      _ack = null;
    });
    _playQuestion(_signs[index].$1, _language, quiet: true);
  }

  @override
  void dispose() {
    _ackTimer?.cancel();
    super.dispose();
  }

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
          title: Text(switch (_stage) {
            _Stage.pick => 'Who are you checking?',
            _Stage.questions => 'What have you noticed?',
            _Stage.result => 'What to do now',
            _Stage.clinicPass => 'Clinic pass',
            _Stage.watchFor => 'Watch for these at home',
          }),
        ),
        body: members.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorView(error: e),
          data: (list) => switch (_stage) {
            _Stage.pick => _buildPersonPicker(list),
            _Stage.questions => _buildChecklist(),
            _Stage.result => _buildResult(household.valueOrNull),
            _Stage.clinicPass => _buildClinicPass(),
            _Stage.watchFor => _buildWatchFor(),
          },
        ),
      ),
    );
  }

  void _back() => setState(() {
    // Inside the conversation the back arrow revisits the previous question;
    // only at the first question does it leave the check.
    if (_stage == _Stage.questions && _qIndex > 0) {
      _qIndex -= 1;
      _ack = null;
      _ackTimer?.cancel();
      return;
    }
    _stage = switch (_stage) {
      _Stage.questions => _Stage.pick,
      _Stage.result => _Stage.questions,
      _Stage.clinicPass || _Stage.watchFor => _Stage.result,
      _Stage.pick => _Stage.pick,
    };
  });

  void _restart() => setState(() {
    _stage = _Stage.pick;
    _person = null;
    _answers.clear();
    _checkSaved = false;
    _qIndex = 0;
    _ack = null;
    _doneSteps.clear();
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
      return Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Expanded(
              child: EmptyState(
                icon: Icons.person_off_outlined,
                title: 'No family members yet',
                message:
                    'Add the people you care for and the check will be '
                    'ready for them. If someone is seriously ill now, go '
                    'straight to the health facility.',
              ),
            ),
            _AddMemberButton(householdId: widget.householdId),
          ],
        ),
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
            onTap: () {
              setState(() {
                _person = p;
                _answers.clear();
                _qIndex = 0;
                _stage = _Stage.questions;
              });
              // Voice-first: the first question is heard the moment the
              // conversation opens.
              final firstKey = switch (p.effectiveClientType) {
                ClientType.newborn => _newbornSigns,
                ClientType.childUnderFive => _childSigns,
                _ => _motherSigns,
              }[0].$1;
              _playQuestion(firstKey, _language, quiet: true);
            },
          ),
      ],
    );
  }

  /// [41-C] The Quick Home Check, as a conversation: one sign at a time,
  /// heard aloud before it is answered, with three enormous answers and a
  /// calm acknowledgement after each. A scrolling clinical list asks a
  /// non-reading caregiver to hold eight questions in mind at once; a
  /// conversation asks for exactly one. The progress segments double as a
  /// review strip — tap any of them to revisit that answer.
  Widget _buildChecklist() {
    final person = _person!;
    final answered = _signs
        .where((s) => _answers[s.$1] != _SignAnswer.unset)
        .length;
    final allAnswered = answered == _signs.length;
    final index = _qIndex.clamp(0, _signs.length - 1);
    final (key, label) = _signs[index];

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Gap.lg),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'About ${person.fullName}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    'Question ${index + 1} of ${_signs.length}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.md),
              // The review strip: one segment per sign, coloured by the
              // answer it received, tap-any to revisit.
              Row(
                children: [
                  for (var i = 0; i < _signs.length; i++) ...[
                    if (i > 0) const SizedBox(width: Gap.xs),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _showQuestion(i),
                        child: Container(
                          height: i == index ? 10 : 7,
                          decoration: BoxDecoration(
                            color:
                                (_answers[_signs[i].$1] ?? _SignAnswer.unset) ==
                                    _SignAnswer.unset
                                ? i == index
                                      ? AppColors.primary
                                      : AppColors.line
                                : (_answers[_signs[i].$1] ?? _SignAnswer.unset)
                                      .colour,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: Gap.lg),
              AnimatedSwitcher(
                duration: AppMotion.fast,
                transitionBuilder: (child, anim) => SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.08, 0),
                    end: Offset.zero,
                  ).animate(anim),
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: _SignQuestionCard(
                  key: ValueKey(key),
                  question: label,
                  icon: _iconForSign(key),
                  answer: _answers[key] ?? _SignAnswer.unset,
                  ack: _ack,
                  onChanged: (v) => _answer(key, v),
                  onPlay: () => _playQuestion(key, _language),
                ),
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
                  color: allAnswered ? AppColors.primary : AppColors.inkMuted,
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

  /// A small pictogram per sign, so the question reads even before the
  /// audio finishes. Icons are decoration — the words and the voice carry
  /// the meaning.
  IconData _iconForSign(String key) => switch (key) {
    'feed' => Icons.child_care_outlined,
    'drink' => Icons.local_drink_outlined,
    'fast' => Icons.speed_outlined,
    'breath' => Icons.air_outlined,
    'fits' => Icons.flash_on_outlined,
    'sleepy' => Icons.bedtime_outlined,
    'temp' => Icons.device_thermostat_outlined,
    'yellow' => Icons.brightness_6_outlined,
    'cord' => Icons.healing_outlined,
    'vomit' => Icons.sick_outlined,
    'blood' => Icons.water_drop_outlined,
    'thin' => Icons.monitor_weight_outlined,
    'fever' => Icons.local_fire_department_outlined,
    'bleed' => Icons.bloodtype_outlined,
    'head' => Icons.visibility_off_outlined,
    'pain' => Icons.health_and_safety_outlined,
    'smell' => Icons.wind_power_outlined,
    'move' => Icons.pregnant_woman_outlined,
    _ => Icons.help_outline_rounded,
  };

  Widget _buildResult(Household? household) {
    final verdict = _verdict();
    final person = _person!;
    final chosenYes = _signs
        .where((s) => _answers[s.$1] == _SignAnswer.yes)
        .map((s) => s.$2)
        .toList(growable: false);
    final chosenUnsure = _signs
        .where((s) => _answers[s.$1] == _SignAnswer.unsure)
        .map((s) => s.$2)
        .toList(growable: false);
    final walk = household?.walkingMinutesToFacility;
    // Clinical colours (red / amber) are reserved for safety. A green
    // outcome is a calm moment, so it wears the brand blue instead of a
    // green that could be read as "medical".
    final heroGradient = verdict == _TriageVerdict.fine
        ? AppColors.heroGradient
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [verdict.colour, verdict.colour.withValues(alpha: 0.82)],
          );

    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        // ------------------------- Who this check is about
        Container(
          padding: const EdgeInsets.all(Gap.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceTint,
            borderRadius: BorderRadius.circular(Gap.radius),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Gap.radiusSm),
                child: SizedBox(
                  width: 54,
                  height: 54,
                  child: AppImage(
                    src: switch (person.effectiveClientType) {
                      ClientType.newborn => AppImages.cardNewborn,
                      ClientType.childUnderFive => AppImages.cardChild,
                      _ => AppImages.cardMother,
                    },
                  ),
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Check for ${person.fullName}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Saved on this phone for your health worker to see.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.inkMuted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),

        // ------------------------- Verdict hero
        Container(
          padding: const EdgeInsets.all(Gap.lg),
          decoration: BoxDecoration(
            gradient: heroGradient,
            borderRadius: BorderRadius.circular(Gap.radius),
            boxShadow: const [AppShadows.card],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(Gap.xs + 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _iconFor(verdict),
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Text(
                      verdict.headline,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.md),
              Text(
                verdict.advice,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: Colors.white.withValues(alpha: 0.94),
                ),
              ),
              if (verdict == _TriageVerdict.urgent && walk != null) ...[
                const SizedBox(height: Gap.md),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Gap.md,
                    vertical: Gap.sm,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(Gap.radiusSm),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.directions_walk_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: Text(
                          'The facility is about $walk minutes on foot.',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Gap.md),

        // ------------------------- Do these now
        // The verdict is a decision; this card is the plan around it. A
        // family told "go now" still has to pack, find a ride and remember
        // the book — the app walks them through it, tick by tick.
        _DoThisNowCard(
          verdict: verdict,
          person: person,
          done: _doneSteps,
          onToggle: (id) => setState(() {
            if (!_doneSteps.remove(id)) _doneSteps.add(id);
          }),
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
                : _Stage.clinicPass;
          }),
          onHearAloud: () => _playVerdict(verdict),
          onCheckAnother: _restart,
        ),
        const SizedBox(height: Gap.md),

        // ------------------------- Your words for the nurse
        // "Go to the clinic" is only half a recommendation; this is the
        // other half — the sentence she will actually say at the gate,
        // built from her own answers, playable aloud and copyable.
        if (verdict != _TriageVerdict.fine) ...[
          _TellTheNurseCard(
            message: _nurseWords(person),
            onPlay: _playWords,
            onCopy: () => _copyWords(_nurseWords(person)),
          ),
          const SizedBox(height: Gap.md),
        ],

        // ------------------------- Feeding today
        // The check ends with what the family CAN do, not only what is
        // wrong. Real Northern Ghana foods, photographed, per master
        // flow [48]. Newborns get breastfeeding guidance only.
        _FamilyFeedingCard(person: person, verdict: verdict),
        const SizedBox(height: Gap.md),

        // ------------------------- Reasons the recommendation rests on
        if (chosenYes.isNotEmpty)
          _SignsCard(
            title: 'Signs you said YES to',
            icon: Icons.campaign_outlined,
            colour: AppColors.triageRed,
            signs: chosenYes,
            note:
                'Say when each sign started, and what has been eaten, '
                'drunk or vomited since.',
          ),
        if (chosenUnsure.isNotEmpty) ...[
          const SizedBox(height: Gap.md),
          _SignsCard(
            title: 'Signs you were not sure about',
            icon: Icons.help_outline_rounded,
            colour: AppColors.triageAmber,
            signs: chosenUnsure,
            note: 'These are the signs the nurse should look at first.',
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

  /// [43-C] Clinic Pass. A digital ticket the mother shows the nurse.
  /// Generates a high-contrast QR code containing the triage data,
  /// bypassing the need for SMS credit or network connectivity.
  Widget _buildClinicPass() {
    final person = _person!;
    final verdict = _verdict();
    final isUrgent = verdict == _TriageVerdict.urgent;

    // A dense JSON payload for the QR code — the nurse sees exactly what
    // the family reported, with no SMS credit and no network.
    final payload = {
      'p': person.id,
      'n': person.fullName,
      'a': person.ageInDays,
      'v': verdict.name,
      'y': _chosenYes,
      'u': _chosenUnsure,
      't': DateTime.now().toIso8601String(),
    };
    final qrData = jsonEncode(payload);

    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => setState(() => _stage = _Stage.result),
            ),
            const SizedBox(width: Gap.sm),
            const Text(
              'Clinic Pass',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.md),
        const Text(
          'Show this screen to the nurse when you arrive at the CHPS compound. '
          'She will scan it to see exactly what you reported.',
          style: TextStyle(
            fontSize: 14,
            color: AppColors.inkMuted,
            height: 1.45,
          ),
        ),
        const SizedBox(height: Gap.xl),

        // The Ticket
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(Gap.radius),
            boxShadow: [
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            children: [
              // Ticket Header (Colored by triage)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: Gap.md,
                  horizontal: Gap.lg,
                ),
                decoration: BoxDecoration(
                  color: isUrgent ? AppColors.triageRed : AppColors.triageAmber,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(Gap.radius),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      isUrgent ? 'URGENT EVALUATION' : 'ROUTINE CHECK',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: Gap.xs),
                    Text(
                      person.fullName.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),

              // Ticket Body (QR + Text)
              Padding(
                padding: const EdgeInsets.all(Gap.xl),
                child: Column(
                  children: [
                    QrImageView(
                      data: qrData,
                      version: QrVersions.auto,
                      size: 200.0,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: AppColors.ink,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: Gap.lg),
                    const Text(
                      'SCAN AT CLINIC',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.inkMuted,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: Gap.xl),

                    // Human readable summary
                    if (_chosenYes.isNotEmpty) ...[
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Primary signs:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ),
                      const SizedBox(height: Gap.xs),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _chosenYes.join('\\n'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: Gap.xxl),

        GradientButton(
          label: 'I have arrived',
          icon: Icons.check_circle_outline_rounded,
          onPressed: () => setState(() => _stage = _Stage.watchFor),
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
                      style: AppType.title.copyWith(color: AppColors.triageRed),
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

  /// One question, heard aloud. Falls back to system TTS, then the Hausa
  /// bridge, then the on-screen text — care never waits on an MP3.
  Future<void> _playQuestion(
    String key,
    String language, {
    // Auto-played questions fail silently — a missing recording must not
    // snack-bar the caregiver eight times in a row. Manual taps still get
    // the honest fallback note.
    bool quiet = false,
  }) async {
    final outcome = await AudioGuide.playQuestion(key, language);
    if (!mounted || quiet) return;
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

  /// The result exactly as the screen shows it — headline and advice — heard
  /// aloud in the caregiver's chosen language. The voice chain is the same
  /// one every other button uses: verified recording, then the phone's own
  /// voice, then the Hausa bridge, then the words on screen.
  Future<void> _playVerdict(_TriageVerdict verdict) async {
    final user = ref.read(currentUserProvider);
    final language = user?.preferredLanguage ?? 'English';
    final outcome = await VoiceService.speakText(
      id: 'caregiver_verdict_${verdict.name}',
      text: '${verdict.headline}. ${verdict.advice}',
      language: language,
    );
    if (!mounted) return;
    if (outcome.source == VoiceSource.readAloud) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'The $language voice is not on this phone yet. The words are on '
            'the screen — read them aloud, or ask someone to.',
          ),
        ),
      );
    }
  }

  /// The caregiver's own words for the nurse, assembled from what she just
  /// tapped — so the gate conversation starts with her observation, not with
  /// a queue number. Never a placeholder: every line is something she said.
  String _nurseWords(Person person) {
    final parts = <String>[
      'Please look at ${person.fullName} (${person.ageLabel}) first.',
      if (_chosenYes.isNotEmpty)
        'What I noticed: ${_chosenYes.map((s) => s.toLowerCase()).join('; ')}.',
      if (_chosenUnsure.isNotEmpty)
        'I was not sure about: '
            '${_chosenUnsure.map((s) => s.toLowerCase()).join('; ')}.',
      'I will say when each sign started.',
    ];
    return parts.join(' ');
  }

  Future<void> _playWords() async {
    final outcome = await VoiceService.speakText(
      id: 'caregiver_nurse_words',
      text: _nurseWords(_person!),
      language: _language,
    );
    if (!mounted) return;
    if (outcome.source == VoiceSource.readAloud) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'The $_language voice is not on this phone yet. The words are on '
            'the screen — read them aloud, or ask someone to.',
          ),
        ),
      );
    }
  }

  void _copyWords(String message) {
    Clipboard.setData(ClipboardData(text: message));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied. Paste it into any message app.')),
    );
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

/// One question of the conversation: a pictogram, the question in large
/// type, a prominent "hear it aloud" button and three enormous answers.
/// Everything a non-reading caregiver needs is a single thumb-reach away.
class _SignQuestionCard extends StatelessWidget {
  const _SignQuestionCard({
    super.key,
    required this.question,
    required this.icon,
    required this.answer,
    required this.ack,
    required this.onChanged,
    required this.onPlay,
  });

  final String question;
  final IconData icon;
  final _SignAnswer answer;
  final String? ack;
  final ValueChanged<_SignAnswer> onChanged;

  /// Voice-first, master flow [41-C]: hear the question before answering it.
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Gap.radius),
        border: Border.all(
          color: answer == _SignAnswer.unset ? AppColors.line : answer.colour,
          width: answer == _SignAnswer.unset ? 1 : 1.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 30, color: AppColors.primary),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: Gap.xs),
                  child: Text(
                    question,
                    style: const TextStyle(
                      fontSize: 17.5,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary, width: 1.2),
              minimumSize: const Size.fromHeight(46),
            ),
            onPressed: onPlay,
            icon: const Icon(Icons.volume_up_rounded, size: 20),
            label: const Text(
              'Hear it aloud',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: Gap.md),
          _BigAnswer(
            label: 'YES',
            icon: Icons.check_rounded,
            selected: answer == _SignAnswer.yes,
            colour: AppColors.triageRed,
            onTap: () => onChanged(_SignAnswer.yes),
          ),
          const SizedBox(height: Gap.sm),
          _BigAnswer(
            label: 'NO',
            icon: Icons.close_rounded,
            selected: answer == _SignAnswer.no,
            colour: AppColors.triageGreen,
            onTap: () => onChanged(_SignAnswer.no),
          ),
          const SizedBox(height: Gap.sm),
          _BigAnswer(
            label: 'NOT SURE',
            icon: Icons.help_rounded,
            selected: answer == _SignAnswer.unsure,
            colour: AppColors.triageAmber,
            onTap: () => onChanged(_SignAnswer.unsure),
          ),
          if (ack != null) ...[
            const SizedBox(height: Gap.md),
            Text(
              ack!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                fontStyle: FontStyle.italic,
                color: AppColors.inkMuted,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A full-width, 56px answer — big enough for a thumb, a worried thumb
/// especially.
class _BigAnswer extends StatelessWidget {
  const _BigAnswer({
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
      borderRadius: BorderRadius.circular(Gap.radiusSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        onTap: onTap,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: selected ? Colors.white : colour),
              const SizedBox(width: Gap.sm),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: selected ? Colors.white : colour,
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
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
  }
}

/// The plan around the verdict: concrete, tickable steps a family can do
/// right now — pack the book, find a ride, keep breastfeeding — because
/// "go to the clinic" without the steps between the door and the gate is
/// only half a recommendation.
class _DoThisNowCard extends StatelessWidget {
  const _DoThisNowCard({
    required this.verdict,
    required this.person,
    required this.done,
    required this.onToggle,
  });

  final _TriageVerdict verdict;
  final Person person;
  final Set<String> done;
  final ValueChanged<String> onToggle;

  String get _title => switch (verdict) {
    _TriageVerdict.urgent => 'Do these now — even on the way',
    _TriageVerdict.caution => 'Do these today',
    _TriageVerdict.fine => 'Keep doing these',
  };

  List<(String, IconData, String)> _steps(Person person) {
    final first = person.fullName.split(' ').first;
    final mother =
        person.effectiveClientType != ClientType.newborn &&
        person.effectiveClientType != ClientType.childUnderFive;
    return switch (verdict) {
      _TriageVerdict.urgent => [
        (
          'book',
          Icons.menu_book_outlined,
          'Carry the health record book — the nurse will ask for it.',
        ),
        (
          'ride',
          Icons.two_wheeler_outlined,
          'Arrange a ride now. A neighbour\u2019s motorbike is fine — do not '
              'wait for a better one.',
        ),
        (
          'feed',
          Icons.local_drink_outlined,
          mother
              ? 'If she can swallow, give sips of water or fluids. If not, '
                    'do not force anything by mouth.'
              : 'If $first can swallow, keep breastfeeding or give sips of '
                    'fluid. If not, do not force anything by mouth.',
        ),
        (
          'company',
          Icons.group_outlined,
          'Go with someone if you can — a second person helps to carry and '
              'to explain.',
        ),
        (
          'words',
          Icons.record_voice_over_outlined,
          'At the gate, say what you noticed and when it started — or show '
              'the clinic pass below.',
        ),
      ],
      _TriageVerdict.caution => [
        (
          'see',
          Icons.medical_services_outlined,
          'Show $first to your CHW or the clinic within a day or two — do '
              'not wait for the next scheduled visit.',
        ),
        (
          'watch',
          Icons.visibility_outlined,
          'Watch morning and evening. If any danger sign appears, go to the '
              'facility the same day.',
        ),
        (
          'feed',
          Icons.local_drink_outlined,
          'Keep feeding and drinking as normal — small amounts, often.',
        ),
        (
          'note',
          Icons.edit_note_outlined,
          'Remember when each sign started — the nurse will ask.',
        ),
      ],
      _TriageVerdict.fine => [
        (
          'feed',
          Icons.restaurant_outlined,
          mother
              ? 'Rest when the baby rests, and eat one extra meal a day.'
              : 'Keep feeding as you are — breastmilk, thick porridge and '
                    'family foods.',
        ),
        (
          'check',
          Icons.refresh_rounded,
          'Check again tomorrow, or any time something worries you.',
        ),
        (
          'play',
          Icons.sports_handball_outlined,
          mother
              ? 'Talk, sing and cuddle the baby every day — a child who is '
                    'played with, learns.'
              : 'Play and talk with $first every day — a child who is '
                    'played with, learns.',
        ),
      ],
    };
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps(person);
    final doneCount = steps.where((s) => done.contains(s.$1)).length;
    final colour = verdict.colour;
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Gap.radius),
        border: Border.all(color: colour.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(Gap.xs + 2),
                decoration: BoxDecoration(
                  color: colour.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.checklist_rounded, size: 20, color: colour),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  _title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: colour,
                  ),
                ),
              ),
              Text(
                '$doneCount of ${steps.length} done',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          for (final (id, icon, text) in steps)
            InkWell(
              onTap: () => onToggle(id),
              borderRadius: BorderRadius.circular(Gap.radiusXs),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.xs + 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      done.contains(id) ? Icons.check_circle_rounded : icon,
                      size: 20,
                      color: done.contains(id)
                          ? AppColors.triageGreen
                          : AppColors.inkMuted,
                    ),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: done.contains(id)
                              ? AppColors.inkMuted
                              : AppColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (doneCount == steps.length)
            const Padding(
              padding: EdgeInsets.only(top: Gap.xs),
              child: Text(
                'Well done — you are doing everything right.',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.triageGreen,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The caregiver's own observation, composed into the sentence she will say
/// at the gate — playable aloud so the words travel even if her confidence
/// does not, and copyable for any message app.
class _TellTheNurseCard extends StatelessWidget {
  const _TellTheNurseCard({
    required this.message,
    required this.onPlay,
    required this.onCopy,
  });

  final String message;
  final VoidCallback onPlay;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(Gap.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.record_voice_over_outlined,
                size: 20,
                color: AppColors.primary,
              ),
              SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  'YOUR WORDS FOR THE NURSE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Text(
            message,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: Gap.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(44),
                  ),
                  onPressed: onPlay,
                  icon: const Icon(Icons.volume_up_rounded, size: 18),
                  label: const Text('Hear it aloud'),
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: TextButton.icon(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy the words'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The check ends with what the family CAN do at the next meal, not only
/// with what is wrong. Real Northern Ghana foods, photographed — advice
/// that shows the actual pot is advice that gets cooked.
class _FamilyFeedingCard extends StatelessWidget {
  const _FamilyFeedingCard({required this.person, required this.verdict});

  final Person person;
  final _TriageVerdict verdict;

  /// Every food below is drawn from the same LocalFoods dataset the
  /// nutrition engine recommends from: year-round, in the cheapest cost
  /// tiers, and age-appropriate from six months. One card per WHO food
  /// group a child needs for dietary diversity.
  static const _childFoods = [
    (
      image: AppImages.foodMilletPorridge,
      name: 'Millet porridge',
      local: 'Za',
      reason:
          'Gives energy for the whole day. Cook it thick, so it sits on '
          'the spoon — thin porridge fills the stomach without feeding.',
    ),
    (
      image: AppImages.foodGroundnutPaste,
      name: 'Groundnut paste',
      local: 'Sinkpam',
      reason:
          'Stir one spoon into every bowl of porridge. The cheapest way '
          'to add energy and protein. Smooth paste only — whole nuts '
          'choke young children.',
    ),
    (
      image: AppImages.foodCowpeaStew,
      name: 'Cowpea (beans)',
      local: 'Tuya',
      reason:
          'Beans build the body with protein and iron. Cook until very '
          'soft and mash well.',
    ),
    (
      image: AppImages.foodDriedFish,
      name: 'Dried fish powder',
      local: 'Zahim',
      reason:
          'The cheapest animal food in the north. Pound one small fish, '
          'bones included, and stir a spoon into the porridge.',
    ),
    (
      image: AppImages.foodBoiledEgg,
      name: 'Egg',
      local: '',
      reason:
          'One boiled egg a day builds the body and the eyes. Always '
          'fully cooked, never soft.',
    ),
    (
      image: AppImages.foodSweetPotato,
      name: 'Orange-fleshed sweet potato',
      local: '',
      reason:
          'Choose the orange kind, not white. One small tuber covers a '
          'young child\u2019s vitamin A for the day.',
    ),
    (
      image: AppImages.foodMoringaBaobab,
      name: 'Moringa and baobab leaves',
      local: 'Zogale',
      reason:
          'Green leaves protect against illness. Stir a spoon of dried '
          'powder into the porridge every day.',
    ),
    (
      image: AppImages.foodPawpaw,
      name: 'Ripe pawpaw',
      local: '',
      reason:
          'Soft, sweet and available all year. Mash two spoons as a '
          'snack between meals.',
    ),
  ];

  static const _motherFoods = [
    (
      image: AppImages.foodMilletPorridge,
      name: 'Millet porridge',
      local: 'Za',
      reason: 'Warm porridge keeps your strength up and helps your milk flow.',
    ),
    (
      image: AppImages.foodCowpeaStew,
      name: 'Cowpea (beans)',
      local: 'Tuya',
      reason: 'Beans give the protein and iron your body is rebuilding with.',
    ),
    (
      image: AppImages.foodMoringaBaobab,
      name: 'Moringa and baobab leaves',
      local: 'Zogale',
      reason:
          'Green leaves give iron and vitamins for you and your milk. '
          'Free from the compound tree, every month of the year.',
    ),
    (
      image: AppImages.foodGroundnutPaste,
      name: 'Groundnut paste',
      local: 'Sinkpam',
      reason:
          'One spoon in your porridge adds the energy a nursing mother '
          'burns through.',
    ),
    (
      image: AppImages.foodDriedFish,
      name: 'Dried fish powder',
      local: 'Zahim',
      reason:
          'Cheap iron and calcium, especially while you are recovering '
          'after delivery.',
    ),
    (
      image: AppImages.foodBoiledEgg,
      name: 'Egg',
      local: '',
      reason: 'One boiled egg a day helps you rebuild strength quickly.',
    ),
    (
      image: AppImages.foodDawadawa,
      name: 'Dawadawa (locust bean)',
      local: 'Kpalgu',
      reason:
          'Already in almost every northern kitchen and unusually rich '
          'in iron. Add a ball to your daily soup.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final type = person.effectiveClientType;
    final isNewborn = type == ClientType.newborn;
    final isChild = type == ClientType.childUnderFive;
    final foods = isChild ? _childFoods : _motherFoods;

    return SectionCard(
      title: isNewborn ? 'Feeding your newborn today' : 'Feeding today',
      subtitle: isNewborn
          ? 'Breastmilk is the one food and the first medicine.'
          : 'Foods from your own market that help recovery.',
      icon: isNewborn ? Icons.child_care_rounded : Icons.restaurant_rounded,
      accent: AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (verdict == _TriageVerdict.urgent)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.md),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Gap.md),
                decoration: BoxDecoration(
                  color: AppColors.triageAmber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Gap.radiusSm),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.local_drink_rounded,
                      color: AppColors.triageAmber,
                      size: 20,
                    ),
                    SizedBox(width: Gap.sm),
                    Expanded(
                      child: Text(
                        'Keep offering breastmilk and fluids, even on the '
                        'way to the clinic.',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (isNewborn)
            for (final (icon, line) in const [
              (Icons.favorite_rounded, 'Breastfeed often, day and night.'),
              (
                Icons.water_drop_outlined,
                'Breastmilk alone is enough. No water is needed.',
              ),
              (
                Icons.self_improvement_rounded,
                'Skin-to-skin cuddles keep the baby warm and feeding well.',
              ),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 18, color: AppColors.primary),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      child: Text(
                        line,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              )
          else
            for (final f in foods) _FeedingTile(food: f),
        ],
      ),
    );
  }
}

/// One photographed food: picture, name with its local name, and the
/// reason it helps, in three lines a caregiver can read at a glance.
class _FeedingTile extends StatelessWidget {
  const _FeedingTile({required this.food});

  final ({String image, String name, String local, String reason}) food;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: Gap.sm),
    padding: const EdgeInsets.all(Gap.md),
    decoration: BoxDecoration(
      color: AppColors.canvas,
      borderRadius: BorderRadius.circular(Gap.radiusSm),
      border: Border.all(color: AppColors.line),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(Gap.radiusXs),
          child: SizedBox(
            width: 64,
            height: 64,
            child: AppImage(src: food.image),
          ),
        ),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      food.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (food.local.isNotEmpty) ...[
                    const SizedBox(width: Gap.xs),
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
                        food.local,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: Gap.xs),
              Text(
                food.reason,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.inkMuted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// The recommendation's evidence, restyled: the very signs the family
/// just answered, now laid out like a note the nurse can read at a glance.
class _SignsCard extends StatelessWidget {
  const _SignsCard({
    required this.title,
    required this.icon,
    required this.colour,
    required this.signs,
    required this.note,
  });

  final String title;
  final IconData icon;
  final Color colour;
  final List<String> signs;
  final String note;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: title,
    icon: icon,
    accent: colour,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in signs)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: colour,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    s,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Text(
          note,
          style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
        ),
      ],
    ),
  );
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
            children: [for (final c in list) _ContactTile(contact: c)],
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
                    color: overdue ? AppColors.triageAmber : AppColors.inkMuted,
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
    final region =
        household.valueOrNull?.region ?? user?.region ?? 'Northern Region';
    final languages = NorthernGhana.languagesOf(region);
    final language = _language ?? user?.preferredLanguage ?? 'English';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice'),
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
    setState(
      () =>
          _playing = outcome.source == VoiceSource.readAloud ? null : topic.id,
    );
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
/// builds it. Each tile offers both, in the family's own words, using only
/// what is already in the compound. The tab shows one tile per child inside
/// the tracked window (birth to five years).
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
          _GrowthStoryStrip(child: child),
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

/// The same trajectory the health worker sees on the verdict screen,
/// translated into family words — one engine, two honest voices. The
/// numbers come from the measurements the health worker recorded; when
/// there are not enough of them, the strip says so instead of guessing.
/// A voice button reads it aloud, because this screen must work for eyes
/// that do not read.
class _GrowthStoryStrip extends ConsumerWidget {
  const _GrowthStoryStrip({required this.child});

  final Person child;

  String get _first => child.fullName.split(' ').first;

  String _gainDetail(TrajectoryResult t) {
    final parts = <String>[];
    final w = t.weightChangePerMonth;
    if (w != null && w > 0) {
      parts.add('about ${(w * 1000).round()} g heavier each month');
    }
    final m = t.muacChangePerMonth;
    if (m != null && m > 0) {
      parts.add('about ${m.toStringAsFixed(1)} cm more around the arm');
    }
    if (parts.isEmpty) {
      return 'Keep up the feeding and the play — it is working.';
    }
    return 'Gaining ${parts.join(' and ')}. Keep up the feeding and the play.';
  }

  Future<void> _speak(WidgetRef ref, String text) async {
    final user = ref.read(currentUserProvider);
    await VoiceService.speakText(
      id: 'caregiver_growth_story_${child.id}',
      text: text,
      language: user?.preferredLanguage ?? 'English',
    );
  }

  Widget _strip({
    required IconData icon,
    required Color accent,
    required String headline,
    required String detail,
    required WidgetRef ref,
  }) {
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: accent),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: accent,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.inkMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: Gap.xs),
                Text(
                  'Measured by the health worker — you see the same story '
                  'they see.',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppColors.inkFaint,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Hear this',
            onPressed: () => _speak(ref, '$headline $detail'),
            icon: Icon(Icons.volume_up_rounded, color: accent, size: 22),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(trajectoryProvider(child.id))
        .when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (t) {
            if (t.trend == GrowthTrend.insufficientData) {
              return _strip(
                icon: Icons.hourglass_bottom_rounded,
                accent: AppColors.inkMuted,
                headline:
                    'The growth story starts after the second measurement.',
                detail:
                    'Once $_first is measured at least twice, this space will '
                    'show which way they are going.',
                ref: ref,
              );
            }
            final (accent, icon, headline, detail) = switch (t.trend) {
              GrowthTrend.rising => (
                AppColors.triageGreen,
                Icons.trending_up_rounded,
                '$_first is growing well.',
                _gainDetail(t),
              ),
              GrowthTrend.flat => (
                AppColors.triageAmber,
                Icons.trending_flat_rounded,
                '$_first has not been gaining between visits.',
                'A young child who is not gaining needs to be seen — go to the '
                    'clinic this week.',
              ),
              GrowthTrend.falling => (
                AppColors.triageRed,
                Icons.trending_down_rounded,
                '$_first is getting thinner between visits.',
                t.daysToSamThreshold != null
                    ? 'At this pace the danger line is about '
                          '${(t.daysToSamThreshold! / 7).round().clamp(1, 52)} '
                          'weeks away. Go to the clinic today if you can.'
                    : 'Go to the clinic this week — earlier is better.',
              ),
              GrowthTrend.insufficientData => (
                AppColors.inkMuted,
                Icons.hourglass_bottom_rounded,
                '',
                '',
              ),
            };
            return _strip(
              icon: icon,
              accent: accent,
              headline: headline,
              detail: detail,
              ref: ref,
            );
          },
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

  /// The child's last check BEFORE this run — read in [initState], before
  /// saving, so the result screen can celebrate what changed. Null on a
  /// first check, where there is nothing to compare yet.
  MilestoneCheck? _previous;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadPrevious);
  }

  Future<void> _loadPrevious() async {
    try {
      final prev = await ref.read(
        latestMilestoneCheckProvider(widget.personId).future,
      );
      if (mounted) setState(() => _previous = prev);
    } catch (_) {
      // No history to compare: the progress memory simply never renders.
    }
  }

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
    final answered = band.milestones
        .where((m) => _answers.containsKey(m.id))
        .length;
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
              for (final m in band.milestones)
                _MilestoneQuestionTile(
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
                  color: allAnswered ? AppColors.primary : AppColors.inkMuted,
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
                      MilestoneVerdict.flag =>
                        Icons.medical_information_rounded,
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
              Text(switch (verdict) {
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
              }, style: const TextStyle(fontSize: 14, height: 1.45)),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),

        // The nurturing-care closed loop, family side: the app remembers
        // the last check and shows what changed since. Compared strictly
        // from two checks this family recorded — nothing invented.
        if (_previous != null) ...[
          _ProgressMemoryCard(
            firstName: person.fullName.split(' ').first,
            previous: _previous!,
            band: band,
            answers: _answers,
          ),
          const SizedBox(height: Gap.md),
        ],

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

/// "Look how far they've come." Every milestone check is saved, so the
/// second time a family runs one, the app can compare — the questions the
/// child could not do last time and now can. It is the nurturing-care
/// closed loop seen from the family's side, and it is built only from the
/// family's own recorded checks: if nothing improved, the card says so
/// gently instead of inventing progress.
class _ProgressMemoryCard extends StatelessWidget {
  const _ProgressMemoryCard({
    required this.firstName,
    required this.previous,
    required this.band,
    required this.answers,
  });

  final String firstName;
  final MilestoneCheck previous;
  final NcAgeBand band;
  final Map<String, bool> answers;

  @override
  Widget build(BuildContext context) {
    // Compare last run's "not yet" against this run's answers. Only
    // questions that still exist in the current band can be compared —
    // the band changes as the child grows.
    final questionToId = {for (final m in band.milestones) m.question: m.id};
    final newly = <String>[];
    final stillPracticing = <String>[];
    for (final q in previous.notYet) {
      final id = questionToId[q];
      if (id == null) continue;
      if (answers[id] == true) {
        newly.add(q);
      } else if (answers[id] == false) {
        stillPracticing.add(q);
      }
    }
    final when = DateFormat('d MMM').format(previous.checkedAt);

    return SectionCard(
      title: 'Look how far they\u2019ve come',
      icon: Icons.stars_rounded,
      accent: AppColors.triageGreen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (newly.isNotEmpty) ...[
            Text(
              'Since the check on $when, $firstName learned:',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: Gap.xs),
            for (final q in newly)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.xs),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.triageGreen,
                    ),
                    const SizedBox(width: Gap.xs),
                    Expanded(
                      child: Text(
                        q,
                        style: const TextStyle(fontSize: 14.5, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            if (stillPracticing.isNotEmpty) ...[
              const SizedBox(height: Gap.xs),
              Text(
                'Still practicing: ${stillPracticing.join(' · ')}. Every '
                'child has their own pace.',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.inkMuted,
                  height: 1.4,
                ),
              ),
            ],
          ] else if (previous.notYet.isNotEmpty) ...[
            Text(
              'The check on $when found ${previous.notYet.length} things '
              'still coming. They are still practicing — play the ideas '
              'below and check again in a few weeks. If you are worried, '
              'show the health worker.',
              style: const TextStyle(fontSize: 14, height: 1.45),
            ),
          ] else ...[
            Text(
              'Last time ($when) everything was a yes. Keep playing — play '
              'is how the brain grows.',
              style: const TextStyle(fontSize: 14, height: 1.45),
            ),
          ],
        ],
      ),
    );
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

// ------------------------------------------------------------ Language sheet

/// The caregiver's language picker. The region decides the list; picking a
/// language writes it to the user record through the session, so every audio
/// button — danger-sign questions, topics, the spoken result — plays in it
/// immediately.
class _GuidanceLanguageSheet extends ConsumerWidget {
  const _GuidanceLanguageSheet({required this.current, required this.region});

  final String current;
  final String? region;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final languages = NorthernGhana.languagesOf(region ?? 'Northern Region');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Guidance language',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: Gap.xs),
            Text(
              'Every voice in this app — the questions, the guidance, and '
              'your check results — speaks in the language you pick here.',
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
              ).copyWith(color: AppColors.inkMuted),
            ),
            const SizedBox(height: Gap.md),
            for (final lang in languages)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  lang == current
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: lang == current
                      ? AppColors.primary
                      : AppColors.inkFaint,
                ),
                title: Text(
                  lang,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: lang == current
                        ? FontWeight.w800
                        : FontWeight.w500,
                  ),
                ),
                onTap: () async {
                  await ref.read(sessionProvider.notifier).updateLanguage(lang);
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    );
  }
}
