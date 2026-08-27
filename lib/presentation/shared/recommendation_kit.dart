/// The shared recommendation system: one implementation, two audiences.
///
/// Everything the engines synthesize into a [CarePlan] is rendered through
/// this kit — by the FHW result screen at the point of care, and by the
/// caregiver's care-plan tab from the saved record. Same engine, same
/// wording, same worklist; only the framing adapts:
///
///   * [RecAudience.healthWorker] keeps the audit anchors — guideline
///     citations on every action, dose-bearing pre-referral protocols.
///   * [RecAudience.caregiver] strips the clinical citations so the family
///     sees plain, doable language — and gains an audio voice for the plan.
///
/// The contract both audiences share: a plan you can check off is a
/// worklist, not a memo.
library;

import 'package:flutter/material.dart';

import '../../core/i18n/dagbani_speech.dart';
import '../../core/theme/app_theme.dart';
import '../../data/reference/local_foods.dart';
import '../../domain/engines/immunisation_engine.dart';
import '../../domain/engines/nurturing_care_engine.dart';
import '../../domain/engines/nutrition_engine.dart';
import '../../domain/engines/nutrition/therapeutic_supplements.dart';
import '../../domain/engines/protocols/stabilization_protocols.dart';
import '../../domain/engines/recommendation_engine.dart';
import '../../domain/entities/core.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../assessment/form_kit.dart';
import 'app_image.dart';
import 'audio_button.dart';
import 'ui.dart';

/// Who is reading the recommendation. Governs what the kit shows and what
/// it keeps quiet — see the library doc.
enum RecAudience { healthWorker, caregiver }

// ---------------------------------------------------------------- Scaffolding

/// A quiet section header: uppercase eyebrow title, optional icon, subtitle
/// and a trailing slot (typically an [AudioButton]).
class RecSection extends StatelessWidget {
  const RecSection({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.subtitle,
    this.trailing,
    this.accent,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;
  final Color? accent;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: accent ?? AppColors.inkFaint),
            const SizedBox(width: Gap.sm),
          ],
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: AppColors.inkMuted,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
      if (subtitle != null) ...[
        const SizedBox(height: Gap.xs),
        Text(
          subtitle!,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.inkMuted,
            height: 1.4,
          ),
        ),
      ],
      const SizedBox(height: Gap.md),
      child,
    ],
  );
}

/// A premium collapsible version of RecSection for secondary care plan info.
class CollapsibleRecSection extends StatefulWidget {
  const CollapsibleRecSection({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.subtitle,
    this.trailing,
    this.accent,
    this.initiallyExpanded = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;
  final Color? accent;
  final bool initiallyExpanded;

  @override
  State<CollapsibleRecSection> createState() => _CollapsibleRecSectionState();
}

class _CollapsibleRecSectionState extends State<CollapsibleRecSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _heightFactor;
  late final Animation<double> _rotation;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _heightFactor = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuart,
    );
    _rotation = Tween<double>(
      begin: 0.0,
      end: 0.5,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    if (_isExpanded) {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent ?? AppColors.primary;
    final isHoveredOrActive = _isExpanded;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: isHoveredOrActive
            ? AppColors.surfaceTint.withValues(alpha: 0.3)
            : Colors.white,
        borderRadius: BorderRadius.circular(Gap.radius),
        border: Border.all(
          color: isHoveredOrActive
              ? accent.withValues(alpha: 0.3)
              : AppColors.line,
          width: isHoveredOrActive ? 1.5 : Gap.hairline,
        ),
        boxShadow: isHoveredOrActive
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : const [AppShadows.card],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Gap.radius),
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _handleTap,
                highlightColor: accent.withValues(alpha: 0.05),
                splashColor: accent.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(Gap.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (widget.icon != null) ...[
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(
                                  Gap.radiusXs,
                                ),
                              ),
                              child: Icon(widget.icon, size: 16, color: accent),
                            ),
                            const SizedBox(width: Gap.sm),
                          ],
                          Expanded(
                            child: Text(
                              widget.title.toUpperCase(),
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                                color: isHoveredOrActive
                                    ? accent
                                    : AppColors.inkMuted,
                              ),
                            ),
                          ),
                          if (widget.trailing != null) ...[
                            widget.trailing!,
                            const SizedBox(width: Gap.sm),
                          ],
                          RotationTransition(
                            turns: _rotation,
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: isHoveredOrActive
                                  ? accent
                                  : AppColors.inkFaint,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: Gap.xs),
                        Padding(
                          padding: EdgeInsets.only(
                            left: widget.icon != null
                                ? (16.0 + 12.0 + Gap.sm)
                                : 0,
                          ),
                          child: Text(
                            widget.subtitle!,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.inkMuted,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            SizeTransition(
              sizeFactor: _heightFactor,
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppColors.line, width: Gap.hairline),
                  ),
                ),
                padding: const EdgeInsets.all(Gap.md),
                child: widget.child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The breathing room between sections: a single hairline with generous
/// vertical margins.
class RecHairline extends StatelessWidget {
  const RecHairline({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: Gap.lg),
    child: Divider(height: 1, thickness: 1, color: AppColors.line),
  );
}

/// The premium finish every kit card shares: a white surface that reads
/// off the canvas, one hairline border, the blue-tinted [AppShadows.card]
/// lift and a generous radius — with an optional accent bar running down
/// the left edge for urgency coding. Drop content in; the card makes it
/// look deliberate.
class KitCard extends StatelessWidget {
  const KitCard({
    super.key,
    required this.child,
    this.accent,
    this.padding = const EdgeInsets.all(Gap.md),
    this.margin = const EdgeInsets.only(bottom: Gap.sm),
  });

  final Widget child;

  /// The urgency/brand colour painted as a 4px bar on the left edge.
  /// Null for a quiet, undifferentiated card.
  final Color? accent;
  final EdgeInsets padding;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Gap.radiusSm);
    return Container(
      width: double.infinity,
      margin: margin,
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: radius,
        border: Border.all(color: AppColors.line, width: Gap.hairline),
        boxShadow: const [AppShadows.card],
      ),
      child: accent == null
          ? Padding(padding: padding, child: child)
          : AccentEdge(
              accent: accent!,
              borderRadius: radius,
              child: Padding(padding: padding, child: child),
            ),
    );
  }
}

/// A small amber callout shown when one of the synthesizer's safety nets —
/// the never-miss escalation or the referral guarantee — has fired. These are
/// deliberately conspicuous: a guard-rail that fires is exactly the kind of
/// thing a supervisor wants to see, not something to bury.
class SafetyNetNote extends StatelessWidget {
  const SafetyNetNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.triageAmberBg,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
      ),
      child: AccentEdge(
        accent: AppColors.triageAmber,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.shield_outlined,
                size: 16,
                color: AppColors.triageAmber,
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.triageAmber,
                    height: 1.4,
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

/// Which patient this plan was tuned for. The synthesizer names the
/// cohort and writes its tailored note; this card makes that visible at
/// the top of the care plan, so a CHO skimming the screen reads *who
/// this is for* before *what to do* — a 3-day-old and a pregnant
/// mother with identical-looking findings are not managed alike.
class CohortCallout extends StatelessWidget {
  const CohortCallout({super.key, required this.cohort, required this.note});

  final ClientType cohort;
  final String note;

  IconData get _icon => switch (cohort) {
    ClientType.newborn => Icons.child_care_outlined,
    ClientType.childUnderFive => Icons.emoji_people_outlined,
    ClientType.pregnantWoman ||
    ClientType.postpartumWoman ||
    ClientType.womanOfReproductiveAge => Icons.pregnant_woman_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(Gap.radiusSm),
      ),
      child: AccentEdge(
        accent: AppColors.primary,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_icon, size: 16, color: AppColors.primaryDeep),
                  const SizedBox(width: Gap.xs),
                  const Expanded(
                    child: Text(
                      'TAILORED PLAN',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                        color: AppColors.primaryDeep,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.sm,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      cohort.protocolLabel,
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.xs),
              Text(
                cohort.label,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                note,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.inkMuted,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- Worklist

/// The "do this now" heart of the recommendation system: numbered-free,
/// tickable, urgency-tagged actions with a live progress bar. Owns its own
/// tick state, so it can be dropped into the FHW result screen and the
/// caregiver's care plan alike — a family completing steps at home is the
/// same loop as a CHO completing them at the compound.
class ActionWorklist extends StatefulWidget {
  const ActionWorklist({
    super.key,
    required this.actions,
    this.audience = RecAudience.healthWorker,
  });

  final List<RecommendedAction> actions;
  final RecAudience audience;

  @override
  State<ActionWorklist> createState() => _ActionWorklistState();
}

/// One urgency band the worklist sorts the model's actions into.
class _Band {
  const _Band({
    required this.title,
    required this.note,
    required this.colour,
    required this.bg,
    required this.matches,
  });

  final String title;
  final String note;
  final Color colour;
  final Color bg;
  final bool Function(RecommendedAction) matches;
}

class _ActionWorklistState extends State<ActionWorklist> {
  /// Indices of plan actions ticked off. A plan you can check off is a
  /// worklist, not a memo. Keyed by the action's position in the plan, so
  /// the ticks survive the band regrouping below.
  final Set<int> _done = {};

  /// The three urgency bands, in the order a CHO must work them. Band
  /// membership is structural: a referral or a pre-referral treatment can
  /// never sort below "before you leave", however its urgency field reads.
  static final List<_Band> _bands = [
    _Band(
      title: 'Before you leave',
      note: 'Do these first — they cannot wait for transport or tomorrow.',
      colour: AppColors.triageRed,
      bg: AppColors.triageRedBg,
      matches: (a) =>
          a.isReferral ||
          a.isPrereferralTreatment ||
          a.urgency == ReferralUrgency.immediate,
    ),
    _Band(
      title: 'Today & within 2 days',
      note: 'Set these in motion while the visit is still fresh.',
      colour: AppColors.triageAmber,
      bg: AppColors.triageAmberBg,
      matches: (a) =>
          a.urgency == ReferralUrgency.sameDay ||
          a.urgency == ReferralUrgency.withinTwoDays,
    ),
    _Band(
      title: 'This week & ongoing care',
      note: 'The routine steps that keep this plan working.',
      colour: AppColors.triageGreen,
      bg: AppColors.triageGreenBg,
      matches: (_) => true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // Every action paired with its plan index, then dealt into bands —
    // each action lands in the first band that claims it.
    final indexed = [
      for (var i = 0; i < widget.actions.length; i++) (i, widget.actions[i]),
    ];
    final claimed = <int>{};
    final dealt = <(List<(int, RecommendedAction)>, _Band)>[];
    for (final band in _bands) {
      final members = indexed
          .where((p) => !claimed.contains(p.$1) && band.matches(p.$2))
          .toList(growable: false);
      claimed.addAll(members.map((p) => p.$1));
      if (members.isNotEmpty) dealt.add((members, band));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: widget.actions.isEmpty
                ? 0
                : _done.length / widget.actions.length,
            minHeight: 6,
            backgroundColor: AppColors.inkFaint.withValues(alpha: 0.2),
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
          ),
        ),
        const SizedBox(height: Gap.xs),
        Text(
          '${_done.length} of ${widget.actions.length} done',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.inkFaint,
          ),
        ),
        const SizedBox(height: Gap.md),
        for (final (members, band) in dealt) ...[
          _BandHeader(
            band: band,
            doneCount: members.where((p) => _done.contains(p.$1)).length,
            totalCount: members.length,
          ),
          for (final (i, action) in members)
            _WorklistTile(
              action,
              audience: widget.audience,
              accent: band.colour,
              done: _done.contains(i),
              onToggle: () => setState(() {
                if (_done.contains(i)) {
                  _done.remove(i);
                } else {
                  _done.add(i);
                }
              }),
            ),
          const SizedBox(height: Gap.sm),
        ],
      ],
    );
  }
}

/// A band's header: its colour, its name, and how far through it the
/// worker is.
class _BandHeader extends StatelessWidget {
  const _BandHeader({
    required this.band,
    required this.doneCount,
    required this.totalCount,
  });

  final _Band band;
  final int doneCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.sm),
    child: Row(
      children: [
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(right: Gap.sm),
          decoration: BoxDecoration(color: band.colour, shape: BoxShape.circle),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                band.title.toUpperCase(),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.9,
                  color: band.colour,
                ),
              ),
              Text(
                band.note,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.inkFaint,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 3),
          decoration: BoxDecoration(
            color: band.bg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$doneCount/$totalCount',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              color: band.colour,
            ),
          ),
        ),
      ],
    ),
  );
}

class _WorklistTile extends StatelessWidget {
  const _WorklistTile(
    this.action, {
    required this.audience,
    required this.accent,
    this.done = false,
    this.onToggle,
  });

  final RecommendedAction action;
  final RecAudience audience;

  /// The band colour — painted as the card's left accent bar and on the
  /// status chip, so the eye sorts the list before reading a word.
  final Color accent;
  final bool done;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final (icon, colour) = action.isReferral
        ? (Icons.local_hospital_outlined, AppColors.triageRed)
        : action.isTreatment
        ? (Icons.medication_outlined, AppColors.triageAmber)
        : (Icons.chat_bubble_outline_rounded, AppColors.accent);

    return KitCard(
      accent: done ? AppColors.lineStrong : accent,
      padding: const EdgeInsets.all(Gap.md),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(Gap.radiusXs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tick circle — the satisfying "done" micro-interaction.
            Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(right: Gap.md),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? AppColors.triageGreen : Colors.transparent,
                border: Border.all(
                  color: done ? AppColors.triageGreen : AppColors.inkFaint,
                  width: 1.5,
                ),
              ),
              child: done
                  ? const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: Colors.white,
                    )
                  : null,
            ),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: colour.withValues(alpha: done ? 0.08 : 0.12),
                borderRadius: BorderRadius.circular(Gap.radiusXs),
              ),
              child: Icon(
                icon,
                size: 16,
                color: done ? AppColors.inkFaint : colour,
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action.instruction,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                      color: done ? AppColors.inkFaint : AppColors.ink,
                      decoration: done
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),
                  if (action.rationale != null) ...[
                    const SizedBox(height: Gap.xs),
                    Text(
                      action.rationale!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.inkMuted,
                        height: 1.4,
                      ),
                    ),
                  ],
                  // The guideline citation is the health worker's audit
                  // anchor; the family only needs the instruction.
                  if (action.protocolSource != null &&
                      audience == RecAudience.healthWorker) ...[
                    const SizedBox(height: Gap.xs),
                    Text(
                      action.protocolSource!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ],
                  const SizedBox(height: Gap.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      action.urgency.label,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                        color: done ? AppColors.inkFaint : accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- Nutrition

class NutritionRecSection extends StatelessWidget {
  const NutritionRecSection({
    super.key,
    required this.plan,
    required this.cost,
    required this.onCost,
    this.collapsible = false,
  });

  final NutritionPlan plan;
  final CostTier cost;
  final ValueChanged<CostTier> onCost;
  final bool collapsible;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(Gap.md),
          decoration: BoxDecoration(
            color: plan.therapeuticFoodRequired
                ? AppColors.triageRedBg
                : AppColors.triageGreenBg,
            borderRadius: BorderRadius.circular(Gap.radiusSm),
          ),
          child: Text(
            plan.headline,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              height: 1.4,
              color: plan.therapeuticFoodRequired
                  ? AppColors.triageRed
                  : AppColors.triageGreen,
            ),
          ),
        ),
        if (plan.cohortLine != null) ...[
          const SizedBox(height: Gap.sm),
          // The cohort line names *who* this basket was chosen for — the
          // engine's own words for the pregnancy, the weaning window, the
          // breastfeeding mother.
          KitCard(
            accent: AppColors.primary,
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.md,
              vertical: Gap.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.person_outline_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    plan.cohortLine!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryDeep,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),
        ],
        Text(
          plan.seasonNote,
          style: const TextStyle(
            fontSize: 12.5,
            color: AppColors.inkMuted,
            height: 1.4,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: Gap.md),
        // The therapeutic prescription — MMS, IFA, RUTF, KMC — is the
        // clinical heart of the plan: named dose, schedule and duration,
        // each anchored to its WHO/GHS citation.
        if (plan.therapeuticPlan != null &&
            plan.therapeuticPlan!.supplements.isNotEmpty) ...[
          const FieldLabel('Therapeutic prescription'),
          if (plan.therapeuticPlan!.counsellingHeadline.isNotEmpty) ...[
            const SizedBox(height: Gap.xs),
            Text(
              plan.therapeuticPlan!.counsellingHeadline,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.inkMuted,
                height: 1.4,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: Gap.sm),
          for (final s in plan.therapeuticPlan!.supplements)
            _PrescriptionCard(s),
        ],
        // Diarrhoea turns fluids into the treatment: the WHO Plan-A
        // prescription stands before any food advice.
        if (plan.hydrationPlan != null) ...[
          const FieldLabel('Fluids for the diarrhoea — WHO Plan A'),
          const SizedBox(height: Gap.sm),
          _HydrationCard(lines: plan.hydrationPlan!),
          const SizedBox(height: Gap.sm),
        ],
        ChoiceChipsField<CostTier>(
          label: 'What can this household afford this month?',
          why:
              'A recommendation the family cannot buy is not a recommendation.',
          options: const [
            CostTier.freeOrGathered,
            CostTier.veryLow,
            CostTier.low,
            CostTier.moderate,
          ],
          labelOf: (t) => t.label,
          value: cost,
          onChanged: (t) => onCost(t ?? CostTier.low),
        ),
        if (plan.mealsPerDayTarget != null) ...[
          const SizedBox(height: Gap.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.md,
              vertical: Gap.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(Gap.radiusSm),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.restaurant_outlined,
                  size: 16,
                  color: AppColors.primaryDeep,
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    'Feeding target: at least ${plan.mealsPerDayTarget} '
                    'times a day, plus snacks.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDeep,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (plan.dayPlan.isNotEmpty) ...[
          const SizedBox(height: Gap.md),
          const FieldLabel("Today's plate"),
          if (plan.dayPlanNote != null) ...[
            Text(
              plan.dayPlanNote!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.inkMuted,
                height: 1.4,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: Gap.sm),
          ],
          _DayPlanCard(slots: plan.dayPlan),
        ],
        if (plan.nutrientCoverage.isNotEmpty) ...[
          const SizedBox(height: Gap.md),
          const FieldLabel('What this basket covers'),
          const SizedBox(height: Gap.xs),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.xs,
            children: [
              for (final entry in plan.nutrientCoverage.entries)
                _CoverageChip(
                  nutrient: entry.key,
                  foods: entry.value.take(3).toList(growable: false),
                ),
            ],
          ),
        ],
        if (plan.diversityGapsFilled.isNotEmpty) ...[
          const SizedBox(height: Gap.md),
          const FieldLabel('Diversity gaps from yesterday'),
          const SizedBox(height: Gap.xs),
          for (final gap in plan.diversityGapsFilled.entries)
            _GapLine(group: gap.key, fillers: gap.value),
        ],
        if (plan.suggestions.isNotEmpty) ...[
          const SizedBox(height: Gap.sm),
          const FieldLabel('Start with these local foods'),
          for (final s in plan.suggestions) _FoodTile(s),
        ],
        if (plan.feedingRules.isNotEmpty) ...[
          const SizedBox(height: Gap.sm),
          const FieldLabel('Feeding rules'),
          for (final rule in plan.feedingRules)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 16,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(
                      rule,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (plan.upcomingFoods.isNotEmpty) ...[
          const SizedBox(height: Gap.md),
          const FieldLabel('Getting ready — first foods at 6 months'),
          for (final s in plan.upcomingFoods) _FoodTile(s),
        ],
        // The safety net, stated out loud: the deterioration signs the
        // family can recognise at home, and the instruction to return.
        if (plan.escalationSigns.isNotEmpty) ...[
          const SizedBox(height: Gap.md),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.triageRedBg,
              borderRadius: BorderRadius.circular(Gap.radiusSm),
            ),
            child: AccentEdge(
              accent: AppColors.triageRed,
              borderRadius: BorderRadius.circular(Gap.radiusSm),
              child: Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'BRING BACK IMMEDIATELY IF:',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: AppColors.triageRed,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final sign in plan.escalationSigns)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Text(
                          '\u2022 $sign',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                            height: 1.4,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
        if (plan.reviewInDays != null) ...[
          const SizedBox(height: Gap.sm),
          Text(
            'Nutrition review in ${plan.reviewInDays} '
            'day${plan.reviewInDays == 1 ? '' : 's'}.',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ],
      ],
    );

    if (collapsible) {
      return CollapsibleRecSection(
        title: 'Nutrition',
        subtitle: plan.pathway.label,
        icon: Icons.restaurant_outlined,
        accent: plan.therapeuticFoodRequired
            ? AppColors.triageRed
            : AppColors.primary,
        child: content,
      );
    }
    return RecSection(
      title: 'Nutrition',
      subtitle: plan.pathway.label,
      icon: Icons.restaurant_outlined,
      accent: plan.therapeuticFoodRequired
          ? AppColors.triageRed
          : AppColors.primary,
      child: content,
    );
  }
}

/// The basket composed into a day — one card, one row per meal. The
/// moment of day leads, the foods follow, and the age-band note (when a
/// slot carries one) sits underneath in quiet italics. A nurse reads it
/// as a menu, not a spreadsheet.
class _DayPlanCard extends StatelessWidget {
  const _DayPlanCard({required this.slots});

  final List<MealSlot> slots;

  IconData get _clockIcon => Icons.restaurant_outlined;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        border: Border.all(color: AppColors.line, width: Gap.hairline),
        boxShadow: const [AppShadows.card],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < slots.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: Gap.xs),
                child: Divider(height: 1, thickness: 1, color: AppColors.line),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(_clockIcon, size: 14, color: AppColors.accent),
                      const SizedBox(width: Gap.xs),
                      SizedBox(
                        width: 64,
                        child: Text(
                          slots[i].moment.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          slots[i].foods.join(' + '),
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (slots[i].note != null) ...[
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.only(left: 22),
                      child: Text(
                        slots[i].note!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.inkFaint,
                          height: 1.4,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One line of the coverage audit: a raised need and the basket foods
/// that answer it. This is the recommender showing its working.
class _CoverageChip extends StatelessWidget {
  const _CoverageChip({required this.nutrient, required this.foods});

  final String nutrient;
  final List<String> foods;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.triageGreenBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$nutrient ✓ ',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                color: AppColors.triageGreen,
              ),
            ),
            TextSpan(
              text: foods.join(', '),
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FoodTile extends StatelessWidget {
  const _FoodTile(this.food);

  final FoodSuggestion food;

  /// Pick the bundled illustration that best matches this food. Real Northern
  /// Ghana foods, per master flow [48] — illustrated cards, not paragraphs.
  String get _image {
    final f = food.food.toLowerCase();
    if (f.contains('egg') && !f.contains('garden')) {
      return AppImages.foodBoiledEgg;
    }
    if (f.contains('fish')) {
      return AppImages.foodDriedFish;
    }
    if (f.contains('groundnut') || f.contains('peanut')) {
      return AppImages.foodGroundnutPaste;
    }
    if (f.contains('sweet potato')) {
      return AppImages.foodSweetPotato;
    }
    if (f.contains('pawpaw') || f.contains('papaya')) {
      return AppImages.foodPawpaw;
    }
    if (f.contains('dawadawa') || f.contains('locust')) {
      return AppImages.foodDawadawa;
    }
    if (f.contains('millet') ||
        f.contains('sorghum') ||
        f.contains('porridge') ||
        f.contains('rice') ||
        f.contains('maize') ||
        f.contains('yam') ||
        f.contains('cassava')) {
      return AppImages.foodMilletPorridge;
    }
    if (f.contains('moringa') ||
        f.contains('baobab') ||
        f.contains('kuka') ||
        f.contains('zogale') ||
        f.contains('leaf') ||
        f.contains('leaves') ||
        f.contains('vegetable') ||
        f.contains('fruit') ||
        f.contains('mango') ||
        f.contains('pumpkin')) {
      return AppImages.foodMoringaBaobab;
    }
    return AppImages.foodCowpeaStew;
  }

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: Gap.sm),
    padding: const EdgeInsets.all(Gap.md),
    decoration: BoxDecoration(
      color: AppColors.canvas,
      borderRadius: BorderRadius.circular(Gap.radiusSm),
      border: Border.all(color: AppColors.line),
      boxShadow: const [AppShadows.card],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(Gap.radiusXs),
              child: SizedBox(
                width: 52,
                height: 52,
                child: AppImage(src: _image),
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    food.localName != null
                        ? '${food.food} (${food.localName})'
                        : food.food,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: Gap.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.sm,
                      vertical: Gap.xs,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      food.householdMeasure,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.xs),
        Text(
          food.reason,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.inkMuted,
            height: 1.4,
          ),
        ),
        if (food.preparation != null) ...[
          const SizedBox(height: Gap.xs),
          Text(
            'How: ${food.preparation}',
            style: const TextStyle(fontSize: 12, height: 1.4),
          ),
        ],
        if (food.caution != null) ...[
          const SizedBox(height: Gap.xs),
          Text(
            'Caution: ${food.caution}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.triageAmber,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ],
      ],
    ),
  );
}

/// One therapeutic prescription — MMS, IFA, RUTF or KMC — rendered the
/// way a nurse reads an order: substance, dose, schedule, duration, then
/// the counselling sentence to say out loud and the citation that backs
/// it. Immediate-urgency prescriptions (RUTF, KMC) carry the red edge.
class _PrescriptionCard extends StatelessWidget {
  const _PrescriptionCard(this.supplement);

  final TherapeuticSupplement supplement;

  bool get _immediate =>
      supplement.id.startsWith('sam_rutf') ||
      supplement.id.startsWith('kmc_lbw');

  Widget _kv(String key, String value) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(
            key,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
              color: AppColors.inkFaint,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final accent = _immediate ? AppColors.triageRed : AppColors.primary;
    return KitCard(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.medication_outlined, size: 15, color: accent),
              const SizedBox(width: Gap.xs),
              const Expanded(
                child: Text(
                  'THERAPEUTIC PRESCRIPTION',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                    color: AppColors.inkMuted,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  supplement.citation.shortName,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          Text(
            supplement.label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              height: 1.3,
            ),
          ),
          const SizedBox(height: Gap.xs),
          _kv('DOSE', supplement.dose),
          _kv('SCHEDULE', supplement.schedule),
          _kv('DURATION', supplement.duration),
          const SizedBox(height: Gap.sm),
          Text(
            supplement.counsellingNote,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.inkMuted,
              height: 1.45,
              fontStyle: FontStyle.italic,
            ),
          ),
          if (supplement.contraindications.isNotEmpty) ...[
            const SizedBox(height: Gap.xs),
            Text(
              'Not if: ${supplement.contraindications.join('; ')}.',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.triageAmber,
                height: 1.4,
              ),
            ),
          ],
          if (supplement.localSources.isNotEmpty) ...[
            const SizedBox(height: Gap.xs),
            Text(
              'Also available from: ${supplement.localSources.join(', ')}.',
              style: const TextStyle(
                fontSize: 11.5,
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

/// The WHO Plan-A fluid prescription as a card: fluids are the
/// treatment in diarrhoea, so this reads like a dose chart, not a tip.
class _HydrationCard extends StatelessWidget {
  const _HydrationCard({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) => KitCard(
    accent: AppColors.primary,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(
              Icons.local_drink_outlined,
              size: 15,
              color: AppColors.primary,
            ),
            SizedBox(width: Gap.xs),
            Expanded(
              child: Text(
                'FLUIDS ARE THE TREATMENT',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.xs),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.check_circle_outline_rounded,
                  size: 14,
                  color: AppColors.primary,
                ),
                const SizedBox(width: Gap.xs),
                Expanded(
                  child: Text(
                    line,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// One diversity gap: the food group missing from yesterday's plate and
/// the affordable local food that fills it. Minimum dietary diversity
/// for a child in the complementary window is 5 of the 8 WHO groups.
class _GapLine extends StatelessWidget {
  const _GapLine({required this.group, required this.fillers});

  final String group;
  final List<String> fillers;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.add_circle_outline_rounded,
          size: 15,
          color: AppColors.triageAmber,
        ),
        const SizedBox(width: Gap.xs),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'No $group yesterday',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.triageAmber,
                  ),
                ),
                TextSpan(
                  text: ' — add ${fillers.take(2).join(' or ')}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.ink,
                    height: 1.4,
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

// ----------------------------------------------------- Early learning [49]

/// Early Learning & Responsive Care tips — master flow [49], a required NEW
/// screen that closes Nurturing Care domains 3 (responsive caregiving) and 5
/// (early learning). Two to three simple, age-appropriate things a caregiver
/// can do today, with no toys and no money — talking, playing, responding.
class EarlyLearningRecSection extends StatelessWidget {
  const EarlyLearningRecSection({
    super.key,
    required this.person,
    this.collapsible = false,
  });

  final Person person;
  final bool collapsible;

  List<String> get _tips {
    final months = person.ageInMonths;
    if (person.effectiveClientType == ClientType.newborn ||
        (months != null && months < 3)) {
      return const [
        'Talk and sing to your baby while feeding and bathing. Your voice is '
            'their first lesson.',
        'Hold your baby close and look into their eyes. They learn safety '
            'from your face.',
        'When your baby cries, answer quickly. A baby who is answered learns '
            'to trust the world.',
      ];
    }
    if (months != null && months < 6) {
      return const [
        'Smile back when your baby smiles. This back-and-forth builds their '
            'brain.',
        'Let them reach for a clean spoon or cup. Grasping is their first '
            'game.',
        'Name things as you touch them: "nose", "hand", "water".',
      ];
    }
    if (months != null && months < 12) {
      return const [
        'Play peek-a-boo. It teaches that things still exist when they are '
            'hidden.',
        'Give safe household objects to explore — a cup, a spoon, a cloth.',
        'Answer their sounds and babbling as if you are having a real '
            'conversation.',
      ];
    }
    if (months != null && months < 24) {
      return const [
        'Name body parts while bathing: "This is your hand, this is your '
            'foot".',
        'Let them try feeding themselves, even if it is messy. Practice '
            'builds skill.',
        'Count out loud together as you walk: one, two, three.',
      ];
    }
    return const [
      'Tell stories and ask "What happens next?" Imagination is learning.',
      'Let them draw with a stick in the sand, or with chalk on a wall.',
      'Give small jobs — fetching a spoon, carrying a small bowl. '
          'Responsibility is learning too.',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final tip in _tips)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.tips_and_updates_outlined,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    tip,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    if (collapsible) {
      return CollapsibleRecSection(
        title: 'Play, talk, respond',
        subtitle:
            'A child’s brain grows fastest in the first five years. These '
            'cost nothing and need no toys — just you.',
        icon: Icons.toys_outlined,
        accent: AppColors.primary,
        child: content,
      );
    }
    return RecSection(
      title: 'Play, talk, respond',
      subtitle:
          'A child’s brain grows fastest in the first five years. These '
          'cost nothing and need no toys — just you.',
      icon: Icons.toys_outlined,
      accent: AppColors.primary,
      child: content,
    );
  }
}

// --------------------------------------------------------------- Immunisation

/// Immunisation at this visit: a live reading of the child's Ghana EPI
/// card — what is protected, what is due, what has been missed, and what
/// each dose is defending against. The section exists because a missed
/// opportunity at the contact is the commonest reason a child ends up
/// under-immunised, so every dose carries its disease and every gap its
/// age limit.
class ImmunisationRecSection extends StatelessWidget {
  const ImmunisationRecSection({
    super.key,
    required this.plan,
    this.collapsible = false,
  });

  final ImmunisationPlan plan;
  final bool collapsible;

  /// Action-first ordering: overdue leads, then due, then upcoming, then
  /// already given; age-barred doses sit last as a do-not-give record.
  static const _order = {
    ImmunisationStatus.overdue: 0,
    ImmunisationStatus.dueToday: 1,
    ImmunisationStatus.notYetDue: 2,
    ImmunisationStatus.given: 3,
    ImmunisationStatus.ageBarred: 4,
  };

  @override
  Widget build(BuildContext context) {
    final items = plan.items.toList(growable: false)
      ..sort((a, b) => _order[a.status]!.compareTo(_order[b.status]!));
    final waiting = items
        .where(
          (i) =>
              i.status == ImmunisationStatus.overdue ||
              i.status == ImmunisationStatus.dueToday,
        )
        .length;
    final upToDate = plan.isFullyUpToDate;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The hero: one glance says whether this child is protected.
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: upToDate ? AppColors.triageGreenBg : AppColors.triageAmberBg,
            borderRadius: BorderRadius.circular(Gap.radiusSm),
            boxShadow: const [AppShadows.card],
          ),
          child: AccentEdge(
            accent: upToDate ? AppColors.triageGreen : AppColors.triageAmber,
            borderRadius: BorderRadius.circular(Gap.radiusSm),
            child: Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    upToDate
                        ? Icons.verified_user_rounded
                        : Icons.warning_amber_rounded,
                    size: 28,
                    color: upToDate
                        ? AppColors.triageGreen
                        : AppColors.triageAmber,
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          upToDate
                              ? 'Fully protected'
                              : '$waiting dose${waiting == 1 ? '' : 's'} '
                                    'waiting for this child',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                            color: upToDate
                                ? AppColors.triageGreen
                                : AppColors.triageAmber,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          plan.summary,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.inkMuted,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: Gap.md),
        // What to draw up in this very session.
        if (plan.giveToday.isNotEmpty) ...[
          KitCard(
            accent: AppColors.primary,
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'GIVE TODAY — IN THIS SAME SESSION',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: Gap.xs),
                for (final d in plan.giveToday)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.vaccines_outlined,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: Gap.xs),
                        Expanded(
                          child: Text(
                            '${d.label} — guards against '
                            '${d.protectsAgainst}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),
        ],
        // The forward plan: what must wait, and how long. The session
        // list turns a wall of overdue doses into dates on the card.
        if (plan.catchUp.isNotEmpty) ...[
          KitCard(
            accent: AppColors.accent,
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'THEN — THE CATCH-UP SCHEDULE',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(height: Gap.xs),
                for (final s in plan.catchUp)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 84,
                          child: Text(
                            'IN ${s.weeksFromNow} WEEKS',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                              color: AppColors.inkMuted,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            s.labels.join(', '),
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: Gap.xs),
                const Text(
                  'Doses in the same series need at least 4 weeks between '
                  'them — write each date on the card.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.inkFaint,
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),
        ],
        for (final item in items) _ImmunisationTile(item: item),
        if (plan.nextDueLabel != null && plan.nextDueInDays != null) ...[
          const SizedBox(height: Gap.xs),
          Text(
            'Next due: ${plan.nextDueLabel} in about '
            '${plan.nextDueInDays} days — note it on the card before '
            'the family leaves.',
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.inkMuted,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
        ],
      ],
    );

    if (collapsible) {
      return CollapsibleRecSection(
        title: 'Immunisation',
        subtitle:
            'Vaccines teach this child\u2019s body to defeat disease before '
            'it strikes. Below is today\u2019s reading of the Ghana EPI '
            'schedule for this child.',
        icon: Icons.vaccines_outlined,
        accent: upToDate ? AppColors.triageGreen : AppColors.triageAmber,
        child: content,
      );
    }
    return RecSection(
      title: 'Immunisation',
      subtitle:
          'Vaccines teach this child\u2019s body to defeat disease before '
          'it strikes. Below is today\u2019s reading of the Ghana EPI '
          'schedule for this child.',
      icon: Icons.vaccines_outlined,
      accent: upToDate ? AppColors.triageGreen : AppColors.triageAmber,
      child: content,
    );
  }
}

/// One dose on the EPI card: its status pill, the engine's detail, and
/// the disease it exists to prevent — so "Penta 2" is never just a name.
class _ImmunisationTile extends StatelessWidget {
  const _ImmunisationTile({required this.item});

  final ImmunisationItem item;

  (Color, Color, String) get _pill => switch (item.status) {
    ImmunisationStatus.given => (
      AppColors.triageGreenBg,
      AppColors.triageGreen,
      'GIVEN',
    ),
    ImmunisationStatus.dueToday => (
      AppColors.primaryLight,
      AppColors.primary,
      'DUE TODAY',
    ),
    ImmunisationStatus.overdue => (
      AppColors.triageAmberBg,
      AppColors.triageAmber,
      item.weeksOverdue > 0 ? 'OVERDUE BY ${item.weeksOverdue} WK' : 'OVERDUE',
    ),
    ImmunisationStatus.notYetDue => (
      AppColors.surface,
      AppColors.inkMuted,
      'NOT YET DUE',
    ),
    ImmunisationStatus.ageBarred => (
      AppColors.surface,
      AppColors.inkFaint,
      'TOO OLD — DO NOT GIVE',
    ),
  };

  Color? get _accent => switch (item.status) {
    ImmunisationStatus.overdue => AppColors.triageAmber,
    ImmunisationStatus.dueToday => AppColors.primary,
    ImmunisationStatus.given => AppColors.triageGreen,
    ImmunisationStatus.ageBarred => AppColors.lineStrong,
    ImmunisationStatus.notYetDue => null,
  };

  @override
  Widget build(BuildContext context) {
    final (bg, fg, pill) = _pill;
    return KitCard(
      accent: _accent,
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.dose.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: item.status == ImmunisationStatus.given
                        ? AppColors.inkMuted
                        : AppColors.ink,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  pill,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            item.detail,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.inkMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 2),
          // Why this row exists at all — the disease, in plain words.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.health_and_safety_outlined,
                size: 12,
                color: AppColors.primaryDeep,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Why it matters: guards against '
                  '${item.dose.protectsAgainst}.',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryDeep,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------- Pre-referral

class PreReferralRecSection extends StatelessWidget {
  const PreReferralRecSection({super.key, required this.plan});

  final CarePlan plan;

  @override
  Widget build(BuildContext context) {
    // Red background with a "DO NOW" pill — the only section of the app
    // that overrides the theme to grab attention. A CHO skimming for what
    // to do first must see this before anything else.
    final protocols = plan.preReferralProtocols;
    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        color: AppColors.triageRed,
        borderRadius: BorderRadius.circular(Gap.radius),
        boxShadow: [
          BoxShadow(
            color: AppColors.triageRed.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(Gap.radiusSm),
                ),
                child: const Text(
                  'DO NOW — BEFORE TRANSPORT',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.triageRed,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.medical_services_outlined,
                color: Colors.white,
                size: 22,
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          const Text(
            'Pre-referral stabilisation',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              height: 1.2,
            ),
          ),
          const SizedBox(height: Gap.xs),
          Text(
            '${protocols.length} WHO / GHS protocol'
            '${protocols.length == 1 ? '' : 's'} activated. '
            'Initiate before transport is dispatched.',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Gap.md),
          for (final p in protocols) ...[
            _ProtocolCard(
              protocol: p,
              reason:
                  plan.preReferralActivationReasons[p.id] ?? 'See audit log.',
            ),
            const SizedBox(height: Gap.md),
          ],
          // Decision-support framing — required for clinical-decision
          // software and a deliberate trust signal: the app does not
          // pretend to be the clinician.
          Container(
            padding: const EdgeInsets.all(Gap.md),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Gap.radiusSm),
            ),
            child: const Text(
              'DECISION SUPPORT — You are the licensed clinician. Verify the '
              'dose, route and contraindications against the patient before '
              'administration. Each card below cites the published guideline.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One pre-referral protocol card, with the headline, citation badge,
/// urgency note, ordered steps (with dose / when / contraindication per
/// step), and the protocol-level contraindications.
class _ProtocolCard extends StatelessWidget {
  const _ProtocolCard({required this.protocol, required this.reason});

  final StabilizationProtocol protocol;
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Gap.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.local_hospital_rounded,
                color: AppColors.triageRed,
                size: 20,
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  protocol.headline,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          // Citation badge — the audit-defensible anchor.
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.sm,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: AppColors.triageRedBg,
              borderRadius: BorderRadius.circular(Gap.radiusSm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.menu_book_outlined,
                  size: 12,
                  color: AppColors.triageRed,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    protocol.citation.shortName,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.triageRed,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (protocol.urgencyNote != null) ...[
            const SizedBox(height: Gap.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.timer_outlined,
                  size: 14,
                  color: AppColors.triageAmber,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    protocol.urgencyNote!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (protocol.contraindications.isNotEmpty) ...[
            const SizedBox(height: Gap.sm),
            Container(
              padding: const EdgeInsets.all(Gap.sm),
              decoration: BoxDecoration(
                color: AppColors.triageAmberBg,
                borderRadius: BorderRadius.circular(Gap.radiusSm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CONTRAINDICATIONS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: AppColors.triageAmber,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final c in protocol.contraindications)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Text(
                        '• $c',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.ink,
                          height: 1.4,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Gap.md),
          const Text(
            'STEPS',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              color: AppColors.inkMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: Gap.xs),
          for (final s in protocol.steps) _ProtocolStepTile(step: s),
          const SizedBox(height: Gap.sm),
          // Why this protocol fired — the audit anchor every card must
          // carry: the selector's own reason string (AI rule-in candidate,
          // IMCI danger sign, …), in the clinician's line of sight.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Gap.sm),
            decoration: BoxDecoration(
              color: AppColors.triageRedBg,
              borderRadius: BorderRadius.circular(Gap.radiusSm),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.bolt_outlined,
                    size: 14,
                    color: AppColors.triageRed,
                  ),
                ),
                const SizedBox(width: Gap.xs),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'WHY ACTIVATED: ',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                            color: AppColors.triageRed,
                          ),
                        ),
                        TextSpan(
                          text: reason,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
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

/// One numbered step in a pre-referral protocol.
class _ProtocolStepTile extends StatelessWidget {
  const _ProtocolStepTile({required this.step});

  final ProtocolStep step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: AppColors.triageRed,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${step.order}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.action,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 2),
                // Dose, in a clinically-faithful format.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Gap.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    borderRadius: BorderRadius.circular(Gap.radiusSm),
                    border: Border.all(color: AppColors.line, width: 0.5),
                  ),
                  child: Text(
                    'DOSE: ${step.dose}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      height: 1.4,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'WHEN: ${step.whenToDo}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                    height: 1.4,
                  ),
                ),
                Text(
                  'WHY: ${step.rationale}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.inkMuted,
                    height: 1.4,
                  ),
                ),
                if (step.contraindication != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'CAUTION: ${step.contraindication!}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.triageAmber,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- Nurturing care

/// UNICEF Nurturing Care Framework section. The five canonical pillars —
/// Good Health, Adequate Nutrition, Responsive Caregiving, Opportunities
/// for Early Learning, Security and Safety — each rendered as its own
/// coloured card carrying the visit's actions, so the framework reads as
/// five small jobs to do, not a wall of text. Each action carries a
/// citation (health-worker audience only), and actions already delivered
/// at this visit are checked off.
class NurturingCareRecSection extends StatelessWidget {
  const NurturingCareRecSection({
    super.key,
    required this.assessment,
    this.audience = RecAudience.healthWorker,
    this.collapsible = false,
  });

  final NurturingCareAssessment assessment;
  final RecAudience audience;
  final bool collapsible;

  /// Each pillar's card styling plus the one line that says why the
  /// pillar matters — the framework in words a CHPS team can use.
  static ({Color colour, Color bg, IconData icon, String why}) _styleOf(
    NurturingCarePillar pillar,
  ) => switch (pillar) {
    NurturingCarePillar.goodHealth => (
      colour: AppColors.triageGreen,
      bg: AppColors.triageGreenBg,
      icon: Icons.favorite_outline,
      why:
          'A treated illness, a kept appointment and a growing body are '
          'the ground the brain builds on.',
    ),
    NurturingCarePillar.adequateNutrition => (
      colour: AppColors.triageAmber,
      bg: AppColors.triageAmberBg,
      icon: Icons.restaurant_outlined,
      why:
          'What the mother and child eat in these days is building '
          'brain and body — every meal counts.',
    ),
    NurturingCarePillar.responsiveCaregiving => (
      colour: AppColors.primary,
      bg: AppColors.primaryLight,
      icon: Icons.record_voice_over_outlined,
      why:
          'Serve and return: answer the child when they call, and '
          'every answer lays down brain wiring.',
    ),
    NurturingCarePillar.earlyLearning => (
      colour: AppColors.offline,
      bg: AppColors.offlineBg,
      icon: Icons.toys_outlined,
      why:
          'Talking, singing and playing are the child\u2019s school — '
          'they need no money and no toys.',
    ),
    NurturingCarePillar.securityAndSafety => (
      colour: AppColors.primaryDeep,
      bg: AppColors.surfaceTint,
      icon: Icons.shield_outlined,
      why:
          'A safe home, clean water and protection from harm let the '
          'brain grow without fear.',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in NurturingCarePillar.values)
          if (assessment.actions.any((a) => a.pillar == p))
            _PillarCard(
              pillar: p,
              style: _styleOf(p),
              summary: assessment.pillarSummaries[p] ?? '',
              actions: assessment.actions
                  .where((a) => a.pillar == p)
                  .toList(growable: false),
              audience: audience,
            ),
        if (audience == RecAudience.healthWorker) ...[
          const SizedBox(height: Gap.sm),
          // Citation footer — the audit-defensible anchor.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.menu_book_outlined,
                size: 12,
                color: AppColors.inkMuted,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Framework: WHO / UNICEF / World Bank 2018, Nurturing '
                  'care for early childhood development. CC BY-NC-SA 3.0 '
                  'IGO. Each action cites a WHO/UNICEF/GHS implementing '
                  'guideline.',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppColors.inkMuted,
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );

    final title = 'Nurturing care for early development';
    final subtitle = audience == RecAudience.caregiver
        ? 'Five everyday things that help a young child grow strong.'
        : 'WHO / UNICEF / World Bank 2018 Nurturing Care Framework — '
              'five pillars, each with its job for this visit.';

    if (collapsible) {
      return CollapsibleRecSection(
        title: title,
        subtitle: subtitle,
        icon: Icons.child_care_rounded,
        child: content,
      );
    }
    return RecSection(
      title: title,
      subtitle: subtitle,
      icon: Icons.child_care_rounded,
      child: content,
    );
  }
}

/// One pillar as a card: its colour, its one-line "why it matters", the
/// engine's summary for this visit, and the actions underneath.
class _PillarCard extends StatelessWidget {
  const _PillarCard({
    required this.pillar,
    required this.style,
    required this.summary,
    required this.actions,
    required this.audience,
  });

  final NurturingCarePillar pillar;
  final ({Color colour, Color bg, IconData icon, String why}) style;
  final String summary;
  final List<NurturingCareAction> actions;
  final RecAudience audience;

  @override
  Widget build(BuildContext context) => KitCard(
    accent: style.colour,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: style.bg,
                borderRadius: BorderRadius.circular(Gap.radiusXs),
              ),
              child: Icon(style.icon, size: 18, color: style.colour),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pillar.displayName.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.7,
                      color: style.colour,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    style.why,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.inkMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (summary.isNotEmpty) ...[
          const SizedBox(height: Gap.sm),
          Text(
            summary,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: Gap.sm),
        const Divider(height: 1, thickness: 1, color: AppColors.line),
        const SizedBox(height: Gap.sm),
        for (var i = 0; i < actions.length; i++) ...[
          _NurturingCareActionTile(action: actions[i], audience: audience),
          if (i < actions.length - 1) const SizedBox(height: Gap.sm),
        ],
      ],
    ),
  );
}

/// One action tile within a pillar.
class _NurturingCareActionTile extends StatelessWidget {
  const _NurturingCareActionTile({
    required this.action,
    this.audience = RecAudience.healthWorker,
  });

  final NurturingCareAction action;
  final RecAudience audience;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Checkmark or hollow circle: delivered or pending.
        Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.only(top: 1),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: action.deliveredAtVisit
                ? AppColors.triageGreen
                : Colors.transparent,
            border: Border.all(
              color: action.deliveredAtVisit
                  ? AppColors.triageGreen
                  : AppColors.inkMuted,
              width: 1.5,
            ),
          ),
          child: action.deliveredAtVisit
              ? const Icon(Icons.check, size: 12, color: Colors.white)
              : null,
        ),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                action.title,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                action.counsellingNote,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.ink,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  if (action.deliveredAtVisit)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: AppColors.triageGreenBg,
                        borderRadius: BorderRadius.circular(Gap.radiusSm),
                      ),
                      child: const Text(
                        'DELIVERED',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: AppColors.triageGreen,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  if (action.referToService)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: AppColors.triageAmberBg,
                        borderRadius: BorderRadius.circular(Gap.radiusSm),
                      ),
                      child: const Text(
                        'REFER',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: AppColors.triageAmber,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  // Citations are for the health worker's audit trail;
                  // the caregiver sees only the plain-language note.
                  if (audience == RecAudience.healthWorker)
                    Flexible(
                      child: Text(
                        action.citation.shortName,
                        style: const TextStyle(
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                          color: AppColors.inkMuted,
                          height: 1.3,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------- Family care plan card

/// The caregiver-facing rendering of a persisted [CarePlan] — the same
/// synthesized plan the health worker saw on the result screen, translated
/// for a family: verdict pill, plain-language message (spoken aloud on
/// demand), the danger signs to watch for, and a tick-off worklist with
/// no guideline citations.
class FamilyCarePlanCard extends StatelessWidget {
  const FamilyCarePlanCard({
    super.key,
    required this.plan,
    required this.personName,
    required this.language,
  });

  final CarePlan plan;
  final String personName;

  /// The caregiver's chosen guidance language, passed to [AudioButton].
  final String language;

  Color get _colour => switch (plan.overallTriage) {
    TriageLevel.urgent => AppColors.triageRed,
    TriageLevel.priority || TriageLevel.watch => AppColors.triageAmber,
    TriageLevel.routine => AppColors.triageGreen,
  };

  Color get _colourBg => switch (plan.overallTriage) {
    TriageLevel.urgent => AppColors.triageRedBg,
    TriageLevel.priority || TriageLevel.watch => AppColors.triageAmberBg,
    TriageLevel.routine => AppColors.triageGreenBg,
  };

  @override
  Widget build(BuildContext context) {
    final message = plan.caregiverMessage ?? plan.summary;
    final colour = _colour;
    // In Dagbani the family message is heard as the triage level's family
    // sentence — the actionable content — from the on-device voice bank.
    final levelClip = DagbaniSpeech.levelClip(plan.overallTriage.name);

    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(Gap.radius),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: who this plan is for, and how urgent it is.
          Row(
            children: [
              Expanded(
                child: Text(
                  personName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.sm,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _colourBg,
                  borderRadius: BorderRadius.circular(Gap.radiusSm),
                ),
                child: Text(
                  plan.overallTriage.label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    color: colour,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          if (plan.classifications.isNotEmpty) ...[
            const SizedBox(height: Gap.xs),
            Text(
              plan.classifications.join(' \u00b7 '),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.inkMuted,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: Gap.md),
          // The message the family should carry home — with a voice
          // button, because this is the card a grandmother may need read
          // aloud.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(width: Gap.sm),
              AudioButton(
                compact: true,
                text: message,
                language: language,
                id: 'plan_family_brief',
                dagbaniClips: levelClip == null ? null : [levelClip.id],
                dagbaniScript: levelClip?.dagbani,
              ),
            ],
          ),
          if (plan.dangerSigns.isNotEmpty) ...[
            const SizedBox(height: Gap.md),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.triageRedBg,
                borderRadius: BorderRadius.circular(Gap.radiusSm),
              ),
              child: AccentEdge(
                accent: AppColors.triageRed,
                borderRadius: BorderRadius.circular(Gap.radiusSm),
                child: Padding(
                  padding: const EdgeInsets.all(Gap.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'GO TO THE CLINIC IF YOU SEE:',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.triageRed,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final d in plan.dangerSigns)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Text(
                            '\u2022 $d',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                              height: 1.4,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (plan.actions.isNotEmpty) ...[
            const RecHairline(),
            ActionWorklist(
              actions: plan.actions,
              audience: RecAudience.caregiver,
            ),
          ],
          if (plan.followUpInDays != null) ...[
            const SizedBox(height: Gap.sm),
            Text(
              'The health worker asked to see $personName again in '
              '${plan.followUpInDays} day${plan.followUpInDays == 1 ? '' : 's'}.',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
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
