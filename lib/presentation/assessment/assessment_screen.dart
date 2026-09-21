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
import '../../data/repositories/care_repository.dart';
import '../../domain/entities/core.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../fhw/clinic_widgets.dart';
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
  bool _chartStarted = false;
  bool _allowExit = false;
  bool _confirmingExit = false;
  bool _openingResult = false;

  /// What the station handed over. Empty when the nurse skipped it.
  StationResult _vitals = StationResult.empty;

  /// Set when the form sends the nurse back to one vital.
  String? _retakeKey;

  void _toChart(StationResult result) => setState(() {
    _vitals = result;
    _retakeKey = null;
    _chartStarted = true;
    _stage = _Stage.chart;
  });

  void _retake(String key) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _retakeKey = key;
      _stage = _Stage.station;
    });
  }

  Future<void> _confirmExit() async {
    if (_confirmingExit || _allowExit) return;
    _confirmingExit = true;
    try {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Unsaved assessment'),
          content: const Text(
            'Leaving will discard the measurements and clinical assessment '
            'entered here. Only saved assessments are kept.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep assessing'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Discard and leave'),
            ),
          ],
        ),
      );
      if (discard == true && mounted) await _leave(false);
    } finally {
      _confirmingExit = false;
    }
  }

  Future<void> _leave(bool saved) async {
    setState(() => _allowExit = true);
    // Let PopScope observe the authorized exit before popping the route.
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop(saved);
  }

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

          return ColoredBox(
            color: AppColors.surface,
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.fullName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.title.copyWith(color: AppColors.primaryDark),
                        ),
                        Text(
                          '${p.ageLabel} · ${h.name}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.caption.copyWith(color: AppColors.ink),
                        ),
                        ClinicStepHeader(
                          steps: const ['Measurements', 'Clinical assessment'],
                          current: _stage == _Stage.station ? 0 : 1,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: IndexedStack(
                      index: _stage == _Stage.station ? 0 : 1,
                      children: [
                        // Only the station is remounted: its initial values and
                        // startAtKey are consumed in initState on every retake.
                        if (_stage == _Stage.station)
                          VitalsStationScreen(
                            key: ValueKey('station-${p.id}'),
                            input: ctx,
                            initial: _vitals,
                            startAtKey: _retakeKey,
                            onContinue: _toChart,
                            onSkip: () => _toChart(_vitals),
                            onDanger: () => _toChart(_vitals),
                          )
                        else
                          const SizedBox.shrink(),
                        // Once begun, the same chart State survives every trip
                        // back to measurements, including its signs and edits.
                        if (_chartStarted)
                          TickerMode(
                            enabled: _stage == _Stage.chart,
                            child: Scaffold(
                              backgroundColor: AppColors.surface,
                              appBar: AppBar(
                                backgroundColor: AppColors.surface,
                                foregroundColor: AppColors.primaryDark,
                                surfaceTintColor: Colors.transparent,
                                elevation: 0,
                                title: const Text('Assessment'),
                                actions: [
                                  IconButton(
                                    tooltip: 'Voice guide',
                                    icon: const Icon(Icons.record_voice_over_rounded),
                                    onPressed: () => _speakWelcome(p.fullName),
                                  ),
                                ],
                              ),
                              body: form,
                            ),
                          )
                        else
                          const SizedBox.shrink(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    return PopScope<bool>(
      canPop: _allowExit,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmExit();
      },
      child: body,
    );
  }

  /// Loading, error and not-found states: a bar so the nurse can go back.
  Widget _plainShell(Widget child) => Scaffold(
    backgroundColor: AppColors.surface,
    appBar: AppBar(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.primaryDark,
      surfaceTintColor: Colors.transparent,
      title: const Text('Assessment'),
    ),
    body: child,
  );

  Future<void> _showResult(
    BuildContext context,
    AssessmentContext ctx,
    AssessmentDraft draft,
  ) async {
    if (_openingResult) return;
    _openingResult = true;
    try {
      // Load history before navigation: treatment-response rules and the
      // referral toggle must see the saved growth trend from the outset.
      var priorGrowth = const <GrowthMeasurement>[];
      try {
        priorGrowth = await ref
            .read(careRepositoryProvider)
            .growthSeries(ctx.user, ctx.person.id);
      } on AccessDenied {
        // Preserve the existing permission rule: inaccessible history is not
        // used, but the assessment itself can continue.
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not load previous growth measurements. '
                'Your assessment is still open. Try again.',
              ),
            ),
          );
        }
        // Do not silently drop history and change treatment-response input.
        return;
      }
      if (!context.mounted) return;
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => AssessmentResultScreen(
            input: ctx,
            draft: draft,
            visitId: visit.id,
            priorGrowth: priorGrowth,
          ),
        ),
      );
      if (saved == true && mounted) await _leave(true);
    } finally {
      // Forms own their busy state. This only prevents duplicate result
      // routes while loading/navigating, and must be released on failure too.
      _openingResult = false;
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
