import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../core/audio/caregiver_playback.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/glass.dart';
import '../../../core/theme/motion.dart';
import '../../../domain/engines/nurturing_care_engine.dart';
import '../../../domain/entities/caregiver.dart';
import '../../../domain/entities/core.dart';
import '../../../domain/enums.dart';
import '../../../domain/services/caregiver_milestone_policy.dart';
import '../caregiver_providers.dart';
import '../care_plan/preparation.dart';
import '../family/person_detail.dart';
import '../food/food_page.dart';
import '../help/caregiver_voice.dart';
import '../widgets/companion.dart';
import 'milestone_screen.dart';

class CaregiverGrowPlayTab extends ConsumerWidget {
  const CaregiverGrowPlayTab({super.key, required this.householdId});
  final String householdId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(caregiverScopeProvider);
    if (scope == null) return const SizedBox.shrink();
    final now = ref.watch(caregiverCalendarProvider);
    final settings = ref.watch(caregiverSettingsProvider(scope));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        GlassSurface(
          tier: GlassTier.hero,
          blur: false,
          padding: EdgeInsets.zero,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GlassTier.hero.radius),
              gradient: AppColors.caregiverGradient,
            ),
            child: const Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.toys_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Grow and play',
                          style: TextStyle(
                            fontFamily: 'Sora',
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 14),
                  Text(
                    "Notice, talk, and play at your own pace. No scores or competition \u2014 every family\u2019s day is different.",
                    style: TextStyle(
                      color: AppColors.white85,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ref
            .watch(caregiverClinicalProvider(scope))
            .when(
              loading: () => const Text('Loading saved family records…'),
              error: (_, _) => CompanionLoadError(
                onRetry: () => ref.invalidate(caregiverClinicalProvider(scope)),
              ),
              data: (data) => settings.when(
                loading: () => const Text('Loading your family selection…'),
                error: (_, _) => CompanionLoadError(
                  onRetry: () =>
                      ref.invalidate(caregiverSettingsProvider(scope)),
                ),
                data: (saved) {
                  final members = data.members
                      .where(
                        (p) =>
                            saved.selectedPersonId == null ||
                            p.id == saved.selectedPersonId,
                      )
                      .toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CaregiverPersonSelector(members: data.members),
                      if (members.isEmpty)
                        const CompanionCard(
                          title: 'Start with your family',
                          child: Text(
                            'Add a family member from Family to see play ideas and saved growth records.',
                          ),
                        ),
                      for (final person in members) ...[
                        if (person.clientType == ClientType.newborn ||
                            person.clientType == ClientType.childUnderFive) ...[
                          _PlayTogether(
                            key: ValueKey(
                              '${person.id}/${caregiverDateKey(now)}',
                            ),
                            person: person,
                            now: now,
                          ),
                          _GrowthRecords(person: person),
                          CompanionCard(
                            title:
                                'Your dated observations • ${person.fullName}',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (!data.milestones.any(
                                  (m) => m.personId == person.id,
                                ))
                                  const Text('No milestone check saved yet.'),
                                for (final check
                                    in data.milestones
                                        .where((m) => m.personId == person.id)
                                        .take(3))
                                  ExpansionTile(
                                    tilePadding: EdgeInsets.zero,
                                    title: Text(caregiverWhen(check.checkedAt)),
                                    subtitle: Text(
                                      '${check.bandLabel} • caregiver report',
                                    ),
                                    children: [
                                      if (check.flags.isNotEmpty)
                                        Text(
                                          "Discuss with a health worker:\n${check.flags.join('\n')}",
                                        ),
                                      Text(
                                        "Observed then:\n${check.canDo.isEmpty ? 'No skills marked Yes.' : check.canDo.join('\n')}",
                                      ),
                                      Text(
                                        "Not yet observed then:\n${check.notYet.isEmpty ? 'None recorded.' : check.notYet.join('\n')}",
                                      ),
                                      const Text(
                                        "Historical screening, not a diagnosis or today's state.",
                                      ),
                                    ],
                                  ),
                                OutlinedButton(
                                  onPressed: () => Navigator.of(context).push(
                                    GlassPageRoute<void>(
                                      builder: (_) => CaregiverPersonDetail(
                                        personId: person.id,
                                      ),
                                    ),
                                  ),
                                  child: const Text(
                                    'See full history and notes',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (person.clientType ==
                                ClientType.pregnantWoman ||
                            person.clientType == ClientType.postpartumWoman)
                          _MaternalPreparation(person: person, now: now),
                      ],
                    ],
                  );
                },
              ),
            ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            GlassPageRoute<void>(
              builder: (_) => CaregiverFoodPage(householdId: householdId),
            ),
          ),
          icon: const Icon(Icons.restaurant_outlined),
          label: const Text('Food for today', textAlign: TextAlign.center),
        ),
      ],
    );
  }
}

class _PlayTogether extends StatelessWidget {
  const _PlayTogether({super.key, required this.person, required this.now});
  final Person person;
  final DateTime now;
  @override
  Widget build(BuildContext context) {
    final band = CaregiverMilestonePolicy.bandFor(person, now);
    if (band == null) {
      return CompanionCard(
        title: 'Play together • ${person.fullName}',
        child: const Text(
          "Confirm the child's date of birth for age-band activities. These milestone checks cover birth to under five years. You can still talk, sing, and respond to the child.",
        ),
      );
    }
    final activity = NurturingCareEngine.activityToday(band, now);
    return CompanionCard(
      title: 'Play together today',
      eyebrow: '${person.fullName} • ${caregiverAge(person)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            activity,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          const Text(
            'Use familiar household items only when safe for this child. Stay close; keep small objects, sharp items, and anything that can cover the face out of reach. Stop if the child is tired or uncomfortable. No special toy is needed.',
          ),
          CaregiverListen(
            speech: CaregiverSpeech(
              id: 'play_${person.id}_${caregiverDateKey(now)}',
              english: activity,
              language: 'English',
            ),
          ),
          const _PlayTimer(),
          CaregiverTaskToggle(
            personId: person.id,
            kind: CaregiverActivityKind.playSession,
            sourceId: 'play-${band.minMonths}-${band.maxMonths}',
            itemKey: activity,
            occurrenceKey: caregiverDateKey(now),
            label: 'We tried this',
          ),
          const Text(
            'This records trying an activity, not a milestone or developmental result.',
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.of(context).push(
              GlassPageRoute<void>(
                builder: (_) => CaregiverMilestoneScreen(person: person),
              ),
            ),
            child: const Text('Check the milestones'),
          ),
        ],
      ),
    );
  }
}

class _PlayTimer extends StatefulWidget {
  const _PlayTimer();
  @override
  State<_PlayTimer> createState() => _PlayTimerState();
}

class _PlayTimerState extends State<_PlayTimer> with WidgetsBindingObserver {
  Timer? _timer;
  int _remaining = 120;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _pause() {
    _timer?.cancel();
    _timer = null;
  }

  void _start() {
    if (_remaining == 0) _remaining = 120;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remaining--;
        if (_remaining == 0) _pause();
      });
    });
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _pause();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _pause();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        _remaining == 0
            ? 'Timer finished. Nothing was marked done.'
            : 'Optional two-minute timer: ${_remaining ~/ 60}:${(_remaining % 60).toString().padLeft(2, '0')}',
      ),
      OutlinedButton(
        onPressed: _timer == null
            ? _start
            : () {
                setState(_pause);
              },
        child: Text(
          _timer != null
              ? 'Pause timer'
              : _remaining == 120 || _remaining == 0
              ? 'Start optional timer'
              : 'Resume timer',
        ),
      ),
      const Text(
        'Not a target or alarm. Pauses when the app backgrounds; leaving this tab resets it.',
      ),
    ],
  );
}

class _GrowthRecords extends ConsumerWidget {
  const _GrowthRecords({required this.person});
  final Person person;
  @override
  Widget build(BuildContext context, WidgetRef ref) => CompanionCard(
    title: 'Clinic growth measurements',
    eyebrow: person.fullName,
    child: ref
        .watch(growthSeriesProvider(person.id))
        .when(
          loading: () => const Text('Loading recorded measurements…'),
          error: (_, _) => CompanionLoadError(
            onRetry: () => ref.invalidate(growthSeriesProvider(person.id)),
          ),
          data: (rows) {
            final series = rows.toList()
              ..sort((a, b) => b.takenAt.compareTo(a.takenAt));
            if (series.isEmpty) {
              return const Text(
                "No clinic growth measurements saved on this phone. Ask your health worker to measure and explain the child's growth. No trend was estimated.",
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  "Recorded measurements, not growth predictions. Ask a health worker to interpret them with the child's health and feeding history.",
                ),
                if (series.where((m) => m.weightKg != null).length >= 2) ...[
                  const SizedBox(height: 8),
                  _WeightSparkline(
                    points: series
                        .where((m) => m.weightKg != null)
                        .toList()
                        .reversed
                        .toList(),
                  ),
                ],
                for (final m in series)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(caregiverWhen(m.takenAt)),
                    children: [
                      Text(
                        "Weight: ${m.weightKg == null ? 'Not recorded' : '${m.weightKg} kg'}",
                      ),
                      Text(
                        "Length / height: ${m.heightCm == null ? 'Not recorded' : '${m.heightCm} cm'}",
                      ),
                      Text(
                        'Arm circumference: ${m.muacMm != null
                            ? '${m.muacMm} mm'
                            : m.muacCm != null
                            ? '${m.muacCm} cm'
                            : 'Not recorded'}',
                      ),
                      if (m.hasBilateralOedema)
                        const Text(
                          'Swelling of both feet was recorded at this visit. Refer to the saved clinic advice.',
                        ),
                      Text(
                        m.recordedBy == null
                            ? 'Recorder not available in this saved record.'
                            : 'Source: recorded clinic measurement',
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
  );
}

class _MaternalPreparation extends ConsumerWidget {
  const _MaternalPreparation({required this.person, required this.now});
  final Person person;
  final DateTime now;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pregnant = person.clientType == ClientType.pregnantWoman;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CompanionCard(
          title: pregnant ? 'Pregnancy preparation' : 'Postnatal preparation',
          eyebrow: '${person.fullName} • ${caregiverAge(person)}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Discuss your next clinic date, a support person, and travel arrangements. This app cannot confirm bookings or transport.',
              ),
              ref
                  .watch(maternalRecordProvider(person.id))
                  .when(
                    loading: () => const Text('Loading recorded dates…'),
                    error: (_, _) => CompanionLoadError(
                      onRetry: () =>
                          ref.invalidate(maternalRecordProvider(person.id)),
                    ),
                    data: (record) {
                      final date = pregnant
                          ? record?.lastMenstrualPeriod
                          : record?.deliveryDate;
                      final days = date == null
                          ? null
                          : now.difference(date).inDays;
                      if (days == null ||
                          date!.isAfter(now) ||
                          days < 0 ||
                          (pregnant ? days > 308 : days > 365)) {
                        return const Text(
                          'A current, valid pregnancy or delivery date is not available. Ask the clinic to confirm it; no week/day estimate was made.',
                        );
                      }
                      return Text(
                        pregnant
                            ? 'About ${days ~/ 7} weeks from the recorded last menstrual period (${caregiverWhen(date)}). Ask the clinic to confirm pregnancy dating.'
                            : '$days days since the recorded delivery (${caregiverWhen(date)}).',
                      );
                    },
                  ),
            ],
          ),
        ),
        CaregiverPreparation(person: person),
      ],
    );
  }
}

class _WeightSparkline extends StatelessWidget {
  const _WeightSparkline({required this.points});
  final List<GrowthMeasurement> points;

  @override
  Widget build(BuildContext context) {
    final weights = points.map((p) => p.weightKg!).toList();
    if (weights.length < 2) return const SizedBox.shrink();
    final minW = weights.reduce((a, b) => a < b ? a : b);
    final maxW = weights.reduce((a, b) => a > b ? a : b);
    final range = maxW - minW;
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.checkBlue.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: CustomPaint(
        size: Size.infinite,
        painter: _SparklinePainter(
          weights: weights,
          min: range > 0 ? minW : minW - 0.5,
          max: range > 0 ? maxW : maxW + 0.5,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.weights,
    required this.min,
    required this.max,
  });
  final List<double> weights;
  final double min;
  final double max;

  @override
  void paint(Canvas canvas, Size size) {
    final range = max - min;
    if (range <= 0 || weights.length < 2) return;
    final step = size.width / (weights.length - 1);
    final path = Path();
    for (var i = 0; i < weights.length; i++) {
      final x = i * step;
      final y = size.height - ((weights[i] - min) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.checkBlue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final dotPaint = Paint()
      ..color = AppColors.checkBlue
      ..style = PaintingStyle.fill;
    for (var i = 0; i < weights.length; i++) {
      final x = i * step;
      final y = size.height - ((weights[i] - min) / range) * size.height;
      canvas.drawCircle(Offset(x, y), 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.weights != weights || old.min != min || old.max != max;
}
