import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/glass.dart';
import '../../../domain/entities/core.dart';
import '../../../domain/entities/caregiver.dart';
import '../../../domain/enums.dart';
import '../../shared/app_image.dart';
import '../caregiver_providers.dart';

abstract final class CompanionColors {
  static const canvas = CaregiverLuxePalette.celestialCanvas;
  static const blue = CaregiverLuxePalette.azurePrimary;
  static const ink = CaregiverLuxePalette.twilightMidnight;
  static const bronze = AppColors.caregiverWarm;
  static const muted = CaregiverLuxePalette.twilightMuted;
  static const accent = CaregiverLuxePalette.azurePrimary;
  static const surface = CaregiverLuxePalette.pearlSurface;
}

String caregiverWhen(DateTime time) =>
    DateFormat('d MMM y, h:mm a').format(time.toLocal());
String caregiverDateLabel(DateTime day) =>
    DateFormat('d MMMM y').format(day.toLocal());
String caregiverAge(Person person) =>
    '${person.ageLabel}${person.isDobEstimated ? ' (estimated)' : ''}';

/// The caregiver body voice. The theme's default is the app-wide warm ink at
/// 1.6 leading; on these blue-tinted cards that reads green and floats apart,
/// so caregiver surfaces set their own: cool navy, 15px, 1.5 leading.
TextStyle caregiverBody({Color? color, double? size, double? height}) =>
    AppType.body.copyWith(
      fontSize: size ?? 15,
      height: height ?? 1.5,
      color: color ?? CompanionColors.ink,
    );

class CompanionCard extends StatelessWidget {
  const CompanionCard({
    super.key,
    required this.title,
    required this.child,
    this.eyebrow,
    this.tone,
  });
  final String title;
  final String? eyebrow;
  final Widget child;
  final Color? tone;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: GlassSurface(
      blur: false,
      tier: GlassTier.card,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (eyebrow != null) ...[
            Text(
              eyebrow!,
              style: AppType.eyebrow.copyWith(
                fontSize: 11,
                letterSpacing: 1.1,
                height: 1.2,
                color: CompanionColors.accent,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Sora',
              fontWeight: FontWeight.w700,
              fontSize: 20,
              height: 1.25,
              letterSpacing: -0.2,
              color: tone ?? CompanionColors.ink,
            ),
          ),
          const SizedBox(height: 12),
          DefaultTextStyle.merge(style: caregiverBody(), child: child),
        ],
      ),
    ),
  );
}

/// A member's face in the navy ring the family hub already uses, so the same
/// person reads the same everywhere. Types with no artwork fall back to the
/// neutral glyph rather than showing the wrong face.
class CaregiverPortraitOrb extends StatelessWidget {
  const CaregiverPortraitOrb({
    super.key,
    required this.person,
    this.size = 56,
  });
  final Person person;
  final double size;
  @override
  Widget build(BuildContext context) {
    final image = switch (person.clientType) {
      ClientType.newborn => AppImages.cardNewborn,
      ClientType.childUnderFive => AppImages.cardChild,
      ClientType.pregnantWoman ||
      ClientType.postpartumWoman => AppImages.cardMother,
      ClientType.womanOfReproductiveAge => AppImages.cardWoman,
    };
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size / 12),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: CaregiverLuxePalette.pearlSurface,
        border: Border.all(
          color: CaregiverLuxePalette.azurePrimary.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: ClipOval(
        child: Image.asset(
          image,
          fit: BoxFit.cover,
          semanticLabel: person.fullName,
        ),
      ),
    );
  }
}

class CaregiverPriorityBadge extends StatelessWidget {
  const CaregiverPriorityBadge({
    super.key,
    required this.label,
    required this.color,
  });
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 0.3,
      ),
    ),
  );
}

class CompanionTheme extends StatelessWidget {
  const CompanionTheme({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return VisualEffectsScope(
      child: Theme(
        data: base.copyWith(
          scaffoldBackgroundColor: CompanionColors.canvas,
          textTheme: base.textTheme.apply(
            bodyColor: CompanionColors.ink,
            displayColor: CompanionColors.ink,
          ),
          colorScheme: base.colorScheme.copyWith(
            primary: CompanionColors.blue,
            onPrimary: Colors.white,
            surface: CompanionColors.surface,
            onSurface: CompanionColors.ink,
            onSurfaceVariant: CompanionColors.muted,
            outline: CaregiverLuxePalette.hairLineQuiet,
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 56),
              padding: const EdgeInsets.all(16),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.all(12),
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary, width: 1.4),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: AppColors.primary,
            ),
          ),
          iconButtonTheme: IconButtonThemeData(
            style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
          ),
        ),
        child: child,
      ),
    );
  }
}

class CompanionPage extends ConsumerStatefulWidget {
  const CompanionPage({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.heroChrome = true,
  });
  final String title;
  final Widget child;
  final List<Widget>? actions;

  /// The caregiver gradient bar. Screens that already open with their own
  /// navy hero pass false so two blue bands never stack.
  final bool heroChrome;
  @override
  ConsumerState<CompanionPage> createState() => _CompanionPageState();
}

class _CompanionPageState extends ConsumerState<CompanionPage> {
  CaregiverScope? _owner;
  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(caregiverScopeProvider);
    _owner ??= scope;
    final hero = widget.heroChrome;
    return CompanionTheme(
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 56 + MediaQuery.textScalerOf(context).scale(16),
          // The bar and the page are one ground: the caregiver body is cool
          // blue, so a warm ivory bar above it reads as a different app.
          backgroundColor: hero
              ? Colors.transparent
              : AppColors.caregiverCanvas,
          foregroundColor: hero ? Colors.white : CompanionColors.ink,
          elevation: 0,
          scrolledUnderElevation: 0,
          flexibleSpace: hero
              ? const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppColors.caregiverGradient,
                  ),
                  child: SizedBox.expand(),
                )
              : null,
          title: Text(
            widget.title,
            style: TextStyle(
              fontFamily: 'Sora',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: hero ? Colors.white : CompanionColors.ink,
            ),
          ),
          actions: widget.actions ?? [const CaregiverEmergencyButton()],
        ),
        body: scope == null || scope != _owner
            ? const Center(
                child: Text('Your account changed. Reopen your family.'),
              )
            : DefaultTextStyle.merge(
                style: caregiverBody(),
                child: widget.child,
              ),
      ),
    );
  }
}

class CaregiverEmergencyButton extends StatelessWidget {
  const CaregiverEmergencyButton({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    // A white safety chip: the red emergency mark stays legible on both the
    // gradient bar and the plain one, and red keeps meaning "danger" only.
    child: IconButton(
      tooltip: 'Emergency help',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFFAA2929),
        side: const BorderSide(color: Color(0x1A0B1B33)),
        shape: const CircleBorder(),
      ),
      icon: const Icon(Icons.emergency_outlined, size: 22),
      onPressed: () => showCaregiverEmergency(context),
    ),
  );
}

Future<void> showCaregiverEmergency(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Emergency help'),
    content: const SingleChildScrollView(
      child: Text(
        'If the person is very unwell or has a danger sign, go to the nearest health facility now. Do not wait for a check, a saved report, or documents.\n\nCall 112 for emergency help. Calling needs a supported phone and cellular coverage. This app does not dispatch help. If calling fails, ask someone nearby to help you reach a facility.',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      FilledButton(
        onPressed: () => caregiverDial(context, '112'),
        child: const Text('Call 112'),
      ),
    ],
  ),
);

Future<void> caregiverDial(BuildContext context, String number) async {
  final safe = number.replaceAll(RegExp(r'[^0-9+]'), '');
  bool opened = false;
  try {
    if (safe.isNotEmpty) {
      opened = await launchUrl(Uri(scheme: 'tel', path: safe));
    }
  } catch (_) {
    /* Show the number below. */
  }
  if (!context.mounted || opened) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Could not open calling. Dial $number on a phone with cellular coverage.',
      ),
    ),
  );
}

/// Controlled, durable operation: no optimistic checkmark or success claim.
class CaregiverSaveAction extends StatefulWidget {
  const CaregiverSaveAction({
    super.key,
    required this.label,
    required this.onSave,
    this.icon,
    this.primary = false,
  });
  final String label;
  final Future<void> Function() onSave;
  final IconData? icon;
  final bool primary;
  @override
  State<CaregiverSaveAction> createState() => _CaregiverSaveActionState();
}

class _CaregiverSaveActionState extends State<CaregiverSaveAction> {
  bool _saving = false;
  bool _failed = false;
  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.onSave();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _saving
        ? 'Saving…'
        : _failed
        ? 'Could not save — Retry'
        : widget.label;
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(48, widget.primary ? 56 : 48)),
    );
    return widget.primary
        ? FilledButton(
            onPressed: _saving ? null : _save,
            style: style,
            child: Text(label, textAlign: TextAlign.center),
          )
        : OutlinedButton.icon(
            onPressed: _saving ? null : _save,
            style: style,
            icon: Icon(widget.icon ?? Icons.check_rounded),
            label: Text(label, textAlign: TextAlign.center),
          );
  }
}

/// One line of a caregiver checklist.
///
/// The tick is decided by the write, never by the tap: the marker changes only
/// once storage confirms, so a ticked box is evidence she can show the nurse
/// rather than a wish. While the write is in flight the line says so, and a
/// failed write keeps the tap available as the retry — nothing is disabled and
/// nothing is claimed.
///
/// [step] turns the line into a sequence: a number inside the marker until it
/// is done, and the thread that runs from one marker to the next. Without it
/// the line is a plain box, which is what a shopping list wants to be.
class CaregiverTaskToggle extends ConsumerStatefulWidget {
  const CaregiverTaskToggle({
    super.key,
    required this.personId,
    required this.kind,
    required this.sourceId,
    required this.itemKey,
    required this.occurrenceKey,
    required this.label,
    this.step,
    this.totalSteps,
    this.tone,
    this.light = false,
  });
  final String? personId;
  final CaregiverActivityKind kind;
  final String sourceId;
  final String itemKey;
  final String occurrenceKey;
  final String label;
  final int? step;
  final int? totalSteps;

  /// Colour of the thread and the pending ring — the verdict's own colour, so
  /// the plan reads as part of the answer it came from.
  final Color? tone;

  /// The line sits on a navy card instead of a white one: labels, notes and
  /// marker numbers switch to light ink so they stay legible.
  final bool light;

  @override
  ConsumerState<CaregiverTaskToggle> createState() =>
      _CaregiverTaskToggleState();
}

class _CaregiverTaskToggleState extends ConsumerState<CaregiverTaskToggle> {
  bool _busy = false;
  bool _failed = false;

  Future<void> _write(CaregiverWriter writer, {required bool done}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await writer.activity(
        writer.entry(
          kind: widget.kind,
          personId: widget.personId,
          sourceId: widget.sourceId,
          itemKey: widget.itemKey,
          occurrenceKey: widget.occurrenceKey,
          done: done,
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(caregiverScopeProvider);
    if (scope == null) return const SizedBox.shrink();
    // Watched, not read: the writer is auto-disposed, and a queue that dies
    // mid-write never tells the list the saved state changed.
    final writer = ref.watch(caregiverWriterProvider(scope));
    final activity = ref.watch(caregiverActivityProvider(scope));
    return activity.when(
      loading: () => _line(note: 'Reading what you saved\u2026', onTap: null),
      error: (_, _) => _line(
        note: 'Saved state unavailable \u2014 tap to try again',
        failed: true,
        onTap: () => ref.invalidate(caregiverActivityProvider(scope)),
      ),
      data: (entries) {
        final done = entries.any(
          (a) =>
              a.personId == widget.personId &&
              a.kind == widget.kind &&
              a.sourceId == widget.sourceId &&
              a.itemKey == widget.itemKey &&
              a.occurrenceKey == widget.occurrenceKey &&
              a.done,
        );
        return _line(
          done: done,
          busy: _busy,
          failed: _failed,
          note: _failed
              ? 'Could not save \u2014 tap to try again'
              : _busy
              ? 'Saving\u2026'
              : null,
          onTap: () => _write(writer, done: !done),
        );
      },
    );
  }

  Widget _line({
    required GestureTapCallback? onTap,
    bool done = false,
    bool busy = false,
    bool failed = false,
    String? note,
  }) {
    final tone = widget.tone ?? AppColors.checkBlue;
    final step = widget.step;
    final total = widget.totalSteps ?? 0;
    final first = step == null || step <= 1;
    final last = step == null || step >= total;
    final light = widget.light;
    return Semantics(
      button: true,
      checked: done,
      label: '${done ? 'Done' : 'Not done yet'}: ${widget.label}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 6, 0),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 34,
                    child: Column(
                      children: [
                        if (first)
                          const Spacer()
                        else
                          Expanded(
                            child: _Thread(tone: tone, complete: done),
                          ),
                        _StepMarker(
                          step: step,
                          done: done,
                          busy: busy,
                          failed: failed,
                          tone: tone,
                          light: light,
                        ),
                        if (last)
                          const Spacer()
                        else
                          Expanded(
                            child: _Thread(tone: tone, complete: done),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  widget.label,
                                  style:
                                      caregiverBody(
                                        size: 15,
                                        height: 1.4,
                                        color: done
                                            ? light
                                                  ? AppColors.white60
                                                  : AppColors.caregiverFaded
                                            : light
                                            ? AppColors.white85
                                            : CompanionColors.ink,
                                      ).copyWith(
                                        fontWeight: done
                                            ? FontWeight.w500
                                            : FontWeight.w600,
                                      ),
                                ),
                              ),
                              if (done) ...[
                                const SizedBox(width: 8),
                                _DoneChip(light: light),
                              ],
                            ],
                          ),
                          if (note != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              note,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                                letterSpacing: 0.1,
                                color: failed
                                    ? light
                                          ? const Color(0xFFFF8A80)
                                          : AppColors.triageRed
                                    : light
                                    ? AppColors.white60
                                    : AppColors.caregiverFaded,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The 2px line between two markers. It is the spine of the whole plan: quiet
/// ahead of her, solid once the step behind it is confirmed, so the path she
/// has walked fills in as she walks it.
class _Thread extends StatelessWidget {
  const _Thread({required this.tone, required this.complete});
  final Color tone;
  final bool complete;
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 2.5,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: complete
              ? [tone.withValues(alpha: 0.55), tone.withValues(alpha: 0.85)]
              : [
                  tone.withValues(alpha: 0.16),
                  tone.withValues(alpha: 0.36),
                  tone.withValues(alpha: 0.16),
                ],
          stops: complete ? const [0, 1] : const [0, 0.5, 1],
        ),
      ),
    ),
  );
}

class _StepMarker extends StatelessWidget {
  const _StepMarker({
    required this.step,
    required this.done,
    required this.busy,
    required this.failed,
    required this.tone,
    this.light = false,
  });
  final int? step;
  final bool done;
  final bool busy;
  final bool failed;
  final Color tone;
  final bool light;

  @override
  Widget build(BuildContext context) {
    if (done) {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.checkBlueLight, AppColors.checkBlue],
          ),
          boxShadow: [
            BoxShadow(
              color: tone.withValues(alpha: 0.32),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.check_rounded, size: 19, color: Colors.white),
      );
    }
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: light ? Colors.white.withValues(alpha: 0.08) : Colors.white,
        border: Border.all(
          color: failed
              ? (light ? const Color(0xFFFF8A80) : AppColors.triageRed)
              : light
              ? Colors.white.withValues(alpha: 0.45)
              : tone.withValues(alpha: 0.42),
          width: 2,
        ),
      ),
      child: busy
          ? SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: light ? Colors.white : tone,
              ),
            )
          : failed
          ? Icon(
              Icons.priority_high_rounded,
              size: 16,
              color: light ? const Color(0xFFFF8A80) : AppColors.triageRed,
            )
          : step == null
          ? null
          : Text(
              '$step',
              style: TextStyle(
                fontFamily: 'Sora',
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: light ? Colors.white : AppColors.checkNavy,
              ),
            ),
    );
  }
}

class _DoneChip extends StatelessWidget {
  const _DoneChip({this.light = false});
  final bool light;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: light
          ? Colors.white.withValues(alpha: 0.12)
          : AppColors.checkBlueTint,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: light
            ? Colors.white.withValues(alpha: 0.16)
            : AppColors.checkBlue.withValues(alpha: 0.16),
      ),
    ),
    child: Text(
      'Done',
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
        color: light ? AppColors.white85 : AppColors.checkBlue,
      ),
    ),
  );
}

class CompanionLoadError extends StatelessWidget {
  const CompanionLoadError({
    super.key,
    required this.onRetry,
    this.message = 'Could not read saved data. Nothing was assumed complete.',
  });
  final VoidCallback onRetry;
  final String message;
  @override
  Widget build(BuildContext context) => CompanionCard(
    title: 'Could not load',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(message),
        OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

class CaregiverPersonSelector extends ConsumerWidget {
  const CaregiverPersonSelector({super.key, required this.members});
  final List<Person> members;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(caregiverScopeProvider);
    if (scope == null) return const SizedBox.shrink();
    final writer = ref.watch(caregiverWriterProvider(scope));
    return ref
        .watch(caregiverSettingsProvider(scope))
        .when(
          loading: () => const Text('Loading your family selection…'),
          error: (_, _) => CaregiverSaveAction(
            label: 'Retry family selection',
            onSave: () async {
              ref.invalidate(caregiverSettingsProvider(scope));
              await ref.read(caregiverSettingsProvider(scope).future);
            },
          ),
          data: (settings) {
            final selected = members
                .where((p) => p.id == settings.selectedPersonId)
                .firstOrNull;
            return CompanionCard(
              title: selected?.fullName ?? 'All family',
              eyebrow: 'CARING FOR',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (selected != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          CaregiverPortraitOrb(person: selected, size: 52),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(caregiverAge(selected)),
                                Text(
                                  selected.clientType.label,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: CompanionColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.people_outline),
                    label: const Text('Choose family member'),
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (context) => SafeArea(
                        child: ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.all(20),
                          children: [
                            CaregiverSaveAction(
                              label: 'All family',
                              onSave: () async {
                                await writer.settings(
                                  (s) => s.copyWith(allFamily: true),
                                );
                                if (context.mounted) Navigator.pop(context);
                              },
                            ),
                            for (final p in members)
                              CaregiverSaveAction(
                                label: '${p.fullName} • ${caregiverAge(p)}',
                                onSave: () async {
                                  await writer.settings(
                                    (s) => s.copyWith(selectedPersonId: p.id),
                                  );
                                  if (context.mounted) Navigator.pop(context);
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
  }
}
