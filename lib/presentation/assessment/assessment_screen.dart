/// The assessment shell: load what the record already knows, hand the person
/// to the right protocol form, and carry the draft to the result screen.
///
/// The protocol is chosen from [Person.effectiveClientType] — the age-derived
/// type — so a baby registered as a newborn who has since turned three months
/// is assessed on the sick-child chart without anyone having to relabel them.
///
/// Access is enforced twice on this screen and never in the UI alone: the
/// repository re-checks [Permission.runClinicalAssessment] on every write, and
/// the screen itself refuses to render for a user without it. A caregiver can
/// never reach this screen through the router, and even a forged deep link
/// would stop at the repository.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/audio/voice_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/motion.dart';
import '../../data/repositories/care_repository.dart';
import '../../domain/entities/core.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../shared/ui.dart';
import 'child_form.dart';
import 'maternal_form.dart';
import 'result_screen.dart';
import 'station/vitals_station_screen.dart';
import 'types.dart';

/// Where the nurse is: taking vitals at the station, or working the chart.
enum _Stage { station, chart }

class AssessmentScreen extends ConsumerStatefulWidget {
  const AssessmentScreen({
    super.key,
    required this.visit,
    required this.personId,
  });

  final Visit visit;
  final String personId;

  @override
  ConsumerState<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends ConsumerState<AssessmentScreen> {
  Visit get visit => widget.visit;
  String get personId => widget.personId;

  _Stage _stage = _Stage.station;

  /// What the station handed over. Empty when the nurse skipped it.
  StationResult _vitals = StationResult.empty;

  /// Set when the form sends the nurse back to one vital.
  String? _retakeKey;

  void _toChart(StationResult result) => setState(() {
    _vitals = result;
    _retakeKey = null;
    _stage = _Stage.chart;
  });

  void _retake(String key) => setState(() {
    _retakeKey = key;
    _stage = _Stage.station;
  });

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null || !user.can(Permission.runClinicalAssessment)) {
      return const Scaffold(
        body: AccessDeniedView(
          message:
              'Only a frontline health worker can run a clinical assessment. '
              'This account does not have that permission.',
        ),
      );
    }

    final household = ref.watch(householdProvider(visit.householdId));
    final person = ref.watch(personProvider(personId));
    final maternal = ref.watch(maternalRecordProvider(personId));
    final birth = ref.watch(birthRecordProvider(personId));

    final body = household.when(
      loading: () =>
          _plainShell(const Center(child: CircularProgressIndicator())),
      error: (e, _) =>
          _plainShell(ErrorView(error: e is AccessDenied ? e.message : e)),
      data: (h) => person.when(
        loading: () =>
            _plainShell(const Center(child: CircularProgressIndicator())),
        error: (e, _) =>
            _plainShell(ErrorView(error: e is AccessDenied ? e.message : e)),
        data: (p) {
          if (h == null || p == null) {
            return _plainShell(
              const EmptyState(
                icon: Icons.person_off_outlined,
                title: 'Record not found',
                message:
                    'This person or household could not be loaded. It may have '
                    'been removed, or this account may not have access to it.',
              ),
            );
          }

          final ctx = AssessmentContext(
            user: user,
            household: h,
            person: p,
            maternal: maternal.valueOrNull,
            birth: birth.valueOrNull,
          );

          if (_stage == _Stage.station) {
            return VitalsStationScreen(
              key: ValueKey('station-${p.id}'),
              input: ctx,
              initial: _vitals.isEmpty ? null : _vitals,
              startAtKey: _retakeKey,
              onContinue: _toChart,
              onSkip: () => _toChart(_vitals),
              onDanger: () => _toChart(_vitals),
            );
          }

          final form = switch (p.effectiveClientType) {
            ClientType.pregnantWoman ||
            ClientType.postpartumWoman ||
            ClientType.womanOfReproductiveAge => MaternalProtocolForm(
              key: ValueKey('maternal-${p.id}'),
              input: ctx,
              initialVitals: _vitals,
              onRetakeVital: _retake,
              onComplete: (draft) => _showResult(context, ctx, draft),
            ),
            ClientType.newborn ||
            ClientType.childUnderFive => ChildProtocolForm(
              key: ValueKey('child-${p.id}'),
              input: ctx,
              initialVitals: _vitals,
              onRetakeVital: _retake,
              onComplete: (draft) => _showResult(context, ctx, draft),
            ),
          };

          return Scaffold(
            backgroundColor: Colors.transparent,
            appBar: GlassAppBar(
              title: const Text('Assessment'),
              actions: [
                IconButton(
                  tooltip: 'Voice guide',
                  icon: const Icon(Icons.record_voice_over_rounded),
                  onPressed: () => _speakWelcome(p.fullName),
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(22),
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: Gap.lg,
                    right: Gap.lg,
                    bottom: Gap.sm,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      h.name,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.inkMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            body: form,
          );
        },
      ),
    );

    // Each stage brings its own Scaffold and app bar; the shell only owns the
    // backdrop, the Lite-mode scope and the cross-fade between stages. The
    // scope is mounted *here*, so the switcher reads the preference directly.
    final motion =
        !ref.watch(visualEffectsProvider) &&
        !MediaQuery.disableAnimationsOf(context);

    return VisualEffectsScope(
      child: AmbientBackdrop(
        child: AnimatedSwitcher(
          duration: motion ? AppMotion.duration : Duration.zero,
          switchInCurve: AppMotion.curve,
          switchOutCurve: AppMotion.curve,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.02),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: KeyedSubtree(key: ValueKey(_stage), child: body),
        ),
      ),
    );
  }

  /// Loading, error and not-found states: a bar so the nurse can go back.
  Widget _plainShell(Widget child) => Scaffold(
    backgroundColor: Colors.transparent,
    appBar: const GlassAppBar(title: Text('Assessment')),
    body: child,
  );

  Future<void> _showResult(
    BuildContext context,
    AssessmentContext ctx,
    AssessmentDraft draft,
  ) async {
    // Load the child's saved growth series now, before navigation, so the
    // result screen can compute treatment response (weight-gain rate)
    // synchronously. The verdict that seeds the referral toggle must already
    // know whether a child on feeding is losing weight — that cannot wait on
    // an async load after the screen is built.
    var priorGrowth = const <GrowthMeasurement>[];
    try {
      priorGrowth = await ref
          .read(careRepositoryProvider)
          .growthSeries(ctx.user, ctx.person.id);
    } on AccessDenied {
      // No growth history this account may see; treatment response simply
      // does not run. The assessment itself is unaffected.
    }
    if (!context.mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      GlassPageRoute<bool>(
        builder: (_) => AssessmentResultScreen(
          input: ctx,
          draft: draft,
          visitId: visit.id,
          priorGrowth: priorGrowth,
        ),
      ),
    );
    if (saved == true && context.mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _speakWelcome(String patientName) async {
    final message =
        'Welcome to the assessment for $patientName. '
        'Follow the form sections: first check vital signs, then look for danger signs, '
        'then record measurements. Take your time — the app will guide you.';
    await VoiceService.speakText(
      id: 'assessment-welcome',
      text: message,
      language: 'en',
    );
  }
}
